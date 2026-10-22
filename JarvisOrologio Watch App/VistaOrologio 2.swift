import SwiftUI
import UIKit
import WatchKit
import Charts
import AVFoundation

/// I suoni del signore anche al polso: gli stessi file dell'iPhone, trascinati nel target dell'orologio.
/// «tick» (o «tocco») al tocco di un'icona, «avvio» all'inizio dell'animazione, «scheda» e «schedapronta» nelle sezioni.
/// Se mancano, silenzio e solo vibrazione.
@MainActor
enum SuoniOrologio {
    private static var lettori: [AVAudioPlayer] = []
    private static var cache: [String: URL?] = [:]
    private static func file(_ nome: String) -> URL? {
        if let u = cache[nome] { return u }
        let u = ["m4a", "mp3", "wav", "caf"].lazy.compactMap { Bundle.main.url(forResource: nome, withExtension: $0) }.first
        cache[nome] = u
        return u
    }
    static func tick() { suona(file("tick") ?? file("tocco"), volume: 1.0) }          // click: 100%
    /// Musica d'avvio con una pulsazione per ognuna delle 19 icone del polso («avvioorologio»); se manca, quella dell'iPhone.
    /// `fra`: la musica parte fra tanti secondi, al campione esatto (play(atTime:) sull'orologio dell'audio).
    static func avvio(fra: TimeInterval = 0) {                           // 100%
        if let p = lettoreAvvio {
            lettoreAvvio = nil
            if fra > 0 { p.play(atTime: p.deviceCurrentTime + fra) } else { p.play() }
            lettori.append(p); return
        }
        suona(file("avvioorologio") ?? file("avvio"), volume: 1.0)
    }
    /// L'avvio si carica prima: quando parte, parte all'istante (le icone sono agganciate alla musica).
    static func preparaAvvio() {
        guard let url = file("avvioorologio") ?? file("avvio"), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)            // l'audio è dell'app prima che suoni: la corona lo regola
        p.volume = 1.0
        p.prepareToPlay()
        lettoreAvvio = p
    }
    private static var lettoreAvvio: AVAudioPlayer?
    /// Conferme (Shazam e le altre): solo la vibrazione. Il suono «pronto» è tolto (20 ott, su richiesta).
    static func pronto() {}
    /// Spunte verdi «Fatto» (promesse, spesa, ricordi): il suono «pronto» resta, 100%.
    static func fatto() { suona(file("pronto"), volume: 1.0) }
    /// Click delle icone in alto (Ricordi, Cronologia): «clicktesta», 50%.
    static func clickTesta() { suona(file("clicktesta") ?? file("tick"), volume: 1.0) }
    /// La conversazione si svuota: «chatsvuota», 70%.
    static func chatSvuota() { suona(file("chatsvuota"), volume: 1.0) }
    /// La conversazione si ricarica all'avvio: «chatcarica», 70%.
    static func chatCarica() { suona(file("chatcarica"), volume: 0.7) }
    /// Apertura delle sezioni senza fotocamera (Bea, Spesa): «apertura», 70%; «schedaPronta» lo sfuma.
    static func apertura() {
        guard let url = file("apertura"), let p = try? AVAudioPlayer(contentsOf: url) else { schedaApre(); return }
        if !MicOrologio.aperto { try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default) }   // col microfono dell'attesa acceso l'audio resta com'è
        p.volume = 1.0
        lettoreScheda?.stop()
        lettoreScheda = p
        MicOrologio.ignora(per: p.duration)
        p.play()
    }
    /// Una sezione si apre (caricamento) e quando è pronta: «scheda» e «schedapronta», come sull'iPhone.
    static func schedaApre() {
        guard let url = file("scheda"), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        if !MicOrologio.aperto { try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default) }   // col microfono dell'attesa acceso l'audio resta com'è
        p.volume = 1.0                                                    // schede: 100%
        lettoreScheda?.stop()
        lettoreScheda = p
        MicOrologio.ignora(per: p.duration)
        p.play()
    }
    static func schedaPronta() {
        if let p = lettoreScheda, p.isPlaying { p.setVolume(0, fadeDuration: 0.18) }
        suona(file("schedapronta"), volume: 1.0)
    }
    private static var lettoreScheda: AVAudioPlayer?
    private static func suona(_ url: URL?, volume: Float) {
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return }
        if !MicOrologio.aperto { try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default) }   // col microfono dell'attesa acceso l'audio resta com'è
        p.volume = volume
        lettori.removeAll { !$0.isPlaying }
        lettori.append(p)
        MicOrologio.ignora(per: p.duration)
        p.play()
    }
}

