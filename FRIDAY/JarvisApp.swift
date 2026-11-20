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
        TocchiSchermo.prepara()                // 26 ott sera: i tocchi sul vetro non sono battiti di mani
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
                Posizione.risveglia()             // il GPS si scalda: la prima domanda non aspetta
            } else {
                Posizione.dormi()
            }
        }
    }
}

/// I colori di FRIDAY (mockup approvato): `ciano` resta il nome della tinta principale di JARVIS, ma in FRIDAY è l'arancio.
extension Color {
    static let ciano = Color(red: 1, green: 106 / 255, blue: 19 / 255)          // #ff6a13 arancio
    static let ciano2 = Color(red: 224 / 255, green: 86 / 255, blue: 12 / 255)  // #e0560c bruciato
    static let fondo = Color(red: 20 / 255, green: 12 / 255, blue: 8 / 255)     // #140c08
    static let tenue = Color(red: 154 / 255, green: 125 / 255, blue: 111 / 255) // #9a7d6f
    static let testo = Color(red: 246 / 255, green: 236 / 255, blue: 230 / 255) // #f6ece6
    static let rossoF = Color(red: 1, green: 90 / 255, blue: 90 / 255)          // #ff5a5a: quando pensa, allarmi
    static let verdeF = Color(red: 209 / 255, green: 127 / 255, blue: 79 / 255) // #4fd1b4: ok
    static let petrolio = Color(red: 143 / 255, green: 72 / 255, blue: 31 / 255) // #1f8f7a accento
    static let fondo2 = Color(red: 36 / 255, green: 21 / 255, blue: 16 / 255)   // #241510
    static let pagina = Color(red: 11 / 255, green: 7 / 255, blue: 5 / 255)     // #0b0705
}
