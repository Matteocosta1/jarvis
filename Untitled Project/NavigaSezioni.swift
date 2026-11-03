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

    @State private var inizioTira: Date?
    @State private var fermoDa: Date?
    @State private var ultimoSu: CGFloat = 0
    @State private var P0: Double = 0
    @State private var assePagina: Int = 0           // 0 da decidere, 1 orizzontale (sfoglia), 2 verticale (alza)
    @State private var trackpad = TrackpadSezioni()  // sul Mac: due dita in orizzontale

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
            if naviga.modo == .sfoglio {
                Color.black.opacity(0.55).ignoresSafeArea().transition(.opacity)
                LinearGradient(colors: [Color.ciano.opacity(0.10), .clear], startPoint: .bottom, endPoint: .center).ignoresSafeArea().allowsHitTesting(false)
            }
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
                LuceAggancio(inizio: da, reattore: reattore, altezza: altezza, larghezza: larghezza)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            bordi
        }
        .gesture(gestoSfoglio, including: naviga.modo == .sfoglio ? .all : .subviews)
        .onAppear { preparaTrackpad() }
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
                .modifier(PosaPagina(posa: p))
                .transition(.offset(y: altezza + 2))               // sale e scende di tutta l'altezza, come prima
    }

    private func posa(_ v: PilaSezioni.Voce) -> Posa {
        var p = Posa()
        let davanti = pila.davanti == v.id
        switch naviga.modo {
        case .sfoglio:
            let k = carte.firstIndex(where: { $0.id == v.id }) ?? 0
            let o = scarto(k), a = abs(o), mat = naviga.scelta == v.id
            p.scala = mat ? 1 : CGFloat(0.8 / (1 + min(a, 1.3) * 0.32))
            p.rotY = mat ? 0 : o * 50
            p.x = mat ? 0 : CGFloat(o) * larghezza * 0.74
            p.y = a < 0.5 && !mat ? naviga.alzata : 0
            let via = a < 0.5 && naviga.alzata < -40 ? max(0, 1 + Double(naviga.alzata + 40) / 220) : 1
            p.opacita = mat ? 1 : max(0, 1 - max(0, a - 1) * 1.2) * via
            p.raggio = mat ? 0 : 28
            p.tinta = mat ? 0 : 1
            p.ombra = mat ? 0 : 0.45
            p.z = mat ? 100 : 50 - a * 10
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
            guard davanti else { p.opacita = 0; return p }
            p.scala = 1 - min(0.3, naviga.su / altezza * 0.45)
            p.y = -naviga.su * 0.45
            p.raggio = min(28, naviga.su / 6)
            p.z = 1
        case .aggancio:
            p.opacita = davanti || naviga.agganciata == v.id ? 1 : 0
            p.z = 1
        case .normale:
            p.opacita = davanti ? 1 : 0
            p.tocchi = davanti
            p.z = davanti ? 1 : 0
        }
        return p
    }

    // MARK: i bordi (in basso: su; ai lati: la sezione accanto)

    @ViewBuilder private var bordi: some View {
        let davanti = pila.voceDavanti
        if (davanti != nil || naviga.modo == .sfoglio || !pila.voci.isEmpty) {
            // in basso: tutta la larghezza, 24 punti (sopra la barretta di iOS: il primo swipe è di JARVIS, il secondo di iOS)
            Color.clear
                .frame(height: 24)
                .contentShape(Rectangle())
                .frame(maxHeight: .infinity, alignment: .bottom)
                .gesture(gestoBasso)
                .ignoresSafeArea(edges: .bottom)
                .zIndex(200)
        }
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

    private var gestoBasso: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in
                let su = max(0, -v.translation.height)
                if naviga.modo == .sfoglio { return }                       // dalle pagine: decide la fine
                if pila.voceDavanti == nil {                                 // da JARVIS: solo le pagine (se ce ne sono)
                    if su > altezza * 0.16 && naviga.modo != .sfoglio { apriSfoglio() }
                    return
                }
                if naviga.modo == .normale { naviga.modo = .tira; inizioTira = Date(); fermoDa = Date(); ultimoSu = su }
                guard naviga.modo == .tira else { return }
                naviga.su = su
                if abs(su - ultimoSu) > 3 { fermoDa = Date(); ultimoSu = su }
                // fermo a metà (oltre il 22% dell'altezza, il dito quasi immobile per 140 ms): le pagine
                if su > altezza * 0.22, let f = fermoDa, Date().timeIntervalSince(f) > 0.14 { apriSfoglio() }
            }
            .onEnded { v in
                let su = max(0, -v.translation.height), lancio = max(0, -v.predictedEndTranslation.height)
                switch naviga.modo {
                case .sfoglio:
                    if su > 36 || lancio > 160 { tornaAJarvis() }
                case .tira:
                    if su > 60 || lancio > 220 { aggancio() }
                    else { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { naviga.su = 0; naviga.modo = .normale } }
                default: break
                }
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

    private func apriSfoglio() {
        guard !carte.isEmpty else { return }
        let k = carte.firstIndex(where: { $0.id == pila.davanti }) ?? (carte.count - 1)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Suoni.caricaOlo()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            naviga.P = Double(k)
            naviga.alzata = 0
            naviga.su = 0
            naviga.modo = .sfoglio
        }
    }

    private func tornaAJarvis() {
        Suoni.zittisciOlo()
        Suoni.sparisce()
        portaDavanti(nil)
        withAnimation(.easeOut(duration: 0.3)) { naviga.modo = .normale; naviga.alzata = 0 }
    }

    private var gestoSfoglio: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if v.translation == .zero { P0 = naviga.P; assePagina = 0; return }
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
                    if naviga.alzata < -110 || v.predictedEndTranslation.height < -320 { chiudiCarta() }
                    else { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { naviga.alzata = 0 } }
                }
                assePagina = 0
            }
    }

    /// La pagina al centro si materializza a tutto schermo e torna davanti.
    private func scegli() {
        let k = quale(naviga.P)
        guard carte.indices.contains(k) else { return }
        let v = carte[k]
        Suoni.zittisciOlo()
        if !v.sezione.conFotocamera { Suoni.sceltaPagina() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { naviga.scelta = v.id; naviga.P = Double(k) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { portaDavanti(v.id) }
            await Task.yield()                                        // la sezione è davanti: ora le pagine se ne vanno
            withTransaction(t) {
                naviga.modo = .normale
                naviga.scelta = nil
                naviga.alzata = 0
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
                if pila.voci.isEmpty { naviga.modo = .normale }
                else { naviga.P = Double(quale(naviga.P)) }
            }
        }
    }

    // MARK: AGGANCIO

    private func aggancio() {
        Suoni.sparisce()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        naviga.aggancioDa = Date()
        naviga.agganciata = pila.davanti
        withAnimation(.easeOut(duration: 0.2)) { naviga.su = 0 }
        naviga.modo = .aggancio
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { portaDavanti(nil) }                 // la sezione va dietro (viva), davanti JARVIS
            try? await Task.sleep(for: .milliseconds(1000))           // gli anelli si spengono sul reattore (fino a 1,5 s)
            if naviga.modo == .aggancio {
                withTransaction(t) { naviga.modo = .normale; naviga.aggancioDa = nil; naviga.agganciata = nil }
            }
        }
    }
}

