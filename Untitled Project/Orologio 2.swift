import Foundation
import Security
import WatchConnectivity
import CoreLocation
import UIKit

/// Decisione del signore (24 ott, M8): mentre usa l'orologio, l'iPhone per 10 secondi non risponde alle frasi senza «Jarvis».
/// Prima rispondevano tutti e due, e l'iPhone sentiva perfino la voce dell'orologio e le rispondeva.
/// L'orologio lo segnala quando ascolta, pensa o parla (ogni pochi secondi) e quando ha finito: i 10 secondi contano da lì.
nonisolated enum OrologioInUso {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var fino = Date.distantPast
    static let durata: TimeInterval = 10

    static func segnala() { lock.lock(); fino = Date().addingTimeInterval(durata); lock.unlock() }
    static var attivo: Bool { lock.lock(); defer { lock.unlock() }; return Date() < fino }
}

/// Ponte verso l'Apple Watch: consegna all'orologio la parola d'ordine e l'indirizzo del cervello,
/// cerca le foto per l'orologio e porta all'orologio gli allarmi e le immagini della Sentinella. Build 23: la MUSICA comandata dal polso.
/// Non legge altro dall'app: funziona anche quando iOS la sveglia in background su richiesta dell'orologio.
nonisolated final class PonteTelefono: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let condiviso = PonteTelefono()

    private static let servizio = "it.discosizer.jarvis.token"     // lo stesso del Portachiavi dell'app
    private static let indirizzoPredefinito = "https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis"

    nonisolated func avvia() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Lascia in consegna all'orologio la parola d'ordine attuale (arriva anche se l'orologio è lontano).
    nonisolated func invia() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let dati = PonteTelefono.datiDaConsegnare()
        guard !(dati["token"] ?? "").isEmpty else { return }
        try? s.updateApplicationContext(dati)
    }

    /// 11.0 (6): una foto nuova di Bea è diventata ologramma: all'orologio subito se è raggiungibile, altrimenti in coda
    /// (arriva appena l'app dell'orologio si sveglia). Viaggia solo l'ologramma piccolo, mai la foto.
    nonisolated func inviaBea() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let messaggio = FotoBea.perPolso(seNonE: "")
        guard messaggio["jpeg"] != nil else { return }
        if s.isReachable {
            s.sendMessage(messaggio, replyHandler: nil) { _ in s.transferUserInfo(messaggio) }
        } else {
            s.transferUserInfo(messaggio)
        }
    }

    // MARK: Build 23: la GUIDA di SATELLITE al polso

    private let chiaveGuida = NSLock()
    private var ultimaGuida: [String: Any]?
    /// Decisione 39 (24 ott): la guida chiesta dal polso che qui non è partita (niente posizione, niente strada): la meta e il
    /// motivo, la frase di `ErroreSat` («Non ho la sua posizione, Sir.», «Non trovo una strada a piedi fino a lì, Sir.»).
    private var erroreGuida: (chiave: String, testo: String)?

    /// La GUIDA in corso all'orologio (nil: finita). Va solo se l'orologio è raggiungibile adesso: è uno stato che cambia
    /// di continuo, quello vecchio non serve; all'apertura l'orologio chiede lo stato attuale («guida»: «stato»).
    nonisolated func inviaGuida(_ g: GuidaPolsoDati?) {
        let dati: [String: Any] = g?.dizionario ?? ["fine": true]
        chiaveGuida.lock(); ultimaGuida = g == nil ? nil : dati; chiaveGuida.unlock()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled, s.isReachable else { return }
        s.sendMessage(["guida": dati], replyHandler: nil, errorHandler: nil)
    }

    /// L'orologio avvia, ferma o chiede la GUIDA (la guida vive sull'iPhone: percorso, GPS, voce).
    nonisolated private func guidaDalPolso(_ m: [String: Any], rispondi: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let risposta = rispondi
        let cosa = m["guida"] as? String ?? ""
        if cosa == "stato" {
            chiaveGuida.lock(); let g = ultimaGuida; let e = erroreGuida; chiaveGuida.unlock()
            // decisione 39: nessuna guida in corso, ma quella chiesta dal polso non è partita: il motivo, se vale ancora
            // (la stessa meta, ancora senza strada e con lo stesso errore sull'iPhone)
            if g == nil, let e {
                Task { @MainActor in
                    let motore = MotoreGuida.condiviso
                    let vale = motore.luogo?.chiave == e.chiave && motore.percorso == nil && motore.errore == e.testo
                    risposta(["guida": vale ? (["errore": e.testo] as [String: Any]) : (["fine": true] as [String: Any])])   // tipi scritti: i due rami sono dizionari diversi
                }
                return
            }
            risposta(["guida": g ?? ["fine": true]])
            return
        }
        let lat = (m["lat"] as? NSNumber)?.doubleValue, lon = (m["lon"] as? NSNumber)?.doubleValue
        let nome = m["nome"] as? String ?? "", via = m["via"] as? String ?? "", chiave = m["chiave"] as? String ?? ""
        let ricordo = (m["ricordo"] as? NSNumber)?.intValue
        if cosa == "avvia" || cosa == "ferma" { chiaveGuida.lock(); erroreGuida = nil; chiaveGuida.unlock() }   // il motivo di prima non vale più
        Task { @MainActor in
            if cosa == "ferma" { MotoreGuida.condiviso.ferma(); risposta(["ok": true]); return }
            guard cosa == "avvia", let lat, let lon, !nome.isEmpty else { risposta(["errore": "richiesta non valida"]); return }
            // con JARVIS chiuso sull'iPhone il GPS parte solo con la modalità «posizione in sottofondo» e il permesso «Sempre»
            // (con «Durante l'uso» iOS non dà la posizione a un'app in sottofondo che non l'aveva già accesa)
            if UIApplication.shared.applicationState == .background && !MotoreGuida.condiviso.puoPartireInSottofondo {
                risposta(["errore": "Apra JARVIS sull'iPhone, Sir: la guida parte da lì."]); return
            }
            let meta = chiave.isEmpty ? "p\(lat),\(lon)" : chiave
            // decisione 39: un'altra meta. La guida di prima non vale più per «stato»: prima l'orologio, aprendo GUIDA, riceveva
            // ancora la freccia e i metri verso la meta vecchia e, se quella nuova non partiva, il motivo restava nascosto
            // withLock: dentro un Task (contesto async) lock()/unlock() a mano danno l'avviso di Xcode
            if MotoreGuida.condiviso.luogo?.chiave != meta { self.chiaveGuida.withLock { self.ultimaGuida = nil } }
            MotoreGuida.condiviso.avvia(LuogoSat(chiave: meta, ricordo: ricordo, tipo: "posto", nome: nome,
                                                via: via.isEmpty ? nome : via, persona: nil, lat: lat, lon: lon, quando: ""))
            risposta(["ok": true])
            await self.seguiGuidaDalPolso(meta: meta)
        }
    }

    /// Decisione 39 (24 ott): l'«ok» al polso parte subito (la risposta non può aspettare: WatchConnectivity non dice quanto
    /// tiene aperta una risposta), ma la strada si calcola dopo: fino a 10 secondi per la posizione, poi MapKit. Prima, se la
    /// guida non partiva, al polso restava «— · Nessuna guida» senza spiegazione. Ora si segue la guida appena chiesta e, se
    /// non parte, il motivo va al polso, che lo scrive in GUIDA e lo dice. Se parte, la guida arriva già da `inviaPolso`.
    @MainActor private func seguiGuidaDalPolso(meta: String) async {
        let motore = MotoreGuida.condiviso
        for _ in 0..<300 {                                       // al massimo un minuto, poi la guida va per conto suo
            guard motore.luogo?.chiave == meta, !motore.arrivato, motore.percorso == nil else { return }   // partita, fermata o un'altra meta
            if let e = motore.errore { inviaErroreGuida(meta: meta, testo: e); return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Decisione 39: il motivo per cui la guida chiesta dal polso non è partita, all'orologio (e per «stato», se lo chiede dopo).
    /// Senza «nome»: un orologio vecchio lo legge come una guida finita, non come una guida a zero metri.
    nonisolated private func inviaErroreGuida(meta: String, testo: String) {
        chiaveGuida.lock(); erroreGuida = (meta, testo); chiaveGuida.unlock()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled, s.isReachable else { return }
        s.sendMessage(["guida": ["errore": testo]], replyHandler: nil, errorHandler: nil)
    }

    nonisolated static func datiDaConsegnare() -> [String: String] {
        let indirizzo = UserDefaults.standard.string(forKey: "indirizzo") ?? indirizzoPredefinito
        // il numero di Bea: per il «Ti penso» dal polso; 11.0 (6): le prove scelte degli ologrammi (il polso mostra le stesse)
        return ["token": leggiToken(), "indirizzo": indirizzo, "numeroBea": UserDefaults.standard.string(forKey: "numeroBea") ?? "",
                "oloProve": SezioneOlo.scelteInRiga]
    }

    nonisolated static func leggiToken() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servizio,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        invia()
    }

    /// L'orologio avvisa che il signore lo sta usando (ascolta, pensa o parla): vedi `OrologioInUso`.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["orologio"] != nil { OrologioInUso.segnala() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["orologio"] != nil { OrologioInUso.segnala(); replyHandler([:]); return }
        // l'orologio parla con la Sentinella: «guarda ora», «disattiva», «a che punto sei»
        if let comando = message["sentinella"] as? String {
            PonteSentinella.ricevi(comando, rispondi: replyHandler)
            return
        }
        // build 23: l'orologio avvia, ferma o chiede la GUIDA di SATELLITE
        if message["guida"] is String {
            guidaDalPolso(message, rispondi: replyHandler)
            return
        }
        // TRAVEL al polso (26 ott sera): l'orologio chiede, l'iPhone calcola con i dati veri e risponde
        if message["travel"] is String {
            nonisolated(unsafe) let rispondi = replyHandler
            nonisolated(unsafe) let m = message
            Task { @MainActor in rispondi(await PonteTravel.perPolso(m)) }
            return
        }
        // build 23, MUSICA dal polso: «stato», «play», «pausa», «avanti», «indietro» sul lettore dell'iPhone (MusicaJarvis.swift)
        if let comando = message["musica"] as? String {
            nonisolated(unsafe) let rispondi = replyHandler
            Task { @MainActor in rispondi(await PonteMusica.esegui(comando)) }
            return
        }
        // 11.0 (6): Bea sul polso. L'orologio chiede l'ologramma di Bea con la versione che ha già: torna solo se è cambiato
        if message["bea"] as? String == "ologramma" {
            replyHandler(FotoBea.perPolso(seNonE: message["versione"] as? String ?? ""))
            return
        }
        // l'orologio chiede di cercare tra le foto (stanno sull'iPhone)
        if let richiesta = message["foto"] as? String {
            nonisolated(unsafe) let rispondi = replyHandler
            Task { rispondi(await PonteTelefono.cercaFotoPerOrologio(richiesta)) }
            return
        }
        // l'orologio chiede la parola d'ordine
        replyHandler(PonteTelefono.datiDaConsegnare())
    }

    /// Cerca nella galleria per l'orologio: testo per il cervello e miniature piccole (il messaggio deve restare leggero).
    nonisolated static func cercaFotoPerOrologio(_ richiesta: String) async -> [String: Any] {
        let i = (try? JSONSerialization.jsonObject(with: Data(richiesta.utf8))) as? [String: Any] ?? [:]
        func testo(_ o: [String: Any]) -> String {
            String(decoding: (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8), as: UTF8.self)
        }
        guard await FotoLocali.autorizza() else {
            return ["risultato": testo(["errore": "il signore non ha dato accesso alle foto sull'iPhone: Impostazioni › Jarvis › Foto"])]
        }
        var luogo: CLLocation?
        if let nome = i["luogo"] as? String, !nome.isEmpty {
            luogo = (try? await CLGeocoder().geocodeAddressString(nome))?.first?.location
            if luogo == nil { return ["risultato": testo(["errore": "non trovo il luogo «\(nome)»"])] }
        }
        let cosa: [String] = (i["cosa"] as? [String]) ?? ((i["cosa"] as? String).map { $0.components(separatedBy: ",") } ?? [])
        let quante = min((i["quante"] as? NSNumber)?.intValue ?? 8, 8)
        let esito = await FotoLocali.cerca(cosa: cosa, da: data(i["da"]), a: data(i["a"]), luogo: luogo,
                                           raggioKm: 5, album: i["album"] as? String, quante: quante, limiteAI: 150)
        var miniature: [Data] = []
        var totale = 0
        for id in esito.trovate {
            guard let img = await FotoLocali.immagine(id: id, lato: 160), let d = img.jpegData(compressionQuality: 0.55) else { continue }
            if totale + d.count > 48_000 { break }      // i messaggi tra iPhone e orologio devono restare piccoli
            miniature.append(d)
            totale += d.count
        }
        var out: [String: Any] = ["trovate": esito.trovate.count, "mostrate_sull_orologio": miniature.count, "foto": esito.righe,
                                  "nota_per_te": "le foto trovate sono già sullo schermo dell'orologio"]
        if let n = esito.nota { out["nota"] = n }
        return ["risultato": testo(out), "miniature": miniature]
    }

    nonisolated static func data(_ valore: Any?) -> Date? {
        guard let s = valore as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for formato in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = formato
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        invia()     // app dell'orologio appena installata
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()     // cambio di orologio
    }
}
