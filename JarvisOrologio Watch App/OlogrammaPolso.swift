import Foundation
import SwiftUI
import Combine

/// MARK XI · l'ologramma dell'icona al centro della barra, nel reattore del polso: lo stesso disegno e gli stessi tempi dell'iPhone
/// (proiettore, cono, GRIGLIA di costruzione (11.0 (6), al posto delle particelle), disco di scansione, anelli giroscopici, staffe,
/// nome che si decodifica), in piccolo (0,6) e con il nome più grande (15 punti) per il polso, come nel mockup. Toccato, apre la
/// sezione.
struct OlogrammaPolso<Icona: View>: View {
    @ObservedObject var ruota: RuotaPolso
    let nomi: [String]
    let gruppi: [String]
    @ViewBuilder let icona: (Int) -> Icona
    let apri: (Int) -> Void

    @State private var cambiataDa = Date.distantPast
    private static var glifi: [Character] { Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|") }
    private let ciano = TintaOrologio.ciano
    private let chiaro = Color(red: 0.56, green: 0.94, blue: 1.0)
    private let bianco = Color(red: 0.75, green: 0.96, blue: 1.0)

    var body: some View {
        let k = ruota.scelta
        let vivo = ruota.vivo && nomi.indices.contains(k)
        let etichetta: String = vivo ? "Apri \(nomi[k])" : ""
        TimelineView(.animation(minimumInterval: nil, paused: !vivo)) { ctx in    // 4 nov: al massimo dell'orologio, 60 Hz (prima 30)
            let t = ctx.date.timeIntervalSinceReferenceDate
            // v266 (5 nov sera, come l'iPhone e il mockup): la nascita a 1,5× e, mentre gira, tutto tenue; ferma, si accende
            let T = ruota.creataDa.map { ctx.date.timeIntervalSince($0) * 1500 } ?? 1e9
            let luce = T < 1e8 ? OlogrammaPolso.ease(T / 350) : 0
            ZStack {
                if vivo {
                    Canvas { gc, _ in disegna(gc, t: t, T: T) }
                        .frame(width: 200, height: 200)
                    icona(k)
                        .foregroundStyle(chiaro)
                        .brightness(0.12 * luce)
                        .frame(width: 64, height: 64)
                        .mask {
                            VStack(spacing: 0) {
                                Color.clear
                                Color.black.frame(height: 64 * (T < 1e8 ? OlogrammaPolso.ease((T - 90) / 290) : 1))
                            }
                            .frame(height: 64)
                        }
                        .mask { RigheIcona() }                                  // 5 nov sera: le righe come nel mockup
                        .shadow(color: ciano.opacity(0.45 + 0.55 * luce), radius: 3 + 5 * luce)
                        .opacity(0.2 + 0.8 * luce)                                     // girando 20%, scelta piena
                        .position(x: 100, y: 82 + sin(t * 1.6) * 1.5)
                    Text(nome(nomi[k], T: T))
                        .font(.system(size: 15, weight: .bold, design: .monospaced)).tracking(3)
                        .foregroundStyle(bianco)
                        .shadow(color: ciano.opacity(0.8 * luce), radius: 4)
                        .opacity(0.25 + 0.75 * luce)
                        .lineLimit(1).fixedSize()
                        .position(x: 100, y: 130)
                    Text(gruppi.indices.contains(k) ? gruppi[k] : "")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))
                        .opacity(luce)
                        .position(x: 100, y: 148)
                }
            }
            .frame(width: 200, height: 200)
            .opacity(vivo ? guizzo(ctx.date) : 0)
        }
        .scaleEffect(0.6)
        .frame(width: 120, height: 120)
        .contentShape(Circle())
        .onTapGesture { if vivo { apri(k) } }
        .allowsHitTesting(vivo)
        .accessibilityHidden(!vivo)
        .accessibilityLabel(etichetta)
        .onChange(of: ruota.scelta) { cambiataDa = Date() }
    }

    private func guizzo(_ ora: Date) -> Double {
        let s = ora.timeIntervalSince(cambiataDa)
        return s < 0.2 ? 0.55 + 0.45 * abs(sin(s * 60)) : 1
    }

    private static func ease(_ p: Double) -> Double { let q = max(0, min(1, p)); return 1 - pow(1 - q, 3) }

    private func nome(_ n: String, T: Double) -> String {
        let v = n.uppercased()
        guard T < 1e8 else { return v }
        let p = max(0, min(1, (T - 120) / 300))
        guard p < 1 else { return v }
        let g = OlogrammaPolso.glifi
        return String(v.enumerated().map { i, c in Double(i) < p * Double(v.count) ? c : (g.randomElement() ?? c) })
    }

    private func disegna(_ gc: GraphicsContext, t: Double, T: Double) {
        var g = gc
        g.translateBy(x: 100, y: 100)
        let creata = T < 1e8, nuova = T < 600
        g.opacity = creata ? 1 : 0.45
        func ellisse(_ cy: Double, _ rx: Double, _ ry: Double) -> Path { Path(ellipseIn: CGRect(x: -rx, y: cy - ry, width: rx * 2, height: ry * 2)) }
        func arco(_ cy: Double, _ rx: Double, _ ry: Double, _ da: Double, _ lung: Double) -> Path {
            var p = Path()
            for i in 0...16 {
                let a = da + lung * Double(i) / 16
                let pt = CGPoint(x: rx * cos(a), y: cy + ry * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            return p
        }
        let lampo = max(0, 1 - T / 260), colonna = OlogrammaPolso.ease(T / 90), cono = creata ? OlogrammaPolso.ease((T - 60) / 160) : 1
        g.stroke(ellisse(70, 30, 6), with: .color(ciano.opacity(0.55)), lineWidth: 1)
        g.stroke(arco(70, 30, 6, t * 2.4, 1.6), with: .color(ciano.opacity(0.9)), lineWidth: 1.6)
        g.stroke(arco(70, 18, 3.5, -t * 3.1, 1.1), with: .color(ciano.opacity(0.9)), lineWidth: 1.6)
        if lampo > 0 {
            g.stroke(ellisse(70, 30 + (1 - lampo) * 46, 6 + (1 - lampo) * 9), with: .color(bianco.opacity(lampo)), lineWidth: 2)
            g.fill(ellisse(70, 14 * lampo + 4, 3 * lampo + 1), with: .color(Color.white.opacity(lampo * 0.9)))
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
        if nuova { NascitaGriglia.disegna(g, T) }                         // 11.0 (6): la GRIGLIA, come sull'iPhone
        let sale = nuova && T < 380
        let ys = sale ? NascitaGriglia.piano(T) : -54 + (t * 40).truncatingRemainder(dividingBy: 72)
        if !nuova || T > 60 {
            g.stroke(ellisse(ys, 42, 5), with: .color(bianco.opacity(sale ? 0.95 : 0.35)), lineWidth: 1)
        }
        if creata {
            let sc = OlogrammaPolso.ease((T - 150) / 270)
            if sc > 0 {
                for (inclina, vel, fase, rx, ry) in [(0.14, 0.9, 0.0, 48.0, 9.0), (-0.1, -0.7, 1.7, 42.0, 7.0)] as [(Double, Double, Double, Double, Double)] {
                    var a = g
                    a.translateBy(x: 0, y: -18)
                    a.rotate(by: .radians(inclina))
                    a.scaleBy(x: sc, y: sc)
                    a.stroke(ellisse(0, rx, ry), with: .color(ciano.opacity(0.18)), lineWidth: 1)
                    for q in 0..<2 {
                        let ang = t * vel + fase + Double(q) * .pi
                        a.stroke(arco(0, rx, ry, ang, 0.7), with: .color(chiaro.opacity(sin(ang + 0.35) > 0 ? 0.8 : 0.3)), lineWidth: 1.4)
                    }
                }
            }
            let sb = OlogrammaPolso.ease((T - 100) / 220)
            let lungo = Double(nomi.indices.contains(ruota.scelta) ? nomi[ruota.scelta].count : 6)
            let w = 12 + (lungo * 12 / 2 + 6) * sb
            var staffe = Path()
            for sx in [-1.0, 1.0] {
                staffe.move(to: CGPoint(x: sx * (w - 4), y: 22)); staffe.addLine(to: CGPoint(x: sx * w, y: 22))
                staffe.addLine(to: CGPoint(x: sx * w, y: 38)); staffe.addLine(to: CGPoint(x: sx * (w - 4), y: 38))
            }
            g.stroke(staffe, with: .color(ciano.opacity(0.8 * sb)), lineWidth: 1)
        }
    }
}
