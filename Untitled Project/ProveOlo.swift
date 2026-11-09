import Foundation
import SwiftUI

// MARK: - LE PROVE DEGLI OLOGRAMMI (11.0 (6)) — il motore del mockup v262–v264 (motore.js), riportato uguale
// Il signore (5 nov, 17:01): «riporta esattamente il mockup nell'app per quanto riguarda il design; lascia la possibilità di scelta
// di tutti e 3 gli ologrammi, perché sono tutti belli ed è cool poter scegliere come visualizzarli». Sei sezioni (Diario, Sonno,
// Briefing, Spesa, Serata, Bea), tre prove ciascuna, scelte con le chip sotto l'ologramma; la scelta resta (e il polso la segue).
// Stessa famiglia di Cuore, Meteo e ghiera: luce additiva, proiettore e cono, tacche, numeri scritti nel disegno. Si toccano: il
// dito di lato li gira (con lo slancio), il tocco su un elemento lo sceglie e apre il suo riquadro (staffe, codice, dato).
// Questo file è sia dell'iPhone sia dell'orologio (sul polso: in piccolo, senza scritte, senza dita).

typealias P3 = SIMD3<Double>

/// Le sezioni con le prove: i nomi delle chip, i suggerimenti e la chiave della scelta (la stessa sull'iPhone e sul polso).
nonisolated enum SezioneOlo: String, CaseIterable {
    case diario, sonno, briefing, spesa, serata, bea
    // 9 nov (build 19, il signore: «falli tutti J»): gli ologrammi della tavola, come il mockup
    case cuore, telefono, meteo, edith, posta, messaggi, confidente, interprete, traccia, vitals, github, supabase, archivio, costi

    /// v270: Bea ha una chiave nuova (le prove sono cambiate: VETRO, SCUDO, RITRATTO); la scelta di prima si ritrova (SCUDO resta SCUDO).
    var chiave: String {
        guard self == .bea else { return "oloProva." + rawValue }
        SezioneOlo.passaBea()
        return "oloProva.bea2"
    }

    /// Una volta sola: la prova di Bea scelta prima (PUNTI, LINEE, VETRO, SCUDO) passa alle tre di adesso.
    private static func passaBea() {
        let d = UserDefaults.standard
        guard d.object(forKey: "oloProva.bea2") == nil else { return }
        d.set(d.integer(forKey: "oloProva.bea") == 3 ? 1 : 0, forKey: "oloProva.bea2")
    }

    var nomi: [String] {
        switch self {
        case .diario: return ["ELICA", "RILIEVO", "ORBITA"]
        case .sonno: return ["LETTO", "CICLI", "NOTTI"]                  // v266: LETTO al posto di ONDA
        case .briefing: return ["RADAR", "GLOBO", "PISTA"]
        case .spesa: return ["CASSA", "SCAFFALE", "ANELLO"]
        case .serata: return ["FLUSSO", "TORRI", "REATTORE"]
        case .bea: return ["VETRO", "SCUDO", "RITRATTO"]                 // v270: tolte PUNTI e LINEE, il RITRATTO come l'Armadio
        case .cuore: return ["BATTITO", "PETTO", "ECG"]                    // 9 nov (il signore): tolto ANELLI
        case .telefono: return ["ANTENNA", "STARKPHONE", "SATELLITI"]
        case .meteo: return ["CELLA", "GLOBO", "VENTO"]
        case .edith: return ["OCCHIALI", "DRONI", "SCUDO"]
        case .posta: return ["SMISTA", "FIREWALL", "FASCICOLI"]
        case .messaggi: return ["BOLLE", "RETE", "ORBITE"]
        case .confidente: return ["BILANCIA", "MENTE", "ONDA"]
        case .interprete: return ["PONTE", "GLOBO", "VOCI"]
        case .traccia: return ["SENTIERO", "B.A.R.F.", "MAPPA"]
        case .vitals: return ["SCANSIONE", "ANELLI", "RADAR"]
        case .github: return ["EXPO", "ATOMO", "PULSAR"]
        case .supabase: return ["REATTORE", "RETE", "BATTITO"]
        case .archivio: return ["OFFICINA", "NUVOLA", "SPIRALE"]
        case .costi: return ["PALLADIO", "TORRI", "CLESSIDRA"]
        }
    }

    /// Il suggerimento in basso finché non si tocca (come il mockup).
    var aiuti: [String] {
        switch self {
        case .diario: return ["↔ GIRA · TOCCA UNA SERA", "↔ GIRA · TOCCA UNA VETTA", "↔ GIRA · TOCCA UNA SERA O UN TEMA"]
        case .sonno: return ["↔ GIRA · TOCCA UNA FASE", "↔ GIRA · TOCCA UN CICLO", "↔ GIRA · TOCCA UNA NOTTE"]
        case .briefing: return ["↔ GIRA · TOCCA UN IMPEGNO", "↔ GIRA · TOCCA MILANO O IL SOLE", "↔ AVANTI E INDIETRO NEL TEMPO"]
        case .spesa: return ["TOCCA UNA COSA: PASSA IN CASSA", "↔ GIRA · TOCCA UNA COSA: PRESA", "↔ GIRA · TOCCA UN SETTORE: PRESA"]
        case .serata: return ["TOCCA UNA VOCE", "↔ GIRA · TOCCA UNA TORRE", "↔ GIRA · TOCCA UN SETTORE"]
        case .bea: return ["↔ GIRA · TOCCA UNA DATA", "↔ GIRA · TOCCA IL CUORE", "↔ GIRA · TOCCA LEI O UNA DATA"]
        case .cuore: return ["", "↔ GIRA · TOCCA IL CUORE", "↔ GIRA · TOCCA UN TRATTO"]
        case .telefono: return ["↔ GIRA · TOCCA LA CIMA", "TOCCA UN TASTO SUL VETRO", "↔ GIRA · TOCCA UN CONTATTO"]
        case .meteo: return ["↔ GIRA · TOCCA LA NUVOLA", "↔ GIRA · TOCCA MILANO", "↔ GIRA · TOCCA LA ROSA"]
        case .edith: return ["↔ GIRA · TOCCA UNA LENTE", "↔ GIRA · TOCCA UN DRONE", "↔ GIRA · TOCCA UNO SPICCHIO"]
        case .posta: return ["↔ GIRA · TOCCA UNA MAIL", "↔ GIRA · TOCCA UNA MAIL", "↔ SFOGLIA · TOCCA QUELLO DAVANTI"]
        case .messaggi: return ["↔ GIRA · TOCCA UN MESSAGGIO", "↔ GIRA · TOCCA UNA PERSONA", "↔ GIRA · TOCCA UN MESSAGGIO"]
        case .confidente: return ["↔ GIRA · TOCCA UN PIATTO", "↔ GIRA · TOCCA UNA ZONA", "↔ GIRA · TOCCA UNA RIGA"]
        case .interprete: return ["↔ GIRA · TOCCA UNA FRASE", "↔ GIRA · TOCCA UN PAESE", "TOCCA UNA VOCE"]
        case .traccia: return ["↔ GIRA · TOCCA IL LUOGO", "↔ SCORRI · TOCCA IL RICORDO", "↔ GIRA · TOCCA UN POSTO"]
        case .vitals: return ["↔ GIRA · TOCCA UNA ZONA", "↔ GIRA · TOCCA UN ANELLO", "↔ GIRA · TOCCA UN GIORNO"]
        case .github: return ["↔ GIRA · TOCCA UN PADIGLIONE", "↔ GIRA · TOCCA UN ELETTRONE", "↔ GIRA · TOCCA UN GIORNO"]
        case .supabase: return ["↔ GIRA · TOCCA UNA CAMERA", "↔ GIRA · TOCCA UNA FUNZIONE", "↔ GIRA · TOCCA UN MINUTO"]
        case .archivio: return ["↔ SFOGLIA · TOCCA LA TAVOLA", "↔ GIRA · TOCCA UNA CARTELLA", "↔ GIRA · TOCCA UN FILE"]
        case .costi: return ["↔ GIRA · TOCCA UNA BOBINA", "↔ GIRA · TOCCA UNA TORRE", "↔ GIRA · TOCCA LA CLESSIDRA"]
        }
    }

    /// La prova scelta (da 0).
    var scelta: Int { min(nomi.count - 1, max(0, UserDefaults.standard.integer(forKey: chiave))) }

    /// Tutte le scelte in una riga, per l'orologio: «diario:0,sonno:2,…».
    static var scelteInRiga: String { allCases.map { "\($0.rawValue):\($0.scelta)" }.joined(separator: ",") }

    /// Sull'orologio: le scelte arrivate dall'iPhone.
    static func salva(scelteInRiga riga: String) {
        for coppia in riga.split(separator: ",") {
            let p = coppia.split(separator: ":")
            guard p.count == 2, let s = SezioneOlo(rawValue: String(p[0])), let k = Int(p[1]) else { continue }
            if UserDefaults.standard.integer(forKey: s.chiave) != k { UserDefaults.standard.set(min(s.nomi.count - 1, max(0, k)), forKey: s.chiave) }
        }
    }
}

