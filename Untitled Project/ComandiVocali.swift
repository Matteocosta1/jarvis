import Foundation
#if os(iOS)
import AVFoundation
import Speech
#endif

/// I reparti che si aprono a voce.
enum Reparto: String, Identifiable, Equatable {
    // INTELLIGENCE e sensi
    case sentinella, occhi, giro, profiler, wiretap, cucina, scanner
    // le schede della corona
    case diario, sonno, cuore, vitals, confidente, allenatore, bea
    case briefing, meteo, email, spesa
    case shazam, foto
    case ricordi, interprete, browser, serata, messaggi, telefono
    // SISTEMI
    case github, supabase, archivio
    var id: String { rawValue }

    /// La frase di JARVIS quando apre il reparto (il Wiretap tace: registrerebbe sé stesso; le schede parlano da sole).
    var annuncio: String? {
        switch self {
        case .sentinella: return "Sentinella in posizione, Sir."
        case .occhi: return "Occhi aperti, Sir."
        case .giro: return "Sistemi ottici attivi. Cinque secondi, Sir: muova pure, cerco di non soffrire il mal di mare."
        case .profiler: return "Profiler pronto. Inquadri il soggetto."
        case .cucina: return "Cucina. Inquadri frigo, dispensa o piatto, Sir."
        case .scanner: return "Scanner pronto. Inquadri il codice a barre, Sir."
        case .wiretap: return nil
        case .diario: return "Il diario, Sir."
        case .sonno: return "Il suo sonno, Sir."
        case .cuore: return "Il suo cuore, Sir."
        case .vitals: return "Vitals, Sir."
        case .confidente: return "Confidente. La ascolto, Sir."
        case .allenatore: return "Allenatore pronto, Sir."
        case .bea: return "Bea, Sir."
        case .briefing: return "Il briefing, Sir."
        case .meteo: return "Il meteo, Sir."
        case .email: return "La posta, Sir."
        case .spesa: return "La lista della spesa, Sir."
        case .shazam: return "Shazam. Faccia sentire, Sir."
        case .foto: return "Le sue foto, Sir."
        case .ricordi: return "I ricordi, Sir."
        case .interprete: return "Interprete. In che lingua, Sir?"
        case .browser: return "Browser, Sir."
        case .serata: return "I conti della serata, Sir."
        case .messaggi: return "Messaggi, Sir. A chi scriviamo?"
        case .telefono: return "Telefono, Sir."
        case .github: return "Il cantiere su GitHub, Sir."
        case .supabase: return "Sala macchine, Sir."
        case .archivio: return "L'archivio, Sir."
        }
    }
}

/// I comandi vocali di JARVIS: «attiva la Sentinella», «apri il Wiretap», «fammi un profilo», «fai un giro», «torna».
/// Riconosce solo frasi brevi con un verbo di comando, così le domande normali vanno al cervello come sempre.
enum ComandoVocale: Equatable {
    case apri(Reparto)
    case torna

