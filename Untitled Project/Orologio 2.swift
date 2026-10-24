import Foundation
import Security
import WatchConnectivity
import CoreLocation
import UIKit

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
        // build 23, MUSICA dal polso: «stato», «play», «pausa», «avanti», «indietro» sul lettore dell'iPhone (MusicaJarvis.swift)
        if let comando = message["musica"] as? String {
            nonisolated(unsafe) let rispondi = replyHandler
            Task { @MainActor in rispondi(await PonteMusica.esegui(comando)) }
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
