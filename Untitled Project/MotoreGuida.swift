#if os(iOS)
import Foundation
import Combine
import CoreLocation
import MapKit
import UIKit

/// Un valore qualsiasi da passare in una continuazione (MapKit risponde con oggetti non Sendable).
nonisolated final class ScatolaSat<T>: @unchecked Sendable {
    let valore: T
    init(_ valore: T) { self.valore = valore }
}

// MARK: - Il percorso a piedi (MKDirections, con le istruzioni di Apple in italiano)

/// Una tappa del percorso: la svolta da fare all'inizio, il testo di Apple («Svolta a destra in Via Tortona»), la via,
/// quanto è lunga e dove comincia. L'ultima è l'arrivo.
struct TappaSat: Identifiable {
    let id: Int
    let svolta: GuidaCondivisa.Svolta
    let testo: String
    let via: String
    let metri: Double                 // lunghezza della tappa
    let inizio: Double                // metri dalla partenza al punto della svolta
    let punto: CLLocationCoordinate2D // dove si fa la svolta (per la vista da strada)
    let rotta: Double?                // la direzione di marcia appena dopo la svolta, gradi dal nord
}

/// Perché il percorso non c'è.
enum ErroreSat: Error {
    case posizione, percorso
    var testo: String {
        switch self {
        case .posizione: return "Non ho la sua posizione, Sir."
        case .percorso: return "Non trovo una strada a piedi fino a lì, Sir."
        }
    }
}

/// Il percorso a piedi verso un luogo: le tappe e la linea, con i metri cumulati per sapere a che punto si è.
struct PercorsoSat {
    let luogo: LuogoSat
    let tappe: [TappaSat]
    let punti: [CLLocationCoordinate2D]
    let cumulati: [Double]            // metri dalla partenza a ogni punto della linea
    let metri: Double

    /// Il percorso da qui al luogo (MKDirections, a piedi).
    static func calcola(da: CLLocationCoordinate2D, a luogo: LuogoSat) async -> Result<PercorsoSat, ErroreSat> {
        guard let r = await rotta(da: da, a: luogo.coordinata)?.valore, !r.steps.isEmpty else { return .failure(.percorso) }
        return .success(PercorsoSat(luogo: luogo, rotta: r))
    }

    /// MKDirections a piedi, con il gestore di completamento (chiamato da MapKit sul thread principale).
    private static func rotta(da: CLLocationCoordinate2D, a: CLLocationCoordinate2D) async -> ScatolaSat<MKRoute>? {
        let q = MKDirections.Request()
        q.source = MKMapItem(placemark: MKPlacemark(coordinate: da))
        q.destination = MKMapItem(placemark: MKPlacemark(coordinate: a))
        q.transportType = .walking
        q.requestsAlternateRoutes = false
        let d = ScatolaSat(MKDirections(request: q))          // resta vivo finché MapKit non risponde
        return await withCheckedContinuation { (c: CheckedContinuation<ScatolaSat<MKRoute>?, Never>) in
            d.valore.calculate { @Sendable risposta, _ in
                _ = d
                c.resume(returning: risposta?.routes.first.map { ScatolaSat($0) })
            }
        }
    }

