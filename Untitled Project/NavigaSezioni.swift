import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - MARK XI · muoversi fra le sezioni aperte (mockup approvato dal signore il 3 nov), solo gesti, niente pillole né pallini
// · swipe su VELOCE dal basso: la sezione si scioglie in luce (AGGANCIO: si inclina, la scansione la percorre dal basso, le
//   scintille volano nel reattore, le staffe lo agganciano, il mirino si stringe, il lampo, gli anelli) e torna JARVIS; la sezione
//   resta aperta dietro. Suono «sparisce».
// · swipe su FERMANDOSI A METÀ: le pagine olografiche (SFOGLIO), una alla volta, in cerchio, col numero piccolo «2 / 3» in alto.
//   Tocchi una pagina: si apre (suono «scelta», tranne le sezioni con la fotocamera che hanno il loro). La spingi in su: si chiude.
//   Tocchi fuori: niente. Di nuovo su dal basso: JARVIS. Suono «caricaolo» all'apertura, sfuma al primo gesto.
// · swipe dai BORDI destro e sinistro: la sezione accanto nel cerchio delle aperte (con JARVIS fra l'ultima e la prima), con il
//   giro olografico della pagina.
// I Protocolli scendono dall'alto come sempre: qui non si tocca niente lassù.

final class NavigaSezioni: ObservableObject {
    enum Modo: Equatable { case normale, tira, aggancio, sfoglio, bordo }
    @Published var modo: Modo = .normale
    /// Tirando su dal basso: quanto (punti).
    @Published var su: CGFloat = 0
    /// AGGANCIO: quando è partito.
    @Published var aggancioDa: Date?
    /// SFOGLIO: la posizione (in pagine, continua) e lo spostamento verticale della pagina al centro (su = negativo).
    @Published var P: Double = 0
    @Published var alzata: CGFloat = 0
    /// La pagina scelta che si sta materializzando.
    @Published var scelta: UUID?
    /// BORDO: di quanto (−1…1, negativo verso sinistra) e verso quale sezione (nil = JARVIS).
    @Published var bordo: CGFloat = 0
    @Published var verso: UUID?? = nil
    /// AGGANCIO: la sezione che si sta sciogliendo in luce.
    @Published var agganciata: UUID?
    /// Su dal basso: la tirata è partita dalle pagine olografiche (lasciata, torna a JARVIS).
    var bassoDaSfoglio = false
    /// Su dal basso fermo: la tendina PROTOCOLLI è aperta (o tirata), come nel mockup.
    var bassoFermo = false
    /// Tirando su: lo spostamento di lato del dito (la pagina lo segue per un quarto).
    @Published var dx: CGFloat = 0
    /// Le pagine olografiche che compaiono mentre si tira (0…1).
    @Published var rivela: Double = 0
    /// Il fondo olografico dietro le pagine (0…1).
    @Published var fondo: Double = 0
    /// In questa tirata le pagine sono già comparse (lasciato il dito, restano).
    var rivelata = false
    /// Da quando il dito va piano oltre la soglia delle pagine.
    var lentoDa: Date?
    /// AGGANCIO: la posa da cui parte la pagina (dove l'ha lasciata il dito, o la pagina al centro) e di quanto sale.
    var baseAggancio = Posa()
    var spostaAggancio: CGFloat = 0
    /// AGGANCIO: la sezione è già andata dietro (una sezione aperta intanto si vede e si tocca).
    var dopoAggancio = false
}

/// Dove e come sta una pagina (gli stessi modificatori in tutti i modi: cambiano solo i valori).
struct Posa {
    var scala: CGFloat = 1
    var rotY: Double = 0
    var x: CGFloat = 0
    var y: CGFloat = 0
    var opacita: Double = 1
    var raggio: CGFloat = 0
    var tinta: Double = 0
    var ombra: Double = 0
    var z: Double = 0
    var tocchi = false
}

/// Il ritaglio delle pagine: arrotondato quando sono pagine; a tutto schermo (raggio 0) non taglia niente, nemmeno sotto l'ora.
struct Ritaglio: Shape {
    var raggio: CGFloat
    var animatableData: CGFloat {
        get { raggio }
        set { raggio = newValue }
    }
    func path(in r: CGRect) -> Path {
        raggio <= 0.01 ? Path(r.insetBy(dx: -3000, dy: -3000)) : Path(roundedRect: r, cornerRadius: raggio, style: .continuous)
    }
}

