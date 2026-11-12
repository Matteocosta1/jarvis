import Foundation
import AVFoundation

// MARK: - 11 nov · Il dialogo vivo (analisi del dialogo, approvata dal signore: «fai le cose perfette»)
// Due pezzi piccoli che servono all'ascolto per capire quando il signore ha davvero finito di parlare:
// - VoceAttiva: il suono della sua voce nel microfono, non solo le parole trascritte (che in una sessione lunga arrivano a scatti);
// - RitmoSignore: il suo ritmo. Se riprende spesso a parlare subito dopo che JARVIS ha chiuso la frase, JARVIS impara ad aspettare
//   un po' di più; se no, torna piano piano ai tempi normali.
// 12 nov (revisione del dialogo, build 12.0 (9)): qui stanno anche le regole di fine frase (FineFrase) e l'intonazione (Intonazione),
// così il controllo di compilazione le prova da sole a ogni build (.github/prove/ProvaDialogo.swift).

/// La voce nel microfono, ascoltata dal suono: ogni pezzo di audio (circa 20-40 ms) si misura e si confronta con il rumore di
/// fondo, che si adatta da solo alla stanza (scende subito nel silenzio, sale piano col rumore costante: frigo, strada, TV bassa).
/// Scritto dal thread del microfono, letto dal thread principale.
nonisolated final class VoceAttiva: @unchecked Sendable {
    static let condivisa = VoceAttiva()

    private let lock = NSLock()
    private var fondo: Float = -60          // il rumore di fondo della stanza, in decibel
    private var ultimaVoce: TimeInterval = 0
    private var pronta = false              // il fondo si è assestato (qualche pezzo di audio dopo l'azzeramento)
    private var pezzi = 0
    private var sommaForza: Float = 0       // 12 nov (A3): quanto la voce sta sopra il fondo, sommato sui pezzi di voce
    private var pezziVoce = 0

    private static var ora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Un ascolto nuovo: il fondo si rimisura da capo (la stanza può essere cambiata).
    func azzera() {
        lock.lock()
        fondo = -60; ultimaVoce = 0; pronta = false; pezzi = 0; sommaForza = 0; pezziVoce = 0
        lock.unlock()
        Intonazione.condivisa.azzera()
    }

    /// 12 nov (errore 3): una frase nuova sul microfono sempre acceso del richiamo. Il fondo della stanza resta quello (rimisurarlo
    /// mentre il signore parla lo alzerebbe fino alla sua voce); ripartono solo la forza della voce e l'intonazione di questa frase.
    func iniziaFrase() {
        lock.lock()
        sommaForza = 0; pezziVoce = 0
        lock.unlock()
        Intonazione.condivisa.iniziaFrase(da: VoceAttiva.ora - 2.5)    // dentro c'è anche «Jarvis» e l'inizio della domanda
    }

    /// Un pezzo di audio del microfono.
    func misura(_ b: AVAudioPCMBuffer) {
        guard let canale = b.floatChannelData?[0], b.frameLength > 0 else { return }
        let n = Int(b.frameLength)
        var somma: Float = 0
        for i in stride(from: 0, to: n, by: 2) { somma += canale[i] * canale[i] }
        let db = 20 * log10(max((somma / Float((n + 1) / 2)).squareRoot(), 0.000_01))
        let t = VoceAttiva.ora
        var voce = false
        lock.lock()
        pezzi += 1
        if !pronta { fondo = pezzi == 1 ? db : min(fondo, db); if pezzi >= 6 { pronta = true } }
        else if db < fondo { fondo = fondo * 0.7 + db * 0.3 }            // nel silenzio il fondo scende subito
        else { fondo += (db - fondo) * 0.004 }                            // col rumore costante sale piano
        // voce: ben sopra il fondo (9 dB) e non un sussurro dell'ambiente (-50 dB)
        if pronta, db > fondo + 9, db > -50 { ultimaVoce = t; sommaForza += db - fondo; pezziVoce += 1; voce = true }
        lock.unlock()
        // 12 nov (P3): l'altezza della voce, solo mentre il signore parla
        Intonazione.condivisa.ascolta(canale, n: n, hz: b.format.sampleRate, voce: voce, tempo: t)
    }

    /// 12 nov (A3): di quanti decibel, in media, la voce di questo ascolto stava sopra il rumore della stanza (nil: troppo poca voce).
    var forzaMedia: Double? {
        lock.lock(); defer { lock.unlock() }
        return pezziVoce >= 15 ? Double(sommaForza / Float(pezziVoce)) : nil
    }

    /// Da quanti secondi il microfono non sente la voce (grande se non l'ha mai sentita).
    var secondiDiSilenzio: Double {
        lock.lock(); defer { lock.unlock() }
        return ultimaVoce == 0 ? 999 : VoceAttiva.ora - ultimaVoce
    }
}

/// Il ritmo del signore: un moltiplicatore delle pause di fine frase, da 1 (i tempi normali) a 1,5.
/// Sale quando il signore riprende a parlare subito dopo che JARVIS ha chiuso la frase (l'«aggiunta»: era stato tagliato),
/// scende piano a ogni frase chiusa bene. Resta sul telefono.
@MainActor
final class RitmoSignore {
    static let condiviso = RitmoSignore()
    private let chiave = "ritmoSignore11nov"
    private(set) var fattore: Double

    private init() {
        let v = UserDefaults.standard.double(forKey: chiave)
        fattore = v >= 1 && v <= 1.5 ? v : 1
    }

    /// Era stato tagliato: la prossima volta un po' più di pazienza.
    func ripresa() { cambia(fattore + 0.08) }

    /// Una frase chiusa bene: si torna piano verso i tempi normali.
    func fraseChiusaBene() { cambia(fattore - 0.01) }

    private func cambia(_ v: Double) {
        fattore = min(1.5, max(1, v))
        UserDefaults.standard.set(fattore, forKey: chiave)
    }
}

