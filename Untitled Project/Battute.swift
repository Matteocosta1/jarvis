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

    /// Il signore va di fretta: un comando a pochi secondi dall'ultima battuta.
    static var diFretta: Bool { Date().timeIntervalSince(ultimaDetta) < 6 }

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
        momento != .notte && !diFretta && Double.random(in: 0..<1) < probabilita
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

    /// La lista vuota letta.
    static func spesaVuota() -> String {
        una("spesa.vuota.letta", ["La lista è vuota, Sir. Frigo pieno o memoria corta?", "Niente da comprare, Sir. Per ora.",
                                   "Lista vuota. Il supermercato può aspettare."])
    }
}
