import Foundation
import SwiftUI
import Combine
import UIKit

// MARK: - MARK XI · muoversi fra le sezioni aperte (mockup approvato dal signore il 3 nov), solo gesti, niente pillole né pallini
// · SWIPE SU dal basso (3 nov sera, «DEFINITIVA» del signore: «stesso funzionamento di Apple»), uguale al mockup. Parte poco sopra
//   il fondo (la fascia sopra la barretta di iOS: il bordo resta di iOS). La pagina resta attaccata al dito (il punto toccato resta
//   sotto il dito) e rimpicciolisce salendo, diventando ologramma (TiroPagina, 120 Hz).
//   - sollevata piano: quando il dito si ferma oltre il 28% dell'altezza, vibrazione e suono «caricaolo»; lasciata (anche senza
//     fermarsi, se è salita oltre il 28%) si ferma a metà pagina, scala 0,78: le pagine olografiche (SFOGLIO), da sfogliare a
//     destra e sinistra, col numero piccolo «2 / 3» in alto. Tocchi la pagina: si apre. La spingi in su: si chiude. Di nuovo su
//     dalla fascia: JARVIS;
//   - lanciata veloce: continua il lancio del dito e vola dentro il reattore (AGGANCIO = ORIGINE · AGGANCIO II, 4 nov notte: il
//     reattore si apre, la pagina si inclina e diventa luce, il laser la scioglie in scintille a vortice, le staffe agganciano, il
//     mirino scatta, il lampo e i battiti sui colpi del suono «sparisce», tutto spento a 1,1 s); la sezione resta aperta dietro;
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
    /// 5 nov (il signore: «manca l'animazione quando li seleziono, come nel mockup»): la sezione appena tornata davanti dalle
    /// pagine olografiche (o dal bordo) che si materializza: la riga di scansione che scende e le staffe agli angoli.
    @Published var materia: UUID?
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
    /// 4 nov: chiesto a voce (ContentView), lo fa il contenitore come col dito: le pagine olografiche («sezioni aperte»), l'AGGANCIO
    /// («mettila da parte»), una sezione che torna davanti («quella di prima»).
    enum Chiesta: Equatable { case sfoglio, aggancio, porta(UUID) }
    @Published var chiesta: Chiesta?
    /// 5 nov (video del signore: «l'animazione dell'aggancio sale troppo in alto»): dov'è il reattore (coordinate globali) e
    /// quanto è grande, sempre aggiornati qui. Lo swipe su dal basso chiama l'aggancio da chiusure preparate al primo disegno
    /// (GestoBassoSezioni), che si portavano dietro il reattore di allora: (0, 0), non ancora misurato. La pagina volava
    /// nell'angolo in alto a sinistra invece che nel reattore (la luce, disegnata dalla vista, era invece al posto giusto).
    var reattore: CGPoint = .zero
    var diametroReattore: CGFloat = 290
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
    /// Studio, Social o Browser: il ciano lo mette la pagina web stessa (OloWeb).
    var web = false
    func body(content: Content) -> some View {
        content
            .environment(\.tintaOlo, TiroPagina.passoOlo(posa.tinta))
            .allowsHitTesting(posa.tocchi)
            .overlay { if posa.tinta > 0.001 { VeloOlo(forza: posa.tinta, web: web) } }
            .clipShape(Ritaglio(raggio: posa.raggio))
            // 5 nov (il signore: «le pagine da sfogliare non sono trasparenti e cool come nel mockup»): come .foglio.ologramma del
            // mockup, la pagina diventa luce (mix-blend-mode: screen): il nero si fonde col fondo olografico e resta il disegno ciano
            .blendMode(posa.tinta > 0.001 ? .screen : .normal)
            // 5 nov pomeriggio (il signore, foto: «più trasparenti, che si veda il sotto, IDENTICI al mockup; nell'app sono troppo
            // luminosi»): sull'iPhone la fusione «screen» non passa fuori dalla pagina girata in 3D (la pagina restava piena).
            // Come nel mockup la pagina olografica lascia vedere il fondo e la griglia: è luce, metà trasparente.
            .opacity(1 - TiroPagina.trasparenza * posa.tinta)
            .modifier(AloneOlo(forza: posa.ombra, alfa: 1 - TiroPagina.trasparenza * posa.tinta))
            .scaleEffect(posa.scala)
            .rotation3DEffect(.degrees(posa.rotY), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .offset(x: posa.x, y: posa.y)
            .opacity(posa.opacita)
            .accessibilityHidden(!posa.tocchi)
            .zIndex(posa.z)
    }
}

/// La pagina in mano (al dito, alla molla o al volo): la posa viva, 120 volte al secondo. Lo legge solo questo modificatore.
/// Nell'AGGANCIO (ORIGINE · AGGANCIO II) la pagina si inclina all'indietro con la prospettiva del mockup e il laser la scioglie dal
/// basso: maschera e inclinazione stanno qui, nello stesso fotogramma del volo (un orologio solo).
struct SegueTiro: ViewModifier {
    @ObservedObject var tiro: TiroPagina
    let id: UUID
    /// Studio, Social o Browser: il ciano lo mette la pagina web stessa (OloWeb).
    var web = false
    /// La tinta data dalla posa (PosaPagina, fuori): alla pagina va la più forte delle due.
    @Environment(\.tintaOlo) private var tintaPosa
    func body(content: Content) -> some View {
        let v = tiro.pagina == id ? tiro.viva : TiroPagina.Viva()
        content
            .environment(\.tintaOlo, max(tintaPosa, TiroPagina.passoOlo(v.tinta)))
            .overlay { if v.tinta > 0.001 { VeloOlo(forza: v.tinta, web: web) } }
            .clipShape(Ritaglio(raggio: v.raggio))
            .blendMode(v.tinta > 0.001 ? .screen : .normal)             // 5 nov: la pagina in mano è luce, come nel mockup
            .opacity(1 - TiroPagina.trasparenza * v.tinta)               // e lascia vedere il fondo, come nel mockup
            .modifier(AloneOlo(forza: v.ombra, alfa: 1 - TiroPagina.trasparenza * v.tinta))
            .mask { MascheraLaser(riga: v.riga) }
            .modifier(Proiezione(x: v.x, y: v.y, scala: v.scala, inclina: v.inclina))
    }
}

/// Dove sta la pagina, come il `transform` del mockup: `perspective(1100px) translate(x, y) rotateX(inclina) scale(scala)` dal centro
/// della pagina. Senza inclinazione è esattamente scala + spostamento (come `scaleEffect` e `offset` di prima).
nonisolated struct Proiezione: GeometryEffect {
    var x: CGFloat
    var y: CGFloat
    var scala: CGFloat
    var inclina: Double                                   // gradi: la cima va indietro (come rotateX del mockup)
    static let distanza: CGFloat = 1100                   // la prospettiva del mockup

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, Double>> {
        get { AnimatablePair(AnimatablePair(x, y), AnimatablePair(scala, inclina)) }
        set { x = newValue.first.first; y = newValue.first.second; scala = newValue.second.first; inclina = newValue.second.second }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let w = size.width, h = size.height, s = scala, a = inclina * .pi / 180
        let ca = CGFloat(cos(a)), sa = CGFloat(sin(a)), d = Proiezione.distanza
        // un punto (px, py) della pagina: X = s(px − w/2), Y = s(py − h/2); ruotato: Y·cos, profondità Y·sin; poi 1100 / (1100 − z)
        let m23 = -(s * sa) / d, m33 = 1 + (s * sa / d) * (h / 2)
        var t = ProjectionTransform()
        t.m11 = s
        t.m12 = 0
        t.m13 = 0
        t.m21 = (w / 2) * m23
        t.m22 = (h / 2) * m23 + s * ca
        t.m23 = m23
        t.m31 = (w / 2) * m33 - s * (w / 2) + x
        t.m32 = (h / 2) * m33 - s * ca * (h / 2) + y
        t.m33 = m33
        return t
    }
}

