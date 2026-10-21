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
    case ricordi, interprete, browser, serata, messaggi, telefono, lidar
    // SISTEMI
    case github, supabase, archivio, costi, edith
    // la schermata principale: il menu SISTEMI, le impostazioni, il cestino
    case sistemi, impostazioni, pulisci
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
        case .lidar: return "LiDAR pronto. Muova l'iPhone lungo le pareti, Sir."
        case .github: return "Il cantiere su GitHub, Sir."
        case .supabase: return "Sala macchine, Sir."
        case .archivio: return "L'archivio, Sir."
        case .costi: return "I costi, Sir."
        case .edith: return "EDITH, Sir."
        case .sistemi: return "Sistemi, Sir."
        case .impostazioni: return "Impostazioni, Sir."
        case .pulisci: return nil                     // parla il cestino: carta appallottolata
        }
    }
}

/// I comandi vocali di JARVIS: «attiva la Sentinella», «apri il Wiretap», «fammi un profilo», «fai un giro», «torna».
/// Riconosce solo frasi brevi con un verbo di comando, così le domande normali vanno al cervello come sempre.
enum ComandoVocale: Equatable {
    case apri(Reparto)
    case torna
    case lidar(AzioneLidar)                 // dentro LiDAR: «fine scansione», «quanto è grande?», «salva»…
    case sentinella(AzioneSentinella)       // dentro la Sentinella: «Jarvis, chi è passato?», «Jarvis, schermo nero»
    case interprete(String)                 // «traduci in inglese», «interprete spagnolo»: apre l'Interprete già sulla lingua (codice: en, es…)

    /// I comandi di LiDAR (21 ott, chiesti dal signore).
    enum AzioneLidar: Equatable { case fine, misure, capienza, salva, tre }
    /// I comandi dentro la Sentinella: gli stessi due tasti in alto.
    enum AzioneSentinella: Equatable { case registro, schermoNero }

    /// Le lingue dell'Interprete come si dicono a voce (gli stessi codici di `Lingua.tutte`).
    static let lingueAVoce: [(codice: String, parole: [String])] = [
        ("en", ["inglese"]), ("es", ["spagnolo"]), ("fr", ["francese"]), ("de", ["tedesco"]), ("pt", ["portoghese", "brasiliano"]),
        ("zh", ["cinese"]), ("ja", ["giapponese"]), ("ar", ["arabo"]), ("ru", ["russo"]), ("tr", ["turco"]), ("ro", ["rumeno"]),
        ("nl", ["olandese"]), ("pl", ["polacco"]), ("el", ["greco"]), ("hi", ["hindi", "indiano"]), ("uk", ["ucraino"]),
    ]

