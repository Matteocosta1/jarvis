import Foundation
import SwiftUI

/// 13.7 · SINTESI, il cuore del reattore: VELO sull'iPhone (dentro la ghiera e le fasce) e, grande, sull'Apple Watch.
/// Stesso disegno del mockup «JARVIS Approvato» (funzione `sintesi` del RV): il guscio di trattini del film (chiaro sul bordo),
/// i frammenti di PULITO dietro e davanti, le lineette prospettiche che escono dal nucleo, il nucleo di vetro con la rete che
/// ruota in 3D, i due cerchi che si illuminano attorno. Le unità sono quelle del mockup (il raggio del cuore è 88): chi disegna
/// sceglie la scala (iPhone 1,68 punti per unità, polso circa 1,2).
/// Fatto per i 120 Hz: i dati fissi si calcolano una volta sola, i tratti si raccolgono in pochi tracciati per colore
/// (un'ottantina di disegni al fotogramma invece di settecento).
enum SintesiFase { case attesa, ascolto, elaboro, parlo }

enum Sintesi {
    // MARK: Dati fissi (gli stessi numeri del mockup)

    /// Il «caso» del mockup (h): sempre gli stessi numeri a ogni avvio.
    private static func h(_ n: Double) -> Double { let s = sin(n * 127.1 + 311.7) * 43758.5453; return s - floor(s) }

    private struct P3 { var x: Double, y: Double, z: Double }
    private static func ruota(_ p: P3, _ ax: Double, _ ay: Double) -> P3 {
        let (ca, sa, cb, sb) = (cos(ax), sin(ax), cos(ay), sin(ay))
        let y1 = p.y * ca - p.z * sa, z1 = p.y * sa + p.z * ca
        return P3(x: p.x * cb + z1 * sb, y: y1, z: -p.x * sb + z1 * cb)
    }

