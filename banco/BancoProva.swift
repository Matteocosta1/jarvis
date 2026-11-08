#if os(iOS)
import Foundation
import SwiftUI
import Combine

// BANCO DI PROVA (solo sul ramo claude/banco-prova, mai nell'app del signore): l'app vera nel simulatore, con una radice che apre
// le sezioni nel contenitore della MARK XI come fa ContentView, e un copione a tempo. Il video lo registra il simulatore.

enum BancoProva {
    static let scena: String? = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-banco"), i + 1 < a.count { return a[i + 1] }
        return nil
    }()
    static var attivo: Bool { scena != nil }

    /// Le risposte del cervello, finte (come le darebbe lui).
    static func risposta(_ corpo: [String: Any]) async -> [String: Any]? {
        guard attivo else { return nil }
        if corpo["posta_priorita"] != nil { return ["errore": "Banco di prova: niente priorità."] }
        if let chiave = corpo["posta_testo"] as? String {
            try? await Task.sleep(for: .milliseconds(700))           // il cervello ci mette un po': il caricamento si vede
            return lettera(chiave)
        }
        if corpo["posta"] != nil {
            try? await Task.sleep(for: .milliseconds(250))
            return ["email": elenco, "totale": elenco.count, "non_lette": 3]
        }
        return ["errore": "Banco di prova."]
    }

    static let elenco: [[String: Any]] = [
        ["id": "arrivo:1", "da": "Noleggio audio <noleggio@esempio.it>", "oggetto": "Preventivo impianto per sabato", "data": "gio 22 ott, 18:40", "letta": false],
        ["id": "arrivo:2", "da": "TestFlight <no_reply@email.apple.com>", "oggetto": "JARVIS Discosizer 11.0 (12) for iOS is now available to test.", "data": "dom 8 nov, 06:11", "letta": false],
        ["id": "arrivo:3", "da": "Studio Rossi <studio@esempio.it>", "oggetto": "Fattura di ottobre", "data": "dom 8 nov, 05:20", "letta": true],
        ["id": "arrivo:4", "da": "Locale Sirio <eventi@esempio.it>", "oggetto": "Conferma della serata di sabato e orari di montaggio", "data": "sab 7 nov, 22:27", "letta": false],
        ["id": "arrivo:5", "da": "Banca <avvisi@esempio.it>", "oggetto": "Estratto conto disponibile", "data": "sab 7 nov, 18:31", "letta": true],
    ]

    static func lettera(_ chiave: String) -> [String: Any] {
        switch chiave {
        case "arrivo:2":
            return ["da": "TestFlight <no_reply@email.apple.com>", "a": "alessandro@esempio.it", "cc": "", "oggetto": "JARVIS Discosizer 11.0 (12) for iOS is now available to test.",
                    "data": "dom 8 nov, 06:11", "messaggio": "banco-2@esempio.it",
                    "testo": "JARVIS Discosizer 11.0 (12) is ready to test on iOS and watchOS.\n\nTo test this app, open TestFlight on your iOS device using iOS 17.6 or later and install the update.\n\nYou can stop testing and manage notifications in the TestFlight app.\n\nTo be removed from this developer's list of potential testers, contact the developer.\n\nTo learn more about installation, testing, submitting feedback, supported OS versions, and the handling of your data, visit testflight.apple.com.\n\nBy using JARVIS Discosizer, you agree that crash data as well as statistics about how you use JARVIS Discosizer will be provided to the developer and linked to your email address.\n\nRiga in fondo per vedere lo scorrimento."]
        default:
            return ["da": "Noleggio audio <noleggio@esempio.it>", "a": "alessandro@esempio.it", "cc": "", "oggetto": "Preventivo impianto per sabato",
                    "data": "gio 22 ott, 18:40", "messaggio": "banco-1@esempio.it",
                    "testo": "Ciao Alessandro,\n\nti giro il preventivo per sabato:\n· impianto 2 kW con due sub\n· mixer e microfono\n· trasporto, montaggio e smontaggio\n\nTotale 480 € + IVA. Consegna alle 18, ritiro a fine serata.\n\nMi dai conferma entro giovedì?\n\nGrazie,\nNoleggio audio"]
        }
    }
}

extension Notification.Name {
    static let bancoApriMail = Notification.Name("bancoApriMail")
    static let bancoChiudiMail = Notification.Name("bancoChiudiMail")
}

