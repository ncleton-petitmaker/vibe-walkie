import SwiftUI

/// Le bouton Push-to-Talk.
///
/// Bouton bleu principal, cohérent avec le reste de la télécommande.
/// dans une zone tactile de 64, anneaux animés pendant l'écoute, icône qui
/// bascule entre `sparkles` et `waveform`, ombre teintée.
///
/// Le geste vit dans un overlay de la frame extérieure, jamais parmi les vues
/// qui s'animent : c'est ce qui empêche UIKit de recréer la vue du
/// reconnaisseur et d'annuler le geste alors que le doigt est encore posé.
struct PTTButton: View {
    @ObservedObject var dictation: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRecording: Bool { dictation.isRecording }
    private var isArmedForCancel: Bool { dictation.phase == .armedForCancel }

    var body: some View {
        ZStack {
            if isRecording {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(ringColor.opacity(0.3), lineWidth: 2)
                        .frame(
                            width: 94 + CGFloat(index) * 18 + level * 12,
                            height: 94 + CGFloat(index) * 18 + level * 12
                        )
                }
            }

            Circle()
                .fill(fillColor)
                .frame(width: 88, height: 88)
                .shadow(color: fillColor.opacity(0.35), radius: isRecording ? 12 : 8, y: 4)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                )
                .scaleEffect(isRecording ? 1.12 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.2), value: isRecording)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isArmedForCancel)
        }
        .frame(width: 116, height: 116)
        .allowsHitTesting(false)
        .overlay(
            PressAndHoldGesture(
                onPressStart: { dictation.pressBegan() },
                onPressMoved: { dictation.pressMoved($0) },
                onPressEnd: { dictation.pressEnded() },
                onPressCancel: { dictation.pressCancelled() }
            )
        )
        .accessibilityElement()
        .accessibilityLabel("ios.dictate.c1b029f")
        .accessibilityValue(isRecording ? AppL10n.text("ios.transcribing.6511a3a") : "")
        .accessibilityHint("ios.hold.to.dictate.release.to.insert.on.the.mac.14cabfc")
        .accessibilityAddTraits(.startsMediaSession)
        .accessibilityAction {
            if isRecording {
                dictation.pressEnded()
            } else {
                dictation.pressBegan()
            }
        }
    }

    private var level: CGFloat { dictation.level }

    private var fillColor: Color {
        isArmedForCancel ? Color(red: 0.75, green: 0.28, blue: 0.28) : .remoteBlue
    }

    private var ringColor: Color { fillColor }

    private var iconName: String {
        if isArmedForCancel { return "xmark" }
        return isRecording ? "waveform" : "sparkles"
    }
}
