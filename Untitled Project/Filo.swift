#if os(iOS)
import Foundation
import Combine
import CoreGraphics      // sottoIcone (CGFloat)

// MARK: - 12.0 (16) · IL FILO DEL DISCORSO e i WIDGET FILO
// Il signore (13 nov sera): «JARVIS deve sempre sapere cosa sono "questo", "quello", "la", "quella di prima", anche dopo cinque
// frasi e cambiando sezione… messo sotto al dialogo, non come comando». Ogni cosa che JARVIS mostra, dice o fa entra nel filo col
// suo genere e numero (il meteo, la canzone, il messaggio di Bea, Bea): così «mandalo», «salvala», «rispondile», «quello di prima»
// trovano la cosa giusta. Il filo lo usano l'app (i comandi rapidi di Insieme) e il cervello (la riga FILO dentro [Schermo]).
// E alle 20:58: «mostrami… si apre FILO che mostra quello che stiamo facendo, senza dover aprire le sezioni… sono come dei widget».
// FILO (una scheda sola: «Mostrami…», «Fammi vedere…», «Fissalo») sta qui; la disegna FiloWidget.swift. Come il mockup.

/// Una cosa del discorso: quello che JARVIS ha mostrato, detto o fatto.
struct CosaFilo {
    /// Unica: «msg:<id>», «p:Bea», «brano:<id>», «post», «risposta»…
    var chiave: String
    /// messaggio, persona, brano, risposta, post, impegno, sezione, lista
    var tipo: String
    /// I nomi con cui il signore la chiama (il loro genere è in `Filo.generi`): «meteo», «previsione», «canzone»…
    var nomi: [String]
    var titolo: String
    var riga: String
    /// Come la dice JARVIS: «il messaggio di Bea», «Bea», «il meteo di stasera».
    var detto: String
    /// Di chi è (il messaggio di Bea) o chi è (la persona).
    var persona: String? = nil
    /// Per le persone: "f" o "m".
    var genere: Character? = nil
    /// Da leggere a voce.
    var testo: String? = nil
    /// Pronto da mandare a qualcuno (nil: lo scrive il cervello).
    var daMandare: String? = nil
    /// Il numero di chi l'ha scritto (un messaggio arrivato): la risposta va lì.
    var numero: String? = nil
    /// Dove si riapre (il tocco sul widget).
    var sezione: String? = nil
    var quando = Date()
}

/// Una riga di FILO: un dato mostrato («Oggi nuvoloso · 14°», «11:30 dentista · 18:00 palestra»), con la sezione che si apre al tocco.
struct RigaFilo: Identifiable, Equatable {
    let id: String
    /// Il titolo del dato («A Bea», «Da Bea», «Post»): si legge davanti alla riga quando non è il nome dell'argomento.
    var titolo: String
    var riga: String
    var sezione: String?
    var alle: Date
    /// Aspetta una risposta (il messaggio che parte col sì): finché c'è, il suo argomento non sparisce.
    var resta = false
    /// 14 nov: un simbolo davanti alla riga (la batteria): le informazioni dell'iniziativa si vedono, non solo si sentono.
    var icona: String? = nil
}

/// Un argomento di FILO (METEO, AGENDA, MESSAGGI…): la sua testata, le sue righe, fissato o no.
struct ArgomentoFilo: Identifiable, Equatable {
    var id: String { nome }
    let nome: String
    var righe: [RigaFilo]
    /// «Fissalo»: resta finché lui non lo chiude.
    var fisso = false
    /// Una notifica («mostrami…»): quando sparisce. Nil: resta.
    var scade: Date?
    /// Sparita: non si vede, ma torna con lo swipe verso sinistra dal bordo destro, nella fascia di FILO.
    var nascosto = false
    /// Appena arrivato o aggiornato (si accende entrando).
    var giro = 0
    /// Quando è stato mostrato l'ultima volta: si accende solo se è appena successo (non quando FILO viene richiamato).
    var aggiornato = Date()
    /// 13.1: quando è sparito (scaduto o mandato via). Se non è fissato, dopo mezz'ora non si richiama più (come il filo del
    /// discorso): il dato è vecchio.
    var nascostoAlle: Date?
    /// 14 nov: il nome mostrato nella testata quando è diverso dal nome dell'argomento («PIANO · SERATA DI SABATO»).
    var etichetta: String?
}

@MainActor
final class Filo: ObservableObject {
    static let condiviso = Filo()

