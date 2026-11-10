import Foundation
import SwiftUI

// MARK: - MUSICA: TRE OLOGRAMMI (10 nov, il signore: «fai come le altre, 3 diversi ologrammi… cool e funzionali, interattivi»)
// Riportati uguali dal mockup (vinileMusica, ondaMusica, codaMusica). Ognuno comanda davvero il lettore di JARVIS:
// VINILE (tocco sul disco: play/pausa; sull'anello del tempo: salta lì; sul braccio: la scheda del brano),
// ONDA (tocco sull'asta: salta lì; sul paesaggio: play/pausa),
// CODA (tocco su un brano in orbita: la scheda; toccato di nuovo: parte; al centro: play/pausa).
// Questo file è sia dell'iPhone sia dell'orologio (sul polso: in piccolo, senza scritte, senza dita).

/// Un brano come lo vede l'ologramma.
struct BranoMusicaOlo {
    var titolo: String
    var artista: String
    var album: String
    var durata: Double
}

/// I dati di Musica per gli ologrammi (letti a ogni fotogramma: il tempo scorre). Le azioni le dà l'iPhone; sul polso non servono.
struct DatiMusicaOlo {
    var ora: BranoMusicaOlo
    var t: Double
    var suona: Bool
    /// In pausa perché il signore parla a JARVIS (riparte da sola dopo la risposta).
    var jPausa: Bool
    /// I prossimi in coda (al massimo 6).
    var prossimi: [BranoMusicaOlo]
    var playPausa: () -> Void = {}
    var vaiA: (Double) -> Void = { _ in }
    var suonaProssimo: (Int) -> Void = { _ in }

    /// Il seme dello spettro: ogni brano la sua forma (nel mockup l'indice del brano).
    var seme: Double { Double(Tav.seme(ora.titolo + ora.artista) % 9) }
}

final class ProveMusica {
    // VINILE: il giro del disco con l'inerzia e il braccio che si alza
    private var spin = 0.0
    private var vel = 0.0
    private var alza = 1.0
    private var ultimo: Double?

    /// Gli id delle zone (le zone del motore sono numeri): il disco, il braccio, le tacche del tempo, il paesaggio, i brani, il centro.
    private static let disco = 1000, braccio = 1001, tacca = 2000, onda = 3000, brano = 4000, centro = 5000

