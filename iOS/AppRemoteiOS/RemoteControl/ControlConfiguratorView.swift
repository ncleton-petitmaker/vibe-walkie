import SwiftUI
import PhotosUI
import RemoteCore
import UIKit

struct ControlConfiguratorView: View {
    @EnvironmentObject private var client: MacConnectionClient
    @State private var selectedZone: ControlZone?
    @State private var showResetConfirmation = false
    @State private var showGlobalOrder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Bloc de boutons")
                        .font(.title2.bold())
                    Text("Touchez une zone pour choisir sa touche, son nom et son icône. Le bouton Push‑to‑Talk reste toujours au centre.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ControlLayoutEditorPreview(configuration: client.controlConfiguration) { zone in
                    selectedZone = zone
                }

                Button {
                    showGlobalOrder = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.grid.2x2.fill")
                            .font(.title3)
                            .foregroundStyle(Color.remoteBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bulle Global")
                                .font(.headline)
                            Text("Ordonner les commandes non visibles")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: -4) {
                            ForEach(client.controlConfiguration.availableGlobalButtons.prefix(4)) { button in
                                ControlIconImage(icon: button.icon)
                                    .frame(width: 14, height: 14)
                                    .padding(7)
                                    .background(Color.controlSurface, in: Circle())
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Label(
                    client.state.isReady
                        ? "Les changements sont synchronisés avec ce Mac."
                        : "Les changements seront envoyés au Mac à la prochaine connexion.",
                    systemImage: client.state.isReady ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Raccourcis Mac")
                        .font(.headline)
                    Text("Sur l’iPhone, vous pouvez affecter les touches standard. Pour enregistrer n’importe quelle combinaison — par exemple ⌘⇧K — ouvrez les réglages de Vibe Walkie sur le Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button("Revenir aux boutons d’origine", role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Commandes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedZone) { zone in
            NavigationStack {
                IOSControlButtonEditor(button: client.controlConfiguration.button(in: zone)) { button in
                    var configuration = client.controlConfiguration
                    configuration.setButton(button)
                    client.updateControlConfiguration(configuration)
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showGlobalOrder) {
            NavigationStack {
                GlobalButtonOrderView(
                    configuration: client.controlConfiguration,
                    save: { order in
                        var configuration = client.controlConfiguration
                        configuration.setAvailableGlobalButtonOrder(order)
                        client.updateControlConfiguration(configuration)
                    }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Réinitialiser le bloc ?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rétablir les boutons d’origine", role: .destructive) {
                client.resetControlConfiguration()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les raccourcis et icônes personnalisés de ces sept zones seront remplacés.")
        }
    }
}

private struct GlobalButtonOrderView: View {
    @Environment(\.dismiss) private var dismiss
    let configuration: ControlConfiguration
    let save: ([GlobalButtonConfiguration]) -> Void
    @State private var order: [GlobalButtonConfiguration]

    init(configuration: ControlConfiguration, save: @escaping ([GlobalButtonConfiguration]) -> Void) {
        self.configuration = configuration
        self.save = save
        _order = State(initialValue: configuration.availableGlobalButtons)
    }

    var body: some View {
        List {
            Section {
                ForEach(order) { button in
                    HStack(spacing: 12) {
                        ControlIconImage(icon: button.icon)
                            .frame(width: 20, height: 20)
                            .frame(width: 36, height: 36)
                            .background(Color.remoteBlue.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(button.title)
                                .font(.body.weight(.semibold))
                            Text(button.action.globalDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { offsets, destination in
                    order.move(fromOffsets: offsets, toOffset: destination)
                    save(order)
                }
            } header: {
                Text("Maintenez la poignée puis faites glisser")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Ordre de Global")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Terminé") { dismiss() }
            }
        }
    }
}

private struct ControlLayoutEditorPreview: View {
    let configuration: ControlConfiguration
    let select: (ControlZone) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                sideColumn([.upperLeft, .lowerLeft])

                VStack(spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(Color.remoteBlue, in: Circle())
                    Label("PTT verrouillé", systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                sideColumn([.upperRight, .lowerRight])
            }

            HStack(spacing: 8) {
                zoneButton(.bottomLeft)
                zoneButton(.bottomCenter)
                zoneButton(.bottomRight)
            }
        }
        .padding(14)
        .background(Color.controlSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func sideColumn(_ zones: [ControlZone]) -> some View {
        VStack(spacing: 8) {
            ForEach(zones) { zone in zoneButton(zone) }
        }
        .frame(maxWidth: .infinity)
    }

    private func zoneButton(_ zone: ControlZone) -> some View {
        let button = configuration.button(in: zone)
        return Button { select(zone) } label: {
            VStack(spacing: 5) {
                ControlIconImage(icon: button.icon)
                    .frame(width: 22, height: 22)
                Text(button.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.remoteBlue)
                    .padding(5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modifier (button.title)")
    }
}

private struct IOSControlButtonEditor: View {
    private enum ActionChoice: String, CaseIterable, Identifiable {
        case standard
        case showKeyboard
        case none
        case macShortcut

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let original: ControlButtonConfiguration
    let save: (ControlButtonConfiguration) -> Void

    @State private var title: String
    @State private var icon: ControlButtonIcon
    @State private var actionChoice: ActionChoice
    @State private var standardKey: RemoteKey
    @State private var retainedMacShortcut: MacKeyboardShortcut?
    @State private var photoItem: PhotosPickerItem?

    init(button: ControlButtonConfiguration, save: @escaping (ControlButtonConfiguration) -> Void) {
        original = button
        self.save = save
        _title = State(initialValue: button.title)
        _icon = State(initialValue: button.icon)

        switch button.action {
        case .standardKey(let key):
            _actionChoice = State(initialValue: .standard)
            _standardKey = State(initialValue: key)
            _retainedMacShortcut = State(initialValue: nil)
        case .showKeyboard:
            _actionChoice = State(initialValue: .showKeyboard)
            _standardKey = State(initialValue: .enter)
            _retainedMacShortcut = State(initialValue: nil)
        case .macShortcut(let shortcut):
            _actionChoice = State(initialValue: .macShortcut)
            _standardKey = State(initialValue: .enter)
            _retainedMacShortcut = State(initialValue: shortcut)
        case .none:
            _actionChoice = State(initialValue: .none)
            _standardKey = State(initialValue: .enter)
            _retainedMacShortcut = State(initialValue: nil)
        }
    }

    var body: some View {
        Form {
            Section("Zone") {
                LabeledContent("Emplacement", value: original.zone.localizedName)
                TextField("Nom du bouton", text: $title)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Action") {
                Picker("Type", selection: $actionChoice) {
                    Text("Touche standard").tag(ActionChoice.standard)
                    Text("Afficher le clavier").tag(ActionChoice.showKeyboard)
                    Text("Aucune action").tag(ActionChoice.none)
                    if retainedMacShortcut != nil {
                        Text("Raccourci enregistré sur le Mac").tag(ActionChoice.macShortcut)
                    }
                }

                if actionChoice == .standard {
                    Picker("Touche", selection: $standardKey) {
                        ForEach(RemoteKey.allCases, id: \.self) { key in
                            Label(key.localizedName, systemImage: key.suggestedSystemImage)
                                .tag(key)
                        }
                    }
                } else if actionChoice == .macShortcut, let retainedMacShortcut {
                    LabeledContent("Combinaison", value: retainedMacShortcut.displayName)
                    Text("Ce raccourci matériel peut être remplacé depuis le Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Icône") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(ControlIconCatalog.systemImages, id: \.self) { name in
                        Button {
                            icon = .system(name)
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(isSelected(name) ? Color.remoteBlue : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Importer une autre icône", systemImage: "photo.badge.plus")
                }
            }
        }
        .navigationTitle("Modifier le bouton")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") {
                    save(ControlButtonConfiguration(
                        zone: original.zone,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sans titre" : title,
                        icon: icon,
                        action: selectedAction
                    ))
                    dismiss()
                }
            }
        }
        .task(id: photoItem) {
            guard let data = try? await photoItem?.loadTransferable(type: Data.self),
                  let normalized = IconImageNormalizer.normalizedData(from: data) else { return }
            icon = .customImage(normalized)
        }
    }

    private var selectedAction: ControlButtonAction {
        switch actionChoice {
        case .standard: return .standardKey(standardKey)
        case .showKeyboard: return .showKeyboard
        case .none: return .none
        case .macShortcut:
            return retainedMacShortcut.map(ControlButtonAction.macShortcut) ?? .none
        }
    }

    private func isSelected(_ name: String) -> Bool {
        guard case .system(let selected) = icon else { return false }
        return selected == name
    }
}

struct ControlIconImage: View {
    let icon: ControlButtonIcon

    var body: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .resizable()
                .scaledToFit()
        case .customImage(let data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
            }
        }
    }
}

enum ControlIconCatalog {
    static let systemImages = [
        "keyboard", "return", "space", "delete.left", "escape", "tab.key",
        "command", "option", "control", "shift", "globe", "fn",
        "arrow.up", "arrow.down", "arrow.left", "arrow.right", "arrow.uturn.backward",
        "doc.on.doc", "doc.on.clipboard", "scissors", "magnifyingglass", "square.and.arrow.up",
        "play.fill", "pause.fill", "backward.fill", "forward.fill", "speaker.wave.2.fill",
        "mic.fill", "camera.fill", "lock.fill", "moon.fill", "sun.max.fill",
        "app", "rectangle.on.rectangle", "arrow.left.arrow.right", "plus", "star.fill"
    ]
}

private enum IconImageNormalizer {
    static func normalizedData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: 96, height: 96)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = min(size.width / image.size.width, size.height / image.size.height)
            let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (size.width - target.width) / 2,
                y: (size.height - target.height) / 2,
                width: target.width,
                height: target.height
            ))
        }
        guard let png = rendered.pngData(), png.count <= 40 * 1_024 else {
            guard let jpeg = rendered.jpegData(compressionQuality: 0.72), jpeg.count <= 40 * 1_024 else {
                guard let compact = rendered.jpegData(compressionQuality: 0.45), compact.count <= 40 * 1_024 else {
                    return nil
                }
                return compact
            }
            return jpeg
        }
        return png
    }
}

extension ControlZone {
    var localizedName: String {
        switch self {
        case .upperLeft: return AppL10n.text("En haut à gauche")
        case .lowerLeft: return AppL10n.text("En bas à gauche")
        case .upperRight: return AppL10n.text("En haut à droite")
        case .lowerRight: return AppL10n.text("En bas à droite")
        case .bottomLeft: return AppL10n.text("Rangée basse · gauche")
        case .bottomCenter: return AppL10n.text("Rangée basse · centre")
        case .bottomRight: return AppL10n.text("Rangée basse · droite")
        }
    }
}

extension RemoteKey {
    var localizedName: String {
        switch self {
        case .enter: return AppL10n.text("Entrée")
        case .escape: return AppL10n.text("Échap")
        case .tab: return AppL10n.text("Tabulation")
        case .applicationSwitcher: return AppL10n.text("Application précédente")
        case .nextConversation: return AppL10n.text("Conversation ou onglet suivant")
        case .backspace: return AppL10n.text("Effacement arrière")
        case .delete: return AppL10n.text("Supprimer")
        case .arrowUp: return AppL10n.text("Flèche haut")
        case .arrowDown: return AppL10n.text("Flèche bas")
        case .arrowLeft: return AppL10n.text("Flèche gauche")
        case .arrowRight: return AppL10n.text("Flèche droite")
        case .space: return AppL10n.text("Espace")
        case .copy: return AppL10n.text("Copier")
        case .paste: return AppL10n.text("Coller")
        case .cut: return AppL10n.text("Couper")
        }
    }

    var suggestedSystemImage: String {
        switch self {
        case .enter: return "return"
        case .escape: return "escape"
        case .tab: return "arrow.right.to.line"
        case .applicationSwitcher: return "arrow.left.arrow.right"
        case .nextConversation: return "arrow.right.to.line"
        case .backspace: return "delete.left"
        case .delete: return "delete.right"
        case .arrowUp: return "arrow.up"
        case .arrowDown: return "arrow.down"
        case .arrowLeft: return "arrow.left"
        case .arrowRight: return "arrow.right"
        case .space: return "space"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .cut: return "scissors"
        }
    }
}

private extension ControlButtonAction {
    var globalDescription: String {
        switch self {
        case .none: return AppL10n.text("À configurer")
        case .standardKey(let key): return key.localizedName
        case .macShortcut(let shortcut): return shortcut.displayName
        case .showKeyboard: return AppL10n.text("Clavier de l’iPhone")
        }
    }
}
