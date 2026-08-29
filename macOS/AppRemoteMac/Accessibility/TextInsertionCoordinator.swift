import ApplicationServices
import AppKit
import RemoteCore

/// Écrit le texte à l'emplacement du curseur, avec repli contrôlé.
///
/// Trois méthodes, essayées dans l'ordre du plus propre au plus compatible :
/// écrire le texte sélectionné en AX, remplacer une plage de la valeur, puis
/// coller. Aucune application ne les supporte toutes, et aucune méthode ne
/// couvre toutes les applications — d'où la cascade plutôt qu'un choix unique.
@MainActor
final class TextInsertionCoordinator {

    /// Ce que chaque application a accepté au cours de la session.
    ///
    /// Utilisé pour aller plus vite la fois suivante, jamais pour sauter la
    /// vérification : une même application peut exposer un champ AX correct
    /// et, dans une autre fenêtre, un éditeur qui ne l'est pas.
    private var knownMethods: [String: InsertionMethod] = [:]
    func insert(_ text: String, into target: CapturedTarget) throws -> InsertionResult {
        guard !text.isEmpty else {
            throw RemoteErrorPayload(code: .internalFailure, detail: "texte vide")
        }
        // Vérifié avant toute écriture, tout presse-papiers, tout événement.
        guard !AccessibilityClient.isSecureInputEnabled else {
            throw RemoteErrorPayload(code: .secureField)
        }
        if let element = target.element, AccessibilityClient.isSecure(element) {
            throw RemoteErrorPayload(code: .secureField)
        }
        if let element = target.element {
            collapseSelectionToEnd(in: element)
        }
        let preparedText = shouldPrependSpace(beforeTyping: text, in: target.element)
            ? " " + text
            : text
        guard preparedText.count <= ProtocolLimits.maxTextLength else {
            throw RemoteErrorPayload(code: .payloadTooLarge)
        }

        if target.element != nil {
            if let result = insertViaSelectedText(preparedText, target: target) {
                remember(.axSelectedText, for: target)
                return result
            }
            if let result = insertViaValueRange(preparedText, target: target) {
                remember(.axRange, for: target)
                return result
            }
        } else {
            // Certaines apps web natives (dont ChatGPT/Codex) masquent toute
            // leur hiérarchie AX. Le collage y est parfois lu après notre
            // restauration transactionnelle et disparaît. Les événements
            // Unicode n'utilisent pas le presse-papiers et sont synchrones.
            let result = try insertViaKeyboardEvents(preparedText, target: target)
            remember(.keyboardEvents, for: target)
            return result
        }

        let result = try insertViaPaste(preparedText, target: target)
        remember(.paste, for: target)
        return result
    }

    /// Frappe directe au clavier, réservée à une action explicite de l'iPhone.
    ///
    /// C'est le seul chemin autorisé dans un champ sécurisé, et uniquement
    /// quand l'utilisateur a ouvert le clavier puis saisi ce texte. On ne peut
    /// pas relire un champ de mot de passe : le succès annoncé porte sur
    /// l'envoi des événements, pas sur le contenu.
    func typeManually(_ text: String, userInitiated: Bool) throws -> InsertionResult {
        guard userInitiated else { throw RemoteErrorPayload(code: .secureField) }
        guard AccessibilityClient.isTrusted else {
            throw RemoteErrorPayload(code: .permissionAccessibilityDenied)
        }

        CGEventFactory.type(text)
        return InsertionResult(
            method: .keyboardEvents,
            verified: false,
            pasteboardRestored: nil,
            applicationName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Application"
        )
    }

    // MARK: - Méthode 1 : texte sélectionné

    private func insertViaSelectedText(_ text: String, target: CapturedTarget) -> InsertionResult? {
        guard let element = target.element else { return nil }
        guard AccessibilityClient.isSettable(element, kAXSelectedTextAttribute) else { return nil }

        let before = AccessibilityClient.range(element, kAXSelectedTextRangeAttribute)
        guard AccessibilityClient.setValue(element, kAXSelectedTextAttribute, text as CFString) else {
            return nil
        }

        // Le curseur doit avoir avancé de la longueur écrite. Sans ce contrôle,
        // une application qui accepte l'attribut sans rien faire passerait pour
        // un succès et le texte serait perdu en silence.
        let after = AccessibilityClient.range(element, kAXSelectedTextRangeAttribute)
        let verified: Bool
        if let before, let after {
            verified = after.location >= before.location
        } else {
            verified = after != nil
        }

        return InsertionResult(
            method: .axSelectedText,
            verified: verified,
            pasteboardRestored: nil,
            applicationName: target.applicationName
        )
    }

    // MARK: - Méthode 2 : remplacement de plage

