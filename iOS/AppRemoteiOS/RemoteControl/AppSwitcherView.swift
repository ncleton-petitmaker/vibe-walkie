import SwiftUI
import RemoteCore

/// Sélecteur d'applications et de fenêtres du Mac.
struct AppSwitcherView: View {
    @EnvironmentObject private var client: HostConnectionClient
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 118), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    if let message = errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding()
                    }

                    let applications = client.snapshot?.applications ?? []
                    if applications.isEmpty && isRefreshing {
                        ProgressView("ios.loading.open.apps.4ba7336")
                            .tint(Color.remoteBlue)
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    } else if applications.isEmpty {
                        Text("ios.no.open.app.detected.e5ef8b2")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(applications) { app in
                                appTile(app)
                            }
                        }
                        .padding(16)
                    }
                }
                .refreshable { await refresh() }
            }
            .navigationTitle("ios.open.apps.af5d137")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ios.close.711e5f2") { dismiss() }
                }
            }
            .task {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--marketing-apps") { return }
#endif
                await refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func appTile(_ app: RemoteApplication) -> some View {
        Button {
            activate(app, window: nil)
        } label: {
            VStack(spacing: 9) {
                if let data = app.iconPNG, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                } else {
                    ApplicationFallbackIcon(app: app)
                        .frame(width: 56, height: 56)
                }

                Text(app.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(app.isActive ? Color.remoteBlue.opacity(0.22) : Color.controlSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(app.isActive ? Color.remoteBlue : .white.opacity(0.07), lineWidth: app.isActive ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            _ = try await client.send(type: .listWindows, payload: ListWindowsPayload())
            errorMessage = nil
        } catch let error as RemoteErrorPayload {
            errorMessage = AppL10n.remoteError(error.code)
        } catch {
            errorMessage = AppL10n.text("ios.could.not.load.apps.from.the.mac.e960e3c")
        }
    }

    private func activate(_ app: RemoteApplication, window: RemoteWindow?) {
        Task {
            do {
                _ = try await client.send(
                    type: .activateWindow,
                    payload: ActivateWindowPayload(applicationID: app.id, windowID: window?.id)
                )
                HapticFeedback.shared.delivered()
                dismiss()
            } catch let error as RemoteErrorPayload {
                // Pas de faux succès : si le Mac n'a pas pu activer la fenêtre,
                // la feuille reste ouverte avec la raison.
                HapticFeedback.shared.failed()
                errorMessage = AppL10n.remoteError(error.code)
            } catch {
                errorMessage = AppL10n.text("ios.the.app.could.not.be.activated.4408c34")
            }
        }
    }
}

/// Icône locale nette lorsque macOS n'a pas encore livré le PNG de l'app.
/// Les symboles restent immédiatement identifiables sans inventer de faux logo.
private struct ApplicationFallbackIcon: View {
    let app: RemoteApplication

    private var style: (symbol: String, colors: [Color]) {
        switch app.bundleIdentifier {
        case "com.apple.Notes":
            return ("note.text", [.yellow, .orange])
        case "com.apple.Safari":
            return ("safari.fill", [.cyan, .blue])
        case "com.apple.mail":
            return ("envelope.fill", [Color(red: 0.20, green: 0.62, blue: 1), .blue])
        case "com.openai.codex":
            return ("sparkles", [Color(red: 0.20, green: 0.22, blue: 0.25), .black])
        case "com.apple.dt.Xcode":
            return ("hammer.fill", [.cyan, .blue])
        case "com.apple.Terminal":
            return ("terminal.fill", [Color(red: 0.22, green: 0.24, blue: 0.27), .black])
        default:
            return ("app.fill", [Color.remoteBlue, .indigo])
        }
    }

    var body: some View {
        let style = style
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: style.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                )

            Image(systemName: style.symbol)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
    }
}
