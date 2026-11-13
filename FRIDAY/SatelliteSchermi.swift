#if os(iOS)
import SwiftUI
import UIKit
import MapKit
import AVFoundation

/// SATELLITE › NAVIGA e GUIDA, a tutto schermo come nel mockup (intestazione J.A.R.V.I.S., la bussola, la X nel cerchio).
/// NAVIGA: il percorso a piedi a tappe, ogni tappa con la sua vista da strada (Look Around di Apple) e le frecce
/// olografiche; GUIDA: la fotocamera con le frecce verso il percorso, i metri che scendono, come TRACCIA.
/// In tutte e due il piccolo tasto di scatto (fotocamera dietro o davanti) mette le foto nel DOSSIER del luogo.

private let scuro = Color(red: 0.016, green: 0.039, blue: 0.047)          // rgba(4,10,12)

// MARK: - I pezzi comuni

/// L'intestazione delle schermate a tutto schermo (come Trainer e Occhi): J.A.R.V.I.S., la riga sotto, la bussola e la chiusura.
/// 5 nov sera (il signore, regola fissa): la X nel cerchio solo dove la fotocamera è aperta (GUIDA); NAVIGA mostra la vista da
/// strada e si chiude con la scritta «Chiudi», come le altre schede senza fotocamera.
struct TestaSat: View {
    let sotto: String
    let bussola: String
    var conFotocamera = false
    let chiudi: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("J.A.R.V.I.S.").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                Text(sotto).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.7).lineLimit(1)
            }
            .foregroundStyle(Color.ciano)
            Spacer(minLength: 4)
            Text(bussola)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Color.ciano)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            Button(action: chiudi) {
                if conFotocamera {
                    TondoX()                                     // 7 nov sera: il tondo di tutte le sezioni (24 a vista, 44 al tocco)
                } else {
                    Text("Chiudi").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ciano).frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(StileStark())
            .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 20).padding(.top, 8)
    }
}

/// I tasti in fondo alle schermate di SATELLITE: a contorno (MAPPE, NAVIGA, FOTO…) o pieni (Guida, Fine guida).
struct TastoSat: View {
    let testo: String
    var pieno = false
    var alto: CGFloat? = nil
    var attivo = true
    var rosso = false
    var conferma = false
    let azione: () -> Void
    private static let rossoChiaro = Color(red: 1.0, green: 0.54, blue: 0.50)     // #ff8a80
    private static let rossoPieno = Color(red: 1.0, green: 0.353, blue: 0.314)     // #ff5a50

