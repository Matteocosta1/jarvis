import Foundation
import SwiftUI

// MARK: - METEO, EDITH, POSTA, MESSAGGI, CONFIDENTE, INTERPRETE, RICORDI (build 11.0 (19), 9 nov, come il mockup)
// Le prove nuove della tavola; la prima prova delle sezioni che un ologramma lo avevano già (SMISTA, BOLLE, BILANCIA, PONTE,
// SENTIERO) resta quella di prima. Meteo, EDITH, Posta e Ricordi anche sul polso (la prova scelta sull'iPhone); Messaggi,
// Confidente e Interprete solo sull'iPhone (al polso non sono sezioni).

// MARK: METEO · CELLA, GLOBO, VENTO

struct DatiMeteoOlo {
    var stato = StatoCielo()
    var gradi = 0
    var nome = ""
}

final class ProveMeteo {
    private struct Particella { var x: Double; var y: Double; let v: Double; let k: Int }
    private var particelle: [Particella] = (0..<70).map { i in Particella(x: OP.caso(i * 3) * 2 - 1, y: OP.caso(i * 3 + 1) * 2 - 1, v: 0.6 + OP.caso(i * 3 + 2) * 0.6, k: i) }
    private var giroCaso = 0

    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMeteoOlo, piccolo: Bool) {
        switch k {
        case 1: globo(&gc, W, H, t, M, D, piccolo)
        case 2: vento(&gc, W, H, t, M, D, piccolo)
        default: cella(&gc, W, H, t, M, D, piccolo)
        }
    }

    // CELLA: la nuvola come la vede il radar (a strati), le colonne di pioggia fitte quanto la probabilità, i lampi se c'è temporale
    private func cella(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMeteoOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.3, sz: 1.05, su: 0.08, giro: 0.12, rx: 0.3, conoSu: 0.3, conoA: 0.05))
        var F = FasciOlo(6)
        let c = D.stato, nuvolosa = c.cielo != .sereno && c.cielo != .notte, p = c.pioggia / 100
        let alto = c.cielo == .temporale ? 1.2 : nuvolosa ? 0.75 : 0.35
        let B: [(Double, Double, Double)] = [(0, 0, 0.55), (0.45, 0.15, 0.42), (-0.42, -0.1, 0.45), (0.1, -0.35, 0.38), (-0.15, 0.38, 0.36)]
        for k in 0..<10 {
            let z = 0.62 + Double(k) / 9 * alto * s.nasce, f = sin(.pi * (0.15 + 0.85 * Double(k) / 9))
            for (bx, by, br) in B { Tav.cerchio(&F, s, br * f * (0.8 + 0.2 * sin(t * 0.6 + bx * 5)), z, k == 0 ? 3 : 1, n: 32, cx: bx, cy: by) }
        }
        Tav.traccia(&gc, F, piccolo)
        let n = Int(((piccolo ? 14 : 40) * p).rounded())
        for i in 0..<n {
            let a = Double(i) * 2.39996, r = 0.15 + 0.5 * (Double(i) * 0.618).truncatingRemainder(dividingBy: 1), u = (t * 1.6 + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let q1 = s.P(cos(a) * r, sin(a) * r, 0.58 - u * 0.55), q2 = s.P(cos(a) * r, sin(a) * r, 0.58 - u * 0.55 - 0.07)
            Tav.segmento(&gc, q1, q2, OP.c(0.55 * (1 - u)), 1)
        }
        if c.cielo == .temporale && t.truncatingRemainder(dividingBy: 2.3) < 0.12 {
            let a = s.P(0.1, 0, 0.6), b = s.P(0.25, 0.1, 0.05)
            var l = Path(); l.move(to: CGPoint(x: a.x, y: a.y)); l.addLine(to: CGPoint(x: (a.x + b.x) / 2 - 6, y: (a.y + b.y) / 2)); l.addLine(to: CGPoint(x: b.x, y: b.y))
            gc.stroke(l, with: .color(OP.b(0.95)), lineWidth: 1.6)
        }
        let pc = s.P(0, 0, 0.62 + alto * 0.5)
        Tav.alone(&gc, pc, s.sz * 0.8, nuvolosa ? 0.12 : 0.06)
        guard !piccolo else { return }
        M.zona(pc.x, pc.y, s.sz * 0.5, 0)
        Tav.testate(&gc, W, "RADAR · CELLA", "\(D.gradi)° \(D.nome.uppercased())", "PIOGGIA \(Int(c.pioggia.rounded()))% · VENTO \(Int(c.vento.rounded())) KM/H")
        if M.scelta == 0 {
            OP.riquadro(&gc, W, H, pc.x, pc.y, [D.nome.uppercased(), "PIOGGIA \(Int(c.pioggia.rounded()))%", "VENTO \(Int(c.vento.rounded())) KM/H"], t - M.sceltaT, codice: "CELLA")
        }
    }

    // GLOBO: la Terra con le bande di nuvole che girano e Milano accesa
    private func globo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMeteoOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.32, sz: 0.85, su: 1.1, giro: 0, mano: 0.8, conoSu: 0.3))
        var F = FasciOlo(6)
        let giro = -9 + sin(t * 0.1) * 25 + M.giro * 40
        let G = Tav.globo(&F, s, 1, giroLon: -giro)
        let fitte = D.stato.pioggia / 100
        let bande: [(Double, Double, Double)] = [(48, 9, 0.6 + fitte), (20, -6, 0.5), (-35, 7, 0.7)]
        for (lat, vel, larg) in bande {
            for k in 0..<9 {
                let lo = Double(k) * 40 + t * vel, q1 = G(lat + sin(Double(k)) * 4, lo), q2 = G(lat + sin(Double(k)) * 4, lo + 18 * larg)
                if q1.z < 0 { F.metti(2, q1, q2) }
            }
        }
        Tav.traccia(&gc, F, piccolo)
        let mi = G(45.46, 9.19)
        Tav.alone(&gc, mi, piccolo ? 5 : 12 + 3 * sin(t * 3), mi.z < 0 ? 0.9 : 0.25, Tav.bianco)
        guard !piccolo else { return }
        if mi.z < 0 {
            gc.stroke(Olo.ellisse(mi.x, mi.y, 7, 7), with: .color(OP.b(0.7)), lineWidth: 1)
            OP.scritta(&gc, "MILANO", mi.x, mi.y - 12, 7, 700, OP.b(0.95))
            M.zona(mi.x, mi.y, 18, 0)
        }
        Tav.testate(&gc, W, "GLOBO METEO", "\(D.gradi)°", D.nome.uppercased())
        if M.scelta == 0 {
            OP.riquadro(&gc, W, H, mi.x, mi.y, ["MILANO", "\(D.gradi)° · \(D.nome.uppercased())", "PIOGGIA \(Int(D.stato.pioggia.rounded()))% · VENTO \(Int(D.stato.vento.rounded())) KM/H"],
                        t - M.sceltaT, codice: "METEO")
        }
    }

    // VENTO: le correnti sulla città (particelle che seguono il vento), la rosa con la freccia da dove viene
    private func vento(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMeteoOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.7, sz: 1.2, su: 0.75, giro: 0.05, rx: 0.32, cono: false))
        var F = FasciOlo(6)
        for i in -4...4 { let d = Double(i) * 0.22; F.metti(0, s.P(d, -0.95, 0), s.P(d, 0.95, 0)); F.metti(0, s.P(-0.95, d, 0), s.P(0.95, d, 0)) }
        for i in 0..<14 {
            let bx = sin(Double(i) * 3.7) * 0.7, by = cos(Double(i) * 2.3) * 0.7, h = (0.1 + 0.3 * (Double(i) * 0.618).truncatingRemainder(dividingBy: 1)) * s.nasce
            F.metti(1, s.P(bx, by, 0), s.P(bx, by, h)); F.metti(1, s.P(bx + 0.06, by, 0), s.P(bx + 0.06, by, h)); F.metti(1, s.P(bx, by, h), s.P(bx + 0.06, by, h))
        }
        Tav.traccia(&gc, F, piccolo)
        let da = D.stato.ventoDa * .pi / 180, dx = -sin(da), dy = cos(da), vel = D.stato.vento / 20, dt = M.dt
        var tratti = Path()
        for i in particelle.indices {
            var q = particelle[i]
            q.x += dx * vel * q.v * dt * 0.6; q.y += dy * vel * q.v * dt * 0.6
            if abs(q.x) > 1 || abs(q.y) > 1 {
                giroCaso += 2
                q.x = -dx * 0.95 + (OP.caso(giroCaso) - 0.5) * 1.8 * abs(dy)
                q.y = -dy * 0.95 + (OP.caso(giroCaso + 1) - 0.5) * 1.8 * abs(dx)
            }
            particelle[i] = q
            let z: Double = 0.18 + 0.06 * sin(Double(q.k)), coda: Double = 0.07 * (0.5 + vel)
            let a = s.P(q.x, q.y, z), b = s.P(q.x - dx * coda, q.y - dy * coda, z)
            tratti.move(to: CGPoint(x: a.x, y: a.y)); tratti.addLine(to: CGPoint(x: b.x, y: b.y))
        }
        gc.stroke(tratti, with: .color(OP.c(0.6)), style: Olo.tratto(1.1))
        guard !piccolo else { return }
        let rx = W - 34, ry = 52.0, r = 18.0
        gc.stroke(Olo.ellisse(rx, ry, r, r), with: .color(OP.c(0.5)), lineWidth: 1)
        for (i, l) in ["N", "E", "S", "O"].enumerated() { let a = Double(i) * 1.5708 - 1.5708; OP.scritta(&gc, l, rx + cos(a) * (r + 7), ry + sin(a) * (r + 7) + 3, 6.5, 700, OP.c(0.8)) }
        let fa = da - 1.5708
        var freccia = Path(); freccia.move(to: CGPoint(x: rx + cos(fa) * r, y: ry + sin(fa) * r)); freccia.addLine(to: CGPoint(x: rx - cos(fa) * r * 0.6, y: ry - sin(fa) * r * 0.6))
        gc.stroke(freccia, with: .color(OP.b(0.95)), lineWidth: 1.6)
        M.zona(rx, ry, 24, 0)
        Tav.testate(&gc, W, "VENTO · MILANO", "\(Int(D.stato.vento.rounded())) KM/H")
        if M.scelta == 0 {
            let nomi = ["NORD", "NORD-EST", "EST", "SUD-EST", "SUD", "SUD-OVEST", "OVEST", "NORD-OVEST"], v = D.stato.vento
            let i = Int((D.stato.ventoDa / 45).rounded()) % 8
            OP.riquadro(&gc, W, H, rx, ry, ["DA \(nomi[max(0, i)])", "\(Int(v.rounded())) KM/H", v > 25 ? "VENTO FORTE" : v > 12 ? "BREZZA" : "CALMO"], t - M.sceltaT, codice: "VENTO")
        }
    }
}

