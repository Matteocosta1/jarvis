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
    private var timerSilenzio: Timer?

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timerRiavvio: Timer?
    private var turno = 0
    private var voluto = false          // il signore vuole l'orecchio acceso (JARVIS sta parlando)
    private var acceso = false

    private static let paroleStop = ["jarvis", "basta", "aspetta", "fermati", "zitto", "silenzio", "un attimo", "stop"]

    var attivo: Bool { acceso }

    func avvia() {
        voluto = true
        accendi()
    }

    func ferma() {
        voluto = false
        inPresa = false
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
            r.contextualStrings = ["Jarvis"]
            if riconoscitore.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }   // niente quota Apple, niente rete
            richiesta = r
            try Orecchio.collega(motore, a: r)
            motore.prepare()
            try motore.start()
            acceso = true
            turno += 1
            let mio = turno
            compito = Orecchio.riconosci(riconoscitore, r) { [weak self] testo, fine in
                Task { @MainActor [weak self] in self?.valuta(testo, fine: fine, turno: mio) }
            }
            // Apple chiude ogni ascolto dopo circa un minuto: si riparte prima, senza che si noti.
            timerRiavvio?.invalidate()
            timerRiavvio = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.riavvia() }
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

    private func valuta(_ testo: String?, fine: Bool, turno mio: Int) {
        guard acceso, mio == turno else { return }
        if let testo, !testo.isEmpty {
            let basso = testo.lowercased()
            if !inPresa, let parola = Orecchio.paroleStop.first(where: { basso.contains($0) }) {
                var resto = ""
                if let r = basso.range(of: parola) {
                    resto = String(testo[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
                }
                ferma()
                interrotto?(resto)
                return
            }
            let parole = basso.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if !inPresa {
                // è la mia eco? Se quasi tutte le parole stanno in ciò che sto dicendo, è l'altoparlante, non il signore
                let mie = Set(testoDetto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                let estranee = parole.filter { !mie.contains($0) }
                guard parole.count >= 2, Double(estranee.count) >= Double(parole.count) * 0.5 else { if fine { riavvia() }; return }
                inPresa = true
                zittisci?()                               // JARVIS tace; io continuo ad ascoltare la frase
            }
            ultimoTesto = testo
            // la frase è finita quando il signore tace (più a lungo se si è fermato a metà: «…e», «…perché»)
            timerSilenzio?.invalidate()
            timerSilenzio = Timer.scheduledTimer(withTimeInterval: Jarvis.pausaFineFrase(testo), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.consegna() }
            }
            if fine { consegna() }
            return
        }
        if fine { if inPresa { consegna() } else { riavvia() } }
    }

    /// La frase del signore è completa: la passo a JARVIS.
    private func consegna() {
        guard inPresa else { return }
        let testo = ultimoTesto.trimmingCharacters(in: .whitespacesAndNewlines)
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
