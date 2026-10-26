#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import Combine

// MARK: - STUDIO (MARK X): il banco olografico per modellare in 3D e stampare, IDENTICO al mockup approvato.
// La pagina è il mockup stesso («Studio3D/studio.html», generata da tools/studio_app.py) con three.js 0.160 nel pacchetto
// (schema jarvis3d://, niente rete per il 3D), come il LiDAR della build 26. L'app le dà quello che il mockup simulava:
//  · la voce di JARVIS (ogni frase del banco la dice lui), il microfono vero (dettatura) per i comandi a voce dello Studio;
//  · FOTO con la fotocamera vera dell'iPhone; CREA libero col cervello (funzione «studio-inventa»);
//  · STAMPA/CONDIVIDI: il file STL o 3MF va al foglio di condivisione (File, AirDrop, l'app della stampante);
//  · l'ARCHIVIO dei progetti salvato sull'iPhone (Application Support/studio-archivio.json), non nel browser.

struct VistaStudio: View {
    let parla: (String) -> Void
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        PaginaStudio(parla: parla, chiudi: { chiudi() })
            .background(Color.fondo)
            .ignoresSafeArea()
            .statusBarHidden(false)
    }
}

private struct PaginaStudio: UIViewRepresentable {
    let parla: (String) -> Void
    let chiudi: () -> Void
    func makeCoordinator() -> RegiaStudio { RegiaStudio(parla: parla, chiudi: chiudi) }
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

    init(parla: @escaping (String) -> Void, chiudi: @escaping () -> Void) {
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
        ponte.addUserScript(WKUserScript(source: RegiaStudio.copioneFine, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
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
        if let u = URL(string: "\(Self.schema)://app/studio.html") { w.load(URLRequest(url: u)) }
        return w
    }

    func smonta() {
        chiuso = true
        dettatura.ferma()
        salvaOra()
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "jarvis")
    }

    // MARK: i file della pagina (dal pacchetto dell'app)

    func webView(_ webView: WKWebView, start t: any WKURLSchemeTask) {
        guard let url = t.request.url else { return }
        let nome = url.lastPathComponent
        let base = (nome as NSString).deletingPathExtension, est = (nome as NSString).pathExtension
        guard ["studio.html", "three.module.min.js"].contains(nome),
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
            Task { await self.rispondi(id, await RegiaStudio.chiediCervello(prompt)) }
        case "salvaFile":                                                // STAMPA / CONDIVIDI
            guard let nome = o["nome"] as? String, let b64 = o["b64"] as? String, let d = Data(base64Encoded: b64) else { rispondi(id, (nil, "file non valido")); return }
            condividi(d, nome: nome) { [weak self] ok in self?.rispondi(id, ok ? ("ok", nil) : (nil, "declined")) }
        case "foto":
            scatta()
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

    private func scatta() {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = self
        RegiaStudio.inCima(web)?.present(p, animated: true)
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = info[.originalImage] as? UIImage else { return }
        let lato: CGFloat = 1400, k = min(1, lato / max(img.size.width, img.size.height))
        let piccola = UIGraphicsImageRenderer(size: CGSize(width: img.size.width * k, height: img.size.height * k)).image { _ in
            img.draw(in: CGRect(x: 0, y: 0, width: img.size.width * k, height: img.size.height * k))
        }
        guard let jpg = piccola.jpegData(compressionQuality: 0.82) else { return }
        esegui("(function(){var im=new Image();im.onload=function(){window.STUDIO_ATTIVO&&window.STUDIO_ATTIVO.foto(im,'foto');};im.src='data:image/jpeg;base64,\(jpg.base64EncodedString())';})()")
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
        })();
        """
    }

    /// Dopo gli script del mockup: a tutto schermo, la voce di JARVIS, lo Studio aperto subito; chiuso lo Studio, si torna all'app.
    static let copioneFine = """
    (function(){
      var post = function(o){ try { window.webkit.messageHandlers.jarvis.postMessage(o); } catch (e) {} };
      var st = document.createElement('style');
      st.textContent = 'html,:root{padding:0!important}body{padding:0!important;margin:0!important;display:block!important;background:#020304!important;overflow:hidden!important}'
        + 'body>*:not(#cornice){display:none!important}#cornice,#cornice>.telefono{width:100vw!important;height:100vh!important;transform:none!important;margin:0!important;border:0!important;border-radius:0!important;box-shadow:none!important}'
        + '.isola{opacity:0!important}.sd-su{padding-top:calc(env(safe-area-inset-top,0px) + 6px)!important}';
      document.head.appendChild(st);
      if (typeof window.parlaMock === 'function') { var o = window.parlaMock; window.parlaMock = function(t){ post({ tipo: 'parla', testo: String(t) }); return o.apply(this, arguments); }; }
      var sez = document.getElementById('sezione');
      var aperta = false;
      if (sez) new MutationObserver(function(){ if (sez.classList.contains('su')) aperta = true; else if (aperta) { aperta = false; post({ tipo: 'chiudi' }); } }).observe(sez, { attributes: true, attributeFilter: ['class'] });
      if (typeof window.apriSezione === 'function') window.apriSezione('Studio');
      if (sez && sez.classList.contains('su')) aperta = true;
    })();
    """
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
