#if os(iOS)
import SwiftUI
import SceneKit
import UIKit
import simd

// MARK: - LiDAR 23 · il 3D olografico (la «scena3d» del mockup approvato, in SceneKit)
// Anteprima a ologramma nel menu dei modi, risultato OLOGRAMMA (colore pieno) o TEXTURE (foto) che si «materializza» dal basso.
// Si gira col dito (in orizzontale; in verticale scorre la pagina), si ingrandisce con due dita, doppio tocco per tornare all'inizio;
// dopo 2,6 s di quiete riprende a girare da solo. Mirino ad anelli a terra, polvere, nuvola di punti (solo in anteprima),
// etichette sopra il modello (solo nel risultato), «360°» in basso a destra.

/// Lo stile del modello finito. `pieno` è il tasto OLOGRAMMA (colore pieno), `foto` il tasto TEXTURE.
nonisolated enum StileLidar: String, Codable, Sendable { case pieno, foto }

/// Anteprima (menu dei modi: nuvola di punti, niente etichette) o risultato (etichette e quote).
nonisolated enum FaseScenaLidar: Sendable { case anteprima, risultato }

// MARK: - I modelli da mostrare

/// Una stanza per il 3D: pavimento, pareti a segmenti, porte, finestre, altezza (metri; x e z della pianta).
nonisolated struct StanzaScena: Sendable {
    var pavimento: [SIMD2<Double>]
    var pareti: [TrattoPianta]
    var porte: [TrattoPianta]
    var finestre: [TrattoPianta]
    var altezza: Double

    init(pavimento: [SIMD2<Double>], pareti: [TrattoPianta], porte: [TrattoPianta], finestre: [TrattoPianta], altezza: Double) {
        self.pavimento = pavimento; self.pareti = pareti; self.porte = porte; self.finestre = finestre; self.altezza = altezza
    }

    /// Da una scansione salvata: il poligono del pavimento se c'è, se no l'inviluppo dei capi delle pareti.
    init(_ s: ScansioneLidar) {
        var p = (s.pavimento ?? []).compactMap { $0.count >= 2 ? SIMD2($0[0], $0[1]) : nil }
        if p.count < 3 { p = GeometriaPiana.inviluppo(s.pareti.flatMap { [SIMD2($0.ax, $0.az), SIMD2($0.bx, $0.bz)] }) }
        self.init(pavimento: p, pareti: s.pareti, porte: s.porte, finestre: s.finestre, altezza: s.altezza > 0 ? s.altezza : 2.7)
    }

    /// Dal poligono del mockup: ogni lato è una parete; porte e finestre come (parete, da, lunghezza).
    init(poligono: [SIMD2<Double>], altezza: Double, porte: [(Int, Double, Double)], finestre: [(Int, Double, Double)]) {
        let n = poligono.count
        func tratto(_ i: Int, _ da: Double, _ l: Double) -> TrattoPianta {
            let a = poligono[i], b = poligono[(i + 1) % n], u = simd_normalize(b - a)
            let p = a + u * da, q = a + u * (da + l)
            return TrattoPianta(ax: p.x, az: p.y, bx: q.x, bz: q.y)
        }
        self.init(pavimento: poligono,
                  pareti: (0..<n).map { i in TrattoPianta(ax: poligono[i].x, az: poligono[i].y, bx: poligono[(i + 1) % n].x, bz: poligono[(i + 1) % n].y) },
                  porte: porte.map { tratto($0.0, $0.1, $0.2) }, finestre: finestre.map { tratto($0.0, $0.1, $0.2) }, altezza: altezza)
    }

    var area: Double { GeometriaPiana.area(pavimento) }
}

/// Il terreno di Esterno: una griglia di quote (metri) con i colori veri presi dalla fotocamera, dentro il bordo percorso.
nonisolated struct TerrenoScena: Sendable {
    var bordo: [SIMD2<Double>]                 // il perimetro camminato (x, z)
    var origine: SIMD2<Double>                 // l'angolo della griglia
    var passo: Double                          // lato della cella
    var nx: Int, nz: Int
    var quote: [Float]                         // nx × nz, metri (già riempite dove mancavano)
    var colori: [SIMD3<Float>]?                // nx × nz, sRGB 0…1 (nil: solo ologramma e colore pieno)
    var area: Double
    var dislivello: Double                     // metri
}

/// L'oggetto di Oggetto: la maglia del LiDAR, già girata sugli assi della scatola (x = largo, z = profondo), base a y = 0.
nonisolated struct OggettoScena: Sendable {
    var vertici: [SIMD3<Float>]
    var colori: [SIMD3<Float>]?                // sRGB 0…1
    var indici: [UInt32]
    var largo: Float, profondo: Float, alto: Float
}

/// Lo scheletro di Postura: le 15 giunture del mockup (metri, piedi a terra, la persona guarda verso +z).
nonisolated struct PosturaScena: Sendable {
    var giunture: [String: SIMD3<Float>]
    var altezza: Float
    var spalle: Float                          // metri
    var bacinoGradi: Float                     // + verso destra della persona
}

nonisolated enum ModelloScena: Sendable {
    case stanza(StanzaScena)
    case evento(StanzaScena, Allestimento)
    case esterno(TerrenoScena)
    case oggetto(OggettoScena)
    case cassaEsempio                          // il flight case del mockup (solo anteprima)
    case statua(URL?, altezza: Float)          // nil: la persona d'esempio (MakeHuman) con la texture dipinta
    case postura(PosturaScena)
    case misura(larghezza: Float, altezza: Float)
}

// MARK: - La scena

@MainActor
final class ScenaLidar: NSObject {
    let scena = SCNScene()
    let camera = SCNNode()
    let fase: FaseScenaLidar
    private(set) var stile: StileLidar?
    private(set) var tag: String?                    // «RILIEVO ×3» in alto a sinistra (Esterno)
    private let radice = SCNNode()

    // una parte del modello: il solido in FOTO e in PIENO, il suo fantasma olografico e i bordi
    private final class Parte {
        let foto: SCNNode?, pieno: SCNNode?, fantasma: SCNNode, linee: SCNNode?
        init(foto: SCNNode?, pieno: SCNNode?, fantasma: SCNNode, linee: SCNNode?) { self.foto = foto; self.pieno = pieno; self.fantasma = fantasma; self.linee = linee }
    }
    private var parti: [Parte] = []
    private var sopra: [SCNNode] = []                // quote, porte, passaggi: solo nel risultato
    private var etichette: [SCNNode] = []
    private var materialiOlo: [SCNMaterial] = []
    private var materialiSolidi: [SCNMaterial] = []
    private var lineaOlo = SCNMaterial(), lineaScura = SCNMaterial()
    private var triangoli: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []   // per la nuvola di punti
    private var nuvola: SCNNode?

    // casa delle bambole: le pareti davanti si fanno trasparenti
    private final class Muro {
        let normale: SIMD2<Float>; var nodi: [SCNNode] = []; var materiali: [SCNMaterial] = []; var vetri: [SCNMaterial] = []; var linee: [SCNNode] = []; var a: Float = 1
        init(_ n: SIMD2<Float>) { normale = n }
    }
    private var muri: [Muro] = []

    // inquadratura (come «cos» del mockup)
    private var inclinazioneBase: Float = 0.7, k: Float = 0.85
    private var asse = SIMD3<Float>(0, 1, 0)
    private var bersaglio = SIMD3<Float>(0, 0, 0)
    private var R: Float = 1
    private var dMin: Float = 0, dMax: Float = 1
    private var campioni = 6000

    // camera e gesti
    var yaw: Float = 0.65
    var inclinazione: Float = 0.7
    var zoom: Float = 1
    var toccando = false
    var ultimoTocco: CFTimeInterval = 0
    private var transizione: CFTimeInterval?
    private var prima: CFTimeInterval = 0
    private var link: CADisplayLink?
    weak var vista: SCNView?

    init(_ modello: ModelloScena, fase: FaseScenaLidar, stile: StileLidar?) {
        self.fase = fase
        self.stile = stile
        super.init()
        lineaOlo = Self.linea(0x7feeff, 0.9, additiva: true)
        lineaScura = Self.linea(0x05080a, 0.45, additiva: false)
        scena.rootNode.addChildNode(radice)
        luci()
        switch modello {
        case .stanza(let s): interno(s)
        case .evento(let s, let a): evento(s, a)
        case .esterno(let t): esterno(t)
        case .oggetto(let o): oggetto(o)
        case .cassaEsempio: cassa()
        case .statua(let url, let h): statua(url, altezza: h)
        case .postura(let p): postura(p)
        case .misura(let l, let h): misura(l, h)
        }
        inquadra()
        if fase == .anteprima { nuvolaDiPunti() }
        sopra.forEach { $0.isHidden = fase != .risultato }
        etichette.forEach { $0.isHidden = fase != .risultato }
        let c = SCNCamera(); c.fieldOfView = 32; c.zNear = 0.05; c.zFar = 500
        camera.camera = c
        scena.rootNode.addChildNode(camera)
        inclinazione = inclinazioneBase
        if stile != nil { materializza() } else { applica() }
    }

    // MARK: Avvio e fermata del giro (CADisplayLink sul main)

