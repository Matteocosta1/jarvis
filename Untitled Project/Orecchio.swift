#if os(iOS)
import AVFoundation
import Speech

/// L'orecchio di JARVIS mentre parla: ascolta sottovoce e, se il signore dice «Jarvis», «basta», «aspetta»,
/// «stop», «zitto», «fermati» o «un attimo», lo interrompe subito e gli passa la parola.
/// Se invece il signore inizia semplicemente a parlare (almeno due parole), JARVIS tace, lo lascia finire la frase
/// e gliela consegna intera: come in una conversazione tra persone, senza toccare il reattore.
/// L'iPhone cancella l'eco della propria voce (voice processing); in più, se quello che sente coincide con le parole
/// che JARVIS sta dicendo, lo ignora: così non si interrompe da solo.
@MainActor
final class Orecchio {
    /// Chiamato quando il signore interrompe: riceve ciò che ha detto (dopo la parola d'ordine, o la frase intera).
    var interrotto: ((String) -> Void)?
    /// Chiamato appena il signore inizia a parlare: JARVIS deve tacere e mettersi in ascolto, l'orecchio continua da solo.
    var zittisci: (() -> Void)?
    /// Le parole che JARVIS sta dicendo in questo momento: servono a riconoscere la propria eco.
    var testoDetto = ""
    private var inPresa = false         // il signore sta parlando: aspetto che finisca la frase
    private var ultimoTesto = ""
    private var precedente = ""         // l'ultima trascrizione ricevuta
    private var primaPresa = ""
    private var voceConfermata = false
    private var controlloInCorso = false         // ciò che il signore ha già detto, se il riconoscimento è ripartito da capo
    private var inizioSegmento = 0      // la trascrizione si accumula: conta solo ciò che è arrivato dopo l'ultima pausa
    private var ultimaLunghezza = 0
    private var ultimoParziale = Date.distantPast
    private var timerSilenzio: Timer?

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timerRiavvio: Timer?
    private var turno = 0
    private var voluto = false          // il signore vuole l'orecchio acceso (JARVIS sta parlando)
    private var acceso = false

    private static let paroleStop = ["jarvis", "giarvis", "jervis", "basta", "aspetta", "ascoltami", "fermati", "zitto", "silenzio",
                                     "un attimo", "stop", "ehi", "hey", "bro", "fratello"]

    var attivo: Bool { acceso }

    func avvia() {
        voluto = true
        accendi()
    }

    func ferma() {
        voluto = false
        inPresa = false
        voceConfermata = false
        primaPresa = ""
        timerSilenzio?.invalidate()
        timerSilenzio = nil
        spegni()
    }

