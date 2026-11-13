#if os(iOS)
import Foundation
import ActivityKit
import Combine
import UIKit

// MARK: - MARK X · DYNAMIC ISLAND: l'app accende, aggiorna e spegne l'attività di JARVIS (la disegna l'estensione JarvisIsola).
// TRAVEL: dopo «Avvisami» fino all'ora di uscire (+10 min). GUIDA: finché la guida di SATELLITE è accesa, aggiornata alla svolta.
// 26 ott sera (sì del signore): REC (il Wiretap registra anche fuori dall'app), PIOGGIA (la accende il cervello col radar, anche ad
// app chiusa: push-to-start). VOCE tolta dal signore lo stesso giorno (iOS non garantisce di riaccendere il microfono da fuori).
// Dentro JARVIS iOS non mostra la sua stessa attività: si vede quando lei esce dall'app o blocca il telefono.

@MainActor
enum IsolaJarvis {
    private static var attivita: Activity<AttivitaJarvis>?
    private static var guardiaGuida: AnyCancellable?
    /// REC: chi esegue i tasti dell'isola (lo imposta il Wiretap).
    static var rec: ((String) -> Void)?

    private static var permesso: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// All'avvio dell'app: i tasti dell'isola che non aprono JARVIS (ComandoIsola) passano da qui; il cervello riceve il
    /// gettone per accendere l'isola della PIOGGIA anche ad app chiusa.
    static func prepara() {
        ComandiIsola.esegui = { a in
            switch a {
            case "basta": AvvisoTravel.spegni()
            case "ferma": MotoreGuida.condiviso.ferma(); chiudi()
            case "pausa", "riprendi", "stoprec": rec?(a)
            case "ok": chiudiPioggia()
            case "finevoce": fineDialogo?(); chiudiVoci()       // 12.0 (11): si chiude sempre, anche se l'app era stata chiusa
            case "ascolta": Comandi.condiviso.richiesta = .ascolta  // 12.0 (12) · B4: il controllo JARVIS (Centro di Controllo)
            default: break
            }
        }
        // 12.0 (11): un'isola VOCE rimasta accesa da un'app chiusa da iOS (in sottofondo) non ha più padrone e restava fissa
        // fino al riavvio del telefono. JARVIS che parte da zero non ha dialoghi in corso: le spegne
        chiudiVoci()
        if #available(iOS 17.2, *) {
            Task {
                for await dati in Activity<AttivitaJarvis>.pushToStartTokenUpdates {
                    await inviaGettone(dati.map { String(format: "%02x", $0) }.joined())
                }
            }
        }
    }

    /// Il gettone per accendere l'isola da remoto (PIOGGIA): va al cervello (funzione jarvis-briefing, tabella jarvis_isola).
    private static func inviaGettone(_ hex: String) async {
        let base = Impostazioni.indirizzo.replacingOccurrences(of: "/functions/v1/jarvis", with: "/functions/v1/jarvis-briefing")
        guard let url = URL(string: base) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["isola_gettone": hex])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// TRAVEL: il conto alla rovescia per uscire e la linea da prendere.
    static func travel(esci: Date, linea: String, ora: String, percorso: String, meta: String, coloreLinea: String? = nil) {
        let s = AttivitaJarvis.ContentState(tipo: "travel", esci: esci, sigla: linea.isEmpty ? nil : linea, coloreSigla: coloreLinea,
                                            oraMezzo: ora, freccia: nil, via: nil, metri: nil, riga: percorso)
        avvia(s, meta: meta, fine: esci.addingTimeInterval(600))
    }

    static func fineTravel() {
        guard let a = attivita, a.content.state.tipo == "travel" else { return }
        chiudi()
    }

    /// GUIDA: segue il motore della guida di SATELLITE (freccia, via, metri alla svolta) finché è acceso.
    static func seguiGuida(_ m: MotoreGuida) {
        guardiaGuida = m.objectWillChange
            .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
            .sink { _ in DispatchQueue.main.async { MainActor.assumeIsolated { aggiornaGuida(m) } } }   // dopo il cambio, non prima
        aggiornaGuida(m)
    }

    private static func aggiornaGuida(_ m: MotoreGuida) {
        guard m.attiva, let l = m.luogo else {
            guardiaGuida = nil
            if attivita?.content.state.tipo == "guida" { chiudi() }
            return
        }
        let metri = Int((m.mancaTappa ?? 0).rounded())
        let arrivo = m.manca.map { DatiTravel.ora(Date().addingTimeInterval($0 / 1.3)) } ?? ""
        let s = AttivitaJarvis.ContentState(tipo: "guida", esci: nil, sigla: nil, coloreSigla: nil, oraMezzo: nil,
                                            freccia: m.arrivato ? "⚑" : m.frecciaIsola, via: m.arrivato ? l.nome : m.viaIsola, metri: m.arrivato ? 0 : metri,
                                            riga: m.arrivato ? "È arrivato, Sir." : "\(m.dopoIsola.map { "poi \($0) · " } ?? "")arrivo \(arrivo)")
        if let a = attivita, a.content.state.tipo == "guida" {
            Task { await a.update(ActivityContent(state: s, staleDate: nil)) }
        } else {
            avvia(s, meta: l.nome, fine: nil)
        }
    }

    /// La guida è finita («Fine guida», «ferma la guida», l'arrivo): l'isola della guida si spegne.
    static func fineGuida() {
        guardiaGuida = nil
        if attivita?.content.state.tipo == "guida" { chiudi() }
    }

    // MARK: REC (26 ott sera)

    /// Il Wiretap registra fuori dall'app: il tempo (iOS lo fa contare da solo) o, in pausa, quello registrato fin lì.
    static func aggiornaRec(inizio: Date, pausaSecondi: Int?) {
        let s = AttivitaJarvis.ContentState(tipo: "rec", esci: nil, sigla: nil, coloreSigla: nil, oraMezzo: nil, freccia: nil, via: nil, metri: nil,
                                            riga: "Riunione · microfono dell'iPhone", inizio: inizio, pausaSecondi: pausaSecondi)
        if let a = attivita, a.content.state.tipo == "rec" {
            Task { await a.update(ActivityContent(state: s, staleDate: nil)) }
        } else {
            avvia(s, meta: "Wiretap", fine: nil)
        }
    }

    static func fineRec() {
        if attivita?.content.state.tipo == "rec" { chiudi() }
    }

    // MARK: VOCE (12 nov, #16): il dialogo che continua fuori dall'app

    /// «Fine» sull'isola della VOCE: il dialogo finisce e il microfono si spegne (lo imposta JARVIS).
    static var fineDialogo: (() -> Void)?

    /// La VOCE si accende (iOS lo permette solo con l'app ancora davanti: si chiama quando l'app sta uscendo) o si aggiorna.
    /// Non prende mai il posto di un'altra attività di JARVIS (Travel, Guida, Rec): quelle contano di più, e il pallino
    /// arancione di iOS dice comunque che il microfono è acceso.
    static func voce(fase: String, riga: String) {
        let s = AttivitaJarvis.ContentState(tipo: "voce", esci: nil, sigla: nil, coloreSigla: nil, oraMezzo: nil, freccia: nil, via: nil,
                                            metri: nil, riga: riga, fase: fase)
        // 12.0 (11): l'isola ha una scadenza (2 minuti dall'ultimo aggiornamento): se l'app non la aggiorna più, iOS la dà per vecchia
        let scade = Date().addingTimeInterval(120)
        if attivita == nil, let orfana = Activity<AttivitaJarvis>.activities.first(where: { $0.content.state.tipo == "voce" }) {
            attivita = orfana                                   // una VOCE già accesa (anche da prima): si aggiorna quella, non se ne apre un'altra
        }
        if let a = attivita {
            guard a.content.state.tipo == "voce" else { return }
            guard a.content.state != s else { return }
            Task { await a.update(ActivityContent(state: s, staleDate: scade)) }
        } else {
            avvia(s, meta: "JARVIS", fine: scade)
        }
    }

    static var voceAccesa: Bool {
        attivita?.content.state.tipo == "voce" || Activity<AttivitaJarvis>.activities.contains { $0.content.state.tipo == "voce" }
    }

    static func fineVoce() {
        if attivita?.content.state.tipo == "voce" { attivita = nil }
        chiudiVoci()
    }

    /// 12.0 (11): spegne tutte le isole VOCE che iOS tiene accese, non solo quella che l'app ricorda (dopo una chiusura in
    /// sottofondo l'app non la ricordava più, e «Fine» non la chiudeva).
    static func chiudiVoci() {
        for a in Activity<AttivitaJarvis>.activities where a.content.state.tipo == "voce" {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: PIOGGIA (26 ott sera): la accende il cervello; qui solo «Ok»

    static func chiudiPioggia() {
        for a in Activity<AttivitaJarvis>.activities where a.content.state.tipo == "pioggia" {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: Accendere e spegnere

    private static func avvia(_ s: AttivitaJarvis.ContentState, meta: String, fine: Date?) {
        guard permesso else { return }
        if let a = attivita {                      // una sola attività di JARVIS alla volta (della pioggia a parte): quella nuova prende il posto
            let vecchia = a
            Task { await vecchia.end(nil, dismissalPolicy: .immediate) }
            attivita = nil
        }
        attivita = try? Activity.request(attributes: AttivitaJarvis(meta: meta), content: ActivityContent(state: s, staleDate: fine), pushType: nil)
    }

    static func chiudi() {
        guard let a = attivita else { return }
        attivita = nil
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    /// I tasti dell'isola che aprono JARVIS (it.discosizer.jarvis://isola/…): «percorso», «guida», «radar», «apri».
    /// «basta» e «ferma» restano per le isole accese dalla build di prima (prima tutti i tasti aprivano l'app).
    static func comando(_ url: URL) -> String? {
        guard url.host == "isola" else { return nil }
        let c = url.lastPathComponent
        switch c {
        case "basta": AvvisoTravel.spegni()
        case "ferma": MotoreGuida.condiviso.ferma(); chiudi()
        default: break
        }
        return c
    }
}
#endif
