import Foundation
import Photos
import Vision
import CoreLocation
import UIKit

/// Ricerca nella galleria del signore: per data, luogo, album e — con l'AI di Apple sul telefono (Vision) — per contenuto.
/// Tutto resta sull'iPhone: le foto non vanno mai al cervello, solo le date e le etichette trovate.
/// Le funzioni sono `nonisolated`: Photos e Vision lavorano su thread in background.
nonisolated enum FotoLocali {

    nonisolated struct Esito: Sendable {
        var trovate: [String] = []          // localIdentifier, dalla più recente
        var righe: [[String: String]] = []  // per il cervello: data, luogo (se c'è), etichette
        var esaminate = 0
        var nota: String?
    }

    static func autorizza() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// cosa: parole chiave in inglese (tassonomia di Vision). Le altre condizioni sono facoltative.
    @concurrent static func cerca(cosa: [String], da: Date?, a: Date?, luogo: CLLocation?, raggioKm: Double, album: String?, quante: Int, limiteAI: Int = 400) async -> Esito {
        var esito = Esito()
        let opzioni = PHFetchOptions()
        opzioni.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var condizioni = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let da { condizioni.append(NSPredicate(format: "creationDate >= %@", da as NSDate)) }
        if let a { condizioni.append(NSPredicate(format: "creationDate <= %@", a as NSDate)) }
        opzioni.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: condizioni)

        let risultato: PHFetchResult<PHAsset>
        if let album, !album.isEmpty {
            guard let raccolta = trovaAlbum(album) else {
                esito.nota = "nessun album con nome simile a «\(album)»"
                return esito
            }
            risultato = PHAsset.fetchAssets(in: raccolta, options: opzioni)
        } else {
            risultato = PHAsset.fetchAssets(with: opzioni)
        }

        // 1. filtri veloci (luogo) su un massimo di 5000 foto
        var candidati: [(id: String, data: Date?, pos: CLLocation?)] = []
        let limiteScansione = min(risultato.count, 5000)
        for k in 0..<limiteScansione {
            let f = risultato.object(at: k)
            if let luogo {
                guard let p = f.location, p.distance(from: luogo) <= raggioKm * 1000 else { continue }
            }
            candidati.append((f.localIdentifier, f.creationDate, f.location))
        }

        // 2. contenuto con Vision, sulle più recenti (con cache: la seconda volta è istantaneo)
        let parole = cosa.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var etichette: [String: [String]] = [:]
        if !parole.isEmpty {
            var cache = Cache.carica()
            let daEsaminare = candidati.prefix(limiteAI)
            var nuove = 0
            for c in daEsaminare {
                if Task.isCancelled { break }
                if let e = cache[c.id] { etichette[c.id] = e; continue }
                let e = classifica(id: c.id)
                cache[c.id] = e
                etichette[c.id] = e
                nuove += 1
            }
            if nuove > 0 { Cache.salva(cache) }
            esito.esaminate = daEsaminare.count
            candidati = daEsaminare.filter { c in
                let e = etichette[c.id] ?? []
                return parole.contains { p in e.contains { $0 == p || $0.contains(p) || ($0.count > 3 && p.contains($0)) } }
            }
            if candidati.isEmpty { esito.nota = "esaminate le \(daEsaminare.count) foto più recenti tra quelle filtrate: nessuna corrisponde" }
        } else {
            esito.esaminate = candidati.count
        }

        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        for c in candidati.prefix(max(1, min(quante, 30))) {
            esito.trovate.append(c.id)
            var riga: [String: String] = ["data": c.data.map { f.string(from: $0) } ?? "senza data"]
            if let e = etichette[c.id], !e.isEmpty { riga["contenuto"] = e.prefix(5).joined(separator: ", ") }
            if let p = c.pos { riga["coordinate"] = String(format: "%.4f, %.4f", p.coordinate.latitude, p.coordinate.longitude) }
            esito.righe.append(riga)
        }
        if esito.trovate.isEmpty, esito.nota == nil { esito.nota = "nessuna foto con questi criteri" }
        return esito
    }

    private static func trovaAlbum(_ nome: String) -> PHAssetCollection? {
        let cercato = nome.lowercased()
        var trovato: PHAssetCollection?
        for tipo in [PHAssetCollectionType.album, .smartAlbum] {
            let elenco = PHAssetCollection.fetchAssetCollections(with: tipo, subtype: .any, options: nil)
            elenco.enumerateObjects { c, _, stop in
                if (c.localizedTitle ?? "").lowercased().contains(cercato) { trovato = c; stop.pointee = true }
            }
            if trovato != nil { break }
        }
        return trovato
    }

    /// Etichette di Vision (in inglese) con fiducia sufficiente, dalla più probabile.
    private static func classifica(id: String) -> [String] {
        guard let cg = immagineSincrona(id: id, lato: 360)?.cgImage else { return [] }
        let richiesta = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([richiesta])
        } catch { return [] }
        return (richiesta.results ?? [])
            .filter { $0.confidence >= 0.25 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(12)
            .map { $0.identifier.lowercased().replacingOccurrences(of: "_", with: " ") }
    }

    private static func immagineSincrona(id: String, lato: CGFloat) -> UIImage? {
        guard let f = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let o = PHImageRequestOptions()
        o.isSynchronous = true
        o.deliveryMode = .fastFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = false     // solo ciò che è già sul telefono: veloce
        let out = Scatola()
        PHImageManager.default().requestImage(for: f, targetSize: CGSize(width: lato, height: lato), contentMode: .aspectFit, options: o) { img, _ in
            out.img = img
        }
        return out.img
    }

    /// Contenitore per il risultato delle richieste sincrone di Photos (il callback arriva prima del ritorno).
    nonisolated private final class Scatola: @unchecked Sendable { var img: UIImage? }

    /// Per le miniature e la vista a schermo intero.
    static func immagine(id: String, lato: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let f = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            let o = PHImageRequestOptions()
            o.isSynchronous = true
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true      // anche le foto rimaste su iCloud
            let out = Scatola()
            PHImageManager.default().requestImage(for: f, targetSize: CGSize(width: lato, height: lato), contentMode: .aspectFit, options: o) { img, _ in
                out.img = img
            }
            return out.img
        }.value
    }

    // Le etichette già calcolate restano in un file nella cache dell'app.
    nonisolated private enum Cache {
        static var file: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("etichette-foto.json") }
        static func carica() -> [String: [String]] {
            guard let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([String: [String]].self, from: d) else { return [:] }
            return c
        }
        static func salva(_ c: [String: [String]]) {
            if let d = try? JSONEncoder().encode(c) { try? d.write(to: file, options: .atomic) }
        }
    }
}
