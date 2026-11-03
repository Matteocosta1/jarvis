import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - MARK XI · muoversi fra le sezioni aperte (mockup approvato dal signore il 3 nov), solo gesti, niente pillole né pallini
// · SWIPE SU dal basso (3 nov sera, «DEFINITIVA» del signore: «stesso funzionamento di Apple»), uguale al mockup. Parte poco sopra
//   il fondo (la fascia sopra la barretta di iOS: il bordo resta di iOS). La pagina resta attaccata al dito (il punto toccato resta
//   sotto il dito) e rimpicciolisce salendo, diventando ologramma (TiroPagina, 120 Hz).
//   - sollevata piano: quando il dito si ferma oltre il 28% dell'altezza, vibrazione e suono «caricaolo»; lasciata (anche senza
//     fermarsi, se è salita oltre il 28%) si ferma a metà pagina, scala 0,6: le pagine olografiche (SFOGLIO), da sfogliare a
//     destra e sinistra, col numero piccolo «2 / 3» in alto. Tocchi la pagina: si apre. La spingi in su: si chiude. Di nuovo su
//     dalla fascia: JARVIS;
//   - lanciata veloce: continua il lancio del dito e vola dentro il reattore (AGGANCIO: si inclina, la scansione la scioglie in
//     scintille, le staffe agganciano, il mirino scatta, il lampo e i due battiti sui colpi del suono «sparisce»); la sezione
//     resta aperta dietro;
//   - poco, o tirata giù prima di lasciarla: torna com'era.
//   Dopo il dito, molle con la sua velocità (come quelle di iOS).
// · swipe dai BORDI destro e sinistro: la sezione accanto nel cerchio delle aperte (con JARVIS fra l'ultima e la prima), con il
//   giro olografico della pagina.
// I Protocolli scendono dall'alto come sempre: qui non si tocca niente lassù.

final class NavigaSezioni: ObservableObject {
    enum Modo: Equatable { case normale, tira, aggancio, sfoglio, bordo }
    @Published var modo: Modo = .normale
    /// AGGANCIO: quando parte l'orologio degli effetti (quando si sente il suono) e il volo della pagina.
    @Published var aggancioDa: Date?
    @Published var volo: Volo?
    /// SFOGLIO: la posizione (in pagine, continua) e lo spostamento verticale della pagina al centro (su = negativo).
    @Published var P: Double = 0
    @Published var alzata: CGFloat = 0
    /// Le altre pagine olografiche, mentre si tira (0…1).
    @Published var rivela: Double = 0
    /// La pagina scelta che si sta materializzando.
    @Published var scelta: UUID?
    /// BORDO: di quanto (−1…1, negativo verso sinistra) e verso quale sezione (nil = JARVIS).
    @Published var bordo: CGFloat = 0
    @Published var verso: UUID?? = nil
    /// AGGANCIO: la sezione che vola nel reattore.
    @Published var agganciata: UUID?
    /// AGGANCIO: la sezione è già andata dietro (una sezione aperta intanto si vede e si tocca).
    @Published var dopoAggancio = false
    /// Su dal basso: la tirata è partita dalle pagine olografiche (o da JARVIS) e il suono delle pagine è già partito.
    var bassoDaSfoglio = false
    var suonoPagine = false
    /// Su dal basso fermo: la tendina PROTOCOLLI è aperta (o tirata), come nel mockup.
    var bassoFermo = false
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

/// La pagina in mano (al dito, alla molla o al volo): la posa viva, 120 volte al secondo. Lo legge solo questo modificatore.
struct SegueTiro: ViewModifier {
    @ObservedObject var tiro: TiroPagina
    let id: UUID
    func body(content: Content) -> some View {
        let v = tiro.pagina == id ? tiro.viva : TiroPagina.Viva()
        content
            .overlay { if v.tinta > 0.001 { VeloOlo().opacity(v.tinta) } }
            .clipShape(Ritaglio(raggio: v.raggio))
            .shadow(color: .ciano.opacity(v.ombra), radius: v.ombra > 0 ? 18 : 0)
            .scaleEffect(v.scala)
            .offset(x: v.x, y: v.y)
    }
}

struct StratoSezioniVista<Vista: View>: View {
    @ObservedObject var pila: PilaSezioni
    @ObservedObject var naviga: NavigaSezioni
    /// Dov'è il reattore (coordinate globali) e quanto è grande: lì vola la pagina dell'AGGANCIO.
    let reattore: CGPoint
    let diametroReattore: CGFloat
    let vista: (PilaSezioni.Voce) -> Vista
    let portaDavanti: (UUID?) -> Void
    let chiudiDietro: (UUID) -> Void

