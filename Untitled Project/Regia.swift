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
        impara(nome, azioni)
    }

    // MARK: Cosa sanno fare anche da chiuse (12.0 (11))

    /// Stamattina (12 nov, 10:45) il cervello ha detto «non posso cercare in Musica»: vedeva le azioni solo delle sezioni aperte.
    /// Ogni sezione, quando si presenta, lascia qui le sue azioni (in breve: nome, valore, * se serve il sì), ricordate anche
    /// dopo un riavvio; finché una sezione non si è mai aperta valgono quelle scritte qui sotto. La regia apre da sola la
    /// sezione chiusa e poi fa l'azione.
    private lazy var conosciute: [String: String] = Regia.seme.merging(
        (UserDefaults.standard.dictionary(forKey: "regiaSaFare") as? [String: String]) ?? [:]) { _, imparata in imparata }

    private func impara(_ nome: String, _ azioni: [AzioneRegia]) {
        guard !azioni.isEmpty else { return }
        var viste = Set<String>()
        let breve = azioni.filter { viste.insert($0.nome).inserted }
            .map { $0.nome + ($0.valore.map { "(\($0))" } ?? "") + ($0.conferma ? "*" : "") }.joined(separator: ", ")
        let k = Regia.destinazione(nome)?.nome ?? nome
        guard conosciute[k] != breve else { return }
        // una sezione in più pezzi (la posta e la mail aperta): si tengono insieme
        let prima = Set((conosciute[k] ?? "").components(separatedBy: ", ").filter { !$0.isEmpty })
        let unite = (conosciute[k].map { [$0] } ?? []) + breve.components(separatedBy: ", ").filter { !prima.contains($0) }
        conosciute[k] = unite.joined(separator: ", ")
        var salvate = (UserDefaults.standard.dictionary(forKey: "regiaSaFare") as? [String: String]) ?? [:]
        salvate[k] = conosciute[k]
        UserDefaults.standard.set(salvate, forKey: "regiaSaFare")
    }

    /// Le azioni delle sezioni prima che si siano mai aperte (dal codice della 12.0 (11)).
    private static let seme: [String: String] = [
        "Spesa": "aggiungi(cosa), togli(cosa), preso(cosa), rimetti(cosa), svuota*, whatsapp",
        "Email": "aggiorna, apri(quale), non_lette, tutte, cartella(nome), periodo(giorni), chiudi_mail, apri_in_mail",
        "Meteo": "aggiorna",
        "Musica": "metti(quale), cerca(testo), scheda(nome), apri(quale), play, pausa, avanti, indietro, casuale, ripeti",
        "Messaggi": "a(chi), testo(testo), aggiungi(testo), canale(nome), cambia, svuota*, invia*",
        "Telefono": "pagina(nome), componi(numero), cerca(chi), chiama(chi)*",
        "Bea": "le_piace(cosa), non_le_piace(cosa), promessa(cosa), regalo(cosa), idea(cosa), nota(cosa), ti_penso, whatsapp, messaggio, chiama*",
        "Diario": "scrivi",
        "Shazam": "suona(quale), libreria, chiudi_player, elimina(quale)*",
        "Foto": "cerca(cosa), periodo(quando), apri(quale), pulisci",
        "Serata": "scegli(quale)",
        "Ricordi": "scheda(nome), cerca(cosa), guida, salva_qui, fatto(quale), elimina(quale)*",
        "Satellite": "scegli(luogo), ricognizione(indirizzo), filtro(quali), naviga, guida, dossier",
        "GitHub": "apri(repo), tutti",
        "Supabase": "periodo(ore), aggiorna",
        "Archivio": "cartella(nome), cerca(cosa), apri(file), condividi(file), elimina(file)*",
        "Costi": "aggiorna",
        "EDITH": "controlla(tipo, dato)",
        "Vitals": "periodo(giorni)",
    ]

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
        if let scrivi = azioneScrivi(nome) { tutte.append(scrivi) }      // 12.0 (12) · B2: i campi di testo della sezione
        return tutte
    }

    /// Il nome della sezione davanti (nil: JARVIS è davanti).
    private var nomeDavanti: String? { pila?.voceDavanti?.sezione.nome }
    /// 12.0 (12): il nome della sezione davanti, per chi sta fuori dalla regia (Jarvis: «avanti» con la Musica davanti).
    var davantiNome: String? { nomeDavanti }

    // MARK: B2 · i campi di testo (12.0 (12))

    /// Il signore non deve scrivere nei campi: ogni campo di testo di una sezione si presenta alla regia (`campoRegia`), che ci
    /// scrive dentro a voce («scrivi nella ricerca Popstar») e, se è un campo di ricerca, la fa partire.
    private struct Campo {
        let sezione: String
        let nome: String
        let scrivi: (String) -> Void
        let leggi: () -> String
        let invio: (() -> Void)?
        let cerca: Bool
    }
    private var campiTesto: [UUID: Campo] = [:]

    func mettiCampo(_ chiave: UUID, sezione: String, nome: String, scrivi: @escaping (String) -> Void, leggi: @escaping () -> String,
                    invio: (() -> Void)?, cerca: Bool) {
        campiTesto[chiave] = Campo(sezione: sezione, nome: nome, scrivi: scrivi, leggi: leggi, invio: invio, cerca: cerca)
    }

    func togliCampo(_ chiave: UUID) { campiTesto[chiave] = nil }

    private func campi(di nome: String) -> [Campo] {
        let k = Regia.chiave(nome)
        return campiTesto.values.filter { Regia.chiave($0.sezione) == k }.sorted { $0.nome < $1.nome }
    }

    /// L'azione che scrive nei campi della sezione: «testo» (e «campo», se ce n'è più di uno; «invia»: «sì» per premere il tasto).
    private func azioneScrivi(_ nome: String) -> AzioneRegia? {
        let lista = campi(di: nome)
        guard !lista.isEmpty else { return nil }
        let nomi = lista.map { c in c.nome + (c.leggi().isEmpty ? "" : " («\(Regia.taglia(c.leggi(), 40))»)") }.joined(separator: ", ")
        return AzioneRegia("scrivi_campo", "scrive nel campo di testo (campi: \(nomi)); invia=sì preme il suo tasto", valore: "testo",
                           frasi: ["scrivi *", "scrivici *", "digita *", "scrivi nel campo *"]) { [weak self] v in
            guard let self else { return .no("regia non pronta") }
            return self.scriviNelCampo(sezione: nome, campo: v["campo"], testo: v["testo"] ?? "", invia: Regia.chiave(v["invia"] ?? "") == "si")
        }
    }

    private func scriviNelCampo(sezione: String, campo detto: String?, testo grezzo: String, invia: Bool) -> EsitoRegia {
        let lista = campi(di: sezione)
        var testo = grezzo.trimmingCharacters(in: .whitespacesAndNewlines)
        var scelto: Campo?
        if let d = detto, !d.isEmpty { scelto = Regia.scegli(d, fra: lista, testo: { $0.nome }) }
        // «scrivi nella ricerca Popstar»: il campo detto davanti al testo
        if scelto == nil {
            let p = testo.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            let attacchi: Set<String> = ["nel", "nella", "nello", "nell", "in", "sul", "sulla", "al", "alla", "campo"]
            if let primo = p.first.map({ Regia.chiave($0) }), attacchi.contains(primo) {
                for c in lista {
                    let parole = c.nome.split(separator: " ").count
                    var k = 1
                    while k < p.count, Regia.chiave(p[k]) == "campo" { k += 1 }
                    if p.count > k + parole - 1, Regia.chiave(p[k..<(k + parole)].joined()) == Regia.chiave(c.nome) {
                        scelto = c
                        testo = p[(k + parole)...].joined(separator: " ")
                        break
                    }
                }
            }
        }
        // con più campi e nessuno detto, non si tira a indovinare (Messaggi: contatto o messaggio?): decide il cervello
        if scelto == nil, lista.count > 1 { return .no("quale campo? \(lista.map(\.nome).joined(separator: ", "))") }
        guard let c = scelto ?? lista.first else { return .no("qui non ci sono campi di testo") }
        guard !testo.isEmpty else { return .no("niente da scrivere") }
        c.scrivi(testo)
        evento("\(sezione): scritto «\(Regia.taglia(testo, 40))» in \(c.nome)")
        if (invia || c.cerca), let invio = c.invio { invio() }
        let nomeCampo = c.nome, scritto = testo
        return .fatto("scritto «\(testo)» nel campo \(c.nome)" + ((invia || c.cerca) && c.invio != nil ? " e premuto il suo tasto" : ""),
                      battuta: { Battute.campoScritto(nomeCampo, scritto) })
    }

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
            if let p = proposta, Date().timeIntervalSince(p.quando) < 45 { pezzi.append("HAI APPENA PROPOSTO: \(p.testo) (se dice sì la fa l'app)") }
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
        // 12.0 (11): cosa sanno fare le sezioni chiuse (la regia le apre da sola e poi fa l'azione); in fondo, così se la riga è
        // troppo lunga si accorcia questa e non quello che c'è davanti
        let aperteNomi = Set(aperte.map(\.sezione.nome))
        let chiuse = Regia.destinazioni.map(\.nome).filter { !aperteNomi.contains($0) }.compactMap { n in conosciute[n].map { "\(n): \($0)" } }
        if !chiuse.isEmpty { pezzi.append("SA FARE ANCHE DA CHIUSE (la regia le apre da sola, poi l'azione): " + chiuse.joined(separator: "; ")) }
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
        var valori = p.valori
        if let k = a.valore, !k.contains(","), valori[k] == nil, valori.count == 1, let unico = valori.values.first { valori = [k: unico] }   // 12.0 (11)
        let e = await a.esegui(valori)
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
    func subito(_ fraseDetta: String) async -> String? {
        // 12.0 (12) · B6: aveva appena proposto qualcosa («La solita playlist?»): un sì la fa, qualsiasi altra frase la lascia cadere
        if let p = proposta {
            proposta = nil
            if Date().timeIntervalSince(p.quando) < 45, Regia.eAssenso(fraseDetta) {
                evento("fatta la proposta: \(p.testo)")
                return await p.fai() ?? ""
            }
        }
        // 12.0 (12) · B3: «annulla», «lascia stare», «non mandarlo» con un invio (o un'eliminazione) in attesa del sì
        if inSospeso != nil, Regia.eAnnulla(fraseDetta) {
            inSospeso = nil
            evento("annullato")
            return Battute.annullato()
        }
        // 12.0 (12) · B3: vale l'ultima intenzione («metti Sfera… no anzi, i Daft Punk»); vuota: ha cambiato idea, niente da fare
        let frase = FineFrase.ultimaIntenzione(fraseDetta)
        if frase.isEmpty { return fraseDetta.isEmpty ? nil : Battute.lasciamoStare() }
        let parole = Regia.paroleComando(frase)
        guard !parole.isEmpty else { return nil }
        // 12.0 (12) · B1: più comandi in fila («apri la spesa e aggiungi il latte»): se l'app li sa fare tutti, li fa lei subito
        if FineFrase.comandoComposto(frase) { return await subitoComposto(frase) }
        return await subitoUno(frase)
    }

    /// Un comando solo: la sezione davanti, i tasti della musica, poi (B1) le intenzioni che valgono da qualsiasi schermata.
    private func subitoUno(_ frase: String) async -> String? {
        let parole = Regia.paroleComando(frase)
        guard !parole.isEmpty else { return nil }
        // prima la sezione davanti, poi le azioni che valgono ovunque (i tasti della musica, se c'è qualcosa in coda)
        let d = nomeDavanti ?? "JARVIS"
        let davanti = nomeDavanti.map { azioni(di: $0) } ?? []
        for a in davanti + globali where !a.conferma {
            for schema in a.frasi {
                guard let m = Regia.combaciaDove(parole, schema) else { continue }
                let valore = m.valore
                // «apri la spesa» con la Posta davanti è la sezione Spesa, non una mail che parla di spesa
                if a.nome == "apri", !valore.isEmpty, Regia.destinazione(valore) != nil { continue }
                var valori: [String: String] = [:]
                // i campi di testo vogliono le parole come sono state dette (maiuscole e accenti), non piegate
                if let v = a.valore, !valore.isEmpty { valori[v] = a.nome == "scrivi_campo" ? Regia.originale(frase, da: m.da, a: m.a) : valore }
                let e = await a.esegui(valori)
                if !e.ok && e.battuta == nil { continue }         // non era per questa azione: si prova la prossima (o il cervello)
                if e.ok { evento("\(d): \(Regia.taglia(e.dato, 80))") }
                return e.battuta?() ?? ""
            }
        }
        return await intenzione(frase)
    }

    // MARK: B1 · da qualsiasi schermata (12.0 (12))

    /// Le intenzioni frequenti riconosciute da qualsiasi schermata: la regia apre la sezione se serve e fa l'azione, senza
    /// cervello, con la battuta di JARVIS. Le frasi dicono la sezione («alla spesa», «in lista»): «metti in ordine la stanza»
    /// non finisce nella lista. Quelle senza (`frasiDentro`) valgono quando la sezione è già davanti o è stata appena aperta
    /// nella stessa frase («apri la spesa e aggiungi il latte»).
    private struct Intenzione {
        let sezione: String
        let azione: String
        let valore: String?
        let frasi: [String]
        var frasiDentro: [String] = []
    }

    private static let intenzioni: [Intenzione] = [
        Intenzione(sezione: "Spesa", azione: "aggiungi", valore: "cosa",
                   frasi: ["aggiungi * alla spesa", "aggiungi * alla lista della spesa", "aggiungi * alla lista", "aggiungi * in lista",
                           "metti * in lista", "metti * nella lista", "metti * alla spesa", "metti in lista *", "segna * nella spesa",
                           "segna * nella lista", "segna * in lista", "devo comprare *", "compra *", "comprami *"],
                   frasiDentro: ["aggiungi *", "aggiungimi *", "segna *", "segnami *"]),      // «metti …» resta la musica
        Intenzione(sezione: "Spesa", azione: "togli", valore: "cosa",
                   frasi: ["togli * dalla spesa", "togli * dalla lista", "leva * dalla lista", "leva * dalla spesa", "cancella * dalla lista",
                           "cancella * dalla spesa", "depenna *"],
                   frasiDentro: ["togli *", "toglimi *", "leva *", "levami *", "cancella *"]),
        Intenzione(sezione: "Spesa", azione: "preso", valore: "cosa", frasi: ["ho preso * della spesa"], frasiDentro: ["ho preso *", "preso *", "spunta *"]),
        Intenzione(sezione: "Meteo", azione: "adesso", valore: nil,
                   frasi: ["che tempo fa", "che tempo fa oggi", "che tempo fa adesso", "che tempo fa fuori", "com e il tempo", "com e il tempo oggi",
                           "com e il meteo", "che tempo c e", "dimmi il meteo", "dimmi che tempo fa", "il meteo di oggi", "meteo di oggi"]),
    ]

    /// B1: un'intenzione detta da qualsiasi schermata (o, `dentro`, con la sua sezione davanti). Nil: non è sua.
    private func intenzione(_ frase: String, dentro: String? = nil) async -> String? {
        let parole = Regia.paroleComando(frase)
        for i in Regia.intenzioni {
            let schemi = i.frasi + ((dentro ?? nomeDavanti) == i.sezione ? i.frasiDentro : [])
            for schema in schemi {
                guard let valore = Regia.combacia(parole, schema) else { continue }
                var valori: [String: String] = [:]
                if let v = i.valore, !valore.isEmpty { valori[v] = valore }
                let e = await passo(Passo(sezione: i.sezione, azione: i.azione, valori: valori))
                if !e.ok && e.battuta == nil { return nil }       // la sezione non l'ha fatta: decide il cervello
                return e.battuta?() ?? ""
            }
        }
        // la musica: «metti Popstar di Sfera Ebbasta», «fammi sentire i Daft Punk», «metti un po' di musica»
        return await musicaDetta(frase)
    }

    private static let frasiMetti = ["metti su *", "metti *", "mettimi *", "fammi sentire *", "fammi ascoltare *", "riproduci *", "suona *",
                                     "suonami *", "fai partire *", "spara *"]
    private static let musicaGenerica: Set<String> = ["metti un po di musica", "metti musica", "metti della musica", "metti la musica",
                                                       "metti su un po di musica", "metti su qualcosa", "metti qualcosa", "fammi sentire qualcosa",
                                                       "fammi sentire un po di musica", "un po di musica", "musica", "metti un po di musica dai"]

    /// B1: la musica da qualsiasi schermata, senza aprire la sezione: cerca, sceglie il risultato che combacia davvero con le
    /// parole dette e lo fa partire (la musica suona dietro, il disco gira nel Dock). Nil: non era musica, o niente di
    /// abbastanza simile: decide il cervello.
    private func musicaDetta(_ frase: String) async -> String? {
        let parole = Regia.paroleComando(frase)
        if Regia.musicaGenerica.contains(parole.joined(separator: " ")) {
            let l = LettoreMusica.condiviso
            await l.play()
            if let e = l.errore { return e }
            evento("musica: play")
            return Battute.musica("play")
        }
        for schema in Regia.frasiMetti {
            guard let m = Regia.combaciaDove(parole, schema, altro: Regia.nonMusica) else { continue }
            let detto = Regia.originale(frase, da: m.da, a: m.a)
            guard let esito = await LettoreMusica.condiviso.mettiDetto(detto) else { return nil }
            if let e = esito.errore { return e }
            guard let nome = esito.nome else { return nil }
            evento("musica: \(Regia.taglia(nome, 60))")
            Abitudini.segna("musica", detto)
            return Battute.musicaMetti(nome)
        }
        return nil
    }

    /// Parole che dicono che «metti …» non è musica (una sveglia, la lista, un posto, una pausa): va al cervello.
    private static let nonMusica: Set<String> = ["sveglia", "timer", "promemoria", "lista", "spesa", "calendario", "appuntamento", "messaggio",
                                                 "messaggi", "mail", "email", "posta", "foto", "video", "sezione", "sezioni", "chat", "jarvis",
                                                 "telefono", "ordine", "posto", "pausa", "nota", "appunti", "parte", "luce", "luci", "allarme",
                                                 "volume", "sottovoce", "silenzioso", "riservato"]

    // MARK: B1 · più comandi in fila, senza cervello (12.0 (12))

    /// «Apri la spesa e aggiungi il latte», «chiudi tutto e dimmi il meteo», «apri la musica e metti Sfera»: se l'app sa fare
    /// ogni pezzo li fa uno dopo l'altro, subito; se anche uno solo non lo sa fare, nessuno parte e la frase va al cervello
    /// (che li fa in fila con la regia). La battuta è quella dell'ultimo pezzo.
    private func subitoComposto(_ frase: String) async -> String? {
        let pezzi = Regia.pezzi(frase)
        guard pezzi.count >= 2, pezzi.count <= 4 else { return nil }
        // prima si controlla che si sappiano fare tutti (senza fare niente), con la sezione che sarà davanti a ogni passo
        var davanti = nomeDavanti
        var piano: [(pezzo: String, tipo: Pezzo)] = []
        for p in pezzi {
            guard let t = riconosci(p, davanti: davanti) else { return nil }
            if case .apri(let n) = t { davanti = n }
            if case .chiudiTutto = t { davanti = nil }
            if case .intenzione(let n) = t { davanti = n }
            piano.append((p, t))
        }
        var battuta: String?
        for (k, voce) in piano.enumerated() {
            switch voce.tipo {
            case .apri(let n):
                let e = await apri(n)
                guard e.ok else { return k == 0 ? nil : (e.battuta?() ?? "") }
                battuta = Regia.aperturaDi(n)
            case .chiudiTutto:
                vai?(.chiudiTutto)
                evento("chiuse tutte le sezioni")
                try? await Task.sleep(for: .milliseconds(350))
                battuta = Battute.chiusoTutto()
            case .intenzione(let n):
                battuta = await intenzione(voce.pezzo, dentro: n)
            case .musica:
                battuta = await musicaDetta(voce.pezzo)
            }
        }
        evento("in fila: " + pezzi.joined(separator: " → "))
        return battuta ?? ""
    }

    private enum Pezzo { case apri(String), chiudiTutto, intenzione(String), musica }

    /// 12.0 (12): la frase la farebbe la regia da sola? (Senza fare niente: serve per non chiedere al cervello una risposta
    /// anticipata che sarebbe buttata.)
    func forseLocale(_ frase: String) -> Bool {
        let f = FineFrase.ultimaIntenzione(frase)
        if f.isEmpty { return true }
        if inSospeso != nil, Regia.eAnnulla(f) { return true }
        if let p = proposta, Date().timeIntervalSince(p.quando) < 45, Regia.eAssenso(f) { return true }
        let pezzi = FineFrase.comandoComposto(f) ? Regia.pezzi(f) : [f]
        var davanti = nomeDavanti
        for pezzo in pezzi {
            guard let t = riconosci(pezzo, davanti: davanti) else { return false }
            switch t {
            case .apri(let n), .intenzione(let n): davanti = n
            case .chiudiTutto: davanti = nil
            case .musica: break
            }
        }
        return true
    }

    /// Cosa sarebbe un pezzo di frase per l'app, con `davanti` come sezione davanti in quel momento. Nil: non lo sa fare da sola.
    private func riconosci(_ pezzo: String, davanti: String?) -> Pezzo? {
        let parole = Regia.paroleComando(pezzo)
        guard !parole.isEmpty else { return nil }
        let j = parole.joined(separator: " ")
        if ["chiudi tutto", "chiudi tutte le sezioni", "chiudile tutte"].contains(j) { return .chiudiTutto }
        for schema in ["apri *", "aprimi *", "mostrami *", "vai alla *", "vai al *", "vai in *", "portami alla *", "portami al *", "porta davanti *"] {
            if let v = Regia.combacia(parole, schema, altro: []), let d = Regia.destinazione(v), !d.dopoLaVoce { return .apri(d.nome) }
        }
        for i in Regia.intenzioni {
            let schemi = i.frasi + (davanti == i.sezione ? i.frasiDentro : [])
            if schemi.contains(where: { Regia.combacia(parole, $0) != nil }) { return .intenzione(i.sezione) }
        }
        if Regia.musicaGenerica.contains(j) || Regia.frasiMetti.contains(where: { Regia.combacia(parole, $0, altro: Regia.nonMusica) != nil }) {
            return .musica
        }
        return nil
    }

    /// I pezzi di una frase con più comandi: «apri la spesa e poi aggiungi il latte» → «apri la spesa» · «aggiungi il latte».
    /// Si taglia solo davanti a un verbo di comando («aggiungi pane e latte» resta un pezzo solo).
    static func pezzi(_ frase: String) -> [String] {
        let parole = frase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let legami: Set<String> = ["e", "ed", "poi", "quindi", "dopo"]
        let ponte: Set<String> = ["poi", "anche", "intanto", "dopo", "pure", "subito"]
        var pezzi: [[String]] = [[]]
        var i = 0
        while i < parole.count {
            let w = Regia.chiave(parole[i])
            if legami.contains(w), !(pezzi.last ?? []).isEmpty {
                var j = i + 1
                while j < parole.count, ponte.contains(Regia.chiave(parole[j])) { j += 1 }
                if j < parole.count, FineFrase.comandoComposto("x y " + w + " " + parole[j...].joined(separator: " ")) {
                    pezzi.append([])
                    i = j
                    continue
                }
            }
            pezzi[pezzi.count - 1].append(parole[i])
            i += 1
        }
        return pezzi.map { $0.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,;.")) }.filter { !$0.isEmpty }
    }

    // MARK: B6 · la proposta (12.0 (12))

    /// Quello che JARVIS ha appena proposto («Le metto la solita playlist?»): un sì nei 45 secondi dopo la fa, senza cervello.
    var proposta: (testo: String, quando: Date, fai: @MainActor () async -> String?)?

    /// Apre una sezione da fuori (la proposta di Abitudini): come «apri».
    func apriDaFuori(_ nome: String) async -> String? {
        let e = await apri(nome)
        guard e.ok else { return nil }
        return Regia.aperturaDi(nome)
    }

    /// La frase d'apertura della sezione (Battute), come quando la si apre a voce.
    static func aperturaDi(_ nome: String) -> String {
        guard let d = destinazione(nome), case .apri(let r) = d.strada else { return "" }
        return Battute.apertura(r) ?? ""
    }

    /// Le azioni rapide che valgono ovunque, con qualsiasi sezione davanti: i tasti della musica, se c'è qualcosa in coda.
    private var globali: [AzioneRegia] { LettoreMusica.condiviso.voce != nil ? Regia.tastiMusica : [] }

    /// I tasti della musica, a voce (la sezione MUSICA e ovunque se c'è musica in coda). Frasi cortissime: mentre JARVIS parla
    /// la musica è in pausa.
    static let tastiMusica: [AzioneRegia] = [
        AzioneRegia("play", "fa partire o riprende la musica", frasi: ["play", "riprendi", "riparti", "fai partire", "rimetti la musica", "riprendi la musica"]) { _ in
            let l = LettoreMusica.condiviso
            await l.play()
            if let e = l.errore { return .no(e, battuta: { e }) }
            return .fatto("in riproduzione: \(l.titolo)", battuta: { Battute.musica("play") })
        },
        AzioneRegia("pausa", "mette in pausa", frasi: ["pausa", "metti in pausa", "stop", "ferma", "ferma la musica", "stoppa"]) { _ in
            LettoreMusica.condiviso.pausa()
            return .fatto("musica in pausa", battuta: { Battute.musica("pausa") })
        },
        AzioneRegia("avanti", "brano successivo", frasi: ["avanti", "prossimo", "prossima", "salta", "brano successivo", "il prossimo",
                                                          "la prossima", "next", "cambia brano", "cambia canzone", "skip"]) { _ in
            let l = LettoreMusica.condiviso
            await l.avanti()
            return .fatto("brano successivo", battuta: { Battute.musica("avanti") })
        },
        AzioneRegia("indietro", "brano precedente (o da capo)", frasi: ["indietro", "precedente", "torna indietro", "brano precedente",
                                                                        "canzone precedente", "da capo"]) { _ in
            await LettoreMusica.condiviso.indietro()
            return .fatto("brano precedente", battuta: { Battute.musica("indietro") })
        },
        AzioneRegia("casuale", "accende o spegne l'ordine casuale", frasi: ["casuale", "riproduzione casuale", "mescola", "shuffle"]) { _ in
            let l = LettoreMusica.condiviso
            l.cambiaCasuale()
            let acceso = l.casuale
            return .fatto(acceso ? "ordine casuale" : "ordine normale", battuta: { Battute.musica("casuale", acceso: acceso) })
        },
        AzioneRegia("ripeti", "ripete lo stesso brano (sì/no)", frasi: ["ripeti", "ripeti il brano", "a ripetizione", "ripeti questa"]) { _ in
            let l = LettoreMusica.condiviso
            l.cambiaRipeti()
            let acceso = l.ripeti
            return .fatto(acceso ? "ripete il brano" : "ripeti spento", battuta: { Battute.musica("ripeti", acceso: acceso) })
        },
    ]

    /// Le parole di un comando: minuscole, senza accenti né punteggiatura, senza il nome e le cortesie davanti e in fondo.
    /// 12.0 (12): quante parole restano togliendo solo le cortesie davanti (per ritrovare le parole com'erano dette).
    static func paroleComandoDavanti(_ frase: String) -> Int {
        var p = FineFrase.paroleNude(frase)
        while let f = p.first, cortesieDavanti.contains(f) { p.removeFirst() }
        return p.count
    }

    private static let cortesieDavanti: Set<String> = ["ok", "okay", "dai", "allora", "ehi", "hey", "per", "favore", "senti", "ecco", "bene", "perfetto", "sir"]

    /// 12.0 (12) · errore 2: la frase è un tasto della musica («avanti», «pausa»…)?
    static func eTastoMusica(_ frase: String) -> Bool {
        let p = paroleComando(frase)
        return tastiMusica.contains { a in a.frasi.contains { combacia(p, $0) != nil } }
    }

    /// 12.0 (12) · B3: «annulla», «lascia stare», «non mandarlo» con qualcosa in attesa del sì.
    static func eAnnulla(_ frase: String) -> Bool {
        let p = paroleComando(frase).joined(separator: " ")
        return ["annulla", "annullalo", "annullala", "lascia stare", "lascia perdere", "non mandarlo", "non mandarla", "non inviarlo", "non inviarla",
                "no non mandarlo", "no non mandarla", "no lascia stare", "no annulla", "non farlo", "no non farlo", "non chiamare", "non chiamarlo",
                "non chiamarla", "non eliminarlo", "non eliminarla", "ferma tutto", "niente", "no niente", "lascia"].contains(p)
    }

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
    static func combacia(_ parole: [String], _ schema: String, altro: Set<String>? = nil) -> String? {
        combaciaDove(parole, schema, altro: altro)?.valore
    }

    /// 12.0 (12): come `combacia`, con dove sta il valore fra le parole (per riprenderlo com'era detto) e l'asterisco anche in
    /// mezzo («aggiungi * alla spesa»). Il valore non comincia con «che» («segna che domani…» non è una cosa da comprare).
    static func combaciaDove(_ parole: [String], _ schema: String, altro: Set<String>? = nil) -> (valore: String, da: Int, a: Int)? {
        let s = FineFrase.paroleNude(schema.replacingOccurrences(of: "*", with: " stellaregia "))
        guard let k = s.firstIndex(of: "stellaregia") else { return parole == s ? ("", 0, 0) : nil }
        let prima = Array(s[..<k]), dopo = Array(s[(k + 1)...])
        guard parole.count >= prima.count + dopo.count + 1, Array(parole.prefix(prima.count)) == prima,
              Array(parole.suffix(dopo.count)) == dopo else { return nil }
        var da = prima.count
        let a = parole.count - dopo.count
        let articoli: Set<String> = ["il", "lo", "la", "i", "gli", "le", "l", "un", "uno", "una", "del", "dello", "della", "dei", "degli", "delle", "anche"]
        while da < a, articoli.contains(parole[da]) { da += 1 }
        let resto = Array(parole[da..<a])
        let fuori = altro ?? Regia.altroMondo
        guard !resto.isEmpty, resto.first != "che", !resto.contains(where: { fuori.contains($0) }) else { return nil }
        return (resto.joined(separator: " "), da, a)
    }

    /// 12.0 (12): le parole dalla `da` alla `a` (contate come `paroleComando`) prese dalla frase com'era detta: maiuscole, accenti,
    /// apostrofi («Popstar», «perché», «l'ombrello»).
    static func originale(_ frase: String, da: Int, a: Int) -> String {
        // i pezzi di parola come li conta `paroleNude` (lettere e cifre), con dove stanno nella frase
        var pezzi: [Range<String.Index>] = []
        var inizio: String.Index?
        var i = frase.startIndex
        while i < frase.endIndex {
            let c = frase[i]
            if c.isLetter || c.isNumber { if inizio == nil { inizio = i } }
            else if let s = inizio { pezzi.append(s..<i); inizio = nil }
            i = frase.index(after: i)
        }
        if let s = inizio { pezzi.append(s..<frase.endIndex) }
        // via il nome di JARVIS (come `paroleNude`) e le cortesie davanti (come `paroleComando`)
        let nude = FineFrase.paroleNude(frase)
        pezzi = pezzi.filter { r in
            let p = String(frase[r]).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            return !FineFrase.nomiJarvis.contains(where: { p.hasPrefix($0) })
        }
        let davanti = nude.count - Regia.paroleComandoDavanti(frase)
        let x = davanti + da, y = davanti + a
        guard x < y, y <= pezzi.count else { return nude.dropFirst(x).prefix(max(0, y - x)).joined(separator: " ") }
        return String(frase[pezzi[x].lowerBound..<pezzi[y - 1].upperBound])
    }

    /// Parole che, dentro il valore di una frase rapida, dicono che la frase parla d'altro: va al cervello.
    private static let altroMondo: Set<String> = ["musica", "canzone", "canzoni", "brano", "playlist", "sveglia", "timer", "promemoria",
                                                  "calendario", "appuntamento", "messaggio", "messaggi", "mail", "email", "posta", "foto",
                                                  "video", "sezione", "sezioni", "chat", "conversazione", "meteo", "jarvis", "telefono"]

    /// «la prima», «seconda», «3», «l'ultima»: la posizione in un elenco (1 = la prima; -1 = l'ultima). Nil: non è una posizione.
    static func ordinale(_ s: String) -> Int? {
        let p = FineFrase.paroleNude(s).filter { !["la", "il", "l", "lo", "numero", "mail", "email", "riga", "voce"].contains($0) }
        guard let w = p.first, p.count <= 2 else { return nil }
        if let n = Int(w), n > 0 { return n }
        if w == "ultima" || w == "ultimo" { return -1 }
        if w == "penultima" || w == "penultimo" { return -2 }
        let ordine = ["prim", "second", "terz", "quart", "quint", "sest", "settim", "ottav", "non", "decim"]
        if let i = ordine.firstIndex(where: { w == $0 + "a" || w == $0 + "o" }) { return i + 1 }
        let numeri = ["uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci"]
        if let i = numeri.firstIndex(of: w) { return i + 1 }
        return nil
    }

    /// L'elemento di un elenco scelto a voce: per posizione («la seconda», «l'ultima») o per parole contenute nel testo di ciascuno.
    static func scegli<T>(_ detto: String, fra elementi: [T], testo: (T) -> String) -> T? {
        guard !elementi.isEmpty else { return nil }
        if let n = ordinale(detto) {
            if n > 0 { return n <= elementi.count ? elementi[n - 1] : nil }
            return elementi.count + n >= 0 ? elementi[elementi.count + n] : nil
        }
        let chiavi = FineFrase.paroleNude(detto).filter { $0.count > 2 && !["della", "delle", "dello", "degli", "che", "con", "per", "dal", "dalla", "mail", "email"].contains($0) }
        guard !chiavi.isEmpty else { return nil }
        let punti = elementi.map { e -> Int in
            let t = FineFrase.paroleNude(testo(e)).joined(separator: " ")
            return chiavi.filter { t.contains($0) }.count
        }
        guard let migliore = punti.max(), migliore > 0, let i = punti.firstIndex(of: migliore) else { return nil }
        return elementi[i]
    }

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
        Destinazione(nome: "Scanner", chiavi: ["scanner", "codiceabarre", "barcode"], strada: .apri(.scanner), dopoLaVoce: true),
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
        Destinazione(nome: "GitHub", chiavi: ["github", "cantiere", "repository"], strada: .apri(.github)),
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
    static let conLaRegia: Set<String> = ["Spesa", "Email", "Meteo", "Briefing", "Musica", "Messaggi", "Telefono", "Bea", "Diario", "Sonno", "Cuore", "Shazam", "Foto", "Serata", "Ricordi", "Satellite", "GitHub", "Supabase", "Archivio", "Costi", "EDITH", "Vitals"]

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
            .environment(\.sezioneRegia, nome)                   // 12.0 (12) · B2: i campi di testo dentro sanno di chi sono
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

    /// 12.0 (12) · B2: il campo di testo si presenta alla regia, che ci scrive a voce. `cerca`: è un campo di ricerca, scritto il
    /// testo parte da solo `invio` (se c'è); senza, `invio` lo preme solo se il signore lo chiede («scrivi … e invia»).
    func campoRegia(_ nome: String, testo: Binding<String>, cerca: Bool = false, invio: (() -> Void)? = nil) -> some View {
        modifier(CampoRegia(nome: nome, testo: testo, cerca: cerca, invio: invio))
    }
}

/// Di quale sezione sono i campi di testo qui dentro (lo dice `regia`).
private struct ChiaveSezioneRegia: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var sezioneRegia: String? {
        get { self[ChiaveSezioneRegia.self] }
        set { self[ChiaveSezioneRegia.self] = newValue }
    }
}

/// 12.0 (12) · B2: un campo di testo che la regia sa riempire.
private struct CampoRegia: ViewModifier {
    let nome: String
    @Binding var testo: String
    let cerca: Bool
    let invio: (() -> Void)?
    @Environment(\.sezioneRegia) private var sezione
    @State private var chiave = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { registra() }
            .onChange(of: sezione) { _, _ in registra() }
            .onDisappear { Regia.condivisa.togliCampo(chiave) }
    }

    private func registra() {
        guard let sezione else { return }
        let campo = $testo
        Regia.condivisa.mettiCampo(chiave, sezione: sezione, nome: nome, scrivi: { campo.wrappedValue = $0 }, leggi: { campo.wrappedValue },
                                   invio: invio, cerca: cerca)
    }
}
#endif
