#if os(iOS)
import Foundation
import UIKit
import MusicKit           // il brano che suona (LettoreMusica.voce) entra nel filo
import EventKit           // 13.1: l'agenda in FILO (il permesso del Calendario)

// MARK: - 12.0 (16) · FA MENTRE PARLA: le frasi del dialogo che l'app fa da sola
// Il signore (13 nov sera): «ogni frase, in qualsiasi forma la dica, diventa un'azione su qualsiasi sezione. Le cose semplici le fa
// subito l'app; quelle complesse le fa il cervello. Il "sì" lo chiede solo prima di mandare, cancellare o chiamare». E alle 20:58:
// «mostrami… fammi vedere…» aprono i widget FILO, non le sezioni; si lavora senza aprirle.
// Qui le frasi semplici del dialogo, coi pronomi del filo (Filo.swift): «Fammi vedere i messaggi», «Leggimi quello di Bea»,
// «Rispondile che arrivo alle otto», «Mandalo anche a lei», «Questa salvala», «Fissalo», «Toglilo», «Chiamala», «Sì», «È tutto».
// Quello che non è qui (o che va riscritto: il meteo da mandare a Bea, una didascalia più corta) va al cervello, che vede il filo.
// Come il mockup 12.0 (16) (v1216/q16-7.js).

@MainActor
final class Insieme {
    static let condiviso = Insieme()

    /// La voce di JARVIS per le frasi dell'app, con la finestra del seguito aperta dopo: il «sì» va senza «Jarvis» (Jarvis).
    var parla: ((String) -> Void)?

    /// Il messaggio (o la chiamata) preparato dall'app che aspetta il sì: «sì» lo fa, «no» lo ferma, «aggiungi che…» lo cambia.
    private struct Attesa {
        var tipo: String              // "messaggio", "chiama" o "pubblica" (il post: in «testo» quando esce, «ORA» o «VEN 21:00»)
        var chi: String
        var numero: String
        var testo: String
        var whatsapp: Bool
        var quando: Date
    }
    private var attesa: Attesa?
    /// «Rispondile» senza il testo: la frase dopo è il testo (entro un minuto).
    private var attesaTesto: (chi: String, numero: String?, quando: Date)?

    // MARK: Le frasi

    private enum Destinatario {
        case nome(String), genere(Character?), ultimo
        var eNome: Bool { if case .nome = self { return true }; return false }
    }
    private struct QualeCosa { var genere: Character? = nil; var plurale = false; var nome: String? = nil; var di: String? = nil; var prima = false }
    private enum Intento {
        case mostra(cosa: String, pron: Character?), togli, togliTutti, fissa(QualeCosa), richiama
        case messaggi, leggi(di: String?, quale: QualeCosa)
        case scrivi(a: Destinatario, testo: String, whatsapp: Bool?), scriviCosa(a: Destinatario)
        case manda(cosa: QualeCosa, a: Destinatario?, whatsapp: Bool?)
        case salva(QualeCosa), chiama(Destinatario), congedo(soloGrazie: Bool)
        case sessione(tema: String), sesSalva, sesLascia, sesIndietro(prima: Bool), pubblica(alle: String?, ora: Bool)
    }

    /// La frase (già senza «Jarvis») è sua? Allora la fa e restituisce la battuta ("": ha già parlato). Nil: va avanti la regia,
    /// poi il cervello.
    func prova(_ frase: String) async -> String? {
        let nudo = FineFrase.paroleNude(frase).joined(separator: " ")
        // il sì (o il no, o una correzione) a quello che aspetta
        if let a = attesa {
            if Date().timeIntervalSince(a.quando) > 180 { attesa = nil; Filo.condiviso.togli("bozza") }
            else if Regia.eAnnulla(frase) || ["no", "no grazie", "aspetta", "non ancora", "no aspetta"].contains(nudo) {
                attesa = nil
                Filo.condiviso.togli("bozza")
                return Battute.annullato()
            } else if Regia.eAssenso(frase) {
                return await conferma()
            } else if a.tipo == "messaggio", let m = Insieme.cerca(#"^(?:aggiungi|aggiungici|metti anche|scrivi anche|di anche|dille anche|digli anche)(?: che)? (.+)$"#, Insieme.norma(frase)) {
                let piu = Insieme.diretto(Regia.originale(frase, da: Insieme.paroleDavanti(frase, m[1] ?? ""), a: Regia.paroleComando(frase).count))
                var x = a
                let base = x.testo.trimmingCharacters(in: CharacterSet(charactersIn: ".!… "))
                x.testo = base + ", " + piu.prefix(1).lowercased() + String(piu.dropFirst())
                x.quando = Date()
                attesa = x
                Filo.condiviso.mostra("bozza", titolo: Filo.a(x.chi).capitalizzata, riga: "«\(x.testo)»", sezione: "Messaggi", suono: false, resta: true)
                return Battute.chiediMessaggio(x.chi, x.testo, whatsapp: x.whatsapp)
            }
        }
        // 13.1: il congedo appena chiesto e lui risponde secco: «sì» a «Sarà tutto?» chiude, «sì» a «Le serve altro?» vuol dire che
        // c'è altro («Mi dica, Sir»); «no» al contrario (prima un «sì» secco andava al cervello, che non sapeva della domanda)
        if attesa == nil, let chiude = Congedo.condiviso.rispostaSecca(nudo) {
            Congedo.condiviso.chiuso()
            return chiude ? Battute.congedoOk() : "Mi dica, Sir."
        }
        // «Rispondile» → «Cosa le scrivo?» → la frase dopo è il testo
        if let t = attesaTesto {
            attesaTesto = nil
            if Date().timeIntervalSince(t.quando) < 60, riconosci(Insieme.norma(frase), nudo: nudo) == nil, !Regia.eAnnulla(frase) {
                return await preparaMessaggio(t.chi, numero: t.numero, testo: Insieme.diretto(frase), whatsapp: nil)
            }
        }
        guard let i = riconosci(Insieme.norma(frase), nudo: nudo) else { return nil }
        return await fai(i, frase: frase)
    }

