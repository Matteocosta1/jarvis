import Foundation
import SwiftUI

// MARK: - SONNO · le tre prove (mockup v262–v264): ONDA, CICLI, NOTTI

/// La notte come il mockup: le fasi in minuti dall'addormentarsi, l'ora d'inizio e le ultime notti (ore; profondo e REM se si sanno).
struct SonnoOlo {
    /// `tipo`: 0 sveglio, 1 REM, 2 core, 3 profondo.
    struct Fase { let tipo: Int; let a: Double; let b: Double }
    struct Notte { let d: Date; let ore: Double; let prof: Double?; let rem: Double?; let stanotte: Bool }

    var fasi: [Fase] = []
    var durata = 0.0
    /// Il minuto del giorno in cui si è addormentato.
    var inizio = 0.0
    var notti: [Notte] = []
    var fine: Double { inizio + durata }

    /// Quanto è profondo il sonno di ogni fase (l'altezza nel disegno) e il suo nome.
    static let alto: [Double] = [0.1, 0.4, 0.64, 1]
    static let nome = ["SVEGLIO", "REM", "CORE", "PROFONDO"]

    init() {}

    /// `fasi`: (da, a, fase) con fase 0 sveglio, 1 REM, 2 core, 3 profondo. `notti`: (giorno, ore dormite), dalla più vecchia.
    init(fasi tratti: [(Date, Date, Int)], notti storico: [(Date, Double)]) {
        let ordinate = tratti.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        if let t0 = ordinate.first?.0, let t1 = ordinate.map(\.1).max() {
            fasi = ordinate.map { Fase(tipo: max(0, min(3, $0.2)), a: $0.0.timeIntervalSince(t0) / 60, b: $0.1.timeIntervalSince(t0) / 60) }
            durata = t1.timeIntervalSince(t0) / 60
            let cal = Calendar.current
            inizio = Double(cal.component(.hour, from: t0) * 60 + cal.component(.minute, from: t0))
        }
        let oggi = Calendar.current.startOfDay(for: Date())
        let prof = fasi.filter { $0.tipo == 3 }.reduce(0) { $0 + $1.b - $1.a }, rem = fasi.filter { $0.tipo == 1 }.reduce(0) { $0 + $1.b - $1.a }
        notti = storico.suffix(14).map { d, ore in
            let st = Calendar.current.isDate(d, inSameDayAs: oggi)
            return Notte(d: d, ore: ore, prof: st && !fasi.isEmpty ? prof : nil, rem: st && !fasi.isEmpty ? rem : nil, stanotte: st)
        }
        if let i = notti.indices.last, !notti.contains(where: \.stanotte) {           // l'ultima è stanotte
            let x = notti[i]
            notti[i] = Notte(d: x.d, ore: x.ore, prof: x.prof, rem: x.rem, stanotte: true)
        }
    }

    /// faseSonnoA: la fase al minuto `m` (fra due fasi: quella prima).
    func fase(_ m: Double) -> Int {
        var t = fasi.last?.tipo ?? 0
        for f in fasi { if m >= f.a { t = f.tipo } ; if m >= f.a && m < f.b { return f.tipo } }
        return t
    }

    /// I minuti di una fase fra `a` e `b`.
    func minuti(_ a: Double, _ b: Double, _ tipo: Int) -> Double {
        fasi.reduce(0) { $0 + ($1.tipo == tipo ? max(0, min(b, $1.b) - max(a, $1.a)) : 0) }
    }
}

