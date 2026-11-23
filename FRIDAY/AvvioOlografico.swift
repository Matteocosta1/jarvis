#if os(iOS)
import Foundation
import CoreGraphics
import SwiftUI

// MARK: - 20 nov · AVVIO «SINGOLO» (scelto dal signore sul mockup v33: «Singolo è veramente bello»)
// Le 6 icone in alto non arrivano più da destra: nascono una alla volta come ologramma GRANDE dove nasce la tab (in alto a destra),
// dentro un anello sottile che si riempie con la percentuale; ognuna si accende tremolando, resta un attimo e sul suo suono di
// caricamento si stringe e vola al suo posto, dove diventa l'icona vera con un lampo. Sotto l'anello la percentuale grande e
// PREFERENZE; su «operational» OPERATIVI, poi tutto si spegne tremolando.
// I tempi sono le parole vere della voce d'avvio (avvio.m4a, trascritta parola per parola, identici al mockup `VOCE_AVVIO`):
// «Importing (10,02) all preferences (10,64) … Systems are now fully operational (14,44)». Le icone si posano sui suoni di
// `Avvio.testaVoce`. Tutto è una funzione del tempo della traccia, ridisegnata a ogni fotogramma (120 Hz): niente ritardi in fila.

/// I posti delle 6 icone in alto (Social … Impostazioni), misurati nella schermata: lì l'ologramma si posa.
nonisolated struct PostiTesta: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// La partitura dell'avvio olografico (secondi dall'inizio della voce d'avvio, come `Avvio.testaVoce`).
enum AvvioOlo {
    static let importing = 10.02          // «Importing»: si accendono il campo, l'anello e la percentuale
    static let preferences = 10.64        // «preferences»: nasce il primo ologramma
    static let operational = 14.44        // «operational»: OPERATIVI e il lampo dell'anello
    static let spegni = 14.78             // si spegne tremolando…
    static let fine = 15.12               // …ed è sparito
    static let accensione = 0.34          // l'ologramma si accende
    static let accensioneAnello = 0.42    // anello e scritte si accendono
    static let volo = 0.28                // l'ologramma si stringe e vola al suo posto
    static let lato: CGFloat = 74         // l'ologramma grande (punti)
    static let raggio: CGFloat = 58       // l'anello

    /// La percentuale: 0 su «Importing», +1/6 a ogni suono di caricamento, 100 sull'ultimo (sale continua tra un suono e l'altro).
    static func percento(_ t: Double) -> Double {
        let tempi = Avvio.testaVoce
        guard t > importing, !tempi.isEmpty else { return 0 }
        let n = Double(tempi.count)
        for j in tempi.indices {
            let a = j == 0 ? importing : tempi[j - 1], b = tempi[j]
            if t <= b { return (Double(j) + (t - a) / (b - a)) / n * 100 }
        }
        return 100
    }

    /// Quando nasce l'ologramma `j`: il primo su «preferences», gli altri appena prima che il precedente parta in volo.
    static func nascita(_ j: Int) -> Double { j == 0 ? preferences : Avvio.testaVoce[j - 1] - 0.06 }

    /// L'accensione di un ologramma (come il mockup): trema (opacità 0 · ,8 · ,2 · ,95 · ,5 · 1), si rivela dall'alto, il lampo si spegne.
    static func accendi(_ u: Double) -> (opacita: Double, rivela: Double, luce: Double) {
        let x = min(1, max(0, u))
        return (spezzata(x, [(0, 0), (0.25, 0.8), (0.4, 0.2), (0.55, 0.95), (0.7, 0.5), (1, 1)]), x, 1.5 + (1 - 1.5) * x)
    }

    /// Lo spegnimento tremolante di tutta la scena.
    static func spento(_ t: Double) -> Double {
        guard t > spegni else { return 1 }
        return spezzata(min(1, (t - spegni) / (fine - spegni)), [(0, 1), (0.2, 0.3), (0.35, 0.85), (0.6, 0.1), (0.72, 0.5), (1, 0)])
    }

