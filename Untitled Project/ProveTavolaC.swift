import Foundation
import SwiftUI

// MARK: - VITALS, GITHUB, SUPABASE, ARCHIVIO, COSTI (build 11.0 (19), 9 nov, come il mockup)
// VITALS    SCANSIONE (la figura a fette, il piano che scende, testa · cuore · gambe), ANELLI (sonno, passi, umore attorno
//           alla prontezza), RADAR (i 30 giorni: umore e sonno, il fascio che gira).
// GITHUB    EXPO (i repository come padiglioni della Stark Expo), ATOMO (i commit come elettroni dell'elemento nuovo), PULSAR (14 giorni).
// SUPABASE  REATTORE (la Stark Tower: le tabelle come camere), RETE (le funzioni attorno al database), BATTITO (le richieste dell'ultima
//           ora, minuto per minuto, gli errori arancio).
// ARCHIVIO  OFFICINA (i file come tavole dell'officina di Tony), NUVOLA (per cartella), SPIRALE (per data).
// COSTI     PALLADIO (il nucleo: le bobine divise fra i modelli, l'anello della voce), TORRI (i giorni del mese), CLESSIDRA (il mese).
// Questo file è sia dell'iPhone sia dell'orologio (sul polso la prova scelta, in piccolo).

// MARK: VITALS

struct GiornoVitalsOlo { let d: Date; let um: Double?; let so: Double?; let ba: Double?; let pa: Double? }

struct DatiVitalsOlo {
    var prontezza: Int?
    var sonno: (punti: Int?, testo: String, nota: String) = (nil, "—", "")
    var battito: (punti: Int?, testo: String, nota: String) = (nil, "—", "A RIPOSO")
    var umore: (punti: Int?, testo: String, nota: String) = (nil, "—", "DAL DIARIO")
    var passi: (punti: Int?, testo: String, nota: String) = (nil, "—", "IERI · OBIETTIVO 10.000")
    var giorni: [GiornoVitalsOlo] = []

    /// 9 nov: i valori veri (come il pannello Organismo sotto), non i punteggi su 100 (prima «BATTITO 91» sopra e «BATTITO 67» sotto)
    var conto: String { "SONNO \(sonno.testo) · BATTITO \(battito.testo) · UMORE \(umore.testo.replacingOccurrences(of: " SU ", with: "/"))" }

    /// Dai dati che Vitals ha già: l'organismo (prontezza e punteggi) e i giorni (umore dal diario, sonno, battito, passi).
    static func da(_ o: DatiOrganismo, giorni: [DatiVitals.Giorno]) -> DatiVitalsOlo {
        var d = DatiVitalsOlo()
        d.prontezza = o.prontezza
        let durata = { (m: Int) -> String in m % 60 == 0 ? "\(m / 60) H" : "\(m / 60) H \(m % 60)" }
        var notaSonno = "STANOTTE"
        if let s = o.sonnoMin, let m = o.sonnoMediaMin { let dm = s - m; notaSonno = dm == 0 ? "NELLA MEDIA" : "\(abs(dm)) MIN \(dm < 0 ? "SOTTO" : "SOPRA") LA MEDIA" }
        d.sonno = (o.punteggioSonno, o.sonnoMin.map(durata) ?? "—", notaSonno)
        d.battito = (o.punteggioBattito, o.battito.map { "\($0) BPM" } ?? "—", o.battitoMedia.map { "A RIPOSO · MEDIA 7 GG \($0)" } ?? "A RIPOSO")
        d.umore = (o.punteggioUmore, o.umore.map { "\(Olo.numero($0, decimali: $0.rounded() == $0 ? 0 : 1)) SU 10" } ?? "—", "DAL DIARIO")
        d.passi = (o.passiIeri.map { min(100, Int((Double($0) / 100).rounded())) }, o.passiIeri.map { Olo.numero(Double($0)) } ?? "—", "IERI · OBIETTIVO 10.000")
        d.giorni = giorni.suffix(30).map { GiornoVitalsOlo(d: $0.data, um: $0.punteggio, so: $0.sonno, ba: $0.battito, pa: $0.passi) }
        return d
    }
}