    @State private var P0: Double = 0
    @State private var assePagina: Int = 0           // 0 da decidere, 1 orizzontale (sfoglia), 2 verticale (alza)
    @State private var trackpad = TrackpadSezioni()  // sul Mac: due dita in orizzontale
    @State private var basso = GestoBassoSezioni()   // su dal basso, poco sopra la barretta di iOS
    @State private var tiro = TiroPagina()           // la pagina in mano, a 120 Hz

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
            // il fondo olografico (sfuma con l'opacità, senza entrare e uscire): nelle pagine prende tocchi e sfoglio anche fuori
            FondoVivo(tiro: tiro, tocca: naviga.modo == .sfoglio)
                .ignoresSafeArea()
            ForEach(pila.voci) { v in
                pagina(v)
            }
            if !carte.isEmpty && (naviga.modo == .sfoglio || (naviga.modo == .tira && naviga.rivela > 0.001)) {
                Text("\(quale(naviga.P) + 1) / \(carte.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(Color.tenue)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 54)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if naviga.modo == .aggancio, let da = naviga.aggancioDa, let volo = naviga.volo {
                LuceAggancio(inizio: da, reattore: reattore, volo: volo, altezza: altezza, larghezza: larghezza)
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
                .modifier(AggancioPagina(attivo: naviga.agganciata == v.id, inizio: naviga.aggancioDa))
                .modifier(SegueTiro(tiro: tiro, id: v.id))
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
            if tiro.pagina == v.id {
                p.z = 100                                             // la posa viva la dà SegueTiro
            } else if naviga.rivela > 0.001 {
                p = posaSfoglio(v)
                p.opacita *= naviga.rivela
            } else {
                p.opacita = 0
            }
        case .aggancio:
            if naviga.agganciata == v.id {
                p.z = 100                                             // il volo lo dà SegueTiro
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

    /// Le pagine olografiche, come nel mockup: a metà pagina (scala 0,6, centro al 48% dell'altezza), una alla volta in 3D (le
    /// accanto girate di 50° per pagina, indietro di 320 in prospettiva 1100, che si vedono sfogliando); spinta in su sfuma.
    private func posaSfoglio(_ v: PilaSezioni.Voce) -> Posa {
        var p = Posa()
        let k = carte.firstIndex(where: { $0.id == v.id }) ?? 0
        let o = scarto(k), a = abs(o), mat = naviga.scelta == v.id
        let centro = a < 0.5 && !mat
        p.scala = mat ? 1 : TiroPagina.sMeta * CGFloat(1100 / (1100 + min(a, 1.3) * 320))
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

    /// La pagina al centro delle pagine olografiche, come posa viva (per farla volare nel reattore).
    private var vivaCentro: TiroPagina.Viva {
        TiroPagina.Viva(x: 0, y: -altezza * 0.02 + naviga.alzata, scala: TiroPagina.sMeta, raggio: 28, tinta: 1, ombra: 0.45)
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

    // MARK: su dal basso

    private func preparaBasso() {
        Suoni.preparaPagine()
        basso.puo = {
            !pila.voci.isEmpty && !naviga.bassoFermo && !tiro.occupato && (naviga.modo == .normale || naviga.modo == .sfoglio)
        }
        basso.inizia = { punto in bassoInizia(punto) }
        basso.segue = { t, v in bassoSegue(t, v) }
        basso.finisce = { t, v in bassoFinisce(t, v) }
        tiro.aggancia = { paginePronte() }
        tiro.sgancia = { pagineVia() }
        basso.installa()
    }

    private func bassoInizia(_ punto: CGPoint) {
        naviga.bassoDaSfoglio = naviga.modo == .sfoglio
        naviga.suonoPagine = false
        guard naviga.modo == .normale else { return }
        var senza = Transaction(); senza.disablesAnimations = true
        if let d = pila.voceDavanti {                                     // da una sezione: la pagina al dito
            tiro.inizia(pagina: d.id, tocco: punto, larghezza: larghezza, altezza: altezza)
            withTransaction(senza) {
                naviga.P = Double(carte.firstIndex { $0.id == d.id } ?? 0)
                naviga.alzata = 0
                naviga.rivela = 0
                naviga.modo = .tira
            }
        } else {                                                          // da JARVIS: le pagine compaiono col dito
            withTransaction(senza) {
                naviga.P = 0
                naviga.alzata = 0
                naviga.rivela = 0
                naviga.modo = .tira
            }
        }
    }

    /// Il dito sale (`t`: lo spostamento, punti; `v`: la velocità, punti al secondo).
    private func bassoSegue(_ t: CGPoint, _ v: CGPoint) {
        guard !naviga.bassoDaSfoglio, naviga.modo == .tira else { return }
        if tiro.pagina != nil {
            tiro.segui(t, v)
            return
        }
        let q = Double(min(1, max(0, -t.y) / (altezza * 0.45)))
        naviga.rivela = min(1, q * 2.5)
        tiro.fondo = min(1, q * 2.2)
        if q > 0.1 && !naviga.suonoPagine { naviga.suonoPagine = true; Suoni.caricaOlo() }
    }

    private func bassoFinisce(_ t: CGPoint, _ v: CGPoint) {
        let daSfoglio = naviga.bassoDaSfoglio
        naviga.bassoDaSfoglio = false
        let su = -v.y, corsa = max(0, -t.y)
        if naviga.modo == .sfoglio {
            // dalle pagine, di nuovo su dalla fascia: JARVIS (la pagina al centro va nel reattore col lancio del dito)
            if daSfoglio && (corsa > 36 || su > 400) { tornaAJarvis(velocita: CGVector(dx: 0, dy: min(0, v.y) * 0.85)) }
            return
        }
        guard naviga.modo == .tira else { return }
        guard let id = tiro.pagina else {                                 // da JARVIS: le pagine restano, o se ne vanno
            if corsa / (altezza * 0.45) > 0.12 || su > 400 { entraSfoglio() } else { pagineSpente() }
            return
        }
        let agganciata = tiro.agganciata
        if su >= (agganciata ? TiroPagina.lancioVOlo : TiroPagina.lancioV) && corsa >= TiroPagina.lancioMin {
            let vp = tiro.velocitaPagina()                                // lanciata: continua il lancio dentro il reattore
            aggancio(id: id, base: tiro.viva, velocita: CGVector(dx: v.x * 0.85, dy: v.y * 0.85), scala: vp.s)
        } else if su > -TiroPagina.giuV && (agganciata || corsa >= altezza * TiroPagina.soglia) {
            formaSfoglio()                                                // sollevata piano: si ferma a metà pagina
        } else {
            tornaGiu()                                                    // poco, o tirata giù: torna com'era
        }
    }

    // MARK: le pagine olografiche

    /// Il dito si è fermato (o la pagina è stata lasciata piano): vibrazione, suono e le altre pagine, a tempo col suono.
    private func paginePronte() {
        guard naviga.modo == .tira, !naviga.suonoPagine else { return }
        naviga.suonoPagine = true
        let fra = min(Suoni.caricaOlo(), TempiAggancio.attesaMassima)
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.5).delay(fra)) { naviga.rivela = 1 }
    }

    /// Tornata giù prima di lasciarla: le pagine se ne vanno.
    private func pagineVia() {
        guard naviga.modo == .tira else { return }
        naviga.suonoPagine = false
        Suoni.zittisciOlo()
        withAnimation(.easeOut(duration: 0.15)) { naviga.rivela = 0 }
    }

    /// Sollevata piano e lasciata: la pagina si ferma a metà pagina con la velocità del dito (molla 0,42 s, smorzata 0,86).
    private func formaSfoglio() {
        if !tiro.agganciata { tiro.vibra(); paginePronte() }
        let id = tiro.pagina
        tiro.assesta(verso: vivaCentro, fondo: 1, risposta: 0.42, smorza: 0.86) {
            guard naviga.modo == .tira, tiro.pagina == id else { return }
            var senza = Transaction(); senza.disablesAnimations = true
            withTransaction(senza) {
                naviga.modo = .sfoglio
                naviga.rivela = 1
                tiro.rilascia(fondo: 1)
            }
        }
    }

    /// Poco, o tirata giù: la pagina torna com'era, con la velocità del dito (molla 0,36 s, smorzata 0,92).
    private func tornaGiu() {
        if tiro.agganciata { pagineVia() }
        let id = tiro.pagina
        tiro.assesta(verso: TiroPagina.Viva(), fondo: 0, risposta: 0.36, smorza: 0.92) {
            guard naviga.modo == .tira, tiro.pagina == id else { return }
            var senza = Transaction(); senza.disablesAnimations = true
            withTransaction(senza) {
                naviga.modo = .normale
                naviga.rivela = 0
                tiro.rilascia(fondo: 0)
            }
        }
    }

    /// Da JARVIS, lasciato il dito: le pagine già comparse col dito restano (0,2 s), come nel mockup.
    private func entraSfoglio() {
        guard !carte.isEmpty else { pagineSpente(); return }
        tiro.vibra()
        if !naviga.suonoPagine { naviga.suonoPagine = true; Suoni.caricaOlo() }
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.2)) {
            naviga.rivela = 1
            tiro.fondo = 1
            naviga.modo = .sfoglio
        }
    }

    /// Da JARVIS, lasciato subito: le pagine se ne vanno.
    private func pagineSpente() {
        Suoni.zittisciOlo()
        var senza = Transaction(); senza.disablesAnimations = true
        withTransaction(senza) {
            naviga.rivela = 0
            tiro.fondo = 0
            naviga.modo = .normale
        }
    }

    /// Dalle pagine, di nuovo su dalla fascia: la pagina al centro va nel reattore (AGGANCIO col suo suono) e torna JARVIS.
    private func tornaAJarvis(velocita: CGVector) {
        Suoni.zittisciOlo()
        let k = quale(naviga.P)
        guard carte.indices.contains(k) else {
            portaDavanti(nil)
            withAnimation(.easeOut(duration: 0.3)) { naviga.modo = .normale; naviga.alzata = 0; naviga.rivela = 0; tiro.fondo = 0 }
            return
        }
        let id = carte[k].id
        tiro.prendi(pagina: id, posa: vivaCentro, larghezza: larghezza, altezza: altezza)
        aggancio(id: id, base: vivaCentro, velocita: velocita, scala: 0)
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
                    // in su solo dalla pagina al centro (si chiude); altrimenti si sfoglia
                    let c = CGPoint(x: larghezza / 2, y: altezza / 2)
                    let sulCentro = abs(v.startLocation.x - c.x) < larghezza * 0.4 && abs(v.startLocation.y - c.y + altezza * 0.03) < altezza * 0.4
                    assePagina = abs(v.translation.width) >= abs(v.translation.height) || v.translation.height > 0 || !sulCentro ? 1 : 2
                    Suoni.zittisciOlo()
                }
                if assePagina == 1 {
                    var p = P0 - Double(v.translation.width / (larghezza * 0.75))
                    if !cerchio { p = max(-0.35, min(Double(carte.count) - 0.65, p)) }
                    naviga.P = p
                } else if assePagina == 2 {
                    naviga.alzata = min(0, v.translation.height)
                }
            }
            .onEnded { v in
                if assePagina == 0 {                                         // un tocco: sulla pagina al centro, si apre
                    let c = CGPoint(x: larghezza / 2, y: altezza / 2)
                    if abs(v.location.x - c.x) < larghezza * 0.4 && abs(v.location.y - c.y + altezza * 0.03) < altezza * 0.4 { scegli() }
                    return
                }
                if assePagina == 1 {
                    // come nel mockup: una pagina per volta, con lo slancio del dito (0,3 s), il tono «olo» quando cambia
                    let giro = P0.rounded(), vx = Double(v.velocity.width) / 1000
                    var meta = (naviga.P - vx * 180 / Double(larghezza * 0.75)).rounded()
                    meta = max(giro - 1, min(giro + 1, meta))
                    if !cerchio { meta = max(0, min(Double(carte.count - 1), meta)) }
                    withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.3)) { naviga.P = meta }
                    if meta != giro {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            Suoni.tonoOlo()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                } else if assePagina == 2 {
                    if naviga.alzata < -altezza * 0.16 || v.velocity.height < -600 { chiudiCarta() }   // come nel mockup
                    else { withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.2)) { naviga.alzata = 0 } }
                }
                assePagina = 0
            }
    }

    /// La pagina al centro si materializza a tutto schermo (0,32 s) e torna davanti; il click «scelta» quando arriva, come nel mockup.
    private func scegli() {
        let k = quale(naviga.P)
        guard carte.indices.contains(k) else { return }
        let v = carte[k]
        Suoni.zittisciOlo()
        if !v.sezione.conFotocamera { Suoni.sceltaPagina(fra: 0.32) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.32)) {
            naviga.scelta = v.id
            naviga.P = Double(k)
            tiro.fondo = 0.7
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { portaDavanti(v.id) }
            await Task.yield()                                        // la sezione è davanti: ora le pagine se ne vanno
            withTransaction(t) {
                naviga.modo = .normale
                naviga.scelta = nil
                naviga.alzata = 0
                naviga.rivela = 0
                tiro.fondo = 0
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
        withAnimation(.easeIn(duration: 0.22)) { naviga.alzata = -altezza * 0.9 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                naviga.alzata = 0
                chiudiDietro(id)
                if pila.voci.isEmpty {
                    naviga.modo = .normale
                    naviga.rivela = 0
                    tiro.fondo = 0
                } else {
                    naviga.P = Double(quale(naviga.P))
                }
            }
        }
    }

    // MARK: AGGANCIO (lo stile «mix» del mockup): la pagina continua il lancio e vola dentro il reattore

    /// `base`: dove sta la pagina; `velocita`: il lancio del dito (punti al secondo); `scala`: quanto stava rimpicciolendo (1/s).
    /// Il suono parte a un istante preciso; gli effetti partono quando si sente, la pagina subito (continua il dito) e arriva nel
    /// reattore all'aggancio (0,44 s dopo il suono: il colpo è a 0,466 s).
    private func aggancio(id: UUID, base: TiroPagina.Viva, velocita: CGVector, scala: CGFloat) {
        Suoni.zittisciOlo()
        let fra = min(Suoni.sparisce(), TempiAggancio.attesaMassima)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let verso = CGPoint(x: reattore.x - larghezza / 2, y: reattore.y - altezza / 2)
        let scalaReattore = max(0.08, min(0.25, diametroReattore * 0.5 / altezza))
        let volo = Volo.crea(da: base, velocita: velocita, scala: scala, verso: verso, scalaFinale: scalaReattore, ritardo: fra)
        var subito = Transaction(); subito.disablesAnimations = true
        withTransaction(subito) {
            naviga.volo = volo
            naviga.aggancioDa = Date().addingTimeInterval(fra)
            naviga.agganciata = id
            naviga.dopoAggancio = false
            naviga.modo = .aggancio
            naviga.rivela = 0
        }
        tiro.lancia(volo)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((fra + TempiAggancio.fase) * 1000)))
            var senza = Transaction(); senza.disablesAnimations = true
            withTransaction(senza) {
                portaDavanti(nil)                                         // la sezione va dietro (viva), davanti JARVIS
                naviga.dopoAggancio = true
            }
            try? await Task.sleep(for: .milliseconds(Int((TempiAggancio.fine - TempiAggancio.fase) * 1000)))
            guard naviga.modo == .aggancio, naviga.agganciata == id else { return }
            withTransaction(senza) {
                naviga.modo = .normale
                naviga.aggancioDa = nil
                naviga.volo = nil
                naviga.agganciata = nil
                naviga.dopoAggancio = false
                naviga.alzata = 0
                tiro.rilascia(fondo: 0)
            }
        }
    }

    // MARK: i bordi

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
}

