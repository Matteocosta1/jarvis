import Foundation
import SwiftUI

// MARK: - GLI OLOGRAMMI NUOVI (11.0 (4), 5 nov notte) — come il mockup v261
// Il signore: «Diario, Sonno, Briefing, Spesa: ognuna col suo ologramma, come Cuore e Meteo»; «Serata ha bisogno di un'animazione
// nella parte dove arrivano i soldi». Stessa famiglia di Cuore e Meteo: Canvas in luce additiva a ogni fotogramma (120 Hz
// sull'iPhone, 60 sull'orologio), il proiettore sul pavimento, il cono di luce, i tratti raccolti per luminosità e profondità,
// i numeri scritti nel disegno. Ognuno dice qualcosa dei dati:
// DIARIO   il libro aperto (oggi scritto o no, la penna di luce che scrive) e l'umore degli ultimi 7 giorni, con la media;
// SONNO    la luna che gira e attorno l'anello della notte: le fasi alte quanto è profondo il sonno, la notte che si riavvolge;
// BRIEFING il quadrante della giornata (24 ore): la luce da alba a tramonto, il sole sul suo arco, adesso, gli impegni;
// SPESA    il carrello: le cose da prendere girano sopra, quelle prese ci cadono dentro, l'anello del pavimento si riempie;
// SERATA   da dove arrivano i soldi: l'anello di monete (una fetta per voce, alta quanto pesa), i soldi che arrivano, il totale.
// Sull'orologio (piccolo) solo l'oggetto, senza scritte, come il cuore e il cielo. Con «Riduci movimento» il disegno resta
// fermo. Questo file è sia dell'iPhone sia dell'orologio.

// MARK: - Gli attrezzi comuni (pavimentoOlo, conoOlo, proiettaOlo, scrittaOlo, gruppiOlo del mockup)

extension Olo {
    /// La prospettiva comune (come il cuore): un punto 3D (x a destra, y in profondità, z in su) girato di `ang` attorno all'asse
    /// verticale e inclinato di `al` verso chi guarda. Risultato: x e y sullo schermo, z = profondità (davanti negativo).
    static func proietta(_ x: Double, _ y: Double, _ z: Double, _ ang: Double, _ al: Double,
                         _ cx: Double, _ cy: Double, _ sz: Double) -> SIMD3<Double> {
        let ca = cos(ang), sa = sin(ang), xx = x * ca - y * sa, y0 = x * sa + y * ca
        let yy = y0 * cos(al) - z * sin(al), zz = y0 * sin(al) + z * cos(al), k = 3.6 / (3.6 + yy)
        return SIMD3<Double>(cx + xx * k * sz, cy - zz * k * sz, yy)
    }

    /// Il proiettore sul pavimento (come quello del cuore): l'ellisse, le tacche che girano, l'arco chiaro. Restituisce ry.
    @discardableResult
    static func pavimento(_ gc: inout GraphicsContext, _ cx: Double, _ base: Double, _ rx: Double, _ t: Double, n: Int = 48) -> Double {
        let ry = rx * 0.17
        gc.stroke(ellisse(cx, base, rx, ry), with: .color(azzurro.opacity(0.32)), lineWidth: 1)
        gc.stroke(ellisse(cx, base, rx * 0.62, ry * 0.62), with: .color(azzurro.opacity(0.18)), lineWidth: 1)
        var tacche = Path()
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi + t * 0.4, c = cos(a), s = sin(a), l = i % 4 != 0 ? 0.9 : 0.8
            linea(&tacche, cx + c * rx, base + s * ry, cx + c * rx * l, base + s * ry * l)
        }
        gc.stroke(tacche, with: .color(ciano.opacity(0.5)), style: tratto(1))
        var lampo = Path()
        arco(&lampo, cx, base, rx, ry, t * 1.1, t * 1.1 + 0.9)
        gc.stroke(lampo, with: .color(bianco.opacity(0.55)), style: tratto(1.6))
        return ry
    }

    /// Il cono di luce dal proiettore fino a `cima`, largo `w` in alto.
    static func cono(_ gc: inout GraphicsContext, _ cx: Double, _ base: Double, _ rx: Double, _ cima: Double, _ w: Double, a: Double = 0.13) {
        var p = Path()
        p.move(to: CGPoint(x: cx - rx * 0.62, y: base))
        p.addLine(to: CGPoint(x: cx - w, y: cima))
        p.addLine(to: CGPoint(x: cx + w, y: cima))
        p.addLine(to: CGPoint(x: cx + rx * 0.62, y: base))
        p.closeSubpath()
        gc.fill(p, with: .linearGradient(Gradient(colors: [azzurro.opacity(a), azzurro.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: cima)))
    }

    /// Una scritta del disegno messa sulla sua linea di base (come il fillText del mockup), sopra la luce e non sommata.
    static func testo(_ gc: inout GraphicsContext, _ s: String, _ x: Double, _ yBase: Double, corpo: Double, peso: Font.Weight,
                      _ col: Color, ancora: UnitPoint = .center) {
        let prima = gc.blendMode
        gc.blendMode = .normal
        scritta(&gc, s, x, yBase - corpo * 0.36, corpo: corpo, peso: peso, col, ancora: ancora)
        gc.blendMode = prima
    }

    /// I numeri all'italiana (punto per le migliaia, virgola per i decimali), uguali su ogni telefono.
    static func numero(_ v: Double, decimali: Int = 0) -> String {
        let s = String(format: "%.\(decimali)f", abs(v))
        let parti = s.split(separator: ".", omittingEmptySubsequences: false)
        var intera = ""
        for (i, c) in String(parti.first ?? "0").reversed().enumerated() {
            if i > 0 && i % 3 == 0 { intera.append(".") }
            intera.append(c)
        }
        let decimale = parti.count > 1 ? "," + String(parti[1]) : ""
        return (v < 0 ? "−" : "") + String(intera.reversed()) + decimale
    }

    /// I minuti del giorno come ora: 630 → «10:30».
    static func ora(_ m: Double) -> String {
        let tot = ((Int(m.rounded()) % 1440) + 1440) % 1440
        return "\(tot / 60):\(String(format: "%02d", tot % 60))"
    }

    /// Ore e minuti di una durata in minuti: 400 → «6 h 40».
    static func durata(_ minuti: Int) -> String { "\(minuti / 60) h \(String(format: "%02d", minuti % 60))" }
}

/// I tratti raccolti per luminosità: un disegno per gruppo invece di uno per tratto (gruppiOlo del mockup).
struct GruppiOlo {
    private var tratti: [Path]
    init(_ n: Int) { tratti = Array(repeating: Path(), count: n) }

    mutating func metti(_ g: Int, _ a: SIMD3<Double>, _ b: SIMD3<Double>) {
        let k = min(tratti.count - 1, max(0, g))
        tratti[k].move(to: CGPoint(x: a.x, y: a.y))
        tratti[k].addLine(to: CGPoint(x: b.x, y: b.y))
    }

