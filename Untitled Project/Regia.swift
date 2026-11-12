#if os(iOS)
import Foundation
import SwiftUI

// MARK: - 12.0 (10) · LA REGIA
// Il mandato del signore (12 nov, 05:22): «sei Jarvis di Iron Man e vuoi integrarti dentro Jarvis app… ti è stato chiesto di essere
// la regia di quest'app, essere cool e fare cose stupefacenti, ma essere funzionale, veloce, dinamico, logico ed un prezioso aiutante
// digitale… crea combinazioni di comandi vocali per ottenere più risultati… spettacolare e fluido, tutto omogeneo e ben orchestrato,
// proprio come nell'armatura di Iron Man». E alle 05:37: non in silenzio, «dialogo ed interazione con frasi anche simpatiche e
// umane, non freddi comandi… come fa Tony con Jarvis, un dialogo dentro l'app mescolato ai comandi chiave».
//
// Come funziona:
// - ogni sezione dice cosa mostra e cosa sa fare (`.regia(...)`): lo stato in una riga e le sue azioni, coi nomi dei suoi tasti;
// - a ogni domanda il cervello riceve il catalogo (`catalogo`, nella riga [Schermo]) e uno strumento solo, «regia»: apre, chiude,
//   porta davanti, mette da parte, e fa le azioni delle sezioni, anche più passi in una volta, mentre parla col signore;
// - inviare, eliminare, pubblicare, chiamare: prima il sì del signore. La conferma la controlla l'app, non il cervello: un testo
//   letto sullo schermo (una mail, una pagina, un messaggio) non può far partire niente da solo;
// - le azioni più usate partono anche senza il cervello (`subito`), con una battuta di JARVIS (Battute.swift).

/// Un'azione di una sezione, per JARVIS.
struct AzioneRegia {
    /// Il nome per il cervello, come il tasto: «aggiungi», «leggi», «svuota».
    let nome: String
    /// Cosa fa, in poche parole.
    let aiuto: String
    /// Il nome del valore che vuole («cosa», «chi», «testo»), se ne vuole uno: nel catalogo «aggiungi(cosa)».
    var valore: String?
    /// Inviare, eliminare, pubblicare, chiamare: prima il sì del signore.
    var conferma = false
    /// Le frasi brevi con cui il signore la chiede, per farla subito senza il cervello: «*» in fondo è il valore (una o più parole).
    var frasi: [String] = []
    let esegui: @MainActor (_ valori: [String: String]) async -> EsitoRegia

    init(_ nome: String, _ aiuto: String, valore: String? = nil, conferma: Bool = false, frasi: [String] = [],
         esegui: @escaping @MainActor (_ valori: [String: String]) async -> EsitoRegia) {
        self.nome = nome
        self.aiuto = aiuto
        self.valore = valore
        self.conferma = conferma
        self.frasi = frasi
        self.esegui = esegui
    }
}

/// Com'è andata un'azione.
struct EsitoRegia {
    var ok: Bool
    /// Per il cervello: cosa è successo e com'è adesso («aggiunti latte e uova; in lista 7 cose»).
    var dato: String
    /// La frase di JARVIS quando l'azione è partita senza il cervello (nil: basta la vibrazione). Si scrive solo se serve: col
    /// cervello parla lui.
    var battuta: (@MainActor () -> String)?

    static func fatto(_ dato: String, battuta: (@MainActor () -> String)? = nil) -> EsitoRegia { EsitoRegia(ok: true, dato: dato, battuta: battuta) }
    static func no(_ dato: String, battuta: (@MainActor () -> String)? = nil) -> EsitoRegia { EsitoRegia(ok: false, dato: dato, battuta: battuta) }
}

@MainActor
final class Regia {
    static let condivisa = Regia()