    /// Valore di una spezzata [(x, y)] in x (x crescenti, da 0 a 1).
    static func spezzata(_ x: Double, _ punti: [(Double, Double)]) -> Double {
        guard let primo = punti.first else { return 0 }
        if x <= primo.0 { return primo.1 }
        for k in 1..<punti.count where x <= punti[k].0 {
            let (x0, y0) = punti[k - 1], (x1, y1) = punti[k]
            return y0 + (y1 - y0) * (x - x0) / max(x1 - x0, 0.0001)
        }
        return punti[punti.count - 1].1
    }

    /// Curva di Bézier cubica come in CSS (`cubic-bezier(x1, y1, x2, y2)`), valutata in x.
    static func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        let x = min(1, max(0, x))
        func cx(_ s: Double) -> Double { 3 * x1 * s * (1 - s) * (1 - s) + 3 * x2 * s * s * (1 - s) + s * s * s }
        func cy(_ s: Double) -> Double { 3 * y1 * s * (1 - s) * (1 - s) + 3 * y2 * s * s * (1 - s) + s * s * s }
        var lo = 0.0, hi = 1.0, s = x
        for _ in 0..<24 {                                   // bisezione: stabile anche dove la curva è piatta
            s = (lo + hi) / 2
            if cx(s) < x { lo = s } else { hi = s }
        }
        return cy(s)
    }
}

/// La scena olografica dell'avvio, sopra titolo e reattore (non si tocca: i tocchi passano sotto). Identica al mockup Novità
/// (versione A3 «SINGOLO», `olo3Avvia`): stesse misure, stessi tempi, stesse curve.
struct AvvioOlografico: View {
    /// La chiave del riquadro della testata in `PostiTesta` (le icone sono 0…5).
    static let testata = -1

    /// L'istante in cui parte la voce d'avvio (il tempo 0 di `AvvioOlo` e di `Avvio.testaVoce`).
    let inizio: Date
    /// Avvio interrotto (voce sfumata prima): da qui si spegne tremolando come alla fine.
    let spegniDa: Date?
    /// La testata (titolo e icone), nello spazio di questa vista: sotto di lei, a destra, nasce la tab e lì nasce l'anello.
    let testata: CGRect?
    /// I disegni delle 6 icone in alto, nello spazio di questa vista: lì si posa l'ologramma.
    let posti: [CGRect]
    /// Quante icone vere sono già al loro posto: l'ologramma resta finché la sua icona non c'è (nessun fotogramma vuoto).
    let arrivate: Int

    // 20 nov, 06:06 (il signore: «deve essere quel ciano chiaro che non è bianco»): tutto nel ciano chiaro degli ologrammi di JARVIS
    // (#8FF0FF, lo stesso dell'ologramma della ruota), con gli aloni nel ciano pieno; prima era quasi bianco (#B4F7FF)
    private static let chiaro = Color(red: 1, green: 154 / 255, blue: 92 / 255)     // #8ff0ff
    private static let buio = Color(red: 12 / 255, green: 6 / 255, blue: 2 / 255)
    /// Il riquadro dell'anello (raggio 58 + le tacche), come `S` del mockup.
    private static let latoAnello: CGFloat = AvvioOlo.raggio * 2 + 8

