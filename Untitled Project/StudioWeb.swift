#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import Combine
import AVFoundation
import UniformTypeIdentifiers
import SafariServices
import PhotosUI             // 3 nov · RITRATTO: la galleria con i byte originali delle foto (la profondità dentro l'HEIC)
import QuickLook            // 3 nov · AR: AR Quick Look
import ARKit                // ARQuickLookPreviewItem
import AuthenticationServices // 8 nov · RIVALI: il login di Facebook (ASWebAuthenticationSession)

// MARK: - STUDIO e SOCIAL (MARK X): il banco olografico per modellare in 3D e stampare, e Instagram, IDENTICI al mockup approvato.
// La pagina è il mockup stesso («Studio3D/markx.html», generata da tools/studio_app.py) con three.js 0.160 nel pacchetto
// (schema jarvis3d://, niente rete per il 3D), come il LiDAR della build 26. L'app le dà quello che il mockup simulava:
//  · la voce di JARVIS (ogni frase del banco la dice lui), il microfono vero (dettatura) per i comandi a voce dello Studio;
//  · FOTO con la fotocamera vera dell'iPhone; CREA libero col cervello (funzione «studio-inventa»);
//  · STAMPA/CONDIVIDI: il file STL o 3MF va al foglio di condivisione (File, AirDrop, l'app della stampante);
//  · l'ARCHIVIO dei progetti salvato sull'iPhone (Application Support/studio-archivio.json), non nel browser;
//  · SOCIAL: i dati veri di @kingrusto dal cervello (funzione «social»), la galleria e la fotocamera vere, la pubblicazione.

struct VistaStudio: View {
    var apertura = AperturaPagina(sezione: "Studio")
    let parla: (String) -> Void
    /// «Chiudi» (della pagina), e prima degli Occhi o del LiDAR: lo strato scende sopra JARVIS e poi sparisce (StratoPagina).
    let chiudi: () -> Void
    /// 26 ott sera (il signore: «si devono aprire come le altre app»): l'apertura di tutte le schede di JARVIS (il caricamento
    /// con anelli e mirino, i suoni di apertura e di pronta), poi la pagina già disegnata. Prima si vedeva la pagina mentre si
    /// caricava (un lampo bianco, poi nero). Il caricamento resta almeno quanto nelle altre schede e finché la pagina non è pronta.
    @State private var coperto = true
    @State private var apertaDa = Date()
    /// 26 ott sera (il signore: «si devono chiudere come le altre»): si chiude trascinando giù come Meteo o Posta, tranne quando
    /// il dito sta lavorando dentro la pagina (banco 3D, schizzo, cursori, PIANO) o la pagina è scorsa giù: lì il trascinamento
    /// è della pagina. Lo dice la pagina al tocco (messaggio «presa»).
    @State private var presa = false
    /// Nelle pagine olografiche: quanto è olografica la pagina e se si sta materializzando (il velo ciano dentro la pagina, OloWeb).
    @Environment(\.tintaOlo) private var tintaOlo
    @Environment(\.materiaOlo) private var materiaOlo
    /// 8 nov (video del signore 09:00 e 09:02: «la parte alta va a salti, si stacca e carica dopo», «uguali alle altre sezioni»):
    /// la riga in alto è quella dell'app (BarraSezione), come in tutte le sezioni, ferma dal primo istante. Prima c'era quella del
    /// caricamento e poi quella della pagina web, diversa (icona, «Chiudi», spaziature): nel cambio si vedevano doppie e saltavano;
    /// in Studio sparivano per 0,2 s. La pagina dice quale sezione mostra e il suo sottotitolo; «Chiudi» e ARCHIVIO comandano la pagina.
    @State private var sezioneMostrata: String?
    @State private var sottotitolo: String?
    @State private var telecomando = TelecomandoStudio()
    private var nome: String { sezioneMostrata ?? apertura.sezione }

    /// 8 nov (il signore: «Studio, Social e Musica si devono aprire come tutte le altre, fluidità, precisione, continuità grafica,
    /// nessun nero»): l'apertura di CorniceScheda, pezzo per pezzo. Lo sfondo è quello di tutte le sezioni (SfondoSezione: la pagina
    /// web è trasparente sopra), la riga in alto è BarraSezione ferma dal primo istante, il caricamento è lo stesso (al centro, 120
    /// punti sotto); quando la pagina è sullo schermo il caricamento sparisce e il contenuto si «stampa» dall'alto con la riga di luce
    /// (0,32 s), come in ogni sezione.
    @State private var stampa: CGFloat = 0
    @State private var stampata = false

    var body: some View {
        // la riga in alto è alta 44 sotto il margine dell'ora: lì comincia il contenuto, e lì comincia la stampa
        let daQui = (FasciaAlta.finestra?.safeAreaInsets.top ?? 59) + 44
        ZStack {
            SfondoSezione()
            // 8 nov mattina (video del signore 06:34): la pagina web va a tutto schermo da sé (sotto l'ora e fino in fondo); la
            // sezione resta nel margine sicuro come tutte le altre (prima ignorava i margini e a fine salita saltava di 59 punti)
            PaginaStudio(apertura: apertura, parla: parla, chiudi: chiudi, pronta: { scopri() }, presa: { presa = $0 },
                         testata: { s, t in
                             if !s.isEmpty { sezioneMostrata = s }
                             sottotitolo = t.isEmpty ? nil : t
                         },
                         passaggio: { riapri() },
                         telecomando: telecomando, olo: tintaOlo, materia: materiaOlo)
                .ignoresSafeArea()
            StampaSezione(da: daQui, stampa: stampa, riga: !coperto && !stampata)
                .opacity(stampata ? 0 : 1)
                .allowsHitTesting(false)
            if coperto {
                // lo stesso caricamento di tutte le sezioni (7 nov sera: «o le fai tutte uguali»); la riga in alto è quella sotto
                SchermoCaricamento(titolo: nome, icona: nome == "Social" ? "social" : "studio", conTestata: false)
            }
            VStack(spacing: 0) {
                BarraSezione(testata: DatiTestata(titolo: nome, sottotitolo: coperto ? TestiCaricamento.di(nome) : (sottotitolo ?? TestiCaricamento.di(nome)),
                                                  icona: nome == "Social" ? "social" : "studio", tinta: .ciano),
                             tinta: .ciano, chiudi: { telecomando.chiudi() }) {
                    if nome == "Studio" {
                        TastoArchivioStudio { telecomando.archivio() }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .statusBarHidden(false)
        .interactiveDismissDisabled(presa)
        .onAppear {
            BattitoMani.paginaAperta(true)                   // 26 ott: i tick della pagina (Web Audio) non sono battiti di mani
            apertaDa = Date()
            Suoni.schedaApre()
        }
        .task {                                              // per sicurezza: se la pagina non dice mai «pronta» (bloccata), dopo 10 s si scopre lo stesso
            // 8 nov: prima 4 s, e una pagina lenta finiva scoperta nel nero; ora il caricamento resta fermo al 92 % come in tutte
            // le sezioni che aspettano i dati, finché la pagina non è sullo schermo
            try? await Task.sleep(for: .seconds(10))
            scopri()
        }
        .onDisappear { BattitoMani.paginaAperta(false) }
    }

    /// La pagina è sullo schermo: dopo il caricamento minimo di tutte le sezioni, il suono di «pronta», il caricamento sparisce
    /// e il contenuto si stampa dall'alto (come CorniceScheda: `mostrato`, poi `stampa` 0 → 1 in Apertura.stampa).
    private func scopri() {
        guard coperto else { return }
        Task { @MainActor in
            let resta = Apertura.caricamento - Date().timeIntervalSince(apertaDa)
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            guard coperto else { return }
            Suoni.schedaPronta()
            coperto = false
            withAnimation(.easeOut(duration: Apertura.stampa)) { stampa = 1 } completion: { stampata = true }
        }
    }

    /// 8 nov: dentro la pagina si passa da una sezione all'altra (Studio → Social, LiDAR → Studio): si riapre come un'apertura,
    /// col caricamento e poi la stampa, come quando si apre una sezione.
    private func riapri() {
        guard !coperto else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            coperto = true
            stampa = 0
            stampata = false
        }
        apertaDa = Date()
        Suoni.schedaApre()
    }
}

/// 8 nov: la «stampa» del contenuto come in tutte le sezioni (CorniceScheda): sopra la pagina lo sfondo della sezione, che dall'alto
/// in giù lascia il posto alla pagina; sul bordo la riga di luce (2 punti, ciano, bagliore 6, larga quanto il contenuto).
private struct StampaSezione: View {
    let da: CGFloat
    let stampa: CGFloat
    let riga: Bool

    var body: some View {
        GeometryReader { g in
            let y = da + max(0, g.size.height - da) * stampa
            ZStack(alignment: .top) {
                SfondoSezione()
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: y)
                            Color.black
                        }
                    }
                Rectangle().fill(Color.ciano).frame(height: 2)
                    .shadow(color: .ciano, radius: 6)
                    .padding(.horizontal, 16)
                    .offset(y: y)
                    .opacity(riga ? 1 : 0)
            }
        }
        .ignoresSafeArea()
    }
}

/// 8 nov: i tasti della riga in alto dell'app (BarraSezione) che comandano la pagina di Studio e Social: «Chiudi» e ARCHIVIO.
final class TelecomandoStudio {
    var chiudi: () -> Void = {}
    var archivio: () -> Void = {}
}

