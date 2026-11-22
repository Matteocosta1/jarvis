import SwiftUI

/// Il reattore del polso: dal 13.7 il cuore di SINTESI, grande (lo stesso disegno dell'iPhone, Sintesi.swift); stessi colori
/// dell'iPhone: azzurro quando aspetta e ascolta, arancione quando pensa e parla.
struct ReattoreOrologio: View {
    let fase: JarvisOrologio.Fase
    /// Fermo sull'ultimo fotogramma mentre c'è l'ologramma della ruota (il reattore è velato all'1,5 %: non si vede, e
    /// l'orologio disegna solo l'ologramma).
    var fermo = false

    @State private var calore: Double = 0
    @State private var obiettivo: Double = 0
    @State private var inizioTransizione = Date.distantPast

    nonisolated private static let azzurro = (r: 0.22, g: 0.88, b: 0.80)
    nonisolated private static let arancio = (r: 1.00, g: 0.47, b: 0.10)

    var body: some View {
        // 4 nov (il signore: «tutte le animazioni di tutta l'app»): sempre al massimo dell'orologio, 60 Hz (prima 15 in attesa, 30 al lavoro)
        TimelineView(.animation(minimumInterval: nil, paused: fermo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let mix = miscela(adesso: ctx.date)
            Canvas { gc, size in
                disegna(gc, size: size, t: t, mix: mix)
            }
        }
        // il bordo sfuma: pieno fino al 72 % del raggio, a zero sul cerchio (come il mockup; il riquadro è di 208 punti)
        .mask(RadialGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                     .init(color: .clear, location: 1)], center: .center, startRadius: 0, endRadius: 104))
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

    /// 13.7 · al polso SINTESI, grande (la scelta del signore, 21 nov 21:23: «al polso SINTESI, ma grande… CORONA è troppi
    /// elementi»; mockup «JARVIS Approvato»): il bagliore e il cuore di SINTESI, senza ghiera né fasce. Il riquadro è il cerchio
    /// di 145 unità del mockup (208 punti per 290 unità); SINTESI a 1,68 come sull'iPhone; le linee sottili ×1,35 perché in piccolo
    /// non spariscano. Il bordo sfuma a zero (la maschera nel body), così senza ghiera il bagliore non lascia un cerchio netto.
    private func disegna(_ gc: GraphicsContext, size: CGSize, t: Double, mix: Double) {
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2
        let c = CGPoint(x: cx, y: cy)
        let u = Double(min(size.width, size.height)) / 2 / 145                 // punti per unità del mockup
        let sc = u * 1.68                                                      // la scala di SINTESI
        // ascoltando e parlando seguono il volume vero della voce
        let letto = Volume.voce.leggi()                        // letto sempre, così in silenzio ricade da solo
        let attivo = fase == .ascolto || fase == .parlo
        let vol: Double = attivo ? letto.voce : 0              // sillaba per sillaba
        let energia: Double = attivo ? letto.energia : 0       // la forza del discorso, lenta
        // la velocità resta fissa per fase: è moltiplicata per il tempo, e farla variare con la voce fa scattare tutto
        let (velocita, battito): (Double, Double) = {
            switch fase {
            case .attesa: return (0.35, 0.5 + 0.5 * sin(t * 1.2))
            case .ascolto: return (0.7, 0.12 + 0.06 * sin(t * 2.5) + 0.85 * vol)
            case .elaboro: return (1.6, 0.5 + 0.5 * sin(t * 6.0))
            case .parlo: return (1.0, 0.15 + 0.08 * sin(t * 3.0) + 0.8 * vol)
            }
        }()
        let tv = Giri.reattore.avanza(velocita)                // tempo × velocità, senza salti
        let col = ReattoreOrologio.colore

        // il bagliore (88 unità × 1,25, alla scala di SINTESI)
        let Rb = 88 * sc
        gc.fill(Path(ellipseIn: CGRect(x: cx - Rb * 1.25, y: cy - Rb * 1.25, width: Rb * 2.5, height: Rb * 2.5)),
                with: .radialGradient(Gradient(colors: [col(mix, 0.34 + 0.12 * battito, 0), col(mix, 0, 0)]),
                                      center: c, startRadius: Rb * 0.2, endRadius: Rb * 1.25))
        // il cuore: SINTESI
        let fs: SintesiFase = {
            switch fase { case .attesa: return .attesa; case .ascolto: return .ascolto; case .elaboro: return .elaboro; case .parlo: return .parlo }
        }()
        Sintesi.disegna(gc, centro: c, scala: sc, t: t, tv: tv, fase: fs, vol: vol, energia: energia, linee: 1.35) { op, sch in
            col(mix, op, sch)
        }
    }
}
