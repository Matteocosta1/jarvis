#if os(iOS)
import Foundation
import simd

// MARK: - LiDAR 23 · SETUP: l'allestimento posato sulla pianta della stanza scansionata
// Le misure sono quelle del mockup approvato: palco 5 × 3 m a 40 cm dal muro, console 1,6 × 1,6 m a 40 cm dal palco,
// bar 4,6 × 1,4 m a 30 cm da un altro muro, stand 3 × 3 m con passaggi da 1,2 m, uscite (le porte) libere per 1,5 m davanti.
// Tutto sta dentro il pavimento vero; gli stand riempiono quello che resta (la griglia che ne fa entrare di più).

/// Un rettangolo sulla pianta: centro, asse del lato lungo (unitario), lati; `versoMuro` dice da che parte sta il muro
/// rispetto alla normale (−asse.y, asse.x): +1 o −1 (per il retro dello stand e lo scaffale del bar).
nonisolated struct RettangoloPiano: Sendable {
    var centro: SIMD2<Double>
    var asse: SIMD2<Double>
    var lungo: Double
    var largo: Double
    var versoMuro: Double = -1

    var normale: SIMD2<Double> { SIMD2(-asse.y, asse.x) }
    var angoli: [SIMD2<Double>] {
        let a = asse * (lungo / 2), b = normale * (largo / 2)
        return [centro - a - b, centro + a - b, centro + a + b, centro - a + b]
    }
    func allargato(_ m: Double) -> RettangoloPiano {
        var r = self; r.lungo += 2 * m; r.largo += 2 * m; return r
    }
    var area: Double { lungo * largo }

    /// Si toccano? (assi separatori: i due assi di ognuno)
    func tocca(_ o: RettangoloPiano) -> Bool {
        for ax in [asse, normale, o.asse, o.normale] {
            let p1 = angoli.map { simd_dot($0, ax) }, p2 = o.angoli.map { simd_dot($0, ax) }
            if (p1.max() ?? 0) <= (p2.min() ?? 0) || (p2.max() ?? 0) <= (p1.min() ?? 0) { return false }
        }
        return true
    }
    func contiene(_ q: SIMD2<Double>) -> Bool {
        let d = q - centro
        return abs(simd_dot(d, asse)) < lungo / 2 - 1e-6 && abs(simd_dot(d, normale)) < largo / 2 - 1e-6
    }
}

