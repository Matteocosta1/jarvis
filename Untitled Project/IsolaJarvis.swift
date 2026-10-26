#if os(iOS)
import Foundation
import ActivityKit
import Combine

// MARK: - MARK X · DYNAMIC ISLAND: l'app accende, aggiorna e spegne l'attività di JARVIS (la disegna l'estensione JarvisIsola).
// TRAVEL: dopo «Avvisami» fino all'ora di uscire (+10 min). GUIDA: finché la guida di SATELLITE è accesa, aggiornata alla svolta.
// Dentro JARVIS iOS non mostra la sua stessa attività: si vede quando lei esce dall'app o blocca il telefono.

@MainActor
enum IsolaJarvis {
    private static var attivita: Activity<AttivitaJarvis>?
    private static var guardiaGuida: AnyCancellable?

    private static var permesso: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

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

    // MARK: Accendere e spegnere

    private static func avvia(_ s: AttivitaJarvis.ContentState, meta: String, fine: Date?) {
        guard permesso else { return }
        if let a = attivita {                      // una sola attività di JARVIS alla volta: quella nuova prende il posto
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

    /// I tasti dell'isola aprono JARVIS con il comando (it.discosizer.jarvis://isola/…): «basta» e «ferma» spengono subito.
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
