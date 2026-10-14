import SwiftUI

/// Il reattore Mark IV sull'orologio: anello di plasma, archi HUD e una sfera di particelle e filamenti che ruota in 3D.
/// Versione alleggerita per la batteria dell'Apple Watch; stessi colori dell'iPhone:
/// azzurro quando aspetta e ascolta, arancione quando pensa e parla.
struct ReattoreOrologio: View {
    let fase: JarvisOrologio.Fase

    @State private var calore: Double = 0
    @State private var obiettivo: Double = 0
    @State private var inizioTransizione = Date.distantPast

    nonisolated private static let azzurro = (r: 0.22, g: 0.88, b: 0.80)
    nonisolated private static let arancio = (r: 1.00, g: 0.47, b: 0.10)

    /// La sfera: 70 nodi distribuiti in modo uniforme e i filamenti tra i vicini (calcolati una volta sola).
    nonisolated private static let nodi: [(x: Double, y: Double, z: Double)] = {
        let n = 70
        let aureo = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - (Double(i) + 0.5) / Double(n) * 2
            let r = (1 - y * y).squareRoot()
            let th = aureo * Double(i)
            return (r * cos(th), y, r * sin(th))
        }
    }()
    nonisolated private static let legami: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        let p = nodi
        for i in 0..<p.count {
            for j in (i + 1)..<p.count {
                let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y, dz = p[i].z - p[j].z
                if dx * dx + dy * dy + dz * dz < 0.3 { out.append((i, j)) }
            }
        }
        return out
    }()

    var body: some View {
        // In attesa basta un'animazione lenta (risparmia batteria); quando lavora, fluida.
        TimelineView(.animation(minimumInterval: fase == .attesa ? 1.0 / 15 : 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let mix = miscela(adesso: ctx.date)
            Canvas { gc, size in
                disegna(gc, size: size, t: t, mix: mix)
            }
        }
        .onAppear { impostaObiettivo(animato: false) }
        .onChange(of: fase) { impostaObiettivo(animato: true) }
        .accessibilityLabel("Parla con Jarvis")
    }

    private func impostaObiettivo(animato: Bool) {
        let nuovo: Double = (fase == .elaboro || fase == .parlo) ? 1 : 0
        calore = animato ? miscela(adesso: Date()) : nuovo
        obiettivo = nuovo
        inizioTransizione = animato ? Date() : .distantPast
    }

    private func miscela(adesso: Date) -> Double {
        let p = min(1, max(0, adesso.timeIntervalSince(inizioTransizione) / 0.9))
        let dolce = p * p * (3 - 2 * p)
        return calore + (obiettivo - calore) * dolce
    }

    nonisolated static func colore(_ mix: Double, _ opacita: Double = 1, schiarisci: Double = 0) -> Color {
        let a = azzurro, b = arancio
        let r = a.r + (b.r - a.r) * mix, g = a.g + (b.g - a.g) * mix, bl = a.b + (b.b - a.b) * mix
        return Color(red: r + (1 - r) * schiarisci, green: g + (1 - g) * schiarisci, blue: bl + (1 - bl) * schiarisci).opacity(opacita)
    }

    private func disegna(_ gc: GraphicsContext, size: CGSize, t: Double, mix: Double) {
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let c = CGPoint(x: cx, y: cy)
        let R: Double = Double(min(size.width, size.height)) / 2 * 0.86
        // ascoltando e parlando seguono il volume vero della voce
        let letto = Volume.voce.leggi()                        // letto sempre, così in silenzio ricade da solo
        let attivo = fase == .ascolto || fase == .parlo
        let vol: Double = attivo ? letto.voce : 0              // sillaba per sillaba
        let energia: Double = attivo ? letto.energia : 0       // la forza del discorso, lenta
        // la velocità resta fissa per fase: è moltiplicata per il tempo, e farla variare con la voce fa scattare tutto
        let (ampiezza, velocita, battito): (Double, Double, Double) = {
            switch fase {
            case .attesa: return (0.035, 0.35, 0.5 + 0.5 * sin(t * 1.2))
            case .ascolto: return (0.04 + 0.14 * vol, 0.7, 0.12 + 0.06 * sin(t * 2.5) + 0.85 * vol)
            case .elaboro: return (0.09, 1.6, 0.5 + 0.5 * sin(t * 6.0))
            case .parlo: return (0.045 + 0.12 * vol, 1.0, 0.15 + 0.08 * sin(t * 3.0) + 0.8 * vol)
            }
        }()
        let tv = Giri.reattore.avanza(velocita)                // tempo × velocità, senza salti
        let col = ReattoreOrologio.colore

        // bagliore
        let alone = Path(ellipseIn: CGRect(x: cx - R * 1.2, y: cy - R * 1.2, width: R * 2.4, height: R * 2.4))
        gc.fill(alone, with: .radialGradient(Gradient(colors: [col(mix, 0.36 + 0.14 * battito, 0), col(mix, 0, 0)]),
                                             center: c, startRadius: R * 0.2, endRadius: R * 1.2))

        // anello di plasma
        var plasma = gc
        plasma.blendMode = .plusLighter
        for i in 0..<14 {
            let fi = Double(i)
            let raggio: Double = R * (0.84 + 0.008 * fi) * (1 + 0.05 * energia)
            var p = Path()
            for k in 0...64 {
                let th: Double = Double(k) / 64 * 2 * .pi
                let o1: Double = sin(3 * th + tv * 1.3 + fi * 0.3) * 0.55
                let o2: Double = sin(5 * th - tv * 1.7 + fi * 0.5) * 0.30
                let o3: Double = sin(8 * th + tv * 2.3 + fi * 0.2) * 0.15
                let spinta: Double = 0.6 + 0.4 * battito
                let r: Double = raggio * (1 + ampiezza * (o1 + o2 + o3) * spinta)
                let pt = CGPoint(x: cx + r * cos(th), y: cy + r * sin(th))
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            plasma.stroke(p, with: .color(col(mix, 0.34, i % 5 == 0 ? 0.5 : 0.1)), lineWidth: 0.9)
        }

        // arco HUD
        let inizio = Angle(radians: t * (fase == .elaboro ? 1.2 : 0.4))
        var arco = Path()
        arco.addArc(center: c, radius: R * 0.64, startAngle: inizio, endAngle: inizio + .radians(.pi * 1.3), clockwise: false)
        gc.stroke(arco, with: .color(col(mix, 0.8, 0.15)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        // il cuore: sfera di particelle legate da filamenti che ruota in 3D (come sull'iPhone, alleggerita)
        let (rBase, collasso): (Double, Double) = {
            switch fase {
            case .attesa: return (0.40 + 0.015 * battito, 0)
            case .ascolto: return (0.36 + 0.22 * energia + 0.10 * vol, 0)   // il discorso la gonfia, ogni sillaba la spinge
            case .elaboro: return (0.34, 0.55 + 0.1 * sin(t * 9))
            case .parlo: return (0.36 + 0.16 * energia + 0.08 * vol, 0)
            }
        }()
        let Rs: Double = R * rBase * (1 - collasso * 0.5)
        let giroY: Double = tv * 0.45
        let inclina: Double = 0.38 + 0.18 * sin(t * 0.21)
        let sy = sin(giroY), cyR = cos(giroY), sx = sin(inclina), cxR = cos(inclina)
        // onde di pensiero: due fasce di luce attraversano la sfera, più svelte e forti con la voce
        let fronte1: Double = (t * 1.3 * (1 + vol)).truncatingRemainder(dividingBy: 2.4) - 1.2
        let fronte2: Double = (t * 1.0 * (1 + vol) + 2.1).truncatingRemainder(dividingBy: 2.4) - 1.2
        let forzaOnda: Double = 0.25 + 0.9 * vol
        func onda(_ n: (x: Double, y: Double, z: Double)) -> Double {
            let p1 = n.x * 0.6 + n.y * 0.8, p2 = -n.x * 0.7 + n.y * 0.2 + n.z * 0.68
            let a = exp(-pow((p1 - fronte1) / 0.18, 2)), b = exp(-pow((p2 - fronte2) / 0.18, 2))
            return max(a, b) * forzaOnda
        }
        var proiettati: [(CGPoint, Double, Double)] = []
        proiettati.reserveCapacity(ReattoreOrologio.nodi.count)
        for (i, n) in ReattoreOrologio.nodi.enumerated() {
            let fi = Double(i)
            var raggio: Double = 1 + 0.045 * sin(t * 1.3 + fi * 1.7)
            if fase == .parlo { raggio += 0.13 * battito * sin(n.y * 6 - t * 8) }
            if collasso > 0 { raggio *= 1 - collasso * (0.5 + 0.5 * sin(fi * 7.3)) * 0.6 }
            let x1 = n.x * cyR + n.z * sy, z1 = -n.x * sy + n.z * cyR
            let y2 = n.y * cxR - z1 * sx, z2 = n.y * sx + z1 * cxR
            let prospettiva: Double = 1 / (1 - z2 * 0.22)
            proiettati.append((CGPoint(x: cx + x1 * Rs * raggio * prospettiva, y: cy + y2 * Rs * raggio * prospettiva), z2, onda(n)))
        }
        var rete = gc
        rete.blendMode = .plusLighter
        var dietro = Path(), davanti = Path(), accesi = Path()
        for (a, b) in ReattoreOrologio.legami {
            let (pa, za, oa) = proiettati[a], (pb, zb, ob) = proiettati[b]
            if (za + zb) / 2 > 0 { davanti.move(to: pa); davanti.addLine(to: pb) } else { dietro.move(to: pa); dietro.addLine(to: pb) }
            if (oa + ob) / 2 > 0.12 { accesi.move(to: pa); accesi.addLine(to: pb) }
        }
        rete.stroke(dietro, with: .color(col(mix, 0.24, 0.1)), lineWidth: 0.6)
        rete.stroke(davanti, with: .color(col(mix, 0.6, 0.4)), lineWidth: 0.8)
        rete.stroke(accesi, with: .color(col(mix, 0.45 + 0.4 * vol, 0.7)), lineWidth: 1.0)
        var puntiDietro = Path(), puntiDavanti = Path(), puntiOnda = Path()
        for (pt, z, o) in proiettati {
            let lato: Double = (1.0 + 1.4 * (z + 1) / 2) * (1 + 0.9 * o)
            let r = CGRect(x: pt.x - lato / 2, y: pt.y - lato / 2, width: lato, height: lato)
            if z > 0 { puntiDavanti.addEllipse(in: r) } else { puntiDietro.addEllipse(in: r) }
            if o > 0.2 { puntiOnda.addEllipse(in: CGRect(x: pt.x - lato, y: pt.y - lato, width: lato * 2, height: lato * 2)) }
        }
        rete.fill(puntiDietro, with: .color(col(mix, 0.5, 0.2)))
        rete.fill(puntiDavanti, with: .color(col(mix, 1, 0.7)))
        rete.fill(puntiOnda, with: .color(col(mix, 0.35 + 0.3 * vol, 0.85)))
        if collasso > 0 {
            var scie = Path()
            for s in 0..<24 {
                let fs = Double(s)
                let dir: Double = fs * 2.399
                let vita: Double = (t * 0.9 + (0.5 + 0.5 * sin(fs * 12.9898))).truncatingRemainder(dividingBy: 1)
                let r1: Double = R * (0.06 + 0.46 * vita)
                let r2: Double = r1 + R * 0.04 * (1 - vita)
                scie.move(to: CGPoint(x: cx + r1 * cos(dir), y: cy + r1 * sin(dir)))
                scie.addLine(to: CGPoint(x: cx + r2 * cos(dir), y: cy + r2 * sin(dir)))
            }
            rete.stroke(scie, with: .color(col(mix, 0.6, 0.5)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }

        // nucleo
        let scala: Double = fase == .parlo ? 0.22 + 0.36 * vol + 0.03 * sin(t * 3) : (fase == .ascolto ? 0.2 + 0.36 * vol : 0.2)
        let nucleo: Double = Rs * scala
        gc.fill(Path(ellipseIn: CGRect(x: cx - nucleo * 2, y: cy - nucleo * 2, width: nucleo * 4, height: nucleo * 4)),
                with: .radialGradient(Gradient(colors: [col(mix, 0.8, 0.7), col(mix, 0, 0)]),
                                      center: c, startRadius: 0, endRadius: nucleo * 2))
        gc.fill(Path(ellipseIn: CGRect(x: cx - nucleo / 2, y: cy - nucleo / 2, width: nucleo, height: nucleo)),
                with: .color(col(mix, 1, 0.85)))
    }
}
