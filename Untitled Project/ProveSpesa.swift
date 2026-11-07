import Foundation
import SwiftUI

// MARK: - SPESA · le tre prove (mockup v262–v264): CASSA, SCAFFALE, ANELLO

/// Le cose della lista come il mockup: il nome, la quantità e se è già presa. Toccata una cosa nell'ologramma è come toccarla nella
/// lista: `tocca` (l'id della voce) la spunta o la rimette, con il suo suono.
struct SpesaOlo {
    struct Voce { let id: Int; let nome: String; let qta: String; let presa: Bool }
    var voci: [Voce] = []
    var tocca: ((Int) -> Void)?

    /// cortoSpesa: la prima parola in maiuscolo (al massimo 9 lettere).
    static func corto(_ n: String) -> String {
        let p = (n.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map { String($0) } ?? n).uppercased()
        return p.count > 9 ? String(p.prefix(8)) + "…" : p
    }
}

/// Le tre prove della spesa: ognuna anima il passaggio di una cosa da «da prendere» a «presa» (e ritorno).
final class ProveSpesa {
    private struct Stato { var presa: Bool; var t0: Double }
    private var stati: [Int: Stato] = [:]          // per id della voce
    private var ultimoT = 0.0

    func crea(_ k: Int) { stati = [:]; ultimoT = 0 }

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: SpesaOlo, piccolo: Bool) {
        if t < ultimoT { stati = [:] }             // la tela è ripartita da capo (sul polso: un'altra prova)
        ultimoT = t
        aggiorna(S.voci, t)
        if !piccolo { tocchi(M, S) }
        switch k {
        case 1: scaffale(&gc, W, H, t, M, S, piccolo)
        case 2: anello(&gc, W, H, t, M, S, piccolo)
        default: cassa(&gc, W, H, t, M, S, piccolo)
        }
    }

    /// statiSpesaOlo: i cambi di stato (presa / da prendere) con l'istante, per animare il passaggio.
    private func aggiorna(_ V: [SpesaOlo.Voce], _ t: Double) {
        for v in V {
            if let s = stati[v.id] {
                if s.presa != v.presa { stati[v.id] = Stato(presa: v.presa, t0: t) }
            } else {
                stati[v.id] = Stato(presa: v.presa, t0: -9)
            }
        }
    }

    /// Quando la voce ha cambiato stato l'ultima volta (-9: mai, da quando l'ologramma c'è).
    private func cambio(_ v: SpesaOlo.Voce) -> Double { stati[v.id]?.t0 ?? -9 }

    /// tocchiSpesa: il tocco su una cosa la spunta o la rimette (niente riquadro: è già l'azione).
    private func tocchi(_ M: ManoOlo, _ S: SpesaOlo) {
        guard let tocca = S.tocca else { M.suTocco = nil; return }
        let V = S.voci
        M.suTocco = { k in
            guard V.indices.contains(k) else { return false }
            tocca(V[k].id)
            return true
        }
    }

    /// scatolaOlo: uno scatolone (una cosa della lista), 12 spigoli, girato di `giro`.
    private static let vertici: [P3] = [P3(-1, -1, -1), P3(1, -1, -1), P3(1, 1, -1), P3(-1, 1, -1),
                                        P3(-1, -1, 1), P3(1, -1, 1), P3(1, 1, 1), P3(-1, 1, 1)]
    private static let spigoli: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]

    private func scatola(_ F: inout FasciOlo, _ P: (Double, Double, Double) -> P3, _ px: Double, _ py: Double, _ pz: Double,
                         _ r: Double, _ giro: Double, _ g: Int) {
        let ca = cos(giro), sa = sin(giro)
        let V: [P3] = ProveSpesa.vertici.map { q in P(px + (q.x * ca - q.y * sa) * r, py + (q.x * sa + q.y * ca) * r, pz + q.z * r * 0.85) }
        for (i, j) in ProveSpesa.spigoli { F.metti(g + (V[i].z + V[j].z < 0 ? 1 : 0), V[i], V[j]) }
    }

    /// In alto: quante ne mancano e quante sono prese.
    private func testata(_ gc: inout GraphicsContext, _ W: Double, _ n: Int, _ presi: Int) {
        if n > 0 { OP.scritta(&gc, "DA PRENDERE \(n - presi)", 10, 14, 8, 700, OP.c(0.9), .leading) }   // 7 nov: «lista vuota» solo sotto il titolo
        if n > 0 { OP.scritta(&gc, "PRESE \(presi) SU \(n)", W - 10, 14, 8, 700, presi == n ? OP.b(1) : OP.c(0.85), .trailing) }
    }

    // MARK: SP1 · CASSA — la cassa automatica: le cose da prendere aspettano sul nastro, che scorre; toccata una, passa nell'arco dello
    // scanner (il laser la legge, lampo e ✓) e cade nella borsa. Toccata nella borsa, torna sul nastro. Sopra, quante ne mancano.

    private func cassa(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: SpesaOlo, _ piccolo: Bool) {
        let V = S.voci
        let cx = W * 0.47, cy = H * 0.6, sz = piccolo ? W * 0.29 : min(W * 0.235, H * 0.35), ang = -0.28 + 0.06 * sin(t * 0.3) + M.giro, al = 0.45
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let quota = 0.3, sulNastro = V.filter { !$0.presa }, inBorsa = V.filter { $0.presa }
        let x0 = -0.32 - Double(max(3, sulNastro.count - 1)) * 0.3 - 0.22          // il nastro lungo quanto la fila
        // il nastro: i bordi, i rulli che scorrono, le gambe
        for y in [-0.26, 0.26] { F.metti(2, P(x0, y, quota), P(0.3, y, quota)) }
        let sc = (t * 0.35).truncatingRemainder(dividingBy: 0.14)
        for k in -1..<24 {
            let xr = x0 + Double(k) * 0.14 + sc
            if xr < x0 || xr > 0.3 { continue }
            F.metti(0, P(xr, -0.26, quota), P(xr, 0.26, quota))
        }
        let gambe: [(x: Double, y: Double)] = [(x0 + 0.1, -0.22), (x0 + 0.1, 0.22), (0.2, -0.22), (0.2, 0.22)]
        for g in gambe { F.metti(0, P(g.x, g.y, 0), P(g.x, g.y, quota)) }
        // lo scanner: l'arco e la riga del laser che scende e sale
        let ax = 0.0
        var lampi = 0.0
        for v in V { lampi = max(lampi, max(0, 1 - abs((t - cambio(v)) - 0.42) / 0.12)) }
        for y in [-0.34, 0.34] { F.metti(3, P(ax, y, quota), P(ax, y, quota + 0.62)) }
        F.metti(3, P(ax, -0.34, quota + 0.62), P(ax, 0.34, quota + 0.62))
        let zl = quota + 0.06 + 0.5 * (0.5 + 0.5 * sin(t * 5.2))
        F.metti(lampi > 0.1 ? 5 : 4, P(ax, -0.32, zl), P(ax, 0.32, zl))
        // la borsa: un cesto a tronco di piramide, con il manico
        let bx = 1.0
        let bordo: [(a: Double, b: Double)] = [(-0.32, -0.26), (0.32, -0.26), (0.32, 0.26), (-0.32, 0.26)]
        for i in 0..<4 {
            let p = bordo[i], q = bordo[(i + 1) % 4]
            F.metti(2, P(bx + p.a, p.b, 0.72), P(bx + q.a, q.b, 0.72))
            F.metti(1, P(bx + p.a * 0.8, p.b * 0.8, 0), P(bx + q.a * 0.8, q.b * 0.8, 0))
            F.metti(1, P(bx + p.a, p.b, 0.72), P(bx + p.a * 0.8, p.b * 0.8, 0))
        }
        F.metti(2, P(bx - 0.2, 0, 0.72), P(bx - 0.12, 0, 1.0))
        F.metti(2, P(bx - 0.12, 0, 1.0), P(bx + 0.12, 0, 1.0))
        F.metti(2, P(bx + 0.12, 0, 1.0), P(bx + 0.2, 0, 0.72))
        // le cose: sul nastro (da prendere, in fila verso lo scanner) o nella borsa (prese); chi cambia passa dall'arco
        let posNastro = { (k: Int) -> P3 in P3(-0.32 - Double(sulNastro.count - 1 - k) * 0.3 - 0.03 * sin(t * 2 + Double(k)), 0, quota + 0.12) }
        let posBorsa = { (k: Int) -> P3 in P3(bx - 0.12 + Double(k % 2) * 0.24, (k / 2) % 2 == 1 ? 0.1 : -0.1, 0.14 + Double(k / 4) * 0.22) }
        var posizioni: [(p: P3, v: SpesaOlo.Voce, i: Int)] = []
        for (i, v) in V.enumerated() {
            let f = min(1, max(0, (t - cambio(v)) / 0.9))
            let k1 = v.presa ? (inBorsa.firstIndex { $0.id == v.id } ?? 0) : (sulNastro.firstIndex { $0.id == v.id } ?? 0)
            let dove = v.presa ? posBorsa(k1) : posNastro(k1)
            var p = dove
            if f < 1 {                                                    // all'andata: nastro → arco → borsa (al ritorno al contrario)
                let da = v.presa ? P3(-0.32, 0, quota + 0.12) : posBorsa(0), arco = P3(ax, 0, quota + 0.12)
                let a = v.presa ? da : dove, b = v.presa ? dove : da, u = v.presa ? f : 1 - f
                if u < 0.45 {
                    let e = u / 0.45
                    p = P3(a.x + (arco.x - a.x) * e, 0, a.z)
                } else {
                    let e = (u - 0.45) / 0.55
                    p = P3(arco.x + (b.x - arco.x) * e, b.y * e, arco.z + (b.z - arco.z) * e + sin(e * .pi) * 0.45)
                }
            }
            scatola(&F, P, p.x, p.y, p.z, 0.11, 0.4 + (v.presa ? 0 : t * 0.4), v.presa ? 3 : 1)
            posizioni.append((p: P(p.x, p.y, p.z + 0.18), v: v, i: i))
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.1 + 0.16 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.14 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        if lampi > 0 {
            let pa = P(ax, 0, quota + 0.3)
            OP.alone(&gc, pa.x, pa.y, piccolo ? 12 : 30, 0.7 * lampi, bianco: true)
            if !piccolo { OP.scritta(&gc, "✓ LETTO", pa.x, pa.y - 26, 8, 700, OP.b(lampi)) }
        }
        guard !piccolo else { return }
        for q in posizioni { M.zona(q.p.x, q.p.y + 12, 17, q.i) }
        // i nomi, senza sovrapporsi (chi urta sale, con il filo)
        let corti = posizioni.map { SpesaOlo.corto($0.v.nome) }
        let L: [(x: Double, y: Double, w: Double, h: Double)] = posizioni.indices.map { k in
            (x: posizioni[k].p.x, y: posizioni[k].p.y - 4, w: Double(corti[k].count) * 4 + 2, h: 8)
        }
        let dy = OP.posaEtichette(L)
        for (k, q) in posizioni.enumerated() {
            let p = q.p, d = dy[k]
            if d < -1 {
                var filo = Path()
                Olo.linea(&filo, p.x, p.y - 1, p.x, p.y - 4 + d + 3)
                gc.stroke(filo, with: .color(OP.c(0.3)), lineWidth: 1)
            }
            OP.scritta(&gc, corti[k], p.x, p.y - 2 + d, 6.5, 700, q.v.presa ? OP.b(0.9) : OP.c(0.75))
        }
        testata(&gc, W, V.count, inBorsa.count)
    }

    // MARK: SP2 · SCAFFALE — la dispensa in ologramma: uno scaffale a tre ripiani con le cose della lista al loro posto (il nome sotto);
    // il fascio di scansione lo percorre dal basso. Toccata una cosa, esce verso di noi, si accende e prende la ✓ (presa); toccata di
    // nuovo, torna da prendere.

    private func scaffale(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: SpesaOlo, _ piccolo: Bool) {
        let V = S.voci
        let cx = W / 2, cy = H * 0.66, sz = min(W * 0.28, H * 0.4), ang = -0.32 + 0.14 * sin(t * 0.25) + M.giro, al = 0.22
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let ripiani: [Double] = [0, 0.5, 1.0], L = 1.15
        for z in ripiani {
            for y in [-0.24, 0.24] { F.metti(z == 0 ? 2 : 1, P(-L, y, z), P(L, y, z)) }
            F.metti(0, P(-L, -0.24, z), P(-L, 0.24, z))
            F.metti(0, P(L, -0.24, z), P(L, 0.24, z))
        }
        let montanti: [(x: Double, y: Double)] = [(-L, -0.24), (L, -0.24), (-L, 0.24), (L, 0.24)]
        for m in montanti { F.metti((m.x < 0) == (m.y < 0) ? 2 : 1, P(m.x, m.y, 0), P(m.x, m.y, 1.4)) }
        // la scansione che sale sugli scaffali
        let zs = (t * 0.45).truncatingRemainder(dividingBy: 1.6) - 0.1
        if zs > 0 && zs < 1.4 {
            F.metti(4, P(-L, -0.28, zs), P(L, -0.28, zs))
            F.metti(4, P(-L, -0.28, zs), P(-L, 0.28, zs))
            F.metti(4, P(L, -0.28, zs), P(L, 0.28, zs))
        }
        let colonne = max(1, (V.count + 2) / 3)
        var etichette: [(p: P3, v: SpesaOlo.Voce)] = []
        for (i, v) in V.enumerated() {
            let r = i % 3, c = i / 3, px = -L + (Double(c) + 0.5) * (2 * L / Double(colonne)), z = ripiani[2 - r] + 0.13, t0 = cambio(v)
            let f = min(1, max(0, (t - t0) / 0.5))
            let fuori = v.presa ? 1 - (1 - f) * (1 - f) : 1 - f
            let esce = t0 > 0 ? sin(f * .pi) * 0.35 : 0
            let py = -0.05 - 0.28 * fuori - esce, vicino = exp(-pow((z - zs) / 0.12, 2))
            scatola(&F, P, px, py, z, 0.12, 0, v.presa ? 3 + (vicino > 0.4 ? 1 : 0) : vicino > 0.4 ? 2 : 0)
            if v.presa {                                                  // la ✓ sulla faccia davanti
                let a = P(px - 0.05, py - 0.13, z + 0.01), b = P(px - 0.01, py - 0.13, z - 0.04), c2 = P(px + 0.07, py - 0.13, z + 0.07)
                F.metti(5, a, b)
                F.metti(5, b, c2)
            }
            let et = P(px, py - 0.12, z - 0.17)
            etichette.append((p: et, v: v))
            if !piccolo { M.zona(et.x, et.y - 10, 17, i) }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.1 + 0.16 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.14 }, alone: { $0 >= 4 ? OP.s(0.08) : nil })
        guard !piccolo else { return }
        for e in etichette {
            OP.scritta(&gc, SpesaOlo.corto(e.v.nome), e.p.x, e.p.y + 2, 6.5, 700, e.v.presa ? OP.b(0.95) : OP.c(0.7))
            if !e.v.qta.isEmpty { OP.scritta(&gc, e.v.qta, e.p.x, e.p.y + 10, 6, 600, OP.c(0.45)) }
        }
        testata(&gc, W, V.count, V.filter { $0.presa }.count)
    }

    // MARK: SP3 · ANELLO — la spesa come il reattore: un anello di settori, uno per cosa (il nome fuori), che gira piano; le cose prese sono
    // settori accesi, con le spire piene, e mandano la loro luce al nucleo, dove c'è il conto (2/4). Toccato un settore, si accende
    // (presa) o si spegne (da prendere).

    private func anello(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ S: SpesaOlo, _ piccolo: Bool) {
        let V = S.voci, n = max(1, V.count), cx = W / 2
        let sz = piccolo ? W * 0.38 : min(W * 0.31, (H - 34) / 2.17), cy = piccolo ? H * 0.5 : 26 + 0.88 * sz, ang = t * 0.12 + M.giro, al = 1.0
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let pol = { (a: Double, r: Double) -> P3 in P(cos(a) * r, sin(a) * r, 0) }
        var F = FasciOlo(6)
        let presi = V.filter { $0.presa }.count
        OP.ghiera(&F, { a, r, z in P(cos(a) * r, sin(a) * r, z) }, 1.08, 0, 120, 5, lunga: 0.05, corta: 0.025)
        var q: P3?
        for i in 0...72 { let o = pol(Double(i) / 72 * OP.due, 0.42); if let q { F.metti(2, q, o) }; q = o }
        var centri: [(c: P3, presa: Bool)] = []
        for (i, v) in V.enumerated() {
            let a0 = Double(i) / Double(n) * OP.due + 0.05, a1 = Double(i + 1) / Double(n) * OP.due - 0.05, am = (a0 + a1) / 2
            let f = min(1, max(0, (t - cambio(v)) / 0.6)), luce = v.presa ? OP.lis(f) : 1 - OP.lis(f)
            let g = 1 + Int((luce * 3).rounded())
            for r in [0.58, 0.96] {
                var o0: P3?
                for k in 0...24 { let o = pol(a0 + (a1 - a0) * Double(k) / 24, r); if let o0 { F.metti(g, o0, o) }; o0 = o }
            }
            F.metti(g, pol(a0, 0.58), pol(a0, 0.96))
            F.metti(g, pol(a1, 0.58), pol(a1, 0.96))
            let spire = 7
            for k in 1..<spire { let a = a0 + (a1 - a0) * Double(k) / Double(spire); F.metti(luce > 0.5 ? g : 0, pol(a, 0.63), pol(a, 0.91)) }
            if luce > 0.02 {                                              // la luce che va al nucleo
                let u = (t * 0.8 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                F.metti(5, pol(am, 0.58 - u * 0.14), pol(am, 0.58 - u * 0.14 - 0.06))
            }
            let c = pol(am, 0.77)
            centri.append((c: c, presa: v.presa))
            if !piccolo {
                let et = pol(am, 1.24)
                OP.dentro(&gc, W, SpesaOlo.corto(v.nome), et.x, et.y + 3, 7, 700, luce > 0.5 ? OP.b(0.95) : OP.c(0.6))
                M.zona(c.x, c.y, 20, i)
            }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.75) : OP.c(0.1 + 0.18 * Double($0)) },
                spessore: { 0.75 + Double($0) * 0.18 }, alone: { $0 >= 3 ? OP.s(0.07) : nil })
        for c in centri where c.presa { OP.alone(&gc, c.c.x, c.c.y, piccolo ? 6 : 16, 0.35, bianco: true) }
        let nc = P(0, 0, 0), batte = 0.5 + 0.5 * sin(t * 2.4), quota = Double(presi) / Double(n)
        OP.alone(&gc, nc.x, nc.y, (piccolo ? 10 : 30) + 8 * batte * quota, 0.25 + 0.4 * quota, bianco: true)
        guard !piccolo else { return }
        OP.scritta(&gc, "\(presi)/\(V.count)", nc.x, nc.y + 5, 16, 700, OP.b(1))
        OP.scritta(&gc, presi == V.count && !V.isEmpty ? "TUTTO PRESO" : "PRESE", nc.x, nc.y + 15, 6.5, 600, OP.c(0.8))
        if !V.isEmpty { OP.scritta(&gc, "DA PRENDERE \(V.count - presi)", 10, 14, 8, 700, OP.c(0.9), .leading) }   // 7 nov: niente doppioni
    }
}

/// L'ologramma della spesa con le sue tre prove (iPhone: grande, con le chip; polso: piccolo, la prova scelta sull'iPhone).
struct OlogrammaSpesaProve: View {
    let dati: SpesaOlo
    var piccolo = false
    @State private var prove = ProveSpesa()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .spesa) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .spesa, altezza: 280, crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
