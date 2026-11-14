#if os(iOS)
import Foundation

// MARK: - 14 nov · PIÙ PASSI SENZA GUIDA
// Il signore (14 nov, 03:23): «lei dà un obiettivo e lui fa da solo i passaggi necessari, controllando a ogni passo che sia andato
// bene… «Prepara la serata di sabato: controlla gli incassi dell'ultima, scrivi a Cristina cosa manca al bar e mettimi il
// promemoria»». Il cervello dichiara il piano (strumento «piano»), fa un passo alla volta coi suoi strumenti e dopo ognuno
// ne segna l'esito; il piano si vede in FILO (PIANO, un passo per riga col suo segno) e va al cervello nella riga [Schermo], così
// dopo un «sì» chiesto a metà riprende da dove era. I passi che vogliono il sì (inviare, eliminare…) si fermano lì.

@MainActor
final class Piano {
    static let condiviso = Piano()

    enum Stato: String { case daFare = "da fare", inCorso = "in corso", fatto, errore, aspetta = "aspetta il sì" }
    struct Passo {
        var testo: String
        var stato: Stato
        var nota: String?
    }

    private(set) var titolo = ""
    private(set) var passi: [Passo] = []
    private(set) var iniziato: Date?
    private(set) var finito = false

    /// Un piano vivo (non ancora finito, e non vecchio di più di 20 minuti).
    var inCorso: Bool {
        guard let iniziato, !finito, !passi.isEmpty else { return false }
        return Date().timeIntervalSince(iniziato) < 1200
    }

    // MARK: Lo strumento del cervello