    func linee(_ gc: inout GraphicsContext, colore: (Int) -> Color, spessore: (Int) -> Double) {
        for (g, p) in tratti.enumerated() where !p.isEmpty {
            gc.stroke(p, with: .color(colore(g)), style: Olo.tratto(spessore(g)))
        }
    }
}

/// Il motore di ogni ologramma nuovo: ridisegna a ogni fotogramma, si ferma con «Riduci movimento» (e resta sul disegno finito)
/// e, sull'iPhone, quando la sezione è dietro. `t` = secondi da quando è comparso; `ora` = l'istante del fotogramma.
struct TelaOlo: View {
    let disegna: (inout GraphicsContext, CGSize, Double, Date) -> Void
    @Environment(\.accessibilityReduceMotion) private var riduci
    @State private var inizio = Date()
    #if os(iOS)
    @Environment(\.sezioneDietro) private var dietro
    #else
    private let dietro = false
    #endif

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: riduci || dietro)) { ctx in
            let t = riduci ? 6 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in disegna(&gc, size, t, ctx.date) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - DIARIO

/// L'umore degli ultimi 7 giorni (dal più vecchio a oggi, da 1 a 10, nil = niente pagina) e se la pagina di oggi è scritta.
struct DatiDiario: Equatable {
    struct Giorno: Equatable {
        var lettera: String
        var voto: Int?
    }
    var giorni: [Giorno] = []
    var oggi = false

    /// `voti`: il voto dell'umore per giorno (inizio del giorno).
    init(voti: [Date: Int], oggi: Bool) {
        let cal = Calendar.current, adesso = cal.startOfDay(for: Date())
        let lettere = ["D", "L", "M", "M", "G", "V", "S"]
        giorni = (0..<7).reversed().map { k -> Giorno in
            let g = cal.date(byAdding: .day, value: -k, to: adesso) ?? adesso
            return Giorno(lettera: lettere[(cal.component(.weekday, from: g) + 6) % 7], voto: voti[g])
        }
        self.oggi = oggi
    }
}

/// Il libro aperto sopra il proiettore. A sinistra la pagina di ieri, piena; a destra quella di oggi: se è scritta ci sono le
/// righe (e quando arriva la penna di luce le scrive), se no lampeggia il cursore e c'è scritto STASERA. Sopra, l'umore degli
/// ultimi 7 giorni: una linguetta per giorno, piena quanto l'umore, col numero e l'iniziale del giorno; in alto la media.
struct OlogrammaDiario: View {
    let dati: DatiDiario
    var piccolo = false
    @State private var scritta: Date?          // quando è arrivata la pagina di oggi: la penna la scrive (nil = era già scritta)

    var body: some View {
        TelaOlo { gc, size, t, ora in
            DisegnoDiario.disegna(&gc, size, t: t, d: dati, penna: scritta.map { ora.timeIntervalSince($0) }, piccolo: piccolo)
        }
        .onChange(of: dati.oggi) { _, nuovo in if nuovo { scritta = Date() } }
    }
}

enum DisegnoDiario {
    /// La lunghezza delle righe: sempre la stessa.
    nonisolated private static let semi: [Double] = (0..<16).map { 0.42 + 0.34 * Olo.caso($0 + 101) }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, d: DatiDiario, penna: Double?, piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let cx = w / 2, base = piccolo ? h - 5 : h - 16, rx = piccolo ? w * 0.34 : min(w * 0.2, 74)
        let cy = piccolo ? h * 0.5 : h * 0.65, sz = piccolo ? min(w, h) * 0.3 : min(w * 0.19, h * 0.3)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 40)
        Olo.cono(&gc, cx, base, rx, cy - sz * 0.75, sz * 1.25, a: 0.1)
        // il libro: due pagine aperte a V verso chi guarda, che oscilla appena (si vede il volume)
        let ang = 0.28 * sin(t * 0.4), al = 0.22, fi = 0.42 + 0.03 * sin(t * 0.9), pw = 0.95, ph = 1.2
        func pagina(_ lato: Double, _ u: Double, _ z: Double) -> SIMD3<Double> {
            Olo.proietta(lato * u * pw * cos(fi), u * pw * sin(fi), z, ang, al, cx, cy, sz)
        }
        var g = GruppiOlo(5)
        func linea(_ lato: Double, _ u0: Double, _ z0: Double, _ u1: Double, _ z1: Double, _ k: Int) {
            let a = pagina(lato, u0, z0), b = pagina(lato, u1, z1)
            g.metti(k + (a.z + b.z < 0 ? 1 : 0), a, b)
        }
        for lato in [-1.0, 1.0] {
            linea(lato, 0, -ph / 2, 1, -ph / 2, 2)
            linea(lato, 0, ph / 2, 1, ph / 2, 2)
            linea(lato, 1, -ph / 2, 1, ph / 2, 2)
            if !piccolo {                                                   // lo spessore delle pagine
                for j in 0..<3 { let u = 1 + 0.025 * Double(j + 1); linea(lato, u, -ph / 2 + 0.03, u, ph / 2 - 0.03, 0) }
            }
        }
        linea(1, 0, -ph / 2, 0, ph / 2, 3)                                  // il dorso
        // le righe: ieri tutte; oggi quelle scritte (la penna le scrive in 2,4 s), o il cursore che lampeggia
        let righe = piccolo ? 5 : 8, passo = piccolo ? 0.19 : 0.12
        for j in 0..<righe {
            let z = ph / 2 - 0.2 - Double(j) * passo
            linea(-1, 0.88, z, 0.88 - semi[j] * 0.8, z, 1)                 // a sinistra le righe partono dal bordo
        }
        var punta: SIMD3<Double>?
        if d.oggi {
            let p = penna.map { max(0, $0 / 2.4) * Double(righe) } ?? Double(righe)
            for j in 0..<righe {
                let f = min(1, max(0, p - Double(j)))
                if f <= 0 { break }
                let z = ph / 2 - 0.2 - Double(j) * passo, u1 = 0.12 + semi[j + 8] * 0.8 * f
                linea(1, 0.12, z, u1, z, 2)
                if f < 1 { punta = pagina(1, u1, z) }
            }
        }
        g.linee(&gc, colore: { $0 >= 4 ? Olo.bianco.opacity(0.85) : Olo.ciano.opacity(0.16 + 0.17 * Double($0)) },
                spessore: { 0.9 + Double($0) * 0.12 })
        if let p = punta {
            Olo.alone(&gc, CGPoint(x: p.x, y: p.y), 9, 0.8, Olo.bianco)
            gc.fill(Olo.ellisse(p.x, p.y, 1.8, 1.8), with: .color(Olo.bianco))
        }
        if !d.oggi {
            let lampo = sin(t * 2 * .pi / 1.1) > 0 ? 1.0 : 0.15                // il cursore: mezzo secondo acceso, mezzo spento
            let a = pagina(1, 0.14, ph / 2 - 0.15), b = pagina(1, 0.14, ph / 2 - 0.26)
            var cursore = Path()
            Olo.linea(&cursore, a.x, a.y, b.x, b.y)
            gc.stroke(cursore, with: .color(Olo.bianco.opacity(0.95 * lampo)), style: Olo.tratto(1.6))
            if !piccolo {
                let q = pagina(1, 0.5, -0.05)
                Olo.testo(&gc, "STASERA", q.x, q.y, corpo: 7, peso: .bold, Olo.ciano.opacity(0.8))
            }
        }
        Olo.alone(&gc, CGPoint(x: cx, y: cy), sz * 1.25, 0.08)
        guard !piccolo else { return }
        // l'umore degli ultimi 7 giorni: le linguette su un arco sopra il libro
        let n = d.giorni.count, ra = min(w * 0.36, 130), cima = 30.0
        var punti: [CGPoint] = []
        for (i, giorno) in d.giorni.enumerated() {
            let a = (Double(i) / Double(max(1, n - 1)) - 0.5) * 1.5
            let px = cx + sin(a) * ra, py = cima + (1 - cos(a)) * ra * 0.32, oggi = i == n - 1
            let lw = 9.0, lh = 22.0, al2 = oggi ? 1.0 : 0.7
            let rett = Path(CGRect(x: px - lw / 2, y: py, width: lw, height: lh))
            if let v = giorno.voto {
                gc.stroke(rett, with: .color(Olo.ciano.opacity(0.5 * al2)), lineWidth: 1)
                let f = min(1, max(0, (t - 0.15 - Double(i) * 0.07) / 0.5)), hv = lh * Double(v) / 10 * Olo.liscia(f)
                if hv > 0.2 {
                    gc.fill(Path(CGRect(x: px - lw / 2 + 1.5, y: py + lh - hv, width: lw - 3, height: hv)),
                            with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0.25 * al2), Olo.ciano.opacity(0.85 * al2)]),
                                                  startPoint: CGPoint(x: 0, y: py + lh), endPoint: CGPoint(x: 0, y: py + lh - hv)))
                }
                punti.append(CGPoint(x: px, y: py + lh - hv))
                Olo.testo(&gc, "\(v)", px, py - 4, corpo: oggi ? 9 : 8, peso: .bold, oggi ? Olo.bianco : Olo.ciano.opacity(0.85))
            } else {
                gc.stroke(rett, with: .color(Olo.ciano.opacity(0.5 * al2)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                Olo.testo(&gc, "—", px, py - 4, corpo: 8, peso: .bold, Olo.ciano.opacity(0.5))
            }
            Olo.testo(&gc, giorno.lettera, px, py + lh + 10, corpo: 7, peso: .semibold, oggi ? Olo.bianco.opacity(0.95) : Olo.ciano.opacity(0.6))
            if oggi {
                gc.stroke(Path(CGRect(x: px - lw / 2 - 2.5, y: py - 2.5, width: lw + 5, height: lh + 5)),
                          with: .color(Olo.bianco.opacity(0.5 + 0.3 * sin(t * 3))), lineWidth: 1)
            }
        }
        if punti.count > 1 {
            var andamento = Path()
            andamento.addLines(punti)
            gc.stroke(andamento, with: .color(Olo.ciano.opacity(0.35)), style: Olo.tratto(1))
        }
        let voti = d.giorni.compactMap(\.voto)
        Olo.testo(&gc, "UMORE · 7 GIORNI", 10, 14, corpo: 8, peso: .semibold, Olo.ciano.opacity(0.85), ancora: .leading)
        if !voti.isEmpty {
            let media = Double(voti.reduce(0, +)) / Double(voti.count)
            Olo.testo(&gc, "MEDIA \(Olo.numero(media, decimali: 1))", w - 10, 14, corpo: 8, peso: .bold, Olo.bianco.opacity(0.95), ancora: .trailing)
        }
    }
}

