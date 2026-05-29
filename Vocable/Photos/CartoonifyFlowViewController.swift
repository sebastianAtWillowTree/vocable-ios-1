//
//  CartoonifyFlowViewController.swift
//  Vocable
//
//  Renders the multi-step cartoonify flow driven by
//  CartoonifyFlowCoordinator. A single view controller switches
//  visible subviews based on coordinator state — there's no
//  navigation stack churn, so accessibility focus stays predictable
//  for caregivers using head tracking.
//

import UIKit

final class CartoonifyFlowViewController: UIViewController, UITextViewDelegate {

    static let maxPromptLength = 240

    private let coordinator: CartoonifyFlowCoordinator

    init(coordinator: CartoonifyFlowCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(coordinator:)") }

    // MARK: - Subviews

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .title1)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var promptTextView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.font = .preferredFont(forTextStyle: .title3)
        view.delegate = self
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor
        view.layer.cornerRadius = 8
        view.accessibilityLabel = String(
            localized: "cartoonify.describe.accessibility",
            defaultValue: "Description for the cartoon"
        )
        view.inputAccessoryView = makeKeyboardToolbar()
        return view
    }()

    private func makeKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexible = UIBarButtonItem(
            barButtonSystemItem: .flexibleSpace,
            target: nil,
            action: nil
        )
        let done = UIBarButtonItem(
            title: String(
                localized: "cartoonify.keyboard.done",
                defaultValue: "Done"
            ),
            style: .done,
            target: self,
            action: #selector(dismissKeyboard)
        )
        toolbar.items = [flexible, done]
        return toolbar
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var previewImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        view.isAccessibilityElement = false
        return view
    }()

    private lazy var promptReadoutLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
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
            localized: "cartoonify.cancel",
            defaultValue: "Cancel"
        ), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
        button.addTarget(self, action: #selector(cancelTapped), for: .primaryActionTriggered)
        return button
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        [statusLabel, promptTextView, errorLabel, previewImageView,
         promptReadoutLabel, spinner, primaryButton, secondaryButton,
         cancelButton].forEach { view.addSubview($0) }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 32),
            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            promptTextView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            promptTextView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            promptTextView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            promptTextView.heightAnchor.constraint(equalToConstant: 120),

            errorLabel.topAnchor.constraint(equalTo: promptTextView.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            previewImageView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            previewImageView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            previewImageView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            previewImageView.bottomAnchor.constraint(equalTo: promptReadoutLabel.topAnchor, constant: -16),

            promptReadoutLabel.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -24),
            promptReadoutLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            promptReadoutLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            primaryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: secondaryButton.topAnchor, constant: -16),

            secondaryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            secondaryButton.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -32),

            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24)
        ])

        // Tap anywhere outside the text view to dismiss the keyboard.
        // cancelsTouchesInView = false so taps still reach buttons.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        coordinator.onStateChange = { [weak self] state in
            self?.render(state: state)
        }
        render(state: coordinator.state)
    }

    // MARK: - Rendering

    private func render(state: CartoonifyFlowCoordinator.State) {
        switch state {
        case .describing(let prompt, let errorMessage):
            statusLabel.text = String(
                localized: "cartoonify.describe.title",
                defaultValue: "Describe the cartoon"
            )
            promptTextView.isHidden = false
            if promptTextView.text != prompt { promptTextView.text = prompt }
            errorLabel.text = errorMessage
            errorLabel.isHidden = (errorMessage == nil)

            previewImageView.isHidden = true
            promptReadoutLabel.isHidden = true
            spinner.stopAnimating()

            primaryButton.setTitle(String(
                localized: "cartoonify.generate.button",
                defaultValue: "Generate"
            ), for: .normal)
            primaryButton.isHidden = false
            primaryButton.isEnabled = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            secondaryButton.isHidden = true

        case .generating(let prompt):
            statusLabel.text = String(
                localized: "cartoonify.generating.title",
                defaultValue: "Generating…"
            )
            promptTextView.isHidden = true
            errorLabel.isHidden = true
            previewImageView.isHidden = true
            promptReadoutLabel.text = prompt
            promptReadoutLabel.isHidden = false
            spinner.startAnimating()

            primaryButton.isHidden = true
            secondaryButton.isHidden = true

        case .reviewing(let image, let prompt):
            statusLabel.text = String(
                localized: "cartoonify.review.title",
                defaultValue: "How does this look?"
            )
            promptTextView.isHidden = true
            errorLabel.isHidden = true
            previewImageView.image = image
            previewImageView.isHidden = false
            promptReadoutLabel.text = prompt
            promptReadoutLabel.isHidden = false
            spinner.stopAnimating()

            primaryButton.setTitle(String(
                localized: "cartoonify.review.use_button",
                defaultValue: "Use this"
            ), for: .normal)
            primaryButton.isHidden = false
            primaryButton.isEnabled = true

            secondaryButton.setTitle(String(
                localized: "cartoonify.review.refine_button",
                defaultValue: "Refine description"
            ), for: .normal)
            secondaryButton.isHidden = false
        }
    }

    // MARK: - Actions

    @objc private func primaryTapped() {
        // Always relinquish first-responder so the keyboard doesn't
        // linger over the next-state UI.
        view.endEditing(true)
        switch coordinator.state {
        case .describing:
            coordinator.generate()
        case .reviewing:
            coordinator.confirm()
        case .generating:
            break
        }
    }

    @objc private func secondaryTapped() {
        view.endEditing(true)
        // Only meaningful in .reviewing — refine.
        if case .reviewing = coordinator.state {
            coordinator.refine()
        }
    }

    @objc private func cancelTapped() {
        view.endEditing(true)
        // In .generating, cancel the in-flight request and stay in the flow.
        // In .describing / .reviewing, dismiss the entire flow.
        if case .generating = coordinator.state {
            coordinator.cancelGeneration()
        } else {
            coordinator.cancel()
        }
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = (textView.text as NSString?) ?? ""
        let updated = current.replacingCharacters(in: range, with: text)
        return updated.count <= Self.maxPromptLength
    }

    func textViewDidChange(_ textView: UITextView) {
        coordinator.updatePrompt(textView.text)
    }
}
