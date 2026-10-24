#if os(iOS)
import SwiftUI
import SceneKit
import UIKit
import simd

// MARK: - LiDAR · il 3D (la «scena3d» del mockup approvato)
// Anteprima nel menu dei modi, risultato OLOGRAMMA (colore pieno) o TEXTURE (foto) che si «materializza» dal basso.
// Dalla build 26 lo disegna three.js (lo stesso motore del mockup) in una pagina web dentro l'app: Lidar3DWeb.swift e
// Lidar3D/lidar3d.html. Qui restano i modelli da mostrare, la vista SwiftUI e la geometria piana.

/// Lo stile del modello finito. `pieno` è il tasto OLOGRAMMA (colore pieno), `foto` il tasto TEXTURE.
nonisolated enum StileLidar: String, Codable, Sendable { case pieno, foto }

/// Anteprima (menu dei modi: nuvola di punti, niente etichette) o risultato (etichette e quote).
nonisolated enum FaseScenaLidar: Sendable { case anteprima, risultato }

// MARK: - I modelli da mostrare

/// Una stanza per il 3D: pavimento, pareti a segmenti, porte, finestre, altezza (metri; x e z della pianta).
nonisolated struct StanzaScena: Sendable {
    var pavimento: [SIMD2<Double>]
    var pareti: [TrattoPianta]
    var porte: [TrattoPianta]
    var finestre: [TrattoPianta]
    var altezza: Double

    init(pavimento: [SIMD2<Double>], pareti: [TrattoPianta], porte: [TrattoPianta], finestre: [TrattoPianta], altezza: Double) {
        self.pavimento = pavimento; self.pareti = pareti; self.porte = porte; self.finestre = finestre; self.altezza = altezza
    }

    /// Da una scansione salvata: il poligono del pavimento se c'è, se no l'inviluppo dei capi delle pareti.
    init(_ s: ScansioneLidar) {
        var p = (s.pavimento ?? []).compactMap { $0.count >= 2 ? SIMD2($0[0], $0[1]) : nil }
        if p.count < 3 { p = GeometriaPiana.inviluppo(s.pareti.flatMap { [SIMD2($0.ax, $0.az), SIMD2($0.bx, $0.bz)] }) }
        self.init(pavimento: p, pareti: s.pareti, porte: s.porte, finestre: s.finestre, altezza: s.altezza > 0 ? s.altezza : 2.7)
    }

    /// Dal poligono del mockup: ogni lato è una parete; porte e finestre come (parete, da, lunghezza).
    init(poligono: [SIMD2<Double>], altezza: Double, porte: [(Int, Double, Double)], finestre: [(Int, Double, Double)]) {
        let n = poligono.count
        func tratto(_ i: Int, _ da: Double, _ l: Double) -> TrattoPianta {
            let a = poligono[i], b = poligono[(i + 1) % n], u = simd_normalize(b - a)
            let p = a + u * da, q = a + u * (da + l)
            return TrattoPianta(ax: p.x, az: p.y, bx: q.x, bz: q.y)
        }
        self.init(pavimento: poligono,
                  pareti: (0..<n).map { i in TrattoPianta(ax: poligono[i].x, az: poligono[i].y, bx: poligono[(i + 1) % n].x, bz: poligono[(i + 1) % n].y) },
                  porte: porte.map { tratto($0.0, $0.1, $0.2) }, finestre: finestre.map { tratto($0.0, $0.1, $0.2) }, altezza: altezza)
    }

    var area: Double { GeometriaPiana.area(pavimento) }
}

/// Il terreno di Esterno: una griglia di quote (metri) con i colori veri presi dalla fotocamera, dentro il bordo percorso.
nonisolated struct TerrenoScena: Sendable {
    var bordo: [SIMD2<Double>]                 // il perimetro camminato (x, z)
    var origine: SIMD2<Double>                 // l'angolo della griglia
    var passo: Double                          // lato della cella
    var nx: Int, nz: Int
    var quote: [Float]                         // nx × nz, metri (già riempite dove mancavano)
    var colori: [SIMD3<Float>]?                // nx × nz, sRGB 0…1 (nil: solo ologramma e colore pieno)
    var area: Double
    var dislivello: Double                     // metri
}

/// L'oggetto di Oggetto: la maglia del LiDAR, già girata sugli assi della scatola (x = largo, z = profondo), base a y = 0.
nonisolated struct OggettoScena: Sendable {
    var vertici: [SIMD3<Float>]
    var colori: [SIMD3<Float>]?                // sRGB 0…1
    var indici: [UInt32]
    var largo: Float, profondo: Float, alto: Float
}