struct PosaPagina: ViewModifier {
    let posa: Posa
    func body(content: Content) -> some View {
        content
            .allowsHitTesting(posa.tocchi)
            .overlay { VeloOlo().opacity(posa.tinta) }
            .clipShape(Ritaglio(raggio: posa.raggio))
            .shadow(color: .ciano.opacity(posa.ombra), radius: posa.ombra > 0 ? 18 : 0)
            .scaleEffect(posa.scala)
            .rotation3DEffect(.degrees(posa.rotY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .offset(x: posa.x, y: posa.y)
            .opacity(posa.opacita)
            .accessibilityHidden(!posa.tocchi)
            .zIndex(posa.z)
    }
}

struct StratoSezioniVista<Vista: View>: View {
    @ObservedObject var pila: PilaSezioni
    @ObservedObject var naviga: NavigaSezioni
    /// Dov'è il reattore (coordinate globali): lì volano le scintille dell'AGGANCIO.
    let reattore: CGPoint
    let vista: (PilaSezioni.Voce) -> Vista
    let portaDavanti: (UUID?) -> Void
    let chiudiDietro: (UUID) -> Void

    @State private var P0: Double = 0
    @State private var assePagina: Int = 0           // 0 da decidere, 1 orizzontale (sfoglia), 2 verticale (alza)
    @State private var trackpad = TrackpadSezioni()  // sul Mac: due dita in orizzontale
    @State private var basso = GestoBassoSezioni()   // su dal basso, poco sopra la barretta di iOS

    private var altezza: CGFloat { FasciaAlta.finestra?.bounds.height ?? 852 }
    private var larghezza: CGFloat { FasciaAlta.finestra?.bounds.width ?? 393 }

    /// Le pagine dello sfoglio: le sezioni aperte, nell'ordine d'apertura.
    private var carte: [PilaSezioni.Voce] { pila.voci }
    private var cerchio: Bool { carte.count > 1 }

    private func quale(_ p: Double) -> Int {
        let n = carte.count
        guard n > 0 else { return 0 }
        let r = Int(p.rounded())
        return cerchio ? ((r % n) + n) % n : max(0, min(n - 1, r))
    }
    private func scarto(_ k: Int) -> Double {
        var o = Double(k) - naviga.P
        if cerchio {
            let n = Double(carte.count)
            o = o.truncatingRemainder(dividingBy: n)
            if o < 0 { o += n }
            if o > n / 2 { o -= n }
        }
        return o
    }

    var body: some View {
        ZStack {
            // sempre presente (sfuma con l'opacità, senza entrare e uscire): nelle pagine prende tocchi e sfoglio anche fuori dalla pagina
            FondoOlo()
                .opacity(naviga.fondo)
                .ignoresSafeArea()
                .allowsHitTesting(naviga.modo == .sfoglio)
                .accessibilityHidden(true)
            ForEach(pila.voci) { v in
                pagina(v)
            }
            if naviga.modo == .sfoglio, !carte.isEmpty {
                Text("\(quale(naviga.P) + 1) / \(carte.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(Color.tenue)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 54)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if naviga.modo == .aggancio, let da = naviga.aggancioDa {
                LuceAggancio(inizio: da, reattore: reattore, base: naviga.baseAggancio, sale: naviga.spostaAggancio,
                             altezza: altezza, larghezza: larghezza)
                    .id(da)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            bordi
        }
        .gesture(gestoSfoglio, including: naviga.modo == .sfoglio ? .all : .subviews)
        .onAppear { preparaTrackpad(); preparaBasso() }
        .onChange(of: pila.voci.isEmpty) { basso.installa() }            // se all'avvio la finestra non c'era ancora
    }

    // MARK: le pagine
    // La vista della sezione sta sempre nello stesso posto (cambiano solo i valori di posa): così passando da un modo all'altro
    // SwiftUI non la ricrea e la sezione resta viva, con i suoi dati.

    @ViewBuilder private func pagina(_ v: PilaSezioni.Voce) -> some View {
        let p = posa(v)
        vista(v)
                .environment(\.sezioneAperta, v.id)
                .environment(\.sezioneDietro, pila.davanti != v.id)        // dietro: fotocamera e microfono in pausa
                .environment(\.jarvisCoperto, false)
                .modifier(AggancioPagina(attivo: naviga.agganciata == v.id, inizio: naviga.aggancioDa, sale: naviga.spostaAggancio))
                .modifier(PosaPagina(posa: p))
                .transition(.offset(y: altezza + 2))               // sale e scende di tutta l'altezza, come prima
    }

    private func posa(_ v: PilaSezioni.Voce) -> Posa {
        var p = Posa()
        let davanti = pila.davanti == v.id
        switch naviga.modo {
        case .sfoglio:
            p = posaSfoglio(v)
        case .bordo:
            let vado = naviga.verso.flatMap { $0 } == v.id
            guard davanti || vado else { p.opacita = 0; return p }
            let b = Double(naviga.bordo)
            let q = davanti ? b : (b < 0 ? 1 + b : b - 1)          // la pagina che entra arriva dal lato opposto
            p.scala = CGFloat(1 - min(1, abs(q)) * 0.18)
            p.rotY = q * 55
            p.x = CGFloat(q) * larghezza * 0.85
            p.opacita = 1 - max(0, abs(q) - 0.6) * 2.5
            p.raggio = abs(q) > 0.01 ? 28 : 0
            p.tinta = min(1, abs(q) * 2.2)
            p.z = davanti ? 2 : 1
        case .tira:
            if davanti {
                p = posaTirata()
            } else if naviga.rivela > 0.001 {
                p = posaSfoglio(v)
                p.opacita *= naviga.rivela
            } else {
                p.opacita = 0
            }
        case .aggancio:
            if naviga.agganciata == v.id {
                p = naviga.baseAggancio
                p.tocchi = false
                p.z = 100
            } else if davanti && naviga.dopoAggancio {
                p.tocchi = true
                p.z = 1
            } else {
                p.opacita = 0
            }
        case .normale:
            p.opacita = davanti ? 1 : 0
            p.tocchi = davanti
            p.z = davanti ? 1 : 0
        }
        return p
    }

    /// Tirata su dal basso: la pagina segue il dito come nel mockup (rimpicciolisce fino a 0,6 al 45% dell'altezza, sale di 0,55
    /// volte il dito, di lato di un quarto) e prende il tono olografico.
    private func posaTirata() -> Posa {
        var p = Posa()
        let q = min(1, naviga.su / (altezza * 0.45))
        p.scala = 1 - 0.4 * q
        p.x = naviga.dx * 0.25
        p.y = -naviga.su * 0.55
        p.raggio = min(28, naviga.su / 6)
        p.tinta = Double(min(1, q * 3))
        p.ombra = 0.45 * Double(min(1, q * 3))
        p.z = 100
        return p
    }

    /// Le pagine olografiche, come nel mockup: una pagina alla volta in 3D (scala 0,8; le accanto girate di 50° per pagina, indietro
    /// di 320 in prospettiva 1100, che si vedono solo sfogliando); la pagina al centro spinta in su sfuma.
    private func posaSfoglio(_ v: PilaSezioni.Voce) -> Posa {
        var p = Posa()
        let k = carte.firstIndex(where: { $0.id == v.id }) ?? 0
        let o = scarto(k), a = abs(o), mat = naviga.scelta == v.id
        let centro = a < 0.5 && !mat
        p.scala = mat ? 1 : CGFloat(0.8 * 1100 / (1100 + min(a, 1.3) * 320))
        p.rotY = mat ? 0 : o * 50
        p.x = mat ? 0 : CGFloat(o) * larghezza * 0.74
        p.y = mat ? 0 : -altezza * 0.02 + (centro ? naviga.alzata : 0)
        let via = centro ? max(0, 1 + Double(min(0, naviga.alzata) / (altezza * 0.55))) : 1
        p.opacita = mat ? 1 : max(0, 1 - a * 1.25) * via
        p.raggio = mat ? 0 : 28
        p.tinta = mat ? 0 : 1
        p.ombra = mat ? 0 : 0.45
        p.z = mat ? 100 : 50 - a * 10
        return p
    }

    // MARK: i bordi ai lati (la sezione accanto). Su dal basso: `GestoBassoSezioni`, sulla finestra.

    @ViewBuilder private var bordi: some View {
        let davanti = pila.voceDavanti
        if naviga.modo != .sfoglio && davanti != nil {
            HStack(spacing: 0) {
                Color.clear.frame(width: 20).contentShape(Rectangle()).gesture(gestoBordo(da: -1))
                Spacer(minLength: 0).allowsHitTesting(false)
                Color.clear.frame(width: 20).contentShape(Rectangle()).gesture(gestoBordo(da: 1))
            }
            .ignoresSafeArea()
            .zIndex(199)
        }
    }

    // MARK: su dal basso (3 nov sera, deciso dal signore): parte nella fascia poco sopra la barretta di iOS, come la tendina in alto
    // che parte sotto la Dynamic Island. Il bordo resta tutto di iOS: si esce dall'app al primo colpo. Le misure (GestoBassoSezioni):
    // - su veloce (lasciato oltre 500 punti/s, almeno 40 punti): AGGANCIO, la sezione va nel reattore;
    // - su lento e trascinato fin quasi al centro (oltre un terzo dell'altezza, sotto i 400 punti/s per 60 ms): compaiono le pagine
    //   olografiche col loro suono, anche col dito ancora giù; lasciato, si resta lì. Lento e lasciato oltre un terzo: lo stesso;
    // - poco e lasciato: la sezione torna com'era;
    // - dalle pagine, di nuovo su dalla fascia: JARVIS (la pagina al centro va nel reattore).
    // Da JARVIS, con sezioni aperte: le pagine compaiono col dito e restano oltre il 5% dell'altezza (o lasciate veloci).

    private func preparaBasso() {
        Suoni.preparaPagine()
        basso.puo = {
            !pila.voci.isEmpty && !naviga.bassoFermo && (naviga.modo == .normale || naviga.modo == .sfoglio)
        }
        basso.inizia = { naviga.bassoDaSfoglio = naviga.modo == .sfoglio }
        basso.segue = { su, dx, velocita in bassoSegue(su: su, dx: dx, velocita: velocita) }
        basso.finisce = { su, velocita in bassoFinisce(su: su, velocita: velocita) }
        basso.installa()
    }

    /// Il dito sale (`su` e `dx` in punti; `velocita` in punti al secondo, positiva verso l'alto).
    private func bassoSegue(su: CGFloat, dx: CGFloat, velocita: CGFloat) {
        if naviga.bassoDaSfoglio || naviga.modo == .sfoglio { return }     // dalle pagine: decide la fine
        let q = Double(min(1, su / (altezza * 0.45)))
        if naviga.modo == .normale {
            let k = pila.voceDavanti.flatMap { d in carte.firstIndex { $0.id == d.id } } ?? 0
            naviga.P = Double(k)
            naviga.alzata = 0
            naviga.rivelata = false
            naviga.lentoDa = nil
            naviga.rivela = 0
            naviga.modo = .tira
        }
        guard naviga.modo == .tira else { return }
        naviga.fondo = min(1, q * 2.2)
        if pila.voceDavanti == nil {                                       // da JARVIS: le pagine compaiono col dito
            naviga.rivela = min(1, q * 2.5)
            if q > 0.1 && !naviga.rivelata { naviga.rivelata = true; Suoni.caricaOlo() }
            return
        }
        naviga.su = su
        naviga.dx = dx
        guard !naviga.rivelata else { return }
        // lento oltre la soglia, per 60 ms: le pagine compaiono (anche col dito fermo, che non manda più movimenti)
        if su >= altezza * GestoBassoSezioni.soglia && abs(velocita) <= GestoBassoSezioni.lento {
            guard naviga.lentoDa == nil else { return }
            let da = Date()
            naviga.lentoDa = da
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(GestoBassoSezioni.tenuta * 1000)))
                if naviga.lentoDa == da, naviga.modo == .tira, !naviga.rivelata { rivelaPagine() }
            }
        } else {
            naviga.lentoDa = nil
        }
    }

    private func bassoFinisce(su: CGFloat, velocita: CGFloat) {
        let daSfoglio = naviga.bassoDaSfoglio
        naviga.bassoDaSfoglio = false
        naviga.lentoDa = nil
        switch naviga.modo {
        case .sfoglio:
            // partita dalle pagine: di nuovo su = JARVIS (aperte in questa stessa tirata: restano)
            if daSfoglio && (su > 36 || velocita > GestoBassoSezioni.diNuovoSu) { tornaAJarvis() }
        case .tira:
            if pila.voceDavanti == nil {
                if su > altezza * 0.45 * 0.12 || velocita > GestoBassoSezioni.diNuovoSu { entraSfoglio() } else { tornaGiu() }
            } else if naviga.rivelata {
                entraSfoglio()
            } else if velocita >= GestoBassoSezioni.veloce && su >= GestoBassoSezioni.minimo {
                aggancio(da: posaTirata(), id: pila.davanti)               // su veloce: AGGANCIO
            } else if su >= altezza * GestoBassoSezioni.soglia {
                entraSfoglio()                                             // lento e lasciato oltre la soglia: le pagine
            } else {
                tornaGiu()                                                 // poco: torna com'era
            }
        default: break
        }
    }

    private func gestoBordo(da lato: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                if naviga.modo == .normale {
                    guard let r = pila.vicina(di: pila.davanti, passo: lato) else { return }
                    naviga.verso = r
                    naviga.modo = .bordo
                    Suoni.zittisciOlo()
                }
                guard naviga.modo == .bordo else { return }
                // dal bordo destro il dito va a sinistra (avanti), dal sinistro a destra (indietro)
                let p = max(-1, min(1, v.translation.width / larghezza))
                naviga.bordo = lato > 0 ? min(0, p) : max(0, p)
            }
            .onEnded { v in
                guard naviga.modo == .bordo else { return }
                let p = v.predictedEndTranslation.width / larghezza
                let fatto = abs(naviga.bordo) > 0.35 || (lato > 0 ? p < -0.6 : p > 0.6)
                if fatto, let r = naviga.verso {
                    withAnimation(.easeOut(duration: 0.22)) { naviga.bordo = lato > 0 ? -1 : 1 }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(230))
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { portaDavanti(r) }
                        await Task.yield()
                        withTransaction(t) { naviga.modo = .normale; naviga.bordo = 0; naviga.verso = nil }
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { naviga.bordo = 0 }
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); if naviga.bordo == 0 { naviga.modo = .normale; naviga.verso = nil } }
                }
            }
    }

    /// Sul Mac, il trackpad: come il bordo (lato +1 = avanti, la sezione dopo; −1 = indietro).
    private func preparaTrackpad() {
        trackpad.inizia = { lato in
            guard naviga.modo == .normale, pila.voceDavanti != nil,
                  let r = pila.vicina(di: pila.davanti, passo: Int(lato)) else { return false }
            naviga.verso = r
            naviga.modo = .bordo
            return true
        }
        trackpad.segue = { p in if naviga.modo == .bordo { naviga.bordo = p } }
        trackpad.finisce = { p, lancio in
            guard naviga.modo == .bordo else { return }
            if (abs(p) > 0.25 || abs(lancio) > 0.5), let r = naviga.verso {
                withAnimation(.easeOut(duration: 0.22)) { naviga.bordo = p < 0 ? -1 : 1 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(230))
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { portaDavanti(r) }
                    await Task.yield()
                    withTransaction(t) { naviga.modo = .normale; naviga.bordo = 0; naviga.verso = nil }
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { naviga.bordo = 0 }
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); if naviga.bordo == 0 { naviga.modo = .normale; naviga.verso = nil } }
            }
        }
        trackpad.installa()
    }

    // MARK: le pagine olografiche

    /// Le pagine compaiono col dito ancora giù: il suono «caricaolo» e, allo stesso istante, le pagine in 0,30 s (il suono sale fino
    /// a 0,32 s).
    private func rivelaPagine() {
        naviga.rivelata = true
        naviga.lentoDa = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let fra = min(Suoni.caricaOlo(), TempiAggancio.attesaMassima)
        withAnimation(.linear(duration: TempiAggancio.rivela).delay(fra)) { naviga.rivela = 1 }
    }

    /// Lasciato il dito: la pagina tirata (o la prima, da JARVIS) si posa al centro delle pagine in 0,26 s, come nel mockup.
    private func entraSfoglio() {
        guard !carte.isEmpty else { tornaGiu(); return }
        if !naviga.rivelata {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Suoni.caricaOlo()
        }
        naviga.rivelata = false
        withAnimation(TempiAggancio.posa) {
            naviga.modo = .sfoglio
            naviga.su = 0
            naviga.dx = 0
            naviga.alzata = 0
            naviga.fondo = 1
            naviga.rivela = 1
        }
    }

    /// Poco e lasciato: la pagina torna com'era (0,22 s).
    private func tornaGiu() {
        naviga.rivelata = false
        withAnimation(TempiAggancio.ritorno) {
            naviga.su = 0
            naviga.dx = 0
            naviga.fondo = 0
            naviga.rivela = 0
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(TempiAggancio.durataRitorno * 1000) + 10))
            if naviga.modo == .tira && naviga.su == 0 { naviga.modo = .normale }
        }
    }

    /// Dalle pagine, di nuovo su dal basso: la pagina al centro va nel reattore (AGGANCIO, col suo suono) e torna JARVIS.
    private func tornaAJarvis() {
        Suoni.zittisciOlo()
        let k = quale(naviga.P)
        guard carte.indices.contains(k) else {
            portaDavanti(nil)
            withAnimation(TempiAggancio.ritorno) { naviga.modo = .normale; naviga.alzata = 0; naviga.fondo = 0; naviga.rivela = 0 }
            return
        }
        aggancio(da: posaSfoglio(carte[k]), id: carte[k].id)
    }

    private var gestoSfoglio: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                // nella fascia in basso il gesto può partire un attimo dopo il tocco (aspetta lo swipe su): la pagina di partenza
                // si prende finché l'asse non è deciso, non solo al primo istante
                if v.translation == .zero { assePagina = 0 }
                if assePagina == 0 { P0 = naviga.P }
                if v.translation == .zero { return }
                if assePagina == 0, hypot(v.translation.width, v.translation.height) > 8 {
                    assePagina = abs(v.translation.width) > abs(v.translation.height) ? 1 : 2
                    Suoni.zittisciOlo()
                }
                if assePagina == 1 {
                    var p = P0 - Double(v.translation.width / (larghezza * 0.74))
                    if !cerchio { p = max(-0.3, min(Double(carte.count - 1) + 0.3, p)) }
                    naviga.P = p
                } else if assePagina == 2 {
                    naviga.alzata = min(0, v.translation.height)
                }
            }
            .onEnded { v in
                if assePagina == 0 {                                         // un tocco: sulla pagina al centro, si apre
                    let w = larghezza * 0.8 * 0.5, h = altezza * 0.8 * 0.5
                    let c = CGPoint(x: larghezza / 2, y: altezza / 2)
                    if abs(v.location.x - c.x) < w && abs(v.location.y - c.y) < h { scegli() }
                    return
                }
                if assePagina == 1 {
                    let lancio = -Double(v.predictedEndTranslation.width - v.translation.width) / Double(larghezza * 0.74)
                    var meta = (naviga.P + max(-1, min(1, lancio))).rounded()
                    if !cerchio { meta = max(0, min(Double(carte.count - 1), meta)) }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { naviga.P = meta }
                    UISelectionFeedbackGenerator().selectionChanged()
                } else if assePagina == 2 {
                    if naviga.alzata < -altezza * 0.16 || v.velocity.height < -600 { chiudiCarta() }   // come nel mockup
                    else { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { naviga.alzata = 0 } }
                }
                assePagina = 0
            }
    }

    /// La pagina al centro si materializza a tutto schermo (0,32 s) e torna davanti; il click «scelta» arriva quando tocca il pieno
    /// schermo, come nel mockup.
    private func scegli() {
        let k = quale(naviga.P)
        guard carte.indices.contains(k) else { return }
        let v = carte[k]
        Suoni.zittisciOlo()
        if !v.sezione.conFotocamera { Suoni.sceltaPagina(fra: TempiAggancio.scelta - TempiAggancio.colpoScelta) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: TempiAggancio.scelta)) {
            naviga.scelta = v.id
            naviga.P = Double(k)
            naviga.fondo = 0.7
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(TempiAggancio.scelta * 1000)))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { portaDavanti(v.id) }
            await Task.yield()                                        // la sezione è davanti: ora le pagine se ne vanno
            withTransaction(t) {
                naviga.modo = .normale
                naviga.scelta = nil
                naviga.alzata = 0
                naviga.fondo = 0
                naviga.rivela = 0
            }
        }
    }

    /// La pagina al centro, spinta in su, si chiude.
    private func chiudiCarta() {
        let k = quale(naviga.P)
        guard carte.indices.contains(k) else { return }
        let id = carte[k].id
        Suoni.zittisciOlo()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeIn(duration: 0.22)) { naviga.alzata = -altezza }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                naviga.alzata = 0
                chiudiDietro(id)
                if pila.voci.isEmpty {
                    naviga.modo = .normale
                    naviga.fondo = 0
                    naviga.rivela = 0
                } else {
                    naviga.P = Double(quale(naviga.P))
                }
            }
        }
    }

    // MARK: AGGANCIO (come lo stile «mix» del mockup, a tempo col suono «sparisce»)

    /// La pagina parte da dove è (`base`: dove l'ha lasciata il dito, o la pagina al centro delle pagine olografiche) e va nel
    /// reattore. Il suono parte a un istante preciso e l'animazione allo stesso istante: i suoi momenti cadono sui colpi del suono.
    private func aggancio(da base: Posa, id: UUID?) {
        Suoni.zittisciOlo()
        let fra = min(Suoni.sparisce(), TempiAggancio.attesaMassima)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let bersaglio = (reattore.y - altezza / 2) * 0.4                // sale verso il reattore (come nel mockup)
        naviga.baseAggancio = base
        naviga.spostaAggancio = (bersaglio - base.y) / max(0.1, base.scala)
        naviga.aggancioDa = Date().addingTimeInterval(fra)
        naviga.agganciata = id
        naviga.dopoAggancio = false
        naviga.rivelata = false
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            naviga.modo = .aggancio
            naviga.rivela = 0
        }
        withAnimation(.timingCurve(0.45, 0, 0.55, 1, duration: TempiAggancio.fase).delay(fra)) { naviga.fondo = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((fra + TempiAggancio.fase) * 1000)))
            var senza = Transaction(); senza.disablesAnimations = true
            withTransaction(senza) {
                portaDavanti(nil)                                         // la sezione va dietro (viva), davanti JARVIS
                naviga.dopoAggancio = true
            }
            try? await Task.sleep(for: .milliseconds(Int((TempiAggancio.fine - TempiAggancio.fase) * 1000)))
            if naviga.modo == .aggancio {
                withTransaction(senza) {
                    naviga.modo = .normale
                    naviga.aggancioDa = nil
                    naviga.agganciata = nil
                    naviga.dopoAggancio = false
                    naviga.su = 0
                    naviga.dx = 0
                    naviga.alzata = 0
                }
            }
        }
    }
}

