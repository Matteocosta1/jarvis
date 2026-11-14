import Foundation
import WatchKit

// MARK: - 12.0 (10) · LA REGIA AL POLSO
//
// Come sull'iPhone, nei limiti dell'orologio: il cervello vede quale sezione è aperta sul polso e la muove con lo stesso
// strumento «regia» (descritto dall'app, il cervello non va ripubblicato): apre e chiude le sezioni dell'orologio e comanda la
// musica dell'iPhone. Sul polso si apre una sezione alla volta e non ci sono azioni da confermare (inviare, eliminare, chiamare
// vivono sull'iPhone). Con la MUSICA davanti, «pausa», «avanti», «indietro», «play» partono subito, senza il cervello, con la
// battuta di JARVIS (Battute, la stessa dell'iPhone).

@MainActor final class RegiaPolso {
    static let condivisa = RegiaPolso()

    /// Una sezione del polso: il nome (come sull'iPhone), le parole con cui si chiama, dove si apre.
    struct Meta {
        let nome: String
        let chiavi: [String]
        let reparto: Reparto?
        let polso: SchermataPolso?
    }

    /// Le sezioni che si aprono sull'orologio (le altre vivono sull'iPhone).
    static let mete: [Meta] = [
        Meta(nome: "Meteo", chiavi: ["meteo", "tempo", "previsioni"], reparto: .meteo, polso: nil),
        Meta(nome: "Spesa", chiavi: ["spesa", "lista", "listadellaspesa", "listaspesa"], reparto: .spesa, polso: nil),
        Meta(nome: "Email", chiavi: ["email", "posta", "mail"], reparto: .email, polso: nil),
        Meta(nome: "Musica", chiavi: ["musica", "lettore", "canzoni", "brani"], reparto: .musica, polso: nil),
        Meta(nome: "Diario", chiavi: ["diario"], reparto: .diario, polso: nil),
        Meta(nome: "Sonno", chiavi: ["sonno", "dormito"], reparto: .sonno, polso: nil),
        Meta(nome: "Cuore", chiavi: ["cuore", "battito", "battiti"], reparto: .cuore, polso: nil),
        Meta(nome: "Briefing", chiavi: ["briefing", "riepilogo", "giornata"], reparto: .briefing, polso: nil),
        Meta(nome: "Serata", chiavi: ["serata", "incassi"], reparto: .serata, polso: nil),
        Meta(nome: "Bea", chiavi: ["bea", "beatrice"], reparto: .bea, polso: nil),
        Meta(nome: "Ricordi", chiavi: ["ricordi", "luoghi"], reparto: .ricordi, polso: nil),
        Meta(nome: "Shazam", chiavi: ["shazam"], reparto: .shazam, polso: nil),
        Meta(nome: "Vitals", chiavi: ["vitals", "parametri", "salute"], reparto: .vitals, polso: nil),
        Meta(nome: "Organismo", chiavi: ["organismo", "scansioneorganismo"], reparto: nil, polso: .organismo),
        Meta(nome: "Sentinella", chiavi: ["sentinella", "guardia"], reparto: .sentinella, polso: nil),
        Meta(nome: "Satellite", chiavi: ["satellite", "mappa", "intelligence"], reparto: nil, polso: .satellite(nil)),
        Meta(nome: "Travel", chiavi: ["travel", "viaggio", "mezzi"], reparto: nil, polso: .travel("", "")),
        Meta(nome: "Radar", chiavi: ["radar", "radarpioggia"], reparto: nil, polso: .radar),
        Meta(nome: "Traccia", chiavi: ["traccia"], reparto: nil, polso: .traccia),
        Meta(nome: "Priorità", chiavi: ["priorita"], reparto: nil, polso: .priorita),
        Meta(nome: "Protocolli", chiavi: ["protocolli", "protocollo"], reparto: nil, polso: .protocolli(nil)),
        Meta(nome: "Social", chiavi: ["social", "instagram"], reparto: nil, polso: .social(nil)),
        Meta(nome: "Sistemi", chiavi: ["sistemi"], reparto: .sistemi, polso: nil),
        Meta(nome: "GitHub", chiavi: ["github", "cantiere", "repository"], reparto: .github, polso: nil),
        Meta(nome: "Supabase", chiavi: ["supabase", "database", "salamacchine"], reparto: .supabase, polso: nil),
        Meta(nome: "Archivio", chiavi: ["archivio", "file", "documenti"], reparto: .archivio, polso: nil),
        Meta(nome: "Costi", chiavi: ["costi", "consumi"], reparto: .costi, polso: nil),
        Meta(nome: "Impostazioni", chiavi: ["impostazioni", "opzioni"], reparto: .impostazioni, polso: nil),
    ]