/// Schermata dell'orologio: il reattore, il campo per dettare e la risposta di JARVIS.
struct VistaOrologio: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.scenePhase) private var scena
    @ObservedObject private var cuore = Cuore.condiviso
    @ObservedObject private var sentinella = SentinellaOrologio.condiviso
    @State private var mostraSentinella = false
    @State private var scheda: Reparto?                  // la sezione aperta (Diario, Sonno, Meteo…)
    @State private var dettato = ""
    @State private var chiediPulizia = false
    @State private var mostraVitals = false
    @State private var accese = 0                        // quante icone si sono già accese all'avvio
    @State private var acceso = false                    // sequenza di avvio: reattore e icone si accendono in fila
    @State private var titolo = "AVVIO SISTEMI"
    @State private var iconaAttiva: Int?                 // scorciatoia in corso: pulsa finché JARVIS non ha finito
    @State private var chatDa: Date?                      // la conversazione si decodifica all'avvio (come sull'iPhone)
    @State private var svuotaDa: Date?                    // la conversazione si ritira verso sinistra quando si pulisce
    @State private var barraInFondo = false                // avvio: la barra parte dall'ultima icona (Archivio)
    @State private var scorriA: Int?                       // avvio: l'icona che sta per accendersi, che la barra porta sul bordo sinistro
    @State private var passoBarra = 0.15                   // quanto dura ogni scorrimento (il tempo fino al colpo dopo)
    @AppStorage("vibrazioni") private var vibrazioni = true   // al posto dei suoni dell'iPhone: tocchi sul polso

    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)

    var body: some View {
        NavigationStack {
            principale
                .navigationDestination(isPresented: $mostraVitals) { VistaVitalsOrologio() }
                .navigationDestination(isPresented: $mostraSentinella) { VistaSentinellaOrologio() }
                .navigationDestination(item: $scheda) { r in paginaScheda(r) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // Ricordi: la seconda memoria (macchina, spesa, promesse, ultime cose segnate)
                        NavigationLink { VistaRicordiOrologio() } label: {
                            Image(systemName: "brain.head.profile").foregroundStyle(ciano)
                        }
                        .simultaneousGesture(TapGesture().onEnded { SuoniOrologio.clickTesta() })
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { VistaCronologia() } label: {
                            Image(systemName: "text.bubble")
                        }
                        .simultaneousGesture(TapGesture().onEnded { SuoniOrologio.clickTesta() })
                    }
                }
        }
        .overlay { if cuore.conto != nil { allarme } }
        // Sentinella: «Perimetro violato, Sir» a tutto schermo, ovunque si trovi nell'app
        .fullScreenCover(item: $sentinella.allarme) { a in VistaAllarmeOrologio(allarme: a) }
        .confirmationDialog("Pulire la conversazione? Memoria e note restano.", isPresented: $chiediPulizia) {
            Button("Pulisci", role: .destructive) { svuotaChat() }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: jarvis.svuotaRichiesto) { _, chiesto in
            guard chiesto else { return }
            jarvis.svuotaRichiesto = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.45))   // la Cronologia ha finito di chiudersi: la chat si vede mentre si ritira
                chiediPulizia = true
            }
        }
        .onAppear {
            jarvis.controllaCollegamento()
            PosizioneOrologio.risveglia()            // il GPS si scalda subito: la domanda non lo aspetta
            accendi()
        }
        .onChange(of: scena) { _, fase in
            if fase == .active { PosizioneOrologio.risveglia() }
            else if fase == .background { PosizioneOrologio.dormi(); jarvis.fermaPassivo() }
        }
        // comando vocale: «apri il meteo», «fammi vedere la spesa»
        .onChange(of: jarvis.repartoRichiesto) { _, r in
            guard let r else { return }
            jarvis.repartoRichiesto = nil
            apri(r)
        }
        .onChange(of: jarvis.fase) { vecchia, nuova in
            // vibrazioni alla Stark: risposta in arrivo e risposta finita
            if vecchia == .elaboro && nuova == .parlo { vibra(.directionUp) }
            if vecchia == .parlo && nuova == .attesa { vibra(.success) }
            if nuova == .attesa { iconaAttiva = nil }
        }
    }

    /// Apre una sezione dal tocco o dalla voce; se ce n'è una aperta, prima torna indietro.
    private func apri(_ r: Reparto) {
        mostraVitals = false
        mostraSentinella = false
        scheda = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            switch r {
            case .vitals: mostraVitals = true
            case .sentinella: mostraSentinella = true
            case .confidente: jarvis.chiedi("Modalità confidente. Ho bisogno di parlarti di una cosa.")
            case .interprete: jarvis.chiedi("Fammi da interprete: ti dirò una frase e la lingua, tu traducila e dimmela ad alta voce.")
            case .diario, .sonno, .cuore, .briefing, .meteo, .email, .spesa, .shazam, .serata, .ricordi, .github, .supabase, .archivio, .bea: scheda = r
            case .pulisci: svuotaChat()                        // «Jarvis, pulisci»: come il cestino
            default: jarvis.stato = "\(r.rawValue.capitalized): questa sezione vive sull'iPhone, Sir."
            }
        }
    }

    @ViewBuilder private func paginaScheda(_ r: Reparto) -> some View {
        switch r {
        case .diario: VistaDiarioOrologio()
        case .sonno: VistaSonnoOrologio()
        case .cuore: VistaCuore().aperturaOrologio("Cuore")
        case .briefing: VistaBriefingOrologio()
        case .meteo: VistaMeteoOrologio()
        case .email: VistaPostaOrologio()
        case .spesa: VistaSpesaOrologio()
        case .shazam: VistaShazamOrologio()
        case .serata: VistaSerataOrologio()
        case .ricordi: VistaRicordiOrologio().aperturaOrologio("Ricordi")
        case .github: VistaGitHubOrologio()
        case .supabase: VistaSupabaseOrologio()
        case .archivio: VistaArchivioOrologio()
        case .bea: VistaBeaOrologio().aperturaOrologio("Bea")
        default: EmptyView()
        }
    }

    private func vibra(_ tipo: WKHapticType) {
        guard vibrazioni else { return }
        WKInterfaceDevice.current().play(tipo)
    }

    /// Sequenza di avvio: vibrazione, reattore che sboccia, icone in fila, «SISTEMI IN LINEA».
    /// Pulisci: domanda e risposta si ritirano verso sinistra, poi la conversazione si cancella (come il cestino dell'iPhone).
    private func svuotaChat() {
        guard !jarvis.risposta.isEmpty || !jarvis.domanda.isEmpty else {
            if !jarvis.storia.isEmpty { SuoniOrologio.chatSvuota(); vibra(.click) }
            jarvis.cancellaConversazione(); return
        }
        jarvis.ferma()
        SuoniOrologio.chatSvuota()
        vibra(.click)
        chatDa = nil
        svuotaDa = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.38))                 // come sull'iPhone: righe che si ritirano, barra da 100 a 0, poi pulito
            jarvis.cancellaConversazione()
            svuotaDa = nil
        }
    }

    private func accendi() {
        guard !acceso else { return }
        vibra(.start)
        Task { @MainActor in
            let v = AvvioOrologio.velocita
            SuoniOrologio.preparaAvvio()
            barraInFondo = true                                        // la barra parte dall'ultima icona
            try? await Task.sleep(for: .seconds(AvvioOrologio.attesaApertura))   // finita l'animazione d'apertura del Watch
            withAnimation(.spring(duration: 0.36 / v, bounce: 0.35)) { acceso = true }   // il reattore è pieno prima della prima icona
            try? await Task.sleep(for: .seconds(0.4 / v))
            // al polso le icone si accendono al contrario: da Archivio a Briefing, la barra scorre all'indietro con loro
            // e la sequenza finisce sulle prime icone, cioè dove la barra resta a riposo
            let elenco = AvvioOrologio.ordine(scorciatoie.count).map { scorciatoie[$0] }
            // la partitura (150 ms, 110 tra i gruppi, l'ultimo gruppo 120, tutto ÷ velocità): è quella con cui è montata «avvioorologio»
            var colpi: [Double] = []; var t = 0.0
            for k in 0..<elenco.count {
                if k > 0 && elenco[k - 1].gruppo != elenco[k].gruppo { t += 0.110 }
                colpi.append(t / v)
                t += elenco[k].gruppo == elenco.last?.gruppo ? 0.120 : 0.150
            }
            // la partitura vera (quella della traccia): le ultime 8 icone sui colpi dello scarico della musica
            if AvvioOrologio.colpi.count == elenco.count { colpi = AvvioOrologio.colpi.map { $0 / v } }
            // la prima icona deve partire PRIMA della musica (la sua molla arriva sul primo colpo): la musica parte dopo l'anticipo
            let pre = AvvioOrologio.anticipo(0, elenco.count)
            SuoniOrologio.avvio(fra: pre)                                  // programmata al campione: niente ritardi del Task
            // un solo orologio: niente pause in fila che sommano i ritardi; il suono arriva all'altoparlante un attimo dopo
            let zero = Date().addingTimeInterval(pre + AVAudioSession.sharedInstance().outputLatency)
            var prima = -10.0, kv = 0
            for k in 0..<elenco.count {
                // ogni icona parte prima del suo colpo di quanto la sua molla ci mette ad «arrivare»: l'arrivo cade sul beep
                let quando = max(prima, colpi[k] - AvvioOrologio.anticipo(k, elenco.count))
                prima = quando
                // i tocchi sul polso restano sul colpo: quelli già scaduti partono adesso
                // l'aptica come sull'iPhone: un tocco solo quando si chiude un gruppo (marcato), l'ultimo pieno; sul colpo, non in anticipo
                while kv < elenco.count && colpi[kv] <= quando {
                    let fineGruppo = kv == elenco.count - 1 || elenco[kv + 1].gruppo != elenco[kv].gruppo
                    if fineGruppo {
                        let tocco: WKHapticType = kv == elenco.count - 1 ? .success : .directionUp
                        let fra = colpi[kv] - Date().timeIntervalSince(zero)
                        if fra > 0.005 { Task { @MainActor in try? await Task.sleep(for: .seconds(fra)); vibra(tocco) } } else { vibra(tocco) }
                    }
                    kv += 1
                }
                let manca = quando - Date().timeIntervalSince(zero)
                if manca > 0 { try? await Task.sleep(for: .seconds(manca)) }
                accese = k + 1                                         // la molla la dà ogni icona (svelta nella coda)
                // la barra segue: porta sul bordo sinistro la PROSSIMA icona, così compare già dentro lo schermo
                // e la fila appena accesa resta visibile alla sua destra
                let ordine = AvvioOrologio.ordine(scorciatoie.count)
                let prossima = k + 1 < colpi.count ? max(quando, colpi[k + 1] - AvvioOrologio.anticipo(k + 1, elenco.count)) : quando + 0.15 / v
                passoBarra = max(0.06, prossima - quando)               // arriva in posizione prima che la prossima parta
                scorriA = ordine[min(k + 1, ordine.count - 1)]
            }
            while kv < elenco.count {                                  // i tocchi rimasti (la raffica finale è partita in anticipo)
                if kv == elenco.count - 1 || elenco[kv + 1].gruppo != elenco[kv].gruppo {
                    let tocco: WKHapticType = kv == elenco.count - 1 ? .success : .directionUp
                    let fra = colpi[kv] - Date().timeIntervalSince(zero)
                    if fra > 0.005 { Task { @MainActor in try? await Task.sleep(for: .seconds(fra)); vibra(tocco) } } else { vibra(tocco) }
                }
                kv += 1
            }
            let resta = (colpi.last ?? 0) + 0.370 / v - Date().timeIntervalSince(zero)   // la coda della musica
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            withAnimation(.easeOut(duration: 0.3)) { titolo = "SISTEMI IN LINEA" }
            vibra(.click)
            if !jarvis.risposta.isEmpty || !jarvis.domanda.isEmpty {     // c'è la conversazione di prima: si ricarica decodificandosi
                try? await Task.sleep(for: .seconds(0.9 / v))         // un respiro, come sull'iPhone
                SuoniOrologio.chatCarica()
                chatDa = Date()
                Task { @MainActor in try? await Task.sleep(for: .seconds(1.3 / v)); chatDa = nil }
            }
            // sistemi in linea: JARVIS ascolta subito, senza toccare il reattore (finito il suono della chat, che non deve sentire)
            let ricarica = chatDa != nil
            Task { @MainActor in
                if ricarica { try? await Task.sleep(for: .seconds(1.4 / v)) }
                jarvis.ascoltaDopoAvvio()
            }
            try? await Task.sleep(for: .seconds(2.2 / v))
            withAnimation(.easeOut(duration: 0.5)) { titolo = "J.A.R.V.I.S. · MARK VIII" }
        }
    }

    /// Conto alla rovescia dell'allarme cuore: un tocco su ANNULLA e non parte nulla.
    private var allarme: some View {
        ZStack {
            Color.red.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 6) {
                Text("❤︎ \(Int(cuore.bpmAllarme)) bpm")
                    .font(.title3.bold())
                Text("Chiamo il contatto di emergenza tra")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Text("\(cuore.conto ?? 0)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                Button("ANNULLA") { cuore.annulla() }
                    .font(.headline)
                    .tint(.white)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    private var principale: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(titolo)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(ReattoreOrologio.colore(caldo ? 1 : 0, titolo == "J.A.R.V.I.S. · MARK VIII" ? 0.8 : 1, schiarisci: titolo == "SISTEMI IN LINEA" ? 0.4 : 0))
                    .id(titolo)
                    .transition(.opacity)
                    .opacity(acceso ? 1 : 0)
                Button { vibra(.click); jarvis.toccaReattore() } label: { reattore }
                    .buttonStyle(StileStarkOrologio())
                    .scaleEffect(acceso ? 1 : 0.6)
                    .opacity(acceso ? 1 : 0)

                barraRapida

                if jarvis.fase == .attesa && jarvis.risposta.isEmpty && jarvis.stato == nil {
                    Text("Tocchi il reattore e parli, Sir")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // In alternativa si scrive (tastiera o scarabocchio).
                TextField("Scriva, Sir", text: $dettato)
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        let testo = dettato
                        dettato = ""
                        jarvis.chiedi(testo)
                    }

                if let stato = jarvis.stato {
                    Text(stato)
                        .font(.footnote)
                        .foregroundStyle(ciano)
                        .multilineTextAlignment(.center)
                }

                if !jarvis.domanda.isEmpty {
                    TestoChatOrologio(testo: jarvis.domanda, stampaDa: chatDa, svuotaDa: svuotaDa, ordine: 0)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !jarvis.risposta.isEmpty {
                    TestoChatOrologio(testo: jarvis.risposta, stampaDa: chatDa, svuotaDa: svuotaDa, ordine: 1)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let s = svuotaDa { BarraSvuotaOrologio(inizio: s, colore: ciano) }   // la barra della pulizia, come sull'iPhone

                if !jarvis.immagini.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(jarvis.immagini.enumerated()), id: \.element.id) { k, foto in
                                NavigationLink {
                                    VistaFoto(foto: jarvis.immagini, iniziale: k)
                                } label: {
                                    MiniaturaOrologio(foto: foto, grande: false)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if jarvis.fase != .attesa {
                    Button("Stop", role: .destructive) { jarvis.fermaETorna() }
                } else if !jarvis.risposta.isEmpty {
                    Button("Ripeti") { jarvis.ripeti() }
                }
            }
            .padding(.horizontal, 4)
        }
        .background { sfondo }
    }

    private var caldo: Bool { jarvis.fase == .elaboro || jarvis.fase == .parlo }

    private var reattore: some View {
        ZStack {
            ReattoreOrologio(fase: jarvis.fase)
            Text(etichetta)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: 38)
        }
        .frame(width: 112, height: 112)
    }

    /// Sfondo: un bagliore azzurro o arancione secondo la fase.
    private var sfondo: some View {
        ZStack {
            RadialGradient(colors: [ReattoreOrologio.colore(caldo ? 1 : 0, 0.28, schiarisci: 0), .black],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 160)
            // la griglia HUD dell'iPhone (SfondoHUD), in scala col polso: passo 14 invece di 28, scorre piano
            TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                Canvas { gc, size in
                    let passo: CGFloat = 14
                    var g = Path()
                    var x: CGFloat = 0
                    while x < size.width { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); x += passo }
                    var y: CGFloat = CGFloat(t * 3).truncatingRemainder(dividingBy: passo)
                    while y < size.height { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); y += passo }
                    gc.stroke(g, with: .color(ReattoreOrologio.colore(caldo ? 1 : 0, 0.07, schiarisci: 0)), lineWidth: 0.5)
                }
                .mask(RadialGradient(colors: [.black, .clear], center: UnitPoint(x: 0.5, y: 0.35), startRadius: 20, endRadius: 150))
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: caldo)
    }

    /// Scorciatoie: un tocco e JARVIS fa la domanda. Per aggiungerne una basta una riga.
    /// Stessi gruppi dell'iPhone: GIORNATA · SIGNORE · SENSI · STRUMENTI, separati da una linea sottile.
    /// Come sull'iPhone: GIORNATA · SIGNORE · SENSI · STRUMENTI.
    /// Occhi, Cucina e Allenatore restano solo sull'iPhone (servono la fotocamera); la Foto e il Browser pure.
    /// frase "#vitals" apre la pagina Vitals, "#sentinella" la Sentinella; frase nil pulisce la conversazione.
    private var scorciatoie: [(gruppo: String, icona: String, frase: String?)] {
        [
            ("GIORNATA", "sun.horizon", "#briefing"),
            ("GIORNATA", "cloud.sun", "#meteo"),
            ("GIORNATA", "envelope", "#email"),
            ("GIORNATA", "cart", "#spesa"),

            ("SIGNORE", "book.closed", "#diario"),
            ("SIGNORE", "person.2.wave.2", "Modalità confidente. Ho bisogno di parlarti di una cosa."),
            ("SIGNORE", "waveform.path.ecg", "#vitals"),
            ("SIGNORE", "bed.double", "#sonno"),
            ("SIGNORE", "heart", "#cuore"),

            ("SENSI", "shazam.logo", "#shazam"),

            ("STRUMENTI", "brain.head.profile", "#ricordi"),
            ("STRUMENTI", "globe.europe.africa", "Fammi da interprete: ti dirò una frase e la lingua, tu traducila e dimmela ad alta voce."),
            ("STRUMENTI", "music.note.list", "#serata"),
            ("STRUMENTI", "trash", nil),                       // pulisce la conversazione

            ("INTELLIGENCE", "dot.radiowaves.left.and.right", "#sentinella"),   // la Sentinella: allarmi e «Guarda ora»
            ("INTELLIGENCE", "link", "#bea"),                                    // 20 ott: Bea passa in INTELLIGENCE, come sull'iPhone

            ("SISTEMI", "logo:github-logo", "#github"),          // i loghi veri, come sull'iPhone
            ("SISTEMI", "logo:supabase-logo", "#supabase"),
            ("SISTEMI", "archivio", "#archivio"),                // la cartella con la nuvola
        ]
    }

    /// L'icona di una scorciatoia: un simbolo di sistema, un logo dagli Assets («logo:nome») o la cartella dell'Archivio.
    @ViewBuilder private func iconaScorciatoia(_ icona: String) -> some View {
        if icona.hasPrefix("logo:") {
            Image(String(icona.dropFirst(5))).resizable().renderingMode(.template).scaledToFit().frame(width: 15, height: 15)
        } else if icona == "archivio" {
            IconaArchivioOrologio().scaleEffect(0.75)
        } else {
            Image(systemName: icona)
        }
    }

    private var barraRapida: some View {
        let n = scorciatoie.count
        let posto: (Int) -> Int = { n - 1 - $0 }                  // il posto di un'icona nell'ordine d'accensione (al contrario)
        return ScrollViewReader { lettore in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(scorciatoie.enumerated()), id: \.offset) { k, s in
                    let inCorso = iconaAttiva == k && jarvis.fase != .attesa
                    if k > 0 && scorciatoie[k - 1].gruppo != s.gruppo {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, ReattoreOrologio.colore(caldo ? 1 : 0, 0.6, schiarisci: 0), .clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 1, height: 26)
                            .opacity(posto(k) < accese ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: accese)
                    }
                    Button {
                        vibra(.click); SuoniOrologio.tick()
                        if let f = s.frase, f.hasPrefix("#"), let r = Reparto(rawValue: String(f.dropFirst())) { apri(r) }
                        else if let frase = s.frase { iconaAttiva = k; jarvis.chiedi(frase) }
                        else { chiediPulizia = true }
                    } label: {
                        iconaScorciatoia(s.icona)
                            .font(.system(size: 14))
                            .symbolEffect(.pulse, options: .repeating, isActive: inCorso)
                            .frame(width: 34, height: 34)
                            .background(ReattoreOrologio.colore(caldo ? 1 : 0, inCorso ? 0.3 : 0.12, schiarisci: 0))
                            .overlay(Circle().stroke(ReattoreOrologio.colore(caldo ? 1 : 0, inCorso ? 1 : 0.5, schiarisci: 0), lineWidth: inCorso ? 1.4 : 0.8))
                            .overlay(AnelloRotanteOrologio(attivo: inCorso, colore: ReattoreOrologio.colore(caldo ? 1 : 0, 1, schiarisci: 0.3)))
                            .clipShape(Circle())
                            .shadow(color: ReattoreOrologio.colore(caldo ? 1 : 0, inCorso ? 0.7 : 0, schiarisci: 0), radius: 6)
                            .foregroundStyle(ReattoreOrologio.colore(caldo ? 1 : 0, 1, schiarisci: 0.2))
                    }
                    .buttonStyle(StileStarkOrologio())
                    .opacity(posto(k) < accese ? 1 : 0)
                    .scaleEffect(posto(k) < accese ? 1 : 2.4)               // come sull'iPhone: grande e trasparente, poi si restringe e si accende
                    .brightness(posto(k) == accese - 1 && accese < n ? 0.35 : 0)   // lampo solo mentre si accende
                    .animation(.spring(duration: AvvioOrologio.molla(posto(k), n), bounce: 0.25), value: accese)
                    .id(k)
                }
            }
            .padding(.horizontal, 2)
        }
        .onChange(of: barraInFondo) { _, si in if si { lettore.scrollTo(n - 1, anchor: .trailing) } }
        .onChange(of: scorriA) { _, k in if let k { withAnimation(.easeOut(duration: passoBarra)) { lettore.scrollTo(k, anchor: .leading) } } }
        }
        .disabled(jarvis.fase == .elaboro)
    }

    private var etichetta: String {
        switch jarvis.fase {
        case .attesa: return "JARVIS"
        case .ascolto: return "ASCOLTO"
        case .elaboro: return "…"
        case .parlo: return "PARLO"
        }
    }
}