final class ProveVitals {
    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiVitalsOlo, piccolo: Bool) {
        switch k {
        case 1: anelli(&gc, W, H, t, M, D, piccolo)
        case 2: radar(&gc, W, H, t, M, D, piccolo)
        default: scansione(&gc, W, H, t, M, D, piccolo)
        }
    }

    /// 9 nov (il signore: «corpo troppo semplice»): la figura vera, come l'ologramma di Organismo sotto: testa, collo, spalle tonde,
    /// petto, vita, fianchi, braccia lungo il corpo (gomito, polso, mano) e gambe (coscia, ginocchio, polpaccio, caviglia, piede).
    /// Le misure sono chiavi lungo l'altezza (0 piedi, 1,95 testa), unite in linea retta: le fette e la sagoma restano morbide.
    private static func chiave(_ k: [(Double, Double)], _ z: Double) -> Double {
        guard let primo = k.first, let ultimo = k.last else { return 0 }
        if z <= primo.0 { return primo.1 }
        if z >= ultimo.0 { return ultimo.1 }
        for n in 1..<k.count where z <= k[n].0 {
            let a = k[n - 1], b = k[n], u: Double = (z - a.0) / (b.0 - a.0)
            return a.1 + (b.1 - a.1) * u
        }
        return ultimo.1
    }
    private static let tronco: [(Double, Double)] = [(0.90, 0.175), (0.97, 0.19), (1.05, 0.17), (1.15, 0.142), (1.26, 0.168), (1.36, 0.198),
                                                     (1.44, 0.222), (1.50, 0.235), (1.545, 0.185), (1.57, 0.085)]
    private static let troncoP: [(Double, Double)] = [(0.90, 0.10), (1.00, 0.105), (1.14, 0.095), (1.26, 0.11), (1.38, 0.12), (1.50, 0.10), (1.57, 0.06)]
    private static let braccioX: [(Double, Double)] = [(0.74, 0.31), (0.90, 0.305), (1.20, 0.29), (1.48, 0.265)]
    private static let braccioR: [(Double, Double)] = [(0.74, 0.024), (0.88, 0.037), (0.94, 0.031), (1.16, 0.04), (1.30, 0.048), (1.48, 0.054)]
    private static let gambaX: [(Double, Double)] = [(0.04, 0.08), (0.50, 0.085), (0.90, 0.095)]
    private static let gambaR: [(Double, Double)] = [(0.04, 0.034), (0.10, 0.03), (0.20, 0.04), (0.36, 0.058), (0.50, 0.048), (0.70, 0.075), (0.90, 0.095)]

    /// Le sezioni del corpo a quota z: centro di lato, raggio largo, raggio profondo e spostamento in avanti (il piede).
    private static func largh(_ z: Double) -> [(Double, Double, Double, Double)] {
        if z > 1.66 { let u: Double = (z - 1.805) / 0.145, k: Double = max(0, 1 - u * u).squareRoot(); return [(0, 0.09 * k, 0.105 * k, -0.01)] }
        if z > 1.57 { return [(0, 0.048, 0.052, 0)] }
        var r: [(Double, Double, Double, Double)] = []
        if z >= 0.90 { r.append((0, chiave(tronco, z), chiave(troncoP, z), 0)) }
        if z < 0.90 {
            let gx = chiave(gambaX, z), gr = chiave(gambaR, z)
            let piede: Double = z < 0.09 ? (0.09 - z) / 0.05 : 0
            r.append((-gx, gr, gr * 0.95 + piede * 0.04, -piede * 0.04)); r.append((gx, gr, gr * 0.95 + piede * 0.04, -piede * 0.04))
        }
        if z >= 0.74 && z <= 1.48 {
            let bx = chiave(braccioX, z), br = chiave(braccioR, z)
            r.append((-bx, br, br, 0)); r.append((bx, br, br, 0))
        }
        return r
    }

    // SCANSIONE: la figura a fette di luce, il piano che scende, i punti agganciati
    private func scansione(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiVitalsOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.12, sz: 0.92, su: 0.02, oscilla: 0.55, mano: 0.8, conoSu: -0.6, conoW: 0.5))
        var F = FasciOlo(6)
        let scan = 1.95 - (t * 0.32).truncatingRemainder(dividingBy: 1.2) / 1.0 * 1.95, passo = piccolo ? 0.11 : 0.055
        var z = 0.04
        while z <= 1.94 && z <= 1.95 * s.nasce {
            let g = abs(z - scan) < 0.06 ? 4 : z > scan ? 2 : 1
            for (cx, rx, ry, dy) in ProveVitals.largh(z) {
                var q: P3?
                var velo = Path()                                  // 9 nov: il volume del corpo, ogni fetta velata di luce
                for k in 0...24 {
                    let a = Double(k) / 24 * OP.due, p = s.P(cx + cos(a) * rx, dy + sin(a) * ry, z)
                    if let q { F.metti(g, q, p) }
                    if k == 0 { velo.move(to: CGPoint(x: p.x, y: p.y)) } else { velo.addLine(to: CGPoint(x: p.x, y: p.y)) }
                    q = p
                }
                gc.fill(velo, with: .color(OP.c(piccolo ? 0.05 : 0.035)))
            }
            z += passo
        }
        if !piccolo {
            var z2 = 0.04
            while z2 + 0.0375 <= 1.94 * s.nasce {
                let A = ProveVitals.largh(z2), B = ProveVitals.largh(z2 + 0.0375)
                if A.count == B.count {
                    for (j, a) in A.enumerated() {
                        let b = B[j]
                        for k in 0..<10 { let an = Double(k) / 10 * OP.due + 0.26; F.metti(k == 0 || k == 5 ? 2 : 0, s.P(a.0 + cos(an) * a.1, a.3 + sin(an) * a.2, z2), s.P(b.0 + cos(an) * b.1, b.3 + sin(an) * b.2, z2 + 0.0375)) }
                    }
                }
                z2 += 0.0375
            }
        }
        Tav.traccia(&gc, F, piccolo)
        gc.stroke(Tav.spezzata((0...40).map { k in let a = Double(k) / 40 * OP.due; return s.P(cos(a) * 0.5, sin(a) * 0.3, scan) }), with: .color(OP.b(0.6)), lineWidth: 1.2)
        let pc = s.P(0.06, -0.05, 1.38)
        Tav.alone(&gc, pc, 8 + 4 * max(0, sin(t * 6.1)), 0.8, Tav.rosa)
        guard !piccolo else { return }
        let punti: [(String, P3, [String])] = [
            ("TESTA", s.P(0, 0, 1.8), ["UMORE \(D.umore.testo)", "SONNO \(D.sonno.testo)", D.sonno.nota]),
            ("CUORE", pc, ["BATTITO \(D.battito.testo)", D.battito.nota, "PUNTEGGIO \(D.battito.punti.map(String.init) ?? "—")"]),
            ("GAMBE", s.P(0.085, 0, 0.45), ["PASSI \(D.passi.testo)", D.passi.nota, "\(D.passi.punti.map(String.init) ?? "—")% DELL'OBIETTIVO"]),
        ]
        for (i, (nome, p, _)) in punti.enumerated() {
            let lx = i == 1 ? p.x + 46 : p.x - 46
            var l = Path(); l.move(to: CGPoint(x: p.x, y: p.y)); l.addLine(to: CGPoint(x: lx, y: p.y - 8))
            gc.stroke(l, with: .color(OP.c(0.6)), lineWidth: 1)
            OP.scritta(&gc, nome, lx, p.y - 11, 6.5, 800, OP.b(0.9), i == 1 ? .leading : .trailing)
            M.zona(p.x, p.y, 16, i)
        }
        Tav.testate(&gc, W, "SCANSIONE · CORPO", "PRONTEZZA \(D.prontezza.map { "\($0)%" } ?? "—")", D.conto)
        if let i = M.scelta, i >= 0, i < punti.count { OP.riquadro(&gc, W, H, punti[i].1.x, punti[i].1.y, [punti[i].0] + punti[i].2, t - M.sceltaT, codice: "SCAN") }
    }

    // ANELLI: sonno fuori, passi in mezzo, umore dentro; al centro la prontezza
    private func anelli(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiVitalsOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.55, sz: 1.15, su: 0.75, oscilla: 0.5, mano: 0.7, conoSu: 0.3))
        var F = FasciOlo(6)
        let A: [(String, (punti: Int?, testo: String, nota: String), Double)] = [("SONNO", D.sonno, 1.0), ("PASSI", D.passi, 0.78), ("UMORE", D.umore, 0.56)]
        let k = OP.lis(t / 1.6)
        for (i, a) in A.enumerated() { Tav.cerchio(&F, s, a.2, 0.15 + Double(i) * 0.06, 0, n: 72); Tav.cerchio(&F, s, a.2 - 0.09, 0.15 + Double(i) * 0.06, 0, n: 72) }
        Tav.traccia(&gc, F, piccolo)
        var cima: [P3] = []
        for (i, a) in A.enumerated() {
            let z = 0.15 + Double(i) * 0.06, fin = Double(a.1.punti ?? 0) / 100 * k * OP.due, r = a.2
            for w in 0..<(piccolo ? 2 : 4) {
                let rr = r - 0.015 - Double(w) * 0.02
                gc.stroke(Tav.spezzata((0...60).map { q in let an = -1.5708 + fin * Double(q) / 60; return s.P(cos(an) * rr, sin(an) * rr, z) }), with: .color(w > 0 ? OP.c(0.55) : OP.b(0.95)), lineWidth: w > 0 ? 1 : 1.6)
            }
            let an = -1.5708 + fin, p = s.P(cos(an) * (r - 0.045), sin(an) * (r - 0.045), z)
            Tav.alone(&gc, p, 9, 0.9, Tav.bianco)
            cima.append(p)
        }
        let c = s.P(0, 0, 0.3)
        Tav.alone(&gc, c, s.sz * 0.35, 0.25, Tav.bianco)
        guard !piccolo else { return }
        OP.scritta(&gc, D.prontezza.map { "\(Int((Double($0) * k).rounded()))%" } ?? "—", c.x, c.y + 4, 13, 800, OP.b(0.98))
        OP.scritta(&gc, "PRONTEZZA", c.x, c.y + 14, 5.5, 700, OP.c(0.85))
        for (i, a) in A.enumerated() { let p = cima[i]; OP.scritta(&gc, a.0, p.x + 8, p.y - 5, 6, 800, OP.c(0.95), .leading); M.zona(p.x, p.y, 14, i) }
        Tav.testate(&gc, W, "ANELLI DI OGGI", D.prontezza.map { "\($0)%" } ?? "—", "SONNO · PASSI · UMORE")
        if let i = M.scelta, i >= 0, i < A.count {
            let a = A[i]
            OP.riquadro(&gc, W, H, cima[i].x, cima[i].y, [a.0, a.1.testo, a.1.nota, "PUNTEGGIO \(a.1.punti.map(String.init) ?? "—") SU 100"], t - M.sceltaT, codice: "ANELLO")
        }
    }

    // RADAR: i 30 giorni come uno schermo radar: umore e sonno (fuori = meglio), il fascio che gira
    private func radar(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiVitalsOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.62, sz: 1.1, su: 0.75, giro: 0.04, rx: 0.3, cono: false))
        var F = FasciOlo(6)
        let G = D.giorni, n = max(1, G.count), A = { (i: Int) -> Double in -1.5708 + Double(i) / Double(n) * OP.due }
        for r in [0.33, 0.66, 1.0] { Tav.cerchio(&F, s, r * s.nasce, 0, r == 1 ? 2 : 0, n: 72) }
        for i in 0..<G.count { F.metti(0, s.P(0, 0, 0), s.P(cos(A(i)) * s.nasce, sin(A(i)) * s.nasce, 0)) }
        func linea(_ f: (GiornoVitalsOlo) -> Double, _ z: Double, _ g: Int) {
            guard G.count > 1 else { return }
            let pts = G.enumerated().map { i, d in s.P(cos(A(i)) * f(d) * s.nasce, sin(A(i)) * f(d) * s.nasce, z) }
            for k in 0..<pts.count { F.metti(g, pts[k], pts[(k + 1) % pts.count]) }
        }
        linea({ ($0.um ?? 0) / 10 }, 0.04, 4); linea({ ($0.so ?? 0) / 10 }, 0.02, 2)
        Tav.traccia(&gc, F, piccolo)
        let sw = t * 1.1, c0 = s.P(0, 0, 0)
        for k in 0..<14 { let a = sw - Double(k) * 0.04; Tav.segmento(&gc, c0, s.P(cos(a), sin(a), 0), OP.c(0.35 * (1 - Double(k) / 14)), 1.4) }
        let punti: [P3] = G.enumerated().map { i, d in
            let r = (d.um ?? 0) / 10 * s.nasce, p = s.P(cos(A(i)) * r, sin(A(i)) * r, 0.04)
            let dA = ((sw - A(i)).truncatingRemainder(dividingBy: OP.due) + OP.due).truncatingRemainder(dividingBy: OP.due)
            Tav.alone(&gc, p, 5, dA < 0.6 ? 0.9 - dA : 0.15, Tav.bianco)
            return p
        }
        guard !piccolo else { return }
        for (i, p) in punti.enumerated() { M.zona(p.x, p.y, 9, i) }
        func media(_ f: (GiornoVitalsOlo) -> Double?) -> Double? { let v = G.compactMap(f); return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
        Tav.testate(&gc, W, "RADAR · \(G.count) GIORNI", "UMORE \(media { $0.um }.map(Tav.uno) ?? "—")",
                    "SONNO \(media { $0.so }.map(Tav.uno) ?? "—") H · BATTITO \(media { $0.ba }.map { "\(Int($0.rounded()))" } ?? "—")")
        OP.scritta(&gc, "━ UMORE", 10, H - 22, 6, 700, OP.b(0.9), .leading)
        OP.scritta(&gc, "━ SONNO", 10, H - 12, 6, 700, OP.c(0.6), .leading)
        if let i = M.scelta, i >= 0, i < G.count {
            let d = G[i]
            OP.riquadro(&gc, W, H, punti[i].x, punti[i].y, [Tav.giorno(d.d), "UMORE \(d.um.map(Tav.uno) ?? "—") · SONNO \(d.so.map(Tav.uno) ?? "—") H",
                                                           "BATTITO \(d.ba.map { "\(Int($0.rounded()))" } ?? "—") · PASSI \(d.pa.map { Olo.numero($0) } ?? "—")"], t - M.sceltaT, codice: "GIORNO")
        }
    }
}

