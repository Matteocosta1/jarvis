import Foundation
#if os(iOS)
import AVFoundation
import Speech
#endif

extension Notification.Name {
    /// Un tasto di una scheda detto a voce (`userInfo["azione"]`: `ComandoVocale.AzioneScheda`): lo esegue la scheda aperta.
    static let jarvisAzioneScheda = Notification.Name("jarvisAzioneScheda")
}

/// Il Confidente aperto con una conversazione incollata: la frase detta diventa la domanda su quella conversazione.
/// Restituisce vero se l'ha presa (c'è del testo incollato); altrimenti la frase va a JARVIS come sempre.
enum ConfidenteAperto {
    static var domanda: ((String) -> Bool)?
}

/// Le parole che il riconoscimento vocale dell'iPhone deve aspettarsi: i nomi inglesi e le parole di JARVIS che altrimenti storpia
/// («EDITH» diventa «edit», «ricevi» diventa «dicevi»). Le usano tutti gli ascolti (richiamo, ascolto, orecchio, comandi nelle sezioni).
enum Vocabolario {
    nonisolated static let parole: [String] = [
        "Jarvis", "EDITH", "apri EDITH", "EDITH controllo completo", "controllo completo", "mi ricevi", "mi ricevi Jarvis", "ricevi", "ricevuto",
        "LiDAR", "Wiretap", "Sentinella", "Profiler", "Vitals", "Briefing", "Shazam", "Scanner", "Supabase", "GitHub", "Discosizer", "Discogs",
        "Resident Advisor", "SumUp", "Spotify", "WhatsApp", "Apple Music", "Interprete", "Allenatore", "Confidente", "Diario", "Occhi", "Cucina",
        "Ricordi", "Bea", "Beatrice", "Matteo", "Pier", "Cristina", "fai un giro", "in video", "girati", "grandangolo", "sottovoce", "voce normale",
        "wake up daddy's home", "daddy's home", "chiudi", "pulisci", "scansiona la stanza", "quanto è grande", "fine scansione",
        // i nomi inglesi delle sezioni dentro le frasi di tutti i giorni: così il riconoscimento li aspetta scritti giusti
        "apri LiDAR", "apri EDITH", "apri Vitals", "apri il Briefing", "apri Shazam", "apri lo Scanner", "apri il Profiler", "apri il Wiretap",
        "apri GitHub", "apri Supabase", "apri il Browser", "apri l'Email", "Email", "Browser", "Intelligence", "Daily",
    ]
}

/// Come il riconoscimento italiano storpia i nomi inglesi delle sezioni («laidar», «idit», «vai tals»…): prima di cercare il comando
/// ogni storpiatura torna il nome giusto, così «apri laidar» apre LiDAR e «Jarvis, vai tals» apre Vitals (22 ott, chiesto dal signore).
enum Pronunce {
    /// (nome giusto, come può arrivare scritto): parole già in minuscolo, senza accenti né punteggiatura; le più lunghe prima.
    nonisolated static let varianti: [(giusto: String, modi: [String])] = [
        ("lidar", ["lai dar s", "lai dar", "lay dar", "lai der", "lie dar", "laidar", "lai da", "laider", "leader", "l idar", "lidarr", "layder", "raider", "li dar", "laida", "lider", "lyder", "li da", "lida", "lidl"]),
        ("edith", ["edit h", "e dith", "i dith", "editth", "editte", "editti", "eddith", "hedith", "heidit", "editto", "e dit", "i dit", "editt", "edyth", "edite", "idith", "iditt", "iddit", "edito", "edita", "eddie", "heidi", "edeth", "edit", "edid", "idit", "idid", "eddy", "edi", "idi"]),
        ("vitals", ["vai tel s", "vai tels", "vaitels", "vitels", "vai tal s", "white als", "vai tals", "wait als", "vai tal", "vital s", "vaitals", "vaitols", "waitals", "vitalls", "baitals", "vitaels", "vitali", "vaital", "vaitol", "vaitls", "vitols", "bitals", "fitals", "vital"]),
        ("briefing", ["bri ffing", "bri fing", "brief in", "briffing", "breefing", "brifing", "briefin", "prifing", "brifin", "brief", "brif"]),
        ("shazam", ["scia zam", "sha zam", "sha sam", "sha zan", "sciazam", "shazaam", "sciasam", "shazamm", "sciazan", "shazzam", "shazan", "chazam"]),
        ("scanner", ["scanners", "skanner", "scannar", "scaner", "skaner", "scanne", "scan"]),
        ("profiler", ["pro fai ler", "pro failer", "pro filer", "profailer", "profiller", "profayler", "proviler"]),
        ("wiretap", ["waiter tap", "uaier tap", "uaier tep", "where tap", "wire tape", "waitertap", "uair tap", "wair tap", "wear tap", "wire tab", "uaia tap", "wire tap", "uaiertep", "uaiertap", "uairtap", "waretap"]),
        ("github", ["ghit hab", "ghit hub", "git hub", "kit hub", "ghi tab", "ghithub", "git ab", "ghitab", "githab", "gitab"]),
        ("supabase", ["super base", "supa base", "supa beis", "supa beys", "suba base", "superbase", "supa bas", "supabeis"]),
        ("email", ["i meil", "i mail", "e mail", "imeil", "imail", "emeil"]),
        ("browser", ["brau ser", "brausser", "brauser", "brouser", "brawser"]),
    ]

