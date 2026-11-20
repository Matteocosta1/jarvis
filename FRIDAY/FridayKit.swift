import SwiftUI
import Combine
import UIKit

// MARK: - FRIDAY · i pezzi comuni delle sezioni nuove (mockup approvato, strato «friday»)

/// Le icone di FRIDAY, disegnate come nel mockup (viewBox 24 × 24, tratto 1,6, estremi tondi). «f:nome» nelle liste delle icone.
enum IconeFriday {
    enum Pezzo { case p(String), c(Double, Double, Double) }
    static let tutte: [String: [Pezzo]] = [
        "occhi": [.p("M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"), .c(12, 12, 3)],
        "foto": [.p("M4 5h16v14H4z"), .c(9, 10, 2), .p("M4 17l5-4 4 3 3-2 4 3")],
        "frigo": [.p("M6 3h12v18H6zM6 10h12M9 6v2M9 13v3")],
        "cucina": [.p("M4 10h16v5a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM2 10h20M9 7c0-1.5 1-2 1-3.5M14 7c0-1.5 1-2 1-3.5")],
        "scanner": [.p("M3 7V4h3M18 4h3v3M21 17v3h-3M6 20H3v-3M7 8v8M10 8v8M13 8v8M16 8v8")],
        "allenatore": [.p("M2 17h20M4 17v3M20 17v3M6 14h8M18 9v8"), .c(8, 10, 1.6), .p("M9.5 11.5l3 2.5 4-4")],
        "makeup": [.p("M9 21h6v-8H9zM10 13V8l4-4v9M8 13h8")],
        "vitals": [.p("M3 12h4l2-5 4 10 2-5h6")],
        "sonno": [.p("M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z")],
        "ciclo": [.p("M12 3s6 7 6 11a6 6 0 0 1-12 0c0-4 6-11 6-11z")],
        "testa": [.p("M7 20v-3a7 7 0 1 1 11-5.7l2 3.7h-2v3a2 2 0 0 1-2 2h-2v-1"), .p("M11 7l-1.5 3h3L11 13")],
        "diario": [.p("M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h11")],
        "confidente": [.p("M4 5h11v8H9l-4 3v-3H4zM18 9h2v8h-1v3l-3-3h-5")],
        "memoria": [.p("M12 21s-7-6-7-11a7 7 0 0 1 14 0c0 5-7 11-7 11z"), .c(12, 10, 2.5)],
        "mail": [.p("M3 6h18v12H3zM3 6l9 7 9-7")],
        "messaggi": [.p("M4 5h16v11H9l-5 4z")],
        "telefono": [.p("M6 3h3.5l2 5-2.5 1.5a11 11 0 0 0 5.5 5.5L16 12.5l5 2V18a2 2 0 0 1-2 2A16 16 0 0 1 4 5a2 2 0 0 1 2-2z")],
        "interprete": [.p("M4 5h8M8 3v2M5 11c2-1 5-4 6-6M7 8c1 2 3 3 5 4M13 21l4-9 4 9M14.5 18h5")],
        "gestionale": [.p("M4 6h16v14H4zM4 10h16M8 3v4M16 3v4")],
        "spesa": [.p("M3 4h2l2 11h11l2-7H6"), .c(9, 19, 1.5), .c(17, 19, 1.5)],
        "armadio": [.p("M10 5a2 2 0 1 1 2 2v2l9 7H3l9-7")],
        "nando": [.c(6, 10, 2), .c(10, 5.5, 2), .c(14, 5.5, 2), .c(18, 10, 2), .p("M12 11c3 0 6 4 6 7 0 2-2 3-3.5 2.4L12 19l-2.5 1.4C8 21 6 20 6 18c0-3 3-7 6-7z")],
        "musica": [.p("M9 18V6l11-2v12"), .c(6, 18, 3), .c(17, 16, 3)],
        "difesa": [.p("M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6z")],
        "account": [.c(12, 8, 4), .p("M4 21c1-4 4-6 8-6s7 2 8 6")],
        "sos": [.p("M12 3l9 16H3zM12 10v4M12 17h.01")]
    ]
}

