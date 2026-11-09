import Foundation
import SwiftUI

// MARK: - EMAIL · l'ologramma SMISTA (mockup v267, il signore 5 nov 19:33: «gli altri belli»)
// La casella è una pila di lastre di luce sul proiettore, una per mail (la più nuova in cima), dentro un telaio: le non lette chiare,
// con la busta disegnata sopra; le lette tenui. Una lama di smistamento sale e scende lungo la pila e accende la lastra che attraversa.
// Le mail che contano (PRIORITÀ, dal cervello) girano in alto come buste in piedi, fuori dalla pila, e a turno una copia sale dalla
// pila fino a loro: smistata. All'apertura (e a ogni lista nuova: cartella, periodo, solo non lette) le lastre cadono al loro posto
// dal basso; i numeri sono scritti sopra. Toccata una lastra: mittente, oggetto, quando, se è letta. Sul polso in piccolo, senza
// scritte e senza le PRIORITÀ. Uguale al mockup (olo_extra/tre.js, smistaEmail).

/// La posta per SMISTA: le mail della lista (nil mentre apre la casella) e le PRIORITÀ.
struct PostaOlo {
    struct Mail { let nome: String; let oggetto: String; let data: String; let letta: Bool }
    struct Prio { let nome: String; let oggetto: String; let quando: String }
    let posta: [Mail]?
    let prio: [Prio]
    /// La firma della lista: cambia, le lastre ricadono.
    let firma: String?

    init(posta: [Mail]?, prio: [Prio] = []) {
        self.posta = posta
        self.prio = prio
        firma = posta.map { l in l.map { "\($0.nome)\($0.oggetto)\($0.letta ? 1 : 0)" }.joined(separator: "|") }
    }
}

/// Lo stato di SMISTA: quando è arrivata la lista (per la caduta delle lastre).
final class ProvePosta {
    private var visto = false
    private var firma: String?
    private var primo = 0.0
    private var ultimo: Double?

