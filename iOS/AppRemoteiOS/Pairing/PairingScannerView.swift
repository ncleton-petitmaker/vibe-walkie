import SwiftUI
import PhotosUI
import Vision
@preconcurrency import AVFoundation
import RemoteCore

/// Scanner du QR affiché par le Mac.
struct PairingScannerView: View {
    @EnvironmentObject private var client: HostConnectionClient
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var scannedCode: String?
    @State private var scannerPaused = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCodeEntry = false
    @State private var enteredCode = ""
    @State private var zoomFactor: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerRepresentable(
                    isPaused: scannerPaused,
                    zoomFactor: zoomFactor,
                    onScan: handle,
                    onUnavailable: { errorMessage = $0 },
                    onZoomChanged: { zoomFactor = $0 }
                )
                .ignoresSafeArea()

                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.remoteBlue, lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .shadow(color: .black.opacity(0.4), radius: 4)

                VStack {
                    if scannedCode == nil {
                        HStack(spacing: 10) {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(.white.opacity(0.8))

                            Slider(value: $zoomFactor, in: 1...8)
                                .tint(.white)

                            Text(verbatim: String(format: "%.1f×", zoomFactor))
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 250)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.top, 12)
                    }

                    Spacer()
                    VStack(spacing: 10) {
                        if let code = scannedCode {
                            if case .awaitingApproval(let hostName, _) = client.state {
                                Label("ios.approval.required.b4ebf21", systemImage: "hand.raised.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text(AppL10n.text("ios.approval.required.b4ebf21"))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("ios.check.that.the.mac.displays.cd8279f")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Text(code)
                                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                                .foregroundStyle(.white)
                            ProgressView()
                                .tint(.white)
                            if case .awaitingApproval = client.state {
                                EmptyView()
                            } else {
                                Text("ios.securing.connection.to.the.mac.03596b1")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        } else {
                            Text("ios.scan.the.code.shown.by.vibe.walkie.on.your.mac.bf54c4e")
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
                                Button("ios.open.settings.5709195") {
                                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                                    UIApplication.shared.open(url)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        HStack(spacing: 10) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("ios.qr.photo.3e3d441", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                enteredCode = UIPasteboard.general.string ?? ""
                                showCodeEntry = true
                            } label: {
                                Label("ios.paste.code.26db0cb", systemImage: "doc.on.clipboard")
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
            .navigationTitle("ios.pair.a.mac.e22b20b")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ios.cancel.46ad391") { dismiss() }
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
                        TextField("ios.pairing.code.5c965f1", text: $enteredCode, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(4...10)
                    } footer: {
                        Text("ios.the.code.stays.between.your.devices.it.is.never.opened.766e735")
                    }
                }
                .navigationTitle("ios.remote.code.7e49a94")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ios.cancel.46ad391") { showCodeEntry = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("ios.connect.2a10fee") {
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
            errorMessage = AppL10n.text("ios.code.not.recognized.a3072c8")
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
            errorMessage = AppL10n.text("ios.no.readable.vibe.walkie.qr.code.was.found.in.this.1aa954c")
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
    let zoomFactor: CGFloat
    let onScan: (String) -> Void
    let onUnavailable: (String) -> Void
    let onZoomChanged: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onScan = onScan
        controller.onUnavailable = onUnavailable
        controller.onZoomChanged = onZoomChanged
        controller.setZoomFactor(zoomFactor)
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {
        uiViewController.onScan = onScan
        uiViewController.onUnavailable = onUnavailable
        uiViewController.onZoomChanged = onZoomChanged
        uiViewController.setPaused(isPaused)
        uiViewController.setZoomFactor(zoomFactor)
    }
}

/// Le délégué de capture est déclaré `nonisolated` et repasse explicitement
/// sur le main actor : AVFoundation appelle sur la file fournie, et Swift 6
/// refuse une conformance qui franchirait l'isolation implicitement.
final class QRScannerController: UIViewController {
    var onScan: ((String) -> Void)?
    var onUnavailable: ((String) -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.nicolascleton.viberemote.camera", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private weak var captureDevice: AVCaptureDevice?
    private var isConfigured = false
    private var lastValue: String?
    private var lastScanAt: TimeInterval = 0
    private var zoomFactor: CGFloat = 1
    private var zoomFactorAtPinchStart: CGFloat = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
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

    func setZoomFactor(_ requestedFactor: CGFloat) {
        zoomFactor = requestedFactor
        guard let device = captureDevice else { return }

        let minimum = max(CGFloat(1), device.minAvailableVideoZoomFactor)
        let maximum = min(CGFloat(8), device.maxAvailableVideoZoomFactor)
        let clampedFactor = min(max(requestedFactor, minimum), maximum)

        guard abs(device.videoZoomFactor - clampedFactor) > 0.01,
              (try? device.lockForConfiguration()) != nil else { return }
        device.videoZoomFactor = clampedFactor
        device.unlockForConfiguration()

        zoomFactor = clampedFactor
        if abs(requestedFactor - clampedFactor) > 0.01 {
            onZoomChanged?(clampedFactor)
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            zoomFactorAtPinchStart = zoomFactor
        case .changed:
            let requestedFactor = zoomFactorAtPinchStart * gesture.scale
            setZoomFactor(requestedFactor)
            onZoomChanged?(zoomFactor)
        default:
            break
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
                        self.onUnavailable?(AppL10n.text("ios.unavailable.3f0806b"))
                    }
                }
            }
        default:
            onUnavailable?(AppL10n.text("ios.unavailable.3f0806b"))
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onUnavailable?(AppL10n.text("ios.unavailable.3f0806b"))
            return
        }
        captureDevice = device

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
        setZoomFactor(zoomFactor)

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
