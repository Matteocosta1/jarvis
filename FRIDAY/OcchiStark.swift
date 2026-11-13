#if os(iOS)
import SwiftUI
import Combine
import AVFoundation
import Vision
import CoreVideo
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Foundation

/// BUILD 23 — Gli OCCHI alla Stark (mockup 23 approvato, funzione `occhi` e `occhiVivo`): il riconoscimento dal vivo.
/// All'apertura niente è acceso (deciso dal signore il 24 ottobre: ETICHETTE e OLOGRAMMA non si ricordano, si accendono
/// solo toccandoli o a voce). ETICHETTE: un mirino ad angoli e un nome piccolo su ogni persona, animale, oggetto e testo.
/// OLOGRAMMA: sul bersaglio (quello toccato, se no il più vicino al centro) la sagoma laser, i lineamenti e la scheda col
/// modello 3D; il nome preciso arriva dal cervello. CERCA: il solo bersaglio va al cervello, che lo cerca sul web (mai le persone).
/// Sotto OCCHI · MANUALE, piccolo, quello che vede: 1 PERSONA · 2 ANIMALI · 3 OGGETTI · 1 TESTO.
/// Tutto il riconoscimento è in locale (Vision): al cervello vanno solo il ritaglio del bersaglio (scheda) e la ricerca (CERCA).

// MARK: - Cosa vede

nonisolated enum TipoVisto: Sendable { case persona, animale, oggetto, testo }

nonisolated struct Visto: Sendable, Identifiable {
    let id: Int
    var tipo: TipoVisto
    var nome: String                 // «PERSONA», «CANE», «BANANA», «TESTO», «OGGETTO»
    var certezza: Float
    var box: CGRect                  // normalizzato dall'alto
    var letto: [String]              // solo i testi: le righe lette
}

/// Il bersaglio con l'ologramma: la sagoma (relativa al suo riquadro, così segue il riquadro del tracciamento a ogni fotogramma),
/// i lineamenti del fotogramma, la nuvola 3D e, per le persone, la distanza dalle pupille.
nonisolated struct BersaglioOcchi: @unchecked Sendable {
    let id: Int
    var sagomaRelativa: [CGPoint]
    var lineamenti: CGImage?
    var regione: CGRect
    var nuvola: Nuvola?
    var distanzaViso: Double?
}

nonisolated struct VistaOcchi: @unchecked Sendable {
    var visti: [Visto]
    var dimensione: CGSize
    var fuoco: Double
    var frontale: Bool
    var bersaglio: BersaglioOcchi?
}

/// I nomi italiani delle classi di Vision (VNClassifyImageRequest: identificatori inglesi con «_»). Quelle che non ci sono
/// restano «OGGETTO»: meglio una parola generica giusta che un nome inglese a metà.
nonisolated enum NomiOcchi {
    static let classi: [String: String] = [
        "banana": "BANANA", "apple": "MELA", "orange": "ARANCIA", "lemon": "LIMONE", "pear": "PERA", "strawberry": "FRAGOLA", "grape": "UVA",
        "tomato": "POMODORO", "carrot": "CAROTA", "potato": "PATATA", "bread": "PANE", "pizza": "PIZZA", "cake": "TORTA", "sandwich": "PANINO",
        "fruit": "FRUTTA", "vegetable": "VERDURA", "food": "CIBO", "egg": "UOVO", "cheese": "FORMAGGIO",
        "bottle": "BOTTIGLIA", "water_bottle": "BOTTIGLIA", "wine_bottle": "BOTTIGLIA", "beer_bottle": "BOTTIGLIA", "can": "LATTINA",
        "cup": "TAZZA", "mug": "TAZZA", "coffee_mug": "TAZZA", "glass": "BICCHIERE", "wine_glass": "CALICE", "drinking_glass": "BICCHIERE",
        "plate": "PIATTO", "bowl": "CIOTOLA", "fork": "FORCHETTA", "knife": "COLTELLO", "spoon": "CUCCHIAIO", "jar": "BARATTOLO",
        "book": "LIBRO", "notebook": "QUADERNO", "paper": "FOGLIO", "document": "DOCUMENTO", "magazine": "RIVISTA", "pen": "PENNA", "pencil": "MATITA",
        "computer_keyboard": "TASTIERA", "keyboard": "TASTIERA", "computer_mouse": "MOUSE", "mouse": "MOUSE", "laptop": "PORTATILE",
        "computer": "COMPUTER", "monitor": "MONITOR", "screen": "SCHERMO", "television": "TELEVISORE", "tv": "TELEVISORE",
        "cellphone": "TELEFONO", "cell_phone": "TELEFONO", "mobile_phone": "TELEFONO", "smartphone": "TELEFONO", "phone": "TELEFONO", "telephone": "TELEFONO",
        "tablet": "TABLET", "camera": "FOTOCAMERA", "headphones": "CUFFIE", "speaker": "CASSA", "remote_control": "TELECOMANDO", "watch": "OROLOGIO",
        "clock": "OROLOGIO", "wristwatch": "OROLOGIO", "lamp": "LAMPADA", "light_bulb": "LAMPADINA", "candle": "CANDELA",
        "chair": "SEDIA", "table": "TAVOLO", "desk": "SCRIVANIA", "sofa": "DIVANO", "couch": "DIVANO", "bed": "LETTO", "pillow": "CUSCINO",
        "shelf": "SCAFFALE", "bookshelf": "LIBRERIA", "door": "PORTA", "window": "FINESTRA", "mirror": "SPECCHIO", "vase": "VASO",
        "plant": "PIANTA", "houseplant": "PIANTA", "potted_plant": "PIANTA", "flower": "FIORE", "tree": "ALBERO",
        "car": "AUTO", "automobile": "AUTO", "truck": "FURGONE", "van": "FURGONE", "bus": "AUTOBUS", "motorcycle": "MOTO", "scooter": "SCOOTER",
        "bicycle": "BICICLETTA", "bike": "BICICLETTA", "boat": "BARCA", "airplane": "AEREO", "train": "TRENO",
        "bag": "BORSA", "handbag": "BORSA", "backpack": "ZAINO", "suitcase": "VALIGIA", "wallet": "PORTAFOGLIO", "umbrella": "OMBRELLO",
        "shoe": "SCARPA", "shoes": "SCARPE", "sneaker": "SCARPA", "hat": "CAPPELLO", "cap": "BERRETTO", "glasses": "OCCHIALI", "sunglasses": "OCCHIALI",
        "jacket": "GIACCA", "shirt": "MAGLIETTA", "jeans": "JEANS", "clothing": "VESTITO", "dress": "ABITO",
        "ball": "PALLA", "toy": "GIOCATTOLO", "guitar": "CHITARRA", "piano": "PIANOFORTE", "musical_instrument": "STRUMENTO",
        "vinyl_record": "DISCO", "record": "DISCO", "turntable": "GIRADISCHI", "cd": "CD",
        "medicine": "MEDICINA", "pill": "PASTIGLIA", "pill_bottle": "FLACONE", "cosmetics": "COSMETICO", "perfume": "PROFUMO",
        "key": "CHIAVE", "keys": "CHIAVI", "scissors": "FORBICI", "tool": "ATTREZZO", "box": "SCATOLA", "cardboard_box": "SCATOLA", "package": "PACCO",
        "dog": "CANE", "cat": "GATTO", "bird": "UCCELLO", "horse": "CAVALLO", "fish": "PESCE",
    ]
}

// MARK: - Il riconoscimento (Vision, sulla coda dei fotogrammi degli Occhi)

