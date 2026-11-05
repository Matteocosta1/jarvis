import Foundation
import SwiftUI

// MARK: - CONFIDENTE · l'ologramma BILANCIA (mockup v267, il signore 5 nov 19:33: «gli altri belli»)
// Una bilancia di luce sul proiettore. Quello che racconta (la conversazione incollata) si posa sui piatti un messaggio alla volta,
// come cubi di luce che cadono: se la conversazione ha due voci (WhatsApp: «[data] Nome: testo»), ognuna ha il suo piatto, col suo
// nome; se è un racconto, tutto va sul piatto LEI e l'altro resta tratteggiato: JARVIS vede solo la sua metà della storia. Il giogo
// si inclina dalla parte del peso (con la sua inerzia) e l'ago lo segna in gradi; nel perno batte il suo cuore, al battito di oggi.
// Toccato un piatto: chi è, quanti messaggi, quanta parte della conversazione. Uguale al mockup (olo_extra/tre.js, bilanciaConfidente).
// Solo iPhone (sul polso il Confidente è a voce).

/// La conversazione per la BILANCIA: le voci (al massimo due, nell'ordine in cui parlano) e il battito di oggi.
struct ConfidenteOlo {
    struct Voce { let nome: String; let n: Int }
    let voci: [Voce]
    let battito: Int?

    init(testo: String, battito: Int?) {
        voci = ConfidenteOlo.voci(testo)
        self.battito = battito
    }

    /// I tre modi in cui arriva una chat incollata: WhatsApp su iPhone «[05/11/26, 18:02] Bea: …», su Android «05/11/26, 18:02 - Bea: …»,
    /// e a mano «Bea: …».
    private static let modi: [NSRegularExpression] = [
        #"^\[[^\]]{4,40}\]\s*([^:]{1,32}?):\s+\S"#,
        #"^\d{1,2}[/.]\d{1,2}[/.]\d{2,4},?\s+\d{1,2}[:.]\d{2}\s*[-–]\s*([^:]{1,32}?):\s+\S"#,
        #"^([A-Za-zÀ-ÿ'][A-Za-zÀ-ÿ' .]{0,30}?):\s+\S"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// vociConfidente del mockup: chi parla e quante volte. Due voci o più: le due che parlano di più, nell'ordine in cui parlano;
    /// altrimenti una sola voce (il racconto) con le sue righe.
    static func voci(_ testo: String) -> [Voce] {
        let invisibili = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}")   // i segni nascosti di WhatsApp
        let righe = testo.components(separatedBy: .newlines)
            .map { riga in String(riga.unicodeScalars.filter { s in !invisibili.contains(s) }).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var ordine: [String] = [], conta: [String: Int] = [:], ultimo: String?
        for r in righe {
            var nome: String?
            let tutta = NSRange(r.startIndex..., in: r)
            for e in modi {
                guard let m = e.firstMatch(in: r, range: tutta), m.numberOfRanges > 1, let g = Range(m.range(at: 1), in: r) else { continue }
                let n = r[g].trimmingCharacters(in: .whitespaces)
                if !n.isEmpty, !n.allSatisfy(\.isNumber), n.split(separator: " ").count <= 4 { nome = n }
                break
            }
            if let nome {
                if conta[nome] == nil { ordine.append(nome) }
                conta[nome, default: 0] += 1
                ultimo = nome
            } else if ultimo == nil {
                if conta[""] == nil { ordine.append("") }
                conta["", default: 0] += 1                                   // il racconto senza nomi
            }
        }
        let nomi = ordine.filter { !$0.isEmpty }
        if nomi.count >= 2 {
            let due = nomi.enumerated()
                .sorted { (conta[$0.element] ?? 0, -$0.offset) > (conta[$1.element] ?? 0, -$1.offset) }
                .prefix(2).map(\.element)
                .sorted { (ordine.firstIndex(of: $0) ?? 0) < (ordine.firstIndex(of: $1) ?? 0) }
            return due.map { Voce(nome: $0, n: conta[$0] ?? 0) }
        }
        return righe.isEmpty ? [] : [Voce(nome: "", n: righe.count)]
    }
}

/// Lo stato della BILANCIA: l'inclinazione (con la sua inerzia) e quando è caduto ogni cubo.
final class ProveConfidente {
    private var inclina = 0.0
    private var ultimo: Double?
    private var firma = ""
    private var nati: [[Double]] = [[], []]