/// I tempi dell'AGGANCIO, uguali nel mockup, a tempo col suono «sparisce» (misurato sul file: colpi a 0,466 e 1,002 s). L'animazione
/// anticipa i colpi di 10–20 ms: l'occhio la sente insieme al suono.
enum TempiAggancio {
    /// Fino a 0,44 s la pagina si inclina e si scioglie dal basso mentre vola; a 0,44 arriva nel reattore, le staffe agganciano e il
    /// mirino scatta.
    static let fase: Double = 0.44
    /// Il lampo nel reattore: da 0,43, pieno a 0,45, spento a 0,60.
    static let lampo: Double = 0.43
    /// I due battiti del reattore, sui due colpi del suono.
    static let battiti: [(Double, Double)] = [(0.455, 1), (0.99, 0.75)]
    static let fine: Double = 1.5
    /// Con cuffie Bluetooth lente l'animazione aspetta il suono al massimo 0,15 s (oltre, il gesto sembrerebbe lento).
    static let attesaMassima: Double = 0.15
}

/// Una molla smorzata come quelle di iOS (risposta e smorzamento): la distanza dalla meta nel tempo, partendo con una velocità.
struct Molla {
    let x0: Double, w: Double, z: Double, wd: Double, b: Double
    init(da x0: Double, velocita v0: Double, risposta: Double, smorza: Double) {
        let w = 2 * Double.pi / risposta, z = min(smorza, 0.999), wd = w * (1 - z * z).squareRoot()
        self.x0 = x0
        self.w = w
        self.z = z
        self.wd = wd
        self.b = (v0 + z * w * x0) / wd
    }
    func valore(_ t: Double) -> Double { exp(-z * w * t) * (x0 * cos(wd * t) + b * sin(wd * t)) }
}

