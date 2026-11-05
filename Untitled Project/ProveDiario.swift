import Foundation
import SwiftUI

// MARK: - DIARIO · le tre prove (mockup v262–v264): ELICA, RILIEVO, ORBITA

/// Una sera del diario: l'umore (1-10), l'energia, l'umore in parole, la pagina e i temi; `oggi` è stasera.
struct SeraDiario {
    var d: Date
    var v: Int?
    var e: Int?
    var u: String?
    var p: String?
    var temi: [String]
    var oggi: Bool
}

/// Le ultime 20 sere e oggi (come il mockup); `scritta` = la pagina di oggi c'è.
struct DiarioOlo {
    var giorni: [SeraDiario] = []
    var scritta = false

    init() {}

    /// Dalle pagine (giorno, umore, energia, umore in parole, testo, temi): una sera per ognuno degli ultimi 20 giorni e oggi.
    init(pagine: [(giorno: Date, v: Int?, e: Int?, u: String?, p: String?, temi: [String])]) {
        let cal = Calendar.current, oggi = cal.startOfDay(for: Date())
        var perGiorno: [Date: (giorno: Date, v: Int?, e: Int?, u: String?, p: String?, temi: [String])] = [:]
        for x in pagine { perGiorno[cal.startOfDay(for: x.giorno)] = x }
        giorni = (0...20).reversed().map { k -> SeraDiario in
            let g = cal.date(byAdding: .day, value: -k, to: oggi) ?? oggi
            let x = perGiorno[g]
            let mezzogiorno = cal.date(byAdding: .hour, value: 12, to: g) ?? g
            return SeraDiario(d: mezzogiorno, v: x?.v, e: x?.e, u: x?.u, p: x?.p, temi: (x?.temi ?? []).map { $0.uppercased() }, oggi: k == 0)
        }
        scritta = perGiorno[oggi] != nil
    }

    var media: Double {
        let v = giorni.compactMap(\.v)
        return v.isEmpty ? 0 : Double(v.reduce(0, +)) / Double(v.count)
    }

    /// righeGiornoOlo: le righe del riquadro di una sera.
    static func righe(_ g: SeraDiario) -> [String] {
        guard let v = g.v else { return ["\(OP.giorno(g.d)) · —", g.oggi ? "STASERA, DA SCRIVERE" : "NESSUNA PAGINA"] }
        let p = g.p ?? ""
        let corta = p.count > 34 ? String(p.prefix(33)) + "…" : p
        return ["\(OP.giorno(g.d)) · \(v)/10", "\((g.u ?? "").uppercased()) · ENERGIA \(g.e.map { String($0) } ?? "—")", "«\(corta)»"]
    }
}

/// Le tre prove del diario, ognuna col suo stato.
final class ProveDiario {
    private var fuori: [Double] = []           // ELICA: quanto è uscita ogni pagina (la scelta esce verso chi guarda)
    private var penna: Double?                 // ELICA: quando la penna ha cominciato a scrivere la pagina di oggi

