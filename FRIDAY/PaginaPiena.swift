#if os(iOS)
import SwiftUI
import UIKit

// MARK: - 26 ott sera (il signore: «nessuna arriva in cima a pagina piena»): tutte le schede di JARVIS a pagina piena, come il mockup
// Salgono dal basso fino in cima (non più il foglio di iOS che si ferma sotto l'ora), si chiudono con «Chiudi» o trascinando giù
// dalla parte alta dello schermo (la fascia dell'ora). Sotto resta JARVIS: scendendo si vede lui, mai nero.

struct PaginaPiena: ViewModifier {
    @Environment(\.chiudiOVia) private var chiudi
    @Environment(\.foglioPagina) private var nelFoglio
    @Environment(\.isPresented) private var presentata
    @State private var scesa: CGFloat = 0

    /// L'altezza della fascia in alto (ora, Dynamic Island) dove parte il trascinamento: lì non ci sono tasti delle schede.
    private var finestra: UIWindow? { FasciaAlta.finestra }
    private var fascia: CGFloat { FasciaAlta.altezza }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 8 nov notte (il signore, video 21:57: «stacco e discrepanza sui colori, deve sembrare un'unica scheda»): nel contenitore
            // delle sezioni lo sfondo del foglio sta qui, sotto la sezione e dentro il suo trascinamento: sale, si ferma e scende
            // insieme a lei, dal bordo alto dello schermo al bordo basso (SfondoAncorato). Prima era un colore pieno che «ignorava i
            // margini»: iOS lo allargava fino in cima solo quando la pagina arrivava sotto l'ora, e la fascia in alto si vedeva arrivare
            // prima del resto.
            .background { if nelFoglio && !presentata { SfondoAncorato() } else { Color.fondo.ignoresSafeArea() } }
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: fascia + 8)
                    .contentShape(Rectangle())
                    .offset(y: -fascia)
                    .gesture(trascina)
            }
            .offset(y: scesa)
            .presentationBackground(.clear)                  // sotto si vede JARVIS, non il nero di iOS
    }

    /// Trascinata giù oltre la soglia: la scheda finisce di scendere da sola (ancora presentata), poi iOS la toglie quando è
    /// già sotto lo schermo, senza una seconda animazione.
    private func scendiEChiudi(durata: Double) {
        let fondo = finestra?.bounds.height ?? 1000
        withAnimation(.easeOut(duration: durata)) { scesa = fondo }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(durata * 1000) + 10))
            var t = Transaction()
            t.disablesAnimations = true                      // è già scesa: niente seconda animazione
            withTransaction(t) { chiudi() }
        }
    }

    private var trascina: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in scesa = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 140 || v.predictedEndTranslation.height > 420 {
                    scendiEChiudi(durata: 0.22)
                } else {
                    withAnimation(.spring(duration: 0.3)) { scesa = 0 }
                }
            }
    }
}

extension View {
    /// Una scheda di JARVIS a pagina piena (vedi PaginaPiena).
    func paginaPiena() -> some View { modifier(PaginaPiena()) }
}

/// La fascia in alto dello schermo (ora, Dynamic Island): da lì si trascina giù per chiudere.
@MainActor
enum FasciaAlta {
    static var finestra: UIWindow? {
        let finestre = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return finestre.first { $0.isKeyWindow } ?? finestre.first
    }
    static var altezza: CGFloat { max(finestra?.safeAreaInsets.top ?? 44, 24) }
    /// 8 nov: il margine in fondo (la barra di iOS), per la scheda della mail che arriva fino in fondo allo schermo.
    static var fondo: CGFloat { finestra?.safeAreaInsets.bottom ?? 34 }
    /// 8 nov notte: il margine sicuro in alto, esatto (dove comincia il contenitore delle sezioni e quindi ogni pagina).
    static var margineAlto: CGFloat { finestra?.safeAreaInsets.top ?? 0 }
    /// 8 nov notte: lo schermo (la finestra): il foglio di ogni sezione è grande così.
    static var schermo: CGSize { finestra?.bounds.size ?? CGSize(width: 393, height: 852) }
}