    private func accendi() {
        guard voluto, !acceso, let riconoscitore, riconoscitore.isAvailable else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        do {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            r.addsPunctuation = true
            r.contextualStrings = ["Jarvis"]
            if riconoscitore.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }   // niente quota Apple, niente rete
            richiesta = r
            try Orecchio.collega(motore, a: r)
            motore.prepare()
            try motore.start()
            acceso = true
            inizioSegmento = 0
            ultimaLunghezza = 0
            ultimoParziale = .distantPast
            precedente = ""
            turno += 1
            let mio = turno
            compito = Orecchio.riconosci(riconoscitore, r) { [weak self] testo, fine in
                Task { @MainActor [weak self] in self?.valuta(testo, fine: fine, turno: mio) }
            }
            // Apple chiude ogni ascolto dopo circa un minuto: si riparte prima, senza che si noti.
            timerRiavvio?.invalidate()
            timerRiavvio = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.inPresa else { return }   // il signore sta parlando: non gli taglio la frase
                    self.riavvia()
                }
            }
        } catch {
            spegni()
        }
    }

    private func spegni() {
        timerRiavvio?.invalidate()
        timerRiavvio = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil
        compito = nil
        acceso = false
    }

    private func riavvia() {
        guard voluto else { return }
        spegni()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.accendi()
        }
    }

    /// Le parole di una frase, minuscole, senza punteggiatura.
    nonisolated private static func parole(_ t: String) -> [String] {
        t.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    /// La prima parola d'ordine detta come parola intera («basta», non «abbastanza») e che JARVIS non sta dicendo lui
    /// («un attimo, Sir» è una sua frase: la sua eco non deve fermarlo). Restituisce la parola e ciò che segue.
    private func paroladOrdine(in segmento: String) -> String? {
        let sentite = " " + Orecchio.parole(segmento).joined(separator: " ") + " "
        let dette = " " + Orecchio.parole(testoDetto).joined(separator: " ") + " "
        for p in Orecchio.paroleStop {
            let cercata = " " + p + " "
            guard sentite.contains(cercata) else { continue }
            if dette.contains(cercata) && !p.hasPrefix("jarvi") { continue }   // la sta dicendo JARVIS: è eco
            if p.hasPrefix("jarvi") && dette.contains(cercata) && sentite.components(separatedBy: cercata).count <= dette.components(separatedBy: cercata).count { continue }
            return p
        }
        return nil
    }

    private func valuta(_ testo: String?, fine: Bool, turno mio: Int) {
        guard acceso, mio == turno else { return }
        if let testo, !testo.isEmpty {
            // dopo una pausa comincia un pezzo nuovo: valuto solo quello, non tutta la trascrizione dall'inizio
            // (prima l'eco accumulata «diluiva» le parole del signore e l'interruzione non scattava più)
            let adesso = Date()
            let pausa = adesso.timeIntervalSince(ultimoParziale)
            // il riconoscimento sull'iPhone a volte ricomincia la trascrizione da capo dopo una pausa
            let ripartito = Richiamo.pezzoNuovo(precedente: precedente, nuovo: testo, pausa: pausa)
            precedente = testo
            if ripartito {
                if inPresa { primaPresa = ultimoTesto }   // tengo quanto ha già detto e continuo ad aggiungere
                inizioSegmento = 0
            } else if !inPresa, pausa > 0.7 { inizioSegmento = min(ultimaLunghezza, testo.count) }
            ultimoParziale = adesso
            ultimaLunghezza = testo.count
            var segmento = String(testo.dropFirst(min(inizioSegmento, testo.count)))

            if !inPresa, let parola = paroladOrdine(in: segmento) {
                // «Jarvis», «aspetta», «basta»…: JARVIS tace subito, ma io continuo ad ascoltare sullo stesso microfono
                // dalla parola d'ordine in poi, così non si perde nulla e non serve riaprire l'ascolto (niente bip)
                if let r = segmento.range(of: parola, options: [.caseInsensitive, .backwards]) {
                    inizioSegmento = min(inizioSegmento + segmento.distance(from: segmento.startIndex, to: r.lowerBound), testo.count)
                    segmento = String(testo.dropFirst(inizioSegmento))
                }
                inPresa = true
                zittisci?()
            }
            let parole = Orecchio.parole(segmento)
            if !inPresa {
                // è la mia eco? Se quasi tutte le parole stanno in ciò che sto dicendo, è l'altoparlante, non il signore
                let mie = Set(Orecchio.parole(testoDetto))
                let estranee = parole.filter { !mie.contains($0) }
                // in mezzo alla folla le voci degli altri non devono zittirlo: lì valgono solo le parole d'ordine («Jarvis», «basta»…)
                guard parole.count >= 2, Double(estranee.count) >= Double(parole.count) * 0.5 else { if fine { riavvia() }; return }
                if AmbienteSonoro.condiviso.affollato && !voceConfermata {
                    // in mezzo alla folla le voci degli altri non devono zittirlo: valgono le parole d'ordine
                    // e, se il signore ha registrato la sua voce, le frasi riconosciute come sue
                    if VoceDelSignore.attiva && !controlloInCorso {
                        controlloInCorso = true
                        let mio = turno
                        Task { @MainActor [weak self] in
                            // aspetto che abbia detto qualche parola in più, così il pezzo controllato è quasi tutto
                            // voce sua e non la coda della mia; sopra la musica e la mia voce l'audio è più sporco,
                            // quindi se stiamo già parlando (fiducia di conversazione) la soglia è un po' più larga
                            try? await Task.sleep(for: .milliseconds(700))
                            let lui = await VoceDelSignore.eLui(ultimi: 1.8, sconto: VoceDelSignore.inFiducia ? 0.08 : 0.03)
                            guard let self else { return }
                            self.controlloInCorso = false
                            guard lui == true, self.acceso, !self.inPresa, self.turno == mio else { return }
                            self.voceConfermata = true
                            self.ultimoParziale = Date()          // nessuna «pausa» finta: la frase continua da dove era
                            self.valuta(self.precedente, fine: false, turno: mio)
                        }
                    }
                    if fine { riavvia() }
                    return
                }
                inPresa = true
                zittisci?()                               // JARVIS tace; io continuo ad ascoltare la frase
            }
            // solo la frase del signore, senza l'eco di prima (più quanto detto prima di un'eventuale ripartenza)
            ultimoTesto = [primaPresa, segmento].filter { !$0.isEmpty }.joined(separator: " ")
            // la frase è finita quando il signore tace (più a lungo se si è fermato a metà: «…e», «…perché»)
            timerSilenzio?.invalidate()
            // solo la parola d'ordine («Jarvis…»): gli lascio qualche secondo per dire cosa vuole
            // («basta», «zitto», «stop» da soli: tace e basta, quindi aspetto poco)
            let (pulito, chiede) = Jarvis.togliRichiamo(ultimoTesto)
            let basso = ultimoTesto.lowercased()
            let chiama = chiede || ["jarvi", "giarvi", "jervis", "ehi", "hey", "bro", "fratello"].contains(where: { basso.contains($0) })
            let attesa = pulito.isEmpty ? (chiama ? 4.0 : 1.2) : Jarvis.pausaFineFrase(ultimoTesto)
            timerSilenzio = Timer.scheduledTimer(withTimeInterval: attesa, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.consegna() }
            }
            if fine { riprendiPresa() }
            return
        }
        if fine { if inPresa { riprendiPresa() } else { riavvia() } }
    }

    /// Il riconoscimento ha chiuso il suo pezzo mentre il signore parlava: riapro subito l'ascolto tenendo quanto detto.
    /// Decide il silenzio (timerSilenzio) quando la frase è davvero finita, non il riconoscimento.
    private func riprendiPresa() {
        guard inPresa else { return }
        primaPresa = ultimoTesto
        spegni()
        accendi()
        if !acceso { consegna() }          // il microfono non riparte: consegno quello che ho
    }

    /// La frase del signore è completa: la passo a JARVIS.
    private func consegna() {
        guard inPresa else { return }
        let testo = ultimoTesto.trimmingCharacters(in: .whitespacesAndNewlines)
        primaPresa = ""
        ferma()
        interrotto?(testo)
    }

    // MARK: Ponti fuori dal thread principale

    nonisolated private static func collega(_ motore: AVAudioEngine, a r: SFSpeechAudioBufferRecognitionRequest) throws {
        let input = motore.inputNode
        // cancellazione dell'eco: il microfono non sente la voce che esce dall'altoparlante
        if !input.isVoiceProcessingEnabled { try input.setVoiceProcessingEnabled(true) }
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Orecchio", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio"])
        }
        input.removeTap(onBus: 0)
        nonisolated(unsafe) let richiesta = r
        let ambiente = AmbienteSonoro.condiviso.nuovaAnalisi(formato: formato)   // folla, musica, TV intorno?
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, quando in
            richiesta.append(buffer)
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
#endif