/// Persone (VNDetectHumanRectanglesRequest) e animali (VNRecognizeAnimalsRequest) ogni ~0,12 s; oggetti (VNGenerateForegroundInstanceMaskRequest
/// + VNClassifyImageRequest sul riquadro) ogni 0,8 s e testi (VNRecognizeTextRequest, italiano e inglese) ogni 1,2 s, seguiti
/// in mezzo con VNTrackObjectRequest. Sul bersaglio con l'OLOGRAMMA: la sagoma (5 volte al secondo), i lineamenti e la nuvola.
/// Lavora sulla coda dei fotogrammi: i fotogrammi in ritardo li scarta la fotocamera, il thread principale non aspetta mai.
nonisolated final class VisoreOcchi: @unchecked Sendable {
    private let lucchetto = NSLock()
    private var attivo = false
    private var conOlo = false
    private var bersaglio: Int?
    private var ultimo: CVPixelBuffer?
    private let contesto = CIContext(options: [.cacheIntermediates: false])
    /// Ogni fotogramma analizzato (da qui va sul thread principale).
    var esito: (@Sendable (VistaOcchi) -> Void)?

    private nonisolated final class Traccia {
        let id: Int
        var tipo: TipoVisto
        var nome: String
        var certezza: Float
        var box: CGRect
        var letto: [String] = []
        var segui: VNTrackObjectRequest?
        var mancato = 0
        init(id: Int, tipo: TipoVisto, nome: String, certezza: Float, box: CGRect) {
            self.id = id; self.tipo = tipo; self.nome = nome; self.certezza = certezza; self.box = box
        }
    }
    private var tracce: [Traccia] = []
    private var prossimo = 1
    private var sequenza = VNSequenceRequestHandler()
    private var frontalePrima: Bool?
    private var ultimiCorpi = Date.distantPast, ultimiOggetti = Date.distantPast, ultimiTesti = Date.distantPast
    private var ultimaSagoma = Date.distantPast, ultimaNuvola = Date.distantPast
    private var extra: (id: Int, relativo: [CGPoint], sagoma: Sagoma?, nuvola: Nuvola?, viso: Double?)?

    private let persone: VNDetectHumanRectanglesRequest = {
        let r = VNDetectHumanRectanglesRequest()
        r.upperBodyOnly = false                                  // anche chi si vede intero
        return r
    }()
    private let animali = VNRecognizeAnimalsRequest()
    private let primoPiano = VNGenerateForegroundInstanceMaskRequest()
    private let sagomePersone = VNGeneratePersonInstanceMaskRequest()
    private let classifica = VNClassifyImageRequest()
    private let visi = VNDetectFaceLandmarksRequest()
    private let testi: VNRecognizeTextRequest = {
        let r = VNRecognizeTextRequest()
        r.recognitionLevel = .fast
        r.recognitionLanguages = ["it-IT", "en-US"]
        r.usesLanguageCorrection = false
        return r
    }()

    private static let uno = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Vision ha l'origine in basso, noi in alto: la stessa formula va e viene.
    private static func capovolto(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }

    /// Dal thread principale: acceso (ETICHETTE o OLOGRAMMA), ologramma, bersaglio.
    func imposta(attivo a: Bool, olo: Bool, bersaglio b: Int?) {
        lucchetto.lock(); attivo = a; conOlo = olo; bersaglio = b; lucchetto.unlock()
    }

    /// Un fotogramma (BGRA, verticale, non specchiato) dalla coda della fotocamera.
    func analizza(_ px: CVPixelBuffer, frontale: Bool, fuoco: Double) {
        lastFuoco = fuoco
        lucchetto.lock()
        let acceso = attivo, olo = conOlo, b = bersaglio
        ultimo = acceso ? px : nil
        lucchetto.unlock()
        guard acceso else {
            if !tracce.isEmpty || extra != nil { tracce = []; extra = nil; sequenza = VNSequenceRequestHandler() }
            return
        }
        if frontalePrima != frontale {                           // girata la fotocamera: si ricomincia
            tracce = []; extra = nil; sequenza = VNSequenceRequestHandler(); frontalePrima = frontale
            ultimiCorpi = .distantPast; ultimiOggetti = .distantPast; ultimiTesti = .distantPast
        }
        let adesso = Date()
        let gestore = VNImageRequestHandler(cvPixelBuffer: px, orientation: .up, options: [:])
        segui(px)
        if adesso.timeIntervalSince(ultimiCorpi) > 0.12 { ultimiCorpi = adesso; corpi(gestore) }
        if adesso.timeIntervalSince(ultimiOggetti) > 0.8 { ultimiOggetti = adesso; oggetti(gestore) }
        else if adesso.timeIntervalSince(ultimiTesti) > 1.2 { ultimiTesti = adesso; leggi(gestore) }
        var bers: BersaglioOcchi?
        if olo, let b, let t = tracce.first(where: { $0.id == b }) { bers = bersaglioOlo(t, gestore, px, adesso) } else { extra = nil }
        let visti = tracce.map { Visto(id: $0.id, tipo: $0.tipo, nome: $0.nome, certezza: $0.certezza, box: $0.box, letto: $0.letto) }
        let dim = CGSize(width: CVPixelBufferGetWidth(px), height: CVPixelBufferGetHeight(px))
        esito?(VistaOcchi(visti: visti, dimensione: dim, fuoco: fuoco, frontale: frontale, bersaglio: bers))
    }

    /// Oggetti e testi tra un riconoscimento e l'altro: il tracciamento di Vision (veloce) li tiene agganciati mentre il telefono si muove.
    private func segui(_ px: CVPixelBuffer) {
        let con = tracce.filter { $0.segui != nil }
        guard !con.isEmpty else { return }
        do { try sequenza.perform(con.compactMap { $0.segui }, on: px, orientation: .up) } catch {
            for t in con { t.segui = nil }                       // troppi o persi: li ritrova il prossimo riconoscimento
            sequenza = VNSequenceRequestHandler()
            return
        }
        var via = Set<Int>()
        for t in con {
            guard let r = t.segui, let o = r.results?.first as? VNDetectedObjectObservation, o.confidence >= 0.3 else { via.insert(t.id); continue }
            t.box = Self.capovolto(o.boundingBox).intersection(Self.uno)
            r.inputObservation = o
        }
        tracce.removeAll { via.contains($0.id) || $0.box.isNull || $0.box.width < 0.005 }
    }

    private func nuovoSegui(_ t: Traccia) {
        let r = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: Self.capovolto(t.box)))
        r.trackingLevel = .fast
        t.segui = r
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let ai = i.width * i.height
        return ai / (a.width * a.height + b.width * b.height - ai)
    }

    /// Unisce quello che ha appena trovato (di un tipo) con quello che già seguiva: stesso numero a chi si sovrappone.
    private func unisci(_ nuovi: [(box: CGRect, nome: String, certezza: Float, letto: [String])], tipi: Set<TipoVisto>, tipo: (String) -> TipoVisto,
                        conSegui: Bool, sparisceDopo: Int) {
        var presi = Set<Int>()
        for n in nuovi {
            let candidata = tracce.filter { tipi.contains($0.tipo) && !presi.contains($0.id) }.max { Self.iou($0.box, n.box) < Self.iou($1.box, n.box) }
            if let t = candidata, Self.iou(t.box, n.box) > 0.3 {
                t.box = CGRect(x: t.box.minX * 0.4 + n.box.minX * 0.6, y: t.box.minY * 0.4 + n.box.minY * 0.6,
                               width: t.box.width * 0.4 + n.box.width * 0.6, height: t.box.height * 0.4 + n.box.height * 0.6)
                t.nome = n.nome; t.certezza = n.certezza; t.letto = n.letto; t.tipo = tipo(n.nome); t.mancato = 0
                if conSegui { nuovoSegui(t) }
                presi.insert(t.id)
            } else if tracce.count < 14 {
                let t = Traccia(id: prossimo, tipo: tipo(n.nome), nome: n.nome, certezza: n.certezza, box: n.box)
                t.letto = n.letto
                prossimo += 1
                if conSegui { nuovoSegui(t) }
                tracce.append(t)
                presi.insert(t.id)
            }
        }
        for t in tracce where tipi.contains(t.tipo) && !presi.contains(t.id) { t.mancato += 1 }
        tracce.removeAll { tipi.contains($0.tipo) && $0.mancato > sparisceDopo }
    }

    private func corpi(_ g: VNImageRequestHandler) {
        guard (try? g.perform([persone, animali])) != nil else { return }
        let p = (persone.results ?? []).filter { $0.confidence > 0.5 }.map {
            (box: Self.capovolto($0.boundingBox).intersection(Self.uno), nome: "PERSONA", certezza: $0.confidence, letto: [String]())
        }
        unisci(p, tipi: [.persona], tipo: { _ in .persona }, conSegui: false, sparisceDopo: 3)
        let a = (animali.results ?? []).compactMap { o -> (box: CGRect, nome: String, certezza: Float, letto: [String])? in
            guard let l = o.labels.first, l.confidence > 0.4 else { return nil }
            let nome = l.identifier == VNAnimalIdentifier.dog.rawValue ? "CANE" : l.identifier == VNAnimalIdentifier.cat.rawValue ? "GATTO" : "ANIMALE"
            return (Self.capovolto(o.boundingBox).intersection(Self.uno), nome, l.confidence, [])
        }
        unisci(a, tipi: [.animale], tipo: { _ in .animale }, conSegui: false, sparisceDopo: 3)
    }

    /// Gli oggetti: le parti in primo piano (iOS 17), tolte persone e animali, e per ognuna il nome dalla classificazione del riquadro.
    private func oggetti(_ g: VNImageRequestHandler) {
        guard (try? g.perform([primoPiano])) != nil, let o = primoPiano.results?.first, let griglia = Maschere.griglia(o, lato: 128) else {
            unisci([], tipi: [.oggetto], tipo: { _ in .oggetto }, conSegui: true, sparisceDopo: 1)
            return
        }
        // il riquadro e la grandezza di ogni parte, dalla griglia
        var riquadri: [UInt8: (x0: Int, y0: Int, x1: Int, y1: Int, n: Int)] = [:]
        for y in 0..<griglia.h {
            for x in 0..<griglia.w {
                let e = griglia.dati[y * griglia.w + x]
                guard e != 0 else { continue }
                if let r = riquadri[e] { riquadri[e] = (min(r.x0, x), min(r.y0, y), max(r.x1, x), max(r.y1, y), r.n + 1) }
                else { riquadri[e] = (x, y, x, y, 1) }
            }
        }
        let corpi = tracce.filter { $0.tipo == .persona || $0.tipo == .animale }.map(\.box)
        var candidati: [(CGRect, CGFloat)] = []
        for (_, r) in riquadri {
            let area = CGFloat(r.n) / CGFloat(griglia.w * griglia.h)
            guard area >= 0.004, area <= 0.7 else { continue }
            let box = CGRect(x: CGFloat(r.x0) / CGFloat(griglia.w), y: CGFloat(r.y0) / CGFloat(griglia.h),
                             width: CGFloat(r.x1 - r.x0 + 1) / CGFloat(griglia.w), height: CGFloat(r.y1 - r.y0 + 1) / CGFloat(griglia.h))
            if corpi.contains(where: { Self.iou($0, box) > 0.4 || $0.contains(CGPoint(x: box.midX, y: box.midY)) }) { continue }
            candidati.append((box, area))
        }
        var trovati: [(box: CGRect, nome: String, certezza: Float, letto: [String])] = []
        for (box, _) in candidati.sorted(by: { $0.1 > $1.1 }).prefix(6) {
            classifica.regionOfInterest = Self.capovolto(box)
            guard (try? g.perform([classifica])) != nil, let tutti = classifica.results else { continue }
            let ris = tutti.sorted { $0.confidence > $1.confidence }
            guard let primo = ris.first else { continue }
            let noto = ris.prefix(25).first { $0.confidence >= 0.1 && NomiOcchi.classi[$0.identifier] != nil }
            if let noto, let nome = NomiOcchi.classi[noto.identifier] { trovati.append((box, nome, noto.confidence, [])) }
            else { trovati.append((box, "OGGETTO", primo.confidence, [])) }
        }
        classifica.regionOfInterest = Self.uno
        unisci(trovati, tipi: [.oggetto], tipo: { _ in .oggetto }, conSegui: true, sparisceDopo: 1)
    }

    /// I testi: le righe lette (italiano e inglese), raggruppate in blocchi vicini (una copertina, un cartello, un'etichetta).
    private func leggi(_ g: VNImageRequestHandler) {
        guard (try? g.perform([testi])) != nil else { return }
        var righe: [(box: CGRect, testo: String, certezza: Float)] = []
        for o in testi.results ?? [] {
            guard let c = o.topCandidates(1).first, c.string.trimmingCharacters(in: .whitespaces).count >= 2 else { continue }
            righe.append((Self.capovolto(o.boundingBox).intersection(Self.uno), c.string, c.confidence))
        }
        righe.sort { $0.box.minY < $1.box.minY }
        var blocchi: [(box: CGRect, righe: [String], certezza: [Float])] = []
        for r in righe {
            if let i = blocchi.lastIndex(where: { b in
                let sopra = b.box, gap = r.box.minY - sopra.maxY, alta = max(0.005, r.box.height)
                return gap < alta * 1.2 && gap > -alta && min(sopra.maxX, r.box.maxX) > max(sopra.minX, r.box.minX)
            }) {
                blocchi[i].box = blocchi[i].box.union(r.box); blocchi[i].righe.append(r.testo); blocchi[i].certezza.append(r.certezza)
            } else {
                blocchi.append((r.box, [r.testo], [r.certezza]))
            }
        }
        let trovati = blocchi.filter { $0.righe.joined().count >= 3 }.map { b in
            (box: b.box, nome: "TESTO", certezza: b.certezza.reduce(0, +) / Float(max(1, b.certezza.count)), letto: Array(b.righe.prefix(3)))
        }
        unisci(trovati, tipi: [.testo], tipo: { _ in .testo }, conSegui: true, sparisceDopo: 1)
    }

    /// Il bersaglio con l'ologramma: sagoma (persona: maschera delle persone; animali e oggetti: primo piano; testo: il suo riquadro),
    /// lineamenti a ogni fotogramma, nuvola 3D ogni 0,7 s, distanza dalle pupille per le persone.
    private func bersaglioOlo(_ t: Traccia, _ g: VNImageRequestHandler, _ px: CVPixelBuffer, _ adesso: Date) -> BersaglioOcchi {
        if extra?.id != t.id { extra = (t.id, [], nil, nil, nil); ultimaSagoma = .distantPast; ultimaNuvola = .distantPast }
        let box = t.box
        if adesso.timeIntervalSince(ultimaSagoma) > 0.2 {
            ultimaSagoma = adesso
            var s: Sagoma?
            switch t.tipo {
            case .persona:
                if (try? g.perform([sagomePersone, visi])) != nil {
                    if let o = sagomePersone.results?.first, let gr = Maschere.griglia(o) { s = Self.migliore(gr, box: box) }
                    // la distanza: le pupille del viso dentro il riquadro (6,3 cm tra le pupille)
                    if let f = (visi.results ?? []).first(where: { box.contains(CGPoint(x: Self.capovolto($0.boundingBox).midX, y: Self.capovolto($0.boundingBox).midY)) }),
                       let lm = f.landmarks, let a = lm.leftPupil?.pointsInImage(imageSize: CGSize(width: 1, height: 1)).first,
                       let b = lm.rightPupil?.pointsInImage(imageSize: CGSize(width: 1, height: 1)).first {
                        let iw = CGFloat(CVPixelBufferGetWidth(px)), ih = CGFloat(CVPixelBufferGetHeight(px))
                        let ipd = hypot(Double((a.x - b.x) * iw), Double((a.y - b.y) * ih))
                        extra?.viso = ipd > 4 ? lastFuoco * 0.063 / ipd : nil
                    }
                }
            case .animale, .oggetto:
                if (try? g.perform([primoPiano])) != nil, let o = primoPiano.results?.first, let gr = Maschere.griglia(o) { s = Self.migliore(gr, box: box) }
            case .testo:
                s = nil
            }
            if let s, s.box.width > 0, s.box.height > 0 {
                let rel = s.contorno.map { CGPoint(x: (($0.x - box.minX) / max(box.width, 1e-6)), y: (($0.y - box.minY) / max(box.height, 1e-6))) }
                extra?.relativo = rel; extra?.sagoma = s
            } else if t.tipo == .testo || extra?.relativo.isEmpty ?? true {
                extra?.relativo = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
                extra?.sagoma = Sagoma(contorno: [], box: box, area: box.width * box.height,
                                       griglia: GrigliaMaschera(w: 2, h: 2, dati: [1, 1, 1, 1]), etichetta: 1)
            }
        }
        if adesso.timeIntervalSince(ultimaNuvola) > 0.7, var s = extra?.sagoma {
            ultimaNuvola = adesso
            if s.contorno.isEmpty { s.box = box }                 // il testo: il riquadro di adesso
            extra?.nuvola = ImmagineOlo.nuvola(px, sagoma: s)
        }
        let regione = box.insetBy(dx: -box.width * 0.03, dy: -box.height * 0.03).intersection(Self.uno)
        return BersaglioOcchi(id: t.id, sagomaRelativa: extra?.relativo ?? [], lineamenti: ImmagineOlo.lineamenti(px, regione: regione),
                              regione: regione, nuvola: extra?.nuvola, distanzaViso: extra?.viso)
    }

    /// La focale dell'ultimo fotogramma (per la distanza dalle pupille).
    private var lastFuoco: Double = 1000

    /// Dalla griglia delle istanze: quella che occupa di più il riquadro del bersaglio.
    private static func migliore(_ g: GrigliaMaschera, box: CGRect) -> Sagoma? {
        var conta: [UInt8: Int] = [:]
        let x0 = max(0, Int(box.minX * CGFloat(g.w))), x1 = min(g.w - 1, Int(box.maxX * CGFloat(g.w)))
        let y0 = max(0, Int(box.minY * CGFloat(g.h))), y1 = min(g.h - 1, Int(box.maxY * CGFloat(g.h)))
        guard x1 >= x0, y1 >= y0 else { return nil }
        for y in y0...y1 { for x in x0...x1 { let e = g.dati[y * g.w + x]; if e != 0 { conta[e, default: 0] += 1 } } }
        guard let piu = conta.max(by: { $0.value < $1.value }), piu.value >= 4 else { return nil }
        return Maschere.sagoma(g, etichetta: piu.key)
    }

    /// Il ritaglio del bersaglio dall'ultimo fotogramma, in JPEG (lato massimo `lato`): per la scheda e per CERCA.
    func ritaglio(_ box: CGRect, lato: CGFloat) -> Data? {
        lucchetto.lock(); let px = ultimo; lucchetto.unlock()
        guard let px else { return nil }
        let iw = CGFloat(CVPixelBufferGetWidth(px)), ih = CGFloat(CVPixelBufferGetHeight(px))
        let r = box.insetBy(dx: -box.width * 0.08, dy: -box.height * 0.08).intersection(Self.uno)
        guard !r.isNull, r.width > 0, r.height > 0 else { return nil }
        let rett = CGRect(x: r.minX * iw, y: (1 - r.maxY) * ih, width: r.width * iw, height: r.height * ih)   // CoreImage: origine in basso
        let s = min(1, lato / max(rett.width, rett.height))
        let img = CIImage(cvPixelBuffer: px).cropped(to: rett).transformed(by: CGAffineTransform(scaleX: s, y: s))
        guard let cg = contesto.createCGImage(img, from: img.extent) else { return nil }
        let dati = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(dati as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return dati as Data
    }
}

