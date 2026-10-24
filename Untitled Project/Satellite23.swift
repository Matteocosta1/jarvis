import SwiftUI
import CoreLocation

// Build 23: i pezzi di SATELLITE in comune tra iPhone e orologio (questo file è in tutti e due i target).

// MARK: - L'icona

/// L'icona di SATELLITE, come nel mockup: il satellite di sbieco con i due pannelli e la parabola che trasmette
/// (tre onde). Disegnata sulla griglia 24 × 24 del mockup, con le sue stesse misure; si colora con il primo piano.
struct FormaSatellite: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        // il gruppo esterno: translate(-.6 .3) scale(1.05)
        func esterno(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + (x * 1.05 - 0.6) * s, y: oy + (y * 1.05 + 0.3) * s)
        }
        // il gruppo interno: rotate(45 10 14)
        let c = CGFloat(cos(Double.pi / 4)), n = CGFloat(sin(Double.pi / 4))
        func ruotato(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let dx = x - 10, dy = y - 14
            return esterno(10 + dx * c - dy * n, 14 + dx * n + dy * c)
        }
        var p = Path()
        // il corpo: rect 7.8, 11.8, 4.4 × 4.4, angoli 0,9
        let r: CGFloat = 0.9
        let corpo: [(CGFloat, CGFloat)] = [(7.8 + r, 11.8), (12.2 - r, 11.8), (12.2, 11.8 + r), (12.2, 16.2 - r),
                                           (12.2 - r, 16.2), (7.8 + r, 16.2), (7.8, 16.2 - r), (7.8, 11.8 + r)]
        let angoli: [(CGFloat, CGFloat)] = [(12.2, 11.8), (12.2, 16.2), (7.8, 16.2), (7.8, 11.8)]
        p.move(to: ruotato(corpo[0].0, corpo[0].1))
        for k in 0..<4 {
            let a = corpo[k * 2], b = corpo[(k * 2 + 1) % 8], q = angoli[k], d = corpo[(k * 2 + 2) % 8]
            p.addLine(to: ruotato(a.0, a.1))
            p.addLine(to: ruotato(b.0, b.1))
            p.addQuadCurve(to: ruotato(d.0, d.1), control: ruotato(q.0, q.1))
        }
        p.closeSubpath()
        // i due pannelli (5 × 3,2) con la loro riga in mezzo, e i due bracci
        for x0: CGFloat in [1.6, 13.4] {
            p.move(to: ruotato(x0, 12.4)); p.addLine(to: ruotato(x0 + 5, 12.4)); p.addLine(to: ruotato(x0 + 5, 15.6))
            p.addLine(to: ruotato(x0, 15.6)); p.closeSubpath()
            p.move(to: ruotato(x0 + 2.5, 12.4)); p.addLine(to: ruotato(x0 + 2.5, 15.6))
        }
        p.move(to: ruotato(6.6, 14)); p.addLine(to: ruotato(7.8, 14))
        p.move(to: ruotato(12.2, 14)); p.addLine(to: ruotato(13.4, 14))
        // l'antenna e le tre onde (archi del mockup, convertiti punto per punto)
        p.move(to: esterno(12.6, 11.4)); p.addLine(to: esterno(15, 9))
        FormaSatellite.arco(&p, da: (14.2, 6.6), a: (17.4, 9.8), raggio: 3.4, orario: false, punto: esterno)
        FormaSatellite.arco(&p, da: (17, 4.4), a: (19.6, 7.0), raggio: 5.5, orario: true, punto: esterno)
        FormaSatellite.arco(&p, da: (18.3, 1.9), a: (22.1, 5.7), raggio: 8.5, orario: true, punto: esterno)
        return p
    }

    /// Un arco piccolo dell'SVG («a r r 0 0 sweep dx dy») disegnato a segmenti: il centro si ricava dai due estremi
    /// (conversione dei parametri dell'SVG), `orario` è il sweep-flag 1 (sullo schermo, con l'asse y in giù).
    nonisolated private static func arco(_ p: inout Path, da: (CGFloat, CGFloat), a: (CGFloat, CGFloat), raggio r: CGFloat, orario: Bool,
                                         punto: (CGFloat, CGFloat) -> CGPoint) {
        let mx = (da.0 + a.0) / 2, my = (da.1 + a.1) / 2
        let dx = a.0 - da.0, dy = a.1 - da.1
        let corda = sqrt(dx * dx + dy * dy)
        let h = sqrt(max(0, r * r - corda * corda / 4))
        // il centro sta sulla perpendicolare alla corda; per l'arco piccolo: a destra del verso se sweep = 1 (y in giù)
        let ux = -dy / corda, uy = dx / corda
        let segno: CGFloat = orario ? 1 : -1
        let cx = mx + ux * h * segno, cy = my + uy * h * segno
        var t0 = atan2(da.1 - cy, da.0 - cx), t1 = atan2(a.1 - cy, a.0 - cx)
        if orario { while t1 < t0 { t1 += 2 * .pi } } else { while t1 > t0 { t1 -= 2 * .pi } }
        p.move(to: punto(da.0, da.1))
        for k in 1...12 {
            let t = t0 + (t1 - t0) * CGFloat(k) / 12
            p.addLine(to: punto(cx + r * cos(t), cy + r * sin(t)))
        }
    }
}

