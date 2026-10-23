#if os(iOS)
import SwiftUI
import Combine
import AVFoundation
import Vision
import UIKit
import simd

/// L'allenatore di JARVIS: inquadra chi si allena, l'iPhone riconosce lo scheletro del corpo (Vision, tutto in locale)
/// e lo disegna in stile HUD sopra la ripresa. JARVIS commenta la postura a voce (schiena, spalle, braccia),
/// conta le ripetizioni e a fine serie fa il riassunto. Pensato per il Pilates, va bene per squat, piegamenti, addominali.
/// Build 22: con «Specchio» (conta le ginocchia) c'è lo SPECCHIO · ALLENAMENTO del mockup, con lo scheletro «giusto» e i conti sul corpo.
/// Si apre sul Busto come sempre: lo Specchio parte scegliendolo, oppure con «Jarvis, modalità specchio» / «allenamento allo specchio».
extension Notification.Name {
    /// «Jarvis, modalità specchio» / «allenamento allo specchio»: l'Allenatore passa allo Specchio.
    static let jarvisSpecchio = Notification.Name("jarvisSpecchio")
}

struct Allenatore: View {
    let chiudi: () -> Void
    @StateObject private var motore = MotoreAllenatore()
    @State private var orecchio = OrecchioComandi()   // «Jarvis, fine serie», «Jarvis, quante ripetizioni?», «Jarvis, pausa»…

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaAllenatore(sessione: motore.sessione).ignoresSafeArea()
            ScheletroHUD(posa: motore.posa, allarme: motore.posturaFuori, specchio: motore.frontale).ignoresSafeArea().allowsHitTesting(false)
            // BUILD 22 · B — Specchio: lo scheletro giusto in verde e i conti sul corpo
            if motore.giunto == .ginocchia {
                SpecchioHUD(posa: motore.posa, ginocchio: motore.ginocchio, in3D: motore.ginocchioIn3D, altezza: motore.altezzaInPiedi,
                            ripetizioni: motore.ripetizioni, schiena: motore.inclinazioneSchiena, specchio: motore.frontale)
                    .ignoresSafeArea().allowsHitTesting(false)
            }

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("J.A.R.V.I.S.").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                        Text("ALLENATORE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.7)
                    }
                    .foregroundStyle(Color.ciano)
                    Spacer()
                    Button { Suoni.tocco(); motore.cambiaCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ciano).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("Cambia fotocamera")
                    Button { Suoni.tocco(); motore.ferma(); chiudi() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.ciano).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("Chiudi")
                }
                .padding(.horizontal, 20).padding(.top, 8)

                // telemetria (nello Specchio no: i numeri stanno solo sul corpo, come nel mockup)
                if motore.giunto != .ginocchia {
                    HStack(spacing: 10) {
                        dato("RIPETIZIONI", "\(motore.ripetizioni)", caldo: false)
                        dato("SCHIENA", motore.posa == nil ? "—" : "\(Int(motore.inclinazioneSchiena))°", caldo: motore.inclinazioneSchiena > motore.sogliaSchiena)
                        dato("SIMMETRIA", motore.posa == nil ? "—" : "\(Int(motore.simmetria))%", caldo: motore.simmetria < 85)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                Text(motore.commento)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .opacity(motore.commento.isEmpty ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: motore.commento)

                if motore.giunto == .ginocchia {
                    Text("SPECCHIO · ALLENAMENTO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color.ciano)
                }

                Picker("Conteggio", selection: $motore.giunto) {
                    Text("Busto").tag(MotoreAllenatore.Giunto.busto)
                    Text("Mani").tag(MotoreAllenatore.Giunto.mani)
                    Text("Specchio").tag(MotoreAllenatore.Giunto.ginocchia)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                HStack(spacing: 14) {
                    Button { Suoni.tocco(); motore.azzera() } label: {
                        Label("Azzera", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.ciano).frame(maxWidth: .infinity).frame(height: 48)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.6), lineWidth: 1))
                    }
                    Button { Suoni.tocco(); motore.fineSerie() } label: {
                        Label("Fine serie", systemImage: "flag.checkered")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.fondo).frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.ciano2).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .buttonStyle(StileStark())
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .statusBarHidden()
        .onReceive(NotificationCenter.default.publisher(for: .jarvisSpecchio)) { _ in   // detto con l'Allenatore già aperto
            MotoreAllenatore.specchioRichiesto = false; motore.giunto = .ginocchia
        }
        .task {
            if MotoreAllenatore.specchioRichiesto { MotoreAllenatore.specchioRichiesto = false; motore.giunto = .ginocchia }
            await motore.avvia()
            // i comandi a voce: dopo il suono d'apertura (come nella Sentinella), sempre con «Jarvis» davanti
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            orecchio.dentro = .allenatore
            orecchio.comando = { c in
                switch c {
                case .torna: motore.ferma(); orecchio.ferma(); chiudi()
                case .allenatore(let a): motore.aVoce(a)
                default: break
                }
            }
            motore.ascoltoComandi = true
            orecchio.avvia()
        }
        .onDisappear { orecchio.ferma(); motore.ferma() }
        .aperturaHUD("Allenatore", fotocamera: true)
    }

    private func dato(_ titolo: String, _ valore: String, caldo: Bool) -> some View {
        VStack(spacing: 2) {
            Text(valore).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(caldo ? Color.orange : .white)
            Text(titolo).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.black.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke((caldo ? Color.orange : Color.ciano).opacity(0.5), lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Lo scheletro disegnato sopra la ripresa

struct ScheletroHUD: View {
    let posa: [VNHumanBodyPoseObservation.JointName: CGPoint]?
    let allarme: Bool
    let specchio: Bool

    private static let ossa: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .nose), (.neck, .leftShoulder), (.neck, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.neck, .root), (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                guard let posa else { return }
                let colore = allarme ? Color.orange : Color.ciano
                func p(_ g: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                    guard let n = posa[g] else { return nil }
                    let x = specchio ? 1 - n.x : n.x
                    return CGPoint(x: x * size.width, y: (1 - n.y) * size.height)
                }
                var linee = Path()
                for (a, b) in ScheletroHUD.ossa { if let pa = p(a), let pb = p(b) { linee.move(to: pa); linee.addLine(to: pb) } }
                var bagliore = gc
                bagliore.blendMode = .plusLighter
                bagliore.stroke(linee, with: .color(colore.opacity(0.35)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                gc.stroke(linee, with: .color(colore.opacity(0.95)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                for (g, _) in posa {
                    guard let c = p(g) else { continue }
                    let r: CGFloat = g == .nose ? 7 : 5
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.9)))
                    var anello = Path()
                    let inizio = Angle(radians: t * 1.5)
                    anello.addArc(center: c, radius: r + 5, startAngle: inizio, endAngle: inizio + .radians(.pi * 1.2), clockwise: false)
                    gc.stroke(anello, with: .color(colore.opacity(0.7)), lineWidth: 1)
                }
                // linea verticale di riferimento per la schiena
                if let collo = p(.neck), let bacino = p(.root) {
                    var rif = Path()
                    rif.move(to: CGPoint(x: bacino.x, y: bacino.y)); rif.addLine(to: CGPoint(x: bacino.x, y: collo.y - 20))
                    gc.stroke(rif, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
        }
    }
}

// MARK: - BUILD 22 · B — Specchio

/// Lo Specchio (mockup «SPECCHIO · ALLENAMENTO»): sopra il suo scheletro, quello «giusto» in verde trasparente
/// che scende fino alla profondità corretta (ginocchio a 90°), e i conti sul corpo: RIPETIZIONI n / 12 sopra la testa,
/// GINOCCHIO accanto al ginocchio destro, SCHIENA accanto al busto (la riga della telemetria in alto qui è nascosta).
/// Il verde è la ripetizione del mockup (`posa(s)` di scena3d) messa sull'immagine: piedi sulle sue caviglie,
/// misura dalla sua altezza in piedi (collo → caviglie = 1,34 m del modello), girato come lui (di fronte o di lato).
/// Va un po' avanti a lui: è in fondo quando lui è all'86% della discesa, così si vede quanto manca.
struct SpecchioHUD: View {
    let posa: [VNHumanBodyPoseObservation.JointName: CGPoint]?
    let ginocchio: Double?
    let in3D: Bool
    let altezza: Double
    let ripetizioni: Int
    let schiena: Double
    let specchio: Bool

    static let obiettivo = 12

    var body: some View {
        GeometryReader { geo in
            if let s = Sagoma(posa: posa, ginocchio: in3D ? ginocchio : nil, altezza: altezza, specchio: specchio, area: geo.size) {
                ZStack {
                    Canvas { gc, _ in s.disegna(&gc) }
                    EtichettaOlo(testo: "RIPETIZIONI \(ripetizioni) / \(Self.obiettivo)", stile: .grande).position(s.ripetizioni)
                    EtichettaOlo(testo: "GINOCCHIO " + (ginocchio.map { "\(Int($0.rounded()))°" } ?? "—"), stile: .ambra).position(s.ginocchio)
                    EtichettaOlo(testo: "SCHIENA \(Int(schiena))°").position(s.schiena)
                }
            }
        }
    }

    /// Lo scheletro giusto e il posto delle etichette, in punti dello schermo (stessa mappa di ScheletroHUD).
    private struct Sagoma {
        typealias V = SIMD3<Double>
        var ossa: [(CGPoint, CGPoint)] = []
        var nodi: [(CGPoint, Bool)] = []          // (punto, è la testa)
        var ripetizioni = CGPoint.zero, ginocchio = CGPoint.zero, schiena = CGPoint.zero

        private static let coppie: [(String, String)] = [
            ("testa", "collo"), ("collo", "spSx"), ("collo", "spDx"), ("spSx", "goSx"), ("spDx", "goDx"), ("goSx", "maSx"), ("goDx", "maDx"),
            ("collo", "bac"), ("bac", "anSx"), ("bac", "anDx"), ("anSx", "giSx"), ("anDx", "giDx"), ("giSx", "piSx"), ("giDx", "piDx"),
        ]

        init?(posa: [VNHumanBodyPoseObservation.JointName: CGPoint]?, ginocchio g: Double?, altezza: Double, specchio: Bool, area: CGSize) {
            guard let posa, altezza > 0.05, area.width > 0, area.height > 0 else { return nil }
            let W = area.width, H = area.height
            func p(_ j: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let n = posa[j] else { return nil }
                return CGPoint(x: (specchio ? 1 - n.x : n.x) * W, y: (1 - n.y) * H)
            }
            guard let cs = p(.leftAnkle), let cd = p(.rightAnkle) else { return nil }
            let piedi = CGPoint(x: (cs.x + cd.x) / 2, y: (cs.y + cd.y) / 2)
            let ky = CGFloat(altezza) * H / 1.34                  // punti per metro in verticale
            let kx = ky * (W / H) / 0.5625                        // e in orizzontale (fotogramma 9:16 steso sullo schermo)
            let lato: CGFloat = cs.x <= cd.x ? 1 : -1             // il suo sinistro a sinistra dello schermo?
            var fronte: CGFloat = 1                               // 1 di fronte, 0 di lato (dalla larghezza delle spalle)
            if let ss = p(.leftShoulder), let sd = p(.rightShoulder) { fronte = min(1, abs(ss.x - sd.x) / (0.40 * kx)) }
            let fianco = (1 - fronte * fronte).squareRoot()
            var verso: CGFloat = 1                                // di lato: da che parte guarda
            if let n = p(.nose), let c = p(.neck), abs(n.x - c.x) > 2 { verso = n.x > c.x ? 1 : -1 }
            // quanto è sceso: dal ginocchio 3D (175° in piedi, 90° in fondo) o, senza, dall'altezza del bacino
            var sceso = 0.0
            if let g { sceso = (175 - g) / 85 }
            else if let b = p(.root) { sceso = (0.95 - (Double((piedi.y - b.y) / ky) + 0.08)) / 0.37 }
            sceso = min(1, max(0, sceso))
            let J = Self.posa(min(1, sceso / 0.86))
            func q(_ v: V) -> CGPoint {
                CGPoint(x: piedi.x + (CGFloat(v.x) * lato * fronte + CGFloat(v.z) * verso * fianco) * kx, y: piedi.y - CGFloat(v.y - 0.08) * ky)
            }
            ossa = Self.coppie.compactMap { a, b in
                guard let pa = J[a], let pb = J[b] else { return nil }
                return (q(pa), q(pb))
            }
            nodi = J.map { (q($0.value), $0.key == "testa") }
            // le etichette: dentro lo schermo, lontane dai tasti
            func dentro(_ c: CGPoint) -> CGPoint { CGPoint(x: min(max(c.x, 90), W - 90), y: min(max(c.y, H * 0.22), H * 0.74)) }
            ripetizioni = dentro(CGPoint(x: piedi.x, y: piedi.y - (2.02 - 0.08) * ky))
            let gd = p(.rightKnee), gs = p(.leftKnee)
            var fuori: CGFloat = 1                                // l'etichetta del ginocchio va dalla parte del ginocchio destro
            if let gd, let gs, gd.x < gs.x { fuori = -1 }
            let pg = gd ?? gs ?? q(J["giDx"] ?? V(0.14, 0.5, 0))
            ginocchio = dentro(CGPoint(x: pg.x + 0.32 * kx * fuori, y: pg.y))
            let busto: CGPoint
            if let b = p(.root), let c = p(.neck) { busto = CGPoint(x: (b.x + c.x) / 2, y: (b.y + c.y) / 2) }
            else { busto = q(V(0, 1.2, 0)) }
            schiena = dentro(CGPoint(x: busto.x - 0.5 * kx * fuori, y: busto.y))
        }

        /// La ripetizione giusta del mockup a profondità s (0 in piedi, 1 in fondo): metri, piedi a terra, guarda verso di noi.
        static func posa(_ s: Double) -> [String: V] {
            let th = 0.62 * s
            let dir = V(0, cos(th), sin(th))
            let ay = 0.92 - 0.37 * s, az = -0.22 * s
            let B = V(0, ay + 0.03, az)
            let C = B + dir * 0.55
            func sp(_ x: Double) -> V { V(x, C.y - 0.08, C.z) }
            func ma(_ x: Double) -> V { V(x * 1.05, C.y - 0.08 - 0.5 * (1 - s) - 0.05 * s, C.z + 0.55 * s + 0.02) }
            func go(_ x: Double) -> V { V(x * 1.1, (sp(x).y + ma(x).y) / 2, (C.z + ma(x).z) / 2 - 0.02) }
            var J: [String: V] = [:]
            J["testa"] = C + dir * 0.17
            J["collo"] = C
            J["spSx"] = sp(-0.2); J["spDx"] = sp(0.2)
            J["goSx"] = go(-0.22); J["goDx"] = go(0.22)
            J["maSx"] = ma(-0.22); J["maDx"] = ma(0.22)
            J["bac"] = B
            J["anSx"] = V(-0.1, ay, az); J["anDx"] = V(0.1, ay, az)
            J["giSx"] = V(-0.14, 0.5 - 0.05 * s, 0.15 * s); J["giDx"] = V(0.14, 0.5 - 0.05 * s, 0.15 * s)
            J["piSx"] = V(-0.13, 0.08, 0); J["piDx"] = V(0.13, 0.08, 0)
            return J
        }

        /// Ossa verdi al 35% e giunture chiare al 35%, sommate alla ripresa (additivo, come nel mockup).
        func disegna(_ gc: inout GraphicsContext) {
            gc.blendMode = .plusLighter
            var linee = Path()
            for (a, b) in ossa { linee.move(to: a); linee.addLine(to: b) }
            gc.stroke(linee, with: .color(Color(red: 120 / 255, green: 230 / 255, blue: 150 / 255).opacity(0.35)),
                      style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            let chiaro = Color(red: 230 / 255, green: 244 / 255, blue: 248 / 255).opacity(0.35)
            for (c, testa) in nodi {
                let r: CGFloat = testa ? 6 : 4
                gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(chiaro))
            }
        }
    }
}

struct AnteprimaAllenatore: UIViewRepresentable {
    let sessione: AVCaptureSession
    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var anteprima: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Vista {
        let v = Vista(); v.backgroundColor = .black
        v.anteprima.session = sessione; v.anteprima.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: Vista, context: Context) {}
}

// MARK: - Il motore: fotocamera, Vision, conteggio e commenti

@MainActor
final class MotoreAllenatore: NSObject, ObservableObject {
    enum Giunto { case busto, mani, ginocchia }

    @Published var posa: [VNHumanBodyPoseObservation.JointName: CGPoint]?
    @Published var ripetizioni = 0
    @Published var inclinazioneSchiena: Double = 0
    @Published var simmetria: Double = 100
    @Published var posturaFuori = false
    @Published var commento = ""
    @Published var frontale = false
    @Published var giunto: Giunto = .busto { didSet { azzeraConteggio(); camera.usa3D(giunto == .ginocchia) } }   // si apre sul Busto, come sempre
    /// «Jarvis, modalità specchio» con l'Allenatore ancora chiuso: lo Specchio parte appena si apre.
    static var specchioRichiesto = false
    @Published var ginocchio: Double?           // angolo del ginocchio in gradi (3D se c'è, se no dall'immagine)
    @Published var altezzaInPiedi: Double = 0   // collo → caviglie in piedi, in frazione dell'altezza dell'immagine
    @Published var ginocchioIn3D = false        // l'angolo viene dallo scheletro 3D

    /// Oltre questa inclinazione la schiena è «fuori asse». Nello squat (ginocchia) il busto corretto si piega in avanti
    /// di circa 30°: lì la soglia è 45°, negli altri casi 12°.
    var sogliaSchiena: Double { giunto == .ginocchia ? 45 : 12 }

    private let camera = CameraPosa()
    var sessione: AVCaptureSession { camera.sessione }

    // conteggio: posizione «su» e «giù» del giunto scelto, con isteresi
    private var altezza: Double = 0            // 0 in alto, 1 in basso (coordinate schermo)
    private var minimo: Double = 1, massimo: Double = 0
    private var giu = false
    // squat con l'angolo del ginocchio (build 22)
    private var giuSquat = false
    private var conAngolo = false               // arrivato l'angolo 3D: la serie si conta con quello
    private var ultimaRipetizione = Date.distantPast
    private var ultimoAngolo3D = Date.distantPast
    private var ultimoCampione = Date.distantPast
    private var serieSchiena: [Double] = [], serieSimmetria: [Double] = []
    private var ultimoCommento = Date.distantPast
    private var ultimoAvviso = ""
    private var voceInCorso = false
    private var lettore: AVAudioPlayer?
    private let sintesi = AVSpeechSynthesizer()
    private var inizioSerie = Date()
    var ascoltoComandi = false                  // il microfono dei comandi è acceso: la voce non deve spegnerlo
    @Published var inPausa = false

    /// I comandi a voce («Jarvis, …»): gli stessi tasti, più le domande sulla serie e la pausa.
    func aVoce(_ a: ComandoVocale.AzioneAllenatore) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch a {
        case .fineSerie: inPausa = false; fineSerie()
        case .azzera: inPausa = false; azzera(); Task { await parla("Azzerato, Sir.") }
        case .ripetizioni:
            let n = ripetizioni
            Task { await parla(n == 0 ? "Nessuna ripetizione contata, Sir." : "\(n) ripetizion\(n == 1 ? "e" : "i"), Sir.") }
        case .postura:
            guard posa != nil else { Task { await parla("Non la vedo, Sir: si metta tutta nell'inquadratura.") }; return }
            let sch = Int(inclinazioneSchiena), sim = Int(simmetria), soglia = Int(sogliaSchiena)
            let giudizio = sch <= soglia && sim >= 85 ? "Va bene così." : (sch > soglia ? "Raddrizzi la schiena." : "Cerchi la simmetria.")
            Task { await parla("Schiena a \(sch) gradi, simmetria al \(sim) per cento. \(giudizio)") }
        case .camera: cambiaCamera()
        case .pausa:
            inPausa = true
            commento = "In pausa. «Jarvis, riprendi» per continuare."
            Task { await parla("In pausa, Sir.") }
        case .riprendi:
            inPausa = false
            commento = "Si riparte, Sir."
            Task { await parla("Si riparte, Sir.") }
        case .conta(let parte):
            switch parte {
            case .busto: giunto = .busto
            case .mani: giunto = .mani
            case .ginocchia: giunto = .ginocchia
            }
            // la terza scelta ora si chiama Specchio (il corpo 3D con i conti sopra): JARVIS la chiama così
            let frase = parte == .busto ? "Conto il busto, Sir." : (parte == .mani ? "Conto le mani, Sir." : "Specchio, Sir.")
            Task { await parla(frase) }
        }
    }

    func avvia() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { commento = "Serve il permesso fotocamera, Sir."; return }
        camera.esito = { [weak self] punti, ginocchio in Task { @MainActor [weak self] in self?.ricevi(punti, ginocchio3D: ginocchio) } }
        camera.usa3D(giunto == .ginocchia)
        configura(frontale: false)
        inizioSerie = Date()
        commento = "Inquadri tutta la persona, Sir."
    }

    func ferma() {
        camera.ferma()
        lettore?.stop(); lettore = nil
        sintesi.stopSpeaking(at: .immediate)
    }

    func cambiaCamera() { configura(frontale: !frontale) }

    func azzera() {
        azzeraConteggio()
        serieSchiena.removeAll(); serieSimmetria.removeAll()
        inizioSerie = Date()
        commento = "Azzerato. Quando vuole, Sir."
    }

    private func azzeraConteggio() { ripetizioni = 0; minimo = 1; massimo = 0; giu = false; giuSquat = false; conAngolo = false }

    func fineSerie() {
        let n = ripetizioni
        let schiena = serieSchiena.isEmpty ? 0 : serieSchiena.reduce(0, +) / Double(serieSchiena.count)
        let simm = serieSimmetria.isEmpty ? 100 : serieSimmetria.reduce(0, +) / Double(serieSimmetria.count)
        let durata = Int(Date().timeIntervalSince(inizioSerie))
        var frase = n == 0 ? "Serie chiusa senza ripetizioni contate, Sir." : "Serie chiusa: \(n) ripetizion\(n == 1 ? "e" : "i") in \(durata / 60) minuti e \(durata % 60) secondi."
        if !serieSchiena.isEmpty {
            let (ok, quasi) = giunto == .ginocchia ? (sogliaSchiena - 15, sogliaSchiena) : (8.0, 15.0)   // nello Specchio il busto si piega di suo
            frase += schiena < ok ? " Schiena allineata per tutta la serie, davvero bene." : schiena < quasi ? " Schiena un po' inclinata, in media \(Int(schiena)) gradi: si può fare meglio." : " Attenzione alla schiena: in media \(Int(schiena)) gradi fuori asse."
            frase += simm >= 92 ? " Simmetria ottima." : " Simmetria al \(Int(simm)) per cento: un lato lavora più dell'altro."
        }
        commento = frase
        Task { await parla(frase) }
        azzera()
        commento = frase
    }

    private func configura(frontale nuova: Bool) {
        camera.configura(frontale: nuova) { [weak self] ok in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if ok { self.frontale = nuova } else { self.commento = "Fotocamera non disponibile, Sir." }
            }
        }
    }

    // MARK: Analisi di ogni posa

    private func ricevi(_ punti: [VNHumanBodyPoseObservation.JointName: CGPoint]?, ginocchio3D: Double?) {
        posa = punti
        misuraSpecchio(punti, ginocchio3D)
        guard !inPausa else { posturaFuori = false; return }      // in pausa: lo scheletro si vede, niente conteggio né commenti
        guard let p = punti, let collo = p[.neck], let bacino = p[.root] else { posturaFuori = false; return }
        // schiena: angolo tra bacino→collo e la verticale (coordinate Vision: y verso l'alto)
        let dx = (collo.x - bacino.x) * 0.5625, dy = collo.y - bacino.y   // il fotogramma è verticale 9:16: l'asse x va riscalato
        let angolo = abs(atan2(dx, dy)) * 180 / .pi
        inclinazioneSchiena = inclinazioneSchiena * 0.7 + angolo * 0.3
        // simmetria: spalle e polsi alla stessa altezza, in rapporto alla larghezza delle spalle
        if let sx = p[.leftShoulder], let dxs = p[.rightShoulder] {
            let larg = max(0.05, abs(sx.x - dxs.x))
            var scarto = abs(sx.y - dxs.y) / larg
            if let px = p[.leftWrist], let pd = p[.rightWrist] { scarto = max(scarto, abs(px.y - pd.y) / larg * 0.5) }
            let s = max(0, 100 - scarto * 100)
            simmetria = simmetria * 0.7 + s * 0.3
        }
        posturaFuori = inclinazioneSchiena > sogliaSchiena || simmetria < 85
        let adesso = Date()
        if adesso.timeIntervalSince(ultimoCampione) > 0.5 {
            ultimoCampione = adesso
            serieSchiena.append(inclinazioneSchiena); serieSimmetria.append(simmetria)
        }
        conta(p)
        commenta(adesso)
    }

    /// Conta le ripetizioni: il giunto scelto scende sotto una soglia e torna su.
    private func conta(_ p: [VNHumanBodyPoseObservation.JointName: CGPoint]) {
        if giunto == .ginocchia && conAngolo { contaSquat(); return }
        let y: Double?
        switch giunto {
        case .busto: y = p[.neck].map { 1 - $0.y }
        case .mani: if let a = p[.leftWrist], let b = p[.rightWrist] { y = 1 - (a.y + b.y) / 2 } else { y = nil }
        case .ginocchia: if let a = p[.leftKnee], let b = p[.rightKnee] { y = 1 - (a.y + b.y) / 2 } else { y = nil }
        }
        guard let y else { return }
        altezza = altezza == 0 ? y : altezza * 0.6 + y * 0.4
        minimo = min(minimo * 0.998 + altezza * 0.002, altezza)      // i limiti si adattano piano piano
        massimo = max(massimo * 0.998 + altezza * 0.002, altezza)
        let corsa = massimo - minimo
        guard corsa > 0.08 else { return }                            // movimento troppo piccolo: niente da contare
        let pos = (altezza - minimo) / corsa                          // 0 = punto più alto, 1 = più basso
        if !giu && pos > 0.7 { giu = true }
        if giu && pos < 0.3 {
            giu = false
            unaRipetizione()
        }
    }

    private func unaRipetizione() {
        ripetizioni += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Suoni.tocco()
    }

    // MARK: Specchio (build 22)

    /// Squat contato con l'angolo del ginocchio: giù sotto i 110°, su sopra i 155°.
    /// I 45° di isteresi e almeno 0,6 s tra due ripetizioni evitano di contare due volte lo stesso squat.
    private func contaSquat() {
        guard let g = ginocchio else { return }
        if !giuSquat && g < 110 { giuSquat = true }
        if giuSquat && g > 155 && Date().timeIntervalSince(ultimaRipetizione) > 0.6 {
            giuSquat = false
            ultimaRipetizione = Date()
            unaRipetizione()
        }
    }

    /// L'angolo del ginocchio (3D di Vision; se manca, dall'immagine) e l'altezza in piedi per la misura dello scheletro giusto.
    private func misuraSpecchio(_ p: [VNHumanBodyPoseObservation.JointName: CGPoint]?, _ g3: Double?) {
        if let g3 {
            // 3D: media con il valore prima (se era 3D anche quello)
            ginocchio = ginocchioIn3D ? (ginocchio ?? g3) * 0.5 + g3 * 0.5 : g3
            ginocchioIn3D = true
            conAngolo = true
            ultimoAngolo3D = Date()
        } else if conAngolo {
            // il 3D c'era: un fotogramma senza non si mescola con l'angolo piatto (conterebbe due volte); dopo 1 s si azzera
            if Date().timeIntervalSince(ultimoAngolo3D) > 1 { ginocchio = nil; ginocchioIn3D = false }
        } else {
            let g = p.flatMap { Self.ginocchio2D($0) }
            ginocchio = g.map { nuovo in ginocchio.map { $0 * 0.5 + nuovo * 0.5 } ?? nuovo }
            ginocchioIn3D = false
        }
        guard let p, let collo = p[.neck] else { return }
        let caviglie = [p[.leftAnkle], p[.rightAnkle]].compactMap { $0 }
        guard !caviglie.isEmpty else { return }
        let h = Double(collo.y) - caviglie.map { Double($0.y) }.reduce(0, +) / Double(caviglie.count)
        guard h > 0.1 else { return }
        // si aggiorna solo in piedi (ginocchio 3D oltre 160°, o alto quasi quanto prima): accucciato non deve rimpicciolire
        let inPiedi = g3.map { $0 > 160 } ?? (h >= altezzaInPiedi * 0.92)
        if altezzaInPiedi == 0 { altezzaInPiedi = h }
        else if inPiedi || h > altezzaInPiedi { altezzaInPiedi = altezzaInPiedi * 0.9 + h * 0.1 }
    }

    /// Angolo anca-ginocchio-caviglia nell'immagine (x riscalata 9:16), media dei due lati. Di lato è giusto, di fronte no.
    private static func ginocchio2D(_ p: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> Double? {
        typealias J = VNHumanBodyPoseObservation.JointName
        var angoli: [Double] = []
        for (a, b, c) in [(J.leftHip, J.leftKnee, J.leftAnkle), (J.rightHip, J.rightKnee, J.rightAnkle)] {
            guard let pa = p[a], let pb = p[b], let pc = p[c] else { continue }
            let ux = Double(pa.x - pb.x) * 0.5625, uy = Double(pa.y - pb.y)
            let wx = Double(pc.x - pb.x) * 0.5625, wy = Double(pc.y - pb.y)
            let lu = hypot(ux, uy), lw = hypot(wx, wy)
            guard lu > 0.01, lw > 0.01 else { continue }
            angoli.append(acos(max(-1, min(1, (ux * wx + uy * wy) / (lu * lw)))) * 180 / .pi)
        }
        return angoli.isEmpty ? nil : angoli.reduce(0, +) / Double(angoli.count)
    }

    /// JARVIS parla ogni tanto: solo se c'è qualcosa da dire, mai sopra se stesso.
    private func commenta(_ adesso: Date) {
        guard !voceInCorso, adesso.timeIntervalSince(ultimoCommento) > 9 else { return }
        var frase = ""
        if inclinazioneSchiena > sogliaSchiena + 6 { frase = "Schiena fuori asse di \(Int(inclinazioneSchiena)) gradi: la raddrizzi." }
        else if inclinazioneSchiena > sogliaSchiena { frase = "Un filo di inclinazione nella schiena, \(Int(inclinazioneSchiena)) gradi." }
        else if simmetria < 80 { frase = "Un lato più basso dell'altro: cerchi la simmetria." }
        else if adesso.timeIntervalSince(ultimoCommento) > 25 { frase = ["Postura ottima, continui così.", "Schiena allineata, molto bene.", "Esecuzione pulita."].randomElement()! }
        guard !frase.isEmpty, frase != ultimoAvviso || adesso.timeIntervalSince(ultimoCommento) > 30 else { return }
        ultimoCommento = adesso
        ultimoAvviso = frase
        commento = frase
        Task { await parla(frase) }
    }

    private func parla(_ testo: String) async {
        voceInCorso = true
        defer { voceInCorso = false }
        let s = AVAudioSession.sharedInstance()
        if ascoltoComandi {
            // il microfono dei comandi è acceso: stessa impostazione sua, così parlando non lo spegne
            if s.category != .playAndRecord { try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers]) }
        } else {
            try? s.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        }
        try? s.setActive(true)
        if Impostazioni.voceCloud, let url = URL(string: Impostazioni.indirizzo) {
            let (dati, _) = await VoceCloud.scarica(testo, id: Impostazioni.idVoceCloud, url: url, token: Portachiavi.leggi())
            if let dati, let p = try? AVAudioPlayer(data: dati) {
                lettore = p
                p.play()
                while p.isPlaying { try? await Task.sleep(for: .milliseconds(100)) }
                lettore = nil
                return
            }
        }
        let u = AVSpeechUtterance(string: testo)
        u.voice = Jarvis.voceScelta()
        sintesi.speak(u)
        while sintesi.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
    }
}

