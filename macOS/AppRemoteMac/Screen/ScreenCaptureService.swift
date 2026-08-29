import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ScreenCaptureKit
import RemoteCore

enum ScreenCaptureServiceError: LocalizedError {
    case permissionDenied
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Autorisez l’enregistrement de l’écran sur le Mac, puis relancez Vibe Walkie."
        case .noDisplay:
            return "L’écran du Mac est verrouillé ou indisponible. Déverrouillez la session Mac pour reprendre le contrôle."
        }
    }
}

/// Capture l'écran principal et produit des JPEG bornés, faciles à transmettre
/// sur la connexion TLS existante. La file dédiée et le saut de frames évitent
/// que l'encodage d'image ne ralentisse les commandes souris/clavier.
final class ScreenCaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let frameQueue = DispatchQueue(label: "com.nicolascleton.viberemote.screen", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    private var stream: SCStream?
    private var powerActivity: NSObjectProtocol?
    private var frameHandler: (@Sendable (ScreenFramePayload) -> Void)?
    private var stoppedHandler: (@Sendable (Error) -> Void)?
    private var jpegQuality = 0.45
    private var minimumFrameInterval: TimeInterval = 0.1
    private var lastFrameAt = Date.distantPast

    func start(
        request: ScreenStreamRequestPayload,
        frameHandler: @escaping @Sendable (ScreenFramePayload) -> Void,
        stoppedHandler: @escaping @Sendable (Error) -> Void
    ) async throws {
        await stop()

        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw ScreenCaptureServiceError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw ScreenCaptureServiceError.noDisplay
        }

        let settings = try ControlInputPolicy.screenSettings(for: request)
        let dimensions = settings.dimensions(displayWidth: display.width, displayHeight: display.height)

        let configuration = SCStreamConfiguration()
        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.framesPerSecond))
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)

        self.jpegQuality = settings.jpegQuality
        self.minimumFrameInterval = 1 / Double(settings.framesPerSecond)
        self.lastFrameAt = .distantPast
        self.frameHandler = frameHandler
        self.stoppedHandler = stoppedHandler
        self.stream = stream
        try await stream.startCapture()
        powerActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Vibe Walkie diffuse l’écran vers un iPhone autorisé"
        )
    }

    func stop() async {
        let previous = stream
        stream = nil
        frameHandler = nil
        stoppedHandler = nil
        if let previous { try? await previous.stopCapture() }
        if let powerActivity {
            ProcessInfo.processInfo.endActivity(powerActivity)
            self.powerActivity = nil
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              sampleBuffer.isValid,
              Date().timeIntervalSince(lastFrameAt) >= minimumFrameInterval,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let frameHandler else { return }

        lastFrameAt = Date()
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let jpeg = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: [
                    CIImageRepresentationOption(
                        rawValue: kCGImageDestinationLossyCompressionQuality as String
                    ): jpegQuality
                ]
            ), jpeg.count < ProtocolLimits.maxFrameBytes / 2 else { return }

            frameHandler(ScreenFramePayload(
                jpegData: jpeg,
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[VibeWalkie] Capture écran arrêtée : %@", error.localizedDescription)
        guard self.stream === stream else { return }
        stoppedHandler?(error)
    }
}
