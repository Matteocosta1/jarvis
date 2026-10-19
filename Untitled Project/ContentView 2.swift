import SwiftUI
import AVFoundation

/// Le schede delle icone della corona.
enum SchedaApp: String, Identifiable {
    case diario, sonno, cuore, briefing, meteo, email, spesa, shazam, foto, serata, messaggi, telefono, bea
    case github, supabase, archivio, costi
    case scanner
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var jarvis: Jarvis
    @ObservedObject private var comandi = Comandi.condiviso
    @AppStorage("ascoltaApertura") private var ascoltaApertura = true
    @State private var testo = ""
    @State private var mostraImpostazioni = false
    @State private var mostraBrowser = false
    @State private var chiediPulizia = false
    @State private var sorgenteFoto: UIImagePickerController.SourceType?
    @State private var primaApertura = true
    @State private var acceso = false            // sequenza di avvio: le icone si accendono una dopo l'altra
    @State private var sottotitolo = "AVVIO SISTEMI"
    @State private var iconaAttiva: Int?         // scorciatoia in corso: pulsa finché JARVIS non ha finito
    @State private var scegliLingua = false       // icona Interprete: scelta della lingua
    @State private var accese = 0                 // quante icone si sono già accese all'avvio (plim, plim, plim…)
    @State private var mostraVitals = false
    @State private var mostraConfidente = false
    @State private var mostraRicordi: VistaRicordi.Scheda?
    @State private var mostraSentinella = false
    @State private var mostraWiretap = false
    @State private var mostraProfiler = false
    @State private var mostraSistemi = false        // il menu SISTEMI in alto: GitHub, Supabase, Archivio
    @State private var statoSistemi: [String: String] = [:]   // la riga di stato sotto ogni voce del menu
    @State private var scheda: SchedaApp?          // le schede delle icone: Diario, Sonno, Cuore, Meteo, Spesa…
    @State private var aiutoBea: AiutoBea?          // il Tocco d'aiuto di Bea: schermata a tutto schermo
    @Environment(\.scenePhase) private var scena

    /// Schermata principale in primo piano e niente aperto sopra: solo così il richiamo «Jarvis» resta in ascolto.
    private var schermoLibero: Bool {
        let inPrimoPiano: Bool = scena == .active
        let nienteDiJarvis: Bool = jarvis.pagina == nil && jarvis.occhi == nil && jarvis.interprete == nil && !jarvis.allenatore
        let nienteSchede: Bool = scheda == nil && mostraRicordi == nil && sorgenteFoto == nil
        let nienteReparti: Bool = !mostraImpostazioni && !mostraBrowser && !mostraSentinella && !mostraWiretap
        let nienteAltro: Bool = !mostraProfiler && !mostraVitals && !mostraConfidente
        return inPrimoPiano && nienteDiJarvis && nienteSchede && nienteReparti && nienteAltro
    }
    @FocusState private var tastiera: Bool

    var body: some View {
        ZStack {
            SfondoHUD(fase: jarvis.fase)
            if mostraSistemi { menuSistemi.zIndex(10) }

            VStack(spacing: 0) {
                intestazione
                corona
                    .padding(.top, 26)        // il reattore più verso il centro dello schermo

                Text(jarvis.fase.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(Color.ciano)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: jarvis.fase)
                    .padding(.top, 8)
                TelemetriaHUD(fase: jarvis.fase)
                    .padding(.top, 4)
                    .opacity(acceso ? 1 : 0)

                Text(!jarvis.parziale.isEmpty ? jarvis.parziale : (jarvis.stato.map { "\($0)…" } ?? suggerimento))
                    .font(.system(size: 15))
                    .foregroundStyle(jarvis.parziale.isEmpty ? Color.tenue : .white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)

                if let avviso = jarvis.avviso {
                    Text(avviso)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                registro
                barraTesto
            }
        }
        .sheet(isPresented: $mostraImpostazioni, onDismiss: eseguiComando) { ImpostazioniView().environmentObject(jarvis) }
        .sheet(item: $jarvis.pagina) { p in BrowserInterno(url: p.url).ignoresSafeArea() }
        .fullScreenCover(isPresented: $mostraBrowser) { BrowserPrivato() }
        .fullScreenCover(item: $jarvis.occhi, onDismiss: { jarvis.occhiChiusi([]) }) { o in
            Occhi(automatico: o.automatico, video: o.video, cucina: o.cucina, zoomIniziale: o.zoom) { dati in jarvis.occhiChiusi(dati) }
        }
        .fullScreenCover(item: $jarvis.interprete) { l in
            Interprete(lingua: l) { jarvis.interprete = nil }
        }
        .fullScreenCover(isPresented: $mostraSentinella) {
            VistaSentinella(chiudi: { mostraSentinella = false }, comando: comandoDaReparto)
        }
        .fullScreenCover(isPresented: $mostraWiretap) {
            VistaWiretap(verbale: { testo, minuti in
                mostraWiretap = false
                jarvis.verbaleWiretap(testo, minuti: minuti)
            }, chiudi: { mostraWiretap = false }, comando: comandoDaReparto)
        }
        // comandi vocali: «attiva la Sentinella», «apri il Wiretap», «fammi un profilo», «fai un giro»
        .onChange(of: jarvis.repartoRichiesto) { _, r in
            guard let r else { return }
            jarvis.repartoRichiesto = nil
            apriReparto(r)
        }
        // Profiler: la sua schermata (fotocamera dietro o selfie) e la scheda da compilare
        .fullScreenCover(isPresented: $mostraProfiler) {
            VistaProfiler { dati, nome in
                mostraProfiler = false
                if !dati.isEmpty { jarvis.profila(dati, nome: nome) }
            }
        }
        // le schede delle icone
        .sheet(item: $scheda) { sc in
            switch sc {
            case .diario: VistaDiario(chiedi: daScheda) {
                scheda = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    jarvis.chiediDiario("Diario, Sir. Mi racconti com'è andata oggi: la ascolto.")
                }
            }
            case .sonno: VistaSonno(chiedi: daScheda)
            case .cuore: VistaCuoreTelefono(chiedi: daScheda)
            case .briefing: VistaBriefing(chiedi: daScheda) { altra in
                scheda = nil
                Task { try? await Task.sleep(for: .milliseconds(500)); scheda = altra }
            }
            case .meteo: VistaMeteo(chiedi: daScheda)
            case .email: VistaPosta(chiedi: daScheda)
            case .spesa: VistaSpesa(chiedi: daScheda)
            case .shazam: VistaShazam(chiedi: daScheda)
            case .foto: VistaFotoScheda(chiedi: daScheda)
            case .serata: VistaSerata(chiedi: daScheda)
            case .messaggi: VistaMessaggi(chiedi: daScheda)
            case .telefono: VistaTelefono(chiedi: daScheda)
            case .github: VistaGitHub(chiedi: daScheda, apri: apriPagina)
            case .supabase: VistaSupabase(chiedi: daScheda)
            case .archivio: VistaArchivio(chiedi: daScheda, apri: apriPagina)
            case .costi: VistaCosti(chiedi: daScheda)
            case .scanner: VistaScanner(chiedi: daScheda)
            case .bea: VistaBea(chiedi: daScheda)
            }
        }
        .fullScreenCover(isPresented: $jarvis.allenatore) {
            Allenatore { jarvis.allenatore = false }
        }
        .sheet(isPresented: $mostraVitals) {
            VistaVitals { frase in mostraVitals = false; chiedi(frase) }
        }
        .sheet(item: $mostraRicordi) { scheda in
            VistaRicordi(iniziale: scheda) { frase in mostraRicordi = nil; chiedi(frase) }
        }
        .sheet(isPresented: $mostraConfidente) {
            VistaConfidente(invia: { testo in mostraConfidente = false; chiedi(testo) },
                            aVoce: { mostraConfidente = false; jarvis.chiediDiario("Modalità confidente. Mi racconti pure, Sir: la ascolto.") })
        }
        .confirmationDialog("Interprete: in che lingua?", isPresented: $scegliLingua, titleVisibility: .visible) {
            ForEach(Lingua.tutte) { l in
                Button("\(l.bandiera) \(l.nome)") { jarvis.interrompi(); jarvis.interprete = l }
            }
            Button("Annulla", role: .cancel) {}
        }
        .fullScreenCover(isPresented: Binding(get: { sorgenteFoto != nil }, set: { if !$0 { sorgenteFoto = nil } })) {
            Fotocamera(sorgente: sorgenteFoto ?? .photoLibrary) { immagine in
                jarvis.impostaFoto(immagine)
                jarvis.ascoltaSubito()          // subito dopo la foto: «che disco è?»
            }
            .ignoresSafeArea()
        }
        .onAppear {
            accendi()
            if Portachiavi.leggi().isEmpty { mostraImpostazioni = true; return }
            if primaApertura {
                primaApertura = false
                if comandi.richiesta == nil && ascoltaApertura { jarvis.ascoltaSubito() }
            }
            eseguiComando()
        }
        .onChange(of: comandi.richiesta) { eseguiComando() }
        .fullScreenCover(item: $aiutoBea) { a in VistaAiutoBea(aiuto: a) { aiutoBea = nil } }
        .onChange(of: jarvis.fase) { _, nuova in if nuova == .attesa { iconaAttiva = nil } }
        .onChange(of: schermoLibero, initial: true) { _, libero in jarvis.richiamoConsentito = libero }
    }

