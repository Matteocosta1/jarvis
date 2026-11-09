import Foundation
import SwiftUI

// MARK: - CUORE e TELEFONO (build 11.0 (19), 9 nov, come il mockup)
// CUORE (il signore: «un cuore vero alla Tony Stark… si vede il petto con un cuore che batte»): BATTITO (il cuore di sempre),
// PETTO (il torace in scansione con il cuore anatomico che batte e il reattore sullo sterno), ECG (il nastro dei battiti di oggi
// con il tracciato vivo); ANELLI tolto il 9 nov (il signore: «togliamolo così almeno sono 3»). TELEFONO: ANTENNA (il traliccio con le cifre
// in orbita), STARKPHONE (il telefono di vetro di Iron Man 2: i tasti sul vetro scrivono), SATELLITI (la Terra coi satelliti Stark
// e il fascio verso il contatto). Il cuore anche sul polso (la prova scelta sull'iPhone); il telefono solo sull'iPhone.

// MARK: il cuore anatomico (CUORE_ANAT del mockup)

/// I dati del cuore per le prove: adesso, a riposo, minimo e massimo di oggi, HRV; i battiti di oggi (minuti dalla mezzanotte) e
/// i 30 giorni di riposo e HRV.
struct DatiCuoreOlo {
    var adesso = 0.0
    var riposo = 0
    var minimo = 0
    var massimo = 0
    var hrv = 0
    var oggi: [(m: Double, v: Double)] = []
    var riposo30: [Double] = []
    var hrv30: [Double] = []
    var base: DatiCuore { DatiCuore(adesso: adesso, riposo: Double(riposo), minimo: Double(minimo), massimo: Double(massimo)) }
}

/// colpoCuore: lub forte, dub più debole dopo un terzo del battito.
nonisolated func colpoCuore(_ t: Double, _ bpm: Double) -> (lub: Double, dub: Double, batte: Double, fase: Double) {
    let periodo = 60 / max(30, min(220, bpm > 0 ? bpm : 60)), n = floor(t / periodo), d = t - n * periodo, d2 = d - min(0.3, periodo / 3)
    let lub = d < 0.16 ? sin(d / 0.16 * .pi) : 0, dub = d2 > 0 && d2 < 0.13 ? sin(d2 / 0.13 * .pi) * 0.55 : 0
    return (lub, dub, max(lub, dub), d / periodo)
}

/// Il cuore come una scansione: un campo di volumi che si fondono (ventricoli, atri, orecchiette) tagliato a fette (marching
/// squares), i vasi veri (aorta con l'arco e i rami, polmonare, cave) e le coronarie posate sulla superficie. Calcolato una volta.
enum CuoreAnat {
    typealias Seg = (P3, P3)
    private static let B: [(c: P3, r: P3, w: Double)] = [
        (P3(0.14, 0.06, -0.18), P3(0.52, 0.47, 0.78), 1), (P3(0.22, 0.02, -0.78), P3(0.24, 0.24, 0.28), 0.8),
        (P3(-0.2, -0.17, -0.06), P3(0.5, 0.36, 0.6), 1),
        (P3(-0.56, 0.06, 0.42), P3(0.31, 0.32, 0.36), 1), (P3(0.3, 0.36, 0.44), P3(0.33, 0.27, 0.24), 1),
        (P3(0.5, -0.1, 0.4), P3(0.17, 0.11, 0.12), 0.9), (P3(-0.42, -0.18, 0.5), P3(0.16, 0.12, 0.12), 0.8),
    ]
    private static func campo(_ p: P3) -> Double {
        var f = 0.0
        for b in B { let d = (p - b.c) / b.r; f += b.w * exp(-0.693 * (d * d).sum()) }
        return f
    }
    private static let soglia = 0.5

    private static func fetta(_ mappa: (Double, Double) -> P3) -> [Seg] {
        let N = 44, L = 1.25, h = 2 * L / Double(N)
        var val = [[Double]](repeating: [Double](repeating: 0, count: N + 1), count: N + 1)
        for i in 0...N { for j in 0...N { val[i][j] = campo(mappa(-L + Double(i) * h, -L + Double(j) * h)) - soglia } }
        func bordo(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) -> P3 {
            let a = val[i0][j0], b = val[i1][j1], f = a / (a - b)
            return mappa(-L + (Double(i0) + Double(i1 - i0) * f) * h, -L + (Double(j0) + Double(j1 - j0) * f) * h)
        }
        let coppie: [Int: [Character]] = [1: ["l", "b"], 2: ["b", "r"], 3: ["l", "r"], 4: ["r", "t"], 5: ["l", "t", "b", "r"], 6: ["b", "t"], 7: ["l", "t"],
                                          8: ["t", "l"], 9: ["t", "b"], 10: ["b", "l", "t", "r"], 11: ["t", "r"], 12: ["r", "l"], 13: ["r", "b"], 14: ["b", "l"]]
        var seg: [Seg] = []
        for i in 0..<N {
            for j in 0..<N {
                let c = (val[i][j] > 0 ? 1 : 0) | (val[i + 1][j] > 0 ? 2 : 0) | (val[i + 1][j + 1] > 0 ? 4 : 0) | (val[i][j + 1] > 0 ? 8 : 0)
                guard c != 0, c != 15, let cc = coppie[c] else { continue }
                func e(_ k: Character) -> P3 {
                    switch k {
                    case "b": return bordo(i, j, i + 1, j)
                    case "r": return bordo(i + 1, j, i + 1, j + 1)
                    case "t": return bordo(i, j + 1, i + 1, j + 1)
                    default: return bordo(i, j, i, j + 1)
                    }
                }
                var k = 0
                while k + 1 < cc.count { seg.append((e(cc[k]), e(cc[k + 1]))); k += 2 }
            }
        }
        return seg
    }