    /// Le parole della frase, con ogni storpiatura sostituita dal nome giusto.
    nonisolated static func sistema(_ t: [String]) -> [String] {
        var s = " " + t.joined(separator: " ") + " "
        for (giusto, modi) in varianti {
            for m in modi {
                while s.contains(" \(m) ") { s = s.replacingOccurrences(of: " \(m) ", with: " \(giusto) ") }
            }
        }
        return s.split(separator: " ").map(String.init)
    }
}

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
    case allenatore(AzioneAllenatore)       // dentro l'Allenatore: «Jarvis, fine serie», «Jarvis, quante ripetizioni?»…
    case dentroInterprete(AzioneInterprete) // dentro l'Interprete: «Jarvis, ascolta lui», «Jarvis, passa al francese»…
    case rapido(AzioneRapida)               // dalla schermata principale: apre la sezione e fa già la sua cosa
    case scheda(AzioneScheda)               // dentro una scheda: i suoi tasti a voce («ne parliamo», «incolla», «ti penso»…)
    case profiler(AzioneProfiler)           // dentro il Profiler: «Jarvis, scatta», «Jarvis, si chiama Marco Rossi»…
    case domanda(String)                    // dentro una scheda: «dimmi», «com'ho dormito?»: chiude la scheda e chiede a JARVIS come il suo tasto

    /// I comandi di LiDAR (21 ott, chiesti dal signore).
    enum AzioneLidar: Equatable { case fine, misure, capienza, salva, tre }
    /// I comandi dentro la Sentinella: gli stessi due tasti in alto.
    enum AzioneSentinella: Equatable { case registro, schermoNero }
    /// I comandi dentro l'Allenatore: i suoi tasti, più le domande sulla serie e la pausa.
    enum AzioneAllenatore: Equatable { case fineSerie, azzera, ripetizioni, postura, camera, pausa, riprendi, conta(ParteConteggio) }
    enum ParteConteggio: Equatable { case busto, mani, ginocchia }
    /// I comandi dentro l'Interprete: i due tasti, la lingua, i turni, «ripeti».
    enum AzioneInterprete: Equatable { case ascoltaMe, ascoltaAltro, lingua(String), sceltaLingua, ripeti, turniAutomatici(Bool) }
    /// I comandi rapidi: la sezione si apre già al lavoro.
    enum AzioneRapida: Equatable { case diario, confidente, cucina, riunione }   // «che canzone è?» no: lo fa già il cervello (riconosci_musica)
    /// I tasti delle schede, a voce (21 ott). Niente «cancella», «elimina», «svuota»: a voce sono troppo rischiosi.
    enum AzioneScheda: Equatable {
        case diarioAVoce, diarioNeParliamo
        case confidenteAVoce, confidenteIncolla
        case vitalsCome
        case cuoreSOS
        case beaTiPenso, beaChiama, beaMessaggio, beaWhatsApp, bea112
        case apriMail, postaRiassumi
        case spesaLeggi, spesaWhatsApp
        case occhiGiro, occhiGira, occhiZoomAvanti, occhiZoomIndietro, occhiZoomNormale
        case scannerAltro, scannerGiudizio, scannerIngredienti
    }
    /// I tasti del Profiler, a voce, più la scheda del soggetto dettata.
    enum AzioneProfiler: Equatable { case scatta, gira, rifai, profila, nome(String), ruolo(String) }

    /// Il codice della lingua se la frase finisce con una lingua («… in francese»).
    static func linguaFinale(_ t: [String]) -> String? {
        lingueAVoce.first { l in l.parole.contains { t.last == $0 } }?.codice
    }

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
        t = Pronunce.sistema(t)                                   // «laidar» → lidar, «idit» → edith, «vai tals» → vitals…
        // «apri la sezione meteo», «attiva sezione LiDAR»: la parola «sezione» (con l'articolo) non cambia il comando
        if let k = t.firstIndex(where: { $0 == "sezione" || $0 == "sezioni" }), k + 1 < t.count {
            t.remove(at: k)
            if k > 0, ["la", "le", "nella", "alla", "in"].contains(t[k - 1]) { t.remove(at: k - 1) }
        }
        guard !t.isEmpty, t.count <= 8 else { return nil }
        let s = " " + t.joined(separator: " ") + " "
        func c(_ x: String) -> Bool { s.contains(x) }
        func uno(_ l: [String]) -> Bool { l.contains(where: c) }
        func solo(_ l: [String]) -> Bool { l.contains(s) }        // frasi generiche («dimmi», «che ne pensi»): solo dette così, da sole
        let generiche = [" dimmi ", " dimmi tutto ", " allora ", " che ne pensi ", " cosa ne pensi ", " che mi dici ", " cosa mi dici ", " come va ",
                         " raccontami ", " spiegami ", " fammi sapere ", " aggiornami ", " novita ", " riassumi ", " riassumimi ", " leggimelo ", " leggimeli "]

        // tornare indietro / chiudere il reparto
        // da soli («chiudi», «indietro»…) o in poche frasi esatte: «torna a casa» e «chiudi Spotify» restano a JARVIS
        if t.count == 1, ["torna", "indietro", "chiudi", "chiudimi", "chiudila", "chiudilo", "esci", "basta"].contains(t[0]) { return .torna }
        if [" torna indietro ", " chiudi tutto ", " torna alla home ", " torna alla schermata principale ", " chiudi la scheda ",
             " chiudi questa scheda ", " esci da qui ", " chiudi qui ", " chiudimi tutto ", " chiudimi questa ", " chiudimi questo ", " torna alla schermata iniziale ",
            " torna all inizio ", " vai alla home ", " portami alla home ", " esci pure ", " ok chiudi ", " grazie chiudi ", " a posto chiudi ", " fatto chiudi "].contains(where: { s == $0 }) { return .torna }
        // «chiudi l'app», «chiudi la sezione», «chiudi qui», oppure «chiudi» + il nome di una sezione di JARVIS («chiudi LiDAR», «chiudi il meteo»).
        // «chiudi Spotify», «chiudi la porta», «chiudi la musica» restano a JARVIS.
        if ["chiudi", "chiudimi", "esci", "togli", "toglimi", "levami"].contains(t[0]), t.count <= 4 {
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
        case .allenatore?:
            if c(" fine serie ") || c(" serie finita ") || c(" ho finito ") || c(" serie chiusa ") { return .allenatore(.fineSerie) }
            if c(" azzera ") || c(" ricomincia ") || c(" da capo ") { return .allenatore(.azzera) }
            if c(" quante ripetizioni ") || c(" quante ne ho fatte ") || c(" a quante sono ") || c(" quante sono ") { return .allenatore(.ripetizioni) }
            if c(" schiena ") || c(" postura ") || c(" come sto andando ") || c(" come va ") { return .allenatore(.postura) }
            if c(" fotocamera ") || c(" girati ") || c(" selfie ") || c(" camera ") { return .allenatore(.camera) }
            if c(" pausa ") || c(" aspetta un attimo ") { return .allenatore(.pausa) }
            if c(" riprendi ") || c(" ripartiamo ") || c(" continua ") || c(" riparti ") { return .allenatore(.riprendi) }
            if c(" conta ") || c(" conteggio ") {
                if c(" mani ") || c(" braccia ") { return .allenatore(.conta(.mani)) }
                if c(" ginocchia ") || c(" gambe ") { return .allenatore(.conta(.ginocchia)) }
                if c(" busto ") || c(" schiena ") { return .allenatore(.conta(.busto)) }
            }
        case .interprete?:
            if c(" ascolta me ") || c(" tocca a me ") || c(" parlo io ") { return .dentroInterprete(.ascoltaMe) }
            if c(" ascolta lui ") || c(" ascolta lei ") || c(" ascolta l altro ") || c(" ascoltalo ") || c(" ascoltala ")
                || c(" tocca a lui ") || c(" tocca a lei ") { return .dentroInterprete(.ascoltaAltro) }
            if c(" ripeti ") || c(" ridillo ") || c(" ripetilo ") { return .dentroInterprete(.ripeti) }
            if c(" turni automatici ") || c(" turni automatico ") { return .dentroInterprete(.turniAutomatici(true)) }
            if c(" turni manuali ") || c(" senza turni ") || c(" niente turni ") { return .dentroInterprete(.turniAutomatici(false)) }
            if c(" cambia ") || c(" passa ") || c(" lingua ") || c(" metti ") {
                if let l = linguaFinale(t) { return .dentroInterprete(.lingua(l)) }
                if c(" lingua ") { return .dentroInterprete(.sceltaLingua) }
            }
        // le schede: tanti modi di dirlo, come si parla davvero («Jarvis, ti racconto una cosa», «che ne pensi di questo?»)
        case .diario?:
            if solo(generiche) || uno([" ne parliamo ", " parliamone ", " che ne pensi ", " cosa ne pensi ", " che ne dici ", " cosa ne dici ", " rileggimi ", " rileggila ",
                    " rileggimela ", " leggimela ", " leggimi la pagina ", " commentala ", " cosa ci leggi ", " come mi vedi ", " come ti sembro "]) { return .scheda(.diarioNeParliamo) }
            if uno([" a voce ", " te lo racconto ", " ti racconto ", " ti devo raccontare ", " parliamo di una cosa ", " parliamo un po ", " ascoltami ",
                    " scriviamo ", " scriviamolo ", " nuova pagina ", " aggiungi una pagina ", " scrivi la pagina ", " com e andata oggi ",
                    " ti dico com e andata ", " voglio raccontarti ", " devo raccontarti "]) { return .scheda(.diarioAVoce) }
        case .confidente?:
            if uno([" incolla ", " incollala ", " incollalo ", " incolla qui ", " incolla il messaggio ", " prendi il messaggio ", " prendi quello che ho copiato ",
                    " ho copiato ", " l ho copiato ", " l ho copiata ", " leggi quello che ho copiato "]) { return .scheda(.confidenteIncolla) }
            if uno([" a voce ", " te lo racconto ", " ti racconto ", " ti devo raccontare ", " parliamo ", " parliamone ", " ascoltami ", " devo parlarti ",
                    " ho bisogno di parlarti ", " mi devo sfogare ", " devo sfogarmi ", " sfogo "]) { return .scheda(.confidenteAVoce) }
        case .vitals?:
            if solo(generiche) || uno([" come sto ", " come sto messo ", " come sto andando ", " come va la salute ", " come mi vedi ", " sto bene ",
                    " che dicono ", " cosa dicono ", " analizzali ", " commentali ", " a che punto sono ", " com e la situazione ", " sto migliorando ",
                    " sto peggiorando ", " va tutto bene ", " come mi sto comportando ", " sto facendo bene "]) { return .scheda(.vitalsCome) }
        case .cuore?:
            if t.count <= 6, uno([" sos ", " chiedi aiuto ", " chiama aiuto ", " aiuto ", " sto male ", " mi sento male ", " chiama i soccorsi ", " emergenza "]) { return .scheda(.cuoreSOS) }
            if solo(generiche + [" e normale ", " va bene ", " come sto "]) || uno([" come va il cuore ", " come sta il cuore ", " com e il battito ", " come e il battito ",
                    " come batte ", " sono agitato ", " sono in ansia ", " batte forte ", " ho il cuore a mille ", " ho le palpitazioni "]) {
                return .domanda("Come sta il mio cuore oggi? Guarda battito a riposo e variabilità.")
            }
        case .sonno?:
            if solo(generiche) || uno([" come ho dormito ", " com ho dormito ", " quanto ho dormito ", " ho dormito bene ", " ho dormito male ", " come va il sonno ",
                    " sono stanco ", " perche sono stanco ", " dormo abbastanza ", " come dormo ", " stanotte ", " com e andata la notte "]) {
                return .domanda("Come ho dormito stanotte? Dimmi anche come sta andando la settimana.")
            }
        case .meteo?:
            if solo(generiche + [" che tempo fa ", " che tempo fara ", " com e fuori ", " com e il tempo ", " ombrello ", " mi serve l ombrello ", " giacca ",
                                 " mi serve la giacca ", " come mi vesto ", " piove ", " fa freddo ", " fa caldo "]) {
                return .domanda("Che tempo fa qui nelle prossime ore? Mi serve l'ombrello o la giacca?")
            }
        case .briefing?:
            if solo(generiche + [" briefing ", " il briefing ", " fammi il briefing ", " cosa c e oggi ", " cosa ho oggi ", " com e la giornata ", " la giornata ",
                                 " buongiorno ", " partiamo ", " vai "]) {
                return .domanda("Buongiorno Jarvis, il briefing per favore.")
            }
            if uno([" apri mail ", " apri la mail ", " apri l app mail ", " apri posta ", " vai su mail "]) { return .scheda(.apriMail) }
        case .ricordi?:
            if uno([" ho parcheggiato ", " parcheggiato qui ", " segna la macchina ", " lascio la macchina qui ", " la macchina e qui "]) { return .domanda("Ho parcheggiato qui, segnalo.") }
            if uno([" ricorda dove sono ", " ricordati questo posto ", " segna questo posto ", " salva questo posto ", " ricorda questo posto ", " segnati dove sono "]) {
                return .domanda("Ricordati questo posto: dove sono adesso.")
            }
            if uno([" dov e la macchina ", " dove ho parcheggiato ", " portami alla macchina ", " portami li ", " portamici "]) { return .domanda("Dov'è la macchina? Portami lì.") }
            if uno([" com e andata oggi ", " cosa ho fatto oggi ", " la mia giornata "]) { return .domanda("Com'è andata oggi?") }
            if solo(generiche + [" cosa devo ricordare ", " cosa mi devo ricordare ", " cosa c e ", " promemoria ", " cosa ho promesso "]) {
                return .domanda("Cosa mi devo ricordare? Promesse aperte, oggetti e parcheggio.")
            }
        case .bea?:
            if t.count <= 7 {
                if uno([" emergenza ", " 112 ", " centododici ", " cento dodici ", " chiama i soccorsi ", " soccorso "]) { return .scheda(.bea112) }
                if uno([" ti penso ", " pensiero ", " qualcosa di carino ", " qualcosa di dolce ", " qualcosa di romantico ", " un messaggio carino ",
                        " mandale un pensiero ", " dille che la penso ", " dille che la amo ", " falle una sorpresa ", " scrivile qualcosa "]) { return .scheda(.beaTiPenso) }
                if solo([" whatsapp ", " su whatsapp ", " scrivile su whatsapp ", " whatsapp a bea ", " mandale un whatsapp "]) { return .scheda(.beaWhatsApp) }
                if uno([" chiamala ", " chiama bea ", " telefonale ", " telefona a bea ", " fammi parlare con lei ", " voglio sentirla "]) { return .scheda(.beaChiama) }
                if uno([" scrivile ", " mandale un messaggio ", " mandale un sms ", " scrivi a bea "]) { return .scheda(.beaMessaggio) }
            }
        case .email?:
            if uno([" apri mail ", " apri la mail ", " apri l app mail ", " apri l app della posta ", " apri posta ", " apri la posta ", " vai su mail "]) { return .scheda(.apriMail) }
            if solo(generiche) || uno([" riassumi ", " riassumimi ", " riassunto ", " cosa conta ", " qualcosa di importante ",
                    " qualcosa di urgente ", " mail importanti ", " leggimele ", " cosa mi e arrivato ", " chi mi ha scritto ", " cosa devo leggere "]) || solo([" cosa c e ", " novita "]) {
                return .scheda(.postaRiassumi)
            }
        case .spesa?:
            if uno([" whatsapp ", " manda la lista ", " mandala ", " condividi ", " condividila ", " mandala a qualcuno ", " inviala "]) { return .scheda(.spesaWhatsApp) }
            if uno([" leggimela ", " leggi la lista ", " leggimi la lista ", " cosa devo comprare ", " cosa manca ", " cosa c e in lista ", " cosa compro ",
                    " che devo prendere ", " cosa devo prendere ",  " sono al supermercato ", " sono al super ", " sono all esselunga ", " cosa prendo ", " ricordami la spesa "]) || solo(generiche) { return .scheda(.spesaLeggi) }
        case .occhi?, .cucina?:
            // «Jarvis, guarda là in fondo», «guarda qua vicino», «guarda l'insieme»: lì ogni frase è già la domanda dello scatto
            if t.count <= 6, uno([" girati ", " gira la fotocamera ", " girala ", " cambia fotocamera ", " cambia camera ", " selfie ", " fai un selfie ",
                    " fotocamera davanti ", " fotocamera dietro ", " camera davanti ", " camera dietro ", " inquadra me ", " inquadrami ", " guardami ",
                    " guarda me ", " gira ", " girà "]) { return .scheda(.occhiGira) }
            if t.count <= 5, uno([" zoom normale ", " uno x ", " 1x ", " togli lo zoom ", " senza zoom "]) || solo([" normale "]) { return .scheda(.occhiZoomNormale) }
            if t.count <= 5, uno([" allarga ", " allargati ", " piu largo ", " zoom indietro ", " meno zoom ", " grandangolo ", " rimpicciolisci ",
                    " allontana ", " allontanati ", " indietro con lo zoom "]) { return .scheda(.occhiZoomIndietro) }
            if t.count <= 5, uno([" zoom ", " zooma ", " zoomma ", " avvicina ", " avvicinati ", " piu vicino ", " ingrandisci ", " zoom avanti ",
                    " piu zoom ", " stringi "]) { return .scheda(.occhiZoomAvanti) }
            if t.count <= 7, uno([" fai un giro ", " giro ", " video ", " in video ", " fai un video ", " riprendi ", " registra ", " panoramica ",
                    " guardati intorno ", " guarda tutto intorno ", " guarda in giro ", " dai un occhiata in giro ", " fammi vedere tutto ",
                    " scorri lo scaffale ", " tutto lo scaffale ", " tutta la stanza ", " tutto il frigo ", " tutta la dispensa ", " tutto il frigorifero "]) { return .scheda(.occhiGiro) }
        case .scanner?:
            if uno([" un altro ", " un altra ", " altro prodotto ", " scansiona un altro ", " prossimo ", " ancora ", " di nuovo ", " rifai ", " riprova ",
                    " un altro codice ", " vai col prossimo ", " avanti "]) { return .scheda(.scannerAltro) }
            if uno([" ingredienti ", " cosa c e dentro ", " additivi ", " di cosa e fatto ", " cosa contiene ", " etichetta ", " composizione "]) { return .scheda(.scannerIngredienti) }
            if solo(generiche) || uno([" fa bene ", " fa male ", " e sano ", " e buono ", " lo compro ", " lo prendo ", " conviene ", " e una buona scelta ",
                    " voto ", " alternativa ", " c e di meglio ", " posso mangiarlo ", " lo posso prendere ", " giudizio "]) { return .scheda(.scannerGiudizio) }
        case .profiler?:
            // la scheda del soggetto dettata: «si chiama Marco Rossi», «è il fornitore audio», «lavora come gestore del locale»
            func coda(dopo n: Int) -> String? { let r = t.dropFirst(n).joined(separator: " "); return r.isEmpty ? nil : r }
            func maiuscole(_ x: String) -> String { x.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
            if t.count >= 3, t[0] == "si", t[1] == "chiama", let n = coda(dopo: 2) { return .profiler(.nome(maiuscole(n))) }
            if t.count >= 4, t[0] == "il", t[1] == "nome", t[2] == "e", let n = coda(dopo: 3) { return .profiler(.nome(maiuscole(n))) }
            if t.count >= 2, ["nome", "chiamato", "chiamata"].contains(t[0]), let n = coda(dopo: 1) { return .profiler(.nome(maiuscole(n))) }
            if t.count >= 3, t[0] == "lavora", ["come", "in", "per", "da", "alla", "al", "nel", "nella"].contains(t[1]), let r = coda(dopo: t[1] == "come" ? 2 : 1) { return .profiler(.ruolo(r)) }
            if t.count >= 3, t[0] == "fa", ["il", "la", "lo", "l"].contains(t[1]), let r = coda(dopo: 1) { return .profiler(.ruolo(r)) }
            if t.count >= 2, t[0] == "ruolo", let r = coda(dopo: 1) { return .profiler(.ruolo(r)) }
            if t.count >= 3, t[0] == "e", ["il", "la", "lo", "l", "un", "una", "uno", "mio", "mia", "un", "nostro", "nostra"].contains(t[1]), let r = coda(dopo: 1) { return .profiler(.ruolo(r)) }
            if uno([" rifai ", " riprova ", " un altra ", " rifalla ", " non va bene ", " e venuta male ", " venuta male ", " e mossa ", " mossa ", " sfocata ",
                    " ricomincia ", " da capo "]) { return .profiler(.rifai) }
            if uno([" girati ", " selfie ", " gira ", " cambia fotocamera ", " fotocamera davanti ", " fotocamera dietro ", " inquadra me ", " guarda me "]) { return .profiler(.gira) }
            if uno([" profila ", " profilalo ", " profilala ", " dossier ", " fammi il profilo ", " fammi il dossier ", " chi e ", " dimmi chi e ", " che tipo e ",
                    " cosa ne pensi ", " che ne pensi ", " leggilo ", " leggila ", " analizzalo ", " analizzala ", " procedi ", " vai ", " fatto ", " schedalo ", " schedala "]) {
                return .profiler(.profila)       // senza la foto ancora: scatta (il Profiler sa a che punto è)
            }
            if uno([" scatta ", " foto ", " acquisisci ", " fotografalo ", " fotografala ", " prendilo ", " prendila ", " fai la foto ", " beccato ", " eccolo ", " eccola "]) {
                return .profiler(.scatta)
            }
        default: break
        }

        // Interprete già sulla lingua: «traduci in inglese», «interprete spagnolo», «fammi da interprete in francese».
        // Solo frasi corte: «traduci in inglese buongiorno a tutti» resta una domanda per il cervello.
        if t.count <= 5, c(" traduci ") || c(" traduttore ") || c(" interprete "), let l = linguaFinale(t) { return .interprete(l) }

        // i comandi rapidi, solo dalla schermata principale: la sezione si apre e fa già il suo lavoro
        if dentro == nil, t.count <= 6 {
            if c(" scrivi il diario ") || c(" scriviamo il diario ") || c(" facciamo il diario ") || c(" compiliamo il diario ") { return .rapido(.diario) }
            if c(" ho bisogno di parlarti ") || c(" devo parlarti ") || c(" ti devo parlare ") || c(" posso parlarti ") { return .rapido(.confidente) }
            if c(" cosa cucino ") || c(" cosa posso cucinare ") || c(" cosa preparo da mangiare ") { return .rapido(.cucina) }
            if c(" registra la riunione ") || c(" registra questa riunione ") || c(" registra la conversazione ") { return .rapido(.riunione) }
        }

        let verbi = ["attiva", "apri", "aprimi", "avvia", "accendi", "lancia", "metti", "vai", "passa", "fammi", "fai", "inizia", "modalita", "parti", "entra",
                     "mostra", "mostrami", "portami", "vediamo"]
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
        if (c(" scanner ") || c(" scansiona ") || c(" codice a barre ") || c(" etichetta ") || c(" yuka ")) && (comanda || c(" scansiona ")) { return .apri(.scanner) }

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
        // tutti i verbi di comando valgono per ogni sezione: «attiva EDITH», «avvia i costi», «lancia le impostazioni» (22 ott)
        let conVerbo = t.contains(where: { verbi.contains($0) })
        if conVerbo { for (reparto, chiavi) in nuove where chiavi.contains(where: c) { return .apri(reparto) } }
        // «apri Bea», «vai a Bea»: solo così, corto; «chiama Bea» o «scrivi a Bea» restano a JARVIS
        let versoBea = ["chiam", "scriv", "telefon", "mand", "messagg", "dill", "dic"]      // «fammi chiamare Bea», «scrivi a Bea»: restano a JARVIS
        if (c(" bea ") || c(" beatrice ")) && t.count <= 4 && t.contains(where: { verbi.contains($0) })
            && !t.contains(where: { p in versoBea.contains(where: { p.hasPrefix($0) }) }) {
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
        r.contextualStrings = ["Jarvis", "Sentinella", "Wiretap", "Profiler", "Occhi", "Diario", "Vitals", "Briefing", "Shazam", "Cucina", "Scanner", "EDITH"]
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

#if os(iOS)
import SwiftUI
import Combine

extension View {
    /// I tasti della scheda detti a voce: JARVIS li riconosce, la scheda aperta li esegue.
    func tastiAVoce(_ fai: @escaping (ComandoVocale.AzioneScheda) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .jarvisAzioneScheda)) { n in
            if let a = n.userInfo?["azione"] as? ComandoVocale.AzioneScheda { fai(a) }
        }
    }
}
#endif