// MARK: - Lo stato sullo schermo (bersaglio, conti, dettagli dal cervello)

/// Il dettaglio del cervello sul bersaglio: il nome preciso («Welsh Corgi Pembroke»), le misure stimate e la dimensione maggiore
/// in centimetri (con la focale e il riquadro dà la distanza, che cambia mentre ci si avvicina).
struct DettaglioOcchi {
    var titolo: String
    var misure: String?
    var dimensioneCm: Double?
}

@MainActor
final class StatoOcchi: ObservableObject {
    @Published var olo = false
    @Published var eti = false
    /// I conti sotto OCCHI · MANUALE (cambiano solo quando cambia un numero).
    @Published private(set) var conti: [(chiave: String, testo: String)] = []
    /// Il bersaglio di adesso: lo cerca CERCA (con o senza ologramma).
    private(set) var obiettivo: Visto?

    let visore = VisoreOcchi()
    /// L'ultimo fotogramma analizzato (lo legge l'ologramma a ogni disegno, non ridisegna la pagina).
    private(set) var vista: VistaOcchi?
    var schermo = CGSize(width: 390, height: 844)
    private(set) var nati: [Int: Date] = [:]
    private(set) var bersaglio: Int?
    private var scelto: Int?
    private(set) var agganciatoDa = Date()
    private(set) var analizzati = Set<Int>()
    private(set) var dettagli: [Int: DettaglioOcchi] = [:]
    private var richiesti = Set<Int>()
    private var inCorso = false
    private var ultimaRichiesta = Date.distantPast
    private var agganciaRichiesto = false
    /// I riquadri sullo schermo degli elementi visibili adesso (per i tocchi).
    private(set) var riquadri: [(id: Int, rett: CGRect)] = []

