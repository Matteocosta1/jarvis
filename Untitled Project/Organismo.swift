import Foundation
import SwiftUI
import SceneKit
import CoreGraphics
import Combine
import simd
#if os(iOS)
import UIKit
#endif

// BUILD 22 · B — Vitals → ORGANISMO (iPhone e Apple Watch, stesso file, due target).
// La persona olografica del mockup (modo «Armatura» di scena3d), con i Vitals veri sulle zone del corpo.

// MARK: - I numeri dell'Organismo e la prontezza

/// PRONTEZZA: la media dei punteggi da 0 a 100 che ci sono.
/// - Sonno = 100 × minuti dormiti stanotte ÷ media delle notti prima (fino a 30, almeno 3), massimo 100.
/// - Battito = 100 × media a riposo di 7 giorni ÷ battito a riposo di oggi, massimo 100 (più basso del solito = recuperato).
/// - Umore = voto dell'ultimo diario degli ultimi 7 giorni × 10.
/// Se un punteggio manca si fa la media degli altri, e la riga sotto lo dice.
/// Sonno e battito sono gli stessi numeri del riquadro OGGI di Vitals (riepilogo di Benessere).
struct DatiOrganismo: Equatable {
    var sonnoMin: Int?          // stanotte, in minuti
    var sonnoMediaMin: Int?     // media delle notti precedenti
    var battito: Int?           // a riposo, l'ultimo
    var battitoMedia: Int?      // media a riposo di 7 giorni
    var passiIeri: Int?
    var umore: Double?          // 1-10, ultimo diario

    var punteggioSonno: Int? {
        guard let s = sonnoMin, let m = sonnoMediaMin, m > 0 else { return nil }
        return min(100, Int((100 * Double(s) / Double(m)).rounded()))
    }
    var punteggioBattito: Int? {
        guard let b = battito, let m = battitoMedia, b > 0 else { return nil }
        return min(100, Int((100 * Double(m) / Double(b)).rounded()))
    }
    var punteggioUmore: Int? { umore.map { min(100, max(0, Int(($0 * 10).rounded()))) } }
    var prontezza: Int? {
        let p = [punteggioSonno, punteggioBattito, punteggioUmore].compactMap { $0 }
        guard !p.isEmpty else { return nil }
        return Int((Double(p.reduce(0, +)) / Double(p.count)).rounded())
    }

