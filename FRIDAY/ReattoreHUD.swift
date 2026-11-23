#if os(iOS)
import SwiftUI

/// Il «cuore» visivo di JARVIS: dal 13.7 VELO (fasce di plasma velate e, al centro, SINTESI).
/// Azzurro quando aspetta e ascolta; diventa un'intelligenza arancione, più agitata, quando pensa e parla.
struct Reattore: View {
    let fase: Fase
    @Environment(\.jarvisCoperto) private var coperto    // 26 ott sera: sotto Studio o Social si ferma sull'ultimo fotogramma

    @State private var calore: Double = 0          // 0 = azzurro, 1 = arancione (valore di partenza della transizione)
    @State private var obiettivo: Double = 0
    @State private var inizioTransizione = Date.distantPast

    private static let azzurro = (r: 0.22, g: 0.88, b: 0.80)

    private static let arancio = (r: 1.00, g: 0.47, b: 0.10)

    /// 5 nov (punto 8 approvato: «stesso disegno, meno lavoro»): i seni e coseni degli angoli dell'anello di plasma, calcolati
    /// una volta sola. Per ogni filo, a ogni fotogramma, sin(n·θ + b) = sin(n·θ)·cos b + cos(n·θ)·sin b: 2 funzioni per onda
    /// e per filo invece di una per punto (da circa 10.000 a circa 200 al fotogramma). Gli stessi numeri di prima.
    private struct Angolo { let c, s, s3, c3, s5, c5, s8, c8: Double }
    private static let puntiPlasma = 110
    private static let angoli: [Angolo] = (0...puntiPlasma).map { k in
        let th = Double(k) / Double(puntiPlasma) * 2 * .pi
        return Angolo(c: cos(th), s: sin(th), s3: sin(3 * th), c3: cos(3 * th), s5: sin(5 * th), c5: cos(5 * th), s8: sin(8 * th), c8: cos(8 * th))
    }

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

    /// 13.7 · VELO (la scelta del signore, 22 nov 01:40): dentro la ghiera (AnelliHUD, senza gli archi coi fermi) il bagliore, le
    /// fasce di plasma e le scintille velate al 62 % e, al centro, SINTESI (Sintesi.swift) a 1,68 (il cuore era a 1,4). Tutto resta
    /// dentro il cerchio della ghiera (145 punti), come il mockup «JARVIS Approvato».
    private func disegna(_ gc: GraphicsContext, size: CGSize, t: Double, mix: Double) {
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let c = CGPoint(x: cx, y: cy)
        let R: Double = Double(min(size.width, size.height)) / 2 * 0.80     // il raggio del cuore (88 unità del mockup a 1,4)
        let u = R / 88                                                         // punti per unità alla scala 1,4
        var gc = gc
        let bordo = Double(min(size.width, size.height)) / 2 * 145 / 154     // il cerchio della ghiera (145 su 154)
        gc.clip(to: Path(ellipseIn: CGRect(x: cx - bordo, y: cy - bordo, width: bordo * 2, height: bordo * 2)))

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

        // 1. il bagliore di fondo, alla scala di SINTESI (1,68)
        let Rb = 88 * u * 1.2
        let alone = Path(ellipseIn: CGRect(x: cx - Rb * 1.25, y: cy - Rb * 1.25, width: Rb * 2.5, height: Rb * 2.5))
        gc.fill(alone, with: .radialGradient(Gradient(colors: [colore(mix, 0.34 + 0.12 * battito), colore(mix, 0)]),
                                             center: c, startRadius: Rb * 0.2, endRadius: Rb * 1.25))

        // 2. le fasce di plasma, velate (VELO: 62 %)
        var plasma = gc
        plasma.blendMode = .plusLighter
        plasma.opacity = 0.62
        let fili = 30
        let spinta: Double = 0.6 + 0.4 * battito
        for i in 0..<fili {
            let fi = Double(i)
            let raggio: Double = R * (0.86 + 0.0045 * fi) * (1 + 0.05 * energia)   // l'anello si allarga col discorso
            let b1: Double = tv * 1.3 + fi * 0.21, b2: Double = -tv * 1.7 + fi * 0.37, b3: Double = tv * 2.3 + fi * 0.11
            let (cb1, sb1, cb2, sb2, cb3, sb3) = (cos(b1), sin(b1), cos(b2), sin(b2), cos(b3), sin(b3))
            let k0: Double = ampiezza * spinta
            var p = Path()
            for (k, a) in Reattore.angoli.enumerated() {
                let o1: Double = (a.s3 * cb1 + a.c3 * sb1) * 0.55          // sin(3θ + b1)
                let o2: Double = (a.s5 * cb2 + a.c5 * sb2) * 0.30          // sin(5θ + b2)
                let o3: Double = (a.s8 * cb3 + a.c8 * sb3) * 0.15          // sin(8θ + b3)
                let r: Double = raggio * (1 + k0 * (o1 + o2 + o3))
                let pt = CGPoint(x: cx + r * a.c, y: cy + r * a.s)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            let luce: Double = 0.17 + 0.14 * (0.5 + 0.5 * sin(fi * 0.9 + t * 0.8)) + 0.2 * vol
            plasma.stroke(p, with: .color(colore(mix, luce, schiarisci: i % 7 == 0 ? 0.5 : 0.1)), lineWidth: 1.0)
        }

        // 3. le scintille che scorrono lungo l'anello (anche loro velate)
        let scintille = 90
        var puntini = Path()                                   // 5 nov (punto 8): un riempimento solo, stesso colore per tutte
        for s in 0..<scintille {
            let fs = Double(s)
            let th: Double = fs / Double(scintille) * 2 * .pi + tv * (0.15 + 0.1 * sin(fs))
            let o1: Double = sin(3 * th + tv * 1.3) * 0.55
            let o2: Double = sin(5 * th - tv * 1.7) * 0.3
            let caso: Double = 0.5 + 0.5 * sin(fs * 12.9898)
            let r: Double = R * (0.86 + 0.14 * caso) * (1 + ampiezza * (o1 + o2))
            let lato: Double = 1.2 + 1.3 * (0.5 + 0.5 * sin(fs * 3.1 + t * 3))
            let rett = CGRect(x: cx + r * cos(th) - lato / 2, y: cy + r * sin(th) - lato / 2, width: lato, height: lato)
            puntini.addEllipse(in: rett)
        }
        plasma.fill(puntini, with: .color(colore(mix, 0.8, schiarisci: 0.55)))

        // 4. il cuore: SINTESI, a 1,68
        let fs: SintesiFase = {
            switch fase { case .attesa: return .attesa; case .ascolto: return .ascolto; case .elaboro: return .elaboro; case .parlo: return .parlo }
        }()
        Sintesi.disegna(gc, centro: c, scala: u * 1.2, t: t, tv: tv, fase: fs, vol: vol, energia: energia) { op, sch in
            colore(mix, op, schiarisci: sch)
        }
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
            let base = caldo ? Color(red: 0.20, green: 0.08, blue: 0.02) : Color(red: 33 / 255, green: 15 / 255, blue: 5 / 255)
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
                    gc.stroke(g, with: .color((caldo ? Color.rossoF : Color.ciano).opacity(0.035)), lineWidth: 0.5)
                }
            }
            .animation(.easeInOut(duration: 0.9), value: caldo)
        }
        .ignoresSafeArea()
    }
}
#endif