/// Il volo dell'AGGANCIO: dalla posa lasciata dal dito al reattore (curva di Hermite: parte con la velocità del dito e arriva ferma
/// nel reattore all'aggancio; le tangenti sono limitate, così non rimbalza oltre il reattore). Uguale al mockup.
struct Volo {
    let p0: CGPoint, m0: CGVector, p1: CGPoint
    let s0: CGFloat, ms0: CGFloat, s1: CGFloat
    /// Fino all'aggancio (0,44 s dopo il suono) e il ritardo del suono (l'orologio degli effetti parte dopo).
    let durata: Double, ritardo: Double

    static func crea(da base: TiroPagina.Viva, velocita v: CGVector, scala vs: CGFloat, verso p1: CGPoint, scalaFinale s1: CGFloat,
                     ritardo: Double) -> Volo {
        let durata = TempiAggancio.fase + ritardo
        func tangente(_ d: CGFloat, _ m: CGFloat, _ piccolo: CGFloat) -> CGFloat {
            abs(d) < piccolo ? max(-piccolo * 3, min(piccolo * 3, m)) : d * max(-0.5, min(2.5, m / d))
        }
        return Volo(p0: CGPoint(x: base.x, y: base.y),
                    m0: CGVector(dx: tangente(p1.x - base.x, v.dx * durata, 50), dy: tangente(p1.y - base.y, v.dy * durata, 50)),
                    p1: p1, s0: base.scala, ms0: tangente(s1 - base.scala, vs * durata, 0.05), s1: s1,
                    durata: durata, ritardo: ritardo)
    }