    init() {
        visore.esito = { [weak self] v in Task { @MainActor [weak self] in self?.ricevi(v) } }
    }

    func aggiorna() { visore.imposta(attivo: olo || eti, olo: olo, bersaglio: olo ? bersaglio : nil) }

    func aggancia() { agganciaRichiesto = true }

    /// CERCA: il mirino resta su quello cercato.
    func blocca() { if let b = bersaglio { scelto = b } }

    /// Un tocco sulla ripresa: si aggancia l'oggetto toccato (il più piccolo che contiene il dito).
    func tocco(_ p: CGPoint) {
        let colpiti = riquadri.filter { $0.rett.contains(p) }.sorted { $0.rett.width * $0.rett.height < $1.rett.width * $1.rett.height }
        guard let c = colpiti.first else { return }
        scelto = c.id; bersaglio = c.id; agganciatoDa = Date()
        aggiorna()
    }

    func spento() {
        vista = nil; riquadri = []; nati = [:]; bersaglio = nil; scelto = nil
        if !conti.isEmpty { conti = [] }
        obiettivo = nil
        aggiorna()
    }

    private func ricevi(_ v: VistaOcchi) {
        guard olo || eti else { spento(); return }
        vista = v
        let adesso = Date()
        let q = Inquadra(schermo: schermo, immagine: v.dimensione, specchio: v.frontale)
        // quello che si vede davvero sullo schermo (almeno per metà)
        var ora: [(Visto, CGRect)] = []
        for o in v.visti {
            let r = q.rett(o.box)
            let dentro = r.intersection(CGRect(x: 0, y: 0, width: q.W, height: q.H))
            let vis = dentro.isNull ? 0 : dentro.width * dentro.height / (min(r.width * r.height, q.W * q.H * 0.6) + 1)
            guard vis >= 0.45 else { nati[o.id] = nil; continue }
            ora.append((o, r))
        }
        var nuovi = 0
        for (o, _) in ora where nati[o.id] == nil { nati[o.id] = adesso.addingTimeInterval(Double(nuovi) * 0.09); nuovi += 1 }
        let presenti = Set(ora.map { $0.0.id })
        nati = nati.filter { presenti.contains($0.key) }
        riquadri = ora.map { ($0.0.id, $0.1) }
        // il bersaglio: quello toccato, altrimenti il più vicino al centro (con un po' di isteresi)
        if agganciaRichiesto {
            agganciaRichiesto = false
            let centro = ora.filter { $0.0.tipo != .testo }.min {
                hypot($0.1.midX - q.W / 2, $0.1.midY - q.H / 2) < hypot($1.1.midX - q.W / 2, $1.1.midY - q.H / 2)
            }
            if let c = centro { scelto = c.0.id; bersaglio = c.0.id; agganciatoDa = adesso }
        }
        if let s = scelto, !presenti.contains(s) { scelto = nil }
        if scelto == nil {
            func dist(_ o: (Visto, CGRect)) -> CGFloat {
                let centro: CGFloat = hypot(o.1.midX - q.W / 2, o.1.midY - q.H * 0.45) / q.W
                let troppo: CGFloat = max(0, o.1.width * o.1.height / (q.W * q.H) - 0.45)    // chi riempie mezzo schermo è uno sfondo
                let testo: CGFloat = o.0.tipo == .testo ? 0.25 : 0
                return centro + 0.4 * troppo - testo
            }
            let best = ora.filter { $0.1.width > 40 * q.k }.min { dist($0) < dist($1) }
            let cur = ora.first { $0.0.id == bersaglio }
            if let best, cur == nil || dist(best) < dist(cur!) * 0.7 {
                if best.0.id != bersaglio { bersaglio = best.0.id; agganciatoDa = adesso }
            } else if cur == nil { bersaglio = nil }
        }
        let t = ora.first { $0.0.id == bersaglio }?.0
        obiettivo = t
        if let t, olo, adesso.timeIntervalSince(agganciatoDa) > 1.3 { analizzati.insert(t.id) }
        // i conti, come le righe dei sistemi all'avvio
        var p = 0, a = 0, o = 0, s = 0
        for (x, _) in ora {
            switch x.tipo {
            case .persona: p += 1
            case .animale: a += 1
            case .oggetto: o += 1
            case .testo: s += 1
            }
        }
        func riga(_ n: Int, _ uno: String, _ tanti: String) -> String { "\(n) \(n == 1 ? uno : tanti)" }
        var c: [(chiave: String, testo: String)] = []
        if p > 0 { c.append(("persone", riga(p, "PERSONA", "PERSONE"))) }
        if a > 0 { c.append(("animali", riga(a, "ANIMALE", "ANIMALI"))) }
        if o > 0 { c.append(("oggetti", riga(o, "OGGETTO", "OGGETTI"))) }
        if s > 0 { c.append(("testo", riga(s, "TESTO", "TESTI"))) }
        if c.map(\.testo) != conti.map(\.testo) { conti = c }
        aggiorna()
        chiediDettaglio(t, adesso: adesso)
    }

