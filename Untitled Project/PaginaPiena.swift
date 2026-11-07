#if os(iOS)
import SwiftUI
import UIKit

// MARK: - 26 ott sera (il signore: «nessuna arriva in cima a pagina piena»): tutte le schede di JARVIS a pagina piena, come il mockup
// Salgono dal basso fino in cima (non più il foglio di iOS che si ferma sotto l'ora), si chiudono con «Chiudi» o trascinando giù
// dalla parte alta dello schermo (la fascia dell'ora). Sotto resta JARVIS: scendendo si vede lui, mai nero.

struct PaginaPiena: ViewModifier {
    @Environment(\.chiudiOVia) private var chiudi
    @State private var scesa: CGFloat = 0

    /// L'altezza della fascia in alto (ora, Dynamic Island) dove parte il trascinamento: lì non ci sono tasti delle schede.
    private var finestra: UIWindow? { FasciaAlta.finestra }
    private var fascia: CGFloat { FasciaAlta.altezza }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fondo.ignoresSafeArea())
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
    /// Al posto di `dismiss`: dentro il contenitore chiude la sezione; in un foglio presentato, il foglio.
    var chiudiOVia: ChiudiOVia { ChiudiOVia(sezione: isPresented ? nil : sezioneAperta, dismiss: dismiss) }
}

struct StratoPagina: View {
    let apertura: AperturaPagina
    let parla: (String) -> Void
    /// Fa scendere lo strato e lo toglie (la schermata principale, con la durata della discesa).
    let chiudi: (Double) -> Void
    /// Il dito sta tirando giù lo strato e sotto si vede JARVIS (vero), o lo strato è tornato su del tutto (falso): con JARVIS
    /// in vista le sue animazioni devono girare (jarvisCoperto).
    let jarvisSiVede: (Bool) -> Void
    @State private var scesa: CGFloat = 0
    @State private var chiusa = false                    // già in discesa: un secondo «Chiudi» non fa niente

    /// 26 ott sera (il signore: «Studio e Social uguali alle altre schede»): la salita e la discesa delle altre schede, misurate
    /// fotogramma per fotogramma sul suo video delle 21:58 (SATELLITE, 60 fotogrammi al secondo): salita ~0,3 s che frena in
    /// fondo, discesa ~0,35 s che parte piano e si posa piano. Sono le molle di iOS che le ricalcano (scarto sotto l'1%).
    // 27 ott notte (10.0 16): lo strato scende di tutta l'altezza dello schermo, come le altre schede di iOS: stessi tempi delle
    // altre schede (misurati sul video di SATELLITE), quindi stessa durata e stessa velocità.
    static let salita: Animation = .spring(response: 0.34, dampingFraction: 0.9)
    /// Dopo il trascinamento col dito: 0,22 s e frena, come le altre schede (PaginaPiena), il dito l'ha già portata giù.
    static func discesa(_ durata: Double = 0.35) -> Animation {
        durata > 0.3 ? .spring(response: 0.33, dampingFraction: 1) : .easeOut(duration: durata)
    }

    var body: some View {
        VistaStudio(apertura: apertura, parla: parla, chiudi: { vaGiu(0.35) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fondo)
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: FasciaAlta.altezza + 8)
                    .contentShape(Rectangle())
                    .gesture(trascina)
            }
            .offset(y: scesa)
            .ignoresSafeArea()
    }

    private func vaGiu(_ durata: Double) {
        guard !chiusa else { return }
        chiusa = true
        chiudi(durata)
    }

    private var trascina: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                guard !chiusa else { return }
                if scesa == 0, v.translation.height > 0 { jarvisSiVede(true) }
                scesa = max(0, v.translation.height)
            }
            .onEnded { v in
                guard !chiusa else { return }
                if v.translation.height > 140 || v.predictedEndTranslation.height > 420 {
                    vaGiu(0.22)
                } else {
                    withAnimation(.spring(duration: 0.3)) { scesa = 0 }
                    Task { @MainActor in                         // tornato su del tutto: JARVIS sotto è di nuovo coperto
                        try? await Task.sleep(for: .milliseconds(350))
                        if !chiusa, scesa == 0 { jarvisSiVede(false) }
                    }
                }
            }
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
struct SfondoSezione: View {
    var tinta: Color = .ciano

    var body: some View {
        ZStack {
            Color.fondo
            GrigliaSfumata()
            RadialGradient(colors: [tinta.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