/// Lo scheletro di Postura: le 15 giunture del mockup (metri, piedi a terra, la persona guarda verso +z).
nonisolated struct PosturaScena: Sendable {
    var giunture: [String: SIMD3<Float>]
    var altezza: Float
    var spalle: Float                          // metri
    var bacinoGradi: Float                     // + verso destra della persona
}

nonisolated enum ModelloScena: Sendable {
    case stanza(StanzaScena)
    case evento(StanzaScena, Allestimento)
    case esterno(TerrenoScena)
    case oggetto(OggettoScena)
    case cassaEsempio                          // il flight case del mockup (solo anteprima)
    case statua(URL?, altezza: Float)          // nil: la persona d'esempio (MakeHuman) con la texture dipinta
    case postura(PosturaScena)
    case misura(larghezza: Float, altezza: Float)
}

// MARK: - Maglie per il file USDZ dell'oggetto (Archivio dei modi)

/// Le normali morbide e i colori dei vertici per esportare la maglia di Oggetto in USDZ (ArchivioModi.esporta).
/// Il 3D a schermo non usa più SceneKit (vedi Lidar3DWeb.swift): resta solo questo per scrivere il file.
enum ScenaLidar {
    private static func lineare(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    static func fonteColori(_ c: [SIMD3<Float>]) -> SCNGeometrySource {
        // sRGB → lineare: i colori dei vertici SceneKit li prende lineari
        var dati = [Float](); dati.reserveCapacity(c.count * 3)
        for x in c { dati += [Float(lineare(Double(x.x))), Float(lineare(Double(x.y))), Float(lineare(Double(x.z)))] }
        let d = dati.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: d, semantic: .color, vectorCount: c.count, usesFloatComponents: true,
                                 componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                 dataStride: MemoryLayout<Float>.size * 3)
    }

    static func normali(_ v: [SIMD3<Float>], _ idx: [UInt32]) -> [SIMD3<Float>] {
        var n = [SIMD3<Float>](repeating: .zero, count: v.count)
        for k in stride(from: 0, to: idx.count - 2, by: 3) {
            let a = Int(idx[k]), b = Int(idx[k + 1]), c = Int(idx[k + 2])
            guard a < v.count, b < v.count, c < v.count else { continue }
            let f = simd_cross(v[b] - v[a], v[c] - v[a])
            n[a] += f; n[b] += f; n[c] += f
        }
        return n.map { let l = simd_length($0); return l > 0 ? $0 / l : SIMD3(0, 1, 0) }
    }
}

// MARK: - La vista (SwiftUI)

/// Il 3D nella tavola: la pagina three.js trasparente (Superficie3DLidar, in Lidar3DWeb.swift); il dito in orizzontale gira,
/// due dita ingrandiscono, doppio tocco riparte. «360°» e «RILIEVO ×3» restano scritte SwiftUI sopra la pagina.
struct Vista3DLidar: View {
    let modello: ModelloScena
    let fase: FaseScenaLidar
    let stile: StileLidar?

