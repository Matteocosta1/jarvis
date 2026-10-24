#if os(iOS)
import SwiftUI
import AVFoundation
import UserNotifications

/// Ricordi › TRACCIA (build 22): la bussola con la freccia verso un LUOGO salvato (di base il più recente), i metri grandi,
/// la distanza e il tempo a piedi. «Luoghi» li elenca per sceglierne un altro, «Salva» aggiunge quello dove si trova adesso.
/// La fotocamera si accende solo col tasto «Guida» (o con «Jarvis, portami al luogo»): allora la vista dalla fotocamera
/// con le frecce olografiche, come nel mockup.
struct PannelliTraccia: View {
    /// I luoghi salvati, dal più recente (i «posti» della seconda memoria con le coordinate).
    let luoghi: [DatiRicordi.Riga]
    let ultimi: [DatiRicordi.Riga]
    /// La Guida (fotocamera e frecce): spenta quando si apre Ricordi, accesa subito da «Jarvis, portami al luogo».
    @Binding var guida: Bool
    /// «Jarvis, ricorda questo luogo»: appena c'è la posizione, si salva da solo. Il segno sta in VistaRicordi e si spegne
    /// appena parte il salvataggio, così cambiando scheda e tornando su TRACCIA non si salva una seconda volta.
    @Binding var salvaSubito: Bool
    /// Dopo un salvataggio: ricarica i ricordi (il luogo nuovo arriva in testa) e dice quale id scegliere.
    let ricarica: () async -> Void
    @StateObject private var bussola = Bussola()
    @State private var sceltoId: Int?
    @State private var elenco = false
    @State private var salvo = false
    @State private var avviso: String?
    private let tinta = Color.ciano

    /// Il luogo puntato: quello scelto, se c'è ancora; altrimenti il più recente.
    private var scelto: DatiRicordi.Riga? { luoghi.first { $0.id == sceltoId } ?? luoghi.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Pannello(titolo: "TRACCIA", tinta: tinta) {
                if let avviso { AvvisoJarvis(testo: avviso) }
                if let l = scelto, let lat = l.lat, let lon = l.lon {
                    let rotta = bussola.verso(lat: lat, lon: lon)
                    if guida {
                        // la fotocamera vive solo dentro VistaAR: spenta la Guida, VistaAR esce e la ferma (onDisappear)
                        VistaAR(lat: lat, lon: lon, nome: PannelliTraccia.etichetta(l), bussola: bussola)
                            .aspectRatio(720.0 / 520.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.22), lineWidth: 1))
                    } else {
                        BussolaTraccia(rilevamento: rotta?.rilevamento, direzione: bussola.direzione)
                            .aspectRatio(4.0 / 3.0, contentMode: .fit)
                            .frame(maxWidth: 280)
                            .frame(maxWidth: .infinity)
                        Text(rotta.map { Rotta.distanza($0.metri) } ?? "…")
                            .font(.system(size: 34, weight: .bold, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    RigaHUD("Luogo", PannelliTraccia.nome(l))
                    RigaHUD("Salvato", l.quando)
                    RigaHUD("Distanza", rotta.map { Rotta.distanza($0.metri) } ?? "cerco la posizione…")
                    RigaHUD("A piedi", rotta.map { Rotta.aPiedi($0.metri) } ?? "—")
                } else {
                    Text("Nessun luogo salvato, Sir. Tocchi «Salva» dove si trova, o dica «Jarvis, ricorda questo luogo».")
                        .font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                }
                HStack(spacing: 8) {
                    TastoComando(testo: guida ? "Bussola" : "Guida", attivo: scelto != nil) { Suoni.tocco(); guida.toggle() }
                    TastoComando(testo: "Luoghi", attivo: !luoghi.isEmpty) { Suoni.tocco(); withAnimation(.easeOut(duration: 0.25)) { elenco.toggle() } }
                    TastoComando(testo: salvo ? "…" : "Salva", attivo: !salvo) { Task { await salva() } }
                }
            }
            if elenco && !luoghi.isEmpty {
                Pannello(titolo: "LUOGHI", tinta: tinta) {
                    ForEach(luoghi) { l in
                        Button { Suoni.tocco(); sceltoId = l.id } label: { rigaLuogo(l, attivo: l.id == scelto?.id) }
                            .buttonStyle(StileStark())
                    }
                }
                .transition(.opacity)
            }
            Pannello(titolo: "ULTIMI", tinta: tinta) {
                if ultimi.isEmpty {
                    Text("Ancora nessun ricordo, Sir.").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                }
                ForEach(ultimi) { r in RigaHUD(r.testo, r.luogo ?? r.quando) }
            }
            PannelloAVoce(frasi: ["«Jarvis, traccia il luogo»", "«Jarvis, portami al luogo»",
                                  "«Jarvis, ricorda questo luogo»", "«Jarvis, dove ho messo le chiavi?»"])
        }
        .onAppear { bussola.accendi() }
        .onDisappear { bussola.spegni() }
        .task(id: bussola.lat != nil) {
            // «ricorda questo luogo»: appena arriva la posizione, una volta sola
            guard salvaSubito, bussola.lat != nil else { return }
            salvaSubito = false
            await salva()
        }
    }