/// La maschera del laser sulla pagina, come nel mockup: piena fino al 3% sopra la riga, trasparente dall'1% sotto.
/// `riga` va da 0 (cima) a 1 (fondo); da 1,015 in su non taglia niente.
struct MascheraLaser: View {
    let riga: Double
    var body: some View {
        if riga >= 1.015 {
            Rectangle().padding(-3000)                        // fermo: non taglia niente (nemmeno l'ombra)
        } else {
            let a = riga - 0.03, b = riga + 0.01
            let p0 = max(0, min(1, a)), p1 = max(0, min(1, b))
            LinearGradient(stops: [.init(color: .black.opacity(MascheraLaser.pieno(0, a, b)), location: 0),
                                   .init(color: .black.opacity(MascheraLaser.pieno(p0, a, b)), location: p0),
                                   .init(color: .black.opacity(MascheraLaser.pieno(p1, a, b)), location: p1),
                                   .init(color: .black.opacity(MascheraLaser.pieno(1, a, b)), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    /// Quanto è piena la maschera al punto `v` (1 sopra `a`, 0 sotto `b`, in mezzo in linea retta, come il gradiente del mockup).
    nonisolated static func pieno(_ v: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (b - v) / (b - a))) }
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
    @State private var telai: [UUID: CGRect] = [:]   // dove sta ogni pagina a riposo (coordinate globali)

    private var altezza: CGFloat { FasciaAlta.finestra?.bounds.height ?? 852 }
    private var larghezza: CGFloat { FasciaAlta.finestra?.bounds.width ?? 393 }

    /// Dove sta la pagina `id` a riposo (coordinate globali); se non è ancora misurata, tutto lo schermo.
    private func telaio(_ id: UUID) -> CGRect {
        if let r = telai[id], r.width > 1, r.height > 1 { return r }
        return CGRect(x: 0, y: 0, width: larghezza, height: altezza)
    }

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
            if naviga.modo == .aggancio, let da = naviga.aggancioDa, let volo = naviga.volo, let id = naviga.agganciata {
                // sopra la pagina che vola (come la tela del mockup): laser, scintille, staffe e mirino le stanno davanti
                LuceAggancio(orologio: tiro.orologio, reattore: reattore, volo: volo, telaio: telaio(id))
                    .id(da)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(150)
            }
            bordi
        }
        .gesture(gestoSfoglio, including: naviga.modo == .sfoglio ? .all : .subviews)
        .onAppear { preparaTrackpad(); preparaBasso() }
        .onChange(of: reattore, initial: true) { _, r in naviga.reattore = r }
        .onChange(of: diametroReattore, initial: true) { _, d in naviga.diametroReattore = d }
        .onChange(of: pila.voci.isEmpty) { _, vuota in
            basso.installa()                                              // se all'avvio la finestra non c'era ancora
            // tutte chiuse a voce («Jarvis, chiudi tutto») con le pagine olografiche aperte: si torna a JARVIS
            if vuota, naviga.modo == .sfoglio {
                Suoni.zittisciOlo()
                withAnimation(.easeOut(duration: 0.3)) { naviga.modo = .normale; naviga.alzata = 0; naviga.rivela = 0; tiro.fondo = 0 }
            }
        }
        .onChange(of: naviga.chiesta) { _, c in
            guard let c else { return }
            naviga.chiesta = nil
            switch c {
            case .sfoglio: sfoglioAVoce()
            case .aggancio: aggancioAVoce()
            case .porta(let id): portaAVoce(id)
            }
        }
    }

    // MARK: a voce (4 nov, approvati dal signore): le stesse animazioni del dito

    /// «Jarvis, sezioni aperte»: da una sezione la pagina si solleva e si ferma a metà (la vibrazione, il suono e le altre pagine,
    /// come sollevata piano col dito); da JARVIS le pagine compaiono. Già aperte: restano.
    private func sfoglioAVoce() {
        guard naviga.modo == .normale, !tiro.occupato, !carte.isEmpty else { return }
        naviga.suonoPagine = false
        naviga.bassoDaSfoglio = false
        var senza = Transaction(); senza.disablesAnimations = true
        if let d = pila.voceDavanti {
            tiro.prendi(pagina: d.id, posa: TiroPagina.Viva(), larghezza: larghezza, altezza: altezza)
            withTransaction(senza) {
                naviga.P = Double(carte.firstIndex { $0.id == d.id } ?? 0)
                naviga.alzata = 0
                naviga.rivela = 0
                naviga.modo = .tira
            }
            formaSfoglio()
        } else {
            withTransaction(senza) {
                naviga.P = 0
                naviga.alzata = 0
                naviga.rivela = 0
                naviga.modo = .tira
            }
            entraSfoglio()
        }
    }

    /// «Jarvis, mettila da parte»: la sezione davanti vola nel reattore come lanciata col dito (AGGANCIO) e resta dietro, viva.
    /// Dalle pagine olografiche: quella al centro, come lo swipe su dalla fascia.
    private func aggancioAVoce() {
        guard !tiro.occupato else { return }
        if naviga.modo == .sfoglio { tornaAJarvis(velocita: TiroPagina.lancioVoce); return }
        guard naviga.modo == .normale, let d = pila.voceDavanti else { return }
        tiro.prendi(pagina: d.id, posa: TiroPagina.Viva(), larghezza: larghezza, altezza: altezza)
        aggancio(id: d.id, base: TiroPagina.Viva(), velocita: TiroPagina.lancioVoce, scala: TiroPagina.lancioVoceScala, olo: true)
    }

    /// «Jarvis, quella di prima»: la sezione torna davanti. Dalle pagine olografiche girano fino a lei e si apre, come toccata;
    /// altrimenti sale come ogni sezione che torna davanti. Con il dito in mezzo a un gesto, vince il dito.
    private func portaAVoce(_ id: UUID) {
        switch naviga.modo {
        case .sfoglio:
            guard let k = carte.firstIndex(where: { $0.id == id }) else { return }
            let o = scarto(k)
            if abs(o) < 0.01 { scegli(); return }
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.3)) { naviga.P += o }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                let q = quale(naviga.P)
                guard naviga.modo == .sfoglio, carte.indices.contains(q), carte[q].id == id else { return }
                scegli()
            }
        case .normale:
            portaDavanti(id)
        default:
            break
        }
    }

    // MARK: le pagine
    // La vista della sezione sta sempre nello stesso posto (cambiano solo i valori di posa): così passando da un modo all'altro
    // SwiftUI non la ricrea e la sezione resta viva, con i suoi dati.

    @ViewBuilder private func pagina(_ v: PilaSezioni.Voce) -> some View {
        let p = posa(v)
        let web = v.sezione.paginaWeb
        vista(v)
                .environment(\.sezioneAperta, v.id)
                .environment(\.sezioneDietro, pila.davanti != v.id)        // dietro: fotocamera e microfono in pausa
                .environment(\.jarvisCoperto, false)
                .environment(\.materiaOlo, naviga.materia == v.id)        // le pagine web si materializzano anche dentro (OloWeb)
                .overlay { if naviga.materia == v.id { MaterializzaOlo(web: web) { if naviga.materia == v.id { naviga.materia = nil } } } }
                .modifier(SegueTiro(tiro: tiro, id: v.id, web: web))
                .modifier(PosaPagina(posa: p, web: web))
                // dove sta la pagina a riposo (coordinate globali): da lì parte il volo dell'AGGANCIO e lì si posa la sua luce
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { telai[v.id] = $0 }
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

    /// Le pagine olografiche, come nel mockup: a metà pagina (scala 0,78, centro al 48% dell'altezza), una alla volta in 3D (le
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
            // 5 nov pomeriggio (punto 6 approvato): salendo piano, le pagine accanto si intravedono già dal 18% dell'altezza
            // (al 25% sono al 40%); alla pausa oltre il 28% si completano come prima, con la vibrazione e il suono (paginePronte).
            // Tornando sotto il 18% spariscono di nuovo.
            if !tiro.agganciata && !naviga.suonoPagine {
                let q = (max(0, -t.y) / altezza - TiroPagina.intravede) / (TiroPagina.intravedePiena - TiroPagina.intravede)
                let si = TiroPagina.intravedeQuanto * Double(min(1, max(0, q)))
                if abs(si - naviga.rivela) > 0.002 {
                    var senza = Transaction(); senza.disablesAnimations = true
                    withTransaction(senza) { naviga.rivela = si }
                }
            }
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
        else if naviga.rivela > 0.001 { withAnimation(.easeOut(duration: 0.15)) { naviga.rivela = 0 } }   // quelle intraviste se ne vanno
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
                            Aptica.sfoglia()                                  // 5 nov: più forte (era «leggero»)
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
        Aptica.sceltaPagina()                                         // 5 nov: più forte (era «leggero»)
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
                naviga.materia = v.id                                 // come il mockup: ora si materializza
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
        Aptica.chiusaPagina()
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

    // MARK: AGGANCIO (ORIGINE · AGGANCIO II del mockup, scelto dal signore il 4 nov notte): la pagina continua il lancio e vola
    // dentro il reattore

    /// `base`: dove sta la pagina; `velocita`: il lancio del dito (punti al secondo); `scala`: quanto stava rimpicciolendo (1/s).
    /// Il suono parte a un istante preciso; gli effetti partono quando si sente, la pagina subito (continua il dito) e arriva nel
    /// reattore all'aggancio (0,44 s dopo il suono: il colpo è a 0,466 s). Tutto spento a 1,1 s dal dito alzato.
    /// `olo`: a voce la pagina parte intera e diventa ologramma nei primi istanti del volo (col dito lo è già).
    private func aggancio(id: UUID, base: TiroPagina.Viva, velocita: CGVector, scala: CGFloat, olo: Bool = false) {
        Suoni.zittisciOlo()
        let fra = min(Suoni.sparisce(), TempiAggancio.attesaMassima)
        Aptica.lancioPagina()
        // il centro vero della pagina (non sempre quello dello schermo: dipende dai margini della sezione) va sul reattore;
        // 5 nov: il reattore di adesso (naviga), non quello copiato quando sono stati preparati i gesti
        let r = telaio(id)
        let misurato = naviga.reattore == .zero ? reattore : naviga.reattore
        let centro = misurato == .zero ? CGPoint(x: larghezza / 2, y: altezza * 0.485) : misurato   // non ancora misurato: il suo posto
        let verso = CGPoint(x: centro.x - r.midX, y: centro.y - r.midY)
        let scalaReattore = max(0.08, min(0.25, naviga.diametroReattore * 0.5 / r.height))
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
        tiro.lancia(volo, olo: olo)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((fra + TempiAggancio.fase) * 1000)))
            var senza = Transaction(); senza.disablesAnimations = true
            withTransaction(senza) {
                portaDavanti(nil)                                         // la sezione va dietro (viva), davanti JARVIS
                naviga.dopoAggancio = true
            }
            // la luce si spegne a 1,1 s dal dito alzato (TempiAggancio.fine); 20 ms dopo si torna al modo normale
            try? await Task.sleep(for: .milliseconds(Int((TempiAggancio.fine - TempiAggancio.fase - fra) * 1000) + 20))
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
                        withTransaction(t) { naviga.modo = .normale; naviga.bordo = 0; naviga.verso = nil; naviga.materia = r }
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
                    withTransaction(t) { naviga.modo = .normale; naviga.bordo = 0; naviga.verso = nil; naviga.materia = r }
                }
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { naviga.bordo = 0 }
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); if naviga.bordo == 0 { naviga.modo = .normale; naviga.verso = nil } }
            }
        }
        trackpad.installa()
    }
}

