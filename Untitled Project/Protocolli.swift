#if os(iOS)
import SwiftUI
import Combine
import UIKit

/// PROTOCOLLI (build 22), nella tendina che scende dall'alto: LAVORO · RIENTRO · NOTTE. «Avvia» lancia il Comando rapido del protocollo
/// («JARVIS Lavoro», «JARVIS Rientro», «JARVIS Notte») con il testo «avvia» e il ritorno automatico in JARVIS (x-callback-url).
/// Tornato qui le luci dei passi si accendono verdi una alla volta e JARVIS fa le sue parti: LAVORO impegni e posta, RIENTRO messaggi
/// e meteo di domani (chiesti al cervello), NOTTE la domanda del diario. Dopo, un tocco su una luce verde spegne solo quel passo:
/// lo stesso Comando rapido riceve «annulla:<chiave>» (un altro tocco: «rifai:<chiave>»). I passi di JARVIS non hanno niente da spegnere.
@MainActor
final class Protocolli: ObservableObject {
    static let condiviso = Protocolli()
    /// Lo schema dell'app per il ritorno da Comandi rapidi (registrato in Untitled-Project-Info.plist).
    nonisolated static let schema = "it.discosizer.jarvis"

    enum Fase: Equatable { case fermo, inCorso, attivo }
    @Published private(set) var attivo: Protocollo?         // la scheda accesa
    @Published private(set) var fase: Fase = .fermo
    @Published private(set) var accesi: Set<String> = []     // le chiavi dei passi con la luce verde
    @Published private(set) var inCambio: String?            // il passo che il Comando rapido sta spegnendo o riaccendendo
    @Published private(set) var nota: String?                // Comando rapido mancante, annullato, non riuscito
    /// Cresce a ogni richiesta a voce: la schermata principale apre la tendina e lo avvia.
    @Published private(set) var richiesta = 0
    private var lanciato: Date?                               // aspetta il ritorno da Comandi rapidi
    private var richiesto: (Protocollo, Date)?                // detto a voce: parte appena scende la tendina
    private var giro = 0                                      // ogni avvio ha il suo numero: le luci di un avvio vecchio si fermano

    /// «Jarvis, protocollo notte»: la tendina scende e lo avvia.
    func richiedi(_ p: Protocollo) { richiesto = (p, Date()); richiesta += 1 }

    /// Il protocollo chiesto a voce pochi secondi fa (e lo consuma): se la tendina non è scesa, non parte più tardi a sorpresa.
    func prendiRichiesto() -> Protocollo? {
        defer { richiesto = nil }
        guard let r = richiesto, Date().timeIntervalSince(r.1) < 8 else { return nil }
        return r.0
    }

    func avvia(_ p: Protocollo) {
        giro += 1
        attivo = p
        fase = .inCorso
        accesi = []
        inCambio = nil
        nota = nil
        apri(p, testo: "avvia", passo: nil) { self.fallito($0) }
    }

    /// Dopo l'Avvia: il tocco su una luce. Verde → il Comando rapido annulla quel passo; grigia → lo rifà.
    func cambia(_ p: Protocollo, _ passo: Protocollo.Passo) {
        guard attivo == p, fase == .attivo, inCambio == nil else { return }
        nota = nil
        let acceso = accesi.contains(passo.chiave)
        if passo.jarvis {                                     // le parti di JARVIS sono già fatte: cambia solo la luce
            if acceso { accesi.remove(passo.chiave) } else { accesi.insert(passo.chiave) }
            Suoni.clickTesta()
            return
        }
        inCambio = passo.chiave
        apri(p, testo: "\(acceso ? "annulla" : "rifai"):\(passo.chiave)", passo: passo.chiave) { t in self.inCambio = nil; self.nota = t }
    }

    /// shortcuts://x-callback-url/run-shortcut con il testo per il Comando rapido e il ritorno
    /// it.discosizer.jarvis://protocollo?nome=…&esito=ok|annullato|errore(&passo=…)
    private func apri(_ p: Protocollo, testo: String, passo: String?, errore: @escaping @MainActor (String) -> Void) {
        func indietro(_ esito: String) -> String {
            Strumenti.codifica("\(Protocolli.schema)://protocollo?nome=\(p.rawValue)&esito=\(esito)" + (passo.map { "&passo=\($0)" } ?? ""))
        }
        guard let url = URL(string: "shortcuts://x-callback-url/run-shortcut?name=\(Strumenti.codifica(p.comandoRapido))&input=text&text=\(Strumenti.codifica(testo))"
                            + "&x-success=\(indietro("ok"))&x-cancel=\(indietro("annullato"))&x-error=\(indietro("errore"))") else {
            errore("Non riesco a preparare il Comando rapido, Sir."); return
        }
        lanciato = Date()
        let mio = giro
        Task {
            let ok = await UIApplication.shared.open(url)
            if !ok, self.giro == mio { self.lanciato = nil; errore("Non riesco ad aprire l'app Comandi, Sir.") }
        }
    }