    static let orizzontali: [(z: Double, seg: [Seg])] = (0..<24).map { k in
        let z = -1.08 + Double(k) * 0.073
        return (z, fetta { u, v in P3(u, v, z) })
    }
    static let verticali: [[Seg]] = (0..<9).map { k in
        let x = -0.8 + Double(k) * 0.17
        return fetta { u, v in P3(x, u * 0.9, v * 1.05) }
    }
    private static func sulla(_ p: P3, _ d: P3) -> P3 {
        var t = 0.0
        while t < 1.6 && campo(p + d * t) > soglia { t += 0.01 }
        return p + d * (t + 0.015)
    }
    private static func lungo(_ a: P3, _ b: P3, _ n: Int) -> [P3] { (0...n).map { a + (b - a) * (Double($0) / Double(n)) } }
    static let coronarie: [[P3]] = [
        lungo(P3(-0.02, -0.1, 0.25), P3(0.24, -0.02, -0.92), 18).map { sulla($0, P3(0, -1, 0)) },
        lungo(P3(0.08, -0.08, 0.02), P3(0.42, -0.1, -0.35), 8).map { sulla($0, P3(0, -1, 0)) },
        lungo(P3(0.0, -0.08, -0.28), P3(0.36, -0.08, -0.6), 7).map { sulla($0, P3(0, -1, 0)) },
        (0..<16).map { k in let a = -1.9 - Double(k) * 0.11; return sulla(P3(cos(a) * 0.1 - 0.25, sin(a) * 0.1, 0.14 - Double(k) * 0.03), P3(-0.8, -0.6, 0)) },
        (0..<14).map { k in let a = 0.3 + Double(k) * 0.13; return sulla(P3(0.1 + cos(a) * 0.1, sin(a) * 0.1, 0.12 - Double(k) * 0.012), P3(0.85, 0.5, 0)) },
    ]
    static let vasi: [(v: (P3, P3, P3), r: Double)] = [
        ((P3(0.02, 0.0, 0.45), P3(-0.32, -0.08, 1.55), P3(0.3, 0.42, 1.12)), 0.15),
        ((P3(0.3, 0.42, 1.12), P3(0.42, 0.55, 0.85), P3(0.36, 0.55, 0.1)), 0.13),
        ((P3(-0.16, -0.36, 0.35), P3(0.05, -0.42, 0.95), P3(0.3, -0.2, 0.98)), 0.14),
        ((P3(0.3, -0.2, 0.98), P3(0.5, -0.12, 0.96), P3(0.75, 0.0, 0.88)), 0.09),
        ((P3(0.3, -0.2, 0.98), P3(0.0, 0.1, 0.98), P3(-0.62, 0.15, 0.88)), 0.09),
        ((P3(-0.62, 0.05, 0.66), P3(-0.64, 0.05, 1.05), P3(-0.62, 0.06, 1.48)), 0.11),
        ((P3(-0.55, 0.12, 0.12), P3(-0.56, 0.14, -0.15), P3(-0.55, 0.16, -0.42)), 0.11),
    ]
    static let rami: [(P3, P3)] = [(P3(-0.12, 0.08, 1.33), P3(-0.2, 0.06, 1.75)), (P3(0.04, 0.18, 1.32), P3(0.06, 0.18, 1.72)), (P3(0.18, 0.3, 1.25), P3(0.28, 0.32, 1.66))]

    struct Esito { var punti: [P3]; var flusso: [(Double) -> P3] }

