#if os(iOS)
import SwiftUI
import UIKit

// MARK: - 12.0 (16) · I WIDGET FILO
// Il signore (13 nov, 20:58): «io ti do dei comandi tipo mostrami e si apre filo che mostra quello che stiamo facendo, senza dover
// aprire le sezioni… sono come dei widget». «Mostrami…», «Fammi vedere…», «Fissalo» mettono il dato in un mini-ologramma FILO in
// alto a destra: fino a tre, il più nuovo in alto. Un tocco apre la sua sezione; trascinato a destra (o «toglilo») se ne va.
// Disegno, misure e tempi come il mockup 12.0 (16) (v1216/q16-7.js: disegnaFilo, widget, disponi, togliW, toccoW).

/// Lo strato dei widget, sopra le sezioni (ContentView).
struct StratoFilo: View {
    @ObservedObject private var filo = Filo.condiviso

    var body: some View {
        let alto = (FasciaAlta.finestra?.safeAreaInsets.top ?? 59) + 37      // nel mockup: 96 px dall'alto del telefono
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(Array(filo.widget.enumerated()), id: \.element.id) { i, w in
                WidgetFiloVista(w: w)
                    .offset(y: alto + Double(i) * 68)
                    .transition(.asymmetric(insertion: .identity,
                                            removal: .offset(x: 172 * 1.3).combined(with: .opacity)
                                                .animation(.timingCurve(0.4, 0, 0.8, 0.4, duration: 0.22))))
            }
        }
        .padding(.trailing, 12)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25), value: filo.widget.map(\.id))
        .ignoresSafeArea()
        .allowsHitTesting(!filo.widget.isEmpty)
    }
}

/// Un widget: il punto di luce nell'angolo e il filo che scende al cartellino, come le etichette degli Occhi.
private struct WidgetFiloVista: View {
    let w: WidgetFilo
    @State private var dx: Double = 0
    @State private var inizio: Date?

    private static let larghezza: Double = 172
    private static let altezza: Double = 62

