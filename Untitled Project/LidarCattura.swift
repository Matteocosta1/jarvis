#if os(iOS)
import SwiftUI
import UIKit
import ARKit
import SceneKit
import RealityKit
import Metal                // le maglie del LiDAR: MTLBuffer.contents() e MTLVertexFormat
import simd
import CoreVideo
import CoreImage
import ImageIO
import AVFoundation         // Texture: il permesso della fotocamera (AVCaptureDevice)

// MARK: - LiDAR 23 · le catture dei modi nuovi (la stanza resta RoomPlan, in Lidar.swift)
// Esterno, Oggetto, Misura: ARKit con la ricostruzione della scena (maglia del LiDAR) o i piani; Postura: ARKit col corpo
// (ARBodyTrackingConfiguration); Texture (gemello digitale): Object Capture di Apple (ObjectCaptureSession + PhotogrammetrySession).
// Sopra la fotocamera: la maglia ciano mentre si forma, i piani misurati, lo scheletro. I numeri vanno nell'HUD del mockup.

/// Quello che la cattura manda alla schermata mentre lavora: i tre numeri dell'HUD e se si può già toccare «Fine».
nonisolated struct StatoScansione: Equatable, Sendable {
    var hud: [String] = ["—", "—", "—"]
    var pronto = false
    /// Cosa sta succedendo, al posto dell'istruzione del modo («CERCO LA PERSONA…», «INQUADRI ANCHE I PIEDI»…). nil: l'istruzione.
    var testo: String? = nil
}

/// Chi può fare cosa su questo iPhone (iPhone 15 Pro: tutto).
enum SupportoModi {
    static var maglia: Bool { !ProcessInfo.processInfo.isiOSAppOnMac && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }
    static var profondita: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }
    static var corpo: Bool { !ProcessInfo.processInfo.isiOSAppOnMac && ARBodyTrackingConfiguration.isSupported }
    static var piani: Bool { !ProcessInfo.processInfo.isiOSAppOnMac && ARWorldTrackingConfiguration.isSupported }
    static var oggettoFoto: Bool { !ProcessInfo.processInfo.isiOSAppOnMac && ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported }

    static func disponibile(_ m: ModoLidar) -> Bool {
        switch m {
        case .stanza, .evento: return LidarSupporto.disponibile
        case .esterno, .oggetto: return maglia
        case .misura: return piani
        case .corpo: return corpo
        case .statua: return oggettoFoto
        }
    }
    /// La frase quando il modo non c'è su questo dispositivo.
    static func avviso(_ m: ModoLidar) -> String {
        m == .corpo ? "SERVE UN IPHONE CHE SEGUA IL CORPO (A12 O PIÙ)" : "SERVE UN IPHONE CON IL LIDAR"
    }
}

/// La foto per «guarda» mentre LiDAR scansiona: l'immagine della fotocamera già accesa, dritta e in JPEG (lato lungo 1600 px).
enum LidarFoto {
    static func jpeg(_ frame: ARFrame) -> Data? {
        var immagine = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let lato = max(immagine.extent.width, immagine.extent.height)
        if lato > 1600 { immagine = immagine.transformed(by: CGAffineTransform(scaleX: 1600 / lato, y: 1600 / lato)) }
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CIContext().jpegRepresentation(of: immagine, colorSpace: spazio,
                                              options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
    }
}

// MARK: - La vista AR (Esterno, Oggetto, Misura, Postura)

struct CatturaAR: UIViewRepresentable {
    let modo: ModoLidar
    @Binding var ferma: Bool
    let aggiorna: (StatoScansione) -> Void
    let finita: (RisultatoModo) -> Void
    let errore: (String) -> Void

    func makeCoordinator() -> RegistaAR { RegistaAR(modo: modo, aggiorna: aggiorna, finita: finita, errore: errore) }

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.automaticallyUpdatesLighting = false
        v.rendersContinuously = true
        v.scene = SCNScene()
        v.session.delegate = context.coordinator
        context.coordinator.vista = v
        context.coordinator.avvia()
        return v
    }

    func updateUIView(_ v: ARSCNView, context: Context) {
        if ferma && !context.coordinator.fermata { context.coordinator.concludi() }
    }

    static func dismantleUIView(_ v: ARSCNView, coordinator: RegistaAR) {
        coordinator.annulla()
        v.session.pause()
    }
}

/// Il regista della sessione AR: riceve i fotogrammi (sul main, dove ARKit li consegna), passa il lavoro pesante a una coda sua.
final class RegistaAR: NSObject, ARSessionDelegate {
    let modo: ModoLidar
    let aggiorna: (StatoScansione) -> Void
    let finita: (RisultatoModo) -> Void
    let errore: (String) -> Void
    weak var vista: ARSCNView?
    var fermata = false
    private var annullata = false
    private var stato = StatoScansione() { didSet { if stato != oldValue { aggiorna(stato) } } }