    /// Il nome preciso dal cervello (una volta per bersaglio, mai per le persone): il ritaglio va al cervello, che lo guarda.
    private func chiediDettaglio(_ t: Visto?, adesso: Date) {
        guard olo, let t, t.tipo != .persona, dettagli[t.id] == nil, !richiesti.contains(t.id), !inCorso,
              adesso.timeIntervalSince(agganciatoDa) > 0.4, adesso.timeIntervalSince(ultimaRichiesta) > 2 else { return }
        inCorso = true
        richiesti.insert(t.id)
        ultimaRichiesta = adesso
        let visore = self.visore, box = t.box, nome = t.nome, letto = t.letto, id = t.id
        Task {
            let foto = await Task.detached(priority: .utility) { visore.ritaglio(box, lato: 512) }.value
            var d: DettaglioOcchi?
            if let foto { d = await CervelloOcchi.dettaglio(cosa: nome, immagine: foto, letto: letto) }
            self.inCorso = false
            self.dettagli[id] = d ?? DettaglioOcchi(titolo: "", misure: nil, dimensioneCm: nil)   // fallito: niente nome, non si riprova
        }
    }

    /// Il titolo della scheda: dal cervello; la persona davanti alla frontale (la più grande) è lei.
    func titolo(_ o: Visto) -> String? {
        if o.tipo == .persona {
            guard let v = vista, v.frontale else { return "" }
            let piuGrande = v.visti.filter { $0.tipo == .persona }.max { $0.box.width * $0.box.height < $1.box.width * $1.box.height }
            return piuGrande?.id == o.id ? "Persona · lei, Sir" : ""
        }
        return dettagli[o.id]?.titolo
    }

    /// DISTANZA e MISURE della scheda: la persona dalle pupille; il resto dalla dimensione stimata dal cervello e dal riquadro.
    func misure(_ o: Visto) -> (distanza: String, misure: String) {
        guard let v = vista else { return ("—", "—") }
        func metri(_ d: Double) -> String { "≈ " + (d < 10 ? DisegnoOlo.nf(d, 1) : "\(Int(d.rounded()))") + " m" }
        if o.tipo == .persona {
            return (v.bersaglio?.id == o.id ? (v.bersaglio?.distanzaViso.map(metri) ?? "—") : "—", "—")
        }
        guard let d = dettagli[o.id] else { return ("—", "—") }
        var distanza = "—"
        if let cm = d.dimensioneCm, cm > 0 {
            let lato = max(o.box.width * v.dimensione.width, o.box.height * v.dimensione.height)
            if lato > 4 { distanza = metri(v.fuoco * cm / 100 / Double(lato)) }
        }
        return (distanza, d.misure ?? "—")
    }
}

// MARK: - Il cervello: il nome preciso e la ricerca sul web

enum CervelloOcchi {
    /// { occhi_dettaglio: { cosa, immagine, letto } } → { titolo, misure, dimensione_cm }
    static func dettaglio(cosa: String, immagine: Data, letto: [String]) async -> DettaglioOcchi? {
        let corpo: [String: Any] = ["occhi_dettaglio": ["cosa": cosa, "immagine": immagine.base64EncodedString(), "letto": letto]]
        guard let o = await VistaVitals.chiama(corpo, attesa: 20), let titolo = o["titolo"] as? String else { return nil }
        return DettaglioOcchi(titolo: titolo, misure: (o["misure"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                              dimensioneCm: (o["dimensione_cm"] as? NSNumber)?.doubleValue)
    }

    struct Fonte: Identifiable { let id = UUID(); let titolo: String; let dominio: String; let url: URL? }
    enum Esito { case trovato(String, [Fonte]), persona, errore }

    /// { occhi_cerca: { nome, cosa, immagine } } → { testo, fonti: [{ titolo, dominio, url }] } oppure { rifiuto: true }.
    static func cerca(nome: String, cosa: String, immagine: Data?) async -> Esito {
        var dentro: [String: Any] = ["nome": nome, "cosa": cosa]
        if let immagine { dentro["immagine"] = immagine.base64EncodedString() }
        guard let o = await VistaVitals.chiama(["occhi_cerca": dentro], attesa: 50) else { return .errore }
        if o["rifiuto"] as? Bool == true { return .persona }
        guard let testo = o["testo"] as? String, !testo.isEmpty else { return .errore }
        let fonti = (o["fonti"] as? [[String: Any]] ?? []).prefix(3).map {
            Fonte(titolo: $0["titolo"] as? String ?? "", dominio: ($0["dominio"] as? String ?? "RICERCA WEB").uppercased(),
                  url: ($0["url"] as? String).flatMap(URL.init(string:)))
        }
        return .trovato(testo, Array(fonti))
    }
}

// MARK: - Il disegno sopra la ripresa (mirini, nomi, ologramma, scheda, freccia della GUIDA)

struct RiconoscimentoHUD: View {
    @ObservedObject var stato: StatoOcchi
    /// Gli Occhi manuali: la vignetta e il riconoscimento (negli altri modi solo la freccia della guida).
    let manuale: Bool
    /// I pezzi dell'interfaccia sopra la ripresa (coordinate dello schermo): i nomi piccoli non ci vanno mai sopra.
    let riservati: [CGRect]
    let guida: GuidaCondivisa.Stato?
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: Occhi dietro (MARK XI): il disegno si ferma

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: dietro)) { ctx in    // 4 nov: a 120 Hz come tutta l'app (prima 60)
            Canvas { gc, size in
                let adesso = ctx.date
                let t = adesso.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                let k = min(size.width, size.height) / 390
                if manuale { DisegnoOlo.vignetta(gc, W: size.width, H: size.height, interno: 0.4, alfa: 0.5) }
                if let guida { freccia(gc, size, k: k, t: t, g: guida) }
                guard manuale, stato.olo || stato.eti, let v = stato.vista else { return }
                let q = Inquadra(schermo: size, immagine: v.dimensione, specchio: v.frontale)
                disegna(gc, q, v, adesso: adesso, t: t)
            }
        }
    }

    private func disegna(_ gc: GraphicsContext, _ q: Inquadra, _ v: VistaOcchi, adesso: Date, t: Double) {
        let k = q.k
        let ora: [(Visto, CGRect)] = v.visti.compactMap { o in
            guard stato.nati[o.id] != nil else { return nil }
            return (o, q.rett(o.box))
        }
        let T = ora.first { $0.0.id == stato.bersaglio }
        var occupati: [CGRect] = riservati
        if let T, stato.olo { occupati.append(SchedaOcchi.posto(q, k: k, T.1)) }
        func libero(_ r: CGRect) -> Bool { !occupati.contains { $0.intersects(r) } }
        // i mirini ad angoli e i nomi piccoli (con ETICHETTE)
        if stato.eti {
            for (o, r) in ora {
                let nato = stato.nati[o.id] ?? adesso
                let a: Double = min(1, max(0, adesso.timeIntervalSince(nato) / 0.38))
                let e: CGFloat = 1 + CGFloat(1 - a) * 0.35                  // entra un po' più grande e si stringe sul soggetto
                let col = o.tipo == .persona ? TintaOlo.ambra : TintaOlo.ciano, sel = o.id == stato.bersaglio
                let hw = r.width / 2 * e, hh = r.height / 2 * e, L = min(hw, hh) * 0.32
                var c = gc
                c.opacity = a
                var mirino = Path()
                for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] as [(CGFloat, CGFloat)] {
                    let px = r.midX + sx * hw, py = r.midY + sy * hh
                    mirino.move(to: CGPoint(x: px - sx * L, y: py)); mirino.addLine(to: CGPoint(x: px, y: py)); mirino.addLine(to: CGPoint(x: px, y: py - sy * L))
                }
                c.stroke(mirino, with: .color(col.opacity(sel ? 1 : 0.85)), lineWidth: (sel ? 2.4 : 1.6) * k)
                guard !sel || !stato.olo else { continue }
                let testo = c.resolve(Text("\(o.nome) \(Int((o.certezza * 100).rounded()))%").font(DisegnoOlo.mono(10 * k, .bold)).foregroundStyle(Color.white))
                let w = testo.measure(in: CGSize(width: 10_000, height: 100)).width + 12 * k
                let tx = min(max(4 * k, r.minX), q.W - w - 4 * k)
                let prove = [r.minY - 18 * k, r.minY + 4 * k, r.maxY + 4 * k].map { min(max(4 * k, $0), q.H - 19 * k) }
                guard let ty = prove.first(where: { libero(CGRect(x: tx, y: $0, width: w, height: 15 * k)) }) else { continue }   // nessun posto: il mirino basta
                occupati.append(CGRect(x: tx, y: ty, width: w, height: 15 * k))
                c.fill(Path(CGRect(x: tx, y: ty, width: w, height: 15 * k)), with: .color(TintaOlo.fondo.opacity(0.7)))
                c.fill(Path(CGRect(x: tx, y: ty, width: 2 * k, height: 15 * k)), with: .color(col))
                c.draw(testo, at: CGPoint(x: tx + 6 * k, y: ty + 7.8 * k), anchor: .leading)
            }
        }
        // il bersaglio: la sagoma olografica sul soggetto e la scheda con il modello 3D
        guard stato.olo, let T else { return }
        let (o, r) = T
        let da = adesso.timeIntervalSince(stato.agganciatoDa), a = min(1, max(0, da / 0.5))
        let col = o.tipo == .persona ? TintaOlo.ambra : TintaOlo.ciano
        if let b = v.bersaglio, b.id == o.id, b.sagomaRelativa.count >= 3 {
            let punti = b.sagomaRelativa.map { CGPoint(x: o.box.minX + $0.x * o.box.width, y: o.box.minY + $0.y * o.box.height) }
            let sagoma = q.percorso(punti)
            DisegnoOlo.sagomaLaser(gc, sagoma, t: t, k: k, a: a, col: col)
            if let li = b.lineamenti { DisegnoOlo.lineamenti(gc, immagine: li, in: q.rett(b.regione), clip: sagoma, specchio: q.specchio, a: a) }
        }
        do {                                                         // il reticolo che gira al centro
            var c = gc
            c.translateBy(x: r.midX, y: r.midY)
            c.rotate(by: .radians(t * 0.9))
            for j in 0..<3 {
                var arco = Path()
                arco.addArc(center: .zero, radius: 13 * k, startAngle: .radians(Double(j) * 2.09), endAngle: .radians(Double(j) * 2.09 + 1.4), clockwise: false)
                c.stroke(arco, with: .color(Color.white.opacity(0.8 * a)), lineWidth: 1.2 * k)
            }
        }
        let pronto = (stato.analizzati.contains(o.id) ? max(da, 1.31) : da) > 1.3 && stato.titolo(o) != nil
        let m = stato.misure(o)
        SchedaOcchi.disegna(gc, q, k: k, t: t, T: o, rett: r, da: stato.analizzati.contains(o.id) ? max(da, 1.31) : da, pronto: pronto,
                            titolo: stato.titolo(o) ?? "", distanza: m.distanza, misure: m.misure,
                            nuvola: v.bersaglio?.id == o.id ? v.bersaglio?.nuvola : nil, col: col, specchio: v.frontale)
    }

    /// La freccia della GUIDA (SATELLITE) in basso, sul pavimento, verso la prossima svolta, con i metri.
    private func freccia(_ gc: GraphicsContext, _ size: CGSize, k: CGFloat, t: Double, g: GuidaCondivisa.Stato) {
        let W = size.width, H = size.height
        let giro: CGFloat = g.svolta == .destra ? 1 : g.svolta == .sinistra ? -1 : 0, cx = W / 2, base = H - 250 * k
        for n in 0..<5 {
            let f = ((t * 1.4 - Double(n) * 0.22).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            let u = CGFloat(n) / 5, y = base - u * 120 * k, sx = 1 - u * 0.55, ox = giro * u * u * 70 * k
            var c = gc
            c.opacity = 0.25 + 0.7 * pow(1 - f, 2)
            var p = Path()
            p.move(to: CGPoint(x: cx + ox - 34 * k * sx, y: y + 16 * k * sx)); p.addLine(to: CGPoint(x: cx + ox, y: y)); p.addLine(to: CGPoint(x: cx + ox + 34 * k * sx, y: y + 16 * k * sx))
            c.stroke(p, with: .color(TintaOlo.ciano), style: StrokeStyle(lineWidth: max(2, 7 * k * sx), lineCap: .round, lineJoin: .round))
        }
        let metri = g.svolta == .arrivo ? g.metriArrivo : g.metriSvolta
        let m = metri < 1000 ? "\(Int(metri.rounded())) m" : DisegnoOlo.nf(metri / 1000, 1) + " km"
        // come il mockup: «↱ VIA TORTONA · 80 m» (decisione 21); senza il nome della via, l'istruzione intera di Apple
        let testo = "\(g.svolta.freccia) \(g.svolta == .arrivo ? g.luogo.uppercased() : (g.via ?? g.istruzione).uppercased()) · \(m)"
        let r = gc.resolve(Text(testo).font(DisegnoOlo.mono(11 * k, .bold)).foregroundStyle(Color.white))
        let w = min(W - 16 * k, r.measure(in: CGSize(width: 10_000, height: 100)).width + 20 * k)
        let ly = base - 158 * k                                       // il cartellino sopra la freccia (sotto ci sono lo stato e i tasti)
        let scatola = Path(roundedRect: CGRect(x: cx - w / 2, y: ly, width: w, height: 22 * k), cornerRadius: 6 * k)
        gc.fill(scatola, with: .color(TintaOlo.fondo.opacity(0.78)))
        gc.stroke(scatola, with: .color(TintaOlo.ciano.opacity(0.8)), lineWidth: 1 * k)
        gc.draw(r, at: CGPoint(x: cx, y: ly + 11.5 * k), anchor: .center)
    }
}