/// I tempi dell'AGGANCIO (ORIGINE · AGGANCIO II), uguali nel mockup, a tempo col suono «sparisce» (misurato sul file: colpi a 0,466
/// e 1,002 s). Due orologi, come nel mockup: dal dito alzato (`tau`, quello dei fotogrammi) e dal suono (`t = tau − ritardo`: aggancio,
/// lampo, battiti). L'animazione anticipa i colpi di 10–20 ms: l'occhio la sente insieme al suono. Solo calcoli: senza attore.
nonisolated enum TempiAggancio {
    /// A 0,44 s dal suono la pagina arriva nel reattore, le staffe agganciano e il mirino scatta.
    static let fase: Double = 0.44
    /// Il lampo nel reattore: da 0,43, pieno a 0,45, spento a 0,60 (orologio del suono).
    static let lampo: Double = 0.43
    /// I due battiti del reattore, sui due colpi del suono (inizio, forza, durata): il secondo breve, dentro i 1100 ms.
    static let battiti: [(Double, Double, Double)] = [(0.455, 1, 0.5), (0.99, 0.75, 0.12)]
    /// Tutto spento a 1,1 s dal dito alzato.
    static let fine: Double = 1.1
    /// Con cuffie Bluetooth lente l'animazione aspetta il suono al massimo 0,15 s (oltre, il gesto sembrerebbe lento).
    static let attesaMassima: Double = 0.15

    // le curve del mockup
    static func c01(_ u: Double) -> Double { u < 0 ? 0 : (u > 1 ? 1 : u) }
    /// smoothstep
    static func lisc(_ u: Double) -> Double { let v = c01(u); return v * v * (3 - 2 * v) }
    /// ease-out cubica
    static func usc(_ u: Double) -> Double { 1 - pow(1 - c01(u), 3) }
    /// «ease in-out» quadratica
    static func ease(_ u: Double) -> Double { u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2 }

    /// Il passaggio da ORIGINE ad AGGANCIO II: da 170 a 260 ms dal dito alzato.
    static func passaggio(_ tau: Double) -> Double { lisc((tau - 0.17) / 0.09) }

    /// La riga del laser sulla pagina, in % dell'altezza dall'alto (102 = sotto la pagina, −4 = sopra la cima): parte nel passaggio e
    /// raggiunge senza scatti quella di AGGANCIO II, che sale con la curva «ease in-out» in 0,44 s dal suono.
    static func laser(_ tau: Double, ritardo: Double) -> Double {
        let t = max(0, tau - ritardo), agg = 102 - ease(c01(t / fase)) * 106
        return 102 - (102 - agg) * passaggio(tau)
    }

    /// L'inclinazione all'indietro (gradi) dal dito alzato: 38° in 150 ms (ORIGINE), 19° a 222 ms, poi fino a 42° all'aggancio.
    static func inclinazione(_ tau: Double, durata: Double) -> Double {
        if tau < 0.15 { return 38 * usc(tau / 0.15) }
        if tau < 0.222 { return 38 - 19 * lisc((tau - 0.15) / 0.072) }
        return 19 + 23 * lisc((tau - 0.222) / max(0.05, durata - 0.222))
    }

    /// Il giro dell'anello di luce: nel mockup cresce di (2,2 + 3·passaggio) al secondo dal suono; qui il suo integrale esatto.
    static func giroAnello(_ tau: Double, ritardo: Double) -> Double {
        let t = max(0, tau - ritardo), x = (tau - 0.17) / 0.09
        let g = x <= 0 ? 0 : (x < 1 ? x * x * x - x * x * x * x / 2 : 0.5 + (x - 1))   // ∫ smoothstep
        return 2.2 * t + 3 * 0.09 * g
    }

    /// Il caso dei pixel che si staccano sotto il laser (lo stesso numero del mockup, bit per bit).
    static func pixelCaso(_ n0: Int) -> Double {
        var n = UInt32(truncatingIfNeeded: n0)
        n = (n ^ (n >> 16)) &* 0x45d9f3b
        n = (n ^ (n >> 16)) &* 0x45d9f3b
        return Double(n ^ (n >> 16)) / 4_294_967_296
    }
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

    /// Dove sta la pagina dopo `tau` secondi dal lancio: lo spostamento dal suo centro a riposo e la scala.
    func stato(_ tau: Double) -> (x: CGFloat, y: CGFloat, scala: CGFloat) {
        let u = CGFloat(max(0, min(1, tau / durata)))
        let h00 = 2 * u * u * u - 3 * u * u + 1, h10 = u * u * u - 2 * u * u + u, h01 = -2 * u * u * u + 3 * u * u
        return (x: h00 * p0.x + h10 * m0.dx + h01 * p1.x,
                y: h00 * p0.y + h10 * m0.dy + h01 * p1.y,
                scala: max(0.02, h00 * s0 + h10 * ms0 + h01 * s1))
    }

    /// La pagina sullo schermo a `tau` secondi dal lancio (fino all'aggancio; dopo resta dov'è arrivata): la stessa prospettiva di
    /// `Proiezione`. `telaio`: dove sta la pagina a riposo (coordinate globali).
    func proiezione(_ tau: Double, telaio: CGRect) -> ProiezionePagina {
        let k = min(max(0, tau), durata), st = stato(k), a = TempiAggancio.inclinazione(k, durata: durata) * .pi / 180
        return ProiezionePagina(cx: Double(telaio.midX), cy: Double(telaio.midY), w: Double(telaio.width), h: Double(telaio.height),
                                x: Double(st.x), y: Double(st.y), s: Double(st.scala), ca: cos(a), sa: sin(a))
    }
}

