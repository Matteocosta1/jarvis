import SwiftUI
import Combine
import AVFoundation
import QuartzCore
import UIKit

/// Le schede delle icone della corona.
/// Le ultime righe di stato del menu SISTEMI, ricordate sul telefono: all'apertura si vedono subito, poi si aggiornano.
enum MemoriaSistemi {
    static func leggi() -> [String: String] {
        // le scritte d'errore salvate dalla build 11 non si mostrano più: solo dati veri
        (UserDefaults.standard.dictionary(forKey: "statoSistemi") as? [String: String] ?? [:]).filter { !$0.value.contains("raggiungibile") }
    }
    static func salva(_ stato: [String: String]) { UserDefaults.standard.set(stato, forKey: "statoSistemi") }
}

enum SchedaApp: String, Identifiable {
    case diario, sonno, cuore, briefing, meteo, email, spesa, shazam, foto, serata, messaggi, telefono, bea
    case github, supabase, archivio, costi, edith
    case scanner
    case satellite                                  // build 23: INTELLIGENCE › SATELLITE
    case musica                 // build 23: MUSICA, dall'icona in alto prima di SISTEMI
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var jarvis: Jarvis
    @ObservedObject private var comandi = Comandi.condiviso
    @AppStorage("ascoltaApertura") private var ascoltaApertura = true
    @State private var testo = ""
    @State private var mostraImpostazioni = false
    @State private var mostraBrowser = false
    @State private var aperturaPagina: AperturaPagina?   // MARK X: STUDIO e SOCIAL, la pagina del mockup (icone in alto, voce, Occhi)
    @State private var chiediPulizia = false
    @State private var sorgenteFoto: UIImagePickerController.SourceType?
    @State private var primaApertura = true
    @State private var ascoltaDopoAvvio = false      // l'ascolto all'apertura parte a sequenza finita: col microfono aperto l'iPhone abbassa l'altoparlante (e il Mac registrerebbe la musica)
    @State private var acceso = false            // sequenza di avvio: le icone si accendono una dopo l'altra
    @State private var regiaChat = RegiaChat()     // la chat che si carica all'avvio e si svuota col cestino (ChatAnimata.swift)
    @State private var sottotitolo = "AVVIO SISTEMI"
    @State private var testaArrivate = 0         // MARK X: quante icone in alto sono già arrivate (da destra, una alla volta, a tempo con l'avvio)
    @State private var bagliore = false          // MARK X: a «SISTEMI IN LINEA» il titolo prende un leggero bagliore bianco, poi resta fermo
    @State private var iconaAttiva: Int?         // scorciatoia in corso: pulsa finché JARVIS non ha finito
    @State private var scegliLingua = false       // icona Interprete: scelta della lingua
    @State private var accese = 0                 // quante icone si sono già accese all'avvio (plim, plim, plim…)
    @State private var mostraVitals = false
    @State private var mostraConfidente = false
    @State private var mostraRicordi: VistaRicordi.Scheda?
    @State private var guidaRicordi = false          // build 22: TRACCIA con la Guida già accesa («portami al luogo»)
    @State private var salvaRicordi = false          // build 22: TRACCIA salva subito il posto dove si trova («ricorda questo luogo»)
    @State private var mostraSentinella = false
    @State private var mostraWiretap = false
    @State private var mostraLidar = false            // STRUMENTI › LiDAR: la scansione della stanza
    @State private var mostraProfiler = false
    @State private var mostraSistemi = false        // il menu SISTEMI in alto: GitHub, Supabase, Archivio
    @State private var statoSistemi: [String: String] = MemoriaSistemi.leggi()   // la riga di stato sotto ogni voce del menu: le ultime lette, subito
    @State private var scheda: SchedaApp?          // le schede delle icone: Diario, Sonno, Cuore, Meteo, Spesa…
    @State private var aiutoBea: AiutoBea?          // il Tocco d'aiuto di Bea: schermata a tutto schermo
    // build 22: la tendina PROTOCOLLI, giù col dito dalla parte alta di JARVIS (titolo e reattore), su per mandarla via
    @State private var tendinaAperta = false
    @State private var tendinaTrascina: CGFloat = 0      // di quanto la sta tirando il dito (in giù da chiusa, in su da aperta)
    @State private var altezzaTendina: CGFloat = 640     // misurata appena la tendina c'è
    @ObservedObject private var protocolli = Protocolli.condiviso
    /// MARK XI: la click wheel della corona. In @State (non osservata): la leggono solo icone, archi e ologramma, non tutta la schermata.
    @State private var ruota = RuotaCorona()
    @State private var rettCorona: CGRect = .zero              // la corona sullo schermo (coordinate globali), per sapere se il dito è sull'anello
    @State private var modoCorona: ModoCorona?                 // il dito sulla corona: gira la ruota o tira giù la tendina (deciso al primo movimento)
    @State private var dock = LenteDock()
    /// MARK XI: le sezioni aperte (fino a 10), nel contenitore sopra JARVIS al posto delle schermate di iOS.
    @StateObject private var pila = PilaSezioni()
    @State private var naviga = NavigaSezioni()                // i gesti fra le sezioni (letti solo dal contenitore)
    @State private var pilaCopre = false                       // una sezione è davanti del tutto: JARVIS sotto si ferma (jarvisCoperto)
    @State private var riprendo: Sezione?                      // la sezione che torna davanti da dietro (non una richiesta nuova)                      // MARK XI: la lente del Dock in alto (anche lei non osservata qui)
    @State private var giroDavanti: [UUID] = []                // le sezioni state davanti, dall'ultima: «Jarvis, quella di prima»
    @State private var modoTestata: ModoCorona?                // il dito sulla testata: scorre sul Dock (.ruota) o tira giù la tendina
    @State private var turnoRichiamo = 0                       // 5 nov: il richiamo si riaccende a discesa della sezione finita
    private enum ModoCorona { case ruota, tendina }
    @Environment(\.scenePhase) private var scena

    /// Il richiamo «Jarvis» resta in ascolto ovunque nell'app (schede, Occhi, Cucina, Impostazioni, SISTEMI, Browser, LiDAR…),
    /// tranne dove il microfono serve già a qualcun altro: Interprete, Allenatore, Sentinella, Wiretap, Shazam, La mia voce,
    /// e (per ora) Profiler e Scanner. App in secondo piano: spento.
    private var schermoLibero: Bool {
        let inPrimoPiano: Bool = scena == .active
        let micLibero: Bool = jarvis.interprete == nil && !jarvis.allenatore && !jarvis.micOccupato && !mostraSentinella && pila.voce(.wiretap) == nil   // MARK XI: il Wiretap registra anche dietro
        let nienteEscluso: Bool = scheda != .shazam && scheda != .scanner && sorgenteFoto == nil && !mostraProfiler
        // iPhone, tastiera aperta (23 ott): JARVIS resta in attesa e appena lei parla passa in ascolto; mentre preme i tasti il microfono
        // tace (i tasti non lo fanno partire) e un attimo dopo l'ultimo tasto torna in attesa. Chiusa la tastiera: la voce di sempre
        let nonScrive: Bool = !(tastiera && scrive) || UIDevice.current.userInterfaceIdiom != .phone   // solo iPhone (iPad e Mac come prima)
        return inPrimoPiano && micLibero && nienteEscluso && nonScrive
    }

    /// La scheda aperta sopra la schermata principale, per i suoi tasti a voce («ne parliamo», «incolla», «ti penso»…).
    private var sezioneAperta: Reparto? {
        if mostraConfidente { return .confidente }
        if mostraVitals { return .vitals }
        if mostraRicordi != nil { return .ricordi }
        if let s = scheda { return Reparto(rawValue: s.rawValue) }
        return nil
    }

    /// Qualcosa è aperto sopra la schermata principale (per JARVIS: prima di aprire Occhi va chiuso).
    private var qualcosaAperto: Bool {
        scheda != nil || mostraRicordi != nil || sorgenteFoto != nil || mostraImpostazioni || mostraBrowser || mostraSentinella
            || mostraWiretap || mostraProfiler || mostraVitals || mostraConfidente || mostraLidar || mostraSistemi
            || jarvis.pagina != nil || jarvis.interprete != nil || jarvis.allenatore || scegliLingua || chiediPulizia
    }
    @FocusState private var tastiera: Bool
    /// Sta premendo i tasti: vero a ogni tasto, torna falso 1,2 secondi dopo l'ultimo (e subito con Invia o con la tastiera chiusa).
    /// Con la tastiera aperta e `scrive` falso JARVIS è in attesa come sempre: qualsiasi frase lo mette in ascolto.
    @State private var scrive = false
    @State private var giroTasti = 0                     // ogni tasto ha il suo numero: l'attesa riparte solo dopo l'ultimo
    /// Il reattore grande al centro (falso: è in piccolo in alto). Segue la tastiera: quando scende rientra insieme a lei,
    /// con la sua stessa durata e curva (keyboardWillHide), in un movimento solo.
    @State private var reattoreGrande = true
    /// La curva della tastiera di iOS (parte veloce e si posa piano, circa 0,25 s): reattore, riga di stato e chat si muovono con lei.
    static let curvaTastiera: Animation = .timingCurve(0.38, 0.7, 0.125, 1, duration: 0.25)
    @State private var durataRientro: Double = 0.25      // la durata vera dell'ultima discesa della tastiera (per far scorrere la chat insieme)
    @State private var salitaTastiera: (quando: Date, durata: Double)?   // l'ultima keyboardWillShow: quando e quanto dura la salita
    /// Il reattore piccolo e il microfono spento mentre si scrive: solo sull'iPhone (iPad e Mac restano come prima).
    private var telefono: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    /// Una schermata aperta da JARVIS o dal Tocco d'aiuto di Bea, non dal signore.
    private var schermataDaSola: Bool {
        let pagina: Bool = jarvis.pagina != nil
        let occhi: Bool = jarvis.occhi != nil
        let interprete: Bool = jarvis.interprete != nil
        return pagina || occhi || interprete || jarvis.allenatore || aiutoBea != nil
    }

    var body: some View {
        // 4 nov: la catena dei collegamenti di `body` è divisa in tre pezzi (schermata, collegata e qui), che il compilatore
        // controlla uno alla volta: tutta insieme era troppo lunga («unable to type-check this expression in reasonable time»).
        // Stesso ordine e stesse cose di prima.
        collegata
            .onChange(of: comandi.richiesta) { eseguiComando() }
            .fullScreenCover(item: $aiutoBea) { a in VistaAiutoBea(aiuto: a) { aiutoBea = nil } }
            .onChange(of: jarvis.fase) { _, nuova in if nuova == .attesa { iconaAttiva = nil } }
            .onChange(of: tastiera) { _, aperta in if aperta { ruota.spegni() } }       // MARK XI: si scrive, l'ologramma della ruota si spegne
            .onChange(of: schermoLibero, initial: true) { _, libero in consentiRichiamo(libero) }
            .onChange(of: qualcosaAperto, initial: true) { _, aperto in jarvis.schermataAperta = aperto }
            .onChange(of: sezioneAperta, initial: true) { _, r in jarvis.sezioneAperta = r }
            .onChange(of: aiutoBea != nil, initial: true) { _, aperto in jarvis.soccorsoAperto = aperto }
            // si apre una schermata da sola (pagina web, Occhi, Interprete, Allenatore, l'SOS di Bea): la tastiera si chiude
            .onChange(of: schermataDaSola) { _, aperta in
                if aperta && telefono { tastiera = false }
            }
            // decisione 15 (24 ott): JARVIS apre una schermata da solo (Occhi, pagina web, Interprete, l'SOS di Bea, qualsiasi foglio
            // o schermata intera): la tendina PROTOCOLLI risale da sola, anche se era solo tirata a metà
            .onChange(of: qualcosaAperto || schermataDaSola) { _, aperta in
                if aperta && (tendinaAperta || tendinaTrascina != 0) { chiudiTendina() }
            }
            .task {                                               // il menu SISTEMI si prepara da solo, a avvio finito: all'apertura è già fresco
                try? await Task.sleep(for: .seconds(8))
                await caricaStatoSistemi()
            }
            .onChange(of: jarvis.chiudiChiesto) { _, si in       // «Jarvis, chiudi» / «torna»: si torna alla schermata principale
                guard si else { return }
                jarvis.chiudiChiesto = false
                if tendinaAperta { chiudiTendina() }               // decisione 15: «Jarvis, chiudi» manda su anche la tendina PROTOCOLLI
                chiudiTutto()
            }
    }

    /// La schermata con i suoi collegamenti di mezzo: le sezioni del contenitore, i reparti chiesti a voce, la fotocamera di
    /// sistema, l'avvio (vedi `body`).
    private var collegata: some View {
        schermata
            .onChange(of: mostraWiretap) { _, aperto in if !aperto { jarvis.riunioneSubito = false } }
            // MARK XI: lo stato di ogni sezione acceso = davanti nel contenitore; spento = dietro (se ci sta andando) o chiusa
            .onChange(of: sezioniAccese) { prima, adesso in sincronizzaSezioni(prima: prima, adesso: adesso) }
            .onReceive(NotificationCenter.default.publisher(for: .jarvisChiudiSezione)) { n in
                guard let id = n.userInfo?["id"] as? UUID, let v = pila.voci.first(where: { $0.id == id }) else { return }
                spegniStato(v.sezione)
            }
            // 4 nov: le sezioni aperte a voce («sezioni aperte», «quella di prima», «chiudi il meteo», «mettila da parte»…)
            .onReceive(NotificationCenter.default.publisher(for: .jarvisComandoSezioni)) { n in
                if let c = n.userInfo?["comando"] as? ComandoVocale { comandoSezioni(c) }
            }
            .onChange(of: pila.davanti) { _, d in davantiCambiata(d) }
            // comandi vocali: «attiva la Sentinella», «apri il Wiretap», «fammi un profilo», «fai un giro»
            .onChange(of: jarvis.repartoRichiesto) { _, r in
                guard let r else { return }
                jarvis.repartoRichiesto = nil
                apriReparto(r)
            }
            .onChange(of: mostraLidar, initial: true) { _, aperto in jarvis.lidarAperto = aperto }
            // 4 nov: gli Occhi e l'Interprete aperti da JARVIS («cosa vedi?», «traduci in inglese») salgono nel contenitore e la
            // sezione davanti va dietro da sola; si chiude solo quello che starebbe sopra di loro (la pagina web, il menu SISTEMI…)
            .onChange(of: jarvis.occhi != nil) { _, aperti in if aperti { liberaSopra() } }
            .onChange(of: jarvis.interprete != nil) { _, aperto in if aperto { liberaSopra() } }
            // 9 nov: la lingua c'è (scelta nel pannello, a voce o cambiata dentro): la sezione la ricorda, la scelta è finita
            .onChange(of: jarvis.interprete) { _, l in if let l { scegliLingua = false; pila.linguaInterprete(l) } }
            .fullScreenCover(isPresented: Binding(get: { sorgenteFoto != nil }, set: { if !$0 { sorgenteFoto = nil } })) {
                Fotocamera(sorgente: sorgenteFoto ?? .photoLibrary) { immagine in
                    jarvis.impostaFoto(immagine)
                    jarvis.ascoltaSubito()          // subito dopo la foto: «che disco è?»
                }
                .ignoresSafeArea()
            }
            .onAppear {
                Aptica.prepara()
                MotoreGuida.condiviso.parla = { [jarvis] frase in jarvis.annuncia(frase) }   // build 23: la GUIDA di SATELLITE parla
                accendi()
                if Portachiavi.leggi().isEmpty { mostraImpostazioni = true; return }
                if primaApertura {
                    primaApertura = false
                    if comandi.richiesta == nil && ascoltaApertura {
                        // sul Mac il microfono non cancella l'eco: aperto subito registrerebbe la musica d'avvio e la chat che si carica,
                        // e dalla trascrizione vuota verrebbe «Non ho capito, Sir». Lì si apre a sequenza finita.
                        ascoltaDopoAvvio = true                         // iPhone e Mac: dopo l'avvio, così musica e pulsazioni escono a pieno volume
                    }
                }
                eseguiComando()
            }
    }