    /// Sequenza di avvio alla Stark: suono, icone che si accendono in fila, «SISTEMI IN LINEA».
    private func accendi() {
        guard !acceso else { return }
        withAnimation(.spring(duration: 0.6, bounce: 0.35)) { acceso = true }
        Task { @MainActor in
            // le icone si accendono una alla volta, ognuna con il suo «plim»
            try? await Task.sleep(for: .milliseconds(650))
            let elenco = tutteLeIcone
            for k in 0..<elenco.count {                             // la corona e, in fondo, INTELLIGENCE sulla curva
                if k > 0 && elenco[k - 1].gruppo != elenco[k].gruppo {
                    try? await Task.sleep(for: .milliseconds(110))      // un respiro tra un gruppo e l'altro
                }
                withAnimation(.spring(duration: 0.4, bounce: 0.55)) { accese = k + 1 }
                Suoni.plim(k)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
                try? await Task.sleep(for: .milliseconds(150))
            }
            try? await Task.sleep(for: .milliseconds(120))
            Suoni.inLinea()
            withAnimation(.easeOut(duration: 0.3)) { sottotitolo = "SISTEMI IN LINEA" }
            try? await Task.sleep(for: .milliseconds(2400))
            withAnimation(.easeOut(duration: 0.6)) { sottotitolo = "MARK VI-4.0" }
        }
    }

    private func eseguiComando() {
        guard let r = comandi.richiesta, !Portachiavi.leggi().isEmpty else { return }
        comandi.richiesta = nil
        switch r {
        case .ascolta:
            jarvis.interrompi()
            jarvis.ascoltaSubito()
        case .briefing:
            Task { await jarvis.invia("Buongiorno Jarvis, il briefing per favore.") }
        case .leggi(let testo):
            jarvis.leggi(testo)
        case .diario(let domanda):
            jarvis.chiediDiario(domanda)
        case .guarda:
            jarvis.interrompi()
            jarvis.guardaAutomatico()
        case .beaSOS(let lat, let lon, let prova, let id):
            jarvis.interrompi()
            scheda = nil
            aiutoBea = AiutoBea(lat: lat, lon: lon, prova: prova)
            // visto: il cervello segna che l'avviso è stato aperto
            if id > 0 { Task { _ = await VistaVitals.chiama(["bea_sos_visto": id]) } }
            jarvis.leggi(prova ? "Prova del Tocco d'aiuto di Bea, Sir: funziona." : "Sir, Bea ha chiesto aiuto. La chiami subito.")
        }
    }

    private var suggerimento: String {
        switch jarvis.fase {
        case .attesa: return "Tocchi il reattore e parli"
        case .ascolto: return "La ascolto, signore…"
        case .elaboro: return "Un momento…"
        case .parlo: return "Tocchi il reattore per interrompermi"
        }
    }