    // la maglia ciano sopra la fotocamera
    private var nodiMaglia: [UUID: SCNNode] = [:]
    private let materialeMaglia: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.31, green: 0.89, blue: 1, alpha: 1)
        m.fillMode = .lines
        m.transparency = 0.45
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }()
    private let disegni = SCNNode()                          // piani, linee, scheletro: rifatti a ogni aggiornamento
    private var ultimoLavoro: TimeInterval = 0
    private var ultimoColore: TimeInterval = 0
    private var ultimoDisegno: TimeInterval = 0
    private var ultimaMira: TimeInterval = 0
    private let calcolo = CalcoloLidar()

    // Esterno: il percorso camminato
    private var percorso: [SIMD2<Double>] = []
    private var lunghezza: Double = 0
    // Oggetto: il punto mirato e il giro intorno
    private var seme: SIMD3<Float>?
    private var appoggio: Float?
    private var settori = Set<Int>()
    private var ultimeMisure: [SIMD3<Float>] = []
    // Misura: il piano della parete
    private var parete: UUID?
    private var misura = (largo: Float(0), alto: Float(0), distanza: Float(0))
    private var storiaLargo: [(TimeInterval, Float)] = []
    // Postura: i campioni dello scheletro
    private var campioni: [[String: SIMD3<Float>]] = []
    private var inizioCorpo: TimeInterval?
    private var pavimentoCorpo: Float?
    private var primoFotogramma: TimeInterval?
    private var ultimoCorpoVisto: TimeInterval?             // l'ultima volta che ARKit ha seguito davvero una persona

    init(modo: ModoLidar, aggiorna: @escaping (StatoScansione) -> Void, finita: @escaping (RisultatoModo) -> Void, errore: @escaping (String) -> Void) {
        self.modo = modo; self.aggiorna = aggiorna; self.finita = finita; self.errore = errore
        super.init()
    }

    /// Gli avvisi passano dal main un attimo dopo: mai mentre SwiftUI sta disegnando.
    private func segnala(_ testo: String) { Task { @MainActor in if !self.annullata { self.errore(testo) } } }

    func avvia() {
        guard let v = vista else { return }
        v.scene.rootNode.addChildNode(disegni)
        OcchiLidar.scatta = { [weak v] in v?.session.currentFrame.flatMap { LidarFoto.jpeg($0) } }   // «guarda» usa questa fotocamera
        let opzioni: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
        switch modo {
        case .corpo:
            guard SupportoModi.corpo else { segnala(SupportoModi.avviso(.corpo)); return }
            let c = ARBodyTrackingConfiguration()
            c.automaticSkeletonScaleEstimationEnabled = true           // l'altezza la stima ARKit (col LiDAR, sul 15 Pro)
            c.planeDetection = [.horizontal]                           // il pavimento, per misurare da terra
            v.session.run(c, options: opzioni)
        case .misura:
            guard SupportoModi.piani else { segnala(SupportoModi.avviso(.misura)); return }
            let c = ARWorldTrackingConfiguration()
            c.planeDetection = [.vertical, .horizontal]
            if SupportoModi.maglia { c.sceneReconstruction = .mesh }   // col LiDAR i piani si trovano subito e più precisi
            v.session.run(c, options: opzioni)
        default:                                                       // Esterno, Oggetto: la maglia del LiDAR
            guard SupportoModi.maglia else { segnala(SupportoModi.avviso(modo)); return }
            let c = ARWorldTrackingConfiguration()
            c.sceneReconstruction = .mesh
            c.planeDetection = [.horizontal]
            if SupportoModi.profondita { c.frameSemantics.insert(.sceneDepth) }
            v.session.run(c, options: opzioni)
        }
    }

    func annulla() { annullata = true; fermata = true; calcolo.annulla(); OcchiLidar.scatta = nil }

    // MARK: ARSessionDelegate (ARKit consegna sul main: niente delegateQueue)

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated { self.fotogramma(frame) }
    }
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        MainActor.assumeIsolated { self.ancore(anchors) }
    }
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        MainActor.assumeIsolated { self.ancore(anchors) }
    }
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        MainActor.assumeIsolated { for a in anchors { self.nodiMaglia.removeValue(forKey: a.identifier)?.removeFromParentNode() } }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let testo = error.localizedDescription.uppercased()
        MainActor.assumeIsolated { if !self.annullata { self.errore("SCANSIONE INTERROTTA · \(testo)") } }
    }

    // MARK: Ancore: la maglia ciano e il corpo

    private func ancore(_ anchors: [ARAnchor]) {
        guard !fermata, let v = vista else { return }
        for a in anchors {
            if let m = a as? ARMeshAnchor, modo == .esterno || modo == .oggetto {
                let g = m.geometry
                let src = SCNGeometrySource(buffer: g.vertices.buffer, vertexFormat: g.vertices.format, semantic: .vertex,
                                            vertexCount: g.vertices.count, dataOffset: g.vertices.offset, dataStride: g.vertices.stride)
                let el = SCNGeometryElement(buffer: g.faces.buffer, primitiveType: .triangles, primitiveCount: g.faces.count, bytesPerIndex: g.faces.bytesPerIndex)
                let geo = SCNGeometry(sources: [src], elements: [el])
                geo.materials = [materialeMaglia]
                let n: SCNNode
                if let x = nodiMaglia[m.identifier] { n = x } else { n = SCNNode(); v.scene.rootNode.addChildNode(n); nodiMaglia[m.identifier] = n }
                n.geometry = geo
                n.simdTransform = m.transform
            } else if let b = a as? ARBodyAnchor, modo == .corpo {
                corpo(b)
            }
        }
    }

    // MARK: Fotogrammi

    private func fotogramma(_ f: ARFrame) {
        guard !fermata else { return }
        let t = f.timestamp
        let cam = f.camera.transform.columns.3
        let posizione = SIMD3<Float>(cam.x, cam.y, cam.z)
        switch modo {
        case .esterno:
            let p = SIMD2(Double(posizione.x), Double(posizione.z))
            if let u = percorso.last { if simd_distance(u, p) >= 0.3 { lunghezza += simd_distance(u, p); percorso.append(p) } } else { percorso.append(p) }
            if t - ultimoLavoro > 1, !calcolo.occupato {
                ultimoLavoro = t
                let maglie = f.anchors.compactMap { $0 as? ARMeshAnchor }
                let giro = percorso, chiuso = giroChiuso
                calcolo.terreno(maglie, percorso: giro, chiuso: chiuso) { [weak self] m in
                    guard let self, !self.fermata else { return }
                    self.stato = StatoScansione(hud: [m.area > 0 ? LidarFormato.n(m.area) : "—", m.perimetro > 0 ? LidarFormato.m(m.perimetro) : "—",
                                                      m.dislivello != nil ? LidarFormato.cm(m.dislivello ?? 0) : "—"], pronto: chiuso)
                }
            }
            if t - ultimoColore > 0.5 { ultimoColore = t; calcolo.colora(f, terreno: true) }
        case .oggetto:
            if t - ultimaMira > 0.3 { ultimaMira = t; mira(f) }
            if let s = seme {                                                      // il giro intorno all'oggetto, a settori di 30°
                let d = SIMD2(posizione.x - s.x, posizione.z - s.z)
                if simd_length(d) > 0.2 { settori.insert(Int(((atan2(d.y, d.x) + .pi) / (2 * .pi) * 12).rounded(.down)) % 12) }
            }
            if t - ultimoLavoro > 0.6, !calcolo.occupato, let s = seme {
                ultimoLavoro = t
                let maglie = f.anchors.compactMap { $0 as? ARMeshAnchor }
                calcolo.oggetto(maglie, seme: s, appoggio: appoggio ?? (s.y - 0.5)) { [weak self] o in
                    guard let self, !self.fermata, let o else { return }
                    self.ultimeMisure.append(SIMD3(o.largo, o.profondo, o.alto)); if self.ultimeMisure.count > 3 { self.ultimeMisure.removeFirst() }
                    let fermo = self.ultimeMisure.count == 3 && self.ultimeMisure.allSatisfy { simd_distance($0, o.dimensioni) < 0.015 }
                    self.stato = StatoScansione(hud: [LidarFormato.cm(Double(o.largo)), LidarFormato.cm(Double(o.profondo)), LidarFormato.cm(Double(o.alto))],
                                                pronto: fermo && self.settori.count >= 6)
                }
            }
            if t - ultimoColore > 0.5 { ultimoColore = t; calcolo.colora(f, terreno: false) }
        case .misura:
            if t - ultimoLavoro > 0.1 { ultimoLavoro = t; misuraParete(f, posizione) }
        case .corpo:
            // nessuna persona seguita da più di 1 s (passato il primo secondo e mezzo): lo si dice, invece di restare muti
            let t0 = primoFotogramma ?? t
            primoFotogramma = t0
            let persa = ultimoCorpoVisto.map { t - $0 > 1 } ?? true
            if t - t0 > 1.5, persa {
                if !disegni.childNodes.isEmpty { disegni.childNodes.forEach { $0.removeFromParentNode() } }   // niente scheletro rimasto appeso
                avvisaCorpo("NON VEDO LA PERSONA · LA INQUADRI DALLA TESTA AI PIEDI")
            }
        default: break
        }
    }

    /// Postura: la riga di stato dice cosa manca; i numeri dell'HUD restano quelli presi finora.
    private func avvisaCorpo(_ testo: String) {
        var s = stato
        s.testo = testo
        stato = s
    }

    /// Esterno: il giro è chiuso quando si torna a meno di 1,5 m dal punto di partenza dopo almeno 6 m.
    private var giroChiuso: Bool {
        guard let a = percorso.first, let b = percorso.last, lunghezza > 6 else { return false }
        return simd_distance(a, b) < 1.5
    }

    /// Oggetto: il punto al centro dello schermo, e il piano su cui poggia (il piano orizzontale più alto sotto di lui).
    private func mira(_ f: ARFrame) {
        guard let v = vista, v.bounds.width > 0 else { return }
        let centro = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        guard let q = v.raycastQuery(from: centro, allowing: .estimatedPlane, alignment: .any),
              let r = v.session.raycast(q).first else { return }
        let p = r.worldTransform.columns.3
        let punto = SIMD3<Float>(p.x, p.y, p.z)
        let piani = f.anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }
        let sotto = piani.map { a -> Float in (a.transform * SIMD4<Float>(a.center.x, a.center.y, a.center.z, 1)).y }
            .filter { $0 < punto.y - 0.02 && $0 > punto.y - 2.5 }
        // il punto mirato vale solo se sta sopra un appoggio (è l'oggetto, non il pavimento)
        if let y = sotto.max() { seme = punto; appoggio = y }
        else if seme == nil, let pav = piani.map({ ($0.transform * SIMD4<Float>($0.center.x, $0.center.y, $0.center.z, 1)).y }).min(), punto.y > pav + 0.03 {
            seme = punto; appoggio = pav
        }
    }

    /// Misura: la parete mirata (il piano verticale al centro dello schermo) e quanto è larga e alta finora.
    private func misuraParete(_ f: ARFrame, _ cam: SIMD3<Float>) {
        guard let v = vista, v.bounds.width > 0 else { return }
        let centro = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        var piano: ARPlaneAnchor?
        var colpo: SIMD3<Float>?
        if let q = v.raycastQuery(from: centro, allowing: .existingPlaneGeometry, alignment: .vertical),
           let r = v.session.raycast(q).first, let a = r.anchor as? ARPlaneAnchor {
            piano = a; let p = r.worldTransform.columns.3; colpo = SIMD3(p.x, p.y, p.z)
        } else if let id = parete {
            piano = f.anchors.first { $0.identifier == id } as? ARPlaneAnchor
        }
        guard let a = piano else { return }
        if parete != a.identifier { parete = a.identifier; storiaLargo = [] }
        let e = a.planeExtent
        // quale lato del piano è in verticale: l'asse x (girato di rotationOnYAxis) o l'asse z
        let ang = e.rotationOnYAxis
        let wx = a.transform * SIMD4<Float>(cos(ang), 0, -sin(ang), 0), wz = a.transform * SIMD4<Float>(sin(ang), 0, cos(ang), 0)
        let xVerticale = abs(wx.y) > abs(wz.y)
        let largo = xVerticale ? e.height : e.width, alto = xVerticale ? e.width : e.height
        misura.largo = largo; misura.alto = alto
        if let colpo { misura.distanza = simd_distance(colpo, cam) }
        storiaLargo.append((f.timestamp, largo)); storiaLargo.removeAll { f.timestamp - $0.0 > 1.5 }
        let larghezze = storiaLargo.map { $0.1 }
        let fermo = storiaLargo.count > 5 && (larghezze.max() ?? 0) - (larghezze.min() ?? 0) < 0.01 && largo >= 0.3
        stato = StatoScansione(hud: [LidarFormato.m(Double(largo), 2), LidarFormato.m(Double(alto), 2),
                                     misura.distanza > 0 && misura.distanza <= 5 ? "±1 cm" : "—"], pronto: fermo)
        if f.timestamp - ultimoDisegno > 0.2 { ultimoDisegno = f.timestamp; disegnaParete(a, xVerticale: xVerticale) }
    }

    /// Sopra l'immagine: il contorno della parete misurata e la misura in larghezza, in arancio, a metà altezza.
    private func disegnaParete(_ a: ARPlaneAnchor, xVerticale: Bool) {
        disegni.childNodes.forEach { $0.removeFromParentNode() }
        let e = a.planeExtent, w = e.width, h = e.height, largo = xVerticale ? h : w
        let gruppo = SCNNode()
        gruppo.simdTransform = a.transform
        let ruota = SCNNode()                                                    // il centro e la rotazione dell'estensione (iOS 16)
        ruota.simdPosition = a.center
        ruota.simdEulerAngles = SIMD3(0, e.rotationOnYAxis, 0)
        gruppo.addChildNode(ruota)
        func linea(_ p: [SIMD3<Float>], _ c: UIColor, _ alfa: CGFloat) {
            let fonte = SCNGeometrySource(vertices: p.map { SCNVector3($0.x, $0.y, $0.z) })
            let g = SCNGeometry(sources: [fonte], elements: [SCNGeometryElement(indices: (0..<UInt32(p.count)).map { $0 }, primitiveType: .line)])
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; m.transparency = alfa; m.readsFromDepthBuffer = false
            g.materials = [m]
            let n = SCNNode(geometry: g); n.renderingOrder = 50; ruota.addChildNode(n)
        }
        let ciano = UIColor(red: 0.31, green: 0.89, blue: 1, alpha: 1), ambra = UIColor(red: 1, green: 0.71, blue: 0.35, alpha: 1)
        let A = SIMD3<Float>(-w / 2, 0, -h / 2), B = SIMD3<Float>(w / 2, 0, -h / 2), C = SIMD3<Float>(w / 2, 0, h / 2), D = SIMD3<Float>(-w / 2, 0, h / 2)
        linea([A, B, B, C, C, D, D, A], ciano, 0.5)
        if xVerticale { linea([SIMD3(0, 0.005, -h / 2), SIMD3(0, 0.005, h / 2)], ambra, 1) }     // la larghezza: il lato orizzontale
        else { linea([SIMD3(-w / 2, 0.005, 0), SIMD3(w / 2, 0.005, 0)], ambra, 1) }
        // la misura scritta sopra l'immagine
        let r = ImageRenderer(content: Text(LidarFormato.m(Double(largo), 2)).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Color.ciano))
        r.scale = 3
        if let img = r.cgImage {
            let k: CGFloat = 0.004                                               // metri per punto: una scritta alta ~10 cm, leggibile a 1-4 m
            let piano = SCNPlane(width: CGFloat(img.width) / 3 * k, height: CGFloat(img.height) / 3 * k)
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = img; m.readsFromDepthBuffer = false; m.blendMode = .alpha
            piano.materials = [m]
            let n = SCNNode(geometry: piano)
            n.constraints = [SCNBillboardConstraint()]
            n.simdPosition = SIMD3(0, 0.02, -0.08)
            n.renderingOrder = 60
            ruota.addChildNode(n)
        }
        disegni.addChildNode(gruppo)
    }

    // MARK: Postura

    private static let indici: [String: Int] = {
        let nomi = ARSkeletonDefinition.defaultBody3D.jointNames
        let mappa = ["testa": "head_joint", "collo": "neck_1_joint", "spSx": "left_arm_joint", "spDx": "right_arm_joint",
                     "goSx": "left_forearm_joint", "goDx": "right_forearm_joint", "maSx": "left_hand_joint", "maDx": "right_hand_joint",
                     "bac": "hips_joint", "anSx": "left_upLeg_joint", "anDx": "right_upLeg_joint", "giSx": "left_leg_joint", "giDx": "right_leg_joint",
                     "piSx": "left_foot_joint", "piDx": "right_foot_joint", "occhioSx": "left_eye_joint", "occhioDx": "right_eye_joint"]
        var out: [String: Int] = [:]
        for (k, n) in mappa { if let i = nomi.firstIndex(of: n) { out[k] = i } }
        return out
    }()

    private func corpo(_ b: ARBodyAnchor) {
        guard b.isTracked, let v = vista, let f = v.session.currentFrame else { return }
        let t = f.timestamp
        let m = b.skeleton.jointModelTransforms
        var mondo: [String: SIMD3<Float>] = [:]
        for (k, i) in Self.indici where i < m.count {
            let p = b.transform * m[i].columns.3
            mondo[k] = SIMD3(p.x, p.y, p.z)
        }
        guard let bac = mondo["bac"], let testa = mondo["testa"], let piSx = mondo["piSx"], let piDx = mondo["piDx"] else { return }
        let piedi = min(piSx.y, piDx.y)
        // uno scheletro vero: la testa almeno 80 cm sopra i piedi (giunture tutte ferme in un punto = nessuna persona)
        guard testa.y - piedi > 0.8 else { return }
        ultimoCorpoVisto = t
        if t - ultimoDisegno > 0.06 { ultimoDisegno = t; disegnaScheletro(mondo) }   // lo scheletro si vede anche se la persona non è tutta dentro
        // la persona tutta nell'immagine, dalla testa ai piedi, e a una distanza giusta: se no lo si dice e il campione non vale
        if let manca = inquadratura(testa: testa, piSx: piSx, piDx: piDx, bacino: bac, f, v) { avvisaCorpo(manca); return }
        // il pavimento: il piano orizzontale più basso sotto i piedi, se no 7 cm sotto la caviglia
        let piani = f.anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }
            .map { ($0.transform * SIMD4<Float>($0.center.x, $0.center.y, $0.center.z, 1)).y }.filter { $0 < piedi && $0 > piedi - 0.3 }
        let pav = piani.max() ?? (piedi - 0.07)
        pavimentoCorpo = pav
        // il riferimento della persona: guarda verso l'iPhone (+z), a sinistra +x, piedi a terra
        let c = f.camera.transform.columns.3
        var avanti = SIMD3<Float>(c.x - bac.x, 0, c.z - bac.z)
        guard simd_length(avanti) > 0.3 else { return }
        avanti = simd_normalize(avanti)
        let sinistra = simd_cross(SIMD3<Float>(0, 1, 0), avanti)
        var locale: [String: SIMD3<Float>] = [:]
        for (k, p) in mondo { let d = p - bac; locale[k] = SIMD3(simd_dot(d, sinistra), p.y - pav, simd_dot(d, avanti)) }
        if inizioCorpo == nil { inizioCorpo = t }
        campioni.append(locale); if campioni.count > 180 { campioni.removeFirst() }
        let medie = Postura.media(campioni)
        let p = Postura(medie)
        let pronto = campioni.count >= 60 && t - (inizioCorpo ?? t) >= 2.5
        stato = StatoScansione(hud: [LidarFormato.m(Double(p.altezza), 2), LidarFormato.cm(Double(p.spalle)), pronto ? "OK" : "—"], pronto: pronto)
    }

    /// Postura: cosa manca perché la persona sia misurabile (nil: va bene). Testa e piedi devono cadere dentro l'immagine;
    /// a meno di 1,2 m una persona in piedi non ci sta, oltre 5 m lo scheletro è poco preciso.
    private func inquadratura(testa: SIMD3<Float>, piSx: SIMD3<Float>, piDx: SIMD3<Float>, bacino: SIMD3<Float>, _ f: ARFrame, _ v: ARSCNView) -> String? {
        let lato = v.bounds.size
        guard lato.width > 0, lato.height > 0 else { return nil }
        let verso = v.window?.windowScene?.interfaceOrientation ?? .portrait
        let c = f.camera.transform.columns.3
        let distanza = simd_distance(SIMD2<Float>(c.x, c.z), SIMD2<Float>(bacino.x, bacino.z))
        let testaDentro = nellImmagine(testa, f, verso, lato)
        let piediDentro = nellImmagine(piSx, f, verso, lato) && nellImmagine(piDx, f, verso, lato)
        if (!testaDentro && !piediDentro) || distanza < 1.2 { return "SI ALLONTANI · DEVO VEDERLA DALLA TESTA AI PIEDI" }
        if !testaDentro { return "INQUADRI ANCHE LA TESTA" }
        if !piediDentro { return "INQUADRI ANCHE I PIEDI" }
        if distanza > 5 { return "SI AVVICINI A 2-3 METRI" }
        return nil
    }

    /// Un punto del mondo cade dentro l'immagine che si vede sullo schermo (e davanti all'iPhone)?
    private func nellImmagine(_ p: SIMD3<Float>, _ f: ARFrame, _ verso: UIInterfaceOrientation, _ lato: CGSize) -> Bool {
        let c = f.camera.transform.inverse * SIMD4<Float>(p.x, p.y, p.z, 1)
        guard c.z < 0 else { return false }                                         // dietro l'iPhone
        let q = f.camera.projectPoint(p, orientation: verso, viewportSize: lato)
        return q.x >= 0 && q.y >= 0 && q.x <= lato.width && q.y <= lato.height
    }

    /// Lo scheletro sopra la persona inquadrata: ossa ciano, giunture chiare.
    private func disegnaScheletro(_ J: [String: SIMD3<Float>]) {
        disegni.childNodes.forEach { $0.removeFromParentNode() }
        let ossa: [(String, String)] = [("testa", "collo"), ("collo", "spSx"), ("collo", "spDx"), ("spSx", "goSx"), ("spDx", "goDx"), ("goSx", "maSx"), ("goDx", "maDx"),
                                        ("collo", "bac"), ("bac", "anSx"), ("bac", "anDx"), ("anSx", "giSx"), ("anDx", "giDx"), ("giSx", "piSx"), ("giDx", "piDx")]
        let mo = SCNMaterial(); mo.lightingModel = .constant; mo.diffuse.contents = UIColor(red: 0.31, green: 0.89, blue: 1, alpha: 1); mo.readsFromDepthBuffer = false
        let mg = SCNMaterial(); mg.lightingModel = .constant; mg.diffuse.contents = UIColor(red: 0.9, green: 0.96, blue: 0.97, alpha: 1); mg.readsFromDepthBuffer = false
        for (a, b) in ossa {
            guard let A = J[a], let B = J[b] else { continue }
            let d = B - A, l = simd_length(d)
            guard l > 0.001 else { continue }
            let cil = SCNCylinder(radius: 0.012, height: CGFloat(l)); cil.radialSegmentCount = 8; cil.materials = [mo]
            let n = SCNNode(geometry: cil); n.simdPosition = (A + B) / 2; n.simdOrientation = simd_quatf(from: [0, 1, 0], to: d / l); n.renderingOrder = 50
            disegni.addChildNode(n)
        }
        for (k, p) in J where !k.hasPrefix("occhio") {
            let s = SCNSphere(radius: 0.022); s.segmentCount = 10; s.materials = [mg]
            let n = SCNNode(geometry: s); n.simdPosition = p; n.renderingOrder = 51; disegni.addChildNode(n)
        }
    }

    // MARK: Fine: il risultato

    func concludi() {
        guard !fermata else { return }
        fermata = true
        OcchiLidar.scatta = nil                                                    // scansione finita: «guarda» torna a Occhi
        let inizio = Date()
        func consegna(_ r: RisultatoModo?) {
            // «ELABORAZIONE…» resta almeno 0,8 s, come nel mockup
            let resta = max(0, 0.8 - Date().timeIntervalSince(inizio))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(resta))
                guard !self.annullata else { return }
                if let r { self.finita(r) } else { self.errore("NON RIESCO A COSTRUIRE IL MODELLO · RIPROVI") }
            }
        }
        let maglie = vista?.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        vista?.session.pause()                                                     // i dati sono presi: la fotocamera si spegne
        disegni.childNodes.forEach { $0.removeFromParentNode() }
        switch modo {
        case .esterno:
            calcolo.terrenoFinale(maglie, percorso: percorso, chiuso: giroChiuso) { t in consegna(t.map { RisultatoModo.esterno($0) }) }
        case .oggetto:
            guard let s = seme else { consegna(nil); return }
            calcolo.oggettoFinale(maglie, seme: s, appoggio: appoggio ?? (s.y - 0.5)) { o in consegna(o.map { RisultatoModo.oggetto($0) }) }
        case .misura:
            consegna(misura.largo > 0 ? RisultatoModo.misura(larghezza: misura.largo, altezza: misura.alto) : nil)
        case .corpo:
            guard campioni.count >= 10 else { consegna(nil); return }
            consegna(RisultatoModo.postura(Postura(Postura.media(campioni))))
        default:
            consegna(nil)
        }
    }

    /// Esterno e Oggetto hanno davvero qualcosa da costruire? (per il secondo «Fine» prima del «FATTO»)
    var haDati: Bool {
        switch modo {
        case .esterno: return percorso.count >= 3 || calcolo.celleTerreno > 20
        case .oggetto: return seme != nil && !ultimeMisure.isEmpty
        case .misura: return misura.largo > 0.1
        case .corpo: return campioni.count >= 10
        default: return false
        }
    }
}

