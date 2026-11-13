#if os(iOS)
import UIKit

// MARK: - 26 ott sera: i tocchi sullo schermo non sono battiti di mani
// Il dito che batte sul vetro e la vibrazione che risponde al tasto arrivano al microfono come un colpo secco, uguale a un
// battito di mani: due tocchi di fila potevano far partire «Bentornato a casa». Un osservatore su ogni finestra dell'app
// vede ogni tocco (anche dentro le pagine web di Studio, Social e LiDAR) senza fermarlo né ritardarlo, e per un attimo
// il rilevatore dei battiti non conta niente.

@MainActor
enum TocchiSchermo {
    private static var osservatore: NSObjectProtocol?

    /// All'avvio dell'app: ogni finestra che diventa principale riceve l'osservatore (una volta sola).
    static func prepara() {
        guard osservatore == nil else { return }
        osservatore = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil, queue: .main) { n in
            guard let w = n.object as? UIWindow else { return }
            MainActor.assumeIsolated { aggancia(w) }
        }
    }

    private static func aggancia(_ w: UIWindow) {
        guard !(w.gestureRecognizers ?? []).contains(where: { $0 is OsservaTocchi }) else { return }
        w.addGestureRecognizer(OsservaTocchi())
    }
}

/// Non riconosce mai niente: guarda soltanto. Non cancella e non ritarda i tocchi, e lascia lavorare tutti gli altri gesti.
private final class OsservaTocchi: UIGestureRecognizer, UIGestureRecognizerDelegate {
    /// Il tocco sul vetro e, all'uscita del dito, la vibrazione del tasto.
    private static let silenzio: TimeInterval = 0.6

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        BattitoMani.ignora(per: Self.silenzio)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        BattitoMani.ignora(per: Self.silenzio)
        if numberOfTouches <= touches.count { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        BattitoMani.ignora(per: Self.silenzio)
        state = .failed
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool { true }
}
#endif