    func disegna(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: ConfidenteOlo, piccolo: Bool) {
        if let u = ultimo, t < u - 0.5 { nati = [[], []]; inclina = 0; ultimo = nil }    // la tela è ripartita
        let dt = ultimo.map { min(0.05, max(0, t - $0)) } ?? 1.0 / 60
        ultimo = t
        let due = D.voci.count == 2
        let nA = D.voci.first?.n ?? 0, nB = due ? D.voci[1].n : 0
        // i cubi nuovi cadono (ogni cubo ricorda quando è arrivato, uno dopo l'altro a 40 ms); se le voci cambiano, si riparte
        let f = due ? D.voci.map(\.nome).joined(separator: "|") : "racconto"
        if f != firma { firma = f; nati = [[], []] }
        let pesi: [(Int, Int)] = [(0, nA), (1, nB)]
        for (lato, k) in pesi {
            let da = nati[lato].count, fino = min(k, 18)
            while nati[lato].count < fino { nati[lato].append(t + Double(nati[lato].count - da) * 0.04) }
            if nati[lato].count > fino { nati[lato].removeLast(nati[lato].count - fino) }
        }
        let meta = due ? max(-1, min(1, Double(nA - nB) / Double(max(1, nA + nB)))) : min(1, Double(nA) / 8)
        inclina += (meta * 0.3 - inclina) * (1 - exp(-dt * 3.2))
        let th = inclina + 0.025 * sin(t * 1.1) * (1 - min(1, abs(inclina) * 4))
        let cx = W / 2, base = piccolo ? H - 3 : H - 14, rx = piccolo ? W * 0.3 : min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        let sz = piccolo ? W * 0.33 : min(W * 0.24, (base - 30) / 1.75), cy = base - (piccolo ? 2 : 6)
        let ang = 0.22 * sin(t * 0.2) + M.giro, al = 0.3
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let H0 = 1.3, L = 0.95, ct = cos(th), st = sin(th)
        // la colonna e il perno
        F.metti(2, P(0, 0, 0), P(0, 0, H0 - 0.06))
        F.metti(1, P(-0.05, 0, 0), P(-0.05, 0, H0 - 0.1))
        F.metti(1, P(0.05, 0, 0), P(0.05, 0, H0 - 0.1))
        for z in [0.05, 0.35, 0.65, 0.95] {
            var q: P3?
            for i in 0...16 { let a = Double(i) / 16 * OP.due, o = P(cos(a) * 0.08, sin(a) * 0.08, z); if let q { F.metti(0, q, o) }; q = o }
        }
        // il giogo, inclinato dalla parte del peso
        let sx = P3(-L * ct, 0, H0 - L * st), dx = P3(L * ct, 0, H0 + L * st)
        for y in [-0.035, 0.035] { F.metti(3, P(sx.x, y, sx.z), P(dx.x, y, dx.z)) }
        // l'ago e la sua scala (±20°, una tacca ogni 5°)
        let ago = P3(-st * 0.34, 0, H0 + ct * 0.34)
        F.metti(5, P(0, 0, H0), P(ago.x, ago.y, ago.z))
        for d in stride(from: -20, through: 20, by: 5) {
            let a = Double(d) * .pi / 180, r0 = 0.38, r1 = d % 10 == 0 ? 0.46 : 0.42
            F.metti(d == 0 ? 3 : 1, P(-sin(a) * r0, 0, H0 + cos(a) * r0), P(-sin(a) * r1, 0, H0 + cos(a) * r1))
        }
        // i piatti: appesi a tre catene, il secondo tratteggiato se l'altra voce non c'è
        var piatti: [P3] = []
        let spigoli: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        let appesi: [(Int, P3)] = [(0, sx), (1, dx)]
        for (lato, e) in appesi {
            let c = P3(e.x, 0, e.z - 0.55), r = 0.32, pieno = lato == 0 || due
            for a in [1.5708, 3.6652, 5.7596] { F.metti(pieno ? 2 : 1, P(e.x, e.y, e.z), P(c.x + cos(a) * r, sin(a) * r, c.z)) }
            var q: P3?
            for i in 0...32 {
                let a = Double(i) / 32 * OP.due, o = P(c.x + cos(a) * r, sin(a) * r, c.z)
                if let q, pieno || i % 2 == 1 { F.metti(pieno ? 3 : 1, q, o) }
                q = o
            }
            q = nil
            for i in 0...24 {
                let a = Double(i) / 24 * OP.due, o = P(c.x + cos(a) * r * 0.7, sin(a) * r * 0.7, c.z - 0.05)
                if let q, pieno { F.metti(1, q, o) }
                q = o
            }
            piatti.append(c)
            // i cubi: uno per messaggio (al massimo 18), cadono al loro posto
            let k = lato == 0 ? nA : nB, s = 0.062
            for i in 0..<min(k, 18) {
                let strato = i / 9, j = i % 9, gx = Double(j % 3 - 1), gy = Double(j / 3 - 1)
                let nato = i < nati[lato].count ? nati[lato][i] : t
                let d = OP.lis((t - nato) / 0.38)
                let p = P3(c.x + gx * 0.15, gy * 0.15, c.z + s + Double(strato) * 0.12 + (1 - d) * 0.7)
                let v: [P3] = [P(p.x - s, p.y - s, p.z - s), P(p.x + s, p.y - s, p.z - s), P(p.x + s, p.y + s, p.z - s), P(p.x - s, p.y + s, p.z - s),
                               P(p.x - s, p.y - s, p.z + s), P(p.x + s, p.y - s, p.z + s), P(p.x + s, p.y + s, p.z + s), P(p.x - s, p.y + s, p.z + s)]
                let g = d < 1 ? 5 : 3
                for (a, b) in spigoli { F.metti(g, v[a], v[b]) }
            }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.95) : $0 == 4 ? OP.b(0.6) : OP.c(0.08 + 0.16 * Double($0)) },
                spessore: { piccolo ? 0.45 + Double($0) * 0.08 : 0.7 + Double($0) * 0.13 }, alone: { $0 >= 4 && !piccolo ? OP.s(0.08) : nil })
        // il cuore nel perno, al battito di oggi
        let bpm = Double(D.battito ?? 60), u = (t * bpm / 60).truncatingRemainder(dividingBy: 1)
        let colpo = exp(-pow(u / 0.07, 2)) + 0.55 * exp(-pow((u - 0.22) / 0.07, 2))
        let pv = P(0, 0, H0)
        OP.alone(&gc, pv.x, pv.y, (piccolo ? 5 : 10) + 5 * colpo, 0.45 + 0.45 * colpo, bianco: true)
        let pa = P(ago.x, ago.y, ago.z)
        OP.alone(&gc, pa.x, pa.y, piccolo ? 3 : 5, 0.8, bianco: true)
        guard !piccolo else { return }
        let nomi = due ? D.voci.map { OP.corto($0.nome, 12) } : ["LEI", "L'ALTRO"]
        for (lato, c) in piatti.enumerated() {
            let o = P(c.x, 0, c.z - 0.1), k = lato == 0 ? nA : nB, pieno = lato == 0 || due
            OP.dentro(&gc, W, nomi[lato], o.x, o.y + 16, 7.5, 700, pieno ? OP.b(0.95) : OP.c(0.6))
            let conta = k == 0 ? "VUOTO" : "\(k) \(due ? (k == 1 ? "MESSAGGIO" : "MESSAGGI") : (k == 1 ? "RIGA" : "RIGHE"))"
            OP.dentro(&gc, W, pieno ? conta : "?", o.x, o.y + 25, 6.5, 600, OP.c(0.8))
            M.zona(o.x, o.y - 4, 26, lato)
        }
        let gradi = Int((abs(th) * 180 / .pi).rounded()), gt = P(0, 0, H0 + 0.55)
        OP.scritta(&gc, "\(gradi)°", gt.x, gt.y, 7, 700, OP.b(0.9))
        OP.scritta(&gc, nA + nB > 0 ? "\(nA + nB) \(due ? "MESSAGGI" : "RIGHE")" : "ASCOLTO", 10, 14, 8, 600, OP.c(0.85), .leading)
        if D.battito != nil { OP.scritta(&gc, "\(Int(bpm)) BPM", W - 10, 14, 8, 700, OP.b(0.95), .trailing) }
        if let lato = M.scelta, lato >= 0, lato < piatti.count {
            let c = piatti[lato], o = P(c.x, 0, c.z), k = lato == 0 ? nA : nB, tot = max(1, nA + nB)
            let righe: [String]
            if due {
                righe = [nomi[lato], "\(k) \(k == 1 ? "MESSAGGIO" : "MESSAGGI")", "\(Int((Double(k) / Double(tot) * 100).rounded()))% DELLA CONVERSAZIONE"]
            } else if lato == 0 {
                righe = ["LEI", k > 0 ? "\(k) \(k == 1 ? "RIGA" : "RIGHE")" : "NIENTE, ANCORA", "LA SUA METÀ DELLA STORIA"]
            } else {
                righe = ["L'ALTRO", "NON LO SENTO", "IL MIO È UN PARERE"]
            }
            OP.riquadro(&gc, W, H, o.x, o.y, righe, t - M.sceltaT, codice: lato == 0 ? "PIATTO SINISTRO" : "PIATTO DESTRO")
        }
    }
}

#if os(iOS)
/// L'ologramma del Confidente, sotto le parole di JARVIS (iPhone).
struct OlogrammaConfidente: View {
    let dati: ConfidenteOlo
    @State private var prove = ProveConfidente()

    var body: some View {
        OloSingolaVista(altezza: 250, aiuto: "↔ GIRA · TOCCA UN PIATTO", etichetta: "Ologramma della bilancia: la conversazione sui due piatti") { gc, W, H, t, M in
            prove.disegna(&gc, W, H, t, M, dati, piccolo: false)
        }
    }
}
#endif