    /// Senza fare niente: la farebbe l'app? (Per non chiedere al cervello una risposta anticipata che sarebbe buttata.)
    func sua(_ frase: String) -> Bool {
        if attesa != nil, Regia.eAssenso(frase) || Regia.eAnnulla(frase) { return true }
        let nudo = FineFrase.paroleNude(frase).joined(separator: " ")
        if attesa == nil, Congedo.condiviso.rispostaSecca(nudo) != nil { return true }
        guard let i = riconosci(Insieme.norma(frase), nudo: nudo) else { return false }
        let filo = Filo.condiviso
        switch i {
        case .sessione: return false                                  // la sessione la propone il cervello
        case .mostra(let cosa, let pron): return mostraLocale(cosa, pron: pron, frase: frase)
        case .togli, .togliTutti, .richiama: return !filo.argomenti.isEmpty   // FILO vuoto: «toglilo» è forse della sezione davanti
        case .salva(let q):
            let r = q.nome != nil ? filo.cosa(nome: q.nome) : filo.cosa(genere: q.genere, plurale: q.plurale)
            return r?.tipo == "brano" || r?.tipo == "post"
        case .manda(let q, _, _):
            let r = q.nome != nil ? filo.cosa(nome: q.nome, di: q.di, prima: q.prima) : filo.cosa(genere: q.genere, plurale: q.plurale)
            return r?.daMandare != nil
        default: return true
        }
    }