// MARK: - SONNO

/// La notte per l'ologramma: la profondità del sonno minuto per minuto (1 profondo, 0,62 leggero, 0,36 REM, 0,12 sveglio)
/// dall'addormentamento al risveglio, le ore e quanto ha dormito.
struct DatiNotte: Equatable {
    var livelli: [Double] = []
    var inizio = ""
    var fine = ""
    var dormito = ""
    var testo = ""
    var durata: Double { Double(livelli.count) }

    /// `fasi`: (da, a, fase) con fase 0 sveglio, 1 REM, 2 leggero (core), 3 profondo.
    init(fasi: [(Date, Date, Int)]) {
        let ordinate = fasi.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        guard let t0 = ordinate.map(\.0).min(), let t1 = ordinate.map(\.1).max() else { return }
        let n = min(1440, max(1, Int(t1.timeIntervalSince(t0) / 60)))
        let profondita: [Double] = [0.12, 0.36, 0.62, 1]
        var livelli = [Double](repeating: 0.12, count: n), fase = [Int](repeating: 0, count: n)
        for (da, a, f) in ordinate {
            let i0 = max(0, min(n - 1, Int(da.timeIntervalSince(t0) / 60))), i1 = max(i0 + 1, min(n, Int(a.timeIntervalSince(t0) / 60)))
            let k = max(0, min(3, f))
            for i in i0..<i1 { livelli[i] = profondita[k]; fase[i] = k }
        }
        self.livelli = livelli
        let ore = DateFormatter()
        ore.dateFormat = "HH:mm"
        inizio = ore.string(from: t0)
        fine = ore.string(from: t1)
        dormito = Olo.durata(fase.filter { $0 > 0 }.count)
        let profondo = fase.filter { $0 == 3 }.count, rem = fase.filter { $0 == 1 }.count
        testo = "PROFONDO \(Olo.durata(profondo)) · REM \(Olo.durata(rem))"
    }

    /// La profondità al minuto `m` della notte.
    func livello(_ m: Double) -> Double {
        guard !livelli.isEmpty else { return 0.12 }
        return livelli[max(0, min(livelli.count - 1, Int(m)))]
    }
}

/// La luna (una sfera di luce illuminata da un lato: la falce) che gira piano sopra il proiettore. Attorno l'anello della notte,
/// da quando si è addormentato (davanti a sinistra) al risveglio (davanti a destra), passando dietro la luna: in ogni punto una
/// barra alta quanto è profondo il sonno. La notte si riavvolge: un punto di luce la ripercorre in 5 s e accende le barre, poi si
/// ferma 2 s alla fine. In alto la durata e le fasi, in basso la legenda.
struct OlogrammaNotte: View {
    let dati: DatiNotte
    var piccolo = false

    var body: some View {
        TelaOlo { gc, size, t, _ in DisegnoNotte.disegna(&gc, size, t: t, n: dati, piccolo: piccolo) }
    }
}

