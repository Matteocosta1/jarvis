import Foundation
import SwiftUI
import Combine

// MARK: - MARK XI · le sezioni restano aperte (mockup approvato dal signore il 3 nov)
// Prima ogni sezione era una schermata di iOS (fullScreenCover): chiusa, spariva del tutto. Ora stanno tutte in un contenitore
// sopra JARVIS (`StratoSezioni` in ContentView): fino a 10 vive, in ordine d'apertura; all'undicesima si chiude la più vecchia.
// Una sola è davanti; le altre restano dietro, vive (con i loro dati, dove le aveva lasciate), come nel mockup. Le sezioni con
// la fotocamera (o col microfono) dietro vanno in PAUSA (l'ultima immagine resta ferma) e davanti riprendono da dove erano, la
// fotocamera col suo suono (scelta B del signore, 3 nov; «deve funzionare tutto come il mockup»). L'Interprete dietro si ferma e
// davanti riprende.
//
// La regola che tiene tutto in ordine: lo «stato» di sempre di ogni sezione (mostraVitals, scheda, jarvis.occhi…) acceso vuol
// dire «davanti». Mandata dietro, il suo stato si spegne ma la sezione resta nell'elenco (`dietro`); chiusa davvero, esce.

extension Notification.Name {
    /// MARK XI: un comando a voce delle sezioni aperte («sezioni aperte», «quella di prima», «chiudi il meteo»…).
    static let jarvisComandoSezioni = Notification.Name("jarvisComandoSezioni")
    /// 4 nov (il signore, strada B): una richiesta nuova a voce per una sezione già aperta, davanti o dietro («portami al luogo»,
    /// «come arrivo da Bea?», «metro laser», «video di…»): la sezione torna davanti e la fa sul posto, senza riaprirsi.
    /// userInfo: "reparto" (il `rawValue` del Reparto) e, per Ricordi, "guida" e "salva".
    static let jarvisRichiestaSezione = Notification.Name("jarvisRichiestaSezione")
}

/// MARK XI (4 nov, approvati dal signore): i comandi a voce delle sezioni aperte arrivano da JARVIS o dal microfono di una
/// sezione (Interprete, Trainer, Scanner); li esegue la schermata principale, che ha l'elenco.
enum ComandiSezioni {
    static func invia(_ c: ComandoVocale) {
        NotificationCenter.default.post(name: .jarvisComandoSezioni, object: nil, userInfo: ["comando": c])
    }
}

/// Una sezione del contenitore.
enum Sezione: Hashable {
    // 9 nov notte (il signore: «si apre due volte ed è orribile così»): niente più la sezione a parte per scegliere la lingua
    // dell'Interprete: la lingua si sceglie dentro l'Interprete, come nel mockup
    case occhi, interprete, allenatore, vitals, ricordi, confidente
    case scheda(SchedaApp)

    /// Il nome, come sulla corona (le pagine olografiche, la scritta APERTA dell'ologramma).
    var nome: String {
        switch self {
        case .occhi: return "Occhi"
        case .interprete: return "Interprete"
        case .allenatore: return "Trainer"
        case .vitals: return "Vitals"
        case .ricordi: return "Ricordi"
        case .confidente: return "Confidente"
        case .scheda(let s):
            switch s {
            case .edith: return "EDITH"
            case .email: return "Email"
            default: return s.rawValue.prefix(1).uppercased() + s.rawValue.dropFirst()
            }
        }
    }

    /// Fotocamera o microfono: dietro va in pausa (e riprende quando torna davanti).
    var inPausaDietro: Bool {
        switch self {
        case .occhi, .allenatore, .interprete: return true
        case .scheda(let s): return s == .scanner
        default: return false
        }
    }

    /// Le pagine web (WKWebView), che nelle pagine olografiche il ciano se lo mettono dentro (OloWeb): in FRIDAY nessuna sezione
    /// lo è (Studio, Social e Browser erano di JARVIS).
    var paginaWeb: Bool { false }

    /// Le sezioni con la fotocamera: scelte dalle pagine olografiche hanno già il loro suono d'apertura (niente «scelta»).
    var conFotocamera: Bool {
        switch self {
        case .occhi, .allenatore: return true
        case .scheda(let s): return s == .scanner
        default: return false
        }
    }
}

