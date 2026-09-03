import SwiftUI
import RemoteCore

enum KeyboardInputMode: String, CaseIterable, Identifiable {
    static let storageKey = "keyboardInputMode"

    case direct
    case corrected

    var id: Self { self }

    var title: String {
        switch self {
        case .direct: AppL10n.text("ios.direct.002c7c6")
        case .corrected: AppL10n.text("ios.editor.b2ded81")
        }
    }

    var systemImage: String {
        switch self {
        case .direct: "bolt.fill"
        case .corrected: "text.badge.checkmark"
        }
    }
}

/// Clavier distant proposant une frappe immédiate ou un brouillon corrigé.
struct RemoteKeyboardView: View {
    enum Presentation {
        case sheet
        case inline
    }

    @EnvironmentObject private var client: HostConnectionClient

    var presentation: Presentation = .sheet

    @AppStorage(KeyboardInputMode.storageKey) private var inputMode: KeyboardInputMode = .direct

    /// Sentinelle invisible qui permet à iOS de signaler un effacement même
    /// quand aucun texte visible n'est conservé dans le champ.
    @State private var buffer = "\u{200B}"
    @State private var draft = ""
    @State private var isSendingDraft = false
    @State private var deliveryMessage: String?
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                sheetContent
            case .inline:
                inlineContent
            }
        }
        .toolbar {
            if presentation == .inline, inputMode == .direct {
                ToolbarItemGroup(placement: .keyboard) {
                    keyboardToolbar
                }
            }
        }
        .onAppear {
            buffer = "\u{200B}"
            Task { @MainActor in
                isFocused = true
            }
        }
        .onChange(of: inputMode) { _, _ in
            buffer = "\u{200B}"
            errorMessage = nil
            deliveryMessage = nil
            Task { @MainActor in
                isFocused = true
            }
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Label(
                AppL10n.text(inputMode == .direct
                    ? "ios.direct.002c7c6"
                    : "ios.editor.b2ded81"),
                systemImage: inputMode.systemImage
            )
                .font(.headline)
                .foregroundStyle(.white)

            statusMessage

            if inputMode == .direct {
                directInputField
                    .foregroundStyle(.white)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.controlSurface))

                HStack(spacing: 12) {
                    keyButton("ios.esc.7bd72d1", key: .escape)
                    keyButton("ios.tab.90ddf19", key: .tab)
                    keyButton("ios.backspace.ff7e715", key: .backspace)
                    keyButton("ios.return.d9c7efe", key: .enter)
                }
            } else {
                composer
                draftActions
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private var inlineContent: some View {
        if inputMode == .direct {
            directInputField
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Label("ios.editable.draft.038347c", systemImage: inputMode.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                }

                composer
                draftActions
                statusMessage
            }
            .padding(12)
            .background(Color.controlSurface)
        }
    }

    private var directInputField: some View {
        TextField("", text: $buffer)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: buffer) { _, newValue in
                send(newValue)
            }
            .onSubmit {
                sendKey(.enter)
            }
    }

    private var composer: some View {
        TextField("ios.type.your.text.e0e35fa", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .autocorrectionDisabled(false)
            .textInputAutocapitalization(.sentences)
            .lineLimit(3...7)
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .disabled(isSendingDraft)
            .accessibilityLabel("ios.draft.to.send.to.the.mac.529af97")
            .onChange(of: draft) { _, newValue in
                guard newValue.count > 512 else { return }
                draft = String(newValue.prefix(512))
            }
    }

    private var draftActions: some View {
        HStack(spacing: 12) {
            Button("ios.clear.e4750da", role: .destructive) {
                draft = ""
                deliveryMessage = nil
                errorMessage = nil
            }
            .disabled(draft.isEmpty || isSendingDraft)

            Spacer()
            characterCount

            Button {
                sendDraft()
            } label: {
                if isSendingDraft {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("ios.send.7907520", systemImage: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.remoteBlue)
            .disabled(draft.isEmpty || isSendingDraft)
        }
    }

    private var characterCount: some View {
        Text("\(draft.count)/512")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.48))
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else if let deliveryMessage {
            Label(deliveryMessage, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var keyboardToolbar: some View {
        Button {
            sendKey(.escape)
        } label: {
            Label("ios.esc.7bd72d1", systemImage: "escape")
        }

        Button {
            sendKey(.tab)
        } label: {
            Label("ios.tab.90ddf19", systemImage: "arrow.right.to.line")
        }
    }

    /// N'envoie que ce qui vient d'être ajouté.
    ///
    /// Une suppression est traduite en touche Retour arrière plutôt qu'en
    /// réécriture du champ : réécrire écraserait ce que l'utilisateur a tapé
    /// directement sur le Mac entre-temps.
    private func send(_ newValue: String) {
        let marker = "\u{200B}"
        guard newValue != marker else { return }

        if newValue.isEmpty {
            buffer = marker
            client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: .backspace))
            return
        }

        let text = newValue.hasPrefix(marker) ? String(newValue.dropFirst()) : newValue
        buffer = marker
        guard !text.isEmpty else { return }
        Task {
            do {
                _ = try await client.send(
                    type: .keyboardText,
                    payload: KeyboardTextPayload(text: text, userInitiated: true)
                )
                errorMessage = nil
            } catch let error as RemoteErrorPayload {
                errorMessage = AppL10n.remoteError(error.code)
            } catch {
                errorMessage = AppL10n.text("ios.the.text.was.not.sent.to.the.mac.8f573c5")
            }
        }
    }

    private func keyButton(_ label: String, key: RemoteKey) -> some View {
        Button {
            sendKey(key)
        } label: {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Color.controlSurface))
        }
        .buttonStyle(.plain)
    }

    private func sendKey(_ key: RemoteKey) {
        HapticFeedback.shared.tick()
        client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: key))
    }

    private func sendDraft() {
        guard !draft.isEmpty, !isSendingDraft else { return }
        let text = draft
        isSendingDraft = true
        errorMessage = nil
        deliveryMessage = nil
        HapticFeedback.shared.tick()

        Task {
            do {
                _ = try await client.send(
                    type: .keyboardText,
                    payload: KeyboardTextPayload(text: text, userInitiated: true)
                )
                draft = ""
                deliveryMessage = AppL10n.text("ios.text.sent.to.the.mac.0ed5c3d")
            } catch let error as RemoteErrorPayload {
                errorMessage = AppL10n.remoteError(error.code)
            } catch {
                errorMessage = AppL10n.text("ios.the.text.was.not.sent.to.the.mac.8f573c5")
            }
            isSendingDraft = false
        }
    }
}