/// 12 nov (A3, piano del dialogo approvato dal signore): come parla il signore in questa frase, rispetto al suo solito.
/// Velocità (parole al secondo), forza della voce sopra il fondo della stanza ed esitazioni (parole ripetute, «ehm», «cioè»).
/// Il suo solito si impara qui, sul telefono, frase dopo frase; finché non conosce il suo solito (8 frasi) dice solo le esitazioni.
/// La riga va al cervello («[Come parla: …]») per scegliere il registro: più calmo se è agitato, più leggero se è allegro.
@MainActor
final class ComeParla {
    static let condiviso = ComeParla()
    private let chiave = "comeParla12nov"
    private var velocita: Double
    private var forza: Double
    private var campioni: Int

    private init() {
        let d = UserDefaults.standard.dictionary(forKey: chiave) ?? [:]
        velocita = d["velocita"] as? Double ?? 0
        forza = d["forza"] as? Double ?? 0
        campioni = d["campioni"] as? Int ?? 0
    }

    /// La riga per il cervello (nil: niente di notevole). `segnali`: quello che ha sentito il classificatore dei suoni
    /// (P2, 12 nov: «ha appena riso», «ha sospirato», «sussurra»).
    func riga(testo: String, secondi: Double, forzaDb: Double?, segnali: [String] = []) -> String? {
        let parole = testo.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
        var note: [String] = []
        if campioni >= 8 {
            var veloce = false, lento = false
            if parole >= 5, secondi > 1 {
                let v = Double(parole) / secondi
                if v > velocita * 1.25 { note.append("più veloce del solito"); veloce = true }
                else if v < velocita * 0.75 { note.append("più lento del solito"); lento = true }
            }
            // 12 nov (errore 13): la forza della voce dipende anche da quanto è lontano dal telefono. Conta solo insieme alla velocità:
            // forte e veloce (agitato, entusiasta), piano e lento (stanco, giù). Da sola faceva sembrare giù chi era solo lontano
            if let f = forzaDb {
                if veloce, f > forza + 5 { note.append("voce più forte del solito") }
                else if lento, f < forza - 5 { note.append("voce più bassa del solito") }
            }
        }
        if FineFrase.esitazioni(testo) >= 2 { note.append("esita (ripete parole, «ehm», «cioè»)") }
        note.append(contentsOf: segnali)
        return note.isEmpty ? nil : note.joined(separator: ", ")
    }

    /// Una frase finita: il suo solito si aggiorna piano (media mobile).
    func impara(testo: String, secondi: Double, forzaDb: Double?) {
        let parole = testo.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
        guard parole >= 5, secondi > 1 else { return }
        let v = Double(parole) / secondi
        guard v > 0.5, v < 7 else { return }
        let peso = campioni < 8 ? 1 / Double(campioni + 1) : 0.1
        velocita += (v - velocita) * peso
        if let f = forzaDb { forza = forza == 0 ? f : forza + (f - forza) * peso }
        campioni += 1
        UserDefaults.standard.set(["velocita": velocita, "forza": forza, "campioni": campioni] as [String: Any], forKey: chiave)
    }
}

// MARK: - 12 nov · Quando la frase è finita (revisione del dialogo, build 12.0 (9))

