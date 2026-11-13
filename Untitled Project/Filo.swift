#if os(iOS)
import Foundation
import Combine

// MARK: - 12.0 (16) · IL FILO DEL DISCORSO e i WIDGET FILO
// Il signore (13 nov sera): «JARVIS deve sempre sapere cosa sono "questo", "quello", "la", "quella di prima", anche dopo cinque
// frasi e cambiando sezione… messo sotto al dialogo, non come comando». Ogni cosa che JARVIS mostra, dice o fa entra nel filo col
// suo genere e numero (il meteo, la canzone, il messaggio di Bea, Bea): così «mandalo», «salvala», «rispondile», «quello di prima»
// trovano la cosa giusta. Il filo lo usano l'app (i comandi rapidi di Insieme) e il cervello (la riga FILO dentro [Schermo]).
// E alle 20:58: «mostrami… si apre FILO che mostra quello che stiamo facendo, senza dover aprire le sezioni… sono come dei widget».
// I widget FILO («Mostrami…», «Fammi vedere…», «Fissalo») stanno qui; li disegna FiloWidget.swift. Come il mockup 12.0 (16).

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

/// Un widget FILO: il dato in un mini-ologramma in alto a destra, senza aprire la sezione.
struct WidgetFilo: Identifiable, Equatable {
    let id: String
    var titolo: String
    var riga: String
    var sezione: String?
    var alle: Date
    /// Ogni aggiornamento ridisegna il widget (senza rinascere).
    var giro = 0
    var nato = Date()

    static func == (a: WidgetFilo, b: WidgetFilo) -> Bool { a.id == b.id && a.giro == b.giro && a.titolo == b.titolo && a.riga == b.riga }
}

@MainActor
final class Filo: ObservableObject {
    static let condiviso = Filo()

    private var cose: [CosaFilo] = []
    /// I widget FILO sullo schermo, il più nuovo per primo (al massimo tre).
    @Published private(set) var widget: [WidgetFilo] = []
    private var scadenze: [String: Task<Void, Never>] = [:]

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
            return "\(i + 1). \(r.detto) [\(nomi)]" + (r.riga.isEmpty ? "" : " — " + String(r.riga.prefix(140)))
        }
        var riga = "FILO (le cose di cui si parla, dalla più recente: «questo», «lo», «la», «quello di prima», «lei», «gli», «le» si risolvono qui guardando genere e numero; se è davvero ambiguo chiedi in quattro parole): " + righe.joined(separator: " · ")
        if !widget.isEmpty { riga += " ‖ WIDGET FILO sullo schermo: " + widget.map { "\($0.titolo) · \($0.riga)" }.joined(separator: "; ") }
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

    // MARK: I widget FILO

    /// Mette (o aggiorna sul posto) un widget: in cima, al massimo tre; `dura`: se ne va da solo dopo tanti secondi.
    func mostra(_ chiave: String, titolo: String, riga: String, sezione: String?, dura: TimeInterval? = nil, suono: Bool = true) {
        if let i = widget.firstIndex(where: { $0.id == chiave }) {
            var w = widget.remove(at: i)
            w.titolo = titolo; w.riga = riga; w.sezione = sezione ?? w.sezione; w.alle = Date(); w.giro += 1
            widget.insert(w, at: 0)
        } else {
            widget.insert(WidgetFilo(id: chiave, titolo: titolo, riga: riga, sezione: sezione, alle: Date()), at: 0)
            if widget.count > 3 { for w in widget[3...] { scadenze[w.id]?.cancel(); scadenze[w.id] = nil }; widget.removeLast(widget.count - 3) }
        }
        scadenze[chiave]?.cancel()
        scadenze[chiave] = nil
        if let dura {
            scadenze[chiave] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(dura))
                guard !Task.isCancelled else { return }
                self?.togli(chiave)
            }
        }
        if suono { Suoni.filo() }
    }

    /// «Fissalo»: la cosa del discorso diventa un widget.
    func fissa(_ c: CosaFilo) {
        mostra("c:" + c.chiave, titolo: c.titolo, riga: c.riga.isEmpty ? c.detto : c.riga, sezione: c.sezione)
    }

    /// Toglie un widget (nil: quello in cima). Vero se c'era.
    @discardableResult
    func togli(_ chiave: String? = nil) -> Bool {
        guard let k = chiave ?? widget.first?.id, let i = widget.firstIndex(where: { $0.id == k }) else { return false }
        scadenze[k]?.cancel()
        scadenze[k] = nil
        widget.remove(at: i)
        return true
    }

    /// «Togli tutto»: quanti ce n'erano.
    @discardableResult
    func togliTutti() -> Int {
        let n = widget.count
        scadenze.values.forEach { $0.cancel() }
        scadenze.removeAll()
        widget.removeAll()
        return n
    }

    // MARK: I nomi, il genere, il numero

    /// Il genere e il numero dei nomi con cui il signore chiama le cose: "m", "f", "mp", "fp".
    static let generi: [String: String] = [
        "messaggio": "m", "messaggi": "mp", "meteo": "m", "tempo": "m", "previsione": "f", "brano": "m", "pezzo": "m", "canzone": "f",
        "traccia": "f", "musica": "f", "post": "m", "bozza": "f", "didascalia": "f", "foto": "f", "giornata": "f", "briefing": "m",
        "impegno": "m", "impegni": "mp", "appuntamento": "m", "dentista": "m", "palestra": "f", "cena": "f", "lista": "f", "spesa": "f",
        "profilo": "m", "instagram": "m", "progetto": "m", "piano": "m", "promemoria": "m", "nota": "f", "risposta": "f", "notizia": "f",
        "risultato": "m", "sezione": "f", "mail": "f", "email": "f", "riunione": "f",
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
