#if os(iOS)
import SwiftUI
import Combine

// MARK: - 14 nov · IL MIRINO DELLE MANI
// Quando JARVIS preme un tasto o scrive in un campo da solo (strumento «mano»), sullo schermo si vede dove: il mirino olografico
// si stringe sul tasto (0,22 s), lo aggancia con gli angoli e sfuma. Serve a capire cosa sta facendo lui, non è un ornamento.

@MainActor
final class Mirino: ObservableObject {
    static let condiviso = Mirino()
    /// Il tasto (coordinate dello schermo) e quando JARVIS l'ha puntato.
    @Published private(set) var bersaglio: (cornice: CGRect, quando: Date)?
    private var spegni: Task<Void, Never>?

    func punta(_ cornice: CGRect) {
        guard cornice.width > 0, cornice.height > 0 else { return }
        bersaglio = (cornice, Date())
        spegni?.cancel()
        spegni = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.bersaglio = nil
        }
    }
}

/// Lo strato del mirino, sopra tutto (ContentView). Non prende tocchi.
struct StratoMirino: View {
    @ObservedObject private var mirino = Mirino.condiviso

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let b = mirino.bersaglio {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSince(b.quando)
                    Canvas(rendersAsynchronously: false) { gc, _ in
                        StratoMirino.disegna(&gc, b.cornice, t: t)
                    }
                }
                .id(b.quando)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func disegna(_ gc: inout GraphicsContext, _ r0: CGRect, t: Double) {
        let presa = Olo.liscia(t / 0.22)                                   // il mirino si stringe sul tasto
        let via = t < 0.55 ? 1 : max(0, 1 - (t - 0.55) / 0.3)              // poi sfuma
        guard via > 0.01 else { return }
        let largo = 1 + 0.6 * (1 - presa)
        let r = CGRect(x: r0.midX - r0.width * largo / 2 - 4, y: r0.midY - r0.height * largo / 2 - 4,
                       width: r0.width * largo + 8, height: r0.height * largo + 8)
        gc.opacity = via
        gc.blendMode = .plusLighter
        // l'alone e il riquadro sottile
        gc.fill(Path(roundedRect: r, cornerRadius: min(12, r.height / 2)), with: .color(Olo.azzurro.opacity(0.10 * presa)))
        gc.stroke(Path(roundedRect: r, cornerRadius: min(12, r.height / 2)), with: .color(Olo.ciano.opacity(0.45)), lineWidth: 1)
        // gli angoli che agganciano
        let k = min(10, min(r.width, r.height) * 0.35)
        var ang = Path()
        let angoli: [(x: CGFloat, y: CGFloat, sx: CGFloat, sy: CGFloat)] = [(x: r.minX, y: r.minY, sx: 1, sy: 1), (x: r.maxX, y: r.minY, sx: -1, sy: 1),
                                                                            (x: r.minX, y: r.maxY, sx: 1, sy: -1), (x: r.maxX, y: r.maxY, sx: -1, sy: -1)]
        for (x, y, sx, sy) in angoli {
            ang.move(to: CGPoint(x: x + sx * k, y: y)); ang.addLine(to: CGPoint(x: x, y: y)); ang.addLine(to: CGPoint(x: x, y: y + sy * k))
        }
        gc.stroke(ang, with: .color(Olo.bianco.opacity(0.95)), style: Olo.tratto(1.6))
        // il colpo: un anello che si allarga una volta, quando aggancia
        if t > 0.2 {
            let u = min(1, (t - 0.2) / 0.35)
            let c = CGPoint(x: r0.midX, y: r0.midY)
            let raggio = 6 + u * max(r0.width, r0.height) * 0.6
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - raggio, y: c.y - raggio, width: raggio * 2, height: raggio * 2)),
                      with: .color(Olo.ciano.opacity(0.6 * (1 - u))), lineWidth: 1.2)
        }
    }
}
#endif