/// I tempi delle pagine, uguali nel mockup, a tempo coi suoni (misurati sui file il 3 nov sera). L'animazione anticipa i colpi
/// di 10–20 ms: l'occhio la sente insieme al suono (la luce arriva prima del suono anche nella realtà).
enum TempiAggancio {
    /// AGGANCIO («sparisce»: colpi a 0,466 e 1,002 s). Fino a 0,44 la pagina si inclina e si scioglie dal basso; a 0,44 la riga
    /// arriva in cima, le staffe agganciano e il mirino scatta.
    static let fase: Double = 0.44
    /// Il lampo nel reattore: da 0,43, pieno a 0,45, spento a 0,60.
    static let lampo: Double = 0.43
    /// I due battiti del reattore, sui due colpi del suono.
    static let battiti: [(Double, Double)] = [(0.455, 1), (0.99, 0.75)]
    static let fine: Double = 1.5
    /// SFOGLIO («caricaolo»: sale fino a 0,32 s): le pagine compaiono in 0,30 s.
    static let rivela: Double = 0.30
    /// La pagina scelta arriva a schermo pieno («scelta»: il colpo a 0,055 s dall'inizio del file).
    static let scelta: Double = 0.32
    static let colpoScelta: Double = 0.055
    /// Con cuffie Bluetooth lente l'animazione aspetta il suono al massimo 0,15 s (oltre, il gesto sembrerebbe lento).
    static let attesaMassima: Double = 0.15
    /// La pagina si posa nelle pagine olografiche (0,26 s) o torna com'era (0,22 s): curva «ease out» cubica, come nel mockup.
    static let posa = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.26)
    static let durataRitorno: Double = 0.22
    static let ritorno = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 0.22)
}

