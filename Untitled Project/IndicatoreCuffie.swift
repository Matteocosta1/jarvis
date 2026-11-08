#if os(iOS)
import Foundation
import SwiftUI
import Combine
import AVFoundation

// MARK: - CUFFIE (8 nov notte, il signore: «c'è un modo di riconoscere quando inserisco le cuffie? … io ho quelle col filo, magari
// viene scritto EarPods… scritta piccola con logo cuffie, rimane per il tempo che sono collegate ma non deve essere invadente; quando
// le scollego per 1/2 secondi dice scollegate e sparisce… accanto a MARK XI»). Come il mockup v285: sulla riga di MARK XI, dopo un
// punto, stesso carattere (10, spaziatura 3) e stesso grigio. Lo dice iOS: a ogni cambio dell'uscita audio si guarda dove va il suono. Col filo (EarPods) «HEADPHONES» col logo delle cuffie, AirPods
// «AIRPODS», altre cuffie Bluetooth «CUFFIE». Tolte: «SCOLLEGATE» per 1,5 s, poi sparisce (dissolvenza 0,3 s).

struct IndicatoreCuffie: View {
    @State private var nome: String?          // le cuffie collegate adesso (nil: nessuna)
    @State private var simbolo = "headphones"
    @State private var scollegate = false
    @State private var giro = 0

    var body: some View {
        let testo = scollegate ? "SCOLLEGATE" : nome
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("·").font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.leading, 3).padding(.trailing, 2)
            // 04:56 «il logo sullo stesso livello della scritta»: i simboli di Apple, a pari carattere e sulla stessa linea, stanno
            // centrati sulle maiuscole; .small li porta all'altezza delle maiuscole (come il mockup: logo 9, centrato)
            Image(systemName: simbolo).font(.system(size: 10, weight: .medium)).imageScale(.small)
            Text(testo ?? "").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(3).lineLimit(1)
        }
        .foregroundStyle(Color.tenue.opacity(scollegate ? 0.6 : 1))
        .opacity(testo == nil ? 0 : 1)
        .frame(width: testo == nil ? 0 : nil, alignment: .leading)
        .clipped()
        .animation(.easeOut(duration: 0.3), value: testo)
        .fixedSize()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(testo.map { scollegate ? "Cuffie scollegate" : "\($0.capitalized) collegate" } ?? "")
        .accessibilityHidden(testo == nil)
        .onAppear { leggi(cambio: false) }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: RunLoop.main)) { _ in
            leggi(cambio: true)
        }
    }

    /// Dove va il suono adesso. `cambio`: è arrivato un cambio dell'uscita (all'apertura non si dice «scollegate»).
    private func leggi(cambio: Bool) {
        let cuffie: [AVAudioSession.Port] = [.headphones, .usbAudio, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP]
        if let u = AVAudioSession.sharedInstance().currentRoute.outputs.first(where: { cuffie.contains($0.portType) }) {
            let n = u.portName.lowercased()
            let bluetooth = [AVAudioSession.Port.bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains(u.portType)
            if n.contains("airpods") { nome = "AIRPODS"; simbolo = "airpods" }
            else if !bluetooth { nome = "HEADPHONES"; simbolo = "headphones" }         // col filo (le sue EarPods): 04:56 «scriviamo headphones», 04:57 il logo delle cuffie
            else { nome = "CUFFIE"; simbolo = "headphones" }
            scollegate = false
            giro += 1
            return
        }
        guard cambio, nome != nil else { nome = nil; return }
        nome = nil
        scollegate = true
        giro += 1
        let mio = giro
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if giro == mio { scollegate = false }
        }
    }
}
#endif
