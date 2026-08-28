import SwiftUI
import RemoteCore

/// Clavier distant en saisie directe.
///
/// Chaque caractère part immédiatement vers le Mac. Le champ local reste vide :
/// il ne sert qu'à capturer les frappes, pas à composer un message. C'est ce
/// qui donne l'impression de taper directement sur l'ordinateur.
struct RemoteKeyboardView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @Environment(\.dismiss) private var dismiss

    /// Sentinelle invisible qui permet à iOS de signaler un effacement même
    /// quand aucun texte visible n'est conservé dans le champ.
    @State private var buffer = "\u{200B}"
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text("Clavier distant")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Ce que vous tapez s'écrit directement sur le Mac.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            TextField("", text: $buffer)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.controlSurface))
                .onChange(of: buffer) { _, newValue in
                    send(newValue)
                }
                .onSubmit {
                    client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: .enter))
                }

            HStack(spacing: 12) {
                keyButton("Échap", key: .escape)
                keyButton("Tab", key: .tab)
                keyButton("Retour", key: .backspace)
                keyButton("Entrée", key: .enter)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            buffer = "\u{200B}"
            isFocused = true
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
                errorMessage = error.message
            } catch {
                errorMessage = "Le texte n'a pas été envoyé au Mac."
            }
        }
    }

    private func keyButton(_ label: String, key: RemoteKey) -> some View {
        Button {
            HapticFeedback.shared.tick()
            client.sendFireAndForget(type: .keyPress, payload: KeyPressPayload(key: key))
        } label: {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(Color.controlSurface))
        }
        .buttonStyle(.plain)
    }
}
