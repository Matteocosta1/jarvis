#if os(iOS)
import UIKit
import CoreHaptics
import AVFoundation

// MARK: - L'aptica di JARVIS
// Il Taptic Engine suonato come uno strumento: ogni evento ha un istante, un'intensità (quanto forte) e una nitidezza
// (secco o morbido). Le regole: una vibrazione conferma un tocco o un cambio di stato, mai decorazione; suono e
// vibrazione sullo stesso istante; non più di una ogni 100 ms; più l'evento è importante, più si sente.
//
//   click        → la «selezione» di iOS, quasi impercettibile (icone, SISTEMI, cestino, rotella)
//   fotocamera   → un tocco medio e secco: il «clack» dell'obiettivo (Occhi, Cucina, Allenatore, Profiler, Scanner)
//   pronto       → la notifica di successo di Apple, che la mano conosce già come «fatto»
//   svuota       → un tocco morbido che cala, in sincronia con la barra che scende
//   avvio        → una partitura: un tocco quando si chiude ogni gruppo di icone (cinque in tutto), sulla musica
//
// Sul Mac (app «Designed for iPad») non c'è motore aptico: tutto resta in silenzio, senza errori.
@MainActor
enum Aptica {
    private static var motore: CHHapticEngine?
    private static var acceso = false
    private static var ultimoTransitorio = Date.distantPast
    private static let selezione = UISelectionFeedbackGenerator()
    private static let notifica = UINotificationFeedbackGenerator()
    private static let medio = UIImpactFeedbackGenerator(style: .medium)
    private static let morbido = UIImpactFeedbackGenerator(style: .soft)
    private static let forte = UIImpactFeedbackGenerator(style: .heavy)

