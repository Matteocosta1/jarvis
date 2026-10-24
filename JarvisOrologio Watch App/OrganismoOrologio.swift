import SwiftUI
import SceneKit
import WatchKit

// BUILD 22 · B — ORGANISMO sul polso (si apre da Vitals).
/// La stessa persona olografica dell'iPhone, più leggera (meno segmenti, niente nuvola di punti né etichette),
/// che si gira con la corona digitale e gira da sola quando la corona è ferma. Sotto: la prontezza grande
/// e «Sonno · Battito · Passi». Con il polso giù (schermo spento o attenuato) la scena si ferma e non disegna.
struct VistaOrganismoOrologio: View {
    @Environment(\.scenePhase) private var fase
    @Environment(\.isLuminanceReduced) private var attenuato
    @StateObject private var ologramma = OlogrammaOrganismo(leggero: true)
    @State private var dati = DatiOrganismo()
    @State private var corona = 0.0
    @FocusState private var coronaAttiva: Bool        // la corona arriva solo alla vista che ha il fuoco
    @State private var mostrato = false               // come nel mockup e nelle altre schermate della 22: prima 0,9 s di caricamento
    private let ciano = TintaOrologio.ciano
    private let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)

    private var attivo: Bool { fase == .active && !attenuato }

    var body: some View {
        VStack(spacing: 5) {
            Text("ORGANISMO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(ciano)
            ZStack {
                if attivo {
                    SceneView(scene: ologramma.scena, pointOfView: ologramma.camera, options: [.rendersContinuously],
                              preferredFramesPerSecond: 30, antialiasingMode: .none)
                } else {
                    Color.black
                }
            }
            .aspectRatio(160.0 / 128.0, contentMode: .fit)
            .frame(maxWidth: 160, minHeight: 64, maxHeight: 128)
            .focusable()
            .focused($coronaAttiva)
            .focusEffectDisabled()                          // niente cornice verde del fuoco: come nel mockup
            .digitalCrownRotation($corona, from: 0, through: 360, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: false)
            .accessibilityLabel("Ologramma dell'organismo: lo giri con la corona")
            Text(dati.testoProntezza).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                .lineLimit(1)
            Text(dati.rigaPolso).font(.system(size: 9)).foregroundStyle(tenue).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // la corona: gradi del giro; il giro da solo si ferma e riparte dopo 2,6 s di quiete
        .onChange(of: corona) { _, gradi in
            ologramma.tocco(inizio: true)
            ologramma.yaw = 0.65 + Float(gradi) * .pi / 180
            ologramma.tocco(inizio: false)
        }
        .onChange(of: attivo) { _, si in ologramma.pausa(!si) }
        .onDisappear { ologramma.pausa(true) }
        .onAppear { ologramma.pausa(!attivo); coronaAttiva = true }
        .task { await carica() }
        // il caricamento del mockup (apri «organismo»: 0,9 s con «scheda», poi «schedapronta»), come SchermoPolso:
        // prima l'Organismo si apriva di colpo, senza caricamento né suoni, unico tra le schermate del polso
        .overlay {
            if !mostrato {
                ZStack { Color.black.ignoresSafeArea(); CaricamentoOrologio(titolo: "ORGANISMO") }
                    .transition(.opacity)
            }
        }
        .onAppear { if !mostrato { WKInterfaceDevice.current().play(.start); SuoniOrologio.schedaApre() } }
        .task {
            guard !mostrato else { return }
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.success)
            SuoniOrologio.schedaPronta()
            withAnimation(.easeOut(duration: 0.3)) { mostrato = true }
        }
    }

    /// Gli stessi numeri di Vitals: riepilogo di oggi, storico di Salute (31 giorni) e diario dal cervello.
    private func carica() async {
        let oggi = await SaluteOggi.leggi()
        let s = await SaluteStorica.giorni(31)
        let d = await VistaVitalsOrologio.chiama(["vitals": true, "giorni": 7])
        dati = DatiOrganismo.calcola(oggi: oggi, storia: s, diario: d.map { DatiVitals($0, salute: s, giorni: 7) })
        ologramma.aggiorna(dati)
    }
}