    private init(luogo: LuogoSat, rotta r: MKRoute) {
        self.luogo = luogo
        // la linea intera del percorso e i metri cumulati
        let n = r.polyline.pointCount
        let mp = r.polyline.points()
        var punti: [CLLocationCoordinate2D] = []
        punti.reserveCapacity(n)
        for k in 0..<n { punti.append(mp[k].coordinate) }
        var cumulati: [Double] = [0]
        for k in 1..<max(1, punti.count) {
            cumulati.append(cumulati[k - 1] + Rotta.metri(lat: punti[k - 1].latitude, lon: punti[k - 1].longitude,
                                                          versoLat: punti[k].latitude, versoLon: punti[k].longitude))
        }
        self.punti = punti
        self.cumulati = cumulati
        self.metri = max(r.distance, cumulati.last ?? 0)
        // le tappe: i passi di Apple con un'istruzione (il primo, vuoto, è il punto di partenza); l'ultimo è l'arrivo
        var tappe: [TappaSat] = []
        var acc = 0.0
        var rottaPrima: Double?
        let passi = r.steps
        for (k, p) in passi.enumerated() {
            let testo = p.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let pp = p.polyline.points()
            let coords = (0..<p.polyline.pointCount).map { pp[$0].coordinate }
            let rottaDopo = PercorsoSat.direzione(coords)
            defer {
                acc += p.distance
                if let d = PercorsoSat.direzioneFinale(coords) { rottaPrima = d }
            }
            let ultima = k == passi.count - 1
            if testo.isEmpty && !ultima { continue }
            let svolta: GuidaCondivisa.Svolta
            if ultima { svolta = .arrivo }
            else if tappe.isEmpty { svolta = PercorsoSat.svoltaDalTesto(testo) ?? .dritto }
            else { svolta = PercorsoSat.svoltaDalTesto(testo) ?? PercorsoSat.svoltaDagliAngoli(prima: rottaPrima, dopo: rottaDopo) }
            let punto = coords.first ?? luogo.coordinata
            tappe.append(TappaSat(id: tappe.count, svolta: svolta, testo: testo.isEmpty ? "Arrivo: \(luogo.via)" : testo,
                                  via: ultima ? luogo.via : PercorsoSat.via(testo), metri: p.distance, inizio: acc, punto: punto, rotta: rottaDopo))
        }
        self.tappe = tappe
    }

    /// «Svolta a destra in Via Tortona» → destra. Le istruzioni sono nella lingua dell'iPhone (italiano; l'inglese per sicurezza).
    private static func svoltaDalTesto(_ t: String) -> GuidaCondivisa.Svolta? {
        let x = t.lowercased()
        if x.contains("destra") || x.contains(" right") { return .destra }
        if x.contains("sinistra") || x.contains(" left") { return .sinistra }
        return nil
    }

    /// Senza parole chiare: dall'angolo tra la strada di prima e quella dopo (oltre 30°: una svolta).
    private static func svoltaDagliAngoli(prima: Double?, dopo: Double?) -> GuidaCondivisa.Svolta {
        guard let prima, let dopo else { return .dritto }
        let d = Rotta.relativa(rilevamento: dopo, direzione: prima)
        return d > 30 ? .destra : d < -30 ? .sinistra : .dritto
    }