// MARK: - La postura dai campioni dello scheletro

nonisolated struct Postura: Sendable {
    var giunture: [String: SIMD3<Float>]
    var altezza: Float
    var spalle: Float
    var dislivelloSpalle: Float          // + la sinistra più alta (metri)
    var bacinoGradi: Float               // + ruotato verso destra (la destra va indietro)

    /// La media giuntura per giuntura.
    static func media(_ c: [[String: SIMD3<Float>]]) -> [String: SIMD3<Float>] {
        var somma: [String: SIMD3<Float>] = [:], n: [String: Float] = [:]
        for x in c { for (k, p) in x { somma[k, default: .zero] += p; n[k, default: 0] += 1 } }
        var out: [String: SIMD3<Float>] = [:]
        for (k, s) in somma { out[k] = s / max(1, n[k] ?? 1) }
        return out
    }

    init(_ J: [String: SIMD3<Float>]) {
        giunture = J.filter { !$0.key.hasPrefix("occhio") }
        // altezza: dagli occhi (in piedi gli occhi sono a circa il 93% della statura); se mancano, dalla testa
        if let a = J["occhioSx"], let b = J["occhioDx"] { altezza = (a.y + b.y) / 2 / 0.93 }
        else { altezza = (J["testa"]?.y ?? 1.63) / 0.915 }
        // spalle: tra le due articolazioni delle spalle, più 4 cm (fino al bordo osseo)
        if let s = J["spSx"], let d = J["spDx"] {
            spalle = simd_distance(SIMD2(s.x, s.z), SIMD2(d.x, d.z)) + 0.04
            dislivelloSpalle = s.y - d.y
        } else { spalle = 0; dislivelloSpalle = 0 }
        // bacino: di quanto la linea delle anche gira rispetto alla fronte (la destra più indietro = ruotato a destra)
        if let s = J["anSx"], let d = J["anDx"] {
            let dx = s.x - d.x, dz = s.z - d.z                                   // dalla destra alla sinistra
            bacinoGradi = atan2(dz, dx) * 180 / .pi                             // la sinistra più avanti (dz > 0) = ruotato a destra
        } else { bacinoGradi = 0 }
    }

    var testoSpalle: String {
        let cm = Int((abs(dislivelloSpalle) * 100).rounded())
        if cm < 2 { return "allineate" }
        return "più alta la \(dislivelloSpalle > 0 ? "sinistra" : "destra") di \(cm) cm"
    }
    var testoBacino: String {
        let g = Int(abs(bacinoGradi).rounded())
        if g < 2 { return "dritto" }
        let lato = bacinoGradi > 0 ? "destra" : "sinistra"
        return g <= 5 ? "ruotato di poco a \(lato)" : "ruotato a \(lato) di \(g)°"
    }
}

