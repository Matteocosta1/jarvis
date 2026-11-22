#if os(iOS)
import SwiftUI
import Combine
import UIKit

/// PROTOCOLLI (build 22), nella tendina che scende dall'alto: LAVORO · RIENTRO · NOTTE. Deciso dal signore il 24 ott:
/// solo le luci. «Avvia» le accende verdi una alla volta (320 ms, il click delle icone in alto), poi «Attivo»; un tocco su una luce
/// la spegne (grigia: quel passo è disattivato, la voce resta), un altro la riaccende. Niente app Comandi, niente mail, JARVIS non parla.
@MainActor
final class Protocolli: ObservableObject {
    static let condiviso = Protocolli()

    @Published private(set) var accesi: [Protocollo: Set<String>] = [:]   // le luci verdi, per protocollo
    @Published private(set) var attivi: Set<Protocollo> = []               // «Attivo» sul tasto (dopo l'Avvia)
    @Published private(set) var inCorso: Protocollo?                       // le luci si stanno accendendo: tocchi fermi
    /// Cresce a ogni richiesta a voce: la schermata principale apre la tendina e lo avvia.
    @Published private(set) var richiesta = 0
    private var richiesto: (Protocollo, Date)?                             // detto a voce: parte appena scende la tendina
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
        inCorso = p
        // come nel mockup: le luci già verdi restano accese, le altre si accendono una alla volta (prima tornavano tutte grigie)
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

    /// Il tocco su una luce: verde → grigia (quel passo è disattivato), grigia → verde. Sempre, tranne mentre parte.
    func cambia(_ p: Protocollo, _ passo: Protocollo.Passo) {
        guard inCorso == nil else { return }
        let ora = !acceso(p, passo.chiave)
        imposta(p, passo.chiave, ora)                                     // deciso dal signore: la luce si spegne e quel passo è disattivato,
        Suoni.clickTesta()                                                 // nient'altro (nessuna mail, nessun Comando rapido)
    }

    private func imposta(_ p: Protocollo, _ chiave: String, _ on: Bool) {
        if on { accesi[p, default: []].insert(chiave) } else { accesi[p]?.remove(chiave) }
        if (accesi[p] ?? []).isEmpty { attivi.remove(p) }                  // tutte spente: il tasto torna «Avvia»
    }
}

/// La tendina PROTOCOLLI (build 22), come il Centro di Controllo di iOS e come nel mockup: scende dall'alto tirandola giù
/// dalla parte alta di JARVIS e risale con uno swipe in su (o toccando la maniglia o il velo). Dentro: le tre schede
/// LAVORO · RIENTRO · NOTTE con «Avvia» e le luci dei passi, le frasi A VOCE e la nota, come nel mockup.
/// 13.7 · OLOGRAFICA (il signore, 22 nov 00:30: «la tendina PROTOCOLLI olografica come le tab, che funzioni come adesso, che giochi
/// sulle trasparenze»; 00:49 approvata): lo stesso vetro delle tab (60 %, sfocato), tutto ciano, il bordo di luce in basso che
/// sfuma ai lati, i due angoli chiari delle tab sulle schede, una riga di scansione che scende quando si apre, le schede quasi
/// trasparenti (si vede la schermata sfocata dietro); «Avvia» e «Attivo» più piccoli (00:31). Il gesto e i tempi sono quelli di prima.
struct TendinaProtocolli: View {
    /// Lo spazio in alto da lasciare libero (la Dynamic Island e l'ora).
    let margineAlto: CGFloat
    /// Quanto è giù (0 chiusa, 1 tutta aperta): passata la metà, la riga di scansione scende una volta.
    var visibile: Double = 1
    let chiudi: () -> Void
    @ObservedObject private var protocolli = Protocolli.condiviso
    @State private var scansioneDa: Date?
    private static let azzurro = Color(red: 79 / 255, green: 227 / 255, blue: 1)      // #4fe3ff
    private static let ciano = Color(red: 143 / 255, green: 240 / 255, blue: 1)       // #8ff0ff
    private static let chiaro = Color(red: 191 / 255, green: 246 / 255, blue: 1)      // #bff6ff
    private static let luce = Color(red: 223 / 255, green: 250 / 255, blue: 1)        // #dffaff

