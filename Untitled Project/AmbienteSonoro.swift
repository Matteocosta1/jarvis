#if os(iOS)
@preconcurrency import AVFoundation
import SoundAnalysis

/// Capisce che aria tira intorno al signore: con il classificatore di suoni dell'iPhone (sul telefono, senza rete)
/// riconosce folla, chiacchiericcio, musica, TV. Se c'è confusione, JARVIS smette di rispondere a qualsiasi frase
/// e torna al solo «Jarvis» (e mentre parla si fa interrompere solo dalle parole d'ordine); quando torna la calma,
/// si torna a parlargli liberamente. Il giudizio dura qualche secondo dopo l'ultimo rumore, così non va avanti e indietro.
nonisolated final class AmbienteSonoro: NSObject, SNResultsObserving, @unchecked Sendable {
    static let condiviso = AmbienteSonoro()

    private let lock = NSLock()
    private var confusioneFino = Date.distantPast
    private var suonaJarvis = false                    // Mac: JARVIS sta parlando o suona l'avvio (stesso altoparlante, stesso microfono)
    private var suonaJarvisFino = Date.distantPast     // e la coda del suono, che il microfono sente ancora un attimo
    // 12 nov (P2): la voce del signore, non il suo contenuto: quando ha riso, sospirato o sussurrato (per il «come parla» del cervello)
    private var ultimaRisata = Date.distantPast
    private var ultimoSospiro = Date.distantPast
    private var ultimoSussurro = Date.distantPast
    private var jarvisRideFino = Date.distantPast     // JARVIS sta ridendo lui («[laughs]»): quella risata non è del signore

    /// Mac: la musica d'avvio e la voce di JARVIS escono dall'altoparlante del Mac e rientrano dal suo microfono.
    /// Il classificatore le prenderebbe per «musica» o «voce sintetica» e renderebbe JARVIS sordo per 12 secondi
    /// proprio dopo l'avvio e dopo ogni risposta: mentre suona lui (e per un secondo e mezzo dopo) non si giudica.
    func jarvisSuona(_ attivo: Bool) {
        lock.lock()
        if suonaJarvis && !attivo { suonaJarvisFino = Date().addingTimeInterval(1.5) }
        suonaJarvis = attivo
        lock.unlock()
    }

    /// Le etichette del classificatore di Apple che indicano altre voci o suoni con parole intorno.
    /// 12 nov (revisione del dialogo, errore 2): «laughter» e «cheering» non stanno più qui da soli. Una risata del signore (a una battuta
    /// di JARVIS) faceva credere a «gente o TV intorno» per 12 secondi: il seguito senza «Jarvis» veniva ignorato o rallentato.
    /// Risate e applausi contano come folla solo se c'è anche la folla.
    private static let segnali = ["crowd", "chatter", "babble", "hubbub", "speech_synthesizer", "music", "singing",
                                  "television", "radio", "choir", "children_shouting"]
    private static let gente = ["crowd", "chatter", "babble", "hubbub"]
    private static let risate = ["laughter", "giggling", "chuckle_chortle", "belly_laugh", "snicker"]

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

    /// 12 nov (P2): JARVIS sta per dire una frase con una risata sua («[laughs]»): per qualche secondo le risate non sono del signore.
    func jarvisRide(per secondi: TimeInterval) {
        lock.lock(); jarvisRideFino = max(jarvisRideFino, Date().addingTimeInterval(secondi)); lock.unlock()
    }

    /// 12 nov (P2): come ha usato la voce il signore nella frase cominciata a `inizio` (per la riga «come parla» del cervello): una
    /// risata o un sospiro poco prima o mentre parlava (da 6 secondi prima), un sussurro mentre parlava. Il sussurro lo conferma chi
    /// chiama, con l'altezza della voce (si sussurra senza voce), e solo allora va nelle note.
    func segnaliVoce(inizio: Date) -> (note: [String], sussurra: Bool) {
        lock.lock(); defer { lock.unlock() }
        let prima = inizio.addingTimeInterval(-6)
        var note: [String] = []
        if ultimaRisata >= prima { note.append("ha appena riso") }
        if ultimoSospiro >= prima { note.append("ha sospirato") }
        return (note, ultimoSussurro >= inizio)
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        // le voci dei bambini («baby_laughter», «baby_crying») non sono le sue
        func fiducia(_ etichette: [String]) -> Double {
            r.classifications.filter { c in !c.identifier.hasPrefix("baby") && etichette.contains(where: { c.identifier.contains($0) }) }
                .map(\.confidence).max() ?? 0
        }
        let folla = fiducia(AmbienteSonoro.gente)
        let risata = fiducia(AmbienteSonoro.risate)
        let rumoroso = r.classifications.contains { c in
            c.confidence > 0.45 && AmbienteSonoro.segnali.contains(where: { c.identifier.contains($0) })
        } || (folla > 0.3 && (risata > 0.45 || fiducia(["cheering"]) > 0.45))
        let adesso = Date()
        lock.lock()
        let suoNoMio = !(suonaJarvis || adesso < suonaJarvisFino)
        if rumoroso && suoNoMio { confusioneFino = adesso.addingTimeInterval(12) }
        if suoNoMio && folla < 0.3 {
            // la sua voce (non la stanza, non JARVIS): una risata, un sospiro, un sussurro
            if risata > 0.5 && adesso >= jarvisRideFino { ultimaRisata = adesso }
            if fiducia(["sigh"]) > 0.5 { ultimoSospiro = adesso }
            if fiducia(["whispering"]) > 0.55 { ultimoSussurro = adesso }
        }
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
