import AppIntents
import Combine
import SwiftUI

/// Ponte tra Siri / tasto Azione / Comandi rapidi e l'app: l'intent lascia qui la richiesta, la schermata la esegue.
@MainActor
final class Comandi: ObservableObject {
    static let condiviso = Comandi()
    enum Richiesta: Equatable { case ascolta, briefing, leggi(String), guarda, diario(String), sos }   // leggi: notifica da dire; guarda: occhi; diario: domanda della sera
    @Published var richiesta: Richiesta?
}

struct ParlaConJarvis: AppIntent {
    // nonisolated e calcolate: soddisfano i requisiti (non isolati) di AppIntent anche con MainActor come isolamento predefinito
    nonisolated static var title: LocalizedStringResource { "Parla con FRIDAY" }
    nonisolated static var description: IntentDescription { IntentDescription("Apre FRIDAY già in ascolto.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .ascolta
        return .result()
    }
}

struct BriefingDiJarvis: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Briefing di FRIDAY" }
    nonisolated static var description: IntentDescription { IntentDescription("FRIDAY prepara il briefing: lezioni, impegni, note e meteo.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .briefing
        return .result()
    }
}

struct GuardaConJarvis: AppIntent {
    nonisolated static var title: LocalizedStringResource { "FRIDAY, guarda" }
    nonisolated static var description: IntentDescription { IntentDescription("Apre gli occhi di FRIDAY: la fotocamera scatta da sola e FRIDAY dice cosa vede.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .guarda
        return .result()
    }
}

/// FRIDAY · SOS: dal tasto Azione o da Siri («FRIDAY, aiuto»). Apre l'SOS: dopo 5 secondi (annullabili) parte l'aiuto ad Ale.
struct AiutoAle: AppIntent {
    nonisolated static var title: LocalizedStringResource { "Aiuto Ale" }
    nonisolated static var description: IntentDescription { IntentDescription("Apre l'SOS di FRIDAY: dopo 5 secondi avvisa Ale con la tua posizione. Puoi annullare.") }
    nonisolated static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        Comandi.condiviso.richiesta = .sos
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
                    shortTitle: "Parla con FRIDAY",
                    systemImageName: "waveform.circle")
        AppShortcut(intent: BriefingDiJarvis(),
                    phrases: ["Buongiorno \(.applicationName)", "Briefing di \(.applicationName)"],
                    shortTitle: "Briefing",
                    systemImageName: "sun.horizon")
        AppShortcut(intent: GuardaConJarvis(),
                    phrases: ["\(.applicationName) guarda", "Guarda con \(.applicationName)", "Occhi di \(.applicationName)"],
                    shortTitle: "Occhi di FRIDAY",
                    systemImageName: "eye")
        AppShortcut(intent: AiutoAle(),
                    phrases: ["\(.applicationName) aiuto", "Aiuto \(.applicationName)", "SOS \(.applicationName)"],
                    shortTitle: "Aiuto Ale",
                    systemImageName: "sos")
    }
}
