#if os(iOS)
import SwiftUI
import Combine
import UIKit

/// PROTOCOLLI (build 22), nella tendina che scende dall'alto: LAVORO · RIENTRO · NOTTE. Deciso dal signore il 24 ott:
/// l'app Comandi non si vede mai, JARVIS nei protocolli non parla, ogni luce è un interruttore. «Avvia» accende tutte le luci verdi
/// una alla volta (320 ms, il click delle icone in alto), poi «Attivo». Un tocco su una luce la spegne (grigia, la voce resta),
/// un altro la riaccende, in qualsiasi momento. I passi del telefono partono in sottofondo: il cervello manda la mail che
/// l'automazione di Comandi esegue (vedi Protocollo); l'automazione conferma con «Conferma protocollo» (Comandi.swift).
/// Se in 30 s il telefono non conferma, la luce torna com'era, con l'avviso. Una conferma che arriva dopo, o un avvio
/// partito dal polso, accende comunque le luci giuste. I passi di JARVIS (impegni, posta, messaggi, meteo, diario) cambiano solo la luce.
@MainActor
final class Protocolli: ObservableObject {
    static let condiviso = Protocolli()
    /// Quanto aspettare la conferma dell'automazione dopo che il cervello ha mandato la mail.
    static let attesaConferma: Duration = .seconds(30)

    @Published private(set) var accesi: [Protocollo: Set<String>] = [:]   // le luci verdi, per protocollo
    @Published private(set) var attivi: Set<Protocollo> = []               // «Attivo» sul tasto (dopo l'Avvia)
    @Published private(set) var inCorso: Protocollo?                       // le luci si stanno accendendo: tocchi fermi
    @Published private(set) var nota: String?                              // il telefono non ha confermato, cervello irraggiungibile
    /// Cresce a ogni richiesta a voce: la schermata principale apre la tendina e lo avvia.
    @Published private(set) var richiesta = 0
    private var richiesto: (Protocollo, Date)?                             // detto a voce: parte appena scende la tendina
    private var inAttesa: [String: () -> Void] = [:]                       // id → come tornare indietro se il telefono non conferma
    private var giro = 0                                                   // ogni avvio ha il suo numero

    /// «Jarvis, protocollo notte»: la tendina scende e lo avvia.
    func richiedi(_ p: Protocollo) { richiesto = (p, Date()); richiesta += 1 }

    /// Il protocollo chiesto a voce pochi secondi fa (e lo consuma): se la tendina non è scesa, non parte più tardi a sorpresa.
    func prendiRichiesto() -> Protocollo? {
        defer { richiesto = nil }
        guard let r = richiesto, Date().timeIntervalSince(r.1) < 8 else { return nil }
        return r.0
    }

    func acceso(_ p: Protocollo, _ chiave: String) -> Bool { accesi[p]?.contains(chiave) ?? false }
    /// La scheda illuminata: sta partendo, è attiva o ha almeno una luce verde.
    func illuminato(_ p: Protocollo) -> Bool { inCorso == p || attivi.contains(p) || !(accesi[p] ?? []).isEmpty }

    func avvia(_ p: Protocollo) {
        guard inCorso == nil else { return }                               // un secondo tocco mentre parte non lo rilancia
        giro += 1
        let mio = giro
        nota = nil
        inCorso = p
        accesi[p] = []
        manda(p, testo: "avvia") { [weak self] in                         // il telefono non ha confermato: tutto spento, «Avvia»
            guard let self else { return }
            if self.inCorso == p { self.giro += 1; self.inCorso = nil }
            self.accesi[p] = []
            self.attivi.remove(p)
        }
        Task {
            for passo in p.passi {
                try? await Task.sleep(for: .milliseconds(320))
                guard self.giro == mio else { return }
                self.accesi[p, default: []].insert(passo.chiave)
                Suoni.clickTesta()
            }
            Suoni.fatto()
            self.attivi.insert(p)
            self.inCorso = nil
        }
    }

    /// Il tocco su una luce: spenta → grigia (quel passo si annulla), grigia → verde (si rifà). Sempre, tranne mentre parte.
    func cambia(_ p: Protocollo, _ passo: Protocollo.Passo) {
        guard inCorso == nil else { return }
        nota = nil
        let ora = !acceso(p, passo.chiave)
        imposta(p, passo.chiave, ora)
        Suoni.clickTesta()
        guard !passo.jarvis else { return }                               // i passi di JARVIS: solo la luce
        manda(p, testo: Protocollo.testoCambio(passo, acceso: ora)) { [weak self] in self?.imposta(p, passo.chiave, !ora) }
    }