    var body: some View {
        Button(action: azione) {
            Text(testo)
                .font(pieno ? .system(size: 14, weight: .semibold, design: .monospaced) : .system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(pieno ? 0 : 1.5)
                .textCase(pieno ? nil : .uppercase)
                .lineLimit(1)
                .foregroundStyle(pieno ? Color.fondo : conferma ? .white : rosso ? TastoSat.rossoChiaro : Color.ciano)
                .frame(maxWidth: .infinity)
                .frame(height: alto ?? 38)
                .background(RoundedRectangle(cornerRadius: pieno ? 12 : 10).fill(pieno ? Color.ciano2 : conferma ? TastoSat.rossoPieno : Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: pieno ? 12 : 10)
                    .stroke(pieno ? Color.ciano2 : rosso ? Color(red: 1, green: 0.35, blue: 0.31).opacity(0.7) : Color.ciano.opacity(0.35), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
        .disabled(!attivo)
        .opacity(attivo ? 1 : 0.5)
    }
}

/// L'avviso che scende dall'alto (come TRACCIA): una notifica di iOS subito, senza suono.
enum AvvisoSat {
    static func mostra(_ testo: String) { Task { await PannelliTraccia.notifica(testo) } }
}

/// Il piccolo tasto di scatto, come nel mockup: a destra sopra i comandi, DIETRO/DAVANTI, il giro della fotocamera,
/// il tasto con il numero di foto del dossier. Lo scatto vero lo fa chi lo usa (`scatta`); la foto va nel DOSSIER.
struct ScattoSat: View {
    let luogo: LuogoSat
    let da: String                                    // naviga, guida
    @Binding var lampo: Bool
    let scatta: (_ davanti: Bool) async -> Data?
    @ObservedObject private var archivio = ArchivioFotoSat.condiviso
    @State private var davanti = false
    @State private var occupato = false

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            // 9 nov notte: sopra la vista da strada la scritta si perdeva: nella capsula scura, come la bussola in alto
            Text(davanti ? "DAVANTI" : "DIETRO")
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
                .foregroundStyle(Color.ciano)
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(Capsule().fill(Color.black.opacity(0.45)))
            Button {
                Suoni.tocco()
                davanti.toggle()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(davanti ? Color.fondo : Color.ciano)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(davanti ? Color.ciano : Color.black.opacity(0.5)))
                    .overlay(Circle().stroke(Color.ciano.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(StileStark())
            .accessibilityLabel(davanti ? "Fotocamera dietro" : "Fotocamera davanti")
            Button { Task { await scatto() } } label: {
                ZStack(alignment: .topTrailing) {
                    Circle().fill(Color.ciano.opacity(0.3)).frame(width: 30, height: 30)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .overlay(Circle().stroke(Color.ciano, lineWidth: 2.5))
                        .shadow(color: Color.ciano.opacity(0.55), radius: 6)
                    Text("\(archivio.di(luogo.chiave).filter { !$0.archiviata }.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.fondo)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Color.ciano))
                        .offset(x: 6, y: -6)
                }
            }
            .buttonStyle(StileStark())
            .disabled(occupato)
            .accessibilityLabel("Scatta una foto per il dossier")
        }
    }

    private func scatto() async {
        guard !occupato else { return }
        occupato = true
        defer { occupato = false }
        Suoni.tocco()
        lampo = true
        guard await AVCaptureDevice.requestAccess(for: .video), let dati = await scatta(davanti) else {
            Suoni.errore(); return
        }
        guard archivio.aggiungi(dati, luogo: luogo.chiave, da: da, cam: davanti ? "davanti" : "dietro") else { Suoni.errore(); return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AvvisoSat.mostra("Foto nel dossier di \(luogo.nome), Sir.")
    }
}

/// Il lampo bianco dello scatto (0,32 s), su tutto lo schermo.
struct LampoSat: View {
    @Binding var acceso: Bool
    @State private var luce = 0.0
    var body: some View {
        Color.white.opacity(luce).ignoresSafeArea().allowsHitTesting(false)
            .onChange(of: acceso) { _, si in
                guard si else { return }
                luce = 0.85
                withAnimation(.easeOut(duration: 0.32)) { luce = 0 }
                acceso = false
            }
    }
}

/// Una foto con la fotocamera scelta, senza anteprima (NAVIGA: sullo schermo c'è la vista da strada).
enum ScattoVeloce {
    static func foto(davanti: Bool) async -> Data? {
        let m = MotoreOcchi()
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            m.avvia(posizione: davanti ? .front : .back) { ok in c.resume(returning: ok) }
        }
        guard ok else { m.ferma(); return nil }
        try? await Task.sleep(for: .milliseconds(600))          // esposizione e messa a fuoco
        let d = await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
            m.scatta(veloce: false) { d in c.resume(returning: d) }
        }
        m.ferma()
        return d
    }
}

// MARK: - Look Around

/// La vista da strada di Apple (MKLookAroundViewController): si gira col dito e ci si muove nella via.
/// 7 nov (screenshot del signore): la scritta di Apple «Guardati intorno» finiva sopra l'ora e la batteria, e il marchio «Mappe»
/// sotto il tasto MAPPE. SwiftUI, a tutto schermo, azzera i margini sicuri della vista e i nostri si perdevano; ora la vista di Apple
/// sta dentro un contenitore che le dà i suoi margini a ogni giro: sopra l'ora e l'intestazione (`sopra`), sotto i comandi (`sotto`).
/// Così i segni di Apple (obbligatori) restano visibili, ma fuori dai nostri tasti.
struct VistaLookAround: UIViewControllerRepresentable {
    let scena: MKLookAroundScene?
    var sopra: CGFloat = 60
    var sotto: CGFloat = 0

    func makeUIViewController(context: Context) -> ContenitoreLookAround {
        let c = ContenitoreLookAround()
        c.vista.isNavigationEnabled = true
        c.vista.showsRoadLabels = true
        // 9 nov notte (il signore, screenshot 02:13: «Guardati intorno» di Apple sopra l'ora, il Wi-Fi e la batteria): la vista di Apple
        // mette il suo tasto in alto senza tener conto dei margini; in basso a destra invece li rispetta (il marchio «Mappe» sta già
        // giusto, sopra i comandi). Il tasto va lì, accanto al marchio: i segni di Apple restano visibili, la testata è libera
        c.vista.badgePosition = .bottomTrailing
        c.vista.scene = scena
        c.sopra = sopra
        c.sotto = sotto
        return c
    }

    func updateUIViewController(_ c: ContenitoreLookAround, context: Context) {
        if c.vista.scene !== scena { c.vista.scene = scena }
        if c.sopra != sopra || c.sotto != sotto {
            c.sopra = sopra
            c.sotto = sotto
            c.view.setNeedsLayout()
        }
    }
}

/// Il contenitore della vista da strada: tiene i margini sicuri giusti anche a tutto schermo.
final class ContenitoreLookAround: UIViewController {
    let vista = MKLookAroundViewController(nibName: nil, bundle: nil)
    var sopra: CGFloat = 60
    var sotto: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(vista)
        vista.view.frame = view.bounds
        vista.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(vista.view)
        vista.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // i margini veri dello schermo (l'isola, la barra in fondo) più l'intestazione e i comandi, tolto quello che c'è già
        let schermo = view.window?.safeAreaInsets ?? .zero
        let gia = view.safeAreaInsets
        let voluti = UIEdgeInsets(top: max(0, schermo.top + sopra - gia.top), left: 0,
                                  bottom: max(0, schermo.bottom + sotto - gia.bottom), right: 0)
        if vista.additionalSafeAreaInsets != voluti { vista.additionalSafeAreaInsets = voluti }
    }
}

// MARK: - Le frecce olografiche

/// NAVIGA, sopra la vista da strada: le frecce a «V» sul selciato, dritte e poi (se c'è) la svolta, che si accendono in fila
/// verso la meta; la meta con l'asta, l'anello che pulsa e il cartellino («↱ VIA TORTONA · 80 m», all'arrivo il nome).
struct FrecceNaviga: View {
    let svolta: GuidaCondivisa.Svolta
    let testo: String

    var body: some View {
        // a tutto schermo (chi la usa ignora la zona sicura): i bordi sicuri servono a tenere dentro il cartellino (decisione 42)
        GeometryReader { g in
            let bordi = g.safeAreaInsets
            TimelineView(.animation(minimumInterval: nil)) { ctx in                   // 4 nov: a 120 Hz come tutta l'app (prima 30)
                Canvas { gc, size in disegna(gc, size, t: ctx.date.timeIntervalSinceReferenceDate, bordi: bordi) }
            }
        }
        .allowsHitTesting(false)
    }

    private func disegna(_ gc: GraphicsContext, _ size: CGSize, t: Double, bordi: EdgeInsets) {
        let W = Double(size.width), H = Double(size.height)
        let giro: Double = svolta == .destra ? 1 : svolta == .sinistra ? -1 : 0
        let arrivo = svolta == .arrivo
        // il percorso sullo schermo: da sotto verso il fondo della via, poi di lato per la svolta (prospettiva: più piccole lontano)
        var punti: [(x: Double, y: Double, scala: Double, angolo: Double)] = []
        let passi = arrivo ? 4 : 6
        for k in 0..<passi {
            let u = Double(k) / Double(passi)
            punti.append((W / 2, H * (0.93 - u * 0.30), 1 - u * 0.6, -Double.pi / 2))
        }
        var fine = (x: W / 2, y: H * (0.93 - 0.30))
        if giro != 0 {
            for k in 1...4 {
                let u = Double(k) / 4
                punti.append((W / 2 + giro * W * 0.32 * u, H * (0.63 - u * 0.02), 0.4 - u * 0.1, giro > 0 ? 0 : Double.pi))
            }
            fine = (x: W / 2 + giro * W * 0.36, y: H * 0.61)
        }
        let ciano = Color.ciano
        var luce = gc
        luce.addFilter(.shadow(color: ciano, radius: 6))
        for (n, p) in punti.enumerated() {
            let f = ((t * 1.6 - Double(n) * 0.35).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            var g = luce
            g.opacity = 0.25 + 0.7 * pow(1 - f, 2)
            g.translateBy(x: CGFloat(p.x), y: CGFloat(p.y))
            g.scaleBy(x: CGFloat(p.scala), y: CGFloat(p.scala * 0.55))      // schiacciata in verticale: sta sul selciato
            g.rotate(by: .radians(p.angolo + Double.pi / 2))
            var v = Path()                                                  // la «V» del mockup
            v.move(to: CGPoint(x: -44, y: 20)); v.addLine(to: CGPoint(x: 0, y: -18)); v.addLine(to: CGPoint(x: 44, y: 20))
            v.addLine(to: CGPoint(x: 44, y: -3)); v.addLine(to: CGPoint(x: 0, y: -41)); v.addLine(to: CGPoint(x: -44, y: -3))
            v.closeSubpath()
            g.fill(v, with: .color(ciano.opacity(0.8)))
        }
        // la meta: l'anello che pulsa, l'asta, il cartellino
        let pulsa = (t * 0.9).truncatingRemainder(dividingBy: 1)
        let rx = (16 + pulsa * 20) * (giro != 0 ? 0.7 : 1)
        var anello = luce
        anello.opacity = (1 - pulsa) * 0.9
        anello.stroke(Path(ellipseIn: CGRect(x: fine.x - rx, y: fine.y - rx * 0.3, width: rx * 2, height: rx * 0.6)), with: .color(ciano), lineWidth: 2)
        var asta = Path()
        asta.move(to: CGPoint(x: fine.x, y: fine.y))
        asta.addLine(to: CGPoint(x: fine.x, y: fine.y - H * 0.22))
        var a = luce
        a.opacity = 0.45
        a.stroke(asta, with: .color(ciano), lineWidth: 2)
        disegnaCartellino(gc, testo: testo, x: fine.x, y: fine.y - H * 0.22 - 4, schermo: size, bordi: bordi, acceso: arrivo)
    }
}

/// GUIDA, sopra la fotocamera: come la TRACCIA di Ricordi, le frecce a chevron dal basso verso la direzione del percorso
/// (a destra o a sinistra di quanto bisogna girarsi), la meta con l'anello e l'asta, il cartellino della tappa.
struct FrecceGuida: View {
    /// Di quanti gradi girarsi per avere il percorso davanti (nil: niente posizione o bussola).
    let relativa: Double?
    let testo: String
    let arrivato: Bool

    var body: some View {
        // a tutto schermo (chi la usa ignora la zona sicura): i bordi sicuri servono a tenere dentro il cartellino (decisione 42)
        GeometryReader { g in
            let bordi = g.safeAreaInsets
            TimelineView(.animation(minimumInterval: nil)) { ctx in                   // 4 nov: a 120 Hz come tutta l'app (prima 30)
                Canvas { gc, size in disegna(gc, size, t: ctx.date.timeIntervalSinceReferenceDate, bordi: bordi) }
            }
        }
        .allowsHitTesting(false)
    }

    private func disegna(_ gc: GraphicsContext, _ size: CGSize, t: Double, bordi: EdgeInsets) {
        let W = Double(size.width), H = Double(size.height)
        let s = W / 390
        let ciano = Color.ciano
        let angolo: Double = max(-80, min(80, relativa ?? 0)) * Double.pi / 180
        let bx: Double = W * (0.5 + 0.42 * sin(angolo)), by: Double = H * 0.50
        let ax: Double = W * 0.5, ay: Double = H * 0.86, cx0: Double = W * 0.5, cy0: Double = H * 0.62
        func punto(_ u: Double) -> (x: Double, y: Double) {
            let v: Double = 1 - u
            return (v * v * ax + 2 * v * u * cx0 + u * u * bx, v * v * ay + 2 * v * u * cy0 + u * u * by)
        }
        var luce = gc
        luce.addFilter(.shadow(color: ciano, radius: CGFloat(8 * s)))
        if relativa != nil && !arrivato {
            for k in 0..<7 {
                let u: Double = (Double(k) + (t * 0.9).truncatingRemainder(dividingBy: 1)) / 7
                if u > 0.96 { continue }
                let p = punto(u), q = punto(min(1, u + 0.02))
                let an: Double = atan2(q.y - p.y, q.x - p.x)
                let lato: Double = 46 * (1 - u * 0.78) * s
                var freccia = Path()
                freccia.move(to: CGPoint(x: p.x + cos(an + 2.4) * lato, y: p.y + sin(an + 2.4) * lato * 0.45))
                freccia.addLine(to: CGPoint(x: p.x, y: p.y))
                freccia.addLine(to: CGPoint(x: p.x + cos(an - 2.4) * lato, y: p.y + sin(an - 2.4) * lato * 0.45))
                var g = luce
                g.opacity = min(1, (1 - u) * 1.4) * (0.55 + 0.45 * sin(t * 4 - Double(k)))
                g.stroke(freccia, with: .color(ciano), style: StrokeStyle(lineWidth: CGFloat(max(2, 9 * (1 - u * 0.8)) * s), lineCap: .round, lineJoin: .round))
            }
        }
        // la meta: l'anello che pulsa e l'asta
        let pulsa: Double = (t * 0.8).truncatingRemainder(dividingBy: 1)
        let rx: Double = (18 + pulsa * 40) * s
        var anello = luce
        anello.opacity = 1 - pulsa
        anello.stroke(Path(ellipseIn: CGRect(x: bx - rx, y: by - rx * 0.35, width: rx * 2, height: rx * 0.7)), with: .color(ciano), lineWidth: 2)
        var asta = Path()
        asta.move(to: CGPoint(x: bx, y: by))
        asta.addLine(to: CGPoint(x: bx, y: by - 150 * s))
        luce.stroke(asta, with: .color(ciano), lineWidth: 2)
        disegnaCartellino(gc, testo: testo, x: bx, y: by - 154 * s, schermo: size, bordi: bordi, acceso: arrivato)
    }
}

/// Il cartellino olografico sopra la meta (.nav-et del mockup), poggiato sul punto (x, y) in cima all'asta.
/// Decisione 42: sempre tutto dentro lo schermo visibile (la zona sicura, a 6 punti dal bordo): a destra, a sinistra, in alto
/// e in basso. Prima si teneva dentro solo ai lati, e senza contare la Dynamic Island in orizzontale.
private func disegnaCartellino(_ gc: GraphicsContext, testo: String, x: Double, y: Double, schermo: CGSize, bordi: EdgeInsets, acceso: Bool) {
    guard !testo.isEmpty else { return }
    let scritta = gc.resolve(Text(testo).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(acceso ? Color.white : ColoriHUD.chiaro))
    let m = scritta.measure(in: CGSize(width: 1000, height: 100))
    let w = Double(m.width) + 14, h = Double(m.height) + 6
    let sx = Double(bordi.leading) + 6, dx = Double(schermo.width - bordi.trailing) - 6
    let su = Double(bordi.top) + 6, giu = Double(schermo.height - bordi.bottom) - 6
    let cx = min(max(x, sx + w / 2), max(sx + w / 2, dx - w / 2))
    let basso = min(max(y, su + h), max(su + h, giu))                  // il lato basso del cartellino
    let r = CGRect(x: cx - w / 2, y: basso - h, width: w, height: h)
    let forma = Path(roundedRect: r, cornerRadius: 6)
    var g = gc
    if acceso { g.addFilter(.shadow(color: Color.ciano.opacity(0.5), radius: 6)) }
    g.fill(forma, with: .color(Color(red: 0.02, green: 0.03, blue: 0.035).opacity(0.8)))
    g.stroke(forma, with: .color(Color.ciano.opacity(acceso ? 1 : 0.6)), lineWidth: 1)
    gc.draw(scritta, at: CGPoint(x: cx, y: basso - h / 2), anchor: .center)
}

/// 9 nov notte (il signore: «risolvi il casino grafico… le sovrapposizioni in alto e riordina»): la vista da strada vera e la
/// fotocamera sono chiare (cielo, facciate), non scure come le viste del mockup, e l'ora, la testata, la bussola e «Chiudi» ci si
/// perdevano sopra; in fondo le frecce passavano sotto i comandi e il totale «A piedi» non si leggeva. Due veli scuri, come le app di
/// foto e mappe di iOS: in alto dietro la barra di iOS e la testata, in basso dietro i comandi (`sotto`: quanto sono alti).
struct VeliSat: View {
    let sotto: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [.init(color: .black.opacity(0.72), location: 0), .init(color: .black.opacity(0.45), location: 0.55),
                                   .init(color: .black.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: FasciaAlta.margineAlto + 120)
            Spacer(minLength: 0)
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0), .init(color: .black.opacity(0.6), location: 0.3),
                                   .init(color: .black.opacity(0.82), location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: sotto + FasciaAlta.fondo + 70)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - NAVIGA

struct SchermoNaviga: View {
    let luogo: LuogoSat
    let apri: (PaginaSat?) -> Void
    @ObservedObject private var motore = MotoreGuida.condiviso
    @State private var percorso: PercorsoSat?
    @State private var errore: String?
    @State private var tappaVista = 0
    @State private var scene: [Int: MKLookAroundScene] = [:]
    @State private var cercate: Set<Int> = []
    @State private var foto: [Int: UIImage] = [:]
    @State private var lampo = false
    @State private var visibile = false
    @State private var altoGiu: CGFloat = 0           // 7 nov: quanto sono alti i comandi in fondo (il marchio di Apple sta sopra)

    private var tappa: TappaSat? { percorso.flatMap { $0.tappe.indices.contains(tappaVista) ? $0.tappe[tappaVista] : nil } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VistaLookAround(scena: scene[tappaVista], sopra: 60, sotto: altoGiu).ignoresSafeArea()
            if percorso != nil, cercate.contains(tappaVista), scene[tappaVista] == nil {
                Text("VISTA DA STRADA NON DISPONIBILE QUI")                  // Apple non ha Look Around in questo punto
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.tenue)
            }
            if let t = tappa {
                FrecceNaviga(svolta: t.svolta, testo: t.svolta == .arrivo ? luogo.nome.uppercased()
                             : "\(t.svolta.freccia) \(t.via.uppercased()) · \(Rotta.distanza(t.metri))")
                    .ignoresSafeArea()
            }
            VeliSat(sotto: altoGiu)

            // decisione 16: sugli iPhone da 375 punti girati in orizzontale (12/13 mini: 354 punti d'altezza utile) la colonna
            // (circa 368 punti) non ci stava e la testata si tagliava. Solo quando non ci sta si stringono gli spazi tra i pezzi
            // (10 → 6) e il margine in fondo (22 → 14): niente tolto. Dove ci sta (il 15 Pro, 372 punti) resta identica
            ViewThatFits(in: .vertical) {
                colonna(stretta: false)
                colonna(stretta: true)
            }
            LampoSat(acceso: $lampo)
        }
        .opacity(visibile ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { visibile = true } }
        .preferredColorScheme(.dark)
        .task { await prepara() }
        .task(id: tappaVista) { await scenaDi(tappaVista) }
        .onDisappear { MotoreGuida.condiviso.spegniSeLibero() }        // senza una guida in corso il GPS si spegne
    }

    /// La testata in alto e i comandi in fondo. `stretta`: gli spazi più piccoli, solo se così non ci sta (decisione 16).
    private func colonna(stretta: Bool) -> some View {
        VStack(spacing: 0) {
            TestaSat(sotto: "NAVIGA · \(luogo.nome.uppercased())", bussola: tappa?.rotta.map { Rotta.bussola($0) } ?? "N · 0°") {
                Suoni.tocco(); apri(nil)
            }
            Spacer(minLength: 0)
            giu(stretta: stretta)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altoGiu = $0 }
        }
    }

    private func giu(stretta: Bool) -> some View {
        VStack(spacing: stretta ? 6 : 10) {
            ScattoSat(luogo: luogo, da: "naviga", lampo: $lampo) { davanti in await ScattoVeloce.foto(davanti: davanti) }
            HStack(spacing: 12) {
                Text(tappa?.svolta.freccia ?? "↑")
                    .font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(Color.ciano)
                    .shadow(color: Color.ciano.opacity(0.7), radius: 5)
                    .frame(minWidth: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tappa?.testo ?? errore ?? "—").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sottoIstruzione).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Color.ciano)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(scuro.opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ciano.opacity(0.5), lineWidth: 1))
            if let p = percorso {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(p.tappe) { t in
                            Button { Suoni.tocco(); tappaVista = t.id } label: { miniatura(t) }
                                .buttonStyle(StileStark())
                        }
                    }
                }
                Text("A piedi \(Text(Rotta.distanza(p.metri)).foregroundStyle(.white).bold()) · \(Text(Rotta.aPiedi(p.metri).replacingOccurrences(of: "circa ", with: "")).foregroundStyle(.white).bold())")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ColoriHUD.chiaro.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                TastoSat(testo: "Mappe", alto: 48) { Suoni.tocco(); apriMappe() }
                TastoSat(testo: "Guida", pieno: true, alto: 48) { Suoni.tocco(); apri(.guida(luogo)) }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, stretta ? 14 : 22)
    }

    private var sottoIstruzione: String {
        guard let p = percorso, let t = tappa else { return "" }
        return t.svolta == .arrivo ? "\(luogo.nome) · arrivo" : "per \(Rotta.distanza(t.metri)) · tappa \(t.id + 1) di \(p.tappe.count)"
    }

    private func miniatura(_ t: TappaSat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color(red: 0.03, green: 0.07, blue: 0.08)
                if let f = foto[t.id] {
                    Image(uiImage: f).resizable().scaledToFill()
                } else if cercate.contains(t.id), scene[t.id] == nil {
                    // 7 nov: lì Apple non ha la vista da strada (prima restava un riquadro nero), come nel DOSSIER
                    Text("NON DISPONIBILE").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1)
                        .foregroundStyle(Color.tenue)
                }
            }
            .frame(width: 112, height: 70).clipped()
            Text("\(t.id + 1) · \(t.svolta.freccia) \(t.via)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.5)
                .foregroundStyle(ColoriHUD.chiaro).lineLimit(1).truncationMode(.tail)
                .padding(.vertical, 5).padding(.horizontal, 7)
                .frame(width: 112, alignment: .leading)
        }
        .background(scuro.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(t.id == tappaVista ? 1 : 0.35), lineWidth: 1))
        .shadow(color: Color.ciano.opacity(t.id == tappaVista ? 0.45 : 0), radius: 6)
    }

    /// Il percorso da qui al luogo, poi le viste da strada di tutte le tappe per le miniature.
    private func prepara() async {
        MotoreGuida.condiviso.accendi()
        for _ in 0..<50 where motore.lat == nil && !motore.posizioneNegata {   // la posizione: fino a 10 secondi (negata: subito la frase)
            try? await Task.sleep(for: .milliseconds(200))
            if Task.isCancelled { return }
        }
        guard let la = motore.lat, let lo = motore.lon else { errore = ErroreSat.posizione.testo; return }
        switch await PercorsoSat.calcola(da: CLLocationCoordinate2D(latitude: la, longitude: lo), a: luogo) {
        case .success(let p): percorso = p; errore = nil
        case .failure(let e): errore = e.testo; return
        }
        await scenaDi(tappaVista)
        for t in percorso?.tappe ?? [] {
            if Task.isCancelled { return }
            await scenaDi(t.id)
            if foto[t.id] == nil, let s = scene[t.id], let img = await VistaStrada.foto(s, larga: 224, alta: 140) { foto[t.id] = img }
        }
    }

    private func scenaDi(_ i: Int) async {
        guard let p = percorso, p.tappe.indices.contains(i), !cercate.contains(i) else { return }
        cercate.insert(i)
        let t = p.tappe[i]
        // l'arrivo: la vista che guarda il luogo; le svolte: la vista nel punto della svolta
        let s = t.svolta == .arrivo ? await VistaStrada.scena(guardando: luogo.coordinata) : await VistaStrada.scena(t.punto)
        if let s { scene[i] = s }
    }

    /// MAPPE: Apple Mappe, a piedi fino al luogo.
    private func apriMappe() {
        let m = MKMapItem(placemark: MKPlacemark(coordinate: luogo.coordinata))
        m.name = luogo.nome
        _ = m.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

// MARK: - GUIDA

struct SchermoGuida: View {
    let luogo: LuogoSat
    let apri: (PaginaSat?) -> Void
    @ObservedObject private var motore = MotoreGuida.condiviso
    @State private var camera: MotoreOcchi?
    @State private var cameraAccesa = false
    @State private var lampo = false
    @State private var visibile = false
    @State private var altoGiu: CGFloat = 0           // 9 nov: quanto sono alti i comandi in fondo (il velo scuro ci sta dietro)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraAccesa, let m = camera { AnteprimaOcchi(sessione: m.sessione).ignoresSafeArea() }
            FrecceGuida(relativa: relativa, testo: cartellino, arrivato: motore.arrivato).ignoresSafeArea()
            VeliSat(sotto: altoGiu)
            VStack(spacing: 0) {
                TestaSat(sotto: "GUIDA · \(luogo.nome.uppercased())", bussola: motore.direzione.map { Rotta.bussola($0) } ?? "N · 0°", conFotocamera: true) {
                    Suoni.tocco(); apri(nil)                       // la guida resta attiva: negli Occhi e al polso
                }
                su
                Spacer(minLength: 0)
                giu
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { altoGiu = $0 }
            }
            LampoSat(acceso: $lampo)
        }
        .opacity(visibile ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { visibile = true } }
        .preferredColorScheme(.dark)
        .task { await accendiCamera() }
        .onDisappear { camera?.ferma(); cameraAccesa = false; MotoreGuida.condiviso.spegniSeLibero() }   // una guida in corso resta; una mai partita finisce
        // la guida finita (arrivo, «Fine guida», «ferma la guida»): la schermata si chiude
        .onChange(of: motore.luogo?.chiave) { _, k in if k != luogo.chiave { apri(nil) } }
    }

    /// La tappa in corso (o la prima, finché il percorso non c'è).
    private var tappa: TappaSat? { motore.tappa }

    private var relativa: Double? {
        guard let r = motore.rilevamento, let d = motore.direzione else { return nil }
        return Rotta.relativa(rilevamento: r, direzione: d)
    }

    private var cartellino: String {
        guard let t = tappa else { return "" }
        return t.svolta == .arrivo || motore.arrivato ? luogo.nome.uppercased() : "\(t.svolta.freccia) \(t.via.uppercased())"
    }

    private var su: some View {
        HStack(spacing: 12) {
            Text(motore.arrivato ? GuidaCondivisa.Svolta.arrivo.freccia : tappa?.svolta.freccia ?? "↑")
                .font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(Color.ciano)
                .shadow(color: Color.ciano.opacity(0.7), radius: 5)
                .frame(minWidth: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(titolo).font(.system(size: 18, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(sottotitolo).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Color.ciano)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(scuro.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ciano.opacity(0.55), lineWidth: 1))
        .padding(.horizontal, 16).padding(.top, 10)
    }

    /// «PER 50 M», «TRA 30 M» (l'ultima tappa), «ARRIVATO».
    private var titolo: String {
        if motore.arrivato { return "ARRIVATO" }
        guard let t = tappa else { return "—" }
        if t.svolta == .arrivo { return "TRA \(Rotta.distanza(motore.manca ?? 0).uppercased())" }
        return "PER \(Rotta.distanza(motore.mancaTappa ?? 0).uppercased())"
    }

    /// «poi: a destra in via tortona»; all'arrivo il luogo; senza percorso, il motivo.
    private var sottotitolo: String {
        if motore.arrivato { return luogo.nome == luogo.via ? luogo.nome : "\(luogo.nome) · \(luogo.via)" }
        if let e = motore.errore, motore.percorso == nil { return e }
        guard let p = motore.percorso, let t = tappa else { return "—" }
        return t.id + 1 < p.tappe.count ? "poi: \(p.tappe[t.id + 1].testo.lowercased())" : t.testo
    }

    private var giu: some View {
        VStack(spacing: 10) {
            ScattoSat(luogo: luogo, da: "guida", lampo: $lampo) { davanti in await scatta(davanti: davanti) }
            HStack(spacing: 8) {
                dato(motore.manca.map { Rotta.distanza($0) } ?? "—", "MANCANO")
                dato(motore.manca.map { $0 < 40 ? "ora" : "\(max(1, Int(($0 / 80).rounded()))) min" } ?? "—", "A PIEDI")
                dato(motore.percorso.map { "\(min(motore.indice + 1, $0.tappe.count))/\($0.tappe.count)" } ?? "—", "TAPPA")
            }
            Text("La guida resta attiva anche se chiude: negli Occhi e sull'orologio c'è la freccia.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(ColoriHUD.chiaro.opacity(0.7))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                TastoSat(testo: "Naviga", alto: 48) { Suoni.tocco(); apri(.naviga(luogo)) }
                TastoSat(testo: "Fine guida", pieno: true, alto: 48) {
                    Suoni.tocco()
                    MotoreGuida.condiviso.ferma()
                    apri(nil)
                    AvvisoSat.mostra("Guida finita, Sir.")
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 22)
    }

    private func dato(_ valore: String, _ nome: String) -> some View {
        VStack(spacing: 1) {
            Text(valore).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(nome).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.5), lineWidth: 1))
    }

    /// La fotocamera dietro, come TRACCIA: parte quando la schermata c'è e si ferma quando si chiude.
    private func accendiCamera() async {
        guard await AVCaptureDevice.requestAccess(for: .video), !Task.isCancelled else { return }
        let m = camera ?? MotoreOcchi()
        camera = m
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            m.avvia(posizione: .back) { ok in c.resume(returning: ok) }
        }
        if !Task.isCancelled { cameraAccesa = ok } else { m.ferma() }
    }

    /// Lo scatto: dietro, dalla fotocamera accesa; davanti, la frontale per un attimo e poi di nuovo quella dietro.
    private func scatta(davanti: Bool) async -> Data? {
        guard let m = camera, cameraAccesa else { return await ScattoVeloce.foto(davanti: davanti) }
        if davanti {
            _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                m.avvia(posizione: .front) { ok in c.resume(returning: ok) }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        let d = await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
            m.scatta(veloce: false) { d in c.resume(returning: d) }
        }
        if davanti {
            _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                m.avvia(posizione: .back) { ok in c.resume(returning: ok) }
            }
        }
        return d
    }
}
#endif
