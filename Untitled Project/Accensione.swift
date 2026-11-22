import SwiftUI
import CoreGraphics

/// 13.7 · ACCENSIONE, la nascita degli ologrammi della click wheel (scelta del signore, 21 nov 04:32, confermata il 22 nov 01:04):
/// niente proiettore né cono. L'icona grande (104 punti) galleggia nel reattore con la sua luce; quando la ruota si ferma i pezzi
/// dell'icona (la sua forma, cella per cella) arrivano da ogni direzione con la scia e si posano al loro posto, poi l'icona vera si
/// accende tremolando e si rivela dall'alto (come l'avvio SINGOLO). Dietro: un buio morbido (si legge sopra il reattore), sette fili
/// di luce che la attraversano e, a riposo, qualche frammento che le gira attorno. Le staffe si aprono attorno al nome.
/// Uguale al mockup «JARVIS Approvato» (OLX, modo z2). Lo usano l'iPhone (OlogrammaRuota) e il polso (OlogrammaPolso).
/// I tempi (T) sono in millisecondi già moltiplicati per 1,5, come il resto della ruota.
enum Accensione {
    static let fine: Double = 560
    static let lato: Double = 104
    static let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
    static let chiaro = Color(red: 143 / 255, green: 240 / 255, blue: 1)
    static let bianco = Color(red: 223 / 255, green: 250 / 255, blue: 1)

    /// Un pezzo dell'icona: dove si posa (x, y), da dove parte (x0, y0), la misura, quando parte e quanto dura, la sua luce.
    struct Pezzo { let x, y, x0, y0, w, hh, da, dur, a: Double }

    private static func h(_ n: Double) -> Double { let x = sin(n * 12.9898 + 78.233) * 43758.5453; return x - floor(x) }
    private static func C(_ p: Double) -> Double { max(0, min(1, p)) }
    private static func E(_ p: Double) -> Double { 1 - pow(1 - C(p), 3) }

    private static var cache: [String: [Pezzo]] = [:]

