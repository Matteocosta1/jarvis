#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import Combine
import AVFoundation
import UniformTypeIdentifiers
import SafariServices

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
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        PaginaStudio(apertura: apertura, parla: parla, chiudi: { chiudi() })
            .background(Color.fondo)
            .ignoresSafeArea()
            .statusBarHidden(false)
    }
}

private struct PaginaStudio: UIViewRepresentable {
    let apertura: AperturaPagina
    let parla: (String) -> Void
    let chiudi: () -> Void
    func makeCoordinator() -> RegiaStudio { RegiaStudio(apertura: apertura, parla: parla, chiudi: chiudi) }
    func makeUIView(context: Context) -> WKWebView { context.coordinator.costruisci() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: RegiaStudio) { coordinator.smonta() }
}

final class RegiaStudio: NSObject, WKURLSchemeHandler, WKScriptMessageHandler, WKNavigationDelegate,
                         UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static let schema = "jarvis3d"
    private let parla: (String) -> Void
    private let chiudi: () -> Void
    private weak var web: WKWebView?
    private var archivio: [String: String] = RegiaStudio.leggiArchivio()
    private var salvataggio: Task<Void, Never>?
    private let dettatura = Wiretap()
    private var chiuso = false
    private let apertura: AperturaPagina
    private var perChi = "studio"                    // a chi va la foto scelta: "studio", "galleria" o "occhi" (Social)
    private var videoScelto: URL?                    // Social: il video scelto dalla galleria (lo carica l'app, non la pagina)

    init(apertura: AperturaPagina, parla: @escaping (String) -> Void, chiudi: @escaping () -> Void) {
        self.apertura = apertura
        self.parla = parla
        self.chiudi = chiudi
        super.init()
    }

    func costruisci() -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.setURLSchemeHandler(self, forURLScheme: Self.schema)
        conf.websiteDataStore = .nonPersistent()             // l'archivio lo tiene l'app, non il browser
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []    // i suoni del banco partono subito, come nel mockup
        let ponte = WKUserContentController()
        ponte.add(PonteDebole(self), name: "jarvis")
        ponte.addUserScript(WKUserScript(source: RegiaStudio.copioneInizio(archivio), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ponte.addUserScript(WKUserScript(source: RegiaStudio.copioneFine(apertura), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        conf.userContentController = ponte
        let w = WKWebView(frame: .zero, configuration: conf)
        w.isOpaque = false
        w.backgroundColor = UIColor(red: 0.008, green: 0.012, blue: 0.016, alpha: 1)
        w.scrollView.isScrollEnabled = false
        w.scrollView.bounces = false
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.navigationDelegate = self
        w.isInspectable = true
        web = w
        if let u = URL(string: "\(Self.schema)://app/markx.html") { w.load(URLRequest(url: u)) }
        return w
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
        guard ["markx.html", "three.module.min.js"].contains(nome),
              let file = Bundle.main.url(forResource: base, withExtension: est) ?? Bundle.main.url(forResource: base, withExtension: est, subdirectory: "Studio3D"),
              let d = try? Data(contentsOf: file) else {
            t.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime = est == "js" ? "text/javascript" : "text/html"
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "\(mime); charset=utf-8", "Content-Length": "\(d.count)", "Access-Control-Allow-Origin": "*"])
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
                self.condividi(d, nome: nome) { [weak self] ok in self?.rispondi(id, ok ? ("ok", nil) : (nil, "declined")) }
            }
        case "modelloAR":                                                // CONDIVIDI › MODELLO AR: l'USDZ vero del pezzo, misura vera
            let nome = (o["nome"] as? String ?? "Studio") + ".usdz"
            let stl = o["stl"] as? String ?? ""
            Task {
                guard let u = await ModelloAR.crea(stl), let d = try? Data(contentsOf: u) else { self.rispondi(id, (nil, "errore")); return }
                try? FileManager.default.removeItem(at: u)
                self.condividi(d, nome: nome) { [weak self] ok in self?.rispondi(id, ok ? ("ok", nil) : (nil, "declined")) }
            }
        case "apriURL":                                                  // SERVICE: la pagina di stampa 3D di Vectorealism, dentro l'app
            guard let t = o["url"] as? String, let u = URL(string: t), u.scheme == "https", u.host?.hasSuffix("vectorealism.com") == true,
                  let sopra = RegiaStudio.inCima(web) else { return }
            sopra.present(SFSafariViewController(url: u), animated: true)
        case "copia":                                                    // CONDIVIDI › Copia: l'immagine del banco negli appunti
            if let b64 = o["b64"] as? String, let d = Data(base64Encoded: b64), let img = UIImage(data: d) { UIPasteboard.general.image = img }
        case "vaiA":                                                     // LIDAR e OCCHI dello Studio: quelli veri dell'iPhone
            let lidar = o["dove"] as? String == "lidar"
            parla(lidar ? "Apro il LiDAR su Oggetto, Sir: finita la scansione, tocchi STUDIO." : "Apro gli Occhi, Sir: inquadri il pezzo e tocchi STUDIO.")
            salvaOra()
            NotificationCenter.default.post(name: .jarvisVaiA, object: nil, userInfo: ["dove": lidar ? "lidar" : "occhi"])
        case "plastico":                                                 // «fai il plastico della stanza» dentro lo Studio: la sala vera
            let p = PaginaMarkX.plasticoDaArchivio(o["k"] as? String ?? "stanza")
            parla(p.frase)
            if let json = p.json { esegui("window.__lidarVero && window.__lidarVero(\(json))") }
        // SOCIAL: i dati veri, le risposte, la pubblicazione, il calendario, l'automazione (funzione «social» del cervello)
        case "socialStato":
            Task { let r = await RegiaStudio.social(["azione": "stato"]); self.esegui("window.__socStato && window.__socStato(\(r))") }
        case "socialRispondi":
            let corpo: [String: Any] = ["azione": "rispondi", "tipo": o["tipoMsg"] as? String ?? "", "id": o["idMsg"] as? String ?? "",
                                        "a": o["a"] as? String ?? "", "testo": o["testo"] as? String ?? ""]
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialAnnulla":
            let corpo: [String: Any] = ["azione": "annulla", "id": o["idCoda"] ?? 0]
            Task { let r = await RegiaStudio.social(corpo); self.rispondi(id, (r, nil)) }
        case "socialAuto":
            let corpo: [String: Any] = ["azione": "auto", "on": o["on"] as? Bool ?? false, "parola": o["parola"] as? String ?? "", "testo": o["testo"] as? String ?? ""]
            Task { _ = await RegiaStudio.social(corpo) }
        case "socialPubblica":
            let formato = o["formato"] as? String ?? "POST", quando = o["quando"] as? String ?? "ORA"
            let didascalia = o["didascalia"] as? String ?? "", b64 = o["media"] as? String ?? "", mime = o["mime"] as? String ?? "image/jpeg"
            Task { let r = await self.pubblica(formato: formato, quando: quando, didascalia: didascalia, b64: b64, mime: mime); self.rispondi(id, (r, nil)) }
        case "socialFoto":
            scegli(per: o["da"] as? String == "occhi" ? "occhi" : "galleria")
        case "ascolta":
            Task { await self.dettatura.avvia() }
        case "ferma":
            dettatura.ferma()
            let t = dettatura.testo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { esegui("window.STUDIO_ATTIVO && window.STUDIO_ATTIVO.voce(\(RegiaStudio.js(t)))") }
        default: break
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

    // MARK: SOCIAL (Instagram dal cervello)

    /// Una chiamata alla funzione «social»: torna sempre un JSON valido (in caso di guasto, {"errore": …}) che la pagina legge.
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
        let conFoto = a.sezione == "Social" ? "window.SOCIAL_DA = { foto: im, da: 'occhi' };" : "window.STUDIO_DA = { foto: im, nome: \(js(a.nomeFoto)) };"
        return """
        (function(){
          var post = function(o){ try { window.webkit.messageHandlers.jarvis.postMessage(o); } catch (e) {} };
          var st = document.createElement('style');
          st.textContent = 'html,:root{padding:0!important}body{padding:0!important;margin:0!important;display:block!important;background:#020304!important;overflow:hidden!important}'
            + 'body>*:not(#cornice){display:none!important}#cornice,#cornice>.telefono{width:100vw!important;height:100vh!important;transform:none!important;margin:0!important;border:0!important;border-radius:0!important;box-shadow:none!important}'
            + '.isola{opacity:0!important}.sd-su,.sc-su{padding-top:calc(env(safe-area-inset-top,0px) + 6px)!important}'
            + '.sd-banco{min-height:min(240px,26vh)!important}';   // iPhone piccoli (SE): il banco cede spazio, STAMPA e CONDIVIDI restano dentro
          document.head.appendChild(st);
          if (typeof window.parlaMock === 'function') { var o = window.parlaMock; window.parlaMock = function(t){ post({ tipo: 'parla', testo: String(t) }); return o.apply(this, arguments); }; }
          var sez = document.getElementById('sezione'), aperta = false, via = null, radice = document.documentElement;
          if (sez) new MutationObserver(function(){
            if (sez.classList.contains('su')) { aperta = true; clearTimeout(via); via = null; radice.style.visibility = ''; }
            else if (aperta && !via) {
              radice.style.visibility = 'hidden';                      // la casa del telefono del mockup non si vede mai
              via = setTimeout(function(){ via = null; if (sez.classList.contains('su')) { radice.style.visibility = ''; return; } aperta = false; post({ tipo: 'chiudi' }); }, 750);
            }
          }).observe(sez, { attributes: true, attributeFilter: ['class'] });
          var apri = function(){ if (typeof window.apriSezione === 'function') window.apriSezione(\(js(a.sezione))); if (sez && sez.classList.contains('su')) aperta = true; };
          \(arrivo)
          var foto = \(foto);
          if (foto) { var im = new Image(); im.onload = function(){ \(conFoto) apri(); }; im.onerror = apri; im.src = foto; } else apri();
        })();
        """
    }
}