    /// cuoreAnatomico: il cuore nel disegno, centro c (coordinate della scena), misura s; batte al ritmo bpm.
    /// I punti da toccare: ventricolo sinistro, destro, atrio destro, sinistro, aorta.
    static func disegna(_ F: inout FasciOlo, _ P: @escaping (P3) -> P3, _ c: P3, _ s: Double, _ t: Double, _ bpm: Double, _ piccolo: Bool, scan: Bool = true) -> Esito {
        let colpo = colpoCuore(t, bpm), V = 1 - 0.075 * colpo.lub, A = 1 - 0.11 * colpo.dub, g = 0.62, ca = cos(g), sa = sin(g), av = 0.25, cv = cos(av), sv = sin(av)
        let pt: (P3) -> P3 = { q in
            let k = q.z < 0.25 ? V : A, x = q.x * k, y = q.y * k, z = q.z
            let x1 = x * ca - z * sa, z1 = x * sa + z * ca, y1 = y * cv - z1 * sv, z2 = y * sv + z1 * cv
            return P(c + P3(x1, y1, z2) * s)
        }
        let zs = scan ? -1.1 + 2.6 * (t * 0.32).truncatingRemainder(dividingBy: 1) : 99
        for (k, o) in orizzontali.enumerated() {
            if piccolo && k % 2 == 1 { continue }
            let vicino = abs(o.z - zs) < 0.05
            for q in o.seg { let a = pt(q.0), b = pt(q.1); F.metti(vicino ? 5 : a.z < 0 ? 2 : 1, a, b) }
        }
        if !piccolo { for v in verticali { for q in v { let a = pt(q.0), b = pt(q.1); F.metti(a.z < 0 ? 1 : 0, a, b) } } }
        for l in coronarie { for k in 1..<l.count { F.metti(3, pt(l[k - 1]), pt(l[k])) } }
        func tubo(_ v: (P3, P3, P3), _ r: Double, _ gr: Int, anelli: Bool) {
            var linee: [[P3]] = [[], [], [], []]
            for k in 0...16 {
                let p = Tav.bez(v.0, v.1, v.2, Double(k) / 16)
                for (j, d) in [P3(r, 0, 0), P3(-r, 0, 0), P3(0, r, 0), P3(0, -r, 0)].enumerated() { linee[j].append(pt(p + d)) }
                if anelli && !piccolo && k % 3 == 0 {
                    var q: P3?
                    for i in 0...12 { let an = Double(i) / 12 * OP.due, w = pt(p + P3(cos(an) * r, sin(an) * r, 0)); if let q { F.metti(gr - 1, q, w) }; q = w }
                }
            }
            for l in linee { for k in 1..<l.count { F.metti(gr, l[k - 1], l[k]) } }
        }
        for v in vasi { tubo(v.v, v.r, 3, anelli: true) }
        for (a, b) in rami { tubo((a, (a + b) / 2, b), 0.05, 2, anelli: false) }
        let punti = [pt(P3(0.32, -0.12, -0.35)), pt(P3(-0.32, -0.38, -0.1)), pt(P3(-0.62, -0.1, 0.42)), pt(P3(0.38, 0.12, 0.6)), pt(P3(-0.15, -0.05, 1.3))]
        let v0 = vasi[0].v, v2 = vasi[2].v
        let flusso: [(Double) -> P3] = [{ u in pt(Tav.bez(v0.0, v0.1, v0.2, u)) }, { u in pt(Tav.bez(v2.0, v2.1, v2.2, u)) }]
        return Esito(punti: punti, flusso: flusso)
    }
}

// MARK: le prove del CUORE