/// I colori e gli attrezzi del mockup: OLO_C (#8ff0ff), OLO_B (#f0fdff), OLO_S (#4fe3ff) con la loro trasparenza.
enum OP {
    static func c(_ a: Double) -> Color { Color(red: 143 / 255, green: 240 / 255, blue: 1).opacity(min(1, max(0, a))) }
    static func b(_ a: Double) -> Color { Color(red: 240 / 255, green: 253 / 255, blue: 1).opacity(min(1, max(0, a))) }
    static func s(_ a: Double) -> Color { Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(min(1, max(0, a))) }
    static let rgbC = Color(red: 143 / 255, green: 240 / 255, blue: 1)
    static let rgbB = Color(red: 240 / 255, green: 253 / 255, blue: 1)
    static let rgbS = Color(red: 79 / 255, green: 227 / 255, blue: 1)
    static let due = 2 * Double.pi

    /// lisO del mockup (smoothstep).
    static func lis(_ u: Double) -> Double { Olo.liscia(u) }

    /// casoOlo del mockup, uguale bit per bit (così gli stessi semi danno gli stessi numeri): 0…1.
    nonisolated static func caso(_ i: Int) -> Double {
        var v = UInt32(truncatingIfNeeded: i) ^ 0x9E37_79B9
        v = v &* 0x85EB_CA6B
        v ^= v >> 13
        v = v &* 0xC2B2_AE35
        v ^= v >> 16
        return Double(v) / 4_294_967_296
    }