    /// Dove sta la pagina dopo `tau` secondi dal lancio: lo spostamento dal centro dello schermo e la scala.
    func stato(_ tau: Double) -> (x: CGFloat, y: CGFloat, scala: CGFloat) {
        let u = CGFloat(max(0, min(1, tau / durata)))
        let h00 = 2 * u * u * u - 3 * u * u + 1, h10 = u * u * u - 2 * u * u + u, h01 = -2 * u * u * u + 3 * u * u
        return (x: h00 * p0.x + h10 * m0.dx + h01 * p1.x,
                y: h00 * p0.y + h10 * m0.dy + h01 * p1.y,
                scala: max(0.02, h00 * s0 + h10 * ms0 + h01 * s1))
    }

    /// Dove sta la pagina sullo schermo all'istante `t` dell'orologio degli effetti (inclinata indietro fino a 42°).
    func rettangolo(_ t: Double, larghezza: CGFloat, altezza: CGFloat) -> CGRect {
        let st = stato(t + ritardo), e = AggancioPagina.curva(min(1, max(0, t) / TempiAggancio.fase))
        let w = larghezza * st.scala, h = altezza * st.scala * CGFloat(cos(42 * e * .pi / 180))
        let cx = larghezza / 2 + st.x, cy = altezza / 2 + st.y
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
}

/// MARK XI · la pagina in mano durante lo swipe su (3 nov sera, «DEFINITIVA» del signore: «stesso funzionamento di Apple»).
/// Il punto toccato resta sotto il dito e la pagina rimpicciolisce salendo (0,88 a 50 punti, 0,78 a 100, 0,59 a 250, verso 0,38);
/// il dito che si ferma oltre il 28% dell'altezza (sotto i 140 punti al secondo per 60 ms, anche senza più movimenti) fa comparire
/// le pagine olografiche, con la vibrazione. Lasciata: molle con la velocità del dito, o il volo nel reattore. Un CADisplayLink a
/// 120 Hz pubblica la posa viva: la leggono solo `SegueTiro` e il fondo. Le misure sono le stesse del mockup.
final class TiroPagina: NSObject, ObservableObject {
    struct Viva {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scala: CGFloat = 1
        var raggio: CGFloat = 0
        var tinta: Double = 0
        var ombra: Double = 0
    }

