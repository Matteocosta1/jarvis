import Foundation
import SwiftUI

// MARK: - GLI OLOGRAMMI DELLA TAVOLA (build 11.0 (19), 9 nov) — il mockup «olo/a_base.js», riportato uguale
// Il signore: «falli tutti J, con massima competenza… cool, realistici, attinenti alla sezione e a Tony Stark». Ogni sezione senza
// fotocamera ha le sue prove (le chip sotto la tela), come Diario, Sonno, Briefing, Spesa, Serata e Bea. Qui gli attrezzi comuni:
// la scena (proiettore, cono, prospettiva), il tratto, i cerchi, il globo coi continenti, le testate in alto, i colori.
// I disegni delle sezioni stanno in ProveTavolaA (Cuore, Telefono), ProveTavolaB (Meteo, EDITH, Posta, Messaggi, Confidente,
// Interprete, Ricordi) e ProveTavolaC (Vitals, GitHub, Supabase, Archivio, Costi: questi anche sul polso).
// Questo file è sia dell'iPhone sia dell'orologio.

/// Come si monta la scena (le opzioni di scenaOlo del mockup).
struct OpzioniOlo {
    var al = 0.3
    var sz = 1.0
    var su = 0.9
    var giro = 0.15
    var oscilla = 0.0
    var mano = 1.0
    var rx = 0.22
    var cono = true
    var conoSu = 0.6
    var conoW = 0.9
    var conoA = 0.07
    var nasce = 0.9
}

/// La scena montata: centro, misura, giro e inclinazione, quanto è nata (0…1) e la proiezione.
struct ScenaTav {
    let cx: Double
    let cy: Double
    let base: Double
    let sz: Double
    let ang: Double
    let al: Double
    let nasce: Double

    func P(_ x: Double, _ y: Double, _ z: Double) -> P3 { Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
    func Pv(_ v: P3) -> P3 { Olo.proietta(v.x, v.y, v.z, ang, al, cx, cy, sz) }
}

enum Tav {
    // i colori della luce (oloAlone del mockup)
    static let bianco = OP.rgbB
    static let ciano = OP.rgbC
    static let arancio = Color(red: 1, green: 170 / 255, blue: 80 / 255)
    static let rosa = Color(red: 1, green: 120 / 255, blue: 140 / 255)
    static let verde = Color(red: 120 / 255, green: 1, blue: 190 / 255)
    static let oro = Color(red: 1, green: 200 / 255, blue: 120 / 255)
    static let menta = Color(red: 160 / 255, green: 1, blue: 200 / 255)
    static let reattore = Color(red: 200 / 255, green: 250 / 255, blue: 1)
    static func a(_ c: Color, _ x: Double) -> Color { c.opacity(min(1, max(0, x))) }

    /// scenaOlo: il proiettore, il cono e la prospettiva.
    static func scena(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ piccolo: Bool,
                      _ o: OpzioniOlo) -> ScenaTav {
        let cx = W / 2, base = piccolo ? H - 3 : H - 12, rx = piccolo ? W * 0.3 : min(W * o.rx, 90)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        let sz = (piccolo ? H * 0.5 : min(W * 0.34, H * 0.42)) * o.sz, cy = base - (piccolo ? 4 : 10) - sz * o.su
        let ang = (o.oscilla != 0 ? o.oscilla * sin(t * 0.3) : t * o.giro) + M.giro * o.mano
        if o.cono { Olo.cono(&gc, cx, base, rx, cy - sz * o.conoSu, sz * o.conoW, a: o.conoA) }
        return ScenaTav(cx: cx, cy: cy, base: base, sz: sz, ang: ang, al: o.al, nasce: OP.lis(t / o.nasce))
    }

    /// tracciaOlo: le linee raccolte, nello stile di sempre (0-5 dal tenue al bianco, l'alone sui chiari).
    static func traccia(_ gc: inout GraphicsContext, _ F: FasciOlo, _ piccolo: Bool, k: Double = 1) {
        F.linee(&gc, colore: { $0 >= 4 ? OP.b(0.9) : OP.c(0.08 + 0.17 * Double($0)) },
                spessore: { (piccolo ? 0.45 + Double($0) * 0.09 : 0.65 + Double($0) * 0.15) * k },
                alone: { $0 >= 3 && !piccolo ? OP.s(0.08) : nil })
    }

