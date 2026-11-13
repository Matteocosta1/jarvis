#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import CoreMotion
import CoreLocation
import Combine

// MARK: - MARK X · OCCHI · AEREO («Jarvis, che aereo è quello?»), come il mockup approvato (build 32)
// L'icona AEREO compare accanto a ETICHETTE · OLOGRAMMA · CERCA quando lo chiede a voce. JARVIS cerca in cielo (il radar),
// aggancia l'aereo con il mirino e la sagoma laser, apre la scheda con l'ologramma 3D che gira e il foglio con i dati del volo.
// Dati veri e gratis: gli aerei in volo intorno da adsb.lol (posizione, quota, velocità, tipo), la rotta e la compagnia da
// adsbdb. L'aereo sta sullo schermo dove sta davvero: posizione del telefono, bussola e inclinazione (Core Motion) e il campo
// visivo vero della fotocamera, con lo zoom.

/// Un aereo in volo intorno al signore (adsb.lol), con la posizione portata avanti tra un aggiornamento e l'altro.
nonisolated struct AereoInCielo: Sendable, Identifiable, Equatable {
    let id: String                  // codice ICAO esadecimale del trasponditore
    let nominativo: String          // «RYR3TZ» (il volo come lo chiama la radio), vuoto se non lo trasmette
    let matricola: String           // «9H-LOA»
    let tipo: String                // codice ICAO del modello: «A20N», «B738»
    let lat: Double
    let lon: Double
    let quota: Double               // metri sul livello del mare
    let variometro: Double          // piedi al minuto: >0 sale, <0 scende
    let velocita: Double            // km/h al suolo
    let rotta: Double               // gradi dal nord
    let quando: Date

    /// Dove si trova adesso, portato avanti dalla velocità e dalla rotta (al massimo 20 secondi).
    func posizione(_ adesso: Date) -> (lat: Double, lon: Double, quota: Double) {
        let dt = min(max(adesso.timeIntervalSince(quando), 0), 20)
        let metri = velocita / 3.6 * dt
        let r = rotta * .pi / 180
        let dLat = metri * cos(r) / 111_320
        let dLon = metri * sin(r) / (111_320 * max(cos(lat * .pi / 180), 0.01))
        return (lat + dLat, lon + dLon, quota + variometro * 0.3048 / 60 * dt)
    }
}

/// La rotta e la compagnia di un volo (adsbdb).
nonisolated struct RottaVolo: Sendable, Equatable {
    let compagnia: String           // «Ryanair»
    let volo: String                // «FR 3TZ»
    let da: String, daSigla: String // «Leeds», «LBA»
    let a: String, aSigla: String
    let aLat: Double?, aLon: Double?
}

