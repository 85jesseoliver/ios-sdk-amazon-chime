//
//  DefaultAudioClientObserver.swift
//  AmazonChimeSDK
//
//  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//  SPDX-License-Identifier: Apache-2.0
//

import AmazonChimeSDKMedia
import Foundation

class DefaultAudioClientObserver: NSObject, AudioClientDelegate {
    private var audioClient: AudioClient
    private var audioClientStateObservers = NSMutableSet()
    private var clientMetricsCollector: ClientMetricsCollector
    private var currentAttendeeSet: Set<AttendeeInfo> = Set()
    private var currentAttendeeSignalMap = [AttendeeInfo: SignalStrength]()
    private var currentAttendeeVolumeMap = [AttendeeInfo: VolumeLevel]()
    private var currentAudioState = SessionStateControllerAction.initialize
    private var currentAudioStatus = MeetingSessionStatusCode.ok
    private var realtimeObservers = NSMutableSet()

    init(audioClient: AudioClient, clientMetricsCollector: ClientMetricsCollector) {
        self.audioClient = audioClient
        self.clientMetricsCollector = clientMetricsCollector
        super.init()
        audioClient.delegate = self
    }

    public func audioClientStateChanged(_ audioClientState: audio_client_state_t, status: audio_client_status_t) {
        let newAudioState = Converters.AudioClientState.toSessionStateControllerAction(state: audioClientState)
        let newAudioStatus = Converters.AudioClientStatus.toMeetingSessionStatusCode(status: status)

        if newAudioState == .unknown || (newAudioState == currentAudioState && newAudioStatus == currentAudioStatus) {
            return
        }

        switch newAudioState {
        case .finishConnecting:
            handleStateChangeToConnected(newAudioStatus: newAudioStatus)
        case .reconnecting:
            handleStateChangeToReconnecting()
        case .finishDisconnecting:
            handleStateChangeToDisconnected()
        case .fail:
            handleStateChangeToFail(newAudioStatus: newAudioStatus)
        default:
            break
        }

        currentAudioState = newAudioState
        currentAudioStatus = newAudioStatus
    }

    public func audioMetricsChanged(_ metrics: [AnyHashable: Any]?) {
        if metrics == nil {
            return
        }

        clientMetricsCollector.processAudioClientMetrics(metrics: metrics!)
    }

    public func signalStrengthChanged(_ signalStrengths: [Any]?) {
        guard let signalUpdate = signalStrengths as? [AttendeeUpdate] else {
            return
        }

        let newAttendeeSignalMap = signalUpdate.reduce(into: [AttendeeInfo: SignalStrength]()) {
            if !$1.externalUserId.isEmpty {
                let attendeeInfo = AttendeeInfo(attendeeId: $1.profileId, externalUserId: $1.externalUserId)
                $0[attendeeInfo] = SignalStrength(rawValue: Int(truncating: $1.data))
            }
        }

        let attendeeSignalDelta = newAttendeeSignalMap.subtracting(dict: currentAttendeeSignalMap)
        currentAttendeeSignalMap = newAttendeeSignalMap

        if !attendeeSignalDelta.isEmpty {
            let signalUpdates = attendeeSignalDelta.reduce(into: [SignalUpdate]()) {
                let signalUpdate = SignalUpdate(attendeeInfo: $1.key, signalStrength: $1.value)
                $0.append(signalUpdate)
            }
            ObserverUtils.forEach(observers: realtimeObservers) { (observer: RealtimeObserver) in
                observer.signalStrengthDidChange(signalUpdates: signalUpdates)
            }
        }
    }

    public func volumeStateChanged(_ volumes: [Any]?) {
        guard let volumesUpdate = volumes as? [AttendeeUpdate] else {
            return
        }
        let newAttendeeVolumeMap = volumesUpdate.reduce(into: [AttendeeInfo: VolumeLevel]()) {
            if !$1.externalUserId.isEmpty {
                let attendeeInfo = AttendeeInfo(attendeeId: $1.profileId, externalUserId: $1.externalUserId)
                $0[attendeeInfo] = VolumeLevel(rawValue: Int(truncating: $1.data))
            }
        }

        attendeePresenceStateChange(newAttendeeVolumeMap)
        let attendeeVolumeDelta = newAttendeeVolumeMap.subtracting(dict: currentAttendeeVolumeMap)
        attendeeMuteStateChange(attendeeVolumeDelta)
        currentAttendeeVolumeMap = newAttendeeVolumeMap
        if !attendeeVolumeDelta.isEmpty {
            let volumeUpdates = attendeeVolumeDelta.reduce(into: [VolumeUpdate]()) {
                let volumeUpdate = VolumeUpdate(attendeeInfo: $1.key, volumeLevel: $1.value)
                $0.append(volumeUpdate)
            }
            ObserverUtils.forEach(observers: realtimeObservers) { (observer: RealtimeObserver) in
                observer.volumeDidChange(volumeUpdates: volumeUpdates)
            }
        }
    }

