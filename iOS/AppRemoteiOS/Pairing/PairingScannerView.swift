import SwiftUI
@preconcurrency import AVFoundation
import RemoteCore

/// Scanner du QR affiché par le Mac.
struct PairingScannerView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var scannedCode: String?
    @State private var scannerPaused = false

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerRepresentable(
                    isPaused: scannerPaused,
                    onScan: handle,
                    onUnavailable: { errorMessage = $0 }
                )
                .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.remoteBlue, lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.4), radius: 4)

                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        if let code = scannedCode {
                            Text("Vérifiez que le Mac affiche")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.7))
                            Text(code)
                                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white)
                            ProgressView()
                                .tint(.white)
                            Text("Connexion sécurisée au Mac…")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            Text("Scannez le code affiché par Vibe Remote sur votre Mac.")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                                Button("Ouvrir les réglages") {
                                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                    UIApplication.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.7)))
                    .padding(24)
                }
            }
            .navigationTitle("Appairer un Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: client.state) { _, newState in
            if newState.isReady { dismiss() }
        }
    }

    private func handle(_ value: String) {
        guard scannedCode == nil else { return }
        do {
            let payload = try PairingQRPayload.decode(value)
            HapticFeedback.shared.tick()
            scannedCode = payload.confirmationCode
            scannerPaused = true
            errorMessage = nil
            try client.pair(with: payload)
        } catch let error as RemoteErrorPayload {
            errorMessage = error.message
            scannedCode = nil
            scannerPaused = false
        } catch {
            errorMessage = "Code non reconnu."
            scannedCode = nil
            scannerPaused = false
        }
    }
}

/// Caméra + détection de QR.
struct QRScannerRepresentable: UIViewControllerRepresentable {
    let isPaused: Bool
    let onScan: (String) -> Void
    let onUnavailable: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onScan = onScan
        controller.onUnavailable = onUnavailable
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {
        uiViewController.setPaused(isPaused)
    }
}

/// Le délégué de capture est déclaré `nonisolated` et repasse explicitement
/// sur le main actor : AVFoundation appelle sur la file fournie, et Swift 6
/// refuse une conformance qui franchirait l'isolation implicitement.
final class QRScannerController: UIViewController {
    var onScan: ((String) -> Void)?
    var onUnavailable: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.nicolascleton.viberemote.camera", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var lastValue: String?
    private var lastScanAt: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // La session s'arrête hors du main actor : `stopRunning` bloque
        // jusqu'à l'arrêt du flux vidéo et figerait l'interface.
        setPaused(true)
    }

    func setPaused(_ paused: Bool) {
        let capture = session
        let configured = isConfigured
        sessionQueue.async {
            if paused {
                if capture.isRunning { capture.stopRunning() }
            } else if configured, !capture.isRunning {
                capture.startRunning()
            }
        }
    }

    private func requestCameraAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.onUnavailable?("Autorisez l'accès à la caméra pour scanner le QR.")
                    }
                }
            }
        default:
            onUnavailable?("Autorisez l'accès à la caméra pour scanner le QR.")
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onUnavailable?("La caméra arrière est indisponible.")
            return
        }

        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            onUnavailable?("Le scanner QR est indisponible.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
        isConfigured = true

        setPaused(false)
    }

}

extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date.timeIntervalSinceReferenceDate
            guard value != self.lastValue || now - self.lastScanAt >= 1 else { return }
            self.lastValue = value
            self.lastScanAt = now
            self.onScan?(value)
        }
    }
}