enum DisegnoNotte {
    nonisolated private static let sole: SIMD3<Double> = {
        let l = SIMD3<Double>(1, -0.55, 0.45)
        return l / (l * l).sum().squareRoot()
    }()

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, n: DatiNotte, piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let cx = w / 2, base = piccolo ? h - 5 : h - 16, rx = piccolo ? w * 0.32 : min(w * 0.22, 80)
        let cy = piccolo ? h * 0.45 : h * 0.46, sz = piccolo ? min(w, h) * 0.17 : min(w * 0.13, h * 0.17)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 40)
        Olo.cono(&gc, cx, base, rx, cy - sz * 0.6, sz * 2.6, a: 0.09)
        let ang = 0.35 * sin(t * 0.22), al = 0.32, giro = t * 0.25
        Olo.alone(&gc, CGPoint(x: cx, y: cy), sz * 2.2, 0.1)
        // la luna: paralleli e meridiani, chiari dal lato del sole, quasi spenti dall'altro (la falce)
        var g = GruppiOlo(6)
        func sfera(_ la: Double, _ lo: Double) -> (SIMD3<Double>, Double) {
            let c = cos(la), p = SIMD3<Double>(c * cos(lo + giro), c * sin(lo + giro), sin(la))
            return (Olo.proietta(p.x, p.y, p.z, ang, al, cx, cy, sz), (p * sole).sum())
        }
        let paralleli: [Double] = piccolo ? [-0.8, -0.3, 0.3, 0.8] : [-1.1, -0.7, -0.35, 0, 0.35, 0.7, 1.1]
        let passi = piccolo ? 24 : 48
        for la in paralleli {
            var (o, lo) = sfera(la, 0)
            for i in 1...passi {
                let (q, lq) = sfera(la, Double(i) / Double(passi) * 2 * .pi)
                let luce = (lo + lq) / 2, dav = o.z + q.z < 0 ? 1 : 0
                g.metti(luce > 0.15 ? 3 + dav : luce > -0.15 ? 1 + dav : 0, o, q)
                o = q; lo = lq
            }
        }
        let meridiani = piccolo ? 6 : 10, tratti = piccolo ? 12 : 24
        for k in 0..<meridiani {
            let lo0 = Double(k) / Double(meridiani) * 2 * .pi
            var (o, l0) = sfera(-1.45, lo0)
            for i in 1...tratti {
                let (q, l1) = sfera(-1.45 + Double(i) / Double(tratti) * 2.9, lo0)
                let luce = (l0 + l1) / 2, dav = o.z + q.z < 0 ? 1 : 0
                g.metti(luce > 0.15 ? 2 + dav : 0, o, q)
                o = q; l0 = l1
            }
        }
        // l'anello della notte, sotto l'equatore
        let rr = 1.95, zr = -0.25, buco = 0.6, dur = max(1, n.durata)
        func angolo(_ m: Double) -> Double { (-Double.pi / 2 - buco) - (m / dur) * (2 * .pi - 2 * buco) }
        func anello(_ m: Double, _ z: Double) -> SIMD3<Double> {
            let a = angolo(m)
            return Olo.proietta(rr * cos(a), rr * sin(a), z, ang, al, cx, cy, sz)
        }
        let p = min(1, t.truncatingRemainder(dividingBy: 7) / 5), mOra = p * dur
        var o = anello(0, zr)
        for i in 1...64 {
            let q = anello(Double(i) / 64 * dur, zr)
            g.metti(o.z < 0 ? 2 : 1, o, q)
            o = q
        }
        g.linee(&gc, colore: { $0 == 5 ? Olo.bianco.opacity(0.85) : $0 == 4 ? Olo.bianco.opacity(0.55) : Olo.ciano.opacity(0.08 + 0.13 * Double($0)) },
                spessore: { 0.8 + Double($0) * 0.1 })
        // le barre: dietro, davanti, accese dalla notte che passa
        guard !n.livelli.isEmpty else { return }
        var fasce = [Path(), Path(), Path()]
        let ogni = piccolo ? 10.0 : 5.0
        var m = ogni / 2
        while m < dur {
            let a = anello(m, zr), b = anello(m, zr + n.livello(m) * 0.95)
            let k = m <= mOra && mOra - m < 60 ? 2 : a.z < 0 ? 1 : 0
            fasce[k].move(to: CGPoint(x: a.x, y: a.y))
            fasce[k].addLine(to: CGPoint(x: b.x, y: b.y))
            m += ogni
        }
        gc.stroke(fasce[0], with: .color(Olo.azzurro.opacity(0.3)), style: Olo.tratto(1.3))
        gc.stroke(fasce[1], with: .color(Olo.ciano.opacity(0.6)), style: Olo.tratto(1.5))
        gc.stroke(fasce[2], with: .color(Olo.bianco.opacity(0.9)), style: Olo.tratto(1.7))
        // il punto della notte che passa
        let punto = anello(mOra, zr + n.livello(min(dur - 0.1, mOra)) * 0.95)
        Olo.alone(&gc, CGPoint(x: punto.x, y: punto.y), 10, 0.75, Olo.bianco)
        gc.fill(Olo.ellisse(punto.x, punto.y, 2.2, 2.2), with: .color(Olo.bianco))
        guard !piccolo else { return }
        // le ore: addormentato e sveglio, accanto ai capi dell'anello
        let a0 = anello(0, zr), a1 = anello(dur, zr)
        Olo.testo(&gc, n.inizio, a0.x - 4, a0.y + 14, corpo: 9, peso: .bold, Olo.bianco.opacity(0.95), ancora: .trailing)
        Olo.testo(&gc, n.fine, a1.x + 4, a1.y + 14, corpo: 9, peso: .bold, Olo.bianco.opacity(0.95), ancora: .leading)
        Olo.testo(&gc, "NOTTE · \(n.dormito)", 10, 14, corpo: 8, peso: .semibold, Olo.ciano.opacity(0.85), ancora: .leading)
        Olo.testo(&gc, n.testo, w - 10, 14, corpo: 8, peso: .semibold, Olo.ciano.opacity(0.85), ancora: .trailing)
        // la legenda delle barre, in basso a sinistra: quattro barrette alte come le fasi
        let lx = 10.0, ly = h - 34
        var barrette = Path()
        for (i, (nome, alto)) in ([("PROF", 1.0), ("CORE", 0.62), ("REM", 0.36), ("SVEG", 0.12)] as [(String, Double)]).enumerated() {
            let x = lx + Double(i) * 27
            Olo.linea(&barrette, x, ly - 2, x, ly - 2 - alto * 14)
            Olo.testo(&gc, nome, x + 4, ly, corpo: 6, peso: .semibold, Olo.ciano.opacity(0.7), ancora: .leading)
        }
        gc.stroke(barrette, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(2))
    }
}

// MARK: - BRIEFING

/// La giornata per l'ologramma: alba e tramonto (minuti dalla mezzanotte, nil se Apple Meteo non li dà) e gli impegni di oggi.
struct DatiGiornata: Equatable {
    var alba: Double?
    var tramonto: Double?
    var impegni: [Double] = []

    /// I minuti dalla mezzanotte di oggi di un istante.
    static func minuti(_ d: Date) -> Double {
        d.timeIntervalSince(Calendar.current.startOfDay(for: d)) / 60
    }
}