nonisolated struct Allestimento: Sendable {
    var palco: RettangoloPiano?
    var console: RettangoloPiano?
    var bar: RettangoloPiano?
    var stand: [RettangoloPiano] = []
    var passaggi: [(SIMD2<Double>, SIMD2<Double>)] = []
    var uscite: [Double] = []                          // larghezza di ogni porta, metri
    var areaPavimento: Double = 0

    static let passaggio = 1.2

    /// La superficie che resta libera per le persone.
    var areaLibera: Double {
        max(0, areaPavimento - [palco, console, bar].compactMap { $0?.area }.reduce(0, +) - stand.reduce(0) { $0 + $1.area })
    }
    var mancanti: [String] { [palco == nil ? "palco" : nil, console == nil ? "console" : nil, bar == nil ? "bar" : nil].compactMap { $0 } }

    // MARK: Il calcolo

    static func calcola(_ s: StanzaScena) -> Allestimento {
        var out = Allestimento()
        var poli = s.pavimento
        if poli.count < 3 { poli = GeometriaPiana.inviluppo(s.pareti.flatMap { [SIMD2($0.ax, $0.az), SIMD2($0.bx, $0.bz)] }) }
        guard poli.count >= 3 else { return out }
        out.areaPavimento = GeometriaPiana.area(poli)
        out.uscite = s.porte.map(\.lunghezza)
        let pareti = s.pareti.filter { $0.lunghezza >= 1 }

        func dentroPavimento(_ r: RettangoloPiano) -> Bool {
            guard r.angoli.allSatisfy({ GeometriaPiana.dentro($0, poli) }), GeometriaPiana.dentro(r.centro, poli) else { return false }
            return !poli.contains { r.contiene($0) }                // nessun angolo della stanza (le L) dentro il rettangolo
        }
        // la normale di una parete verso l'interno della stanza
        func dentroDi(_ w: TrattoPianta) -> (a: SIMD2<Double>, u: SIMD2<Double>, n: SIMD2<Double>, l: Double) {
            let a = SIMD2(w.ax, w.az), b = SIMD2(w.bx, w.bz), l = max(simd_distance(a, b), 0.001), u = (b - a) / l
            var n = SIMD2(-u.y, u.x)
            if !GeometriaPiana.dentro((a + b) / 2 + n * 0.3, poli) { n = -n }
            return (a, u, n, l)
        }
        // davanti a ogni porta 1,5 m liberi (largo quanto la porta più 60 cm)
        let zonePorte: [RettangoloPiano] = s.porte.map { p in
            let d = dentroDi(p), m = d.a + d.u * (d.l / 2)
            return RettangoloPiano(centro: m + d.n * 0.75, asse: d.u, lungo: d.l + 0.6, largo: 1.5)
        }
        func libero(_ r: RettangoloPiano, da altri: [RettangoloPiano], margine: Double) -> Bool {
            let g = r.allargato(margine)
            return !altri.contains { g.tocca($0) }
        }
        func verso(_ n: SIMD2<Double>, _ r: RettangoloPiano) -> Double { simd_dot(-n, r.normale) > 0 ? 1 : -1 }   // il muro sta da −n
        func scorrendo(_ l: Double, _ passo: Double = 0.5) -> [Double] {
            var o: [Double] = [0]; var k = passo
            while k <= l / 2 { o += [k, -k]; k += passo }
            return o
        }

        // 1. il palco: 5 × 3 m a 40 cm dal muro più lungo senza porte (o dal più lungo)
        let ordinate = pareti.sorted { a, b in
            let pa = s.porte.contains { $0.vicino(a) }, pb = s.porte.contains { $0.vicino(b) }
            return pa != pb ? !pa : a.lunghezza > b.lunghezza
        }
        var muroPalco: TrattoPianta?
        cerca: for w in ordinate {
            let d = dentroDi(w), lungo = min(5.0, d.l - 0.4)
            guard lungo >= 3 else { continue }
            for off in scorrendo(d.l - lungo) {
                var r = RettangoloPiano(centro: d.a + d.u * (d.l / 2 + off) + d.n * (0.4 + 1.5), asse: d.u, lungo: lungo, largo: 3)
                r.versoMuro = verso(d.n, r)
                if dentroPavimento(r), libero(r, da: zonePorte, margine: 0) { out.palco = r; muroPalco = w; break cerca }
            }
        }
        // 2. la console davanti al palco, a 40 cm
        if let p = out.palco, let w = muroPalco {
            let d = dentroDi(w)
            var c = RettangoloPiano(centro: p.centro + d.n * (1.5 + 0.4 + 0.8), asse: d.u, lungo: 1.6, largo: 1.6)
            c.versoMuro = verso(d.n, c)
            if dentroPavimento(c), libero(c, da: zonePorte, margine: 0) { out.console = c }
        }
        // 3. il bar: 4,6 × 1,4 m a 30 cm dal muro più lontano dal palco
        let occupati0 = [out.palco, out.console].compactMap { $0 }
        let perBar = pareti.filter { w in muroPalco.map { m in !(w.ax == m.ax && w.az == m.az && w.bx == m.bx && w.bz == m.bz) } ?? true }
            .sorted { a, b in
                guard let p = out.palco else { return a.lunghezza > b.lunghezza }
                let ma = SIMD2((a.ax + a.bx) / 2, (a.az + a.bz) / 2), mb = SIMD2((b.ax + b.bx) / 2, (b.az + b.bz) / 2)
                return simd_distance(ma, p.centro) > simd_distance(mb, p.centro)
            }
        cercaBar: for w in perBar {
            let d = dentroDi(w), lungo = min(4.6, d.l - 0.2)
            guard lungo >= 2.5 else { continue }
            for off in scorrendo(d.l - lungo) {
                var r = RettangoloPiano(centro: d.a + d.u * (d.l / 2 + off) + d.n * (0.3 + 0.7), asse: d.u, lungo: lungo, largo: 1.4)
                r.versoMuro = verso(d.n, r)
                if dentroPavimento(r), libero(r, da: zonePorte, margine: 0), libero(r, da: occupati0, margine: passaggio) { out.bar = r; break cercaBar }
            }
        }
        // 4. gli stand 3 × 3 m: la griglia (passo 4,2 m = 3 + 1,2 di passaggio) che ne fa entrare di più
        let e1 = out.palco?.asse ?? (pareti.max { $0.lunghezza < $1.lunghezza }.map { simd_normalize(SIMD2($0.bx - $0.ax, $0.bz - $0.az)) } ?? SIMD2(1, 0))
        let e2 = SIMD2(-e1.y, e1.x)
        let pr1 = poli.map { simd_dot($0, e1) }, pr2 = poli.map { simd_dot($0, e2) }
        guard let a1 = pr1.min(), let b1 = pr1.max(), let a2 = pr2.min(), let b2 = pr2.max() else { return out }
        let passo = 3 + passaggio
        let palcoEConsole = [out.palco, out.console].compactMap { $0 }
        let barra = [out.bar].compactMap { $0 }
        var meglio: [(RettangoloPiano, Int, Int)] = []
        for ox in stride(from: 0.0, to: passo, by: 0.6) { for oy in stride(from: 0.0, to: passo, by: 0.6) {
            var trovati: [(RettangoloPiano, Int, Int)] = []
            var i = 0, x = a1 + ox + 1.5
            while x <= b1 {
                var j = 0, y = a2 + oy + 1.5
                while y <= b2 {
                    let r = RettangoloPiano(centro: e1 * x + e2 * y, asse: e1, lungo: 3, largo: 3)
                    if dentroPavimento(r.allargato(0.6)), libero(r, da: zonePorte, margine: 0.6),
                       libero(r, da: palcoEConsole, margine: 1.6), libero(r, da: barra, margine: passaggio) {
                        trovati.append((r, i, j))
                    }
                    y += passo; j += 1
                }
                x += passo; i += 1
            }
            if trovati.count > meglio.count { meglio = trovati }
        } }
        // il retro di ogni stand dalla parte opposta al centro della griglia: i fronti guardano il passaggio
        if !meglio.isEmpty {
            let g = meglio.reduce(SIMD2<Double>(0, 0)) { $0 + $1.0.centro } / Double(meglio.count)
            let cg = simd_dot(g, e2)
            out.stand = meglio.map { r0 in
                var r = r0.0
                let lato = simd_dot(r.centro, e2) - cg
                r.versoMuro = lato >= 0 ? (simd_dot(e2, r.normale) > 0 ? 1 : -1) : (simd_dot(e2, r.normale) > 0 ? -1 : 1)
                if abs(lato) < 0.01, let c = out.palco?.centro { r.versoMuro = simd_dot(r.centro - c, r.normale) > 0 ? 1 : -1 }
                return r
            }
            // i passaggi: a metà tra le file e tra le colonne di stand
            let righe = Set(meglio.map { $0.2 }).sorted(), colonne = Set(meglio.map { $0.1 }).sorted()
            for (j0, j1) in zip(righe, righe.dropFirst()) where j1 == j0 + 1 {
                let fila = meglio.filter { $0.2 == j0 || $0.2 == j1 }
                let xs = fila.map { simd_dot($0.0.centro, e1) }, y = (fila.filter { $0.2 == j0 }.map { simd_dot($0.0.centro, e2) }.first ?? 0) + passo / 2
                if let x0 = xs.min(), let x1 = xs.max() { out.passaggi.append((e1 * (x0 - 2.1) + e2 * y, e1 * (x1 + 2.1) + e2 * y)) }
            }
            for (i0, i1) in zip(colonne, colonne.dropFirst()) where i1 == i0 + 1 {
                let col = meglio.filter { $0.1 == i0 || $0.1 == i1 }
                let ys = col.map { simd_dot($0.0.centro, e2) }, x = (col.filter { $0.1 == i0 }.map { simd_dot($0.0.centro, e1) }.first ?? 0) + passo / 2
                if let y0 = ys.min(), let y1 = ys.max() { out.passaggi.append((e1 * x + e2 * (y0 - 2.1), e1 * x + e2 * (y1 + 2.1))) }
            }
        }
        return out
    }

    // MARK: I testi (come le righe del mockup)

    /// «2 · 1,6 m e 1,8 m»
    var testoUscite: String {
        guard !uscite.isEmpty else { return "nessuna porta trovata" }
        let l = uscite.map { LidarFormato.m($0) }
        let elenco = l.count == 1 ? l[0] : l.dropLast().joined(separator: ", ") + " e " + (l.last ?? "")
        return "\(uscite.count) · \(elenco)"
    }
    /// «posati», oppure cosa non è entrato.
    var testoPosati: String {
        let m = mancanti
        guard !m.isEmpty else { return "posati" }
        if m.count == 1 { return "non c'è spazio per " + (m[0] == "console" ? "la console" : "il " + m[0]) }
        return "non c'è spazio per " + m.dropLast().joined(separator: ", ") + " e " + (m.last ?? "")
    }
}

extension TrattoPianta {
    /// Una porta sta su questa parete? (entrambi i capi a meno di 30 cm dalla sua linea, e dentro la sua lunghezza)
    nonisolated func vicino(_ w: TrattoPianta) -> Bool {
        let a = SIMD2(w.ax, w.az), b = SIMD2(w.bx, w.bz), l = max(simd_distance(a, b), 0.001), u = (b - a) / l, n = SIMD2(-u.y, u.x)
        for q in [SIMD2(ax, az), SIMD2(bx, bz)] {
            let d = q - a
            if abs(simd_dot(d, n)) > 0.3 { return false }
            let t = simd_dot(d, u)
            if t < -0.3 || t > l + 0.3 { return false }
        }
        return true
    }
}
#endif
