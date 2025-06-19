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
      let boundary = "Boundary-\(UUID().uuidString)"
      request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
      request.httpBody = try createMultipartBody(parameters: endPoint.parameters, attachments: endPoint.attachments, boundary: boundary)
      
    case .url:
      // URL encoding handled above
      break
    }
    
    plugins.forEach { (plugin) in
      plugin.processRequest(&request)
    }
    print(request.url ?? "")
    utilityQueue.async {
      let task = self.urlSession.dataTask(with: request as URLRequest) { (data: Data?, response: URLResponse?, error: Error?) in
        if let error = error {
          print(error)
          return
        }

        guard let data = data else {
          print("no data")
          return
        }
        guard
          let httpResponse = response as? HTTPURLResponse else {
            print("response not found")
            return
        }

        do {
          let result = try JSONDecoder().decode(T.self, from: data)

          if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            completion(result)
          } else {
            print("request failed with code: \(httpResponse.statusCode)")
          }
        } catch let error {
          print("cannot deserialize data: \(String(describing: try? JSONSerialization.jsonObject(with: data, options: []) ))")
          print(error)
        }
      }
      task.resume()
    }
  }
  
  // MARK: - Multipart Form Data Helper
  private func createMultipartBody(parameters: [String: Any], attachments: [FileAttachment], boundary: String) throws -> Data {
    var body = Data()
    
    // Add JSON request part
    if let jsonRequestPart = parameters["json_request_part"] {
      let jsonData = try JSONSerialization.data(withJSONObject: jsonRequestPart, options: [])  // Remove prettyPrinted to avoid formatting issues
      
      // Debug: Print the JSON we're sending
      if let jsonString = String(data: jsonData, encoding: .utf8) {
        print("🔍 HTTPClient: JSON being sent in multipart:")
        print(jsonString)
      }
      
      body.append("--\(boundary)\r\n".data(using: .utf8)!)
      body.append("Content-Disposition: form-data; name=\"json_request_part\"\r\n".data(using: .utf8)!)
      body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
      body.append(jsonData)
      body.append("\r\n".data(using: .utf8)!)
    }
    
    // Add file attachments
    for attachment in attachments {
      body.append("--\(boundary)\r\n".data(using: .utf8)!)
      body.append("Content-Disposition: form-data; name=\"\(attachment.fieldName)\"; filename=\"\(attachment.filename)\"\r\n".data(using: .utf8)!)
      body.append("Content-Type: \(attachment.mimeType)\r\n\r\n".data(using: .utf8)!)
      body.append(attachment.data)
      body.append("\r\n".data(using: .utf8)!)
    }
    
    // Close boundary
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    
    return body
  }
}

protocol HTTPClientPlugin {
  func processRequest(_ originRequest: inout URLRequest)
}
