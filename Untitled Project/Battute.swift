import Foundation

// MARK: - 12.0 (10) · Le battute di JARVIS
// Il signore (12 nov, 05:37–05:41): «non freddi comandi… un dialogo dentro l'app mescolato ai comandi chiave, come fa Tony con
// Jarvis»; «le reference di dialogo sono Tony e Jarvis mentre creano in studio o sono in missione… il dialogo umano-assistente
// digitale amico»; «sii molto creativo e crea tante tante frasi di risposta e interazione, non le solite che girano; sii simpatico
// se serve, usa le emozioni, sii più un amico umano oltre che un assistente digitale… stupefacente, cool».
//
// Qui stanno le frasi che JARVIS dice da solo, senza il cervello (aprire una sezione, le azioni rapide della regia, riprendere il
// filo). Le regole:
// - ogni situazione ha tante varianti, scritte apposta, e non si ripete la stessa finché non sono passate le altre;
// - la battuta di spirito è dosata (non sempre), mai di notte, mai quando il signore va di fretta;
// - comandi uno dietro l'altro (pochi secondi): JARVIS accorcia («Fatto.», «Segnato.»), come chi lavora fianco a fianco;
// - i toni tra parentesi quadre («[chuckles]», «[sighs]», «[whispers]») li dice solo la voce di JARVIS dal cloud: la voce
//   dell'iPhone e dell'orologio li salta (TagVoce).
enum Battute {
    // MARK: Il motore

    private static var usate: [String: [Int]] = [:]
    private static var ultimaDetta = Date.distantPast

    /// Il momento della giornata: la mattina JARVIS è più sveglio, di notte più asciutto e a voce bassa.
    enum Momento { case mattina, giorno, sera, notte }
    static var momento: Momento {
        switch Calendar.current.component(.hour, from: Date()) {
        case 6..<12: return .mattina
        case 12..<18: return .giorno
        case 18..<23: return .sera
        default: return .notte
        }
    }

    /// Il signore va di fretta: un comando a pochi secondi dall'ultima battuta, o la voce più veloce del solito (B5).
    static var diFretta: Bool { Date().timeIntervalSince(ultimaDetta) < 6 || umore == .fretta }

    // MARK: B5 · come sta il signore (12.0 (12))

    /// Come sta il signore adesso, da come ha parlato (ComeParla: risate, sospiri, velocità, forza): le battute si adattano, come
    /// fa un amico. Vale 10 minuti dall'ultima frase che l'ha mostrato.
    enum Umore { case normale, allegro, giu, fretta }
    private static var umoreSentito: (umore: Umore, quando: Date) = (.normale, .distantPast)
    static var umore: Umore {
        // la fretta passa prima (3 minuti); allegria e giornata storta restano un po' di più (10 minuti)
        let durata: TimeInterval = umoreSentito.umore == .fretta ? 180 : 600
        return Date().timeIntervalSince(umoreSentito.quando) < durata ? umoreSentito.umore : .normale
    }

    /// La riga di ComeParla dell'ultima frase («ha appena riso», «più veloce del solito»…): aggiorna l'umore.
    static func sentito(_ come: String?) {
        guard let c = come?.lowercased(), !c.isEmpty else { return }
        if c.contains("riso") { umoreSentito = (.allegro, Date()) }
        else if c.contains("sospirato") || (c.contains("più lento") && c.contains("più bassa")) { umoreSentito = (.giu, Date()) }
        else if c.contains("più veloce") { umoreSentito = (.fretta, Date()) }
    }

    /// Una variante della situazione `chiave`, mai una di quelle uscite di recente.
    static func una(_ chiave: String, _ varianti: [String]) -> String {
        guard !varianti.isEmpty else { return "" }
        let giro = usate[chiave] ?? []
        let memoria = max(0, min(varianti.count - 1, (varianti.count * 2) / 3))
        let recenti = Set(giro.suffix(memoria))
        let i = varianti.indices.filter { !recenti.contains($0) }.randomElement() ?? 0
        usate[chiave] = Array((giro + [i]).suffix(16))
        ultimaDetta = Date()
        return varianti[i]
    }

    /// Ogni tanto, non sempre, un tocco di spirito dopo la frase: mai di notte, mai se va di fretta.
    static func spirito(_ probabilita: Double = 0.3) -> Bool {
        // B5: col signore giù o di fretta niente battute; se ride, JARVIS sta al gioco più volentieri
        let p = umore == .allegro ? min(0.8, probabilita * 1.6) : probabilita
        return momento != .notte && !diFretta && umore != .giu && Double.random(in: 0..<1) < p
    }

    /// Le frasi da una parola per i comandi a raffica.
    private static let lampi = ["Fatto.", "Eccolo.", "Ci sono.", "Andata.", "Sistemato.", "Fatto, Sir.", "Preso.", "Agli ordini."]
    static func lampo() -> String { una("lampo", lampi) }

    /// Un elenco detto bene: «latte», «latte e uova», «latte, uova e pane».
    static func elenco(_ cose: [String]) -> String {
        let c = cose.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        switch c.count {
        case 0: return ""
        case 1: return c[0]
        default: return c.dropLast().joined(separator: ", ") + " e " + c[c.count - 1]
        }
    }