    static var disponibile: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics && !ProcessInfo.processInfo.isiOSAppOnMac }

    /// Da chiamare all'apertura dell'app: il motore si scalda, così il primo tocco non arriva in ritardo.
    static func prepara() {
        guard disponibile else { return }
        // con il microfono aperto (ascolto all'apertura, richiamo) iOS spegne le vibrazioni dell'app: qui si lasciano passare
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        selezione.prepare(); notifica.prepare(); medio.prepare(); morbido.prepare(); forte.prepare()
        _ = accendi()
    }

    /// Con il microfono aperto iOS spegne le vibrazioni dell'app se il permesso non c'è più (la voce riconfigura la sessione
    /// audio): si rimette prima di ogni vibrazione delle pagine, solo se serve.
    static func permettiColMicrofono() {
        let s = AVAudioSession.sharedInstance()
        if !s.allowHapticsAndSystemSoundsDuringRecording { try? s.setAllowHapticsAndSystemSoundsDuringRecording(true) }
    }

    /// Un colpo secco, con un filo di corpo sotto (0 = solo il colpo).
    private static func colpo(intensita: Float, nitidezza: Float, corpo: Double) -> CHHapticPattern? {
        var eventi = [CHHapticEvent(eventType: .hapticTransient,
                                    parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensita),
                                                 CHHapticEventParameter(parameterID: .hapticSharpness, value: nitidezza)],
                                    relativeTime: 0)]
        if corpo > 0 {
            eventi.append(CHHapticEvent(eventType: .hapticContinuous,
                                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensita * 0.7),
                                                     CHHapticEventParameter(parameterID: .hapticSharpness, value: nitidezza * 0.45)],
                                        relativeTime: 0, duration: corpo))
        }
        return try? CHHapticPattern(events: eventi, parameters: [])
    }

    /// Suona il colpo col motore (o, se non c'è, col generatore forte di iOS).
    private static func suona(intensita: Float, nitidezza: Float, corpo: Double = 0) {
        BattitoMani.ignora(per: 0.5)
        permettiColMicrofono()
        if let m = accendi(), let pat = colpo(intensita: intensita, nitidezza: nitidezza, corpo: corpo), let p = try? m.makePlayer(with: pat) {
            try? p.start(atTime: CHHapticTimeImmediate)
        } else {
            forte.impactOccurred(intensity: CGFloat(intensita))
            forte.prepare()
        }
    }

    // MARK: MARK XI · le pagine (5 nov, il signore: «non c'è il feedback aptico come quando selezioni le pagine con lo swipe up
    // lento di Apple», «più forte»). Prima erano i tocchi «leggero» e «medio» di iOS, che col microfono aperto si perdevano.

    /// Le pagine olografiche compaiono (la pagina sollevata piano si aggancia): un colpo pieno e deciso, con un filo di corpo.
    static func pagine() {
        guard disponibile else { return }
        ultimoTransitorio = Date()
        suona(intensita: 1, nitidezza: 0.75, corpo: 0.06)
    }

    /// Sfogliando, arriva la pagina nuova al centro: un tocco secco e netto.
    static func sfoglia() {
        guard disponibile, libero() else { return }
        suona(intensita: 0.8, nitidezza: 0.85)
    }

    /// La pagina scelta si apre a tutto schermo.
    static func sceltaPagina() {
        guard disponibile, libero() else { return }
        suona(intensita: 0.85, nitidezza: 0.6)
    }

    /// La pagina spinta in su si chiude: il colpo più secco.
    static func chiusaPagina() {
        guard disponibile, libero() else { return }
        suona(intensita: 1, nitidezza: 0.95)
    }

    /// La pagina lanciata vola nel reattore (AGGANCIO): un colpo pieno e morbido alla partenza.
    static func lancioPagina() {
        guard disponibile, libero() else { return }
        suona(intensita: 0.9, nitidezza: 0.35, corpo: 0.05)
    }

    private static func accendi() -> CHHapticEngine? {
        guard disponibile else { return nil }
        if let motore, acceso { return motore }
        do {
            let m = try motore ?? CHHapticEngine()
            m.playsHapticsOnly = true
            m.resetHandler = { Task { @MainActor in acceso = false; _ = accendi() } }       // il sistema l'ha spento: si riaccende al bisogno
            m.stoppedHandler = { _ in Task { @MainActor in acceso = false } }
            try m.start()
            motore = m
            acceso = true
            return m
        } catch {
            acceso = false
            return nil
        }
    }

    /// Non più di un tocco secco ogni 100 ms: due colpi troppo vicini la mano li sente come un ronzio.
    private static func libero() -> Bool {
        let ora = Date()
        guard ora.timeIntervalSince(ultimoTransitorio) > 0.1 else { return false }
        ultimoTransitorio = ora
        return true
    }

    // MARK: I cinque gesti

    /// Click: la selezione fine di iOS.
    static func click() {
        guard disponibile, libero() else { return }
        BattitoMani.ignora(per: 0.5)                     // la vibrazione arriva al microfono come un battito
        selezione.selectionChanged()
        selezione.prepare()
    }

    /// La fotocamera è pronta: un «clack» medio e secco, insieme al suono.
    static func fotocamera() {
        guard disponibile, libero() else { return }
        BattitoMani.ignora(per: 0.5)
        if let m = accendi(), let p = try? m.makePlayer(with: pattern(transitori: [(0, 0.8, 0.9)])) {
            try? p.start(atTime: CHHapticTimeImmediate)
        } else {
            medio.impactOccurred()
        }
    }

    /// Fatto: la notifica di successo di Apple.
    static func pronto() {
        guard disponibile, libero() else { return }
        BattitoMani.ignora(per: 0.8)
        notifica.notificationOccurred(.success)
        notifica.prepare()
    }

    /// La chat si svuota: un tocco morbido che cala per tutta la durata, come la barra che scende da 100 a 0.
    static func svuota(durata: Double) {
        guard disponibile, let m = accendi() else { return }
        let d = max(0.3, durata)
        BattitoMani.ignora(per: d + 0.5)
        let evento = CHHapticEvent(eventType: .hapticContinuous,
                                   parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                                                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)],
                                   relativeTime: 0, duration: d)
        let calo = CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                          controlPoints: [.init(relativeTime: 0, value: 1.0),
                                                          .init(relativeTime: d * 0.7, value: 0.45),
                                                          .init(relativeTime: d, value: 0.0)],
                                          relativeTime: 0)
        let chiusura = CHHapticEvent(eventType: .hapticTransient,
                                     parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                                                  CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)],
                                     relativeTime: d)                                  // «memoria libera»: un punto fermo
        guard let pattern = try? CHHapticPattern(events: [evento, chiusura], parameterCurves: [calo]),
              let p = try? m.makePlayer(with: pattern) else { morbido.impactOccurred(); return }
        try? p.start(atTime: CHHapticTimeImmediate)
    }

    /// L'avvio: un tocco a ogni gruppo di icone completato, sull'istante dell'ultima icona del gruppo.
    /// Cinque tocchi in tutto: la mano sente il caricamento che avanza a reparti, non il ritmo delle icone.
    /// Forti (0,9) e l'ultimo, INTELLIGENCE, al massimo (1,0) con una coda piena: il colpo finale (20 ott, «aptica forte»).
    static func avvio(tempi: [Double]) {
        guard disponibile, let m = accendi(), !tempi.isEmpty else { return }
        BattitoMani.ignora(per: (tempi.max() ?? 0) + 0.6)
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        var eventi: [CHHapticEvent] = []
        for (k, t) in tempi.enumerated() {
            let ultimo = k == tempi.count - 1
            eventi.append(CHHapticEvent(eventType: .hapticTransient,
                                        parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: ultimo ? 1.0 : 0.9),
                                                     CHHapticEventParameter(parameterID: .hapticSharpness, value: ultimo ? 1.0 : 0.8)],
                                        relativeTime: t))
            if ultimo {                                                                // la coda: 120 ms pieni sotto l'ultimo colpo
                eventi.append(CHHapticEvent(eventType: .hapticContinuous,
                                            parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                                                         CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)],
                                            relativeTime: t, duration: 0.12))
            }
        }
        guard let pat = try? CHHapticPattern(events: eventi, parameters: []), let p = try? m.makePlayer(with: pat) else { return }
        try? p.start(atTime: CHHapticTimeImmediate)
        ultimoTransitorio = Date().addingTimeInterval(tempi.last ?? 0)                 // per tutta la sequenza niente altri tocchi sopra
    }

    private static func pattern(transitori: [(Double, Float, Float)]) -> CHHapticPattern {
        let eventi = transitori.map { (t, intensita, nitidezza) in
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensita),
                                       CHHapticEventParameter(parameterID: .hapticSharpness, value: nitidezza)],
                          relativeTime: t)
        }
        return (try? CHHapticPattern(events: eventi, parameters: [])) ?? (try! CHHapticPattern(events: [], parameters: []))
    }
}
#endif