    private var cose: [CosaFilo] = []
    /// Gli argomenti di FILO, il più recente per primo (anche quelli spariti, da richiamare).
    @Published private(set) var argomenti: [ArgomentoFilo] = []
    /// Richiamato con lo swipe dal bordo destro: resta finché lui non lo rimanda via.
    @Published private(set) var richiamato = false
    /// 13.8 · richiamata col dito senza niente da riportare: la tab si apre lo stesso, vuota, con «NESSUNA NOTIFICA» (il
    /// signore, 22 nov 07:28: «la tab alta non si può richiamare col dito anche se vuota»), finché lui non la manda via.
    @Published private(set) var vuota = false
    /// Il dito è su FILO (scorre, tocca): le notifiche aspettano.
    private var tocco = false
    private var fonti: Set<String> = []
    private var controllo: Task<Void, Never>?
    /// Il menu SISTEMI o la tendina PROTOCOLLI sono aperti (FILO si è fatto da parte): i tocchi lì non sono per FILO.
    var daParte = false
    /// Dove finiscono le icone di sistema in alto (in punti, sullo schermo): FILO sta subito sotto.
    @Published var sottoIcone: CGFloat = 0
    /// Quello che si vede adesso.
    var visti: [ArgomentoFilo] { argomenti.filter { !$0.nascosto } }
    /// 13.1 (il signore, 14 nov: «se copre una sezione aperta usa la trasparenza dinamica della navigazione olografica»): FILO è
    /// a fuoco quando arriva, si aggiorna, viene richiamato o toccato; 2,8 s dopo (o appena il dito tocca fuori, sulla sezione)
    /// va in secondo piano e sopra una sezione diventa vetro trasparente (come le pagine dietro della PILA). Toccato torna a fuoco.
    /// 14 nov (scelta del signore, 09:08): in secondo piano la tab è COMPATTA, una riga per argomento (il nome e il dato); toccata
    /// torna intera (il primo tocco la riapre e basta, come il Dock). Come il mockup.
    @Published private(set) var fuoco = true
    /// Quando il dito l'ha appena svegliata (era compatta): quel tocco la riapre e basta, non apre e non chiude niente.
    private var svegliataAlle: Date?
    /// 13.9 (22) (il signore, 28 nov 07:35: «quando è grande anche quell'altra rimane grande»): aperta grande da lui (richiamata dal
    /// bordo, il tasto «apri», riaperta col dito) resta grande, come la tab bassa: si stringe solo col tasto «riduci» o col dito fuori.
    /// Arrivata da sola (una notifica) si stringe dopo 2,8 s come sempre.
    private var grandeDaLui = false
    /// 21 nov: quando la pressione lunga ha appena fissato (o sganciato) un argomento: il dito che si alza non apre e non chiude niente.
    private var fissatoAlle: Date?
    /// 14 nov (scelta del signore: «si accende la riga che dice»): la frase che JARVIS sta dicendo adesso, piegata (minuscole, senza
    /// accenti), da quando e per quanto (stimato): nella tab si accende la riga di cui sta parlando.
    struct VoceOra: Equatable {
        let testo: String
        let inizio: Date
        let durata: TimeInterval
    }
    @Published private(set) var voceOra: VoceOra?
    private var riposa: Task<Void, Never>?
    /// Dove sta la scheda sullo schermo (coordinate della finestra): un tocco fuori la manda in secondo piano.
    var rettScheda: CGRect = .zero
    /// 13.7: dove stanno i tre tasti (chiudi, riduci, apri): il dito lì non sveglia la tab (se no da piccola si aprirebbe sotto il
    /// dito e il tasto non arriverebbe), come il mockup.
    var rettTasti: CGRect = .zero
    /// 13.9 (22): dove sta la fascia invisibile del bordo destro che la richiama (zero quando la tab c'è): il dito che parte da lì
    /// per richiamare la tab alta non è «fuori» per la tab bassa, che resta grande.
    var rettFascia: CGRect = .zero
    /// 13.7: l'argomento che sta uscendo a sinistra (chiuso con lo swipe): la sua uscita va verso sinistra invece che a destra.
    @Published var esceASinistra: String?
    private var pulizia: Task<Void, Never>?

    // MARK: Il filo

    /// Il filo vale mezz'ora dall'ultima volta che se n'è parlato.
    private var vive: [CosaFilo] { cose.filter { Date().timeIntervalSince($0.quando) < 1800 } }

    /// Una cosa nuova nel discorso (o di nuovo in cima, se c'era già).
    @discardableResult
    func metti(_ c: CosaFilo) -> CosaFilo {
        var c = c
        c.quando = Date()
        cose.removeAll { $0.chiave == c.chiave }
        cose.insert(c, at: 0)
        if cose.count > 20 { cose.removeLast(cose.count - 20) }
        return c
    }

    /// Una cosa dello stesso tipo prende il posto della vecchia (il brano cambiato), oppure entra in cima (`inCima`) o in fondo.
    func sostituisci(_ c: CosaFilo, inCima: Bool) {
        if inCima { metti(c); return }
        if let i = cose.firstIndex(where: { $0.tipo == c.tipo }) {
            guard cose[i].chiave != c.chiave else { return }
            var nuova = c
            nuova.quando = cose[i].quando
            cose[i] = nuova
            return
        }
        var nuova = c
        nuova.quando = Date()
        if cose.count >= 20 { cose.removeLast() }                    // in fondo ci sono le più vecchie
        cose.append(nuova)
    }

    /// Una persona nel discorso: «lei», «lui», «rispondile», «chiamalo».
    func persona(_ nome: String) {
        metti(CosaFilo(chiave: "p:" + Regia.chiave(nome), tipo: "persona", nomi: [], titolo: nome, riga: "", detto: Filo.detto(nome),
                       persona: nome, genere: Filo.genere(di: nome)))
    }

    /// «Questo»: l'ultima cosa (non una persona) di cui si è parlato.
    var questo: CosaFilo? { vive.first { $0.tipo != "persona" } }

    /// La cosa che corrisponde: per nome («la canzone»), per genere e numero («la», «quello»), di qualcuno («quello di Bea»),
    /// «di prima» (la penultima che corrisponde).
    func cosa(genere g: Character? = nil, plurale p: Bool = false, nome: String? = nil, di: String? = nil, prima: Bool = false,
              tipi: Set<String>? = nil) -> CosaFilo? {
        let ok = vive.filter { r in
            guard r.tipo != "persona" else { return false }
            if let tipi, !tipi.contains(r.tipo) { return false }
            if let di, Regia.chiave(r.persona ?? "") != Regia.chiave(di) { return false }
            if let nome { return Filo.ha(r, nome) }
            guard let g else { return true }
            return r.nomi.contains { n in let x = Filo.gn(n); return x.genere == g && x.plurale == p }
        }
        return prima && ok.count > 1 ? ok[1] : ok.first
    }

