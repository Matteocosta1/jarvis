import Foundation
import SwiftUI
import WeatherKit

// MARK: - OLOGRAMMI DELLE SEZIONI (11.0 (3), 4 nov) — come il mockup v247 approvato («tutto bellissimo»)
// Canvas in luce additiva, a ogni fotogramma (120 Hz sull'iPhone, 60 sull'orologio), con i tratti raccolti per luminosità.
// CUORE  il cuore batte al ritmo vero (lub-dub), l'anello dice dove sta il battito di adesso e quello a riposo fra il minimo e il
//        massimo di oggi (sull'orologio solo il cuore, piccolo);
// METEO  il cielo di adesso (sole, luna, nuvole, pioggia fitta quanto la probabilità, temporale, neve, nebbia) sopra la rosa dei
//        venti con la freccia da dove soffia il vento.
// Con «Riduci movimento» il disegno resta fermo. Questo file è sia dell'iPhone sia dell'orologio.

/// I colori e gli attrezzi comuni degli ologrammi (OLO_C, OLO_B, OLO_S del mockup).
enum Olo {
    static let ciano = Color(red: 143 / 255, green: 240 / 255, blue: 1)
    static let bianco = Color(red: 240 / 255, green: 253 / 255, blue: 1)
    static let azzurro = Color(red: 79 / 255, green: 227 / 255, blue: 1)
    static let caldo = Color(red: 1, green: 236 / 255, blue: 190 / 255)

    /// Smoothstep: 0…1 morbido ai due capi.
    static func liscia(_ u: Double) -> Double { let v = min(1, max(0, u)); return v * v * (3 - 2 * v) }

    /// Il bagliore tondo che sfuma.
    static func alone(_ gc: inout GraphicsContext, _ c: CGPoint, _ r: Double, _ a: Double, _ col: Color = Olo.ciano) {
        guard a > 0.004, r > 0.5 else { return }
        let q = CGRect(x: Double(c.x) - r, y: Double(c.y) - r, width: 2 * r, height: 2 * r)
        gc.fill(Path(ellipseIn: q), with: .radialGradient(Gradient(colors: [col.opacity(min(1, a)), col.opacity(0)]),
                                                         center: c, startRadius: 0, endRadius: r))
    }

    /// Un'ellisse intera, centrata.
    static func ellisse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    }

    /// Un arco di ellisse da `a0` a `a1` (radianti, in senso orario sullo schermo, come l'arc del Canvas del mockup).
    static func arco(_ p: inout Path, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, nuovo: Bool = true) {
        let passi = max(8, Int(abs(a1 - a0) / (2 * .pi) * 72))
        for i in 0...passi {
            let a = a0 + (a1 - a0) * Double(i) / Double(passi)
            let q = CGPoint(x: cx + cos(a) * rx, y: cy + sin(a) * ry)
            if i == 0 && nuovo { p.move(to: q) } else { p.addLine(to: q) }
        }
    }

    static func linea(_ p: inout Path, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
    }

    static func tratto(_ w: Double) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }

    /// Una scritta monospaziata del disegno.
    static func scritta(_ gc: inout GraphicsContext, _ s: String, _ x: Double, _ y: Double, corpo: Double, peso: Font.Weight,
                        _ col: Color, ancora: UnitPoint = .center) {
        gc.draw(Text(s).font(.system(size: corpo, weight: peso, design: .monospaced)).foregroundStyle(col),
                at: CGPoint(x: x, y: y), anchor: ancora)
    }

    /// Un numero a caso ma sempre uguale per lo stesso seme (le gocce, i fiocchi, le stelle, i fulmini).
    nonisolated static func caso(_ n: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: n &* 2_654_435_761 &+ 1_013_904_223)
        x ^= x >> 15; x = x &* 0x2C1B_3C6D; x ^= x >> 12; x = x &* 0x297A_2D39; x ^= x >> 15
        return Double(x) / Double(UInt32.max)
    }
}

// MARK: - CUORE