/// AGGANCIO, la pagina: si inclina indietro (fino a 42°), si rimpicciolisce (0,7) e sale verso il reattore, mentre la scansione
/// la percorre dal basso in alto e se la porta via (0–0,42 s).
struct AggancioPagina: ViewModifier {
    let attivo: Bool
    let inizio: Date?
    // sempre dentro lo stesso TimelineView (fermo quando non serve): la sezione non viene mai ricreata
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: nil, paused: !attivo)) { ctx in
            let dt = attivo ? ctx.date.timeIntervalSince(inizio ?? ctx.date) : 0
            let t = min(1, dt / 0.52)
            let e = 1 - pow(1 - t, 3)
            let scan = attivo ? min(1, dt / 0.42) : 0
            content
                .mask {
                    if attivo {
                        GeometryReader { g in
                            VStack(spacing: 0) {
                                Rectangle().frame(height: g.size.height * (1 - scan))
                                Spacer(minLength: 0)
                            }
                        }
                        .ignoresSafeArea()
                    } else {
                        Rectangle().padding(-3000)                     // fermo: non taglia niente
                    }
                }
                .overlay(alignment: .top) {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, Color.ciano.opacity(0.9), .white, Color.ciano.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 10)
                            .shadow(color: .ciano, radius: 12)
                            .offset(y: g.size.height * (1 - scan) - 5)
                            .opacity(attivo && scan < 1 ? 1 : 0)
                    }
                    .allowsHitTesting(false)
                }
                .rotation3DEffect(.degrees(42 * e), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
                .scaleEffect(1 - 0.3 * e)
                .offset(y: -120 * e)
        }
    }
}

/// AGGANCIO, la luce: le scintille dalla pagina al reattore (curve), le staffe che inquadrano la pagina e poi si chiudono sul
/// reattore (0,42–0,52 s), il mirino che si stringe (1,9 → 1), il lampo dell'aggancio (0,41–0,58 s), gli anelli fino a 1,5 s.
struct LuceAggancio: View {
    let inizio: Date
    let reattore: CGPoint
    let altezza: CGFloat
    let larghezza: CGFloat
    @State private var scintille: [(x: Double, y: Double, ritardo: Double, curva: Double)] =
        (0..<46).map { _ in (x: Double.random(in: 0.08...0.92), y: Double.random(in: 0.25...0.95), ritardo: Double.random(in: 0...0.22), curva: Double.random(in: -0.35...0.35)) }