    /// Mette insieme i dati che Vitals ha già: il riepilogo di oggi, lo storico di Salute e il diario del cervello.
    static func calcola(oggi: SaluteOggi?, storia: [Date: SaluteStorica.Valori], diario: DatiVitals?) -> DatiOrganismo {
        let cal = Calendar.current
        let oggiG = cal.startOfDay(for: Date())
        let ieri = cal.date(byAdding: .day, value: -1, to: oggiG) ?? oggiG
        let settimana = cal.date(byAdding: .day, value: -7, to: oggiG) ?? oggiG
        func media(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        var d = DatiOrganismo()
        d.sonnoMin = minuti(oggi?.sonno) ?? storia[oggiG]?.sonnoOre.map { Int(($0 * 60).rounded()) }
        let notti = storia.filter { $0.key < oggiG }.compactMap { $0.value.sonnoOre }.filter { $0 > 0 }
        if notti.count >= 3, let m = media(notti) { d.sonnoMediaMin = Int((m * 60).rounded()) }
        d.battito = oggi?.battito ?? (storia[oggiG]?.battito ?? storia[ieri]?.battito).map { Int($0.rounded()) }
        d.battitoMedia = oggi?.battitoMedia
            ?? media(storia.filter { $0.key >= settimana && $0.key < oggiG }.compactMap { $0.value.battito }).map { Int($0.rounded()) }
        d.passiIeri = storia[ieri]?.passi.map { Int($0.rounded()) }
        d.umore = diario?.giorni.last(where: { $0.punteggio != nil && $0.data >= settimana })?.punteggio
        return d
    }

    /// «6 h 40 min» o «45 min» (il formato di Benessere) → minuti.
    static func minuti(_ testo: String?) -> Int? {
        guard let parole = testo?.split(separator: " ") else { return nil }
        var ore = 0, min = 0, trovato = false
        for (i, p) in parole.enumerated() where i + 1 < parole.count {
            guard let n = Int(p) else { continue }
            if parole[i + 1].hasPrefix("h") { ore = n; trovato = true } else if parole[i + 1].hasPrefix("min") { min = n; trovato = true }
        }
        return trovato ? ore * 60 + min : nil
    }

    // MARK: Testi

    static func durata(_ m: Int) -> String { m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min" }
    static func durataBreve(_ m: Int) -> String { m >= 60 ? "\(m / 60) h \(String(format: "%02d", m % 60))" : "\(m) min" }
    static func migliaia(_ n: Int) -> String {
        var s = String(abs(n)), out = ""
        while s.count > 3 { out = "." + String(s.suffix(3)) + out; s = String(s.dropLast(3)) }
        return (n < 0 ? "-" : "") + s + out
    }

    var testoProntezza: String { prontezza.map { "\($0)%" } ?? "—" }
    var testoSonno: String {
        guard let s = sonnoMin else { return "—" }
        guard let m = sonnoMediaMin else { return Self.durata(s) }
        let diff = s - m
        if abs(diff) < 5 { return "\(Self.durata(s)) · in media" }
        return "\(Self.durata(s)) · \(Self.durata(abs(diff))) \(diff < 0 ? "sotto" : "sopra") la media"
    }
    var testoBattito: String { battito.map { "\($0) bpm" } ?? "—" }
    var testoPassi: String { passiIeri.map { Self.migliaia($0) } ?? "—" }
    var testoUmore: String {
        guard let u = umore else { return "—" }
        let v = u == u.rounded() ? "\(Int(u))" : String(format: "%.1f", u).replacingOccurrences(of: ".", with: ",")
        return "\(v) su 10"
    }
    /// Il conto della prontezza, scritto: i tre punteggi e cosa manca.
    var contoProntezza: String {
        var parti: [String] = [], manca: [String] = []
        if let p = punteggioSonno { parti.append("Sonno \(p)") } else { manca.append("il sonno") }
        if let p = punteggioBattito { parti.append("Battito \(p)") } else { manca.append("il battito") }
        if let p = punteggioUmore { parti.append("Umore \(p)") } else { manca.append("l'umore") }
        if parti.isEmpty { return "Servono sonno, battito a riposo o il diario della sera." }
        var t = "Media dei punteggi su 100: " + parti.joined(separator: " · ") + "."
        if !manca.isEmpty { t += " \(manca.count == 1 ? "Manca" : "Mancano") \(manca.joined(separator: " e "))." }
        return t
    }

    // le etichette sopra il modello e la riga del polso
    var etichettaSonno: String { "SONNO " + (sonnoMin.map { Self.durataBreve($0) } ?? "—") }
    var etichettaBattito: String { "BATTITO " + (battito.map { "\($0)" } ?? "—") }
    var etichettaPassi: String { "PASSI " + (passiIeri.map { Self.migliaia($0) } ?? "—") }
    var etichettaPronto: String { "PRONTO " + testoProntezza }
    var rigaPolso: String {
        "Sonno \(sonnoMin.map { Self.durataBreve($0) } ?? "—") · Battito \(battito.map { "\($0)" } ?? "—") · Passi \(passiIeri.map { Self.migliaia($0) } ?? "—")"
    }
}

// MARK: - L'etichetta olografica (la «.et» del mockup)

struct EtichettaOlo: View {
    enum Stile { case normale, verde, ambra, grande }
    let testo: String
    var stile: Stile = .normale

    private static let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
    private static let verde = Color(red: 120 / 255, green: 230 / 255, blue: 150 / 255)
    private static let ambra = Color(red: 1, green: 180 / 255, blue: 90 / 255)

    private var bordo: Color {
        switch stile {
        case .verde: return Self.verde.opacity(0.85)
        case .ambra: return Self.ambra.opacity(0.85)
        case .grande, .normale: return Self.ciano.opacity(0.5)
        }
    }
    private var scritta: Color {
        switch stile {
        case .verde: return Color(red: 168 / 255, green: 245 / 255, blue: 191 / 255)
        case .ambra: return Color(red: 1, green: 214 / 255, blue: 163 / 255)
        case .grande: return .white
        case .normale: return Color(red: 230 / 255, green: 244 / 255, blue: 248 / 255)
        }
    }
    private var alone: Color {
        switch stile {
        case .verde: return Self.verde.opacity(0.3)
        case .ambra: return Self.ambra.opacity(0.3)
        case .grande, .normale: return Self.ciano.opacity(0.25)
        }
    }

    var body: some View {
        Text(testo)
            .font(.system(size: stile == .grande ? 13 : 10, weight: .semibold, design: .monospaced))
            .tracking(1)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(scritta)
            .padding(.horizontal, stile == .grande ? 9 : 6).padding(.vertical, stile == .grande ? 4 : 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 5 / 255, green: 8 / 255, blue: 9 / 255).opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(bordo, lineWidth: 1))
            .shadow(color: alone, radius: 5)
    }
}

// MARK: - La persona olografica (SceneKit)

/// La scena dell'Organismo, costruita come «Armatura» del mockup: il corpo umano vero (MakeHuman, CC0, lo stesso file
/// `corpo.bin` del mockup: 13.380 punti, 26.756 triangoli, alto 1,78 m) in materiale olografico ciano additivo con il bordo
/// luminoso (fresnel) e le righe di scansione, anello ambra sulla testa, cuore verde che batte, anelli verdi alle ginocchia,
/// mirino ad anelli a terra e polvere. `leggero` è l'orologio: meno segmenti, niente etichette né linea della schiena.
/// Tutto gira con le azioni di SceneKit (niente codice per fotogramma): la vista che la mostra decide solo l'angolo.
final class OlogrammaOrganismo: ObservableObject {
    let scena = SCNScene()
    let camera = SCNNode()
    private let leggero: Bool
    private let radice = SCNNode()
    private let giro = SCNNode()          // il giro da solo (0,22 rad/s)
    private let manuale = SCNNode()       // il dito o la corona
    private let cuore = SCNNode()
    private let alone = SCNNode()
    private var etichette: [SCNNode] = []
    private var bpm = 0
    private var ultimiDati: DatiOrganismo?
    private var riprendi: Task<Void, Never>?

