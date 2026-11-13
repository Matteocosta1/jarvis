#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import WebKit
import ModelIO
import simd

// MARK: - LiDAR 3D nella pagina web (build 26)
// Il 3D di LiDAR non è più SceneKit (sull'iPhone del signore usciva tutto magenta, anche semplificato): è il motore del mockup
// approvato, three.js 0.160, dentro una WKWebView. La pagina è «Lidar3D/lidar3d.html» (three.js compreso, niente rete) e la
// serve questa classe con lo schema jarvis3d://, insieme ai dati veri della scansione («modello.json»), al corpo d'esempio
// («corpo.bin», lo stesso dell'Organismo) e alla texture fotografica del gemello digitale («tex»).
// I tocchi li prende l'app: il dito in orizzontale gira (e in verticale inclina, come nel mockup), in verticale puro scorre la
// pagina; due dita ingrandiscono; doppio tocco riparte. Lo stile (OLOGRAMMA · TEXTURE) cambia senza ricaricare (J3D.stile).

/// Il riquadro: la pagina 3D trasparente, i gesti sopra.
struct Superficie3DLidar: UIViewRepresentable {
    let modello: ModelloScena
    let fase: FaseScenaLidar
    let stile: StileLidar?

    func makeCoordinator() -> Regia3DLidar { Regia3DLidar(modello: modello, fase: fase, stile: stile) }
    func makeUIView(context: Context) -> Contenitore3DLidar { context.coordinator.costruisci() }
    func updateUIView(_ v: Contenitore3DLidar, context: Context) { context.coordinator.imposta(stile) }
    static func dismantleUIView(_ v: Contenitore3DLidar, coordinator: Regia3DLidar) { coordinator.chiudi() }
}

/// Il contenitore: tiene la pagina a tutta grandezza e riceve i tocchi (la pagina non ne riceve: non scorre, non ingrandisce, non seleziona).
final class Contenitore3DLidar: UIView {
    weak var web: WKWebView?
    override func layoutSubviews() {
        super.layoutSubviews()
        web?.frame = bounds
    }
}

/// La regia: crea la pagina, le serve i file e i dati, le passa gesti e stile.
final class Regia3DLidar: NSObject, WKURLSchemeHandler, WKNavigationDelegate, UIGestureRecognizerDelegate {
    static let schema = "jarvis3d"

    private let modello: ModelloScena
    private let fase: FaseScenaLidar
    private var stile: StileLidar?
    private weak var web: WKWebView?
    private weak var contenitore: Contenitore3DLidar?
    private weak var scorrimento: UIScrollView?            // la pagina SwiftUI: ferma mentre il dito gira il modello
    private var pacco: Pacco3DLidar?
    private var preparazione: Task<Void, Never>?
    private var attivi = Set<ObjectIdentifier>()           // le richieste della pagina ancora aperte (a una chiusa non si risponde mai)
    private var inAttesa: [any WKURLSchemeTask] = []       // modello.json e tex chiesti prima che i dati fossero pronti
    private var chiuso = false
    private var pizzicando = false

    init(modello: ModelloScena, fase: FaseScenaLidar, stile: StileLidar?) {
        self.modello = modello
        self.fase = fase
        self.stile = stile
        super.init()
    }

