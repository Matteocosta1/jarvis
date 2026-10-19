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
    private var piccoVoce: Float = 0            // la voce più forte sentita: la fine si misura anche rispetto a lei
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
        durata = 0; fondo = 0.004; voceDi = 0; parlato = false; ultimaVoce = 0; avvisato = false; piccoVoce = 0
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
        // il rumore della stanza: il pezzo più silenzioso (100 ms) di ciò che è già stato sentito; la voce: il più forte
        var minimo: Float = .greatestFiniteMagnitude, massimo: Float = 0
        var i = 0
        while i + 1_600 <= pezzo.count {
            var q: Float = 0
            for k in i..<(i + 1_600) { q += pezzo[k] * pezzo[k] }
            let e = (q / 1_600).squareRoot()
            minimo = min(minimo, e); massimo = max(massimo, e)
            i += 1_600
        }
        if minimo < .greatestFiniteMagnitude { fondo = max(0.002, minimo) }
        piccoVoce = massimo
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
        if parlato || durata > 0.4 {                         // i primi istanti (il «bip» di JARVIS) non contano per niente
            // è voce se supera il rumore della stanza e non è troppo più bassa della sua voce (musica o ventola sotto)
            if energia > soglia && energia > piccoVoce * 0.25 {
                voceDi += secondi
                if voceDi >= 0.18 { parlato = true }
                if parlato { ultimaVoce = durata; piccoVoce = max(piccoVoce, energia) }
            } else {
                voceDi = 0
                if !parlato && energia < soglia { fondo = fondo * 0.9 + energia * 0.1 }
            }
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
        let hz = UInt32(fr >= 16_000 ? 16_000 : fr)          // un microfono Bluetooth a 8 kHz resta a 8 kHz (a16k non lo alza)
        return RegistratoreVoce.creaWAV(x, hz: hz)
    }

    /// Campioni (−1…1) → file WAV mono a 16 bit.
    static func creaWAV(_ x: [Float], hz: UInt32) -> Data {
        var pcm = Data(capacity: x.count * 2)
        for v in x {
            let s = Int16(v.isFinite ? max(-1, min(1, v)) * 32_767 : 0)
            withUnsafeBytes(of: s.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func scrivi<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); scrivi(UInt32(36 + pcm.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); scrivi(UInt32(16)); scrivi(UInt16(1)); scrivi(UInt16(1))
        scrivi(hz); scrivi(hz * 2); scrivi(UInt16(2)); scrivi(UInt16(16))
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

/// Il Mac in attesa: le frasi dette nella stanza, una alla volta. Quando la voce parte e poi si ferma (0,8 s di silenzio)
/// consegna la frase come WAV a 16 kHz, con un attimo di audio prima (così la prima sillaba non si perde).
nonisolated final class Segmentatore: @unchecked Sendable {
    private let lock = NSLock()
    private var fondo: Float = 0.004
    private var inVoce = false
    private var voceDi: Double = 0
    private var silenzioDi: Double = 0
    private var durata: Double = 0
    private var prima: [Float] = []             // gli ultimi 0,4 s prima che parlasse
    private var campioni: [Float] = []
    private var inizio = Date.distantPast       // quando ha cominciato a parlare (per la finestra del seguito)
    private var avviso: (@Sendable (Data, Date) -> Void)?

    var quandoFrase: (@Sendable (Data, Date) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }

    func azzera() {
        lock.lock()
        fondo = 0.004; inVoce = false; voceDi = 0; silenzioDi = 0; durata = 0; prima.removeAll(); campioni.removeAll()
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
        let pezzo = RegistroMicrofono.a16k(Array(UnsafeBufferPointer(start: dati, count: n)), da: fr)
        var pronta: [Float]?
        lock.lock()
        let soglia = max(fondo * 3.5, 0.015)
        if !inVoce {
            prima.append(contentsOf: pezzo)
            if prima.count > 6_400 { prima.removeFirst(prima.count - 6_400) }
            if energia > soglia {
                voceDi += secondi
                if voceDi >= 0.15 { inVoce = true; campioni = prima; durata = voceDi; silenzioDi = 0; inizio = Date().addingTimeInterval(-voceDi) }
            } else {
                voceDi = 0
                fondo = fondo * 0.95 + energia * 0.05
            }
        } else {
            campioni.append(contentsOf: pezzo)
            durata += secondi
            silenzioDi = energia > soglia ? 0 : silenzioDi + secondi
            if durata >= 10 && silenzioDi < 0.3 {
                // 10 secondi senza una pausa: non è una frase, è un rumore continuo (ventola, condizionatore). Si butta
                // e il livello del silenzio sale fin lì, così non continua a mandare rumore in cloud
                fondo = max(fondo, energia / 3)
                inVoce = false; voceDi = 0; silenzioDi = 0; durata = 0; prima.removeAll(); campioni.removeAll()
            } else if silenzioDi >= 0.8 || durata >= 10 {
                if durata - silenzioDi >= 0.5 { pronta = campioni }      // un colpo o un «bip» non sono una frase
                inVoce = false; voceDi = 0; silenzioDi = 0; durata = 0; prima.removeAll(); campioni.removeAll()
            }
        }
        let chiama = pronta != nil ? avviso : nil
        let quando = inizio
        lock.unlock()
        if let pronta, let chiama { chiama(RegistratoreVoce.creaWAV(pronta, hz: 16_000), quando) }
    }
}

/// Sul Mac, al posto del richiamo di Apple (che lì spesso non parte, e con lui i battiti di mani):
/// un solo microfono acceso in attesa che sente i due battiti (tutto locale) e manda alle orecchie in cloud
/// le frasi dette nella stanza. Chi lo usa decide cosa farne: «Jarvis, …», la frase di Tony, o il seguito subito dopo una risposta.
/// Freno: al massimo 20 frasi ogni 10 minuti, e niente con folla, musica o TV intorno (i battiti restano).
@MainActor
final class AttesaMac {
    var applauso: (() -> Void)?
    /// Il testo trascritto e il momento in cui il signore ha cominciato a dirlo.
    var frase: ((String, Date) -> Void)?
    private let motore = AVAudioEngine()
    private let mani = BattitoMani()
    private let segmenti = Segmentatore()
    private var voluto = false
    private var acceso = false
    private var inViaggio = false
    private var inCoda: (Data, Date)?          // una frase arrivata mentre la precedente era in viaggio: si manda subito dopo
    private var invii: [Date] = []
    private var osservatore: NSObjectProtocol?
    private var riprova: Task<Void, Never>?

    /// Acceso e con il microfono che gira davvero.
    var attivo: Bool { voluto && acceso && motore.isRunning }

    func avvia() {
        voluto = true
        accendi()
    }

    func ferma() {
        voluto = false
        riprova?.cancel()
        spegni()
        inCoda = nil
    }

    private func accendi() {
        guard voluto, !(acceso && motore.isRunning) else { return }
        spegni()
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        do {
            let sessione = AVAudioSession.sharedInstance()
            do {
                try sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            } catch {
                try sessione.setCategory(.playAndRecord, options: [.mixWithOthers])
            }
            try sessione.setActive(true)
            mani.quandoSente = { [weak self] in
                Task { @MainActor [weak self] in self?.applauso?() }
            }
            segmenti.quandoFrase = { [weak self] audio, inizio in
                Task { @MainActor [weak self] in self?.trascrivi(audio, inizio) }
            }
            mani.azzera()
            segmenti.azzera()
            try AttesaMac.collega(motore, mani, segmenti)
            motore.prepare()
            try motore.start()
            acceso = true
            // cuffie collegate, microfono cambiato: il motore si ferma da solo; qui si riaccende
            osservatore = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: motore, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.riaccendiFraPoco() }
            }
        } catch {
            spegni()
            riaccendiFraPoco()
        }
    }

    private func spegni() {
        if let o = osservatore { NotificationCenter.default.removeObserver(o); osservatore = nil }
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        acceso = false
    }

    private func riaccendiFraPoco() {
        riprova?.cancel()
        guard voluto else { return }
        riprova = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled, self.voluto else { return }
            self.acceso = false
            self.accendi()
        }
    }

    private func trascrivi(_ audio: Data, _ inizio: Date) {
        guard voluto, !AmbienteSonoro.condiviso.affollato else { return }
        if inViaggio { inCoda = (audio, inizio); return }        // non si perde: parte appena torna la precedente
        let adesso = Date()
        invii.removeAll { adesso.timeIntervalSince($0) > 600 }
        guard invii.count < 30 else { return }
        invii.append(adesso)
        inViaggio = true
        Task { [weak self] in
            let (testo, _) = await RegistratoreVoce.trascrivi(audio, token: Portachiavi.leggi(), indirizzo: Impostazioni.indirizzo)
            guard let self else { return }
            self.inViaggio = false
            if self.voluto, let testo, !testo.isEmpty { self.frase?(testo, inizio) }
            if let coda = self.inCoda { self.inCoda = nil; self.trascrivi(coda.0, coda.1) }
        }
    }

    nonisolated private static func collega(_ motore: AVAudioEngine, _ mani: BattitoMani, _ segmenti: Segmentatore) throws {
        let input = motore.inputNode
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio valido."])
        }
        input.removeTap(onBus: 0)
        let ambiente = AmbienteSonoro.condiviso.nuovaAnalisi(formato: formato)
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, quando in
            mani.analizza(buffer)
            segmenti.analizza(buffer)
            ambiente?.analizza(buffer, posizione: quando.sampleTime)
            RegistroMicrofono.condiviso.scrivi(buffer)
        }
    }
}
