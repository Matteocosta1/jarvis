#if os(iOS)
import SwiftUI

/// Il «cuore» visivo di JARVIS (Mark IV): un anello di plasma fatto di decine di fili ondulati,
/// archi da HUD che girano e, al centro, una sfera di particelle legate da filamenti che ruota in 3D.
/// Azzurro quando aspetta e ascolta; diventa un'intelligenza arancione, più agitata, quando pensa e parla.
struct Reattore: View {
    let fase: Fase
    @Environment(\.jarvisCoperto) private var coperto    // 26 ott sera: sotto Studio o Social si ferma sull'ultimo fotogramma

    @State private var calore: Double = 0          // 0 = azzurro, 1 = arancione (valore di partenza della transizione)
    @State private var obiettivo: Double = 0
    @State private var inizioTransizione = Date.distantPast

    private static let azzurro = (r: 0.22, g: 0.88, b: 0.80)

    /// I nodi della sfera: 150 punti distribuiti in modo uniforme (spirale di Fibonacci).
    private static let nodi: [(x: Double, y: Double, z: Double)] = {
        let n = 150
        let aureo = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - (Double(i) + 0.5) / Double(n) * 2
            let r = (1 - y * y).squareRoot()
            let th = aureo * Double(i)
            return (r * cos(th), y, r * sin(th))
        }
    }()

    /// I filamenti: ogni nodo è legato ai vicini più prossimi (calcolato una volta sola).
    private static let legami: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        let p = nodi
        for i in 0..<p.count {
            for j in (i + 1)..<p.count {
                let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y, dz = p[i].z - p[j].z
                if dx * dx + dy * dy + dz * dz < 0.16 { out.append((i, j)) }
            }
        }
        return out
    }()
    private static let arancio = (r: 1.00, g: 0.47, b: 0.10)

    var body: some View {
        TimelineView(.animation(paused: coperto)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let mix = miscela(adesso: ctx.date)
            Canvas { gc, size in
                disegna(gc, size: size, t: t, mix: mix)
            }
        }
        .onAppear { impostaObiettivo(animato: false) }
        .onChange(of: fase) { impostaObiettivo(animato: true) }
        .accessibilityHidden(true)
    }

    // MARK: Colore

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

    private func colore(_ mix: Double, _ opacita: Double = 1, schiarisci: Double = 0) -> Color {
        let a = Reattore.azzurro, b = Reattore.arancio
        let r = a.r + (b.r - a.r) * mix, g = a.g + (b.g - a.g) * mix, bl = a.b + (b.b - a.b) * mix
        return Color(red: r + (1 - r) * schiarisci, green: g + (1 - g) * schiarisci, blue: bl + (1 - bl) * schiarisci).opacity(opacita)
    }

    // MARK: Disegno

    private func disegna(_ gc: GraphicsContext, size: CGSize, t: Double, mix: Double) {
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let c = CGPoint(x: cx, y: cy)
        let R: Double = Double(min(size.width, size.height)) / 2 * 0.80

        // energia e velocità secondo la fase; ascoltando e parlando seguono il volume vero della voce
        let letto = Volume.voce.leggi()                        // letto sempre, così in silenzio ricade da solo
        let attivo = fase == .ascolto || fase == .parlo
        let vol: Double = attivo ? letto.voce : 0              // sillaba per sillaba
        let energia: Double = attivo ? letto.energia : 0       // la forza del discorso, lenta
        // la velocità resta fissa per fase: è moltiplicata per il tempo, e farla variare con la voce fa scattare tutto
        let (ampiezza, velocita, battito): (Double, Double, Double) = {
            switch fase {
            case .attesa: return (0.035, 0.35, 0.5 + 0.5 * sin(t * 1.2))
            case .ascolto: return (0.035 + 0.14 * vol, 0.7, 0.12 + 0.06 * sin(t * 2.5) + 0.85 * vol)
            case .elaboro: return (0.085, 1.6, 0.5 + 0.5 * sin(t * 6.0))
            case .parlo: return (0.04 + 0.12 * vol, 1.0, 0.15 + 0.08 * sin(t * 3.0) + 0.8 * vol)
            }
        }()
        let tv = Giri.reattore.avanza(velocita)                // tempo × velocità, senza salti

        // 1. bagliore di fondo
        let alone = Path(ellipseIn: CGRect(x: cx - R * 1.25, y: cy - R * 1.25, width: R * 2.5, height: R * 2.5))
        gc.fill(alone, with: .radialGradient(Gradient(colors: [colore(mix, 0.34 + 0.12 * battito), colore(mix, 0)]),
                                             center: c, startRadius: R * 0.2, endRadius: R * 1.25))

        // 2. anello di plasma: tanti fili chiusi, ognuno deformato da onde diverse
        var plasma = gc
        plasma.blendMode = .plusLighter
        let fili = 30
        let punti = 110
        for i in 0..<fili {
            let fi = Double(i)
            let raggio: Double = R * (0.86 + 0.0045 * fi) * (1 + 0.05 * energia)   // l'anello si allarga col discorso
            var p = Path()
            for k in 0...punti {
                let th: Double = Double(k) / Double(punti) * 2 * .pi
                let o1: Double = sin(3 * th + tv * 1.3 + fi * 0.21) * 0.55
                let o2: Double = sin(5 * th - tv * 1.7 + fi * 0.37) * 0.30
                let o3: Double = sin(8 * th + tv * 2.3 + fi * 0.11) * 0.15
                let spinta: Double = 0.6 + 0.4 * battito
                let r: Double = raggio * (1 + ampiezza * (o1 + o2 + o3) * spinta)
                let pt = CGPoint(x: cx + r * cos(th), y: cy + r * sin(th))
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            let luce: Double = 0.17 + 0.14 * (0.5 + 0.5 * sin(fi * 0.9 + t * 0.8)) + 0.2 * vol
            plasma.stroke(p, with: .color(colore(mix, luce, schiarisci: i % 7 == 0 ? 0.5 : 0.1)), lineWidth: 1.0)
        }

        // 3. scintille che scorrono lungo l'anello
        let scintille = 90
        for s in 0..<scintille {
            let fs = Double(s)
            let th: Double = fs / Double(scintille) * 2 * .pi + tv * (0.15 + 0.1 * sin(fs))
            let o1: Double = sin(3 * th + tv * 1.3) * 0.55
            let o2: Double = sin(5 * th - tv * 1.7) * 0.3
            let caso: Double = 0.5 + 0.5 * sin(fs * 12.9898)
            let r: Double = R * (0.86 + 0.14 * caso) * (1 + ampiezza * (o1 + o2))
            let lato: Double = 1.2 + 1.3 * (0.5 + 0.5 * sin(fs * 3.1 + t * 3))
            let rett = CGRect(x: cx + r * cos(th) - lato / 2, y: cy + r * sin(th) - lato / 2, width: lato, height: lato)
            plasma.fill(Path(ellipseIn: rett), with: .color(colore(mix, 0.8, schiarisci: 0.55)))
        }

        // 4. archi HUD che girano in senso opposto
        let archi: [(Double, Double, Double, Double)] = [(0.66, 0.25, 0.70, 1.5), (0.60, -0.4, 0.45, 3.0), (0.71, 0.12, 0.25, 1.0)]
        let fretta: Double = fase == .elaboro ? 3 : 1
        for (n, arcoDati) in archi.enumerated() {
            let (fr, vel, lung, spessore) = arcoDati
            let inizio = Angle(radians: t * vel * fretta + Double(n) * 2.1)
            var arco = Path()
            arco.addArc(center: c, radius: R * fr, startAngle: inizio, endAngle: inizio + .radians(2 * .pi * lung), clockwise: false)
            gc.stroke(arco, with: .color(colore(mix, 0.75, schiarisci: 0.15)), style: StrokeStyle(lineWidth: spessore, lineCap: .round))
        }
        // tacche sull'anello interno
        let tacche = 60
        for k in 0..<tacche {
            let th: Double = Double(k) / Double(tacche) * 2 * .pi - t * 0.08
            let lunga = k % 5 == 0
            let r1: Double = R * 0.54
            let r2: Double = R * (lunga ? 0.575 : 0.56)
            var tac = Path()
            tac.move(to: CGPoint(x: cx + r1 * cos(th), y: cy + r1 * sin(th)))
            tac.addLine(to: CGPoint(x: cx + r2 * cos(th), y: cy + r2 * sin(th)))
            gc.stroke(tac, with: .color(colore(mix, lunga ? 0.5 : 0.22)), lineWidth: 1)
        }

        // 5. il cuore: una sfera di particelle collegate da filamenti (una rete neurale) che ruota in 3D.
        //    In attesa respira piano; ascoltando si gonfia; pensando collassa in un nucleo e lancia scintille;
        //    parlando è attraversata da onde.
        let (rBase, collasso): (Double, Double) = {
            switch fase {
            case .attesa: return (0.36 + 0.012 * battito, 0)
            case .ascolto: return (0.34 + 0.22 * energia + 0.10 * vol, 0)   // il discorso la gonfia, ogni sillaba la spinge
            case .elaboro: return (0.30, 0.55 + 0.1 * sin(t * 9))
            case .parlo: return (0.34 + 0.16 * energia + 0.08 * vol, 0)
            }
        }()
        let Rs: Double = R * rBase * (1 - collasso * 0.5)
        let giroY: Double = tv * 0.45
        let inclina: Double = 0.38 + 0.18 * sin(t * 0.21)
        let (sy, cyR, sx, cxR) = (sin(giroY), cos(giroY), sin(inclina), cos(inclina))
        // onde di pensiero: due fasce di luce attraversano la sfera, più svelte e forti con la voce
        let fronte1: Double = (t * 1.3 * (1 + vol)).truncatingRemainder(dividingBy: 2.4) - 1.2
        let fronte2: Double = (t * 1.0 * (1 + vol) + 2.1).truncatingRemainder(dividingBy: 2.4) - 1.2
        let forzaOnda: Double = 0.25 + 0.9 * vol
        func onda(_ n: (x: Double, y: Double, z: Double)) -> Double {
            let p1 = n.x * 0.6 + n.y * 0.8, p2 = -n.x * 0.7 + n.y * 0.2 + n.z * 0.68
            let a = exp(-pow((p1 - fronte1) / 0.18, 2)), b = exp(-pow((p2 - fronte2) / 0.18, 2))
            return max(a, b) * forzaOnda
        }
        var proiettati: [(CGPoint, Double, Double)] = []           // punto, profondità, onda
        proiettati.reserveCapacity(Reattore.nodi.count)
        for (i, n) in Reattore.nodi.enumerated() {
            let fi = Double(i)
            // respiro organico: ogni nodo si muove un poco per conto suo
            var raggio: Double = 1 + 0.045 * sin(t * 1.3 + fi * 1.7)
            if fase == .parlo { raggio += 0.13 * battito * sin(n.y * 6 - t * 8) }          // onde che attraversano la sfera
            if collasso > 0 { raggio *= 1 - collasso * (0.5 + 0.5 * sin(fi * 7.3)) * 0.6 } // tutti verso il centro
            // rotazione attorno a Y, poi inclinazione attorno a X
            let x1 = n.x * cyR + n.z * sy, z1 = -n.x * sy + n.z * cyR
            let y2 = n.y * cxR - z1 * sx, z2 = n.y * sx + z1 * cxR
            let prospettiva: Double = 1 / (1 - z2 * 0.22)
            let pt = CGPoint(x: cx + x1 * Rs * raggio * prospettiva, y: cy + y2 * Rs * raggio * prospettiva)
            proiettati.append((pt, z2, onda(n)))
        }
        // i filamenti, in tre strati di profondità (davanti più luminosi)
        var rete = gc
        rete.blendMode = .plusLighter
        var strati = [Path(), Path(), Path()]
        var accesi = Path()                                                  // i filamenti attraversati dall'onda
        for (a, b) in Reattore.legami {
            let (pa, za, oa) = proiettati[a], (pb, zb, ob) = proiettati[b]
            let z = (za + zb) / 2
            let k = z > 0.35 ? 2 : (z > -0.3 ? 1 : 0)
            strati[k].move(to: pa)
            strati[k].addLine(to: pb)
            if (oa + ob) / 2 > 0.12 { accesi.move(to: pa); accesi.addLine(to: pb) }
        }
        for k in 0..<3 {
            rete.stroke(strati[k], with: .color(colore(mix, [0.18, 0.36, 0.62][k], schiarisci: [0.1, 0.25, 0.45][k])), lineWidth: CGFloat([0.6, 0.8, 1.0][k]))
        }
        rete.stroke(accesi, with: .color(colore(mix, 0.45 + 0.4 * vol, schiarisci: 0.7)), lineWidth: 1.1)
        // i nodi: puntini più grandi e luminosi quando sono davanti
        var nodiPath = [Path(), Path(), Path()]
        var nodiOnda = Path()
        for (pt, z, o) in proiettati {
            let lato: Double = (1.1 + 1.9 * (z + 1) / 2) * (1 + 0.9 * o)
            let k = z > 0.35 ? 2 : (z > -0.3 ? 1 : 0)
            nodiPath[k].addEllipse(in: CGRect(x: pt.x - lato / 2, y: pt.y - lato / 2, width: lato, height: lato))
            if o > 0.2 { nodiOnda.addEllipse(in: CGRect(x: pt.x - lato, y: pt.y - lato, width: lato * 2, height: lato * 2)) }
        }
        for k in 0..<3 {
            rete.fill(nodiPath[k], with: .color(colore(mix, [0.45, 0.75, 1.0][k], schiarisci: [0.2, 0.45, 0.7][k])))
        }
        rete.fill(nodiOnda, with: .color(colore(mix, 0.35 + 0.3 * vol, schiarisci: 0.85)))   // alone attorno ai nodi investiti dall'onda
        // pulviscolo: particelle libere che orbitano attorno alla sfera
        var polvere = Path()
        for d in 0..<70 {
            let fd = Double(d)
            let caso: Double = 0.5 + 0.5 * sin(fd * 78.233)
            let th: Double = fd * 2.399 + tv * (0.08 + 0.12 * caso)
            let r: Double = R * (rBase * (1 - collasso * 0.5) + 0.04 + 0.13 * caso)
            let lato: Double = 0.8 + 1.2 * (0.5 + 0.5 * sin(fd * 3.7 + t * 2))
            polvere.addEllipse(in: CGRect(x: cx + r * cos(th) - lato / 2, y: cy + r * sin(th) * 0.92 - lato / 2, width: lato, height: lato))
        }
        rete.fill(polvere, with: .color(colore(mix, 0.55, schiarisci: 0.45)))
        // pensando: scintille che schizzano fuori dal nucleo, come un big bang continuo
        if collasso > 0 {
            var scie = Path()
            for s in 0..<48 {
                let fs = Double(s)
                let dir: Double = fs * 2.399
                let vita: Double = (t * 0.9 + (0.5 + 0.5 * sin(fs * 12.9898))).truncatingRemainder(dividingBy: 1)
                let r1: Double = R * (0.06 + 0.46 * vita)
                let r2: Double = r1 + R * 0.035 * (1 - vita)
                scie.move(to: CGPoint(x: cx + r1 * cos(dir), y: cy + r1 * sin(dir)))
                scie.addLine(to: CGPoint(x: cx + r2 * cos(dir), y: cy + r2 * sin(dir)))
            }
            rete.stroke(scie, with: .color(colore(mix, 0.6, schiarisci: 0.5)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }

        // 6. nucleo: si accende quando parla, pulsa quando ascolta
        let scala: Double = fase == .parlo ? 0.2 + 0.36 * vol + 0.03 * sin(t * 3) : (fase == .ascolto ? 0.18 + 0.36 * vol : 0.2)
        let nucleo: Double = Rs * scala
        gc.fill(Path(ellipseIn: CGRect(x: cx - nucleo * 2.2, y: cy - nucleo * 2.2, width: nucleo * 4.4, height: nucleo * 4.4)),
                with: .radialGradient(Gradient(colors: [colore(mix, 0.8, schiarisci: 0.7), colore(mix, 0)]),
                                      center: c, startRadius: 0, endRadius: nucleo * 2.2))
        gc.fill(Path(ellipseIn: CGRect(x: cx - nucleo / 2, y: cy - nucleo / 2, width: nucleo, height: nucleo)),
                with: .color(colore(mix, 1, schiarisci: 0.85)))
    }
}

/// Sfondo animato: un bagliore che respira lentamente, del colore della fase.
struct SfondoHUD: View {
    let fase: Fase
    @Environment(\.jarvisCoperto) private var coperto    // 26 ott sera: sotto Studio o Social si ferma sull'ultimo fotogramma
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: coperto)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let caldo = fase == .elaboro || fase == .parlo
            let base = caldo ? Color(red: 0.20, green: 0.08, blue: 0.02) : Color(red: 0.02, green: 0.13, blue: 0.13)
            ZStack {
                Color.fondo
                RadialGradient(colors: [base.opacity(0.9 + 0.1 * sin(t * 0.7)), .clear],
                               center: UnitPoint(x: 0.5, y: 0.28 + 0.02 * sin(t * 0.4)), startRadius: 0, endRadius: 560)
                // griglia HUD appena visibile
                Canvas { gc, size in
                    let passo: CGFloat = 28
                    var g = Path()
                    var x: CGFloat = 0
                    while x < size.width { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); x += passo }
                    var y: CGFloat = (CGFloat(t * 6).truncatingRemainder(dividingBy: passo))
                    while y < size.height { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); y += passo }
                    gc.stroke(g, with: .color((caldo ? Color.orange : Color.ciano).opacity(0.035)), lineWidth: 0.5)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: caldo)
        }
        .ignoresSafeArea()
    }
}
#endif
