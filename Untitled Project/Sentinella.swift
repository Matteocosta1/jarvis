#if os(iOS)
import SwiftUI
import AVFoundation
import Vision
import CoreImage
import ImageIO
import UIKit
import WatchConnectivity
import Combine

/// SENTINELLA (reparto INTELLIGENCE): l'iPhone, appoggiato e puntato sulla stanza, fa da telecamera di sicurezza.
/// - riconosce persone e animali (Vision, tutto sul telefono, niente cloud) e li insegue con un mirino;
/// - se la stanza è buia passa da solo alla visione notturna;
/// - quando entra qualcuno: «Perimetro violato, Sir» sull'orologio, con vibrazione e fotogramma;
/// - dall'orologio: «Guarda ora» (vista quasi in diretta) e «Disattiva».
/// La fotocamera funziona solo con l'app aperta: la sentinella si accende dall'iPhone.
@MainActor
final class Sentinella: ObservableObject {
    static let condiviso = Sentinella()

    nonisolated struct Bersaglio: Equatable, Sendable {
        let rect: CGRect        // normalizzato, origine in alto a sinistra, nell'immagine raddrizzata
        let tipo: String        // «PERSONA», «ANIMALE · GATTO»…
    }
    struct Evento: Identifiable {
        let id = UUID()
        let quando: Date
        let cosa: String
        let foto: Data
    }

    @Published private(set) var attiva = false
    /// 5 nov (il signore: «l'animazione di Sentinella scatta»): l'immagine arrivava a 12 fotogrammi al secondo e passava da
    /// SwiftUI, che ridisegnava tutta la schermata a ogni fotogramma. Ora arriva a 30 al secondo e la disegna un CALayer
    /// (SchermoSentinella), fuori da SwiftUI: qui restano solo «c'è l'immagine» e le sue proporzioni.
    @Published private(set) var inVista = false
    @Published private(set) var proporzione = CGSize(width: 3, height: 4)
    /// Lo schermo che mostra l'immagine (quello della schermata aperta).
    weak var schermo: SchermoSentinella.Vista?
    @Published private(set) var bersagli: [Bersaglio] = []
    @Published private(set) var notte = false
    @Published private(set) var violato = false           // allarme in corso: tutto rosso per qualche secondo
    @Published private(set) var eventi: [Evento] = []
    @Published var problema: String?

    private let motore = MotoreSentinella()
    /// Sul Mac: finché la Sentinella è accesa il Mac non va in stop e non spegne lo schermo (la webcam resta viva).
    private var restaSveglio: NSObjectProtocol?
    private var ultimaFoto: Data?                          // l'ultimo fotogramma leggero, per «Guarda ora»
    private var presenzaPrima = false
    private var ultimoAllarme = Date.distantPast
    private var luminositaPrima: CGFloat = 0.5