    // le misure (uguali al mockup)
    static let sMeta: CGFloat = 0.6                    // la pagina olografica a metà pagina
    static let soglia: CGFloat = 0.28                  // le pagine: oltre il 28% dell'altezza
    static let pausaV: CGFloat = 140                   // fermo: sotto 140 punti al secondo…
    static let pausaT: Double = 0.06                   // …per 60 ms
    static let lancioV: CGFloat = 550                  // lanciata: oltre 550 punti al secondo…
    static let lancioVOlo: CGFloat = 750               // …750 se le pagine sono già comparse
    static let lancioMin: CGFloat = 24                 // dopo almeno 24 punti
    static let giuV: CGFloat = 350                     // tirata giù: oltre 350 punti al secondo, torna com'era

    @Published private(set) var viva = Viva()
    @Published var fondo: Double = 0
    @Published private(set) var pagina: UUID?

    /// Le pagine olografiche ci sono (il dito si è fermato) / tornata giù prima di lasciarla.
    var aggancia: () -> Void = {}
    var sgancia: () -> Void = {}
    private(set) var agganciata = false
    /// Una molla o un volo in corso: un nuovo swipe aspetta.
    var occupato: Bool { fase == .molla || fase == .volo }

    private enum Fase { case ferma, dito, molla, volo }
    private struct MollaPosa {
        let x: Molla, y: Molla, s: Molla
        let da: Viva, a: Viva
        let f0: Double, f1: Double
        let t0: CFTimeInterval, risposta: Double
    }
    private var fase: Fase = .ferma
    private var larghezza: CGFloat = 393, altezza: CGFloat = 852
    private var tocco: CGPoint = .zero
    private var corsa: CGFloat = 0
    private var dx: CGFloat = 0
    private var velDito: CGVector = .zero
    private var ultimoMoto: CFTimeInterval = 0
    private var lentoDa: CFTimeInterval?
    private var molla: MollaPosa?
    private var fineMolla: (() -> Void)?
    private var volo: Volo?
    private var t0Volo: CFTimeInterval = 0
    private var baseVolo = Viva()
    private var f0Volo: Double = 0
    private var collegamento: CADisplayLink?
    private let vibrazione = UIImpactFeedbackGenerator(style: .medium)

    static func scala(_ t: CGFloat) -> CGFloat { 1 - 0.62 * (1 - exp(-t / 230)) }
    static func dScala(_ t: CGFloat) -> CGFloat { -0.62 / 230 * exp(-t / 230) }

    // MARK: il dito

    func inizia(pagina id: UUID, tocco p: CGPoint, larghezza w: CGFloat, altezza h: CGFloat) {
        pagina = id
        tocco = p
        larghezza = w
        altezza = h
        corsa = 0
        dx = 0
        velDito = .zero
        agganciata = false
        lentoDa = nil
        ultimoMoto = CACurrentMediaTime()
        molla = nil
        volo = nil
        viva = Viva()
        fase = .dito
        vibrazione.prepare()
        avvia()
    }

    /// Prende una pagina già ferma (la pagina al centro delle pagine olografiche), per farla volare.
    func prendi(pagina id: UUID, posa: Viva, larghezza w: CGFloat, altezza h: CGFloat) {
        pagina = id
        larghezza = w
        altezza = h
        viva = posa
        fase = .ferma
    }

    func segui(_ t: CGPoint, _ v: CGPoint) {
        guard fase == .dito else { return }
        let nuova = max(0, -t.y)
        if abs(nuova - corsa) > 0.5 || abs(t.x - dx) > 0.5 { ultimoMoto = CACurrentMediaTime() }
        corsa = nuova
        dx = t.x
        velDito = CGVector(dx: v.x, dy: v.y)
        viva = posaDito()
        fondo = min(1, Double(corsa / (altezza * 0.45)) * 2.2)
    }

    /// Il punto toccato resta sotto il dito; il tono olografico cresce nei primi 120 punti.
    private func posaDito() -> Viva {
        let s = TiroPagina.scala(corsa), ax = tocco.x - larghezza / 2, ay = tocco.y - altezza / 2, q = Double(min(1, corsa / 120))
        return Viva(x: dx + ax * (1 - s), y: -corsa + ay * (1 - s), scala: s, raggio: 28 * min(1, corsa / 40),
                    tinta: q, ombra: 0.45 * Double(min(1, corsa / 40)))
    }

    /// La velocità della pagina attaccata al dito (punti al secondo; la scala: al secondo).
    func velocitaPagina() -> (x: CGFloat, y: CGFloat, s: CGFloat) {
        guard corsa > 0 else { return (x: velDito.dx, y: 0, s: 0) }
        let vs = TiroPagina.dScala(corsa) * -velDito.dy
        return (x: velDito.dx - (tocco.x - larghezza / 2) * vs, y: velDito.dy - (tocco.y - altezza / 2) * vs, s: vs)
    }

    func vibra() { vibrazione.impactOccurred() }

    // MARK: dopo il dito