    private func insertViaValueRange(_ text: String, target: CapturedTarget) -> InsertionResult? {
        guard let element = target.element else { return nil }
        guard AccessibilityClient.isSettable(element, kAXValueAttribute),
              let current = AccessibilityClient.string(element, kAXValueAttribute),
              let selection = AccessibilityClient.range(element, kAXSelectedTextRangeAttribute) else {
            return nil
        }

        let nsCurrent = current as NSString
        let location = min(max(0, selection.location), nsCurrent.length)
        let length = min(max(0, selection.length), nsCurrent.length - location)
        let updated = nsCurrent.replacingCharacters(in: NSRange(location: location, length: length), with: text)

        guard AccessibilityClient.setValue(element, kAXValueAttribute, updated as CFString) else {
            return nil
        }

        let written = AccessibilityClient.string(element, kAXValueAttribute)
        let verified = written == updated

        // Replace le curseur après le texte inséré : sans cela, la dictée
        // suivante repartirait du début du champ.
        var caret = CFRange(location: location + (text as NSString).length, length: 0)
        if let value = AXValueCreate(.cfRange, &caret) {
            AccessibilityClient.setValue(element, kAXSelectedTextRangeAttribute, value)
        }

        return InsertionResult(
            method: .axRange,
            verified: verified,
            pasteboardRestored: nil,
            applicationName: target.applicationName
        )
    }

    // MARK: - Méthode 3 : collage transactionnel

    private func insertViaKeyboardEvents(_ text: String, target: CapturedTarget) throws -> InsertionResult {
        guard CGEventFactory.type(text) else {
            throw RemoteErrorPayload(code: .internalFailure, detail: "événements clavier indisponibles")
        }
        return InsertionResult(
            method: .keyboardEvents,
            verified: false,
            pasteboardRestored: nil,
            applicationName: target.applicationName
        )
    }

    private func insertViaPaste(_ text: String, target: CapturedTarget) throws -> InsertionResult {
        let transaction = PasteboardTransaction(writing: text)
        CGEventFactory.paste()

        // Laisse à l'application le temps de lire le presse-papiers. Les apps
        // Electron le font souvent de façon asynchrone ; restaurer trop tôt
        // colle l'ancien contenu à la place du texte dicté.
        Thread.sleep(forTimeInterval: 0.12)

        let restored = transaction.restore()
        return InsertionResult(
            method: .paste,
            verified: false,
            pasteboardRestored: restored,
            applicationName: target.applicationName
        )
    }

    private func remember(_ method: InsertionMethod, for target: CapturedTarget) {
        guard let bundle = target.bundleIdentifier else { return }
        knownMethods[bundle] = method
    }

    /// Une frappe Unicode remplacerait une sélection active. Le PTT étant
    /// append-only, on replie d'abord la sélection vers son extrémité droite.
    private func collapseSelectionToEnd(in element: AXUIElement) {
        guard let selection = AccessibilityClient.range(element, kAXSelectedTextRangeAttribute),
              selection.length > 0 else { return }
        var caret = CFRange(location: selection.location + selection.length, length: 0)
        if let value = AXValueCreate(.cfRange, &caret) {
            AccessibilityClient.setValue(element, kAXSelectedTextRangeAttribute, value)
        }
    }

    /// Détermine la frontière depuis la valeur AX et la position du curseur.
    /// Si une application ne publie pas son contenu (certains éditeurs web),
    /// on préfère ajouter la séparation : un éventuel espace initial est moins
    /// destructeur que deux mots fusionnés puis corrigés comme un seul mot.
    private func shouldPrependSpace(
        beforeTyping replacement: String,
        in providedElement: AXUIElement? = nil
    ) -> Bool {
        guard let first = replacement.first,
              first.isLetter || first.isNumber else {
            return false
        }
        guard let element = providedElement ?? AccessibilityClient.focusedElement(),
              let selection = AccessibilityClient.range(element, kAXSelectedTextRangeAttribute) else {
            return true
        }

        // Une sélection explicite signifie que l'utilisateur remplace le texte,
        // pas qu'il continue le mot placé avant elle.
        guard selection.length == 0 else { return false }
        guard selection.location > 0 else { return false }
        guard let current = AccessibilityClient.string(element, kAXValueAttribute) else {
            return true
        }

        let value = current as NSString
        let location = min(selection.location, value.length)
        guard location > 0 else { return false }
        let composedRange = value.rangeOfComposedCharacterSequence(at: location - 1)
        guard let previous = value.substring(with: composedRange).last else { return false }
        if previous.isWhitespace { return false }

        // Ces signes ouvrent ou relient une expression : « l' » + « arbre »,
        // « dossier/ » + « fichier », etc. ne doivent pas recevoir d'espace.
        let noSpaceAfter: Set<Character> = ["(", "[", "{", "'", "’", "-", "–", "—", "/", "\\"]
        return !noSpaceAfter.contains(previous)
    }
}
