#if os(iOS)
import Foundation
import UIKit
import UserNotifications
import WatchConnectivity

// MARK: - 18 nov · 13.1 (2) · FUORI DALL'APP (mockup FUORI approvato dal signore, scelte del 18 nov)
// Il signore (18 nov, 11:24): «migliorare ancora l'interattività e la fluidità… senza incongruenze, bug o sovrapposizioni».
// Qui le parti che lavorano con JARVIS dietro o chiuso:
// - IL SÌ DAL POLSO: quando un messaggio, una chiamata, un post o un passo del piano aspetta il sì, sull'orologio arriva la scheda
//   Sì / No. Col telefono in mano arriva in silenzio; in tasca (JARVIS dietro o bloccato) bussa due volte (scelta del signore).
//   Se l'app dell'orologio non è aperta, la scheda è una notifica dell'iPhone coi tasti Sì e No (sull'orologio solo se lo specchio
//   delle notifiche di JARVIS è acceso: limite di Apple, detto al signore).
// - APERTURA FUORI: col telefono in tasca iOS non lascia aprire Comandi rapidi, Messaggi, WhatsApp o il telefono. iMessage e
//   chiamate li apre l'orologio (scelta del signore: un tocco su Invia); il resto parte appena il signore sblocca.
// - LA RIPRESA («dove eravamo rimasti»): quello che aspettava il sì si salva quando JARVIS va dietro; riaprendo (dopo almeno
//   3 minuti, entro 12 ore) JARVIS lo dice una volta sola e rimette la tab. Niente in sospeso: silenzio.
// - IL FILO CON IL MAC (scelta del signore: Supabase, funzione jarvis-filo, tabella jarvis_filo_app): ogni dispositivo lascia le
//   ultime battute (mai quelle di Confidente, Profiler e Wiretap) e il sì in attesa; l'altro, riaprendo JARVIS, riprende il discorso.

/// Quello che aspetta il sì adesso.
nonisolated struct InAttesa: Equatable, Sendable {
    var chiave: String
    var tipo: String          // messaggio, chiama, pubblica, piano, conferma
    var domanda: String       // la testata della scheda: «LO MANDO?»
    var riga: String          // «A Bea · «Arrivo alle nove.»»
    var quando: Date

    /// Per l'orologio (WatchConnectivity vuole solo tipi semplici).
    /// `zitta`: notifiche spente fino a domattina, o di notte: l'orologio mostra la scheda ma non bussa (13.4).
    func perPolso(inMano: Bool, zitta: Bool = false) -> [String: Any] {
        // «t»: quando parte (l'orologio scarta le schede arrivate in coda dopo 3 minuti). Non l'inizio del piano: un piano cominciato
        // da più di 3 minuti mandava una scheda già «vecchia» e l'orologio non la mostrava
        ["si_scheda": ["k": chiave, "tipo": tipo, "d": domanda, "r": riga, "t": Date().timeIntervalSince1970, "mano": inMano, "zitta": zitta] as [String: Any]]
    }
}

@MainActor
enum SiInAttesa {
    /// L'ultima domanda di JARVIS (l'ultima sua frase con il punto di domanda), per la scheda e per la ripresa.
    static func domanda(in messaggi: [Messaggio]) -> String? {
        guard let m = messaggi.last(where: { !$0.testo.isEmpty }), m.ruolo == "assistant" else { return nil }
        return ultimaDomanda(m.testo)
    }

    /// «…gin, tonica e lime. Scrivo a Cristina che mancano quelli?» → «Scrivo a Cristina che mancano quelli?»
    nonisolated static func ultimaDomanda(_ testo: String) -> String? {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasSuffix("?") else { return nil }
        var inizio = t.startIndex
        var k = t.index(before: t.endIndex)
        while k > t.startIndex {
            let prima = t.index(before: k)
            if ".!?…\n".contains(t[prima]) { inizio = k; break }
            k = prima
        }
        let d = t[inizio...].trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? nil : String(d.prefix(220))
    }

