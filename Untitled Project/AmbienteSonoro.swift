#if os(iOS)
import AVFoundation
import SoundAnalysis

/// Capisce che aria tira intorno al signore: con il classificatore di suoni dell'iPhone (sul telefono, senza rete)
/// riconosce folla, chiacchiericcio, musica, TV. Se c'è confusione, JARVIS smette di rispondere a qualsiasi frase
/// e torna al solo «Jarvis» (e mentre parla si fa interrompere solo dalle parole d'ordine); quando torna la calma,
/// si torna a parlargli liberamente. Il giudizio dura qualche secondo dopo l'ultimo rumore, così non va avanti e indietro.
nonisolated final class AmbienteSonoro: NSObject, SNResultsObserving, @unchecked Sendable {
    static let condiviso = AmbienteSonoro()

    private let lock = NSLock()
    private var confusioneFino = Date.distantPast

    /// Le etichette del classificatore di Apple che indicano altre voci o suoni con parole intorno.
    private static let segnali = ["crowd", "chatter", "babble", "hubbub", "speech_synthesizer", "music", "singing",
                                  "television", "radio", "applause", "cheering", "laughter", "choir", "children_shouting"]

    /// Vero se negli ultimi secondi intorno c'era confusione.
    var affollato: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() < confusioneFino
    }

    /// Un analizzatore per il microfono che sta per partire (nil se il classificatore non è disponibile).
    func nuovaAnalisi(formato: AVAudioFormat) -> AnalisiAmbiente? {
        guard let richiesta = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        richiesta.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        richiesta.overlapFactor = 0.5
        let analizzatore = SNAudioStreamAnalyzer(format: formato)
        guard (try? analizzatore.add(richiesta, withObserver: self)) != nil else { return nil }
        return AnalisiAmbiente(analizzatore)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        let rumoroso = r.classifications.contains { c in
            c.confidence > 0.45 && AmbienteSonoro.segnali.contains(where: { c.identifier.contains($0) })
        }
        guard rumoroso else { return }
        lock.lock()
        confusioneFino = Date().addingTimeInterval(12)
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}

/// L'analisi dei suoni di un microfono: riceve i pezzi audio dal tap e li analizza su una coda sua, fuori dal thread audio.
nonisolated final class AnalisiAmbiente: @unchecked Sendable {
    private let analizzatore: SNAudioStreamAnalyzer
    private let coda = DispatchQueue(label: "jarvis.ambiente")

    init(_ a: SNAudioStreamAnalyzer) { analizzatore = a }

    func analizza(_ buffer: AVAudioPCMBuffer, posizione: AVAudioFramePosition) {
        coda.async { [self] in analizzatore.analyze(buffer, atAudioFramePosition: posizione) }
    }
}
#endif
