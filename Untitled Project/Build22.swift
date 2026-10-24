import Foundation
import Combine
import CoreLocation

// Build 22: i pezzi in comune tra iPhone e orologio (questo file è in tutti e due i target).

// MARK: - I toni della voce

/// I toni che il cervello può mettere nel testo per la voce di ElevenLabs («[whispers]», «[sarcastic]», «[serious]»…):
/// servono solo alla voce. A schermo e nella cronologia non compaiono mai (23 ott).
nonisolated enum TagVoce {
    /// Il testo senza i tag tra parentesi quadre e senza lo spazio dopo. Un tag è solo inglese minuscolo («[whispers]»,
    /// «[sarcastic]»: una lettera, poi da 1 a 24 tra lettere minuscole, spazi e trattini) e sta a inizio testo, dopo uno
    /// spazio o dopo un a capo: «array[index]» e «[Nota]» restano come sono.
    /// `inCorso`: la risposta sta ancora arrivando a pezzi; un tag non ancora chiuso in fondo («[whis») non si mostra.
    static func togli(_ testo: String, inCorso: Bool = false) -> String {
        guard testo.contains("[") else { return testo }
        let c = Array(testo)
        var out: [Character] = []
        out.reserveCapacity(c.count)
        var i = 0
        while i < c.count {
            if c[i] == "[", libero(out.last), let fine = chiusura(c, da: i) {
                var j = fine + 1
                let aCapo = out.isEmpty || out.last == "\n"                       // tag da solo in testa a una riga: via anche l'a capo
                while j < c.count, c[j] == " " || c[j] == "\t" || (aCapo && c[j] == "\n") { j += 1 }   // lo spazio dopo il tag
                // dopo il tag c'è punteggiatura o la fine: via anche lo spazio prima («Ciao [laughs].» → «Ciao.»)
                if j >= c.count || c[j] == "\n" || ".,;:!?…)»".contains(c[j]) {
                    while let u = out.last, u == " " || u == "\t" { out.removeLast() }
                }
                i = j
                continue
            }
            out.append(c[i])
            i += 1
        }
        if inCorso, let k = out.lastIndex(of: "["), libero(k > 0 ? out[k - 1] : nil), forseTag(out[(k + 1)...]) {
            out.removeSubrange(k...)
        }
        return String(out)
    }

    /// La posizione della «]» che chiude un tag valido aperto in `i`, altrimenti nil.
    /// «[testo](link)» non è un tag: è un link scritto alla maniera del web e resta com'è.
    private static func chiusura(_ c: [Character], da i: Int) -> Int? {
        var k = i + 1
        while k < c.count, k - i - 1 <= 25, c[k] != "]" { k += 1 }
        guard k < c.count, c[k] == "]", valido(c[(i + 1)..<k]) else { return nil }
        if k + 1 < c.count, c[k + 1] == "(" { return nil }
        return k
    }

    /// Prima della «[» di un tag: l'inizio del testo, uno spazio o un a capo (quello che resta a schermo: dopo un tag tolto
    /// ne può venire subito un altro). Attaccata a una parola («array[index]») non è un tag.
    private static func libero(_ prima: Character?) -> Bool {
        guard let prima else { return true }
        return prima == " " || prima == "\n"
    }

    /// Una lettera inglese minuscola (a…z).
    private static func minuscola(_ c: Character) -> Bool { c.isASCII && c.isLetter && c.isLowercase }

    private static func valido(_ s: ArraySlice<Character>) -> Bool {
        guard s.count >= 2, s.count <= 25, let p = s.first, minuscola(p) else { return false }
        return s.allSatisfy { minuscola($0) || $0 == " " || $0 == "-" }
    }

    /// Un pezzo di tag non ancora chiuso («[», «[whis»): potrebbe diventarlo col prossimo pezzo di testo.
    private static func forseTag(_ s: ArraySlice<Character>) -> Bool {
        guard s.count <= 25 else { return false }
        if let p = s.first, !minuscola(p) { return false }
        return s.allSatisfy { minuscola($0) || $0 == " " || $0 == "-" }
    }
}

