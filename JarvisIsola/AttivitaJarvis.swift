import Foundation
import ActivityKit
import AppIntents

// MARK: - MARK X · DYNAMIC ISLAND (mockup approvato, build 32): l'attività di JARVIS fuori dall'app.
// Questo file è sia nell'app (che accende, aggiorna e spegne l'attività) sia nell'estensione JarvisIsola (che la disegna).
// TRAVEL: dopo «Avvisami», il conto alla rovescia per uscire e la linea da prendere. GUIDA: la guida a piedi di SATELLITE
// col telefono in tasca: la freccia, la via e i metri. 26 ott sera (sì del signore): REC (il Wiretap registra anche fuori
// dall'app), PIOGGIA (il radar, anche ad app chiusa).

nonisolated struct AttivitaJarvis: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// "travel", "guida", "rec" o "pioggia".
        var tipo: String
        /// TRAVEL: quando uscire. PIOGGIA: quando comincia (il conto alla rovescia lo fa iOS, anche ad app chiusa).
        var esci: Date?
        /// TRAVEL: la sigla della prima linea («M1»), il suo colore (esadecimale) e l'ora del mezzo («19:27»).
        var sigla: String?
        var coloreSigla: String?
        var oraMezzo: String?
        /// GUIDA: la freccia della svolta (↱ ↰ ↑ ⚑), la via e i metri alla svolta.
        var freccia: String?
        var via: String?
        var metri: Int?
        /// La riga sotto, nell'isola grande: il percorso (TRAVEL), la svolta dopo e l'arrivo (GUIDA), la stanza (REC), i
        /// millimetri (PIOGGIA).
        var riga: String
        /// REC: da quando conta (già spostato delle pause) e, in pausa, i secondi registrati fin lì.
        var inizio: Date? = nil
        var pausaSecondi: Int? = nil
    }
    /// Dove va: il luogo di SATELLITE (TRAVEL, GUIDA); «Wiretap» o «Radar» per le altre.
    var meta: String
}

/// I tasti dell'isola che non aprono l'app (Pausa, Stop, Ok, Basta avvisi, Ferma guida): li esegue l'app,
/// anche in sottofondo, senza che il signore debba tornare in JARVIS. Nell'estensione `esegui` resta vuoto.
@MainActor
enum ComandiIsola {
    static var esegui: ((String) -> Void)?
}

// niente «nonisolated» sul tipo: il @Parameter è una proprietà che cambia, e Swift 6 non lo permette (avviso di Xcode, 26 ott)
struct ComandoIsola: LiveActivityIntent {
    static let title: LocalizedStringResource = "Comando di JARVIS"
    @Parameter(title: "Azione") var azione: String

    init() {}
    init(_ azione: String) { self.azione = azione }

    func perform() async throws -> some IntentResult {
        let a = azione
        await MainActor.run { ComandiIsola.esegui?(a) }
        return .result()
    }
}