    /// Una riga di LUOGHI: nome e via a sinistra, la distanza da qui a destra; quello puntato è acceso.
    private func rigaLuogo(_ l: DatiRicordi.Riga, attivo: Bool) -> some View {
        let metri = l.lat.flatMap { la in l.lon.flatMap { lo in bussola.verso(lat: la, lon: lo)?.metri } }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.testo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                // sotto il nome la via; se il nome è già la via (un luogo salvato con «Salva»), quando è stato salvato (come nel mockup)
                Text(l.luogo.flatMap { $0.isEmpty || $0 == l.testo ? nil : $0 } ?? l.quando).font(.system(size: 13)).foregroundStyle(Color(red: 0.56, green: 0.70, blue: 0.74)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(metri.map { Rotta.distanza($0) } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .monospaced)).monospacedDigit().foregroundStyle(tinta)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tinta.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(attivo ? tinta : Color(red: 0.07, green: 0.20, blue: 0.23), lineWidth: attivo ? 1.5 : 1))
        .contentShape(Rectangle())
    }

    /// «Salva»: il posto dove si trova adesso diventa un luogo (con la via), e la freccia passa su di lui.
    private func salva() async {
        guard !salvo else { return }
        guard let lat = bussola.lat, let lon = bussola.lon else {
            Suoni.errore(); avviso = "Non ho ancora la sua posizione, Sir: un attimo e riprovi."; return
        }
        salvo = true
        defer { salvo = false }
        guard let o = await VistaVitals.chiama(["luogo_salva": ["lat": lat, "lon": lon] as [String: Any]], attesa: 15),
              let riga = o["luogo"] as? [String: Any], let id = (riga["id"] as? NSNumber)?.intValue else {
            Suoni.errore(); avviso = "Il luogo non si è salvato, Sir: riprovi tra poco."; return
        }
        Suoni.pronto()
        avviso = nil
        await ricarica()
        sceltoId = id
        let via = (riga["luogo"] as? String) ?? (riga["testo"] as? String) ?? "posizione salvata"
        await PannelliTraccia.notifica("Luogo salvato, Sir: \(via).")
    }

    /// «Studio · Via Tortona 12» (o solo la via, se il nome è la via).
    static func nome(_ l: DatiRicordi.Riga) -> String {
        guard let via = l.luogo, !via.isEmpty, via != l.testo else { return l.testo }
        return "\(l.testo) · \(via)"
    }

    /// L'etichetta sopra la meta nella Guida: il nome in maiuscolo, al massimo 16 lettere (come nel mockup).
    static func etichetta(_ l: DatiRicordi.Riga) -> String {
        let n = l.testo.uppercased()
        return n.isEmpty ? "LUOGO" : String(n.prefix(16))
    }

    /// L'avviso che scende dall'alto, come nel mockup: una notifica di iOS subito, senza suono (il «pronto» l'ha già fatto l'app).
    static func notifica(_ testo: String) async {
        let c = UNMutableNotificationContent()
        c.title = "JARVIS"
        c.body = testo
        c.sound = nil
        c.userInfo = ["jarvis_azione": "avviso"]                          // toccata: niente da leggere, l'ha già vista
        let r = UNNotificationRequest(identifier: "luogo-\(Date().timeIntervalSince1970)", content: c, trigger: nil)
        try? await UNUserNotificationCenter.current().add(r)
    }
}

