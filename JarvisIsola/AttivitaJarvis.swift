import Foundation
import ActivityKit

// MARK: - MARK X · DYNAMIC ISLAND (mockup approvato, build 32): l'attività di JARVIS fuori dall'app.
// Questo file è sia nell'app (che accende, aggiorna e spegne l'attività) sia nell'estensione JarvisIsola (che la disegna).
// TRAVEL: dopo «Avvisami», il conto alla rovescia per uscire e la linea da prendere. GUIDA: la guida a piedi di SATELLITE
// col telefono in tasca: la freccia, la via e i metri.

nonisolated struct AttivitaJarvis: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// "travel" o "guida".
        var tipo: String
        /// TRAVEL: quando uscire (il conto alla rovescia lo fa iOS, anche ad app chiusa).
        var esci: Date?
        /// TRAVEL: la sigla della prima linea («M1»), il suo colore (esadecimale) e l'ora del mezzo («19:27»).
        var sigla: String?
        var coloreSigla: String?
        var oraMezzo: String?
        /// GUIDA: la freccia della svolta (↱ ↰ ↑ ⚑), la via e i metri alla svolta.
        var freccia: String?
        var via: String?
        var metri: Int?
        /// La riga sotto, nell'isola grande: il percorso (TRAVEL) o la svolta dopo e l'arrivo (GUIDA).
        var riga: String
    }
    /// Dove va: il luogo di SATELLITE.
    var meta: String
}
