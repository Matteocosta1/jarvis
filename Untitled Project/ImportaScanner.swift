#if os(iOS)
import Foundation
import ModelIO
import simd

// MARK: - 13 nov · I modelli 3D degli scanner dentro JARVIS (il signore: «la 2 mi piace… facciamola… fai quello che proponi»)
// Uno scanner a luce proiettata (Revopoint, Creality, Einstar…) misura al decimo o al centesimo di millimetro, anche dove il LiDAR
// dell'iPhone si confonde (poca luce, piastrelle, cavi). Il suo file (STL, OBJ, PLY o USDZ) entra in JARVIS dal tasto Condividi o
// da «Apri con» e diventa un OGGETTO di LiDAR: si vede in 3D (OLOGRAMMA e TEXTURE) con le misure scritte a schermo, si salva
// nell'archivio (il file originale intero e il modello in USDZ) e va allo Studio come un oggetto scansionato.
// Il file dello scanner non dice in che unità è: oltre 20 unità di lato è in millimetri (come esportano gli scanner), altrimenti in
// metri (come le app dell'iPhone). L'unità dedotta è scritta fra le misure.

/// Il modello letto dal file, pronto per la schermata (si costruisce fuori dal thread principale).
nonisolated struct ModelloImportato: Sendable {
    var oggetto: OggettoScena            // in metri, centrato, appoggiato a y = 0
    var nome: String                     // dal nome del file («mixer dpr»)
    var formato: String                  // «STL», «OBJ», «PLY», «USDZ»
    var unita: String                    // «millimetri» o «metri»
    var triangoli: Int                   // nel file
    var mostrati: Int                    // dopo la semplificazione (uguali se non serviva)
    var volume: Double?                  // m³, solo se il modello è chiuso
    var superficie: Double               // m²
    var originale: URL                   // la copia del file dello scanner, nella cartella di LiDAR
    var tipo: String                     // il tipo del file per l'Archivio
}