    /// `serveJarvis`: dentro un reparto il comando deve cominciare con «Jarvis» (lì intorno parlano anche altri).
    static func riconosci(_ frase: String, serveJarvis: Bool = false) -> ComandoVocale? {
        var t = frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        // via il richiamo iniziale: «Jarvis», «ehi Jarvis», «ok Jarvis»
        var chiamato = false
        while let p = t.first, ["ehi", "ok", "hey", "jarvis", "giarvis", "jervis"].contains(p) {
            if p != "ehi" && p != "ok" && p != "hey" { chiamato = true }
            t.removeFirst()
        }
        if serveJarvis && !chiamato { return nil }
        guard !t.isEmpty, t.count <= 8 else { return nil }
        let s = " " + t.joined(separator: " ") + " "
        func c(_ x: String) -> Bool { s.contains(x) }

        // tornare indietro / chiudere il reparto
        if t.count <= 3, ["torna", "indietro", "chiudi", "esci", "basta"].contains(t[0]) { return .torna }

        let verbi = ["attiva", "apri", "avvia", "accendi", "lancia", "metti", "vai", "passa", "fammi", "fai", "inizia", "modalita", "parti", "entra"]
        let comanda = t.contains(where: { verbi.contains($0) }) || t.count <= 2

        if c(" sentinella ") && comanda { return .apri(.sentinella) }
        if (c(" wiretap ") || c(" wire tap ") || c(" waiter tap ") || c(" intercett")) && comanda { return .apri(.wiretap) }
        if (c(" profiler ") || c(" profilo ") || c(" profila ")) && comanda { return .apri(.profiler) }
        if c(" fai un giro ") || c(" fammi un giro ") || ((c(" giro ") || c(" video ")) && comanda && c(" occhi ")) || c(" modalita video ") {
            return .apri(.giro)
        }
        if c(" occhi ") && comanda { return .apri(.occhi) }
        if c(" cucina ") && comanda { return .apri(.cucina) }
        if (c(" scanner ") || c(" scansiona ") || c(" codice a barre ") || c(" etichetta ") || c(" yuka ")) && comanda { return .apri(.scanner) }

        // le schede: «apri il diario», «fammi vedere il sonno», «vai al meteo», «mostra la posta», «lista della spesa»
        let schede: [(Reparto, [String])] = [
            (.diario, [" diario "]), (.sonno, [" sonno ", " dormito "]), (.cuore, [" cuore ", " battito "]), (.vitals, [" vitals ", " vitali ", " parametri "]),
            (.confidente, [" confidente "]), (.bea, [" reparto bea ", " scheda di bea ", " sezione bea "]), (.allenatore, [" allenatore ", " allenamento "]), (.briefing, [" briefing ", " brifing "]),
            (.meteo, [" meteo ", " tempo "]), (.email, [" email ", " mail ", " posta "]), (.spesa, [" spesa "]),
            (.shazam, [" shazam "]), (.foto, [" foto ", " galleria "]), (.ricordi, [" ricordi "]),
            (.interprete, [" interprete ", " traduttore "]), (.browser, [" browser ", " internet ", " navigatore "]), (.serata, [" serata "]),
            (.messaggi, [" messaggi ", " whatsapp ", " imessage "]), (.telefono, [" telefono ", " tastiera ", " rubrica "]),
            (.github, [" github ", " git hub ", " ghitab ", " repository ", " cantiere "]), (.supabase, [" supabase ", " supa base ", " sala macchine ", " database "]),
            (.archivio, [" archivio ", " cloud ", " disco rigido "]),
        ]
        // «apri Bea», «vai a Bea»: solo così, corto; «chiama Bea» o «scrivi a Bea» restano a JARVIS
        if (c(" bea ") || c(" beatrice ")) && t.count <= 4 && t.contains(where: { ["apri", "mostra", "mostrami", "vai", "entra"].contains($0) }) {
            return .apri(.bea)
        }
        let mostra = comanda || t.contains(where: { ["mostra", "mostrami", "vedere", "vediamo", "guardiamo", "controlla", "controlliamo"].contains($0) })
        if mostra {
            for (reparto, chiavi) in schede where chiavi.contains(where: c) { return .apri(reparto) }
        }
        return nil
    }
}

#if os(iOS)
/// Un orecchio per i comandi dentro un reparto (la Sentinella): ascolta la stanza in continuo,
/// e quando sente «Jarvis, …» seguito da un comando lo consegna. Tutto sul telefono.
@MainActor
final class OrecchioComandi {
    var comando: ((ComandoVocale) -> Void)?

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let presa = PresaRichiesta()
    private var compito: SFSpeechRecognitionTask?
    private var turno = 0
    private var acceso = false
    private var ultimoTesto = ""
    private var silenzio: Timer?

    func avvia() {
        guard !acceso, let riconoscitore, riconoscitore.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try s.setActive(true)
            try OrecchioComandi.collega(motore.inputNode, presa: presa)
            motore.prepare()
            try motore.start()
        } catch { return }
        acceso = true
        nuovaFrase()
    }

    func ferma() {
        guard acceso else { return }
        acceso = false
        turno += 1
        silenzio?.invalidate()
        presa.metti(nil)?.endAudio()
        compito?.cancel()
        compito = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
    }

    private func nuovaFrase() {
        guard acceso, let riconoscitore else { return }
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.contextualStrings = ["Jarvis", "Sentinella", "Wiretap", "Profiler", "Occhi", "Diario", "Vitals", "Briefing", "Shazam", "Cucina", "Scanner"]
        if riconoscitore.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
        presa.metti(r)
        turno += 1
        let mio = turno
        ultimoTesto = ""
        compito = OrecchioComandi.riconosci(riconoscitore, r) { [weak self] testo, fine in
            let io = self
            Task { @MainActor in io?.risultato(testo, fine: fine, turno: mio) }
        }
    }

    private func risultato(_ testo: String?, fine: Bool, turno mio: Int) {
        guard acceso, mio == turno else { return }
        if let testo, !testo.isEmpty {
            ultimoTesto = testo
            // la frase è finita dopo un secondo di silenzio
            silenzio?.invalidate()
            silenzio = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                let io = self
                Task { @MainActor in io?.valuta(turno: mio) }
            }
        }
        if fine { valuta(turno: mio) }
    }

    private func valuta(turno mio: Int) {
        guard acceso, mio == turno else { return }
        silenzio?.invalidate()
        let frase = ultimoTesto
        presa.metti(nil)?.endAudio()
        compito?.cancel()
        compito = nil
        if let c = ComandoVocale.riconosci(frase, serveJarvis: true) {
            comando?(c)
        }
        nuovaFrase()       // si continua ad ascoltare
    }

    nonisolated private static func collega(_ input: AVAudioInputNode, presa: PresaRichiesta) throws {
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "OrecchioComandi", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio"])
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, _ in presa.attuale()?.append(buffer) }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in
            esito(ris?.bestTranscription.formattedString, (ris?.isFinal ?? false) || err != nil)
        }
    }
}
#endif
