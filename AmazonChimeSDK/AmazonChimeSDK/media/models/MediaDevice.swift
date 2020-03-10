//
//  MediaDevice.swift
//  AmazonChimeSDK
//
//  Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import AVFoundation
import Foundation

/// `MediaDevice` represents an IOS audio/video device.
@objcMembers public class MediaDevice: NSObject {
    /// Label of MediaDevice
    public let label: String

    /// Type of MediaDevice (ex: Bluetooth Audio, Front Camera)
    public let type: MediaDeviceType

    /// Audio Information based on iOS native `AVAudioSessionPortDescription`
    /// It will be null when it represent a video device.
    public let port: AVAudioSessionPortDescription?

    /// Create `MediaDevice` for audio from audio information based on iOS native `AVAudioSessionPortDescription`.
    /// - Parameter port: Audio information
    static func fromAVSessionPort(port: AVAudioSessionPortDescription) -> MediaDevice {
        return MediaDevice(label: port.portName, port: port)
    }

    /// Create `MediaDevice` for video from  `VideoDevice`.
    /// - Parameter device: Video device that contains information about device
    static func fromVideoDevice(device: VideoDevice?) -> MediaDevice {
        return MediaDevice(label: device?.name ?? "unknown", videoDevice: device)
    }

    public init(label: String, port: AVAudioSessionPortDescription? = nil, videoDevice: VideoDevice? = nil) {
        self.label = label
        self.port = port
        if let videoDevice = videoDevice {
            let nameLowercased = videoDevice.name.lowercased()
            if nameLowercased.contains("front") {
                self.type = .videoFrontCamera
            } else if nameLowercased.contains("back") {
                self.type = .videoBackCamera
            } else {
                self.type = .other
            }
        } else if let port = port {
            switch port.portType {
            case .bluetoothLE, .bluetoothHFP, .bluetoothA2DP:
                self.type = .audioBluetooth
            case .builtInReceiver, .builtInMic:
                self.type = .audioHandset
            case .headphones, .headsetMic:
                self.type = .audioWiredHeadset
            default:
                self.type = .other
            }
        } else {
            self.type = .other
        }
    }

    override public var description: String {
        return "\(self.label) - \(self.type)"
    }
}

@objc public enum MediaDeviceType: Int, CustomStringConvertible {
    case audioBluetooth
    case audioWiredHeadset
    case audioBuiltInSpeaker
    case audioHandset
    case videoFrontCamera
    case videoBackCamera
    case other

    public var description: String {
        switch self {
        case .audioBluetooth:
            return "audioBluetooth"
        case .audioWiredHeadset:
            return "audioWiredHeadset"
        case .audioBuiltInSpeaker:
            return "audioBuiltInSpeaker"
        case .audioHandset:
            return "audioHandset"
        case .videoFrontCamera:
            return "videoFrontCamera"
        case .videoBackCamera:
            return "videoBackCamera"
        case .other:
            return "other"
        }
    }
}
