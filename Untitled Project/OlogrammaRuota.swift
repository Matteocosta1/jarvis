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

/// 7 nov sera (il signore, scelta finale: «ruota: MAGLIA»): la ghiera della click wheel fatta di NANOTECNOLOGIA, come il mockup
/// v274 (JARVIS Fasce › RUOTA › MAGLIA). Un nido d'ape di tre file appena dentro le icone, che quando la ruota si accende cresce dal
/// punto in alto verso il basso sui due lati come metallo liquido (0,5 s), con il fronte che brilla; spenta, si ritira verso l'alto
/// (0,35 s). Gira col dito insieme alla corona; vicino all'icona in alto le celle si accendono e, mentre gira, un'onda di luce le
/// percorre. Dentro, il numero di ogni icona; sotto l'icona in alto il contatore «07 / 27 · 247°».
/// Disegnata una volta sola e girata (rotationEffect): a 120 Hz cambiano solo la rotazione e le maschere.
struct GhieraRuota: View {
    @ObservedObject var ruota: RuotaCorona
    /// L'angolo di partenza di ogni icona (radianti), nell'ordine della corona.
    let angoli: [Double]
    /// Il raggio dell'anello delle icone (160).
    let raggio: CGFloat
    @State private var fronte: Double = 0          // quanto è cresciuta la maglia dall'alto (0 → 1,06 π per lato)

    var body: some View {
        let vivo = ruota.vivo
        let rg = raggio - 27
        ZStack {
            MagliaDisegno(angoli: angoli, raggio: rg, forte: false)
                .rotationEffect(.radians(ruota.giro))
            MagliaDisegno(angoli: angoli, raggio: rg, forte: true)
                .rotationEffect(.radians(ruota.giro))
                .mask {
                    ZStack {
                        GhieraCima()
                        // l'onda di luce che segue il giro (accesa solo mentre gira: la lente)
                        OndaMaglia(angolo: -Double.pi / 2 + 1.4 * ruota.giro).opacity(ruota.lente)
                    }
                }
            FronteMaglia(fronte: fronte, raggio: rg - 3)
                .stroke(Color.ciano.opacity(0.35), style: StrokeStyle(lineWidth: 18, lineCap: .round))   // il tratto c'è solo mentre cresce o si ritira
                .blur(radius: 3)
            contatore
                .offset(y: -raggio + 62)
                .opacity(vivo ? 1 : 0)
        }
        .mask(SettoreMaglia(fronte: fronte))
        .animation(.easeOut(duration: 0.15), value: vivo)
        .onChange(of: vivo, initial: true) { _, v in
            withAnimation(v ? .easeOut(duration: 0.5) : .easeIn(duration: 0.35)) { fronte = v ? 1.06 * .pi : 0 }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// «07 / 27 · 247°»: il numero dell'icona in alto, quante sono, e di quanti gradi è girata la ruota.
    private var contatore: some View {
        let n = angoli.count, k = max(0, ruota.scelta)
        let gradi = Int((((-ruota.giro * 180 / .pi).truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360).rounded()) % 360
        let testo = String(format: "%02d / %d · %03d°", k + 1, n, gradi)
        return Text(testo)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(red: 191 / 255, green: 246 / 255, blue: 1))
            .shadow(color: Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.7), radius: 2)
            .fixedSize()
    }
}

/// Il nido d'ape a ruota ferma (giro 0): tre file di 64 celle esagonali (raggi −10, −3, +4 attorno all'anello), sfalsate di mezza
/// cella, e i numeri delle icone più dentro. `forte`: la copia accesa (si vede in cima e sull'onda). Valori del mockup MAGLIA.
struct MagliaDisegno: View {
    let angoli: [Double]
    let raggio: CGFloat
    let forte: Bool