    func crea(_ k: Int) { spin = 0; vel = 0; alza = 1; ultimo = nil }

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMusicaOlo, piccolo: Bool) {
        switch k {
        case 1: ondaProva(&gc, W, H, t, M, D, piccolo)
        case 2: coda(&gc, W, H, t, M, D, piccolo)
        default: vinile(&gc, W, H, t, M, D, piccolo)
        }
    }

    // MARK: lo spettro, il tempo, lo stato (come il mockup)

    /// spettroMu: lo spettro d'esempio al tempo tt (Apple non dà il segnale dei brani di Apple Music).
    static func spettro(_ tt: Double, _ k: Int, _ n: Int, _ id: Double) -> Double {
        let f = Double(k) / Double(n), cassa = exp(-(tt * 2).truncatingRemainder(dividingBy: 1) * 7)
        let corpo = 0.25 + 0.75 * abs(sin(tt * 2.1 + Double(k) * 0.7 + id) * sin(tt * 0.93 + Double(k) * 1.31 + id * 2))
        return max(0.03, (1 - f * 0.65) * corpo * 0.8 + (f < 0.18 ? cassa * (0.9 - f * 3) : 0))
    }

    static func mmss(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let v = max(0, Int(s))
        return "\(v / 60):" + String(format: "%02d", v % 60)
    }

    private static func stato(_ D: DatiMusicaOlo) -> String { D.jPausa ? "JARVIS ASCOLTA" : D.suona ? "IN RIPRODUZIONE" : "IN PAUSA" }

    private static func lis(_ v: Double) -> Double { min(1, max(0, v)) }

    // MARK: M1 · VINILE

    // il giradischi di Stark: il vinile gira a 33⅓ giri con l'inerzia vera (in pausa rallenta e si ferma), la copertina sull'etichetta,
    // i solchi col riflesso fermo verso chi guarda. Il braccio scende quando suona e avanza verso il centro col brano (è la barra del
    // tempo); in pausa si alza e torna a riposo. Attorno la corona di colonne di luce (lo spettro) e l'anello del tempo con 12 tacche.
    private func vinile(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMusicaOlo, _ piccolo: Bool) {
        if !piccolo, M.suTocco == nil {
            let playPausa = D.playPausa, vaiA = D.vaiA
            M.suTocco = { id in
                if id == ProveMusica.disco { playPausa(); return true }
                if id >= ProveMusica.tacca, id < ProveMusica.tacca + 12 { vaiA(Double(id - ProveMusica.tacca) / 12); return true }
                return false
            }
        }
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.6, sz: 0.8, su: 1.08, oscilla: 0.4, mano: 0.8, conoSu: 0.05, conoW: 0.95, conoA: 0.06))
        let dt = ultimo.map { min(0.05, max(0, t - $0)) } ?? 1.0 / 60
        ultimo = t
        let dur = D.ora.durata > 0 ? D.ora.durata : 1, pr = Self.lis(D.t / dur)
        vel += ((D.suona ? 3.49 : 0) - vel) * (1 - exp(-dt / (D.suona ? 0.35 : 0.9)))
        spin += vel * dt
        alza += ((D.suona ? 0 : 1) - alza) * (1 - exp(-dt / 0.25))
        var F = FasciOlo(6)
        let R = s.nasce
        // il piatto, il bordo, i solchi
        Tav.cerchio(&F, s, 1.0 * R, 0, 4, n: 72)
        Tav.cerchio(&F, s, 1.04 * R, -0.03, 2, n: 72)
        if !piccolo { for r in stride(from: 0.4, to: 0.97, by: 0.05) { Tav.cerchio(&F, s, r * R, 0, 0, n: 48) } }
        // il riflesso dei solchi: fermo rispetto a chi guarda (contro il giro della scena)
        for r in stride(from: 0.42, to: 0.97, by: piccolo ? 0.14 : 0.07) {
            var q: P3?
            for i in 0...8 {
                let a = -s.ang + 2.2 + Double(i) * 0.07, p = s.P(cos(a) * r * R, sin(a) * r * R, 0)
                if let q { F.metti(3, q, p) }
                q = p
            }
        }
        // la tacca che gira col disco
        F.metti(4, s.P(cos(spin) * 0.36 * R, sin(spin) * 0.36 * R, 0), s.P(cos(spin) * 0.52 * R, sin(spin) * 0.52 * R, 0))
        // l'anello del tempo: 60 tacche, la parte suonata accesa
        let rT = 1.2 * R
        Tav.cerchio(&F, s, rT, -0.04, 1, n: 72)
        for k in 0..<60 {
            let a = -Double.pi / 2 + Double(k) / 60 * OP.due, l = k % 5 != 0 ? 0.04 : 0.09, on = Double(k) / 60 <= pr
            F.metti(on ? 4 : 1, s.P(cos(a) * rT, sin(a) * rT, -0.04), s.P(cos(a) * (rT + l), sin(a) * (rT + l), -0.04))
        }
        do {
            var q: P3?
            let n = max(1, Int((72 * pr).rounded()))
            for i in 0...n {
                let a = -Double.pi / 2 + Double(i) / 72 * OP.due, p = s.P(cos(a) * rT, sin(a) * rT, -0.04)
                if let q { F.metti(5, q, p) }
                q = p
            }
        }
        // lo spettro: colonne di luce attorno al piatto (davanti più chiare)
        let N = piccolo ? 32 : 64, id = D.seme
        for k in 0..<N {
            let a = Double(k) / Double(N) * OP.due, v = (D.suona ? 1 : 0.06) * Self.spettro(t, k, N, id) * (k % 8 == 0 ? 1.2 : 1)
            let b = s.P(cos(a) * 1.1 * R, sin(a) * 1.1 * R, 0), c = s.P(cos(a) * 1.1 * R, sin(a) * 1.1 * R, 0.04 + v * 0.55 * R)
            F.metti(b.z < 0 ? 3 : 1, b, c)
        }
        // il braccio: dal perno (dietro a destra) alla puntina; suonando sta sul solco del tempo che passa
        let piv = P3(1.18, 0.62, 0.12), L = 1.36, rS = 0.95 - 0.55 * pr, dP = hypot(piv.x, piv.y), aP = atan2(piv.y, piv.x)
        let cosA = max(-1, min(1, (rS * rS + dP * dP - L * L) / (2 * rS * dP))), gS = aP - acos(cosA)
        let punta = P3(cos(gS) * rS, sin(gS) * rS, 0.015), riposo = P3(1.3, -0.7, 0.12), u = Self.lis(1 - alza)
        let tip = P3(riposo.x + (punta.x - riposo.x) * u, riposo.y + (punta.y - riposo.y) * u, riposo.z + (punta.z - riposo.z) * u + alza * 0.05)
        let ddx = tip.x - piv.x, ddy = tip.y - piv.y, dlr = hypot(ddx, ddy), dl = dlr > 0 ? dlr : 1, nx = ddx / dl, ny = ddy / dl
        let gomito = P3(piv.x + nx * dl * 0.72 - ny * 0.08, piv.y + ny * dl * 0.72 + nx * 0.08, piv.z + 0.02)
        let pv = s.Pv(piv), gm = s.Pv(gomito), tp = s.Pv(tip), peso = s.P(piv.x - nx * 0.22, piv.y - ny * 0.22, piv.z)
        Tav.cerchio(&F, s, 0.1, piv.z - 0.1, 2, n: 24, cx: piv.x, cy: piv.y)
        F.metti(2, peso, pv)
        F.metti(5, pv, gm)
        F.metti(5, gm, tp)
        Tav.traccia(&gc, F, piccolo)
        // l'etichetta: la copertina, girata col disco e schiacciata in prospettiva
        let c0 = s.P(0, 0, 0.005)
        let ax = s.P(cos(spin) * 0.34 * R, sin(spin) * 0.34 * R, 0.005), ay = s.P(cos(spin + 1.5708) * 0.34 * R, sin(spin + 1.5708) * 0.34 * R, 0.005)
        if R > 0.05 {
            var g = gc
            var bordo = Path()
            for i in 0...40 {
                let a = Double(i) / 40 * OP.due, p = s.P(cos(a) * 0.34 * R, sin(a) * 0.34 * R, 0.005)
                if i == 0 { bordo.move(to: CGPoint(x: p.x, y: p.y)) } else { bordo.addLine(to: CGPoint(x: p.x, y: p.y)) }
            }
            bordo.closeSubpath()
            g.clip(to: bordo)
            g.blendMode = .normal
            g.opacity = 0.8
            g.concatenate(CGAffineTransform(a: ax.x - c0.x, b: ax.y - c0.y, c: ay.x - c0.x, d: ay.y - c0.y, tx: c0.x, ty: c0.y))
            g.translateBy(x: -1, y: -1)
            g.scaleBy(x: 2 / CopertinaOlo.lato, y: 2 / CopertinaOlo.lato)
            CopertinaOlo.disegna(&g, D.ora.album, simbolo: CopertinaOlo.simbolo(0))
        }
        Tav.alone(&gc, c0, s.sz * 0.08, 0.7, Tav.bianco)
        Tav.alone(&gc, pv, s.sz * 0.07, 0.6)
        if D.suona && u > 0.9 { Tav.alone(&gc, tp, s.sz * (0.09 + 0.04 * abs(sin(t * 7))), 0.95, Tav.bianco) }
        guard !piccolo else { return }
        M.zona(c0.x, c0.y, s.sz * 0.42, Self.disco)
        M.zona(tp.x, tp.y, 18, Self.braccio)
        for k in 0..<12 {
            let a = -Double.pi / 2 + Double(k) / 12 * OP.due, p = s.P(cos(a) * rT, sin(a) * rT, -0.04)
            if p.z < 0.2 { M.zona(p.x, p.y, 14, Self.tacca + k) }
        }
        Tav.testate(&gc, W, "VINILE · 33⅓ GIRI", Self.stato(D), "\(Self.mmss(D.t)) / \(Self.mmss(D.ora.durata))")
        if M.scelta == Self.braccio {
            OP.riquadro(&gc, W, H, tp.x, tp.y, [D.ora.titolo.uppercased(), D.ora.artista,
                                                "\(Self.mmss(D.t)) DI \(Self.mmss(D.ora.durata)) · \(Int((pr * 100).rounded()))%", "PUNTINA SUL SOLCO"],
                        t - M.sceltaT, codice: "BRACCIO")
        }
    }

    // MARK: M2 · ONDA

    // il suono come un paesaggio olografico: ogni fila un istante (davanti adesso, dietro i secondi appena passati), ogni colonna una
    // banda (bassi a sinistra col colpo di cassa, acuti a destra). Scorre mentre suona, in pausa si ferma. Davanti l'asta del brano col
    // punto di adesso: toccata, salta lì. Tocco sul paesaggio: play/pausa.
    private func ondaProva(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMusicaOlo, _ piccolo: Bool) {
        if !piccolo, M.suTocco == nil {
            let playPausa = D.playPausa, vaiA = D.vaiA
            M.suTocco = { id in
                if id == ProveMusica.onda { playPausa(); return true }
                if id >= ProveMusica.tacca, id <= ProveMusica.tacca + 10 { vaiA(Double(id - ProveMusica.tacca) / 10); return true }
                return false
            }
        }
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.45, sz: 0.88, su: 0.82, oscilla: 0.32, mano: 0.7, conoSu: 0.1, conoW: 1.0, conoA: 0.05))
        var F = FasciOlo(6)
        let N = piccolo ? 20 : 36, RIGHE = piccolo ? 10 : 22, dur = D.ora.durata > 0 ? D.ora.durata : 1, pr = Self.lis(D.t / dur), id = D.seme
        let yR = { (r: Int) -> Double in -0.75 + Double(r) * (1.6 / Double(RIGHE - 1)) }
        let xK = { (k: Int) -> Double in -1.05 + 2.1 * Double(k) / Double(N - 1) }
        var fronte: [P3]?
        for r in stride(from: RIGHE - 1, through: 0, by: -1) {
            let tt = D.t - Double(r) * 0.25
            guard tt >= 0 else { continue }
            let vis = Self.lis(s.nasce * 1.8 - Double(r) / Double(RIGHE))
            guard vis > 0 else { continue }
            let fila: [P3] = (0..<N).map { k in s.P(xK(k), yR(r), Self.spettro(tt, k, N, id) * 0.7 * vis) }
            let g = r == 0 ? 5 : r < 4 ? 3 : r < 10 ? 2 : r < 16 ? 1 : 0
            for k in 1..<N { F.metti(g, fila[k - 1], fila[k]) }
            if r == 0 { fronte = fila }
            if r % 3 == 0 && !piccolo { for k in stride(from: 0, to: N, by: 5) { F.metti(0, fila[k], s.P(xK(k), yR(r), 0)) } }
        }
        // il pavimento: la griglia e l'asta del brano davanti
        for k in 0...6 { F.metti(0, s.P(xK(0) + 2.1 * Double(k) / 6, yR(0), 0), s.P(xK(0) + 2.1 * Double(k) / 6, yR(RIGHE - 1), 0)) }
        let yA = yR(0) - 0.22
        F.metti(1, s.P(-1.2, yA, 0), s.P(1.2, yA, 0))
        F.metti(5, s.P(-1.2, yA, 0), s.P(-1.2 + 2.4 * pr, yA, 0))
        for k in 0...10 { F.metti(Double(k) / 10 <= pr ? 4 : 1, s.P(-1.2 + 2.4 * Double(k) / 10, yA, 0), s.P(-1.2 + 2.4 * Double(k) / 10, yA - 0.05, 0)) }
        Tav.traccia(&gc, F, piccolo)
        let pn = s.P(-1.2 + 2.4 * pr, yA, 0)
        Tav.alone(&gc, pn, s.sz * 0.08, 0.95, Tav.bianco)
        if let fronte, D.suona { for (k, q) in fronte.enumerated() where k % 6 == 0 { Tav.alone(&gc, q, s.sz * 0.04, 0.5, Tav.bianco) } }
        guard !piccolo else { return }
        let c = s.P(0, yR(4), 0.3)
        M.zona(c.x, c.y, s.sz * 0.6, Self.onda)
        for k in 0...10 { let p = s.P(-1.2 + 2.4 * Double(k) / 10, yA, 0); M.zona(p.x, p.y, 13, Self.tacca + k) }
        let b = s.P(-1.05, yA - 0.12, 0), a = s.P(1.05, yA - 0.12, 0)
        OP.scritta(&gc, "BASSI", b.x, b.y + 9, 6.5, 700, OP.c(0.55))
        OP.scritta(&gc, "ACUTI", a.x, a.y + 9, 6.5, 700, OP.c(0.55))
        Tav.testate(&gc, W, "ONDA · SPETTRO", Self.stato(D), "\(Self.mmss(D.t)) / \(Self.mmss(D.ora.durata))")
    }

    // MARK: M3 · CODA

    // al centro il brano di adesso (la copertina in piedi sul disco di luce, l'anello del tempo intorno), i prossimi in orbita su tre
    // anelli, più piccoli quanto più lontani in coda. Toccato un brano: la scheda; toccato di nuovo: parte. Al centro: play/pausa.
    private func coda(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiMusicaOlo, _ piccolo: Bool) {
        if !piccolo, M.suTocco == nil {
            let playPausa = D.playPausa, suonaProssimo = D.suonaProssimo
            M.suTocco = { [weak M] id in
                if id == ProveMusica.centro { playPausa(); return true }
                guard let M, id >= ProveMusica.brano, id < ProveMusica.brano + 6, M.scelta == id else { return false }
                suonaProssimo(id - ProveMusica.brano)
                M.scelta = nil
                return true
            }
        }
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.4, sz: 0.88, su: 0.95, oscilla: 0.5, mano: 0.9, conoSu: 0.4, conoW: 0.45, conoA: 0.08))
        var F = FasciOlo(6)
        let nasce = s.nasce, dur = D.ora.durata > 0 ? D.ora.durata : 1, pr = Self.lis(D.t / dur)
        let prossimi = Array(D.prossimi.prefix(piccolo ? 3 : 6)), ORB = [0.62, 0.92, 1.18]
        for (j, r) in ORB.enumerated() { Tav.cerchio(&F, s, r * nasce, 0, j == 0 ? 1 : 0, n: 72) }
        Tav.cerchio(&F, s, 0.38, 0, 1, n: 48)
        do {
            var q: P3?
            let m = max(1, Int((60 * pr).rounded()))
            for i in 0...m {
                let a = -Double.pi / 2 + Double(i) / 60 * OP.due, p = s.P(cos(a) * 0.38, sin(a) * 0.38, 0)
                if let q { F.metti(5, q, p) }
                q = p
            }
        }
        // il cavalletto di luce della copertina di adesso
        let lato = 0.5 * nasce, zc = 0.12
        F.metti(2, s.P(-lato / 2, 0, 0), s.P(-lato / 2, 0, zc))
        F.metti(2, s.P(lato / 2, 0, 0), s.P(lato / 2, 0, zc))
        Tav.traccia(&gc, F, piccolo)
        // i pianeti: posizioni in orbita, poi disegnati da dietro a davanti; la copertina di adesso al suo posto nella fila
        let pianeti: [(k: Int, p: P3)] = prossimi.indices.map { k in
            let r = ORB[min(2, k / 2)] * nasce, g = t * (0.16 - Double(k) * 0.012) * (k % 2 != 0 ? -1 : 1) + Double(k) * 2.1
            return (k: k, p: s.P(cos(g) * r, sin(g) * r, 0.05))
        }
        let c0 = s.P(0, 0, zc + lato / 2), cA = s.P(-lato / 2, 0, zc + lato), cB = s.P(lato / 2, 0, zc + lato), cC = s.P(-lato / 2, 0, zc)
        // -1 è la copertina di adesso
        var fila: [(k: Int, z: Double)] = pianeti.map { (k: $0.k, z: $0.p.z) }
        fila.append((k: -1, z: c0.z))
        fila.sort { $0.z > $1.z }
        for q in fila {
            if q.k < 0 {
                guard lato > 0.02 else { continue }
                var g = gc
                g.blendMode = .normal
                g.opacity = 0.92
                g.concatenate(CGAffineTransform(a: cB.x - cA.x, b: cB.y - cA.y, c: cC.x - cA.x, d: cC.y - cA.y, tx: cA.x, ty: cA.y))
                g.scaleBy(x: 1 / CopertinaOlo.lato, y: 1 / CopertinaOlo.lato)
                CopertinaOlo.disegna(&g, D.ora.album, simbolo: CopertinaOlo.simbolo(0))
                let cD = s.P(lato / 2, 0, zc)
                var n = gc
                n.blendMode = .normal
                n.stroke(Tav.spezzata([cA, cB, cD, cC], chiusa: true), with: .color(OP.b(0.85)), lineWidth: 1.3)
                Tav.alone(&gc, c0, s.sz * lato * 0.9, D.suona ? 0.16 + 0.08 * abs(sin(t * 4)) : 0.08)
                continue
            }
            let p = pianeti[q.k].p, b = prossimi[q.k]
            let lt = (piccolo ? 10 : 22 - Double(q.k) * 2) * (3.6 / (3.6 + p.z)), scelto = M.scelta == Self.brano + q.k
            var g = gc
            g.blendMode = .normal
            g.opacity = 0.45 + 0.55 * Self.lis(0.6 - p.z * 0.5)
            g.translateBy(x: p.x - lt / 2, y: p.y - lt - 4)
            g.scaleBy(x: lt / CopertinaOlo.lato, y: lt / CopertinaOlo.lato)
            CopertinaOlo.disegna(&g, b.album, simbolo: CopertinaOlo.simbolo(q.k + 1))
            var n = gc
            n.blendMode = .normal
            n.stroke(Path(CGRect(x: p.x - lt / 2 + 0.5, y: p.y - lt - 3.5, width: lt - 1, height: lt - 1)),
                     with: .color(scelto ? OP.b(0.95) : OP.c(0.7)), lineWidth: scelto ? 1.5 : 1)
            Tav.segmento(&gc, P3(p.x, p.y - 4, 0), p, OP.c(0.35), 0.8)
            Tav.alone(&gc, p.x, p.y, 3, 0.7)
            if !piccolo && q.k < 3 { OP.scritta(&gc, String(b.titolo.uppercased().prefix(14)), p.x, p.y + 9, 6, 700, OP.c(0.75)) }
            if !piccolo { M.zona(p.x, p.y - lt / 2 - 4, max(16, lt * 0.7), Self.brano + q.k) }
        }
        guard !piccolo else { return }
        M.zona(c0.x, c0.y, s.sz * 0.3, Self.centro)
        OP.scritta(&gc, String(D.ora.titolo.uppercased().prefix(24)), c0.x, cC.y + 14, 7, 700, OP.b(0.9))
        Tav.testate(&gc, W, "CODA · PROSSIMI", Self.stato(D), "\(prossimi.count) IN ORBITA")
        if let k = Tav.scelta(M, Self.brano), k < pianeti.count {
            let p = pianeti[k].p, b = prossimi[k]
            OP.riquadro(&gc, W, H, p.x, p.y - 14, [b.titolo.uppercased(), b.artista, "\(b.album) · \(Self.mmss(b.durata))", "TOCCHI ANCORA: SUONA"],
                        t - M.sceltaT, codice: "CODA " + String(format: "%02d", k + 1))
        }
    }
}