    private var intestazione: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("J.A.R.V.I.S.")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(.white)
                    .shadow(color: .ciano.opacity(0.5), radius: 10)
                Text(sottotitolo)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(sottotitolo == "MARK VI-4.0" ? Color.tenue : Color.ciano)
                    .contentTransition(.numericText())
                    .id(sottotitolo)
                    .transition(.opacity)
            }
            .opacity(acceso ? 1 : 0)
            .offset(x: acceso ? 0 : -12)
            Spacer()
            Button { Suoni.tocco(); jarvis.interrompi(); withAnimation(.spring(duration: 0.35, bounce: 0.2)) { mostraSistemi.toggle() } } label: {
                Image(systemName: "server.rack")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.ciano)
                    .padding(10)
                    .background(Color.ciano.opacity(mostraSistemi ? 0.15 : 0))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Sistemi")
            Button { Suoni.tocco(); chiediPulizia = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 19))
                    .foregroundStyle(Color.ciano)
                    .padding(10)
            }
            .accessibilityLabel("Pulisci la conversazione")
            .confirmationDialog("Pulire la conversazione?", isPresented: $chiediPulizia, titleVisibility: .visible) {
                Button("Pulisci", role: .destructive) { jarvis.nuovaConversazione() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Memoria e note di JARVIS restano: si cancella solo la chat sullo schermo.")
            }
            Button { Suoni.tocco(); mostraImpostazioni = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.ciano)
                    .padding(10)
                    .rotationEffect(.degrees(mostraImpostazioni ? 90 : 0))
                    .animation(.spring(duration: 0.5), value: mostraImpostazioni)
            }
            .accessibilityLabel("Impostazioni")
        }
        .buttonStyle(StileStark())
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Scorciatoie in alto: per aggiungere una funzione nuova basta una riga in più qui.
    /// In quattro gruppi, separati da una linea sottile:
    /// LA GIORNATA (cosa c'è oggi) · IL SIGNORE (come sta) · I SENSI (cosa vede e sente JARVIS) · STRUMENTI.
    /// In quattro gruppi lungo i tre quarti di cerchio attorno al reattore, da sinistra in basso verso destra in basso:
    /// SIGNORE (come sta) · DAILY (la giornata) · SENSI (cosa vede e sente JARVIS) · STRUMENTI.
    private var scorciatoie: [(gruppo: String, icona: String, nome: String, azione: () -> Void)] {
        [
            ("SIGNORE", "book.closed", "Diario", { tastiera = false; scheda = .diario }),
            ("SIGNORE", "person.2.wave.2", "Confidente", { tastiera = false; mostraConfidente = true }),
            ("SIGNORE", "waveform.path.ecg", "Vitals", { tastiera = false; mostraVitals = true }),
            ("SIGNORE", "bed.double", "Sonno", { tastiera = false; scheda = .sonno }),
            ("SIGNORE", "heart", "Cuore", { tastiera = false; scheda = .cuore }),
            ("SIGNORE", "figure.pilates", "Allenatore", { tastiera = false; jarvis.interrompi(); jarvis.allenatore = true }),

            ("DAILY", "sun.horizon", "Briefing", { tastiera = false; scheda = .briefing }),
            ("DAILY", "cloud.sun", "Meteo", { tastiera = false; scheda = .meteo }),
            ("DAILY", "envelope.badge", "Email", { tastiera = false; scheda = .email }),
            ("DAILY", "envelope", "Messaggi", { tastiera = false; scheda = .messaggi }),
            ("DAILY", "cart", "Spesa", { tastiera = false; scheda = .spesa }),

            ("SENSI", "eye", "Occhi", { tastiera = false; jarvis.guardaManuale() }),
            ("SENSI", "fork.knife", "Cucina", { tastiera = false; jarvis.guardaCucina() }),
            ("SENSI", "barcode.viewfinder", "Scanner", { tastiera = false; scheda = .scanner }),
            ("SENSI", "shazam.logo", "Shazam", { tastiera = false; jarvis.interrompi(); scheda = .shazam }),
            ("SENSI", "photo.on.rectangle", "Foto", { tastiera = false; scheda = .foto }),

            ("STRUMENTI", "brain.head.profile", "Ricordi", { tastiera = false; mostraRicordi = .ricordi }),
            ("STRUMENTI", "globe.europe.africa", "Interprete", { tastiera = false; scegliLingua = true }),
            ("STRUMENTI", "globe", "Browser", { mostraBrowser = true }),
            ("STRUMENTI", "music.note.list", "Serata", { tastiera = false; scheda = .serata }),
            ("STRUMENTI", "phone", "Telefono", { tastiera = false; scheda = .telefono }),
            ("STRUMENTI", "link", "Bea", { tastiera = false; scheda = .bea }),
        ]
    }

    private func chiedi(_ frase: String) {
        tastiera = false
        Task { await jarvis.invia(frase) }
    }

    /// Le icone in corona attorno al reattore, divise per gruppo con un arco e il nome del gruppo.
    /// All'avvio ogni icona appare grande e trasparente e in pochi millisecondi si restringe e si accende, una dopo l'altra.
    private static let raggioCorona: CGFloat = 160
    private static let latoCorona: CGFloat = 372

    /// Angolo (in radianti) di ogni icona sui tre quarti di cerchio: da sinistra in basso, su per la sinistra,
    /// sopra il reattore e giù per la destra. Il quarto in basso resta libero per la chat.
    /// I gruppi occupano archi proporzionali, separati da un vuoto.
    private var angoli: [Double] {
        let elenco = scorciatoie
        let gruppi = elenco.map(\.gruppo).reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }
        let inizio = 0.75 * .pi, fine = 2.25 * .pi                      // 135° → 405°, sul lato in basso niente
        let vuoto = 0.04 * 2 * .pi                                       // spazio tra un gruppo e l'altro
        let utile = (fine - inizio) - vuoto * Double(gruppi.count - 1)
        let passo = utile / Double(elenco.count - 1)
        var out: [Double] = []
        var a = inizio
        for (k, s) in elenco.enumerated() {
            if k > 0 && elenco[k - 1].gruppo != s.gruppo { a += vuoto }
            out.append(a)
            a += passo
        }
        // il passo è calcolato sugli intervalli tra le icone: l'ultima cade esattamente a 405°
        // INTELLIGENCE chiude il cerchio in basso (90°), con lo stesso passo della corona
        let centro = 2.5 * Double.pi
        let n = intelligence.count
        for j in 0..<n { out.append(centro + (Double(j) - Double(n - 1) / 2) * passo) }
        return out
    }

    /// La corona più INTELLIGENCE, nell'ordine di accensione.
    private var tutteLeIcone: [(gruppo: String, icona: String, nome: String, azione: () -> Void)] {
        scorciatoie + intelligence.map { (gruppo: "INTELLIGENCE", icona: $0.icona, nome: $0.nome, azione: $0.azione) }
    }

    private var corona: some View {
        let elenco = tutteLeIcone
        let ang = angoli
        let r = ContentView.raggioCorona
        // il cerchio ora è intero: in basso c'è INTELLIGENCE, con il suo nome sotto le icone
        let altezza = ContentView.latoCorona / 2 + r + 40
        return ZStack {
            // archi e nomi dei gruppi, sotto le icone
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var k = 0
                while k < elenco.count {
                    var fine = k
                    while fine + 1 < elenco.count && elenco[fine + 1].gruppo == elenco[k].gruppo { fine += 1 }
                    let acceso = fine < accese
                    let da = ang[k] - 0.09, a = ang[fine] + 0.09
                    var arco = Path()
                    arco.addArc(center: c, radius: r, startAngle: .radians(da), endAngle: .radians(a), clockwise: false)
                    gc.stroke(arco, with: .color(Color.ciano.opacity(acceso ? 0.35 : 0.08)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    let medio = (ang[k] + ang[fine]) / 2
                    // il nome corre lungo l'arco, appena fuori dalle icone, sempre leggibile da sinistra a destra
                    var rotazione = medio + .pi / 2
                    if cos(rotazione) < 0 { rotazione += .pi }
                    var testo = gc
                    testo.translateBy(x: c.x + (r + 27) * cos(medio), y: c.y + (r + 27) * sin(medio))
                    testo.rotate(by: .radians(rotazione))
                    testo.draw(Text(elenco[k].gruppo).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Color.tenue.opacity(acceso ? 1 : 0)), at: .zero)
                    k = fine + 1
                }
            }
            .allowsHitTesting(false)

            // il reattore al centro, della misura di sempre
            Button { tastiera = false; jarvis.toccaReattore() } label: {
                ZStack {
                    AnelliHUD(fase: jarvis.fase).frame(width: 290, height: 290)
                    Reattore(fase: jarvis.fase).frame(width: 220, height: 220)
                }
                .frame(width: 240, height: 240)
            }
            .buttonStyle(StileStark())
            .scaleEffect(acceso ? 1 : 0.7)
            .opacity(acceso ? 1 : 0)
            .accessibilityLabel("Parla con Jarvis")

            // le icone
            ForEach(Array(elenco.enumerated()), id: \.offset) { k, s in
                let inCorso = iconaAttiva == k && jarvis.fase != .attesa
                let accesa = k < accese
                Button {
                    Suoni.tocco()
                    if ["Occhi", "Cucina"].contains(s.nome) { iconaAttiva = k }
                    s.azione()
                } label: {
                    Group {
                        if s.icona == "profiler" { IconaProfiler() } else { Image(systemName: s.icona) }
                    }
                        .font(.system(size: 15))
                        .symbolRenderingMode(.monochrome)                 // tutte dello stesso colore (Serata e Shazam compresi)
                        .symbolEffect(.pulse, options: .repeating, isActive: inCorso)
                        .frame(width: 38, height: 38)
                        .background(Color.fondo.opacity(0.85))
                        .background(Color.ciano.opacity(inCorso ? 0.25 : 0.08))
                        .overlay(Circle().stroke(Color.ciano.opacity(inCorso ? 0.95 : 0.4), lineWidth: inCorso ? 1.3 : 0.8))
                        .overlay(AnelloScansione(attivo: inCorso).clipShape(Circle()))
                        .clipShape(Circle())
                        .shadow(color: .ciano.opacity(inCorso ? 0.7 : 0), radius: 8)
                        .foregroundStyle(Color.ciano)
                }
                .buttonStyle(StileStark())
                .accessibilityLabel(s.nome)
                .disabled(jarvis.fase == .elaboro && s.nome != "Browser" && s.gruppo != "INTELLIGENCE")
                .opacity(accesa ? 1 : 0)
                .scaleEffect(accesa ? 1 : 2.4)                      // grande e trasparente, poi si restringe e si accende
                .brightness(k == accese - 1 && accese < elenco.count ? 0.35 : 0)   // lampo solo mentre si accende: l'ultima non resta chiara
                .animation(.spring(duration: 0.32, bounce: 0.25), value: accese)
                .offset(x: r * CGFloat(cos(ang[k])), y: r * CGFloat(sin(ang[k])))
            }
        }
        .frame(maxWidth: .infinity).frame(height: ContentView.latoCorona)          // largo quanto lo schermo: i nomi non vengono tagliati
        .frame(maxWidth: .infinity).frame(height: altezza, alignment: .top)       // sotto resta lo spazio per la chat
    }

    /// INTELLIGENCE: il reparto speciale, una fila centrata sotto il reattore. Si accende dopo la corona,
    /// con lo stesso «plim», lo stesso ingresso (grande e trasparente → piccola e nitida) e lo stesso tocco.
    private var intelligence: [(icona: String, nome: String, azione: () -> Void)] {
        [
            ("dot.radiowaves.left.and.right", "Sentinella", { tastiera = false; jarvis.interrompi(); mostraSentinella = true }),
            ("profiler", "Profiler", { tastiera = false; jarvis.interrompi(); profiler() }),
            ("waveform.and.mic", "Wiretap", { tastiera = false; jarvis.interrompi(); mostraWiretap = true }),
        ]
    }

    /// Apre un reparto chiesto a voce; se ce n'è già uno aperto, prima lo chiude.
    private func apriReparto(_ r: Reparto) {
        let aperto = mostraSentinella || mostraWiretap || mostraProfiler || scheda != nil || jarvis.occhi != nil
            || mostraVitals || mostraConfidente || mostraRicordi != nil || mostraBrowser || jarvis.allenatore
        mostraSentinella = false
        mostraWiretap = false
        mostraProfiler = false
        scheda = nil
        mostraVitals = false
        mostraConfidente = false
        mostraRicordi = nil
        mostraBrowser = false
        mostraSistemi = false
        jarvis.allenatore = false
        jarvis.occhiChiusi([])
        Task {
            if aperto { try? await Task.sleep(for: .milliseconds(700)) }     // il tempo che la schermata si chiuda
            switch r {
            case .sentinella: mostraSentinella = true
            case .wiretap: mostraWiretap = true
            case .profiler: profiler()
            case .occhi: jarvis.guardaManuale()
            case .giro: jarvis.giroAVoce()
            case .cucina: jarvis.guardaCucina()
            case .scanner: scheda = .scanner
            case .diario: scheda = .diario
            case .sonno: scheda = .sonno
            case .cuore: scheda = .cuore
            case .briefing: scheda = .briefing
            case .meteo: scheda = .meteo
            case .email: scheda = .email
            case .spesa: scheda = .spesa
            case .shazam: scheda = .shazam
            case .foto: scheda = .foto
            case .serata: scheda = .serata
            case .messaggi: scheda = .messaggi
            case .telefono: scheda = .telefono
            case .github: scheda = .github
            case .supabase: scheda = .supabase
            case .archivio: scheda = .archivio
            case .vitals: mostraVitals = true
            case .confidente: mostraConfidente = true
            case .allenatore: jarvis.allenatore = true
            case .bea: scheda = .bea
            case .ricordi: mostraRicordi = .ricordi
            case .interprete: scegliLingua = true
            case .browser: mostraBrowser = true
            }
        }
    }

    /// Un comando detto dentro un reparto («Jarvis, torna», «Jarvis, apri il Wiretap»).
    private func comandoDaReparto(_ c: ComandoVocale) {
        switch c {
        case .torna:
            mostraSentinella = false
            mostraWiretap = false
            mostraProfiler = false
            scheda = nil
        case .apri(let r):
            apriReparto(r)
        }
    }

    /// Profiler: la sua schermata, con la scheda da compilare dopo lo scatto.
    private func profiler() { mostraProfiler = true }

    /// Da una scheda: chiude la scheda e passa la frase a JARVIS.
    private func daScheda(_ frase: String) {
        scheda = nil
        chiedi(frase)
    }

    /// Da una scheda: chiude la scheda e apre la pagina nel browser interno.
    private func apriPagina(_ url: URL) {
        scheda = nil
        Task { try? await Task.sleep(for: .milliseconds(450)); jarvis.pagina = PaginaWeb(url: url) }
    }

    /// SISTEMI: il reparto tecnico, dal tasto in alto. Un menu da HUD con GitHub, Supabase e Archivio,
    /// ognuno con una riga di stato viva (letta dal cervello all'apertura).
    private var menuSistemi: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001).ignoresSafeArea()
                .onTapGesture { withAnimation(.spring(duration: 0.3)) { mostraSistemi = false } }
            VStack(alignment: .leading, spacing: 2) {
                Text("SISTEMI")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(Color.ciano)
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                voceSistemi(logo: "github-logo", simbolo: nil, nome: "GitHub", stato: statoSistemi["github"] ?? "…") { scheda = .github }
                voceSistemi(logo: "supabase-logo", simbolo: nil, nome: "Supabase", stato: statoSistemi["supabase"] ?? "…") { scheda = .supabase }
                voceSistemi(logo: nil, simbolo: "archivio", nome: "Archivio", stato: statoSistemi["archivio"] ?? "…") { scheda = .archivio }
                voceSistemi(logo: UIImage(named: "langfuse-logo") != nil ? "langfuse-logo" : nil, simbolo: "costi", nome: "Costi", stato: statoSistemi["costi"] ?? "…") { scheda = .costi }
            }
            .padding(6)
            .frame(width: 262)
            .background(Color.fondo.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
            .padding(.trailing, 16)
            .padding(.top, 56)
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
        .task { await caricaStatoSistemi() }
    }

    private func voceSistemi(logo: String?, simbolo: String?, nome: String, stato: String, azione: @escaping () -> Void) -> some View {
        Button {
            Suoni.tocco()
            withAnimation(.spring(duration: 0.3)) { mostraSistemi = false }
            tastiera = false
            azione()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let logo {
                        Image(logo).resizable().renderingMode(.template).scaledToFit()
                    } else if simbolo == "costi" {
                        Image(systemName: "gauge.with.dots.needle.33percent").resizable().scaledToFit()
                    } else {
                        IconaArchivio()
                    }
                }
                .foregroundStyle(Color.ciano)
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nome).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Text(stato).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
    }

    /// Le righe di stato del menu: chiamate leggere al cervello, una dopo l'altra (i costi per ultimi: sono i più lenti).
    private func caricaStatoSistemi() async {
        let ra = await VistaVitals.chiama(["archivio": true])
        let rs = await VistaVitals.chiama(["supabase": true, "ore": 24])
        let rg = await VistaVitals.chiama(["github": true])
        if let ra, ra["errore"] == nil {
            let file = ra["file"] as? [[String: Any]] ?? [], cartelle = ra["cartelle"] as? [[String: Any]] ?? []
            statoSistemi["archivio"] = "\(file.count) file · \(cartelle.count) cartelle"
        } else { statoSistemi["archivio"] = "non raggiungibile" }
        if let rs {
            if let e = rs["errore"] as? String { statoSistemi["supabase"] = e.contains("manca") ? "non collegato" : "non raggiungibile" }
            else {
                let log = rs["log"] as? [String: Any]
                let errori = ((log?["richieste"] as? [[String: Any]])?.count ?? 0) + ((log?["console"] as? [[String: Any]])?.count ?? 0)
                let mb = (rs["database_mb"] as? NSNumber)?.doubleValue ?? 0
                statoSistemi["supabase"] = "\(errori == 0 ? "nessun errore" : "\(errori) errori") · \(Int(mb)) MB"
            }
        } else { statoSistemi["supabase"] = "cervello non raggiungibile" }
        if let rg {
            if let e = rg["errore"] as? String { statoSistemi["github"] = e.contains("manca") ? "non collegato" : "non raggiungibile" }
            else {
                let repo = rg["repository"] as? [[String: Any]] ?? []
                let issue = repo.reduce(0) { $0 + (($1["issue_aperte"] as? NSNumber)?.intValue ?? 0) }
                statoSistemi["github"] = "\(repo.count) repository · \(issue) issue aperte"
            }
        } else { statoSistemi["github"] = "cervello non raggiungibile" }
        if let c = await VistaVitals.chiama(["consumi": true]), c["errore"] == nil {
            let oggi = (c["dollari_oggi"] as? NSNumber)?.doubleValue ?? 0, mese = (c["dollari_mese"] as? NSNumber)?.doubleValue ?? 0
            statoSistemi["costi"] = String(format: "oggi %.2f · mese %.2f $", oggi, mese).replacingOccurrences(of: ".", with: ",")
        } else { statoSistemi["costi"] = "non raggiungibile" }
    }

    private var registro: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(jarvis.messaggi) { m in
                        RigaMessaggio(m: m).id(m.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: jarvis.messaggi.count) {
                if let ultimo = jarvis.messaggi.last {
                    withAnimation { proxy.scrollTo(ultimo.id, anchor: .bottom) }
                }
            }
            .onAppear {
                if let ultimo = jarvis.messaggi.last { proxy.scrollTo(ultimo.id, anchor: .bottom) }
            }
        }
    }

    private var barraTesto: some View {
        VStack(spacing: 6) {
            if let dati = jarvis.foto, let img = UIImage(data: dati) {
                HStack(spacing: 10) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Foto pronta: mi dica cosa vuole sapere, o invii così.")
                        .font(.footnote).foregroundStyle(Color.tenue)
                    Spacer()
                    Button { jarvis.foto = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) }
                        .accessibilityLabel("Togli la foto")
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
            Menu {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { sorgenteFoto = .camera } label: { Label("Scatta una foto", systemImage: "camera") }
                }
                Button { sorgenteFoto = .photoLibrary } label: { Label("Scegli dalla libreria", systemImage: "photo") }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.ciano)
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.11, green: 0.21, blue: 0.25)))
            }
            .accessibilityLabel("Fotocamera")
            TextField("Oppure scriva qui, signore…", text: $testo, axis: .vertical)
                .lineLimit(1...4)
                .focused($tastiera)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(red: 0.04, green: 0.12, blue: 0.15).opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.11, green: 0.21, blue: 0.25)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button {
                let t = testo
                testo = ""
                Task { await jarvis.invia(t) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.fondo)
                    .frame(width: 44, height: 44)
                    .background(Color.ciano2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled((testo.trimmingCharacters(in: .whitespaces).isEmpty && jarvis.foto == nil) || jarvis.fase == .elaboro)
            .accessibilityLabel("Invia")
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }
}

