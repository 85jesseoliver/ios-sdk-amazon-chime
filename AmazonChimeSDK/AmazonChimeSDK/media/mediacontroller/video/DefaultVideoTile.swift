//
//  DefaultVideoTile.swift
//  AmazonChimeSDK
//
//  Copyright 2020 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//

import Foundation

public class DefaultVideoTile: VideoTile {
    private let logger: Logger

    public let tileId: Int
    public let attendeeId: String?
    public var videoRenderView: VideoRenderView?
    public var paused = false

    init(logger: Logger, tileId: Int, attendeeId: String?) {
        self.tileId = tileId
        self.attendeeId = attendeeId
        self.logger = logger
    }

    // TODO: figure out what todo with this bind if builder decide to call this directly
    public func bind(videoRenderView: VideoRenderView?) {
        logger.info(msg: "Binding the view to tile: tileId: \(tileId), attendeeId: \(attendeeId ?? "self")")
        self.videoRenderView = videoRenderView
    }

    public func renderFrame(frame: Any?) {
        videoRenderView?.renderFrame(frame: frame)
    }

    public func unbind() {
        logger.info(msg: "Unbinding the view from tile: tileId:  \(tileId), attendeeId: \(attendeeId ?? "self")")
        videoRenderView = nil
    }

    public func pause() {
        self.paused = true
    }

    public func unpause() {
        self.paused = false
    }
}