    // le misure della scena del mockup (Box3 del modello): raggio, mirino, inquadratura
    private static let R: Float = 0.99
    private static let pavimento: Float = -0.011
    private static let bersaglio = SIMD3<Float>(0, 1.0, 0)
    private static let inclinazione: Float = 0.12
    private static let distanza: Float = R / sin(Float(16) * Float.pi / 180) * 1.05
    private static let metriPerPunto: CGFloat = 0.0074    // etichette alte come nel mockup (10 pt) sull'iPhone

    /// L'angolo dato col dito o con la corona (si somma al giro da solo).
    var yaw: Float = 0.65 { didSet { manuale.simdEulerAngles = SIMD3(0, yaw, 0) } }

    init(leggero: Bool) {
        self.leggero = leggero
        if leggero { scena.background.contents = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
        scena.rootNode.addChildNode(radice)
        persona()
        armatura()
        mirinoEPolvere()
        // la camera gira intorno al bersaglio: giro → dito/corona → inclinazione → camera
        let inclina = SCNNode()
        giro.simdPosition = Self.bersaglio
        manuale.simdEulerAngles = SIMD3(0, yaw, 0)
        inclina.simdEulerAngles = SIMD3(-Self.inclinazione, 0, 0)
        let c = SCNCamera()
        c.fieldOfView = 32
        c.zNear = 0.05
        c.zFar = 60
        camera.camera = c
        camera.simdPosition = SIMD3(0, 0, Self.distanza)
        scena.rootNode.addChildNode(giro)
        giro.addChildNode(manuale)
        manuale.addChildNode(inclina)
        inclina.addChildNode(camera)
        giro.runAction(.repeatForever(.rotateBy(x: 0, y: 0.22, z: 0, duration: 1)), forKey: "giro")
        battito(58)
    }

    // MARK: Comandi dalla vista

    /// Dito o corona: il giro da solo si ferma e riparte dopo 2,6 secondi di quiete (come nel mockup).
    func tocco(inizio: Bool) {
        riprendi?.cancel()
        if inizio { giro.isPaused = true; return }
        riprendi = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.giro.isPaused = false
        }
    }

    /// Schermo spento o pagina nascosta: tutto fermo.
    func pausa(_ si: Bool) { scena.isPaused = si }

    /// I numeri veri: etichette e battito del cuore.
    func aggiorna(_ d: DatiOrganismo) {
        if d.battito != nil, d.battito != bpm { battito(d.battito ?? 58) }
        guard !leggero, d != ultimiDati else { return }
        ultimiDati = d
        etichette.forEach { $0.removeFromParentNode() }
        let te = Self.g("testa"), gd = Self.g("giDx")
        etichette = [                                                     // dove le mette il mockup
            etichetta(d.etichettaSonno, .ambra, SIMD3(0.45, te.y + 0.08, te.z)),
            etichetta(d.etichettaBattito, .verde, SIMD3(-0.55, 1.34, Self.g("collo").z + 0.07)),
            etichetta(d.etichettaPassi, .verde, SIMD3(0.48, gd.y, gd.z)),
            etichetta(d.etichettaPronto, .grande, SIMD3(0, 2.0, 0)),
        ].compactMap { $0 }
    }