    /// La via nell'istruzione: quello che viene dopo «in», «su», «verso» («Svolta a destra in Via Tortona» → «Via Tortona»).
    private static func via(_ testo: String) -> String {
        for chiave in [" in ", " su ", " verso ", " onto ", " on "] {
            if let r = testo.range(of: chiave, options: [.backwards, .caseInsensitive]) {
                let v = testo[r.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
                if !v.isEmpty { return v }
            }
        }
        return testo
    }

    /// La direzione dei primi metri di una linea (il primo punto diverso dal primo).
    private static func direzione(_ c: [CLLocationCoordinate2D]) -> Double? {
        guard let a = c.first, let b = c.dropFirst().first(where: { Rotta.metri(lat: a.latitude, lon: a.longitude, versoLat: $0.latitude, versoLon: $0.longitude) > 2 }) else { return nil }
        return Rotta.rilevamento(lat: a.latitude, lon: a.longitude, versoLat: b.latitude, versoLon: b.longitude)
    }

    /// La direzione degli ultimi metri di una linea.
    private static func direzioneFinale(_ c: [CLLocationCoordinate2D]) -> Double? {
        guard let b = c.last, let a = c.dropLast().last(where: { Rotta.metri(lat: $0.latitude, lon: $0.longitude, versoLat: b.latitude, versoLon: b.longitude) > 2 }) else { return nil }
        return Rotta.rilevamento(lat: a.latitude, lon: a.longitude, versoLat: b.latitude, versoLon: b.longitude)
    }

    /// A che punto del percorso si è: i metri lungo la linea e quanto se ne è lontani. Si cerca dal punto di prima
    /// (meno 30 m) in avanti, così un percorso che torna vicino a sé stesso non fa saltare indietro.
    func avanzamento(lat: Double, lon: Double, oltre: Double) -> (metri: Double, scarto: Double) {
        guard punti.count >= 2 else { return (0, Rotta.metri(lat: lat, lon: lon, versoLat: luogo.lat, versoLon: luogo.lon)) }
        let kx = cos(lat * .pi / 180) * 111_320, ky = 110_540.0
        var migliore = (metri: 0.0, scarto: Double.greatestFiniteMagnitude)
        for i in 0..<(punti.count - 1) where cumulati[i + 1] >= oltre - 30 {
            let ax = (punti[i].longitude - lon) * kx, ay = (punti[i].latitude - lat) * ky
            let bx = (punti[i + 1].longitude - lon) * kx, by = (punti[i + 1].latitude - lat) * ky
            let dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
            let t = l2 > 0 ? max(0, min(1, -(ax * dx + ay * dy) / l2)) : 0
            let px = ax + dx * t, py = ay + dy * t
            let d = sqrt(px * px + py * py)
            if d < migliore.scarto { migliore = (cumulati[i] + (cumulati[i + 1] - cumulati[i]) * t, d) }
        }
        return migliore
    }

    /// Il punto del percorso a `m` metri dalla partenza (oltre la fine: il luogo).
    func punto(a m: Double) -> CLLocationCoordinate2D {
        guard punti.count >= 2, m < (cumulati.last ?? 0) else { return luogo.coordinata }
        guard let i = cumulati.lastIndex(where: { $0 <= m }), i + 1 < punti.count else { return punti[0] }
        let l = cumulati[i + 1] - cumulati[i]
        let t = l > 0 ? (m - cumulati[i]) / l : 0
        return CLLocationCoordinate2D(latitude: punti[i].latitude + (punti[i + 1].latitude - punti[i].latitude) * t,
                                      longitude: punti[i].longitude + (punti[i + 1].longitude - punti[i].longitude) * t)
    }

    /// La tappa in corso a `m` metri dalla partenza (si entra in una tappa 8 m prima della sua svolta).
    func indice(per m: Double) -> Int {
        tappe.lastIndex(where: { $0.inizio <= m + 8 }) ?? 0
    }

    /// I metri dalla partenza alla fine della tappa `i` (la svolta dopo, o l'arrivo).
    func fine(tappa i: Int) -> Double {
        i + 1 < tappe.count ? tappe[i + 1].inizio : metri
    }
}

// MARK: - La vista da strada (Look Around di Apple)

enum VistaStrada {
    /// La scena di Look Around più vicina a un punto (nil: lì Apple non ha la vista da strada).
    static func scena(_ c: CLLocationCoordinate2D) async -> MKLookAroundScene? {
        await chiedi(MKLookAroundSceneRequest(coordinate: c))
    }

    /// La scena che guarda un luogo (Apple sceglie da dove inquadrarlo).
    static func scena(guardando c: CLLocationCoordinate2D) async -> MKLookAroundScene? {
        await chiedi(MKLookAroundSceneRequest(mapItem: MKMapItem(placemark: MKPlacemark(coordinate: c))))
    }

    private static func chiedi(_ r: MKLookAroundSceneRequest) async -> MKLookAroundScene? {
        let q = ScatolaSat(r)                                 // resta viva finché MapKit non risponde
        let s = await withCheckedContinuation { (c: CheckedContinuation<ScatolaSat<MKLookAroundScene?>, Never>) in
            q.valore.getSceneWithCompletionHandler { @Sendable scena, _ in _ = q; c.resume(returning: ScatolaSat(scena)) }
        }
        return s.valore
    }

    /// Una foto ferma della scena (MKLookAroundSnapshotter), della misura chiesta in punti.
    static func foto(_ scena: MKLookAroundScene, larga: CGFloat, alta: CGFloat) async -> UIImage? {
        let o = MKLookAroundSnapshotter.Options()
        o.size = CGSize(width: larga, height: alta)
        return await scatta(MKLookAroundSnapshotter(scene: scena, options: o))
    }

    private static func scatta(_ s: MKLookAroundSnapshotter) async -> UIImage? {
        let q = ScatolaSat(s)                                 // resta vivo finché MapKit non risponde
        let r = await withCheckedContinuation { (c: CheckedContinuation<ScatolaSat<UIImage?>, Never>) in
            q.valore.getSnapshotWithCompletionHandler { @Sendable foto, _ in _ = q; c.resume(returning: ScatolaSat(foto?.image)) }
        }
        return r.valore
    }
}

// MARK: - La GUIDA in corso

/// La GUIDA di SATELLITE: la posizione e la bussola, il percorso, la tappa in corso, i metri che scendono, la voce
/// di JARVIS a ogni svolta e all'arrivo. Vive fuori dalla sezione: resta attiva anche con SATELLITE chiuso
/// (negli Occhi la freccia, al polso la guida) finché arriva o il signore dice «ferma la guida».
/// Scrive GuidaCondivisa (letta dagli Occhi) e la manda all'orologio.
@MainActor
final class MotoreGuida: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let condiviso = MotoreGuida()