    var body: some View {
        // le scritte già tagliate con «…» (taglia del mockup), una volta per aggiornamento, non a ogni fotogramma
        let titolo = Self.taglia(w.titolo.uppercased(), 70, UIFont.monospacedSystemFont(ofSize: 8, weight: .bold))
        let riga = Self.taglia(w.riga, Self.larghezza - 8 - 14, UIFont.systemFont(ofSize: 11.5, weight: .semibold))
        let alle = Self.ora.string(from: w.alle)
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSince(w.nato)
            let n = Self.nascita(t)
            Canvas(rendersAsynchronously: false) { gc, size in
                Self.disegna(&gc, size, t: t, titolo: titolo, riga: riga, alle: alle)
            }
            .frame(width: Self.larghezza, height: Self.altezza)
            // la nascita: si apre in largo su una riga sottile, poi in alto (0,3 s; l'angolo in alto a destra resta fermo)
            .scaleEffect(x: n.x, y: n.y, anchor: .topTrailing)
            .opacity(n.a)
        }
        .frame(width: Self.larghezza, height: Self.altezza)
        .offset(x: dx)
        .opacity(1 - min(0.8, dx / 160))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if inizio == nil { inizio = Date() }
                    dx = max(0, v.translation.width)
                }
                .onEnded { _ in
                    let ms = max(1, Date().timeIntervalSince(inizio ?? Date()) * 1000)
                    let v = dx / ms
                    inizio = nil
                    if dx > 64 || (dx > 18 && v > 0.5) {               // trascinato a destra: se ne va
                        Suoni.sparisce()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        _ = Filo.condiviso.togli(w.id)
                        return
                    }
                    let tocco = dx < 6
                    withAnimation(.easeOut(duration: 0.2)) { dx = 0 }
                    if tocco, let s = w.sezione {                        // un tocco: la sua sezione
                        Suoni.tocco()
                        Regia.condivisa.porta(s)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(w.titolo): \(w.riga)")
        .accessibilityHint("Tocchi per aprirlo, lo trascini a destra per toglierlo.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if let s = w.sezione { Regia.condivisa.porta(s) } }
        .accessibilityAction(named: "Togli") { _ = Filo.condiviso.togli(w.id) }
    }

    /// La nascita del mockup: scale(.2,.04) → (1,.04) al 45 % → (1,1), 0,3 s con la curva (.2,.8,.2,1).
    private static func nascita(_ t: Double) -> (x: Double, y: Double, a: Double) {
        guard t < 0.3 else { return (1, 1, 1) }
        let p = curva(max(0, t) / 0.3)
        if p < 0.45 { let k = p / 0.45; return (0.2 + 0.8 * k, 0.04, k) }
        return (1, 0.04 + 0.96 * (p - 0.45) / 0.55, 1)
    }

    /// cubic-bezier(.2, .8, .2, 1): il progresso per un tempo 0…1.
    private static func curva(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = (0.2, 0.8, 0.2, 1.0)
        func b(_ s: Double, _ p1: Double, _ p2: Double) -> Double { 3 * (1 - s) * (1 - s) * s * p1 + 3 * (1 - s) * s * s * p2 + s * s * s }
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<20 { s = (lo + hi) / 2; if b(s, x1, x2) < x { lo = s } else { hi = s } }
        return b(s, y1, y2)
    }

    /// Taglia la scritta con «…» perché stia in `massimo` punti.
    private static func taglia(_ s: String, _ massimo: Double, _ font: UIFont) -> String {
        let a: [NSAttributedString.Key: Any] = [.font: font]
        func largo(_ x: String) -> Double { Double((x as NSString).size(withAttributes: a).width) }
        guard largo(s) > massimo else { return s }
        var c = s
        while c.count > 1, largo(c + "…") > massimo { c.removeLast() }
        return c + "…"
    }

    private static let ora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Il disegno (disegnaFilo del mockup), in punti: 172 × 62.
    private static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, titolo: String, riga: String, alle: String) {
        let W = Double(size.width), H = Double(size.height)
        // si accende sfarfallando (nascita del mockup)
        let u0 = min(1, t / 0.5)
        gc.opacity = u0 < 1 ? (sin(u0 * 40) > -0.2 ? u0 : u0 * 0.3) : 1
        gc.blendMode = .plusLighter
        let ax = W - 6, ay = 6.0, u = Olo.liscia(t / 0.45), lx = W - 22 - (W - 60) * u, ly = 24.0
        // il punto di luce che pulsa
        let pul = (t * 0.9).truncatingRemainder(dividingBy: 1)
        gc.stroke(Olo.ellisse(ax, ay, 2 + pul * 8, 2 + pul * 8), with: .color(Olo.ciano.opacity(0.7 * (1 - pul))), lineWidth: 1)
        Olo.alone(&gc, CGPoint(x: ax, y: ay), 10, 0.5)
        gc.fill(Olo.ellisse(ax, ay, 2.4, 2.4), with: .color(Olo.bianco))
        // il filo che scende al cartellino
        var f = Path()
        f.move(to: CGPoint(x: ax, y: ay)); f.addLine(to: CGPoint(x: lx + 8, y: ly - 4)); f.addLine(to: CGPoint(x: 4, y: ly - 4))
        gc.stroke(f, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(1.1))
        // il cartellino che si allarga
        let bx = 4.0, by = ly, bw = W - 8, bh = H - by - 3
        let box = CGRect(x: bx + 0.5, y: by + 0.5, width: bw * u, height: bh)
        gc.fill(Path(CGRect(x: bx, y: by, width: bw * u, height: bh)),
                with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0.13), Olo.azzurro.opacity(0.02)]),
                                      startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + bh)))
        gc.stroke(Path(box), with: .color(Olo.ciano.opacity(0.35)), style: Olo.tratto(1.1))
        var ang = Path()
        let k = 8.0
        let angoli: [(x: Double, y: Double, sx: Double, sy: Double)] = [(x: bx, y: by, sx: 1, sy: 1), (x: bx + bw * u, y: by, sx: -1, sy: 1),
                                                                         (x: bx, y: by + bh, sx: 1, sy: -1), (x: bx + bw * u, y: by + bh, sx: -1, sy: -1)]
        for (px, py, sx, sy) in angoli {
            ang.move(to: CGPoint(x: px + sx * k, y: py)); ang.addLine(to: CGPoint(x: px, y: py)); ang.addLine(to: CGPoint(x: px, y: py + sy * k))
        }
        gc.stroke(ang, with: .color(Olo.bianco.opacity(0.9)), style: Olo.tratto(1.5))
        // le scritte (con il loro bagliore ciano)
        gc.blendMode = .normal
        var s = gc
        s.addFilter(.shadow(color: Olo.azzurro.opacity(0.9), radius: 3))
        s.draw(Text(titolo).font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 143 / 255, green: 240 / 255, blue: 1).opacity(0.95)),
               at: CGPoint(x: 10, y: ly - 8), anchor: UnitPoint(x: 0, y: 0.8))
        s.draw(Text(alle).font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Olo.ciano.opacity(0.7)),
               at: CGPoint(x: W - 30, y: ly - 8), anchor: UnitPoint(x: 1, y: 0.8))
        if u > 0.6 {
            var r = gc
            r.addFilter(.shadow(color: Olo.azzurro.opacity(0.9), radius: 4))
            r.draw(Text(riga).font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(red: 236 / 255, green: 252 / 255, blue: 1).opacity(0.98)),
                   at: CGPoint(x: 11, y: by + bh / 2 + 4.5), anchor: UnitPoint(x: 0, y: 0.8))
        }
    }
}
#endif
