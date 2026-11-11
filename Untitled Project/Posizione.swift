#if os(iOS)
import Foundation
import CoreLocation

/// Dove si trova il signore: la posizione dell'iPhone va al cervello con ogni richiesta,
/// così la seconda memoria sa dove è stato salvato ogni ricordo (luoghi, oggetti, persone).
/// Solo «mentre usa l'app», mai in sottofondo. Stessa frase di permesso già usata dal meteo.
/// Per non far aspettare le risposte, il GPS parte appena l'app si apre e la domanda al massimo aspetta un secondo.
@MainActor
enum Posizione {
    private static let gestore: CLLocationManager = {
        let g = CLLocationManager()
        g.desiredAccuracy = kCLLocationAccuracyHundredMeters   // basta per via e città, consuma poco
        g.distanceFilter = 25
        return g
    }()
    private static var spegni: Task<Void, Never>?

    /// Da chiamare quando l'app torna in primo piano: il GPS si scalda, così la prima domanda non aspetta.
    static func risveglia() {
        let stato = gestore.authorizationStatus
        if stato == .notDetermined { gestore.requestWhenInUseAuthorization(); return }
        guard stato == .authorizedWhenInUse || stato == .authorizedAlways else { return }
        gestore.startUpdatingLocation()
        spegni?.cancel()
        spegni = Task { @MainActor in                      // dopo 3 minuti si ferma da solo (batteria); si riaccende alla prossima domanda
            try? await Task.sleep(for: .seconds(180))
            gestore.stopUpdatingLocation()
        }
    }

    static func dormi() {
        spegni?.cancel()
        gestore.stopUpdatingLocation()
        ultimoScaldato = .distantPast
    }

    private static var ultimoScaldato = Date.distantPast
    /// Difetto 5 (controllo del 25 ott): JARVIS comincia ad ascoltare. Il GPS si sveglia adesso, mentre il signore dice la frase
    /// (1-3 secondi), così la domanda non aspetta la posizione (prima fino a 1 secondo dopo una pausa di oltre 3 minuti).
    /// Al massimo una volta ogni 30 secondi: in una conversazione fitta il GPS è già acceso.
    static func scalda() {
        guard Date().timeIntervalSince(ultimoScaldato) > 30 else { return }
        ultimoScaldato = Date()
        risveglia()
    }

    /// La posizione da mandare con la domanda, SENZA far aspettare la domanda (11 nov, analisi dei tempi): con il signore fermo
    /// il GPS (filtro di 25 m) non manda più letture nuove, e dopo 3 minuti ogni domanda aspettava fino a 1 secondo in più.
    /// Ora: c'è una posizione (anche di qualche minuto fa, da fermo è la stessa)? Va subito, e intanto se ne chiede una nuova per
    /// la prossima domanda. Solo se non ce n'è nessuna si aspetta, al massimo 1 secondo. Niente posizione = nil: JARVIS lavora lo stesso.
    static func attuale() async -> [String: Any]? {
        let stato = gestore.authorizationStatus
        if stato == .notDetermined { gestore.requestWhenInUseAuthorization(); return nil }
        guard stato == .authorizedWhenInUse || stato == .authorizedAlways else { return nil }
        if let l = fresca() { return dizionario(l) }
        // revisione 11 nov: solo se non è troppo vecchia (15 minuti). Una posizione di ore fa può essere di un'altra città (app
        // rimasta chiusa durante un viaggio) e finirebbe nei ricordi come «dove l'ho messo»: allora si aspetta quella nuova
        if let l = gestore.location, l.horizontalAccuracy >= 0, Date().timeIntervalSince(l.timestamp) < 900 {
            rinfresca()                                    // la prossima domanda avrà quella nuova
            return dizionario(l)
        }
        gestore.stopUpdatingLocation()                     // fermo e riavvio: anche da fermo arriva subito una lettura nuova
        risveglia()
        for _ in 0..<10 {                                  // nessuna posizione: fino a 1 secondo, a passi di 100 ms
            try? await Task.sleep(for: .milliseconds(100))
            if let l = fresca() { return dizionario(l) }
        }
        // niente di fresco in 1 secondo: quella vecchia va bene solo se recente (15 minuti), altrimenti meglio nessuna
        guard let l = gestore.location, l.horizontalAccuracy >= 0, Date().timeIntervalSince(l.timestamp) < 900 else { return nil }
        return dizionario(l)
    }

    private static var ultimoRinfresco = Date.distantPast
    /// Una lettura nuova in sottofondo: fermare e riavviare il GPS lo fa rispondere subito anche da fermo (col filtro di 25 m
    /// altrimenti tace). Al massimo una volta ogni 30 secondi.
    private static func rinfresca() {
        guard Date().timeIntervalSince(ultimoRinfresco) > 30 else { return }
        ultimoRinfresco = Date()
        gestore.stopUpdatingLocation()
        risveglia()
    }

    private static func fresca() -> CLLocation? {
        guard let l = gestore.location, l.horizontalAccuracy >= 0, Date().timeIntervalSince(l.timestamp) < 180 else { return nil }
        return l
    }

    private static func dizionario(_ l: CLLocation) -> [String: Any] {
        ["lat": l.coordinate.latitude, "lon": l.coordinate.longitude, "precisione": l.horizontalAccuracy]
    }
}
#endif