// MARK: - Il dialogo: le regole in comune tra iPhone e orologio (revisione del dialogo, 24 ott)

nonisolated enum Dialogo {
    /// La nota «ti ho interrotto mentre rispondevi a…» vale due minuti, poi sparisce (deciso dal signore, 24 ott):
    /// passato quel tempo, quello che dice è una domanda nuova.
    static let validitaInterruzione: TimeInterval = 120
    /// «Aspetta» e poi silenzio: dopo 5 secondi JARVIS dice «Mi dica, Sir» e lo ascolta (deciso dal signore, 24 ott).
    static let silenzioDopoAspetta: TimeInterval = 5
    static let miDica = "Mi dica, Sir."
    /// Subito dopo una domanda JARVIS ascolta ancora per 2 secondi un'aggiunta («…e anche domani»), senza «Jarvis»;
    /// il riempitivo («Un attimo, Sir») parte solo dopo (deciso dal signore, 24 ott).
    static let finestraAggiunta: TimeInterval = 2
    /// Finita una risposta, per 4 secondi il seguito vale anche senza «Jarvis» («Perché?», «E domani?»), come tra due persone.
    static let finestraSeguito: TimeInterval = 4

    // MARK: Il punto dell'interruzione

    /// La risposta interrotta come la rilegge il cervello nei turni dopo: quello che il signore ha sentito, la nota con il punto
    /// esatto del taglio, poi il resto che non ha sentito. Così con «continua», «dicevi?» riprende da lì, senza ripetere.
    /// `detto`: le frasi dette per intero prima dell'interruzione (vuoto: non aveva ancora cominciato a parlare).
    /// Le note cominciano come le aspetta il cervello: «(qui il signore mi ha interrotto…» e «(il signore mi ha interrotto prima che cominciassi…».
    static func rispostaInterrotta(_ testo: String, detto: String) -> String {
        let tutto = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentito = TagVoce.togli(detto).trimmingCharacters(in: .whitespacesAndNewlines)
        if sentito.isEmpty {
            let nota = "(il signore mi ha interrotto prima che cominciassi a parlare: non ha sentito nulla)"
            return tutto.isEmpty ? nota : "\(nota) \(tutto)"
        }
        let nota = "(qui il signore mi ha interrotto: il resto non l'ho detto)"
        guard let k = taglio(tutto, dopo: sentito) else { return "\(sentito) \(nota)" }
        let prima = tutto[..<k].trimmingCharacters(in: .whitespacesAndNewlines)
        let resto = tutto[k...].trimmingCharacters(in: .whitespacesAndNewlines)
        return resto.isEmpty ? "\(prima) \(nota)" : "\(prima) \(nota) \(resto)"
    }

    /// Dove finisce, dentro `testo`, la parte già detta. Contano solo lettere e cifre: spazi, a capo e punteggiatura
    /// possono cambiare fra le frasi dette una per una e il testo intero. Nil se il detto non è l'inizio del testo.
    static func taglio(_ testo: String, dopo detto: String) -> String.Index? {
        let voluti = detto.compactMap { c -> String? in c.isLetter || c.isNumber ? String(c).lowercased() : nil }
        guard !voluti.isEmpty else { return nil }
        var k = 0
        var i = testo.startIndex
        while i < testo.endIndex {
            let c = testo[i]
            i = testo.index(after: i)
            guard c.isLetter || c.isNumber else { continue }
            guard String(c).lowercased() == voluti[k] else { return nil }
            k += 1
            if k == voluti.count {
                // la punteggiatura attaccata all'ultima parola detta («…domani piove.») resta con la parte detta
                while i < testo.endIndex, !testo[i].isWhitespace, !testo[i].isLetter, !testo[i].isNumber { i = testo.index(after: i) }
                return i
            }
        }
        return nil
    }

    // MARK: L'eco sull'orologio

    /// Orologio: la frase con cui il signore interrompe JARVIS è registrata dallo stesso microfono che sentiva la sua voce.
    /// Toglie dall'inizio della trascrizione le parole di JARVIS (nell'ordine in cui le diceva): resta solo il signore.
    static func togliEco(_ sentito: String, detto: String) -> String {
        func norma(_ s: Substring) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
        }
        let separa: (Character) -> Bool = { !$0.isLetter && !$0.isNumber && $0 != "'" }
        let d = TagVoce.togli(detto).split(whereSeparator: separa).map(norma)
        let s = sentito.split(whereSeparator: separa)
        guard !d.isEmpty, !s.isEmpty else { return sentito }
        var i = 0, j = 0, fine = 0
        var saltata = false
        while i < s.count, j < d.count {
            if let k = d[j..<min(d.count, j + 4)].firstIndex(of: norma(s[i])) {
                j = k + 1; i += 1; fine = i; saltata = false
                continue
            }
            // una parola dell'eco capita male: la salto se quella dopo torna a combaciare
            if !saltata, i + 1 < s.count, d[j..<min(d.count, j + 5)].contains(norma(s[i + 1])) { saltata = true; i += 1; continue }
            break
        }
        guard fine > 0 else { return sentito }
        guard fine < s.count else { return "" }
        return String(sentito[s[fine].startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sottovoce

    enum CambioVoce: Equatable { case sottovoce, normale }

    /// «Piano» / «sottovoce» (risponde sottovoce per 10 minuti) e «voce normale» (torna come prima): uguali su iPhone e orologio.
    /// Restituisce la frase senza il comando e il cambio da fare (nil: nessun comando, la frase resta com'è).
    /// Revisione del dialogo (24 ott): prima bastava «piano» fra le prime cinque parole (tre sull'orologio), e «qual è il piano
    /// per stasera?» accendeva il sottovoce e perdeva la parola; «ma è una voce normale?» spariva come se fosse un ordine.
    /// Ora «piano» vale in testa alla frase («piano, che ore sono», «Jarvis, piano…») o dopo «parla», «rispondi», «più»
    /// («parla piano»); «sottovoce» dove stava già (fra le prime cinque parole); «voce normale» solo se non è dentro un discorso.
    static func volume(_ frase: String) -> (resto: String, cambio: CambioVoce?) {
        let parole = frase.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let p = parole.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        // «voce normale»: un ordine («Jarvis, voce normale», «torna alla voce normale»), non un discorso («ma è una voce normale?»)
        if frase.count < 40 {
            let unita = " " + p.joined(separator: " ") + " "
            let discorso: Set<String> = ["è", "era", "sembra", "sembrava", "una", "un", "ha", "hai", "ho", "sei", "come", "che", "non",
                                         "perché", "perche", "mai", "cosa", "quale"]
            for ordine in ["voce normale", "parla normale", "alza la voce", "torna normale"] {
                guard let r = unita.range(of: " " + ordine + " ") else { continue }
                if !unita[..<r.lowerBound].split(separator: " ").contains(where: { discorso.contains(String($0)) }) { return ("", .normale) }
            }
        }
        let nomi = ["jarvi", "giarvi", "giàrvi", "jervis", "charvis", "jarves", "jarbis"]
        var inizio = 0                                   // la frase vera comincia dopo «Jarvis», «ehi», «ok»
        while inizio < p.count, nomi.contains(where: { p[inizio].hasPrefix($0) }) || ["ehi", "hey", "ok", "okay"].contains(p[inizio]) { inizio += 1 }
        let verbiVoce: Set<String> = ["parla", "parlami", "rispondi", "rispondimi"]
        // «piano» seguito da queste parole è un nome o un avverbio, non l'ordine: «piano terra», «piano piano», «piano B»
        let nonOrdine: Set<String> = ["piano", "terra", "terreno", "primo", "secondo", "terzo", "superiore", "inferiore", "di", "del", "della",
                                      "dei", "delle", "per", "b", "a", "è", "e", "era", "sarà", "sara", "bar", "forte", "regolatore"]
        for k in 0..<min(p.count, 5) where p[k] == "piano" || p[k] == "sottovoce" {
            var togli: Set<Int> = [k]
            var j = k - 1
            if j >= 0, ["più", "piu"].contains(p[j]) { togli.insert(j); j -= 1 }          // «parla più piano»
            let dopoVerbo = j >= 0 && verbiVoce.contains(p[j])
            if dopoVerbo { togli.insert(j) }                                                 // «parla piano»: via anche «parla»
            if p[k] == "piano" && !dopoVerbo && !togli.contains(k - 1) {
                guard k == inizio else { continue }                                          // «qual è il piano per stasera?»
                let chiuso = k + 1 == p.count || [",", ":", ";", "!", "."].contains(where: { parole[k].hasSuffix($0) })
                if !chiuso, nonOrdine.contains(p[k + 1]) { continue }                       // «piano terra», «piano piano»
            }
            let resto = parole.enumerated().filter { !togli.contains($0.offset) }.map(\.element).joined(separator: " ")
            return (resto.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!")), .sottovoce)
        }
        return (frase, nil)
    }
}

// MARK: - I comandi a frase esatta

/// I protocolli alla Stark (la tendina PROTOCOLLI), deciso dal signore il 24 ott: solo le luci. «Avvia» le accende tutte,
/// ogni luce è un interruttore (spenta = quel passo disattivato). L'app Comandi non si apre e JARVIS non parla.
nonisolated enum Protocollo: String, CaseIterable, Identifiable, Hashable, Sendable {
    case lavoro, rientro, notte
    var id: String { rawValue }
    /// Come si legge sulla scheda: LAVORO, RIENTRO, NOTTE.
    var titolo: String { rawValue.uppercased() }

    /// Un passo del protocollo: `chiave` per riconoscere la sua luce, `testo` sull'iPhone, `breve` sul polso.
    nonisolated struct Passo: Sendable { let chiave: String; let testo: String; let breve: String }

    var passi: [Passo] {
        switch self {
        case .lavoro:
            return [Passo(chiave: "full-immersion-lavoro", testo: "Full immersion «Lavoro» accesa", breve: "Full immersion Lavoro"),
                    Passo(chiave: "wifi", testo: "Wi-Fi acceso", breve: "Wi-Fi"),
                    Passo(chiave: "impegni", testo: "Impegni di oggi", breve: "Impegni di oggi"),
                    Passo(chiave: "posta", testo: "Posta PRIORITÀ", breve: "Posta PRIORITÀ")]
        case .rientro:
            return [Passo(chiave: "full-immersion-spenta", testo: "Full immersion spenta", breve: "Full immersion spenta"),
                    Passo(chiave: "wifi", testo: "Wi-Fi acceso", breve: "Wi-Fi"),
                    Passo(chiave: "messaggi", testo: "Messaggi da leggere", breve: "Messaggi"),
                    Passo(chiave: "meteo", testo: "Meteo di domani", breve: "Meteo domani")]
        case .notte:
            return [Passo(chiave: "full-immersion-riposo", testo: "Full immersion «Riposo» accesa", breve: "Full immersion Riposo"),
                    Passo(chiave: "bluetooth", testo: "Bluetooth spento", breve: "Bluetooth spento"),
                    Passo(chiave: "sveglia", testo: "Sveglia alle 9:30", breve: "Sveglia 9:30"),
                    Passo(chiave: "diario", testo: "Domanda del diario", breve: "Diario")]
        }
    }
}

/// I comandi a frase esatta (dopo «Jarvis»): riconosciuti sul dispositivo prima di ogni altro comando e prima delle
/// storpiature imparate. Risposta immediata, niente cervello, e non si imparano mai come storpiature.
nonisolated enum ComandoDedicato: Equatable, Sendable {
    case protocollo(Protocollo)   // «protocollo lavoro», «attiva il protocollo notte»: la tendina PROTOCOLLI, e parte
    case traccia                  // «traccia il luogo»: Ricordi › TRACCIA (la bussola, fotocamera spenta)
    case guida                    // «portami al luogo»: Ricordi › TRACCIA con la Guida accesa (fotocamera e frecce)
    case salvaLuogo               // «ricorda questo luogo»: Ricordi › TRACCIA, e il posto dove si trova diventa un luogo
    case radar                    // «radar pioggia»: Meteo › RADAR
    case priorita                 // «rapporto posta»: Email › PRIORITÀ
    case organismo                // «scansione organismo», «stato dell'organismo»: Vitals (sull'orologio l'Organismo)
    case specchio                 // «modalità specchio»: Allenatore, sullo Specchio
    case allenamento              // «allenamento allo specchio»: Allenatore, sullo Specchio
    case satellite(AzioneSatellite)   // build 23: «guidami allo studio», «mostrami la strada per il locale», «ricognizione su Via Savona», «mostrami lo studio in 3D»
    case fermaGuida               // build 23: «ferma la guida» (la GUIDA di SATELLITE, anche a Satellite chiuso)

    static func riconosci(_ frase: String) -> ComandoDedicato? {
        var t = frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        // le stesse parole con gli accenti e le lettere di prima: servono per i nomi e gli indirizzi detti («Via Perù»)
        var o = frase.lowercased()
            .replacingOccurrences(of: "[^\\p{L}\\p{N} ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        while let p = t.first, ["ehi", "ok", "hey", "jarvis", "giarvis", "jervis"].contains(p) { t.removeFirst(); if !o.isEmpty { o.removeFirst() } }
        if o.count != t.count { o = t }
        if let s = satellite(t, originale: o) { return s }
        // «protocollo notte», anche con attiva / avvia / esegui / lancia davanti («avvia il protocollo notte»)
        var p = t
        if let v = p.first, ["attiva", "avvia", "esegui", "lancia"].contains(v) {
            p.removeFirst()
            if p.first == "il" { p.removeFirst() }
        }
        if p.count == 2, p[0] == "protocollo" {
            switch p[1] {
            case "lavoro": return .protocollo(.lavoro)
            case "rientro": return .protocollo(.rientro)
            case "notte": return .protocollo(.notte)
            default: return nil
            }
        }
        switch t.joined(separator: " ") {
        case "traccia il luogo": return .traccia
        case "portami al luogo": return .guida
        case "ricorda questo luogo", "salva questo luogo": return .salvaLuogo
        case "radar pioggia": return .radar
        case "rapporto posta": return .priorita
        case "scansione organismo", "stato dell organismo": return .organismo
        case "modalita specchio": return .specchio
        case "allenamento allo specchio", "allenati allo specchio": return .allenamento
        default: return nil
        }
    }

    /// Build 23, SATELLITE: le frasi con un luogo o un indirizzo dentro. `t` sono le parole senza accenti, `o` le stesse
    /// come sono state dette (per il nome). Solo frasi che cominciano così: il resto della frase è il luogo.
    private static func satellite(_ t: [String], originale o: [String]) -> ComandoDedicato? {
        let frase = t.joined(separator: " ")
        if ["ferma la guida", "ferma guida", "fine guida", "fine della guida", "stop guida", "termina la guida", "interrompi la guida"].contains(frase) {
            return .fermaGuida
        }
        guard t.count >= 2, t.count <= 12 else { return nil }
        /// Il luogo dopo le prime `da` parole, saltando le preposizioni in `preposizioni` (al massimo due: «fino al»).
        func luogo(da: Int, preposizioni: Set<String>, fino: Int? = nil) -> String? {
            var k = da
            var salti = 0
            while k < t.count, salti < 2, preposizioni.contains(t[k]) { k += 1; salti += 1 }
            let f = fino ?? t.count
            // l'articolo davanti al nome non fa parte del nome («per il locale» → «Locale»)
            if k + 1 < f, ["il", "lo", "la", "l", "i", "gli", "le"].contains(t[k]) { k += 1 }
            guard k < f else { return nil }
            return ComandoDedicato.maiuscole(Array(o[k..<f]))
        }
        let verso: Set<String> = ["a", "al", "allo", "alla", "all", "ai", "agli", "alle", "da", "dal", "dallo", "dalla", "dai", "verso", "fino", "per"]
        // «guidami allo studio», «guidami verso il locale», «guidami fino a Piazza Duomo»
        if t[0] == "guidami", let n = luogo(da: 1, preposizioni: verso) { return .satellite(.guida(n)) }
        // «mostrami la strada per il locale», «fammi vedere la strada per lo studio», «mostrami il percorso verso casa di Luca»
        for inizio in [["mostrami", "la", "strada"], ["fammi", "vedere", "la", "strada"], ["mostrami", "il", "percorso"]] where t.starts(with: inizio) {
            if let n = luogo(da: inizio.count, preposizioni: verso) { return .satellite(.naviga(n)) }
        }
        // «ricognizione su Via Savona», «fai una ricognizione su Via Tortona 12»
        let sopra: Set<String> = ["su", "sul", "sullo", "sulla", "sull", "sui", "sopra", "a", "al", "alla", "in", "di", "del", "della"]
        for inizio in [["ricognizione"], ["fai", "una", "ricognizione"], ["fammi", "una", "ricognizione"]] where t.starts(with: inizio) {
            if let n = luogo(da: inizio.count, preposizioni: sopra) { return .satellite(.ricognizione(n)) }
        }
        // «mostrami lo studio in 3D», «fammi vedere il locale in tre D»
        let fine: [[String]] = [["in", "3d"], ["in", "3", "d"], ["in", "tre", "d"], ["in", "tre", "di"]]
        for inizio in [["mostrami"], ["fammi", "vedere"]] where t.starts(with: inizio) {
            for coda in fine where t.count > inizio.count + coda.count && Array(t.suffix(coda.count)) == coda {
                if let n = luogo(da: inizio.count, preposizioni: [], fino: t.count - coda.count) { return .satellite(.mostra(n)) }
            }
        }
        return nil
    }

    /// «via savona 20» → «Via Savona 20»: le iniziali maiuscole, tranne le parole piccole in mezzo («Corso di Porta Romana»).
    static func maiuscole(_ parole: [String]) -> String {
        let piccole: Set<String> = ["di", "del", "dello", "della", "dei", "degli", "delle", "da", "dal", "dalla", "e", "a", "al", "alla", "in", "su", "sul", "sulla", "con", "per"]
        return parole.enumerated().map { k, p in
            (k > 0 && piccole.contains(p)) ? p : p.prefix(1).uppercased() + p.dropFirst()
        }.joined(separator: " ")
    }
}

// MARK: - TRACCIA: la strada verso un luogo salvato

nonisolated enum Rotta {
    /// Il rilevamento da un punto all'altro, in gradi dal nord (0…360).
    static func rilevamento(lat: Double, lon: Double, versoLat: Double, versoLon: Double) -> Double {
        let f1 = lat * .pi / 180, f2 = versoLat * .pi / 180, dl = (versoLon - lon) * .pi / 180
        let y = sin(dl) * cos(f2)
        let x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl)
        let g = atan2(y, x) * 180 / .pi
        return (g + 360).truncatingRemainder(dividingBy: 360)
    }

    /// La distanza in metri tra due punti (formula dell'emisenoverso).
    static func metri(lat: Double, lon: Double, versoLat: Double, versoLon: Double) -> Double {
        let r = 6_371_000.0
        let f1 = lat * .pi / 180, f2 = versoLat * .pi / 180
        let df = (versoLat - lat) * .pi / 180, dl = (versoLon - lon) * .pi / 180
        let a = sin(df / 2) * sin(df / 2) + cos(f1) * cos(f2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// Di quanti gradi girarsi per avere la meta davanti: da −180 a 180, positivo = a destra.
    static func relativa(rilevamento: Double, direzione: Double) -> Double {
        var x = (rilevamento - direzione).truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 } else if x < -180 { x += 360 }
        return x
    }

    /// «NE · 32°»: la direzione in cui guarda il dispositivo.
    static func bussola(_ gradi: Double) -> String {
        let punti = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let g = (gradi.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return "\(punti[Int((g + 22.5) / 45) % 8]) · \(Int(g.rounded()) % 360)°"
    }

    /// «180 m», «1,2 km».
    static func distanza(_ m: Double) -> String {
        if m < 1000 { return "\(Int(m.rounded())) m" }
        return (m / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "it_IT"))) + " km"
    }

    /// A piedi, a 80 metri al minuto: «circa 2 minuti».
    static func aPiedi(_ m: Double) -> String {
        let minuti = max(1, Int((m / 80).rounded()))
        if minuti == 1 { return "circa 1 minuto" }
        if minuti < 60 { return "circa \(minuti) minuti" }
        return minuti % 60 == 0 ? "circa \(minuti / 60) h" : "circa \(minuti / 60) h \(minuti % 60) min"
    }
}

/// Posizione e direzione del dispositivo, solo mentre TRACCIA è aperta (iPhone e orologio).
@MainActor
final class Bussola: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var lat: Double?
    @Published private(set) var lon: Double?
    /// Dove guarda il dispositivo, in gradi dal nord (nil: niente bussola, per esempio sul Mac).
    @Published private(set) var direzione: Double?
    private let gestore = CLLocationManager()

    override init() {
        super.init()
        gestore.delegate = self
        gestore.desiredAccuracy = kCLLocationAccuracyBest
        gestore.distanceFilter = 2
        gestore.headingFilter = 2
    }

    func accendi() {
        if gestore.authorizationStatus == .notDetermined { gestore.requestWhenInUseAuthorization() }
        gestore.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { gestore.startUpdatingHeading() }
    }

    func spegni() {
        gestore.stopUpdatingLocation()
        gestore.stopUpdatingHeading()
    }

    /// Il rilevamento verso la meta e la distanza, se la posizione c'è già.
    func verso(lat mLat: Double, lon mLon: Double) -> (rilevamento: Double, metri: Double)? {
        guard let lat, let lon else { return nil }
        return (Rotta.rilevamento(lat: lat, lon: lon, versoLat: mLat, versoLon: mLon), Rotta.metri(lat: lat, lon: lon, versoLat: mLat, versoLon: mLon))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        let a = l.coordinate.latitude, b = l.coordinate.longitude
        Task { @MainActor in self.lat = a; self.lon = b }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let g = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.direzione = g }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

// MARK: - RADAR: la pioggia in arrivo (dal cervello, azione «radar»)

nonisolated struct DatiRadar: Equatable, Sendable {
    let piove: Bool
    let iniziaMin: Int
    let mm30: Double
    let smette: String
    /// Il cervello non ha potuto guardare il radar e dice perché (es. «Non so dove si trova, Sir: serve la posizione dell'iPhone.»).
    let errore: String?

    /// Dalla risposta del cervello: { piove, inizia_min, mm_30, smette } oppure { errore }. nil se non è una risposta del radar.
    init?(_ o: [String: Any]) {
        guard let p = o["piove"] as? Bool else {
            guard let e = (o["errore"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty else { return nil }
            piove = false; iniziaMin = 0; mm30 = 0; smette = ""; errore = e
            return
        }
        errore = nil
        piove = p
        iniziaMin = (o["inizia_min"] as? NSNumber)?.intValue ?? 0
        mm30 = (o["mm_30"] as? NSNumber)?.doubleValue ?? 0
        smette = (o["smette"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// «fra 15 minuti», «adesso».
    var inizia: String {
        if iniziaMin <= 0 { return "adesso" }
        if iniziaMin == 1 { return "fra 1 minuto" }
        if iniziaMin < 60 { return "fra \(iniziaMin) minuti" }
        return iniziaMin % 60 == 0 ? "fra \(iniziaMin / 60) h" : "fra \(iniziaMin / 60) h \(iniziaMin % 60) min"
    }

    /// «2,4».
    var millimetri: String { mm30.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "it_IT"))) }

    /// L'avviso in testa al pannello RADAR dell'iPhone.
    var avviso: String {
        let quando = iniziaMin <= 0 ? "Signore, piove già dove si trova" : "Signore, pioggia \(inizia) dove si trova"
        return "\(quando): \(millimetri) mm nella prossima mezz'ora. Prenda l'ombrello."
    }

    /// L'avviso sul polso, più corto.
    var avvisoBreve: String {
        iniziaMin <= 0 ? "Signore, piove già dove si trova. Prenda l'ombrello." : "Signore, pioggia \(inizia) dove si trova. Prenda l'ombrello."
    }
}

// MARK: - PRIORITÀ: la posta che conta (dal cervello, azioni «posta_priorita» e «posta_rispondi»)

nonisolated struct MailImportante: Identifiable, Equatable, Sendable {
    let id: String
    let idNumero: Int?          // se il cervello ha mandato l'id come numero, torna come numero
    let mittente: String
    let oggetto: String
    let quando: String
    let riassunto: String
    /// Con `serveRisposta` è la risposta proposta da JARVIS; senza, una nota breve («Nessuna risposta: era lei»).
    let risposta: String?
    let serveRisposta: Bool

    /// Il corpo per il cervello: { "posta_rispondi": { "id": …, "testo": … } }.
    func corpoRisposta(_ testo: String) -> [String: Any] {
        let id: Any = idNumero.map { $0 as Any } ?? self.id
        return ["posta_rispondi": ["id": id, "testo": testo] as [String: Any]]
    }
}

nonisolated struct PostaPriorita: Equatable, Sendable {
    let importanti: [MailImportante]
    let altreConteggio: Int
    let altreNota: String

    /// Dalla risposta del cervello: { importanti: [...], altre: { conteggio, nota } }. nil se non è quella risposta.
    init?(_ o: [String: Any]) {
        guard let lista = o["importanti"] as? [[String: Any]] else { return nil }
        importanti = lista.compactMap { d in
            let numero = d["id"] as? NSNumber
            guard let id = (d["id"] as? String) ?? numero?.stringValue else { return nil }
            let r = (d["risposta"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return MailImportante(id: id, idNumero: d["id"] is String ? nil : numero?.intValue,
                                  mittente: d["mittente"] as? String ?? "", oggetto: d["oggetto"] as? String ?? "",
                                  quando: d["quando"] as? String ?? "", riassunto: d["riassunto"] as? String ?? "",
                                  risposta: (r?.isEmpty ?? true) ? nil : r, serveRisposta: (d["serve_risposta"] as? Bool) ?? false)
        }
        let altre = o["altre"] as? [String: Any] ?? [:]
        altreConteggio = (altre["conteggio"] as? NSNumber)?.intValue ?? 0
        altreNota = (altre["nota"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La risposta proposta senza le virgolette «», per mostrarla e modificarla.
    static func senzaVirgolette(_ t: String) -> String {
        t.trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“” \n"))
    }
}