/// La radice del banco: lo stesso contenitore di ContentView (StratoSezioniVista dentro la GeometryReader della schermata),
/// con sotto un finto JARVIS (per vedere cosa c'è dietro mentre le sezioni salgono e scendono).
struct RadiceBanco: View {
    @StateObject private var pila = PilaSezioni()
    @StateObject private var naviga = NavigaSezioni()
    @State private var inizio = Date()

    var body: some View {
        GeometryReader { g in
            ZStack {
                FintoJarvis()
                StratoSezioniVista(pila: pila, naviga: naviga, reattore: CGPoint(x: g.size.width / 2, y: 260), diametroReattore: 220,
                                   vista: { v in vista(v) }, portaDavanti: { _ in }, chiudiDietro: { id in chiudi(id) })
                    .zIndex(25)
                // l'orologio del copione, in basso a sinistra (nella fascia della barretta di iOS)
                TimelineView(.animation) { t in
                    Text(String(format: "%.2f", t.date.timeIntervalSince(inizio)))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.yellow.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 6)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(1000)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .jarvisChiudiSezione)) { n in
            if let id = n.userInfo?["id"] as? UUID { chiudi(id) }
        }
        .task { await copione() }
    }

    // COPIA dei rami di ContentView.vistaSezione (da tenere uguali)
    @ViewBuilder private func vista(_ v: PilaSezioni.Voce) -> some View {
        switch v.sezione {
        case .scheda(.email):
            VistaPosta(chiedi: { _ in }) { _, _ in }.paginaPiena()
        case .pagina:
            if let a = v.pagina {
                VistaStudio(apertura: a, parla: { _ in }, chiudi: { chiudi(v.id) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fondo)
                    .ignoresSafeArea()
                    .paginaPiena()
            }
        default:
            EmptyView()
        }
    }

    private func apri(_ s: Sezione, pagina: AperturaPagina? = nil) {
        withAnimation(StratoPagina.salita) { _ = pila.accesa(s, pagina: pagina) }
    }

    private func chiudi(_ id: UUID) {
        guard let v = pila.voci.first(where: { $0.id == id }) else { return }
        withAnimation(StratoPagina.discesa()) { _ = pila.spenta(v.sezione) }
    }

    private func chiudiDavanti() {
        if let d = pila.davanti { chiudi(d) }
    }

    private func aspetta(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    private func copione() async {
        inizio = Date()
        await aspetta(1.5)
        switch BancoProva.scena ?? "" {
        case "mail":
            apri(.scheda(.email))
            await aspetta(3.0)                                                  // 4,5
            NotificationCenter.default.post(name: .bancoApriMail, object: 1)    // la mail lunga (due righe di titolo)
            await aspetta(3.0)                                                  // 7,5
            NotificationCenter.default.post(name: .bancoChiudiMail, object: nil)
            await aspetta(1.5)                                                  // 9,0
            NotificationCenter.default.post(name: .bancoApriMail, object: 0)    // il preventivo (come il mockup)
            await aspetta(3.0)                                                  // 12,0
            NotificationCenter.default.post(name: .bancoChiudiMail, object: nil)
            await aspetta(1.5)                                                  // 13,5
            chiudiDavanti()
        case "studio":
            apri(.pagina("Studio"), pagina: AperturaPagina(sezione: "Studio"))
            await aspetta(7.0)                                                  // 8,5
            chiudiDavanti()
            await aspetta(1.5)                                                  // 10,0
            apri(.pagina("Social"), pagina: AperturaPagina(sezione: "Social"))
            await aspetta(7.0)                                                  // 17,0
            chiudiDavanti()
        default:
            break
        }
    }
}

/// Il finto JARVIS sotto: fondo scuro, una scritta in alto e un anello ciano (per vedere la fascia dell'ora e cosa c'è dietro).
private struct FintoJarvis: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.03, green: 0.10, blue: 0.12), Color.black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 30) {
                Text("J.A.R.V.I.S.  (dietro)").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4).foregroundStyle(Color.ciano)
                Circle().stroke(Color.ciano.opacity(0.6), lineWidth: 6).frame(width: 220, height: 220)
            }
            .padding(.top, 70)
        }
        .ignoresSafeArea()
    }
}
#endif