/// La bussola di TRACCIA (come `bussola` del mockup e la versione dell'orologio): il quadrante gira con l'iPhone,
/// la freccia punta il luogo scelto. Si ridisegna quando la bussola cambia (ogni 2°), senza animazione continua.
private struct BussolaTraccia: View {
    let rilevamento: Double?
    let direzione: Double?

    var body: some View {
        Canvas { gc, size in disegna(gc, size) }
            .allowsHitTesting(false)
    }

    private func disegna(_ gc: GraphicsContext, _ size: CGSize) {
        let W = Double(size.width), H = Double(size.height)
        let s = H / 240                                       // le misure del mockup sono su una tela 320 × 240
        let cx = W / 2, cy = H / 2, r = H * 0.42
        let giro = (direzione ?? 0) * Double.pi / 180
        let dir = ((rilevamento ?? 0) - (direzione ?? 0)) * Double.pi / 180
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
        let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
        gc.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(ciano.opacity(0.35)), lineWidth: CGFloat(2 * s))
        var tacche = Path()
        for i in 0..<36 {
            let a: Double = Double(i) / 36 * 2 * Double.pi - giro
            let l: Double = (i % 9 == 0 ? 14 : 6) * s
            tacche.move(to: pt(cx + sin(a) * r, cy - cos(a) * r))
            tacche.addLine(to: pt(cx + sin(a) * (r - l), cy - cos(a) * (r - l)))
        }
        gc.stroke(tacche, with: .color(ciano.opacity(0.35)), lineWidth: CGFloat(2 * s))
        let arancio = Color(red: 1.0, green: 0.706, blue: 0.353)          // #ffb45a
        gc.draw(Text("N").font(.system(size: CGFloat(16 * s), weight: .bold, design: .monospaced)).foregroundStyle(arancio),
                at: pt(cx + sin(-giro) * (r - 26 * s), cy - cos(-giro) * (r - 26 * s)), anchor: .center)
        guard rilevamento != nil else { return }                       // senza posizione, niente freccia
        var freccia = Path()
        freccia.move(to: pt(0, -r * 0.78))
        freccia.addLine(to: pt(r * 0.28, r * 0.12))
        freccia.addLine(to: pt(0, -r * 0.05))
        freccia.addLine(to: pt(-r * 0.28, r * 0.12))
        freccia.closeSubpath()
        var g = gc
        g.translateBy(x: CGFloat(cx), y: CGFloat(cy))
        g.rotate(by: .radians(dir))
        g.addFilter(.shadow(color: ciano, radius: CGFloat(9 * s)))
        g.fill(freccia, with: .color(ciano))
    }
}

