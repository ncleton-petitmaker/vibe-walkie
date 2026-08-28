import AppIntents
import SwiftUI
import WidgetKit

@main
struct AppRemoteControlsBundle: WidgetBundle {
    var body: some Widget {
        OpenAppRemoteControl()
    }
}

/// Bouton système disponible dans le Centre de contrôle, sur l'écran
/// verrouillé et pour le bouton Action.
struct OpenAppRemoteControl: ControlWidget {
    static let kind = "com.nicolascleton.viberemote.control.open"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAppRemoteIntent()) {
                Label("Vibe Remote", systemImage: "laptopcomputer.and.iphone")
                    .controlWidgetActionHint("Ouvrir Vibe Remote")
            }
            .tint(.blue)
        }
        .displayName("Vibe Remote")
        .description("Ouvrir rapidement Vibe Remote depuis le Centre de contrôle.")
    }
}