// MARK: - 26 ott sera (video del signore 21:58: Studio e Social sparivano di colpo e restava il nero per quasi un secondo)
// Le schede a pagina piena sono schermate di iOS: mentre sono aperte iOS toglie JARVIS dallo schermo e alla chiusura lo deve
// ridisegnare da capo. Studio e Social, chiudendosi, buttano via anche la pagina web con il 3D, che è pesante: per quell'attimo
// non c'era niente da mostrare, e si vedeva nero. Ora Studio e Social sono uno STRATO dentro la schermata di JARVIS: salgono e
// scendono come le altre schede (stesse curve, vedi salita e discesa) e JARVIS sotto non viene mai tolto, quindi scendendo si
// vede sempre lui. Si chiudono con «Chiudi» (della pagina) o trascinando giù dalla fascia dell'ora, come le schede.
// La pagina web si butta solo quando lo strato è già sotto lo schermo.

private struct ChiaveJarvisCoperto: EnvironmentKey { static let defaultValue = false }

// MARK: - MARK XI · le sezioni non sono più schermate di iOS ma stanno nel contenitore di JARVIS (StratoSezioni)
// Il «Chiudi» delle sezioni (e il trascinamento giù dalla fascia dell'ora) chiude la sezione del contenitore; dentro una sezione,
// un foglio di iOS aperto da lei (presentato) si chiude come sempre col suo dismiss.

/// La sezione del contenitore in cui sta questa vista (nil: fuori dal contenitore).
private struct ChiaveSezioneAperta: EnvironmentKey { static let defaultValue: UUID? = nil }
/// La sezione è dietro (o è una pagina olografica non davanti): fotocamera, microfono e comandi a voce in pausa.
private struct ChiaveSezioneDietro: EnvironmentKey { static let defaultValue = false }
/// 8 nov notte: la vista sta in una pagina del contenitore delle sezioni (StratoSezioniVista): lo sfondo del foglio si disegna
/// dal bordo alto dello schermo, fermo sulla pagina (SfondoAncorato).
private struct ChiaveFoglioPagina: EnvironmentKey { static let defaultValue = false }
extension Notification.Name {
    /// Una sezione del contenitore chiede di chiudersi (userInfo «id»: UUID).
    static let jarvisChiudiSezione = Notification.Name("JarvisChiudiSezione")
}
/// MARK XI: una sezione con fotocamera o microfono, mandata dietro, va in pausa; tornata davanti riprende (come nel mockup).
struct PausaDietro: ViewModifier {
    @Environment(\.sezioneDietro) private var dietro
    let ferma: () -> Void
    let riprendi: () -> Void
    func body(content: Content) -> some View {
        content.onChange(of: dietro) { _, d in if d { ferma() } else { riprendi() } }
    }
}
extension View {
    func pausaDietro(ferma: @escaping () -> Void, riprendi: @escaping () -> Void) -> some View {
        modifier(PausaDietro(ferma: ferma, riprendi: riprendi))
    }
    /// 4 nov · MARK XI: la sezione va dietro (un'altra sale davanti, anche chiesta a voce): il suo foglio di iOS (il Dossier di
    /// SATELLITE, il visore delle foto, il Registro…) si chiude, perché iOS lo terrebbe sopra a tutto, anche sopra la sezione
    /// nuova. La sezione resta viva dietro; tornata davanti si rivede la sua pagina.
    func chiudiFoglioDietro(_ chiudi: @escaping () -> Void) -> some View {
        modifier(PausaDietro(ferma: chiudi, riprendi: {}))
    }
}

/// Chiude la sezione del contenitore, o il foglio di iOS se la vista è presentata.
struct ChiudiOVia {
    let sezione: UUID?
    let dismiss: DismissAction
    func callAsFunction() {
        if let sezione { NotificationCenter.default.post(name: .jarvisChiudiSezione, object: nil, userInfo: ["id": sezione]) }
        else { dismiss() }
    }
}
extension EnvironmentValues {
    /// Studio o Social sono su del tutto e coprono JARVIS: le sue animazioni continue (reattore, sfondo, anelli) restano ferme
    /// sull'ultimo fotogramma, così il telefono lavora solo per la pagina (prima, sotto una schermata di iOS, JARVIS non girava).
    /// Ripartono appena lo strato comincia a scendere: scendendo si vede JARVIS vivo.
    var jarvisCoperto: Bool {
        get { self[ChiaveJarvisCoperto.self] }
        set { self[ChiaveJarvisCoperto.self] = newValue }
    }
    var sezioneAperta: UUID? {
        get { self[ChiaveSezioneAperta.self] }
        set { self[ChiaveSezioneAperta.self] = newValue }
    }
    var sezioneDietro: Bool {
        get { self[ChiaveSezioneDietro.self] }
        set { self[ChiaveSezioneDietro.self] = newValue }
    }
    var foglioPagina: Bool {
        get { self[ChiaveFoglioPagina.self] }
        set { self[ChiaveFoglioPagina.self] = newValue }
    }
    /// Al posto di `dismiss`: dentro il contenitore chiude la sezione; in un foglio presentato, il foglio.
    var chiudiOVia: ChiudiOVia { ChiudiOVia(sezione: isPresented ? nil : sezioneAperta, dismiss: dismiss) }
}