    /// Chi: l'ultima persona del discorso (del genere detto: «-le», «lei» → f; «-gli», «lui» → m).
    func chi(genere g: Character? = nil) -> String? {
        if let p = vive.first(where: { $0.tipo == "persona" && (g == nil || $0.genere == g) }) { return p.persona }
        return vive.first { r in r.persona.map { g == nil || Filo.genere(di: $0) == g } ?? false }?.persona
    }

    /// La riga per il cervello (dentro [Schermo]): il filo dal più recente, coi generi.
    func perCervello() -> String? {
        let v = Array(vive.prefix(8))
        guard !v.isEmpty else { return nil }
        let righe = v.enumerated().map { i, r -> String in
            if r.tipo == "persona" { return "\(i + 1). \(r.detto) (persona, \(r.genere == "f" ? "lei" : "lui"))" }
            let nomi = r.nomi.map { "\($0) \(Filo.generi[$0] ?? "m")" }.joined(separator: ", ")
            return "\(i + 1). \(r.detto) [\(nomi)]" + (r.riga.isEmpty ? "" : " — " + String(Filo.inLinea(r.riga).prefix(140)))
        }
        var riga = "FILO (le cose di cui si parla, dalla più recente: «questo», «lo», «la», «quello di prima», «lei», «gli», «le» si risolvono qui guardando genere e numero; se è davvero ambiguo chiedi in quattro parole): " + righe.joined(separator: " · ")
        if !visti.isEmpty {
            let schede: [String] = visti.map { (a: ArgomentoFilo) -> String in
                let dati: String = a.righe.map { Filo.inLinea(Filo.testo(di: $0, in: a.nome)) }.joined(separator: " / ")
                return a.nome + (a.fisso ? " (fissato)" : "") + ": " + dati
            }
            riga += " ‖ FILO sullo schermo: " + schede.joined(separator: "; ")
        }
        return riga
    }

    /// Una risposta del cervello entra nel filo: «la risposta», coi nomi delle cose di cui parla (dalla domanda e dagli strumenti
    /// usati: il meteo, l'agenda, la ricerca…), pronta da fissare. Da mandare la riscrive il cervello (parla a «Sir»).
    func risposta(_ testo: String, azioni: [String], domanda: String?) {
        let t = TagVoce.togli(testo).trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 12 else { return }
        let q = Set(FineFrase.paroleNude((domanda ?? "") + " " + azioni.joined(separator: " ")))
        var nomi = ["risposta"], titolo = "Risposta"
        if !q.isDisjoint(with: ["meteo", "tempo", "piove", "pioggia", "pioverà", "gradi", "temperatura", "ombrello", "vento", "neve"]) {
            nomi = ["meteo", "tempo", "previsione", "risposta"]; titolo = "Meteo"
        } else if !q.isDisjoint(with: ["agenda", "calendario", "impegni", "impegno", "appuntamento", "appuntamenti", "riunione", "calendario_leggi"]) {
            nomi = ["impegno", "appuntamento", "risposta"]; titolo = "Agenda"
        } else if !q.isDisjoint(with: ["notizie", "notizia", "cerca", "cerca_web", "web", "ricerca"]) {
            nomi = ["notizia", "risultato", "risposta"]; titolo = "Notizia"
        }
        metti(CosaFilo(chiave: "risposta", tipo: "risposta", nomi: nomi, titolo: titolo, riga: Filo.primaFrase(t),
                       detto: titolo == "Meteo" ? "il meteo appena detto" : "la risposta di poco fa", testo: t))
    }

    // MARK: FILO, una scheda sola (13 nov, 22:33–23:02)
    // Il signore: «come FILO ma tutto raggruppato in un'unica tab», sotto le icone di sistema in alto a destra. «Mostrami…» è una
    // notifica: sparisce da sola in 2,8 s; «fissalo» la tiene; toccato resta finché lui non ha finito di scorrere. Ogni argomento
    // ha la sua testata e la X che chiude solo quello. Le cose sparite tornano con lo swipe dal bordo destro, nella fascia di FILO (13.1); lo swipe a destra su
    // FILO le rimanda via. Scelta SCORRI (23:02): gli argomenti uno sotto l'altro. Come il mockup (v1216/q16-9.js).

    static let durataNotifica: TimeInterval = 2.8

    /// 20 nov (il signore: «OK», l'elenco che sparisce): una notifica resta in base a quante voci ha l'argomento. Un dato solo
    /// 2,8 s come sempre; ogni voce in più di un elenco (o impegno dell'agenda) altri 0,9 s, fino a 20 s (20 voci ≈ 19,9 s; 23 nov: prima 14 s, con 12 voci al massimo).
    static func durata(_ a: ArgomentoFilo) -> TimeInterval {
        guard a.nome != "Piano" else { return durataNotifica }           // il piano ha le sue regole (resta mentre lavora, finito 5 s)
        let n: Int = a.righe.reduce(0) { (somma: Int, r: RigaFilo) -> Int in
            let voci: Int = a.nome == "Agenda" ? r.riga.components(separatedBy: " · ").count : Filo.voci(r.riga).count
            return somma + max(1, voci)
        }
        // 21 nov (il signore: «poter rileggere lì tutta la risposta»): un testo lungo resta il tempo di leggerlo, 50 ms a lettera
        // oltre le prime 60 (come il mockup), sempre fino a 20 s (23 nov); toccata o fissata resta finché lui vuole
        let lettere: Int = a.righe.reduce(0) { (somma: Int, r: RigaFilo) -> Int in somma + r.riga.count }
        let elenco: TimeInterval = durataNotifica + 0.9 * Double(max(0, n - 1))
        let lettura: TimeInterval = durataNotifica + 0.05 * Double(max(0, lettere - 60))
        return min(max(elenco, lettura), 20)                              // 23 nov: fino a 20 s (le 20 voci), come il mockup
    }

