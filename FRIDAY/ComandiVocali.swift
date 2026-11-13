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

/// Le parole che il riconoscimento vocale dell'iPhone dovrebbe aspettarsi (nomi inglesi, parole di JARVIS).
/// Nota (22 ott): al momento nessun ascolto usa questa lista (gli ascolti hanno le loro, dalla build 12); le storpiature le corregge `Pronunce`.
enum Vocabolario {
    nonisolated static let parole: [String] = [
        "Jarvis", "EDITH", "apri EDITH", "EDITH controllo completo", "controllo completo", "mi ricevi", "mi ricevi Jarvis", "ricevi", "ricevuto",
        "LiDAR", "Wiretap", "Sentinella", "Profiler", "Vitals", "Briefing", "Shazam", "Scanner", "Supabase", "GitHub", "Discosizer", "Discogs",
        "Resident Advisor", "SumUp", "Spotify", "WhatsApp", "Apple Music", "Interprete", "Allenatore", "Trainer", "Personal Trainer", "apri il Trainer", "Confidente", "Diario", "Occhi", "Cucina",
        "Ricordi", "Bea", "Beatrice", "Matteo", "Pier", "Cristina", "fai un giro", "in video", "girati", "grandangolo", "sottovoce", "sussurra", "voce normale",
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
        ("edith", ["edit h", "e dith", "i dith", "editth", "editte", "editti", "eddith", "hedith", "heidit", "editto", "e dit", "i dit", "editt", "edyth", "edite", "idith", "iditt", "iddit", "edito", "edita", "eddie", "heidi", "edeth", "edit", "edid", "idit", "idid", "eddy", "edi", "idi"]),
        ("vitals", ["vai tel s", "vai tels", "vaitels", "vitels", "vai tal s", "white als", "vai tals", "wait als", "vai tal", "vital s", "vaitals", "vaitols", "waitals", "vitalls", "baitals", "vitaels", "vitali", "vaital", "vaitol", "vaitls", "vitols", "bitals", "fitals", "vital"]),
        ("scanner", ["scanners", "skanner", "scannar", "scaner", "skaner", "scanne", "scan"]),
        ("email", ["i meil", "i mail", "e mail", "imeil", "imail", "emeil"]),
    ]

    /// Storpiature che sono anche parole normali («il leader», «il Lidl», «uno scan»): valgono solo in una frase di comando.
    nonisolated static let soloConVerbo: Set<String> = ["scan", "vital", "vitali", "idi", "edi", "eddie", "eddy", "heidi", "edita", "edito",
                                                        "editto", "e mail"]
    nonisolated static let verbiComando: Set<String> = ["apri", "aprimi", "attiva", "avvia", "accendi", "lancia", "mostra", "mostrami", "vai",
                                                        "entra", "fammi", "portami", "vediamo", "chiudi", "chiudimi", "esci", "togli", "toglimi", "levami"]

    /// Tra il verbo e il nome possono stare solo queste parole: «apri il leader», «vai su leader», «fammi vedere la sezione edit».
    nonisolated static let ponte: Set<String> = ["il", "lo", "la", "l", "i", "gli", "le", "su", "a", "al", "alla", "in", "nella", "sezione", "vedere"]

    /// Le parole della frase, con ogni storpiatura sostituita dal nome giusto. Le storpiature che sono anche parole normali
    /// valgono solo come comando secco: verbo (più al massimo «il», «la», «su», «sezione»…) e il nome in fondo alla frase.
    /// Così «apri leader» apre LiDAR, ma «mostrami chi è il leader del partito» resta una domanda.
    nonisolated static func sistema(_ t: [String]) -> [String] {
        var p = t
        for (giusto, modi) in varianti {
            for m in modi {
                let w = m.split(separator: " ").map(String.init)
                var i = 0
                while i + w.count <= p.count {
                    if Array(p[i..<(i + w.count)]) == w {
                        var j = i - 1
                        while j >= 0, ponte.contains(p[j]) { j -= 1 }
                        let comandoSecco = j >= 0 && verbiComando.contains(p[j]) && i + w.count == p.count
                        if !soloConVerbo.contains(m) || comandoSecco {
                            p.replaceSubrange(i..<(i + w.count), with: [giusto])
                        }
                    }
                    i += 1
                }
            }
        }
        return p
    }
}

