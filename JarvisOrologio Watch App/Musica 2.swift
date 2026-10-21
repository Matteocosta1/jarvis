import Foundation
import ShazamKit
import AVFoundation

/// «Jarvis, che canzone è?»: riconoscimento con ShazamKit dal microfono. Vale per iPhone e Apple Watch (stesso file, due target).
/// Serve il servizio ShazamKit attivo sull'identificativo dell'app (developer.apple.com › Identifiers).
nonisolated enum Musica {

    nonisolated struct Brano: Sendable {
        let titolo: String
        let artista: String
        let album: String?
        let appleMusic: URL?
        let web: URL?
        let copertina: URL?
        let generi: [String]
    }

    nonisolated enum Esito: Sendable { case trovato(Brano), nessuno, errore(String) }

    static func riconosci(secondi: Double) async -> Esito {
        guard await AVAudioApplication.requestRecordPermission() else { return .errore("manca il permesso del microfono") }
        NotificationCenter.default.post(name: .jarvisMicServe, object: nil)        // l'attesa in ascolto lascia il microfono a Shazam
        defer { NotificationCenter.default.post(name: .jarvisMicLibero, object: nil) }
        // musica di altre app: la lasciamo suonare (mixWithOthers), così Shazam la sente
        let s = AVAudioSession.sharedInstance()
        #if os(iOS)
        try? s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        #else
        try? s.setCategory(.playAndRecord, mode: .default)
        #endif
        try? s.setActive(true)

        let sessione = SHManagedSession()
        let durata = min(max(secondi, 5), 20)
        let inizio = Date()
        // Rete di sicurezza: qualunque cosa succeda (Shazam che non risponde, prepare bloccato), entro durata+8 s si esce.
        let r: SHSession.Result? = await withCheckedContinuation { (c: CheckedContinuation<SHSession.Result?, Never>) in
            let una = UnaVolta()
            Task {
                await sessione.prepare()
                let scadenza = Task {
                    try? await Task.sleep(for: .seconds(durata))
                    if !Task.isCancelled { sessione.cancel() }
                }
                let esito = await sessione.result()
                scadenza.cancel()
                if una.prendi() { c.resume(returning: esito) }
            }
            Task {
                try? await Task.sleep(for: .seconds(durata + 8))
                if una.prendi() { sessione.cancel(); c.resume(returning: nil) }
            }
        }
        sessione.cancel()
        guard let r else { return .errore("Shazam non ha risposto in tempo: forse il servizio ShazamKit non è ancora attivo per questa app") }

        switch r {
        case .match(let m):
            guard let v = m.mediaItems.first else { return .nessuno }
            return .trovato(Brano(titolo: v.title ?? "senza titolo", artista: v.artist ?? "artista sconosciuto", album: v.subtitle,
                                  appleMusic: v.appleMusicURL, web: v.webURL, copertina: v.artworkURL, generi: v.genres))
        case .noMatch:
            return .nessuno
        case .error(let e, _):
            let ns = e as NSError
            if ns.domain == SHErrorDomain, ns.code == SHError.Code.matchAttemptFailed.rawValue { return .nessuno }
            // fermato dal nostro tempo massimo: semplicemente non l'ha riconosciuta
            if Date().timeIntervalSince(inizio) >= durata - 0.5 { return .nessuno }
            return .errore("\(e.localizedDescription) [\(ns.domain) \(ns.code)]")
        @unknown default:
            return .nessuno
        }
    }
}

/// Garantisce che la risposta venga data una volta sola (dal risultato o dal tempo massimo).
nonisolated final class UnaVolta: @unchecked Sendable {
    private let lock = NSLock()
    private var usata = false
    func prendi() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if usata { return false }
        usata = true
        return true
    }
}

extension Notification.Name {
    /// Qualcuno (Shazam) prende il microfono / lo restituisce: l'attesa in ascolto del Watch si fa da parte e poi riprende.
    static let jarvisMicServe = Notification.Name("jarvisMicServe")
    static let jarvisMicLibero = Notification.Name("jarvisMicLibero")
}
