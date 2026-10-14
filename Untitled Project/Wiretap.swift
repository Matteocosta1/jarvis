#if os(iOS)
import SwiftUI
import AVFoundation
import Speech
import UIKit
import Combine

/// WIRETAP (reparto INTELLIGENCE): l'iPhone ascolta una riunione e la trascrive mentre si parla,
/// tutto sul telefono. Alla fine JARVIS ne fa il verbale: di cosa si è parlato, cosa si è deciso, chi fa cosa.
/// L'audio non viene salvato: resta solo il testo. Buona educazione (e a volte la legge): avvisare i presenti.
@MainActor
final class Wiretap: ObservableObject {
    @Published private(set) var attivo = false
    @Published private(set) var confermato: [String] = []      // frasi già chiuse
    @Published private(set) var parziale = ""                 // la frase che si sta ancora riconoscendo
    @Published private(set) var livello: Float = 0            // 0…1, per l'onda sullo schermo
    @Published private(set) var inizio: Date?
    @Published var problema: String?
    /// Un comando detto durante la registrazione («Jarvis, torna», «Jarvis, apri la Sentinella»): non finisce nel verbale.
    var comando: ((ComandoVocale) -> Void)?

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let presa = PresaRichiesta()
    private var compito: SFSpeechRecognitionTask?
    private var turno = 0

    var testo: String {
        (confermato + (parziale.isEmpty ? [] : [parziale])).joined(separator: " ")
    }
    var minuti: Int { inizio.map { max(1, Int(Date().timeIntervalSince($0) / 60 + 0.5)) } ?? 0 }

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
        if riconoscitore.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }   // tutto sul telefono
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
            return
        }
        if !chiuso.isEmpty { confermato.append(chiuso) }
        nuovaFrase()
    }

    func ferma() {
        guard attivo else { return }
        attivo = false
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

// MARK: - La schermata

struct VistaWiretap: View {
    /// Manda la trascrizione a JARVIS per il verbale (chiude la pagina).
    let verbale: (String, Int) -> Void
    let chiudi: () -> Void
    /// Comandi a voce durante l'intercettazione: «Jarvis, torna» chiude (e se c'è testo, prepara il verbale).
    var comando: (ComandoVocale) -> Void = { _ in }

    @StateObject private var w = Wiretap()
    @State private var copiato = false

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WIRETAP")
                            .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                        Text(w.attivo ? "INTERCETTAZIONE IN CORSO" : (w.confermato.isEmpty ? "PRONTO" : "REGISTRAZIONE CHIUSA"))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).opacity(0.8)
                    }
                    .foregroundStyle(w.attivo ? Color.red : Color.ciano)
                    Spacer()
                    Button { Suoni.tocco(); w.cancella(); chiudi() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ciano)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("Chiudi")
                }

                // durata e onda
                HStack(spacing: 10) {
                    if let i = w.inizio {
                        TimelineView(.periodic(from: i, by: 1)) { t in
                            let s = Int((w.attivo ? t.date : Date()).timeIntervalSince(i))
                            Text(String(format: "%02d:%02d", s / 60, s % 60))
                                .font(.system(size: 28, weight: .light, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                    OndaWiretap(livello: w.livello, attivo: w.attivo)
                        .frame(height: 36)
                }
                .padding(.top, 4)

                // la trascrizione che scorre
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(w.testo.isEmpty ? (w.attivo ? "In ascolto…" : "Premi REC: trascrivo tutto quello che si dice nella stanza. L'audio non viene salvato, solo il testo.") : w.testo)
                            .font(.system(size: 15))
                            .foregroundStyle(w.testo.isEmpty ? Color.tenue : Color(red: 0.85, green: 0.93, blue: 0.97))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .id("fine")
                    }
                    .background(Color.ciano.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.3), lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onChange(of: w.testo) { withAnimation { proxy.scrollTo("fine", anchor: .bottom) } }
                }

                if let p = w.problema { Text(p).font(.footnote).foregroundStyle(.orange) }

                if w.attivo || w.confermato.isEmpty {
                    Button {
                        Suoni.tocco()
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        if w.attivo { w.ferma() } else { Task { await w.avvia() } }
                    } label: {
                        ZStack {
                            Circle().stroke(Color.red.opacity(0.9), lineWidth: 3).frame(width: 78, height: 78)
                            if w.attivo {
                                RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 30, height: 30)
                            } else {
                                Text("REC").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            }
                        }
                        .shadow(color: .red.opacity(w.attivo ? 0.7 : 0.3), radius: 12)
                    }
                    .buttonStyle(StileStark())
                    .accessibilityLabel(w.attivo ? "Ferma" : "Registra")
                    Text("Avvisi i presenti che sta registrando.")
                        .font(.footnote).foregroundStyle(Color.tenue)
                } else {
                    Button {
                        Suoni.tocco()
                        verbale(w.testo, w.minuti)
                    } label: {
                        Label("Il verbale, JARVIS", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .foregroundStyle(Color.fondo).background(Color.ciano2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(StileStark())
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = w.testo
                            copiato = true
                        } label: {
                            Label(copiato ? "Copiato" : "Copia il testo", systemImage: copiato ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity).frame(height: 42)
                        }
                        Button { Task { await w.avvia() } } label: {
                            Label("Nuova", systemImage: "record.circle").frame(maxWidth: .infinity).frame(height: 42)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ciano)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.5), lineWidth: 0.8))
                }
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            w.comando = { c in
                w.ferma()
                let testo = w.testo
                if c == .torna, !testo.isEmpty { verbale(testo, w.minuti) }    // niente si perde: parte il verbale
                else { comando(c) }
            }
        }
        .onDisappear { w.ferma() }
        .aperturaHUD("Wiretap")
    }
}

/// L'onda del Wiretap: barre che seguono il volume della stanza.
struct OndaWiretap: View {
    let livello: Float
    let attivo: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !attivo)) { ctx in
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