    /// I giorni e i mesi come nel mockup («DOM 25 OTT»).
    static let giorni = ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"]
    static let mesi = ["GEN", "FEB", "MAR", "APR", "MAG", "GIU", "LUG", "AGO", "SET", "OTT", "NOV", "DIC"]
    static func giorno(_ d: Date) -> String {
        let cal = Calendar.current
        let w = cal.component(.weekday, from: d) - 1, g = cal.component(.day, from: d), m = cal.component(.month, from: d) - 1
        return "\(giorni[max(0, min(6, w))]) \(g) \(mesi[max(0, min(11, m))])"
    }
    /// La lettera del giorno della settimana (D, L, M…).
    static func lettera(_ d: Date) -> String { String(giorni[max(0, min(6, Calendar.current.component(.weekday, from: d) - 1))].prefix(1)) }
    static func durata(_ minuti: Double) -> String { Olo.durata(Int(minuti.rounded())) }
    static func euro(_ v: Double) -> String { Olo.numero(v) + " €" }
    /// v267 · quantoFaOlo: da quanto, «ORA», «5 MIN», «2 H», «IERI», «3 G».
    static func quantoFa(_ d: Date?, ora: Date = Date()) -> String {
        guard let d else { return "" }
        let m = max(0, ora.timeIntervalSince(d) / 60)
        return m < 1 ? "ORA" : m < 60 ? "\(Int(m)) MIN" : m < 1440 ? "\(Int(m / 60)) H" : m < 2880 ? "IERI" : "\(Int(m / 1440)) G"
    }
    /// v267 · cortoOlo: la prima parola, in maiuscolo, al massimo `n` lettere.
    static func corto(_ s: String, _ n: Int = 10) -> String {
        let p = s.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init)?.uppercased() ?? ""
        return p.count > n ? String(p.prefix(n - 1)) + "…" : p
    }
    /// v267 · tagliaOlo: al massimo `n` caratteri, con i puntini.
    static func taglia(_ s: String, _ n: Int) -> String {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return u.count > n ? String(u.prefix(max(1, n - 1))) + "…" : u
    }
    /// fraOlo: «50 MIN», «7 H 20».
    static func fra(_ m: Double) -> String {
        m < 60 ? "\(max(0, Int(m.rounded()))) MIN" : "\(Int(m / 60)) H \(String(format: "%02d", Int(m.truncatingRemainder(dividingBy: 60).rounded()) % 60))"
    }

    // MARK: le scritte

    static func peso(_ p: Int) -> Font.Weight { p >= 700 ? .bold : p >= 600 ? .semibold : .medium }

    /// scrittaOlo: la scritta sulla sua linea di base, allineata a sinistra, al centro o a destra; sopra la luce, non sommata.
    static func scritta(_ gc: inout GraphicsContext, _ s: String, _ x: Double, _ y: Double, _ corpo: Double, _ p: Int, _ col: Color,
                        _ al: HorizontalAlignment = .center) {
        let ancora: UnitPoint = al == .leading ? .leading : al == .trailing ? .trailing : .center
        Olo.testo(&gc, s, x, y, corpo: corpo, peso: peso(p), col, ancora: ancora)
    }

    /// Quanto è larga una scritta (punti).
    static func larghezza(_ gc: GraphicsContext, _ s: String, _ corpo: Double, _ p: Int) -> Double {
        let r = gc.resolve(Text(s).font(.system(size: corpo, weight: peso(p), design: .monospaced)))
        return Double(r.measure(in: CGSize(width: 4000, height: 400)).width)
    }

    /// scrittaDentroOlo: una scritta che resta dentro la tela (6 punti dal bordo).
    static func dentro(_ gc: inout GraphicsContext, _ W: Double, _ s: String, _ x: Double, _ y: Double, _ corpo: Double, _ p: Int, _ col: Color,
                       _ al: HorizontalAlignment = .center) {
        let w = larghezza(gc, s, corpo, p)
        let sx = al == .leading ? x : al == .trailing ? x - w : x - w / 2
        let dx = max(6 - sx, min(0, W - 6 - (sx + w)))
        scritta(&gc, s, x + dx, y, corpo, p, col, al)
    }

    // MARK: la luce

    /// oloAlone: il bagliore tondo che sfuma (ciano chiaro o bianco).
    static func alone(_ gc: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ a: Double, bianco: Bool = false) {
        Olo.alone(&gc, CGPoint(x: x, y: y), r, a, bianco ? rgbB : rgbC)
    }

    /// stelleOlo: i punti fissi che respirano, in alto.
    static func stelle(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ n: Int, _ seme: Int, alto: Double = 0.62, forza: Double = 1) {
        for i in 0..<n {
            let r = caso(seme + i * 3), px = caso(seme + i * 3 + 1) * W, py = caso(seme + i * 3 + 2) * H * alto
            let a = forza * (0.15 + 0.5 * r) * (0.55 + 0.45 * sin(t * (0.8 + 2 * r) + Double(i)))
            let l = r > 0.85 ? 1.6 : 1.0
            gc.fill(Path(CGRect(x: px, y: py, width: l, height: l)), with: .color(b(a)))
        }
    }

    /// ghieraOlo: l'anello graduato in 3D (la GHIERA della click wheel): il cerchio e `n` tacche, lunghe ogni `ogni`.
    static func ghiera(_ F: inout FasciOlo, _ P: (Double, Double, Double) -> P3, _ R: Double, _ z: Double, _ n: Int, _ ogni: Int,
                       lunga: Double = 0.08, corta: Double = 0.04) {
        var a0 = P(0, R, z)
        for i in 1...96 {
            let a1 = P(Double(i) / 96 * due, R, z)
            F.metti(a0.z + a1.z < 0 ? 2 : 1, a0, a1)
            a0 = a1
        }
        for i in 0..<n {
            let a = Double(i) / Double(n) * due, l = i % ogni == 0 ? lunga : corta, p = P(a, R, z), q = P(a, R + l, z)
            F.metti((p.z < 0 ? 3 : 1) + (i % ogni == 0 ? 1 : 0), p, q)
        }
    }

    /// lamaOlo: il velo di scansione verticale sul segmento a→b del pavimento, alto h, con la riga accesa a terra.
    static func lama(_ gc: inout GraphicsContext, _ F: inout FasciOlo, _ P: (Double, Double, Double) -> P3,
                     _ a: (Double, Double), _ b: (Double, Double), _ h: Double) {
        let p0 = P(a.0, a.1, 0), p1 = P(b.0, b.1, 0), p2 = P(b.0, b.1, h), p3 = P(a.0, a.1, h)
        var q = Path()
        q.move(to: CGPoint(x: p0.x, y: p0.y)); q.addLine(to: CGPoint(x: p1.x, y: p1.y))
        q.addLine(to: CGPoint(x: p2.x, y: p2.y)); q.addLine(to: CGPoint(x: p3.x, y: p3.y)); q.closeSubpath()
        gc.fill(q, with: .linearGradient(Gradient(colors: [s(0.22), s(0)]), startPoint: CGPoint(x: 0, y: max(p0.y, p1.y)),
                                         endPoint: CGPoint(x: 0, y: min(p2.y, p3.y))))
        F.metti(4, p0, p1)
    }

    /// posaEtichetteOlo: le etichette senza sovrapporsi (centrate in x); chi urta una già posata sale. Restituisce lo spostamento.
    static func posaEtichette(_ L: [(x: Double, y: Double, w: Double, h: Double)]) -> [Double] {
        var dy = Array(repeating: 0.0, count: L.count)
        var posate: [(x: Double, y: Double, w: Double, h: Double)] = []
        for i in L.indices.sorted(by: { L[$0].y > L[$1].y }) {
            let e = L[i]
            var y = e.y
            for _ in 0..<8 {
                guard let u = posate.first(where: { abs($0.x - e.x) < ($0.w + e.w) / 2 + 3 && abs($0.y - y) < ($0.h + e.h) / 2 + 1 }) else { break }
                y = u.y - (u.h + e.h) / 2 - 1
            }
            posate.append((x: e.x, y: y, w: e.w, h: e.h))
            dy[i] = y - e.y
        }
        return dy
    }

    /// Un poligono pieno dai punti proiettati.
    static func poligono(_ punti: [P3]) -> Path {
        var p = Path()
        for (i, q) in punti.enumerated() {
            if i == 0 { p.move(to: CGPoint(x: q.x, y: q.y)) } else { p.addLine(to: CGPoint(x: q.x, y: q.y)) }
        }
        p.closeSubpath()
        return p
    }

    // MARK: il riquadro (come l'HUD di Stark)

    /// riquadroOlo: il mirino sul punto, la linea a gomito, il vetro scuro con le staffe, il codice e i dati che si scrivono.
    /// `righe[0]` è il titolo; `eta` = secondi dalla scelta.
    static func riquadro(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ px: Double, _ py: Double, _ righe: [String], _ eta: Double,
                         codice: String = "") {
        let k = lis(eta / 0.22)
        guard k > 0.001, !righe.isEmpty else { return }
        let prima = gc.blendMode
        gc.blendMode = .normal
        defer { gc.blendMode = prima }
        var bw = larghezza(gc, righe[0], 9, 700)
        for r in righe.dropFirst() { bw = max(bw, larghezza(gc, r, 8, 500)) }
        if !codice.isEmpty { bw = max(bw, larghezza(gc, codice, 6.5, 600)) }
        bw = (bw + 18).rounded(.up)
        let bh = 12 + 11 * Double(righe.count) + (codice.isEmpty ? 0 : 9)
        let verso: Double = px < W * 0.5 ? 1 : -1
        var bx = verso > 0 ? px + 30 : px - 30 - bw
        bx = max(6, min(W - bw - 6, bx))
        var by = py - bh - 16
        if by < 22 { by = py + 18 }
        by = max(22, min(H - bh - 6, by))
        let ex = bx + bw / 2 - verso * (bw / 2), ey = by + (by > py ? 0 : bh), gx = ex - verso * 10
        // il mirino sul punto
        let giro = eta * 2.2
        var mirino = Path()
        mirino.addEllipse(in: CGRect(x: px - (5 + 3 * (1 - k)), y: py - (5 + 3 * (1 - k)), width: 2 * (5 + 3 * (1 - k)), height: 2 * (5 + 3 * (1 - k))))
        for i in 0..<4 {
            let a = giro + Double(i) * 1.5708
            Olo.linea(&mirino, px + cos(a) * 8, py + sin(a) * 8, px + cos(a) * 11, py + sin(a) * 11)
        }
        gc.stroke(mirino, with: .color(b(0.9 * k)), lineWidth: 1)
        // la linea a gomito, che si disegna
        let l1 = hypot(gx - px, ey - py), l2 = abs(ex - gx), L = (l1 + l2) * k
        var gomito = Path()
        gomito.move(to: CGPoint(x: px, y: py))
        if L <= l1 { gomito.addLine(to: CGPoint(x: px + (gx - px) * L / max(0.001, l1), y: py + (ey - py) * L / max(0.001, l1))) }
        else { gomito.addLine(to: CGPoint(x: gx, y: ey)); gomito.addLine(to: CGPoint(x: gx + (ex - gx) * (L - l1) / max(1, l2), y: ey)) }
        gc.stroke(gomito, with: .color(c(0.85)), lineWidth: 1)
        // il vetro e le staffe
        let kb = lis((eta - 0.12) / 0.18)
        guard kb > 0 else { return }
        let vetro = CGRect(x: bx, y: by, width: bw, height: bh)
        gc.fill(Path(vetro), with: .color(Color(red: 2 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.84 * kb)))
        gc.stroke(Path(vetro.insetBy(dx: 0.5, dy: 0.5)), with: .color(s(0.4 * kb)), lineWidth: 1)
        var staffe = Path()
        let st = 6.0
        let angoli: [(Double, Double, Double, Double)] = [(bx, by, 1, 1), (bx + bw, by, -1, 1), (bx, by + bh, 1, -1), (bx + bw, by + bh, -1, -1)]
        for (ax, ay, dx, dy) in angoli {
            staffe.move(to: CGPoint(x: ax, y: ay + dy * st)); staffe.addLine(to: CGPoint(x: ax, y: ay)); staffe.addLine(to: CGPoint(x: ax + dx * st, y: ay))
        }
        gc.stroke(staffe, with: .color(b(0.95 * kb)), lineWidth: 1.4)
        // i dati che si scrivono
        var resta = max(0, Int(((eta - 0.2) * 95).rounded(.down)))
        var y = by + 11
        if !codice.isEmpty {
            scritta(&gc, String(codice.prefix(resta)), bx + 9, y, 6.5, 600, s(0.85 * kb), .leading)
            resta -= codice.count
            y += 9
        }
        for (i, r) in righe.enumerated() {
            guard resta > 0 else { break }
            scritta(&gc, String(r.prefix(resta)), bx + 9, y + 2, i == 0 ? 9 : 8, i == 0 ? 700 : 500, i == 0 ? b(1) : c(0.92), .leading)
            resta -= r.count
            y += 11
        }
    }

    /// aiutoOlo: il suggerimento in basso finché non si tocca. 7 nov (il signore, «fondo scuro dietro»): una pillola scura sotto
    /// la scritta, che la stacca dall'anello del proiettore (prima le tacche le passavano sopra e si leggeva male).
    static func aiuto(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ testo: String, _ t: Double) {
        let f = lis((t - 1.2) / 0.6) * (0.75 + 0.25 * sin(t * 2.4)), a = 0.55 * f
        guard a > 0.01 else { return }
        let w = larghezza(gc, testo, 7, 600) + 14, alta = 12.0, y = H - 6 - 7 * 0.36
        let pillola = Path(roundedRect: CGRect(x: W / 2 - w / 2, y: y - alta / 2, width: w, height: alta), cornerRadius: alta / 2)
        var g = gc
        g.blendMode = .normal
        g.fill(pillola, with: .color(Color(red: 2 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.85 * f)))
        g.stroke(pillola, with: .color(s(0.25 * f)), lineWidth: 0.6)
        scritta(&gc, testo, W / 2, H - 6, 7, 600, c(a))
    }
}