    /// La schermata di JARVIS (reattore, chat, tendina, contenitore delle sezioni) con i primi collegamenti: protocolli, pagina
    /// web, Studio e Social, isola, Occhi e LiDAR dallo Studio (vedi `body`).
    private var schermata: some View {
        GeometryReader { g in
            // schermo grande (il Mac, un iPad in orizzontale): la stessa interfaccia dell'iPhone, centrata,
            // con il reattore che cresce con la finestra e la conversazione sotto, più stretta e al centro
            let alto = g.size.height + g.safeAreaInsets.bottom      // l'altezza vera, anche con la tastiera aperta
            let mac = ProcessInfo.processInfo.isiOSAppOnMac
            let grande = mac || (g.size.width >= 900 && g.size.width > alto * 1.15)
            // la conversazione: più bassa, così il reattore prende quasi tutto lo schermo; sul Mac anche il testo è più grande
            let zc: CGFloat = mac ? 1.25 : 1
            let altezzaChat = max(140, alto * 0.18)
            let altezzaCorona: CGFloat = ContentView.latoCorona / 2 + ContentView.raggioCorona + 40
            let altezzaTesti: CGFloat = mac ? 125 * 1.25 : 125      // stato, telemetria e la frase sotto il reattore
            // la corona con sotto il nome INTELLIGENCE, poi i testi: nessuna sovrapposizione
            // la corona tiene tutto il suo spazio (anche il nome INTELLIGENCE in basso) più un respiro: niente scritte sopra
            let scala = max(0.3, min(3, (g.size.width - 32) / 430, max(0.7, (alto - 70 - altezzaTesti - altezzaChat - 60 - 10) / (altezzaCorona + 12))))   // anche la larghezza conta
            ZStack {
                SfondoHUD(fase: jarvis.fase)
                if mostraSistemi { menuSistemi.zIndex(10) }
                if grande {
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 0) {
                            intestazione()
                                .contentShape(Rectangle())
                                .highPriorityGesture(gestoTestata)
                            Spacer(minLength: 0)
                            corona()
                                .frame(width: 430)
                                .scaleEffect(scala, anchor: .top)                     // il reattore cresce con lo schermo
                                .frame(width: g.size.width, height: (altezzaCorona + 12) * scala, alignment: .top)
                            testiHUD
                                .frame(maxWidth: max(0, min(640, (g.size.width - 32) / 1.25)))
                                .scaleEffect(mac ? 1.25 : 1, anchor: .top)
                                .frame(height: altezzaTesti, alignment: .top)
                                .contentShape(Rectangle())
                                .highPriorityGesture(tiraGiuTendina)
                            Spacer(minLength: 0)
                            Color.clear.frame(height: altezzaChat + 60)           // il posto della conversazione
                        }
                        .ignoresSafeArea(.keyboard, edges: .bottom)                // il reattore resta fermo
                        VStack(spacing: 0) {
                            registro
                            barraTesto
                        }
                        .frame(width: max(0, min(860, g.size.width - 32)) / zc, height: (altezzaChat + 60) / zc)
                        .scaleEffect(zc, anchor: .bottom)                          // sul Mac la chat è più grande, stessa forma
                        .frame(width: g.size.width, height: altezzaChat + 60, alignment: .bottom)
                    }
                } else {
                    VStack(spacing: 0) {
                        intestazione(mini: telefono && !reattoreGrande, stretta: g.size.width < ContentView.larghezzaStretta)
                            .contentShape(Rectangle())
                                .highPriorityGesture(gestoTestata)
                        // con la tastiera aperta (reattore piccolo) la riga di stato sotto il titolo: cosa fa JARVIS, cosa sente, gli avvisi
                        if telefono && !reattoreGrande && g.size.height > 300 {   // iPhone piccolo girato: non c'è posto, niente riga
                            rigaStato
                                .transition(.opacity)
                        }
                        // mentre scrive il reattore grande lascia il posto alla chat (resta in piccolo in alto): sopra la tastiera la chat, il testo e il tasto per inviare
                        if reattoreGrande || !telefono {
                            // con la tastiera le icone delle sezioni e gli archi si spengono e lasciano il posto alla chat (il reattore vola)
                            centroHUD
                                .transition(.opacity)
                        }
                        registro
                        barraTesto
                    }
                    // 27 ott (video del signore 01:34, misurato fotogramma per fotogramma): aprendo la tastiera titolo e icone salivano di
                    // ~10 punti e ridiscendevano in 0,2 s. Lo spazio si accorcia subito (sale la tastiera) ma il reattore grande lascia
                    // il posto un attimo dopo: per quell'attimo il contenuto è più alto dello spazio e iOS lo centrava, spingendo su la
                    // testata. Ancorato in alto, la testata resta ferma (l'eccedenza va in basso, dietro la tastiera che sale).
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // build 23: il reattore sopra la schermata, nel suo posto grande o in quello piccolo (vola dall'uno all'altro)
                    .overlayPreferenceValue(PostiReattore.self) { posti in reattoreVolante(posti) }
                    .onChange(of: tastiera) { _, aperta in
                        guard telefono else { return }                      // iPad: come prima, niente reattore piccolo
                        if aperta {
                            // di solito keyboardWillShow è appena arrivata (o arriva subito dopo): il volo parte con la sua durata
                            if let s = salitaTastiera, Date().timeIntervalSince(s.quando) < 0.2 {
                                vola(grande: false, durata: s.durata - Date().timeIntervalSince(s.quando))
                            } else {
                                // rete di sicurezza (tastiera fisica, nessuna notifica): il volo con la durata di sempre
                                Task {
                                    try? await Task.sleep(for: .milliseconds(80))
                                    if tastiera && reattoreGrande { vola(grande: false, durata: 0.25) }
                                }
                            }
                        } else {
                            // rete di sicurezza (tastiera fisica, notifica mancata): di solito il rientro lo fa già keyboardWillHide qui sotto
                            Task {
                                try? await Task.sleep(for: .milliseconds(60))
                                if !tastiera && !reattoreGrande { vola(grande: true, durata: 0.25) }
                            }
                        }
                    }
                    // il reattore vola su mentre la tastiera sale, con la durata e la curva della tastiera stessa;
                    // la tastiera ricompare senza che il campo sia cambiato (app riaperta, iPhone girato…): il reattore torna piccolo
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
                        let d = ContentView.durataTastiera(n)
                        salitaTastiera = (Date(), d)
                        if telefono && tastiera && reattoreGrande { vola(grande: false, durata: d) }
                    }
                    // il reattore torna giù mentre la tastiera scende, con la durata e la curva della tastiera stessa (anche nello swipe,
                    // dove la tastiera è già a metà): un movimento solo, la chat non si allunga prima per poi restringersi
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { n in
                        guard telefono, !reattoreGrande else { return }
                        let d = max(ContentView.durataTastiera(n), 0.2)
                        durataRientro = d
                        vola(grande: true, durata: d)
                    }
                    // tornato dal layout largo (iPhone girato) a tastiera chiusa: il reattore grande al suo posto
                    .onAppear { if telefono { reattoreGrande = !tastiera } }
                }
                // 26 ott notte (il signore): lo swipe giù dal bordo in alto è di iOS (Centro notifiche), senza linguetta; i PROTOCOLLI
                // scendono con lo swipe giù da metà pagina (titolo, reattore e corona, testi). Tolta la fascia dell'ora che li apriva.
                tendina(g)
                // 26 ott sera (video del signore 21:58: alla chiusura di Studio e Social quasi un secondo di nero): STUDIO e SOCIAL
                // non sono più una schermata di iOS ma uno strato qui sopra JARVIS (StratoPagina, in PaginaPiena.swift): salgono e
                // scendono come le altre schede e JARVIS sotto resta sempre disegnato. Sopra tutto, anche la tendina (19-20).
                // MARK XI: le sezioni, nel contenitore (davanti una, dietro le altre vive)
                strato
                    .zIndex(25)
                // MARK XI: Studio e Social stanno nel contenitore come le altre sezioni (la pagina web resta viva dietro)
            }
            .environment(\.jarvisCoperto, pilaCopre)

            .frame(width: g.size.width, height: g.size.height)
            // 26 ott notte (foto del signore 23:29, «menu a tendina inutile»): tolto il blocco dello swipe di iOS dall'alto: con il
            // blocco iOS mostrava sempre la sua linguetta grigia sotto la Dynamic Island. I PROTOCOLLI si aprono tirando giù da titolo,
            // reattore e testi, come prima.
        }
        // MARK XI (3 nov sera, «DEFINITIVA»): il bordo in basso è tutto di iOS (si esce dall'app al primo swipe); lo swipe su delle
        // sezioni parte poco sopra la barretta (GestoBassoSezioni). Con la tendina aperta o tirata, è fermo (come nel mockup).
        .onChange(of: tendinaAperta || tendinaTrascina != 0) { _, ferma in naviga.bassoFermo = ferma }
        // 4 nov: quando cambia la sezione davanti (aperta, chiusa, mandata dietro con lo swipe) le icone del Dock tornano allineate
        .onChange(of: pila.davanti) { if dock.x != nil { dock.lascia() } }
        // app in sottofondo a metà di una tirata: il gesto non finisce mai, la tendina non deve restare appesa
        .onChange(of: scena) { _, fase in
            if fase != .active && !tendinaAperta { tendinaTrascina = 0 }
            if fase == .background { jarvis.vaInSottofondo() }      // 25 ott: niente risposte a frasi vecchie al ritorno
        }
        // «Jarvis, protocollo notte»: si chiude quello che è aperto, scende la tendina e il protocollo parte (come nel mockup)
        .onReceive(protocolli.$richiesta.dropFirst()) { _ in
            chiudiTutto()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                apriTendina()
                try? await Task.sleep(for: .milliseconds(600))
                if let p = Protocolli.condiviso.prendiRichiesto() { Protocolli.condiviso.avvia(p) }
            }
        }
        .fullScreenCover(item: $jarvis.pagina) { p in BrowserInterno(url: p.url).ignoresSafeArea().aperturaHUD("Browser", icona: "globe").paginaPiena() }
        // Studio e Social: lo strato sopra JARVIS, nel corpo qui sopra (dopo la tendina)
        .onReceive(NotificationCenter.default.publisher(for: .jarvisApriPagina)) { n in
            guard let a = n.userInfo?["a"] as? AperturaPagina else { return }
            // 4 nov: Studio e Social salgono nel contenitore e la sezione davanti va dietro da sola (sincronizzaSezioni), viva,
            // come nel mockup. Si chiude solo quello che sta sopra a tutto (liberaSopra); se era aperta la pagina web o la
            // fotocamera di sistema (schermate di iOS) si aspetta che siano giù (al massimo 3 s), come prima.
            let coperta = jarvis.pagina != nil || sorgenteFoto != nil
            // 4 nov (il signore, scelta A): Studio o Social già davanti e una richiesta nuova per loro («Jarvis, crea una
            // piastra…»): prima si perdeva. Ora la pagina scende (il lavoro dello Studio si salva uscendo) e risale subito con
            // la richiesta, come nella MARK X.
            let rifai = aperturaPagina?.sezione == a.sezione && a.conRichiesta
            liberaSopra()
            Task { @MainActor in
                if rifai {
                    aperturaPagina = nil
                    try? await Task.sleep(for: .milliseconds(550))            // la discesa finita: poi sale quella nuova
                }
                if coperta {
                    for _ in 0..<60 {
                        try? await Task.sleep(for: .milliseconds(50))
                        if PaginaMarkX.schermoLibero() { break }
                    }
                }
                alzaPagina(a)
            }
        }
        .onOpenURL { url in                                 // MARK X · i tasti della Dynamic Island (it.discosizer.jarvis://isola/…)
            guard let c = IsolaJarvis.comando(url) else { return }
            switch c {
            case "percorso":                                 // TRAVEL › Percorso: SATELLITE con TRAVEL aperto
                RichiestaSatellite.condivisa.azione = .travel("", "mezzi")
                apriReparto(.satellite)
            case "guida":                                    // GUIDA › Apri: la guida di SATELLITE
                if let l = MotoreGuida.condiviso.luogo { RichiestaSatellite.condivisa.azione = .guida(l.nome); apriReparto(.satellite) }
            case "radar":                                    // PIOGGIA › Radar: il Meteo con il radar in testa
                apriReparto(.meteo)
            default: break                                   // «apri», «basta», «ferma»: JARVIS davanti, il resto l'ha già fatto l'isola
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisVaiA)) { n in   // LIDAR e OCCHI dello Studio: quelli veri
            let lidar = n.userInfo?["dove"] as? String == "lidar"
            Task { @MainActor in
                // 26 ott sera: come Occhi → Studio, si aspetta che lo Studio (o Social) sia davvero chiuso (al massimo 3 s):
                // iOS non apre gli Occhi o LiDAR mentre un'altra schermata si sta ancora chiudendo.
                try? await Task.sleep(for: .milliseconds(150))
                for _ in 0..<60 {
                    if PaginaMarkX.schermoLibero() { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                if lidar { LidarAperta.richiesta = (.oggetto, nil, false) }   // LiDAR parte già su Oggetto (in silenzio, come sempre)
                apriReparto(lidar ? .lidar : .occhi)
            }
        }
    }

    /// Sequenza di avvio alla Stark: suono, icone che si accendono in fila, «SISTEMI IN LINEA».
    private func accendi() {
        guard !acceso else { return }
        Suoni.preparaAudio()                // l'audio è dell'app prima che suoni l'avvio: i tasti del volume lo regolano (solo la prima volta)
        withAnimation(.spring(duration: 0.6 / Avvio.velocita, bounce: 0.35)) { acceso = true }   // il reattore è pieno prima della prima icona
        let chatDaCaricare = !jarvis.messaggi.isEmpty && !UIAccessibility.isReduceMotionEnabled
        if chatDaCaricare { regiaChat.fase = .nascosta }      // la chat aspetta la fine delle icone
        Task { @MainActor in
            let v = Avvio.velocita
            try? await Task.sleep(for: .seconds(0.65 / v))
            let elenco = tutteLeIcone
            // la partitura: l'istante di ogni icona dall'inizio della musica (150 ms, 110 tra i gruppi, INTELLIGENCE 120, tutto ÷ velocità).
            // È la stessa partitura con cui è montata la traccia «avvio»: ogni pulsazione cade sulla sua icona.
            var colpi: [Double] = []; var t = 0.0
            for k in 0..<elenco.count {
                if k > 0 && elenco[k - 1].gruppo != elenco[k].gruppo { t += 0.110 }
                colpi.append(t / v)
                t += elenco[k].gruppo == "INTELLIGENCE" ? 0.120 : 0.150
            }
            // la partitura vera (quella della traccia): STRUMENTI e INTELLIGENCE su tutto lo scarico della musica
            if Avvio.colpi.count == elenco.count { colpi = Avvio.colpi.map { $0 / v } }
            let fineMusica = colpi.last ?? 0
            // l'aptica: un tocco sull'ULTIMA icona di ogni gruppo (cinque in tutto)
            let tempiAptica = (0..<elenco.count).filter { $0 == elenco.count - 1 || elenco[$0 + 1].gruppo != elenco[$0].gruppo }.map { colpi[$0] }
            let coda = Avvio.inizioCoda(elenco.map { $0.nome })
            // un solo orologio per musica, icone e aptica: niente pause in fila che sommano i ritardi
            Suoni.plim(0)                                                  // parte la musica d'avvio
            let ritardoAudio = AVAudioSession.sharedInstance().outputLatency   // il suono arriva all'altoparlante un attimo dopo
            let zero = CACurrentMediaTime() + ritardoAudio
            Aptica.avvio(tempi: tempiAptica.map { $0 + ritardoAudio })
            // MARK X: le icone in alto arrivano da destra, rapide (0,2 s), una alla volta e alla STESSA distanza fra loro:
            // la prima si posa sul colpo della prima icona della corona, l'ultima sul colpo dell'ultima. Partono 110 ms prima del colpo.
            let colpoVero = { (k: Int) in colpi[k] - (k >= coda ? Avvio.anticipoCoda : 0) }
            let nTesta = ContentView.postoTesta.totale, primoColpo = colpoVero(0), ultimoColpo = colpoVero(elenco.count - 1)
            Task { @MainActor in
                for j in 0..<nTesta {
                    let posa = primoColpo + Double(j) * (ultimoColpo - primoColpo) / Double(max(1, nTesta - 1))
                    let manca = zero + posa - 0.110 - CACurrentMediaTime()
                    if manca > 0 { try? await Task.sleep(for: .seconds(manca)) }
                    withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.2)) { testaArrivate = j + 1 }
                }
            }
            // «SISTEMI IN LINEA» sulla chiusura della musica (4,35 s nel tempo di base), mai prima di 120 ms dopo l'ultima icona
            let inLinea = zero + max(Avvio.chiusuraMusica / v, fineMusica + 0.120 / v)
            // v266 (5 nov sera, il signore: «la chat deve partire subito a fine animazione» e «nello stesso istante che arriva
            // l'ultima icona, l'ultimo click, loading, carica la chat»): sul colpo dell'ultima icona (Bea) parte il caricamento HUD,
            // poi la stampa. Prima: «Sistemi in linea», 0,9 s di respiro, il caricamento, la stampa. Come il mockup v266.
            let chatStampa: Task<Void, Never>?
            if chatDaCaricare {
                chatStampa = Task { @MainActor in
                    let manca = zero + fineMusica - CACurrentMediaTime()
                    if manca > 0 { try? await Task.sleep(for: .seconds(manca)) }
                    guard preparaChat() else { return }
                    try? await Task.sleep(for: .seconds(TempiChat.carica))
                    await stampaChat()
                }
            } else {
                chatStampa = nil
            }
            var prima = 0.0
            for k in 0..<elenco.count {                             // la corona e, in fondo, INTELLIGENCE sulla curva
                // da Interprete in poi l'icona parte 110 ms prima del colpo (SINCRO): la molla svelta arriva sul beep
                let quando = max(prima, colpi[k] - (k >= coda ? Avvio.anticipoCoda : 0))
                prima = quando
                let manca = zero + quando - CACurrentMediaTime()
                if manca > 0 { try? await Task.sleep(for: .seconds(manca)) }
                accese = k + 1                                       // la molla la dà ogni icona (svelta nella coda)
                if k > 0 { Suoni.plim(k) }
            }
            let resta = inLinea - CACurrentMediaTime()
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            Suoni.inLinea()
            withAnimation(.easeOut(duration: 0.3)) { sottotitolo = "SISTEMI IN LINEA" }
            testaArrivate = ContentView.postoTesta.totale                 // per sicurezza: a sistemi in linea ci sono tutte
            withAnimation(.easeOut(duration: 1.6)) { bagliore = true }    // MARK X: il bagliore bianco si accende e resta fermo
            await chatStampa?.value                                       // v266: la chat è partita sull'ultima icona
            if !Impostazioni.richiamo { await Suoni.fineAvvioAudio() }   // col «Jarvis» acceso l'audio lo prende lui, come nella 12
            jarvis.avvioInCorso = false                            // finito: ora il microfono può accendersi
            if ascoltaDopoAvvio {                                  // ora che musica e chat hanno finito, in ascolto
                ascoltaDopoAvvio = false
                // icone e chat caricate: JARVIS si mette in ascolto da solo, come col tocco sul reattore
                // (finito l'ascolto, il richiamo «Jarvis» e i battiti di mani riprendono come sempre)
                try? await Task.sleep(for: .milliseconds(300))        // la coda dei suoni si spegne
                jarvis.ascoltaSubito()
            }
            try? await Task.sleep(for: .seconds(2.4 / Avvio.velocita))
            withAnimation(.easeOut(duration: 0.6)) { sottotitolo = ContentView.marca }   // MARK X (deciso dal signore il 26 ott)
        }
    }

    /// La chat si carica come una scheda: caricamento HUD (`preparaChat`), poi si stampa dall'alto e i caratteri si decodificano
    /// (`stampaChat`). v266: all'avvio il caricamento parte sul colpo dell'ultima icona.
    /// Il caricamento HUD (dura `TempiChat.carica`). Falso: non c'è niente da caricare.
    private func preparaChat() -> Bool {
        guard regiaChat.fase == .nascosta else { return false }
        if jarvis.messaggi.isEmpty { regiaChat.fase = .normale; return false }
        withAnimation(.easeOut(duration: 0.2)) { regiaChat.fase = .carica }
        return true
    }

    /// v266: la stampa dall'alto, con i caratteri che si decodificano.
    private func stampaChat() async {
        Suoni.chatCarica()                    // il suono dei caratteri parte con la stampa: dura quanto la decodifica
        regiaChat.fase = .stampa(Date())
        try? await Task.sleep(for: .seconds(TempiChat.stampa + TempiChat.decodifica + 0.1))
        Suoni.chatPronta()
        regiaChat.fase = .normale
    }

    /// Cestino › Pulisci: la chat si svuota settore per settore verso sinistra, poi si cancella davvero.
    private func svuotaChat() {
        guard !jarvis.messaggi.isEmpty, regiaChat.fase == .normale, !UIAccessibility.isReduceMotionEnabled else {
            jarvis.nuovaConversazione(); return
        }
        jarvis.interrompi()
        Suoni.chatSvuota()
        Aptica.svuota(durata: TempiChat.svuotaScala + TempiChat.svuotaRiga)
        regiaChat.fase = .svuota(Date())
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(TempiChat.totaleSvuota))
            jarvis.nuovaConversazione()
            regiaChat.fase = .normale
        }
    }

    private func eseguiComando() {
        guard let r = comandi.richiesta, !Portachiavi.leggi().isEmpty else { return }
        comandi.richiesta = nil
        switch r {
        case .ascolta:
            jarvis.interrompi()
            // 7 nov notte (il signore: «se lo lancio dal tasto Azione il volume è basso»): durante l'avvio il microfono aspetta la fine
            // della musica, come aprendo dall'icona (col microfono aperto l'iPhone abbassa l'altoparlante e i tasti del volume non
            // regolano più la musica). A JARVIS già acceso il tasto Azione resta immediato.
            if jarvis.avvioInCorso { ascoltaDopoAvvio = true } else { jarvis.ascoltaSubito() }
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
        case .radar:
            apriReparto(.meteo)                      // la notifica della pioggia: il Meteo con RADAR in testa
        }
    }

    /// La riga di stato con la tastiera aperta: la fase («PARLO», «LA ASCOLTO»…) e sotto la frase che sta sentendo,
    /// quello che sta facendo («Cerco sul web…») o l'avviso. Gli stessi testi che con la tastiera chiusa stanno sotto il reattore.
    private var rigaStato: some View {
        // solo cosa sente o cosa fa: i suggerimenti («tocchi il reattore…») qui non valgono, il reattore piccolo chiude la tastiera
        let frase: String = !jarvis.parziale.isEmpty ? jarvis.parziale : (jarvis.stato.map { "\($0)…" } ?? "")
        return VStack(spacing: 2) {
            Text(jarvis.etichettaFase)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Color.ciano)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: jarvis.fase)
            if let avviso = jarvis.avviso {
                Text(avviso)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if !frase.isEmpty {
                Text(frase)
                    .font(.system(size: 13))
                    .foregroundStyle(jarvis.parziale.isEmpty ? Color.tenue : .white)
                    .lineLimit(1)
                    .truncationMode(.head)              // mentre parla si vede la fine della frase, quella appena detta
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private var suggerimento: String {
        switch jarvis.fase {
        case .attesa: return jarvis.micSpento ? "Non ascolto nulla · tocchi il reattore per parlare" : "Tocchi il reattore e parli"
        case .ascolto: return "La ascolto, signore…"
        case .elaboro: return "Un momento…"
        case .parlo: return "Tocchi il reattore per interrompermi"
        }
    }

    /// Decisione 16 (24 ott): sotto questa larghezza (iPhone da 375 punti: SE 2ª e 3ª gen., 12 e 13 mini; 320 con lo Zoom
    /// dello schermo) il titolo con la tastiera aperta non va mai a capo e non tocca le icone (rete di sicurezza sul titolo).
    /// Da 390 punti in su (15 Pro compreso) resta tutto com'era.
    static let larghezzaStretta: CGFloat = 385
    /// MARK X (26 ott): il nome della versione sotto il titolo.
    static let marca = "MARK XI"                         // 3 nov: MARK XI, Version 11.0 (approvata dal signore)
    /// MARK X: il posto di ogni icona in alto nell'arrivo da destra (da sinistra a destra). Studio e Social arrivano con le tappe 2 e 3.
    enum postoTesta { static let social = 0, musica = 1, studio = 2, sistemi = 3, cestino = 4, impostazioni = 5, totale = 6 }
    /// 5 nov (il signore: «vanno distanziate un minimo»): il margine per lato di ogni icona in alto, 3,5 punti (era 2): fra due
    /// icone 3 punti in più, e un tocco più largo. Con la tastiera aperta resta 1 (lì c'è il reattore piccolo).
    static let margineDock: CGFloat = 3.5

    /// `mini`: con la tastiera aperta (solo iPhone) qui c'è il posto del reattore piccolo, tra il titolo e i tasti: il reattore vero
    /// ci vola sopra dal centro (`reattoreVolante`). Build 23: le icone sono quattro (MUSICA, SISTEMI, cestino, Impostazioni); come nel
    /// mockup («.telefono.b23») le icone hanno 1 punto in meno per lato e, con la tastiera aperta, le lettere del titolo 1 punto più vicine:
    /// così il reattore piccolo non tocca né il titolo né le icone.
    /// `stretta`: schermo più stretto di `larghezzaStretta` (decisione 16): il titolo non va mai a capo e non tocca le icone.
    /// Il titolo su una riga, a misura fissa (20 punti, spaziatura 5 come il mockup): l'ultimo punto attaccato alla S.
    ///
    private func titoloJarvis(spazio: CGFloat, misura: CGFloat) -> some View {
        (Text("J.A.R.V.I.").tracking(spazio) + Text("S."))
            .font(.system(size: misura, weight: .bold, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
    }

    private func intestazione(mini: Bool = false, stretta: Bool = false) -> some View {
        HStack(alignment: .rigaMark, spacing: 0) {          // le icone sulla stessa riga di «MARK VIII», strette tra loro
            VStack(alignment: .leading, spacing: 2) {
                // l'ultimo punto attaccato alla S (la spaziatura delle lettere lo staccava)
                // 26 ott (foto del signore): con la tastiera aperta e 7 icone in testata, sul 15 Pro restano ~192 punti e il titolo ne
                // vuole ~208: la «S.» andava a capo. Ora prima si stringe solo lo spazio tra le lettere (le lettere restano uguali, come il
                // mockup b32), poi, solo se ancora non ci sta, il testo; sempre su una riga, mai tagliato.
                // 26 ott notte (video del signore 23:03: «la scritta JARVIS che vola»): chiusa la tastiera, il titolo saltava fin
                // sotto l'ora per 1,5 s mentre MARK X e le icone restavano al loro posto. Lo spostava ViewThatFits, che cambiando
                // misura (stretta con la tastiera, larga senza) rimetteva il titolo fuori dall'area sicura in alto. Ora il titolo è
                // un testo solo, sempre lo stesso: le misure possibili si contano a parte (nascoste) e si sceglie la più larga che
                // entra nel posto libero accanto alle icone. Stesse misure e stesso ordine di prima.
                // 26 ott notte (il signore: «la scritta JARVIS deve rimanere ferma, bastava impaginare bene»): una misura sola, quella
                // del mockup approvato (20 punti, spaziatura 5), uguale con e senza tastiera: niente più cambi di misura né salti.
                titoloJarvis(spazio: stretta ? 2 : 5, misura: stretta ? 18 : 20)
                    .foregroundStyle(.white)
                    .shadow(color: .ciano.opacity(0.5), radius: 10)
                    .shadow(color: .white.opacity(bagliore ? 0.38 : 0), radius: 7)      // MARK X: bagliore bianco, si accende una volta e resta
                    .shadow(color: .white.opacity(bagliore ? 0.15 : 0), radius: 16)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(sottotitolo)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(sottotitolo == ContentView.marca ? Color.tenue : Color.ciano)
                        .contentTransition(.numericText())
                        .id(sottotitolo)
                        .transition(.opacity)
                    // 8 nov · CUFFIE (il signore: «scritta piccola con logo cuffie, finché sono collegate, non invadente… accanto a
                    // MARK XI»): «· EARPODS» sulla stessa riga, stesso carattere e grigio, come il mockup v285; con la tastiera no
                    if !mini && sottotitolo == ContentView.marca { IndicatoreCuffie() }
                }
                .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            }
            .frame(maxWidth: .infinity, alignment: .leading)          // tutto il posto libero accanto alle icone (prima: lo Spacer)
            .opacity(acceso ? 1 : 0)
            .offset(x: acceso ? 0 : -12)
            if mini {
                // il posto del reattore piccolo (34 punti): il reattore vero ci arriva volando e, toccato, chiude la tastiera e basta
                Button { tastiera = false } label: {
                    Color.clear
                        .frame(width: 22, height: 34)               // MARK X (mockup b32): della misura delle icone, 5 dal titolo e 2 dalle icone
                        .contentShape(Rectangle())                  // si tocca tutto il quadrato, non solo il disegno
                }
                .anchorPreference(key: PostiReattore.self, value: .bounds) { ["piccolo": $0] }
                .padding(.leading, 5).padding(.trailing, 2)
                .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
                .accessibilityHidden(true)                          // per VoiceOver c'è il reattore stesso («Chiudi la tastiera»)
            }
            // MARK X: SOCIAL, la prima in alto (Instagram di @kingrusto, il glifo ufficiale in ciano)
            Button { toccaDock(ContentView.postoTesta.social) } label: {
                IconaSocial()
                    .foregroundStyle(Color.ciano)
                    .padding(.vertical, 8).padding(.horizontal, mini ? 1 : ContentView.margineDock)   // MARK X: 6 icone, 2 per lato (mockup b32); con la tastiera 1
                    .contentShape(Rectangle())
            }
            .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            .arrivoTesta(ContentView.postoTesta.social, arrivate: testaArrivate)
            .modifier(PostoDock(dock: dock, indice: ContentView.postoTesta.social))
            .accessibilityLabel("Social")
            // build 23: MUSICA, prima di SISTEMI (il vinile olografico del mockup)
            Button { toccaDock(ContentView.postoTesta.musica) } label: {
                IconaVinile()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Color.ciano)
                    // 27 ott notte (il signore): il disco un poco più a destra, verso Studio
                    .padding(.vertical, 8).padding(.leading, (mini ? 1 : ContentView.margineDock) + 0.6).padding(.trailing, (mini ? 1 : ContentView.margineDock) - 0.6)
                    .contentShape(Rectangle())
            }
            .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            .arrivoTesta(ContentView.postoTesta.musica, arrivate: testaArrivate)
            .modifier(PostoDock(dock: dock, indice: ContentView.postoTesta.musica))
            .accessibilityLabel("Musica")
            // MARK X: STUDIO, subito dopo MUSICA (ordine deciso dal signore: Social, Musica, Studio, Sistemi, Cestino, Impostazioni)
            Button { toccaDock(ContentView.postoTesta.studio) } label: {
                IconaStudio(pieno: true)                            // 27 ott: alta 15 punti come le altre 5 (misurate sulla foto), cubo più grande
                    .frame(width: 18, height: 18)                       // 27 ott notte (il signore): Studio più grande, armonico con le altre (20 un filo troppo)
                    .foregroundStyle(Color.ciano)
                    // 27 ott: il riquadro è 2 punti più stretto di prima ma il disegno quasi uguale: +0,75 per lato e la distanza a vista
                    // dalle icone vicine resta quella di sempre (~7,5 punti, misurata sulla foto), uguale tra tutte e 6
                    .padding(.vertical, 8)
                    .padding(.leading, (mini ? 1 : ContentView.margineDock) + 0.55).padding(.trailing, (mini ? 1 : ContentView.margineDock) + 0.25)   // spazi a vista uguali
                    .contentShape(Rectangle())
            }
            .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            .arrivoTesta(ContentView.postoTesta.studio, arrivate: testaArrivate)
            .modifier(PostoDock(dock: dock, indice: ContentView.postoTesta.studio))
            .accessibilityLabel("Studio")
            Button { toccaDock(ContentView.postoTesta.sistemi) } label: {
                Image(systemName: "server.rack")
                    .font(.system(size: 11.8, weight: .semibold))   // 27 ott notte (il signore): linee spesse come Social (1,33 pt, misurate sulla foto)                      // 27 ott notte (il signore: «sembra sempre grande»): larga e piena di righe, a vista pesa di più: 13,5 × 10,5 pt
                    .foregroundStyle(Color.ciano)
                    .padding(.vertical, 8).padding(.horizontal, mini ? 1 : ContentView.margineDock)   // MARK X: 6 icone, 2 per lato (mockup b32); con la tastiera 1
                    .contentShape(Rectangle())          // 27 ott (il signore): niente alone intorno all'icona col menu aperto
            }
            .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            .arrivoTesta(ContentView.postoTesta.sistemi, arrivate: testaArrivate)
            .modifier(PostoDock(dock: dock, indice: ContentView.postoTesta.sistemi))
            .accessibilityLabel("Sistemi")
            Button { toccaDock(ContentView.postoTesta.cestino) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13.9, weight: .semibold))                      // 27 ott notte (misurato: 15 × 17,3 pt a 16): lato maggiore 15 pt come le altre; tratto leggero come Social e Musica (foto 02:49: il tratto pieno le faceva sembrare più grandi)
                    .foregroundStyle(Color.ciano)
                    // 27 ott (misurato sulla foto: SISTEMI-cestino 7,3 punti, gli altri 7): 0,3 in meno a sinistra
                    .padding(.vertical, 8).padding(.leading, (mini ? 1 : ContentView.margineDock) - 0.8)   /* 27 ott notte: SISTEMI-cestino era troppo larga */.padding(.trailing, (mini ? 1 : ContentView.margineDock) + 0.35)   // foto 02:49: cestino-impostazioni 6,3 → 7
            }
            .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            .arrivoTesta(ContentView.postoTesta.cestino, arrivate: testaArrivate)
            .modifier(PostoDock(dock: dock, indice: ContentView.postoTesta.cestino))
            .accessibilityLabel("Pulisci la conversazione")
            .confirmationDialog("Pulire la conversazione?", isPresented: $chiediPulizia, titleVisibility: .visible) {
                Button("Pulisci", role: .destructive) { svuotaChat() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Memoria e note di JARVIS restano: si cancella solo la chat sullo schermo.")
            }
            Button { toccaDock(ContentView.postoTesta.impostazioni) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14.4, weight: .regular))                      // 27 ott notte (misurata: 17,7 × 17,7 pt a 17): lato maggiore 15 pt come le altre
                    .foregroundStyle(Color.ciano)
                    .padding(.vertical, 8).padding(.leading, (mini ? 1 : ContentView.margineDock) + 0.35).padding(.trailing, mini ? 1 : ContentView.margineDock)   // foto 02:49: spazio 7
                    // 9 nov notte (il signore: «l'icona di impostazioni mi piace che si animi all'avvio e alla chiusura… aggiungiamola»):
                    // la rotella gira di un quarto aprendo Impostazioni e torna chiudendo, ora anche nel mockup
                    .rotationEffect(.degrees(mostraImpostazioni ? 90 : 0))
                    .animation(.spring(duration: 0.5), value: mostraImpostazioni)
            }
            .alignmentGuide(.rigaMark) { d in d[VerticalAlignment.center] }
            .arrivoTesta(ContentView.postoTesta.impostazioni, arrivate: testaArrivate)
            .modifier(PostoDock(dock: dock, indice: ContentView.postoTesta.impostazioni))
            .accessibilityLabel("Impostazioni")
        }
        .buttonStyle(StileStark())
        // MARK XI: sul Mac il puntatore sopra le icone le ingrandisce (senza premere), con il click per icona
        .onContinuousHover(coordinateSpace: .global) { fase in
            guard ProcessInfo.processInfo.isiOSAppOnMac, testaArrivate >= ContentView.postoTesta.totale else { return }
            switch fase {
            case .active(let p): if sulDock(p) { dock.segui(p.x, mac: true) } else if dock.x != nil { dock.lascia() }
            case .ended: if dock.x != nil { dock.lascia() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        // 26 ott sera (testata «non fluida» con la tastiera): sul 15 Pro, aprendo la tastiera arriva il posto del reattore piccolo e il
        // titolo a spaziatura 5 non ci stava più: scattava di colpo a una spaziatura più stretta (prima rimpiccioliva di colpo). Ora fa
        // posto la testata, non il titolo: le icone si avvicinano di 1 punto per lato e lo spazio vuoto prima delle icone può arrivare a 0
        // (20 punti, ne servivano ~16), e tutto scivola insieme. Il titolo resta identico al mockup b32 (lettere e spaziatura uguali);
        // ViewThatFits resta solo per gli iPhone più stretti (SE).
        .animation(ContentView.curvaTastiera, value: mini)
    }

    /// Scorciatoie in alto: per aggiungere una funzione nuova basta una riga in più qui.
    /// In quattro gruppi, separati da una linea sottile:
    /// LA GIORNATA (cosa c'è oggi) · IL SIGNORE (come sta) · I SENSI (cosa vede e sente JARVIS) · STRUMENTI.
    /// In quattro gruppi lungo i tre quarti di cerchio attorno al reattore, da sinistra in basso verso destra in basso:
    /// BIOMETRICS (come sta) · OPERATIONS (la giornata) · PERCEPTION (cosa vede e sente JARVIS) · ENGINEERING (8 nov: i nomi in
    /// inglese, scelta del signore; prima SIGNORE · DAILY · SENSI · STRUMENTI).
    private var scorciatoie: [(gruppo: String, icona: String, nome: String, azione: () -> Void)] {
        [
            ("BIOMETRICS", "book.closed", "Diario", { tastiera = false; scheda = .diario }),
            ("BIOMETRICS", "person.2.wave.2", "Confidente", { tastiera = false; mostraConfidente = true }),
            ("BIOMETRICS", "waveform.path.ecg", "Vitals", { tastiera = false; mostraVitals = true }),
            ("BIOMETRICS", "bed.double", "Sonno", { tastiera = false; scheda = .sonno }),
            ("BIOMETRICS", "heart", "Cuore", { tastiera = false; scheda = .cuore }),
            ("BIOMETRICS", "figure.pilates", "Trainer", { tastiera = false; jarvis.interrompi(); jarvis.allenatore = true }),

            ("OPERATIONS", "sun.horizon", "Briefing", { tastiera = false; scheda = .briefing }),
            ("OPERATIONS", "cloud.sun", "Meteo", { tastiera = false; scheda = .meteo }),
            ("OPERATIONS", "envelope.badge", "Email", { tastiera = false; scheda = .email }),
            ("OPERATIONS", "envelope", "Messaggi", { tastiera = false; scheda = .messaggi }),
            ("OPERATIONS", "cart", "Spesa", { tastiera = false; scheda = .spesa }),

            ("PERCEPTION", "eye", "Occhi", { tastiera = false; jarvis.guardaManuale() }),
            ("PERCEPTION", "fork.knife", "Cucina", { tastiera = false; jarvis.guardaCucina() }),
            ("PERCEPTION", "barcode.viewfinder", "Scanner", { tastiera = false; scheda = .scanner }),
            ("PERCEPTION", "shazam.logo", "Shazam", { tastiera = false; jarvis.interrompi(); scheda = .shazam }),
            ("PERCEPTION", "photo.on.rectangle", "Foto", { tastiera = false; scheda = .foto }),

            ("ENGINEERING", "brain.head.profile", "Ricordi", { tastiera = false; guidaRicordi = false; salvaRicordi = false; mostraRicordi = .traccia }),   // build 22: si apre su TRACCIA, come nel mockup
            ("ENGINEERING", "globe.europe.africa", "Interprete", { tastiera = false; apriInterprete() }),
            ("ENGINEERING", "globe", "Browser", { mostraBrowser = true }),
            ("ENGINEERING", "music.note.list", "Serata", { tastiera = false; scheda = .serata }),
            ("ENGINEERING", "phone", "Telefono", { tastiera = false; scheda = .telefono }),
            ("ENGINEERING", "cube.transparent", "LiDAR", { tastiera = false; jarvis.interrompi(); mostraLidar = true }),
        ]
    }

    private func chiedi(_ frase: String, nascosto: String? = nil) {
        tastiera = false
        Task { await jarvis.invia(frase, nascosto: nascosto) }
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

    /// Il centro del HUD: la corona col reattore, lo stato, la telemetria, la frase in corso e gli avvisi.
    /// Sull'iPhone il reattore non sta qui dentro ma sopra (`reattoreVolante`): qui c'è solo il suo posto, da cui vola nella barra in alto.
    private var centroHUD: some View {
        VStack(spacing: 0) {
            corona(reattoreFuori: telefono)
                .padding(.top, 26)        // il reattore più verso il centro dello schermo
            testiHUD
                .contentShape(Rectangle())
                .highPriorityGesture(tiraGiuTendina)
        }
    }

    /// Sotto il reattore: lo stato, la telemetria, la frase che sta dicendo (o il suggerimento) e gli avvisi.
    private var testiHUD: some View {
        VStack(spacing: 0) {
            Text(jarvis.etichettaFase)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(Color.ciano)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.3), value: jarvis.fase)
                .padding(.top, 8)
            TelemetriaHUD(fase: jarvis.fase)
                .padding(.top, 4)
                .opacity(acceso ? 1 : 0)
            if !jarvis.diagnosiMac.isEmpty {         // solo sul Mac: cosa sente il microfono in attesa
                Text(jarvis.diagnosiMac)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.tenue)
                    .lineLimit(1)
                    .padding(.top, 2)
            }

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
        }
    }

    /// `reattoreFuori`: il reattore lo disegna `reattoreVolante` (iPhone), qui resta il suo posto (240 × 240), misurato.
    private func corona(reattoreFuori: Bool = false) -> some View {
        let elenco = tutteLeIcone
        let ang = angoli
        let coda = Avvio.inizioCoda(elenco.map { $0.nome })
        let r = ContentView.raggioCorona
        let passo = ang.count > 1 ? abs(ang[1] - ang[0]) : 0.2
        // il cerchio ora è intero: in basso c'è INTELLIGENCE, con il suo nome sotto le icone
        let altezza = ContentView.latoCorona / 2 + r + 40
        return ZStack {
            // archi e nomi dei gruppi, sotto le icone (MARK XI: girano con la ruota)
            ArchiRuota(ruota: ruota, gruppi: elenco.map(\.gruppo), angoli: ang, accese: accese, raggio: r)
            // più alto della corona (stesso centro): il nome INTELLIGENCE, sotto le icone in basso, non viene più tagliato
            .frame(height: ContentView.latoCorona + 80)
            // 5 nov: la GHIERA (mockup v259), dentro le icone, solo mentre la ruota è viva
            GhieraRuota(ruota: ruota, angoli: ang, raggio: r)
                .frame(height: ContentView.latoCorona + 80)

            // il reattore al centro, della misura di sempre (sull'iPhone solo il suo posto: il reattore vola sopra)
            if reattoreFuori {
                Color.clear
                    .frame(width: 240, height: 240)
                    .anchorPreference(key: PostiReattore.self, value: .bounds) { ["grande": $0] }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                Button { tastiera = false; jarvis.toccaReattore() } label: { reattore }
                    .buttonStyle(StileStark())
                    .scaleEffect(acceso ? 1 : 0.7)
                    .opacity(acceso ? 1 : 0)
                    .accessibilityLabel("Parla con Jarvis")
                    .modifier(VeloRuota(ruota: ruota))
                ologramma
            }

            // le icone
            ForEach(Array(elenco.enumerated()), id: \.offset) { k, s in
                let inCorso = iconaAttiva == k && jarvis.fase != .attesa
                let accesa = k < accese
                Button {
                    ruota.spegni()                                       // MARK XI: si apre una sezione, l'ologramma si spegne
                    Suoni.tocco()
                    if ["Occhi", "Cucina"].contains(s.nome) { iconaAttiva = k }
                    s.azione()
                } label: {
                    Group {
                        if s.icona == "profiler" { IconaProfiler() } else if s.icona == "satellite" { IconaSatellite(lato: 18) } else { Image(systemName: s.icona) }
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
                .disabled(jarvis.fase == .elaboro && s.nome != "Browser" && (s.gruppo != "INTELLIGENCE" || s.nome == "Bea"))
                .opacity(accesa ? 1 : 0)
                .scaleEffect(accesa ? 1 : 2.4)                      // grande e trasparente, poi si restringe e si accende
                .brightness(k == accese - 1 && accese < elenco.count ? 0.35 : 0)   // lampo solo mentre si accende: l'ultima non resta chiara
                .animation(.spring(duration: k >= coda ? Avvio.mollaCoda : 0.32, bounce: 0.25), value: accese)   // da Interprete: la stessa molla, più svelta
                .modifier(PostoRuota(ruota: ruota, indice: k, base: ang[k], raggio: r, passo: passo))   // MARK XI: gira con la ruota, lente in alto
            }
        }
        .frame(maxWidth: .infinity).frame(height: ContentView.latoCorona)          // largo quanto lo schermo: i nomi non vengono tagliati
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rettCorona = $0 }
        .contentShape(Rectangle())
        .highPriorityGesture(gestoCorona)                                          // MARK XI: sull'anello gira la ruota, altrove la tendina
        .frame(maxWidth: .infinity).frame(height: altezza, alignment: .top)       // sotto resta lo spazio per la chat
    }

    /// Il reattore: la ghiera (290), il cuore (308: il 140% dal 7 nov) e le coordinate, nel quadrato di 240.
    private var reattore: some View {
        ZStack {
            AnelliHUD(fase: jarvis.fase).frame(width: 290, height: 290)
            Reattore(fase: jarvis.fase).frame(width: 308, height: 308)        // 7 nov sera (il signore: «140 il cuore»): era 220
            EtichetteGhiera(fase: jarvis.fase).frame(width: 290, height: 290)   // le coordinate sopra il cuore, niente sopra di loro
        }
        .frame(width: 240, height: 240)
        // MARK XI: si tocca il cerchio del reattore, non il quadrato degli anelli (290): l'anello delle icone resta della ruota
        .contentShape(Circle())
    }

    /// Il lato del reattore piccolo nella barra in alto (tastiera aperta): gli anelli da 290 rimpiccioliti a 34.
    static let latoMini: CGFloat = 26                  // 26 ott notte: il disegno visibile del reattore grande quanto le icone (con 18 era più piccolo)

    /// Build 23, come nel mockup («vola»): un reattore solo, che con la tastiera vola dal suo posto al centro al posto piccolo nella
    /// barra in alto (tra «J.A.R.V.I.S.» e le icone) rimpicciolendo, e ritorno, nello stesso tempo e con la stessa curva della
    /// tastiera di iOS (keyboardWillShow / keyboardWillHide). Solo posizione e scala: non sparisce al centro per ricomparire in alto.
    @ViewBuilder private func reattoreVolante(_ posti: [String: Anchor<CGRect>]) -> some View {
        let piccolo = !reattoreGrande
        GeometryReader { g in
            if telefono, let posto = posti[piccolo ? "piccolo" : "grande"] {     // iPad e Mac: il reattore resta nella corona
                let r = g[posto]
                Button {
                    tastiera = false                                   // piccolo: chiude la tastiera e basta
                    if !piccolo { jarvis.toccaReattore() }
                } label: { reattore }
                .buttonStyle(StileStark())
                .scaleEffect(piccolo ? ContentView.latoMini / 290 : (acceso ? 1 : 0.7))
                .shadow(color: .ciano.opacity(piccolo ? 0.85 : 0), radius: 3)       // MARK X (mockup b32): piccolo, ma luminoso
                .opacity(acceso ? 1 : 0)
                .position(x: r.midX, y: r.midY)
                .highPriorityGesture(tiraGiuTendina)                    // giù col dito dal reattore: la tendina PROTOCOLLI, come prima
                .accessibilityLabel(piccolo ? "Chiudi la tastiera" : "Parla con Jarvis")
                .modifier(VeloRuota(ruota: ruota))
                if !piccolo {
                    ologramma.position(x: r.midX, y: r.midY)            // MARK XI: l'ologramma dell'icona in alto, al posto del reattore
                }
            }
        }
    }

    /// Il volo del reattore (e con lui la chat che sale, la riga di stato, le icone che si spengono): la durata della tastiera,
    /// la curva della tastiera di iOS.
    private func vola(grande: Bool, durata: Double) {
        guard reattoreGrande != grande else { return }
        withAnimation(.timingCurve(0.38, 0.7, 0.125, 1, duration: max(durata, 0.2))) { reattoreGrande = grande }
    }

    /// La durata dell'animazione della tastiera scritta nella notifica di iOS (di solito 0,25 s).
    private static func durataTastiera(_ n: Notification) -> Double {
        (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    }

    /// INTELLIGENCE: il reparto speciale, una fila centrata sotto il reattore. Si accende dopo la corona,
    /// con lo stesso «plim», lo stesso ingresso (grande e trasparente → piccola e nitida) e lo stesso tocco.
    private var intelligence: [(icona: String, nome: String, azione: () -> Void)] {
        [
            ("dot.radiowaves.left.and.right", "Sentinella", { tastiera = false; jarvis.interrompi(); mostraSentinella = true }),
            ("profiler", "Profiler", { tastiera = false; jarvis.interrompi(); profiler() }),
            ("waveform.and.mic", "Wiretap", { tastiera = false; jarvis.interrompi(); mostraWiretap = true }),
            ("satellite", "Satellite", { tastiera = false; scheda = .satellite }),   // build 23: SATELLITE prima di Bea (Bea sull'ultimo colpo)
            ("link", "Bea", { tastiera = false; scheda = .bea }),                    // 20 ott: Bea passa in INTELLIGENCE
        ]
    }

    // MARK: Build 22 · la tendina PROTOCOLLI (come il Centro di Controllo di iOS, come nel mockup)

    /// Il velo scuro e la tendina. Chiusa sta appena sopra lo schermo; mentre il dito la tira segue il dito.
    @ViewBuilder private func tendina(_ g: GeometryProxy) -> some View {
        let chiusa = -(altezzaTendina + 12)
        let y: CGFloat = tendinaAperta ? min(0, tendinaTrascina) : min(0, chiusa + max(0, tendinaTrascina))
        let quanto = max(0, min(1, 1 + y / (altezzaTendina + 12)))          // 0 chiusa, 1 tutta giù
        Color.black.opacity(0.45 * quanto)
            .ignoresSafeArea()
            .allowsHitTesting(tendinaAperta)
            .onTapGesture { chiudiTendina() }
            .zIndex(19)
        TendinaProtocolli(margineAlto: g.safeAreaInsets.top) { chiudiTendina() }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in if h > 100 { altezzaTendina = h } }
            .offset(y: y)
            .gesture(
                // su col dito per mandarla via (giù non va oltre: è già tutta aperta)
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        guard tendinaAperta, abs(v.translation.height) > abs(v.translation.width) else { return }
                        tendinaTrascina = min(0, v.translation.height)
                    }
                    .onEnded { v in
                        guard tendinaAperta else { return }
                        let su = -min(0, v.predictedEndTranslation.height)
                        if -tendinaTrascina > altezzaTendina * 0.3 || su > altezzaTendina * 0.5 { chiudiTendina() }
                        else { withAnimation(ContentView.curvaTendina) { tendinaTrascina = 0 } }
                    }
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .ignoresSafeArea(.keyboard)
            .opacity(quanto > 0 ? 1 : 0)                       // chiusa del tutto: nemmeno l'ombra sotto la barra di stato
            .allowsHitTesting(tendinaAperta)
            .accessibilityHidden(!tendinaAperta)
            .zIndex(20)
    }

    /// Giù col dito dal titolo o dal reattore: la tendina segue il dito (anche se torna su) e, lasciata oltre un terzo
    /// (o lanciata), scende tutta. Ha la precedenza sui tasti sotto solo quando il dito si muove: un tocco resta un tocco,
    /// e una tirata che finisce sul reattore non lo accende.
    private var tiraGiuTendina: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { v in tendinaSegue(v.translation) }
            .onEnded { v in tendinaLasciata(v.translation, previsto: v.predictedEndTranslation) }
    }

    /// 5 nov (il signore: «si aprono involontariamente e si cliccano male… come il Dock di Apple»): il tocco su un'icona in alto.
    /// Sul Mac (il puntatore le ha già ingrandite) apre; sull'iPhone apre solo se le icone sono già ingrandite (dopo il dito che
    /// scorre o un primo tocco): altrimenti le ingrandisce attorno all'icona toccata, e il tocco dopo apre quella giusta.
    private func toccaDock(_ i: Int) {
        guard testaArrivate >= ContentView.postoTesta.totale else { return }          // durante l'arrivo delle icone non si apre niente
        if ProcessInfo.processInfo.isiOSAppOnMac || dock.trattenuta || UIAccessibility.isVoiceOverRunning {   // VoiceOver: apre subito
            Suoni.clickDock()
            azioneDock(i)
        } else {
            dock.mostra(i)
        }
    }

    /// 5 nov (video del signore: «chiudendo il Trainer l'animazione si ferma a metà per circa un secondo»): riaccendere il
    /// richiamo («Jarvis» in attesa) prepara il microfono sul thread principale (sessione audio e motore nuovo) e capitava a metà
    /// della discesa della sezione, fermandola. Ora, quando il microfono torna libero, il richiamo si riaccende a discesa finita
    /// (0,45 s dopo); quando si deve spegnere, subito come prima. Il richiamo resta quello di sempre: cambia solo l'istante.
    private func consentiRichiamo(_ libero: Bool) {
        turnoRichiamo += 1
        guard libero else { jarvis.richiamoConsentito = false; return }
        guard !jarvis.richiamoConsentito else { return }
        let mio = turnoRichiamo
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard mio == turnoRichiamo, schermoLibero else { return }
            jarvis.richiamoConsentito = true
        }
    }

    /// MARK XI: cosa fa ogni icona del Dock (dal tocco sull'icona ingrandita).
    private func azioneDock(_ i: Int) {
        // 4 nov: la lente si spegne sempre quando un'icona apre qualcosa. Sul Mac il puntatore era ancora sopra l'icona quando la
        // sezione la copriva: l'icona restava ingrandita (anche dopo lo swipe veloce); ora le icone tornano sempre allineate.
        if dock.x != nil { dock.lascia() }
        switch i {
        case ContentView.postoTesta.social:
            Suoni.tocco(); if telefono { tastiera = false }; jarvis.interrompi(); alzaPagina(AperturaPagina(sezione: "Social"))
        case ContentView.postoTesta.musica:
            Suoni.tocco(); if telefono { tastiera = false }; scheda = .musica
        case ContentView.postoTesta.studio:
            Suoni.tocco(); if telefono { tastiera = false }; jarvis.interrompi(); alzaPagina(AperturaPagina(sezione: "Studio"))
        case ContentView.postoTesta.sistemi:
            jarvis.interrompi(); withAnimation(.spring(duration: 0.35, bounce: 0.2)) { mostraSistemi.toggle() }
        case ContentView.postoTesta.cestino:
            chiediPulizia = true
        case ContentView.postoTesta.impostazioni:
            if telefono { tastiera = false }; mostraImpostazioni = true
        default: break
        }
    }

    /// Il dito sulla testata: partito sulle icone del Dock (arrivate tutte) scorre sul Dock con la lente; partito altrove (il titolo)
    /// tira giù la tendina PROTOCOLLI, come sempre. Deciso al primo movimento.
    private var gestoTestata: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { v in
                if modoTestata == nil {
                    modoTestata = sulDock(v.startLocation) ? .ruota : .tendina
                    if modoTestata == .tendina, dock.x != nil { dock.lascia() }          // tirata altrove: le icone tornano piccole
                }
                if modoTestata == .ruota { dock.segui(v.location.x) } else { tendinaSegue(v.translation) }
            }
            .onEnded { v in
                if modoTestata == .ruota {
                    // 5 nov: alzando il dito non si apre niente: le icone restano grandi e aspettano il tocco (come il Dock)
                    dock.trattieni()
                } else {
                    tendinaLasciata(v.translation, previsto: v.predictedEndTranslation)
                }
                modoTestata = nil
            }
    }

    /// Il punto è sulle icone del Dock (a destra del titolo, all'altezza delle icone), finito il loro arrivo.
    private func sulDock(_ p: CGPoint) -> Bool {
        guard testaArrivate >= ContentView.postoTesta.totale, !mostraSistemi else { return false }
        return dock.vicino(p)
    }

    private func tendinaSegue(_ spostamento: CGSize) {
        guard !tendinaAperta, tendinaLibera else { return }
        if tendinaTrascina > 0 { tendinaTrascina = max(0.5, spostamento.height); return }   // già partita: segue il dito su e giù
        guard spostamento.height > 0, abs(spostamento.height) > abs(spostamento.width) * 1.2 else { return }
        tendinaTrascina = spostamento.height
    }

    private func tendinaLasciata(_ spostamento: CGSize, previsto: CGSize) {
        guard !tendinaAperta, tendinaTrascina > 0 else { tendinaTrascina = 0; return }
        if spostamento.height > altezzaTendina * 0.3 || previsto.height > altezzaTendina * 0.6 { apriTendina() }
        else { withAnimation(ContentView.curvaTendina) { tendinaTrascina = 0 } }
    }

    // MARK: MARK XI · il contenitore delle sezioni

    /// Le sezioni accese adesso (lo stato di sempre acceso), cioè quella davanti (di solito una sola).
    private var sezioniAccese: [Sezione] {
        var a: [Sezione] = []
        if mostraImpostazioni { a.append(.impostazioni) }
        if mostraBrowser { a.append(.browser) }
        if jarvis.occhi != nil { a.append(.occhi) }
        if jarvis.interprete != nil || scegliLingua { a.append(.interprete) }      // 9 nov: senza lingua, la sceglie lì dentro
        if mostraSentinella { a.append(.sentinella) }
        if mostraWiretap { a.append(.wiretap) }
        if mostraProfiler { a.append(.profiler) }
        if jarvis.allenatore { a.append(.allenatore) }
        if mostraLidar { a.append(.lidar) }
        if mostraVitals { a.append(.vitals) }
        if mostraRicordi != nil { a.append(.ricordi) }
        if mostraConfidente { a.append(.confidente) }
        if let sc = scheda { a.append(.scheda(sc)) }
        if let p = aperturaPagina { a.append(.pagina(p.sezione)) }
        return a
    }

    /// Una sezione si è accesa: davanti (se un'altra era davanti, va dietro). Una si è spenta: dietro o chiusa.
    private func sincronizzaSezioni(prima: [Sezione], adesso: [Sezione]) {
        let unaScheda: (Sezione) -> Bool = { if case .scheda = $0 { return true } else { return false } }
        let unaPagina: (Sezione) -> Bool = { if case .pagina = $0 { return true } else { return false } }
        for s in prima where !adesso.contains(s) {
            // una scheda al posto di un'altra (lo stato delle schede è uno solo): quella di prima va dietro, non si chiude
            if unaScheda(s), adesso.contains(where: unaScheda) { pila.vaDietro(s) }
            // 4 nov: lo stesso per Studio e Social (anche la pagina ha uno stato solo): Social aperto sopra Studio (o il
            // contrario) e quello di prima resta vivo dietro, con il suo lavoro («tutte restano vive dietro, anche Studio e Social»)
            if unaPagina(s), adesso.contains(where: unaPagina) { pila.vaDietro(s) }
            var chiusa = false
            withAnimation(StratoPagina.discesa()) { chiusa = pila.spenta(s) }
            if chiusa { sezioneChiusa(s) }
        }
        for s in adesso where !prima.contains(s) {
            // quella che era davanti ed è ancora accesa va dietro (come nel mockup: la sezione di prima resta viva)
            if let d = pila.voceDavanti?.sezione, d != s, adesso.contains(d) { pila.vaDietro(d); spegniStato(d) }
            // riaperta da zero (non ripresa da dietro): Occhi con un'altra richiesta, Interprete in un'altra lingua, Studio o Social
            // con una frase o una foto. Quella vecchia si chiude e sale la nuova.
            if riprendo != s, let vecchia = pila.voce(s), nuovaRichiesta(s, vecchia) {
                pila.togli(s)
            }
            if riprendo == s { riprendo = nil }
            // 9 nov notte (il signore: «la rotella di impostazioni non ha il suono di apertura scheda»): Impostazioni sale senza
            // caricamento e non aveva suono; ora quello d'apertura delle schede, solo quando si apre davvero (non da dietro)
            if s == .impostazioni, pila.voce(s) == nil { Suoni.schedaApre() }
            let occhiata: Occhiata? = s == .occhi ? jarvis.occhi : nil
            let lingua: Lingua? = s == .interprete ? jarvis.interprete : nil
            let pagina: AperturaPagina? = aperturaPagina.flatMap { s == .pagina($0.sezione) ? $0 : nil }
            withAnimation(StratoPagina.salita) {
                if let vecchia = pila.accesa(s, ricordi: s == .ricordi ? mostraRicordi : nil, occhiata: occhiata, lingua: lingua, pagina: pagina) {
                    pila.togli(vecchia)                               // più di 10: la più vecchia si chiude
                    sezioneChiusa(vecchia)
                }
            }
            ruota.spegni()
        }
    }

    /// La richiesta è nuova (non la stessa sezione che torna davanti)?
    private func nuovaRichiesta(_ s: Sezione, _ v: PilaSezioni.Voce) -> Bool {
        switch s {
        case .occhi: return true
        case .interprete: return v.lingua?.id != jarvis.interprete?.id
        case .pagina:
            guard let a = aperturaPagina else { return false }
            return a.conRichiesta
        default: return false
        }
    }

    /// Quello che succedeva alla chiusura della schermata di iOS (onDismiss).
    private func sezioneChiusa(_ s: Sezione) {
        switch s {
        case .impostazioni:
            eseguiComando()
            if jarvis.svuotaChiesto {                    // «Nuova conversazione»: a foglio chiuso, la stessa animazione del cestino
                jarvis.svuotaChiesto = false
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); svuotaChat() }
            }
        case .occhi: jarvis.occhiChiusi([])
        default: break
        }
    }

    /// Spegne lo stato della sezione (davanti → dietro, se prima è stata segnata con `vaDietro`; altrimenti la chiude).
    private func spegniStato(_ s: Sezione) {
        switch s {
        case .impostazioni: mostraImpostazioni = false
        case .browser: mostraBrowser = false
        case .occhi: jarvis.occhiChiusi([])               // dietro: JARVIS non resta ad aspettare la foto (davanti la riaspetta)
        case .interprete: jarvis.interprete = nil; scegliLingua = false
        case .sentinella: mostraSentinella = false
        case .wiretap: mostraWiretap = false
        case .profiler: mostraProfiler = false
        case .allenatore: jarvis.allenatore = false
        case .lidar: mostraLidar = false
        case .vitals: mostraVitals = false
        case .ricordi: mostraRicordi = nil
        case .confidente: mostraConfidente = false
        case .scheda(let sc): if scheda == sc { scheda = nil }
        case .pagina: aperturaPagina = nil
        }
    }

    /// Riaccende lo stato di una sezione che sta dietro: torna davanti (le spente si riaprono, la fotocamera col suo suono).
    private func accendiStato(_ v: PilaSezioni.Voce) {
        riprendo = v.sezione
        switch v.sezione {
        case .impostazioni: mostraImpostazioni = true
        case .browser: mostraBrowser = true
        case .occhi: if let o = v.occhiata { jarvis.riprendiOcchi(o) }       // la stessa inquadratura, e JARVIS riaspetta la foto
        case .interprete: if let l = v.lingua { jarvis.interprete = l } else { scegliLingua = true }   // 9 nov: senza lingua, la scelta
        case .wiretap: mostraWiretap = true
        case .sentinella: mostraSentinella = true
        case .profiler: profiler()
        case .allenatore: jarvis.allenatore = true
        case .lidar: mostraLidar = true
        case .vitals: mostraVitals = true
        case .ricordi: mostraRicordi = v.ricordi ?? .ricordi
        case .confidente: mostraConfidente = true
        case .scheda(let sc): scheda = sc
        case .pagina: aperturaPagina = v.pagina
        }
    }

    /// Manda dietro la sezione davanti (resta viva, o spenta se ha la fotocamera): davanti torna JARVIS.
    private func mandaDietroDavanti() {
        guard let d = pila.voceDavanti?.sezione else { return }
        pila.vaDietro(d)
        spegniStato(d)
    }

    /// Porta davanti una sezione che sta dietro (dalle pagine olografiche o dallo swipe dai bordi); nil: JARVIS.
    private func portaDavanti(_ id: UUID?) {
        guard let id else { mandaDietroDavanti(); return }
        guard let v = pila.voci.first(where: { $0.id == id }), pila.davanti != id else { return }
        mandaDietroDavanti()
        accendiStato(v)
    }

    /// Il contenitore: le sezioni in ordine d'apertura; quella davanti si vede e si tocca, le altre restano vive e invisibili
    /// (le spente non si disegnano). Con i gesti per muoversi fra loro (NavigaSezioni.swift).
    private var strato: some View {
        StratoSezioniVista(pila: pila, naviga: naviga, reattore: CGPoint(x: rettCorona.midX, y: rettCorona.midY),
                           diametroReattore: rettCorona.height * 290 / ContentView.latoCorona,
                           vista: { v in vistaSezione(v) },
                           portaDavanti: { id in portaDavanti(id) },
                           chiudiDietro: { id in chiudiDietro(id) },
                           icone: Dictionary(tutteLeIcone.map { ($0.nome, $0.icona) }, uniquingKeysWith: { a, _ in a }))
    }

    /// Dalle pagine olografiche (o a voce, «chiudi il meteo»): la sezione si chiude, davanti o dietro che sia.
    private func chiudiDietro(_ id: UUID) {
        guard let v = pila.voci.first(where: { $0.id == id }) else { return }
        if v.sezione == .wiretap { chiudiWiretap(); return }       // 9 nov: con del testo si salva da solo nell'Archivio
        if pila.davanti == id { spegniStato(v.sezione); return }
        pila.togli(v.sezione)
        sezioneChiusa(v.sezione)
    }

    /// 4 nov (il signore): il Wiretap chiuso da fuori (pagine olografiche, «chiudi tutto», «chiudi il Wiretap»). 9 nov notte: niente
    /// più verbale automatico; con del testo si salva da solo nell'Archivio (cartella Wiretap). Dietro, poi esce anche dall'elenco.
    private func chiudiWiretap() {
        guard let v = pila.voce(.wiretap) else { return }
        let dietro = pila.davanti != v.id
        if let comeIlSuoChiudi = WiretapAperto.chiudi { comeIlSuoChiudi() } else if !dietro { mostraWiretap = false }
        if dietro { pila.togli(.wiretap) }
    }

    /// «Jarvis, chiudi tutto» (4 nov, il signore): si chiudono tutte le sezioni aperte, anche quelle dietro, e quello che sta
    /// sopra (come «Jarvis, chiudi»). Il Wiretap con del testo lo salva nell'Archivio (9 nov).
    private func chiudiTutteLeSezioni() {
        if tendinaAperta || tendinaTrascina != 0 { chiudiTendina() }
        for v in pila.voci where v.id != pila.davanti && v.sezione != .wiretap {
            pila.togli(v.sezione)
            sezioneChiusa(v.sezione)
        }
        chiudiWiretap()
        chiudiTutto()
    }

    /// MARK XI (4 nov, il signore): i comandi a voce delle sezioni aperte. JARVIS parla solo quando non si vede cosa è successo
    /// (una sezione chiusa dietro, una che non c'è) e solo se il microfono è il suo: dalle sezioni col microfono (Wiretap,
    /// Interprete, Trainer…) la sua voce finirebbe nell'ascolto, e lì basta la vibrazione.
    private func comandoSezioni(_ c: ComandoVocale) {
        let parla = schermoLibero
        let fatto = { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }   // il comando è arrivato, come gli altri
        let dici: (String) -> Void = { frase in
            if parla { jarvis.annuncia(frase) } else { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
        switch c {
        case .chiudiSezioni:
            fatto()
            chiudiTutteLeSezioni()
        case .chiudiSezione(let nome):
            guard let v = pila.voci.first(where: { $0.sezione.nome == nome }) else { dici("La sezione \(nome) non è aperta, Sir."); return }
            fatto()
            let dietro = pila.davanti != v.id
            chiudiDietro(v.id)
            if dietro && parla { jarvis.annuncia("Sezione \(nome) chiusa, Sir.") }      // non si vede: lo dice
        case .sezioniAperte:
            guard !pila.voci.isEmpty else { dici("Nessuna sezione aperta, Sir."); return }
            fatto()
            liberaSopra()
            naviga.chiesta = .sfoglio
        case .sezionePrima:
            guard let id = sezioneDiPrima() else {
                dici(pila.voci.isEmpty ? "Nessuna sezione aperta, Sir." : "Non c'è un'altra sezione aperta, Sir.")
                return
            }
            fatto()
            liberaSopra()
            naviga.chiesta = .porta(id)
        case .daParte:
            guard pila.voceDavanti != nil || naviga.modo == .sfoglio else {
                dici(pila.voci.isEmpty ? "Nessuna sezione aperta, Sir." : "Nessuna sezione davanti, Sir.")
                return
            }
            fatto()
            liberaSopra()
            naviga.chiesta = .aggancio
        default:
            break
        }
    }

    /// MARK XI · i comandi sentiti dal Wiretap che valgono per JARVIS e la sezione davanti: le sezioni aperte a voce («quella di
    /// prima», «chiudi il meteo», «fai il verbale»…), «Jarvis, apri…» (4 nov, il signore: il Wiretap davanti va dietro e continua a
    /// registrare) e, col Wiretap dietro, «Jarvis, chiudi».
    /// Il richiamo di JARVIS tace (il microfono è del Wiretap): qui si fa quello che farebbe lui, senza la sua voce, che finirebbe
    /// nella registrazione (basta la vibrazione). Con davanti una sezione col suo microfono (Trainer, Interprete, Sentinella,
    /// Profiler, Scanner) il comando l'ha già sentito lei: qui si fanno solo quelli del Wiretap.
    private func comandoDalWiretap(_ c: ComandoVocale) {
        let delWiretap: Bool = c == .chiudiSezione(Sezione.wiretap.nome)      // «fai il verbale», «ferma la registrazione»…
        let altroOrecchio: Bool = jarvis.interprete != nil || jarvis.allenatore || mostraSentinella || mostraProfiler || scheda == .scanner
        guard delWiretap || !altroOrecchio else { return }
        if c.navigaSezioni { comandoSezioni(c); return }
        switch c {
        case .torna:                                     // come «Jarvis, chiudi» da JARVIS: la sezione davanti (il Wiretap dietro resta)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if tendinaAperta { chiudiTendina() }
            chiudiTutto()
        case .apri(let r):
            if r == .scanner && LidarAperta.aperta { return }      // come JARVIS: dentro LiDAR «scansione» è la stanza
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            apriReparto(r)
        case .pagina(let nome, let voce, let cosa):              // Studio e Social
            jarvis.apriPagina(nome, voce: voce, scheda: cosa, parla: false)
        default:
            break
        }
    }

    /// È cambiata la sezione davanti: a salita finita (la molla si posa in ~0,5 s) JARVIS sotto si ferma; e si ricorda l'ordine
    /// in cui sono state davanti (le chiuse escono), per «Jarvis, quella di prima».
    private func davantiCambiata(_ d: UUID?) {
        if let d {
            giroDavanti.removeAll { id in id == d || !pila.voci.contains { $0.id == id } }
            giroDavanti.append(d)
        }
        if d == nil { pilaCopre = false; return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            if pila.davanti == d { pilaCopre = true }
        }
    }

    /// La sezione che era davanti prima di quella di adesso (con JARVIS davanti: l'ultima che c'era).
    private func sezioneDiPrima() -> UUID? {
        let vive = Set(pila.voci.map(\.id))
        let davanti = pila.davanti
        if let id = giroDavanti.last(where: { vive.contains($0) && $0 != davanti }) { return id }
        return pila.voci.last(where: { $0.id != davanti })?.id
    }

    /// La vista di ogni sezione: quella che prima stava nella sua schermata di iOS, uguale.
    @ViewBuilder private func vistaSezione(_ v: PilaSezioni.Voce) -> some View {
        switch v.sezione {
        case .impostazioni:
            ImpostazioniView().environmentObject(jarvis).paginaPiena()                 // 27 ott: senza caricamento, sale come le altre
        case .browser:
            BrowserPrivato()
        case .occhi:
            if let o = v.occhiata {
                Occhi(automatico: o.automatico, video: o.video, cucina: o.cucina, zoomIniziale: o.zoom,
                      oloIniziale: o.olo, etiIniziale: o.eti, agganciaIniziale: o.aggancia, mandaIniziale: o.manda, aereoIniziale: o.aereo) { dati in jarvis.occhiChiusi(dati) }
                    .aperturaHUD(o.cucina ? "Cucina" : "Occhi", icona: o.cucina ? "fork.knife" : "eye", conX: true, soloSfuma: true)      // 26 ott notte: il caricamento come le altre schede
            }
        case .interprete:
            // 9 nov notte (il signore: «si apre due volte ed è orribile così»): una sezione sola, come il mockup. Dall'icona si apre
            // senza lingua e la si sceglie nel pannello LINGUA, lì dentro; «Jarvis, traduci in tedesco» la apre già con la lingua
            Interprete(lingua: v.lingua ?? jarvis.interprete, scelta: { l in jarvis.interrompi(); jarvis.interprete = l }) {
                jarvis.interprete = nil; scegliLingua = false
            }
            .paginaPiena()
        case .sentinella:
            VistaSentinella(chiudi: { mostraSentinella = false }, comando: comandoDaReparto)
        case .wiretap:
            VistaWiretap(verbale: { testo, minuti in
                mostraWiretap = false
                jarvis.verbaleWiretap(testo, minuti: minuti)
            }, chiudi: { mostraWiretap = false }, comando: comandoDaReparto, aJarvis: comandoDalWiretap, avviaSubito: jarvis.riunioneSubito)
        case .profiler:
            VistaProfiler { dati, nome in
                mostraProfiler = false
                if !dati.isEmpty { jarvis.profila(dati, nome: nome) }
            }
            .aperturaHUD("Profiler", icona: "person.text.rectangle", conX: true, soloSfuma: true)                                 // 26 ott notte: il caricamento come tutte le sezioni
        case .allenatore:
            Allenatore { jarvis.allenatore = false }
        case .lidar:
            VistaLidar(chiudi: { mostraLidar = false }, chiedi: { frase in mostraLidar = false; chiedi(frase) })
                .aperturaHUD("LiDAR", icona: "cube.transparent", conX: true)                                                  // 26 ott notte: il caricamento come le altre schede
                .environmentObject(jarvis)          // i comandi a voce di LiDAR («fine scansione», «salva»…)
        case .vitals:
            VistaVitals { frase in mostraVitals = false; chiedi(frase) }.paginaPiena()
        case .ricordi:
            VistaRicordi(iniziale: v.ricordi ?? .ricordi, guida: guidaRicordi, salva: salvaRicordi) { frase in mostraRicordi = nil; chiedi(frase) }.paginaPiena()
        case .confidente:
            VistaConfidente(invia: { testo, nascosto in mostraConfidente = false; chiedi(testo, nascosto: nascosto) },
                            aVoce: { mostraConfidente = false; jarvis.chiediDiario("Modalità confidente. Mi racconti pure, Sir: la ascolto.") }).paginaPiena()
        case .scheda(let sc):
            vistaScheda(sc).paginaPiena()
        case .pagina:
            if let a = v.pagina {
                // MARK X: Studio e Social (la pagina del mockup), ora una sezione come le altre: si chiudono col loro «Chiudi»
                // o trascinando giù dalla fascia dell'ora
                // 8 nov mattina: nel margine sicuro come ogni sezione (la pagina web va a tutto schermo da sé, VistaStudio)
                VistaStudio(apertura: a, parla: { [jarvis] frase in jarvis.annuncia(frase) }, chiudi: { aperturaPagina = nil })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .paginaPiena()
            }
        }
    }

    /// Le schede delle icone.
    @ViewBuilder private func vistaScheda(_ sc: SchedaApp) -> some View {
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
        case .email: VistaPosta(chiedi: daScheda) { frase, testo in scheda = nil; chiedi(frase, nascosto: testo) }   // 7 nov: il lettore
        case .spesa: VistaSpesa(chiedi: daScheda)
        case .shazam: VistaShazam(chiedi: daScheda, apriMusica: { scheda = .musica })
        case .foto: VistaFotoScheda(chiedi: daScheda)
        case .serata: VistaSerata(chiedi: daScheda)
        case .messaggi: VistaMessaggi(chiedi: daScheda)
        case .telefono: VistaTelefono(chiedi: daScheda)
        case .github: VistaGitHub(chiedi: daScheda, apri: apriPagina)
        case .supabase: VistaSupabase(chiedi: daScheda)
        case .archivio: VistaArchivio(chiedi: daScheda, apri: apriPagina)
        case .costi: VistaCosti(chiedi: daScheda)
        case .edith: VistaEdith(chiedi: daScheda)
        case .scanner: VistaScanner(chiedi: daScheda)
        case .bea: VistaBea(chiedi: daScheda)
        case .satellite: VistaSatellite(parla: { [jarvis] frase in jarvis.annuncia(frase) })
        case .musica: VistaMusica()
        }
    }

    // MARK: MARK XI · la click wheel

    /// Il dito sulla corona. Sull'anello delle icone (finito l'avvio, tastiera chiusa) gira la ruota; altrove (il centro, il reattore)
    /// resta la tendina PROTOCOLLI di sempre. Deciso al primo movimento (7 punti): un tocco resta un tocco.
    private var gestoCorona: some Gesture {
        DragGesture(minimumDistance: 7, coordinateSpace: .global)
            .onChanged { v in
                if modoCorona == nil {
                    if sullAnello(v.startLocation) {
                        modoCorona = .ruota
                        ruota.inizia(base: angoli, angolo: angoloDito(v.startLocation))
                    } else {
                        modoCorona = .tendina
                    }
                }
                if modoCorona == .ruota { ruota.trascina(angolo: angoloDito(v.location)) }
                else if v.translation.height > 0 || tendinaTrascina > 0 { tendinaSegue(v.translation) }
            }
            .onEnded { v in
                if modoCorona == .ruota { ruota.lascia() } else { tendinaLasciata(v.translation, previsto: v.predictedEndTranslation) }
                modoCorona = nil
            }
    }

    /// Il dito è sull'anello delle icone (fra 24 punti dentro e 44 fuori dal raggio), finito l'avvio e con la tastiera chiusa.
    private func sullAnello(_ p: CGPoint) -> Bool {
        guard accese >= tutteLeIcone.count, !tastiera, rettCorona.height > 0 else { return false }
        let k = rettCorona.height / ContentView.latoCorona
        let d = hypot(p.x - rettCorona.midX, p.y - rettCorona.midY) / k
        return d >= ContentView.raggioCorona - 24 && d <= ContentView.raggioCorona + 44
    }

    private func angoloDito(_ p: CGPoint) -> Double {
        Double(atan2(p.y - rettCorona.midY, p.x - rettCorona.midX))
    }

    /// L'ologramma dell'icona in alto, nel reattore: toccato apre la sezione, come il tocco sull'icona.
    private var ologramma: some View {
        OlogrammaRuota(ruota: ruota, voci: tutteLeIcone.map { (nome: $0.nome, gruppo: $0.gruppo, icona: $0.icona) }, aperte: pila.nomiAperti) { k in
            let elenco = tutteLeIcone
            guard elenco.indices.contains(k) else { return }
            let s = elenco[k]
            ruota.spegni()
            guard !(jarvis.fase == .elaboro && s.nome != "Browser" && (s.gruppo != "INTELLIGENCE" || s.nome == "Bea")) else { return }
            Suoni.tocco()
            if ["Occhi", "Cucina"].contains(s.nome) { iconaAttiva = k }
            s.azione()
        }
    }

    /// La tendina scende solo sulla schermata principale libera: niente tastiera aperta, niente menu SISTEMI.
    private var tendinaLibera: Bool { !tastiera && !mostraSistemi }

    private func apriTendina() {
        if !tendinaAperta { Suoni.clickTesta() }                 // il click delle icone in alto, come nel mockup
        if telefono { tastiera = false }
        withAnimation(ContentView.curvaTendina) { tendinaAperta = true; tendinaTrascina = 0 }
    }

    private func chiudiTendina() {
        withAnimation(ContentView.curvaTendina) { tendinaAperta = false; tendinaTrascina = 0 }
    }

    /// La curva della tendina: parte decisa e si posa piano (0,42 s, come nel mockup).
    static let curvaTendina: Animation = .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.42)

    /// Chiude tutto quello che è aperto sopra la schermata principale.
    private func chiudiTutto() {
        if telefono { tastiera = false }
        if !tendinaAperta { tendinaTrascina = 0 }        // una tirata rimasta a metà (gesto interrotto) non resta appesa
        mostraSentinella = false
        if mostraWiretap { chiudiWiretap() }              // 4 nov: davanti con del testo, parte il verbale (niente si perde)
        mostraProfiler = false
        scheda = nil
        mostraVitals = false
        mostraConfidente = false
        mostraRicordi = nil
        mostraBrowser = false
        withAnimation(.spring(duration: 0.3)) { mostraSistemi = false }
        mostraImpostazioni = false
        jarvis.pagina = nil
        sorgenteFoto = nil
        scegliLingua = false
        chiediPulizia = false
        jarvis.allenatore = false
        mostraLidar = false
        jarvis.occhiChiusi([])
        aperturaPagina = nil                              // 4 nov: anche Studio e Social («Jarvis, chiudi» non li chiudeva)
    }

    /// 4 nov · MARK XI: prima che salga una sezione chiesta da JARVIS (Studio, Social, gli Occhi, l'Interprete) si chiude solo
    /// quello che sta sopra a tutto: la tendina PROTOCOLLI (decisione 15), la tastiera, il menu SISTEMI, la pagina web e la
    /// fotocamera di sistema, la domanda «Pulire la conversazione?». La sezione davanti no: va dietro da sola
    /// (sincronizzaSezioni) e resta viva, come nel mockup.
    private func liberaSopra() {
        if tendinaAperta || tendinaTrascina != 0 { chiudiTendina() }
        if telefono { tastiera = false }
        if mostraSistemi { withAnimation(.spring(duration: 0.3)) { mostraSistemi = false } }
        jarvis.pagina = nil
        sorgenteFoto = nil
        chiediPulizia = false
    }

    /// 26 ott sera: Studio o Social salgono come strato sopra JARVIS (StratoPagina), con la salita delle altre schede. A salita
    /// finita (la molla si posa in ~0,5 s) JARVIS sotto è tutto coperto e le sue animazioni si fermano (jarvisCoperto).
    private func alzaPagina(_ a: AperturaPagina) {
        aperturaPagina = a                                   // MARK XI: nel contenitore, come le altre sezioni
    }

    /// Studio o Social si chiudono (scendono come le altre sezioni).
    private func abbassaPagina(_ durata: Double = 0.35) {
        _ = durata
        aperturaPagina = nil
    }

    /// La sezione del contenitore che apre un reparto (nil: non è una sezione, oppure ogni richiesta riparte da capo, come gli
    /// Occhi, il giro e la Cucina).
    private func sezione(di r: Reparto) -> Sezione? {
        switch r {
        case .sentinella: return .sentinella
        case .wiretap: return .wiretap
        case .profiler: return .profiler
        case .occhi, .giro, .cucina: return nil
        case .vitals: return .vitals
        case .confidente: return .confidente
        case .allenatore: return .allenatore
        case .ricordi: return .ricordi
        case .interprete: return .interprete
        case .browser: return .browser
        case .lidar: return .lidar
        case .impostazioni: return .impostazioni
        case .sistemi, .pulisci: return nil
        case .scanner: return .scheda(.scanner)
        case .satellite: return .scheda(.satellite)
        case .diario: return .scheda(.diario)
        case .sonno: return .scheda(.sonno)
        case .cuore: return .scheda(.cuore)
        case .bea: return .scheda(.bea)
        case .briefing: return .scheda(.briefing)
        case .meteo: return .scheda(.meteo)
        case .email: return .scheda(.email)
        case .spesa: return .scheda(.spesa)
        case .shazam: return .scheda(.shazam)
        case .foto: return .scheda(.foto)
        case .serata: return .scheda(.serata)
        case .messaggi: return .scheda(.messaggi)
        case .telefono: return .scheda(.telefono)
        case .github: return .scheda(.github)
        case .supabase: return .scheda(.supabase)
        case .archivio: return .scheda(.archivio)
        case .costi: return .scheda(.costi)
        case .edith: return .scheda(.edith)
        case .musica: return .scheda(.musica)
        }
    }

    /// Il reparto è chiesto con qualcosa da fare appena aperto (TRACCIA di Ricordi con la guida o il salvataggio, la guida, il
    /// TRAVEL o la ricognizione di SATELLITE, un modo di LiDAR, i video del Browser): allora non è solo «apri».
    private func conRichiesta(_ r: Reparto) -> Bool {
        switch r {
        case .ricordi: return jarvis.richiestaTraccia
        case .satellite: return RichiestaSatellite.condivisa.azione != nil
        case .lidar: return LidarAperta.richiesta != nil
        case .browser: return CercaVideo.richiesta != nil || CercaWeb.richiesta != nil
        case .shazam: return VistaShazam.ascoltaSubito                  // 5 nov: a voce Shazam ascolta subito, anche se è già aperto
        default: return false
        }
    }

    /// 4 nov (il signore, strada B): la sezione già aperta fa sul posto la richiesta nuova («portami al luogo», «come arrivo da
    /// Bea?», «metro laser», «video di…»), senza riaprirsi. Ricordi riceve qui la guida e il salvataggio; SATELLITE, LiDAR e il
    /// Browser trovano la richiesta dove l'ha lasciata JARVIS (RichiestaSatellite, LidarAperta, CercaVideo).
    private func richiestaSulPosto(_ r: Reparto, guida: Bool, salva: Bool) {
        NotificationCenter.default.post(name: .jarvisRichiestaSezione, object: nil,
                                        userInfo: ["reparto": r.rawValue, "guida": guida, "salva": salva])
    }

    /// Apre un reparto chiesto a voce; se ce n'è già uno aperto, prima lo chiude.
    private func apriReparto(_ r: Reparto) {
        // MARK XI: le sezioni stanno nel contenitore: quella davanti va dietro (resta viva) e la nuova sale subito. Solo la pagina
        // web e la fotocamera di sistema sono ancora schermate di iOS: lì si aspetta che si chiudano.
        let aperto = jarvis.pagina != nil || sorgenteFoto != nil
        if r == .shazam { VistaShazam.ascoltaSubito = true }               // 5 nov: chiesto a voce, Shazam ascolta subito
        if tendinaAperta { chiudiTendina() }      // come nel mockup: la sezione chiesta a voce non si apre con la tendina PROTOCOLLI rimasta giù dietro
        // 4 nov (il signore, strada B): già aperta, davanti o dietro, e con una richiesta nuova: la fa sul posto (sotto)
        let s: Sezione? = sezione(di: r)
        let sulPosto: Bool = s.map { pila.voce($0) != nil } == true && conRichiesta(r)
        let guida = jarvis.guidaTraccia, salva = jarvis.salvaTraccia
        // 4 nov (il signore): chiesta mentre è già davanti («Jarvis, apri il meteo» col Meteo aperto) resta ferma, senza andare dietro
        // e tornare; JARVIS risponde lo stesso (la sua frase l'ha già detta). Con una richiesta nuova, la fa lì
        if let s, pila.voceDavanti?.sezione == s {
            liberaSopra()
            if sulPosto {
                if r == .ricordi { jarvis.guidaTraccia = false; jarvis.salvaTraccia = false; jarvis.richiestaTraccia = false }
                richiestaSulPosto(r, guida: guida, salva: salva)
            }
            return
        }
        mandaDietroDavanti()
        chiudiTutto()
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
            case .satellite: scheda = .satellite
            case .ricordi:                                         // build 22: TRACCIA per prima, come nel mockup
                guidaRicordi = jarvis.guidaTraccia                 // con la Guida solo se è stato «portami al luogo»
                salvaRicordi = jarvis.salvaTraccia                 // e salva subito solo se è stato «ricorda questo luogo»
                jarvis.guidaTraccia = false
                jarvis.salvaTraccia = false
                jarvis.richiestaTraccia = false
                mostraRicordi = .traccia
            case .interprete: apriInterprete()
            case .browser: mostraBrowser = true
            case .lidar: mostraLidar = true
            case .costi: scheda = .costi
            case .edith: scheda = .edith
            case .sistemi: withAnimation(.spring(duration: 0.35, bounce: 0.2)) { mostraSistemi = true }
            case .impostazioni: mostraImpostazioni = true
            case .pulisci: svuotaChat()
            case .musica: scheda = .musica
            }
            // 4 nov (il signore, strada B): era dietro: prima torna davanti (la salita), poi fa la richiesta, come nel mockup
            if sulPosto {
                try? await Task.sleep(for: .milliseconds(380))
                richiestaSulPosto(r, guida: guida, salva: salva)
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
        case .interprete(let codice):
            // 4 nov · MARK XI: come da JARVIS, l'Interprete sale e la sezione davanti va dietro da sola, viva (prima si chiudeva:
            // il Wiretap perdeva il testo senza verbale)
            jarvis.apriInterprete(codice)
        default:
            break                                   // gli altri li gestisce il reparto stesso
        }
    }

    /// 9 nov notte: l'icona (o «Jarvis, apri l'interprete»). Se l'Interprete è già aperto, anche dietro, torna con la sua lingua e
    /// la sua conversazione; se no sale senza lingua e la si sceglie lì dentro (una sola apertura, come il mockup).
    private func apriInterprete() {
        if let l = pila.voce(.interprete)?.lingua ?? jarvis.interprete { jarvis.interprete = l } else { scegliLingua = true }
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
                voceSistemi(logo: nil, simbolo: "edith", nome: "EDITH", stato: "porte · fughe · link · domini") { scheda = .edith }
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
                    } else if simbolo == "edith" {
                        Image(systemName: "eyeglasses").resizable().scaledToFit()       // gli occhiali di EDITH
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

    /// Le righe di stato del menu: chiamate leggere al cervello, tutte insieme.
    private func caricaStatoSistemi() async {
        // le quattro voci partono insieme e ognuna si scrive appena arriva (Archivio e Costi non aspettano Supabase).
        // Solo letture riuscite: se una fallisce resta la riga buona di prima, e riprova una volta.
        async let a: Void = leggiSistema("archivio")
        async let s: Void = leggiSistema("supabase")
        async let g: Void = leggiSistema("github")
        async let k: Void = leggiSistema("costi")
        _ = await (a, s, g, k)
    }

    private func leggiSistema(_ voce: String) async {
        let corpo: [String: Any]
        switch voce {
        case "supabase": corpo = ["supabase": true, "ore": 24]
        case "costi": corpo = ["consumi": true]
        default: corpo = [voce: true]
        }
        for tentativo in 0..<2 {
            if tentativo > 0 { try? await Task.sleep(for: .seconds(2)) }
            if Task.isCancelled { return }                      // menu chiuso: niente da segnare
            if let r = await VistaVitals.chiama(corpo, attesa: 30), let riga = Self.rigaSistema(voce, r) {
                statoSistemi[voce] = riga
                MemoriaSistemi.salva(statoSistemi)              // la prossima volta il menu la mostra subito
                return
            }
        }
    }

    /// La riga di stato di una voce, solo se la lettura è riuscita (nil = fallita: resta quella di prima).
    private static func rigaSistema(_ voce: String, _ r: [String: Any]) -> String? {
        if let e = r["errore"] as? String { return e.contains("manca") ? "non collegato" : nil }
        switch voce {
        case "archivio":
            let file = r["file"] as? [[String: Any]] ?? [], cartelle = r["cartelle"] as? [[String: Any]] ?? []
            return "\(file.count) file · \(cartelle.count) cartelle"
        case "supabase":
            let log = r["log"] as? [String: Any]
            let errori = ((log?["richieste"] as? [[String: Any]])?.count ?? 0) + ((log?["console"] as? [[String: Any]])?.count ?? 0)
            let mb = (r["database_mb"] as? NSNumber)?.doubleValue ?? 0
            return "\(errori == 0 ? "nessun errore" : "\(errori) errori") · \(Int(mb)) MB"
        case "github":
            let repo = r["repository"] as? [[String: Any]] ?? []
            let issue = repo.reduce(0) { $0 + (($1["issue_aperte"] as? NSNumber)?.intValue ?? 0) }
            return "\(repo.count) repository · \(issue) issue aperte"
        case "costi":
            let oggi = (r["dollari_oggi"] as? NSNumber)?.doubleValue ?? 0, mese = (r["dollari_mese"] as? NSNumber)?.doubleValue ?? 0
            return String(format: "oggi %.2f · mese %.2f $", oggi, mese).replacingOccurrences(of: ".", with: ",")
        default: return nil
        }
    }

    private var registro: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(jarvis.messaggi) { m in
                        RigaAnimata { q in RigaMessaggio(m: m, rimescola: q) }.id(m.id)
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
            // si apre la tastiera e la chat si accorcia: l'ultimo messaggio resta in vista
            .onChange(of: tastiera) { _, aperta in
                guard aperta, telefono, let ultimo = jarvis.messaggi.last else { return }
                withAnimation(ContentView.curvaTastiera) { proxy.scrollTo(ultimo.id, anchor: .bottom) }
            }
            // il reattore grande rientra e la chat si accorcia: l'ultimo messaggio resta in vista
            .onChange(of: reattoreGrande) { _, grande in
                guard grande, let ultimo = jarvis.messaggi.last else { return }
                withAnimation(.timingCurve(0.38, 0.7, 0.125, 1, duration: durataRientro)) { proxy.scrollTo(ultimo.id, anchor: .bottom) }   // insieme al reattore
            }
        }
        .coordinateSpace(.named("chat"))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { regiaChat.altezza = $0 }
        .environment(\.regiaChat, regiaChat)
        .modifier(EffettiChat(regia: regiaChat))
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
                .onChange(of: tastiera) { _, _ in scrive = false }                        // tastiera su o giù: in attesa, non sta ancora scrivendo
                .onChange(of: testo) { _, nuovo in
                    guard tastiera, !nuovo.isEmpty else { return }
                    scrive = true                                                        // preme i tasti: microfono zitto
                    giroTasti += 1
                    let mio = giroTasti
                    Task {
                        try? await Task.sleep(for: .milliseconds(1200))
                        if mio == giroTasti { scrive = false }                           // smesso di scrivere: di nuovo in attesa
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(red: 0.04, green: 0.12, blue: 0.15).opacity(0.8))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.11, green: 0.21, blue: 0.25)))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Button {
                let t = testo
                testo = ""
                scrive = false                      // la tastiera resta aperta: di nuovo in attesa, risponde e si può interrompere
                if telefono { Task { await jarvis.inviaScritto(t) } } else { Task { await jarvis.invia(t) } }   // iPhone: scritto mentre risponde vale come interromperlo a voce
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.fondo)
                    .frame(width: 44, height: 44)
                    .background(Color.ciano2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled((testo.trimmingCharacters(in: .whitespaces).isEmpty && jarvis.foto == nil) || (!telefono && jarvis.fase == .elaboro))   // iPhone: anche mentre pensa (vale come interromperlo); iPad e Mac come prima
            .accessibilityLabel("Invia")
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }
}