/// Dopo un'interruzione decide il cervello, come in una conversazione vera: niente parole chiave obbligatorie (22 ott, chiesto dal signore).
/// Qui solo il caso «aspetta» / «ascoltami» detto da solo: JARVIS riascolta, la frase vera arriva adesso.
enum Seguito {
    nonisolated static func soloAspetta(_ frase: String) -> Bool {
        let parole = frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let segnali: Set<String> = ["aspetta", "aspetti", "ascoltami", "ascolta", "ascolti", "attimo", "momento"]
        let contorno: Set<String> = ["jarvis", "giarvis", "jervis", "ehi", "hey", "ok", "senti", "scusa", "un", "mi", "dai", "no", "allora", "ah",
                                     "si", "per", "favore", "secondo"]
        let unSecondo = parole.joined(separator: " ").contains("un secondo")    // «un secondo» sì, «secondo» da solo no
        guard !parole.isEmpty, parole.count <= 6, unSecondo || parole.contains(where: { segnali.contains($0) }) else { return false }
        return parole.allSatisfy { segnali.contains($0) || contorno.contains($0) }
    }
}

/// I reparti che si aprono a voce.
enum Reparto: String, Identifiable, Equatable {
    // i sensi
    case occhi, giro, cucina, scanner
    // le schede della corona
    case diario, sonno, vitals, confidente, allenatore
    case email, spesa
    case foto
    case ricordi, interprete, messaggi, telefono
    case edith
    // la schermata principale: il cestino
    case pulisci
    // build 23: MUSICA, l'icona in alto
    case musica
    var id: String { rawValue }

    /// La frase di JARVIS quando apre il reparto (le schede parlano da sole).
    /// 12.0 (10) (il signore: «tante tante frasi… non le solite»): tante varianti in Battute.swift, mai due volte uguale; la prima
    /// di ogni sezione è quella di sempre.
    var annuncio: String? { Battute.apertura(self) }
}

/// I comandi vocali: «apri il diario», «fai un giro», «torna».
/// Riconosce solo frasi brevi con un verbo di comando, così le domande normali vanno al cervello come sempre.
enum ComandoVocale: Equatable {
    case apri(Reparto)
    case torna
    case interprete(String)                 // «traduci in inglese», «interprete spagnolo»: apre l'Interprete già sulla lingua (codice: en, es…)
    case allenatore(AzioneAllenatore)       // dentro l'Allenatore: «Jarvis, fine serie», «Jarvis, quante ripetizioni?»…
    case dentroInterprete(AzioneInterprete) // dentro l'Interprete: «Jarvis, ascolta lui», «Jarvis, passa al francese»…
    case rapido(AzioneRapida)               // dalla schermata principale: apre la sezione e fa già la sua cosa
    case scheda(AzioneScheda)               // dentro una scheda: i suoi tasti a voce («ne parliamo», «incolla», «ti penso»…)
    case domanda(String)                    // dentro una scheda: «dimmi», «com'ho dormito?»: chiude la scheda e chiede a JARVIS come il suo tasto
    // MARK XI (4 nov, approvati dal signore): le sezioni aperte, a voce. Li esegue la schermata principale, anche da dentro un
    // reparto col microfono. Sull'orologio (niente sezioni dietro) la frase va al cervello come prima.
    case chiudiSezioni                      // «Jarvis, chiudi tutto»: tutte le sezioni aperte, anche quelle dietro
    case chiudiSezione(String)              // «Jarvis, chiudi il meteo»: quella sezione (il suo nome, come `Sezione.nome`), anche se è dietro
    case sezioniAperte                      // «Jarvis, sezioni aperte»: le pagine olografiche da sfogliare
    case sezionePrima                       // «Jarvis, quella di prima»: torna davanti la sezione di prima
    case daParte                            // «Jarvis, mettila da parte»: quella davanti vola nel reattore (AGGANCIO) e va dietro

