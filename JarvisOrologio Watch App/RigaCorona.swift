import Foundation
import SwiftUI
import Combine

/// MARK XI · al polso (deciso dal signore il 3 nov): le righe che scorrono di lato (le ore del Meteo, le foto nella chat) vanno col
/// dito come sempre e, toccate, con la corona: il contorno ciano dice che la corona ora è loro, un elemento per scatto (con lo
/// scatto della corona). Toccato un altro punto della pagina, il contorno si spegne e la corona torna alla pagina.
struct RigaCorona<Contenuto: View>: View {
    /// Quanti elementi ci sono (ognuno con `.id(k)`, k da 0).
    let quanti: Int
    @ViewBuilder let contenuto: () -> Contenuto

    @FocusState private var fuoco: Bool
    @State private var valore = 0.0
    @State private var riquadro: CGRect = .zero

    /// La pagina avvisa di ogni tocco (coordinate globali): fuori dalla riga, la corona torna alla pagina.
    static var toccoPagina: Notification.Name { Notification.Name("JarvisPolsoToccoPagina") }
    /// La riga ha lasciato la corona (4 nov: nella schermata principale la riprendono le icone, `CoronaBarra`).
    static var lascia: Notification.Name { Notification.Name("JarvisPolsoRigaLascia") }

    var body: some View {
        ScrollViewReader { lettore in
            ScrollView(.horizontal, showsIndicators: false) { contenuto() }
                // il contorno sta appena fuori dalla riga: la pagina resta impaginata come prima
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(TintaOrologio.ciano.opacity(fuoco ? 1 : 0), lineWidth: 1.5)
                        .shadow(color: TintaOrologio.ciano.opacity(fuoco ? 0.35 : 0), radius: 5)
                        .padding(-4)
                }
                .animation(.easeOut(duration: 0.2), value: fuoco)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riquadro = $0 }
                .focusable()
                .focused($fuoco)
                .focusEffectDisabled()
                .digitalCrownRotation($valore, from: 0, through: Double(max(0, quanti - 1)), by: 1,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .onChange(of: valore) { _, v in
                    let k = Int(v.rounded())
                    withAnimation(.easeOut(duration: 0.16)) { lettore.scrollTo(k, anchor: .leading) }
                }
                .onTapGesture { fuoco = true }
                .onReceive(NotificationCenter.default.publisher(for: RigaCorona<Contenuto>.toccoPagina)) { n in
                    guard fuoco, let p = n.userInfo?["p"] as? CGPoint, !riquadro.contains(p) else { return }
                    fuoco = false
                    NotificationCenter.default.post(name: RigaCorona<Contenuto>.lascia, object: nil)
                }
        }
    }
}

extension View {
    /// La pagina del polso avvisa le righe di ogni tocco, così toccando fuori da una riga la corona torna alla pagina.
    func avvisaRighe() -> some View {
        simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global).onEnded { v in
                NotificationCenter.default.post(name: Notification.Name("JarvisPolsoToccoPagina"), object: nil, userInfo: ["p": v.location])
            }
        )
    }
}