// MARK: GITHUB

struct RepoOlo { let nome: String; let da: String; let lingua: String; let commit: [String]; let giorni: [Int] }
struct DatiGithubOlo { var repo: [RepoOlo] = [] }

final class ProveGithub {
    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiGithubOlo, piccolo: Bool) {
        guard !D.repo.isEmpty else { if !piccolo { Tav.testate(&gc, W, "GITHUB", "APRO IL CANTIERE") }; return }
        switch k {
        case 1: atomo(&gc, W, H, t, M, D, piccolo)
        case 2: pulsar(&gc, W, H, t, M, D, piccolo)
        default: expo(&gc, W, H, t, M, D, piccolo)
        }
    }

    // EXPO: l'Unisfera al centro, ogni repository una torre (alta quanto il lavoro di 14 giorni), il più recente acceso
    private func expo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiGithubOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.42, sz: 1.1, su: 0.32, giro: 0.1, rx: 0.32, cono: false))
        var F = FasciOlo(6)
        let R = Array(D.repo.prefix(5))
        for k in 0..<4 {
            let b = Double(k) * 0.785 + t * 0.4
            var q: P3?
            for i in 0...40 { let a: Double = Double(i) / 40 * OP.due, r: Double = cos(a) * 0.22, z: Double = 0.32 + sin(a) * 0.22 * s.nasce, p = s.P(r * cos(b), r * sin(b), z); if let q { F.metti(k > 0 ? 1 : 3, q, p) }; q = p }
        }
        Tav.cerchio(&F, s, 0.22, 0.32, 1, n: 40); F.metti(2, s.P(0, 0, 0), s.P(0, 0, 0.1)); Tav.cerchio(&F, s, 0.3, 0, 1, n: 40)
        Tav.cerchio(&F, s, 1.0, 0, 0, n: 72); Tav.cerchio(&F, s, 0.62, 0, 0, n: 56)
        let tot = Double(max(1, R.map { $0.giorni.reduce(0, +) }.max() ?? 1))
        var torri: [(r: RepoOlo, top: P3)] = []
        for (i, r) in R.enumerated() {
            let a = -1.5708 + (Double(i) - Double(R.count - 1) / 2) * 1.15 + 3.1416, cx = cos(a) * 0.72, cy = sin(a) * 0.72
            let h = (0.22 + 0.5 * Double(r.giorni.reduce(0, +)) / tot) * s.nasce, w = 0.09, g = i == 0 ? 4 : 2
            let c: [(Double, Double)] = [(-w, -w), (w, -w), (w, w), (-w, w)]
            for (k, (u, v)) in c.enumerated() {
                let (u2, v2) = c[(k + 1) % 4]
                F.metti(g - 1, s.P(cx + u, cy + v, 0), s.P(cx + u * 0.6, cy + v * 0.6, h)); F.metti(g - 1, s.P(cx + u * 0.6, cy + v * 0.6, h), s.P(cx + u2 * 0.6, cy + v2 * 0.6, h))
            }
            Tav.cerchio(&F, s, 0.17, h * 0.7, g, n: 32, cx: cx, cy: cy)
            F.metti(g, s.P(cx, cy, h), s.P(cx, cy, h + 0.12))
            torri.append((r, s.P(cx, cy, h + 0.12)))
        }
        Tav.traccia(&gc, F, piccolo)
        Tav.alone(&gc, s.P(0, 0, 0.32), s.sz * 0.35, 0.2, Tav.bianco)
        for (i, q) in torri.enumerated() {
            Tav.alone(&gc, q.top, i == 0 ? 10 + 3 * sin(t * 4) : 6, i == 0 ? 0.9 : 0.4, Tav.bianco)
            var l = Path(); l.move(to: CGPoint(x: q.top.x, y: q.top.y)); l.addLine(to: CGPoint(x: q.top.x + sin(t + Double(i)) * 8, y: q.top.y - 40))
            gc.stroke(l, with: .linearGradient(Gradient(colors: [OP.c(i == 0 ? 0.35 : 0.15), OP.c(0)]), startPoint: CGPoint(x: q.top.x, y: q.top.y), endPoint: CGPoint(x: q.top.x, y: q.top.y - 40)), lineWidth: 3)
        }
        guard !piccolo else { return }
        for (i, q) in torri.enumerated() {
            OP.scritta(&gc, "\(OP.taglia(q.r.nome.uppercased(), 14)) · \(q.r.da.uppercased())", q.top.x, q.top.y - 8, 6.5, 800, i == 0 ? OP.b(0.95) : OP.c(0.85))
            M.zona(q.top.x, q.top.y + 10, 18, i)
        }
        Tav.testate(&gc, W, "STARK EXPO · GITHUB", "\(D.repo.count) REPOSITORY", "ULTIMO: \(OP.taglia(R[0].nome.uppercased(), 14)) · \(R[0].da.uppercased())")
        if let i = M.scelta, i >= 0, i < torri.count {
            let r = torri[i].r
            OP.riquadro(&gc, W, H, torri[i].top.x, torri[i].top.y, [r.nome.uppercased(), "AGGIORNATO \(r.da.uppercased())\(r.lingua.isEmpty ? "" : " · " + r.lingua.uppercased())",
                                                                     "\(r.giorni.reduce(0, +)) COMMIT IN 14 GIORNI", r.commit.first.map { "«\(OP.taglia($0, 26))»" } ?? "—"], t - M.sceltaT, codice: "PADIGLIONE")
        }
    }

    // ATOMO: il nucleo, un'orbita per repository, gli elettroni sono gli ultimi commit; il fascio dell'acceleratore
    private func atomo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiGithubOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.3, sz: 1.0, su: 0.95, giro: 0.15, conoSu: 0.4))
        var F = FasciOlo(6)
        let R = Array(D.repo.prefix(3))
        let orb: [(Double, Double, Double)] = [(0.5, 0.25, 0), (0.75, 1.15, 1.0), (1.0, -0.75, 2.1)]
        let Q = { (o: (Double, Double, Double), a: Double) -> P3 in
            let p = P3(cos(a) * o.0, sin(a) * o.0 * cos(o.1), sin(a) * o.0 * sin(o.1))
            return P3(p.x * cos(o.2) - p.y * sin(o.2), p.x * sin(o.2) + p.y * cos(o.2), p.z) * s.nasce
        }
        for (i, o) in orb.prefix(R.count).enumerated() { var q: P3?; for k in 0...72 { let p = s.Pv(Q(o, Double(k) / 72 * OP.due)); if let q { F.metti(i == 0 ? 2 : 1, q, p) }; q = p } }
        for k in 0..<3 {
            var q: P3?
            let ck: Double = cos(Double(k) * 1.05), sk: Double = sin(Double(k) * 1.05)
            for i in 0...24 { let a: Double = Double(i) / 24 * OP.due, r: Double = sin(a) * 0.12, p = s.P(cos(a) * 0.12, r * ck, r * sk); if let q { F.metti(4, q, p) }; q = p }
        }
        Tav.traccia(&gc, F, piccolo)
        let c = s.P(0, 0, 0)
        Tav.alone(&gc, c, s.sz * 0.45, 0.35 + 0.1 * sin(t * 5), Tav.bianco)
        let fa = (t * 0.6).truncatingRemainder(dividingBy: 1)
        Tav.segmento(&gc, P3(W * 0.04, c.y - s.sz * 0.9, 0), c, OP.b(0.5 * (1 - fa)), 1.2, tratteggio: [2, 4])
        var el: [(r: RepoOlo, m: String, k: Int, p: P3)] = []
        for (i, r) in R.enumerated() {
            let msg = Array(r.commit.prefix(4)), nm = Double(max(1, msg.count))
            for (k, m) in msg.enumerated() {
                let a = t * (0.9 - Double(i) * 0.2) + Double(k) * (OP.due / nm), p = s.Pv(Q(orb[i], a))
                Tav.alone(&gc, p, i == 0 && k == 0 ? 9 : 6, i == 0 && k == 0 ? 1 : 0.55, Tav.bianco)
                el.append((r, m, k, p))
            }
        }
        guard !piccolo else { return }
        for (j, e) in el.enumerated() { M.zona(e.p.x, e.p.y, 10, j) }
        OP.scritta(&gc, "NUCLEO", c.x, c.y + s.sz * 0.22 + 6, 5.5, 700, OP.c(0.7))
        Tav.testate(&gc, W, "ELEMENTO NUOVO", "\(el.count) COMMIT", "\(OP.taglia(R[0].nome.uppercased(), 14)) · \(R[0].da.uppercased())")
        if let j = M.scelta, j >= 0, j < el.count {
            let e = el[j]
            OP.riquadro(&gc, W, H, e.p.x, e.p.y, [e.r.nome.uppercased(), "«\(OP.taglia(e.m, 30))»", e.k == 0 ? "L'ULTIMO · \(e.r.da.uppercased())" : "\(e.k + 1)° PIÙ RECENTE"], t - M.sceltaT, codice: "ELETTRONE")
        }
    }

    // PULSAR: le ultime due settimane: la stella batte quanto si è lavorato oggi, 14 colonne attorno (oggi davanti), i fasci girano
    private func pulsar(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiGithubOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.4, sz: 1.15, su: 0.45, giro: 0.08, rx: 0.3, conoA: 0.04))
        var F = FasciOlo(6)
        let n = 14
        let g: [Int] = (0..<n).map { i in D.repo.reduce(0) { $0 + ($1.giorni.count == n ? $1.giorni[i] : 0) } }
        let mx = Double(max(1, g.max() ?? 1)), oggi = Date()
        var col: [(v: Int, top: P3, d: Date)] = []
        for (i, v) in g.enumerated() {
            let a = 1.5708 - Double(n - 1 - i) / Double(n) * OP.due, cx = cos(a) * 0.85, cy = sin(a) * 0.85, h = (0.05 + 0.7 * Double(v) / mx) * s.nasce, w = 0.05
            let gg = i == n - 1 ? 4 : Double(v) > mx * 0.6 ? 3 : 1
            F.metti(gg, s.P(cx - w, cy, 0), s.P(cx - w, cy, h)); F.metti(gg, s.P(cx + w, cy, 0), s.P(cx + w, cy, h)); F.metti(gg, s.P(cx - w, cy, h), s.P(cx + w, cy, h))
            col.append((v, s.P(cx, cy, h), oggi.addingTimeInterval(-Double(n - 1 - i) * 86_400)))
        }
        Tav.cerchio(&F, s, 0.85, 0, 0, n: 72); Tav.cerchio(&F, s, 0.5, 0.3, 0, n: 48)
        Tav.traccia(&gc, F, piccolo)
        let c = s.P(0, 0, 0.3), batte = pow(max(0, sin(t * .pi * (0.8 + Double(g[n - 1]) / mx))), 8)
        Tav.alone(&gc, c, s.sz * (0.25 + 0.12 * batte), 0.5 + 0.4 * batte, Tav.bianco)
        for lato in [1.0, -1.0] {
            let a = t * 1.3 + (lato > 0 ? 0 : .pi), e = s.P(cos(a) * 1.3, sin(a) * 1.3, 0.3 + lato * 0.5)
            var l = Path(); l.move(to: CGPoint(x: c.x, y: c.y)); l.addLine(to: CGPoint(x: e.x, y: e.y))
            gc.stroke(l, with: .linearGradient(Gradient(colors: [OP.b(0.6), OP.b(0)]), startPoint: CGPoint(x: c.x, y: c.y), endPoint: CGPoint(x: e.x, y: e.y)), lineWidth: 2.5)
        }
        guard !piccolo else { return }
        for (i, q) in col.enumerated() { M.zona(q.top.x, q.top.y, 10, i) }
        Tav.testate(&gc, W, "PULSAR · 14 GIORNI", "\(g.reduce(0, +)) COMMIT", "OGGI \(g[n - 1]) · RECORD \(Int(mx))")
        if let i = M.scelta, i >= 0, i < col.count {
            let q = col[i], chi = D.repo.filter { $0.giorni.count == n && $0.giorni[i] > 0 }.map { $0.nome.uppercased() }
            OP.riquadro(&gc, W, H, q.top.x, q.top.y, [Tav.giorno(q.d), "\(q.v) COMMIT", chi.isEmpty ? "GIORNO DI RIPOSO" : OP.taglia(chi.joined(separator: " · "), 30)], t - M.sceltaT, codice: "GIORNO")
        }
    }
}