    /// Un comando delle sezioni aperte (MARK XI): lo esegue la schermata principale.
    var navigaSezioni: Bool {
        switch self {
        case .chiudiSezioni, .chiudiSezione, .sezioniAperte, .sezionePrima, .daParte: return true
        default: return false
        }
    }

    /// Il nome della sezione (come `Sezione.nome`) detto a voce dopo «chiudi»: «meteo» → «Meteo», «posta» → «Email»… nil: non è
    /// il nome di una sezione («app», «scheda», «sistemi», «fotocamera»…), e allora si chiude quella davanti.
    static func nomeSezione(_ p: String) -> String? {
        switch p {
        case "occhi", "cucina": return "Occhi"
        case "edith", "edit": return "EDITH"
        case "diario": return "Diario"
        case "sonno": return "Sonno"
        case "vitals": return "Vitals"
        case "posta", "email", "mail": return "Email"
        case "spesa": return "Spesa"
        case "foto", "galleria": return "Foto"
        case "messaggi": return "Messaggi"
        case "telefono", "rubrica": return "Telefono"
        case "ricordi": return "Ricordi"
        case "confidente": return "Confidente"
        case "scanner": return "Scanner"
        case "interprete", "traduttore": return "Interprete"
        case "allenatore", "allenamento", "trainer", "treiner", "personal": return "Trainer"
        default: return nil
        }
    }

    /// MARK XI · le sezioni aperte a voce (4 nov, approvati dal signore), a frase esatta: «sezioni aperte», «quella di prima»,
    /// «mettila da parte», «chiudi tutto». Si guardano prima di togliere la parola «sezione» dalla frase.
    static func navigazione(_ t: [String]) -> ComandoVocale? {
        guard !t.isEmpty, t.count <= 7 else { return nil }
        let s = t.joined(separator: " ")
        let aperte: Set<String> = ["sezioni", "le sezioni", "sezioni aperte", "le sezioni aperte", "tutte le sezioni", "pagine aperte", "le pagine aperte",
                                   "mostrami le sezioni", "mostrami le sezioni aperte", "mostrami tutte le sezioni", "mostrami le pagine aperte",
                                   "fammi vedere le sezioni", "fammi vedere le sezioni aperte", "vediamo le sezioni aperte", "apri le sezioni aperte",
                                   "apri le sezioni", "mostra le sezioni", "mostra le sezioni aperte",
                                   "sfoglia le sezioni", "quali sezioni sono aperte", "che sezioni sono aperte", "che sezioni ho aperto",
                                   "quali sezioni ho aperto", "cosa ho aperto", "che cosa ho aperto"]
        if aperte.contains(s) { return .sezioniAperte }
        // («la pagina di prima» no: nel Browser è la pagina web di prima)
        let prima: Set<String> = ["quella di prima", "la sezione di prima", "sezione di prima", "di nuovo quella di prima",
                                  "torna a quella di prima", "tornami a quella di prima", "torna alla sezione di prima", "torna alla precedente",
                                  "torna alla sezione precedente", "rimetti quella di prima", "rimettimi quella di prima", "riapri quella di prima",
                                  "ridammi quella di prima", "riportami quella di prima", "fammi vedere quella di prima", "mostrami quella di prima",
                                  "apri quella di prima", "la precedente", "sezione precedente", "la sezione precedente"]
        if prima.contains(s) { return .sezionePrima }
        let parte: Set<String> = ["mettila da parte", "mettilo da parte", "metti da parte", "mettila via", "mettilo via", "mettila dietro",
                                  "mettilo dietro", "metti dietro", "mandala dietro", "mandalo dietro", "manda dietro"]
        if parte.contains(s) { return .daParte }
        let tutte: Set<String> = ["chiudi tutto", "chiudimi tutto", "chiudi tutto quanto", "chiudi tutte", "chiudile tutte", "chiudi le sezioni",
                                  "chiudi tutte le sezioni", "chiudi le sezioni aperte", "chiudi tutte le sezioni aperte", "chiudimi tutte le sezioni",
                                  "chiudi tutte le pagine"]
        if tutte.contains(s) { return .chiudiSezioni }
        return nil
    }