    /// Accende la sentinella. Falso se manca il permesso della fotocamera.
    func avvia() async -> Bool {
        guard !attiva else { return true }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            problema = "Mi serve la fotocamera, Sir: Impostazioni › Jarvis › Fotocamera."
            return false
        }
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            motore.avvia(
                quadro: { immagine, notte in
                    let img = immagine         // CGImage è Sendable: passa tranquillo al thread principale
                    Task { @MainActor in Sentinella.condiviso.nuovoQuadro(img, notte: notte) }
                },
                analisi: { bersagli, foto in
                    Task { @MainActor in Sentinella.condiviso.nuovaAnalisi(bersagli, foto: foto) }
                },
                pronto: { ok in c.resume(returning: ok) })
        }
        guard ok else {
            problema = "La fotocamera non risponde, Sir. Chiuda Occhi o le altre app che la usano e riprovi."
            return false
        }
        attiva = true
        presenzaPrima = false
        UIApplication.shared.isIdleTimerDisabled = true      // lo schermo non si spegne: la fotocamera resta viva
        if ProcessInfo.processInfo.isiOSAppOnMac, restaSveglio == nil {   // sul Mac quel blocco non vale: si chiede al Mac di restare sveglio
            restaSveglio = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled, .userInitiated],
                                                                 reason: "Sentinella di JARVIS accesa: la webcam sorveglia la stanza")
        }
        if !ProcessInfo.processInfo.isiOSAppOnMac {          // sul Mac la luminosità non si tocca
            luminositaPrima = UIScreen.main.brightness
            UIScreen.main.brightness = 0.25                  // consuma meno e non illumina la stanza
        }
        PonteSentinella.inviaStato(attiva: true)
        return true
    }

    func ferma() {
        guard attiva else { return }
        motore.ferma()
        attiva = false
        bersagli = []
        inVista = false
        schermo?.layer.contents = nil
        violato = false
        UIApplication.shared.isIdleTimerDisabled = false
        if let a = restaSveglio { ProcessInfo.processInfo.endActivity(a); restaSveglio = nil }   // il Mac torna a fare come sempre
        if !ProcessInfo.processInfo.isiOSAppOnMac { UIScreen.main.brightness = luminositaPrima }
        PonteSentinella.inviaStato(attiva: false)
    }

    private func nuovoQuadro(_ immagine: CGImage, notte: Bool) {
        guard attiva else { return }
        schermo?.layer.contents = immagine
        let p = CGSize(width: immagine.width, height: immagine.height)
        if proporzione != p { proporzione = p }
        if !inVista { inVista = true }
        if self.notte != notte { withAnimation(.easeInOut(duration: 0.6)) { self.notte = notte } }
    }

    private func nuovaAnalisi(_ nuovi: [Bersaglio], foto: Data?) {
        guard attiva else { return }
        withAnimation(.easeOut(duration: 0.35)) { bersagli = nuovi }
        if let foto { ultimaFoto = foto }
        let presenza = !nuovi.isEmpty
        // scatta quando qualcuno ENTRA (prima la stanza era vuota), non a ogni fotogramma; poi 20 secondi di quiete
        if presenza && !presenzaPrima && Date().timeIntervalSince(ultimoAllarme) > 20, let foto {
            allarme(cosa: Sentinella.descrivi(nuovi), foto: foto)
        }
        presenzaPrima = presenza
    }

    private func allarme(cosa: String, foto: Data) {
        ultimoAllarme = Date()
        eventi.insert(Evento(quando: Date(), cosa: cosa, foto: foto), at: 0)
        if eventi.count > 40 { eventi.removeLast(eventi.count - 40) }
        withAnimation(.easeOut(duration: 0.2)) { violato = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.6)) { self.violato = false }
        }
        PonteSentinella.inviaAllarme(cosa: cosa, foto: foto)
        if ProcessInfo.processInfo.isiOSAppOnMac { Task { await Sentinella.avvisaIPhone(cosa: cosa) } }
    }

    /// Sul Mac non c'è l'orologio accanto: l'allarme arriva come notifica sull'iPhone (e da lì sull'Apple Watch),
    /// tramite il briefing, che sa già mandare avvisi a tutti i dispositivi di JARVIS.
    static func avvisaIPhone(cosa: String) async {
        let base = Impostazioni.indirizzo
        let indirizzo = base.hasSuffix("/jarvis") ? base + "-briefing" : base.replacingOccurrences(of: "/jarvis", with: "/jarvis-briefing")
        guard let url = URL(string: indirizzo) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        let ora = Date().formatted(date: .omitted, time: .shortened)
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["titolo": "🚨 SENTINELLA · Mac",
                                                                    "testo": "Alle \(ora): \(cosa) davanti al Mac, Sir."])
        _ = try? await URLSession.shared.data(for: req)
    }

    /// «una persona», «2 persone e un gatto»…
    static func descrivi(_ b: [Bersaglio]) -> String {
        let persone = b.filter { $0.tipo == "PERSONA" }.count
        let animali = b.filter { $0.tipo != "PERSONA" }.map { $0.tipo.replacingOccurrences(of: "ANIMALE · ", with: "").lowercased() }
        var parti: [String] = []
        if persone == 1 { parti.append("una persona") } else if persone > 1 { parti.append("\(persone) persone") }
        if let a = animali.first { parti.append(animali.count == 1 ? (a == "animale" ? "un animale" : "un \(a)") : "\(animali.count) animali") }
        return parti.isEmpty ? "movimento" : parti.joined(separator: " e ")
    }

    /// Le richieste che arrivano dall'orologio.
    func rispondi(_ comando: String) -> [String: Any] {
        switch comando {
        case "ferma":
            ferma()
            return ["attiva": false]
        case "guarda":
            var r: [String: Any] = ["attiva": attiva, "notte": notte, "bersagli": bersagli.count]
            if attiva, let f = ultimaFoto { r["foto"] = f }
            return r
        default:
            return ["attiva": attiva]
        }
    }
}