    /// 21 nov (il signore: «la frase finisce coi puntini anziché poter rileggere lì tutta la risposta»): di una risposta di JARVIS
    /// la tab mostra tutto il testo, non solo la prima frase; le altre cose la loro riga (o come si chiamano).
    static func rigaIntera(_ c: CosaFilo) -> String {
        if c.tipo == "risposta", let t = c.testo, !t.isEmpty { return t }
        return c.riga.isEmpty ? c.detto : c.riga
    }

    /// Il nome dell'argomento: la sezione da cui viene (il briefing è l'agenda), o il titolo.
    static func argomento(sezione: String?, titolo: String) -> String {
        switch sezione {
        case "Briefing"?: return "Agenda"
        case "Social"?: return "Instagram"
        case let s?: return s
        case nil: return titolo.isEmpty ? "Filo" : titolo
        }
    }

    /// Mostra (o aggiorna) un dato nel suo argomento, che passa davanti. `resta`: non è una notifica (il messaggio che aspetta il
    /// sì); `dura`: notifica di un'altra durata; `fisso`: «fissalo».
    func mostra(_ chiave: String, titolo: String, riga: String, sezione: String?, dura: TimeInterval? = nil, suono: Bool = true,
                resta: Bool = false, fisso: Bool = false, icona: String? = nil) {
        let nome = Filo.argomento(sezione: sezione, titolo: titolo)
        let appare = visti.isEmpty && !vuota                              // 14 nov (il signore): ogni volta che la tab compare, il suo suono
        let nuova = RigaFilo(id: chiave, titolo: titolo, riga: riga, sezione: sezione, alle: Date(), resta: resta, icona: icona)
        var a: ArgomentoFilo
        if let i = argomenti.firstIndex(where: { $0.nome == nome }) {
            a = argomenti.remove(at: i)
        } else if let i = argomenti.firstIndex(where: { $0.righe.contains { $0.id == chiave } }) {
            a = argomenti.remove(at: i)                                   // lo stesso dato era sotto un altro nome: si sposta
            a.righe.removeAll { $0.id == chiave }
            if !a.righe.isEmpty { argomenti.insert(a, at: i) }
            a = ArgomentoFilo(nome: nome, righe: [])
        } else {
            a = ArgomentoFilo(nome: nome, righe: [])
        }
        a.righe.removeAll { $0.id == chiave }
        a.righe.insert(nuova, at: 0)
        if a.righe.count > 4 { a.righe.removeLast(a.righe.count - 4) }
        if fisso { a.fisso = true }
        // una notifica scade; un argomento fissato, o con dentro qualcosa che aspetta il sì, resta
        a.scade = a.fisso || a.righe.contains(where: \.resta) ? nil : Date().addingTimeInterval(max(dura ?? Filo.durataNotifica, Filo.durata(a)))
        a.nascosto = false
        a.nascostoAlle = nil
        a.giro += 1
        a.aggiornato = Date()
        for k in argomenti.indices where argomenti[k].fisso {                                    // i fissati tornano con lui
            argomenti[k].nascosto = false
            argomenti[k].nascostoAlle = nil
        }
        argomenti.insert(a, at: 0)
        if argomenti.count > 6 { argomenti.removeLast(argomenti.count - 6) }
        // 14 nov (il signore: «le cose non spariscono dopo 2,8 secondi»): richiamato dal bordo restava fermo per sempre, anche coi
        // dati nuovi; un dato nuovo riporta le regole di sempre (notifica 2,8 s, fissato resta)
        richiamato = false
        vuota = false
        programma()
        svegli()
        if suono || appare { Suoni.filo() }
    }

    /// 14 nov · il PIANO in FILO (Piano.swift): un argomento suo, i passi nel loro ordine (fino a 8). Mentre il cervello lavora resta e
    /// torna davanti a ogni passo; finito, è una notifica di 5 secondi (poi si richiama come gli altri).
    func mostraPiano(titolo: String, righe: [RigaFilo], finito: Bool) {
        let nome = "Piano"
        let appare = visti.isEmpty && !vuota
        var a: ArgomentoFilo
        if let i = argomenti.firstIndex(where: { $0.nome == nome }) { a = argomenti.remove(at: i) } else { a = ArgomentoFilo(nome: nome, righe: []) }
        a.righe = Array(righe.prefix(8))
        a.etichetta = "\u{00A0}"                                          // 14 nov (il signore): nessuna scritta, solo i passi
        a.scade = finito ? Date().addingTimeInterval(5) : nil
        a.nascosto = false
        a.nascostoAlle = nil
        // 14 nov (il signore: «non voglio né che saltelli né che si accenda, solo che si spunti»): un passo fatto cambia solo il suo
        // segno (e il tocco di Aptica); niente lampo. Si accende solo il piano appena arrivato (ArgomentoFilo nuovo: aggiornato adesso)
        argomenti.insert(a, at: 0)
        if argomenti.count > 6 { argomenti.removeLast(argomenti.count - 6) }
        richiamato = false
        vuota = false
        programma()
        svegli()
        if appare { Suoni.filo() }
    }