    /// La sezione aperta sul polso (nil: la schermata principale). La scrive la schermata.
    var davanti: String?
    /// L'ultimo stato della musica dell'iPhone visto dal polso (lo aggiorna la sezione MUSICA, o un comando della regia).
    var musica: PonteOrologio.StatoMusica?
    /// Le strade della schermata: aprire una sezione (o una schermata del polso) e tornare alla principale.
    var apri: ((Reparto) -> Void)?
    var apriPolso: ((SchermataPolso) -> Void)?
    var chiudi: (() -> Void)?
    private var eventi: [(quando: Date, testo: String)] = []

    private init() {}

    // MARK: I nomi

    static func meta(_ detto: String) -> Meta? {
        let k = chiave(detto)
        guard !k.isEmpty else { return nil }
        return mete.first { chiave($0.nome) == k || $0.chiavi.contains(k) }
    }

    static func nome(_ r: Reparto) -> String { mete.first { $0.reparto == r }?.nome ?? r.rawValue.capitalized }

    static func nome(_ s: SchermataPolso) -> String {
        switch s {
        case .protocolli: return "Protocolli"
        case .traccia: return "Traccia"
        case .radar: return "Radar"
        case .priorita: return "Priorità"
        case .organismo: return "Organismo"
        case .satellite: return "Satellite"
        case .social: return "Social"
        case .travel: return "Travel"
        }
    }

    /// Il nome ridotto all'osso per i confronti: minuscole, senza accenti, solo lettere e cifre.
    static func chiave(_ s: String) -> String {
        String(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            .filter { $0.isLetter || $0.isNumber })
    }

    private func evento(_ testo: String) {
        eventi.append((Date(), testo))
        if eventi.count > 6 { eventi.removeFirst(eventi.count - 6) }
    }

    // MARK: Il catalogo per il cervello

