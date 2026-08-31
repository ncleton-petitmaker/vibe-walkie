import SwiftUI
import PhotosUI
import Vision
@preconcurrency import AVFoundation
import RemoteCore

/// Scanner du QR affiché par le Mac.
struct PairingScannerView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var scannedCode: String?
    @State private var scannerPaused = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCodeEntry = false
    @State private var enteredCode = ""

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
                            if case .awaitingApproval(let macName, _) = client.state {
                                Label("Autorisation requise", systemImage: "hand.raised.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text("Sur \(macName), cliquez sur « Autoriser ».")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Vérifiez que le Mac affiche")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Text(code)
                                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white)
                            ProgressView()
                                .tint(.white)
                            if case .awaitingApproval = client.state {
                                Text("Cette confirmation protège le contrôle à distance du Mac.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Connexion sécurisée au Mac…")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        } else {
                            Text("Scannez le code affiché par Vibe Walkie sur votre Mac.")
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

                        HStack(spacing: 10) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Photo du QR", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                enteredCode = UIPasteboard.general.string ?? ""
                                showCodeEntry = true
                            } label: {
                                Label("Coller le code", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption.weight(.semibold))
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
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            scannerPaused = true
            Task { await importQRCode(from: item) }
        }
        .onChange(of: client.state) { _, newState in
            if newState.isReady {
                dismiss()
            } else if case .failed(let error) = newState {
                errorMessage = AppL10n.remoteError(error)
                scannedCode = nil
                scannerPaused = false
            }
        }
        .onDisappear {
            if !client.state.isReady {
                client.cancelPairing()
            }
        }
        .sheet(isPresented: $showCodeEntry) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Code d’appairage", text: $enteredCode, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(4...10)
                    } footer: {
                        Text("Le code reste entre vos appareils. Il n’est jamais ouvert dans un navigateur.")
                    }
                }
                .navigationTitle("Code Nomade")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { showCodeEntry = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Connecter") {
                            showCodeEntry = false
                            handle(enteredCode.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .disabled(enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .presentationDetents([.medium])
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
            errorMessage = AppL10n.remoteError(error.code)
            scannedCode = nil
            scannerPaused = false
        } catch {
            errorMessage = AppL10n.text("Code non reconnu.")
            scannedCode = nil
            scannerPaused = false
        }
    }

    private func importQRCode(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let ciImage = CIImage(image: image) else {
                throw QRImportError.unreadable
            }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            let handler = VNImageRequestHandler(ciImage: ciImage)
            try handler.perform([request])
            guard let value = request.results?.first?.payloadStringValue else {
                throw QRImportError.missingCode
            }
            handle(value)
        } catch {
            errorMessage = AppL10n.text("Aucun QR Vibe Walkie lisible dans cette image.")
            scannedCode = nil
            scannerPaused = false
        }
        selectedPhoto = nil
    }
}

private enum QRImportError: Error {
    case unreadable
    case missingCode
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