// MARK: EDITH · OCCHIALI, DRONI, SCUDO

/// Un controllo di EDITH: fatto = ha un esito a schermo; ok = l'esito è buono; pronto = si può far partire dal tocco (il campo è scritto).
struct ControlloEdith {
    let id: String
    let nome: String
    let esito: String
    let fatto: Bool
    let ok: Bool
    let pronto: Bool
}

struct DatiEdithOlo {
    var controlli: [ControlloEdith] = []
    var avvia: (String) -> Void = { _ in }
}

final class ProveEdith {
    private var parte: [Int: Double] = [:]

    func crea(_ k: Int) { parte = [:] }

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiEdithOlo, piccolo: Bool) {
        guard !D.controlli.isEmpty else { return }
        switch k {
        case 1: droni(&gc, W, H, t, M, D, piccolo)
        case 2: scudo(&gc, W, H, t, M, D, piccolo)
        default: occhiali(&gc, W, H, t, M, D, piccolo)
        }
    }

    private static func colore(_ c: ControlloEdith, _ a: Double = 1) -> Color { !c.fatto ? OP.c(0.45 * a) : c.ok ? OP.b(0.95 * a) : Tav.a(Tav.arancio, 0.95 * a) }
    private static func luce(_ c: ControlloEdith) -> Color { !c.fatto ? Tav.ciano : c.ok ? Tav.bianco : Tav.arancio }
    private static func righe(_ c: ControlloEdith) -> [String] {
        [c.nome, c.fatto ? OP.taglia(c.esito, 40) : "NON ANCORA CONTROLLATO",
         c.fatto ? (c.ok ? "A POSTO" : "DA SISTEMARE") : c.pronto ? "TOCCHI DI NUOVO: PARTE" : "SCRIVA NEL CAMPO SOTTO"]
    }

    /// Toccato di nuovo, un controllo non ancora fatto (col campo scritto) parte, come il suo tasto.
    private func toccoAvvia(_ M: ManoOlo, _ D: DatiEdithOlo, _ base: Int) {
        guard M.suTocco == nil else { return }
        let lista = D.controlli, avvia = D.avvia
        M.suTocco = { [weak M] id in
            guard let M, id >= base, id < base + lista.count else { return false }
            let c = lista[id - base]
            if !c.fatto && c.pronto && M.scelta == id { avvia(c.id); M.scelta = nil; return true }
            return false
        }
    }

    // OCCHIALI: gli occhiali di Peter in Far From Home; a sinistra l'elenco dei controlli, a destra il mirino sul punto debole
    private func occhiali(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiEdithOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.05, sz: 1.3, su: 0.3, oscilla: 0.35, mano: 0.6, conoSu: 0.1, conoW: 1.3))
        var F = FasciOlo(6)
        let Cs = D.controlli
        func lente(_ cxL: Double) -> [P3] {
            (0...48).map { k in let a = Double(k) / 48 * OP.due, rr = 0.36 + 0.035 * cos(2 * a) - 0.02 * sin(a); return P3(cxL + cos(a) * rr * 1.15, 0, 0.18 + sin(a) * rr * 0.82) }
        }
        let L = [lente(-0.5), lente(0.5)]
        for l in L { for k in 1..<l.count where Double(k) / Double(l.count) <= s.nasce { F.metti(3, s.Pv(l[k - 1]), s.Pv(l[k])) } }
        F.metti(3, s.P(-0.09, 0, 0.36), s.P(0.09, 0, 0.36))
        for lato in [-1.0, 1.0] {
            F.metti(2, s.P(lato * 0.91, 0, 0.32), s.P(lato * 0.98, 0.22, 0.34)); F.metti(1, s.P(lato * 0.98, 0.22, 0.34), s.P(lato * 0.98, 0.95, 0.3))
            F.metti(1, s.P(lato * 0.98, 0.95, 0.3), s.P(lato * 0.96, 1.05, 0.18))
        }
        Tav.traccia(&gc, F, piccolo)
        for (i, l) in L.enumerated() {
            let c = s.P(i == 1 ? 0.5 : -0.5, 0, 0.18)
            gc.fill(Tav.spezzata(l.map { s.Pv($0) }, chiusa: true), with: .color(OP.s(0.07)))
            Tav.alone(&gc, c, s.sz * 0.4, 0.07)
        }
        guard !piccolo else { return }
        let cL = s.P(-0.5, 0, 0.18), cR = s.P(0.5, 0, 0.18), fatti = Cs.filter(\.fatto), debole = Cs.first { $0.fatto && !$0.ok }
        let n = min(Cs.count, 9), passo = min(8.5, s.sz * 0.6 / Double(n)), y0 = cL.y - passo * Double(n - 1) / 2, cur = Int(max(0, t) * 1.2) % n
        for (k, c) in Cs.prefix(n).enumerated() {
            let y = y0 + Double(k) * passo + 2.5, vis = OP.lis((t - 0.3 - Double(k) * 0.08) / 0.25)
            guard vis > 0 else { continue }
            OP.scritta(&gc, OP.taglia(c.nome, 11), cL.x - s.sz * 0.36, y, 5.6, k == cur ? 800 : 600, k == cur ? OP.b(vis) : OP.c(0.85 * vis), .leading)
            OP.scritta(&gc, !c.fatto ? "·" : c.ok ? "OK" : "!", cL.x + s.sz * 0.36, y, 6, 800, ProveEdith.colore(c, vis), .trailing)
        }
        let col = debole != nil ? Tav.a(Tav.arancio, 0.9) : OP.b(0.8), r0 = 10 + 2 * sin(t * 4), a = t * 1.5
        gc.stroke(Olo.ellisse(cR.x, cR.y, r0, r0), with: .color(col), lineWidth: 1)
        var tacche = Path()
        for i in 0..<4 { let b = a + Double(i) * 1.5708; Olo.linea(&tacche, cR.x + cos(b) * (r0 + 4), cR.y + sin(b) * (r0 + 4), cR.x + cos(b) * (r0 + 10), cR.y + sin(b) * (r0 + 10)) }
        gc.stroke(tacche, with: .color(col), lineWidth: 1)
        gc.stroke(Tav.arco(cR.x, cR.y, r0 + 16, -a, -a + 2.2), with: .color(col), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        OP.scritta(&gc, debole.map { OP.taglia($0.nome, 11) } ?? (fatti.isEmpty ? "IN ATTESA" : "TUTTO A POSTO"), cR.x, cR.y + r0 + 26, 6.5, 800, debole != nil ? Tav.a(Tav.arancio, 0.95) : OP.b(0.9))
        M.zona(cL.x, cL.y, s.sz * 0.38, 0); M.zona(cR.x, cR.y, s.sz * 0.38, 1)
        Tav.testate(&gc, W, "E.D.I.T.H.", "\(fatti.filter(\.ok).count)/\(Cs.count) A POSTO", fatti.count < Cs.count ? "\(Cs.count - fatti.count) DA CONTROLLARE" : "TUTTO CONTROLLATO")
        if M.scelta == 0 {
            OP.riquadro(&gc, W, H, cL.x, cL.y, ["CONTROLLI", "FATTI \(fatti.count) DI \(Cs.count)", "DA SISTEMARE \(fatti.filter { !$0.ok }.count)"], t - M.sceltaT, codice: "LENTE SX")
        } else if M.scelta == 1 {
            let r = debole.map { ["PUNTO DEBOLE · \($0.nome)", OP.taglia($0.esito, 40), "DA SISTEMARE"] }
                ?? ["NESSUN PUNTO DEBOLE", fatti.isEmpty ? "NIENTE CONTROLLATO ANCORA" : "QUELLO CONTROLLATO È A POSTO", "EVEN DEAD, I'M THE HERO"]
            OP.riquadro(&gc, W, H, cR.x, cR.y, r, t - M.sceltaT, codice: "MIRINO")
        }
    }

    // DRONI: un drone per controllo attorno alla casa (la rete): a posto pattuglia, problema scende arancio sul punto, a terra se no
    private func droni(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiEdithOlo, _ piccolo: Bool) {
        toccoAvvia(M, D, 100)
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.42, sz: 1.1, su: 0.5, giro: 0.08, rx: 0.3, conoA: 0.05))
        var F = FasciOlo(6)
        let Cs = D.controlli, n = Double(Cs.count), b = 0.2, z1 = 0.28 * s.nasce, z2 = 0.45 * s.nasce
        let q: [(Double, Double)] = [(-b, -b), (b, -b), (b, b), (-b, b)]
        for (i, (a1, b1)) in q.enumerated() {
            let (a2, b2) = q[(i + 1) % 4]
            F.metti(2, s.P(a1, b1, 0), s.P(a2, b2, 0)); F.metti(2, s.P(a1, b1, z1), s.P(a2, b2, z1)); F.metti(2, s.P(a1, b1, 0), s.P(a1, b1, z1)); F.metti(2, s.P(a1, b1, z1), s.P(0, 0, z2))
        }
        F.metti(3, s.P(0, 0, z2), s.P(0, 0, 0.58 * s.nasce))
        Tav.cerchio(&F, s, 0.95, 0.01, 1, n: 72); Tav.cerchio(&F, s, 0.62, 0.01, 0, n: 48)
        Tav.traccia(&gc, F, piccolo)
        let ant = s.P(0, 0, 0.58 * s.nasce)
        for k in 0..<3 { let v = (t * 0.7 + Double(k) / 3).truncatingRemainder(dividingBy: 1); gc.stroke(Tav.arco(ant.x, ant.y, 6 + v * s.sz * 0.35, .pi * 1.15, .pi * 1.85), with: .color(OP.c(0.4 * (1 - v))), lineWidth: 1) }
        var punti: [P3] = []
        for (i, c) in Cs.enumerated() {
            let ai = Double(i) / n * OP.due, terra = P3(cos(ai) * 0.95, sin(ai) * 0.95, 0.03)
            if c.fatto && parte[i] == nil { parte[i] = t }
            let k = c.fatto ? OP.lis((t - (parte[i] ?? t)) / 1.2) : 0
            let a = t * 0.45 + ai
            let vol = c.ok ? P3(cos(a) * 0.8, sin(a) * 0.8, 0.55 + 0.07 * sin(t * 2 + Double(i))) : P3(cos(ai) * 0.36, sin(ai) * 0.36, 0.42 + 0.03 * sin(t * 3))
            let p3 = terra + (vol - terra) * k, p = s.Pv(p3), w = 6 + 2 * k
            var dr = Path(); Olo.linea(&dr, p.x - w, p.y, p.x + w, p.y); Olo.linea(&dr, p.x, p.y - 2, p.x, p.y + 2)
            gc.stroke(dr, with: .color(ProveEdith.colore(c)), lineWidth: 1.2)
            if k > 0.3 { gc.stroke(Olo.ellisse(p.x - w, p.y, 3, 1), with: .color(ProveEdith.colore(c)), lineWidth: 0.8); gc.stroke(Olo.ellisse(p.x + w, p.y, 3, 1), with: .color(ProveEdith.colore(c)), lineWidth: 0.8) }
            Tav.alone(&gc, p, 8, c.fatto ? 0.5 : 0.2, ProveEdith.luce(c))
            if c.fatto && !c.ok && k > 0.9 {
                let g = s.P(p3.x * 0.55, p3.y * 0.55, 0.12)
                var fascio = Path(); fascio.move(to: CGPoint(x: p.x, y: p.y)); fascio.addLine(to: CGPoint(x: g.x - 9, y: g.y)); fascio.addLine(to: CGPoint(x: g.x + 9, y: g.y)); fascio.closeSubpath()
                gc.fill(fascio, with: .color(Tav.a(Tav.arancio, 0.12)))
            }
            punti.append(p)
        }
        guard !piccolo else { return }
        for (i, p) in punti.enumerated() { M.zona(p.x, p.y, 14, 100 + i) }
        let fatti = Cs.filter(\.fatto), male = fatti.filter { !$0.ok }.count
        Tav.testate(&gc, W, "DRONI EDITH", male > 0 ? "\(male) DA SISTEMARE" : fatti.isEmpty ? "IN HANGAR" : "PERIMETRO PULITO", "\(fatti.count) IN VOLO · \(Cs.count - fatti.count) A TERRA")
        if let i = Tav.scelta(M, 100), i < Cs.count {
            OP.riquadro(&gc, W, H, punti[i].x, punti[i].y, ProveEdith.righe(Cs[i]), t - M.sceltaT, codice: "DRONE " + String(format: "%02d", i + 1))
        }
    }

    // SCUDO: la cupola a nido d'ape sopra la rete, uno spicchio per controllo (chiuso se a posto, aperto arancio, tratteggiato da fare)
    private func scudo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiEdithOlo, _ piccolo: Bool) {
        toccoAvvia(M, D, 200)
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.3, sz: 0.95, su: 0.32, giro: 0.1, rx: 0.32, cono: false))
        var F = FasciOlo(6)
        let Cs = D.controlli, n = Double(Cs.count)
        let E = { (a: Double, e: Double) -> P3 in s.P(cos(a) * cos(e), sin(a) * cos(e), sin(e) * s.nasce) }
        var centri: [P3] = []
        for (i, c) in Cs.enumerated() {
            let a0 = Double(i) / n * OP.due, a1 = Double(i + 1) / n * OP.due, g = c.fatto && c.ok ? 3 : 1
            for k in 0..<6 { F.metti(1, E(a0, Double(k) / 6 * 1.5708), E(a0, Double(k + 1) / 6 * 1.5708)) }
            for r in 0..<3 {
                for sk in 0..<2 {
                    if !c.fatto && (r + sk) % 2 == 1 { continue }
                    if c.fatto && !c.ok && r == 1 { continue }
                    let e0 = 0.12 + Double(r) * 0.42, am = a0 + (a1 - a0) * (Double(sk) + 0.5 + Double(r % 2) * 0.25) / 2.25, re = 0.17, ra = (a1 - a0) * 0.2
                    var qq: P3?
                    for h in 0...6 { let b = Double(h) / 6 * OP.due, p = E(am + cos(b) * ra, e0 + sin(b) * re); if let qq { F.metti(g, qq, p) }; qq = p }
                }
            }
            centri.append(E((a0 + a1) / 2, 0.55))
        }
        Tav.cerchio(&F, s, 1, 0, 3, n: 72)
        Tav.traccia(&gc, F, piccolo)
        let e = (t * 0.35).truncatingRemainder(dividingBy: 1) * 1.5708
        gc.stroke(Tav.spezzata((0...72).map { E(Double($0) / 72 * OP.due, e) }), with: .color(OP.b(0.45 * (1 - e / 1.5708))), lineWidth: 1.4)
        for (i, p) in centri.enumerated() {
            let c = Cs[i]
            if c.fatto && !c.ok { Tav.alone(&gc, p, 14 + 3 * sin(t * 5), 0.55, Tav.arancio) } else if c.fatto { Tav.alone(&gc, p, 10, 0.18, Tav.bianco) }
        }
        Tav.alone(&gc, E(0, 1.5708), s.sz * 0.5, 0.06)
        guard !piccolo else { return }
        for (i, p) in centri.enumerated() { M.zona(p.x, p.y, 16, 200 + i) }
        let ok = Cs.filter { $0.fatto && $0.ok }.count, fatti = Cs.filter(\.fatto).count
        Tav.testate(&gc, W, "SCUDO EDITH", "\(Int((Double(ok) / n * 100).rounded()))% CHIUSO", "\(ok) A POSTO · \(fatti - ok) APERTI · \(Cs.count - fatti) DA FARE")
        if let i = Tav.scelta(M, 200), i < Cs.count {
            OP.riquadro(&gc, W, H, centri[i].x, centri[i].y, ProveEdith.righe(Cs[i]), t - M.sceltaT, codice: "SPICCHIO \(i + 1)")
        }
    }
}

