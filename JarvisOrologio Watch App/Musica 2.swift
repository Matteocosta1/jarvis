import Foundation
import ShazamKit
import AVFoundation

/// «Jarvis, che canzone è?»: riconoscimento con ShazamKit dal microfono. Vale per iPhone e Apple Watch (stesso file, due target).
/// Serve il servizio ShazamKit attivo sull'identificativo dell'app (developer.apple.com › Identifiers).
/// Questa è la copia dell'orologio (target JarvisOrologio): dal 24 ott ha in più la fermata immediata (decisione 38c) e
/// `inAscolto` (decisione 37); quella dell'iPhone (Untitled Project/Musica 2.swift) è rimasta com'era.
nonisolated enum Musica {

    /// Decisione 37 (24 ott): Shazam sta ascoltando (dentro una risposta o dalla scheda SHAZAM). Intanto i suoni del polso
    /// non cambiano la sessione audio: con `.ambient` il microfono di Shazam smetteva di sentire (per esempio «schedapronta»
    /// della scheda SHAZAM, 0,9 s dopo l'apertura, mentre Shazam stava già ascoltando).
    static var inAscolto: Bool { ascolti.attivi }
    private static let ascolti = ContaAscolti()

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
        guard !Task.isCancelled else { return .nessuno }      // fermato prima di cominciare: il microfono non si apre
        ascolti.entra()
        defer { ascolti.esce() }
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
        let attesa = AttesaShazam()
        // Rete di sicurezza: qualunque cosa succeda (Shazam che non risponde, prepare bloccato), entro durata+8 s si esce.
        // Decisione 38c (24 ott): un tocco sul reattore (o «Stop», o una telefonata) annulla il compito che aspetta Shazam:
        // prima l'annullamento non arrivava fin qui e il microfono di Shazam restava acceso fino a 15 s sopra l'ascolto nuovo.
        // Ora `onCancel` chiude subito l'attesa e ferma Shazam (`cancel()`, già chiamato da altri compiti qui sotto).
        let r: SHSession.Result? = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<SHSession.Result?, Never>) in
                attesa.aspetta(c)
                Task {
                    await sessione.prepare()
                    guard !attesa.chiusa else { sessione.cancel(); return }   // fermato mentre si preparava: niente ascolto
                    let scadenza = Task {
                        try? await Task.sleep(for: .seconds(durata))
                        if !Task.isCancelled { sessione.cancel() }
                    }
                    let esito = await sessione.result()
                    scadenza.cancel()
                    attesa.chiudi(esito)
                }
                Task {
                    try? await Task.sleep(for: .seconds(durata + 8))
                    if !attesa.chiusa { sessione.cancel() }
                    attesa.chiudi(nil)
                }
            }
        } onCancel: {
            attesa.chiudi(nil)                                    // si esce subito
            sessione.cancel()                                     // e il microfono di Shazam si chiude
        }
        sessione.cancel()
        if Task.isCancelled { return .nessuno }                   // fermato dal signore: non è un errore, nessuno lo legge
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

/// Decisione 38c: l'attesa del risultato di Shazam, chiusa una volta sola: dal risultato, dal tempo massimo o dal tocco del
/// signore (l'annullamento del compito). Se si chiude prima che la continuazione arrivi, la continuazione esce subito.
nonisolated final class AttesaShazam: @unchecked Sendable {
    private let lock = NSLock()
    private var c: CheckedContinuation<SHSession.Result?, Never>?
    private var fatta = false
    var chiusa: Bool { lock.lock(); defer { lock.unlock() }; return fatta }
    func aspetta(_ nuova: CheckedContinuation<SHSession.Result?, Never>) {
        lock.lock()
        if fatta { lock.unlock(); nuova.resume(returning: nil); return }
        c = nuova
        lock.unlock()
    }
    func chiudi(_ r: SHSession.Result?) {
        lock.lock()
        guard !fatta else { lock.unlock(); return }
        fatta = true
        let k = c
        c = nil
        lock.unlock()
        k?.resume(returning: r)
    }
}

/// Decisione 37: quanti riconoscimenti di Shazam sono in corso (di solito zero o uno).
nonisolated final class ContaAscolti: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var attivi: Bool { lock.lock(); defer { lock.unlock() }; return n > 0 }
    func entra() { lock.lock(); n += 1; lock.unlock() }
    func esce() { lock.lock(); n = max(0, n - 1); lock.unlock() }
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
