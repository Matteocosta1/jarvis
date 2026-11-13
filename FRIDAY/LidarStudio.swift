#if os(iOS)
import Foundation
import simd

// MARK: - MARK X · LiDAR → STUDIO: la scansione vera dell'iPhone sul banco dello Studio (non più i dati d'esempio del mockup)
// Il tasto STUDIO del risultato di LiDAR manda alla pagina dello Studio (window.STUDIO_DA = { lidarVero }) quello che ha misurato:
//  · INTERNO e SETUP: il poligono del pavimento, porte e finestre sulle loro pareti (con le altezze vere), l'altezza della sala e,
//    per SETUP, palco, console, bar e stand calcolati da Allestimento → il plastico dello Studio (1:100, 1:200 se la sala è grande);
//  · ESTERNO: il terreno come solido chiuso (quote vere, rilievo ×1, base 4 mm) → plastico 1:50 o più piccolo;
//  · OGGETTO e TEXTURE: la maglia vera (oggetto in scala per stare nel piatto, persona statuina 1:10);
//  · CORPO: le giunture vere → la sagoma con quelle proporzioni → ologramma (come la sagoma del mockup).
// Misura no (come il mockup). Le maglie vanno in millimetri, triangoli sciolti con le normali, Float32 in base64.

nonisolated enum LidarAlloStudio {
    /// Quanti pezzi al massimo legge la ricetta dello Studio (B.ricetta: pezzi.slice(0, 28)).
    static let pezziMassimi = 28
    /// Il lato più lungo che un pezzo dello Studio può avere (la ricetta lo taglia a 250 mm).
    static let latoMassimo = 220.0

    /// Le frasi di JARVIS quando manda allo Studio (le stesse del mockup).
    static func frase(_ m: ModoLidar) -> String {
        switch m {
        case .stanza: return "Mando la sala allo Studio, Sir: diventa un plastico in scala."
        case .oggetto: return "Mando la scansione allo Studio, Sir."
        case .esterno: return "Mando il terreno allo Studio, Sir: diventa un plastico in scala."
        case .evento: return "Mando l'allestimento allo Studio, Sir: plastico della sala con palco, bar e stand."
        case .corpo, .statua: return "Mando il corpo allo Studio, Sir: diventa una statuina in scala."
        case .misura: return "Le misure restano qui, Sir: allo Studio passano sale, esterni, allestimenti, oggetti e corpi."
        }
    }

    /// Il JSON per la pagina, o il motivo per cui la scansione non basta.
    static func dati(_ m: ModelloScena) -> Result<String, Guasto> {
        let d: [String: Any]?
        switch m {
        case .stanza(let s): d = sala(s, allestimento: nil)
        case .evento(let s, let a): d = sala(s, allestimento: a)
        case .esterno(let t): d = terreno(t)
        case .oggetto(let o): d = oggetto(o)
        case .statua(let url, _): d = url.flatMap(persona)
        case .postura(let p): d = corpo(p)
        case .misura, .cassaEsempio: d = nil
        }
        guard let d, let j = try? JSONSerialization.data(withJSONObject: d), let s = String(data: j, encoding: .utf8) else { return .failure(Guasto()) }
        return .success(s)
    }
    struct Guasto: Error {}

    private static func n(_ x: Double) -> Double { x.isFinite ? (x * 1000).rounded() / 1000 : 0 }

    // MARK: INTERNO e SETUP → il plastico della sala

    static func sala(_ st: StanzaScena, allestimento a: Allestimento?) -> [String: Any]? {
        var poli = semplifica(st.pavimento.filter { $0.x.isFinite && $0.y.isFinite })
        guard poli.count >= 3, GeometriaPiana.area(poli) > 1 else { return nil }
        let off = SIMD2(poli.map(\.x).min() ?? 0, poli.map(\.y).min() ?? 0)
        poli = poli.map { $0 - off }                                    // la pagina vuole la sala dall'angolo (0, 0)
        let lato = max(poli.map(\.x).max() ?? 0, poli.map(\.y).max() ?? 0)
        let k = [100.0, 200, 400, 1000].first { lato * 1000 / $0 <= latoMassimo } ?? 1000
        let sc = 1000 / k                                                // millimetri per metro
        var posto = pezziMassimi - 1 - poli.count - (a == nil ? 0 : 3)  // pavimento e pareti prima di tutto
        func aperture(_ l: [TrattoPianta], basso: Double, alto: Double) -> [[String: Any]] {
            var out: [[String: Any]] = []
            for t in l where t.ax.isFinite && t.az.isFinite && t.bx.isFinite && t.bz.isFinite {
                let p = SIMD2(t.ax, t.az) - off, q = SIMD2(t.bx, t.bz) - off, m = (p + q) / 2
                var migliore = (i: -1, d: Double.infinity)
                for i in poli.indices {                                  // la parete più vicina al centro dell'apertura
                    let a = poli[i], b = poli[(i + 1) % poli.count], ab = b - a, L2 = simd_length_squared(ab)
                    guard L2 > 1e-6 else { continue }
                    let u = max(0, min(1, simd_dot(m - a, ab) / L2)), dist = simd_length(m - (a + ab * u))
                    if dist < migliore.d { migliore = (i, dist) }
                }
                guard migliore.i >= 0, migliore.d < 0.6 else { continue }   // non sta su una parete del pavimento
                let a = poli[migliore.i], b = poli[(migliore.i + 1) % poli.count], L = simd_length(b - a), u = (b - a) / L
                let t0 = simd_dot(p - a, u), t1 = simd_dot(q - a, u), da = max(0, min(t0, t1)), lu = min(abs(t1 - t0), L - da)
                guard lu > 0.3 else { continue }
                var o: [String: Any] = ["w": migliore.i, "da": n(da), "l": n(lu)]
                let b0 = t.basso ?? basso, a0 = t.alto ?? alto
                if b0.isFinite, a0.isFinite, a0 - b0 > 0.2, a0 <= st.altezza + 0.05 { o["basso"] = n(b0); o["alto"] = n(a0) }
                out.append(o)
            }
            return out
        }
        var porte = aperture(st.porte, basso: 0, alto: 2.1)
        var finestre = aperture(st.finestre, basso: 0.9, alto: 2.1)
        porte = Array(porte.prefix(max(0, posto))); posto -= porte.count
        finestre = Array(finestre.prefix(max(0, posto))); posto -= finestre.count
        let h = st.altezza.isFinite && st.altezza > 1.8 ? st.altezza : 2.7
        var d: [String: Any] = [
            "tipo": a == nil ? "stanza" : "setup", "sc": sc, "scala": "1:\(Int(k))",
            "sala": ["nome": "Sala scansionata", "h": n(h), "p": poli.map { [n($0.x), n($0.y)] }, "porte": porte, "finestre": finestre] as [String: Any],
        ]
        let alt = LidarFormato.n(h, 2).uppercased()
        if let a {
            func r(_ x: RettangoloPiano, _ alto: Double? = nil) -> [String: Any] {
                var o: [String: Any] = ["c": [n(x.centro.x - off.x), n(x.centro.y - off.y)], "u": [n(x.asse.x), n(x.asse.y)],
                                        "l": n(x.lungo), "p": n(x.largo), "verso": n(x.versoMuro)]
                if let alto { o["h"] = alto }
                return o
            }
            let posati = [(a.palco, 0.8), (a.console, 1.0), (a.bar, 1.1)].compactMap { x in x.0.map { r($0, x.1) } }
            let stand = a.stand.prefix(max(0, posto / 2)).map { r($0) }
            d["posati"] = posati
            d["stand"] = stand
            d["nome"] = "Plastico allestimento 1:\(Int(k))"
            let cosa = [a.palco == nil ? nil : "PALCO", a.console == nil ? nil : "CONSOLE", a.bar == nil ? nil : "BAR"].compactMap { $0 }
            d["righe"] = [(cosa + ["\(a.stand.count) STAND 3 × 3 M"]).joined(separator: " · ")]
                + (stand.count < a.stand.count ? ["NEL PLASTICO \(stand.count) STAND SU \(a.stand.count)"] : [])
        } else {
            d["nome"] = "Plastico sala 1:\(Int(k))"
            d["righe"] = ["\(alt) M D'ALTEZZA · \(porte.count) PORTE · \(finestre.count) FINESTRE"]
        }
        return d
    }

    /// Il pavimento senza i punti inutili (doppi, allineati) e al massimo 16 pareti: tolto sempre il vertice che cambia meno l'area.
    static func semplifica(_ p: [SIMD2<Double>]) -> [SIMD2<Double>] {
        var q: [SIMD2<Double>] = []
        for x in p where q.last.map({ simd_distance($0, x) > 0.1 }) ?? true { q.append(x) }
        if let a = q.first, let b = q.last, q.count > 3, simd_distance(a, b) <= 0.1 { q.removeLast() }
        while q.count > 3 {
            var meno = (i: 0, area: Double.infinity)
            for i in q.indices {
                let a = q[(i + q.count - 1) % q.count], b = q[i], c = q[(i + 1) % q.count]
                let ar = abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
                if ar < meno.area { meno = (i, ar) }
            }
            guard q.count > 16 || meno.area < 0.03 else { break }
            q.remove(at: meno.i)
        }
        return q
    }

    // MARK: ESTERNO → il terreno solido

    static func terreno(_ t: TerrenoScena) -> [String: Any]? {
        guard t.nx >= 2, t.nz >= 2, t.quote.count == t.nx * t.nz, t.passo > 0 else { return nil }
        let passo = max(1, Int((Double(max(t.nx, t.nz)) / 80).rounded(.up)))     // al massimo 80 × 80 punti
        let ii = Array(stride(from: 0, to: t.nx, by: passo)) + (((t.nx - 1) % passo == 0) ? [] : [t.nx - 1])
        let jj = Array(stride(from: 0, to: t.nz, by: passo)) + (((t.nz - 1) % passo == 0) ? [] : [t.nz - 1])
        let W = Double(t.nx - 1) * t.passo, D = Double(t.nz - 1) * t.passo
        guard W > 0.5, D > 0.5 else { return nil }
        let k = [50.0, 100, 200, 500, 1000].first { max(W, D) * 1000 / $0 <= latoMassimo } ?? 1000
        let sc = 1000 / k, base = 4.0
        let minimo = Double(t.quote.filter(\.isFinite).min() ?? 0)
        func y(_ i: Int, _ j: Int) -> Double {
            let q = Double(t.quote[j * t.nx + i])
            return base + max(0, (q.isFinite ? q : minimo) - minimo) * sc
        }
        func punto(_ i: Int, _ j: Int, _ alto: Bool) -> SIMD3<Double> {
            SIMD3((Double(i) * t.passo - W / 2) * sc, alto ? y(i, j) : 0, (Double(j) * t.passo - D / 2) * sc)
        }
        var m = Maglia()
        for a in 0..<(jj.count - 1) { for b in 0..<(ii.count - 1) {
            let i0 = ii[b], i1 = ii[b + 1], j0 = jj[a], j1 = jj[a + 1]
            m.quadro(punto(i0, j0, true), punto(i1, j0, true), punto(i1, j1, true), punto(i0, j1, true), verso: SIMD3(0, 1, 0))
            m.quadro(punto(i0, j0, false), punto(i1, j0, false), punto(i1, j1, false), punto(i0, j1, false), verso: SIMD3(0, -1, 0))
        } }
        for b in 0..<(ii.count - 1) {                                   // i quattro fianchi, punto per punto (niente giunti a T)
            let i0 = ii[b], i1 = ii[b + 1], j0 = jj.first!, j1 = jj.last!
            m.quadro(punto(i0, j0, false), punto(i1, j0, false), punto(i1, j0, true), punto(i0, j0, true), verso: SIMD3(0, 0, -1))
            m.quadro(punto(i0, j1, false), punto(i1, j1, false), punto(i1, j1, true), punto(i0, j1, true), verso: SIMD3(0, 0, 1))
        }
        for a in 0..<(jj.count - 1) {
            let j0 = jj[a], j1 = jj[a + 1], i0 = ii.first!, i1 = ii.last!
            m.quadro(punto(i0, j0, false), punto(i0, j1, false), punto(i0, j1, true), punto(i0, j0, true), verso: SIMD3(-1, 0, 0))
            m.quadro(punto(i1, j0, false), punto(i1, j1, false), punto(i1, j1, true), punto(i1, j0, true), verso: SIMD3(1, 0, 0))
        }
        let scala = "1:\(Int(k))"
        return m.dati(nome: "Plastico terreno \(scala)",
                      righe: ["LIDAR · PLASTICO TERRENO \(scala)", "\(LidarFormato.n(t.area)) M² · DISLIVELLO \(LidarFormato.cm(t.dislivello).uppercased()) (×1, NON ESAGERATO)"],
                      parla: "Ecco il plastico del terreno, Sir: {L} per {P} millimetri. Scala \(scala.replacingOccurrences(of: ":", with: " a ")), quote vere.")
    }

    // MARK: OGGETTO e TEXTURE → la maglia vera

    static func oggetto(_ o: OggettoScena) -> [String: Any]? {
        var v: [Float] = []
        v.reserveCapacity(o.vertici.count * 3)
        for p in o.vertici { v += [p.x, p.y, p.z] }
        guard let mk = maglia(v, o.indici, scale: [1, 2, 5, 10, 20, 50, 100]) else { return nil }
        let (m, k) = mk
        let cm = { (x: Float) in Int((x * 100).rounded()) }
        let scala = k == 1 ? "1:1" : "1:\(Int(k))"
        return m.dati(nome: k == 1 ? "Oggetto scansionato" : "Oggetto scansionato \(scala)",
                      righe: ["LIDAR · SCANSIONE RICEVUTA", "OGGETTO \(cm(o.largo)) × \(cm(o.profondo)) × \(cm(o.alto)) CM · SCALA \(scala)"],
                      parla: "Mesh generata, Sir: {L} per {P} per {H} millimetri" + (k == 1 ? ", a grandezza vera." : ", in scala \(scala.replacingOccurrences(of: ":", with: " a "))."))
    }

    static func persona(_ url: URL) -> [String: Any]? {
        let s = Lidar3DDati.statua(url)
        guard s.errore == nil, let mk = maglia(s.vertici, s.indici, scale: [10, 20, 50]) else { return nil }
        let (m, k) = mk
        var minY = Float.infinity, maxY = -Float.infinity
        var i = 1
        while i < s.vertici.count { minY = min(minY, s.vertici[i]); maxY = max(maxY, s.vertici[i]); i += 3 }
        let h = Double(maxY - minY)
        return m.dati(nome: "Statuina 1:\(Int(k))",
                      righe: ["LIDAR · MODELLO 3D DELLA PERSONA", "ALTA \(LidarFormato.m(h, 2).uppercased()) · STATUINA 1:\(Int(k))"],
                      parla: "Ecco la statuina, Sir: alta {H} millimetri, scala 1 a \(Int(k)).")
    }

    /// Una maglia di Object Capture o di Oggetto (metri, indici) → millimetri, centrata, base a zero, nella scala più grande che sta
    /// nel piatto (`scale`: 1 = grandezza vera), al massimo ~60.000 triangoli (raggruppando i vertici vicini).
    static func maglia(_ v: [Float], _ idx: [UInt32], scale: [Double]) -> (Maglia, Double)? {
        let nv = v.count / 3
        guard nv >= 3, idx.count >= 3 else { return nil }
        var lo = SIMD3<Double>(repeating: .infinity), hi = SIMD3<Double>(repeating: -.infinity)
        for i in 0..<nv {
            let p = SIMD3(Double(v[i * 3]), Double(v[i * 3 + 1]), Double(v[i * 3 + 2]))
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { continue }
            lo = simd_min(lo, p); hi = simd_max(hi, p)
        }
        let dim = hi - lo
        guard dim.x.isFinite, max(dim.x, dim.y, dim.z) > 0.005 else { return nil }
        let k = scale.first { max(dim.x, dim.y, dim.z) * 1000 / $0 <= latoMassimo } ?? scale.last!
        let sc = 1000 / k, centro = SIMD3((lo.x + hi.x) / 2, lo.y, (lo.z + hi.z) / 2)
        // troppi triangoli: i vertici nella stessa cella diventano uno solo (la maglia resta della stessa forma)
        let triangoli = idx.count / 3
        var mappa = Array(0..<nv)
        var posizioni = (0..<nv).map { SIMD3(Double(v[$0 * 3]), Double(v[$0 * 3 + 1]), Double(v[$0 * 3 + 2])) }
        if triangoli > 60_000 {
            let cella = max(dim.x, dim.y, dim.z) / (220 * (Double(triangoli) > 400_000 ? 0.5 : 1))
            var gruppi: [SIMD3<Int>: Int] = [:], somma: [SIMD3<Double>] = [], conta: [Double] = []
            for i in 0..<nv {
                let c = SIMD3(Int((posizioni[i].x - lo.x) / cella), Int((posizioni[i].y - lo.y) / cella), Int((posizioni[i].z - lo.z) / cella))
                if let g = gruppi[c] { mappa[i] = g; somma[g] += posizioni[i]; conta[g] += 1 }
                else { gruppi[c] = somma.count; mappa[i] = somma.count; somma.append(posizioni[i]); conta.append(1) }
            }
            posizioni = zip(somma, conta).map { $0 / $1 }
        }
        var m = Maglia()
        var visti = Set<SIMD3<Int>>()
        var t = 0
        while t + 2 < idx.count {
            let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2]); t += 3
            guard a < nv, b < nv, c < nv else { continue }
            let A = mappa[a], Bi = mappa[b], C = mappa[c]
            guard A != Bi, Bi != C, A != C else { continue }                // schiacciato dal raggruppamento
            let o = [A, Bi, C].sorted(), chiave = SIMD3(o[0], o[1], o[2])
            guard visti.insert(chiave).inserted else { continue }
            m.triangolo((posizioni[A] - centro) * sc, (posizioni[Bi] - centro) * sc, (posizioni[C] - centro) * sc)
        }
        return m.vuota ? nil : (m, k)
    }

    // MARK: CORPO → la sagoma con le proporzioni vere

    static func corpo(_ p: PosturaScena) -> [String: Any]? {
        var g: [String: Any] = [:]
        for (k, v) in p.giunture where v.x.isFinite && v.y.isFinite && v.z.isFinite { g[k] = [n(Double(v.x)), n(Double(v.y)), n(Double(v.z))] }
        guard g.count >= 6 else { return nil }
        let ossa = [("testa", "collo"), ("collo", "spSx"), ("collo", "spDx"), ("spSx", "goSx"), ("spDx", "goDx"), ("goSx", "maSx"), ("goDx", "maDx"),
                    ("collo", "bac"), ("bac", "anSx"), ("bac", "anDx"), ("anSx", "giSx"), ("anDx", "giDx"), ("giSx", "piSx"), ("giDx", "piDx")]
        let h = Double(p.altezza).isFinite && p.altezza > 0.5 ? Double(p.altezza) : 1.78
        return ["tipo": "corpo", "giunture": g, "ossa": ossa.map { [$0.0, $0.1] }, "altezza": n(h)]
    }
}