    /// Le strade della schermata principale (le collega ContentView).
    enum Strada {
        case apri(Reparto), pagina(String), chiudi(String), chiudiTutto, daParte, diPrima, sfoglia
    }
    /// Esegue una strada (ContentView).
    var vai: ((Strada) -> Void)?
    /// Le sezioni aperte (ContentView): la davanti e quelle dietro, coi nomi.
    weak var pila: PilaSezioni?
    /// L'ultima frase del signore e quando l'ha detta (Jarvis): serve per il sì delle conferme.
    var ultimaFrase: (() -> (testo: String, quando: Date)?)?
    /// Un lavoro da fare quando JARVIS ha finito di parlare (Jarvis): le sezioni col microfono o la fotocamera si aprono dopo la
    /// voce, come sempre (Shazam, l'Interprete, la Sentinella non devono sentire JARVIS).
    var dopoLaVoce: ((@escaping @MainActor () -> Void) -> Void)?

    private struct Scena {
        var nome: String
        var stato: String
        var azioni: [AzioneRegia]
        var davanti: Bool
        var ordine: Int
    }
    private var scene: [UUID: Scena] = [:]
    private var contatore = 0
    private var eventi: [(quando: Date, testo: String)] = []

    struct Passo: Equatable {
        var sezione: String
        var azione: String
        var valori: [String: String]
    }
    /// I passi fermi in attesa del sì del signore (inviare, eliminare, pubblicare, chiamare) e quando li ha chiesti.
    private var inSospeso: (passi: [Passo], quando: Date)?

    // MARK: Le sezioni si presentano

    func metti(_ chiave: UUID, nome: String, stato: String, azioni: [AzioneRegia], davanti: Bool) {
        var ordine = scene[chiave]?.ordine ?? 0
        if scene[chiave]?.davanti != davanti || ordine == 0 {      // appena arrivata davanti: diventa la più recente
            contatore += 1
            ordine = contatore
        }
        scene[chiave] = Scena(nome: nome, stato: stato, azioni: azioni, davanti: davanti, ordine: ordine)
    }

    func togli(_ chiave: UUID) { scene[chiave] = nil }

    /// Una cosa appena successa (un'azione, una sezione aperta): il cervello sa cosa è cambiato e quando.
    func evento(_ testo: String) {
        eventi.append((Date(), testo))
        if eventi.count > 8 { eventi.removeFirst(eventi.count - 8) }
    }

    /// Le scene di una sezione (anche più pezzi: la lista della posta e la mail aperta), la più recente per prima.
    private func scene(di nome: String) -> [Scena] {
        let k = Regia.chiave(nome)
        return scene.values.filter { Regia.chiave($0.nome) == k }.sorted { $0.ordine > $1.ordine }
    }

    private func azioni(di nome: String) -> [AzioneRegia] {
        var viste = Set<String>()
        var tutte: [AzioneRegia] = []
        for s in scene(di: nome) { for a in s.azioni where viste.insert(Regia.chiave(a.nome)).inserted { tutte.append(a) } }
        return tutte
    }

    /// Il nome della sezione davanti (nil: JARVIS è davanti).
    private var nomeDavanti: String? { pila?.voceDavanti?.sezione.nome }

    private func statoDi(_ nome: String) -> String? {
        let righe = scene(di: nome).map(\.stato).filter { !$0.isEmpty }
        return righe.isEmpty ? nil : righe.joined(separator: " · ")
    }

    // MARK: Il catalogo per il cervello