    func disegna(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: PostaOlo, piccolo: Bool) {
        if let u = ultimo, t < u - 0.5 { visto = false }                   // la tela è ripartita: le lastre ricadono
        ultimo = t
        let cx = W / 2, base = piccolo ? H - 3 : H - 14, rx = piccolo ? W * 0.3 : min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        if !visto || firma != D.firma { visto = true; firma = D.firma; primo = t }
        let prio: [PostaOlo.Prio] = piccolo ? [] : D.prio
        let nP = min(prio.count, 4)
        let n = D.posta.map { min($0.count, piccolo ? 8 : 14) } ?? 6
        let passo = piccolo ? 0.13 : 0.085, z0 = 0.12, wx = 0.6, wy = 0.38
        let alto = z0 + Double(max(1, n - 1)) * passo, al = piccolo ? 0.5 : 0.6
        let sz = piccolo ? W * 0.4 : min(W * 0.3, (base - 40) / (alto * cos(al) + (nP > 0 ? 0.62 : 0.2) + 0.45 * sin(al)))
        let cy = base - (piccolo ? 4 : 12), ang = -0.5 + 0.25 * sin(t * 0.18) + M.giro
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let quad = { (z: Double, ax: Double, ay: Double) -> [P3] in [P(-ax, -ay, z), P(ax, -ay, z), P(ax, ay, z), P(-ax, ay, z)] }
        var F = FasciOlo(6)
        // il telaio: quattro montanti e le traverse in cima e in fondo
        let tx = wx + 0.07, ty = wy + 0.07, zt = alto + 0.06
        let montanti: [(Double, Double)] = [(-tx, -ty), (tx, -ty), (tx, ty), (-tx, ty)]
        for (a, b) in montanti { F.metti(1, P(a, b, 0), P(a, b, zt)) }
        for z in [0, zt] {
            F.metti(1, P(-tx, -ty, z), P(tx, -ty, z)); F.metti(1, P(tx, -ty, z), P(tx, ty, z))
            F.metti(0, P(tx, ty, z), P(-tx, ty, z)); F.metti(0, P(-tx, ty, z), P(-tx, -ty, z))
        }
        // la lama di smistamento: sale e scende lungo la pila
        let zs = z0 + (0.5 - 0.5 * cos(t * 0.9)) * max(0.01, Double(n - 1) * passo)
        let lama = quad(zs, wx + 0.12, wy + 0.12)
        gc.fill(OP.poligono(lama), with: .color(OP.s(0.07)))
        for k in 0..<4 { F.metti(4, lama[k], lama[(k + 1) % 4]) }
        var centri: [(p: P3, i: Int)] = []
        if let posta = D.posta {
            for i in 0..<n {
                let m = posta[i], liv = Double(n - 1 - i), d = OP.lis((t - primo - liv * 0.045) / 0.32)   // dal basso: la più vecchia per prima
                if d <= 0 { continue }
                let z = z0 + liv * passo + (1 - d) * 0.45, vicino = abs(z - zs) < passo * 0.55, scelta = M.scelta == i
                let c = quad(z, wx, wy)
                gc.fill(OP.poligono(c), with: .color(OP.s((m.letta ? 0.025 : 0.07) * d + (scelta ? 0.16 : 0) + (vicino ? 0.06 : 0))))
                let g = (m.letta ? 1 : 3) + (vicino ? 1 : 0) + (scelta ? 1 : 0)
                for k in 0..<4 { F.metti(g, c[k], c[(k + 1) % 4]) }
                if !m.letta { let v = P(0, wy * 0.15, z); F.metti(g, c[3], v); F.metti(g, v, c[2]) }   // la busta: il lembo
                centri.append((p: P(0, -wy, z), i: i))
            }
        } else {
            for i in 0..<n {                                              // apro la casella: lastre fantasma che respirano
                let z = z0 + Double(i) * passo, c = quad(z, wx, wy), g = abs(z - zs) < passo * 0.55 ? 2 : 0
                for k in 0..<4 where (k + i + Int(t * 4)) % 2 == 0 { F.metti(g, c[k], c[(k + 1) % 4]) }
            }
        }
        // le PRIORITÀ: girano in alto, in piedi come buste; a turno una copia sale dalla pila e le raggiunge
        let pz = zt + 0.42
        var posti: [P3] = []
        let busta = { (c: P3) -> [P3] in [P(c.x - 0.2, c.y, c.z - 0.13), P(c.x + 0.2, c.y, c.z - 0.13), P(c.x + 0.2, c.y, c.z + 0.13), P(c.x - 0.2, c.y, c.z + 0.13)] }
        for j in 0..<nP {
            let a = t * 0.35 + Double(j) * OP.due / Double(nP)
            let pc = P3(cos(a) * 0.98, sin(a) * 0.98, pz + 0.05 * sin(t * 1.3 + Double(j)))
            let c = busta(pc), scelta = M.scelta == 100 + j
            gc.fill(OP.poligono(c), with: .color(OP.s(0.12 + (scelta ? 0.18 : 0))))
            for k in 0..<4 { F.metti(5, c[k], c[(k + 1) % 4]) }
            let v = P(pc.x, pc.y, pc.z - 0.01)
            F.metti(4, c[3], v); F.metti(4, v, c[2])
            F.metti(1, P(0, 0, zt), P(pc.x, pc.y, pc.z - 0.13))
            // la copia che sale (ogni 7 s, a turno)
            let u = (t + Double(j) * 2.3).truncatingRemainder(dividingBy: 7) / 1.1
            if u < 1 {
                let e = OP.lis(u), cc = busta(P3(pc.x * e, pc.y * e, zt + (pc.z - zt) * e))
                for k in 0..<4 { F.metti(4, cc[k], cc[(k + 1) % 4]) }
            }
            posti.append(P(pc.x, pc.y, pc.z))
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.08 + 0.16 * Double($0)) },
                spessore: { piccolo ? 0.45 + Double($0) * 0.08 : 0.7 + Double($0) * 0.13 }, alone: { $0 >= 4 && !piccolo ? OP.s(0.08) : nil })
        for p in posti { OP.alone(&gc, p.x, p.y, 10, 0.45, bianco: true) }
        let sl = P(wx + 0.12, -wy - 0.12, zs)
        OP.alone(&gc, sl.x, sl.y, piccolo ? 4 : 9, 0.7, bianco: true)
        guard !piccolo else { return }
        for c in centri { M.zona(c.p.x, c.p.y, max(7, passo * sz * 0.55), c.i) }
        for (j, p) in posti.enumerated() {
            M.zona(p.x, p.y, 16, 100 + j)
            OP.dentro(&gc, W, OP.corto(prio[j].nome, 12), p.x, p.y - 0.16 * sz - 8, 6.5, 700, OP.b(0.95))
        }
        let nl = D.posta?.filter { !$0.letta }.count ?? 0
        OP.scritta(&gc, D.posta.map { "POSTA · \($0.count)" } ?? "POSTA", 10, 14, 8, 600, OP.c(0.85), .leading)
        if D.posta != nil { OP.scritta(&gc, "NON LETTE \(nl)", W - 10, 14, 8, 700, nl > 0 ? OP.b(0.95) : OP.c(0.6), .trailing) }
        if !D.prio.isEmpty { OP.scritta(&gc, "PRIORITÀ \(D.prio.count)", W - 10, 24, 6.5, 600, OP.c(0.8), .trailing) }
        if D.posta == nil { OP.scritta(&gc, "APRO LA CASELLA", cx, 34, 8, 700, OP.c(0.9)) }
        else if D.posta?.isEmpty == true { OP.scritta(&gc, "CASELLA IN ORDINE", cx, 34, 8, 700, OP.c(0.9)) }
        if let s = M.scelta, s >= 100, s - 100 < prio.count, s - 100 < posti.count {
            let m = prio[s - 100], p = posti[s - 100]
            OP.riquadro(&gc, W, H, p.x, p.y, [OP.taglia(m.nome.uppercased(), 20), OP.taglia(m.oggetto, 28), m.quando.isEmpty ? "PRIORITÀ" : "PRIORITÀ · \(m.quando)"],
                        t - M.sceltaT, codice: "IMPORTANTE")
        } else if let s = M.scelta, let posta = D.posta, s >= 0, s < posta.count, let c = centri.first(where: { $0.i == s }) {
            let m = posta[s]
            OP.riquadro(&gc, W, H, c.p.x, c.p.y, [OP.taglia(m.nome.uppercased(), 20), OP.taglia(m.oggetto, 28), "\(m.data) · \(m.letta ? "LETTA" : "NON LETTA")"],
                        t - M.sceltaT, codice: "MAIL \(s + 1)/\(n)")
        }
    }
}

/// L'ologramma dell'Email: sull'iPhone in testa alla sezione (col dito), sul polso piccolo nella riga in alto.
struct OlogrammaPosta: View {
    let dati: PostaOlo
    var piccolo = false
    @State private var prove = ProvePosta()

    @State private var altre = ProvePostaTavola()

    var body: some View {
        // 9 nov (build 19): tre prove come il mockup, SMISTA (quella di prima), FIREWALL e FASCICOLI; il polso segue la scelta
        if piccolo {
            ProvaOloPiccola(sezione: .posta) { k, gc, W, H, t, M in disegna(k, &gc, W, H, t, M, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .posta, altezza: 260, crea: { _ in }) { k, gc, W, H, t, M in disegna(k, &gc, W, H, t, M, piccolo: false) }
            #endif
        }
    }

    private func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, piccolo: Bool) {
        switch k {
        case 1: altre.firewall(&gc, W, H, t, M, dati, piccolo: piccolo)
        case 2: altre.fascicoli(&gc, W, H, t, M, dati, piccolo: piccolo)
        default: prove.disegna(&gc, W, H, t, M, dati, piccolo: piccolo)
        }
    }
}
