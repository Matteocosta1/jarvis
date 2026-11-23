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
    /// 14 nov: l'ultima volta che il dito ha toccato lo schermo (l'iniziativa non parla mentre lui sta lavorando col dito).
    static var ultimoTocco = Date.distantPast

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
        w.addGestureRecognizer(TiraTendina())                      // 13.8 (4): la tendina PROTOCOLLI dalla testata di ogni sezione
    }
}

/// 13.8 (4) (il signore, 22 nov 22:34: «la tendina Protocolli voglio poterla chiamare in ogni momento e in ogni sezione»; scelta:
/// swipe giù dalla testata). Con una sezione davanti, il dito che parte dalla testata (la fascia subito sotto l'ora: icona, nome,
/// «Chiudi») e tira giù porta la tendina sopra la sezione, e la segue come sulla schermata di JARVIS. Lo scorrimento delle pagine
/// non cambia (si parte dalla testata, non dalla pagina); lo swipe dal bordo in alto resta di iOS (Centro notifiche).
@MainActor
enum TendinaOvunque {
    /// Una sezione è davanti e la tendina si può tirare (lo scrive ContentView).
    static var attiva = false
    /// Le schede davanti che si chiudono tirandole giù dalla loro barra (la mail proiettata): finché ce n'è una, il gesto è loro.
    /// (Revisione 13.8 (6): conta solo quella davanti; con la sua sezione dietro, nella PILA, la tendina si tira come sempre.)
    static var occupata: Set<UUID> = []
    /// L'altezza della fascia della testata, sotto il margine in alto (l'ora e l'isola).
    static let fascia: CGFloat = 76
    /// Il dito che tira (spostamento) e che lascia (spostamento, dove arriverebbe lanciato): li collega ContentView.
    static var segue: ((CGSize) -> Void)?
    static var lascia: ((CGSize, CGSize) -> Void)?
}

/// Il gesto della tendina dalla testata: un pan sulla finestra che non ferma nessun altro gesto e non cancella i tocchi.
private final class TiraTendina: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(muove(_:)))
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        maximumNumberOfTouches = 1
        delegate = self
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard TendinaOvunque.attiva, TendinaOvunque.occupata.isEmpty, let v = view else { return false }
        let t = translation(in: v), p = location(in: v)
        let partenza = CGPoint(x: p.x - t.x, y: p.y - t.y), alto = v.safeAreaInsets.top
        guard partenza.y >= alto - 4, partenza.y <= alto + TendinaOvunque.fascia else { return false }
        // revisione 13.8 (6): sulla tab FILO (in alto a destra, sopra la testata) il dito scorre le sue notifiche: lì non è la tendina
        let filo = Filo.condiviso
        if !filo.daParte, !filo.visti.isEmpty || filo.vuota, filo.rettScheda.insetBy(dx: -8, dy: -8).contains(partenza) { return false }
        return t.y > 0 && t.y > abs(t.x) * 1.2
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool { true }

    @objc private func muove(_ g: UIPanGestureRecognizer) {
        guard let v = view else { return }
        let t = g.translation(in: v), vel = g.velocity(in: v)
        let spostamento = CGSize(width: t.x, height: t.y)
        switch g.state {
        case .began, .changed:
            TendinaOvunque.segue?(spostamento)
        case .ended:
            TendinaOvunque.lascia?(spostamento, CGSize(width: t.x + vel.x * 0.25, height: t.y + vel.y * 0.25))
        case .cancelled, .failed:
            TendinaOvunque.lascia?(spostamento, spostamento)
        default:
            break
        }
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
        TocchiSchermo.ultimoTocco = Date()
        // 13.1: FILO sa dove si appoggia il dito (su di lui: a fuoco e fermo; fuori: in secondo piano)
        if let t = touches.first {
            Filo.condiviso.toccoSchermo(t.location(in: nil))
            Pagine.condivisa.toccoSchermo(t.location(in: nil))     // 13.7: fuori dalla tab PAGINE la rimpicciolisce
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        BattitoMani.ignora(per: Self.silenzio)
        TocchiSchermo.ultimoTocco = Date()
        if numberOfTouches <= touches.count {
            Filo.condiviso.ditoAlzato()
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        BattitoMani.ignora(per: Self.silenzio)
        Filo.condiviso.ditoAlzato()
        state = .failed
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool { true }
}
#endif