/// Dove va sullo schermo un punto della pagina (u, v da 0 a 1) con la posa del volo: `posaSchermo` del mockup (1100, dal centro).
nonisolated struct ProiezionePagina {
    let cx: Double, cy: Double, w: Double, h: Double
    let x: Double, y: Double, s: Double, ca: Double, sa: Double

    func punto(_ u: Double, _ v: Double) -> CGPoint {
        let X = (u - 0.5) * w * s, Y = (v - 0.5) * h * s, k = 1100 / (1100 - Y * sa)
        return CGPoint(x: cx + (X + x) * k, y: cy + (Y * ca + y) * k)
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
        /// AGGANCIO: l'inclinazione all'indietro (gradi) e la riga del laser (0 cima … 1 fondo; da 1,015 in su la pagina è intera).
        var inclina: Double = 0
        var riga: Double = 2
    }

    /// L'orologio dell'AGGANCIO (secondi dal dito alzato), lo stesso fotogramma della pagina: lo legge solo la luce.
    let orologio = OrologioAggancio()

    // le misure (uguali al mockup)
    static let sMeta: CGFloat = 0.78                   // la pagina olografica a metà pagina («almeno il 30% più grandi», 3 nov sera)
    static let soglia: CGFloat = 0.28                  // le pagine: oltre il 28% dell'altezza
    static let intravede: CGFloat = 0.18               // 5 nov (punto 6): le pagine accanto si intravedono dal 18%…
    static let intravedePiena: CGFloat = 0.25          // …e al 25% sono al massimo prima della pausa…
    static let intravedeQuanto: Double = 0.4           // …cioè al 40%
    static let pausaV: CGFloat = 140                   // fermo: sotto 140 punti al secondo…
    static let pausaT: Double = 0.06                   // …per 60 ms
    static let lancioV: CGFloat = 550                  // lanciata: oltre 550 punti al secondo…
    static let lancioVOlo: CGFloat = 750               // …750 se le pagine sono già comparse
    static let lancioMin: CGFloat = 24                 // dopo almeno 24 punti
    static let giuV: CGFloat = 350                     // tirata giù: oltre 350 punti al secondo, torna com'era
    /// 4 nov, «Jarvis, mettila da parte»: il lancio di un dito medio (900 punti al secondo in su, la pagina che rimpicciolisce
    /// di 1,2 al secondo, come a 150 punti di corsa); l'ologramma arriva in 0,15 s.
    static let lancioVoce = CGVector(dx: 0, dy: -900)
    static let lancioVoceScala: CGFloat = -1.2
    static let entrataOlo: Double = 0.15

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
    private var voloPosato = false
    private var voloOlo = false
    private var t0Volo: CFTimeInterval = 0
    private var baseVolo = Viva()
    private var f0Volo: Double = 0
    private var collegamento: CADisplayLink?

    /// Quanto è trasparente una pagina olografica piena (il fondo e la griglia si vedono attraverso, come nel mockup).
    static let trasparenza = 0.45

    /// La tinta olografica a passi di un decimo, per le pagine web (OloWeb): la pagina si chiama una volta per passo, non 120
    /// volte al secondo; fra un passo e l'altro sfuma la pagina stessa.
    static func passoOlo(_ t: Double) -> Double { (min(1, max(0, t)) * 10).rounded() / 10 }

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

    func vibra() { Aptica.pagine() }                              // 5 nov: il colpo pieno delle pagine (era «medio»)

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

    /// Il volo nel reattore (la pagina continua il lancio). `olo`: la pagina parte intera (a voce) e diventa ologramma, angoli,
    /// velo e ombra, nei primi 0,15 s.
    func lancia(_ v: Volo, olo: Bool = false) {
        volo = v
        t0Volo = CACurrentMediaTime()
        baseVolo = viva
        f0Volo = fondo
        voloPosato = false
        voloOlo = olo
        orologio.tau = 0
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
                            Aptica.pagine()                               // 5 nov: si sente anche col microfono aperto, più forte
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
            // ORIGINE · AGGANCIO II: la pagina continua il lancio, si inclina (38° → 19° → 42°) e il laser la scioglie dal basso; il
            // tempo è quello in cui il fotogramma si vedrà, lo stesso per la pagina e per la luce
            guard let v = volo else { fase = .ferma; return }
            let tau = max(0, l.targetTimestamp - t0Volo)
            if !voloPosato {
                let k = min(tau, v.durata), st = v.stato(k)
                var b = baseVolo
                if voloOlo {                                           // a voce: diventa ologramma (curva che si posa piano)
                    let q = 1 - pow(1 - min(1, tau / TiroPagina.entrataOlo), 3)
                    b.raggio += (28 - b.raggio) * CGFloat(q)
                    b.tinta += (1 - b.tinta) * q
                    b.ombra += (0.45 - b.ombra) * q
                }
                viva = Viva(x: st.x, y: st.y, scala: st.scala, raggio: b.raggio, tinta: b.tinta, ombra: b.ombra,
                            inclina: TempiAggancio.inclinazione(k, durata: v.durata), riga: TempiAggancio.laser(k, ritardo: v.ritardo) / 100)
                fondo = f0Volo * (1 - TempiAggancio.lisc(k / v.durata))
                voloPosato = tau >= v.durata                          // arrivata: tutta sciolta, resta lì finché la sezione va dietro
            }
            orologio.tau = tau
            if tau >= TempiAggancio.fine { ferma() }
        case .ferma:
            ferma()
        }
    }
}

/// L'orologio dell'AGGANCIO: i secondi dal dito alzato, aggiornati da `TiroPagina` nello stesso fotogramma della pagina (120 Hz).
/// Lo legge solo la luce, così la pagina e la luce sono sempre allo stesso istante.
final class OrologioAggancio: ObservableObject {
    @Published var tau: Double = 0
}

/// AGGANCIO, la luce: ORIGINE · AGGANCIO II del mockup (scelto dal signore il 4 nov notte, «ok bellissimo»), stessi numeri e stessi
/// tempi. Due orologi, come nel mockup: dal dito alzato (`tau`, quello dei fotogrammi) e dal suono (`t`: aggancio, lampo, battiti).
///   0–170 ms   ORIGINE: il reattore si apre (diaframma) e gli anelli giroscopici gli si aprono attorno; la pagina comincia a
///              diventare luce.
///   170–260    il passaggio: dal basso parte il laser di AGGANCIO II (tendina di luce, pixel, scintille con la scia) e raggiunge il
///              suo senza scatti; le staffe compaiono sugli angoli veri della pagina; il mirino arriva largo e si stringe mentre il
///              diaframma si chiude nel nucleo; gli anelli giroscopici diventano l'anello di luce inclinato, che si carica.
///   dopo       l'aggancio a 0,44 s dal suono: le staffe girando diventano un rombo, l'anello si chiude, il mirino scatta, lampo, onda
///              e primo battito; il secondo battito, breve; tutto spento a 1,1 s dal dito alzato.
/// Si disegna in coordinate globali, sopra la pagina che vola e con la sua stessa prospettiva (`Volo.proiezione`).
struct LuceAggancio: View {
    @ObservedObject var orologio: OrologioAggancio
    let reattore: CGPoint
    let volo: Volo
    let telaio: CGRect
    @State private var scintille: [Scintilla]

    /// Una scintilla di AGGANCIO II: nasce sulla riga del laser e va nel reattore a vortice (una curva, girata attorno al reattore).
    struct Scintilla {
        let t0: Double, dur: Double, x0: Double, y0: Double, cx: Double, cy: Double, giro: Double, s: Double
    }

    private enum Luce { case punto, alone, lampo }

    init(orologio: OrologioAggancio, reattore: CGPoint, volo: Volo, telaio: CGRect) {
        _orologio = ObservedObject(wrappedValue: orologio)
        self.reattore = reattore
        self.volo = volo
        self.telaio = telaio
        _scintille = State(initialValue: LuceAggancio.genera(volo: volo, telaio: telaio))
    }