    var body: some View {
        Superficie3DLidar(modello: modello, fase: fase, stile: stile)
            .overlay(alignment: .bottomTrailing) {
                Text("360°").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.ciano).opacity(0.75).padding(.trailing, 10).padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if case .esterno = modello {
                    Text("RILIEVO ×3").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Color.ciano).opacity(0.75).padding(.leading, 10).padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Geometria piana (pavimenti, bordi, allestimento)

nonisolated enum GeometriaPiana {
    static func areaConSegno(_ p: [SIMD2<Float>]) -> Float {
        guard p.count >= 3 else { return 0 }
        var a: Float = 0
        for i in 0..<p.count { let j = (i + 1) % p.count; a += p[i].x * p[j].y - p[j].x * p[i].y }
        return a / 2
    }
    static func area(_ p: [SIMD2<Double>]) -> Double {
        guard p.count >= 3 else { return 0 }
        var a = 0.0
        for i in 0..<p.count { let j = (i + 1) % p.count; a += p[i].x * p[j].y - p[j].x * p[i].y }
        return abs(a) / 2
    }
    static func perimetro(_ p: [SIMD2<Double>]) -> Double {
        guard p.count >= 2 else { return 0 }
        return (0..<p.count).reduce(0) { $0 + simd_distance(p[$1], p[($1 + 1) % p.count]) }
    }
    static func baricentro(_ p: [SIMD2<Float>]) -> SIMD2<Float> {
        guard !p.isEmpty else { return .zero }
        let a = areaConSegno(p)
        if abs(a) < 1e-6 { return p.reduce(.zero, +) / Float(p.count) }
        var c = SIMD2<Float>(0, 0)
        for i in 0..<p.count { let j = (i + 1) % p.count; let k = p[i].x * p[j].y - p[j].x * p[i].y; c += (p[i] + p[j]) * k }
        return c / (6 * a)
    }
    static func baricentro(_ p: [SIMD2<Double>]) -> SIMD2<Double> {
        let f = baricentro(p.map { SIMD2<Float>(Float($0.x), Float($0.y)) }); return SIMD2(Double(f.x), Double(f.y))
    }
    /// Un punto sicuramente dentro (il baricentro, o il punto interno più vicino a lui su una griglia).
    static func puntoInterno(_ p: [SIMD2<Float>]) -> SIMD2<Float> {
        let g = baricentro(p)
        if dentro(g, p) || p.count < 3 { return g }
        let xs = p.map(\.x), ys = p.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return g }
        var meglio = g, d = Float.infinity
        for i in 0...20 { for j in 0...20 {
            let q = SIMD2(x0 + (x1 - x0) * Float(i) / 20, y0 + (y1 - y0) * Float(j) / 20)
            if dentro(q, p), simd_distance(q, g) < d { d = simd_distance(q, g); meglio = q }
        } }
        return meglio
    }
    static func dentro(_ q: SIMD2<Float>, _ p: [SIMD2<Float>]) -> Bool {
        var c = false, j = p.count - 1
        for i in 0..<p.count {
            let a = p[i], b = p[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }
    static func dentro(_ q: SIMD2<Double>, _ p: [SIMD2<Double>]) -> Bool {
        dentro(SIMD2<Float>(Float(q.x), Float(q.y)), p.map { SIMD2<Float>(Float($0.x), Float($0.y)) })
    }
    /// Il triangolatore «a orecchie» per i poligoni semplici (anche concavi); il poligono va dato in senso antiorario.
    static func triangola(_ p: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        var idx = Array(p.indices), out: [(Int, Int, Int)] = []
        func croce(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
        func nelTriangolo(_ q: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            croce(a, b, q) >= 0 && croce(b, c, q) >= 0 && croce(c, a, q) >= 0
        }
        var giri = 0
        while idx.count > 3 && giri < 10_000 {
            giri += 1
            var tagliato = false
            for k in 0..<idx.count {
                let i0 = idx[(k + idx.count - 1) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = p[i0], b = p[i1], c = p[i2]
                guard croce(a, b, c) > 1e-7 else { continue }                       // angolo convesso
                let dentroQualcuno = idx.contains { j in j != i0 && j != i1 && j != i2 && nelTriangolo(p[j], a, b, c) }
                if dentroQualcuno { continue }
                out.append((i0, i1, i2)); idx.remove(at: k); tagliato = true; break
            }
            if !tagliato {                                                           // poligono sporco: si chiude a ventaglio
                for k in 1..<(idx.count - 1) { out.append((idx[0], idx[k], idx[k + 1])) }
                return out
            }
        }
        if idx.count == 3 { out.append((idx[0], idx[1], idx[2])) }
        return out
    }
    /// L'inviluppo convesso (catena monotona).
    static func inviluppo(_ punti: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let p = punti.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard p.count >= 3 else { return p }
        func croce(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var basso: [SIMD2<Double>] = [], alto: [SIMD2<Double>] = []
        for q in p { while basso.count >= 2 && croce(basso[basso.count - 2], basso[basso.count - 1], q) <= 0 { basso.removeLast() }; basso.append(q) }
        for q in p.reversed() { while alto.count >= 2 && croce(alto[alto.count - 2], alto[alto.count - 1], q) <= 0 { alto.removeLast() }; alto.append(q) }
        return Array(basso.dropLast() + alto.dropLast())
    }
    /// Semplifica una linea (Douglas–Peucker).
    static func semplifica(_ p: [SIMD2<Double>], _ tolleranza: Double) -> [SIMD2<Double>] {
        guard p.count > 2 else { return p }
        func dist(_ q: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            let ab = b - a, l2 = simd_length_squared(ab)
            if l2 < 1e-12 { return simd_distance(q, a) }
            let t = max(0, min(1, simd_dot(q - a, ab) / l2))
            return simd_distance(q, a + ab * t)
        }
        var dMax = 0.0, iMax = 0
        for i in 1..<(p.count - 1) { let d = dist(p[i], p[0], p[p.count - 1]); if d > dMax { dMax = d; iMax = i } }
        if dMax <= tolleranza { return [p[0], p[p.count - 1]] }
        let a = semplifica(Array(p[0...iMax]), tolleranza), b = semplifica(Array(p[iMax...]), tolleranza)
        return Array(a.dropLast()) + b
    }
}
#endif
