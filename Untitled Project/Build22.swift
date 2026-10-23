import Foundation
import Combine
import CoreLocation

// Build 22: i pezzi in comune tra iPhone e orologio (questo file è in tutti e due i target).

// MARK: - I toni della voce

/// I toni che il cervello può mettere nel testo per la voce di ElevenLabs («[whispers]», «[sarcastic]», «[serious]»…):
/// servono solo alla voce. A schermo e nella cronologia non compaiono mai (23 ott).
nonisolated enum TagVoce {
    /// Il testo senza i tag tra parentesi quadre e senza lo spazio dopo. Un tag è solo inglese minuscolo («[whispers]»,
    /// «[sarcastic]»: una lettera, poi da 1 a 24 tra lettere minuscole, spazi e trattini) e sta a inizio testo, dopo uno
    /// spazio o dopo un a capo: «array[index]» e «[Nota]» restano come sono.
    /// `inCorso`: la risposta sta ancora arrivando a pezzi; un tag non ancora chiuso in fondo («[whis») non si mostra.
    static func togli(_ testo: String, inCorso: Bool = false) -> String {
        guard testo.contains("[") else { return testo }
        let c = Array(testo)
        var out: [Character] = []
        out.reserveCapacity(c.count)
        var i = 0
        while i < c.count {
            if c[i] == "[", libero(out.last), let fine = chiusura(c, da: i) {
                var j = fine + 1
                let aCapo = out.isEmpty || out.last == "\n"                       // tag da solo in testa a una riga: via anche l'a capo
                while j < c.count, c[j] == " " || c[j] == "\t" || (aCapo && c[j] == "\n") { j += 1 }   // lo spazio dopo il tag
                // dopo il tag c'è punteggiatura o la fine: via anche lo spazio prima («Ciao [laughs].» → «Ciao.»)
                if j >= c.count || c[j] == "\n" || ".,;:!?…)»".contains(c[j]) {
                    while let u = out.last, u == " " || u == "\t" { out.removeLast() }
                }
                i = j
                continue
            }
            out.append(c[i])
            i += 1
        }
        if inCorso, let k = out.lastIndex(of: "["), libero(k > 0 ? out[k - 1] : nil), forseTag(out[(k + 1)...]) {
            out.removeSubrange(k...)
        }
        return String(out)
    }

    /// La posizione della «]» che chiude un tag valido aperto in `i`, altrimenti nil.
    /// «[testo](link)» non è un tag: è un link scritto alla maniera del web e resta com'è.
    private static func chiusura(_ c: [Character], da i: Int) -> Int? {
        var k = i + 1
        while k < c.count, k - i - 1 <= 25, c[k] != "]" { k += 1 }
        guard k < c.count, c[k] == "]", valido(c[(i + 1)..<k]) else { return nil }
        if k + 1 < c.count, c[k + 1] == "(" { return nil }
        return k
    }

    /// Prima della «[» di un tag: l'inizio del testo, uno spazio o un a capo (quello che resta a schermo: dopo un tag tolto
    /// ne può venire subito un altro). Attaccata a una parola («array[index]») non è un tag.
    private static func libero(_ prima: Character?) -> Bool {
        guard let prima else { return true }
        return prima == " " || prima == "\n"
    }

    /// Una lettera inglese minuscola (a…z).
    private static func minuscola(_ c: Character) -> Bool { c.isASCII && c.isLetter && c.isLowercase }

    private static func valido(_ s: ArraySlice<Character>) -> Bool {
        guard s.count >= 2, s.count <= 25, let p = s.first, minuscola(p) else { return false }
        return s.allSatisfy { minuscola($0) || $0 == " " || $0 == "-" }
    }

    /// Un pezzo di tag non ancora chiuso («[», «[whis»): potrebbe diventarlo col prossimo pezzo di testo.
    private static func forseTag(_ s: ArraySlice<Character>) -> Bool {
        guard s.count <= 25 else { return false }
        if let p = s.first, !minuscola(p) { return false }
        return s.allSatisfy { minuscola($0) || $0 == " " || $0 == "-" }
    }
}

// MARK: - I comandi a frase esatta