    func crea(_ k: Int) { fuori = []; penna = nil }

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ d: DiarioOlo, piccolo: Bool) {
        guard d.giorni.count >= 2 else { return }
        switch k {
        case 1: rilievo(&gc, W, H, t, M, d, piccolo)
        case 2: orbita(&gc, W, H, t, M, d, piccolo)
        default: elica(&gc, W, H, t, M, d, piccolo)
        }
    }

    // MARK: D1 · ELICA — le sere come pagine su una doppia elica che gira (un archivio di Stark): in basso le più vecchie, in cima oggi.
    // Due filamenti di luce salgono attorno all'asse, legati da un gradino per sera; ogni pagina pende dal suo gradino, con la barra
    // dell'umore sul bordo. Toccata, esce verso chi guarda e si apre il riquadro col giorno, l'umore e la pagina.

    private static let R = 1.0, hw = 0.3, hh = 0.2, passoA = 0.7, z0 = -0.85, z1 = 0.85, Rg = 0.62, al = 0.18
    private static let zg = z0 - hh - 0.14
    /// Quanto sale e quanto scende il disegno (a misura 1), per ogni giro: così tutto sta nella tela, anche girando.
    private static let misure: (su: Double, giu: Double) = {
        var su = 0.0, giu = 0.0
        var a = 0.0
        let casi: [(Double, Double)] = [(hypot(R, hw), z1 + hh), (0, z1 + 0.3), (Rg + 0.09, zg), (hypot(R, hw), z0 - hh)]
        while a < OP.due {
            for (r, z) in casi {
                let o = Olo.proietta(cos(a) * r, sin(a) * r, z, 0, al, 0, 0, 1)
                su = max(su, -o.y); giu = max(giu, o.y)
            }
            a += 0.04
        }
        return (su, giu)
    }()

    private func elica(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ d: DiarioOlo, _ piccolo: Bool) {
        let G = Array(d.giorni.suffix(14)), n = G.count
        if d.scritta && penna == nil { penna = t }
        if fuori.count < n { fuori += Array(repeating: 0, count: n - fuori.count) }
        let S = ProveDiario.self
        let base = piccolo ? H - 3 : H - 12, rx = piccolo ? W * 0.3 : min(W * 0.17, 62), ry = rx * 0.17
        let cima = piccolo ? 2.0 : 30.0, fondo = base - ry - (piccolo ? 2 : 8)
        let sz = min(W * 0.24, (fondo - cima) / (S.misure.su + S.misure.giu)), cx = W / 2, cy = cima + S.misure.su * sz, ang = t * 0.2 + M.giro
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, S.al, cx, cy, sz) }
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 40)
        let fondoGhiera = P(0, 0, S.zg).y
        Olo.cono(&gc, cx, base, rx, cy - sz * 0.9, sz * 1.45, a: 0.07)
        OP.alone(&gc, cx, cy, sz * 1.8, 0.06)
        var asse = Path()
        Olo.linea(&asse, cx, base - ry * 0.4, cx, fondoGhiera)
        gc.stroke(asse, with: .color(OP.s(0.25)), lineWidth: 1)
        var F = FasciOlo(6)
        let zi = { (i: Int) -> Double in S.z0 + (S.z1 - S.z0) * Double(i) / Double(max(1, n - 1)) }
        // l'asse e i due filamenti che salgono (la doppia elica), con un gradino per sera
        F.metti(1, P(0, 0, S.zg), P(0, 0, S.z1 + 0.22))
        var qa: P3?, qb: P3?
        for s in 0...((n - 1) * 10) {
            let u = Double(s) / 10, a = u * S.passoA, z = S.z0 + (S.z1 - S.z0) * u / Double(max(1, n - 1))
            let pa = P(cos(a) * 0.34, sin(a) * 0.34, z), pb = P(cos(a + .pi) * 0.34, sin(a + .pi) * 0.34, z)
            if let qa, let qb {
                F.metti(pa.z + qa.z < 0 ? 3 : 1, qa, pa)
                F.metti(pb.z + qb.z < 0 ? 2 : 0, qb, pb)
            }
            qa = pa; qb = pb
        }
        OP.ghiera(&F, { a, r, z in P(cos(a) * r, sin(a) * r, z) }, S.Rg, S.zg, 60, 5, lunga: 0.1, corta: 0.05)
        // le pagine
        var centri: [(x: Double, y: Double, i: Int)] = []
        for (i, g) in G.enumerated() {
            let a = Double(i) * S.passoA, z = zi(i), ca = cos(a), sa = sin(a)
            fuori[i] += ((M.scelta == i ? 1 : 0) - fuori[i]) * (1 - exp(-M.dt * 9))
            let f = fuori[i], Rr = S.R + 0.4 * f
            let c = P(ca * Rr, sa * Rr, z), dav = c.z < 0
            // il gradino: dall'altro filamento, attraverso l'asse, fino alla pagina
            F.metti(0, P(-ca * 0.34, -sa * 0.34, z), P(ca * 0.34, sa * 0.34, z))
            F.metti(dav ? 2 : 0, P(ca * 0.34, sa * 0.34, z), P(ca * (Rr - 0.02), sa * (Rr - 0.02), z))
            // gli angoli della pagina: sull'elica (tangente) o, uscita, dritta verso chi guarda e più grande
            let tx = -sa, ty = ca
            let uv: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            let angoli: [P3] = uv.map { (u, v) -> P3 in
                let p = P(ca * Rr + tx * S.hw * u, sa * Rr + ty * S.hw * u, z + S.hh * v)
                let kk = 1 + 0.9 * f, fx = c.x + u * S.hw * sz * kk, fy = c.y - v * S.hh * sz * kk
                return P3(p.x + (fx - p.x) * f, p.y + (fy - p.y) * f, p.z)
            }
            // il vetro della pagina (davanti un filo più chiaro)
            gc.fill(OP.poligono(angoli), with: .color(OP.s(dav ? 0.05 + 0.06 * f : 0.02)))
            let lum = (g.v ?? 0) >= 7 ? 1 : 0, gp = (dav ? 3 : 1) + lum + (f > 0.5 ? 1 : 0)
            let tratteggio = g.oggi && !d.scritta
            if !tratteggio { for j in 0..<4 { F.metti(gp, angoli[j], angoli[(j + 1) % 4]) } }
            // le righe della pagina (oggi: quelle scritte dalla penna) e la barra dell'umore sul bordo
            let A = angoli[0], B = angoli[1], C = angoli[3]
            let pt = { (u: Double, v: Double) -> P3 in P3(A.x + (B.x - A.x) * u + (C.x - A.x) * v, A.y + (B.y - A.y) * u + (C.y - A.y) * v, 0) }
            var righe = g.v == nil ? 0 : 3
            var fino = 1.0
            if g.oggi { righe = d.scritta ? 3 : 0; fino = penna.map { max(0, (t - $0) / 2.4) * 3 } ?? 1 }
            for r in 0..<righe {
                let pr = min(1, max(0, fino - Double(r)))
                if pr <= 0 { break }
                let L = 0.55 + 0.3 * OP.caso(i * 7 + r), v = 0.28 + Double(r) * 0.22
                let a1 = pt(0.22, v), b1 = pt(0.22 + (L - 0.22) * pr, v)
                F.metti(gp - 1, a1, b1)
                if g.oggi && pr < 1 { OP.alone(&gc, b1.x, b1.y, 9, 0.8, bianco: true) }
            }
            if let v = g.v { F.metti(min(5, gp + 1), pt(0.08, 0.92), pt(0.08, 0.92 - 0.84 * Double(v) / 10)) }
            if tratteggio && !piccolo {                                   // oggi da scrivere: il bordo tratteggiato e il cursore
                gc.stroke(OP.poligono(angoli), with: .color(OP.c(0.75)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if sin(t * 5.7) > 0 {
                    var cur = Path()
                    let c0 = pt(0.22, 0.25), c1 = pt(0.22, 0.55)
                    Olo.linea(&cur, c0.x, c0.y, c1.x, c1.y)
                    gc.stroke(cur, with: .color(OP.b(0.95)), lineWidth: 1.5)
                }
            }
            centri.append((c.x, c.y, i))
            if piccolo { continue }
            M.zona(c.x, c.y, 20 + 14 * f, i)
            if dav && f < 0.3 && !tratteggio {
                let giorno = Calendar.current.component(.day, from: g.d)
                OP.scritta(&gc, String(giorno), max(angoli[1].x, angoli[2].x) + 4, (angoli[1].y + angoli[2].y) / 2 + 3, 7.5, 600,
                           OP.c(0.35 + 0.45 * min(1, -c.z)), .leading)
            }
            if tratteggio {                                                // STASERA fuori dalla pagina, dal lato libero
                let xs = angoli.map(\.x), sx = c.x < cx
                OP.scritta(&gc, "STASERA", sx ? (xs.min() ?? c.x) - 5 : (xs.max() ?? c.x) + 5, c.y + 3, 7, 700, OP.b(0.9), sx ? .trailing : .leading)
            }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.06 + 0.15 * Double($0)) },
                spessore: { 0.8 + Double($0) * 0.13 }, alone: { $0 >= 4 ? OP.s(0.07) : nil })
        // la cima: oggi
        let top = P(0, 0, S.z1 + 0.22)
        OP.alone(&gc, top.x, top.y, piccolo ? 6 : 14, 0.5 + 0.3 * sin(t * 3), bianco: true)
        guard !piccolo else { return }
        let media = Olo.numero(DiarioOlo(giorniDi: G).media, decimali: 1)
        OP.scritta(&gc, "DIARIO · \(n) SERE", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, "MEDIA \(media)", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if let s = M.scelta, s < n, let c = centri.first(where: { $0.i == s }) {
            OP.riquadro(&gc, W, H, c.x, c.y, DiarioOlo.righe(G[s]), t - M.sceltaT, codice: "PAGINA \(s + 1)/\(n)")
        }
    }

    // MARK: D2 · RILIEVO — l'umore come una catena di montagne di luce: la cresta è l'umore di ogni sera (alta = bene), dietro la catena
    // più bassa dell'energia. Un velo di scansione la percorre; oggi è un faro. Toccata una vetta, il riquadro della sera.

    private func rilievo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ d: DiarioOlo, _ piccolo: Bool) {
        let G = d.giorni, n = G.count
        let cx = W / 2, cy = H * (piccolo ? 0.6 : 0.64), sz = piccolo ? W * 0.27 : min(W * 0.255, H * 0.46)
        let ang = -0.32 + 0.2 * sin(t * 0.18) + M.giro, al = 0.5
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let X = { (i: Int) -> Double in -1.4 + 2.8 * Double(i) / Double(n - 1) }
        // i valori riempiti dove manca la pagina (per la forma), e la curva liscia fra un giorno e l'altro
        let riempi = { (val: (SeraDiario) -> Int?) -> [Double] in
            G.indices.map { i -> Double in
                if let x = val(G[i]) { return Double(x) }
                var a = i - 1, b = i + 1
                while a >= 0 && val(G[a]) == nil { a -= 1 }
                while b < n && val(G[b]) == nil { b += 1 }
                let va: Double? = a >= 0 ? val(G[a]).map { Double($0) } : nil
                let vb: Double? = b < n ? val(G[b]).map { Double($0) } : nil
                if let va, let vb { return va + (vb - va) * Double(i - a) / Double(b - a) }
                return va ?? vb ?? 5
            }
        }
        let um = riempi { $0.v }, en = riempi { $0.e }
        let liscia = { (A: [Double], u: Double) -> Double in
            let i = max(0, min(n - 2, Int(u.rounded(.down)))), f = u - Double(i)
            let p0 = A[max(0, i - 1)], p1 = A[i], p2 = A[i + 1], p3 = A[min(n - 1, i + 2)]
            let c1 = (-p0 + p2) * f, c2 = (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f, c3 = (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f
            return 0.5 * (2 * p1 + c1 + c2 + c3)
        }
        let cresce = OP.lis(t / 1.1)
        var F = FasciOlo(6)
        // il pavimento: la griglia del piano
        for j in -3...6 { let y = Double(j) * 0.2; F.metti(j == 0 ? 1 : 0, P(-1.52, y, 0), P(1.52, y, 0)) }
        for i in stride(from: 0, to: n, by: 2) { F.metti(0, P(X(i), -0.6, 0), P(X(i), 1.25, 0)) }
        // le due catene: la sezione è una campana, più file di quote danno il volume
        let catena = { (F: inout FasciOlo, A: [Double], y0: Double, h: Double, larg: Double, g0: Int) -> Void in
            for j in -4...4 {
                let y = Double(j) * larg / 3.2, s = exp(-pow(Double(j) / 2.2, 2))
                var q: P3?
                for kk in 0...((n - 1) * 4) {
                    let u = Double(kk) / 4, z = h * liscia(A, u) / 10 * s * cresce, o = P(-1.4 + 2.8 * u / Double(n - 1), y0 + y, z)
                    if let q { F.metti(g0 + (j == 0 ? 2 : abs(j) <= 1 ? 1 : 0) + (o.z < -0.2 ? 1 : 0), q, o) }
                    q = o
                }
            }
            for i in 0..<n {                                              // le coste: da una fila all'altra, a ogni sera
                var q: P3?
                for j in -4...4 {
                    let y = Double(j) * larg / 3.2, s = exp(-pow(Double(j) / 2.2, 2)), o = P(X(i), y0 + y, h * A[i] / 10 * s * cresce)
                    if let q { F.metti(g0, q, o) }
                    q = o
                }
            }
        }
        catena(&F, en, 0.85, 0.55, 0.32, 0)
        catena(&F, um, 0, 0.95, 0.38, 1)
        // il velo di scansione che percorre le sere
        let sx = -1.55 + 3.1 * (t * 0.22).truncatingRemainder(dividingBy: 1)
        OP.lama(&gc, &F, P, (sx, -0.6), (sx, 1.25), 1.0)
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.65) : OP.c(0.07 + 0.15 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.14 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        // le vette: un punto per sera (vuoto se manca la pagina); acceso quando passa la scansione
        let voti = G.compactMap(\.v), vmax = voti.max() ?? -1, vmin = voti.min() ?? 11
        for (i, g) in G.enumerated() {
            let o = P(X(i), 0, 0.95 * um[i] / 10 * cresce), vicino = exp(-pow((X(i) - sx) / 0.12, 2))
            if g.v == nil {
                gc.stroke(Path(ellipseIn: CGRect(x: o.x - 2.4, y: o.y - 2.4, width: 4.8, height: 4.8)), with: .color(OP.c(0.6)), lineWidth: 1)
            } else {
                if vicino > 0.05 { OP.alone(&gc, o.x, o.y, 12, 0.7 * vicino, bianco: true) }
                let r = 1.9 + vicino
                gc.fill(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r)), with: .color(OP.b(0.75 + 0.25 * vicino)))
            }
            if piccolo { continue }
            M.zona(o.x, o.y, 14, i)
            let piede = P(X(i), -0.75, 0)
            OP.scritta(&gc, OP.lettera(g.d), piede.x, piede.y + 3, 6.5, 600, g.oggi ? OP.b(0.95) : OP.c(0.55))
            if let v = g.v, v == vmax || v == vmin || vicino > 0.4 || i == n - 2 { OP.scritta(&gc, String(v), o.x, o.y - 7, 8, 700, OP.b(0.9)) }
        }
        // oggi: il faro
        let og = G[n - 1], f0 = P(X(n - 1), 0, 0), f1 = P(X(n - 1), 0, og.v.map { 0.95 * Double($0) / 10 + 0.45 } ?? 1.15)
        var faro = Path()
        Olo.linea(&faro, f0.x, f0.y, f1.x, f1.y)
        gc.stroke(faro, with: .linearGradient(Gradient(colors: [OP.b(0.7), OP.b(0)]), startPoint: CGPoint(x: f0.x, y: f0.y), endPoint: CGPoint(x: f1.x, y: f1.y)),
                  lineWidth: 2.2)
        let pulsa = t.truncatingRemainder(dividingBy: 1.6) / 1.6, rr = 4 + 16 * pulsa
        gc.stroke(Olo.ellisse(f0.x, f0.y, rr, rr * 0.45), with: .color(OP.c(0.8 * (1 - pulsa))), lineWidth: 1)
        guard !piccolo else { return }
        OP.dentro(&gc, W, og.v.map { "OGGI · \($0)" } ?? "OGGI · STASERA", f1.x, f1.y - 4, 7, 700, OP.b(0.95))
        let et = P(-1.48, 0.85, 0.3)
        OP.scritta(&gc, "ENERGIA", et.x - 4, et.y, 7, 600, OP.s(0.7), .trailing)
        OP.scritta(&gc, "UMORE · \(n - 1) SERE", 10, 14, 8, 600, OP.c(0.85), .leading)
        let mm = voti.isEmpty ? "—" : Olo.numero(d.media, decimali: 1)
        OP.scritta(&gc, voti.isEmpty ? "MEDIA —" : "MEDIA \(mm) · MAX \(vmax) · MIN \(vmin)", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if let s = M.scelta, s < n {
            let o = P(X(s), 0, 0.95 * um[s] / 10 * cresce)
            OP.riquadro(&gc, W, H, o.x, o.y, DiarioOlo.righe(G[s]), t - M.sceltaT, codice: "SERA \(s + 1)/\(n)")
        }
    }

    // MARK: D3 · ORBITA — come Tracktor: le sere su un anello radiale che gira attorno al nucleo del diario. Più l'umore è alto, più il
    // punto è lontano dal centro: il contorno è la forma del mese. Fuori girano i temi: toccato un tema, si accendono le sue sere.

    /// Il cristallo del nucleo: un icosaedro (12 vertici, i 30 spigoli).
    private static let ico: (V: [P3], S: [(Int, Int)]) = {
        let f = (1 + 5.0.squareRoot()) / 2
        let V0: [P3] = [P3(-1, f, 0), P3(1, f, 0), P3(-1, -f, 0), P3(1, -f, 0), P3(0, -1, f), P3(0, 1, f), P3(0, -1, -f), P3(0, 1, -f),
                        P3(f, 0, -1), P3(f, 0, 1), P3(-f, 0, -1), P3(-f, 0, 1)]
        var S: [(Int, Int)] = []
        for i in 0..<12 { for j in (i + 1)..<12 { let d = V0[i] - V0[j]; if (d * d).sum().squareRoot() < 2.1 { S.append((i, j)) } } }
        return (V0.map { $0 / ($0 * $0).sum().squareRoot() }, S)
    }()

    private func orbita(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ d: DiarioOlo, _ piccolo: Bool) {
        let G = d.giorni, n = G.count
        let cx = W / 2, cy = H * (piccolo ? 0.52 : 0.56), sz = piccolo ? W * 0.36 : min(W * 0.34, H * 0.52), ang = t * 0.1 + M.giro, al = 0.95
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let raggio = { (v: Double) -> Double in 0.32 + 0.68 * v / 10 }
        let th = { (i: Int) -> Double in Double(i) / Double(n) * OP.due }
        var conto: [String: Int] = [:]
        for g in G { for m in g.temi { conto[m, default: 0] += 1 } }
        let elenco: [(nome: String, quanti: Int)] = conto.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map { (nome: $0.key, quanti: $0.value) }
        var tema: String?
        if let s = M.scelta, s >= 1000, elenco.indices.contains(s - 1000) { tema = elenco[s - 1000].nome }
        OP.alone(&gc, cx, cy, sz * 1.1, 0.06)
        var F = FasciOlo(6)
        let cresce = OP.lis(t / 1.2)
        // i cerchi di riferimento (umore 5 e 10) con le tacche delle sere, come la ghiera
        OP.ghiera(&F, { a, r, z in P(cos(a) * r, sin(a) * r, z) }, raggio(10), 0, n * 2, 2, lunga: 0.06, corta: 0.03)
        var q: P3?
        for k in 0...72 {
            let a = Double(k) / 72 * OP.due, o = P(cos(a) * raggio(5), sin(a) * raggio(5), 0)
            if let q, k % 2 == 1 { F.metti(1, q, o) }
            q = o
        }
        // i raggi e il contorno del mese
        let punti: [P3] = G.indices.map { i -> P3 in
            let v = Double(G[i].v ?? 5), r = 0.32 + (raggio(v) - 0.32) * cresce
            return P(cos(th(i)) * r, sin(th(i)) * r, G[i].v == nil ? 0 : 0.04)
        }
        let c0 = P(0, 0, 0)
        for (i, g) in G.enumerated() where g.v != nil { F.metti(punti[i].z < 0 ? 2 : 1, c0, punti[i]) }
        for i in 0..<n {
            let a = punti[i], b = punti[(i + 1) % n]
            if G[i].v != nil && G[(i + 1) % n].v != nil { F.metti(a.z + b.z < 0 ? 4 : 3, a, b) }
        }
        // il riempimento della forma
        gc.fill(OP.poligono(punti), with: .color(OP.s(0.07)))
        // il nucleo: un cristallo che gira, pulsa con la media
        let batte = 0.5 + 0.5 * sin(t * 2.4), rn = 0.13 + 0.015 * batte, rot = t * 0.6, cr = cos(rot), sr = sin(rot)
        let V: [P3] = ProveDiario.ico.V.map { v in P((v.x * cr - v.y * sr) * rn, (v.x * sr + v.y * cr) * rn, v.z * rn + 0.16) }
        for (i, j) in ProveDiario.ico.S { F.metti(V[i].z + V[j].z < 0 ? 5 : 3, V[i], V[j]) }
        F.metti(1, P(0, 0, 0), P(0, 0, 0.16))
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.9) : $0 == 4 ? OP.b(0.55) : OP.c(0.07 + 0.15 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.13 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        let nc = P(0, 0, 0.16)
        OP.alone(&gc, nc.x, nc.y, (piccolo ? 10 : 26) + 6 * batte, 0.35 + 0.2 * batte, bianco: true)
        if !piccolo {
            OP.scritta(&gc, Olo.numero(d.media, decimali: 1), nc.x, nc.y + 30, 11, 700, OP.b(1))
            OP.scritta(&gc, "MEDIA", nc.x, nc.y + 39, 6.5, 600, OP.c(0.8))
        }
        // le sere: i punti (oggi pulsa; senza pagina vuoti; col tema scelto accesi)
        for (i, g) in G.enumerated() {
            let p = punti[i], acceso = tema.map { g.temi.contains($0) } ?? false
            if g.v == nil {
                let r = g.oggi ? 3.2 : 2.2
                gc.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                          with: .color(OP.c(g.oggi ? 0.5 + 0.5 * sin(t * 5) : 0.45)), lineWidth: 1)
            } else {
                if acceso { OP.alone(&gc, p.x, p.y, 13, 0.9, bianco: true) }
                let r = acceso ? 2.8 : 2.0
                gc.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                        with: .color(tema != nil && !acceso ? OP.c(0.35) : OP.b(p.z < 0 ? 0.95 : 0.6)))
            }
            if piccolo { continue }
            M.zona(p.x, p.y, 12, i)
            if g.oggi { OP.scritta(&gc, d.scritta ? "OGGI" : "STASERA", p.x, p.y - 7, 7, 700, OP.b(0.95)) }
        }
        guard !piccolo else { return }
        // i temi in orbita, fuori (girano al contrario)
        let angoloTema = { (k: Int) -> Double in Double(k) / Double(max(1, elenco.count)) * OP.due - t * 0.16 - M.giro * 1.6 }
        for (k, e) in elenco.enumerated() {
            let a = angoloTema(k), p = P(cos(a) * 1.22, sin(a) * 1.22, 0.1), dav = p.z < 0.2, scelto = tema == e.nome
            var rombo = Path()
            rombo.move(to: CGPoint(x: p.x, y: p.y - 3.5)); rombo.addLine(to: CGPoint(x: p.x + 3, y: p.y))
            rombo.addLine(to: CGPoint(x: p.x, y: p.y + 3.5)); rombo.addLine(to: CGPoint(x: p.x - 3, y: p.y)); rombo.closeSubpath()
            gc.fill(rombo, with: .color(scelto ? OP.b(1) : OP.c(dav ? 0.85 : 0.4)))
            OP.scritta(&gc, "\(e.nome) \(e.quanti)", p.x, p.y - 7, 7, 700, scelto ? OP.b(1) : OP.c(dav ? 0.85 : 0.45))
            M.zona(p.x, p.y - 4, 16, 1000 + k)
        }
        OP.scritta(&gc, "UMORE · \(n - 1) SERE", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, tema.map { "TEMA \($0)" } ?? "TOCCHI UN TEMA", W - 10, 14, 8, 700, tema != nil ? OP.b(0.95) : OP.c(0.6), .trailing)
        if let s = M.scelta, s < n {
            OP.riquadro(&gc, W, H, punti[s].x, punti[s].y, DiarioOlo.righe(G[s]), t - M.sceltaT, codice: "SERA \(s + 1)/\(n)")
        } else if let tema, let k = elenco.firstIndex(where: { $0.nome == tema }) {
            let sere = G.filter { $0.temi.contains(tema) }, v = sere.compactMap(\.v)
            let m = v.isEmpty ? 0 : Double(v.reduce(0, +)) / Double(v.count)
            let a = angoloTema(k), p = P(cos(a) * 1.22, sin(a) * 1.22, 0.1)
            OP.riquadro(&gc, W, H, p.x, p.y, ["\(tema) · \(sere.count) SERE", "UMORE MEDIO \(Olo.numero(m, decimali: 1))"], t - M.sceltaT, codice: "TEMA")
        }
    }
}

extension DiarioOlo {
    /// Per la media di una parte delle sere (ELICA: le ultime 14).
    init(giorniDi g: [SeraDiario]) { self.init(); giorni = g }
}

/// L'ologramma del diario con le sue tre prove (iPhone: grande, con le chip; polso: piccolo, la prova scelta sull'iPhone).
struct OlogrammaDiarioProve: View {
    let dati: DiarioOlo
    var piccolo = false
    @State private var prove = ProveDiario()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .diario) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .diario, altezza: 280, crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