// MARK: POSTA · FIREWALL, FASCICOLI (SMISTA resta ProvePosta)

enum Sospetta {
    /// Le parole tipiche delle truffe (accessi, verifiche, password, premi, pagamenti): la mail resta ferma al muro.
    static func mail(_ oggetto: String) -> Bool {
        let o = oggetto.lowercased()
        return ["accesso", "verific", "password", "premio", "vinto", "bonifico", "sospes", "account", "conferma i dati", "pacco in giacenza"].contains { o.contains($0) }
    }
}

final class ProvePostaTavola {
    // FIREWALL: la posta arriva da internet e passa il muro esagonale fino alla casella; le sospette restano ferme, arancio
    func firewall(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: PostaOlo, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.22, sz: 1.15, su: 0.35, oscilla: 0.4, mano: 0.7, rx: 0.34, conoSu: 0.2, conoW: 1.4))
        var F = FasciOlo(6)
        let posta = D.posta ?? []
        for r in 0..<5 {
            for c in 0..<6 {
                let y = -0.75 + Double(c) * 0.3 + Double(r % 2) * 0.15, z = 0.08 + Double(r) * 0.17 * s.nasce, rr = 0.1
                if abs(y) > 0.82 { continue }
                var q: P3?
                for h in 0...6 { let b = Double(h) / 6 * OP.due + 0.5236, p = s.P(0, y + cos(b) * rr, z + sin(b) * rr * 0.95); if let q { F.metti(1, q, p) }; q = p }
            }
        }
        let zt = 0.85 * s.nasce
        F.metti(3, s.P(0, -0.85, 0), s.P(0, 0.85, 0)); F.metti(3, s.P(0, -0.85, zt), s.P(0, 0.85, zt)); F.metti(2, s.P(0, -0.85, 0), s.P(0, -0.85, zt)); F.metti(2, s.P(0, 0.85, 0), s.P(0, 0.85, zt))
        for lato in [-1.0, 1.0] { F.metti(0, s.P(lato * 0.15, -0.55, 0.02), s.P(lato * 1.05, -0.55, 0.02)); F.metti(0, s.P(lato * 0.15, 0.55, 0.02), s.P(lato * 1.05, 0.55, 0.02)) }
        func box(_ X: Double, _ w: Double, _ g: Int) {
            let a = s.P(X, -w, 0.35 - w * 0.6), b = s.P(X, w, 0.35 - w * 0.6), c = s.P(X, w, 0.35 + w * 0.6), d = s.P(X, -w, 0.35 + w * 0.6)
            F.metti(g, a, b); F.metti(g, b, c); F.metti(g, c, d); F.metti(g, d, a)
        }
        box(1.05, 0.22, 2); box(-1.05, 0.22, 1)
        Tav.traccia(&gc, F, piccolo)
        let m = Double(max(1, min(8, posta.count)))
        var pac: [(mail: PostaOlo.Mail, p: P3, sosp: Bool)] = []
        for (i, mail) in posta.prefix(8).enumerated() {
            let sosp = Sospetta.mail(mail.oggetto), u = (t * 0.16 + Double(i) / m).truncatingRemainder(dividingBy: 1), y = -0.55 + Double(i % 4) * 0.37, z = 0.2 + Double(i / 4) * 0.32
            let X = sosp ? -1.0 + min(u * 2.4, 0.92) : -1.0 + u * 2.0, fermo = sosp && u * 2.4 >= 0.92, p = s.P(X, y, z)
            let col = sosp ? Tav.a(Tav.arancio, 0.95) : OP.b(mail.letta ? 0.55 : 0.95)
            var busta = Path(CGRect(x: p.x - 5, y: p.y - 3.5, width: 10, height: 7))
            busta.move(to: CGPoint(x: p.x - 5, y: p.y - 3.5)); busta.addLine(to: CGPoint(x: p.x, y: p.y)); busta.addLine(to: CGPoint(x: p.x + 5, y: p.y - 3.5))
            gc.stroke(busta, with: .color(col), lineWidth: 1.1)
            Tav.alone(&gc, p, fermo ? 14 + 3 * sin(t * 6) : 8, fermo ? 0.6 : 0.3, sosp ? Tav.arancio : Tav.bianco)
            if abs(X) < 0.06 && !sosp { Tav.alone(&gc, s.P(0, y, z), 16, 0.45, Tav.bianco) }
            pac.append((mail, p, sosp))
        }
        guard !piccolo else { return }
        let iA = s.P(-1.05, 0, 0.75), iB = s.P(1.05, 0, 0.75)
        OP.scritta(&gc, "INTERNET", iA.x, iA.y, 6.5, 700, OP.c(0.85)); OP.scritta(&gc, "CASELLA", iB.x, iB.y, 6.5, 700, OP.c(0.85))
        for (i, q) in pac.enumerated() { M.zona(q.p.x, q.p.y, 12, i) }
        let sosp = pac.filter { $0.sosp }.count
        Tav.testate(&gc, W, "FIREWALL POSTA", D.posta != nil ? (sosp > 0 ? "\(sosp) DA VERIFICARE" : "TUTTO PULITO") : "APRO LA CASELLA", "\(pac.count - sosp) PASSATE")
        if let i = M.scelta, i >= 0, i < pac.count {
            let q = pac[i]
            OP.riquadro(&gc, W, H, q.p.x, q.p.y, [OP.taglia(q.mail.nome.uppercased(), 22), OP.taglia(q.mail.oggetto, 30),
                                                   q.sosp ? "FERMA AL MURO: DA VERIFICARE" : "PASSATA: NIENTE DI STRANO", q.sosp ? "NON APRA I LINK DELLA MAIL" : q.mail.data.uppercased()],
                        t - M.sceltaT, codice: q.sosp ? "ALLARME" : "PACCHETTO")
        }
    }

    // FASCICOLI: le mail come i fascicoli olografici di Avengers, su un arco; quella davanti aperta. Si sfogliano col dito.
    func fascicoli(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: PostaOlo, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.12, sz: 1.2, su: 0.12, giro: 0, mano: 0, rx: 0.3, conoSu: 0.1, conoW: 1.2))
        let posta = D.posta ?? [], n = posta.count
        guard n > 0 else { if !piccolo { Tav.testate(&gc, W, "FASCICOLI", "APRO LA CASELLA") }; return }
        let nd = Double(n), pos = ((M.giro * 2.2).truncatingRemainder(dividingBy: nd) + nd).truncatingRemainder(dividingBy: nd), dav = Int(pos.rounded()) % n
        var lista: [(d: Double, i: Int)] = []
        for i in 0..<n {
            var d = Double(i) - pos
            if d > nd / 2 { d -= nd }
            if d < -nd / 2 { d += nd }
            if abs(d) <= 2.6 { lista.append((d, i)) }
        }
        lista.sort { abs($0.d) > abs($1.d) }
        for (d, i) in lista {
            let mail = posta[i], a = d * 0.55, cx = sin(a) * 1.0, cy = -cos(a) * 0.5 + 0.5, w = 0.42, h = 0.56, z0 = 0.1, fr = abs(d) < 0.5, g = fr ? 4 : 1
            let rx = cos(a) * w, ry = sin(a) * w, hz = h * s.nasce
            let x0: Double = cx - rx, x1: Double = cx + rx, y0: Double = cy - ry, y1: Double = cy + ry, zt: Double = z0 + hz
            let c: [P3] = [s.P(x0, y0, z0), s.P(x1, y1, z0), s.P(x1, y1, zt), s.P(x0, y0, zt)]
            gc.fill(Tav.spezzata(c, chiusa: true), with: .color(OP.s(fr ? 0.1 : 0.04)))
            var Fk = FasciOlo(6)
            for k in 0..<4 { Fk.metti(g, c[k], c[(k + 1) % 4]) }
            let zl: Double = z0 + (h + 0.06) * s.nasce
            let tab: [P3] = [s.P(x0, y0, zt), s.P(cx - rx * 0.4, cy - ry * 0.4, zt), s.P(cx - rx * 0.3, cy - ry * 0.3, zl), s.P(cx - rx * 0.9, cy - ry * 0.9, zl)]
            Fk.metti(g - 1, tab[0], tab[3]); Fk.metti(g - 1, tab[3], tab[2]); Fk.metti(g - 1, tab[2], tab[1])
            Tav.traccia(&gc, Fk, piccolo, k: fr ? 1.1 : 0.8)
            guard !piccolo else { continue }
            let al = max(0.15, 1 - abs(d) * 0.45), m0 = s.P(cx, cy, z0 + h * 0.82), m1 = s.P(cx, cy, z0 + h * 0.6), m2 = s.P(cx, cy, z0 + h * 0.42), m3 = s.P(cx, cy, z0 + h * 0.15)
            OP.scritta(&gc, OP.taglia(mail.nome.uppercased(), fr ? 16 : 9), m0.x, m0.y, fr ? 8 : 6, 800, OP.b(al))
            if fr {
                OP.scritta(&gc, OP.taglia(mail.oggetto, 22), m1.x, m1.y, 6.5, 600, OP.c(0.95))
                OP.scritta(&gc, mail.data.uppercased(), m2.x, m2.y, 5.5, 600, OP.c(0.7))
                OP.scritta(&gc, mail.letta ? "LETTA" : "● DA LEGGERE", m3.x, m3.y, 6, 800, mail.letta ? OP.c(0.6) : OP.b(0.95))
                M.zona(m1.x, m1.y, 26, i)
            }
        }
        guard !piccolo else { return }
        Tav.testate(&gc, W, "FASCICOLI", "\(dav + 1) / \(n)", "\(posta.filter { !$0.letta }.count) DA LEGGERE")
        if let i = M.scelta, i >= 0, i < n {
            let mail = posta[i], p = s.P(0, 0, 0.5)
            OP.riquadro(&gc, W, H, p.x, p.y, [mail.nome.uppercased(), OP.taglia(mail.oggetto, 30), mail.data.uppercased(), Sospetta.mail(mail.oggetto) ? "ATTENZIONE: SEMBRA UNA TRUFFA" : "MITTENTE IN ORDINE"],
                        t - M.sceltaT, codice: "FASCICOLO \(i + 1)")
        }
    }
}

