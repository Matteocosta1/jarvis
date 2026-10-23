#if os(iOS)
import SwiftUI
import AVFoundation

/// Ricordi › TRACCIA (build 22): la vista dalla fotocamera con le frecce olografiche verso l'ultimo parcheggio,
/// la distanza e il tempo a piedi; sotto gli ultimi ricordi e le frasi A VOCE. Come nel mockup.
struct PannelliTraccia: View {
    let parcheggio: DatiRicordi.Riga?
    let ultimi: [DatiRicordi.Riga]
    @StateObject private var bussola = Bussola()
    private let tinta = Color.ciano

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Pannello(titolo: "TRACCIA", tinta: tinta) {
                if let pk = parcheggio, let lat = pk.lat, let lon = pk.lon {
                    let rotta = bussola.verso(lat: lat, lon: lon)
                    VistaAR(lat: lat, lon: lon, bussola: bussola)
                        .aspectRatio(720.0 / 520.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.22), lineWidth: 1))
                    RigaHUD("Parcheggiata", [pk.quando, pk.luogo ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    RigaHUD("Distanza", rotta.map { Rotta.distanza($0.metri) } ?? "cerco la posizione…")
                    RigaHUD("A piedi", rotta.map { Rotta.aPiedi($0.metri) } ?? "—")
                } else {
                    Text("Nessun parcheggio salvato, Sir. Quando lascia la macchina dica «Jarvis, ho parcheggiato qui».")
                        .font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                }
            }
            Pannello(titolo: "ULTIMI", tinta: tinta) {
                if ultimi.isEmpty {
                    Text("Ancora nessun ricordo, Sir.").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                }
                ForEach(ultimi) { r in RigaHUD(r.testo, r.luogo ?? r.quando) }
            }
            PannelloAVoce(frasi: ["«Jarvis, traccia la macchina»", "«Jarvis, portami alla macchina»",
                                  "«Jarvis, dov'è la macchina?»", "«Jarvis, dove ho messo le chiavi?»"])
        }
        .onAppear { if parcheggio?.lat != nil { bussola.accendi() } }
        .onDisappear { bussola.spegni() }
    }
}