    var body: some View {
        TimelineView(.animation) { ctx in
            scena(ctx.date.timeIntervalSince(inizio), spento: spegniDa.map { ctx.date.timeIntervalSince($0) })
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func scena(_ t: Double, spento: Double?) -> some View {
        if t >= AvvioOlo.importing, t < AvvioOlo.fine, let testata, posti.count == ContentView.postoTesta.totale {
            // come il mockup: il centro della zona dove nasce la tab (a 10 punti dal bordo, larga 212: W − 116) e 86 punti sotto
            // l'inizio della tab (6 punti sotto la testata, come FiloWidget)
            let cx: CGFloat = testata.maxX - 116
            let cy: CGFloat = testata.maxY + 6 + 86
            let p = AvvioOlo.percento(t)
            let acceso = AvvioOlo.accendi((t - AvvioOlo.importing) / AvvioOlo.accensioneAnello)
            let entra = AvvioOlo.bezier(0.2, 0.8, 0.2, 1, (t - AvvioOlo.importing) / AvvioOlo.accensioneAnello)
            let lampo = t > AvvioOlo.operational
                ? AvvioOlo.spezzata(min(1, (t - AvvioOlo.operational) / 0.56), [(0, 0), (0.3, 1), (1, 0)]) : 0
            // lo spegnimento: alla fine (14,78 s) o, se l'avvio è stato interrotto, da quel momento (stesso tremolio, 0,34 s)
            let visibile = min(AvvioOlo.spento(t), spento.map { AvvioOlo.spento(AvvioOlo.spegni + $0) } ?? 1)
            ZStack {
                // il campo di proiezione: un buio morbido senza bordi, perché la luce si legga sopra la corona (06:06: più trasparente,
                // la corona si intravede). Nel mockup è un cerchio da 250 col gradiente «circle» (che arriva all'angolo del riquadro:
                // 125 × √2), quindi le stesse percentuali qui sono su quel raggio
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Self.buio.opacity(0.68), location: 0), .init(color: Self.buio.opacity(0.68), location: 0.40),
                                                 .init(color: Self.buio.opacity(0.38), location: 0.58), .init(color: Self.buio.opacity(0), location: 0.72)],
                                         center: .center, startRadius: 0, endRadius: 176.78))   // 125 × √2
                    .frame(width: 250, height: 250)
                    .opacity(min(1, max(0, (t - AvvioOlo.importing) / 0.36)))
                    .position(x: cx, y: cy + 14)
                // l'anello con le tacche, che si riempie con la percentuale
                Anello(percento: p)
                    .frame(width: Self.latoAnello, height: Self.latoAnello)
                    .shadow(color: Color.ciano.opacity(0.8), radius: 2 + 5 * lampo)
                    .brightness(0.3 * (acceso.luce - 1) + 0.18 * lampo)
                    .mask { Rectangle().scaleEffect(x: 1, y: CGFloat(acceso.rivela), anchor: .top) }   // si rivela dall'alto
                    .opacity(acceso.opacita)
                    .scaleEffect(CGFloat(0.6 + 0.4 * entra))
                    .rotationEffect(.degrees(-40 * (1 - entra)))
                    .position(x: cx, y: cy)
                // la percentuale grande e la scritta, 12 punti sotto l'anello
                VStack(spacing: 0) {
                    Text("\(Int(p))%")
                        .font(.system(size: 22, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                    Text(t >= AvvioOlo.operational ? "OPERATIVI" : "PREFERENZE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundStyle(Self.chiaro)
                .shadow(color: Color.ciano.opacity(0.95), radius: 3)
                .shadow(color: Color.ciano.opacity(0.5), radius: 8)
                .brightness(0.3 * (acceso.luce - 1))
                .mask { Rectangle().scaleEffect(x: 1, y: CGFloat(acceso.rivela), anchor: .top) }
                .opacity(acceso.opacita)
                .fixedSize()
                .frame(width: 160, alignment: .top)
                .position(x: cx, y: cy + AvvioOlo.raggio + 12 + 19)
                // l'ologramma di turno (al cambio due per un attimo: uno vola via, l'altro si accende)
                ForEach(0..<posti.count, id: \.self) { j in
                    ologramma(j, t: t, cx: cx, cy: cy)
                }
            }
            .opacity(visibile)
        }
    }

    @ViewBuilder
    private func ologramma(_ j: Int, t: Double, cx: CGFloat, cy: CGFloat) -> some View {
        let posa = Avvio.testaVoce[min(j, Avvio.testaVoce.count - 1)]
        let nasce = AvvioOlo.nascita(j)
        let parte = posa - AvvioOlo.volo
        // finché la sua icona vera non è al suo posto (sul suo suono) l'ologramma c'è: fermo in fondo al volo, mai un fotogramma vuoto
        if t >= nasce, arrivate <= j {
            let m: CGFloat = AvvioOlo.lato / 18                               // l'icona vera è in un riquadro da 18 punti
            let acceso = AvvioOlo.accendi((t - nasce) / AvvioOlo.accensione)
            // il volo: si stringe fino alla misura dell'icona vera e arriva al suo posto esattamente sul suo suono (come il mockup:
            // a metà strada un terzo in orizzontale e metà in verticale, un filo più luminoso)
            let e = CGFloat(AvvioOlo.bezier(0.6, 0, 0.25, 1, (t - parte) / AvvioOlo.volo))
            let f: CGFloat = 1 / m, dx: CGFloat = posti[j].midX - cx, dy: CGFloat = posti[j].midY - cy
            let meta: CGFloat = (1 + f) / 2
            let a: CGFloat = min(1, e / 0.5), b: CGFloat = max(0, (e - 0.5) / 0.5)
            let sx: CGFloat = e < 0.5 ? 1 + (meta - 1) * a : meta + (f - meta) * b
            let ox: CGFloat = dx * 0.3 * a + dx * 0.7 * b
            let oy: CGFloat = dy * 0.55 * a + dy * 0.45 * b
            // come nel mockup la luce del volo prende il posto di quella dell'accensione (non si sommano)
            let luce: Double = t >= parte ? (e < 0.5 ? 1 + 0.25 * Double(a) : 1.25 - 0.15 * Double(b)) : acceso.luce
            AvvioOlografico.glifo(j, m: m)
                .frame(width: AvvioOlo.lato, height: AvvioOlo.lato)
                .foregroundStyle(Self.chiaro)
                .mask { RigheScansione() }                                     // le righe di scansione dell'ologramma
                .shadow(color: Color.ciano.opacity(0.9), radius: 1)
                .shadow(color: Color.ciano.opacity(0.6), radius: 5)
                .shadow(color: Color.ciano.opacity(0.3), radius: 11)
                .brightness(0.3 * (luce - 1))
                .mask { Rectangle().scaleEffect(x: 1, y: CGFloat(acceso.rivela), anchor: .top) }   // si rivela dall'alto
                .opacity(acceso.opacita)
                .blendMode(.screen)                                            // luce: si somma a quello che c'è sotto
                .scaleEffect(sx)
                .offset(x: ox, y: oy)
                .position(x: cx, y: cy)
        }
    }

    /// L'icona in alto `j` disegnata `m` volte più grande (stesse proporzioni e stesso tratto delle icone vere, `intestazione`).
    @ViewBuilder
    static func glifo(_ j: Int, m: CGFloat) -> some View {
        switch j {
        case ContentView.postoTesta.social:
            Image("GlifoInstagram").renderingMode(.template).resizable().interpolation(.high)
                .frame(width: 15 * m, height: 15 * m).padding(1.5 * m)
        case ContentView.postoTesta.musica:
            IconaVinile().frame(width: 18 * m, height: 18 * m)
        case ContentView.postoTesta.studio:
            IconaStudio(pieno: true).frame(width: 18 * m, height: 18 * m)
        case ContentView.postoTesta.sistemi:
            Image(systemName: "server.rack").font(.system(size: 11.8 * m, weight: .semibold))
        case ContentView.postoTesta.cestino:
            Image(systemName: "trash").font(.system(size: 13.9 * m, weight: .semibold))
        default:
            Image(systemName: "gearshape").font(.system(size: 14.4 * m, weight: .regular))
        }
    }
}

/// L'anello sottile con 60 tacche (una più lunga ogni cinque) e l'arco pieno della percentuale, da ore 12 in senso orario.
private struct Anello: View {
    let percento: Double
    var body: some View {
        Canvas { c, size in
            let centro = CGPoint(x: size.width / 2, y: size.height / 2), r = AvvioOlo.raggio
            let cerchio = Path(ellipseIn: CGRect(x: centro.x - r, y: centro.y - r, width: 2 * r, height: 2 * r))
            c.stroke(cerchio, with: .color(Color.ciano.opacity(0.18)), lineWidth: 1.5)
            var tacche = Path()
            for k in 0..<60 {
                let a = Double(k) / 60 * 2 * .pi, r1 = r + 4, r2 = r + (k % 5 == 0 ? 9 : 6)
                tacche.move(to: CGPoint(x: centro.x + cos(a) * r1, y: centro.y + sin(a) * r1))
                tacche.addLine(to: CGPoint(x: centro.x + cos(a) * r2, y: centro.y + sin(a) * r2))
            }
            c.stroke(tacche, with: .color(Color.ciano.opacity(0.45)), lineWidth: 1)
            if percento > 0 {
                var arco = Path()
                arco.addArc(center: centro, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(100, percento) / 100), clockwise: false)
                c.stroke(arco, with: .color(Color(red: 1, green: 154 / 255, blue: 92 / 255)), lineWidth: 2.2)
            }
        }
    }
}

/// Le righe di scansione di un ologramma, come il mockup: ogni 3 punti una riga di 1 punto che resta al 45 % (dal basso).
private struct RigheScansione: View {
    var body: some View {
        Canvas { c, size in
            var y: CGFloat = size.height
            while y > 0 {
                c.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 1)), with: .color(.black.opacity(0.45)))
                c.fill(Path(CGRect(x: 0, y: y - 3, width: size.width, height: 2)), with: .color(.black))
                y -= 3
            }
        }
    }
}
/// 13.7 · la scritta sotto J.A.R.V.I.S. (il signore, 22 nov 00:50: «con la stessa animazione dell'Apple Watch, le lettere che girano
/// come un computer»): ogni volta che cambia si decodifica lettera per lettera da sinistra, con tre caratteri che girano davanti,
/// partendo dalla scritta di prima (0,5 s), come `scriviSotto` del mockup «JARVIS Approvato».
struct TestoDecodificato: View {
    let testo: String
    var durata: Double = 0.5
    @State private var da = ""
    @State private var inizio: Date?
    private static let glifi = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|▪▫░▒")