nonisolated enum DatiAerei {
    /// Gli aerei entro 40 miglia nautiche (74 km) da dove si trova: adsb.lol, gratis, senza chiave.
    static func intorno(lat: Double, lon: Double) async -> [AereoInCielo]? {
        guard let u = URL(string: String(format: "https://api.adsb.lol/v2/point/%.4f/%.4f/40", lat, lon)) else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 8)
        r.setValue("JARVIS (iPhone)", forHTTPHeaderField: "User-Agent")
        guard let (d, risp) = try? await URLSession.shared.data(for: r), (risp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let ac = o["ac"] as? [[String: Any]] else { return nil }
        let adesso = Date()
        return ac.compactMap { a in
            guard let id = a["hex"] as? String, let la = num(a["lat"]), let lo = num(a["lon"]) else { return nil }
            // a terra (alt_baro "ground") o senza quota: non è in cielo
            guard let piedi = num(a["alt_geom"]) ?? num(a["alt_baro"]), piedi > 300 else { return nil }
            let vista = num(a["seen_pos"]) ?? 0
            guard vista < 60 else { return nil }
            return AereoInCielo(id: id,
                                nominativo: (a["flight"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                                matricola: a["r"] as? String ?? "",
                                tipo: a["t"] as? String ?? "",
                                lat: la, lon: lo, quota: piedi * 0.3048,
                                variometro: num(a["geom_rate"]) ?? num(a["baro_rate"]) ?? 0,
                                velocita: (num(a["gs"]) ?? 0) * 1.852,
                                rotta: num(a["track"]) ?? num(a["true_heading"]) ?? 0,
                                quando: adesso.addingTimeInterval(-vista))
        }
    }

    /// La rotta del volo dal nominativo (adsbdb, gratis). Nil se non si sa.
    static func rotta(_ nominativo: String) async -> RottaVolo? {
        guard !nominativo.isEmpty, let u = URL(string: "https://api.adsbdb.com/v0/callsign/\(nominativo)") else { return nil }
        guard let (d, risp) = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 8)),
              (risp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let f = (o["response"] as? [String: Any])?["flightroute"] as? [String: Any] else { return nil }
        let og = f["origin"] as? [String: Any] ?? [:], de = f["destination"] as? [String: Any] ?? [:]
        let comp = (f["airline"] as? [String: Any])?["name"] as? String ?? ""
        let iata = f["callsign_iata"] as? String ?? nominativo
        // «FR3TZ» → «FR 3TZ», come sui tabelloni
        let volo = iata.count > 2 ? "\(iata.prefix(2)) \(iata.dropFirst(2))" : iata
        func nome(_ p: [String: Any]) -> String {
            let n = p["name"] as? String ?? "", c = p["municipality"] as? String ?? ""
            return Self.nomeAeroporto(n, citta: c)
        }
        return RottaVolo(compagnia: comp, volo: volo, da: nome(og), daSigla: og["iata_code"] as? String ?? "",
                         a: nome(de), aSigla: de["iata_code"] as? String ?? "", aLat: num(de["latitude"]), aLon: num(de["longitude"]))
    }

    /// «Milano Linate» invece di «Milan Linate Airport»: la città in italiano (le più comuni) e il nome senza «Airport».
    static func nomeAeroporto(_ nome: String, citta: String) -> String {
        let it = ["Milan": "Milano", "Rome": "Roma", "Naples": "Napoli", "Venice": "Venezia", "Florence": "Firenze", "Turin": "Torino",
                  "Genoa": "Genova", "London": "Londra", "Paris": "Parigi", "Munich": "Monaco", "Brussels": "Bruxelles", "Lisbon": "Lisbona",
                  "Athens": "Atene", "Vienna": "Vienna", "Geneva": "Ginevra", "Cologne": "Colonia", "Moscow": "Mosca", "Warsaw": "Varsavia",
                  "Prague": "Praga", "Copenhagen": "Copenaghen", "Seville": "Siviglia", "Dusseldorf": "Düsseldorf", "Bergamo": "Bergamo"]
        var n = nome.replacingOccurrences(of: " International Airport", with: "").replacingOccurrences(of: " Airport", with: "")
            .replacingOccurrences(of: " Airfield", with: "")
        for (en, itn) in it { n = n.replacingOccurrences(of: en, with: itn) }
        let c = it[citta] ?? citta
        if !c.isEmpty && !n.localizedCaseInsensitiveContains(c) { n = "\(c) \(n)" }
        return n.isEmpty ? c : n
    }

    /// Il nome del modello dal codice ICAO (i più comuni nei cieli italiani); se non lo conosce, il codice.
    static func modello(_ t: String) -> String {
        let m = ["A318": "AIRBUS A318", "A319": "AIRBUS A319", "A320": "AIRBUS A320", "A321": "AIRBUS A321", "A19N": "AIRBUS A319neo",
                 "A20N": "AIRBUS A320neo", "A21N": "AIRBUS A321neo", "A332": "AIRBUS A330-200", "A333": "AIRBUS A330-300",
                 "A339": "AIRBUS A330-900neo", "A359": "AIRBUS A350-900", "A35K": "AIRBUS A350-1000", "A388": "AIRBUS A380",
                 "BCS1": "AIRBUS A220-100", "BCS3": "AIRBUS A220-300", "B737": "BOEING 737-700", "B738": "BOEING 737-800",
                 "B739": "BOEING 737-900", "B37M": "BOEING 737 MAX 7", "B38M": "BOEING 737 MAX 8", "B39M": "BOEING 737 MAX 9",
                 "B752": "BOEING 757-200", "B763": "BOEING 767-300", "B772": "BOEING 777-200", "B77W": "BOEING 777-300ER",
                 "B77L": "BOEING 777-200LR", "B788": "BOEING 787-8", "B789": "BOEING 787-9", "B78X": "BOEING 787-10", "B744": "BOEING 747-400",
                 "B748": "BOEING 747-8", "E170": "EMBRAER 170", "E175": "EMBRAER 175", "E190": "EMBRAER 190", "E195": "EMBRAER 195",
                 "E290": "EMBRAER E190-E2", "E295": "EMBRAER E195-E2", "CRJ9": "BOMBARDIER CRJ900", "CRJX": "BOMBARDIER CRJ1000",
                 "AT72": "ATR 72", "AT75": "ATR 72-500", "AT76": "ATR 72-600", "DH8D": "DASH 8-400", "C56X": "CESSNA CITATION XLS",
                 "C68A": "CESSNA CITATION LATITUDE", "GLF6": "GULFSTREAM G650", "PC12": "PILATUS PC-12", "C172": "CESSNA 172"]
        return m[t] ?? (t.isEmpty ? "AEREO" : t)
    }

    /// Il modello da dire: «Airbus A320neo», «Boeing 737-800» (la marca con la maiuscola, il resto com'è).
    static func nome(_ t: String) -> String {
        let m = modello(t)
        guard let primo = m.split(separator: " ").first else { return m }
        let marca = primo.prefix(1) + primo.dropFirst().lowercased()
        let resto = m.split(separator: " ").dropFirst().joined(separator: " ")
        return resto.isEmpty ? String(marca) : "\(marca) \(resto)"
    }

    /// I grandi (due corridoi) sono un po' più lunghi nell'ologramma, come l'aereo lontano del mockup (1,12).
    static func lunghezza(_ t: String) -> Double {
        ["A332", "A333", "A339", "A359", "A35K", "A388", "B763", "B772", "B77W", "B77L", "B788", "B789", "B78X", "B744", "B748"].contains(t) ? 1.12 : 1
    }

    private static func num(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }
}

// MARK: - Il cielo: dove guarda il telefono, gli aerei intorno, quello agganciato

@MainActor
final class CieloOcchi: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Fase: Equatable { case spento, cerca, agganciato }
    @Published private(set) var fase: Fase = .spento
    @Published private(set) var aerei: [AereoInCielo] = []
    @Published private(set) var scelto: String?
    @Published private(set) var rotte: [String: RottaVolo] = [:]
    /// Il foglio con i dati del volo (come il CERCA del mockup), con la domanda detta.
    @Published var foglio: String?
    @Published private(set) var bussolaGradi: Double = 0
    @Published private(set) var alzoGradi: Double = 0

    private let movimento = CMMotionManager()
    private let posizione = CLLocationManager()
    private var lat: Double?, lon: Double?, quotaLei: Double = 120
    /// La matrice dell'assetto (riga per riga) e se va letta così (riferimento → telefono) o trasposta: si decide dalla gravità.
    private var m: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    private var diretta = true
    private var giro: Task<Void, Never>?
    private var generazione = 0

    override init() {
        super.init()
        posizione.delegate = self
        posizione.desiredAccuracy = kCLLocationAccuracyBest
    }

    var acceso: Bool { fase != .spento }
    var agganciato: AereoInCielo? { aerei.first { $0.id == scelto } }
    var rottaScelta: RottaVolo? { scelto.flatMap { rotte[$0] } }

    // MARK: Sensori

    private func accendiSensori() {
        if posizione.authorizationStatus == .notDetermined { posizione.requestWhenInUseAuthorization() }
        posizione.startUpdatingLocation()
        guard movimento.isDeviceMotionAvailable, !movimento.isDeviceMotionActive else { return }
        movimento.deviceMotionUpdateInterval = 1.0 / 30
        let quadro: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)
            ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        movimento.startDeviceMotionUpdates(using: quadro, to: .main) { [weak self] d, _ in
            guard let d else { return }
            MainActor.assumeIsolated { self?.assetto(d) }
        }
    }

    private func spegniSensori() {
        movimento.stopDeviceMotionUpdates()
        posizione.stopUpdatingLocation()
    }

    private func assetto(_ d: CMDeviceMotion) {
        let r = d.attitude.rotationMatrix
        m = [r.m11, r.m12, r.m13, r.m21, r.m22, r.m23, r.m31, r.m32, r.m33]
        // la gravità nel telefono è il «giù» del riferimento portato nel telefono: dice in che verso si legge la matrice
        let g = d.gravity
        let diretto = -(r.m13 * g.x + r.m23 * g.y + r.m33 * g.z), trasposto = -(r.m31 * g.x + r.m32 * g.y + r.m33 * g.z)
        diretta = diretto >= trasposto
        // dove guarda la fotocamera dietro (il -z del telefono) nel riferimento: X nord, Y ovest, Z su
        let v = nelRiferimento(0, 0, -1)
        let az = atan2(-v.1, v.0) * 180 / .pi
        bussolaGradi = (az + 360).truncatingRemainder(dividingBy: 360)
        alzoGradi = asin(max(-1, min(1, v.2))) * 180 / .pi
    }

    /// Un vettore del telefono portato nel riferimento (nord, ovest, su).
    private func nelRiferimento(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        diretta ? (m[0] * x + m[3] * y + m[6] * z, m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z)
                : (m[0] * x + m[1] * y + m[2] * z, m[3] * x + m[4] * y + m[5] * z, m[6] * x + m[7] * y + m[8] * z)
    }

    /// Un vettore del riferimento portato nel telefono.
    private func nelTelefono(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        diretta ? (m[0] * x + m[1] * y + m[2] * z, m[3] * x + m[4] * y + m[5] * z, m[6] * x + m[7] * y + m[8] * z)
                : (m[0] * x + m[3] * y + m[6] * z, m[1] * x + m[4] * y + m[7] * z, m[2] * x + m[5] * y + m[8] * z)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let a = l.coordinate.latitude, b = l.coordinate.longitude, q = l.verticalAccuracy >= 0 ? l.altitude : 120
        Task { @MainActor in self.lat = a; self.lon = b; self.quotaLei = q }
    }

    // MARK: Dove sta un aereo

    /// Distanza (km), rilevamento e alzo da dove si trova il signore, adesso.
    func dove(_ a: AereoInCielo, adesso: Date = Date()) -> (km: Double, rilevamento: Double, alzo: Double)? {
        guard let lat, let lon else { return nil }
        let p = a.posizione(adesso)
        let metri = Rotta.metri(lat: lat, lon: lon, versoLat: p.lat, versoLon: p.lon)
        let ril = Rotta.rilevamento(lat: lat, lon: lon, versoLat: p.lat, versoLon: p.lon)
        // l'alzo con la curvatura della Terra (sui 50 km conta: ~200 m)
        let h = p.quota - quotaLei - metri * metri / (2 * 6_371_000)
        return (metri / 1000, ril, atan2(h, max(metri, 1)) * 180 / .pi)
    }

    /// Il punto sullo schermo (in punti) dove si vede l'aereo, con il campo visivo verticale `campo` (gradi). Nil se è dietro.
    func punto(_ a: AereoInCielo, schermo s: CGSize, campo: Double, adesso: Date = Date()) -> CGPoint? {
        guard let d = dove(a, adesso: adesso), s.height > 0 else { return nil }
        let az = d.rilevamento * .pi / 180, el = d.alzo * .pi / 180
        let t = nelTelefono(cos(el) * cos(az), -cos(el) * sin(az), sin(el))
        let profondo = -t.2
        guard profondo > 0.05 else { return nil }
        // anteprima a riempimento: in verticale il lato lungo del sensore è l'altezza dello schermo
        let f = Double(s.height) / 2 / tan(campo / 2 * .pi / 180)
        return CGPoint(x: Double(s.width) / 2 + f * t.0 / profondo, y: Double(s.height) / 2 - f * t.1 / profondo)
    }

    // MARK: Accendere, agganciare, spegnere

    /// Cerca in cielo (il radar, 1,8 s) e aggancia l'aereo più vicino al centro dell'inquadratura. Falso se non ce ne sono.
    func accendi(schermo: CGSize, campo: Double) async -> Bool {
        generazione += 1
        let mio = generazione
        foglio = nil
        scelto = nil
        fase = .cerca
        accendiSensori()
        // la posizione arriva in un attimo (se non c'è ancora); intanto il radar gira
        let inizio = Date()
        while lat == nil, Date().timeIntervalSince(inizio) < 4 { try? await Task.sleep(for: .milliseconds(150)) }
        guard mio == generazione else { return false }
        if lat != nil { await aggiorna() }
        let resta = 1.8 - Date().timeIntervalSince(inizio)
        if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
        guard mio == generazione else { return false }
        guard let primo = migliore(schermo: schermo, campo: campo) else {
            fase = .spento
            spegniSensori()
            return false
        }
        scelto = primo.id
        fase = .agganciato
        avviaGiro()
        await caricaRotta(primo)
        return mio == generazione
    }

    func spegni() {
        generazione += 1
        giro?.cancel()
        giro = nil
        fase = .spento
        scelto = nil
        foglio = nil
        spegniSensori()
    }

    /// «Aggancia l'altro aereo»: il prossimo, dal più vicino al centro.
    func altro(schermo: CGSize, campo: Double) async -> Bool {
        let ordinati = ordine(schermo: schermo, campo: campo)
        guard ordinati.count > 1 else { return false }
        let k = (ordinati.firstIndex { $0.id == scelto } ?? -1) + 1
        let nuovo = ordinati[k % ordinati.count]
        scelto = nuovo.id
        await caricaRotta(nuovo)
        return true
    }

    /// Prima quelli dentro l'inquadratura (dal centro verso fuori), poi gli altri dal più vicino.
    private func ordine(schermo: CGSize, campo: Double) -> [AereoInCielo] {
        let c = CGPoint(x: schermo.width / 2, y: schermo.height / 2)
        func peso(_ a: AereoInCielo) -> Double {
            if let p = punto(a, schermo: schermo, campo: campo), p.x >= 0, p.x <= schermo.width, p.y >= 0, p.y <= schermo.height {
                return Double(hypot(p.x - c.x, p.y - c.y))
            }
            return 100_000 + (dove(a)?.km ?? 999) * 10
        }
        return aerei.sorted { peso($0) < peso($1) }
    }

    private func migliore(schermo: CGSize, campo: Double) -> AereoInCielo? { ordine(schermo: schermo, campo: campo).first }

    /// Ogni 5 secondi le posizioni nuove (tra un giro e l'altro si portano avanti da sole).
    private func avviaGiro() {
        giro?.cancel()
        giro = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, self.fase == .agganciato else { return }
                await self.aggiorna()
            }
        }
    }

    private func aggiorna() async {
        guard let lat, let lon, let nuovi = await DatiAerei.intorno(lat: lat, lon: lon) else { return }
        // l'agganciato resta agganciato anche se per un giro non arriva (al massimo 30 s di buco)
        if let s = scelto, !nuovi.contains(where: { $0.id == s }), let vecchio = aerei.first(where: { $0.id == s }),
           Date().timeIntervalSince(vecchio.quando) < 30 {
            aerei = nuovi + [vecchio]
        } else {
            aerei = nuovi
        }
    }

    private func caricaRotta(_ a: AereoInCielo) async {
        guard rotte[a.id] == nil, let r = await DatiAerei.rotta(a.nominativo) else { return }
        rotte[a.id] = r
    }

    // MARK: Le parole (come il mockup, con i dati veri)

    func righe() -> [(chiave: String, testo: String)] {
        let b = String(format: "BUSSOLA %.0f° · ALZO %.0f°", bussolaGradi, alzoGradi)
        if fase == .cerca { return [("a", "AEREI · CERCO IN CIELO…"), ("b", b)] }
        guard let a = agganciato else { return [("b", b)] }
        let n = aerei.count
        return [("a", "\(n) \(n == 1 ? "AEREO" : "AEREI") · \(a.tipo.isEmpty ? "AEREO" : a.tipo) AGGANCIATO"), ("b", b)]
    }

    static func km(_ k: Double) -> String {
        k < 10 ? String(format: "%.1f km", k).replacingOccurrences(of: ".", with: ",") : "\(Int(k.rounded())) km"
    }

    static func metri(_ m: Double) -> String {
        let n = Int((m / 50).rounded() * 50)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        return "\(f.string(from: NSNumber(value: n)) ?? "\(n)") m"
    }

    func dati() -> (tipo: String, sigla: String, quota: String, distanza: String, velocita: String)? {
        guard let a = agganciato else { return nil }
        let r = rottaScelta
        let sigla = [r?.compagnia.uppercased() ?? "", r?.volo ?? a.nominativo].filter { !$0.isEmpty }.joined(separator: " · ")
        return (DatiAerei.modello(a.tipo), sigla.isEmpty ? a.matricola : sigla, Self.metri(a.posizione(Date()).quota),
                dove(a).map { Self.km($0.km) } ?? "—", "\(Int(a.velocita.rounded())) km/h")
    }

    private var sale: Bool? {
        guard let a = agganciato else { return nil }
        if a.variometro > 300 { return true }
        if a.variometro < -300 { return false }
        return nil
    }

    /// «Un Airbus A320neo di ITA Airways, Sir: viene da Roma Fiumicino e sta scendendo verso Linate. È a 3.350 metri, a circa 7 km da lei.»
    func testo() -> String {
        guard let a = agganciato else { return "Non vedo aerei in cielo qui intorno, Sir." }
        let chi = DatiAerei.nome(a.tipo)
        let q = Self.metri(a.posizione(Date()).quota).replacingOccurrences(of: " m", with: " metri")
        let lontano = dove(a).map { "a circa \(Self.km($0.km)) da lei" } ?? ""
        guard let r = rottaScelta else {
            return "Un \(chi), Sir: la rotta non la trovo. È a \(q)\(lontano.isEmpty ? "" : ", \(lontano)")."
        }
        let moto: String
        switch sale {
        case true?: moto = "sta salendo e va a \(r.a)"
        case false?: moto = "sta scendendo verso \(r.a)"
        case nil: moto = "va a \(r.a)"
        }
        return "Un \(chi) di \(r.compagnia), Sir: viene da \(r.da) e \(moto). È a \(q)\(lontano.isEmpty ? "" : ", \(lontano)")."
    }

    /// La frase breve detta a voce: «Un Airbus di ITA, Sir: da Fiumicino, scende su Linate.»
    func breve() -> String {
        guard let a = agganciato else { return "Non vedo aerei in cielo qui intorno, Sir." }
        let marca = DatiAerei.nome(a.tipo).split(separator: " ").first.map(String.init) ?? "Aereo"
        guard let r = rottaScelta else { return "Un \(marca), Sir: la rotta di questo volo non la trovo." }
        let comp = r.compagnia.split(separator: " ").first.map(String.init) ?? r.compagnia
        let verbo = sale == false ? "scende su" : "va a"
        return "Un \(marca) di \(comp), Sir: da \(r.da), \(verbo) \(r.a)."
    }

    /// Le domande sull'aereo agganciato.
    func risposta(_ p: String) -> String {
        guard let a = agganciato else { return "Non vedo aerei in cielo qui intorno, Sir." }
        let r = rottaScelta
        switch p {
        case "AEREO_DA":
            return r.map { "Viene da \($0.da), Sir." } ?? "Da dove viene non lo trovo, Sir."
        case "AEREO_DOVE":
            guard let r else { return "Dove va non lo trovo, Sir." }
            if let la = r.aLat, let lo = r.aLon, a.velocita > 100 {
                let p0 = a.posizione(Date())
                let km = Rotta.metri(lat: p0.lat, lon: p0.lon, versoLat: la, versoLon: lo) / 1000
                let min = Int((km / a.velocita * 60).rounded())
                return "Va a \(r.a), Sir: \(sale == false ? "atterra" : "arriva") fra circa \(max(min, 1)) minuti, dalla sua velocità."
            }
            return "Va a \(r.a), Sir."
        case "AEREO_QUOTA":
            let q = Self.metri(a.posizione(Date()).quota).replacingOccurrences(of: " m", with: " metri")
            let moto = sale == true ? " e sta salendo" : sale == false ? " e sta scendendo" : ""
            return "È a \(q)\(moto), Sir: \(Int(a.velocita.rounded())) chilometri all'ora."
        case "AEREO_COMP":
            guard let r, !r.compagnia.isEmpty else { return "La compagnia non la trovo, Sir: il nominativo è \(a.nominativo)." }
            return "È un volo \(r.compagnia), Sir: il \(r.volo)."
        default:
            return breve()
        }
    }
}