/// Tasti alla Stark anche sul polso: si schiacciano, si illuminano e tornano su con una molla.
struct StileStarkOrologio: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .brightness(configuration.isPressed ? 0.3 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

/// Un arco di luce che gira intorno all'icona in lavorazione.
struct AnelloRotanteOrologio: View {
    let attivo: Bool
    let colore: Color
    var body: some View {
        if attivo {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let giro = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(colore, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(giro))
                    .padding(1)
            }
            .allowsHitTesting(false)
        }
    }
}

/// La conversazione sull'orologio, con il tasto per cancellarla.
struct VistaCronologia: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.dismiss) private var chiudi

    var body: some View {
        List {
            if jarvis.storia.isEmpty {
                Text("Nessuna conversazione, Sir.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(jarvis.storia.enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(m["role"] == "user" ? "Lei" : "JARVIS")
                        .font(.caption2)
                        .foregroundStyle(m["role"] == "user" ? Color.secondary : Color(red: 0.31, green: 0.89, blue: 1.0))
                    Text(m["content"] ?? "")
                        .font(.footnote)
                }
            }
            if !jarvis.storia.isEmpty {
                Button("Cancella conversazione", role: .destructive) {
                    jarvis.svuotaRichiesto = true            // la conferma e la cancellazione le fa la schermata principale
                    chiudi()
                }
            }
        }
        .navigationTitle("Cronologia")
    }
}

