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

class HTTPClient {

  private let baseURL: URL
  private let requestTimeout: TimeInterval = 120
  private let utilityQueue = DispatchQueue(label: "com.report_portal_agent.httpclient", qos: .utility)
  private var plugins: [HTTPClientPlugin] = []

  init(baseURL: URL) {
    self.baseURL = baseURL

    URLSession.shared.configuration.timeoutIntervalForRequest = requestTimeout
  }

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
    if endPoint.encoding == .json {
      let data = try JSONSerialization.data(withJSONObject: endPoint.parameters, options: .prettyPrinted)
      request.httpBody = data
    }
    plugins.forEach { (plugin) in
      plugin.processRequest(&request)
    }
    print(request.url ?? "")
    utilityQueue.async {
      let task = URLSession.shared.dataTask(with: request as URLRequest) { (data: Data?, response: URLResponse?, error: Error?) in
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
}

protocol HTTPClientPlugin {
  func processRequest(_ originRequest: inout URLRequest)
}