// MARK: - Quello che si vede sopra la fotocamera: il radar, i mirini sugli aerei, il filo, la scheda con l'ologramma

struct VistaCieloOcchi: View {
    @ObservedObject var cielo: CieloOcchi
    /// Il campo visivo verticale di adesso (con lo zoom).
    let campo: () -> Double
    let apriFoglio: () -> Void
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: Occhi dietro (MARK XI): il disegno si ferma

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation(paused: !cielo.acceso || dietro)) { tl in
                let adesso = tl.date
                let c = campo()
                ZStack(alignment: .topLeading) {
                    if cielo.fase == .cerca { RadarOcchi().position(x: g.size.width / 2, y: g.size.height * 0.42) }
                    if cielo.fase == .agganciato {
                        ForEach(cielo.aerei) { a in
                            if let p = cielo.punto(a, schermo: g.size, campo: c, adesso: adesso) {
                                let agg = a.id == cielo.scelto
                                let km = cielo.dove(a, adesso: adesso)?.km ?? 50
                                let w = CGFloat(min(108, max(46, 108 * 9 / max(km, 1))))
                                MirinoAereo(agganciato: agg, etichetta: "\(a.tipo.isEmpty ? "AEREO" : a.tipo) · \(CieloOcchi.km(km).uppercased())",
                                            larghezza: w, t: adesso.timeIntervalSinceReferenceDate)
                                    .position(p)
                            }
                        }
                        if let a = cielo.agganciato, let p = cielo.punto(a, schermo: g.size, campo: c, adesso: adesso) {
                            FiloAereo(da: p, a: CGPoint(x: 16 + 150, y: 150 + 93))
                        }
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .allowsHitTesting(false)
            if cielo.fase == .agganciato {
                SchedaAereo(cielo: cielo, apri: apriFoglio)
                    .frame(width: 150, height: 186)
                    .offset(x: 16, y: 150)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.35), value: cielo.fase)
    }
}

