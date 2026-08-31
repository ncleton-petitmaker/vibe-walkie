import CoreGraphics
import AppKit
import RemoteCore

/// Génération des événements clavier et souris.
///
/// Toutes les entrées viennent d'énumérations fermées ou de valeurs bornées.
/// Les raccourcis matériels sont enregistrés par l'utilisateur sur ce Mac et
/// leurs keycodes sont validés avant exécution. Les coordonnées absolues de
/// l'écran distant sont normalisées et bornées avant conversion.
/// Isolé sur le main actor : `CGEventSource` n'est pas `Sendable` et tous les
/// appelants (routeur de session) vivent déjà sur le main actor.
@MainActor
enum CGEventFactory {

    private static let source = CGEventSource(stateID: .combinedSessionState)

    // MARK: - Clavier

    private static func keyCode(for key: RemoteKey) -> CGKeyCode {
        switch key {
        case .enter: return 36
        case .escape: return 53
        case .tab, .applicationSwitcher: return 48
        case .nextConversation: return 124
        case .backspace: return 51
        case .delete: return 117
        case .arrowUp: return 126
        case .arrowDown: return 125
        case .arrowLeft: return 123
        case .arrowRight: return 124
        case .space: return 49
        case .copy: return 8
        case .paste: return 9
        case .cut: return 7
        }
    }

    static func press(_ key: RemoteKey) {
        if key == .applicationSwitcher {
            switchToPreviousApplication()
            return
        }
        if key == .nextConversation {
            navigateToNextConversation()
            return
        }
        if key == .copy {
            pressShortcut(keyCode: 8, modifiers: [(55, .maskCommand)])
            return
        }
        if key == .paste {
            pressShortcut(keyCode: 9, modifiers: [(55, .maskCommand)])
            return
        }
        if key == .cut {
            pressShortcut(keyCode: 7, modifiers: [(55, .maskCommand)])
            return
        }

        let code = keyCode(for: key)
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }

    /// Rejoue une combinaison capturée localement dans l'éditeur Mac.
    /// Les valeurs restent bornées par le modèle partagé avant d'atteindre
    /// CoreGraphics.
    static func press(_ shortcut: MacKeyboardShortcut) {
        guard shortcut.isValid else { return }
        let modifiers = shortcut.modifiers.compactMap { modifier -> (CGKeyCode, CGEventFlags)? in
            switch modifier {
            case .command: return (55, .maskCommand)
            case .option: return (58, .maskAlternate)
            case .control: return (59, .maskControl)
            case .shift: return (56, .maskShift)
            case .function: return (63, .maskSecondaryFn)
            }
        }
        pressShortcut(keyCode: CGKeyCode(shortcut.keyCode), modifiers: modifiers)
    }

    /// Reproduit un appui bref sur Cmd+Tab. Relâcher Command immédiatement
    /// valide la sélection : l'app précédente passe devant sans laisser le
    /// sélecteur macOS affiché.
    private static func switchToPreviousApplication() {
        pressShortcut(keyCode: 48, modifiers: [(55, .maskCommand)])
    }

    /// Utilise le raccourci réellement exposé par l'application active.
    /// ChatGPT possède une commande dédiée « Chat suivant » tandis que Claude
    /// et Chrome suivent la convention macOS Cmd+Option+Flèche droite.
    private static func navigateToNextConversation() {
        let application = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = application?.bundleIdentifier?.lowercased()
        let applicationName = application?.localizedName?.lowercased()
        let isChatGPT = bundleIdentifier == "com.openai.codex"
            || bundleIdentifier == "com.openai.chat"
            || applicationName == "chatgpt"

        if isChatGPT {
            // Touche physique « ] » sur QWERTY, affichée « $ » sur AZERTY.
            pressShortcut(
                keyCode: 30,
                modifiers: [(55, .maskCommand), (56, .maskShift)]
            )
        } else {
            pressShortcut(
                keyCode: 124,
                modifiers: [(55, .maskCommand), (58, .maskAlternate)]
            )
        }
    }