    /// La prima lettera maiuscola (per cominciare la frase con una cosa: «Latte in lista»).
    static func maiuscola(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    // MARK: Il filo del discorso

    /// «Dicevi?», ma JARVIS aveva già detto tutto.
    static func avevoFinito() -> String {
        una("avevoFinito", [
            "Avevo finito, Sir. Mi ha fermato proprio sull'ultima parola.",
            "Era tutto: mi ha interrotto sul punto finale. Tempismo perfetto.",
            "Niente da aggiungere, Sir. Per una volta sono stato breve.",
            "[chuckles] Avevo già concluso, Sir. Le serve che ripeta qualcosa?",
            "Ero arrivato in fondo, Sir. Il resto era silenzio.",
            "Discorso chiuso, Sir. Se vuole, glielo riassumo in una riga.",
            "Avevo detto tutto. Mi creda, era un gran finale.",
        ])
    }

    /// 14 nov (il signore: «a volte riparte con un "ehm…" o "dicevo…" invece che dalla sillaba esatta: questo va bene ed è umano»):
    /// dopo un attimo in cui si è fermato per lui (ha detto «ma…» e ha lasciato perdere). Brevi, e non sempre: di solito riparte e basta.
    static let ripreseBrevi = ["Dicevo…", "Ehm, dicevo…", "Come dicevo…"]
    static func ripresaBreve() -> String? {
        guard Double.random(in: 0..<1) < 0.4 else { return nil }
        return una("ripresaBreve", ripreseBrevi)
    }

    /// Davanti al resto della risposta, dopo una pausa lunga: come una persona che ritrova il filo. Ogni tanto niente: riparte e basta.
    static func dicevo() -> String? {
        guard Double.random(in: 0..<1) < 0.85 else { return nil }
        return una("dicevo", [
            "Dicevo…", "Allora, dicevo:", "Riprendo il filo:", "Dunque, tornando a noi:", "Dove eravamo… ah, sì.", "Torno al punto:",
            "Ecco, dicevo:", "Riprendo da dove ero:", "Come stavo dicendo:",
        ])
    }

    // MARK: Le sezioni

    /// La frase quando si apre una sezione: tante varianti, la prima è quella di sempre. Nil: la sezione non ha frase.
    static func apertura(_ r: Reparto) -> String? {
        let m = momento
        var v: [String]
        switch r {
        case .sentinella: v = ["Sentinella in posizione, Sir.", "Sentinella attiva. Nessuno passa senza che io lo sappia.",
                              "Faccio io la guardia, Sir. Lei si rilassi.", "Perimetro sotto controllo. Occhio aperto.",
                              "Sentinella pronta: se si muove una foglia, glielo dico."]
        case .occhi: v = ["Occhi aperti, Sir.", "Vista attiva. Mi mostri pure.", "Ottiche accese: cosa guardiamo?",
                         "Eccomi: vedo quello che vede lei.", "Sensori ottici in linea, Sir."]
        case .giro: v = ["Sistemi ottici attivi. Cinque secondi, Sir: muova pure, cerco di non soffrire il mal di mare.",
                        "Panoramica: cinque secondi. Giri piano, io registro tutto.", "Giro d'orizzonte, Sir. Lei muova, io guardo.",
                        "Cinque secondi di riprese, Sir. Con calma: ho uno stomaco digitale delicato."]
        case .profiler: v = ["Profiler pronto. Inquadri il soggetto.", "Profiler acceso: mi faccia vedere di chi parliamo.",
                            "Pronto a profilare, Sir. Inquadratura frontale, se possibile."]
        case .cucina: v = ["Cucina. Inquadri frigo, dispensa o piatto, Sir.", "Modalità chef: mi mostri cosa abbiamo.",
                          "Apriamo la dispensa, Sir. Lei inquadri, al menù ci penso io."]
        case .scanner: v = ["Scanner pronto. Inquadri il codice a barre, Sir.", "Scanner acceso: avvicini il codice.",
                           "Pronto a leggere etichette, Sir. Le più piccole sono le mie preferite."]
        case .wiretap: return nil                    // registra: la voce di JARVIS finirebbe nella registrazione
        case .satellite: v = ["Satellite, Sir.", "Satellite agganciato. Dove andiamo?", "Collegamento orbitale stabilito, Sir.",
                             "In orbita, Sir. Mi dica il punto.", "Vista dall'alto pronta."]
        case .diario: v = ["Il diario, Sir.", "Il diario è aperto, Sir.", "Pagina bianca pronta, Sir.", "Il suo diario. Prometto discrezione."]
        case .sonno:
            v = ["Il suo sonno, Sir.", "Vediamo come ha dormito.", "Il rapporto della notte, Sir.", "Dati del sonno in arrivo."]
            if m == .notte { v += ["Il sonno, Sir. E a quest'ora, se posso, sarebbe anche il momento di praticarlo."] }
            if m == .mattina { v += ["Vediamo com'è andata la notte, Sir. Il caffè lo lascio a lei."] }
        case .cuore: v = ["Il suo cuore, Sir.", "Telemetria cardiaca in linea.", "Il motore principale, Sir. Vediamo i giri.",
                         "Battito sotto controllo, Sir. Ecco i numeri."]
        case .vitals: v = ["Vitals, Sir.", "Parametri vitali in linea.", "Diagnostica completa del pilota, Sir."]
        case .confidente: v = ["Confidente. La ascolto, Sir.", "Sono qui, Sir. Mi racconti.", "Resta tra noi, Sir. La ascolto.",
                              "Con calma, Sir. Ho tutto il tempo del mondo."]
        case .allenatore: v = ["Personal trainer pronto, Sir.", "Allenamento in linea. Si scaldi, io conto.",
                              "Trainer acceso. Oggi niente scuse, Sir.", "Pronto a contare le ripetizioni. Anche quelle che salterà."]
        case .bea: v = ["Bea, Sir.", "La sezione di Bea, Sir.", "Ecco Bea, Sir."]
        case .briefing:
            v = ["Il briefing, Sir.", "Il quadro della giornata, Sir.", "Briefing pronto: la giornata in un colpo d'occhio.",
                 "Ecco cosa ci aspetta, Sir."]
            if m == .mattina { v += ["Il briefing del mattino, Sir. Si prenda un caffè: è tutto qui."] }
        case .meteo:
            v = ["Il meteo, Sir.", "Vediamo cosa dice il cielo.", "Situazione atmosferica in arrivo.", "Il cielo, aggiornato al minuto."]
            if m == .mattina { v += ["Il meteo di oggi, Sir. Vediamo come vestirla."] }
            if m == .sera { v += ["Il cielo di stanotte e di domani, Sir."] }
        case .email: v = ["La posta, Sir.", "La sua posta, Sir. Prometto di non giudicare le newsletter.", "Casella aperta, Sir.",
                         "La posta, Sir: vediamo chi la cerca."]
        case .spesa: v = ["La lista della spesa, Sir.", "La spesa, Sir. Cosa manca in casa?", "Lista aperta. Detti pure, io scrivo.",
                         "La spesa, Sir: il frigo attende istruzioni."]
        case .shazam: v = ["Shazam. Faccia sentire, Sir.", "Orecchie tese: faccia partire la musica.", "Ascolto, Sir. Alzi pure il volume."]
        case .foto: v = ["Le sue foto, Sir.", "La galleria, Sir.", "I suoi scatti, Sir. Cosa cerchiamo?", "Archivio fotografico aperto, Sir."]
        case .ricordi: v = ["I ricordi, Sir.", "I suoi luoghi, Sir: la mappa di dove è stato.", "Ricordi aperti, Sir."]
        case .interprete: v = ["Interprete. In che lingua, Sir?", "Interprete pronto. Che lingua parliamo?",
                              "Traduzione simultanea, Sir: mi dica la lingua.", "Pronto a tradurre, Sir. In quale lingua?"]
        case .browser: v = ["Browser, Sir.", "La rete, Sir. Cosa cerchiamo?", "Navigatore aperto, Sir.", "Il web, Sir: tutto a portata di voce."]
        case .serata: v = ["I conti della serata, Sir.", "La serata, Sir: incassi e spese.", "I numeri della serata, Sir.",
                          "Contabilità della serata in linea, Sir."]
        case .messaggi: v = ["Messaggi, Sir. A chi scriviamo?", "Messaggi, Sir. Chi sentiamo?", "Pronto a scrivere, Sir. A chi?"]
        case .telefono: v = ["Telefono, Sir.", "Linea pronta, Sir. Chi chiamiamo?", "Centralino in linea, Sir."]
        case .lidar:
            #if os(iOS)
            v = ["LiDAR, Sir.", "LiDAR pronto, Sir. Scegliamo il modo.", "Sensore di profondità acceso, Sir."]
            #else
            v = ["LiDAR pronto. Muova l'iPhone lungo le pareti, Sir."]
            #endif
        case .github: v = ["Il cantiere su GitHub, Sir.", "Il cantiere, Sir. Vediamo chi ha lavorato.", "GitHub, Sir: il codice in un colpo d'occhio."]
        case .supabase: v = ["Sala macchine, Sir.", "Sala macchine: motori e serbatoi in vista.", "Supabase, Sir: il motore sotto il cofano."]
        case .archivio: v = ["L'archivio, Sir.", "Archivio aperto: tutto quello che abbiamo messo da parte.", "Gli schedari, Sir."]
        case .costi: v = ["I costi, Sir.", "Il conto dei servizi, Sir. Si sieda.", "I costi, Sir: vediamo quanto le costo.",
                         "La bolletta di casa JARVIS, Sir."]
        case .edith: v = ["EDITH, Sir.", "EDITH in linea, Sir.", "EDITH, Sir: protezione attiva."]
        case .sistemi: v = ["Sistemi, Sir.", "Diagnostica dei sistemi, Sir.", "Pannello sistemi aperto, Sir."]
        case .impostazioni: v = ["Impostazioni, Sir.", "Il pannello di controllo, Sir. Mi tratti bene.", "Impostazioni, Sir: ogni mia vite è qui."]
        case .pulisci: return nil                     // parla il cestino: carta appallottolata
        case .musica: v = ["La musica, Sir.", "La musica, Sir. Cosa mettiamo?", "Impianto pronto, Sir.", "La sala d'ascolto, Sir."]
        }
        if diFretta { return una("apertura.breve", ["Eccola.", "Ecco, Sir.", "Pronta.", "Aperta."]) }
        return una("apertura." + r.rawValue, v)
    }

    /// «Chiudi tutto».
    static func chiusoTutto() -> String {
        if diFretta { return lampo() }
        return una("chiusoTutto", ["Fatto, Sir. Tavolo sgombro.", "Tutto chiuso. Silenzio in sala.", "Sezioni a riposo, Sir.",
                                    "Ripulito. Si riparte da zero.", "Banco di lavoro sgombro, Sir.", "Chiuso tutto. Resto solo io."])
    }

    /// «Mettila da parte».
    static func messaDaParte(_ nome: String) -> String {
        if diFretta { return lampo() }
        return una("daParte", ["\(nome) messa da parte, Sir.", "\(nome) dietro le quinte. Resta lì, pronta.", "Parcheggiata, Sir.",
                               "La tengo da parte, Sir.", "\(nome) in panchina. La richiamo quando vuole."])
    }

    /// 14 nov · le mani subito: la pagina scorsa a voce («scendi», «torna su», «in fondo»). `dove`: com'è adesso (in cima, in fondo…).
    static func scorri(_ verso: String, dove: String) -> String {
        if diFretta { return lampo() }
        if dove == "in fondo" && verso != "fondo" { return una("scorri.fine", ["In fondo, Sir: non c'è altro.", "Fine pagina, Sir."]) }
        switch verso {
        case "su": return una("scorri.su", ["Su.", "Più su, Sir.", "Ecco, risalgo.", "Torniamo su."])
        case "cima": return una("scorri.cima", ["In cima, Sir.", "Dall'inizio.", "Torniamo in cima."])
        case "fondo": return una("scorri.fondo", ["In fondo, Sir.", "Fino in fondo.", "Eccoci in fondo."])
        default: return una("scorri.giu", ["Più giù.", "Scendo, Sir.", "Ecco il resto.", "Giù."])
        }
    }

    /// 14 nov · la vista dell'ologramma cambiata a voce («passa al globo»): «Globo, Sir.».
    static func vista(_ nome: String, gia: Bool) -> String {
        let n = maiuscola(nome.lowercased())
        if gia { return una("vista.gia", ["È già \(n), Sir.", "Ci siamo già: \(n)."]) }
        if diFretta { return n + "." }
        return una("vista", ["\(n), Sir.", "Ecco \(n).", "\(n).", "Passo a \(n), Sir."])
    }

    /// «Quella di prima».
    static func diPrima(_ nome: String) -> String {
        if diFretta { return lampo() }
        return una("diPrima", ["Ecco \(nome), Sir.", "Torna \(nome).", "Rieccola: \(nome).", "\(nome), di nuovo in scena."])
    }

    // MARK: La spesa

    /// Cose aggiunte alla lista; `totale`: quante cose ci sono adesso; `gia`: quelle che c'erano già.
    static func spesaAggiunta(_ cose: [String], totale: Int, gia: [String] = []) -> String {
        let nuove = cose.filter { c in !gia.contains { $0.caseInsensitiveCompare(c) == .orderedSame } }
        if nuove.isEmpty, let g = gia.first {
            return una("spesa.gia", ["\(maiuscola(g)) c'era già, Sir. Lo lascio una volta sola.", "\(maiuscola(g)) era già in lista: non lo raddoppio.",
                                      "Già segnato, Sir. Il frigo ringrazia per l'insistenza."])
        }
        if diFretta { return una("spesa.lampo", ["Segnato.", "In lista.", "Preso nota.", "Fatto."]) }
        let cosa = elenco(nuove)
        let base = una("spesa.aggiunta", ["\(maiuscola(cosa)) in lista, Sir.", "Segnato: \(cosa).", "\(maiuscola(cosa)): preso nota.",
                                          "Aggiunto \(cosa).", "\(maiuscola(cosa)) in lista."])
        guard spirito(0.45) else { return base }
        let coda: String
        switch totale {
        case ..<4: coda = una("spesa.poche", ["Lista ancora leggera.", "Per ora poca roba.", "Siamo a \(totale)."])
        case 4..<10: coda = una("spesa.medie", ["Siamo a \(totale) cose: il supermercato ci aspetta.", "Totale \(totale). Il carrello si scalda.",
                                                 "\(totale) voci in lista. Comincia a sembrare una spedizione."])
        default: coda = una("spesa.tante", ["Siamo a \(totale). Più che una spesa, un trasloco.", "\(totale) cose, Sir: le serve un carrello grande.",
                                             "[chuckles] \(totale) voci. Mi preparo a calcolare il percorso fra gli scaffali."])
        }
        return base + " " + coda
    }

    /// Cose tolte dalla lista (nil: non c'erano).
    static func spesaTolta(_ cose: [String], resta: Int) -> String {
        if diFretta { return una("spesa.via.lampo", ["Tolto.", "Via.", "Depennato."]) }
        let cosa = elenco(cose)
        let base = una("spesa.via", ["\(maiuscola(cosa)) via dalla lista.", "Depennato: \(cosa).", "Tolto \(cosa), Sir.", "\(maiuscola(cosa)): cancellato."])
        return resta == 0 ? base + " " + una("spesa.vuota", ["Lista vuota.", "Non resta niente.", "Tabula rasa, Sir."]) : base
    }

    /// Cose spuntate (nel carrello).
    static func spesaPresa(_ cose: [String], resta: Int) -> String {
        if resta == 0 {
            return una("spesa.finita", ["Lista completata, Sir. Missione compiuta.", "Tutto nel carrello. Ottimo lavoro di squadra.",
                                        "Ultima cosa presa, Sir. Si può andare alla cassa.", "[excited] Lista finita! Torniamo alla base, Sir."])
        }
        if diFretta { return una("spesa.presa.lampo", ["Preso.", "Nel carrello.", "Spuntato."]) }
        let cosa = elenco(cose)
        return una("spesa.presa", ["\(maiuscola(cosa)) nel carrello. Ne mancano \(resta).", "Preso \(cosa). Ancora \(resta).",
                                   "Spuntato \(cosa), Sir. Restano \(resta) cose."])
    }

    /// Le cose non trovate in lista.
    static func spesaNonCe(_ cosa: String) -> String {
        una("spesa.nonce", ["\(maiuscola(cosa)) non è in lista, Sir.", "Non trovo \(cosa) nella lista.", "In lista \(cosa) non c'è, Sir."])
    }

    // MARK: La posta

    static func postaAperta(_ nome: String, oggetto: String) -> String {
        if diFretta { return una("posta.lampo", ["Eccola.", "Aperta.", "Ecco, Sir."]) }
        return una("posta.apri", ["La mail di \(nome), Sir.", "Ecco \(nome): «\(oggetto)».", "Aperta. Scrive \(nome).",
                                  "\(nome), Sir. Vediamo cosa vuole.", "«\(oggetto)», da \(nome)."])
    }

    static func postaCartella(_ nome: String, quante: Int?) -> String {
        if nome == "Indesiderata" {
            return una("posta.spam", ["Indesiderata, Sir. Entriamo coi guanti.", "La posta che nessuno ha chiesto, Sir.", "Lo scantinato della casella, Sir."])
        }
        if nome == "Cestino" { return una("posta.cestino", ["Il cestino, Sir. Frughiamo con discrezione.", "Cestino aperto."]) }
        return una("posta.cartella", ["Cartella \(nome).", "Eccoci in \(nome), Sir.", "\(nome), Sir."])
    }

    static func postaNonLette(_ n: Int) -> String {
        switch n {
        case 0: return una("posta.zero", ["Nessuna da leggere, Sir. Casella in ordine.", "Tutto letto. Ammirevole, Sir.", "Zero non lette: un raro momento di pace."])
        case 1: return una("posta.una", ["Una sola da leggere, Sir.", "Una mail la aspetta."])
        default: return una("posta.tante", ["\(n) da leggere, Sir.", "Ecco le \(n) non lette.", "\(n) mail aspettano il suo verdetto, Sir."])
        }
    }

    // MARK: La musica (frasi cortissime: la musica è in pausa mentre JARVIS parla)

    static func musica(_ azione: String, acceso: Bool = true) -> String {
        switch azione {
        case "avanti": return una("mus.avanti", ["Avanti.", "Prossimo brano.", "Cambio pista, Sir.", "Ecco il prossimo."])
        case "indietro": return una("mus.indietro", ["Indietro.", "Torno al brano di prima.", "Riavvolgo, Sir."])
        case "pausa": return una("mus.pausa", ["In pausa.", "Pausa, Sir.", "Musica ferma."])
        case "play": return una("mus.play", ["Si riparte.", "Musica, Sir.", "Ripartiamo."])
        case "casuale": return acceso ? una("mus.casuale", ["Casuale: lascio decidere al destino.", "Ordine casuale, Sir."])
                                      : una("mus.ordine", ["Casuale spento: si torna all'ordine.", "Di nuovo in ordine, Sir."])
        case "ripeti": return acceso ? una("mus.ripeti", ["Lo stesso brano a ripetizione, Sir.", "Ripeti attivo: questo non ci stanca."])
                                     : una("mus.nonripeti", ["Ripeti spento.", "Basta replica, Sir."])
        default: return lampo()
        }
    }

    static func musicaMetti(_ nome: String) -> String {
        if diFretta { return una("mus.metti.lampo", ["Ecco.", "Parte.", "In onda."]) }
        let base = una("mus.metti", ["Ecco \(nome).", "Parte \(nome), Sir.", "\(nome): ottima scelta.", "Metto \(nome).", "In onda: \(nome)."])
        guard spirito(0.2) else { return base }
        return base + " " + una("mus.volume", ["Il volume lo lascio a lei: Apple non me lo permette.", "Alzi pure: io tengo il tempo."])
    }

    static func musicaCerca(_ testo: String, trovati: Int) -> String {
        if trovati == 0 { return una("mus.cerca.zero", ["Niente per «\(testo)», Sir.", "Apple Music non conosce «\(testo)»."]) }
        return una("mus.cerca", ["Ecco cosa trovo per «\(testo)».", "\(trovati) risultati per «\(testo)», Sir.", "Cercato: \(testo)."])
    }

    // MARK: Sistemi (GitHub, Supabase, Costi, Archivio)

    static func repoAperto(_ nome: String) -> String {
        if diFretta { return una("gh.lampo", ["\(nome).", "Eccolo.", "Aperto."]) }
        let base = una("gh.apri", ["Ecco \(nome), Sir.", "Cantiere \(nome): ultimi lavori a schermo.", "\(nome) sul tavolo.",
                                   "\(nome), aperto. Commit, issue, tutto in fila."])
        guard spirito(0.25) else { return base }
        return base + " " + una("gh.spirito", ["Il codice non mente. I commenti, a volte.", "Se trova un errore, è stato il compilatore.",
                                               "Ogni riga ha una storia. Alcune, un po' tormentate."])
    }

    /// La sala macchine ricontrollata: con gli errori del periodo, se ce ne sono.
    static func salaMacchine(errori: Int, ore: Int) -> String {
        if errori > 0 {
            return una("supa.errori", ["\(errori == 1 ? "Un errore" : "\(errori) errori") nelle ultime \(ore) ore, Sir: sono a schermo.",
                                       "Sala macchine ricontrollata: \(errori == 1 ? "c'è un errore" : "ci sono \(errori) errori") da guardare."])
        }
        if diFretta { return lampo() }
        let base = una("supa.agg", ["Sala macchine ricontrollata.", "Dati freschi dal motore, Sir.", "Motore ascoltato: ecco i valori.",
                                    "Ricontrollato tutto, Sir."])
        guard spirito(0.3) else { return base }
        return base + " " + una("supa.spirito", ["Nessun errore nel periodo: gira liscio.", "Zero errori. Il motore fa le fusa."])
    }

    static func costiRifatti() -> String {
        if diFretta { return lampo() }
        let base = una("costi.agg", ["Conti rifatti, Sir.", "Ricalcolato al centesimo.", "Ecco i conti aggiornati.", "Bilancio ricontrollato, Sir."])
        guard spirito(0.25) else { return base }
        return base + " " + una("costi.spirito", ["I numeri sono a schermo: li ho contati due volte.", "Nessuna sorpresa nascosta tra le righe."])
    }

    static func archivioTrovati(_ n: Int, _ cosa: String) -> String {
        if n == 0 { return una("arch.zero", ["Niente per «\(cosa)», Sir.", "Negli schedari «\(cosa)» non c'è.", "Archivio setacciato: di «\(cosa)» nessuna traccia."]) }
        if diFretta { return una("arch.lampo", ["\(n) file.", "Trovati."]) }
        return una("arch.cerca", ["\(n == 1 ? "Un file" : "\(n) file") per «\(cosa)», Sir.", "Schedari consultati: \(n == 1 ? "ne trovo uno" : "ne trovo \(n)").",
                                  "Ecco cosa trovo per «\(cosa)»."])
    }

    // MARK: 12.0 (12) · B2, B3, B6, il meteo

    /// B2: ha scritto in un campo di testo per lui.
    static func campoScritto(_ campo: String, _ testo: String) -> String {
        if diFretta { return una("campo.lampo", ["Scritto.", "Fatto.", "Eccolo."]) }
        return una("campo", ["Scritto, Sir.", "Ecco «\(testo)».", "Digitato per lei.", "«\(testo)»: fatto. Le dita può tenerle in tasca.",
                             "Scritto nel campo \(campo)."])
    }

    /// B3: ha annullato quello che aspettava il sì.
    static func annullato() -> String {
        una("annullato", ["Annullato, Sir.", "Fermo tutto. Non parte niente.", "Come non detto.", "Annullato. Resta tutto com'era."])
    }

    /// B3: ha cambiato idea e non vuole più niente.
    static func lasciamoStare() -> String {
        una("lasciamo", ["Va bene, lasciamo stare.", "Come non detto, Sir.", "Ricevuto: niente.", "D'accordo. Quando vuole, sono qui."])
    }

    /// B6: JARVIS propone quello che il signore fa di solito a quest'ora (`cosa`: «la spesa», «Sfera Ebbasta»…).
    static func propostaSezione(_ cosa: String) -> String {
        una("proposta.sez", ["Le apro \(cosa), come sempre a quest'ora?", "È l'ora in cui di solito apre \(cosa). Vado?",
                             "Le preparo \(cosa), Sir?", "Il solito, Sir? Le apro \(cosa)."])
    }

    static func propostaMusica(_ cosa: String) -> String {
        una("proposta.mus", ["Le metto \(cosa), come al solito?", "A quest'ora di solito c'è \(cosa). Vado?", "\(maiuscola(cosa)), Sir? È quasi tradizione.",
                             "Le faccio partire \(cosa)?"])
    }

    /// B1: «che tempo fa», detto da qualsiasi schermata (la sezione Meteo si apre e JARVIS dice il dato che conta).
    static func meteoAdesso(_ gradi: String, _ cielo: String, massima: String?, pioggia: Int?) -> String {
        let base: String
        if let m = massima {
            base = una("meteo.ora", ["Adesso \(gradi), \(cielo). Oggi si arriva a \(m).", "\(maiuscola(cielo)), \(gradi). Massima di oggi \(m).",
                                     "Fuori \(gradi) e \(cielo); oggi fino a \(m)."])
        } else {
            base = una("meteo.ora.breve", ["Adesso \(gradi), \(cielo).", "\(maiuscola(cielo)), \(gradi)."])
        }
        guard let p = pioggia else { return base }
        if p >= 50 { return base + " " + una("meteo.pioggia", ["Pioggia al \(p) per cento: meglio l'ombrello.", "L'ombrello oggi non è un vezzo, Sir.",
                                                                "Probabile pioggia: ombrello in tasca."]) }
        if p < 20, spirito(0.5) { return base + " " + una("meteo.asciutto", ["L'ombrello può restare a casa.", "Niente pioggia in vista.",
                                                                              "Cielo dalla nostra parte, Sir."]) }
        return base
    }

    // MARK: Messaggi e telefono

    static func messaggioA(_ nome: String) -> String {
        if diFretta { return una("msg.a.lampo", ["A \(nome).", "\(nome), Sir."]) }
        return una("msg.a", ["Scriviamo a \(nome). Detti pure.", "A \(nome), Sir. Cosa scriviamo?", "\(nome) in linea. La ascolto.",
                             "Pronto per \(nome), Sir: mi dica il testo."])
    }

    static func messaggioCanale(_ canale: String) -> String {
        una("msg.canale." + canale, ["Su \(canale).", "\(canale), Sir.", "Passo a \(canale)."])
    }

    static func telefonoComposto(_ numero: String) -> String {
        una("tel.componi", ["Numero in tastiera, Sir.", "Composto: \(numero).", "\(numero), pronto da chiamare."])
    }

    // MARK: Bea

    static func beaSegnato(_ tipo: String, _ testo: String) -> String {
        if diFretta { return una("bea.lampo", ["Segnato.", "Annotato, Sir.", "Fatto."]) }
        switch tipo {
        case "gusto": return una("bea.gusto", ["Annotato: le piace \(testo).", "\(maiuscola(testo)): in archivio fra le cose che ama.",
                                               "Segnato, Sir. Queste informazioni valgono oro."])
        case "non_piace": return una("bea.nonpiace", ["Annotato: niente \(testo). Evitiamo incidenti diplomatici.", "Segnato fra le cose da evitare."])
        case "promessa": return una("bea.promessa", ["Promessa registrata, Sir. Gliela ricorderò io.", "Annotata. Le promesse a Bea non scadono."])
        case "regalo", "idea": return una("bea.idea", ["Idea in cassaforte, Sir.", "Annotata. Al momento giusto gliela ricordo."])
        case "data": return una("bea.data", ["Data segnata, Sir. Avviso una settimana prima e il giorno stesso.", "In calendario mentale, Sir."])
        default: return una("bea.nota", ["Da non dimenticare: segnato.", "Annotato, Sir."])
        }
    }

    // MARK: Il meteo

    static func meteoAggiornato(_ gradi: String, _ cielo: String) -> String {
        una("meteo.agg", ["Aggiornato: \(gradi), \(cielo).", "Dati freschi, Sir: \(gradi) e \(cielo).", "Cielo ricontrollato: \(cielo), \(gradi)."])
    }

    /// La lista vuota letta.
    static func spesaVuota() -> String {
        una("spesa.vuota.letta", ["La lista è vuota, Sir. Frigo pieno o memoria corta?", "Niente da comprare, Sir. Per ora.",
                                   "Lista vuota. Il supermercato può aspettare."])
    }
}

// MARK: - 12.0 (16) · Il dialogo: i messaggi preparati, i widget FILO, il congedo, la fretta delle frasi secche

extension Battute {
    /// I numeri detti: 3 → «tre», 25 → «venticinque».
    static func numero(_ n: Int) -> String {
        let u = ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci", "undici", "dodici", "tredici",
                 "quattordici", "quindici", "sedici", "diciassette", "diciotto", "diciannove", "venti"]
        if n >= 0 && n <= 20 { return u[n] }
        let d = ["", "", "venti", "trenta", "quaranta", "cinquanta", "sessanta", "settanta", "ottanta", "novanta"]
        guard n < 100 else { return String(n) }
        let decina = d[n / 10], unita = n % 10
        if unita == 0 { return decina }
        return (unita == 1 || unita == 8 ? String(decina.dropLast()) : decina) + (unita == 3 ? "tré" : u[unita])
    }

    /// L'ora detta, con la preposizione: 1260 → «alle nove», 60 → «all'una», 720 → «a mezzogiorno», 1290 → «alle nove e mezza».
    static func allOra(_ minuti: Int) -> String {
        let ore = ["mezzanotte", "l'una", "le due", "le tre", "le quattro", "le cinque", "le sei", "le sette", "le otto", "le nove", "le dieci", "le undici", "mezzogiorno"]
        var h = (minuti / 60) % 24, m = minuti % 60
        let meno = m == 45
        if meno { h = (h + 1) % 24; m = 0 }
        let base = h == 0 ? ore[0] : h == 12 ? ore[12] : ore[h % 12 == 0 ? 12 : h % 12]
        var detta = base
        if meno { detta += " meno un quarto" } else if m == 30 { detta += " e mezza" } else if m == 15 { detta += " e un quarto" } else if m > 0 { detta += " e " + numero(m) }
        if detta.hasPrefix("l'") { return "all'" + detta.dropFirst(2) }
        if detta.hasPrefix("le ") { return "alle " + detta.dropFirst(3) }
        return "a " + detta
    }

#if os(iOS)                // i messaggi preparati, i widget FILO, i Preferiti: solo iPhone e Mac (al polso non ci sono)
    /// Il messaggio preparato, riletto: parte solo col sì.
    static func chiediMessaggio(_ chi: String, _ testo: String, whatsapp: Bool) -> String {
        "\(Filo.a(chi).capitalizzata)\(whatsapp ? " su WhatsApp" : ""): «\(testo)» " + una("msg.chiedi", ["Lo mando, Sir?", "Glielo mando così?", "Parte così, Sir?", "Lo mando?"])
    }
    static func mandato(_ chi: String) -> String {
        diFretta ? una("msg.ok.l", ["Mandato.", "Partito."]) : una("msg.ok", ["Mandato, Sir.", "Consegnato \(Filo.a(chi)).", "Partito.", "Inviato, Sir."])
    }
    static func fissato() -> String {
        diFretta ? lampo() : una("filo.fissa", ["Fissato, Sir.", "Lo tengo in vista.", "In vista, Sir.", "Resta lì, in alto.", "Appuntato in alto, Sir."])
    }
    static func staccato() -> String { diFretta ? lampo() : una("filo.togli", ["Tolto, Sir.", "Via da FILO.", "Fatto, Sir.", "Tolto."]) }
    static func angoloLibero() -> String { una("filo.tutti", ["FILO chiuso, Sir.", "Tolto tutto.", "Pulito."]) }
    static func ecco() -> String { diFretta ? lampo() : una("filo.ecco", ["Ecco, Sir.", "In vista.", "Ecco qui, Sir."]) }
    static func nienteDaMostrare() -> String {
        una("filo.niente", ["Non le ho ancora mostrato niente, Sir.", "Qui non c'è ancora niente da prendere, Sir.", "Mi manca il «questo», Sir."])
    }
    static func aChi() -> String { una("msg.achi", ["A chi, Sir?", "A chi lo mando, Sir?"]) }
    static func salvataMusica(_ titolo: String) -> String {
        diFretta ? una("mus.salva.l", ["Salvata.", "Nei Preferiti."]) : una("mus.salva", ["Salvata nei Preferiti, Sir.", "«\(titolo)» è nei Preferiti.", "Messa nei Preferiti, Sir."])
    }

#endif
    /// Il congedo: solo alla fine di una cosa vera, sempre variato (il signore, 13 nov).
    static func congedo() -> String {
        una("congedo", ["Sarà tutto, Sir?", "Le serve altro, Sir?", "Altro per lei, Sir?", "Posso fare altro, Sir?", "Nient'altro, Sir?", "C'è altro, Sir?", "Will that be all, Sir?"])
    }
    static func congedoOk() -> String { una("congedo.ok", ["Molto bene, Sir.", "A disposizione.", "Bene così, Sir.", "Quando vuole, Sir."]) }
    static func prego() -> String { una("prego", ["Prego, Sir.", "Dovere, Sir.", "Si figuri, Sir."]) }

    /// La fretta dalle frasi secche (il mockup 12.0 (16)): una frase di due o tre parole (o quattro senza parole che legano) è un
    /// segno, doppio se arriva a raffica appena JARVIS ha finito; due punti in un minuto: risposte di una riga per tre minuti.
    /// «Veloce», «al volo», «in breve»: subito; «con calma», «raccontami», una frase lunga: niente fretta.
    static func ritmo(_ frase: String, dopoRisposta secondi: TimeInterval?) {
        let p = FineFrase.paroleNude(frase)
        let n = p.joined(separator: " ")
        if ["veloce", "al volo", "in breve", "in due parole", "sbrigati", "taglia corto", "di corsa", "ho fretta", "rapido", "svelto"].contains(where: { n.contains($0) }) {
            umoreSentito = (.fretta, Date()); segniFretta = []; return
        }
        if ["con calma", "raccontami", "spiegami", "fammi capire"].contains(where: { n.contains($0) }) || p.count >= 10 {
            if umoreSentito.umore == .fretta { umoreSentito = (.normale, Date()) }
            segniFretta = []; return
        }
        let legano: Set<String> = ["che", "come", "quanto", "quanti", "quando", "dove", "chi", "cosa", "il", "lo", "la", "i", "gli", "le", "un", "una",
                                   "di", "del", "della", "al", "alla", "per", "mi", "ci", "fa", "ho", "hai", "e", "grazie", "favore", "scusa"]
        guard p.count <= 3 || (p.count <= 4 && p.allSatisfy { !legano.contains($0) }), !p.contains(where: { ["grazie", "favore", "scusa"].contains($0) }) else { return }
        let ora = Date()
        let peso: Int = (secondi ?? 99) < 2.5 ? 2 : 1
        let segno: (quando: Date, peso: Int) = (quando: ora, peso: peso)
        segniFretta = segniFretta.filter { ora.timeIntervalSince($0.quando) < 60 } + [segno]
        if segniFretta.reduce(0, { (somma: Int, s: (quando: Date, peso: Int)) in somma + s.peso }) >= 2 { umoreSentito = (.fretta, ora) }
    }
    private static var segniFretta: [(quando: Date, peso: Int)] = []
}
