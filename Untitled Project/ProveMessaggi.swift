import Foundation
import SwiftUI

// MARK: - MESSAGGI · l'ologramma BOLLE (mockup v267b, il signore 5 nov 19:33: «messaggi rifallo»; 19:35 «ok mi piace»)
// La conversazione in 3D: i messaggi che JARVIS ha mandato per lui sono fumetti di luce su un'elica attorno alla colonna del
// proiettore, il più nuovo in basso; l'elica gira piano e il dito la gira. Ogni fumetto ha il nome, da quanto e l'inizio del
// messaggio, e un raggio che lo lega alla colonna. Scelta una persona per scriverle, in fondo compare il fumetto che scrive («…» che
// pulsa) e i suoi messaggi restano chiari, gli altri si abbassano; mandato, il fumetto nuovo nasce lì, gli altri salgono di un posto
// lungo l'elica e un lampo corre su per la colonna. Toccato un fumetto: chi, il messaggio, il canale e da quanto.
// 7 nov sera (il signore: «almeno gli ultimi 5 ricevuti, poi sostituiti dai nuovi»): sull'elica anche i messaggi RICEVUTI
// (l'automazione di Comandi «Messaggio ricevuto», vedi MessaggioRicevuto in Comunicazioni.swift), con «DA MATTEO» sul fumetto;
// quelli mandati da JARVIS «A MATTEO». Gli ultimi 5 fra tutti, il più nuovo in basso.
// Uguale al mockup (olo_extra/tre.js, bolleMessaggi). Solo iPhone (sul polso Messaggi non è una sezione).

/// I messaggi per BOLLE: quelli che JARVIS ha mandato (dal registro, il più nuovo per primo), la persona scelta e il canale.
struct MessaggiOlo {
    struct Voce { let id: UUID; let nome: String; let testo: String; let quando: Date?; let tipo: String; var ricevuto = false }
    var voci: [Voce] = []
    var totale = 0
    var scelto: String?
    var canale = ""
}

/// Lo stato di BOLLE: dove sta ogni fumetto sull'elica (scivola quando ne arriva uno nuovo), quando è nato, il lampo dell'invio.
final class ProveMessaggi {
    private var livelli: [UUID: Double] = [:]
    private var nati: [UUID: Double] = [:]
    private var ultimo: Double?
    private var lancio = -9.0
    private var primoId: UUID?
    private var visto = false

    private struct Posto { let voce: MessaggiOlo.Voce?; let i: Int; let p: P3; let asse: P3; let nasce: Double }

