import AppIntents
import SwiftUI
import WidgetKit

@main
struct VibeWalkieControlsBundle: WidgetBundle {
    var body: some Widget {
        OpenVibeWalkieControl()
    }
}

/// Bouton système disponible dans le Centre de contrôle, sur l'écran
/// verrouillé et pour le bouton Action.
struct OpenVibeWalkieControl: ControlWidget {
    static let kind = "com.nicolascleton.viberemote.control.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenVibeWalkieIntent()) {
                Label("Vibe Walkie", systemImage: "laptopcomputer.and.iphone")
                    .controlWidgetActionHint("Ouvrir Vibe Walkie")
            }
            .tint(.blue)
        }
        .displayName("Vibe Walkie")
        .description("Ouvrir rapidement Vibe Walkie depuis le Centre de contrôle.")
    }
}
