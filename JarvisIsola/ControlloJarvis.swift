import SwiftUI
import WidgetKit
import AppIntents

// MARK: - 12.0 (12) · B4 · IL CONTROLLO JARVIS
// Nel Centro di Controllo, sulla schermata bloccata o sul tasto Azione (iOS 18): un tocco e JARVIS si apre già in ascolto,
// più rapido di Siri e senza sbloccare per cercare l'app. Il ciano di JARVIS, l'onda come icona.

@available(iOS 18.0, *)
struct ControlloJarvis: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "it.discosizer.jarvis.controllo") {
            ControlWidgetButton(action: ParlaDalControllo()) {
                Label("JARVIS", systemImage: "waveform.circle")
            }
            .tint(Color(red: 79 / 255, green: 227 / 255, blue: 1))
        }
        .displayName("JARVIS")
        .description("Apre JARVIS già in ascolto.")
    }
}