/// Un'icona: «f:nome» (FRIDAY, dal mockup), «vinile», «logo:…» (immagine) o un simbolo di sistema. `lato`: la misura del disegno.
struct SimboloFriday: View {
    let nome: String
    var lato: CGFloat = 15

    var body: some View {
        if nome.hasPrefix("f:"), let pezzi = IconeFriday.tutte[String(nome.dropFirst(2))] {
            FormaSVG(pezzi: pezzi)
                .stroke(style: StrokeStyle(lineWidth: max(1, 1.6 * lato / 24 * 1.25), lineCap: .round, lineJoin: .round))
                .frame(width: lato * 1.25, height: lato * 1.25)
        } else if nome == "vinile" {
            IconaVinile().frame(width: lato * 1.15, height: lato * 1.15)
        } else if nome.hasPrefix("logo:") {
            Image(String(nome.dropFirst(5))).resizable().renderingMode(.template).scaledToFit().frame(width: lato, height: lato)
        } else {
            Image(systemName: nome).font(.system(size: lato))
        }
    }
}

/// I pezzi SVG (path e cerchi) di un'icona, scalati nel riquadro.
struct FormaSVG: Shape {
    let pezzi: [IconeFriday.Pezzo]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for x in pezzi {
            switch x {
            case .p(let d): p.addPath(PercorsoSVG.leggi(d))
            case .c(let cx, let cy, let raggio): p.addEllipse(in: CGRect(x: cx - raggio, y: cy - raggio, width: raggio * 2, height: raggio * 2))
            }
        }
        let s = min(r.width, r.height) / 24
        return p.applying(CGAffineTransform(translationX: r.minX + (r.width - 24 * s) / 2, y: r.minY + (r.height - 24 * s) / 2).scaledBy(x: s, y: s))
    }
}

