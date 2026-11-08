#if os(iOS)
import Foundation
import SwiftUI
import Combine
import UIKit
import QuartzCore

// BANCO DI PROVA (solo sul ramo claude/banco-prova, mai nell'app del signore): l'app vera nel simulatore, con una radice che apre
// le sezioni nel contenitore della MARK XI come fa ContentView, e un copione a tempo. Il video lo registra il simulatore.

enum BancoProva {
    static let scena: String? = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-banco"), i + 1 < a.count { return a[i + 1] }
        return nil
    }()
    static var attivo: Bool { scena != nil }
    /// Le sonde dei margini (scene «…sonde»).
    static var sonde: Bool { scena?.hasSuffix("sonde") ?? false }
    /// La PROIEZIONE senza luce e colore (scene «…B»).
    static var senzaColori: Bool { scena?.hasSuffix("B") ?? false }
    /// 8 nov notte (diagnosi): le aperture rallentate (scene con «_L»): salita, caricamento, stampa e dissolvenza × 6.
    static var lento: Double { (scena?.contains("_L") ?? false) ? 6 : 1 }
    /// 8 nov notte (diagnosi): gli sfondi colorati (scene con «_T»): il «cappello» in rosso, lo sfondo della sezione in verde.
    static var tinte: Bool { scena?.contains("_T") ?? false }

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
                .overlay { SondaSA(nome: "PAG", riga: 5) }
        case .scheda(.cuore):
            VistaCuoreTelefono(chiedi: { _ in }).paginaPiena()
        case .scheda(.musica):
            VistaMusica().paginaPiena()
        case .scheda(.edith):
            VistaEdith(chiedi: { _ in }).paginaPiena()
        case .scheda(.meteo):
            VistaMeteo(chiedi: { _ in }).paginaPiena()
        case .lingua:
            SceltaLingua { _ in }.paginaPiena()
        case .ricordi:
            VistaRicordi(iniziale: .ricordi, guida: false, salva: false) { _ in }.paginaPiena()
        case .scheda(.bea):
            VistaBea(chiedi: { _ in }).paginaPiena()
        case .pagina:
            if let a = v.pagina {
                VistaStudio(apertura: a, parla: { _ in }, chiudi: { chiudi(v.id) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .paginaPiena()
                    .overlay { SondaSA(nome: "PAG", riga: 5) }
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
        var nome = BancoProva.scena ?? ""
        if nome.hasSuffix("sonde") { nome.removeLast(5) }
        if nome.hasSuffix("B") { nome.removeLast() }
        switch nome {
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
            await aspetta(13.0)                                                 // 14,5 (nel simulatore la pagina web è lenta)
            chiudiDavanti()
            await aspetta(1.5)                                                  // 16,0
            apri(.pagina("Social"), pagina: AperturaPagina(sezione: "Social"))
            await aspetta(13.0)                                                 // 29,0
            chiudiDavanti()
        case "tutte":                                                           // 8 nov: le aperture a confronto (Posta e Cuore come riferimento)
            apri(.scheda(.email)); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.cuore)); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.pagina("Studio"), pagina: AperturaPagina(sezione: "Studio")); await aspetta(13.0); chiudiDavanti(); await aspetta(1.5)
            apri(.pagina("Social"), pagina: AperturaPagina(sezione: "Social")); await aspetta(10.0); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.musica)); await aspetta(5.0); chiudiDavanti()
        case "diag", "diag_L_T":                                                // 8 nov notte: la diagnosi del foglio (strati per fotogramma)
            let lento = BancoProva.lento
            let resta = lento > 1 ? 7.0 : 4.0
            SondaStrati.condivisa.avvia("CUORE", durata: lento > 1 ? 4.5 : 1.6)
            apri(.scheda(.cuore)); await aspetta(resta); chiudiDavanti(); await aspetta(1.5)
            SondaStrati.condivisa.avvia("STUDIO", durata: lento > 1 ? 4.5 : 1.6)
            apri(.pagina("Studio"), pagina: AperturaPagina(sezione: "Studio")); await aspetta(lento > 1 ? 12.0 : 9.0); chiudiDavanti(); await aspetta(1.5)
            SondaStrati.condivisa.avvia("RICORDI", durata: lento > 1 ? 4.5 : 1.6)
            apri(.ricordi); await aspetta(resta); chiudiDavanti()
        case "pagine":                                                          // 8 nov pomeriggio: ogni sezione come una pagina sola
            apri(.scheda(.edith)); await aspetta(3.5); chiudiDavanti(); await aspetta(1.5)
            apri(.lingua); await aspetta(3.5); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.meteo)); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.email)); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.cuore)); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.ricordi); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.bea)); await aspetta(4.0); chiudiDavanti(); await aspetta(1.5)
            apri(.pagina("Studio"), pagina: AperturaPagina(sezione: "Studio")); await aspetta(11.0); chiudiDavanti(); await aspetta(1.5)
            apri(.scheda(.musica)); await aspetta(5.0); chiudiDavanti()
        default:
            break
        }
    }
}

