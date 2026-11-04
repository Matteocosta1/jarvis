import Foundation
import SwiftUI
import UIKit

// MARK: - FOTO in ologramma (11.0 (3), 4 nov) — come il mockup v247 approvato
// Il pannello dell'analisi della galleria: la foto che l'AI sta leggendo (un esempio ogni 1,5 s: il conto vero va molto più
// veloce), con il laser che la legge riga per riga (lo stesso dell'AGGANCIO), le cose trovate con la fiducia, l'aggancio, poi
// la foto scende nel proiettore (l'indice) e l'anello del proiettore si riempie con l'avanzamento. Dietro, la coda.
// Poi i quadratini nuovi della ricerca che si materializzano col laser, e le parole capite sotto il campo.

/// Il pannello dell'analisi: il conto, l'ologramma, la barra, il ritmo e quanto manca. Finita: «ANALISI COMPLETA».
struct PannelloAnalisi: View {
    @ObservedObject var analisi: AvanzamentoFoto
    let tinta: Color
    let completa: Bool
    @State private var misure: [(Date, Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(intestazione)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(completa ? Color.white : tinta)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Text("\(percento)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(tinta)
                    .contentTransition(.numericText())
            }
            .animation(.easeOut(duration: 0.2), value: analisi.fatte)
            OlogrammaAnalisi(analisi: analisi)
                .frame(height: 150)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(tinta.opacity(0.14))
                    Capsule().fill(tinta)
                        .frame(width: g.size.width * frazione)
                        .shadow(color: tinta.opacity(0.9), radius: 4)
                }
            }
            .frame(height: 3)
            .animation(.linear(duration: 0.25), value: analisi.fatte)
            Text(completa ? "Ora cerco in tutta la galleria." : ritmo)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tenue)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinta.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tinta.opacity(0.22), lineWidth: 1))
        .overlay { AngoliOlo(tinta: tinta).padding(-1).allowsHitTesting(false) }
        .onChange(of: analisi.fatte, initial: true) { _, n in
            let ora = Date()
            misure.append((ora, n))
            while misure.count > 2, let prima = misure.first, ora.timeIntervalSince(prima.0) > 4 { misure.removeFirst() }
        }
    }

    private var intestazione: String {
        completa ? "ANALISI COMPLETA · \(PannelloAnalisi.numero(analisi.totale)) FOTO"
                 : "ANALISI · \(PannelloAnalisi.numero(analisi.fatte)) / \(PannelloAnalisi.numero(analisi.totale))"
    }

    private var frazione: CGFloat { completa ? 1 : CGFloat(analisi.totale > 0 ? Double(analisi.fatte) / Double(analisi.totale) : 0) }
    private var percento: Int { completa ? 100 : analisi.totale > 0 ? analisi.fatte * 100 / analisi.totale : 0 }

    /// «45 foto al secondo · fine fra 3 min», dalle foto analizzate negli ultimi 4 secondi.
    private var ritmo: String {
        guard let a = misure.first, let b = misure.last, b.0.timeIntervalSince(a.0) > 0.6, b.1 > a.1 else { return " " }
        let r = Double(b.1 - a.1) / b.0.timeIntervalSince(a.0), resta = Double(max(0, analisi.totale - analisi.fatte)) / max(0.1, r)
        let fine = resta > 90 ? "\(Int((resta / 60).rounded())) min" : "\(max(5, Int((resta / 5).rounded()) * 5)) s"
        return "\(Int(r.rounded())) foto al secondo · fine fra \(fine)"
    }

    /// I numeri con il punto delle migliaia («8.312»).
    static func numero(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: "it_IT"))) }
}

/// Il giro dell'ologramma: la foto di adesso, la prossima già pronta, quando è cominciato il giro, le onde delle foto archiviate.
/// Non è osservato: il disegno lo rilegge a ogni fotogramma.
final class RegiaAnalisi {
    struct Pronto {
        let immagine: Image
        let cose: [CampioneFoto.CosaTrovata]
    }
    var corrente: Pronto?
    var prossimo: Pronto?
    var inizio = Date.distantPast
    var fine: Date?
    var impulsi: [Date] = []
    var archiviata = false
    let zero = Date()
    static let durata = 1.5