/// Lettore dei «d» SVG: M L H V C S Q T A Z, assoluti e relativi.
enum PercorsoSVG {
    static func leggi(_ d: String) -> Path {
        var p = Path()
        var t = numeriEComandi(d)[...]
        var cur = CGPoint.zero, inizio = CGPoint.zero, ultimoCtrl: CGPoint? = nil, cmd: Character = "M"
        func n() -> CGFloat { if case .n(let v)? = t.first { t.removeFirst(); return v }; return 0 }
        func haNumero() -> Bool { if case .n? = t.first { return true }; return false }
        while !t.isEmpty {
            if case .c(let c) = t.first! { cmd = c; t.removeFirst() }
            let rel = cmd.isLowercase
            let o = rel ? cur : .zero
            switch cmd.uppercased() {
            case "M":
                cur = CGPoint(x: o.x + n(), y: o.y + n()); p.move(to: cur); inizio = cur; ultimoCtrl = nil
                cmd = rel ? "l" : "L"                                   // le coppie dopo M sono linee
            case "L": cur = CGPoint(x: o.x + n(), y: o.y + n()); p.addLine(to: cur); ultimoCtrl = nil
            case "H": cur = CGPoint(x: (rel ? cur.x : 0) + n(), y: cur.y); p.addLine(to: cur); ultimoCtrl = nil
            case "V": cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + n()); p.addLine(to: cur); ultimoCtrl = nil
            case "C":
                let c1 = CGPoint(x: o.x + n(), y: o.y + n()), c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addCurve(to: e, control1: c1, control2: c2); ultimoCtrl = c2; cur = e
            case "S":
                let c1 = ultimoCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addCurve(to: e, control1: c1, control2: c2); ultimoCtrl = c2; cur = e
            case "Q":
                let c = CGPoint(x: o.x + n(), y: o.y + n()), e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addQuadCurve(to: e, control: c); ultimoCtrl = c; cur = e
            case "T":
                let c = ultimoCtrl.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let e = CGPoint(x: o.x + n(), y: o.y + n())
                p.addQuadCurve(to: e, control: c); ultimoCtrl = c; cur = e
            case "A":
                let rx = n(), ry = n(), rot = n(), grande = n() != 0, orario = n() != 0
                let e = CGPoint(x: o.x + n(), y: o.y + n())
                arco(&p, da: cur, a: e, rx: rx, ry: ry, rotazione: rot, grande: grande, orario: orario)
                cur = e; ultimoCtrl = nil
            case "Z":
                p.closeSubpath(); cur = inizio; ultimoCtrl = nil
                while haNumero() { t.removeFirst() }                    // numeri dopo Z: non validi, si saltano
            default: t.removeFirst()
            }
        }
        return p
    }

    private enum Pezzo { case n(CGFloat), c(Character) }
    private static func numeriEComandi(_ d: String) -> [Pezzo] {
        var out: [Pezzo] = [], numero = ""
        func chiudi() { if let v = Double(numero) { out.append(.n(CGFloat(v))) }; numero = "" }
        for ch in d {
            if ch.isLetter && ch != "e" { chiudi(); out.append(.c(ch)) }
            else if ch == "-" { if numero.last == "e" { numero.append(ch) } else { chiudi(); numero = "-" } }
            else if ch == "." { if numero.contains(".") { chiudi(); numero = "0." } else { numero.append(ch) } }
            else if ch.isNumber || ch == "e" { numero.append(ch) }
            else { chiudi() }
        }
        chiudi()
        return out
    }

    /// L'arco ellittico SVG in curve di Bézier (W3C, implementation notes F.6).
    private static func arco(_ p: inout Path, da a: CGPoint, a b: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rotazione: CGFloat,
                             grande: Bool, orario: Bool) {
        guard rx0 != 0, ry0 != 0, a != b else { p.addLine(to: b); return }
        let fi = rotazione * .pi / 180, c = cos(fi), s = sin(fi)
        let dx = (a.x - b.x) / 2, dy = (a.y - b.y) / 2
        let x1 = c * dx + s * dy, y1 = -s * dx + c * dy
        var rx = abs(rx0), ry = abs(ry0)
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
        let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        var k = sqrt(num / (rx * rx * y1 * y1 + ry * ry * x1 * x1))
        if grande == orario { k = -k }
        let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
        let cx = c * cx1 - s * cy1 + (a.x + b.x) / 2, cy = s * cx1 + c * cy1 + (a.y + b.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let segno: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let d = max(-1, min(1, (ux * vx + uy * vy) / (hypot(ux, uy) * hypot(vx, vy))))
            return segno * acos(d)
        }
        let t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !orario && dt > 0 { dt -= 2 * .pi } else if orario && dt < 0 { dt += 2 * .pi }
        let pezzi = Int(ceil(abs(dt) / (.pi / 2)))
        let passo = dt / CGFloat(pezzi)
        let h = 4 / 3 * tan(passo / 4)
        var t = t1
        for _ in 0..<pezzi {
            let c1 = cos(t), s1 = sin(t), c2 = cos(t + passo), s2 = sin(t + passo)
            func punto(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c * rx * x - s * ry * y + cx, y: s * rx * x + c * ry * y + cy) }
            p.addCurve(to: punto(c2, s2), control1: punto(c1 - h * s1, s1 + h * c1), control2: punto(c2 + h * s2, s2 - h * c2))
            t += passo
        }
    }
}

// MARK: - Le righe delle sezioni (come r() del mockup: etichetta a sinistra, valore a destra; verde ok, rosso da guardare)

struct RigaF: View {
    enum Stato { case normale, ok, no }
    let etichetta: String
    let valore: String
    var stato: Stato = .normale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(etichetta).font(.system(size: 14)).foregroundStyle(Color.testo)
            Spacer(minLength: 8)
            Text(valore).font(.system(size: 13, design: .monospaced)).multilineTextAlignment(.trailing)
                .foregroundStyle(stato == .ok ? Color.verdeF : stato == .no ? Color.rossoF : Color.tenue)
        }
        .padding(.vertical, 3)
    }
}