/// AGGANCIO, la pagina: si inclina indietro (fino a 42°), si rimpicciolisce (0,7) e sale verso il reattore, mentre la riga di
/// scansione la percorre dal basso in alto e se la porta via (0–0,44 s, curva «ease in-out»), come nel mockup.
struct AggancioPagina: ViewModifier {
    let attivo: Bool
    let inizio: Date?
    let sale: CGFloat

    /// «ease in-out» quadratica (la stessa del mockup).
    static func curva(_ a: Double) -> Double { a < 0.5 ? 2 * a * a : 1 - pow(-2 * a + 2, 2) / 2 }

    // sempre dentro lo stesso TimelineView (fermo quando non serve): la sezione non viene mai ricreata
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !attivo)) { ctx in
            let dt = attivo ? max(0, ctx.date.timeIntervalSince(inizio ?? ctx.date)) : 0
            let e = AggancioPagina.curva(min(1, dt / TempiAggancio.fase))
            let yy = 1.02 - e * 1.06                                   // la riga: dal 102% (sotto) al −4% (sopra la cima)
            content
                .overlay(alignment: .top) {
                    GeometryReader { g in
                        Rectangle()
                            .fill(Color(red: 0.875, green: 0.98, blue: 1))
                            .frame(height: 2)
                            .shadow(color: .ciano, radius: 5)
                            .shadow(color: .ciano.opacity(0.85), radius: 13)
                            .offset(y: g.size.height * yy - 1)
                            .opacity(attivo && yy > -0.04 && yy < 1.02 ? 1 : 0)
                    }
                    .allowsHitTesting(false)
                }
                .mask {
                    if attivo {
                        LinearGradient(stops: [.init(color: .black, location: max(0, min(1, yy - 0.03))),
                                               .init(color: .clear, location: max(0, min(1, yy + 0.01)))],
                                       startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle().padding(-3000)                     // fermo: non taglia niente
                    }
                }
                .rotation3DEffect(.degrees(42 * e), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
                .scaleEffect(1 - 0.3 * e)
                .offset(y: sale * e)
        }
    }
}