/// fasciOlo: i tratti raccolti per luminosità (un disegno per gruppo), con l'alone largo per i gruppi chiari.
struct FasciOlo {
    private var p: [Path]
    init(_ n: Int) { p = Array(repeating: Path(), count: n) }

    private func k(_ g: Int) -> Int { g < 0 ? 0 : (g >= p.count ? p.count - 1 : g) }

    mutating func metti(_ g: Int, _ a: P3, _ b: P3) {
        let i = k(g)
        p[i].move(to: CGPoint(x: a.x, y: a.y))
        p[i].addLine(to: CGPoint(x: b.x, y: b.y))
    }

    mutating func linea(_ g: Int, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        let i = k(g)
        p[i].move(to: CGPoint(x: x0, y: y0))
        p[i].addLine(to: CGPoint(x: x1, y: y1))
    }

    func linee(_ gc: inout GraphicsContext, colore: (Int) -> Color, spessore: (Int) -> Double, alone: ((Int) -> Color?)? = nil) {
        for g in p.indices where !p[g].isEmpty {
            if let a = alone?(g) { gc.stroke(p[g], with: .color(a), style: Olo.tratto(spessore(g) * 4.5)) }
            gc.stroke(p[g], with: .color(colore(g)), style: Olo.tratto(spessore(g)))
        }
    }
}