    /// A ogni fotogramma: finito il giro, se c'è la prossima foto si comincia il giro nuovo (sennò si aspetta, col proiettore).
    func passo(_ adesso: Date) -> Double {
        if fine == nil, adesso.timeIntervalSince(inizio) >= RegiaAnalisi.durata, let p = prossimo {
            corrente = p
            prossimo = nil
            inizio = adesso
            archiviata = false
        }
        return adesso.timeIntervalSince(inizio)
    }
}

/// L'ologramma dell'analisi. Con «Riduci movimento» la foto resta ferma, agganciata con le sue cose.
struct OlogrammaAnalisi: View {
    @ObservedObject var analisi: AvanzamentoFoto
    @State private var regia = RegiaAnalisi()
    @State private var foto = 0                       // sale a ogni foto pronta: col disegno fermo lo fa ridisegnare
    @Environment(\.accessibilityReduceMotion) private var riduci
    @Environment(\.sezioneDietro) private var dietro  // 4 nov: la sezione dietro (MARK XI): l'ologramma si ferma

    var body: some View {
        let finita = !analisi.attivo, avanti = analisi.totale > 0 ? min(1, Double(analisi.fatte) / Double(analisi.totale)) : 0
        TimelineView(.animation(minimumInterval: nil, paused: riduci || dietro)) { ctx in
            let adesso = ctx.date, giro = foto
            Canvas { gc, size in
                _ = giro
                DisegnoAnalisi.disegna(&gc, size, adesso: adesso, regia: regia, avanti: avanti, finita: finita, fermo: riduci)
            }
        }
        .task(id: analisi.campione) { await prepara(analisi.campione) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// La foto del campione, piccola, in luce; poi è la prossima del giro.
    private func prepara(_ c: CampioneFoto?) async {
        guard let c, let img = await FotoLocali.immagine(id: c.id, lato: 252), !Task.isCancelled else { return }
        let pronto = RegiaAnalisi.Pronto(immagine: Image(uiImage: DisegnoAnalisi.luce(img, lato: 84)), cose: c.cose)
        if riduci { regia.corrente = pronto } else { regia.prossimo = pronto }
        foto += 1
    }
}

enum DisegnoAnalisi {
    private static let e = 0.14, s = 0.78, a0 = 1.16, a1 = 0.22

    /// Il nome che sta in `posti` caratteri: se è più lungo, i primi e «…» (4 nov, i nomi lunghi sugli iPhone piccoli).
    nonisolated static func accorcia(_ nome: String, _ posti: Int) -> String {
        guard nome.count > posti else { return nome }
        guard posti > 1 else { return posti == 1 ? "…" : "" }
        return String(nome.prefix(posti - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// La foto in luce: il contrasto tirato, la luce della foto col colore dell'ologramma, il fondo mai spento, l'interlinea.
    static func luce(_ foto: UIImage, lato: CGFloat) -> UIImage {
        let quadro = CGRect(x: 0, y: 0, width: lato, height: lato)
        let k = max(lato / max(1, foto.size.width), lato / max(1, foto.size.height))
        let dentro = CGRect(x: (lato - foto.size.width * k) / 2, y: (lato - foto.size.height * k) / 2, width: foto.size.width * k, height: foto.size.height * k)
        return UIGraphicsImageRenderer(size: quadro.size).image { ctx in
            let c = ctx.cgContext
            c.clip(to: quadro)
            foto.draw(in: dentro)
            foto.draw(in: dentro, blendMode: .softLight, alpha: 1)
            c.setBlendMode(.color)
            UIColor(red: 143 / 255, green: 240 / 255, blue: 1, alpha: 1).setFill()
            c.fill(quadro)
            c.setBlendMode(.screen)
            UIColor(red: 79 / 255, green: 227 / 255, blue: 1, alpha: 0.1).setFill()
            c.fill(quadro)
            c.setBlendMode(.normal)
            UIColor(white: 0, alpha: 0.5).setFill()
            var y: CGFloat = 1
            while y < lato { c.fill(CGRect(x: 0, y: y, width: lato, height: 1)); y += 2 }
        }
    }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, adesso: Date, regia: RegiaAnalisi, avanti: Double, finita: Bool, fermo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 40, h > 40 else { return }
        gc.blendMode = .plusLighter
        let p = min(84, h * 0.56), cx = min(w * 0.23, 76), top = 24.0, cy = top + p / 2, base = h - 13, rx = p * 0.64, ry = rx * 0.17
        let t = adesso.timeIntervalSince(regia.zero)
        if fermo, regia.corrente == nil, let q = regia.prossimo { regia.corrente = q; regia.prossimo = nil }
        if finita, regia.fine == nil, regia.corrente != nil { regia.fine = adesso }
        var u = regia.passo(adesso)
        if regia.fine != nil || fermo { u = a0 - 0.001 }          // finita (o ferma): l'ultima foto resta agganciata
        // il proiettore: l'ellisse, le tacche che girano, l'anello dell'avanzamento, le onde delle foto archiviate
        gc.stroke(Olo.ellisse(cx, base, rx, ry), with: .color(Olo.azzurro.opacity(0.3)), lineWidth: 1)
        var tacche = Path()
        for i in 0..<40 {
            let a = Double(i) / 40 * 2 * .pi + t * 0.3, c = cos(a), sn = sin(a), l = i % 5 != 0 ? 0.88 : 0.78
            Olo.linea(&tacche, cx + c * rx, base + sn * ry, cx + c * rx * l, base + sn * ry * l)
        }
        gc.stroke(tacche, with: .color(Olo.ciano.opacity(0.45)), style: Olo.tratto(1))
        if avanti > 0 {
            var anello = Path()
            Olo.arco(&anello, cx, base, rx * 1.08, ry * 1.08, -Double.pi / 2, -Double.pi / 2 + 2 * .pi * avanti)
            gc.stroke(anello, with: .color(Olo.bianco.opacity(0.85)), style: Olo.tratto(2))
        }
        regia.impulsi.removeAll { adesso.timeIntervalSince($0) >= 0.6 }
        for t0 in regia.impulsi {
            let v = adesso.timeIntervalSince(t0) / 0.6, k = 1 - pow(1 - v, 2)
            gc.stroke(Olo.ellisse(cx, base, rx * (0.3 + 0.8 * k), ry * (0.3 + 0.8 * k)), with: .color(Olo.ciano.opacity(0.6 * (1 - v))), lineWidth: 1.2)
        }
        // il cono di luce
        var cono = Path()
        cono.move(to: CGPoint(x: cx - rx * 0.5, y: base))
        cono.addLine(to: CGPoint(x: cx - p * 0.62, y: top + p * 0.1))
        cono.addLine(to: CGPoint(x: cx + p * 0.62, y: top + p * 0.1))
        cono.addLine(to: CGPoint(x: cx + rx * 0.5, y: base))
        cono.closeSubpath()
        gc.fill(cono, with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0.12), Olo.azzurro.opacity(0)]),
                                            startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: top)))
        // la coda: le prossime foto, una dietro l'altra (solo i contorni); all'inizio del giro avanzano di un posto
        let k = u < e ? Olo.liscia(u / e) : 1
        let posa: (Int) -> (x: Double, y: Double, s: Double, a: Double) = { i in
            (x: cx + 9 * Double(i), y: cy - 6 * Double(i), s: 1 - 0.07 * Double(i), a: max(0, 0.42 - 0.12 * Double(i)))
        }
        if regia.fine == nil {
            for i in stride(from: 3, through: 1, by: -1) {
                let q0 = posa(i + 1), q1 = posa(i)
                let px = q0.x + (q1.x - q0.x) * k, py = q0.y + (q1.y - q0.y) * k, ps = (q0.s + (q1.s - q0.s) * k) * p, pa = q0.a + (q1.a - q0.a) * k
                gc.stroke(Path(CGRect(x: px - ps / 2, y: py - ps / 2, width: ps, height: ps)), with: .color(Olo.ciano.opacity(pa)), lineWidth: 1)
            }
        }
        guard let cur = regia.corrente else { return }
        // la foto davanti: entra dalla coda, il laser la legge, si aggancia, poi scende nel proiettore
        let q0 = posa(1), pkx = q0.x + (cx - q0.x) * k, pky = q0.y + (cy - q0.y) * k, pks = (q0.s + (1 - q0.s) * k) * p
        var sy = 1.0, dy = 0.0, alfa = 1.0
        if u >= a0 {
            let q = min(1, (u - a0) / a1)
            sy = 1 - 0.97 * Olo.liscia(min(1, q * 1.6))
            dy = (base - cy) * Olo.liscia(max(0, q * 1.6 - 0.6))
            alfa = 1 - 0.5 * q
            if q >= 1, !regia.archiviata { regia.impulsi.append(adesso); regia.archiviata = true }
        }
        let sl = pkx - pks / 2, st = pky + dy - pks * sy / 2, sw = pks, sh = pks * sy
        let f = u < e ? 0 : min(1, (u - e) / s), fl = 0.5 - 0.5 * cos(.pi * f), ly = st + sh * fl
        if u < a0 + a1 {
            let letta = u >= e + s ? sh : max(0, ly - st)
            gc.drawLayer { l in
                l.clip(to: Path(CGRect(x: sl, y: st, width: sw, height: letta)))
                l.opacity = alfa
                l.draw(cur.immagine, in: CGRect(x: sl, y: st, width: sw, height: sh))
            }
            gc.stroke(Path(CGRect(x: sl, y: st, width: sw, height: sh)), with: .color(Olo.ciano.opacity(0.55 * alfa)), lineWidth: 1)
            if u < e + s && sh > 4 {   // ancora da leggere: solo la griglia; il laser con il bagliore e i lampi ai lati
                var griglia = Path()
                for g in 1..<4 {
                    let yy = st + sh * Double(g) / 4, xx = sl + sw * Double(g) / 4
                    if yy > ly { Olo.linea(&griglia, sl, yy, sl + sw, yy) }
                    Olo.linea(&griglia, xx, max(ly, st), xx, st + sh)
                }
                gc.stroke(griglia, with: .color(Olo.azzurro.opacity(0.2)), lineWidth: 1)
                if u >= e {
                    gc.fill(Path(CGRect(x: sl - 6, y: ly - 8, width: sw + 12, height: 16)),
                            with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0), Olo.azzurro.opacity(0.4), Olo.azzurro.opacity(0)]),
                                                  startPoint: CGPoint(x: 0, y: ly - 8), endPoint: CGPoint(x: 0, y: ly + 8)))
                    var laser = Path()
                    Olo.linea(&laser, sl - 7, ly, sl + sw + 7, ly)
                    gc.stroke(laser, with: .color(Olo.bianco.opacity(0.95)), style: Olo.tratto(1.4))
                    Olo.alone(&gc, CGPoint(x: sl - 7, y: ly), 8, 0.8, Olo.bianco)
                    Olo.alone(&gc, CGPoint(x: sl + sw + 7, y: ly), 8, 0.8, Olo.bianco)
                }
            }
            if u >= e + s && u < a0 + 0.06 {   // l'aggancio: le staffe agli angoli si chiudono sulla foto, un lampo
                let q = min(1, (u - e - s) / 0.14), o = 3 + 11 * (1 - Olo.liscia(q)), l = 11.0
                var staffe = Path()
                let angoli: [(Double, Double, Double, Double)] = [(sl - o, st - o, 1, 1), (sl + sw + o, st - o, -1, 1), (sl - o, st + sh + o, 1, -1), (sl + sw + o, st + sh + o, -1, -1)]
                for (ax, ay, sx, syy) in angoli {
                    staffe.move(to: CGPoint(x: ax, y: ay + syy * l))
                    staffe.addLine(to: CGPoint(x: ax, y: ay))
                    staffe.addLine(to: CGPoint(x: ax + sx * l, y: ay))
                }
                gc.stroke(staffe, with: .color(Olo.bianco.opacity(0.95 * q)), style: Olo.tratto(1.6))
                if q < 1 { Olo.alone(&gc, CGPoint(x: pkx, y: pky), p * 0.8, 0.25 * (1 - q), Olo.bianco) }
            }
        }
        // le cose trovate: compaiono quando il laser ci passa sopra, con il filo dalla foto e la barra della fiducia
        let tx = cx + p / 2 + 44, n = cur.cose.count
        // 4 nov: un nome lungo (iPhone piccoli) si accorcia con «…» prima della percentuale. La scritta è monospaziata: basta la
        // larghezza di un carattere, misurata una volta per disegno.
        let carattere = Double(gc.resolve(Text("M").font(.system(size: 10, weight: .bold, design: .monospaced)))
            .measure(in: CGSize(width: 200, height: 50)).width)
        gc.blendMode = .normal
        for (i, cosa) in cur.cose.enumerated() {
            let soglia = 0.12 + 0.72 * (Double(i) + 0.5) / Double(max(1, n)), du = u - e - s * soglia
            let fuori = u >= a0 ? max(0, 1 - (u - a0) / 0.12) : 1
            if du < 0 || fuori <= 0 { continue }
            let q = min(1, du / 0.2), ry0 = top + 6 + Double(i) * 23
            let ny = top + p * (0.2 + 0.6 * Double(i) / Double(max(1, n - 1))), nx = cx + p / 2 + 2
            let punti: [CGPoint] = [CGPoint(x: nx, y: ny), CGPoint(x: tx - 26, y: ny), CGPoint(x: tx - 12, y: ry0 - 3.5), CGPoint(x: tx - 5, y: ry0 - 3.5)]
            var lung = 0.0
            for j in 1..<punti.count { lung += hypot(Double(punti[j].x - punti[j - 1].x), Double(punti[j].y - punti[j - 1].y)) }
            var resta = lung * min(1, q / 0.6)
            var filo = Path()
            filo.move(to: punti[0])
            for j in 1..<punti.count where resta > 0 {
                let a = punti[j - 1], b = punti[j], d = hypot(Double(b.x - a.x), Double(b.y - a.y)), r = d > 0 ? min(1, resta / d) : 1
                filo.addLine(to: CGPoint(x: Double(a.x) + Double(b.x - a.x) * r, y: Double(a.y) + Double(b.y - a.y) * r))
                resta -= d
            }
            gc.stroke(filo, with: .color(Olo.ciano.opacity(0.6 * fuori)), lineWidth: 1)
            gc.fill(Olo.ellisse(nx, ny, 1.8, 1.8), with: .color(Olo.bianco.opacity(0.95 * fuori)))
            let qt = max(0, (q - 0.4) / 0.6)
            if qt <= 0 { continue }
            var rombo = Path()
            rombo.move(to: CGPoint(x: tx - 4, y: ry0 - 7))
            rombo.addLine(to: CGPoint(x: tx, y: ry0 - 3.5))
            rombo.addLine(to: CGPoint(x: tx - 4, y: ry0))
            rombo.addLine(to: CGPoint(x: tx - 8, y: ry0 - 3.5))
            rombo.closeSubpath()
            gc.fill(rombo, with: .color(Olo.ciano.opacity(qt * fuori)))
            let percento = "\(Int((cosa.fiducia * 100).rounded()))%"
            // lo spazio del nome: fino alla percentuale, con un carattere vuoto in mezzo
            let posti = carattere > 0 ? Int(((w - 4 - Double(percento.count + 1) * carattere) - (tx + 5)) / carattere) : cosa.nome.count
            Olo.scritta(&gc, DisegnoAnalisi.accorcia(cosa.nome, posti), tx + 5, ry0 - 3.5, corpo: 10, peso: .bold, Olo.bianco.opacity(qt * fuori), ancora: .leading)
            Olo.scritta(&gc, percento, w - 4, ry0 - 3.5, corpo: 10, peso: .bold, Olo.ciano.opacity(qt * fuori), ancora: .trailing)
            let bw = w - 4 - (tx + 5)
            gc.fill(Path(CGRect(x: tx + 5, y: ry0 + 4, width: bw, height: 2)), with: .color(Olo.azzurro.opacity(0.16 * fuori)))
            gc.fill(Path(CGRect(x: tx + 5, y: ry0 + 4, width: bw * cosa.fiducia * Olo.liscia(min(1, qt * 1.4)), height: 2)),
                    with: .color(Olo.ciano.opacity(0.9 * qt * fuori)))
        }
    }
}

