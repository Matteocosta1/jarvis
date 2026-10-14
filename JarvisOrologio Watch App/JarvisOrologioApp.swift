import SwiftUI

@main
struct JarvisOrologioApp: App {
    @StateObject private var jarvis = JarvisOrologio()

    init() {
        PonteOrologio.condiviso.avvia()     // riceve la parola d'ordine dall'iPhone
        Cuore.condiviso.avvia()             // battiti e allarme
    }

    var body: some Scene {
        WindowGroup {
            VistaOrologio()
                .environmentObject(jarvis)
                .onOpenURL { url in
                    // jarvis://ascolta arriva dalla complicazione sul quadrante
                    if url.host == "ascolta" { jarvis.ascoltaDaComplicazione() }
                }
        }
    }
}
