//
//  AudioExclusiveCoordinator.swift
//  Vocable
//
//  Sibling of CameraExclusiveCoordinator for the audio session.
//  Vocable's AudioEngineController owns the AVAudioSession for
//  listening mode and sound effects; AudioCaptureService and
//  AudioPlaybackService also reach for the session when the
//  caregiver records or plays back a phrase. Without coordination
//  the two systems can race to set the session category, leaving
//  listening mode broken or the recording silent.
//
//  Producers acquire an AudioExclusiveLease; AudioEngineController
//  observes the exclusive flag and pauses its engine for the
//  duration. Same defensive shape as the camera coordinator —
//  Set-of-IDs source of truth, 5-min safety timeout, multi-observer,
//  snapshot-then-dispatch fan-out, serial queue isolation.
//

import Foundation

/// Lease handle. Auto-released on deinit; calling `release()` more
/// than once is safe.
public final class AudioExclusiveLease: @unchecked Sendable {

    public let id: UUID
    public let reason: String

    private let lock = NSLock()
    private var onRelease: (() -> Void)?

    fileprivate init(id: UUID, reason: String, onRelease: @escaping () -> Void) {
        self.id = id
        self.reason = reason.isEmpty ? "unspecified" : reason
        self.onRelease = onRelease
    }

    public func release() {
        lock.lock()
        let callback = onRelease
        onRelease = nil
        lock.unlock()
        callback?()
    }

    deinit {
        release()
    }
}

/// Subscription handle for state-change observers.
public final class AudioExclusiveObserverToken: @unchecked Sendable {

    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    fileprivate init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        lock.lock()
        let callback = onCancel
        onCancel = nil
        lock.unlock()
        callback?()
    }

    deinit { cancel() }
}

public final class AudioExclusiveCoordinator {

    public static let shared = AudioExclusiveCoordinator()

    /// Max lease duration before auto-release. 5 minutes covers any
    /// reasonable recording or playback flow and short enough that a
    /// stuck producer can't permanently lock the audio engine.
    public var maxLeaseDuration: TimeInterval = 5 * 60

    private let queue = DispatchQueue(
        label: "AudioExclusiveCoordinator.queue",
        qos: .userInitiated
    )
    private var activeLeaseIDs: Set<UUID> = []
    private var observers: [UUID: (Bool) -> Void] = [:]
    private var leaseTimers: [UUID: Timer] = [:]

    public var isAudioExclusive: Bool {
        queue.sync { !activeLeaseIDs.isEmpty }
    }

    private init() {}

    // MARK: - Public API

    @discardableResult
    public func acquire(reason: String) -> AudioExclusiveLease {
        let leaseID = UUID()
        let lease = AudioExclusiveLease(
            id: leaseID,
            reason: reason
        ) { [weak self] in
            self?.releaseLease(id: leaseID, viaTimeout: false)
        }

        queue.async { [weak self] in
            guard let self else { return }
            let wasIdle = self.activeLeaseIDs.isEmpty
            self.activeLeaseIDs.insert(leaseID)
            self.scheduleSafetyTimer(for: leaseID)
            self.logDebug("acquire id=\(leaseID.uuidString.prefix(8)) reason=\"\(reason)\" active=\(self.activeLeaseIDs.count)")
            if wasIdle {
                self.fanOutStateChange(true)
            }
        }

        return lease
    }

    public func observe(_ observer: @escaping (Bool) -> Void) -> AudioExclusiveObserverToken {
        let observerID = UUID()
        let token = AudioExclusiveObserverToken { [weak self] in
            self?.queue.async { [weak self] in
                self?.observers.removeValue(forKey: observerID)
            }
        }
        queue.async { [weak self] in
            self?.observers[observerID] = observer
        }
        return token
    }

    // MARK: - Internals

    private func releaseLease(id: UUID, viaTimeout: Bool) {
        queue.async { [weak self] in
            guard let self else { return }

            guard self.activeLeaseIDs.remove(id) != nil else {
                self.logDebug("release id=\(id.uuidString.prefix(8)) ignored (not active)")
                return
            }

            if let timer = self.leaseTimers.removeValue(forKey: id) {
                timer.invalidate()
            }

            self.logDebug("release id=\(id.uuidString.prefix(8)) viaTimeout=\(viaTimeout) active=\(self.activeLeaseIDs.count)")

            if self.activeLeaseIDs.isEmpty {
                self.fanOutStateChange(false)
            }
        }
    }

    private func scheduleSafetyTimer(for leaseID: UUID) {
        let duration = maxLeaseDuration
        DispatchQueue.main.async { [weak self] in
            let timer = Timer.scheduledTimer(
                withTimeInterval: duration,
                repeats: false
            ) { [weak self] _ in
                self?.logDebug("safety timeout — auto-releasing \(leaseID.uuidString.prefix(8))")
                self?.releaseLease(id: leaseID, viaTimeout: true)
            }
            self?.queue.async { [weak self] in
                guard let self else {
                    timer.invalidate()
                    return
                }
                if self.activeLeaseIDs.contains(leaseID) {
                    self.leaseTimers[leaseID] = timer
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func fanOutStateChange(_ isExclusive: Bool) {
        let observersSnapshot = observers
        DispatchQueue.main.async {
            for observer in observersSnapshot.values {
                observer(isExclusive)
            }
        }
    }

    private func logDebug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[AudioExclusive] \(message())")
        #endif
    }

    // MARK: - Test hook

    #if DEBUG
    public func _resetForTesting() {
        queue.sync {
            leaseTimers.values.forEach { $0.invalidate() }
            leaseTimers.removeAll()
            activeLeaseIDs.removeAll()
            observers.removeAll()
        }
    }
    #endif
}
