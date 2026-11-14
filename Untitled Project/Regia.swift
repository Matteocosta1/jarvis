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
    /// 14 nov: quello che mostra la sezione davanti se non è ancora nella regia (la riga di `Schermo`, da Jarvis): serve agli strumenti
    /// «schermo» e «mano» per dire al cervello com'è lo schermo dopo un passo.
    var rigaVecchia: (() -> String?)?
    /// 14 nov: gli strumenti che l'app descrive al cervello da sé (senza ripubblicarlo): la regia, il piano, le mani, lo schermo.
    static var definizioni: [[String: Any]] { [definizione, Piano.definizione, ManiJarvis.definizione, ManiJarvis.definizioneSchermo] }
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
    /// 14 nov: un invio, un'eliminazione, una chiamata aspettano il sì.
    var aspettaIlSi: Bool { inSospeso.map { Date().timeIntervalSince($0.quando) < 180 } ?? false }

    // MARK: Le sezioni si presentano

    func metti(_ chiave: UUID, nome: String, stato: String, azioni: [AzioneRegia], davanti: Bool) {
        var ordine = scene[chiave]?.ordine ?? 0
        let arrivata = davanti && scene[chiave]?.davanti != true
        if scene[chiave]?.davanti != davanti || ordine == 0 {      // appena arrivata davanti: diventa la più recente
            contatore += 1
            ordine = contatore
        }
        scene[chiave] = Scena(nome: nome, stato: stato, azioni: azioni, davanti: davanti, ordine: ordine)
        impara(nome, azioni)
        // 14 nov: ogni sezione che arriva davanti (col dito, a voce o dal cervello) entra nel filo del discorso: dopo, «fissalo»,
        // «mandalo a Bea» sanno di cosa si parla, in una frase sola o in due (come il mockup, segnaSezione)
        if arrivata, let d = Regia.destinazione(nome) { metteNelFilo(d) }
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
        if self.viste(di: nome) != nil, let vista = azioneVista(nome) { tutte.append(vista) }   // 14 nov: le viste dell'ologramma (`viste` qui sopra è il Set)
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
        // 14 nov: i tasti che si vedono (le mani di JARVIS) e il piano in corso, subito dopo davanti
        if nomeDavanti != nil, let t = ManiJarvis.perCervello() { pezzi.append(t) }
        if let p = Piano.condiviso.perCervello { pezzi.append(p) }
        // 12.0 (16): il filo del discorso, il lavoro insieme, la fretta (subito dopo davanti: se la riga è lunga si accorcia altro)
        if let f = Filo.condiviso.perCervello() { pezzi.append(f) }
        if let ses = Sessione.condivisa.perCervello() { pezzi.append(ses) }
        if Battute.umore == .fretta { pezzi.append("RITMO: il signore ha fretta: rispondi in una riga sola (se poi dice «dimmi meglio», la versione intera)") }
        let dietro = aperte.map(\.sezione.nome).filter { $0 != nomeDavanti }
        for n in dietro.suffix(6) {
            var riga = "DIETRO \(n)"
            if let s = statoDi(n) { riga += ": " + Regia.taglia(s, 280) }
            let a = azioni(di: n)
            if !a.isEmpty { riga += " · azioni: " + Regia.elenco(a) }
            pezzi.append(riga)
        }
        pezzi.append("SI APRONO: " + Regia.destinazioni.map(\.nome).joined(separator: ", "))
        // 14 nov (il signore: «come Iron Man: attivo, sveglio, reattivo»): la tab mostra da sola i dati che servono per decidere
        pezzi.append("SEMPRE: apri(sezione), chiudi(sezione), da_parte (quella davanti va dietro, resta accesa), di_prima (torna davanti quella di prima), sfoglia, chiudi_tutto, mostra(sezione, titolo, riga): il dato nella tab in alto a destra (FILO), divisa per argomento (sezione = di quale argomento è: Meteo, Briefing per l'agenda, Messaggi, Travel…), senza aprire sezioni. LA TAB DA SOLA: ogni volta che nella risposta dai un dato che serve al signore per decidere (meteo e pioggia, orari, impegni, percorsi e mezzi, numeri, incassi, un messaggio) e non è già sullo schermo davanti, mettilo nella tab con mostra mentre rispondi (titolo una parola, riga il dato in breve; l'agenda un impegno dopo l'altro separati da « · »); per chiacchiere, pareri e battute niente tab. Resta finché parli, poi sparisce da sola; «fissalo» la tiene. «Mostrami…», «fammi vedere…» non aprono sezioni; «apri…» apre la sezione. Più cose in una frase («mettilo dietro e apri i messaggi», «torna allo studio»): fai tutto, in ordine. LA TAB A VOCE (sezione vuota): tab_fissa(titolo) e tab_sgancia(titolo) (titolo = l'argomento: Meteo, Agenda, Messaggi…; vuoto = quello di cui si parla), tab_togli(titolo), tab_vuota, tab_nascondi (va via, si richiama), tab_richiama. Le viste dell'ologramma della sezione davanti: vista(nome), coi nomi delle sue chip. Scorrere la pagina: mano scorri. «Mandalo a Foto», «portalo in Musica», «mandalo a LiDAR»: se il nome è di una sezione e non di una persona della rubrica è andare in quella sezione (apri), non un messaggio")
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
                            "azione": ["type": "string", "description": "apri, chiudi, da_parte, di_prima, sfoglia, chiudi_tutto, mostra, tab_fissa, tab_sgancia, tab_togli, tab_vuota, tab_nascondi, tab_richiama, oppure un'azione della sezione"],
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
        if confermato, !fatti.isEmpty, fatti.allSatisfy({ $0["ok"] as? Bool == true }) { Congedo.condiviso.cosaVera() }   // 12.0 (16)
        var risposta: [String: Any] = ["fatti": fatti]
        if let d = nomeDavanti { risposta["davanti"] = d + (statoDi(d).map { ": " + Regia.taglia($0, 600) } ?? "") } else { risposta["davanti"] = "JARVIS" }
        return (Regia.json(risposta), false)
    }

    /// Un passo: le strade di sempre o un'azione di una sezione (che si apre da sola, se serve).
    private func passo(_ p: Passo) async -> EsitoRegia {
        switch Regia.chiave(p.azione) {
        case "apri", "davanti", "porta", "torna":
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
        case "mostra", "widget", "filo":                                 // 12.0 (16): il widget FILO, senza aprire niente
            let titolo = (p.valori["titolo"] ?? p.sezione).trimmingCharacters(in: .whitespacesAndNewlines)
            let riga = (p.valori["riga"] ?? p.valori["testo"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // «mostra» senza riga, con una sezione: come prima, la apre (i passi scritti prima della 12.0 (16))
            if riga.isEmpty, !p.sezione.isEmpty, Regia.chiave(p.azione) == "mostra" { return await apri(p.sezione) }
            guard !titolo.isEmpty, !riga.isEmpty else { return .no("mostra vuole titolo e riga") }
            Filo.condiviso.mostra("cer:" + Regia.chiave(titolo), titolo: String(titolo.prefix(14)), riga: String(riga.prefix(90)),
                                  sezione: Regia.destinazione(p.sezione)?.nome)
            Filo.condiviso.metti(CosaFilo(chiave: "cer:" + Regia.chiave(titolo), tipo: "risposta", nomi: ["risposta"], titolo: String(titolo.prefix(14)),
                                          riga: riga, detto: "il dato di " + titolo, testo: riga, sezione: Regia.destinazione(p.sezione)?.nome))
            return .fatto("widget FILO: \(titolo) · \(riga)")
        // 14 nov (il signore: «apri il meteo e fissalo» faceva metà): la tab a voce anche per il cervello
        case "tabfissa", "tabsgancia":
            let si = Regia.chiave(p.azione) == "tabfissa"
            let detto = (p.valori["titolo"] ?? p.sezione).trimmingCharacters(in: .whitespacesAndNewlines)
            let filo = Filo.condiviso
            if let nome = filo.nomeArgomento(detto) ?? (detto.isEmpty ? filo.visti.first?.nome : nil), filo.fissa(argomento: nome, si: si) {
                return .fatto("tab: \(nome) " + (si ? "fissata" : "sganciata"))
            }
            if si, let c = filo.questo { filo.fissa(c); return .fatto("tab: fissata «\(c.titolo)»") }
            return .no("nella tab non c'è «\(detto)»: " + filo.argomenti.map(\.nome).joined(separator: ", "))
        case "tabtogli":
            let detto = (p.valori["titolo"] ?? p.sezione).trimmingCharacters(in: .whitespacesAndNewlines)
            if let nome = Filo.condiviso.nomeArgomento(detto), Filo.condiviso.togliArgomento(nome) { Suoni.filoVia(); return .fatto("tab: tolto \(nome)") }
            if detto.isEmpty, Filo.condiviso.togli() { Suoni.filoVia(); return .fatto("tab: tolto l'argomento di cui si parlava") }
            return .no("nella tab non c'è «\(detto)»")
        case "tabvuota":
            let n = Filo.condiviso.togliTutti()
            if n > 0 { Suoni.filoVia() }
            return .fatto(n > 0 ? "tab vuota (tolti \(n) argomenti)" : "la tab era già vuota")
        case "tabnascondi":
            guard !Filo.condiviso.visti.isEmpty else { return .fatto("la tab non si vede già") }
            Suoni.filoVia()
            Filo.condiviso.rimandaVia()
            return .fatto("tab nascosta (si richiama)")
        case "tabrichiama":
            return Filo.condiviso.richiama() ? .fatto("tab richiamata: " + Filo.condiviso.visti.map(\.nome).joined(separator: ", ")) : .no("niente da richiamare")
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
        metteNelFilo(d)                                                  // 14 nov: «apri il meteo e fissalo», «…e mandalo a Bea»
        evento(eraDietro ? "\(d.nome) tornata davanti" : "aperta \(d.nome)")
        if let s = await attendi(d.nome, conAzioni: false) { return .fatto("\(d.nome) davanti: " + Regia.taglia(s, 600)) }
        return .fatto("\(d.nome) davanti")
    }

    /// 13.1: la sezione davanti ha una sua frase per questo? («mostrami Milano» col Satellite, «mostrami tutte» con la Posta): allora
    /// è sua, non del dialogo.
    func davantiCapisce(_ frase: String) -> Bool {
        guard let d = nomeDavanti else { return false }
        let parole = Regia.paroleComando(frase)
        guard !parole.isEmpty else { return false }
        return azioni(di: d).contains { a in !a.conferma && a.frasi.contains { Regia.combaciaDove(parole, $0) != nil } }
    }

    /// 12.0 (16): un tocco su un widget FILO apre (o riporta davanti) la sua sezione.
    func porta(_ nome: String) {
        Task { _ = await apri(nome) }
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
        // 12.0 (16): il dialogo (Insieme.swift): «mostrami…», «leggimi quello di Bea», «rispondile che…», «mandalo anche a lei»,
        // «questa salvala», il sì (o il no) a quello che l'app ha preparato. Nil: non è una sua frase, si va avanti
        if let b = await Insieme.condiviso.prova(fraseDetta) {
            evento("dialogo: \(Regia.taglia(fraseDetta, 60))")
            return b
        }
        // 12.0 (12) · B3: «annulla», «lascia stare», «non mandarlo» con un invio (o un'eliminazione) in attesa del sì
        if inSospeso != nil, Regia.eAnnulla(fraseDetta) {
            inSospeso = nil
            evento("annullato")
            return Battute.annullato()
        }
        // 14 nov (l'iniziativa): «non ora», «basta iniziative», «riprendi le iniziative»
        if let b = Iniziativa.condivisa.comando(fraseDetta) {
            evento("iniziative: \(fraseDetta)")
            return b
        }
        // 14 nov (più passi senza guida): «lascia stare», «annulla», «ferma tutto» con un piano in corso: il piano si ferma lì
        if Piano.condiviso.inCorso, Regia.eAnnulla(fraseDetta) || ["fermati", "basta cosi", "ferma il piano", "annulla il piano"].contains(Regia.paroleComando(fraseDetta).joined(separator: " ")) {
            Piano.condiviso.ferma()
            evento("piano fermato dal signore")
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
        // 14 nov (le mani subito, senza cervello): «scendi», «torna su», «in fondo»; «passa al globo», «vista atomo», «le torri»
        if !davantiCapisce(frase) {
            // 14 nov (il signore: «mandalo non lo dico solo per il messaggio, anche per spostarmi da una sezione all'altra»)
            if let n = Regia.mandaA(parole) {
                let e = await apri(n)
                return e.ok ? Regia.aperturaDi(n) : nil
            }
            if let v = Regia.versoScorri(parole) { return scorriDetto(v) }
            if let d = nomeDavanti, let n = Regia.vistaDetta(parole, sezione: d) {
                let e = await vista(sezione: d, detto: n)
                if e.ok { return e.battuta?() ?? "" }
            }
        }
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
                                                       "fammi sentire un po di musica", "un po di musica", "musica", "metti un po di musica dai",
                                                       "mettimi un po di musica", "mettimi della musica", "mettimi qualcosa", "mettimi la musica",
                                                       "mettimi musica", "mi metti un po di musica", "fammi ascoltare qualcosa", "fammi ascoltare un po di musica"]

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
            Insieme.condiviso.branoInCima()                              // 12.0 (16): «questa salvala» trova il brano
            return Battute.musica("play")
        }
        for schema in Regia.frasiMetti {
            guard let m = Regia.combaciaDove(parole, schema, altro: Regia.nonMusica) else { continue }
            let detto = Regia.originale(frase, da: m.da, a: m.a)
            guard let esito = await LettoreMusica.condiviso.mettiDetto(detto) else { return nil }
            if let e = esito.errore { return e }
            guard let nome = esito.nome else { return nil }
            evento("musica: \(Regia.taglia(nome, 60))")
            Insieme.condiviso.branoInCima()                              // 12.0 (16)
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
    /// (che li fa in fila con la regia).
    /// 14 nov (il signore: «frasi, non comandi… dico quello che mi viene in mente, lui lo fa»): i pezzi possono essere anche le sezioni
    /// aperte («mettilo dietro», «quella di prima», «chiudi il meteo»), lo scorrere («scendi», «torna su»), le viste degli ologrammi
    /// («passa al globo»), la tab e il dialogo coi pronomi («fissalo», «leggimi quello di Bea», «rispondile che…»), i tasti della
    /// musica. Quello che chiede il sì (un messaggio, una chiamata) può essere solo l'ultimo pezzo. JARVIS dice le cose vere (quello
    /// che legge, il messaggio che prepara); se i pezzi sono solo movimenti, la battuta dell'ultimo.
    /// Se l'app non sa fare tutto, i primi pezzi che aprono o chiudono partono subito (si vede subito) e la frase intera va al cervello,
    /// che trova la sezione già davanti.
    private func subitoComposto(_ frase: String) async -> String? {
        let pezzi = Regia.pezzi(frase)
        guard pezzi.count >= 2, pezzi.count <= 5 else { return nil }
        // prima si controlla che si sappiano fare tutti (senza fare niente), con la sezione che sarà davanti a ogni passo
        guard let piano = pianoDi(pezzi) else {
            avviaPrimi(pezzi)
            return nil
        }
        var dette: [String] = []
        var ultima: String?
        for (k, voce) in piano.enumerated() {
            let (battuta, vera) = await fai(voce.tipo, pezzo: voce.pezzo, primo: k == 0)
            guard let battuta else { if k == 0 { return nil } else { continue } }
            if vera, !battuta.isEmpty { dette.append(battuta) }
            if !battuta.isEmpty { ultima = battuta }
        }
        evento("in fila: " + pezzi.joined(separator: " → "))
        return dette.isEmpty ? (ultima ?? "") : dette.joined(separator: " ")
    }

    /// I pezzi riconosciuti in ordine, con la sezione che sarà davanti a ogni passo. Nil: almeno uno non lo sa fare l'app, oppure
    /// chiede il sì e non è l'ultimo (due messaggi in fila aspetterebbero lo stesso sì).
    private func pianoDi(_ pezzi: [String]) -> [(pezzo: String, tipo: Pezzo)]? {
        var davanti = nomeDavanti
        var piano: [(pezzo: String, tipo: Pezzo)] = []
        for (k, p) in pezzi.enumerated() {
            guard let t = riconosci(p, davanti: davanti) else { return nil }
            if case .dialogo = t, Insieme.condiviso.chiedeSi(p), k < pezzi.count - 1 { return nil }
            switch t {
            case .apri(let n), .intenzione(let n): davanti = n
            case .chiudiTutto: davanti = nil
            case .strada(let s, let n):
                switch s {
                case .daParte: davanti = nil
                case .chiudi: if n == davanti { davanti = nil }
                default: davanti = nil                                     // quella di prima, le sezioni aperte: non si sa quale
                }
            default: break
            }
            piano.append((p, t))
        }
        return piano
    }

    /// La frase intera va al cervello, ma i primi pezzi che aprono o chiudono partono subito: lui vede subito la sezione, il cervello
    /// la trova già davanti (aprirla di nuovo non fa niente).
    private func avviaPrimi(_ pezzi: [String]) {
        var davanti = nomeDavanti
        for p in pezzi {
            guard let t = riconosci(p, davanti: davanti) else { return }
            switch t {
            case .apri(let n):
                guard let d = Regia.destinazione(n), nomeDavanti != d.nome else { return }
                vai?(d.strada)
                metteNelFilo(d)
                evento("aperta \(d.nome) (dall'app, subito; il resto della frase al cervello)")
                davanti = d.nome
            case .chiudiTutto:
                vai?(.chiudiTutto)
                evento("chiuse tutte le sezioni (dall'app, subito)")
                davanti = nil
            default:
                return
            }
        }
    }

    /// Fa un pezzo. La battuta (nil: non è andato e la fila si ferma lì) e se è una cosa vera da dire (quello che legge, il
    /// messaggio che prepara) o solo un movimento (aperta, più giù, globo).
    private func fai(_ tipo: Pezzo, pezzo: String, primo: Bool) async -> (String?, Bool) {
        switch tipo {
        case .apri(let n):
            let e = await apri(n)
            let fallita: String? = primo ? nil : (e.battuta?() ?? "")
            guard e.ok else { return (fallita, false) }
            return (Regia.aperturaDi(n), false)
        case .chiudiTutto:
            vai?(.chiudiTutto)
            evento("chiuse tutte le sezioni")
            try? await Task.sleep(for: .milliseconds(350))
            return (Battute.chiusoTutto(), false)
        case .strada(let s, let n):
            let davanti = nomeDavanti
            vai?(s)
            try? await Task.sleep(for: .milliseconds(500))                  // la sezione vola dietro o torna davanti
            switch s {
            case .daParte:
                evento("\(davanti ?? "JARVIS") messa da parte")
                return (davanti.map { Battute.messaDaParte($0) } ?? "", false)
            case .diPrima:
                evento("torna davanti la sezione di prima")
                return (nomeDavanti.map { Battute.diPrima($0) } ?? "", false)
            case .chiudi:
                evento("chiusa \(n ?? "la sezione")")
                return (Battute.una("chiusa", ["Chiusa, Sir.", "Fatto.", "Via.", "Chiusa."]), false)
            default:
                evento("le sezioni aperte si sfogliano")
                return ("", false)
            }
        case .scorri(let verso):
            return (scorriDetto(verso), false)
        case .vista(let nome):
            let e = await vista(sezione: nomeDavanti ?? "", detto: nome)
            let detta: String? = e.ok ? (e.battuta?() ?? "") : (primo ? nil : "")
            return (detta, false)
        case .intenzione(let n):
            return (await intenzione(pezzo, dentro: n), true)
        case .musica:
            return (await musicaDetta(pezzo), false)
        case .tasto(let t):
            guard let a = Regia.tastiMusica.first(where: { $0.nome == t }) else { return (nil, false) }
            let e = await a.esegui([:])
            return (e.battuta?() ?? "", false)
        case .dialogo:
            return (await Insieme.condiviso.prova(pezzo), true)
        }
    }

    private enum Pezzo { case apri(String), chiudiTutto, intenzione(String), musica, strada(Strada, String?), scorri(String), vista(String), tasto(String), dialogo }

    /// 12.0 (12): la frase la farebbe la regia da sola? (Senza fare niente: serve per non chiedere al cervello una risposta
    /// anticipata che sarebbe buttata.)
    func forseLocale(_ frase: String) -> Bool {
        if Insieme.condiviso.sua(frase) { return true }               // 12.0 (16): il dialogo
        let f = FineFrase.ultimaIntenzione(frase)
        if f.isEmpty { return true }
        if inSospeso != nil, Regia.eAnnulla(f) { return true }
        if let p = proposta, Date().timeIntervalSince(p.quando) < 45, Regia.eAssenso(f) { return true }
        let pezzi = FineFrase.comandoComposto(f) ? Regia.pezzi(f) : [f]
        if pezzi.count >= 2 { return pianoDi(pezzi) != nil }
        return riconosci(f, davanti: nomeDavanti) != nil || davantiCapisce(f) || Regia.mandaA(Regia.paroleComando(f)) != nil
    }

    /// Cosa sarebbe un pezzo di frase per l'app, con `davanti` come sezione davanti in quel momento. Nil: non lo sa fare da sola.
    private func riconosci(_ pezzo: String, davanti: String?) -> Pezzo? {
        let parole = Regia.paroleComando(pezzo)
        guard !parole.isEmpty else { return nil }
        let j = parole.joined(separator: " ")
        if ["chiudi tutto", "chiudi tutte le sezioni", "chiudile tutte"].contains(j) { return .chiudiTutto }
        // 14 nov: le sezioni aperte, come da sole («mettilo dietro», «quella di prima», «cosa ho aperto»)
        if let c = ComandoVocale.navigazione(parole) {
            switch c {
            case .daParte: return .strada(.daParte, nil)
            case .sezionePrima: return .strada(.diPrima, nil)
            case .sezioniAperte: return .strada(.sfoglia, nil)
            case .chiudiSezioni: return .chiudiTutto
            default: break
            }
        }
        if let n = chiudiDetto(parole, davanti: davanti) { return .strada(.chiudi(n), n) }
        for schema in ["apri *", "aprimi *", "riapri *", "vai alla *", "vai al *", "vai in *", "portami alla *", "portami al *", "porta davanti *",
                       "riportami il *", "riportami la *", "riportami *"] {   // 12.0 (16): «mostrami» è il widget FILO
            if let v = Regia.combacia(parole, schema, altro: []), let d = Regia.destinazione(v), !d.dopoLaVoce { return .apri(d.nome) }
        }
        if let n = Regia.mandaA(parole), Regia.destinazione(n)?.dopoLaVoce == false { return .apri(n) }   // 14 nov: «e mandalo a Foto»
        if let v = Regia.versoScorri(parole) { return .scorri(v) }                         // 14 nov: le mani, subito
        if let d = davanti, let n = Regia.vistaDetta(parole, sezione: d) { return .vista(n) }   // 14 nov: le viste degli ologrammi
        if Insieme.condiviso.sua(pezzo) { return .dialogo }                                 // 14 nov: la tab e il dialogo coi pronomi
        for i in Regia.intenzioni {
            let schemi = i.frasi + (davanti == i.sezione ? i.frasiDentro : [])
            if schemi.contains(where: { Regia.combacia(parole, $0) != nil }) { return .intenzione(i.sezione) }
        }
        if Regia.musicaGenerica.contains(j) || Regia.frasiMetti.contains(where: { Regia.combacia(parole, $0, altro: Regia.nonMusica) != nil }) {
            return .musica
        }
        if LettoreMusica.condiviso.voce != nil, let t = Regia.tastiMusica.first(where: { a in a.frasi.contains { Regia.combacia(parole, $0) != nil } }) {
            return .tasto(t.nome)
        }
        return nil
    }

    /// «Chiudi il meteo», «chiudila», «chiudi questa»: quale sezione (aperta). Nil: non è una chiusura di una sezione aperta.
    private func chiudiDetto(_ parole: [String], davanti: String?) -> String? {
        guard let primo = parole.first else { return nil }
        if ["chiudila", "chiudilo"].contains(primo), parole.count == 1 { return davanti }
        guard ["chiudi", "chiudimi"].contains(primo), parole.count >= 2, parole.count <= 4 else { return nil }
        let resto = parole.dropFirst().filter { !["il", "lo", "la", "l", "i", "gli", "le", "sezione", "anche"].contains($0) }
        if resto == ["questa"] || resto == ["questo"] { return davanti }
        guard resto.count == 1, let w = resto.first, let n = ComandoVocale.nomeSezione(w) ?? Regia.destinazione(w)?.nome else { return nil }
        return pila?.voci.contains(where: { $0.sezione.nome == n }) == true || n == davanti ? n : nil
    }

    /// 14 nov (il signore: «fai questo e mandalo a LiDAR, mandalo a Foto: mandalo non lo dico solo per il messaggio, anche per
    /// spostarmi da una sezione all'altra»): «mandalo a / portalo in / passalo su» + una sezione è andare in quella sezione, se il nome
    /// non è di una persona in rubrica (Bea resta Bea: un messaggio a lei). Le storpiature valgono come negli altri comandi («leader»
    /// è LiDAR). Il nome della sezione; nil: non è questo.
    static func mandaA(_ parole: [String]) -> String? {
        let verbi: Set<String> = ["mandalo", "mandala", "mandali", "mandale", "portalo", "portala", "portali", "portale", "passalo", "passala",
                                  "passali", "passale"]
        guard parole.count >= 3, parole.count <= 7, let v = parole.first, verbi.contains(v) else { return nil }
        var resto = Array(parole.dropFirst())
        if resto.first == "anche" { resto.removeFirst() }
        let verso: Set<String> = ["a", "al", "alla", "allo", "all", "ai", "alle", "in", "nel", "nella", "nello", "su", "sul", "sulla", "sullo", "dentro"]
        guard let a = resto.first, verso.contains(a) else { return nil }
        resto.removeFirst()
        while let f = resto.first, ["il", "lo", "la", "l", "i", "gli", "le", "sezione"].contains(f) { resto.removeFirst() }
        guard !resto.isEmpty, resto.count <= 2 else { return nil }
        let detto = Pronunce.sistema(["apri"] + resto).dropFirst().joined(separator: " ")
        // «mandalo su WhatsApp», «mandalo per mail»: è il canale del messaggio, non una sezione (Messaggi ed Email restano del dialogo)
        guard let d = destinazione(detto), !["Bea", "Messaggi", "Email"].contains(d.nome), !Rubrica.chiamatoCosi(detto) else { return nil }
        return d.nome
    }

    // MARK: 14 nov · le mani subito: scorrere e le viste degli ologrammi

    /// Le frasi dello scorrere (già senza cortesie): verso giu, su, cima, fondo. Nil: non è uno scorrere.
    static func versoScorri(_ parole: [String]) -> String? {
        let j = parole.joined(separator: " ")
        let giu: Set<String> = ["scorri", "scorri giu", "scorri in giu", "scendi", "scendi giu", "scendi un po", "scendi ancora", "vai giu", "piu giu",
                                "un po piu giu", "ancora giu", "ancora un po giu", "giu", "sotto", "vai sotto", "fammi vedere sotto", "scorri ancora",
                                "pagina giu", "scorri la pagina", "fammi vedere il resto", "vai avanti con la pagina"]
        let su: Set<String> = ["torna su", "su", "sali", "risali", "vai su", "piu su", "un po piu su", "scorri su", "scorri in su", "sopra",
                               "torna sopra", "pagina su", "sali un po", "torna un po su"]
        // («torna all'inizio» no: da sola chiude la sezione e torna a JARVIS, ComandoVocale)
        let cima: Set<String> = ["torna in cima", "in cima", "vai in cima", "su in cima", "all inizio", "dall inizio", "vai all inizio", "inizio",
                                 "torna su in cima", "riportami in cima"]
        let fondo: Set<String> = ["vai in fondo", "in fondo", "fino in fondo", "alla fine", "vai alla fine", "fino alla fine", "fondo", "giu in fondo",
                                  "scendi in fondo", "scorri fino in fondo", "vai giu in fondo", "scendi fino in fondo"]
        if giu.contains(j) { return "giu" }
        if su.contains(j) { return "su" }
        if cima.contains(j) { return "cima" }
        if fondo.contains(j) { return "fondo" }
        return nil
    }

    /// Scorre la pagina davanti (ManiJarvis) e restituisce la battuta.
    private func scorriDetto(_ verso: String) -> String {
        guard let dove = ManiJarvis.scorriSubito(verso), dove != "tutta visibile" else {      // niente da scorrere, o si vede già tutta
            return Battute.una("scorri.niente", ["Qui c'è tutto, Sir.", "Non c'è altro da vedere, Sir."])
        }
        evento("pagina \(dove)")
        return Battute.scorri(verso, dove: dove)
    }

    /// Le viste degli ologrammi di una sezione: quelle che si vedono adesso (la sezione si è presentata) o, da chiusa, quelle che
    /// avrà (le stesse di SezioneOlo), così «apri il meteo e passa al globo» si riconosce prima di aprire.
    private func nomiViste(_ sezione: String) -> [String]? {
        if let v = viste(di: sezione) { return v.nomi }
        return Regia.sezioneOlo(sezione)?.nomi
    }

    /// La sezione degli ologrammi di una sezione della regia («Email» → .posta, «Ricordi» → .traccia).
    static func sezioneOlo(_ nome: String) -> SezioneOlo? {
        switch Regia.chiave(Regia.destinazione(nome)?.nome ?? nome) {
        case "diario": return .diario
        case "sonno": return .sonno
        case "briefing": return .briefing
        case "spesa": return .spesa
        case "serata": return .serata
        case "bea": return .bea
        case "cuore": return .cuore
        case "telefono": return .telefono
        case "meteo": return .meteo
        case "edith": return .edith
        case "email": return .posta
        case "messaggi": return .messaggi
        case "confidente": return .confidente
        case "interprete": return .interprete
        case "ricordi": return .traccia
        case "vitals": return .vitals
        case "github": return .github
        case "supabase": return .supabase
        case "archivio": return .archivio
        case "costi": return .costi
        case "musica": return .musica
        default: return nil
        }
    }

    /// Il nome della sezione della regia di una prova degli ologrammi (.posta → «Email», .traccia → «Ricordi»).
    static func nomeDi(_ s: SezioneOlo) -> String {
        switch s {
        case .diario: return "Diario"
        case .sonno: return "Sonno"
        case .briefing: return "Briefing"
        case .spesa: return "Spesa"
        case .serata: return "Serata"
        case .bea: return "Bea"
        case .cuore: return "Cuore"
        case .telefono: return "Telefono"
        case .meteo: return "Meteo"
        case .edith: return "EDITH"
        case .posta: return "Email"
        case .messaggi: return "Messaggi"
        case .confidente: return "Confidente"
        case .interprete: return "Interprete"
        case .traccia: return "Ricordi"
        case .vitals: return "Vitals"
        case .github: return "GitHub"
        case .supabase: return "Supabase"
        case .archivio: return "Archivio"
        case .costi: return "Costi"
        case .musica: return "Musica"
        }
    }

    /// «Passa al globo», «vista atomo», «fammi le torri», «il vento»: il nome della vista detta (com'è scritto sulla chip). Nil: non
    /// è una vista di quella sezione.
    static func vistaDetta(_ parole: [String], sezione: String) -> String? {
        guard let nomi = condivisa.nomiViste(sezione), !nomi.isEmpty else { return nil }
        let attacchi: [[String]] = [["vista"], ["passa", "a"], ["passa", "al"], ["passa", "alla"], ["passa", "allo"], ["passa", "all"], ["passa", "ai"],
                                    ["passa", "alle"], ["fammi", "vedere"], ["mostrami"], ["fammi"], ["torna", "al"], ["torna", "alla"], ["torna", "allo"],
                                    ["torna", "all"], ["metti", "la", "vista"], ["vista", "a"], ["cambia", "in"], []]
        for a in attacchi where parole.count > a.count && Array(parole.prefix(a.count)) == a {
            var resto = Array(parole.dropFirst(a.count))
            while let f = resto.first, ["il", "lo", "la", "l", "i", "gli", "le", "vista", "a", "ad"].contains(f) { resto.removeFirst() }
            guard !resto.isEmpty, resto.count <= 3 else { continue }
            let k = Regia.chiave(resto.joined())
            if let n = nomi.first(where: { Regia.chiave($0) == k }) { return n }
        }
        return nil
    }

    /// Cambia la vista dell'ologramma della sezione (come la chip toccata col dito). Se la sezione si è appena aperta e le sue viste
    /// non ci sono ancora, aspetta un attimo; se non arrivano, la scelta resta e la sezione la usa appena compare.
    private func vista(sezione: String, detto: String) async -> EsitoRegia {
        let parole = FineFrase.paroleNude(detto)
        guard let nome = Regia.vistaDetta(parole, sezione: sezione) ?? Regia.vistaDetta(["vista"] + parole, sezione: sezione) else {
            return .no("viste di \(sezione): " + (nomiViste(sezione) ?? []).joined(separator: ", "))
        }
        for _ in 0..<30 where viste(di: sezione) == nil { try? await Task.sleep(for: .milliseconds(50)) }
        if let v = viste(di: sezione), let i = v.nomi.firstIndex(of: nome) {
            if v.scelta() == i { return .fatto("\(sezione): vista \(nome) (era già questa)", battuta: { Battute.vista(nome, gia: true) }) }
            v.scegli(i)
        } else if let s = Regia.sezioneOlo(sezione), let i = s.nomi.firstIndex(of: nome) {
            UserDefaults.standard.set(i, forKey: s.chiave)
            PonteTelefono.condiviso.invia()                               // il polso segue la scelta
        } else {
            return .no("\(sezione) non ha la vista \(nome)")
        }
        evento("\(sezione): vista \(nome)")
        return .fatto("\(sezione): vista \(nome)", battuta: { Battute.vista(nome, gia: false) })
    }

    /// Le viste degli ologrammi che si vedono (ProveOloVista si presenta): sezione, nomi delle chip, la scelta e come cambiarla.
    private struct Viste {
        let sezione: String
        let nomi: [String]
        let scelta: () -> Int
        let scegli: (Int) -> Void
    }
    private var tutteLeViste: [UUID: Viste] = [:]

    func mettiViste(_ chiave: UUID, sezione: String, nomi: [String], scelta: @escaping () -> Int, scegli: @escaping (Int) -> Void) {
        tutteLeViste[chiave] = Viste(sezione: sezione, nomi: nomi, scelta: scelta, scegli: scegli)
    }

    func togliViste(_ chiave: UUID) { tutteLeViste[chiave] = nil }

    private func viste(di nome: String) -> Viste? {
        let k = Regia.chiave(Regia.destinazione(nome)?.nome ?? nome)
        return tutteLeViste.values.first { Regia.chiave(Regia.destinazione($0.sezione)?.nome ?? $0.sezione) == k }
    }

    /// L'azione «vista» della sezione, per il cervello e per le frasi brevi (le stesse di `vistaDetta`).
    private func azioneVista(_ nome: String) -> AzioneRegia? {
        guard let nomi = nomiViste(nome), !nomi.isEmpty else { return nil }
        let ora = viste(di: nome).map { v in v.nomi.indices.contains(v.scelta()) ? v.nomi[v.scelta()] : "" } ?? ""
        return AzioneRegia("vista", "cambia la vista dell'ologramma (\(nomi.joined(separator: ", "))\(ora.isEmpty ? "" : "; ora \(ora)"))", valore: "nome") { [weak self] v in
            guard let self else { return .no("regia non pronta") }
            return await self.vista(sezione: nome, detto: v["nome"] ?? "")
        }
    }

    /// Una sezione appena aperta entra nel filo del discorso: dopo «apri il meteo», «fissalo» e «mandalo a Bea» sanno di cosa si parla.
    private func metteNelFilo(_ d: Destinazione) {
        Filo.condiviso.metti(CosaFilo(chiave: "sez:" + d.nome, tipo: "sezione", nomi: Array(d.chiavi.prefix(3)) + ["sezione"], titolo: d.nome,
                                      riga: statoDi(d.nome) ?? "", detto: d.nome, sezione: d.nome))
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
                // si taglia solo se subito dopo il legame c'è un verbo di comando (14 nov: guardato direttamente, non più con
                // `comandoComposto` sul resto della frase, che vedeva anche le virgole più avanti)
                if j < parole.count, FineFrase.verbiComposti.contains(Regia.chiave(parole[j])) {
                    pezzi.append([])
                    i = j
                    continue
                }
            }
            pezzi[pezzi.count - 1].append(parole[i])
            // 14 nov: anche alla virgola seguita da un verbo («apri il meteo, fissalo»)
            if parole[i].hasSuffix(","), i + 1 < parole.count, FineFrase.verbiComposti.contains(Regia.chiave(parole[i + 1])) { pezzi.append([]) }
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
    static let conLaRegia: Set<String> = ["Social", "Spesa", "Email", "Meteo", "Briefing", "Musica", "Messaggi", "Telefono", "Bea", "Diario", "Sonno", "Cuore", "Shazam", "Foto", "Serata", "Ricordi", "Satellite", "GitHub", "Supabase", "Archivio", "Costi", "EDITH", "Vitals"]

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
