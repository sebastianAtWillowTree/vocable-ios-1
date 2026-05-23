//
//  VoiceRecorderViewController.swift
//  Vocable
//
//  Caregiver-facing UI for recording a short voice sample for a
//  phrase. Drives VoiceRecorderViewModel through a state machine
//  (ready → recording → review). On Save, hands the recorded
//  audio bytes back to the caller.
//

import UIKit
import AVFoundation

final class VoiceRecorderViewController: UIViewController {

    private let viewModel: VoiceRecorderViewModel
    private let onSave: (Data) -> Void
    private let onCancel: () -> Void
    private var tickTimer: Timer?
    private var previewPlayer: AVAudioPlayer?

    init(
        captureService: AudioCaptureServicing = AudioCaptureService(),
        maxDuration: TimeInterval = 15,
        onSave: @escaping (Data) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = VoiceRecorderViewModel(
            captureService: captureService,
            maxDuration: maxDuration
        )
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(captureService:onSave:onCancel:)") }

    // MARK: - UI

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .title1)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var elapsedLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        label.textAlignment = .center
        label.text = "0.0 / 15.0 s"
        label.isHidden = true
        return label
    }()

    private lazy var primaryButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .preferredFont(forTextStyle: .title2)
        button.addTarget(self, action: #selector(primaryTapped), for: .primaryActionTriggered)
        return button
    }()

    private lazy var secondaryButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
        button.isHidden = true
        button.addTarget(self, action: #selector(secondaryTapped), for: .primaryActionTriggered)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(String(
            localized: "voice_recorder.cancel",
            defaultValue: "Cancel"
        ), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
        button.addTarget(self, action: #selector(cancelTapped), for: .primaryActionTriggered)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        [statusLabel, elapsedLabel, primaryButton, secondaryButton, cancelButton].forEach { view.addSubview($0) }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 48),
            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            elapsedLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 32),
            elapsedLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            elapsedLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            primaryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            primaryButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            secondaryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            secondaryButton.topAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: 24),

            cancelButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            cancelButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24)
        ])

        viewModel.onStateChange = { [weak self] state in
            self?.render(state: state)
        }
        render(state: viewModel.state)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopTimer()
        previewPlayer?.stop()
    }

    // MARK: - Rendering

    private func render(state: VoiceRecorderViewModel.State) {
        switch state {
        case .ready:
            statusLabel.text = String(
                localized: "voice_recorder.status.ready",
                defaultValue: "Record a short voice sample"
            )
            elapsedLabel.isHidden = true
            primaryButton.setTitle(String(
                localized: "voice_recorder.button.record",
                defaultValue: "Record"
            ), for: .normal)
            secondaryButton.isHidden = true
            stopTimer()
            previewPlayer?.stop()
        case .recording(let elapsed):
            statusLabel.text = String(
                localized: "voice_recorder.status.recording",
                defaultValue: "Recording…"
            )
            elapsedLabel.isHidden = false
            elapsedLabel.text = String(format: "%.1f / %.1f s", elapsed, viewModel.maxDuration)
            primaryButton.setTitle(String(
                localized: "voice_recorder.button.stop",
                defaultValue: "Stop"
            ), for: .normal)
            secondaryButton.isHidden = true
        case .review:
            statusLabel.text = String(
                localized: "voice_recorder.status.review",
                defaultValue: "Listen and save, or re-record."
            )
            elapsedLabel.isHidden = true
            primaryButton.setTitle(String(
                localized: "voice_recorder.button.save",
                defaultValue: "Save"
            ), for: .normal)
            secondaryButton.isHidden = false
            secondaryButton.setTitle(String(
                localized: "voice_recorder.button.rerecord",
                defaultValue: "Play & Re-record"
            ), for: .normal)
            stopTimer()
        }
    }

    // MARK: - Actions

    @objc private func primaryTapped() {
        switch viewModel.state {
        case .ready:
            do {
                try viewModel.startRecording()
                startTimer()
            } catch {
                presentErrorAlert(error)
            }
        case .recording:
            do {
                try viewModel.stopRecording()
            } catch {
                presentErrorAlert(error)
            }
        case .review:
            if let data = viewModel.confirmedData() {
                stopTimer()
                onSave(data)
            }
        }
    }

    @objc private func secondaryTapped() {
        // In review state: play preview, then offer re-record.
        if case let .review(data) = viewModel.state {
            playPreview(data: data) { [weak self] in
                self?.viewModel.discardAndReturnToReady()
            }
        }
    }

    @objc private func cancelTapped() {
        stopTimer()
        previewPlayer?.stop()
        viewModel.discardAndReturnToReady()
        onCancel()
    }

    // MARK: - Timer

    private func startTimer() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            do { try self?.viewModel.tick(0.1) }
            catch { self?.presentErrorAlert(error) }
        }
    }

    private func stopTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Preview playback

    private func playPreview(data: Data, completion: @escaping () -> Void) {
        do {
            let player = try AVAudioPlayer(data: data)
            previewPlayer = player
            player.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1, execute: completion)
        } catch {
            completion()
        }
    }

    private func presentErrorAlert(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "voice_recorder.error.title", defaultValue: "Recording error"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