/// Le fasce attorno al reattore (dal 7 nov la GHIERA): più veloci quando JARVIS ascolta e pensa, arancioni quando lavora e parla.
/// Puro contorno: il reattore resta il cuore.
struct AnelliHUD: View {
    let fase: Fase
    @Environment(\.jarvisCoperto) private var coperto    // 26 ott sera: sotto Studio o Social si ferma sull'ultimo fotogramma
    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: coperto)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let caldo = fase == .elaboro || fase == .parlo
            let fretta: Double = fase == .elaboro ? 2.2 : (fase == .ascolto ? 1.4 : 1)
            Canvas { gc, size in
                // 7 nov sera (il signore: «la mia scelta per il reattore è Ghiera»): la GHIERA, come il mockup v274 (prova GHIERA
                // di «Fasce reattore»). Una ghiera tecnica alla Stark: 120 tacche graduate (ogni 10 lunga), il controanello
                // tratteggiato che gira al contrario, il binario con tre archi e i fermi alle estremità, il raggio di scansione che
                // passa piano, l'anello interno. Le coordinate 000 · 090 · 180 · 270 le disegna EtichetteGhiera, sopra il cuore.
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = Double(min(size.width, size.height)) / 2
                let base = caldo ? Color.orange : Color.ciano
                func punto(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
                func cerchio(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
                // il bordo e le 120 tacche che scorrono piano
                gc.stroke(cerchio(R * 0.99), with: .color(base.opacity(0.32)), lineWidth: 0.8)
                var lunghe = Path(), medie = Path(), corte = Path()
                for k in 0..<120 {
                    let a = Double(k) / 120 * 2 * .pi + t * 0.03 * fretta
                    if k % 10 == 0 { lunghe.move(to: punto(R * 0.985, a)); lunghe.addLine(to: punto(R * 0.925, a)) }
                    else if k % 5 == 0 { medie.move(to: punto(R * 0.985, a)); medie.addLine(to: punto(R * 0.945, a)) }
                    else { corte.move(to: punto(R * 0.985, a)); corte.addLine(to: punto(R * 0.962, a)) }
                }
                gc.stroke(lunghe, with: .color(base.opacity(0.75)), lineWidth: 1.4)
                gc.stroke(medie, with: .color(base.opacity(0.42)), lineWidth: 0.8)
                gc.stroke(corte, with: .color(base.opacity(0.2)), lineWidth: 0.8)
                // il controanello tratteggiato, che gira al contrario (la fase del tratteggio lo fa girare)
                gc.stroke(cerchio(R * 0.9), with: .color(base.opacity(0.45)),
                          style: StrokeStyle(lineWidth: 1, dash: [1.6, 4.2], dashPhase: t * 0.12 * fretta * R * 0.9))
                // il binario e i tre archi coi fermi
                gc.stroke(cerchio(R * 0.855), with: .color(base.opacity(0.1)), lineWidth: 3.2)
                var archi = Path(), fermi = Path()
                for q in 0..<3 {
                    let a = t * 0.32 * fretta + Double(q) * 2 * .pi / 3
                    let l = 0.5 + (caldo ? 0.12 * sin(t * 3 + Double(q)) : 0)
                    archi.move(to: punto(R * 0.855, a))
                    archi.addArc(center: c, radius: R * 0.855, startAngle: .radians(a), endAngle: .radians(a + l), clockwise: false)
                    for e in [a, a + l] { fermi.move(to: punto(R * 0.825, e)); fermi.addLine(to: punto(R * 0.885, e)) }
                }
                gc.stroke(archi, with: .color(base.opacity(0.85)), lineWidth: 2.4)
                gc.stroke(fermi, with: .color(base.opacity(0.85)), lineWidth: 1.2)
                // il raggio di scansione: una scia che sfuma dietro
                let sa = t * 0.7 * fretta
                for i in 0..<18 {
                    let a0 = sa - Double(i) * 0.035
                    var p = Path(); p.addArc(center: c, radius: R * 0.9, startAngle: .radians(a0 - 0.035), endAngle: .radians(a0), clockwise: false)
                    gc.stroke(p, with: .color(base.opacity(0.16 * (1 - Double(i) / 18))), lineWidth: R * 0.17)
                }
                // l'anello interno, sottile
                gc.stroke(cerchio(R * 0.78), with: .color(base.opacity(0.3)), lineWidth: 0.8)
            }
            .animation(.easeInOut(duration: 0.8), value: caldo)
        }
        .allowsHitTesting(false)
    }
}