    /// Le scintille, tutte prima: tante quante la pagina che il laser scioglie (2,7 per ogni 1% di pagina, circa 286, come nel
    /// mockup), ognuna nel suo istante e nel suo punto della riga del laser, sulla pagina in prospettiva di quell'istante.
    static func genera(volo: Volo, telaio: CGRect) -> [Scintilla] {
        var out: [Scintilla] = []
        out.reserveCapacity(300)
        let F = TempiAggancio.fase, passo = 1.0 / 480
        var precedente = 102.0, conto = 0.0, tau = 0.0
        while tau < volo.durata {
            let tau1 = min(volo.durata, tau + passo), yy = TempiAggancio.laser(tau1, ritardo: volo.ritardo)
            if yy < 101.5 {
                conto += max(0, precedente - yy) * 2.7
                precedente = yy
                while conto >= 1 {
                    conto -= 1
                    let tn = tau + Double.random(in: 0..<1) * (tau1 - tau)
                    let pr = volo.proiezione(tn, telaio: telaio)
                    let v1 = TempiAggancio.c01(TempiAggancio.laser(tn, ritardo: volo.ritardo) / 100)
                    let e = pr.punto(0, v1), g = pr.punto(1, v1), f = Double.random(in: 0..<1)
                    let x0 = Double(e.x) + Double(g.x - e.x) * f
                    let y0 = Double(e.y) + Double(g.y - e.y) * f + (Double.random(in: 0..<1) - 0.5) * 4
                    let t0 = max(0, tn - volo.ritardo)
                    out.append(Scintilla(t0: t0,
                                         dur: 0.34 + Double.random(in: 0..<1) * 0.2 + max(0, F - t0) * 0.3,
                                         x0: x0, y0: y0,
                                         cx: (Double.random(in: 0..<1) - 0.5) * 130,
                                         cy: -12 - Double.random(in: 0..<1) * min(110, max(24, y0 * 0.45)),
                                         giro: 1.1 + Double.random(in: 0..<1) * 0.7,
                                         s: 0.7 + Double.random(in: 0..<1) * 1.1))
                }
            }
            tau = tau1
        }
        return out
    }

    var body: some View {
        let tau = orologio.tau
        GeometryReader { g in
            let o = g.frame(in: .global).origin
            Canvas { gc, _ in
                gc.translateBy(x: -o.x, y: -o.y)                       // si disegna in coordinate globali, come reattore e pagina
                disegna(&gc, tau: tau)
            }
        }
    }

    // MARK: il disegno di un fotogramma (stesso ordine del mockup; tutto in luce additiva)

