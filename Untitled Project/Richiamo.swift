#if os(iOS)
import AVFoundation
import Speech

/// Il richiamo: quando JARVIS è in attesa e l'app è aperta, ascolta in silenzio e si sveglia solo sentendo «Jarvis».
/// «Jarvis, che tempo fa domani»: raccoglie la frase intera (stesse pause dell'ascolto normale) e la consegna.
/// Solo «Jarvis» e poi silenzio: JARVIS apre l'ascolto normale e aspetta la domanda.
/// Le altre voci, la musica, la TV vengono ignorate: senza «Jarvis» non succede nulla.
/// Il riconoscimento è sull'iPhone (niente rete, niente quota Apple) e riparte da solo ogni 50 secondi.
/// Il microfono resta sempre acceso: quando il riconoscimento riparte cambia solo il «trascrittore», senza buchi,
/// e gli ultimi istanti di audio vengono riletti dal nuovo, così nessuna parola cade nel passaggio.
@MainActor
final class Richiamo {
    /// Ha sentito «Jarvis»: suono e reattore in ascolto.
    var sveglia: (() -> Void)?
    /// La frase dopo «Jarvis» è finita (vuota se ha detto solo «Jarvis»).
    var consegna: ((String) -> Void)?
    /// La frase mentre la dice, per mostrarla sullo schermo.
    var testo: ((String) -> Void)?
    /// Due battiti di mani (come Tony Stark): JARVIS si mette in ascolto.
    var applauso: (() -> Void)?

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private let condotto = Condotto()
    private let mani = BattitoMani()
    private var ultimoAvvio = Date.distantPast
    private var compito: SFSpeechRecognitionTask?
    private var timerRiavvio: Timer?
    private var timerSilenzio: Timer?
    private var timerTetto: Timer?
    private var turno = 0
    private var voluto = false
    private var acceso = false
    private(set) var sveglio = false     // ha sentito «Jarvis»: sta raccogliendo la frase
    private var resto = ""
    /// Fino a quando basta parlare, senza «Jarvis»: subito dopo una richiesta il signore può aggiungere ancora qualcosa.
    var liberoFinoA = Date.distantPast
    private var precedente = ""         // l'ultima trascrizione ricevuta
    private var prima = ""              // ciò che ha già detto dopo il richiamo, prima che il riconoscimento ripartisse da capo
    private var soloDopoNome = true      // vero: conta ciò che segue «Jarvis»; falso: conta tutta la frase (seguito senza nome)
    private var corrente = ""
    private var voceConfermata = false     // in mezzo alla confusione: l'impronta ha riconosciuto il signore
    private var controlloInCorso = false
    private var inizioSegmento = 0       // da quale parola comincia l'ultima frase (dopo una pausa) nella trascrizione
    private var ultimeParole = 0
    private var ultimoParziale = Date.distantPast

    /// Il nome, anche come lo storpia il riconoscimento («Giarvis», «Jervis»…): vale in qualsiasi punto della frase.
    nonisolated static let nomi = ["jarvi", "giarvi", "giàrvi", "jervis", "charvis", "jarves", "jarbis"]
    /// Parole di richiamo che valgono solo a inizio frase (dopo una pausa): «ascoltami, …», «ehi, …», «bro, …», «fratello, …».
    nonisolated static let risposteBrevi: Set<String> = ["sì", "si", "no", "ok", "okay", "grazie", "perfetto", "certo", "esatto",
                                                         "bravo", "basta", "avanti", "pausa", "stop", "dimmi", "allora", "senti"]
    nonisolated static let aperture = ["ascoltami", "ascolta", "ehi", "hey", "ei", "bro", "fratello", "frate", "socio", "amico", "capo"]

