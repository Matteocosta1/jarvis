import Foundation
import SwiftUI
import Combine

// MARK: - MARK XI · la click wheel: le viste che leggono la ruota (icone, archi, reattore velato, ologramma)
// Solo queste seguono il giro a 120 Hz; la schermata di JARVIS non si ridisegna a ogni fotogramma.

/// Il posto di un'icona sulla corona: il suo angolo più il giro, la lente mentre gira e l'anello di selezione con l'ologramma acceso.
struct PostoRuota: ViewModifier {
    @ObservedObject var ruota: RuotaCorona
    let indice: Int
    let base: Double
    let raggio: CGFloat
    let passo: Double

    func body(content: Content) -> some View {
        let a = base + ruota.giro
        let s = ruota.scala(base: base, passo: passo)
        let scelta = ruota.selezionata(indice)
        content
            .overlay {
                Circle()
                    .fill(Color.ciano.opacity(scelta ? 0.25 : 0))
                    .overlay(Circle().stroke(Color.ciano.opacity(scelta ? 0.95 : 0), lineWidth: 1.3))
                    .shadow(color: .ciano.opacity(scelta ? 0.7 : 0), radius: 6)
                    .frame(width: 38, height: 38)
                    .allowsHitTesting(false)
            }
            .scaleEffect(s)
            .offset(x: raggio * CGFloat(cos(a)), y: raggio * CGFloat(sin(a)))
            .zIndex(s > 1.02 ? 3 : 0)
    }
}

/// Gli archi e i nomi dei gruppi, che girano con le icone.
struct ArchiRuota: View {
    @ObservedObject var ruota: RuotaCorona
    let gruppi: [String]          // il gruppo di ogni icona, nell'ordine della corona
    let angoli: [Double]
    let accese: Int
    let raggio: CGFloat