    private func disegna(_ gc: inout GraphicsContext, tau: Double) {
        typealias T = TempiAggancio
        guard tau < T.fine else { return }
        let F = T.fase, durata = volo.durata, rit = volo.ritardo
        let t = max(0, tau - rit), u = T.c01(tau / durata), finito = tau >= durata
        let R = reattore, RX = Double(R.x), RY = Double(R.y)
        let pas = T.passaggio(tau)
        let yy = T.laser(tau, ritardo: rit), sv = yy / 100
        let fineT = 1 - T.lisc((tau - 1) / 0.1)                         // tutto spento entro 1100 ms
        let pr = volo.proiezione(tau, telaio: telaio)                   // la pagina adesso (dopo l'aggancio: dov'è arrivata)
        let asp = Double(telaio.width / max(1, telaio.height)), m = 0.025, mv = m * asp
        let angoli: [(Double, Double)] = [(-m, -mv), (1 + m, -mv), (1 + m, 1 + mv), (-m, 1 + mv)]
        gc.blendMode = .plusLighter

        // 1) ORIGINE: il diaframma del reattore che si apre; nel passaggio si chiude nel nucleo e lascia il posto al mirino
        let ap = T.usc(t / 0.2), apA = ap * (1 - pas)
        if apA > 0.01 {
            let r = 40 * ap * (1 - 0.6 * pas), r2 = 30 * ap * (1 - 0.6 * pas)
            var p = Path()
            for i in 0..<6 { LuceAggancio.arco(&p, R, r, da: Double(i) * 1.0472 + t * 1.6, lungo: 0.7) }
            gc.stroke(p, with: .color(LuceAggancio.colore(143, 240, 255, 0.7 * apA)), style: LuceAggancio.tratto(1.4))
            gc.stroke(Path(ellipseIn: CGRect(x: RX - r2, y: RY - r2, width: r2 * 2, height: r2 * 2)),
                      with: .color(LuceAggancio.colore(79, 227, 255, 0.35 * apA)), style: LuceAggancio.tratto(1))
        }

        // 2) gli anelli giroscopici di ORIGINE, che nel passaggio diventano l'anello di luce inclinato di AGGANCIO II (si carica,
        //    all'aggancio si chiude); il secondo anello si spegne
        let ag = T.c01((t - 0.04) / 0.14)
        let carica = t < F ? T.lisc(t / F) : 1 - T.c01((t - F) / 0.12)
        let kr = t < F ? 1 : 1 - 0.8 * T.usc((t - F) / 0.09)
        let fase1 = T.giroAnello(tau, ritardo: rit), fase2 = 1.7 - 1.7 * t
        let rxE = 78 + (66 * kr - 78) * pas, ryE = 14 + (66 * 0.3 * kr - 14) * pas, incl = 0.14 + (-0.32 - 0.14) * pas
        let aB = (1 - pas) * 0.2 * ag + pas * 0.3 * carica, aA = (1 - pas) * ag + pas * carica
        if aA > 0.01 {
            gc.stroke(LuceAggancio.ellisse(R, rxE, ryE, incl), with: .color(LuceAggancio.colore(79, 227, 255, aB)), style: LuceAggancio.tratto(1))
            for k in 0..<2 {
                let a = fase1 + Double(k) * .pi, davanti = sin(a + 0.35) > 0
                let al = ((1 - pas) * (davanti ? 0.85 : 0.3) + pas * 0.85) * aA
                var p = Path()
                LuceAggancio.arcoEllisse(&p, R, rxE, ryE, incl, da: a, lungo: 0.8 + 0.1 * pas)
                gc.stroke(p, with: .color(LuceAggancio.colore((143 + 80 * pas).rounded(), (240 + 10 * pas).rounded(), 255, al)),
                          style: LuceAggancio.tratto(1.6 + 0.2 * pas))
            }
        }
        let a2 = ag * (1 - pas)
        if a2 > 0.01 {
            gc.stroke(LuceAggancio.ellisse(R, 68, 11, -0.1), with: .color(LuceAggancio.colore(79, 227, 255, 0.2 * a2)), style: LuceAggancio.tratto(1))
            for k in 0..<2 {
                let a = fase2 + Double(k) * .pi, davanti = sin(a + 0.35) > 0
                var p = Path()
                LuceAggancio.arcoEllisse(&p, R, 68, 11, -0.1, da: a, lungo: 0.8)
                gc.stroke(p, with: .color(LuceAggancio.colore(143, 240, 255, (davanti ? 0.85 : 0.3) * a2)), style: LuceAggancio.tratto(1.6))
            }
        }
        if pas > 0.01 { LuceAggancio.luce(&gc, .alone, R, 50 + 30 * carica, 0.5 * carica * pas) }

        // 3) ORIGINE: la pagina che diventa luce (solo la parte che il laser non ha ancora sciolto); si spegne fra 260 e 400 ms
        let lw = 0.5 * T.lisc((u - 0.28) / 0.4) * (1 - T.lisc((tau - 0.26) / 0.14))
        if !finito && lw > 0.01 && sv > 0.01 {
            let v1 = T.c01(sv)
            var q = Path()
            q.move(to: pr.punto(0, 0))
            q.addLine(to: pr.punto(1, 0))
            q.addLine(to: pr.punto(1, v1))
            q.addLine(to: pr.punto(0, v1))
            q.closeSubpath()
            gc.fill(q, with: .color(LuceAggancio.colore(143, 240, 255, lw)))
        }

        // 4) AGGANCIO II sulla pagina: la tendina di luce, i pixel che si staccano sotto il laser, il laser con i bagliori ai lati
        if !finito && yy < 101.5 && sv > -0.03 {
            let al = pas, v1 = T.c01(sv), v2 = T.c01(sv - 0.07)
            let e = pr.punto(0, v1), g = pr.punto(1, v1)
            if v1 - v2 > 0.005 {
                let su = pr.punto(1, v2), so = pr.punto(0, v2)
                var q = Path()
                q.move(to: e)
                q.addLine(to: g)
                q.addLine(to: su)
                q.addLine(to: so)
                q.closeSubpath()
                gc.fill(q, with: .linearGradient(Gradient(colors: [LuceAggancio.colore(79, 227, 255, 0.26 * al), LuceAggancio.colore(79, 227, 255, 0)]),
                                                 startPoint: CGPoint(x: (e.x + g.x) / 2, y: (e.y + g.y) / 2),
                                                 endPoint: CGPoint(x: (so.x + su.x) / 2, y: (so.y + su.y) / 2)))
            }
            let cs = 1.0 / 36, dvc = cs * asp, fr = Int((t * 40).rounded(.down))
            let lato = Double(hypot(g.x - e.x, g.y - e.y)) / 36 * 0.27
            var chiari = Path(), scuri = Path()
            for j in 0..<4 {
                let v = sv + (Double(j) + 0.5) * dvc
                if v > 1 || v < 0 { continue }
                let soglia = j == 0 ? 0.62 : (j == 1 ? 0.45 : (j == 2 ? 0.3 : 0.16))
                for i in 0..<36 where T.pixelCaso(i * 7 + j * 131 + fr * 977) <= soglia {
                    let o = pr.punto((Double(i) + 0.5) * cs, v)
                    let r = CGRect(x: Double(o.x) - lato, y: Double(o.y) - lato, width: lato * 2, height: lato * 2)
                    if j < 2 { chiari.addRect(r) } else { scuri.addRect(r) }
                }
            }
            gc.fill(chiari, with: .color(LuceAggancio.colore(191, 246, 255, 0.8 * al)))
            gc.fill(scuri, with: .color(LuceAggancio.colore(79, 227, 255, 0.45 * al)))
            let a = pr.punto(-0.04, sv), b = pr.punto(1.04, sv)
            var raggio = Path()
            raggio.move(to: a)
            raggio.addLine(to: b)
            gc.stroke(raggio, with: .color(LuceAggancio.colore(79, 227, 255, 0.16 * al)), style: LuceAggancio.tratto(9))
            gc.stroke(raggio, with: .color(LuceAggancio.colore(143, 240, 255, 0.4 * al)), style: LuceAggancio.tratto(3.2))
            gc.stroke(raggio, with: .color(LuceAggancio.colore(240, 253, 255, 0.95 * al)), style: LuceAggancio.tratto(1.3))
            LuceAggancio.luce(&gc, .punto, a, 10, al)
            LuceAggancio.luce(&gc, .punto, b, 10, al)
        }

        // 5) AGGANCIO II: le scintille con la scia, a vortice nel reattore (raccolte per colore: quattro disegni in tutto)
        var scia1 = Path(), scia2 = Path(), teste1 = Path(), teste2 = Path()
        for p in scintille {
            let w = (t - p.t0) / p.dur
            guard w >= 0, w <= 1 else { continue }
            let h = LuceAggancio.dove(p, w * w * (3 - 2 * w), R)
            var prima = h
            for j in 0..<2 {
                let w2 = w - Double(j + 1) * 0.065
                if w2 <= 0 { break }
                let q = LuceAggancio.dove(p, w2 * w2 * (3 - 2 * w2), R)
                if j == 0 {
                    scia1.move(to: prima)
                    scia1.addLine(to: q)
                } else {
                    scia2.move(to: prima)
                    scia2.addLine(to: q)
                }
                prima = q
            }
            let r = p.s * 0.8, c = CGRect(x: Double(h.x) - r, y: Double(h.y) - r, width: r * 2, height: r * 2)
            if p.s > 1.25 { teste1.addEllipse(in: c) } else { teste2.addEllipse(in: c) }
        }
        gc.stroke(scia1, with: .color(LuceAggancio.colore(79, 227, 255, 0.55)), style: LuceAggancio.tratto(1.3))
        gc.stroke(scia2, with: .color(LuceAggancio.colore(79, 227, 255, 0.26)), style: LuceAggancio.tratto(0.95))
        gc.fill(teste1, with: .color(LuceAggancio.colore(240, 253, 255, 0.95)))
        gc.fill(teste2, with: .color(LuceAggancio.colore(191, 246, 255, 0.72)))

        // 6) AGGANCIO II: le staffe sugli angoli veri della pagina (compaiono nel passaggio); all'aggancio volano sul reattore e
        //    girando diventano un rombo
        let K0 = angoli.map { pr.punto($0.0, $0.1) }
        let lB = max(8, min(26, Double(hypot(K0[2].x - K0[3].x, K0[2].y - K0[3].y)) * 0.12))
        if !finito {
            LuceAggancio.staffe(&gc, K0, lB, 0.95 * T.lisc((tau - 0.17) / 0.05))
        } else if t < F + 0.26 {
            let e = T.usc((t - F) / 0.1), gi = Double.pi / 4 * e, rr = 48.0
            let al = 0.95 * (t < F + 0.12 ? 1 : 1 - (t - F - 0.12) / 0.14)
            var K: [CGPoint] = []
            for i in 0..<4 {
                let sx: Double = (i == 0 || i == 3) ? -1 : 1, sy: Double = i < 2 ? -1 : 1
                let tx = RX + (sx * cos(gi) - sy * sin(gi)) * rr, ty = RY + (sx * sin(gi) + sy * cos(gi)) * rr
                K.append(CGPoint(x: Double(K0[i].x) + (tx - Double(K0[i].x)) * e, y: Double(K0[i].y) + (ty - Double(K0[i].y)) * e))
            }
            LuceAggancio.staffe(&gc, K, lB + (14 - lB) * e, al)
        }

        // 7) il mirino a tre anelli (arriva nel passaggio, largo, e si stringe; all'aggancio scatta) e le quattro tacche
        let stringe = t < F ? 1.9 - 0.9 * T.lisc(t / F) : (t < F + 0.08 ? 1 - 0.12 * sin((t - F) / 0.08 * .pi) : 1)
        let alM = T.lisc((tau - 0.17) / 0.08) * fineT
        if alM > 0 {
            let giro = t * (t < F ? 1.2 : 3)
            let anelli: [(Double, Int, Double, Double, Double)] = [(46, 12, 1.6, 2, 0.55), (60, 36, -0.9, 1, 0.4), (74, 6, 0.6, 3, 0.3)]
            for (r, n, vel, lw, a0) in anelli {
                var anello = Path()
                let passo = 2 * Double.pi / Double(n)
                for i in 0..<n { LuceAggancio.arco(&anello, R, r * stringe, da: giro * vel + Double(i) * passo, lungo: passo * 0.55) }
                gc.stroke(anello, with: .color(LuceAggancio.colore(143, 240, 255, alM * a0 * 1.6)),
                          style: StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .round))
            }
        }
        if alM > 0.01 {
            var tacche = Path()
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + (t < F ? 0 : (t - F) * 4), r1 = 86 * stringe, r2 = r1 + 9
                tacche.move(to: CGPoint(x: RX + cos(a) * r1, y: RY + sin(a) * r1))
                tacche.addLine(to: CGPoint(x: RX + cos(a) * r2, y: RY + sin(a) * r2))
            }
            gc.stroke(tacche, with: .color(LuceAggancio.colore(191, 246, 255, alM * 0.8)), style: LuceAggancio.tratto(1.2))
        }

        // 8) l'aggancio: il lampo sul colpo, l'onda, il primo battito; il secondo battito, sul secondo colpo, breve
        if t > T.lampo && t < T.lampo + 0.17 {
            let v = (t - T.lampo) / 0.17
            LuceAggancio.luce(&gc, .lampo, R, 60 + v * 40, 0.85 * (v < 0.12 ? v / 0.12 : (1 - v) / 0.88))
        }
        if t > F && t < F + 0.3 {
            let v = (t - F) / 0.3, r = 36 + 120 * T.usc(v)
            gc.stroke(Path(ellipseIn: CGRect(x: RX - r, y: RY - r, width: r * 2, height: r * 2)),
                      with: .color(LuceAggancio.colore(191, 246, 255, 0.7 * (1 - v))), style: LuceAggancio.tratto(2 * (1 - v) + 0.4))
        }
        for (tb, forza, dur) in T.battiti {
            let v = (t - tb) / dur
            guard v > 0, v < 1 else { continue }
            let e = 1 - pow(1 - v, 2.5), al = (1 - v) * forza * fineT, r = 28 + e * 96
            LuceAggancio.luce(&gc, .alone, R, 70 + e * 50, al)
            gc.stroke(Path(ellipseIn: CGRect(x: RX - r, y: RY - r, width: r * 2, height: r * 2)),
                      with: .color(LuceAggancio.colore(143, 240, 255, al * 0.9)), style: LuceAggancio.tratto(2 * (1 - v) + 0.5))
        }
    }

    // MARK: i pezzi

    private static func colore(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255).opacity(max(0, min(1, a)))
    }

    private static func tratto(_ w: Double) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }

    /// Un arco di cerchio come spezzata, da `a0` per `l` radianti (il verso è sempre quello del mockup, a schermo).
    private static func arco(_ p: inout Path, _ c: CGPoint, _ r: Double, da a0: Double, lungo l: Double) {
        let passi = max(3, Int(l * r / 5))
        for i in 0...passi {
            let a = a0 + l * Double(i) / Double(passi)
            let q = CGPoint(x: Double(c.x) + cos(a) * r, y: Double(c.y) + sin(a) * r)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
    }

    /// Un'ellisse inclinata (in radianti, come `ellipse()` del mockup).
    private static func ellisse(_ c: CGPoint, _ rx: Double, _ ry: Double, _ incl: Double) -> Path {
        Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            .applying(CGAffineTransform(rotationAngle: incl).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
    }

    /// Un arco d'ellisse inclinata come spezzata (l'angolo è quello del parametro, come `ellipse()` del mockup).
    private static func arcoEllisse(_ p: inout Path, _ c: CGPoint, _ rx: Double, _ ry: Double, _ incl: Double, da a0: Double, lungo l: Double) {
        let passi = max(4, Int(l * max(rx, ry) / 5)), ci = cos(incl), si = sin(incl)
        for i in 0...passi {
            let a = a0 + l * Double(i) / Double(passi), ex = rx * cos(a), ey = ry * sin(a)
            let q = CGPoint(x: Double(c.x) + ex * ci - ey * si, y: Double(c.y) + ex * si + ey * ci)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
    }

    /// Dove sta una scintilla al punto `e` del suo viaggio: la curva verso il reattore, girata attorno al reattore di giro·e².
    private static func dove(_ p: Scintilla, _ e: Double, _ R: CGPoint) -> CGPoint {
        let RX = Double(R.x), RY = Double(R.y), b = 1 - e
        let X = b * b * p.x0 + 2 * b * e * (p.x0 + p.cx) + e * e * RX
        let Y = b * b * p.y0 + 2 * b * e * (p.y0 + p.cy) + e * e * RY
        let f = p.giro * e * e, cf = cos(f), sf = sin(f), dx = X - RX, dy = Y - RY
        return CGPoint(x: RX + dx * cf - dy * sf, y: RY + dx * sf + dy * cf)
    }

    /// Le staffe del mirino su quattro angoli qualsiasi (la pagina in prospettiva, o il rombo sul reattore): i bracci vanno verso gli
    /// angoli vicini, lunghi `l` (al massimo il 30% del lato).
    private static func staffe(_ gc: inout GraphicsContext, _ K: [CGPoint], _ l: Double, _ al: Double) {
        guard al > 0.01, K.count == 4 else { return }
        var p = Path()
        for i in 0..<4 {
            let k = K[i], a = K[(i + 3) % 4], n = K[(i + 1) % 4]
            let la = Double(hypot(a.x - k.x, a.y - k.y)), ln = Double(hypot(n.x - k.x, n.y - k.y))
            let lp = la > 0 ? la : 1, lq = ln > 0 ? ln : 1, da = min(l, lp * 0.3), db = min(l, lq * 0.3)
            p.move(to: CGPoint(x: Double(k.x) + Double(a.x - k.x) / lp * da, y: Double(k.y) + Double(a.y - k.y) / lp * da))
            p.addLine(to: k)
            p.addLine(to: CGPoint(x: Double(k.x) + Double(n.x - k.x) / lq * db, y: Double(k.y) + Double(n.y - k.y) / lq * db))
        }
        gc.stroke(p, with: .color(colore(143, 240, 255, min(1, al))), style: tratto(2))
    }

    /// Le luci già pronte del mockup (punto, alone, lampo): un tondo sfumato di raggio `r`, con opacità `a`.
    private static func luce(_ gc: inout GraphicsContext, _ tipo: Luce, _ c: CGPoint, _ r: Double, _ a: Double) {
        guard a > 0.004, r > 0.5 else { return }
        let k = min(1, a)
        let stops: [Gradient.Stop]
        switch tipo {
        case .punto:
            stops = [.init(color: colore(240, 253, 255, k), location: 0), .init(color: colore(191, 246, 255, 0.85 * k), location: 0.16),
                     .init(color: colore(79, 227, 255, 0.25 * k), location: 0.42), .init(color: colore(79, 227, 255, 0), location: 1)]
        case .alone:
            stops = [.init(color: colore(223, 250, 255, 0.55 * k), location: 0), .init(color: colore(79, 227, 255, 0), location: 1)]
        case .lampo:
            stops = [.init(color: colore(240, 253, 255, k), location: 0), .init(color: colore(79, 227, 255, 0), location: 1)]
        }
        gc.fill(Path(ellipseIn: CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: r * 2, height: r * 2)),
                with: .radialGradient(Gradient(stops: stops), center: c, startRadius: 0, endRadius: r))
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

/// Il tono olografico delle pagine, uguale al mockup (5 nov, il signore: «trasparenti e cool come nel mockup»):
/// - .olo-tinta: il ciano #4fe3ff in «color» (la pagina diventa tutta ciano, con le sue luci e le sue ombre), più un velo ciano
///   al 7% in «screen» e il bagliore interno sui bordi (inset 60 px al 25%);
/// - .olo-righe: le righe di scansione, una riga nera al 42% ogni 3 punti;
/// - il bordo che brilla (1,5 punti, #8ff0ff all'85%).
/// La pagina sotto, in «screen» (PosaPagina, SegueTiro), lascia vedere il fondo olografico dove è scura.
/// `forza` (0…1) è l'opacità di ogni strato, data prima della fusione: come nel mockup (tintaDito), dove la tinta cresce col dito.
/// Non va data all'insieme: un'opacità sul gruppo fonderebbe il ciano col vuoto invece che con la pagina (pagina tutta ciano).
struct VeloOlo: View {
    var forza: Double = 1
    /// 5 nov (il signore: «Studio e Social come gli altri, più trasparenti, identici al mockup»): sopra una pagina web le due
    /// fusioni di SwiftUI non arrivano dentro la WKWebView (vista UIKit). Il ciano e il velo al 7% li mette la pagina stessa,
    /// con la stessa fusione del mockup (OloWeb); qui restano il bagliore, le righe e il bordo.
    var web = false
    var body: some View {
        ZStack {
            if !web {
                Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(forza).blendMode(.color)
                Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.07 * forza).blendMode(.screen)
            }
            RigheOlo().opacity(forza)
            // il bordo come .foglio.in-vista del mockup (le pagine olografiche): 1,5 punti di ciano al 55% (era #8ff0ff all'85%)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.55 * forza), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// Quanto è olografica la pagina (0…1, a passi di un decimo) e se si sta materializzando: le pagine web (Studio, Social,
/// Browser) li leggono per mettersi il velo ciano dentro la pagina (OloWeb).
private struct ChiaveTintaOlo: EnvironmentKey { static let defaultValue: Double = 0 }
private struct ChiaveMateriaOlo: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var tintaOlo: Double {
        get { self[ChiaveTintaOlo.self] }
        set { self[ChiaveTintaOlo.self] = newValue }
    }
    var materiaOlo: Bool {
        get { self[ChiaveMateriaOlo.self] }
        set { self[ChiaveMateriaOlo.self] = newValue }
    }
}

/// Il bagliore interno e le righe di scansione del velo olografico. Una vista senza dati: SwiftUI non la ridisegna mentre la
/// pagina si muove o la tinta cresce (si ridisegna solo se cambia la misura).
struct RigheOlo: View {
    var body: some View {
        Canvas { gc, size in
            let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
            let fondo: CGFloat = 60, w = size.width, h = size.height
            // il bagliore interno dai quattro bordi (box-shadow: inset 0 0 60px rgba(79,227,255,.25))
            let bordi: [(CGRect, CGPoint, CGPoint)] = [
                (CGRect(x: 0, y: 0, width: w, height: fondo), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: fondo)),
                (CGRect(x: 0, y: h - fondo, width: w, height: fondo), CGPoint(x: 0, y: h), CGPoint(x: 0, y: h - fondo)),
                (CGRect(x: 0, y: 0, width: fondo, height: h), CGPoint(x: 0, y: 0), CGPoint(x: fondo, y: 0)),
                (CGRect(x: w - fondo, y: 0, width: fondo, height: h), CGPoint(x: w, y: 0), CGPoint(x: w - fondo, y: 0)),
            ]
            for (r, da, a) in bordi {
                gc.fill(Path(r), with: .linearGradient(Gradient(colors: [ciano.opacity(0.25), ciano.opacity(0)]), startPoint: da, endPoint: a))
            }
            var righe = Path()
            var y: CGFloat = 0
            while y < h { righe.addRect(CGRect(x: 0, y: y, width: w, height: 1)); y += 3 }
            gc.fill(righe, with: .color(.black.opacity(0.42)))
        }
    }
}

/// Il bagliore attorno alla pagina olografica, come .foglio.in-vista del mockup (0 0 46px al 22%); `forza` 0,45 = quello pieno.
/// 5 nov pomeriggio (il signore: «troppo luminosi»): prima era quello più forte (26 px al 55% e 70 px al 25%).
/// 5 nov pomeriggio (punto 5 approvato: «alone disegnato una volta»): prima era l'ombra della pagina intera, ricalcolata a ogni
/// fotogramma (120 al secondo) mentre la pagina si muove. Ora è un'immagine sola, disegnata una volta all'avvio (il rettangolo
/// arrotondato della pagina, sfocato di 23 punti, nel ciano), stirata alla misura della pagina e messa dietro: stessa luce, stesso
/// colore, stessa forza (22%, e come prima segue quanto la pagina è piena). La pagina sopra non si ridisegna più per l'alone.
struct AloneOlo: ViewModifier {
    let forza: Double
    /// Quanto è piena la pagina (1 − trasparenza × tinta): l'ombra di prima prendeva la trasparenza della pagina.
    var alfa: Double = 1
    func body(content: Content) -> some View {
        let k = min(1, max(0, forza / 0.45))
        content
            .background {
                if k > 0.001 {
                    Image(uiImage: AloneOlo.immagine)
                        .resizable(capInsets: EdgeInsets(top: AloneOlo.bordo, leading: AloneOlo.bordo, bottom: AloneOlo.bordo, trailing: AloneOlo.bordo))
                        .padding(-AloneOlo.fuori)
                        .opacity(0.22 * k * alfa)
                        .allowsHitTesting(false)
                }
            }
    }

    /// Quanto la luce esce dalla pagina e quanto entra (la sfocatura di 23 punti si spegne entro 4 volte tanto).
    static let fuori: CGFloat = 92
    static let bordo: CGFloat = 184
    /// L'alone in nove pezzi: gli angoli restano com'erano, il centro (4 punti) si stira a ogni misura di pagina.
    static let immagine: UIImage = {
        let lato = 2 * bordo + 4, forma = lato - 2 * fuori
        let vista = RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(red: 79 / 255, green: 227 / 255, blue: 1))
            .frame(width: forma, height: forma)
            .blur(radius: 23)
            .frame(width: lato, height: lato)
        let r = ImageRenderer(content: vista)
        r.scale = 3
        r.isOpaque = false
        return r.uiImage ?? UIImage()
    }()
}

/// 5 nov pomeriggio (il signore: «manca l'animazione quando li seleziono, come nel mockup»): la pagina scelta si materializza
/// come `materializza` del mockup. Sotto la riga di scansione è ancora luce ciano (il velo olografico), sopra è la sezione vera;
/// la riga (2 punti, #dffaff, con l'alone) scende in 0,43 s con la sua scia di 70 punti; le staffe arrivano dagli angoli in
/// 0,62 s e spariscono. Finito, si toglie da sola.
struct MaterializzaOlo: View {
    /// Studio, Social o Browser: sotto la riga il ciano lo mette la pagina web stessa (OloWeb, con la stessa corsa).
    var web = false
    let fatto: () -> Void
    @State private var inizio = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(inizio)
            let q = min(1, t / 0.43), e = q < 0.5 ? 2 * q * q : 1 - pow(-2 * q + 2, 2) / 2, y = e * 1.06 - 0.03
            GeometryReader { g in
                let h = g.size.height, yy = CGFloat(y), ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
                ZStack(alignment: .top) {
                    if q < 1 {
                        let a = max(0, y - 0.05)
                        VeloOlo(forza: 1, web: web)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: a), .init(color: .black, location: max(a + 0.0001, y))],
                                                 startPoint: .top, endPoint: .bottom))
                        LinearGradient(colors: [ciano.opacity(0), ciano.opacity(0.22)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 70)
                            .offset(y: yy * h - 72)
                        Rectangle()
                            .fill(Color(red: 223 / 255, green: 250 / 255, blue: 1))
                            .frame(height: 2)
                            .shadow(color: ciano, radius: 5)
                            .shadow(color: ciano.opacity(0.85), radius: 13)
                            .offset(y: yy * h)
                            .opacity(q < 0.85 ? 1 : (1 - q) / 0.15)
                    }
                    StaffeOlo(t: t, misura: g.size)
                }
                .frame(width: g.size.width, height: h, alignment: .top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .milliseconds(680))
            fatto()
        }
    }
}