    var body: some View {
        TimelineView(.animation) { ctx in
            let T = ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in
                let c = reattore
                // le scintille: dalla pagina, lungo una curva, dentro il reattore
                for s in scintille {
                    let p = (T - 0.06 - s.ritardo) / 0.36
                    guard p > 0, p < 1.15 else { continue }
                    let e = 1 - pow(1 - min(1, p), 2)
                    let a = CGPoint(x: s.x * size.width, y: s.y * size.height)
                    let ctrl = CGPoint(x: (a.x + c.x) / 2 + CGFloat(s.curva) * size.width, y: min(a.y, c.y) - 60)
                    func punto(_ u: Double) -> CGPoint {
                        let v = 1 - u
                        return CGPoint(x: v * v * a.x + 2 * v * u * ctrl.x + u * u * c.x, y: v * v * a.y + 2 * v * u * ctrl.y + u * u * c.y)
                    }
                    let q = punto(e), q2 = punto(max(0, e - 0.08))
                    var scia = Path(); scia.move(to: q2); scia.addLine(to: q)
                    let forza = p > 1 ? max(0, 1 - (p - 1) / 0.15) : 1
                    gc.stroke(scia, with: .color(Color.ciano.opacity(0.6 * forza)), lineWidth: 1.2)
                    gc.fill(Path(ellipseIn: CGRect(x: q.x - 1.4, y: q.y - 1.4, width: 2.8, height: 2.8)), with: .color(.white.opacity(forza)))
                }
                // le staffe: inquadrano la pagina, poi si chiudono sul reattore
                let chiudi = max(0, min(1, (T - 0.42) / 0.10)), vedo = T < 0.62 ? min(1, T / 0.12) : max(0, 1 - (T - 0.62) / 0.2)
                if vedo > 0 {
                    let w0 = size.width * 0.42, h0 = size.height * 0.36, w1: CGFloat = 70, h1: CGFloat = 70
                    let w = w0 + (w1 - w0) * chiudi, h = h0 + (h1 - h0) * chiudi
                    let cx = size.width / 2 + (c.x - size.width / 2) * chiudi, cy = size.height * 0.45 + (c.y - size.height * 0.45) * chiudi
                    var st = Path()
                    for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
                        let x = cx + sx * w, y = cy + sy * h
                        st.move(to: CGPoint(x: x, y: y - sy * 18)); st.addLine(to: CGPoint(x: x, y: y)); st.addLine(to: CGPoint(x: x - sx * 18, y: y))
                    }
                    gc.stroke(st, with: .color(Color.ciano.opacity(0.9 * vedo)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
                // il mirino che si stringe e il lampo dell'aggancio
                if T < 1.5 {
                    let stringe = max(0, min(1, T / 0.45)), r = 34 * (1.9 - 0.9 * (1 - pow(1 - stringe, 3)))
                    let fade = T < 0.6 ? 1 : max(0, 1 - (T - 0.6) / 0.9)
                    gc.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color.ciano.opacity(0.7 * fade)), lineWidth: 1.2)
                    for i in 0..<4 {
                        let a = Double(i) * .pi / 2 + T * 1.2
                        var tick = Path()
                        tick.move(to: CGPoint(x: c.x + cos(a) * (r + 4), y: c.y + sin(a) * (r + 4)))
                        tick.addLine(to: CGPoint(x: c.x + cos(a) * (r + 12), y: c.y + sin(a) * (r + 12)))
                        gc.stroke(tick, with: .color(Color.ciano.opacity(0.8 * fade)), lineWidth: 1.4)
                    }
                    let lampo = T > 0.41 && T < 0.58 ? sin((T - 0.41) / 0.17 * .pi) : 0
                    if lampo > 0 {
                        gc.fill(Path(ellipseIn: CGRect(x: c.x - 60, y: c.y - 60, width: 120, height: 120)),
                                with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * lampo), Color.ciano.opacity(0.4 * lampo), .clear]),
                                                      center: c, startRadius: 0, endRadius: 60))
                    }
                    // gli anelli che si allargano dal reattore e si spengono
                    for j in 0..<2 {
                        let u = (T - 0.45 - Double(j) * 0.18) / 1.0
                        guard u > 0, u < 1 else { continue }
                        let rr = 40 + 110 * u
                        gc.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(Color.ciano.opacity(0.5 * (1 - u))), lineWidth: 1.2)
                    }
                }
            }
        }
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
