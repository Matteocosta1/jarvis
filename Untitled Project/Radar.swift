#if os(iOS)
import SwiftUI
import Combine
import CoreLocation
import UIKit

/// Meteo › RADAR (build 22). Il cervello sa dove si trova il signore anche con l'app chiusa: quando lui si sposta di
/// parecchio (spostamenti significativi di iOS, circa mezzo chilometro) l'iPhone gli manda la posizione.
/// Serve il permesso «Sempre». Quando sta per piovere il cervello manda una notifica (una per pioggia).
@MainActor
final class PosizioneSfondo: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let condiviso = PosizioneSfondo()
    @Published private(set) var sempre = false              // permesso «Sempre» dato
    @Published private(set) var negato = false              // chiesto «Sempre» ma iOS non l'ha dato (o la posizione è negata)
    private let gestore = CLLocationManager()
    private var ultimaInviata: (lat: Double, lon: Double, quando: Date)?

    override init() {
        super.init()
        gestore.delegate = self
        sempre = gestore.authorizationStatus == .authorizedAlways
    }

    /// All'avvio (anche quando iOS riapre l'app in sottofondo per uno spostamento): con «Sempre», segue gli spostamenti grandi.
    func avvia() {
        sempre = gestore.authorizationStatus == .authorizedAlways
        if sempre { negato = false }
        guard sempre, CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        gestore.startMonitoringSignificantLocationChanges()
    }

    /// Solo dal tasto «Attiva» del pannello RADAR, mai da sola: chiede «Sempre» (con «Quando in uso» è il passaggio a «Sempre»).
    /// iOS mostra la domanda una volta sola: se non la mostra, o la risposta non è «Sempre», `negato` lo dice
    /// e il pannello spiega dove abilitarla in Impostazioni.
    func chiediSempre() {
        switch gestore.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            negato = false
            gestore.requestAlwaysAuthorization()
            Task {
                // con la domanda di iOS a schermo l'app non è attiva: si aspetta la risposta, poi si guarda com'è andata
                try? await Task.sleep(for: .seconds(1))
                while UIApplication.shared.applicationState != .active { try? await Task.sleep(for: .milliseconds(300)) }
                try? await Task.sleep(for: .milliseconds(500))
                self.sempre = self.gestore.authorizationStatus == .authorizedAlways
                self.negato = !self.sempre
            }
        case .authorizedAlways:
            sempre = true
        default:
            negato = true                                     // negata o limitata: si cambia solo in Impostazioni
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.avvia() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let lat = l.coordinate.latitude, lon = l.coordinate.longitude, precisione = l.horizontalAccuracy, quando = l.timestamp
        Task { @MainActor in await self.invia(lat: lat, lon: lon, precisione: precisione, quando: quando) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    /// Al cervello: { "posizione_aggiorna": { lat, lon, precisione, quando } }, con la parola d'ordine di sempre.
    private func invia(lat: Double, lon: Double, precisione: Double, quando: Date) async {
        // un doppione (stesso posto, meno di un minuto fa) non parte
        if let u = ultimaInviata, Date().timeIntervalSince(u.quando) < 60,
           Rotta.metri(lat: u.lat, lon: u.lon, versoLat: lat, versoLon: lon) < 200 { return }
        let token = Portachiavi.leggi()
        guard !token.isEmpty, let url = URL(string: Impostazioni.indirizzo) else { return }
        ultimaInviata = (lat, lon, Date())
        // iOS ci lascia finire la richiesta anche se l'app è stata svegliata in sottofondo solo per questo
        let sfondo = UIApplication.shared.beginBackgroundTask(withName: "jarvis-posizione") { }
        defer { if sfondo != .invalid { UIApplication.shared.endBackgroundTask(sfondo) } }
        let iso = ISO8601DateFormatter()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        let posizione: [String: Any] = ["lat": lat, "lon": lon, "precisione": precisione, "quando": iso.string(from: quando)]
        let corpo: [String: Any] = ["posizione_aggiorna": posizione, "dispositivo": Impostazioni.dispositivo]
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        _ = try? await URLSession.shared.data(for: req)
    }
}

/// La pioggia in arrivo dal cervello: { "radar": true, "lat", "lon" } → { piove, inizia_min, mm_30, smette }.
enum Radar {
    static func chiedi() async -> DatiRadar? {
        var corpo: [String: Any] = ["radar": true]
        if let p = await Posizione.attuale(), let lat = p["lat"] as? Double, let lon = p["lon"] as? Double {
            corpo["lat"] = lat
            corpo["lon"] = lon
        }
        guard let o = await VistaVitals.chiama(corpo, attesa: 15) else { return nil }
        return DatiRadar(o)
    }
}

/// In testa al Meteo, come nel mockup: l'avviso (solo se sta per piovere), il pannello RADAR e A VOCE.
struct PannelloRadar: View {
    let radar: DatiRadar?
    let finito: Bool                     // il cervello ha risposto (o non ha risposto in tempo)
    @ObservedObject private var posizione = PosizioneSfondo.condiviso
    @Environment(\.openURL) private var apriLink
    private let tinta = Color.ciano

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let r = radar, r.piove { AvvisoJarvis(testo: r.avviso) }
            Pannello(titolo: "RADAR", tinta: tinta) {
                if let r = radar {
                    if r.piove {
                        RigaHUD("Inizia", r.inizia)
                        RigaHUD("Quanta", "\(r.millimetri) mm in mezz'ora")
                        RigaHUD("Smette", r.smette.isEmpty ? "—" : r.smette)
                    } else {
                        Text("Nessuna pioggia in arrivo").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                    }
                } else {
                    Text(finito ? "Il radar non risponde, Sir." : "Controllo il radar…").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                }
                Text("JARVIS avvisa una volta sola, solo quando sta per piovere dove si trova lei.")
                    .font(.system(size: 11)).foregroundStyle(Color.tenue)
                if !posizione.sempre {
                    // il permesso «Sempre» si chiede solo a questo tocco, mai da solo all'apertura del Meteo
                    HStack(spacing: 10) {
                        Text("Avviso pioggia spento").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                        Spacer(minLength: 8)
                        TastoComando(testo: "Attiva", corto: true) { posizione.chiediSempre() }
                    }
                    if posizione.negato {
                        Button {
                            if let u = URL(string: UIApplication.openSettingsURLString) { apriLink(u) }
                        } label: {
                            Text("iOS non ha dato la posizione «Sempre», Sir: la attivi in Impostazioni › Jarvis › Posizione › Sempre.")
                                .font(.system(size: 11)).foregroundStyle(.orange).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            PannelloAVoce(frasi: ["«Jarvis, radar pioggia»", "«Jarvis, pioverà?»", "«Jarvis, mi serve l'ombrello?»"])
        }
    }
}
#endif