/// Il quadrante della giornata, steso come un piatto davanti a chi guarda: 24 ore, mezzanotte davanti, le 6 a sinistra,
/// mezzogiorno dietro, le 18 a destra. La luce del giorno chiara, la notte spenta; sopra, l'arco del sole col sole dov'è adesso
/// (di notte la luna). La lancetta di ADESSO. Gli impegni sono spilli alla loro ora: quelli passati spenti, il prossimo pulsa.
struct OlogrammaGiornata: View {
    let dati: DatiGiornata
    var piccolo = false

    var body: some View {
        TelaOlo { gc, size, t, ora in
            DisegnoGiornata.disegna(&gc, size, t: t, adesso: DatiGiornata.minuti(ora), g: dati, piccolo: piccolo)
        }
    }
}

enum DisegnoGiornata {
    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, adesso: Double, g: DatiGiornata, piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let cx = w / 2, cy = h * 0.66
        let rx = piccolo ? w * 0.44 : min(w * 0.4, 146), ry = rx * (piccolo ? 0.3 : 0.28)
        func th(_ m: Double) -> Double { .pi / 2 + m / 1440 * 2 * .pi }
        func punto(_ m: Double, _ r: Double = 1) -> (x: Double, y: Double) { (cx + cos(th(m)) * rx * r, cy + sin(th(m)) * ry * r) }
        Olo.alone(&gc, CGPoint(x: cx, y: cy), rx * 0.9, 0.06)
        // il quadrante: la notte, poi la luce del giorno
        gc.stroke(Olo.ellisse(cx, cy, rx, ry), with: .color(Olo.azzurro.opacity(0.22)), lineWidth: 1)
        gc.stroke(Olo.ellisse(cx, cy, rx * 0.7, ry * 0.7), with: .color(Olo.azzurro.opacity(0.14)), lineWidth: 1)
        if let alba = g.alba, let tramonto = g.tramonto, tramonto > alba {
            var giorno = Path()
            Olo.arco(&giorno, cx, cy, rx, ry, th(alba), th(tramonto))
            gc.stroke(giorno, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(piccolo ? 2 : 2.4))
            gc.stroke(giorno, with: .color(Olo.azzurro.opacity(0.12)), style: Olo.tratto(piccolo ? 5 : 8))
        }
        var tacche = Path()
        for o in 0..<24 where !piccolo || o % 3 == 0 {
            let a = punto(Double(o) * 60), b = punto(Double(o) * 60, o % 6 != 0 ? 0.94 : 0.86)
            Olo.linea(&tacche, a.x, a.y, b.x, b.y)
        }
        gc.stroke(tacche, with: .color(Olo.ciano.opacity(0.45)), style: Olo.tratto(1))
        if !piccolo {
            for o in [0, 6, 12, 18] {
                let q = punto(Double(o) * 60, 1.13)
                Olo.testo(&gc, "\(o)", q.x, q.y + 3, corpo: 7, peso: .semibold, Olo.ciano.opacity(0.6))
            }
        }
        // l'arco del sole, da alba a tramonto, e il sole adesso (di notte la luna)
        let hs = piccolo ? h * 0.42 : min(h * 0.36, rx * 0.75)
        if let alba = g.alba, let tramonto = g.tramonto, tramonto > alba {
            func su(_ m: Double) -> (x: Double, y: Double) {
                let p = punto(m), f = (m - alba) / (tramonto - alba)
                return (p.x, p.y - hs * sin(.pi * f))
            }
            var arco = Path()
            arco.addLines((0...40).map { k -> CGPoint in let q = su(alba + (tramonto - alba) * Double(k) / 40); return CGPoint(x: q.x, y: q.y) })
            gc.stroke(arco, with: .color(Olo.ciano.opacity(0.35)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 4]))
            if adesso > alba && adesso < tramonto {
                let s = su(adesso), r0 = piccolo ? 3.5 : 6
                Olo.alone(&gc, CGPoint(x: s.x, y: s.y), piccolo ? 12 : 22, 0.55, Olo.caldo)
                gc.stroke(Olo.ellisse(s.x, s.y, r0, r0), with: .color(Olo.bianco.opacity(0.95)), lineWidth: piccolo ? 1.1 : 1.4)
                var raggi = Path()
                for i in 0..<8 {
                    let r = Double(i) / 8 * 2 * .pi + t * 0.5
                    Olo.linea(&raggi, s.x + cos(r) * r0 * 1.5, s.y + sin(r) * r0 * 1.5, s.x + cos(r) * r0 * 2.15, s.y + sin(r) * r0 * 2.15)
                }
                gc.stroke(raggi, with: .color(Olo.bianco.opacity(0.95)), style: Olo.tratto(piccolo ? 1 : 1.4))
                let terra = punto(adesso)
                var filo = Path()
                Olo.linea(&filo, s.x, s.y + r0 + 2, terra.x, terra.y)
                gc.stroke(filo, with: .color(Olo.azzurro.opacity(0.25)), lineWidth: 1)
            } else {
                luna(&gc, cx, cy - hs * 0.55, piccolo: piccolo)
            }
        } else if DatiGiornata.notte(adesso) {
            luna(&gc, cx, cy - hs * 0.55, piccolo: piccolo)
        }
        // gli impegni: spilli alla loro ora; il prossimo pulsa
        let prossimo = g.impegni.first { $0 >= adesso }
        for m in g.impegni {
            let p = punto(m), passato = m < adesso, qui = m == prossimo, alto = piccolo ? 9.0 : 22.0, r = piccolo ? 2.0 : 3.5
            var spillo = Path()
            Olo.linea(&spillo, p.x, p.y, p.x, p.y - alto)
            gc.stroke(spillo, with: .color(passato ? Olo.azzurro.opacity(0.35) : Olo.ciano.opacity(qui ? 0.95 : 0.7)), lineWidth: qui ? 1.6 : 1.1)
            var rombo = Path()
            rombo.addLines([CGPoint(x: p.x, y: p.y - alto - r - 0.5), CGPoint(x: p.x + r, y: p.y - alto), CGPoint(x: p.x, y: p.y - alto + r + 0.5),
                            CGPoint(x: p.x - r, y: p.y - alto)])
            rombo.closeSubpath()
            gc.fill(rombo, with: .color(passato ? Olo.azzurro.opacity(0.4) : qui ? Olo.bianco : Olo.ciano.opacity(0.85)))
            if qui {
                let v = t.truncatingRemainder(dividingBy: 1.4) / 1.4, rr = 4 + 14 * v
                gc.stroke(Olo.ellisse(p.x, p.y, rr, rr * 0.3), with: .color(Olo.ciano.opacity(0.7 * (1 - v))), lineWidth: 1)
            }
            if !piccolo {
                Olo.testo(&gc, Olo.ora(m), p.x, p.y - alto - 8, corpo: qui ? 8 : 7, peso: .bold,
                          passato ? Olo.azzurro.opacity(0.5) : qui ? Olo.bianco : Olo.ciano.opacity(0.85))
            }
        }
        // adesso: la lancetta sul quadrante
        let q = punto(adesso)
        var lancetta = Path()
        Olo.linea(&lancetta, cx, cy, q.x, q.y)
        gc.stroke(lancetta, with: .color(Olo.bianco.opacity(0.8)), lineWidth: piccolo ? 1 : 1.2)
        Olo.alone(&gc, CGPoint(x: q.x, y: q.y), piccolo ? 6 : 9, 0.6, Olo.bianco)
        gc.fill(Olo.ellisse(q.x, q.y, piccolo ? 1.6 : 2.4, piccolo ? 1.6 : 2.4), with: .color(Olo.bianco))
        guard !piccolo else { return }
        let destra = q.x < w / 2, tx = max(8, min(w - 8, q.x + (destra ? 8 : -8)))
        Olo.testo(&gc, "ADESSO \(Olo.ora(adesso))", tx, q.y + 13, corpo: 7, peso: .bold, Olo.bianco.opacity(0.9), ancora: destra ? .leading : .trailing)
        let n = g.impegni.count
        let testa = n == 0 ? "OGGI · GIORNATA LIBERA"
            : "OGGI · \(n) IMPEGN\(n == 1 ? "O" : "I")" + (prossimo.map { " · PROSSIMO \(Olo.ora($0))" } ?? "")
        Olo.testo(&gc, testa, 10, 14, corpo: 8, peso: .semibold, Olo.ciano.opacity(0.85), ancora: .leading)
        if let alba = g.alba, let tramonto = g.tramonto {
            Olo.testo(&gc, "ALBA \(Olo.ora(alba)) · TRAMONTO \(Olo.ora(tramonto))", w - 10, h - 8, corpo: 7, peso: .semibold,
                      Olo.ciano.opacity(0.7), ancora: .trailing)
        }
    }

    /// La luna di notte (una falce), sopra il quadrante.
    private static func luna(_ gc: inout GraphicsContext, _ x: Double, _ y: Double, piccolo: Bool) {
        let k = piccolo ? 0.6 : 1.0
        Olo.alone(&gc, CGPoint(x: x, y: y), 16 * k, 0.35)
        var falce = Path()
        Olo.arco(&falce, x, y, 7 * k, 7 * k, 0.9, 5.4)
        Olo.arco(&falce, x + 3.5 * k, y - 1.5 * k, 5.6 * k, 5.6 * k, 4.9, 1.2, nuovo: false)
        gc.stroke(falce, with: .color(Olo.bianco.opacity(0.85)), style: Olo.tratto(piccolo ? 1.1 : 1.4))
    }
}