/// AGGANCIO, la luce (lo stile «mix» del mockup, stessi numeri): le staffe inquadrano la pagina e a 0,44 s si chiudono sul reattore;
/// le scintille nascono sulla riga di scansione (950 al secondo) e corrono nel reattore; il mirino a tre anelli si stringe, scatta
/// all'aggancio e gira; il lampo (pieno a 0,45 s) e i due battiti (0,455 e 0,99 s) sui colpi del suono; tutto si spegne a 1,5 s.
/// Un orologio solo, a 120 Hz.
struct LuceAggancio: View {
    let inizio: Date
    let reattore: CGPoint
    let base: Posa
    let sale: CGFloat
    let altezza: CGFloat
    let larghezza: CGFloat
    @State private var scintille: [Scintilla]

    struct Scintilla {
        let x0: Double, y0: Double, t0: Double, dur: Double, cx: Double, cy: Double, s: Double
    }

    init(inizio: Date, reattore: CGPoint, base: Posa, sale: CGFloat, altezza: CGFloat, larghezza: CGFloat) {
        self.inizio = inizio
        self.reattore = reattore
        self.base = base
        self.sale = sale
        self.altezza = altezza
        self.larghezza = larghezza
        _scintille = State(initialValue: LuceAggancio.genera(base: base, sale: sale, altezza: altezza, larghezza: larghezza))
    }

