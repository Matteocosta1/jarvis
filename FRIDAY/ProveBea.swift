import Foundation
import SwiftUI
import UIKit                // UIImage (c'è anche sull'orologio): la foto di Bea in ologramma
import CoreGraphics
#if os(iOS)
import CoreImage            // l'alone attorno alla foto del RITRATTO, fatto una volta per foto
#endif

// MARK: - BEA · le tre prove (mockup v270): VETRO, SCUDO e RITRATTO (il signore, 5 nov sera: «togli punti e linee», «più grandi,
// proporzionati ai due lati della pagina e centrati», «mettine un terzo come abbiamo su FRIDAY in armadio»)
// La foto scelta, già in luce ciano (FotoBea: la persona la ritaglia Vision e la foto resta sul telefono; sul polso arriva in piccolo,
// su nero). Senza foto: il busto di luce. Le date e la promessa sono quelle della sezione.

/// Bea come il mockup: la foto in luce e le cose da non dimenticare (le prime due date e la prima promessa).
struct BeaOlo {
    struct Tag { let data: Bool; let titolo: String; let sotto: String }
    var foto: UIImage?
    var tags: [Tag] = []

    /// Il titolo di un'etichetta: in maiuscolo, al massimo 18 lettere.
    static func corto(_ s: String) -> String {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return u.count > 18 ? String(u.prefix(17)) + "…" : u
    }

    /// Fra quanti giorni, come il mockup: OGGI, DOMANI, FRA 41 GIORNI.
    static func fra(_ giorni: Int) -> String { giorni <= 0 ? "OGGI" : giorni == 1 ? "DOMANI" : "FRA \(giorni) GIORNI" }
}

/// I campioni della foto (luce e trasparenza su una griglia), fatti una volta per foto: campionaBea del mockup.
struct CampioniBea {
    let colonne: Int
    let righe: Int
    let L: [Double]
    let A: [Double]
    let rapporto: Double

    /// `suNero`: sul polso la foto arriva in JPEG su nero (senza trasparenza): lì la luce fa anche da trasparenza.
    init?(_ im: CGImage, colonne: Int, suNero: Bool) {
        guard im.width > 0, im.height > 0, colonne > 1 else { return nil }
        let righe = max(8, Int((Double(colonne) * Double(im.height) / Double(im.width)).rounded()))
        let n = colonne * righe
        guard let spazio = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var px = [UInt8](repeating: 0, count: n * 4)
        let fatto: Bool = px.withUnsafeMutableBytes { b in
            guard let tela = CGContext(data: b.baseAddress, width: colonne, height: righe, bitsPerComponent: 8, bytesPerRow: colonne * 4,
                                       space: spazio, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            tela.interpolationQuality = .medium
            tela.draw(im, in: CGRect(x: 0, y: 0, width: colonne, height: righe))
            return true
        }
        guard fatto else { return nil }
        var L = [Double](repeating: 0, count: n), A = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let lum = (0.2126 * Double(px[i * 4]) + 0.7152 * Double(px[i * 4 + 1]) + 0.0722 * Double(px[i * 4 + 2])) / 255
            if suNero {
                A[i] = min(1, max(0, (lum - 0.03) / 0.12))
                L[i] = min(1, lum / 0.864)                                // 0,864: la luce del ciano pieno
            } else {
                let a = Double(px[i * 4 + 3]) / 255
                A[i] = a
                L[i] = a > 0.004 ? min(1, lum / a) : 0                    // premoltiplicato: la luce vera è divisa per la trasparenza
            }
        }
        // [1 2 1] in verticale e in orizzontale, due volte (come il mockup)
        var T = [Double](repeating: 0, count: n)
        for _ in 0..<2 {
            for j in 0..<righe {
                for i in 0..<colonne {
                    let k = j * colonne + i, su = j > 0 ? k - colonne : k, giu = j < righe - 1 ? k + colonne : k
                    T[k] = (L[su] + 2 * L[k] + L[giu]) / 4
                }
            }
            for j in 0..<righe {
                for i in 0..<colonne {
                    let k = j * colonne + i, sx = i > 0 ? k - 1 : k, dx = i < colonne - 1 ? k + 1 : k
                    L[k] = (T[sx] + 2 * T[k] + T[dx]) / 4
                }
            }
        }
        self.colonne = colonne
        self.righe = righe
        self.L = L
        self.A = A
        self.rapporto = Double(im.width) / Double(im.height)
    }
}

/// Le tre prove di Bea.
final class ProveBea {
    #if os(watchOS)
    private static let suNero = true
    #else
    private static let suNero = false
    #endif