extension DatiGiornata {
    /// Senza alba e tramonto: notte prima delle 7 e dopo le 18.
    static func notte(_ m: Double) -> Bool { m < 420 || m > 1080 }
}

// MARK: - SPESA

/// Un cubo che cade nel carrello (spuntato) o risale (tolta la spunta).
struct VoloSpesa: Equatable {
    let quando: Date
    let su: Bool
    let k: Int
}

/// Il carrello sopra il proiettore (gira appena, di tre quarti). Le cose da prendere sono cubi che gli girano sopra; quelle prese
/// stanno dentro. Spuntata una voce, un cubo ci cade dentro (un lampo e l'onda sul pavimento); tolta la spunta, risale. L'anello
/// del pavimento si riempie quanto la spesa è fatta. In alto quante restano e quante sono prese.
struct OlogrammaSpesa: View {
    let totale: Int
    let presi: Int
    var piccolo = false
    @State private var voli: [VoloSpesa] = []

    var body: some View {
        TelaOlo { gc, size, t, ora in
            DisegnoSpesa.disegna(&gc, size, t: t, ora: ora, tot: totale, presi: min(totale, presi), voli: voli, piccolo: piccolo)
        }
        .onChange(of: presi) { prima, dopo in
            let adesso = Date()
            voli.removeAll { adesso.timeIntervalSince($0.quando) > 1.2 }
            for k in min(prima, dopo)..<max(prima, dopo) { voli.append(VoloSpesa(quando: adesso, su: dopo < prima, k: k)) }
        }
    }
}