// MARK: - Il ponte verso l'orologio (stessa sessione WatchConnectivity del resto dell'app)

nonisolated enum PonteSentinella {
    /// Allarme: messaggio immediato se l'orologio è raggiungibile, altrimenti consegna in coda (arriva appena l'app si sveglia).
    static func inviaAllarme(cosa: String, foto: Data) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        let messaggio: [String: Any] = ["sentinella": "allarme", "cosa": cosa, "foto": foto, "quando": Date().timeIntervalSince1970]
        if s.isReachable {
            s.sendMessage(messaggio, replyHandler: nil) { _ in s.transferUserInfo(messaggio) }
        } else {
            s.transferUserInfo(messaggio)
        }
    }

    static func inviaStato(attiva: Bool) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { return }
        s.sendMessage(["sentinella": "stato", "attiva": attiva], replyHandler: nil, errorHandler: nil)
    }

    /// Chiamato dal ponte del telefono quando l'orologio chiede qualcosa alla sentinella.
    static func ricevi(_ comando: String, rispondi: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let risposta = rispondi
        Task { @MainActor in risposta(Sentinella.condiviso.rispondi(comando)) }
    }
}

// MARK: - Motore: fotocamera, visione notturna e riconoscimento (su una coda sua, fuori dal thread principale)