    /// Quello che aspetta il sì adesso (nil: niente).
    static func adesso(domanda: String?) -> InAttesa? {
        if let a = Insieme.condiviso.inAttesa {
            let k = "m:\(Int(a.quando.timeIntervalSince1970))"
            switch a.tipo {
            case "messaggio":
                return InAttesa(chiave: k, tipo: "messaggio", domanda: "LO MANDO?", riga: "\(Filo.a(a.chi).capitalizzata) · «\(a.testo)»", quando: a.quando)
            case "chiama":
                return InAttesa(chiave: k, tipo: "chiama", domanda: "CHIAMO?", riga: Filo.detto(a.chi).capitalizzata, quando: a.quando)
            default:
                let quando = a.testo == "ORA" ? "adesso" : Sessione.detto(a.testo)
                return InAttesa(chiave: k, tipo: "pubblica", domanda: "LO PUBBLICO?", riga: "Post · \(quando)", quando: a.quando)
            }
        }
        if let passo = Piano.condiviso.passoInAttesa, let inizio = Piano.condiviso.inizio {
            let basso = passo.lowercased()
            let manda = ["messaggio", "scriv", "invia", "manda"].contains { basso.contains($0) }
            // 13.4: con il numero del passo: se il cervello passa da un sì all'altro nello stesso istante, è comunque una scheda nuova
            let k = "p:\(Int(inizio.timeIntervalSince1970)):\(Piano.condiviso.indiceInAttesa ?? 0)"
            return InAttesa(chiave: k, tipo: "piano", domanda: manda ? "LO MANDO?" : "LO FACCIO?",
                            riga: domanda ?? passo, quando: inizio)
        }
        if Regia.condivisa.aspettaIlSi || ManiJarvis.aspettaIlSi, let domanda {
            return InAttesa(chiave: "c:\(domanda.prefix(40))", tipo: "conferma", domanda: "LO FACCIO?", riga: domanda, quando: Date())
        }
        return nil
    }
}

// MARK: - Aprire con JARVIS dietro

@MainActor
enum AperturaFuori {
    enum Via { case subito, polso, allaSblocco }

    /// Le app da aprire rimaste in sospeso (WhatsApp, Mappe…): si aprono appena il signore torna in JARVIS.
    private static var rimandata: (url: URL, quando: Date)?

    /// Il telefono è in mano: JARVIS davanti o appena coperto (Centro di Controllo, una chiamata in arrivo). Sul Mac sempre.
    static var davanti: Bool { ProcessInfo.processInfo.isiOSAppOnMac || UIApplication.shared.applicationState != .background }

    /// Come andrà: subito (JARVIS davanti), dall'orologio (iMessage e chiamate, con l'app dell'orologio aperta), allo sblocco.
    static func via(_ url: URL) -> Via {
        if davanti { return .subito }
        if !ProcessInfo.processInfo.isiOSAppOnMac, PonteTelefono.condiviso.polsoRaggiungibile, messaggio(url) != nil || chiamata(url) != nil { return .polso }
        return .allaSblocco
    }

    /// Apre adesso, oppure passa all'orologio, oppure aspetta lo sblocco. `chi`: il nome da scrivere sull'orologio.
    static func apri(_ url: URL, chi: String?) {
        switch via(url) {
        case .subito:
            UIApplication.shared.open(url)
        case .polso:
            if let m = messaggio(url) {
                PonteTelefono.condiviso.inviaAlPolso(["si_messaggio": ["numero": m.numero, "testo": m.testo, "chi": chi ?? ""] as [String: Any]])
            } else if let n = chiamata(url) {
                PonteTelefono.condiviso.inviaAlPolso(["si_chiama": ["numero": n, "chi": chi ?? ""] as [String: Any]])
            }
        case .allaSblocco:
            rimandata = (url, Date())                               // una sola: l'ultima cosa chiesta
            Regia.condivisa.evento("rimandato allo sblocco: \(url.scheme ?? "")")
        }
    }