    // MARK: Materiali

    /// sRGB → lineare: SceneKit lavora in lineare, come three.js con `Color("#…")`.
    private static func lineare(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func rgb(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255)
    }
    private static func colore(_ hex: UInt32) -> CGColor {
        let (r, g, b) = rgb(hex)
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// L'ologramma del mockup (`holo`): bordo luminoso col fresnel, righe di scansione che scorrono, additivo, senza profondità.
    private static func olo(_ hex: UInt32, alfa: Double) -> SCNMaterial {
        let (r, g, b) = rgb(hex)
        func f(_ x: Double) -> String { String(format: "%.5ff", x) }
        let righe = 70 / Double(R)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = colore(hex)
        m.isDoubleSided = true
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.shaderModifiers = [.fragment: """
        #pragma transparent
        #pragma body
        float3 jvN = normalize(_surface.normal);
        float jvK = clamp(1.0f - abs(dot(jvN, normalize(_surface.view))), 0.0f, 1.0f);
        float jvFr = jvK * jvK;
        float4 jvW = scn_frame.inverseViewTransform * float4(_surface.position, 1.0f);
        float jvRiga = smoothstep(0.6f, 1.0f, sin(jvW.y * \(f(righe)) - scn_frame.time * 3.0f) * 0.5f + 0.5f);
        float jvA = clamp((0.05f + jvFr * 0.5f + jvRiga * 0.05f) * \(f(alfa)), 0.0f, 1.0f);
        float3 jvC = float3(\(f(lineare(r))), \(f(lineare(g))), \(f(lineare(b)))) * (0.3f + jvFr * 1.5f + jvRiga * 0.3f);
        _output.color = float4(jvC * jvA, jvA);
        """]
        return m
    }

    /// Colore pieno additivo (MeshBasicMaterial del mockup).
    private static func pieno(_ hex: UInt32, _ opacita: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = colore(hex)
        m.transparency = opacita
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    // MARK: Geometrie

    private var radiali: Int { leggero ? 8 : 16 }
    private var calotte: Int { leggero ? 2 : 6 }
    private var spicchi: Int { leggero ? 12 : 24 }

    private func capsula(_ r: Float, _ l: Float) -> SCNGeometry {
        let g = SCNCapsule(capRadius: CGFloat(r), height: CGFloat(l + 2 * r))
        g.radialSegmentCount = radiali; g.capSegmentCount = calotte; g.heightSegmentCount = 1
        return g
    }
    private func sfera(_ r: Float) -> SCNGeometry {
        let g = SCNSphere(radius: CGFloat(r)); g.segmentCount = spicchi; return g
    }
    @discardableResult
    private func pezzo(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SIMD3<Float>, rot: SIMD3<Float>? = nil, scala: SIMD3<Float>? = nil,
                       verso: simd_quatf? = nil, in genitore: SCNNode? = nil) -> SCNNode {
        g.materials = [m]
        let nodo = SCNNode(geometry: g)
        nodo.simdPosition = p
        if let rot { nodo.simdEulerAngles = rot }
        if let verso { nodo.simdOrientation = verso }
        if let scala { nodo.simdScale = scala }
        (genitore ?? radice).addChildNode(nodo)
        return nodo
    }

    /// Un osso: capsula da a a b.
    private func osso(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ r: Float, _ m: SCNMaterial) {
        var d = b - a
        let l = max(0.001, simd_length(d))
        if d.y < 0 { d = -d }                      // la capsula è simmetrica: sempre verso l'alto, niente rotazioni di 180°
        pezzo(capsula(r, l), m, (a + b) / 2, verso: simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(d)))
    }

    // MARK: La persona: il corpo umano vero, in ologramma

    /// Le articolazioni del corpo MakeHuman (A-pose, metri, piedi a terra, guarda verso +z): le stesse `GIUNTURE_CORPO` del mockup.
    static let giunture: [String: SIMD3<Float>] = [
        "testa": [0, 1.6301, -0.0948], "collo": [0, 1.5319, -0.1274], "spSx": [-0.1916, 1.4251, -0.1209], "spDx": [0.1916, 1.4251, -0.1209],
        "goSx": [-0.3618, 1.23, -0.1231], "goDx": [0.3618, 1.23, -0.1231], "maSx": [-0.4971, 1.1013, 0.0679], "maDx": [0.4971, 1.1013, 0.0679],
        "bac": [0, 0.9559, -0.1358], "anSx": [-0.1118, 0.9503, -0.1466], "anDx": [0.1118, 0.9503, -0.1466],
        "giSx": [-0.1553, 0.5165, -0.1114], "giDx": [0.1553, 0.5165, -0.1114], "piSx": [-0.1999, 0.0736, -0.1234], "piDx": [0.1999, 0.0736, -0.1234],
    ]
    private static func g(_ k: String) -> SIMD3<Float> { giunture[k] ?? .zero }

    /// Il corpo da `corpo.bin`: 2 × UInt32 (punti, triangoli), poi le posizioni (Float32, metri) e gli indici (UInt16),
    /// tutto little-endian. Le normali si calcolano qui, morbide (media delle facce pesata con l'area), come `computeVertexNormals`.
    /// Letto una volta sola e condiviso (iPhone e orologio hanno ognuno il suo file nell'app).
    static let corpo: SCNGeometry? = {
        guard let url = Bundle.main.url(forResource: "corpo", withExtension: "bin"),
              let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count >= 8 else { return nil }
        func u32(_ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
        let nv = u32(0), nt = u32(4)
        guard nv > 0, nv <= 65_536, nt > 0, d.count == 8 + nv * 12 + nt * 6 else { return nil }
        var pos = [SIMD3<Float>](repeating: .zero, count: nv)
        var idx = [UInt16](repeating: 0, count: nt * 3)
        d.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            for i in 0..<nv {
                let o = 8 + i * 12
                pos[i] = SIMD3(Float(bitPattern: b.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian),
                               Float(bitPattern: b.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self).littleEndian),
                               Float(bitPattern: b.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self).littleEndian))
            }
            let base = 8 + nv * 12
            for k in 0..<(nt * 3) { idx[k] = b.loadUnaligned(fromByteOffset: base + k * 2, as: UInt16.self).littleEndian }
        }
        guard idx.allSatisfy({ Int($0) < nv }) else { return nil }
        var nor = [SIMD3<Float>](repeating: .zero, count: nv)
        for t in 0..<nt {
            let a = Int(idx[t * 3]), b = Int(idx[t * 3 + 1]), c = Int(idx[t * 3 + 2])
            let n = simd_cross(pos[b] - pos[a], pos[c] - pos[a])         // lunga quanto il doppio dell'area: pesa da sola
            nor[a] += n; nor[b] += n; nor[c] += n
        }
        let vertici = pos.map { SCNVector3(x: $0.x, y: $0.y, z: $0.z) }
        let normali = nor.map { v -> SCNVector3 in let l = simd_length(v); let u = l > 0 ? v / l : SIMD3<Float>(0, 1, 0); return SCNVector3(x: u.x, y: u.y, z: u.z) }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: vertici), SCNGeometrySource(normals: normali)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }()

    /// Il corpo in ologramma, più luminoso che altrove (alfa 0,62 come nel mockup: nell'Organismo il protagonista è lui).
    /// Se il file mancasse, il fantasma di capsule di prima: la pagina non resta mai vuota.
    private func persona() {
        let m = Self.olo(0x4fe3ff, alfa: 0.62)
        if let corpo = Self.corpo?.copy() as? SCNGeometry {
            corpo.materials = [m]
            radice.addChildNode(SCNNode(geometry: corpo))
            return
        }
        for (s, sg) in [("Sx", Float(-1)), ("Dx", Float(1))] {
            osso(Self.g("pi" + s), Self.g("gi" + s), 0.06, m)
            osso(Self.g("gi" + s), Self.g("an" + s), 0.085, m)
            osso(Self.g("sp" + s), Self.g("go" + s), 0.052, m)
            osso(Self.g("go" + s), Self.g("ma" + s), 0.041, m)
            pezzo(sfera(0.085), m, Self.g("sp" + s) + SIMD3(-sg * 0.01, 0, 0))
        }
        pezzo(capsula(0.11, 0.14), m, Self.g("bac"), rot: [0, 0, .pi / 2], scala: [1, 1, 0.75])
        osso(Self.g("bac"), Self.g("collo"), 0.16, m)
        pezzo(sfera(0.105), m, Self.g("testa"), scala: [0.92, 1.12, 1])
    }

    // MARK: Armatura: i parametri sulle zone del corpo

    private func armatura() {
        // sonno: l'anello ambra sulla testa, che gira
        let te = Self.g("testa")
        let anello = SCNTorus(ringRadius: 0.14, pipeRadius: 0.007)
        anello.ringSegmentCount = leggero ? 32 : 64; anello.pipeSegmentCount = leggero ? 6 : 8
        let testa = pezzo(anello, Self.pieno(0xffb45a, 0.9), [0, te.y + 0.07, te.z])
        testa.runAction(.repeatForever(.rotateBy(x: 0, y: 0.8, z: 0, duration: 1)))
        // battito: il cuore verde e il suo alone
        // il cuore a sinistra della persona (che ci guarda: a destra per noi), dentro il petto
        let posCuore = SIMD3<Float>(0.045, 1.33, Self.g("collo").z + 0.07)
        let sc = sfera(0.04); sc.materials = [Self.pieno(0x78e696, 0.9)]
        cuore.geometry = sc; cuore.simdPosition = posCuore; radice.addChildNode(cuore)
        let sa = sfera(0.08); sa.materials = [Self.pieno(0x78e696, 1)]
        alone.geometry = sa; alone.simdPosition = posCuore; alone.opacity = 0.12; radice.addChildNode(alone)
        // passi: gli anelli verdi alle ginocchia, che respirano (0,55 + 0,35·sin(2t + i))
        for (i, k) in ["giSx", "giDx"].enumerated() {
            let t = SCNTorus(ringRadius: 0.08, pipeRadius: 0.006)
            t.ringSegmentCount = leggero ? 24 : 48; t.pipeSegmentCount = leggero ? 6 : 8
            let gin = pezzo(t, Self.pieno(0x78e696, 1), Self.g(k))
            let passi = leggero ? 12 : 24
            var seq: [SCNAction] = []
            for k in 1...passi {
                let tt = Double(k) / Double(passi) * .pi          // periodo π secondi
                seq.append(.fadeOpacity(to: CGFloat(0.55 + 0.35 * sin(2 * tt + Double(i))), duration: .pi / Double(passi)))
            }
            gin.opacity = CGFloat(0.55 + 0.35 * sin(Double(i)))
            gin.runAction(.repeatForever(.sequence(seq)))
        }
        // la schiena: la linea dal bacino al collo (sull'orologio no: nel mockup è nascosta in anteprima)
        if !leggero {
            let ba = Self.g("bac"), co = Self.g("collo")
            let v = [SCNVector3(x: ba.x, y: ba.y, z: ba.z), SCNVector3(x: co.x, y: co.y, z: co.z)]
            let l = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: [UInt16(0), 1], primitiveType: .line)])
            let ml = SCNMaterial(); ml.lightingModel = .constant; ml.diffuse.contents = Self.colore(0x7feeff); ml.transparency = 0.7; ml.writesToDepthBuffer = false
            l.materials = [ml]
            radice.addChildNode(SCNNode(geometry: l))
        }
    }

    /// Il cuore batte al battito a riposo vero: doppio colpo come nel mockup (e^-(f/0,07)² + 0,6·e^-((f-0,2)/0,06)²).
    private func battito(_ b: Int) {
        bpm = b
        let periodo = 60 / Double(max(35, min(b, 180)))
        let passi = leggero ? 16 : 30
        var su: [SCNAction] = [], al: [SCNAction] = []
        for k in 1...passi {
            let f = Double(k % passi) / Double(passi)
            let x = exp(-pow(f / 0.07, 2)) + 0.6 * exp(-pow((f - 0.2) / 0.06, 2))
            let dt = periodo / Double(passi)
            su.append(.scale(to: CGFloat(1 + 0.45 * x), duration: dt))
            al.append(.group([.scale(to: CGFloat(1 + 0.9 * x), duration: dt), .fadeOpacity(to: CGFloat(0.12 + 0.25 * x), duration: dt)]))
        }
        cuore.removeAllActions(); alone.removeAllActions()
        cuore.scale = SCNVector3(x: 1.45, y: 1.45, z: 1.45); alone.scale = SCNVector3(x: 1.9, y: 1.9, z: 1.9)
        cuore.runAction(.repeatForever(.sequence(su)))
        alone.runAction(.repeatForever(.sequence(al)))
    }

    // MARK: Mirino a terra e polvere

    /// Anelli piatti (RingGeometry ruotata a terra), anche a spicchi.
    private func anelli(_ r0: Float, _ r1: Float, archi: Int, quota: Float, segmenti: Int) -> SCNGeometry {
        var v: [SCNVector3] = [], n: [SCNVector3] = [], idx: [UInt16] = []
        for s in 0..<archi {
            let inizio = Float(s) * 2 * .pi / Float(archi), ampiezza = 2 * .pi / Float(archi) * quota
            let base = UInt16(v.count)
            for i in 0...segmenti {
                let a = inizio + ampiezza * Float(i) / Float(segmenti)
                v.append(SCNVector3(x: cos(a) * r0, y: 0, z: sin(a) * r0)); v.append(SCNVector3(x: cos(a) * r1, y: 0, z: sin(a) * r1))
                n.append(SCNVector3(x: 0, y: 1, z: 0)); n.append(SCNVector3(x: 0, y: 1, z: 0))
            }
            for i in 0..<segmenti {
                let a = base + UInt16(2 * i)
                idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
            }
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    private func mirinoEPolvere() {
        let R = Self.R
        let mirino = SCNNode()
        mirino.simdPosition = [0, Self.pavimento, 0]
        scena.rootNode.addChildNode(mirino)
        let giri = leggero ? 48 : 96
        pezzo(anelli(R * 1.02, R * 1.03, archi: 1, quota: 1, segmenti: giri), Self.pieno(0x4fe3ff, 0.5), .zero, in: mirino)
        pezzo(anelli(R * 1.08, R * 1.1, archi: 12, quota: 0.62, segmenti: leggero ? 4 : 8), Self.pieno(0x4fe3ff, 0.3), .zero, in: mirino)
        pezzo(anelli(R * 0.55, R * 0.555, archi: 1, quota: 1, segmenti: giri), Self.pieno(0x4fe3ff, 0.18), .zero, in: mirino)
        // le tacche: 72, una lunga ogni 6
        var tv: [SCNVector3] = [], ti: [UInt16] = []
        for i in 0..<72 {
            let a = Float(i) / 72 * 2 * .pi, l: Float = i % 6 == 0 ? 0.09 : 0.04
            tv.append(SCNVector3(x: cos(a) * R * 1.13, y: 0, z: sin(a) * R * 1.13))
            tv.append(SCNVector3(x: cos(a) * R * (1.13 + l), y: 0, z: sin(a) * R * (1.13 + l)))
            ti += [UInt16(2 * i), UInt16(2 * i + 1)]
        }
        let tacche = SCNGeometry(sources: [SCNGeometrySource(vertices: tv)], elements: [SCNGeometryElement(indices: ti, primitiveType: .line)])
        pezzo(tacche, Self.pieno(0x4fe3ff, 0.4), .zero, in: mirino)
        mirino.runAction(.repeatForever(.rotateBy(x: 0, y: 1.2, z: 0, duration: 10)))

        // la polvere: punti che salgono piano e girano al contrario
        let quanti = leggero ? 80 : 160
        var pv: [SCNVector3] = [], pIdx: [UInt16] = []
        for i in 0..<quanti {
            let a = Float.random(in: 0..<(2 * .pi)), r = sqrt(Float.random(in: 0..<1)) * R * 1.1
            pv.append(SCNVector3(x: cos(a) * r, y: Float.random(in: 0..<1) * R * 0.9, z: sin(a) * r))
            pIdx.append(UInt16(i))
        }
        let el = SCNGeometryElement(indices: pIdx, primitiveType: .point)
        el.pointSize = CGFloat(R * 0.012)
        el.minimumPointScreenSpaceRadius = 1
        el.maximumPointScreenSpaceRadius = 2.5
        let polvere = SCNGeometry(sources: [SCNGeometrySource(vertices: pv)], elements: [el])
        let nodo = pezzo(polvere, Self.pieno(0x8ff0ff, 0.55), [0, Self.pavimento, 0], in: scena.rootNode)
        let sale = CGFloat(R * 0.05)
        nodo.runAction(.repeatForever(.sequence([.moveBy(x: 0, y: sale, z: 0, duration: 9), .moveBy(x: 0, y: -sale, z: 0, duration: 0)])))
        nodo.runAction(.repeatForever(.rotateBy(x: 0, y: -0.3, z: 0, duration: 10)))
    }

    // MARK: Etichette (cartellini sempre davanti, che guardano la camera)

    private func etichetta(_ testo: String, _ stile: EtichettaOlo.Stile, _ p: SIMD3<Float>) -> SCNNode? {
        let r = ImageRenderer(content: EtichettaOlo(testo: testo, stile: stile).padding(8))
        r.scale = 3
        guard let img = r.cgImage else { return nil }
        let w = CGFloat(img.width) / 3 * Self.metriPerPunto, h = CGFloat(img.height) / 3 * Self.metriPerPunto
        let piano = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = img
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        m.blendMode = .alpha
        piano.materials = [m]
        let nodo = SCNNode(geometry: piano)
        nodo.simdPosition = p
        nodo.constraints = [SCNBillboardConstraint()]
        nodo.renderingOrder = 100
        radice.addChildNode(nodo)
        return nodo
    }
}

#if os(iOS)

// MARK: - iPhone: la vista 3D e il pannello ORGANISMO

/// La scena in una SCNView trasparente: il dito in orizzontale gira il modello, in verticale scorre la pagina (pan-y del mockup).
struct VistaOlogramma: UIViewRepresentable {
    let ologramma: OlogrammaOrganismo

    func makeCoordinator() -> Coordinatore { Coordinatore(ologramma) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero, options: nil)
        v.scene = ologramma.scena
        v.pointOfView = ologramma.camera
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 30
        v.allowsCameraControl = false
        v.isPlaying = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinatore.trascina(_:)))
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}

    static func dismantleUIView(_ v: SCNView, coordinator: Coordinatore) {
        v.isPlaying = false
        v.scene = nil
    }

    final class Coordinatore: NSObject, UIGestureRecognizerDelegate {
        let ologramma: OlogrammaOrganismo
        private var yaw0: Float = 0
        init(_ o: OlogrammaOrganismo) { ologramma = o }

        @objc func trascina(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                yaw0 = ologramma.yaw
                ologramma.tocco(inizio: true)
            case .changed:
                ologramma.yaw = yaw0 - Float(g.translation(in: g.view).x) * 0.009
            default:
                ologramma.tocco(inizio: false)
            }
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool { true }
    }
}