    var body: some View {
        // iPhone piccolo o girato: se non ci sta tutta, la tendina scorre (maniglia e frasi restano raggiungibili)
        ViewThatFits(in: .vertical) {
            contenuto
            ScrollView(.vertical, showsIndicators: false) { contenuto }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            let forma = UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34)
            forma
                .fill(Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.6))
                .background { VetroTab().clipShape(forma) }         // 13.8 (4): solo sfocatura, come il mockup (senza la tinta di iOS)
                .environment(\.colorScheme, .dark)
                .overlay(alignment: .top) { scansione.clipShape(forma) }
                .overlay(alignment: .bottom) {
                    // il bordo di luce in basso, che sfuma ai lati
                    LinearGradient(stops: [.init(color: TendinaProtocolli.ciano.opacity(0), location: 0),
                                           .init(color: TendinaProtocolli.ciano.opacity(0.95), location: 0.22),
                                           .init(color: TendinaProtocolli.chiaro, location: 0.5),
                                           .init(color: TendinaProtocolli.ciano.opacity(0.95), location: 0.78),
                                           .init(color: TendinaProtocolli.ciano.opacity(0), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1.5)
                        .padding(.horizontal, 20)
                        .shadow(color: TendinaProtocolli.azzurro.opacity(0.9), radius: 5)
                        .shadow(color: TendinaProtocolli.azzurro.opacity(0.45), radius: 11)
                }
                .shadow(color: .black.opacity(0.45), radius: 25, y: 18)
                .ignoresSafeArea(edges: .top)
        }
        .onChange(of: visibile > 0.5) { _, su in
            guard su else { return }
            let da = Date()
            scansioneDa = da
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                if scansioneDa == da { scansioneDa = nil }                   // finita: niente più fotogrammi
            }
        }
    }

    /// La riga di scansione che scende quando la tendina si apre (0,75 s, una volta): alta il 40 % della tendina, parte da sopra
    /// e finisce sotto, sfumando nell'ultimo 15 %.
    @ViewBuilder private var scansione: some View {
        if let da = scansioneDa {
            TimelineView(.animation) { tl in
                GeometryReader { g in
                    let u = min(1, max(0, tl.date.timeIntervalSince(da) / 0.75))
                    let e = TendinaProtocolli.curva(u)                     // cubic-bezier(.3,.6,.4,1)
                    let h = g.size.height * 0.4
                    let op = u < 0.85 ? 1 : max(0, 1 - (u - 0.85) / 0.15)
                    LinearGradient(stops: [.init(color: TendinaProtocolli.azzurro.opacity(0), location: 0),
                                           .init(color: TendinaProtocolli.azzurro.opacity(0.10), location: 0.85),
                                           .init(color: TendinaProtocolli.chiaro.opacity(0.55), location: 0.99),
                                           .init(color: TendinaProtocolli.chiaro.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: h)
                        .offset(y: -h + (h + h * 1.6) * e)
                        .opacity(u >= 1 ? 0 : op)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// cubic-bezier(.3, .6, .4, 1) del mockup (y in funzione di x, con qualche passo di Newton).
    private static func curva(_ x: Double) -> Double {
        let (x1, y1, x2, y2) = (0.3, 0.6, 0.4, 1.0)
        func b(_ t: Double, _ a: Double, _ c: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * c + t * t * t }
        var t = x
        for _ in 0..<6 {
            let d = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2)
            guard abs(d) > 1e-6 else { break }
            t = min(1, max(0, t - (b(t, x1, x2) - x) / d))
        }
        return b(t, y1, y2)
    }

    private var contenuto: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROTOCOLLI")
                .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(3)
                .foregroundStyle(TendinaProtocolli.ciano).shadow(color: TendinaProtocolli.azzurro.opacity(0.95), radius: 4)
                .padding(.horizontal, 4)
            ForEach(Protocollo.allCases) { p in scheda(p) }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(["«Jarvis, protocollo lavoro»", "«Jarvis, protocollo rientro»", "«Jarvis, protocollo notte»"], id: \.self) {
                    Text($0).font(.system(size: 13)).foregroundStyle(TendinaProtocolli.ciano.opacity(0.85))
                }
            }
            .padding(.horizontal, 6)
            Text("Avvia accende tutte le luci. Poi tocchi una luce per spegnere quel passo; un altro tocco lo riaccende.")
                .font(.system(size: 11)).foregroundStyle(TendinaProtocolli.ciano.opacity(0.6)).padding(.horizontal, 6)
            Capsule().fill(TendinaProtocolli.ciano.opacity(0.75))
                .frame(width: 44, height: 5)
                .shadow(color: TendinaProtocolli.azzurro.opacity(0.8), radius: 4)
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
        let forma = RoundedRectangle(cornerRadius: 18)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(p.titolo)
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(TendinaProtocolli.chiaro)
                    .shadow(color: TendinaProtocolli.azzurro.opacity(0.7), radius: 3)
                Spacer(minLength: 0)
                tasto(etichetta(p)) { protocolli.avvia(p) }
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(p.passi.enumerated()), id: \.offset) { _, passo in
                    let ok = protocolli.acceso(p, passo.chiave)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ok ? ColoriHUD.verde : Color.clear)
                            .overlay(Circle().stroke(TendinaProtocolli.ciano.opacity(0.65), lineWidth: 1))
                            .frame(width: 7, height: 7)
                            .shadow(color: ok ? ColoriHUD.verde : .clear, radius: 3)
                        Text(passo.testo)
                            .font(.system(size: 13))
                            .foregroundStyle(ok ? TendinaProtocolli.luce : TendinaProtocolli.ciano.opacity(0.72))
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
        .background {
            // quasi trasparente (si vede la schermata sfocata dietro), con la luce dentro sul bordo
            forma.fill(TendinaProtocolli.azzurro.opacity(acceso ? 0.09 : 0.035))
                .overlay(forma.stroke(TendinaProtocolli.azzurro.opacity(acceso ? 0.14 : 0.05), lineWidth: 6).blur(radius: 7).clipShape(forma))
        }
        .overlay {
            forma.stroke(acceso ? TendinaProtocolli.ciano.opacity(0.7) : TendinaProtocolli.azzurro.opacity(0.2), lineWidth: 1)
                .shadow(color: acceso ? TendinaProtocolli.azzurro.opacity(0.3) : .clear, radius: 7)   // il bagliore solo sul bordo
        }
        .overlay { AngoliScheda().allowsHitTesting(false) }
        .animation(.easeOut(duration: 0.3), value: acceso)
    }

    /// «Avvia» / «Attivo», più piccoli (il signore, 22 nov 00:31: erano 12 punti): 9,5 punti, dentro il vetro ciano.
    private func tasto(_ testo: String, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(testo)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(1.2)
                .textCase(.uppercase)
                .lineLimit(1)
                .foregroundStyle(TendinaProtocolli.chiaro)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(TendinaProtocolli.azzurro.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TendinaProtocolli.ciano.opacity(0.55), lineWidth: 1))
                .shadow(color: TendinaProtocolli.azzurro.opacity(0.25), radius: 4)
                .padding(.vertical, 7)                                   // l'area del dito resta di 30 punti, come prima
                .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
    }

    private func etichetta(_ p: Protocollo) -> String {
        if protocolli.inCorso == p { return "…" }
        return protocolli.attivi.contains(p) ? "Attivo" : "Avvia"
    }
}

