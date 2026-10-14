import Foundation
import Combine
import HealthKit
import WatchKit
import UserNotifications
import CoreLocation

/// Il cuore del signore: legge i battiti dall'app Salute e, se superano la soglia a riposo,
/// dà 5 secondi per annullare e poi fa partire SMS e chiamata al contatto di emergenza (dal cloud).
@MainActor
final class Cuore: NSObject, ObservableObject {
    static let condiviso = Cuore()

    static let soglia: Double = 130           // troppo alto, a riposo
    static let sogliaBassa: Double = 40       // troppo basso, a riposo
    static let secondiPerAnnullare = 5

    @Published var ultimo: Double?
    @Published var ultimoQuando: Date?
    @Published var conto: Int?                 // secondi rimasti per annullare (nil = nessun allarme in corso)
    @Published var bpmAllarme: Double = 0
    @Published var esito: String?
    @Published var sorveglianza: Bool = UserDefaults.standard.object(forKey: "sorveglianzaCuore") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sorveglianza, forKey: "sorveglianzaCuore") }
    }

    nonisolated private static let negozio = HKHealthStore()
    private var avviato = false
    private var contoAllaRovescia: Task<Void, Never>?
    private var ultimoAllarme = Date.distantPast
    private var ultimoControllato = Date().addingTimeInterval(-600)
    private var annullato = false
    private var motivo = "alto"
    private let gps = CLLocationManager()
    private var ricercaPosizione: Task<String?, Never>?

    // MARK: Avvio

    func avvia() {
        guard !avviato, HKHealthStore.isHealthDataAvailable() else { return }
        avviato = true
        // la posizione serve per mandare al contatto il link «Dove si trova»
        if gps.authorizationStatus == .notDetermined { gps.requestWhenInUseAuthorization() }
        UNUserNotificationCenter.current().delegate = self
        let annulla = UNNotificationAction(identifier: "ANNULLA", title: "ANNULLA", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "ALLARME_CUORE", actions: [annulla], intentIdentifiers: [], options: [])
        ])
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard await Cuore.autorizza() else { return }
            Cuore.negozio.execute(Cuore.queryOsservatore())
            try? await Cuore.negozio.enableBackgroundDelivery(for: HKQuantityType(.heartRate), frequency: .immediate)
            await aggiornaUltimo()
        }
    }

    nonisolated private static func autorizza() async -> Bool {
        let tipi: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate)]
        do {
            try await negozio.requestAuthorization(toShare: [], read: tipi)
            return true
        } catch {
            return false
        }
    }

    // Le callback di HealthKit arrivano su un thread qualsiasi: vanno create fuori dal MainActor.
    nonisolated private static func queryOsservatore() -> HKObserverQuery {
        HKObserverQuery(sampleType: HKQuantityType(.heartRate), predicate: nil) { _, completamento, _ in
            nonisolated(unsafe) let fine = completamento
            Task { @MainActor in
                await Cuore.condiviso.controllaNuoviBattiti()
                fine()
            }
        }
    }

    // MARK: Sorveglianza

    private func controllaNuoviBattiti() async {
        let campioni = await Cuore.leggiBattiti(da: ultimoControllato, limite: 50)
        guard let piuRecente = campioni.first else { return }
        ultimo = piuRecente.bpm
        ultimoQuando = piuRecente.quando
        ultimoControllato = piuRecente.quando
        guard sorveglianza, conto == nil, Date().timeIntervalSince(ultimoAllarme) > 300 else { return }
        // conta solo a riposo: i campioni presi durante l'attività fisica non fanno scattare l'allarme
        if let alto = campioni.first(where: { $0.bpm >= Cuore.soglia && !$0.inAttivita && Date().timeIntervalSince($0.quando) < 600 }) {
            avviaAllarme(bpm: alto.bpm, prova: false, motivo: "alto")
        } else if let basso = campioni.first(where: { $0.bpm > 0 && $0.bpm <= Cuore.sogliaBassa && !$0.inAttivita && Date().timeIntervalSince($0.quando) < 600 }) {
            avviaAllarme(bpm: basso.bpm, prova: false, motivo: "basso")
        }
    }

    /// motivo: "alto", "basso" oppure "manuale" (il tasto SOS: parte subito, senza conto alla rovescia).
    func avviaAllarme(bpm: Double, prova: Bool, motivo: String = "alto") {
        guard conto == nil else { return }
        self.motivo = motivo
        ultimoAllarme = Date()
        bpmAllarme = bpm
        annullato = false
        esito = nil
        conto = Cuore.secondiPerAnnullare
        // mentre scorre il conto alla rovescia, cerca dove si trova il signore
        ricercaPosizione = Task { await self.posizioneAttuale() }
        notificaAllarme(bpm: bpm, prova: prova)
        // tempo extra per finire anche se l'app è in secondo piano
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Allarme cuore JARVIS",
                                                        using: Cuore.attivitaAllarme(bpm: bpm, prova: prova, motivo: motivo))
    }

    // Gira su un thread in background: tiene sveglia l'app finché il conto alla rovescia e l'invio sono finiti.
    nonisolated private static func attivitaAllarme(bpm: Double, prova: Bool, motivo: String) -> @Sendable (Bool) -> Void {
        { scaduto in
            guard !scaduto else { return }
            let semaforo = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await Cuore.condiviso.eseguiContoAllaRovescia(bpm: bpm, prova: prova, motivo: motivo)
                semaforo.signal()
            }
            _ = semaforo.wait(timeout: .now() + 25)
        }
    }

    private func eseguiContoAllaRovescia(bpm: Double, prova: Bool, motivo: String) async {
        // il tasto SOS non aspetta: il conto alla rovescia serve solo quando è l'orologio a decidere
        for s in stride(from: motivo == "manuale" ? 1 : Cuore.secondiPerAnnullare, through: 1, by: -1) {
            if annullato { return }
            conto = s
            WKInterfaceDevice.current().play(.notification)
            try? await Task.sleep(for: .seconds(1))
        }
        if annullato { return }
        conto = nil
        esito = "Avviso il contatto di emergenza…"
        WKInterfaceDevice.current().play(.failure)
        let posizione = await ricercaPosizione?.value ?? nil
        ricercaPosizione = nil
        esito = await Cuore.inviaAllarme(bpm: bpm, prova: prova, posizione: posizione, motivo: motivo,
                                         token: PortachiaviOrologio.leggi(),
                                         indirizzo: Cuore.indirizzoAllarme())
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["allarme-cuore"])
    }

    /// Posizione GPS: una nuova entro 5 secondi, altrimenti l'ultima conosciuta. Formato "lat,lon".
    private func posizioneAttuale() async -> String? {
        let recente = gps.location
        let nuova: CLLocation? = await withTaskGroup(of: CLLocation?.self) { g in
            g.addTask {
                do {
                    for try await aggiornamento in CLLocationUpdate.liveUpdates() {
                        if let l = aggiornamento.location { return l }
                    }
                } catch {}
                return nil
            }
            g.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let primo = await g.next() ?? nil
            g.cancelAll()
            return primo
        }
        guard let l = nuova ?? recente else { return nil }
        return String(format: "%.5f,%.5f", l.coordinate.latitude, l.coordinate.longitude)
    }

    func annulla() {
        guard conto != nil else { return }
        annullato = true
        conto = nil
        esito = "Allarme annullato, Sir."
        WKInterfaceDevice.current().play(.success)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["allarme-cuore"])
    }

    private func notificaAllarme(bpm: Double, prova: Bool) {
        let c = UNMutableNotificationContent()
        c.title = prova ? "PROVA allarme cuore" : (motivo == "manuale" ? "SOS" : "Battito \(Int(bpm)) a riposo")
        c.body = "Tra \(Cuore.secondiPerAnnullare) secondi JARVIS avvisa il contatto di emergenza. Tocchi ANNULLA se sta bene."
        c.sound = .default
        c.categoryIdentifier = "ALLARME_CUORE"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "allarme-cuore", content: c, trigger: nil))
    }

    private static func indirizzoAllarme() -> String {
        let base = ImpostazioniOrologio.indirizzo
        return base.hasSuffix("/jarvis") ? base + "-allarme" : base.replacingOccurrences(of: "/jarvis", with: "/jarvis-allarme")
    }

    nonisolated static func inviaAllarme(bpm: Double, prova: Bool, posizione: String?, motivo: String = "alto", token: String, indirizzo: String) async -> String {
        guard !token.isEmpty, let url = URL(string: indirizzo) else { return "Non ho la parola d'ordine: allarme NON inviato. Apra JARVIS sull'iPhone." }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        var corpo: [String: Any] = ["bpm": bpm, "prova": prova, "motivo": motivo]
        if let posizione { corpo["posizione"] = posizione }
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return "Nessuna connessione: allarme NON inviato." }
        let codice = (r as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        if codice == 200 {
            if json?["ripetuto"] as? Bool == true { return "Il contatto era già stato avvisato pochi minuti fa." }
            let canali = (json?["canali"] as? [String] ?? []).map { $0 == "whatsapp" ? "WhatsApp" : $0 == "sms" ? "SMS" : $0 == "chiamata" ? "telefonata" : $0 }
            let elenco = Array(Set(canali)).sorted().joined(separator: ", ")
            return prova ? "Prova inviata: \(elenco)." : "Contatto di emergenza avvisato: \(elenco). Resti dov'è, Sir."
        }
        return "Allarme non riuscito: \(json?["errore"] as? String ?? "codice \(codice)")."
    }

    // MARK: Lettura dei battiti (anche per «Jarvis, come sta il mio cuore?»)

    nonisolated struct Battito: Sendable { let bpm: Double; let quando: Date; let inAttivita: Bool }

    nonisolated private static func leggiBattiti(da inizio: Date, limite: Int) async -> [Battito] {
        let tipo = HKQuantityType(.heartRate)
        let predicato = HKQuery.predicateForSamples(withStart: inizio, end: nil, options: .strictStartDate)
        let ordine = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { (c: CheckedContinuation<[Battito], Never>) in
            let q = HKSampleQuery(sampleType: tipo, predicate: predicato, limit: limite, sortDescriptors: ordine) { _, campioni, _ in
                let unita = HKUnit.count().unitDivided(by: .minute())
                let battiti = (campioni as? [HKQuantitySample] ?? []).map { s -> Battito in
                    let contesto = (s.metadata?[HKMetadataKeyHeartRateMotionContext] as? NSNumber)?.intValue
                    return Battito(bpm: s.quantity.doubleValue(for: unita), quando: s.endDate,
                                   inAttivita: contesto == HKHeartRateMotionContext.active.rawValue)
                }
                c.resume(returning: battiti)
            }
            negozio.execute(q)
        }
    }

    nonisolated private static func battitoARiposoOggi() async -> Double? {
        let tipo = HKQuantityType(.restingHeartRate)
        let predicato = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: nil)
        let ordine = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { (c: CheckedContinuation<Double?, Never>) in
            let q = HKSampleQuery(sampleType: tipo, predicate: predicato, limit: 1, sortDescriptors: ordine) { _, campioni, _ in
                let unita = HKUnit.count().unitDivided(by: .minute())
                c.resume(returning: (campioni?.first as? HKQuantitySample)?.quantity.doubleValue(for: unita))
            }
            negozio.execute(q)
        }
    }

    func aggiornaUltimo() async {
        if let b = await Cuore.leggiBattiti(da: Date().addingTimeInterval(-6 * 3600), limite: 1).first {
            ultimo = b.bpm
            ultimoQuando = b.quando
        }
    }

    /// Risposta allo strumento «salute_battito» del cervello.
    func riepilogo(ore: Double) async -> String {
        _ = await Cuore.autorizza()
        let finestra = min(max(ore, 1), 48)
        let battiti = await Cuore.leggiBattiti(da: Date().addingTimeInterval(-finestra * 3600), limite: 500)
        let riposo = await Cuore.battitoARiposoOggi()
        var out: [String: Any] = ["finestra_ore": finestra, "soglia_allarme": Cuore.soglia, "sorveglianza_attiva": sorveglianza]
        if let r = riposo { out["a_riposo_oggi"] = Int(r.rounded()) }
        if let u = battiti.first {
            let f = DateFormatter()
            f.locale = Locale(identifier: "it_IT")
            f.dateFormat = "HH:mm"
            let valori = battiti.map(\.bpm)
            out["ultimo"] = ["bpm": Int(u.bpm.rounded()), "ora": f.string(from: u.quando), "durante_attivita": u.inAttivita] as [String: Any]
            out["media"] = Int((valori.reduce(0, +) / Double(valori.count)).rounded())
            out["minimo"] = Int((valori.min() ?? 0).rounded())
            out["massimo"] = Int((valori.max() ?? 0).rounded())
            out["campioni"] = valori.count
            ultimo = u.bpm
            ultimoQuando = u.quando
        } else {
            out["nota"] = "nessun battito registrato nella finestra: l'orologio forse non era al polso o l'accesso a Salute è negato"
        }
        guard let d = try? JSONSerialization.data(withJSONObject: out) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}

extension Cuore: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let azione = response.actionIdentifier
        let categoria = response.notification.request.content.categoryIdentifier
        guard categoria == "ALLARME_CUORE", azione == "ANNULLA" || azione == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            // toccare la notifica apre JARVIS sul conto alla rovescia; il tasto ANNULLA annulla subito
            if azione == "ANNULLA" { Cuore.condiviso.annulla() }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
