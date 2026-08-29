import SwiftUI
import RemoteCore

struct SettingsSheet: View {
    @EnvironmentObject private var client: MacConnectionClient
    @EnvironmentObject private var history: TranscriptHistoryStore
    @ObservedObject var dictation: DictationController
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @AppStorage("trackpadSensitivity") private var trackpadSensitivity: Double = 1.6
    @AppStorage("scrollSensitivity") private var scrollSensitivity: Double = 0.8
    @AppStorage("screenQuality") private var screenQuality: Double = 0.45
    @AppStorage("screenFrameRate") private var screenFrameRate: Double = 10

    var body: some View {
        NavigationStack {
            List {
                Section("Connexion") {
                    LabeledContent("État", value: statusText)
                    if !client.accessibilityGranted {
                        Label("Accessibilité désactivée sur le Mac", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    if client.isPaired {
                        Button("Oublier ce Mac", role: .destructive) { client.forgetMac() }
                    } else {
                        Button("Appairer un Mac") { showScanner = true }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Vitesse du curseur") {
                            Text("\(trackpadSensitivity, specifier: "%.2g")×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $trackpadSensitivity, in: 0.5...3.0, step: 0.1) {
                            Text("Vitesse du curseur")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Vitesse du défilement") {
                            Text("\(scrollSensitivity, specifier: "%.2g")×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $scrollSensitivity, in: 0.2...2.0, step: 0.1) {
                            Text("Vitesse du défilement")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                } header: {
                    Text("Pavé tactile")
                } footer: {
                    Text("Le curseur et le défilement se règlent indépendamment.")
                }

                Section {
                    LabeledContent("Connexion actuelle") {
                        Label(
                            "Réseau local",
                            systemImage: "wifi"
                        )
                        .foregroundStyle(client.state.isReady ? .green : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Qualité de l’écran") {
                            Text("\(Int(screenQuality * 100)) %")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $screenQuality, in: 0.25...0.7, step: 0.05)
                    }

                    Picker("Fluidité", selection: $screenFrameRate) {
                        Text("Économie · 6 i/s").tag(6.0)
                        Text("Équilibré · 10 i/s").tag(10.0)
                        Text("Fluide · 15 i/s").tag(15.0)
                    }

                } header: {
                    Text("Retour écran")
                } footer: {
                    Text("Le retour écran facultatif reste chiffré entre l’iPhone et le Mac sur votre réseau local.")
                }

                Section {
                    Toggle("Conserver l'historique", isOn: $history.isEnabled)
                    if !history.entries.isEmpty {
                        Button("Tout effacer", role: .destructive) { history.clear() }
                    }
                } header: {
                    Text("Historique")
                } footer: {
                    Text("Les transcriptions restent sur cet iPhone, jamais sur le Mac. Elles sont supprimées après 7 jours.")
                }

                if !history.entries.isEmpty {
                    Section("Dernières dictées") {
                        ForEach(history.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.text).font(.callout).lineLimit(3)
                                HStack(spacing: 6) {
                                    Text(entry.createdAt, style: .time)
                                    Text("·")
                                    Text(label(for: entry))
                                }
                                .font(.caption2)
                                .foregroundStyle(color(for: entry.delivery))
                            }
                            .swipeActions {
                                Button("Supprimer", role: .destructive) { history.remove(entry.id) }
                                Button("Renvoyer") {
                                    dictation.resend(entry)
                                    dismiss()
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vibe Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(isPresented: $showScanner) {
                PairingScannerView().environmentObject(client)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statusText: String {
        switch client.state {
        case .ready(let name): return "Connecté à \(name)"
        case .connecting(let name): return "Connexion à \(name)…"
        case .pairing(let name, let code): return "Appairage \(name) · \(code)"
        case .awaitingApproval(let name, let code): return "Autorisez \(name) sur le Mac · \(code)"
        case .searching: return "Recherche…"
        case .failed(let code): return code.localizedMessage
        case .idle: return "Aucun Mac appairé"
        }
    }

    private func label(for entry: TranscriptEntry) -> String {
        switch entry.delivery {
        case .delivered: return entry.applicationName.map { "Inséré dans \($0)" } ?? "Inséré"
        case .notSent: return "Non envoyé"
        case .unknown: return "Résultat inconnu"
        case .pending: return "En cours"
        case .failed: return "Échec"
        }
    }

    private func color(for state: DeliveryState) -> Color {
        switch state {
        case .delivered: return .green
        case .unknown: return .orange
        case .notSent, .failed: return .red
        case .pending: return .secondary
        }
    }
}