enum DisegnoSpesa {
    private static let spigoli: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
    private static let vertici: [SIMD3<Double>] = [SIMD3(-1, -1, -1), SIMD3(1, -1, -1), SIMD3(1, 1, -1), SIMD3(-1, 1, -1),
                                                   SIMD3(-1, -1, 1), SIMD3(1, -1, 1), SIMD3(1, 1, 1), SIMD3(-1, 1, 1)]

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, ora: Date, tot: Int, presi: Int, voli tutti: [VoloSpesa], piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let voli = tutti.map { (v: $0, dt: ora.timeIntervalSince($0.quando)) }.filter { $0.dt >= 0 && $0.dt < 1.2 }
        let cx = w / 2, base = piccolo ? h - 5 : h - 16, rx = piccolo ? w * 0.34 : min(w * 0.22, 80)
        let cy = piccolo ? h * 0.52 : h * 0.6, sz = piccolo ? min(w, h) * 0.24 : min(w * 0.15, h * 0.21)
        let ry = Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 40)
        // l'anello della spesa fatta, sul pavimento
        if tot > 0 && presi > 0 {
            var fatto = Path()
            Olo.arco(&fatto, cx, base, rx * 1.12, ry * 1.12, -.pi / 2, -.pi / 2 + 2 * .pi * Double(presi) / Double(tot))
            gc.stroke(fatto, with: .color(Olo.bianco.opacity(0.85)), style: Olo.tratto(piccolo ? 1.8 : 2.4))
        }
        for (v, dt) in voli where !v.su {
            let o = (dt - 0.55) / 0.6
            if o > 0 && o < 1 {
                gc.stroke(Olo.ellisse(cx, base, rx * (0.4 + 0.8 * o), ry * (0.4 + 0.8 * o)), with: .color(Olo.ciano.opacity(0.6 * (1 - o))), lineWidth: 1.2)
            }
        }
        Olo.cono(&gc, cx, base, rx, cy - sz * 0.9, sz * 1.5, a: 0.09)
        let ang = 0.55 + 0.3 * sin(t * 0.45), al = 0.26
        var g = GruppiOlo(5)
        func p3(_ v: SIMD3<Double>) -> SIMD3<Double> { Olo.proietta(v.x, v.y, v.z, ang, al, cx, cy, sz) }
        func linea(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ k: Int) {
            let o = p3(a), q = p3(b)
            g.metti(k + (o.z + q.z < 0 ? 1 : 0), o, q)
        }
        func cubo(_ c: SIMD3<Double>, _ r: Double, _ giro: Double, _ k: Int) {
            let ca = cos(giro), sa = sin(giro)
            let v = vertici.map { p in p3(SIMD3(c.x + (p.x * ca - p.y * sa) * r, c.y + (p.x * sa + p.y * ca) * r, c.z + p.z * r)) }
            for (i, j) in spigoli { g.metti(k, v[i], v[j]) }
        }
        // il cesto: bordo alto largo, fondo più stretto, le sbarre dei lati
        let alto: [SIMD3<Double>] = [SIMD3(-1, -0.62, 0.55), SIMD3(1, -0.62, 0.55), SIMD3(1, 0.62, 0.55), SIMD3(-1, 0.62, 0.55)]
        let fondo: [SIMD3<Double>] = [SIMD3(-0.78, -0.5, -0.2), SIMD3(0.72, -0.5, -0.2), SIMD3(0.72, 0.5, -0.2), SIMD3(-0.78, 0.5, -0.2)]
        for i in 0..<4 {
            let j = (i + 1) % 4
            linea(alto[i], alto[j], 2); linea(fondo[i], fondo[j], 1); linea(alto[i], fondo[i], 1)
            if !piccolo {
                for s in 1..<5 {
                    let f = Double(s) / 5
                    linea(alto[i] + (alto[j] - alto[i]) * f, fondo[i] + (fondo[j] - fondo[i]) * f, 0)
                }
                linea((alto[i] + fondo[i]) / 2, (alto[j] + fondo[j]) / 2, 0)
            }
        }
        // il manico e le ruote
        linea(SIMD3(1, -0.62, 0.55), SIMD3(1.32, -0.62, 0.86), 2)
        linea(SIMD3(1, 0.62, 0.55), SIMD3(1.32, 0.62, 0.86), 2)
        linea(SIMD3(1.32, -0.62, 0.86), SIMD3(1.32, 0.62, 0.86), 3)
        let raggi = piccolo ? 8 : 12
        for (wx, wy) in [(-0.6, -0.45), (0.55, -0.45), (-0.6, 0.45), (0.55, 0.45)] as [(Double, Double)] {
            linea(SIMD3(wx, wy, -0.2), SIMD3(wx, wy, -0.38), 1)
            for i in 0..<raggi {
                let a = Double(i) / Double(raggi) * 2 * .pi + t * 2, b = Double(i + 1) / Double(raggi) * 2 * .pi + t * 2
                linea(SIMD3(wx + cos(a) * 0.1, wy, -0.48 + sin(a) * 0.1), SIMD3(wx + cos(b) * 0.1, wy, -0.48 + sin(b) * 0.1), 1)
            }
        }
        // le cose prese: dentro, in fila (2 file da 5); quelle da prendere: girano sopra
        func dentro(_ k: Int) -> SIMD3<Double> {
            SIMD3(-0.55 + Double(k % 5) * 0.28, k % 10 < 5 ? -0.18 : 0.2, -0.05 + Double(k / 10) * 0.26)
        }
        func sopra(_ k: Int, _ n: Int) -> SIMD3<Double> {
            let a = t * 0.55 + Double(k) / Double(max(1, n)) * 2 * .pi
            return SIMD3(cos(a) * 1.35, sin(a) * 1.35, 1.3 + 0.08 * sin(t * 1.3 + Double(k)))
        }
        let restano = tot - presi
        for k in 0..<min(presi, 20) where !voli.contains(where: { $0.v.k == k && !$0.v.su }) {
            cubo(dentro(k), 0.1, 0.2, 3)
        }
        for k in 0..<max(0, min(restano, 12)) where !voli.contains(where: { $0.v.su && $0.v.k == presi + k }) {
            cubo(sopra(k, restano), 0.1, t * 1.2 + Double(k), 2)
        }
        var lampi: [(CGPoint, Double)] = []
        for (v, dt) in voli {
            let f = min(1, dt / 0.6), e = v.su ? 1 - pow(1 - f, 2) : f * f, a = sopra(0, max(1, restano)), b = dentro(v.k)
            cubo(v.su ? b + (a - b) * e : a + (b - a) * e, 0.1, t * 3, 4)
            if !v.su && f >= 1 && dt < 0.8 {
                let q = p3(b)
                lampi.append((CGPoint(x: q.x, y: q.y), 0.7 * (1 - (dt - 0.6) / 0.2)))
            }
        }
        g.linee(&gc, colore: { $0 >= 4 ? Olo.bianco.opacity(0.9) : Olo.ciano.opacity(0.14 + 0.17 * Double($0)) },
                spessore: { (piccolo ? 0.8 : 0.9) + Double($0) * 0.12 })
        for (c, a) in lampi { Olo.alone(&gc, c, 16, a, Olo.bianco) }
        guard !piccolo else { return }
        Olo.testo(&gc, tot > 0 ? "DA PRENDERE \(restano)" : "LISTA VUOTA", 10, 14, corpo: 8, peso: .bold, Olo.ciano.opacity(0.9), ancora: .leading)
        if tot > 0 {
            Olo.testo(&gc, "PRESE \(presi) SU \(tot)", w - 10, 14, corpo: 8, peso: .bold,
                      presi == tot ? Olo.bianco : Olo.ciano.opacity(0.85), ancora: .trailing)
        }
    }
}

// MARK: - SERATA · DA DOVE ARRIVANO I SOLDI

/// Le voci dell'incasso di una serata (ingressi contanti, POS, Resident Advisor, bar contanti, bar POS), in euro.
struct DatiSoldi: Equatable {
    struct Fonte: Equatable {
        var nome: String
        var valore: Double
    }
    var fonti: [Fonte]
    var totale: Double { fonti.reduce(0) { $0 + max(0, $1.valore) } }
}

/// Un anello di monete visto dall'alto, che gira piano: una fetta per voce, larga quanto vale e alta quanto pesa, fatta di
/// monete impilate. All'apertura le fette crescono una dopo l'altra mentre i soldi arrivano da fuori e ci cadono dentro, e il
/// totale al centro sale fino all'incasso; poi ogni tanto arriva ancora una moneta (più spesso dove si incassa di più) e una
/// luce fa il giro dell'anello.
struct OlogrammaSoldi: View {
    let dati: DatiSoldi
    var piccolo = false

    var body: some View {
        TelaOlo { gc, size, t, _ in DisegnoSoldi.disegna(&gc, size, t: t, s: dati, piccolo: piccolo) }
    }
}

enum DisegnoSoldi {
    private struct Fetta {
        let da: Double
        let ampiezza: Double
        let alto: Double
        let valore: Double
    }

    private struct Moneta {
        let fetta: Int
        let da: Double
        let dura: Double
        let partenza: SIMD3<Double>
        let posto: Double
    }

