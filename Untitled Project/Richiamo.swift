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

    private var motore = AVAudioEngine()
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
    /// Fino a quando, finita una risposta, il seguito vale senza «Jarvis» («Perché?», «E domani?»). Come `liberoFinoA`,
    /// ma non in mezzo alla folla: lì le voci degli altri non devono svegliarlo (revisione del dialogo, M6).
    var seguitoFinoA = Date.distantPast
    /// L'ultima volta che ha sentito parlare (anche frasi non per lui): JARVIS non attacca il riempitivo sopra il signore.
    private(set) var ultimaVoce = Date.distantPast
    private var precedente = ""         // l'ultima trascrizione ricevuta
    private var prima = ""              // ciò che ha già detto dopo il richiamo, prima che il riconoscimento ripartisse da capo
    private var soloDopoNome = true      // vero: conta ciò che segue «Jarvis»; falso: conta tutta la frase (seguito senza nome)
    private var corrente = ""
    /// «Che ore sono, Jarvis?»: la frase intera col nome in fondo; vale se dopo il nome il signore non aggiunge altro.
    private var vocativo: String?
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

    /// «Che ore sono, Jarvis?»: il nome in fondo, detto come si chiama una persona. Vero se prima del nome c'è una frase vera
    /// (non solo «senti», «ehi», «ok») e il nome non è dentro un discorso («chiedilo a Jarvis», «io e Jarvis»).
    /// Revisione del dialogo (24 ott, come M2 per l'orecchio): prima restava solo quello che veniva DOPO il nome, cioè niente,
    /// e la domanda si perdeva dopo 5 secondi di attesa.
    nonisolated static func nomeInFondo(_ segmento: String) -> Bool {
        let parole = segmento.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        guard parole.count >= 2, let ultima = parole.last, nomi.contains(where: { ultima.hasPrefix($0) }) else { return false }
        let prima = parole.dropLast()
        let legate: Set<String> = ["a", "ad", "di", "da", "con", "su", "per", "tra", "fra", "il", "al", "del", "dal", "col", "sul", "che", "e", "o", "come"]
        guard let precedente = prima.last, !legate.contains(precedente) else { return false }
        let soloRichiami: Set<String> = ["senti", "ascolta", "ascoltami", "ehi", "hey", "ei", "ok", "okay", "scusa", "allora", "dai", "oh", "ciao",
                                         "buongiorno", "buonasera", "no", "sì", "si", "aspetta", "bro", "fratello", "frate", "socio", "amico", "capo"]
        return prima.contains(where: { p in !soloRichiami.contains(p) && !nomi.contains(where: { p.hasPrefix($0) }) })
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
                // un motore nuovo, creato ADESSO che l'audio permette il microfono: quello vecchio poteva essersi
                // «ricordato» l'audio dell'avvio (nessun ingresso) e restare acceso ma sordo (il «Jarvis» che non sente)
                motore = AVAudioEngine()
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
        r.contextualStrings = ["Jarvis", "ascoltami", "ehi Jarvis", "hey Jarvis", "wake up", "daddy's home", "wake up daddy's home", "EDITH", "mi ricevi"]
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
        vocativo = nil
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
            ultimaVoce = adesso
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
                vocativo = trovato?.isEmpty == true && !AmbienteSonoro.condiviso.affollato && Richiamo.nomeInFondo(segmento) ? segmento.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                // decisione del signore (24 ott, M8): mentre usa l'orologio, per 10 secondi l'iPhone non prende le frasi senza «Jarvis»
                // (sentirebbe la domanda fatta al polso, o la voce dell'orologio, e risponderebbe anche lui)
                if trovato == nil, !OrologioInUso.attivo {
                    let t = segmento.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
                    let parole = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
                    let breve = parole.count == 1 && Richiamo.risposteBrevi.contains(String(parole[0]).lowercased())
                    // ascolto sempre aperto: qualsiasi frase del signore lo sveglia, non solo «Jarvis» (ma se intorno c'è folla,
                    // musica o TV, solo «Jarvis» e le parole di richiamo; una parola isolata
                    // conta solo se è una risposta tipo «sì», «no», «grazie», così un rumore non lo accende);
                    // e subito dopo una richiesta, il seguito della frase vale anche se è una parola sola; così pure appena
                    // finita una risposta («Perché?»), ma non in mezzo alla folla
                    let affollato = AmbienteSonoro.condiviso.affollato
                    if !t.isEmpty, adesso < liberoFinoA || (adesso < seguitoFinoA && !affollato) || voceConfermata || Benvenuto.eFraseDiTony(t)
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
                    prima = resto.isEmpty ? (vocativo ?? "") : resto
                    vocativo = nil
                    corrente = ""
                    inizioSegmento = 0
                    soloDopoNome = false
                }
                let segmento = Richiamo.dallaParola(inizioSegmento, testo)
                if soloDopoNome {
                    if let dopo = Richiamo.dopoRichiamo(segmento) { corrente = dopo }
                    // «Che ore sono, Jarvis?» e niente dopo il nome: vale la frase intera
                    vocativo = corrente.isEmpty && prima.isEmpty && !AmbienteSonoro.condiviso.affollato && Richiamo.nomeInFondo(segmento) ? segmento.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                } else {
                    corrente = segmento.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
                }
            }
            resto = [prima, corrente].filter { !$0.isEmpty }.joined(separator: " ")
            self.testo?(resto.isEmpty ? (vocativo ?? "") : resto)
            // solo «Jarvis»: gli lascio qualche secondo per iniziare la domanda; poi le solite pause
            // («Che ore sono, Jarvis?»: la frase c'è già, la pausa è quella della frase)
            let attesa = resto.isEmpty ? (vocativo.map { Jarvis.pausaFineFrase($0) } ?? 5.0) : Jarvis.pausaFineFrase(resto)
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
        let detto = resto.isEmpty ? (vocativo ?? "") : resto
        vocativo = nil
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
        let frase = resto.isEmpty ? (vocativo ?? "") : resto
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
/// Build 23 (24 ott, i tasti del Mac scambiati per battiti): il suono si guarda a fettine da 1,25 ms e in tre bande,
/// e ogni colpo deve essere un battito VERO.
///  • Il «ciac» delle mani ha il corpo fra 700 e 2500 Hz: il clic di un tasto sta quasi tutto sopra i 4 kHz,
///    un tonfo sul tavolo o un dito sul telefono sotto i 500 Hz. È rumore, non una nota: un tavolo bussato,
///    un legnetto, un bicchiere «suonano» (si misura col tono, l'autocorrelazione a 0,5–2 ms) e non passano.
///  • Nessun altro colpo dentro il battito (il rilascio del tasto), nessun colpo fra i due battiti e nessuno nei 120 ms
///    dopo il secondo: chi scrive preme e rilascia, le mani no.
///  • È più forte dei suoni non-battito degli ultimi secondi: l'asticella si alza a ogni tasto, parola o colpo che non era
///    un battito e cala piano (1 dB al secondo). Chi smette di scrivere e batte le mani passa, i tasti di chi scrive no.
///  • 0,15–0,8 secondi fra l'uno e l'altro; il secondo si decide 120 ms dopo il suo attacco (prima 130 ms), poi due
///    secondi di pausa: il terzo battito cade nella pausa, come prima.
/// Nessun logaritmo e nessuna allocazione sul thread audio: solo energie, rapporti e memoria preparata all'inizio.
/// Il modello riga per riga di questo codice, con il banco di prova, è in battiti-banco/b4 (banco4.c).
nonisolated final class BattitoMani: @unchecked Sendable {
    private let lock = NSLock()
    private var avviso: (@Sendable () -> Void)?
    /// Chi avvisare quando sente i due battiti (si può cambiare anche mentre il microfono è acceso).
    var quandoSente: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }
    /// Il colpo minimo per un battito (il campione più alto). Sull'iPhone resta 0,08; il Mac (microfono più lontano e più basso) lo abbassa.
    var minimoPicco: Float = 0.08

    /// I suoni dell'app (tick, plim, avvio) non devono sembrare battiti: per un attimo si ignora tutto.
    private nonisolated(unsafe) static var ignoraFino = Date.distantPast
    private static let lockIgnora = NSLock()
    static func ignora(per secondi: TimeInterval) {
        lockIgnora.lock(); ignoraFino = max(ignoraFino, Date().addingTimeInterval(secondi)); lockIgnora.unlock()
    }
    private static var daIgnorare: Bool { lockIgnora.lock(); defer { lockIgnora.unlock() }; return Date() < ignoraFino || tastiera || voceJarvis }

    /// Mac: l'attesa ascolta anche mentre JARVIS parla, e la sua voce rientra dal microfono. Come i suoni dell'app,
    /// mentre parla (e per un secondo dopo) non conta: le sue parole non alzano l'asticella e non fanno da primo battito.
    private nonisolated(unsafe) static var voceJarvis = false
    static func jarvisParla(_ parla: Bool) {
        lockIgnora.lock()
        if voceJarvis && !parla { ignoraFino = max(ignoraFino, Date().addingTimeInterval(1.0)) }
        voceJarvis = parla
        lockIgnora.unlock()
    }

    /// Tastiera aperta: i suoi click dall'altoparlante sembrano battiti di mani, quindi finché si scrive non contano.
    private nonisolated(unsafe) static var tastiera = false
    static func tastieraAperta(_ aperta: Bool) { lockIgnora.lock(); tastiera = aperta; lockIgnora.unlock() }

    /// Un filtro biquad (RBJ, Q 0,707), forma diretta II trasposta, in Float come il modello del banco.
    nonisolated struct Filtro {
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
        var z0: Float = 0, z1: Float = 0
        init() {}
        init(hz: Double, taglio: Double, passaAlto: Bool) {
            let w0 = 2.0 * Double.pi * min(taglio, 0.45 * hz) / hz, cw = cos(w0), sw = sin(w0)
            let alfa = sw / (2.0 * 0.7071067811865476), a0 = 1.0 + alfa
            let c0: Double, c1: Double, c2: Double
            if passaAlto { c0 = (1.0 + cw) / 2.0; c1 = -(1.0 + cw); c2 = (1.0 + cw) / 2.0 }
            else { c0 = (1.0 - cw) / 2.0; c1 = 1.0 - cw; c2 = (1.0 - cw) / 2.0 }
            b0 = Float(c0 / a0); b1 = Float(c1 / a0); b2 = Float(c2 / a0)
            a1 = Float(-2.0 * cw / a0); a2 = Float((1.0 - alfa) / a0)
        }
        mutating func filtra(_ x: Float) -> Float {
            let y = b0 * x + z0
            z0 = b1 * x - a1 * y + z1
            z1 = b2 * x - a2 * y
            return y
        }
    }

    /// Un rapporto di energie da decibel (calcolato una volta, alla creazione: mai sul thread audio).
    private static func dB(_ d: Double) -> Float { Float(pow(10.0, d / 10.0)) }

    // Le soglie (tarate sul banco: battiti veri e di sintesi contro tastiera, tocchi, rumori di casa, percussioni)
    private static let storiaN = 128                      // campioni ricordati per il tono
    private let salto = BattitoMani.dB(9)                 // un attacco: +9 dB sul livello recente…
    private let sopraFondo = BattitoMani.dB(12)           // …e +12 dB sul fondo della stanza
    private let riparti = BattitoMani.dB(9)               // un attacco +9 dB più forte durante la misura: il colpo vero è quello
    private let contrasto = BattitoMani.dB(20)            // il colpo almeno +20 dB sul fondo
    private let quotaMedie: Float = 0.10                  // parte dell'energia del colpo fra 700 e 2500 Hz: almeno
    private let quotaAlte: Float = 0.60                   // sopra i 4 kHz (il clic dei tasti): al massimo
    private let quotaBasse: Float = 0.55                  // sotto i 500 Hz (tonfi, dita sul telefono): al massimo
    private let tonoMassimo: Float = 0.72                 // oltre, il colpo «suona una nota» (tavolo, legno, vetro)
    private let margineMemoria = BattitoMani.dB(9)        // il colpo +9 dB sopra i suoni non-battito recenti…
    private static let calaMemoriaPerSecondo = 1.0        // …che calano di 1 dB al secondo

    private var hzFiltri: Double = 0
    private var pa = Filtro(), basse = Filtro(), medieDa = Filtro(), medieA = Filtro(), alte = Filtro()
    private var lunghezza = 60                  // campioni per fettina
    private var sE: Float = 0, sB: Float = 0, sM: Float = 0, sA: Float = 0, sP: Float = 0
    private var nf = 0
    private var k: Int64 = 0                    // fettine dall'accensione
    private var rec: Float = 1e-10, fondo: Float = 1e-7
    private var memoria: Float = 0              // il colpo più forte fra i suoni recenti che NON erano battiti
    private var calaMemoria: Float = 1
    private var pausaFino: Int64 = 0
    // l'attacco in misura
    private var misura = false, mod2 = false
    private var k0: Int64 = 0
    private var pk: Float = 0, picco: Float = 0, eb: Float = 0, bb: Float = 0, mb: Float = 0, ab: Float = 0, f0: Float = 0
    private var riattacco = false
    private var pE: Float = 0, pB: Float = 0, pM: Float = 0, pA: Float = 0, pP: Float = 0
    // il tono
    private let storia: UnsafeMutablePointer<Float>
    private let acc: UnsafeMutablePointer<Float>
    private let accq: UnsafeMutablePointer<Float>
    private var pos = 0
    private var r0: Float = 0
    private var lmin = 24, lmax = 96, ta = 2, tb = 23
    // il primo battito, armato
    private var primo = false
    private var k1: Int64 = 0
    // in fettine
    private var jp = 4, js = 6, jr = 8, jd = 96, jv = 40
    private var imin: Int64 = 120, imax: Int64 = 640, riposo: Int64 = 1600
    private var aRec: Float = 0.083333336
    private var saleFondo: Float = 1.0017285

    init() {
        let n = BattitoMani.storiaN
        let s = UnsafeMutablePointer<Float>.allocate(capacity: n); s.initialize(repeating: 0, count: n)
        let c = UnsafeMutablePointer<Float>.allocate(capacity: n); c.initialize(repeating: 0, count: n)
        let q = UnsafeMutablePointer<Float>.allocate(capacity: n); q.initialize(repeating: 0, count: n)
        storia = s; acc = c; accq = q
    }

    deinit {
        storia.deallocate(); acc.deallocate(); accq.deallocate()
    }

    /// Microfono appena riacceso: si riparte puliti (niente colpi a metà rimasti dalla volta prima).
    func azzera() { lock.lock(); misura = false; primo = false; pausaFino = 0; memoria = 0; lock.unlock() }

    /// Filtri e misure per la frequenza del microfono (una volta, o quando cambia): si riparte da zero.
    private func configura(_ hz: Double) {
        hzFiltri = hz
        pa = Filtro(hz: hz, taglio: 150, passaAlto: true)
        basse = Filtro(hz: hz, taglio: 500, passaAlto: false)
        medieDa = Filtro(hz: hz, taglio: 700, passaAlto: true)
        medieA = Filtro(hz: hz, taglio: 2500, passaAlto: false)
        alte = Filtro(hz: hz, taglio: 4000, passaAlto: true)
        lunghezza = max(8, Int((hz * 0.00125).rounded()))
        let dt = Double(lunghezza) / hz
        func f(_ s: Double) -> Int { Int((s / dt).rounded()) }
        jp = f(0.005); js = f(0.0075); jr = f(0.010)
        jd = f(0.120); jv = f(0.050)
        imin = Int64(f(0.15)); imax = Int64(f(0.80)); riposo = Int64(f(2.0))
        aRec = Float(dt / 0.015)
        saleFondo = Float(pow(10.0, 6.0 * dt / 10.0))
        calaMemoria = Float(pow(10.0, -BattitoMani.calaMemoriaPerSecondo * dt / 10.0))
        lmax = min(Int((0.002 * hz).rounded()), BattitoMani.storiaN - 1); lmin = min(Int((0.0005 * hz).rounded()), lmax)
        ta = f(0.0025); tb = f(0.030) - 1
        sE = 0; sB = 0; sM = 0; sA = 0; sP = 0; nf = 0
        k = 0; rec = 1e-10; fondo = 1e-7; memoria = 0; pausaFino = 0
        misura = false; primo = false; pos = 0
        pE = 0; pB = 0; pM = 0; pA = 0; pP = 0
        storia.update(repeating: 0, count: BattitoMani.storiaN)
    }

    func analizza(_ b: AVAudioPCMBuffer) {
        guard UserDefaults.standard.object(forKey: "battitoMani") as? Bool ?? true,
              let dati = b.floatChannelData?[0] else { return }
        let n = Int(b.frameLength), hz = b.format.sampleRate
        guard n > 0, hz > 0 else { return }
        let ignora = BattitoMani.daIgnorare          // un suono dell'app (o la tastiera dell'iPhone): vale per tutto il pacchetto
        var sentito = false
        lock.lock()
        if hz != hzFiltri { configura(hz) }
        for i in 0..<n {
            if campione(dati[i], ignora: ignora) == 1 { sentito = true }
        }
        let avvisa = sentito ? avviso : nil
        lock.unlock()
        avvisa?()
    }

    /// Un campione: filtri, storia per il tono, somme della fettina; a fettina piena, la macchina a stati.
    private func campione(_ v: Float, ignora: Bool) -> Int {
        let f = pa.filtra(v)
        let fb = basse.filtra(f)
        let f7 = medieDa.filtra(f)
        let fm = medieA.filtra(f7)
        let fa = alte.filtra(f)
        pos = (pos + 1) & (BattitoMani.storiaN - 1)
        storia[pos] = f7
        if misura {
            let j = k - k0                                   // la fettina che si sta riempiendo
            if j >= Int64(ta) && j <= Int64(tb) {
                r0 += f7 * f7
                for l in lmin...lmax {
                    let w = storia[(pos - l) & (BattitoMani.storiaN - 1)]
                    acc[l] += f7 * w
                    accq[l] += w * w
                }
            }
        }
        sE += f * f; sB += fb * fb; sM += fm * fm; sA += fa * fa
        let av = abs(v); if av > sP { sP = av }
        nf += 1
        if nf < lunghezza { return 0 }
        let inv = 1 / Float(lunghezza)
        let r = fettina(sE * inv, sB * inv, sM * inv, sA * inv, sP, ignora: ignora)
        sE = 0; sB = 0; sM = 0; sA = 0; sP = 0; nf = 0
        return r
    }

    /// Quanto il colpo «suona una nota»: la massima autocorrelazione normalizzata (0–1) a 0,5–2 ms.
    private func tono() -> Float {
        var m: Float = 0
        for l in lmin...lmax {
            let q = r0 * accq[l]
            if q > 0 { let v = abs(acc[l]) / q.squareRoot(); if v > m { m = v } }
        }
        return m
    }

    /// È un colpo secco di mani? (vale per tutti e due i battiti)
    private func buonColpo(_ qb: Float, _ qm: Float, _ qa: Float, _ to: Float) -> Bool {
        to <= tonoMassimo && picco >= minimoPicco && pk >= f0 * contrasto
            && qm >= quotaMedie && qa <= quotaAlte && qb <= quotaBasse && !riattacco
            && pk >= memoria * margineMemoria
    }

    /// Una fettina finita: e (banda piena), b, m, a (bande), p (campione più alto). 1 = i due battiti, 2 = primo armato.
    private func fettina(_ e: Float, _ b: Float, _ m: Float, _ a: Float, _ p: Float, ignora: Bool) -> Int {
        memoria *= calaMemoria
        let recPrima = rec
        rec += (e - rec) * aRec
        let attacco = e >= recPrima * salto && e >= fondo * sopraFondo
        var esito = 0
        if misura && attacco && e >= pk * riparti {
            misura = false                                   // il colpo vero arriva adesso: quello di prima era solo un preavviso
            if pk > memoria { memoria = pk }
        }
        if misura {
            let j = Int(k - k0)
            if j <= jp { if e > pk { pk = e }; if p > picco { picco = p } }
            if j <= js { eb += e; bb += b; mb += m; ab += a }
            if j >= jr && attacco { riattacco = true }       // un altro colpo dentro questo (il rilascio di un tasto)
            if j == jp && primo && !mod2 { primo = false }   // un altro colpo subito dopo il primo battito
            if misura && j == jd && mod2 {
                let qb = bb / eb, qm = mb / eb, qa = ab / eb
                let inter = k0 - k1
                let ok = buonColpo(qb, qm, qa, tono()) && inter >= imin && inter <= imax
                if ok && !ignora {
                    esito = 1
                    misura = false; primo = false
                    pausaFino = k + riposo
                } else {
                    primo = false                            // non era il secondo: può ancora essere un primo
                }
            }
            if misura && j == (mod2 && jd > jv ? jd : jv) {   // un secondo mancato si giudica da primo dopo la sua decisione
                let qb = bb / eb, qm = mb / eb, qa = ab / eb
                let ok = buonColpo(qb, qm, qa, tono())
                misura = false
                if ok && !ignora {
                    primo = true; k1 = k0
                    if esito == 0 { esito = 2 }
                } else if pk > memoria {
                    memoria = pk                             // non era un battito (un tasto, una parola): alza l'asticella
                }
            }
        }
        if !misura {
            // il fondo della stanza: scende svelto, sale piano (al massimo 6 dB al secondo)
            if e < fondo { fondo += (e - fondo) * 0.1 }
            else { let su = fondo + (e - fondo) * 0.05; let tetto = fondo * saleFondo; fondo = su < tetto ? su : tetto }
            if primo && k - k1 > imax { primo = false }      // il secondo non è arrivato
            if attacco && k >= pausaFino {
                if ignora {
                    primo = false                            // un suono dell'app: non conta
                } else {
                    misura = true; k0 = k; mod2 = primo && k - k1 >= imin
                    pk = e > pE ? e : pE; picco = p > pP ? p : pP
                    eb = pE + e; bb = pB + b; mb = pM + m; ab = pA + a
                    riattacco = false
                    f0 = fondo
                    r0 = 0
                    acc.update(repeating: 0, count: BattitoMani.storiaN)
                    accq.update(repeating: 0, count: BattitoMani.storiaN)
                }
            }
        }
        pE = e; pB = b; pM = m; pA = a; pP = p
        k += 1
        return esito
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