/// Vitals sull'orologio: tutto quello che c'è sull'iPhone, in formato polso.
/// Oggi (sonno, battito, passi, calorie, allenamenti), periodo 7/30 giorni con medie, grafici di umore e sonno,
/// battito e passi, la lettura, il diario da rileggere e cancellare, le domande a JARVIS e l'allarme cuore.
struct VistaVitalsOrologio: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.dismiss) private var chiudi
    @ObservedObject private var cuore = Cuore.condiviso
    @State private var oggi: SaluteOggi?
    @State private var dati: DatiVitals?
    @State private var giorni = 7
    @State private var confermaTutto = false
    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)

    var body: some View {
        List {
            Section {
                riga("heart.fill", .red, "Battito ora", cuore.ultimo.map { "\(Int($0.rounded())) bpm" } ?? "—")
                riga("bed.double.fill", ciano, "Sonno", oggi?.sonno ?? (oggi == nil ? "…" : "—"))
                if let o = oggi?.orari { Text(o).font(.footnote).foregroundStyle(.secondary) }
                if let f = oggi?.fasi { Text(f).font(.caption2).foregroundStyle(.secondary) }
                if let p = oggi?.pisolini { Text("Pisolino \(p)").font(.caption2).foregroundStyle(ciano) }
                riga("heart.text.square", .pink, "A riposo", oggi?.battito.map { b in "\(b) bpm" + (oggi?.battitoMedia.map { " · media \($0)" } ?? "") } ?? "—")
                riga("figure.walk", .green, "Passi", oggi?.passi.map { $0.formatted() } ?? "—")
                riga("flame.fill", .orange, "Calorie", oggi?.calorie.map { "\($0) kcal" } ?? "—")
                ForEach(oggi?.allenamenti ?? [], id: \.self) { a in
                    Label(a, systemImage: "figure.run").font(.caption2)
                }
            } header: { Text("Oggi") }

            Section {
                Picker("Periodo", selection: $giorni) {
                    Text("7 giorni").tag(7)
                    Text("30 giorni").tag(30)
                }
                if let d = dati {
                    riga("face.smiling", ciano, "Umore", d.mediaUmore.map { String(format: "%.1f / 10", $0) } ?? "—")
                    riga("bed.double", ciano, "Sonno", d.mediaSonno.map { String(format: "%.1f h", $0) } ?? "—")
                    riga("heart", .pink, "Riposo", d.mediaBattito.map { "\(Int($0)) bpm" } ?? "—")
                } else {
                    Text("Leggo i Vitals…").font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Medie") }

            if let d = dati, !d.giorni.isEmpty {
                Section {
                    Chart {
                        ForEach(d.giorni) { g in
                            if let s = g.sonno {
                                BarMark(x: .value("Giorno", g.data, unit: .day), y: .value("Valore", s))
                                    .foregroundStyle(Color.orange.opacity(0.5))
                            }
                        }
                        ForEach(d.giorni.filter { $0.punteggio != nil }) { g in
                            LineMark(x: .value("Giorno", g.data, unit: .day), y: .value("Valore", g.punteggio!))
                                .foregroundStyle(ciano)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: 0...10)
                    .chartXAxis(.hidden)
                    .frame(height: 90)
                    Text("Linea: umore · barre: ore di sonno").font(.caption2).foregroundStyle(.secondary)
                } header: { Text("Umore e sonno") }

                if !d.battiti.isEmpty {
                    Section {
                        Chart(d.battiti) { g in
                            LineMark(x: .value("Giorno", g.data, unit: .day), y: .value("bpm", g.battito ?? 0))
                                .foregroundStyle(Color.red)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxis(.hidden)
                        .frame(height: 70)
                    } header: { Text("Battito a riposo") }
                }

                if !d.passiGiorni.isEmpty {
                    Section {
                        Chart(d.passiGiorni) { g in
                            BarMark(x: .value("Giorno", g.data, unit: .day), y: .value("Passi", g.passi ?? 0))
                                .foregroundStyle(ciano.opacity(0.6))
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 70)
                    } header: { Text("Passi") }
                }
            }

            if let d = dati {
                Section {
                    ForEach(d.frasi, id: \.self) { f in Text(f).font(.footnote) }
                } header: { Text("Lettura") }
            }

            Section {
                Button { jarvis.chiedi("Come sto ultimamente? Guarda i miei Vitals: umore, sonno e cuore."); chiudi() } label: {
                    Label("Come sto?", systemImage: "waveform")
                }
                Button { jarvis.chiedi("Come ho dormito stanotte?"); chiudi() } label: {
                    Label("Il mio sonno", systemImage: "bed.double")
                }
                Button { jarvis.chiedi("Come sta il mio cuore oggi?"); chiudi() } label: {
                    Label("Il mio cuore", systemImage: "heart")
                }
            }

            if let d = dati, !d.pagine.isEmpty {
                Section {
                    ForEach(d.pagine) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(p.giorno)\(p.umore.map { " · \($0)" } ?? "")").font(.caption2).foregroundStyle(ciano)
                            Text(p.risposta).font(.footnote).lineLimit(4)
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await cancella(p.id) } } label: { Label("Cancella", systemImage: "trash") }
                        }
                    }
                    Button("Cancella tutto il diario", role: .destructive) { confermaTutto = true }
                } header: { Text("Diario") }
            }

            Section {
                NavigationLink { VistaCuore() } label: {
                    Label("Allarme cuore", systemImage: "bell.badge.fill").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Vitals")
        .aperturaOrologio("Vitals")
        .task {
            await cuore.aggiornaUltimo()
            oggi = await SaluteOggi.leggi()
        }
        .task(id: giorni) { await carica() }
        .confirmationDialog("Cancellare tutto il diario?", isPresented: $confermaTutto) {
            Button("Cancella tutto", role: .destructive) { Task { await cancella(nil) } }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func riga(_ icona: String, _ colore: Color, _ titolo: String, _ valore: String) -> some View {
        HStack {
            Image(systemName: icona).foregroundStyle(colore).frame(width: 20)
            Text(titolo).font(.footnote)
            Spacer()
            Text(valore).font(.footnote.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func carica() async {
        async let salute = SaluteStorica.giorni(giorni)
        let o = await VistaVitalsOrologio.chiama(["vitals": true, "giorni": giorni])
        let s = await salute
        withAnimation { dati = DatiVitals(o ?? [:], salute: s, giorni: giorni) }
    }

    /// nil = tutto il diario
    private func cancella(_ id: Int?) async {
        let valore: Any = id.map { $0 as Any } ?? "tutto"
        _ = await VistaVitalsOrologio.chiama(["diario_cancella": valore])
        WKInterfaceDevice.current().play(.click)
        await carica()
    }

    static func chiama(_ corpo: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: ImpostazioniOrologio.indirizzo) else { return nil }
        let token = PortachiaviOrologio.leggi()
        guard !token.isEmpty else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}

/// Ricordi: la seconda memoria sul polso. La macchina (con il percorso a piedi), la lista della spesa da spuntare,
/// le promesse con il loro avviso, le ultime cose segnate. Per aggiungere: basta dirlo a JARVIS.
struct VistaRicordiOrologio: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.dismiss) private var chiudi
    @State private var dati: [String: Any]?
    @State private var errore = false
    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)

    var body: some View {
        List {
            if let d = dati {
                let posti = (d["posti"] as? [[String: Any]] ?? []).prefix(8)
                if !posti.isEmpty {
                    Section {
                        ForEach(Array(posti.enumerated()), id: \.offset) { _, p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p["testo"] as? String ?? "").font(.footnote).lineLimit(2)
                                Text([p["luogo"] as? String, p["quando_leggibile"] as? String].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let lat = (p["lat"] as? NSNumber)?.doubleValue, let lon = (p["lon"] as? NSNumber)?.doubleValue,
                                   let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=w") {
                                    Link(destination: url) { Label("Portami lì", systemImage: "figure.walk").font(.caption2) }
                                }
                            }
                            .swipeActions { cancellaTasto(p) }
                        }
                    } header: { Label("Posti", systemImage: "mappin.and.ellipse") }
                }

                Section {
                    let spesa = d["spesa"] as? [[String: Any]] ?? []
                    if spesa.isEmpty { Text("Lista vuota").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(spesa.enumerated()), id: \.offset) { _, r in
                        Button { Task { await spunta(r) } } label: {
                            Label(r["testo"] as? String ?? "", systemImage: "circle")
                        }
                        .swipeActions { cancellaTasto(r) }
                    }
                } header: { Label("Spesa", systemImage: "cart.fill") }

                let promesse = d["promesse"] as? [[String: Any]] ?? []
                if !promesse.isEmpty {
                    Section {
                        ForEach(Array(promesse.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r["testo"] as? String ?? "").font(.footnote)
                                Text([r["persona"] as? String, r["quando_leggibile"] as? String].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button { Task { await spunta(r) } } label: { Label("Fatta", systemImage: "checkmark") }.tint(.green)
                                cancellaTasto(r)
                            }
                        }
                    } header: { Label("Promesse", systemImage: "hand.raised.fill") }
                }

                let ultimi = d["ricordi"] as? [[String: Any]] ?? []
                if !ultimi.isEmpty {
                    Section {
                        ForEach(Array(ultimi.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r["testo"] as? String ?? "").font(.footnote).lineLimit(3)
                                Text([r["tipo"] as? String, r["luogo"] as? String, r["quando_leggibile"] as? String].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .swipeActions { cancellaTasto(r) }
                        }
                    } header: { Label("Ultimi ricordi", systemImage: "brain.head.profile") }
                }
            } else if errore {
                Text("Non raggiungo la memoria, Sir.").font(.footnote)
            } else {
                ProgressView()
            }

            Section {
                Button { jarvis.chiedi("Ricordati questo posto: dove sono adesso."); chiudi() } label: { Label("Ricorda dove sono", systemImage: "mappin.and.ellipse") }
                Button { jarvis.chiedi("Ho parcheggiato qui, segnalo."); chiudi() } label: { Label("Ho parcheggiato", systemImage: "car") }
                Button { jarvis.chiedi("Com'è andata oggi?"); chiudi() } label: { Label("Com'è andata oggi?", systemImage: "clock.arrow.circlepath") }
            }
        }
        .navigationTitle("Ricordi")
        .task { await carica() }
    }

    private func carica() async {
        let o = await VistaVitalsOrologio.chiama(["ricordi": true])
        errore = o == nil
        withAnimation { dati = o }
    }

    private func spunta(_ r: [String: Any]) async {
        guard let id = (r["id"] as? NSNumber)?.intValue else { return }
        WKInterfaceDevice.current().play(.success)
        SuoniOrologio.fatto()
        _ = await VistaVitalsOrologio.chiama(["ricordo_fatto": id])
        await carica()
    }

    /// Scorrendo verso sinistra: cancella il ricordo (anche dalla memoria dell'iPhone).
    private func cancellaTasto(_ r: [String: Any]) -> some View {
        Button(role: .destructive) { Task { await cancella(r) } } label: { Label("Cancella", systemImage: "trash") }
    }

    private func cancella(_ r: [String: Any]) async {
        guard let id = (r["id"] as? NSNumber)?.intValue else { return }
        WKInterfaceDevice.current().play(.click)
        _ = await VistaVitalsOrologio.chiama(["ricordo_elimina": id])
        await carica()
    }
}

/// Il cuore: ultimo battito, sorveglianza e prova dell'allarme.
struct VistaCuore: View {
    @ObservedObject private var cuore = Cuore.condiviso
    @State private var confermaProva = false
    @State private var confermaSOS = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                    Text(cuore.ultimo.map { "\(Int($0.rounded())) bpm" } ?? "—")
                        .font(.title2.bold())
                }
                if let q = cuore.ultimoQuando {
                    Text(q.formatted(date: .omitted, time: .shortened))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button { confermaSOS = true } label: {
                    HStack {
                        Spacer()
                        Label("SOS · CHIEDI AIUTO", systemImage: "sos.circle.fill").font(.system(size: 15, weight: .heavy))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .tint(.red).buttonStyle(.borderedProminent)
            } footer: {
                Text("Manda subito SMS, WhatsApp e chiamata al contatto di emergenza, con la sua posizione.")
            }
            Section {
                Toggle("Sorveglianza", isOn: $cuore.sorveglianza)
            } footer: {
                Text("Sopra \(Int(Cuore.soglia)) o sotto \(Int(Cuore.sogliaBassa)) bpm a riposo: \(Cuore.secondiPerAnnullare) secondi per annullare, poi SMS e chiamata al contatto di emergenza, con la posizione.")
            }
            Section {
                Button("Prova allarme") { confermaProva = true }
            } footer: {
                Text("Manda al contatto un SMS e una chiamata di PROVA.")
            }
            if let e = cuore.esito {
                Text(e).font(.footnote)
            }
        }
        .navigationTitle("Cuore")
        .task { await cuore.aggiornaUltimo() }
        .confirmationDialog("Chiedo aiuto al contatto di emergenza, con la sua posizione?", isPresented: $confermaSOS, titleVisibility: .visible) {
            Button("SÌ, CHIEDI AIUTO", role: .destructive) { cuore.avviaAllarme(bpm: cuore.ultimo ?? 0, prova: false, motivo: "manuale") }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Mando una PROVA al contatto di emergenza?", isPresented: $confermaProva) {
            Button("Manda la prova") { cuore.avviaAllarme(bpm: cuore.ultimo ?? 0, prova: true) }
            Button("Annulla", role: .cancel) {}
        }
    }
}

/// Miniatura: dal web oppure dai dati arrivati dall'iPhone.
struct MiniaturaOrologio: View {
    let foto: FotoOrologio
    let grande: Bool
    var body: some View {
        if let d = foto.dati, let img = UIImage(data: d) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: grande ? .fit : .fill)
        } else if let s = grande ? (foto.grande ?? foto.url) : (foto.url ?? foto.grande), let url = URL(string: s) {
            AsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: grande ? .fit : .fill)
            } placeholder: {
                Color.gray.opacity(0.2)
            }
        } else {
            Color.gray.opacity(0.2)
        }
    }
}

