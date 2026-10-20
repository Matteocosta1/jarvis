#if os(iOS)
import UIKit
import CoreHaptics

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

    static var disponibile: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics && !ProcessInfo.processInfo.isiOSAppOnMac }

    /// Da chiamare all'apertura dell'app: il motore si scalda, così il primo tocco non arriva in ritardo.
    static func prepara() {
        guard disponibile else { return }
        selezione.prepare(); notifica.prepare(); medio.prepare(); morbido.prepare()
        _ = accendi()
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
        selezione.selectionChanged()
        selezione.prepare()
    }

    /// La fotocamera è pronta: un «clack» medio e secco, insieme al suono.
    static func fotocamera() {
        guard disponibile, libero() else { return }
        if let m = accendi(), let p = try? m.makePlayer(with: pattern(transitori: [(0, 0.8, 0.9)])) {
            try? p.start(atTime: CHHapticTimeImmediate)
        } else {
            medio.impactOccurred()
        }
    }

    /// Fatto: la notifica di successo di Apple.
    static func pronto() {
        guard disponibile, libero() else { return }
        notifica.notificationOccurred(.success)
        notifica.prepare()
    }

    /// La chat si svuota: un tocco morbido che cala per tutta la durata, come la barra che scende da 100 a 0.
    static func svuota(durata: Double) {
        guard disponibile, let m = accendi() else { return }
        let d = max(0.3, durata)
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
    /// Crescono piano (0,45 → 0,6) e l'ultimo, INTELLIGENCE, chiude con un tocco più deciso.
    static func avvio(tempi: [Double]) {
        guard disponibile, let m = accendi(), !tempi.isEmpty else { return }
        var eventi: [(Double, Float, Float)] = []
        for (k, t) in tempi.enumerated() {
            let ultimo = k == tempi.count - 1
            let intensita: Float = ultimo ? 0.8 : 0.45 + 0.15 * Float(k) / Float(max(1, tempi.count - 1))
            eventi.append((t, intensita, ultimo ? 0.6 : 0.75))                        // secchi; l'ultimo un filo più pieno
        }
        guard let p = try? m.makePlayer(with: pattern(transitori: eventi)) else { return }
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