    func costruisci() -> Contenitore3DLidar {
        let c = Contenitore3DLidar(frame: .zero)
        c.backgroundColor = .clear
        c.isOpaque = false
        c.clipsToBounds = true
        let conf = WKWebViewConfiguration()
        conf.setURLSchemeHandler(self, forURLScheme: Self.schema)
        conf.websiteDataStore = .nonPersistent()
        let w = WKWebView(frame: .zero, configuration: conf)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.underPageBackgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.scrollView.isScrollEnabled = false
        w.scrollView.bounces = false
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.isUserInteractionEnabled = false                 // i tocchi vanno al contenitore
        w.navigationDelegate = self
        w.isInspectable = true                              // se servisse: Safari › Sviluppo › iPhone › la pagina del 3D
        c.addSubview(w)
        c.web = w
        web = w
        contenitore = c

        let pan = UIPanGestureRecognizer(target: self, action: #selector(trascina(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        c.addGestureRecognizer(pan)
        let pinza = UIPinchGestureRecognizer(target: self, action: #selector(pizzica(_:)))
        pinza.delegate = self
        c.addGestureRecognizer(pinza)
        let doppio = UITapGestureRecognizer(target: self, action: #selector(doppioTocco(_:)))
        doppio.numberOfTapsRequired = 2
        doppio.delegate = self
        c.addGestureRecognizer(doppio)

        prepara()
        if let url = URL(string: "\(Self.schema)://lidar/lidar3d.html") { w.load(URLRequest(url: url)) }
        return c
    }

    /// OLOGRAMMA ↔ TEXTURE: la pagina fa salire il nuovo materiale dal basso, senza ricaricare.
    func imposta(_ s: StileLidar?) {
        guard s != stile else { return }
        stile = s
        mandaStile()
    }

    func chiudi() {
        guard !chiuso else { return }
        js("J3D.chiudi()")
        chiuso = true
        preparazione?.cancel()
        inAttesa = []
        attivi = []
        bloccaScorrimento(false)
        web?.stopLoading()
        web?.navigationDelegate = nil
    }

    // MARK: I dati (preparati fuori dal thread principale: il gemello digitale va letto dal file USDZ)

    private func prepara() {
        let m = modello, f = fase, s = stile
        preparazione = Task { [weak self] in
            let p = await Task.detached(priority: .userInitiated) { Lidar3DDati.pacco(m, fase: f, stile: s) }.value
            guard let self, !self.chiuso else { return }
            self.pacco = p
            let coda = self.inAttesa
            self.inAttesa = []
            for t in coda { self.servi(t) }
        }
    }

    // MARK: Schema jarvis3d:// (WKURLSchemeHandler)

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        attivi.insert(ObjectIdentifier(urlSchemeTask))
        let nome = urlSchemeTask.request.url?.lastPathComponent ?? ""
        switch nome {
        case "modello.json", "tex":
            if pacco != nil { servi(urlSchemeTask) } else { inAttesa.append(urlSchemeTask) }
        case "lidar3d.html", "corpo.bin":
            if let u = Self.risorsa(nome), let d = try? Data(contentsOf: u) {
                rispondi(urlSchemeTask, d, nome.hasSuffix(".html") ? "text/html; charset=utf-8" : "application/octet-stream")
            } else if nome.hasSuffix(".html") {                // la pagina non è nel pacchetto: una scritta, mai un riquadro vuoto
                let testo = "<!doctype html><meta charset=\"utf-8\"><body style=\"margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:transparent;color:#ffb45a;font:600 11px ui-monospace,monospace;letter-spacing:1px;text-align:center;padding:16px;box-sizing:border-box\">3D non disponibile · manca lidar3d.html nell'app</body>"
                rispondi(urlSchemeTask, Data(testo.utf8), "text/html; charset=utf-8")
            } else {
                manca(urlSchemeTask)
            }
        default:
            manca(urlSchemeTask)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        attivi.remove(ObjectIdentifier(urlSchemeTask))
        inAttesa.removeAll { $0 === urlSchemeTask }
    }

    /// I file della pagina: nel pacchetto dell'app la cartella «Lidar3D» si appiattisce (si cercano tutti e due i posti).
    private static func risorsa(_ nome: String) -> URL? {
        let base = (nome as NSString).deletingPathExtension, est = (nome as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: est)
            ?? Bundle.main.url(forResource: base, withExtension: est, subdirectory: "Lidar3D")
    }

    private func servi(_ t: any WKURLSchemeTask) {
        guard let p = pacco else { return }
        if t.request.url?.lastPathComponent == "tex" {
            if let d = p.texture { rispondi(t, d, p.mimeTexture) } else { manca(t) }
        } else {
            rispondi(t, p.json, "application/json; charset=utf-8")
        }
    }

    private func rispondi(_ t: any WKURLSchemeTask, _ d: Data, _ mime: String, stato: Int = 200) {
        let id = ObjectIdentifier(t)
        guard !chiuso, attivi.contains(id), let url = t.request.url else { return }
        attivi.remove(id)
        let intestazioni: [String: String] = ["Content-Type": mime, "Content-Length": String(d.count), "Cache-Control": "no-store",
                                              "Access-Control-Allow-Origin": "*"]
        let r: URLResponse = HTTPURLResponse(url: url, statusCode: stato, httpVersion: "HTTP/1.1", headerFields: intestazioni)
            ?? URLResponse(url: url, mimeType: mime, expectedContentLength: d.count, textEncodingName: nil)
        t.didReceive(r)
        t.didReceive(d)
        t.didFinish()
    }

    private func manca(_ t: any WKURLSchemeTask) {
        rispondi(t, Data("non trovato".utf8), "text/plain; charset=utf-8", stato: 404)
    }

    // MARK: La pagina (WKNavigationDelegate)

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        mandaStile()                                        // lo stile di adesso, anche se è cambiato mentre la pagina caricava
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !chiuso else { return }
        webView.reload()                                    // iOS ha chiuso la pagina per memoria: la si riapre
    }

    private func mandaStile() {
        let s: String
        if let st = stile { s = "\"\(st.rawValue)\"" } else { s = "null" }
        js("J3D.stile(\(s))")
    }

    private func js(_ codice: String) {
        guard !chiuso, let w = web else { return }
        w.evaluateJavaScript("if (window.J3D) { \(codice); }", completionHandler: nil)
    }

    private static func numero(_ v: CGFloat) -> String {
        let d = Double(v)
        return String(format: "%.3f", d.isFinite ? d : 0)
    }

    // MARK: I gesti (come il mockup: x del dito × 0,009 gira, y × 0,006 inclina, due dita ingrandiscono, doppio tocco riparte)

    @objc func trascina(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            bloccaScorrimento(true)
            js("J3D.dita(1)")
            muovi(g)
        case .changed:
            muovi(g)
        default:
            js("J3D.dita(0)")
            bloccaScorrimento(false)
        }
    }

    private func muovi(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        g.setTranslation(.zero, in: g.view)
        guard !pizzicando else { return }
        js("J3D.trascina(\(Self.numero(t.x)), \(Self.numero(t.y)))")
    }

    @objc func pizzica(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pizzicando = true
            js("J3D.dita(2); J3D.pinza(1, 1)")
        case .changed:
            js("J3D.pinza(0, \(Self.numero(g.scale)))")
        default:
            pizzicando = false
            js("J3D.dita(0)")
        }
    }

