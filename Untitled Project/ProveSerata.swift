import Foundation
import SwiftUI

// MARK: - SERATA · DA DOVE ARRIVANO I SOLDI · le tre prove (mockup v262–v264): FLUSSO, TORRI, REATTORE
// Le voci dell'incasso della serata scelta (ingressi contanti e POS, Resident Advisor, bar contanti e POS) e il totale. Toccata una
// voce: il riquadro col valore, la quota sul totale e il posto in classifica.

extension DatiSoldi {
    /// righeVoceSerata: le righe del riquadro di una voce.
    func righe(_ i: Int) -> [String] {
        let f = fonti[i]
        let ord = (fonti.sorted { $0.valore > $1.valore }.firstIndex { $0.nome == f.nome } ?? 0) + 1
        return [f.nome.uppercased(), OP.euro(f.valore), "\(Olo.numero(f.valore / max(1, totale) * 100, decimali: 1))% DEL TOTALE · \(ord)ª VOCE"]
    }

    /// Quanto vale una moneta: 100 € come il mockup; con incassi grandi il primo taglio tondo che tiene la torre più alta entro
    /// 16 monete (altrimenti uscirebbe dalla tela).
    var moneta: Double {
        let massimo = fonti.map(\.valore).max() ?? 0
        for v in [100.0, 200, 250, 500, 1000, 2000, 2500, 5000, 10000] where massimo / v <= 16 { return v }
        return 20000
    }
}