// MARK: SUPABASE

struct DatiSupabaseOlo {
    var tabelle: [(nome: String, righe: Int)] = []
    var funzioni: [(nome: String, versione: Int, attiva: Bool)] = []
    var db = "—"
    var righe = 0
    var storage = "—"
    var errori = 0
    var minuti: [(r: Int, e: Int)] = []
    var richieste: Int { minuti.reduce(0) { $0 + $1.r } }
}

final class ProveSupabase {
    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiSupabaseOlo, piccolo: Bool) {
        switch k {
        case 1: rete(&gc, W, H, t, M, D, piccolo)
        case 2: battito(&gc, W, H, t, M, D, piccolo)
        default: reattore(&gc, W, H, t, M, D, piccolo)
        }
    }

    // REATTORE: il nucleo alto (la Stark Tower), le tabelle sono camere piene quanto le righe (scala logaritmica)
    private func reattore(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiSupabaseOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.35, sz: 1.05, su: 0.08, giro: 0.12, rx: 0.3, conoA: 0.04))
        var F = FasciOlo(6)
        let T = Array(D.tabelle.sorted { $0.righe > $1.righe }.prefix(6)), nb = s.nasce
        for z in [0.0, 0.4, 0.8, 1.2] { Tav.cerchio(&F, s, 0.2 - z * 0.04, z * nb, z == 1.2 ? 4 : 2, n: 32) }
        for k in 0..<6 { let a = Double(k) / 6 * OP.due; F.metti(1, s.P(cos(a) * 0.2, sin(a) * 0.2, 0), s.P(cos(a) * 0.15, sin(a) * 0.15, 1.2 * nb)) }
        let mx = log10(Double(max(10, T.map { $0.righe }.max() ?? 10))), tot = Double(max(1, D.tabelle.reduce(0) { $0 + $1.righe }))
        var cam: [(nome: String, n: Int, f: Double, cx: Double, cy: Double, p: P3)] = []
        for (i, tb) in T.enumerated() {
            let a = Double(i) / Double(max(1, T.count)) * OP.due + 0.4, cx = cos(a) * 0.72, cy = sin(a) * 0.72, h = 0.55, f = log10(Double(max(1, tb.righe))) / mx
            Tav.cerchio(&F, s, 0.14, 0, 1, n: 24, cx: cx, cy: cy); Tav.cerchio(&F, s, 0.14, h * nb, 1, n: 24, cx: cx, cy: cy); Tav.cerchio(&F, s, 0.13, h * f * nb, 4, n: 24, cx: cx, cy: cy)
            for k in 0..<4 { let b = Double(k) / 4 * OP.due; F.metti(0, s.P(cx + cos(b) * 0.14, cy + sin(b) * 0.14, 0), s.P(cx + cos(b) * 0.14, cy + sin(b) * 0.14, h * nb)) }
            F.metti(0, s.P(cx * 0.8, cy * 0.8, 0.1), s.P(cos(a) * 0.2, sin(a) * 0.2, 0.1))
            cam.append((tb.nome, tb.righe, f, cx, cy, s.P(cx, cy, h * f * nb + 0.05)))
        }
        Tav.traccia(&gc, F, piccolo)
        for k in 0..<8 { let z = (t * 0.5 + Double(k) / 8).truncatingRemainder(dividingBy: 1) * 1.2 * nb; Tav.alone(&gc, s.P(0, 0, z), 8, 0.5 * (1 - z / 1.3), Tav.bianco) }
        let cima = s.P(0, 0, 1.2 * nb)
        Tav.alone(&gc, cima, s.sz * 0.3, 0.6 + 0.2 * sin(t * 3), Tav.bianco)
        Tav.segmento(&gc, cima, P3(cima.x, 0, 0), OP.b(0.4), 2)
        for c in cam { Tav.alone(&gc, s.P(c.cx, c.cy, 0.55 * c.f * nb), 10, 0.35, Tav.bianco) }
        guard !piccolo else { return }
        for (i, c) in cam.enumerated() { OP.scritta(&gc, OP.taglia(c.nome.replacingOccurrences(of: "jarvis_", with: "").uppercased(), 12), c.p.x, c.p.y - 14, 6, 800, OP.c(0.95)); M.zona(c.p.x, c.p.y, 16, i) }
        Tav.testate(&gc, W, "REATTORE · DATABASE", D.db, "\(Olo.numero(Double(D.righe))) RIGHE · \(D.errori) ERRORI")
        if let i = M.scelta, i >= 0, i < cam.count {
            let c = cam[i]
            OP.riquadro(&gc, W, H, c.p.x, c.p.y, [c.nome.uppercased(), "\(Olo.numero(Double(c.n))) RIGHE", "\(Olo.numero(Double(c.n) / tot * 100, decimali: 1))% DELLE RIGHE"], t - M.sceltaT, codice: "CAMERA")
        }
    }

    // RETE: le funzioni attorno al database, gli impulsi che vanno e tornano (più chiamate nell'ultima ora, più impulsi)
    private func rete(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiSupabaseOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.38, sz: 1.1, su: 0.6, giro: 0.1))
        var F = FasciOlo(6)
        let Fn = Array(D.funzioni.prefix(8))
        for k in 0..<3 { Tav.cerchio(&F, s, 0.2, 0.15 + Double(k) * 0.12, k == 1 ? 4 : 2, n: 32) }
        var nodi: [(f: (nome: String, versione: Int, attiva: Bool), q: P3, p: P3)] = []
        for (i, f) in Fn.enumerated() {
            let a = Double(i) / Double(max(1, Fn.count)) * OP.due + 0.8, q = P3(cos(a) * 0.9 * s.nasce, sin(a) * 0.9 * s.nasce, 0.27 + 0.2 * sin(Double(i) * 2))
            F.metti(1, s.Pv(q), s.P(0, 0, 0.27)); Tav.cerchio(&F, s, 0.09, q.z, 3, n: 20, cx: q.x, cy: q.y)
            nodi.append((f, q, s.Pv(q)))
        }
        Tav.traccia(&gc, F, piccolo)
        let c0 = s.P(0, 0, 0.27)
        Tav.alone(&gc, c0, s.sz * 0.35, 0.35, Tav.bianco)
        let ritmo = Double(min(6, max(1, D.richieste / 40)))
        for (i, nd) in nodi.enumerated() {
            for k in 0..<Int(ritmo) {
                let u = (t * 0.45 + Double(k) / ritmo + Double(i) * 0.13).truncatingRemainder(dividingBy: 1), w = u < 0.5 ? u * 2 : 2 - u * 2
                Tav.alone(&gc, s.P(nd.q.x * (1 - w), nd.q.y * (1 - w), nd.q.z + (0.27 - nd.q.z) * w), 5, 0.85, Tav.bianco)
            }
            Tav.alone(&gc, nd.p, 10, 0.4, nd.f.attiva ? Tav.bianco : Tav.arancio)
        }
        guard !piccolo else { return }
        OP.scritta(&gc, "DATABASE", c0.x, c0.y + s.sz * 0.3 + 4, 6, 800, OP.b(0.9))
        for (i, nd) in nodi.enumerated() {
            OP.scritta(&gc, OP.taglia(nd.f.nome.replacingOccurrences(of: "jarvis-", with: "").uppercased(), 12), nd.p.x, nd.p.y - 12, 6.5, 800, OP.c(0.95))
            OP.scritta(&gc, "V\(nd.f.versione)", nd.p.x, nd.p.y + 15, 5.5, 600, OP.c(0.7))
            M.zona(nd.p.x, nd.p.y, 15, i)
        }
        Tav.testate(&gc, W, "FUNZIONI EDGE", "\(Fn.count) FUNZIONI", "\(D.richieste) RICHIESTE NELL'ULTIMA ORA")
        if let i = M.scelta, i >= 0, i < nodi.count {
            let f = nodi[i].f
            OP.riquadro(&gc, W, H, nodi[i].p.x, nodi[i].p.y, [f.nome.uppercased(), "VERSIONE \(f.versione)", f.attiva ? "ATTIVA" : "NON ATTIVA"], t - M.sceltaT, codice: "FUNZIONE")
        }
    }

    // BATTITO: l'ultima ora minuto per minuto, 60 colonne in cerchio alte quanto le richieste, gli errori arancio; al centro il totale
    private func battito(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiSupabaseOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.5, sz: 1.2, su: 0.4, giro: 0.05, rx: 0.3, cono: false))
        var F = FasciOlo(6)
        let m = D.minuti, n = max(1, m.count), mx = Double(max(1, m.map { $0.r }.max() ?? 1))
        var col: [(q: (r: Int, e: Int), c: P3, i: Int)] = []
        for (i, q) in m.enumerated() {
            let a = 1.5708 - Double(n - 1 - i) / Double(n) * OP.due, r = 0.85, h = (0.03 + Double(q.r) / mx * 0.6) * s.nasce
            let g = q.e > 0 ? 5 : Double(q.r) == mx ? 4 : Double(q.r) > mx * 0.6 ? 3 : 1
            let b = s.P(cos(a) * r, sin(a) * r, 0), c = s.P(cos(a) * r, sin(a) * r, h)
            if q.e > 0 { Tav.segmento(&gc, b, c, Tav.a(Tav.arancio, 0.95), 1.6) } else { F.metti(g, b, c) }
            col.append((q, c, i))
        }
        Tav.cerchio(&F, s, 0.85, 0, 0, n: 72)
        Tav.traccia(&gc, F, piccolo)
        let c = s.P(0, 0, 0.15), b = pow(max(0, sin(t * 3.2)), 10)
        Tav.alone(&gc, c, s.sz * (0.3 + 0.08 * b), 0.3 + 0.4 * b, D.errori > 0 ? Tav.arancio : Tav.bianco)
        if !col.isEmpty { let k = Int(max(0, t) * 20) % col.count; Tav.alone(&gc, col[k].c, 7, 0.8, Tav.bianco) }
        guard !piccolo else { return }
        OP.scritta(&gc, "\(D.richieste)", c.x, c.y + 4, 12, 800, OP.b(0.98))
        OP.scritta(&gc, "RICHIESTE", c.x, c.y + 14, 5.5, 700, OP.c(0.8))
        for q in col where q.i % 2 == 0 || q.q.e > 0 || Double(q.q.r) == mx { M.zona(q.c.x, q.c.y, 8, q.i) }
        Tav.testate(&gc, W, "BATTITO · ULTIMA ORA", D.errori > 0 ? "\(D.errori) ERRORI" : "SANO", "\(D.richieste) RICHIESTE · \(D.storage)")
        if let i = M.scelta, let q = col.first(where: { $0.i == i }) {
            let fa = n - 1 - q.i
            OP.riquadro(&gc, W, H, q.c.x, q.c.y, [fa > 0 ? "\(fa) MIN FA" : "ADESSO", "\(q.q.r) RICHIESTE", q.q.e > 0 ? "\(q.q.e) ERRORI" : Double(q.q.r) == mx ? "IL MINUTO PIÙ PIENO" : "NESSUN ERRORE"],
                        t - M.sceltaT, codice: "MINUTO")
        }
    }
}