// MARK: - i quadratini nuovi che si materializzano

/// Un quadratino nuovo della ricerca: il laser scende e lo scopre, la velatura ciano sfuma (0,36 s e 0,55 s, uno dopo l'altro).
/// Solo per le foto appena arrivate e visibili subito; quelle che si scoprono scorrendo arrivano e basta.
struct Materializza: ViewModifier {
    let ritardo: Double?
    let quando: Date
    let altezza: CGFloat
    @State private var p: Double

    init(ritardo: Double?, quando: Date, altezza: CGFloat = 104) {
        self.ritardo = ritardo
        self.quando = quando
        self.altezza = altezza
        // si parte nascosti solo se la foto è nuova e appena arrivata: le altre ci sono e basta
        _p = State(initialValue: ritardo != nil && Date().timeIntervalSince(quando) < 0.3 ? 0 : 1)
    }

    func body(content: Content) -> some View {
        content
            .modifier(Rivela(p: p, altezza: altezza))
            .onAppear {
                guard p < 1, let r = ritardo else { return }
                withAnimation(.linear(duration: 0.55).delay(max(0, r - Date().timeIntervalSince(quando)))) { p = 1 }
            }
    }
}

/// Il disegno della materializzazione, a ogni fotogramma dell'animazione (p da 0 a 1 in 0,55 s).
struct Rivela: ViewModifier, Animatable {
    var p: Double
    let altezza: CGFloat
    // nonisolated: SwiftUI la legge e la scrive dall'animazione (come i Shape del progetto, che sono già nonisolated)
    nonisolated var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    @ViewBuilder func body(content: Content) -> some View {
        let q = min(1, p * 0.55 / 0.36), u = Rivela.curva(q)
        let laser = q < 0.08 ? q / 0.08 : q > 0.85 ? (1 - q) / 0.15 : 1
        let velo = pow(1 - min(1, p), 2)
        content
            .mask(alignment: .top) { Rectangle().frame(height: altezza * CGFloat(u)) }
            .overlay {
                if velo > 0.001 {
                    LinearGradient(colors: [Olo.ciano.opacity(0.34), Olo.azzurro.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                        .opacity(velo)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if p < 1 {
                    Rectangle().fill(Olo.bianco).frame(height: 2)
                        .shadow(color: Olo.azzurro.opacity(0.85), radius: 5)
                        .offset(y: altezza * CGFloat(u) - 1)
                        .opacity(max(0, laser))
                        .allowsHitTesting(false)
                }
            }
    }

    /// La curva del mockup, cubic-bezier(.25, .7, .3, 1): parte veloce e frena.
    static func curva(_ x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        let x1 = 0.25, y1 = 0.7, x2 = 0.3, y2 = 1.0
        var a = 0.0, b = 1.0, t = x
        for _ in 0..<24 {
            t = (a + b) / 2
            if Rivela.bezier(t, x1, x2) < x { a = t } else { b = t }
        }
        return Rivela.bezier(t, y1, y2)
    }

    /// Un punto della curva di Bézier da 0 a 1 con i due punti di controllo `p1` e `p2` (una coordinata).
    private static func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let m = 1 - t
        let b1 = 3 * m * m * t, b2 = 3 * m * t * t, b3 = t * t * t
        return b1 * p1 + b2 * p2 + b3
    }
}

// MARK: - le parole capite sotto il campo di ricerca

/// Le cose che JARVIS ha capito, in fila col «+» (devono esserci tutte): appena riconosciuta, una parola si aggancia.
struct ParoleCapite: View {
    let parole: [String]
    let tinta: Color
    @Environment(\.accessibilityReduceMotion) private var riduci

    /// Una parola in fila, con la sua identità.
    nonisolated private struct Voce: Identifiable {
        let id: String
        let k: Int
        let parola: String
    }

    /// 4 nov: l'identità di ogni parola è la parola stessa (e quante volte è già comparsa prima, se si ripete), non il posto
    /// in fila: togliendo la prima, le altre restano quelle che erano e non rifanno l'aggancio, come nel mockup (lì si aggancia
    /// solo una parola che prima non c'era).
    private var voci: [Voce] {
        var viste: [String: Int] = [:]
        return parole.enumerated().map { k, p in
            let chiave = p.lowercased()
            let n = viste[chiave, default: 0]
            viste[chiave] = n + 1
            return Voce(id: "\(chiave)#\(n)", k: k, parola: p)
        }
    }

    /// L'aggancio (arriva più grande, si stringe con un lampo); con «Riduci movimento» solo la dissolvenza (4 nov).
    private var entrata: AnyTransition {
        riduci ? .opacity : .asymmetric(insertion: .modifier(active: Aggancio(p: 0), identity: Aggancio(p: 1)), removal: .opacity)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(voci) { v in
                    if v.k > 0 {
                        Text("+").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Color.tenue)
                    }
                    HStack(spacing: 6) {
                        Rectangle().fill(tinta).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                        Text(v.parola.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(tinta)
                    }
                    .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 4)
                    .background(tinta.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(tinta.opacity(0.4), lineWidth: 1))
                    .transition(entrata)
                }
            }
        }
        .scrollClipDisabled()
    }
}

/// L'aggancio di una parola appena capita: arriva più grande, si stringe al suo posto con un lampo.
struct Aggancio: ViewModifier, Animatable {
    var p: Double
    // nonisolated: come in Rivela
    nonisolated var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + 0.3 * (1 - p))
            .opacity(min(1, p / 0.55))
            .shadow(color: Olo.azzurro.opacity(0.75 * sin(min(1, max(0, p)) * .pi)), radius: 7)
    }
}