/// L'icona pronta da mettere al posto di un simbolo: `lato` come la misura dell'SVG nel mockup (18 nella corona,
/// 22 nella testata della scheda, 15 sul polso), il tratto 1,6 della griglia 24.
struct IconaSatellite: View {
    var lato: CGFloat = 18
    var body: some View {
        FormaSatellite()
            .stroke(style: StrokeStyle(lineWidth: 1.6 * lato / 24, lineCap: .round, lineJoin: .round))
            .frame(width: lato, height: lato)
    }
}

// MARK: - Le frasi a voce di SATELLITE (riconosciute in ComandoDedicato, Build22.swift)

/// Cosa fare in SATELLITE, detto a voce: il nome del luogo (o l'indirizzo) è com'è stato detto.
nonisolated enum AzioneSatellite: Hashable, Sendable {
    case guida(String)             // «guidami allo studio»: la GUIDA verso quel luogo
    case naviga(String)            // «mostrami la strada per il locale»: NAVIGA, le tappe con la vista da strada
    case ricognizione(String)      // «ricognizione su Via Savona»: RICOGNIZIONE su quell'indirizzo
    case mostra(String)            // «mostrami lo studio in 3D»: SATELLITE vola su quel luogo

    var nome: String {
        switch self { case .guida(let n), .naviga(let n), .ricognizione(let n), .mostra(let n): return n }
    }
}

// MARK: - I luoghi