/// Le curve della salita e della discesa delle sezioni (nate il 26 ott con lo strato di Studio e Social di JARVIS).
enum StratoPagina {
    /// 26 ott sera (il signore: «Studio e Social uguali alle altre schede»): la salita e la discesa delle altre schede, misurate
    /// fotogramma per fotogramma sul suo video delle 21:58 (60 fotogrammi al secondo): salita ~0,3 s che frena in fondo, discesa
    /// ~0,35 s che parte piano e si posa piano. 8 nov sera (il signore: «il mockup adesso è perfetto… timing perfetto, deve sembrare
    /// un'unica pagina»): la salita del .foglio del mockup (transform .35s cubic-bezier(.2,.8,.2,1)).
    static let salita: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)
    /// Dopo il trascinamento col dito: 0,22 s e frena, come le altre schede (PaginaPiena), il dito l'ha già portata giù.
    static func discesa(_ durata: Double = 0.35) -> Animation {
        durata > 0.3 ? .spring(response: 0.33, dampingFraction: 1) : .easeOut(duration: durata)
    }
}
/// 27 ott (il signore): la quadrettatura della pagina d'avvio anche sullo sfondo di ogni sezione, più leggera e sfumata verso i bordi:
/// «si vede e non si vede», dà profondità. Ferma (non scorre come quella dell'avvio).
struct GrigliaSfumata: View {
    var body: some View {
        Canvas { gc, size in
            let passo: CGFloat = 22                       // come il mockup approvato (.foglio::after): 22 pt, linea 1, 0,03
            var g = Path()
            var x: CGFloat = 0
            while x < size.width { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); x += passo }
            var y: CGFloat = 0
            while y < size.height { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); y += passo }
            gc.stroke(g, with: .color(Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.03)), lineWidth: 1)
        }
        .mask(RadialGradient(stops: [.init(color: .black, location: 0.25), .init(color: .clear, location: 0.8)],
                             center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 630))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 7 nov (il signore: «non hanno lo sfondo uguale alle altre, a quadretti con la sfumatura»): lo sfondo di ogni sezione, uno solo
/// per tutte. Il fondo scuro, la quadrettatura sfumata e il chiarore ciano che scende dall'alto, come in CorniceScheda.
/// 8 nov notte (il signore: «stacco e discrepanza sui colori… i quadrati precisi, allineati e composti bene, come fosse un'unica
/// scheda»): nel contenitore delle sezioni è il foglio intero, ancorato alla pagina (SfondoAncorato): ogni sfondo della pagina
/// (quello sotto la sezione, quello della sezione, quello del caricamento) è lo stesso disegno nello stesso punto, pixel per
/// pixel, quindi non c'è più nessuna giuntura. Nei fogli di iOS (presentati) resta com'era: grande quanto il foglio.
struct SfondoSezione: View {
    var tinta: Color = .ciano
    @Environment(\.foglioPagina) private var nelFoglio
    @Environment(\.isPresented) private var presentata

    var body: some View {
        if nelFoglio && !presentata {
            SfondoAncorato(tinta: tinta)
        } else {
            SfondoFoglio(tinta: tinta)
                .ignoresSafeArea()
        }
    }
}

