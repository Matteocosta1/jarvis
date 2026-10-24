import Foundation
import CoreLocation

/// Dove si trova il signore: la posizione dell'orologio va al cervello con ogni richiesta,
/// così la seconda memoria sa dove è stato salvato ogni ricordo (luoghi, oggetti, persone).
/// Solo «mentre usa l'app», mai in sottofondo. Stesso permesso già chiesto dall'allarme cuore.
/// Per non far aspettare le risposte, il GPS parte appena l'app si apre e la domanda al massimo aspetta 0,3 secondi.
@MainActor
enum PosizioneOrologio {
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
    /// Difetto 5 (controllo del 25 ott), come sull'iPhone: JARVIS comincia ad ascoltare e il GPS si sveglia adesso, mentre il
    /// signore parla, così la domanda non aspetta la posizione. Al massimo una volta ogni 30 secondi.
    static func scalda() {
        guard Date().timeIntervalSince(ultimoScaldato) > 30 else { return }
        ultimoScaldato = Date()
        risveglia()
    }

    /// Posizione recente (al massimo 3 minuti), oppure una nuova lettura aspettando al massimo 0,3 secondi.
    /// Niente posizione = nil: JARVIS lavora lo stesso.
    static func attuale() async -> [String: Any]? {
        let stato = gestore.authorizationStatus
        if stato == .notDetermined { gestore.requestWhenInUseAuthorization(); return nil }
        guard stato == .authorizedWhenInUse || stato == .authorizedAlways else { return nil }
        if let l = fresca() { return dizionario(l) }
        risveglia()
        for _ in 0..<3 {                                   // al polso al massimo 0,3 secondi: la velocità conta più della precisione
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
