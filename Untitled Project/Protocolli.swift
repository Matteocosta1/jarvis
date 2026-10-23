#if os(iOS)
import SwiftUI
import Combine
import UIKit

/// PROTOCOLLI (build 22), nella tendina che scende dall'alto. «Avvia» lancia il Comando rapido del protocollo («JARVIS Party», «JARVIS Notte»,
/// «JARVIS Rientro») con il ritorno automatico in JARVIS (x-callback-url). Tornato qui i passi si spuntano nella tendina
/// e JARVIS fa le sue parti: NOTTE la domanda del diario, RIENTRO messaggi da leggere e meteo di domani (chiesti al cervello).
@MainActor
final class Protocolli: ObservableObject {
    static let condiviso = Protocolli()
    /// Lo schema dell'app per il ritorno da Comandi rapidi (registrato in Untitled-Project-Info.plist).
    nonisolated static let schema = "it.discosizer.jarvis"

    enum Fase: Equatable { case fermo, inCorso, attivo }
    @Published private(set) var attivo: Protocollo?         // la scheda accesa
    @Published private(set) var fase: Fase = .fermo
    @Published private(set) var spuntati = 0                 // i passi già spuntati del protocollo attivo
    @Published private(set) var nota: String?                // Comando rapido mancante, annullato, non riuscito
    /// Cresce a ogni richiesta a voce: la schermata principale apre la tendina e lo avvia.
    @Published private(set) var richiesta = 0
    private var lanciato: Date?                               // aspetta il ritorno da Comandi rapidi
    private var richiesto: (Protocollo, Date)?                // detto a voce: parte appena si apre la scheda Telefono
    private var giro = 0                                      // ogni avvio ha il suo numero: le spunte di un avvio vecchio si fermano

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
        spuntati = 0
        nota = nil
        guard let url = indirizzo(p) else { fallito("Non riesco a preparare il Comando rapido, Sir."); return }
        lanciato = Date()
        let mio = giro
        Task {
            let ok = await UIApplication.shared.open(url)
            if !ok, self.giro == mio { self.fallito("Non riesco ad aprire l'app Comandi, Sir.") }
        }
    }

    /// shortcuts://x-callback-url/run-shortcut con il ritorno it.discosizer.jarvis://protocollo?nome=…&esito=ok|annullato|errore
    private func indirizzo(_ p: Protocollo) -> URL? {
        func indietro(_ esito: String) -> String { Strumenti.codifica("\(Protocolli.schema)://protocollo?nome=\(p.rawValue)&esito=\(esito)") }
        return URL(string: "shortcuts://x-callback-url/run-shortcut?name=\(Strumenti.codifica(p.comandoRapido))"
                   + "&x-success=\(indietro("ok"))&x-cancel=\(indietro("annullato"))&x-error=\(indietro("errore"))")
    }

    /// Il ritorno da Comandi rapidi. Vale anche se arriva tardi (il signore era già tornato a mano).
    func ritorno(_ url: URL, jarvis: Jarvis) {
        guard url.scheme == Protocolli.schema, url.host == "protocollo" else { return }
        let voci = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func valore(_ k: String) -> String? { voci.first { $0.name == k }?.value }
        // anche se iOS ha chiuso JARVIS mentre andava il Comando rapido (attivo vuoto): il protocollo si completa lo stesso
        guard let p = Protocollo(rawValue: valore("nome") ?? ""), attivo == nil || attivo == p else { return }
        lanciato = nil
        switch valore("esito") ?? "" {
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
            self.fallito("Il Comando rapido «\(p.comandoRapido)» non ha risposto, Sir: controlli che esista in Comandi, con questo nome.")
        }
    }

    /// Comandi rapidi ha finito: i passi si spuntano uno alla volta (come nel mockup), poi JARVIS fa la sua parte
    /// (dopo i suoni, così non si sovrappongono alla sua voce).
    private func completa(_ p: Protocollo, jarvis: Jarvis) {
        giro += 1
        let mio = giro
        attivo = p
        fase = .inCorso
        spuntati = 0
        nota = nil
        Task {
            for k in p.passi.indices {
                try? await Task.sleep(for: .milliseconds(320))
                guard self.giro == mio else { return }
                self.spuntati = k + 1
                Suoni.clickTesta()                                  // lo stesso click delle icone in alto (SISTEMI, cestino)
            }
            Suoni.fatto()
            self.fase = .attivo
            guard p.passi.contains(where: { $0.jarvis }) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard self.giro == mio else { return }
            self.parteDiJarvis(p, jarvis: jarvis)
        }
    }

    private func parteDiJarvis(_ p: Protocollo, jarvis: Jarvis) {
        switch p {
        case .notte: jarvis.chiediDiario("Diario, Sir. Mi racconti com'è andata oggi: la ascolto.")   // come «A voce» nel Diario
        case .rientro: Task { await jarvis.invia(Protocollo.fraseRientro) }
        case .party: break
        }
    }

    private func fallito(_ testo: String) {
        lanciato = nil
        fase = .fermo
        spuntati = 0
        nota = testo
    }
}

/// La tendina PROTOCOLLI (build 22), come il Centro di Controllo di iOS e come nel mockup: scende dall'alto tirandola giù
/// dalla parte alta di JARVIS e risale con uno swipe in su (o toccando la maniglia o il velo). Dentro: le tre schede
/// PARTY · NOTTE · RIENTRO con «Avvia» e i passi che si spuntano, le frasi A VOCE e la nota sui Comandi rapidi.
struct TendinaProtocolli: View {
    /// Lo spazio in alto da lasciare libero (la Dynamic Island e l'ora).
    let margineAlto: CGFloat
    let chiudi: () -> Void
    @ObservedObject private var protocolli = Protocolli.condiviso
    private let tinta = Color.ciano
    private let fondo = Color(red: 7 / 255, green: 13 / 255, blue: 15 / 255)

    var body: some View {
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
                ForEach(["«Jarvis, protocollo party»", "«Jarvis, protocollo notte»", "«Jarvis, protocollo rientro»"], id: \.self) {
                    Text($0).font(.system(size: 13)).foregroundStyle(ColoriHUD.testo)
                }
            }
            .padding(.horizontal, 6)
            Text("Ogni protocollo è un Comando rapido dell'app Comandi («JARVIS Party», «JARVIS Notte», «JARVIS Rientro»): i passi si cambiano lì.")
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

    private func scheda(_ p: Protocollo) -> some View {
        let acceso = protocolli.attivo == p && protocolli.fase != .fermo
        let fatti = acceso ? protocolli.spuntati : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(p.titolo)
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                TastoComando(testo: etichetta(p), corto: true) { protocolli.avvia(p) }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(p.passi.enumerated()), id: \.offset) { k, passo in
                    let ok = k < fatti
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ok ? ColoriHUD.verde : Color.clear)
                            .overlay(Circle().stroke(ok ? ColoriHUD.verde : tinta.opacity(0.5), lineWidth: 1))
                            .frame(width: 7, height: 7)
                            .shadow(color: ok ? ColoriHUD.verde : .clear, radius: 3)
                        Text(passo.testo)
                            .font(.system(size: 13))
                            .foregroundStyle(ok ? ColoriHUD.chiaro : ColoriHUD.spento)
                    }
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