// MARK: ARCHIVIO

struct FileOlo { let nome: String; let cartella: String; let kb: Int; let quando: String; let tipo: String }
struct DatiArchivioOlo {
    var file: [FileOlo] = []
    var cartelle: [(nome: String, n: Int)] = []
    /// foto, audio o doc (dal tipo del file).
    static func genere(_ mime: String, _ nome: String) -> String {
        let n = nome.lowercased()
        if mime.hasPrefix("image/") || [".jpg", ".jpeg", ".png", ".heic"].contains(where: { n.hasSuffix($0) }) { return "foto" }
        if mime.hasPrefix("audio/") || [".m4a", ".mp3", ".wav"].contains(where: { n.hasSuffix($0) }) { return "audio" }
        return "doc"
    }
}

final class ProveArchivio {
    private static let colori: [Color] = [Tav.bianco, Tav.ciano, Tav.oro, Tav.menta]
    private static func peso(_ kb: Int) -> String { kb < 1000 ? "\(kb) KB" : "\(Olo.numero(Double(kb) / 1024, decimali: 1)) MB" }

    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiArchivioOlo, piccolo: Bool) {
        guard !D.file.isEmpty else { if !piccolo { Tav.testate(&gc, W, "ARCHIVIO", "VUOTO") }; return }
        switch k {
        case 1: nuvola(&gc, W, H, t, M, D, piccolo)
        case 2: spirale(&gc, W, H, t, M, D, piccolo)
        default: officina(&gc, W, H, t, M, D, piccolo)
        }
    }

    /// Il disegno dentro la tavola: foto (le montagne), audio (l'onda), documento (le righe).
    private static func disegno(_ F: inout FasciOlo, _ s: ScenaTav, _ g: String, _ cx: Double, _ cy: Double, _ z0: Double, _ w: Double, _ h: Double, _ gr: Int) {
        if g == "foto" {
            let p: [(Double, Double)] = [(-0.6, 0.25), (-0.15, 0.6), (0.15, 0.4), (0.35, 0.52), (0.6, 0.25)]
            for k in 1..<p.count { F.metti(gr, s.P(cx + w * p[k - 1].0, cy, z0 + h * p[k - 1].1), s.P(cx + w * p[k].0, cy, z0 + h * p[k].1)) }
        } else if g == "audio" {
            var q: P3?
            for k in 0...24 {
                let u: Double = Double(k) / 24, px: Double = cx - w * 0.65 + u * w * 1.3, onda: Double = 0.2 * sin(Double(k) * 1.9) * sin(u * .pi)
                let p = s.P(px, cy, z0 + h * (0.45 + onda))
                if let q { F.metti(gr, q, p) }
                q = p
            }
        } else {
            for r in 0..<5 { let z = z0 + h * (0.72 - Double(r) * 0.12); F.metti(gr, s.P(cx - w * 0.6, cy, z), s.P(cx + w * (r == 4 ? 0.1 : 0.6), cy, z)) }
        }
    }

    // OFFICINA: i file come i progetti olografici dell'officina di Tony: tavole a quadretti, quella davanti grande. Si sfogliano.
    private func officina(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiArchivioOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.25, sz: 1.2, su: 0.1, giro: 0, mano: 0, rx: 0.3, conoSu: 0.1, conoW: 1.0))
        let Fl = Array(D.file.prefix(40)), n = Fl.count, nd = Double(n)
        let pos = ((M.giro * 2.4).truncatingRemainder(dividingBy: nd) + nd).truncatingRemainder(dividingBy: nd)
        var lista: [(d: Double, i: Int)] = []
        for i in 0..<n {
            var d = Double(i) - pos
            if d > nd / 2 { d -= nd }
            if d < -nd / 2 { d += nd }
            if d >= -0.5 && d <= 3.2 { lista.append((d, i)) }
        }
        lista.sort { $0.d > $1.d }
        for (d, i) in lista {
            let f = Fl[i], fr = abs(d) < 0.5, cy = d * 0.32, cx = d * 0.08, z0 = 0.1 + max(0, d) * 0.05, w = fr ? 0.55 : 0.45, h = fr ? 0.7 : 0.55, g = fr ? 4 : 1
            let al = max(0.2, 1 - abs(d) * 0.28), hz = h * s.nasce
            var F = FasciOlo(6)
            let c = [s.P(cx - w, cy, z0), s.P(cx + w, cy, z0), s.P(cx + w, cy, z0 + hz), s.P(cx - w, cy, z0 + hz)]
            for k in 0..<4 { F.metti(g, c[k], c[(k + 1) % 4]) }
            if fr && !piccolo {
                for k in 1..<6 { let x = cx - w + Double(k) * w / 3; F.metti(0, s.P(x, cy, z0), s.P(x, cy, z0 + hz)) }
                for k in 1..<4 { let z = z0 + Double(k) * h / 4 * s.nasce; F.metti(0, s.P(cx - w, cy, z), s.P(cx + w, cy, z)) }
            }
            F.metti(g, s.P(cx - w, cy, z0 + hz), s.P(cx - w - 0.06, cy, z0 + hz + 0.06)); F.metti(g, s.P(cx + w, cy, z0), s.P(cx + w + 0.06, cy, z0 - 0.06))
            ProveArchivio.disegno(&F, s, DatiArchivioOlo.genere(f.tipo, f.nome), cx, cy, z0, w * 0.55, hz, fr ? 3 : 1)
            gc.fill(Tav.spezzata(c, chiusa: true), with: .color(OP.s(fr ? 0.08 : 0.03 * al)))
            Tav.traccia(&gc, F, piccolo, k: al)
            if !piccolo && fr {
                let t0 = s.P(cx, cy, z0 + hz + 0.08), t1 = s.P(cx, cy, z0 - 0.08), m = s.P(cx, cy, z0 + h * 0.5)
                OP.scritta(&gc, OP.taglia(f.nome.uppercased(), 28), t0.x, t0.y, 7, 800, OP.b(0.95))
                OP.scritta(&gc, "\(f.cartella.uppercased()) · \(ProveArchivio.peso(f.kb)) · \(f.quando.uppercased())", t1.x, t1.y + 6, 6, 600, OP.c(0.85))
                M.zona(m.x, m.y, 30, i)
            }
        }
        guard !piccolo else { return }
        Tav.testate(&gc, W, "OFFICINA · ARCHIVIO", "\(Int(pos.rounded()) % n + 1) / \(n)", "\(D.file.count) FILE · \(D.cartelle.count) CARTELLE")
        if let i = M.scelta, i >= 0, i < n {
            let f = Fl[i], p = s.P(0, 0, 0.45)
            OP.riquadro(&gc, W, H, p.x, p.y, [f.nome.uppercased(), "CARTELLA \(f.cartella.uppercased())", "\(ProveArchivio.peso(f.kb)) · \(DatiArchivioOlo.genere(f.tipo, f.nome).uppercased())",
                                               "CARICATO \(f.quando.uppercased())"], t - M.sceltaT, codice: "TAVOLA")
        }
    }

    // NUVOLA: le cartelle come nuvole di particelle che girano attorno al centro (ogni file un punto, grande quanto pesa)
    private func nuvola(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiArchivioOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.35, sz: 1.05, su: 0.7, giro: 0.15))
        var F = FasciOlo(6)
        Tav.cerchio(&F, s, 0.78, 0.3, 0, n: 64); Tav.cerchio(&F, s, 0.12, 0.3, 3, n: 24)
        let cart = Array(D.cartelle.prefix(6)), nc = Double(max(1, cart.count))
        var nuv: [(nome: String, cc: P3, f: [FileOlo], tot: Int)] = []
        for (i, c) in cart.enumerated() {
            let a = Double(i) / nc * OP.due + t * 0.2, cc = P3(cos(a) * 0.78 * s.nasce, sin(a) * 0.78 * s.nasce, 0.3 + 0.12 * sin(Double(i) * 2.1))
            F.metti(0, s.P(0, 0, 0.3), s.Pv(cc))
            let f = D.file.filter { $0.cartella == c.nome }
            nuv.append((c.nome, cc, f, max(c.n, f.count)))
        }
        Tav.traccia(&gc, F, piccolo)
        for (i, q) in nuv.enumerated() {
            Tav.alone(&gc, s.Pv(q.cc), s.sz * 0.3, 0.12)
            for (k, f) in q.f.prefix(30).enumerated() {
                let a = Double(k) * 2.39996 + t * (0.6 + Double(i) * 0.1), r = 0.06 + 0.04 * Double(k + 1).squareRoot()
                let px: Double = q.cc.x + cos(a) * r, py: Double = q.cc.y + sin(a) * r, pz: Double = q.cc.z + 0.06 * sin(a * 1.7 + t)
                let p = s.P(px, py, pz)
                Tav.alone(&gc, p, 3 + min(6, Double(f.kb) / 1024 * 1.4), 0.75, Tav.bianco)
            }
        }
        Tav.alone(&gc, s.P(0, 0, 0.3), 10, 0.6, Tav.bianco)
        guard !piccolo else { return }
        for (i, q) in nuv.enumerated() { let p = s.Pv(q.cc); OP.scritta(&gc, "\(OP.taglia(q.nome.uppercased(), 12)) · \(q.tot)", p.x, p.y - s.sz * 0.22, 6.5, 800, OP.c(0.95)); M.zona(p.x, p.y, 20, i) }
        let tot = D.file.reduce(0) { $0 + $1.kb }
        Tav.testate(&gc, W, "NUVOLA DEI FILE", "\(D.file.count) FILE", "\(ProveArchivio.peso(tot)) IN TUTTO")
        if let i = M.scelta, i >= 0, i < nuv.count {
            let q = nuv[i], p = s.Pv(q.cc)
            OP.riquadro(&gc, W, H, p.x, p.y, [q.nome.uppercased(), "\(q.tot) FILE · \(ProveArchivio.peso(q.f.reduce(0) { $0 + $1.kb }))", "ULTIMO: \(OP.taglia(q.f.first?.nome ?? "—", 24))"],
                        t - M.sceltaT, codice: "CARTELLA")
        }
    }

    // SPIRALE: i file in ordine di tempo su una spirale che sale (in cima il più recente); il colore dice la cartella
    private func spirale(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiArchivioOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.28, sz: 0.95, su: 0.05, giro: 0.2, conoSu: -0.3, conoW: 0.7))
        var F = FasciOlo(6)
        let Fl = Array(D.file.prefix(30)), n = Fl.count, cartelle = D.cartelle.map { $0.nome }
        let su = { (u: Double) -> P3 in let a = u * OP.due * 1.6, r = 0.75 - u * 0.4; return P3(cos(a) * r, sin(a) * r, (0.05 + u * 1.25) * s.nasce) }
        var q: P3?
        for k in 0...120 { let p = s.Pv(su(Double(k) / 120)); if let q { F.metti(1, q, p) }; q = p }
        F.metti(0, s.P(0, 0, 0), s.P(0, 0, 1.35 * s.nasce))
        let pt: [(f: FileOlo, p: P3)] = Fl.enumerated().map { i, f in
            let v = su(1 - Double(i) / Double(max(1, n - 1)))
            F.metti(0, s.Pv(v), s.P(0, 0, v.z))
            return (f, s.Pv(v))
        }
        Tav.traccia(&gc, F, piccolo)
        for (i, q) in pt.enumerated() {
            let ci = cartelle.firstIndex(of: q.f.cartella) ?? 0
            Tav.alone(&gc, q.p, 4 + min(6, Double(q.f.kb) / 1024 * 1.2), i == 0 ? 0.95 : 0.55, ProveArchivio.colori[ci % ProveArchivio.colori.count])
        }
        guard !piccolo else { return }
        if let p0 = pt.first?.p { OP.scritta(&gc, "OGGI", p0.x + 10, p0.y - 6, 6, 800, OP.b(0.9), .leading) }
        for (i, q) in pt.enumerated() { M.zona(q.p.x, q.p.y, 10, i) }
        for (i, c) in cartelle.prefix(4).enumerated() {
            OP.scritta(&gc, "● " + OP.taglia(c.uppercased(), 12), 10, H - 44 + Double(i) * 10, 6, 700, Tav.a(ProveArchivio.colori[i % ProveArchivio.colori.count], 0.9), .leading)
        }
        Tav.testate(&gc, W, "SPIRALE DEL TEMPO", "\(D.file.count) FILE", n > 0 ? "DAL \(Fl[n - 1].quando.uppercased()) A \(Fl[0].quando.uppercased())" : nil)
        if let i = M.scelta, i >= 0, i < pt.count {
            let f = pt[i].f
            OP.riquadro(&gc, W, H, pt[i].p.x, pt[i].p.y, [f.nome.uppercased(), "\(f.cartella.uppercased()) · \(ProveArchivio.peso(f.kb))", f.quando.uppercased()], t - M.sceltaT, codice: "FILE")
        }
    }
}

