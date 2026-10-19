import AVFoundation

/// Sul Mac (l'app dell'iPhone che gira sui chip Apple) il riconoscimento vocale di Apple è capriccioso: a volte non parte,
/// a volte non chiude mai la frase, a volte non manda il risultato. Lì JARVIS fa da sé, come l'orologio:
/// registra la frase, capisce da solo quando il signore ha finito (la voce scende al livello del silenzio per un attimo)
/// e la manda alle «orecchie in cloud» (la funzione jarvis-ascolto, la stessa dell'Apple Watch), che restituiscono il testo.
/// Gira sul thread audio: niente MainActor, tutto sotto lucchetto.
nonisolated final class RegistratoreVoce: @unchecked Sendable {
    private let lock = NSLock()
    private var campioni: [Float] = []          // alla frequenza del microfono; portati a 16 kHz solo alla fine
    private var frequenza: Double = 48_000
    private var durata: Double = 0              // secondi registrati
    private var fondo: Float = 0.004            // il rumore della stanza (media lenta, solo prima che parli)
    private var voceDi: Double = 0              // da quanto la voce è sopra il fondo (per non scambiare un colpo per una parola)
    private var parlato = false
    private var ultimaVoce: Double = 0
    private var avvisato = false
    private var avviso: (@Sendable () -> Void)?

    /// Silenzio dopo la voce che chiude la frase.
    private let silenzioFine: Double = 1.3
    /// Tetto: una domanda non dura più di così.
    private let massimo: Double = 30
    /// Se non dice niente entro questo tempo, si chiude.
    private let attesaMassima: Double = 7

    /// Chiamato una volta sola (dal thread audio) quando la frase è finita.
    var quandoFinito: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }

    var haParlato: Bool { lock.lock(); defer { lock.unlock() }; return parlato }

    func azzera() {
        lock.lock()
        campioni.removeAll(keepingCapacity: true)
        durata = 0; fondo = 0.004; voceDi = 0; parlato = false; ultimaVoce = 0; avvisato = false
        lock.unlock()
    }

    /// Chiamato per nome («Jarvis, …»): l'inizio della frase è già stato detto. Si parte dagli ultimi secondi già sentiti
    /// (a 16 kHz) e si considera che stia già parlando.
    func precarica(_ pezzo: [Float]) {
        guard !pezzo.isEmpty else { return }
        lock.lock()
        campioni = pezzo
        frequenza = 16_000
        durata = Double(pezzo.count) / 16_000
        parlato = true
        ultimaVoce = durata
        lock.unlock()
    }

    func analizza(_ b: AVAudioPCMBuffer) {
        guard let dati = b.floatChannelData?[0] else { return }
        let n = Int(b.frameLength), fr = b.format.sampleRate
        guard n > 0, fr > 0 else { return }
        var somma: Float = 0
        for k in 0..<n { somma += dati[k] * dati[k] }
        let energia = (somma / Float(n)).squareRoot()
        let secondi = Double(n) / fr

        lock.lock()
        if campioni.isEmpty || frequenza == fr {
            frequenza = fr
            campioni.append(contentsOf: UnsafeBufferPointer(start: dati, count: n))
        } else {
            // precaricato a 16 kHz: anche il resto va a 16 kHz, così il file è uno solo
            campioni.append(contentsOf: RegistroMicrofono.a16k(Array(UnsafeBufferPointer(start: dati, count: n)), da: fr))
        }
        durata += secondi
        let soglia = max(fondo * 3.5, 0.012)
        if energia > soglia, durata > 0.3 {                  // i primi istanti: il «bip» di JARVIS, non conta
            voceDi += secondi
            if voceDi >= 0.18 { parlato = true }
            if parlato { ultimaVoce = durata }
        } else {
            voceDi = 0
            if !parlato { fondo = fondo * 0.9 + energia * 0.1 }
        }
        let fine = (parlato && durata - ultimaVoce >= silenzioFine) || durata >= massimo || (!parlato && durata >= attesaMassima)
        var chiama: (@Sendable () -> Void)?
        if fine && !avvisato { avvisato = true; chiama = avviso }
        lock.unlock()
        chiama?()
    }

    /// La frase registrata, come file WAV a 16 kHz, mono, 16 bit (quello che le orecchie in cloud si aspettano).
    func wav() -> Data {
        lock.lock()
        let fr = frequenza
        let grezzi = campioni
        lock.unlock()
        let x = fr == 16_000 ? grezzi : RegistroMicrofono.a16k(grezzi, da: fr)
        var pcm = Data(capacity: x.count * 2)
        for v in x {
            let s = Int16(max(-1, min(1, v)) * 32_767)
            withUnsafeBytes(of: s.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func scrivi<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); scrivi(UInt32(36 + pcm.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); scrivi(UInt32(16)); scrivi(UInt16(1)); scrivi(UInt16(1))
        scrivi(UInt32(16_000)); scrivi(UInt32(32_000)); scrivi(UInt16(2)); scrivi(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); scrivi(UInt32(pcm.count))
        d.append(pcm)
        return d
    }

    /// Manda l'audio alle orecchie in cloud e restituisce il testo (o un messaggio d'errore da mostrare).
    static func trascrivi(_ audio: Data, token: String, indirizzo: String) async -> (testo: String?, errore: String?) {
        let base = indirizzo
        let url = base.hasSuffix("/jarvis") ? base + "-ascolto" : base.replacingOccurrences(of: "/jarvis", with: "/jarvis-ascolto")
        guard !token.isEmpty, let u = URL(string: url) else { return (nil, "Manca la parola d'ordine nelle impostazioni, Sir.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["audio": audio.base64EncodedString(), "formato": "wav"])
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return (nil, "Non raggiungo le mie orecchie in cloud, Sir.") }
        let codice = (r as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        if codice == 200 { return ((json?["testo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), nil) }
        if codice == 401 { return (nil, "La parola d'ordine non coincide, Sir.") }
        return (nil, "Non ho capito, Sir. Riprovi.")
    }
}