    var body: some View {
        Canvas { gc, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1), chiaro = Color(red: 191 / 255, green: 246 / 255, blue: 1)
            var g = gc
            g.addFilter(.shadow(color: ciano.opacity(0.6), radius: 1.5))
            var celle = Path()
            let file: [CGFloat] = [raggio - 10, raggio - 3, raggio + 4]
            for (j, rf) in file.enumerated() {
                for k in 0..<64 {
                    let th = (Double(k) + Double(j % 2) * 0.5) / 64 * 2 * .pi
                    let cx = c.x + rf * CGFloat(cos(th)), cy = c.y + rf * CGFloat(sin(th))
                    for v in 0..<6 {
                        let a = th + Double(v) * .pi / 3
                        let p = CGPoint(x: cx + 3.6 * CGFloat(cos(a)), y: cy + 3.6 * CGFloat(sin(a)))
                        if v == 0 { celle.move(to: p) } else { celle.addLine(to: p) }
                    }
                    celle.closeSubpath()
                }
            }
            let l: Double = forte ? 0.62 : 0.12                 // la luce della cella: in cima 0,12 + 0,5 (mockup)
            g.fill(celle, with: .color(ciano.opacity(0.05 + 0.3 * l)))
            g.stroke(celle, with: .color(ciano.opacity(0.25 + 0.6 * l)), lineWidth: 0.7)
            for (k, a) in angoli.enumerated() {
                let rr = raggio - 22
                var t = g
                t.translateBy(x: c.x + rr * CGFloat(cos(a)), y: c.y + rr * CGFloat(sin(a)))
                t.rotate(by: .radians(a + .pi / 2))
                t.draw(Text(String(format: "%02d", k + 1)).font(.system(size: 6, weight: .semibold, design: .monospaced))
                        .foregroundStyle(chiaro.opacity(forte ? 1 : 0.45)), at: .zero)
            }
        }
    }
}