    var body: some View {
        Group {
            if let inizio {
                TimelineView(.animation) { tl in
                    Text(TestoDecodificato.mescola(da, testo, min(1, tl.date.timeIntervalSince(inizio) / durata)))
                }
            } else {
                Text(testo)
            }
        }
        .onChange(of: testo) { vecchio, nuovo in
            guard !nuovo.isEmpty else { return }
            da = vecchio
            let t = Date()
            inizio = t
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(durata + 0.05))
                if inizio == t { inizio = nil }                          // finita: il testo fermo, niente più fotogrammi
            }
        }
    }

    /// Da `da` a `a`, a che punto `p`: le lettere scoperte di `a`, tre glifi sul fronte, poi il resto di `da`.
    private static func mescola(_ da: String, _ a: String, _ p: Double) -> String {
        guard p < 1 else { return a }
        let x = Array(da), y = Array(a), n = max(x.count, y.count), f = p * Double(n)
        var q = ""
        for i in 0..<n {
            if Double(i) < f { if i < y.count { q.append(y[i]) } }
            else if Double(i) < f + 3 { q.append(i < y.count && y[i] == " " ? " " : (glifi.randomElement() ?? " ")) }
            else if i < x.count { q.append(x[i]) }
        }
        return q
    }
}

#endif
