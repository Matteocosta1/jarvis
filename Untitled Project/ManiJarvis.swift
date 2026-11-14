#if os(iOS)
import Foundation
import UIKit

// MARK: - 14 nov · MANI SU TUTTO JARVIS
// Il signore (14 nov, 03:23: «ogni tasto di ogni sezione diventa un'azione che il cervello può fare a voce, in automatico… così
// smettono di esistere cose che lei vede ma che lui non sa fare»). JARVIS legge i tasti che sono davvero sullo schermo dalla
// stessa descrizione che iOS prepara per l'accessibilità (nome, tipo, se è selezionato, dove sta) e li preme come li preme
// VoiceOver: nessun tasto da scrivere a mano, quelli nuovi arrivano da soli.

@MainActor
enum ManiJarvis {
    struct Tasto {
        /// «T1», «T2»… nell'ordine di lettura (dall'alto, da sinistra).
        let id: String
        let etichetta: String
        let valore: String?
        /// tasto, interruttore, regolabile, link, scheda
        let tipo: String
        let selezionato: Bool
        /// Dove sta sullo schermo (coordinate dello schermo).
        let cornice: CGRect
        let oggetto: NSObject
    }

    /// La finestra dell'app davanti.
    static var finestra: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow } ?? FasciaAlta.finestra
    }

    /// I tasti che si vedono adesso, dall'alto in basso.
    static func leggi() -> [Tasto] {
        guard let w = finestra else { return [] }
        var trovati: [(NSObject, CGRect)] = []
        var visti = Set<ObjectIdentifier>()
        visita(w, profondita: 0, schermo: w.screen.bounds, trovati: &trovati, visti: &visti)
        let ordinati = trovati.sorted { a, b in
            abs(a.1.minY - b.1.minY) > 6 ? a.1.minY < b.1.minY : a.1.minX < b.1.minX
        }
        var out: [Tasto] = []
        for (o, r) in ordinati {
            let t = o.accessibilityTraits
            let etichetta = (o.accessibilityLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let valore = o.accessibilityValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !etichetta.isEmpty || !(valore ?? "").isEmpty else { continue }
            let tipo: String
            if t.contains(.adjustable) { tipo = "regolabile" }
            else if t.contains(.link) { tipo = "link" }
            else if t.contains(.tabBar) { tipo = "scheda" }
            else if t.contains(.toggleButton) { tipo = "interruttore" }
            else { tipo = "tasto" }
            out.append(Tasto(id: "T\(out.count + 1)", etichetta: etichetta, valore: (valore?.isEmpty ?? true) ? nil : valore, tipo: tipo,
                             selezionato: t.contains(.selected), cornice: r, oggetto: o))
        }
        return out
    }

    /// Un elemento che si preme (o si regola) e che si vede sullo schermo.
    private static func premibile(_ o: NSObject) -> Bool {
        let t = o.accessibilityTraits
        if t.contains(.notEnabled) { return false }
        if t.contains(.button) || t.contains(.link) || t.contains(.adjustable) || t.contains(.tabBar) { return true }
        if t.contains(.toggleButton) { return true }
        return false
    }

    private static func visita(_ o: NSObject, profondita: Int, schermo: CGRect, trovati: inout [(NSObject, CGRect)],
                               visti: inout Set<ObjectIdentifier>) {
        guard profondita < 64, trovati.count < 400, visti.insert(ObjectIdentifier(o)).inserted else { return }
        if let v = o as? UIView {
            if v.isHidden || v.alpha < 0.02 || v.window == nil { return }
        }
        if o.accessibilityElementsHidden { return }
        if o.isAccessibilityElement {
            if premibile(o) {
                let r = o.accessibilityFrame
                if r.width > 1, r.height > 1, r.intersects(schermo) { trovati.append((o, r)) }
            }
            return
        }
        // un contenitore: i suoi elementi (SwiftUI li descrive così), oppure le viste dentro
        if let elementi = o.accessibilityElements, !elementi.isEmpty {
            for e in elementi { if let e = e as? NSObject { visita(e, profondita: profondita + 1, schermo: schermo, trovati: &trovati, visti: &visti) } }
            return
        }
        let n = o.accessibilityElementCount()
        if n != NSNotFound, n > 0 {
            for k in 0..<min(n, 300) {
                if let e = o.accessibilityElement(at: k) as? NSObject { visita(e, profondita: profondita + 1, schermo: schermo, trovati: &trovati, visti: &visti) }
            }
            return
        }
        if let v = o as? UIView {
            for s in v.subviews { visita(s, profondita: profondita + 1, schermo: schermo, trovati: &trovati, visti: &visti) }
        }
    }

    #if DEBUG
    /// Solo nella versione di prova (simulatore, -provaMani): scrive i tasti letti e prova a premerne uno, per vedere se iOS
    /// descrive i tasti di SwiftUI anche senza VoiceOver acceso.
    static func prova(tocca etichetta: String?) async {
        let cartella = FileManager.default.temporaryDirectory
        func scrivi(_ nome: String, _ tasti: [Tasto], extra: [String: Any] = [:]) {
            var d: [String: Any] = extra
            d["quanti"] = tasti.count
            d["tasti"] = tasti.map { t -> [String: Any] in
                ["id": t.id, "etichetta": t.etichetta, "valore": t.valore ?? "", "tipo": t.tipo, "sel": t.selezionato,
                 "x": Int(t.cornice.minX), "y": Int(t.cornice.minY), "w": Int(t.cornice.width), "h": Int(t.cornice.height),
                 "classe": String(describing: type(of: t.oggetto))]
            }
            if let j = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted]) {
                try? j.write(to: cartella.appendingPathComponent(nome))
            }
        }
        let prima = leggi()
        var esito: [String: Any] = ["voiceover": UIAccessibility.isVoiceOverRunning]
        if let etichetta, let t = prima.first(where: { $0.etichetta.localizedCaseInsensitiveCompare(etichetta) == .orderedSame }) {
            esito["toccato"] = t.etichetta
            esito["attivato"] = t.oggetto.accessibilityActivate()
        }
        scrivi("mani1.json", prima, extra: esito)
        try? await Task.sleep(for: .seconds(2))
        scrivi("mani2.json", leggi())
    }
    #endif
}
#endif