/// La scheda del bersaglio: nome (poi il dettaglio del cervello), certezza, distanza, misure, e la sagoma in 3D che gira.
enum SchedaOcchi {
    /// Dove va la scheda (la usano anche i nomi piccoli, per non finirci sopra): sotto le righe di OCCHI · MANUALE a sinistra,
    /// in alto a destra, in basso sopra i tasti, o accanto al bersaglio; la meno sovrapposta e la più vicina.
    static func posto(_ q: Inquadra, k: CGFloat, _ T: CGRect) -> CGRect {
        let W = 150 * k, H = 186 * k, m = 10 * k, cx0 = T.midX, cy0 = T.midY
        let tutti: [CGPoint] = [CGPoint(x: m, y: 150 * k), CGPoint(x: q.W - W - m, y: 104 * k), CGPoint(x: m, y: q.H - H - 236 * k),
                                CGPoint(x: q.W - W - m, y: q.H - H - 236 * k), CGPoint(x: T.maxX + 12 * k, y: cy0 - H / 2), CGPoint(x: T.minX - 12 * k - W, y: cy0 - H / 2)]
        let posti = tutti.filter { $0.x >= m && $0.x + W <= q.W - m && $0.y >= ($0.x < q.W / 2 ? 150 : 100) * k && $0.y + H <= q.H - 230 * k }
        func copre(_ p: CGPoint) -> CGFloat {
            let sx: CGFloat = max(0, min(p.x + W, T.maxX) - max(p.x, T.minX))
            let sy: CGFloat = max(0, min(p.y + H, T.maxY) - max(p.y, T.minY))
            let lontano: CGFloat = hypot(p.x + W / 2 - cx0, p.y + H / 2 - cy0)
            return sx * sy + lontano * 20 * k
        }
        let p = (posti.isEmpty ? [CGPoint(x: q.W - W - m, y: 104 * k)] : posti).min { copre($0) < copre($1) } ?? CGPoint(x: q.W - W - m, y: 104 * k)
        return CGRect(x: p.x, y: p.y, width: W, height: H)
    }