/// Il gestore dei messaggi tiene la regia senza trattenerla (niente cicli che non si chiudono mai).
private final class PonteDebole: NSObject, WKScriptMessageHandler {
    weak var regia: RegiaStudio?
    init(_ r: RegiaStudio) { regia = r }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { regia?.userContentController(c, didReceive: m) }
}

/// L'icona STUDIO del mockup (il cubo a tasselli con i tre assi), disegnata uguale.
struct IconaStudio: View {
    private static func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
    private static let tasselli: [(Double, [[CGPoint]])] = [
        (0.68, [[P(12.19, 13.81), P(14.21, 12.64), P(14.21, 14.98), P(12.19, 16.15)], [P(12.19, 16.6), P(14.21, 15.43), P(14.21, 17.77), P(12.19, 18.94)], [P(12.19, 19.39), P(14.21, 18.22), P(14.21, 20.56), P(12.19, 21.73)], [P(14.6, 12.42), P(16.61, 11.25), P(16.61, 13.59), P(14.6, 14.76)], [P(14.6, 15.21), P(16.61, 14.03), P(16.61, 16.38), P(14.6, 17.55)], [P(14.6, 17.99), P(16.61, 16.82), P(16.61, 19.17), P(14.6, 20.34)], [P(17, 11.02), P(19.02, 9.85), P(19.02, 12.19), P(17, 13.37)], [P(17, 13.81), P(19.02, 12.64), P(19.02, 14.98), P(17, 16.15)], [P(17, 16.6), P(19.02, 15.43), P(19.02, 17.77), P(17, 18.94)]]),
        (0.85, [[P(4.98, 9.85), P(7, 11.02), P(7, 13.37), P(4.98, 12.19)], [P(4.98, 12.64), P(7, 13.81), P(7, 16.15), P(4.98, 14.98)], [P(4.98, 15.43), P(7, 16.6), P(7, 18.94), P(4.98, 17.77)], [P(7.39, 11.25), P(9.4, 12.42), P(9.4, 14.76), P(7.39, 13.59)], [P(7.39, 14.03), P(9.4, 15.21), P(9.4, 17.55), P(7.39, 16.38)], [P(7.39, 16.82), P(9.4, 17.99), P(9.4, 20.34), P(7.39, 19.17)], [P(9.79, 12.64), P(11.81, 13.81), P(11.81, 16.15), P(9.79, 14.98)], [P(9.79, 15.43), P(11.81, 16.6), P(11.81, 18.94), P(9.79, 17.77)], [P(9.79, 18.22), P(11.81, 19.39), P(11.81, 21.73), P(9.79, 20.56)]]),
        (1, [[P(5.18, 9.52), P(7.19, 8.35), P(9.21, 9.52), P(7.19, 10.69)], [P(7.58, 10.91), P(9.6, 9.74), P(11.62, 10.91), P(9.6, 12.08)], [P(9.98, 12.31), P(12, 11.13), P(14.02, 12.31), P(12, 13.48)], [P(7.58, 8.12), P(9.6, 6.95), P(11.62, 8.12), P(9.6, 9.29)], [P(9.98, 9.52), P(12, 8.35), P(14.02, 9.52), P(12, 10.69)], [P(12.38, 10.91), P(14.4, 9.74), P(16.42, 10.91), P(14.4, 12.08)], [P(9.98, 6.73), P(12, 5.56), P(14.02, 6.73), P(12, 7.9)], [P(12.38, 8.12), P(14.4, 6.95), P(16.42, 8.12), P(14.4, 9.29)], [P(14.79, 9.52), P(16.81, 8.35), P(18.82, 9.52), P(16.81, 10.69)]]),
    ]
    var body: some View {
        Canvas { c, size in
            let k = min(size.width, size.height) / 24
            let t = CGAffineTransform(scaleX: k, y: k)
            for (opacita, poligoni) in IconaStudio.tasselli {
                var p = Path()
                for poli in poligoni { p.addLines(poli); p.closeSubpath() }
                var g = c
                g.opacity = opacita
                g.fill(p.applying(t), with: .foreground)
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
