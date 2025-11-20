//
//  HTTPClient.swift
//  RPAgentSwift
//
//  Created by Stas Kirichok on 20/08/18.
//  Copyright © 2018 Windmill. All rights reserved.
//

import Foundation

enum HTTPClientError: Error {
  case invalidURL
  case noResponse
  case httpError(statusCode: Int, body: String?)
  case decodingError(String)
  case networkError(Error)
}

final class HTTPClient: NSObject, URLSessionDelegate, @unchecked Sendable {

  private let baseURL: URL
  private let requestTimeout: TimeInterval = 120
  private let plugins: [HTTPClientPlugin]
  
  // Lazy var allows us to use 'self' as delegate after initialization
  private lazy var urlSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 300
    configuration.httpMaximumConnectionsPerHost = 6
    
    #if DEBUG
    // DEVELOPMENT ONLY: Initialize with delegate for SSL bypass (proxy testing)
    // Note: @unchecked Sendable because URLSession is not Sendable on all SDK versions
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    #else
    // RELEASE: No delegate needed
    return URLSession(configuration: configuration)
    #endif
  }()

  init(baseURL: URL, plugins: [HTTPClientPlugin] = []) {
    self.baseURL = baseURL
    self.plugins = plugins
    super.init()
  }

  // DEVELOPMENT ONLY: Bypass SSL validation for proxy testing
  #if DEBUG
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    // Accept any certificate in DEBUG builds for proxy testing
    if let serverTrust = challenge.protectionSpace.serverTrust {
      completionHandler(.useCredential, URLCredential(trust: serverTrust))
    } else {
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }
  #endif

  // MARK: - Async/Await API

  /// Call endpoint with async/await (non-blocking)
  func callEndPoint<T: Decodable>(_ endPoint: EndPoint) async throws -> T {
    let request = try buildRequest(for: endPoint)

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await urlSession.data(for: request)
    } catch {
      Logger.shared.error("Network error: \(error.localizedDescription)")
      throw HTTPClientError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.shared.error("Invalid response format: expected HTTP response")
      throw HTTPClientError.noResponse
    }

    guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
      let body = String(data: data, encoding: .utf8)
      // Truncate large response bodies to prevent log spam (max 1KB)
      let truncatedBody = truncateForLog(body ?? "no body", maxLength: 1024)
      Logger.shared.error("HTTP error \(httpResponse.statusCode): \(truncatedBody)")
      throw HTTPClientError.httpError(statusCode: httpResponse.statusCode, body: body)
    }

    // Handle 204 No Content or empty responses
    if httpResponse.statusCode == 204 || data.isEmpty {
      // For 204 or empty responses, we can't decode JSON
      // Check if T is optional or has a default value
      // For now, throw an error since ReportPortal API should always return data
      Logger.shared.error("Received 204 No Content or empty response")
      throw HTTPClientError.noResponse
    }

    do {
      let result = try JSONDecoder().decode(T.self, from: data)
      return result
    } catch {
      let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
      // Truncate large response bodies to prevent log spam (max 1KB)
      let truncatedBody = truncateForLog(responseBody, maxLength: 1024)
      Logger.shared.error("JSON decode error: \(error.localizedDescription)")
      Logger.shared.error("Raw response: \(truncatedBody)")
      throw HTTPClientError.decodingError("Failed to decode response: \(error.localizedDescription)")
    }
  }

  // MARK: - Private Helpers

  private func buildRequest(for endPoint: EndPoint) throws -> URLRequest {
    var url = baseURL.appendingPathComponent(endPoint.relativePath)

    if endPoint.encoding == .url {
      guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        Logger.shared.error("Failed to create URLComponents from URL: \(url)")
        throw HTTPClientError.invalidURL
      }
      let queryItems = endPoint.parameters.map {
        return URLQueryItem(name: "\($0)", value: "\($1)")
      }

      urlComponents.queryItems = queryItems
      guard let constructedURL = urlComponents.url else {
        Logger.shared.error("Failed to construct URL from URLComponents with query items")
        throw HTTPClientError.invalidURL
      }
      url = constructedURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = endPoint.method.rawValue
    request.cachePolicy = .reloadIgnoringCacheData
    request.allHTTPHeaderFields = endPoint.headers

    // Handle different encoding types
    switch endPoint.encoding {
    case .json:
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let data = try JSONSerialization.data(withJSONObject: endPoint.parameters, options: .prettyPrinted)
      request.httpBody = data

    case .multipartFormData:
      // Build multipart body
      let boundary = "Boundary-\(UUID().uuidString)"
      let bodyData = createMultipartBody(
        parameters: endPoint.parameters,
        attachments: endPoint.attachments,
        boundary: boundary
      )
      request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
      request.setValue(String(bodyData.count), forHTTPHeaderField: "Content-Length")
      request.httpBody = bodyData
      request.httpShouldHandleCookies = false

    case .url:
      // URL encoding handled above
      break
    }

    // Allow plugins to mutate the request
    for plugin in plugins {
      plugin.processRequest(&request)
    }

    return request
  }

  /// Build multipart body for file upload requests
  /// Each parameter and attachment gets its own part separated by the boundary
  ///
  /// - Parameters:
  ///   - parameters: Dictionary of parameters to send. Values can be `String`, `Data`, or any JSON-serialisable type.
  ///   - attachments: Array of `FileAttachment` to include in the request.
  ///   - boundary: The boundary string (WITHOUT the leading "--").
  /// - Returns: A `Data` object containing the fully-formed multipart body.
  private func createMultipartBody(parameters: [String: Any], attachments: [FileAttachment], boundary: String) -> Data {
    var body = Data()

    let lineBreak = "\r\n"

    // Helper to append string
    func append(_ string: String) {
      if let data = string.data(using: .utf8) {
        body.append(data)
      }
    }

    // 1. Append parameters (each parameter as separate multipart section)
    for (key, value) in parameters {
      append("--\(boundary)\r\n")

      if let stringValue = value as? String {
        append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
        append(stringValue)
        append(lineBreak)
      } else if JSONSerialization.isValidJSONObject(value) {
        // Handle JSON objects/arrays - critical for json_request_part
        append("Content-Disposition: form-data; name=\"\(key)\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        if let jsonData = try? JSONSerialization.data(withJSONObject: value, options: []) {
          body.append(jsonData)
        }
        append(lineBreak)
      } else if let dataValue = value as? Data {
        append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
        body.append(dataValue)
        append(lineBreak)
      } else {
        // Fallback – convert to string
        append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
        append("\(String(describing: value))")
        append(lineBreak)
      }
    }

    // 2. Append file attachments
    for attachment in attachments {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"\(attachment.fieldName)\"; filename=\"\(attachment.filename)\"\r\n")
      append("Content-Type: \(attachment.mimeType)\r\n\r\n")
      body.append(attachment.data)
      append(lineBreak)
    }

    // 3. Close the body with final boundary
    append("--\(boundary)--\r\n")

    return body
  }

  // MARK: - Logging Helpers

  /// Truncate string for logging to prevent console spam
  /// - Parameters:
  ///   - string: Original string
  ///   - maxLength: Maximum length (default 1024 bytes)
  /// - Returns: Truncated string with ellipsis if truncated
  private func truncateForLog(_ string: String, maxLength: Int = 1024) -> String {
    if string.count <= maxLength {
      return string
    }
    let truncated = String(string.prefix(maxLength))
    return "\(truncated)... (truncated, \(string.count) bytes total)"
  }
}

protocol HTTPClientPlugin: Sendable {
  func processRequest(_ originRequest: inout URLRequest)
}
