#if os(iOS)
import UIKit
import UserNotifications

/// Le notifiche di JARVIS quando parla per primo: il briefing del mattino e gli avvisi mandati dal cervello.
/// L'iPhone si registra presso il cervello con il suo token; il cervello (jarvis-briefing) manda le push tramite Apple.
/// Le notifiche dell'iPhone compaiono da sole anche sull'Apple Watch.
final class Notifiche: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { await Notifiche.chiediPermesso(application) }
        return true
    }

    static func chiediPermesso(_ application: UIApplication) async {
        let centro = UNUserNotificationCenter.current()
        let ok = (try? await centro.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { await MainActor.run { application.registerForRemoteNotifications() } }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await Notifiche.registra(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        print("notifiche push non disponibili: \(error.localizedDescription)")
    }

    /// Consegna il token al cervello (una volta ogni tre giorni, o quando cambia).
    static func registra(_ token: String) async {
        guard let url = URL(string: Impostazioni.indirizzo) else { return }
        let parola = Portachiavi.leggi()
        guard !parola.isEmpty else { return }
        let difese = UserDefaults.standard
        if difese.string(forKey: "pushToken") == token, let quando = difese.object(forKey: "pushRegistrato") as? Date,
           Date().timeIntervalSince(quando) < 3 * 86400 { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(parola, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["registra_push": token, "dispositivo": "iphone"])
        guard let (_, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return }
        difese.set(token, forKey: "pushToken")
        difese.set(Date(), forKey: "pushRegistrato")
    }

    /// App aperta: la notifica si mostra lo stesso, in alto.
    func userNotificationCenter(_ centro: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        // il Tocco d'aiuto di Bea con l'app aperta: la schermata d'allarme parte subito, senza dover toccare la notifica
        if let s = Notifiche.sos(n.request.content.userInfo) {
            await MainActor.run { Comandi.condiviso.richiesta = .beaSOS(lat: s.lat, lon: s.lon, prova: s.prova, id: s.id) }
        }
        return [.banner, .sound]
    }

    /// La richiesta d'aiuto di Bea, se la notifica è quella.
    nonisolated static func sos(_ info: [AnyHashable: Any]) -> (lat: Double?, lon: Double?, prova: Bool, id: Int)? {
        guard info["jarvis_azione"] as? String == "bea_sos" else { return nil }
        return ((info["lat"] as? NSNumber)?.doubleValue, (info["lon"] as? NSNumber)?.doubleValue, (info["prova"] as? Bool) ?? false,
                (info["sos_id"] as? NSNumber)?.intValue ?? 0)
    }

    /// Tocco sulla notifica: per il briefing JARVIS lo prepara completo (con calendario e sonno); per il resto legge il testo.
    func userNotificationCenter(_ centro: UNUserNotificationCenter, didReceive risposta: UNNotificationResponse) async {
        let contenuto = risposta.notification.request.content
        let azione = contenuto.userInfo["jarvis_azione"] as? String
        let testo = contenuto.userInfo["jarvis_testo"] as? String ?? contenuto.body
        let sos = Notifiche.sos(contenuto.userInfo)
        await MainActor.run {
            if let sos { Comandi.condiviso.richiesta = .beaSOS(lat: sos.lat, lon: sos.lon, prova: sos.prova, id: sos.id); return }
            switch azione {
            case "briefing": Comandi.condiviso.richiesta = .briefing
            case "diario": Comandi.condiviso.richiesta = .diario(testo)     // la domanda della sera: JARVIS la legge e ascolta
            default: Comandi.condiviso.richiesta = .leggi(testo)
            }
        }
    }
}
#endif