    /// «Fissalo»: l'argomento di quella cosa resta (se c'è già non si duplica).
    func fissa(_ c: CosaFilo) {
        let nome = Filo.argomento(sezione: c.sezione, titolo: c.titolo)
        if let i = argomenti.firstIndex(where: { $0.nome == nome }) {
            var a = argomenti.remove(at: i)
            a.fisso = true; a.scade = nil; a.nascosto = false; a.nascostoAlle = nil; a.giro += 1; a.aggiornato = Date()
            argomenti.insert(a, at: 0)
            programma()
            svegli()
            Suoni.filo()
            return
        }
        mostra("c:" + c.chiave, titolo: c.titolo, riga: Filo.rigaIntera(c), sezione: c.sezione, fisso: true)
    }

    /// Toglie un dato (`chiave`), o senza chiave l'argomento di cui si parla («toglilo»: la cosa del discorso, se no quello davanti,
    /// se FILO è via l'ultimo mostrato). Vero se c'era.
    @discardableResult
    func togli(_ chiave: String? = nil) -> Bool {
        if let chiave {
            guard let i = argomenti.firstIndex(where: { $0.righe.contains { $0.id == chiave } }) else { return false }
            argomenti[i].righe.removeAll { $0.id == chiave }
            if argomenti[i].righe.isEmpty { argomenti.remove(at: i) }
            else if !argomenti[i].fisso, !argomenti[i].righe.contains(where: \.resta), argomenti[i].scade == nil {
                argomenti[i].scade = Date().addingTimeInterval(Filo.durata(argomenti[i]))   // non aspetta più niente: torna una notifica
            }
            fineSeVuoto()
            return true
        }
        let delDiscorso = questo.map { Filo.argomento(sezione: $0.sezione, titolo: $0.titolo) }
        guard let nome = argomenti.first(where: { $0.nome == delDiscorso })?.nome ?? visti.first?.nome ?? argomenti.first?.nome else { return false }
        return togliArgomento(nome)
    }

    /// Come si legge una riga: col suo titolo davanti quando non è il nome dell'argomento («A Bea: «Arrivo alle otto.»»).
    static func testo(di r: RigaFilo, in argomento: String) -> String {
        let t = r.titolo.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.lowercased() != argomento.lowercased() else { return r.riga }
        return t + ": " + r.riga
    }

    /// 20 nov (il signore: «righe in colonna, scorrimento verticale»): un elenco dentro una riga ha le voci una per riga (a capo).
    /// Una voce sola non è un elenco. Vale per ogni argomento; l'agenda resta coi suoi « · ».
    static func voci(_ riga: String) -> [String] {
        riga.replacingOccurrences(of: "\\n", with: "\n")                  // l'a capo scritto per esteso dal cervello vale lo stesso
            .split(whereSeparator: \.isNewline)
            .map { (s: Substring) -> String in s.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// L'elenco su una riga sola (per il cervello e per i registri): le voci separate da « / ».
    static func inLinea(_ riga: String) -> String { voci(riga).joined(separator: " / ") }

    /// La X sulla testata: chiude solo quell'argomento.
    @discardableResult
    func togliArgomento(_ nome: String) -> Bool {
        guard let i = argomenti.firstIndex(where: { $0.nome == nome }) else { return false }
        argomenti.remove(at: i)
        fineSeVuoto()
        return true
    }

    /// «Togli tutto»: quanti argomenti c'erano.
    @discardableResult
    func togliTutti() -> Int {
        let n = argomenti.count
        argomenti.removeAll()
        richiamato = false
        vuota = false
        controllo?.cancel()
        pulizia?.cancel()
        riposa?.cancel()
        fuoco = true
        return n
    }

    /// Lo swipe verso sinistra dal bordo destro, nella fascia di FILO: tutto quello che c'era torna, e resta. Senza niente da
    /// riportare (13.8) si apre vuota, con «NESSUNA NOTIFICA». Il valore dice se c'era qualcosa da riportare.
    @discardableResult
    func richiama() -> Bool {
        guard !argomenti.isEmpty else {
            let eraVia = !vuota
            vuota = true
            richiamato = true
            grandeDaLui = true
            controllo?.cancel()
            svegli()
            if eraVia { Suoni.filo() }
            return false
        }
        vuota = false
        for k in argomenti.indices {
            argomenti[k].nascosto = false
            argomenti[k].nascostoAlle = nil
        }
        richiamato = true
        grandeDaLui = true
        controllo?.cancel()
        svegli()
        Suoni.filo()
        return true
    }

    /// Lo swipe a destra su FILO: tutto via (resta da richiamare con lo swipe dal bordo; per cancellare c'è la X).
    func rimandaVia() {
        let ora = Date()
        for k in argomenti.indices where !argomenti[k].nascosto {
            argomenti[k].nascosto = true
            argomenti[k].nascostoAlle = ora
        }
        richiamato = false
        grandeDaLui = false
        vuota = false
        controllo?.cancel()
        riposa?.cancel()
        fuoco = true
        programmaPulizia()
    }

    /// Il dito su FILO: le notifiche aspettano e FILO resta a fuoco; finito (anche lo scorrimento), altri 2,8 secondi.
    /// Le fonti sono tre e si sommano: il dito appoggiato (TocchiSchermo, anche fermo, come il pointerdown del mockup), il
    /// trascinamento della scheda e lo scorrimento della lista (che continua anche dopo il dito).
    func toccato(_ sopra: Bool, da fonte: String = "dito") {
        if sopra { fonti.insert(fonte) } else { fonti.remove(fonte) }
        let ora = !fonti.isEmpty
        guard ora != tocco else { return }
        tocco = ora
        if ora {
            controllo?.cancel()
            riposa?.cancel()
            fuoco = true
            return
        }
        for k in argomenti.indices where !argomenti[k].fisso && argomenti[k].scade != nil {
            let t = Date().addingTimeInterval(Filo.durata(argomenti[k]))         // 20 nov: un elenco lascia più tempo per leggerlo
            argomenti[k].scade = max(argomenti[k].scade ?? t, t)
        }
        programma()
        svegli()
    }

    /// 20 nov: quanto aspetta prima di stringersi: 2,8 s, o di più se sullo schermo c'è un elenco (come la sua scadenza).
    private var attesaCompatta: TimeInterval { visti.map { Filo.durata($0) }.max() ?? Filo.durataNotifica }

    /// FILO a fuoco adesso; in secondo piano (compatta) 2,8 s dopo, se nessuno lo tocca.
    /// 14 nov: mai mentre JARVIS parla (riparte da quando ha finito, `jarvisParla`); e se sullo schermo c'è solo roba che sta per
    /// sparire, non si stringe: sparisce e basta.
    private func svegli() {
        fuoco = true
        riposa?.cancel()
        guard !tocco else { return }
        let attesa: TimeInterval = attesaCompatta
        riposa = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(attesa))
            // 14 nov (il signore: «il saltello tra un'azione e l'altra, no»): durante la missione non si stringe, se no a ogni passo
            // si riaprirebbe (a missione finita riparte il conto)
            guard let self, !Task.isCancelled, !self.tocco, !self.voce, !Piano.condiviso.inCorso, !self.grandeDaLui else { return }
            let tra = Date().addingTimeInterval(0.6)
            let resta = self.richiamato || self.visti.contains { $0.fisso || ($0.scade ?? .distantFuture) > tra }
            guard resta else { return }
            self.fuoco = false
        }
    }