nonisolated final class MotoreSentinella: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessione = AVCaptureSession()
    private let uscita = AVCaptureVideoDataOutput()
    private let coda = DispatchQueue(label: "it.discosizer.jarvis.sentinella")
    /// 5 nov: il riconoscimento su una coda sua, così mentre Vision lavora (30–60 ms) le immagini continuano ad arrivare a 30 al
    /// secondo (prima, sulla stessa coda della fotocamera, faceva saltare fotogrammi tre volte al secondo).
    private let codaAnalisi = DispatchQueue(label: "it.discosizer.jarvis.sentinella.analisi", qos: .userInitiated)
    private var analizzando = false                    // solo sulla coda della fotocamera
    private let contesto = CIContext(options: [.cacheIntermediates: false])
    private var configurata = false
    private var notte = false
    private var ultimoQuadro = Date.distantPast
    private var ultimaAnalisi = Date.distantPast
    private var suQuadro: (@Sendable (CGImage, Bool) -> Void)?
    private var suAnalisi: (@Sendable ([Sentinella.Bersaglio], Data?) -> Void)?

    func avvia(quadro: @escaping @Sendable (CGImage, Bool) -> Void,
               analisi: @escaping @Sendable ([Sentinella.Bersaglio], Data?) -> Void,
               pronto: @escaping @Sendable (Bool) -> Void) {
        coda.async {
            self.suQuadro = quadro
            self.suAnalisi = analisi
            if !self.configurata {
                self.sessione.beginConfiguration()
                let mac = ProcessInfo.processInfo.isiOSAppOnMac
                // sul Mac lo schermo è grande: immagine più definita (se la webcam la regge)
                self.sessione.sessionPreset = mac && self.sessione.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .vga640x480
                guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? (mac ? AVCaptureDevice.default(for: .video) : nil),          // sul Mac: la webcam
                      let ingresso = try? AVCaptureDeviceInput(device: cam),
                      self.sessione.canAddInput(ingresso), self.sessione.canAddOutput(self.uscita) else {
                    self.sessione.commitConfiguration()
                    pronto(false)
                    return
                }
                self.sessione.addInput(ingresso)
                self.uscita.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.uscita.alwaysDiscardsLateVideoFrames = true
                self.uscita.setSampleBufferDelegate(self, queue: self.coda)
                self.sessione.addOutput(self.uscita)
                self.sessione.commitConfiguration()
                if (try? cam.lockForConfiguration()) != nil {
                    if cam.isFocusModeSupported(.continuousAutoFocus) { cam.focusMode = .continuousAutoFocus }
                    if cam.isLowLightBoostSupported { cam.automaticallyEnablesLowLightBoostWhenAvailable = true }
                    cam.unlockForConfiguration()
                }
                self.configurata = true
            }
            if !self.sessione.isRunning { self.sessione.startRunning() }
            pronto(self.sessione.isRunning)
        }
    }

    func ferma() {
        coda.async {
            if self.sessione.isRunning { self.sessione.stopRunning() }
            self.suQuadro = nil
            self.suAnalisi = nil
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixel = CMSampleBufferGetImageBuffer(buffer) else { return }
        let adesso = Date()

        // luce della scena: il valore «Brightness» che la fotocamera scrive in ogni fotogramma (sotto ~-1,5 è buio)
        if let exif = CMGetAttachment(buffer, key: kCGImagePropertyExifDictionary, attachmentModeOut: nil) as? [String: Any],
           let luce = exif[kCGImagePropertyExifBrightnessValue as String] as? Double {
            if !notte && luce < -1.5 { notte = true }          // isteresi: non sfarfalla al confine
            else if notte && luce > -0.5 { notte = false }
        }

        // telefono in verticale: si raddrizza; sul Mac la webcam è già orizzontale e si guarda a specchio, come FaceTime
        let mac = ProcessInfo.processInfo.isiOSAppOnMac
        let raddrizzata = CIImage(cvPixelBuffer: pixel).oriented(mac ? .upMirrored : .right)

        // 1) l'immagine da mostrare: tutti i fotogrammi della fotocamera, 30 al secondo (5 nov: prima 12, e «scattava»)
        if adesso.timeIntervalSince(ultimoQuadro) > 0.025, let f = suQuadro {
            ultimoQuadro = adesso
            let vista = notte ? MotoreSentinella.visioneNotturna(raddrizzata) : raddrizzata
            if let cg = contesto.createCGImage(vista, from: vista.extent) { f(cg, notte) }
        }

        // 2) riconoscimento di persone e animali, circa 3 volte al secondo, sulla sua coda (uno alla volta)
        guard adesso.timeIntervalSince(ultimaAnalisi) > 0.33, !analizzando, let a = suAnalisi else { return }
        ultimaAnalisi = adesso
        analizzando = true
        let f = Fotogramma(pixel: pixel, immagine: raddrizzata, notte: notte, mac: mac)
        codaAnalisi.async {
            self.analizza(f, consegna: a)
            self.coda.async { self.analizzando = false }
        }
    }

    /// Un fotogramma da analizzare (il buffer della fotocamera resta in mano solo per l'analisi, uno alla volta).
    private nonisolated struct Fotogramma: @unchecked Sendable {
        let pixel: CVPixelBuffer
        let immagine: CIImage
        let notte: Bool
        let mac: Bool
    }

    private func analizza(_ f: Fotogramma, consegna a: @Sendable ([Sentinella.Bersaglio], Data?) -> Void) {
        let persone = VNDetectHumanRectanglesRequest()
        persone.upperBodyOnly = false
        let animali = VNRecognizeAnimalsRequest()
        let gestore = VNImageRequestHandler(cvPixelBuffer: f.pixel, orientation: f.mac ? .upMirrored : .right)
        try? gestore.perform([persone, animali])
        var trovati: [Sentinella.Bersaglio] = []
        for p in persone.results ?? [] where p.confidence > 0.5 {
            trovati.append(.init(rect: MotoreSentinella.inAlto(p.boundingBox), tipo: "PERSONA"))
        }
        for o in animali.results ?? [] where o.confidence > 0.5 {
            let nome = o.labels.first.map { MotoreSentinella.nomeAnimale($0.identifier) } ?? "ANIMALE"
            trovati.append(.init(rect: MotoreSentinella.inAlto(o.boundingBox), tipo: "ANIMALE · \(nome)"))
        }
        // fotogramma leggero (per l'allarme e per «Guarda ora» sull'orologio): lato lungo 480 px, JPEG
        let vista = f.notte ? MotoreSentinella.visioneNotturna(f.immagine) : f.immagine
        let scala = 480 / max(vista.extent.width, vista.extent.height)
        let piccola = vista.transformed(by: CGAffineTransform(scaleX: scala, y: scala))
        let jpeg = contesto.jpegRepresentation(of: piccola, colorSpace: CGColorSpaceCreateDeviceRGB(),
                                               options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.45])
        a(trovati, jpeg)
    }

    /// Vision dà i riquadri con l'origine in basso a sinistra: li porto in alto a sinistra, come lo schermo.
    static func inAlto(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }

    static func nomeAnimale(_ id: String) -> String {
        switch id.lowercased() {
        case "cat": return "GATTO"
        case "dog": return "CANE"
        default: return "ANIMALE"
        }
    }

    /// Visione notturna: bianco e nero, luce e contrasto alzati, poi verde fosforo come un visore.
    static func visioneNotturna(_ i: CIImage) -> CIImage {
        let grigia = i.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.35, kCIInputBrightnessKey: 0.08])
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.6])
        return grigia.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: CIColor(red: 0.25, green: 1.0, blue: 0.35), kCIInputIntensityKey: 1.0])
    }
}

