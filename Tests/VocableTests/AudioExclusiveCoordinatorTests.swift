//
//  AudioExclusiveCoordinatorTests.swift
//  VocableTests
//
//  Mirrors CameraExclusiveCoordinatorTests one-for-one. Validates
//  the same defensive contract — idempotent release, deinit-driven
//  cleanup, safety timeout, multi-observer fan-out, re-entrancy
//  safety, concurrent stress.
//

import XCTest
@testable import Vocable

final class AudioExclusiveCoordinatorTests: XCTestCase {

    private var coordinator: AudioExclusiveCoordinator { .shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        coordinator._resetForTesting()
    }

    override func tearDownWithError() throws {
        coordinator._resetForTesting()
        try super.tearDownWithError()
    }

    func test_acquire_flipsStateToTrue() {
        let exp = expectation(description: "state change")
        var captured: [Bool] = []
        let token = coordinator.observe { isExclusive in
            captured.append(isExclusive)
            if captured.count == 1 { exp.fulfill() }
        }
        let lease = coordinator.acquire(reason: "test")
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(captured, [true])
        withExtendedLifetime(lease) {}
        token.cancel()
    }

    func test_releaseSingleLease_flipsStateToFalse() {
        let up = expectation(description: "up")
        let down = expectation(description: "down")
        var captured: [Bool] = []
        let token = coordinator.observe { isExclusive in
            captured.append(isExclusive)
            if captured.count == 1 { up.fulfill() }
            if captured.count == 2 { down.fulfill() }
        }
        let lease = coordinator.acquire(reason: "test")
        wait(for: [up], timeout: 1)
        lease.release()
        wait(for: [down], timeout: 1)
        XCTAssertEqual(captured, [true, false])
        token.cancel()
    }

    func test_doubleAcquire_singleStateChange() {
        var captured: [Bool] = []
        let token = coordinator.observe { isExclusive in
            captured.append(isExclusive)
        }
        let one = coordinator.acquire(reason: "one")
        let two = coordinator.acquire(reason: "two")
        let exp = expectation(description: "drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(captured, [true])

        one.release()
        let exp2 = expectation(description: "drain 2")
        DispatchQueue.main.async { exp2.fulfill() }
        wait(for: [exp2], timeout: 1)
        XCTAssertEqual(captured, [true])

        two.release()
        let exp3 = expectation(description: "drain 3")
        DispatchQueue.main.async { exp3.fulfill() }
        wait(for: [exp3], timeout: 1)
        XCTAssertEqual(captured, [true, false])

        token.cancel()
    }

    func test_release_isIdempotent() {
        let lease = coordinator.acquire(reason: "idempotent")
        lease.release()
        lease.release()
        lease.release()
        let exp = expectation(description: "drain")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertFalse(coordinator.isAudioExclusive)
    }

    func test_deinit_releasesLease() {
        let exp = expectation(description: "down after dealloc")
        var captured: [Bool] = []
        let token = coordinator.observe { isExclusive in
            captured.append(isExclusive)
            if captured == [true, false] { exp.fulfill() }
        }
        autoreleasepool {
            let lease = coordinator.acquire(reason: "scope")
            XCTAssertNotNil(lease)
        }
        wait(for: [exp], timeout: 1)
        XCTAssertFalse(coordinator.isAudioExclusive)
        token.cancel()
    }

    func test_safetyTimeout_autoReleasesStuckLease() {
        coordinator.maxLeaseDuration = 0.1

        let up = expectation(description: "up")
        let down = expectation(description: "down via timeout")
        var captured: [Bool] = []
        let token = coordinator.observe { isExclusive in
            captured.append(isExclusive)
            if captured == [true] { up.fulfill() }
            if captured == [true, false] { down.fulfill() }
        }
        let lease = coordinator.acquire(reason: "stuck")
        wait(for: [up], timeout: 1)
        wait(for: [down], timeout: 2)
        lease.release()
        XCTAssertFalse(coordinator.isAudioExclusive)
        token.cancel()
    }

    func test_multipleObservers_allFire() {
        let exp1 = expectation(description: "obs1")
        let exp2 = expectation(description: "obs2")
        exp1.assertForOverFulfill = false
        exp2.assertForOverFulfill = false
        let token1 = coordinator.observe { _ in exp1.fulfill() }
        let token2 = coordinator.observe { _ in exp2.fulfill() }
        let lease = coordinator.acquire(reason: "fanout")
        wait(for: [exp1, exp2], timeout: 1)
        withExtendedLifetime(lease) {}
        token1.cancel()
        token2.cancel()
    }

    func test_cancelledObserver_doesNotFire() {
        let shouldNotFire = expectation(description: "cancelled observer")
        shouldNotFire.isInverted = true

        let token = coordinator.observe { _ in shouldNotFire.fulfill() }
        token.cancel()

        let drain = expectation(description: "drain")
        DispatchQueue.main.async { drain.fulfill() }
        wait(for: [drain], timeout: 1)

        _ = coordinator.acquire(reason: "ignored")
        wait(for: [shouldNotFire], timeout: 0.5)
    }

    func test_observer_thatCallsAcquireInsideCallback_doesNotDeadlock() {
        let exp = expectation(description: "inner acquire returns")
        var innerLease: AudioExclusiveLease?
        let token = coordinator.observe { isExclusive in
            if isExclusive && innerLease == nil {
                innerLease = self.coordinator.acquire(reason: "inner")
                exp.fulfill()
            }
        }
        _ = coordinator.acquire(reason: "outer")
        wait(for: [exp], timeout: 1)
        XCTAssertNotNil(innerLease)
        token.cancel()
    }

    func test_concurrentAcquireRelease_endsAtCountZero() {
        let group = DispatchGroup()
        let iterations = 200
        for _ in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let lease = self.coordinator.acquire(reason: "stress")
                lease.release()
                group.leave()
            }
        }
        let exp = expectation(description: "drain stress")
        group.notify(queue: .main) { exp.fulfill() }
        wait(for: [exp], timeout: 5)

        let settle = expectation(description: "queue settle")
        DispatchQueue.main.async { settle.fulfill() }
        wait(for: [settle], timeout: 1)

        XCTAssertFalse(coordinator.isAudioExclusive)
    }
}
