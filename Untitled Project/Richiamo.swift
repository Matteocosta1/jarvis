#if os(iOS)
import AVFoundation
import Speech

/// Il richiamo: quando JARVIS è in attesa e l'app è aperta, ascolta in silenzio e si sveglia solo sentendo «Jarvis».
/// «Jarvis, che tempo fa domani»: raccoglie la frase intera (stesse pause dell'ascolto normale) e la consegna.
/// Solo «Jarvis» e poi silenzio: JARVIS apre l'ascolto normale e aspetta la domanda.
/// Le altre voci, la musica, la TV vengono ignorate: senza «Jarvis» non succede nulla.
/// Il riconoscimento è sull'iPhone (niente rete, niente quota Apple) e riparte da solo ogni 50 secondi.
@MainActor
final class Richiamo {
    /// Ha sentito «Jarvis»: suono e reattore in ascolto.
    var sveglia: (() -> Void)?
    /// La frase dopo «Jarvis» è finita (vuota se ha detto solo «Jarvis»).
    var consegna: ((String) -> Void)?
    /// La frase mentre la dice, per mostrarla sullo schermo.
    var testo: ((String) -> Void)?

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
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
    private var inizioSegmento = 0       // dove comincia l'ultima frase (dopo una pausa) nella trascrizione
    private var ultimaLunghezza = 0
    private var ultimoParziale = Date.distantPast

    /// Il nome, anche come lo storpia il riconoscimento («Giarvis», «Jervis»…): vale in qualsiasi punto della frase.
    nonisolated static let nomi = ["jarvi", "giarvi", "giàrvi", "jervis", "charvis", "jarves", "jarbis"]
    /// Parole di richiamo che valgono solo a inizio frase (dopo una pausa): «ascoltami, …», «ehi, …», «bro, …», «fratello, …».
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
            let sessione = AVAudioSession.sharedInstance()
            // mixWithOthers: la musica di Spotify continua; A2DP: le cuffie restano in alta qualità
            try sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try sessione.setActive(true)
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            r.addsPunctuation = true
            r.contextualStrings = ["Jarvis", "ascoltami", "ehi Jarvis", "hey Jarvis"]
            if riconoscitore.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
            richiesta = r
            try Richiamo.collega(motore, a: r)
            motore.prepare()
            try motore.start()
            acceso = true
            sveglio = false
            resto = ""
            inizioSegmento = 0
            ultimaLunghezza = 0
            ultimoParziale = .distantPast
            turno += 1
            let mio = turno
            compito = Richiamo.riconosci(riconoscitore, r) { [weak self] testo, fine in
                Task { @MainActor [weak self] in self?.valuta(testo, fine: fine, turno: mio) }
            }
            // Apple chiude ogni ascolto dopo circa un minuto: si riparte prima (ma non mentre il signore sta parlando)
            timerRiavvio?.invalidate()
            timerRiavvio = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.sveglio else { return }
                    self.riavvia()
                }
            }
        } catch {
            spegni()
            // microfono occupato (un'altra app, una chiamata): riprovo fra poco
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.accendi()
            }
        }
    }

    private func spegni() {
        timerRiavvio?.invalidate(); timerRiavvio = nil
        timerSilenzio?.invalidate(); timerSilenzio = nil
        timerTetto?.invalidate(); timerTetto = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil
        compito = nil
        acceso = false
        sveglio = false
        resto = ""
    }

    private func riavvia() {
        guard voluto else { return }
        spegni()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.accendi()
        }
    }

    private func valuta(_ testo: String?, fine: Bool, turno mio: Int) {
        guard acceso, mio == turno else { return }
        if let testo, !testo.isEmpty {
            let adesso = Date()
            if !sveglio {
                // dopo una pausa comincia una frase nuova: i richiami «ascoltami», «ehi» valgono solo lì
                if adesso.timeIntervalSince(ultimoParziale) > 1.0 { inizioSegmento = min(ultimaLunghezza, testo.count) }
                ultimoParziale = adesso
                ultimaLunghezza = testo.count
                let segmento = String(testo.dropFirst(min(inizioSegmento, testo.count)))
                var trovato = Richiamo.dopoRichiamo(segmento)
                if trovato == nil, adesso < liberoFinoA {
                    // ha appena finito di parlare e riprende: è il seguito della frase, niente «Jarvis» necessario
                    let t = segmento.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
                    if !t.isEmpty { trovato = t }
                }
                guard let dopo = trovato else { if fine { riavvia() }; return }
                sveglio = true
                resto = dopo
                sveglia?()
                // da qui ha un minuto per dire tutto
                timerTetto = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.chiudi() }
                }
            } else {
                let segmento = String(testo.dropFirst(min(inizioSegmento, testo.count)))
                if let dopo = Richiamo.dopoRichiamo(segmento) { resto = dopo }
            }
            self.testo?(resto)
            // solo «Jarvis»: gli lascio qualche secondo per iniziare la domanda; poi le solite pause
            let attesa = resto.isEmpty ? 5.0 : Jarvis.pausaFineFrase(resto)
            timerSilenzio?.invalidate()
            timerSilenzio = Timer.scheduledTimer(withTimeInterval: attesa, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.chiudi() }
            }
            if fine { chiudi() }
            return
        }
        if fine { if sveglio { chiudi() } else { riavvia() } }
    }

    /// La frase è finita: la consegno a JARVIS e mi spengo (JARVIS mi riaccende quando torna in attesa).
    private func chiudi() {
        guard sveglio else { return }
        let frase = resto
        voluto = false
        spegni()
        consegna?(frase)
    }

    // MARK: Ponti fuori dal thread principale

    nonisolated private static func collega(_ motore: AVAudioEngine, a r: SFSpeechAudioBufferRecognitionRequest) throws {
        let input = motore.inputNode
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Richiamo", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio"])
        }
        input.removeTap(onBus: 0)
        nonisolated(unsafe) let richiesta = r
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, _ in richiesta.append(buffer) }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in
            esito(ris?.bestTranscription.formattedString, (ris?.isFinal ?? false) || err != nil)
        }
    }
}
#endif
