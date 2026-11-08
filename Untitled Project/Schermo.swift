#if os(iOS)
import Foundation
import SwiftUI

// MARK: - 8 nov notte (il signore: «il commento vocale di JARVIS dice che il link è vuoto», con il link scritto in EDITH e il
// risultato «SEMBRA A POSTO» sullo schermo): JARVIS vede quello che vede il signore.
// Ogni sezione dice in una riga cosa mostra adesso (i campi scritti o incollati, la voce aperta, i risultati già comparsi).
// L'app la manda al cervello a ogni domanda (`schermo`), il cervello la mette nel contesto come [Schermo: …]: così «controlla il
// link», «è sicuro?», «leggimela», «mandalo» parlano di quello che c'è davanti, e JARVIS non risponde più che è vuoto.
// Vale solo la sezione davanti: quelle dietro (MARK XI) e quelle chiuse non contano. La password di EDITH non c'è mai.

/// Quello che il signore ha davanti nella sezione aperta.
enum Schermo {
    private struct Riga {
        var testo: String
        var davanti: Bool
        var ordine: Int
    }
    private static var righe: [UUID: Riga] = [:]
    private static var contatore = 0

    /// La riga da mandare al cervello: la sezione davanti più recente. Senza riga propria, almeno il nome della sezione aperta.
    static func perCervello(sezione: Reparto?) -> String? {
        guard let sezione else { return nil }            // sulla schermata principale non c'è niente da vedere
        let davanti = righe.values.filter { $0.davanti && !$0.testo.isEmpty }.max { $0.ordine < $1.ordine }
        return davanti?.testo ?? "Sezione \(sezione.rawValue) aperta."
    }

    /// Una sezione (o un pezzo di sezione, come il lettore della posta) dice cosa mostra.
    fileprivate static func metti(_ chiave: UUID, testo: String, davanti: Bool) {
        var ordine = righe[chiave]?.ordine ?? 0
        if righe[chiave]?.davanti != davanti || ordine == 0 {      // appena arrivata davanti: diventa la più recente
            contatore += 1
            ordine = contatore
        }
        righe[chiave] = Riga(testo: testo, davanti: davanti, ordine: ordine)
    }

    fileprivate static func togli(_ chiave: UUID) { righe[chiave] = nil }

    /// Un valore scritto dal signore, tra virgolette e tagliato se lunghissimo (un SMS incollato resta intero fino a 600 caratteri).
    static func campo(_ nome: String, _ valore: String, massimo: Int = 600) -> String? {
        let v = valore.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        return "\(nome): «\(v.count > massimo ? String(v.prefix(massimo)) + "…" : v)»"
    }

    /// Un risultato del cervello già mostrato, in JSON compatto (tagliato se lunghissimo).
    static func esito(_ d: [String: Any], massimo: Int = 700) -> String {
        guard JSONSerialization.isValidJSONObject(d),
              let dati = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
        let s = String(decoding: dati, as: UTF8.self)
        return s.count > massimo ? String(s.prefix(massimo)) + "…" : s
    }

    /// Le righe di una sezione in una sola: «Sezione X. A · B · C».
    static func unisci(_ sezione: String, _ pezzi: [String?]) -> String {
        let dentro = pezzi.compactMap { $0 }.filter { !$0.isEmpty }
        return dentro.isEmpty ? "Sezione \(sezione)." : "Sezione \(sezione). " + dentro.joined(separator: " · ")
    }
}

/// Tiene aggiornata la riga della sezione: quando cambia il testo, quando va dietro o torna davanti, quando si chiude.
private struct PubblicaSchermo: ViewModifier {
    let testo: String
    @Environment(\.sezioneDietro) private var dietro
    @State private var chiave = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { Schermo.metti(chiave, testo: testo, davanti: !dietro) }
            .onChange(of: testo) { _, nuovo in Schermo.metti(chiave, testo: nuovo, davanti: !dietro) }
            .onChange(of: dietro) { _, d in Schermo.metti(chiave, testo: testo, davanti: !d) }
            .onDisappear { Schermo.togli(chiave) }
    }
}

extension View {
    /// La sezione dice a JARVIS cosa mostra adesso (vedi `Schermo`).
    func sulloSchermo(_ testo: String) -> some View { modifier(PubblicaSchermo(testo: testo)) }
}
#endif
