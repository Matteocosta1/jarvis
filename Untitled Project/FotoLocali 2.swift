import Foundation
import Combine
import Photos
import Vision
import CoreLocation
import UIKit

/// Ricerca nella galleria del signore: per data, luogo, album e — con l'AI di Apple sul telefono (Vision) — per contenuto.
/// Tutto resta sull'iPhone: le foto non vanno mai al cervello, solo le date e le etichette trovate.
/// 4 nov (i problemi trovati col signore, corretti): prima cercava solo nel periodo scelto e solo fra le 400 foto più recenti,
/// capiva una trentina di parole e confrontava pezzi di parola, e una foto che una volta non si apriva restava «vuota» per sempre.
/// Ora l'analisi copre tutta la galleria (IndiceFoto: una volta sola, dalle più recenti, poi solo le nuove), le parole passano dal
/// dizionario completo (DizionarioFoto) e si confrontano parole intere; le foto che non si aprono si riprovano.
/// Le funzioni sono `nonisolated`: Photos e Vision lavorano fuori dal thread principale.
nonisolated enum FotoLocali {

    nonisolated struct Esito: Sendable {
        var trovate: [String] = []          // localIdentifier, dalla più recente
        var righe: [[String: String]] = []  // per il cervello: data, luogo (se c'è), etichette (le prime 30 foto)
        var esaminate = 0
        var nota: String?
        var nonCapite: [String] = []        // le parole che non sono né categorie di Apple né album (come le ha scritte lui)
        var capite: [String] = []           // le cose capite, come le ha scritte lui: si mostrano sotto il campo («CANI + MARE»)
    }

    /// Una cosa da trovare: basta una delle sue categorie o dei suoi album.
    nonisolated struct Gruppo: Sendable {
        var etichette = Set<UInt16>()
        var album: [Int] = []
    }

    static func autorizza() async -> Bool {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// Accesso limitato: JARVIS vede solo le foto che il signore ha scelto.
    static var accessoLimitato: Bool { PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited }

    /// Per il cervello e l'orologio: `cosa` sono parole (le categorie inglesi di Vision, o italiane) e basta che una corrisponda.
    /// `limiteAI`: quante foto fra le più recenti si analizzano subito, se l'analisi della galleria non ci è ancora arrivata.
    @concurrent static func cerca(cosa: [String], da: Date?, a: Date?, luogo: CLLocation?, raggioKm: Double, album: String?, quante: Int, limiteAI: Int = 400) async -> Esito {
        var g = Gruppo(), ignote: [String] = []
        for p in cosa {
            let l = DizionarioFoto.capisci(p)
            ignote += l.nonCapite
            for c in l.cose {
                switch c {
                case .etichette(let e): g.etichette.formUnion(e)
                case .album(let t): g.album.append(t)
                }
            }
        }
        let vuota = g.etichette.isEmpty && g.album.isEmpty
        if vuota && !ignote.isEmpty {
            var e = Esito()
            e.nonCapite = ignote
            e.nota = "nessuna di queste parole è tra le cose che l'AI di Apple riconosce nelle foto: \(ignote.joined(separator: ", "))"
            return e
        }
        var esito = await trova(gruppi: vuota ? [] : [g], da: da, a: a, luogo: luogo, raggioKm: raggioKm, album: album,
                                quante: max(1, min(quante, 30)), recenti: limiteAI)
        esito.nonCapite = ignote
        return esito
    }

    /// Per la sezione Foto: il testo scritto dal signore. Ogni cosa riconosciuta deve esserci («cani al mare»: cani e mare);
    /// le parole che non sono categorie né album si segnalano. Senza parole da cercare: le foto del periodo.
    @concurrent static func cercaTesto(_ testo: String, da: Date?, a: Date?, quante: Int) async -> Esito {
        let lettura = DizionarioFoto.capisci(testo)
        let cose = lettura.cose, ignote = lettura.nonCapite
        if cose.isEmpty && !ignote.isEmpty {
            var e = Esito()
            e.nonCapite = ignote
            e.nota = "Non riconosco «\(ignote.joined(separator: " "))»: l'AI di Apple riconosce cose, animali e luoghi nelle foto, non le persone per nome."
            return e
        }
        let gruppi: [Gruppo] = cose.map { c in
            switch c {
            case .etichette(let e): return Gruppo(etichette: e, album: [])
            case .album(let t): return Gruppo(etichette: [], album: [t])
            }
        }
        var esito = await trova(gruppi: gruppi, da: da, a: a, luogo: nil, raggioKm: 5, album: nil, quante: quante, recenti: 60)
        esito.nonCapite = ignote
        esito.capite = lettura.scritte
        if !ignote.isEmpty && !esito.trovate.isEmpty {
            esito.nota = "Non riconosco «\(ignote.joined(separator: " "))»: cerco solo il resto."
        }
        return esito
    }

    // MARK: il cuore della ricerca

    /// `gruppi`: tutti insieme (in ognuno basta una categoria o un album); poi le date, il luogo, l'album col nome.
    private static func trova(gruppi: [Gruppo], da: Date?, a: Date?, luogo: CLLocation?, raggioKm: Double, album: String?,
                              quante: Int, recenti: Int) async -> Esito {
        var esito = Esito()
        let opzioni = PHFetchOptions()
        opzioni.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var condizioni = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if let da { condizioni.append(NSPredicate(format: "creationDate >= %@", da as NSDate)) }
        if let a { condizioni.append(NSPredicate(format: "creationDate <= %@", a as NSDate)) }
        opzioni.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: condizioni)

        var raccolta: PHAssetCollection?
        if let album, !album.isEmpty {
            guard let r = trovaAlbum(album) else {
                esito.nota = "nessun album con nome simile a «\(album)»"
                return esito
            }
            raccolta = r
        }
        let base = raccolta.map { PHAsset.fetchAssets(in: $0, options: opzioni) } ?? PHAsset.fetchAssets(with: opzioni)
        let indice = IndiceFoto.condiviso
        await indice.avvia()                                          // l'analisi di tutta la galleria, se non c'è ancora

        var scelte: [PHAsset] = []
        if gruppi.isEmpty {
            esito.esaminate = base.count
            var k = 0
            while k < base.count && scelte.count < quante {
                let f = base.object(at: k)
                if vicina(f, a: luogo, raggioKm: raggioKm) { scelte.append(f) }
                k += 1
            }
        } else {
            // le più recenti (anche appena scattate) si analizzano subito; il resto lo fa l'analisi della galleria
            var nuove: [String] = []
            for k in 0..<min(base.count, recenti) { nuove.append(base.object(at: k).localIdentifier) }
            await indice.assicura(nuove)
            var buone: Set<String>?
            for g in gruppi {
                var s = await indice.con(g.etichette)
                for t in g.album { s.formUnion(idsAlbum(t)) }
                buone = buone.map { $0.intersection(s) } ?? s
            }
            esito.esaminate = await indice.analizzate
            let ids = Array(buone ?? [])
            if !ids.isEmpty {
                let trovati = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: opzioni)
                let dentro: Set<String>? = raccolta == nil ? nil : idsDi(base)
                var k = 0
                while k < trovati.count && scelte.count < quante {
                    let f = trovati.object(at: k)
                    k += 1
                    if let dentro, !dentro.contains(f.localIdentifier) { continue }
                    if vicina(f, a: luogo, raggioKm: raggioKm) { scelte.append(f) }
                }
            }
        }

        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        let etichette = await indice.etichette(di: scelte.prefix(30).map(\.localIdentifier))
        for c in scelte {
            esito.trovate.append(c.localIdentifier)
            guard esito.righe.count < 30 else { continue }
            var riga: [String: String] = ["data": c.creationDate.map { f.string(from: $0) } ?? "senza data"]
            if let e = etichette[c.localIdentifier], !e.isEmpty {
                riga["contenuto"] = e.prefix(5).map { DizionarioFoto.etichette[Int($0)].replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")
            }
            if let p = c.location { riga["coordinate"] = String(format: "%.4f, %.4f", p.coordinate.latitude, p.coordinate.longitude) }
            esito.righe.append(riga)
        }
        if esito.trovate.isEmpty {
            let stato = await indice.stato()
            if !gruppi.isEmpty && !stato.completa && stato.totale > 0 {
                esito.nota = "Nessuna finora: sto ancora analizzando la galleria (\(stato.fatte) di \(stato.totale) foto)."
            } else {
                esito.nota = "nessuna foto con questi criteri"
            }
        }
        return esito
    }

    private static func vicina(_ f: PHAsset, a luogo: CLLocation?, raggioKm: Double) -> Bool {
        guard let luogo else { return true }
        guard let p = f.location else { return false }
        return p.distance(from: luogo) <= raggioKm * 1000
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

    /// Le foto di un album di Apple (selfie, screenshot, preferite…).
    private static func idsAlbum(_ tipo: Int) -> Set<String> {
        guard let s = PHAssetCollectionSubtype(rawValue: tipo),
              let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: s, options: nil).firstObject else { return [] }
        return idsDi(PHAsset.fetchAssets(in: c, options: nil))
    }

    private static func idsDi(_ r: PHFetchResult<PHAsset>) -> Set<String> {
        var s = Set<String>()
        s.reserveCapacity(r.count)
        for k in 0..<r.count { s.insert(r.object(at: k).localIdentifier) }
        return s
    }

    // MARK: le immagini

    /// Le categorie di Vision di una foto (fiducia almeno 0,25, le 12 più probabili, come prima). nil: la foto non si è aperta
    /// (non si segna: si riprova al giro dopo). `rete`: anche la versione piccola da iCloud.
    static func classifica(_ foto: PHAsset, rete: Bool) -> [UInt16]? {
        classificaConFiducia(foto, rete: rete)?.map { $0.0 }
    }

    /// Come `classifica`, con la fiducia di ogni categoria (0-1): l'ologramma dell'analisi la scrive accanto alle cose trovate.
    static func classificaConFiducia(_ foto: PHAsset, rete: Bool) -> [(UInt16, Float)]? {
        guard let cg = immagineSincrona(foto, lato: 360, rete: rete)?.cgImage else { return nil }
        let richiesta = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([richiesta])
        } catch { return nil }
        return (richiesta.results ?? [])
            .filter { $0.confidence >= 0.25 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(12)
            .compactMap { (r: VNClassificationObservation) -> (UInt16, Float)? in
                guard let k = DizionarioFoto.posizione[r.identifier] else { return nil }
                return (k, r.confidence)
            }
    }

    private static func immagineSincrona(_ foto: PHAsset, lato: CGFloat, rete: Bool) -> UIImage? {
        let o = PHImageRequestOptions()
        o.isSynchronous = true
        o.deliveryMode = rete ? .highQualityFormat : .fastFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = rete      // prima solo ciò che è già sul telefono (veloce); al secondo giro anche iCloud
        let out = Scatola()
        PHImageManager.default().requestImage(for: foto, targetSize: CGSize(width: lato, height: lato), contentMode: .aspectFit, options: o) { img, _ in
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
}

/// L'analisi di tutta la galleria con l'AI di Apple (Vision), una volta sola: dalle foto più recenti alle più vecchie, poi solo le
/// nuove. Le etichette restano in un file nella cache dell'app (salvato ogni 300 foto). Le foto che non si aprono non si segnano:
/// alla fine del giro si riprovano con iCloud, e se ancora non si aprono si riprovano la volta dopo.
actor IndiceFoto {
    nonisolated static let condiviso = IndiceFoto()

    private var etichette: [String: [UInt16]] = [:]
    private var caricato = false
    private var lavoro: Task<Void, Never>?
    private var nonSalvate = 0
    private var fatte = 0
    private var totale = 0
    private var completa = false

    /// Quante foto sono già analizzate.
    var analizzate: Int { etichette.count }

    func stato() -> (fatte: Int, totale: Int, completa: Bool) { (fatte, totale, completa) }

    private func carica() {
        guard !caricato else { return }
        caricato = true
        etichette = Archivio.carica()
        Archivio.togliVecchio()
    }

    /// Parte (o continua) l'analisi di tutta la galleria, in sottofondo; il conto lo pubblica `AvanzamentoFoto`.
    func avvia() {
        carica()
        let permesso = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard lavoro == nil, permesso == .authorized || permesso == .limited else { return }
        lavoro = Task(priority: .utility) { await self.analizzaTutto() }
    }

    private func analizzaTutto() async {
        let opzioni = PHFetchOptions()
        opzioni.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opzioni.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let tutte = PHAsset.fetchAssets(with: opzioni)
        var mancanti: [PHAsset] = [], presenti = Set<String>()
        presenti.reserveCapacity(tutte.count)
        for k in 0..<tutte.count {
            let f = tutte.object(at: k)
            presenti.insert(f.localIdentifier)
            if etichette[f.localIdentifier] == nil { mancanti.append(f) }
        }
        // le foto cancellate escono dall'indice (il file resta piccolo)
        if etichette.count > presenti.count - mancanti.count {
            etichette = etichette.filter { presenti.contains($0.key) }
            nonSalvate += 1
        }
        totale = tutte.count
        fatte = totale - mancanti.count
        completa = mancanti.isEmpty
        await pubblica(attivo: !mancanti.isEmpty)
        // primo giro: solo quello che è già sul telefono (veloce); secondo giro: le foto che non si sono aperte, anche da iCloud
        var daRiprovare: [PHAsset] = [], falliti = 0
        for f in mancanti {
            if Task.isCancelled { break }
            if etichette[f.localIdentifier] != nil { fatte += 1 }      // analizzata intanto da una ricerca
            else if !analizza(f, rete: false) { daRiprovare.append(f) }
            await avanza()
        }
        for f in daRiprovare {
            if Task.isCancelled { break }
            if etichette[f.localIdentifier] != nil { fatte += 1 }      // analizzata intanto da una ricerca
            else if !analizza(f, rete: true) { falliti += 1 }          // si riprova la volta dopo
            await avanza()
        }
        completa = falliti == 0 && !Task.isCancelled
        if nonSalvate > 0 { salva() }
        await pubblica(attivo: false)
        lavoro = nil
    }

    /// Una foto: le sue categorie nell'indice. Falso se non si è aperta (non si segna niente). Ogni 1,4 s la foto appena letta,
    /// con le sue cose e la fiducia, diventa il campione che l'ologramma della sezione Foto mostra.
    private func analizza(_ f: PHAsset, rete: Bool) -> Bool {
        guard let e = FotoLocali.classificaConFiducia(f, rete: rete) else { return false }
        etichette[f.localIdentifier] = e.map { $0.0 }
        nonSalvate += 1
        fatte += 1
        if Date().timeIntervalSince(ultimoCampione) > 1.4 {
            ultimoCampione = Date()
            campione = CampioneFoto(id: f.localIdentifier, cose: CampioneFoto.cose(e))
        }
        return true
    }

    private var ultimoCampione = Date.distantPast
    private var campione: CampioneFoto?

    private var ultimoConto = Date.distantPast

    /// Dopo ogni foto: il file ogni 300 foto, il conto a schermo 4 volte al secondo, e spazio alle ricerche.
    private func avanza() async {
        if nonSalvate >= 300 { salva() }
        if Date().timeIntervalSince(ultimoConto) > 0.25 {
            ultimoConto = Date()
            await pubblica(attivo: true)
        }
        await Task.yield()
    }

    /// Le foto indicate (le più recenti di una ricerca), analizzate subito se mancano.
    func assicura(_ ids: [String]) async {
        carica()
        let mancano = ids.filter { etichette[$0] == nil }
        guard !mancano.isEmpty else { return }
        let r = PHAsset.fetchAssets(withLocalIdentifiers: mancano, options: nil)
        var nuove = 0
        for k in 0..<r.count {
            if Task.isCancelled { break }
            let f = r.object(at: k)
            if etichette[f.localIdentifier] == nil, let e = FotoLocali.classifica(f, rete: false) {
                etichette[f.localIdentifier] = e
                nuove += 1
            }
            await Task.yield()
        }
        if nuove > 0 {
            nonSalvate += nuove
            if lavoro == nil { salva() }
        }
    }

    /// Le foto con almeno una di queste categorie.
    func con(_ g: Set<UInt16>) -> Set<String> {
        carica()
        guard !g.isEmpty else { return [] }
        var out = Set<String>()
        for (id, e) in etichette where e.contains(where: { g.contains($0) }) { out.insert(id) }
        return out
    }

    /// Le categorie di queste foto (per il cervello).
    func etichette(di ids: [String]) -> [String: [UInt16]] {
        carica()
        var out: [String: [UInt16]] = [:]
        for id in ids { if let e = etichette[id] { out[id] = e } }
        return out
    }

    private func salva() {
        Archivio.salva(etichette)
        nonSalvate = 0
    }

    private func pubblica(attivo: Bool) async {
        let f = fatte, t = totale, c = campione
        await MainActor.run { AvanzamentoFoto.condiviso.aggiorna(fatte: f, totale: t, attivo: attivo, campione: c) }
    }

    /// Il file delle etichette nella cache dell'app (le categorie per nome: il file resta valido anche se l'elenco cambiasse).
    nonisolated private enum Archivio {
        static var cartella: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }
        static var file: URL { cartella.appendingPathComponent("etichette-foto-2.json") }

        static func carica() -> [String: [UInt16]] {
            guard let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([String: [String]].self, from: d) else { return [:] }
            var out: [String: [UInt16]] = [:]
            out.reserveCapacity(c.count)
            for (id, nomi) in c { out[id] = nomi.compactMap { DizionarioFoto.posizione[$0] } }
            return out
        }

        static func salva(_ e: [String: [UInt16]]) {
            let c = e.mapValues { v in v.map { DizionarioFoto.etichette[Int($0)] } }
            if let d = try? JSONEncoder().encode(c) { try? d.write(to: file, options: .atomic) }
        }

        /// Il file di prima (con le foto «vuote» segnate per sempre): si butta, l'analisi riparte giusta.
        static func togliVecchio() {
            try? FileManager.default.removeItem(at: cartella.appendingPathComponent("etichette-foto.json"))
        }
    }
}

/// Una foto appena analizzata, per l'ologramma della sezione Foto: il suo id e le prime 4 cose trovate (nome italiano, fiducia).
nonisolated struct CampioneFoto: Sendable, Equatable {
    nonisolated struct CosaTrovata: Sendable, Equatable {
        let nome: String
        let fiducia: Double
    }
    let id: String
    let cose: [CosaTrovata]

    /// Le prime 4 cose con un nome diverso (dog e canine sono tutti e due «cane»).
    static func cose(_ e: [(UInt16, Float)]) -> [CosaTrovata] {
        var visti = Set<String>(), out: [CosaTrovata] = []
        for (k, c) in e {
            let n = DizionarioFoto.nome(k).uppercased()
            if visti.contains(n) { continue }
            visti.insert(n)
            out.append(CosaTrovata(nome: n, fiducia: Double(c)))
            if out.count == 4 { break }
        }
        return out
    }
}

/// Il conto dell'analisi della galleria, per la sezione Foto («1.240 / 8.312»), e la foto che l'ologramma mostra.
final class AvanzamentoFoto: ObservableObject {
    static let condiviso = AvanzamentoFoto()
    @Published private(set) var fatte = 0
    @Published private(set) var totale = 0
    @Published private(set) var attivo = false
    /// Sale ogni 400 foto analizzate: una ricerca aperta si ripete e trova anche quelle nuove.
    @Published private(set) var passo = 0
    /// L'ultima foto letta (una ogni 1,4 s circa), con le sue cose.
    @Published private(set) var campione: CampioneFoto?

    func aggiorna(fatte: Int, totale: Int, attivo: Bool, campione: CampioneFoto? = nil) {
        if self.fatte != fatte { self.fatte = fatte }
        if self.totale != totale { self.totale = totale }
        if self.attivo != attivo { self.attivo = attivo }
        let p = attivo ? fatte / 400 : -1
        if passo != p { passo = p }
        if let campione, self.campione != campione { self.campione = campione }
    }
}
