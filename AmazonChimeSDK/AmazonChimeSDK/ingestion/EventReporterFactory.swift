//
//  EventReporterFactory.swift
//  AmazonChimeSDK
//
//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

@objc public protocol EventReporterFactory {
    func createEventReporter() -> EventReporter?
}
