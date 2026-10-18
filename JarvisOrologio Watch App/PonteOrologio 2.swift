import Foundation
import WatchConnectivity

/// Il ponte con l'iPhone: riceve la parola d'ordine (e l'indirizzo del cervello) senza doverli scrivere sull'orologio,
/// chiede le foto della galleria e parla con la Sentinella (allarmi, «Guarda ora», «Disattiva»).
@MainActor
final class PonteOrologio: NSObject {
    static let condiviso = PonteOrologio()

    private var attivazione: [CheckedContinuation<Void, Never>] = []

    func avvia() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Chiede la parola d'ordine all'iPhone. Vero se ne è arrivata una.
    /// `soloDiretta`: salta la consegna già ricevuta (serve quando quella si è rivelata vecchia).
    func chiediToken(soloDiretta: Bool = false) async -> Bool {
        guard WCSession.isSupported() else { return false }
        await attendiAttivazione()
        let s = WCSession.default
        // 1) quella che l'iPhone ha già lasciato in consegna
        if !soloDiretta, salva(s.receivedApplicationContext) { return true }
        // 2) domanda diretta (l'iPhone viene svegliato anche se l'app è chiusa)
        guard s.isReachable else { return false }
        let risposta: [String: String] = await withCheckedContinuation { c in
            // @Sendable: le risposte arrivano su una coda in background, non sul main actor
            s.sendMessage(["chiedi": "token"], replyHandler: { @Sendable r in
                c.resume(returning: PonteOrologio.soloTesti(r))
            }, errorHandler: { @Sendable _ in
                c.resume(returning: [:])
            })
        }
        return salva(risposta)
    }

    /// Chiede all'iPhone di cercare tra le foto del signore (le foto stanno sull'iPhone).
    /// Restituisce il testo per il cervello e le miniature da mostrare.
    func cercaFoto(_ input: [String: Any]) async -> (String, [Data]) {
        guard WCSession.isSupported() else { return (PonteOrologio.errore("orologio senza collegamento all'iPhone"), []) }
        await attendiAttivazione()
        let s = WCSession.default
        guard s.isReachable else { return (PonteOrologio.errore("iPhone non raggiungibile: le foto sono sull'iPhone, lo tenga vicino"), []) }
        let dati = (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8)
        let richiesta = String(decoding: dati, as: UTF8.self)
        return await withCheckedContinuation { (c: CheckedContinuation<(String, [Data]), Never>) in
            s.sendMessage(["foto": richiesta], replyHandler: { @Sendable r in
                c.resume(returning: (r["risultato"] as? String ?? "{}", r["miniature"] as? [Data] ?? []))
            }, errorHandler: { @Sendable e in
                c.resume(returning: (PonteOrologio.errore("l'iPhone non ha risposto: \(e.localizedDescription)"), []))
            })
        }
    }

    /// La risposta della Sentinella sull'iPhone.
    nonisolated struct RispostaSentinella: Sendable {
        let attiva: Bool
        let notte: Bool
        let soggetti: Int
        let foto: Data?
    }

    /// Parla con la Sentinella sull'iPhone: «guarda» (stato + ultimo fotogramma), «ferma», «stato». Nil se l'iPhone non risponde.
    func sentinella(_ comando: String) async -> RispostaSentinella? {
        guard WCSession.isSupported() else { return nil }
        await attendiAttivazione()
        let s = WCSession.default
        guard s.isReachable else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<RispostaSentinella?, Never>) in
            s.sendMessage(["sentinella": comando], replyHandler: { @Sendable r in
                c.resume(returning: RispostaSentinella(attiva: r["attiva"] as? Bool ?? false, notte: r["notte"] as? Bool ?? false,
                                                       soggetti: (r["bersagli"] as? NSNumber)?.intValue ?? 0, foto: r["foto"] as? Data))
            }, errorHandler: { @Sendable _ in
                c.resume(returning: nil)
            })
        }
    }

    /// Un messaggio della Sentinella arrivato dall'iPhone (allarme o cambio di stato).
    nonisolated static func smistaSentinella(_ d: [String: Any]) {
        guard let tipo = d["sentinella"] as? String else { return }
        SentinellaOrologio.arrivato(tipo: tipo, cosa: d["cosa"] as? String, foto: d["foto"] as? Data, attiva: d["attiva"] as? Bool)
    }

    nonisolated static func errore(_ testo: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: ["errore": testo])) ?? Data("{}".utf8)
        return String(decoding: d, as: UTF8.self)
    }

    /// Salva token e indirizzo se presenti. Vero se c'era un token.
    @discardableResult
    fileprivate func salva(_ d: [String: Any]) -> Bool {
        salva(PonteOrologio.soloTesti(d))
    }

    @discardableResult
    fileprivate func salva(_ d: [String: String]) -> Bool {
        if let indirizzo = d["indirizzo"], !indirizzo.isEmpty {
            UserDefaults.standard.set(indirizzo, forKey: "indirizzo")
        }
        if let bea = d["numeroBea"] { UserDefaults.standard.set(bea, forKey: "numeroBea") }
        guard let token = d["token"], !token.isEmpty else { return false }
        PortachiaviOrologio.salva(token)
        return true
    }

    private func attendiAttivazione() async {
        if WCSession.default.activationState == .activated { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            attivazione.append(c)
            // rete di sicurezza: non si resta appesi se l'attivazione non risponde
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.sbloccaAttese()
            }
        }
    }

    fileprivate func sbloccaAttese() {
        let attese = attivazione
        attivazione.removeAll()
        attese.forEach { $0.resume() }
    }

    nonisolated static func soloTesti(_ d: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in d { if let s = v as? String { out[k] = s } }
        return out
    }
}

extension PonteOrologio: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let consegna = PonteOrologio.soloTesti(session.receivedApplicationContext)
        Task { @MainActor in
            self.salva(consegna)
            self.sbloccaAttese()
        }
    }

    // la Sentinella sull'iPhone: allarmi (subito, oppure in coda se l'app dormiva) e cambi di stato
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        PonteOrologio.smistaSentinella(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        PonteOrologio.smistaSentinella(message)
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // un allarme in coda vecchio di oltre 10 minuti non suona più: resta solo come «ultimo allarme»
        if let t = userInfo["quando"] as? Double, Date().timeIntervalSince1970 - t > 600 {
            var vecchio = userInfo
            vecchio["sentinella"] = "vecchio"
            PonteOrologio.smistaSentinella(vecchio)
            return
        }
        PonteOrologio.smistaSentinella(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let consegna = PonteOrologio.soloTesti(applicationContext)
        Task { @MainActor in self.salva(consegna) }
    }
}