    private func riconosci(_ n: String, nudo: String) -> Intento? {
        guard !n.isEmpty || !nudo.isEmpty else { return nil }
        // il congedo («è tutto, grazie», «no grazie»), fuori dal lavoro insieme
        if !Sessione.condivisa.aperta, Insieme.cerca(#"^(?:si )?(?:e tutto|no (?:e tutto|grazie)|no grazie|basta cosi|a posto cosi|niente grazie|nient altro|niente altro|tutto a posto|va bene cosi|sono a posto|grazie e tutto|grazie)(?: grazie)?(?: sir)?$"#, nudo) != nil {
            return .congedo(soloGrazie: nudo == "grazie" || nudo == "grazie sir")
        }
        let ses = Sessione.condivisa
        // il lavoro insieme: le chiusure e il «torna indietro» le fa l'app; le correzioni le riscrive il cervello
        if ses.aperta {
            if Insieme.cerca(#"^(?:salval[oa]|salva|salvala cosi|salvalo cosi|tienilo cosi|va bene cosi|ok cosi|perfetto|chiudiamo|fatto|e perfetto|cosi va bene|lascialo cosi|mi piace cosi|approvato|va bene|e tutto|basta cosi|a posto cosi|grazie e tutto)$"#, nudo) != nil || (n.isEmpty && nudo == "perfetto") { return .sesSalva }
            if Insieme.cerca(#"^(?:lascia stare|lascia perdere|annulla tutto|non lo facciamo|niente post|butta via tutto|lasciamo perdere)$"#, n) != nil { return .sesLascia }
            if Insieme.cerca(#"^(?:torna (?:alla )?(?:versione )?(?:di )?prima|torna indietro|indietro|la versione di prima|era meglio prima|la prima era meglio|torna alla prima(?: versione)?|annulla l ultima(?: modifica)?|annulla|rimetti com era|com era prima|rimettilo com era)$"#, n) != nil {
                return .sesIndietro(prima: n.contains("prima era meglio") || n.contains("alla prima"))
            }
        }
        if ses.aperta || ses.bozza != nil {
            if let m = Insieme.cerca(#"^(?:programmal[oa]|pubblical[oa]|mettil[oa] online|fall[oa] uscire|postal[oa])(?: (?:per|stasera))?(?: (?:alle|all|per le|verso le) (.+))?$"#, n) {
                return .pubblica(alle: m[1], ora: n.hasPrefix("pubblic") && m[1] == nil)
            }
        }
        var m: [String?]?
        // i widget FILO: «mostrami…», «fammi vedere…» (niente sezione), «toglilo», «togli tutto»
        if let m = Insieme.cerca(#"^(?:mostrami|mostra|fammi vedere|fai vedere|vediamo|fammel([oaie]) vedere|mostramel([oaie])|fammi un po vedere)(?: (.+))?$"#, n) {
            return .mostra(cosa: (m[3] ?? "").trimmingCharacters(in: .whitespaces), pron: (m[1] ?? m[2]).flatMap { Insieme.pron($0).genere })
        }
        // 14 nov: la tab torna a voce, come con lo swipe dal bordo
        if Insieme.cerca(#"^(?:rifammi vedere|fammi rivedere|fammel[oaie] rivedere|riportami la tab|ridammi la tab|cosa mi hai mostrato|rimetti in vista|rimettimel[oaie] in vista|riportamel[oaie])$"#, n) != nil { return .richiama }
        if Insieme.cerca(#"^(?:togli tutto|togli tutti|via tutto|via tutti|togli i widget|pulisci tutto)$"#, n) != nil { return .togliTutti }
        if Insieme.cerca(#"^(?:toglil[oaie]|togli questo|togli quello|via questo|togli il widget|staccal[oa]|stacca)$"#, n) != nil || n == "via" { return .togli }
        if let m = Insieme.cerca(#"^(?:fissal([oaie])|fissa(?: quest([oa]))?|tienil([oa]) in vista|appuntal([oa]))$"#, n) {
            let p = (m[1] ?? m[2] ?? m[3] ?? m[4]).map { Insieme.pron($0) }
            return .fissa(QualeCosa(genere: p?.genere, plurale: p?.plurale ?? false))
        }
        // i messaggi: «apri i messaggi» apre la sezione (la regia); qui «chi mi ha scritto», «leggimi quello di Bea»
        if Insieme.cerca(#"^(?:chi mi ha scritto(?: oggi)?|ho (?:dei |nuovi |altri )?messaggi(?: nuovi)?|ci sono (?:dei )?messaggi(?: nuovi)?)$"#, n) != nil { return .messaggi }
        m = Insieme.cerca(#"^(?:leggimi|leggi|leggermi|fammi sentire|dimmi) (?:quello|quella|il messaggio|l ultimo(?: messaggio)?|cosa ha scritto|cosa scrive|cosa dice) (?:di|da) (\w+)$"#, n)
            ?? Insieme.cerca(#"^(?:cosa|che cosa) (?:dice|mi dice|ha scritto|mi ha scritto|scrive|mi scrive|vuole) (\w+)$"#, n)
        if let m, let di = m[1] { return .leggi(di: di, quale: QualeCosa()) }
        if let m = Insieme.cerca(#"^(?:leggimel([oa])|leggil([oa])|leggimi quest([oa])|leggi quest([oa])|leggimi quell([oa])(?: di prima)?)$"#, n) {
            let p = Insieme.pron(m[1] ?? m[2] ?? m[3] ?? m[4] ?? m[5] ?? "o")
            return .leggi(di: nil, quale: QualeCosa(genere: p.genere, prima: n.hasSuffix("di prima")))
        }
        // rispondere e scrivere: «rispondile che…», «dille che…», «scrivi a Marco che…» (con «di + verbo» decide il cervello)
        if let m = Insieme.cerca(#"^(rispondile|rispondigli|scrivile|scrivigli|dille|digli)(?: su (whatsapp|imessage))?(?: che)? (.+)$"#, n), let t = m[3], !t.hasPrefix("di ") {
            return .scrivi(a: .genere((m[1] ?? "").hasSuffix("le") ? "f" : "m"), testo: t, whatsapp: m[2].map { $0 == "whatsapp" })
        }
        if let m = Insieme.cerca(#"^(?:rispondi|scrivi|di|manda un messaggio|scrivi un messaggio) a (\w+)(?: su (whatsapp|imessage))?(?: che)? (.+)$"#, n), let chi = m[1], let t = m[3], !t.hasPrefix("di ") {
            return .scrivi(a: .nome(chi), testo: t, whatsapp: m[2].map { $0 == "whatsapp" })
        }
        if let m = Insieme.cerca(#"^rispondi(?: su (whatsapp|imessage))?(?: che)? (.+)$"#, n), let t = m[2], !t.hasPrefix("di "), !t.hasPrefix("a ") {
            return .scrivi(a: .ultimo, testo: t, whatsapp: m[1].map { $0 == "whatsapp" })
        }
        if ["rispondile", "rispondigli", "scrivile", "scrivigli", "rispondi"].contains(n) {
            return .scriviCosa(a: n.hasSuffix("le") ? .genere("f") : n.hasSuffix("gli") ? .genere("m") : .ultimo)
        }
        // mandare: «mandalo anche a lei», «giraglielo», «manda a Bea il messaggio di Marco»
        if let m = Insieme.cerca(#"^(?:mandal|invial|giral|passal|condividil)([oaie])(?: anche)?(?: a (\w+))?(?: anche)?(?: su (whatsapp|imessage))?$"#, n) {
            let p = Insieme.pron(m[1] ?? "o")
            return .manda(cosa: QualeCosa(genere: p.genere, plurale: p.plurale), a: m[2].map { .nome($0) }, whatsapp: m[3].map { $0 == "whatsapp" })
        }
        if let m = Insieme.cerca(#"^(?:mandaglie|giraglie|inviaglie)l([oaie])(?: su (whatsapp|imessage))?$"#, n) {
            let p = Insieme.pron(m[1] ?? "o")
            return .manda(cosa: QualeCosa(genere: p.genere, plurale: p.plurale), a: .ultimo, whatsapp: m[2].map { $0 == "whatsapp" })
        }
        if let m = Insieme.cerca(#"^(manda|gira|invia|mandale|mandagli|girale|giragli)(?: a (\w+))? (?:anche )?(?:il |lo |la |l |i |gli |le |quest[oa] |quell[oa] )(\w+)(?: di (\w+))?(?: a (\w+))?(?: su (whatsapp|imessage))?$"#, n),
           let nome = m[3], Filo.generi[nome] != nil {
            let di = m[4].flatMap { ["prima", "oggi", "stasera", "domani", "ieri"].contains($0) ? nil : $0 }
            let verbo = m[1] ?? ""
            let a: Destinatario? = (m[2] ?? m[5]).map { .nome($0) } ?? (verbo.hasSuffix("le") ? .genere("f") : verbo.hasSuffix("gli") ? .genere("m") : nil)
            return .manda(cosa: QualeCosa(nome: nome, di: di, prima: m[4] == "prima"), a: a, whatsapp: m[6].map { $0 == "whatsapp" })
        }
        // salvare: «questa salvala», «salvala», «salva questa canzone», «mettila nei preferiti»
        if let m = Insieme.cerca(#"^(?:quest[oaie] )?(?:salval|salvamel|tienil|conserval)([oaie])(?: (?:nei|tra i|ai) preferiti)?$"#, n) {
            let p = Insieme.pron(m[1] ?? "o")
            return .salva(QualeCosa(genere: p.genere, plurale: p.plurale))
        }
        if let m = Insieme.cerca(#"^(?:mettil|aggiungil)([oa]) (?:nei|ai|tra i) preferiti$"#, n) { return .salva(QualeCosa(genere: Insieme.pron(m[1] ?? "o").genere)) }
        if let m = Insieme.cerca(#"^(?:salva|salvami) (?:quest[oa] |il |la |lo |l )?(\w+)(?: di prima)?$"#, n), let nome = m[1], Filo.generi[nome] != nil {
            return .salva(QualeCosa(nome: nome))
        }
        // chiamare (col sì)
        if let m = Insieme.cerca(#"^(?:chiamal([oa])|telefonal([oa])|telefonagli)$"#, n) { return .chiama(.genere((m[1] ?? m[2]) == "a" ? "f" : "m")) }
        if let m = Insieme.cerca(#"^(?:chiama|chiamami|telefona a) (\w+)$"#, n), let chi = m[1], !["la", "lo", "lei", "lui"].contains(chi) { return .chiama(.nome(chi)) }
        // lavorare insieme: «progettiamo il post di stasera», «prepariamo…», «scriviamo…»
        if let m = Insieme.cerca(#"^(?:progettiamo|prepariamo|scriviamo|organizziamo|pensiamo|lavoriamo|impostiamo|creiamo|costruiamo|studiamo|buttiamo giu|mettiamo giu|facciamo)(?: a| al| alla| allo| ai| un| una| il| la| lo| l)? ?(.+)$"#, n),
           let tema = m[1], Insieme.cerca(#"\b(post|reel|storia|instagram|didascalia|carosello)\b"#, tema) != nil {
            return .sessione(tema: tema)
        }
        return nil
    }

    // MARK: Fare

    private func fai(_ i: Intento, frase: String) async -> String? {
        let filo = Filo.condiviso
        switch i {
        case .congedo(let solo):
            Congedo.condiviso.chiuso()
            return solo ? Battute.prego() : Battute.congedoOk()
        case .mostra(let cosa, let pron):
            return await mostra(cosa, pron: pron, frase: frase)
        case .togli:
            guard !filo.argomenti.isEmpty else { return nil }                // FILO vuoto: forse è della sezione davanti
            guard filo.togli() else { return "Non c'è niente in vista, Sir." }
            Suoni.filoVia()
            return Battute.staccato()
        case .togliTutti:
            guard filo.togliTutti() > 0 else { return nil }                  // FILO vuoto: forse «togli tutto» della sezione davanti
            Suoni.filoVia()
            return Battute.angoloLibero()
        case .richiama:
            guard filo.richiama() else { return nil }                       // niente da riportare: la frase va avanti
            return Battute.una("richiamaTab", ["Ecco, Sir.", "Di nuovo in vista.", "Eccolo qui."])
        case .fissa(let q):
            aggiornaBrano()
            guard let r = q.genere == nil ? filo.questo : filo.cosa(genere: q.genere, plurale: q.plurale) else { return Battute.nienteDaMostrare() }
            filo.fissa(r)
            return Battute.fissato()
        case .messaggi:
            let arr = Insieme.arrivatiOggi()
            guard !arr.isEmpty else { return "Oggi non è arrivato niente, Sir." }
            for v in arr.reversed() { filo.persona(v.nome); filo.metti(Insieme.cosaMessaggio(v)) }
            let nomi = arr.map { Filo.detto($0.nome) }
            // 14 nov: il dato utile va nella tab da solo, mentre lo dice
            filo.mostra("messaggi", titolo: "Messaggi", riga: "\(arr.count) nuovi · " + nomi.joined(separator: ", "), sezione: "Messaggi")
            return "\(Battute.numero(arr.count).capitalizzata) nuovi, Sir: \(Insieme.elenco(nomi))."
        case .leggi(let di, let q):
            var r: CosaFilo?
            if let di {
                r = filo.cosa(di: Insieme.nomeDetto(di) ?? di, tipi: ["messaggio"]) ?? Insieme.ultimoDi(di).map(Insieme.cosaMessaggio)
                guard r != nil else { return "Oggi \(di.capitalizzata) non ha scritto, Sir." }
            } else {
                r = filo.cosa(genere: q.genere, prima: q.prima, tipi: ["messaggio", "risposta", "post"]) ?? filo.cosa(genere: q.genere, prima: q.prima)
            }
            guard let r, let testo = r.testo else { return Battute.nienteDaMostrare() }
            if let p = r.persona { filo.persona(p) }
            filo.metti(r)
            mostraCosa(r)                                                // 14 nov: quello che legge compare nella tab mentre lo legge
            if r.tipo == "messaggio", let p = r.persona { return "\(Filo.detto(p).capitalizzata), \(Insieme.quandoDetto(r.quando)): «\(testo)»" }
            return testo
        case .scrivi(let a, let testo, let wa):
            guard let chi = await destinatario(a) else { return a.eNome ? nil : Battute.aChi() }
            let originale = Insieme.testoOriginale(frase, dopo: testo)
            return await preparaMessaggio(chi.nome, numero: chi.numero, testo: Insieme.diretto(originale), whatsapp: wa)
        case .scriviCosa(let a):
            guard let chi = await destinatario(a) else { return Battute.aChi() }
            attesaTesto = (chi.nome, chi.numero, Date())
            return "Cosa \(Filo.genere(di: chi.nome) == "f" ? "le" : "gli") scrivo, Sir?"
        case .manda(let q, let a, let wa):
            aggiornaBrano()
            let r = q.nome != nil ? filo.cosa(nome: q.nome, di: q.di, prima: q.prima) : filo.cosa(genere: q.genere, plurale: q.plurale)
            // da riscrivere (una risposta del cervello, che parla a «Sir»): lo fa il cervello, che vede il filo
            guard let r, let testo = r.daMandare else { return nil }
            guard let a, let chi = await destinatario(a) else { return a == nil ? Battute.aChi() : nil }
            return await preparaMessaggio(chi.nome, numero: chi.numero, testo: testo, whatsapp: wa)
        case .salva(let q):
            aggiornaBrano()
            guard let r = q.nome != nil ? filo.cosa(nome: q.nome) : filo.cosa(genere: q.genere, plurale: q.plurale) else { return nil }   // niente: decide la sezione o il cervello
            switch r.tipo {
            case "brano":
                let e = await LettoreMusica.condiviso.salvaNeiPreferiti()
                if let errore = e.errore { return errore }
                return Battute.salvataMusica(e.titolo ?? r.titolo)
            case "post":
                if Sessione.condivisa.aperta { return Sessione.condivisa.salva() }
                return "È già tra le bozze, Sir."
            default:
                return nil                                           // una risposta, una nota: dove salvarla lo decide il cervello
            }
        case .chiama(let a):
            guard let chi = await destinatario(a), let numero = chi.numero else { return a.eNome ? nil : "Chi, Sir?" }
            attesa = Attesa(tipo: "chiama", chi: chi.nome, numero: numero, testo: "", whatsapp: false, quando: Date())
            return "Chiamo \(Filo.detto(chi.nome)), Sir?"
        case .sessione(let tema):
            await Sessione.condivisa.inizia(tema: tema)
            return nil                                               // la prima idea la propone il cervello (vede la SESSIONE)
        case .sesSalva:
            return Sessione.condivisa.salva()
        case .sesLascia:
            Sessione.condivisa.chiudi(salva: false)
            return "Come vuole, Sir: niente post. La bozza resta lì se cambia idea."
        case .sesIndietro(let prima):
            return await Sessione.condivisa.indietro(allaPrima: prima)
        case .pubblica(let alle, let ora):
            // pubblicare è mandare: prima il sì («Lo programmo per stasera alle nove, Sir?»)
            let ses = Sessione.condivisa
            let q = ora ? "ORA" : (Sessione.quando(detto: alle) ?? ses.bozza?.quando ?? ses.versione?.quando ?? Sessione.stasera(21 * 60))
            attesa = Attesa(tipo: "pubblica", chi: "", numero: "", testo: q, whatsapp: false, quando: Date())
            return q == "ORA" ? "Lo pubblico adesso su @kingrusto, Sir?" : "Lo programmo per \(Sessione.detto(q)), Sir?"
        }
    }

    /// «Mostrami…»: il dato giusto in un widget FILO, senza aprire niente. Nil: non ce l'ho qui, decide il cervello.
    private func mostra(_ cosaDetta: String, pron: Character?, frase: String) async -> String? {
        let filo = Filo.condiviso
        let t = Insieme.cosaMostrata(cosaDetta)
        aggiornaBrano()
        if t.isEmpty || pron != nil || ["questo", "questa", "quello", "quella"].contains(t) {
            let g: Character? = pron ?? (["questa", "quella"].contains(t) ? "f" : nil)
            guard let r = g == nil ? filo.questo : filo.cosa(genere: g) else { return Battute.nienteDaMostrare() }
            mostraCosa(r)                                            // «mostramelo»: una notifica, non fissato (come il mockup)
            return Battute.ecco()
        }
        if Insieme.cerca(#"^(?:(?:nuovi |ultimi )?messaggi(?: nuovi| arrivati| di oggi)?|chi mi ha scritto)$"#, t) != nil {
            let arr = Insieme.arrivatiOggi()
            for v in arr.reversed() { filo.persona(v.nome); filo.metti(Insieme.cosaMessaggio(v)) }
            filo.mostra("messaggi", titolo: "Messaggi", riga: arr.isEmpty ? "niente di nuovo oggi" : "\(arr.count) nuovi · " + arr.map { Filo.detto($0.nome) }.joined(separator: ", "), sezione: "Messaggi")
            return arr.isEmpty ? "Niente di nuovo, Sir." : "\(Battute.numero(arr.count).capitalizzata) nuovi, Sir."
        }
        // 13.1: il meteo e l'agenda li mostra l'app (come il mockup), senza aspettare il cervello
        if Insieme.cerca(Insieme.schemaMeteo, t) != nil {
            let giorno = Insieme.giornoMeteo(t)
            guard let m = await MeteoQui.rigaFilo(giorno) else { return nil }          // Apple Meteo non risponde: il cervello
            let r = filo.metti(CosaFilo(chiave: "meteo:" + giorno, tipo: "risposta", nomi: ["meteo", "tempo", "previsione"], titolo: "Meteo",
                                        riga: m.riga, detto: "il meteo di " + giorno, testo: m.daMandare, daMandare: m.daMandare, sezione: "Meteo"))
            filo.mostra("c:" + r.chiave, titolo: "Meteo", riga: m.riga, sezione: "Meteo")
            return Battute.ecco()
        }
        if Insieme.cerca(Insieme.schemaAgenda, t) != nil {
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }   // senza permesso: il cervello
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            let oggi = Calendar.current.startOfDay(for: Date())
            let impegni: [String] = PonteTelefono.impegniDiOggi().map { e in
                let minuti = (e["m"] as? Double) ?? 0
                return f.string(from: oggi.addingTimeInterval(minuti * 60)) + " " + ((e["nome"] as? String) ?? "")
            }
            let riga = impegni.isEmpty ? "nessun impegno oggi" : impegni.joined(separator: " · ")
            filo.metti(CosaFilo(chiave: "agenda", tipo: "impegno", nomi: ["agenda", "impegni", "appuntamento"], titolo: "Agenda", riga: riga,
                                detto: "l'agenda di oggi", testo: riga, sezione: "Briefing"))
            filo.mostra("agenda", titolo: "Agenda", riga: riga, sezione: "Briefing")
            return impegni.isEmpty ? "Oggi niente in agenda, Sir." : Battute.ecco()
        }
        if let m = Insieme.cerca(#"^(?:quello|quella|il messaggio|l ultimo(?: messaggio)?) (?:di|da) (\w+)$"#, t), let di = m[1] {
            guard let v = Insieme.ultimoDi(di) else { return "Oggi \(di.capitalizzata) non ha scritto, Sir." }
            let r = filo.metti(Insieme.cosaMessaggio(v))
            filo.persona(v.nome)
            filo.mostra("c:" + r.chiave, titolo: "Da " + v.nome, riga: "«\(r.testo ?? "")»", sezione: "Messaggi")
            return Battute.ecco()
        }
        if Insieme.cerca(#"\b(canzone|brano|pezzo|musica|cosa suona|che canzone)\b"#, t) != nil {
            guard let r = filo.cosa(tipi: ["brano"]) else {
                filo.mostra("brano", titolo: "Musica", riga: "niente in riproduzione", sezione: "Musica")
                return Battute.ecco()
            }
            mostraCosa(r)
            return Battute.ecco()
        }
        if Insieme.cerca(#"\b(post|didascalia|bozza)\b"#, t) != nil, let v = Sessione.condivisa.versione ?? Sessione.condivisa.bozza {
            filo.mostra("c:post", titolo: "Post", riga: Filo.primaFrase(v.didascalia), sezione: "Social")
            return Battute.ecco()
        }
        // un nome secco («mostrami Bea»): l'ultimo messaggio di quella persona, se la sezione davanti non ha una sua frase per questo
        // («mostrami Milano» col Satellite davanti vola su Milano)
        if t.split(separator: " ").count == 1, !Regia.condivisa.davantiCapisce(frase), let v = Insieme.ultimoDi(t) {
            let r = filo.metti(Insieme.cosaMessaggio(v))
            filo.persona(v.nome)
            filo.mostra("c:" + r.chiave, titolo: "Da " + v.nome, riga: "«\(r.testo ?? "")»", sezione: "Messaggi")
            return Battute.ecco()
        }
        // tutto il resto: il cervello risponde e lo mette in FILO con la regia («mostra»)
        return nil
    }

    /// Senza fare niente: «mostrami…» lo fa l'app (gli stessi casi di `mostra`)? No: va al cervello, che può partire in anticipo.
    private func mostraLocale(_ cosaDetta: String, pron: Character?, frase: String) -> Bool {
        let t = Insieme.cosaMostrata(cosaDetta)
        if t.isEmpty || pron != nil || ["questo", "questa", "quello", "quella"].contains(t) { return true }
        if Insieme.cerca(#"^(?:(?:nuovi |ultimi )?messaggi(?: nuovi| arrivati| di oggi)?|chi mi ha scritto)$"#, t) != nil { return true }
        if Insieme.cerca(Insieme.schemaMeteo, t) != nil { return true }
        if Insieme.cerca(Insieme.schemaAgenda, t) != nil { return EKEventStore.authorizationStatus(for: .event) == .fullAccess }
        if Insieme.cerca(#"^(?:quello|quella|il messaggio|l ultimo(?: messaggio)?) (?:di|da) (\w+)$"#, t) != nil { return true }
        if Insieme.cerca(#"\b(canzone|brano|pezzo|musica|cosa suona|che canzone)\b"#, t) != nil { return true }
        if Insieme.cerca(#"\b(post|didascalia|bozza)\b"#, t) != nil, Sessione.condivisa.versione ?? Sessione.condivisa.bozza != nil { return true }
        return t.split(separator: " ").count == 1 && !Regia.condivisa.davantiCapisce(frase) && Insieme.ultimoDi(t) != nil
    }

    /// La cosa detta dopo «mostrami»: senza «un po'», «anche» e l'articolo.
    private static func cosaMostrata(_ cosaDetta: String) -> String {
        var t = cosaDetta
        for a in ["un po ", "anche "] where t.hasPrefix(a) { t.removeFirst(a.count) }
        if let r = t.range(of: #"^(?:il|lo|la|l|i|gli|le) "#, options: .regularExpression) { t.removeSubrange(r) }
        return t
    }
    /// «tempo» solo come meteo («il tempo», «che tempo fa»): «quanto tempo manca» no
    private static let schemaMeteo = #"\b(meteo|previsioni|previsione|cielo)\b|(?:^|che )tempo\b"#
    private static let schemaAgenda = #"\b(agenda|impegni|impegno|appuntamenti|calendario|giornata)\b"#
    /// «il meteo di domani», «com'è stasera»: di quale giorno.
    private static func giornoMeteo(_ t: String) -> String {
        if t.contains("domani") { return "domani" }
        if t.contains("stasera") || t.contains("sera") || t.contains("stanotte") { return "stasera" }
        return "oggi"
    }

    /// Una cosa del discorso in FILO come notifica («mostrami…»: sparisce da sola; «fissalo» la tiene).
    private func mostraCosa(_ r: CosaFilo) {
        Filo.condiviso.mostra("c:" + r.chiave, titolo: r.titolo, riga: r.riga.isEmpty ? r.detto : r.riga, sezione: r.sezione)
    }

    /// Il brano che suona nel filo: se nel filo c'è un altro brano (è cambiato) prende il suo posto; se non c'è, entra in fondo
    /// (la musica che suona da dieci minuti non è l'ultima cosa detta). In cima solo quando parte a voce (`branoInCima`).
    func aggiornaBrano() {
        guard let c = cosaBrano() else { return }
        Filo.condiviso.sostituisci(c, inCima: false)
    }

    /// La musica appena partita a voce («mettimi un po' di musica»): è la cosa di cui si parla.
    func branoInCima() {
        Task { @MainActor in
            for _ in 0..<12 {                                           // il lettore mette il brano in coda un attimo dopo
                if let c = cosaBrano() { Filo.condiviso.sostituisci(c, inCima: true); return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func cosaBrano() -> CosaFilo? {
        guard let e = LettoreMusica.condiviso.voce else { return nil }
        let sotto = e.subtitle ?? ""
        return CosaFilo(chiave: "brano:" + e.id, tipo: "brano", nomi: ["brano", "pezzo", "canzone", "traccia"], titolo: "Musica",
                        riga: e.title + (sotto.isEmpty ? "" : " · " + sotto), detto: "«\(e.title)»",
                        daMandare: "Ascolta questa: «\(e.title)»" + (sotto.isEmpty ? "." : " di \(sotto)."), sezione: "Musica")
    }

    // MARK: Il messaggio: preparato, riletto, parte solo col sì (senza aprire Messaggi)

    private func preparaMessaggio(_ chi: String, numero: String?, testo: String, whatsapp: Bool?) async -> String? {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        var num = numero
        if num == nil { num = await Insieme.numero(di: chi) }
        guard let num else { return "Non trovo il numero di \(Filo.detto(chi)), Sir." }
        let wa = whatsapp ?? false
        attesa = Attesa(tipo: "messaggio", chi: chi, numero: num, testo: t, whatsapp: wa, quando: Date())
        Filo.condiviso.persona(chi)
        // il signore (13 nov 20:58): si lavora senza aprire sezioni: la bozza è un widget FILO finché non dice sì
        Filo.condiviso.mostra("bozza", titolo: Filo.a(chi).capitalizzata, riga: "«\(t)»", sezione: "Messaggi", resta: true)   // aspetta il sì: non è una notifica
        return Battute.chiediMessaggio(chi, t, whatsapp: wa)
    }

    /// Il sì: parte da qui (iMessage col Comando rapido «JARVIS invia», WhatsApp pronto da toccare), quando JARVIS ha finito di parlare.
    private func conferma() async -> String {
        guard let a = attesa else { return Battute.lampo() }
        attesa = nil
        if a.tipo == "pubblica" {                                        // il post: esce come dal tasto PUBBLICA › SÌ della pagina
            let r = await Sessione.condivisa.pubblica(alle: a.testo == "ORA" ? nil : a.testo, ora: a.testo == "ORA")
            Congedo.condiviso.cosaVera()
            return r ?? ""
        }
        if a.tipo == "chiama" {
            Filo.condiviso.persona(a.chi)
            guard let url = URL(string: "tel://\(Strumenti.pulisci(a.numero))") else { return "Non riesco a chiamare, Sir." }
            Insieme.dopoLaVoce { UIApplication.shared.open(url) }
            return "Chiamo \(Filo.detto(a.chi))."
        }
        let url: URL?
        if a.whatsapp {
            url = URL(string: "https://wa.me/\(Rubrica.internazionale(a.numero))?text=\(Strumenti.codifica(a.testo))")
        } else {
            let dati = (try? JSONSerialization.data(withJSONObject: ["numero": Strumenti.pulisci(a.numero), "testo": a.testo])) ?? Data()
            url = URL(string: "shortcuts://run-shortcut?name=\(Strumenti.codifica(Strumenti.comandoInvio))&input=text&text=\(Strumenti.codifica(String(decoding: dati, as: UTF8.self)))")
        }
        guard let url else { return "Non riesco a preparare il messaggio, Sir." }
        Insieme.dopoLaVoce { UIApplication.shared.open(url) }
        let (numero, testo, wa, chi) = (a.numero, a.testo, a.whatsapp, a.chi)
        Task { await RegistroMessaggi.mandato(a: numero, testo: testo, whatsapp: wa) }
        Suoni.pronto()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Filo.condiviso.mostra("bozza", titolo: Filo.a(chi).capitalizzata, riga: wa ? "pronto su WhatsApp" : "inviato · \(testo)", sezione: "Messaggi", dura: 3.5, suono: false)
        Filo.condiviso.metti(CosaFilo(chiave: "out:" + Regia.chiave(chi), tipo: "messaggio", nomi: ["messaggio"], titolo: "Messaggio",
                                      riga: Filo.a(chi).capitalizzata + ": " + testo, detto: "il messaggio " + Filo.a(chi), persona: chi,
                                      testo: testo, daMandare: testo, numero: numero, sezione: "Messaggi"))
        Filo.condiviso.persona(chi)
        Congedo.condiviso.cosaVera()                                    // un messaggio mandato è una cosa vera
        return wa ? "Pronto per \(Filo.detto(chi)) su WhatsApp, Sir: l'ultimo tocco su Invia è suo." : Battute.mandato(chi)
    }

    /// Un lavoro da fare quando JARVIS ha finito di parlare (aprire Comandi, WhatsApp, il telefono).
    private static func dopoLaVoce(_ lavoro: @escaping @MainActor () -> Void) {
        if let dopo = Regia.condivisa.dopoLaVoce { dopo(lavoro) } else { lavoro() }
    }

    private func destinatario(_ a: Destinatario) async -> (nome: String, numero: String?)? {
        switch a {
        case .nome(let n):
            if n == "lei" || n == "lui" {
                guard let p = Filo.condiviso.chi(genere: n == "lei" ? "f" : "m") else { return nil }
                return (p, Insieme.numeroNelFilo(p))
            }
            guard let c = await Insieme.contatto(n) else { return nil }
            return (c.nome, c.primoNumero)
        case .genere(let g):
            guard let p = Filo.condiviso.chi(genere: g) ?? (g == "m" ? Filo.condiviso.chi() : nil) else { return nil }
            return (p, Insieme.numeroNelFilo(p))
        case .ultimo:
            if let r = Filo.condiviso.cosa(tipi: ["messaggio"]), let p = r.persona { return (p, r.numero) }
            guard let p = Filo.condiviso.chi() else { return nil }
            return (p, Insieme.numeroNelFilo(p))
        }
    }

    // MARK: I dati

    /// I messaggi arrivati oggi (l'automazione di Comandi), il più nuovo per primo.
    static func arrivatiOggi() -> [VoceRegistro] {
        Registro.leggi(RegistroMessaggi.ricevuti).filter { Calendar.current.isDateInToday($0.quando) }.prefix(5).map { $0 }
    }
    static func ultimoDi(_ detto: String) -> VoceRegistro? {
        let voci = Registro.leggi(RegistroMessaggi.ricevuti)
        let k = Regia.chiave(detto)
        guard !k.isEmpty else { return nil }
        return voci.first { v in let n = Regia.chiave(v.nome); return n == k || n.hasPrefix(k) || FineFrase.paroleNude(v.nome).first.map(Regia.chiave) == k }
    }
    static func nomeDetto(_ detto: String) -> String? { ultimoDi(detto)?.nome }
    static func cosaMessaggio(_ v: VoceRegistro) -> CosaFilo {
        CosaFilo(chiave: "msg:" + v.id.uuidString, tipo: "messaggio", nomi: ["messaggio"], titolo: "Messaggio", riga: "\(Filo.detto(v.nome)): \(v.testo ?? "")",
                 detto: "il messaggio " + Filo.di(v.nome), persona: v.nome, testo: v.testo ?? "", daMandare: v.testo, numero: v.numero, sezione: "Messaggi",
                 quando: v.quando)
    }
    static func numeroNelFilo(_ persona: String) -> String? {
        let k = Regia.chiave(persona)
        if let v = Registro.leggi(RegistroMessaggi.ricevuti).first(where: { Regia.chiave($0.nome) == k }) { return v.numero }
        return Registro.leggi(RegistroMessaggi.mandati).first { Regia.chiave($0.nome) == k }?.numero
    }
    static func contatto(_ detto: String) async -> Contatto? {
        let tutti = await Rubrica.tutti()
        if ["mamma", "miamadre", "madre"].contains(Regia.chiave(detto)) {
            return tutti.first { Regia.chiave($0.nome).contains("mamma") } ?? Regia.scegli(detto, fra: tutti, testo: { $0.nome })
        }
        return Regia.scegli(detto, fra: tutti, testo: { $0.nome })
    }
    static func numero(di nome: String) async -> String? {
        if let n = numeroNelFilo(nome) { return n }
        return await contatto(nome)?.primoNumero
    }

    // MARK: Le parole

    /// La frase per i confronti: minuscola, senza accenti, senza il nome e le cortesie (come la regia), senza «buongiorno» davanti.
    static func norma(_ frase: String) -> String {
        var p = Regia.paroleComando(frase)
        while let f = p.first, ["buongiorno", "buonasera", "ciao", "salve", "veloce", "senti"].contains(f) { p.removeFirst() }
        if p.count >= 2, p[0] == "con", p[1] == "calma" { p.removeFirst(2) }
        if p.count >= 2, p[0] == "al", p[1] == "volo" { p.removeFirst(2) }
        return p.joined(separator: " ")
    }

    /// «o» → m, «a» → f, «i» → m plurale, «e» → f plurale.
    static func pron(_ s: String) -> (genere: Character, plurale: Bool) {
        switch s.last {
        case "a": return ("f", false)
        case "i": return ("m", true)
        case "e": return ("f", true)
        default: return ("m", false)
        }
    }

    /// Il testo detto in forma diretta: «che arrivo alle otto» → «Arrivo alle otto.»
    static func diretto(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        for a in ["che ", "Che "] where s.hasPrefix(a) { s.removeFirst(a.count) }
        guard let primo = s.first else { return s }
        s = String(primo).uppercased() + s.dropFirst()
        return ".!?…".contains(s.last ?? " ") ? s : s + "."
    }

    /// Il testo com'era detto (maiuscole, accenti, apostrofi): dalla parola dove comincia `pezzo` fino in fondo.
    static func testoOriginale(_ frase: String, dopo pezzo: String) -> String {
        let tutte = Regia.paroleComando(frase)
        let p = FineFrase.paroleNude(pezzo)
        guard !p.isEmpty, tutte.count >= p.count else { return pezzo }
        for k in stride(from: tutte.count - p.count, through: 0, by: -1) where Array(tutte[k..<(k + p.count)]) == p {
            return Regia.originale(frase, da: k, a: tutte.count)
        }
        return pezzo
    }
    static func paroleDavanti(_ frase: String, _ pezzo: String) -> Int {
        let tutte = Regia.paroleComando(frase), p = FineFrase.paroleNude(pezzo)
        guard !p.isEmpty, tutte.count >= p.count else { return 0 }
        for k in stride(from: tutte.count - p.count, through: 0, by: -1) where Array(tutte[k..<(k + p.count)]) == p { return k }
        return 0
    }

    static func elenco(_ v: [String]) -> String {
        guard v.count > 1 else { return v.first ?? "" }
        return v.dropLast().joined(separator: ", ") + " e " + (v.last ?? "")
    }

    static func quandoDetto(_ t: Date) -> String {
        let min = Int(Date().timeIntervalSince(t) / 60)
        if min < 2 { return "adesso" }
        if min < 25 { return "\(Battute.numero(min)) minuti fa" }
        if min < 45 { return "mezz'ora fa" }
        if min < 90 { return "un'ora fa" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "alle " + f.string(from: t)
    }

    private static var regole: [String: NSRegularExpression] = [:]
    /// La frase combacia con lo schema? I gruppi (nil quelli vuoti), il primo è tutta la frase.
    static func cerca(_ schema: String, _ s: String) -> [String?]? {
        let re: NSRegularExpression
        if let r = regole[schema] { re = r } else {
            guard let r = try? NSRegularExpression(pattern: schema) else { return nil }
            regole[schema] = r
            re = r
        }
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
    }
}

// MARK: - Il congedo: «Will that be all, Sir?» solo alla fine di una cosa vera

/// Il signore (13 nov): «solo alla fine di una cosa vera, sempre variata, mai insistente». Dopo una cosa vera (un messaggio
/// mandato, un lavoro salvato, più comandi in fila) e 9 secondi di silenzio, JARVIS chiede una volta; al massimo una ogni 15
/// minuti, mai di fretta, mai col lavoro insieme aperto o con qualcosa che aspetta il sì.
@MainActor
final class Congedo {
    static let condiviso = Congedo()
    /// Jarvis: dice la frase con la finestra del seguito aperta dopo (la risposta va senza «Jarvis»).
    var chiedi: ((String) -> Void)?
    /// Jarvis: è in attesa e non sta ascoltando né parlando.
    var inAttesa: (() -> Bool)?
    /// Jarvis: quando il signore ha detto l'ultima frase.
    var ultimaFrase: (() -> Date)?
    private var ultimo = Date.distantPast
    private var compito: Task<Void, Never>?
    private(set) var aperto = Date.distantPast
    /// La domanda fatta: «Sarà tutto, Sir?» (un sì chiude) o «Le serve altro, Sir?» (un no chiude).
    private var domanda = ""

    func cosaVera() {
        compito?.cancel()
        guard Battute.umore != .fretta, Date().timeIntervalSince(ultimo) > 15 * 60 else { return }   // di fretta: niente congedo
        let da = ultimaFrase?() ?? Date()
        compito = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard let self, !Task.isCancelled, !Sessione.condivisa.aperta, Battute.umore != .fretta, self.inAttesa?() == true,
                  (self.ultimaFrase?() ?? da) <= da, Date().timeIntervalSince(self.ultimo) > 15 * 60 else { return }
            self.ultimo = Date()
            self.aperto = Date().addingTimeInterval(10)
            let frase = Battute.congedo()
            self.domanda = frase
            self.chiedi?(frase)
        }
    }

    /// Il signore ha parlato: niente congedo in arrivo.
    func zitto() { compito?.cancel() }

    /// 13.1: la risposta secca al congedo appena chiesto (entro 10 secondi): vero = ha finito, falso = c'è altro; nil = non è una
    /// risposta secca (o non c'è un congedo aperto). «Sarà tutto?», «Will that be all?»: «sì» chiude; «Le serve altro?», «Altro per
    /// lei?», «Posso fare altro?», «C'è altro?»: «no» chiude; «Nient'altro?»: chiudono tutti e due.
    func rispostaSecca(_ nudo: String) -> Bool? {
        guard aperto > Date() else { return nil }
        if ["ok", "okay", "va bene", "a posto", "perfetto", "basta"].contains(nudo) { return true }     // chiudono con qualsiasi domanda
        let si: Set<String> = ["si", "si si", "si sir", "si grazie", "certo", "esatto", "sì"]
        let no: Set<String> = ["no", "no sir", "niente", "nulla", "no no"]
        let risposta: Bool
        if si.contains(nudo) { risposta = true } else if no.contains(nudo) { risposta = false } else { return nil }
        let d = Regia.chiave(domanda)
        if d.contains("niente") || d.contains("nient") { return true }
        let siChiude = d.contains("saratutto") || d.contains("willthatbeall")
        return risposta == siChiude
    }
    func chiuso() { aperto = .distantPast; compito?.cancel() }
}

extension String {
    /// La prima lettera maiuscola («a Bea» → «A Bea»).
    var capitalizzata: String { prefix(1).uppercased() + dropFirst() }
}
#endif