/// 8 nov: ARCHIVIO di Studio nella riga in alto, uguale a quello della pagina (.sd-arch: alto 28, 8 punti, icona 12, bordo 0,4).
/// Il suono lo fa la pagina, come prima.
private struct TastoArchivioStudio: View {
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            HStack(spacing: 4) {
                IconaArchivioStudio()
                    .stroke(Color.ciano, style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 12, height: 12)
                Text("ARCHIVIO").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
            }
            .foregroundStyle(Color.ciano)
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(Color(red: 2 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
        .accessibilityLabel("Archivio")
    }
}

/// L'icona dell'archivio della pagina (SD_ICO.archivio): la cartella con la nuvola, nel quadrato 24 × 24.
private struct IconaArchivioStudio: Shape {
    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 24
        let p0 = CGPoint(x: r.minX, y: r.minY)
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: p0.x + x * k, y: p0.y + y * k) }
        var p = Path()
        p.move(to: q(3, 6)); p.addLine(to: q(9, 6)); p.addLine(to: q(11, 8)); p.addLine(to: q(21, 8))
        p.addLine(to: q(21, 19)); p.addLine(to: q(3, 19)); p.closeSubpath()
        // la nuvola: tre archi (raggi 2,5 · 3,5 · 2) come nel disegno della pagina
        func arco(_ cx: CGFloat, _ cy: CGFloat, _ raggio: CGFloat, _ da: Double, _ a: Double) {
            for i in 0...14 {
                let t = (da + (a - da) * Double(i) / 14) * .pi / 180
                p.addLine(to: q(cx + raggio * CGFloat(cos(t)), cy + raggio * CGFloat(sin(t))))
            }
        }
        p.move(to: q(9, 15.5))
        arco(9.25, 13.05, 2.5, 95.8, 275.8)
        arco(12.8, 11.76, 3.5, 199.4, 357.4)
        arco(16.15, 13.55, 2, 274.4, 454.4)
        p.closeSubpath()
        return p
    }
}

private struct PaginaStudio: UIViewRepresentable {
    let apertura: AperturaPagina
    let parla: (String) -> Void
    let chiudi: () -> Void
    let pronta: () -> Void
    let presa: (Bool) -> Void
    let testata: (_ sezione: String, _ sottotitolo: String) -> Void
    let passaggio: () -> Void
    let telecomando: TelecomandoStudio
    let olo: Double
    let materia: Bool
    func makeCoordinator() -> RegiaStudio {
        RegiaStudio(apertura: apertura, parla: parla, chiudi: chiudi, pronta: pronta, presa: presa, testata: testata, passaggio: passaggio,
                    telecomando: telecomando)
    }
    func makeUIView(context: Context) -> WKWebView { context.coordinator.costruisci() }
    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.olo(forza: olo, materia: materia) }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: RegiaStudio) { coordinator.smonta() }
}