/// Le tre prove del sonno.
final class ProveSonno {
    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ N: SonnoOlo, piccolo: Bool) {
        switch k {
        case 1: cicli(&gc, W, H, t, M, N, piccolo)
        case 2: notti(&gc, W, H, t, M, N, piccolo)
        default: onda(&gc, W, H, t, M, N, piccolo)
        }
    }

    private static func vuoto(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ testo: String, _ piccolo: Bool) {
        Olo.pavimento(&gc, W / 2, H - (piccolo ? 4 : 14), piccolo ? W * 0.3 : min(W * 0.22, 84), t, n: piccolo ? 20 : 48)
        if !piccolo { OP.scritta(&gc, testo, W / 2, H * 0.45, 8, 700, OP.c(0.85)) }
    }

    // MARK: S1 · ONDA — l'ipnogramma in 3D: la notte è un nastro di luce che corre da sinistra (l'addormentarsi) a destra (la sveglia),
    // alto quanto è profondo il sonno, steso in profondità come un'onda. Un velo di scansione ripercorre la notte ogni 9 s e dice l'ora e
    // la fase; sul pavimento le ore. Toccata una fase, il riquadro con gli orari e i minuti.

    private func onda(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ N: SonnoOlo, _ piccolo: Bool) {
        guard !N.fasi.isEmpty, N.durata > 1 else { ProveSonno.vuoto(&gc, W, H, t, "NESSUN DATO DELLA NOTTE", piccolo); return }
        let cx = W / 2, cy = H * 0.62, sz = piccolo ? W * 0.28 : min(W * 0.25, H * 0.42)
        let ang = -0.36 + 0.1 * sin(t * 0.21) + M.giro, al = 0.4
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let X = { (m: Double) -> Double in -1.5 + 3 * m / N.durata }
        let cresce = OP.lis(t / 0.9)
        let alto = { (tipo: Int) -> Double in SonnoOlo.alto[tipo] * 0.95 * cresce }
        var F = FasciOlo(6)
        // il pavimento: il bordo, la riga di ogni ora
        F.metti(1, P(-1.55, -0.5, 0), P(1.55, -0.5, 0)); F.metti(0, P(-1.55, 0.5, 0), P(1.55, 0.5, 0))
        var ore: [(m: Double, h: Int)] = []
        var hm = (N.inizio / 60).rounded(.up) * 60
        while hm - N.inizio <= N.durata { ore.append((hm - N.inizio, Int(hm / 60) % 24)); hm += 60 }
        for o in ore { F.metti(0, P(X(o.m), -0.5, 0), P(X(o.m), 0.5, 0)) }
        // il nastro: cinque file in profondità (la davanti la più chiara); ogni fase è un gradino alto quanto è profondo il sonno
        for j in 0..<5 {
            let y = -0.4 + Double(j) * 0.2, g = j == 0 ? 3 : j == 4 ? 1 : 2
            var q: P3?
            for f in N.fasi {
                let z = alto(f.tipo), p0 = P(X(f.a), y, z), p1 = P(X(f.b), y, z)
                if let q { F.metti(g - 1, q, p0) }
                F.metti(g + (f.tipo == 3 ? 1 : 0), p0, p1)
                q = p1
            }
        }
        for f in N.fasi { F.metti(0, P(X(f.a), -0.4, 0), P(X(f.a), -0.4, alto(f.tipo))) }   // i montanti davanti: si vede il volume
        // il velo di scansione: la notte rivista, ogni 9 s
        let m = t.truncatingRemainder(dividingBy: 9) / 9 * N.durata, fs = N.fase(m), sx = X(m)
        OP.lama(&gc, &F, P, (sx, -0.5), (sx, 0.5), 1.06)
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.08 + 0.16 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.14 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        // le facce dei gradini (più piene dove il sonno è più profondo) e le zone da toccare
        for (i, f) in N.fasi.enumerated() {
            let z = alto(f.tipo)
            let c = [P(X(f.a), -0.4, z), P(X(f.b), -0.4, z), P(X(f.b), 0.4, z), P(X(f.a), 0.4, z)]
            let pieno = f.tipo == 3 ? 0.15 : f.tipo == 1 ? 0.09 : 0.05
            gc.fill(OP.poligono(c), with: .color(OP.s(pieno + (M.scelta == i ? 0.18 : 0))))
            if !piccolo {
                let cc = P(X((f.a + f.b) / 2), -0.4, z)
                M.zona(cc.x, cc.y, max(12, (X(f.b) - X(f.a)) * sz * 0.45), i)
            }
        }
        let sp = P(sx, -0.4, alto(fs))
        OP.alone(&gc, sp.x, sp.y, piccolo ? 6 : 15, 0.85, bianco: true)
        guard !piccolo else { return }
        let cima = P(sx, -0.5, 1.13)
        OP.dentro(&gc, W, Olo.ora(N.inizio + m), cima.x, cima.y - 3, 8, 700, OP.b(0.95))
        OP.dentro(&gc, W, SonnoOlo.nome[fs], cima.x, cima.y + 7, 6.5, 600, OP.c(0.85))
        for o in ore { let p = P(X(o.m), -0.64, 0); OP.scritta(&gc, String(format: "%02d", o.h), p.x, p.y + 3, 6.5, 600, OP.c(0.55)) }
        // la scala delle fasi, a destra: quanto pesa ognuna stanotte
        var yy = 28.0
        for tipo in [3, 2, 1, 0] {
            OP.scritta(&gc, "\(SonnoOlo.nome[tipo]) \(OP.durata(N.minuti(0, N.durata, tipo)))", W - 10, yy, 6.5, 600, tipo == fs ? OP.b(0.95) : OP.c(0.6), .trailing)
            yy += 9
        }
        OP.scritta(&gc, "NOTTE · \(OP.durata(N.durata))", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, "\(Olo.ora(N.inizio)) → \(Olo.ora(N.fine))", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if let s = M.scelta, s < N.fasi.count {
            let f = N.fasi[s], c = P(X((f.a + f.b) / 2), -0.4, alto(f.tipo))
            OP.riquadro(&gc, W, H, c.x, c.y, [SonnoOlo.nome[f.tipo], "\(Olo.ora(N.inizio + f.a)) – \(Olo.ora(N.inizio + f.b))", "\(Int((f.b - f.a).rounded())) MIN"],
                        t - M.sceltaT, codice: "FASE \(s + 1)/\(N.fasi.count)")
        }
    }

    // MARK: S2 · CICLI — la notte come una spirale che sale dal proiettore: ogni giro è un ciclo del sonno (si chiude con il REM), il raggio
    // è quanto è profondo il sonno in quel momento. Una cometa la ripercorre dal fondo (l'addormentarsi) alla cima (la sveglia). Toccato
    // un ciclo, il riquadro con gli orari e il profondo e il REM di quel ciclo.

    private static func cicliDi(_ N: SonnoOlo) -> [(a: Double, b: Double)] {
        var cicli: [(a: Double, b: Double)] = []
        var da = 0.0
        for (i, f) in N.fasi.enumerated() {
            let dopo = i + 1 < N.fasi.count ? N.fasi[i + 1] : nil
            if f.tipo == 1 && (dopo == nil || dopo?.tipo != 1) { cicli.append((da, f.b)); da = f.b }
        }
        if N.durata - da > 5 { cicli.append((da, N.durata)) }
        return cicli
    }

    private func cicli(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ N: SonnoOlo, _ piccolo: Bool) {
        guard !N.fasi.isEmpty, N.durata > 1 else { ProveSonno.vuoto(&gc, W, H, t, "NESSUN DATO DELLA NOTTE", piccolo); return }
        let C = ProveSonno.cicliDi(N)
        guard !C.isEmpty else { ProveSonno.vuoto(&gc, W, H, t, "NESSUN CICLO", piccolo); return }
        let giroDi = { (m: Double) -> Double in
            var k = C.firstIndex { m >= $0.a && m <= $0.b } ?? (C.count - 1)
            k = max(0, k)
            return Double(k) + (m - C[k].a) / max(1, C[k].b - C[k].a)
        }
        let cx = W / 2, base = piccolo ? H - 3 : H - 14, cy = H * 0.52, sz = piccolo ? W * 0.26 : min(W * 0.25, H * 0.34)
        let ang = t * 0.22 + M.giro, al = 0.32
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let rx = piccolo ? W * 0.3 : min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        Olo.cono(&gc, cx, base, rx, cy - sz * 1.15, sz * 1.25, a: 0.06)
        let zDi = { (m: Double) -> Double in -0.95 + 1.9 * m / N.durata }
        let raggio = { (m: Double) -> Double in 0.32 + 0.62 * SonnoOlo.alto[N.fase(m)] }
        var F = FasciOlo(6)
        let fino = N.durata * OP.lis(t / 1.3)
        var q: P3?
        for s in 0...420 {
            let m = Double(s) / 420 * N.durata
            if m > fino { break }
            let a = giroDi(m) * OP.due, r = raggio(m), o = P(cos(a) * r, sin(a) * r, zDi(m))
            let k = C.firstIndex { m >= $0.a && m <= $0.b }
            if let q {
                let tipo = N.fase(m)
                F.metti((o.z < 0 ? 2 : 0) + (tipo == 3 ? 2 : tipo == 1 ? 1 : 0) + (M.scelta != nil && M.scelta == k ? 1 : 0), q, o)
            }
            q = o
        }
        F.metti(1, P(0, 0, -1.02), P(0, 0, 1.04))
        for c in C {
            var r0: P3?
            for i in 0...48 {
                let a = Double(i) / 48 * OP.due, o = P(cos(a) * 1.02, sin(a) * 1.02, zDi(c.b))
                if let r0, i % 2 == 1 { F.metti(o.z < 0 ? 1 : 0, r0, o) }
                r0 = o
            }
        }
        // la cometa: la notte rivista ogni 10 s, con la scia
        let mc = t.truncatingRemainder(dividingBy: 10) / 10 * min(fino, N.durata)
        var qq: P3?
        for k in 0...16 {
            let m = max(0, mc - Double(k) * 2.4), a = giroDi(m) * OP.due, r = raggio(m), o = P(cos(a) * r, sin(a) * r, zDi(m))
            if let qq { F.metti(5 - min(4, k >> 2), qq, o) }
            qq = o
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.62) : OP.c(0.08 + 0.16 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.15 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        let ac = giroDi(mc) * OP.due, rc = raggio(mc), cp = P(cos(ac) * rc, sin(ac) * rc, zDi(mc))
        OP.alone(&gc, cp.x, cp.y, piccolo ? 6 : 13, 0.9, bianco: true)
        guard !piccolo else { return }
        // i cicli: il numero e la durata a destra della spirale, alla quota del ciclo
        for (k, c) in C.enumerated() {
            let z = zDi((c.a + c.b) / 2), dx = P(0, 0, z), lx = min(W - 12, dx.x + sz * 1.25), scelto = M.scelta == k
            OP.scritta(&gc, "\(k + 1) · \(OP.durata(c.b - c.a))", lx, dx.y + 3, 7, 700, scelto ? OP.b(1) : OP.c(0.7), .trailing)
            M.zona(lx - 22, dx.y, 18, k)
            let mm = (c.a + c.b) / 2, am = giroDi(mm) * OP.due, sul = P(cos(am) * raggio(mm), sin(am) * raggio(mm), z)
            M.zona(sul.x, sul.y, 16, k)
        }
        OP.scritta(&gc, Olo.ora(N.inizio + mc), cp.x, cp.y - 9, 7, 700, OP.b(0.9))
        OP.scritta(&gc, "\(C.count) CICLI · \(OP.durata(N.durata))", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, "SVEGLIA \(Olo.ora(N.fine))", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if let s = M.scelta, s < C.count {
            let c = C[s], p = P(0, 0, zDi((c.a + c.b) / 2))
            let righe = ["CICLO \(s + 1) · \(OP.durata(c.b - c.a))", "\(Olo.ora(N.inizio + c.a)) – \(Olo.ora(N.inizio + c.b))",
                         "PROFONDO \(Int(N.minuti(c.a, c.b, 3).rounded())) MIN · REM \(Int(N.minuti(c.a, c.b, 1).rounded())) MIN"]
            OP.riquadro(&gc, W, H, p.x, p.y, righe, t - M.sceltaT, codice: "CICLI DEL SONNO")
        }
    }

    // MARK: S3 · NOTTI — le ultime 14 notti come colonne di luce in cerchio, alte quante ore; l'anello delle 7 ore le attraversa (chi lo
    // supera è una notte piena, più chiara). Stanotte sta davanti e pulsa. Toccata una colonna, la notte.

    private func notti(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ N: SonnoOlo, _ piccolo: Bool) {
        let n = N.notti.count
        guard n > 0 else { ProveSonno.vuoto(&gc, W, H, t, "NESSUNA NOTTE REGISTRATA", piccolo); return }
        let cx = W / 2, cy = H * 0.7, sz = piccolo ? W * 0.3 : min(W * 0.3, H * 0.4), ang = M.giro + 0.12 * sin(t * 0.25), al = 0.36
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let th = { (i: Int) -> Double in -Double.pi / 2 + Double(i - (n - 1)) * OP.due / Double(n) }   // stanotte davanti
        let R = 1.12, sale = OP.lis(t / 1.1)
        let alt = { (h: Double) -> Double in h / 9 * 1.35 * sale }
        let media = N.notti.reduce(0) { $0 + $1.ore } / Double(n)
        var F = FasciOlo(6)
        OP.ghiera(&F, { a, r, z in P(cos(a) * r, sin(a) * r, z) }, R + 0.22, 0, 112, 4, lunga: 0.06, corta: 0.03)
        // l'anello delle 7 ore (tratteggiato)
        var q: P3?
        for i in 0...96 {
            let a = Double(i) / 96 * OP.due, o = P(cos(a) * R, sin(a) * R, alt(7))
            if let q, i % 2 == 1 { F.metti(o.z < 0 ? 2 : 1, q, o) }
            q = o
        }
        var centri: [(x: Double, y: Double, i: Int)] = []
        var scritte: [(s: String, x: Double, y: Double, corpo: Double, col: Color)] = []
        for (i, nt) in N.notti.enumerated() {
            let a = th(i), c = (cos(a) * R, sin(a) * R), w = 0.07, h = alt(nt.ore), piena = nt.ore >= 7, scelta = M.scelta == i
            let uv: [(Double, Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            let ang4: [(Double, Double)] = uv.map { (c.0 + $0.0 * w, c.1 + $0.1 * w) }
            let dav = P(c.0, c.1, 0).z < 0
            let g = (dav ? 2 : 0) + (piena ? 1 : 0) + (nt.stanotte || scelta ? 2 : 0)
            for k in 0..<4 {
                let p = ang4[k], r = ang4[(k + 1) % 4]
                F.metti(g, P(p.0, p.1, 0), P(p.0, p.1, h))
                F.metti(g, P(p.0, p.1, h), P(r.0, r.1, h))
                F.metti(max(0, g - 2), P(p.0, p.1, 0), P(r.0, r.1, 0))
            }
            if nt.ore >= 2 { for k in 1..<Int(nt.ore) { F.metti(max(0, g - 1), P(ang4[0].0, ang4[0].1, alt(Double(k))), P(ang4[1].0, ang4[1].1, alt(Double(k)))) } }
            let top = P(c.0, c.1, h)
            centri.append((top.x, top.y, i))
            if piccolo { continue }
            M.zona(top.x, top.y + 10, 16, i)
            if dav || nt.stanotte { scritte.append((Olo.numero(nt.ore, decimali: 1), top.x, top.y - 5, 7, nt.stanotte ? OP.b(1) : OP.c(piena ? 0.9 : 0.6))) }
            let piede = P(c.0 * 1.32, c.1 * 1.32, 0)
            scritte.append((OP.lettera(nt.d), piede.x, piede.y + 3, 6.5, nt.stanotte ? OP.b(0.95) : OP.c(0.5)))
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.62) : OP.c(0.08 + 0.16 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.14 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        let st = N.notti[n - 1], ps = P(cos(th(n - 1)) * R, sin(th(n - 1)) * R, alt(st.ore))
        OP.alone(&gc, ps.x, ps.y, (piccolo ? 6 : 16) + 4 * sin(t * 3), 0.7, bianco: true)
        guard !piccolo else { return }
        for s in scritte { OP.scritta(&gc, s.s, s.x, s.y, s.corpo, s.corpo >= 7 ? 700 : 600, s.col) }
        let et = P(-R * 1.05, 0.2, alt(7))
        OP.scritta(&gc, "7 H", et.x - 4, et.y + 3, 7, 700, OP.c(0.8), .trailing)
        OP.scritta(&gc, "\(n) NOTTI · MEDIA \(Olo.numero(media, decimali: 1)) H", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, "STANOTTE \(OP.durata(st.ore * 60))", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if let s = M.scelta, s < n, let c = centri.first(where: { $0.i == s }) {
            let nt = N.notti[s]
            var righe = ["\(OP.giorno(nt.d)) · \(OP.durata(nt.ore * 60))"]
            if let p = nt.prof, let r = nt.rem { righe.append("PROFONDO \(OP.durata(p)) · REM \(OP.durata(r))") }
            righe.append(nt.ore >= 7 ? "NOTTE PIENA" : "SOTTO LE 7 H DI \(Int(((7 - nt.ore) * 60).rounded())) MIN")
            OP.riquadro(&gc, W, H, c.x, c.y, righe, t - M.sceltaT, codice: "NOTTE \(s + 1)/\(n)")
        }
    }
}

/// L'ologramma del sonno con le sue tre prove (iPhone: grande, con le chip; polso: piccolo, la prova scelta sull'iPhone).
struct OlogrammaSonnoProve: View {
    let dati: SonnoOlo
    var piccolo = false
    @State private var prove = ProveSonno()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .sonno) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .sonno, altezza: 280, crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
