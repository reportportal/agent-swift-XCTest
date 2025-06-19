//
//  HTTPClient.swift
//
//  Created by Stas Kirichok on 20/08/18.
//  Copyright © 2018 Windmill. All rights reserved.
//

import Foundation

enum HTTPClientError: Error {
  case invalidURL
  case noResponse
}

class HTTPClient: NSObject, URLSessionDelegate {

  private let baseURL: URL
  private let requestTimeout: TimeInterval = 120
  private let utilityQueue = DispatchQueue(label: "com.report_portal_agent.httpclient", qos: .utility)
  private var plugins: [HTTPClientPlugin] = []
  private lazy var urlSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = requestTimeout
    
    #if DEBUG
    // DEVELOPMENT ONLY: Allow proxy certificates for testing
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    #else
    return URLSession(configuration: configuration)
    #endif
  }()

  override init() {
    self.baseURL = URL(string: "https://example.com")! // Will be overridden
    super.init()
  }
  
  init(baseURL: URL) {
    self.baseURL = baseURL
    super.init()
  }
  
  // DEVELOPMENT ONLY: Bypass SSL validation for proxy testing
  #if DEBUG
  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    // Accept any certificate in DEBUG builds for proxy testing
    completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
  }
  #endif

  func setPlugins(_ plugins: [HTTPClientPlugin]) {
    self.plugins = plugins
  }

  func callEndPoint<T: Decodable>(_ endPoint: EndPoint, completion: @escaping (_ result: T) -> Void) throws {
    var url = baseURL.appendingPathComponent(endPoint.relativePath)

    if endPoint.encoding == .url {
      var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      let queryItems = endPoint.parameters.map {
        return URLQueryItem(name: "\($0)", value: "\($1)")
      }

      urlComponents.queryItems = queryItems
      url = urlComponents.url!
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
      // Use proper multipart construction based on John Xavier's guide
      try handleProperMultipart(request: request, endPoint: endPoint, completion: completion)
      return
      
    case .url:
      // URL encoding handled above
      break
    }
    
    plugins.forEach { (plugin) in
      plugin.processRequest(&request)
    }
    
    utilityQueue.async {
      let task = self.urlSession.dataTask(with: request as URLRequest) { (data: Data?, response: URLResponse?, error: Error?) in
        self.handleResponse(data: data, response: response, error: error, completion: completion)
      }
      task.resume()
    }
  }
  
  // MARK: - Proper Multipart Construction (Stack Overflow Pattern)
  private func handleProperMultipart<T: Decodable>(request: URLRequest, endPoint: EndPoint, completion: @escaping (_ result: T) -> Void) throws {
    // Build multipart body following the style described at https://fluffy.es/upload-image-to-server/

    var mutableRequest = request

    // Generate a unique boundary
    let boundary = generateBoundary()

    // Build the multipart body with ALL parameters & attachments (can handle any number of files)
    let bodyData = createMultipartBody(
      parameters: endPoint.parameters,
      attachments: endPoint.attachments,
      boundary: boundary
    )

    // Set required headers
    mutableRequest.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
    mutableRequest.setValue(String(bodyData.count), forHTTPHeaderField: "Content-Length")

    mutableRequest.httpBody = bodyData
    mutableRequest.httpShouldHandleCookies = false

    // Allow plugins to mutate the request
    for plugin in plugins {
      plugin.processRequest(&mutableRequest)
    }

    utilityQueue.async {
      let task = self.urlSession.dataTask(with: mutableRequest) { (data: Data?, response: URLResponse?, error: Error?) in
        self.handleResponse(data: data, response: response, error: error, completion: completion)
      }
      task.resume()
    }
  }
  
  // Generate boundary following Stack Overflow pattern
  private func generateBoundary() -> String {
    return "Boundary-\(UUID().uuidString)"
  }
  
  /// and every attachment gets its own part separated by the same boundary.
  ///
  /// - Parameters:
  ///   - parameters: Dictionary of parameters to send. Values can be `String`, `Data`, or any JSON-serialisable type.
  ///   - attachments: Array of `FileAttachment` to include in the request.
  ///   - boundary: The boundary string (WITHOUT the leading "--").
  /// - Returns: A `Data` object containing the fully-formed multipart body.
  private func createMultipartBody(parameters: [String: Any], attachments: [FileAttachment], boundary: String) -> Data {
    var body = Data()

    let lineBreak = "\r\n"

    body.append("\r\n".data(using: .utf8)!)

    // Helper to append string
    func append(_ string: String) {
      if let data = string.data(using: .utf8) {
        body.append(data)
      }
    }

    // 1. Append parameters
    for (key, value) in parameters {
      append("--\(boundary)\r\n")

      if let stringValue = value as? String {
        append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
        append(stringValue)
        append(lineBreak)
      } else if JSONSerialization.isValidJSONObject(value) {
        // Treat any collection value as JSON
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

    // 3. Close the body
    append("--\(boundary)--\r\n")

    return body
  }
  
  // MARK: - Shared Response Handling
  private func handleResponse<T: Decodable>(data: Data?, response: URLResponse?, error: Error?, completion: @escaping (_ result: T) -> Void) {
    
    if let error = error {
      print("🚨 HTTPClient Network Error: Request failed due to network connectivity or timeout issues. Details: \(error.localizedDescription). Check your internet connection and server availability.")
      return
    }
    
    guard let data = data else {
      print("🚨 HTTPClient Data Error: Server responded but no data was received. This could indicate a server-side issue or incomplete response.")
      return
    }
    
    guard let httpResponse = response as? HTTPURLResponse else {
      print("🚨 HTTPClient Response Error: Invalid response format received from server. Expected HTTP response but got: \(String(describing: response))")
      return
    }

    do {
      if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
        let result = try JSONDecoder().decode(T.self, from: data)
        completion(result)
      } else {
        let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
        print("🚨 HTTPClient HTTP Error: Server returned status code \(httpResponse.statusCode). This indicates a server-side error or invalid request.")
        print("   📄 Response details: \(responseBody)")
        print("   🔗 Request URL: \(httpResponse.url?.absoluteString ?? "Unknown")")
      }
    } catch let error {
      let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
      print("🚨 HTTPClient JSON Decode Error: Failed to parse server response as expected format.")
      print("   🔍 Decode error: \(error.localizedDescription)")
      print("   📄 Raw response: \(responseBody)")
      print("   💡 This usually means the server returned a different JSON structure than expected.")
    }
  }
}

// MARK: - NSMutableData Extension
extension NSMutableData {
  func appendString(_ string: String) {
    if let data = string.data(using: .utf8) {
      self.append(data)
    }
  }
}

protocol HTTPClientPlugin {
  func processRequest(_ originRequest: inout URLRequest)
}