#if os(iOS)
// MARK: MESSAGGI · RETE, ORBITE (BOLLE resta ProveMessaggi)

enum ProveMessaggiTavola {
    private static func recente(_ v: MessaggiOlo.Voce) -> Bool { v.quando.map { Date().timeIntervalSince($0) < 3600 } ?? false }

    // RETE: lei al centro, ogni persona un nodo (più vicino chi sente di più), i messaggi come impulsi sul filo
    static func rete(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: MessaggiOlo, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.38, sz: 1.05, su: 0.55, giro: 0.12))
        var F = FasciOlo(6)
        var nomi: [String] = [], per: [String: [MessaggiOlo.Voce]] = [:]
        for v in D.voci { if per[v.nome] == nil { nomi.append(v.nome) }; per[v.nome, default: []].append(v) }
        let n = Double(max(1, nomi.count)), io = P3(0, 0, 0.3)
        let nodi: [(nm: String, k: Int, q: P3, ult: MessaggiOlo.Voce)] = nomi.enumerated().compactMap { (i: Int, nm: String) -> (nm: String, k: Int, q: P3, ult: MessaggiOlo.Voce)? in
            guard let l = per[nm], let u = l.first else { return nil }
            let a = Double(i) / n * OP.due + 0.3, r = (0.95 - min(0.4, Double(l.count) * 0.1)) * s.nasce, z = 0.25 + 0.25 * sin(Double(i) * 2.3)
            return (nm, l.count, P3(cos(a) * r, sin(a) * r, z), u)
        }
        for d in nodi { F.metti(1, s.Pv(io), s.Pv(d.q)); F.metti(0, s.P(d.q.x, d.q.y, 0), s.Pv(d.q)) }
        if nodi.count > 2 { for (i, d) in nodi.enumerated() { F.metti(0, s.Pv(d.q), s.Pv(nodi[(i + 1) % nodi.count].q)) } }
        Tav.cerchio(&F, s, 0.12, 0.3, 3, n: 24); Tav.cerchio(&F, s, 1.0, 0, 0, n: 64)
        Tav.traccia(&gc, F, piccolo)
        let pc = s.Pv(io)
        Tav.alone(&gc, pc, s.sz * 0.35, 0.25, Tav.bianco)
        for (i, d) in nodi.enumerated() {
            let p = s.Pv(d.q)
            Tav.alone(&gc, p, 8 + Double(d.k) * 2, M.scelta == i ? 0.8 : 0.45, d.ult.tipo == "whatsapp" ? Tav.verde : Tav.bianco)
            gc.stroke(Olo.ellisse(p.x, p.y, 3 + Double(d.k), 3 + Double(d.k)), with: .color(OP.b(0.9)), lineWidth: 1)
            for (k, v) in (per[d.nm] ?? []).prefix(3).enumerated() {
                let fr = recente(v) ? 1.4 : 0.7, u = (t * 0.6 * fr + Double(k) * 0.33 + Double(i) * 0.17).truncatingRemainder(dividingBy: 1), w = v.ricevuto ? u : 1 - u
                Tav.alone(&gc, s.Pv(d.q + (io - d.q) * w), 5, 0.8, Tav.bianco)
            }
        }
        guard !piccolo else { return }
        OP.scritta(&gc, "LEI", pc.x, pc.y + 3, 6.5, 800, OP.b(0.95))
        for (i, d) in nodi.enumerated() { let p = s.Pv(d.q); OP.scritta(&gc, d.nm.uppercased(), p.x, p.y - 9 - Double(d.k), 6.5, 700, OP.c(0.95)); M.zona(p.x, p.y, 14, i) }
        Tav.testate(&gc, W, "RETE COMUNICAZIONI", "\(D.voci.count) MESSAGGI", "\(nodi.count) PERSONE")
        if let i = M.scelta, i >= 0, i < nodi.count {
            let d = nodi[i], p = s.Pv(d.q)
            OP.riquadro(&gc, W, H, p.x, p.y, [d.nm.uppercased(), "«\(OP.taglia(d.ult.testo, 28))»", "\(d.ult.ricevuto ? "RICEVUTO" : "MANDATO DA JARVIS") · \(Tav.fa(d.ult.quando))",
                                               "\(d.k) MESSAGGI · \(d.ult.tipo == "whatsapp" ? "WHATSAPP" : "IMESSAGE")"], t - M.sceltaT, codice: "NODO")
        }
    }

    // ORBITE: iMessage dentro, WhatsApp fuori; ogni messaggio un satellite, il ricevuto con la coda verso di lei
    static func orbite(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: MessaggiOlo, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.35, sz: 1.2, su: 0.62, giro: 0.1))
        var F = FasciOlo(6)
        let V = Array(D.voci.prefix(12))
        let orb: [String: (Double, Double)] = ["imessage": (0.6, 0.35), "whatsapp": (1.0, -0.45)]
        let Q = { (r: Double, inc: Double, a: Double) -> P3 in P3(cos(a) * r * s.nasce, sin(a) * r * cos(inc) * s.nasce, sin(a) * r * sin(inc) * s.nasce) }
        for (r, inc) in orb.values { var q: P3?; for k in 0...72 { let p = s.Pv(Q(r, inc, Double(k) / 72 * OP.due)); if let q { F.metti(1, q, p) }; q = p } }
        for k in 0..<3 {
            var q: P3?
            let ck: Double = cos(Double(k)), sk: Double = sin(Double(k))
            for i in 0...32 { let a: Double = Double(i) / 32 * OP.due, r: Double = sin(a) * 0.14, p = s.P(cos(a) * 0.14, r * ck, r * sk); if let q { F.metti(3, q, p) }; q = p }
        }
        Tav.traccia(&gc, F, piccolo)
        var conta: [String: Int] = ["imessage": 0, "whatsapp": 0]
        var sat: [(v: MessaggiOlo.Voce, p: P3, c: String)] = []
        for v in V {
            let c = v.tipo == "whatsapp" ? "whatsapp" : "imessage", o = orb[c] ?? (0.6, 0.35), r = o.0, inc = o.1, k = conta[c] ?? 0
            conta[c] = k + 1
            let a = 1.5708 - Double(k) * 0.55 + t * (c == "whatsapp" ? 0.12 : 0.2), q = Q(r, inc, a), p = s.Pv(q)
            if v.ricevuto {
                let c2 = s.Pv(q * 0.75)
                var coda = Path(); coda.move(to: CGPoint(x: p.x, y: p.y)); coda.addLine(to: CGPoint(x: c2.x, y: c2.y))
                gc.stroke(coda, with: .linearGradient(Gradient(colors: [OP.b(0.6), OP.b(0)]), startPoint: CGPoint(x: p.x, y: p.y), endPoint: CGPoint(x: c2.x, y: c2.y)), lineWidth: 1.2)
            }
            Tav.alone(&gc, p, 7, recente(v) ? 0.9 : 0.45, c == "whatsapp" ? Tav.verde : Tav.bianco)
            sat.append((v, p, c))
        }
        Tav.alone(&gc, s.P(0, 0, 0), s.sz * 0.3, 0.3, Tav.bianco)
        guard !piccolo else { return }
        for (nome, chiave) in [("IMESSAGE", "imessage"), ("WHATSAPP", "whatsapp")] {
            if let o = orb[chiave] { let p = s.Pv(Q(o.0, o.1, 3.6)); OP.scritta(&gc, nome, p.x, p.y + 10, 6, 700, OP.c(0.85)) }
        }
        for (i, q) in sat.enumerated() { M.zona(q.p.x, q.p.y, 11, i) }
        Tav.testate(&gc, W, "ORBITE", "\(conta["imessage"] ?? 0) IMESSAGE · \(conta["whatsapp"] ?? 0) WHATSAPP", D.scelto.map { "SCRIVE A \($0.uppercased())" })
        if let i = M.scelta, i >= 0, i < sat.count {
            let q = sat[i]
            OP.riquadro(&gc, W, H, q.p.x, q.p.y, [q.v.nome.uppercased(), "«\(OP.taglia(q.v.testo, 28))»", "\(q.v.ricevuto ? "RICEVUTO" : "MANDATO") · \(Tav.fa(q.v.quando))"],
                        t - M.sceltaT, codice: q.c.uppercased())
        }
    }
}