    /// Se nella frase c'è un richiamo, restituisce ciò che viene dopo (anche vuoto); altrimenti nil.
    nonisolated static func dopoRichiamo(_ frase: String) -> String? {
        let basso = frase.lowercased()
        var migliore: Range<String.Index>?
        for n in nomi {
            if let r = basso.range(of: n, options: .backwards), migliore == nil || r.lowerBound > migliore!.lowerBound { migliore = r }
        }
        if let r = migliore {
            // fine della parola che contiene il nome («jarvis,» → dopo la virgola)
            var fine = r.upperBound
            while fine < basso.endIndex, basso[fine].isLetter { fine = basso.index(after: fine) }
            return String(basso[fine...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
        }
        let parole = basso.split(whereSeparator: { !$0.isLetter && $0 != "'" })
        if let prima = parole.first, aperture.contains(String(prima)) {
            let dopo = basso[prima.endIndex...]
            return String(dopo).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
        }
        return nil
    }

    var attivo: Bool { voluto }

    func avvia() {
        guard !voluto else { return }
        voluto = true
        accendi()
    }

    func ferma() {
        voluto = false
        spegni()
    }

    private func accendi() {
        guard voluto, !acceso, let riconoscitore, riconoscitore.isAvailable else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        do {
            if !motore.isRunning {
                let sessione = AVAudioSession.sharedInstance()
                // mixWithOthers: la musica di Spotify continua; A2DP: le cuffie restano in alta qualità
                do {
                    try sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
                } catch {
                    // sul Mac alcune opzioni dell'iPhone non valgono: si va sul semplice (tenendo la musica degli altri)
                    try sessione.setCategory(.playAndRecord, options: [.mixWithOthers])
                }
                try sessione.setActive(true)
                mani.quandoSente = { [weak self] in
                    guard let richiamo = self else { return }
                    Task { @MainActor in richiamo.applauso?() }
                }
                mani.azzera()
                try Richiamo.collega(motore, condotto, mani)
                motore.prepare()
                try motore.start()
            }
            azzera()
            nuovoRiconoscimento(riconoscitore, recentiDa: nil)
            programmaRiavvio()
        } catch {
            spegni()
            // microfono occupato (un'altra app, una chiamata): riprovo fra poco
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.accendi()
            }
        }
    }

    /// Un trascrittore nuovo sullo stesso microfono acceso. `recentiDa`: rilegge l'audio arrivato da quel momento.
    private func nuovoRiconoscimento(_ ric: SFSpeechRecognizer, recentiDa: Date?) {
        let vecchia = richiesta, vecchio = compito
        ultimoAvvio = Date()
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.addsPunctuation = true
        r.contextualStrings = ["Jarvis", "ascoltami", "ehi Jarvis", "hey Jarvis", "wake up", "daddy's home", "wake up daddy's home"]
        if ric.supportsOnDeviceRecognition, !ProcessInfo.processInfo.isiOSAppOnMac { r.requiresOnDeviceRecognition = true }   // sul Mac il motore locale non risponde (errore 1101): lì si usa quello di Apple
        richiesta = r
        turno += 1
        let mio = turno
        let condotto = condotto
        compito = Richiamo.riconosci(ric, r) { [weak self] testo, fine in
            if fine { condotto.segnaFine() }
            Task { @MainActor [weak self] in self?.valuta(testo, fine: fine, turno: mio) }
        }
        condotto.usa(r, recentiDa: recentiDa)       // prima il nuovo trascrittore, poi chiudo il vecchio: nessun buco
        vecchia?.endAudio()
        vecchio?.cancel()
        acceso = true
    }

    private func programmaRiavvio() {
        // Apple chiude ogni ascolto dopo circa un minuto: si riparte prima (ma non mentre il signore sta parlando)
        timerRiavvio?.invalidate()
        timerRiavvio = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.sveglio else { return }
                self.riavvia(recentiDa: Date().addingTimeInterval(-0.8))
            }
        }
    }

    private func azzera() {
        sveglio = false
        voceConfermata = false
        resto = ""
        inizioSegmento = 0
        ultimeParole = 0
        ultimoParziale = .distantPast
        precedente = ""
        prima = ""
        corrente = ""
        soloDopoNome = true
    }

    private func spegni() {
        timerRiavvio?.invalidate(); timerRiavvio = nil
        timerSilenzio?.invalidate(); timerSilenzio = nil
        timerTetto?.invalidate(); timerTetto = nil
        condotto.usa(nil, recentiDa: nil)
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil
        compito = nil
        acceso = false
        azzera()
    }

    /// Ricomincia la trascrizione senza spegnere il microfono.
    private func riavvia(recentiDa: Date? = nil) {
        guard voluto else { return }
        timerRiavvio?.invalidate(); timerRiavvio = nil
        timerSilenzio?.invalidate(); timerSilenzio = nil
        timerTetto?.invalidate(); timerTetto = nil
        guard motore.isRunning, let riconoscitore else {
            spegni()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.accendi()
            }
            return
        }
        // il riconoscimento si è chiuso appena partito (un errore): non riparto a raffica, aspetto un attimo
        if Date().timeIntervalSince(ultimoAvvio) < 0.5 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.voluto, !self.sveglio else { return }
                self.riavvia(recentiDa: recentiDa)
            }
            return
        }
        azzera()
        nuovoRiconoscimento(riconoscitore, recentiDa: recentiDa)
        programmaRiavvio()
    }

    /// Le parole di una trascrizione (la punteggiatura non conta).
    nonisolated static func contaParole(_ t: String) -> Int {
        t.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).count
    }

    /// La trascrizione a partire dalla parola numero `n` (0 = tutta). Conta le parole e non le lettere:
    /// il riconoscimento ritocca virgole e maiuscole del già detto, e un taglio a caratteri mangerebbe pezzi di parola.
    nonisolated static func dallaParola(_ n: Int, _ testo: String) -> String {
        guard n > 0 else { return testo }
        var conta = 0
        var dentro = false
        for i in testo.indices {
            let c = testo[i]
            let lettera = c.isLetter || c.isNumber || c == "'"
            if lettera && !dentro {
                if conta == n { return String(testo[i...]) }
                conta += 1
            }
            dentro = lettera
        }
        return ""
    }

    /// Il riconoscimento sull'iPhone, dopo una pausa, a volte ricomincia la trascrizione da capo invece di allungarla.
    /// Vero se il testo nuovo non è il seguito del precedente ma un pezzo nuovo.
    nonisolated static func pezzoNuovo(precedente: String, nuovo: String, pausa: TimeInterval) -> Bool {
        guard !precedente.isEmpty, !nuovo.isEmpty else { return false }
        let p = precedente.lowercased(), n = nuovo.lowercased()
        let k = min(4, p.count, n.count)
        let stessoInizio = p.prefix(k) == n.prefix(k)
        if n.count < p.count && !stessoInizio { return true }      // più corto e diverso: è ripartito
        if n.count * 2 < p.count { return true }                   // si è dimezzato: è ripartito
        return pausa > 0.8 && !stessoInizio                         // dopo una pausa, con un inizio diverso
    }

    private func valuta(_ testo: String?, fine: Bool, turno mio: Int) {
        guard acceso, mio == turno else { return }
        if let testo, !testo.isEmpty {
            let adesso = Date()
            let pausa = adesso.timeIntervalSince(ultimoParziale)
            let ripartito = Richiamo.pezzoNuovo(precedente: precedente, nuovo: testo, pausa: pausa)
            precedente = testo
            if !sveglio {
                // dopo una pausa comincia una frase nuova: i richiami «ascoltami», «ehi» valgono solo lì
                let parole = Richiamo.contaParole(testo)
                if ripartito { inizioSegmento = 0 }
                else if pausa > 1.0 { inizioSegmento = min(ultimeParole, parole) }
                ultimoParziale = adesso
                ultimeParole = parole
                let segmento = Richiamo.dallaParola(inizioSegmento, testo)
                var trovato = Richiamo.dopoRichiamo(segmento)
                soloDopoNome = true
                if trovato == nil {
                    let t = segmento.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
                    let parole = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
                    let breve = parole.count == 1 && Richiamo.risposteBrevi.contains(String(parole[0]).lowercased())
                    // ascolto sempre aperto: qualsiasi frase del signore lo sveglia, non solo «Jarvis» (ma se intorno c'è folla,
                    // musica o TV, solo «Jarvis» e le parole di richiamo; una parola isolata
                    // conta solo se è una risposta tipo «sì», «no», «grazie», così un rumore non lo accende);
                    // e subito dopo una richiesta, il seguito della frase vale anche se è una parola sola
                    let affollato = AmbienteSonoro.condiviso.affollato
                    if !t.isEmpty, adesso < liberoFinoA || voceConfermata || Benvenuto.eFraseDiTony(t)
                        || (Impostazioni.ascoltoSempre && !affollato && (parole.count >= 2 || breve)) {
                        trovato = t; soloDopoNome = false
                    } else if !t.isEmpty, Impostazioni.ascoltoSempre, affollato, VoceDelSignore.attiva {
                        // in mezzo alla gente: risponde solo alla voce del signore. Se stiamo già parlando (fiducia di
                        // conversazione) passa anche un «sì»; altrimenti si controlla l'impronta su una frase vera.
                        if VoceDelSignore.inFiducia && (parole.count >= 2 || breve) {
                            trovato = t; soloDopoNome = false
                        } else if parole.count >= 2 && !controlloInCorso {
                            controllaVoce(turno: mio)
                        }
                    }
                }
                guard let dopo = trovato else { if fine { riavvia(recentiDa: condotto.ultimaFine) }; return }
                if soloDopoNome { VoceDelSignore.rinnovaFiducia() }   // ha detto «Jarvis»: la conversazione è sua
                sveglio = true
                prima = ""
                corrente = dopo
                sveglia?()
                // da qui ha un minuto per dire tutto
                timerTetto = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.chiudi() }
                }
            } else {
                ultimoParziale = adesso
                if ripartito {
                    // il riconoscimento è ripartito da capo: tengo ciò che aveva già detto e continuo ad aggiungere
                    prima = resto
                    corrente = ""
                    inizioSegmento = 0
                    soloDopoNome = false
                }
                let segmento = Richiamo.dallaParola(inizioSegmento, testo)
                if soloDopoNome {
                    if let dopo = Richiamo.dopoRichiamo(segmento) { corrente = dopo }
                } else {
                    corrente = segmento.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
                }
            }
            resto = [prima, corrente].filter { !$0.isEmpty }.joined(separator: " ")
            self.testo?(resto)
            // solo «Jarvis»: gli lascio qualche secondo per iniziare la domanda; poi le solite pause
            let attesa = resto.isEmpty ? 5.0 : Jarvis.pausaFineFrase(resto)
            timerSilenzio?.invalidate()
            timerSilenzio = Timer.scheduledTimer(withTimeInterval: attesa, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.chiudi() }
            }
            // «fine» qui è il riconoscimento che chiude un pezzo: se la frase non è finita, riparto e continuo ad ascoltare
            if fine { continuaDopoFine() }
            return
        }
        if fine { if sveglio { continuaDopoFine() } else { riavvia(recentiDa: condotto.ultimaFine) } }
    }

    /// Controlla con l'impronta se chi sta parlando è il signore; se sì, lo sveglia con la frase che sta dicendo.
    private func controllaVoce(turno mio: Int) {
        controlloInCorso = true
        Task { @MainActor [weak self] in
            let lui = await VoceDelSignore.eLui(ultimi: 1.6)
            guard let self else { return }
            self.controlloInCorso = false
            guard lui == true, self.acceso, !self.sveglio, self.turno == mio else { return }
            self.voceConfermata = true
            self.ultimoParziale = Date()          // nessuna «pausa» finta: la frase continua da dove era
            self.valuta(self.precedente, fine: false, turno: mio)
        }
    }

    /// Il riconoscimento ha chiuso il suo pezzo ma il signore potrebbe non aver finito: tengo quanto detto e riapro
    /// l'ascolto senza perdere nulla; sarà il silenzio (timerSilenzio) a decidere quando la frase è davvero finita.
    private func continuaDopoFine() {
        guard sveglio else { return }
        guard motore.isRunning, let riconoscitore else { chiudi(); return }
        let detto = resto
        // il microfono non si ferma: cambio solo il trascrittore, e gli rileggo l'audio arrivato dopo la sua chiusura
        nuovoRiconoscimento(riconoscitore, recentiDa: condotto.ultimaFine)
        prima = detto
        corrente = ""
        resto = detto
        soloDopoNome = false
        precedente = ""
        inizioSegmento = 0
        ultimeParole = 0
    }

    /// La frase è finita: la consegno a JARVIS e continuo ad ascoltare con il microfono acceso, così se il signore
    /// riprende subito a parlare («…e anche un'altra cosa») l'attacco non si perde. Se a JARVIS non servo, mi spegne lui.
    private func chiudi() {
        guard sveglio else { return }
        let frase = resto
        timerSilenzio?.invalidate(); timerSilenzio = nil
        timerTetto?.invalidate(); timerTetto = nil
        if voluto, motore.isRunning, let riconoscitore {
            azzera()
            nuovoRiconoscimento(riconoscitore, recentiDa: nil)
            programmaRiavvio()
        } else {
            voluto = false
            spegni()
        }
        consegna?(frase)
    }

    // MARK: Ponti fuori dal thread principale

    nonisolated private static func collega(_ motore: AVAudioEngine, _ condotto: Condotto, _ mani: BattitoMani) throws {
        let input = motore.inputNode
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Richiamo", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio"])
        }
        input.removeTap(onBus: 0)
        let ambiente = AmbienteSonoro.condiviso.nuovaAnalisi(formato: formato)   // folla, musica, TV intorno?
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, quando in
            condotto.scrivi(buffer)
            mani.analizza(buffer)                                // due battiti di mani: JARVIS si sveglia
            ambiente?.analizza(buffer, posizione: quando.sampleTime)
            RegistroMicrofono.condiviso.scrivi(buffer)          // gli ultimi secondi, per riconoscere la voce del signore
        }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in
            esito(ris?.bestTranscription.formattedString, (ris?.isFinal ?? false) || err != nil)
        }
    }
}

