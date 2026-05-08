//
//  UserProfile.swift
//  connect-ios
//
//  Created by Will Killebrew on 11/11/25.
//
//  Data model for user profile
//

import Foundation

struct UserProfile: Codable, Sendable {
    var id: String
    var email: String?
    var username: String?
    var superuser: Bool
    var prime: Bool?
    var userId: String?
    var regdate: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case superuser
        case prime
        case userId = "user_id"
        case regdate
    }

    init(
        id: String,
        email: String? = nil,
        username: String? = nil,
        superuser: Bool = false,
        prime: Bool? = nil,
        userId: String? = nil,
        regdate: Int? = nil
    ) {
        self.id = id
        self.email = email
        self.username = username
        self.superuser = superuser
        self.prime = prime
        self.userId = userId
        self.regdate = regdate
    }
}
