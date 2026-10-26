#if os(iOS)
import SwiftUI
import UIKit
import AVFoundation
import CoreVideo

// MARK: - MARK X · le pagine del mockup nell'app (STUDIO e SOCIAL) e i collegamenti verso di loro
// Studio e Social sono la pagina del mockup approvato (Studio3D/markx.html) dentro VistaStudio. Ci si arriva dall'icona in alto,
// a voce («Jarvis, apri Instagram», «Jarvis, crea una piastra…») o dagli Occhi (STUDIO, PUBBLICA SU SOCIAL), con quello che serve.

/// Cosa apre la pagina e con che cosa ci arriva.
struct AperturaPagina: Identifiable {
    let id = UUID()
    var sezione: String                 // "Studio" o "Social"
    var voce: String? = nil             // Studio: la frase detta («crea una piastra 80 per 40»), la esegue il banco
    var scheda: String? = nil           // Social: "POSTA", "REPORT", "CALENDARIO" oppure "STUDIO" (l'ultimo pezzo, pronto per un Reel)
    var foto: UIImage? = nil            // dagli Occhi: la foto per il banco o per Instagram
    var nomeFoto = "inquadratura"
    var lidar: String? = nil            // da LiDAR: la scansione vera già pronta per il banco (LidarStudio.swift, JSON)
}

enum PaginaMarkX {
    /// Da qualunque punto dell'app: la schermata principale apre la pagina (se ce n'è una aperta, prima la chiude).
    static func apri(_ a: AperturaPagina) {
        NotificationCenter.default.post(name: .jarvisApriPagina, object: nil, userInfo: ["a": a])
    }
    /// C'è un pezzo con la miniatura nell'archivio dello Studio? (per la frase di JARVIS, come il mockup)
    static var pezzoStudio: Bool {
        (RegiaStudio.leggiArchivio()["jarvisStudioArchivio1"] ?? "").contains("\"mini\"")
    }
    /// «Jarvis, fai il plastico della stanza / dell'evento»: l'ultima sala scansionata e salvata in LiDAR (Interno), vera.
    /// `k`: "stanza", "setup" o "esterno". Torna il JSON per il banco e la frase di JARVIS (o solo la frase, se non c'è niente).
    static func plasticoDaArchivio(_ k: String) -> (json: String?, frase: String) {
        if k == "esterno" { return (nil, "Il terreno non lo tengo in 3D, Sir: lo scansioni con LiDAR, Esterno, e tocchi STUDIO.") }
        guard let s = ArchivioLidar.condiviso.scansioni.first else {
            return (nil, "Non ho ancora una sala scansionata, Sir: la scansioni con LiDAR, Interno, e la salvi.")
        }
        let st = StanzaScena(s)
        let m: ModelloScena = k == "setup" ? .evento(st, Allestimento.calcola(st)) : .stanza(st)
        guard case .success(let json) = LidarAlloStudio.dati(m) else { return (nil, "La sala «\(s.nome)» non basta per un plastico, Sir: la riscansioni.") }
        return (json, LidarAlloStudio.frase(k == "setup" ? .evento : .stanza))
    }
    static func tipoPlastico(_ frase: String) -> String {
        let t = frase.lowercased()
        if ["giardin", "terren", "estern"].contains(where: t.contains) { return "esterno" }
        if ["evento", "allestiment", "palco", "setup"].contains(where: t.contains) { return "setup" }
        return "stanza"
    }

    /// La frase di JARVIS quando si apre a voce (le stesse del mockup).
    static func annuncio(_ a: AperturaPagina) -> String {
        if a.sezione == "Studio" { return "Lo studio, Sir." }
        switch a.scheda {
        case "STUDIO": return pezzoStudio ? "L'ultimo pezzo dello Studio, pronto per Instagram, Sir." : "Lo Studio è vuoto, Sir: prima crei un pezzo."
        case "POSTA": return "I messaggi di Instagram, Sir."
        case "REPORT": return "La settimana su Instagram, Sir."
        case "CALENDARIO": return "Il calendario dei post, Sir."
        default: return "Instagram, Sir."
        }
    }
}

extension Notification.Name {
    static let jarvisApriPagina = Notification.Name("jarvisApriPagina")
}