nonisolated enum ImportaScanner {
    static let estensioni: Set<String> = ["stl", "obj", "ply", "usdz", "usd", "usdc", "usda"]
    /// Oltre si semplifica per vederlo e per il USDZ (il file originale resta intero nell'archivio).
    static let massimoTriangoli = 300_000

    static func accetta(_ url: URL) -> Bool { url.isFileURL && estensioni.contains(url.pathExtension.lowercased()) }

    enum Guasto: Error, Sendable {
        case illeggibile, vuoto, nuvola
        var testo: String {
            switch self {
            case .illeggibile: return "Questo file non riesco ad aprirlo, Sir: me lo mandi in STL, OBJ o PLY."
            case .vuoto: return "Nel file non c'è un modello 3D, Sir."
            case .nuvola: return "È una nuvola di punti senza superficie, Sir: dallo scanner la esporti come maglia (mesh), in STL o PLY."
            }
        }
    }

    static func tipo(_ estensione: String) -> String {
        switch estensione {
        case "stl": return "model/stl"
        case "obj": return "model/obj"
        case "ply": return "model/ply"
        default: return "model/vnd.usdz+zip"
        }
    }

    /// Legge il file (copiandolo prima nella cartella di LiDAR) e prepara il modello. Lavoro pesante: mai sul thread principale.
    static func leggi(_ origine: URL) -> Result<ModelloImportato, Guasto> {
        let accesso = origine.startAccessingSecurityScopedResource()
        defer { if accesso { origine.stopAccessingSecurityScopedResource() } }
        let est = origine.pathExtension.lowercased()
        let copia = ArchivioLidar.cartella.appendingPathComponent("importato-\(UUID().uuidString).\(est)")
        do { try FileManager.default.copyItem(at: origine, to: copia) } catch { return .failure(.illeggibile) }
        // arrivato da «Apri con»: iOS l'ha messo nella cartella Inbox dell'app; copiato, lì non serve più
        if origine.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: origine) }

        let asset = MDLAsset(url: copia)
        guard asset.count > 0 else { try? FileManager.default.removeItem(at: copia); return .failure(.illeggibile) }
        var punti: [SIMD3<Float>] = []
        var colori: [SIMD3<Float>] = []
        var colorati = false
        var indici: [UInt32] = []
        for oggetto in asset.childObjects(of: MDLMesh.self) {
            guard let maglia = oggetto as? MDLMesh,
                  let pos = maglia.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3) else { continue }
            let base = UInt32(punti.count)
            let matrice = MDLTransform.globalTransform(with: maglia, atTime: 0)
            let quanti = maglia.vertexCount
            punti.reserveCapacity(punti.count + quanti)
            for i in 0..<quanti {
                let p = pos.dataStart.advanced(by: i * pos.stride)
                let v = matrice * SIMD4<Float>(p.loadUnaligned(as: Float.self), p.loadUnaligned(fromByteOffset: 4, as: Float.self),
                                               p.loadUnaligned(fromByteOffset: 8, as: Float.self), 1)
                // un vertice rotto nel file (non un numero) non deve bloccare tutto: va nell'origine
                punti.append(v.x.isFinite && v.y.isFinite && v.z.isFinite ? SIMD3(v.x, v.y, v.z) : .zero)
            }
            if let col = maglia.vertexAttributeData(forAttributeNamed: MDLVertexAttributeColor, as: .float3) {
                colorati = true
                for i in 0..<quanti {
                    let p = col.dataStart.advanced(by: i * col.stride)
                    colori.append(SIMD3(p.loadUnaligned(as: Float.self), p.loadUnaligned(fromByteOffset: 4, as: Float.self),
                                        p.loadUnaligned(fromByteOffset: 8, as: Float.self)))
                }
            } else {
                colori.append(contentsOf: repeatElement(SIMD3<Float>(0.62, 0.66, 0.68), count: quanti))
            }
            for sotto in (maglia.submeshes as? [MDLSubmesh]) ?? [] where sotto.geometryType == .triangles {
                let mappa = sotto.indexBuffer.map()
                let b = UnsafeRawPointer(mappa.bytes)
                indici.reserveCapacity(indici.count + sotto.indexCount)
                for k in 0..<sotto.indexCount {
                    let v: UInt32
                    switch sotto.indexType {
                    case .uInt8: v = UInt32(b.load(fromByteOffset: k, as: UInt8.self))
                    case .uInt16: v = UInt32(b.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self))
                    default: v = b.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self)
                    }
                    indici.append(base + v)
                }
            }
        }
        guard !punti.isEmpty else { try? FileManager.default.removeItem(at: copia); return .failure(.vuoto) }
        indici = Array(indici.prefix(indici.count - indici.count % 3))
        // un file rovinato può puntare a vertici che non ci sono: quei triangoli si saltano (invece di bloccare l'app)
        let quantiPunti = UInt32(punti.count)
        if indici.contains(where: { $0 >= quantiPunti }) {
            var buoni: [UInt32] = []
            buoni.reserveCapacity(indici.count)
            for k in stride(from: 0, to: indici.count, by: 3) where indici[k] < quantiPunti && indici[k + 1] < quantiPunti && indici[k + 2] < quantiPunti {
                buoni.append(indici[k]); buoni.append(indici[k + 1]); buoni.append(indici[k + 2])
            }
            indici = buoni
        }
        guard !indici.isEmpty else { try? FileManager.default.removeItem(at: copia); return .failure(.nuvola) }
        let triangoli = indici.count / 3

        // STL e PLY degli scanner hanno l'alto sull'asse z (come la stampa 3D); per JARVIS l'alto è y
        if est == "stl" || est == "ply" { punti = punti.map { SIMD3($0.x, $0.z, -$0.y) } }
        // l'unità: oltre 20 unità di lato sono millimetri
        var minimo = punti[0], massimo = punti[0]
        for p in punti { minimo = simd_min(minimo, p); massimo = simd_max(massimo, p) }
        let lato = max(massimo.x - minimo.x, massimo.y - minimo.y, massimo.z - minimo.z)
        let mm = lato > 20
        let scala: Float = mm ? 0.001 : 1
        // in metri, centrato in pianta e appoggiato a terra
        let centro = SIMD3((minimo.x + massimo.x) / 2, minimo.y, (minimo.z + massimo.z) / 2)
        punti = punti.map { ($0 - centro) * scala }

        // superficie e volume (tetraedri dall'origine: esatto se la maglia è chiusa)
        var area: Double = 0, volume: Double = 0
        for k in stride(from: 0, to: indici.count, by: 3) {
            let a = punti[Int(indici[k])], b = punti[Int(indici[k + 1])], c = punti[Int(indici[k + 2])]
            area += Double(simd_length(simd_cross(b - a, c - a))) / 2
            volume += Double(simd_dot(a, simd_cross(b, c))) / 6
        }

        // troppi triangoli per vederlo fluido: si semplifica (il file originale resta intero)
        var vista = (punti: punti, colori: colori, indici: indici)
        if triangoli > massimoTriangoli { vista = semplifica(punti, colori, indici, area: area, obiettivo: massimoTriangoli) }
        let chiuso = eChiuso(vista.indici)
        let estremi = (min: vista.punti.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) },
                       max: vista.punti.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) })
        let o = OggettoScena(vertici: vista.punti, colori: colorati ? vista.colori : nil, indici: vista.indici,
                             largo: estremi.max.x - estremi.min.x, profondo: estremi.max.z - estremi.min.z, alto: estremi.max.y - estremi.min.y)
        let nome = origine.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return .success(ModelloImportato(oggetto: o, nome: nome.isEmpty ? "Modello" : nome, formato: est == "usd" || est.hasPrefix("usd") ? "USDZ" : est.uppercased(),
                                         unita: mm ? "millimetri" : "metri", triangoli: triangoli, mostrati: vista.indici.count / 3,
                                         volume: chiuso ? abs(volume) : nil, superficie: area, originale: copia, tipo: tipo(est)))
    }

    /// Semplificazione per raggruppamento: i vertici si uniscono in celle di una griglia (della misura giusta per stare sotto
    /// l'obiettivo), i triangoli diventati piatti spariscono. Forma e misure restano; spariscono solo i dettagli più fini.
    private static func semplifica(_ punti: [SIMD3<Float>], _ colori: [SIMD3<Float>], _ indici: [UInt32], area: Double,
                                   obiettivo: Int) -> (punti: [SIMD3<Float>], colori: [SIMD3<Float>], indici: [UInt32]) {
        var cella = max(Float((2 * area / Double(obiettivo)).squareRoot()), 0.000_01)
        func casella(_ x: Float) -> Int32 {                       // sempre un numero valido, anche con coordinate enormi
            let q = (x / cella).rounded(.down)
            return Int32(q.isFinite ? max(-2_000_000_000, min(2_000_000_000, q)) : 0)
        }
        var risultato = (punti: punti, colori: colori, indici: indici)
        for _ in 0..<5 {
            var mappa: [SIMD3<Int32>: UInt32] = [:]
            mappa.reserveCapacity(min(punti.count, obiettivo * 2))
            var somme: [SIMD3<Float>] = [], tinte: [SIMD3<Float>] = [], conti: [Float] = []
            var nuovo = [UInt32](repeating: 0, count: punti.count)
            for (i, p) in punti.enumerated() {
                let chiave = SIMD3<Int32>(casella(p.x), casella(p.y), casella(p.z))
                if let k = mappa[chiave] {
                    nuovo[i] = k
                    somme[Int(k)] += p; tinte[Int(k)] += colori[i]; conti[Int(k)] += 1
                } else {
                    let k = UInt32(somme.count)
                    mappa[chiave] = k
                    nuovo[i] = k
                    somme.append(p); tinte.append(colori[i]); conti.append(1)
                }
            }
            var tri: [UInt32] = []
            tri.reserveCapacity(min(indici.count, obiettivo * 4))
            for k in stride(from: 0, to: indici.count, by: 3) {
                let a = nuovo[Int(indici[k])], b = nuovo[Int(indici[k + 1])], c = nuovo[Int(indici[k + 2])]
                if a != b && b != c && a != c { tri.append(a); tri.append(b); tri.append(c) }
            }
            risultato = (punti: zip(somme, conti).map { $0 / $1 }, colori: zip(tinte, conti).map { $0 / $1 }, indici: tri)
            if tri.count / 3 <= obiettivo * 13 / 10 { break }
            cella *= 1.4
        }
        return risultato
    }

    /// La maglia è chiusa (ogni lato tra due triangoli): solo allora il volume ha senso.
    private static func eChiuso(_ indici: [UInt32]) -> Bool {
        guard indici.count >= 12 else { return false }
        var lati: [UInt64: UInt8] = [:]
        lati.reserveCapacity(indici.count)
        for k in stride(from: 0, to: indici.count, by: 3) {
            for (a, b) in [(indici[k], indici[k + 1]), (indici[k + 1], indici[k + 2]), (indici[k + 2], indici[k])] {
                let chiave = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                lati[chiave, default: 0] &+= 1
            }
        }
        return lati.values.allSatisfy { $0 == 2 }
    }
}
#endif
