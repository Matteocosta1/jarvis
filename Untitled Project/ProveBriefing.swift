import Foundation
import SwiftUI

// MARK: - BRIEFING · le tre prove (mockup v262–v264): RADAR, GLOBO, PISTA

/// La giornata come il mockup: alba e tramonto (minuti del giorno), il meteo, dove si è e gli impegni di oggi.
struct BriefingOlo {
    struct Impegno { let m: Double; let nome: String; let corto: String }
    var alba = 420.0
    var tramonto = 1020.0
    var gradi: Int?
    var massima: Int?
    var cielo = ""
    var lat = 45.4642
    var lon = 9.19
    var luogo = "MILANO"
    var impegni: [Impegno] = []

    /// I minuti del giorno di un istante (con i secondi, come il mockup: la pista e il radar scorrono senza scatti).
    static func minuti(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: d)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// Il nome corto di un impegno (la prima parola, in maiuscolo): «Studio · stampa supporto» → STUDIO.
    static func corto(_ titolo: String) -> String {
        let p = titolo.split(whereSeparator: { $0 == " " || $0 == "·" || $0 == "-" || $0 == "," }).first.map(String.init) ?? titolo
        let u = p.uppercased()
        return u.count > 12 ? String(u.prefix(11)) + "…" : u
    }

    /// Le coordinate scritte come nel mockup: 45°28′N 9°11′E.
    var coordinate: String {
        func gm(_ v: Double) -> String { let a = abs(v); return "\(Int(a))°\(String(format: "%02d", Int(((a - Double(Int(a))) * 60).rounded()) % 60))′" }
        return "\(gm(lat))\(lat >= 0 ? "N" : "S") \(gm(lon))\(lon >= 0 ? "E" : "W")"
    }
}

/// Le tre prove del briefing.
final class ProveBriefing {
    func crea(_ k: Int) {}