/// L'elenco delle sezioni aperte.
final class PilaSezioni: ObservableObject {
    struct Voce: Identifiable, Equatable {
        let id = UUID()
        let sezione: Sezione
        /// Ricordi: la scheda con cui si erano aperti.
        var ricordi: VistaRicordi.Scheda?
        /// Occhi e Interprete: con cosa si erano aperti (servono per disegnarli anche dietro, a stato spento).
        var occhiata: Occhiata?
        var lingua: Lingua?
        static func == (a: Voce, b: Voce) -> Bool { a.id == b.id && a.ricordi == b.ricordi }
    }

    @Published private(set) var voci: [Voce] = []
    /// La sezione davanti (nil: JARVIS).
    @Published private(set) var davanti: UUID?
    /// Le sezioni che stanno andando dietro: il loro stato si spegne, ma non sono chiuse.
    private(set) var vannoDietro: Set<Sezione> = []

    static let massimo = 10

    var voceDavanti: Voce? { voci.first { $0.id == davanti } }
    func voce(_ s: Sezione) -> Voce? { voci.first { $0.sezione == s } }
    var nomiAperti: Set<String> { Set(voci.map(\.sezione.nome)) }

    /// La sezione si accende (davanti): nuova in fondo all'elenco, o una che c'era già (torna davanti, sveglia se era spenta).
    /// Restituisce la sezione da chiudere perché sono più di 10 (la più vecchia, mai quella davanti).
    @discardableResult func accesa(_ s: Sezione, ricordi: VistaRicordi.Scheda? = nil, occhiata: Occhiata? = nil,
                                   lingua: Lingua? = nil) -> Sezione? {
        vannoDietro.remove(s)
        if let i = voci.firstIndex(where: { $0.sezione == s }) {
            if let ricordi { voci[i].ricordi = ricordi }
            if let occhiata { voci[i].occhiata = occhiata }
            if let lingua { voci[i].lingua = lingua }
            davanti = voci[i].id
            return nil
        }
        var v = Voce(sezione: s)
        v.ricordi = ricordi
        v.occhiata = occhiata
        v.lingua = lingua
        voci.append(v)
        davanti = v.id
        // la più vecchia, mai quella davanti
        if voci.count > PilaSezioni.massimo, let vecchia = voci.first(where: { $0.id != davanti }) {
            return vecchia.sezione
        }
        return nil
    }

    /// 9 nov: la lingua dell'Interprete scelta o cambiata dentro la sezione (tornando davanti da dietro riparte con questa).
    func linguaInterprete(_ l: Lingua) {
        guard let i = voci.firstIndex(where: { $0.sezione == .interprete }) else { return }
        voci[i].lingua = l
    }

    /// Lo stato della sezione si è spento: se stava andando dietro resta (spenta se ha la fotocamera), altrimenti è chiusa ed esce.
    /// Vero: è chiusa davvero.
    @discardableResult func spenta(_ s: Sezione) -> Bool {
        guard let i = voci.firstIndex(where: { $0.sezione == s }) else { vannoDietro.remove(s); return false }
        if vannoDietro.contains(s) {
            vannoDietro.remove(s)
            if davanti == voci[i].id { davanti = nil }
            return false
        }
        if davanti == voci[i].id { davanti = nil }
        voci.remove(at: i)
        return true
    }

    /// La sezione sta per andare dietro (subito dopo il suo stato si spegne).
    func vaDietro(_ s: Sezione) {
        guard voce(s) != nil else { return }
        vannoDietro.insert(s)
    }

    /// Toglie dall'elenco una sezione già dietro (chiusa dalle pagine olografiche, o la più vecchia oltre le 10).
    func togli(_ s: Sezione) {
        vannoDietro.remove(s)
        voci.removeAll { $0.sezione == s }
    }

    /// La sezione vicina nel cerchio delle aperte (per lo swipe dai bordi): `passo` +1 la prossima, −1 la precedente.
    /// Il cerchio comprende JARVIS (nil) fra l'ultima e la prima.
    func vicina(di id: UUID?, passo: Int) -> UUID?? {
        guard !voci.isEmpty else { return nil }
        let giro: [UUID?] = voci.map { Optional($0.id) } + [nil]
        guard let i = giro.firstIndex(where: { $0 == id }) else { return nil }
        let n = giro.count
        return .some(giro[((i + passo) % n + n) % n])
    }
}
