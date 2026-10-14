import SwiftUI

@main
struct JarvisApp: App {
    @UIApplicationDelegateAdaptor(Notifiche.self) private var notifiche   // push: briefing del mattino e avvisi
    @StateObject private var jarvis = Jarvis()
    @Environment(\.scenePhase) private var fase

    init() {
        UserDefaults.standard.register(defaults: ["ascoltaApertura": true, "voceCloud": true, "interruzioneVocale": true, "suoni": true])
        PonteTelefono.condiviso.avvia()        // Apple Watch: gli consegna la parola d'ordine
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(jarvis)
                .preferredColorScheme(.dark)
        }
        .onChange(of: fase) { _, nuova in
            if nuova == .active {
                PonteTelefono.condiviso.invia()   // parola d'ordine sempre aggiornata sull'orologio
                Posizione.risveglia()             // il GPS si scalda: la prima domanda non aspetta
            } else {
                Posizione.dormi()
            }
        }
    }
}

extension Color {
    static let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
    static let ciano2 = Color(red: 0.04, green: 0.65, blue: 0.79)
    static let fondo = Color(red: 0.02, green: 0.03, blue: 0.04)
    static let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)
}