    @objc func doppioTocco(_ g: UITapGestureRecognizer) {
        if g.state == .ended { js("J3D.reset()") }
    }

    /// Il dito parte in orizzontale: gira il modello; in verticale: scorre la pagina (il «pan-y» del mockup).
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let p = g as? UIPanGestureRecognizer else { return true }
        let v = p.velocity(in: p.view)
        return abs(v.x) > abs(v.y)
    }

    /// Insieme solo i gesti del riquadro (giro, due dita, doppio tocco); lo scorrimento della pagina no.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool {
        altro.view === g.view
    }

    /// Mentre il dito gira il modello la pagina non scorre (come Safari col mockup); al rilascio torna libera.
    private func bloccaScorrimento(_ si: Bool) {
        if si {
            var v = contenitore?.superview
            while let x = v, !(x is UIScrollView) { v = x.superview }
            scorrimento = v as? UIScrollView
            scorrimento?.panGestureRecognizer.isEnabled = false
        } else {
            scorrimento?.panGestureRecognizer.isEnabled = true
            scorrimento = nil
        }
    }
}

// MARK: - I dati per la pagina («modello.json»)
// Numeri sempre finiti (JSONSerialization non accetta NaN), maglie e quote in base64 (Float32 / UInt32, little-endian),
// i testi delle etichette già scritti qui con LidarFormato (stessa virgola e stesse unità dei pannelli).

nonisolated struct Pacco3DLidar: Sendable {
    let json: Data
    let texture: Data?
    let mimeTexture: String
}

