#if os(iOS)
import SwiftUI
import AVFoundation
import Vision
import CoreVideo
import CoreGraphics
import CoreMedia
import Foundation
import simd

/// BUILD 23 — L'OLOGRAMMA alla Stark, in comune tra il Trainer (modalità Ologramma) e gli Occhi (riconoscimento dal vivo).
/// Tutto come il mockup approvato (mockup 23: sagomaLaser, lineamentiLaser, etichettaOlo, nuvola, disegnaNuvola):
/// la sagoma laser sul soggetto, i lineamenti in laser (i bordi veri del fotogramma dentro la sagoma), i cartellini
/// che non si sovrappongono mai, la nuvola di punti 3D della scheda.
/// Le coordinate delle analisi sono sempre «normalizzate dall'alto»: u da sinistra (0…1), v dall'alto (0…1),
/// nel fotogramma verticale così come arriva dalla fotocamera (non specchiato). Lo specchio della frontale lo fa `Inquadra`.

// MARK: - Colori del mockup

nonisolated enum TintaOlo {
    /// 79,227,255: il celeste di JARVIS.
    static let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
    /// 170,244,255: il secondo tono, un celeste più chiaro (mani, gomiti, gesti, le persone negli Occhi).
    static let ambra = Color(red: 170 / 255, green: 244 / 255, blue: 1)
    /// 190,248,255: il bordo che brilla.
    static let filo = Color(red: 190 / 255, green: 248 / 255, blue: 1)
    /// 4,10,12: il fondo dei cartellini.
    static let fondo = Color(red: 4 / 255, green: 10 / 255, blue: 12 / 255)
    /// 3,9,11: il fondo della scheda del bersaglio.
    static let fondoScheda = Color(red: 3 / 255, green: 9 / 255, blue: 11 / 255)
}

// MARK: - L'inquadratura: dal fotogramma allo schermo