    /// cerchioF: un cerchio orizzontale di raggio r a quota z (centro cx, cy), fino a una frazione del giro.
    static func cerchio(_ F: inout FasciOlo, _ s: ScenaTav, _ r: Double, _ z: Double, _ g: Int, n: Int = 48,
                        cx: Double = 0, cy: Double = 0, fino: Double = 1) {
        var q: P3?
        let fine = Int(Double(n) * fino)
        guard fine >= 1 else { return }
        for i in 0...fine {
            let a = Double(i) / Double(n) * OP.due, p = s.P(cx + cos(a) * r, cy + sin(a) * r, z)
            if let q { F.metti(g, q, p) }
            q = p
        }
    }

    /// geoOlo: un punto sul globo (gradi); longitudine 0 davanti a chi guarda.
    nonisolated static func geo(_ lat: Double, _ lon: Double, _ r: Double = 1) -> P3 {
        let a = lat * .pi / 180, b = lon * .pi / 180
        return P3(r * cos(a) * sin(b), -r * cos(a) * cos(b), r * sin(a))
    }

    /// I continenti, contorni grossolani (lat, lon), come le mappe dell'officina.
    static let continenti: [[(Double, Double)]] = [
        [(71, 25), (70, 60), (73, 100), (68, 140), (62, 165), (55, 160), (45, 142), (35, 140), (22, 120), (10, 105), (1, 104), (8, 98), (21, 92), (22, 88), (8, 77),
         (25, 67), (25, 57), (13, 45), (30, 32), (37, 36), (41, 29), (45, 13), (38, 15), (43, 5), (36, -5), (43, -9), (48, -4), (54, 8), (57, 10), (65, 13), (71, 25)],
        [(37, -5), (35, 10), (33, 22), (31, 32), (12, 44), (11, 51), (-2, 41), (-15, 40), (-26, 33), (-34, 25), (-34, 18), (-17, 12), (-5, 12), (4, 9), (5, -5), (11, -16),
         (21, -17), (28, -13), (37, -5)],
        [(70, -160), (71, -128), (68, -95), (60, -64), (47, -53), (44, -66), (30, -81), (25, -80), (29, -95), (19, -96), (16, -88), (9, -79), (8, -83), (16, -95),
         (23, -106), (32, -117), (40, -124), (49, -125), (59, -138), (60, -147), (55, -162), (70, -160)],
        [(12, -72), (9, -61), (-5, -35), (-23, -42), (-34, -53), (-41, -63), (-55, -68), (-46, -75), (-18, -70), (-5, -81), (1, -80), (12, -72)],
        [(-11, 132), (-12, 142), (-25, 153), (-38, 147), (-38, 140), (-32, 115), (-22, 114), (-14, 127), (-11, 132)],
        [(60, -45), (76, -20), (82, -40), (77, -70), (60, -45)],
    ]

    /// globoOlo: paralleli, meridiani e continenti (davanti più chiari). Restituisce il punto (lat, lon) proiettato.
    static func globo(_ F: inout FasciOlo, _ s: ScenaTav, _ r: Double, giroLon: Double) -> (Double, Double) -> P3 {
        let raggio = r * s.nasce
        let G = { (lat: Double, lon: Double) -> P3 in s.Pv(geo(lat, lon + giroLon, raggio)) }
        for lat in [-60.0, -30, 0, 30, 60] {
            var q: P3?
            for k in 0...48 { let p = G(lat, -180 + Double(k) * 7.5); if let q { F.metti(p.z < 0 ? 1 : 0, q, p) }; q = p }
        }
        for m in 0..<12 {
            var q: P3?
            for k in 0...24 { let p = G(-90 + Double(k) * 7.5, -180 + Double(m) * 30); if let q { F.metti(p.z < 0 ? 1 : 0, q, p) }; q = p }
        }
        for c in continenti {
            var q: P3?
            for (la, lo) in c { let p = G(la, lo); if let q { F.metti(p.z < 0 ? 3 : 1, q, p) }; q = p }
        }
        return G
    }

