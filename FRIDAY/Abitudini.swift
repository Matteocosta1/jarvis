#if os(iOS)
import Foundation

// MARK: - 12.0 (12) · B6 · LE ABITUDINI DEL SIGNORE
//
// Come un amico che ti conosce: JARVIS si accorge di quello che il signore fa di solito a una certa ora (la sezione che apre,
// la musica che mette) e, al momento giusto, lo propone una volta sola: «Le metto la solita playlist, Sir?». Un sì lo fa subito
// (Regia.proposta, senza cervello). Resta sul telefono: non va al cervello e non esce mai di qui.
// Regole: almeno 3 giorni diversi nelle ultime 3 settimane, entro un'ora da adesso, stesso tipo di giorno (feriale o festivo);
// non se l'ha già fatto oggi; ogni abitudine al massimo una volta al giorno e al massimo due proposte al giorno; mai di notte.

@MainActor
enum Abitudini {
    private struct Evento: Codable {
        let tipo: String       // "sezione", "musica", "playlist"
        let cosa: String
        let quando: Date
    }

    struct Previsione {
        let tipo: String
        let cosa: String
        let giorni: Int
    }

    private static let chiaveEventi = "abitudini.eventi"
    private static let chiaveProposte = "abitudini.proposte"
    private static var eventi: [Evento] = {
        guard let d = UserDefaults.standard.data(forKey: chiaveEventi), let e = try? JSONDecoder().decode([Evento].self, from: d) else { return [] }
        return e
    }()

    /// Una cosa fatta adesso (la sezione aperta davanti, la musica messa).
    static func segna(_ tipo: String, _ cosa: String) {
        let c = cosa.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        // la stessa cosa nei 20 minuti dopo conta una volta sola
        if let u = eventi.last(where: { $0.tipo == tipo && $0.cosa.lowercased() == c.lowercased() }), Date().timeIntervalSince(u.quando) < 1200 { return }
        eventi.append(Evento(tipo: tipo, cosa: c, quando: Date()))
        if eventi.count > 500 { eventi.removeFirst(eventi.count - 500) }
        if let d = try? JSONEncoder().encode(eventi) { UserDefaults.standard.set(d, forKey: chiaveEventi) }
    }

    /// Quello che di solito fa a quest'ora (nil: niente di abbastanza abituale, già fatto o già proposto oggi).
    static func previsione(adesso: Date = Date()) -> Previsione? {
        let cal = Calendar.current
        let ora = cal.component(.hour, from: adesso)
        guard ora >= 7, ora < 23 else { return nil }                                    // mai di notte
        let proposte = proposteDi(oggi: adesso)
        guard proposte.count < 2 else { return nil }                                    // al massimo due al giorno
        func minuti(_ d: Date) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
        let adessoMin = minuti(adesso)
        let da = adesso.addingTimeInterval(-21 * 86_400)
        let oggi = cal.startOfDay(for: adesso)
        let festivo = cal.isDateInWeekend(adesso)
        var giorni: [String: Set<Date>] = [:]
        var nomi: [String: (tipo: String, cosa: String)] = [:]
        var fatteOggi = Set<String>()
        for e in eventi where e.quando >= da {
            let k = e.tipo + "|" + e.cosa.lowercased()
            if e.quando >= oggi { fatteOggi.insert(k); continue }
            guard abs(minuti(e.quando) - adessoMin) <= 60, cal.isDateInWeekend(e.quando) == festivo else { continue }
            giorni[k, default: []].insert(cal.startOfDay(for: e.quando))
            nomi[k] = (e.tipo, e.cosa)
        }
        let candidate = giorni.filter { $0.value.count >= 3 && !fatteOggi.contains($0.key) && !proposte.contains($0.key) }
        guard let migliore = candidate.max(by: { $0.value.count < $1.value.count }), let n = nomi[migliore.key] else { return nil }
        return Previsione(tipo: n.tipo, cosa: n.cosa, giorni: migliore.value.count)
    }

    /// La proposta è stata fatta: non si ripete oggi.
    static func proposta(_ p: Previsione) {
        var tutte = (UserDefaults.standard.dictionary(forKey: chiaveProposte) as? [String: Date]) ?? [:]
        let da = Date().addingTimeInterval(-86_400 * 2)
        tutte = tutte.filter { $0.value > da }
        tutte[p.tipo + "|" + p.cosa.lowercased()] = Date()
        UserDefaults.standard.set(tutte, forKey: chiaveProposte)
    }

    private static func proposteDi(oggi: Date) -> Set<String> {
        let tutte = (UserDefaults.standard.dictionary(forKey: chiaveProposte) as? [String: Date]) ?? [:]
        let inizio = Calendar.current.startOfDay(for: oggi)
        return Set(tutte.filter { $0.value >= inizio }.keys)
    }

    /// Come si dice una sezione in una frase («la spesa», «il meteo», «la posta»).
    static func detta(_ sezione: String) -> String {
        let nomi: [String: String] = [
            "Spesa": "la spesa", "Email": "la posta", "Meteo": "il meteo", "Musica": "la musica", "Briefing": "il briefing", "Diario": "il diario",
            "Sonno": "il sonno", "Cuore": "il cuore", "Serata": "la serata", "Bea": "la scheda di Bea", "Satellite": "il satellite",
            "Ricordi": "i ricordi", "Messaggi": "i messaggi", "Telefono": "il telefono", "Foto": "le foto", "Vitals": "i Vitals",
            "Costi": "i costi", "Archivio": "l'archivio", "Sistemi": "i sistemi", "Impostazioni": "le impostazioni", "Shazam": "Shazam",
            "GitHub": "GitHub", "Supabase": "Supabase", "EDITH": "EDITH", "Sentinella": "la Sentinella", "Wiretap": "il Wiretap",
            "Interprete": "l'Interprete", "Trainer": "il Trainer", "LiDAR": "il LiDAR", "Scanner": "lo Scanner", "Occhi": "gli Occhi",
            "Cucina": "la Cucina", "Profiler": "il Profiler", "Confidente": "il Confidente", "Browser": "il Browser",
        ]
        return nomi[sezione] ?? sezione
    }
}
#endif