/// puntiOlo: i punti raccolti per luminosità (un riempimento per gruppo: migliaia di punti senza pesare).
struct PuntiOlo {
    private var p: [Path]
    init(_ n: Int) { p = Array(repeating: Path(), count: n) }

    mutating func metti(_ g: Int, _ x: Double, _ y: Double, _ l: Double) {
        let i = max(0, min(p.count - 1, g))
        p[i].addRect(CGRect(x: x - l / 2, y: y - l / 2, width: l, height: l))
    }

    func disegna(_ gc: inout GraphicsContext, colore: (Int) -> Color) {
        for g in p.indices where !p[g].isEmpty { gc.fill(p[g], with: .color(colore(g))) }
    }
}

/// manoOlo: il dito su un ologramma. Di lato: `giro` (radianti, con lo slancio) e `dx` (punti); il tocco secco sceglie l'elemento più
/// vicino fra le zone segnate dall'ultimo fotogramma; toccato di nuovo o fuori, si chiude. In verticale la pagina scorre.
final class ManoOlo {
    struct Zona { let x: Double; let y: Double; let r: Double; let id: Int }

    var giro = 0.0
    var vel = 0.0
    var dx = 0.0
    var dito = false
    var scelta: Int?
    var sceltaT = -9.0
    var zone: [Zona] = []
    var usata = false
    var t = 0.0
    var dt = 1.0 / 60
    var ultimo: Double?
    /// Spesa: il tocco fa già l'azione (spunta la voce), niente riquadro. Vero = fatto.
    var suTocco: ((Int) -> Bool)?