/// Le quattro staffe del mockup (.olo-staffe: 28 punti, 2 punti #8ff0ff con l'alone): arrivano da 60 e 120 punti verso gli
/// angoli (al 70% di 0,62 s), si accendono al 30% e si spengono alla fine. Stanno a 20 punti dai bordi (nel mockup 10 dal bordo
/// del telefono disegnato; qui lo schermo ha gli angoli tondi e a 10 punti si taglierebbero).
struct StaffeOlo: View {
    let t: Double
    let misura: CGSize

    var body: some View {
        let u = min(1, t / 0.62), m = min(1, u / 0.7), e = 1 - pow(1 - m, 3)
        let alfa = u < 0.3 ? u / 0.3 : u < 0.7 ? 1 : max(0, 1 - (u - 0.7) / 0.3)
        let w = misura.width, h = misura.height, l: CGFloat = 28, d: CGFloat = 20
        Path { p in
            for (cx, cy, sx, sy, dx, dy) in [(d, d, 1.0, 1.0, 60.0, 120.0), (w - d, d, -1, 1, -60, 120), (d, h - d, 1, -1, 60, -120),
                                              (w - d, h - d, -1, -1, -60, -120)] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
                let k = CGFloat(1 - e), x = cx + dx * k, y = cy + dy * k
                p.move(to: CGPoint(x: x, y: y + sy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + sx * l, y: y))
            }
        }
        .stroke(Color(red: 143 / 255, green: 240 / 255, blue: 1), style: StrokeStyle(lineWidth: 2, lineCap: .square))
        .shadow(color: Color(red: 79 / 255, green: 227 / 255, blue: 1), radius: 3)
        .opacity(alfa)
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
    /// 5 nov pomeriggio (punto 4 approvato: «partenza senza scatto, come Apple»): iOS riconosce lo swipe dopo una decina di
    /// punti, e prima la pagina saltava subito di quei punti. Ora parte da ferma sotto il dito e li recupera dolcemente nei 48
    /// punti successivi: dopo, il punto toccato è di nuovo esattamente sotto il dito, come prima.
    private var scatto: CGPoint = .zero
    private static let recupero: CGFloat = 48

    private func senzaScatto(_ t: CGPoint) -> CGPoint {
        let d = CGPoint(x: t.x - scatto.x, y: t.y - scatto.y)
        let u = min(1, hypot(d.x, d.y) / GestoBassoSezioni.recupero), k = u * u * (3 - 2 * u)
        return CGPoint(x: d.x + scatto.x * k, y: d.y + scatto.y * k)
    }

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
            scatto = t
            inizia(CGPoint(x: p.x - t.x, y: p.y - t.y))
            segue(senzaScatto(t), v)
        case .changed:
            segue(senzaScatto(t), v)
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