/// ORGANISMO in Vitals: la persona olografica che gira, poi Prontezza, Sonno, Battito a riposo, Passi ieri, Umore.
/// Lo stesso `Pannello` delle altre schede (e di A VOCE sotto): angoli, fondo e titolo identici.
struct PannelloOrganismo: View {
    let oggi: SaluteOggi?
    let diario: DatiVitals?
    @StateObject private var ologramma = OlogrammaOrganismo(leggero: false)
    @State private var storia: [Date: SaluteStorica.Valori] = [:]
    private let chiaro = Color(red: 207 / 255, green: 226 / 255, blue: 232 / 255)   // #cfe2e8

    private var dati: DatiOrganismo { DatiOrganismo.calcola(oggi: oggi, storia: storia, diario: diario) }

    var body: some View {
        let d = dati
        Pannello(titolo: "ORGANISMO", tinta: .ciano) {
            VistaOlogramma(ologramma: ologramma)
                .aspectRatio(720.0 / 640.0, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Text("360°").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Color.ciano).opacity(0.75)
                        .padding(.trailing, 10).padding(.bottom, 8)
                        .allowsHitTesting(false)
                }
                .background(Color.ciano.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.22), lineWidth: 1))
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Ologramma dell'organismo. \(d.etichettaPronto)")
            riga("Prontezza", d.testoProntezza)
            Text(d.contoProntezza).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue)
                .fixedSize(horizontal: false, vertical: true)
            riga("Sonno", d.testoSonno)
            riga("Battito a riposo", d.testoBattito)
            riga("Passi ieri", d.testoPassi)
            riga("Umore", d.testoUmore)
        }
        .task { storia = await SaluteStorica.giorni(31) }
        .onAppear { ologramma.pausa(false); ologramma.aggiorna(d) }
        .onDisappear { ologramma.pausa(true) }
        .onChange(of: d) { _, nuovi in ologramma.aggiorna(nuovi) }
    }

    private func riga(_ titolo: String, _ valore: String) -> some View {
        HStack(spacing: 10) {
            Text(titolo).font(.system(size: 14)).foregroundStyle(chiaro)
            Spacer(minLength: 6)
            Text(valore).font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(Color.tenue).lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

// A VOCE: si usa PannelloAVoce di Pannelli.swift (parte A), lo stesso di Telefono, Ricordi, Meteo ed Email.

#endif