    // il dito in corso
    private var mosso = false
    private var verticale = false
    private var ultimaX: CGFloat = 0
    private var ultimoMoto = Date.distantPast

    func zona(_ x: Double, _ y: Double, _ r: Double, _ id: Int) { zone.append(Zona(x: x, y: y, r: r, id: id)) }

    /// Una prova nuova: tutto da capo.
    func azzera() {
        giro = 0; vel = 0; dx = 0; scelta = nil; sceltaT = -9; suTocco = nil; usata = false; ultimo = nil; zone.removeAll()
    }

    /// Lo slancio, a ogni fotogramma.
    func passo(_ dt: Double) {
        self.dt = dt
        guard !dito else { return }
        giro += vel * dt
        dx += vel / 0.011 * dt
        vel *= exp(-dt * 2.4)
        if abs(vel) < 0.01 { vel = 0 }
    }

    /// Il dito si muove (dal primo contatto): solo di lato gira.
    func muove(inizio: CGPoint, punto: CGPoint) {
        if !dito { dito = true; vel = 0; mosso = false; verticale = false; ultimaX = inizio.x; ultimoMoto = Date() }
        let ax = abs(punto.x - inizio.x), ay = abs(punto.y - inizio.y)
        if !mosso && !verticale {
            if ax > 7 && ax > ay { mosso = true } else if ay > 7 { verticale = true }
        }
        let ora = Date()
        if mosso {
            let d = Double(punto.x - ultimaX)
            giro += d * 0.011
            dx += d
            usata = true
            let v = d * 0.011 / max(0.008, ora.timeIntervalSince(ultimoMoto))
            vel = vel * 0.4 + v * 0.6
        }
        ultimaX = punto.x
        ultimoMoto = ora
    }

    /// Il dito si alza: restituisce il punto del tocco se era un tocco secco (niente movimento).
    func lascia(inizio: CGPoint, punto: CGPoint) -> CGPoint? {
        defer { dito = false; mosso = false; verticale = false }
        if Date().timeIntervalSince(ultimoMoto) > 0.09 { vel = 0 }           // fermo prima di alzare: niente slancio
        guard !mosso, !verticale, hypot(punto.x - inizio.x, punto.y - inizio.y) < 10 else { return nil }
        return punto
    }

    enum Esito { case niente, chiuso, scelto, fatto }