    /// Envoie les modificateurs comme de vraies touches. Les apps Electron
    /// peuvent ignorer un raccourci si seuls les drapeaux du dernier événement
    /// sont positionnés.
    private static func pressShortcut(
        keyCode: CGKeyCode,
        modifiers: [(keyCode: CGKeyCode, flag: CGEventFlags)]
    ) {
        for modifier in modifiers {
            CGEvent(
                keyboardEventSource: source,
                virtualKey: modifier.keyCode,
                keyDown: true
            )?.post(tap: .cghidEventTap)
        }

        let flags = modifiers.reduce(into: CGEventFlags()) { result, modifier in
            result.insert(modifier.flag)
        }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }

        for modifier in modifiers.reversed() {
            CGEvent(
                keyboardEventSource: source,
                virtualKey: modifier.keyCode,
                keyDown: false
            )?.post(tap: .cghidEventTap)
        }
    }

    /// Tape du texte par événements Unicode.
    ///
    /// Découpé en petits paquets : certaines applications ignorent une chaîne
    /// Unicode trop longue attachée à un seul événement.
    @discardableResult
    static func type(_ text: String) -> Bool {
        for chunk in text.chunked(by: 16) {
            let utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return false }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Colle avec un vrai Cmd+V.
    ///
    /// Les quatre événements sont envoyés séparément avec le drapeau command
    /// sur les deux touches V : un raccourci simulé partiellement est ignoré
    /// par plusieurs applications Electron.
    static func paste() {
        let command: CGKeyCode = 55
        let v: CGKeyCode = 9

        CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: true)?.post(tap: .cghidEventTap)

        if let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }

        CGEvent(keyboardEventSource: source, virtualKey: command, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - Pointeur

    private static var currentLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Déplace le curseur d'un delta, en le gardant sur un écran connecté.
    static func move(deltaX: Double, deltaY: Double) {
        let target = clampToScreens(CGPoint(
            x: currentLocation.x + deltaX,
            y: currentLocation.y + deltaY
        ))
        let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    static func moveAbsolute(normalizedX: Double, normalizedY: Double) {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let x = min(max(normalizedX, 0), 1)
        let y = min(max(normalizedY, 0), 1)
        let target = CGPoint(
            x: bounds.minX + x * bounds.width,
            y: bounds.minY + y * bounds.height
        )
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    static func click(button: PointerButton, clickCount: Int) {
        let location = currentLocation
        let count = ControlInputPolicy.clickCount(clickCount)
        let (down, up, cgButton): (CGEventType, CGEventType, CGMouseButton) = button == .left
            ? (.leftMouseDown, .leftMouseUp, .left)
            : (.rightMouseDown, .rightMouseUp, .right)

        for index in 1...count {
            if let event = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: location, mouseButton: cgButton) {
                event.setIntegerValueField(.mouseEventClickState, value: Int64(index))
                event.post(tap: .cghidEventTap)
            }
            if let event = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: location, mouseButton: cgButton) {
                event.setIntegerValueField(.mouseEventClickState, value: Int64(index))
                event.post(tap: .cghidEventTap)
            }
        }
    }

    static func drag(phase: DragPhase, deltaX: Double, deltaY: Double) {
        let target = clampToScreens(CGPoint(
            x: currentLocation.x + deltaX,
            y: currentLocation.y + deltaY
        ))
        let type: CGEventType
        switch phase {
        case .began: type = .leftMouseDown
        case .moved: type = .leftMouseDragged
        case .ended: type = .leftMouseUp
        }
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func scroll(deltaX: Double, deltaY: Double) {
        let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(clamping: Int(deltaY)),
            wheel2: Int32(clamping: Int(deltaX)),
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    /// Garde le curseur dans l'union des écrans branchés.
    private static func clampToScreens(_ point: CGPoint) -> CGPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return point }

        if screens.contains(where: { $0.frame.contains(point) }) {
            return point
        }
        let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
        return CGPoint(
            x: min(max(point.x, union.minX), union.maxX - 1),
            y: min(max(point.y, union.minY), union.maxY - 1)
        )
    }
}

private extension String {
    func chunked(by size: Int) -> [String] {
        guard count > size else { return [self] }
        var result: [String] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            result.append(String(self[index..<end]))
            index = end
        }
        return result
    }
}