    /// La pagina va a `meta` con la velocità del dito; il fondo verso `fondo`. Alla fine `fine`.
    func assesta(verso meta: Viva, fondo f1: Double, risposta: Double, smorza: Double, fine: @escaping () -> Void) {
        let v = fase == .dito ? velocitaPagina() : (x: CGFloat(0), y: CGFloat(0), s: CGFloat(0))
        molla = MollaPosa(x: Molla(da: Double(viva.x - meta.x), velocita: Double(v.x), risposta: risposta, smorza: smorza),
                          y: Molla(da: Double(viva.y - meta.y), velocita: Double(v.y), risposta: risposta, smorza: smorza),
                          s: Molla(da: Double(viva.scala - meta.scala), velocita: Double(v.s), risposta: risposta, smorza: smorza),
                          da: viva, a: meta, f0: fondo, f1: f1, t0: CACurrentMediaTime(), risposta: risposta)
        fineMolla = fine
        fase = .molla
        avvia()
    }

    /// Il volo nel reattore (la pagina continua il lancio).
    func lancia(_ v: Volo) {
        volo = v
        t0Volo = CACurrentMediaTime()
        baseVolo = viva
        f0Volo = fondo
        fase = .volo
        avvia()
    }

    /// La pagina torna alla sua posa (la dà di nuovo PosaPagina).
    func rilascia(fondo f: Double) {
        pagina = nil
        fase = .ferma
        molla = nil
        fineMolla = nil
        volo = nil
        agganciata = false
        lentoDa = nil
        viva = Viva()
        fondo = f
        ferma()
    }

    // MARK: 120 Hz