/// Un luogo di SATELLITE: i luoghi salvati dal signore (la seconda memoria, gli stessi di Ricordi › TRACCIA) e, se c'è,
/// quello della RICOGNIZIONE. `chiave` tiene insieme le foto del dossier anche se il nome cambia.
nonisolated struct LuogoSat: Identifiable, Hashable, Sendable {
    let chiave: String
    let ricordo: Int?              // l'id nella seconda memoria (nil: la ricognizione, non salvata)
    let tipo: String               // posto, parcheggio, persona (ricognizione: «ricognizione»)
    let nome: String
    let via: String
    let persona: String?
    let lat: Double
    let lon: Double
    let quando: String
    var id: String { chiave }
    var coordinata: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    /// I luoghi dalla risposta del cervello a { ricordi: true }: i «posti» con le coordinate, dal più recente.
    /// Sono luoghi i posti salvati, i vecchi parcheggi (come in TRACCIA) e dove ha incontrato qualcuno (PERSONE).
    static func daRicordi(_ o: [String: Any]) -> [LuogoSat] {
        (o["posti"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = (r["id"] as? NSNumber)?.intValue, let tipo = r["tipo"] as? String, ["posto", "parcheggio", "persona"].contains(tipo),
                  let lat = (r["lat"] as? NSNumber)?.doubleValue, let lon = (r["lon"] as? NSNumber)?.doubleValue else { return nil }
            let testo = (r["testo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let persona = (r["persona"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let via = (r["luogo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // per una persona il nome è chi ha incontrato; per un luogo il suo nome (o la via, se il nome manca)
            let nome = tipo == "persona" ? (persona ?? testo) : (testo.isEmpty ? via : testo)
            guard !nome.isEmpty else { return nil }
            return LuogoSat(chiave: "r\(id)", ricordo: id, tipo: tipo, nome: nome, via: via.isEmpty ? nome : via, persona: persona,
                            lat: lat, lon: lon, quando: r["quando_leggibile"] as? String ?? "")
        }
    }

    /// Il luogo detto a voce («lo studio», «il locale», «Bar Basso»): prima il nome uguale, poi uno che lo contiene
    /// (o contenuto), poi la via. Senza articoli e senza accenti. nil: non è tra i suoi luoghi.
    static func trova(_ detto: String, in luoghi: [LuogoSat]) -> LuogoSat? {
        func pulito(_ s: String) -> String {
            var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
                .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
                .split(separator: " ").map(String.init)
            while let p = t.first, ["il", "lo", "la", "l", "i", "gli", "le", "un", "una", "uno", "mio", "mia"].contains(p), t.count > 1 { t.removeFirst() }
            return t.joined(separator: " ")
        }
        let d = pulito(detto)
        guard !d.isEmpty else { return nil }
        if let l = luoghi.first(where: { pulito($0.nome) == d }) { return l }
        let parole = Set(d.split(separator: " ").map(String.init))
        if let l = luoghi.first(where: { let n = pulito($0.nome); return n.contains(d) || (n.count >= 3 && d.contains(n)) }) { return l }
        if let l = luoghi.first(where: { Set(pulito($0.nome).split(separator: " ").map(String.init)).isSuperset(of: parole) }) { return l }
        return luoghi.first { pulito($0.via) == d || pulito($0.via).contains(d) }
    }
}

// MARK: - La GUIDA in corso, al polso

/// La GUIDA in corso come arriva all'orologio dall'iPhone (WatchConnectivity): la freccia, i metri, la tappa e il luogo.
/// Le svolte come le frecce del mockup: dritto ↑, destra ↱, sinistra ↰, arrivo ⚑.
nonisolated struct GuidaPolsoDati: Equatable, Sendable {
    var nome: String               // «Studio»
    var svolta: String             // la svolta della tappa in corso: dritto, destra, sinistra, arrivo
    var via: String                // «Via Tortona»
    var metri: Double              // metri alla fine della tappa (all'arrivo, se è l'ultima)
    var manca: Double              // metri all'arrivo
    var rilevamento: Double?       // gradi dal nord verso il prossimo punto del percorso (la freccia)
    var arrivato: Bool

    static func freccia(_ svolta: String) -> String {
        switch svolta { case "destra": return "↱"; case "sinistra": return "↰"; case "arrivo": return "⚑"; default: return "↑" }
    }

    var dizionario: [String: Any] {
        var d: [String: Any] = ["nome": nome, "svolta": svolta, "via": via, "metri": metri, "manca": manca, "arrivato": arrivato]
        if let rilevamento { d["rilevamento"] = rilevamento }
        return d
    }

    init(nome: String, svolta: String, via: String, metri: Double, manca: Double, rilevamento: Double?, arrivato: Bool) {
        self.nome = nome; self.svolta = svolta; self.via = via; self.metri = metri; self.manca = manca
        self.rilevamento = rilevamento; self.arrivato = arrivato
    }

    init?(_ d: [String: Any]) {
        guard let nome = d["nome"] as? String else { return nil }
        self.nome = nome
        svolta = d["svolta"] as? String ?? "dritto"
        via = d["via"] as? String ?? ""
        metri = (d["metri"] as? NSNumber)?.doubleValue ?? 0
        manca = (d["manca"] as? NSNumber)?.doubleValue ?? 0
        rilevamento = (d["rilevamento"] as? NSNumber)?.doubleValue
        arrivato = d["arrivato"] as? Bool ?? false
    }
}