// MARK: CONFIDENTE · MENTE, ONDA (BILANCIA resta ProveConfidente)

enum ProveConfidenteTavola {
    /// I temi della conversazione: nome, parole, e dove si accendono sul cervello (davanti a destra).
    private static let temi: [(nome: String, parole: [String], x: Double, z: Double)] = [
        ("LAVORO", ["lavor", "client", "serat", "soldi", "pagament", "fattur", "capo", "progett"], 0.62, 0.3),
        ("AMORE", ["ti amo", "bacio", "cuore", "insieme", "manchi", "tesoro", "amore", "amo "], 0.05, 0.6),
        ("AMICI", ["amic", "uscire", "birra", "festa", "cena", "ragazzi"], -0.5, 0.38),
        ("FAMIGLIA", ["mamma", "papà", "fratell", "sorell", "famiglia", "nonn"], -0.6, 0.02),
        ("TENSIONE", ["sempre tu", "mai ", "basta", "stanco", "stanca", "arrabbiat", "scusa", "colpa", "lascia stare", "non capisci"], 0.3, -0.22),
        ("PIANI", ["domani", "sabato", "venerd", "weekend", "vacanz", "stasera", "ci vediamo"], -0.15, 0.2),
    ]
    private static let positive = ["grazie", "bello", "bella", "felice", "contento", "contenta", "amo", "❤", "😊", "😂", "perfetto", "ok", "va bene", "dai che", "bravo", "brava", "top", "grande"]
    private static let negative = ["no", "basta", "stanc", "arrabbiat", "sempre", "mai", "scusa", "colpa", "male", "triste", "😢", "😡", "non capisci", "lascia stare"]