/// La fotocamera riempie lo schermo (resizeAspectFill, come AVCaptureVideoPreviewLayer): il fotogramma si ingrandisce
/// finché copre tutto e i bordi in più restano fuori. La frontale si vede specchiata (come la anteprima di iOS).
nonisolated struct Inquadra {
    let W: CGFloat, H: CGFloat
    let iw: CGFloat, ih: CGFloat
    let specchio: Bool
    let s: CGFloat

    init(schermo: CGSize, immagine: CGSize, specchio: Bool) {
        W = max(1, schermo.width); H = max(1, schermo.height)
        iw = max(1, immagine.width); ih = max(1, immagine.height)
        self.specchio = specchio
        s = max(W / iw, H / ih)
    }

    /// L'unità di misura del mockup: 1 su uno schermo largo 390 punti.
    var k: CGFloat { min(W, H) / 390 }

    func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let x = W / 2 + (u * iw - iw / 2) * s
        return CGPoint(x: specchio ? W - x : x, y: H / 2 + (v * ih - ih / 2) * s)
    }

    func p(_ q: CGPoint) -> CGPoint { p(q.x, q.y) }

    /// Un riquadro normalizzato sullo schermo (con lo specchio, sinistra e destra si scambiano).
    func rett(_ r: CGRect) -> CGRect {
        let a = p(r.minX, r.minY), b = p(r.maxX, r.maxY)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Da un punto dello schermo (un tocco) al fotogramma.
    func normalizzato(_ q: CGPoint) -> CGPoint {
        let x = specchio ? W - q.x : q.x
        return CGPoint(x: ((x - W / 2) / s + iw / 2) / iw, y: ((q.y - H / 2) / s + ih / 2) / ih)
    }

    /// Il contorno chiuso di una sagoma (punti normalizzati) sullo schermo.
    func percorso(_ punti: [CGPoint]) -> Path {
        var path = Path()
        guard let primo = punti.first else { return path }
        path.move(to: p(primo))
        for q in punti.dropFirst() { path.addLine(to: p(q)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - I cartellini già messi in questo fotogramma (per non sovrapporli)

nonisolated struct PostiEtichette {
    var rett: [CGRect] = []
    var alto: CGFloat
    var basso: CGFloat

    /// Come `etichetteNuovoGiro` del mockup: i cartellini restano tra `alto` (sotto la testata) e `basso` (sopra i tasti).
    init(H: CGFloat, k: CGFloat, alto: CGFloat = 118, basso: CGFloat = 250) {
        self.alto = alto * k
        self.basso = H - basso * k
    }
}

// MARK: - Il disegno (stessa grafica del mockup)

nonisolated enum DisegnoOlo {
    static func mono(_ dimensione: CGFloat, _ peso: Font.Weight) -> Font { .system(size: max(1, dimensione), weight: peso, design: .monospaced) }

    /// «1,2»: la virgola all'italiana.
    static func nf(_ v: Double, _ decimali: Int = 1) -> String {
        String(format: "%.\(decimali)f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// La sagoma laser: riempimento a righe, una banda che scorre, il bordo che brilla e i trattini che corrono lungo il contorno.
    static func sagomaLaser(_ gc: GraphicsContext, _ p: Path, t: Double, k: CGFloat, a: Double, col: Color = TintaOlo.ciano) {
        guard a > 0, !p.isEmpty, k > 0 else { return }
        let b = p.boundingRect
        guard b.width > 1, b.height > 1 else { return }
        let y0 = b.minY, y1 = b.maxY
        var c = gc
        c.clip(to: p)
        c.fill(Path(CGRect(x: b.minX, y: y0, width: b.width, height: y1 - y0)), with: .color(col.opacity(0.045 * a)))
        let passo = 5 * k
        var righe = Path()
        var y = y0 + CGFloat((t * 24 * Double(k)).truncatingRemainder(dividingBy: Double(passo)))
        while y < y1 {
            righe.addRect(CGRect(x: b.minX, y: y, width: b.width, height: 1.1 * k))
            y += passo
        }
        c.fill(righe, with: .color(col.opacity(0.085 * a)))
        let yb = y0 + CGFloat(t.truncatingRemainder(dividingBy: 2.4) / 2.4) * (y1 - y0)
        c.fill(Path(CGRect(x: b.minX, y: yb - 40 * k, width: b.width, height: 46 * k)),
               with: .linearGradient(Gradient(colors: [col.opacity(0), col.opacity(0.26 * a)]),
                                     startPoint: CGPoint(x: b.minX, y: yb - 40 * k), endPoint: CGPoint(x: b.minX, y: yb + 6 * k)))
        gc.stroke(p, with: .color(col.opacity(0.16 * a)), style: StrokeStyle(lineWidth: 7 * k, lineJoin: .round))
        gc.stroke(p, with: .color(TintaOlo.filo.opacity(0.9 * a)), style: StrokeStyle(lineWidth: 1.6 * k, lineJoin: .round))
        gc.stroke(p, with: .color(Color.white.opacity(0.85 * a)),
                  style: StrokeStyle(lineWidth: 2.6 * k, lineJoin: .round, dash: [2.5 * k, 11 * k], dashPhase: -CGFloat(t) * 46 * k))
    }

    /// I lineamenti in laser: prima il soggetto si scurisce un poco (sui soggetti chiari il celeste si perderebbe nel bianco),
    /// poi i bordi del fotogramma, già colorati, si sommano alla ripresa. Solo dentro la sagoma.
    /// `immagine` è nel verso del fotogramma: con la frontale si disegna specchiata.
    static func lineamenti(_ gc: GraphicsContext, immagine: CGImage, in r: CGRect, clip: Path, specchio: Bool, a: Double) {
        guard a > 0, r.width > 2, r.height > 2, !clip.isEmpty else { return }
        var c = gc
        c.clip(to: clip)
        c.fill(Path(r), with: .color(Color(red: 0, green: 10 / 255, blue: 14 / 255).opacity(0.42 * a)))
        c.blendMode = .plusLighter
        c.opacity = a * 0.85
        if specchio {
            c.translateBy(x: r.midX, y: 0)
            c.scaleBy(x: -1, y: 1)
            c.translateBy(x: -r.midX, y: 0)
        }
        c.draw(Image(decorative: immagine, scale: 1), in: r)
    }

    /// Il cartellino: pallino sul punto, filo, scatola con la riga di colore. Se tocca un altro cartellino scende (o sale)
    /// di quel che serve, sempre tra `posti.alto` e `posti.basso`.
    static func etichetta(_ gc: GraphicsContext, _ posti: inout PostiEtichette, k: CGFloat, W: CGFloat, ax: CGFloat, ay: CGFloat,
                          lx lx0: CGFloat, ly: CGFloat, righe: [String], a: Double, col: Color = TintaOlo.ciano, grande: Bool = false) {
        guard a > 0, let prima = righe.first else { return }
        var c = gc
        c.opacity = a
        var filo = Path()
        filo.move(to: CGPoint(x: ax, y: ay))
        filo.addLine(to: CGPoint(x: lx0, y: ly))
        c.stroke(filo, with: .color(col.opacity(0.85)), lineWidth: 1.2 * k)
        c.fill(Path(ellipseIn: CGRect(x: ax - 2.6 * k, y: ay - 2.6 * k, width: 5.2 * k, height: 5.2 * k)), with: .color(col))
        let f1 = (grande ? 13 : 10.5) * k, f2 = 9 * k, pad = 6 * k
        let t1 = c.resolve(Text(prima).font(mono(f1, .bold)).foregroundStyle(Color.white))
        let altre = righe.dropFirst().map { c.resolve(Text($0).font(mono(f2, .medium)).foregroundStyle(col)) }
        let libero = CGSize(width: 10_000, height: 10_000)
        var w = t1.measure(in: libero).width
        for r in altre { w = max(w, r.measure(in: libero).width) }
        let h = f1 + CGFloat(altre.count) * (f2 + 3 * k) + pad * 1.6
        var bx = lx0 < ax ? lx0 - w - 2 * pad : lx0
        bx = max(4 * k, min(W - w - 2 * pad - 4 * k, bx))
        let lx = lx0 < ax ? bx + w + 2 * pad : bx
        var by = max(posti.alto, min(posti.basso - h, ly - h / 2))
        for _ in 0..<8 {
            guard let urto = posti.rett.first(where: { bx < $0.maxX && bx + w + 2 * pad > $0.minX && by < $0.maxY + 3 * k && by + h + 3 * k > $0.minY })
            else { break }
            let giu = urto.maxY + 4 * k, su = urto.minY - h - 4 * k
            by = giu + h <= posti.basso ? giu : (su >= posti.alto ? su : giu)
        }
        posti.rett.append(CGRect(x: bx, y: by, width: w + 2 * pad, height: h))
        let scatola = Path(roundedRect: CGRect(x: bx, y: by, width: w + 2 * pad, height: h), cornerRadius: 5 * k)
        c.fill(scatola, with: .color(TintaOlo.fondo.opacity(0.72)))
        c.stroke(scatola, with: .color(col.opacity(0.7)), lineWidth: 1 * k)
        c.fill(Path(CGRect(x: lx < ax ? bx + w + 2 * pad - 2 * k : bx, y: by + 3 * k, width: 2 * k, height: h - 6 * k)), with: .color(col))
        c.draw(t1, at: CGPoint(x: bx + pad, y: by + pad * 0.8), anchor: .topLeading)
        for (i, r) in altre.enumerated() {
            c.draw(r, at: CGPoint(x: bx + pad, y: by + pad * 0.8 + f1 + 3 * k + CGFloat(i) * (f2 + 3 * k)), anchor: .topLeading)
        }
    }

    /// La nuvola di punti 3D che oscilla (rotazione attorno all'asse verticale, prospettiva leggera); i punti più chiari brillano di più.
    /// Per non fare migliaia di disegni separati i punti si raggruppano in 8 livelli di luce.
    static func nuvola(_ gc: GraphicsContext, _ nv: Nuvola, mx: CGFloat, my: CGFloat, scala: CGFloat, r: Double, k: CGFloat, col: Color, specchio: Bool) {
        let cs = cos(r), sn = sin(r), prof = Double(min(nv.w, nv.h)) * 0.55, f = 260.0
        var secchi = [Path](repeating: Path(), count: 8)
        for q in nv.punti {
            let X = Double(specchio ? -q.x : q.x), Y = Double(q.y), Z = (Double(q.z) - 0.5) * prof
            let Xr = X * cs + Z * sn, Zr = -X * sn + Z * cs
            let s = f / (f + Zr) * Double(scala)
            let livello = min(7, max(0, Int(Double(q.w) * 8)))
            secchi[livello].addRect(CGRect(x: mx + CGFloat(Xr * s) - 0.9 * k, y: my + CGFloat(Y * s) - 0.9 * k, width: 1.8 * k, height: 1.8 * k))
        }
        for (i, p) in secchi.enumerated() where !p.isEmpty {
            gc.fill(p, with: .color(col.opacity(0.18 + (Double(i) + 0.5) / 8 * 0.82)))
        }
    }

    /// I bordi dello schermo appena scuri, verso il blu-nero di JARVIS.
    static func vignetta(_ gc: GraphicsContext, W: CGFloat, H: CGFloat, interno: CGFloat, alfa: Double) {
        gc.fill(Path(CGRect(x: 0, y: 0, width: W, height: H)),
                with: .radialGradient(Gradient(colors: [Color.clear, Color(red: 0, green: 8 / 255, blue: 12 / 255).opacity(alfa)]),
                                      center: CGPoint(x: W / 2, y: H / 2), startRadius: min(W, H) * interno, endRadius: max(W, H) * 0.75))
    }

    /// Angolo in gradi tra a-b-c (b al vertice), nel piano dell'immagine.
    static func angolo(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Int {
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y), v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let d = (hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)) + 1e-6
        let cosx = max(-1, min(1, (v1.dx * v2.dx + v1.dy * v2.dy) / d))
        return Int((acos(Double(cosx)) * 180 / .pi).rounded())
    }

    /// Dai 21 punti della mano (in pixel del fotogramma): quali dita sono distese. Come `gesto` del mockup.
    static func gesto(_ m: [CGPoint?]) -> String? {
        guard m.count == 21 else { return nil }
        func q(_ i: Int) -> CGPoint? { m[i] }
        func d(_ a: Int, _ b: Int) -> CGFloat? { guard let p = q(a), let r = q(b) else { return nil }; return hypot(p.x - r.x, p.y - r.y) }
        var su: [Bool] = []
        for (p, r) in [(8, 6), (12, 10), (16, 14), (20, 18)] {
            guard let a = d(p, 0), let b = d(r, 0) else { return nil }
            su.append(a > b * 1.12)
        }
        guard let p4 = d(4, 17), let p3 = d(3, 17), let p45 = d(4, 5), let p25 = d(2, 5), let p09 = d(0, 9),
              let t4 = q(4), let t5 = q(5) else { return nil }
        let pol = p4 > p3 * 1.08 && p45 > p25 * 0.9
        let n = su.filter { $0 }.count
        if pol && n == 0 && t4.y < t5.y - p09 * 0.25 { return "POLLICE SU" }
        if n == 0 && !pol { return "PUGNO" }
        if su[0] && su[1] && !su[2] && !su[3] { return "VITTORIA" }
        if su[0] && !su[1] && !su[2] && !su[3] { return "INDICA" }
        if n >= 4 { return "MANO APERTA" }
        return nil
    }
}

// MARK: - La nuvola di punti

/// Punti (x, y, profondità 0…1, luce 0…1), in pixel della nuvola (lato massimo 110), centrati.
nonisolated struct Nuvola: Sendable {
    var punti: [SIMD4<Float>]
    var w: CGFloat
    var h: CGFloat
}

// MARK: - La griglia delle maschere di Vision e i contorni

/// Una maschera di Vision ridotta a griglia (lato lungo ≤ 192): ogni cella ha l'etichetta dell'istanza (0 = sfondo).
nonisolated struct GrigliaMaschera: Sendable {
    let w: Int
    let h: Int
    var dati: [UInt8]

    func a(_ u: CGFloat, _ v: CGFloat) -> UInt8 {
        let x = min(w - 1, max(0, Int(u * CGFloat(w)))), y = min(h - 1, max(0, Int(v * CGFloat(h))))
        return dati[y * w + x]
    }
}

/// Una sagoma: il contorno (normalizzato), il riquadro, quanta parte del fotogramma copre e la sua griglia (1 = dentro).
nonisolated struct Sagoma: Sendable {
    var contorno: [CGPoint]
    var box: CGRect
    var area: CGFloat
    var griglia: GrigliaMaschera
    var etichetta: UInt8
}

nonisolated enum Maschere {
    /// La maschera delle istanze (VNInstanceMaskObservation.instanceMask: 0 sfondo, 1…n le istanze) come griglia piccola.
    static func griglia(_ o: VNInstanceMaskObservation, lato: Int = 192) -> GrigliaMaschera? {
        let px = o.instanceMask
        let mw = CVPixelBufferGetWidth(px), mh = CVPixelBufferGetHeight(px)
        guard mw > 1, mh > 1 else { return nil }
        let scala = min(1, Double(lato) / Double(max(mw, mh)))
        let w = max(2, Int((Double(mw) * scala).rounded())), h = max(2, Int((Double(mh) * scala).rounded()))
        let formato = CVPixelBufferGetPixelFormatType(px)
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return nil }
        let riga = CVPixelBufferGetBytesPerRow(px)
        var dati = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = dati.withUnsafeMutableBufferPointer { d in
            for y in 0..<h {
                let my = min(mh - 1, Int((Double(y) + 0.5) * Double(mh) / Double(h)))
                let r = base.advanced(by: my * riga)
                for x in 0..<w {
                    let mx = min(mw - 1, Int((Double(x) + 0.5) * Double(mw) / Double(w)))
                    switch formato {
                    case kCVPixelFormatType_OneComponent8:
                        d[y * w + x] = r.assumingMemoryBound(to: UInt8.self)[mx]
                    case kCVPixelFormatType_OneComponent32Float:
                        let v = r.assumingMemoryBound(to: Float.self)[mx]
                        d[y * w + x] = UInt8(max(0, min(255, v.rounded())))
                    case kCVPixelFormatType_OneComponent16:
                        d[y * w + x] = UInt8(min(255, r.assumingMemoryBound(to: UInt16.self)[mx]))
                    case kCVPixelFormatType_OneComponent16Half:
                        d[y * w + x] = UInt8(max(0, min(255, mezzo(r.assumingMemoryBound(to: UInt16.self)[mx]).rounded())))
                    default:
                        return false
                    }
                }
            }
            return true
        }
        return ok ? GrigliaMaschera(w: w, h: h, dati: dati) : nil
    }

    /// Un numero a mezza precisione (IEEE 754, 16 bit) in Float, senza Float16 (che non c'è su tutti i processori).
    static func mezzo(_ b: UInt16) -> Float {
        let segno: Float = (b & 0x8000) != 0 ? -1 : 1
        let esponente = Int((b >> 10) & 0x1F), mantissa = Float(b & 0x3FF)
        if esponente == 0 { return segno * mantissa / 1024 * pow(2, -14) }
        if esponente == 31 { return mantissa == 0 ? segno * .infinity : .nan }
        return segno * (1 + mantissa / 1024) * pow(2, Float(esponente - 15))
    }

    /// Le sagome di tutte le istanze (la parte più grande di ognuna), dalla più grande alla più piccola.
    /// `minimo`: le istanze più piccole di questa frazione del fotogramma non contano.
    static func sagome(_ g: GrigliaMaschera, istanze: IndexSet, minimo: CGFloat = 0.002) -> [Sagoma] {
        var out: [Sagoma] = []
        for i in istanze where i > 0 && i < 256 {
            if let s = sagoma(g, etichetta: UInt8(i)), s.area >= minimo { out.append(s) }
        }
        return out.sorted { $0.area > $1.area }
    }

    /// La parte più grande (8-connessa) dell'istanza `etichetta`, con il suo contorno.
    static func sagoma(_ g: GrigliaMaschera, etichetta: UInt8) -> Sagoma? {
        let w = g.w, h = g.h, n = w * h
        var visto = [UInt8](repeating: 0, count: n)
        var migliore: [Int] = []
        var pila: [Int] = []
        pila.reserveCapacity(1024)
        g.dati.withUnsafeBufferPointer { d in
            visto.withUnsafeMutableBufferPointer { v in
                for s in 0..<n where d[s] == etichetta && v[s] == 0 {
                    var parte: [Int] = []
                    v[s] = 1
                    pila.append(s)
                    while let c = pila.popLast() {
                        parte.append(c)
                        let cx = c % w, cy = c / w
                        for dy in -1...1 {
                            let ny = cy + dy
                            if ny < 0 || ny >= h { continue }
                            for dx in -1...1 {
                                let nx = cx + dx
                                if nx < 0 || nx >= w || (dx == 0 && dy == 0) { continue }
                                let j = ny * w + nx
                                if d[j] == etichetta && v[j] == 0 { v[j] = 1; pila.append(j) }
                            }
                        }
                    }
                    if parte.count > migliore.count { migliore = parte }
                }
            }
        }
        guard migliore.count >= 3 else { return nil }
        var dentro = [UInt8](repeating: 0, count: n)
        var x0 = w, y0 = h, x1 = 0, y1 = 0, primo = n
        for c in migliore {
            dentro[c] = 1
            let x = c % w, y = c / w
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            primo = min(primo, c)
        }
        let bordo = dentro.withUnsafeBufferPointer { traccia($0, w: w, h: h, inizio: primo) }
        guard bordo.count >= 3 else { return nil }
        let semplice = levigato(semplifica(bordo.map { CGPoint(x: CGFloat($0.0), y: CGFloat($0.1)) }, epsilon: 0.8))
        let contorno = semplice.map { CGPoint(x: ($0.x + 0.5) / CGFloat(w), y: ($0.y + 0.5) / CGFloat(h)) }
        let box = CGRect(x: CGFloat(x0) / CGFloat(w), y: CGFloat(y0) / CGFloat(h),
                         width: CGFloat(x1 - x0 + 1) / CGFloat(w), height: CGFloat(y1 - y0 + 1) / CGFloat(h))
        return Sagoma(contorno: contorno, box: box, area: CGFloat(migliore.count) / CGFloat(n),
                      griglia: GrigliaMaschera(w: w, h: h, dati: dentro), etichetta: etichetta)
    }

    /// Il bordo esterno con il metodo dei vicini di Moore: si parte dalla prima cella (dall'alto, da sinistra), entrati da ovest,
    /// e si gira in senso orario finché, tornati nella prima cella, il passo dopo è di nuovo il primo (vale anche per le linee sottili).
    static func traccia(_ m: UnsafeBufferPointer<UInt8>, w: Int, h: Int, inizio: Int) -> [(Int, Int)] {
        let dx = [-1, -1, 0, 1, 1, 1, 0, -1]        // O, NO, N, NE, E, SE, S, SO: orario sullo schermo (y verso il basso)
        let dy = [0, -1, -1, -1, 0, 1, 1, 1]
        func verso(_ x: Int, _ y: Int) -> Int {
            switch (x, y) {
            case (-1, 0): return 0
            case (-1, -1): return 1
            case (0, -1): return 2
            case (1, -1): return 3
            case (1, 0): return 4
            case (1, 1): return 5
            case (0, 1): return 6
            default: return 7
            }
        }
        let sx = inizio % w, sy = inizio / w
        var cx = sx, cy = sy, dir = 0
        var out: [(Int, Int)] = [(sx, sy)]
        var secondo: (Int, Int)?
        var passi = 0
        let massimo = 4 * w * h + 8
        while passi < massimo {
            var prossimo: (Int, Int, Int)?
            for i in 1...8 {
                let d = (dir + i) % 8
                let nx = cx + dx[d], ny = cy + dy[d]
                if nx >= 0, ny >= 0, nx < w, ny < h, m[ny * w + nx] != 0 {
                    let prima = (dir + i - 1) % 8
                    let bx = cx + dx[prima], by = cy + dy[prima]     // la cella vuota appena guardata: il nuovo «da dove vengo»
                    prossimo = (nx, ny, verso(bx - nx, by - ny))
                    break
                }
            }
            guard let passo = prossimo else { break }             // una cella sola
            let (nx, ny, nd) = passo
            // di nuovo nella prima cella e il passo dopo è lo stesso della prima volta: il giro è chiuso
            if let s2 = secondo, cx == sx, cy == sy, nx == s2.0, ny == s2.1 { break }
            if secondo == nil { secondo = (nx, ny) }
            cx = nx; cy = ny; dir = nd
            passi += 1
            if !(cx == sx && cy == sy) { out.append((cx, cy)) }
        }
        return out
    }

    /// Douglas-Peucker su un contorno chiuso; se restano più di 360 punti si semplifica di più.
    static func semplifica(_ p: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard p.count > 4 else { return p }
        var eps = epsilon
        var r = dp(p, eps)
        while r.count > 360 { eps *= 1.5; r = dp(p, eps) }
        return r
    }

    private static func dp(_ p: [CGPoint], _ eps: CGFloat) -> [CGPoint] {
        // chiuso: si spezza nel punto più lontano dal primo, poi le due metà
        let a = p[0]
        var lontano = 0, dmax: CGFloat = -1
        for (i, q) in p.enumerated() {
            let d = hypot(q.x - a.x, q.y - a.y)
            if d > dmax { dmax = d; lontano = i }
        }
        guard lontano > 0 else { return [a] }
        var tieni = [Bool](repeating: false, count: p.count)
        tieni[0] = true; tieni[lontano] = true
        var pila: [(Int, Int)] = [(0, lontano), (lontano, p.count)]
        while let tratto = pila.popLast() {
            let (i, j) = tratto
            let b = p[i], c = p[j % p.count]
            guard j - i > 1 else { continue }
            var kmax = -1, dm: CGFloat = 0
            let lx = c.x - b.x, ly = c.y - b.y, l = hypot(lx, ly)
            for k in (i + 1)..<j {
                let q = p[k]
                let d = l < 1e-6 ? hypot(q.x - b.x, q.y - b.y) : abs((q.x - b.x) * ly - (q.y - b.y) * lx) / l
                if d > dm { dm = d; kmax = k }
            }
            if kmax >= 0, dm > eps {
                tieni[kmax] = true
                pila.append((i, kmax)); pila.append((kmax, j))
            }
        }
        var out: [CGPoint] = []
        for (i, q) in p.enumerated() where tieni[i] { out.append(q) }
        return out
    }

    /// Un passaggio di Chaikin: gli scalini della griglia diventano una linea morbida.
    static func levigato(_ p: [CGPoint]) -> [CGPoint] {
        guard p.count >= 3 else { return p }
        var out: [CGPoint] = []
        out.reserveCapacity(p.count * 2)
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            out.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
            out.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
        }
        return out
    }
}

// MARK: - I lineamenti (Sobel) e la nuvola, dal fotogramma vero

nonisolated enum ImmagineOlo {
    /// I bordi del fotogramma nella `regione` (normalizzata), come `lineamentiLaser` del mockup: luce → filtro di Sobel →
    /// celeste che schiarisce sui bordi forti, trasparente dove non c'è bordo. Al massimo 60.000 pixel (il mockup fa lo stesso).
    /// Il fotogramma deve essere BGRA.
    static func lineamenti(_ px: CVPixelBuffer, regione r: CGRect, massimo: Int = 60_000) -> CGImage? {
        guard CVPixelBufferGetPixelFormatType(px) == kCVPixelFormatType_32BGRA else { return nil }
        let iw = CVPixelBufferGetWidth(px), ih = CVPixelBufferGetHeight(px)
        let x0 = max(0, Int((r.minX * CGFloat(iw)).rounded(.down))), y0 = max(0, Int((r.minY * CGFloat(ih)).rounded(.down)))
        let x1 = min(iw, Int((r.maxX * CGFloat(iw)).rounded(.up))), y1 = min(ih, Int((r.maxY * CGFloat(ih)).rounded(.up)))
        let bw = x1 - x0, bh = y1 - y0
        guard bw >= 8, bh >= 8 else { return nil }
        let ds = max(1, (Double(bw * bh) / Double(massimo)).squareRoot())
        let w = max(8, Int((Double(bw) / ds).rounded())), h = max(8, Int((Double(bh) / ds).rounded()))
        guard let L = luce(px, x0: x0, y0: y0, bw: bw, bh: bh, w: w, h: h) else { return nil }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        let cr: Float = 79, cg: Float = 227, cb: Float = 255
        L.withUnsafeBufferPointer { l in
            out.withUnsafeMutableBufferPointer { o in
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        let j = y * w + x
                        // Sobel 3×3: sopra (a), riga (b), sotto (c)
                        let a0 = l[j - w - 1], a1 = l[j - w], a2 = l[j - w + 1]
                        let b0 = l[j - 1], b2 = l[j + 1]
                        let c0 = l[j + w - 1], c1 = l[j + w], c2 = l[j + w + 1]
                        let gx: Float = (a2 + c2 - a0 - c0) + 2 * (b2 - b0)
                        let gy: Float = (c0 + c2 - a0 - a2) + 2 * (c1 - a1)
                        let forza: Float = (gx * gx + gy * gy).squareRoot()
                        let e: Float = min(1, max(0, (forza - 0.14) * 2.4))
                        let v: Float = min(1, e + l[j] * 0.14)
                        let m = j * 4
                        o[m] = UInt8(min(255, (cr + (255 - cr) * e * 0.6) * v))          // colore già moltiplicato per l'alfa
                        o[m + 1] = UInt8(min(255, (cg + (255 - cg) * e * 0.45) * v))
                        o[m + 2] = UInt8(min(255, cb * v))
                        o[m + 3] = UInt8(min(255, v * 255))
                    }
                }
            }
        }
        return rgba(out, w: w, h: h)
    }

    /// La luce (0…1) del fotogramma BGRA, ridotta a w×h: la media di 4 campioni per cella.
    static func luce(_ px: CVPixelBuffer, x0: Int, y0: Int, bw: Int, bh: Int, w: Int, h: Int) -> [Float]? {
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return nil }
        let riga = CVPixelBufferGetBytesPerRow(px)
        let src = base.assumingMemoryBound(to: UInt8.self)
        let sx = Double(bw) / Double(w), sy = Double(bh) / Double(h)
        var L = [Float](repeating: 0, count: w * h)
        L.withUnsafeMutableBufferPointer { l in
            for y in 0..<h {
                let ya = y0 + min(bh - 1, Int((Double(y) + 0.25) * sy)), yb = y0 + min(bh - 1, Int((Double(y) + 0.75) * sy))
                let ra = src + ya * riga, rb = src + yb * riga
                for x in 0..<w {
                    let xa = (x0 + min(bw - 1, Int((Double(x) + 0.25) * sx))) * 4
                    let xb = (x0 + min(bw - 1, Int((Double(x) + 0.75) * sx))) * 4
                    // BGRA: rosso ×0,3, verde ×0,59, blu ×0,11 (come il mockup)
                    let r4: Float = Float(ra[xa + 2]) + Float(ra[xb + 2]) + Float(rb[xa + 2]) + Float(rb[xb + 2])
                    let g4: Float = Float(ra[xa + 1]) + Float(ra[xb + 1]) + Float(rb[xa + 1]) + Float(rb[xb + 1])
                    let b4: Float = Float(ra[xa]) + Float(ra[xb]) + Float(rb[xa]) + Float(rb[xb])
                    l[y * w + x] = (r4 * 0.3 + g4 * 0.59 + b4 * 0.11) / 1020
                }
            }
        }
        return L
    }

    static func rgba(_ dati: [UInt8], w: Int, h: Int) -> CGImage? {
        guard let fonte = CGDataProvider(data: Data(dati) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: fonte, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    /// La nuvola di punti 3D da UN fotogramma (come `nuvola` del mockup): i pixel del soggetto dentro la sagoma, uno ogni due,
    /// con la profondità «gonfiata» dal bordo (al centro è più vicino, sul bordo scende) e la luce del pixel.
    static func nuvola(_ px: CVPixelBuffer, sagoma s: Sagoma) -> Nuvola? {
        let iw = CVPixelBufferGetWidth(px), ih = CVPixelBufferGetHeight(px)
        let b = s.box
        let bw = b.width * CGFloat(iw), bh = b.height * CGFloat(ih)
        guard bw >= 4, bh >= 4 else { return nil }
        let sc = 110 / max(bw, bh)
        let w = max(4, Int((bw * sc).rounded())), h = max(4, Int((bh * sc).rounded()))
        let cw = (w + 1) / 2, ch = (h + 1) / 2                     // un campione ogni 2 pixel
        guard let L = luce(px, x0: max(0, Int(b.minX * CGFloat(iw))), y0: max(0, Int(b.minY * CGFloat(ih))),
                           bw: max(1, min(iw - Int(b.minX * CGFloat(iw)), Int(bw))), bh: max(1, min(ih - Int(b.minY * CGFloat(ih)), Int(bh))),
                           w: cw, h: ch) else { return nil }
        // dentro o fuori, cella per cella (dalla griglia della sagoma)
        var dentro = [Bool](repeating: false, count: cw * ch)
        for y in 0..<ch {
            for x in 0..<cw {
                let u = b.minX + (CGFloat(x) + 0.5) / CGFloat(cw) * b.width, v = b.minY + (CGFloat(y) + 0.5) / CGFloat(ch) * b.height
                dentro[y * cw + x] = s.griglia.a(u, v) != 0
            }
        }
        // distanza dal bordo (chamfer 3-4 in due passate), in celle
        let inf: Float = 1e9
        var d = dentro.map { $0 ? inf : 0 }
        for y in 0..<ch {
            for x in 0..<cw where d[y * cw + x] > 0 {
                var m = d[y * cw + x]
                if x == 0 || y == 0 { m = min(m, 1) }
                if x > 0 { m = min(m, d[y * cw + x - 1] + 1) }
                if y > 0 { m = min(m, d[(y - 1) * cw + x] + 1) }
                if x > 0 && y > 0 { m = min(m, d[(y - 1) * cw + x - 1] + 1.414) }
                if x < cw - 1 && y > 0 { m = min(m, d[(y - 1) * cw + x + 1] + 1.414) }
                d[y * cw + x] = m
            }
        }
        for y in stride(from: ch - 1, through: 0, by: -1) {
            for x in stride(from: cw - 1, through: 0, by: -1) where d[y * cw + x] > 0 {
                var m = d[y * cw + x]
                if x == cw - 1 || y == ch - 1 { m = min(m, 1) }
                if x < cw - 1 { m = min(m, d[y * cw + x + 1] + 1) }
                if y < ch - 1 { m = min(m, d[(y + 1) * cw + x] + 1) }
                if x < cw - 1 && y < ch - 1 { m = min(m, d[(y + 1) * cw + x + 1] + 1.414) }
                if x > 0 && y < ch - 1 { m = min(m, d[(y + 1) * cw + x - 1] + 1.414) }
                d[y * cw + x] = m
            }
        }
        let dmax = max(1, d.max() ?? 1)
        var punti: [SIMD4<Float>] = []
        punti.reserveCapacity(cw * ch)
        for y in 0..<ch {
            for x in 0..<cw where dentro[y * cw + x] {
                let X = Float(x * 2) - Float(w) / 2, Y = Float(y * 2) - Float(h) / 2
                punti.append(SIMD4<Float>(X, Y, (d[y * cw + x] / dmax).squareRoot(), L[y * cw + x]))
            }
        }
        return punti.isEmpty ? nil : Nuvola(punti: punti, w: CGFloat(w), h: CGFloat(h))
    }
}

// MARK: - La maglia del viso (Delaunay, Bowyer-Watson)

/// Un triangolo con il suo cerchio circoscritto (centro e raggio al quadrato).
nonisolated struct TriangoloDelaunay {
    var a: Int, b: Int, c: Int
    var cx: CGFloat, cy: CGFloat, r2: CGFloat
}

nonisolated enum Delaunay {
    /// I triangoli (indici) della triangolazione di Delaunay dei punti. Per i ~76 punti del viso bastano pochi decimi di millisecondo.
    static func triangoli(_ p: [CGPoint]) -> [(Int, Int, Int)] {
        let n = p.count
        guard n >= 3 else { return [] }
        var minX = p[0].x, minY = p[0].y, maxX = p[0].x, maxY = p[0].y
        for q in p { minX = min(minX, q.x); minY = min(minY, q.y); maxX = max(maxX, q.x); maxY = max(maxY, q.y) }
        let dm = max(maxX - minX, maxY - minY, 1e-6), mx = (minX + maxX) / 2, my = (minY + maxY) / 2
        var v = p
        v.append(CGPoint(x: mx - 1000 * dm, y: my - dm))      // il triangolo «grande» deve essere molto più grande: se no si perdono i bordi
        v.append(CGPoint(x: mx, y: my + 1000 * dm))
        v.append(CGPoint(x: mx + 1000 * dm, y: my - dm))
        typealias T = TriangoloDelaunay
        func crea(_ a: Int, _ b: Int, _ c: Int) -> T {
            let A = v[a], B = v[b], C = v[c]
            let d = 2 * (A.x * (B.y - C.y) + B.x * (C.y - A.y) + C.x * (A.y - B.y))
            if abs(d) < 1e-12 { return T(a: a, b: b, c: c, cx: 0, cy: 0, r2: .greatestFiniteMagnitude) }
            let a2 = A.x * A.x + A.y * A.y, b2 = B.x * B.x + B.y * B.y, c2 = C.x * C.x + C.y * C.y
            let ux = (a2 * (B.y - C.y) + b2 * (C.y - A.y) + c2 * (A.y - B.y)) / d
            let uy = (a2 * (C.x - B.x) + b2 * (A.x - C.x) + c2 * (B.x - A.x)) / d
            return T(a: a, b: b, c: c, cx: ux, cy: uy, r2: (A.x - ux) * (A.x - ux) + (A.y - uy) * (A.y - uy))
        }
        var tri = [crea(n, n + 1, n + 2)]
        for i in 0..<n {
            let q = v[i]
            var cattivi: [Int] = []
            for (j, t) in tri.enumerated() where (q.x - t.cx) * (q.x - t.cx) + (q.y - t.cy) * (q.y - t.cy) <= t.r2 { cattivi.append(j) }
            var lati: [(Int, Int)] = []
            for j in cattivi {
                let t = tri[j]
                for (a, b) in [(t.a, t.b), (t.b, t.c), (t.c, t.a)] {
                    if let k = lati.firstIndex(where: { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }) { lati.remove(at: k) }
                    else { lati.append((a, b)) }
                }
            }
            for j in cattivi.sorted(by: >) { tri.remove(at: j) }
            for (a, b) in lati { tri.append(crea(a, b, i)) }
        }
        return tri.filter { $0.a < n && $0.b < n && $0.c < n }.map { ($0.a, $0.b, $0.c) }
    }
}

// MARK: - L'ottica e il LiDAR

nonisolated enum Ottica {
    /// La focale in pixel del fotogramma: il campo visivo orizzontale del formato vale sul lato lungo del sensore
    /// (nel fotogramma verticale è l'altezza). Con la fotocamera virtuale lo zoom 1 del dispositivo è il campo più largo.
    static func fuoco(campo gradi: Float, latoLungo: Int, zoom: CGFloat = 1) -> Double {
        let g = Double(gradi > 1 ? gradi : 70)
        return Double(latoLungo) / 2 / tan(g / 2 * .pi / 180) * Double(max(zoom, 0.1))
    }

    /// Il campo visivo da usare: quello con la correzione della distorsione, se è accesa.
    static func campo(_ d: AVCaptureDevice) -> Float {
        let f = d.activeFormat
        if d.isGeometricDistortionCorrectionEnabled, f.geometricDistortionCorrectedVideoFieldOfView > 1 { return f.geometricDistortionCorrectedVideoFieldOfView }
        return f.videoFieldOfView
    }
}

/// L'ultima mappa di profondità del LiDAR (metri), già nel verso del fotogramma se la connessione la ruota.
nonisolated final class MappaProfondita: @unchecked Sendable {
    private let lucchetto = NSLock()
    private var w = 0, h = 0
    private var dati: [Float] = []
    private var quando = Date.distantPast
    /// false: la mappa è nel verso del sensore (orizzontale) e va ruotata di 90° per il fotogramma verticale.
    var ruotata = true

    func aggiorna(_ d: AVDepthData) {
        let m = d.depthDataType == kCVPixelFormatType_DepthFloat32 ? d : d.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let px = m.depthDataMap
        let mw = CVPixelBufferGetWidth(px), mh = CVPixelBufferGetHeight(px)
        guard mw > 0, mh > 0 else { return }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(px) else { return }
        let riga = CVPixelBufferGetBytesPerRow(px)
        var nuovi = [Float](repeating: 0, count: mw * mh)
        nuovi.withUnsafeMutableBufferPointer { o in
            for y in 0..<mh {
                let r = base.advanced(by: y * riga).assumingMemoryBound(to: Float.self)
                for x in 0..<mw { o[y * mw + x] = r[x] }
            }
        }
        lucchetto.lock()
        w = mw; h = mh; dati = nuovi; quando = Date()
        lucchetto.unlock()
    }

    func svuota() {
        lucchetto.lock(); dati = []; w = 0; h = 0; lucchetto.unlock()
    }

    /// I metri nel punto (u, v) del fotogramma verticale: la mediana dei valori buoni in un 5×5, solo tra 0,2 e 5 m (oltre il LiDAR non è affidabile).
    func metri(_ u: CGFloat, _ v: CGFloat) -> Double? {
        lucchetto.lock()
        defer { lucchetto.unlock() }
        guard w > 0, h > 0, Date().timeIntervalSince(quando) < 0.5 else { return nil }
        // ruotata: stesso verso del fotogramma; altrimenti il sensore è orizzontale e il fotogramma è girato di 90° in senso orario
        let uu = min(1, max(0, u)), vv = min(1, max(0, v))
        let sx = ruotata ? uu : vv, sy = ruotata ? vv : 1 - uu
        let cx = min(w - 1, Int(sx * CGFloat(w))), cy = min(h - 1, Int(sy * CGFloat(h)))
        var buoni: [Float] = []
        for y in max(0, cy - 2)...min(h - 1, cy + 2) {
            for x in max(0, cx - 2)...min(w - 1, cx + 2) {
                let d = dati[y * w + x]
                if d.isFinite, d >= 0.2, d <= 5 { buoni.append(d) }
            }
        }
        guard buoni.count >= 5 else { return nil }
        buoni.sort()
        return Double(buoni[buoni.count / 2])
    }
}

/// Gli angoli olografici del visore (come il mirino delle altre sezioni): quattro L ciano sui bordi della pagina.
struct AngoliOlo: View {
    let tinta: Color
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height, l: CGFloat = 18
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: 0, y: h - l)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: l, y: h))
                p.move(to: CGPoint(x: w - l, y: h)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w, y: h - l))
            }
            .stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: tinta.opacity(0.7), radius: 4)
        }
    }
}
#endif
