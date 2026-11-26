#if os(iOS)
import Foundation
import SwiftUI
import UIKit
import PDFKit

// MARK: - 26 nov · DOCUMENTI (mockup approvato «JARVIS Documenti», nel mockup principale Mark XIII versione 110)
// Ritenuta d'acconto, prestazione occasionale e fattura (copia di cortesia). Il cervello chiede i dati e chiama lo strumento
// «documento»; qui l'app fa i conti, il PDF, l'anteprima a pagina piena (MODIFICA · INVIA), l'invio col foglio di condivisione di
// iOS e il salvataggio in Archivio › Documenti. I dati non si salvano da nessuna parte: restano solo nel documento.

/// Un documento preparato da JARVIS.
struct DocumentoJarvis: Identifiable, Equatable {
    enum Tipo: String { case ritenuta, occasionale, fattura }

    /// Chi lo fa (il signore) o chi lo riceve (il cliente).
    struct Parte: Equatable {
        var nome: String
        var codice: String
        var indirizzo: String
        var iban: String
    }

    let id = UUID()
    var tipo: Tipo
    var regime: String              // solo fattura: «forfettario» o «ordinario»
    var numero: Int
    var anno: Int
    var data: Date
    var cliente: Parte
    var prestatore: Parte
    var importo: Double
    var descrizione: String

    var nomeTipo: String {
        switch tipo {
        case .ritenuta: return "Ritenuta d'acconto"
        case .occasionale: return "Prestazione occasionale"
        case .fattura: return "Fattura"
        }
    }

    var titolo: String { tipo == .fattura ? "Fattura" : "Ricevuta per prestazione occasionale" }

    var nomeFile: String {
        let base: String
        switch tipo {
        case .ritenuta: base = "Ritenuta"
        case .occasionale: base = "Occasionale"
        case .fattura: base = "Fattura"
        }
        return "\(base) \(numero)-\(anno) · \(cliente.nome).pdf".replacingOccurrences(of: "/", with: "-")
    }
}

/// Una riga dei conti: etichetta e valore già scritti.
struct RigaConto: Equatable {
    let etichetta: String
    let valore: String
}

/// I conti del documento (li fa l'app, mai il cervello), uguali al mockup approvato.
struct ContiDocumento {
    let righe: [RigaConto]
    let totale: RigaConto
    let bollo: Bool
    let totaleNumero: Double

    init(_ d: DocumentoJarvis) {
        let l = d.importo
        let bollo = l > 77.47
        switch d.tipo {
        case .ritenuta:
            let r = ContiDocumento.tondo(l * 0.2)
            righe = [RigaConto(etichetta: "Compenso lordo", valore: Euro.scritto(l)),
                     RigaConto(etichetta: "Ritenuta d'acconto 20%", valore: "− " + Euro.scritto(r))]
            totaleNumero = l - r
            totale = RigaConto(etichetta: "Netto a pagare", valore: Euro.scritto(l - r))
            self.bollo = bollo
        case .occasionale:
            righe = [RigaConto(etichetta: "Compenso", valore: Euro.scritto(l)),
                     RigaConto(etichetta: "Ritenuta d'acconto", valore: "non dovuta")]
            totaleNumero = l
            totale = RigaConto(etichetta: "Totale a pagare", valore: Euro.scritto(l))
            self.bollo = bollo
        case .fattura:
            if d.regime == "ordinario" {
                let iva = ContiDocumento.tondo(l * 0.22)
                righe = [RigaConto(etichetta: "Imponibile", valore: Euro.scritto(l)),
                         RigaConto(etichetta: "IVA 22%", valore: Euro.scritto(iva))]
                totaleNumero = l + iva
                totale = RigaConto(etichetta: "Totale fattura", valore: Euro.scritto(l + iva))
                self.bollo = false
            } else {
                var r: [RigaConto] = [RigaConto(etichetta: "Imponibile", valore: Euro.scritto(l)),
                                      RigaConto(etichetta: "IVA", valore: "non applicata")]
                if bollo { r.append(RigaConto(etichetta: "Rivalsa imposta di bollo", valore: Euro.scritto(2))) }
                righe = r
                totaleNumero = l + (bollo ? 2 : 0)
                totale = RigaConto(etichetta: "Totale fattura", valore: Euro.scritto(l + (bollo ? 2 : 0)))
                self.bollo = bollo
            }
        }
    }