    private func avvia() {
        guard collegamento == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(passo(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        collegamento = l
    }

    private func ferma() {
        collegamento?.invalidate()
        collegamento = nil
    }

    @objc private func passo(_ l: CADisplayLink) {
        let ora = CACurrentMediaTime()
        switch fase {
        case .dito:
            // il dito che si ferma, anche senza più movimenti (fermo da 70 ms = velocità zero)
            let vel = ora - ultimoMoto > 0.07 ? 0 : hypot(velDito.dx, velDito.dy)
            if !agganciata {
                if corsa >= altezza * TiroPagina.soglia && vel <= TiroPagina.pausaV {
                    if let d = lentoDa {
                        if ora - d >= TiroPagina.pausaT {
                            agganciata = true
                            lentoDa = nil
                            vibrazione.impactOccurred()
                            aggancia()
                        }
                    } else {
                        lentoDa = ora
                    }
                } else {
                    lentoDa = nil
                }
            } else if corsa < altezza * TiroPagina.soglia * 0.6 {
                agganciata = false
                sgancia()
            }
        case .molla:
            guard let m = molla else { fase = .ferma; return }
            let t = ora - m.t0, p = min(1, 1 - exp(-t / (m.risposta * 0.3)))
            viva = Viva(x: m.a.x + CGFloat(m.x.valore(t)), y: m.a.y + CGFloat(m.y.valore(t)), scala: m.a.scala + CGFloat(m.s.valore(t)),
                        raggio: m.da.raggio + (m.a.raggio - m.da.raggio) * CGFloat(p),
                        tinta: m.da.tinta + (m.a.tinta - m.da.tinta) * p,
                        ombra: m.da.ombra + (m.a.ombra - m.da.ombra) * p)
            fondo = m.f0 + (m.f1 - m.f0) * p
            if t >= m.risposta * 1.5 {
                viva = m.a
                fondo = m.f1
                molla = nil
                fase = .ferma
                ferma()
                let f = fineMolla
                fineMolla = nil
                f?()
            }
        case .volo:
            guard let v = volo else { fase = .ferma; return }
            let tau = ora - t0Volo, st = v.stato(tau)
            viva = Viva(x: st.x, y: st.y, scala: st.scala, raggio: baseVolo.raggio, tinta: baseVolo.tinta, ombra: baseVolo.ombra)
            fondo = f0Volo * (1 - AggancioPagina.curva(max(0, min(1, (tau - v.ritardo) / TempiAggancio.fase))))
            if tau >= v.durata + 0.05 { ferma() }
        case .ferma:
            ferma()
        }
    }
}

/// AGGANCIO, la pagina: si inclina indietro (fino a 42°) mentre la riga di scansione la percorre dal basso in alto e se la porta
/// via (0–0,44 s dell'orologio degli effetti, curva «ease in-out»), come nel mockup. Il volo lo dà `SegueTiro`.
struct AggancioPagina: ViewModifier {
    let attivo: Bool
    let inizio: Date?

    /// «ease in-out» quadratica (la stessa del mockup).
    nonisolated static func curva(_ a: Double) -> Double { a < 0.5 ? 2 * a * a : 1 - pow(-2 * a + 2, 2) / 2 }   // solo calcolo

    // sempre dentro lo stesso TimelineView (fermo quando non serve): la sezione non viene mai ricreata
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !attivo)) { ctx in
            let dt = attivo ? max(0, ctx.date.timeIntervalSince(inizio ?? ctx.date)) : 0
            let e = AggancioPagina.curva(min(1, dt / TempiAggancio.fase))
            let yy = 1.02 - e * 1.06                                   // la riga: dal 102% (sotto) al −4% (sopra la cima)
            content
                .overlay(alignment: .top) {
                    GeometryReader { g in
                        ZStack(alignment: .bottom) {
                            LinearGradient(colors: [Color.ciano.opacity(0), Color.ciano.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 70)
                            Rectangle()
                                .fill(Color(red: 0.875, green: 0.98, blue: 1))
                                .frame(height: 2)
                                .shadow(color: .ciano, radius: 5)
                                .shadow(color: .ciano.opacity(0.85), radius: 13)
                        }
                        .frame(height: 72)
                        .offset(y: g.size.height * yy - 72)
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
        }
    }
}

/// AGGANCIO, la luce (lo stile «mix» del mockup, stessi numeri): le staffe inquadrano la pagina in volo e all'aggancio (0,44 s) si
/// chiudono sul reattore; le scintille nascono sulla riga di scansione (950 al secondo) e corrono nel reattore; il mirino a tre
/// anelli si stringe, scatta all'aggancio e gira; il lampo (pieno a 0,45 s) e i due battiti (0,455 e 0,99 s) sui colpi del suono;
/// tutto si spegne a 1,5 s. Un orologio solo, a 120 Hz.
struct LuceAggancio: View {
    let inizio: Date
    let reattore: CGPoint
    let volo: Volo
    let altezza: CGFloat
    let larghezza: CGFloat
    @State private var scintille: [Scintilla]

    struct Scintilla {
        let x0: Double, y0: Double, t0: Double, dur: Double, cx: Double, cy: Double, s: Double
    }

    init(inizio: Date, reattore: CGPoint, volo: Volo, altezza: CGFloat, larghezza: CGFloat) {
        self.inizio = inizio
        self.reattore = reattore
        self.volo = volo
        self.altezza = altezza
        self.larghezza = larghezza
        _scintille = State(initialValue: LuceAggancio.genera(volo: volo, altezza: altezza, larghezza: larghezza))
    }

    /// Le scintille, tutte prima (come le nasce il mockup fotogramma per fotogramma): sulla riga di scansione di quell'istante.
    static func genera(volo: Volo, altezza: CGFloat, larghezza: CGFloat) -> [Scintilla] {
        let F = TempiAggancio.fase, n = Int(950 * F)
        return (0..<n).map { i in
            let t0 = F * (Double(i) + Double.random(in: 0..<1)) / Double(n)
            let r = volo.rettangolo(t0, larghezza: larghezza, altezza: altezza)
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
        let F = TempiAggancio.fase, R = reattore

        // le staffe: inquadrano la pagina in volo fino all'aggancio, poi si chiudono sul reattore (0,44–0,54 s) e si spengono (0,62)
        var riquadro: CGRect?
        var alS = 0.0
        if t < F {
            riquadro = volo.rettangolo(t, larghezza: larghezza, altezza: altezza)
            alS = min(1, t / 0.08)
        } else if t < F + 0.18 {
            let b0 = volo.rettangolo(F, larghezza: larghezza, altezza: altezza)
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

        // il mirino sul reattore: si stringe mentre la pagina vola, scatta all'aggancio, poi gira e si spegne
        let stringe = t < F ? 1.9 - 0.9 * AggancioPagina.curva(t / F) : (t < F + 0.08 ? 1 - 0.12 * sin((t - F) / 0.08 * .pi) : 1)
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

/// Il fondo olografico che segue la pagina in mano (lo legge solo lui, 120 volte al secondo).
struct FondoVivo: View {
    @ObservedObject var tiro: TiroPagina
    let tocca: Bool
    var body: some View {
        FondoOlo()
            .opacity(tiro.fondo)
            .allowsHitTesting(tocca)
            .accessibilityHidden(true)
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
/// sicuro in basso; sul Mac e sugli iPhone col tasto Home, dal fondo), alta 56 punti e larga quanto lo schermo. Il bordo resta di iOS:
/// si esce dall'app al primo swipe, sempre.
/// Il riconoscitore sta sulla finestra e sente solo i tocchi che partono nella fascia. Prende solo lo swipe verso l'alto: un tocco,
/// lo scorrere in orizzontale o verso il basso restano della sezione. Quando lo prende, ha la precedenza sullo scorrimento della
/// sezione sotto (che così non si muove insieme). Spento con una schermata di iOS sopra (Safari, foto, aiuto).
final class GestoBassoSezioni: NSObject, UIGestureRecognizerDelegate {
    /// La fascia: 56 punti sopra la zona di iOS (su iPhone 15 Pro: dai 34 ai 90 punti dal fondo).
    static let alta: CGFloat = 56

    var puo: () -> Bool = { false }                              // ci sono sezioni aperte e nessun altro gesto in corso
    var inizia: (CGPoint) -> Void = { _ in }                     // dove ha toccato (nella finestra)
    var segue: (CGPoint, CGPoint) -> Void = { _, _ in }          // lo spostamento e la velocità (punti, punti al secondo)
    var finisce: (CGPoint, CGPoint) -> Void = { _, _ in }
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
            let p = r.location(in: finestra)
            inizia(CGPoint(x: p.x - t.x, y: p.y - t.y))
            segue(t, v)
        case .changed:
            segue(t, v)
        case .ended:
            finisce(t, v)
        case .cancelled, .failed:
            finisce(t, .zero)
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
