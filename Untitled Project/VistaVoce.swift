#if os(iOS)
import SwiftUI
import AVFoundation

/// «La mia voce»: il signore legge qualche frase, JARVIS ne ricava l'impronta e la tiene sul telefono.
/// Serve in mezzo alla confusione: JARVIS risponde alla sua voce e non a quella degli altri.
struct VistaLaMiaVoce: View {
    @AppStorage("riconosciVoce") private var riconosci = true
    @AppStorage("sogliaVoce") private var soglia = 0.79
    @State private var registrata = VoceDelSignore.registrata
    @State private var fase: FaseVoce = .ferma
    @State private var secondi = 0.0
    @State private var esitoProva: String?
    @State private var registratore = Registratore()

    enum FaseVoce { case ferma, registro, calcolo, prova }

    private static let frasi = [
        "Buonasera Jarvis, sono io. Oggi è stata una giornata lunga, ma il lavoro è andato bene.",
        "Mi ricordi di chiamare Matteo domani mattina e di controllare i conti della serata.",
        "Metti un po' di musica, qualcosa di elettronico, e abbassa le luci in salotto.",
        "Che tempo farà questo fine settimana a Milano? Vorrei andare al mare se c'è il sole.",
        "Uno, due, tre, quattro, cinque. Prova, prova. Questa è la mia voce, Jarvis.",
    ]

    var body: some View {
        Form {
            Section {
                Label(registrata ? "Impronta registrata" : "Nessuna impronta", systemImage: registrata ? "checkmark.seal.fill" : "waveform")
                    .foregroundStyle(registrata ? Color.ciano : Color.secondary)
                if registrata {
                    Toggle("Riconosci la mia voce nella confusione", isOn: $riconosci)
                }
            } footer: {
                Text("Quando intorno c'è folla, musica o TV, JARVIS risponde solo alla sua voce. Nella calma non controlla nulla. L'impronta resta su questo iPhone.")
            }

            Section {
                if fase == .registro {
                    ForEach(Self.frasi, id: \.self) { Text($0).font(.callout) }
                    ProgressView(value: min(secondi, 20), total: 20) { Text("Legga ad alta voce, con calma · \(Int(secondi)) s") }
                    Button("Ho finito") { Task { await fine() } }.disabled(secondi < 8)
                } else if fase == .calcolo {
                    HStack { ProgressView(); Text("Calcolo l'impronta…") }
                } else {
                    Button(registrata ? "Registra di nuovo" : "Registra la mia voce") { avvia(prova: false) }
                }
            } header: { Text("Registrazione") } footer: {
                Text("Circa 20 secondi: legga le frasi che compaiono, con la voce di sempre, in un posto tranquillo.")
            }

            if registrata {
                Section {
                    if fase == .prova {
                        HStack { ProgressView(); Text("Parli per 3 secondi…") }
                    } else {
                        Button("Prova: parlo io") { avvia(prova: true) }
                    }
                    if let esitoProva { Text(esitoProva).font(.callout) }
                    VStack(alignment: .leading) {
                        Text("Severità: \(Int(soglia * 100))").font(.callout)
                        Slider(value: $soglia, in: 0.60...0.85, step: 0.01)
                    }
                } header: { Text("Prova e taratura") } footer: {
                    Text("La prova mostra quanto la voce somiglia all'impronta. Se la riconosce poco, abbassi la severità; se risponde anche agli altri, la alzi.")
                }
                Section {
                    Button("Cancella l'impronta", role: .destructive) {
                        VoceDelSignore.impronta = nil
                        registrata = false
                        esitoProva = nil
                    }
                }
            }
        }
        .navigationTitle("La mia voce")
        .onDisappear { registratore.ferma() }
    }

    private func avvia(prova: Bool) {
        esitoProva = nil
        secondi = 0
        guard registratore.avvia() else { esitoProva = "Microfono non disponibile."; return }
        fase = prova ? .prova : .registro
        Task {
            while fase == .registro || fase == .prova {
                try? await Task.sleep(for: .milliseconds(250))
                secondi += 0.25
                if fase == .prova && secondi >= 3 { await fineProva(); return }
                if fase == .registro && secondi >= 20 { await fine(); return }
            }
        }
    }

    private func fine() async {
        guard fase == .registro else { return }
        fase = .calcolo
        let audio = registratore.ferma()
        let e = await Task.detached(priority: .userInitiated) { ModelloVoce.condiviso.impronta(audio) }.value
        if let e {
            VoceDelSignore.impronta = e
            registrata = true
            esitoProva = "Fatto: la sua voce è registrata."
        } else {
            esitoProva = "Non sono riuscito a ricavare l'impronta: riprovi parlando un po' più a lungo."
        }
        fase = .ferma
    }

    private func fineProva() async {
        fase = .calcolo
        let audio = registratore.ferma()
        let mia = VoceDelSignore.impronta
        let e = await Task.detached(priority: .userInitiated) { ModelloVoce.condiviso.impronta(audio) }.value
        if let e, let mia {
            let s = ModelloVoce.somiglianza(e, mia)
            esitoProva = "Somiglianza \(Int(s * 100)) su 100 (soglia \(Int(soglia * 100))): " + (Double(s) >= soglia ? "è lei." : "non la riconosco.")
        } else {
            esitoProva = "Troppo corto o troppo silenzioso: riprovi."
        }
        fase = .ferma
    }
}

/// Registra il microfono e restituisce il parlato a 16 kHz.
final class Registratore {
    private let motore = AVAudioEngine()
    private let registro = RegistroLungo()

    func avvia() -> Bool {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try s.setActive(true)
            registro.svuota()
            try Registratore.collega(motore.inputNode, registro)
            motore.prepare()
            try motore.start()
            return true
        } catch { return false }
    }

    @discardableResult
    func ferma() -> [Float] {
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        return registro.a16k()
    }

    nonisolated private static func collega(_ input: AVAudioInputNode, _ r: RegistroLungo) throws {
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else { throw NSError(domain: "Voce", code: 1) }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: formato) { buffer, _ in r.scrivi(buffer) }
    }
}

/// Tutto il parlato della registrazione (fino a 30 s).
nonisolated final class RegistroLungo: @unchecked Sendable {
    private let lock = NSLock()
    private var campioni: [Float] = []
    private var frequenza: Double = 48_000

    func scrivi(_ buffer: AVAudioPCMBuffer) {
        guard let c = buffer.floatChannelData?[0] else { return }
        lock.lock()
        frequenza = buffer.format.sampleRate
        if campioni.count < Int(frequenza * 30) {
            campioni.append(contentsOf: UnsafeBufferPointer(start: c, count: Int(buffer.frameLength)))
        }
        lock.unlock()
    }

    func svuota() { lock.lock(); campioni.removeAll(); lock.unlock() }

    func a16k() -> [Float] {
        lock.lock(); let x = campioni, fr = frequenza; lock.unlock()
        return RegistroMicrofono.a16k(x, da: fr)
    }
}
#endif