/// La strada vista dalla fotocamera e la freccia olografica verso la macchina (disegnata come `disegnaAR` del mockup).
/// Direzione = rilevamento verso la macchina meno la direzione dell'iPhone; in alto la bussola.
struct VistaAR: View {
    let lat: Double
    let lon: Double
    @ObservedObject var bussola: Bussola
    @State private var motore = MotoreOcchi()
    @State private var camera = false

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.035)          // #050809, se la fotocamera non c'è
            if camera { AnteprimaOcchi(sessione: motore.sessione) }
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                Canvas { gc, size in disegna(gc, size, t: ctx.date.timeIntervalSinceReferenceDate) }
            }
            .allowsHitTesting(false)
        }
        .task {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return }
            let m = motore
            let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                m.avvia { ok in c.resume(returning: ok) }
            }
            if !Task.isCancelled { camera = ok } else { m.ferma() }
        }
        .onDisappear { motore.ferma() }
    }

    private func disegna(_ gc: GraphicsContext, _ size: CGSize, t: Double) {
        let W = Double(size.width), H = Double(size.height)
        let s = W / 720                                       // le misure del mockup sono su una tela larga 720
        let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
        let rotta = bussola.verso(lat: lat, lon: lon)
        // la macchina sullo schermo: a destra o a sinistra di quanto bisogna girarsi (oltre gli 80° resta sul bordo)
        let rel: Double = rotta.map { Rotta.relativa(rilevamento: $0.rilevamento, direzione: bussola.direzione ?? 0) } ?? 0
        let angolo: Double = max(-80, min(80, rel)) * Double.pi / 180
        let bx: Double = W * (0.5 + 0.42 * sin(angolo)), by: Double = H * 0.52
        let ax: Double = W * 0.5, ay: Double = H * 0.98, cx0: Double = W * 0.5, cy0: Double = H * 0.6
        func punto(_ u: Double) -> (x: Double, y: Double) {
            let v: Double = 1 - u
            let x: Double = v * v * ax + 2 * v * u * cx0 + u * u * bx
            let y: Double = v * v * ay + 2 * v * u * cy0 + u * u * by
            return (x, y)
        }
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }

        var luce = gc
        luce.addFilter(.shadow(color: ciano, radius: CGFloat(8 * max(s, 0.5))))
        // le frecce a chevron che scorrono verso la macchina
        for k in 0..<7 {
            let u: Double = (Double(k) + (t * 0.9).truncatingRemainder(dividingBy: 1)) / 7
            if u > 0.96 { continue }
            let p = punto(u), q = punto(min(1, u + 0.02))
            let an: Double = atan2(q.y - p.y, q.x - p.x)
            let lato: Double = 46 * (1 - u * 0.78) * s
            var freccia = Path()
            freccia.move(to: pt(p.x + cos(an + 2.4) * lato, p.y + sin(an + 2.4) * lato * 0.45))
            freccia.addLine(to: pt(p.x, p.y))
            freccia.addLine(to: pt(p.x + cos(an - 2.4) * lato, p.y + sin(an - 2.4) * lato * 0.45))
            var g = luce
            g.opacity = min(1, (1 - u) * 1.4) * (0.55 + 0.45 * sin(t * 4 - Double(k)))
            let spessore: Double = max(2, 9 * (1 - u * 0.8)) * s
            g.stroke(freccia, with: .color(ciano), style: StrokeStyle(lineWidth: CGFloat(spessore), lineCap: .round, lineJoin: .round))
        }
        // il punto della macchina: l'anello che pulsa e l'asta
        let pulsa: Double = (t * 0.8).truncatingRemainder(dividingBy: 1)
        let rx: Double = (18 + pulsa * 40) * s
        var anello = luce
        anello.opacity = 1 - pulsa
        anello.stroke(Path(ellipseIn: CGRect(x: bx - rx, y: by - rx * 0.35, width: rx * 2, height: rx * 0.7)), with: .color(ciano), lineWidth: 2)
        var asta = Path()
        asta.move(to: pt(bx, by))
        asta.addLine(to: pt(bx, by - 70 * s))
        luce.stroke(asta, with: .color(ciano), lineWidth: 2)
        // l'etichetta «MACCHINA · 180 m»
        let testo = rotta.map { "MACCHINA · \(Rotta.distanza($0.metri))" } ?? "MACCHINA"
        let scritta = gc.resolve(Text(testo).font(.system(size: CGFloat(22 * s), weight: .bold, design: .monospaced)).foregroundStyle(ColoriHUD.chiaro))
        let misura = scritta.measure(in: size)
        let lw: Double = Double(misura.width) + 28 * s, lh: Double = 42 * s
        let ex: Double = min(max(bx, lw / 2 + 4), W - lw / 2 - 4)
        let riquadro = Path(roundedRect: CGRect(x: ex - lw / 2, y: by - 116 * s, width: lw, height: lh), cornerRadius: CGFloat(8 * s))
        gc.fill(riquadro, with: .color(Color(red: 0.02, green: 0.03, blue: 0.035).opacity(0.8)))
        gc.stroke(riquadro, with: .color(ciano), lineWidth: 1.5)
        gc.draw(scritta, at: pt(ex, by - 95 * s), anchor: .center)
        // la bussola in alto: dove guarda l'iPhone
        let nord = bussola.direzione.map { Rotta.bussola($0) } ?? "BUSSOLA…"
        gc.draw(Text(nord).font(.system(size: CGFloat(16 * s), weight: .semibold, design: .monospaced)).foregroundStyle(ciano.opacity(0.85)),
                at: pt(W / 2, 26 * s), anchor: .center)
    }
}
#endif