    static func disegna(_ gc: GraphicsContext, _ q: Inquadra, k: CGFloat, t: Double, T o: Visto, rett r: CGRect, da: Double, pronto: Bool,
                        titolo: String, distanza: String, misure: String, nuvola nv: Nuvola?, col: Color, specchio: Bool) {
        let s = posto(q, k: k, r), bx = s.minX, by = s.minY, W = s.width, H = s.height
        let dx: CGFloat = bx + W / 2 < r.midX ? 1 : -1
        let a = min(1, da / 0.35)
        guard a > 0 else { return }
        var c = gc
        c.opacity = a
        let ax = max(max(0, r.minX) + 6 * k, min(min(q.W, r.maxX) - 6 * k, dx > 0 ? r.minX + 14 * k : r.maxX - 14 * k))
        let ay = max(max(0, r.minY) + 6 * k, min(min(q.H, r.maxY) - 6 * k, by + H / 2))
        let lx = dx > 0 ? bx + W : bx, ly = by + H / 2
        var filo = Path()
        filo.move(to: CGPoint(x: ax, y: ay)); filo.addLine(to: CGPoint(x: lx, y: ly))
        c.stroke(filo, with: .color(col.opacity(0.9)), lineWidth: 1.2 * k)
        c.fill(Path(ellipseIn: CGRect(x: ax - 3 * k, y: ay - 3 * k, width: 6 * k, height: 6 * k)), with: .color(col))
        let carta = Path(roundedRect: s, cornerRadius: 8 * k)
        c.fill(carta, with: .color(TintaOlo.fondoScheda.opacity(0.8)))
        c.stroke(carta, with: .color(col.opacity(0.75)), lineWidth: 1.2 * k)
        c.fill(Path(CGRect(x: bx, y: by + 8 * k, width: 2.5 * k, height: H - 16 * k)), with: .color(col))
        // in alto: l'ologramma 3D fatto dal fotogramma vero (nuvola di punti), che oscilla per mostrare il volume
        let mx = bx + W / 2, my = by + 56 * k
        if let nv {
            let scala = min(W * 0.7 / nv.w, 84 * k / nv.h)
            DisegnoOlo.nuvola(c, nv, mx: mx, my: my, scala: scala, r: sin(t * 0.8) * 0.9, k: k, col: col, specchio: specchio)
            let ys = my - 42 * k + CGFloat(t.truncatingRemainder(dividingBy: 1.8) / 1.8) * 84 * k
            c.fill(Path(CGRect(x: bx + 10 * k, y: ys, width: W - 20 * k, height: 1.5 * k)), with: .color(col.opacity(0.25)))
            c.stroke(Path(ellipseIn: CGRect(x: mx - W * 0.32, y: my + 46 * k - 6 * k, width: W * 0.64, height: 12 * k)), with: .color(col.opacity(0.3)), lineWidth: 1 * k)
        }
        // sotto: il nome e i dati; il dettaglio arriva dal cervello (ANALISI… poi il nome preciso)
        let ty = by + 108 * k
        c.draw(Text(o.nome).font(DisegnoOlo.mono(14 * k, .bold)).foregroundStyle(Color.white), at: CGPoint(x: bx + 12 * k, y: ty), anchor: .topLeading)
        let sotto = pronto ? titolo : "ANALISI" + String(repeating: ".", count: 1 + Int(t * 3) % 3)
        let corto = sotto.count > 22 ? String(sotto.prefix(21)) + "…" : sotto
        c.draw(Text(corto).font(DisegnoOlo.mono(9.5 * k, .semibold)).foregroundStyle(col), at: CGPoint(x: bx + 12 * k, y: ty + 18 * k), anchor: .topLeading)
        var righe: [(String, String)] = [("CERTEZZA", "\(Int((o.certezza * 100).rounded()))%"), ("DISTANZA", distanza), ("MISURE", misure)]
        if o.tipo == .testo && pronto { righe = [("LETTO", "")] + o.letto.map { ($0, "") } }
        for (j, (a1, b1)) in righe.enumerated() {
            let y = ty + 36 * k + CGFloat(j) * 13 * k
            if y > by + H - 12 * k { continue }
            c.draw(Text(a1).font(DisegnoOlo.mono(9 * k, .medium)).foregroundStyle(Color(red: 200 / 255, green: 240 / 255, blue: 250 / 255).opacity(0.65)),
                   at: CGPoint(x: bx + 12 * k, y: y), anchor: .topLeading)
            if !b1.isEmpty {
                c.draw(Text(b1).font(DisegnoOlo.mono(9 * k, .medium)).foregroundStyle(Color.white), at: CGPoint(x: bx + W - 12 * k, y: y), anchor: .topTrailing)
            }
        }
    }
}

// MARK: - Le righe sotto OCCHI · MANUALE (entrano come i sistemi all'avvio)

struct RigheOcchi: View {
    let righe: [(chiave: String, testo: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(righe.enumerated()), id: \.element.chiave) { j, r in
                HStack(spacing: 7) {
                    Rectangle().fill(Color.ciano).frame(width: 5, height: 5).shadow(color: Color.ciano, radius: 2)
                    Text(r.testo).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Color.ciano).shadow(color: .black.opacity(0.9), radius: 3)
                        .contentTransition(.identity)
                }
                .transition(AnyTransition.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: AnyTransition.offset(x: -6)).animation(.easeOut(duration: 0.35).delay(Double(j) * 0.09)),
                    removal: AnyTransition.identity))
            }
        }
        .frame(minHeight: 13, alignment: .topLeading)
        .padding(.top, 9)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Le tre icone sopra lo zoom: ETICHETTE, OLOGRAMMA, CERCA (disegnate come nel mockup)

nonisolated enum IconaOcchi {
    nonisolated enum Tipo: Sendable { case etichette, ologramma, cerca, aereo }

    /// Il disegno dell'icona (viewBox 24×24 del mockup) in un quadrato di `lato` punti.
    static func percorso(_ tipo: Tipo, lato: CGFloat) -> Path {
        let r = CGRect(x: 0, y: 0, width: lato, height: lato)
        let s = lato / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var path = Path()
        switch tipo {
        case .etichette:          // M3 4.5V11l9.5 9.5 8-8L11 3H4.5A1.5 1.5 0 0 0 3 4.5z + cerchio (7.5, 7.5) r1.4
            path.move(to: p(3, 4.5)); path.addLine(to: p(3, 11)); path.addLine(to: p(12.5, 20.5)); path.addLine(to: p(20.5, 12.5))
            path.addLine(to: p(11, 3)); path.addLine(to: p(4.5, 3))
            path.addQuadCurve(to: p(3, 4.5), control: p(3, 3))            // l'angolo arrotondato (A1.5 1.5)
            path.closeSubpath()
            path.addEllipse(in: CGRect(x: r.minX + 6.1 * s, y: r.minY + 6.1 * s, width: 2.8 * s, height: 2.8 * s))
        case .ologramma:          // M12 3l8 4.5v9L12 21l-8-4.5v-9z + M4 7.5l8 4.5 8-4.5M12 12v9
            path.move(to: p(12, 3)); path.addLine(to: p(20, 7.5)); path.addLine(to: p(20, 16.5)); path.addLine(to: p(12, 21))
            path.addLine(to: p(4, 16.5)); path.addLine(to: p(4, 7.5)); path.closeSubpath()
            path.move(to: p(4, 7.5)); path.addLine(to: p(12, 12)); path.addLine(to: p(20, 7.5))
            path.move(to: p(12, 12)); path.addLine(to: p(12, 21))
        case .cerca:              // cerchio (10.5,10.5) r6.5, M15.5 15.5L21 21, M4 10.5h13, i due meridiani
            path.addEllipse(in: CGRect(x: r.minX + 4 * s, y: r.minY + 4 * s, width: 13 * s, height: 13 * s))
            path.move(to: p(15.5, 15.5)); path.addLine(to: p(21, 21))
            path.move(to: p(4, 10.5)); path.addLine(to: p(17, 10.5))
            path.move(to: p(10.5, 4)); path.addCurve(to: p(10.5, 17), control1: p(8.1, 7.6), control2: p(8.1, 13.4))
            path.move(to: p(10.5, 4)); path.addCurve(to: p(10.5, 17), control1: p(12.9, 7.6), control2: p(12.9, 13.4))
        case .aereo:              // MARK X: M12 2.5c1 0 1.5 1.2 1.5 2.5v4.5l7.5 4.5v2l-7.5-2.3V18l2.5 1.8V21L12 20l-4 1v-1.2l2.5-1.8v-4.3L3 16v-2l7.5-4.5V5c0-1.3.5-2.5 1.5-2.5z
            path.move(to: p(12, 2.5)); path.addCurve(to: p(13.5, 5), control1: p(13, 2.5), control2: p(13.5, 3.7))
            path.addLine(to: p(13.5, 9.5)); path.addLine(to: p(21, 14)); path.addLine(to: p(21, 16)); path.addLine(to: p(13.5, 13.7))
            path.addLine(to: p(13.5, 18)); path.addLine(to: p(16, 19.8)); path.addLine(to: p(16, 21)); path.addLine(to: p(12, 20))
            path.addLine(to: p(8, 21)); path.addLine(to: p(8, 19.8)); path.addLine(to: p(10.5, 18)); path.addLine(to: p(10.5, 13.7))
            path.addLine(to: p(3, 16)); path.addLine(to: p(3, 14)); path.addLine(to: p(10.5, 9.5)); path.addLine(to: p(10.5, 5))
            path.addCurve(to: p(12, 2.5), control1: p(10.5, 3.7), control2: p(11, 2.5))
            path.closeSubpath()
        }
        return path
    }
}

