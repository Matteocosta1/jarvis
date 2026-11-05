#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import Vision
import CoreVideo
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - BEA IN OLOGRAMMA (11.0 (4), 5 nov notte) — come il mockup v261
// Il signore: «scegli la foto nell'app, la persona viene ritagliata in ologramma ciano e la foto resta sul telefono» («FARE
// COSÌ», la foto dal rullino). La foto si sceglie col selettore di Apple (nessun permesso sulla libreria: l'app vede solo quella
// scelta); la persona la ritaglia Vision sul telefono, la luce ciano si fa una volta sola e si salva solo il risultato, in
// Application Support, fuori dal backup di iCloud. La foto originale non si salva e non va da nessuna parte.

/// La foto di Bea in ologramma: preparata una volta, salvata solo sul telefono.
nonisolated enum FotoBea {
    private static var cartella: URL { URL.applicationSupportDirectory.appending(path: "JARVIS", directoryHint: .isDirectory) }
    private static var indirizzo: URL { cartella.appending(path: "bea-ologramma.png") }

    /// L'ologramma già preparato, se c'è.
    static func salvata() -> Data? { try? Data(contentsOf: indirizzo) }

    /// Ritaglia la persona (Vision), la fa diventare luce ciano (i contorni più chiari, le righe di scansione, il fondo che sfuma
    /// verso il basso) e salva solo il risultato. nil = la foto non si legge.
    @concurrent static func prepara(_ dati: Data) async -> Data? {
        let opzioni: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1024]
        guard let sorgente = CGImageSourceCreateWithData(dati as CFData, nil),
              let foto = CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary) else { return nil }
        let w = foto.width, h = foto.height
        guard w > 8, h > 8 else { return nil }
        // la persona: Vision, sul telefono. Se non trova nessuno, l'ovale al centro (come il mockup)
        let maschera = persona(foto)
        var x0 = 0, y0 = 0, x1 = w, y1 = h
        if let m = maschera {
            var minX = w, minY = h, maxX = -1, maxY = -1
            for y in 0..<h {
                for x in 0..<w where m[y * w + x] > 0.5 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            if maxX > minX && maxY > minY {
                let mx = (maxX - minX) * 6 / 100, my = (maxY - minY) * 4 / 100
                x0 = max(0, minX - mx); x1 = min(w, maxX + mx + 1); y0 = max(0, minY - my); y1 = min(h, maxY + 1)
            }
        }
        let cw = x1 - x0, ch = y1 - y0
        guard cw > 8, ch > 8, let ritaglio = foto.cropping(to: CGRect(x: x0, y: y0, width: cw, height: ch)) else { return nil }
        let alto = 420, largo = max(120, min(600, cw * alto / ch))
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let tela = CGContext(data: nil, width: largo, height: alto, bitsPerComponent: 8, bytesPerRow: largo * 4, space: spazio,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        tela.interpolationQuality = .high
        tela.draw(ritaglio, in: CGRect(x: 0, y: 0, width: largo, height: alto))
        guard let base = tela.data else { return nil }
        let px = base.bindMemory(to: UInt8.self, capacity: largo * alto * 4)
        let n = largo * alto
        var luce = [Float](repeating: 0, count: n), dentro = [Float](repeating: 0, count: n)
        for y in 0..<alto {
            for x in 0..<largo {
                let i = y * largo + x, j = i * 4
                luce[i] = (0.2126 * Float(px[j]) + 0.7152 * Float(px[j + 1]) + 0.0722 * Float(px[j + 2])) / 255
                if let m = maschera {
                    let sx = min(w - 1, x0 + Int((Double(x) + 0.5) * Double(cw) / Double(largo)))
                    let sy = min(h - 1, y0 + Int((Double(y) + 0.5) * Double(ch) / Double(alto)))
                    dentro[i] = m[sy * w + sx]
                } else {
                    let ox = (Double(x) / Double(largo) - 0.5) / 0.36, oy = (Double(y) / Double(alto) - 0.5) / 0.46
                    dentro[i] = Float(max(0, min(1, (1.1 - (ox * ox + oy * oy).squareRoot()) / 0.25)))
                }
            }
        }
        // la luce: ciano, i contorni (Sobel) più chiari, una riga su tre più scura; il fondo sfuma verso il basso e ai lati
        var esce = [UInt8](repeating: 0, count: n * 4)
        for y in 0..<alto {
            for x in 0..<largo {
                let i = y * largo + x, j = i * 4
                let ox = (Double(x) / Double(largo) - 0.5) / 0.5, oy = (Double(y) / Double(alto) - 0.55) / 0.55
                let ov = max(0, min(1, (1.08 - (ox * ox + oy * oy).squareRoot()) / 0.25))
                let gx = x > 0 && x < largo - 1 ? luce[i + 1] - luce[i - 1] : 0
                let gy = y > 0 && y < alto - 1 ? luce[i + largo] - luce[i - largo] : 0
                let e = Double(min(1, (gx * gx + gy * gy).squareRoot() * 3.2))
                let l = max(0, min(1, (Double(luce[i]) - 0.06) * 1.35)), kk = 0.22 + 0.78 * l, riga = y % 3 == 0 ? 0.5 : 1
                let a = min(1, Double(dentro[i]) * ov * (0.35 + 0.65 * l + 0.5 * e))
                let r = min(255, (143 * kk + 112 * e * 0.8) * riga), g = min(255, (240 * kk + 15 * e * 0.8) * riga)
                let b = 255 * min(1, kk + 0.6 * e) * riga
                esce[j] = UInt8(r * a); esce[j + 1] = UInt8(g * a); esce[j + 2] = UInt8(b * a); esce[j + 3] = UInt8(255 * a)
            }
        }
        let immagine: CGImage? = esce.withUnsafeMutableBytes { b in
            CGContext(data: b.baseAddress, width: largo, height: alto, bitsPerComponent: 8, bytesPerRow: largo * 4, space: spazio,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let immagine else { return nil }
        let png = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(png as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, immagine, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        let risultato = png as Data
        // solo sul telefono: niente backup su iCloud
        do {
            try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
            try risultato.write(to: indirizzo, options: .atomic)
            var dove = indirizzo
            var valori = URLResourceValues()
            valori.isExcludedFromBackup = true
            try dove.setResourceValues(valori)
        } catch { return nil }
        return risultato
    }

    /// La maschera della persona (0…1 per pixel, righe dall'alto), grande quanto la foto. nil = Vision non trova nessuno.
    private static func persona(_ foto: CGImage) -> [Float]? {
        let richiesta = VNGenerateForegroundInstanceMaskRequest()
        let gestore = VNImageRequestHandler(cgImage: foto)
        do {
            try gestore.perform([richiesta])
            guard let r = richiesta.results?.first, !r.allInstances.isEmpty else { return nil }
            let buf = try r.generateScaledMaskForImage(forInstances: r.allInstances, from: gestore)
            CVPixelBufferLockBaseAddress(buf, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
            let bw = CVPixelBufferGetWidth(buf), bh = CVPixelBufferGetHeight(buf), riga = CVPixelBufferGetBytesPerRow(buf)
            let w = foto.width, h = foto.height
            guard bw > 0, bh > 0 else { return nil }
            var m = [Float](repeating: 0, count: w * h)
            for y in 0..<h {
                let sy = min(bh - 1, y * bh / h)
                let fila = (base + sy * riga).assumingMemoryBound(to: Float32.self)
                for x in 0..<w { m[y * w + x] = max(0, min(1, fila[min(bw - 1, x * bw / w)])) }
            }
            return m
        } catch {
            return nil
        }
    }
}

/// La foto scelta in ologramma sopra il proiettore: tutta ciano, coi contorni che brillano, il respiro della luce e la banda che
/// la ripercorre dal basso ogni 3,2 s; ogni tanto un guizzo (due strisce che scivolano). Senza foto: un busto di luce e
/// SCELGA UNA FOTO.
struct OlogrammaBea: View {
    let foto: UIImage?

    var body: some View {
        TelaOlo { gc, size, t, _ in
            let immagine = foto.map { gc.resolve(Image(uiImage: $0)) }
            let rapporto = foto.map { Double($0.size.width / max(1, $0.size.height)) } ?? 1
            DisegnoBea.disegna(&gc, size, t: t, foto: immagine, rapporto: rapporto)
        }
    }
}

enum DisegnoBea {
    /// Il busto di luce (senza foto): mezza larghezza e mezza profondità all'altezza z (0 = petto, 1,22 = cima della testa).
    private static func busto(_ z: Double) -> (Double, Double) {
        if z > 0.63 { let f = max(0, 1 - pow((z - 0.9) / 0.27, 2)).squareRoot(); return (0.2 * f, 0.23 * f) }
        if z > 0.46 { return (0.09, 0.085) }
        if z > 0.28 {
            let f = max(0, 1 - pow((z - 0.28) / 0.19, 2)).squareRoot()
            return (max(0.09, 0.62 * pow(f, 0.7)), max(0.085, 0.26 * f))
        }
        return (0.62, 0.26)
    }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, foto: GraphicsContext.ResolvedImage?, rapporto: Double) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 4, h > 4 else { return }
        gc.blendMode = .plusLighter
        let cx = w / 2, base = h - 16, rx = min(w * 0.24, 90)
        let ry = Olo.pavimento(&gc, cx, base, rx, t, n: 48)
        let cima = 18.0, alto = base - ry * 0.4 - cima
        Olo.cono(&gc, cx, base, rx, cima + 10, rx * 1.15, a: 0.1)
        // la polvere di luce che sale nel cono
        for i in 0..<26 {
            let p = (t * 0.22 + Double(i) / 26).truncatingRemainder(dividingBy: 1), s = sin(Double(i) * 91.7)
            let x = cx + s * rx * 0.55 * (0.4 + 0.6 * p), y = base - p * alto
            gc.fill(Path(CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(Olo.ciano.opacity(0.6 * sin(p * .pi) * 0.8)))
        }
        if let foto {
            let fh = alto, fw = fh * rapporto, x0 = cx - fw / 2, y0 = base - ry * 0.4 - fh
            let rett = CGRect(x: x0, y: y0, width: fw, height: fh)
            var c = gc
            c.opacity = 0.86 + 0.14 * (0.5 + 0.5 * sin(t * 2.1)) * (0.7 + 0.3 * sin(t * 13))    // il respiro della luce
            c.draw(foto, in: rett)
            // la banda che la ripercorre dal basso in alto (ogni 3,2 s)
            let yb = y0 + fh * (1 - t.truncatingRemainder(dividingBy: 3.2) / 3.2), bh = 16.0
            var banda = gc
            banda.clip(to: Path(CGRect(x: x0, y: yb - bh, width: fw, height: bh)))
            banda.opacity = 0.75
            banda.draw(foto, in: rett)
            var riga = Path()
            Olo.linea(&riga, x0 + fw * 0.1, yb, x0 + fw * 0.9, yb)
            gc.stroke(riga, with: .color(Olo.bianco.opacity(0.35)), lineWidth: 1)
            // il guizzo: due strisce che scivolano di lato, una volta ogni 4,3 s per 0,12 s
            if t.truncatingRemainder(dividingBy: 4.3) < 0.12 {
                for (f, dx) in [(0.3, 6.0), (0.62, -5.0)] as [(Double, Double)] {
                    var g = gc
                    g.clip(to: Path(CGRect(x: x0 - 10, y: y0 + fh * f, width: fw + 20, height: 9)))
                    g.opacity = 0.9
                    g.draw(foto, in: CGRect(x: x0 + dx, y: y0, width: fw, height: fh))
                }
            }
        } else {
            // il busto di luce: sezioni orizzontali che girano piano
            let sz = alto * 0.8, ang = 0.45 * sin(t * 0.4), al = 0.12, cy = base - ry * 0.4
            var g = GruppiOlo(5)
            for k in 0...27 {
                let z = Double(k) / 27 * 1.22, (bx, by) = busto(z)
                var o = Olo.proietta(bx, 0, z, ang, al, cx, cy, sz)
                for i in 1...40 {
                    let a = Double(i) / 40 * 2 * .pi, q = Olo.proietta(cos(a) * bx, sin(a) * by, z, ang, al, cx, cy, sz)
                    g.metti((o.z + q.z < 0 ? 2 : 0) + (k % 4 == 0 ? 1 : 0), o, q)
                    o = q
                }
            }
            for m in 0..<8 {                                              // i meridiani: si vede il volume
                let a = Double(m) / 8 * 2 * .pi
                for k in 0..<27 {
                    let z0 = Double(k) / 27 * 1.22, z1 = Double(k + 1) / 27 * 1.22, (a0, b0) = busto(z0), (a1, b1) = busto(z1)
                    let o = Olo.proietta(cos(a) * a0, sin(a) * b0, z0, ang, al, cx, cy, sz)
                    let q = Olo.proietta(cos(a) * a1, sin(a) * b1, z1, ang, al, cx, cy, sz)
                    g.metti(o.z + q.z < 0 ? 1 : 0, o, q)
                }
            }
            g.linee(&gc, colore: { Olo.ciano.opacity(0.12 + 0.17 * Double($0)) }, spessore: { 0.8 + Double($0) * 0.1 })
            Olo.testo(&gc, "SCELGA UNA FOTO", cx, 14, corpo: 8, peso: .bold, Olo.ciano.opacity(0.9))
        }
    }
}
#endif