    /// Dove sta la pagina all'istante `t` (sullo schermo): la posa di partenza, rimpicciolita, inclinata e salita.
    static func rettangolo(_ t: Double, base: Posa, sale: CGFloat, altezza: CGFloat, larghezza: CGFloat) -> CGRect {
        let e = AggancioPagina.curva(min(1, max(0, t) / TempiAggancio.fase))
        let s = base.scala * CGFloat(1 - 0.3 * e)
        let w = larghezza * s, h = altezza * s * CGFloat(cos(42 * e * .pi / 180))
        let cx = larghezza / 2 + base.x, cy = altezza / 2 + base.y + sale * CGFloat(e) * base.scala
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Le scintille, tutte prima (come le nasce il mockup fotogramma per fotogramma): sulla riga di scansione di quell'istante.
    static func genera(base: Posa, sale: CGFloat, altezza: CGFloat, larghezza: CGFloat) -> [Scintilla] {
        let F = TempiAggancio.fase, n = Int(950 * F)
        return (0..<n).map { i in
            let t0 = F * (Double(i) + Double.random(in: 0..<1)) / Double(n)
            let r = rettangolo(t0, base: base, sale: sale, altezza: altezza, larghezza: larghezza)
            let e = AggancioPagina.curva(min(1, t0 / F))
            let yy = max(0, min(1, 1.02 - e * 1.06))
            let ly = Double(r.minY) + Double(r.height) * yy
            return Scintilla(x0: Double(r.minX) + Double.random(in: 0..<1) * Double(r.width),
                             y0: ly + (Double.random(in: 0..<1) - 0.5) * 6,
                             t0: t0,
                             dur: 0.36 + Double.random(in: 0..<1) * 0.2 + (F - t0) * 0.3,
                             cx: (Double.random(in: 0..<1) - 0.5) * 120,
                             cy: -10 - Double.random(in: 0..<1) * min(110, ly * 0.5),
                             s: 0.7 + Double.random(in: 0..<1) * 1.4)
        }
    }

    private static func colore(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255).opacity(max(0, min(1, a)))
    }