/// Le immagini a schermo intero, una per pagina; «Apri la pagina» la apre nel browser dell'orologio.
struct VistaFoto: View {
    let foto: [FotoOrologio]
    @State var iniziale: Int
    var body: some View {
        TabView(selection: $iniziale) {
            ForEach(Array(foto.enumerated()), id: \.element.id) { k, f in
                ScrollView {
                    VStack(spacing: 6) {
                        MiniaturaOrologio(foto: f, grande: true)
                            .frame(maxWidth: .infinity)
                        if let t = f.titolo, !t.isEmpty {
                            Text(t).font(.footnote).multilineTextAlignment(.center)
                        }
                        if let p = f.pagina, let url = URL(string: p) {
                            Link(destination: url) { Label("Apri la pagina", systemImage: "safari") }
                        }
                    }
                }
                .tag(k)
            }
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Archivio: la cartella con la piccola nuvola, la stessa dell'iPhone.
struct IconaArchivioOrologio: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 5)); p.addLine(to: CGPoint(x: 6.5, y: 5)); p.addLine(to: CGPoint(x: 8.5, y: 7.5))
                p.addLine(to: CGPoint(x: 21, y: 7.5)); p.addLine(to: CGPoint(x: 21, y: 19)); p.addLine(to: CGPoint(x: 0, y: 19))
                p.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            Image(systemName: "cloud.fill").font(.system(size: 8, weight: .semibold))
                .position(x: 15, y: 3.5)
        }
        .frame(width: 21, height: 19)
    }
}


