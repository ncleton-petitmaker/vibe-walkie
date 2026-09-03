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
                        Button("ios.close.711e5f2") { dismiss() }
                        Spacer()
                        Text("ios.vibe.walkie.111e6dd").font(.headline)
                        Spacer()
                        Text("ios.demo.17dc034")
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.yellow, in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ios.explore.the.remote.6996aae")
                            .font(.title2.bold())
                        Text("ios.this.tour.is.read.only.no.command.is.sent.and.cb7442d")
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
                            Text("ios.trackpad.2fb1077")
                                .font(.headline)
                            Text("ios.move.the.pointer.click.scroll.and.drag.395a9bc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(32)
                    }

                    HStack(spacing: 14) {
                        feature("keyboard", "ios.keyboard.cd896f5")
                        feature("mic.fill", "ios.local.dictation")
                        feature("rectangle.on.rectangle", "ios.windows")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("ios.audio.processed.on.iphone.efd47c9", systemImage: "iphone.and.arrow.forward")
                        Label("ios.direct.connection.over.local.wi.fi.288e49d", systemImage: "wifi")
                        Label("ios.pairing.confirmed.on.the.mac.3d6d8bb", systemImage: "lock.shield")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 20))

                    Button("ios.install.mac.companion.382f963") {
                        UIApplication.shared.open(URL(string: "https://vibewalkie.app/download")!)
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
            Text(LocalizedStringKey(title)).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