    /// Un arco come spezzata (il verso è sempre quello giusto, a schermo).
    private static func arco(_ p: inout Path, centro c: CGPoint, raggio r: Double, da a0: Double, lungo l: Double) {
        let passi = max(3, Int(l * r / 6))
        for i in 0...passi {
            let a = a0 + l * Double(i) / Double(passi)
            let q = CGPoint(x: Double(c.x) + cos(a) * r, y: Double(c.y) + sin(a) * r)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: false)) { ctx in
            let t = max(0, ctx.date.timeIntervalSince(inizio))
            Canvas { gc, _ in disegna(&gc, t: t) }
        }
    }

    private func disegna(_ gc: inout GraphicsContext, t: Double) {
        guard t < TempiAggancio.fine else { return }
        gc.blendMode = .plusLighter
        let F = TempiAggancio.fase, R = reattore, ease = AggancioPagina.curva

        // le staffe: inquadrano la pagina fino all'aggancio, poi si chiudono sul reattore (0,44–0,54 s) e si spengono (0,62)
        var riquadro: CGRect?
        var alS = 0.0
        if t < F {
            riquadro = LuceAggancio.rettangolo(t, base: base, sale: sale, altezza: altezza, larghezza: larghezza)
            alS = min(1, t / 0.08)
        } else if t < F + 0.18 {
            let b0 = LuceAggancio.rettangolo(F, base: base, sale: sale, altezza: altezza, larghezza: larghezza)
            let u = min(1, (t - F) / 0.10), e = CGFloat(1 - pow(1 - u, 3))
            let w = b0.width + (104 - b0.width) * e, h = b0.height + (104 - b0.height) * e
            let cx = b0.midX + (R.x - b0.midX) * e, cy = b0.midY + (R.y - b0.midY) * e
            riquadro = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            alS = t < F + 0.10 ? 1 : 1 - (t - F - 0.10) / 0.08
        }
        if let b = riquadro?.insetBy(dx: -5, dy: -5), alS > 0 {
            let l = max(8, min(26, b.width * 0.12))
            var st = Path()
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
                let px = b.midX + sx * b.width / 2, py = b.midY + sy * b.height / 2
                st.move(to: CGPoint(x: px - sx * l, y: py))
                st.addLine(to: CGPoint(x: px, y: py))
                st.addLine(to: CGPoint(x: px, y: py - sy * l))
            }
            gc.stroke(st, with: .color(LuceAggancio.colore(143, 240, 255, alS * 0.95)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // le scintille: dalla riga di scansione, lungo una curva, dentro il reattore (a gruppi: poche passate di disegno a 120 Hz)
        var tratti = [Path](repeating: Path(), count: 12), punti = [Path](repeating: Path(), count: 12)
        for p in scintille {
            let u = (t - p.t0) / p.dur
            guard u >= 0, u <= 1 else { continue }
            func qb(_ v: Double) -> CGPoint {
                let a = 1 - v
                return CGPoint(x: a * a * p.x0 + 2 * a * v * (p.x0 + p.cx) + v * v * Double(R.x),
                               y: a * a * p.y0 + 2 * a * v * (p.y0 + p.cy) + v * v * Double(R.y))
            }
            let e1 = u * u * (3 - 2 * u), u2 = max(0, u - 0.1), e2 = u2 * u2 * (3 - 2 * u2)
            let qa = qb(e1), qs = qb(e2)
            let k = min(3, Int(u * 4)) * 3 + min(2, Int((p.s - 0.7) / 1.4 * 3))
            tratti[k].move(to: qs)
            tratti[k].addLine(to: qa)
            punti[k].addEllipse(in: CGRect(x: Double(qa.x) - p.s, y: Double(qa.y) - p.s, width: p.s * 2, height: p.s * 2))
        }
        for k in 0..<12 where !tratti[k].isEmpty {
            let uMedio = (Double(k / 3) + 0.5) / 4, sMedio = 0.7 + (Double(k % 3) + 0.5) / 3 * 1.4
            gc.stroke(tratti[k], with: .color(LuceAggancio.colore(79, 227, 255, 0.5 * (1 - uMedio * 0.3))),
                      style: StrokeStyle(lineWidth: sMedio * 0.9, lineCap: .round))
            gc.fill(punti[k], with: .color(LuceAggancio.colore(223, 250, 255, 1 - uMedio * 0.45)))
        }

        // il mirino sul reattore: si stringe mentre la pagina si scioglie, scatta all'aggancio, poi gira e si spegne
        let stringe = t < F ? 1.9 - 0.9 * ease(t / F) : (t < F + 0.08 ? 1 - 0.12 * sin((t - F) / 0.08 * .pi) : 1)
        let alM = t < 0.1 ? t / 0.1 : max(0, 1 - max(0, t - 1) / 0.5)
        if alM > 0 {
            let giro = t * (t < F ? 1.2 : 3)
            let anelli: [(Double, Int, Double, Double, Double)] = [(46, 12, 1.6, 2, 0.55), (60, 36, -0.9, 1, 0.4), (74, 6, 0.6, 3, 0.3)]
            for (r, n, vel, lw, a0) in anelli {
                var anello = Path()
                let passo = 2 * Double.pi / Double(n)
                for i in 0..<n { LuceAggancio.arco(&anello, centro: R, raggio: r * stringe, da: giro * vel + Double(i) * passo, lungo: passo * 0.55) }
                gc.stroke(anello, with: .color(LuceAggancio.colore(143, 240, 255, alM * a0 * 1.6)), style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            }
            var tacche = Path()
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + (t < F ? 0 : (t - F) * 4), r1 = 86 * stringe, r2 = r1 + 9
                tacche.move(to: CGPoint(x: Double(R.x) + cos(a) * r1, y: Double(R.y) + sin(a) * r1))
                tacche.addLine(to: CGPoint(x: Double(R.x) + cos(a) * r2, y: Double(R.y) + sin(a) * r2))
            }
            gc.stroke(tacche, with: .color(LuceAggancio.colore(191, 246, 255, alM * 0.8)), lineWidth: 1.2)
        }

        // il lampo dell'aggancio: da 0,43 s, pieno a 0,45 (sul colpo del suono), spento a 0,60
        let L = TempiAggancio.lampo
        if t > L && t < L + 0.17 {
            let u = (t - L) / 0.17, al = 0.8 * (u < 0.12 ? u / 0.12 : (1 - u) / 0.88), raggio = 60 + u * 40
            gc.fill(Path(ellipseIn: CGRect(x: Double(R.x) - 100, y: Double(R.y) - 100, width: 200, height: 200)),
                    with: .radialGradient(Gradient(colors: [LuceAggancio.colore(240, 253, 255, al), LuceAggancio.colore(79, 227, 255, 0)]),
                                          center: R, startRadius: 0, endRadius: raggio))
        }

        // i due battiti del reattore, sui due colpi del suono
        for (tb, forza) in TempiAggancio.battiti {
            let u = (t - tb) / 0.5
            guard u > 0, u < 1 else { continue }
            let e = 1 - pow(1 - u, 2.5), al = (1 - u) * forza
            let rg = 70 + e * 50, ra = 28 + e * 96
            gc.fill(Path(ellipseIn: CGRect(x: Double(R.x) - rg, y: Double(R.y) - rg, width: rg * 2, height: rg * 2)),
                    with: .radialGradient(Gradient(colors: [LuceAggancio.colore(223, 250, 255, al * 0.55), LuceAggancio.colore(79, 227, 255, 0)]),
                                          center: R, startRadius: 0, endRadius: rg))
            gc.stroke(Path(ellipseIn: CGRect(x: Double(R.x) - ra, y: Double(R.y) - ra, width: ra * 2, height: ra * 2)),
                      with: .color(LuceAggancio.colore(143, 240, 255, al * 0.9)), lineWidth: 2 * (1 - u) + 0.5)
        }
    }
}

/// Il fondo delle pagine olografiche, come nel mockup: il blu scurissimo che sfuma dal centro e la griglia ciano di 22 punti.
struct FondoOlo: View {
    var body: some View {
        ZStack {
            EllipticalGradient(colors: [Color(red: 6 / 255, green: 27 / 255, blue: 34 / 255), Color(red: 1 / 255, green: 5 / 255, blue: 7 / 255)],
                               center: UnitPoint(x: 0.5, y: 0.46), startRadiusFraction: 0, endRadiusFraction: 1)
            Canvas { gc, size in
                var griglia = Path()
                var x: CGFloat = 0
                while x < size.width { griglia.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 22 }
                var y: CGFloat = 0
                while y < size.height { griglia.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 22 }
                gc.fill(griglia, with: .color(Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.05)))
            }
        }
        .contentShape(Rectangle())
    }
}

/// Il tono olografico delle pagine: un velo ciano con le righe di scansione.
struct VeloOlo: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.ciano.opacity(0.22), Color.ciano.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                .blendMode(.screen)
            Canvas { gc, size in
                var y: CGFloat = 0
                var righe = Path()
                while y < size.height { righe.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 3 }
                gc.fill(righe, with: .color(.black.opacity(0.18)))
            }
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.ciano.opacity(0.7), lineWidth: 1.2)
        }
        .allowsHitTesting(false)
    }
}