// MARK: - La schermata

struct VistaSentinella: View {
    let chiudi: () -> Void
    /// Comandi a voce dentro la Sentinella: «Jarvis, torna», «Jarvis, apri il Wiretap»…
    var comando: (ComandoVocale) -> Void = { _ in }
    @ObservedObject private var s = Sentinella.condiviso
    @State private var orecchio = OrecchioComandi()
    @State private var oscurato = false
    @State private var registro = false
    @Environment(\.sezioneDietro) private var dietro    // 4 nov: dietro (MARK XI) il lampeggio si ferma

    private var colore: Color { s.violato ? .red : (s.notte ? Color(red: 0.35, green: 1, blue: 0.45) : .ciano) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if s.inVista {
                SchermoSentinella()
                    .aspectRatio(s.proporzione, contentMode: .fit)
                    .overlay { mirini }
                    .overlay { RadarSentinella(colore: colore).opacity(0.5).allowsHitTesting(false) }
            } else {
                ProgressView().tint(Color.ciano)
            }

            // bordo rosso che lampeggia durante l'allarme
            // 27 ott: il lampeggio lo dà l'orologio (come gli anelli), non un'animazione infinita: il bordo non può vagare
            TimelineView(.animation(minimumInterval: nil, paused: !s.violato || dietro)) { t in
                RoundedRectangle(cornerRadius: 36)
                    .stroke(Color.red, lineWidth: 6)
                    .opacity(s.violato ? (1 - cos(t.date.timeIntervalSinceReferenceDate * .pi / 0.35)) / 2 : 0)
            }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                // 7 nov sera (il signore: «metti icona, titolo e sottotitolo nel frame dove c'è Chiudi»): la testata nella riga
                // della X, come tutte le sezioni (BarraSezione); l'ora sotto il sottotitolo, come nel mockup
                BarraSezione(testata: DatiTestata(titolo: "Sentinella", sottotitolo: s.notte ? "visione notturna" : "perimetro sotto controllo",
                                                  icona: "dot.radiowaves.left.and.right", tinta: colore, titoloColorato: true,
                                                  riga: AnyView(TimelineView(.periodic(from: .now, by: 1)) { t in
                                                      Text(t.date.formatted(date: .omitted, time: .standard))
                                                          .font(.system(size: 10, design: .monospaced)).opacity(0.7)
                                                  }
                                                  .foregroundStyle(colore))),     // 27 ott: niente bagliore sulle scritte della testata
                             tinta: .ciano, conX: true, etichettaX: "Disattiva la sentinella", chiudi: { s.ferma(); chiudi() })
                // 8 nov (video del signore: «la scritta non è allineata dopo il caricamento»): BarraSezione ha già i suoi 16 punti
                // dai bordi: si toglie tutto il margine della pagina (20), non solo 4 (prima testata e X stavano a 32 punti dai bordi)
                .padding(.horizontal, -20)
                .padding(.top, -12)
                Spacer()
                // 7 nov sera (il signore: «la luna e il registro sopra PERIMETRO SICURO, così sono simili ad Occhi»): tondi col nome
                // sotto, come ETICHETTE e OLOGRAMMA di Occhi
                HStack(alignment: .top, spacing: 18) {
                    tastoGiu("list.bullet.rectangle", "REGISTRO") { registro = true }
                    tastoGiu("moon.fill", "BUIO") { oscurato = true }
                }
                .padding(.bottom, 6)
                Text(s.violato ? "PERIMETRO VIOLATO" : (s.bersagli.isEmpty ? "PERIMETRO SICURO" : "SOGGETTI IN VISTA · \(s.bersagli.count)"))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(3)
                    .foregroundStyle(s.violato ? .white : colore)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(s.violato ? Color.red.opacity(0.8) : Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.25), value: s.violato)
                Text(ProcessInfo.processInfo.isiOSAppOnMac
                     ? "Lasci il Mac con la webcam sulla stanza: finché la Sentinella è accesa non va in stop. Gli allarmi arrivano come notifica sull'iPhone e sull'orologio."
                     : "Lasci il telefono fermo, puntato sulla stanza. Gli allarmi arrivano all'orologio. «Jarvis, torna» per uscire.")
                    .font(.footnote).foregroundStyle(Color.tenue).multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            // schermo nero: la sentinella continua a guardare, un tocco per tornare
            if oscurato {
                Color.black.ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        Text("SENTINELLA ATTIVA · tocchi per vedere")
                            .font(.system(size: 10, design: .monospaced)).tracking(2)
                            .foregroundStyle(Color.ciano.opacity(0.35)).padding(.bottom, 40)
                    }
                    .onTapGesture { oscurato = false }
            }
        }
        .statusBarHidden()
        .task {
            let aperta = Date()
            if !(await s.avvia()) {
                try? await Task.sleep(for: .seconds(3))
                chiudi()
                return
            }
            orecchio.dentro = .sentinella
            orecchio.comando = { c in
                switch c {
                case .sentinella(.registro): oscurato = false; registro = true; return   // «Jarvis, chi è passato?»
                case .sentinella(.schermoNero): registro = false; oscurato = true; return  // «Jarvis, schermo nero»
                default: break
                }
                if c == .torna { s.ferma() }
                comando(c)
            }
            // l'ascolto dei comandi cambia la sessione audio: si accende dopo il clic di fine caricamento (0,45 s + 0,7 s),
            // altrimenti il suono si perde
            let resta = Apertura.orecchio - Date().timeIntervalSince(aperta)
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            guard !Task.isCancelled else { return }
            orecchio.avvia()
        }
        .overlay(alignment: .center) {
            if let p = s.problema {
                Text(p).font(.footnote).foregroundStyle(.orange).padding().background(Color.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12)).padding()
            }
        }
        .onDisappear { orecchio.ferma(); s.ferma() }
        .pausaDietro(ferma: { orecchio.ferma(); s.ferma(); registro = false },            // MARK XI: dietro in pausa (4 nov: e il Registro si chiude)
                     riprendi: { Task { if await s.avvia() { Suoni.aperturaCamera(); orecchio.avvia() } } })
        .aperturaHUD("Sentinella", icona: "dot.radiowaves.left.and.right", conX: true, fotocamera: true)
        // 4 nov: il Registro come nel mockup (il foglio che sale dal basso, la ✕ nel cerchio), non più la lista di iOS
        .fullScreenCover(isPresented: $registro) { RegistroSentinella() }
    }

    /// Il mirino che insegue: un riquadro ad angoli su ogni persona o animale, con la sua etichetta.
    private var mirini: some View {
        GeometryReader { g in
            ForEach(Array(s.bersagli.enumerated()), id: \.offset) { _, b in
                let r = CGRect(x: b.rect.minX * g.size.width, y: b.rect.minY * g.size.height,
                               width: b.rect.width * g.size.width, height: b.rect.height * g.size.height)
                ZStack(alignment: .topLeading) {
                    AngoliMirino()
                        .stroke(s.violato ? Color.red : colore, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .shadow(color: (s.violato ? Color.red : colore).opacity(0.8), radius: 5)
                    Text("SOGGETTO: \(b.tipo)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(s.violato ? Color.red : colore)
                        .offset(y: -16)
                }
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
            }
        }
        .allowsHitTesting(false)
    }

    /// I tasti in basso, come quelli di Occhi (TastoOcchi): il tondo da 40 e il nome sotto.
    private func tastoGiu(_ icona: String, _ titolo: String, _ azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            VStack(spacing: 4) {
                Image(systemName: icona).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.ciano.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.ciano.opacity(0.55), lineWidth: 1))
                Text(titolo).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.5)
                    .foregroundStyle(Color.ciano.opacity(0.7))
            }
            .frame(width: 50)
        }
        .buttonStyle(StileStark())
        .accessibilityLabel(titolo == "BUIO" ? "Schermo nero" : "Registro")
    }

}

