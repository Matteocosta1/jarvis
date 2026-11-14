#if os(iOS)
import Foundation
import UIKit

// MARK: - 14 nov · MANI SU TUTTO JARVIS
// Il signore (14 nov, 03:23: «ogni tasto di ogni sezione diventa un'azione che il cervello può fare a voce, in automatico… così
// smettono di esistere cose che lei vede ma che lui non sa fare»). Da solo, senza scrivere niente sezione per sezione: scorre la
// pagina davanti e scrive in ogni campo di testo che si vede (SwiftUI li costruisce su UIScrollView e UITextField, che l'app può
// toccare). I tasti di SwiftUI invece iOS li descrive solo alle tecnologie d'accessibilità: provato nel simulatore il 14 nov
// (VoiceOver spento: 0 tasti letti), quindi «tocca» vale solo quando la descrizione c'è (VoiceOver acceso); i tasti a voce li fa la
// regia, sezione per sezione.

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

    // MARK: Lo strumento del cervello

    /// Lo strumento «mano» com'è descritto al cervello (`strumenti_client_def`, senza ripubblicare il cervello).
    static let definizione: [String: Any] = [
        "name": "mano",
        "description": "Le mani di JARVIS sull'app, quando la regia non ha l'azione: scorre la pagina davanti (scorri: verso su, giu, cima, fondo), scrive in qualsiasi campo di testo che si vede (scrivi: testo, campo facoltativo, invia=true per mandarlo) e, solo se nella riga [Schermo] c'è TASTI, preme un tasto (tocca: tasto = nome o T-numero). Mandare, eliminare, pubblicare, chiamare, pagare aspettano il sì: chiedilo e richiama con confermato=true. Ti torna com'è andata: controlla.",
        "input_schema": [
            "type": "object",
            "properties": [
                "azione": ["type": "string", "enum": ["tocca", "scorri", "scrivi"]],
                "tasto": ["type": "string", "description": "Il nome del tasto com'è nei TASTI, o il suo T-numero"],
                "verso": ["type": "string", "enum": ["su", "giu", "cima", "fondo"]],
                "testo": ["type": "string", "description": "Cosa scrivere"],
                "campo": ["type": "string", "description": "In quale campo (se ce n'è più d'uno)"],
                "invia": ["type": "boolean", "description": "Scritto il testo, lo manda (come il tasto invio)"],
                "confermato": ["type": "boolean", "description": "Solo dopo il sì del signore alla tua domanda"],
            ] as [String: Any],
            "required": ["azione"],
        ] as [String: Any],
    ]

    /// Lo strumento «schermo»: com'è adesso l'app, per controllare un passo appena fatto (le richieste che continuano un lavoro
    /// non portano la riga [Schermo]).
    static let definizioneSchermo: [String: Any] = [
        "name": "schermo",
        "description": "Com'è adesso lo schermo dell'app: la sezione davanti con cosa mostra e le sue azioni, i TASTI che si vedono, quelle dietro, FILO e il piano in corso. Usalo per controllare un passo appena fatto, prima di andare avanti.",
        "input_schema": ["type": "object", "properties": [String: Any]()] as [String: Any],
    ]

    /// Il tasto rischioso premuto in attesa del sì, e quando l'ha chiesto.
    private static var inSospeso: (chiave: String, quando: Date)?
    /// 14 nov: un tasto rischioso aspetta il sì.
    static var aspettaIlSi: Bool { inSospeso.map { Date().timeIntervalSince($0.quando) < 180 } ?? false }

    /// I tasti che vogliono il sì del signore: inviare, eliminare, pubblicare, chiamare, pagare, uscire da un account.
    static func rischioso(_ etichetta: String) -> Bool {
        let parole = Set(FineFrase.paroleNude(etichetta).map { Regia.chiave($0) })
        let rischio: Set<String> = ["invia", "inviare", "inviala", "invialo", "manda", "mandalo", "mandala", "spedisci", "pubblica", "pubblicalo",
                                    "elimina", "eliminare", "cancella", "rimuovi", "svuota", "pulisci", "butta", "azzera", "resetta", "reimposta",
                                    "chiama", "telefona", "videochiama", "paga", "acquista", "compra", "ordina", "disconnetti", "scollega",
                                    "revoca", "esci", "condividi", "send", "delete", "remove", "call", "pay", "buy", "logout", "trash"]
        return !parole.isDisjoint(with: rischio)
    }

    /// Esegue lo strumento «mano».
    static func esegui(_ i: [String: Any]) async -> (String, Bool) {
        switch Regia.chiave(i["azione"] as? String ?? "tocca") {
        case "scorri": return scorri(i["verso"] as? String ?? "giu")
        case "scrivi": return await scrivi(i)
        default: return await tocca(i)
        }
    }

    private static func tocca(_ i: [String: Any]) async -> (String, Bool) {
        let detto = (i["tasto"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detto.isEmpty else { return (Regia.json(["errore": "quale tasto? (nome o T-numero)"]), true) }
        let tasti = leggi()
        guard let t = trova(detto, in: tasti) else {
            return (Regia.json(["errore": "nessun tasto «\(detto)» sullo schermo", "tasti": elenco(tasti, massimo: 40)]), true)
        }
        let chiave = Regia.chiave(t.etichetta)
        if rischioso(t.etichetta) {
            if i["confermato"] as? Bool == true {
                guard let s = inSospeso, s.chiave == chiave, Date().timeIntervalSince(s.quando) < 180,
                      let f = Regia.condivisa.ultimaFrase?(), f.quando > s.quando, Regia.eAssenso(f.testo) else {
                    inSospeso = nil
                    return (Regia.json(["errore": "conferma non valida: chiedi al signore con una domanda breve e aspetta il suo sì (lo controlla l'app)"]), true)
                }
                inSospeso = nil
            } else {
                inSospeso = (chiave, Date())
                return (Regia.json(["aspetta_il_si": "«\(t.etichetta)»", "nota": "chiedi conferma al signore con una domanda breve; se dice sì richiama mano con lo stesso tasto e confermato=true"]), false)
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var fatto = t.oggetto.accessibilityActivate()
        if !fatto, let c = t.oggetto as? UIControl { c.sendActions(for: .touchUpInside); fatto = true }
        guard fatto else { return (Regia.json(["errore": "il tasto «\(t.etichetta)» non si lascia premere da qui"]), true) }
        Regia.condivisa.evento("premuto «\(t.etichetta)»")
        try? await Task.sleep(for: .milliseconds(450))                 // la sezione risponde (si apre, cambia scheda…)
        return (Regia.json(["fatto": "premuto «\(t.etichetta)»", "schermo": Regia.condivisa.catalogo(rigaVecchia: Regia.condivisa.rigaVecchia?())]), false)
    }

    /// Il tasto detto: il T-numero, il nome esatto, poi il nome che comincia o contiene quelle parole.
    static func trova(_ detto: String, in tasti: [Tasto]) -> Tasto? {
        let d = detto.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.uppercased().hasPrefix("T"), Int(d.dropFirst()) != nil, let t = tasti.first(where: { $0.id.caseInsensitiveCompare(d) == .orderedSame }) { return t }
        let k = Regia.chiave(d)
        guard !k.isEmpty else { return nil }
        if let t = tasti.first(where: { Regia.chiave($0.etichetta) == k }) { return t }
        let candidati = tasti.filter { Regia.chiave($0.etichetta).hasPrefix(k) || Regia.chiave($0.etichetta).contains(k) }
        return candidati.count == 1 ? candidati[0] : candidati.first { Regia.chiave($0.etichetta).hasPrefix(k) }
    }

    /// I tasti per il cervello, in una riga: «T1 «CELLA» sel · T2 «GLOBO» · T3 «Chiudi»».
    static func elenco(_ tasti: [Tasto], massimo: Int) -> String {
        tasti.prefix(massimo).map { t in
            var e = t.etichetta.count > 28 ? String(t.etichetta.prefix(28)) + "…" : t.etichetta
            if let v = t.valore, !v.isEmpty, v != e { e += " = " + (v.count > 18 ? String(v.prefix(18)) + "…" : v) }
            return "\(t.id) «\(e)»" + (t.selezionato ? " sel" : "") + (t.tipo == "tasto" ? "" : " (\(t.tipo))") + (rischioso(t.etichetta) ? "*" : "")
        }.joined(separator: " · ")
    }

    /// La riga TASTI per [Schermo] (vuota sulla schermata di JARVIS: lì ci sono la corona e la regia).
    static func perCervello() -> String? {
        // senza una tecnologia d'accessibilità accesa iOS non descrive i tasti di SwiftUI (prova del 14 nov): niente giro a vuoto
        guard UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning else { return nil }
        let tasti = leggi()
        guard !tasti.isEmpty else { return nil }
        return "TASTI (strumento mano; * = serve il sì): " + elenco(tasti, massimo: 45)
    }

    // MARK: Scorrere e scrivere (le viste di UIKit sotto SwiftUI)

    private static func scorri(_ verso: String) -> (String, Bool) {
        guard let dove = scorriSubito(verso) else { return (Regia.json(["errore": "qui non c'è niente da scorrere"]), true) }
        return (Regia.json(["fatto": "pagina \(dove)"]), false)
    }

    /// 14 nov · le mani subito («scendi», «torna su», «in fondo»: la regia, senza cervello): scorre la pagina davanti e dice dove è
    /// arrivata («in cima», «in fondo», «a metà (40%)», «tutta visibile»). Nil: qui non c'è niente da scorrere.
    static func scorriSubito(_ verso: String) -> String? {
        guard let w = finestra, let sv = pagina(in: w) else { return nil }
        let alto = sv.bounds.height - sv.adjustedContentInset.top - sv.adjustedContentInset.bottom
        let minimo = -sv.adjustedContentInset.top
        let massimo = max(minimo, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
        var y = sv.contentOffset.y
        switch Regia.chiave(verso) {
        case "su", "sopra", "indietro": y -= alto * 0.8
        case "cima", "inizio", "inalto": y = minimo
        case "fondo", "fine", "inbasso": y = massimo
        default: y += alto * 0.8
        }
        y = min(massimo, max(minimo, y))
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: y), animated: true)
        return massimo <= minimo ? "tutta visibile" : y <= minimo + 2 ? "in cima" : y >= massimo - 2 ? "in fondo" : "a metà (\(Int((y - minimo) / (massimo - minimo) * 100))%)"
    }

    /// La pagina da scorrere: la vista che scorre più grande che si vede (non quelle piccole, come la lista di FILO).
    private static func pagina(in w: UIWindow) -> UIScrollView? {
        var migliore: (UIScrollView, CGFloat)?
        func cerca(_ v: UIView) {
            guard !v.isHidden, v.alpha > 0.02 else { return }
            if let sv = v as? UIScrollView, !(sv is UITextView), sv.isScrollEnabled, sv.bounds.width >= 240,
               sv.contentSize.height > sv.bounds.height + 8 {
                let r = sv.convert(sv.bounds, to: w).intersection(w.bounds)
                let area = r.isNull ? 0 : r.width * r.height
                if area > (migliore?.1 ?? 0) * 0.98 { migliore = (sv, area) }      // a parità, quella sopra (vista dopo)
            }
            for s in v.subviews { cerca(s) }
        }
        cerca(w)
        return migliore?.0
    }

    private static func scrivi(_ i: [String: Any]) async -> (String, Bool) {
        let testo = (i["testo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testo.isEmpty else { return (Regia.json(["errore": "cosa scrivo?"]), true) }
        guard let w = finestra else { return (Regia.json(["errore": "nessuna finestra"]), true) }
        var campi: [UITextField] = []
        func cerca(_ v: UIView) {
            guard !v.isHidden, v.alpha > 0.02 else { return }
            if let f = v as? UITextField, f.isEnabled, f.convert(f.bounds, to: w).intersects(w.bounds) { campi.append(f) }
            for s in v.subviews { cerca(s) }
        }
        cerca(w)
        guard !campi.isEmpty else { return (Regia.json(["errore": "qui non c'è un campo dove scrivere"]), true) }
        let detto = Regia.chiave(i["campo"] as? String ?? "")
        let campo = campi.first { f in !detto.isEmpty && (Regia.chiave(f.placeholder ?? "").contains(detto) || Regia.chiave(f.accessibilityLabel ?? "").contains(detto)) }
            ?? campi.first { $0.isFirstResponder } ?? campi.last!
        _ = campo.becomeFirstResponder()
        if let tutto = campo.textRange(from: campo.beginningOfDocument, to: campo.endOfDocument) { campo.replace(tutto, withText: testo) }
        else { campo.insertText(testo) }
        let nome = campo.placeholder ?? campo.accessibilityLabel ?? "il campo"
        Regia.condivisa.evento("scritto in «\(nome)»")
        guard i["invia"] as? Bool == true else {
            return (Regia.json(["fatto": "scritto «\(testo.prefix(60))» in «\(nome)»"]), false)
        }
        // mandare un messaggio, una risposta, un commento: prima il sì (cercare, invece, parte subito)
        let k = Regia.chiave(nome)
        if rischioso(nome) || ["messaggio", "rispost", "rispondi", "commento", "didascalia", "mail", "scrivia"].contains(where: { k.contains($0) }) {
            let chiave = "scrivi:" + k
            if i["confermato"] as? Bool == true, let s = inSospeso, s.chiave == chiave, Date().timeIntervalSince(s.quando) < 180,
               let f = Regia.condivisa.ultimaFrase?(), f.quando > s.quando, Regia.eAssenso(f.testo) {
                inSospeso = nil
            } else {
                inSospeso = (chiave, Date())
                return (Regia.json(["scritto": "«\(testo.prefix(60))» in «\(nome)»", "aspetta_il_si": "mandarlo",
                                    "nota": "chiedi al signore se lo mandi; se dice sì richiama mano scrivi con lo stesso testo, invia=true e confermato=true"]), false)
            }
        }
        _ = campo.delegate?.textFieldShouldReturn?(campo)                // come il tasto invio (onSubmit di SwiftUI)
        Regia.condivisa.evento("mandato «\(nome)»")
        return (Regia.json(["fatto": "scritto «\(testo.prefix(60))» in «\(nome)» e mandato"]), false)
    }
}
#endif