    /// Il ritorno da Comandi rapidi. Vale anche se arriva tardi (il signore era già tornato a mano).
    func ritorno(_ url: URL, jarvis: Jarvis) {
        guard url.scheme == Protocolli.schema, url.host == "protocollo" else { return }
        let voci = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func valore(_ k: String) -> String? { voci.first { $0.name == k }?.value }
        // anche se iOS ha chiuso JARVIS mentre andava il Comando rapido (attivo vuoto): il protocollo si completa lo stesso
        guard let p = Protocollo(rawValue: valore("nome") ?? ""), attivo == nil || attivo == p else { return }
        lanciato = nil
        let esito = valore("esito") ?? ""
        if let chiave = valore("passo") {                     // un passo spento o riacceso dopo l'Avvia
            inCambio = nil
            guard attivo == p, fase == .attivo else { return }
            switch esito {
            case "ok":
                if accesi.contains(chiave) { accesi.remove(chiave) } else { accesi.insert(chiave) }
                Suoni.clickTesta()
            case "annullato": break
            default:
                let perche = valore("errorMessage").map { ": \($0)" } ?? "."
                nota = "Il Comando rapido «\(p.comandoRapido)» non ha cambiato il passo, Sir\(perche)"
            }
            return
        }
        switch esito {
        case "ok":
            completa(p, jarvis: jarvis)
        case "annullato":
            fallito("Protocollo \(p.rawValue) annullato, Sir.")
        default:
            let perche = valore("errorMessage").map { ": \($0)" } ?? "."
            fallito("Il Comando rapido «\(p.comandoRapido)» non è andato, Sir\(perche)")
        }
    }

    /// L'app è tornata in primo piano: se il Comando rapido non ha chiamato JARVIS (non esiste, o ci è tornato a mano), lo dice.
    func inPrimoPiano() {
        guard let quando = lanciato, Date().timeIntervalSince(quando) > 1 else { return }
        let mio = giro
        Task {
            try? await Task.sleep(for: .milliseconds(1500))          // il ritorno di Comandi rapidi arriva subito dopo l'apertura
            guard self.giro == mio, self.lanciato != nil, let p = self.attivo else { return }
            self.lanciato = nil
            let testo = "Il Comando rapido «\(p.comandoRapido)» non ha risposto, Sir: controlli che esista in Comandi, con questo nome."
            if self.inCambio != nil { self.inCambio = nil; self.nota = testo } else { self.fallito(testo) }
        }
    }

    /// Comandi rapidi ha finito: le luci si accendono verdi una alla volta (come nel mockup), poi JARVIS fa la sua parte
    /// (dopo i suoni, così non si sovrappongono alla sua voce).
    private func completa(_ p: Protocollo, jarvis: Jarvis) {
        giro += 1
        let mio = giro
        attivo = p
        fase = .inCorso
        accesi = []
        nota = nil
        Task {
            for passo in p.passi {
                try? await Task.sleep(for: .milliseconds(320))
                guard self.giro == mio else { return }
                self.accesi.insert(passo.chiave)
                Suoni.clickTesta()                                  // lo stesso click delle icone in alto (SISTEMI, cestino)
            }
            Suoni.fatto()
            self.fase = .attivo
            try? await Task.sleep(for: .milliseconds(500))
            guard self.giro == mio else { return }
            self.parteDiJarvis(p, jarvis: jarvis)
        }
    }

    private func parteDiJarvis(_ p: Protocollo, jarvis: Jarvis) {
        switch p {
        case .lavoro: Task { await jarvis.invia(Protocollo.fraseLavoro) }
        case .rientro: Task { await jarvis.invia(Protocollo.fraseRientro) }
        case .notte: jarvis.chiediDiario("Diario, Sir. Mi racconti com'è andata oggi: la ascolto.")   // come «A voce» nel Diario
        }
    }

    private func fallito(_ testo: String) {
        lanciato = nil
        fase = .fermo
        accesi = []
        inCambio = nil
        nota = testo
    }
}