final class ProveCuore {
    private static let parti: [[String]] = [["VENTRICOLO SINISTRO", "SPINGE IL SANGUE IN TUTTO IL CORPO"], ["VENTRICOLO DESTRO", "MANDA IL SANGUE AI POLMONI"],
                                            ["ATRIO DESTRO", "RICEVE IL SANGUE DAL CORPO"], ["ATRIO SINISTRO", "RICEVE IL SANGUE DAI POLMONI"],
                                            ["AORTA", "LA STRADA PRINCIPALE DEL SANGUE"]]

    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCuoreOlo, piccolo: Bool) {
        switch k {
        case 1: petto(&gc, W, H, t, M, D, piccolo)
        case 2: ecg(&gc, W, H, t, M, D, piccolo)
        default: DisegnoCuore.disegna(&gc, CGSize(width: W, height: H), t: t, d: D.base, piccolo: piccolo)
        }
    }

    // PETTO: il torace di Iron Man 2 in scansione, il cuore vero a sinistra del petto, il reattore sullo sterno
    private func petto(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCuoreOlo, _ piccolo: Bool) {
        let colpo = colpoCuore(t, D.adesso), batte = colpo.batte, cx = W / 2, base = piccolo ? H - 3 : H - 12, rx = piccolo ? W * 0.3 : min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        let al = 0.16, sz = piccolo ? H * 0.55 : min((H - 36) / 1.5, W * 0.33), cy = base - (piccolo ? 4 : 10) - sz * 0.62
        let ang = 0.55 * sin(t * 0.3) + M.giro, nasce = OP.lis(t / 0.9)
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        Olo.cono(&gc, cx, base, rx, cy - sz * 0.2, sz * 0.95, a: 0.08)
        var F = FasciOlo(6)
        let sez: [(Double, Double, Double)] = [(-0.62, 0.62, 0.34), (-0.3, 0.66, 0.36), (0, 0.72, 0.38), (0.28, 0.79, 0.38), (0.5, 0.9, 0.33), (0.66, 0.78, 0.26), (0.74, 0.4, 0.2)]
        let cresci = { (z: Double) -> Bool in z <= -0.62 + 1.4 * nasce }
        for (k, (z, w, d)) in sez.enumerated() where cresci(z) && !(k % 2 == 1 && k != 5) {
            var q: P3?
            for s in 0...48 { let a = Double(s) / 48 * OP.due, p = P(cos(a) * w, sin(a) * d, z); if let q { F.metti(0, q, p) }; q = p }
        }
        for m in 0..<12 {
            let a = Double(m) / 12 * OP.due, bordo = m == 0 || m == 6
            var q: P3?
            for (z, w, d) in sez where cresci(z) { let p = P(cos(a) * w, sin(a) * d, z); if let q { F.metti(bordo ? 2 : 0, q, p) }; q = p }
        }
        if nasce > 0.8 {
            let spalle: [(Double, Double)] = [(0.0, -0.13), (0.0, 0.13), (0.13, 0.0), (-0.13, 0.0)]
            for lato in [-1.0, 1.0] { for (dx, dy) in spalle { F.metti(1, P(lato * (0.88 + dx), dy, 0.5), P(lato * (1.0 + dx), dy * 0.8, -0.3)) } }
        }
        if nasce > 0.7 {
            for lato in [-1.0, 1.0] {
                var q: P3?
                for s in 0...12 { let u = Double(s) / 12, p = P(lato * (0.06 + 0.6 * u), -0.38 + 0.12 * u * u, 0.12 + 0.18 * sin(u * .pi) - 0.05 * u); if let q { F.metti(1, q, p) }; q = p }
            }
        }
        if nasce > 0.95 {
            for z in [0.72, 0.95] { var q: P3?; for s in 0...24 { let a = Double(s) / 24 * OP.due, p = P(cos(a) * 0.17, sin(a) * 0.15, z); if let q { F.metti(1, q, p) }; q = p } }
        }
        let largo = { (z: Double) -> (Double, Double) in
            for k in 1..<sez.count where z <= sez[k].0 {
                let (z0, w0, d0) = sez[k - 1], (z1, w1, d1) = sez[k], u = (z - z0) / (z1 - z0)
                return (w0 + (w1 - w0) * u, d0 + (d1 - d0) * u)
            }
            return (sez[6].1, sez[6].2)
        }
        for k in 0..<7 {
            let z = 0.48 - Double(k) * 0.15
            guard cresci(z), z >= -0.58 else { continue }
            let (w, d) = largo(z)
            for lato in [-1.0, 1.0] {
                var q: P3?
                for s in 0...14 { let f = 0.22 + Double(s) / 14 * 1.45, p = P(lato * sin(f) * w * 0.95, -cos(f) * d * 0.95, z - 0.16 * cos(f)); if let q { F.metti(2, q, p) }; q = p }
            }
        }
        if nasce > 0.6 {
            F.metti(3, P(0, -0.4, 0.55), P(0, -0.39, -0.12))
            for lato in [-1.0, 1.0] {
                var q: P3?
                for s in 0...10 { let u = Double(s) / 10, p = P(lato * (0.04 + 0.74 * u), -0.36 + 0.3 * u, 0.6 + 0.08 * sin(u * .pi)); if let q { F.metti(2, q, p) }; q = p }
            }
            var z = -0.6
            while z < 0.7 { F.metti(0, P(0, 0.31, z), P(0, 0.31, z + 0.06)); z += 0.1 }
        }
        let hc = P3(0.12, -0.1, 0.0)
        let cuore = CuoreAnat.disegna(&F, { P($0.x, $0.y, $0.z) }, hc, 0.3 * nasce, t, D.adesso, piccolo)
        F.linee(&gc, colore: { $0 >= 4 ? OP.b(0.6 + 0.35 * batte) : OP.c(0.07 + 0.15 * Double($0)) },
                spessore: { piccolo ? 0.4 + Double($0) * 0.08 : 0.6 + Double($0) * 0.15 }, alone: { $0 >= 3 && !piccolo ? OP.s(0.07 + 0.08 * batte) : nil })
        let pc = P(hc.x, hc.y, hc.z)
        Tav.alone(&gc, pc, sz * (0.42 + 0.18 * batte), 0.12 + 0.3 * batte, Tav.rosa)
        for v in cuore.flusso {
            for k in 0..<5 {
                let u = min(1, colpo.fase * 1.6 - Double(k) * 0.05)
                guard u > 0 else { continue }
                let g = v(u)
                Tav.alone(&gc, g, piccolo ? 2 : 5 - Double(k) * 0.6, 0.8 * (1 - u) * (1 - Double(k) / 5), Tav.bianco)
            }
        }
        let re = P(0, -0.4, 0.36)
        Tav.alone(&gc, re, sz * (0.16 + 0.06 * colpo.lub), 0.55 + 0.35 * colpo.lub, Tav.reattore)
        gc.stroke(Path(ellipseIn: CGRect(x: re.x - sz * 0.065, y: re.y - sz * 0.065, width: sz * 0.13, height: sz * 0.13)), with: .color(OP.b(0.75)), lineWidth: 1.2)
        var tri = Path()
        for k in 0..<3 { let a = -1.5708 + Double(k) * 2.0944, r = sz * 0.045, q = CGPoint(x: re.x + cos(a) * r, y: re.y + sin(a) * r); if k == 0 { tri.move(to: q) } else { tri.addLine(to: q) } }
        tri.closeSubpath()
        gc.stroke(tri, with: .color(OP.c(0.6)), lineWidth: 1)
        if !piccolo {
            let zs = -0.55 + 1.2 * (0.5 + 0.5 * sin(t * 0.9)), (w, d) = largo(max(-0.62, min(0.72, zs)))
            let anello = (0...40).map { s -> P3 in let a = Double(s) / 40 * OP.due; return P(cos(a) * (w + 0.06), sin(a) * (d + 0.06), zs) }
            gc.stroke(Tav.spezzata(anello), with: .color(OP.c(0.28)), lineWidth: 1)
        }
        guard !piccolo else { return }
        for (i, p) in cuore.punti.enumerated() { M.zona(p.x, p.y, 16, i) }
        Tav.testate(&gc, W, "CUORE", "\(Int(D.adesso)) BPM", "A RIPOSO \(D.riposo)")
        if let s = M.scelta, s >= 0, s < ProveCuore.parti.count {
            let p = cuore.punti[s]
            OP.riquadro(&gc, W, H, p.x, p.y, ProveCuore.parti[s] + ["\(Int(D.adesso)) BPM · RIPOSO \(D.riposo) · HRV \(D.hrv) ms"], t - M.sceltaT, codice: "CUORE")
        }
    }

    // ECG: il nastro di luce davanti con i battiti di oggi, e in testa il tracciato vivo (P, QRS, T)
    private static func forma(_ u: Double) -> Double {
        0.12 * exp(-pow((u - 0.18) / 0.035, 2)) - 0.12 * exp(-pow((u - 0.3) / 0.012, 2)) + exp(-pow((u - 0.33) / 0.012, 2))
            - 0.28 * exp(-pow((u - 0.36) / 0.014, 2)) + 0.22 * exp(-pow((u - 0.58) / 0.05, 2))
    }

    private func ecg(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiCuoreOlo, _ piccolo: Bool) {
        let O = D.oggi, cx = W / 2, base = piccolo ? H - 3 : H - 12, rx = piccolo ? W * 0.3 : min(W * 0.26, 100)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        let al = 0.3, sz = piccolo ? W * 0.42 : min(W * 0.42, H * 0.7), cy = base - (piccolo ? 4 : 30)
        let ang = 0.2 * sin(t * 0.25) + M.giro * 0.6, nasce = OP.lis(t / 0.9), periodo = 60 / max(30, D.adesso > 0 ? D.adesso : 60)
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let A0 = -2.75, A1 = -0.39, R = 1.0, alto = 0.62
        let nastro = { (u: Double, z: Double) -> P3 in let a = A0 + (A1 - A0) * u; return P(cos(a) * R, sin(a) * R, z) }
        var q0: P3?, q1: P3?
        for s in 0...60 {
            let u = Double(s) / 60
            if u > nasce { break }
            let a = nastro(u, 0.05), b = nastro(u, 0.05 + alto)
            if let q0, let q1 { F.metti(1, q0, a); F.metti(1, q1, b) }
            q0 = a; q1 = b
        }
        let ok = O.count >= 2
        let m0 = O.first?.m ?? 0, m1 = max(m0 + 1, O.last?.m ?? 1), lo = Double(D.minimo) - 6, hi = max(lo + 1, Double(D.massimo) + 6)
        let posto = { (m: Double, v: Double) -> P3 in nastro((m - m0) / (m1 - m0) * 0.7, 0.08 + (v - lo) / (hi - lo) * (alto - 0.06)) }
        if ok {
            var h = ceil(m0 / 180) * 180
            while h <= m1 { let u = (h - m0) / (m1 - m0) * 0.7; if u <= nasce { F.metti(0, nastro(u, 0.05), nastro(u, 0.05 + alto)) }; h += 180 }
            var q: P3?
            for c in O where (c.m - m0) / (m1 - m0) <= nasce { let p = posto(c.m, c.v); if let q { F.metti(2, q, p) }; q = p }
        }
        let testa = 0.72, larg = 0.27
        var q: P3?
        for s in 0...90 {
            let u = Double(s) / 90, tt = t - (1 - u) * 2.2, v = ProveCuore.forma((tt / periodo).truncatingRemainder(dividingBy: 1))
            let p = nastro(testa + larg * u, 0.05 + alto * (0.32 + 0.5 * v))
            if let q { F.metti(s > 70 ? 4 : 3, q, p) }
            q = p
        }
        F.linee(&gc, colore: { $0 >= 4 ? OP.b(0.9) : OP.c(0.1 + 0.17 * Double($0)) }, spessore: { piccolo ? 0.45 + Double($0) * 0.09 : 0.7 + Double($0) * 0.15 },
                alone: { $0 >= 3 && !piccolo ? OP.s(0.09) : nil })
        let pt = nastro(testa + larg, 0.05 + alto * (0.32 + 0.5 * ProveCuore.forma((t / periodo).truncatingRemainder(dividingBy: 1))))
        Tav.alone(&gc, pt, piccolo ? 4 : 10, 0.8, Tav.bianco)
        guard !piccolo else { return }
        if ok {
            for (i, c) in O.enumerated() where i % 6 == 0 { let p = posto(c.m, c.v); M.zona(p.x, p.y, 14, i) }
            var h = ceil(m0 / 180) * 180
            while h <= m1 { let p = nastro((h - m0) / (m1 - m0) * 0.7, 0); OP.scritta(&gc, "\(Int(h / 60))", p.x, p.y + 10, 6.5, 600, OP.c(0.6)); h += 180 }
        }
        Tav.testate(&gc, W, "ECG · OGGI", "\(Int(D.adesso)) BPM", ok ? "MIN \(D.minimo) · MAX \(D.massimo)" : O.count == 1 ? "UNA MISURA OGGI" : "NESSUN BATTITO OGGI")   // 9 nov: una misura non è «nessun battito»
        if let s = M.scelta, ok, s >= 0, s < O.count {
            let c = O[s], p = posto(c.m, c.v), mm = Int(c.m)
            let stato = c.v > Double(D.riposo + 30) ? "SOTTO SFORZO" : c.v < Double(D.riposo + 6) ? "A RIPOSO" : "NORMALE"
            OP.riquadro(&gc, W, H, p.x, p.y, ["ORE \(mm / 60):\(String(format: "%02d", mm % 60))", "\(Int(c.v)) BATTITI AL MINUTO", stato], t - M.sceltaT, codice: "ECG")
        }
    }

}