    /// I pezzi di un'icona: la si disegna in bianco su una griglia di 26 × 26 e ogni cella piena diventa un pezzo (calcolati una volta
    /// per icona e tenuti da parte).
    static func pezzi<V: View>(_ chiave: String, icona: V) -> [Pezzo] {
        if let c = cache[chiave] { return c }
        let N = 26
        let vista = icona.foregroundStyle(Color.white).frame(width: CGFloat(N), height: CGFloat(N))
        let r = ImageRenderer(content: vista)
        r.scale = 1
        var out: [Pezzo] = []
        if let img = r.cgImage {
            var dati = [UInt8](repeating: 0, count: N * N * 4)
            let spazio = CGColorSpaceCreateDeviceRGB()
            dati.withUnsafeMutableBytes { buf in
                if let ctx = CGContext(data: buf.baseAddress, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N * 4, space: spazio,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: N, height: N))
                }
            }
            let cella = lato / Double(N), mezzo = lato / 2
            for y in 0..<N { for x in 0..<N {
                // la riga 0 del buffer è in alto (CGContext disegna l'immagine dritta nel buffer: la prima riga è quella di sopra)
                let al = Double(dati[(y * N + x) * 4 + 3])
                if al < 70 { continue }
                let i = Double(out.count), dir = h(i * 3.1) * 2 * .pi, dist = 120 + 50 * h(i * 1.7)
                out.append(Pezzo(x: -mezzo + (Double(x) + 0.5) * cella, y: -mezzo + (Double(y) + 0.5) * cella,
                                 x0: cos(dir) * dist, y0: sin(dir) * dist,
                                 w: cella * (h(i * 5.5) > 0.5 ? 1.6 : 0.9), hh: cella * 0.55,
                                 da: 20 + h(i * 2.3) * 220, dur: 130 + 70 * h(i * 8.1), a: al / 255))
            } }
        }
        cache[chiave] = out
        return out
    }

    /// Come appare l'icona vera mentre nasce: quanto è accesa (tremolando), quanta se ne vede dall'alto (0…1), quanto è più chiara.
    static func rivela(_ T: Double) -> (opacita: Double, scoperta: Double, chiarezza: Double) {
        guard T >= 0, T < fine else { return (1, 1, 0) }
        let u = C((T - 290) / 230)
        let fl: [(Double, Double)] = [(0, 0), (0.25, 0.8), (0.4, 0.2), (0.55, 0.95), (0.7, 0.5), (1, 1)]
        var op = 1.0
        if u < 1 {
            for k in 1..<fl.count where u <= fl[k].0 {
                op = fl[k - 1].1 + (fl[k].1 - fl[k - 1].1) * (u - fl[k - 1].0) / (fl[k].0 - fl[k - 1].0)
                break
            }
        }
        return (op, u, 0.6 * (1 - u))
    }

    /// Tutto quello che non è l'icona, centrato sull'icona (coordinate del mockup: il riquadro è 300 × 300).
    /// `forza` è la luce generale (mentre la ruota gira 0,32, ferma 1), `nata` se l'ologramma si è creato, `lungNome` le lettere del nome.
    static func disegna(_ gc: GraphicsContext, centro c: CGPoint, T: Double, t: Double, forza: Double, nata: Bool, lungNome: Int, pezzi: [Pezzo]) {
        var g = gc
        g.translateBy(x: c.x, y: c.y)
        g.opacity = forza
        // il buio morbido dietro, perché la luce si legga sopra il reattore
        g.fill(Path(ellipseIn: CGRect(x: -120, y: -120, width: 240, height: 240)), with: .radialGradient(Gradient(stops: [
            .init(color: Color(red: 2 / 255, green: 9 / 255, blue: 12 / 255).opacity(0.7), location: 0),
            .init(color: Color(red: 2 / 255, green: 9 / 255, blue: 12 / 255).opacity(0.45), location: 0.55),
            .init(color: Color(red: 2 / 255, green: 9 / 255, blue: 12 / 255).opacity(0), location: 1)]), center: .zero, startRadius: 0, endRadius: 120))
        var l = g
        l.blendMode = .plusLighter
        // l'alone dietro l'icona
        l.fill(Path(ellipseIn: CGRect(x: -92, y: -92, width: 184, height: 184)),
               with: .radialGradient(Gradient(colors: [ciano.opacity(0.18), ciano.opacity(0)]), center: .zero, startRadius: 0, endRadius: 92))
        // i fili di luce che attraversano l'icona, sempre
        for i in 0..<7 {
            let fi = Double(i)
            let a = h(fi * 4.1) * .pi + t * 0.05 * (i % 2 == 1 ? 1 : -1), o = (h(fi * 6.2) - 0.5) * 40, Lr = 110.0, cs = cos(a), sn = sin(a)
            let p0 = CGPoint(x: -Lr * cs - o * sn, y: -Lr * sn + o * cs), p1 = CGPoint(x: Lr * cs - o * sn, y: Lr * sn + o * cs)
            var p = Path(); p.move(to: p0); p.addLine(to: p1)
            l.stroke(p, with: .linearGradient(Gradient(stops: [.init(color: ciano.opacity(0), location: 0), .init(color: ciano.opacity(0.35), location: 0.5),
                                                                .init(color: ciano.opacity(0), location: 1)]), startPoint: p0, endPoint: p1),
                     style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }
        // i pezzi che arrivano con la scia e si posano; posati, si accendono bianchi e poi sfumano mentre si accende l'icona vera
        if nata && T < fine && !pezzi.isEmpty {
            var scie = Path()
            var bianchi = Path()
            var luci: [Path] = [Path(), Path(), Path()]
            for q in pezzi {
                let u = (T - q.da) / q.dur
                if u < 0 { continue }
                let e = E(u), px = q.x0 + (q.x - q.x0) * e, py = q.y0 + (q.y - q.y0) * e
                let a = u > 1 ? C(1 - (T - 420) / 140) : 1
                if a <= 0 { continue }
                if u < 1 {
                    let e0 = E(u - 0.18)
                    scie.move(to: CGPoint(x: q.x0 + (q.x - q.x0) * e0, y: q.y0 + (q.y - q.y0) * e0)); scie.addLine(to: CGPoint(x: px, y: py))
                }
                let r = CGRect(x: px - q.w / 2, y: py - q.hh / 2, width: q.w, height: q.hh)
                if u >= 1 && u < 1.25 { bianchi.addRect(r) } else { luci[min(2, Int(q.a * 3))].addRect(r) }
            }
            let fade = T > 420 ? C(1 - (T - 420) / 140) : 1
            l.stroke(scie, with: .color(chiaro.opacity(0.45)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            for k in 0..<3 { l.fill(luci[k], with: .color(chiaro.opacity(0.85 * fade * [0.45, 0.75, 1.0][k]))) }
            l.fill(bianchi, with: .color(bianco.opacity(fade)))
        }
        // a riposo qualche frammento le gira attorno
        var orbita = Path()
        for i in 0..<14 {
            let fi = Double(i), a = h(fi * 2.2) * 2 * .pi + t * (0.3 + 0.2 * h(fi)), r = 64 + 22 * h(fi * 5.5)
            orbita.addRect(CGRect(x: r * cos(a) - 2, y: r * sin(a) * 0.55 - 0.6, width: 4 + 4 * h(fi * 3), height: 1.3))
        }
        l.fill(orbita, with: .color(chiaro.opacity(0.5 + 0.3 * sin(t * 2))))
        // le staffe sul nome
        if nata {
            let sb = E((T - 100) / 220), w = 14 + (Double(lungNome) * 14 / 2 + 8) * sb
            var staffe = Path()
            for sx in [-1.0, 1.0] {
                staffe.move(to: CGPoint(x: sx * (w - 5), y: 62)); staffe.addLine(to: CGPoint(x: sx * w, y: 62))
                staffe.addLine(to: CGPoint(x: sx * w, y: 79)); staffe.addLine(to: CGPoint(x: sx * (w - 5), y: 79))
            }
            g.stroke(staffe, with: .color(ciano.opacity(0.8 * sb)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }
}

/// L'icona dell'ologramma che nasce in ACCENSIONE: si accende tremolando, si rivela dall'alto, con le righe e la luce del mockup
/// (ferma: più chiara, con tre aloni; mentre la ruota gira: al 30 %, alone corto).
struct IconaAccensione<V: View>: View {
    let T: Double
    let ferma: Bool
    let lato: Double
    @ViewBuilder let icona: () -> V

    var body: some View {
        let r = Accensione.rivela(ferma ? T : 1e9)
        icona()
            .foregroundStyle(Accensione.chiaro)
            .frame(width: lato, height: lato)
            .mask {
                VStack(spacing: 0) {
                    Color.black.frame(height: lato * r.scoperta)
                    Color.clear
                }
                .frame(height: lato, alignment: .top)
            }
            .mask { RigheIcona() }
            .brightness(ferma ? 0.25 + 0.6 * r.chiarezza : 0)
            .shadow(color: Accensione.ciano.opacity(ferma ? 1 : 0.45), radius: ferma ? 7 : 3)
            .shadow(color: Accensione.ciano.opacity(ferma ? 0.6 : 0), radius: 18)
            .shadow(color: Accensione.ciano.opacity(ferma ? 0.5 : 0), radius: 28)
            .opacity(ferma ? r.opacita : 0.3)
    }
}
