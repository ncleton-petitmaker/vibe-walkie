import ApplicationServices
import AppKit
import RemoteCore

/// Accès minimal et typé à l'API d'accessibilité.
///
/// L'API C d'AXUIElement est utilisée directement plutôt qu'une enveloppe
/// tierce : la surface nécessaire ici est petite, et une dépendance externe
/// peu maintenue sur le chemin critique de l'injection de texte serait un
/// mauvais échange.
enum AccessibilityClient {

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ouvre le dialogue système. À n'appeler qu'après avoir expliqué pourquoi.
    ///
    /// La clé est écrite littéralement : `kAXTrustedCheckOptionPrompt` est une
    /// `var` globale non concurrency-safe en Swift 6, et sa valeur est stable.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Lecture d'attributs

    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = copyAttribute(element, attribute) as? [AnyObject] else { return [] }
        return value.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return (item as! AXUIElement)
        }
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyAttribute(element, attribute) as? Bool
    }

    static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = CFRange()
        guard AXValueGetValue((value as! AXValue), .cfRange, &result) else { return nil }
        return result
    }

    // MARK: - Écriture

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    static func setValue(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    // MARK: - Focus

    /// Élément qui a le focus clavier, tel que le système le voit.
    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        return element(system, kAXFocusedUIElementAttribute)
    }

    static func processIdentifier(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    /// Vrai si l'élément est un champ de mot de passe.
    ///
    /// Vérifié avant toute écriture, jamais après : le but est de ne jamais
    /// approcher un mot de passe, pas de s'en rendre compte ensuite.
    static func isSecure(_ element: AXUIElement) -> Bool {
        if let subrole = string(element, kAXSubroleAttribute),
           subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        return false
    }
}
