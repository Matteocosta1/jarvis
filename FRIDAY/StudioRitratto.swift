#if os(iOS)
import Foundation
import UIKit
import AVFoundation
import CoreImage
import CoreVideo
import CoreGraphics
import ImageIO
import PhotosUI
import QuickLook
import ARKit
import UniformTypeIdentifiers

// MARK: - STUDIO · Fase 4 (build 23): RILIEVO con la profondità vera delle foto Ritratto, e AR nella stanza a grandezza vera.
// Tutto sul telefono e gratis: la profondità e il ritaglio della persona li salva l'iPhone dentro la foto Ritratto (HEIC);
// l'AR è AR Quick Look di Apple.

/// La foto Ritratto letta: il JPEG raddrizzato per la pagina e, se c'è, la profondità (0 = lontano, 1 = vicino) e il ritaglio della persona.
nonisolated struct FotoRitratto: Sendable {
    let jpg: Data
    let larghezza: Int
    let altezza: Int
    let profondita: Data?          // Float32, larghezza × altezza
    let ritaglio: Data?            // UInt8 (1 = persona), larghezza × altezza
}

nonisolated enum ProfonditaRitratto {
    /// I byte originali della foto (HEIC con i dati ausiliari) → foto dritta, profondità normalizzata, ritaglio. nil se non è un'immagine.
    @concurrent static func leggi(_ dati: Data) async -> FotoRitratto? {
        guard let sorgente = CGImageSourceCreateWithData(dati as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(sorgente, 0, nil) else { return nil }
        let proprieta = CGImageSourceCopyPropertiesAtIndex(sorgente, 0, nil) as? [CFString: Any]
        let verso = CGImagePropertyOrientation(rawValue: (proprieta?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        let contesto = CIContext()

        // la foto: dritta, lato lungo 1400 px, JPEG
        var foto = CIImage(cgImage: cg).oriented(verso)
        let latoFoto = max(foto.extent.width, foto.extent.height)
        if latoFoto > 1400 { foto = foto.transformed(by: CGAffineTransform(scaleX: 1400 / latoFoto, y: 1400 / latoFoto)) }
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB),
              let jpg = contesto.jpegRepresentation(of: foto, colorSpace: spazio,
                                                   options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]) else { return nil }

        // la profondità: le foto Ritratto salvano la disparità (più alta = più vicino); se c'è solo la profondità, si converte
        var datiProfondita: AVDepthData?
        for tipo in [kCGImageAuxiliaryDataTypeDisparity, kCGImageAuxiliaryDataTypeDepth] {
            if let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(sorgente, 0, tipo) as? [AnyHashable: Any],
               let d = try? AVDepthData(fromDictionaryRepresentation: info) { datiProfondita = d; break }
        }
        guard let grezza = datiProfondita else { return FotoRitratto(jpg: jpg, larghezza: 0, altezza: 0, profondita: nil, ritaglio: nil) }
        let disparita = grezza.depthDataType == kCVPixelFormatType_DisparityFloat32 ? grezza : grezza.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        var mappa = CIImage(cvPixelBuffer: disparita.depthDataMap).oriented(verso)
        let latoMappa = max(mappa.extent.width, mappa.extent.height)
        if latoMappa > 256 { mappa = mappa.transformed(by: CGAffineTransform(scaleX: 256 / latoMappa, y: 256 / latoMappa)) }
        let w = max(1, Int(mappa.extent.width.rounded(.down))), h = max(1, Int(mappa.extent.height.rounded(.down)))
        let riquadro = CGRect(x: mappa.extent.minX, y: mappa.extent.minY, width: CGFloat(w), height: CGFloat(h))
        var valori = [Float](repeating: 0, count: w * h)
        valori.withUnsafeMutableBytes { b in
            if let base = b.baseAddress { contesto.render(mappa, toBitmap: base, rowBytes: w * 4, bounds: riquadro, format: .Rf, colorSpace: nil) }
        }
        // normalizzata fra il 2° e il 98° percentile (i punti sballati ai bordi non schiacciano tutto il resto); i vuoti a 0
        let buoni = valori.filter { $0.isFinite && $0 > 0 }.sorted()
        guard buoni.count > 16 else { return FotoRitratto(jpg: jpg, larghezza: 0, altezza: 0, profondita: nil, ritaglio: nil) }
        let basso = buoni[buoni.count * 2 / 100], alto = buoni[min(buoni.count - 1, buoni.count * 98 / 100)], gamma = max(alto - basso, 1e-6)
        let normali = valori.map { v -> Float in v.isFinite && v > 0 ? min(1, max(0, (v - basso) / gamma)) : 0 }
        let profondita = normali.withUnsafeBufferPointer { Data(buffer: $0) }

        // il ritaglio della persona (Portrait Effects Matte), sulla stessa griglia della profondità
        var ritaglio: Data?
        if let info = CGImageSourceCopyAuxiliaryDataInfoAtIndex(sorgente, 0, kCGImageAuxiliaryDataTypePortraitEffectsMatte) as? [AnyHashable: Any],
           let matte = try? AVPortraitEffectsMatte(fromDictionaryRepresentation: info) {
            let m = CIImage(cvPixelBuffer: matte.mattingImage).oriented(verso)
            let mm = m.transformed(by: CGAffineTransform(scaleX: CGFloat(w) / m.extent.width, y: CGFloat(h) / m.extent.height))
            var byte = [UInt8](repeating: 0, count: w * h)
            byte.withUnsafeMutableBytes { b in
                if let base = b.baseAddress {
                    contesto.render(mm, toBitmap: base, rowBytes: w, bounds: CGRect(x: mm.extent.minX, y: mm.extent.minY, width: CGFloat(w), height: CGFloat(h)), format: .R8, colorSpace: nil)
                }
            }
            ritaglio = Data(byte.map { $0 > 127 ? UInt8(1) : UInt8(0) })
        }
        return FotoRitratto(jpg: jpg, larghezza: w, altezza: h, profondita: profondita, ritaglio: ritaglio)
    }
}

/// La galleria per RITRATTO: restituisce i byte originali della foto (non una copia ricompressa, che perderebbe la profondità).
nonisolated final class SceltaRitratto: NSObject, PHPickerViewControllerDelegate, @unchecked Sendable {
    private let fatto: @MainActor @Sendable (Data?) -> Void
    init(_ fatto: @escaping @MainActor @Sendable (Data?) -> Void) { self.fatto = fatto }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        MainActor.assumeIsolated { picker.dismiss(animated: true) }
        let fatto = self.fatto
        guard let fornitore = results.first?.itemProvider, fornitore.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            Task { @MainActor in fatto(nil) }
            return
        }
        fornitore.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { dati, _ in
            Task { @MainActor in fatto(dati) }
        }
    }
}

/// AR Quick Look: un solo modello, a grandezza vera (senza ridimensionarlo con le dita).
nonisolated final class FonteAR: NSObject, QLPreviewControllerDataSource, @unchecked Sendable {
    private let modello: ARQuickLookPreviewItem
    init(_ modello: ARQuickLookPreviewItem) { self.modello = modello }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { modello }
}
#endif