    /// Va nella riga [Schermo] (una riga): cosa c'è davanti sul polso, cosa si apre, le strade di sempre, cosa è appena successo.
    func catalogo() -> String {
        var pezzi: [String] = ["REGIA AL POLSO (strumento «regia»: sezione, azione, valori; sull'orologio si apre una sezione alla volta)"]
        if let d = davanti {
            var riga = "DAVANTI \(d)"
            if d == "Musica", let m = musica, m.errore == nil { riga += ": " + (m.suona ? "suona" : "in pausa") + " «\(m.titolo)» di \(m.artista)" }
            pezzi.append(riga)
        } else {
            pezzi.append("DAVANTI JARVIS (la schermata principale dell'orologio)")
        }
        pezzi.append("SI APRONO SUL POLSO: " + Self.mete.map(\.nome).joined(separator: ", "))
        pezzi.append("SEMPRE: apri(sezione), chiudi (torna alla schermata principale); Musica: play, pausa, avanti, indietro (la musica dell'iPhone, anche a sezione chiusa)")
        pezzi.append("Occhi, LiDAR, Messaggi, Telefono, Studio e le altre vivono sull'iPhone")
        if let p = PianoPolso.condiviso.perCervello { pezzi.append(p) }                // 14 nov: il piano in corso
        if Battute.umore == .fretta { pezzi.append("RITMO: il signore ha fretta: rispondi in una riga sola (se poi dice «dimmi meglio», la versione intera)") }   // 13.0
        let recenti = eventi.filter { Date().timeIntervalSince($0.quando) < 600 }
        if !recenti.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            pezzi.append("APPENA: " + recenti.map { "\(f.string(from: $0.quando)) \($0.testo)" }.joined(separator: "; "))
        }
        return pezzi.joined(separator: " ‖ ")
    }

    /// Lo strumento «regia» com'è descritto al cervello dall'orologio (`strumenti_client_def`).
    static let definizione: [String: Any] = [
        "name": "regia",
        "description": "La regia dell'orologio, come JARVIS nell'armatura di Tony: apri e chiudi le sezioni del polso e comanda la musica dell'iPhone (play, pausa, avanti, indietro), come scritto dopo REGIA nella riga [Schermo]. Più passi in una chiamata, in ordine. Agisci e intanto parla come JARVIS con Tony in missione: una frase brevissima e viva col dato che conta, una battuta asciutta quando ci sta; mai «comando eseguito», mai elenchi.",
        "input_schema": [
            "type": "object",
            "properties": [
                "passi": [
                    "type": "array",
                    "description": "I passi in ordine, al massimo 4.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "sezione": ["type": "string", "description": "Il nome della sezione (Meteo, Musica, Cuore…); vuoto per chiudi"],
                            "azione": ["type": "string", "description": "apri, chiudi, oppure play, pausa, avanti, indietro (Musica)"],
                            "valori": ["type": "object", "description": "Valori dell'azione, come testo (Travel: {\"luogo\": \"…\"})",
                                       "additionalProperties": ["type": "string"]],
                        ] as [String: Any],
                        "required": ["azione"],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
            "required": ["passi"],
        ] as [String: Any],
    ]

    // MARK: Lo strumento del cervello

    /// Esegue i passi in ordine e dice al cervello com'è andata e cosa c'è adesso davanti sul polso.
    func esegui(_ input: [String: Any]) async -> (String, Bool) {
        let grezzi: [[String: Any]] = input["passi"] as? [[String: Any]] ?? (input["azione"] != nil ? [input] : [])
        guard !grezzi.isEmpty else { return (Self.json(["errore": "nessun passo"]), true) }
        var fatti: [[String: Any]] = []
        for g in grezzi.prefix(4) {
            var valori: [String: String] = [:]
            for (k, v) in g["valori"] as? [String: Any] ?? [:] { valori[k] = (v as? String) ?? "\(v)" }
            let sezione = g["sezione"] as? String ?? ""
            let azione = g["azione"] as? String ?? ""
            let (ok, esito) = await passo(sezione: sezione, azione: azione, valori: valori)
            fatti.append(["sezione": sezione, "azione": azione, "ok": ok, "esito": esito])
            if !ok { break }
        }
        return (Self.json(["fatti": fatti, "davanti": davanti ?? "JARVIS"]), false)
    }

    private func passo(sezione: String, azione: String, valori: [String: String]) async -> (Bool, String) {
        switch Self.chiave(azione) {
        case "apri", "davanti", "porta", "mostra", "torna":
            guard let m = Self.meta(sezione) else { return (false, "«\(sezione)» vive sull'iPhone, Sir: sul polso non c'è") }
            if davanti == m.nome { return (true, "\(m.nome) è già aperta sul polso") }
            if let r = m.reparto { apri?(r) }
            else if case .some(.travel) = m.polso { apriPolso?(.travel(valori["luogo"] ?? "", "")) }
            else if let p = m.polso { apriPolso?(p) }
            evento("aperta \(m.nome)")
            return (true, "\(m.nome) aperta sul polso")
        case "chiudi", "chiuditutto", "daparte", "casa", "home", "via":
            guard let d = davanti else { return (true, "davanti c'è già la schermata principale") }
            chiudi?()
            evento("chiusa \(d)")
            return (true, "\(d) chiusa, davanti la schermata principale")
        case "diprima", "precedente", "sfoglia", "sezioniaperte":
            return (false, "sull'orologio si apre una sezione alla volta")
        case "play", "riprendi", "pausa", "avanti", "prossimo", "indietro":
            return await tasto(Self.chiave(azione))
        default:
            return (false, "al polso \(sezione.isEmpty ? "la regia" : sezione) sa fare: apri, chiudi; Musica: play, pausa, avanti, indietro")
        }
    }

    /// Un tasto della musica dell'iPhone, dal polso.
    private func tasto(_ k: String) async -> (Bool, String) {
        let comando: String
        switch k {
        case "riprendi": comando = "play"
        case "prossimo": comando = "avanti"
        default: comando = k
        }
        guard let s = await PonteOrologio.condiviso.musica(comando) else { return (false, "l'iPhone non risponde: va tenuto vicino") }
        musica = s
        if let e = s.errore { return (false, e) }
        evento("musica: \(comando)")
        return (true, (s.suona ? "suona" : "in pausa") + " «\(s.titolo)» di \(s.artista)")
    }

    // MARK: Subito, senza il cervello

    private static let frasiTasti: [String: [String]] = [
        "play": ["play", "riprendi", "riparti", "fai partire", "rimetti la musica", "riprendi la musica"],
        "pausa": ["pausa", "metti in pausa", "ferma la musica", "stoppa"],
        "avanti": ["avanti", "prossimo", "prossima", "salta", "brano successivo", "il prossimo", "la prossima", "next", "cambia brano", "cambia canzone", "skip"],
        "indietro": ["indietro", "precedente", "torna indietro", "brano precedente", "canzone precedente", "da capo"],
    ]

    /// 14 nov: da qualsiasi schermata del polso, le frasi che parlano chiaro della musica dell'iPhone (come sull'iPhone, dove i tasti
    /// della musica valgono ovunque): «metti in pausa», «cambia canzone». «Avanti», «indietro», «salta» da soli restano della
    /// MUSICA davanti (altrove vogliono dire altro).
    private static let frasiOvunque: [String: [String]] = [
        "play": ["play", "riprendi la musica", "rimetti la musica", "fai partire la musica", "fai ripartire la musica"],
        "pausa": ["pausa", "metti in pausa", "metti in pausa la musica", "ferma la musica", "stoppa la musica"],
        "avanti": ["brano successivo", "canzone successiva", "prossima canzone", "la prossima canzone", "cambia brano", "cambia canzone", "skip"],
        "indietro": ["brano precedente", "canzone precedente", "la canzone di prima"],
    ]

    /// La frase è un tasto della musica? Con la MUSICA davanti sul polso tutti i suoi tasti («pausa», «avanti»); altrove quelli che
    /// parlano chiaro (`frasiOvunque`). Il comando, se sì.
    func tastoDetto(_ testo: String) -> String? {
        var p = FineFrase.paroleNude(testo)
        let cortesie: Set<String> = ["ok", "okay", "dai", "allora", "ehi", "hey", "per", "favore", "senti", "grazie", "sir", "subito", "adesso", "ora", "pure"]
        while let f = p.first, cortesie.contains(f) { p.removeFirst() }
        while let l = p.last, cortesie.contains(l) { p.removeLast() }
        guard !p.isEmpty else { return nil }
        let detta = p.joined(separator: " ")
        let tasti = davanti == "Musica" ? Self.frasiTasti : Self.frasiOvunque
        for (comando, frasi) in tasti where frasi.contains(where: { FineFrase.paroleNude($0).joined(separator: " ") == detta }) { return comando }
        return nil
    }

    /// Esegue il tasto detto e restituisce la frase di JARVIS: la battuta, o perché non è andata («l'iPhone non risponde»).
    func subito(_ comando: String) async -> String {
        let (ok, esito) = await tasto(comando)
        WKInterfaceDevice.current().play(.click)
        return ok ? Battute.musica(comando) : String(esito.prefix(1)).uppercased() + String(esito.dropFirst()) + ", Sir."
    }

    static func json(_ d: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(d),
              let dati = try? JSONSerialization.data(withJSONObject: d, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: dati, as: UTF8.self)
    }
}