    static func righe(_ s: String) -> [String] { s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private static func conta(_ testo: String, _ parola: String) -> Int { testo.components(separatedBy: parola).count - 1 }
    static func tono(_ r: String) -> Int {
        let t = " " + r.lowercased() + " "
        let p = positive.reduce(0) { $0 + conta(t, $1.count <= 3 ? " \($1) " : $1) }, n = negative.reduce(0) { $0 + conta(t, $1.count <= 3 ? " \($1) " : $1) }
        return p - n
    }

    // il profilo laterale del cervello (davanti a destra): lobi, cervelletto e tronco
    private static let K: [(Double, Double)] = [(0.95, 0.05), (0.9, 0.36), (0.72, 0.6), (0.42, 0.76), (0.05, 0.8), (-0.35, 0.72), (-0.68, 0.52), (-0.9, 0.22), (-0.95, -0.08),
                                                (-0.82, -0.28), (-0.6, -0.3), (-0.38, -0.22), (-0.1, -0.24), (0.15, -0.38), (0.45, -0.42), (0.72, -0.28), (0.88, -0.12)]
    private static let profilo: [(Double, Double)] = (0...80).map { i in
        let n = K.count, f = Double(i) / 80 * Double(n), k = Int(f) % n, s = f - floor(f)
        let p0 = K[(k - 1 + n) % n], p1 = K[k], p2 = K[(k + 1) % n], p3 = K[(k + 2) % n]
        func c(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double { 0.5 * (2 * b + (-a + c) * s + (2 * a - 5 * b + 4 * c - d) * s * s + (-a + 3 * b - 3 * c + d) * s * s * s) }
        return (c(p0.0, p1.0, p2.0, p3.0), c(p0.1, p1.1, p2.1, p3.1))
    }

    // MENTE: il cervello di profilo a strati (Extremis, Iron Man 3): i temi della conversazione accendono le loro zone
    static func mente(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, testo: String, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.08, sz: 1.05, su: 0.42, oscilla: 0.45, mano: 0.6, conoSu: 0.2, conoW: 1.0))
        var F = FasciOlo(6)
        let Z = 0.15, nb = s.nasce
        for k in 0..<7 {
            let y = -0.42 + Double(k) * 0.14, sc = (max(0, 1 - pow(y / 0.48, 2))).squareRoot() * nb
            var q: P3?
            for (a, b) in profilo { let p = s.P(a * sc, y, Z + 0.45 + b * sc * 0.82); if let q { F.metti(k == 3 ? 3 : 1, q, p) }; q = p }
        }
        func solco(_ pts: [(Double, Double)], _ g: Int) { var q: P3?; for (a, b) in pts { let p = s.P(a * nb, 0.02, Z + 0.45 + b * 0.82 * nb); if let q { F.metti(g, q, p) }; q = p } }
        solco([(0.12, 0.79), (0.05, 0.5), (-0.02, 0.25), (0.05, 0.08)], 3); solco([(0.72, -0.05), (0.35, 0.02), (0.0, 0.0), (-0.3, 0.12)], 3)
        solco([(0.6, 0.62), (0.55, 0.35), (0.62, 0.12)], 1); solco([(-0.4, 0.68), (-0.35, 0.4), (-0.5, 0.2)], 1); solco([(0.85, 0.3), (0.6, 0.4), (0.35, 0.45)], 1)
        for k in 0..<5 {
            let r = 0.22 - Double(k) * 0.025
            var q: P3?
            for i in 0...16 {
                let a: Double = 3.3 + Double(i) / 16 * 2.7, px: Double = (-0.45 + cos(a) * r * 1.3) * nb
                let pz: Double = Z + 0.45 + (-0.3 + sin(a) * r * 0.75 - Double(k) * 0.02) * 0.82 * nb
                let p = s.P(px, 0, pz)
                if let q { F.metti(2, q, p) }
                q = p
            }
        }
        F.metti(2, s.P(-0.05, 0, Z + 0.45 - 0.2 * 0.82), s.P(-0.18, 0, Z - 0.05)); F.metti(2, s.P(0.1, 0, Z + 0.45 - 0.3 * 0.82), s.P(-0.04, 0, Z - 0.05))
        Tav.traccia(&gc, F, piccolo)
        let basso = testo.lowercased()
        let zone: [(nome: String, n: Int, parole: [String], p: P3)] = temi.map { tema in
            let trovate = tema.parole.filter { basso.contains($0) }
            return (tema.nome, tema.parole.reduce(0) { $0 + conta(basso, $1) }, Array(trovate.prefix(3)), s.P(tema.x * nb, 0, Z + 0.45 + tema.z * 0.82 * nb))
        }
        for z in zone where z.n > 0 {
            Tav.alone(&gc, z.p, s.sz * (0.16 + min(0.2, Double(z.n) * 0.04)), min(0.8, 0.28 + Double(z.n) * 0.12) * (0.85 + 0.15 * sin(t * 3 + z.p.x)), z.nome == "TENSIONE" ? Tav.arancio : Tav.bianco)
        }
        let sw = (t * 0.35).truncatingRemainder(dividingBy: 1) * 2 - 1
        Tav.segmento(&gc, s.P(sw * 0.95, 0, Z - 0.05), s.P(sw * 0.95, 0, Z + 1.15), OP.s(0.35), 1)
        guard !piccolo else { return }
        for (i, z) in zone.enumerated() {
            OP.scritta(&gc, z.nome, z.p.x, z.p.y + 3, 6, 800, z.n > 0 ? (z.nome == "TENSIONE" ? Tav.a(Tav.arancio, 0.95) : OP.b(0.95)) : OP.c(0.35))
            M.zona(z.p.x, z.p.y, 18, i)
        }
        let pieno = !testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, forte = zone.filter { $0.n > 0 }.max { $0.n < $1.n }
        Tav.testate(&gc, W, "MAPPA DELLA MENTE", pieno ? (forte?.nome ?? "NEUTRA") : "IN ATTESA", pieno ? "\(righe(testo).count) RIGHE LETTE" : "INCOLLI UNA CONVERSAZIONE")
        if let i = M.scelta, i >= 0, i < zone.count {
            let z = zone[i]
            OP.riquadro(&gc, W, H, z.p.x, z.p.y, [z.nome, z.n > 0 ? "\(z.n) VOLTE NELLA CONVERSAZIONE" : "NON COMPARE", z.parole.isEmpty ? "—" : z.parole.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " · ").uppercased()],
                        t - M.sceltaT, codice: "ZONA")
        }
    }

    // ONDA: il tono riga per riga come un nastro (su caldo, giù teso arancio); le righe dell'altro davanti, le sue dietro
    static func onda(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, testo: String, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.3, sz: 1.2, su: 0.5, oscilla: 0.5, mano: 0.6, rx: 0.3, conoW: 1.3))
        var F = FasciOlo(6)
        var R = righe(testo)
        let vuoto = R.isEmpty
        if vuoto { R = Array(repeating: "", count: 14) }
        let n = min(R.count, 24), R2 = Array(R.suffix(n)), X = { (i: Int) -> Double in -1 + 2 * Double(i) / Double(max(1, n - 1)) }
        let v: [Double] = R2.enumerated().map { i, r in vuoto ? 0.12 * sin(t * 2 + Double(i) * 0.7) : max(-1, min(1, Double(tono(r)) / 2)) * 0.45 }
        let lato: [Double] = R2.enumerated().map { i, r in
            let l = r.lowercased()
            if l.hasPrefix("io:") || l.hasPrefix("me:") || l.hasPrefix("tu:") { return 0.25 }
            if let d = r.firstIndex(of: ":"), r.distance(from: r.startIndex, to: d) <= 18 { return -0.25 }
            return i % 2 == 1 ? 0.25 : -0.25
        }
        F.metti(0, s.P(-1, 0, 0.5), s.P(1, 0, 0.5))
        if n > 1 {
            for i in 1..<n { for dy in [-0.06, 0.06] { F.metti(v[i] < -0.05 ? 2 : 3, s.P(X(i - 1), lato[i - 1] + dy, 0.5 + v[i - 1] * s.nasce), s.P(X(i), lato[i] + dy, 0.5 + v[i] * s.nasce)) } }
        }
        for i in 0..<n { F.metti(0, s.P(X(i), lato[i], 0.5), s.P(X(i), lato[i], 0.5 + v[i] * s.nasce)) }
        Tav.traccia(&gc, F, piccolo)
        let pts: [P3] = (0..<n).map { i in s.P(X(i), lato[i], 0.5 + v[i] * s.nasce) }
        if !vuoto {
            for (i, p) in pts.enumerated() { Tav.alone(&gc, p, 6, 0.6, v[i] < -0.05 ? Tav.arancio : Tav.bianco) }
            Tav.alone(&gc, pts[Int(max(0, t) * 3) % n], 12, 0.7, Tav.bianco)
        }
        guard !piccolo else { return }
        if !vuoto { for (i, p) in pts.enumerated() { M.zona(p.x, p.y, 10, i) } }
        let media = vuoto ? 0 : v.reduce(0, +) / Double(n)
        Tav.testate(&gc, W, "ONDA DEL TONO", vuoto ? "IN ATTESA" : media > 0.08 ? "CALDA" : media < -0.08 ? "TESA" : "NEUTRA",
                    vuoto ? "INCOLLI UNA CONVERSAZIONE" : "\(n) RIGHE · \(v.filter { $0 < -0.05 }.count) TESE")
        if !vuoto, let i = M.scelta, i >= 0, i < n {
            OP.riquadro(&gc, W, H, pts[i].x, pts[i].y, ["RIGA \(i + 1)", "«\(OP.taglia(R2[i], 30))»", v[i] > 0.05 ? "TONO CALDO" : v[i] < -0.05 ? "TONO TESO" : "TONO NEUTRO"], t - M.sceltaT, codice: "ONDA")
        }
    }
}