    private var foto: UIImage?
    private var cache: [Int: CampioniBea] = [:]

    func crea(_ k: Int) {}

    func disegna(_ k: Int, _ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, piccolo: Bool) {
        switch k {
        case 1: scudo(&gc, W, H, t, M, B, piccolo)
        case 2: ritratto(&gc, W, H, t, M, B, piccolo)
        default: vetro(&gc, W, H, t, M, B, piccolo)
        }
    }

    /// I campioni della foto per `colonne` colonne (fatti una volta; una foto nuova li rifà).
    private func campioni(_ im: UIImage, _ colonne: Int) -> CampioniBea? {
        if foto !== im { foto = im; cache = [:] }
        if let c = cache[colonne] { return c }
        guard let cg = im.cgImage, let c = CampioniBea(cg, colonne: colonne, suNero: ProveBea.suNero) else { return nil }
        cache[colonne] = c
        return c
    }

    /// bustoBeaOlo: il busto di luce (senza foto): mezza larghezza e mezza profondità all'altezza z (0 = petto, 1,22 = cima della
    /// testa). Il petto si allarga verso le spalle, le spalle scendono tonde fino al collo, poi la testa (un ovale).
    private static func busto(_ z: Double) -> (x: Double, y: Double) {
        if z > 0.64 {
            let f = max(0, 1 - pow((z - 0.93) / 0.28, 2)).squareRoot()
            return (x: max(z < 0.8 ? 0.13 : 0, 0.2 * f), y: max(z < 0.8 ? 0.12 : 0, 0.23 * f))
        }
        if z > 0.44 { return (x: 0.13, y: 0.12) }
        if z > 0.27 {
            let f = max(0, cos((z - 0.27) / 0.17 * .pi / 2))
            return (x: 0.13 + 0.43 * pow(f, 0.5), y: 0.12 + 0.11 * pow(f, 0.8))
        }
        return (x: 0.5 + 0.06 * z / 0.27, y: 0.23)
    }

