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

    // MARK: 11.0 (6) · Bea sul polso (il signore: «fallo»)
    // L'orologio non riceve la foto: riceve l'ologramma già fatto qui, in piccolo (160 pixel sul lato lungo, JPEG su nero da
    // pochi kB: sull'orologio la luce si somma al fondo, il nero non conta, e il messaggio resta leggero). La versione è l'ora in
    // cui l'ologramma è stato preparato: l'orologio lo chiede con la sua, e se è la stessa non viaggia niente.

    /// La risposta per l'orologio: «nessuna» (nessuna foto scelta), la versione (l'orologio ha già questa) o versione e JPEG.
    static func perPolso(seNonE versione: String) -> [String: Any] {
        guard let attributi = try? FileManager.default.attributesOfItem(atPath: indirizzo.path(percentEncoded: false)),
              let quando = attributi[.modificationDate] as? Date else { return ["bea": "ologramma", "nessuna": true] }
        let v = String(Int(quando.timeIntervalSince1970))
        if v == versione { return ["bea": "ologramma", "versione": v] }
        guard let png = salvata(), let jpeg = piccola(png) else { return ["bea": "ologramma", "nessuna": true] }
        return ["bea": "ologramma", "versione": v, "jpeg": jpeg]
    }

    /// L'ologramma rimpicciolito (160 pixel sul lato lungo) e posato sul nero, in JPEG.
    private static func piccola(_ png: Data) -> Data? {
        let opzioni: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160]
        guard let sorgente = CGImageSourceCreateWithData(png as CFData, nil),
              let im = CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary),
              let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let tela = CGContext(data: nil, width: im.width, height: im.height, bitsPerComponent: 8, bytesPerRow: 0, space: spazio,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let tutta = CGRect(x: 0, y: 0, width: im.width, height: im.height)
        tela.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        tela.fill(tutta)
        tela.draw(im, in: tutta)
        guard let su = tela.makeImage() else { return nil }
        let jpeg = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(jpeg as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, su, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return jpeg as Data
    }

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

#endif