/// Il radar della ricerca: un cerchio con la scia che gira e la N in cima.
private struct RadarOcchi: View {
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: dietro (MARK XI) si ferma
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: dietro)) { tl in
            let a = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360
            ZStack {
                Circle().fill(AngularGradient(colors: [Color.ciano.opacity(0.45), Color.ciano.opacity(0), Color.ciano.opacity(0)],
                                              center: .center, startAngle: .degrees(0), endAngle: .degrees(360)))
                    .rotationEffect(.degrees(a - 90))
                Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1)
                Text("N").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.ciano).offset(y: -109)
            }
            .frame(width: 200, height: 200)
        }
        .transition(.opacity)
    }
}

/// Il mirino ad angoli e la sagoma laser sull'aereo agganciato; sugli altri il nome piccolo con la distanza.
private struct MirinoAereo: View {
    let agganciato: Bool
    let etichetta: String
    let larghezza: CGFloat
    let t: Double

    var body: some View {
        let k = larghezza / 108, h = 64 * k
        ZStack(alignment: .topLeading) {
            if agganciato {
                AngoliMira().stroke(Color.ciano, lineWidth: 2).shadow(color: Color.ciano, radius: 4)
                SagomaAereo().fill(Color.ciano.opacity(0.18))
                    .frame(width: 84 * k, height: 40 * k).offset(x: 12 * k, y: 12 * k)
                SagomaAereo().stroke(Color.ciano, style: StrokeStyle(lineWidth: 1.2, dash: [6, 4], dashPhase: CGFloat(-(t.truncatingRemainder(dividingBy: 1.2)) / 1.2 * 40)))
                    .frame(width: 84 * k, height: 40 * k).offset(x: 12 * k, y: 12 * k)
                    .shadow(color: Color.ciano, radius: 3)
            } else {
                Text(etichetta).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.7))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.ciano).frame(width: 2) }
                    .fixedSize()
                    .offset(x: larghezza / 2 + 6, y: h / 2 - 9)
            }
        }
        .frame(width: larghezza, height: h, alignment: .topLeading)
    }
}