/// Domanda e risposta sull'orologio: si decodificano all'avvio e si ritirano verso sinistra quando si pulisce.
struct TestoChatOrologio: View {
    let testo: String
    let stampaDa: Date?
    let svuotaDa: Date?
    let ordine: Double            // 0 = domanda (sopra), 1 = risposta (sotto)

    private static let glifi = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|▪▫░▒")
    private static func rimescola(_ s: String, _ q: Double) -> String {
        guard q > 0 else { return s }
        return String(s.map { c in (c == " " || c == "\n" || Double.random(in: 0..<1) > q) ? c : (glifi.randomElement() ?? c) })
    }

    var body: some View {
        if let s = svuotaDa {
            TimelineView(.animation) { ctx in
                let p = min(1, max(0, (ctx.date.timeIntervalSince(s) - (1 - ordine) * 0.75) / 0.38))   // prima la risposta, poi la domanda (tempi dell'iPhone)
                let e = p * p * (3 - 2 * p)
                Text(Self.rimescola(testo, min(1, p * 2.2)))
                    .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: g.size.width * (1 - e)) } }
            }
        } else if let s = stampaDa {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(s) - ordine * 0.35 / AvvioOrologio.velocita         // prima la domanda, poi la risposta
                Text(Self.rimescola(testo, t < 0 ? 1 : max(0, 1 - t / (0.42 / AvvioOrologio.velocita))))
                    .opacity(t < 0 ? 0 : 1)
            }
        } else {
            Text(testo)
        }
    }
}


