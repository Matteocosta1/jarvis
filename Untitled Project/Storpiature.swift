import Foundation

/// Il dizionario personale dei comandi: come il riconoscimento vocale storpia le frasi del signore.
/// Quando un comando detto a voce non viene capito qui ma il cervello capisce che era un comando (strumento «comando_app»),
/// la frase così come è stata sentita viene imparata: la volta dopo il comando parte subito, senza passare dal cervello.
/// Tutto resta sul dispositivo (iPhone o Mac), niente rete. Valori: «rito» oppure il nome di un reparto («diario», «sentinella»…).
enum Storpiature {
    private static let chiave = "storpiature"
    private static let richiami: Set<String> = ["jarvis", "giarvis", "jervis", "ehi", "hey", "ok"]

    /// Minuscole, senza accenti né punteggiatura, senza «Jarvis» davanti: così «Jarvis, backup Daddy!» e «backup daddy» sono la stessa frase.
    static func normalizza(_ frase: String) -> String {
        frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
            .filter { !richiami.contains($0) }
            .joined(separator: " ")
    }

    static var tutte: [String: String] {
        UserDefaults.standard.dictionary(forKey: chiave) as? [String: String] ?? [:]
    }

    /// Segna la frase sentita come quel comando (solo frasi brevi: un comando, non un discorso).
    static func impara(_ frase: String, comando: String) {
        let f = normalizza(frase)
        guard f.count >= 3, f.count <= 40 else { return }
        var d = tutte
        d[f] = comando
        while d.count > 300, let via = d.keys.first { d[via] = nil }    // un tetto, per non crescere all'infinito
        UserDefaults.standard.set(d, forKey: chiave)
    }

    /// Il comando per questa frase: una frase già imparata, uguale o quasi (al massimo una lettera su cinque diversa).
    static func cerca(_ frase: String) -> String? {
        let f = normalizza(frase)
        guard f.count >= 3, f.count <= 40 else { return nil }
        let d = tutte
        if let c = d[f] { return c }
        var migliore: (comando: String, scarto: Double)?
        for (nota, comando) in d {
            let lunga = max(nota.count, f.count)
            guard lunga >= 6, abs(nota.count - f.count) * 4 <= lunga else { continue }
            let scarto = Double(distanza(Array(nota), Array(f))) / Double(lunga)
            if scarto <= 0.2, scarto < (migliore?.scarto ?? 1) { migliore = (comando, scarto) }
        }
        return migliore?.comando
    }

    /// Quante lettere vanno cambiate per passare da una frase all'altra (distanza di Levenshtein).
    private static func distanza(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prima = Array(0...b.count)
        var ora = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            ora[0] = i
            for j in 1...b.count {
                ora[j] = min(prima[j] + 1, ora[j - 1] + 1, prima[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prima, &ora)
        }
        return prima[b.count]
    }
}