/// 5 nov · l'immagine della Sentinella: un CALayer a cui la Sentinella dà ogni fotogramma (30 al secondo), senza passare da
/// SwiftUI. Stessa misura e stesso posto dell'immagine di prima (adattata, senza tagli).
struct SchermoSentinella: UIViewRepresentable {
    final class Vista: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            layer.contentsGravity = .resizeAspect
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }
    }
    func makeUIView(context: Context) -> Vista {
        let v = Vista()
        Sentinella.condiviso.schermo = v
        return v
    }
    func updateUIView(_ v: Vista, context: Context) {
        if Sentinella.condiviso.schermo !== v { Sentinella.condiviso.schermo = v }
    }
}

/// Quattro angoli, come il mirino di JARVIS.
struct AngoliMirino: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = min(r.width, r.height) * 0.22
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Un fascio di radar che gira piano sopra l'immagine.
struct RadarSentinella: View {
    let colore: Color
    @Environment(\.sezioneDietro) private var dietro    // 4 nov: dietro (MARK XI) il radar si ferma
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: dietro)) { ctx in
            let a = ctx.date.timeIntervalSinceReferenceDate * 1.2
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = max(size.width, size.height)
                var fetta = Path()
                fetta.move(to: c)
                fetta.addArc(center: c, radius: r, startAngle: .radians(a), endAngle: .radians(a + 0.35), clockwise: false)
                fetta.closeSubpath()
                gc.fill(fetta, with: .color(colore.opacity(0.10)))
            }
        }
    }
}

