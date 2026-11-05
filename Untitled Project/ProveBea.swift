import Foundation
import SwiftUI
import UIKit                // UIImage (c'è anche sull'orologio): la foto di Bea in ologramma
import CoreGraphics

// MARK: - BEA · le tre prove (mockup v262–v264): PUNTI, LINEE, VETRO
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
        case 1: linee(&gc, W, H, t, M, B, piccolo)
        case 2: vetro(&gc, W, H, t, M, B, piccolo)
        default: punti(&gc, W, H, t, M, B, piccolo)
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

    // MARK: BE1 · PUNTI — Bea fatta di migliaia di punti di luce, come la nuvola di un LiDAR: la luce della foto diventa profondità (le
    // parti chiare vengono avanti), girando si vede il rilievo; i punti tremano appena e una banda di scansione sale e li accende.

    private func punti(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, _ piccolo: Bool) {
        let base = scena(&gc, W, H, t, piccolo), cx = W / 2
        let sz = piccolo ? min(W * 0.55, H * 0.52) : min(W * 0.27, H * 0.4), cy = piccolo ? base - 2 : base - 6 - sz * 0.05
        let ang = 0.42 * sin(t * 0.3) + M.giro, al = 0.1, lato = piccolo ? 0.6 : 1.0
        let zs = (t * 0.32).truncatingRemainder(dividingBy: 1.2) * 1.45 - 0.05
        var G = PuntiOlo(6)
        var quanti = 0
        if let im = B.foto, let C = campioni(im, piccolo ? 30 : 76) {
            let hh = 1.5, ww = hh * C.rapporto, nasce = OP.lis(t / 1.2)
            for j in 0..<C.righe {
                let Z = (1 - Double(j) / Double(C.righe)) * hh
                if Z > hh * nasce + 0.02 { continue }
                let vicino = exp(-pow((Z - zs) / 0.06, 2))
                for i in 0..<C.colonne {
                    let k = j * C.colonne + i, a = C.A[k]
                    if a < 0.14 { continue }
                    let L = C.L[k]
                    let o = Olo.proietta((Double(i) / Double(C.colonne) - 0.5) * ww, -(L - 0.45) * 0.45 * nasce, Z, ang, al, cx, cy, sz)
                    let trema = 0.75 + 0.25 * sin(t * 3.1 + Double(i) * 0.7 + Double(j) * 1.3)
                    G.metti(Int(((a * (0.25 + 0.75 * L) * trema + 0.6 * vicino) * 5).rounded()), o.x, o.y, (1 + 0.9 * L + vicino) * lato)
                    quanti += 1
                }
            }
        } else {
            for k in 0...46 {
                let z = Double(k) / 46 * 1.22, b = ProveBea.busto(z), giro = max(12, Int((56 * b.x).rounded())), vicino = exp(-pow((z - zs) / 0.06, 2))
                for s in 0..<giro {
                    let a = Double(s) / Double(giro) * OP.due + Double(k) * 0.17
                    let o = Olo.proietta(cos(a) * b.x, sin(a) * b.y, z, ang, al, cx, cy, sz * 1.15)
                    let luce = (o.z < 0 ? 0.65 : 0.25) * (0.75 + 0.25 * sin(t * 3 + Double(s) + Double(k))) + 0.6 * vicino
                    G.metti(Int((luce * 5).rounded()), o.x, o.y, (1.3 + vicino) * lato)
                    quanti += 1
                }
            }
            if !piccolo { OP.scritta(&gc, "SCELGA UNA FOTO", cx, 30, 8, 700, OP.c(0.9)) }
        }
        G.disegna(&gc, colore: { $0 >= 4 ? OP.b(0.5 + 0.12 * Double($0)) : OP.c(0.12 + 0.16 * Double($0)) })
        guard !piccolo else { return }
        OP.scritta(&gc, "BEA · \(Olo.numero(Double(quanti))) PUNTI", 10, 14, 8, 600, OP.c(0.85), .leading)
    }

    // MARK: BE2 · LINEE — Bea fatta di righe orizzontali che si gonfiano dove la foto è chiara, come un rilievo inciso dal laser: girando,
    // le righe diventano il volto in 3D. Una riga più chiara la ripercorre dal basso.

    private func linee(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, _ piccolo: Bool) {
        let base = scena(&gc, W, H, t, piccolo), cx = W / 2
        let sz = piccolo ? min(W * 0.55, H * 0.52) : min(W * 0.27, H * 0.4), cy = piccolo ? base - 2 : base - 6 - sz * 0.05
        let ang = 0.5 * sin(t * 0.28) + M.giro, al = 0.16
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let zs = (t * 0.3).truncatingRemainder(dividingBy: 1.2) * 1.45 - 0.05
        if let im = B.foto, let C = campioni(im, piccolo ? 34 : 84) {
            let hh = 1.5, ww = hh * C.rapporto, nasce = OP.lis(t / 1.2)
            for j in stride(from: 0, to: C.righe, by: piccolo ? 3 : 2) {
                let Z = (1 - Double(j) / Double(C.righe)) * hh
                if Z > hh * nasce + 0.02 { continue }
                let vicino = exp(-pow((Z - zs) / 0.05, 2))
                var q: P3?
                for i in 0..<C.colonne {
                    let k = j * C.colonne + i, a = C.A[k], L = C.L[k]
                    if a < 0.14 { q = nil; continue }
                    let o = P((Double(i) / Double(C.colonne) - 0.5) * ww, -(L * a) * 0.36 * nasce, Z + L * a * 0.02)
                    if let q { F.metti(Int(((a * (0.25 + 0.75 * L) + 0.7 * vicino) * 5).rounded()), q, o) }
                    q = o
                }
            }
        } else {
            for k in 0...40 {
                let z = Double(k) / 40 * 1.22, b = ProveBea.busto(z), vicino = exp(-pow((z - zs) / 0.05, 2))
                var q: P3?
                for s in 0...48 {
                    let a = Double(s) / 48 * OP.due, o = P(cos(a) * b.x * 1.15, sin(a) * b.y * 1.15, z * 1.15)
                    if let q { F.metti((o.z + q.z < 0 ? 3 : 1) + Int((vicino * 2).rounded()), q, o) }
                    q = o
                }
            }
            if !piccolo { OP.scritta(&gc, "SCELGA UNA FOTO", cx, 30, 8, 700, OP.c(0.9)) }
        }
        F.linee(&gc, colore: { $0 >= 5 ? OP.b(0.9) : $0 == 4 ? OP.b(0.55) : OP.c(0.08 + 0.17 * Double($0)) },
                spessore: { 0.7 + Double($0) * 0.12 }, alone: { $0 >= 4 ? OP.s(0.06) : nil })
        guard !piccolo else { return }
        OP.scritta(&gc, "BEA · RILIEVO", 10, 14, 8, 600, OP.c(0.85), .leading)
    }

    // MARK: BE3 · VETRO — Bea su una lastra di vetro sospesa sopra il proiettore (la foto in luce, il riflesso che la attraversa, le staffe
    // agli angoli); attorno girano le cose da non dimenticare: le date e la promessa. Toccata una, il riquadro; toccata la lastra, la foto.

    private static let lastraId = 100

    private func vetro(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, _ B: BeaOlo, _ piccolo: Bool) {
        let base = scena(&gc, W, H, t, piccolo), cx = W / 2
        let sz = piccolo ? min(W * 0.5, H * 0.5) : min(W * 0.27, H * 0.38), cy = base - (piccolo ? 3 : 8)
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
            let a = t * 0.32 + Double(k) * 2.094, p = P(cos(a) * (hw + 0.55), sin(a) * 0.5, z0 + hh * (0.35 + 0.22 * Double(k)))
            let dav = p.z < 0, scelta = M.scelta == k, al2 = dav ? 1.0 : 0.4
            let tw = max(OP.larghezza(gc, tag.titolo, 6.5, 700), OP.larghezza(gc, tag.sotto, 6, 600))
            let w = max(66, (tw + 12).rounded(.up)), h = 22.0, bx = p.x - w / 2, by = p.y - h / 2
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
            OP.scritta(&gc, tag.titolo, p.x, p.y - 1, 6.5, 700, OP.b(0.95 * al2))
            OP.scritta(&gc, tag.sotto, p.x, p.y + 8, 6, 600, tag.data && k == 0 ? OP.b(0.95 * al2) : OP.c(0.8 * al2))
            if dav { M.zona(p.x, p.y, 24, k) }
            posti.append(p)
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
            ProveOloVista(sezione: .bea, altezza: 310, crea: { prove.crea($0) }) { k, gc, W, H, t, M in
                prove.disegna(k, &gc, W, H, t, M, dati, piccolo: false)
            }
            #endif
        }
    }
}