/// Gli angoli del mirino (viewBox 108×64 del mockup).
private struct AngoliMira: Shape {
    func path(in r: CGRect) -> Path {
        let l = min(14, r.width * 0.13)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
        p.move(to: CGPoint(x: r.width - l, y: 0)); p.addLine(to: CGPoint(x: r.width, y: 0)); p.addLine(to: CGPoint(x: r.width, y: l))
        p.move(to: CGPoint(x: r.width, y: r.height - l)); p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: r.width - l, y: r.height))
        p.move(to: CGPoint(x: l, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height - l))
        return p
    }
}

/// La sagoma dell'aereo di linea del mockup (viewBox 84×40): fusoliera, ali a freccia, coda, i due motori.
struct SagomaAereo: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 84, sy = r.height / 40
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var p = Path()
        p.move(to: q(2, 20))
        p.addCurve(to: q(8, 17.4), control1: q(2, 18.3), control2: q(4, 17.5))
        p.addLine(to: q(33, 17.4)); p.addLine(to: q(47, 2)); p.addLine(to: q(52.5, 2)); p.addLine(to: q(46, 17.4))
        p.addLine(to: q(70, 17.4)); p.addLine(to: q(76.5, 10)); p.addLine(to: q(80, 10)); p.addLine(to: q(77.5, 17.6))
        p.addLine(to: q(82, 18.7)); p.addLine(to: q(82, 21.3)); p.addLine(to: q(77.5, 22.4)); p.addLine(to: q(80, 30))
        p.addLine(to: q(76.5, 30)); p.addLine(to: q(70, 22.6)); p.addLine(to: q(46, 22.6)); p.addLine(to: q(52.5, 38))
        p.addLine(to: q(47, 38)); p.addLine(to: q(33, 22.6)); p.addLine(to: q(8, 22.6))
        p.addCurve(to: q(2, 20), control1: q(4, 22.5), control2: q(2, 21.7))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: r.minX + 38 * sx, y: r.minY + 8.1 * sy, width: 6.4 * sx, height: 3 * sy))
        p.addEllipse(in: CGRect(x: r.minX + 38 * sx, y: r.minY + 28.9 * sy, width: 6.4 * sx, height: 3 * sy))
        return p
    }
}

