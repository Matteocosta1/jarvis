import Foundation
import WatchKit

// MARK: - 14 nov · PIÙ PASSI SENZA GUIDA, al polso
// Come sull'iPhone (Piano.swift): il cervello dichiara il piano (strumento «piano»), fa un passo alla volta e ne segna l'esito.
// Lo schermo dell'orologio è piccolo: niente elenco, sotto il reattore una riga sola col passo in corso e il conto
// («PIANO 2/4 · Scrivo a Cristina»), e un tocco al polso a ogni passo fatto. Il piano va al cervello nella riga [Schermo].

@MainActor
final class PianoPolso {
    static let condiviso = PianoPolso()

    private struct Passo {
        var testo: String
        var stato: String          // da fare, in corso, fatto, errore, aspetta il sì
        var nota: String?
    }
    private var titolo = ""
    private var passi: [Passo] = []
    private var iniziato: Date?
    private var finito = false

    static let definizione: [String: Any] = [
        "name": "piano",
        "description": "Quando il signore ti affida un lavoro con più passi («fallo tu», «pensaci tu», «vedi tu»): prima piano(titolo, passi) coi passi in poche parole, e digli solo «Ci penso io»; poi un passo alla volta coi tuoi strumenti, e dopo ognuno piano(passo, stato, nota) controllando l'esito. Se un passo non va prova un'altra strada, o dillo. Un passo da confermare: stato=aspetta e chiedi il sì. Alla fine piano(fine=true) e una frase sola col risultato. Sull'orologio si vede il passo in corso sotto il reattore.",
        "input_schema": [
            "type": "object",
            "properties": [
                "titolo": ["type": "string", "description": "L'obiettivo in tre o quattro parole"],
                "passi": ["type": "array", "items": ["type": "string"] as [String: Any], "description": "I passi in ordine, al massimo 8"],
                "passo": ["type": "integer", "description": "Il numero del passo (da 1) di cui segni lo stato"],
                "stato": ["type": "string", "enum": ["in_corso", "fatto", "errore", "aspetta"]],
                "nota": ["type": "string", "description": "L'esito in breve"],
                "fine": ["type": "boolean", "description": "true quando l'obiettivo è raggiunto (o ti fermi)"],
            ] as [String: Any],
        ] as [String: Any],
    ]

    /// Esegue «piano»: la risposta per il cervello e la riga per sotto il reattore (nil: piano finito, la riga si toglie).
    func esegui(_ i: [String: Any]) -> (testo: String, errore: Bool, riga: String?) {
        if let nuovi = i["passi"] as? [Any], !nuovi.isEmpty {
            let testi = nuovi.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(8)
            guard !testi.isEmpty else { return (RegiaPolso.json(["errore": "passi vuoti"]), true, nil) }
            titolo = ((i["titolo"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            passi = testi.enumerated().map { k, t in Passo(testo: String(t.prefix(60)), stato: k == 0 ? "in corso" : "da fare", nota: nil) }
            iniziato = Date()
            finito = false
        }
        guard !passi.isEmpty else { return (RegiaPolso.json(["errore": "nessun piano: prima piano(titolo, passi)"]), true, nil) }
        if let n = (i["passo"] as? NSNumber)?.intValue ?? (i["passo"] as? String).flatMap({ Int($0) }) {
            guard passi.indices.contains(n - 1) else { return (RegiaPolso.json(["errore": "il piano ha \(passi.count) passi"]), true, nil) }
            let stato: String
            switch (i["stato"] as? String ?? "fatto").lowercased() {
            case "errore", "fallito", "no": stato = "errore"
            case "aspetta", "aspetta_il_si", "conferma": stato = "aspetta il sì"
            case "in_corso", "incorso", "via": stato = "in corso"
            default: stato = "fatto"
            }
            passi[n - 1].stato = stato
            if let nota = (i["nota"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !nota.isEmpty { passi[n - 1].nota = String(nota.prefix(70)) }
            if stato == "fatto" {
                WKInterfaceDevice.current().play(.click)                 // un passo fatto: un tocco al polso
                if passi.indices.contains(n), passi[n].stato == "da fare" { passi[n].stato = "in corso" }
            } else if stato == "errore" {
                WKInterfaceDevice.current().play(.retry)
            }
        }
        if i["fine"] as? Bool == true {
            finito = true
            for k in passi.indices where passi[k].stato == "in corso" { passi[k].stato = "da fare" }
            WKInterfaceDevice.current().play(passi.allSatisfy { $0.stato == "fatto" } ? .success : .stop)
        }
        return (RegiaPolso.json(["piano": perCervello ?? "", "nota": finito ? "piano chiuso: di' il risultato in una frase" : "vai avanti col passo in corso"]),
                false, finito ? nil : riga)
    }

    /// «PIANO 2/4 · Scrivo a Cristina»
    private var riga: String {
        let fatti = passi.filter { $0.stato == "fatto" }.count
        let ora = passi.first { $0.stato == "in corso" || $0.stato == "aspetta il sì" }
        return "\(min(fatti + 1, passi.count))/\(passi.count)" + (ora.map { " · " + $0.testo } ?? "")
    }

    /// La riga per il cervello (dentro [Schermo]).
    var perCervello: String? {
        guard !passi.isEmpty, let iniziato, Date().timeIntervalSince(iniziato) < 1200 else { return nil }
        let righe = passi.enumerated().map { k, p in "\(k + 1) \(p.stato): \(p.testo)" + (p.nota.map { " (\($0))" } ?? "") }
        return (finito ? "PIANO FINITO" : "PIANO IN CORSO") + (titolo.isEmpty ? "" : " «\(titolo)»") + ": " + righe.joined(separator: "; ")
    }
}