/// Il cuore: 9 sagome a cuore una dietro l'altra (le più esterne più piccole) e i meridiani che le uniscono.
nonisolated enum ModelloCuore {
    static let n = 64, k = 9
    static let fette: [[SIMD3<Double>]] = (0..<k).map { j -> [SIMD3<Double>] in
        let y = -0.55 + 1.1 * Double(j) / Double(k - 1)
        let s = max(0, 1 - pow(y / 0.62, 2)).squareRoot()
        return (0...n).map { i -> SIMD3<Double> in
            let t = Double(i) / Double(n) * 2 * .pi
            let x = 16 * pow(sin(t), 3) / 17
            let z = (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 17
            return SIMD3<Double>(x * s, y * 0.62, z * s + 0.12 * (1 - s) + 0.15)
        }
    }
}

/// I numeri del cuore per l'ologramma: battito di adesso, a riposo, minimo e massimo di oggi (0 = non c'è).
struct DatiCuore: Equatable {
    var adesso: Double = 0
    var riposo: Double = 0
    var minimo: Double = 0
    var massimo: Double = 0
}

/// Il cuore in ologramma sopra il proiettore: batte al ritmo di adesso (lub forte, dub più debole dopo un terzo del battito), a
/// ogni colpo l'onda sul pavimento; il piano di scansione sale e scende. Grande: l'anello da 40 a 180 battiti con l'arco di oggi,
/// adesso (il punto pieno), a riposo (il cerchio vuoto) e la legenda. Piccolo (orologio): solo il cuore e il proiettore.
struct OlogrammaCuore: View {
    let dati: DatiCuore
    var piccolo = false
    @Environment(\.accessibilityReduceMotion) private var riduci
    @State private var inizio = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: riduci)) { ctx in
            let t = riduci ? 1 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in DisegnoCuore.disegna(&gc, size, t: t, d: dati, piccolo: piccolo) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum DisegnoCuore {
    /// La proiezione del modello: girato di `ang`, inclinato di 0,2, in prospettiva (3,6). z = profondità (davanti negativo).
    private static func proietta(_ p: SIMD3<Double>, _ ang: Double, _ sc: Double, _ cx: Double, _ cy: Double, _ sz: Double) -> SIMD3<Double> {
        let ca = cos(ang), sa = sin(ang)
        let x = p.x * ca - p.y * sa, y0 = p.x * sa + p.y * ca, al = 0.2
        let y = y0 * cos(al) - p.z * sin(al), z = y0 * sin(al) + p.z * cos(al), k = 3.6 / (3.6 + y)
        return SIMD3<Double>(cx + x * k * sz * sc, cy - z * k * sz * sc, y)
    }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, d: DatiCuore, piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let bpm = min(220, max(30, d.adesso)), periodo = d.adesso > 0 ? 60 / bpm : 0
        // i colpi: lub all'inizio del battito, dub dopo un terzo (al massimo 0,3 s)
        var lub = 0.0, dub = 0.0, colpi: [Double] = []
        if periodo > 0 {
            let n = floor(t / periodo), dd = t - n * periodo, d2 = dd - min(0.3, periodo / 3)
            lub = dd < 0.16 ? sin(dd / 0.16 * .pi) : 0
            dub = d2 > 0 && d2 < 0.13 ? sin(d2 / 0.13 * .pi) * 0.55 : 0
            for k in 0..<4 where n - Double(k) >= 0 { colpi.append((n - Double(k)) * periodo) }
        }
        let batte = max(lub, dub), cx = w / 2, base = h - (piccolo ? 10 : 26), cy = piccolo ? h * 0.42 : h * 0.45
        let sz = piccolo ? min(w, h) * 0.33 : min(w * 0.24, h * 0.31)
        let sc = 1 + 0.07 * lub + 0.035 * dub, ang = 0.62 * sin(t * 0.45)   // oscilla attorno al davanti (±35°): si vede il volume
        // il proiettore: il pavimento con le tacche che girano, l'onda di ogni colpo
        let rx = piccolo ? w * 0.3 : min(w * 0.26, 100), ry = rx * 0.17
        gc.stroke(Olo.ellisse(cx, base, rx, ry), with: .color(Olo.azzurro.opacity(0.32)), lineWidth: 1)
        gc.stroke(Olo.ellisse(cx, base, rx * 0.62, ry * 0.62), with: .color(Olo.azzurro.opacity(0.18)), lineWidth: 1)
        var tacche = Path()
        let nt = piccolo ? 24 : 48
        for i in 0..<nt {
            let a = Double(i) / Double(nt) * 2 * .pi + t * 0.4, c = cos(a), s = sin(a), l = i % 4 != 0 ? 0.9 : 0.8
            Olo.linea(&tacche, cx + c * rx, base + s * ry, cx + c * rx * l, base + s * ry * l)
        }
        gc.stroke(tacche, with: .color(Olo.ciano.opacity(0.5)), style: Olo.tratto(1))
        var lampo = Path()
        Olo.arco(&lampo, cx, base, rx, ry, t * 1.1, t * 1.1 + 0.9)
        gc.stroke(lampo, with: .color(Olo.bianco.opacity(0.55)), style: Olo.tratto(1.6))
        for c0 in colpi {
            let v = (t - c0) / 1.1
            guard v > 0, v < 1 else { continue }
            let e = 1 - pow(1 - v, 2.2)
            gc.stroke(Olo.ellisse(cx, base, rx * (0.35 + 0.9 * e), ry * (0.35 + 0.9 * e)), with: .color(Olo.ciano.opacity(0.55 * (1 - v))),
                      lineWidth: 1.4 * (1 - v) + 0.4)
        }
        // il cono di luce dal proiettore al cuore
        var cono = Path()
        cono.move(to: CGPoint(x: cx - rx * 0.62, y: base))
        cono.addLine(to: CGPoint(x: cx - sz * 1.15, y: cy - sz * 0.75))
        cono.addLine(to: CGPoint(x: cx + sz * 1.15, y: cy - sz * 0.75))
        cono.addLine(to: CGPoint(x: cx + rx * 0.62, y: base))
        cono.closeSubpath()
        gc.fill(cono, with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0.13), Olo.azzurro.opacity(0)]),
                                            startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: cy - sz * 0.9)))
        Olo.alone(&gc, CGPoint(x: cx, y: cy), sz * (1.5 + 0.35 * batte), 0.13 + 0.3 * batte)
        // il cuore: i tratti divisi per profondità (davanti più chiari), un disegno per gruppo
        var gruppi = [Path](repeating: Path(), count: 5)
        let fette = ModelloCuore.fette, nn = ModelloCuore.n, kk = ModelloCuore.k, salto = piccolo ? 2 : 1
        let gruppo: (Double, Double) -> Int = { a, b in Int(((1 - (a + b + 1.1) / 2.2) * 4).rounded()) }
        for j in 0..<kk {
            var q = proietta(fette[j][0], ang, sc, cx, cy, sz)
            for i in stride(from: salto, through: nn, by: salto) {
                let r = proietta(fette[j][i], ang, sc, cx, cy, sz)
                let g = min(4, max(0, gruppo(q.z, r.z)))
                gruppi[g].move(to: CGPoint(x: q.x, y: q.y))
                gruppi[g].addLine(to: CGPoint(x: r.x, y: r.y))
                q = r
            }
        }
        for i in stride(from: 0, to: nn, by: 8) {
            var q = proietta(fette[0][i], ang, sc, cx, cy, sz)
            for j in 1..<kk {
                let r = proietta(fette[j][i], ang, sc, cx, cy, sz)
                let g = min(4, max(0, gruppo(q.z, r.z) - 1))
                gruppi[g].move(to: CGPoint(x: q.x, y: q.y))
                gruppi[g].addLine(to: CGPoint(x: r.x, y: r.y))
                q = r
            }
        }
        for g in 0..<5 {
            let col = g == 4 ? Olo.bianco.opacity(0.55 + 0.4 * batte) : Olo.ciano.opacity(0.1 + 0.15 * Double(g) + 0.22 * batte)
            gc.stroke(gruppi[g], with: .color(col), style: Olo.tratto((piccolo ? 0.8 : 1) + Double(g) * 0.12))
        }
        guard !piccolo else { return }
        // il piano di scansione: sale e scende; dove taglia il cuore, i punti si accendono
        let zs = 0.85 * sin(t * 2.6) - 0.1
        let qz = proietta(SIMD3<Double>(0, 0, zs), ang, sc, cx, cy, sz)
        gc.stroke(Olo.ellisse(cx, qz.y, sz * 1.25, sz * 0.2), with: .color(Olo.ciano.opacity(0.32)), lineWidth: 1)
        var punti = Path()
        for j in stride(from: 0, to: kk, by: 2) {
            let sl = fette[j]
            for i in 0..<nn {
                let a = sl[i], b = sl[i + 1]
                if (a.z - zs) * (b.z - zs) > 0 { continue }
                let den = b.z - a.z, f = den == 0 ? 0 : (zs - a.z) / den
                let r = proietta(SIMD3<Double>(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, zs), ang, sc, cx, cy, sz)
                punti.addEllipse(in: CGRect(x: r.x - 1.6, y: r.y - 1.6, width: 3.2, height: 3.2))
            }
        }
        gc.fill(punti, with: .color(Olo.bianco.opacity(0.85)))
        // l'anello: da 40 a 180 battiti su 270°, con l'arco di oggi, adesso e a riposo
        guard d.adesso > 0 else { return }
        let r = min(w * 0.4, cy - 14), a0 = Double.pi * 0.75, giro = Double.pi * 1.5
        let ang0: (Double) -> Double = { b in a0 + giro * max(0, min(1, (b - 40) / 140)) }
        var anello = Path()
        Olo.arco(&anello, cx, cy, r, r, a0, a0 + giro)
        gc.stroke(anello, with: .color(Olo.azzurro.opacity(0.22)), lineWidth: 1)
        var scala = Path()
        for b in stride(from: 40, through: 180, by: 10) {
            let a = ang0(Double(b)), l: Double = b % 50 == 0 || b == 40 ? 7 : 4
            Olo.linea(&scala, cx + cos(a) * r, cy + sin(a) * r, cx + cos(a) * (r + l), cy + sin(a) * (r + l))
        }
        gc.stroke(scala, with: .color(Olo.azzurro.opacity(0.4)), style: Olo.tratto(1))
        if d.minimo > 0, d.massimo > 0 {
            var oggi = Path()
            Olo.arco(&oggi, cx, cy, r, r, ang0(d.minimo), ang0(d.massimo))
            gc.stroke(oggi, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(3))
            gc.stroke(oggi, with: .color(Olo.azzurro.opacity(0.12)), style: Olo.tratto(7))
        }
        if d.riposo > 0 {
            let a = ang0(d.riposo)
            gc.stroke(Olo.ellisse(cx + cos(a) * r, cy + sin(a) * r, 4, 4), with: .color(Olo.bianco.opacity(0.8)), lineWidth: 1.4)
        }
        let aa = ang0(bpm), px = cx + cos(aa) * r, py = cy + sin(aa) * r
        Olo.alone(&gc, CGPoint(x: px, y: py), 12 + 8 * batte, 0.5 + 0.4 * batte, Olo.bianco)
        gc.fill(Olo.ellisse(px, py, 3.2 + 1.2 * batte, 3.2 + 1.2 * batte), with: .color(Olo.bianco))
        // le scritte: la scala (40, 100, 180), il minimo e il massimo di oggi accanto all'arco, la legenda in basso a sinistra
        gc.blendMode = .normal
        for b in [40.0, 100, 180] {
            let a = ang0(b)
            Olo.scritta(&gc, String(Int(b)), cx + cos(a) * (r + 15), cy + sin(a) * (r + 15), corpo: 8, peso: .semibold, Olo.ciano.opacity(0.6))
        }
        if d.minimo > 0, d.massimo > 0 {
            for b in [d.minimo, d.massimo] {
                let a = ang0(b), c = cos(a), s = sin(a)
                let ancora: UnitPoint = c < -0.2 ? .trailing : c > 0.2 ? .leading : .center
                Olo.scritta(&gc, String(Int(b.rounded())), cx + c * (r + 13), cy + s * (r + 13), corpo: 10, peso: .bold, Olo.bianco.opacity(0.95), ancora: ancora)
            }
        }
        for (k, nome) in ["ADESSO", "A RIPOSO", "OGGI"].enumerated() {
            Olo.scritta(&gc, nome, 22, h - 41 + Double(k) * 13, corpo: 8, peso: .semibold, Olo.ciano.opacity(0.85), ancora: .leading)
        }
        gc.fill(Olo.ellisse(14, h - 41, 2.6, 2.6), with: .color(Olo.bianco))
        gc.stroke(Olo.ellisse(14, h - 28, 2.6, 2.6), with: .color(Olo.bianco.opacity(0.8)), lineWidth: 1.2)
        var trattino = Path()
        Olo.linea(&trattino, 10, h - 15, 18, h - 15)
        gc.stroke(trattino, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(3))
    }
}