    /// Una moneta: sempre la stessa per lo stesso seme (niente stato fra un fotogramma e l'altro).
    private static func moneta(_ seme: Int, fetta: Int, da: Double) -> Moneta {
        let aa = Olo.caso(seme * 7 + 1) * 2 * .pi
        return Moneta(fetta: fetta, da: da + Olo.caso(seme * 7 + 2) * 0.25, dura: 0.75 + Olo.caso(seme * 7 + 3) * 0.35,
                      partenza: SIMD3(cos(aa) * 2.1, sin(aa) * 2.1, 0.5 + Olo.caso(seme * 7 + 4) * 0.9), posto: Olo.caso(seme * 7 + 5))
    }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, s: DatiSoldi, piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        let voci = s.fonti.filter { $0.valore > 0 }
        guard w > 4, h > 4, !voci.isEmpty else { return }
        gc.blendMode = .plusLighter
        let tot = voci.reduce(0) { $0 + $1.valore }, vmax = voci.map(\.valore).max() ?? 1
        let cx = w / 2, cy = h * 0.5, sz = piccolo ? min(w, h) * 0.4 : min(w * 0.27, h * 0.42)
        let ang = t * 0.12, al = 0.62, rR = 1.0, rr = 0.6, gap = 0.035
        Olo.alone(&gc, CGPoint(x: cx, y: cy), sz * 1.25, 0.07)
        var a0 = -Double.pi / 2
        let fette = voci.enumerated().map { i, f -> Fetta in
            let largo = 2 * .pi * f.valore / tot, cresce = Olo.liscia((t - 0.3 - Double(i) * 0.18) / 0.5)
            let fetta = Fetta(da: a0 + gap / 2, ampiezza: max(0, largo - gap) * cresce, alto: (0.08 + 0.42 * f.valore / vmax) * cresce, valore: f.valore)
            a0 += largo
            return fetta
        }
        func p3(_ a: Double, _ r: Double, _ z: Double) -> SIMD3<Double> { Olo.proietta(cos(a) * r, sin(a) * r, z, ang, al, cx, cy, sz) }
        var g = GruppiOlo(6)
        let luceGiro = (t * 0.9).truncatingRemainder(dividingBy: 2 * .pi) - .pi, impila = piccolo ? 0.12 : 0.06
        for f in fette where f.ampiezza > 0.001 {
            let passi = max(3, Int((f.ampiezza / (piccolo ? 0.16 : 0.08)).rounded())), forte = f.valore == vmax ? 1 : 0
            for k in 0..<passi {
                let a = f.da + f.ampiezza * Double(k) / Double(passi), b = f.da + f.ampiezza * Double(k + 1) / Double(passi)
                let o = p3(a, rR, f.alto), q = p3(b, rR, f.alto), dav = o.z + q.z < 0 ? 1 : 0
                let luce = cos(a - luceGiro) > 0.97 ? 1 : 0                          // la luce che fa il giro dell'anello
                g.metti(2 + dav + forte + luce, o, q)                                // il bordo di sopra, fuori
                g.metti(1 + dav, p3(a, rr, f.alto), p3(b, rr, f.alto))              // il bordo di sopra, dentro
                g.metti(dav, p3(a, rR, 0), p3(b, rR, 0))                            // il fondo
                var z = impila
                while z < f.alto { g.metti(dav, p3(a, rR, z), p3(b, rR, z)); z += impila }   // le monete impilate
            }
            for a in [f.da, f.da + f.ampiezza] {
                for r in [rR, rr] { g.metti(2, p3(a, r, 0), p3(a, r, f.alto)) }
                g.metti(2, p3(a, rR, f.alto), p3(a, rr, f.alto))
            }
        }
        g.linee(&gc, colore: { $0 >= 5 ? Olo.bianco.opacity(0.95) : $0 == 4 ? Olo.bianco.opacity(0.6) : Olo.ciano.opacity(0.12 + 0.16 * Double($0)) },
                spessore: { (piccolo ? 0.7 : 0.8) + Double($0) * 0.14 })
        // i soldi che arrivano: all'apertura tanti (quanto pesa ogni fetta), poi uno ogni 0,7 s, dove si incassa di più
        var monete: [Moneta] = []
        var seme = 0
        let quante = piccolo ? 0.5 : 1.0
        for (i, f) in fette.enumerated() {
            let n = Int((quante * (4 + 18 * f.valore / tot * Double(fette.count) / 2)).rounded())
            for _ in 0..<n { monete.append(moneta(seme, fetta: i, da: 0.25)); seme += 1 }
        }
        let ultima = Int(floor((t - 2.4) / 0.7))
        if ultima >= 0 {
            for j in max(0, ultima - 2)...ultima {
                var c = Olo.caso(90_000 + j) * tot, scelta = 0
                for (i, f) in fette.enumerated() { c -= f.valore; if c <= 0 { scelta = i; break } }
                monete.append(moneta(10_000 + j, fetta: scelta, da: 2.4 + 0.7 * Double(j)))
            }
        }
        var scie = Path(), punte: [SIMD3<Double>] = [], arrivi: [(CGPoint, Double)] = []
        for m in monete {
            let v = (t - m.da) / m.dura
            guard v >= 0, v <= 1.25 else { continue }
            let f = fette[m.fetta], am = f.da + f.ampiezza * (0.15 + 0.7 * m.posto)
            let arrivo = SIMD3(cos(am) * (rR + rr) / 2, sin(am) * (rR + rr) / 2, f.alto)
            func dove(_ e: Double) -> SIMD3<Double> {
                let e2 = e * e * (3 - 2 * e)
                return SIMD3(m.partenza.x + (arrivo.x - m.partenza.x) * e2, m.partenza.y + (arrivo.y - m.partenza.y) * e2,
                             m.partenza.z + (arrivo.z - m.partenza.z) * e + 0.5 * sin(.pi * e))
            }
            if v <= 1 {
                let e = min(1, v), o = dove(e), q = dove(max(0, e - 0.08))
                let po = Olo.proietta(o.x, o.y, o.z, ang, al, cx, cy, sz), pq = Olo.proietta(q.x, q.y, q.z, ang, al, cx, cy, sz)
                Olo.linea(&scie, pq.x, pq.y, po.x, po.y)
                punte.append(po)
            } else {
                let pa = Olo.proietta(arrivo.x, arrivo.y, arrivo.z, ang, al, cx, cy, sz)
                arrivi.append((CGPoint(x: pa.x, y: pa.y), 0.6 * (1 - (v - 1) / 0.25)))
            }
        }
        gc.stroke(scie, with: .color(Olo.ciano.opacity(0.45)), lineWidth: 1)
        var dischi = Path()
        let mx = piccolo ? 1.6 : 2.4, my = piccolo ? 0.9 : 1.3
        for p in punte { dischi.addEllipse(in: CGRect(x: p.x - mx, y: p.y - my, width: 2 * mx, height: 2 * my)) }
        gc.fill(dischi, with: .color(Olo.bianco.opacity(0.95)))
        for (c, a) in arrivi { Olo.alone(&gc, c, piccolo ? 6 : 9, a, Olo.bianco) }
        guard !piccolo else { return }
        // il totale al centro, che sale fino all'incasso
        let conta = tot * Olo.liscia((t - 0.2) / 1.4)
        Olo.testo(&gc, "\(Olo.numero(conta.rounded())) €", cx, cy + 3, corpo: 17, peso: .bold, Olo.bianco)
        Olo.testo(&gc, "INCASSO LORDO", cx, cy + 16, corpo: 7, peso: .semibold, Olo.ciano.opacity(0.85))
    }
}

#if os(iOS)
// MARK: - La cornice degli ologrammi nelle sezioni dell'iPhone (come il cuore: fondo, bordo e angoli del visore)

extension View {
    func corniceOlo(_ tinta: Color) -> some View {
        self
            .frame(maxWidth: .infinity)
            .background(tinta.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tinta.opacity(0.22), lineWidth: 1))
            .overlay { AngoliOlo(tinta: tinta).padding(-1).allowsHitTesting(false) }
    }
}
#endif