// MARK: COSTI

struct DatiCostiOlo {
    var mese = 0.0
    var oggi = 0.0
    var ieri = 0.0
    var sette = 0.0
    var risposte = 0
    var modelli: [(nome: String, dollari: Double, risposte: Int)] = []
    var voce: (percento: Int, testo: String)?
    var fissi = ""
    var giorni: [(giorno: Date, dollari: Double)] = []

    /// Dal JSON del cervello (consumi): la stessa scheda dell'iPhone e del polso.
    static func da(_ o: [String: Any]) -> DatiCostiOlo {
        func n(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "") ?? 0 }
        func nome(_ m: String) -> String { m.contains("opus") ? "OPUS" : m.contains("sonnet") ? "SONNET" : m.contains("haiku") ? "HAIKU" : m.replacingOccurrences(of: "claude-", with: "").uppercased() }
        var d = DatiCostiOlo()
        d.mese = n(o["dollari_mese"]); d.oggi = n(o["dollari_oggi"]); d.ieri = n(o["dollari_ieri"]); d.sette = n(o["dollari_7_giorni"]); d.risposte = Int(n(o["chiamate_mese"]))
        d.modelli = (o["modelli"] as? [[String: Any]] ?? []).map { m -> (nome: String, dollari: Double, risposte: Int) in
            (nome: nome((m["modello"] as? String) ?? ""), dollari: n(m["dollari"]), risposte: Int(n(m["chiamate"])))
        }
        if let v = o["voce"] as? [String: Any] { d.voce = (Int(n(v["percento"])), "\(Olo.numero(n(v["usati"]))) DI \(Olo.numero(n(v["limite"]))) CARATTERI") }
        d.fissi = (o["fissi"] as? [[String: Any]] ?? []).map { "\(($0["nome"] as? String ?? "").uppercased()) \(($0["costo"] as? String ?? "").uppercased())" }.joined(separator: " · ")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        d.giorni = (o["giorni"] as? [[String: Any]] ?? []).compactMap { g -> (giorno: Date, dollari: Double)? in
            guard let s = g["giorno"] as? String, let data = f.date(from: s) else { return nil }
            return (giorno: data, dollari: n(g["dollari"]))
        }
        return d
    }
}