/// Sul Mac: due dita sul trackpad, in orizzontale, fanno lo stesso dello swipe dai bordi (la sezione accanto nel cerchio).
/// Il riconoscitore sta sulla finestra e sente solo lo scorrimento del trackpad (nessun tocco): non toglie niente agli altri gesti
/// e lo scorrimento in verticale resta delle sezioni.
final class TrackpadSezioni: NSObject, UIGestureRecognizerDelegate {
    var inizia: (CGFloat) -> Bool = { _ in false }       // il verso (+1 avanti, −1 indietro): vero se c'è una sezione accanto
    var segue: (CGFloat) -> Void = { _ in }              // −1…1
    var finisce: (CGFloat, CGFloat) -> Void = { _, _ in } // spostamento e slancio (frazioni della larghezza)
    private var asse = 0                                  // 0 da decidere, 1 orizzontale, 2 verticale (ignorato)
    private weak var finestra: UIWindow?
    private var riconoscitore: UIPanGestureRecognizer?

    func installa() {
        guard ProcessInfo.processInfo.isiOSAppOnMac, riconoscitore == nil, let w = FasciaAlta.finestra else { return }
        let r = UIPanGestureRecognizer(target: self, action: #selector(scorre(_:)))
        r.allowedScrollTypesMask = .continuous
        r.allowedTouchTypes = []
        r.cancelsTouchesInView = false
        r.delegate = self
        w.addGestureRecognizer(r)
        riconoscitore = r
        finestra = w
    }

    @objc private func scorre(_ r: UIPanGestureRecognizer) {
        let w = max(1, finestra?.bounds.width ?? 1000)
        let t = r.translation(in: finestra)
        switch r.state {
        case .began:
            asse = 0
        case .changed:
            if asse == 0, hypot(t.x, t.y) > 10 {
                asse = abs(t.x) > abs(t.y) * 1.5 && inizia(t.x < 0 ? 1 : -1) ? 1 : 2
            }
            if asse == 1 { segue(max(-1, min(1, t.x / w))) }
        case .ended, .cancelled, .failed:
            if asse == 1 { finisce(t.x / w, r.velocity(in: finestra).x / w * 0.3) }
            asse = 0
        default: break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}

/// Su dal basso (3 nov sera, deciso dal signore): il gesto parte nella fascia appena sopra la zona della barretta di iOS (il margine
/// sicuro in basso; sul Mac e sugli iPhone col tasto Home, dal fondo), alta 56 punti e larga quanto lo schermo. Il bordo resta di iOS,
/// come in alto per la tendina: si esce dall'app al primo swipe, sempre.
/// Il riconoscitore sta sulla finestra e sente solo i tocchi che partono nella fascia. Prende solo lo swipe verso l'alto: un tocco,
/// lo scorrere in orizzontale o verso il basso restano della sezione. Quando lo prende, ha la precedenza sullo scorrimento della
/// sezione sotto (che così non si muove insieme). Spento con una schermata di iOS sopra (Safari, foto, aiuto).
final class GestoBassoSezioni: NSObject, UIGestureRecognizerDelegate {
    /// La fascia: 56 punti sopra la zona di iOS (su iPhone 15 Pro: dai 34 ai 90 punti dal fondo), un pollice comodo.
    static let alta: CGFloat = 56
    /// Le pagine: oltre un terzo dell'altezza (partendo dalla fascia il dito arriva appena sotto il centro).
    static let soglia: CGFloat = 0.33
    /// Lento: sotto i 400 punti al secondo, per 60 ms (anche col dito fermo).
    static let lento: CGFloat = 400
    static let tenuta: Double = 0.06
    /// Veloce, lasciato: oltre i 500 punti al secondo verso l'alto, dopo almeno 40 punti (AGGANCIO).
    static let veloce: CGFloat = 500
    static let minimo: CGFloat = 40
    /// Dalle pagine olografiche, di nuovo su: oltre 36 punti o 400 punti al secondo (JARVIS).
    static let diNuovoSu: CGFloat = 400

    var puo: () -> Bool = { false }                              // ci sono sezioni aperte e nessun altro gesto in corso
    var inizia: () -> Void = {}
    var segue: (CGFloat, CGFloat, CGFloat) -> Void = { _, _, _ in }   // su e di lato (punti) e velocità (punti/s, positiva in su)
    var finisce: (CGFloat, CGFloat) -> Void = { _, _ in }
    private weak var finestra: UIWindow?
    private var riconoscitore: UIPanGestureRecognizer?

    func installa() {
        guard riconoscitore == nil, let w = FasciaAlta.finestra else { return }
        let r = UIPanGestureRecognizer(target: self, action: #selector(scorre(_:)))
        r.maximumNumberOfTouches = 1
        r.delegate = self
        w.addGestureRecognizer(r)
        riconoscitore = r
        finestra = w
    }

    @objc private func scorre(_ r: UIPanGestureRecognizer) {
        let t = r.translation(in: finestra), v = r.velocity(in: finestra)
        switch r.state {
        case .began:
            inizia()
            segue(max(0, -t.y), t.x, -v.y)
        case .changed:
            segue(max(0, -t.y), t.x, -v.y)
        case .ended:
            finisce(max(0, -t.y), -v.y)
        case .cancelled, .failed:
            finisce(max(0, -t.y), 0)
        default: break
        }
    }

    /// Solo i tocchi che partono nella fascia, con le sezioni aperte e nessuna schermata di iOS sopra.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive tocco: UITouch) -> Bool {
        guard let w = finestra, w.rootViewController?.presentedViewController == nil, puo() else { return false }
        let fondo = w.bounds.height - w.safeAreaInsets.bottom
        let y = tocco.location(in: w).y
        return y <= fondo && y >= fondo - GestoBassoSezioni.alta
    }

    /// Solo verso l'alto (più in su che di lato).
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let p = g as? UIPanGestureRecognizer else { return false }
        let t = p.translation(in: finestra)
        return t.y < 0 && -t.y > abs(t.x)
    }

    /// Nella fascia, lo scorrimento della sezione aspetta: se lo swipe va in su è di JARVIS, altrimenti parte subito.
    /// I tocchi no: un pulsante nella fascia si preme come sempre.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy altro: UIGestureRecognizer) -> Bool {
        !(altro is UITapGestureRecognizer) && !(altro is UILongPressGestureRecognizer)
    }
}