    /// toccoOlo: sceglie l'elemento più vicino; toccato di nuovo o fuori, si chiude.
    func tocca(_ p: CGPoint) -> Esito {
        usata = true
        var meglio: Int?
        var d0 = 1e9
        for z in zone {
            let d = hypot(z.x - Double(p.x), z.y - Double(p.y))
            if d < max(z.r, 16) && d < d0 { d0 = d; meglio = z.id }
        }
        // 9 nov: l'azione del tocco viene prima (EDITH: toccato di nuovo, il controllo parte; prima il secondo tocco chiudeva e basta)
        if let m = meglio, let f = suTocco, f(m) { return .fatto }
        guard let m = meglio, m != scelta else {
            if scelta != nil { scelta = nil; return .chiuso }
            return .niente
        }
        scelta = m
        sceltaT = t
        return .scelto
    }
}

/// Il giro di ogni fotogramma (come proveOlo del mockup): lo slancio, le zone da capo, la scansione che porta la prova nuova (0,45 s)
/// e il suggerimento finché non si tocca. `disegna` disegna la prova.
enum MotoreOlo {
    static func fotogramma(_ gc: inout GraphicsContext, _ size: CGSize, _ t: Double, _ M: ManoOlo, aiuto: String?,
                           disegna: (inout GraphicsContext, Double, Double) -> Void) {
        let W = Double(size.width), H = Double(size.height)
        guard W > 4, H > 4 else { return }
        let dt = M.ultimo.map { min(0.05, max(0, t - $0)) } ?? 1.0 / 60
        M.ultimo = t
        M.passo(dt)
        M.zone.removeAll(keepingCapacity: true)
        M.t = t
        gc.blendMode = .plusLighter
        let sc = t < 0.45 ? OP.lis(t / 0.45) : 1
        if sc < 1 {
            var g = gc
            g.clip(to: Path(CGRect(x: 0, y: 0, width: W, height: H * sc + 1)))
            disegna(&g, W, H)
            let y = H * sc
            gc.fill(Path(CGRect(x: 0, y: y - 18, width: W, height: 18)),
                    with: .linearGradient(Gradient(colors: [OP.s(0), OP.s(0.35)]), startPoint: CGPoint(x: 0, y: y - 18), endPoint: CGPoint(x: 0, y: y)))
            gc.fill(Path(CGRect(x: 0, y: y - 1, width: W, height: 1.2)), with: .color(OP.b(0.9)))
        } else {
            disegna(&gc, W, H)
        }
        if !M.usata, let a = aiuto, !a.isEmpty { OP.aiuto(&gc, W, H, a, t) }
    }
}

/// v267 · un ologramma solo, in piccolo (il polso: Email), senza scritte e senza dita.
struct OloPiccolaVista: View {
    let disegna: (inout GraphicsContext, Double, Double, Double, ManoOlo) -> Void
    @State private var mano = ManoOlo()
    @State private var inizio = Date()
    @Environment(\.accessibilityReduceMotion) private var riduci

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: riduci)) { ctx in
            let t = riduci ? 6 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in
                let W = Double(size.width), H = Double(size.height)
                guard W > 4, H > 4 else { return }
                gc.blendMode = .plusLighter
                disegna(&gc, W, H, t, mano)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Sull'orologio (e ovunque serva in piccolo): la prova scelta sull'iPhone, senza scritte e senza dita, al ritmo del polso.
struct ProvaOloPiccola: View {
    let sezione: SezioneOlo
    let disegna: (Int, inout GraphicsContext, Double, Double, Double, ManoOlo) -> Void
    @AppStorage private var scelta: Int
    @State private var mano = ManoOlo()
    @State private var inizio = Date()
    @Environment(\.accessibilityReduceMotion) private var riduci

    init(sezione: SezioneOlo, disegna: @escaping (Int, inout GraphicsContext, Double, Double, Double, ManoOlo) -> Void) {
        self.sezione = sezione
        self.disegna = disegna
        _scelta = AppStorage(wrappedValue: 0, sezione.chiave)
    }

    var body: some View {
        let k = min(sezione.nomi.count - 1, max(0, scelta))
        TimelineView(.animation(minimumInterval: nil, paused: riduci)) { ctx in
            let t = riduci ? 6 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in
                let W = Double(size.width), H = Double(size.height)
                guard W > 4, H > 4 else { return }
                gc.blendMode = .plusLighter
                disegna(k, &gc, W, H, t, mano)
            }
        }
        .onChange(of: scelta) { _, _ in inizio = Date() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(iOS)
/// Le chip delle prove (come `.olo-prove .chip` del mockup: 10 punti, spaziatura 1,5, accesa piena di ciano).
struct ChipOlo: View {
    let testo: String
    let acceso: Bool
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            Text(testo)
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(acceso ? Color(red: 0, green: 0.094, blue: 0.125) : Color.ciano)
                .padding(.vertical, 7).padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(acceso ? Color.ciano : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(acceso ? 1 : 0.3), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
        .accessibilityAddTraits(acceso ? .isSelected : [])
    }
}

/// v267 · un ologramma solo nella sezione (Messaggi, Email, Confidente), come le prove ma senza chip: la tela, il dito di lato che
/// lo gira (con lo slancio), il tocco su un elemento che apre il suo riquadro, la scansione che lo porta all'apertura e il suggerimento
/// finché non si tocca. Si ferma con «Riduci movimento» (resta il disegno finito) e quando la sezione è dietro.
struct OloSingolaVista: View {
    let altezza: CGFloat
    let aiuto: String
    let etichetta: String
    let disegna: (inout GraphicsContext, Double, Double, Double, ManoOlo) -> Void

    @State private var mano = ManoOlo()
    @State private var inizio = Date()
    @State private var ritocco = 0
    @Environment(\.accessibilityReduceMotion) private var riduci
    @Environment(\.sezioneDietro) private var dietro

    var body: some View {
        let tocchi = ritocco, aiuto = self.aiuto
        TimelineView(.animation(minimumInterval: nil, paused: riduci || dietro)) { ctx in
            let t = riduci ? 6 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in
                _ = tocchi                                        // con «Riduci movimento»: un tocco ridisegna
                MotoreOlo.fotogramma(&gc, size, t, mano, aiuto: aiuto) { g, W, H in disegna(&g, W, H, t, mano) }
            }
        }
        .frame(height: altezza)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in mano.muove(inizio: v.startLocation, punto: v.location) }
                .onEnded { v in
                    guard let p = mano.lascia(inizio: v.startLocation, punto: v.location) else { return }
                    switch mano.tocca(p) {
                    case .scelto, .chiuso: Suoni.tocco()
                    case .fatto, .niente: break
                    }
                    ritocco += 1
                }
        )
        .accessibilityElement()
        .accessibilityLabel(etichetta)
    }
}