/// I protocolli alla Stark (Telefono › PROTOCOLLI). Sull'iPhone «Avvia» lancia un Comando rapido per protocollo
/// («JARVIS Party», «JARVIS Notte», «JARVIS Rientro»); poi JARVIS fa le sue parti.
nonisolated enum Protocollo: String, CaseIterable, Identifiable, Hashable, Sendable {
    case party, notte, rientro
    var id: String { rawValue }
    /// Come si legge sulla scheda: PARTY, NOTTE, RIENTRO.
    var titolo: String { rawValue.uppercased() }
    /// Il nome del Comando rapido che il signore crea nell'app Comandi.
    var comandoRapido: String { "JARVIS " + rawValue.capitalized }

    /// Un passo del protocollo: `testo` sull'iPhone, `breve` sul polso; `jarvis`: lo fa JARVIS, non il Comando rapido.
    nonisolated struct Passo: Sendable { let testo: String; let breve: String; let jarvis: Bool }

    var passi: [Passo] {
        switch self {
        case .party:
            return [Passo(testo: "Non disturbare acceso", breve: "Non disturbare", jarvis: false),
                    Passo(testo: "Wi-Fi acceso", breve: "Wi-Fi", jarvis: false),
                    Passo(testo: "Playlist «Serata»", breve: "Playlist", jarvis: false),
                    Passo(testo: "Sveglia alle 11:00", breve: "Sveglia 11:00", jarvis: false)]
        case .notte:
            return [Passo(testo: "Non disturbare acceso", breve: "Non disturbare", jarvis: false),
                    Passo(testo: "Bluetooth spento", breve: "Bluetooth spento", jarvis: false),
                    Passo(testo: "Sveglia alle 9:30", breve: "Sveglia 9:30", jarvis: false),
                    Passo(testo: "Domanda del diario", breve: "Diario", jarvis: true)]
        case .rientro:
            return [Passo(testo: "Wi-Fi acceso", breve: "Wi-Fi", jarvis: false),
                    Passo(testo: "Non disturbare spento", breve: "Non disturbare spento", jarvis: false),
                    Passo(testo: "Messaggi da leggere", breve: "Messaggi", jarvis: true),
                    Passo(testo: "Meteo di domani", breve: "Meteo domani", jarvis: true)]
        }
    }

    /// La frase per il cervello del RIENTRO (messaggi da leggere e meteo di domani), come se la dicesse il signore.
    static let fraseRientro = "Protocollo rientro: dimmi se ci sono messaggi da leggere e che tempo farà domani."
}

/// I comandi a frase esatta (dopo «Jarvis»): riconosciuti sul dispositivo prima di ogni altro comando e prima delle
/// storpiature imparate. Risposta immediata, niente cervello, e non si imparano mai come storpiature.
nonisolated enum ComandoDedicato: Equatable, Sendable {
    case protocollo(Protocollo)   // «protocollo party», «attiva il protocollo notte»: Telefono › PROTOCOLLI, e parte
    case traccia                  // «traccia la macchina»: Ricordi › TRACCIA (la bussola, fotocamera spenta)
    case guida                    // «portami alla macchina»: Ricordi › TRACCIA con la Guida accesa (fotocamera e frecce)
    case radar                    // «radar pioggia»: Meteo › RADAR
    case priorita                 // «rapporto posta»: Email › PRIORITÀ
    case organismo                // «scansione organismo», «stato dell'organismo»: Vitals (sull'orologio l'Organismo)
    case specchio                 // «modalità specchio»: Allenatore
    case squat                    // «contami gli squat»: Allenatore

    static func riconosci(_ frase: String) -> ComandoDedicato? {
        var t = frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        while let p = t.first, ["ehi", "ok", "hey", "jarvis", "giarvis", "jervis"].contains(p) { t.removeFirst() }
        // «protocollo notte», anche con attiva / avvia / esegui / lancia davanti («avvia il protocollo notte»)
        var p = t
        if let v = p.first, ["attiva", "avvia", "esegui", "lancia"].contains(v) {
            p.removeFirst()
            if p.first == "il" { p.removeFirst() }
        }
        if p.count == 2, p[0] == "protocollo" {
            switch p[1] {
            case "party", "parti": return .protocollo(.party)
            case "notte": return .protocollo(.notte)
            case "rientro": return .protocollo(.rientro)
            default: return nil
            }
        }
        switch t.joined(separator: " ") {
        case "traccia la macchina": return .traccia
        case "portami alla macchina": return .guida
        case "radar pioggia": return .radar
        case "rapporto posta": return .priorita
        case "scansione organismo", "stato dell organismo": return .organismo
        case "modalita specchio": return .specchio
        case "contami gli squat", "contami gli squats", "contami gli squad": return .squat
        default: return nil
        }
    }
}