/// Il gemello digitale letto dal file USDZ di Object Capture.
nonisolated struct Statua3DLidar {
    var vertici: [Float] = []
    var normali: [Float] = []
    var uv: [Float] = []
    var indici: [UInt32] = []
    var conNormali = true
    var conUV = true
    var nomeTexture: String?                                // il nome dell'immagine del colore secondo ModelIO (se lo dice)
    var texture: Data?
    var mime = "image/png"
    var errore: String?
}

nonisolated enum Lidar3DDati {
    static func pacco(_ m: ModelloScena, fase: FaseScenaLidar, stile: StileLidar?) -> Pacco3DLidar {
        let st: Any
        if let s = stile { st = s.rawValue } else { st = NSNull() }
        let fa: String
        switch fase {
        case .anteprima: fa = "anteprima"
        case .risultato: fa = "risultato"
        }
        var d: [String: Any] = ["v": 1, "fase": fa, "stile": st]
        var tex: Data? = nil
        var mime = "image/png"
        switch m {
        case .stanza(let s):
            d["tipo"] = "stanza"; d["stanza"] = stanza(s)
        case .evento(let s, let a):
            d["tipo"] = "evento"; d["stanza"] = stanza(s); d["allestimento"] = allestimento(a)
        case .esterno(let t):
            d["tipo"] = "esterno"; d["terreno"] = terreno(t)
        case .oggetto(let o):
            d["tipo"] = "oggetto"; d["oggetto"] = oggetto(o)
        case .cassaEsempio:
            d["tipo"] = "cassa"
        case .statua(let url, _):
            d["tipo"] = "statua"
            if let url {
                let s = statua(url)
                if let e = s.errore { return errore(e) }
                d["statua"] = dizionario(s)
                tex = s.texture
                mime = s.mime
            } else {
                d["statua"] = ["esempio": true] as [String: Any]
            }
        case .postura(let p):
            d["tipo"] = "postura"; d["postura"] = postura(p)
        case .misura(let l, let h):
            d["tipo"] = "misura"
            d["misura"] = ["larghezza": n(Double(l)), "altezza": n(Double(h)),
                           "testoL": LidarFormato.m(Double(l), 2), "testoH": LidarFormato.m(Double(h), 2)] as [String: Any]
        }
        guard JSONSerialization.isValidJSONObject(d), let j = try? JSONSerialization.data(withJSONObject: d) else {
            return errore("i dati del modello non si possono scrivere")
        }
        return Pacco3DLidar(json: j, texture: tex, mimeTexture: mime)
    }

    /// Un pacco con solo il messaggio: la pagina lo scrive al posto del 3D.
    static func errore(_ testo: String) -> Pacco3DLidar {
        let d: [String: Any] = ["v": 1, "errore": testo]
        let j = (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{\"v\":1,\"errore\":\"dati del modello non validi\"}".utf8)
        return Pacco3DLidar(json: j, texture: nil, mimeTexture: "image/png")
    }

    static func n(_ x: Double) -> Double { x.isFinite ? min(max(x, -1e6), 1e6) : 0 }

    static func b64(_ a: [Float]) -> String {
        let pulito = a.map { $0.isFinite ? $0 : 0 }
        return pulito.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
    }
    static func b64(_ a: [UInt32]) -> String {
        a.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
    }

    static func finito(_ t: TrattoPianta) -> Bool { t.ax.isFinite && t.az.isFinite && t.bx.isFinite && t.bz.isFinite }

    static func tratto(_ t: TrattoPianta) -> [String: Any] {
        var r: [String: Any] = ["a": [t.ax, t.az], "b": [t.bx, t.bz]]
        if let b = t.basso, b.isFinite { r["basso"] = b }
        if let a = t.alto, a.isFinite { r["alto"] = a }
        return r
    }

    static func stanza(_ s: StanzaScena) -> [String: Any] {
        let pav: [[Double]] = s.pavimento.filter { $0.x.isFinite && $0.y.isFinite }.map { [$0.x, $0.y] }
        let h = s.altezza.isFinite && s.altezza > 0 ? s.altezza : 2.7
        let r: [String: Any] = ["pavimento": pav,
                                "pareti": s.pareti.filter(finito).map(tratto),
                                "porte": s.porte.filter(finito).map(tratto),
                                "finestre": s.finestre.filter(finito).map(tratto),
                                "altezza": h,
                                "testoAltezza": LidarFormato.m(h, 2),
                                "testoArea": LidarFormato.n(n(s.area)) + " m²"]
        return r
    }

    static func rettangolo(_ r: RettangoloPiano?) -> Any {
        guard let r else { return NSNull() }
        let d: [String: Any] = ["c": [n(r.centro.x), n(r.centro.y)], "a": [n(r.asse.x), n(r.asse.y)],
                                "lungo": n(r.lungo), "largo": n(r.largo), "verso": n(r.versoMuro)]
        return d
    }

    static func allestimento(_ a: Allestimento) -> [String: Any] {
        let passaggi: [[Double]] = a.passaggi.map { [n($0.0.x), n($0.0.y), n($0.1.x), n($0.1.y)] }
        let stand: [Any] = a.stand.map { rettangolo($0) }
        let r: [String: Any] = ["palco": rettangolo(a.palco), "console": rettangolo(a.console), "bar": rettangolo(a.bar),
                                "stand": stand, "passaggi": passaggi]
        return r
    }

    static func terreno(_ t: TerrenoScena) -> [String: Any] {
        var r: [String: Any] = ["bordo": t.bordo.map { [n($0.x), n($0.y)] }, "origine": [n(t.origine.x), n(t.origine.y)],
                                "passo": n(t.passo), "nx": t.nx, "nz": t.nz, "quote": b64(t.quote),
                                "testoArea": LidarFormato.n(n(t.area)) + " m²", "testoDislivello": "Δ " + LidarFormato.cm(n(t.dislivello))]
        if let c = t.colori, c.count == t.nx * t.nz {
            var f: [Float] = []
            f.reserveCapacity(c.count * 3)
            for x in c { f.append(x.x); f.append(x.y); f.append(x.z) }
            r["colori"] = b64(f)
        }
        return r
    }

    static func oggetto(_ o: OggettoScena) -> [String: Any] {
        var v: [Float] = []
        v.reserveCapacity(o.vertici.count * 3)
        for p in o.vertici { v.append(p.x); v.append(p.y); v.append(p.z) }
        let nv = UInt32(o.vertici.count)
        var idx: [UInt32] = []
        idx.reserveCapacity(o.indici.count)
        var k = 0
        while k + 2 < o.indici.count {                                // solo i triangoli coi tre vertici esistenti
            let a = o.indici[k], b = o.indici[k + 1], c = o.indici[k + 2]
            if a < nv && b < nv && c < nv { idx.append(a); idx.append(b); idx.append(c) }
            k += 3
        }
        let l = Double(o.largo), p = Double(o.profondo), h = Double(o.alto)
        var r: [String: Any] = ["vertici": b64(v), "indici": b64(idx), "largo": n(l), "profondo": n(p), "alto": n(h),
                                "testi": [LidarFormato.cm(n(l)), LidarFormato.cm(n(p)), LidarFormato.cm(n(h))]]
        if let c = o.colori, c.count == o.vertici.count {
            var f: [Float] = []
            f.reserveCapacity(c.count * 3)
            for x in c { f.append(x.x); f.append(x.y); f.append(x.z) }
            r["colori"] = b64(f)
        }
        return r
    }

    static func postura(_ p: PosturaScena) -> [String: Any] {
        var g: [String: Any] = [:]
        for (k, v) in p.giunture where v.x.isFinite && v.y.isFinite && v.z.isFinite { g[k] = [Double(v.x), Double(v.y), Double(v.z)] }
        let h = Double(p.altezza).isFinite && p.altezza > 0.5 ? Double(p.altezza) : 1.78
        let r: [String: Any] = ["giunture": g, "altezza": h, "bacinoGradi": n(Double(p.bacinoGradi)),
                                "testoSpalle": "SPALLE " + LidarFormato.cm(n(Double(p.spalle))),
                                "testoBacino": "BACINO " + LidarFormato.bacino(n(Double(p.bacinoGradi))),
                                "testoAltezza": LidarFormato.m(h, 2)]
        return r
    }

    static func dizionario(_ s: Statua3DLidar) -> [String: Any] {
        var minY = Float.infinity, maxY = -Float.infinity
        var i = 1
        while i < s.vertici.count { minY = min(minY, s.vertici[i]); maxY = max(maxY, s.vertici[i]); i += 3 }
        let h = maxY > minY ? Double(maxY - minY) : 0
        var r: [String: Any] = ["vertici": b64(s.vertici), "indici": b64(s.indici), "texture": s.texture != nil,
                                "testoAltezza": LidarFormato.m(n(h), 2)]
        if s.conUV && s.uv.count * 3 == s.vertici.count * 2 { r["uv"] = b64(s.uv) }
        if s.conNormali && s.normali.count == s.vertici.count { r["normali"] = b64(s.normali) }
        return r
    }

    // MARK: Il gemello digitale (USDZ di Object Capture): la maglia con ModelIO, l'immagine del colore direttamente dal pacchetto

    static func statua(_ url: URL) -> Statua3DLidar {
        var s = Statua3DLidar()
        guard FileManager.default.fileExists(atPath: url.path) else { s.errore = "il modello 3D non c'è più sul telefono"; return s }
        let asset = MDLAsset(url: url)
        for o in asset.childObjects(of: MDLMesh.self) {
            guard let mesh = o as? MDLMesh else { continue }
            leggi(mesh, in: &s)
        }
        guard !s.vertici.isEmpty, !s.indici.isEmpty else { s.errore = "non riesco a leggere il modello 3D (USDZ)"; return s }
        if let d = try? Data(contentsOf: url, options: .mappedIfSafe), let img = immagineColore(d, suggerito: s.nomeTexture) {
            s.texture = img.dati
            s.mime = img.mime
        }
        return s
    }

    /// La posizione nel mondo: le trasformazioni dell'oggetto e dei suoi genitori.
    static func matriceMondo(_ o: MDLObject) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        var x: MDLObject? = o
        while let c = x {
            if let t = c.transform { m = t.matrix * m }
            x = c.parent
        }
        return m
    }

    static func leggi(_ mesh: MDLMesh, in s: inout Statua3DLidar) {
        let nv = mesh.vertexCount
        guard nv > 0, let pos = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition, as: .float3), pos.stride >= 12 else { return }
        let nor = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3)
        let tc = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2)
        let conN = (nor?.stride ?? 0) >= 12, conT = (tc?.stride ?? 0) >= 8
        if !conN { s.conNormali = false }
        if !conT { s.conUV = false }
        let M = matriceMondo(mesh)
        let N = simd_float3x3(SIMD3<Float>(M.columns.0.x, M.columns.0.y, M.columns.0.z),
                              SIMD3<Float>(M.columns.1.x, M.columns.1.y, M.columns.1.z),
                              SIMD3<Float>(M.columns.2.x, M.columns.2.y, M.columns.2.z))
        let base = UInt32(s.vertici.count / 3)
        for i in 0..<nv {
            let o = i * pos.stride
            let p = SIMD4<Float>(pos.dataStart.loadUnaligned(fromByteOffset: o, as: Float.self),
                                 pos.dataStart.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                                 pos.dataStart.loadUnaligned(fromByteOffset: o + 8, as: Float.self), 1)
            let w = M * p
            s.vertici.append(w.x); s.vertici.append(w.y); s.vertici.append(w.z)
            if conN, let nor {
                let q = i * nor.stride
                let nn = N * SIMD3<Float>(nor.dataStart.loadUnaligned(fromByteOffset: q, as: Float.self),
                                          nor.dataStart.loadUnaligned(fromByteOffset: q + 4, as: Float.self),
                                          nor.dataStart.loadUnaligned(fromByteOffset: q + 8, as: Float.self))
                let l = simd_length(nn)
                if l > 0 && l.isFinite { s.normali.append(nn.x / l); s.normali.append(nn.y / l); s.normali.append(nn.z / l) }
                else { s.normali.append(0); s.normali.append(1); s.normali.append(0) }
            }
            if conT, let tc {
                let q = i * tc.stride
                s.uv.append(tc.dataStart.loadUnaligned(fromByteOffset: q, as: Float.self))
                s.uv.append(tc.dataStart.loadUnaligned(fromByteOffset: q + 4, as: Float.self))
            }
        }
        guard let sotto = mesh.submeshes else { return }
        let limite = UInt32(nv)
        for case let sm as MDLSubmesh in sotto where sm.geometryType == .triangles {
            let buf = sm.indexBuffer(asIndexType: .uInt32)
            let mappa = buf.map()
            let quanti = min(sm.indexCount, buf.length / 4)
            var k = 0
            while k + 2 < quanti {
                let a = mappa.bytes.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self)
                let b = mappa.bytes.loadUnaligned(fromByteOffset: k * 4 + 4, as: UInt32.self)
                let c = mappa.bytes.loadUnaligned(fromByteOffset: k * 4 + 8, as: UInt32.self)
                if a < limite && b < limite && c < limite { s.indici.append(base + a); s.indici.append(base + b); s.indici.append(base + c) }
                k += 3
            }
            if s.nomeTexture == nil, let mat = sm.material, let p = mat.property(with: .baseColor) {
                let nomi: [String?] = [p.textureSamplerValue?.texture?.name, p.urlValue?.lastPathComponent, p.stringValue]
                s.nomeTexture = nomi.compactMap { $0 }.map { ($0 as NSString).lastPathComponent }.first { !$0.isEmpty }
            }
        }
    }

    /// Il file USDZ è uno zip senza compressione: le immagini si prendono così come sono. Si sceglie quella del colore
    /// (il nome che dice ModelIO; se no la «tex»/«diffuse»/«albedo», mai normali, occlusione, rugosità, metallo).
    static func immagineColore(_ d: Data, suggerito: String?) -> (dati: Data, mime: String)? {
        var immagini: [(nome: String, dati: Data)] = []
        let z = [UInt8](d)
        func u16(_ o: Int) -> Int { Int(z[o]) | Int(z[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        var i = 0
        while i + 30 <= z.count, u32(i) == 0x04034b50 {
            let metodo = u16(i + 8), taglia = u32(i + 18), lNome = u16(i + 26), lExtra = u16(i + 28)
            let inizio = i + 30 + lNome + lExtra
            guard inizio + taglia <= z.count else { break }
            let nome = String(decoding: z[(i + 30)..<(i + 30 + lNome)], as: UTF8.self)
            let est = (nome as NSString).pathExtension.lowercased()
            if metodo == 0, taglia > 0, ["png", "jpg", "jpeg"].contains(est) {
                immagini.append((nome: nome, dati: Data(z[inizio..<(inizio + taglia)])))
            }
            i = inizio + taglia
        }
        func mime(_ nome: String) -> String { (nome as NSString).pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg" }
        if let s = suggerito?.lowercased(), let x = immagini.first(where: { ($0.nome as NSString).lastPathComponent.lowercased() == s }) {
            return (x.dati, mime(x.nome))
        }
        let vietate = ["norm", "_ao", "ao0", "occl", "rough", "metal", "opac", "disp", "height", "bump", "spec"]
        let buone = immagini.filter { im in
            let n = (im.nome as NSString).lastPathComponent.lowercased()
            return !vietate.contains { n.contains($0) }
        }
        let preferite = ["tex", "diffuse", "albedo", "basecolor", "base_color", "color"]
        if let x = buone.first(where: { im in preferite.contains { (im.nome as NSString).lastPathComponent.lowercased().contains($0) } }) {
            return (x.dati, mime(x.nome))
        }
        if let x = buone.max(by: { $0.dati.count < $1.dati.count }) { return (x.dati, mime(x.nome)) }
        return nil
    }
}
#endif
