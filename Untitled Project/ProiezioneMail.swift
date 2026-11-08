#if os(iOS)
import SwiftUI

// MARK: - POSTA › la PROIEZIONE della mail (8 nov notte, scelta del signore alle 02:56: «PROIEZIONE va bene per mail»)
// Come il mockup v278 (MAIL_OLO «proiezione»): la riga toccata si accende; dalla sua linea due scansioni corrono in su e in giù e
// la scheda della mail si materializza fra loro, con un tremolio olografico che si assesta (0,40 s). Chiudendo («Chiudi», o un tocco
// fuori dalla scheda) la scheda si richiude sulla sua riga (0,26 s) e la riga si riaccende. Tirata giù dalla barra segue il dito e si
// chiude scivolando, come il foglio di prima; col «Riduci movimento» di iOS si apre e si chiude scivolando. Tutto a 120 Hz: le curve
// sono quelle del mockup e l'effetto è un modificatore animabile, ricalcolato a ogni fotogramma.

/// Dove stanno le righe della posta sullo schermo (coordinate globali). Una scatola, non uno stato: scorrendo la lista le posizioni
/// cambiano di continuo e non devono ridisegnare niente; servono solo nel momento in cui la scheda si apre o si chiude.
final class PosizioniRighe {
    var righe: [String: CGRect] = [:]
}

struct ProiezioneMail<Contenuto: View>: View {
    /// Lo schermo intero (globale), dall'alto dell'ora al fondo.
    let schermo: CGRect
    /// Dove parte la scheda (globale): sotto l'ora, come nel mockup (top 58 del telefono). Si prende dalla finestra (FasciaAlta),
    /// perché nel contenitore della MARK XI il margine dell'ora a volte vale 0 (come SchermoCaricamento).
    let alto: CGFloat
    let tinta: Color
    /// Dove sta adesso la riga toccata (nil se non c'è più: allora si chiude scivolando).
    let riga: () -> CGRect?
    /// La riga si accende: all'apertura subito (0,42 s), alla chiusura verso la fine (0,52 s).
    let accendiRiga: (_ dopo: Double, _ durata: Double) -> Void
    /// La scheda è chiusa del tutto: via l'overlay.
    let fine: () -> Void
    let contenuto: (_ chiudi: @escaping () -> Void) -> Contenuto

    // l'init esplicito: con gli stati privati sotto, quello automatico sarebbe visibile solo in questo file
    init(schermo: CGRect, alto: CGFloat, tinta: Color, riga: @escaping () -> CGRect?,
         accendiRiga: @escaping (_ dopo: Double, _ durata: Double) -> Void, fine: @escaping () -> Void,
         @ViewBuilder contenuto: @escaping (_ chiudi: @escaping () -> Void) -> Contenuto) {
        self.schermo = schermo
        self.alto = alto
        self.tinta = tinta
        self.riga = riga
        self.accendiRiga = accendiRiga
        self.fine = fine
        self.contenuto = contenuto
    }

    @Environment(\.accessibilityReduceMotion) private var riduci
    @State private var fase: CGFloat = 0            // 0 chiusa · 1 aperta
    @State private var aprendo = true
    @State private var scivola = false              // apertura/chiusura che scivola dal basso (tirata giù, Riduci movimento)
    @State private var velo = false
    @State private var tiro: CGFloat = 0
    @State private var via = false

    /// Il bordo alto della scheda dentro l'overlay.
    private var cima: CGFloat { max(0, alto - schermo.minY) }
    private var altezza: CGFloat { max(1, schermo.height - cima) }
    /// Il centro della riga, nelle coordinate della scheda.
    private var yRiga: CGFloat {
        guard let r = riga() else { return altezza / 2 }
        return min(altezza - 8, max(8, r.midY - schermo.minY - cima))
    }

