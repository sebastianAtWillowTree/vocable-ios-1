//
//  CartoonifyPreflightViewController.swift
//  Vocable
//
//  Renders the CartoonifyPreflightCoordinator state machine. Three
//  visible surfaces:
//      • enteringPrompt — subject preview + prompt entry + Continue
//      • classifying    — spinner with "Checking…"
//      • misaligned     — defers to PromptSubjectMismatchPresenting,
//                         which puts up a soft warning alert. The VC
//                         itself stays put under the alert.
//
//  Pattern follows CartoonifyFlowViewController — one VC, subviews
//  hide/show on state change, no navigation stack churn so focus
//  stays predictable for head-tracking users.
//

import UIKit

// MARK: - Mismatch presenter protocol

/// Seam for the "Your description doesn't match the photo's main
/// subject" alert. Production uses UIAlertController; tests inject a
/// fake to verify the VC fires the right action.
protocol PromptSubjectMismatchPresenting {
    func presentMismatchAlert(
        from presenter: UIViewController,
        reason: AlignmentMismatchReason,
        onContinueAnyway: @escaping () -> Void,
        onEditDescription: @escaping () -> Void,
        onCancel: @escaping () -> Void
    )
}

// MARK: - View controller

final class CartoonifyPreflightViewController: UIViewController, UITextViewDelegate {

    static let maxPromptLength = 240

    private let coordinator: CartoonifyPreflightCoordinator
    private let mismatchPresenter: PromptSubjectMismatchPresenting
    private let sourceImage: UIImage

    init(
        coordinator: CartoonifyPreflightCoordinator,
        sourceImage: UIImage,
        mismatchPresenter: PromptSubjectMismatchPresenting
    ) {
        self.coordinator = coordinator
        self.mismatchPresenter = mismatchPresenter
        self.sourceImage = sourceImage
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(coordinator:sourceImage:mismatchPresenter:)") }

    // MARK: - Subviews

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .title1)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var subjectPreview: UIImageView = {
        let view = UIImageView(image: sourceImage)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.isAccessibilityElement = false
        return view
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
            localized: "cartoonify.preflight.describe.accessibility",
            defaultValue: "Description for the cartoon"
        )
        view.inputAccessoryView = makeKeyboardToolbar()
        return view
    }()

    private func makeKeyboardToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(
            title: String(
                localized: "cartoonify.preflight.keyboard.done",
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

    private lazy var spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true
        return view
    }()

    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(String(
            localized: "cartoonify.preflight.continue.button",
            defaultValue: "Continue"
        ), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .title2)
        button.addTarget(self, action: #selector(continueTapped), for: .primaryActionTriggered)
        return button
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(String(
            localized: "cartoonify.preflight.cancel",
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

        [statusLabel, subjectPreview, promptTextView, spinner, continueButton, cancelButton]
            .forEach { view.addSubview($0) }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            subjectPreview.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            subjectPreview.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subjectPreview.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, multiplier: 0.6),
            subjectPreview.heightAnchor.constraint(equalTo: subjectPreview.widthAnchor),

            promptTextView.topAnchor.constraint(equalTo: subjectPreview.bottomAnchor, constant: 24),
            promptTextView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            promptTextView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            promptTextView.heightAnchor.constraint(equalToConstant: 120),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            continueButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            continueButton.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -16),

            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        coordinator.onStateChange = { [weak self] state in
            self?.render(state: state)
        }
        render(state: coordinator.state)
    }

    // MARK: - Rendering

    /// Tracks whether the mismatch alert is currently up so we don't
    /// stack a second copy if the coordinator emits .misaligned again.
    private var didPresentMismatchAlert = false

    private func render(state: CartoonifyPreflightCoordinator.State) {
        switch state {
        case .enteringPrompt(let prompt):
            statusLabel.text = String(
                localized: "cartoonify.preflight.describe.title",
                defaultValue: "Describe what to cartoonify"
            )
            subjectPreview.isHidden = false
            promptTextView.isHidden = false
            if promptTextView.text != prompt { promptTextView.text = prompt }
            spinner.stopAnimating()
            continueButton.isHidden = false
            continueButton.isEnabled = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            didPresentMismatchAlert = false

        case .classifying:
            statusLabel.text = String(
                localized: "cartoonify.preflight.checking.title",
                defaultValue: "Checking…"
            )
            subjectPreview.isHidden = true
            promptTextView.isHidden = true
            continueButton.isHidden = true
            spinner.startAnimating()
            view.endEditing(true)
            didPresentMismatchAlert = false

        case .misaligned(_, let reason):
            spinner.stopAnimating()
            view.endEditing(true)
            guard !didPresentMismatchAlert else { return }
            didPresentMismatchAlert = true
            mismatchPresenter.presentMismatchAlert(
                from: self,
                reason: reason,
                onContinueAnyway: { [weak self] in
                    self?.didPresentMismatchAlert = false
                    self?.coordinator.continueAnyway()
                },
                onEditDescription: { [weak self] in
                    self?.didPresentMismatchAlert = false
                    self?.coordinator.editDescription()
                },
                onCancel: { [weak self] in
                    self?.didPresentMismatchAlert = false
                    self?.coordinator.cancel()
                }
            )
        }
    }

    // MARK: - Actions

    @objc private func continueTapped() {
        view.endEditing(true)
        coordinator.continueFromPrompt()
    }

    @objc private func cancelTapped() {
        view.endEditing(true)
        coordinator.cancel()
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

// MARK: - Preflight presenter protocol + production adapter

/// Result of a preflight step. Confirmed prompt is the trimmed text
/// the caregiver wants to feed into cartoonify. nil completion means
/// they cancelled.
struct CartoonifyPreflightOutcome {
    let confirmedPrompt: String
}

/// Seam for "present the preflight UI and tell me when it's done."
/// Mirrors CartoonifyApplying's shape so PhotoEnhanceCoordinator can
/// treat it as just another step in the cartoonify chain.
protocol CartoonifyPreflightPresenting {
    func presentPreflight(
        sourceImage: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyPreflightOutcome?) -> Void
    )
}

/// Production CartoonifyPreflightPresenting. Constructs the
/// coordinator + VC inline so callers only have to supply the aligner
/// and mismatch presenter once at composition time.
final class DefaultCartoonifyPreflightPresenter: CartoonifyPreflightPresenting {

    private let aligner: PromptSubjectAligning
    private let mismatchPresenter: PromptSubjectMismatchPresenting
    /// Retained for the lifetime of the presentation so the coordinator
    /// + VC graph doesn't dealloc mid-flight when the closures are the
    /// only references back into it.
    private var activeGraph: AnyObject?

    init(
        aligner: PromptSubjectAligning,
        mismatchPresenter: PromptSubjectMismatchPresenting = AlertPromptSubjectMismatchPresenter()
    ) {
        self.aligner = aligner
        self.mismatchPresenter = mismatchPresenter
    }

    func presentPreflight(
        sourceImage: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyPreflightOutcome?) -> Void
    ) {
        var vc: UIViewController?

        let coordinator = CartoonifyPreflightCoordinator(
            sourceImage: sourceImage,
            initialPrompt: initialPrompt,
            aligner: aligner,
            onContinue: { [weak self] confirmedPrompt in
                self?.activeGraph = nil
                vc?.dismiss(animated: true) {
                    completion(CartoonifyPreflightOutcome(confirmedPrompt: confirmedPrompt))
                }
            },
            onCancel: { [weak self] in
                self?.activeGraph = nil
                vc?.dismiss(animated: true) {
                    completion(nil)
                }
            }
        )
        let preflightVC = CartoonifyPreflightViewController(
            coordinator: coordinator,
            sourceImage: sourceImage,
            mismatchPresenter: mismatchPresenter
        )
        vc = preflightVC
        // Retain the coordinator (and transitively the VC's references)
        // across the async present/dismiss cycle.
        activeGraph = coordinator
        presenter.present(preflightVC, animated: true)
    }
}