/// Anelli da HUD attorno al reattore: tre corone con tacche e segmenti che girano a velocità diverse,
/// più veloci quando JARVIS pensa, arancioni quando lavora. Puro contorno: il reattore resta il cuore.
struct AnelliHUD: View {
    let fase: Fase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let caldo = fase == .elaboro || fase == .parlo
            let fretta: Double = fase == .elaboro ? 2.2 : (fase == .ascolto ? 1.4 : 1)
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = Double(min(size.width, size.height)) / 2
                let base = caldo ? Color.orange : Color.ciano
                // corona esterna: 72 tacche, ogni sesta più lunga, che scorrono piano
                for k in 0..<72 {
                    let th = Double(k) / 72 * 2 * .pi + t * 0.05 * fretta
                    let lunga = k % 6 == 0
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + R * 0.97 * cos(th), y: c.y + R * 0.97 * sin(th)))
                    p.addLine(to: CGPoint(x: c.x + R * (lunga ? 0.91 : 0.945) * cos(th), y: c.y + R * (lunga ? 0.91 : 0.945) * sin(th)))
                    gc.stroke(p, with: .color(base.opacity(lunga ? 0.55 : 0.25)), lineWidth: lunga ? 1.4 : 0.8)
                }
                // segmenti che girano in senso opposto su due raggi
                let segmenti: [(Double, Double, Double, Int)] = [(0.88, 0.35, 0.18, 3), (0.80, -0.6, 0.08, 5)]
                for (fr, vel, lung, quanti) in segmenti {
                    for q in 0..<quanti {
                        let inizio = Angle(radians: t * vel * fretta + Double(q) * 2 * .pi / Double(quanti))
                        var arco = Path()
                        arco.addArc(center: c, radius: R * fr, startAngle: inizio, endAngle: inizio + .radians(2 * .pi * lung), clockwise: false)
                        gc.stroke(arco, with: .color(base.opacity(0.5)), style: StrokeStyle(lineWidth: fr > 0.85 ? 2.2 : 1.2, lineCap: .round))
                    }
                }
                // piccoli numeri «telemetrici» ai quattro punti cardinali
                let etichette = ["0", "90", "180", "270"]
                for (n, e) in etichette.enumerated() {
                    let th = Double(n) * .pi / 2 - .pi / 2 + t * 0.05 * fretta
                    let pt = CGPoint(x: c.x + R * 0.86 * cos(th), y: c.y + R * 0.86 * sin(th))
                    gc.draw(Text(e).font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(base.opacity(0.6)), at: pt)
                }
            }
            .animation(.easeInOut(duration: 0.8), value: caldo)
        }
        .allowsHitTesting(false)
    }
}