    var body: some View {
        let H = altezza
        ZStack(alignment: .top) {
            Color.black.opacity(velo ? 0.45 : 0)
                .contentShape(Rectangle())
                .onTapGesture { chiudi() }                      // un tocco fuori dalla scheda, come iOS
            contenuto(chiudi)
                .ignoresSafeArea()                                  // i margini li dà la scheda (ora sopra, barra di iOS sotto)
                .frame(width: schermo.width, height: H)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
                .overlay(alignment: .topLeading) {
                    // la barra in alto (fuori dal «Chiudi»): si tira giù
                    Color.clear
                        .frame(width: max(0, schermo.width - 110), height: 44)
                        .contentShape(Rectangle())
                        .gesture(trascina)
                }
                .modifier(EffettoProiezione(fase: fase, aprendo: aprendo, y: yRiga, altezza: H, attivo: !scivola))
                .padding(.top, cima)
                .offset(y: tiro + (scivola ? (1 - fase) * H : 0))
        }
        .frame(width: schermo.width, height: schermo.height, alignment: .top)
        .onAppear(perform: apri)
    }

    private var trascina: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in if !via { tiro = max(0, v.translation.height) } }
            .onEnded { v in
                guard !via else { return }
                let veloce = v.velocity.height > 800                  // come il mockup: oltre un terzo o una spinta (0,8 px/ms)
                if tiro > altezza / 3 || veloce { chiudiScivolando() }
                else { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) { tiro = 0 } }
            }
    }

    private func apri() {
        withAnimation(.easeOut(duration: 0.32)) { velo = true }
        if riduci || riga() == nil {
            scivola = true
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) { fase = 1 }
            return
        }
        aprendo = true
        accendiRiga(0, 0.42)
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.40)) { fase = 1 }
    }

    private func chiudi() {
        guard !via else { return }
        if scivola || riduci || riga() == nil { chiudiScivolando(); return }
        via = true
        aprendo = false
        accendiRiga(0.20, 0.52)
        withAnimation(.easeOut(duration: 0.26)) { velo = false }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)) { fase = 0 } completion: { fine() }
    }

    private func chiudiScivolando() {
        guard !via else { return }
        via = true
        scivola = true
        withAnimation(.easeOut(duration: 0.32)) { velo = false }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) { fase = 0 } completion: { fine() }
    }
}

/// L'effetto PROIEZIONE, fotogramma per fotogramma: la finestra che si apre dalla riga, le due scansioni, il tremolio e la luce
/// olografica che si spegne. Le tappe (offset) sono quelle del mockup, sul tempo già passato per la curva, come in Web Animations.
struct EffettoProiezione: ViewModifier, Animatable {
    var fase: CGFloat
    let aprendo: Bool
    let y: CGFloat
    let altezza: CGFloat
    let attivo: Bool

    // nonisolated: SwiftUI la legge e la scrive dall'animazione (come Rivela in OlogrammaFoto)
    nonisolated var animatableData: CGFloat {
        get { fase }
        set { fase = newValue }
    }

    // le tappe del mockup: (punto della corsa, valore). Aprendo sul punto dell'apertura, chiudendo su quello della chiusura.
    private static let opacitaApre: [(CGFloat, CGFloat)] = [(0, 0.2), (0.2, 0.85), (0.3, 0.45), (0.55, 1), (1, 1)]
    private static let opacitaChiude: [(CGFloat, CGFloat)] = [(0, 1), (0.5, 0.9), (1, 0.2)]
    private static let luceApre: [(CGFloat, CGFloat)] = [(0, 1.9), (0.55, 1.3), (1, 1)]
    private static let luceChiude: [(CGFloat, CGFloat)] = [(0, 1), (0.5, 1.5), (1, 1.9)]
    private static let coloreApre: [(CGFloat, CGFloat)] = [(0, 0.5), (0.55, 0.8), (1, 1)]
    private static let coloreChiude: [(CGFloat, CGFloat)] = [(0, 1), (0.5, 0.7), (1, 0.5)]

