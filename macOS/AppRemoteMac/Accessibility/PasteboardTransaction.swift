import AppKit
import RemoteCore

/// Écriture temporaire dans le presse-papiers, avec restauration prudente.
///
/// Le presse-papiers appartient à l'utilisateur. Le principe directeur ici est
/// simple : on peut échouer à restaurer l'ancien contenu, mais on ne doit
/// jamais écraser quelque chose que l'utilisateur vient de copier. Une
/// restauration aveugle après un délai fixe ferait exactement cela.
final class PasteboardTransaction {

    /// Type privé déposé à côté du texte. Sa présence prouve que le contenu
    /// courant est encore le nôtre.
    private static let markerType = NSPasteboard.PasteboardType("com.nicolascleton.viberemote.transaction")

    private let pasteboard: NSPasteboard
    private let snapshot: [[NSPasteboard.PasteboardType: Data]]
    private let changeCountAfterWrite: Int

    /// Capture l'état complet puis écrit le texte.
    ///
    /// Chaque item et chacun de ses types sont sauvegardés : un presse-papiers
    /// ne contient pas qu'une chaîne, et restaurer seulement le texte perdrait
    /// une image ou un fichier copié.
    init(writing text: String, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard

        var captured: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type] = data
                }
            }
            if !entry.isEmpty { captured.append(entry) }
        }
        self.snapshot = captured

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data([1]), forType: Self.markerType)
        pasteboard.writeObjects([item])
        self.changeCountAfterWrite = pasteboard.changeCount
    }

    /// Vrai tant que personne n'a touché au presse-papiers depuis notre écriture.
    var stillOwnsPasteboard: Bool {
        pasteboard.changeCount == changeCountAfterWrite
            && pasteboard.data(forType: Self.markerType) != nil
    }

    /// Restaure l'état d'origine si, et seulement si, il est sûr de le faire.
    ///
    /// Retourne `false` quand une copie concurrente est détectée. Ce n'est pas
    /// une erreur d'insertion : c'est un choix délibéré de préserver l'action
    /// la plus récente de l'utilisateur.
    @discardableResult
    func restore() -> Bool {
        guard stillOwnsPasteboard else { return false }

        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return true }

        let items: [NSPasteboardItem] = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
        return true
    }
}