    /// I comandi dentro l'Allenatore: i suoi tasti, più le domande sulla serie e la pausa.
    enum AzioneAllenatore: Equatable { case fineSerie, azzera, ripetizioni, postura, camera, pausa, riprendi, pronto, conta(ParteConteggio) }
    enum ParteConteggio: Equatable { case busto, mani, ginocchia, ologramma }
    /// I comandi dentro l'Interprete: i due tasti, la lingua, i turni, «ripeti».
    enum AzioneInterprete: Equatable { case ascoltaMe, ascoltaAltro, lingua(String), sceltaLingua, ripeti, turniAutomatici(Bool) }
    /// I comandi rapidi: la sezione si apre già al lavoro.
    enum AzioneRapida: Equatable { case diario, confidente, cucina }   // «che canzone è?» no: lo fa già il cervello (riconosci_musica)
    /// I tasti delle schede, a voce (21 ott). Niente «cancella», «elimina», «svuota»: a voce sono troppo rischiosi.
    enum AzioneScheda: Equatable {
        case diarioAVoce, diarioNeParliamo
        case confidenteAVoce, confidenteIncolla
        case vitalsCome
        case apriMail, postaRiassumi
        case spesaLeggi, spesaWhatsApp
        case occhiGiro, occhiGira, occhiZoomAvanti, occhiZoomIndietro, occhiZoomNormale
        case scannerAltro, scannerGiudizio, scannerIngredienti
    }

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
    /// `dentro`: il reparto aperto, per i comandi che valgono solo lì (i tasti delle schede, i comandi del Trainer).
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
        t = Pronunce.sistema(t)                                   // «idit» → edith, «vai tals» → vitals…
        // MARK XI: «sezioni aperte», «quella di prima», «mettila da parte», «chiudi tutto» (prima di togliere «sezione»)
        if let n = navigazione(t) { return n }
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
        // («chiudi tutto» non è più qui: dal 4 nov chiude tutte le sezioni aperte, anche quelle dietro, vedi `navigazione`)
        if [" torna indietro ", " torna alla home ", " torna alla schermata principale ", " chiudi la scheda ",
             " chiudi questa scheda ", " esci da qui ", " chiudi qui ", " chiudimi questa ", " chiudimi questo ", " torna alla schermata iniziale ",
            " torna all inizio ", " vai alla home ", " portami alla home ", " esci pure ", " ok chiudi ", " grazie chiudi ", " a posto chiudi ", " fatto chiudi "].contains(where: { s == $0 }) { return .torna }
        // «chiudi l'app», «chiudi la sezione», «chiudi qui», oppure «chiudi» + il nome di una sezione di JARVIS («chiudi LiDAR», «chiudi il meteo»).
        // «chiudi Spotify», «chiudi la porta», «chiudi la musica» restano a JARVIS.
        if ["chiudi", "chiudimi", "esci", "togli", "toglimi", "levami"].contains(t[0]), t.count <= 4 {
            let resto = Array(t.dropFirst()).filter { !["l", "la", "il", "lo", "le", "i", "gli", "da", "dal", "dalla", "dallo", "questa", "questo"].contains($0) }
            let generiche: Set<String> = ["app", "applicazione", "sezione", "scheda", "schermata", "pagina", "qui", "tutto", "scansione"]
            let sezioni: Set<String> = ["occhi", "fotocamera", "camera", "cucina", "edith", "edit", "diario", "sonno", "vitals", "posta",
                                        "email", "mail", "spesa", "foto", "galleria", "messaggi", "telefono", "rubrica", "ricordi",
                                        "confidente", "scanner", "interprete", "traduttore", "allenatore", "allenamento", "trainer", "treiner",
                                        "personal"]
            if !resto.isEmpty, resto.allSatisfy({ generiche.contains($0) || sezioni.contains($0) }) {
                // MARK XI (4 nov, il signore): con il nome si chiude quella sezione, anche se è dietro («chiudi il meteo»);
                // senza («chiudi la scheda», «chiudi qui», «chiudi la fotocamera») quella davanti, come sempre
                let nomi = Set(resto.compactMap { nomeSezione($0) })
                if nomi.count == 1, let n = nomi.first { return .chiudiSezione(n) }
                return .torna
            }
        }