    private func attendeeMuteStateChange(_ map: [AttendeeInfo: VolumeLevel]) {
        let attendeesMuted = map.filter { (_, value) -> Bool in
            value == .muted
        }
        if !attendeesMuted.isEmpty {
            ObserverUtils.forEach(observers: realtimeObservers) { (observer: RealtimeObserver) in
                observer.attendeesDidMute(attendeeInfo: [AttendeeInfo](attendeesMuted.keys))
            }
        }

        let attendeesUnmuted = map.filter { (key, _) -> Bool in
            currentAttendeeVolumeMap[key] == .muted
        }
        if !attendeesUnmuted.isEmpty {
            ObserverUtils.forEach(observers: realtimeObservers) { (observer: RealtimeObserver) in
                observer.attendeesDidUnmute(attendeeInfo: [AttendeeInfo](attendeesUnmuted.keys))
            }
        }
    }

    private func attendeePresenceStateChange(_ map: [AttendeeInfo: Any]) {
        let newAttendees = Set(map.keys)
        let attendeesAdded = newAttendees.subtracting(currentAttendeeSet)
        let attendeesRemoved = currentAttendeeSet.subtracting(newAttendees)

        if !attendeesAdded.isEmpty {
            ObserverUtils.forEach(observers: realtimeObservers) { (observer: RealtimeObserver) in
                observer.attendeesDidJoin(attendeeInfo: [AttendeeInfo](attendeesAdded))
            }
        }

        if !attendeesRemoved.isEmpty {
            ObserverUtils.forEach(observers: realtimeObservers) { (observer: RealtimeObserver) in
                observer.attendeesDidLeave(attendeeInfo: [AttendeeInfo](attendeesRemoved))
            }
        }
        currentAttendeeSet = newAttendees
    }

    private func handleStateChangeToConnected(newAudioStatus: MeetingSessionStatusCode) {
        switch currentAudioState {
        case .connecting:
            notifyAudioClientObserver { (observer: AudioVideoObserver) in
                observer.audioSessionDidStart(reconnecting: false)
            }
        case .reconnecting:
            notifyAudioClientObserver { (observer: AudioVideoObserver) in
                observer.audioSessionDidStart(reconnecting: true)
            }
        case .finishConnecting:
            switch (newAudioStatus, currentAudioStatus) {
            case (.ok, .networkBecomePoor):
                notifyAudioClientObserver { (observer: AudioVideoObserver) in
                    observer.connectionDidRecover()
                }
            case (.networkBecomePoor, .ok):
                notifyAudioClientObserver { (observer: AudioVideoObserver) in
                    observer.connectionDidBecomePoor()
                }
            default:
                break
            }
        default:
            break
        }
    }

    private func handleStateChangeToDisconnected() {
        switch currentAudioState {
        case .connecting,
             .finishConnecting:
            // No-op, already handled in DefaultAudioClientController.stop()
            break
        case .reconnecting:
            notifyAudioClientObserver { (observer: AudioVideoObserver) in
                observer.audioSessionDidCancelReconnect()
            }
        default:
            break
        }
    }

    private func handleStateChangeToFail(newAudioStatus: MeetingSessionStatusCode) {
        switch currentAudioState {
        case .connecting, .finishConnecting:
            handleAudioSessionDidFail(newAudioStatus: newAudioStatus)
        case .reconnecting:
            notifyAudioClientObserver { (observer: AudioVideoObserver) in
                observer.audioSessionDidCancelReconnect()
            }
            handleAudioSessionDidFail(newAudioStatus: newAudioStatus)
        default:
            break
        }
    }

    private func handleStateChangeToReconnecting() {
        if currentAudioState == .finishConnecting {
            notifyAudioClientObserver { (observer: AudioVideoObserver) in
                observer.audioSessionDidDrop()
            }
        }
    }

    private func handleAudioSessionDidFail(newAudioStatus: MeetingSessionStatusCode) {
        if DefaultAudioClientController.state != .started {
            return
        }

        DispatchQueue.global().async {
            self.audioClient.stopSession()
            DefaultAudioClientController.state = .stopped
            self.notifyAudioClientObserver { (observer: AudioVideoObserver) in
                observer.audioSessionDidStopWithStatus(sessionStatus: MeetingSessionStatus(statusCode: newAudioStatus))
            }
        }
    }

    private func processAnyDictToStringEnumDict<T: RawRepresentable>(anyDict: [AnyHashable: Any]) -> [String: T] {
        var strEnumDict = [String: T]()
        for (key, rawValue) in anyDict {
            if let keyString = key as? String, let rawValue = rawValue as? T.RawValue {
                if let value = T(rawValue: rawValue) {
                    strEnumDict[keyString] = value
                }
            }
        }
        return strEnumDict
    }
}

extension DefaultAudioClientObserver: AudioClientObserver {
    func notifyAudioClientObserver(observerFunction: @escaping (_ observer: AudioVideoObserver) -> Void) {
        ObserverUtils.forEach(observers: self.audioClientStateObservers) { (observer: AudioVideoObserver) in
            observerFunction(observer)
        }
    }

    func subscribeToAudioClientStateChange(observer: AudioVideoObserver) {
        audioClientStateObservers.add(observer)
    }

    func subscribeToRealTimeEvents(observer: RealtimeObserver) {
        realtimeObservers.add(observer)
    }

    func unsubscribeFromAudioClientStateChange(observer: AudioVideoObserver) {
        audioClientStateObservers.remove(observer)
    }

    func unsubscribeFromRealTimeEvents(observer: RealtimeObserver) {
        realtimeObservers.remove(observer)
    }
}