    var body: some View {
        Canvas { gc, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let g = ruota.giro
            var k = 0
            while k < gruppi.count && k < angoli.count {
                var fine = k
                while fine + 1 < gruppi.count && gruppi[fine + 1] == gruppi[k] { fine += 1 }
                let acceso = fine < accese
                let da = angoli[k] + g - 0.09, a = angoli[fine] + g + 0.09
                var arco = Path()
                arco.addArc(center: c, radius: raggio, startAngle: .radians(da), endAngle: .radians(a), clockwise: false)
                gc.stroke(arco, with: .color(Color.ciano.opacity(acceso ? 0.35 : 0.08)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                let medio = (angoli[k] + angoli[fine]) / 2 + g
                // il nome corre lungo l'arco, appena fuori dalle icone, sempre leggibile da sinistra a destra
                var rotazione = medio + .pi / 2
                if cos(rotazione) < 0 { rotazione += .pi }
                var testo = gc
                testo.translateBy(x: c.x + (raggio + 27) * cos(medio), y: c.y + (raggio + 27) * sin(medio))
                testo.rotate(by: .radians(rotazione))
                testo.draw(Text(gruppi[k]).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.tenue.opacity(acceso ? 1 : 0)), at: .zero)
                k = fine + 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Il reattore si vela mentre l'ologramma è acceso, e non prende i tocchi (li prende l'ologramma).
struct VeloRuota: ViewModifier {
    @ObservedObject var ruota: RuotaCorona
    func body(content: Content) -> some View {
        content
            .opacity(ruota.vivo ? 0.12 : 1)
            .animation(.easeOut(duration: 0.2), value: ruota.vivo)
            .allowsHitTesting(!ruota.vivo)
    }
}

/// L'ologramma dell'icona in alto, nel reattore (mockup approvato). Mentre gira: l'anteprima tenue, che cambia di scatto con un
/// guizzo. Ferma: si crea alla Tony Stark sul tono «olo» — 0–90 ms il proiettore si accende (lampo alla base, colonna di luce che
/// sale, poi il cono); 40–330 ms le particelle salgono dalla base e si posano sull'icona; 90–380 ms l'icona si disegna dal basso
/// mentre il disco di scansione la percorre; 120–420 ms il nome si decodifica; 150–420 ms gli anelli giroscopici si aprono;
/// 100–320 ms le staffe attorno al nome. Toccato: apre la sezione.
struct OlogrammaRuota: View {
    @ObservedObject var ruota: RuotaCorona
    /// Nome, gruppo e simbolo di ogni icona della corona, nell'ordine.
    let voci: [(nome: String, gruppo: String, icona: String)]
    /// Le sezioni già aperte (la scritta APERTA al posto del gruppo).
    var aperte: Set<String> = []
    let apri: (Int) -> Void

    @State private var cambiataDa = Date.distantPast
    @State private var particelle: [Particella] = []

    private struct Particella { let x0: Double, x: Double, y: Double, da: Double, dur: Double }
    private static let glifi = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|▪▫░▒")
    private static let chiaro = Color(red: 0.56, green: 0.94, blue: 1.0)      // #8ff0ff
    private static let bianco = Color(red: 0.75, green: 0.96, blue: 1.0)      // #bff6ff

    var body: some View {
        let k = ruota.scelta
        let vivo = ruota.vivo && k >= 0 && k < voci.count
        let etichetta: String = vivo ? "Apri \(voci[k].nome)" : ""
        TimelineView(.animation(minimumInterval: nil, paused: !vivo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let T = ruota.creataDa.map { ctx.date.timeIntervalSince($0) * 1000 } ?? 1e9     // ms dalla creazione
            ZStack {
                if vivo {
                    Canvas { gc, _ in disegna(gc, t: t, T: T) }
                        .frame(width: 200, height: 200)
                    icona(voci[k].icona, T: T, t: t)
                    nome(voci[k].nome, T: T)
                    Text(aperte.contains(voci[k].nome) ? "APERTA" : voci[k].gruppo)
                        .font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color.tenue)
                        .position(x: 100, y: 147)
                }
            }
            .frame(width: 200, height: 200)
            .opacity(vivo ? guizzo(ctx.date) : 0)
        }
        .scaleEffect(1.2)                                         // nel quadrato del reattore (240)
        .frame(width: 240, height: 240)
        .contentShape(Circle())
        .onTapGesture { if vivo { apri(k) } }
        .allowsHitTesting(vivo)
        .accessibilityHidden(!vivo)
        .accessibilityLabel(etichetta)
        .onChange(of: ruota.scelta) { cambiataDa = Date() }
        .onChange(of: ruota.creataDa) { _, d in if d != nil { particelle = OlogrammaRuota.nuoveParticelle() } }
    }

    /// Il guizzo quando cambia l'icona in alto (0,2 s): un tremolio di luce.
    private func guizzo(_ ora: Date) -> Double {
        let s = ora.timeIntervalSince(cambiataDa)
        guard s < 0.2 else { return 1 }
        return 0.55 + 0.45 * abs(sin(s * 60))
    }

    private static func nuoveParticelle() -> [Particella] {
        (0..<40).map { _ in
            Particella(x0: Double.random(in: -22...22), x: Double.random(in: -28...28), y: Double.random(in: -46...10),
                       da: 40 + Double.random(in: 0...110), dur: 150 + Double.random(in: 0...80))
        }
    }

    private static func ease(_ p: Double) -> Double { let q = max(0, min(1, p)); return 1 - pow(1 - q, 3) }

    @ViewBuilder private func icona(_ simbolo: String, T: Double, t: Double) -> some View {
        let creata = T < 1e8
        // l'icona si disegna dal basso in alto mentre il disco di scansione la percorre (90–380 ms)
        let rivela = creata ? OlogrammaRuota.ease((T - 90) / 290) : 1
        Group {
            if simbolo == "profiler" { IconaProfiler() } else if simbolo == "satellite" { IconaSatellite(lato: 40) } else { Image(systemName: simbolo) }
        }
        .font(.system(size: 40, weight: .light))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(OlogrammaRuota.chiaro)
        .frame(width: 64, height: 64)
        .mask {
            VStack(spacing: 0) {
                Color.clear
                LinearGradient(colors: [.black.opacity(0.4), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64 * rivela)
            }
            .frame(height: 64)
        }
        .shadow(color: .ciano.opacity(0.8), radius: 6)
        .offset(x: creata && T > 380 && T < 520 ? sin(T * 0.25) * 0.8 : 0)      // due tremolii, poi resta sospesa
        .position(x: 100, y: 82 + sin(t * 1.6) * 1.5)                              // sospesa: respira appena
    }

    private func nome(_ n: String, T: Double) -> some View {
        let v = n.uppercased()
        var q = v
        if T < 1e8 {
            let p = max(0, min(1, (T - 120) / 300))
            if p < 1 {
                q = String(v.enumerated().map { i, c in Double(i) < p * Double(v.count) ? c : (OlogrammaRuota.glifi.randomElement() ?? c) })
            }
        }
        return Text(q)
            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(4)
            .foregroundStyle(OlogrammaRuota.bianco)
            .shadow(color: .ciano.opacity(0.8), radius: 4)
            .lineLimit(1)
            .fixedSize()
            .position(x: 100, y: 130)
    }

    /// Il proiettore e tutto ciò che non è l'icona (coordinate del mockup, centro 100,100).
    private func disegna(_ gc: GraphicsContext, t: Double, T: Double) {
        var g = gc
        g.translateBy(x: 100, y: 100)
        let creata = T < 1e8, nuova = T < 600
        let forza = creata ? 1.0 : 0.45
        g.opacity = forza
        let ciano = Color.ciano
        func ellisse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
            Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        }
        func arcoEllisse(_ cy: Double, _ rx: Double, _ ry: Double, _ da: Double, _ lung: Double) -> Path {
            var p = Path()
            let passi = 16
            for i in 0...passi {
                let a = da + lung * Double(i) / Double(passi)
                let pt = CGPoint(x: rx * cos(a), y: cy + ry * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            return p
        }
        // 1) il proiettore: la base, il lampo che si allarga, la colonna di luce che sale, poi il cono
        let lampo = max(0, 1 - T / 260), colonna = OlogrammaRuota.ease(T / 90), cono = creata ? OlogrammaRuota.ease((T - 60) / 160) : 1
        g.stroke(ellisse(0, 70, 30, 6), with: .color(ciano.opacity(0.55)), lineWidth: 1)
        g.stroke(arcoEllisse(70, 30, 6, t * 2.4, 1.6), with: .color(ciano.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        g.stroke(arcoEllisse(70, 18, 3.5, -t * 3.1, 1.1), with: .color(ciano.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        if lampo > 0 {
            g.stroke(ellisse(0, 70, 30 + (1 - lampo) * 46, 6 + (1 - lampo) * 9), with: .color(OlogrammaRuota.bianco.opacity(lampo)), lineWidth: 2)
            g.fill(ellisse(0, 70, 14 * lampo + 4, 3 * lampo + 1), with: .color(Color.white.opacity(lampo * 0.9)))
        }
        if creata && T < 260 {
            let cima = 70 - 125 * colonna, a = max(0, 1 - (T - 90) / 170)
            var col = Path(); col.move(to: CGPoint(x: 0, y: 70)); col.addLine(to: CGPoint(x: 0, y: cima))
            g.stroke(col, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.95 * a), .clear]),
                                                startPoint: CGPoint(x: 0, y: 70), endPoint: CGPoint(x: 0, y: cima)), lineWidth: 2.2)
        }
        var fascio = Path()
        fascio.move(to: CGPoint(x: -24 * cono, y: 70)); fascio.addLine(to: CGPoint(x: 24 * cono, y: 70))
        fascio.addLine(to: CGPoint(x: 56 * cono, y: -50)); fascio.addLine(to: CGPoint(x: -56 * cono, y: -50)); fascio.closeSubpath()
        g.fill(fascio, with: .linearGradient(Gradient(colors: [ciano.opacity((0.26 + lampo * 0.3) * cono), ciano.opacity(0)]),
                                             startPoint: CGPoint(x: 0, y: 70), endPoint: CGPoint(x: 0, y: -50)))
        // 2) le particelle che salgono e si posano sull'icona (con la scia); a riposo qualche granello nel cono
        if nuova {
            for q in particelle {
                let p = (T - q.da) / q.dur
                guard p >= 0, p <= 1.4 else { continue }
                let e = OlogrammaRuota.ease(min(1, p)), e2 = OlogrammaRuota.ease(min(1, p - 0.12)), a = p > 1 ? 1 - (p - 1) / 0.4 : 1
                let x = q.x0 + (q.x - q.x0) * e, y = 70 + (q.y - 70) * e
                var scia = Path(); scia.move(to: CGPoint(x: q.x0 + (q.x - q.x0) * e2, y: 70 + (q.y - 70) * e2)); scia.addLine(to: CGPoint(x: x, y: y))
                g.stroke(scia, with: .color(OlogrammaRuota.chiaro.opacity(0.5 * a)), lineWidth: 1)
                g.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)), with: .color(Color.white.opacity(a)))
            }
        } else {
            for i in 0..<6 {
                let p = (t * 0.35 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
                let x = sin(Double(i) * 12.9 + t) * 30 * p, y = 70 - p * 120
                g.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(OlogrammaRuota.chiaro.opacity(0.5 * sin(p * .pi))))
            }
        }
        // 3) il disco di scansione: alla creazione sale una volta sull'icona; poi passa lento
        let sale = nuova && T < 380
        let ys = sale ? 18 - 72 * OlogrammaRuota.ease((T - 60) / 300) : -54 + (t * 40).truncatingRemainder(dividingBy: 72)
        let forzaDisco = sale ? 0.95 : 0.35
        if !nuova || T > 60 {
            g.stroke(ellisse(0, ys, 42, 5), with: .color(OlogrammaRuota.bianco.opacity(forzaDisco)), lineWidth: 1)
            g.fill(Path(CGRect(x: -42, y: ys - 8, width: 84, height: 16)),
                   with: .linearGradient(Gradient(colors: [ciano.opacity(0), ciano.opacity(forzaDisco * 0.25), ciano.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: ys - 8), endPoint: CGPoint(x: 0, y: ys + 8)))
            var tacche = Path()
            tacche.move(to: CGPoint(x: -50, y: ys)); tacche.addLine(to: CGPoint(x: -45, y: ys))
            tacche.move(to: CGPoint(x: 45, y: ys)); tacche.addLine(to: CGPoint(x: 50, y: ys))
            g.stroke(tacche, with: .color(ciano.opacity(forzaDisco)), lineWidth: 1)
        }
        // 4) gli anelli giroscopici attorno all'icona (solo ferma), che si aprono alla creazione; le staffe attorno al nome
        if creata {
            let sc = OlogrammaRuota.ease((T - 150) / 270)
            if sc > 0 {
                for (inclina, vel, fase, rx, ry) in [(0.14, 0.9, 0.0, 48.0, 9.0), (-0.1, -0.7, 1.7, 42.0, 7.0)] as [(Double, Double, Double, Double, Double)] {
                    var a = g
                    a.translateBy(x: 0, y: -18)
                    a.rotate(by: .radians(inclina))
                    a.scaleBy(x: sc, y: sc)
                    a.stroke(ellisse(0, 0, rx, ry), with: .color(ciano.opacity(0.18)), lineWidth: 1)
                    for q in 0..<2 {
                        let ang = t * vel + fase + Double(q) * .pi
                        let davanti = sin(ang + 0.35) > 0
                        a.stroke(arcoEllisse(0, rx, ry, ang, 0.7), with: .color(OlogrammaRuota.chiaro.opacity(davanti ? 0.8 : 0.3)), lineWidth: 1.4)
                    }
                }
            }
            let sb = OlogrammaRuota.ease((T - 100) / 220)
            let lungo = Double(voci.indices.contains(ruota.scelta) ? voci[ruota.scelta].nome.count : 6)
            let w = 12 + (lungo * 10.6 / 2 + 6) * sb
            var staffe = Path()
            for sx in [-1.0, 1.0] {
                staffe.move(to: CGPoint(x: sx * (w - 4), y: 24)); staffe.addLine(to: CGPoint(x: sx * w, y: 24))
                staffe.addLine(to: CGPoint(x: sx * w, y: 36)); staffe.addLine(to: CGPoint(x: sx * (w - 4), y: 36))
            }
            g.stroke(staffe, with: .color(ciano.opacity(0.8 * sb)), lineWidth: 1)
        }
    }
}
