#if os(iOS)
import Combine
import CoreLocation
import Foundation

/// BUILD 23: la GUIDA di SATELLITE in corso, condivisa con il resto dell'app (come nel mockup: GUIDA_ATTIVA).
/// La scrive solo SATELLITE (Satellite.swift); la leggono gli OCCHI (la freccia olografica in basso finché la guida è attiva)
/// e la chiude «ferma la guida» o l'arrivo. Resta attiva anche con SATELLITE chiuso.
@MainActor
final class GuidaCondivisa: ObservableObject {
    static let condivisa = GuidaCondivisa()

    /// La svolta della prossima tappa, come le frecce del mockup (↑ dritto, ↱ destra, ↰ sinistra, ⚑ arrivo).
    enum Svolta: String, Sendable { case dritto, destra, sinistra, arrivo
        var freccia: String { switch self { case .dritto: "↑"; case .destra: "↱"; case .sinistra: "↰"; case .arrivo: "⚑" } }
    }

    struct Stato: Equatable, Sendable {
        var luogo: String                 // «Studio»
        var destinazione: CLLocationCoordinate2D
        var svolta: Svolta                // la prossima svolta
        var istruzione: String            // «A destra in Via Tortona» (le istruzioni di Apple, in italiano)
        var metriSvolta: Double           // metri alla prossima svolta
        var metriArrivo: Double           // metri all'arrivo
        /// Il rilevamento (gradi dal nord, 0–360) verso il prossimo punto del percorso: gli Occhi lo confrontano con la bussola.
        var rilevamento: Double?

        static func == (a: Stato, b: Stato) -> Bool {
            a.luogo == b.luogo && a.destinazione.latitude == b.destinazione.latitude && a.destinazione.longitude == b.destinazione.longitude
                && a.svolta == b.svolta && a.istruzione == b.istruzione && a.metriSvolta == b.metriSvolta && a.metriArrivo == b.metriArrivo
                && a.rilevamento == b.rilevamento
        }
    }

    /// nil = nessuna guida.
    @Published var stato: Stato?

    func ferma() { stato = nil }
}
#endif