/// La tendina PROTOCOLLI (build 22), come il Centro di Controllo di iOS e come nel mockup: scende dall'alto tirandola giù
/// dalla parte alta di JARVIS e risale con uno swipe in su (o toccando la maniglia o il velo). Dentro: le tre schede
/// LAVORO · RIENTRO · NOTTE con «Avvia» e le luci dei passi, le frasi A VOCE e la nota sui Comandi rapidi.
struct TendinaProtocolli: View {
    /// Lo spazio in alto da lasciare libero (la Dynamic Island e l'ora).
    let margineAlto: CGFloat
    let chiudi: () -> Void
    @ObservedObject private var protocolli = Protocolli.condiviso
    private let tinta = Color.ciano
    private let fondo = Color(red: 7 / 255, green: 13 / 255, blue: 15 / 255)

    var body: some View {
        // iPhone piccolo o girato: se non ci sta tutta, la tendina scorre (maniglia e frasi restano raggiungibili)
        ViewThatFits(in: .vertical) {
            contenuto
            ScrollView(.vertical, showsIndicators: false) { contenuto }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34)
                .fill(fondo.opacity(0.84))
                .background(.ultraThinMaterial, in: UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34))
                .overlay(alignment: .bottom) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34)
                        .stroke(tinta.opacity(0.25), lineWidth: 1).mask(alignment: .bottom) { Rectangle().frame(height: 40) }
                }
                .shadow(color: .black.opacity(0.6), radius: 25, y: 18)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var contenuto: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROTOCOLLI")
                .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(3)
                .foregroundStyle(tinta).shadow(color: tinta.opacity(0.5), radius: 5)
                .padding(.horizontal, 4)
            ForEach(Protocollo.allCases) { p in scheda(p) }
            if let n = protocolli.nota {
                Text(n).font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(["«Jarvis, protocollo lavoro»", "«Jarvis, protocollo rientro»", "«Jarvis, protocollo notte»"], id: \.self) {
                    Text($0).font(.system(size: 13)).foregroundStyle(ColoriHUD.testo)
                }
            }
            .padding(.horizontal, 6)
            Text("Dopo Avvia, tocchi una luce verde per spegnere solo quel passo; un altro tocco lo riaccende.")
                .font(.system(size: 11)).foregroundStyle(Color.tenue).padding(.horizontal, 6)
            Text("Ogni protocollo è un Comando rapido dell'app Comandi («JARVIS Lavoro», «JARVIS Rientro», «JARVIS Notte»): i passi si cambiano lì.")
                .font(.system(size: 11)).foregroundStyle(Color.tenue).padding(.horizontal, 6)
            Capsule().fill(ColoriHUD.chiaro.opacity(0.45))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity).padding(.top, 4).padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { chiudi() }
                .accessibilityLabel("Chiudi i protocolli").accessibilityAddTraits(.isButton)
        }
        .padding(.top, margineAlto + 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    private func scheda(_ p: Protocollo) -> some View {
        let acceso = protocolli.attivo == p && protocolli.fase != .fermo
        let toccabile = protocolli.attivo == p && protocolli.fase == .attivo
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(p.titolo)
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                TastoComando(testo: etichetta(p), corto: true) { protocolli.avvia(p) }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(p.passi.enumerated()), id: \.offset) { _, passo in
                    let ok = acceso && protocolli.accesi.contains(passo.chiave)
                    let cambia = protocolli.inCambio == passo.chiave
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ok ? ColoriHUD.verde : Color.clear)
                            .overlay(Circle().stroke(ok ? ColoriHUD.verde : tinta.opacity(0.5), lineWidth: 1))
                            .frame(width: 7, height: 7)
                            .shadow(color: ok ? ColoriHUD.verde : .clear, radius: 3)
                            .opacity(cambia ? 0.4 : 1)
                        Text(passo.testo)
                            .font(.system(size: 13))
                            .foregroundStyle(ok ? ColoriHUD.chiaro : ColoriHUD.spento)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if toccabile { protocolli.cambia(p, passo) } }   // dopo l'Avvia: spegne (o riaccende) solo questo passo
                    .accessibilityAddTraits(toccabile ? .isButton : [])
                    .accessibilityValue(ok ? "acceso" : "spento")
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(acceso ? tinta.opacity(0.1) : Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 22).stroke(acceso ? tinta : tinta.opacity(0.16), lineWidth: 1)
                .shadow(color: acceso ? tinta.opacity(0.25) : .clear, radius: 8)        // il bagliore solo sul bordo, come nel mockup
        )
        .animation(.easeOut(duration: 0.3), value: acceso)
    }

    private func etichetta(_ p: Protocollo) -> String {
        guard protocolli.attivo == p else { return "Avvia" }
        switch protocolli.fase {
        case .inCorso: return "…"
        case .attivo: return "Attivo"
        case .fermo: return "Avvia"
        }
    }
}
#endif