    /// Le note a piè di pagina (riferimenti di legge, bollo, pagamento), come nel mockup.
    static func note(_ d: DocumentoJarvis, _ c: ContiDocumento) -> [String] {
        var n: [String] = []
        switch d.tipo {
        case .ritenuta:
            n.append("Prestazione di lavoro autonomo occasionale (art. 2222 c.c.), fuori campo IVA per mancanza di abitualità (art. 5 D.P.R. 633/72).")
            n.append("Ritenuta d'acconto del 20% ai sensi dell'art. 25 D.P.R. 600/73, versata dal committente.")
        case .occasionale:
            n.append("Prestazione di lavoro autonomo occasionale (art. 2222 c.c.), fuori campo IVA per mancanza di abitualità (art. 5 D.P.R. 633/72).")
            n.append("Committente privato, non sostituto d'imposta: nessuna ritenuta d'acconto.")
        case .fattura:
            if d.regime != "ordinario" {
                n.append("Operazione senza applicazione dell'IVA, effettuata ai sensi dell'art. 1, commi 54-89, L. 190/2014 (regime forfettario).")
                n.append("Compenso non soggetto a ritenuta d'acconto ai sensi dell'art. 1, comma 67, L. 190/2014.")
            }
        }
        if c.bollo {
            n.append(d.tipo == .fattura ? "Imposta di bollo da 2,00 € assolta in modo virtuale."
                     : "Marca da bollo da 2,00 € applicata sull'originale (importo superiore a 77,47 €).")
        }
        let iban = d.prestatore.iban.trimmingCharacters(in: .whitespaces)
        if !iban.isEmpty {
            let pulito = iban.replacingOccurrences(of: "^IBAN\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            n.append("Pagamento con bonifico: IBAN \(pulito)")
        }
        return n
    }

    nonisolated static func tondo(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}

/// Gli euro scritti all'italiana: «1.200,00 €».
enum Euro {
    static func scritto(_ x: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return (f.string(from: NSNumber(value: x)) ?? String(format: "%.2f", x)) + " €"
    }
}

/// Lo strumento «documento» del cervello: legge i dati, numera, fa i conti. Il numero è progressivo per tipo e per anno
/// (solo il contatore resta sull'iPhone, i dati no); con «modifica» resta quello del documento appena fatto.
enum Documenti {
    /// L'ultimo documento preparato (per MODIFICA: stesso numero). Vive solo finché l'app è aperta.
    static var ultimo: DocumentoJarvis?

    static func prepara(_ i: [String: Any]) -> (String, Bool, DocumentoJarvis?) {
        guard let t = DocumentoJarvis.Tipo(rawValue: (i["tipo"] as? String ?? "").lowercased()) else {
            return (json(["errore": "tipo mancante: ritenuta, occasionale o fattura"]), true, nil)
        }
        let cliente = parte(i["cliente"])
        let io = parte(i["prestatore"])
        let importo = (i["importo"] as? NSNumber)?.doubleValue ?? Double(String(describing: i["importo"] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
        let descrizione = (i["descrizione"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var mancano: [String] = []
        if cliente.nome.isEmpty { mancano.append("il cliente") }
        if io.nome.isEmpty { mancano.append("i dati del signore") }
        if importo <= 0 { mancano.append("l'importo") }
        if descrizione.isEmpty { mancano.append("la descrizione") }
        guard mancano.isEmpty else { return (json(["errore": "mancano: " + mancano.joined(separator: ", ")]), true, nil) }

        let oggi = Date()
        let anno = Calendar(identifier: .gregorian).component(.year, from: oggi)
        let modifica = (i["modifica"] as? Bool) ?? false
        let numero: Int
        if modifica, let u = ultimo, u.tipo == t, u.anno == anno {
            numero = u.numero
        } else {
            let chiave = "documenti.numero.\(t.rawValue).\(anno)"
            numero = UserDefaults.standard.integer(forKey: chiave) + 1
            UserDefaults.standard.set(numero, forKey: chiave)
        }
        let regime = (i["regime"] as? String ?? "forfettario").lowercased() == "ordinario" ? "ordinario" : "forfettario"
        let d = DocumentoJarvis(tipo: t, regime: regime, numero: numero, anno: anno, data: oggi, cliente: cliente, prestatore: io,
                                importo: ContiDocumento.tondo(importo), descrizione: descrizione)
        ultimo = d
        let c = ContiDocumento(d)
        var conti: [[String: String]] = c.righe.map { ["voce": $0.etichetta, "valore": $0.valore] }
        conti.append(["voce": c.totale.etichetta, "valore": c.totale.valore])
        if c.bollo && t != .fattura { conti.append(["voce": "Marca da bollo", "valore": "2,00 € sull'originale"]) }
        return (json(["ok": true, "documento": "\(d.nomeTipo) n. \(numero)/\(anno)", "conti": conti,
                      "nota": "l'anteprima si apre appena hai finito di parlare: di' in una frase il netto o il totale, senza leggere tutte le righe"]),
                false, d)
    }

    private static func parte(_ x: Any?) -> DocumentoJarvis.Parte {
        let o = x as? [String: Any] ?? [:]
        func campo(_ k: String) -> String { (o[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return DocumentoJarvis.Parte(nome: campo("nome"), codice: campo("codice"), indirizzo: campo("indirizzo"), iban: campo("iban"))
    }

    private static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}

// MARK: - Il PDF (A4), impaginato come il foglio del mockup

enum PDFDocumentoJarvis {
    /// A4 in punti.
    static let pagina = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)

    static func crea(_ d: DocumentoJarvis) -> Data {
        let r = UIGraphicsPDFRenderer(bounds: pagina)
        return r.pdfData { ctx in
            ctx.beginPage()
            disegna(d)
        }
    }

    /// L'anteprima: la pagina del PDF vero, a buona risoluzione.
    static func immagine(_ dati: Data) -> UIImage? {
        guard let p = PDFDocument(data: dati)?.page(at: 0) else { return nil }
        return p.thumbnail(of: CGSize(width: pagina.width * 2, height: pagina.height * 2), for: .mediaBox)
    }

    // misure in proporzione al foglio del mockup (cqw = 1% della larghezza)
    private static let w = pagina.width
    private static func cqw(_ x: CGFloat) -> CGFloat { w * x / 100 }
    private static let inchiostro = UIColor(red: 17 / 255, green: 20 / 255, blue: 23 / 255, alpha: 1)
    private static let grigio = UIColor(red: 75 / 255, green: 85 / 255, blue: 92 / 255, alpha: 1)
    private static let grigioChiaro = UIColor(red: 107 / 255, green: 118 / 255, blue: 125 / 255, alpha: 1)
    private static let linea = UIColor(red: 217 / 255, green: 222 / 255, blue: 225 / 255, alpha: 1)

    private static func font(_ size: CGFloat, _ peso: UIFont.Weight = .regular, mono: Bool = false) -> UIFont {
        mono ? UIFont.monospacedSystemFont(ofSize: size, weight: peso) : UIFont.systemFont(ofSize: size, weight: peso)
    }

    /// Scrive un testo nel riquadro largo `larghezza` a partire da (x, y); restituisce l'altezza usata.
    @discardableResult
    private static func scrivi(_ testo: String, _ f: UIFont, _ colore: UIColor, x: CGFloat, y: CGFloat, larghezza: CGFloat,
                               allinea: NSTextAlignment = .left, interlinea: CGFloat = 1.3, spaziatura: CGFloat = 0) -> CGFloat {
        let p = NSMutableParagraphStyle()
        p.alignment = allinea
        p.lineHeightMultiple = interlinea
        let a = NSAttributedString(string: testo, attributes: [.font: f, .foregroundColor: colore, .paragraphStyle: p, .kern: spaziatura])
        let box = a.boundingRect(with: CGSize(width: larghezza, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        a.draw(with: CGRect(x: x, y: y, width: larghezza, height: ceil(box.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(box.height)
    }

    private static func riga(_ y: CGFloat, da x0: CGFloat, a x1: CGFloat, colore: UIColor, spessore: CGFloat) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x1, y: y))
        p.lineWidth = spessore
        colore.setStroke()
        p.stroke()
    }

    private static func disegna(_ d: DocumentoJarvis) {
        let c = ContiDocumento(d)
        let fattura = d.tipo == .fattura
        let m = cqw(7)
        let largo = w - 2 * m
        let data = d.data.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
        var y = m

        if fattura {   // la copia di cortesia: l'originale elettronico va allo SDI
            let alto = cqw(2.1) + cqw(2.4)
            let box = CGRect(x: m, y: y, width: largo, height: alto + cqw(0.6))
            let bordo = UIBezierPath(roundedRect: box, cornerRadius: cqw(1))
            bordo.lineWidth = cqw(0.25)
            UIColor(red: 226 / 255, green: 166 / 255, blue: 74 / 255, alpha: 1).setStroke()
            bordo.stroke()
            scrivi("COPIA DI CORTESIA · L'ORIGINALE ELETTRONICO VA INVIATO ALLO SDI", font(cqw(2.1), .bold, mono: true),
                   UIColor(red: 154 / 255, green: 91 / 255, blue: 0, alpha: 1), x: m, y: y + cqw(1.2), larghezza: largo,
                   allinea: .center, interlinea: 1, spaziatura: cqw(0.25))
            y += box.height + cqw(3.2)
        }

        y += scrivi(d.titolo, font(cqw(4.2), .bold), inchiostro, x: m, y: y, larghezza: largo, interlinea: 1.15)
        y += cqw(1)
        y += scrivi("n. \(d.numero)/\(d.anno) · \(data)", font(cqw(2.5), .medium), grigio, x: m, y: y, larghezza: largo)
        y += cqw(3.2)

        // le due parti, affiancate
        let mezza = (largo - cqw(4)) / 2
        func blocco(_ etichetta: String, _ p: DocumentoJarvis.Parte, x: CGFloat) -> CGFloat {
            var h = scrivi(etichetta, font(cqw(1.9), .bold, mono: true), grigioChiaro, x: x, y: y, larghezza: mezza, spaziatura: cqw(0.27))
            h += cqw(1)
            h += scrivi(p.nome, font(cqw(2.45), .bold), inchiostro, x: x, y: y + h, larghezza: mezza, interlinea: 1.45)
            let resto = [p.codice, p.indirizzo].filter { !$0.isEmpty }.joined(separator: "\n")
            if !resto.isEmpty { h += scrivi(resto, font(cqw(2.45)), inchiostro, x: x, y: y + h, larghezza: mezza, interlinea: 1.45) }
            return h
        }
        let hSx = blocco(fattura ? "CEDENTE" : "PRESTATORE", d.prestatore, x: m)
        let hDx = blocco(fattura ? "CESSIONARIO" : "COMMITTENTE", d.cliente, x: m + mezza + cqw(4))
        y += max(hSx, hDx) + cqw(3.2)

        // la descrizione
        riga(y, da: m, a: w - m, colore: linea, spessore: cqw(0.2))
        y += cqw(2.6)
        y += scrivi("Descrizione", font(cqw(2.5), .bold), inchiostro, x: m, y: y, larghezza: largo, interlinea: 1.5)
        let descr = d.descrizione.prefix(1).uppercased() + d.descrizione.dropFirst()
        y += scrivi(descr, font(cqw(2.5)), inchiostro, x: m, y: y, larghezza: largo, interlinea: 1.5)
        y += cqw(3.2)

        // i conti
        for r in c.righe {
            y += cqw(1.4)
            let h = scrivi(r.etichetta, font(cqw(2.5)), inchiostro, x: m, y: y, larghezza: largo * 0.65)
            scrivi(r.valore, font(cqw(2.5)), inchiostro, x: m + largo * 0.35, y: y, larghezza: largo * 0.65, allinea: .right)
            y += h + cqw(1.4)
            riga(y, da: m, a: w - m, colore: UIColor(red: 230 / 255, green: 233 / 255, blue: 235 / 255, alpha: 1), spessore: cqw(0.2))
        }
        y += cqw(0.4)
        riga(y, da: m, a: w - m, colore: inchiostro, spessore: cqw(0.35))
        y += cqw(2)
        scrivi(c.totale.etichetta, font(cqw(2.9), .bold), inchiostro, x: m, y: y, larghezza: largo * 0.65)
        scrivi(c.totale.valore, font(cqw(2.9), .bold), inchiostro, x: m + largo * 0.35, y: y, larghezza: largo * 0.65, allinea: .right)

        // in fondo al foglio: le note e la firma
        let note = ContiDocumento.note(d, c)
        let hFirma = cqw(2.3) + cqw(6)
        var hNote: CGFloat = 0
        let fNote = font(cqw(2.05))
        for n in note {
            let a = NSAttributedString(string: n, attributes: [.font: fNote])
            hNote += ceil(a.boundingRect(with: CGSize(width: largo, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height * 1.5) + cqw(1)
        }
        var yn = pagina.height - m - hFirma - cqw(3.2) - hNote
        for n in note {
            yn += scrivi(n, fNote, grigio, x: m, y: yn, larghezza: largo, interlinea: 1.5) + cqw(1)
        }
        let yf = pagina.height - m - cqw(2.3)
        scrivi("Milano, \(data)", font(cqw(2.3)), grigio, x: m, y: yf, larghezza: largo / 2)
        if !fattura {
            let xf = w - m - cqw(30)
            scrivi("Firma", font(cqw(2.3)), grigio, x: xf, y: yf - cqw(6), larghezza: cqw(30))
            riga(yf + cqw(2.3), da: xf, a: w - m, colore: inchiostro, spessore: cqw(0.2))
        }
    }
}

// MARK: - La sezione DOCUMENTI: l'anteprima a pagina piena, come tutte le sezioni (caricamento, testata, «Chiudi»)

struct VistaDocumento: View {
    let doc: DocumentoJarvis
    /// MODIFICA: la sezione si chiude e JARVIS chiede cosa cambiare.
    let modifica: () -> Void
    /// Inviato o salvato col foglio di iOS: il PDF è già in Archivio › Documenti.
    let inviato: () -> Void
    @Environment(\.chiudiOVia) private var chiudi
    @State private var pdf: Data?
    @State private var anteprima: UIImage?

    var body: some View {
        CorniceScheda(titolo: "Documenti", sottotitolo: doc.nomeTipo.lowercased(), icona: "doc.text", tinta: .ciano, pronto: anteprima != nil) {
            if let a = anteprima {
                Image(uiImage: a)
                    .resizable()
                    .aspectRatio(PDFDocumentoJarvis.pagina.width / PDFDocumentoJarvis.pagina.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ciano.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: 20, y: 10)
                    .accessibilityLabel("\(doc.nomeTipo) numero \(doc.numero), \(ContiDocumento(doc).totale.etichetta) \(ContiDocumento(doc).totale.valore)")
            }
            HStack(spacing: 10) {
                TastoComando(testo: "Modifica") { chiudi(); modifica() }
                TastoComando(testo: "Invia") { invia() }
            }
        }
        .task {
            let d = PDFDocumentoJarvis.crea(doc)
            pdf = d
            anteprima = PDFDocumentoJarvis.immagine(d)
        }
    }

    /// INVIA: il foglio di condivisione di iOS (Mail, WhatsApp, Salva su File…). Fatto l'invio, il PDF va in Archivio › Documenti.
    private func invia() {
        guard let pdf else { return }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(doc.nomeFile)
        do { try pdf.write(to: u, options: .atomic) } catch { return }
        let foglio = UIActivityViewController(activityItems: [u], applicationActivities: nil)
        let nome = doc.nomeFile, descrizione = "\(doc.nomeTipo) · \(ContiDocumento(doc).totale.valore)"
        // come Studio (condividi): il foglio di iOS chiama sul thread principale
        foglio.completionWithItemsHandler = { _, completato, _, _ in
            guard completato else { return }
            ArchivioCentrale.copia(nome: nome, cartella: "documenti", tipo: "application/pdf", dati: pdf, descrizione: descrizione)
            chiudi()
            inviato()
        }
        guard let sopra = VistaDocumento.inCima() else { return }
        foglio.popoverPresentationController?.sourceView = sopra.view
        foglio.popoverPresentationController?.sourceRect = CGRect(x: sopra.view.bounds.midX, y: sopra.view.bounds.maxY - 80, width: 1, height: 1)
        sopra.present(foglio, animated: true)
    }

    /// Il controller in cima a tutto (la sezione è a pagina piena): da lì sale il foglio di condivisione.
    static func inCima() -> UIViewController? {
        let finestra = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
        var c = finestra?.rootViewController
        while let p = c?.presentedViewController { c = p }
        return c
    }
}
#endif