final class ProveCosti {
    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCostiOlo, piccolo: Bool) {
        switch k {
        case 1: torri(&gc, W, H, t, M, D, piccolo)
        case 2: clessidra(&gc, W, H, t, M, D, piccolo)
        default: palladio(&gc, W, H, t, M, D, piccolo)
        }
    }

    // PALLADIO: il nucleo al palladio: dieci bobine divise fra i modelli in proporzione alla spesa; l'anello interno la voce
    private func palladio(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCostiOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 1.25, sz: 0.78, su: 1.3, oscilla: 0.5, mano: 0.7, conoSu: 0.2))
        var F = FasciOlo(6)
        let Mo = D.modelli.filter { $0.dollari > 0 }, tot = max(0.01, Mo.reduce(0) { $0 + $1.dollari }), nb = s.nasce
        var quale: [Int] = []
        if !Mo.isEmpty {
            var quote = Mo.map { max(1, Int(($0.dollari / tot * 10).rounded(.down))) }
            var resto = Mo.enumerated().map { $0.element.dollari / tot * 10 - Double(quote[$0.offset]) }
            while quote.reduce(0, +) < 10, let i = resto.indices.max(by: { resto[$0] < resto[$1] }) { quote[i] += 1; resto[i] = -9 }
            while quote.reduce(0, +) > 10, let i = quote.indices.max(by: { quote[$0] < quote[$1] }) { quote[i] -= 1 }
            for (i, q) in quote.enumerated() { quale += Array(repeating: i, count: q) }
        }
        Tav.cerchio(&F, s, 1.0 * nb, 0, 3, n: 72); Tav.cerchio(&F, s, 0.9 * nb, 0, 1, n: 72); Tav.cerchio(&F, s, 0.42 * nb, 0, 2, n: 48); Tav.cerchio(&F, s, 0.3 * nb, 0, 1, n: 40)
        var bob: [(mi: Int, am: Double, p: P3)] = []
        for (k, mi) in quale.enumerated() {
            let a0 = Double(k) / 10 * OP.due + 0.05, a1 = Double(k + 1) / 10 * OP.due - 0.05, g = mi == 0 ? 4 : mi == 1 ? 3 : 2
            for q in 0...(piccolo ? 3 : 6) { let a = a0 + (a1 - a0) * Double(q) / (piccolo ? 3 : 6); F.metti(g, s.P(cos(a) * 0.48 * nb, sin(a) * 0.48 * nb, 0), s.P(cos(a) * 0.85 * nb, sin(a) * 0.85 * nb, 0)) }
            let am = (a0 + a1) / 2
            bob.append((mi, am, s.P(cos(am) * 0.66 * nb, sin(am) * 0.66 * nb, 0)))
        }
        Tav.traccia(&gc, F, piccolo)
        let c = s.P(0, 0, 0)
        Tav.alone(&gc, c, s.sz * 0.55, 0.45 + 0.08 * sin(t * 2.5), Tav.bianco)
        if let v = D.voce {
            let vf = Double(v.percento) / 100 * OP.due * OP.lis(t / 1.4)
            gc.stroke(Tav.spezzata((0...40).map { q in let a = -1.5708 + vf * Double(q) / 40; return s.P(cos(a) * 0.36, sin(a) * 0.36, 0) }), with: .color(OP.b(0.9)), lineWidth: 2)
        }
        guard !piccolo else { return }
        OP.scritta(&gc, "\(Tav.soldi(D.mese)) $", c.x, c.y + 4, 12, 800, OP.b(0.98))
        OP.scritta(&gc, "QUESTO MESE", c.x, c.y + 14, 5.5, 700, OP.c(0.8))
        for (k, b) in bob.enumerated() {
            let q = s.P(cos(b.am) * 0.95, sin(b.am) * 0.95, 0)
            OP.scritta(&gc, String(Mo[b.mi].nome.prefix(1)), q.x, q.y + 3, 7, 800, b.mi == 0 ? OP.b(0.95) : b.mi == 1 ? Tav.a(Tav.oro, 0.95) : OP.c(0.85))
            M.zona(b.p.x, b.p.y, 13, k)
        }
        Tav.testate(&gc, W, "NUCLEO AL PALLADIO", "\(Tav.soldi(D.mese)) $", "\(D.risposte) RISPOSTE\(D.voce.map { " · VOCE \($0.percento)%" } ?? "")")
        OP.scritta(&gc, Mo.prefix(3).map { "\($0.nome.prefix(1)) \($0.nome)" }.joined(separator: " · "), 10, H - 12, 6, 700, OP.c(0.85), .leading)
        if let k = M.scelta, k >= 0, k < bob.count {
            let m = Mo[bob[k].mi]
            OP.riquadro(&gc, W, H, bob[k].p.x, bob[k].p.y, [m.nome, "\(Tav.soldi(m.dollari)) $ · \(Int((m.dollari / tot * 100).rounded()))% DEL CERVELLO",
                                                             "\(m.risposte) RISPOSTE · \(Tav.soldi(m.dollari / Double(max(1, m.risposte)) * 100)) $ OGNI 100"], t - M.sceltaT, codice: "BOBINA")
        }
    }

    // TORRI: i giorni del mese come grattacieli (alta quanto si è speso), oggi in fondo e acceso; la linea della media
    private func torri(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCostiOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.38, sz: 1.15, su: 0.15, oscilla: 0.3, mano: 0.6, rx: 0.34, cono: false))
        var F = FasciOlo(6)
        let G = D.giorni, n = G.count
        guard n > 0 else { if !piccolo { Tav.testate(&gc, W, "SKYLINE DEI COSTI", "OGGI \(Tav.soldi(D.oggi)) $", "IERI \(Tav.soldi(D.ieri)) · 7 GIORNI \(Tav.soldi(D.sette))") }; return }
        let mx = max(0.01, G.map { $0.dollari }.max() ?? 0.01), med = D.mese / Double(n)
        var tor: [(v: Double, i: Int, top: P3)] = []
        for (i, g) in G.enumerated() {
            let cx = n > 1 ? -1.05 + Double(i) / Double(n - 1) * 2.1 : 0, cy = 0.1 * sin(Double(i) * 1.3), h = g.dollari / mx * 0.95 * OP.lis((t - Double(i) * 0.03) / 0.6), w = 0.035
            let gg = i == n - 1 ? 4 : g.dollari > med * 1.4 ? 3 : 1
            let c: [(Double, Double)] = [(-w, -w), (w, -w), (w, w), (-w, w)]
            for (k, (a, b)) in c.enumerated() { let (a2, b2) = c[(k + 1) % 4]; F.metti(gg, s.P(cx + a, cy + b, h), s.P(cx + a2, cy + b2, h)); F.metti(gg - 1, s.P(cx + a, cy + b, 0), s.P(cx + a, cy + b, h)) }
            tor.append((g.dollari, i, s.P(cx, cy, h)))
        }
        let hm = med / mx * 0.95
        F.metti(2, s.P(-1.1, 0, hm), s.P(1.1, 0, hm))
        for i in -5...5 { F.metti(0, s.P(Double(i) * 0.22, -0.35, 0), s.P(Double(i) * 0.22, 0.35, 0)) }
        Tav.traccia(&gc, F, piccolo)
        if let o = tor.last?.top { Tav.alone(&gc, o, 9 + 2 * sin(t * 4), 0.85, Tav.bianco) }
        guard !piccolo else { return }
        let pm = s.P(1.1, 0, hm)
        OP.scritta(&gc, "MEDIA \(Tav.soldi(med))", pm.x + 3, pm.y - 3, 5.5, 700, OP.c(0.8), .leading)
        for q in tor { M.zona(q.top.x, q.top.y, 8, q.i) }
        Tav.testate(&gc, W, "SKYLINE DEI COSTI", "OGGI \(Tav.soldi(D.oggi)) $", "IERI \(Tav.soldi(D.ieri)) · 7 GIORNI \(Tav.soldi(D.sette))")
        if let i = M.scelta, i >= 0, i < tor.count {
            let q = tor[i], d = G[i].giorno, cal = Calendar.current
            let titolo = "\(cal.component(.day, from: d)) \(OP.mesi[max(0, min(11, cal.component(.month, from: d) - 1))])\(i == n - 1 ? " · OGGI" : "")"
            OP.riquadro(&gc, W, H, q.top.x, q.top.y, [titolo, "\(Tav.soldi(q.v)) $", q.v > med * 1.4 ? "GIORNO PESANTE" : q.v < med * 0.7 ? "GIORNO LEGGERO" : "NELLA MEDIA"], t - M.sceltaT, codice: "TORRE")
        }
    }

    // CLESSIDRA: sopra i giorni che restano, sotto la sabbia spesa; a questo ritmo, quanto a fine mese
    private func clessidra(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCostiOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.2, sz: 0.7, su: 0, giro: 0.2, conoSu: -0.2, conoW: 0.6))
        var F = FasciOlo(6)
        let cal = Calendar.current, oggi = Date(), giorno = cal.component(.day, from: oggi), giorniMese = cal.range(of: .day, in: .month, for: oggi)?.count ?? 30
        let k = Double(giorno) / Double(giorniMese), prev = D.mese / Double(max(1, giorno)) * Double(giorniMese)
        let prof = { (u: Double) -> Double in 0.08 + 0.5 * pow(abs(u), 0.9) }, Z = { (u: Double) -> Double in (1 + u) * 0.95 * s.nasce + 0.05 }
        for q in -10...10 { let u = Double(q) / 10; Tav.cerchio(&F, s, prof(u), Z(u), abs(q) == 10 ? 3 : 0, n: piccolo ? 18 : 28) }
        for m in 0..<8 { let a = Double(m) / 8 * OP.due; var q: P3?; for j in -10...10 { let u = Double(j) / 10, p = s.P(cos(a) * prof(u), sin(a) * prof(u), Z(u)); if let q { F.metti(1, q, p) }; q = p } }
        for z in [0, Z(1) + 0.05] { Tav.cerchio(&F, s, 0.68, z, 3, n: 36) }
        for m in 0..<3 { let a = Double(m) / 3 * OP.due + 0.5; F.metti(2, s.P(cos(a) * 0.66, sin(a) * 0.66, 0), s.P(cos(a) * 0.66, sin(a) * 0.66, Z(1) + 0.05)) }
        func sabbia(_ u0: Double, _ u1: Double, _ g: Int) { for q in 0...8 { let u = u0 + (u1 - u0) * Double(q) / 8; Tav.cerchio(&F, s, prof(u) * 0.92, Z(u), g, n: 24) } }
        sabbia(-1, -1 + k * 0.85, 4); sabbia(0.05, 0.05 + (1 - k) * 0.85, 3)
        Tav.traccia(&gc, F, piccolo)
        let a = s.P(0, 0, Z(0.05)), b = s.P(0, 0, Z(-1 + k * 0.85))
        Tav.segmento(&gc, a, b, OP.b(0.8), 1.2, tratteggio: [2, 2], fase: CGFloat(-t * 20))
        Tav.alone(&gc, b, 14, 0.5, Tav.bianco)
        guard !piccolo else { return }
        let ps = s.P(0, 0, Z(0.5)), pg = s.P(0, 0, Z(-0.5))
        OP.scritta(&gc, "\(giorniMese - giorno) GIORNI", ps.x + s.sz * 0.75, ps.y, 7, 800, OP.c(0.95), .leading)
        OP.scritta(&gc, "ANCORA", ps.x + s.sz * 0.75, ps.y + 9, 5.5, 600, OP.c(0.7), .leading)
        OP.scritta(&gc, "\(Tav.soldi(D.mese)) $", pg.x - s.sz * 0.75, pg.y, 7, 800, OP.b(0.95), .trailing)
        OP.scritta(&gc, "SPESI", pg.x - s.sz * 0.75, pg.y + 9, 5.5, 600, OP.c(0.7), .trailing)
        M.zona(ps.x, (ps.y + pg.y) / 2, s.sz * 0.8, 0)
        Tav.testate(&gc, W, "CLESSIDRA DEL MESE", "≈ \(Tav.soldi(prev)) $", "A FINE MESE, A QUESTO RITMO")
        if M.scelta == 0 {
            OP.riquadro(&gc, W, H, a.x, a.y, ["GIORNO \(giorno) DI \(giorniMese)", "SPESI \(Tav.soldi(D.mese)) $ · \(Tav.soldi(D.mese / Double(max(1, giorno)))) AL GIORNO",
                                               "PREVISIONE \(Tav.soldi(prev)) $", OP.taglia(D.fissi, 40)], t - M.sceltaT, codice: "MESE")
        }
    }
}