/// Il filo dalla scheda all'aereo agganciato, con il punto sull'aereo.
private struct FiloAereo: View {
    let da: CGPoint
    let a: CGPoint
    var body: some View {
        ZStack {
            Path { p in p.move(to: da); p.addLine(to: a) }.stroke(Color.ciano, lineWidth: 1.2)
            Circle().fill(Color.ciano).frame(width: 6, height: 6).position(da)
        }
    }
}

/// La scheda a sinistra: l'ologramma 3D che gira (con la riga di scansione) e i dati.
private struct SchedaAereo: View {
    @ObservedObject var cielo: CieloOcchi
    let apri: () -> Void
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: dietro (MARK XI) la riga di scansione si ferma

    var body: some View {
        Button { Suoni.tocco(); apri() } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .top) {
                    RadialGradient(colors: [Color.ciano.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.7), startRadius: 0, endRadius: 70)
                    AereoOlografico(lunghezza: DatiAerei.lunghezza(cielo.agganciato?.tipo ?? ""))
                    TimelineView(.animation(minimumInterval: nil, paused: dietro)) { tl in
                        let k = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                        Rectangle().fill(Color.ciano.opacity(0.35)).frame(height: 1).shadow(color: Color.ciano, radius: 3)
                            .padding(.horizontal, 10).offset(y: 6 + 80 * k)
                    }
                }
                .frame(height: 92)
                .padding(.horizontal, 4)
                if let d = cielo.dati() {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.tipo).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(d.sigla).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color.ciano)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        riga("QUOTA", d.quota)
                        riga("DISTANZA", d.distanza)
                        riga("VELOCITÀ", d.velocita)
                    }
                    .padding(.leading, 12).padding(.trailing, 10)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 150, height: 186, alignment: .topLeading)
            .background(Color(red: 3 / 255, green: 9 / 255, blue: 11 / 255).opacity(0.8))
            .overlay(alignment: .leading) { Rectangle().fill(Color.ciano).frame(width: 2.5).padding(.vertical, 8) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(0.75), lineWidth: 1.2))
        }
        .buttonStyle(StileStark())
        .accessibilityLabel("Apri i dati del volo")
    }

    private func riga(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color(red: 200 / 255, green: 240 / 255, blue: 250 / 255).opacity(0.65))
            Spacer()
            Text(v).foregroundStyle(.white)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
    }
}

