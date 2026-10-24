import Foundation
import Security
import WatchConnectivity
import CoreLocation
import UIKit

/// Ponte verso l'Apple Watch: consegna all'orologio la parola d'ordine e l'indirizzo del cervello,
/// cerca le foto per l'orologio e porta all'orologio gli allarmi e le immagini della Sentinella.
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

    // MARK: Build 23: la GUIDA di SATELLITE al polso

    private let chiaveGuida = NSLock()
    private var ultimaGuida: [String: Any]?

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
            chiaveGuida.lock(); let g = ultimaGuida; chiaveGuida.unlock()
            risposta(["guida": g ?? ["fine": true]])
            return
        }
        let lat = (m["lat"] as? NSNumber)?.doubleValue, lon = (m["lon"] as? NSNumber)?.doubleValue
        let nome = m["nome"] as? String ?? "", via = m["via"] as? String ?? "", chiave = m["chiave"] as? String ?? ""
        let ricordo = (m["ricordo"] as? NSNumber)?.intValue
        Task { @MainActor in
            if cosa == "ferma" { MotoreGuida.condiviso.ferma(); risposta(["ok": true]); return }
            guard cosa == "avvia", let lat, let lon, !nome.isEmpty else { risposta(["errore": "richiesta non valida"]); return }
            // senza la modalità «posizione in sottofondo», con JARVIS chiuso sull'iPhone il GPS non parte
            let modi = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
            if UIApplication.shared.applicationState == .background && !modi.contains("location") {
                risposta(["errore": "Apra JARVIS sull'iPhone, Sir: la guida parte da lì."]); return
            }
            MotoreGuida.condiviso.avvia(LuogoSat(chiave: chiave.isEmpty ? "p\(lat),\(lon)" : chiave, ricordo: ricordo, tipo: "posto", nome: nome,
                                                via: via.isEmpty ? nome : via, persona: nil, lat: lat, lon: lon, quando: ""))
            risposta(["ok": true])
        }
    }

    nonisolated static func datiDaConsegnare() -> [String: String] {
        let indirizzo = UserDefaults.standard.string(forKey: "indirizzo") ?? indirizzoPredefinito
        // il numero di Bea: per il «Ti penso» dal polso
        return ["token": leggiToken(), "indirizzo": indirizzo, "numeroBea": UserDefaults.standard.string(forKey: "numeroBea") ?? ""]
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

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
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
