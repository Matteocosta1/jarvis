#if os(iOS)
import Foundation
import SwiftUI
import AVFoundation
import Speech
import UIKit
import Combine

/// La dettatura sul telefono (nata col WIRETAP di JARVIS): trascrive mentre si parla, tutto sul telefono, e l'audio non viene
/// salvato. In FRIDAY la usano i Messaggi.
@MainActor
final class Wiretap: ObservableObject {
    @Published private(set) var attivo = false
    @Published private(set) var confermato: [String] = []      // frasi già chiuse
    @Published private(set) var parziale = ""                 // la frase che si sta ancora riconoscendo
    @Published private(set) var livello: Float = 0            // 0…1, per l'onda sullo schermo
    @Published private(set) var inizio: Date?
    @Published var problema: String?
    /// 26 ott sera (REC nella Dynamic Island): in pausa il microfono resta aperto (da fuori iOS non lo lascia riaccendere) ma niente
    /// finisce nel testo; il tempo registrato non conta le pause.
    @Published private(set) var inPausa = false
    private var pausaDa: Date?
    private var pause: TimeInterval = 0
    /// 9 nov notte (il signore, video 02:07: fermata la registrazione «lui continua a scorrere il tempo»): quando si è fermata.
    private var fine: Date?
    /// Un comando detto durante la registrazione («Jarvis, torna», «Jarvis, apri la Sentinella»): non finisce nel verbale.
    var comando: ((ComandoVocale) -> Void)?
    /// MARK XI (4 nov, il signore): il Wiretap sta dietro un'altra sezione e registra ancora: «Jarvis, chiudi» vale per la sezione
    /// davanti e la registrazione continua (lo dice la vista, da `sezioneDietro`).
    var dietro = false

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let presa = PresaRichiesta()
    private var compito: SFSpeechRecognitionTask?
    private var turno = 0

    var testo: String {
        (confermato + (parziale.isEmpty ? [] : [parziale])).joined(separator: " ")
    }
    var minuti: Int { inizio == nil ? 0 : max(1, Int(Double(secondi()) / 60 + 0.5)) }

    /// I secondi registrati fino a `adesso`, senza le pause.
    func secondi(_ adesso: Date = Date()) -> Int {
        guard let inizio else { return 0 }
        let adesso = fine.map { min($0, adesso) } ?? adesso          // fermata: il tempo resta quello registrato
        let fermo = pause + (pausaDa.map { adesso.timeIntervalSince($0) } ?? 0)
        return max(0, Int(adesso.timeIntervalSince(inizio) - fermo))
    }

    /// Pausa: la frase a metà si tiene, poi più niente nel testo finché non riprende.
    func pausa() {
        guard attivo, !inPausa else { return }
        inPausa = true
        pausaDa = Date()
        turno += 1
        let chiuso = parziale.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chiuso.isEmpty { confermato.append(chiuso) }
        parziale = ""
        presa.metti(nil)?.endAudio()
        compito?.finish()
        compito = nil
    }

    func riprendi() {
        guard attivo, inPausa else { return }
        if let p = pausaDa { pause += Date().timeIntervalSince(p) }
        pausaDa = nil
        inPausa = false
        nuovaFrase()
    }

