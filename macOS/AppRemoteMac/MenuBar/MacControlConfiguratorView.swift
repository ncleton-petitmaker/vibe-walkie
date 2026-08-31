import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RemoteCore

struct MacControlConfiguratorView: View {
    @EnvironmentObject private var server: MacConnectionServer
    @Environment(\.dismiss) private var dismiss
    @State private var selectedZone: ControlZone = .upperLeft
    @State private var showResetConfirmation = false
    @State private var showGlobalOrder = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Commandes de l’iPhone")
                        .font(.headline)
                    Text("Choisissez une zone, puis son action et son icône.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(0.07), in: Circle())
                .help("Fermer")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("APERÇU SUR L’IPHONE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)

                    MacControlLayoutPreview(
                        configuration: server.controlConfiguration,
                        selectedZone: selectedZone
                    ) { zone in
                        selectedZone = zone
                    }

                    Button {
                        showGlobalOrder = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.grid.2x2.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Bulle Global")
                                    .font(.caption.weight(.semibold))
                                Text("Modifier l’ordre")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(9)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(width: 232)
                .frame(maxHeight: .infinity, alignment: .top)

                Divider()

                MacControlButtonEditor(button: server.controlConfiguration.button(in: selectedZone)) { button in
                    var configuration = server.controlConfiguration
                    configuration.setButton(button)
                    server.updateControlConfiguration(configuration)
                }
                .id(selectedZone)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack(spacing: 8) {
                Image(systemName: server.connectedPeerName == nil ? "iphone.slash" : "iphone.radiowaves.left.and.right")
                    .foregroundStyle(server.connectedPeerName == nil ? Color.secondary : Color.green)
                Text(server.connectedPeerName.map { "Synchronisé avec \($0)" } ?? "La configuration sera synchronisée à la prochaine connexion")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Réinitialiser", role: .destructive) {
                    showResetConfirmation = true
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
        }
        .frame(width: 570, height: 500)
        .background(Color(red: 0.035, green: 0.038, blue: 0.042))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showGlobalOrder) {
            MacGlobalButtonOrderView(
                configuration: server.controlConfiguration,
                save: { order in
                    var configuration = server.controlConfiguration
                    configuration.setAvailableGlobalButtonOrder(order)
                    server.updateControlConfiguration(configuration)
                }
            )
        }
        .confirmationDialog(
            "Réinitialiser le bloc de boutons ?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rétablir les boutons d’origine", role: .destructive) {
                server.resetControlConfiguration()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les raccourcis clavier et les icônes personnalisées seront remplacés.")
        }
    }
}

private struct MacGlobalButtonOrderView: View {
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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ordre de la bulle Global")
                        .font(.headline)
                    Text("Uniquement les commandes absentes du bloc principal.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Terminé") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(order.enumerated()), id: \.element.id) { index, button in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            MacControlIconImage(icon: button.icon)
                                .frame(width: 18, height: 18)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(button.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(button.action.shortDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                move(index, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .help("Monter")
                            Button {
                                move(index, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == order.count - 1)
                            .help("Descendre")
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 48)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 390, height: 440)
        .background(Color(red: 0.035, green: 0.038, blue: 0.042))
        .preferredColorScheme(.dark)
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard order.indices.contains(index), order.indices.contains(destination) else { return }
        order.swapAt(index, destination)
        save(order)
    }
}

private struct MacControlLayoutPreview: View {
    let configuration: ControlConfiguration
    let selectedZone: ControlZone
    let select: (ControlZone) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                sideColumn([.upperLeft, .lowerLeft])

                VStack(spacing: 5) {
                    ZStack {
                        Circle().fill(Color.accentColor.gradient)
                        Circle().stroke(.white.opacity(0.2), lineWidth: 1)
                        Image(systemName: "waveform")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 74, height: 74)
                    Label("PTT", systemImage: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                sideColumn([.upperRight, .lowerRight])
            }

            HStack(spacing: 6) {
                zoneButton(.bottomLeft)
                zoneButton(.bottomCenter)
                zoneButton(.bottomRight)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func sideColumn(_ zones: [ControlZone]) -> some View {
        VStack(spacing: 6) {
            ForEach(zones) { zone in zoneButton(zone) }
        }
        .frame(maxWidth: .infinity)
    }

    private func zoneButton(_ zone: ControlZone) -> some View {
        let button = configuration.button(in: zone)
        return Button { select(zone) } label: {
            VStack(spacing: 3) {
                MacControlIconImage(icon: button.icon)
                    .frame(width: 19, height: 19)
                Text(button.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .background(
                selectedZone == zone ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selectedZone == zone ? Color.accentColor : .white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Modifier \(button.title)")
    }
}

private struct MacControlButtonEditor: View {
    private enum ActionChoice: String, CaseIterable, Identifiable {
        case standard
        case shortcut
        case showKeyboard
        case none

        var id: String { rawValue }
    }

    let original: ControlButtonConfiguration
    let save: (ControlButtonConfiguration) -> Void

    @State private var title: String
    @State private var icon: ControlButtonIcon
    @State private var actionChoice: ActionChoice
    @State private var standardKey: RemoteKey
    @State private var shortcut: MacKeyboardShortcut?
    @State private var showIconImporter = false
    @State private var importError: String?
    @State private var iconSearch = ""
    @State private var didSave = false

    init(button: ControlButtonConfiguration, save: @escaping (ControlButtonConfiguration) -> Void) {
        original = button
        self.save = save
        _title = State(initialValue: button.title)
        _icon = State(initialValue: button.icon)

        switch button.action {
        case .standardKey(let key):
            _actionChoice = State(initialValue: .standard)
            _standardKey = State(initialValue: key)
            _shortcut = State(initialValue: nil)
        case .macShortcut(let shortcut):
            _actionChoice = State(initialValue: .shortcut)
            _standardKey = State(initialValue: .enter)
            _shortcut = State(initialValue: shortcut)
        case .showKeyboard:
            _actionChoice = State(initialValue: .showKeyboard)
            _standardKey = State(initialValue: .enter)
            _shortcut = State(initialValue: nil)
        case .none:
            _actionChoice = State(initialValue: .none)
            _standardKey = State(initialValue: .enter)
            _shortcut = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        MacControlIconImage(icon: icon)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.accentColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(original.zone.macName)
                                .font(.headline)
                            Text(actionSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("NOM DU BOUTON")
                        TextField("Ex. Copier", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        fieldLabel("ACTION")
                        Picker("", selection: $actionChoice) {
                            Label("Touche standard", systemImage: "keyboard").tag(ActionChoice.standard)
                            Label("Raccourci du Mac", systemImage: "command").tag(ActionChoice.shortcut)
                            Label("Ouvrir le clavier iPhone", systemImage: "iphone.gen3").tag(ActionChoice.showKeyboard)
                            Label("Aucune action", systemImage: "nosign").tag(ActionChoice.none)
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if actionChoice == .standard {
                            Picker("Touche", selection: $standardKey) {
                                ForEach(RemoteKey.allCases, id: \.self) { key in
                                    Text(key.macName).tag(key)
                                }
                            }
                        } else if actionChoice == .shortcut {
                            ShortcutRecorderField(shortcut: $shortcut)
                                .frame(height: 52)
                        } else if actionChoice == .showKeyboard {
                            Label("Affiche le clavier complet sur l’iPhone", systemImage: "iphone.gen3")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            fieldLabel("ICÔNE")
                            Spacer()
                            Button {
                                showIconImporter = true
                            } label: {
                                Label("Importer", systemImage: "photo.badge.plus")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }

                        TextField("Rechercher une icône", text: $iconSearch)
                            .textFieldStyle(.roundedBorder)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                            ForEach(filteredIcons) { item in
                                Button {
                                    icon = .system(item.systemName)
                                } label: {
                                    Image(systemName: item.systemName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(width: 34, height: 31)
                                        .background(
                                            isSelected(item.systemName) ? Color.accentColor : Color.white.opacity(0.055),
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(item.label)
                                .accessibilityLabel(item.label)
                            }
                        }

                        if case .customImage = icon {
                            Label("Image personnalisée sélectionnée", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                        if let importError {
                            Text(importError).foregroundStyle(.orange).font(.caption2)
                        }
                    }
                }
                .padding(14)
            }

            Divider()

            HStack {
                if didSave {
                    Label("Enregistré", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Appliquer") { commit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(actionChoice == .shortcut && shortcut == nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
        .fileImporter(isPresented: $showIconImporter, allowedContentTypes: [.image]) { result in
            importIcon(result)
        }
    }

    private func commit() {
        let action: ControlButtonAction
        switch actionChoice {
        case .standard: action = .standardKey(standardKey)
        case .shortcut: action = shortcut.map(ControlButtonAction.macShortcut) ?? .none
        case .showKeyboard: action = .showKeyboard
        case .none: action = .none
        }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        save(ControlButtonConfiguration(
            zone: original.zone,
            title: cleanedTitle.isEmpty ? "Sans titre" : cleanedTitle,
            icon: icon,
            action: action
        ))
        didSave = true
    }

    private func isSelected(_ name: String) -> Bool {
        guard case .system(let selected) = icon else { return false }
        return selected == name
    }

    private var filteredIcons: [MacControlIconCatalog.Item] {
        let query = iconSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return MacControlIconCatalog.items }
        return MacControlIconCatalog.items.filter {
            $0.label.localizedCaseInsensitiveContains(query) ||
                $0.systemName.localizedCaseInsensitiveContains(query)
        }
    }

    private var actionSummary: String {
        switch actionChoice {
        case .standard: return standardKey.macName
        case .shortcut: return shortcut?.displayName ?? MacL10n.text("Raccourci à enregistrer")
        case .showKeyboard: return MacL10n.text("Clavier de l’iPhone")
        case .none: return MacL10n.text("Aucune action")
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.65)
            .foregroundStyle(.secondary)
    }

    private func importIcon(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let normalized = MacIconNormalizer.normalizedData(from: data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            icon = .customImage(normalized)
            importError = nil
        } catch {
            importError = MacL10n.text("Image illisible ou trop volumineuse.")
        }
    }
}

private struct ShortcutRecorderField: View {
    @Binding var shortcut: MacKeyboardShortcut?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.8), lineWidth: 1))
            VStack(spacing: 3) {
                Text(shortcut?.displayName ?? "Appuyez sur les touches…")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Text("Le champ capture la prochaine combinaison")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ShortcutCaptureRepresentable { shortcut = $0 }
        }
        .accessibilityLabel("Enregistrer un raccourci clavier")
    }
}

private struct ShortcutCaptureRepresentable: NSViewRepresentable {
    let onCapture: (MacKeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
    }
}

@MainActor
private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((MacKeyboardShortcut) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierKeyCodes.contains(event.keyCode) else { return }

        var modifiers: [ShortcutModifier] = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.append(.command) }
        if flags.contains(.option) { modifiers.append(.option) }
        if flags.contains(.control) { modifiers.append(.control) }
        if flags.contains(.shift) { modifiers.append(.shift) }
        if flags.contains(.function) { modifiers.append(.function) }

        let keyName = Self.keyName(for: event)
        let prefix = [
            flags.contains(.control) ? "⌃" : "",
            flags.contains(.option) ? "⌥" : "",
            flags.contains(.shift) ? "⇧" : "",
            flags.contains(.command) ? "⌘" : "",
            flags.contains(.function) ? "fn " : ""
        ].joined()
        onCapture?(MacKeyboardShortcut(
            keyCode: event.keyCode,
            modifiers: modifiers,
            displayName: prefix + keyName
        ))
    }

    private static func keyName(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "⎋",
            117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19"
        ]
        if let name = special[event.keyCode] { return name }
        let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
        return characters?.isEmpty == false ? characters!.uppercased() : "Touche \(event.keyCode)"
    }
}

private struct MacControlIconImage: View {
    let icon: ControlButtonIcon

    var body: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name).resizable().scaledToFit()
        case .customImage(let data):
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").resizable().scaledToFit()
            }
        }
    }
}

private enum MacControlIconCatalog {
    struct Item: Identifiable {
        let systemName: String
        let label: String
        var id: String { systemName }
    }

    static let items: [Item] = [
        Item(systemName: "keyboard", label: "Clavier"),
        Item(systemName: "return", label: "Entrée"),
        Item(systemName: "space", label: "Espace"),
        Item(systemName: "delete.left", label: "Effacer"),
        Item(systemName: "escape", label: "Échap"),
        Item(systemName: "arrow.right.to.line.compact", label: "Tabulation"),
        Item(systemName: "command", label: "Commande"),
        Item(systemName: "option", label: "Option"),
        Item(systemName: "control", label: "Contrôle"),
        Item(systemName: "shift", label: "Majuscule"),
        Item(systemName: "globe", label: "Globe"),
        Item(systemName: "fn", label: "Fonction"),
        Item(systemName: "arrow.up", label: "Flèche haut"),
        Item(systemName: "arrow.down", label: "Flèche bas"),
        Item(systemName: "arrow.left", label: "Flèche gauche"),
        Item(systemName: "arrow.right", label: "Flèche droite"),
        Item(systemName: "arrow.uturn.backward", label: "Annuler"),
        Item(systemName: "arrow.uturn.forward", label: "Rétablir"),
        Item(systemName: "doc.on.doc", label: "Copier"),
        Item(systemName: "doc.on.clipboard", label: "Coller"),
        Item(systemName: "scissors", label: "Couper"),
        Item(systemName: "magnifyingglass", label: "Rechercher"),
        Item(systemName: "square.and.arrow.up", label: "Partager"),
        Item(systemName: "tray.and.arrow.down", label: "Télécharger"),
        Item(systemName: "play.fill", label: "Lecture"),
        Item(systemName: "pause.fill", label: "Pause"),
        Item(systemName: "backward.fill", label: "Précédent"),
        Item(systemName: "forward.fill", label: "Suivant"),
        Item(systemName: "speaker.wave.2.fill", label: "Volume"),
        Item(systemName: "speaker.slash.fill", label: "Silence"),
        Item(systemName: "mic.fill", label: "Microphone"),
        Item(systemName: "camera.fill", label: "Caméra"),
        Item(systemName: "video.fill", label: "Vidéo"),
        Item(systemName: "airplayvideo", label: "AirPlay"),
        Item(systemName: "lock.fill", label: "Verrouiller"),
        Item(systemName: "moon.fill", label: "Mode sombre"),
        Item(systemName: "sun.max.fill", label: "Luminosité"),
        Item(systemName: "power", label: "Alimentation"),
        Item(systemName: "app", label: "Application"),
        Item(systemName: "square.grid.2x2", label: "Applications"),
        Item(systemName: "rectangle.on.rectangle", label: "Fenêtres"),
        Item(systemName: "arrow.left.arrow.right", label: "Changer d’application"),
        Item(systemName: "desktopcomputer", label: "Mac"),
        Item(systemName: "iphone.gen3", label: "iPhone"),
        Item(systemName: "message.fill", label: "Message"),
        Item(systemName: "envelope.fill", label: "E-mail"),
        Item(systemName: "phone.fill", label: "Téléphone"),
        Item(systemName: "calendar", label: "Calendrier"),
        Item(systemName: "clock.fill", label: "Horloge"),
        Item(systemName: "bell.fill", label: "Notification"),
        Item(systemName: "folder.fill", label: "Dossier"),
        Item(systemName: "link", label: "Lien"),
        Item(systemName: "star.fill", label: "Favori"),
        Item(systemName: "heart.fill", label: "J’aime"),
        Item(systemName: "checkmark", label: "Valider"),
        Item(systemName: "xmark", label: "Fermer"),
        Item(systemName: "plus", label: "Ajouter"),
        Item(systemName: "minus", label: "Retirer"),
        Item(systemName: "gearshape.fill", label: "Réglages"),
        Item(systemName: "ellipsis", label: "Plus")
    ]
}

private enum MacIconNormalizer {
    static func normalizedData(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let size = NSSize(width: 96, height: 96)
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let scale = min(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
        let target = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(
            x: (size.width - target.width) / 2,
            y: (size.height - target.height) / 2,
            width: target.width,
            height: target.height
        ))
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        if let png = bitmap.representation(using: .png, properties: [:]), png.count <= 40 * 1_024 {
            return png
        }
        if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]),
           jpeg.count <= 40 * 1_024 {
            return jpeg
        }
        guard let compact = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.45]),
              compact.count <= 40 * 1_024 else { return nil }
        return compact
    }
}

private extension ControlZone {
    var macName: String {
        switch self {
        case .upperLeft: return MacL10n.text("Haut gauche")
        case .lowerLeft: return MacL10n.text("Bas gauche")
        case .upperRight: return MacL10n.text("Haut droite")
        case .lowerRight: return MacL10n.text("Bas droite")
        case .bottomLeft: return MacL10n.text("Rangée basse · gauche")
        case .bottomCenter: return MacL10n.text("Rangée basse · centre")
        case .bottomRight: return MacL10n.text("Rangée basse · droite")
        }
    }
}

private extension RemoteKey {
    var macName: String {
        switch self {
        case .enter: return MacL10n.text("Entrée")
        case .escape: return MacL10n.text("Échap")
        case .tab: return MacL10n.text("Tabulation")
        case .applicationSwitcher: return MacL10n.text("Application précédente")
        case .nextConversation: return MacL10n.text("Conversation ou onglet suivant")
        case .backspace: return MacL10n.text("Effacement arrière")
        case .delete: return MacL10n.text("Supprimer")
        case .arrowUp: return MacL10n.text("Flèche haut")
        case .arrowDown: return MacL10n.text("Flèche bas")
        case .arrowLeft: return MacL10n.text("Flèche gauche")
        case .arrowRight: return MacL10n.text("Flèche droite")
        case .space: return MacL10n.text("Espace")
        case .copy: return MacL10n.text("Copier (⌘C)")
        case .paste: return MacL10n.text("Coller (⌘V)")
        case .cut: return MacL10n.text("Couper (⌘X)")
        }
    }
}

private extension ControlButtonAction {
    var shortDescription: String {
        switch self {
        case .none: return MacL10n.text("À configurer")
        case .standardKey(let key): return key.macName
        case .macShortcut(let shortcut): return shortcut.displayName
        case .showKeyboard: return MacL10n.text("Clavier iPhone")
        }
    }
}
