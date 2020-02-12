//
//  AttendeeInfoResponse.swift
//  AmazonChimeSDKDemo
//
//  Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import Foundation

struct AttendeeIdName: Codable {
    var attendeeId: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case attendeeId = "AttendeeId"
        case name = "Name"
    }
}

struct AttendeeInfoResponse: Codable {
    var attendeeInfo: AttendeeIdName

    enum CodingKeys: String, CodingKey {
        case attendeeInfo = "AttendeeInfo"
    }
}