    @Published private(set) var luogo: LuogoSat?
    @Published private(set) var percorso: PercorsoSat?
    @Published private(set) var indice = 0
    @Published private(set) var fatti = 0.0          // metri già fatti lungo il percorso
    @Published private(set) var arrivato = false
    @Published private(set) var errore: String?
    @Published private(set) var lat: Double?
    @Published private(set) var lon: Double?
    @Published private(set) var direzione: Double?   // dove guarda l'iPhone, gradi dal nord
    /// La voce di JARVIS (la imposta la schermata principale: Jarvis.annuncia).
    var parla: ((String) -> Void)?

    var attiva: Bool { luogo != nil }
    var tappa: TappaSat? { percorso.flatMap { $0.tappe.indices.contains(indice) ? $0.tappe[indice] : nil } }
    /// Metri alla fine della tappa in corso (la prossima svolta, o l'arrivo).
    var mancaTappa: Double? { percorso.map { max(0, $0.fine(tappa: indice) - fatti) } }
    /// Metri all'arrivo.
    var manca: Double? { percorso.map { max(0, $0.metri - fatti) } }
    /// Gradi dal nord verso il punto del percorso 20 m più avanti: la freccia della guida.
    var rilevamento: Double? {
        guard let p = percorso, let lat, let lon else { return nil }
        let q = p.punto(a: fatti + 20)
        return Rotta.rilevamento(lat: lat, lon: lon, versoLat: q.latitude, versoLon: q.longitude)
    }

    private let gestore = CLLocationManager()
    private var generazione = 0
    private var fuoriDa: Date?
    private var ultimoRicalcolo = Date.distantPast
    private var ultimoPolso = Date.distantPast
    private var osserva: AnyCancellable?

    override init() {
        super.init()
        gestore.delegate = self
        gestore.desiredAccuracy = kCLLocationAccuracyBest
        gestore.distanceFilter = 3
        gestore.headingFilter = 2
        gestore.activityType = .fitness
        // la guida chiusa da fuori (GuidaCondivisa.ferma(), per esempio dagli Occhi): si ferma anche qui
        osserva = GuidaCondivisa.condivisa.$stato.sink { [weak self] s in
            guard s == nil, let io = self else { return }
            Task { @MainActor in io.chiusaDaFuori() }          // dopo: il valore nuovo arriva prima di essere scritto
        }
    }

    /// Parte la guida verso un luogo (se è già in corso verso lo stesso, continua; se lì non era partita, riprova).
    func avvia(_ l: LuogoSat) {
        // la stessa meta: continua solo se la guida c'è (o si sta calcolando). Se non era partita (niente posizione,
        // niente strada) si riprova: prima restava ferma sull'errore e «guidami allo studio» non faceva più niente
        if let attuale = luogo, attuale.chiave == l.chiave, !arrivato, percorso != nil || errore == nil { return }
        generazione += 1
        let g = generazione
        luogo = l
        percorso = nil
        indice = 0
        fatti = 0
        arrivato = false
        errore = nil
        fuoriDa = nil
        // un'altra meta: la freccia negli Occhi della meta di prima si spegne subito (finché arriva il percorso nuovo;
        // se il percorso nuovo non si trova, restava accesa verso la meta vecchia). Il percorso è nil: la guida nuova non si ferma
        if GuidaCondivisa.condivisa.stato != nil { GuidaCondivisa.condivisa.ferma() }
        accendi()
        Task { await calcola(g, da: nil) }
    }

    /// Fine della guida («Fine guida», «ferma la guida», l'arrivo). Spegne il GPS se nessuno lo usa più.
    func ferma() {
        generazione += 1
        let c_era = luogo != nil
        luogo = nil
        percorso = nil
        arrivato = false
        errore = nil
        indice = 0
        fatti = 0
        spegniPosizione()
        if GuidaCondivisa.condivisa.stato != nil { GuidaCondivisa.condivisa.ferma() }
        if c_era { PonteTelefono.condiviso.inviaGuida(nil) }
    }