// MARK: - Production alert presenter

/// UIAlertController-backed PromptSubjectMismatchPresenting. Three
/// actions: "Continue anyway" (default), "Edit description", "Cancel".
/// Messaging varies based on whether the misalignment was the
/// high-signal personhood case or the lower-signal "no overlap" case.
struct AlertPromptSubjectMismatchPresenter: PromptSubjectMismatchPresenting {

    func presentMismatchAlert(
        from presenter: UIViewController,
        reason: AlignmentMismatchReason,
        onContinueAnyway: @escaping () -> Void,
        onEditDescription: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let title = String(
            localized: "cartoonify.preflight.mismatch.title",
            defaultValue: "Description doesn't match the photo"
        )
        let message = Self.message(for: reason)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: String(
                localized: "cartoonify.preflight.mismatch.continue",
                defaultValue: "Continue anyway"
            ),
            style: .default
        ) { _ in onContinueAnyway() })
        alert.addAction(UIAlertAction(
            title: String(
                localized: "cartoonify.preflight.mismatch.edit",
                defaultValue: "Edit description"
            ),
            style: .default
        ) { _ in onEditDescription() })
        alert.addAction(UIAlertAction(
            title: String(
                localized: "cartoonify.preflight.mismatch.cancel",
                defaultValue: "Cancel"
            ),
            style: .cancel
        ) { _ in onCancel() })

        presenter.present(alert, animated: true)
    }

    private static func message(for reason: AlignmentMismatchReason) -> String {
        switch reason {
        case .personSubjectButPromptIsObject:
            return String(
                localized: "cartoonify.preflight.mismatch.message.person",
                defaultValue: "The photo's main subject looks like a person, but your description is about an object. Cartoonify works best when they match."
            )
        case .noOverlapBetweenPromptAndImage:
            return String(
                localized: "cartoonify.preflight.mismatch.message.no_overlap",
                defaultValue: "Your description doesn't seem to match what's in the photo. Cartoonify works best when they match."
            )
        }
    }
}