/// Una riga di telemetria che cambia ogni pochi secondi, come i dati che scorrono nell'armatura.
struct TelemetriaHUD: View {
    let fase: Fase
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.5)) { ctx in
            let k = Int(ctx.date.timeIntervalSinceReferenceDate / 2.5)
            let ora = Date().formatted(.dateTime.hour().minute().second())
            let voci = ["SISTEMI NOMINALI", "VOCE \(Impostazioni.voceCloud ? "CLOUD" : "LOCALE")", "ORECCHIO \(Impostazioni.interruzioneVocale ? "ATTIVO" : "SPENTO")",
                        "MEMORIA SINCRONIZZATA", "T \(ora)", "MARK VI-4.0 · BUILD \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")"]
            let riga = fase == .elaboro ? "ELABORAZIONE IN CORSO" : (fase == .ascolto ? "CANALE AUDIO APERTO" : voci[k % voci.count])
            Text(riga)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.tenue)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: riga)
                .id(riga)
        }
    }
}

/// Tasti alla Stark: si schiacciano, si illuminano e tornano su con una molla.
/// L'icona del Profiler, disegnata a mano: il fascicolo del dossier con la sagoma e le righe della scheda. Ferma.
struct IconaProfiler: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 7, y: 0)); p.addLine(to: CGPoint(x: 9, y: 2.5))
                p.addLine(to: CGPoint(x: 20, y: 2.5)); p.addLine(to: CGPoint(x: 20, y: 15)); p.addLine(to: CGPoint(x: 0, y: 15))
                p.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            Image(systemName: "person.fill").font(.system(size: 7, weight: .semibold))
                .position(x: 5.5, y: 9)
            ForEach(0..<3, id: \.self) { k in
                Capsule().frame(width: 7, height: 1.1).opacity(0.75)
                    .position(x: 14.5, y: 6.5 + Double(k) * 2.8)
            }
        }
        .frame(width: 20, height: 15)
    }
}

