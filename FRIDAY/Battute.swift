import Foundation

// MARK: - Le battute di FRIDAY (nate da quelle di JARVIS 12.0 (10): stesse regole, voce di FRIDAY: donna, dà del tu a Bea)
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
    private static let lampi = ["Fatto.", "Eccolo.", "Ci sono.", "Andata.", "Sistemato.", "Fatto, Bea.", "Preso.", "Subito."]
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
            "Avevo finito. Mi hai fermata proprio sull'ultima parola.",
            "Era tutto: mi hai interrotta sul punto finale. Tempismo perfetto.",
            "Niente da aggiungere. Per una volta sono stata breve.",
            "Avevo già concluso. Vuoi che ripeta qualcosa?",
            "Ero arrivata in fondo. Il resto era silenzio.",
            "Discorso chiuso. Se vuoi te lo riassumo in una riga.",
            "Avevo detto tutto. Credimi, era un gran finale.",
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
        case .occhi: v = ["Occhi aperti.", "Vista attiva: fammi vedere.", "Ottiche accese: cosa guardiamo?",
                         "Eccomi: vedo quello che vedi tu.", "Occhi in linea, Bea."]
        case .giro: v = ["Cinque secondi: gira piano, io guardo tutto.", "Panoramica: cinque secondi. Con calma, registro io.",
                        "Giro d'orizzonte: tu muovi, io guardo.", "Cinque secondi di riprese. Piano, che mi gira la testa."]
        case .cucina: v = ["Cucina. Inquadra frigo, dispensa o piatto.", "Modalità chef: fammi vedere cosa c'è.",
                          "Apriamo la dispensa: tu inquadri, al menù ci penso io."]
        case .scanner: v = ["Scanner pronto: inquadra il codice a barre.", "Scanner acceso: avvicina il codice.",
                           "Pronta a leggere etichette. Le più piccole sono le mie preferite."]
        case .diario: v = ["Il diario.", "Il tuo diario è aperto.", "Pagina bianca pronta.", "Il tuo diario. Prometto discrezione."]
        case .sonno:
            v = ["Il tuo sonno.", "Vediamo come hai dormito.", "Il riassunto della notte.", "Ecco i dati del sonno."]
            if m == .notte { v += ["Il sonno. E a quest'ora, se posso, sarebbe il momento di farlo davvero."] }
            if m == .mattina { v += ["Vediamo com'è andata la notte. Il caffè lo lascio a te."] }
        case .vitals: v = ["Vitals.", "I tuoi parametri.", "Come stai, in numeri."]
        case .confidente: v = ["Sono qui. Ti ascolto.", "Raccontami.", "Resta tra noi. Ti ascolto.", "Con calma: ho tutto il tempo del mondo."]
        case .allenatore: v = ["Lo specchio. Pronta quando vuoi.", "Reformer in linea: scaldati, io conto.",
                              "Si comincia. Oggi niente scuse.", "Pronta a contare le ripetizioni. Anche quelle che salterai."]
        case .email: v = ["La posta.", "La tua posta. Prometto di non giudicare le newsletter.", "Casella aperta.", "Vediamo chi ti cerca."]
        case .spesa: v = ["La lista della spesa.", "La spesa: cosa manca in casa?", "Lista aperta: detta pure, scrivo io.",
                         "La spesa: il frigo aspetta istruzioni."]
        case .foto: v = ["Le tue foto.", "La galleria.", "I tuoi scatti: cosa cerchiamo?", "Ecco le tue foto."]
        case .ricordi: v = ["La memoria.", "I tuoi luoghi: la mappa di dove sei stata.", "Ecco cosa ricordo."]
        case .interprete: v = ["Interprete: in che lingua?", "Interprete pronto. Che lingua parliamo?",
                              "Traduzione in diretta: dimmi la lingua.", "Pronta a tradurre. In quale lingua?"]
        case .messaggi: v = ["Messaggi: a chi scriviamo?", "Messaggi: chi sentiamo?", "Pronta a scrivere. A chi?"]
        case .telefono: v = ["Telefono.", "Linea pronta: chi chiamiamo?", "Telefono in linea."]
        case .edith: v = ["Difesa.", "Difesa attiva.", "Scudi su: sono qui."]
        case .pulisci: return nil                     // parla il cestino: carta appallottolata
        case .musica: v = ["La musica.", "La musica: cosa mettiamo?", "Musica pronta.", "Cosa ascoltiamo?"]
        case .frigo: v = ["Il frigo.", "Vediamo cosa c'è in frigo.", "Frigo aperto: inquadralo e ti dico cosa scade prima."]
        case .pilates: v = ["Pilates.", "Pilates: allenamento, Reel o lezioni?", "Reformer pronto. Anche tu?"]
        case .makeup: v = ["Lo specchio.", "Makeup: mettiti in luce.", "Specchio acceso: si comincia dalla base."]
        case .ciclo: v = ["Il ciclo.", "Il tuo ciclo, con i dati di Salute.", "Ecco a che punto sei."]
        case .testa: v = ["Testa.", "Come va la testa?", "Diario della testa aperto. Piano con le luci."]
        case .gestionale: v = ["Il gestionale.", "Le tue lezioni e le tue clienti.", "Gestionale aperto: chi c'è oggi?"]
        case .armadio: v = ["L'armadio.", "Il tuo armadio: cosa mettiamo?", "Armadio aperto. Prometto di non giudicare."]
        case .nando: v = ["Nando.", "La sezione di Nando.", "Nando: pipì, giri e coccole."]
        case .account: v = ["Il tuo account.", "Account: i tuoi collegamenti.", "Ecco cosa è collegato."]
        case .sos: return "Mando l'aiuto ad Ale tra cinque secondi. Tocca annulla se è un errore."
        }
        if diFretta { return una("apertura.breve", ["Eccola.", "Ecco.", "Pronta.", "Aperta."]) }
        return una("apertura." + r.rawValue, v)
    }

    /// «Chiudi tutto».
    static func chiusoTutto() -> String {
        if diFretta { return lampo() }
        return una("chiusoTutto", ["Fatto. Tutto in ordine.", "Tutto chiuso. Silenzio in sala.", "Sezioni a riposo.",
                                    "Ripulito. Si riparte da zero.", "Schermo libero.", "Chiuso tutto. Resto solo io."])
    }

    /// «Mettila da parte».
    static func messaDaParte(_ nome: String) -> String {
        if diFretta { return lampo() }
        return una("daParte", ["\(nome) messa da parte.", "\(nome) dietro le quinte. Resta lì, pronta.", "Parcheggiata.",
                               "La tengo da parte.", "\(nome) in panchina. La richiamo quando vuoi."])
    }

    /// «Quella di prima».
    static func diPrima(_ nome: String) -> String {
        if diFretta { return lampo() }
        return una("diPrima", ["Ecco \(nome).", "Torna \(nome).", "Rieccola: \(nome).", "\(nome), di nuovo in scena."])
    }

    // MARK: La spesa

    /// Cose aggiunte alla lista; `totale`: quante cose ci sono adesso; `gia`: quelle che c'erano già.
    static func spesaAggiunta(_ cose: [String], totale: Int, gia: [String] = []) -> String {
        let nuove = cose.filter { c in !gia.contains { $0.caseInsensitiveCompare(c) == .orderedSame } }
        if nuove.isEmpty, let g = gia.first {
            return una("spesa.gia", ["\(maiuscola(g)) c'era già: lo lascio una volta sola.", "\(maiuscola(g)) era già in lista: non lo raddoppio.",
                                      "Già segnato. Il frigo ringrazia per l'insistenza."])
        }
        if diFretta { return una("spesa.lampo", ["Segnato.", "In lista.", "Preso nota.", "Fatto."]) }
        let cosa = elenco(nuove)
        let base = una("spesa.aggiunta", ["\(maiuscola(cosa)) in lista.", "Segnato: \(cosa).", "\(maiuscola(cosa)): preso nota.",
                                          "Aggiunto \(cosa).", "\(maiuscola(cosa)) in lista."])
        guard spirito(0.45) else { return base }
        let coda: String
        switch totale {
        case ..<4: coda = una("spesa.poche", ["Lista ancora leggera.", "Per ora poca roba.", "Siamo a \(totale)."])
        case 4..<10: coda = una("spesa.medie", ["Siamo a \(totale) cose: il supermercato ci aspetta.", "Totale \(totale). Il carrello si scalda.",
                                                 "\(totale) voci in lista. Comincia a sembrare una spedizione."])
        default: coda = una("spesa.tante", ["Siamo a \(totale). Più che una spesa, un trasloco.", "\(totale) cose: ti serve un carrello grande.",
                                             "\(totale) voci. Ti preparo il percorso fra gli scaffali."])
        }
        return base + " " + coda
    }

    /// Cose tolte dalla lista (nil: non c'erano).
    static func spesaTolta(_ cose: [String], resta: Int) -> String {
        if diFretta { return una("spesa.via.lampo", ["Tolto.", "Via.", "Depennato."]) }
        let cosa = elenco(cose)
        let base = una("spesa.via", ["\(maiuscola(cosa)) via dalla lista.", "Depennato: \(cosa).", "Tolto \(cosa).", "\(maiuscola(cosa)): cancellato."])
        return resta == 0 ? base + " " + una("spesa.vuota", ["Lista vuota.", "Non resta niente.", "Tabula rasa."]) : base
    }

    /// Cose spuntate (nel carrello).
    static func spesaPresa(_ cose: [String], resta: Int) -> String {
        if resta == 0 {
            return una("spesa.finita", ["Lista completata. Missione compiuta.", "Tutto nel carrello. Ottimo lavoro di squadra.",
                                        "Ultima cosa presa: si può andare alla cassa.", "Lista finita! Si torna a casa."])
        }
        if diFretta { return una("spesa.presa.lampo", ["Preso.", "Nel carrello.", "Spuntato."]) }
        let cosa = elenco(cose)
        return una("spesa.presa", ["\(maiuscola(cosa)) nel carrello. Ne mancano \(resta).", "Preso \(cosa). Ancora \(resta).",
                                   "Spuntato \(cosa). Restano \(resta) cose."])
    }

    /// Le cose non trovate in lista.
    static func spesaNonCe(_ cosa: String) -> String {
        una("spesa.nonce", ["\(maiuscola(cosa)) non è in lista.", "Non trovo \(cosa) nella lista.", "In lista \(cosa) non c'è."])
    }

    // MARK: La posta

    static func postaAperta(_ nome: String, oggetto: String) -> String {
        if diFretta { return una("posta.lampo", ["Eccola.", "Aperta.", "Ecco."]) }
        return una("posta.apri", ["La mail di \(nome).", "Ecco \(nome): «\(oggetto)».", "Aperta. Scrive \(nome).",
                                  "\(nome): vediamo cosa vuole.", "«\(oggetto)», da \(nome)."])
    }

    static func postaCartella(_ nome: String, quante: Int?) -> String {
        if nome == "Indesiderata" {
            return una("posta.spam", ["Indesiderata: entriamo coi guanti.", "La posta che nessuno ha chiesto.", "Lo scantinato della casella."])
        }
        if nome == "Cestino" { return una("posta.cestino", ["Il cestino: frughiamo con discrezione.", "Cestino aperto."]) }
        return una("posta.cartella", ["Cartella \(nome).", "Eccoci in \(nome).", "\(nome)."])
    }

    static func postaNonLette(_ n: Int) -> String {
        switch n {
        case 0: return una("posta.zero", ["Nessuna da leggere: casella in ordine.", "Tutto letto. Brava.", "Zero non lette: un raro momento di pace."])
        case 1: return una("posta.una", ["Una sola da leggere.", "Una mail ti aspetta."])
        default: return una("posta.tante", ["\(n) da leggere.", "Ecco le \(n) non lette.", "\(n) mail aspettano il tuo verdetto."])
        }
    }

    // MARK: La musica (frasi cortissime: la musica è in pausa mentre FRIDAY parla)

    static func musica(_ azione: String, acceso: Bool = true) -> String {
        switch azione {
        case "avanti": return una("mus.avanti", ["Avanti.", "Prossimo brano.", "Cambio pista.", "Ecco il prossimo."])
        case "indietro": return una("mus.indietro", ["Indietro.", "Torno al brano di prima.", "Riavvolgo."])
        case "pausa": return una("mus.pausa", ["In pausa.", "Pausa.", "Musica ferma."])
        case "play": return una("mus.play", ["Si riparte.", "Musica.", "Ripartiamo."])
        case "casuale": return acceso ? una("mus.casuale", ["Casuale: lascio decidere al destino.", "Ordine casuale."])
                                      : una("mus.ordine", ["Casuale spento: si torna all'ordine.", "Di nuovo in ordine."])
        case "ripeti": return acceso ? una("mus.ripeti", ["Lo stesso brano a ripetizione.", "Ripeti attivo: questo non ci stanca."])
                                     : una("mus.nonripeti", ["Ripeti spento.", "Basta replica."])
        default: return lampo()
        }
    }

    static func musicaMetti(_ nome: String) -> String {
        if diFretta { return una("mus.metti.lampo", ["Ecco.", "Parte.", "In onda."]) }
        let base = una("mus.metti", ["Ecco \(nome).", "Parte \(nome).", "\(nome): ottima scelta.", "Metto \(nome).", "In onda: \(nome)."])
        guard spirito(0.2) else { return base }
        return base + " " + una("mus.volume", ["Il volume lo lasci a te: Apple non me lo fa toccare.", "Alza pure: io tengo il tempo."])
    }

    static func musicaCerca(_ testo: String, trovati: Int) -> String {
        if trovati == 0 { return una("mus.cerca.zero", ["Niente per «\(testo)».", "Non trovo «\(testo)»."]) }
        return una("mus.cerca", ["Ecco cosa trovo per «\(testo)».", "\(trovati) risultati per «\(testo)».", "Cercato: \(testo)."])
    }

    // MARK: 12.0 (12) · B2, B3, B6, il meteo

    /// B2: ha scritto in un campo di testo per lui.
    static func campoScritto(_ campo: String, _ testo: String) -> String {
        if diFretta { return una("campo.lampo", ["Scritto.", "Fatto.", "Eccolo."]) }
        return una("campo", ["Scritto.", "Ecco «\(testo)».", "Scritto per te.", "«\(testo)»: fatto. Le dita puoi tenerle in tasca.",
                             "Scritto nel campo \(campo)."])
    }

    /// B3: ha annullato quello che aspettava il sì.
    static func annullato() -> String {
        una("annullato", ["Annullato.", "Fermo tutto. Non parte niente.", "Come non detto.", "Annullato. Resta tutto com'era."])
    }

    /// B3: ha cambiato idea e non vuole più niente.
    static func lasciamoStare() -> String {
        una("lasciamo", ["Va bene, lasciamo stare.", "Come non detto.", "Ricevuto: niente.", "D'accordo. Quando vuoi, sono qui."])
    }

    /// B6: FRIDAY propone quello che Bea fa di solito a quest'ora (`cosa`: «la spesa», una playlist…).
    static func propostaSezione(_ cosa: String) -> String {
        una("proposta.sez", ["Ti apro \(cosa), come sempre a quest'ora?", "È l'ora in cui di solito apri \(cosa). Vado?",
                             "Ti preparo \(cosa)?", "Il solito? Ti apro \(cosa)."])
    }

    static func propostaMusica(_ cosa: String) -> String {
        una("proposta.mus", ["Ti metto \(cosa), come al solito?", "A quest'ora di solito c'è \(cosa). Vado?", "\(maiuscola(cosa))? È quasi tradizione.",
                             "Ti faccio partire \(cosa)?"])
    }

    // MARK: Messaggi e telefono

    static func messaggioA(_ nome: String) -> String {
        if diFretta { return una("msg.a.lampo", ["A \(nome).", "\(nome)."]) }
        return una("msg.a", ["Scriviamo a \(nome): detta pure.", "A \(nome): cosa scriviamo?", "\(nome) in linea. Ti ascolto.",
                             "Pronta per \(nome): dimmi il testo."])
    }

    static func messaggioCanale(_ canale: String) -> String {
        una("msg.canale." + canale, ["Su \(canale).", "\(canale).", "Passo a \(canale)."])
    }

    static func telefonoComposto(_ numero: String) -> String {
        una("tel.componi", ["Numero in tastiera.", "Composto: \(numero).", "\(numero), pronto da chiamare."])
    }

    /// La lista vuota letta.
    static func spesaVuota() -> String {
        una("spesa.vuota.letta", ["La lista è vuota. Frigo pieno o memoria corta?", "Niente da comprare. Per ora.",
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
        "\(Filo.a(chi).capitalizzata)\(whatsapp ? " su WhatsApp" : ""): «\(testo)» " + una("msg.chiedi", ["Lo mando?", "Glielo mando così?", "Parte così?", "Invio?"])
    }
    static func mandato(_ chi: String) -> String {
        diFretta ? una("msg.ok.l", ["Mandato.", "Partito."]) : una("msg.ok", ["Mandato.", "Consegnato \(Filo.a(chi)).", "Partito.", "Inviato."])
    }
    static func fissato() -> String {
        diFretta ? lampo() : una("filo.fissa", ["Fissato.", "Lo tengo in vista.", "In vista.", "Resta lì, in alto.", "Appuntato in alto."])
    }
    static func staccato() -> String { diFretta ? lampo() : una("filo.togli", ["Tolto.", "Via da FILO.", "Fatto.", "Via."]) }
    static func angoloLibero() -> String { una("filo.tutti", ["FILO chiuso.", "Tolto tutto.", "Pulito."]) }
    static func ecco() -> String { diFretta ? lampo() : una("filo.ecco", ["Ecco.", "In vista.", "Ecco qui."]) }
    static func nienteDaMostrare() -> String {
        una("filo.niente", ["Non ti ho ancora mostrato niente.", "Qui non c'è ancora niente da prendere.", "Mi manca il «questo»."])
    }
    static func aChi() -> String { una("msg.achi", ["A chi?", "A chi lo mando?"]) }
    static func salvataMusica(_ titolo: String) -> String {
        diFretta ? una("mus.salva.l", ["Salvata.", "Nei Preferiti."]) : una("mus.salva", ["Salvata nei Preferiti.", "«\(titolo)» è nei Preferiti.", "Messa nei Preferiti."])
    }

#endif
    /// Il congedo: solo alla fine di una cosa vera, sempre variato (il signore, 13 nov).
    static func congedo() -> String {
        una("congedo", ["Ti serve altro?", "Altro per te?", "Posso fare altro?", "Nient'altro?", "C'è altro, Bea?", "Tutto a posto così?"])
    }
    static func congedoOk() -> String { una("congedo.ok", ["Perfetto.", "Sono qui.", "Bene così.", "Quando vuoi."]) }
    static func prego() -> String { una("prego", ["Prego!", "Figurati.", "Di niente, Bea."]) }

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