// MARK: INTERPRETE · GLOBO, VOCI (PONTE resta PonteInterprete)

enum ProveInterpreteTavola {
    static let paesi: [String: (nome: String, lat: Double, lon: Double)] = [
        "IT": ("ITALIA", 42.5, 12.5), "EN": ("REGNO UNITO", 52, -1.5), "ES": ("SPAGNA", 40, -3.7), "FR": ("FRANCIA", 46.5, 2.5), "DE": ("GERMANIA", 51, 10),
        "PT": ("BRASILE", -12, -50), "ZH": ("CINA", 34, 105), "JA": ("GIAPPONE", 36, 138), "AR": ("ARABIA SAUDITA", 24, 45),
    ]

    // GLOBO: l'Italia e il Paese della lingua accesi, l'arco della traduzione; ogni frase un impulso
    static func globo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, codice: String, frasi: [PonteInterprete.Frase], piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.32, sz: 0.82, su: 0.95, giro: 0, mano: 0.8, conoSu: 0.3))
        var F = FasciOlo(6)
        let dst = paesi[codice], it = paesi["IT"] ?? ("ITALIA", 42.5, 12.5), lonC = dst.map { (it.lon + $0.lon) / 2 } ?? it.lon
        let giro = -lonC + sin(t * 0.15) * 15 + M.giro * 40
        let G = Tav.globo(&F, s, 1, giroLon: giro)
        var arco: [P3] = []
        if let dst {
            for k in 0...40 {
                let u = Double(k) / 40, la = it.lat + (dst.lat - it.lat) * u, lo = it.lon + (dst.lon - it.lon) * u
                let h = 1 + 0.35 * sin(.pi * u) * min(1, abs(dst.lon - it.lon) / 60 + 0.3)
                arco.append(s.Pv(Tav.geo(la, lo + giro, h * s.nasce)))
            }
            for k in 1..<arco.count { F.metti(4, arco[k - 1], arco[k]) }
        }
        Tav.traccia(&gc, F, piccolo)
        let pI = G(it.lat, it.lon), pD = dst.map { G($0.lat, $0.lon) }
        Tav.alone(&gc, pI, 12, pI.z < 0 ? 0.9 : 0.3, Tav.bianco)
        if let pD { Tav.alone(&gc, pD, 12, pD.z < 0 ? 0.9 : 0.3, Tav.bianco) }
        if !arco.isEmpty {
            for (k, f) in frasi.suffix(4).enumerated() {
                let u = (t * 0.5 + Double(k) * 0.25).truncatingRemainder(dividingBy: 1), i = Int(((f.altro ? 1 - u : u) * 40).rounded())
                Tav.alone(&gc, arco[max(0, min(40, i))], 7, 0.9, Tav.bianco)
            }
        }
        guard !piccolo else { return }
        OP.scritta(&gc, "ITALIA", pI.x, pI.y - 12, 6.5, 800, OP.b(0.95)); M.zona(pI.x, pI.y, 16, 0)
        if let pD, let dst { OP.scritta(&gc, dst.nome, pD.x, pD.y - 12, 6.5, 800, OP.b(0.95)); M.zona(pD.x, pD.y, 16, 1) }
        Tav.testate(&gc, W, "GLOBO · INTERPRETE", dst != nil ? "IT ⇄ \(codice)" : "SCELGA LA LINGUA", "\(frasi.count) FRASI TRADOTTE")
        if let sc = M.scelta, sc == 0 || (sc == 1 && pD != nil) {
            let p = sc == 0 ? pI : (pD ?? pI), mie = frasi.filter { sc == 0 ? !$0.altro : $0.altro }
            OP.riquadro(&gc, W, H, p.x, p.y, [sc == 0 ? "ITALIA" : (dst?.nome ?? ""), sc == 0 ? "LEI PARLA ITALIANO" : "L'ALTRO PARLA \(codice)", "\(mie.count) FRASI",
                                               mie.last.map { "«\(OP.taglia($0.testo, 26))»" } ?? "ANCORA NIENTE"], t - M.sceltaT, codice: "VOCE")
        }
    }

    // VOCI: due spettrogrammi a cascata (lei a sinistra, l'altro a destra); chi ha parlato per ultimo è acceso
    static func voci(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, codice: String, frasi: [PonteInterprete.Frase], piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.45, sz: 1.15, su: 0.35, oscilla: 0.18, mano: 0.6, rx: 0.32, conoW: 1.5))
        var F = FasciOlo(6)
        let attivo = frasi.last.map { $0.altro ? 1 : 0 } ?? -1
        let lati: [(Double, String)] = [(-0.55, "IT"), (0.55, codice)]
        func seme(_ i: Int, _ k: Int) -> Double { 0.5 + 0.5 * sin(Double(i) * 12.9898 + Double(k) * 78.233) }
        for (li, (cx, _)) in lati.enumerated() {
            let on = li == attivo
            for r in 0..<9 {
                let y = -0.6 + Double(r) * 0.15, fase = Int(t * 6) - r
                var q: P3?
                for b in 0...16 {
                    let X = cx - 0.42 + Double(b) * 0.0525, env = sin(.pi * Double(b) / 16)
                    let forza: Double = on ? 0.35 : 0.08, rumore: Double = 0.3 + 0.7 * seme(fase, b + li * 31), cala: Double = 1 - Double(r) / 12
                    let amp: Double = forza * env * rumore * cala * s.nasce
                    let p = s.P(X, y, 0.12 + amp)
                    if let q { F.metti(r == 0 ? (on ? 4 : 2) : on ? 2 : 0, q, p) }
                    q = p
                }
            }
        }
        Tav.traccia(&gc, F, piccolo)
        guard !piccolo else { return }
        for (li, (cx, nome)) in lati.enumerated() {
            let p = s.P(cx, -0.75, 0.12)
            OP.scritta(&gc, li == 1 ? "ALTRO · \(nome)" : "LEI · IT", p.x, p.y + 12, 7, 800, li == attivo ? OP.b(0.95) : OP.c(0.6))
            let pz = s.P(cx, 0, 0.3); M.zona(pz.x, pz.y, s.sz * 0.4, li)
        }
        Tav.testate(&gc, W, "SPETTRO DELLE VOCI", attivo < 0 ? "IN ASCOLTO" : attivo == 1 ? "PARLA L'ALTRO" : "PARLA LEI", "\(frasi.count) FRASI")
        if let sc = M.scelta, sc == 0 || sc == 1 {
            let mie = frasi.filter { sc == 1 ? $0.altro : !$0.altro }, p = s.P(lati[sc].0, 0, 0.35)
            let r = mie.last.map { [sc == 1 ? "L'ALTRO HA DETTO" : "LEI HA DETTO", "«\(OP.taglia($0.testo, 26))»", "→ \(OP.taglia($0.trad, 26))"] } ?? [sc == 1 ? "L'ALTRO" : "LEI", "ANCORA NESSUNA FRASE"]
            OP.riquadro(&gc, W, H, p.x, p.y, r, t - M.sceltaT, codice: "VOCE")
        }
    }
}

