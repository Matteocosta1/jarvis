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
            // 8 nov (foto del signore 03:33: «quella selezionata non deve rimanere un pochino sotto l'altra, si deve vedere tutta»):
            // più è ingrandita dalla lente, più sta sopra; la scelta sopra a tutte
            .zIndex(scelta ? 100 : s > 1.001 ? 10 * s : 0)
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
            .foregroundStyle(Color(red: 1, green: 214 / 255, blue: 191 / 255))
            .shadow(color: Color(red: 1, green: 106 / 255, blue: 19 / 255).opacity(0.7), radius: 2)
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
            let ciano = Color(red: 1, green: 106 / 255, blue: 19 / 255), chiaro = Color(red: 1, green: 214 / 255, blue: 191 / 255)
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

/// L'ologramma dell'icona in alto, nel reattore. Dal 13.7 ACCENSIONE (Accensione.swift, scelta del signore): niente proiettore,
/// l'icona grande (104 punti) galleggia con la sua luce; mentre la ruota gira è un'anteprima tenue che cambia di scatto con un
/// guizzo; ferma, i suoi pezzi arrivano con la scia e si posano, poi si accende tremolando e si rivela dall'alto (sul tono «olo»);
/// il nome si decodifica (120–420 ms) e le staffe si aprono attorno al nome. Toccato: apre la sezione.
struct OlogrammaRuota: View {
    @ObservedObject var ruota: RuotaCorona
    /// Nome, gruppo e simbolo di ogni icona della corona, nell'ordine.
    let voci: [(nome: String, gruppo: String, icona: String)]
    /// Le sezioni già aperte (la scritta APERTA al posto del gruppo).
    var aperte: Set<String> = []
    let apri: (Int) -> Void

    @State private var cambiataDa = Date.distantPast

    private static let glifi = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|▪▫░▒")
    private static let bianco = Color(red: 1, green: 215 / 255, blue: 191 / 255)      // #bff6ff

    var body: some View {
        let k = ruota.scelta
        let vivo = ruota.vivo && k >= 0 && k < voci.count
        let etichetta: String = vivo ? "Apri \(voci[k].nome)" : ""
        TimelineView(.animation(minimumInterval: nil, paused: !vivo)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // ms dalla creazione, a 1,5× come tutta la ruota
            let T = ruota.creataDa.map { ctx.date.timeIntervalSince($0) * 1500 } ?? 1e9
            let ferma = T < 1e8
            let luce = ferma ? OlogrammaRuota.ease(T / 350) : 0
            ZStack {
                if vivo {
                    let simbolo = voci[k].icona
                    let pezzi = Accensione.pezzi("iphone." + simbolo, icona: OlogrammaRuota.simbolo(simbolo, lato: 26))
                    let scarto = Accensione.scarto("iphone." + simbolo)                     // 13.8: centrata sul disegno vero
                    Canvas { gc, size in
                        Accensione.disegna(gc, centro: CGPoint(x: size.width / 2, y: size.height / 2), T: T, t: t, forza: 0.32 + 0.68 * luce,
                                           nata: ferma, lungNome: voci[k].nome.count, pezzi: pezzi)
                    }
                    .frame(width: 300, height: 300)
                    .position(x: 100, y: 82)
                    IconaAccensione(T: T, ferma: ferma, lato: Accensione.lato) { OlogrammaRuota.simbolo(simbolo, lato: Accensione.lato) }
                        // 13.8 (il signore: «l'icona non vada su e giù»): ferma; spostata sul centro del suo disegno
                        .position(x: 100 - scarto.width * Accensione.lato, y: 82 - scarto.height * Accensione.lato)
                    nome(voci[k].nome, T: T, luce: luce)
                    Text(aperte.contains(voci[k].nome) ? "APERTA" : voci[k].gruppo)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced)).tracking(2.6)
                        .foregroundStyle(Color.tenue)
                        .opacity(luce)
                        .position(x: 100, y: 175)
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
        // 13.7 (debug, i 120 Hz): i pezzi di ogni icona si preparano prima, a avvio finito e uno alla volta. Prima si calcolavano
        // la prima volta che l'icona arrivava in alto, mentre lui girava la ruota: un piccolo scatto alla prima passata
        .task {
            try? await Task.sleep(for: .seconds(20))
            for v in voci {
                guard !Task.isCancelled else { return }
                if !ruota.vivo { _ = Accensione.pezzi("iphone." + v.icona, icona: OlogrammaRuota.simbolo(v.icona, lato: 26)) }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    /// Il simbolo di una voce, grande `lato` punti (le proporzioni di prima: il simbolo è i 5/8 del riquadro).
    @ViewBuilder static func simbolo(_ s: String, lato: Double) -> some View {
        if s == "profiler" { IconaProfiler().scaleEffect(2 * lato / 64).frame(width: lato, height: lato) }
        else if s == "satellite" { IconaSatellite(lato: lato * 40 / 64) }
        else { SimboloFriday(nome: s, lato: lato * 40 / 64).font(.system(size: lato * 40 / 64, weight: .light)).symbolRenderingMode(.monochrome) }   // FRIDAY: le icone del mockup
    }

    /// Il guizzo quando cambia l'icona in alto (0,2 s): un tremolio di luce.
    private func guizzo(_ ora: Date) -> Double {
        let s = ora.timeIntervalSince(cambiataDa)
        guard s < 0.2 else { return 1 }
        return 0.55 + 0.45 * abs(sin(s * 60))
    }

    private static func ease(_ p: Double) -> Double { let q = max(0, min(1, p)); return 1 - pow(1 - q, 3) }

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
            .font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(5.5)
            .foregroundStyle(OlogrammaRuota.bianco)
            .shadow(color: .ciano.opacity(0.8 * luce), radius: 4)
            .opacity(0.35 + 0.65 * luce)
            .lineLimit(1)
            .fixedSize()
            .position(x: 100, y: 154)
    }
}