/// Dove la maglia è già cresciuta: lo spicchio attorno alla cima, largo `fronte` per lato (si anima).
struct SettoreMaglia: Shape {
    var fronte: Double
    var animatableData: Double {
        get { fronte }
        set { fronte = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fronte > 0.001 else { return p }
        let c = CGPoint(x: rect.midX, y: rect.midY), r = max(rect.width, rect.height)
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: .radians(-Double.pi / 2 - fronte), endAngle: .radians(-Double.pi / 2 + fronte), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Il fronte che brilla mentre la maglia cresce o si ritira: due tratti corti ai due lati, sulla maglia.
struct FronteMaglia: Shape {
    var fronte: Double
    let raggio: CGFloat
    var animatableData: Double {
        get { fronte }
        set { fronte = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fronte > 0.001, fronte < 1.06 * .pi - 0.001 else { return p }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for lato in [-1.0, 1.0] {
            let a = -Double.pi / 2 + lato * fronte
            p.move(to: CGPoint(x: c.x + raggio * CGFloat(cos(a - 0.05)), y: c.y + raggio * CGFloat(sin(a - 0.05))))
            p.addArc(center: c, radius: raggio, startAngle: .radians(a - 0.05), endAngle: .radians(a + 0.05), clockwise: false)
        }
        return p
    }
}

/// L'onda di luce sulla maglia mentre gira: una campana stretta attorno ad `angolo` (fissa sullo schermo, si sposta col giro).
struct OndaMaglia: View {
    let angolo: Double
    var body: some View {
        let passi = 72
        let fermate: [Gradient.Stop] = (0...passi).map { i in
            let u = Double(i) / Double(passi), a = u * 2 * .pi
            var d = abs(a - ((angolo.truncatingRemainder(dividingBy: 2 * .pi)) + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi))
            d = min(d, 2 * .pi - d)
            return Gradient.Stop(color: .black.opacity(exp(-pow(d / 0.35, 2))), location: u)
        }
        AngularGradient(stops: fermate, center: .center, startAngle: .zero, endAngle: .degrees(360))
    }
}

/// La luce in cima alla ghiera: piena sull'icona in alto e sfuma ai lati (come exp(−(d/0,35)²) del mockup), ferma mentre la
/// ghiera gira sotto.
struct GhieraCima: View {
    var body: some View {
        // da −π (sinistra) a +π, con la cima (−π/2) piena: 73 punti della campana
        let passi = 72
        let fermate: [Gradient.Stop] = (0...passi).map { i in
            let u = Double(i) / Double(passi), a = u * 2 * .pi                 // 0 = destra, in senso orario (SwiftUI)
            var d = abs(a - 1.5 * .pi)                                          // la cima è a 270° in senso orario
            d = min(d, 2 * .pi - d)
            return Gradient.Stop(color: .black.opacity(exp(-pow(d / 0.35, 2))), location: u)
        }
        AngularGradient(stops: fermate, center: .center, startAngle: .zero, endAngle: .degrees(360))
    }
}

/// Il reattore si vela mentre l'ologramma è acceso, e non prende i tocchi (li prende l'ologramma).
/// 5 nov (il signore: «il reattore deve essere davvero in secondo piano, molto trasparente e meno luminoso: la ghiera deve
/// prendere la scena»), come il mockup v259 (.velato: opacità 0,06, luminosità 0,5, saturazione 0,6, scala 0,86): sul fondo
/// scuro opacità 0,06 a metà luminosità si vede come opacità 0,03, senza filtri da ricalcolare a ogni fotogramma.
struct VeloRuota: ViewModifier {
    @ObservedObject var ruota: RuotaCorona
    func body(content: Content) -> some View {
        content
            .opacity(ruota.vivo ? 0.015 : 1)              // 7 nov (il signore: «ancora più trasparente ed in secondo piano»): 0,03 → 0,015
            .scaleEffect(ruota.vivo ? 0.78 : 1)           // e più indietro: 0,86 → 0,78 (mockup v274: opacità 0,03, scala 0,78)
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: ruota.vivo)
            .allowsHitTesting(!ruota.vivo)
    }
}

/// L'ologramma dell'icona in alto, nel reattore (mockup approvato). Mentre gira: l'anteprima tenue, che cambia di scatto con un
/// guizzo. Ferma: si crea alla Tony Stark sul tono «olo» — 0–90 ms il proiettore si accende (lampo alla base, colonna di luce che
/// sale, poi il cono); 0–470 ms la GRIGLIA (11.0 (6), al posto dei puntini: spigoli di costruzione, gabbia di luce, piano di
/// stampa con la sua griglia); 90–380 ms l'icona si disegna dal basso dietro il piano di stampa, col disco di scansione;
/// 120–420 ms il nome si decodifica; 150–420 ms gli anelli giroscopici si aprono; 100–320 ms le staffe attorno al nome.
/// Toccato: apre la sezione.
struct OlogrammaRuota: View {
    @ObservedObject var ruota: RuotaCorona
    /// Nome, gruppo e simbolo di ogni icona della corona, nell'ordine.
    let voci: [(nome: String, gruppo: String, icona: String)]
    /// Le sezioni già aperte (la scritta APERTA al posto del gruppo).
    var aperte: Set<String> = []
    let apri: (Int) -> Void

    @State private var cambiataDa = Date.distantPast

    private static let glifi = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|▪▫░▒")
    private static let chiaro = Color(red: 0.56, green: 0.94, blue: 1.0)      // #8ff0ff
    private static let bianco = Color(red: 0.75, green: 0.96, blue: 1.0)      // #bff6ff

    var body: some View {
        let k = ruota.scelta
        let vivo = ruota.vivo && k >= 0 && k < voci.count
        let etichetta: String = vivo ? "Apri \(voci[k].nome)" : ""
        TimelineView(.animation(minimumInterval: nil, paused: !vivo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // ms dalla creazione, a 1,5× (5 nov sera, il signore: «l'animazione è lenta, troppo lenta» e poi «un minimo più lenta,
            // che si veda il target come prima, ma fluida»; mockup v266): GRIGLIA in 0,31 s, luce piena in 0,23 s, nome in 0,2 s
            let T = ruota.creataDa.map { ctx.date.timeIntervalSince($0) * 1500 } ?? 1e9
            // 5 nov (il signore: «il primo ologramma deve essere poco luminoso mentre ruoto, poi si illumina quando è fermo»),
            // come il mockup v266: mentre gira icona al 20%, nome al 25%, gruppo spento, proiettore al 26%; ferma, pieni e più chiari
            let luce = T < 1e8 ? OlogrammaRuota.ease(T / 350) : 0
            ZStack {
                if vivo {
                    Canvas { gc, _ in disegna(gc, t: t, T: T, luce: luce) }
                        .frame(width: 200, height: 200)
                    icona(voci[k].icona, T: T, t: t, luce: luce)
                    nome(voci[k].nome, T: T, luce: luce)
                    Text(aperte.contains(voci[k].nome) ? "APERTA" : voci[k].gruppo)
                        .font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color.tenue)
                        .opacity(luce)
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
    }

    /// Il guizzo quando cambia l'icona in alto (0,2 s): un tremolio di luce.
    private func guizzo(_ ora: Date) -> Double {
        let s = ora.timeIntervalSince(cambiataDa)
        guard s < 0.2 else { return 1 }
        return 0.55 + 0.45 * abs(sin(s * 60))
    }

    private static func ease(_ p: Double) -> Double { let q = max(0, min(1, p)); return 1 - pow(1 - q, 3) }

    @ViewBuilder private func icona(_ simbolo: String, T: Double, t: Double, luce: Double) -> some View {
        let creata = T < 1e8
        // l'icona si disegna dal basso in alto mentre il disco di scansione la percorre (90–380 ms)
        let rivela = creata ? OlogrammaRuota.ease((T - 90) / 290) : 1
        Group {
            // v266: Profiler grande come le altre (era 20 × 15)
            if simbolo == "profiler" { IconaProfiler().scaleEffect(2) } else if simbolo == "satellite" { IconaSatellite(lato: 40) } else { Image(systemName: simbolo) }
        }
        .font(.system(size: 40, weight: .light))
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(OlogrammaRuota.chiaro)
        .brightness(0.25 * luce)                                                   // 7 nov (il signore: «scelte ancora più luminose»): 0,25 (era 0,12)
        .frame(width: 64, height: 64)
        .mask {
            VStack(spacing: 0) {
                Color.clear
                LinearGradient(colors: [.black.opacity(0.4), .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64 * rivela)
            }
            .frame(height: 64)
        }
        .mask { RigheIcona() }                                                     // 5 nov sera: le righe come nel mockup
        .shadow(color: .ciano.opacity(0.45 + 0.55 * luce), radius: 3 + 5 * luce)   // mentre gira: alone corto e tenue; scelta, pieno
        .shadow(color: .ciano.opacity(0.7 * luce), radius: 14 * luce)              // 7 nov: scelta, un secondo alone più largo (mockup v274)
        .opacity(0.3 + 0.7 * luce)                                                 // 7 nov (il signore: «un pochino più luminose»): girando 30% (era 20%)
        .offset(x: creata && T > 380 && T < 520 ? sin(T * 0.25) * 0.8 : 0)      // due tremolii, poi resta sospesa
        .position(x: 100, y: 82 + sin(t * 1.6) * 1.5)                              // sospesa: respira appena
    }

    private func nome(_ n: String, T: Double, luce: Double) -> some View {
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
            .shadow(color: .ciano.opacity(0.8 * luce), radius: 4)                    // mentre gira: senza alone
            .opacity(0.35 + 0.65 * luce)                                              // 7 nov: girando 35% (era 25%)
            .lineLimit(1)
            .fixedSize()
            .position(x: 100, y: 130)
    }

    /// Il proiettore e tutto ciò che non è l'icona (coordinate del mockup, centro 100,100).
    private func disegna(_ gc: GraphicsContext, t: Double, T: Double, luce: Double) {
        var g = gc
        g.translateBy(x: 100, y: 100)
        let creata = T < 1e8, nuova = T < 600
        let forza = 0.32 + 0.68 * luce                               // 7 nov: mentre gira il proiettore al 32% (era 26%)
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
        // 2) 11.0 (6): la GRIGLIA, come nasce l'ologramma (al posto dei puntini); a riposo qualche granello nel cono
        if nuova {
            NascitaGriglia.disegna(g, T)
        } else {
            for i in 0..<6 {
                let p = (t * 0.35 + Double(i) / 6).truncatingRemainder(dividingBy: 1)
                let x = sin(Double(i) * 12.9 + t) * 30 * p, y = 70 - p * 120
                g.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)), with: .color(OlogrammaRuota.chiaro.opacity(0.5 * sin(p * .pi))))
            }
        }
        // 3) il disco di scansione: alla creazione sale con il piano di stampa; poi passa lento
        let sale = nuova && T < 380
        let ys = sale ? NascitaGriglia.piano(T) : -54 + (t * 40).truncatingRemainder(dividingBy: 72)
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