    /// L'ora di adesso scritta per difetto (alle 10:29:40 sono le 10:29, non le 10:30).
    private func hm(_ m: Double) -> String { Olo.ora(m.rounded(.down)) }

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BriefingOlo, piccolo: Bool) {
        let ora = BriefingOlo.minuti(Date())
        switch k {
        case 1: globo(&gc, W, H, t, M, B, ora, piccolo)
        case 2: pista(&gc, W, H, t, M, B, ora, piccolo)
        default: radar(&gc, W, H, t, M, B, ora, piccolo)
        }
    }

    // MARK: B1 · RADAR — la giornata sul radar di Stark: il disco è inclinato, adesso sta davanti; ogni impegno è un bersaglio all'ora
    // giusta sul quadrante delle 24 ore, tanto più vicino al centro quanto prima arriva (gli anelli: fra 3, 6, 9, 12 ore). Il fascio gira
    // e li accende; il prossimo è il più chiaro, con il suo anello e il conto alla rovescia. Sul bordo la luce da alba a tramonto.

    private func radar(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BriefingOlo, _ ora: Double, _ piccolo: Bool) {
        let cx = W / 2, sz = piccolo ? W * 0.36 : min(W * 0.36, (H - 58) / 2.03), cy = piccolo ? H * 0.5 : 36 + 0.86 * sz, al = 1.02, ang = M.giro
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let aDi = { (m: Double) -> Double in -Double.pi / 2 + (m - ora) / 1440 * OP.due }
        let rDi = { (m: Double) -> Double in m < ora ? 1.04 : 0.16 + 0.84 * min(1, (m - ora) / 720) }
        let pol = { (a: Double, r: Double) -> P3 in P(cos(a) * r, sin(a) * r, 0) }
        var F = FasciOlo(6)
        let apre = OP.lis(t / 0.8)
        // gli anelli della distanza (3, 6, 9, 12 ore) e il quadrante delle 24 ore sul bordo, con la luce del giorno
        for k in 1...4 {
            let r = (0.16 + 0.84 * Double(k) / 4) * apre
            var q: P3?
            for i in 0...96 { let o = pol(Double(i) / 96 * OP.due, r); if let q, k == 4 || i % 2 == 1 { F.metti(k == 4 ? 2 : 0, q, o) }; q = o }
        }
        for h in 0..<96 {
            let m = Double(h) * 15, a = aDi(m), lunga = h % 24 == 0, ora1 = h % 4 == 0
            F.metti(lunga ? 3 : ora1 ? 1 : 0, pol(a, 1.04 * apre), pol(a, (lunga ? 1.14 : ora1 ? 1.1 : 1.07) * apre))
        }
        do {
            var q: P3?
            var m = B.alba
            while m <= B.tramonto { let o = pol(aDi(m), 1.04 * apre); if let q { F.metti(4, q, o) }; q = o; m += 6 }
        }
        // il fascio che gira, con la sua scia
        let s = -Double.pi / 2 + t * 2.1, c0 = P(0, 0, 0)
        for k in 0..<12 {
            let a0 = s - Double(k) * 0.045, a1 = s - Double(k + 1) * 0.045
            gc.fill(OP.poligono([c0, pol(a0, 1.02 * apre), pol(a1, 1.02 * apre)]), with: .color(OP.s(0.16 * (1 - Double(k) / 12))))
        }
        F.metti(5, c0, pol(s, 1.02 * apre))
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.9) : $0 == 4 ? OP.b(0.6) : OP.c(0.1 + 0.16 * Double($0)) },
                spessore: { $0 == 4 ? 2.2 : 0.75 + Double($0) * 0.12 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        if !piccolo {
            for h in [0, 6, 12, 18] { let p = pol(aDi(Double(h) * 60), 1.24 * apre); OP.scritta(&gc, String(format: "%02d", h), p.x, p.y + 3, 7, 700, OP.c(0.7)) }
            for k in 1...4 { let p = pol(-Double.pi / 2 + 0.2, (0.16 + 0.84 * Double(k) / 4) * apre); OP.scritta(&gc, "+\(k * 3)H", p.x + 3, p.y - 2, 6, 600, OP.c(0.45), .leading) }
        }
        // i bersagli: gli impegni (il prossimo il più chiaro, con il suo anello)
        let prossimo = B.impegni.first { $0.m > ora }
        for (i, e) in B.impegni.enumerated() {
            let a = aDi(e.m), r = rDi(e.m) * apre, p = pol(a, r), passato = e.m < ora, prox = prossimo?.m == e.m
            let d = ((s - a).truncatingRemainder(dividingBy: OP.due) + OP.due).truncatingRemainder(dividingBy: OP.due), lampo = exp(-d * 2.2)
            if prox {
                var anello = Path(), q: P3?
                for k in 0...96 { let o = pol(Double(k) / 96 * OP.due, r); if let q, k % 2 == 1 { Olo.linea(&anello, q.x, q.y, o.x, o.y) }; q = o }
                gc.stroke(anello, with: .color(OP.b(0.32 + 0.2 * sin(t * 4))), lineWidth: 1)
            }
            OP.alone(&gc, p.x, p.y, (prox ? 14 : 10) + 8 * lampo, (passato ? 0.2 : prox ? 0.6 : 0.35) + 0.5 * lampo, bianco: prox)
            let rp = prox ? 3.4 : 2.6
            gc.fill(Path(ellipseIn: CGRect(x: p.x - rp, y: p.y - rp, width: 2 * rp, height: 2 * rp)), with: .color(prox ? OP.b(1) : passato ? OP.c(0.45) : OP.c(0.9)))
            if piccolo { continue }
            OP.dentro(&gc, W, "\(Olo.ora(e.m)) \(e.corto)", p.x + 6, p.y - 5, 7, 700, prox ? OP.b(1) : passato ? OP.c(0.45) : OP.c(0.85), .leading)
            M.zona(p.x, p.y, 16, i)
        }
        // adesso: il centro e la tacca davanti
        OP.alone(&gc, c0.x, c0.y, piccolo ? 6 : 12, 0.6, bianco: true)
        gc.fill(Path(CGRect(x: c0.x - 1.5, y: c0.y - 1.5, width: 3, height: 3)), with: .color(OP.b(1)))
        guard !piccolo else { return }
        let dav = pol(-Double.pi / 2, 1.18 * apre)
        OP.scritta(&gc, "ADESSO \(hm(ora))", dav.x, dav.y + 12, 7, 700, OP.b(0.95))
        OP.scritta(&gc, "OGGI · \(B.impegni.count) IMPEGNI", 10, 14, 8, 600, OP.c(0.85), .leading)
        if let p = prossimo {
            OP.scritta(&gc, "PROSSIMITÀ · \(p.corto)", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
            OP.scritta(&gc, "TRA \(OP.fra(p.m - ora))", W - 10, 25, 9, 700, OP.b(0.6 + 0.4 * abs(sin(t * 2.2))), .trailing)
        } else {
            OP.scritta(&gc, B.impegni.isEmpty ? "GIORNATA LIBERA" : "GIORNATA FINITA", W - 10, 14, 8, 700, OP.b(0.9), .trailing)
        }
        if let k = M.scelta, k < B.impegni.count {
            let e = B.impegni[k], p = pol(aDi(e.m), rDi(e.m) * apre)
            OP.riquadro(&gc, W, H, p.x, p.y, [e.nome.uppercased(), "ORE \(Olo.ora(e.m))", e.m > ora ? "TRA \(OP.fra(e.m - ora))" : "GIÀ PASSATO"],
                        t - M.sceltaT, codice: "IMPEGNO \(k + 1)/\(B.impegni.count)")
        }
    }

    // MARK: B2 · GLOBO — la Terra di puntini di luce che gira piano attorno a dove si è: il giorno è acceso, la notte spenta, e la linea
    // del tramonto (il terminatore) li separa; il Sole è dove sta adesso. Sul posto un faro con i gradi. Il dito di lato fa girare il
    // globo; toccato il posto o il Sole, il riquadro.

    /// La Terra a puntini (Natural Earth 1:110m, una cella ogni 2°): i centri delle celle di terra, come versori. `polso`: una cella su
    /// quattro (una riga sì e una no, una colonna sì e una no): sull'orologio, a 46 punti, le celle di 2° sono più fitte di un punto.
    private static let mappa: (terra: [P3], polso: [P3]) = {
        let righe = "||1h03|1g041n02|1g04|1g05|1h034t02|1h044u02|1h054j014w01|1h064x01|1h084g024j014x02|1i074g05|1i092r0244024f07|1i0a2r0644064c0a|1i0b2r06430k|1i0c2q08430k|1j0b2p09430k|1j0c2p0b3402430j|1j0e2p0b3402430i|1j0f2o0b3402460e|1j0f2o0c3403470c|1h0i2o0e350248074h02|1g0j2o0e360149014b034h01|1f0k2p0d4c014h01|1f0l2p0d4k01|1e0n2p0d41024f034j014p01|1d0n2o0d3z014f064n01|1d0m2o0e3x0243014c064m01|1e0i2n0g3w02410346014c014e02|1e0f2n0g3w024104|1f0e2n0i3v034203|1f0d2m0k3u013w024302|1f0a1q012d062k0m3w0144014801|1d011f092b0w3m013v014702|1b011g072b0w3k023v013y0145014701|1b012a0u37013k023v013x044801|18042a0t34023j033v064602|150117032a0s33053j033t013v054601|13071f011k012a0r33073j053t064601|110519011f022a0r32093i073s07|11041e012a0q320a3h0a3s0b|10052a0q310a3g0p4601|0z061d012b0o30073b0v|0x091d012c0n3006380z|0w010y0b1b022d0t3710|0w0i2d0d2s022z184b01|0v0k2e0930164b02|0t0n2i05301649024e02|0t0n2e042o022t012v0c390w4802|0s0p2d052m012s012v0c390x47034g01|0s0r2d072m012o022s042z01330338134g01|0s0r1l012h052n012q06320437174h02|0s0u1n012h0g31053916|0t0s1o042g20|0q010s0t1p012i1y4h01|0q0n1f0b2d012f042k1y4o01|0n010p0o1e0b2d022h012m1u4o02|0a010o0m1g082f012m012o012t1m4o03|0b020n0l1f082f012o022u1m4p02|08080j0o1f041l012l062t012x1q4r02|07101f031t042l062t1y4s06|0a0z1b011d011i031s0627032n052t07311y|010406151h031l021r09260128032o0b321y|0001070p100315051b021h041r0b2q0c3401371t|090a0o010q010v0916021b031f051r0g2s053g023j174v01|0r030v07140219081q0g38023g023j033n0n4g05|0s0417011q0i39023p0c|0t010w020z01130217021o0k3c033t013v084f02|0y01130115011b041h0r2p022t01|16041b081k0p2q063s04|190d1o031s0d2601"
        let lat0 = -58.0, passo = 2.0
        var V: [P3] = [], Vp: [P3] = []
        for (j, r) in righe.split(separator: "|", omittingEmptySubsequences: false).enumerated() {
            let fi = (lat0 + Double(j) * passo) * .pi / 180, c = Array(r)
            var i = 0
            while i + 3 < c.count {
                let s = Int(String(c[i..<(i + 2)]), radix: 36) ?? 0, l = Int(String(c[(i + 2)..<(i + 4)]), radix: 36) ?? 0
                for k in s..<(s + l) {
                    let la = (-180 + passo / 2 + Double(k) * passo) * .pi / 180, v = P3(cos(fi) * cos(la), cos(fi) * sin(la), sin(fi))
                    V.append(v)
                    if j % 2 == 0 && k % 2 == 0 { Vp.append(v) }
                }
                i += 4
            }
        }
        return (terra: V, polso: Vp)
    }()

    private static func versore(_ lat: Double, _ lon: Double) -> P3 {
        let f = lat * .pi / 180, l = lon * .pi / 180
        return P3(cos(f) * cos(l), cos(f) * sin(l), sin(f))
    }

    /// Il punto sotto il Sole adesso (declinazione e ora in UTC, senza l'equazione del tempo: basta per la luce del giorno).
    private static func sole(_ d: Date = Date()) -> P3 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = cal.dateComponents([.year, .hour, .minute], from: d)
        let inizio = cal.date(from: DateComponents(year: c.year)) ?? d
        let giorno = d.timeIntervalSince(inizio) / 86_400, ore = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        return versore(-23.44 * cos(OP.due / 365 * (giorno + 10)), (12 - ore) * 15)
    }

    private func globo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BriefingOlo, _ ora: Double, _ piccolo: Bool) {
        let cx = W / 2, cy = H * (piccolo ? 0.5 : 0.56), R = (piccolo ? W * 0.42 : min(W * 0.3, H * 0.4)) * (0.6 + 0.4 * OP.lis(t / 0.9)), beta = 0.52
        let lc = (B.lon + 16 * sin(t * 0.16)) * .pi / 180 - M.giro, cl = cos(lc), sl = sin(lc), cb = cos(beta), sb = sin(beta)
        // dalla Terra allo schermo: x, y, profondità verso chi guarda
        let S = { (v: P3, r: Double) -> P3 in
            let xp = v.x * cl + v.y * sl, yp = -v.x * sl + v.y * cl, zp = v.z, d = xp * cb + zp * sb, u = -xp * sb + zp * cb, k = 3.6 / (3.6 - d * r)
            return P3(cx + yp * r * k * R, cy - u * r * k * R, d)
        }
        let sole = ProveBriefing.sole()
        let dot = { (a: P3, b: P3) -> Double in (a * b).sum() }
        if !piccolo { OP.stelle(&gc, W, H, t, 40, 911, alto: 1, forza: 0.8) }
        OP.alone(&gc, cx, cy, R * 1.35, 0.1)
        // la griglia: paralleli e meridiani ogni 30°
        var F = FasciOlo(6)
        for lat in stride(from: -60.0, through: 60, by: 30) {
            var q: P3?
            for lo in stride(from: -180.0, through: 180, by: 6) { let o = S(ProveBriefing.versore(lat, lo), 1); if let q { F.metti(o.z + q.z > 0 ? 1 : 0, q, o) }; q = o }
        }
        for lo in stride(from: -180.0, to: 180, by: 30) {
            var q: P3?
            for lat in stride(from: -84.0, through: 84, by: 6) { let o = S(ProveBriefing.versore(lat, lo), 1); if let q { F.metti(o.z + q.z > 0 ? 1 : 0, q, o) }; q = o }
        }
        // il terminatore: il cerchio dove il Sole tramonta
        let l = max(1e-9, hypot(sole.y, sole.x)), U = P3(sole.y / l, -sole.x / l, 0)
        let V2 = P3(sole.y * U.z - sole.z * U.y, sole.z * U.x - sole.x * U.z, sole.x * U.y - sole.y * U.x)
        do {
            var q: P3?
            for i in 0...120 {
                let a = Double(i) / 120 * OP.due, o = S(U * cos(a) + V2 * sin(a), 1.004)
                if let q { F.metti(o.z + q.z > 0 ? 4 : 1, q, o) }
                q = o
            }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.75) : OP.c(0.05 + 0.12 * Double($0)) },
                spessore: { $0 == 4 ? 1.4 : 0.7 + Double($0) * 0.1 }, alone: { $0 == 4 ? OP.s(0.07) : nil })
        // le terre: davanti accese (il giorno più chiaro della notte), dietro appena (si vede attraverso); a gruppi di luce
        var dietro = Path()
        var giorno = Array(repeating: Path(), count: 10), notte = Array(repeating: Path(), count: 10)
        let lato = piccolo ? 0.9 : 1.4
        for v in piccolo ? ProveBriefing.mappa.polso : ProveBriefing.mappa.terra {
            let o = S(v, 1)
            if o.z < -0.05 { if !piccolo { dietro.addRect(CGRect(x: o.x - 0.5, y: o.y - 0.5, width: 1, height: 1)) }; continue }
            let g = dot(v, sole) > 0, a = (g ? 0.85 : 0.32) * (0.45 + 0.55 * min(1, o.z * 1.6 + 0.2))
            let k = max(0, min(9, Int(a * 10)))
            let r = CGRect(x: o.x - lato / 2, y: o.y - lato / 2, width: lato, height: lato)
            if g { giorno[k].addRect(r) } else { notte[k].addRect(r) }
        }
        gc.fill(dietro, with: .color(OP.s(0.05)))
        for k in 0..<10 {
            let a = (Double(k) + 0.5) / 10
            if !giorno[k].isEmpty { gc.fill(giorno[k], with: .color(OP.b(a))) }
            if !notte[k].isEmpty { gc.fill(notte[k], with: .color(OP.c(a))) }
        }
        // il bordo del globo
        gc.stroke(Path(ellipseIn: CGRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R)), with: .color(OP.s(0.45)), lineWidth: 1)
        // il Sole, fuori dal globo nella sua direzione
        let ps = S(sole, 1.3), sdav = ps.z > -0.2
        if sdav && !piccolo {
            OP.alone(&gc, ps.x, ps.y, 18, 0.5, bianco: true)
            var s = Path(ellipseIn: CGRect(x: ps.x - 4, y: ps.y - 4, width: 8, height: 8))
            for i in 0..<8 { let a = Double(i) / 8 * OP.due + t * 0.5; Olo.linea(&s, ps.x + cos(a) * 6, ps.y + sin(a) * 6, ps.x + cos(a) * 9, ps.y + sin(a) * 9) }
            gc.stroke(s, with: .color(OP.b(0.9)), lineWidth: 1)
            M.zona(ps.x, ps.y, 16, 2)
        }
        // il posto: il punto, l'onda e il faro con i gradi
        let mi = ProveBriefing.versore(B.lat, B.lon), pm = S(mi, 1), pt = S(mi, piccolo ? 1.15 : 1.32), vis = pm.z > 0
        if vis {
            let w = t.truncatingRemainder(dividingBy: 1.8) / 1.8, rr = 3 + 13 * w
            gc.stroke(Olo.ellisse(pm.x, pm.y, rr, rr * 0.6), with: .color(OP.b(0.8 * (1 - w))), lineWidth: 1)
            var faro = Path()
            Olo.linea(&faro, pm.x, pm.y, pt.x, pt.y)
            gc.stroke(faro, with: .linearGradient(Gradient(colors: [OP.b(0.9), OP.b(0)]), startPoint: CGPoint(x: pm.x, y: pm.y), endPoint: CGPoint(x: pt.x, y: pt.y)), lineWidth: 1.6)
            OP.alone(&gc, pm.x, pm.y, piccolo ? 5 : 10, 0.9, bianco: true)
            gc.fill(Path(CGRect(x: pm.x - 1.5, y: pm.y - 1.5, width: 3, height: 3)), with: .color(OP.b(1)))
            if !piccolo {
                OP.dentro(&gc, W, B.gradi.map { "\(B.luogo) \($0)°" } ?? B.luogo, pt.x, pt.y - 4, 8, 700, OP.b(0.95))
                OP.dentro(&gc, W, hm(ora), pt.x, pt.y + 6, 6.5, 600, OP.c(0.8))
                M.zona(pm.x, pm.y, 18, 1)
            }
        }
        guard !piccolo else { return }
        let elev = asin(max(-1, min(1, dot(mi, sole)))) * 180 / .pi, luce = B.tramonto - B.alba
        // a sinistra il posto e il meteo, a destra alba e tramonto: se il nome del posto e il cielo sono lunghi («Parzialmente
        // nuvoloso»), prima si toglie il cielo, poi si accorcia il nome, così le due scritte non si toccano mai
        let destra = "ALBA \(Olo.ora(B.alba)) · TRAMONTO \(Olo.ora(B.tramonto))"
        let spazio = W - 28 - OP.larghezza(gc, destra, 8, 700)
        let gradi = B.gradi.map { " · \($0)°" } ?? ""
        let tutto = B.cielo.isEmpty ? "\(B.luogo)\(gradi)" : "\(B.luogo)\(gradi) \(B.cielo.uppercased())"
        let prove: [String] = [tutto, "\(B.luogo)\(gradi)"]
        var sinistra = prove.first { OP.larghezza(gc, $0, 8, 600) <= spazio } ?? ""
        if sinistra.isEmpty {
            var n = B.luogo.count
            repeat { n -= 1; sinistra = String(B.luogo.prefix(max(1, n))) + "…" + gradi } while n > 3 && OP.larghezza(gc, sinistra, 8, 600) > spazio
        }
        OP.scritta(&gc, sinistra, 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, destra, W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        OP.scritta(&gc, "LUCE \(OP.fra(luce)) · SOLE \(Int(elev.rounded()))°", W - 10, 25, 7, 600, OP.c(0.7), .trailing)
        if M.scelta == 1 && vis {
            var righe = [B.gradi.map { "\(B.luogo) · \($0)°" } ?? B.luogo]
            let partiSotto: [String?] = [B.cielo.isEmpty ? nil : B.cielo.uppercased(), B.massima.map { "MAX \($0)°" }]
            let sotto = partiSotto.compactMap { $0 }.joined(separator: " · ")
            if !sotto.isEmpty { righe.append(sotto) }
            righe.append("ALBA \(Olo.ora(B.alba)) · TRAMONTO \(Olo.ora(B.tramonto))")
            OP.riquadro(&gc, W, H, pm.x, pm.y, righe, t - M.sceltaT, codice: B.coordinate)
        } else if M.scelta == 2 && sdav {
            let tra = B.tramonto - ora
            OP.riquadro(&gc, W, H, ps.x, ps.y, ["SOLE", "ALTO \(Int(elev.rounded()))° SU \(B.luogo)", tra > 0 ? "TRAMONTO TRA \(OP.fra(tra))" : "ALBA ALLE \(Olo.ora(B.alba))"],
                        t - M.sceltaT, codice: "POSIZIONE ADESSO")
        }
    }

    // MARK: B3 · PISTA — la giornata come la pista di volo dell'HUD di Iron Man: adesso è sotto di noi, avanti arrivano le ore, ognuna con
    // la sua porta di luce; gli impegni sono fari alti sulla pista, col nome e l'ora (il prossimo il più chiaro). Il tratto del giorno è
    // chiaro, la notte scura; sulla pista la riga del tramonto. Il dito di lato fa scorrere il tempo avanti e indietro.

    private func pista(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BriefingOlo, _ ora: Double, _ piccolo: Bool) {
        let vista = max(0, min(1439, ora + (-M.dx * 1.6).rounded())), cx = W / 2, oriz = H * 0.34, f = H * 0.62
        let S = { (X: Double, Zh: Double, Y: Double) -> P3 in
            let z = max(0.06, 0.26 + Zh * 0.235)
            return P3(cx + X / z * f * 0.32, oriz + (0.62 - Y) / z * f * 0.3, z)
        }
        let Zm = { (m: Double) -> Double in (m - vista) / 60 }
        let w = 0.72
        var F = FasciOlo(6)
        // l'orizzonte e le stelle
        if !piccolo { OP.stelle(&gc, W, H, t, 26, 517, alto: 0.3, forza: 0.7) }
        var orizzonte = Path()
        Olo.linea(&orizzonte, 0, oriz, W, oriz)
        gc.stroke(orizzonte, with: .color(OP.s(0.35)), lineWidth: 1)
        // la pista: il giorno più chiaro, la notte più scura (a strisce di 15 minuti)
        var m = ((vista - 30) / 15).rounded(.down) * 15
        while m < vista + 14 * 60 {
            let z0 = Zm(m), z1 = Zm(m + 15)
            if z1 >= -0.5 {
                let g = m >= B.alba && m < B.tramonto
                gc.fill(OP.poligono([S(-w, z0, 0), S(w, z0, 0), S(w, z1, 0), S(-w, z1, 0)]), with: .color(OP.s((g ? 0.1 : 0.03) / max(1, z0 * 0.4 + 1))))
            }
            m += 15
        }
        F.metti(3, S(-w, -0.5, 0), S(-w, 14, 0)); F.metti(3, S(w, -0.5, 0), S(w, 14, 0))
        // la riga in mezzo, che corre verso di noi (il tempo che passa)
        let fr = (t * 0.5).truncatingRemainder(dividingBy: 1)
        for k in -1..<28 { let z = Double(k) * 0.5 - fr * 0.5; if z >= -0.5 { F.metti(1, S(0, z, 0), S(0, z + 0.2, 0)) } }
        // le porte delle ore, con l'ora scritta di lato
        let h0 = Int((vista / 60).rounded(.up)), h1 = min(24, Int(vista / 60) + 14)
        if h0 <= h1 {
            for h in h0...h1 {
                let z = Zm(Double(h) * 60)
                if z < -0.3 { continue }
                let g = z < 3 ? 3 : z < 7 ? 2 : 1
                var q: P3?
                for i in 0...16 { let a = Double.pi * Double(i) / 16, o = S(-cos(a) * w, z, 0.15 + sin(a) * 0.55); if let q { F.metti(g, q, o) }; q = o }
                F.metti(g - 1, S(-w, z, 0), S(-w, z, 0.15)); F.metti(g - 1, S(w, z, 0), S(w, z, 0.15))
                if !piccolo {
                    let et = S(-w - 0.08, z, 0.15)
                    OP.scritta(&gc, String(format: "%02d", h % 24), et.x, et.y, max(5.5, 9 - z * 0.5), 700, OP.c(max(0.25, 0.85 - z * 0.06)), .trailing)
                }
            }
        }
        // l'alba e il tramonto sulla pista: la riga di traverso e il nome
        var righe: [(p: P3, s: String, z: Double)] = []
        let luce: [(m: Double, nome: String)] = [(B.alba, "ALBA"), (B.tramonto, "TRAMONTO")]
        for l in luce {
            let z = Zm(l.m)
            if z < -0.3 || z > 13 { continue }
            F.metti(4, S(-w * 1.25, z, 0), S(w * 1.25, z, 0))
            righe.append((p: S(w * 1.25, z, 0), s: "\(l.nome) \(Olo.ora(l.m))", z: z))
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.1 + 0.17 * Double($0)) },
                spessore: { 0.8 + Double($0) * 0.15 }, alone: { $0 >= 3 ? OP.s(0.06) : nil })
        // i fari degli impegni
        let prossimo = B.impegni.first { $0.m > ora }
        for (i, e) in B.impegni.enumerated() {
            let z = Zm(e.m)
            if z < -0.45 || z > 14 { continue }
            let prox = prossimo?.m == e.m, passato = e.m < ora, p0 = S(0, z, 0), p1 = S(0, z, 1.25)
            let col = prox ? OP.rgbB : OP.rgbC
            var faro = Path()
            Olo.linea(&faro, p0.x, p0.y, p1.x, p1.y)
            gc.stroke(faro, with: .linearGradient(Gradient(colors: [col.opacity(passato ? 0.35 : 0.9), col.opacity(0)]),
                                                 startPoint: CGPoint(x: p0.x, y: p0.y), endPoint: CGPoint(x: p1.x, y: p1.y)), lineWidth: max(1.2, 3 - z * 0.15))
            let w2 = t.truncatingRemainder(dividingBy: 1.4) / 1.4, rr = S(0.4 * w2, z, 0), rx = abs(rr.x - p0.x) + 2
            gc.stroke(Olo.ellisse(p0.x, p0.y, rx, rx * 0.28), with: .color(prox ? OP.b(0.9 * (1 - w2)) : OP.c(0.6 * (1 - w2))), lineWidth: 1)
            OP.alone(&gc, p0.x, p0.y, piccolo ? 6 : 12, 0.7, bianco: prox)
            if piccolo { continue }
            let et = S(0.1, z, 0.95)
            OP.dentro(&gc, W, "\(Olo.ora(e.m)) \(e.corto)", et.x + 4, et.y, max(6, 8.5 - z * 0.3), 700, prox ? OP.b(1) : passato ? OP.c(0.5) : OP.c(0.85), .leading)
            M.zona(p0.x, (p0.y + p1.y) / 2, 18, i)
        }
        if !piccolo { for r in righe { OP.dentro(&gc, W, r.s, r.p.x + 4, r.p.y + 3, max(6, 8 - r.z * 0.3), 700, OP.b(0.85), .leading) } }
        // adesso: il segno sotto di noi
        let zn = Zm(ora), n0 = S(0, zn, 0), kn = piccolo ? 0.55 : 1.0              // sul polso il segno più piccolo
        if zn > -0.45 {
            var tri = Path()
            tri.move(to: CGPoint(x: n0.x, y: n0.y - 5 * kn)); tri.addLine(to: CGPoint(x: n0.x + 6 * kn, y: n0.y + 3 * kn))
            tri.addLine(to: CGPoint(x: n0.x - 6 * kn, y: n0.y + 3 * kn)); tri.closeSubpath()
            gc.fill(tri, with: .color(OP.b(0.95)))
            OP.alone(&gc, n0.x, n0.y, 14 * kn, 0.6, bianco: true)
        }
        guard !piccolo else { return }
        let diff = vista - ora
        OP.scritta(&gc, abs(diff) < 0.5 ? "ADESSO \(hm(ora))" : "\(diff > 0 ? "+" : "−")\(OP.fra(abs(diff))) · \(hm(vista))", 10, 14, 8, 600, OP.c(0.85), .leading)
        if let p = prossimo { OP.scritta(&gc, "\(p.corto) TRA \(OP.fra(p.m - ora))", W - 10, 14, 8, 700, OP.b(0.95), .trailing) }
        if let k = M.scelta, k < B.impegni.count {
            let e = B.impegni[k], z = Zm(e.m)
            if z > -0.45 && z <= 14 {
                let p = S(0, z, 0.6)
                OP.riquadro(&gc, W, H, p.x, p.y, [e.nome.uppercased(), "ORE \(Olo.ora(e.m))", e.m > ora ? "TRA \(OP.fra(e.m - ora))" : "GIÀ PASSATO"],
                            t - M.sceltaT, codice: "IMPEGNO \(k + 1)/\(B.impegni.count)")
            }
        }
    }
}

/// L'ologramma della giornata con le sue tre prove (iPhone: grande, con le chip; polso: piccolo, la prova scelta sull'iPhone).
struct OlogrammaBriefingProve: View {
    let dati: BriefingOlo
    var piccolo = false
    @State private var prove = ProveBriefing()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .briefing) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .briefing, altezza: 280, crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
