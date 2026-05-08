//
//  UploadURLResponse.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/14/25.
//
//  Represents upload URL info returned by comma API
//

import Foundation

struct UploadURLResponse: Decodable, Sendable {
    let path: String
    let url: String
    let headers: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case path
        case fn
        case url
        case headers
    }

    init(path: String, url: String, headers: [String: String]?) {
        self.path = path
        self.url = url
        self.headers = headers
    }

    init(from decoder: Decoder) throws {
        // Some responses are simple strings (legacy); treat as URL only
        if let singleValue = try? decoder.singleValueContainer().decode(String.self) {
            path = ""
            url = singleValue
            headers = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)

        if let decodedPath = try container.decodeIfPresent(String.self, forKey: .path) {
            path = decodedPath
        } else if let fn = try container.decodeIfPresent(String.self, forKey: .fn) {
            path = fn
        } else {
            path = ""
        }
    }
}