    /// scenaBea: il proiettore sul pavimento e il cono di luce. Restituisce la base.
    private func scena(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ piccolo: Bool) -> Double {
        let cx = W / 2, base = piccolo ? H - 3 : H - 14, rx = piccolo ? W * 0.3 : min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: piccolo ? 20 : 48)
        Olo.cono(&gc, cx, base, rx, piccolo ? 2 : 20, rx * 1.25, a: 0.07)
        return base
    }

    // MARK: BE1 · VETRO — Bea su una lastra di vetro sospesa sopra il proiettore (la foto in luce, il riflesso che la attraversa, le staffe
    // agli angoli); attorno girano le cose da non dimenticare: le date e la promessa. Toccata una, il riquadro; toccata la lastra, la foto.

    private static let lastraId = 100

    private func vetro(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, _ piccolo: Bool) {
        let base = scena(&gc, W, H, t, piccolo), cx = W / 2
        let sz = piccolo ? min(W * 0.5, H * 0.5) : min(W * 0.56, (H - 50) / 1.75), cy = base - (piccolo ? 3 : 8)   // v270: grande
        let ang = 0.3 * sin(t * 0.27) + M.giro * 0.7, al = 0.08
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let rapporto = B.foto.map { Double($0.size.width / max(1, $0.size.height)) } ?? 0.78
        let hh = 1.55, hw = hh * rapporto / 2, z0 = 0.12, apre = OP.lis(t / 0.8)
        let TL = P(-hw * apre, 0, z0 + hh), TR = P(hw * apre, 0, z0 + hh), BL = P(-hw * apre, 0, z0), BR = P(hw * apre, 0, z0)
        let lastra = OP.poligono([TL, TR, BR, BL])
        do {                                                              // dentro la lastra
            var g = gc
            g.fill(lastra, with: .color(OP.s(0.035)))
            g.clip(to: lastra)
            if let im = B.foto {                                          // la foto sulla lastra: la trasformazione dai tre angoli
                var f = g
                f.opacity = 0.86 + 0.14 * (0.5 + 0.5 * sin(t * 2.1))
                let w = max(1, Double(im.size.width)), h = max(1, Double(im.size.height))
                f.concatenate(CGAffineTransform(a: (TR.x - TL.x) / w, b: (TR.y - TL.y) / w, c: (BL.x - TL.x) / h, d: (BL.y - TL.y) / h, tx: TL.x, ty: TL.y))
                f.draw(Image(uiImage: im), in: CGRect(x: 0, y: 0, width: w, height: h))
            } else {                                                      // senza foto: il busto di luce, piccolo, che gira
                var F = FasciOlo(4)
                let cxl = (TL.x + BR.x) / 2, cyl = BL.y - 6, s2 = (BL.y - TL.y) * 0.62
                for k in 0...22 {
                    let z = Double(k) / 22 * 1.22, b = ProveBea.busto(z)
                    var q: P3?
                    for s in 0...40 {
                        let a = Double(s) / 40 * OP.due, o = Olo.proietta(cos(a) * b.x, sin(a) * b.y, z, t * 0.4, 0.12, cxl, cyl, s2)
                        if let q { F.metti(o.z + q.z < 0 ? 2 : 0, q, o) }
                        q = o
                    }
                }
                F.linee(&g, colore: { OP.c(0.12 + 0.18 * Double($0)) }, spessore: { 0.7 + Double($0) * 0.1 })
            }
            // il riflesso che attraversa il vetro in diagonale
            let u = (t * 0.3).truncatingRemainder(dividingBy: 1.6) - 0.3, gx = TL.x + (BR.x - TL.x) * u, gy = TL.y + (BR.y - TL.y) * u
            let riflesso = Color(red: 223 / 255, green: 250 / 255, blue: 1)
            let fermate: [Gradient.Stop] = [Gradient.Stop(color: riflesso.opacity(0), location: 0), Gradient.Stop(color: riflesso.opacity(0.14), location: 0.5),
                                            Gradient.Stop(color: riflesso.opacity(0), location: 1)]
            g.fill(Path(CGRect(x: min(TL.x, BL.x) - 10, y: TL.y - 10, width: abs(TR.x - TL.x) + 20, height: BL.y - TL.y + 20)),
                   with: .linearGradient(Gradient(stops: fermate), startPoint: CGPoint(x: gx - 30, y: gy - 30), endPoint: CGPoint(x: gx + 30, y: gy + 30)))
        }
        // il bordo e le staffe agli angoli
        gc.stroke(lastra, with: .color(OP.s(0.5)), lineWidth: 1)
        var staffe = Path()
        let st = piccolo ? 4.0 : 9.0
        let angoli: [(p: P3, a: P3, b: P3)] = [(TL, TR, BL), (TR, TL, BR), (BL, BR, TL), (BR, BL, TR)]
        for q in angoli {
            let ux = q.a.x - q.p.x, uy = q.a.y - q.p.y, lu = max(1e-6, hypot(ux, uy))
            let vx = q.b.x - q.p.x, vy = q.b.y - q.p.y, lv = max(1e-6, hypot(vx, vy))
            staffe.move(to: CGPoint(x: q.p.x + ux / lu * st, y: q.p.y + uy / lu * st))
            staffe.addLine(to: CGPoint(x: q.p.x, y: q.p.y))
            staffe.addLine(to: CGPoint(x: q.p.x + vx / lv * st, y: q.p.y + vy / lv * st))
        }
        gc.stroke(staffe, with: .color(OP.b(0.95)), lineWidth: piccolo ? 1 : 1.5)
        guard !piccolo else { return }
        M.zona((TL.x + BR.x) / 2, (TL.y + BR.y) / 2, 30, ProveBea.lastraId)
        if B.foto == nil { OP.scritta(&gc, "SCELGA UNA FOTO", (TL.x + TR.x) / 2, TL.y - 6, 8, 700, OP.c(0.9)) }
        // le cose da non dimenticare, in orbita
        var posti: [P3] = []
        for (k, tag) in B.tags.enumerated() {
            let a = t * 0.32 + Double(k) * 2.094, p = P(cos(a) * (hw + 0.3), sin(a) * 0.42, z0 + hh * (0.35 + 0.22 * Double(k)))
            let dav = p.z < 0, scelta = M.scelta == k, al2 = dav ? 1.0 : 0.4
            let tw = max(OP.larghezza(gc, tag.titolo, 6.5, 700), OP.larghezza(gc, tag.sotto, 6, 600))
            // v270: l'etichetta resta sempre dentro la tela (4 punti dal bordo), col testo al suo centro
            let w = max(66, (tw + 12).rounded(.up)), h = 22.0, bx = max(4, min(W - w - 4, p.x - w / 2)), by = p.y - h / 2, mx = bx + w / 2
            var filo = Path()
            Olo.linea(&filo, p.x, p.y, dav ? (p.x < cx ? BL.x : BR.x) : p.x, p.y)
            gc.stroke(filo, with: .color(OP.s(0.35 * al2)), lineWidth: 1)
            gc.fill(Path(CGRect(x: bx, y: by, width: w, height: h)), with: .color(Color(red: 2 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.75 * al2)))
            var tacche = Path()
            let spigoli: [(x: Double, y: Double, dx: Double, dy: Double)] = [(bx, by, 1, 1), (bx + w, by, -1, 1), (bx, by + h, 1, -1), (bx + w, by + h, -1, -1)]
            for s in spigoli {
                tacche.move(to: CGPoint(x: s.x, y: s.y + s.dy * 5))
                tacche.addLine(to: CGPoint(x: s.x, y: s.y))
                tacche.addLine(to: CGPoint(x: s.x + s.dx * 5, y: s.y))
            }
            gc.stroke(tacche, with: .color(scelta ? OP.b(1) : OP.c(0.75 * al2)), lineWidth: 1)
            OP.scritta(&gc, tag.titolo, mx, p.y - 1, 6.5, 700, OP.b(0.95 * al2))
            OP.scritta(&gc, tag.sotto, mx, p.y + 8, 6, 600, tag.data && k == 0 ? OP.b(0.95 * al2) : OP.c(0.8 * al2))
            if dav { M.zona(mx, p.y, 24, k) }
            posti.append(P3(mx, p.y, p.z))
        }
        OP.scritta(&gc, "BEA", 10, 14, 8, 600, OP.c(0.85), .leading)
        if let k = M.scelta, k < B.tags.count, k < posti.count {
            let tag = B.tags[k], p = posti[k]
            OP.riquadro(&gc, W, H, p.x, p.y, [tag.titolo, tag.sotto, tag.data ? "JARVIS TE LO RICORDA PRIMA" : "SEGNALA «FATTO» QUANDO C'È"],
                        t - M.sceltaT, codice: tag.data ? "DATA" : "PROMESSA")
        } else if M.scelta == ProveBea.lastraId {
            OP.riquadro(&gc, W, H, (TL.x + TR.x) / 2, TL.y + 20,
                        ["BEA", B.foto != nil ? "LA FOTO SCELTA, IN LUCE" : "TOCCHI FOTO PER SCEGLIERLA", "RESTA SOLO SUL TELEFONO"],
                        t - M.sceltaT, codice: "OLOGRAMMA")
        }
    }

    // MARK: BE2 · SCUDO (v266, il signore 5 nov 18:31: «anche Bea sarebbe carino che ci fosse qualcosa che sa di amore e protezione»)
    // — Bea in punti di luce dentro una cupola a esagoni: la protezione. Il cuore le batte nel petto (due colpi, come un cuore vero) e a
    // ogni battito parte un'onda a forma di cuore che si allarga e accende gli esagoni che tocca: l'amore. Da fuori arrivano scintille
    // che rimbalzano sulla cupola con un lampo. Toccato il cuore, il riquadro. Uguale al mockup v266 (olo_extra/scudo.js).

    private static let cuoreId = 101
    private static let cuorePetto = P3(0, 0, 0.5)

    /// La curva del cuore (x fra −1 e 1, y in su).
    private static func cuore(_ u: Double) -> (x: Double, y: Double) {
        (x: pow(sin(u), 3), y: (13 * cos(u) - 5 * cos(2 * u) - 2 * cos(3 * u) - cos(4 * u)) / 16)
    }

    private func scudo(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, _ piccolo: Bool) {
        let base = scena(&gc, W, H, t, piccolo), cx = W / 2
        let sz = piccolo ? min(W * 0.42, H * 0.4) : min(W * 0.4, (H - 44) / 1.9), cy = piccolo ? base - 2 : base - 6   // v270: grande
        let ang = 0.4 * sin(t * 0.25) + M.giro, al = 0.16, nasce = OP.lis(t / 1.2), C0 = ProveBea.cuorePetto
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        let Rh = 1.0, Rz = 1.75                                                    // la cupola: mezzo ellissoide attorno a lei
        let batte = 1.15, u = t.truncatingRemainder(dividingBy: batte) / batte
        let colpo = exp(-pow(u / 0.05, 2)) + 0.6 * exp(-pow((u - 0.2) / 0.05, 2))
        let onda = u * 2.6                                                         // il raggio dell'onda, dal petto in fuori
        // Bea, in punti di luce; il petto si accende a ogni battito
        var G = PuntiOlo(6)
        if let im = B.foto, let C = campioni(im, piccolo ? 26 : 64) {
            let hh = 1.4, ww = hh * C.rapporto
            for j in 0..<C.righe {
                let Z = (1 - Double(j) / Double(C.righe)) * hh
                if Z > hh * nasce + 0.02 { continue }
                for i in 0..<C.colonne {
                    let k = j * C.colonne + i, a = C.A[k]
                    if a < 0.14 { continue }
                    let L = C.L[k], X = (Double(i) / Double(C.colonne) - 0.5) * ww
                    let petto = exp(-(pow(X / 0.25, 2) + pow((Z - C0.z) / 0.2, 2))) * colpo
                    let o = P(X, -(L - 0.45) * 0.4 * nasce, Z)
                    G.metti(Int(((a * (0.25 + 0.7 * L) + 0.8 * petto) * 5).rounded()), o.x, o.y, (1 + 0.8 * L + petto) * (piccolo ? 0.55 : 0.9))
                }
            }
        } else {
            for k in 0...40 {
                let z = Double(k) / 40 * 1.22, b = ProveBea.busto(z), giro = max(10, Int((48 * b.x).rounded()))
                for s in 0..<giro {
                    let a = Double(s) / Double(giro) * OP.due + Double(k) * 0.17
                    let o = Olo.proietta(cos(a) * b.x, sin(a) * b.y, z * 1.12, ang, al, cx, cy, sz * 1.05)
                    let petto = exp(-pow((z * 1.12 - C0.z) / 0.2, 2)) * colpo * (o.z < 0 ? 1 : 0.3)
                    G.metti(Int((((o.z < 0 ? 0.6 : 0.22) + 0.8 * petto) * 5).rounded()), o.x, o.y, (1.2 + petto) * (piccolo ? 0.55 : 1))
                }
            }
        }
        G.disegna(&gc, colore: { $0 >= 4 ? OP.b(0.5 + 0.12 * Double($0)) : OP.c(0.12 + 0.16 * Double($0)) })
        // la cupola a esagoni: dietro tenue, davanti più chiara; l'onda del cuore la accende passando
        var F = FasciOlo(7)
        let righe = piccolo ? 5 : 8, db = (Double.pi / 2) / (Double(righe) + 0.3), alza = OP.lis((t - 0.5) / 1.0)
        var luci = Path()
        for j in 0..<righe {
            let b = (Double(j) + 0.5) * db
            if b > Double.pi / 2 * alza + 0.05 { continue }
            let n = max(6, Int(((piccolo ? 12 : 22) * cos(b)).rounded())), da = Double.pi / Double(n)
            for i in 0..<n {
                let a = (Double(i) + 0.5 * Double(j % 2)) / Double(n) * OP.due
                let ch = P3(Rh * cos(b) * cos(a), Rh * cos(b) * sin(a), Rz * sin(b))
                let dd = ch - C0, d = (dd * dd).sum().squareRoot()
                let luce = exp(-pow((d - onda) / 0.16, 2)) * (1 - u)
                let c = P(ch.x, ch.y, ch.z), dav = c.z < 0
                let g = min(6, (dav ? 2 : 0) + Int((luce * 4.5).rounded()))
                var q: P3?
                for v in 0...6 {
                    let th = Double(v % 6) * 1.0472 + 0.5236, aa = a + da * 0.92 * cos(th), bb = b + db * 0.6 * sin(th)
                    let p = P(Rh * cos(bb) * cos(aa), Rh * cos(bb) * sin(aa), Rz * max(0, sin(bb)))
                    if let q { F.metti(g, q, p) }
                    q = p
                }
                if luce > 0.35 && dav && !piccolo {
                    let r = 3 + 4 * luce
                    luci.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                }
            }
        }
        if !luci.isEmpty { gc.fill(luci, with: .color(OP.s(0.1))) }
        // l'orlo della cupola, a terra
        var q: P3?
        for i in 0...64 {
            let a = Double(i) / 64 * OP.due, p = P(Rh * cos(a), Rh * sin(a), 0)
            if let q { F.metti(p.z + q.z < 0 ? 4 : 1, q, p) }
            q = p
        }
        // le scintille da fuori: arrivano, sbattono sulla cupola con un lampo, rimbalzano via
        let scintille = piccolo ? 3 : 6
        var lampi: [(p: P3, l: Double)] = []
        let dir = { (a: Double, b: Double) -> P3 in P3(Rh * cos(b) * cos(a), Rh * cos(b) * sin(a), Rz * sin(b)) }
        for k in 0..<scintille {
            let per = 2.6 + 0.37 * Double(k), s = (t + Double(k) * 1.13).truncatingRemainder(dividingBy: per) / per
            let a0 = Double(k) * 2.39 + 0.6, b0 = 0.25 + 0.18 * Double((k * 7) % 4)
            let via = { (ss: Double) -> P3 in
                if ss < 0.55 { return dir(a0, b0) * (2.5 - 1.5 * ss / 0.55) }
                return dir(a0 + 0.5, b0 + 0.35) * (1 + 1.4 * (ss - 0.55) / 0.45)
            }
            let vis = s < 0.55 ? min(1, s * 6) : max(0, 1 - (s - 0.55) / 0.45)
            let v1 = via(s), v0 = via(max(0, s - 0.04)), p1 = P(v1.x, v1.y, v1.z), p0 = P(v0.x, v0.y, v0.z)
            var scia = Path()
            scia.move(to: CGPoint(x: p0.x, y: p0.y)); scia.addLine(to: CGPoint(x: p1.x, y: p1.y))
            gc.stroke(scia, with: .color(OP.b(0.85 * vis)), style: Olo.tratto(piccolo ? 0.6 : 1.1))
            let lampo = exp(-pow((s - 0.55) / 0.035, 2))
            if lampo > 0.05 { let d0 = dir(a0, b0); lampi.append((p: P(d0.x, d0.y, d0.z), l: lampo)) }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.9) : $0 == 4 ? OP.b(0.6) : OP.c(0.06 + 0.13 * Double($0)) },
                spessore: { piccolo ? 0.4 + Double($0) * 0.07 : 0.6 + Double($0) * 0.11 }, alone: { $0 >= 4 && !piccolo ? OP.s(0.07) : nil })
        for (p, l) in lampi {
            OP.alone(&gc, p.x, p.y, piccolo ? 5 : 12, 0.9 * l, bianco: true)
            if !piccolo {
                let r = 6 + 10 * (1 - l)
                gc.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(OP.b(0.8 * l)), style: Olo.tratto(1))
            }
        }
        // il cuore nel petto (batte) e l'onda a forma di cuore che parte a ogni battito
        let cp = P(C0.x, C0.y, C0.z), sc = piccolo ? 0.45 : 1.0
        let tracciaCuore = { (s: Double) -> Path in
            var h = Path()
            for i in 0...40 {
                let c = ProveBea.cuore(Double(i) / 40 * OP.due), pt = CGPoint(x: cp.x + c.x * s, y: cp.y - c.y * s)
                if i == 0 { h.move(to: pt) } else { h.addLine(to: pt) }
            }
            h.closeSubpath()
            return h
        }
        let piccoloCuore = tracciaCuore((8 + 3 * colpo) * sc)
        gc.fill(piccoloCuore, with: .color(OP.s(0.12 + 0.25 * colpo)))
        gc.stroke(piccoloCuore, with: .color(OP.b(0.75 + 0.25 * colpo)), style: Olo.tratto(piccolo ? 0.8 : 1.4))
        gc.stroke(tracciaCuore((10 + onda * sz * 0.55) * sc), with: .color(OP.b(0.6 * pow(1 - u, 1.6))), style: Olo.tratto(piccolo ? 0.6 : 1))
        OP.alone(&gc, cp.x, cp.y, (piccolo ? 6 : 16) + 6 * colpo, 0.35 + 0.45 * colpo, bianco: true)
        guard !piccolo else { return }
        M.zona(cp.x, cp.y, 26, ProveBea.cuoreId)
        if B.foto == nil { OP.scritta(&gc, "SCELGA UNA FOTO", cx, 30, 8, 700, OP.c(0.9)) }
        OP.scritta(&gc, "BEA · SCUDO", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, "PROTEZIONE · ATTIVA", 10, 30, 8, 700, OP.b(0.95), .leading)   // v270: sotto il titolo, lontano da FOTO
        if M.scelta == ProveBea.cuoreId {
            var righe = ["BEA", "SEMPRE AL SICURO"]
            if let tag = B.tags.first { righe.append("\(tag.titolo) \(tag.sotto)") }
            OP.riquadro(&gc, W, H, cp.x, cp.y, righe, t - M.sceltaT, codice: "CUORE")
        }
    }

    // MARK: BE3 · RITRATTO (v270) — come l'Armadio di FRIDAY: la sua foto vera, staccata dallo sfondo e fatta luce, in piedi sul
    // proiettore e grande quanto la tela. Nasce dal basso con la riga di luce, galleggia appena, una scansione la risale ogni 3 secondi
    // e ogni tanto un tremolio da ologramma; le staffe agli angoli la inquadrano. Il dito la gira: di taglio si stringe e da dietro si
    // vede rovesciata e più tenue. Accanto, appese con un filo, le cose da non dimenticare. Toccata la foto o un'etichetta: il
    // riquadro. Senza foto: il VETRO col busto di luce e «SCELGA UNA FOTO». Uguale al mockup v270 (olo_extra/nuovi.js, fotoBea).

    private static let fotoId = 102

    #if os(iOS)
    /// L'alone della foto (lo shadowBlur del mockup), sfocato una volta per foto: l'immagine e quanto sporge su ogni lato (in frazione).
    private var alone: (foto: UIImage, im: UIImage, fx: Double, fy: Double)?

    private func aloneFoto(_ im: UIImage) -> (im: UIImage, fx: Double, fy: Double)? {
        if let a = alone, a.foto === im { return (a.im, a.fx, a.fy) }
        guard let cg = im.cgImage else { return nil }
        let ci = CIImage(cgImage: cg), e = ci.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let r = 8 * Double(e.height) / 420, bordo = r * 3                 // ombra di 16 punti su una foto alta circa 420 punti
        guard let filtro = CIFilter(name: "CIGaussianBlur") else { return nil }
        filtro.setValue(ci, forKey: kCIInputImageKey)
        filtro.setValue(r, forKey: kCIInputRadiusKey)
        let fuori = e.insetBy(dx: -bordo, dy: -bordo)
        guard let sfocata = filtro.outputImage?.cropped(to: fuori),
              let fatta = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(sfocata, from: fuori) else { return nil }
        let a = (foto: im, im: UIImage(cgImage: fatta), fx: bordo / Double(e.width), fy: bordo / Double(e.height))
        alone = a
        return (a.im, a.fx, a.fy)
    }
    #endif

    private func ritratto(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, _ piccolo: Bool) {
        guard let im = B.foto, im.size.width > 0, im.size.height > 0 else { vetro(&gc, W, H, t, M, B, piccolo); return }
        let base = scena(&gc, W, H, t, piccolo), cx = W / 2, r = Double(im.size.width / im.size.height)
        let h = min(base - (piccolo ? 4 : 44), (piccolo ? W * 0.95 : W * 0.84) / r), w = h * r
        let nasce = OP.lis(t / 0.9), gira = cos(M.giro * 0.9 + 0.12 * sin(t * 0.35))
        let sx = (gira < 0 ? -1.0 : 1.0) * max(0.08, abs(gira)), ww = w * abs(sx)
        let top = base - (piccolo ? 2 : 10) - h + (piccolo ? 0 : 3 * sin(t * 1.2)), fondo = top + h, taglio = top + h * (1 - nasce)
        // la foto in luce: nasce dal basso, l'alone attorno, il tremolio
        do {
            var g = gc
            g.clip(to: Path(CGRect(x: 0, y: taglio - 1, width: W, height: fondo - taglio + 3)))
            g.translateBy(x: cx, y: 0)
            g.scaleBy(x: sx, y: 1)
            let luce = (0.88 + 0.12 * sin(t * 2.3)) * (sx < 0 ? 0.5 : 1), dove = CGRect(x: -w / 2, y: top, width: w, height: h)
            #if os(iOS)
            if !piccolo, let a = aloneFoto(im) {
                var l = g
                l.opacity = 0.75 * luce
                l.draw(Image(uiImage: a.im), in: dove.insetBy(dx: -a.fx * w, dy: -a.fy * h))
            }
            #endif
            g.opacity = luce
            g.draw(Image(uiImage: im), in: dove)
            if !piccolo && t.truncatingRemainder(dividingBy: 4.3) < 0.09 {
                g.opacity = 0.35
                g.draw(Image(uiImage: im), in: dove.offsetBy(dx: 5, dy: -1))
                g.draw(Image(uiImage: im), in: dove.offsetBy(dx: -3, dy: 1))
            }
        }
        if nasce < 1 {                                                    // la riga di luce che la fa nascere
            gc.fill(Path(CGRect(x: cx - ww / 2 - 6, y: taglio - 1, width: ww + 12, height: 2)), with: .color(OP.b(0.95)))
            OP.alone(&gc, cx, taglio, piccolo ? 6 : 26, 0.5)
        } else {                                                          // la scansione che la risale, ogni 3 secondi
            let u = t.truncatingRemainder(dividingBy: 3) / 3, y = fondo - h * u
            gc.fill(Path(CGRect(x: cx - ww / 2, y: y - 22, width: ww, height: 23)),
                    with: .linearGradient(Gradient(colors: [OP.s(0), OP.c(0.28 * (1 - u))]), startPoint: CGPoint(x: 0, y: y - 22), endPoint: CGPoint(x: 0, y: y + 1)))
            gc.fill(Path(CGRect(x: cx - ww / 2, y: y, width: ww, height: 1.2)), with: .color(OP.b(0.6 * (1 - u))))
        }
        // le staffe
        let st = piccolo ? 4.0 : 13.0, L = cx - ww / 2 - (piccolo ? 2 : 9), R = cx + ww / 2 + (piccolo ? 2 : 9)
        let T = top - (piccolo ? 1 : 7), Bo = fondo + (piccolo ? 0 : 3)
        var staffe = Path()
        let angoli: [(x: Double, y: Double, dx: Double, dy: Double)] = [(L, T, 1, 1), (R, T, -1, 1), (L, Bo, 1, -1), (R, Bo, -1, -1)]
        for q in angoli {
            staffe.move(to: CGPoint(x: q.x, y: q.y + q.dy * st))
            staffe.addLine(to: CGPoint(x: q.x, y: q.y))
            staffe.addLine(to: CGPoint(x: q.x + q.dx * st, y: q.y))
        }
        gc.stroke(staffe, with: .color(OP.b(0.9 * nasce)), lineWidth: piccolo ? 1 : 1.6)
        guard !piccolo else { return }
        M.zona(cx, top + h / 2, max(30, min(ww, h) / 2), ProveBea.fotoId)
        // le cose da non dimenticare, appese ai lati con un filo
        var posti: [Int: (x: Double, y: Double)] = [:]
        for (k, tag) in B.tags.prefix(3).enumerated() {
            let aSinistra = k % 2 == 0, a = OP.lis((t - 0.9 - Double(k) * 0.25) / 0.4)
            if a <= 0 { continue }
            let wC = 78.0, hC = 24.0, y = top + h * (0.28 + 0.24 * Double(k)) + 2 * sin(t * 0.9 + Double(k))
            let bx = aSinistra ? max(4, L - wC - 14) : min(W - wC - 4, R + 14), by = y - hC / 2, aggancio = aSinistra ? L + 2 : R - 2
            var filo = Path()
            Olo.linea(&filo, aSinistra ? bx + wC : bx, y, aggancio, y)
            gc.stroke(filo, with: .color(OP.s(0.4 * a)), lineWidth: 1)
            gc.fill(Path(CGRect(x: bx, y: by, width: wC, height: hC)), with: .color(Color(red: 2 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.78 * a)))
            var tacche = Path()
            let spigoli: [(x: Double, y: Double, dx: Double, dy: Double)] = [(bx, by, 1, 1), (bx + wC, by, -1, 1), (bx, by + hC, 1, -1), (bx + wC, by + hC, -1, -1)]
            for s in spigoli {
                tacche.move(to: CGPoint(x: s.x, y: s.y + s.dy * 5))
                tacche.addLine(to: CGPoint(x: s.x, y: s.y))
                tacche.addLine(to: CGPoint(x: s.x + s.dx * 5, y: s.y))
            }
            gc.stroke(tacche, with: .color(M.scelta == k ? OP.b(1) : OP.c(0.8 * a)), lineWidth: 1)
            OP.scritta(&gc, OP.taglia(tag.titolo, 13), bx + wC / 2, y - 1, 6.5, 700, OP.b(0.95 * a))
            OP.scritta(&gc, OP.taglia(tag.sotto, 14), bx + wC / 2, y + 8, 6, 600, OP.c(0.85 * a))
            M.zona(bx + wC / 2, y, 22, k)
            posti[k] = (x: bx + wC / 2, y: y)
        }
        OP.scritta(&gc, "BEA", 10, 14, 8, 600, OP.c(0.85), .leading)
        if let k = M.scelta, k < B.tags.count, let p = posti[k] {
            let tag = B.tags[k]
            OP.riquadro(&gc, W, H, p.x, p.y, [tag.titolo, tag.sotto, tag.data ? "JARVIS TE LO RICORDA PRIMA" : "SEGNALA «FATTO» QUANDO C'È"],
                        t - M.sceltaT, codice: tag.data ? "DATA" : "PROMESSA")
        } else if M.scelta == ProveBea.fotoId {
            OP.riquadro(&gc, W, H, cx, top + h * 0.3, ["BEA", "LA SUA FOTO, IN LUCE", "RESTA SOLO SUL TELEFONO"], t - M.sceltaT, codice: "RITRATTO")
        }
    }
}

/// L'ologramma di Bea con le sue tre prove (iPhone: grande, con le chip; polso: piccolo, la prova scelta sull'iPhone).
struct OlogrammaBeaProve: View {
    let dati: BeaOlo
    var piccolo = false
    @State private var prove = ProveBea()

    var body: some View {
        if piccolo {
            ProvaOloPiccola(sezione: .bea) { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, dati, piccolo: true) }
        } else {
            #if os(iOS)
            ProveOloVista(sezione: .bea, altezza: 480, crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