/// La strada vista dalla fotocamera e la freccia olografica verso il luogo scelto (disegnata come `disegnaAR` del mockup).
/// Direzione = rilevamento verso il luogo meno la direzione dell'iPhone; in alto la bussola.
/// Esiste solo con la Guida accesa: la fotocamera parte quando compare e si ferma quando esce (Guida spenta o pagina chiusa).
struct VistaAR: View {
    let lat: Double
    let lon: Double
    /// Il nome sopra la meta («STUDIO · 180 m»).
    let nome: String
    @ObservedObject var bussola: Bussola
    /// Creato una volta sola, quando serve: con `= MotoreOcchi()` ogni ridisegno ne costruirebbe uno nuovo (e una sessione).
    @State private var motore: MotoreOcchi?
    @State private var camera = false

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.035)          // #050809, se la fotocamera non c'è
            if camera, let m = motore { AnteprimaOcchi(sessione: m.sessione) }
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                Canvas { gc, size in disegna(gc, size, t: ctx.date.timeIntervalSinceReferenceDate) }
            }
            .allowsHitTesting(false)
        }
        .task {
            guard await AVCaptureDevice.requestAccess(for: .video), !Task.isCancelled else { return }
            let m = motore ?? MotoreOcchi()
            motore = m
            let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                m.avvia { ok in c.resume(returning: ok) }
            }
            if !Task.isCancelled { camera = ok } else { m.ferma() }
        }
        .onDisappear { motore?.ferma(); camera = false }
    }

    private func disegna(_ gc: GraphicsContext, _ size: CGSize, t: Double) {
        let W = Double(size.width), H = Double(size.height)
        let s = W / 720                                       // le misure del mockup sono su una tela larga 720
        let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
        let rotta = bussola.verso(lat: lat, lon: lon)
        // il luogo sullo schermo: a destra o a sinistra di quanto bisogna girarsi (oltre gli 80° resta sul bordo)
        let rel: Double = rotta.map { Rotta.relativa(rilevamento: $0.rilevamento, direzione: bussola.direzione ?? 0) } ?? 0
        let angolo: Double = max(-80, min(80, rel)) * Double.pi / 180
        let bx: Double = W * (0.5 + 0.42 * sin(angolo)), by: Double = H * 0.52
        let ax: Double = W * 0.5, ay: Double = H * 0.98, cx0: Double = W * 0.5, cy0: Double = H * 0.6
        func punto(_ u: Double) -> (x: Double, y: Double) {
            let v: Double = 1 - u
            let x: Double = v * v * ax + 2 * v * u * cx0 + u * u * bx
            let y: Double = v * v * ay + 2 * v * u * cy0 + u * u * by
            return (x, y)
        }
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }

        var luce = gc
        luce.addFilter(.shadow(color: ciano, radius: CGFloat(8 * max(s, 0.5))))
        // le frecce a chevron che scorrono verso il luogo
        for k in 0..<7 {
            let u: Double = (Double(k) + (t * 0.9).truncatingRemainder(dividingBy: 1)) / 7
            if u > 0.96 { continue }
            let p = punto(u), q = punto(min(1, u + 0.02))
            let an: Double = atan2(q.y - p.y, q.x - p.x)
            let lato: Double = 46 * (1 - u * 0.78) * s
            var freccia = Path()
            freccia.move(to: pt(p.x + cos(an + 2.4) * lato, p.y + sin(an + 2.4) * lato * 0.45))
            freccia.addLine(to: pt(p.x, p.y))
            freccia.addLine(to: pt(p.x + cos(an - 2.4) * lato, p.y + sin(an - 2.4) * lato * 0.45))
            var g = luce
            g.opacity = min(1, (1 - u) * 1.4) * (0.55 + 0.45 * sin(t * 4 - Double(k)))
            let spessore: Double = max(2, 9 * (1 - u * 0.8)) * s
            g.stroke(freccia, with: .color(ciano), style: StrokeStyle(lineWidth: CGFloat(spessore), lineCap: .round, lineJoin: .round))
        }
        // il punto del luogo: l'anello che pulsa e l'asta
        let pulsa: Double = (t * 0.8).truncatingRemainder(dividingBy: 1)
        let rx: Double = (18 + pulsa * 40) * s
        var anello = luce
        anello.opacity = 1 - pulsa
        anello.stroke(Path(ellipseIn: CGRect(x: bx - rx, y: by - rx * 0.35, width: rx * 2, height: rx * 0.7)), with: .color(ciano), lineWidth: 2)
        var asta = Path()
        asta.move(to: pt(bx, by))
        asta.addLine(to: pt(bx, by - 70 * s))
        luce.stroke(asta, with: .color(ciano), lineWidth: 2)
        // l'etichetta «STUDIO · 180 m»
        let testo = rotta.map { "\(nome) · \(Rotta.distanza($0.metri))" } ?? nome
        let scritta = gc.resolve(Text(testo).font(.system(size: CGFloat(22 * s), weight: .bold, design: .monospaced)).foregroundStyle(ColoriHUD.chiaro))
        let misura = scritta.measure(in: size)
        let lw: Double = Double(misura.width) + 28 * s, lh: Double = 42 * s
        let ex: Double = min(max(bx, lw / 2 + 4), W - lw / 2 - 4)
        let riquadro = Path(roundedRect: CGRect(x: ex - lw / 2, y: by - 116 * s, width: lw, height: lh), cornerRadius: CGFloat(8 * s))
        gc.fill(riquadro, with: .color(Color(red: 0.02, green: 0.03, blue: 0.035).opacity(0.8)))
        gc.stroke(riquadro, with: .color(ciano), lineWidth: 1.5)
        gc.draw(scritta, at: pt(ex, by - 95 * s), anchor: .center)
        // la bussola in alto: dove guarda l'iPhone
        let nord = bussola.direzione.map { Rotta.bussola($0) } ?? "BUSSOLA…"
        gc.draw(Text(nord).font(.system(size: CGFloat(16 * s), weight: .semibold, design: .monospaced)).foregroundStyle(ciano.opacity(0.85)),
                at: pt(W / 2, 26 * s), anchor: .center)
    }
}
#endif