    private func imposta(_ p: Protocollo, _ chiave: String, _ on: Bool) {
        if on { accesi[p, default: []].insert(chiave) } else { accesi[p]?.remove(chiave) }
        if (accesi[p] ?? []).isEmpty { attivi.remove(p) }                  // tutte spente: il tasto torna «Avvia»
    }

    /// Il cervello manda la mail per l'automazione; poi si aspetta la conferma del telefono.
    private func manda(_ p: Protocollo, testo: String, torna: @escaping () -> Void) {
        let id = Protocollo.nuovoId()
        inAttesa[id] = torna
        Task {
            let r = await VistaVitals.chiama(Protocollo.richiesta(p, testo: testo, id: id), attesa: 30)
            guard self.inAttesa[id] != nil else { return }                 // già confermato
            guard let r, r["ok"] as? Bool == true else {
                self.inAttesa[id] = nil
                torna()
                self.nota = (r?["errore"] as? String) ?? "Non raggiungo il cervello, Sir: il passo non è partito."
                return
            }
            try? await Task.sleep(for: Protocolli.attesaConferma)
            guard let t = self.inAttesa.removeValue(forKey: id) else { return }
            t()
            self.nota = "Il telefono non ha confermato, Sir: controlli l'automazione «JARVIS» in Comandi."
        }
    }

    /// L'automazione di Comandi ha eseguito il passo (azione «Conferma protocollo» con l'oggetto della mail).
    func conferma(_ oggetto: String) {
        guard let letto = Protocollo.leggi(oggetto) else { return }
        let id = letto.id
        // partito dal polso, o conferma arrivata dopo l'attesa: le luci si mettono come le ha lasciate il telefono
        if inAttesa.removeValue(forKey: id) == nil { applica(letto.protocollo, letto.testo) }
        Task { _ = await VistaVitals.chiama(["protocollo_pulisci": id], attesa: 30) }   // la mail del passo va nel Cestino
    }

    private func applica(_ p: Protocollo, _ testo: String) {
        guard inCorso == nil else { return }
        nota = nil
        if testo == "avvia" {
            accesi[p] = Set(p.passi.map(\.chiave))
            attivi.insert(p)
            Suoni.fatto()
            return
        }
        let pezzi = testo.split(separator: ":", maxSplits: 1).map(String.init)
        guard pezzi.count == 2 else { return }
        imposta(p, pezzi[1], pezzi[0] == "rifai")
        Suoni.clickTesta()
    }
}

/// La tendina PROTOCOLLI (build 22), come il Centro di Controllo di iOS e come nel mockup: scende dall'alto tirandola giù
/// dalla parte alta di JARVIS e risale con uno swipe in su (o toccando la maniglia o il velo). Dentro: le tre schede
/// LAVORO · RIENTRO · NOTTE con «Avvia» e le luci dei passi, le frasi A VOCE e le due note, come nel mockup.
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
            Text("Avvia accende tutte le luci. Poi tocchi una luce per spegnere quel passo; un altro tocco lo riaccende.")
                .font(.system(size: 11)).foregroundStyle(Color.tenue).padding(.horizontal, 6)
            Text("I passi li fa il telefono in silenzio, in sottofondo.")
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
        let acceso = protocolli.illuminato(p)
        let toccabile = protocolli.inCorso == nil
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
                    let ok = protocolli.acceso(p, passo.chiave)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ok ? ColoriHUD.verde : Color.clear)
                            .overlay(Circle().stroke(ok ? ColoriHUD.verde : tinta.opacity(0.5), lineWidth: 1))
                            .frame(width: 7, height: 7)
                            .shadow(color: ok ? ColoriHUD.verde : .clear, radius: 3)
                        Text(passo.testo)
                            .font(.system(size: 13))
                            .foregroundStyle(ok ? ColoriHUD.chiaro : ColoriHUD.spento)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if toccabile { protocolli.cambia(p, passo) } }   // spegne (o riaccende) solo questo passo, sempre
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
        if protocolli.inCorso == p { return "…" }
        return protocolli.attivi.contains(p) ? "Attivo" : "Avvia"
    }
}
#endif