/// La fotocamera dell'allenatore: lavora su una coda sua, riceve i fotogrammi e chiede a Vision lo scheletro (uno su tre basta).
nonisolated final class CameraPosa: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sessione = AVCaptureSession()
    let coda = DispatchQueue(label: "it.discosizer.jarvis.allenatore")
    var esito: (@Sendable ([VNHumanBodyPoseObservation.JointName: CGPoint]?, Double?) -> Void)?   // scheletro 2D e ginocchio 3D
    private let uscita = AVCaptureVideoDataOutput()
    private var ingresso: AVCaptureDeviceInput?
    private var contatore = 0
    private let richiesta = VNDetectHumanBodyPoseRequest()
    // build 22: lo scheletro 3D (iOS 17) per l'angolo vero del ginocchio, solo nello Specchio
    private let richiesta3D = VNDetectHumanBodyPose3DRequest()
    private var vuole3D = false
    private var turno3D = 0
    private var lento3D = false
    private var ultimo3D: (gradi: Double, quando: Date)?

    func usa3D(_ si: Bool) { coda.async { self.vuole3D = si; if !si { self.ultimo3D = nil } } }

    func configura(frontale: Bool, pronto: @escaping @Sendable (Bool) -> Void) {
        coda.async {
            let s = self.sessione
            s.beginConfiguration()
            s.sessionPreset = .high
            if let vecchio = self.ingresso { s.removeInput(vecchio); self.ingresso = nil }
            if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: frontale ? .front : .back),
               let i = try? AVCaptureDeviceInput(device: cam), s.canAddInput(i) {
                s.addInput(i); self.ingresso = i
            }
            if !s.outputs.contains(self.uscita) {
                self.uscita.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.uscita.alwaysDiscardsLateVideoFrames = true
                self.uscita.setSampleBufferDelegate(self, queue: self.coda)
                if s.canAddOutput(self.uscita) { s.addOutput(self.uscita) }
            }
            if let c = self.uscita.connection(with: .video) {
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }   // ripresa verticale
                c.isVideoMirrored = false
            }
            s.commitConfiguration()
            if !s.isRunning { s.startRunning() }
            pronto(self.ingresso != nil && s.isRunning)
        }
    }

    func ferma() {
        coda.async { if self.sessione.isRunning { self.sessione.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        contatore += 1
        guard contatore % 3 == 0, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let gestore = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up)
        try? gestore.perform([richiesta])
        guard let oss = richiesta.results?.first, let punti = try? oss.recognizedPoints(.all) else { esito?(nil, nil); return }
        var out: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (nome, p) in punti where p.confidence > 0.3 { out[nome] = CGPoint(x: p.location.x, y: p.location.y) }
        let visto = out.count >= 5
        esito?(visto ? out : nil, visto ? ginocchio3D(gestore) : nil)
    }

    /// L'angolo del ginocchio dallo scheletro 3D: vale anche di fronte, dove nell'immagine piatta il ginocchio sembra sempre dritto.
    /// Se il 3D è lento (oltre 80 ms) si calcola un fotogramma sì e uno no, tenendo buono l'ultimo valore per 0,4 s.
    private func ginocchio3D(_ gestore: VNImageRequestHandler) -> Double? {
        guard vuole3D else { return nil }
        turno3D += 1
        if lento3D && turno3D % 2 == 1 {
            guard let u = ultimo3D, Date().timeIntervalSince(u.quando) < 0.4 else { return nil }
            return u.gradi
        }
        let inizio = Date()
        var gradi: Double?
        if (try? gestore.perform([richiesta3D])) != nil, let o = richiesta3D.results?.first { gradi = Self.angoloGinocchio(o) }
        lento3D = Date().timeIntervalSince(inizio) > 0.08
        if let gradi { ultimo3D = (gradi, Date()) }
        return gradi
    }

    /// Anca-ginocchio-caviglia in metri, media dei due lati.
    private static func angoloGinocchio(_ o: VNHumanBodyPose3DObservation) -> Double? {
        typealias J = VNHumanBodyPose3DObservation.JointName
        func punto(_ j: J) -> simd_float3? {
            guard let r = try? o.recognizedPoint(j) else { return nil }
            let c = r.position.columns.3
            return simd_float3(c.x, c.y, c.z)
        }
        var angoli: [Double] = []
        for (a, b, c) in [(J.leftHip, J.leftKnee, J.leftAnkle), (J.rightHip, J.rightKnee, J.rightAnkle)] {
            guard let pa = punto(a), let pb = punto(b), let pc = punto(c) else { continue }
            let u = pa - pb, w = pc - pb
            let lu = simd_length(u), lw = simd_length(w)
            guard lu > 0.01, lw > 0.01 else { continue }
            angoli.append(Double(acos(max(-1, min(1, simd_dot(u, w) / (lu * lw))))) * 180 / .pi)
        }
        return angoli.isEmpty ? nil : angoli.reduce(0, +) / Double(angoli.count)
    }
}
#endif