    /// Di nuovo davanti: quello che era rimasto si apre adesso (entro 10 minuti; dopo, non lo aspetta più nessuno).
    static func riprendi() {
        guard let r = rimandata else { return }
        rimandata = nil
        guard Date().timeIntervalSince(r.quando) < 600 else { return }
        let url = r.url
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))       // prima l'app torna davanti del tutto
            _ = await UIApplication.shared.open(url)
        }
    }

    /// Il messaggio dentro l'indirizzo: il Comando rapido «JARVIS invia» (iMessage) o sms:. WhatsApp no: vuole il telefono.
    static func messaggio(_ url: URL) -> (numero: String, testo: String)? {
        if url.scheme == "sms" {
            let resto = url.absoluteString.dropFirst(4)
            let parti = resto.components(separatedBy: "&body=")
            let numero = parti.first ?? ""
            let testo = parti.count > 1 ? (parti[1].removingPercentEncoding ?? parti[1]) : ""
            return numero.isEmpty ? nil : (numero, testo)
        }
        guard url.scheme == "shortcuts", let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.queryItems?.first(where: { $0.name == "name" })?.value == Strumenti.comandoInvio,
              let testo = c.queryItems?.first(where: { $0.name == "text" })?.value,
              let d = (try? JSONSerialization.jsonObject(with: Data(testo.utf8))) as? [String: Any],
              let numero = d["numero"] as? String, let corpo = d["testo"] as? String, !numero.isEmpty else { return nil }
        return (numero, corpo)
    }

    /// Il numero di una chiamata (tel:).
    static func chiamata(_ url: URL) -> String? {
        guard url.scheme == "tel" else { return nil }
        let n = url.absoluteString.replacingOccurrences(of: "tel://", with: "").replacingOccurrences(of: "tel:", with: "")
        return n.isEmpty ? nil : n
    }
}

// MARK: - Il sì dal polso (iPhone)

@MainActor
final class SiPolso {
    static let condiviso = SiPolso()
    nonisolated static let categoria = "jarvis.si"

    /// L'ultima domanda di JARVIS (la imposta Jarvis).
    var ultimaDomanda: (() -> String?)?
    /// Il sì (o il no) arrivato dal polso: lo fa Jarvis. Restituisce la battuta (nil: risponde il cervello, arriva dopo).
    var esegui: ((Bool, InAttesa) async -> String?)?
    /// Il dialogo continua fuori dall'app (JARVIS parla e ascolta col telefono in tasca): la domanda la sente già, niente notifica.
    var dialogoFuori: (() -> Bool)?

    private var attuale: InAttesa?
    private var inManoInviato = true
    private var notificata: String?
    private var giro: Task<Void, Never>?