// MARK: - TRACCIA: la strada verso la macchina

nonisolated enum Rotta {
    /// Il rilevamento da un punto all'altro, in gradi dal nord (0…360).
    static func rilevamento(lat: Double, lon: Double, versoLat: Double, versoLon: Double) -> Double {
        let f1 = lat * .pi / 180, f2 = versoLat * .pi / 180, dl = (versoLon - lon) * .pi / 180
        let y = sin(dl) * cos(f2)
        let x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        let g = atan2(y, x) * 180 / .pi
        return (g + 360).truncatingRemainder(dividingBy: 360)
    }

    /// La distanza in metri tra due punti (formula dell'emisenoverso).
    static func metri(lat: Double, lon: Double, versoLat: Double, versoLon: Double) -> Double {
        let r = 6_371_000.0
        let f1 = lat * .pi / 180, f2 = versoLat * .pi / 180
        let df = (versoLat - lat) * .pi / 180, dl = (versoLon - lon) * .pi / 180
        let a = sin(df / 2) * sin(df / 2) + cos(f1) * cos(f2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// Di quanti gradi girarsi per avere la meta davanti: da −180 a 180, positivo = a destra.
    static func relativa(rilevamento: Double, direzione: Double) -> Double {
        var x = (rilevamento - direzione).truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 } else if x < -180 { x += 360 }
        return x
    }

    /// «NE · 32°»: la direzione in cui guarda il dispositivo.
    static func bussola(_ gradi: Double) -> String {
        let punti = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let g = (gradi.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return "\(punti[Int((g + 22.5) / 45) % 8]) · \(Int(g.rounded()) % 360)°"
    }

    /// «180 m», «1,2 km».
    static func distanza(_ m: Double) -> String {
        if m < 1000 { return "\(Int(m.rounded())) m" }
        return (m / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "it_IT"))) + " km"
    }

    /// A piedi, a 80 metri al minuto: «circa 2 minuti».
    static func aPiedi(_ m: Double) -> String {
        let minuti = max(1, Int((m / 80).rounded()))
        if minuti == 1 { return "circa 1 minuto" }
        if minuti < 60 { return "circa \(minuti) minuti" }
        return minuti % 60 == 0 ? "circa \(minuti / 60) h" : "circa \(minuti / 60) h \(minuti % 60) min"
    }
}

/// Posizione e direzione del dispositivo, solo mentre TRACCIA è aperta (iPhone e orologio).
@MainActor
final class Bussola: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var lat: Double?
    @Published private(set) var lon: Double?
    /// Dove guarda il dispositivo, in gradi dal nord (nil: niente bussola, per esempio sul Mac).
    @Published private(set) var direzione: Double?
    private let gestore = CLLocationManager()

    override init() {
        super.init()
        gestore.delegate = self
        gestore.desiredAccuracy = kCLLocationAccuracyBest
        gestore.distanceFilter = 2
        gestore.headingFilter = 2
    }

    func accendi() {
        if gestore.authorizationStatus == .notDetermined { gestore.requestWhenInUseAuthorization() }
        gestore.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { gestore.startUpdatingHeading() }
    }

    func spegni() {
        gestore.stopUpdatingLocation()
        gestore.stopUpdatingHeading()
    }

    /// Il rilevamento verso la meta e la distanza, se la posizione c'è già.
    func verso(lat mLat: Double, lon mLon: Double) -> (rilevamento: Double, metri: Double)? {
        guard let lat, let lon else { return nil }
        return (Rotta.rilevamento(lat: lat, lon: lon, versoLat: mLat, versoLon: mLon), Rotta.metri(lat: lat, lon: lon, versoLat: mLat, versoLon: mLon))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let a = l.coordinate.latitude, b = l.coordinate.longitude
        Task { @MainActor in self.lat = a; self.lon = b }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let g = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.direzione = g }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