// MARK: - METEO

/// Il cielo di adesso per l'ologramma (da Apple Meteo): com'è, la probabilità di pioggia (0-100), il vento (km/h) e da dove soffia.
struct StatoCielo: Equatable {
    enum Cielo: Equatable { case sereno, notte, nuvole, pioggia, temporale, neve, nebbia }
    var cielo: Cielo = .nuvole
    var pioggia: Double = 0
    var vento: Double = 0
    var ventoDa: Double = 225

    init(cielo: Cielo = .nuvole, pioggia: Double = 0, vento: Double = 0, ventoDa: Double = 225) {
        self.cielo = cielo; self.pioggia = pioggia; self.vento = vento; self.ventoDa = ventoDa
    }

    /// Dal meteo di adesso; `probabilita` è quella di pioggia della prossima ora (0-1).
    init(_ c: CurrentWeather, probabilita: Double?) {
        self.init(cielo: StatoCielo.cielo(c.condition, giorno: c.isDaylight),
                  pioggia: (probabilita ?? 0) * 100,
                  vento: c.wind.speed.converted(to: .kilometersPerHour).value,
                  ventoDa: c.wind.direction.converted(to: .degrees).value)
    }

    static func cielo(_ c: WeatherCondition, giorno: Bool) -> Cielo {
        switch c {
        case .clear, .mostlyClear, .hot, .frigid: return giorno ? .sereno : .notte
        case .partlyCloudy, .mostlyCloudy, .cloudy, .breezy, .windy: return .nuvole
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain: return .pioggia
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms, .tropicalStorm, .hurricane: return .temporale
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .sleet, .wintryMix, .hail: return .neve
        case .foggy, .haze, .smoky, .blowingDust: return .nebbia
        default: return .nuvole
        }
    }
}

