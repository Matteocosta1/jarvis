#if os(iOS)
import Foundation
import EventKit
import MapKit
import CoreLocation
import UserNotifications
import UIKit

// MARK: - 14 nov · L'INIZIATIVA
// Il signore (14 nov, 03:23): «le dice le cose prima che lei chieda, al momento giusto e senza disturbare. «Sir, fra 40 minuti ha
// il dentista e c'è traffico», «Bea le ha scritto mentre parlava»». Tutto sul telefono, senza il cervello (subito, anche offline):
// - IMPEGNI: ogni minuto, con JARVIS davanti, guarda il calendario delle prossime due ore. Con un luogo calcola quanto ci vuole da
//   dove si trova (a piedi se è vicino, se no in auto col traffico di adesso, Apple Mappe) e avvisa dieci minuti prima dell'ora di
//   uscire; senza luogo, mezz'ora prima. Ogni impegno una volta sola. Con JARVIS dietro ci pensa una notifica all'ora di uscire
//   (arriva anche all'Apple Watch).
// - MESSAGGI (dall'automazione «Messaggio ricevuto»): arrivato mentre parlavate, lo dice alla prima pausa vera (finito il seguito);
//   se no subito. Corto lo legge, lungo chiede «Glielo leggo?» (un sì lo legge, senza cervello). Più messaggi insieme: una frase sola.
// - QUANDO (le regole delle INIZIATIVE del mockup): solo con JARVIS davanti e in attesa, mai sopra una voce (la sua o quella di
//   JARVIS), mai durante l'avvio, il rito, l'Interprete, il Trainer, il Wiretap, la Sentinella o la fotocamera; mai mentre lavora
//   (una sezione davanti o la tastiera aperta), con la musica, in RISERVATO o di notte (23–7): lì solo FILO, tranne quello che non
//   può aspettare (è ora di uscire). Col microfono spento o col muto mai la voce. Gli impegni al massimo uno ogni 4 minuti.
//   FILO lo mostra sempre, subito. «Non ora»: zitto per un'ora; «basta iniziative»: spente finché non dice «riprendi le iniziative».

@MainActor
final class Iniziativa {
    static let condivisa = Iniziativa()

    /// Chi parla (Jarvis): la frase, con il seguito aperto dopo («sì», «rispondile che…», «portami lì» senza «Jarvis»).
    var parla: ((String) -> Void)?
    /// JARVIS può dire una cosa da sé adesso (Jarvis). `urgente`: vale anche con la musica e in RISERVATO.
    var libero: ((_ urgente: Bool) -> Bool)?
    /// Il signore sta parlando con JARVIS (ascolta, pensa, parla, o il seguito è ancora aperto).
    var inConversazione: (() -> Bool)?

    private enum Tipo { case impegno, messaggio, batteria }
    private struct Avviso {
        let chiave: String
        let tipo: Tipo
        let frase: String
        let urgente: Bool
        let scade: Date
        var voce: VoceRegistro? = nil
        var mentreParlavamo = false
    }
    private var coda: [Avviso] = []
    private var giro: Task<Void, Never>?
    private var attesaPausa: Task<Void, Never>?
    private var ultimaDetta = Date.distantPast
    private var ultimoImpegnoDetto = Date.distantPast
    private var ultimoControllo = Date.distantPast
    /// «Non ora»: niente iniziative fino a quest'ora (un'ora).
    private var pausaFino = Date.distantPast
    /// «Basta iniziative»: spente, anche dopo un riavvio, finché non dice «riprendi le iniziative».
    private var spente = UserDefaults.standard.bool(forKey: "iniziativa.spente") {
        didSet { UserDefaults.standard.set(spente, forKey: "iniziativa.spente") }
    }
    /// La tastiera è aperta: lui sta scrivendo (lavora).
    private(set) var tastieraSu = false
    /// Le iniziative tacciono («non ora», «basta iniziative»): anche le proposte delle abitudini.
    var tace: Bool { spente || Date() < pausaFino }

