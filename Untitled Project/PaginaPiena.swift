#if os(iOS)
import SwiftUI
import UIKit

// MARK: - 26 ott sera (il signore: «nessuna arriva in cima a pagina piena»): tutte le schede di JARVIS a pagina piena, come il mockup
// Salgono dal basso fino in cima (non più il foglio di iOS che si ferma sotto l'ora), si chiudono con «Chiudi» o trascinando giù
// dalla parte alta dello schermo (la fascia dell'ora). Sotto resta JARVIS: scendendo si vede lui, mai nero.

struct PaginaPiena: ViewModifier {
    @Environment(\.dismiss) private var chiudi
    @State private var scesa: CGFloat = 0

    /// L'altezza della fascia in alto (ora, Dynamic Island) dove parte il trascinamento: lì non ci sono tasti delle schede.
    private var finestra: UIWindow? {
        let finestre = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return finestre.first { $0.isKeyWindow } ?? finestre.first
    }
    private var fascia: CGFloat { max(finestra?.safeAreaInsets.top ?? 44, 24) }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fondo.ignoresSafeArea())
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: fascia + 8)
                    .contentShape(Rectangle())
                    .offset(y: -fascia)
                    .gesture(trascina)
            }
            .offset(y: scesa)
            .environment(\.chiudiPagina, { scendiEChiudi(durata: 0.35) })
            .presentationBackground(.clear)                  // sotto si vede JARVIS, non il nero di iOS
    }

    /// 26 ott sera (il signore: «Studio e Social devono andare via come le altre, senza nero»): la scheda scende DA SOLA, ancora
    /// presentata (la pagina web resta nella finestra e continua a disegnarsi), poi iOS la toglie quando è già sotto lo schermo,
    /// senza una seconda animazione. Così iOS non fa mai scendere una pagina web «spenta»: niente nero. La curva è quella del
    /// mockup (.foglio: 0,35 s, cubic-bezier(.2,.8,.2,1)); dopo il trascinamento col dito è più breve, il dito l'ha già portata giù.
    private func scendiEChiudi(durata: Double) {
        let fondo = finestra?.bounds.height ?? 1000
        let curva: Animation = durata > 0.3 ? .timingCurve(0.2, 0.8, 0.2, 1, duration: durata) : .easeOut(duration: durata)
        withAnimation(curva) { scesa = fondo }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(durata * 1000) + 10))
            var t = Transaction()
            t.disablesAnimations = true                      // è già scesa: niente seconda animazione
            withTransaction(t) { chiudi() }
        }
    }

    private var trascina: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in scesa = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 140 || v.predictedEndTranslation.height > 420 {
                    scendiEChiudi(durata: 0.22)
                } else {
                    withAnimation(.spring(duration: 0.3)) { scesa = 0 }
                }
            }
    }
}

/// «Chiudi» di una scheda a pagina piena: scende da sola e poi sparisce (vedi PaginaPiena.scendiEChiudi). Fuori da una pagina piena è nil.
private struct ChiaveChiudiPagina: EnvironmentKey { static let defaultValue: (@MainActor () -> Void)? = nil }
extension EnvironmentValues {
    var chiudiPagina: (@MainActor () -> Void)? {
        get { self[ChiaveChiudiPagina.self] }
        set { self[ChiaveChiudiPagina.self] = newValue }
    }
}

extension View {
    /// Una scheda di JARVIS a pagina piena (vedi PaginaPiena).
    func paginaPiena() -> some View { modifier(PaginaPiena()) }
}
#endif
