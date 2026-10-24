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
    private let silenzioFine: Double = 0.9
    /// Tetto: una domanda non dura più di così.
    private let massimo: Double = 30
    /// Se non dice niente entro questo tempo, si chiude (7 secondi; dopo «aspetta» meno, vedi `azzera(attesa:)`).
    private var attesaMassima: Double = 7

    /// Chiamato una volta sola (dal thread audio) quando la frase è finita.
    var quandoFinito: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }

    var haParlato: Bool { lock.lock(); defer { lock.unlock() }; return parlato }

    /// `attesa`: quanto aspettare che cominci a parlare. Di solito 7 secondi; dopo «aspetta» meno, perché il silenzio dei
    /// 5 secondi decisi dal signore (24 ott) conta da quando ha smesso di parlare, e la frase è già stata chiusa e trascritta.
    func azzera(attesa: Double = 7) {
        lock.lock()
        campioni.removeAll(keepingCapacity: true)
        durata = 0; fondo = 0.004; voceDi = 0; parlato = false; ultimaVoce = 0; avvisato = false; piccoVoce = 0
        attesaMassima = attesa
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
        // dritto al cervello (già sveglio) che la passa a ElevenLabs: mezzo secondo invece di 7-8
        guard !token.isEmpty, let u = URL(string: indirizzo) else { return (nil, "Manca la parola d'ordine nelle impostazioni, Sir.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["trascrivi": audio.base64EncodedString()])
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return (nil, "Non raggiungo le mie orecchie in cloud, Sir.") }
        let codice = (r as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        if codice == 200 { return ((json?["testo"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), nil) }
        if codice == 401 { return (nil, "La parola d'ordine non coincide, Sir.") }
        return (nil, "Non ho capito, Sir. Riprovi.")
    }
}

/// Difetto 2 (controllo del 25 ott): sul Mac il microfono resta acceso mentre JARVIS parla, senza cancellazione dell'eco (che
/// abbasserebbe le altre app). Qui si tiene quanto forte esce in questo momento la voce di JARVIS, per capire se un pezzo
/// sentito dal microfono mentre parla è soltanto la sua eco (allora non va in cloud) o se dentro c'è anche il signore.
/// Il rapporto tra il microfono e la voce che esce, quando è solo eco, lo impara dalle frasi trascritte che sono risultate
/// tutta eco (`impara`): finché non ne ha viste almeno tre, ogni pezzo va in cloud come prima. Nel dubbio si trascrive sempre:
/// una sua parola («basta») non si perde mai per questo controllo.
nonisolated final class EcoMac: @unchecked Sendable {
    static let condivisa = EcoMac()
    private let lock = NSLock()
    private var parla = false
    private var codaFino: TimeInterval = 0               // dopo l'ultima frase la sua voce rimbomba ancora un attimo
    private var uscite: [(t: TimeInterval, rms: Float)] = []   // il volume della voce di JARVIS nell'ultimo secondo
    private var k: Float                                 // il rapporto più alto microfono/voce visto quando era tutta eco
    private var campioni: Int

    private init() {
        k = Float(UserDefaults.standard.double(forKey: "ecoMacSoglia"))
        campioni = UserDefaults.standard.integer(forKey: "ecoMacCampioni")
    }

    private static var ora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// JARVIS comincia o smette di parlare (dal cambio di fase).
    func jarvisParla(_ p: Bool) {
        lock.lock()
        if parla && !p { codaFino = EcoMac.ora + 0.8 }
        parla = p
        lock.unlock()
    }

    /// Un pezzo della voce di JARVIS mentre esce dal motore dello streaming.
    func misura(_ b: AVAudioPCMBuffer) {
        guard let canale = b.floatChannelData?[0], b.frameLength > 0 else { return }
        let n = Int(b.frameLength)
        var somma: Float = 0
        for i in 0..<n { somma += canale[i] * canale[i] }
        uscita((somma / Float(n)).squareRoot())
    }

    /// Il volume (rms, 0…1) della voce di JARVIS adesso.
    func uscita(_ rms: Float) {
        let t = EcoMac.ora
        lock.lock()
        uscite.append((t, rms))
        while let p = uscite.first, t - p.t > 1 { uscite.removeFirst() }
        lock.unlock()
    }

    /// Una frase di JARVIS dalla cache o mp3 (AVAudioPlayer): il suo volume, ogni 40 ms, finché suona.
    @MainActor static func segui(_ p: AVAudioPlayer) {
        p.isMeteringEnabled = true
        Task { @MainActor [weak p] in
            var suonato = false
            for _ in 0..<4000 {
                guard let p else { break }
                if p.isPlaying {
                    suonato = true
                    p.updateMeters()
                    let db = Double(p.averagePower(forChannel: 0))
                    EcoMac.condivisa.uscita(db <= -120 ? 0 : Float(pow(10.0, db / 20.0)))
                } else if suonato { break }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    /// `attiva`: JARVIS sta parlando (o ha appena smesso). `rif`: la sua voce più forte negli ultimi 0,3 s (il ritardo
    /// dell'altoparlante e il rimbombo); nil se in questo momento la voce che esce non si conosce (silenzio fra due frasi,
    /// oppure la voce dell'iPhone, che non dice quanto è forte).
    func riferimento() -> (attiva: Bool, rif: Float?) {
        let t = EcoMac.ora
        lock.lock(); defer { lock.unlock() }
        let attiva = parla || t < codaFino
        var m: Float = 0
        for u in uscite where t - u.t <= 0.3 { m = max(m, u.rms) }
        return (attiva, m > 0.0005 ? m : nil)
    }

    /// Il rapporto microfono/voce oltre il quale c'è anche il signore (nil: non ancora imparato, si trascrive tutto).
    var soglia: Float? { lock.lock(); defer { lock.unlock() }; return campioni >= 3 && k > 0 ? k * 1.5 : nil }

    /// Una frase trascritta che era tutta eco: il suo rapporto più alto alza (o tiene) la soglia. Cala piano (3% a frase), così
    /// se il volume del Mac scende la soglia lo segue; se sale, le frasi passano in cloud e la soglia si rialza da sola.
    func impara(_ rapporto: Float) {
        guard rapporto.isFinite, rapporto > 0 else { return }
        lock.lock()
        k = campioni == 0 ? rapporto : max(rapporto, k * 0.97)
        campioni += 1
        let soglia = k, quanti = campioni
        lock.unlock()
        UserDefaults.standard.set(Double(soglia), forKey: "ecoMacSoglia")
        UserDefaults.standard.set(quanti, forKey: "ecoMacCampioni")
    }
}

/// Com'era un pezzo sentito dal microfono dell'attesa, rispetto alla voce di JARVIS (difetto 2).
nonisolated struct EcoPezzo: Sendable {
    /// Sentito tutto mentre JARVIS parlava, con la sua voce sempre nota: se in cloud torna tutta eco, insegna la soglia.
    var candidato = false
    /// Solo la sua eco (soglia imparata e nessun pezzo più forte): non si trascrive.
    var soloEco = false
    /// Il rapporto più alto fra il microfono e la voce di JARVIS.
    var rapporto: Float = 0
    /// Quando il signore ha smesso di parlare (l'ultimo pezzo di voce).
    var fine = Date()
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
    private var ultimoLivello: Float = 0
    private var ultimoBuffer = Date()
    /// Da quanti secondi il microfono non manda audio (se il motore «gira» ma è muto, va riacceso).
    var secondiSenzaAudio: Double { lock.lock(); defer { lock.unlock() }; return Date().timeIntervalSince(ultimoBuffer) }
    /// Il livello del microfono adesso e quello del silenzio (per la riga di controllo sullo schermo del Mac).
    var livelli: (voce: Float, fondo: Float, parla: Bool) { lock.lock(); defer { lock.unlock() }; return (ultimoLivello, fondo, inVoce) }
    private var avviso: (@Sendable (Data, Date, EcoPezzo) -> Void)?
    // difetto 2: il pezzo in corso rispetto alla voce di JARVIS
    private var segDurante = false        // finora sentito tutto mentre JARVIS parlava
    private var segIncerti: Double = 0    // secondi di voce forte mentre JARVIS taceva o la sua voce non si conosceva
    private var segRapporto: Float = 0
    private var segSopra: Double = 0      // secondi in cui il microfono era più forte dell'eco: c'è il signore
    private var segDopoSopra: Double = 0  // secondi tornati al livello dell'eco dopo il signore
    private var segFineVoce = Date()

    var quandoFrase: (@Sendable (Data, Date, EcoPezzo) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }
    private var avvisoInizio: (@Sendable () -> Void)?
    /// Difetto 5 (25 ott): qualcuno ha cominciato a parlare (chiamato dal thread audio): il GPS si può svegliare già adesso.
    var quandoComincia: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avvisoInizio }
        set { lock.lock(); avvisoInizio = newValue; lock.unlock() }
    }

    func azzera() {
        lock.lock()
        fondo = 0.004; inVoce = false; voceDi = 0; silenzioDi = 0; durata = 0; prima.removeAll(); campioni.removeAll()
        ultimoBuffer = Date()
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
        var cominciata = false
        let eco = EcoMac.condivisa.riferimento()          // fuori dal lucchetto: EcoMac ha il suo
        let sogliaEco = EcoMac.condivisa.soglia
        var info = EcoPezzo()
        lock.lock()
        ultimoLivello = energia
        ultimoBuffer = Date()
        let soglia = max(fondo * 3, 0.006)          // il microfono del Mac è più basso di quello dell'iPhone
        if !inVoce {
            prima.append(contentsOf: pezzo)
            if prima.count > 6_400 { prima.removeFirst(prima.count - 6_400) }
            if energia > soglia {
                voceDi += secondi
                if voceDi >= 0.15 {
                    inVoce = true; campioni = prima; durata = voceDi; silenzioDi = 0; inizio = Date().addingTimeInterval(-voceDi); cominciata = true
                    segDurante = true; segIncerti = 0; segRapporto = 0; segSopra = 0; segDopoSopra = 0; segFineVoce = Date()
                    segnaEco(eco, sogliaEco, energia: energia, soglia: soglia, secondi: secondi)
                }
            } else {
                voceDi = 0
                fondo = fondo * 0.95 + energia * 0.05
            }
        } else {
            campioni.append(contentsOf: pezzo)
            durata += secondi
            silenzioDi = energia > soglia ? 0 : silenzioDi + secondi
            if energia > soglia { segFineVoce = Date() }
            segnaEco(eco, sogliaEco, energia: energia, soglia: soglia, secondi: secondi)
            // difetto 2: mentre JARVIS parla senza pause, la frase del signore («basta») si chiude appena il microfono torna al
            // livello della sola eco per mezzo secondo, invece di aspettare una pausa della voce di JARVIS (anche 10 secondi)
            let finitoSopraEco = segDurante && sogliaEco != nil && segSopra >= 0.1 && segDopoSopra >= 0.5
            if durata >= 10 && silenzioDi < 0.3 && !segDurante {
                // 10 secondi senza una pausa: non è una frase, è un rumore continuo (ventola, condizionatore). Si butta
                // e il livello del silenzio sale fin lì, così non continua a mandare rumore in cloud.
                // Difetto 2: non mentre JARVIS parla (lì è la sua voce, e dentro può esserci un «basta» del signore)
                fondo = max(fondo, energia / 3)
                inVoce = false; voceDi = 0; silenzioDi = 0; durata = 0; prima.removeAll(); campioni.removeAll()
            } else if silenzioDi >= 0.7 || durata >= 10 || finitoSopraEco {
                if durata - silenzioDi >= 0.5 {                            // un colpo o un «bip» non sono una frase
                    pronta = campioni
                    info.candidato = segDurante && segIncerti < 0.1
                    info.soloEco = info.candidato && sogliaEco != nil && segSopra < 0.1
                    info.rapporto = segRapporto
                    info.fine = segFineVoce
                }
                inVoce = false; voceDi = 0; silenzioDi = 0; durata = 0; prima.removeAll(); campioni.removeAll()
            }
        }
        let chiama = pronta != nil ? avviso : nil
        let quando = inizio
        let comincia = cominciata ? avvisoInizio : nil
        lock.unlock()
        comincia?()
        if let pronta, let chiama { chiama(RegistratoreVoce.creaWAV(pronta, hz: 16_000), quando, info) }
    }

    /// Difetto 2: un pezzo di microfono dentro la frase, rispetto alla voce di JARVIS che esce adesso (sotto il lucchetto).
    private func segnaEco(_ eco: (attiva: Bool, rif: Float?), _ sogliaEco: Float?, energia: Float, soglia: Float, secondi: Double) {
        guard eco.attiva else { segDurante = false; return }
        guard let rif = eco.rif else {
            if energia > soglia { segIncerti += secondi }          // voce mentre JARVIS tace fra due frasi: probabilmente lui
            return
        }
        let r = energia / max(rif, 0.0001)
        segRapporto = max(segRapporto, r)
        if let k = sogliaEco, r > k { segSopra += secondi; segDopoSopra = 0 } else if segSopra > 0 { segDopoSopra += secondi }
    }
}

/// Sul Mac, al posto del richiamo di Apple (che lì spesso non parte, e con lui i battiti di mani):
/// un solo microfono acceso in attesa che sente i due battiti (tutto locale) e manda alle orecchie in cloud
/// le frasi dette nella stanza. Chi lo usa decide cosa farne: «Jarvis, …», la frase di Tony, o il seguito subito dopo una risposta.
/// Freno: al massimo 20 frasi ogni 10 minuti, e niente con folla, musica o TV intorno (i battiti restano).
@MainActor
final class AttesaMac {
    var applauso: (() -> Void)?
    /// Idea D (25 ott): prende la frase per mandarla al cervello come audio insieme alla richiesta della risposta (un giro solo).
    /// Vero: presa; allora chiama l'ultimo argomento quando la frase è passata, e solo dopo parte quella che aspettava.
    var giroUnico: ((Data, Date, EcoPezzo, @escaping () -> Void) -> Bool)?
    /// Acceso (voluto): il Mac sta ascoltando la stanza.
    var inAscolto: Bool { voluto }
    /// Il testo trascritto, il momento in cui il signore ha cominciato a dirlo e quello in cui ha smesso.
    /// Restituisce vero se era solo l'eco di JARVIS.
    var frase: ((String, Date, Date) -> Bool)?
    private let motore: AVAudioEngine          // lo stesso motore dell'ascolto (sul Mac funziona già quello: niente secondo motore)
    private let mani = BattitoMani()
    private let segmenti = Segmentatore()
    private var errore = ""                    // perché il microfono non è partito (si vede nella riga di controllo)
    private var mio = false                    // il motore in questo momento lo sta usando l'attesa

    init(motore: AVAudioEngine) { self.motore = motore }
    private var voluto = false
    private var acceso = false
    private var inViaggio = false
    private var inCoda: (Data, Date, EcoPezzo)?   // una frase arrivata mentre la precedente era in viaggio: si manda subito dopo
    private var invii: [Date] = []
    private var osservatore: NSObjectProtocol?
    private var riprova: Task<Void, Never>?
    private var controllo: Task<Void, Never>?
    private var frasiMandate = 0
    private var ultimaSentita = ""
    /// Una riga che dice cosa sta succedendo (microfono, livello, ultima frase sentita): si vede sotto il reattore sul Mac.
    var diagnosi: ((String) -> Void)?

    /// Acceso e con il microfono che gira davvero.
    var attivo: Bool { voluto && acceso && motore.isRunning }

    func avvia() {
        voluto = true
        accendi()
    }

    /// Battiti di mani sentiti dal microfono dell'attesa (per la riga di controllo).
    func segnaBattiti() { ultimaSentita = "👏👏" }

    func ferma() {
        voluto = false
        riprova?.cancel()
        spegni()
        inCoda = nil
        diagnosi?("")
    }

    private func aggiornaDiagnosi() {
        controllo?.cancel()
        controllo = Task { [weak self] in
            while let self, !Task.isCancelled, self.voluto {
                let l = self.segmenti.livelli
                let mic = self.attivo ? (l.parla ? "◉ sento" : "● in ascolto") : "○ microfono spento" + (self.errore.isEmpty ? "" : " (\(self.errore.prefix(60)))")
                var riga = "\(mic) · livello \(Int(l.voce * 1000)) / silenzio \(Int(l.fondo * 1000)) · frasi \(self.frasiMandate)"
                if !self.ultimaSentita.isEmpty { riga += " · «\(self.ultimaSentita.prefix(40))»" }
                self.diagnosi?(riga)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func accendi() {
        guard voluto, !(acceso && motore.isRunning) else { return }
        spegni()
        aggiornaDiagnosi()
        guard AVAudioApplication.shared.recordPermission != .denied else { diagnosi?("○ microfono non permesso: Impostazioni di Sistema › Privacy › Microfono"); return }
        mani.minimoPicco = 0.04                    // sul Mac il battito arriva più piano
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
            segmenti.quandoFrase = { [weak self] audio, inizio, eco in
                Task { @MainActor [weak self] in self?.trascrivi(audio, inizio, eco) }
            }
            // difetto 5 (25 ott): la frase comincia, il GPS si sveglia mentre il signore parla (la domanda non lo aspetta)
            segmenti.quandoComincia = { Task { @MainActor in Posizione.scalda() } }
            mani.azzera()
            segmenti.azzera()
            if motore.isRunning { motore.stop() }   // qui si arriva solo in attesa: l'ascolto vero è già chiuso
            motore.reset()                          // riparte pulito dopo la voce di JARVIS o i Clash
            mio = true
            try AttesaMac.collega(motore, mani, segmenti)
            motore.prepare()
            try motore.start()
            acceso = true
            errore = ""
            sorveglia()
        } catch {
            errore = error.localizedDescription
            spegni()
            riaccendiFraPoco()
        }
    }

    /// Spegne il microfono solo se in questo momento è dell'attesa: il motore è condiviso con l'ascolto vero e proprio.
    private func spegni() {
        if let o = osservatore { NotificationCenter.default.removeObserver(o); osservatore = nil }
        guard mio else { acceso = false; return }
        mio = false
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        acceso = false
    }

    /// Ogni 3 secondi: se il microfono si è fermato da solo (cuffie collegate, microfono cambiato) lo riaccende.
    private func sorveglia() {
        riprova?.cancel()
        riprova = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !Task.isCancelled, self.voluto else { return }
                if !self.motore.isRunning || self.segmenti.secondiSenzaAudio > 2 {
                    self.errore = "il microfono si era fermato, lo riaccendo"
                    self.spegni()
                    self.acceso = false
                    self.accendi()
                    return
                }
            }
        }
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

    private func trascrivi(_ audio: Data, _ inizio: Date, _ eco: EcoPezzo) {
        guard voluto else { return }   // anche con musica o TV intorno: lì però vale solo «Jarvis, …» (lo decide chi riceve la frase)
        // difetto 2: sentito mentre JARVIS parlava e mai più forte della sua eco: è la sua voce, non va in cloud (né consuma il tetto)
        if eco.soloEco { return }
        if inViaggio { inCoda = (audio, inizio, eco); return }   // non si perde: parte appena torna la precedente
        let adesso = Date()
        invii.removeAll { adesso.timeIntervalSince($0) > 600 }
        guard invii.count < 40 else { return }
        invii.append(adesso)
        inViaggio = true
        frasiMandate += 1
        // idea D: senza la voce di JARVIS in mezzo, la frase va al cervello insieme alla richiesta della risposta
        if !eco.candidato, let prendi = giroUnico, prendi(audio, inizio, eco, { [weak self] in self?.viaggioFinito() }) { return }
        Task { [weak self] in
            let (testo, errore) = await RegistratoreVoce.trascrivi(audio, token: Portachiavi.leggi(), indirizzo: Impostazioni.indirizzo)
            guard let self else { return }
            self.inViaggio = false
            self.ultimaSentita = testo.map { $0.isEmpty ? "(niente)" : $0 } ?? (errore ?? "errore")
            if self.voluto, let testo, !testo.isEmpty {
                let soloEco = self.frase?(testo, inizio, eco.fine) ?? false
                // difetto 2: un pezzo sentito tutto mentre JARVIS parlava ed era solo la sua eco non conta nel tetto delle 40
                // trascrizioni, e insegna quanto forte il microfono sente JARVIS (la prossima volta non va in cloud)
                if soloEco && eco.candidato {
                    EcoMac.condivisa.impara(eco.rapporto)
                    if let i = self.invii.lastIndex(of: adesso) { self.invii.remove(at: i) }
                }
            }
            if let coda = self.inCoda { self.inCoda = nil; self.trascrivi(coda.0, coda.1, coda.2) }
        }
    }

    /// Idea D: la frase del giro unico è passata: parte quella arrivata nel frattempo.
    private func viaggioFinito() {
        inViaggio = false
        if let coda = inCoda { inCoda = nil; trascrivi(coda.0, coda.1, coda.2) }
    }

    nonisolated private static func collega(_ motore: AVAudioEngine, _ mani: BattitoMani, _ segmenti: Segmentatore) throws {
        let input = motore.inputNode
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio valido."])
        }
        input.removeTap(onBus: 0)
        // niente «modalità chiamata»: con l'elaborazione vocale accesa il Mac abbassa l'audio di tutte le altre app
        // (Claude, Apple Music…) finché il microfono resta aperto
        try? input.setVoiceProcessingEnabled(false)
        let ambiente = AmbienteSonoro.condiviso.nuovaAnalisi(formato: formato)
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, quando in
            mani.analizza(buffer)
            segmenti.analizza(buffer)
            ambiente?.analizza(buffer, posizione: quando.sampleTime)
            RegistroMicrofono.condiviso.scrivi(buffer)
        }
    }
}