/// Archivio: una cartella con una piccola nuvola, nello stile delle altre icone.
struct IconaArchivio: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 5)); p.addLine(to: CGPoint(x: 6.5, y: 5)); p.addLine(to: CGPoint(x: 8.5, y: 7.5))
                p.addLine(to: CGPoint(x: 21, y: 7.5)); p.addLine(to: CGPoint(x: 21, y: 19)); p.addLine(to: CGPoint(x: 0, y: 19))
                p.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
            Image(systemName: "cloud.fill").font(.system(size: 8, weight: .semibold))
                .position(x: 15, y: 3.5)
        }
        .frame(width: 21, height: 19)
    }
}

struct StileStark: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .brightness(configuration.isPressed ? 0.25 : 0)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

/// Una riga di luce che scorre dall'alto in basso sull'icona in lavorazione, come una scansione.
struct AnelloScansione: View {
    let attivo: Bool
    var body: some View {
        if attivo {
            TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let y = (t * 0.9).truncatingRemainder(dividingBy: 1)
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.ciano.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                        .offset(y: CGFloat(y) * (g.size.height + 8) - 8)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct RigaMessaggio: View {
    let m: Messaggio
    var body: some View {
        let jarvis = m.ruolo == "assistant"
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(jarvis ? Color.ciano : Color(red: 0.11, green: 0.21, blue: 0.25))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(jarvis ? "JARVIS" : "SIGNORE") · \(m.data.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(jarvis ? Color.ciano : Color.tenue)
                Text(m.testo.isEmpty ? "…" : (m.conFoto ? "📷 " + m.testo : m.testo))
                    .font(.system(size: 16))
                    .foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
                    .textSelection(.enabled)
                if let immagini = m.immagini, !immagini.isEmpty {
                    GalleriaMessaggio(immagini: immagini)
                        .padding(.top, 2)
                }
                if !m.azioni.isEmpty {
                    Text("▸ " + descriviAzioni(m.azioni))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(red: 0.36, green: 0.42, blue: 0.23))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ImpostazioniView: View {
    @EnvironmentObject var jarvis: Jarvis
    @Environment(\.dismiss) private var chiudi
    @AppStorage("indirizzo") private var indirizzo = Impostazioni.indirizzoPredefinito
    @AppStorage("voce") private var voce = ""
    @AppStorage("muto") private var muto = false
    @AppStorage("ascoltaApertura") private var ascoltaApertura = true
    @AppStorage("voceCloud") private var voceCloud = true
    @AppStorage("idVoceCloud") private var idVoceCloud = ""
    @AppStorage("interruzioneVocale") private var interruzioneVocale = true
    @AppStorage("richiamo") private var richiamo = true
    @AppStorage("ascoltoSempre") private var ascoltoSempre = true
    @AppStorage("battitoMani") private var battitoMani = true
    @AppStorage("suoni") private var suoni = true
    @AppStorage("suonoAvvio") private var suonoAvvio = "hud"
    @State private var parola = Portachiavi.leggi()
    @State private var voci: [AVSpeechSynthesisVoice] = []
    @State private var vociCloud: [VoceRemota] = []
    @State private var statoCloud = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Parola d'ordine", text: $parola)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: { Text("Accesso") } footer: {
                    Text("La stessa impostata come JARVIS_TOKEN su Supabase. Resta nel portachiavi dell'iPhone.")
                }

                Section {
                    Toggle("Voce di JARVIS (cloud)", isOn: $voceCloud)
                    if voceCloud {
                        Picker("Voce cloud", selection: $idVoceCloud) {
                            Text("Predefinita").tag("")
                            ForEach(vociCloud) { v in
                                Text(v.descrizione?.isEmpty == false ? "\(v.nome) · \(v.descrizione!)" : v.nome).tag(v.id)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        if !statoCloud.isEmpty {
                            Text(statoCloud).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Voce di JARVIS") } footer: {
                    Text("Voce neurale ElevenLabs, generata dal cervello. Se il cloud non risponde, JARVIS usa la voce dell'iPhone qui sotto.")
                }
                .task(id: voceCloud) { await caricaVociCloud() }

                Section("Voce dell'iPhone") {
                    Picker("Voce", selection: $voce) {
                        Text("Automatica (la migliore installata)").tag("")
                        ForEach(voci, id: \.identifier) { v in
                            Text("\(v.name) · \(qualita(v))").tag(v.identifier)
                        }
                    }
                    Toggle("Silenzioso (solo testo)", isOn: $muto)
                    Toggle("In ascolto appena si apre", isOn: $ascoltaApertura)
                    Button("Prova la voce") {
                        Task { await jarvis.parla("Buonasera signore. Sistemi in linea, e pronto a servirla.") }
                    }
                }

                Section {
                    Toggle("Interruzione a voce", isOn: $interruzioneVocale)
                    Toggle("Richiamo «Jarvis» senza toccare", isOn: $richiamo)
                    if richiamo { Toggle("Risponde a qualsiasi frase (non solo «Jarvis»)", isOn: $ascoltoSempre) }
                    if richiamo { Toggle("Due battiti di mani per chiamarlo", isOn: $battitoMani) }
                    NavigationLink("La mia voce") { VistaLaMiaVoce() }
                    Toggle("Suoni dell'interfaccia", isOn: $suoni)
                    if suoni {
                        Picker("Suono delle icone all'avvio", selection: $suonoAvvio) {
                            Text("HUD (tick digitali)").tag("hud")
                            Text("Note").tag("note")
                            Text("Nessuno").tag("off")
                        }
                    }
                } header: { Text("Alla Stark") } footer: {
                    Text("Con l'interruzione a voce, mentre JARVIS parla basta dire «Jarvis», «basta» o «aspetta» per zittirlo e prendere la parola. L'iPhone tiene acceso il microfono mentre lui parla; se la voce le sembra meno piena, la spenga. Con il richiamo, quando JARVIS è in attesa e l'app è aperta basta dire «Jarvis, …»: le altre voci vengono ignorate. Il microfono resta acceso, quindi consuma un po' più di batteria.")
                }

                Section {
                    TextField("Indirizzo", text: $indirizzo)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                } header: { Text("Cervello") } footer: {
                    Text("Le voci Premium si scaricano da Impostazioni › Accessibilità › Contenuti letti › Voci › Italiano.")
                }

                Section {
                    Text("«Ehi Siri, parla con Jarvis» · «Ehi Siri, buongiorno Jarvis»")
                        .font(.footnote)
                    Text("Tasto Azione: Impostazioni › Tasto Azione › Comando rapido › Jarvis › Parla con Jarvis")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Siri e tasto Azione") }

                Section {
                    Text("Comando rapido «\(Strumenti.comandoInvio)»: riceve numero e testo e invia SMS o iMessage senza chiedere conferma.")
                        .font(.footnote)
                    Text("Briefing: automazione «Sveglia › Quando viene interrotta» › Briefing di Jarvis.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Meteo locale fornito da \u{F8FF} Meteo.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Automazioni") }

                Section {
                    Button("Nuova conversazione", role: .destructive) { jarvis.nuovaConversazione() }
                } footer: {
                    Text("Cancella la cronologia sull'iPhone. Note e memoria di JARVIS restano nel cervello.")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        Portachiavi.salva(parola.trimmingCharacters(in: .whitespacesAndNewlines))
                        chiudi()
                    }
                }
            }
            .onAppear { voci = Jarvis.vociItaliane() }
        }
    }

    private func caricaVociCloud() async {
        guard voceCloud else { return }
        statoCloud = "Cerco le voci…"
        if let elenco = await VoceCloud.elencoVoci() {
            vociCloud = elenco
            statoCloud = elenco.isEmpty ? "Attiva, con la voce scelta nel cervello. Le voci dell'account non si vedono: alla chiave ElevenLabs forse manca il permesso «Voices · Read»." : "Attiva · \(elenco.count) voci disponibili."
        } else {
            statoCloud = "Non ancora attiva: manca la chiave ElevenLabs nel cervello. Intanto parla la voce dell'iPhone."
        }
    }

    private func qualita(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "Premium"
        case .enhanced: return "Ottimizzata"
        default: return "Base"
        }
    }
}

// Registro di bordo leggibile: «dati_leggi ×6» diventa «ha consultato le serate (6 letture)»
func descriviAzioni(_ azioni: [String]) -> String {
    let nomi: [String: (String, String)] = [
        "dati_leggi": ("ha consultato le serate", "letture"),
        "serata_riepilogo": ("ha fatto i conti della serata", "serate"),
        "note_salva": ("ha salvato una nota", "note"),
        "note_cerca": ("ha consultato le note", "ricerche"),
        "note_completa": ("ha aggiornato una nota", "note"),
        "memoria_salva": ("se l'è segnato in memoria", "ricordi"),
        "memoria_dimentica": ("ha dimenticato", "ricordi"),
        "web_search": ("ha cercato sul web", "ricerche"),
        "meteo": ("ha guardato il meteo", "controlli"),
        "discogs_cerca": ("ha cercato su Discogs", "ricerche"),
        "calendario_crea": ("ha segnato in calendario", "eventi"),
        "calendario_leggi": ("ha guardato il calendario", "letture"),
        "promemoria_crea": ("ha creato un promemoria", "promemoria"),
        "contatti_cerca": ("ha cercato in rubrica", "ricerche"),
        "chiama": ("ha preparato la chiamata", "chiamate"),
        "messaggio": ("ha preparato il messaggio", "messaggi"),
        "naviga": ("ha preparato il percorso", "percorsi"),
        "invia_messaggio": ("ha inviato il messaggio", "messaggi"),
        "riconosci_musica": ("ha ascoltato la musica", "ascolti"),
        "apri_apple_music": ("ha aperto Apple Music", "volte"),
        "immagini_cerca": ("ha cercato immagini", "ricerche"),
        "foto_cerca": ("ha cercato tra le sue foto", "ricerche"),
        "apri_pagina": ("ha aperto la pagina", "pagine"),
        "salute_battito": ("ha letto i battiti", "letture"),
        "musica_riproduci": ("ha messo la musica", "brani"),
        "musica_controllo": ("ha comandato la musica", "comandi"),
        "meteo_qui": ("ha guardato il cielo qui", "controlli"),
        "bar_magazzino": ("ha controllato bar e magazzino", "controlli"),
    ]
    var ordine: [String] = []
    var conta: [String: Int] = [:]
    for a in azioni {
        if conta[a] == nil { ordine.append(a) }
        conta[a, default: 0] += 1
    }
    return ordine.map { a in
        let (frase, unita) = nomi[a] ?? (a, "volte")
        let n = conta[a] ?? 1
        return n > 1 ? "\(frase) (\(n) \(unita))" : frase
    }.joined(separator: " · ")
}

/// Fotocamera o libreria foto (UIKit dentro SwiftUI).
struct Fotocamera: UIViewControllerRepresentable {
    let sorgente: UIImagePickerController.SourceType
    let suFoto: (UIImage) -> Void
    @Environment(\.dismiss) var chiudi

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(sorgente) ? sorgente : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinatore { Coordinatore(self) }

    final class Coordinatore: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let padre: Fotocamera
        init(_ padre: Fotocamera) { self.padre = padre }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let immagine = info[.originalImage] as? UIImage
            padre.chiudi()
            if let immagine { padre.suFoto(immagine) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { padre.chiudi() }
    }
}
