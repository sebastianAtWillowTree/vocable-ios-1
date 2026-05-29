//
//  CameraExclusiveCoordinator.swift
//  Vocable
//
//  Coordinates exclusive use of the device camera between subsystems.
//  In Vocable that means: the head-tracking ARFaceTrackingConfiguration
//  uses the front camera continuously; when the caregiver opens a photo
//  capture or library flow (which may also reach for the camera, and
//  whose modal screens shouldn't be talking to a gaze cursor in any
//  case) we want head tracking suspended for the duration.
//
//  Producers acquire a CameraExclusiveLease; consumers observe the
//  exclusive-state flag and pause/resume accordingly. ARC-driven,
//  idempotent, with a safety-timeout net so a stuck producer can't
//  permanently disable head tracking.
//
//  Defensive techniques in use here:
//
//   - ARC-driven lease lifetime + idempotent explicit release
//   - Counter underflow guard (double-release is a no-op + log)
//   - Safety-net timeout (default 5 min) — stuck lease auto-releases
//   - Observer tokens, also ARC-managed; multiple observers supported
//   - Snapshot-then-dispatch observer fan-out — observers that call
//     acquire/release inside their callback can't deadlock the queue
//   - Serial queue isolation for all mutable state
//   - Observer callbacks fire on the main queue
//   - `weak self` everywhere in long-lived closures
//   - #if DEBUG diagnostic logging with short lease IDs
//   - _resetForTesting test hook
//

import Foundation

/// Lease handle. Auto-released on deinit; calling `release()` more
/// than once is safe.
public final class CameraExclusiveLease: @unchecked Sendable {

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
        // Snapshot-and-clear under the lock so reentrancy inside
        // onRelease can't trigger another release.
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

/// Subscription handle for state-change observers. Cancel explicitly
/// or let ARC dealloc it.
public final class CameraExclusiveObserverToken: @unchecked Sendable {

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

public final class CameraExclusiveCoordinator {

    public static let shared = CameraExclusiveCoordinator()

    /// Max lease duration before auto-release. 5 minutes is generous
    /// for caregiver-driven flows and short enough that a stuck or
    /// leaked lease doesn't permanently disable head tracking for the
    /// AAC user.
    public var maxLeaseDuration: TimeInterval = 5 * 60

    private let queue = DispatchQueue(
        label: "CameraExclusiveCoordinator.queue",
        qos: .userInitiated
    )
    /// Source of truth for "which leases are currently held." Using a
    /// Set (instead of a bare counter) makes release idempotent and
    /// race-free even when timer scheduling lags behind a fast
    /// acquire-then-release cycle.
    private var activeLeaseIDs: Set<UUID> = []
    private var observers: [UUID: (Bool) -> Void] = [:]
    private var leaseTimers: [UUID: Timer] = [:]

    public var isCameraExclusive: Bool {
        queue.sync { !activeLeaseIDs.isEmpty }
    }

    private init() {}

    // MARK: - Public API

    @discardableResult
    public func acquire(reason: String) -> CameraExclusiveLease {
        let leaseID = UUID()
        let lease = CameraExclusiveLease(
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

    public func observe(_ observer: @escaping (Bool) -> Void) -> CameraExclusiveObserverToken {
        let observerID = UUID()
        let token = CameraExclusiveObserverToken { [weak self] in
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

            // Idempotent: only the first release for a given lease ID
            // actually decrements state. Set.remove returns the value
            // iff it was present, so it cleanly handles repeated and
            // race-condition release paths.
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
        // Must be called from `queue`.
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
                // If the lease was released before this timer-store
                // task ran, throw the timer away to avoid orphaning it.
                if self.activeLeaseIDs.contains(leaseID) {
                    self.leaseTimers[leaseID] = timer
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func fanOutStateChange(_ isExclusive: Bool) {
        // Snapshot under queue, dispatch on main. Observers that call
        // acquire/release inside their callback can't deadlock the queue.
        let observersSnapshot = observers
        DispatchQueue.main.async {
            for observer in observersSnapshot.values {
                observer(isExclusive)
            }
        }
    }

    private func logDebug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[CameraExclusive] \(message())")
        #endif
    }

    // MARK: - Test hook

    #if DEBUG
    /// Clears all state. Tests only.
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