/// Una sonda: dove sta la vista (y globale, altezza) e quali margini di iOS riceve (alto/basso), scritta in giallo a 300 + 26·riga
/// punti dal suo bordo alto. Si aggiorna a ogni impaginazione (non a ogni fotogramma di un'animazione).
struct SondaSA: View {
    let nome: String
    let riga: Int
    var body: some View {
        if BancoProva.sonde { GeometryReader { g in
            let f = g.frame(in: .global)
            Text("\(nome) y\(Int(f.minY.rounded())) h\(Int(f.height.rounded())) sa\(Int(g.safeAreaInsets.top.rounded()))/\(Int(g.safeAreaInsets.bottom.rounded()))")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.yellow)
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.75))
                .offset(x: 4 + CGFloat(riga % 2) * 150, y: 300 + CGFloat(riga) * 26)
        }
        .allowsHitTesting(false) }
    }
}

/// 8 nov notte (diagnosi del «foglio unico»): a ogni fotogramma, per `durata` secondi, ogni strato largo quanto lo schermo
/// (CALayer della finestra, anche quelli disegnati da SwiftUI): dove sta (y e altezza in punti della finestra, dal layer di
/// presentazione), opacità, se è nascosto, la classe e (se è di una UIView) i margini sicuri. Scritto nel registro («STRATI»).
@MainActor
final class SondaStrati: NSObject {
    static let condivisa = SondaStrati()
    private var link: CADisplayLink?
    private var inizio: CFTimeInterval = 0
    private var durata: CFTimeInterval = 1.6
    private var nome = ""
    private var ultimo: [ObjectIdentifier: String] = [:]
    private var giro = 0

    func avvia(_ nome: String, durata: Double) {
        link?.invalidate()
        self.nome = nome
        self.durata = durata
        inizio = CACurrentMediaTime()
        ultimo = [:]
        giro = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
        NSLog("STRATI %@ INIZIO", nome)
    }

    @objc private func tick(_ l: CADisplayLink) {
        let t = CACurrentMediaTime() - inizio
        if t > durata { l.invalidate(); link = nil; NSLog("STRATI %@ FINE", nome); return }
        guard let w = FasciaAlta.finestra else { return }
        giro += 1
        let radice = w.layer.presentation() ?? w.layer
        var visti: Set<ObjectIdentifier> = []
        var righe: [String] = []
        visita(w.layer, radice: radice, profondita: 0, percorso: "", visti: &visti, righe: &righe)
        for (k, _) in ultimo where !visti.contains(k) { righe.append("VIA \(k.hashValue % 1_000_000)") }
        ultimo = ultimo.filter { visti.contains($0.key) }
        NSLog("STRATI %@ t=%.3f g=%d n=%d", nome, t, giro, righe.count)
        for r in righe { NSLog("STRATI %@ %@", nome, r) }
    }

    private func visita(_ layer: CALayer, radice: CALayer, profondita: Int, percorso: String, visti: inout Set<ObjectIdentifier>,
                        righe: inout [String]) {
        guard profondita < 60 else { return }
        let p = layer.presentation() ?? layer
        let r = p.convert(p.bounds, to: radice)
        let id = ObjectIdentifier(layer)
        if r.width >= 300 && r.height >= 30 {
            visti.insert(id)
            var classe = String(describing: type(of: layer))
            var sa = ""
            if let v = layer.delegate as? UIView {
                classe = String(describing: type(of: v))
                sa = String(format: " sa=%.0f/%.0f", v.safeAreaInsets.top, v.safeAreaInsets.bottom)
            }
            let colore: String = {
                guard let c = p.backgroundColor, let k = c.components, k.count >= 3 else { return "" }
                return String(format: " bg=%.2f,%.2f,%.2f,%.2f", k[0], k[1], k[2], c.alpha)
            }()
            let riga = String(format: "y=%.1f h=%.1f x=%.1f w=%.1f a=%.2f%@%@%@%@", r.minY, r.height, r.minX, r.width, p.opacity,
                              p.isHidden ? " NASC" : "", p.masksToBounds ? " CLIP" : "", sa, colore)
            if ultimo[id] != riga {
                righe.append("L\(id.hashValue % 1_000_000) d\(profondita) \(classe) \(riga)")
                ultimo[id] = riga
            }
        }
        for s in layer.sublayers ?? [] {
            visita(s, radice: radice, profondita: profondita + 1, percorso: percorso, visti: &visti, righe: &righe)
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
