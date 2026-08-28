import SwiftUI

/// Démonstration strictement locale et en lecture seule pour comprendre le
/// produit sans Mac. Aucune connexion ni commande réseau n'est créée.
struct DiscoveryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Button("Fermer") { dismiss() }
                        Spacer()
                        Text("Vibe Remote").font(.headline)
                        Spacer()
                        Text("DÉMO")
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.yellow, in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Découvrez la télécommande")
                            .font(.title2.bold())
                        Text("Cette visite est en lecture seule. Aucune commande n’est envoyée et aucun Mac n’est simulé comme connecté.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.trackpadSurface)
                            .frame(height: 300)
                        VStack(spacing: 12) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 40, weight: .light))
                            Text("Trackpad")
                                .font(.headline)
                            Text("Déplacez le pointeur, cliquez, faites défiler et glissez.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                    }

                    HStack(spacing: 14) {
                        feature("keyboard", "Clavier")
                        feature("mic.fill", "Dictée locale")
                        feature("rectangle.on.rectangle", "Fenêtres")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Audio traité sur l’iPhone", systemImage: "iphone.and.arrow.forward")
                        Label("Connexion directe sur le Wi‑Fi local", systemImage: "wifi")
                        Label("Appairage confirmé sur le Mac", systemImage: "lock.shield")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 20))

                    Button("Installer le compagnon Mac") {
                        UIApplication.shared.open(URL(string: "https://viberemote.app/download")!)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.remoteBlue)
                    .controlSize(.large)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
