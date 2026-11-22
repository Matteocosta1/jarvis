import Foundation
import SwiftUI
import Combine

/// MARK XI · l'ologramma dell'icona al centro della barra, nel reattore del polso. Dal 13.7 nasce come sull'iPhone: ACCENSIONE
/// (Accensione.swift, mockup «JARVIS Approvato»): niente proiettore né cono; l'icona grande galleggia con la sua luce, quando la
/// ruota si ferma i suoi pezzi arrivano con la scia, poi l'icona vera si accende tremolando e si rivela dall'alto; le staffe si
/// aprono attorno al nome. Al polso con le scritte del polso (nome 9,5 punti, gruppo 6,3) e dentro il reattore velato, che si
/// stringe a 0,78 (come il mockup, dove l'ologramma sta nel reattore). Toccato, apre la sezione.
struct OlogrammaPolso<Icona: View>: View {
    @ObservedObject var ruota: RuotaPolso
    let nomi: [String]
    let gruppi: [String]
    /// L'icona `k`, grande `lato` punti.
    @ViewBuilder let icona: (Int, Double) -> Icona
    let apri: (Int) -> Void

    @State private var cambiataDa = Date.distantPast
    private static var glifi: [Character] { Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|") }
    private let ciano = TintaOrologio.ciano
    private let bianco = Color(red: 0.75, green: 0.96, blue: 1.0)

    var body: some View {
        let k = ruota.scelta
        let vivo = ruota.vivo && nomi.indices.contains(k)
        let etichetta: String = vivo ? "Apri \(nomi[k])" : ""
        TimelineView(.animation(minimumInterval: nil, paused: !vivo)) { ctx in    // 4 nov: al massimo dell'orologio
            let t = ctx.date.timeIntervalSinceReferenceDate
            // v266 (5 nov sera, come l'iPhone e il mockup): la nascita a 1,5× e, mentre gira, tutto tenue; ferma, si accende
            let T = ruota.creataDa.map { ctx.date.timeIntervalSince($0) * 1500 } ?? 1e9
            let ferma = T < 1e8
            let luce = ferma ? OlogrammaPolso.ease(T / 350) : 0
            ZStack {
                if vivo {
                    let pezzi = Accensione.pezzi("polso.\(k).\(nomi[k])", icona: icona(k, 26))
                    Canvas { gc, size in
                        Accensione.disegna(gc, centro: CGPoint(x: size.width / 2, y: size.height / 2), T: T, t: t, forza: 0.32 + 0.68 * luce,
                                           nata: ferma, lungNome: nomi[k].count, pezzi: pezzi)
                    }
                    .frame(width: 300, height: 300)
                    .position(x: 100, y: 82)
                    IconaAccensione(T: T, ferma: ferma, lato: Accensione.lato) { icona(k, Accensione.lato) }
                        .position(x: 100, y: 82 + sin(t * 1.6) * 1.5)                          // sospesa: respira appena
                    Text(nome(nomi[k], T: T))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(1.9)
                        .foregroundStyle(bianco)
                        .shadow(color: ciano.opacity(0.8 * luce), radius: 4)
                        .opacity(0.35 + 0.65 * luce)                                   // girando 35% come l'iPhone
                        .lineLimit(1).fixedSize()
                        .position(x: 100, y: 130)
                    Text(gruppi.indices.contains(k) ? gruppi[k] : "")
                        .font(.system(size: 6.3, weight: .semibold, design: .monospaced)).tracking(2.6)
                        .foregroundStyle(Color(red: 0.30, green: 0.40, blue: 0.44))
                        .opacity(luce)
                        .lineLimit(1).fixedSize()
                        .position(x: 100, y: 145.5)
                }
            }
            .frame(width: 200, height: 200)
            .opacity(vivo ? guizzo(ctx.date) : 0)
        }
        // nel reattore velato, che si stringe insieme a lui (VeloPolso: 0,78 in 0,3 s, la stessa curva)
        .scaleEffect(vivo ? 0.78 : 1)
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.3), value: vivo)
        .frame(width: 200, height: 200)
        .contentShape(Circle())
        .onTapGesture { if vivo { apri(k) } }
        .allowsHitTesting(vivo)
        .accessibilityHidden(!vivo)
        .accessibilityLabel(etichetta)
        .onChange(of: ruota.scelta) { cambiataDa = Date() }
        // 13.7 (debug): i pezzi di ogni icona si preparano prima, a avvio finito e uno alla volta (non mentre gira la ruota)
        .task {
            try? await Task.sleep(for: .seconds(20))
            for k in nomi.indices {
                guard !Task.isCancelled else { return }
                if !ruota.vivo { _ = Accensione.pezzi("polso.\(k).\(nomi[k])", icona: icona(k, 26)) }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    /// Il guizzo quando cambia l'icona in alto (0,2 s): un tremolio di luce.
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
}