#if os(iOS)
// MARK: le prove del TELEFONO

/// I dati del telefono per le prove: il numero scritto, di chi è, la rubrica, le chiamate di JARVIS, il tasto appena premuto e
/// quando è partita l'ultima chiamata; `premi` scrive una cifra (dai tasti di vetro di STARKPHONE).
struct DatiTelefonoOlo {
    var numero = ""
    var chi: String?
    var contatti: [(nome: String, numero: String)] = []
    var recenti: [(nome: String, numero: String, quando: String)] = []
    var premuto: (k: String, quando: Date)?
    var chiamata: Date?
    var premi: (String) -> Void = { _ in }
}

final class ProveTelefono {
    private static let tasti = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiTelefonoOlo, piccolo: Bool) {
        switch k {
        case 1: starkphone(&gc, W, H, t, M, D, piccolo)
        case 2: satelliti(&gc, W, H, t, M, D, piccolo)
        default: antenna(&gc, W, H, t, M, D, piccolo)
        }
    }

    private func inChiamata(_ D: DatiTelefonoOlo, _ secondi: Double) -> Bool { D.chiamata.map { Date().timeIntervalSince($0) < secondi } ?? false }

    // ANTENNA: il traliccio con le onde e le cifre in orbita (l'ultima sale dal proiettore)
    private func antenna(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiTelefonoOlo, _ piccolo: Bool) {
        let cx = W / 2, base = piccolo ? H - 3 : H - 14, rx = piccolo ? W * 0.3 : min(W * 0.2, 76)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        let al = 0.3, sz = piccolo ? H * 0.78 : min(H * 0.66, W * 0.52), cy = base - (piccolo ? 3 : 8)
        let ang = t * 0.35 + M.giro, nasce = OP.lis(t / 0.8), alto = 1.0 * nasce
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        Olo.cono(&gc, cx, base, rx, cy - sz * 0.95, sz * 0.22, a: 0.08)
        var F = FasciOlo(6)
        let gamba = { (k: Int, z: Double) -> P3 in let a = Double(k) / 3 * OP.due, r = 0.17 * (1 - z / 1.2); return P(cos(a) * r, sin(a) * r, z) }
        for k in 0..<3 {
            F.metti(3, gamba(k, 0.02), gamba(k, alto))
            var z = 0.06
            while z < alto - 0.1 { F.metti(1, gamba(k, z), gamba((k + 1) % 3, z + 0.13)); F.metti(0, gamba(k, z), gamba((k + 1) % 3, z)); z += 0.13 }
        }
        let zo = 0.5, ro = 0.62
        var q: P3?
        for s in 0...64 { let a = Double(s) / 64 * OP.due, p = P(cos(a) * ro, sin(a) * ro, zo); if let q { F.metti(1, q, p) }; q = p }
        F.linee(&gc, colore: { $0 >= 4 ? OP.b(0.85) : OP.c(0.1 + 0.17 * Double($0)) }, spessore: { piccolo ? 0.45 + Double($0) * 0.09 : 0.7 + Double($0) * 0.14 },
                alone: { $0 >= 3 && !piccolo ? OP.s(0.08) : nil })
        let cima = P(0, 0, alto + 0.05), chiama = inChiamata(D, 4), periodo = chiama ? 0.55 : 2.4
        Tav.alone(&gc, cima, piccolo ? 6 : 16, chiama ? 0.9 : 0.6, Tav.bianco)
        for k in 0..<4 {
            let u = (t / periodo + Double(k) / 4).truncatingRemainder(dividingBy: 1)
            let r = (piccolo ? 4 : 10) + u * (piccolo ? W * 0.4 : min(W * 0.42, 150)), a = (1 - u) * (chiama ? 0.75 : 0.35) * nasce
            gc.stroke(Tav.arco(cima.x, cima.y, r, .pi * 1.08, .pi * 1.92), with: .color(OP.c(a)), lineWidth: chiama ? 1.6 : 1)
            gc.stroke(Tav.arco(cima.x, cima.y, r, .pi * 0.12, .pi * 0.88), with: .color(OP.c(a)), lineWidth: chiama ? 1.6 : 1)
        }
        M.zona(cima.x, cima.y, 22, 0)
        let cifre = Array(D.numero.filter { !$0.isWhitespace }.suffix(14)).map(String.init), n = cifre.count
        for (i, c) in cifre.enumerated() {
            let a = Double(i) / Double(max(n, 7)) * OP.due + t * 0.5, ultima = i == n - 1
            let eta = ultima ? (D.premuto.map { Date().timeIntervalSince($0.quando) } ?? 9) : 9, su = OP.lis(eta / 0.45)
            let p = P(cos(a) * ro * su, sin(a) * ro * su, 0.05 + (zo - 0.05) * su + 0.03 * sin(t * 2 + Double(i))), davanti = p.z < 0
            if !piccolo {
                if ultima && eta < 0.6 { Tav.alone(&gc, p, 14, 0.5 * (1 - eta / 0.6), Tav.bianco) }
                OP.scritta(&gc, c, p.x, p.y + 4, davanti ? 13 : 10, 800, davanti ? OP.b(0.98) : OP.c(0.45))
            }
        }
        guard !piccolo else { return }
        OP.scritta(&gc, "TELEFONO", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, chiama ? "CHIAMATA IN CORSO" : (D.chi ?? (n > 0 ? "NUMERO" : "PRONTO")).uppercased(), W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if M.scelta == 0 {
            OP.riquadro(&gc, W, H, cima.x, cima.y, [D.numero.isEmpty ? "NESSUN NUMERO" : D.numero, D.chi?.uppercased() ?? (n > 0 ? "NON IN RUBRICA" : "SCRIVA O DETTI UN NUMERO"),
                                                     chiama ? "LA CHIAMATA È PARTITA" : "TOCCHI IL VERDE PER CHIAMARE"], t - M.sceltaT, codice: "ANTENNA")
        }
    }

    // STARKPHONE: il telefono di vetro di Iron Man 2, sospeso; i tasti sul vetro scrivono, il riflesso scorre, chiamando le onde
    private func starkphone(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiTelefonoOlo, _ piccolo: Bool) {
        if M.suTocco == nil {
            let premi = D.premi
            M.suTocco = { id in
                guard id >= 100, id < 100 + ProveTelefono.tasti.count else { return false }
                premi(ProveTelefono.tasti[id - 100])
                return true
            }
        }
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.08, sz: 1.45, su: 0.06, oscilla: 0.32, mano: 0.6, conoSu: 0.2, conoW: 0.7))
        var F = FasciOlo(6)
        let w = 0.5, h = 1.0, sp = 0.035, z0 = 0.05 + (1 - s.nasce) * 0.4, chiama = inChiamata(D, 4)
        let R = { (x: Double, z: Double, y: Double) -> P3 in s.P(x, y, z0 + z) }
        func bordo(_ Y: Double, _ g: Int) {
            let r = 0.1, ang: [(Double, Double, Double)] = [(w - r, h - r, 0), (-w + r, h - r, 1.5708), (-w + r, r, 3.1416), (w - r, r, 4.7124)]
            var q: P3?
            for (ax, az, a0) in ang { for k in 0...6 { let a = a0 + Double(k) / 6 * 1.5708, p = R(ax + cos(a) * r, az + sin(a) * r, Y); if let q { F.metti(g, q, p) }; q = p } }
            if let q { F.metti(g, q, R(w, h - r, Y)) }
        }
        bordo(-sp, 3); bordo(sp, 1)
        let premuto: String? = D.premuto.flatMap { Date().timeIntervalSince($0.quando) < 0.45 ? $0.k : nil }
        var celle: [(k: String, p: P3, on: Bool)] = []
        for (i, k) in ProveTelefono.tasti.enumerated() {
            let c = i % 3, r = i / 3, X = Double(c - 1) * 0.28, Z = 0.62 - Double(r) * 0.15, on = premuto == k, g = on ? 4 : 1
            let a = R(X - 0.1, Z - 0.055, 0), b = R(X + 0.1, Z - 0.055, 0), cc = R(X + 0.1, Z + 0.055, 0), d = R(X - 0.1, Z + 0.055, 0)
            F.metti(g, a, b); F.metti(g, b, cc); F.metti(g, cc, d); F.metti(g, d, a)
            celle.append((k, R(X, Z, 0), on))
        }
        Tav.traccia(&gc, F, piccolo)
        let a1 = R(-w, 0, 0), a2 = R(w, 0, 0), a3 = R(w, h, 0), a4 = R(-w, h, 0), vetro = Tav.spezzata([a1, a2, a3, a4], chiusa: true)
        gc.fill(vetro, with: .color(OP.s(0.05 + (chiama ? 0.05 * abs(sin(t * 6)) : 0))))
        let u = (t * 0.35).truncatingRemainder(dividingBy: 1.6) - 0.3, r1 = R(-w + u * 2 * w, 0, 0), r2 = R(-w + (u + 0.18) * 2 * w, h, 0)
        gc.fill(vetro, with: .linearGradient(Gradient(colors: [OP.b(0), OP.b(0.08), OP.b(0)]), startPoint: CGPoint(x: r1.x, y: r1.y), endPoint: CGPoint(x: r2.x, y: r2.y)))
        for c in celle where c.on { Tav.alone(&gc, c.p, s.sz * 0.14, 0.6, Tav.bianco) }
        if chiama {
            let c = R(0, h * 0.55, 0)
            for k in 0..<3 {
                let v = (t * 1.4 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                gc.stroke(Olo.ellisse(c.x, c.y, s.sz * (0.55 + v * 0.7), s.sz * (0.75 + v * 0.7)), with: .color(OP.c(0.6 * (1 - v))), lineWidth: 1.2)
            }
        }
        guard !piccolo else { return }
        for (i, c) in celle.enumerated() {
            OP.scritta(&gc, c.k, c.p.x, c.p.y + 3, 8.5, 700, c.on ? OP.b(1) : OP.c(0.9))
            M.zona(c.p.x, c.p.y, s.sz * 0.12, 100 + i)
        }
        let pn = R(0, 0.86, 0), cur = Int(max(0, t) * 2) % 2 == 1 ? "▏" : " "
        OP.scritta(&gc, D.numero.isEmpty ? "STARK · PRONTO" : OP.taglia(D.numero, 16) + cur, pn.x, pn.y, D.numero.isEmpty ? 7 : 11, 800, D.numero.isEmpty ? OP.c(0.8) : OP.b(0.98))
        if let chi = D.chi { let pc = R(0, 0.78, 0); OP.scritta(&gc, chi.uppercased(), pc.x, pc.y, 6.5, 700, OP.c(0.9)) }
        Tav.testate(&gc, W, "STARKPHONE", chiama ? "CHIAMATA" : nil)
    }

    // SATELLITI: la Terra coi satelliti Stark in orbita; i contatti sono stazioni in Italia; chiamando, il fascio sale da lei al
    // satellite più vicino e scende al contatto. Tocca un contatto: nome, numero, ultima chiamata.
    private func satelliti(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ D: DatiTelefonoOlo, _ piccolo: Bool) {
        let s = Tav.scena(&gc, W, H, t, M, piccolo, OpzioniOlo(al: 0.3, sz: 0.82, su: 1.15, giro: 0, mano: 0.8, conoSu: 0.3, conoW: 0.8))
        var F = FasciOlo(6)
        let giro = -12 + sin(t * 0.12) * 18 + M.giro * 40
        let G = Tav.globo(&F, s, 1, giroLon: -giro)
        let C = Array(D.contatti.prefix(24)), io = G(45.46, 9.19), chiama = inChiamata(D, 5)
        func pos(_ n: String) -> (Double, Double) { let h = Tav.seme(n) % 997; return (38 + Double(h % 9), 8 + Double((h * 7) % 10)) }
        let sat: [P3] = (0..<3).map { k in
            let a = t * (0.35 + Double(k) * 0.08) + Double(k) * 2.1, inc = 0.5 + Double(k) * 0.35, r = 1.32 + Double(k) * 0.08
            return s.P(cos(a) * r, sin(a) * r * cos(inc), sin(a) * r * sin(inc))
        }
        for k in 0..<3 {
            let inc = 0.5 + Double(k) * 0.35, r = 1.32 + Double(k) * 0.08
            var q: P3?
            for i in 0...64 { let a = Double(i) / 64 * OP.due, p = s.P(cos(a) * r, sin(a) * r * cos(inc), sin(a) * r * sin(inc)); if let q { F.metti(0, q, p) }; q = p }
        }
        Tav.traccia(&gc, F, piccolo)
        for p in sat {
            var pa = Path(CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            Olo.linea(&pa, p.x - 8, p.y, p.x - 3, p.y); Olo.linea(&pa, p.x + 3, p.y, p.x + 8, p.y)
            gc.stroke(pa, with: .color(OP.b(0.9)), lineWidth: 1)
            Tav.alone(&gc, p, 6, 0.5, Tav.bianco)
        }
        Tav.alone(&gc, io, piccolo ? 4 : 10, io.z < 0 ? 0.9 : 0.3, Tav.bianco)
        let stazioni: [P3] = C.map { c in let (la, lo) = pos(c.nome), p = G(la, lo); Tav.alone(&gc, p, piccolo ? 2 : 4, p.z < 0 ? 0.7 : 0.15); return p }
        let bersaglio = D.chi ?? (chiama ? D.recenti.first?.nome : nil)
        if let b = bersaglio, let ci = C.firstIndex(where: { $0.nome == b }), let meglio = sat.min(by: { hypot($0.x - io.x, $0.y - io.y) < hypot($1.x - io.x, $1.y - io.y) }) {
            let dst = stazioni[ci], v = chiama ? (t * 1.5).truncatingRemainder(dividingBy: 1) : 0.5
            gc.stroke(Tav.spezzata([io, meglio, dst]), with: .color(OP.b(chiama ? 0.8 : 0.4)), style: StrokeStyle(lineWidth: chiama ? 1.4 : 0.8, dash: [3, 3]))
            if chiama {
                let da: P3 = v < 0.5 ? io : meglio, verso: P3 = v < 0.5 ? meglio : dst, u: Double = v < 0.5 ? v * 2 : (v - 0.5) * 2
                let p: P3 = da + (verso - da) * u
                Tav.alone(&gc, p, 7, 0.9, Tav.bianco)
            }
        }
        guard !piccolo else { return }
        for (i, p) in stazioni.enumerated() where p.z < -0.2 { M.zona(p.x, p.y, 14, 200 + i) }
        OP.scritta(&gc, "LEI · MILANO", io.x, io.y - 10, 6.5, 700, OP.b(0.85))
        Tav.testate(&gc, W, "SATELLITI STARK", chiama ? "COLLEGAMENTO" : "\(D.contatti.count) CONTATTI", D.chi?.uppercased())
        if let i = Tav.scelta(M, 200), i < C.count {
            let c = C[i], p = stazioni[i], r = D.recenti.first { $0.nome == c.nome }
            OP.riquadro(&gc, W, H, p.x, p.y, [c.nome.uppercased(), c.numero, r.map { "ULTIMA \($0.quando)" } ?? "STAZIONE IN RUBRICA"], t - M.sceltaT, codice: "CONTATTO")
        }
    }
}
// MARK: le viste (in testa alle sezioni, con le chip)

struct OlogrammaCuoreProve: View {
    let dati: DatiCuoreOlo
    @State private var prove = ProveCuore()
    var body: some View {
        ProveOloVista(sezione: .cuore, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
    }
}

struct OlogrammaTelefono: View {
    let dati: DatiTelefonoOlo
    @State private var prove = ProveTelefono()
    var body: some View {
        ProveOloVista(sezione: .telefono, altezza: 260, crea: { prove.crea($0) }) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false) }
    }
}
#endif