/// Il cielo di adesso sopra un piccolo proiettore, con la rosa dei venti (N in alto) e la freccia che viene da dove soffia il
/// vento; più vento, più veloci le linee del vento. La pioggia cade fitta quanto la probabilità e fa i cerchi sul pavimento.
struct OlogrammaCielo: View {
    let stato: StatoCielo
    var piccolo = false
    @Environment(\.accessibilityReduceMotion) private var riduci
    @State private var inizio = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: riduci)) { ctx in
            let t = riduci ? 1 : ctx.date.timeIntervalSince(inizio)
            Canvas { gc, size in DisegnoCielo.disegna(&gc, size, t: t, s: stato, piccolo: piccolo) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum DisegnoCielo {
    /// Gocce (posto, fase, velocità), fiocchi (posto, fase, velocità, giro) e stelle (x, y, fase): sempre gli stessi.
    nonisolated private static let gocce: [(x: Double, f: Double, v: Double)] = (0..<34).map { i in
        (x: Olo.caso(i * 3 + 1), f: Olo.caso(i * 3 + 2), v: 0.75 + Olo.caso(i * 3 + 3) * 0.5)
    }
    nonisolated private static let fiocchi: [(x: Double, f: Double, v: Double, o: Double)] = (0..<16).map { i in
        (x: Olo.caso(500 + i * 4), f: Olo.caso(501 + i * 4), v: 0.22 + Olo.caso(502 + i * 4) * 0.2, o: Olo.caso(503 + i * 4) * 6.28)
    }
    nonisolated private static let stelle: [(x: Double, y: Double, o: Double)] = (0..<9).map { i in
        (x: Olo.caso(900 + i * 3) * 2 - 1, y: Olo.caso(901 + i * 3), o: Olo.caso(902 + i * 3) * 6.28)
    }
    /// I fulmini: uno ogni 1,6-3,4 s (20 intervalli che si ripetono), il primo a 1,4 s.
    nonisolated private static let fulmini: [Double] = {
        var v: [Double] = [], t = 1.4
        for i in 0..<20 { v.append(t); t += 1.6 + Olo.caso(1300 + i) * 1.8 }
        v.append(t)
        return v
    }()
    /// Gli sbuffi della nuvola: x, y, raggio (in unità della nuvola).
    nonisolated private static let sbuffi: [(x: Double, y: Double, r: Double)] = [(x: -0.55, y: 0.12, r: 0.42), (x: 0, y: -0.12, r: 0.55),
                                                                                    (x: 0.55, y: 0.1, r: 0.4), (x: 0.05, y: 0.22, r: 0.45)]

    /// L'ultimo fulmine prima di `t` (i 20 intervalli si ripetono).
    private static func fulmine(_ t: Double) -> Double {
        let giro = fulmini[fulmini.count - 1] - 1.4, tt = t < 1.4 ? t : 1.4 + (t - 1.4).truncatingRemainder(dividingBy: giro)
        var ultimo = -9.0
        for f in fulmini.dropLast() where f <= tt { ultimo = f }
        return ultimo < 0 ? -9 : t - (tt - ultimo)
    }

    private static func nuvola(_ gc: inout GraphicsContext, _ cx: Double, _ cy: Double, _ s: Double, _ t: Double, _ al: Double, _ scan: Double, piccolo: Bool) {
        let d = sin(t * 0.5) * 0.04
        var bordo = Path()
        for (k, b) in sbuffi.enumerated() {
            var su = false
            for i in 0...40 {
                let a = Double(i) / 40 * 2 * .pi, px = b.x + d + cos(a) * b.r, py = b.y + sin(a) * b.r
                var dentro = py > 0.42
                if !dentro {
                    for (j, q) in sbuffi.enumerated() where j != k && hypot(px - q.x - d, py - q.y) < q.r - 0.004 { dentro = true; break }
                }
                if dentro { su = false; continue }
                let p = CGPoint(x: cx + px * s, y: cy + py * s)
                if su { bordo.addLine(to: p) } else { bordo.move(to: p); su = true }
            }
        }
        Olo.linea(&bordo, cx + (-0.95 + d) * s, cy + 0.42 * s, cx + (0.95 + d) * s, cy + 0.42 * s)
        gc.stroke(bordo, with: .color(Olo.ciano.opacity(al)), style: Olo.tratto(piccolo ? 1 : 1.3))
        guard scan > 0 else { return }
        var righe = Path()
        for yy in stride(from: -0.6, to: 0.42, by: piccolo ? 0.16 : 0.1) {
            var l = 9.0, r = -9.0
            for b in sbuffi {
                let dy = yy - b.y
                if abs(dy) < b.r { let w = (b.r * b.r - dy * dy).squareRoot(); l = min(l, b.x - w); r = max(r, b.x + w) }
            }
            if r > l { Olo.linea(&righe, cx + (l + d + 0.06) * s, cy + yy * s, cx + (r + d - 0.06) * s, cy + yy * s) }
        }
        gc.stroke(righe, with: .color(Olo.azzurro.opacity(scan)), style: Olo.tratto(1))
    }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, s st: StatoCielo, piccolo: Bool) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let cx = w / 2, base = h - (piccolo ? 7 : 17), rx = w * 0.4, ry = rx * 0.18, cy = h * (piccolo ? 0.42 : 0.4)
        let s = min(w, h) * (piccolo ? 0.3 : 0.27)
        // il proiettore con la rosa dei venti: N in alto (dietro), la freccia viene da dove soffia
        gc.stroke(Olo.ellisse(cx, base, rx, ry), with: .color(Olo.azzurro.opacity(0.3)), lineWidth: 1)
        var tacche = Path()
        for i in 0..<16 {
            let a = Double(i) / 16 * 2 * .pi, l = i % 4 != 0 ? 0.88 : 0.74
            Olo.linea(&tacche, cx + cos(a) * rx, base + sin(a) * ry, cx + cos(a) * rx * l, base + sin(a) * ry * l)
        }
        gc.stroke(tacche, with: .color(Olo.azzurro.opacity(0.45)), style: Olo.tratto(1))
        let dir = st.ventoDa * .pi / 180, ax = sin(dir), ay = -cos(dir)
        let da = CGPoint(x: cx + ax * rx, y: base + ay * ry), a2 = CGPoint(x: cx + ax * rx * 0.25, y: base + ay * ry * 0.25)
        let angF = atan2(Double(a2.y - da.y), Double(a2.x - da.x))
        var freccia = Path()
        freccia.move(to: da); freccia.addLine(to: a2)
        Olo.linea(&freccia, Double(a2.x), Double(a2.y), Double(a2.x) - cos(angF - 0.5) * 6, Double(a2.y) - sin(angF - 0.5) * 6)
        Olo.linea(&freccia, Double(a2.x), Double(a2.y), Double(a2.x) - cos(angF + 0.5) * 6, Double(a2.y) - sin(angF + 0.5) * 6)
        gc.stroke(freccia, with: .color(Olo.bianco.opacity(0.9)), style: Olo.tratto(1.6))
        if !piccolo {
            gc.blendMode = .normal
            let punti: [(String, Double)] = [("N", -Double.pi / 2), ("E", 0), ("S", Double.pi / 2), ("O", Double.pi)]
            for (l, a) in punti { Olo.scritta(&gc, l, cx + cos(a) * (rx + 7), base + sin(a) * (ry + 6), corpo: 7, peso: .semibold, Olo.ciano.opacity(0.7)) }
            gc.blendMode = .plusLighter
        }
        // il vento: linee che scorrono nel verso in cui va (più vento, più veloci e più numerose)
        if st.vento >= 8 {
            let n = min(6, 2 + Int((st.vento / 10).rounded())), vx = -ax, sp = 0.25 + st.vento / 60
            var righe = Path()
            for i in 0..<n {
                let f = (t * sp + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1), yy = cy - s * 0.9 + Double(i) / Double(n) * s * 1.9
                let x0 = cx + (vx >= 0 ? -1 : 1) * w * 0.55 + vx * f * w * 1.1, l = 14 + Double(i % 3) * 6
                Olo.linea(&righe, x0, yy, x0 - vx * l, yy + sin(t * 3 + Double(i)) * 1.5)
            }
            gc.stroke(righe, with: .color(Olo.azzurro.opacity(0.4)), style: Olo.tratto(1))
        }
        var cono = Path()
        cono.move(to: CGPoint(x: cx - rx * 0.55, y: base))
        cono.addLine(to: CGPoint(x: cx - s * 1.15, y: cy - s * 0.7))
        cono.addLine(to: CGPoint(x: cx + s * 1.15, y: cy - s * 0.7))
        cono.addLine(to: CGPoint(x: cx + rx * 0.55, y: base))
        cono.closeSubpath()
        gc.fill(cono, with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0.11), Olo.azzurro.opacity(0)]),
                                            startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: cy - s)))
        Olo.alone(&gc, CGPoint(x: cx, y: cy), s * 2.1, 0.12)
        switch st.cielo {
        case .sereno:   // il sole: una sfera di linee che gira, i raggi che respirano
            let r = s * 0.62
            Olo.alone(&gc, CGPoint(x: cx, y: cy), r * 2.4, 0.3, Olo.caldo)
            gc.stroke(Olo.ellisse(cx, cy, r, r), with: .color(Olo.ciano.opacity(0.75)), lineWidth: 1.3)
            var sfera = Path()
            for k in -2...2 {
                let yy = Double(k) / 3 * r, ww = (r * r - yy * yy).squareRoot()
                sfera.addPath(Olo.ellisse(cx, cy + yy, ww, ww * 0.22))
            }
            for k in 0..<3 {
                let a = t * 0.6 + Double(k) * .pi / 3, ww = abs(cos(a)) * r
                sfera.addPath(Olo.ellisse(cx, cy, max(0.5, ww), r))
            }
            gc.stroke(sfera, with: .color(Olo.ciano.opacity(0.35)), lineWidth: 1)
            var raggi = Path()
            for i in 0..<12 {
                let a = Double(i) / 12 * 2 * .pi + t * 0.25, l = r * (1.32 + 0.12 * sin(t * 2 + Double(i)))
                Olo.linea(&raggi, cx + cos(a) * r * 1.16, cy + sin(a) * r * 1.16, cx + cos(a) * l, cy + sin(a) * l)
            }
            gc.stroke(raggi, with: .color(Olo.bianco.opacity(0.8)), style: Olo.tratto(1.4))
        case .notte:   // la luna (falce) e le stelle che brillano
            let r = s * 0.55
            Olo.alone(&gc, CGPoint(x: cx, y: cy), r * 2, 0.22)
            var luna = Path()
            Olo.arco(&luna, cx, cy, r, r, .pi * 0.32, .pi * 1.68)
            Olo.arco(&luna, cx + r * 0.42, cy - r * 0.12, r * 0.8, r * 0.8, .pi * 1.58, .pi * 0.42, nuovo: false)
            luna.closeSubpath()
            gc.stroke(luna, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(1.4))
            var punti = Path()
            for q in stelle {
                let a = 0.4 + 0.6 * abs(sin(t * 1.3 + q.o)), px = cx + q.x * s * 1.6, py = cy - s * 0.9 + q.y * s * 1.2, rr = 0.6 + a
                punti.addEllipse(in: CGRect(x: px - rr, y: py - rr, width: 2 * rr, height: 2 * rr))
            }
            gc.fill(punti, with: .color(Olo.bianco))
        case .nuvole, .pioggia, .temporale, .neve, .nebbia:
            let temp = st.cielo == .temporale, piove = st.cielo == .pioggia || temp
            let lampo = temp ? max(0, 1 - (t - fulmine(t)) / 0.16) : 0
            if st.cielo == .nebbia {
                var banchi = Path()
                for i in 0..<5 {
                    let yy = cy - s * 0.5 + Double(i) * s * 0.32, o = sin(t * 0.6 + Double(i)) * s * 0.3
                    Olo.linea(&banchi, cx - s * 1.1 + o, yy, cx + s * (0.6 + 0.4 * Double(i % 2)) + o, yy)
                }
                gc.stroke(banchi, with: .color(Olo.ciano.opacity(0.4)), style: Olo.tratto(2))
            } else {
                nuvola(&gc, cx, cy - s * 0.15, s, t, 0.75 + 0.25 * lampo, temp ? 0.32 + 0.4 * lampo : 0.18, piccolo: piccolo)
            }
            if lampo > 0 {
                Olo.alone(&gc, CGPoint(x: cx, y: cy), s * 1.8, 0.5 * lampo, Olo.bianco)
                var zig = Path()
                var px = cx + s * 0.1, py = cy + s * 0.3
                zig.move(to: CGPoint(x: px, y: py))
                for i in 0..<4 { px += (i % 2 != 0 ? 1 : -1) * s * 0.16; py += (base - cy - s * 0.3) / 4; zig.addLine(to: CGPoint(x: px, y: py)) }
                gc.stroke(zig, with: .color(Olo.bianco.opacity(lampo)), style: Olo.tratto(1.8))
            }
            if piove {   // tante gocce quanta la probabilità, piegate dal vento; i cerchi sul pavimento
                let n = Int((Double(gocce.count) * max(0.25, min(1, st.pioggia / 90))).rounded()), y0 = cy + s * 0.32, y1 = base
                let inclina = -ax * min(0.5, st.vento / 50)
                var g0 = Path(), g1 = Path(), g2 = Path()
                for i in 0..<n {
                    let q = gocce[i], f = (t * q.v * 1.4 + q.f).truncatingRemainder(dividingBy: 1)
                    let px = cx + (q.x - 0.5) * s * 1.7 + inclina * f * (y1 - y0), py = y0 + f * (y1 - y0)
                    if f > 0.85 { Olo.linea(&g2, px, py, px - inclina * 7, py - 7) } else { Olo.linea(&g1, px, py, px - inclina * 7, py - 7) }
                    if f > 0.93 { let v = (f - 0.93) / 0.07; Olo.linea(&g0, px - 4 * v, y1, px + 4 * v, y1) }
                }
                gc.stroke(g1, with: .color(Olo.ciano.opacity(0.75)), style: Olo.tratto(1.2))
                gc.stroke(g2, with: .color(Olo.bianco.opacity(0.7)), style: Olo.tratto(1.2))
                gc.stroke(g0, with: .color(Olo.azzurro.opacity(0.6)), style: Olo.tratto(1))
            }
            if st.cielo == .neve {
                var neve = Path()
                for q in fiocchi {
                    let f = (t * q.v + q.f).truncatingRemainder(dividingBy: 1)
                    let px = cx + (q.x - 0.5) * s * 1.7 + sin(t * 1.4 + q.o) * 5, py = cy + s * 0.32 + f * (base - cy - s * 0.32), rr = 2.4
                    for k in 0..<3 {
                        let a = Double(k) * .pi / 3 + t * 0.8 + q.o
                        Olo.linea(&neve, px - cos(a) * rr, py - sin(a) * rr, px + cos(a) * rr, py + sin(a) * rr)
                    }
                }
                gc.stroke(neve, with: .color(Olo.bianco.opacity(0.85)), style: Olo.tratto(1))
            }
        }
    }
}