    /// Un dito si appoggia sullo schermo (TocchiSchermo, coordinate della finestra). Su FILO: FILO a fuoco e il conto delle
    /// notifiche fermo finché il dito non si alza. Fuori: lui lavora su quello che c'è sotto (la sezione, la corona), FILO va
    /// subito in secondo piano.
    func toccoSchermo(_ p: CGPoint) {
        guard !visti.isEmpty || vuota, !daParte, rettScheda.width > 0 else { return }
        if rettTasti.width > 0, rettTasti.insetBy(dx: -4, dy: -7).contains(p) { return }   // 13.7: i tre tasti fanno solo il loro
        // 23 nov (il signore: «le tab possono rimanere ingrandite entrambe nello stesso istante»): il dito sulla tab bassa (PAGINE)
        // non è «fuori»: FILO resta com'è
        let pagine = Pagine.condivisa
        if pagine.su, pagine.rett.contains(p) { return }
        // 13.9 (22): anche il dito che richiama la tab bassa dal bordo sinistro (la sua fascia) lascia la tab alta com'è
        if !pagine.su, pagine.fascia(pagine.zona()).contains(p) { return }
        if rettScheda.contains(p) {
            if !fuoco { Aptica.click(); grandeDaLui = true }             // 14 nov: si riapre sotto il dito, la selezione fine (13.9 (22): e resta)
            svegliataAlle = fuoco ? nil : Date()                         // era compatta: questo tocco la riapre e basta
            toccato(true, da: "appoggiato")
        } else if fuoco, !tocco {
            riposa?.cancel()
            grandeDaLui = false
            fuoco = false
        }
    }

    /// 13.7 · il tasto «riduci» (il signore, 21 nov 20:22: «come quelli di Apple: uno per farla grande, uno per chiuderla e uno per
    /// ridurla»): la tab compatta, una riga per argomento, subito.
    func riduci() {
        riposa?.cancel()
        guard !visti.isEmpty || vuota else { return }
        grandeDaLui = false
        fuoco = false
    }

    /// 13.7 · il tasto «apri»: la tab intera (poi, come sempre, compatta 2,8 s dopo se nessuno la tocca).
    func apri() {
        guard !visti.isEmpty || vuota else { return }
        grandeDaLui = true
        svegli()
    }

    /// Il tocco che l'ha appena riaperta (era compatta): vero una volta sola, e chi lo riceve non fa niente (come il Dock).
    /// La pressione lunga ha appena fissato: vero una volta sola (entro 0,8 s), e chi lo riceve (la riga, la X) non fa niente.
    func consumaFissa() -> Bool {
        guard let f = fissatoAlle else { return false }
        fissatoAlle = nil
        return Date().timeIntervalSince(f) < 0.8
    }

    func consumaSveglia() -> Bool {
        guard let s = svegliataAlle else { return false }
        svegliataAlle = nil
        return Date().timeIntervalSince(s) < 1.2
    }

