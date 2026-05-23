//
//  VoiceRecorderViewModelTests.swift
//  VocableTests
//

import XCTest
@testable import Vocable

final class VoiceRecorderViewModelTests: XCTestCase {

    private var capture: FakeCaptureService!
    private var vm: VoiceRecorderViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        capture = FakeCaptureService()
        vm = VoiceRecorderViewModel(captureService: capture, maxDuration: 15)
    }

    override func tearDownWithError() throws {
        vm = nil
        capture = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_initial_stateIsReady() {
        XCTAssertEqual(vm.state, .ready)
    }

    func test_startRecording_transitionsToRecording_withZeroElapsed() throws {
        try vm.startRecording()
        XCTAssertEqual(vm.state, .recording(elapsed: 0))
        XCTAssertEqual(capture.prepareCount, 1)
        XCTAssertEqual(capture.startCount, 1)
    }

    func test_startRecording_ignored_whenAlreadyRecording() throws {
        try vm.startRecording()
        try vm.startRecording()
        XCTAssertEqual(capture.prepareCount, 1)
    }

    func test_tick_advancesElapsedTime() throws {
        try vm.startRecording()
        try vm.tick(0.5)
        try vm.tick(0.5)
        XCTAssertEqual(vm.state, .recording(elapsed: 1.0))
    }

    func test_tick_autoStopsAtMaxDuration_andTransitionsToReview() throws {
        try vm.startRecording()
        capture.stubbedStopData = Data([0xAA, 0xBB])

        // 14 ticks of 1s = 14s elapsed (still recording).
        for _ in 0..<14 { try vm.tick(1) }
        if case .recording = vm.state {} else {
            XCTFail("Expected still recording at 14s")
        }

        // 15th tick crosses the 15s cap.
        try vm.tick(1)

        XCTAssertEqual(vm.state, .review(audioData: Data([0xAA, 0xBB])))
        XCTAssertEqual(capture.stopCount, 1)
    }

    func test_stopRecording_transitionsToReview_withCapturedData() throws {
        try vm.startRecording()
        capture.stubbedStopData = Data([0x01, 0x02, 0x03])
        try vm.stopRecording()
        XCTAssertEqual(vm.state, .review(audioData: Data([0x01, 0x02, 0x03])))
    }

    func test_stopRecording_isNoOp_whenNotRecording() throws {
        try vm.stopRecording()    // from .ready
        XCTAssertEqual(vm.state, .ready)
        XCTAssertEqual(capture.stopCount, 0)
    }

    func test_discardAndReturnToReady_fromReview_resetsState() throws {
        try vm.startRecording()
        capture.stubbedStopData = Data([0x01])
        try vm.stopRecording()
        vm.discardAndReturnToReady()
        XCTAssertEqual(vm.state, .ready)
        XCTAssertEqual(capture.cancelCount, 1)
    }

    func test_confirmedData_returnsAudio_onlyInReviewState() throws {
        XCTAssertNil(vm.confirmedData())
        try vm.startRecording()
        XCTAssertNil(vm.confirmedData())
        capture.stubbedStopData = Data([0x42])
        try vm.stopRecording()
        XCTAssertEqual(vm.confirmedData(), Data([0x42]))
    }

    func test_onStateChange_firesForEveryTransition() throws {
        var states: [VoiceRecorderViewModel.State] = []
        vm.onStateChange = { states.append($0) }

        try vm.startRecording()
        try vm.tick(1)
        capture.stubbedStopData = Data([0x01])
        try vm.stopRecording()
        vm.discardAndReturnToReady()

        XCTAssertEqual(states, [
            .recording(elapsed: 0),
            .recording(elapsed: 1),
            .review(audioData: Data([0x01])),
            .ready
        ])
    }
}

// MARK: - Fake capture service

private final class FakeCaptureService: AudioCaptureServicing {
    var stubbedStopData = Data()
    var currentInputLevelDB: Float = -160
    var isRecording: Bool = false

    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    func prepare() throws -> URL {
        prepareCount += 1
        return URL(fileURLWithPath: "/tmp/fake.m4a")
    }

    func start() throws {
        startCount += 1
        isRecording = true
    }

    func stop() throws -> Data {
        stopCount += 1
        isRecording = false
        return stubbedStopData
    }

    func cancel() {
        cancelCount += 1
        isRecording = false
    }
}