    /// La posizione e la bussola, anche senza guida (le schermate NAVIGA e GUIDA le usano per i metri e le frecce).
    func accendi() {
        if gestore.authorizationStatus == .notDetermined { gestore.requestWhenInUseAuthorization() }
        // con la modalità «posizione in sottofondo» nell'Info.plist (build 23, decisione 17) la guida continua anche a telefono
        // bloccato, con la freccia blu di iOS (senza la modalità, impostarla farebbe chiudere l'app: si controlla prima).
        // Solo con una guida in corso: NAVIGA e GUIDA aperte senza guida restano «solo con JARVIS aperto»
        if Self.posizioneInSottofondo {
            gestore.allowsBackgroundLocationUpdates = luogo != nil
            gestore.showsBackgroundLocationIndicator = true
        }
        // con una guida in corso iOS non deve mettere in pausa il GPS quando lei si ferma (a un semaforo, a parlare):
        // a telefono bloccato una pausa non si riprende più da sola e la guida resterebbe ferma
        gestore.pausesLocationUpdatesAutomatically = luogo == nil
        gestore.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { gestore.startUpdatingHeading() }
    }

    /// La modalità «posizione in sottofondo» (UIBackgroundModes › location) è nell'Info.plist dell'app.
    static var posizioneInSottofondo: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []).contains("location")
    }

    /// La guida può partire con JARVIS in sottofondo (chiesta dall'orologio con l'iPhone in tasca): serve la modalità
    /// «posizione in sottofondo» e il permesso «Sempre». Con «Durante l'uso» iOS dà la posizione solo se la guida è partita
    /// con JARVIS aperto (poi continua anche a telefono bloccato, con la freccia blu).
    var puoPartireInSottofondo: Bool {
        Self.posizioneInSottofondo && gestore.authorizationStatus == .authorizedAlways
    }

    /// Le schermate si chiudono: se non c'è una guida in corso, il GPS si spegne. Una guida che non è mai partita
    /// (niente posizione o niente strada: c'è solo l'errore) non è «in corso»: finisce anche lei, se no il GPS restava
    /// acceso a vuoto finché lei diceva «ferma la guida».
    func spegniSeLibero() {
        if luogo != nil, percorso == nil, errore != nil { ferma(); return }
        guard luogo == nil else { return }
        spegniPosizione()
    }

    /// GPS e bussola spenti; la posizione vecchia si dimentica (la prossima guida aspetta quella nuova).
    private func spegniPosizione() {
        gestore.stopUpdatingLocation()
        gestore.stopUpdatingHeading()
        lat = nil
        lon = nil
        direzione = nil
    }

    private func chiusaDaFuori() {
        guard luogo != nil, !arrivato, GuidaCondivisa.condivisa.stato == nil, percorso != nil else { return }
        ferma()
    }

    /// La posizione è negata nelle impostazioni (o bloccata): non arriverà, inutile aspettarla.
    var posizioneNegata: Bool {
        let s = gestore.authorizationStatus
        return s == .denied || s == .restricted
    }

    private func calcola(_ g: Int, da partenza: CLLocationCoordinate2D?) async {
        // la posizione: fino a 10 secondi (negata: la frase subito, invece di 10 secondi di attesa a vuoto)
        for _ in 0..<50 where lat == nil && !posizioneNegata {
            try? await Task.sleep(for: .milliseconds(200))
            guard g == generazione else { return }
        }
        guard g == generazione, let l = luogo else { return }
        guard let la = lat, let lo = lon else { errore = ErroreSat.posizione.testo; return }
        let da = partenza ?? CLLocationCoordinate2D(latitude: la, longitude: lo)
        let esito = await PercorsoSat.calcola(da: da, a: l)
        guard g == generazione else { return }
        switch esito {
        case .success(let p):
            percorso = p
            errore = nil
            indice = 0
            fatti = 0
            aggiorna()
            inviaPolso(forza: true)
        case .failure(let e):
            if percorso == nil { errore = e.testo }
        }
    }

    /// A ogni posizione nuova: a che punto è, la tappa, l'arrivo, il percorso da rifare se è uscito di strada.
    private func aggiorna() {
        guard let p = percorso, let l = luogo, let la = lat, let lo = lon, !arrivato else { return }
        let (m, scarto) = p.avanzamento(lat: la, lon: lo, oltre: fatti)
        fatti = m
        // uscito dal percorso (oltre 40 m per più di 8 secondi): un percorso nuovo da qui, al massimo ogni 20 secondi
        if scarto > 40 {
            if let da = fuoriDa {
                if Date().timeIntervalSince(da) > 8, Date().timeIntervalSince(ultimoRicalcolo) > 20 {
                    ultimoRicalcolo = Date()
                    fuoriDa = nil
                    let g = generazione
                    Task { await calcola(g, da: CLLocationCoordinate2D(latitude: la, longitude: lo)) }
                }
            } else { fuoriDa = Date() }
        } else { fuoriDa = nil }
        // arrivato: a meno di 12 m dalla fine del percorso o a meno di 15 m dal luogo
        let dritto = Rotta.metri(lat: la, lon: lo, versoLat: l.lat, versoLon: l.lon)
        if p.metri - fatti < 12 || dritto < 15 { arrivo(); return }
        let nuovo = p.indice(per: fatti)
        if nuovo > indice {
            indice = nuovo
            if nuovo < p.tappe.count - 1 { parla?("\(p.tappe[nuovo].testo), Sir.") }      // come il mockup: la svolta, detta
            inviaPolso(forza: true)
        }
        pubblica()
        inviaPolso(forza: false)
    }

    private func arrivo() {
        guard let l = luogo else { return }
        arrivato = true
        indice = max(0, (percorso?.tappe.count ?? 1) - 1)
        if let p = percorso { fatti = p.metri }
        parla?("Arrivato, Sir: \(l.nome).")
        GuidaCondivisa.condivisa.ferma()                 // la freccia negli Occhi si spegne all'arrivo
        inviaPolso(forza: true)
        let g = generazione
        Task {
            try? await Task.sleep(for: .seconds(4))       // «ARRIVATO» resta a schermo per un attimo, poi la guida finisce
            if g == generazione { ferma() }
        }
    }

    /// La guida per gli Occhi (GuidaCondivisa): la prossima svolta con i metri, l'arrivo, la direzione del percorso.
    private func pubblica() {
        guard let p = percorso, let l = luogo, !arrivato, !p.tappe.isEmpty else { return }
        let prossima = p.tappe[min(indice + 1, p.tappe.count - 1)]
        // la via della svolta (decisione 21): solo se l'istruzione di Apple ne ha una («… in Via Tortona»); se no
        // TappaSat.via è l'istruzione intera, e gli Occhi scrivono quella come prima
        let via = prossima.svolta != .arrivo && !prossima.via.isEmpty && prossima.via != prossima.testo ? prossima.via : nil
        GuidaCondivisa.condivisa.stato = GuidaCondivisa.Stato(
            luogo: l.nome, destinazione: l.coordinata, svolta: prossima.svolta, istruzione: prossima.testo, via: via,
            metriSvolta: mancaTappa ?? 0, metriArrivo: manca ?? 0, rilevamento: rilevamento)
    }

    /// La guida all'orologio: a ogni tappa nuova subito, altrimenti al massimo una volta al secondo.
    private func inviaPolso(forza: Bool) {
        guard let l = luogo, let p = percorso, let t = tappa else { return }
        guard forza || Date().timeIntervalSince(ultimoPolso) >= 1 else { return }
        ultimoPolso = Date()
        let svolta = arrivato ? "arrivo" : t.svolta.rawValue
        let metri = t.svolta == .arrivo ? (manca ?? 0) : (mancaTappa ?? 0)
        PonteTelefono.condiviso.inviaGuida(GuidaPolsoDati(nome: l.nome, svolta: svolta, via: t.svolta == .arrivo ? l.nome : t.via,
                                                          metri: metri, manca: max(0, p.metri - fatti), rilevamento: rilevamento, arrivato: arrivato))
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 80 else { return }
        let a = l.coordinate.latitude, b = l.coordinate.longitude
        Task { @MainActor in
            self.lat = a
            self.lon = b
            self.aggiorna()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let g = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.direzione = g }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
#endif