/// La copertina nell'ologramma, in un quadrato di `lato` punti (chi la chiama la porta al suo posto con la trasformazione).
/// Sull'iPhone la copertina vera di Apple Music (un simbolo della tela); dove non c'è (sul polso, o finché non arriva) quella disegnata
/// dal nome dell'album, come la `copertina()` del mockup.
enum CopertinaOlo {
    static let lato = 100.0

    static func simbolo(_ i: Int) -> String { "copertina\(i)" }

    static func disegna(_ g: inout GraphicsContext, _ nome: String, simbolo: String) {
        disegnata(&g, nome)
        if let s = g.resolveSymbol(id: simbolo) {
            let k = lato / 240
            var q = g
            q.scaleBy(x: k, y: k)
            q.draw(s, in: CGRect(x: 0, y: 0, width: 240, height: 240))
        }
    }

    /// copertina(): il fondo sfumato e uno dei tre disegni (cerchi, linee, raggi) scelti dal nome, con le iniziali.
    private static func disegnata(_ g: inout GraphicsContext, _ nome: String) {
        let L = lato
        var h: UInt32 = 0
        for c in nome.utf16 { h = h &* 31 &+ UInt32(c) }
        func r(_ n: Double) -> Double {
            h = h &* 1_103_515_245 &+ 12_345
            return Double(h % 1000) / 1000 * n
        }
        let tinta = rgbDaHsl((185 + r(20)) / 360, 0.7, (8 + r(10)) / 100)
        g.fill(Path(CGRect(x: 0, y: 0, width: L, height: L)),
               with: .linearGradient(Gradient(colors: [Color(red: 3 / 255, green: 22 / 255, blue: 27 / 255), tinta]),
                                     startPoint: .zero, endPoint: CGPoint(x: L, y: L)))
        let lw = L / 90, tipo = h % 3
        func traccia(_ p: Path, _ a: Double) { g.stroke(p, with: .color(OP.s(0.75 * a)), lineWidth: lw) }
        if tipo == 0 {
            for k in 1..<7 {
                let a = 1 - Double(k) / 8, cx = L * (0.3 + r(0.4)), cy = L * (0.3 + r(0.4)), rr = Double(k) * L / 12
                traccia(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)), a)
            }
        } else if tipo == 1 {
            for k in 0..<14 {
                let a = 0.25 + r(0.6), y = L * Double(k) / 14 + r(L / 20), y1 = y + r(L / 3) - L / 6
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: L, y: y1))
                traccia(p, a)
            }
        } else {
            for k in 0..<24 {
                let a = 0.3 + r(0.6), ang = Double(k + 1) * Double.pi / 12, l = L * (0.2 + r(0.25))
                var p = Path()
                p.move(to: CGPoint(x: L / 2 + cos(ang) * L * 0.08, y: L / 2 + sin(ang) * L * 0.08))
                p.addLine(to: CGPoint(x: L / 2 + cos(ang) * l, y: L / 2 + sin(ang) * l))
                traccia(p, a)
            }
        }
        let sigla = String(nome.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased()
        g.draw(Text(sigla).font(.system(size: L / 7, weight: .bold, design: .monospaced)).foregroundStyle(Color.white),
               at: CGPoint(x: L * 0.08, y: L * 0.94), anchor: .bottomLeading)
    }

    /// hsl() del mockup.
    private static func rgbDaHsl(_ hh: Double, _ s: Double, _ l: Double) -> Color {
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func canale(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return Color(red: canale(hh + 1.0 / 3), green: canale(hh), blue: canale(hh - 1.0 / 3))
    }
}