#endif

// MARK: RICORDI · B.A.R.F., MAPPA (SENTIERO resta SentieroTraccia)

struct RicordoOlo { let tipo: String; let testo: String; let chi: String?; let dove: String?; let quando: String }
struct LuogoOlo { let nome: String; let via: String; let quando: String; let metri: Double? }

enum ProveRicordiTavola {
    private static let simboli: [String: String] = ["oggetto": "⌘", "persona": "◉", "visto": "◎", "idea": "✦", "promessa": "✓", "posto": "⌖"]

    // B.A.R.F.: i ricordi nei cubi di luce di Civil War, in fila su un arco; quello davanti si legge. Si scorre col dito.
    static func barf(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ R: [RicordoOlo], piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.2, sz: 1.15, su: 0.1, giro: 0, mano: 0, rx: 0.32, conoSu: 0.05, conoW: 1.1))
        let n = R.count
        guard n > 0 else { if !piccolo { Tav.testate(&gc, W, "B.A.R.F.", "NESSUN RICORDO") }; return }
        let nd = Double(n), pos = ((M.giro * 2).truncatingRemainder(dividingBy: nd) + nd).truncatingRemainder(dividingBy: nd)
        var lista: [(d: Double, i: Int)] = []
        for i in 0..<n {
            var d = Double(i) - pos
            if d > nd / 2 { d -= nd }
            if d < -nd / 2 { d += nd }
            if abs(d) <= 2.4 { lista.append((d, i)) }
        }
        lista.sort { abs($0.d) > abs($1.d) }
        for (d, i) in lista {
            let r = R[i], a = d * 0.62, cx = sin(a) * 1.0, cy = -cos(a) * 0.55 + 0.55, fr = abs(d) < 0.5
            let sc = (fr ? 0.36 : 0.24) * (fr ? 1 + 0.03 * sin(t * 3) : 1), z0 = 0.06 + (fr ? 0.05 * sin(t * 1.4) : 0), g = fr ? 4 : 1
            var F = FasciOlo(6)
            var v: [P3] = []
            for zx in [-1.0, 1.0] { for zy in [-1.0, 1.0] { for zz in [0.0, 1.0] { v.append(P3(cx + zx * sc, cy + zy * sc, z0 + zz * 2 * sc * s.nasce)) } } }
            for p in 0..<8 {
                for q in (p + 1)..<8 {
                    let diversi = (v[p].x != v[q].x ? 1 : 0) + (v[p].y != v[q].y ? 1 : 0) + (v[p].z != v[q].z ? 1 : 0)
                    if diversi == 1 { F.metti(g - (v[p].y > cy && v[q].y > cy ? 1 : 0), s.Pv(v[p]), s.Pv(v[q])) }
                }
            }
            Tav.traccia(&gc, F, piccolo, k: fr ? 1 : 0.75)
            let c = s.P(cx, cy, z0 + sc * s.nasce)
            Tav.alone(&gc, c, s.sz * sc * 1.4, fr ? 0.28 : 0.1, Tav.bianco)
            guard !piccolo else { continue }
            OP.scritta(&gc, simboli[r.tipo] ?? "✦", c.x, c.y + (fr ? 6 : 4), fr ? 18 : 11, 700, OP.b(fr ? 0.95 : 0.5))
            if fr {
                let tp = s.P(cx, cy, z0 + 2 * sc * s.nasce + 0.1)
                OP.scritta(&gc, OP.taglia(r.testo.uppercased(), 30), tp.x, tp.y, 7, 800, OP.b(0.95))
                OP.scritta(&gc, OP.taglia([r.chi, r.dove, r.quando].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased(), 34), tp.x, tp.y + 10, 5.8, 600, OP.c(0.85))
                M.zona(c.x, c.y, s.sz * sc * 1.2, i)
            }
        }
        guard !piccolo else { return }
        Tav.testate(&gc, W, "B.A.R.F.", "\(Int(pos.rounded()) % n + 1) / \(n)", "RICORDI IN SCENA")
        if let i = M.scelta, i >= 0, i < n {
            let r = R[i], p = s.P(0, 0.1, 0.4), chi = [r.chi, r.dove].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
            OP.riquadro(&gc, W, H, p.x, p.y, [r.tipo.uppercased(), OP.taglia(r.testo, 32), chi.isEmpty ? "—" : chi, r.quando.uppercased()], t - M.sceltaT, codice: "MEMORIA")
        }
    }

    // MAPPA: il plastico della città (come il modello della casa di Malibu): i posti salvati come fari, lei al centro
    static func mappa(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ L: [LuogoOlo], scelto: Int, piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.55, sz: 1.15, su: 0.45, giro: 0.07, rx: 0.34, cono: false))
        var F = FasciOlo(6)
        for i in -5...5 { let d = Double(i) * 0.2; F.metti(0, s.P(d, -1, 0), s.P(d, 1, 0)); F.metti(0, s.P(-1, d, 0), s.P(1, d, 0)) }
        for i in 0..<34 {
            let bx = (Double(i) * 0.618).truncatingRemainder(dividingBy: 1) * 2 - 1, by = (Double(i) * 0.381 + 0.13).truncatingRemainder(dividingBy: 1) * 2 - 1
            let h = 0.04 + 0.18 * (Double(i) * 0.739).truncatingRemainder(dividingBy: 1)
            if hypot(bx, by) < 0.14 { continue }
            let w = 0.06, z = h * s.nasce, c: [(Double, Double)] = [(-w, -w), (w, -w), (w, w), (-w, w)]
            for (k, (a, b)) in c.enumerated() { let (a2, b2) = c[(k + 1) % 4]; F.metti(1, s.P(bx + a, by + b, z), s.P(bx + a2, by + b2, z)); F.metti(0, s.P(bx + a, by + b, 0), s.P(bx + a, by + b, z)) }
        }
        let mx = max(500, L.compactMap(\.metri).max() ?? 500)
        let fari: [(l: LuogoOlo, x: Double, y: Double)] = L.map { l in
            let a = Double(Tav.seme(l.nome)) / 100_003 * OP.due, r = 0.2 + 0.75 * ((l.metri ?? mx) / mx).squareRoot()
            return (l, cos(a) * r, sin(a) * r)
        }
        for (i, f) in fari.enumerated() {
            let g = i == scelto ? 4 : 2
            F.metti(g, s.P(f.x, f.y, 0), s.P(f.x, f.y, (i == scelto ? 0.75 : 0.5) * s.nasce))
            Tav.cerchio(&F, s, 0.05, 0.005, g, n: 16, cx: f.x, cy: f.y)
        }
        if scelto < fari.count {
            let f = fari[scelto]
            var pp: P3?
            for k in 0...20 { let u = Double(k) / 20, p = s.P(f.x * u, f.y * u, 0.01); if let pp, k % 2 == 1 { F.metti(3, pp, p) }; pp = p }
        }
        Tav.traccia(&gc, F, piccolo)
        let io = s.P(0, 0, 0.02)
        Tav.alone(&gc, io, 10 + 2 * sin(t * 3), 0.85, Tav.bianco)
        for k in 0..<2 { let v = (t * 0.5 + Double(k) / 2).truncatingRemainder(dividingBy: 1), r = 4 + v * 26; gc.stroke(Olo.ellisse(io.x, io.y, r, r * sin(0.95)), with: .color(OP.b(0.5 * (1 - v))), lineWidth: 1) }
        for (i, f) in fari.enumerated() { Tav.alone(&gc, s.P(f.x, f.y, (i == scelto ? 0.75 : 0.5) * s.nasce), i == scelto ? 12 : 7, 0.8, Tav.bianco) }
        guard !piccolo else { return }
        OP.scritta(&gc, "LEI", io.x, io.y + 14, 6.5, 800, OP.b(0.9))
        for (i, f) in fari.enumerated() {
            let p = s.P(f.x, f.y, (i == scelto ? 0.75 : 0.5) * s.nasce)
            OP.scritta(&gc, OP.taglia(f.l.nome.uppercased(), 16), p.x, p.y - 8, 6.5, 800, i == scelto ? OP.b(0.95) : OP.c(0.85))
            M.zona(p.x, p.y, 14, i)
        }
        let sel = scelto < fari.count ? fari[scelto].l : nil
        Tav.testate(&gc, W, "PLASTICO · MILANO", "\(L.count) POSTI", sel.map { l in OP.taglia(l.nome.uppercased(), 16) + (l.metri.map { " · " + Rotta.distanza($0).uppercased() } ?? "") })
        if let i = M.scelta, i >= 0, i < fari.count {
            let f = fari[i], p = s.P(f.x, f.y, 0.5)
            OP.riquadro(&gc, W, H, p.x, p.y, [OP.taglia(f.l.nome.uppercased(), 24), OP.taglia(f.l.via.uppercased(), 30), f.l.metri.map { Rotta.distanza($0).uppercased() } ?? "DISTANZA: ASPETTO LA POSIZIONE",
                                               "SALVATO \(f.l.quando.uppercased())"], t - M.sceltaT, codice: "POSTO")
        }
    }
}
