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

    /// Posizione recente (al massimo 3 minuti), oppure una nuova lettura aspettando al massimo 1 secondo.
    /// Niente posizione = nil: JARVIS lavora lo stesso.
    static func attuale() async -> [String: Any]? {
        let stato = gestore.authorizationStatus
        if stato == .notDetermined { gestore.requestWhenInUseAuthorization(); return nil }
        guard stato == .authorizedWhenInUse || stato == .authorizedAlways else { return nil }
        if let l = fresca() { return dizionario(l) }
        risveglia()
        for _ in 0..<10 {                                  // fino a 1 secondo, a passi di 100 ms
            try? await Task.sleep(for: .milliseconds(100))
            if let l = fresca() { return dizionario(l) }
        }
        return gestore.location.map(dizionario)            // anche una vecchia è meglio di niente
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