    /// Il catalogo (va nella riga [Schermo], una riga sola): la sezione davanti, cosa mostra e cosa sa fare; quelle dietro; le
    /// sezioni che si possono aprire; le strade di sempre; quello che è appena successo. `rigaVecchia`: quello che mostra la
    /// sezione davanti se non è ancora nella regia (la riga di `Schermo`).
    func catalogo(rigaVecchia: String?) -> String {
        var pezzi: [String] = ["REGIA (strumento «regia»: sezione, azione, valori; * = serve il sì del signore)"]
        let aperte = pila?.voci ?? []
        if let d = nomeDavanti {
            let stato = statoDi(d) ?? rigaVecchia ?? "aperta"
            pezzi.append("DAVANTI \(d): " + Regia.taglia(stato, 3000))
            let a = azioni(di: d)
            if !a.isEmpty { pezzi.append("azioni \(d): " + Regia.elenco(a)) }
        } else {
            pezzi.append("DAVANTI JARVIS (la schermata principale)")
        }
        let dietro = aperte.map(\.sezione.nome).filter { $0 != nomeDavanti }
        for n in dietro.suffix(6) {
            var riga = "DIETRO \(n)"
            if let s = statoDi(n) { riga += ": " + Regia.taglia(s, 280) }
            let a = azioni(di: n)
            if !a.isEmpty { riga += " · azioni: " + Regia.elenco(a) }
            pezzi.append(riga)
        }
        pezzi.append("SI APRONO: " + Regia.destinazioni.map(\.nome).joined(separator: ", "))
        pezzi.append("SEMPRE: apri(sezione), chiudi(sezione), da_parte (quella davanti va dietro, torna JARVIS), di_prima, sfoglia, chiudi_tutto")
        let recenti = eventi.filter { Date().timeIntervalSince($0.quando) < 600 }
        if !recenti.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            pezzi.append("APPENA: " + recenti.map { "\(f.string(from: $0.quando)) \($0.testo)" }.joined(separator: "; "))
        }
        return Regia.taglia(pezzi.joined(separator: " ‖ "), 5900)
    }

    private static func elenco(_ azioni: [AzioneRegia]) -> String {
        azioni.map { a in a.nome + (a.valore.map { "(\($0))" } ?? "") + (a.conferma ? "*" : "") + " " + a.aiuto }.joined(separator: "; ")
    }

    private static func taglia(_ s: String, _ massimo: Int) -> String { s.count > massimo ? String(s.prefix(massimo)) + "…" : s }

    // MARK: Lo strumento del cervello

    /// Lo strumento «regia» com'è descritto al cervello (`strumenti_client_def`): il cervello lo usa senza essere ripubblicato.
    static let definizione: [String: Any] = [
        "name": "regia",
        "description": "La regia dell'app, come JARVIS nell'armatura di Tony: apri, chiudi, porta davanti, metti da parte le sezioni e fai le loro azioni, quelle elencate dopo REGIA nella riga [Schermo] (sezione, azione, valori). Più passi in una chiamata, in ordine. Le azioni con * (inviare, eliminare, pubblicare, chiamare) aspettano il sì del signore: chiediglielo con una domanda breve e naturale, poi richiama con confermato=true. Agisci e intanto parla come JARVIS con Tony in laboratorio: una frase breve e viva col dato che conta, una battuta asciutta quando ci sta; mai «comando eseguito», mai elenchi.",
        "input_schema": [
            "type": "object",
            "properties": [
                "passi": [
                    "type": "array",
                    "description": "I passi in ordine, al massimo 8.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "sezione": ["type": "string", "description": "Il nome della sezione (Spesa, Meteo, Musica…); vuoto per da_parte, di_prima, sfoglia, chiudi_tutto"],
                            "azione": ["type": "string", "description": "apri, chiudi, da_parte, di_prima, sfoglia, chiudi_tutto, oppure un'azione della sezione"],
                            "valori": ["type": "object", "description": "I valori dell'azione, come testo (es. {\"cosa\": \"latte, uova\"})",
                                       "additionalProperties": ["type": "string"]],
                        ] as [String: Any],
                        "required": ["azione"],
                    ] as [String: Any],
                ] as [String: Any],
                "confermato": ["type": "boolean", "description": "Solo dopo il sì del signore alla tua domanda di conferma"],
            ] as [String: Any],
            "required": ["passi"],
        ] as [String: Any],
    ]

    /// Lo strumento «regia»: esegue i passi in ordine e dice al cervello com'è andata e cosa c'è adesso davanti.
    func esegui(_ input: [String: Any]) async -> (String, Bool) {
        let grezzi: [[String: Any]] = input["passi"] as? [[String: Any]] ?? (input["azione"] != nil ? [input] : [])
        var passi: [Passo] = grezzi.prefix(8).map { g in
            var valori: [String: String] = [:]
            for (k, v) in g["valori"] as? [String: Any] ?? [:] { valori[k] = (v as? String) ?? "\(v)" }
            return Passo(sezione: g["sezione"] as? String ?? "", azione: g["azione"] as? String ?? "", valori: valori)
        }
        guard !passi.isEmpty else { return (Regia.json(["errore": "nessun passo"]), true) }
        let confermato = input["confermato"] as? Bool ?? false
        if confermato {
            // il sì vale solo per i passi chiesti (con i loro valori, quelli che il signore ha sentito), entro 3 minuti, e solo se
            // l'ultima frase del signore, detta dopo la domanda, è davvero un sì
            guard let s = inSospeso, Date().timeIntervalSince(s.quando) < 180,
                  s.passi.map({ Regia.chiave($0.sezione) + "/" + Regia.chiave($0.azione) }) == passi.map({ Regia.chiave($0.sezione) + "/" + Regia.chiave($0.azione) }),
                  let f = ultimaFrase?(), f.quando > s.quando, Regia.eAssenso(f.testo) else {
                inSospeso = nil
                return (Regia.json(["errore": "conferma non valida: chiedi al signore con una domanda breve e aspetta il suo sì (lo controlla l'app)"]), true)
            }
            passi = s.passi
            inSospeso = nil
        }
        var fatti: [[String: Any]] = []
        for (k, p) in passi.enumerated() {
            if !confermato, azioni(di: p.sezione).first(where: { Regia.chiave($0.nome) == Regia.chiave(p.azione) })?.conferma == true {
                inSospeso = (Array(passi[k...]), Date())
                return (Regia.json(["fatti": fatti, "aspetta_il_si": "\(p.sezione) · \(p.azione) \(p.valori.values.joined(separator: " "))",
                                    "nota": "chiedi conferma al signore con una domanda breve e naturale; se dice sì, richiama regia con gli stessi passi e confermato=true"]), false)
            }
            let e = await passo(p)
            fatti.append(["sezione": p.sezione, "azione": p.azione, "ok": e.ok, "esito": e.dato])
            if !e.ok { break }
        }
        var risposta: [String: Any] = ["fatti": fatti]
        if let d = nomeDavanti { risposta["davanti"] = d + (statoDi(d).map { ": " + Regia.taglia($0, 600) } ?? "") } else { risposta["davanti"] = "JARVIS" }
        return (Regia.json(risposta), false)
    }

    /// Un passo: le strade di sempre o un'azione di una sezione (che si apre da sola, se serve).
    private func passo(_ p: Passo) async -> EsitoRegia {
        switch Regia.chiave(p.azione) {
        case "apri", "davanti", "porta", "mostra", "torna":
            return await apri(p.sezione)
        case "chiudi":
            let nome: String? = p.sezione.isEmpty ? nomeDavanti : (Regia.destinazione(p.sezione)?.nome ?? p.sezione)
            guard let nome, pila?.voci.contains(where: { $0.sezione.nome == nome }) == true else { return .no("\(p.sezione) non è aperta") }
            vai?(.chiudi(nome))
            evento("chiusa \(nome)")
            return .fatto("\(nome) chiusa")
        case "chiuditutto":
            vai?(.chiudiTutto)
            evento("chiuse tutte le sezioni")
            return .fatto("tutte chiuse, davanti JARVIS")
        case "daparte", "casa", "home", "via":
            guard let d = nomeDavanti else { return .fatto("davanti c'è già JARVIS") }
            vai?(.daParte)
            evento("\(d) messa da parte")
            return .fatto("\(d) è andata dietro (resta aperta), davanti JARVIS")
        case "diprima", "precedente":
            vai?(.diPrima)
            return .fatto("torna davanti la sezione di prima")
        case "sfoglia", "sezioniaperte":
            vai?(.sfoglia)
            return .fatto("le sezioni aperte si sfogliano sullo schermo")
        default:
            break
        }
        // un'azione di una sezione: se non è aperta, si apre (e si aspetta che sia pronta)
        guard let d = Regia.destinazione(p.sezione) ?? (p.sezione.isEmpty ? nomeDavanti.flatMap(Regia.destinazione) : nil) else {
            return .no("sezione «\(p.sezione)» sconosciuta")
        }
        if azioni(di: d.nome).isEmpty {
            let aperta = await apri(d.nome)
            guard aperta.ok else { return aperta }
            _ = await attendi(d.nome, conAzioni: true)
        }
        let tutte = azioni(di: d.nome)
        guard let a = tutte.first(where: { Regia.chiave($0.nome) == Regia.chiave(p.azione) }) else {
            return .no(tutte.isEmpty ? "\(d.nome) non ha azioni" : "\(d.nome) sa fare: " + tutte.map(\.nome).joined(separator: ", "))
        }
        let e = await a.esegui(p.valori)
        if e.ok { evento("\(d.nome): \(Regia.taglia(e.dato, 80))") }
        return e
    }

    /// Apre una sezione (o la riporta davanti se era dietro) e aspetta che sia pronta.
    private func apri(_ nome: String) async -> EsitoRegia {
        guard let d = Regia.destinazione(nome) else { return .no("sezione «\(nome)» sconosciuta") }
        if nomeDavanti == d.nome { return .fatto("\(d.nome) è già davanti" + (statoDi(d.nome).map { ": " + Regia.taglia($0, 600) } ?? "")) }
        let eraDietro = pila?.voci.contains { $0.sezione.nome == d.nome } == true
        if d.dopoLaVoce, let dopo = dopoLaVoce {
            // microfono o fotocamera: si apre appena JARVIS ha finito la sua frase (non deve sentire la sua voce)
            dopo { [weak self] in self?.vai?(d.strada) }
            evento("\(d.nome) in apertura")
            return .fatto("\(d.nome) si apre appena hai finito la frase: dilla breve")
        }
        vai?(d.strada)
        evento(eraDietro ? "\(d.nome) tornata davanti" : "aperta \(d.nome)")
        if let s = await attendi(d.nome, conAzioni: false) { return .fatto("\(d.nome) davanti: " + Regia.taglia(s, 600)) }
        return .fatto("\(d.nome) davanti")
    }

    /// Aspetta (al massimo 2,5 s) che la sezione sia davanti e si sia presentata; restituisce cosa mostra.
    private func attendi(_ nome: String, conAzioni: Bool) async -> String? {
        for _ in 0..<50 {
            if nomeDavanti == nome, !scene(di: nome).isEmpty, !conAzioni || !azioni(di: nome).isEmpty { return statoDi(nome) }
            if !Regia.conLaRegia.contains(nome), nomeDavanti == nome { return nil }   // non ancora nella regia: niente da aspettare
            try? await Task.sleep(for: .milliseconds(50))
        }
        return statoDi(nome)
    }

    // MARK: Subito, senza il cervello

    /// Le azioni più usate partono subito: la frase chiede un'azione della sezione davanti («aggiungi il latte» con la Spesa
    /// davanti)? Allora la fa e restituisce la battuta di JARVIS (vuota: basta la vibrazione). Nil: la frase va al cervello.
    func subito(_ frase: String) async -> String? {
        guard let d = nomeDavanti else { return nil }
        let parole = Regia.paroleComando(frase)
        guard !parole.isEmpty else { return nil }
        for a in azioni(di: d) where !a.conferma {
            for schema in a.frasi {
                guard let valore = Regia.combacia(parole, schema) else { continue }
                var valori: [String: String] = [:]
                if let v = a.valore, !valore.isEmpty { valori[v] = valore }
                let e = await a.esegui(valori)
                if e.ok { evento("\(d): \(Regia.taglia(e.dato, 80))") }
                if !e.ok && e.battuta == nil { return nil }       // non era una frase per lei: decide il cervello
                return e.battuta?() ?? ""
            }
        }
        return nil
    }

    /// Le parole di un comando: minuscole, senza accenti né punteggiatura, senza il nome e le cortesie davanti e in fondo.
    static func paroleComando(_ frase: String) -> [String] {
        var p = FineFrase.paroleNude(frase)
        let davanti: Set<String> = ["ok", "okay", "dai", "allora", "ehi", "hey", "per", "favore", "senti", "ecco", "bene", "perfetto", "sir"]
        let dietro: Set<String> = ["grazie", "sir", "dai", "subito", "adesso", "ora", "pure", "favore", "per"]
        while let f = p.first, davanti.contains(f) { p.removeFirst() }
        while let l = p.last, dietro.contains(l) { p.removeLast() }
        return p
    }

    /// La frase combacia con lo schema? «aggiungi *»: le parole dello schema all'inizio, il resto (almeno una parola) è il valore;
    /// senza «*» la frase deve essere proprio quella. Nil: non combacia. Il valore non può parlare d'altro (musica, sveglie,
    /// messaggi…): quella frase va al cervello.
    static func combacia(_ parole: [String], _ schema: String) -> String? {
        let s = FineFrase.paroleNude(schema.replacingOccurrences(of: "*", with: " stellaregia "))
        let conValore = s.last == "stellaregia"
        let fisse = conValore ? Array(s.dropLast()) : s
        guard parole.count >= fisse.count + (conValore ? 1 : 0), Array(parole.prefix(fisse.count)) == fisse else { return nil }
        if !conValore { return parole.count == fisse.count ? "" : nil }
        var resto = Array(parole.dropFirst(fisse.count))
        let articoli: Set<String> = ["il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "del", "dello", "della", "dei", "degli", "delle", "anche"]
        while let f = resto.first, articoli.contains(f) { resto.removeFirst() }
        guard !resto.isEmpty, !resto.contains(where: { Regia.altroMondo.contains($0) }) else { return nil }
        return resto.joined(separator: " ")
    }

    /// Parole che, dentro il valore di una frase rapida, dicono che la frase parla d'altro: va al cervello.
    private static let altroMondo: Set<String> = ["musica", "canzone", "canzoni", "brano", "playlist", "sveglia", "timer", "promemoria",
                                                  "calendario", "appuntamento", "messaggio", "messaggi", "mail", "email", "posta", "foto",
                                                  "video", "sezione", "sezioni", "chat", "conversazione", "meteo", "jarvis", "telefono"]

    /// Il sì del signore a una domanda di conferma: «sì», «vai», «mandalo», «procedi», «certo»… e niente «no», «aspetta», «ma».
    static func eAssenso(_ frase: String) -> Bool {
        let p = FineFrase.paroleNude(frase)
        guard !p.isEmpty, p.count <= 7 else { return false }
        let si: Set<String> = ["si", "sisi", "vai", "procedi", "procediamo", "conferma", "confermo", "certo", "certamente", "ok", "okay",
                               "esatto", "perfetto", "giusto", "fallo", "falla", "mandalo", "mandala", "mandali", "mandale", "manda",
                               "invia", "invialo", "inviala", "inviali", "chiama", "chiamalo", "chiamala", "elimina", "eliminalo",
                               "eliminala", "cancella", "cancellalo", "cancellala", "pubblica", "pubblicalo", "pubblicala", "sicuro",
                               "assolutamente", "ovvio", "affermativo", "andiamo", "yes", "va", "bene", "dai", "pure", "sir", "grazie",
                               "lo", "la", "e", "cosi", "adesso", "ora", "subito", "tutto", "benissimo", "ottimo"]
        let contro: Set<String> = ["no", "non", "aspetta", "aspetti", "ferma", "fermo", "fermati", "annulla", "lascia", "stop", "niente",
                                   "nulla", "dopo", "ma", "cambia", "prima", "invece"]
        guard !p.contains(where: { contro.contains($0) }) else { return false }
        let pieni: Set<String> = si.subtracting(["va", "bene", "dai", "pure", "sir", "grazie", "lo", "la", "e", "cosi", "adesso", "ora", "subito", "tutto"])
        return p.contains(where: { pieni.contains($0) }) && p.allSatisfy { si.contains($0) }
    }

    // MARK: Le sezioni per nome

    /// Dove si va: il nome della sezione (come sulla corona), le parole con cui si chiama e la strada per aprirla.
    /// `dopoLaVoce`: microfono o fotocamera, si apre quando JARVIS ha finito di parlare.
    struct Destinazione {
        let nome: String
        let chiavi: [String]
        let strada: Strada
        var dopoLaVoce = false
    }

    static let destinazioni: [Destinazione] = [
        Destinazione(nome: "Meteo", chiavi: ["meteo", "tempo", "previsioni"], strada: .apri(.meteo)),
        Destinazione(nome: "Spesa", chiavi: ["spesa", "lista", "listadellaspesa", "listaspesa"], strada: .apri(.spesa)),
        Destinazione(nome: "Email", chiavi: ["email", "posta", "mail", "mails"], strada: .apri(.email)),
        Destinazione(nome: "Messaggi", chiavi: ["messaggi", "messaggio", "sms", "whatsapp"], strada: .apri(.messaggi)),
        Destinazione(nome: "Telefono", chiavi: ["telefono", "chiamate", "rubrica"], strada: .apri(.telefono)),
        Destinazione(nome: "Musica", chiavi: ["musica", "canzoni", "brani", "lettore"], strada: .apri(.musica)),
        Destinazione(nome: "Foto", chiavi: ["foto", "fotografie", "galleria", "rullino"], strada: .apri(.foto)),
        Destinazione(nome: "Diario", chiavi: ["diario"], strada: .apri(.diario)),
        Destinazione(nome: "Sonno", chiavi: ["sonno", "dormito"], strada: .apri(.sonno)),
        Destinazione(nome: "Cuore", chiavi: ["cuore", "battito", "battiti"], strada: .apri(.cuore)),
        Destinazione(nome: "Briefing", chiavi: ["briefing", "riepilogo", "giornata"], strada: .apri(.briefing)),
        Destinazione(nome: "Serata", chiavi: ["serata", "incassi", "conti", "contidellaserata"], strada: .apri(.serata)),
        Destinazione(nome: "Bea", chiavi: ["bea", "beatrice"], strada: .apri(.bea)),
        Destinazione(nome: "Satellite", chiavi: ["satellite", "mappa", "mappe", "intelligence", "travel", "viaggio"], strada: .apri(.satellite)),
        Destinazione(nome: "Ricordi", chiavi: ["ricordi", "traccia", "luoghi"], strada: .apri(.ricordi)),
        Destinazione(nome: "Scanner", chiavi: ["scanner", "codice", "codiceabarre"], strada: .apri(.scanner), dopoLaVoce: true),
        Destinazione(nome: "Shazam", chiavi: ["shazam"], strada: .apri(.shazam), dopoLaVoce: true),
        Destinazione(nome: "Occhi", chiavi: ["occhi", "fotocamera", "camera"], strada: .apri(.occhi), dopoLaVoce: true),
        Destinazione(nome: "Cucina", chiavi: ["cucina", "frigo", "dispensa"], strada: .apri(.cucina), dopoLaVoce: true),
        Destinazione(nome: "Sentinella", chiavi: ["sentinella", "guardia"], strada: .apri(.sentinella), dopoLaVoce: true),
        Destinazione(nome: "Wiretap", chiavi: ["wiretap", "registrazione", "riunione", "registratore"], strada: .apri(.wiretap), dopoLaVoce: true),
        Destinazione(nome: "Profiler", chiavi: ["profiler", "profilo"], strada: .apri(.profiler), dopoLaVoce: true),
        Destinazione(nome: "Trainer", chiavi: ["trainer", "allenatore", "personaltrainer", "allenamento"], strada: .apri(.allenatore), dopoLaVoce: true),
        Destinazione(nome: "LiDAR", chiavi: ["lidar", "scansione", "stanza"], strada: .apri(.lidar), dopoLaVoce: true),
        Destinazione(nome: "Interprete", chiavi: ["interprete", "traduttore", "traduzione"], strada: .apri(.interprete), dopoLaVoce: true),
        Destinazione(nome: "Browser", chiavi: ["browser", "internet", "web", "google"], strada: .apri(.browser)),
        Destinazione(nome: "EDITH", chiavi: ["edith", "sicurezza"], strada: .apri(.edith)),
        Destinazione(nome: "Costi", chiavi: ["costi", "spese", "consumi"], strada: .apri(.costi)),
        Destinazione(nome: "GitHub", chiavi: ["github", "cantiere", "codice"], strada: .apri(.github)),
        Destinazione(nome: "Supabase", chiavi: ["supabase", "salamacchine", "database"], strada: .apri(.supabase)),
        Destinazione(nome: "Archivio", chiavi: ["archivio", "file", "documenti"], strada: .apri(.archivio)),
        Destinazione(nome: "Sistemi", chiavi: ["sistemi"], strada: .apri(.sistemi)),
        Destinazione(nome: "Impostazioni", chiavi: ["impostazioni", "settaggi", "opzioni"], strada: .apri(.impostazioni)),
        Destinazione(nome: "Vitals", chiavi: ["vitals", "parametri", "salute"], strada: .apri(.vitals)),
        Destinazione(nome: "Confidente", chiavi: ["confidente", "sfogo"], strada: .apri(.confidente), dopoLaVoce: true),
        Destinazione(nome: "Studio", chiavi: ["studio", "laboratorio", "officina"], strada: .pagina("Studio")),
        Destinazione(nome: "Social", chiavi: ["social", "instagram"], strada: .pagina("Social")),
    ]

    /// Le sezioni che si presentano alla regia (stato e azioni): per le altre JARVIS vede la riga di `Schermo` e non aspetta che
    /// si presentino. Si aggiorna quando una sezione entra nella regia.
    static let conLaRegia: Set<String> = ["Spesa"]

    static func destinazione(_ nome: String) -> Destinazione? {
        let k = chiave(nome)
        guard !k.isEmpty else { return nil }
        return destinazioni.first { d in chiave(d.nome) == k || d.chiavi.contains(k) }
    }

    /// Il nome ridotto all'osso per i confronti: minuscole, senza accenti, solo lettere e cifre («Lista della spesa» = «listadellaspesa»).
    static func chiave(_ s: String) -> String {
        String(s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            .filter { $0.isLetter || $0.isNumber })
    }

    static func json(_ d: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(d),
              let dati = try? JSONSerialization.data(withJSONObject: d, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: dati, as: UTF8.self)
    }
}

