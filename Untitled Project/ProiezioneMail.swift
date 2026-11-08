#if os(iOS)
import SwiftUI
import UIKit

// MARK: - POSTA › la PROIEZIONE della mail (8 nov notte, scelta del signore alle 02:56: «PROIEZIONE va bene per mail»)
// Come il mockup v278 (MAIL_OLO «proiezione»): la riga toccata si accende; dalla sua linea due scansioni corrono in su e in giù e
// la scheda della mail si materializza fra loro, con un tremolio olografico che si assesta (0,40 s). Chiudendo («Chiudi», o un tocco
// fuori dalla scheda) la scheda si richiude sulla sua riga (0,26 s) e la riga si riaccende. Tirata giù dalla barra segue il dito e si
// chiude scivolando, come il foglio di prima; col «Riduci movimento» di iOS si apre e si chiude scivolando. Tutto a 120 Hz: le curve
// sono quelle del mockup e l'effetto è un modificatore animabile, ricalcolato a ogni fotogramma.
//
// 8 nov mattina (video del signore 06:32: la scheda partiva troppo in basso, il titolo usciva sopra la scheda, «Chiudi» e
// «Chiedi a JARVIS» sparivano): la scheda non si affida più ai margini di iOS. Tutto lo strato ignora i margini e la scheda ha
// misure sue, scritte qui: larga quanto lo schermo, dal bordo dell'ora (come il «top: 58px» del mockup) fino in fondo; dentro,
// il lettore non riceve margini (SenzaMargini: il suo fondo lo dà lui, sopra la barretta di iOS). La scheda si mette al suo posto
// spostandola (offset), senza margini sopra che iOS poteva raddoppiare. La luce e il colore del mockup (brightness e saturate) sono strati
// sopra la scheda (fusione «schiarisci colore» e «saturazione»), non filtri sul contenuto, che con le pagine che scorrono
// facevano sparire scritte e tasti.

/// Dove stanno le righe della posta sullo schermo (coordinate globali). Una scatola, non uno stato: scorrendo la lista le posizioni
/// cambiano di continuo e non devono ridisegnare niente; servono solo nel momento in cui la scheda si apre o si chiude.
final class PosizioniRighe {
    var righe: [String: CGRect] = [:]
}

struct ProiezioneMail<Contenuto: View>: View {
    /// Lo strato intero (globale): tutto lo schermo, dall'alto dell'ora al fondo.
    let schermo: CGRect
    /// Dove parte la scheda (globale): sotto l'ora, come nel mockup (top 58 del telefono). Si prende dalla finestra (FasciaAlta).
    let alto: CGFloat
    let tinta: Color
    /// Dove sta adesso la riga toccata (nil se non c'è più: allora si chiude scivolando).
    let riga: () -> CGRect?
    /// La riga si accende: all'apertura subito (0,42 s), alla chiusura verso la fine (0,52 s).
    let accendiRiga: (_ dopo: Double, _ durata: Double) -> Void
    /// La scheda è chiusa del tutto: via lo strato.
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

    /// Il bordo alto della scheda dentro lo strato.
    private var cima: CGFloat { max(0, alto - schermo.minY) }
    private var altezza: CGFloat { max(1, schermo.height - cima) }
    /// Il centro della riga, nelle coordinate della scheda.
    private var yRiga: CGFloat {
        guard let r = riga() else { return altezza / 2 }
        return min(altezza - 8, max(8, r.midY - schermo.minY - cima))
    }