    func avvia(_ v: SCNView) {
        vista = v
        prima = CACurrentMediaTime()
        ultimoTocco = 0
        let l = CADisplayLink(target: self, selector: #selector(passo(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        aggiornaCamera(0)
    }
    func ferma() { link?.invalidate(); link = nil }

    /// OLOGRAMMA ↔ TEXTURE: il nuovo materiale sale dal basso in 1,1 s (nel risultato e nell'anteprima).
    func imposta(_ s: StileLidar?) {
        guard s != stile else { return }
        stile = s
        if s == nil { applica() } else { materializza() }
    }

    func ripristina() { yaw = 0.65; inclinazione = inclinazioneBase; zoom = 1 }

    @objc private func passo(_ l: CADisplayLink) {
        let ora = l.timestamp
        let dt = Float(min(0.05, max(0, ora - prima)))
        prima = ora
        if !toccando && ora - ultimoTocco > 2.6 { yaw += dt * 0.22 }            // gira da solo dopo 2,6 s di quiete
        if let t0 = transizione {
            let f = Float(min(1, (ora - t0) / 1.1)), e = 1 - pow(1 - f, 2.4)
            let v = dMin - 0.01 + (dMax - dMin + 0.05) * e
            taglio(v, verso: -1)
            if f >= 1 { transizione = nil; taglio(1e6, verso: 1); applica() }
        }
        aggiornaCamera(dt)
    }

    private func aggiornaCamera(_ dt: Float) {
        guard let v = vista, v.bounds.width > 0, v.bounds.height > 0 else { return }
        let aspetto = Float(v.bounds.width / v.bounds.height)
        let vf: Float = 32 * .pi / 180, hf = 2 * atan(tan(vf / 2) * aspetto)
        let d = R / sin(min(vf, hf) / 2) * k * zoom
        let p = bersaglio + d * SIMD3(cos(inclinazione) * sin(yaw), sin(inclinazione), cos(inclinazione) * cos(yaw))
        camera.simdPosition = p
        camera.simdLook(at: bersaglio)
        // casa delle bambole
        if !muri.isEmpty {
            var vx = p.x - bersaglio.x, vz = p.z - bersaglio.z
            let l = max(0.0001, (vx * vx + vz * vz).squareRoot()); vx /= l; vz /= l
            for m in muri {
                let davanti = m.normale.x * vx + m.normale.y * vz > 0.2
                m.a += ((davanti ? 0.1 : 1) - m.a) * min(1, dt * 6)
                for mt in m.materiali { mt.transparency = CGFloat(m.a); mt.writesToDepthBuffer = m.a > 0.5 }
                for mt in m.vetri { mt.transparency = CGFloat(0.45 * m.a) }
                if stile == .pieno && transizione == nil { for ln in m.linee { ln.isHidden = m.a <= 0.5 } }
            }
        }
        // le etichette restano grandi uguali sullo schermo (10 pt), a qualunque distanza
        let altezza = Float(v.bounds.height)
        for e in etichette where !e.isHidden {
            let dist = simd_distance(p, e.simdWorldPosition)
            e.simdScale = SIMD3(repeating: 2 * dist * tan(vf / 2) / altezza)
        }
    }

    // MARK: Stile e materializzazione

    private func applica() {
        for p in parti {
            let s: SCNNode? = stile == .foto ? (p.foto ?? p.pieno) : (stile == .pieno ? p.pieno : nil)
            p.foto?.isHidden = !(s != nil && s === p.foto)
            p.pieno?.isHidden = !(s != nil && s === p.pieno)
            p.fantasma.isHidden = s != nil && transizione == nil
            if let ln = p.linee {
                ln.isHidden = !(s == nil || stile == .pieno || transizione != nil)
                ln.geometry?.materials = [s != nil && stile == .pieno && transizione == nil ? lineaScura : lineaOlo]
            }
        }
    }

    private func materializza() {
        guard stile != nil else { applica(); return }
        transizione = CACurrentMediaTime()
        taglio(dMin - 0.01, verso: -1)
        applica()
    }

    private func taglio(_ v: Float, verso: Float) {
        for m in materialiOlo { m.setValue(NSNumber(value: v), forKey: "taglio"); m.setValue(NSNumber(value: verso), forKey: "verso") }
        for m in materialiSolidi { m.setValue(NSNumber(value: v), forKey: "tagS") }
    }

    // MARK: Materiali

    private static func lineare(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xff) / 255, Float((hex >> 8) & 0xff) / 255, Float(hex & 0xff) / 255)
    }
    static func colore(_ hex: UInt32, _ a: CGFloat = 1) -> UIColor {
        let c = rgb(hex); return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: a)
    }
    private static func f(_ x: Double) -> String { String(format: "%.5ff", x) }
    private var asseShader: String { "float3(\(Self.f(Double(asse.x))), \(Self.f(Double(asse.y))), \(Self.f(Double(asse.z))))" }

    /// L'ologramma del mockup (`holo`): bordo luminoso (fresnel), righe di scansione, il filo del taglio; additivo, senza profondità.
    private var cacheOlo: [String: SCNMaterial] = [:]
    private func olo(_ hex: UInt32, _ alfa: Double = 1) -> SCNMaterial {
        let chiave = "\(hex)-\(alfa)"
        if let m = cacheOlo[chiave] { return m }
        let c = Self.rgb(hex)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.colore(hex)
        m.isDoubleSided = true
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
        #pragma arguments
        float taglio;
        float verso;
        #pragma transparent
        #pragma body
        float4 jvW = scn_frame.inverseViewTransform * float4(_surface.position, 1.0f);
        float jvD = dot(jvW.xyz, \(asseShader));
        if ((jvD - taglio) * verso > 0.0f) { discard_fragment(); }
        float3 jvN = normalize(_surface.normal);
        float jvK = clamp(1.0f - abs(dot(jvN, normalize(_surface.view))), 0.0f, 1.0f);
        float jvFr = jvK * jvK;
        float jvRiga = smoothstep(0.6f, 1.0f, sin(jvW.y * \(Self.f(Double(70 / max(R, 0.05)))) - scn_frame.time * 3.0f) * 0.5f + 0.5f);
        float jvFilo = 1.0f - smoothstep(0.0f, \(Self.f(Double(0.03 * max(R, 0.05)))), abs(jvD - taglio));
        float jvA = clamp((0.05f + jvFr * 0.5f + jvRiga * 0.05f + jvFilo) * \(Self.f(alfa)), 0.0f, 1.0f);
        float3 jvC = float3(\(Self.f(Self.lineare(Double(c.x)))), \(Self.f(Self.lineare(Double(c.y)))), \(Self.f(Self.lineare(Double(c.z))))) * (0.3f + jvFr * 1.5f + jvRiga * 0.3f) + float3(0.85f, 0.97f, 1.0f) * jvFilo * 1.5f;
        _output.color = float4(jvC * jvA, jvA);
        """]
        m.setValue(NSNumber(value: Float(1e6)), forKey: "taglio")
        m.setValue(NSNumber(value: Float(1)), forKey: "verso")
        cacheOlo[chiave] = m
        materialiOlo.append(m)
        return m
    }

    /// Il materiale vero (foto o pieno), col taglio della materializzazione.
    private func solido(_ hex: UInt32 = 0xffffff, trama: UIImage? = nil, metri: Float = 1, ruvido: Float = 0.6, metallo: Float = 0,
                        opacita: CGFloat = 1, emissivo: UInt32? = nil, emissione: CGFloat = 0, doppio: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        if let trama {
            m.diffuse.contents = trama
            m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(1 / metri, 1 / metri, 1)
            m.diffuse.mipFilter = .linear
        } else {
            m.diffuse.contents = Self.colore(hex)
        }
        m.roughness.contents = NSNumber(value: ruvido)
        m.metalness.contents = NSNumber(value: metallo)
        if let emissivo { m.emission.contents = Self.colore(emissivo); m.emission.intensity = emissione }
        m.transparency = opacita
        m.isDoubleSided = doppio
        aggiungiTaglio(m)
        return m
    }
    private func aggiungiTaglio(_ m: SCNMaterial) {
        var mod = m.shaderModifiers ?? [:]
        mod[.fragment] = """
        #pragma arguments
        float tagS;
        #pragma body
        float4 jvWs = scn_frame.inverseViewTransform * float4(_surface.position, 1.0f);
        if (dot(jvWs.xyz, \(asseShader)) > tagS) { discard_fragment(); }
        """
        m.shaderModifiers = mod
        m.setValue(NSNumber(value: Float(1e6)), forKey: "tagS")
        materialiSolidi.append(m)
    }

    private static func linea(_ hex: UInt32, _ alfa: CGFloat, additiva: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = colore(hex)
        m.transparency = alfa
        m.blendMode = additiva ? .add : .alpha
        m.writesToDepthBuffer = false
        return m
    }

    /// Colore semplice (scheletro, polvere, mirino): additivo o normale, senza luce.
    private static func tinta(_ hex: UInt32, _ alfa: CGFloat, additiva: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = colore(hex)
        m.transparency = alfa
        m.blendMode = additiva ? .add : .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    // MARK: Luci (emisfero, sole, controluce ciano) e ambiente per i riflessi del metallo

    private var sole = SCNNode()
    private func luci() {
        let amb = SCNLight(); amb.type = .ambient; amb.color = Self.colore(0x87929c); amb.intensity = 500
        let na = SCNNode(); na.light = amb; scena.rootNode.addChildNode(na)
        let s = SCNLight(); s.type = .directional; s.color = UIColor.white; s.intensity = 1700
        sole.light = s; sole.simdPosition = [-6, 10, 7]; sole.simdLook(at: .zero); scena.rootNode.addChildNode(sole)
        let b = SCNLight(); b.type = .directional; b.color = Self.colore(0x6fe9ff); b.intensity = 600
        let nb = SCNNode(); nb.light = b; nb.simdPosition = [8, 3, -8]; nb.simdLook(at: .zero); scena.rootNode.addChildNode(nb)
        scena.lightingEnvironment.contents = TrameLidar.studio
        scena.lightingEnvironment.intensity = 1
    }

    // MARK: Geometrie (vertici già nel mondo: la nuvola li riusa)

    /// Un quadrilatero con le coordinate della trama in metri; il verso dei triangoli segue la normale voluta.
    private struct Maglia {
        var v: [SIMD3<Float>] = [], n: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], c: [SIMD3<Float>] = []
        var gruppi: [[UInt32]] = [[]]
        mutating func quad(_ p: [SIMD3<Float>], _ normale: SIMD3<Float>, _ uvs: [SIMD2<Float>], gruppo: Int = 0) {
            while gruppi.count <= gruppo { gruppi.append([]) }
            let b = UInt32(v.count)
            v += p; n += Array(repeating: normale, count: 4); uv += uvs
            let giusto = simd_dot(simd_cross(p[1] - p[0], p[2] - p[0]), normale) >= 0
            gruppi[gruppo] += giusto ? [b, b + 1, b + 2, b, b + 2, b + 3] : [b, b + 2, b + 1, b, b + 3, b + 2]
        }
        mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c3: SIMD3<Float>, _ normale: SIMD3<Float>, _ uvs: [SIMD2<Float>], gruppo: Int = 0) {
            while gruppi.count <= gruppo { gruppi.append([]) }
            let k = UInt32(v.count)
            v += [a, b, c3]; n += [normale, normale, normale]; uv += uvs
            let giusto = simd_dot(simd_cross(b - a, c3 - a), normale) >= 0
            gruppi[gruppo] += giusto ? [k, k + 1, k + 2] : [k, k + 2, k + 1]
        }
        func geometria(colori: Bool = false) -> SCNGeometry {
            var fonti = [SCNGeometrySource(vertices: v.map { SCNVector3($0.x, $0.y, $0.z) }),
                         SCNGeometrySource(normals: n.map { SCNVector3($0.x, $0.y, $0.z) })]
            if uv.count == v.count { fonti.append(SCNGeometrySource(textureCoordinates: uv.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })) }
            if colori, c.count == v.count { fonti.append(ScenaLidar.fonteColori(c)) }
            let el = gruppi.filter { !$0.isEmpty }.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
            return SCNGeometry(sources: fonti, elements: el)
        }
        var triangoli: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
            gruppi.flatMap { g in stride(from: 0, to: g.count - 2, by: 3).map { (v[Int(g[$0])], v[Int(g[$0 + 1])], v[Int(g[$0 + 2])]) } }
        }
    }

    static func fonteColori(_ c: [SIMD3<Float>]) -> SCNGeometrySource {
        // sRGB → lineare: i colori dei vertici SceneKit li prende lineari
        var dati = [Float](); dati.reserveCapacity(c.count * 3)
        for x in c { dati += [Float(lineare(Double(x.x))), Float(lineare(Double(x.y))), Float(lineare(Double(x.z)))] }
        let d = dati.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: d, semantic: .color, vectorCount: c.count, usesFloatComponents: true,
                                 componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                 dataStride: MemoryLayout<Float>.size * 3)
    }

    /// Un parallelepipedo: centro, asse x (lungo), dimensioni (x, y, z); y è sempre la verticale.
    private func scatola(_ c: SIMD3<Float>, _ dim: SIMD3<Float>, asseX: SIMD3<Float> = [1, 0, 0]) -> (Maglia, [SIMD3<Float>]) {
        let ux = simd_normalize(asseX), uy = SIMD3<Float>(0, 1, 0), uz = simd_cross(ux, uy)
        let h = dim / 2
        func p(_ a: Float, _ b: Float, _ cz: Float) -> SIMD3<Float> { c + ux * (a * h.x) + uy * (b * h.y) + uz * (cz * h.z) }
        var m = Maglia()
        // facce: ±x (d × h), ±y (w × d), ±z (w × h), uv in metri
        m.quad([p(1, -1, 1), p(1, -1, -1), p(1, 1, -1), p(1, 1, 1)], ux, [[0, 0], [dim.z, 0], [dim.z, dim.y], [0, dim.y]])
        m.quad([p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1)], -ux, [[0, 0], [dim.z, 0], [dim.z, dim.y], [0, dim.y]])
        m.quad([p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), p(-1, 1, -1)], uy, [[0, 0], [dim.x, 0], [dim.x, dim.z], [0, dim.z]])
        m.quad([p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1)], -uy, [[0, 0], [dim.x, 0], [dim.x, dim.z], [0, dim.z]])
        m.quad([p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)], uz, [[0, 0], [dim.x, 0], [dim.x, dim.y], [0, dim.y]])
        m.quad([p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1)], -uz, [[0, 0], [dim.x, 0], [dim.x, dim.y], [0, dim.y]])
        let spigoli = [p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1), p(-1, 1, -1), p(1, 1, -1), p(1, 1, 1), p(-1, 1, 1)]
        return (m, spigoli)
    }

    private func bordiScatola(_ s: [SIMD3<Float>]) -> SCNGeometry {
        let coppie: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
        return segmenti(coppie.flatMap { [s[$0.0], s[$0.1]] })
    }
    private func segmenti(_ punti: [SIMD3<Float>]) -> SCNGeometry {
        let fonte = SCNGeometrySource(vertices: punti.map { SCNVector3($0.x, $0.y, $0.z) })
        let idx = (0..<UInt32(punti.count)).map { $0 }
        return SCNGeometry(sources: [fonte], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
    }

    /// Una parte: solido FOTO e PIENO (materiali diversi, anche più di uno per gli elementi) e fantasma olografico.
    @discardableResult
    private func parte(_ g: SCNGeometry, foto: [SCNMaterial]?, pieno: [SCNMaterial]?, olo coloreOlo: UInt32 = 0x4fe3ff, alfa: Double = 1,
                       bordi: SCNGeometry? = nil, tri: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [], in genitore: SCNNode? = nil,
                       geoFoto: SCNGeometry? = nil) -> (foto: SCNNode?, pieno: SCNNode?, linee: SCNNode?) {
        let dove = genitore ?? radice
        func nodo(_ mats: [SCNMaterial], _ geo: SCNGeometry) -> SCNNode {
            let c = geo.copy() as? SCNGeometry ?? geo
            c.materials = mats
            let n = SCNNode(geometry: c); dove.addChildNode(n); return n
        }
        let nf = foto.map { nodo($0, geoFoto ?? g) }
        let np = pieno.map { nodo($0, g) }
        let fan = nodo([olo(coloreOlo, alfa)], g)
        fan.renderingOrder = 10
        var nl: SCNNode?
        if let bordi {
            bordi.materials = [lineaOlo]
            let n = SCNNode(geometry: bordi); n.renderingOrder = 20; dove.addChildNode(n); nl = n
        }
        parti.append(Parte(foto: nf, pieno: np, fantasma: fan, linee: nl))
        triangoli += tri
        return (nf, np, nl)
    }

    @discardableResult
    private func scatolaParte(_ c: SIMD3<Float>, _ dim: SIMD3<Float>, asseX: SIMD3<Float> = [1, 0, 0], foto: SCNMaterial?, pieno: SCNMaterial?,
                              olo: UInt32 = 0x4fe3ff, bordi: Bool = true, in g: SCNNode? = nil) -> (foto: SCNNode?, pieno: SCNNode?, linee: SCNNode?) {
        let (m, s) = scatola(c, dim, asseX: asseX)
        return parte(m.geometria(), foto: foto.map { [$0] }, pieno: pieno.map { [$0] }, olo: olo, bordi: bordi ? bordiScatola(s) : nil, tri: m.triangoli, in: g)
    }

    /// Una linea (quota, porta, bordo): visibile solo nel risultato.
    @discardableResult
    private func linea(_ punti: [SIMD3<Float>], _ hex: UInt32 = 0x4fe3ff, _ alfa: CGFloat = 0.95, tratteggio: Float = 0) -> SCNNode {
        var seg: [SIMD3<Float>] = []
        for i in 0..<max(0, punti.count - 1) {
            let a = punti[i], b = punti[i + 1]
            if tratteggio > 0 {
                let l = simd_distance(a, b), u = (b - a) / max(l, 0.0001)
                var t: Float = 0
                while t < l { seg += [a + u * t, a + u * min(l, t + tratteggio)]; t += tratteggio * 2 }
            } else { seg += [a, b] }
        }
        let g = segmenti(seg)
        g.materials = [Self.linea(hex, alfa, additiva: false)]
        let n = SCNNode(geometry: g); n.renderingOrder = 30
        radice.addChildNode(n); sopra.append(n)
        return n
    }

    /// Quota con le stanghette alle estremità e l'etichetta a metà.
    private func quota(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ testo: String, _ su: SIMD3<Float>, _ stile: EtichettaOlo.Stile = .normale) {
        let t = su * 0.04
        linea([a, b]); linea([a - t, a + t]); linea([b - t, b + t])
        etichetta(testo, (a + b) / 2, stile)
    }

    /// Il cartellino del mockup (la «.et»): sempre davanti, guarda la camera, alto 10 pt sullo schermo.
    private func etichetta(_ testo: String, _ p: SIMD3<Float>, _ stile: EtichettaOlo.Stile = .normale) {
        let r = ImageRenderer(content: EtichettaOlo(testo: testo, stile: stile).padding(6))
        r.scale = 3
        guard let img = r.cgImage else { return }
        let piano = SCNPlane(width: CGFloat(img.width) / 3, height: CGFloat(img.height) / 3)     // in punti: la scala la mette il giro
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.blendMode = .alpha
        piano.materials = [m]
        let n = SCNNode(geometry: piano)
        n.simdPosition = p
        n.simdScale = SIMD3(repeating: 0.001)
        n.constraints = [SCNBillboardConstraint()]
        n.renderingOrder = 100
        scena.rootNode.addChildNode(n)                 // fuori da «radice»: non allargano l'inquadratura
        etichette.append(n)
    }

    // MARK: Le trame «fotografiche» (disegnate una volta, sempre uguali)

    private lazy var parquet = solido(trama: TrameLidar.immagine("parquet"), metri: 2.4, ruvido: 0.55)
    private lazy var latoPavimento = solido(0x3b2a1c, ruvido: 0.9)

    // MARK: - I modelli

    /// Interno ed Evento: pavimento, pareti con porte e finestre, pilastrini d'angolo; la casa delle bambole.
    @discardableResult
    private func costruisciStanza(_ s: StanzaScena, porte colPorte: UInt32, muro colMuro: UInt32) -> SIMD2<Double> {
        guard s.pavimento.count >= 3 || !s.pareti.isEmpty else { return .zero }
        let tutti = s.pavimento + s.pareti.flatMap { [SIMD2($0.ax, $0.az), SIMD2($0.bx, $0.bz)] }
        let mn = tutti.reduce(SIMD2(Double.infinity, .infinity)) { simd_min($0, $1) }, mx = tutti.reduce(SIMD2(-Double.infinity, -.infinity)) { simd_max($0, $1) }
        let c0 = (mn + mx) / 2
        func P(_ q: SIMD2<Double>) -> SIMD2<Float> { SIMD2(Float(q.x - c0.x), Float(q.y - c0.y)) }
        let poli = s.pavimento.map(P)
        let h = Float(s.altezza), t: Float = 0.15
        // il pavimento: lastra di 12 cm, parquet sopra
        if poli.count >= 3 {
            let m = lastra(poli, spessore: 0.12)
            parte(m.geometria(), foto: [parquet, latoPavimento], pieno: [solido(0x1c5866, ruvido: 0.8), solido(0x0f3540, ruvido: 0.8)], tri: m.triangoli)
        }
        let centro = poli.count >= 3 ? GeometriaPiana.baricentro(poli) : SIMD2<Float>(0, 0)
        var angoli: [SIMD2<Float>] = []
        for w in s.pareti {
            let a = P(SIMD2(w.ax, w.az)), b = P(SIMD2(w.bx, w.bz)), L = simd_distance(a, b)
            guard L > 0.05 else { continue }
            let u = (b - a) / L
            var nrm = SIMD2<Float>(u.y, -u.x)
            if simd_dot(nrm, (a + b) / 2 - centro) < 0 { nrm = -nrm }                // la normale verso fuori
            let gruppo = SCNNode(); radice.addChildNode(gruppo)
            let muro = Muro(nrm)
            let mF = solido(trama: TrameLidar.immagine("intonaco"), metri: 2, ruvido: 0.92)
            let mP = solido(colMuro, ruvido: 0.6)
            let vetro = solido(0x9cc9e2, ruvido: 0.08, metallo: 0.3, opacita: 0.45)
            muro.materiali = [mF, mP]; muro.vetri = [vetro]
            // le aperture su questa parete: porte (0 → 2,2 m) e finestre (1,0 → 2,4 m), o le altezze vere se ci sono
            struct Apertura { var da: Float; var l: Float; var y0: Float; var y1: Float; var porta: Bool }
            var aperture: [Apertura] = []
            func suParete(_ q: TrattoPianta, porta: Bool) {
                let pa = P(SIMD2(q.ax, q.az)), pb = P(SIMD2(q.bx, q.bz))
                let fuoriA = abs(simd_dot(pa - a, nrm)), fuoriB = abs(simd_dot(pb - a, nrm))
                guard fuoriA < 0.3, fuoriB < 0.3 else { return }
                var da = simd_dot(pa - a, u), fino = simd_dot(pb - a, u)
                if da > fino { swap(&da, &fino) }
                da = max(0.02, da); fino = min(L - 0.02, fino)
                guard fino - da > 0.2 else { return }
                let y0 = q.basso.map { Float(max(0, $0)) } ?? (porta ? 0 : 1)
                let y1 = q.alto.map { Float(min(Double(h) - 0.02, $0)) } ?? (porta ? min(2.2, h - 0.05) : min(2.4, h - 0.05))
                guard y1 - y0 > 0.2 else { return }
                aperture.append(Apertura(da: da, l: fino - da, y0: y0, y1: y1, porta: porta))
            }
            s.porte.forEach { suParete($0, porta: true) }
            s.finestre.forEach { suParete($0, porta: false) }
            let tagli = Array(Set([0, L] + aperture.flatMap { [$0.da, $0.da + $0.l] })).sorted()
            for k in 0..<(tagli.count - 1) {
                let x0 = tagli[k], x1 = tagli[k + 1], mid = (x0 + x1) / 2
                guard x1 - x0 > 0.005 else { continue }
                let ap = aperture.first { mid > $0.da && mid < $0.da + $0.l }
                let fasce: [(Float, Float)] = ap.map { (a: Apertura) -> [(Float, Float)] in [(Float(0), a.y0), (a.y1, h)] } ?? [(Float(0), h)]
                let p2 = a + u * mid + nrm * (t / 2)
                for (y0, y1) in fasce where y1 - y0 > 0.01 {
                    let r = scatolaParte(SIMD3(p2.x, (y0 + y1) / 2, p2.y), SIMD3(x1 - x0, y1 - y0, t), asseX: SIMD3(u.x, 0, u.y), foto: mF, pieno: mP, in: gruppo)
                    if let n = r.foto { muro.nodi.append(n) }
                    if let n = r.pieno { muro.nodi.append(n) }
                    if let n = r.linee { muro.linee.append(n) }
                }
                if let ap, !ap.porta {
                    _ = scatolaParte(SIMD3(p2.x, (ap.y0 + ap.y1) / 2, p2.y), SIMD3(x1 - x0, ap.y1 - ap.y0, 0.02), asseX: SIMD3(u.x, 0, u.y),
                                     foto: vetro, pieno: vetro, olo: 0xbdf3ff, bordi: false, in: gruppo)
                }
                if let ap, ap.porta {                                                 // il varco: arancio, o verde con «USCITA» nell'allestimento
                    let q = a + u * x0, r = a + u * x1
                    linea([SIMD3(q.x, 0, q.y), SIMD3(q.x, ap.y1, q.y), SIMD3(r.x, ap.y1, r.y), SIMD3(r.x, 0, r.y)], colPorte, 1)
                    if colPorte != 0xffb45a {
                        let piano = SCNPlane(width: CGFloat(x1 - x0), height: CGFloat(ap.y1))
                        piano.materials = [Self.tinta(colPorte, 0.22)]
                        let v = SCNNode(geometry: piano)
                        let pv = a + u * mid
                        v.simdPosition = SIMD3(pv.x, ap.y1 / 2, pv.y)
                        v.simdEulerAngles = SIMD3(0, atan2(-u.y, u.x), 0)
                        radice.addChildNode(v); sopra.append(v)
                        let pe = a + u * mid - nrm * 0.6
                        etichetta("USCITA", SIMD3(pe.x, ap.y1 + 0.4, pe.y), .verde)
                    }
                }
            }
            // i pilastrini d'angolo chiudono le giunture
            for q in [a, b] {
                let pq = q + nrm * (t / 2)
                guard !angoli.contains(where: { simd_distance($0, pq) < 0.12 }) else { continue }
                angoli.append(pq)
                let r = scatolaParte(SIMD3(pq.x, h / 2, pq.y), SIMD3(t, h, t), foto: mF, pieno: mP, bordi: false, in: gruppo)
                if let n = r.foto { muro.nodi.append(n) }
                if let n = r.pieno { muro.nodi.append(n) }
            }
            muri.append(muro)
        }
        return SIMD2(c0.x, c0.y)
    }

    /// Una lastra orizzontale dal poligono: sopra a y = 0, sotto a y = −spessore (gruppo 0 sopra e sotto, gruppo 1 i lati).
    private func lastra(_ p: [SIMD2<Float>], spessore: Float) -> Maglia {
        var m = Maglia()
        let ccw = GeometriaPiana.areaConSegno(p) > 0 ? p : Array(p.reversed())
        for (i, j, k) in GeometriaPiana.triangola(ccw) {
            let a = ccw[i], b = ccw[j], c = ccw[k]
            m.tri(SIMD3(a.x, 0, a.y), SIMD3(b.x, 0, b.y), SIMD3(c.x, 0, c.y), [0, 1, 0], [a, b, c])
            m.tri(SIMD3(a.x, -spessore, a.y), SIMD3(b.x, -spessore, b.y), SIMD3(c.x, -spessore, c.y), [0, -1, 0], [a, b, c])
        }
        for i in 0..<ccw.count {
            let a = ccw[i], b = ccw[(i + 1) % ccw.count], L = simd_distance(a, b)
            guard L > 0.001 else { continue }
            let d = (b - a) / L
            let fuori = SIMD3<Float>(d.y, 0, -d.x)                                    // ccw nel piano (x, z): fuori è a destra
            m.quad([SIMD3(a.x, -spessore, a.y), SIMD3(b.x, -spessore, b.y), SIMD3(b.x, 0, b.y), SIMD3(a.x, 0, a.y)], fuori,
                   [[0, 0], [L, 0], [L, spessore], [0, spessore]], gruppo: 1)
        }
        return m
    }

    private func etichettaArea(_ area: Double, _ p: SIMD3<Float>) { etichetta(LidarFormato.n(area) + " m²", p, .grande) }

    // Interno
    private func interno(_ s: StanzaScena) {
        let c = costruisciStanza(s, porte: 0xffb45a, muro: 0x4fd2ee)
        if s.pavimento.count >= 3 {
            // la quota dell'altezza vicino al secondo angolo, verso dentro; l'area al centro
            let n = s.pavimento.count
            let v = s.pavimento[1 % n], verso = GeometriaPiana.baricentro(s.pavimento) - v
            let dentro = simd_length(verso) > 0.01 ? simd_normalize(verso) * 0.64 : SIMD2<Double>(0, 0)
            let e = SIMD2<Float>(Float(v.x - c.x + dentro.x), Float(v.y - c.y + dentro.y))
            quota(SIMD3(e.x, 0, e.y), SIMD3(e.x, Float(s.altezza), e.y), LidarFormato.m(s.altezza, 2), [1, 0, 0])
            let g = GeometriaPiana.puntoInterno(s.pavimento.map { SIMD2<Float>(Float($0.x - c.x), Float($0.y - c.y)) })
            etichettaArea(s.area, SIMD3(g.x, 0.3, g.y))
        }
        inclinazioneBase = 0.82; k = 0.98; campioni = 9000
    }

    // Setup: la stanza con le uscite in verde, palco con americana, console, bar, stand 3×3, passaggi da 1,2 m
    private func evento(_ s: StanzaScena, _ a: Allestimento) {
        let c = costruisciStanza(s, porte: 0x78e696, muro: 0x1d6577)
        func at(_ r: RettangoloPiano, _ y: Float) -> SIMD3<Float> { SIMD3(Float(r.centro.x - c.x), y, Float(r.centro.y - c.y)) }
        func direzione(_ r: RettangoloPiano) -> SIMD3<Float> { SIMD3(Float(r.asse.x), 0, Float(r.asse.y)) }
        let allu = solido(0xc9ced3, ruvido: 0.32, metallo: 0.85)
        if let p = a.palco {
            let w = Float(p.lungo), d = Float(p.largo), ax = direzione(p), az = simd_cross(ax, [0, 1, 0])
            let cc = at(p, 0.3)
            scatolaParte(cc, [w, 0.6, d], asseX: ax, foto: solido(trama: TrameLidar.immagine("palco"), metri: 1, ruvido: 0.85), pieno: solido(0xffb45a), olo: 0xffb45a)
            for sx in [Float(-1), 1] { for sz in [Float(-1), 1] {
                let q = cc + ax * (sx * (w / 2 - 0.11)) + az * (sz * (d / 2 - 0.11))
                scatolaParte(SIMD3(q.x, 1.6, q.z), [0.22, 3.2, 0.22], asseX: ax, foto: allu, pieno: solido(0xffd29c), olo: 0xffb45a, bordi: false)
            } }
            // l'americana in alto: una trave per lato corto e una lungo il fronte (verso la sala)
            for sx in [Float(-1), 1] {
                let q = cc + ax * (sx * (w / 2 - 0.11))
                scatolaParte(SIMD3(q.x, 3.2, q.z), [0.22, 0.22, d], asseX: ax, foto: allu, pieno: solido(0xffd29c), olo: 0xffb45a, bordi: false)
            }
            let q = cc - az * (Float(p.versoMuro) * (d / 2 - 0.11))
            scatolaParte(SIMD3(q.x, 3.2, q.z), [w, 0.22, 0.22], asseX: ax, foto: allu, pieno: solido(0xffd29c), olo: 0xffb45a, bordi: false)
            etichetta("PALCO", at(p, 3.7))
        }
        if let cons = a.console {
            let ax = direzione(cons)
            scatolaParte(at(cons, 0.5), [Float(cons.lungo), 1.0, min(0.8, Float(cons.largo))], asseX: ax, foto: solido(0x121416, ruvido: 0.5), pieno: solido(0xffb45a), olo: 0xffb45a)
            let disco = solido(0x1d2124, ruvido: 0.3, emissivo: 0x4fe3ff, emissione: 0.5)
            for dx in [Float(-0.42), 0.42] {
                let cil = SCNCylinder(radius: 0.15, height: 0.03); cil.radialSegmentCount = 32
                let p = at(cons, 1.02) + ax * dx
                let nf = SCNNode(geometry: cil.copy() as? SCNGeometry); nf.geometry?.materials = [disco]; nf.simdPosition = p
                let np = SCNNode(geometry: cil.copy() as? SCNGeometry); np.geometry?.materials = [solido(0xffe2bd)]; np.simdPosition = p
                let nfan = SCNNode(geometry: cil.copy() as? SCNGeometry); nfan.geometry?.materials = [olo(0xffb45a)]; nfan.simdPosition = p
                [nf, np, nfan].forEach { radice.addChildNode($0) }
                parti.append(Parte(foto: nf, pieno: np, fantasma: nfan, linee: nil))
            }
            etichetta("DJ", at(cons, 1.3))
        }
        if let b = a.bar {
            let ax = direzione(b), az = simd_cross(ax, [0, 1, 0]), d = Float(b.largo), w = Float(b.lungo)
            let legno = solido(trama: TrameLidar.immagine("noce"), metri: 1, ruvido: 0.55), viola = solido(0xaa8cff, ruvido: 0.6)
            let verso = Float(b.versoMuro)                                         // il muro sta da −az (−1) o da +az (+1)
            let cMuro = at(b, 0.9) + az * (verso * (d / 2 - 0.175)), cBanco = at(b, 0.54) - az * (verso * (d / 2 - 0.3))
            scatolaParte(cMuro, [w, 1.8, 0.35], asseX: ax, foto: legno, pieno: viola, olo: 0xaa8cff)
            scatolaParte(cBanco, [w, 1.08, 0.6], asseX: ax, foto: legno, pieno: viola, olo: 0xaa8cff)
            scatolaParte(SIMD3(cBanco.x, 1.1, cBanco.z), [w + 0.1, 0.05, 0.72], asseX: ax, foto: solido(0xd8d4cc, ruvido: 0.25, metallo: 0.1), pieno: solido(0xd4c8ff), olo: 0xaa8cff, bordi: false)
            etichetta("BAR", at(b, 2.2))
        }
        for (i, st) in a.stand.enumerated() {
            let ax = direzione(st), az = simd_cross(ax, [0, 1, 0]), cc = at(st, 0)
            let bianco = solido(0xeeeeec, ruvido: 0.85), ciano = solido(0x4fe3ff, ruvido: 0.6)
            scatolaParte(SIMD3(cc.x, 0.02, cc.z), [3, 0.04, 3], asseX: ax, foto: solido(trama: TrameLidar.immagine("moquette"), metri: 1, ruvido: 0.95), pieno: solido(0x1d6c7e), bordi: false)
            let retro = cc + az * (Float(st.versoMuro) * 1.475)
            scatolaParte(SIMD3(retro.x, 1.25, retro.z), [3, 2.5, 0.05], asseX: ax, foto: bianco, pieno: ciano)
            for sx in [Float(-1), 1] {
                let q = cc + ax * (sx * 1.475)
                scatolaParte(SIMD3(q.x, 1.25, q.z), [0.05, 2.5, 3], asseX: ax, foto: bianco, pieno: ciano)
            }
            let allu2 = solido(0xc9ced3, ruvido: 0.32, metallo: 0.85)
            for sx in [Float(-1), 1] { for sz in [Float(-1), 1] {
                let q = cc + ax * (sx * 1.48) + az * (sz * 1.48)
                scatolaParte(SIMD3(q.x, 1.27, q.z), [0.04, 2.55, 0.04], asseX: ax, foto: allu2, pieno: solido(0xbff4ff), bordi: false)
            } }
            if i == min(1, a.stand.count - 1) { etichetta("STAND", at(st, 2.9)) }
        }
        for p in a.passaggi {                                                            // i passaggi da 1,2 m, tratteggiati in verde
            linea([SIMD3(Float(p.0.x - c.x), 0.03, Float(p.0.y - c.y)), SIMD3(Float(p.1.x - c.x), 0.03, Float(p.1.y - c.y))], 0x78e696, 1, tratteggio: 0.25)
        }
        inclinazioneBase = 0.9; k = 0.98; campioni = 7000
    }

    // Esterno: il terreno come plastico, quote ×3, il taglio del terreno ai lati
    private func esterno(_ t: TerrenoScena) {
        let ES: Float = 3
        let xs = t.bordo.map(\.x), zs = t.bordo.map(\.y)
        let cx = Float(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2), cz = Float(((zs.min() ?? 0) + (zs.max() ?? 0)) / 2)
        let qmed = t.quote.isEmpty ? 0 : t.quote.sorted()[t.quote.count / 2]
        func quota3(_ i: Int, _ j: Int) -> Float { (t.quote[j * t.nx + i] - qmed) * ES }
        let poli = t.bordo.map { SIMD2<Float>(Float($0.x) - cx, Float($0.y) - cz) }
        func pos(_ i: Int, _ j: Int) -> SIMD2<Float> {
            SIMD2(Float(t.origine.x + (Double(i) + 0.5) * t.passo) - cx, Float(t.origine.y + (Double(j) + 0.5) * t.passo) - cz)
        }
        let hmin = t.quote.map { ($0 - qmed) * ES }.min() ?? 0, hmax = t.quote.map { ($0 - qmed) * ES }.max() ?? 0
        let base = min(-0.45, hmin - 0.25)
        var m = Maglia(), mp = Maglia()
        let c0 = Self.rgb(0x0a2f39), c1 = Self.rgb(0x5fe6ff)
        func livello(_ y: Float) -> SIMD3<Float> {
            let f = hmax > hmin ? Float(Int((y - hmin) / (hmax - hmin) * 9)) / 8 : 0.5
            return c0 + (c1 - c0) * min(1, f)
        }
        for j in 0..<(t.nz - 1) { for i in 0..<(t.nx - 1) {
            let q = [pos(i, j), pos(i + 1, j), pos(i + 1, j + 1), pos(i, j + 1)]
            let centro = (q[0] + q[2]) / 2
            guard GeometriaPiana.dentro(centro, poli) else { continue }
            let y = [quota3(i, j), quota3(i + 1, j), quota3(i + 1, j + 1), quota3(i, j + 1)]
            let v = (0..<4).map { SIMD3(q[$0].x, y[$0], q[$0].y) }
            let nrm = simd_normalize(simd_cross(v[3] - v[0], v[1] - v[0]) + simd_cross(v[1] - v[2], v[3] - v[2]))
            let nn = nrm.y < 0 ? -nrm : nrm
            let uv = q
            m.quad(v, nn, uv); mp.quad(v, nn, uv)
            if let col = t.colori {
                m.c += [col[j * t.nx + i], col[j * t.nx + i + 1], col[(j + 1) * t.nx + i + 1], col[(j + 1) * t.nx + i]]
            }
            mp.c += y.map(livello)
        }}
        if !m.v.isEmpty {
            let fotoMat = solido(0xffffff, ruvido: 0.95, doppio: true)
            let pienoMat = solido(0xffffff, ruvido: 0.7, doppio: true)
            let geoP = mp.geometria(colori: true)
            let geoF = m.geometria(colori: t.colori != nil)
            parte(geoP, foto: [t.colori != nil ? fotoMat : solido(trama: TrameLidar.immagine("erba"), metri: 1.2, ruvido: 0.95, doppio: true)], pieno: [pienoMat],
                  tri: m.triangoli, geoFoto: geoF)
        }
        // il taglio laterale, dal prato giù fino alla base, e il filo del bordo
        var lato = Maglia(); var filo: [SIMD3<Float>] = []
        func altezza(_ p: SIMD2<Float>) -> Float {
            let i = Int(((Double(p.x + cx) - t.origine.x) / t.passo - 0.5).rounded()), j = Int(((Double(p.y + cz) - t.origine.y) / t.passo - 0.5).rounded())
            return quota3(max(0, min(t.nx - 1, i)), max(0, min(t.nz - 1, j)))
        }
        let ccw = GeometriaPiana.areaConSegno(poli) > 0 ? poli : Array(poli.reversed())
        var s0: Float = 0
        for i in 0..<ccw.count {
            let a = ccw[i], b = ccw[(i + 1) % ccw.count], L = simd_distance(a, b)
            let n = max(1, Int(ceil(L / 0.2)))
            for k in 0..<n {
                let A = a + (b - a) * (Float(k) / Float(n)), B = a + (b - a) * (Float(k + 1) / Float(n))
                let ha = altezza(A), hb = altezza(B), d = simd_normalize(B - A)
                lato.quad([SIMD3(A.x, base, A.y), SIMD3(B.x, base, B.y), SIMD3(B.x, hb, B.y), SIMD3(A.x, ha, A.y)], SIMD3(d.y, 0, -d.x),
                          [[s0, 0], [s0 + 0.2, 0], [s0 + 0.2, hb - base], [s0, ha - base]])
                s0 += 0.2
                filo.append(SIMD3(A.x, ha + 0.03, A.y))
            }
        }
        if !lato.v.isEmpty {
            parte(lato.geometria(), foto: [solido(trama: TrameLidar.immagine("terra"), metri: 0.8, ruvido: 1, doppio: true)], pieno: [solido(0x0f3d48, ruvido: 0.8, doppio: true)], tri: lato.triangoli)
        }
        if let primo = filo.first { linea(filo + [primo], 0x7feeff, 0.9) }
        // il punto più alto: la linea ambra e il dislivello
        if let k = t.quote.indices.filter({ GeometriaPiana.dentro(pos($0 % t.nx, $0 / t.nx), poli) }).max(by: { t.quote[$0] < t.quote[$1] }) {
            let p = pos(k % t.nx, k / t.nx), y = (t.quote[k] - qmed) * ES
            linea([SIMD3(p.x, y, p.y), SIMD3(p.x, y + 0.9, p.y)], 0xffb45a, 1)
            etichetta("Δ " + LidarFormato.cm(t.dislivello), SIMD3(p.x, y + 1.05, p.y), .ambra)
        }
        let g = GeometriaPiana.puntoInterno(poli)
        etichettaArea(t.area, SIMD3(g.x, altezza(g) + 0.4, g.y))
        tag = "RILIEVO ×3"
        sole.simdPosition = [-8, 4.5, 2]; sole.simdLook(at: .zero)                  // luce radente: si legge il rilievo
        inclinazioneBase = 0.62; k = 0.82; asse = [1, 0, 0]; campioni = 7000
    }

    // Oggetto: la maglia vera del LiDAR, foto (i colori dei vertici presi dalla fotocamera) o colore pieno
    private func oggetto(_ o: OggettoScena) {
        let n = SCNGeometrySource(normals: Self.normali(o.vertici, o.indici).map { SCNVector3($0.x, $0.y, $0.z) })
        let v = SCNGeometrySource(vertices: o.vertici.map { SCNVector3($0.x, $0.y, $0.z) })
        let el = SCNGeometryElement(indices: o.indici, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [v, n], elements: [el])
        var geoF: SCNGeometry? = nil
        if let c = o.colori, c.count == o.vertici.count { geoF = SCNGeometry(sources: [v, n, Self.fonteColori(c)], elements: [el]) }
        var tri: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for k in stride(from: 0, to: o.indici.count - 2, by: 3) { tri.append((o.vertici[Int(o.indici[k])], o.vertici[Int(o.indici[k + 1])], o.vertici[Int(o.indici[k + 2])])) }
        parte(geo, foto: geoF != nil ? [solido(0xffffff, ruvido: 0.7, doppio: true)] : nil, pieno: [solido(0x2fb8d6, ruvido: 0.55, doppio: true)], tri: tri, geoFoto: geoF)
        let l = o.largo, p = o.profondo, h = o.alto
        quota([-l / 2, 0, p / 2 + 0.1], [l / 2, 0, p / 2 + 0.1], LidarFormato.cm(Double(l)), [0, 0, 1])
        quota([l / 2 + 0.1, 0, -p / 2], [l / 2 + 0.1, 0, p / 2], LidarFormato.cm(Double(p)), [1, 0, 0])
        quota([l / 2 + 0.15, 0, p / 2 + 0.15], [l / 2 + 0.15, h, p / 2 + 0.15], LidarFormato.cm(Double(h)), [1, 0, 0])
        inclinazioneBase = 0.42; k = 0.9; campioni = 4500
    }

    static func normali(_ v: [SIMD3<Float>], _ idx: [UInt32]) -> [SIMD3<Float>] {
        var n = [SIMD3<Float>](repeating: .zero, count: v.count)
        for k in stride(from: 0, to: idx.count - 2, by: 3) {
            let a = Int(idx[k]), b = Int(idx[k + 1]), c = Int(idx[k + 2])
            guard a < v.count, b < v.count, c < v.count else { continue }
            let f = simd_cross(v[b] - v[a], v[c] - v[a])
            n[a] += f; n[b] += f; n[c] += f
        }
        return n.map { let l = simd_length($0); return l > 0 ? $0 / l : SIMD3(0, 1, 0) }
    }

    // L'anteprima di Oggetto: il flight case del mockup (laminato, profili e angolari in alluminio, maniglia, chiusure a farfalla)
    private func cassa() {
        let l: Float = 0.8, p: Float = 0.6, h: Float = 0.55, e: Float = 0.03
        let lam = solido(trama: TrameLidar.immagine("laminato"), metri: 0.5, ruvido: 0.7), cia = solido(0x2fb8d6, ruvido: 0.55)
        let al = solido(0xcfd4d8, ruvido: 0.3, metallo: 0.9), alP = solido(0xa6efff, ruvido: 0.4)
        let cr = solido(0xe8ecef, ruvido: 0.15, metallo: 1), scuro = solido(0x0d0f11, ruvido: 0.6)
        scatolaParte([0, h / 2, 0], [l - 0.006, h - 0.006, p - 0.006], foto: lam, pieno: cia)
        for y in [Float(0), h] { for z in [-p / 2, p / 2] { scatolaParte([0, y, z], [l - 2 * e, e, e], foto: al, pieno: alP, bordi: false) } }
        for x in [-l / 2, l / 2] { for z in [-p / 2, p / 2] { scatolaParte([x, h / 2, z], [e, h - 2 * e, e], foto: al, pieno: alP, bordi: false) } }
        for x in [-l / 2, l / 2] { for y in [Float(0), h] { scatolaParte([x, y, 0], [e, e, p - 2 * e], foto: al, pieno: alP, bordi: false) } }
        let giunto = h - 0.14
        for z in [-p / 2, p / 2] { scatolaParte([0, giunto, z], [l - 2 * e, 0.024, 0.012], foto: al, pieno: alP, bordi: false) }
        for x in [-l / 2, l / 2] { scatolaParte([x, giunto, 0], [0.012, 0.024, p - 2 * e], foto: al, pieno: alP, bordi: false) }
        for x in [-l / 2, l / 2] { for y in [Float(0), h] { for z in [-p / 2, p / 2] {
            let s = SCNSphere(radius: 0.03); s.segmentCount = 20
            primitiva(s, [x, y, z], foto: cr, pieno: alP)
        } } }
        scatolaParte([0, h + 0.006, 0], [0.22, 0.012, 0.08], foto: scuro, pieno: alP, bordi: false)
        let man = SCNCylinder(radius: 0.012, height: 0.16); man.radialSegmentCount = 16
        primitiva(man, [0, h + 0.03, 0], rot: [0, 0, .pi / 2], foto: cr, pieno: alP)
        for z in [-p / 2 - 0.006, p / 2 + 0.006] { for x in [Float(-0.22), 0.22] { scatolaParte([x, giunto, z], [0.07, 0.07, 0.012], foto: cr, pieno: alP, bordi: false) } }
        quota([-l / 2, 0, p / 2 + 0.1], [l / 2, 0, p / 2 + 0.1], "80 cm", [0, 0, 1])
        quota([l / 2 + 0.1, 0, -p / 2], [l / 2 + 0.1, 0, p / 2], "60 cm", [1, 0, 0])
        quota([l / 2 + 0.15, 0, p / 2 + 0.15], [l / 2 + 0.15, h, p / 2 + 0.15], "55 cm", [1, 0, 0])
        inclinazioneBase = 0.42; k = 0.9; campioni = 4500
    }

    private func primitiva(_ g: SCNGeometry, _ p: SIMD3<Float>, rot: SIMD3<Float>? = nil, foto: SCNMaterial, pieno: SCNMaterial, olo coloreOlo: UInt32 = 0x4fe3ff) {
        func nodo(_ m: SCNMaterial) -> SCNNode {
            let c = g.copy() as? SCNGeometry ?? g; c.materials = [m]
            let n = SCNNode(geometry: c); n.simdPosition = p; if let rot { n.simdEulerAngles = rot }
            radice.addChildNode(n); return n
        }
        parti.append(Parte(foto: nodo(foto), pieno: nodo(pieno), fantasma: nodo(olo(coloreOlo)), linee: nil))
    }

    // Corpo › Texture: il modello fotografico (Object Capture) o, in anteprima, la persona d'esempio con la texture dipinta
    private func statua(_ url: URL?, altezza: Float) {
        var h = altezza
        if let url, let modello = try? SCNScene(url: url, options: [.checkConsistency: true]) {
            let foto = SCNNode()
            for n in modello.rootNode.childNodes { foto.addChildNode(n) }
            // a terra e al centro
            let (lo, hi) = foto.boundingBox
            foto.simdPosition = SIMD3(-(Float(lo.x) + Float(hi.x)) / 2, -Float(lo.y), -(Float(lo.z) + Float(hi.z)) / 2)
            h = Float(hi.y - lo.y)
            let pieno = foto.clone(), fan = foto.clone()
            func rivesti(_ radiceNodo: SCNNode, _ mat: @escaping (SCNMaterial) -> SCNMaterial) {
                radiceNodo.enumerateHierarchy { n, _ in
                    guard let g = n.geometry?.copy() as? SCNGeometry else { return }
                    g.materials = g.materials.map(mat)
                    n.geometry = g
                }
            }
            let pienoMat = solido(0x7fd8ec, ruvido: 0.55), fanMat = olo(0x4fe3ff)
            rivesti(foto) { m in let c = m.copy() as? SCNMaterial ?? m; self.aggiungiTaglio(c); return c }
            rivesti(pieno) { _ in pienoMat }
            rivesti(fan) { _ in fanMat }
            fan.renderingOrder = 10
            [foto, pieno, fan].forEach { radice.addChildNode($0) }
            parti.append(Parte(foto: foto, pieno: pieno, fantasma: fan, linee: nil))
        } else if let corpo = OlogrammaOrganismo.corpo {
            let colori = Self.coloriPersona(corpo)
            var fonti = corpo.sources
            if let colori { fonti.append(Self.fonteColori(colori)) }
            let conColori = SCNGeometry(sources: fonti, elements: corpo.elements)
            parte(corpo, foto: [solido(0xffffff, ruvido: 0.72)], pieno: [solido(0x7fd8ec, ruvido: 0.55)], tri: Self.triangoliDi(corpo), geoFoto: conColori)
            h = 1.78
        }
        quota([0.62, 0, -0.1], [0.62, h, -0.1], LidarFormato.m(Double(h), 2), [1, 0, 0])
        inclinazioneBase = 0.1; k = 0.95; bersaglio = [0, h / 2, 0]; campioni = 6500
        bersaglioFisso = true
    }
    private var bersaglioFisso = false

    /// La «texture» dipinta della persona d'esempio, come `corpoUmano()` del mockup: pelle, maglia, jeans, cintura, scarpe, capelli.
    private static func coloriPersona(_ g: SCNGeometry) -> [SIMD3<Float>]? {
        guard let pos = vertici(g) else { return nil }
        let J = OlogrammaOrganismo.giunture
        func j(_ k: String) -> SIMD3<Float> { J[k] ?? .zero }
        let PELLE = rgb(0xc99a7a), MAGLIA = rgb(0x26363f), JEANS = rgb(0x3a5470), CINTA = rgb(0x3b2a1e), SCARPE = rgb(0xe6e6e2), SUOLA = rgb(0x9a9a96), CAPELLI = rgb(0x2a2018)
        return pos.enumerated().map { i, p in
            let ax = abs(p.x), braccio = ax > 0.2 && p.y > 0.85
            let rum = Float((sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
            var base = PELLE, f: Float = 0.04
            let spalla = j(p.x < 0 ? "spSx" : "spDx")
            if p.y < 0.02 { base = SUOLA }
            else if p.y < 0.085 { base = SCARPE }
            else if !braccio && p.y < 0.975 { base = JEANS; f = 0.1 }
            else if !braccio && p.y < 1.015 { base = CINTA }
            else if p.y < j("collo").y - 0.035 && (!braccio || simd_distance(p, spalla) < 0.17) { base = MAGLIA; f = 0.08 }
            else if p.y > j("testa").y + 0.025 && (p.z < j("testa").z + 0.045 || p.y > j("testa").y + 0.1) { base = CAPELLI; f = 0.1 }
            else if p.y > j("collo").y + 0.03 && p.y < j("testa").y + 0.03 && p.z < j("testa").z - 0.06 { base = CAPELLI; f = 0.1 }
            return simd_clamp(base * (1 + (rum - 0.5) * f), SIMD3(repeating: 0), SIMD3(repeating: 1))
        }
    }

    /// I vertici di una geometria (float × 3).
    static func vertici(_ g: SCNGeometry) -> [SIMD3<Float>]? {
        guard let s = g.sources(for: .vertex).first, s.usesFloatComponents, s.bytesPerComponent == 4, s.componentsPerVector >= 3 else { return nil }
        var out = [SIMD3<Float>](); out.reserveCapacity(s.vectorCount)
        s.data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            for i in 0..<s.vectorCount {
                let o = s.dataOffset + i * s.dataStride
                guard o + 12 <= b.count else { break }
                out.append(SIMD3(b.loadUnaligned(fromByteOffset: o, as: Float.self), b.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                                 b.loadUnaligned(fromByteOffset: o + 8, as: Float.self)))
            }
        }
        return out
    }
    static func triangoliDi(_ g: SCNGeometry) -> [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] {
        guard let v = vertici(g) else { return [] }
        var out: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
        for el in g.elements where el.primitiveType == .triangles {
            let bpi = el.bytesPerIndex
            el.data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                func idx(_ k: Int) -> Int {
                    switch bpi {
                    case 2: return Int(b.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self))
                    case 4: return Int(b.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self))
                    default: return Int(b.loadUnaligned(fromByteOffset: k, as: UInt8.self))
                    }
                }
                for t in 0..<el.primitiveCount {
                    guard (t * 3 + 2) * bpi + bpi <= b.count else { break }
                    let a = idx(t * 3), c = idx(t * 3 + 1), d = idx(t * 3 + 2)
                    if a < v.count, c < v.count, d < v.count { out.append((v[a], v[c], v[d])) }
                }
            }
        }
        return out
    }

    // Corpo › Postura: il fantasma della persona, lo scheletro vero, spalle e bacino in ambra, la quota dell'altezza
    private func postura(_ p: PosturaScena) {
        if let corpo = OlogrammaOrganismo.corpo {
            let s = p.altezza / 1.78                                                  // il fantasma alto come la persona
            let fan = SCNNode(geometry: corpo.copy() as? SCNGeometry)
            fan.geometry?.materials = [olo(0x4fe3ff, 0.32)]
            fan.simdScale = SIMD3(repeating: s)
            fan.renderingOrder = 10
            radice.addChildNode(fan)
            triangoli += Self.triangoliDi(corpo).map { ($0.0 * s, $0.1 * s, $0.2 * s) }
        }
        let J = p.giunture
        let ossa: [(String, String)] = [("testa", "collo"), ("collo", "spSx"), ("collo", "spDx"), ("spSx", "goSx"), ("spDx", "goDx"), ("goSx", "maSx"), ("goDx", "maDx"),
                                        ("collo", "bac"), ("bac", "anSx"), ("bac", "anDx"), ("anSx", "giSx"), ("anDx", "giDx"), ("giSx", "piSx"), ("giDx", "piDx")]
        let mo = Self.tinta(0x4fe3ff, 1), mg = Self.tinta(0xe6f4f8, 1)
        for (a, b) in ossa {
            guard let A = J[a], let B = J[b] else { continue }
            let d = B - A, l = simd_length(d)
            guard l > 0.001 else { continue }
            let c = SCNCylinder(radius: 0.011, height: CGFloat(l)); c.radialSegmentCount = 8; c.materials = [mo]
            let n = SCNNode(geometry: c)
            n.simdPosition = (A + B) / 2
            n.simdOrientation = simd_quatf(from: [0, 1, 0], to: d / l)
            n.renderingOrder = 15
            radice.addChildNode(n)
        }
        for (k, q) in J {
            let s = SCNSphere(radius: k == "testa" ? 0.03 : 0.022); s.segmentCount = 14; s.materials = [mg]
            let n = SCNNode(geometry: s); n.simdPosition = q; n.renderingOrder = 15; radice.addChildNode(n)
        }
        let spS = J["spSx"] ?? [-0.19, 1.43, -0.12], spD = J["spDx"] ?? [0.19, 1.43, -0.12]
        let anS = J["anSx"] ?? [-0.11, 0.95, -0.15], anD = J["anDx"] ?? [0.11, 0.95, -0.15]
        let ys = (spS.y + spD.y) / 2, zs = (spS.z + spD.z) / 2, yb = (anS.y + anD.y) / 2, zb = (anS.z + anD.z) / 2
        let rb = p.bacinoGradi * .pi / 180
        linea([[-0.42, spS.y, zs], [0.42, spD.y, zs]], 0xffb45a, 1, tratteggio: 0.03)
        etichetta("SPALLE " + LidarFormato.cm(Double(p.spalle)), [0.66, ys + 0.06, zs], .ambra)
        linea([[-0.3 * cos(rb), yb, zb + 0.3 * sin(rb)], [0.3 * cos(rb), yb, zb - 0.3 * sin(rb)]], 0xffb45a, 1, tratteggio: 0.03)
        etichetta("BACINO " + LidarFormato.bacino(Double(p.bacinoGradi)), [-0.6, yb - 0.06, zb], .ambra)
        let collo = J["collo"] ?? [0, 1.53, -0.13]
        linea([[0, p.altezza + 0.02, collo.z], [0, 0, collo.z]], 0x7feeff, 0.55, tratteggio: 0.04)
        quota([0.8, 0, zs], [0.8, p.altezza, zs], LidarFormato.m(Double(p.altezza), 2), [1, 0, 0])
        inclinazioneBase = 0.1; k = 0.95; bersaglio = [0, p.altezza / 2, 0]; bersaglioFisso = true; asse = [0, -1, 0]; campioni = 4500
    }

    // Misura: la parete (intonaco), il pavimento (parquet), la quota larga in grande e quella alta
    private func misura(_ L: Float, _ H: Float) {
        scatolaParte([0, H / 2, -0.06], [L, H, 0.12], foto: solido(trama: TrameLidar.immagine("intonaco"), metri: 2, ruvido: 0.92), pieno: solido(0x4fd2ee, ruvido: 0.6))
        scatolaParte([0, -0.01, 0.9], [L + 1.2, 0.02, 1.8], foto: parquet, pieno: solido(0x1c5866, ruvido: 0.8), bordi: false)
        let yq = min(1.3, H * 0.48)
        quota([-L / 2, yq, 0.1], [L / 2, yq, 0.1], LidarFormato.m(Double(L), 2), [0, 1, 0], .grande)
        quota([L / 2 + 0.25, 0, 0.1], [L / 2 + 0.25, H, 0.1], LidarFormato.m(Double(H), 2), [1, 0, 0])
        for x in [-L / 2, L / 2] {
            let s = SCNSphere(radius: 0.035); s.segmentCount = 16; s.materials = [Self.tinta(0xffb45a, 1, additiva: false)]
            let n = SCNNode(geometry: s); n.simdPosition = [x, yq, 0.1]; radice.addChildNode(n); sopra.append(n)
        }
        inclinazioneBase = 0.16; k = 0.78; asse = [1, 0, 0]; bersaglio = [0, H * 0.46, 0.2]; bersaglioFisso = true; campioni = 3500
    }

    // MARK: Inquadratura, mirino a terra, polvere

    private func inquadra() {
        let (lo, hi) = radice.boundingBox
        let mn = SIMD3<Float>(Float(lo.x), Float(lo.y), Float(lo.z)), mx = SIMD3<Float>(Float(hi.x), Float(hi.y), Float(hi.z))
        let centro = (mn + mx) / 2
        R = max(0.1, simd_length(mx - mn) / 2)
        if !bersaglioFisso { bersaglio = centro }
        // dove passa il taglio (sull'asse scelto), per la materializzazione
        var dm: Float = .infinity, dM: Float = -.infinity
        for i in 0..<2 { for j in 0..<2 { for l in 0..<2 {
            let v = SIMD3<Float>(i == 0 ? mn.x : mx.x, j == 0 ? mn.y : mx.y, l == 0 ? mn.z : mx.z)
            dm = min(dm, simd_dot(v, asse)); dM = max(dM, simd_dot(v, asse))
        } } }
        dMin = dm; dMax = dM
        // i materiali olografici già fatti hanno l'asse e la scala del modello di prima: si rifanno con quelli veri
        rifaiOlografici()
        let mirino = SCNNode()
        mirino.simdPosition = [centro.x, mn.y - 0.02, centro.z]
        scena.rootNode.addChildNode(mirino)
        func anello(_ r0: Float, _ r1: Float, _ alfa: CGFloat, spicchi: Int = 1) {
            var v: [SCNVector3] = [], idx: [UInt32] = []
            let quota: Float = spicchi > 1 ? 0.62 : 1, seg = spicchi > 1 ? 8 : 96
            for s in 0..<spicchi {
                let inizio = Float(s) * 2 * .pi / Float(spicchi), ampiezza = 2 * .pi / Float(spicchi) * quota
                let b = UInt32(v.count)
                for i in 0...seg {
                    let a = inizio + ampiezza * Float(i) / Float(seg)
                    v.append(SCNVector3(cos(a) * r0, 0, sin(a) * r0)); v.append(SCNVector3(cos(a) * r1, 0, sin(a) * r1))
                }
                for i in 0..<UInt32(seg) { let a = b + 2 * i; idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2] }
            }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
            g.materials = [Self.tinta(0x4fe3ff, alfa)]
            mirino.addChildNode(SCNNode(geometry: g))
        }
        anello(R * 1.02, R * 1.03, 0.5); anello(R * 1.08, R * 1.1, 0.3, spicchi: 12); anello(R * 0.55, R * 0.555, 0.18)
        var tv: [SCNVector3] = []
        for i in 0..<72 {
            let a = Float(i) / 72 * 2 * .pi, l: Float = i % 6 == 0 ? 0.09 : 0.04
            tv.append(SCNVector3(cos(a) * R * 1.13, 0, sin(a) * R * 1.13)); tv.append(SCNVector3(cos(a) * R * (1.13 + l), 0, sin(a) * R * (1.13 + l)))
        }
        let tg = SCNGeometry(sources: [SCNGeometrySource(vertices: tv)], elements: [SCNGeometryElement(indices: (0..<UInt32(tv.count)).map { $0 }, primitiveType: .line)])
        tg.materials = [Self.tinta(0x4fe3ff, 0.4)]
        mirino.addChildNode(SCNNode(geometry: tg))
        mirino.runAction(.repeatForever(.rotateBy(x: 0, y: 1.2, z: 0, duration: 10)))
        // la polvere: punti che salgono piano e girano al contrario
        var pv: [SCNVector3] = []
        for _ in 0..<160 {
            let a = Float.random(in: 0..<(2 * .pi)), r = Float.random(in: 0..<1).squareRoot() * R * 1.1
            pv.append(SCNVector3(cos(a) * r, Float.random(in: 0..<1) * R * 0.9, sin(a) * r))
        }
        let el = SCNGeometryElement(indices: (0..<UInt32(pv.count)).map { $0 }, primitiveType: .point)
        el.pointSize = CGFloat(R * 0.012); el.minimumPointScreenSpaceRadius = 1; el.maximumPointScreenSpaceRadius = 2.5
        let pg = SCNGeometry(sources: [SCNGeometrySource(vertices: pv)], elements: [el])
        pg.materials = [Self.tinta(0x8ff0ff, 0.55)]
        let polvere = SCNNode(geometry: pg); polvere.simdPosition = mirino.simdPosition
        scena.rootNode.addChildNode(polvere)
        let sale = CGFloat(R * 0.05)
        polvere.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: sale, z: 0, duration: 9), .moveBy(x: 0, y: -sale, z: 0, duration: 0)])))
        polvere.runAction(.repeatForever(.rotateBy(x: 0, y: -0.3, z: 0, duration: 10)))
    }

    /// I materiali olografici sono nati prima di conoscere asse e grandezza del modello: si riscrive il loro shader.
    private func rifaiOlografici() {
        let vecchi = cacheOlo
        cacheOlo = [:]
        let tenuti = materialiOlo.filter { m in !vecchi.values.contains { $0 === m } }
        materialiOlo = tenuti
        for (chiave, m) in vecchi {
            let parti = chiave.split(separator: "-")
            guard parti.count == 2, let hex = UInt32(parti[0]), let alfa = Double(parti[1]) else { continue }
            let nuovo = olo(hex, alfa)
            m.shaderModifiers = nuovo.shaderModifiers
            m.setValue(NSNumber(value: Float(1e6)), forKey: "taglio")
            m.setValue(NSNumber(value: Float(1)), forKey: "verso")
            materialiOlo.removeAll { $0 === nuovo }
            materialiOlo.append(m)
            cacheOlo[chiave] = m
        }
        // anche il taglio dei solidi va sull'asse giusto
        for m in materialiSolidi { aggiungiTaglioSoltanto(m) }
    }
    private func aggiungiTaglioSoltanto(_ m: SCNMaterial) {
        var mod = m.shaderModifiers ?? [:]
        mod[.fragment] = """
        #pragma arguments
        float tagS;
        #pragma body
        float4 jvWs = scn_frame.inverseViewTransform * float4(_surface.position, 1.0f);
        if (dot(jvWs.xyz, \(asseShader)) > tagS) { discard_fragment(); }
        """
        m.shaderModifiers = mod
        m.setValue(NSNumber(value: Float(1e6)), forKey: "tagS")
    }

    // MARK: La nuvola di punti (anteprima): campionata sulle superfici del modello

    private func nuvolaDiPunti() {
        guard !triangoli.isEmpty, campioni > 0 else { return }
        var cum: [Float] = []; var tot: Float = 0
        for t in triangoli { tot += simd_length(simd_cross(t.1 - t.0, t.2 - t.0)) / 2; cum.append(tot) }
        guard tot > 0 else { return }
        var pv: [SCNVector3] = []; pv.reserveCapacity(campioni)
        for _ in 0..<campioni {
            let x = Float.random(in: 0..<tot)
            var lo = 0, hi = cum.count - 1
            while lo < hi { let md = (lo + hi) / 2; if cum[md] < x { lo = md + 1 } else { hi = md } }
            let (a, b, c) = triangoli[lo]
            var u = Float.random(in: 0..<1), v = Float.random(in: 0..<1)
            if u + v > 1 { u = 1 - u; v = 1 - v }
            let p = a + (b - a) * u + (c - a) * v
            pv.append(SCNVector3(p.x, p.y, p.z))
        }
        let el = SCNGeometryElement(indices: (0..<UInt32(pv.count)).map { $0 }, primitiveType: .point)
        el.pointSize = CGFloat(R * 0.008); el.minimumPointScreenSpaceRadius = 0.6; el.maximumPointScreenSpaceRadius = 1.6
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pv)], elements: [el])
        g.materials = [Self.tinta(0x7feeff, 0.5)]
        let n = SCNNode(geometry: g); n.renderingOrder = 25
        radice.addChildNode(n)
        nuvola = n
    }
}

// MARK: - La vista (SwiftUI)

/// Il 3D nella tavola: SCNView trasparente, il dito in orizzontale gira, due dita ingrandiscono, doppio tocco riparte.
struct Vista3DLidar: View {
    let modello: ModelloScena
    let fase: FaseScenaLidar
    let stile: StileLidar?

    var body: some View {
        Superficie3DLidar(modello: modello, fase: fase, stile: stile)
            .overlay(alignment: .bottomTrailing) {
                Text("360°").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.ciano).opacity(0.75).padding(.trailing, 10).padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if case .esterno = modello {
                    Text("RILIEVO ×3").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Color.ciano).opacity(0.75).padding(.leading, 10).padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct Superficie3DLidar: UIViewRepresentable {
    let modello: ModelloScena
    let fase: FaseScenaLidar
    let stile: StileLidar?

    func makeCoordinator() -> Coordinatore { Coordinatore(ScenaLidar(modello, fase: fase, stile: stile)) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: nil)
        let s = context.coordinator.scena
        v.scene = s.scena
        v.pointOfView = s.camera
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.allowsCameraControl = false
        v.rendersContinuously = true
        v.isPlaying = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinatore.trascina(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        let pinza = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinatore.pizzica(_:)))
        pinza.delegate = context.coordinator
        v.addGestureRecognizer(pinza)
        let doppio = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinatore.doppio(_:)))
        doppio.numberOfTapsRequired = 2
        v.addGestureRecognizer(doppio)
        s.avvia(v)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) { context.coordinator.scena.imposta(stile) }

    static func dismantleUIView(_ v: SCNView, coordinator: Coordinatore) {
        coordinator.scena.ferma()
        v.isPlaying = false
        v.scene = nil
    }

    final class Coordinatore: NSObject, UIGestureRecognizerDelegate {
        let scena: ScenaLidar
        private var yaw0: Float = 0, zoom0: Float = 1
        init(_ s: ScenaLidar) { scena = s }

        @objc func trascina(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began: yaw0 = scena.yaw; scena.toccando = true
            case .changed: scena.yaw = yaw0 - Float(g.translation(in: g.view).x) * 0.009; scena.ultimoTocco = CACurrentMediaTime()
            default: scena.toccando = false; scena.ultimoTocco = CACurrentMediaTime()
            }
        }
        @objc func pizzica(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began: zoom0 = scena.zoom; scena.toccando = true
            case .changed: scena.zoom = max(0.45, min(1.8, zoom0 / Float(max(0.01, g.scale)))); scena.ultimoTocco = CACurrentMediaTime()
            default: scena.toccando = false; scena.ultimoTocco = CACurrentMediaTime()
            }
        }
        @objc func doppio(_ g: UITapGestureRecognizer) { scena.ripristina(); scena.ultimoTocco = CACurrentMediaTime() }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y)                       // in verticale scorre la pagina (pan-y del mockup)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Le trame «fotografiche» del mockup (trama3): generatore pseudo-casuale fisso, sempre uguali

@MainActor
enum TrameLidar {
    private static var cache: [String: UIImage] = [:]

    /// Lo «studio» per i riflessi: luce bianca in alto, azzurra a sinistra, fondo scuro.
    static let studio: UIImage = {
        let f = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 128))
        return f.image { c in
            let cg = c.cgContext
            let colori = [UIColor(white: 1, alpha: 1).cgColor, UIColor(red: 0.62, green: 0.86, blue: 1, alpha: 1).cgColor,
                          UIColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1).cgColor, UIColor(red: 0.19, green: 0.22, blue: 0.25, alpha: 1).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colori as CFArray, locations: [0, 0.35, 0.55, 1]) {
                cg.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 128), options: [])
            }
        }
    }()

    static func immagine(_ nome: String) -> UIImage {
        if let i = cache[nome] { return i }
        var seme: UInt64 = 1 + UInt64(nome.count) * 7919
        func r() -> CGFloat { seme = (seme * 16807) % 2147483647; return CGFloat(seme) / 2147483647 }
        let N: CGFloat = nome == "parquet" ? 1024 : 512
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: N, height: N), format: fmt).image { c in
            // il renderer chiama questo blocco subito, sullo stesso thread (il principale): lo si dice a Swift, così il blocco può
            // usare r(), hex() e ScenaLidar.colore, che appartengono al thread principale come tutta TrameLidar
            MainActor.assumeIsolated {
            let x = c.cgContext
            func hsl(_ h: CGFloat, _ s: CGFloat, _ l: CGFloat) -> UIColor {
                let ll = l / 100, ss = s / 100, a = ss * min(ll, 1 - ll)
                func f(_ n: CGFloat) -> CGFloat { let k = (n + h / 30).truncatingRemainder(dividingBy: 12); return ll - a * max(-1, min(k - 3, 9 - k, 1)) }
                return UIColor(red: f(0), green: f(8), blue: f(4), alpha: 1)
            }
            func rumore(_ base: UIColor, _ forza: CGFloat, _ n: Int, _ dim: CGFloat = 2) {
                x.setFillColor(base.cgColor); x.fill(CGRect(x: 0, y: 0, width: N, height: N))
                for _ in 0..<n {
                    let v = (r() - 0.5) * forza
                    x.setFillColor(v > 0 ? UIColor(white: 1, alpha: v).cgColor : UIColor(white: 0, alpha: -v).cgColor)
                    x.fill(CGRect(x: r() * N, y: r() * N, width: dim * (0.5 + r()), height: dim * (0.5 + r())))
                }
            }
            func hex(_ h: UInt32) -> UIColor { ScenaLidar.colore(h) }
            switch nome {
            case "parquet":                                                  // 2,4 m: listoni da 12 cm, giunti sfalsati, venature
                let riga = N / 20
                for i in 0..<20 {
                    var px = -r() * N * 0.4
                    while px < N {
                        let lung = N * (0.25 + r() * 0.3), l = 36 + r() * 12, h = 28 + r() * 6
                        x.setFillColor(hsl(h, 30 + r() * 9, l + 4).cgColor); x.fill(CGRect(x: px, y: CGFloat(i) * riga, width: lung, height: riga))
                        x.setStrokeColor(UIColor(red: 60 / 255, green: 35 / 255, blue: 15 / 255, alpha: 0.18).cgColor); x.setLineWidth(1)
                        for k in 0..<7 {
                            let yy = CGFloat(i) * riga + r() * riga
                            x.move(to: CGPoint(x: px, y: yy))
                            for s in 0...8 { x.addLine(to: CGPoint(x: px + lung * CGFloat(s) / 8, y: yy + sin(CGFloat(s + k)) * 1.4)) }
                            x.strokePath()
                        }
                        x.setFillColor(UIColor(red: 25 / 255, green: 12 / 255, blue: 5 / 255, alpha: 0.55).cgColor); x.fill(CGRect(x: px, y: CGFloat(i) * riga, width: 2, height: riga))
                        px += lung
                    }
                    x.setFillColor(UIColor(red: 25 / 255, green: 12 / 255, blue: 5 / 255, alpha: 0.5).cgColor); x.fill(CGRect(x: 0, y: CGFloat(i) * riga, width: N, height: 1.5))
                }
            case "intonaco": rumore(hex(0xd9d2c4), 0.07, 9000, 3)
            case "erba":
                x.setFillColor(hex(0x3f6a2a).cgColor); x.fill(CGRect(x: 0, y: 0, width: N, height: N))
                for _ in 0..<14000 {
                    let px = r() * N, py = r() * N, l = 4 + r() * 7, a = -CGFloat.pi / 2 + (r() - 0.5) * 1.2
                    x.setStrokeColor(hsl(88 + r() * 30, 38 + r() * 22, 20 + r() * 26).cgColor); x.setLineWidth(1 + r())
                    x.move(to: CGPoint(x: px, y: py)); x.addLine(to: CGPoint(x: px + cos(a) * l, y: py + sin(a) * l)); x.strokePath()
                }
            case "terra":
                var y: CGFloat = 0
                while y < N { x.setFillColor(hsl(24 + r() * 8, 30 + r() * 12, 16 + (y / N) * 10 + r() * 5).cgColor); x.fill(CGRect(x: 0, y: y, width: N, height: 4)); y += 4 }
                for _ in 0..<2500 {
                    x.setFillColor((r() > 0.5 ? UIColor(red: 200 / 255, green: 180 / 255, blue: 150 / 255, alpha: r() * 0.25) : UIColor(white: 0, alpha: r() * 0.25)).cgColor)
                    x.fill(CGRect(x: r() * N, y: r() * N, width: 2 + r() * 3, height: 2 + r() * 2))
                }
            case "laminato": rumore(hex(0x2c3035), 0.16, 26000, 2.2)
            case "palco": rumore(hex(0x1c1e21), 0.1, 12000, 2)
            case "noce":
                for i in 0..<8 {
                    x.setFillColor(hsl(22 + r() * 6, 42 + r() * 10, 22 + r() * 8).cgColor); x.fill(CGRect(x: CGFloat(i) * N / 8, y: 0, width: N / 8, height: N))
                    x.setStrokeColor(UIColor(red: 20 / 255, green: 8 / 255, blue: 2 / 255, alpha: 0.3).cgColor); x.setLineWidth(1)
                    for k in 0..<12 {
                        let xx = CGFloat(i) * N / 8 + r() * N / 8
                        x.move(to: CGPoint(x: xx, y: 0))
                        for s in 0...10 { x.addLine(to: CGPoint(x: xx + sin(CGFloat(s) * 0.9 + CGFloat(k)) * 2.5, y: N * CGFloat(s) / 10)) }
                        x.strokePath()
                    }
                    x.setFillColor(UIColor(red: 10 / 255, green: 4 / 255, blue: 0, alpha: 0.6).cgColor); x.fill(CGRect(x: CGFloat(i) * N / 8, y: 0, width: 2, height: N))
                }
            case "moquette": rumore(hex(0x55595e), 0.12, 15000, 1.6)
            default: rumore(hex(0x808080), 0.05, 2000)
            }
            }
        }
        cache[nome] = img
        return img
    }
}

// MARK: - Geometria piana (pavimenti, bordi, allestimento)

nonisolated enum GeometriaPiana {
    static func areaConSegno(_ p: [SIMD2<Float>]) -> Float {
        guard p.count >= 3 else { return 0 }
        var a: Float = 0
        for i in 0..<p.count { let j = (i + 1) % p.count; a += p[i].x * p[j].y - p[j].x * p[i].y }
        return a / 2
    }
    static func area(_ p: [SIMD2<Double>]) -> Double {
        guard p.count >= 3 else { return 0 }
        var a = 0.0
        for i in 0..<p.count { let j = (i + 1) % p.count; a += p[i].x * p[j].y - p[j].x * p[i].y }
        return abs(a) / 2
    }
    static func perimetro(_ p: [SIMD2<Double>]) -> Double {
        guard p.count >= 2 else { return 0 }
        return (0..<p.count).reduce(0) { $0 + simd_distance(p[$1], p[($1 + 1) % p.count]) }
    }
    static func baricentro(_ p: [SIMD2<Float>]) -> SIMD2<Float> {
        guard !p.isEmpty else { return .zero }
        let a = areaConSegno(p)
        if abs(a) < 1e-6 { return p.reduce(.zero, +) / Float(p.count) }
        var c = SIMD2<Float>(0, 0)
        for i in 0..<p.count { let j = (i + 1) % p.count; let k = p[i].x * p[j].y - p[j].x * p[i].y; c += (p[i] + p[j]) * k }
        return c / (6 * a)
    }
    static func baricentro(_ p: [SIMD2<Double>]) -> SIMD2<Double> {
        let f = baricentro(p.map { SIMD2<Float>(Float($0.x), Float($0.y)) }); return SIMD2(Double(f.x), Double(f.y))
    }
    /// Un punto sicuramente dentro (il baricentro, o il punto interno più vicino a lui su una griglia).
    static func puntoInterno(_ p: [SIMD2<Float>]) -> SIMD2<Float> {
        let g = baricentro(p)
        if dentro(g, p) || p.count < 3 { return g }
        let xs = p.map(\.x), ys = p.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return g }
        var meglio = g, d = Float.infinity
        for i in 0...20 { for j in 0...20 {
            let q = SIMD2(x0 + (x1 - x0) * Float(i) / 20, y0 + (y1 - y0) * Float(j) / 20)
            if dentro(q, p), simd_distance(q, g) < d { d = simd_distance(q, g); meglio = q }
        } }
        return meglio
    }
    static func dentro(_ q: SIMD2<Float>, _ p: [SIMD2<Float>]) -> Bool {
        var c = false, j = p.count - 1
        for i in 0..<p.count {
            let a = p[i], b = p[j]
            if (a.y > q.y) != (b.y > q.y), q.x < (b.x - a.x) * (q.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }
    static func dentro(_ q: SIMD2<Double>, _ p: [SIMD2<Double>]) -> Bool {
        dentro(SIMD2<Float>(Float(q.x), Float(q.y)), p.map { SIMD2<Float>(Float($0.x), Float($0.y)) })
    }
    /// Il triangolatore «a orecchie» per i poligoni semplici (anche concavi); il poligono va dato in senso antiorario.
    static func triangola(_ p: [SIMD2<Float>]) -> [(Int, Int, Int)] {
        var idx = Array(p.indices), out: [(Int, Int, Int)] = []
        func croce(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
        func nelTriangolo(_ q: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
            croce(a, b, q) >= 0 && croce(b, c, q) >= 0 && croce(c, a, q) >= 0
        }
        var giri = 0
        while idx.count > 3 && giri < 10_000 {
            giri += 1
            var tagliato = false
            for k in 0..<idx.count {
                let i0 = idx[(k + idx.count - 1) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = p[i0], b = p[i1], c = p[i2]
                guard croce(a, b, c) > 1e-7 else { continue }                       // angolo convesso
                let dentroQualcuno = idx.contains { j in j != i0 && j != i1 && j != i2 && nelTriangolo(p[j], a, b, c) }
                if dentroQualcuno { continue }
                out.append((i0, i1, i2)); idx.remove(at: k); tagliato = true; break
            }
            if !tagliato {                                                           // poligono sporco: si chiude a ventaglio
                for k in 1..<(idx.count - 1) { out.append((idx[0], idx[k], idx[k + 1])) }
                return out
            }
        }
        if idx.count == 3 { out.append((idx[0], idx[1], idx[2])) }
        return out
    }
    /// L'inviluppo convesso (catena monotona).
    static func inviluppo(_ punti: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let p = punti.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard p.count >= 3 else { return p }
        func croce(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var basso: [SIMD2<Double>] = [], alto: [SIMD2<Double>] = []
        for q in p { while basso.count >= 2 && croce(basso[basso.count - 2], basso[basso.count - 1], q) <= 0 { basso.removeLast() }; basso.append(q) }
        for q in p.reversed() { while alto.count >= 2 && croce(alto[alto.count - 2], alto[alto.count - 1], q) <= 0 { alto.removeLast() }; alto.append(q) }
        return Array(basso.dropLast() + alto.dropLast())
    }
    /// Semplifica una linea (Douglas–Peucker).
    static func semplifica(_ p: [SIMD2<Double>], _ tolleranza: Double) -> [SIMD2<Double>] {
        guard p.count > 2 else { return p }
        func dist(_ q: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            let ab = b - a, l2 = simd_length_squared(ab)
            if l2 < 1e-12 { return simd_distance(q, a) }
            let t = max(0, min(1, simd_dot(q - a, ab) / l2))
            return simd_distance(q, a + ab * t)
        }
        var dMax = 0.0, iMax = 0
        for i in 1..<(p.count - 1) { let d = dist(p[i], p[0], p[p.count - 1]); if d > dMax { dMax = d; iMax = i } }
        if dMax <= tolleranza { return [p[0], p[p.count - 1]] }
        let a = semplifica(Array(p[0...iMax]), tolleranza), b = semplifica(Array(p[iMax...]), tolleranza)
        return Array(a.dropLast()) + b
    }
}
#endif