    static let definizione: [String: Any] = [
        "name": "piano",
        "description": "Quando il signore ti affida un lavoro con più passi («fallo tu», «pensaci tu», «vedi tu», «occupatene tu»): piano(titolo, passi) coi passi in poche parole, poi un passo alla volta coi tuoi strumenti e dopo ognuno piano(passo, stato, nota) controllando l'esito. Parla come JARVIS con Tony: «Ci penso io», poi solo i dati che contano mentre lavori, mai l'elenco dei passi (si vede da solo nella tab). Un passo da confermare: stato=aspetta e chiedi il sì in una domanda breve. Alla fine piano(fine=true) e una frase col risultato.",
        "input_schema": [
            "type": "object",
            "properties": [
                "titolo": ["type": "string", "description": "L'obiettivo in tre o quattro parole («Serata di sabato»)"],
                "passi": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "I passi in ordine, al massimo 8, poche parole ciascuno"],
                "passo": ["type": "integer", "description": "Il numero del passo (da 1) di cui segni lo stato"],
                "stato": ["type": "string", "enum": ["in_corso", "fatto", "errore", "aspetta"]],
                "nota": ["type": "string", "description": "L'esito in breve («7 drink sotto scorta»)"],
                "fine": ["type": "boolean", "description": "true quando l'obiettivo è raggiunto (o ti fermi)"],
            ] as [String: Any],
        ] as [String: Any],
    ]

    /// Quante risposte del cervello sono finite senza che il piano andasse avanti.
    private var giriFermo = 0

    /// Esegue una chiamata dello strumento «piano» e dice al cervello com'è il piano adesso.
    func esegui(_ i: [String: Any]) -> (String, Bool) {
        giriFermo = 0
        if let nuovi = i["passi"] as? [Any], !nuovi.isEmpty {
            let testi = nuovi.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(8)
            guard !testi.isEmpty else { return (Regia.json(["errore": "passi vuoti"]), true) }
            titolo = ((i["titolo"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            passi = testi.enumerated().map { k, t in Passo(testo: String(t.prefix(60)), stato: k == 0 ? .inCorso : .daFare) }
            iniziato = Date()
            finito = false
            Regia.condivisa.evento("piano: \(titolo.isEmpty ? "senza titolo" : titolo), \(passi.count) passi")
        }
        guard !passi.isEmpty else { return (Regia.json(["errore": "nessun piano: prima piano(titolo, passi)"]), true) }
        var esito: Stato?                                                    // 14 nov: per l'aptica del passo (Aptica)
        if let n = (i["passo"] as? NSNumber)?.intValue ?? (i["passo"] as? String).flatMap({ Int($0) }) {
            guard passi.indices.contains(n - 1) else { return (Regia.json(["errore": "il piano ha \(passi.count) passi"]), true) }
            let stato: Stato
            switch (i["stato"] as? String ?? "fatto").lowercased() {
            case "errore", "fallito", "no": stato = .errore
            case "aspetta", "aspetta_il_si", "conferma": stato = .aspetta
            case "in_corso", "incorso", "via": stato = .inCorso
            default: stato = .fatto
            }
            passi[n - 1].stato = stato
            esito = stato
            if let nota = (i["nota"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !nota.isEmpty { passi[n - 1].nota = String(nota.prefix(70)) }
            // il passo dopo, se ancora da fare, è quello in corso
            if stato == .fatto, passi.indices.contains(n), passi[n].stato == .daFare { passi[n].stato = .inCorso }
        }
        let fine = i["fine"] as? Bool == true
        if fine {
            finito = true
            for k in passi.indices where passi[k].stato == .inCorso { passi[k].stato = .daFare }
            if passi.allSatisfy({ $0.stato == .fatto }) { Congedo.condiviso.cosaVera() }
            Regia.condivisa.evento("piano finito: \(riassunto)")
        }
        mostra()
        // 14 nov (il signore: «i feedback aptici… che seguano una logica»; come al polso): finita tutta bene «fatto», chiusa a metà un
        // tocco morbido; un passo fatto un tocco secco, il passo che aspetta il sì bussa due volte, un errore l'errore di Apple
        if fine {
            if passi.allSatisfy({ $0.stato == .fatto }) { Aptica.pronto() } else { Aptica.tabVia() }
        } else if let esito {
            switch esito {
            case .fatto: Aptica.passoFatto()
            case .aspetta: Aptica.passoAspetta()
            case .errore: Aptica.passoErrore()
            default: break
            }
        }
        return (Regia.json(["piano": perCervello ?? "", "nota": finito ? "piano chiuso: di' il risultato in una frase" : "vai avanti col passo in corso"]), false)
    }

    /// 14 nov (il signore: «il messaggio non parte e le tab non spariscono da sole»): una risposta del cervello è finita (detta,
    /// interrotta, andata male). Se il piano non aspetta il sì, si chiude lì e sparisce in 5 secondi; se aspetta il sì, resta per la
    /// risposta dopo: se anche quella non lo manda avanti (ha detto altro), si chiude. Prima un piano interrotto restava sullo schermo.
    func turnoFinito() {
        guard inCorso else { return }
        giriFermo += 1
        if !passi.contains(where: { $0.stato == .aspetta }) || giriFermo >= 2 { ferma() }
    }

    /// Il signore cambia argomento o chiude tutto: il piano si ferma (resta in FILO da richiamare).
    func ferma() {
        guard inCorso else { return }
        finito = true
        mostra()
    }

    // MARK: FILO e cervello

    private var riassunto: String {
        let fatti = passi.filter { $0.stato == .fatto }.count
        return "\(fatti) di \(passi.count) fatti"
    }

    /// Il segno davanti a ogni passo.
    static func segno(_ s: Stato) -> String {
        switch s {
        case .fatto: return "✓"
        case .inCorso: return "▸"
        case .daFare: return "○"
        case .errore: return "✕"
        case .aspetta: return "◇"
        }
    }

    /// La riga per il cervello (dentro [Schermo]).
    var perCervello: String? {
        guard !passi.isEmpty, let iniziato, Date().timeIntervalSince(iniziato) < 1200 else { return nil }
        let righe = passi.enumerated().map { k, p in "\(k + 1) \(p.stato.rawValue): \(p.testo)" + (p.nota.map { " (\($0))" } ?? "") }
        return (finito ? "PIANO FINITO" : "PIANO IN CORSO") + (titolo.isEmpty ? "" : " «\(titolo)»") + ": " + righe.joined(separator: "; ")
    }

    /// Il piano in FILO: un passo per riga, nel suo ordine. Mentre lavora resta; finito, sparisce da solo dopo qualche secondo.
    private func mostra() {
        let righe = passi.enumerated().map { k, p in
            RigaFilo(id: "piano#\(k)", titolo: "Piano", riga: Piano.segno(p.stato) + " " + p.testo + (p.nota.map { " · " + $0 } ?? ""),
                     sezione: nil, alle: Date(), resta: !finito)
        }
        Filo.condiviso.mostraPiano(titolo: titolo, righe: righe, finito: finito)
    }
}
#endif