/// 7 nov sera (il signore: «nessuna sovrapposizione su numeri o scritte»): le coordinate della GHIERA, fisse e sempre dritte, sopra
/// il cuore del reattore. Ognuna nel suo riquadro scuro, così sopra i numeri non passa niente (mockup v274, ghieraEtichette).
struct EtichetteGhiera: View {
    let fase: Fase
    var body: some View {
        let base = fase == .elaboro || fase == .parlo ? Color.orange : Color.ciano
        GeometryReader { g in
            let R = Double(min(g.size.width, g.size.height)) / 2
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ForEach(0..<4, id: \.self) { n in
                let a = Double(n) * .pi / 2 - .pi / 2
                Text(["000", "090", "180", "270"][n])
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundStyle(base.opacity(0.95))
                    .frame(width: 26, height: 12)
                    .background(Color(red: 0.02, green: 0.03, blue: 0.035).opacity(0.82))
                    .overlay(Rectangle().stroke(base.opacity(0.6), lineWidth: 0.8))
                    .position(x: c.x + R * 0.9 * cos(a), y: c.y + R * 0.9 * sin(a))
            }
        }
        .animation(.easeInOut(duration: 0.8), value: fase == .elaboro || fase == .parlo)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                        "MEMORIA SINCRONIZZATA", "T \(ora)", "\(ContentView.marca) · BUILD \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")"]
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
            TimelineView(.animation(minimumInterval: nil)) { ctx in
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
    var rimescola: Double = 0          // 0 = testo vero, 1 = caratteri da computer (chat che carica o si svuota)
    var body: some View {
        let jarvis = m.ruolo == "assistant"
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(jarvis ? Color.ciano : Color(red: 0.11, green: 0.21, blue: 0.25))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(Glifi.rimescola("\(jarvis ? "JARVIS" : "SIGNORE") · \(m.data.formatted(date: .omitted, time: .shortened))", rimescola))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(jarvis ? Color.ciano : Color.tenue)
                Text(Glifi.rimescola(m.testo.isEmpty ? "…" : (m.conFoto ? "📷 " + m.testo : m.testo), rimescola))
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
    @Environment(\.chiudiOVia) private var chiudi
    @AppStorage("indirizzo") private var indirizzo = Impostazioni.indirizzoPredefinito
    @AppStorage("voce") private var voce = ""
    @AppStorage("muto") private var muto = false
    @AppStorage("ascoltaApertura") private var ascoltaApertura = true
    @AppStorage("voceCloud") private var voceCloud = true
    @AppStorage("idVoceCloud") private var idVoceCloud = ""
    @AppStorage("interruzioneVocale") private var interruzioneVocale = true
    @AppStorage("richiamo") private var richiamo = true
    @AppStorage("ascoltoSempre") private var ascoltoSempre = true   // difetto 7 (25 ott): acceso anche sul Mac, come si comportava già
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
                // 7 nov (il signore: «falle tutte uguali»): le righe come i pannelli delle altre sezioni (velo ciano), non il grigio di iOS
                Group {
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
                        Task { await jarvis.parla("Buonasera, Sir. Sistemi in linea, e pronto a servirla.") }
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
                    Button("Nuova conversazione", role: .destructive) { jarvis.svuotaChiesto = true; chiudi() }   // si chiude e la chat si svuota con l'animazione del cestino
                } footer: {
                    Text("Cancella la cronologia sull'iPhone. Note e memoria di JARVIS restano nel cervello.")
                }
                }
                .listRowBackground(Color.ciano.opacity(0.06))
            }
            // 7 nov (il signore: «le pagine devono avere tutte lo stesso sfondo»): niente grigio di iOS dietro le righe; la testata
            // allo stesso posto delle altre sezioni (16 punti sotto «Fatto» e dal bordo)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            // 5 nov (il signore: «se scorro si vede quella barra grigia»): «Fatto» in una riga sua sopra la pagina, come «Chiudi»
            // 7 nov sera: la testata nella riga di «Fatto», come in tutte le sezioni
            .modifier(ConBarraChiudi(tinta: Color.ciano, testo: "Fatto",
                                     testata: DatiTestata(titolo: "Impostazioni", sottotitolo: "configurazione nucleo", icona: "gearshape")) {
                Portachiavi.salva(parola.trimmingCharacters(in: .whitespacesAndNewlines))
                chiudi()
            })
            .background(SfondoSezione())                     // dietro anche alla riga di «Fatto», come nelle altre sezioni
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { voci = Jarvis.vociItaliane() }
        }
        // 4 nov (il signore: «ciano come il resto, mai il blu di iOS»): interruttori, «Fatto», il ritorno da «La mia voce» e il
        // cursore in ciano, come nel mockup
        .tint(Color.ciano)
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
    @Environment(\.chiudiOVia) var chiudi

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

/// Build 23: i due posti del reattore, misurati nella schermata (grande al centro, piccolo nella barra in alto con la tastiera aperta).
nonisolated private struct PostiReattore: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// La riga di «MARK VIII»: le icone in alto a destra si allineano al centro di quella scritta.
extension VerticalAlignment {
    nonisolated private enum RigaMark: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    nonisolated static let rigaMark = VerticalAlignment(RigaMark.self)
}


// MARK: - MARK X · arrivo delle icone in alto
private struct ArrivoTesta: ViewModifier {
    let posto: Int, arrivate: Int
    func body(content: Content) -> some View {
        let dentro = posto < arrivate
        content
            .opacity(dentro ? 1 : 0)
            .offset(x: dentro || UIAccessibility.isReduceMotionEnabled ? 0 : 28)   // da destra; con «Riduci movimento» solo dissolvenza
            .allowsHitTesting(dentro)
    }
}
extension View {
    /// L'icona in alto arriva da destra quando tocca a lei (vedi `accendi()`).
    func arrivoTesta(_ posto: Int, arrivate: Int) -> some View { modifier(ArrivoTesta(posto: posto, arrivate: arrivate)) }
}
