#if os(iOS)
import SwiftUI
import Combine
import AVFoundation
import Vision
import UIKit

/// L'allenatore di JARVIS: inquadra chi si allena, l'iPhone riconosce lo scheletro del corpo (Vision, tutto in locale)
/// e lo disegna in stile HUD sopra la ripresa. JARVIS commenta la postura a voce (schiena, spalle, braccia),
/// conta le ripetizioni e a fine serie fa il riassunto. Pensato per il Pilates, va bene per squat, piegamenti, addominali.
struct Allenatore: View {
    let chiudi: () -> Void
    @StateObject private var motore = MotoreAllenatore()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaAllenatore(sessione: motore.sessione).ignoresSafeArea()
            ScheletroHUD(posa: motore.posa, allarme: motore.posturaFuori, specchio: motore.frontale).ignoresSafeArea().allowsHitTesting(false)

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

                // telemetria
                HStack(spacing: 10) {
                    dato("RIPETIZIONI", "\(motore.ripetizioni)", caldo: false)
                    dato("SCHIENA", motore.posa == nil ? "—" : "\(Int(motore.inclinazioneSchiena))°", caldo: motore.inclinazioneSchiena > 12)
                    dato("SIMMETRIA", motore.posa == nil ? "—" : "\(Int(motore.simmetria))%", caldo: motore.simmetria < 85)
                }
                .padding(.horizontal, 20)

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

                Picker("Conteggio", selection: $motore.giunto) {
                    Text("Busto").tag(MotoreAllenatore.Giunto.busto)
                    Text("Mani").tag(MotoreAllenatore.Giunto.mani)
                    Text("Ginocchia").tag(MotoreAllenatore.Giunto.ginocchia)
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
        .task { await motore.avvia() }
        .onDisappear { motore.ferma() }
        .aperturaHUD("Allenatore")
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
    @Published var giunto: Giunto = .busto { didSet { azzeraConteggio() } }

    private let camera = CameraPosa()
    var sessione: AVCaptureSession { camera.sessione }

    // conteggio: posizione «su» e «giù» del giunto scelto, con isteresi
    private var altezza: Double = 0            // 0 in alto, 1 in basso (coordinate schermo)
    private var minimo: Double = 1, massimo: Double = 0
    private var giu = false
    private var ultimoCampione = Date.distantPast
    private var serieSchiena: [Double] = [], serieSimmetria: [Double] = []
    private var ultimoCommento = Date.distantPast
    private var ultimoAvviso = ""
    private var voceInCorso = false
    private var lettore: AVAudioPlayer?
    private let sintesi = AVSpeechSynthesizer()
    private var inizioSerie = Date()

    func avvia() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { commento = "Serve il permesso fotocamera, Sir."; return }
        camera.esito = { [weak self] punti in Task { @MainActor [weak self] in self?.ricevi(punti) } }
        configura(frontale: false)
        inizioSerie = Date()
        commento = "Inquadri tutta la persona, Sir."
        Suoni.aperturaCamera()
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

    private func azzeraConteggio() { ripetizioni = 0; minimo = 1; massimo = 0; giu = false }

    func fineSerie() {
        let n = ripetizioni
        let schiena = serieSchiena.isEmpty ? 0 : serieSchiena.reduce(0, +) / Double(serieSchiena.count)
        let simm = serieSimmetria.isEmpty ? 100 : serieSimmetria.reduce(0, +) / Double(serieSimmetria.count)
        let durata = Int(Date().timeIntervalSince(inizioSerie))
        var frase = n == 0 ? "Serie chiusa senza ripetizioni contate, Sir." : "Serie chiusa: \(n) ripetizion\(n == 1 ? "e" : "i") in \(durata / 60) minuti e \(durata % 60) secondi."
        if !serieSchiena.isEmpty {
            frase += schiena < 8 ? " Schiena allineata per tutta la serie, davvero bene." : schiena < 15 ? " Schiena un po' inclinata, in media \(Int(schiena)) gradi: si può fare meglio." : " Attenzione alla schiena: in media \(Int(schiena)) gradi fuori asse."
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

    private func ricevi(_ punti: [VNHumanBodyPoseObservation.JointName: CGPoint]?) {
        posa = punti
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
        posturaFuori = inclinazioneSchiena > 12 || simmetria < 85
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
            ripetizioni += 1
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Suoni.tocco()
        }
    }

    /// JARVIS parla ogni tanto: solo se c'è qualcosa da dire, mai sopra se stesso.
    private func commenta(_ adesso: Date) {
        guard !voceInCorso, adesso.timeIntervalSince(ultimoCommento) > 9 else { return }
        var frase = ""
        if inclinazioneSchiena > 18 { frase = "Schiena fuori asse di \(Int(inclinazioneSchiena)) gradi: la raddrizzi." }
        else if inclinazioneSchiena > 12 { frase = "Un filo di inclinazione nella schiena, \(Int(inclinazioneSchiena)) gradi." }
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
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
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
    var esito: (@Sendable ([VNHumanBodyPoseObservation.JointName: CGPoint]?) -> Void)?
    private let uscita = AVCaptureVideoDataOutput()
    private var ingresso: AVCaptureDeviceInput?
    private var contatore = 0
    private let richiesta = VNDetectHumanBodyPoseRequest()

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
        guard let oss = richiesta.results?.first, let punti = try? oss.recognizedPoints(.all) else { esito?(nil); return }
        var out: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (nome, p) in punti where p.confidence > 0.3 { out[nome] = CGPoint(x: p.location.x, y: p.location.y) }
        esito?(out.count >= 5 ? out : nil)
    }
}
#endif
