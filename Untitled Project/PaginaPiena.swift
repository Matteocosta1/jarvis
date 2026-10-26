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
            .presentationBackground(.clear)                  // sotto si vede JARVIS, non il nero di iOS
    }

    private var trascina: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in scesa = max(0, v.translation.height) }
            .onEnded { v in
                if v.translation.height > 140 || v.predictedEndTranslation.height > 420 {
                    let fondo = finestra?.bounds.height ?? 1000
                    withAnimation(.easeOut(duration: 0.22)) { scesa = fondo }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(230))
                        var t = Transaction()
                        t.disablesAnimations = true                      // è già scesa: niente seconda animazione
                        withTransaction(t) { chiudi() }
                    }
                } else {
                    withAnimation(.spring(duration: 0.3)) { scesa = 0 }
                }
            }
    }
}

extension View {
    /// Una scheda di JARVIS a pagina piena (vedi PaginaPiena).
    func paginaPiena() -> some View { modifier(PaginaPiena()) }
}
#endif