/// I due angoli chiari delle tab sulle schede dei protocolli (in alto a sinistra e in basso a destra), che seguono la curva
/// della scheda (raggio 18): 10 punti, 1,5 di spessore, con la luce ciano.
private struct AngoliScheda: View {
    var body: some View {
        Canvas { gc, size in
            let r = 18.0, w = Double(size.width), h = Double(size.height), k = 10.0
            var p = Path()
            // in alto a sinistra: dal lato sinistro, giro dell'angolo, fino al lato alto
            p.move(to: CGPoint(x: -0.25, y: k))
            p.addArc(tangent1End: CGPoint(x: -0.25, y: -0.25), tangent2End: CGPoint(x: k, y: -0.25), radius: min(r, k))
            p.addLine(to: CGPoint(x: k, y: -0.25))
            // in basso a destra
            p.move(to: CGPoint(x: w + 0.25, y: h - k))
            p.addArc(tangent1End: CGPoint(x: w + 0.25, y: h + 0.25), tangent2End: CGPoint(x: w - k, y: h + 0.25), radius: min(r, k))
            p.addLine(to: CGPoint(x: w - k, y: h + 0.25))
            var l = gc
            l.addFilter(.shadow(color: Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.9), radius: 3))
            l.stroke(p, with: .color(Color(red: 223 / 255, green: 250 / 255, blue: 1).opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}
#endif