/// La sezione si presenta alla regia: cosa mostra (`stato`, una riga) e cosa sa fare (`azioni`). Davanti, dietro, chiusa: la
/// regia lo sa da sola (come `Schermo`).
private struct PresentaRegia: ViewModifier {
    let nome: String
    let stato: String
    let azioni: [AzioneRegia]
    @Environment(\.sezioneDietro) private var dietro
    @State private var chiave = UUID()

    func body(content: Content) -> some View {
        content
            .sulloSchermo(stato)
            .onAppear { Regia.condivisa.metti(chiave, nome: nome, stato: stato, azioni: azioni, davanti: !dietro) }
            .onChange(of: stato) { _, nuovo in Regia.condivisa.metti(chiave, nome: nome, stato: nuovo, azioni: azioni, davanti: !dietro) }
            .onChange(of: dietro) { _, d in Regia.condivisa.metti(chiave, nome: nome, stato: stato, azioni: azioni, davanti: !d) }
            .onDisappear { Regia.condivisa.togli(chiave) }
    }
}

extension View {
    /// La sezione dice a JARVIS cosa mostra e cosa sa fare (vedi `Regia`). Vale anche come `sulloSchermo`.
    func regia(_ nome: String, stato: String, azioni: [AzioneRegia]) -> some View {
        modifier(PresentaRegia(nome: nome, stato: stato, azioni: azioni))
    }
}
#endif