    /// 14 nov: una frase di JARVIS comincia a suonare (Jarvis.suonoIniziato): la riga della tab di cui parla si accende.
    func voceIniziata(_ frase: String) {
        let t = Filo.piega(TagVoce.togli(frase))
        guard t.contains(where: { $0.isLetter }) else { voceOra = nil; return }
        // la durata stimata: circa 68 ms a lettera (la voce di JARVIS), almeno un secondo
        voceOra = VoceOra(testo: t, inizio: Date(), durata: max(1, Double(t.count) * 0.068))
    }

    /// Minuscole, senza accenti: per confrontare quello che dice JARVIS con le righe della tab.
    static func piega(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
    }

    /// Le parole di una riga che JARVIS potrebbe dire («11:30 dentista» → dentista), senza quelle che dice sempre.
    private static let paroleVuote: Set<String> = ["oggi", "domani", "ieri", "stasera", "alle", "dalle", "sono", "anche", "della", "delle",
                                                    "dello", "degli", "nella", "nelle", "questo", "questa", "quello", "quella", "tutto",
                                                    "tutti", "molto", "ancora", "dopo", "prima", "adesso", "sempre", "niente", "nuovi",
                                                    "nuovo", "fra", "minuti", "inviato", "pronto"]

    /// La riga accesa adesso: fra le righe (id, testo), quella la cui parola JARVIS ha appena detto (l'ultima già arrivata).
    static func rigaDetta(_ righe: [(id: String, testo: String)], voce: VoceOra?, ora: Date) -> String? {
        guard let v = voce else { return nil }
        let frase = v.testo as NSString
        let dove = min(1, max(0, ora.timeIntervalSince(v.inizio) / v.durata)) * Double(frase.length)
        var scelta: String?
        var ultima = -1
        for r in righe {
            let parole = piega(r.testo).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !paroleVuote.contains($0) }
            let dette = parole.map { frase.range(of: $0).location }.filter { $0 != NSNotFound }
            guard let k = dette.min(), Double(k) <= dove, k > ultima else { continue }
            ultima = k
            scelta = r.id
        }
        return scelta
    }

    /// 14 nov: gli istanti in cui la riga accesa cambia (la voce arriva alla parola di una riga): la tab si ridisegna proprio allora,
    /// al fotogramma giusto, senza controlli a intervalli.
    static func cambiDetta(_ righe: [(id: String, testo: String)], voce: VoceOra?) -> [Date] {
        guard let v = voce else { return [] }
        let frase = v.testo as NSString
        guard frase.length > 0 else { return [] }
        var istanti: [Date] = []
        for r in righe {
            let parole = piega(r.testo).split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !paroleVuote.contains($0) }
            guard let k = parole.map({ frase.range(of: $0).location }).filter({ $0 != NSNotFound }).min() else { continue }
            istanti.append(v.inizio.addingTimeInterval(v.durata * Double(k) / Double(frase.length) + 0.001))
        }
        return istanti.sorted()
    }

    /// Il dito si alza (o il tocco finisce in un altro modo).
    func ditoAlzato() {
        // il tocco che l'ha riaperta vale solo per quel tocco: se non è finito su un tasto, poco dopo non conta più
        if svegliataAlle != nil {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.svegliataAlle = nil
            }
        }
        if fonti.contains("appoggiato") { toccato(false, da: "appoggiato") }
    }

    private func fineSeVuoto() {
        if visti.isEmpty { richiamato = false }
        programma()
        programmaPulizia()
    }

    /// Le notifiche scadute spariscono (restano da richiamare).
    /// 14 nov (il signore: «resta finché ne state parlando»): mentre JARVIS parla le notifiche non scadono; quando ha finito,
    /// ripartono da lì (2,8 s dopo la sua ultima parola), così il dato non sparisce mentre lo sta ancora dicendo.
    private(set) var voce = false
    func jarvisParla(_ si: Bool) {
        guard si != voce else { return }
        voce = si
        if !si {
            for k in argomenti.indices where !argomenti[k].fisso && !argomenti[k].nascosto {
                let fine = Date().addingTimeInterval(Filo.durata(argomenti[k]))   // 20 nov: un elenco resta di più dopo la sua ultima parola
                if let s = argomenti[k].scade, s < fine { argomenti[k].scade = fine }
            }
            voceOra = nil                                                // ha finito: nessuna riga accesa
            if fuoco, !visti.isEmpty { svegli() }                        // 14 nov: compatta 2,8 s dopo la sua ultima parola
        }
        programma()
    }

    /// 14 nov: il cervello fissa o sgancia un argomento per nome (la regia, «tab_fissa» / «tab_sgancia»). Falso se non c'è.
    @discardableResult
    func fissa(argomento nome: String, si: Bool) -> Bool {
        guard let i = argomenti.firstIndex(where: { Regia.chiave($0.nome) == Regia.chiave(nome) }) else { return false }
        if argomenti[i].fisso != si { fissaArgomento(argomenti[i].nome) }
        if si, argomenti[i].nascosto { argomenti[i].nascosto = false; argomenti[i].nascostoAlle = nil; svegli() }
        return true
    }

    /// Il nome dell'argomento com'è nella tab, detto dal cervello o da lui («il meteo», «agenda», «Briefing»).
    func nomeArgomento(_ detto: String) -> String? {
        let k = Regia.chiave(detto)
        guard !k.isEmpty else { return nil }
        let nome = Regia.destinazione(detto).map { Filo.argomento(sezione: $0.nome, titolo: $0.nome) }
        return argomenti.first { Regia.chiave($0.nome) == k || ($0.etichetta.map { Regia.chiave($0) == k } ?? false) || $0.nome == nome }?.nome
    }

    /// 14 nov: tenuto premuto col dito, l'argomento si fissa (come «fissalo»); di nuovo, si sgancia.
    func fissaArgomento(_ nome: String) {
        guard let i = argomenti.firstIndex(where: { $0.nome == nome }) else { return }
        fissatoAlle = Date()
        argomenti[i].fisso.toggle()
        argomenti[i].scade = argomenti[i].fisso ? nil : Date().addingTimeInterval(Filo.durata(argomenti[i]))
        argomenti[i].giro += 1
        programma()
        svegli()
    }

    private func programma() {
        controllo?.cancel()
        guard !tocco, !richiamato, !voce else { return }
        let prossima = visti.filter { !$0.fisso }.compactMap(\.scade).min()
        guard let prossima else { return }
        controllo = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.05, prossima.timeIntervalSinceNow)))
            guard let self, !Task.isCancelled, !self.tocco, !self.richiamato else { return }
            let ora = Date().addingTimeInterval(0.03)
            for k in self.argomenti.indices where !self.argomenti[k].fisso && !self.argomenti[k].nascosto {
                if let s = self.argomenti[k].scade, s <= ora {
                    self.argomenti[k].nascosto = true
                    self.argomenti[k].nascostoAlle = Date()
                }
            }
            self.programma()
            self.programmaPulizia()
        }
    }

    /// 21 nov (scelta del signore: «le ultime cose mostrate»): gli argomenti spariti non escono più da FILO dopo mezz'ora; lo swipe
    /// dal bordo riporta sempre le ultime cose mostrate. Restano gli ultimi 6 (i più vecchi escono quando ne arriva uno nuovo).
    /// Prima qui partiva la pulizia dei 30 minuti: si ferma quella eventualmente in corso.
    private func programmaPulizia() {
        pulizia?.cancel()
        pulizia = nil
    }

    // MARK: I nomi, il genere, il numero

    /// Il genere e il numero dei nomi con cui il signore chiama le cose: "m", "f", "mp", "fp".
    static let generi: [String: String] = [
        "messaggio": "m", "messaggi": "mp", "meteo": "m", "tempo": "m", "previsione": "f", "brano": "m", "pezzo": "m", "canzone": "f",
        "traccia": "f", "musica": "f", "post": "m", "bozza": "f", "didascalia": "f", "foto": "f", "giornata": "f", "briefing": "m",
        "impegno": "m", "impegni": "mp", "appuntamento": "m", "dentista": "m", "palestra": "f", "cena": "f", "lista": "f", "spesa": "f",
        "profilo": "m", "instagram": "m", "progetto": "m", "piano": "m", "promemoria": "m", "nota": "f", "risposta": "f", "notizia": "f",
        "risultato": "m", "sezione": "f", "mail": "f", "email": "f", "riunione": "f", "agenda": "f",
    ]
    static let sinonimi: [String: String] = ["canzone": "brano", "pezzo": "brano", "traccia": "brano", "musica": "brano", "tempo": "meteo",
                                             "previsione": "meteo", "bozza": "post", "didascalia": "post", "appuntamento": "impegno", "email": "mail"]

    static func gn(_ nome: String) -> (genere: Character, plurale: Bool) {
        let g = generi[nome] ?? "m"
        return (g.first ?? "m", g.count > 1)
    }

    static func ha(_ r: CosaFilo, _ nome: String) -> Bool {
        r.nomi.contains(nome) || sinonimi[nome].map { r.nomi.contains($0) } == true || r.nomi.contains { sinonimi[$0] == nome }
    }

    /// Come si dice una persona: «la mamma», «Bea».
    static func detto(_ nome: String) -> String {
        switch Regia.chiave(nome) {
        case "mamma": return "la mamma"
        case "papa": return "il papà"
        default: return nome
        }
    }

    /// «di Bea», «della mamma»; «a Bea», «alla mamma».
    static func di(_ nome: String) -> String {
        switch Regia.chiave(nome) {
        case "mamma": return "della mamma"
        case "papa": return "del papà"
        default: return "di " + nome
        }
    }
    static func a(_ nome: String) -> String {
        switch Regia.chiave(nome) {
        case "mamma": return "alla mamma"
        case "papa": return "al papà"
        default: return "a " + nome
        }
    }

    /// Il genere di un nome di persona: i nomi in -a sono di donna, tranne quelli di uomo che finiscono in -a.
    static func genere(di nome: String) -> Character {
        let primo = Regia.chiave(String(nome.split(separator: " ").first ?? Substring(nome)))
        if ["mamma", "nonna", "zia", "sorella", "bea", "beatrice"].contains(primo) { return "f" }
        if ["papa", "nonno", "zio", "fratello", "luca", "andrea", "nicola", "mattia", "elia", "enea", "tobia", "battista"].contains(primo) { return "m" }
        let donna = primo.hasSuffix("a") || ["irene", "adele", "rachele", "noemi", "agnese", "beatrice"].contains(primo)
        return donna ? "f" : "m"
    }

    /// La prima frase di un testo (per la riga di un widget).
    static func primaFrase(_ t: String) -> String {
        let pulito = t.replacingOccurrences(of: "\n", with: " ")
        if let r = pulito.range(of: #"[.!?](\s|$)"#, options: .regularExpression) { return String(pulito[..<r.upperBound]).trimmingCharacters(in: .whitespaces) }
        return String(pulito.prefix(120))
    }
}
#endif
