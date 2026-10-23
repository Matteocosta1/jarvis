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

/// La scena dell'Organismo, costruita come `persona(giunture(false), "fantasma")` + «Armatura» del mockup:
/// capsule, sfere e coni (altezza 1,78 m), materiale olografico ciano additivo con il bordo luminoso (fresnel)
/// e le righe di scansione, anello ambra sulla testa, cuore verde che batte, anelli verdi alle ginocchia,
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
        etichette = [
            etichetta(d.etichettaSonno, .ambra, SIMD3(0.42, 1.74, 0)),
            etichetta(d.etichettaBattito, .verde, SIMD3(-0.5, 1.34, 0)),
            etichetta(d.etichettaPassi, .verde, SIMD3(0.42, 0.5, 0)),
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
    private func cono(_ alto: Float, _ basso: Float, _ h: Float) -> SCNGeometry {
        let g = SCNCone(topRadius: CGFloat(alto), bottomRadius: CGFloat(basso), height: CGFloat(h))
        g.radialSegmentCount = leggero ? 14 : 28; g.heightSegmentCount = 1
        return g
    }
    /// Mezza sfera in alto (i capelli: SphereGeometry con thetaLength π/2).
    private func calotta(_ r: Float) -> SCNGeometry {
        let nf = leggero ? 12 : 24, nt = leggero ? 4 : 8
        var v: [SCNVector3] = [], n: [SCNVector3] = [], idx: [UInt16] = []
        for i in 0...nt {
            let t = Float(i) / Float(nt) * .pi / 2
            for j in 0...nf {
                let p = Float(j) / Float(nf) * 2 * .pi
                let d = SIMD3<Float>(-cos(p) * sin(t), cos(t), sin(p) * sin(t))
                v.append(SCNVector3(x: d.x * r, y: d.y * r, z: d.z * r)); n.append(SCNVector3(x: d.x, y: d.y, z: d.z))
            }
        }
        for i in 0..<nt { for j in 0..<nf {
            let a = UInt16(i * (nf + 1) + j), b = a + UInt16(nf + 1)
            idx += [a, b, a + 1, b, b + 1, a + 1]
        } }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
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

    // MARK: La persona (giunture(false), solo il fantasma olografico)

    private func persona() {
        let J: [String: SIMD3<Float>] = [
            "testa": [0, 1.67, 0], "collo": [0, 1.5, 0], "spSx": [-0.2, 1.42, 0], "spDx": [0.2, 1.42, 0],
            "goSx": [-0.27, 1.16, 0], "goDx": [0.27, 1.16, 0], "maSx": [-0.31, 0.9, 0.02], "maDx": [0.31, 0.9, 0.02],
            "bac": [0, 0.95, 0], "anSx": [-0.1, 0.92, 0], "anDx": [0.1, 0.92, 0], "giSx": [-0.11, 0.5, 0.01], "giDx": [0.11, 0.5, 0.01],
            "piSx": [-0.11, 0.08, 0], "piDx": [0.11, 0.08, 0],
        ]
        func g(_ k: String) -> SIMD3<Float> { J[k] ?? .zero }
        let m = Self.olo(0x4fe3ff, alfa: 0.32)
        for (s, sg) in [("Sx", Float(-1)), ("Dx", Float(1))] {
            pezzo(capsula(0.045, 0.16), m, [sg * 0.11, 0.045, 0.04], rot: [.pi / 2, 0, 0], scala: [1, 1, 0.8])     // scarpa
            osso(g("pi" + s), g("gi" + s), 0.06, m)
            osso(g("gi" + s), g("an" + s), 0.085, m)
            let sp = g("sp" + s), go = g("go" + s), ma = g("ma" + s)
            let meta = sp + (go - sp) * 0.45
            osso(sp, meta, 0.058, m); osso(meta, go, 0.047, m); osso(go, ma, 0.041, m)
            pezzo(sfera(0.045), m, ma + simd_normalize(ma - go) * 0.07, scala: [0.65, 1.2, 0.9])                  // mano
            pezzo(sfera(0.085), m, [sg * 0.18, 1.41, 0])                                                            // spalla
        }
        pezzo(capsula(0.11, 0.14), m, [0, 0.95, 0], rot: [0, 0, .pi / 2], scala: [1, 1, 0.75])                       // bacino
        let cintura = SCNCylinder(radius: 0.168, height: 0.04); cintura.radialSegmentCount = leggero ? 14 : 28
        pezzo(cintura, m, [0, 1.01, 0], scala: [1, 1, 0.72])
        pezzo(cono(0.195, 0.165, 0.46), m, [0, 1.24, 0], scala: [1, 1, 0.62])                                       // busto
        pezzo(cono(0.05, 0.055, 0.12), m, [0, 1.52, 0])                                                             // collo
        pezzo(sfera(0.105), m, [0, 1.67, 0], scala: [0.92, 1.12, 1])                                                // testa
        pezzo(calotta(0.112), m, [0, 1.695, -0.008], scala: [0.94, 1.05, 1.02])                                     // capelli
    }

    // MARK: Armatura: i parametri sulle zone del corpo

    private func armatura() {
        // sonno: l'anello ambra sulla testa, che gira
        let anello = SCNTorus(ringRadius: 0.16, pipeRadius: 0.007)
        anello.ringSegmentCount = leggero ? 32 : 64; anello.pipeSegmentCount = leggero ? 6 : 8
        let testa = pezzo(anello, Self.pieno(0xffb45a, 0.9), [0, 1.67, 0])
        testa.runAction(.repeatForever(.rotateBy(x: 0, y: 0.8, z: 0, duration: 1)))
        // battito: il cuore verde e il suo alone
        let sc = sfera(0.045); sc.materials = [Self.pieno(0x78e696, 0.9)]
        cuore.geometry = sc; cuore.simdPosition = [-0.05, 1.32, 0.07]; radice.addChildNode(cuore)
        let sa = sfera(0.09); sa.materials = [Self.pieno(0x78e696, 1)]
        alone.geometry = sa; alone.simdPosition = [-0.05, 1.32, 0.07]; alone.opacity = 0.12; radice.addChildNode(alone)
        // passi: gli anelli verdi alle ginocchia, che respirano (0,55 + 0,35·sin(2t + i))
        for (i, x) in [Float(-0.11), Float(0.11)].enumerated() {
            let t = SCNTorus(ringRadius: 0.085, pipeRadius: 0.006)
            t.ringSegmentCount = leggero ? 24 : 48; t.pipeSegmentCount = leggero ? 6 : 8
            let gin = pezzo(t, Self.pieno(0x78e696, 1), [x, 0.5, 0.01])
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
            let v = [SCNVector3(x: 0, y: 0.95, z: 0), SCNVector3(x: 0, y: 1.5, z: 0)]
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
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
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

/// Il riquadro dei pannelli del mockup (.pannello): fondo ciano 5%, bordo 22%, angoli 12.
struct StilePannello22: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciano.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.22), lineWidth: 1))
    }
}

/// Il titolo dei pannelli del mockup (h3): 10 pt mono, spaziato, ciano.
struct TitoloPannello22: View {
    let testo: String
    var body: some View {
        Text(testo).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
    }
}

/// ORGANISMO in Vitals: la persona olografica che gira, poi Prontezza, Sonno, Battito a riposo, Passi ieri, Umore.
struct PannelloOrganismo: View {
    let oggi: SaluteOggi?
    let diario: DatiVitals?
    @StateObject private var ologramma = OlogrammaOrganismo(leggero: false)
    @State private var storia: [Date: SaluteStorica.Valori] = [:]
    private let chiaro = Color(red: 207 / 255, green: 226 / 255, blue: 232 / 255)   // #cfe2e8

    private var dati: DatiOrganismo { DatiOrganismo.calcola(oggi: oggi, storia: storia, diario: diario) }

    var body: some View {
        let d = dati
        VStack(alignment: .leading, spacing: 8) {
            TitoloPannello22(testo: "ORGANISMO")
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
        .modifier(StilePannello22())
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
