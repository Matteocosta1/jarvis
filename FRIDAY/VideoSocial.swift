#if os(iOS)
import Foundation
import AVFoundation
import UIKit

// MARK: - 26 ott sera: il video degli Occhi per Social
// Gli Occhi registrano a 1080p; per Instagram il video si ricomprime in H.264 (lato lungo 1280, 3,2 Mbit/s) con l'audio in AAC:
// un minuto pesa circa 25 MB, sotto il limite di 30 MB del caricamento. Si scrive leggendo e scrivendo a turno video e audio
// (lo scrittore vuole i due flussi intrecciati), senza code né thread in più.

nonisolated enum VideoSocial {
    enum Guasto: Error { case video, scrittura }

    @concurrent static func comprimi(_ sorgente: URL) async throws -> URL {
        let asset = AVURLAsset(url: sorgente)
        guard let tv = try await asset.loadTracks(withMediaType: .video).first else { throw Guasto.video }
        let (misura, giro) = try await tv.load(.naturalSize, .preferredTransform)
        let ta = try await asset.loadTracks(withMediaType: .audio).first

        let k = min(1, 1280 / max(misura.width, misura.height))
        let W = Int((misura.width * k / 2).rounded()) * 2, H = Int((misura.height * k / 2).rounded()) * 2
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("social-occhi-\(UUID().uuidString).mp4")

        let lettore = try AVAssetReader(asset: asset)
        let fuoriV = AVAssetReaderTrackOutput(track: tv, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        fuoriV.alwaysCopiesSampleData = false
        guard lettore.canAdd(fuoriV) else { throw Guasto.video }
        lettore.add(fuoriV)
        var fuoriA: AVAssetReaderTrackOutput?
        if let ta {
            let o = AVAssetReaderTrackOutput(track: ta, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
                                                                        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                                                                        AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
            o.alwaysCopiesSampleData = false
            if lettore.canAdd(o) { lettore.add(o); fuoriA = o }
        }

        let scrittore = try AVAssetWriter(outputURL: url, fileType: .mp4)
        scrittore.shouldOptimizeForNetworkUse = true
        let dentroV = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_200_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel] as [String: Any],
        ])
        dentroV.expectsMediaDataInRealTime = false
        dentroV.transform = giro                                             // verticale come è stato girato
        guard scrittore.canAdd(dentroV) else { throw Guasto.scrittura }
        scrittore.add(dentroV)
        var dentroA: AVAssetWriterInput?
        if fuoriA != nil {
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                                                         AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
            i.expectsMediaDataInRealTime = false
            if scrittore.canAdd(i) { scrittore.add(i); dentroA = i }
        }
        if dentroA == nil { fuoriA = nil }

        guard lettore.startReading() else { throw lettore.error ?? Guasto.video }
        guard scrittore.startWriting() else { throw scrittore.error ?? Guasto.scrittura }
        scrittore.startSession(atSourceTime: .zero)

        var fineV = false, fineA = fuoriA == nil
        while !fineV || !fineA {
            var mosso = false
            if !fineV && dentroV.isReadyForMoreMediaData {
                if let c = fuoriV.copyNextSampleBuffer() {
                    guard dentroV.append(c) else { throw scrittore.error ?? Guasto.scrittura }
                } else { dentroV.markAsFinished(); fineV = true }
                mosso = true
            }
            if !fineA, let fa = fuoriA, let da = dentroA, da.isReadyForMoreMediaData {
                if let c = fa.copyNextSampleBuffer() {
                    guard da.append(c) else { throw scrittore.error ?? Guasto.scrittura }
                } else { da.markAsFinished(); fineA = true }
                mosso = true
            }
            if !mosso { try await Task.sleep(for: .milliseconds(3)) }
            if lettore.status == .failed { throw lettore.error ?? Guasto.video }
        }
        await scrittore.finishWriting()
        guard scrittore.status == .completed else { throw scrittore.error ?? Guasto.scrittura }
        return url
    }

    /// La copertina per Social: il primo fotogramma, dritto.
    @concurrent static func copertina(_ u: URL) async -> UIImage? {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: u))
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: 1600, height: 1600)
        guard let cg = try? await g.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cg)
    }
}
#endif