    /// `serveJarvis`: dentro un reparto il comando deve cominciare con «Jarvis» (lì intorno parlano anche altri).
    /// `dentro`: il reparto aperto, per i comandi che valgono solo lì («salva» in LiDAR, «chi è passato?» nella Sentinella).
    static func riconosci(_ frase: String, serveJarvis: Bool = false, dentro: Reparto? = nil) -> ComandoVocale? {
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
        // da soli («chiudi», «indietro»…) o in poche frasi esatte: «torna a casa» e «chiudi Spotify» restano a JARVIS
        if t.count == 1, ["torna", "indietro", "chiudi", "esci", "basta"].contains(t[0]) { return .torna }
        if [" torna indietro ", " chiudi tutto ", " torna alla home ", " torna alla schermata principale ", " chiudi la scheda ",
            " chiudi questa scheda ", " esci da qui "].contains(where: { s == $0 }) { return .torna }
        // «chiudi l'app», «chiudi la sezione», «chiudi qui», oppure «chiudi» + il nome di una sezione di JARVIS («chiudi LiDAR», «chiudi il meteo»).
        // «chiudi Spotify», «chiudi la porta», «chiudi la musica» restano a JARVIS.
        if t[0] == "chiudi" || t[0] == "esci", t.count <= 4 {
            let resto = Array(t.dropFirst()).filter { !["l", "la", "il", "lo", "le", "i", "gli", "da", "dal", "dalla", "dallo", "questa", "questo"].contains($0) }
            let generiche: Set<String> = ["app", "applicazione", "sezione", "scheda", "schermata", "pagina", "qui", "tutto", "scansione"]
            let sezioni: Set<String> = ["lidar", "laidar", "planimetria", "occhi", "fotocamera", "camera", "cucina", "meteo", "tempo", "browser", "internet",
                                        "impostazioni", "sistemi", "costi", "edith", "edit", "diario", "sonno", "cuore", "vitals", "briefing", "posta",
                                        "email", "mail", "spesa", "foto", "galleria", "serata", "messaggi", "telefono", "rubrica", "bea", "ricordi",
                                        "confidente", "github", "supabase", "archivio", "scanner", "profiler"]
            if !resto.isEmpty, resto.allSatisfy({ generiche.contains($0) || sezioni.contains($0) }) { return .torna }
        }
        // «spegni la Sentinella», «ferma il Wiretap»: come «torna» (il Wiretap prepara comunque il verbale)
        if t.count <= 4, ["spegni", "disattiva", "ferma"].contains(t[0]),
           c(" sentinella ") || c(" wiretap ") || c(" wire tap ") || c(" registrazione ") { return .torna }

        // i comandi che valgono solo dentro un reparto
        switch dentro {
        case .lidar?:
            if t.count <= 5 {
                if c(" quante persone ") || c(" capienza ") || c(" quanta gente ") || c(" ci stanno ") { return .lidar(.capienza) }
                if c(" quanto e grande ") || c(" quanto misura ") || c(" quanti metri ") || c(" metri quadri ") || c(" superficie ") || c(" misure ") { return .lidar(.misure) }
                if c(" 3d ") || c(" tre d ") || c(" tre di ") || c(" modello ") || c(" ologramma ") { return .lidar(.tre) }
                if c(" salva ") || c(" salvala ") || c(" salvalo ") || c(" salvami ") { return .lidar(.salva) }
                if c(" fine ") || c(" finito ") || c(" ho finito ") || c(" termina ") { return .lidar(.fine) }   // «stop» no: è il «zitto» di sempre
            }
        case .sentinella?:
            if c(" chi e passato ") || c(" chi c e stato ") || c(" registro ") || c(" cosa hai visto ") { return .sentinella(.registro) }
            if c(" schermo nero ") || c(" oscura ") || c(" spegni lo schermo ") || c(" buio ") { return .sentinella(.schermoNero) }
        case .wiretap?:
            if t.count <= 4 && (c(" verbale ") || c(" fine riunione ") || c(" riunione finita ")) { return .torna }   // il verbale parte da «torna»
        default: break
        }

        // Interprete già sulla lingua: «traduci in inglese», «interprete spagnolo», «fammi da interprete in francese».
        // Solo frasi corte: «traduci in inglese buongiorno a tutti» resta una domanda per il cervello.
        if t.count <= 5, c(" traduci ") || c(" traduttore ") || c(" interprete ") {
            for l in lingueAVoce where l.parole.contains(where: { t.last == $0 }) { return .interprete(l.codice) }
        }

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
        // LiDAR: «scansiona la stanza», «misura la stanza», «planimetria»: prima dello Scanner, che prende «scansiona»
        let verboStanza = c(" scansiona ") || c(" misura ") || c(" scansione ")
        if ((c(" lidar ") || c(" laidar ") || c(" lai dar ") || c(" planimetria ") || c(" pianta della stanza ")) && (comanda || verboStanza))
            || ((c(" stanza ") || c(" sala ") || c(" locale ")) && verboStanza) {
            return .apri(.lidar)
        }
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
        // le sezioni nuove solo con un verbo: «apri i costi», «mostrami EDITH», «vai alle impostazioni» («che costi?» resta a JARVIS)
        let nuove: [(Reparto, [String])] = [
            (.costi, [" costi ", " consumi "]),
            (.edith, [" edith ", " editt ", " edit ", " edid ", " edyth ", " editth ", " editte ", " editti ", " eddith ", " edite ",
                      " e dit ", " e dith ", " idit ", " idith ", " hedith ", " heidit ", " edit h "]),
            (.sistemi, [" sistemi "]), (.impostazioni, [" impostazioni ", " settaggi "]),
        ]
        let conVerbo = t.contains(where: { ["apri", "mostra", "mostrami", "vai", "entra", "fammi"].contains($0) })
        if conVerbo { for (reparto, chiavi) in nuove where chiavi.contains(where: c) { return .apri(reparto) } }
        // «apri Bea», «vai a Bea»: solo così, corto; «chiama Bea» o «scrivi a Bea» restano a JARVIS
        if (c(" bea ") || c(" beatrice ")) && t.count <= 4 && t.contains(where: { ["apri", "mostra", "mostrami", "vai", "entra"].contains($0) }) {
            return .apri(.bea)
        }
        // il cestino: «pulisci», «svuota la chat», «cancella la conversazione»
        // solo frasi esatte: «pulisci il bagno» o «cancella la chat con Bea» restano a JARVIS
        if [" pulisci ", " pulisci la chat ", " pulisci tutto ", " pulisci lo schermo ", " svuota la chat ", " svuota la conversazione ",
            " cancella la chat ", " cancella la conversazione ", " cestino ", " svuota il cestino "].contains(where: { s == $0 }) { return .apri(.pulisci) }
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
    var dentro: Reparto?                  // il reparto in cui ascolta, per i suoi comandi («Jarvis, chi è passato?»)

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
        if riconoscitore.supportsOnDeviceRecognition, !ProcessInfo.processInfo.isiOSAppOnMac { r.requiresOnDeviceRecognition = true }   // sul Mac il motore locale non risponde (errore 1101): lì si usa quello di Apple
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
        if let c = ComandoVocale.riconosci(frase, serveJarvis: true, dentro: dentro) {
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