    /// All'avvio di JARVIS: i tasti Sì e No delle notifiche e il controllo ogni secondo (solo mentre l'app gira).
    func avvia() {
        guard giro == nil else { return }
        if !ProcessInfo.processInfo.isiOSAppOnMac {                   // sul Mac niente orologio: lì serve solo il filo
            let si = UNNotificationAction(identifier: "si", title: "Sì", options: [])
            let no = UNNotificationAction(identifier: "no", title: "No", options: [.destructive])
            UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: SiPolso.categoria, actions: [si, no], intentIdentifiers: [])])
        }
        giro = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.controlla()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Guarda se qualcosa aspetta il sì e lo dice all'orologio (o alla notifica) quando cambia, o quando il telefono va in tasca.
    func controlla() {
        let mac = ProcessInfo.processInfo.isiOSAppOnMac
        let ora = SiInAttesa.adesso(domanda: ultimaDomanda?())
        let inMano = mac || UIApplication.shared.applicationState == .active
        let cambiata = ora?.chiave != attuale?.chiave
        guard cambiata || (ora != nil && inMano != inManoInviato) else { return }
        let prima = attuale
        attuale = ora
        inManoInviato = inMano
        FiloCondiviso.condiviso.cambiato()                         // il sì in attesa va anche all'altro dispositivo
        guard !mac else { return }
        // 13.4 (il signore: «ESEGUI»): con JARVIS dietro quello che aspettava il sì è cambiato (sì o no dal polso, dalla notifica, dal
        // tasto Azione): la ripresa salvata andando dietro si rifà su com'è adesso, così riaprendo non richiede una cosa già fatta
        if cambiata, !AperturaFuori.davanti { Ripresa.aggiorna(domanda: ultimaDomanda?()) }
        guard let ora else {
            if let prima { PonteTelefono.condiviso.inviaAlPolso(["si_via": prima.chiave]) }
            togliNotifica()
            return
        }
        // 13.4 (il signore: «OK»): le regole degli avvisi valgono anche qui. Con «niente notifiche fino a domattina» niente notifica e
        // l'orologio non bussa; di notte (23–7) la notifica arriva senza suono e l'orologio non bussa
        let spente = AvvisiVoce.spenteFino != nil
        let zitta = spente || !AvvisiVoce.permesso(Date())
        PonteTelefono.condiviso.inviaAlPolso(ora.perPolso(inMano: inMano, zitta: zitta))
        // in tasca e senza l'app dell'orologio aperta: la scheda è una notifica coi tasti Sì e No
        if inMano || spente { togliNotifica() }
        else if !PonteTelefono.condiviso.polsoRaggiungibile, dialogoFuori?() != true, notificata != ora.chiave { notifica(ora, suono: !zitta) }
    }

    private func notifica(_ a: InAttesa, suono: Bool) {
        togliNotifica()
        notificata = a.chiave
        let c = UNMutableNotificationContent()
        c.title = "JARVIS"
        c.subtitle = String(a.domanda.prefix(1)) + a.domanda.dropFirst().lowercased()
        c.body = a.riga
        c.sound = suono ? .default : nil
        c.categoryIdentifier = SiPolso.categoria
        c.userInfo = ["chiave": a.chiave]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "jarvis.si", content: c, trigger: nil))
    }

    private func togliNotifica() {
        guard notificata != nil else { return }
        notificata = nil
        let c = UNUserNotificationCenter.current()
        c.removeDeliveredNotifications(withIdentifiers: ["jarvis.si"])
        c.removePendingNotificationRequests(withIdentifiers: ["jarvis.si"])
    }

    /// Il signore ha toccato Sì o No (sull'orologio o sulla notifica). La risposta per l'orologio.
    func dalPolso(si: Bool, chiave: String) async -> [String: Any] {
        let ora = SiInAttesa.adesso(domanda: ultimaDomanda?())
        guard let a = ora, a.chiave == chiave else { return ["errore": "Non c'è più niente da confermare."] }
        guard let esegui else { return ["errore": "Apra FRIDAY sull'iPhone."] }
        togliNotifica()
        Regia.condivisa.evento("dal polso: \(si ? "sì" : "no") a «\(a.riga.prefix(60))»")
        let battuta = await esegui(si, a)
        // 13.4: la risposta è data: la ripresa salvata andando dietro non vale più (se il cervello lascia un altro sì in attesa, la
        // rifanno `controlla` qui sotto o la fine del turno)
        if !AperturaFuori.davanti { Ripresa.dimentica() }
        controlla()
        return ["ok": true, "testo": battuta ?? ""]
    }

    /// Sì o No toccato sulla notifica del sì (sul telefono o, con lo specchio acceso, sull'orologio).
    func dallaNotifica(si: Bool, chiave: String) async {
        // tasto toccato con JARVIS chiuso da iOS: l'app si sveglia adesso, si aspetta che ci sia (al massimo 3 secondi)
        for _ in 0..<15 where esegui == nil { try? await Task.sleep(for: .milliseconds(200)) }
        let r = await dalPolso(si: si, chiave: chiave)
        if let errore = r["errore"] as? String {
            // non è partito niente: lui deve saperlo (prima il tocco andava a vuoto in silenzio)
            let c = UNMutableNotificationContent()
            c.title = "JARVIS"
            c.body = errore == "Non c'è più niente da confermare." ? "non è partito niente: la richiesta era scaduta. Me la ripeta in FRIDAY." : errore
            c.sound = .default
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "jarvis.si.esito", content: c, trigger: nil))
            return
        }
        if let testo = r["testo"] as? String, !testo.isEmpty { fatto(testo) }
    }

    /// La risposta del cervello a un sì dato dal polso: all'orologio, scritta (il telefono in tasca non parla).
    func fatto(_ testo: String) {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        PonteTelefono.condiviso.inviaAlPolso(["si_fatto": ["testo": String(t.prefix(240)), "t": Date().timeIntervalSince1970] as [String: Any]])
    }
}

// MARK: - La ripresa («dove eravamo rimasti»)

@MainActor
enum Ripresa {
    nonisolated struct AttesaSalvata: Codable, Sendable {
        var tipo: String
        var chi: String
        var numero: String
        var testo: String
        var whatsapp: Bool
    }
    nonisolated struct Salvata: Codable, Sendable {
        var uscito: Date
        var piano: Piano.Istantanea?
        var attesa: AttesaSalvata?
        var domanda: String?
    }

    private static let chiave = "ripresa.salvata"
    static let minimo: TimeInterval = 180          // prima di 3 minuti il sì vale ancora: niente da riprendere
    static let massimo: TimeInterval = 12 * 3600