    func avvia() async {
        guard !attivo else { return }
        let parlato = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable s in c.resume(returning: s == .authorized) }
        }
        guard parlato, await AVAudioApplication.requestRecordPermission() else {
            problema = "Servono microfono e riconoscimento vocale: Impostazioni › Jarvis."
            return
        }
        guard let riconoscitore, riconoscitore.isAvailable else {
            problema = "Il riconoscimento vocale non è disponibile in questo momento."
            return
        }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.record, mode: .measurement, options: [.duckOthers])   // .measurement: niente filtri sulla voce, sente tutta la stanza
            try s.setActive(true)
            try Wiretap.collega(motore.inputNode, presa: presa) { [weak self] l in
                let io = self
                Task { @MainActor in
                    guard let io else { return }
                    io.livello = io.livello * 0.6 + l * 0.4
                }
            }
            motore.prepare()
            try motore.start()
        } catch {
            problema = "Il microfono non parte: \(error.localizedDescription)"
            return
        }
        confermato = []
        parziale = ""
        inizio = Date()
        fine = nil
        inPausa = false
        pausaDa = nil
        pause = 0
        attivo = true
        UIApplication.shared.isIdleTimerDisabled = true      // una riunione lunga: lo schermo resta acceso
        nuovaFrase()
    }

    /// Ogni tratto di parlato ha la sua richiesta: quando il riconoscitore chiude una frase (o dopo circa un minuto),
    /// si conferma il testo e se ne apre subito un'altra, così l'ascolto non ha limiti di durata.
    private func nuovaFrase() {
        guard attivo, let riconoscitore else { return }
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.addsPunctuation = true
        r.contextualStrings = ["Discosizer", "Jarvis", "Matteo", "Pier", "Cristina", "Beatrice"]
        if riconoscitore.supportsOnDeviceRecognition, !ProcessInfo.processInfo.isiOSAppOnMac { r.requiresOnDeviceRecognition = true }   // sul Mac il motore locale non risponde (errore 1101): lì si usa quello di Apple   // tutto sul telefono
        presa.metti(r)
        turno += 1
        let mio = turno
        compito = Wiretap.riconosci(riconoscitore, r) { [weak self] testo, fine in
            let io = self
            Task { @MainActor in io?.risultato(testo, fine: fine, turno: mio) }
        }
    }

    private func risultato(_ testo: String?, fine: Bool, turno mio: Int) {
        guard attivo, mio == turno else { return }
        if let testo { parziale = testo }
        guard fine else { return }
        let chiuso = parziale.trimmingCharacters(in: .whitespacesAndNewlines)
        parziale = ""
        presa.metti(nil)
        compito = nil
        if let c = ComandoVocale.riconosci(chiuso, serveJarvis: true) {
            comando?(c)                       // la frase di comando non entra nel verbale
            // MARK XI: «Jarvis, quella di prima», «mettila da parte»… muovono le sezioni, «Jarvis, apri…» manda il Wiretap dietro e,
            // col Wiretap dietro, «Jarvis, chiudi» vale per la sezione davanti: la registrazione continua, se il comando non l'ha
            // fermata (la vista del Wiretap ferma da sé quando serve). Le dettature (Messaggi, Studio) come prima.
            if attivo, comando != nil || c.navigaSezioni { nuovaFrase() }
            return
        }
        if !chiuso.isEmpty { confermato.append(chiuso) }
        nuovaFrase()
    }

    func ferma() {
        guard attivo else { return }
        if let p = pausaDa { pause += Date().timeIntervalSince(p) }
        pausaDa = nil
        inPausa = false
        attivo = false
        fine = Date()
        turno += 1
        presa.metti(nil)?.endAudio()
        compito?.finish()
        compito = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        let chiuso = parziale.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chiuso.isEmpty { confermato.append(chiuso) }
        parziale = ""
        livello = 0
        UIApplication.shared.isIdleTimerDisabled = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancella() {
        ferma()
        confermato = []
        inizio = nil
    }

    // MARK: Fuori dal thread principale

    /// Il microfono versa l'audio nella richiesta del momento (che cambia a ogni frase) e misura il volume.
    nonisolated private static func collega(_ input: AVAudioInputNode, presa: PresaRichiesta,
                                            livello: @escaping @Sendable (Float) -> Void) throws {
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Wiretap", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio"])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: formato) { buffer, _ in
            presa.attuale()?.append(buffer)
            guard let canale = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var somma: Float = 0
            for k in stride(from: 0, to: n, by: 8) { somma += canale[k] * canale[k] }
            let rms = sqrt(somma / Float(max(1, n / 8)))
            livello(min(1, rms * 12))
        }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in
            esito(ris?.bestTranscription.formattedString, (ris?.isFinal ?? false) || err != nil)
        }
    }
}

/// La richiesta di riconoscimento in uso, condivisa tra il microfono (thread audio) e l'app.
nonisolated final class PresaRichiesta: @unchecked Sendable {
    private let lucchetto = NSLock()
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?

    /// Mette la nuova richiesta e restituisce quella vecchia.
    @discardableResult
    func metti(_ r: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lucchetto.lock(); defer { lucchetto.unlock() }
        let vecchia = richiesta
        richiesta = r
        return vecchia
    }

    func attuale() -> SFSpeechAudioBufferRecognitionRequest? {
        lucchetto.lock(); defer { lucchetto.unlock() }
        return richiesta
    }
}

/// L'onda del Wiretap: barre che seguono il volume della stanza.
struct OndaWiretap: View {
    let livello: Float
    let attivo: Bool
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: dietro (MARK XI) registra ancora, ma l'onda non si disegna
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !attivo || dietro)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let barre = 28
                let passo = size.width / CGFloat(barre)
                for k in 0..<barre {
                    let onda = (sin(t * 6 + Double(k) * 0.55) + 1) / 2
                    let h = max(2, size.height * CGFloat(Double(attivo ? livello : 0) * (0.35 + 0.65 * onda)))
                    let r = CGRect(x: CGFloat(k) * passo + passo * 0.2, y: (size.height - h) / 2, width: passo * 0.6, height: h)
                    gc.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(attivo ? .red.opacity(0.85) : Color.ciano.opacity(0.3)))
                }
            }
        }
    }
}
#endif