/// Due battiti di mani, come Tony Stark. Gira sul thread audio, tutto sul telefono (o sul Mac), senza rete.
/// Un battito è un colpo secco: sale di colpo molto sopra il rumore di fondo e si spegne entro un decimo di secondo
/// (la voce e la musica invece restano accese). Ne servono due, a distanza di 0,15–0,8 secondi; poi due secondi di pausa.
/// Con musica, folla o TV intorno (l'analisi dell'ambiente) non scatta: un colpo di batteria non deve svegliare JARVIS.
nonisolated final class BattitoMani: @unchecked Sendable {
    private let lock = NSLock()
    private var avviso: (@Sendable () -> Void)?
    /// Chi avvisare quando sente i due battiti (si può cambiare anche mentre il microfono è acceso).
    var quandoSente: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }
    private var fondo: Float = 0.01          // il rumore di fondo (media lenta)
    private var campioni: Int64 = 0          // il tempo, in campioni dall'accensione
    private var candidato: (inizio: Int64, energia: Float, coda: Float, finestre: Int)?
    private var primoBattito: Int64 = -1
    private var pausaFino: Int64 = 0
    private let finestra = 256
    /// Il colpo minimo per un battito. Sull'iPhone resta 0,08; il Mac (microfono più lontano e più basso) lo abbassa.
    var minimoPicco: Float = 0.08

    /// I suoni dell'app (tick, plim, avvio) non devono sembrare battiti: per un attimo si ignora tutto.
    private nonisolated(unsafe) static var ignoraFino = Date.distantPast
    private static let lockIgnora = NSLock()
    static func ignora(per secondi: TimeInterval) {
        lockIgnora.lock(); ignoraFino = max(ignoraFino, Date().addingTimeInterval(secondi)); lockIgnora.unlock()
    }
    private static var daIgnorare: Bool { lockIgnora.lock(); defer { lockIgnora.unlock() }; return Date() < ignoraFino || tastiera }

    /// Tastiera aperta: i suoi click dall'altoparlante sembrano battiti di mani, quindi finché si scrive non contano.
    private nonisolated(unsafe) static var tastiera = false
    static func tastieraAperta(_ aperta: Bool) { lockIgnora.lock(); tastiera = aperta; lockIgnora.unlock() }

    /// Microfono appena riacceso: si riparte puliti (niente colpi a metà rimasti dalla volta prima).
    func azzera() { lock.lock(); candidato = nil; primoBattito = -1; pausaFino = 0; lock.unlock() }

    func analizza(_ b: AVAudioPCMBuffer) {
        guard UserDefaults.standard.object(forKey: "battitoMani") as? Bool ?? true,
              let dati = b.floatChannelData?[0] else { return }
        let n = Int(b.frameLength), hz = Int64(b.format.sampleRate)
        guard n > 0, hz > 0 else { return }
        var sentito = false
        lock.lock()
        var i = 0
        while i + finestra <= n {
            var picco: Float = 0, somma: Float = 0
            for k in i..<(i + finestra) { let v = abs(dati[k]); picco = max(picco, v); somma += v * v }
            let energia = (somma / Float(finestra)).squareRoot()
            let ora = campioni + Int64(i)
            if var c = candidato {
                // dopo il colpo: quanto resta acceso fra 50 e 130 millisecondi
                let dopo = ora - c.inizio
                if dopo < hz * 50 / 1000 { c.energia = max(c.energia, energia); candidato = c }      // il colpo vero, al suo massimo
                else if dopo <= hz * 130 / 1000 { c.coda += energia; c.finestre += 1; candidato = c }
                else if dopo > hz * 130 / 1000 {
                    let media = c.finestre > 0 ? c.coda / Float(c.finestre) : 0
                    candidato = nil
                    if media < c.energia * 0.4 {                  // si è spento subito: è un battito
                        if primoBattito >= 0, c.inizio - primoBattito >= hz * 150 / 1000, c.inizio - primoBattito <= hz * 800 / 1000 {
                            primoBattito = -1
                            pausaFino = ora + hz * 2
                            sentito = true
                        } else {
                            primoBattito = c.inizio
                        }
                    } else {
                        primoBattito = -1                         // suono lungo (voce, musica): non conta
                    }
                }
            } else if ora >= pausaFino, picco > max(minimoPicco, fondo * 10), energia > fondo * 5 {
                if BattitoMani.daIgnorare {
                    primoBattito = -1                             // un suono dell'app: non conta
                } else {
                    candidato = (ora, energia, 0, 0)
                }
            }
            if candidato == nil { fondo = fondo * 0.995 + energia * 0.005 }
            if primoBattito >= 0, ora - primoBattito > hz { primoBattito = -1 }   // il secondo non è arrivato
            i += finestra
        }
        campioni += Int64(n)
        let avvisa = sentito ? avviso : nil
        lock.unlock()
        avvisa?()
    }
}