    /// JARVIS va dietro: quello che aspetta il sì si salva (anche se iOS poi chiude l'app). Niente in attesa: niente da salvare.
    static func salva(domanda: String?, uscito: Date = Date()) {
        var s = Salvata(uscito: uscito, piano: Piano.condiviso.ultimoInAttesa, attesa: nil, domanda: domanda)
        if let a = Insieme.condiviso.ultimaInAttesa, a.tipo == "messaggio" || a.tipo == "chiama" {
            s.attesa = AttesaSalvata(tipo: a.tipo, chi: a.chi, numero: a.numero, testo: a.testo, whatsapp: a.whatsapp)
        }
        guard s.piano != nil || s.attesa != nil, let d = try? JSONEncoder().encode(s) else {
            UserDefaults.standard.removeObject(forKey: chiave)
            return
        }
        UserDefaults.standard.set(d, forKey: chiave)
    }

    /// 13.4: con JARVIS dietro quello che aspettava il sì è cambiato: la ripresa si rifà su com'è adesso (niente più in attesa: si
    /// cancella). L'ora di uscita resta quella vera (i 3 minuti contano da quando è andato dietro).
    static func aggiorna(domanda: String?) {
        var uscito = Date()
        if let d = UserDefaults.standard.data(forKey: chiave), let s = try? JSONDecoder().decode(Salvata.self, from: d) { uscito = s.uscito }
        salva(domanda: domanda, uscito: uscito)
    }

    /// Riaprendo: quello che era rimasto, se vale (una volta sola: si cancella qui).
    static func prendi() -> Salvata? {
        guard let d = UserDefaults.standard.data(forKey: chiave), let s = try? JSONDecoder().decode(Salvata.self, from: d) else { return nil }
        let via = Date().timeIntervalSince(s.uscito)
        // appena uscito e rientrato: il sì vale ancora com'era (e la tab c'è); si cancella solo se è passato troppo
        if via < minimo, Piano.condiviso.inAttesa != nil || Insieme.condiviso.inAttesa != nil { return nil }
        UserDefaults.standard.removeObject(forKey: chiave)
        guard via <= massimo else { return nil }
        // la stessa cosa già ripresa una volta (riaperto, non ha risposto, richiuso): non si ripete a ogni apertura
        let impronta = Ripresa.impronta(s)
        if UserDefaults.standard.string(forKey: "ripresa.detta") == impronta { return nil }
        UserDefaults.standard.set(impronta, forKey: "ripresa.detta")
        return s
    }

    /// Rimette quello che era rimasto (JARVIS era occupato e non l'ha potuto dire): lo dirà alla prossima apertura.
    static func rimetti(_ s: Salvata) {
        UserDefaults.standard.removeObject(forKey: "ripresa.detta")
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: chiave) }
    }

    /// Cosa aspettava il sì, in una riga (il piano col passo, o il messaggio): per non riprendere due volte la stessa cosa.
    private static func impronta(_ s: Salvata) -> String {
        if let p = s.piano { return "p|" + p.titolo + "|" + (p.passi.first(where: { $0.stato == Piano.Stato.aspetta.rawValue })?.testo ?? "") }
        if let a = s.attesa { return "m|" + a.chi + "|" + a.testo }
        return ""
    }

    static func dimentica() { UserDefaults.standard.removeObject(forKey: chiave) }
}

// MARK: - Il filo tra iPhone e Mac (Supabase, funzione jarvis-filo)

@MainActor
final class FiloCondiviso {
    static let condiviso = FiloCondiviso()

    nonisolated struct Battuta: Codable, Sendable {
        var r: String
        var t: String
        var d: Date
    }
    nonisolated struct Stato: Codable, Sendable {
        var battute: [Battuta]
        var piano: Piano.Istantanea?
        var attesa: Ripresa.AttesaSalvata?
        var domanda: String?
    }
    nonisolated struct Altro: Sendable {
        var dispositivo: String
        var stato: Stato
        var aggiornato: Date
    }

    /// Le battute della chat e se JARVIS è in RISERVATO (le imposta Jarvis).
    var battute: (() -> [Messaggio])?
    var riservato: (() -> Bool)?

    private var ultimoInviato = ""
    private var invio: Task<Void, Never>?
    private static let chiaveImportato = "filo.importatoFino"

    /// Le frasi delle modalità riservate non lasciano mai il dispositivo (come il filo del cervello: Confidente, Profiler, Wiretap).
    nonisolated static func riservata(_ t: String) -> Bool {
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.hasPrefix("modalità confidente") || s.hasPrefix("modalita confidente") || s.hasPrefix("modalità profiler")
            || s.hasPrefix("modalita profiler") || s.hasPrefix("wiretap:")
    }