    /// I 150 nodi della rete (spirale di Fibonacci) e i legami fra i vicini.
    private static let nodi: [P3] = {
        let n = 150, au = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - (Double(i) + 0.5) / Double(n) * 2, r = (1 - y * y).squareRoot(), th = au * Double(i)
            return P3(x: r * cos(th), y: y, z: r * sin(th))
        }
    }()
    private static let legami: [(Int, Int)] = {
        var o: [(Int, Int)] = []
        for i in 0..<nodi.count { for j in (i + 1)..<nodi.count {
            let dx = nodi[i].x - nodi[j].x, dy = nodi[i].y - nodi[j].y, dz = nodi[i].z - nodi[j].z
            if dx * dx + dy * dy + dz * dz < 0.16 { o.append((i, j)) }
        } }
        return o
    }()

    /// Il guscio del film: 600 trattini tangenti alla sfera (gli estremi, sulla sfera di raggio 1, calcolati una volta).
    private struct Trattino { let a: P3, b: P3, w: Double, ph: Double }
    private static let guscio: [Trattino] = (0..<600).map { i in
        let fi = Double(i), g = Double(i % 26), sparso = i % 4 == 3
        let gy = 2 * h(g * 9.7 + 0.1) - 1, glon = h(g * 5.3) * 2 * .pi
        let y = sparso ? 2 * h(fi * 1.31 + 0.7) - 1 : max(-0.98, min(0.98, gy + (h(fi * 1.31) - 0.5) * 0.5))
        let lon = sparso ? h(fi * 2.17) * 2 * .pi : glon + (h(fi * 2.17) - 0.5) * 0.55 / max(0.3, (1 - gy * gy).squareRoot())
        let d = h(fi * 3.53) < 0.62 ? 0 : Double.pi / 2
        let l = 0.025 + 0.07 * pow(h(fi * 4.91), 2), r = 0.97 + 0.05 * h(fi * 6.1)
        let p0 = P3(x: (1 - y * y).squareRoot() * cos(lon), y: y, z: (1 - y * y).squareRoot() * sin(lon))
        // e1 = unità(p0 × asse), e2 = p0 × e1, la tangente nella direzione d
        let asse = abs(p0.y) < 0.9 ? P3(x: 0, y: 1, z: 0) : P3(x: 1, y: 0, z: 0)
        var e1 = P3(x: p0.y * asse.z - p0.z * asse.y, y: p0.z * asse.x - p0.x * asse.z, z: p0.x * asse.y - p0.y * asse.x)
        let le = (e1.x * e1.x + e1.y * e1.y + e1.z * e1.z).squareRoot(); if le > 0 { e1 = P3(x: e1.x / le, y: e1.y / le, z: e1.z / le) }
        let e2 = P3(x: p0.y * e1.z - p0.z * e1.y, y: p0.z * e1.x - p0.x * e1.z, z: p0.x * e1.y - p0.y * e1.x)
        let (cd, sd) = (cos(d), sin(d))
        let tg = P3(x: e1.x * cd + e2.x * sd, y: e1.y * cd + e2.y * sd, z: e1.z * cd + e2.z * sd)
        return Trattino(a: P3(x: r * (p0.x - tg.x * l), y: r * (p0.y - tg.y * l), z: r * (p0.z - tg.z * l)),
                        b: P3(x: r * (p0.x + tg.x * l), y: r * (p0.y + tg.y * l), z: r * (p0.z + tg.z * l)),
                        w: 0.4 + 0.9 * h(fi * 7.3), ph: h(fi * 8.9) * 2 * .pi)
    }
    /// Il bordo del guscio: tre giri spezzati che scorrono piano.
    private struct Giro { let r: Double, fr: [(Double, Double)], v: Double }
    private static let bordo: [Giro] = (0..<3).map { i in
        let fi = Double(i)
        let fr: [(Double, Double)] = (0..<14).map { k in
            let fk = Double(k)
            return ((fk + 0.5 * h(fi * 30 + fk)) / 14 * 2 * .pi, 0.12 + 0.3 * h(fi * 30 + fk * 1.7))
        }
        return Giro(r: [1, 0.985, 1.015][i], fr: fr, v: (0.03 + 0.03 * h(fi * 2.3)) * (i % 2 == 1 ? 1 : -1))
    }
    /// Le lineette che vengono avanti dal nucleo.
    private struct Scintilla { let a: Double, v: Double, ph: Double, l: Double, r0: Double }
    private static let scintille: [Scintilla] = (0..<150).map { i in
        let fi = Double(i)
        return Scintilla(a: h(fi * 1.9) * 2 * .pi, v: 0.18 + 0.3 * h(fi * 2.7), ph: h(fi * 3.1), l: 0.03 + 0.09 * h(fi * 4.3), r0: 0.08 + 0.2 * h(fi * 5.9))
    }
    /// I frammenti di PULITO: 11 anelli spezzati in 3D, 30 frammenti l'uno, qualche blocchetto.
    private struct Frammento { let a: Double, l: Double, w: Double, blocco: Bool }
    private struct Anello { let ax: Double, ay: Double, v: Double, r: Double, fr: [Frammento] }
    private static let anelli: [Anello] = (0..<11).map { i in
        let fi = Double(i)
        let fr: [Frammento] = (0..<30).map { k in
            let fk = Double(k), base = fi * 100
            return Frammento(a: (fk + 0.6 * h(base + fk * 1.37)) / 30 * 2 * .pi, l: 0.06 + 0.14 * h(base + fk * 2.71),
                             w: 0.5 + 1.8 * pow(h(base + fk * 4.4), 3), blocco: h(base + fk * 9.1) > 0.86)
        }
        return Anello(ax: 0.25 + h(fi * 3.3) * 1.3, ay: h(fi * 5.1) * 2 * .pi, v: (h(fi * 7.7) - 0.5) * 0.5,
                      r: i < 3 ? 0.45 + 0.15 * h(fi * 2.9) : 0.86 + 0.14 * h(fi * 2.9), fr: fr)
    }

    // MARK: Disegno

    /// Disegna SINTESI centrata in `c`, `scala` punti per unità del mockup.
    /// `colore(opacità, schiarisci)` è il colore del reattore (ciano a riposo, ambra quando pensa e parla).
    static func disegna(_ gc: GraphicsContext, centro c: CGPoint, scala: Double, t: Double, tv: Double, fase: SintesiFase,
                        vol: Double, energia: Double, linee: Double = 1, colore: (Double, Double) -> Color) {
        // al polso le linee sottili sono un poco più spesse (×1,35 sotto i 4 punti, come il mockup), perché in piccolo non spariscano
        let lw: (Double) -> Double = { $0 < 4 ? $0 * linee : $0 }
        var g = gc
        g.translateBy(x: c.x, y: c.y)
        g.scaleBy(x: scala, y: scala)
        g.blendMode = .plusLighter

        // il respiro della sfera (cuoreVero del mockup, versioni P): con la voce cresce, ma un quarto e mai più di +14 %
        let battito: Double = {
            switch fase {
            case .attesa: return 0.5 + 0.5 * sin(t * 1.2)
            case .ascolto: return 0.12 + 0.06 * sin(t * 2.5) + 0.85 * vol
            case .elaboro: return 0.5 + 0.5 * sin(t * 6)
            case .parlo: return 0.15 + 0.08 * sin(t * 3) + 0.8 * vol
            }
        }()
        let (rBase, coll): (Double, Double) = {
            switch fase {
            case .attesa: return (0.36 + 0.012 * battito, 0)
            case .ascolto: return (0.36, 0)          // 13.8 (il signore, 22 nov 08:02): ascoltando la sfera non cresce, percepisce
            case .elaboro: return (0.3, 0.55 + 0.1 * sin(t * 9))
            case .parlo: return (0.34 + 0.16 * energia + 0.08 * vol, 0)
            }
        }()
        let rB = 0.36 + min(0.05, (rBase - 0.36) * 0.25)
        let Rs = 88 * rB * (1 - coll * 0.5) * 1.05
        let R0 = 88 * 0.36 * 1.05, Rsh = (R0 + (Rs - R0) * 0.4) * 1.64
        let ay = tv * 0.18, ax = 0.32 + 0.06 * sin(t * 0.15)
        let luce: Double = fase == .elaboro ? 1 : (fase == .attesa ? 0.8 : 0.88 + 0.2 * vol)
        let acceso: Double = fase == .elaboro ? 1 : (fase == .attesa ? 0.18 : 0.55 + 0.45 * vol)
        // 13.8 · le scelte del signore (22 nov, mockup «JARVIS Approvato»):
        // · NUCLEO BRILLANTE (07:56): il vetro più acceso anche a riposo, un cuore di luce al centro, la rete più chiara; le linee
        //   prospettiche dietro non cambiano, così il nucleo stacca;
        // · ASCOLTO ONDE (08:02–08:05): le linee dietro restano calme come a riposo (niente corsa fitta), la sfera non cresce; dal
        //   nucleo escono due anelli leggeri, forti quanto la voce che li ha fatti nascere, e il nucleo si accende con la voce;
        // · PARLO ECO (08:05): le linee prospettiche tenui, sottili e lente (la luce segue la voce, non la velocità) e la sfera che
        //   cresce (fino a +12 %) e si accende con la voce di JARVIS.
        let ascolta = fase == .ascolto, parla = fase == .parlo
        let faseL: SintesiFase = ascolta ? .attesa : fase           // le linee e i frammenti ascoltando: come a riposo
        let volL = ascolta ? 0 : vol
        let accN = min(1, max(acceso, 0.5) + 0.12 + (ascolta ? 0.28 * vol : 0) + (parla ? 0.25 * vol : 0))
        let nucleo = Rsh * 0.58 * (parla ? 1 + 0.12 * vol : 1)
        func resp(_ per: Double, _ ph: Double) -> Double { 0.5 + 0.5 * sin(t * 2 * .pi / per + ph) }
        let dietroA = 0.5 + 0.3 * resp(12, 0), davantiA = 0.45 + 0.4 * resp(12, .pi), anelloA = 0.62 + 0.25 * resp(9, 1.3)

        // 1 · il fondo: il velo, il guscio del film e i frammenti dietro
        let velo = Path(ellipseIn: CGRect(x: -Rsh * 1.05, y: -Rsh * 1.05, width: Rsh * 2.1, height: Rsh * 2.1))
        g.fill(velo, with: .radialGradient(Gradient(colors: [colore(0.08 * luce, 0.3), colore(0, 0)]), center: .zero,
                                           startRadius: Rsh * 0.2, endRadius: Rsh * 1.05))
        var gg = g; gg.opacity = dietroA
        guscioFilm(gg, t: t, Rsh: Rsh, ax: ax, ay: ay, luce: luce, vol: volL, lw: lw, colore: colore)
        var gf = g; gf.opacity = 0.55 + 0.35 * resp(12, .pi)
        frammenti(gf, t: t, tv: tv, R: Rsh * 0.96, luce: luce, fase: faseL, davanti: false, forza: 0.7, lw: lw, colore: colore)

        // 2 · le lineette del film che vengono avanti, dal bordo del nucleo verso fuori (parlando: ECO, tenui e lente)
        if parla {
            lineette(g, t: t, Rsh: Rsh, luce: luce * 0.55 * (0.3 + 0.7 * vol), vol: 0, fase: .attesa, r0min: nucleo / Rsh + 0.04,
                     velocita: 0.45, spessore: 0.6, lw: lw, colore: colore)
        } else {
            lineette(g, t: t, Rsh: Rsh, luce: luce, vol: volL, fase: faseL, r0min: nucleo / Rsh + 0.04, lw: lw, colore: colore)
        }

        // 3 · il nucleo di vetro (tenue al centro, più chiaro sul bordo) e la rete che ruota
        let vetro = Path(ellipseIn: CGRect(x: -nucleo * 1.45, y: -nucleo * 1.45, width: nucleo * 2.9, height: nucleo * 2.9))
        g.fill(vetro, with: .radialGradient(Gradient(stops: [
            .init(color: colore(0.05 + 0.3 * accN, 0.3), location: 0),
            .init(color: colore(0.1 + 0.22 * accN, 0.25), location: 0.55),
            .init(color: colore(0.04 + 0.1 * accN, 0.2), location: 0.72),
            .init(color: colore(0, 0), location: 1)]), center: .zero, startRadius: 0, endRadius: nucleo * 1.45))
        // il cuore di luce (NUCLEO BRILLANTE)
        let cuore = Path(ellipseIn: CGRect(x: -nucleo * 0.75, y: -nucleo * 0.75, width: nucleo * 1.5, height: nucleo * 1.5))
        g.fill(cuore, with: .radialGradient(Gradient(stops: [
            .init(color: colore(0.32 + 0.2 * accN, 0.75), location: 0),
            .init(color: colore(0.12 + 0.1 * accN, 0.5), location: 0.5),
            .init(color: colore(0, 0), location: 1)]), center: .zero, startRadius: 0, endRadius: nucleo * 0.75))
        rete(g, t: t, tv: tv, fase: fase, vol: vol, volAccesi: volL, battito: battito, coll: coll, Rs: Rs, k: nucleo / Rs,
             luce: min(1, 0.26 + 0.74 * accN + 0.12), lw: lw, colore: colore)

        // 4 · i due cerchi che si illuminano attorno al nucleo (semitrasparenti)
        let fr: Double = fase == .elaboro ? 2.2 : 1
        var ga = g; ga.opacity = anelloA
        let kN = nucleo / (Rsh * 0.58)                              // 13.8: con PARLO ECO i cerchi seguono il nucleo che cresce (come il mockup)
        cerchio(ga, t: t, Rsh: Rsh, rr: Rsh * min(0.9, 0.74 * kN), inc: 1.05 + 0.12 * sin(t * 0.23), rot: tv * 0.35 * fr + 0.6, luce: luce, largo: 2.6, lw: lw, colore: colore)
        cerchio(ga, t: t, Rsh: Rsh, rr: Rsh * min(0.82, 0.64 * kN), inc: 1.75 + 0.1 * sin(t * 0.31), rot: -tv * 0.5 * fr, luce: luce * 0.7, largo: 1, lw: lw, colore: colore)

        // ascoltando: le ONDE che escono dal nucleo
        if ascolta { onde(g, t: t, Rsh: Rsh, nucleo: nucleo, vol: vol, lw: lw, colore: colore) }

        // 5 · sopra a tutto: la metà davanti dei frammenti, che passa sul nucleo
        var gd = g; gd.opacity = davantiA
        frammenti(gd, t: t, tv: tv, R: Rsh * 0.96, luce: luce, fase: faseL, davanti: true, forza: 0.8, lw: lw, colore: colore)

        // 6 · pensando, le scie che escono dal centro (cuoreVero del mockup: 48, sul raggio del cuore)
        if coll > 0 {
            var scie = Path()
            for s in 0..<48 {
                let fs = Double(s), dir = fs * 2.399
                let vita = (t * 0.9 + (0.5 + 0.5 * sin(fs * 12.9898))).truncatingRemainder(dividingBy: 1)
                let r1 = 88 * (0.06 + 0.46 * vita), r2 = r1 + 88 * 0.035 * (1 - vita)
                scie.move(to: CGPoint(x: r1 * cos(dir), y: r1 * sin(dir)))
                scie.addLine(to: CGPoint(x: r2 * cos(dir), y: r2 * sin(dir)))
            }
            g.stroke(scie, with: .color(colore(0.6, 0.5)), style: StrokeStyle(lineWidth: lw(1), lineCap: .round))
        }
    }

    // MARK: Le parti

    /// 13.8 · ASCOLTO ONDE: due anelli che escono dal bordo del nucleo verso il guscio (2,4 s l'uno, sfasati di mezzo giro), sottili e
    /// leggeri; ognuno è forte quanto la voce nel momento in cui è nato (come il mockup), così mostrano che JARVIS sta percependo.
    private static func onde(_ g: GraphicsContext, t: Double, Rsh: Double, nucleo: Double, vol: Double,
                             lw: (Double) -> Double, colore: (Double, Double) -> Color) {
        let per = 2.4
        for i in 0..<2 {
            let ti = t + Double(i) * per / 2
            let u = ti.truncatingRemainder(dividingBy: per) / per
            let forza = OndeAscolto.condivise.forza(i, giro: Int(floor(ti / per)), vol: vol)
            let r = nucleo * 1.02 + (Rsh * 0.95 - nucleo * 1.02) * (1 - pow(1 - u, 2))
            let a = pow(1 - u, 2) * (0.1 + 0.9 * forza) * 0.75
            guard a > 0.004 else { continue }
            let anello = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            g.stroke(anello, with: .color(colore(0.16 * a, 0.35)), lineWidth: lw(3.4))
            g.stroke(anello, with: .color(colore(0.8 * a, 0.7)), lineWidth: lw(0.9))
        }
    }

    private static func guscioFilm(_ g: GraphicsContext, t: Double, Rsh: Double, ax: Double, ay: Double, luce: Double, vol: Double,
                                   lw: (Double) -> Double, colore: (Double, Double) -> Color) {
        var B = [Path(), Path(), Path()]
        let luceDir = -0.7 + 0.5 * sin(t * 0.11)
        let (ca, sa, cb, sb) = (cos(ax), sin(ax), cos(ay), sin(ay))
        func proietta(_ p: P3, _ r: Double) -> (Double, Double, Double) {
            let y1 = p.y * ca - p.z * sa, z1 = p.y * sa + p.z * ca
            let x2 = p.x * cb + z1 * sb, z2 = -p.x * sb + z1 * cb
            let k = 1 / (1 - z2 * r / (Rsh * 5))
            return (x2 * r * k, y1 * r * k, z2 * r / Rsh)
        }
        for q in guscio {
            let A = proietta(q.a, Rsh), Bp = proietta(q.b, Rsh)
            let z = (A.2 + Bp.2) / 2
            let falce = 0.3 + 0.7 * pow(0.5 + 0.5 * cos(atan2(A.1, A.0) - luceDir), 2)
            let bordo = pow(1 - min(1, abs(z)), 2.2) * falce, lampo = 0.5 + 0.5 * sin(t * q.w * (1 + vol) + q.ph)
            let v = bordo * (0.75 + 0.25 * lampo) + (z > 0 ? 0.18 : 0.05) * lampo
            let k = v > 0.55 ? 2 : (v > 0.22 ? 1 : 0)
            B[k].move(to: CGPoint(x: A.0, y: A.1)); B[k].addLine(to: CGPoint(x: Bp.0, y: Bp.1))
        }
        g.stroke(B[2], with: .color(colore(0.12 * luce, 0.3)), lineWidth: lw(2.4))            // l'alone del bordo
        g.stroke(B[1], with: .color(colore(0.07 * luce, 0.25)), lineWidth: lw(2))
        let stili: [(Double, Double, Double)] = [(0.18, 0.15, 0.5), (0.55, 0.4, 0.65), (0.95, 0.65, 0.8)]
        for (k, s) in stili.enumerated() { g.stroke(B[k], with: .color(colore(min(1, s.0 * luce), s.1)), lineWidth: lw(s.2)) }
        // il bordo: tre giri spezzati, sottili, che scorrono piano (raccolti in quattro livelli di luce)
        var livelli = [Path(), Path(), Path(), Path()]
        var fs: [Double] = [0, 0, 0, 0], ns: [Double] = [0, 0, 0, 0]
        for giro in bordo {
            let rr = Rsh * giro.r
            for (s, l) in giro.fr {
                let a = s + t * giro.v, f = 0.2 + 0.8 * pow(0.5 + 0.5 * cos(a + l / 2 - luceDir), 2)
                let k = min(3, Int(f * 4))
                livelli[k].move(to: CGPoint(x: rr * cos(a), y: rr * sin(a)))
                livelli[k].addArc(center: .zero, radius: rr, startAngle: .radians(a), endAngle: .radians(a + l), clockwise: false)
                fs[k] += f; ns[k] += 1
            }
        }
        for k in 0..<4 where ns[k] > 0 {
            let f = fs[k] / ns[k]
            g.stroke(livelli[k], with: .color(colore(0.14 * luce * f, 0.3)), lineWidth: lw(2.4))
            g.stroke(livelli[k], with: .color(colore(0.75 * luce * f, 0.6)), lineWidth: lw(0.5))
        }
    }

    private static func lineette(_ g: GraphicsContext, t: Double, Rsh: Double, luce: Double, vol: Double, fase: SintesiFase, r0min: Double,
                                 velocita: Double = 1, spessore: Double = 1, lw: (Double) -> Double, colore: (Double, Double) -> Color) {
        let vel: Double = (fase == .elaboro ? 2.2 : (fase == .attesa ? 1 : 1.3 + 1.4 * vol)) * velocita
        var B = [Path(), Path()]
        for s in scintille {
            let u = (t * s.v * vel * 0.35 + s.ph).truncatingRemainder(dividingBy: 1)
            let r0 = max(r0min, s.r0)
            let r1 = Rsh * (r0 + (1 - r0) * u), r2 = min(Rsh * 1.01, r1 + Rsh * s.l * (0.6 + 0.8 * u))
            let a = s.a + 0.15 * sin(t * 0.2 + s.ph * 6), (cs, sn) = (cos(a), sin(a))
            let k = sin(Double.pi * u) > 0.6 ? 1 : 0
            B[k].move(to: CGPoint(x: cs * r1, y: sn * r1)); B[k].addLine(to: CGPoint(x: cs * r2, y: sn * r2))
        }
        g.stroke(B[0], with: .color(colore(0.28 * luce, 0.4)), lineWidth: lw(0.4 * spessore))
        g.stroke(B[1], with: .color(colore(min(1, (0.7 + 0.3 * vol) * luce), 0.7)), lineWidth: lw(0.55 * spessore))
    }

    private static func frammenti(_ g: GraphicsContext, t: Double, tv: Double, R: Double, luce: Double, fase: SintesiFase, davanti: Bool,
                                  forza: Double, lw: (Double) -> Double, colore: (Double, Double) -> Color) {
        let fr: Double = fase == .elaboro ? 2.4 : (fase == .attesa ? 1 : 1.5)
        // cinque livelli di profondità × tre spessori: i tratti si raccolgono, il disegno resta quello
        var linee = Array(repeating: Path(), count: 15), blocchi = Array(repeating: Path(), count: 5)
        var davSomma = Array(repeating: 0.0, count: 5), davConto = Array(repeating: 0.0, count: 5)
        for (i, A) in anelli.enumerated() {
            let fi = Double(i), spin = tv * A.v * fr + fi, axA = A.ax + 0.15 * sin(t * 0.2 + fi), ayA = A.ay + tv * 0.05
            let (ca, sa, cb, sb) = (cos(axA), sin(axA), cos(ayA), sin(ayA)), r = R * (0.8 + 0.2 * A.r)
            for f in A.fr {
                let a0 = f.a + spin, passi = max(2, Int((f.l / 0.05).rounded(.up)))
                var pts: [CGPoint] = []; pts.reserveCapacity(passi + 1); var zm = 0.0
                for s in 0...passi {
                    let a = a0 + f.l * Double(s) / Double(passi)
                    let px = r * cos(a), pz = r * sin(a)
                    let y1 = -pz * sa, z1 = pz * ca                        // ruota3([px, 0, pz], ax, ay)
                    let x2 = px * cb + z1 * sb, z2 = -px * sb + z1 * cb
                    let k = 1 / (1 - (z2 / R) * 0.25)
                    pts.append(CGPoint(x: x2 * k, y: y1 * k)); zm += z2 / R
                }
                zm /= Double(passi + 1)
                if (zm > 0) != davanti { continue }
                let dav = 0.5 + 0.5 * zm, livello = min(4, max(0, Int(dav * 5)))
                let spessore = f.w < 0.8 ? 0 : (f.w < 1.4 ? 1 : 2)
                linee[livello * 3 + spessore].addLines(pts)
                davSomma[livello] += dav; davConto[livello] += 1
                if f.blocco, let p = pts.first {
                    blocchi[livello].addRect(CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4 + 2.4 * dav, height: 1.6 + 1.6 * dav))
                }
            }
        }
        let spessori: [Double] = [0.6, 1.1, 1.8]
        for lv in 0..<5 where davConto[lv] > 0 {
            let dav = davSomma[lv] / davConto[lv]
            let col = colore(min(1, (0.1 + 0.55 * dav) * luce * forza), 0.15 + 0.45 * dav)
            for s in 0..<3 { g.stroke(linee[lv * 3 + s], with: .color(col), lineWidth: lw(spessori[s] * (0.5 + 0.55 * dav))) }
            g.fill(blocchi[lv], with: .color(colore(min(1, (0.3 * dav + 0.08) * luce * forza), 0.3)))
        }
    }

    private static func rete(_ g: GraphicsContext, t: Double, tv: Double, fase: SintesiFase, vol: Double, volAccesi: Double, battito: Double, coll: Double,
                             Rs: Double, k: Double, luce: Double, lw: (Double) -> Double, colore: (Double, Double) -> Color) {
        let gy = tv * 0.45, inc = 0.38 + 0.18 * sin(t * 0.21)
        let (sy, cyR, sx, cxR) = (sin(gy), cos(gy), sin(inc), cos(inc))
        let f1 = (t * 1.3 * (1 + vol)).truncatingRemainder(dividingBy: 2.4) - 1.2
        let f2 = (t * (1 + vol) + 2.1).truncatingRemainder(dividingBy: 2.4) - 1.2
        let fo = 0.25 + 0.9 * vol
        var P: [(CGPoint, Double, Double)] = []; P.reserveCapacity(nodi.count)
        for (i, n) in nodi.enumerated() {
            let fi = Double(i)
            var rr = 1 + 0.045 * sin(t * 1.3 + fi * 1.7)
            if fase == .parlo { rr += 0.13 * battito * sin(n.y * 6 - t * 8) }
            if coll > 0 { rr *= 1 - coll * (0.5 + 0.5 * sin(fi * 7.3)) * 0.6 }
            let x1 = n.x * cyR + n.z * sy, z1 = -n.x * sy + n.z * cyR
            let y2 = n.y * cxR - z1 * sx, z2 = n.y * sx + z1 * cxR, pr = 1 / (1 - z2 * 0.22)
            let p1 = n.x * 0.6 + n.y * 0.8, p2 = -n.x * 0.7 + n.y * 0.2 + n.z * 0.68
            let d1 = (p1 - f1) / 0.18, d2 = (p2 - f2) / 0.18
            P.append((CGPoint(x: x1 * Rs * rr * pr * k, y: y2 * Rs * rr * pr * k), z2, max(exp(-d1 * d1), exp(-d2 * d2)) * fo))
        }
        var strati = [Path(), Path(), Path()], accesi = Path()
        for (a, b) in legami {
            let (pa, za, oa) = P[a], (pb, zb, ob) = P[b], z = (za + zb) / 2
            let s = z > 0.35 ? 2 : (z > -0.3 ? 1 : 0)
            strati[s].move(to: pa); strati[s].addLine(to: pb)
            if (oa + ob) / 2 > 0.12 { accesi.move(to: pa); accesi.addLine(to: pb) }
        }
        // le larghezze del mockup sono nella scala della rete (k): qui la rete è già nella scala del nucleo
        let stili: [(Double, Double, Double)] = [(0.14, 0.1, 0.45), (0.28, 0.25, 0.6), (0.5, 0.45, 0.8)]
        for (s, st) in stili.enumerated() { g.stroke(strati[s], with: .color(colore(st.0 * luce, st.1)), lineWidth: lw(st.2 * k)) }
        g.stroke(accesi, with: .color(colore((0.4 + 0.4 * volAccesi) * luce, 0.7)), lineWidth: lw(0.9 * k))
        var punti = Path()
        for (p, z, o) in P {
            let r = (0.45 + 0.75 * (z + 1) / 2) * (1 + 0.8 * o) * k
            punti.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        g.fill(punti, with: .color(colore(0.7 * luce, 0.6)))
    }

    private static func cerchio(_ g: GraphicsContext, t: Double, Rsh: Double, rr: Double, inc: Double, rot: Double, luce: Double, largo: Double,
                                lw: (Double) -> Double, colore: (Double, Double) -> Color) {
        let passi = 72, hl = t * 0.9
        let (ca, sa, cb, sb) = (cos(inc), sin(inc), cos(rot), sin(rot))
        func punto(_ a: Double) -> (CGPoint, Double) {
            let px = rr * cos(a), pz = rr * sin(a)
            let y1 = -pz * sa, z1 = pz * ca
            let x2 = px * cb + z1 * sb, z2 = -px * sb + z1 * cb
            let k = 1 / (1 - z2 / (Rsh * 5))
            return (CGPoint(x: x2 * k, y: y1 * k), z2 / rr)
        }
        var B = [Path(), Path(), Path()]
        var prima = punto(0)
        for s in 1...passi {
            let a = Double(s) / Double(passi) * 2 * .pi, p = punto(a)
            let chiaro = pow(0.5 + 0.5 * cos(a - hl), 6), z = (p.1 + prima.1) / 2
            let b = z < -0.2 ? 0 : (chiaro > 0.4 ? 2 : 1)
            B[b].move(to: prima.0); B[b].addLine(to: p.0)
            prima = p
        }
        let stili: [(Double, Double, Double)] = [(0.05, 0.14, 0.25), (0.1, 0.3, 0.5), (0.18, 0.6, 0.8)]
        let tondo = StrokeStyle(lineWidth: 1, lineCap: .round)
        for (b, st) in stili.enumerated() where !B[b].isEmpty {
            let (ga, ca2, s) = st
            var stile = tondo
            stile.lineWidth = lw(largo * 5); g.stroke(B[b], with: .color(colore(ga * 0.7 * luce, 0.3)), style: stile)
            stile.lineWidth = lw(largo * 2.6); g.stroke(B[b], with: .color(colore(ga * luce, 0.3)), style: stile)
            stile.lineWidth = lw(largo); g.stroke(B[b], with: .color(colore(ca2 * luce, s)), style: stile)
            stile.lineWidth = lw(0.4); g.stroke(B[b], with: .color(colore(min(1, ca2 * 1.3 * luce), 0.6)), style: stile)
        }
    }
}

/// 13.8 · la forza di ogni anello delle ONDE, presa dalla voce quando l'anello nasce (un giro nuovo) e tenuta per tutto il giro.
/// Letta a ogni fotogramma dal disegno del reattore: protetta da un lucchetto, come Volume e Giri.
nonisolated final class OndeAscolto: @unchecked Sendable {
    static let condivise = OndeAscolto()
    private let lock = NSLock()
    private var giri: [Int] = [-1, -1]
    private var forze: [Double] = [0, 0]

    func forza(_ i: Int, giro: Int, vol: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard giri.indices.contains(i) else { return vol }
        if giri[i] != giro { giri[i] = giro; forze[i] = vol }
        return forze[i]
    }
}