/// Il registro: chi è passato e quando, con il fotogramma. 4 nov: come nel mockup (il foglio che sale dal basso, come il Dossier
/// di SATELLITE): REGISTRO · CHI È PASSATO · OGGI, la ✕ nel cerchio a destra (la Sentinella ha la fotocamera), le righe
/// «SOGGETTO: …» con l'ora, dal più recente; vuoto: NESSUN PASSAGGIO.
struct RegistroSentinella: View {
    @ObservedObject private var s = Sentinella.condiviso
    @Environment(\.chiudiOVia) private var chiudi

    var body: some View {
        ZStack {
            SfondoSezione()   // 7 nov: lo sfondo di tutte le sezioni
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("REGISTRO").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                        Text("CHI È PASSATO · OGGI").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.75)
                    }
                    .foregroundStyle(Color.ciano)
                    Spacer(minLength: 4)
                    Button { Suoni.tocco(); chiudi() } label: { TondoX() }
                    .buttonStyle(StileStark())
                    .accessibilityLabel("Chiudi")
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if s.eventi.isEmpty {
                            Text("NESSUN PASSAGGIO")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                                .foregroundStyle(Color.tenue).multilineTextAlignment(.center)
                                .padding(14).frame(maxWidth: .infinity)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        }
                        ForEach(s.eventi) { e in riga(e) }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Una riga: il fotogramma, SOGGETTO e l'ora (ore, minuti e secondi, come nel mockup).
    private func riga(_ e: Sentinella.Evento) -> some View {
        HStack(spacing: 12) {
            if let img = UIImage(data: e.foto) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 64, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.ciano.opacity(0.3), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SOGGETTO: \(e.cosa.uppercased())")
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1)
                    .foregroundStyle(.white)
                Text(e.quando.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ciano)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ciano.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.18), lineWidth: 1))
    }
}
#endif