    private var indirizzo: URL? {
        URL(string: Impostazioni.indirizzo.replacingOccurrences(of: "/functions/v1/jarvis", with: "/functions/v1/jarvis-filo"))
    }

    /// Qualcosa è cambiato (fine turno, un sì in attesa): fra 3 secondi si lascia il filo (una volta sola se cambia di nuovo).
    func cambiato() {
        invio?.cancel()
        invio = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.salva()
        }
    }

    /// Lascia il filo di questo dispositivo (ultime 12 battute senza le riservate, il sì in attesa).
    func salva() async {
        guard riservato?() != true, let url = indirizzo else { return }
        let token = Portachiavi.leggi()
        guard !token.isEmpty else { return }
        let tutte = (battute?() ?? []).filter { !$0.testo.isEmpty }.suffix(16)
        var tenute: [Battuta] = []
        var scarta = false
        var jarvisRiservato = false          // l'ultima frase di JARVIS apriva una modalità riservata (Confidente «A voce»)
        for m in tutte {
            if m.ruolo == "user" {
                scarta = FiloCondiviso.riservata(m.testo) || jarvisRiservato
            } else {
                jarvisRiservato = FiloCondiviso.riservata(m.testo)
                if jarvisRiservato { scarta = true }
            }
            if !scarta { tenute.append(Battuta(r: m.ruolo, t: String(m.testo.prefix(1500)), d: m.data)) }
        }
        var stato = Stato(battute: Array(tenute.suffix(12)), piano: Piano.condiviso.ultimoInAttesa, attesa: nil, domanda: nil)
        if let a = Insieme.condiviso.ultimaInAttesa, a.tipo == "messaggio" || a.tipo == "chiama" {
            stato.attesa = Ripresa.AttesaSalvata(tipo: a.tipo, chi: a.chi, numero: a.numero, testo: a.testo, whatsapp: a.whatsapp)
        }
        if let ultima = tenute.last, ultima.r == "assistant" { stato.domanda = SiInAttesa.ultimaDomanda(ultima.t) }
        let codifica = JSONEncoder()
        codifica.dateEncodingStrategy = .iso8601
        guard let datiStato = try? codifica.encode(stato), let oggetto = try? JSONSerialization.jsonObject(with: datiStato) else { return }
        let impronta = String(decoding: datiStato, as: UTF8.self)
        guard impronta != ultimoInviato else { return }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["dispositivo": Impostazioni.dispositivo, "salva": oggetto] as [String: Any])
        guard let (_, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return }
        ultimoInviato = impronta
    }

    /// Il filo dell'altro dispositivo, se è più nuovo di quello già preso e di quest'ultima battuta qui (al massimo 6 secondi).
    func leggi(dopo ultimaQui: Date) async -> Altro? {
        guard let url = indirizzo else { return nil }
        let token = Portachiavi.leggi()
        guard !token.isEmpty else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["dispositivo": Impostazioni.dispositivo, "leggi": true] as [String: Any])
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let radice = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let altro = radice["altro"] as? [String: Any], let disp = altro["dispositivo"] as? String,
              let statoGrezzo = altro["stato"], let quando = FiloCondiviso.data(altro["aggiornato"] as? String),
              let datiStato = try? JSONSerialization.data(withJSONObject: statoGrezzo) else { return nil }
        let decodifica = JSONDecoder()
        decodifica.dateDecodingStrategy = .iso8601
        guard let stato = try? decodifica.decode(Stato.self, from: datiStato) else { return nil }
        let preso = UserDefaults.standard.object(forKey: FiloCondiviso.chiaveImportato) as? Date ?? .distantPast
        guard quando > preso, let ultimaLa = stato.battute.last?.d, ultimaLa > ultimaQui else { return nil }
        return Altro(dispositivo: disp, stato: stato, aggiornato: quando)
    }

    /// Preso: lo stesso filo non si riprende due volte.
    func segnaPreso(_ a: Altro) { UserDefaults.standard.set(a.aggiornato, forKey: FiloCondiviso.chiaveImportato) }

    /// «2026-11-18T12:03:04.123456+00:00» (Postgres) o con la Z.
    nonisolated static func data(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
#endif
