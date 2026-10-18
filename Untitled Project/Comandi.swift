import AppIntents
import Combine
import SwiftUI

/// Ponte tra Siri / tasto Azione / Comandi rapidi e l'app: l'intent lascia qui la richiesta, la schermata la esegue.
@MainActor
final class Comandi: ObservableObject {
    static let condiviso = Comandi()
    enum Richiesta: Equatable { case ascolta, briefing, leggi(String), guarda, diario(String), beaSOS(lat: Double?, lon: Double?, prova: Bool) }   // beaSOS: il Tocco d'aiuto di Bea   // leggi: notifica da dire; guarda: occhi; diario: domanda della sera
    @Published var richiesta: Richiesta?
}

struct ParlaConJarvis: AppIntent {
    // nonisolated e calcolate: soddisfano i requisiti (non isolati) di AppIntent anche con MainActor come isolamento predefinito
    nonisolated static var title: LocalizedStringResource { "Parla con Jarvis" }
    nonisolated static var description: IntentDescription { IntentDescription("Apre Jarvis già in ascolto.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .ascolta
        return .result()
    }
}

struct BriefingDiJarvis: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Briefing di Jarvis" }
    nonisolated static var description: IntentDescription { IntentDescription("Jarvis prepara il briefing: meteo, impegni, note e serate.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .briefing
        return .result()
    }
}

struct GuardaConJarvis: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Jarvis, guarda" }
    nonisolated static var description: IntentDescription { IntentDescription("Apre gli occhi di Jarvis: la fotocamera scatta da sola e Jarvis dice cosa vede.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .guarda
        return .result()
    }
}

/// Frasi per Siri, disponibili subito dopo l'installazione (nessuna configurazione nei Comandi rapidi).
/// «Ehi Siri, Jarvis» apre l'app già in ascolto; da lì in poi si parla con JARVIS (anche i comandi: «attiva la Sentinella»).
/// Compaiono anche tra le scelte del tasto Azione.
struct ScorciatoieJarvis: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ParlaConJarvis(),
                    phrases: ["\(.applicationName)", "Parla con \(.applicationName)", "Chiedi a \(.applicationName)", "Ehi \(.applicationName)",
                             "Attiva \(.applicationName)", "Svegliati \(.applicationName)"],
                    shortTitle: "Parla con Jarvis",
                    systemImageName: "waveform.circle")
        AppShortcut(intent: BriefingDiJarvis(),
                    phrases: ["Buongiorno \(.applicationName)", "Briefing di \(.applicationName)"],
                    shortTitle: "Briefing",
                    systemImageName: "sun.horizon")
        AppShortcut(intent: GuardaConJarvis(),
                    phrases: ["\(.applicationName) guarda", "Guarda con \(.applicationName)", "Occhi di \(.applicationName)"],
                    shortTitle: "Occhi di Jarvis",
                    systemImageName: "eye")
    }
}