/// Le prove di un ologramma nella sezione, come il mockup v262: la tela col disegno scelto e, sotto, le chip (tre). Il dito di lato lo
/// gira (con lo slancio), il tocco su un elemento apre il suo riquadro; passando a un'altra prova, una scansione scende e la ridisegna.
/// La scelta resta (anche sul polso). Si ferma con «Riduci movimento» (resta il disegno finito) e quando la sezione è dietro.
struct ProveOloVista: View {
    let sezione: SezioneOlo
    let altezza: CGFloat
    /// La prova `k` riparte da capo (il suo stato: pagine uscite, penna, monete…).
    let crea: (Int) -> Void
    let disegna: (Int, inout GraphicsContext, Double, Double, Double, ManoOlo) -> Void
    /// Attorno alle chip: come `.olo-prove` (4 · 10 · 10 · 10); nella Serata, dentro il pannello, `.se-olo .olo-prove` (2 · 0 · 6 · 0).
    let margini: EdgeInsets

    @AppStorage private var scelta: Int
    @State private var mano = ManoOlo()
    @State private var inizio = Date()
    @State private var ritocco = 0
    @Environment(\.accessibilityReduceMotion) private var riduci
    @Environment(\.sezioneDietro) private var dietro

    init(sezione: SezioneOlo, altezza: CGFloat, margini: EdgeInsets = EdgeInsets(top: 4, leading: 10, bottom: 10, trailing: 10),
         crea: @escaping (Int) -> Void, disegna: @escaping (Int, inout GraphicsContext, Double, Double, Double, ManoOlo) -> Void) {
        self.sezione = sezione
        self.altezza = altezza
        self.margini = margini
        self.crea = crea
        self.disegna = disegna
        _scelta = AppStorage(wrappedValue: 0, sezione.chiave)
    }

    private var k: Int { min(sezione.nomi.count - 1, max(0, scelta)) }

    var body: some View {
        VStack(spacing: 0) {
            tela
            HStack(spacing: 6) {
                ForEach(sezione.nomi.indices, id: \.self) { i in
                    ChipOlo(testo: sezione.nomi[i], acceso: i == k) { scegli(i) }
                }
            }
            .padding(margini)
        }
        .onAppear { crea(k) }
    }

    private var tela: some View {
        let k = self.k, aiuto = sezione.aiuti[k], tocchi = ritocco
        return TimelineView(.animation(minimumInterval: nil, paused: riduci || dietro)) { ctx in
            let t = riduci ? 6 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in
                _ = tocchi                                        // con «Riduci movimento»: un tocco ridisegna
                MotoreOlo.fotogramma(&gc, size, t, mano, aiuto: aiuto) { g, W, H in disegna(k, &g, W, H, t, mano) }
            }
        }
        .frame(height: altezza)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in mano.muove(inizio: v.startLocation, punto: v.location) }
                .onEnded { v in
                    guard let p = mano.lascia(inizio: v.startLocation, punto: v.location) else { return }
                    switch mano.tocca(p) {
                    case .scelto, .chiuso: Suoni.tocco()
                    case .fatto, .niente: break
                    }
                    ritocco += 1
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Ologramma, prova \(sezione.nomi[k].lowercased())")
    }

    private func scegli(_ i: Int) {
        guard i != k else { return }
        Suoni.tocco()
        scelta = i
        mano.azzera()
        crea(i)
        inizio = Date()
        ritocco += 1
        PonteTelefono.condiviso.invia()                           // il polso segue la scelta
    }
}
#endif