// MARK: - RADAR: la pioggia in arrivo (dal cervello, azione «radar»)

nonisolated struct DatiRadar: Equatable, Sendable {
    let piove: Bool
    let iniziaMin: Int
    let mm30: Double
    let smette: String

    /// Dalla risposta del cervello: { piove, inizia_min, mm_30, smette }. nil se non è una risposta del radar.
    init?(_ o: [String: Any]) {
        guard let p = o["piove"] as? Bool else { return nil }
        piove = p
        iniziaMin = (o["inizia_min"] as? NSNumber)?.intValue ?? 0
        mm30 = (o["mm_30"] as? NSNumber)?.doubleValue ?? 0
        smette = (o["smette"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// «fra 15 minuti», «adesso».
    var inizia: String {
        if iniziaMin <= 0 { return "adesso" }
        if iniziaMin == 1 { return "fra 1 minuto" }
        if iniziaMin < 60 { return "fra \(iniziaMin) minuti" }
        return iniziaMin % 60 == 0 ? "fra \(iniziaMin / 60) h" : "fra \(iniziaMin / 60) h \(iniziaMin % 60) min"
    }

    /// «2,4».
    var millimetri: String { mm30.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "it_IT"))) }

    /// L'avviso in testa al pannello RADAR dell'iPhone.
    var avviso: String {
        let quando = iniziaMin <= 0 ? "Signore, piove già dove si trova" : "Signore, pioggia \(inizia) dove si trova"
        return "\(quando): \(millimetri) mm nella prossima mezz'ora. Prenda l'ombrello."
    }

    /// L'avviso sul polso, più corto.
    var avvisoBreve: String {
        iniziaMin <= 0 ? "Signore, piove già dove si trova. Prenda l'ombrello." : "Signore, pioggia \(inizia) dove si trova. Prenda l'ombrello."
    }
}

// MARK: - PRIORITÀ: la posta che conta (dal cervello, azioni «posta_priorita» e «posta_rispondi»)

nonisolated struct MailImportante: Identifiable, Equatable, Sendable {
    let id: String
    let idNumero: Int?          // se il cervello ha mandato l'id come numero, torna come numero
    let mittente: String
    let oggetto: String
    let quando: String
    let riassunto: String
    /// Con `serveRisposta` è la risposta proposta da JARVIS; senza, una nota breve («Nessuna risposta: era lei»).
    let risposta: String?
    let serveRisposta: Bool

    /// Il corpo per il cervello: { "posta_rispondi": { "id": …, "testo": … } }.
    func corpoRisposta(_ testo: String) -> [String: Any] {
        let id: Any = idNumero.map { $0 as Any } ?? self.id
        return ["posta_rispondi": ["id": id, "testo": testo] as [String: Any]]
    }
}

nonisolated struct PostaPriorita: Equatable, Sendable {
    let importanti: [MailImportante]
    let altreConteggio: Int
    let altreNota: String

    /// Dalla risposta del cervello: { importanti: [...], altre: { conteggio, nota } }. nil se non è quella risposta.
    init?(_ o: [String: Any]) {
        guard let lista = o["importanti"] as? [[String: Any]] else { return nil }
        importanti = lista.compactMap { d in
            let numero = d["id"] as? NSNumber
            guard let id = (d["id"] as? String) ?? numero?.stringValue else { return nil }
            let r = (d["risposta"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return MailImportante(id: id, idNumero: d["id"] is String ? nil : numero?.intValue,
                                  mittente: d["mittente"] as? String ?? "", oggetto: d["oggetto"] as? String ?? "",
                                  quando: d["quando"] as? String ?? "", riassunto: d["riassunto"] as? String ?? "",
                                  risposta: (r?.isEmpty ?? true) ? nil : r, serveRisposta: (d["serve_risposta"] as? Bool) ?? false)
        }
        let altre = o["altre"] as? [String: Any] ?? [:]
        altreConteggio = (altre["conteggio"] as? NSNumber)?.intValue ?? 0
        altreNota = (altre["nota"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La risposta proposta senza le virgolette «», per mostrarla e modificarla.
    static func senzaVirgolette(_ t: String) -> String {
        t.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“” \n"))
    }
}