/// L'icona SOCIAL in alto: il glifo ufficiale di Instagram (scaricato da Meta), in ciano come le altre (regole di Meta: un colore pieno va bene).
struct IconaSocial: View {
    var body: some View {
        Image("GlifoInstagram")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: 15, height: 15)
            .padding(1.5)
    }
}

/// Il tasto STUDIO degli Occhi (accanto a CERCA): stesso stile dei tasti degli Occhi, con il cubo dello Studio.
struct TastoOcchiStudio: View {
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            VStack(spacing: 4) {
                IconaStudio()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.ciano.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.ciano.opacity(0.55), lineWidth: 1))
                Text("STUDIO").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
                    .foregroundStyle(Color.ciano.opacity(0.7))
            }
            .frame(width: 50)
        }
        .buttonStyle(StileStark())
        .accessibilityLabel("Manda allo Studio")
    }
}

/// Il tasto STUDIO nei risultati di LiDAR (come «.comando.con-ico» del mockup): il cubo dello Studio e la scritta.
struct TastoLidarStudio: View {
    let azione: () -> Void
    var body: some View {
        Button { Suoni.tocco(); azione() } label: {
            HStack(spacing: 6) {
                IconaStudio().frame(width: 15, height: 15)
                Text("STUDIO").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11).padding(.horizontal, 8)
            .foregroundStyle(Color.ciano)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
        .accessibilityLabel("Manda allo Studio")
    }
}

/// I due tasti sotto la ricerca degli Occhi (come il mockup): MANDA ALLO STUDIO, PUBBLICA SU SOCIAL.
struct TastiMandaOcchi: View {
    let studio: () -> Void
    let social: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            tasto("MANDA ALLO STUDIO", studio)
            tasto("PUBBLICA SU SOCIAL", social)
        }
        .padding(.top, 10)
    }
    private func tasto(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); a() } label: {
            Text(t).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Color.ciano)
                .frame(maxWidth: .infinity, minHeight: 40)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(StileStark())
    }
}

// MARK: - Il Reel da una foto (il pezzo dello Studio, una foto): 6 secondi in H.264, 1080×1920, con un lento avvicinamento.
// Lo fa l'iPhone (AVAssetWriter), così Instagram riceve un MP4 vero, non un video registrato dal browser.

nonisolated enum ReelDaFoto {
    enum Guasto: Error { case immagine, scrittura }

    @concurrent static func crea(_ jpg: Data, secondi: Double = 6) async throws -> URL {
        guard let img = UIImage(data: jpg)?.cgImage else { throw Guasto.immagine }
        let W = 1080, H = 1920, fps: Int32 = 30
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reel-\(UUID().uuidString).mp4")
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let ingresso = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel] as [String: Any],
        ])
        ingresso.expectsMediaDataInRealTime = false
        let adattatore = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: ingresso, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
        ])
        guard w.canAdd(ingresso) else { throw Guasto.scrittura }
        w.add(ingresso)
        guard w.startWriting() else { throw w.error ?? Guasto.scrittura }
        w.startSession(atSourceTime: .zero)
        let iw = Double(img.width), ih = Double(img.height), n = Int(secondi * Double(fps))
        let spazio = CGColorSpaceCreateDeviceRGB()
        for i in 0..<n {
            while !ingresso.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(4)) }
            guard let pool = adattatore.pixelBufferPool else { throw w.error ?? Guasto.scrittura }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let b = pb else { throw Guasto.scrittura }
            CVPixelBufferLockBaseAddress(b, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: W, height: H, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(b), space: spazio,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.setFillColor(CGColor(red: 0.008, green: 0.04, blue: 0.055, alpha: 1))
                ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
                ctx.interpolationQuality = .high
                let z = 1 + 0.06 * Double(i) / Double(max(1, n - 1))           // il lento avvicinamento dell'anteprima del mockup
                let k = max(Double(W) / iw, Double(H) / ih) * z
                ctx.draw(img, in: CGRect(x: (Double(W) - iw * k) / 2, y: (Double(H) - ih * k) / 2, width: iw * k, height: ih * k))
            }
            CVPixelBufferUnlockBaseAddress(b, [])
            guard adattatore.append(b, withPresentationTime: CMTime(value: Int64(i), timescale: fps)) else { throw w.error ?? Guasto.scrittura }
        }
        ingresso.markAsFinished()
        await w.finishWriting()
        guard w.status == .completed else { throw w.error ?? Guasto.scrittura }
        return url
    }
}
#endif