    /// testateOlo: in alto a sinistra il nome, a destra il valore che conta e una riga sotto.
    static func testate(_ gc: inout GraphicsContext, _ W: Double, _ sx: String, _ dx: String?, _ dx2: String? = nil) {
        OP.scritta(&gc, sx, 10, 14, 8, 600, OP.c(0.85), .leading)
        if let dx { OP.scritta(&gc, dx, W - 10, 14, 9, 800, OP.b(0.98), .trailing) }
        if let dx2 { OP.scritta(&gc, dx2, W - 10, 26, 7, 600, OP.c(0.8), .trailing) }
    }

    /// sceltaOlo: l'elemento scelto di una famiglia (gli id `base + i`), o nil.
    static func scelta(_ M: ManoOlo, _ base: Int) -> Int? {
        guard let s = M.scelta, s >= base, s < base + 1000 else { return nil }
        return s - base
    }

    /// oloAlone su un punto proiettato.
    static func alone(_ gc: inout GraphicsContext, _ p: P3, _ r: Double, _ a: Double, _ c: Color = OP.rgbC) {
        Olo.alone(&gc, CGPoint(x: p.x, y: p.y), r, a, c)
    }
    static func alone(_ gc: inout GraphicsContext, _ x: Double, _ y: Double, _ r: Double, _ a: Double, _ c: Color = OP.rgbC) {
        Olo.alone(&gc, CGPoint(x: x, y: y), r, a, c)
    }

    /// Un segmento sottile, disegnato subito (il moveTo/lineTo/stroke del mockup).
    static func segmento(_ gc: inout GraphicsContext, _ a: P3, _ b: P3, _ col: Color, _ w: Double, tratteggio: [CGFloat] = [], fase: CGFloat = 0) {
        var p = Path()
        p.move(to: CGPoint(x: a.x, y: a.y)); p.addLine(to: CGPoint(x: b.x, y: b.y))
        gc.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round, dash: tratteggio, dashPhase: fase))
    }

    /// Una spezzata dai punti proiettati.
    static func spezzata(_ punti: [P3], chiusa: Bool = false) -> Path {
        var p = Path()
        for (i, q) in punti.enumerated() { if i == 0 { p.move(to: CGPoint(x: q.x, y: q.y)) } else { p.addLine(to: CGPoint(x: q.x, y: q.y)) } }
        if chiusa { p.closeSubpath() }
        return p
    }

    /// Un arco di cerchio sullo schermo (come arc del Canvas: angoli in radianti, in senso orario).
    static func arco(_ cx: Double, _ cy: Double, _ r: Double, _ a0: Double, _ a1: Double) -> Path {
        var p = Path()
        Olo.arco(&p, cx, cy, r, r, a0, a1)
        return p
    }

    /// bezOlo: la curva di Bézier quadratica.
    nonisolated static func bez(_ a: P3, _ b: P3, _ c: P3, _ u: Double) -> P3 {
        let v = 1 - u
        return a * (v * v) + b * (2 * v * u) + c * (u * u)
    }

    /// Un seme sempre uguale per una parola (hashOlo del mockup): 0…100002.
    nonisolated static func seme(_ s: String) -> Int {
        var h = 7
        for c in s.unicodeScalars { h = (h * 31 + Int(c.value)) % 100_003 }
        return h
    }

    /// Le cifre all'italiana, con due decimali e la virgola.
    nonisolated static func soldi(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
    nonisolated static func uno(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }

    /// «ADESSO», «12 MIN FA», «3 H FA», «2 G FA».
    static func fa(_ d: Date?) -> String {
        guard let d else { return "" }
        let m = max(0, Int((Date().timeIntervalSince(d) / 60).rounded()))
        return m < 1 ? "ADESSO" : m < 60 ? "\(m) MIN FA" : m < 1440 ? "\(Int((Double(m) / 60).rounded())) H FA" : "\(Int((Double(m) / 1440).rounded())) G FA"
    }

    /// Il giorno come «LUN 26 OTT».
    static func giorno(_ d: Date) -> String { OP.giorno(d) }
}