/// Il tubo fra il microfono e il trascrittore di turno. Il microfono scrive sempre qui; il trascrittore si può cambiare
/// in un istante, e il nuovo può rileggere l'ultimo secondo e mezzo di audio (le parole dette durante il cambio).
nonisolated final class Condotto: @unchecked Sendable {
    private let lock = NSLock()
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var recenti: [(buffer: AVAudioPCMBuffer, quando: Date)] = []
    private var fine = Date.distantPast

    func scrivi(_ b: AVAudioPCMBuffer) {
        let copia = Condotto.copia(b)
        let adesso = Date()
        lock.lock()
        richiesta?.append(b)
        if let copia { recenti.append((copia, adesso)) }
        while let p = recenti.first, adesso.timeIntervalSince(p.quando) > 1.5 { recenti.removeFirst() }
        lock.unlock()
    }

    /// Il trascrittore ha chiuso il suo pezzo adesso.
    func segnaFine() { lock.lock(); fine = Date(); lock.unlock() }
    var ultimaFine: Date { lock.lock(); defer { lock.unlock() }; return fine }

    func usa(_ r: SFSpeechAudioBufferRecognitionRequest?, recentiDa: Date?) {
        lock.lock()
        if let r, let da = recentiDa {
            for p in recenti where p.quando >= da { r.append(p.buffer) }
        }
        richiesta = r
        lock.unlock()
    }

    private static func copia(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let sorgente = b.floatChannelData,
              let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength),
              let destinazione = c.floatChannelData else { return nil }
        c.frameLength = b.frameLength
        for k in 0..<Int(b.format.channelCount) {
            destinazione[k].update(from: sorgente[k], count: Int(b.frameLength))
        }
        return c
    }
}
#endif