    /// Una spezzata: il valore fra due tappe è la retta fra le due.
    private static func tratto(_ x: CGFloat, _ k: [(CGFloat, CGFloat)]) -> CGFloat {
        guard let primo = k.first, let ultimo = k.last else { return 0 }
        if x <= primo.0 { return primo.1 }
        for i in 1..<k.count where x <= k[i].0 {
            let (a, b) = (k[i - 1], k[i])
            return a.1 + (b.1 - a.1) * (x - a.0) / max(0.0001, b.0 - a.0)
        }
        return ultimo.1
    }

    /// Quanto si vedono le due scansioni (1 → 0,85 → spente aprendo; accese dai bordi → piene sulla riga chiudendo).
    private static func luceLinee(p: CGFloat, q: CGFloat, corsa: CGFloat, aprendo: Bool) -> CGFloat {
        if aprendo {
            if p >= 1 { return 0 }
            return p < 0.82 ? 1 - 0.15 * p / 0.82 : 0.85 * (1 - (p - 0.82) / 0.18)
        }
        if q <= 0 { return 0 }
        return q < 0.15 ? 0.85 * q / 0.15 : 0.85 + 0.15 * corsa
    }

    @ViewBuilder func body(content: Content) -> some View {
        let p = min(1, max(0, fase))
        let q = 1 - p                                                   // chiudendo: quanto è andata la chiusura
        // la finestra: dalla linea della riga verso l'alto e il basso (aperta, o niente effetto)
        let cima = attivo ? y * (1 - p) : 0
        let fondo = attivo ? y + (altezza - y) * p : altezza
        // tremolio, luce e colore (tappe del mockup)
        let x: CGFloat = aprendo ? p : q
        let opacita: CGFloat = attivo ? Self.tratto(x, aprendo ? Self.opacitaApre : Self.opacitaChiude) : 1
        let luce: CGFloat = attivo ? Self.tratto(x, aprendo ? Self.luceApre : Self.luceChiude) : 1
        let colore: CGFloat = attivo ? Self.tratto(x, aprendo ? Self.coloreApre : Self.coloreChiude) : 1
        // le due scansioni: corrono dalla riga ai bordi (aprendo) o dai bordi alla riga (chiudendo)
        let corsa = aprendo ? min(1, p / 0.82) : max(0, (q - 0.15) / 0.85)
        let su = aprendo ? y * (1 - corsa) : y * corsa
        let giu = aprendo ? y + (altezza - y) * corsa : altezza - (altezza - y) * corsa
        let lineeOp: CGFloat = attivo ? Self.luceLinee(p: p, q: q, corsa: corsa, aprendo: aprendo) : 0
        content
            .saturation(Double(colore))
            .overlay {
                // la «luminosità» del mockup (brightness > 1): luce ciano-bianca sommata, che si spegne
                Color(red: 0.75, green: 0.96, blue: 1)
                    .opacity(Double(max(0, luce - 1)) * 0.32)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .opacity(Double(opacita))
            .mask(alignment: .top) {
                Rectangle()
                    .frame(height: max(0, fondo - cima))
                    .padding(.top, cima)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    LineaScansione().offset(y: su - 1)
                    LineaScansione().offset(y: giu - 1)
                }
                .opacity(Double(max(0, lineeOp)))
                .allowsHitTesting(false)
            }
    }
}

/// Una scansione: 2 punti di luce ciano-bianca, sfumata ai lati, con l'alone (come .lmo-riga del mockup).
private struct LineaScansione: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Color(red: 0.75, green: 0.96, blue: 1).opacity(0), location: 0),
                               .init(color: Color(red: 0.75, green: 0.96, blue: 1).opacity(0.95), location: 0.1),
                               .init(color: Color(red: 0.75, green: 0.96, blue: 1).opacity(0.95), location: 0.9),
                               .init(color: Color(red: 0.75, green: 0.96, blue: 1).opacity(0), location: 1)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: 2)
            .shadow(color: Color.ciano.opacity(0.75), radius: 6)
            .shadow(color: Color.ciano.opacity(0.25), radius: 17)
    }
}
#endif