final class RegiaStudio: NSObject, WKURLSchemeHandler, WKScriptMessageHandler, WKNavigationDelegate,
                         UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static let schema = "jarvis3d"
    private let parla: (String) -> Void
    private let chiudi: () -> Void
    private let pronta: () -> Void
    private let presa: (Bool) -> Void
    private let testata: (_ sezione: String, _ sottotitolo: String) -> Void
    private let passaggio: () -> Void
    private var paginaAperta = false                 // 8 nov: la pagina ha aperto la sezione (ha detto «pronta»)
    private weak var web: WKWebView?
    private var archivio: [String: String] = RegiaStudio.leggiArchivio()
    private var salvataggio: Task<Void, Never>?
    private let dettatura = Wiretap()
    private var chiuso = false
    private let apertura: AperturaPagina
    private var perChi = "studio"                    // a chi va la foto scelta: "studio", "galleria" o "occhi" (Social)
    private var videoScelto: URL?                    // Social: il video scelto dalla galleria (lo carica l'app, non la pagina)
    private var sceltaRitratto: SceltaRitratto?      // 3 nov · RITRATTO: il delegato della galleria (il picker lo tiene debole)
    private var fonteAR: FonteAR?                    // 3 nov · AR: la fonte di AR Quick Look (anche lei tenuta debole)
    private let velo = VeloWeb()                     // 5 nov: il velo olografico dentro la pagina (pagine olografiche)
    private var loginFacebook: ASWebAuthenticationSession?   // 8 nov · RIVALI: il login in corso (va tenuto vivo finché finisce)
    private let ancoraLogin = AncoraLogin()

    init(apertura: AperturaPagina, parla: @escaping (String) -> Void, chiudi: @escaping () -> Void, pronta: @escaping () -> Void = {},
         presa: @escaping (Bool) -> Void = { _ in }, testata: @escaping (_ sezione: String, _ sottotitolo: String) -> Void = { _, _ in },
         passaggio: @escaping () -> Void = {}, telecomando: TelecomandoStudio? = nil) {
        self.apertura = apertura
        self.parla = parla
        self.chiudi = chiudi
        self.pronta = pronta
        self.presa = presa
        self.testata = testata
        self.passaggio = passaggio
        self.videoScelto = apertura.video                // 26 ott sera: il video degli Occhi (lo carica l'app, alla pagina va la copertina)
        super.init()
        // 8 nov: «Chiudi» e ARCHIVIO della riga in alto (dell'app) premono quelli della pagina, che resta padrona della chiusura
        // (Studio: «Salvare in archivio?»). Prima che la pagina sia aperta «Chiudi» chiude e basta.
        telecomando?.chiudi = { [weak self] in self?.premiChiudi() }
        telecomando?.archivio = { [weak self] in self?.web?.evaluateJavaScript("window.__jarvisArchivio && window.__jarvisArchivio()", completionHandler: nil) }
    }

    private func premiChiudi() {
        guard paginaAperta, let web else { salvaOra(); chiudi(); return }
        web.evaluateJavaScript("window.__jarvisChiudi ? window.__jarvisChiudi() : window.webkit.messageHandlers.jarvis.postMessage({ tipo: 'chiudi' })",
                               completionHandler: nil)
    }

    func costruisci() -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.setURLSchemeHandler(self, forURLScheme: Self.schema)
        conf.websiteDataStore = .nonPersistent()             // l'archivio lo tiene l'app, non il browser
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []    // i suoni del banco partono subito, come nel mockup
        let ponte = WKUserContentController()
        ponte.add(PonteDebole(self), name: "jarvis")
        conf.userContentController = ponte
        let w = WKWebView(frame: .zero, configuration: conf)
        w.isOpaque = false
        // 8 nov: trasparente: lo sfondo è SfondoSezione, lo stesso di tutte le sezioni (la pagina disegna solo il contenuto)
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.scrollView.isScrollEnabled = false
        w.scrollView.bounces = false
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.navigationDelegate = self
        w.isInspectable = true
        web = w
        // 26 ott sera (il signore: «Social e Studio non sono fluide»): preparare la pagina (l'archivio, la foto in JPEG) e caricarla
        // occupava il telefono proprio mentre la scheda saliva, e la salita scattava. Ora la scheda sale libera (sopra c'è il
        // caricamento, come in tutte le altre) e la pagina si prepara e si carica appena la salita è finita (0,45 s).
        Task { @MainActor [weak self, weak w] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, let w else { return }
            ponte.addUserScript(WKUserScript(source: RegiaStudio.copioneInizio(self.archivio), injectionTime: .atDocumentStart, forMainFrameOnly: true))
            ponte.addUserScript(WKUserScript(source: RegiaStudio.copioneFine(self.apertura), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            if let u = URL(string: "\(Self.schema)://app/markx.html") { w.load(URLRequest(url: u)) }
        }
        return w
    }

    /// Nelle pagine olografiche: il velo ciano dentro la pagina (solo quando cambia).
    func olo(forza: Double, materia: Bool) {
        guard let web else { return }
        velo.metti(forza: forza, materia: materia, a: web)
    }

    /// La pagina è stata caricata (anche di nuovo) mentre era olografica: il velo torna.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        velo.rimetti(a: webView)
    }

    func smonta() {
        chiuso = true
        dettatura.ferma()
        salvaOra()
        if let v = videoScelto { try? FileManager.default.removeItem(at: v) }
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "jarvis")
    }

    // MARK: i file della pagina (dal pacchetto dell'app)

    func webView(_ webView: WKWebView, start t: any WKURLSchemeTask) {
        guard let url = t.request.url else { return }
        let nome = url.lastPathComponent
        let base = (nome as NSString).deletingPathExtension, est = (nome as NSString).pathExtension
        // 3 nov · CAD: il motore OpenCascade (replicad_single.js + .wasm, LGPL: licenza in Licenze/) si carica solo quando si entra in CAD
        guard ["markx.html", "three.module.min.js", "replicad_single.js", "replicad_single.wasm"].contains(nome),
              let file = Bundle.main.url(forResource: base, withExtension: est) ?? Bundle.main.url(forResource: base, withExtension: est, subdirectory: "Studio3D"),
              let d = try? Data(contentsOf: file) else {
            t.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = est == "js" ? "text/javascript" : est == "wasm" ? "application/wasm" : "text/html"
        let tipo = est == "wasm" ? mime : "\(mime); charset=utf-8"
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": tipo, "Content-Length": "\(d.count)", "Access-Control-Allow-Origin": "*"])
            ?? URLResponse(url: url, mimeType: mime, expectedContentLength: d.count, textEncodingName: "utf-8")
        t.didReceive(r); t.didReceive(d); t.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: i messaggi della pagina

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let o = m.body as? [String: Any], let tipo = o["tipo"] as? String else { return }
        let id = (o["id"] as? NSNumber)?.intValue ?? 0
        switch tipo {
        case "parla":
            if let t = o["testo"] as? String, !t.isEmpty { parla(t) }
        case "chiudi":
            salvaOra(); chiudi()
        case "pronta":                                                   // la sezione è aperta: via il caricamento, ma solo a pagina sullo schermo
            // 8 nov (il signore: «non voglio problemi di nero»): «pronta» della pagina vuol dire che la pagina ha finito il suo lavoro,
            // non che l'immagine sia già sullo schermo (nel simulatore arrivava secondi dopo: nero). L'istantanea di iOS «dopo
            // l'aggiornamento dello schermo» torna solo quando la pagina è davvero presentata: allora sfuma il caricamento.
            paginaAperta = true
            guard let web else { pronta(); return }
            let c = WKSnapshotConfiguration()
            c.rect = CGRect(x: 0, y: 0, width: 4, height: 4)
            c.snapshotWidth = 4
            c.afterScreenUpdates = true
            Task { [weak self, weak web] in
                _ = try? await web?.takeSnapshot(configuration: c)
                self?.pronta()
            }
        case "testata":                                                  // 8 nov: la sezione che la pagina mostra e il suo sottotitolo
            testata(o["sezione"] as? String ?? "", o["sotto"] as? String ?? "")
        case "passaggio":                                                // 8 nov: la pagina passa a un'altra sezione: si ricopre col caricamento
            passaggio()
        case "presa":                                                    // il dito lavora nella pagina: niente chiusura trascinando
            presa(o["on"] as? Bool ?? false)
        case "ls":                                                       // l'archivio dei progetti (localStorage del mockup)
            guard let k = o["k"] as? String else { return }
            if let v = o["v"] as? String { archivio[k] = v } else { archivio[k] = nil }
            salvaPresto()
        case "cervello":                                                 // CREA libero: la ricetta dei pezzi
            let prompt = o["prompt"] as? String ?? ""
            Task { let r = await RegiaStudio.chiediCervello(prompt); self.rispondi(id, r) }
        case "salvaFile":                                                // STAMPA / CONDIVIDI
            guard let nome = o["nome"] as? String, let b64 = o["b64"] as? String, let d = Data(base64Encoded: b64) else { rispondi(id, (nil, "file non valido")); return }
            condividi(d, nome: nome) { [weak self] ok in self?.rispondi(id, ok ? ("ok", nil) : (nil, "declined")) }
        case "foto":
            scatta()
        case "video360":                                                 // CONDIVIDI › VIDEO 360°: l'MP4 vero del giro del banco
            let nome = (o["nome"] as? String ?? "Studio") + ".mp4"
            let fotogrammi = (o["fotogrammi"] as? [String] ?? []).compactMap { Data(base64Encoded: $0) }
            Task {
                guard fotogrammi.count >= 2, let u = try? await Video360.crea(fotogrammi), let d = try? Data(contentsOf: u) else {
                    self.rispondi(id, (nil, "errore")); return
                }
                try? FileManager.default.removeItem(at: u)
                self.condividi(d, nome: nome) { ok in self.rispondi(id, ok ? ("ok", nil) : (nil, "declined")) }
            }
        case "modelloAR":                                                // CONDIVIDI › MODELLO AR: l'USDZ vero del pezzo, misura vera
            let nome = (o["nome"] as? String ?? "Studio") + ".usdz"
            let stl = o["stl"] as? String ?? ""
            Task {
                guard let u = await ModelloAR.crea(stl), let d = try? Data(contentsOf: u) else { self.rispondi(id, (nil, "errore")); return }
                try? FileManager.default.removeItem(at: u)
                self.condividi(d, nome: nome) { ok in self.rispondi(id, ok ? ("ok", nil) : (nil, "declined")) }
            }
        case "apriURL":                                                  // SERVICE: la pagina di stampa 3D di Vectorealism, dentro l'app
            guard let t = o["url"] as? String, let u = URL(string: t), u.scheme == "https", u.host?.hasSuffix("vectorealism.com") == true,
                  let sopra = RegiaStudio.inCima(web) else { return }
            let pagina = SFSafariViewController(url: u)
            pagina.preferredControlTintColor = UIColor(Color.ciano)     // 4 nov: tasti in ciano come il resto, mai il blu di iOS
            sopra.present(pagina, animated: true)
        case "copia":                                                    // CONDIVIDI › Copia: l'immagine del banco negli appunti
            if let b64 = o["b64"] as? String, let d = Data(base64Encoded: b64), let img = UIImage(data: d) { UIPasteboard.general.image = img }
        case "vaiA":                                                     // LIDAR e OCCHI dello Studio: quelli veri dell'iPhone
            let lidar = o["dove"] as? String == "lidar"
            if !lidar { OcchiAperti.studioAcceso = true }            // 26 ott: negli Occhi STUDIO è già acceso, basta lo scatto
            parla(lidar ? "Apro il LiDAR su Oggetto, Sir: finita la scansione, tocchi STUDIO." : "Apro gli Occhi, Sir: inquadri il pezzo e scatti.")
            salvaOra()
            scendiPoi { NotificationCenter.default.post(name: .jarvisVaiA, object: nil, userInfo: ["dove": lidar ? "lidar" : "occhi"]) }
        case "plastico":                                                 // «fai il plastico della stanza» dentro lo Studio: la sala vera
            let p = PaginaMarkX.plasticoDaArchivio(o["k"] as? String ?? "stanza")
            parla(p.frase)
            if let json = p.json { esegui("window.__lidarVero && window.__lidarVero(\(json))") }
        // SOCIAL: i dati veri, le risposte, la pubblicazione, il calendario, l'automazione (funzione «social» del cervello)
        case "socialStato":
            // 26 ott (video del signore: ~9 s di «KR · CARICO…»): subito gli ultimi dati salvati sull'iPhone, poi quelli nuovi del
            // cervello appena arrivano. Il riassunto a voce («com'è andata la settimana?») aspetta i dati nuovi, mai quelli vecchi.
            if let vecchio = RegiaStudio.socialSalvato() {
                esegui("(function(){var v=window.__socRiassunto;window.__socRiassunto=false;window.__socStato&&window.__socStato(\(vecchio));window.__socRiassunto=v;})()")
            }
            Task {
                let r = await RegiaStudio.social(["azione": "stato"])
                RegiaStudio.salvaSocial(r)
                self.esegui("window.__socStato && window.__socStato(\(r))")
            }
        case "socialRispondi":
            let corpo: [String: Any] = ["azione": "rispondi", "tipo": o["tipoMsg"] as? String ?? "", "id": o["idMsg"] as? String ?? "",
                                        "a": o["a"] as? String ?? "", "testo": o["testo"] as? String ?? ""]
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialAnnulla":
            let corpo: [String: Any] = ["azione": "annulla", "id": o["idCoda"] ?? 0]
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialModifica":                                           // PIANO: didascalia e ora di un programmato
            var corpo: [String: Any] = ["azione": "modifica", "id": o["idCoda"] ?? 0]
            if let d = o["didascalia"] as? String { corpo["didascalia"] = d }
            if let q = o["quando"] as? String { corpo["quando"] = q }
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialScambia":                                            // PIANO: due programmati si scambiano l'ora
            let corpo: [String: Any] = ["azione": "scambia", "a": o["a"] ?? 0, "b": o["b"] ?? 0]
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialCommenti":                                           // GRIGLIA: commenti sì/no su un post pubblicato
            let corpo: [String: Any] = ["azione": "commenti", "id": o["idMedia"] as? String ?? "", "on": o["on"] as? Bool ?? true]
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialRivali":                                             // 8 nov · RIVALI: gli account seguiti coi numeri, AGGIUNGI e TOGLI
            var corpo: [String: Any] = ["azione": "rivali"]
            if let op = o["op"] as? String { corpo["op"] = op }
            if let u = o["username"] as? String { corpo["username"] = u }
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialFacebook":                                           // 8 nov · RIVALI › COLLEGA: il login di Facebook, una volta sola
            Task { await self.collegaFacebook() }
        case "apriInstagram":                                            // GRIGLIA › MODIFICA: il post nell'app di Instagram
            guard let t = o["url"] as? String, let u = URL(string: t), u.scheme == "https",
                  u.host == "www.instagram.com" || u.host == "instagram.com" else { return }
            UIApplication.shared.open(u)
        case "socialAuto":
            let corpo: [String: Any] = ["azione": "auto", "on": o["on"] as? Bool ?? false, "parola": o["parola"] as? String ?? "", "testo": o["testo"] as? String ?? ""]
            Task { _ = await RegiaStudio.social(corpo) }
        case "socialPubblica":
            let formato = o["formato"] as? String ?? "POST", quando = o["quando"] as? String ?? "ORA"
            let didascalia = o["didascalia"] as? String ?? "", b64 = o["media"] as? String ?? "", mime = o["mime"] as? String ?? "image/jpeg"
            Task { let r = await self.pubblica(formato: formato, quando: quando, didascalia: didascalia, b64: b64, mime: mime); self.rispondi(id, (r, nil)) }
        case "socialFoto":
            if o["da"] as? String == "occhi" {                           // 26 ott sera: OCCHI apre gli Occhi di JARVIS, lo scatto torna qui
                OcchiAperti.socialAcceso = true
                OcchiAperti.socialDida = o["dida"] as? String          // la didascalia già scritta torna con lo scatto
                salvaOra()
                scendiPoi { NotificationCenter.default.post(name: .jarvisVaiA, object: nil, userInfo: ["dove": "occhi"]) }
            } else {
                scegli(per: "galleria")
            }
        case "vediAR":                                                   // 3 nov · AR: il pezzo nella stanza, a grandezza vera
            let stl = o["stl"] as? String ?? ""
            Task {
                guard let u = await ModelloAR.crea(stl) else { self.parla("Il modello per l'AR non è venuto, Sir."); return }
                self.mostraAR(u)
            }
        case "ritratto":                                                 // 3 nov · RILIEVO › RITRATTO: una foto Ritratto, con la profondità vera
            scegliRitratto()
        case "ascolta":
            Task { await self.dettatura.avvia() }
        case "ferma":
            dettatura.ferma()
            let t = dettatura.testo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { esegui("window.STUDIO_ATTIVO && window.STUDIO_ATTIVO.voce(\(RegiaStudio.js(t)))") }
        default: break
        }
    }

    /// 26 ott sera: per gli Occhi e il LiDAR la scheda prima scende da sola (niente nero), poi si aprono loro.
    private func scendiPoi(_ dopo: @escaping () -> Void) {
        chiudi()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            dopo()
        }
    }

    private func rispondi(_ id: Int, _ esito: (String?, String?)) {
        let ok = esito.0 != nil
        esegui("window.__jarvisRisposta(\(id), \(ok), \(RegiaStudio.js(esito.0 ?? esito.1 ?? "errore")))")
    }

    private func esegui(_ codice: String) {
        guard !chiuso else { return }
        web?.evaluateJavaScript(codice, completionHandler: nil)
    }

    // MARK: CREA libero (cervello)

    static func chiediCervello(_ prompt: String) async -> (String?, String?) {
        let base = Impostazioni.indirizzo.replacingOccurrences(of: "/functions/v1/jarvis", with: "/functions/v1/studio-inventa")
        guard let url = URL(string: base) else { return (nil, "indirizzo non valido") }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": prompt])
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return (nil, "il cervello non risponde") }
        if let t = o["testo"] as? String, !t.isEmpty { return (t, nil) }
        return (nil, o["errore"] as? String ?? "risposta vuota")
    }

    // MARK: SOCIAL › RIVALI: COLLEGA (8 nov)
    /// Il cervello prepara l'indirizzo del login (configurazione «JARVIS Rivali», codice monouso di 10 minuti); il login si apre nel
    /// foglio sicuro di iOS (con l'accesso a Facebook di Safari, se c'è); Facebook torna al cervello, che si tiene la chiave e rimanda
    /// a jarvis://rivali?ok=1 (o ?errore=…). La pagina riceve l'esito in window.__socFb e rilegge i rivali.
    private func collegaFacebook() async {
        guard loginFacebook == nil else { return }
        let r = await RegiaStudio.social(["azione": "fbLink"], attesa: 20)
        let o = r.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let t = o?["url"] as? String, let u = URL(string: t), u.scheme == "https" else {
            finitoFacebook(["errore": o?["errore"] as? String ?? "il cervello non risponde"])
            return
        }
        let s = ASWebAuthenticationSession(url: u, callback: .customScheme("jarvis")) { @Sendable url, errore in
            var esito: [String: String] = [:]
            if let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                for q in c.queryItems ?? [] { esito[q.name] = q.value ?? "" }
            } else if let e = errore as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                esito["errore"] = "annullato"
            } else {
                esito["errore"] = "il login non è riuscito"
            }
            let fatto = esito
            Task { @MainActor in self.finitoFacebook(fatto) }
        }
        s.presentationContextProvider = ancoraLogin
        s.prefersEphemeralWebBrowserSession = false
        loginFacebook = s
        if !s.start() { finitoFacebook(["errore": "il login non parte"]) }
    }

    private func finitoFacebook(_ esito: [String: String]) {
        loginFacebook = nil
        var o: [String: Any] = ["ok": esito["ok"] == "1"]
        if let e = esito["errore"] { o["errore"] = e }
        if let p = esito["pagina"] { o["pagina"] = p }
        let json = (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        esegui("window.__socFb && window.__socFb(\(json))")
    }

    // MARK: SOCIAL (Instagram dal cervello)

    /// Una chiamata alla funzione «social»: torna sempre un JSON valido (in caso di guasto, {"errore": …}) che la pagina legge.
    /// SOCIAL: l'ultimo stato buono (senza errore), salvato sull'iPhone per mostrarlo subito alla prossima apertura.
    private static var fileSocial: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("social-stato.json")
    }
    static func socialSalvato() -> String? {
        guard let u = fileSocial, let d = try? Data(contentsOf: u), (try? JSONSerialization.jsonObject(with: d)) is [String: Any] else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func salvaSocial(_ json: String) {
        guard let u = fileSocial, let d = json.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], o["errore"] == nil else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: u, options: .atomic)
    }

    static func social(_ corpo: [String: Any], attesa: TimeInterval = 60) async -> String {
        func errore(_ t: String) -> String { (try? JSONSerialization.data(withJSONObject: ["errore": t])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
        let base = Impostazioni.indirizzo.replacingOccurrences(of: "/functions/v1/jarvis", with: "/functions/v1/social")
        guard let url = URL(string: base) else { return errore("indirizzo del cervello non valido") }
        var req = URLRequest(url: url, timeoutInterval: attesa)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return errore("Instagram non risponde: controlli la connessione") }
        guard (try? JSONSerialization.jsonObject(with: d)) is [String: Any], let s = String(data: d, encoding: .utf8) else {
            return errore("il cervello ha risposto male (codice \((r as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        return s
    }

    /// PUBBLICA: la foto preparata dalla pagina (già nel formato giusto), oppure il video scelto dalla galleria.
    /// Un REEL da una foto diventa un video vero di 6 secondi (ReelDaFoto), perché Instagram vuole un video per i Reel.
    private func pubblica(formato: String, quando: String, didascalia: String, b64: String, mime: String) async -> String {
        func errore(_ t: String) -> String { (try? JSONSerialization.data(withJSONObject: ["errore": t])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
        var dati: Data?, tipo = mime
        if b64.isEmpty, let v = videoScelto {
            dati = try? Data(contentsOf: v)
            tipo = v.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"
        } else if formato == "REEL", let jpg = Data(base64Encoded: b64) {
            do {
                let u = try await ReelDaFoto.crea(jpg)
                dati = try Data(contentsOf: u); tipo = "video/mp4"
                try? FileManager.default.removeItem(at: u)
            } catch { return errore("non riesco a montare il video del Reel") }
        } else {
            dati = Data(base64Encoded: b64)
        }
        guard let dati, !dati.isEmpty else { return errore("manca il contenuto") }
        guard dati.count < 30_000_000 else { return errore("il video è troppo pesante: ne scelga uno più corto") }
        return await RegiaStudio.social(["azione": "pubblica", "formato": formato, "quando": quando, "didascalia": didascalia,
                                         "media": dati.base64EncodedString(), "mime": tipo], attesa: 240)
    }

    // MARK: condividi (STL, 3MF, immagini)

    private func condividi(_ d: Data, nome: String, fatto: @escaping (Bool) -> Void) {
        let pulito = nome.replacingOccurrences(of: "/", with: "-")
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(pulito)
        do { try d.write(to: u, options: .atomic) } catch { fatto(false); return }
        let foglio = UIActivityViewController(activityItems: [u], applicationActivities: nil)
        foglio.completionWithItemsHandler = { _, completato, _, _ in fatto(completato) }
        guard let sopra = RegiaStudio.inCima(web) else { fatto(false); return }
        foglio.popoverPresentationController?.sourceView = sopra.view
        foglio.popoverPresentationController?.sourceRect = CGRect(x: sopra.view.bounds.midX, y: sopra.view.bounds.maxY - 80, width: 1, height: 1)
        sopra.present(foglio, animated: true)
    }

    // MARK: AR (AR Quick Look a grandezza vera) e RITRATTO (la foto con la profondità per il RILIEVO)

    private func mostraAR(_ u: URL) {
        guard let sopra = RegiaStudio.inCima(web) else { return }
        let modello = ARQuickLookPreviewItem(fileAt: u)
        modello.allowsContentScaling = false                 // niente ingrandimento con le dita: la misura resta quella vera
        let fonte = FonteAR(modello)
        fonteAR = fonte
        let anteprima = QLPreviewController()
        anteprima.dataSource = fonte
        sopra.present(anteprima, animated: true)
    }

    private func scegliRitratto() {
        var c = PHPickerConfiguration()
        c.filter = .images
        c.selectionLimit = 1
        c.preferredAssetRepresentationMode = .current         // l'HEIC originale: con la profondità e il ritaglio della persona
        let galleria = PHPickerViewController(configuration: c)
        let scelta = SceltaRitratto { [weak self] dati in self?.ritrattoScelto(dati) }
        sceltaRitratto = scelta
        galleria.delegate = scelta
        RegiaStudio.inCima(web)?.present(galleria, animated: true)
    }

    private func ritrattoScelto(_ dati: Data?) {
        sceltaRitratto = nil
        guard let dati else { return }
        Task {
            guard let r = await ProfonditaRitratto.leggi(dati) else { self.parla("Questa foto non si apre, Sir."); return }
            var prof = "null"
            if let z = r.profondita {
                let m = r.ritaglio.map { "'\($0.base64EncodedString())'" } ?? "null"
                prof = "{w:\(r.larghezza),h:\(r.altezza),z:'\(z.base64EncodedString())',m:\(m)}"
            }
            self.esegui("(function(){var im=new Image();im.onload=function(){window.__studioRitratto&&window.__studioRitratto(im,\(prof));};im.src='data:image/jpeg;base64,\(r.jpg.base64EncodedString())';})()")
        }
    }

    // MARK: FOTO (fotocamera vera; se manca, la galleria)

    private func scatta() { scegli(per: "studio") }

    /// La fotocamera (Studio, Occhi di Social) o la galleria con foto e video (Social).
    private func scegli(per: String) {
        perChi = per
        let p = UIImagePickerController()
        let camera = UIImagePickerController.isSourceTypeAvailable(.camera)
        p.sourceType = per != "galleria" && camera ? .camera : .photoLibrary
        if per == "galleria" {
            p.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
            p.videoExportPreset = AVAssetExportPreset1280x720             // pesa meno da caricare, Instagram lo accetta
        }
        p.delegate = self
        RegiaStudio.inCima(web)?.present(p, animated: true)
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if perChi == "galleria", let u = info[.mediaURL] as? URL { prendiVideo(u); return }
        guard let img = info[.originalImage] as? UIImage else { return }
        let lato: CGFloat = perChi == "studio" ? 1400 : 2000, k = min(1, lato / max(img.size.width, img.size.height))
        let piccola = UIGraphicsImageRenderer(size: CGSize(width: img.size.width * k, height: img.size.height * k)).image { _ in
            img.draw(in: CGRect(x: 0, y: 0, width: img.size.width * k, height: img.size.height * k))
        }
        guard let jpg = piccola.jpegData(compressionQuality: perChi == "studio" ? 0.82 : 0.9) else { return }
        if perChi == "studio" {
            esegui("(function(){var im=new Image();im.onload=function(){window.STUDIO_ATTIVO&&window.STUDIO_ATTIVO.foto(im,'foto');};im.src='data:image/jpeg;base64,\(jpg.base64EncodedString())';})()")
        } else {
            videoScelto = nil
            mandaASocial(jpg, da: perChi, video: false)
        }
    }

    /// Social: un video dalla galleria. Resta all'app (troppo pesante per la pagina): alla pagina va la copertina.
    private func prendiVideo(_ sorgente: URL) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("social-video.\(sorgente.pathExtension.isEmpty ? "mov" : sorgente.pathExtension)")
        try? FileManager.default.removeItem(at: dest)
        guard (try? FileManager.default.copyItem(at: sorgente, to: dest)) != nil else { return }
        Task {
            let asset = AVURLAsset(url: dest)
            let durata = (try? await asset.load(.duration).seconds) ?? 0
            let peso = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if durata < 3 { parla("Il video è troppo corto, Sir: Instagram ne vuole almeno tre secondi."); return }
            if peso > 30_000_000 { parla("Il video è troppo pesante, Sir: ne scelga uno più corto, al massimo un minuto circa."); return }
            let g = AVAssetImageGenerator(asset: asset)
            g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 1600, height: 1600)
            guard let cg = try? await g.image(at: .zero).image, let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { return }
            videoScelto = dest
            mandaASocial(jpg, da: "galleria", video: true)
        }
    }

    private func mandaASocial(_ jpg: Data, da: String, video: Bool) {
        esegui("(function(){var im=new Image();im.onload=function(){window.__socFonte&&window.__socFonte(im,\(RegiaStudio.js(da)),\(video));};im.src='data:image/jpeg;base64,\(jpg.base64EncodedString())';})()")
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }

    // MARK: l'archivio sull'iPhone

    private static var fileArchivio: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("studio-archivio.json")
    }
    static func leggiArchivio() -> [String: String] {
        guard let u = fileArchivio, let d = try? Data(contentsOf: u) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: d)) ?? [:]
    }
    private func salvaPresto() {
        salvataggio?.cancel()
        salvataggio = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.salvaOra()
        }
    }
    private func salvaOra() {
        guard let u = RegiaStudio.fileArchivio, let d = try? JSONEncoder().encode(archivio) else { return }
        try? d.write(to: u, options: .atomic)
    }

    // MARK: aiuti

    static func js(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s]), let t = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(t.dropFirst().dropLast())                         // una stringa JavaScript sicura (virgolette, a capo)
    }
    static func inCima(_ v: UIView?) -> UIViewController? {
        var c = v?.window?.rootViewController
        while let p = c?.presentedViewController { c = p }
        return c
    }

    /// Prima degli script del mockup: modo app, l'archivio salvato, le «capability» che il mockup chiede a claude.ai.
    static func copioneInizio(_ archivio: [String: String]) -> String {
        let iniziale = (try? JSONSerialization.data(withJSONObject: archivio)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        (function(){
          window.JARVIS_APP = true;
          // 26 ott: la pagina (4 MB) si disegnava a pezzi mentre si caricava: per un attimo la casa del mockup su fondo bianco
          // (menu delle build, link). Resta nascosta, sul nero, finché non è aperta la sezione (la mostra copioneFine).
          document.documentElement.style.visibility = 'hidden';
          // 8 nov: la pagina è trasparente: sotto c'è lo sfondo di tutte le sezioni, quello dell'app (SfondoSezione). Nelle pagine
          // olografiche (OloWeb) torna il suo fondo, come prima
          document.documentElement.style.background = 'transparent';
          document.documentElement.classList.add('jarvis-trasparente');
          // 26 ott: i suoni del banco (tag <audio>) aprivano il lettore di iOS nella Dynamic Island. Si suonano con Web Audio,
          // che non passa da «In riproduzione»; i video (Reel, 360°) restano come sono.
          (function(){
            var C = window.AudioContext || window.webkitAudioContext; if (!C) return;
            var ctx = null, cache = new Map(), play = HTMLMediaElement.prototype.play, pausa = HTMLMediaElement.prototype.pause;
            HTMLMediaElement.prototype.play = function(){
              var el = this, src = el.currentSrc || el.src;
              if (!(el instanceof HTMLAudioElement) || !src) return play.apply(this, arguments);
              try { ctx = ctx || new C(); if (ctx.state === 'suspended') ctx.resume(); } catch (e) { return play.apply(this, arguments); }
              var p = cache.get(src);
              if (!p) { p = fetch(src).then(function(r){ return r.arrayBuffer(); }).then(function(b){ return new Promise(function(ok, no){ ctx.decodeAudioData(b, ok, no); }); }); cache.set(src, p); }
              var da = el.currentTime || 0, vol = el.muted ? 0 : el.volume, vel = el.playbackRate || 1;
              p.then(function(buf){
                if (el.__s) { try { el.__s.stop(); } catch (e) {} }
                var s = ctx.createBufferSource(), g = ctx.createGain();
                s.buffer = buf; s.playbackRate.value = vel; g.gain.value = vol; s.connect(g); g.connect(ctx.destination);
                s.start(0, Math.min(da, buf.duration)); el.__s = s;
              }).catch(function(){ cache.delete(src); });
              return Promise.resolve();
            };
            HTMLMediaElement.prototype.pause = function(){
              if (this.__s) { try { this.__s.stop(); } catch (e) {} this.__s = null; }
              return pausa.apply(this, arguments);
            };
          })();
          var post = function(o){ try { window.webkit.messageHandlers.jarvis.postMessage(o); } catch (e) {} };
          var m = new Map(Object.entries(\(iniziale)));
          var ls = { getItem: function(k){ return m.has(k) ? m.get(k) : null; },
                     setItem: function(k, v){ v = String(v); m.set(k, v); post({ tipo: 'ls', k: k, v: v }); },
                     removeItem: function(k){ m.delete(k); post({ tipo: 'ls', k: k, v: null }); },
                     clear: function(){ m.forEach(function(_, k){ post({ tipo: 'ls', k: k, v: null }); }); m.clear(); },
                     key: function(i){ return Array.from(m.keys())[i] || null; }, get length(){ return m.size; } };
          try { Object.defineProperty(window, 'localStorage', { value: ls, configurable: true }); } catch (e) {}
          var attese = new Map(), n = 0;
          window.__jarvisRisposta = function(id, ok, testo){ var a = attese.get(id); if (!a) return; attese.delete(id); ok ? a.res(testo) : a.rej({ code: testo, message: testo }); };
          var chiedi = function(tipo, dati){ return new Promise(function(res, rej){ var id = ++n; attese.set(id, { res: res, rej: rej }); dati.tipo = tipo; dati.id = id; post(dati); }); };
          var testo = function(x){ return typeof x === 'string' ? x : (Array.isArray(x) ? x.map(function(y){ return y.content; }).join('\\n') : String(x)); };
          var sample = function(input){ return chiedi('cervello', { prompt: testo(input) }).then(function(t){ return { text: t, truncated: false }; }); };
          sample.json = function(input){ return chiedi('cervello', { prompt: testo(input) + '\\nRispondi SOLO con il JSON, senza altro testo.' }).then(function(t){ var j = t.match(/\\{[\\s\\S]*\\}/); return JSON.parse(j ? j[0] : t); }); };
          var downloads = { save: function(o){ var b = o.data instanceof Blob ? o.data : new Blob([o.data]);
            return b.arrayBuffer().then(function(buf){ var u = new Uint8Array(buf), s = ''; for (var i = 0; i < u.length; i += 32768) s += String.fromCharCode.apply(null, u.subarray(i, i + 32768));
              return chiedi('salvaFile', { nome: o.filename, b64: btoa(s) }); }); } };
          window.claude = { use: function(nome){ return Promise.resolve(nome === 'sample' ? sample : nome === 'downloads' ? downloads : null); } };
          window.__jarvisChiedi = chiedi;
          // SOCIAL · la foto nel formato che Instagram accetta: POST tra 4:5 e 1,91:1, STORIA e REEL 9:16, 1080 di larghezza.
          // Il video scelto dalla galleria resta all'app (nativo); il REEL da una foto lo monta l'app (video vero).
          window.__socMedia = function(f, formato){
            if (f && f.video) return Promise.resolve({ formato: formato, b64: '', mime: 'video' });
            var im = f && f.img; if (!im) return Promise.reject(new Error('niente da pubblicare'));
            var W = im.naturalWidth || im.width, H = im.naturalHeight || im.height;
            var r = formato === 'POST' ? Math.min(1.91, Math.max(0.8, W / H)) : 9 / 16, ow = 1080, oh = Math.round(1080 / r);
            var c = document.createElement('canvas'); c.width = ow; c.height = oh; var x = c.getContext('2d'), k = Math.max(ow / W, oh / H);
            x.fillStyle = '#020a0e'; x.fillRect(0, 0, ow, oh); x.imageSmoothingQuality = 'high'; x.drawImage(im, (ow - W * k) / 2, (oh - H * k) / 2, W * k, H * k);
            return Promise.resolve({ formato: formato, b64: c.toDataURL('image/jpeg', 0.9).split(',')[1], mime: 'image/jpeg' });
          };
          var tAuto = null;
          window.__socAuto = function(){ clearTimeout(tAuto); tAuto = setTimeout(function(){ var a = window.SOC && window.SOC.auto; if (a) post({ tipo: 'socialAuto', on: !!a.on, parola: a.parola || '', testo: a.testo || '' }); }, 800); };
        })();
        """
    }

    /// Dopo gli script del mockup: a tutto schermo, la voce di JARVIS, la sezione aperta subito (con quello che porta); chiusa la sezione,
    /// si torna all'app. Studio → Social (e ritorno) dentro la pagina: la sezione si chiude e si riapre in 450 ms, non si esce.
    static func copioneFine(_ a: AperturaPagina) -> String {
        var arrivo = ""
        if a.sezione == "Studio", let v = a.voce { arrivo = "window.STUDIO_DA = { voce: \(js(v)) };" }
        if a.sezione == "Studio", let l = a.lidar { arrivo = "window.STUDIO_DA = { lidarVero: \(l) };" }   // JSON valido = JavaScript valido
        if a.sezione == "Social", let k = a.scheda { arrivo = k == "STUDIO" ? "window.SOCIAL_DA = { studio: true };" : "window.SOCIAL_DA = \(js(k));" }
        var foto = "''"
        if let f = a.foto {
            let k = min(1, 1600 / max(f.size.width, f.size.height))
            let p = UIGraphicsImageRenderer(size: CGSize(width: f.size.width * k, height: f.size.height * k)).image { _ in f.draw(in: CGRect(x: 0, y: 0, width: f.size.width * k, height: f.size.height * k)) }
            if let d = p.jpegData(compressionQuality: 0.88) { foto = "'data:image/jpeg;base64,\(d.base64EncodedString())'" }
        }
        let conFoto = a.sezione == "Social"
            ? "window.SOCIAL_DA = { foto: im, da: 'occhi', dida: \(js(a.didascalia ?? ""))\(a.video != nil ? ", video: \(max(1, a.secondiVideo))" : "") };" : "window.STUDIO_DA = { foto: im, nome: \(js(a.nomeFoto)) };"
        // 5 nov (foto e video del signore: in Studio e Social la testata finiva sotto l'ora e la Dynamic Island): nel contenitore
        // della MARK XI la pagina web non riceve più il margine dell'ora (env(safe-area-inset-top) vale 0). Il margine vero lo dà
        // l'app, dalla finestra: la testata scende sotto l'ora come prima, su ogni iPhone.
        let alto = Int((FasciaAlta.finestra?.safeAreaInsets.top ?? 59).rounded())
        return """
        (function(){
          var post = function(o){ try { window.webkit.messageHandlers.jarvis.postMessage(o); } catch (e) {} };
          var st = document.createElement('style');
          st.textContent = 'html,:root{padding:0!important}body{padding:0!important;margin:0!important;display:block!important;background:#020304!important;overflow:hidden!important}'
            + 'body>*:not(#cornice){display:none!important}#cornice,#cornice>.telefono{width:100vw!important;height:100vh!important;transform:none!important;margin:0!important;border:0!important;border-radius:0!important;box-shadow:none!important}'
            + '.isola{opacity:0!important}html .sd-su,html .sc-su{padding-top:\(alto + 2)px!important}'   // 8 nov: la riga della testata alla stessa altezza di quella del caricamento (e di tutte le sezioni: icona 2 punti sotto il margine dell'ora)
            + '.sd-banco{min-height:min(240px,26vh)!important}'
            + '#tendina{display:none!important}'
            + '.voce-mock{display:none!important}'
            // 8 nov (video del signore 09:00/09:02: «la parte alta va a salti»): la riga in alto è quella dell'app, come in tutte le
            // sezioni; della testata della pagina restano solo le righe di stato di Studio (.oc-info), al loro posto
            + '#sezione .sd-su>.anello,#sezione .sd-su>div>b,#sezione .sd-su>div>small,#sezione .sd-su>button,#sezione .sc-su>.anello,#sezione .sc-su>div>b,#sezione .sc-su>div>small,#sezione .sc-su>button{visibility:hidden!important}'
            // 8 nov: lo sfondo è quello dell'app (SfondoSezione, uguale in tutte le sezioni): la pagina disegna solo il contenuto
            + 'html.jarvis-trasparente,html.jarvis-trasparente body,html.jarvis-trasparente #cornice,html.jarvis-trasparente #cornice>.telefono,html.jarvis-trasparente #sezione,html.jarvis-trasparente .allen.sd,html.jarvis-trasparente .allen.sc{background:transparent!important}'
            + 'html.jarvis-trasparente #cornice>.telefono::before,html.jarvis-trasparente #sezione::before,html.jarvis-trasparente #sezione::after,html.jarvis-trasparente .allen.sd::before,html.jarvis-trasparente .allen.sd::after,html.jarvis-trasparente .allen.sc::before,html.jarvis-trasparente .allen.sc::after{display:none!important}'
            + 'html.jarvis-trasparente #cornice>.telefono>:not(#sezione):not(#notifica):not(#conferma){opacity:0!important;pointer-events:none!important}';   // 8 nov notte (foto del signore, Social): nell'app JARVIS parla davvero, la sua frase scritta non si vede mai   // 26 ott sera (foto del signore): la tendina PROTOCOLLI del mockup spuntava sopra l'ora   // iPhone piccoli (SE): il banco cede spazio, STAMPA e CONDIVIDI restano dentro
          document.head.appendChild(st);
          // 8 nov notte (il signore: «toglile, queste trascrizioni orribili delle parole di JARVIS»): nell'app la frase la dice la voce
          // vera; la scritta del mockup (che non parla) qui non si crea più
          if (typeof window.parlaMock === 'function') { window.parlaMock = function(t){ post({ tipo: 'parla', testo: String(t) }); }; }
          var sez = document.getElementById('sezione'), aperta = false, via = null, radice = document.documentElement;
          // 8 nov: all'app la sezione mostrata e il suo sottotitolo (per la riga in alto dell'app); «Chiudi» e ARCHIVIO dell'app
          // premono quelli della pagina (Studio: «Salvare in archivio?» come prima)
          var ultimaTestata = '';
          var testata = function(){ var su = sez && sez.querySelector('.sd-su, .sc-su'); if (!su) return;
            var n = su.classList.contains('sc-su') ? 'Social' : 'Studio', s = su.querySelector(':scope > div > small'), t = s ? s.textContent.trim() : '';
            if (n + '|' + t === ultimaTestata) return; ultimaTestata = n + '|' + t; post({ tipo: 'testata', sezione: n, sotto: t }); };
          if (sez) new MutationObserver(testata).observe(sez, { childList: true, subtree: true, characterData: true });
          window.__jarvisChiudi = function(){ var b = sez && sez.querySelector('.sd-su .sd-chiudi, .sc-su .sc-chiudi');
            if (aperta && b) { chiedeChiusura = performance.now(); b.click(); } else { aperta = false; post({ tipo: 'chiudi' }); } };
          window.__jarvisArchivio = function(){ var b = sez && sez.querySelector('.sd-su [data-sdarch]'); if (b) b.click(); };
          if (sez) new MutationObserver(function(){
            if (sez.classList.contains('su')) { var ripresa = !!via; aperta = true; clearTimeout(via); via = null; radice.style.visibility = '';
              // 8 nov: dopo un passaggio (Studio → Social…) la sezione nuova è aperta: di nuovo «pronta», come all'apertura
              if (ripresa) requestAnimationFrame(function(){ requestAnimationFrame(function(){ testata(); post({ tipo: 'pronta' }); }); }); }
            else if (aperta && !via) {
              post({ tipo: 'passaggio' });                             // 8 nov: l'app ricopre col caricamento, come un'apertura
              radice.style.visibility = 'hidden';                      // la casa del telefono del mockup non si vede mai
              via = setTimeout(function(){ via = null; if (sez.classList.contains('su')) { radice.style.visibility = ''; return; } aperta = false; post({ tipo: 'chiudi' }); }, 750);
            }
          }).observe(sez, { attributes: true, attributeFilter: ['class'] });
          // 26 ott (video del signore): «Chiudi» toccato da lui chiude subito la sezione dell'app, che scende come ogni scheda di JARVIS.
          // Prima la pagina si nascondeva e l'app aspettava 750 ms: un secondo di nero prima di JARVIS. L'attesa resta solo per i
          // passaggi dentro la pagina (Studio → Social), che premono «Chiudi» da programma e riaprono subito.
          // 26 ott sera (video del signore, 21:06): il tocco arrivava PRIMA al «Chiudi» della pagina (WebKit, sullo stesso tasto, chiama
          // gli ascoltatori nell'ordine in cui sono stati messi): la pagina si nascondeva (nero) e solo dopo la scheda scendeva, nera.
          // Ora il tocco si prende sulla finestra, in cattura: arriva qui prima di qualunque altro, la pagina resta com'è e scende intera.
          window.addEventListener('click', function(e){
            var t = e.target && e.target.closest ? e.target.closest('#chiudiSez') : null;
            if (!t || !e.isTrusted || !aperta) return;
            e.stopImmediatePropagation(); e.preventDefault();
            aperta = false; clearTimeout(via); via = null;
            post({ tipo: 'chiudi' });
          }, true);
          // 26 ott notte (video del signore 23:03, ancora nero alla chiusura): il «Chiudi» che lui tocca in Studio e in Social non è
          // #chiudiSez (a pagina piena è nascosto) ma quello della testata della sezione (.sd-chiudi, .sc-chiudi), che chiama
          // $("chiudiSez").click() da programma: il tocco qui sopra non lo vedeva, la pagina si chiudeva da sola, si nascondeva
          // (nero) e l'app chiudeva 750 ms dopo, nera. Ora: tocco su quel «Chiudi» (Studio anche dopo «Salvare in archivio?»,
          // non con ANNULLA) → quando la pagina preme #chiudiSez, lo strato di JARVIS scende subito con la pagina com'è.
          // I passaggi dentro la pagina (Studio → Social, LiDAR → Studio) restano come prima.
          var chiedeChiusura = 0;
          window.addEventListener('click', function(e){
            if (!e.isTrusted || !e.target || !e.target.closest) return;
            if (e.target.closest('.sd-su .sd-chiudi, .sc-su .sc-chiudi')) chiedeChiusura = performance.now();
            else if (e.target.closest('.sd-chiedi [data-esci="annulla"]')) chiedeChiusura = 0;
          }, true);
          var tastoChiudi = document.getElementById('chiudiSez');
          if (tastoChiudi) tastoChiudi.click = function(){
            if (aperta && chiedeChiusura && performance.now() - chiedeChiusura < 60000) {
              chiedeChiusura = 0; aperta = false; clearTimeout(via); via = null;
              post({ tipo: 'chiudi' });
              return;
            }
            return HTMLElement.prototype.click.call(tastoChiudi);
          };
          // 26 ott sera: si chiude trascinando giù come le altre schede, ma non se il dito lavora dentro la pagina (banco 3D, schizzo,
          // cursori, griglia del PIANO, campi di testo) o se tocca una parte già scorsa giù (lì trascinare giù vuol dire risalire)
          var presaOn = false;
          var dentro = function(t){
            if (!t || !t.closest) return false;
            if (t.closest('canvas, .sd-banco, .sd-schizzo, input, textarea, .sc-g, .sc-piano, [draggable="true"]')) return true;
            for (var e = t; e && e !== document.body; e = e.parentElement) { if (e.scrollTop > 0 && e.scrollHeight > e.clientHeight) return true; }
            return false;
          };
          var mettiPresa = function(v){ if (v === presaOn) return; presaOn = v; post({ tipo: 'presa', on: v }); };
          document.addEventListener('pointerdown', function(e){ mettiPresa(dentro(e.target)); }, true);
          document.addEventListener('pointerup', function(){ setTimeout(function(){ mettiPresa(false); }, 300); }, true);
          document.addEventListener('pointercancel', function(){ mettiPresa(false); }, true);
          // 26 ott sera: l'apertura la fa l'app (caricamento e suoni come le altre schede): i suoni d'apertura della pagina tacciono
          var zitto = performance.now() + 2500;
          if (typeof window.suona === 'function') { var s0 = window.suona; window.suona = function(id){ if ((id === 'aPronta' || id === 'aScheda') && performance.now() < zitto) return; return s0.apply(this, arguments); }; }
          // 8 nov mattina (video del signore 06:34): la sezione della pagina si apre già al suo posto. La salita la fa l'app (come
          // per tutte le sezioni); quella del mockup (.foglio, 0,35 s) partiva sotto il caricamento e si vedeva finire mentre il
          // caricamento sfumava: la testata entrava più in basso e saliva. La transizione torna dopo, per i passaggi dentro la pagina.
          var apri = function(){ if (sez) sez.style.transition = 'none';
            if (typeof window.apriSezione === 'function') window.apriSezione(\(js(a.sezione))); if (sez && sez.classList.contains('su')) { aperta = true; radice.style.visibility = ''; }
            testata();
            if (sez) void sez.offsetWidth;
            requestAnimationFrame(function(){ requestAnimationFrame(function(){ if (sez) sez.style.transition = ''; post({ tipo: 'pronta' }); }); }); };
          setTimeout(function(){ if (!via) radice.style.visibility = ''; }, 1500);   // per sicurezza: mai una pagina che resta nera
          \(arrivo)
          var foto = \(foto);
          if (foto) { var im = new Image(); im.onload = function(){ \(conFoto) apri(); }; im.onerror = apri; im.src = foto; } else apri();
        })();
        """
    }
}

/// Il gestore dei messaggi tiene la regia senza trattenerla (niente cicli che non si chiudono mai).
/// 8 nov · RIVALI: la finestra su cui iOS mostra il login di Facebook. iOS la chiede sul thread principale.
private final class AncoraLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { FasciaAlta.finestra ?? ASPresentationAnchor() }
    }
}

private final class PonteDebole: NSObject, WKScriptMessageHandler {
    weak var regia: RegiaStudio?
    init(_ r: RegiaStudio) { regia = r }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { regia?.userContentController(c, didReceive: m) }
}

// MARK: - 5 nov (il signore: «Studio e Social, la vista dei post in ologramma: falli come gli altri, più trasparenti, identici al mockup»)
// Nelle pagine olografiche le pagine di SwiftUI diventano luce ciano col velo di VeloOlo (il ciano #4fe3ff in «color»), ma quella
// fusione non arriva dentro una WKWebView (è una vista UIKit): Studio, Social e Browser restavano a colori pieni, coi post accesi.
// Qui il velo lo mette la pagina stessa, come .olo-tinta del mockup: due strati fissi sopra tutta la pagina, senza tocchi, con le
// fusioni di WebKit (che usa le stesse di Core Animation): il ciano in «color» (la pagina diventa ciano con le sue luci e le sue
// ombre) e il velo ciano al 7% in «screen». Bagliore, righe e bordo restano quelli di VeloOlo, disegnati sopra la pagina.

/// Il velo olografico dentro una pagina web.
enum OloWeb {
    /// `forza` 0…1 (a passi di un decimo: fra un passo e l'altro sfuma la pagina in 90 ms); `materia`: la pagina scelta si
    /// materializza, il velo si scioglie dall'alto con la riga di MaterializzaOlo (0,43 s, la stessa curva). A forza 0 il velo
    /// sfuma e si toglie dalla pagina.
    static func applica(forza: Double, materia: Bool, a web: WKWebView) {
        web.evaluateJavaScript("(\(funzione))(\(forza), \(materia));", in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// Nel mondo di JavaScript di JARVIS (.defaultClient): la pagina non vede le nostre variabili e non le tocca.
    private static let funzione = """
    function (f, m) {
      var D = document, R = D.documentElement;
      if (!R) { return 0; }
      var G = window.__jarvisOlo || (window.__jarvisOlo = { giro: 0, mat: false });
      var C = D.getElementById('jarvis-olo-c'), S = D.getElementById('jarvis-olo-s');
      var metti = function (e, p) { for (var k in p) { e.style.setProperty(k, p[k], 'important'); } };
      var via = function () { if (C) { C.remove(); } if (S) { S.remove(); } C = null; S = null; };
      var giro = ++G.giro;
      // 8 nov: la pagina è trasparente sopra lo sfondo dell'app; olografica torna col suo fondo (il ciano «color» vuole un fondo)
      if (f > 0 || m) { R.classList.remove('jarvis-trasparente'); }
      if (!m && f <= 0 && (!C || !S || G.mat)) { G.mat = false; via(); R.classList.add('jarvis-trasparente'); return 0; }
      if (!C || !S) {
        via();
        var crea = function (id, fondo, fusione) {
          var e = D.createElement('div');
          e.id = id;
          e.setAttribute('aria-hidden', 'true');
          metti(e, { position: 'fixed', top: '0', left: '0', right: '0', bottom: '0', margin: '0', padding: '0', border: '0',
            'pointer-events': 'none', 'z-index': '2147483647', background: fondo, 'mix-blend-mode': fusione, opacity: '0',
            transition: 'opacity 90ms linear', '-webkit-mask-repeat': 'no-repeat', 'mask-repeat': 'no-repeat',
            '-webkit-mask-size': '100% 200%', 'mask-size': '100% 200%' });
          R.appendChild(e);
          return e;
        };
        C = crea('jarvis-olo-c', '#4fe3ff', 'color');
        S = crea('jarvis-olo-s', 'rgba(79, 227, 255, 0.07)', 'screen');
        void C.offsetWidth;
      }
      if (m) {
        if (G.mat) { return 0; }
        G.mat = true;
        var maschera = 'linear-gradient(to bottom, transparent 47.5%, #000 50%)';
        [C, S].forEach(function (e) {
          metti(e, { transition: 'none', opacity: '1', '-webkit-mask-image': maschera, 'mask-image': maschera,
            '-webkit-mask-position': '0 103%', 'mask-position': '0 103%' });
        });
        void C.offsetWidth;
        var corsa = '430ms cubic-bezier(0.455, 0.03, 0.515, 0.955)';
        [C, S].forEach(function (e) {
          metti(e, { transition: '-webkit-mask-position ' + corsa + ', mask-position ' + corsa,
            '-webkit-mask-position': '0 -3%', 'mask-position': '0 -3%' });
        });
        return 0;
      }
      if (G.mat) {
        G.mat = false;
        [C, S].forEach(function (e) { metti(e, { transition: 'none', opacity: '0' }); });
        void C.offsetWidth;
      }
      var ora = parseFloat(C.style.getPropertyValue('opacity')) || 0, salto = Math.abs(f - ora);
      var tempo = salto > 0.15 ? Math.round(salto * 320) : 90;
      var curva = salto > 0.15 ? 'cubic-bezier(0.33, 1, 0.68, 1)' : 'linear';
      [C, S].forEach(function (e) {
        metti(e, { transition: 'opacity ' + tempo + 'ms ' + curva, '-webkit-mask-image': 'none', 'mask-image': 'none',
          opacity: String(f) });
      });
      if (f <= 0) { setTimeout(function () { if (G.giro === giro) { via(); R.classList.add('jarvis-trasparente'); } }, tempo + 50); }
      return 0;
    }
    """
}

/// L'ultimo velo messo in una pagina web: la pagina si chiama solo quando cambia.
final class VeloWeb {
    private var forza = 0.0
    private var materia = false

    func metti(forza f: Double, materia m: Bool, a web: WKWebView) {
        guard f != forza || m != materia else { return }
        forza = f
        materia = m
        OloWeb.applica(forza: f, materia: m, a: web)
    }

    /// Una pagina nuova (caricata mentre era olografica) non ha il velo: si rimette.
    func rimetti(a web: WKWebView) {
        guard forza > 0 || materia else { return }
        OloWeb.applica(forza: forza, materia: materia, a: web)
    }
}

/// L'icona STUDIO del mockup (il cubo a tasselli con i tre assi), disegnata uguale.
struct IconaStudio: View {
    /// 27 ott (il signore: «l'icona di Studio è troppo piccola rispetto alle altre 5»): in alto il disegno riempie il suo riquadro
    /// (il cubo con gli assi, non il quadrato da 24 con i margini), così pesa come le altre icone.
    var pieno = false
    private static func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
    private static let tasselli: [(Double, [[CGPoint]])] = [
        (0.68, [[P(12.19, 13.81), P(14.21, 12.64), P(14.21, 14.98), P(12.19, 16.15)], [P(12.19, 16.6), P(14.21, 15.43), P(14.21, 17.77), P(12.19, 18.94)], [P(12.19, 19.39), P(14.21, 18.22), P(14.21, 20.56), P(12.19, 21.73)], [P(14.6, 12.42), P(16.61, 11.25), P(16.61, 13.59), P(14.6, 14.76)], [P(14.6, 15.21), P(16.61, 14.03), P(16.61, 16.38), P(14.6, 17.55)], [P(14.6, 17.99), P(16.61, 16.82), P(16.61, 19.17), P(14.6, 20.34)], [P(17, 11.02), P(19.02, 9.85), P(19.02, 12.19), P(17, 13.37)], [P(17, 13.81), P(19.02, 12.64), P(19.02, 14.98), P(17, 16.15)], [P(17, 16.6), P(19.02, 15.43), P(19.02, 17.77), P(17, 18.94)]]),
        (0.85, [[P(4.98, 9.85), P(7, 11.02), P(7, 13.37), P(4.98, 12.19)], [P(4.98, 12.64), P(7, 13.81), P(7, 16.15), P(4.98, 14.98)], [P(4.98, 15.43), P(7, 16.6), P(7, 18.94), P(4.98, 17.77)], [P(7.39, 11.25), P(9.4, 12.42), P(9.4, 14.76), P(7.39, 13.59)], [P(7.39, 14.03), P(9.4, 15.21), P(9.4, 17.55), P(7.39, 16.38)], [P(7.39, 16.82), P(9.4, 17.99), P(9.4, 20.34), P(7.39, 19.17)], [P(9.79, 12.64), P(11.81, 13.81), P(11.81, 16.15), P(9.79, 14.98)], [P(9.79, 15.43), P(11.81, 16.6), P(11.81, 18.94), P(9.79, 17.77)], [P(9.79, 18.22), P(11.81, 19.39), P(11.81, 21.73), P(9.79, 20.56)]]),
        (1, [[P(5.18, 9.52), P(7.19, 8.35), P(9.21, 9.52), P(7.19, 10.69)], [P(7.58, 10.91), P(9.6, 9.74), P(11.62, 10.91), P(9.6, 12.08)], [P(9.98, 12.31), P(12, 11.13), P(14.02, 12.31), P(12, 13.48)], [P(7.58, 8.12), P(9.6, 6.95), P(11.62, 8.12), P(9.6, 9.29)], [P(9.98, 9.52), P(12, 8.35), P(14.02, 9.52), P(12, 10.69)], [P(12.38, 10.91), P(14.4, 9.74), P(16.42, 10.91), P(14.4, 12.08)], [P(9.98, 6.73), P(12, 5.56), P(14.02, 6.73), P(12, 7.9)], [P(12.38, 8.12), P(14.4, 6.95), P(16.42, 8.12), P(14.4, 9.29)], [P(14.79, 9.52), P(16.81, 8.35), P(18.82, 9.52), P(16.81, 10.69)]]),
    ]
    var body: some View {
        Canvas { c, size in
            let lato = min(size.width, size.height)
            // pieno (in alto): il cubo grande e le frecce corte, tutto dentro il riquadro (da 2,5 a 21,5 e da 3,1 a 22,3)
            let k = pieno ? lato / 19.2 : lato / 24
            let t = pieno ? CGAffineTransform(translationX: (size.width - 19 * k) / 2 - 2.5 * k, y: (size.height - 19.2 * k) / 2 - 3.1 * k).scaledBy(x: k, y: k)
                          : CGAffineTransform(scaleX: k, y: k)
            for (opacita, poligoni) in IconaStudio.tasselli {
                var p = Path()
                for poli in poligoni { p.addLines(poli); p.closeSubpath() }
                var g = c
                g.opacity = opacita
                g.fill(p.applying(t), with: .foreground)
            }
            if pieno {
                // 27 ott (il signore: «le frecce piccoline, non devono uscire dall'interlinea, equilibrio»): assi corti, punte piccole
                var corte = Path()
                for (a, b) in [(CGPoint(x: 12, y: 4.88), CGPoint(x: 12, y: 3.78)), (CGPoint(x: 4.39, y: 18.11), CGPoint(x: 3.13, y: 18.84)), (CGPoint(x: 19.61, y: 18.11), CGPoint(x: 20.87, y: 18.84))] {
                    corte.move(to: a); corte.addLine(to: b)
                }
                corte.addLines([CGPoint(x: 12.4, y: 4.28), CGPoint(x: 12, y: 3.78), CGPoint(x: 11.6, y: 4.28)])
                corte.addLines([CGPoint(x: 3.76, y: 18.94), CGPoint(x: 3.13, y: 18.84), CGPoint(x: 3.36, y: 18.24)])
                corte.addLines([CGPoint(x: 20.24, y: 18.94), CGPoint(x: 20.87, y: 18.84), CGPoint(x: 20.64, y: 18.24)])
                c.stroke(corte.applying(t), with: .foreground, style: StrokeStyle(lineWidth: 1.3 * k, lineCap: .round, lineJoin: .round))
                return
            }
            var assi = Path()
            for (a, b) in [(CGPoint(x: 12, y: 4.88), CGPoint(x: 12, y: 3.05)), (CGPoint(x: 4.39, y: 18.11), CGPoint(x: 2.29, y: 19.33)), (CGPoint(x: 19.61, y: 18.11), CGPoint(x: 21.71, y: 19.33))] {
                assi.move(to: a); assi.addLine(to: b)
            }
            assi.addLines([CGPoint(x: 12.76, y: 4.00), CGPoint(x: 12, y: 3.05), CGPoint(x: 11.24, y: 4.00)])
            assi.addLines([CGPoint(x: 2.73, y: 18.20), CGPoint(x: 2.29, y: 19.33), CGPoint(x: 3.49, y: 19.51)])
            assi.addLines([CGPoint(x: 20.51, y: 19.51), CGPoint(x: 21.71, y: 19.33), CGPoint(x: 21.27, y: 18.20)])
            c.stroke(assi.applying(t), with: .foreground, style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round))
        }
    }
}
#endif
