import Foundation
import ARKit
import Combine

extension Notification.Name {
    static let applicationDidAcquireGaze = Notification.Name("applicationDidAcquireGaze")
    static let applicationDidLoseGaze = Notification.Name("applicationDidLoseGaze")
    static let headTrackingDisabled = Notification.Name("headTrackingDisabled")
}

extension UIApplication {

    fileprivate class Storage {

        static var isGazeTrackingActive: Bool = false {
            didSet {
                guard oldValue != isGazeTrackingActive else { return }
                if isGazeTrackingActive {
                    NotificationCenter.default.post(name: .applicationDidAcquireGaze, object: nil)
                } else {
                    NotificationCenter.default.post(name: .applicationDidLoseGaze, object: nil)
                }
            }
        }
    }

    var isGazeTrackingActive: Bool {
        return Storage.isGazeTrackingActive
    }
}

class UIHeadGazeViewController: UIViewController, ARSessionDelegate, ARSCNViewDelegate {

    private(set) var sceneview: ARSCNView?
    private lazy var receivingWindow: HeadGazeWindow? = {
        for window in UIApplication.shared.connectedSceneWindows {
            if let result = window as? HeadGazeWindow {
                return result
            }
        }
        return nil
    }()

    let pidInterpolator = PIDControlledTrackingInterpolator()
    let debugInterpolator = HeadGazeTrackingInterpolator()
    lazy var trackingInterpolators: [HeadGazeTrackingInterpolator] = [pidInterpolator, debugInterpolator]

    private var computedScale: CGFloat = 0
    private var xAngleCorrectionAmount = 0.0
    private var yAngleCorrectionAmount = 0.0

    // The minimum/maximum values to scale how quickly the cursor moves around the screen
    var scalingRange = (3.0 ... 6.0)

    private var disposables = Set<AnyCancellable>()

    // MARK: - Camera-exclusive coordination
    //
    // The head-gaze window stays on screen even when other parts of the
    // app present modals (caregiver photo capture, etc.), so the AR
    // session would otherwise keep the front camera reserved and fight
    // any other camera consumer. We subscribe to CameraExclusiveCoordinator
    // so that whenever another subsystem acquires a lease, we pause the
    // AR session for the duration.
    private var cameraExclusiveObservation: CameraExclusiveObserverToken?
    private var isViewVisible = false
    private var isCameraSuspendedByCoordinator = false
    private var isARSessionRunning = false

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneview = ARSCNView(frame: .zero)
        self.view.addSubview(sceneview!)
        sceneview?.translatesAutoresizingMaskIntoConstraints = false
        sceneview?.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        sceneview?.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        sceneview?.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        sceneview?.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        sceneview?.delegate = self
        sceneview?.session.delegate = self
        sceneview?.isHidden = true
        sceneview?.preferredFramesPerSecond =  UIScreen.main.maximumFramesPerSecond
        setupSceneNode()
        
        AppConfig.$cursorSensitivity.sink { [weak self] (sensitivity) in
            guard let self = self else { return }
            self.scalingRange = sensitivity.range
        }.store(in: &disposables)

        for interpolator in trackingInterpolators {
            interpolator.view = self.view
        }

        // Subscribe to camera-exclusive state. When any other subsystem
        // (e.g. caregiver photo capture) acquires a lease, we pause the
        // AR session; when the last lease is released, we resume.
        cameraExclusiveObservation = CameraExclusiveCoordinator.shared.observe { [weak self] isExclusive in
            guard let self else { return }
            self.isCameraSuspendedByCoordinator = isExclusive
            self.applyTrackingState()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isViewVisible = true
        applyTrackingState()

        if let sceneView = sceneview {
            sceneView.isHidden = false
            view.sendSubviewToBack(sceneView)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        applyTrackingState()
    }

    deinit {
        cameraExclusiveObservation?.cancel()
    }

    /// Decides whether the AR session should currently be running and
    /// transitions only on change (so we don't restart-with-reset
    /// repeatedly or pause an already-paused session).
    private func applyTrackingState() {
        let shouldTrack = isViewVisible && !isCameraSuspendedByCoordinator
        if shouldTrack && !isARSessionRunning {
            let configuration = ARFaceTrackingConfiguration()
            configuration.worldAlignment = .camera
            sceneview?.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            isARSessionRunning = true
        } else if !shouldTrack && isARSessionRunning {
            sceneview?.session.pause()
            isARSessionRunning = false
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let correction = CGSize(width: xAngleCorrectionAmount, height: yAngleCorrectionAmount)
        for interpolator in trackingInterpolators {
            interpolator.update(withFrame: frame,
                                correctionAmount: correction,
                                scale: computedScale)
        }

        if let event = pidInterpolator.event {
            receivingWindow?.sendEvent(event)
        }
        if let debugEvent = debugInterpolator.event, let gaze = debugEvent.allGazes?.first {
            receivingWindow?.cursorView?.debugCursorMoved(gaze, with: debugEvent)
        }
    }

    private var headNode: SCNNode?
    private var faceAnchor: ARFaceAnchor? {
        didSet {
            for interpolator in trackingInterpolators {
                interpolator.faceAnchor = faceAnchor
            }
            let oldTracked = oldValue?.isTracked ?? false
            let newTracked = faceAnchor?.isTracked ?? false
            if oldTracked && !newTracked {
                DispatchQueue.main.async {
                    UIApplication.Storage.isGazeTrackingActive = false
                }
            } else if !oldTracked && newTracked {
                DispatchQueue.main.async {
                    UIApplication.Storage.isGazeTrackingActive = true
                }
            }
        }
    }

    private let axesNode = loadModelFromAsset(named: "axes")

    private func setupSceneNode() {
        headNode?.addChildNode(axesNode)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR session failed")
    }

    /// - Tag: ARNodeTracking
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        self.headNode = node
        setupSceneNode()
    }

    /// - Tag: ARFaceGeometryUpdate
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        self.faceAnchor = anchor as? ARFaceAnchor
        guard let headNode = headNode, let sceneView = sceneview else { return }
        let vector = headNode.convertPosition(SCNVector3Zero, to: sceneView.pointOfView)
        let angleX = vector.angleToReach(SCNVector3Make(1, 0, 0))
        let angleY = vector.angleToReach(SCNVector3Make(0, 1, 0))
        xAngleCorrectionAmount = Double(90 - angleX.radiansToDegrees) / 90.0
        yAngleCorrectionAmount = Double(90 - angleY.radiansToDegrees) / 90.0

        let length = Double(sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z))
        
        let distanceRange = (0.3 ... 0.6) // Distance from camera

        let normalizedLength = min(max((length - distanceRange.lowerBound) / (distanceRange.upperBound - distanceRange.lowerBound), 0.0), 1.0)
        let normalizedScale = 1.0 - normalizedLength
        let scaleValue = (normalizedScale * (scalingRange.upperBound - scalingRange.lowerBound)) + scalingRange.lowerBound
        computedScale = CGFloat(scaleValue)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        if anchor is ARFaceAnchor {
            self.faceAnchor = nil
            self.headNode = nil
        }
    }
}

private func loadModelFromAsset(named assetName: String) -> SCNNode {
    let url = Bundle.main.url(forResource: assetName, withExtension: "scn", subdirectory: "GazeLib.scnassets")
    let node = SCNReferenceNode(url: url!)
    node?.load()
    return node!
}