/// 8 nov notte: lo sfondo del foglio in una pagina del contenitore delle sezioni. Il foglio è grande quanto lo schermo e parte dal
/// bordo alto dello schermo (la pagina parte dal margine sicuro: il foglio comincia `margineAlto` più su), con misure esplicite e
/// senza «ignorare i margini»: iOS i margini li calcola sulla posizione animata, e mentre la pagina saliva allargava gli sfondi fino
/// in cima solo quando la pagina arrivava sotto l'ora (la fascia in alto arrivava ferma prima del resto, con i quadretti sfasati e il
/// chiarore che ripartiva). Così sale, si ferma e scende tutto insieme, un foglio solo. Non cambia l'impaginazione di chi lo usa
/// (prende lo spazio che gli danno) e non prende i tocchi.
struct SfondoAncorato: View {
    var tinta: Color = .ciano

    var body: some View {
        // la GeometryReader rifà il disegno se cambia la finestra (iPad, Mac, rotazione)
        GeometryReader { _ in
            let schermo = FasciaAlta.schermo
            SfondoFoglio(tinta: tinta)
                .frame(width: schermo.width, height: schermo.height)
                .offset(y: -FasciaAlta.margineAlto)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 8 nov notte (il signore: «la perfetta corrispondenza del colore, uniforme alla perfezione… i quadrati precisi, allineati e composti
/// bene»): lo sfondo del foglio disegnato come il .foglio.scheda del mockup approvato, misura per misura, a partire dal suo bordo alto:
///  · il fondo #050809 (--fondo);
///  · la quadrettatura (.foglio::after): una riga di 1 punto ogni 22 dal bordo alto e dal bordo sinistro, ciano al 3%, orizzontali e
///    verticali (dove si incrociano si sommano, come nel browser), sfumata da un cerchio al 50% / 30% del foglio: piena fino al 25% del
///    raggio, sparita all'80% (il raggio arriva all'angolo più lontano, come «farthest-corner»);
///  · il chiarore in alto (.foglio.scheda::before): una fascia alta 380 con un'ellisse centrata in alto, ciano al 16% che sparisce al
///    70% (l'ellisse passa per l'angolo più lontano della fascia con le proporzioni metà larghezza × 380, come nel browser).
/// Un Canvas solo, fermo: si ridisegna solo se cambia la grandezza del foglio.
struct SfondoFoglio: View {
    var tinta: Color = .ciano

    var body: some View {
        let luce = tinta
        Canvas { gc, size in
            let tutto = CGRect(origin: .zero, size: size)
            gc.fill(Path(tutto), with: .color(Color(red: 5 / 255, green: 8 / 255, blue: 9 / 255)))
            // la quadrettatura, sfumata dal cerchio
            gc.drawLayer { strato in
                var orizzontali = Path()
                var y: CGFloat = 0
                while y < size.height { orizzontali.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y += 22 }
                var verticali = Path()
                var x: CGFloat = 0
                while x < size.width { verticali.addRect(CGRect(x: x, y: 0, width: 1, height: size.height)); x += 22 }
                strato.fill(orizzontali, with: .color(luce.opacity(0.03)))
                strato.fill(verticali, with: .color(luce.opacity(0.03)))
                let centro = CGPoint(x: size.width * 0.5, y: size.height * 0.3)
                let dx = max(centro.x, size.width - centro.x), dy = max(centro.y, size.height - centro.y)
                let raggio = (dx * dx + dy * dy).squareRoot()
                strato.blendMode = .destinationIn
                strato.fill(Path(tutto), with: .radialGradient(Gradient(stops: [.init(color: .black, location: 0.25),
                                                                                 .init(color: .black.opacity(0), location: 0.8)]),
                                                               center: centro, startRadius: 0, endRadius: raggio))
            }
            // il chiarore in alto: un cerchio di raggio √2 × 380 stretto in larghezza fino a √2 × metà foglio (l'ellisse del browser)
            let alta: CGFloat = 380
            let raggio = alta * CGFloat(2).squareRoot()
            var chiarore = gc
            chiarore.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: alta)))
            chiarore.translateBy(x: size.width / 2, y: 0)
            chiarore.scaleBy(x: size.width / 2 / alta, y: 1)
            chiarore.fill(Path(CGRect(x: -raggio, y: 0, width: 2 * raggio, height: alta)),
                          with: .radialGradient(Gradient(stops: [.init(color: luce.opacity(0.16), location: 0),
                                                                 .init(color: luce.opacity(0), location: 0.7)]),
                                                center: .zero, startRadius: 0, endRadius: raggio))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