/// Triangoli sciolti in millimetri con la normale della faccia, per la geometria «unito» dello Studio.
nonisolated struct Maglia {
    private(set) var pos: [Float] = []
    private(set) var norm: [Float] = []
    var vuota: Bool { pos.isEmpty }

    mutating func triangolo(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) {
        let f = simd_cross(b - a, c - a), l = simd_length(f)
        guard l > 1e-9, l.isFinite else { return }
        let nn = f / l
        for p in [a, b, c] { pos += [Float(p.x), Float(p.y), Float(p.z)]; norm += [Float(nn.x), Float(nn.y), Float(nn.z)] }
    }
    /// Un quadrilatero (a b c d in giro) con la faccia girata verso `verso`.
    mutating func quadro(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ d: SIMD3<Double>, verso: SIMD3<Double>) {
        let giusto = simd_dot(simd_cross(b - a, c - a), verso) >= 0
        if giusto { triangolo(a, b, c); triangolo(a, c, d) } else { triangolo(a, c, b); triangolo(a, d, c) }
    }
    func dati(nome: String, righe: [String], parla: String) -> [String: Any] {
        ["tipo": "maglia", "nome": nome, "righe": righe, "parla": parla, "pos": Lidar3DDati.b64(pos), "norm": Lidar3DDati.b64(norm)]
    }
}
#endif