/// Il tasto pieno delle sezioni (azione principale), come i tasti arancio del mockup.
struct TastoF: View {
    let testo: String
    var icona: String? = nil
    var tinta: Color = .ciano
    var pieno = true
    let azione: () -> Void
    var body: some View {
        Button { Suoni.tocco(); azione() } label: {
            HStack(spacing: 8) {
                if let icona { SimboloFriday(nome: icona, lato: 14) }
                Text(testo).font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(pieno ? Color.fondo : tinta)
            .background(RoundedRectangle(cornerRadius: 12).fill(pieno ? tinta : tinta.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(pieno ? 0 : 0.45), lineWidth: 1))
        }
        .buttonStyle(StileStark())
    }
}

/// Un'etichetta da accendere e spegnere (sintomi, fattori, permessi).
struct ChipF: View {
    let testo: String
    let acceso: Bool
    var tinta: Color = .ciano
    let tocco: () -> Void
    var body: some View {
        Button { Suoni.tocco(); tocco() } label: {
            Text(testo).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(acceso ? Color.fondo : tinta)
                .background(Capsule().fill(acceso ? tinta : tinta.opacity(0.06)))
                .overlay(Capsule().stroke(tinta.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(acceso ? .isSelected : [])
    }
}

/// Le schede a schede (Capi · Vinted · Conti…): una riga di tasti sotto la testata.
struct LinguetteF: View {
    let voci: [String]
    @Binding var scelta: Int
    var tinta: Color = .ciano
    var body: some View {
        HStack(spacing: 6) {
            ForEach(voci.indices, id: \.self) { k in
                Button { Suoni.tocco(); withAnimation(.easeOut(duration: 0.2)) { scelta = k } } label: {
                    Text(voci[k].uppercased()).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(scelta == k ? Color.fondo : tinta)
                        .background(RoundedRectangle(cornerRadius: 9).fill(scelta == k ? tinta : tinta.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(tinta.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// «Solo tuo»: i dati che non escono dal telefono di Bea.
struct SoloTuo: View {
    var body: some View {
        Label("Solo tuo", systemImage: "lock.fill")
            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
            .foregroundStyle(Color.petrolio)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().stroke(Color.petrolio.opacity(0.6), lineWidth: 1))
    }
}

/// Una nota in piccolo sotto i riquadri.
struct NotaF: View {
    let testo: String
    var body: some View { Text(testo).font(.system(size: 12)).foregroundStyle(Color.tenue).fixedSize(horizontal: false, vertical: true) }
}

// MARK: - L'archivio sul telefono: i dati di Bea delle sezioni nuove restano nella cartella dell'app (protetta, nel backup cifrato
// dell'iPhone come le altre app); non vanno al cervello se non quando servono a una risposta, mai ad Ale

enum ArchivioF {
    private static var cartella: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FRIDAY", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func leggi<T: Decodable>(_ nome: String, _ tipo: T.Type) -> T? {
        guard let d = try? Data(contentsOf: cartella.appendingPathComponent(nome + ".json")) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: d)
    }
    static func scrivi<T: Encodable>(_ nome: String, _ valore: T) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(valore) else { return }
        try? d.write(to: cartella.appendingPathComponent(nome + ".json"), options: [.atomic, .completeFileProtection])
    }
    /// Le immagini (capi, Nando, outfit): JPEG nella sottocartella «foto».
    static func salvaFoto(_ img: UIImage, nome: String) -> String? {
        let dir = cartella.appendingPathComponent("foto", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let d = img.jpegData(compressionQuality: 0.8) else { return nil }
        let file = nome + ".jpg"
        do { try d.write(to: dir.appendingPathComponent(file), options: [.atomic, .completeFileProtection]); return file } catch { return nil }
    }
    static func foto(_ file: String) -> UIImage? { UIImage(contentsOfFile: cartella.appendingPathComponent("foto").appendingPathComponent(file).path) }
    static func togliFoto(_ file: String) { try? FileManager.default.removeItem(at: cartella.appendingPathComponent("foto").appendingPathComponent(file)) }
}

/// Un dato di Bea che si salva da solo a ogni modifica.
@MainActor final class Salvato<T: Codable & Equatable>: ObservableObject {
    @Published var valore: T { didSet { if valore != oldValue { ArchivioF.scrivi(nome, valore) } } }
    private let nome: String
    init(_ nome: String, iniziale: T) {
        self.nome = nome
        self.valore = ArchivioF.leggi(nome, T.self) ?? iniziale
    }
}