    var body: some View {
        let larga = schermo.width
        let alta = altezza
        ZStack(alignment: .topLeading) {
            // 8 nov (LUCE, scelta del signore 09:49): dietro la scheda trasparente si vede la Posta, velata al 28 %
            Color.black.opacity(velo ? 0.28 : 0)
                .contentShape(Rectangle())
                .onTapGesture { chiudi() }                      // un tocco fuori dalla scheda, come iOS
            // LUCE: il bagliore ciano sopra la scheda (box-shadow 0 -10px 50px del mockup). Nella PROIEZIONE il mockup lo taglia
            // col clip-path finché la scheda non è aperta del tutto: qui c'è solo a fase 1 (letta fotogramma per fotogramma)
            let su = cima + tiro + (scivola ? (1 - fase) * alta : 0)
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(tinta.opacity(0.30))
                .frame(width: larga, height: alta)
                .blur(radius: 25)
                .offset(y: su - 10)
                .mask(alignment: .topLeading) { Rectangle().frame(width: larga, height: max(0, su)) }
                .modifier(SoloAperta(fase: fase, sempre: scivola))
                .allowsHitTesting(false)
            SenzaMargini(contenuto: contenuto(chiudi))          // dentro la scheda niente margini di iOS (li scrive il lettore)
                .frame(width: larga, height: alta)
                .modifier(EffettoProiezione(fase: fase, aprendo: aprendo, y: yRiga, altezza: alta, attivo: !scivola))
                .overlay(alignment: .topLeading) {
                    // la barra in alto (fuori dal «Chiudi»): si tira giù
                    Color.clear
                        .frame(width: max(0, larga - 110), height: 44)
                        .contentShape(Rectangle())
                        .gesture(trascina)
                }
                .offset(y: cima + tiro + (scivola ? (1 - fase) * alta : 0))
        }
        .frame(width: larga, height: schermo.height, alignment: .topLeading)
        .ignoresSafeArea()
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

    func body(content: Content) -> some View {
        let p = min(1, max(0, fase))
        let q = 1 - p                                                   // chiudendo: quanto è andata la chiusura
        // la finestra: dalla linea della riga verso l'alto e il basso (aperta, o niente effetto), con gli angoli alti di 32 punti
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
            .overlay {
                // brightness(luce) del mockup: «schiarisci colore» con un grigio 1 − 1/luce moltiplica ogni colore per luce
                // (il nero resta nero, il ciano si fa quasi bianco), come il filtro del mockup
                if luce > 1.001 {
                    Color(white: Double(1 - 1 / luce))
                        .blendMode(.colorDodge)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                // saturate(colore) del mockup: il grigio in «saturazione» toglie colore per quanto manca all'1
                if colore < 0.999 {
                    Color.gray
                        .blendMode(.saturation)
                        .opacity(Double(1 - colore))
                        .allowsHitTesting(false)
                }
            }
            .clipShape(FinestraScheda(cima: cima, fondo: fondo, raggio: 32))
            .opacity(Double(opacita))
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

/// La finestra della scheda (come il clip-path «inset(… round 32px 32px 0 0)» del mockup): dal bordo `cima` al bordo `fondo`,
/// gli angoli in alto arrotondati (mai più della sua altezza). A scheda aperta è la scheda intera.
struct FinestraScheda: Shape {
    let cima: CGFloat
    let fondo: CGFloat
    let raggio: CGFloat

    func path(in r: CGRect) -> Path {
        let alta = max(0, fondo - cima)
        let tondo = min(raggio, alta, r.width / 2)
        return UnevenRoundedRectangle(topLeadingRadius: tondo, topTrailingRadius: tondo, style: .continuous)
            .path(in: CGRect(x: r.minX, y: r.minY + cima, width: r.width, height: alta))
    }
}

/// 8 nov mattina (provato nel simulatore iPhone del banco di prova): il lettore senza i margini di iOS. Per SwiftUI la scheda tocca
/// la cima dello schermo e quindi ha il margine dell'ora: chiedendo di ignorarlo, il lettore si allargava di 59 punti verso l'alto
/// (la riga di «Chiudi» finiva sotto l'ora e il titolo sopra la scheda); senza chiederlo, il margine si sarebbe aggiunto (la scheda
/// partiva 59 punti più giù, il video delle 06:32). Qui il lettore sta in un ospite senza margini (safeAreaRegions vuote): occupa
/// esattamente la scheda, e il fondo sopra la barretta di iOS se lo dà lui.
private struct SenzaMargini<Contenuto: View>: UIViewControllerRepresentable {
    let contenuto: Contenuto

    func makeUIViewController(context: Context) -> UIHostingController<Contenuto> {
        let ospite = UIHostingController(rootView: contenuto)
        ospite.safeAreaRegions = []
        ospite.view.backgroundColor = .clear
        return ospite
    }

    func updateUIViewController(_ ospite: UIHostingController<Contenuto>, context: Context) {
        ospite.rootView = contenuto
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
/// Il bagliore di LUCE si vede solo a scheda aperta del tutto (la fase vera di ogni fotogramma, non quella d'arrivo); scivolando sempre.
private struct SoloAperta: ViewModifier, Animatable {
    var fase: CGFloat
    let sempre: Bool
    nonisolated var animatableData: CGFloat {
        get { fase }
        set { fase = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(sempre || fase > 0.999 ? 1 : 0)
    }
}

/// 8 nov (il signore, 09:49: «per MAIL la mia scelta è LUCE»): la scheda della mail olografica, come la prova LUCE del mockup v290.
/// Vetro trasparente (dietro si vede la Posta), la luce del proiettore che scende dall'alto, le righe di scansione fini, gli angoli
/// da mirino, il filo di luce sul bordo e una fascia di luce che attraversa la scheda dall'alto in basso ogni 4 s.
struct PelleLuce: View {
    let tinta: Color
    @Environment(\.sezioneDietro) private var dietro

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            ZStack(alignment: .topLeading) {
                // il vetro: il più leggero di iOS (nel mockup blur 5 e saturazione 1,4) e il fondo al 34 %
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Color(red: 2 / 255, green: 14 / 255, blue: 18 / 255).opacity(0.34)
                // la luce del proiettore: ellisse 130 % × 380 dall'alto, ciano al 30 %
                EllipticalGradient(colors: [tinta.opacity(0.30), tinta.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                    .frame(width: W * 2.6, height: 760)
                    .position(x: W / 2, y: 0)
                GrigliaSfumata()
                RigheLuce(tinta: tinta)
                AngoliLuce()
                if !dietro { ScansioneLuce(tinta: tinta, alta: H) }
                BordoLuce(tinta: tinta)
            }
            .frame(width: W, height: H, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Le righe di scansione della scheda: 1 punto ogni 3, ciano al 6 % (dal basso, come il gradiente del mockup).
private struct RigheLuce: View {
    let tinta: Color
    var body: some View {
        Canvas { gc, size in
            var p = Path()
            var y = size.height - 1
            while y > -1 { p.addRect(CGRect(x: 0, y: y, width: size.width, height: 1)); y -= 3 }
            gc.fill(p, with: .color(tinta.opacity(0.06)))
        }
    }
}

/// Gli angoli da mirino: L di 16 punti, spesse 1,5, a 12 dai lati; in alto a 52 (sotto la riga di «Chiudi»), in basso sopra i tasti.
private struct AngoliLuce: View {
    var body: some View {
        Canvas { gc, size in
            let W = size.width, H = size.height, l: CGFloat = 16, s: CGFloat = 1.5
            var p = Path()
            p.addRect(CGRect(x: 12, y: 52, width: l, height: s)); p.addRect(CGRect(x: 12, y: 52, width: s, height: l))
            p.addRect(CGRect(x: W - 12 - l, y: 52, width: l, height: s)); p.addRect(CGRect(x: W - 12 - s, y: 52, width: s, height: l))
            p.addRect(CGRect(x: 12, y: H - 96 - s, width: l, height: s)); p.addRect(CGRect(x: 12, y: H - 96 - l, width: s, height: l))
            p.addRect(CGRect(x: W - 12 - l, y: H - 96 - s, width: l, height: s)); p.addRect(CGRect(x: W - 12 - s, y: H - 96 - l, width: s, height: l))
            gc.fill(p, with: .color(Color(red: 120 / 255, green: 236 / 255, blue: 1).opacity(0.9)))
        }
    }
}

/// La scansione lenta: una fascia di luce (110 punti, più chiara sul bordo basso) che attraversa la scheda dall'alto in basso in
/// 2,2 s con la curva del mockup (0,45 0 0,55 1), poi una pausa; un giro ogni 4 s, a 120 Hz. Dietro si ferma.
private struct ScansioneLuce: View {
    let tinta: Color
    let alta: CGFloat
    private static let curva = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.45, y: 0), endControlPoint: UnitPoint(x: 0.55, y: 1))
    var body: some View {
        TimelineView(.animation) { t in
            let c = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4
            let p = c < 0.55 ? Self.curva.value(at: c / 0.55) : 1
            let bordo = 2 * alta * CGFloat(p)
            LinearGradient(stops: [.init(color: tinta.opacity(0), location: 0),
                                   .init(color: tinta.opacity(0.10), location: 80 / 110),
                                   .init(color: Color(red: 190 / 255, green: 248 / 255, blue: 1).opacity(0.40), location: 109 / 110),
                                   .init(color: tinta.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .offset(y: bordo - 110)
                .opacity(bordo > 0 && bordo < alta + 110 ? 1 : 0)
        }
    }
}

/// Il filo di luce sul bordo (lati e angoli alti di 32, come la scheda): in alto più chiaro, sui lati ciano al 50 %; dentro, un alone.
private struct BordoLuce: View {
    let tinta: Color
    private struct Bordo: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + 32))
            p.addArc(center: CGPoint(x: r.minX + 32, y: r.minY + 32), radius: 32, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX - 32, y: r.minY))
            p.addArc(center: CGPoint(x: r.maxX - 32, y: r.minY + 32), radius: 32, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            return p
        }
    }
    var body: some View {
        ZStack {
            Bordo().stroke(tinta.opacity(0.14), lineWidth: 60).blur(radius: 30)
            Bordo().stroke(LinearGradient(stops: [.init(color: Color(red: 190 / 255, green: 248 / 255, blue: 1).opacity(0.95), location: 0),
                                                  .init(color: tinta.opacity(0.5), location: 0.06)],
                                          startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
        }
    }
}
#endif