// MARK: - I conti pesanti (su una coda sua): terreno, oggetto, colori

/// Le misure dal vivo del terreno.
nonisolated struct MisureTerreno: Sendable { var area: Double; var perimetro: Double; var dislivello: Double? }
/// L'oggetto misurato.
nonisolated struct MisureOggetto: Sendable {
    var largo: Float, profondo: Float, alto: Float
    var dimensioni: SIMD3<Float> { SIMD3(largo, profondo, alto) }
}

nonisolated final class CalcoloLidar: @unchecked Sendable {
    private let coda = DispatchQueue(label: "it.discosizer.jarvis.lidar23", qos: .userInitiated)
    private var lavori = 0                       // solo sul main
    private var fermo = false
    private var cella: Float = 0.1               // terreno: celle da 10 cm
    // sulla coda: le quote del terreno e i colori (voxel da 2 cm per l'oggetto, celle per il terreno)
    private var quote: [Int64: Float] = [:]
    private var coloriCelle: [Int64: SIMD4<Float>] = [:]          // somma rgb + conteggio
    private var coloriVoxel: [Int64: SIMD4<Float>] = [:]
    private var puntiOggetto: [SIMD3<Float>] = []                 // gli ultimi vertici dell'oggetto, per i colori
    private var _celle = 0

    var occupato: Bool { lavori > 0 }
    var celleTerreno: Int { coda.sync { _celle } }
    func annulla() { coda.async { self.fermo = true } }

    private static func chiave(_ i: Int, _ j: Int) -> Int64 { (Int64(i) << 32) ^ Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: j))) }
    private static func chiave3(_ p: SIMD3<Float>, _ l: Float) -> Int64 {
        let i = Int64(Int32(truncatingIfNeeded: Int((p.x / l).rounded(.down)))) & 0x1FFFFF
        let j = Int64(Int32(truncatingIfNeeded: Int((p.y / l).rounded(.down)))) & 0x1FFFFF
        let k = Int64(Int32(truncatingIfNeeded: Int((p.z / l).rounded(.down)))) & 0x1FFFFF
        return (i << 42) | (j << 21) | k
    }

    /// I vertici di una maglia nel mondo, con le normali.
    private static func vertici(_ a: ARMeshAnchor) -> [(SIMD3<Float>, SIMD3<Float>)] {
        let g = a.geometry, v = g.vertices, n = g.normals
        guard v.format == .float3, n.format == .float3 else { return [] }
        let pv = v.buffer.contents().advanced(by: v.offset), pn = n.buffer.contents().advanced(by: n.offset)
        let T = a.transform
        var out: [(SIMD3<Float>, SIMD3<Float>)] = []; out.reserveCapacity(v.count)
        for i in 0..<v.count {
            let q = pv.advanced(by: i * v.stride).assumingMemoryBound(to: Float.self)
            let m = pn.advanced(by: i * n.stride).assumingMemoryBound(to: Float.self)
            let w = T * SIMD4<Float>(q[0], q[1], q[2], 1)
            let nw = T * SIMD4<Float>(m[0], m[1], m[2], 0)
            out.append((SIMD3(w.x, w.y, w.z), simd_normalize(SIMD3(nw.x, nw.y, nw.z))))
        }
        return out
    }
    private static func facce(_ a: ARMeshAnchor) -> [UInt32] {
        let f = a.geometry.faces
        guard f.indexCountPerPrimitive == 3 else { return [] }
        let p = f.buffer.contents()
        var out = [UInt32](); out.reserveCapacity(f.count * 3)
        for i in 0..<(f.count * 3) {
            if f.bytesPerIndex == 4 { out.append(p.advanced(by: i * 4).assumingMemoryBound(to: UInt32.self).pointee) }
            else { out.append(UInt32(p.advanced(by: i * 2).assumingMemoryBound(to: UInt16.self).pointee)) }
        }
        return out
    }

    // MARK: Terreno

    /// Le quote del terreno: per ogni cella da 10 cm la superficie orizzontale più bassa (la media dei vertici entro 5 cm dal minimo).
    private func rifaiQuote(_ maglie: [ARMeshAnchor]) {
        var minimo: [Int64: Float] = [:]
        var tutti: [(Int64, Float)] = []
        for a in maglie {
            for (p, n) in Self.vertici(a) where n.y > 0.8 {
                let k = Self.chiave(Int((p.x / cella).rounded(.down)), Int((p.z / cella).rounded(.down)))
                tutti.append((k, p.y))
                minimo[k] = min(minimo[k] ?? .infinity, p.y)
            }
        }
        var somma: [Int64: (Float, Float)] = [:]
        for (k, y) in tutti where y < (minimo[k] ?? .infinity) + 0.05 { let s = somma[k] ?? (0, 0); somma[k] = (s.0 + y, s.1 + 1) }
        quote = somma.mapValues { $0.0 / $0.1 }
        _celle = quote.count
    }

    /// Il bordo: il giro camminato se è chiuso, se no l'inviluppo di quello che il LiDAR ha visto a terra.
    private func bordo(_ percorso: [SIMD2<Double>], chiuso: Bool) -> [SIMD2<Double>] {
        if chiuso, percorso.count >= 3 { return Array(GeometriaPiana.semplifica(percorso + [percorso[0]], 0.25).dropLast()) }
        let punti = quote.keys.map { k -> SIMD2<Double> in
            let i = Int(Int32(truncatingIfNeeded: k >> 32)), j = Int(Int32(truncatingIfNeeded: k & 0xFFFFFFFF))
            return SIMD2((Double(i) + 0.5) * Double(cella), (Double(j) + 0.5) * Double(cella))
        }
        return GeometriaPiana.inviluppo(punti + (percorso.count >= 3 ? percorso : []))
    }

    private func dislivello(_ poli: [SIMD2<Double>]) -> Double? {
        var dentro: [Float] = []
        for (k, y) in quote {
            let i = Int(Int32(truncatingIfNeeded: k >> 32)), j = Int(Int32(truncatingIfNeeded: k & 0xFFFFFFFF))
            if GeometriaPiana.dentro(SIMD2((Double(i) + 0.5) * Double(cella), (Double(j) + 0.5) * Double(cella)), poli) { dentro.append(y) }
        }
        dentro.sort()
        guard dentro.count >= 20 else { return nil }
        let basso = dentro[Int(Double(dentro.count - 1) * 0.02)], alto = dentro[Int(Double(dentro.count - 1) * 0.98)]
        return Double(alto - basso)
    }

    func terreno(_ maglie: [ARMeshAnchor], percorso: [SIMD2<Double>], chiuso: Bool, _ fatto: @escaping @MainActor (MisureTerreno) -> Void) {
        lavori += 1
        coda.async {
            guard !self.fermo else { return }
            self.rifaiQuote(maglie)
            let poli = self.bordo(percorso, chiuso: chiuso)
            let m = MisureTerreno(area: GeometriaPiana.area(poli), perimetro: GeometriaPiana.perimetro(poli), dislivello: self.dislivello(poli))
            Task { @MainActor in self.lavori -= 1; fatto(m) }
        }
    }

    func terrenoFinale(_ maglie: [ARMeshAnchor], percorso: [SIMD2<Double>], chiuso: Bool, _ fatto: @escaping @MainActor (TerrenoScena?) -> Void) {
        coda.async {
            if !maglie.isEmpty { self.rifaiQuote(maglie) }
            let poli = self.bordo(percorso, chiuso: chiuso)
            guard poli.count >= 3, GeometriaPiana.area(poli) > 0.5, !self.quote.isEmpty else { Task { @MainActor in fatto(nil) }; return }
            let area = GeometriaPiana.area(poli)
            let passo = max(0.2, (area / 4000).squareRoot())                       // al massimo ~4000 celle nel modello
            let xs = poli.map(\.x), zs = poli.map(\.y)
            let x0 = (xs.min() ?? 0) - passo, z0 = (zs.min() ?? 0) - passo
            let nx = Int(((xs.max() ?? 0) - x0) / passo) + 2, nz = Int(((zs.max() ?? 0) - z0) / passo) + 2
            var q = [Float?](repeating: nil, count: nx * nz), col = [SIMD3<Float>?](repeating: nil, count: nx * nz)
            var sommaQ = [SIMD2<Float>](repeating: .zero, count: nx * nz), sommaC = [SIMD4<Float>](repeating: .zero, count: nx * nz)
            for (k, y) in self.quote {
                let i = Int(Int32(truncatingIfNeeded: k >> 32)), j = Int(Int32(truncatingIfNeeded: k & 0xFFFFFFFF))
                let x = (Double(i) + 0.5) * Double(self.cella), z = (Double(j) + 0.5) * Double(self.cella)
                let gi = Int((x - x0) / passo), gj = Int((z - z0) / passo)
                guard gi >= 0, gi < nx, gj >= 0, gj < nz else { continue }
                sommaQ[gj * nx + gi] += SIMD2(y, 1)
                if let c = self.coloriCelle[k] { sommaC[gj * nx + gi] += c }
            }
            for i in 0..<(nx * nz) {
                if sommaQ[i].y > 0 { q[i] = sommaQ[i].x / sommaQ[i].y }
                if sommaC[i].w > 0 { col[i] = SIMD3(sommaC[i].x, sommaC[i].y, sommaC[i].z) / sommaC[i].w }
            }
            // le celle che il LiDAR non ha visto: la media dei vicini, a giri, finché non sono piene
            func riempi<T>(_ a: inout [T?], _ somma: (T, T) -> T, _ dividi: (T, Float) -> T, _ riserva: T) {
                for _ in 0..<60 {
                    var vuote = 0; var nuovo = a
                    for j in 0..<nz { for i in 0..<nx where a[j * nx + i] == nil {
                        var s: T?; var n: Float = 0
                        for (di, dj) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                            let ii = i + di, jj = j + dj
                            guard ii >= 0, ii < nx, jj >= 0, jj < nz, let v = a[jj * nx + ii] else { continue }
                            s = s.map { somma($0, v) } ?? v; n += 1
                        }
                        if let s { nuovo[j * nx + i] = dividi(s, n) } else { vuote += 1 }
                    } }
                    a = nuovo
                    if vuote == 0 { break }
                }
                for i in a.indices where a[i] == nil { a[i] = riserva }
            }
            let misurate = q.compactMap { $0 }.sorted()
            let mediana = misurate.isEmpty ? 0 : misurate[misurate.count / 2]
            riempi(&q, { $0 + $1 }, { $0 / $1 }, mediana)
            let conColori = col.compactMap { $0 }.count > nx * nz / 10
            if conColori { riempi(&col, { $0 + $1 }, { $0 / $1 }, SIMD3<Float>(0.35, 0.38, 0.32)) }
            let t = TerrenoScena(bordo: poli, origine: SIMD2(x0, z0), passo: passo, nx: nx, nz: nz, quote: q.map { $0 ?? mediana },
                                 colori: conColori ? col.map { $0 ?? SIMD3(0.35, 0.38, 0.32) } : nil,
                                 area: area, dislivello: self.dislivello(poli) ?? 0)
            Task { @MainActor in fatto(t) }
        }
    }

    // MARK: Oggetto

    /// I vertici dell'oggetto: quelli sopra l'appoggio, attaccati al punto mirato (griglia da 2 cm, crescita della regione).
    private func segmenta(_ maglie: [ARMeshAnchor], seme: SIMD3<Float>, appoggio: Float) -> (punti: [SIMD3<Float>], tri: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)])? {
        let l: Float = 0.02
        var vertici: [[(SIMD3<Float>, SIMD3<Float>)]] = []
        var celle = Set<Int64>()
        for a in maglie {
            let v = Self.vertici(a)
            vertici.append(v)
            for (p, _) in v where p.y > appoggio + 0.015 && p.y < appoggio + 2.5 && simd_distance(SIMD2(p.x, p.z), SIMD2(seme.x, seme.z)) < 1.5 {
                celle.insert(Self.chiave(Int((p.x / l).rounded(.down)), Int((p.z / l).rounded(.down))))
            }
        }
        let s = (Int((seme.x / l).rounded(.down)), Int((seme.z / l).rounded(.down)))
        // il seme: la cella occupata più vicina al punto mirato
        var partenza: (Int, Int)?
        cerca: for r in 0...5 { for di in -r...r { for dj in -r...r where celle.contains(Self.chiave(s.0 + di, s.1 + dj)) { partenza = (s.0 + di, s.1 + dj); break cerca } } }
        guard let p0 = partenza else { return nil }
        var preso = Set<Int64>([Self.chiave(p0.0, p0.1)]), coda = [p0]
        while let c = coda.popLast() {
            for di in -1...1 { for dj in -1...1 where di != 0 || dj != 0 {
                let k = Self.chiave(c.0 + di, c.1 + dj)
                if celle.contains(k), !preso.contains(k) { preso.insert(k); coda.append((c.0 + di, c.1 + dj)) }
            } }
            if preso.count > 40_000 { break }                                        // più di 16 m²: non è un oggetto
        }
        var punti: [SIMD3<Float>] = [], tri: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for (ai, a) in maglie.enumerated() {
            let v = vertici[ai]
            var dentro = [Bool](repeating: false, count: v.count)
            for (i, (p, _)) in v.enumerated() where p.y > appoggio + 0.015 && p.y < appoggio + 2.5
                && preso.contains(Self.chiave(Int((p.x / l).rounded(.down)), Int((p.z / l).rounded(.down)))) { dentro[i] = true; punti.append(p) }
            let f = Self.facce(a)
            for k in stride(from: 0, to: f.count - 2, by: 3) {
                let i0 = Int(f[k]), i1 = Int(f[k + 1]), i2 = Int(f[k + 2])
                guard i0 < v.count, i1 < v.count, i2 < v.count, dentro[i0], dentro[i1], dentro[i2] else { continue }
                tri.append((v[i0].0, v[i1].0, v[i2].0))
            }
        }
        return punti.count >= 30 ? (punti, tri) : nil
    }

    /// Il rettangolo più piccolo che contiene l'oggetto visto dall'alto (prima ogni grado, poi ogni 0,05° intorno al migliore): angolo e lati.
    private static func scatola(_ punti: [SIMD3<Float>]) -> (angolo: Float, centro: SIMD2<Float>, largo: Float, profondo: Float) {
        var meglio = (angolo: Float(0), centro: SIMD2<Float>(0, 0), largo: Float(0), profondo: Float(0), area: Float.infinity)
        var migliore: Float = 0
        func prova(_ gradi: [Float]) {
            for g in gradi {
                let a = g * .pi / 180, u = SIMD2(cos(a), sin(a)), w = SIMD2(-sin(a), cos(a))
                var mnU = Float.infinity, mxU = -Float.infinity, mnW = Float.infinity, mxW = -Float.infinity
                for p in punti {
                    let q = SIMD2(p.x, p.z), pu = simd_dot(q, u), pw = simd_dot(q, w)
                    mnU = min(mnU, pu); mxU = max(mxU, pu); mnW = min(mnW, pw); mxW = max(mxW, pw)
                }
                let area = (mxU - mnU) * (mxW - mnW)
                guard area < meglio.area else { continue }
                let c = u * ((mnU + mxU) / 2) + w * ((mnW + mxW) / 2)
                meglio = mxU - mnU >= mxW - mnW ? (a, c, mxU - mnU, mxW - mnW, area) : (a + .pi / 2, c, mxW - mnW, mxU - mnU, area)
                migliore = g
            }
        }
        prova((0..<90).map { Float($0) })
        prova((-20...20).map { migliore + Float($0) * 0.05 })
        return (meglio.angolo, meglio.centro, meglio.largo, meglio.profondo)
    }

    func oggetto(_ maglie: [ARMeshAnchor], seme: SIMD3<Float>, appoggio: Float, _ fatto: @escaping @MainActor (MisureOggetto?) -> Void) {
        lavori += 1
        coda.async {
            guard !self.fermo else { return }
            var m: MisureOggetto?
            if let s = self.segmenta(maglie, seme: seme, appoggio: appoggio) {
                self.puntiOggetto = s.punti
                let b = Self.scatola(s.punti)
                let alto = (s.punti.map(\.y).max() ?? appoggio) - appoggio
                m = MisureOggetto(largo: b.largo, profondo: b.profondo, alto: alto)
            }
            Task { @MainActor [m] in self.lavori -= 1; fatto(m) }     // [m]: la copia; una var catturata non si legge da un Task
        }
    }

    func oggettoFinale(_ maglie: [ARMeshAnchor], seme: SIMD3<Float>, appoggio: Float, _ fatto: @escaping @MainActor (OggettoScena?) -> Void) {
        coda.async {
            guard let s = self.segmenta(maglie, seme: seme, appoggio: appoggio), !s.tri.isEmpty else { Task { @MainActor in fatto(nil) }; return }
            let b = Self.scatola(s.punti)
            let alto = (s.punti.map(\.y).max() ?? appoggio) - appoggio
            // girato sugli assi della scatola: x = largo, z = profondo, la base a y = 0
            let ca = cos(-b.angolo), sa = sin(-b.angolo)
            func porta(_ p: SIMD3<Float>) -> SIMD3<Float> {
                let x = p.x - b.centro.x, z = p.z - b.centro.y
                return SIMD3(x * ca - z * sa, p.y - appoggio, x * sa + z * ca)
            }
            var vertici: [SIMD3<Float>] = [], indici: [UInt32] = [], colori: [SIMD3<Float>] = []
            var colorati = 0
            for (a, c, d) in s.tri {
                for p in [a, c, d] {
                    indici.append(UInt32(vertici.count))
                    vertici.append(porta(p))
                    if let v = self.coloriVoxel[Self.chiave3(p, 0.02)], v.w > 0 { colori.append(SIMD3(v.x, v.y, v.z) / v.w); colorati += 1 }
                    else { colori.append(SIMD3(0.5, 0.5, 0.5)) }
                }
            }
            let o = OggettoScena(vertici: vertici, colori: colorati > vertici.count / 3 ? colori : nil, indici: indici,
                                 largo: b.largo, profondo: b.profondo, alto: alto)
            Task { @MainActor in fatto(o) }
        }
    }

    // MARK: Colori veri dalla fotocamera

    /// Prende i colori dell'immagine: per il terreno sulle celle vicine, per l'oggetto sui suoi vertici (solo se visibili: profondità).
    func colora(_ f: ARFrame, terreno: Bool) {
        // nonisolated(unsafe): le immagini della fotocamera passano alla coda di calcolo e non si toccano più qui (niente avvisi)
        nonisolated(unsafe) let immagine = f.capturedImage
        nonisolated(unsafe) let profondita = f.sceneDepth?.depthMap
        let T = f.camera.transform.inverse, K = f.camera.intrinsics, ris = f.camera.imageResolution
        let cam = f.camera.transform.columns.3
        coda.async {
            guard !self.fermo else { return }
            CVPixelBufferLockBaseAddress(immagine, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(immagine, .readOnly) }
            if let profondita { CVPixelBufferLockBaseAddress(profondita, .readOnly) }
            defer { if let profondita { CVPixelBufferUnlockBaseAddress(profondita, .readOnly) } }
            guard CVPixelBufferGetPlaneCount(immagine) >= 2,
                  let pY = CVPixelBufferGetBaseAddressOfPlane(immagine, 0), let pC = CVPixelBufferGetBaseAddressOfPlane(immagine, 1) else { return }
            let rY = CVPixelBufferGetBytesPerRowOfPlane(immagine, 0), rC = CVPixelBufferGetBytesPerRowOfPlane(immagine, 1)
            let W = CVPixelBufferGetWidthOfPlane(immagine, 0), H = CVPixelBufferGetHeightOfPlane(immagine, 0)
            let fx = K[0][0], fy = K[1][1], cx = K[2][0], cy = K[2][1]
            let sx = Float(W) / Float(ris.width), sy = Float(H) / Float(ris.height)
            // dal mondo al pixel; nil se dietro o fuori; la distanza davanti alla camera
            func pixel(_ p: SIMD3<Float>) -> (Int, Int, Float)? {
                let c = T * SIMD4<Float>(p.x, p.y, p.z, 1)
                guard c.z < -0.05 else { return nil }
                let u = (fx * c.x / -c.z + cx) * sx, v = (fy * -c.y / -c.z + cy) * sy
                guard u >= 0, v >= 0, u < Float(W - 1), v < Float(H - 1) else { return nil }
                return (Int(u), Int(v), -c.z)
            }
            func rgb(_ u: Int, _ v: Int) -> SIMD3<Float> {
                let y = Float(pY.advanced(by: v * rY + u).assumingMemoryBound(to: UInt8.self).pointee) / 255
                let o = (v / 2) * rC + (u / 2) * 2
                let cb = Float(pC.advanced(by: o).assumingMemoryBound(to: UInt8.self).pointee) / 255
                let cr = Float(pC.advanced(by: o + 1).assumingMemoryBound(to: UInt8.self).pointee) / 255
                // YCbCr pieno (BT.601), come nel campione di Apple per capturedImage
                return simd_clamp(SIMD3(y + 1.402 * cr - 0.701, y - 0.3441 * cb - 0.7141 * cr + 0.5291, y + 1.772 * cb - 0.886), SIMD3(repeating: 0), SIMD3(repeating: 1))
            }
            func visibile(_ u: Int, _ v: Int, _ d: Float) -> Bool {
                guard let profondita else { return true }
                let dw = CVPixelBufferGetWidth(profondita), dh = CVPixelBufferGetHeight(profondita), r = CVPixelBufferGetBytesPerRow(profondita)
                guard let b = CVPixelBufferGetBaseAddress(profondita) else { return true }
                let du = min(dw - 1, u * dw / W), dv = min(dh - 1, v * dh / H)
                let misurata = b.advanced(by: dv * r + du * 4).assumingMemoryBound(to: Float32.self).pointee
                return abs(misurata - d) < 0.06
            }
            if terreno {
                let c = SIMD2(cam.x, cam.z), raggio: Float = 4
                for (k, y) in self.quote {
                    let i = Int(Int32(truncatingIfNeeded: k >> 32)), j = Int(Int32(truncatingIfNeeded: k & 0xFFFFFFFF))
                    let p = SIMD3((Float(i) + 0.5) * self.cella, y, (Float(j) + 0.5) * self.cella)
                    guard simd_distance(SIMD2(p.x, p.z), c) < raggio, let px = pixel(p), visibile(px.0, px.1, px.2) else { continue }
                    let col = rgb(px.0, px.1)
                    self.coloriCelle[k, default: .zero] += SIMD4(col.x, col.y, col.z, 1)
                }
            } else {
                for p in self.puntiOggetto {
                    guard let px = pixel(p), visibile(px.0, px.1, px.2) else { continue }
                    let col = rgb(px.0, px.1)
                    self.coloriVoxel[Self.chiave3(p, 0.02), default: .zero] += SIMD4(col.x, col.y, col.z, 1)
                }
            }
        }
    }
}