        // i comandi che valgono solo dentro un reparto
        switch dentro {
        case .allenatore?:
            if c(" fine serie ") || c(" serie finita ") || c(" ho finito ") || c(" serie chiusa ") { return .allenatore(.fineSerie) }
            if c(" azzera ") || c(" ricomincia ") || c(" da capo ") { return .allenatore(.azzera) }
            if c(" quante ripetizioni ") || c(" quante ne ho fatte ") || c(" a quante sono ") || c(" quante sono ") { return .allenatore(.ripetizioni) }
            if c(" schiena ") || c(" postura ") || c(" come sto andando ") || c(" come va ") { return .allenatore(.postura) }
            if c(" fotocamera ") || c(" girati ") || c(" selfie ") || c(" camera ") { return .allenatore(.camera) }
            if c(" pausa ") || c(" aspetta un attimo ") { return .allenatore(.pausa) }
            if c(" riprendi ") || c(" ripartiamo ") || c(" continua ") || c(" riparti ") { return .allenatore(.riprendi) }
            if c(" ologramma ") { return .allenatore(.conta(.ologramma)) }    // build 23: «Jarvis, modalità ologramma» dentro il Trainer
            if c(" specchio ") { return .allenatore(.pronto) }                // «Jarvis, allenati allo specchio»: come il mockup, «Personal trainer pronto»
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
        case .sonno?:
            if solo(generiche) || uno([" come ho dormito ", " com ho dormito ", " quanto ho dormito ", " ho dormito bene ", " ho dormito male ", " come va il sonno ",
                    " sono stanco ", " perche sono stanco ", " dormo abbastanza ", " come dormo ", " stanotte ", " com e andata la notte "]) {
                return .domanda("Come ho dormito stanotte? Dimmi anche come sta andando la settimana.")
            }
        case .ricordi?:
            if uno([" ricorda dove sono ", " ricordati questo posto ", " segna questo posto ", " salva questo posto ", " ricorda questo posto ", " segnati dove sono "]) {
                return .domanda("Ricordati questo posto: dove sono adesso.")
            }
            if uno([" com e andata oggi ", " cosa ho fatto oggi ", " la mia giornata "]) { return .domanda("Com'è andata oggi?") }
            if solo(generiche + [" cosa devo ricordare ", " cosa mi devo ricordare ", " cosa c e ", " promemoria ", " cosa ho promesso "]) {
                return .domanda("Cosa mi devo ricordare? Promesse aperte e oggetti.")
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
        }

        // build 23, MUSICA: «apri la musica», «mostrami la musica», «fammi vedere la musica», «vai alla musica»: solo così, corto.
        // «metti la musica», «accendi la musica», «fammi sentire la musica», «chiudi la musica», «apri la musica dei Daft Punk»
        // restano a JARVIS: la musica la mette e la ferma il cervello (musica_riproduci, musica_controllo), come sempre.
        if c(" musica "), t.count <= 7 {
            let verbiMusica: Set<String> = ["apri", "aprimi", "mostra", "mostrami", "portami", "vai", "entra", "vediamo"]
            let paroleMusica: Set<String> = ["musica", "la", "l", "mia", "su", "a", "alla", "in", "nella", "pagina",
                                             "per", "favore", "sir", "grazie", "pure", "subito", "adesso", "ora"]
            let verbo = t.contains(where: { verbiMusica.contains($0) }) || (t.contains("fammi") && t.contains("vedere"))
            if verbo, t.allSatisfy({ verbiMusica.contains($0) || paroleMusica.contains($0) || $0 == "fammi" || $0 == "vedere" }) { return .apri(.musica) }
        }

        let verbi = ["attiva", "apri", "aprimi", "avvia", "accendi", "lancia", "metti", "vai", "passa", "fammi", "fai", "inizia", "modalita", "parti", "entra",
                     "mostra", "mostrami", "portami", "vediamo"]
        let comanda = t.contains(where: { verbi.contains($0) }) || t.count <= 2

        if c(" fai un giro ") || c(" fammi un giro ") || ((c(" giro ") || c(" video ")) && comanda && c(" occhi ")) || c(" modalita video ") {
            return .apri(.giro)
        }
        if c(" occhi ") && comanda { return .apri(.occhi) }
        if c(" cucina ") && comanda { return .apri(.cucina) }
        if (c(" scanner ") || c(" scansiona ") || c(" codice a barre ") || c(" etichetta ") || c(" yuka ")) && (comanda || c(" scansiona ")) { return .apri(.scanner) }

        // le schede: «apri il diario», «fammi vedere il sonno», «vai al meteo», «mostra la posta», «lista della spesa»
        let schede: [(Reparto, [String])] = [
            (.diario, [" diario "]), (.sonno, [" sonno ", " dormito "]), (.vitals, [" vitals ", " vitali ", " parametri "]),
            (.confidente, [" confidente "]), (.allenatore, [" allenatore ", " allenamento ", " trainer ", " treiner ", " personal trainer "]),
            (.email, [" email ", " mail ", " posta "]), (.spesa, [" spesa "]),
            (.foto, [" foto ", " galleria "]), (.ricordi, [" ricordi "]),
            (.interprete, [" interprete ", " traduttore "]),
            (.messaggi, [" messaggi ", " whatsapp ", " imessage "]), (.telefono, [" telefono ", " tastiera ", " rubrica "]),
        ]
        // le sezioni nuove solo con un verbo: «apri i costi», «mostrami EDITH», «vai alle impostazioni» («che costi?» resta a JARVIS)
        let nuove: [(Reparto, [String])] = [
            (.edith, [" edith ", " editt ", " edit ", " edid ", " edyth ", " editth ", " editte ", " editti ", " eddith ", " edite ",
                      " e dit ", " e dith ", " idit ", " idith ", " hedith ", " heidit ", " edit h "]),
        ]
        // tutti i verbi di comando valgono per ogni sezione: «attiva EDITH», «avvia i costi», «lancia le impostazioni» (22 ott)
        // («fai», «passa», «metti», «parti»… no: «fai il punto sui costi» resta una domanda per JARVIS)
        let verbiApri = ["apri", "aprimi", "attiva", "avvia", "accendi", "lancia", "mostra", "mostrami", "vai", "entra", "fammi", "portami", "vediamo"]
        let conVerbo = t.contains(where: { verbiApri.contains($0) })
        if conVerbo { for (reparto, chiavi) in nuove where chiavi.contains(where: c) { return .apri(reparto) } }
        // il cestino: «pulisci», «svuota la chat», «cancella la conversazione»
        // solo frasi esatte: «pulisci il bagno» o «cancella la chat con Bea» restano a JARVIS
        if [" pulisci ", " pulisci la chat ", " pulisci tutto ", " pulisci lo schermo ", " svuota la chat ", " svuota la conversazione ",
            " cancella la chat ", " cancella la conversazione ", " cestino ", " svuota il cestino "].contains(where: { s == $0 }) { return .apri(.pulisci) }
        // Revisione del dialogo (24 ott): una scheda si apre solo se la frase è davvero un ordine di aprirla, non se la parola
        // capita in un discorso normale («quanto tempo?», «fai una foto alla lavagna», «fammi il punto sulla serata»,
        // «metti il cuore in pace», «vai avanti con la spiegazione del database», «che messaggi?»).
        // Vale se: (1) un verbo d'apertura (apri, mostrami, fammi vedere, inizia…) sta poco prima del nome, con al massimo due
        // parole in mezzo («fammi vedere le foto di ieri», «apri la mail di Matteo»); (2) un verbo semplice (vai, passa, fammi,
        // fai, metti, controlla…) sta subito prima del nome, solo con «il», «al», «sulla»… in mezzo, e la frase finisce lì
        // («vai al meteo», «fammi il briefing», «controlla la posta»); (3) la frase è di una o due parole e non è una domanda
        // («il cuore», «i vitals», «personal trainer»; «che messaggi?» e «il cuore?» vanno a JARVIS).
        // «Tempo» apre il Meteo solo come ordine secco («mostrami il tempo», «fammi vedere che tempo fa»): «quanto tempo?»,
        // «hai tempo?» sono discorso. «Fammi controllare la posta», «fammi sentire Shazam», «fammi guardare le foto» restano ordini.
        let verbiForti: Set<String> = ["apri", "aprimi", "attiva", "avvia", "accendi", "lancia", "inizia", "modalita", "entra", "mostra", "mostrami",
                                       "portami", "vediamo", "vedere", "aprire", "controllare", "guardare", "sentire"]
        let verbiSemplici: Set<String> = ["vai", "passa", "fammi", "fai", "metti", "parti", "controlla", "controlliamo", "guardiamo"]
        let ponteScheda: Set<String> = ["il", "lo", "la", "l", "i", "gli", "le", "al", "allo", "alla", "all", "ai", "agli", "alle", "su", "sul", "sullo",
                                        "sulla", "sull", "sui", "sugli", "sulle", "nel", "nello", "nella", "nell", "nei", "negli", "nelle", "a", "in", "con"]
        let cortesia: Set<String> = ["per", "favore", "sir", "jarvis", "grazie", "pure", "subito", "adesso", "ora", "prego"]
        var fine = t.count                                   // la frase senza le parole di cortesia in fondo («…il meteo, per favore»)
        while fine > 1, cortesia.contains(t[fine - 1]) { fine -= 1 }
        let interrogative: Set<String> = ["che", "quale", "quali", "qual", "quanto", "quanta", "quanti", "quante", "chi", "come", "dove", "quando",
                                          "perche", "cosa", "hai", "ho", "sai", "c"]
        let domanda = frase.contains("?") || interrogative.contains(t[0])
        let breve = t.count <= 2 && !domanda
        func ordineDiAprire(_ chiave: String, secco: Bool) -> Bool {
            let k = chiave.split(separator: " ").map(String.init)
            guard !k.isEmpty, k.count <= t.count else { return false }
            for i in 0...(t.count - k.count) where Array(t[i..<(i + k.count)]) == k {
                let inFondo = i + k.count == fine
                var j = i - 1
                var inMezzo = 0                               // parole in mezzo che non sono «il», «al», «sulla»…
                while j >= 0 {
                    let w = t[j]
                    if verbiForti.contains(w) { if inMezzo <= (secco ? 0 : 2) { return true }; break }
                    if secco && w == "che" { j -= 1; continue }       // «fammi vedere che tempo fa», «mostrami che tempo fa»
                    if verbiSemplici.contains(w) { if inMezzo == 0 && inFondo { return true }; break }
                    if !ponteScheda.contains(w) { inMezzo += 1; if inMezzo > 2 { break } }
                    j -= 1
                }
            }
            return false
        }
        for (reparto, chiavi) in schede {
            for chiave in chiavi where c(chiave) {
                let tempo = chiave == " tempo "
                if (breve && !tempo) || ordineDiAprire(chiave, secco: tempo) { return .apri(reparto) }
            }
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
            // MARK XI: «sezioni aperte», «quella di prima», «chiudi il meteo»… li esegue la schermata principale
            if c.navigaSezioni { ComandiSezioni.invia(c) } else { comando?(c) }
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
