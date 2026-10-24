import SwiftUI
import WatchKit
import AVFoundation
import WatchConnectivity
import Combine

/// La Sentinella vista dal polso: l'iPhone fa da telecamera, l'orologio riceve gli allarmi,
/// mostra il fotogramma, guarda la stanza quasi in diretta e può disattivare la sentinella.
/// Tenendo aperta la pagina Sentinella, l'app resta sveglia anche col polso abbassato (fino a un'ora),
/// così l'allarme arriva subito.
@MainActor
final class SentinellaOrologio: NSObject, ObservableObject {
    static let condiviso = SentinellaOrologio()

    struct Allarme: Identifiable {
        let id = UUID()
        let cosa: String
        let quando: Date
        let foto: Data?
    }

    @Published var allarme: Allarme?          // allarme in primo piano (si apre a tutto schermo)
    @Published var ultimo: Allarme?           // l'ultimo, da rivedere nella pagina
    @Published var attiva: Bool?              // nil = non so ancora
    @Published var vista: Data?               // l'ultimo fotogramma di «Guarda ora»
    @Published var notte = false
    @Published var soggetti = 0
    @Published var guardando = false
    @Published var problema: String?

    private var giro: Task<Void, Never>?
    private var sveglia: WKExtendedRuntimeSession?
    private var lettore: AVAudioPlayer?
    private let voce = AVSpeechSynthesizer()
    private var voceInArrivo = false              // la frase dell'allarme si sta scaricando (la sessione è già sua)

    /// Decisione 37 (24 ott): la voce dell'allarme («Perimetro violato, Sir.») è la voce di JARVIS: mentre si scarica o si
    /// sente, i suoni del polso non le cambiano la sessione audio (`SuoniOrologio`).
    var parla: Bool { voceInArrivo || (lettore?.isPlaying ?? false) || voce.isSpeaking }

    // MARK: Dall'iPhone

    /// Un messaggio della sentinella dall'iPhone (già ridotto a valori semplici dal ponte).
    nonisolated static func arrivato(tipo: String, cosa: String?, foto: Data?, attiva: Bool?) {
        Task { @MainActor in
            let s = SentinellaOrologio.condiviso
            switch tipo {
            case "allarme":
                let a = Allarme(cosa: cosa ?? "movimento", quando: Date(), foto: foto)
                s.ultimo = a
                s.allarme = a
                s.attiva = true
                s.suona()
            case "vecchio":
                s.ultimo = Allarme(cosa: cosa ?? "movimento", quando: Date(), foto: foto)
            case "stato":
                s.attiva = attiva
                if attiva == false { s.smettiDiGuardare() }
            default: break
            }
        }
    }

    /// Vibrazione forte (tre colpi) e la voce di JARVIS: «Perimetro violato, Sir.»
    private func suona() {
        let polso = WKInterfaceDevice.current()
        polso.play(.notification)
        Task { @MainActor in
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(650))
                polso.play(.failure)
            }
        }
        let frase = "Perimetro violato, Sir."
        Task { @MainActor in
            voceInArrivo = true
            defer { voceInArrivo = false }               // da qui in poi la voce suona (o non c'è): lo dicono lettore e sintesi
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.playback, mode: .spokenAudio)
            try? s.setActive(true)
            let token = PortachiaviOrologio.leggi()
            if let audio = await JarvisOrologio.scaricaVoce(frase, token: token, indirizzo: ImpostazioniOrologio.indirizzo),
               let p = try? AVAudioPlayer(data: audio), p.play() {
                lettore = p
                return
            }
            let u = AVSpeechUtterance(string: frase)
            u.voice = AVSpeechSynthesisVoice(language: "it-IT")
            voce.speak(u)
        }
    }

    // MARK: Verso l'iPhone

    /// Chiede all'iPhone lo stato e, se è attiva, l'ultimo fotogramma.
    func aggiorna() async {
        let r = await PonteOrologio.condiviso.sentinella("guarda")
        guard let r else {
            problema = "iPhone non raggiungibile: lo tenga a portata di Bluetooth o sulla stessa Wi‑Fi."
            return
        }
        problema = nil
        attiva = r.attiva
        notte = r.notte
        soggetti = r.soggetti
        if let f = r.foto { vista = f }
    }

    /// «Guarda ora»: un fotogramma al secondo circa, finché resta aperta la vista.
    func guarda() {
        guard !guardando else { return }
        guardando = true
        giro = Task { @MainActor in
            while !Task.isCancelled && guardando {
                await aggiorna()
                if attiva == false { break }
                try? await Task.sleep(for: .milliseconds(900))
            }
            guardando = false
        }
    }

    func smettiDiGuardare() {
        guardando = false
        giro?.cancel()
        giro = nil
    }

    func disattiva() async {
        smettiDiGuardare()
        let r = await PonteOrologio.condiviso.sentinella("ferma")
        attiva = r?.attiva ?? attiva
        WKInterfaceDevice.current().play(.success)
    }

    // MARK: Restare svegli

    /// Tiene l'app viva col polso abbassato (sessione «mindfulness», fino a un'ora), così l'allarme arriva subito.
    /// Serve la capacità «Background Modes › Mindfulness» sul target dell'orologio; senza, semplicemente non parte.
    func restaInGuardia() {
        guard sveglia == nil || sveglia?.state == .invalid else { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        s.start()
        sveglia = s
    }

    func smontaGuardia() {
        if sveglia?.state == .running { sveglia?.invalidate() }
        sveglia = nil
    }
}