/// Il foglio con i dati del volo (come il CERCA degli Occhi): «VOLO · FR 3TZ», la domanda, il testo e i quattro dati.
struct FoglioVoloOcchi: View {
    @ObservedObject var cielo: CieloOcchi
    let chiesto: String
    let chiudi: () -> Void

    var body: some View {
        let r = cielo.rottaScelta, a = cielo.agganciato
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VOLO · \(r?.volo ?? a?.nominativo ?? "—")").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color.ciano)
                    Text("«\(chiesto)»").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.tenue)
                }
                Spacer()
                Button { Suoni.tocco(); chiudi() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ciano)
                        .frame(width: 36, height: 36).overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                }
                .accessibilityLabel("Chiudi")
            }
            Text(cielo.testo()).font(.system(size: 14)).lineSpacing(3).foregroundStyle(.white).padding(.top, 12).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 8) {
                if let r { voce(r.compagnia.isEmpty ? "—" : r.compagnia, "COMPAGNIA") }
                if let r { voce("\(r.da) → \(r.a)", "ROTTA · \(r.daSigla) → \(r.aSigla)") }
                if let a, let d = cielo.dati() {
                    let moto = a.variometro > 300 ? "sale" : a.variometro < -300 ? "scende" : "in quota"
                    voce("\(d.quota) · \(moto) · \(d.velocita)", "QUOTA E VELOCITÀ")
                    voce("\(DatiAerei.nome(a.tipo))\(a.matricola.isEmpty ? "" : " · \(a.matricola)")", "AEREO")
                }
            }
            Text("DATI DAL VIVO · ADSB.LOL E ADSBDB").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundStyle(Color.tenue).padding(.top, 10)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color(red: 3 / 255, green: 9 / 255, blue: 11 / 255).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.ciano.opacity(0.45), lineWidth: 1))
        .shadow(color: Color.ciano.opacity(0.2), radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dati del volo")
    }

    private func voce(_ b: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(b).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Text(s).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Color.ciano)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color.ciano.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(Color.ciano).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - L'ologramma 3D dell'aereo: lo stesso codice three.js del mockup, in una pagina trasparente (come LiDAR e Studio)

struct AereoOlografico: UIViewRepresentable {
    let lunghezza: Double

    func makeCoordinator() -> RegiaAereo3D { RegiaAereo3D() }

    func makeUIView(context: Context) -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.setURLSchemeHandler(context.coordinator, forURLScheme: RegiaAereo3D.schema)
        conf.websiteDataStore = .nonPersistent()
        let w = WKWebView(frame: .zero, configuration: conf)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.scrollView.isScrollEnabled = false
        w.isUserInteractionEnabled = false
        context.coordinator.lunghezza = lunghezza
        if let u = URL(string: "\(RegiaAereo3D.schema)://app/aereo.html") { w.load(URLRequest(url: u)) }
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        guard context.coordinator.lunghezza != lunghezza else { return }
        context.coordinator.lunghezza = lunghezza
        w.evaluateJavaScript("window.modello && window.modello(\(lunghezza))", completionHandler: nil)
    }
}