/// I numeri dell'avvio al polso (+35%; la raffica finale in anticipo di 110 ms con la molla svelta).
enum AvvioOrologio {
    static let velocita = 1.15          // il polso è piccolo: +15%, scelto dal signore sul mock (l'iPhone resta a +60%)
    /// L'apertura di un'app sul Watch (lo zoom dall'icona) dura circa mezzo secondo: la sequenza parte quando lo schermo si vede.
    static let attesaApertura = 0.6
    /// La molla di ogni icona, per posto d'accensione: più svelta verso la fine, dove i colpi si avvicinano.
    /// Le prime 11 (passo 150 ms) 0,32 s come sull'iPhone; le 4 dopo 0,20; le ultime 4 (GIORNATA, passo 120) 0,14.
    static func molla(_ posto: Int, _ n: Int) -> Double { (posto >= n - 8 ? 0.14 : 0.32) / velocita }   // ÷ velocità, come tutto
    /// Una molla con rimbalzo 0,25 raggiunge il 90% della sua misura al 44,5% della durata: lì l'occhio la vede arrivata.
    /// L'icona parte con questo anticipo sul suo colpo, così l'arrivo cade sul beep.
    static func anticipo(_ posto: Int, _ n: Int) -> Double { 0.445 * molla(posto, n) }
    /// La partitura del polso (secondi a velocità normale, nell'ordine d'accensione, da Archivio a Briefing): è quella con cui
    /// è montata «avvioorologio». Segue la musica (misurata): le prime 11 da 0 al colpo forte di 2,499 s (passo 250 ms),
    /// poi la pausa (2,6–2,8 s, il respiro), poi le ultime 8 su tutto lo SCARICO (2,885 → 3,724 s, una ogni 120 ms):
    /// Briefing si accende sull'ultimo colpo dello scarico, poi la musica sfuma.
    static let colpi: [Double] = [0, 0.25, 0.50, 0.75, 1.00, 1.25, 1.499, 1.749, 1.999, 2.249, 2.499,
                                  2.885, 3.005, 3.125, 3.245, 3.364, 3.484, 3.604, 3.724]
    /// L'ordine d'accensione al polso: dall'ultima icona alla prima (la barra finisce dov'è a riposo).
    static func ordine(_ n: Int) -> [Int] { Array((0..<n).reversed()) }

}

/// La barra in fondo mentre la conversazione si svuota: da 100% a 0%, con le voci della pulizia (come sull'iPhone).
struct BarraSvuotaOrologio: View {
    let inizio: Date
    let colore: Color
    private let voci = ["ARCHIVIO", "PULIZIA", "MEMORIA LIBERA"]

    var body: some View {
        TimelineView(.animation) { ctx in
            let q = min(1, ctx.date.timeIntervalSince(inizio) / 1.13)          // 0,75 + 0,38 s, gli stessi tempi dell'iPhone
            VStack(spacing: 4) {
                HStack {
                    Text(voci[min(2, Int(q * 3))])
                    Spacer()
                    Text("\(Int(((1 - q) * 100).rounded()))%").monospacedDigit()
                }
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(colore)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(colore.opacity(0.15))
                        Capsule().fill(colore).frame(width: g.size.width * (1 - q)).shadow(color: colore, radius: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .allowsHitTesting(false)
    }
}