/// Le tre prove della serata.
final class ProveSerata {
    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: DatiSoldi, piccolo: Bool) {
        guard !S.fonti.isEmpty, S.totale > 0 else { return }
        switch k {
        case 1: torri(&gc, W, H, t, M, S, piccolo)
        case 2: reattore(&gc, W, H, t, M, S, piccolo)
        default: flusso(&gc, W, H, t, M, S, piccolo)
        }
    }

    // MARK: SE1 · FLUSSO — i soldi che scorrono: a sinistra le voci (una barra alta quanto vale), a destra l'incasso; ogni voce manda la
    // sua corrente di luce, larga quanto vale, con le monete che ci corrono dentro (più fitte dove arrivano più soldi). Toccata una voce,
    // la sua corrente si accende e il riquadro dice quanto e che quota.

    private struct Banda { let a0: Double; let a1: Double; let b0: Double; let b1: Double; let v: Double; let nome: String }

    private func flusso(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: DatiSoldi, _ piccolo: Bool) {
        let n = S.fonti.count, tot = S.totale
        let sz = piccolo ? W * 0.3 : min(W * 0.28, H * 0.5), cx = piccolo ? W / 2 - 0.16 * sz : W / 2 - 4, cy = H * 0.5
        let ang = 0.12 * sin(t * 0.22) + M.giro * 0.6, al = 0.12
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let alto = 1.7, gap = 0.14, unit = (alto - gap * Double(n - 1)) / tot, cresce = OP.lis(t / 1.0), Zt = (alto - gap * Double(n - 1)) / 2
        var za = alto / 2, zb = Zt
        var bande: [Banda] = []
        for f in S.fonti {
            let h = max(0, f.valore) * unit
            bande.append(Banda(a0: za, a1: za - h, b0: zb, b1: zb - h, v: f.valore, nome: f.nome))
            za -= h + gap
            zb -= h
        }
        let xa = -0.62, xb = 0.92, moneta = S.moneta
        var F = FasciOlo(6)
        // la barra del totale
        F.metti(3, P(xb, 0, Zt), P(xb, 0, -Zt))
        F.metti(3, P(xb + 0.08, 0, Zt), P(xb + 0.08, 0, -Zt))
        // la corrente: due bordi a S e il velo in mezzo
        let curva = { (z0: Double, z1: Double, u: Double) -> P3 in
            let e = u * u * (3 - 2 * u)
            return P(xa + (xb - xa) * u, 0, z0 + (z1 - z0) * e)
        }
        for (i, b) in bande.enumerated() {
            let scelta = M.scelta == i, g = scelta ? 4 : 2, fino = cresce
            F.metti(g, P(xa, 0, b.a0), P(xa, 0, b.a1))
            F.metti(g, P(xa - 0.06, 0, b.a0), P(xa - 0.06, 0, b.a1))
            let bordi: [(z0: Double, z1: Double)] = [(b.a0, b.b0), (b.a1, b.b1)]
            for e in bordi {
                var q: P3?
                for k in 0...30 { let o = curva(e.z0, e.z1, Double(k) / 30 * fino); if let q { F.metti(scelta ? 3 : 1, q, o) }; q = o }
            }
            var velo = Path()
            for k in 0...30 {
                let o = curva(b.a0, b.b0, Double(k) / 30 * fino)
                if k == 0 { velo.move(to: CGPoint(x: o.x, y: o.y)) } else { velo.addLine(to: CGPoint(x: o.x, y: o.y)) }
            }
            for k in stride(from: 30, through: 0, by: -1) { let o = curva(b.a1, b.b1, Double(k) / 30 * fino); velo.addLine(to: CGPoint(x: o.x, y: o.y)) }
            velo.closeSubpath()
            gc.fill(velo, with: .color(OP.s(scelta ? 0.2 : 0.07)))
            // le monete che corrono: tante quante monete vale la voce (sul polso al massimo 12)
            let quante = min(piccolo ? 12 : 400, max(0, Int((b.v / moneta).rounded())))
            for k in 0..<quante {
                let u = (t * 0.32 + Double(k) / Double(quante) + Double(i) * 0.13).truncatingRemainder(dividingBy: 1) * fino
                let frz = 0.2 + 0.6 * OP.caso(i * 97 + k), z0 = b.a0 + (b.a1 - b.a0) * frz, z1 = b.b0 + (b.b1 - b.b0) * frz
                F.metti(scelta ? 5 : 4, curva(z0, z1, max(0, u - 0.04)), curva(z0, z1, u))
            }
            if !piccolo { let c = P(xa - 0.03, 0, (b.a0 + b.a1) / 2); M.zona(c.x - 20, c.y, 20, i) }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.62) : OP.c(0.1 + 0.17 * Double($0)) },
                spessore: { 0.8 + Double($0) * 0.15 }, alone: { $0 >= 4 ? OP.s(0.07) : nil })
        if !piccolo {
            for (i, b) in bande.enumerated() {
                let c = P(xa - 0.1, 0, (b.a0 + b.a1) / 2), scelta = M.scelta == i
                OP.dentro(&gc, W, b.nome.uppercased(), c.x - 2, c.y - 1, 6.5, 700, scelta ? OP.b(1) : OP.c(0.75), .trailing)
                OP.dentro(&gc, W, OP.euro(b.v), c.x - 2, c.y + 8, 7, 700, OP.b(0.9), .trailing)
            }
        }
        let pt = P(xb + 0.14, 0, 0), batte = 0.5 + 0.5 * sin(t * 2.2)
        OP.alone(&gc, pt.x, pt.y, (piccolo ? 8 : 24) + 6 * batte, 0.35, bianco: true)
        guard !piccolo else { return }
        OP.scritta(&gc, OP.euro((tot * cresce).rounded()), pt.x + 4, pt.y + 2, 11, 700, OP.b(1), .leading)
        OP.scritta(&gc, "INCASSO", pt.x + 4, pt.y + 12, 6.5, 600, OP.c(0.8), .leading)
        if let k = M.scelta, k < n {
            let b = bande[k], c = P(0, 0, (b.a0 + b.b1) / 2)
            OP.riquadro(&gc, W, H, c.x, c.y, S.righe(k), t - M.sceltaT, codice: "VOCE \(k + 1)/\(n)")
        }
    }

    // MARK: SE2 · TORRI — le voci come torri di monete su un piatto che gira: ogni moneta vale 100 € (o il taglio scritto in alto), la
    // torre più alta ha la corona di luce; sopra, il valore. In alto a sinistra l'incasso. Toccata una torre, il riquadro.

    private func torri(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: DatiSoldi, _ piccolo: Bool) {
        let fonti = S.fonti, n = fonti.count
        let cx = W / 2, cy = H * (piccolo ? 0.66 : 0.72), sz = piccolo ? W * 0.34 : min(W * 0.27, H * 0.44), ang = t * 0.18 + M.giro, al = 0.34
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let massimo = fonti.map(\.valore).max() ?? 1, sale = OP.lis(t / 1.3), moneta = S.moneta
        OP.ghiera(&F, { a, r, z in P(cos(a) * r, sin(a) * r, z) }, 1.2, 0, 100, 5, lunga: 0.06, corta: 0.03)
        var cime: [(c: P3, i: Int)] = []
        for (i, f) in fonti.enumerated() {
            let a = Double(i) / Double(n) * OP.due, px = cos(a) * 0.78, py = sin(a) * 0.78
            let monete = max(0, Int((f.valore / moneta).rounded())), mostrate = Int((Double(monete) * sale).rounded(.up)), scelta = M.scelta == i
            let dav = P(px, py, 0).z < 0
            for k in 0..<mostrate {
                let z = Double(k) * 0.072, cima = k == mostrate - 1, g = (dav ? 1 : 0) + (cima ? 2 : 0) + (scelta ? 2 : 0)
                var q: P3?
                var disco = Path()
                for s in 0...18 {
                    let b = Double(s) / 18 * OP.due, o = P(px + cos(b) * 0.15, py + sin(b) * 0.15, z)
                    if let q { F.metti(g, q, o); disco.addLine(to: CGPoint(x: o.x, y: o.y)) } else { disco.move(to: CGPoint(x: o.x, y: o.y)) }
                    q = o
                }
                gc.fill(disco, with: .color(OP.s(scelta ? 0.07 : 0.035)))
            }
            let top = Double(mostrate) * 0.072
            for b in [0, 1.57, 3.14, 4.71] {
                F.metti(dav ? 1 : 0, P(px + cos(b) * 0.15, py + sin(b) * 0.15, 0), P(px + cos(b) * 0.15, py + sin(b) * 0.15, top))
            }
            if f.valore == massimo && sale > 0.95 {                     // la corona della torre più alta
                var q: P3?
                for s in 0...24 {
                    let b = Double(s) / 24 * OP.due + t, o = P(px + cos(b) * 0.22, py + sin(b) * 0.22, top + 0.12 + 0.02 * sin(t * 3))
                    if let q, s % 2 == 1 { F.metti(5, q, o) }
                    q = o
                }
            }
            let c = P(px, py, top + (f.valore == massimo ? 0.2 : 0.04))
            cime.append((c: c, i: i))
            if !piccolo { M.zona(c.x, c.y + 18, 22, i) }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.65) : OP.c(0.1 + 0.17 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.14 }, alone: { $0 >= 4 ? OP.s(0.07) : nil })
        guard !piccolo else { return }
        // sopra ogni torre il valore e la sigla, senza sovrapporsi
        let L: [(x: Double, y: Double, w: Double, h: Double)] = cime.map { q in
            (x: q.c.x, y: q.c.y - 4, w: Double(OP.euro(fonti[q.i].valore).count) * 4.6 + 4, h: 18)
        }
        let dy = OP.posaEtichette(L)
        for (k, q) in cime.enumerated() {
            let f = fonti[q.i], scelta = M.scelta == q.i
            let sigla = f.nome.split(separator: " ").compactMap { $0.first }.map { String($0) }.joined().uppercased()
            OP.scritta(&gc, OP.euro(f.valore), q.c.x, q.c.y - 6 + dy[k], 7.5, 700, scelta || f.valore == massimo ? OP.b(1) : OP.c(0.8))
            OP.scritta(&gc, sigla, q.c.x, q.c.y + 4 + dy[k], 6, 600, OP.c(0.55))
        }
        OP.scritta(&gc, OP.euro((S.totale * sale).rounded()), 10, 18, 13, 700, OP.b(1), .leading)
        OP.scritta(&gc, "INCASSO", 10, 29, 6.5, 600, OP.c(0.8), .leading)
        OP.scritta(&gc, "1 MONETA = \(OP.euro(moneta))", W - 10, 14, 7, 600, OP.c(0.75), .trailing)
        if let k = M.scelta, let q = cime.first(where: { $0.i == k }) {
            OP.riquadro(&gc, W, H, q.c.x, q.c.y, S.righe(k), t - M.sceltaT, codice: "TORRE \(k + 1)/\(n)")
        }
    }

    // MARK: SE3 · REATTORE — l'incasso come il reattore di Tony: le voci sono i settori dell'anello, lunghi quanto valgono, con le spire;
    // l'energia corre da ogni settore al nucleo (più svelta dove arrivano più soldi) e il nucleo è l'incasso. Toccato un settore, il
    // riquadro.

    private func reattore(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: DatiSoldi, _ piccolo: Bool) {
        let fonti = S.fonti, n = fonti.count, tot = S.totale
        let cx = W / 2, sz = piccolo ? W * 0.4 : min(W * 0.3, (H - 34) / 2.05), cy = piccolo ? H * 0.5 : 20 + 0.8 * sz, ang = t * 0.08 + M.giro, al = 0.88
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let pol = { (a: Double, r: Double) -> P3 in P(cos(a) * r, sin(a) * r, 0) }
        var F = FasciOlo(6)
        let sale = OP.lis(t / 1.1), gap = 0.06, totA = OP.due - gap * Double(n), massimo = max(1, fonti.map(\.valore).max() ?? 1)
        OP.ghiera(&F, { a, r, z in P(cos(a) * r, sin(a) * r, z) }, 1.1, 0, 120, 6, lunga: 0.05, corta: 0.025)
        for r in [0.38, 0.5] {
            var q: P3?
            for i in 0...72 { let o = pol(Double(i) / 72 * OP.due, r); if let q { F.metti(r < 0.4 ? 3 : 1, q, o) }; q = o }
        }
        var angolo = -Double.pi / 2
        var centri: [(c: P3, i: Int)] = []
        for (i, f) in fonti.enumerated() {
            let span = totA * max(0, f.valore) / tot * sale, a0 = angolo, a1 = angolo + span, scelta = M.scelta == i, forte = f.valore / massimo
            let g = 1 + Int((forte * 2).rounded()) + (scelta ? 2 : 0)
            for r in [0.62, 0.98] {
                var q: P3?
                for k in 0...30 { let o = pol(a0 + span * Double(k) / 30, r); if let q { F.metti(g, q, o) }; q = o }
            }
            F.metti(g, pol(a0, 0.62), pol(a0, 0.98))
            F.metti(g, pol(a1, 0.62), pol(a1, 0.98))
            let spire = max(3, Int((span * 9).rounded()))
            for k in 1..<spire { let b = a0 + span * Double(k) / Double(spire); F.metti(max(0, g - 1), pol(b, 0.66), pol(b, 0.94)) }
            // l'energia verso il nucleo
            let vel = 0.5 + 0.9 * forte
            for k in 0..<3 {
                let u = (t * vel + Double(k) / 3 + Double(i) * 0.21).truncatingRemainder(dividingBy: 1)
                let b = a0 + span * (0.25 + 0.5 * OP.caso(i * 13 + k)), r0 = 0.6 - u * 0.2
                F.metti(5, pol(b, r0), pol(b, r0 - 0.05))
            }
            let am = a0 + span / 2, c = pol(am, 0.8)
            centri.append((c: c, i: i))
            if !piccolo {
                let et = pol(am, 1.26)
                OP.dentro(&gc, W, f.nome.uppercased(), et.x, et.y - 1, 6, 700, scelta ? OP.b(1) : OP.c(0.7))
                OP.dentro(&gc, W, OP.euro(f.valore), et.x, et.y + 8, 7, 700, OP.b(0.85))
                M.zona(c.x, c.y, 22, i)
            }
            angolo = a1 + gap
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.7) : OP.c(0.1 + 0.18 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.16 }, alone: { $0 >= 3 ? OP.s(0.07) : nil })
        let nc = P(0, 0, 0), batte = 0.5 + 0.5 * sin(t * 2.6)
        OP.alone(&gc, nc.x, nc.y, (piccolo ? 12 : 40) + 8 * batte, 0.45 + 0.15 * batte, bianco: true)
        guard !piccolo else { return }
        OP.scritta(&gc, OP.euro((tot * sale).rounded()), nc.x, nc.y + 4, 13, 700, OP.b(1))
        OP.scritta(&gc, "INCASSO", nc.x, nc.y + 14, 6.5, 600, OP.c(0.8))
        if let k = M.scelta, let q = centri.first(where: { $0.i == k }) {
            OP.riquadro(&gc, W, H, q.c.x, q.c.y, S.righe(k), t - M.sceltaT, codice: "SETTORE \(k + 1)/\(n)")
        }
    }
}

/// L'ologramma dei soldi della serata con le sue tre prove (iPhone: grande, con le chip; polso: piccolo, la prova scelta sull'iPhone).
struct OlogrammaSerataProve: View {
    let dati: DatiSoldi
    var piccolo = false
    @State private var prove = ProveSerata()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .serata) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .serata, altezza: 260, margini: EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0),
                          crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