/// Un'icona con la scritta sotto (oc-ico del mockup): accesa = cerchio pieno celeste che brilla.
struct TastoOcchi: View {
    let tipo: IconaOcchi.Tipo
    let titolo: String
    let acceso: Bool
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            VStack(spacing: 4) {
                // 8 nov (il signore: «ridurre la dimensione delle icone»): cerchio 34 (era 40), simbolo 15 (era 18), larghezza 46
                IconaOcchi.percorso(tipo, lato: 15)
                    .stroke(style: StrokeStyle(lineWidth: tipo == .aereo ? 1.5 : 1.6, lineCap: tipo == .cerca ? .round : .butt, lineJoin: .round))
                    .frame(width: 15, height: 15)
                    .foregroundStyle(acceso ? Color.fondo : Color.ciano.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(acceso ? Color.ciano : Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.ciano.opacity(0.55), lineWidth: 1))
                    .shadow(color: Color.ciano.opacity(acceso ? 0.65 : 0), radius: 7)
                Text(titolo).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
                    .foregroundStyle(acceso ? Color.ciano : Color.ciano.opacity(0.7))
            }
            .frame(width: 46)
            .animation(.easeOut(duration: 0.2), value: acceso)
        }
        .buttonStyle(StileStark())
        .accessibilityLabel(titolo.capitalized)
        .accessibilityAddTraits(acceso ? .isSelected : [])
    }
}

// MARK: - CERCA: il foglio che sale dal basso (la fotocamera resta viva sopra)

struct FoglioWebOcchi: View {
    let nome: String
    let cosa: String
    let esito: CervelloOcchi.Esito?
    /// Decisione 29: una fonte toccata si apre nel browser di JARVIS.
    var apri: (URL) -> Void = { _ in }
    let chiudi: () -> Void
    @State private var punti = 1

    var body: some View {
        // il foglio è alto quanto serve; se il testo è lungo, scorre (al massimo poco più di metà schermo)
        ViewThatFits(in: .vertical) {
            contenuto
            ScrollView { contenuto }.scrollIndicators(.hidden)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color(red: 3 / 255, green: 9 / 255, blue: 11 / 255).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.ciano.opacity(0.45), lineWidth: 1))
        .shadow(color: Color.ciano.opacity(0.2), radius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ricerca web")
    }

    private var contenuto: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEB · \(nome)").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
                    Text("«\(cosa.replacingOccurrences(of: " · ", with: " "))»").font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.5).foregroundStyle(Color.tenue)
                }
                Spacer()
                Button { Suoni.tocco(); chiudi() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ciano)
                        .frame(width: 36, height: 36).overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                }
                .accessibilityLabel("Chiudi")
            }
            switch esito {
            case nil:
                Text("CERCO" + String(repeating: ".", count: punti)).font(.system(size: 14)).foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .task {
                        while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(350)); punti = punti % 3 + 1 }
                    }
            case .trovato(let testo, let fonti)?:
                Text(testo).font(.system(size: 14)).lineSpacing(3).foregroundStyle(.white).padding(.top, 12).padding(.bottom, 10)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fonti) { f in
                        // decisione 29: la fonte con il suo indirizzo si tocca e si apre nel browser di JARVIS (stesso aspetto).
                        // Solo indirizzi web: il browser di Safari si chiude di colpo con altri tipi di indirizzo
                        if let u = f.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
                            Button { apri(u) } label: { rigaFonte(f) }
                                .buttonStyle(StileStark())
                                .accessibilityHint("Apre la pagina")
                        } else {
                            rigaFonte(f)
                        }
                    }
                }
            case .persona?:
                Text("Le persone non le cerco sul web, Sir.").font(.system(size: 14)).foregroundStyle(.white).padding(.vertical, 12)
            case .errore?:
                Text("Ricerca non riuscita, Sir: riprovi tra poco.").font(.system(size: 14)).foregroundStyle(.white).padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Una fonte: il titolo e il sito, con la riga ciano a sinistra (come il mockup).
    private func rigaFonte(_ f: CervelloOcchi.Fonte) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(f.titolo).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Text(f.dominio).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Color.ciano)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Color.ciano.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(Color.ciano).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - I comandi a voce degli Occhi (frasi esatte del mockup)

/// «Jarvis, mostra le etichette», «togli le etichette», «scansione olografica», «aggancia il bersaglio», «disattiva l'ologramma»,
/// «cerca questo sul web»: agiscono negli Occhi aperti; con gli Occhi chiusi li aprono già così (manuali).
nonisolated enum ComandoOcchi: Equatable, Sendable {
    case etichette(Bool)
    case ologramma(Bool)
    case aggancia
    case cerca
    /// MARK X · AEREO (mockup build 32): `p` è AEREO, AEREO_DA, AEREO_DOVE, AEREO_QUOTA, AEREO_COMP, AEREO_ALTRO o AEREO_OFF;
    /// `frase` è la domanda detta (va in cima al foglio del volo).
    case aereo(String, frase: String)

    /// Un aereo è agganciato negli Occhi aperti: allora valgono anche le domande corte («dove va?», «a che quota è?»).
    /// Lo tengono aggiornato gli Occhi.
    nonisolated(unsafe) static var aereoAgganciato = false

    /// Con gli Occhi chiusi, la frase quando si aprono per mandare la foto (come il mockup).
    var annuncioApertura: String? {
        switch self {
        case .aereo(let p, _): return p == "AEREO_OFF" ? nil : "Cerco l'aereo, Sir."
        default: return nil
        }
    }

    /// La risposta di JARVIS (come il mockup); CERCA risponde quando ha trovato.
    var risposta: String? {
        switch self {
        case .etichette(true): return "Etichette attive, Sir."
        case .etichette(false): return "Etichette disattivate, Sir."
        case .ologramma(true): return "Scansione olografica, Sir."
        case .ologramma(false): return "Ologramma disattivato, Sir."
        case .aggancia: return "Bersaglio agganciato, Sir."
        case .aereo("AEREO", _): return "Cerco l'aereo, Sir."
        case .cerca, .aereo: return nil
        }
    }

    /// MARK X · AEREO: la frase (già in minuscolo, senza accenti né apostrofi) → il comando. Le domande corte («dove va?»,
    /// «a che quota è?») valgono solo con un aereo agganciato negli Occhi; con la parola «aereo» o «volo» valgono sempre.
    private static func fraseAereo(_ t: String) -> String? {
        let f = " \(t) "
        func c(_ x: String) -> Bool { f.contains(" \(x) ") }
        let aereo = c("aereo") || c("aerei") || c("aereoplano") || c("volo") || c("velivolo")
        guard aereo || aereoAgganciato else { return nil }
        if aereo && (c("spegni") || c("togli") || c("basta")) { return "AEREO_OFF" }
        if c("altro") && (aereo || c("aggancia")) { return "AEREO_ALTRO" }
        if c("da dove viene") || c("da dove arriva") || c("da dove parte") || c("da dove e partito") { return "AEREO_DA" }
        if c("dove va") || c("dove sta andando") || c("dove e diretto") || c("dove atterra") { return "AEREO_DOVE" }
        if c("quota") || c("quanto e alto") || c("a che altezza") || c("quanto vola alto") { return "AEREO_QUOTA" }
        if c("compagnia") || c("di chi e") { return "AEREO_COMP" }
        // 27 ott (il signore): anche «Jarvis, target aereo» e «Jarvis, guarda l'aereo» (l'apostrofo diventa uno spazio: «guarda l aereo»)
        if aereo && (c("che") || c("quale") || c("cos e") || c("cosa e") || c("cerca") || c("trova") || c("guarda") || c("target") || c("punta") || c("inquadra") || c("aggancia")) { return "AEREO" }
        return nil
    }

    static func riconosci(_ frase: String) -> ComandoOcchi? {
        var t = frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        while let p = t.first, ["ehi", "ok", "hey", "jarvis", "giarvis", "jervis"].contains(p) { t.removeFirst() }
        let detta = frase.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^(?i)(ehi |ok |hey )?(jarvis|giarvis|jervis)[,. ]*", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
        if let p = fraseAereo(t.joined(separator: " ")) { return .aereo(p, frase: detta.prefix(1).lowercased() + detta.dropFirst()) }
        switch t.joined(separator: " ") {
        case "mostra le etichette": return .etichette(true)
        case "togli le etichette": return .etichette(false)
        case "scansione olografica": return .ologramma(true)
        case "disattiva l ologramma": return .ologramma(false)
        case "aggancia il bersaglio": return .aggancia
        case "cerca questo sul web": return .cerca
        default: return nil
        }
    }
}
#endif