extension SentinellaOrologio: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in WKInterfaceDevice.current().play(.retry) }   // tra poco scade l'ora di guardia
    }
    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {
        Task { @MainActor in SentinellaOrologio.condiviso.sveglia = nil }
    }
}

// MARK: - La pagina Sentinella sull'orologio

struct VistaSentinellaOrologio: View {
    @ObservedObject private var s = SentinellaOrologio.condiviso
    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
    private var colore: Color { s.notte ? Color(red: 0.35, green: 1, blue: 0.45) : ciano }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(s.attiva == true ? Color.green : (s.attiva == false ? Color.gray : Color.orange))
                        .frame(width: 8, height: 8)
                    Text(s.attiva == true ? (s.notte ? "VISIONE NOTTURNA" : "IN GUARDIA") : (s.attiva == false ? "SPENTA" : "COLLEGO…"))
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                        .foregroundStyle(colore)
                }

                if let f = s.vista, let img = UIImage(data: f) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colore.opacity(0.6), lineWidth: 1))
                        .overlay(alignment: .bottomLeading) {
                            if s.guardando {
                                Text(s.soggetti > 0 ? "SOGGETTI · \(s.soggetti)" : "DIRETTA")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(3).background(s.soggetti > 0 ? Color.red : Color.black.opacity(0.6)).padding(4)
                            }
                        }
                }

                if s.attiva == true {
                    Button { s.guardando ? s.smettiDiGuardare() : s.guarda() } label: {
                        Label(s.guardando ? "Basta guardare" : "Guarda ora", systemImage: s.guardando ? "pause.fill" : "eye")
                    }
                    .tint(colore)
                    Button(role: .destructive) { Task { await s.disattiva() } } label: {
                        Label("Disattiva", systemImage: "shield.slash")
                    }
                } else if s.attiva == false {
                    Text("La accenda dall'iPhone: icona Sentinella, poi appoggi il telefono puntato sulla stanza.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                if let u = s.ultimo {
                    Divider()
                    Text("Ultimo allarme · \(u.quando.formatted(date: .omitted, time: .shortened))")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(u.cosa.prefix(1).uppercased() + u.cosa.dropFirst()).font(.footnote)
                }
                if let p = s.problema { Text(p).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
                Text("Lasci aperta questa pagina: resto in guardia anche col polso abbassato.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Sentinella")
        .aperturaOrologio("Sentinella")
        .task {
            s.restaInGuardia()
            await s.aggiorna()
        }
        .onDisappear { s.smettiDiGuardare() }
    }
}

/// L'allarme a tutto schermo: «PERIMETRO VIOLATO», il fotogramma e «Guarda ora».
struct VistaAllarmeOrologio: View {
    let allarme: SentinellaOrologio.Allarme
    @ObservedObject private var s = SentinellaOrologio.condiviso
    @Environment(\.dismiss) private var chiudi
    @State private var lampo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("PERIMETRO VIOLATO")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.red.opacity(lampo ? 1 : 0.55))
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: lampo)
                Text("\(allarme.cosa.prefix(1).uppercased() + allarme.cosa.dropFirst()) · \(allarme.quando.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                if let f = (s.guardando ? s.vista : nil) ?? allarme.foto, let img = UIImage(data: f) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red, lineWidth: 1.5))
                }
                Button { s.guardando ? s.smettiDiGuardare() : s.guarda() } label: {
                    Label(s.guardando ? "Basta guardare" : "Guarda ora", systemImage: "eye")
                }
                .tint(.red)
                Button(role: .destructive) { Task { await s.disattiva(); chiudi() } } label: {
                    Label("Disattiva", systemImage: "shield.slash")
                }
                Button("Chiudi") { s.smettiDiGuardare(); chiudi() }
            }
        }
        .onAppear { lampo = true }
        .onDisappear { s.smettiDiGuardare() }
    }
}