    private init() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Iniziativa.condivisa.tastieraSu = true }
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Iniziativa.condivisa.tastieraSu = false }
        }
    }
    private let calendario = EKEventStore()
    /// Il viaggio verso ogni impegno, ricalcolato ogni 5 minuti (Apple Mappe non va interrogato a ogni giro).
    private var viaggi: [String: (calcolato: Date, viaggio: Viaggio?)] = [:]
    private static var luoghi: [String: CLLocationCoordinate2D] = [:]
    /// Le cose già dette (chiave → quando), ricordate un giorno anche dopo un riavvio.
    private var dette: [String: Date] = {
        let d = (UserDefaults.standard.dictionary(forKey: "iniziativa.dette") as? [String: Date]) ?? [:]
        return d.filter { Date().timeIntervalSince($0.value) < 86_400 }
    }()

    struct Viaggio {
        let secondi: Double
        let metri: Double
        let aPiedi: Bool
        /// Più lento di 14 km/h su almeno 3 km: c'è traffico vero.
        var traffico: Bool { !aPiedi && metri >= 3000 && metri / max(secondi, 1) < 14 / 3.6 }
    }

    // MARK: Il giro

    /// JARVIS davanti (all'avvio e a ogni rientro): il giro parte (ogni 20 s guarda se può dire qualcosa, ogni minuto il calendario).
    /// Gli impegni già arrivati come notifica mentre era dietro non si ripetono a voce.
    func avvia() {
        Task { await riprendiDaNotifiche() }
        guard giro == nil else { return }
        giro = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))                   // prima l'avvio
            while !Task.isCancelled {
                guard let self else { return }
                if UIApplication.shared.applicationState == .active {
                    if Date().timeIntervalSince(self.ultimoControllo) >= 60 {
                        self.ultimoControllo = Date()
                        self.controllaBatteria()
                        await self.controllaImpegni()
                    }
                    self.consegna()
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    /// JARVIS dietro: il giro si ferma e gli impegni con un luogo diventano notifiche all'ora di uscire (iOS concede qualche secondo).
    func ferma() {
        giro?.cancel()
        giro = nil
        attesaPausa?.cancel()
        let compito = CompitoSfondo()
        compito.id = UIApplication.shared.beginBackgroundTask(withName: "jarvis-iniziativa") { compito.chiudi() }
        Task { @MainActor [weak self] in
            await self?.programmaNotificheImpegni()
            compito.chiudi()
        }
    }

    /// Una pausa nel dialogo (JARVIS ha finito di parlare): appena il seguito si chiude e nessuno parla, è il momento.
    func pausa() {
        guard !coda.isEmpty else { return }
        attesaPausa?.cancel()
        attesaPausa = Task { @MainActor [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, !self.coda.isEmpty else { return }
                if self.consegna() { return }
            }
        }
    }

    // MARK: Gli impegni

    private func controllaImpegni() async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let ora = Date()
        let eventi = calendario.events(matching: calendario.predicateForEvents(withStart: ora, end: ora.addingTimeInterval(7200), calendars: nil))
            .filter { !$0.isAllDay && $0.startDate > ora.addingTimeInterval(240) }
            .sorted { $0.startDate < $1.startDate }
        for e in eventi.prefix(3) {
            let chiave = Iniziativa.chiave(e)
            guard dette[chiave] == nil, !coda.contains(where: { $0.chiave == chiave }) else { continue }
            let titolo = Iniziativa.titolo(e)
            let viaggio = await self.viaggio(verso: e, chiave: chiave)
            let adesso = Date()                                         // il viaggio può aver chiesto qualche secondo
            let mancano = e.startDate.timeIntervalSince(adesso)
            let quandoDirlo: Date
            if let v = viaggio, v.secondi >= 180 { quandoDirlo = e.startDate.addingTimeInterval(-v.secondi - 900) }   // 5' di margine, 10' prima di uscire
            else if viaggio != nil { quandoDirlo = e.startDate.addingTimeInterval(-900) }                           // è qui vicino: un quarto d'ora prima
            else { quandoDirlo = e.startDate.addingTimeInterval(-1800) }                                             // senza luogo: mezz'ora prima
            guard adesso >= quandoDirlo else { continue }
            let partenza = viaggio.map { e.startDate.addingTimeInterval(-$0.secondi - 300) }
            let urgente = partenza.map { $0.timeIntervalSince(adesso) < 300 } ?? (mancano < 900)
            coda.append(Avviso(chiave: chiave, tipo: .impegno, frase: Iniziativa.fraseImpegno(titolo: titolo, mancano: mancano, viaggio: viaggio),
                               urgente: urgente, scade: e.startDate))
            // FILO subito, anche se la voce aspetta: l'impegno, fra quanto, il viaggio
            // (niente « · »: in FILO l'Agenda va a capo lì, un impegno per riga) «17:30 Dentista — fra 40 min, in auto 25 min, traffico»
            var riga = "\(Iniziativa.orario(e.startDate)) \(titolo) — fra \(Iniziativa.minutiBrevi(mancano))"
            if let v = viaggio, v.secondi >= 180 {
                riga += ", \(v.aPiedi ? "a piedi" : "in auto") \(Int((v.secondi / 60).rounded())) min" + (v.traffico ? ", traffico" : "")
            }
            Filo.condiviso.mostra("iniz:" + chiave, titolo: "Agenda", riga: String(riga.prefix(90)), sezione: "Briefing", dura: 6)
            Filo.condiviso.metti(CosaFilo(chiave: "imp:" + chiave, tipo: "impegno", nomi: ["impegno", "appuntamento"], titolo: titolo,
                                          riga: riga, detto: "l'impegno delle \(Iniziativa.orario(e.startDate))",
                                          daMandare: "\(titolo) alle \(Iniziativa.orario(e.startDate)).", sezione: "Briefing"))
            Regia.condivisa.evento("iniziativa: \(riga)")
        }
    }

    // MARK: La batteria (come nel mockup: «Batteria al 18 per cento, Sir: la metterei in carica.»)

    /// Sotto il 20% e staccato dalla corrente: una volta sola, e di nuovo al 10%, finché non torna in carica. 14 nov (il signore:
    /// «la batteria si vedesse nella tab, con un'icona»): anche nella tab, col simbolo della batteria, subito.
    private func controllaBatteria() {
        let d = UIDevice.current
        guard d.isBatteryMonitoringEnabled, d.batteryLevel >= 0 else { return }
        if d.batteryState == .charging || d.batteryState == .full { dette["batteria20"] = nil; dette["batteria10"] = nil; return }
        let p = Int((d.batteryLevel * 100).rounded())
        let soglia = p <= 10 ? "batteria10" : p <= 20 ? "batteria20" : nil
        guard let soglia, dette[soglia] == nil, !coda.contains(where: { $0.chiave == soglia }) else { return }
        if soglia == "batteria10" { dette["batteria20"] = Date() }               // al 10% la frase del 20% non serve più
        Filo.condiviso.mostra("iniz:batteria", titolo: "Batteria", riga: "\(p)% · " + (p <= 10 ? "da caricare subito" : "da caricare"),
                              sezione: "Batteria", dura: 6, icona: p <= 10 ? "battery.0percent" : "battery.25percent")
        let frase = p <= 10
            ? Battute.una("in.batt10", ["Sir, siamo al \(Battute.numero(p)) per cento: lo metterei in carica adesso.", "Batteria al \(Battute.numero(p)) per cento, Sir. Ormai è urgente."])
            : Battute.una("in.batt", ["Batteria al \(Battute.numero(p)) per cento, Sir: la metterei in carica.", "Sir, siamo al \(Battute.numero(p)) per cento. Meglio caricarlo adesso."])
        coda.append(Avviso(chiave: soglia, tipo: .batteria, frase: frase, urgente: false, scade: Date().addingTimeInterval(1800)))
    }

    private static func chiave(_ e: EKEvent) -> String {
        "evento:" + (e.eventIdentifier ?? e.title ?? "") + "@\(Int(e.startDate.timeIntervalSince1970))"
    }

    private static func titolo(_ e: EKEvent) -> String {
        let t = (e.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "un impegno" : t
    }

    /// Il viaggio verso l'impegno (nil: senza luogo, o Apple Mappe non risponde), al massimo ogni 5 minuti per impegno.
    private func viaggio(verso e: EKEvent, chiave: String) async -> Viaggio? {
        if let v = viaggi[chiave], Date().timeIntervalSince(v.calcolato) < 300 { return v.viaggio }
        var calcolato: Viaggio?
        if let dove = await destinazione(e) { calcolato = await tempoDiViaggio(a: dove) }
        viaggi[chiave] = (Date(), calcolato)
        return calcolato
    }

    /// Dove va l'impegno: il luogo del calendario (coordinate se ci sono, se no l'indirizzo cercato in Apple Mappe).
    private func destinazione(_ e: EKEvent) async -> CLLocationCoordinate2D? {
        if let g = e.structuredLocation?.geoLocation { return g.coordinate }
        guard let testo = e.location?.trimmingCharacters(in: .whitespacesAndNewlines), testo.count >= 4 else { return nil }
        if let c = Iniziativa.luoghi[testo] { return c }
        let q = MKLocalSearch.Request()
        q.naturalLanguageQuery = testo
        guard let c = try? await MKLocalSearch(request: q).start().mapItems.first?.placemark.coordinate else { return nil }
        Iniziativa.luoghi[testo] = c
        return c
    }

    /// Quanto ci vuole da qui: a piedi se è vicino (fino a 20 minuti), se no in auto col traffico di adesso (Apple Mappe).
    private func tempoDiViaggio(a: CLLocationCoordinate2D) async -> Viaggio? {
        guard let p = await Posizione.attuale(), let lat = p["lat"] as? Double, let lon = p["lon"] as? Double else { return nil }
        let da = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if let piedi = await DatiTravel.aPiedi(da: da, a: a), piedi.secondi <= 1200 {
            return Viaggio(secondi: piedi.secondi, metri: piedi.metri, aPiedi: true)
        }
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: da))
        r.destination = MKMapItem(placemark: MKPlacemark(coordinate: a))
        r.transportType = .automobile
        r.departureDate = Date()
        guard let eta = try? await MKDirections(request: r).calculateETA() else { return nil }
        return Viaggio(secondi: eta.expectedTravelTime, metri: eta.distance, aPiedi: false)
    }

    // MARK: I messaggi

    /// Un messaggio appena arrivato (l'automazione di Comandi, RegistroMessaggi). Con JARVIS dietro ci pensa iOS.
    func messaggio(_ v: VoceRegistro) {
        guard UIApplication.shared.applicationState == .active else { return }
        let parlavamo = inConversazione?() ?? false
        let testo = (v.testo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Filo.condiviso.mostra("iniz:msg:" + v.id.uuidString, titolo: "Messaggi", riga: String("\(Filo.detto(v.nome)): \(testo)".prefix(90)),
                              sezione: "Messaggi", suono: false)          // il suono l'ha già fatto iOS
        coda.append(Avviso(chiave: "msg:" + v.id.uuidString, tipo: .messaggio, frase: "", urgente: false,
                           scade: Date().addingTimeInterval(360), voce: v, mentreParlavamo: parlavamo))
        pausa()
    }

    // MARK: I comandi a voce (come nel mockup)

    /// «Non ora», «basta iniziative», «riprendi le iniziative»: la battuta di JARVIS (nil: non è un comando delle iniziative).
    func comando(_ frase: String) -> String? {
        let n = Regia.paroleComando(frase).joined(separator: " ")
        if n == "non ora" {
            pausaFino = Date().addingTimeInterval(3600)
            coda.removeAll { !$0.urgente && $0.tipo == .messaggio }
            Regia.condivisa.evento("iniziative: zitto per un'ora")
            return Battute.una("nonOra", ["Come vuole: per un'ora niente iniziative.", "Ricevuto, Sir. Per un'ora me ne sto buono.", "Silenzio per un'ora, Sir."])
        }
        if ["basta iniziative", "basta le iniziative", "basta proposte", "basta le proposte", "niente iniziative", "niente piu iniziative"].contains(n) {
            spente = true
            coda.removeAll()
            Regia.condivisa.evento("iniziative spente")
            return "Va bene, Sir: niente più iniziative. Quando le rivuole, me lo dica."
        }
        if ["riprendi le iniziative", "riattiva le iniziative", "rimetti le iniziative", "riprendi le proposte", "riattiva le proposte",
            "rimetti le proposte", "iniziative si"].contains(n) {
            spente = false
            pausaFino = .distantPast
            Regia.condivisa.evento("iniziative accese")
            return Battute.una("riprendo", ["Bentornate. Solo cose utili, promesso.", "Iniziative di nuovo accese, Sir: poche e utili."])
        }
        return nil
    }

    // MARK: Quando dirlo

    /// Dice la prossima cosa, se può adesso (le scadute si buttano). Vero se l'ha detta.
    @discardableResult
    func consegna() -> Bool {
        coda.removeAll { $0.scade < Date() }
        guard !coda.isEmpty else { return false }
        guard !tace else { return false }                               // «non ora», «basta iniziative»: solo FILO
        let ora = Calendar.current.component(.hour, from: Date())
        let notte = ora >= 23 || ora < 7
        // prima quello che non può aspettare
        guard let k = coda.firstIndex(where: \.urgente) ?? coda.indices.first else { return false }
        let a = coda[k]
        if a.urgente {
            guard libero?(true) == true else { return false }
        } else {
            guard !notte, !tastieraSu, libero?(false) == true, Date().timeIntervalSince(ultimaDetta) > 20 else { return false }
            if a.tipo != .messaggio, Date().timeIntervalSince(ultimoImpegnoDetto) < 240 { return false }
        }
        let frase: String
        if a.tipo == .messaggio {
            let tutti = coda.filter { $0.tipo == .messaggio }
            coda.removeAll { $0.tipo == .messaggio }
            frase = fraseMessaggi(tutti)
        } else {
            coda.remove(at: k)
            frase = a.frase
            ultimoImpegnoDetto = Date()
            if a.tipo == .impegno { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["iniziativa." + a.chiave]) }
        }
        segnaDetta(a.chiave)
        ultimaDetta = Date()
        guard !frase.isEmpty else { return false }
        Regia.condivisa.evento("JARVIS di sua iniziativa: «\(frase.count > 120 ? String(frase.prefix(120)) + "…" : frase)»")
        parla?(frase)
        return true
    }

    private func segnaDetta(_ chiave: String) {
        dette[chiave] = Date()
        dette = dette.filter { Date().timeIntervalSince($0.value) < 86_400 }
        UserDefaults.standard.set(dette, forKey: "iniziativa.dette")
    }

    /// «Sir, le ha scritto Bea: «Arrivo alle nove».» · «Sir, mentre parlavamo le ha scritto la mamma. Glielo leggo?» ·
    /// «Sir, le hanno scritto Bea e Marco. Glieli leggo?» Il messaggio entra nel filo: «rispondile che…», «leggimelo» funzionano.
    private func fraseMessaggi(_ lista: [Avviso]) -> String {
        let voci = lista.compactMap(\.voce).sorted { $0.quando < $1.quando }
        guard let ultima = voci.last else { return "" }
        let mentre = lista.contains(where: \.mentreParlavamo) ? "mentre parlavamo " : ""
        for v in voci { Filo.condiviso.metti(Insieme.cosaMessaggio(v)) }
        Filo.condiviso.persona(ultima.nome)
        var nomi: [String] = []
        for v in voci where !nomi.contains(v.nome) { nomi.append(v.nome) }
        let chi = nomi.map { Iniziativa.mittente($0) }
        if voci.count == 1 {
            let t = (ultima.testo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return "Sir, \(mentre)le ha scritto \(chi[0])." }
            if t.count <= 120 { return "Sir, \(mentre)le ha scritto \(chi[0]): «\(t)»" }
            proponiLettura(voci, frase: "Glielo leggo?")
            return "Sir, \(mentre)le ha scritto \(chi[0]). Glielo leggo?"
        }
        proponiLettura(voci, frase: "Glieli leggo?")
        if nomi.count == 1 { return "Sir, \(mentre)\(chi[0]) le ha scritto \(Battute.numero(voci.count)) messaggi. Glieli leggo?" }
        let elenco = chi.count == 2 ? "\(chi[0]) e \(chi[1])" : chi.dropLast().joined(separator: ", ") + " e " + (chi.last ?? "")
        return "Sir, \(mentre)le hanno scritto \(elenco). Glieli leggo?"
    }

    /// Un sì nei 45 secondi dopo la domanda li legge (Regia.proposta, senza cervello).
    private func proponiLettura(_ voci: [VoceRegistro], frase: String) {
        let letti = voci.map { v in
            Iniziativa.maiuscola(Iniziativa.mittente(v.nome)) + ": «" + (v.testo ?? "").trimmingCharacters(in: .whitespacesAndNewlines) + "»"
        }
        let testo = letti.joined(separator: " ")
        let leggi: @MainActor () async -> String? = { testo }
        Regia.condivisa.proposta = (frase, Date(), leggi)
    }

    /// Il mittente detto: «Bea», «la mamma»; un numero che non è in rubrica non si legge cifra per cifra.
    private static func mittente(_ nome: String) -> String {
        nome.filter(\.isNumber).count >= 6 ? "un numero che non è in rubrica" : Filo.detto(nome)
    }

    /// «la mamma» → «La mamma» (all'inizio della lettura).
    private static func maiuscola(_ s: String) -> String { (s.first.map { String($0).uppercased() } ?? "") + s.dropFirst() }

    // MARK: Con JARVIS dietro: le notifiche

    /// Gli impegni con un luogo delle prossime 4 ore diventano notifiche all'ora di uscire meno dieci minuti (col viaggio di
    /// adesso); arrivano anche all'Apple Watch. Quelli senza luogo li avvisa già il Calendario.
    private func programmaNotificheImpegni() async {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let centro = UNUserNotificationCenter.current()
        let ora = Date()
        let eventi = calendario.events(matching: calendario.predicateForEvents(withStart: ora, end: ora.addingTimeInterval(4 * 3600), calendars: nil))
            .filter { !$0.isAllDay && $0.startDate > ora.addingTimeInterval(600) }
            .sorted { $0.startDate < $1.startDate }
        for e in eventi.prefix(4) {
            let chiave = Iniziativa.chiave(e)
            guard dette[chiave] == nil, let v = await viaggio(verso: e, chiave: chiave), v.secondi >= 180 else { continue }
            let uscita = e.startDate.addingTimeInterval(-v.secondi - 300)
            let quando = uscita.addingTimeInterval(-600)
            guard quando > Date().addingTimeInterval(30) else { continue }
            let c = UNMutableNotificationContent()
            c.title = "JARVIS"
            let minuti = Int((v.secondi / 60).rounded())
            c.body = "Sir, alle \(Iniziativa.orario(e.startDate)) ha \(Iniziativa.articolato(Iniziativa.titolo(e))): esca verso le \(Iniziativa.orario(uscita))"
                + " (\(v.aPiedi ? "a piedi" : "in auto") circa \(minuti) minuti)."
            c.sound = .default
            let scatto = UNTimeIntervalNotificationTrigger(timeInterval: max(quando.timeIntervalSinceNow, 1), repeats: false)
            try? await centro.add(UNNotificationRequest(identifier: "iniziativa." + chiave, content: c, trigger: scatto))
        }
    }

    /// Di nuovo davanti: le notifiche ancora da arrivare le sostituisce la voce; quelle già arrivate non si ripetono a voce.
    private func riprendiDaNotifiche() async {
        let centro = UNUserNotificationCenter.current()
        let arrivate = await centro.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("iniziativa.") }
        for id in arrivate { segnaDetta(String(id.dropFirst("iniziativa.".count))) }
        let inArrivo = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("iniziativa.") }
        if !inArrivo.isEmpty { centro.removePendingNotificationRequests(withIdentifiers: inArrivo) }
    }

    // MARK: Le parole

    /// «Sir, fra quaranta minuti ha il dentista. In auto, col traffico di adesso, ci vogliono venticinque minuti: le conviene uscire
    /// fra dieci minuti.» · «… e c'è traffico: …» · «Sir, fra mezz'ora ha la riunione.»
    static func fraseImpegno(titolo: String, mancano: TimeInterval, viaggio: Viaggio?) -> String {
        let prima = "Sir, fra \(minutiDetti(mancano)) ha \(articolato(titolo))"
        guard let v = viaggio, v.secondi >= 180 else {
            return prima + (viaggio != nil ? ", qui vicino." : ".")
        }
        let viaggioDetto = minutiDetti(max(60, v.secondi))
        let uscire = mancano - v.secondi - 300
        let seconda: String
        if v.aPiedi { seconda = "A piedi sono \(viaggioDetto)" }
        else if v.traffico { seconda = "In auto ci vogliono \(viaggioDetto)" }
        else { seconda = "In auto, col traffico di adesso, ci vogliono \(viaggioDetto)" }
        let uscita = uscire <= 60 ? ": è ora di uscire." : ": le conviene uscire fra \(minutiDetti(uscire))."
        return prima + (v.traffico ? " e c'è traffico. " : ". ") + seconda + uscita
    }

    /// «il dentista», «la riunione con Marco», «l'aperitivo», «lo studio»; un titolo che non è un nome comune resta com'è,
    /// fra le virgolette («ha in agenda «Marco»»).
    static func articolato(_ titolo: String) -> String {
        let parole = FineFrase.paroleNude(titolo)
        guard let prima = parole.first else { return "in agenda «\(titolo)»" }
        let comune = titolo.first?.isLowercase == true || generiImpegni.contains(prima) || Filo.generi[prima] != nil
        guard comune else { return "in agenda «\(titolo)»" }
        let t = (titolo.first.map { String($0).lowercased() } ?? "") + titolo.dropFirst()
        let g = Filo.generi[prima] ?? (prima.hasSuffix("a") || prima.hasSuffix("ione") ? "f" : "m")
        if let c = prima.first, "aeiou".contains(c) { return "l'" + t }
        if g.hasPrefix("f") { return "la " + t }
        let seconda = prima.dropFirst().first
        let lo = prima.hasPrefix("z") || prima.hasPrefix("gn") || prima.hasPrefix("ps") || prima.hasPrefix("x") || prima.hasPrefix("y")
            || (prima.hasPrefix("s") && seconda.map { !"aeiou".contains($0) } == true)
        return (lo ? "lo " : "il ") + t
    }
    private static let generiImpegni: Set<String> = ["dentista", "palestra", "riunione", "medico", "cena", "pranzo", "call", "aperitivo",
                                                     "colazione", "visita", "appuntamento", "incontro", "lezione", "allenamento", "volo",
                                                     "treno", "serata", "festa", "compleanno", "colloquio", "meeting", "studio", "parrucchiere"]

    /// «un minuto», «quaranta minuti», «un quarto d'ora», «mezz'ora», «tre quarti d'ora», «un'ora e un quarto», «due ore».
    static func minutiDetti(_ secondi: TimeInterval) -> String {
        let m = max(1, Int((secondi / 60).rounded()))
        switch m {
        case 1: return "un minuto"
        case 15: return "un quarto d'ora"
        case 30: return "mezz'ora"
        case 45: return "tre quarti d'ora"
        case 60: return "un'ora"
        case 75: return "un'ora e un quarto"
        case 90: return "un'ora e mezza"
        default: break
        }
        if m < 60 { return "\(Battute.numero(m)) minuti" }
        let h = m / 60, r = m % 60
        let ore = h == 1 ? "un'ora" : "\(Battute.numero(h)) ore"
        if r == 0 { return ore }
        return ore + " e " + (r == 1 ? "un minuto" : "\(Battute.numero(r)) minuti")
    }

    static func minutiBrevi(_ secondi: TimeInterval) -> String {
        let m = max(1, Int((secondi / 60).rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func orario(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
#endif
