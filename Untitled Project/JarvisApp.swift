import SwiftUI

@main
struct JarvisApp: App {
    @UIApplicationDelegateAdaptor(Notifiche.self) private var notifiche   // push: briefing del mattino e avvisi
    @StateObject private var jarvis = Jarvis()
    @Environment(\.scenePhase) private var fase

    init() {
        // difetto 7 (controllo del 25 ott): «risponde a qualsiasi frase» parte acceso anche sul Mac, perché il Mac rispondeva già a
        // qualsiasi frase (l'interruttore non contava). Una volta sola, sul Mac, si torna al valore di partenza: un «spento» rimasto
        // da quando l'interruttore non faceva niente non deve cambiare all'improvviso come risponde il Mac. Da qui in poi conta davvero.
        if ProcessInfo.processInfo.isiOSAppOnMac, !UserDefaults.standard.bool(forKey: "ascoltoSempreMac25ott") {
            UserDefaults.standard.removeObject(forKey: "ascoltoSempre")
            UserDefaults.standard.set(true, forKey: "ascoltoSempreMac25ott")
        }
        UserDefaults.standard.register(defaults: ["ascoltaApertura": true, "voceCloud": true, "interruzioneVocale": true, "suoni": true, "richiamo": true,
                                                  "ascoltoSempre": true])
        PonteTelefono.condiviso.avvia()        // Apple Watch: gli consegna la parola d'ordine
        TocchiSchermo.prepara()                // 26 ott sera: i tocchi sul vetro non sono battiti di mani
        IsolaJarvis.prepara()                  // 26 ott sera: i tasti della Dynamic Island e l'isola della PIOGGIA ad app chiusa
        CodaArchivio.condivisa.avvia()         // 13 nov: le copie per l'Archivio rimaste in coda ripartono all'avvio
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