    func disegna(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: MessaggiOlo, piccolo: Bool) {
        if let u = ultimo, t < u - 0.5 { livelli = [:]; nati = [:]; ultimo = nil; lancio = -9; visto = false }   // la tela è ripartita
        let dt = ultimo.map { min(0.05, max(0, t - $0)) } ?? 1.0 / 60
        ultimo = t
        let massimo = piccolo ? 4 : 5
        let voci = Array(D.voci.prefix(massimo)), scelto = D.scelto, sc: Double = scelto == nil ? 0 : 1
        // un messaggio nuovo in cima al registro: nasce in fondo (dal fumetto che scrive) e gli altri salgono
        let id0 = voci.first?.id
        if !visto { visto = true; primoId = id0 } else if id0 != primoId { primoId = id0; lancio = t }
        var vivi = Set<UUID>()
        for (i, v) in voci.enumerated() {
            vivi.insert(v.id)
            if livelli[v.id] == nil { livelli[v.id] = t < 0.05 ? Double(i) : -1; nati[v.id] = t < 0.05 ? Double(i) * 0.07 : t }
            let l = livelli[v.id] ?? Double(i)
            livelli[v.id] = l + (Double(i) - l) * (1 - exp(-dt * 7))
        }
        if livelli.count > vivi.count { livelli = livelli.filter { vivi.contains($0.key) }; nati = nati.filter { vivi.contains($0.key) } }

        let cx = W / 2, base = piccolo ? H - 3 : H - 14, rx = piccolo ? W * 0.3 : min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        let zl = { (l: Double) -> Double in 0.4 + l * 0.38 + sc * 0.22 }
        let cima = zl(Double(massimo - 1)) + 0.24
        let sz = piccolo ? W * 0.3 : min(W * 0.27, (base - 34) / (cima + 0.25)), cy = base - (piccolo ? 2 : 6)
        let ang = t * 0.16 + M.giro, al = 0.22, R = 0.82
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        Olo.cono(&gc, cx, base, rx, P(0, 0, cima).y, rx * 0.5, a: 0.06)
        var F = FasciOlo(6)
        // la colonna e le sue tacche; il lampo che sale quando parte un messaggio
        F.metti(2, P(0, 0, 0), P(0, 0, cima))
        for k in 0...12 { let z = cima * Double(k) / 12; F.metti(k % 3 == 0 ? 1 : 0, P(-0.05, 0, z), P(0.05, 0, z)) }
        let dl = t - lancio
        if dl < 0.7 { let z = cima * OP.lis(dl / 0.7); F.metti(5, P(0, 0, max(0, z - 0.15)), P(0, 0, z)) }
        // l'elica: il filo che lega i posti, tenue
        var q: P3?
        for k in 0...60 {
            let l = -sc + (Double(massimo - 1) + sc) * Double(k) / 60, a = l * 1.25 + 2.2
            let o = P(cos(a) * R, sin(a) * R, zl(l))
            if let q { F.metti(0, q, o) }
            q = o
        }
        // i fumetti, dal più lontano al più vicino (le scritte davanti restano sopra)
        var posti: [Posto] = voci.enumerated().map { i, v in
            let l = livelli[v.id] ?? Double(i), a = l * 1.25 + 2.2, z = zl(l)
            return Posto(voce: v, i: i, p: P(cos(a) * R, sin(a) * R, z), asse: P(0, 0, z), nasce: OP.lis((t - (nati[v.id] ?? 0)) / 0.35))
        }
        if scelto != nil {
            let a = -1.25 + 2.2, z = zl(-1)
            posti.append(Posto(voce: nil, i: -1, p: P(cos(a) * R, sin(a) * R, z), asse: P(0, 0, z), nasce: 1))
        }
        for b in posti {                                                  // il raggio dalla colonna
            let altro = b.voce.map { scelto != nil && $0.nome != scelto } == true
            F.metti(altro ? 0 : 1, b.asse, b.p)
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.08 + 0.16 * Double($0)) },
                spessore: { piccolo ? 0.45 + Double($0) * 0.08 : 0.7 + Double($0) * 0.13 }, alone: { $0 >= 4 && !piccolo ? OP.s(0.08) : nil })
        posti.sort { $0.p.z > $1.p.z }
        var centri: [(x: Double, y: Double, i: Int, davanti: Bool)] = []
        for b in posti {
            let davanti = b.p.z < 0
            let altro = b.voce.map { scelto != nil && $0.nome != scelto } == true
            let alfa: Double = (davanti ? 1.0 : 0.5) * b.nasce * (altro ? 0.4 : 1.0)
            guard let v = b.voce else {                                  // il fumetto che scrive: «…» che pulsa
                let f = ProveMessaggi.fumetto(&gc, b, 54, 22, 1, chiaro: true, W: W)
                for k in 0..<3 {
                    let a = 0.3 + 0.7 * max(0, sin(t * 6 - Double(k) * 0.9)), r = 2.2 * f.s
                    let c = CGPoint(x: f.x + f.w / 2 + Double(k - 1) * 9 * f.s, y: f.y + f.h / 2)
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(OP.b(a)))
                }
                if !piccolo, let s = scelto { OP.scritta(&gc, "A \(OP.corto(s, 12))", f.x + f.w + 8, f.y + f.h / 2 + 2.5, 6.5, 700, OP.b(0.95), .leading) }
                continue
            }
            if piccolo { _ = ProveMessaggi.fumetto(&gc, b, 34, 14, alfa, chiaro: b.i == 0, W: W); continue }
            let f = ProveMessaggi.fumetto(&gc, b, 92, 28, alfa, chiaro: b.i == 0 || scelto == v.nome || M.scelta == b.i, W: W)
            let caratteri = max(8, Int((f.w - 14) / (3.9 * f.s)))
            OP.scritta(&gc, (v.ricevuto ? "DA " : "A ") + OP.corto(v.nome, 9), f.x + 7 * f.s, f.y + 10.5 * f.s, 7 * f.s, 700, OP.b(0.95 * alfa), .leading)
            if v.quando != nil { OP.scritta(&gc, OP.quantoFa(v.quando), f.x + f.w - 7 * f.s, f.y + 10.5 * f.s, 6 * f.s, 600, OP.c(0.8 * alfa), .trailing) }
            OP.scritta(&gc, OP.taglia(v.testo, caratteri), f.x + 7 * f.s, f.y + 21 * f.s, 6.5 * f.s, 500, OP.c(0.9 * alfa), .leading)
            centri.append((x: f.x + f.w / 2, y: f.y + f.h / 2, i: b.i, davanti: davanti))
            if b.i == 0 && t - lancio < 0.6 { OP.alone(&gc, f.x + f.w / 2, f.y + f.h / 2, 22, 0.8 * (1 - (t - lancio) / 0.6), bianco: true) }
        }
        let cp = P(0, 0, cima)
        OP.alone(&gc, cp.x, cp.y, piccolo ? 4 : 8, 0.5 + 0.3 * sin(t * 2.2), bianco: true)
        guard !piccolo else { return }
        for c in centri { M.zona(c.x, c.y, c.davanti ? 26 : 16, c.i) }
        OP.scritta(&gc, voci.isEmpty ? "MESSAGGI" : "MESSAGGI · \(D.totale)", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, D.canale.uppercased(), W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if voci.isEmpty && scelto == nil { OP.scritta(&gc, "NESSUN MESSAGGIO", cx, 34, 8, 700, OP.c(0.9)) }
        if let s = M.scelta, s >= 0, s < voci.count, let c = centri.first(where: { $0.i == s }) {
            let v = voci[s]
            let tipo = v.tipo == "whatsapp" ? "WHATSAPP" : v.tipo == "imessage" ? "IMESSAGE" : v.tipo.uppercased()
            OP.riquadro(&gc, W, H, c.x, c.y, [OP.taglia((v.ricevuto ? "DA " : "A ") + v.nome.uppercased(), 18), "«\(OP.taglia(v.testo, 26))»", v.quando != nil ? "\(tipo) · \(OP.quantoFa(v.quando))" : tipo],
                        t - M.sceltaT, codice: "MESSAGGIO \(s + 1)/\(voci.count)")
        }
    }

    /// Un fumetto che guarda sempre chi guarda: angoli tondi, la coda verso la colonna, il vetro scuro sotto e il bordo di luce.
    /// Restituisce dove sta e la sua scala (per le scritte).
    private static func fumetto(_ gc: inout GraphicsContext, _ b: Posto, _ w: Double, _ h: Double, _ alfa: Double, chiaro: Bool,
                                W: Double) -> (x: Double, y: Double, w: Double, h: Double, s: Double) {
        let kp = (3.6 / (3.6 + b.p.z)).squareRoot(), s = (0.6 + 0.4 * b.nasce) * kp, bw = w * s, bh = h * s
        let coda: Double = b.p.x > b.asse.x ? -1 : 1
        let bx = max(4, min(W - 4 - bw, b.p.x - bw / 2)), by = b.p.y - bh / 2, r = 6 * s
        var p = Path()
        p.move(to: CGPoint(x: bx + r, y: by))
        p.addLine(to: CGPoint(x: bx + bw - r, y: by))
        p.addQuadCurve(to: CGPoint(x: bx + bw, y: by + r), control: CGPoint(x: bx + bw, y: by))
        p.addLine(to: CGPoint(x: bx + bw, y: by + bh - r))
        p.addQuadCurve(to: CGPoint(x: bx + bw - r, y: by + bh), control: CGPoint(x: bx + bw, y: by + bh))
        if coda > 0 {
            p.addLine(to: CGPoint(x: bx + bw - r - 2, y: by + bh))
            p.addLine(to: CGPoint(x: bx + bw + 5 * s, y: by + bh + 5 * s))
            p.addLine(to: CGPoint(x: bx + bw - r - 9 * s, y: by + bh))
        }
        p.addLine(to: CGPoint(x: bx + r, y: by + bh))
        if coda < 0 {
            p.addLine(to: CGPoint(x: bx + r + 9 * s, y: by + bh))
            p.addLine(to: CGPoint(x: bx - 5 * s, y: by + bh + 5 * s))
            p.addLine(to: CGPoint(x: bx + r + 2, y: by + bh))
        }
        p.addQuadCurve(to: CGPoint(x: bx, y: by + bh - r), control: CGPoint(x: bx, y: by + bh))
        p.addLine(to: CGPoint(x: bx, y: by + r))
        p.addQuadCurve(to: CGPoint(x: bx + r, y: by), control: CGPoint(x: bx, y: by))
        p.closeSubpath()
        let prima = gc.blendMode
        gc.blendMode = .normal                                          // il vetro scuro: copre quello che sta dietro
        gc.fill(p, with: .color(Color(red: 2 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.62 * alfa)))
        gc.blendMode = prima
        gc.fill(p, with: .color(OP.s((chiaro ? 0.14 : 0.06) * alfa)))
        gc.stroke(p, with: .color(chiaro ? OP.b(0.9 * alfa) : OP.c(0.55 * alfa)), lineWidth: chiaro ? 1.2 : 0.9)
        return (x: bx, y: by, w: bw, h: bh, s: s)
    }
}

#if os(iOS)
/// L'ologramma dei Messaggi in testa alla sezione (iPhone).
struct OlogrammaMessaggi: View {
    let dati: MessaggiOlo
    @State private var prove = ProveMessaggi()

    var body: some View {
        OloSingolaVista(altezza: 260, aiuto: "↔ GIRA · TOCCA UN MESSAGGIO", etichetta: "Ologramma dei messaggi mandati da JARVIS") { gc, W, H, t, M in
            prove.disegna(&gc, W, H, t, M, dati, piccolo: false)
        }
    }
}
#endif