// MARK: - Corpo › Texture: il gemello digitale con Object Capture (giro intorno alla persona, poi il modello sull'iPhone)
// Come il campione di Apple «GuidedCapture»: la sessione parte, si cerca la persona al centro (startDetecting, che può dire di no:
// allora si riprova), il riquadro, gli scatti automatici (startCapturing), «Fine» (finish), e a .completed la sessione di cattura
// si libera PRIMA di costruire il modello (memoria e GPU), con la stessa cartella dei punti (checkpointDirectory).
// Lo stato si legge 4 volte al secondo da `state`: non dipende da cosa ripetono o no gli aggiornamenti a cui ci si iscrive.

struct CatturaStatua: View {
    @Binding var ferma: Bool
    let aggiorna: (StatoScansione) -> Void
    let elaboro: () -> Void
    let finita: (RisultatoModo) -> Void
    let errore: (String) -> Void
    var nome: String? = nil

    @State private var sessione: ObjectCaptureSession?
    @State private var cartella: URL?
    @State private var foto = 0
    @State private var giro = false
    @State private var finito = false                 // foto prese: la fotocamera si toglie, si costruisce il modello
    @State private var avviata = false
    @State private var regia: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.clear                               // la cornice è piena anche prima che la sessione esista, come negli altri modi
            if let s = sessione, !finito { ObjectCaptureView(session: s) }
        }
        .onAppear(perform: avvia)
        .onDisappear(perform: chiudi)
        .onChange(of: ferma) { _, f in if f { concludi() } }
    }

    private func avvia() {
        guard !avviata else { return }
        avviata = true
        guard SupportoModi.oggettoFoto else { errore(SupportoModi.avviso(.statua)); return }
        OcchiLidar.scatta = { nil }            // la fotocamera è di Object Capture: «guarda» non apre Occhi (le ruberebbe la fotocamera)
        UIApplication.shared.isIdleTimerDisabled = true   // un minuto di giro e due di elaborazione senza toccare lo schermo
        regia = Task { @MainActor in
            // la fotocamera di prima (un'altra scansione, Occhi) ha il tempo di liberarsi; intanto c'è «ACCENSIONE SENSORE…»
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            guard await permessoFotocamera() else { errore("SERVE IL PERMESSO DELLA FOTOCAMERA · IMPOSTAZIONI › JARVIS"); return }
            guard !Task.isCancelled, apri() else { return }
            if await segui() { await ricostruisci() }
        }
    }

    private func chiudi() {
        regia?.cancel()
        sessione?.cancel()
        sessione = nil
        OcchiLidar.scatta = nil
        UIApplication.shared.isIdleTimerDisabled = false
        pulisci()
    }

    /// Il permesso della fotocamera: se non è mai stato chiesto lo chiede adesso; se è stato negato lo si dice (niente schermo nero).
    private func permessoFotocamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Le cartelle (Images, Snapshots) e la sessione di Apple. Se la sessione fallisce subito, lo si dice (come il campione di Apple).
    private func apri() -> Bool {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("LiDAR-texture-\(UUID().uuidString)", isDirectory: true)
        let immagini = base.appendingPathComponent("Images/", isDirectory: true), punti = base.appendingPathComponent("Snapshots/", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: immagini, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: punti, withIntermediateDirectories: true)
        } catch {
            errore("NON RIESCO A PREPARARE LE FOTO · RIPROVI")
            return false
        }
        cartella = base
        let s = ObjectCaptureSession()
        var c = ObjectCaptureSession.Configuration()
        c.checkpointDirectory = punti
        s.start(imagesDirectory: immagini, configuration: c)
        if case .failed(let e) = s.state {
            errore("SCANSIONE INTERROTTA · \(e.localizedDescription.uppercased())")
            return false
        }
        sessione = s
        return true
    }

    /// La regia, 4 volte al secondo: guarda lo stato della sessione, le dà i comandi al momento giusto e scrive nella riga di stato
    /// cosa sta succedendo. true quando le foto sono prese (.completed) e si può costruire il modello.
    private func segui() async -> Bool {
        let inizio = Date()
        var ultimaRicerca = Date.distantPast            // l'ultimo startDetecting()
        var mancate = 0                                 // le ricerche andate a vuoto (la persona non è al centro o è lontana)
        var trovata: Date?                              // da quando c'è il riquadro sulla persona
        var ultimoAvvio = Date.distantPast              // l'ultimo startCapturing()
        var inviato: StatoScansione?
        while !Task.isCancelled {
            guard let s = sessione else { return false }
            var testo: String?
            switch s.state {
            case .initializing:
                testo = "ACCENSIONE SENSORE…"
                if Date().timeIntervalSince(inizio) > 15 { fallita("LA FOTOCAMERA NON PARTE · RIPROVI"); return false }
            case .ready:
                trovata = nil
                // `if case`: funziona qualunque sia il tipo dello stato di tracciamento (non serve che sia Equatable)
                if case .normal = s.cameraTracking {
                    // Apple cerca l'oggetto sotto il pallino al centro: se non lo trova risponde false e resta pronta. Si riprova.
                    if Date().timeIntervalSince(ultimaRicerca) > 1.5 {
                        ultimaRicerca = Date()
                        if !s.startDetecting() { mancate += 1 }
                    }
                    testo = consiglio(s) ?? (mancate < 4 ? "CERCO LA PERSONA · LA TENGA AL CENTRO" : "NON LA TROVO · SI AVVICINI E LA TENGA AL CENTRO")
                } else {
                    testo = "MUOVA PIANO L'IPHONE PER PARTIRE"
                }
            case .detecting:
                mancate = 0
                let t0 = trovata ?? Date()
                trovata = t0
                testo = "PERSONA TROVATA · UN ATTIMO…"
                // il riquadro è sulla persona: dopo 2 s gli scatti partono da soli (se non partono, si richiede ogni 2 s)
                if Date().timeIntervalSince(t0) >= 2, Date().timeIntervalSince(ultimoAvvio) > 2 {
                    ultimoAvvio = Date()
                    s.startCapturing()
                }
            case .capturing:
                testo = consiglio(s)                    // nil: «LA PERSONA STIA FERMA · LE GIRI INTORNO», poi «FATTO · TOCCHI FINE»
            case .completed:
                finito = true                           // via la fotocamera…
                sessione = nil                          // …e la sessione di cattura si libera prima di costruire (campione di Apple)
                return true
            case .failed(let e):
                if Task.isCancelled { return false }        // chiusa da lei (cancel): non è un errore da mostrare
                fallita("SCANSIONE INTERROTTA · \(e.localizedDescription.uppercased())")
                return false
            default:
                break                                   // .finishing dopo «Fine»: la riga dice «ELABORAZIONE…»
            }
            let n = s.numberOfShotsTaken, g = s.userCompletedScanPass
            if n != foto { foto = n }
            if g != giro { giro = g }
            let nuovo = StatoScansione(hud: [n > 0 ? "\(n)" : "—", "—", g ? "360°" : "—"], pronto: g && n >= 20, testo: testo)
            if nuovo != inviato { inviato = nuovo; aggiorna(nuovo) }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// I consigli di Object Capture (quelli che mostra anche il campione di Apple), in parole nostre.
    private func consiglio(_ s: ObjectCaptureSession) -> String? {
        let f = s.feedback
        if f.contains(.environmentTooDark) || f.contains(.environmentLowLight) { return "SERVE PIÙ LUCE" }
        if f.contains(.objectTooFar) { return "SI AVVICINI" }
        if f.contains(.objectTooClose) { return "SI ALLONTANI UN PO'" }
        if f.contains(.movingTooFast) { return "PIÙ PIANO" }
        if f.contains(.outOfFieldOfView) { return "INQUADRI LA PERSONA" }
        return nil
    }

    /// Un errore: la sessione si ferma (la fotocamera si libera) e la riga arancione dice cosa è successo, con «Riprova».
    private func fallita(_ testo: String) {
        sessione?.cancel()
        sessione = nil
        errore(testo)
    }

    private func concludi() {
        guard let s = sessione, !finito else { return }
        guard foto >= 20 else { errore("SERVONO PIÙ FOTO · GIRI ANCORA INTORNO"); return }
        elaboro()
        OcchiLidar.scatta = nil
        s.finish()                                                                 // → .finishing → .completed → ricostruisci()
    }

    /// Il modello sull'iPhone (dettaglio ridotto, quello di iOS): USDZ con la texture fotografica. La percentuale va nella riga di stato.
    private func ricostruisci() async {
        guard let base = cartella else { return }
        let inizio = Date()
        let uscita = ArchivioLidar.cartella.appendingPathComponent("texture-\(UUID().uuidString).usdz")
        let hud = [foto > 0 ? "\(foto)" : "—", "—", giro ? "360°" : "—"]
        var conf = PhotogrammetrySession.Configuration()
        conf.checkpointDirectory = base.appendingPathComponent("Snapshots/", isDirectory: true)   // i dati della cattura: si fa prima
        do {
            let p = try PhotogrammetrySession(input: base.appendingPathComponent("Images/", isDirectory: true), configuration: conf)
            try p.process(requests: [.modelFile(url: uscita)])
            var ultimo = -1
            for try await o in p.outputs {
                if Task.isCancelled { p.cancel(); return }
                switch o {
                case .requestProgress(_, fractionComplete: let x):
                    let pc = min(99, max(0, Int(x * 100)))
                    if pc != ultimo { ultimo = pc; aggiorna(StatoScansione(hud: hud, pronto: true, testo: "ELABORAZIONE… \(pc)%")) }
                case .processingComplete:
                    pulisci()
                    let minuti = Date().timeIntervalSince(inizio) / 60
                    finita(RisultatoModo.statua(file: uscita, foto: foto, minuti: minuti, nome: nome))
                    return
                case .requestError(_, let e):
                    errore("NON RIESCO A COSTRUIRE IL MODELLO · \(e.localizedDescription.uppercased())"); return
                case .processingCancelled: return
                default: break
                }
            }
        } catch {
            errore("NON RIESCO A COSTRUIRE IL MODELLO · RIPROVI")
        }
    }

    /// Le foto servono solo per costruire il modello: poi si cancellano.
    private func pulisci() {
        guard let base = cartella else { return }
        try? FileManager.default.removeItem(at: base)
        cartella = nil
    }
}
#endif