final class RegiaAereo3D: NSObject, WKURLSchemeHandler {
    static let schema = "jarvisaereo"
    var lunghezza: Double = 1

    func webView(_ webView: WKWebView, start t: any WKURLSchemeTask) {
        guard let url = t.request.url else { return }
        let nome = url.lastPathComponent
        let dati: Data?, mime: String
        if nome == "three.module.min.js" {
            let f = Bundle.main.url(forResource: "three.module.min", withExtension: "js")
                ?? Bundle.main.url(forResource: "three.module.min", withExtension: "js", subdirectory: "Studio3D")
            dati = f.flatMap { try? Data(contentsOf: $0) }
            mime = "text/javascript"
        } else {
            dati = Data(Self.pagina(lunghezza).utf8)
            mime = "text/html"
        }
        guard let dati else { t.didFailWithError(URLError(.fileDoesNotExist)); return }
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "\(mime); charset=utf-8", "Content-Length": "\(dati.count)"])
            ?? URLResponse(url: url, mimeType: mime, expectedContentLength: dati.count, textEncodingName: "utf-8")
        t.didReceive(r); t.didReceive(dati); t.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    /// `aereoOlografico` del mockup (build 32), identico: fusoliera tornita, ali a freccia, motori, coda, a reticolo luminoso che gira.
    static func pagina(_ lung0: Double) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:transparent;overflow:hidden}canvas{display:block;width:100%!important;height:100%!important}</style></head>
        <body><script type="module">
        import * as T from './three.module.min.js';
        let lung = \(lung0);
        const box = document.body, w = innerWidth || 142, h = innerHeight || 92;
        const ren = new T.WebGLRenderer({ antialias: true, alpha: true }); ren.setPixelRatio(Math.min(devicePixelRatio || 1, 2)); ren.setSize(w, h, false); box.appendChild(ren.domElement);
        const scena = new T.Scene(), cam = new T.PerspectiveCamera(30, w / h, 1, 500); cam.position.set(0, 26, 78); cam.lookAt(0, -1, 0);
        const add = T.AdditiveBlending, facce = new T.MeshBasicMaterial({ color: 0x4fe3ff, transparent: true, opacity: .13, depthWrite: false, side: T.DoubleSide, blending: add });
        const linee = new T.LineBasicMaterial({ color: 0xaaf4ff, transparent: true, opacity: .9, blending: add });
        const aereo = new T.Group(); scena.add(aereo);
        const pezzo = (g) => { aereo.add(new T.Mesh(g, facce)); aereo.add(new T.LineSegments(new T.EdgesGeometry(g, 18), linee)); };
        const ala = (pts, spess) => { const sh = new T.Shape(); pts.forEach(([u, v], i) => (i ? sh.lineTo(u, v) : sh.moveTo(u, v))); return new T.ExtrudeGeometry(sh, { depth: spess, bevelEnabled: false }); };
        function costruisci() {
          aereo.clear();
          const L = 38 * lung, mezzo = L / 2;
          const prof = [[0, -mezzo], [1.1, -mezzo + 1], [1.8, -mezzo + 3], [2, -mezzo + 6], [2, mezzo - 9], [1.6, mezzo - 4], [.9, mezzo - 1], [.3, mezzo]].map(([r, y]) => new T.Vector2(r, y));
          const fus = new T.LatheGeometry(prof, 14); fus.rotateZ(-Math.PI / 2); pezzo(fus);
          [1, -1].forEach((k) => {
            const g = ala([[0, 0], [9.5, 16.5], [11.6, 16.5], [7.2, 0]], .45); g.rotateX(Math.PI / 2); if (k < 0) g.scale(1, 1, -1); g.translate(-4 * lung, -1, 0); pezzo(g);
            const gc = ala([[0, 0], [4, 6.2], [5.6, 6.2], [3.6, 0]], .3); gc.rotateX(Math.PI / 2); if (k < 0) gc.scale(1, 1, -1); gc.translate(mezzo - 6.5, .4, 0); pezzo(gc);
            const mot = new T.CylinderGeometry(1.15, .95, 4.2, 14, 1, true); mot.rotateZ(Math.PI / 2); mot.translate(-3.6 * lung, -2.1, 6.3 * k); pezzo(mot);
          });
          const deriva = ala([[0, 0], [5.2, 7.4], [7.2, 7.4], [6.4, 0]], .3); deriva.translate(mezzo - 8, 1.4, -.15); pezzo(deriva);
        }
        costruisci();
        window.modello = (k) => { lung = k; costruisci(); };
        const t0 = performance.now();
        (function f(ts) { const t = (ts - t0) / 1000; aereo.rotation.set(.18 + Math.sin(t * .7) * .06, t * .55, Math.sin(t * .9) * .08);
          facce.opacity = .1 + .04 * Math.sin(t * 4); ren.render(scena, cam); requestAnimationFrame(f); })(performance.now());
        </script></body></html>
        """
    }
}
#endif