/// Le regole con cui JARVIS decide quanto silenzio aspettare prima di rispondere, come farebbe una persona che ascolta: conta cosa
/// è stato detto (le parole), come (esitazioni) e come è finita la voce (intonazione). Solo testo e numeri: si provano da sole.
nonisolated enum FineFrase {
    /// Le parole su cui chi parla si ferma a metà: articoli, preposizioni, congiunzioni, pronomi, ausiliari, intercalari.
    static let paroleSospese: Set<String> = ["e", "ed", "o", "ma", "che", "perché", "poi", "di", "del", "della", "dei", "delle", "a", "al",
                                             "alla", "ai", "da", "dal", "dalla", "in", "nel", "nella", "con", "per", "su", "sul", "tra", "fra",
                                             "il", "lo", "la", "i", "gli", "le", "un", "una", "uno", "mi", "ti", "ci", "si", "se", "quando",
                                             "dove", "come", "anche", "quindi", "cioè", "tipo", "ehm", "eh", "mmm", "allora", "praticamente",
                                             "comunque", "però", "mentre", "oppure", "magari", "sono", "è", "ho", "hai", "abbiamo", "volevo",
                                             "vorrei", "devo", "dobbiamo", "questo", "questa", "quel", "quella", "mio", "mia", "tuo", "tua"]

    /// Le parole di una frase, minuscole, senza punteggiatura (l'apostrofo resta: «c'è», «com'è»).
    static func parole(_ testo: String) -> [String] {
        testo.replacingOccurrences(of: "’", with: "'").lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    /// Quanto silenzio aspettare prima di considerare finita la frase, come farebbe una persona che ascolta:
    /// non conta solo il silenzio ma cosa è stato detto.
    /// - «che tempo fa oggi?», «sì», «apri la Sentinella»: la frase è chiusa, si risponde quasi subito;
    /// - «oggi ero a Bari…», «allora, ti racconto…»: è un racconto, chi parla di solito continua; si aspetta di più;
    /// - «…e», «…perché», «…ehm»: si è fermato a metà, sta pensando; si aspetta ancora di più.
    /// Revisione del dialogo (24 ott): stessa tabella di tempi, ma nell'ordine giusto. Prima il «?» veniva dopo la frase
    /// sospesa, e «Che ore sono?», «Chi è?», «Perché?» aspettavano 2,4 s («sono», «è», «perché» sembravano parole a metà);
    /// «No, aspetta», «Ok senti» erano prese per risposte brevi e tagliate a 0,6 s.
    /// 12 nov (errore 1): tolta la regola «ultima parola ripetuta = 2,4 s». In italiano raddoppiare è normale («sì sì», «no no»,
    /// «ok ok», «piano piano»: aspettavano 2,4 s invece di 0,6); chi cerca la parola ripete le parole piccole («che che», «delle
    /// delle»), che sono già fra le parole sospese. `nomi`: il nome di JARVIS come lo storpia il riconoscimento (si toglie davanti).
    static func pausa(_ testo: String, nomi: [String]) -> Double {
        let basso = testo.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "’", with: "'").lowercased()
        var parole = basso.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        // il nome o un richiamo davanti non fa parte della frase («Jarvis, apri il meteo» è un comando come «apri il meteo»)
        while let p = parole.first, ["ehi", "hey", "ei"].contains(p) || nomi.contains(where: { p.hasPrefix($0) }) {
            parole.removeFirst()
        }
        guard let ultima = parole.last, let prima = parole.first else { return 1.2 }
        let frase = parole.joined(separator: " ")

        // domanda chiusa: il punto di domanda del riconoscimento («Che ore sono?», «Chi è?», «Perché?», «E sabato?»)
        if basso.hasSuffix("?") { return 0.7 }

        // risposte brevi, anche di due o tre parole: «sì», «no grazie», «va bene», «sì, mandala pure», «sì sì», «no no»
        let brevi: Set<String> = ["sì", "si", "no", "ok", "okay", "certo", "esatto", "grazie", "mille", "perfetto", "va", "bene", "giusto",
                                  "bravo", "basta", "stop", "ferma", "avanti", "pausa", "dai", "fatto", "procedi", "vai", "confermo",
                                  "pure", "sir", "mandala", "mandalo", "mandale", "mandali", "inviala", "invialo", "fallo", "falla"]
        if parole.count <= 3 && parole.allSatisfy({ brevi.contains($0) }) { return 0.6 }

        // domanda breve senza «?» che finisce col verbo («che ore sono», «chi è», «che impegni ho»): è chiusa, non sospesa
        let interrogative: Set<String> = ["che", "cosa", "cos'è", "quanto", "quanti", "quanta", "quante", "chi", "dove", "qual", "quale",
                                          "quali", "c'è", "com'è", "dov'è"]
        let verbiFinali: Set<String> = ["sono", "è", "ho", "hai", "sei", "siamo", "c'è"]
        if interrogative.contains(prima), verbiFinali.contains(ultima), parole.count >= 2, parole.count <= 6, !basso.contains("?") { return 1.2 }

        // si è fermato a metà o sta pensando ad alta voce («…e», «…perché», «no, aspetta», «fammi pensare»)
        // «aspetta», «senti», «guarda» in fondo: sta per dire la cosa vera (non «mi senti», «lo guarda»)
        let segnali: Set<String> = ["aspetta", "senti", "ascolta", "guarda", "scusa"]
        let cliticoPrima = parole.count >= 2 && ["mi", "ci", "lo", "la", "li", "le", "ti"].contains(parole[parole.count - 2])
        if paroleSospese.contains(ultima) || (segnali.contains(ultima) && !cliticoPrima)
            || ["fammi pensare", "fammi capire", "fammi dire"].contains(frase) { return 2.4 }
        if basso.hasSuffix(",") || basso.hasSuffix("…") || basso.hasSuffix("...") { return 2.0 }

        // domanda chiusa senza «?»: solo le interrogative vere («che tempo fa domani»). «Come», «quando», «mi», «hai»…
        // senza «?» aprono spesso un racconto («Quando ero piccolo…», «Mi sono svegliato tardi…»): lì l'attesa è normale
        if interrogative.contains(prima), parole.count >= 2, parole.count <= 10 { return 0.8 }

        // comandi: «apri…», «metti…», «chiama…», «guarda là in fondo» (ma «Guarda, oggi…» è un racconto)
        let comandi: Set<String> = ["apri", "chiudi", "metti", "chiama", "manda", "scrivi", "accendi", "spegni", "ferma", "avvia",
                                    "leggi", "cerca", "dimmi", "fammi", "ricordami", "imposta", "alza", "abbassa", "guarda",
                                    "scansiona", "traduci", "attiva", "disattiva", "riproduci", "salta", "segna", "aggiungi",
                                    "togli", "cancella", "mostrami", "trova", "calcola", "prenota", "fai"]
        let guardaRacconto = prima == "guarda" && (parole.count > 5 || basso.contains("guarda,"))
        if comandi.contains(prima), parole.count <= 10, !guardaRacconto { return 0.9 }

        // racconto: chi parla sta esponendo un pensiero, di solito continua
        let racconto = ["oggi", "ieri", "stamattina", "stasera", "allora", "ascolta", "senti", "praticamente", "sai", "comunque",
                        "quindi", "ti volevo", "volevo", "ti racconto", "ti devo", "devo dirti", "pensavo", "secondo me", "io", "noi",
                        "l'altro giorno", "prima", "aspetta", "scusa"]
        if guardaRacconto || racconto.contains(where: { frase == $0 || frase.hasPrefix($0 + " ") }) { return 1.8 }
        if parole.count >= 15 { return 1.6 }                    // discorso lungo: pause di pensiero più probabili
        return 1.2
    }

    /// Esitazioni di chi sta cercando le parole: intercalari («ehm», «cioè», «tipo») e parole piccole ripetute di seguito
    /// («delle delle», «che che», «il il»). 12 nov (errore 1): le parole piene ripetute («sì sì», «no no», «piano piano») non contano:
    /// in italiano raddoppiare è un modo di dire, non un'esitazione.
    static func esitazioni(_ testo: String) -> Int {
        let p = parole(testo)
        guard p.count >= 2 else { return 0 }
        let intercalari: Set<String> = ["ehm", "eh", "mmm", "mh", "uhm", "cioè", "tipo", "praticamente", "insomma", "boh"]
        var n = p.filter { intercalari.contains($0) }.count
        for k in 1..<p.count where p[k] == p[k - 1] && paroleSospese.contains(p[k]) && !intercalari.contains(p[k]) { n += 1 }
        return n
    }

    /// Quello che il signore dice mentre JARVIS parla (P1, 12 nov). Fra persone «sì», «mh», «certo», «esatto» sono segnali d'ascolto:
    /// chi parla continua. «Ho capito», «sì sì sì», «ok grazie», «va bene va bene»: ha capito, chi parla finisce la frase e si ferma.
    enum SegnaleAscolto: Sendable { case nessuno, ascolto, chiusura }

    static func segnaleDAscolto(_ testo: String) -> SegnaleAscolto {
        let p = parole(testo)
        guard !p.isEmpty, p.count <= 5 else { return .nessuno }
        let assensi: Set<String> = ["sì", "si", "ok", "okay", "certo", "certamente", "esatto", "esattamente", "giusto", "vero", "già", "appunto",
                                    "infatti", "chiaro", "ovvio", "sicuro", "perfetto", "bene", "benissimo", "ottimo", "d'accordo", "capito",
                                    "ah", "eh", "oh", "mh", "mhm", "mm", "mmh", "uhm", "uh", "aha", "ecco", "bravo", "wow", "caspita",
                                    "davvero", "ho", "va", "grazie"]
        guard p.allSatisfy({ assensi.contains($0) }) else { return .nessuno }
        let ripetuta = p.count >= 3 && Set(p).count == 1                         // «sì sì sì», «ok ok ok»
        let chiude = p.contains("capito") || p.contains("grazie") || ripetuta || p.filter({ $0 == "bene" }).count >= 2
        return chiude ? .chiusura : .ascolto
    }

    /// La pausa finale: le parole (`lessicale`, da `pausa`), il ritmo del signore, le esitazioni (A2) e come è finita la voce (P3).
    /// L'intonazione non tocca mai quello che decidono le parole da sole: le risposte brevi (0,6 s), le domande col «?» (0,7 s) e le
    /// frasi rimaste a metà (2 s e oltre). Sulle altre: voce che scende (ha finito) → si risponde prima; voce sospesa (vuole
    /// continuare) → un po' più di pazienza, al massimo mezzo secondo in più.
    static func conVoce(lessicale: Double, ritmo: Double, esitazioni: Int, fine: Intonazione.Fine) -> Double {
        var p = lessicale * ritmo
        if p >= 1, esitazioni >= 2 { p = min(2.6, p * 1.3) }
        guard lessicale > 0.75, lessicale < 2.0 else { return p }
        switch fine {
        case .scende: return max(0.6, p * 0.7)
        case .sospesa: return min(2.6, p + min(0.5, p * 0.25))
        case .incerta: return p
        }
    }

    // MARK: 12.0 (10) · Riprendere il filo (deciso dal signore: «voglio più comandi per ricominciare a parlare con lui e che mi finisca
    // la frase… comandi umani… perché voglio un perfetto dialogo umano»)

    /// Il nome di JARVIS come lo storpia il riconoscimento («Giarvis», «Jervis»…): una lista sola per iPhone, Mac e polso.
    static let nomiJarvis = ["jarvi", "giarvi", "giàrvi", "jervis", "charvis", "jarves", "jarbis"]
    private static let nomiNudi = ["jarvi", "giarvi", "jervis", "charvis", "jarves", "jarbis"]   // gli stessi, senza accenti

    /// Quanto JARVIS ricorda la frase su cui ha taciuto perché credeva che il signore parlasse con qualcun altro (deciso dal
    /// signore: 8 secondi). Entro quel tempo «Jarvis?», «ci sei?», «dico a te» vogliono dire che era per lui.
    static let memoriaSilenzio: TimeInterval = 8

    /// Le parole per il confronto con le frasi fatte: minuscole, senza accenti («lì» = «li», «perché» = «perche»), l'apostrofo
    /// separa («dov'eri» = «dov eri»), senza il nome di JARVIS (anche storpiato).
    static func paroleNude(_ testo: String) -> [String] {
        testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { p in !nomiNudi.contains(where: { p.hasPrefix($0) }) }
    }

    /// 12.0 (10) · la regia: più comandi in una frase («apri la spesa e aggiungi il latte», «chiudi tutto e poi dimmi il meteo»).
    /// Non li fa l'app da sola (il primo si aprirebbe e il secondo andrebbe perso): vanno al cervello, che li fa in fila con lo
    /// strumento «regia». Basta un legame («e», «poi», «quindi», «dopo») seguito da un verbo di comando.
    static func comandoComposto(_ testo: String) -> Bool {
        let p = paroleNude(testo)
        guard p.count >= 4 else { return false }
        let legami: Set<String> = ["e", "ed", "poi", "quindi", "dopo"]
        let ponte: Set<String> = ["poi", "anche", "intanto", "dopo", "pure", "subito"]
        for (i, w) in p.enumerated() where i >= 2 && legami.contains(w) {
            var j = i + 1
            while j < p.count, ponte.contains(p[j]) { j += 1 }               // «e poi», «e intanto», «e anche»
            if j < p.count, verbiComposti.contains(p[j]) { return true }
        }
        return false
    }

    private static let verbiComposti: Set<String> = [
        "aggiungi", "aggiungimi", "togli", "toglimi", "leva", "levami", "metti", "mettimi", "segna", "segnami", "scrivi", "scrivimi",
        "manda", "mandami", "mandagli", "mandale", "invia", "chiama", "chiamami", "cerca", "cercami", "leggi", "leggimi", "dimmi",
        "apri", "aprimi", "chiudi", "chiudila", "chiudilo", "fammi", "suona", "avvia", "accendi", "spegni", "prendi", "compra",
        "mostra", "mostrami", "porta", "portami", "controlla", "aggiorna", "cambia", "imposta", "ricordami", "spunta", "svuota",
        "rispondi", "inoltra", "salva", "salvami", "elimina", "cancella", "dammi", "trova", "trovami", "guarda", "mettila",
        "mettilo", "riproduci", "fai", "torna", "vai",
    ]

    /// 12.0 (11) · l'interruzione, come fra persone: le parole che il signore dice davvero mentre JARVIS parla, separate dalla sua
    /// eco. Una parola è eco solo se JARVIS la sta dicendo E fa coppia con una vicina come nella sua frase («il bar ha perso»
    /// sentito mentre lo dice). Prima bastava che JARVIS l'avesse usata una volta: «ma», «non», «cosa», «dici» del signore
    /// sparivano come eco e lui non riusciva a fermarlo.
    static func paroleProprie(_ sentite: [String], detto: [String]) -> [String] {
        let mie = Set(detto)
        var coppie = Set<String>()
        if detto.count > 1 { for i in 1..<detto.count { coppie.insert(detto[i - 1] + " " + detto[i]) } }
        var proprie: [String] = []
        for (i, p) in sentite.enumerated() {
            guard mie.contains(p) else { proprie.append(p); continue }
            let conPrima = i > 0 && coppie.contains(sentite[i - 1] + " " + p)
            let conDopo = i + 1 < sentite.count && coppie.contains(p + " " + sentite[i + 1])
            if !conPrima && !conDopo && sentite.count > 1 { proprie.append(p) }
        }
        return proprie
    }

    /// 12.0 (11): mentre JARVIS parla, il signore gli sta parlando sopra? Contano le ultime quattro parole sentite (l'eco
    /// accumulata prima non «diluisce» più le sue): almeno due sono sue e almeno la metà.
    static func parlaSopra(_ sentite: [String], detto: [String]) -> Bool {
        let coda = Array(sentite.suffix(4))
        let sue = paroleProprie(coda, detto: detto)
        return sue.count >= 2 && sue.count * 2 >= coda.count
    }

    /// Nella frase c'è il nome di JARVIS (anche storpiato).
    static func haNome(_ testo: String) -> Bool {
        testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { p in nomiNudi.contains(where: { p.hasPrefix($0) }) }
    }

    /// Il cuore della frase: via le parole di contorno davanti («ma», «dai», «scusa», «no niente»…) e in fondo («pure», «dai»,
    /// «per favore»…), finché resta almeno una parola.
    private static func cuore(_ parole: [String], davanti: Set<String>, dietro: Set<String>) -> String {
        var w = parole
        var cambiato = true
        while cambiato, w.count > 1 {
            cambiato = false
            if let f = w.first, davanti.contains(f) { w.removeFirst(); cambiato = true; continue }
            if let l = w.last, dietro.contains(l) { w.removeLast(); cambiato = true; continue }
            if w.count > 2, w[w.count - 2] == "per", w[w.count - 1] == "favore" { w.removeLast(2); cambiato = true }
        }
        return w.joined(separator: " ")
    }

    private static let davantiRichiamo: Set<String> = ["ma", "e", "ehi", "hey", "ei", "oh", "ohi", "ehm", "scusa", "scusami", "dai",
                                                        "insomma", "allora", "quindi", "beh", "be", "ok", "okay", "sir", "si", "o",
                                                        "senti", "ascolta"]
    private static let dietroRichiamo: Set<String> = ["dai", "eh", "allora", "sir", "o", "no", "ora", "adesso", "insomma", "scusa",
                                                       "ehi", "oh", "pure", "almeno", "si"]
    /// I richiami puri: chi li dice vuole la risposta alla frase di prima, così com'era.
    private static let richiamiPuri: Set<String> = [
        // ci sei? mi senti?
        "ci sei", "ci sei ancora", "sei li", "sei qui", "sei ancora li", "sei ancora qui", "sei sveglio", "sei ancora sveglio",
        "sei acceso", "sei connesso", "sei in linea", "pronto", "ehi", "hey", "oh", "ohi", "eh", "ehila", "allo", "senti", "ascolta",
        "ascoltami", "ci senti", "mi senti", "mi hai sentito", "hai sentito", "mi ascolti", "mi stai ascoltando", "mi stai sentendo",
        "mi hai ascoltato", "non mi senti", "non mi hai sentito", "non hai sentito", "hai sentito cosa ho detto",
        "hai sentito cosa ti ho detto", "hai sentito la domanda", "hai capito", "mi hai capito", "non hai capito", "non mi hai capito",
        "hai capito cosa ho detto", "hai capito cosa ti ho detto", "hai capito la domanda",
        // allora?
        "allora", "beh", "be", "quindi", "dunque", "e quindi", "e dunque", "e allora", "insomma", "cosa aspetti", "che aspetti",
        // rispondi
        "rispondi", "rispondimi", "mi rispondi", "non mi rispondi", "non rispondi", "perche non rispondi", "perche non mi rispondi",
        "perche non parli", "perche stai zitto", "perche taci", "non parli", "parla", "parlami", "dimmi qualcosa", "di qualcosa",
        "dici qualcosa",
        // dico a te
        "dico a te", "dicevo a te", "dico proprio a te", "dicevo proprio a te", "parlo con te", "parlavo con te",
        "sto parlando con te", "stavo parlando con te", "parlo a te", "parlavo a te", "sto parlando a te", "stavo parlando a te",
        "era per te", "e per te", "era proprio per te", "e proprio per te", "chiedo a te", "chiedevo a te", "lo chiedo a te",
        "lo chiedevo a te", "domandavo a te", "lo domandavo a te", "a te", "proprio a te", "con te", "tu", "proprio tu", "te",
        "dicevo te", "dico a te dico",
        // dormi?
        "dormi", "stai dormendo", "ti sei addormentato", "ti sei incantato", "ti sei bloccato", "sei bloccato", "sei morto",
        "funzioni", "funzioni ancora", "tutto bene", "che succede", "che fai", "che stai facendo", "cosa fai",
    ]
    /// I richiami che chiedono anche un parere sulla frase di prima: vanno al cervello dopo di lei.
    private static let richiamiConParere: Set<String> = [
        "che dici", "cosa dici", "che mi dici", "che ne dici", "tu che dici", "tu che ne dici", "che ne pensi", "cosa ne pensi",
        "tu che ne pensi", "tu cosa ne pensi", "e tu", "e tu che dici", "e tu che ne pensi", "e tu cosa ne pensi", "tu cosa dici",
        "secondo te", "e secondo te", "e tu cosa dici",
    ]

    /// 12.0 (10): JARVIS ha appena taciuto su una frase (credeva che il signore parlasse con qualcun altro) e il signore lo richiama.
    /// Come una persona che si accorge che parlavano proprio a lei, JARVIS risponde alla frase di prima.
    /// - Returns: nil se non è un richiamo; "" se è un richiamo puro («Jarvis?», «ci sei?», «mi senti?», «allora?», «dico a te»,
    ///   «rispondi»: si risponde alla frase di prima così com'era); la frase stessa se chiede anche un parere su quella frase
    ///   («tu che ne pensi?», «e tu?»: va al cervello dopo la frase di prima).
    static func richiamoDopoSilenzio(_ testo: String) -> String? {
        let p = paroleNude(testo)
        if p.isEmpty { return haNome(testo) ? "" : nil }          // il nome da solo: «Jarvis?», «Jarvis!»
        guard p.count <= 8 else { return nil }
        let c = cuore(p, davanti: davantiRichiamo, dietro: dietroRichiamo)
        // «e tu?» chiede un parere (la «e» davanti non è contorno, qui)
        if richiamiConParere.contains(p.joined(separator: " ")) || richiamiConParere.contains(c) {
            return testo.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return richiamiPuri.contains(c) ? "" : nil
    }

    private static let davantiRipresa: Set<String> = ["no", "niente", "nulla", "scusa", "scusami", "perdonami", "perdona", "pardon",
                                                       "ok", "okay", "si", "va", "bene", "ah", "oh", "eh", "ehm", "dai", "ma", "allora",
                                                       "prego", "anzi", "certo", "sir", "ehi", "hey", "giusto", "ecco", "vabbe"]
    private static let dietroRipresa: Set<String> = ["pure", "dai", "sir", "prego", "allora", "scusa", "scusami", "grazie", "ok", "eh",
                                                      "tranquillo"]
    /// Chiedono senza dubbio di riprendere la frase di JARVIS, anche presi senza «Jarvis» («dicevi?», «dove eri rimasto?»).
    private static let ripreseChiare: Set<String> = [
        "dicevi", "stavi dicendo", "cosa dicevi", "che dicevi", "cosa stavi dicendo", "che stavi dicendo", "dicevi qualcosa",
        "stavi dicendo qualcosa", "dicevi tu", "cosa stavi per dire", "che stavi per dire", "stavi per dire",
        "continua quello che dicevi", "continua quello che stavi dicendo", "continua il discorso", "continua la frase",
        "continua la risposta", "vai avanti con il discorso", "vai avanti col discorso", "finisci la frase", "finisci di dire",
        "finisci il discorso", "finisci quello che dicevi", "finisci quello che stavi dicendo", "finisci la risposta",
        "riprendi il discorso", "riprendi da dove eri", "riprendi da dove eri rimasto", "riprendi da dove ti eri fermato",
        "ricomincia da dove eri", "ricomincia da dove eri rimasto", "da dove eri rimasto", "dove eri rimasto", "dov eri rimasto",
        "dove eravamo rimasti", "dov eravamo rimasti", "ti ho interrotto", "ti ho interrotto continua", "ti ho interrotto vai avanti",
        "non volevo interromperti", "non volevo interromperti continua", "scusa se ti ho interrotto", "se ti ho interrotto",
    ]
    /// «Continua», «vai avanti», «finisci»: la ripresa, detti a lui (col nome, toccando il reattore o in dialogo).
    private static let ripreseGeneriche: Set<String> = [
        "continua", "continua continua", "continua a dire", "puoi continuare", "prosegui", "vai avanti", "vai pure avanti",
        "vai avanti a dire", "finisci", "puoi finire", "riprendi", "dove eravamo",
    ]
    /// «Vai», «avanti», «prego», «dimmi», «e poi?»: riprendono la frase di JARVIS, ma dopo una sua domanda sono la risposta.
    private static let ripreseSemplici: Set<String> = ["vai", "vai pure", "avanti", "prego", "dimmi", "dimmi pure", "e poi", "poi",
                                                        "sentiamo", "ti ascolto", "ti sto ascoltando", "sono tutto orecchi"]

    /// 12.0 (10): il signore ha interrotto JARVIS e adesso gli chiede di finire la sua frase: «dicevi?», «continua pure», «scusa,
    /// vai avanti», «finisci», «prego», «dove eri rimasto?».
    /// - `dopoDomanda`: JARVIS si è fermato su una sua domanda («…lo mando?»): «vai», «avanti», «prego» sono la risposta.
    /// - `libera`: la frase l'ha presa l'ascolto libero, senza «Jarvis»: valgono solo quelle che parlano della sua frase («dicevi?»);
    ///   «continua» o «vai avanti» potevano essere per un'altra persona.
    static func chiedeDiContinuare(_ testo: String, dopoDomanda: Bool = false, libera: Bool = false) -> Bool {
        let p = paroleNude(testo)
        guard !p.isEmpty, p.count <= 9 else { return false }
        let c = cuore(p, davanti: davantiRipresa, dietro: dietroRipresa)
        if ripreseChiare.contains(c) { return true }
        if libera { return false }
        return ripreseGeneriche.contains(c) || (!dopoDomanda && ripreseSemplici.contains(c))
    }

    /// 12.0 (10): i secondi fra la fine dell'ultima risposta di JARVIS e l'inizio della frase del signore, con un decimale (per il
    /// cervello: una frase detta a pochi secondi dalla risposta è quasi sempre per JARVIS). Nil se non c'è o è troppo lontana.
    static func dopoRisposta(fine: Date?, inizio: Date?) -> Double? {
        guard let fine, let inizio else { return nil }
        let s = inizio.timeIntervalSince(fine)
        return s >= 0 && s < 600 ? (s * 10).rounded() / 10 : nil
    }

    /// Il resto della risposta interrotta da dire: quello che viene dopo le frasi già dette (`detto`, con o senza i toni della
    /// voce come «[laughs]»). Nil se il punto non si ritrova; vuoto se l'aveva già detta tutta.
    static func restoDaDire(_ completa: String, detto: String) -> String? {
        let d = detto.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return completa.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let k = taglio(completa, dopo: d) else { return nil }
        return String(completa[k...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dove finisce, dentro `testo`, la parte già detta. Contano solo lettere e cifre: spazi, a capo e punteggiatura possono
    /// cambiare fra le frasi dette una per una e il testo intero. Nil se il detto non è l'inizio del testo. (Qui dal 12.0 (10),
    /// per le prove automatiche; `Dialogo.taglio` la usa.)
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
}

// MARK: - 12 nov · L'intonazione (P3, revisione del dialogo approvata dal signore: «provala già adesso»)

/// L'altezza della voce, misurata sul telefono mentre il signore parla. Chi ha finito di parlare abbassa la voce in fondo alla frase;
/// chi vuole continuare la lascia sospesa. Ogni 20 ms di voce si misura la frequenza fondamentale (metodo YIN, su un segnale ridotto a
/// circa 12 kHz e addolcito sotto i 1000 Hz); a fine frase si guarda l'ultimo mezzo secondo di voce rispetto alla sua altezza degli
/// ultimi secondi. Gira sul thread del microfono: nessuna allocazione, tutto sotto lucchetto, memoria preparata all'inizio.
nonisolated final class Intonazione: @unchecked Sendable {
    static let condivisa = Intonazione()

    /// Com'è finita la voce: scende (ha finito), sospesa (vuole continuare), incerta (non si capisce: decidono le parole).
    enum Fine: String, Sendable { case scende, sospesa, incerta }

    /// Il giudizio sull'ultima frase: livello (semitoni sotto o sopra la sua altezza di questa frase), pendenza dell'ultimo mezzo
    /// secondo (semitoni), quante misure buone c'erano.
    struct Giudizio: Sendable {
        var fine: Fine
        var livello: Double
        var pendenza: Double
        var punti: Int
        static let incerto = Giudizio(fine: .incerta, livello: 0, pendenza: 0, punti: 0)
    }

    private let lock = NSLock()
    private var hzIngresso: Double = 0
    private var passo = 4                  // un campione ridotto ogni `passo` del microfono
    private var hz: Double = 12_000        // la frequenza del segnale ridotto
    private var aBasso: Float = 0.12       // il filtro che addolcisce sopra i 1000 Hz
    private var basso: Float = 0
    private var accumulo: Float = 0
    private var contati = 0
    private static let capienza = 8192
    private let ridotto: UnsafeMutablePointer<Float>
    private var quanti = 0                 // campioni ridotti nel buffer
    private var analizzato = 0             // da dove parte la prossima misura
    private static let finestra = 384      // campioni per una misura (~32 ms a 12 kHz)
    private var salto = 240                // ~20 ms fra due misure
    private var tauMin = 28, tauMax = 200  // da circa 430 Hz a 60 Hz
    private static let tauCapienza = 320
    private let diff: UnsafeMutablePointer<Float>
    private let cmnd: UnsafeMutablePointer<Float>
    private static let maxPunti = 512
    private let tempi: UnsafeMutablePointer<Double>
    private let semitoni: UnsafeMutablePointer<Float>
    private var punti = 0, prossimo = 0
    private var daTempo: TimeInterval = 0  // i punti prima di questo istante non contano (frase nuova)

    init() {
        ridotto = .allocate(capacity: Intonazione.capienza); ridotto.initialize(repeating: 0, count: Intonazione.capienza)
        diff = .allocate(capacity: Intonazione.tauCapienza + 1); diff.initialize(repeating: 0, count: Intonazione.tauCapienza + 1)
        cmnd = .allocate(capacity: Intonazione.tauCapienza + 1); cmnd.initialize(repeating: 0, count: Intonazione.tauCapienza + 1)
        tempi = .allocate(capacity: Intonazione.maxPunti); tempi.initialize(repeating: 0, count: Intonazione.maxPunti)
        semitoni = .allocate(capacity: Intonazione.maxPunti); semitoni.initialize(repeating: 0, count: Intonazione.maxPunti)
    }

    deinit {
        ridotto.deallocate(); diff.deallocate(); cmnd.deallocate(); tempi.deallocate(); semitoni.deallocate()
    }

    /// Un ascolto nuovo: si dimentica tutto.
    func azzera() {
        lock.lock()
        quanti = 0; analizzato = 0; punti = 0; prossimo = 0; basso = 0; accumulo = 0; contati = 0; daTempo = 0
        lock.unlock()
    }

    /// Una frase nuova sul microfono sempre acceso: contano solo le misure da `da` in poi.
    func iniziaFrase(da: TimeInterval) {
        lock.lock(); daTempo = da; lock.unlock()
    }

    private func configura(_ ingresso: Double) {
        hzIngresso = ingresso
        passo = max(1, Int((ingresso / 12_000).rounded()))
        hz = ingresso / Double(passo)
        aBasso = Float(1 - exp(-2 * Double.pi * 1_000 / ingresso))
        tauMin = max(2, Int(hz / 430))
        tauMax = min(Intonazione.tauCapienza - 1, Int(hz / 60))
        salto = max(1, Int(hz * 0.02))
        quanti = 0; analizzato = 0; basso = 0; accumulo = 0; contati = 0
    }

    /// Toglie i primi `k` campioni ridotti (quelli già misurati o troppo vecchi).
    private func scarta(_ k: Int) {
        guard k > 0 else { return }
        let resto = quanti - k
        if resto > 0 { memmove(ridotto, ridotto + k, resto * MemoryLayout<Float>.stride) }   // le due zone si sovrappongono
        quanti = max(0, resto)
        analizzato = max(0, analizzato - k)
    }

    /// Un pezzo di audio del microfono. `voce`: in questo pezzo il signore parla (lo decide VoceAttiva); `tempo`: quando è arrivato.
    func ascolta(_ campioni: UnsafePointer<Float>, n: Int, hz ingresso: Double, voce: Bool, tempo: TimeInterval) {
        guard n > 0, ingresso > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if ingresso != hzIngresso { configura(ingresso) }
        let serve = Intonazione.finestra + tauMax
        for i in 0..<n {
            basso += aBasso * (campioni[i] - basso)
            accumulo += basso
            contati += 1
            if contati == passo {
                if quanti == Intonazione.capienza { scarta(Intonazione.capienza - serve) }
                ridotto[quanti] = accumulo / Float(passo)
                quanti += 1
                accumulo = 0; contati = 0
            }
        }
        guard voce else {
            // niente voce: si tiene solo quanto serve per la prossima misura
            if quanti > serve { scarta(quanti - serve) }
            analizzato = 0
            return
        }
        while analizzato + serve <= quanti {
            if let f0 = yin(ridotto + analizzato) {
                let ritardo = Double(quanti - (analizzato + Intonazione.finestra / 2)) / hz
                tempi[prossimo] = tempo - ritardo
                semitoni[prossimo] = Float(12 * log2(Double(f0) / 100))
                prossimo = (prossimo + 1) % Intonazione.maxPunti
                punti = min(punti + 1, Intonazione.maxPunti)
            }
            analizzato += salto
        }
        if analizzato > 0 { scarta(analizzato) }
    }

    /// La frequenza fondamentale di una finestra (nil: non è voce intonata, o non si capisce). YIN: differenza, media cumulativa
    /// normalizzata, prima discesa sotto la soglia, minimo locale, interpolazione parabolica.
    private func yin(_ x: UnsafeMutablePointer<Float>) -> Float? {
        let w = Intonazione.finestra
        for tau in 1...tauMax {
            var s: Float = 0
            for j in 0..<w { let d = x[j] - x[j + tau]; s += d * d }
            diff[tau] = s
        }
        var cumulata: Float = 0
        cmnd[0] = 1
        for tau in 1...tauMax {
            cumulata += diff[tau]
            cmnd[tau] = cumulata > 0 ? diff[tau] * Float(tau) / cumulata : 1
        }
        var scelto = -1
        var tau = tauMin
        while tau <= tauMax {
            if cmnd[tau] < 0.15 {
                while tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                scelto = tau
                break
            }
            tau += 1
        }
        guard scelto > 0 else { return nil }
        var t = Float(scelto)
        if scelto > 1 && scelto < tauMax {
            let s0 = cmnd[scelto - 1], s1 = cmnd[scelto], s2 = cmnd[scelto + 1]
            let den = s0 + s2 - 2 * s1
            if abs(den) > 1e-9 { t += 0.5 * (s0 - s2) / den }
        }
        guard t > 0 else { return nil }
        let f0 = Float(hz) / t
        return f0 >= 60 && f0 <= 430 ? f0 : nil
    }

    /// Le misure degli ultimi `secondi` (per le prove e per il giudizio): quando e altezza in semitoni.
    func misure(ultimi secondi: Double, ora: TimeInterval) -> [(t: Double, st: Float)] {
        lock.lock(); defer { lock.unlock() }
        var out: [(t: Double, st: Float)] = []
        out.reserveCapacity(punti)
        for k in 0..<punti {
            let i = (prossimo - punti + k + Intonazione.maxPunti) % Intonazione.maxPunti
            if tempi[i] >= ora - secondi && tempi[i] >= daTempo { out.append((tempi[i], semitoni[i])) }
        }
        return out
    }

    /// Com'è finita la voce nell'ultima frase. Servono almeno 10 misure buone negli ultimi 8 secondi e la voce sentita da poco
    /// (meno di 1,5 s fa); le misure sbagliate d'ottava (oltre 7 semitoni dalla sua altezza) si scartano.
    func giudizio(ora: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Giudizio {
        let tutte = misure(ultimi: 8, ora: ora)
        guard tutte.count >= 10, let ultima = tutte.last, ora - ultima.t < 1.5 else { return .incerto }
        let mediana0 = Intonazione.mediana(tutte.map(\.st))
        let buone = tutte.filter { abs($0.st - mediana0) <= 7 }
        guard buone.count >= 10, let fineVoce = buone.last?.t else { return .incerto }
        let coda = buone.filter { $0.t >= fineVoce - 0.5 }
        guard coda.count >= 5 else { return .incerto }
        let base = Intonazione.mediana(buone.map(\.st))
        let fine = Intonazione.mediana(coda.suffix(4).map(\.st))
        let inizio = Intonazione.mediana(coda.prefix(4).map(\.st))
        let livello = Double(fine - base), pendenza = Double(fine - inizio)
        let tipo: Fine = livello <= -1.8 && pendenza <= -0.8 ? .scende : (livello >= -0.4 && pendenza >= -0.3 ? .sospesa : .incerta)
        return Giudizio(fine: tipo, livello: (livello * 10).rounded() / 10, pendenza: (pendenza * 10).rounded() / 10, punti: buone.count)
    }

    static func mediana(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
