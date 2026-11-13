import Foundation
import HealthKit

/// I numeri della salute per Vitals, letti direttamente dall'app Salute (iPhone e Apple Watch, stesso file, due target).
/// - `giorni(_:)`: per ogni giorno sonno (della notte che finisce quel mattino), battito a riposo, passi e calorie attive.
/// - `SaluteOggi`: la fotografia di oggi, presa dal riepilogo di Benessere (sonno con le fasi, battito, passi, allenamenti).
/// Solo lettura: JARVIS non scrive mai nulla in Salute.
nonisolated enum SaluteStorica {
    nonisolated private static let negozio = HKHealthStore()

    struct Valori: Sendable {
        var sonnoOre: Double?
        var battito: Double?
        var passi: Double?
        var calorie: Double?
    }

    static func giorni(_ quanti: Int) async -> [Date: Valori] {
        guard HKHealthStore.isHealthDataAvailable() else { return [:] }
        let tipi: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate),
                                       HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned)]
        try? await negozio.requestAuthorization(toShare: [], read: tipi)
        let cal = Calendar.current
        let oggi = cal.startOfDay(for: Date())
        guard let inizio = cal.date(byAdding: .day, value: -quanti, to: oggi) else { return [:] }

        async let battiti = statistica(HKQuantityType(.restingHeartRate), .discreteAverage, da: inizio, unita: HKUnit.count().unitDivided(by: .minute()))
        async let passi = statistica(HKQuantityType(.stepCount), .cumulativeSum, da: inizio, unita: .count())
        async let calorie = statistica(HKQuantityType(.activeEnergyBurned), .cumulativeSum, da: inizio, unita: .kilocalorie())
        async let sonno = sonnoPerNotte(da: inizio.addingTimeInterval(-12 * 3600))

        var out: [Date: Valori] = [:]
        for (d, v) in await battiti { out[d, default: Valori()].battito = v }
        for (d, v) in await passi where v > 0 { out[d, default: Valori()].passi = v }
        for (d, v) in await calorie where v > 0 { out[d, default: Valori()].calorie = v }
        for (d, v) in await sonno where v > 0 { out[d, default: Valori()].sonnoOre = v }
        return out
    }

    /// Un valore al giorno (media o somma), con le statistiche di HealthKit (niente doppioni tra iPhone e orologio).
    private static func statistica(_ tipo: HKQuantityType, _ opzione: HKStatisticsOptions, da: Date, unita: HKUnit) async -> [Date: Double] {
        let cal = Calendar.current
        let ancora = cal.startOfDay(for: Date())
        return await withCheckedContinuation { (c: CheckedContinuation<[Date: Double], Never>) in
            let q = HKStatisticsCollectionQuery(quantityType: tipo, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: da, end: Date()),
                                                options: opzione, anchorDate: ancora, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, risultati, _ in
                var out: [Date: Double] = [:]
                risultati?.enumerateStatistics(from: da, to: Date()) { s, _ in
                    let q = opzione == .cumulativeSum ? s.sumQuantity() : s.averageQuantity()
                    if let v = q?.doubleValue(for: unita) { out[cal.startOfDay(for: s.startDate)] = v }
                }
                c.resume(returning: out)
            }
            negozio.execute(q)
        }
    }

    /// Ore dormite per notte, assegnate al giorno del risveglio. Se c'è l'orologio, contano solo i suoi dati.
    private static func sonnoPerNotte(da: Date) async -> [Date: Double] {
        let campioni: [HKCategorySample] = await withCheckedContinuation { (c: CheckedContinuation<[HKCategorySample], Never>) in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: da, end: Date()),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                c.resume(returning: s as? [HKCategorySample] ?? [])
            }
            negozio.execute(q)
        }
        let addormentato: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let dormito = campioni.filter { addormentato.contains($0.value) }
        let daOrologio = dormito.filter { ($0.sourceRevision.productType ?? "").hasPrefix("Watch") }
        let scelti = daOrologio.isEmpty ? dormito : daOrologio
        let cal = Calendar.current
        var perGiorno: [Date: [HKCategorySample]] = [:]
        for s in scelti { perGiorno[cal.startOfDay(for: s.endDate), default: []].append(s) }
        return perGiorno.mapValues { unione($0) / 3600 }
    }

    /// 11.0 (4), per l'ologramma del Sonno sull'orologio: la notte scorsa a tratti (da, a, fase: 0 sveglio, 1 REM, 2 leggero,
    /// 3 profondo), dalle 18 di ieri alle 10 di oggi. Se c'è l'orologio, solo i suoi dati (come la scheda Sonno dell'iPhone).
    static func notte() async -> [(Date, Date, Int)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        try? await negozio.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
        let oggi = Calendar.current.startOfDay(for: Date())
        let da = oggi.addingTimeInterval(-6 * 3600), a = oggi.addingTimeInterval(10 * 3600)
        let campioni: [HKCategorySample] = await withCheckedContinuation { (c: CheckedContinuation<[HKCategorySample], Never>) in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: da, end: a),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                c.resume(returning: s as? [HKCategorySample] ?? [])
            }
            negozio.execute(q)
        }
        let daOrologio = campioni.filter { ($0.sourceRevision.productType ?? "").hasPrefix("Watch") }
        return (daOrologio.isEmpty ? campioni : daOrologio).compactMap { s -> (Date, Date, Int)? in
            switch s.value {
            case HKCategoryValueSleepAnalysis.awake.rawValue: return (s.startDate, s.endDate, 0)
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return (s.startDate, s.endDate, 1)
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return (s.startDate, s.endDate, 2)
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return (s.startDate, s.endDate, 3)
            default: return nil                                    // «a letto» non è sonno
            }
        }
    }

    /// Secondi coperti da intervalli che possono sovrapporsi, contati una volta sola.
    private static func unione(_ campioni: [HKCategorySample]) -> TimeInterval {
        let ordinati = campioni.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var totale: TimeInterval = 0
        var corrente: (Date, Date)?
        for (i, f) in ordinati {
            if let c = corrente, i <= c.1 { corrente = (c.0, max(c.1, f)) }
            else { if let c = corrente { totale += c.1.timeIntervalSince(c.0) }; corrente = (i, f) }
        }
        if let c = corrente { totale += c.1.timeIntervalSince(c.0) }
        return totale
    }
}

/// La fotografia di oggi, letta dal JSON del riepilogo di Benessere.
struct SaluteOggi {
    var sonno: String?
    var fasi: String?
    var orari: String?
    var notaSonno: String?
    var pisolini: String?          // «14:30 → 18:30 (3 h 30 min)», se oggi ha riposato di pomeriggio
    var riposoTotale: String?      // notte + pisolini
    var battito: Int?
    var battitoMedia: Int?
    var passi: Int?
    var calorie: Int?
    var allenamenti: [String] = []

    static func leggi() async -> SaluteOggi? {
        let (testo, errore) = await Benessere.riepilogo(giorni: 2)
        guard !errore, let d = testo.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        var s = SaluteOggi()
        if let sonno = o["sonno"] as? [String: Any] {
            s.sonno = sonno["totale"] as? String
            s.notaSonno = sonno["nota"] as? String
            let fasi = [("profondo", "profondo"), ("rem", "REM"), ("leggero", "leggero")].compactMap { k, nome in (sonno[k] as? String).map { "\(nome) \($0)" } }
            if !fasi.isEmpty { s.fasi = fasi.joined(separator: " · ") }
            if let a = sonno["addormentato_alle"] as? String, let b = sonno["sveglio_alle"] as? String { s.orari = "\(a) → \(b)" }
        }
        let sonnellini = (o["pisolini_oggi"] as? [[String: Any]] ?? []).compactMap { p -> String? in
            guard let da = p["da"] as? String, let a = p["a"] as? String, let d = p["durata"] as? String else { return nil }
            return "\(da) → \(a) (\(d))"
        }
        if !sonnellini.isEmpty { s.pisolini = sonnellini.joined(separator: " · ") }
        s.riposoTotale = o["riposo_totale_oggi"] as? String
        if let b = o["battito_a_riposo"] as? [String: Any] {
            s.battito = (b["ultimo"] as? NSNumber)?.intValue
            s.battitoMedia = (b["media_7_giorni"] as? NSNumber)?.intValue
        }
        s.passi = ((o["passi"] as? [String: Any])?["oggi_finora"] as? NSNumber)?.intValue
        s.calorie = ((o["calorie_attive_kcal"] as? [String: Any])?["oggi_finora"] as? NSNumber)?.intValue
        s.allenamenti = (o["allenamenti"] as? [[String: Any]] ?? []).prefix(3).map { w in
            [w["tipo"] as? String, w["quando"] as? String, w["durata"] as? String].compactMap { $0 }.joined(separator: " · ")
        }
        return s
    }
}

// MARK: - I dati, letti dal JSON del cervello

struct DatiVitals {
    struct Giorno: Identifiable {
        let data: Date
        let punteggio: Double?
        let sonno: Double?
        let battito: Double?
        var passi: Double? = nil
        var id: Date { data }
    }
    struct Pagina: Identifiable {
        let id: Int
        let giorno: String
        let domanda: String?
        let risposta: String
        let umore: String?
    }

    let giorni: [Giorno]
    let pagine: [Pagina]
    let mediaUmore: Double?
    let mediaSonno: Double?
    let mediaBattito: Double?
    let frasi: [String]
    var battiti: [Giorno] { giorni.filter { $0.battito != nil } }
    var passiGiorni: [Giorno] { giorni.filter { ($0.passi ?? 0) > 0 } }

    init(_ o: [String: Any], salute: [Date: SaluteStorica.Valori] = [:], giorni quanti: Int = 30) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        func numero(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }
        // umore dal diario (cervello) + sonno, battito e passi dall'app Salute, giorno per giorno
        var umori: [Date: Double] = [:], sonniDiario: [Date: Double] = [:], battitiDiario: [Date: Double] = [:]
        var riposiDetti: [Date: Double] = [:]   // 13 nov (12.0 (17)): il riposo detto a voce, segnato nel diario della sera
        for s in o["serie"] as? [[String: Any]] ?? [] {
            guard let g = s["giorno"] as? String, let d = f.date(from: g) else { continue }
            let k = Calendar.current.startOfDay(for: d)
            if let p = numero(s["punteggio"]) { umori[k] = p }
            if let x = numero(s["sonno_ore"]) { sonniDiario[k] = x }
            if let x = numero(s["battito_riposo"]) { battitiDiario[k] = x }
            if let x = numero(s["riposo_detto_ore"]) { riposiDetti[k] = x }
        }
        let tutti = Set(umori.keys).union(salute.keys).union(sonniDiario.keys)
        let limite = Calendar.current.date(byAdding: .day, value: -quanti, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        giorni = tutti.filter { $0 >= limite }.sorted().map { k in
            let v = salute[k]
            // il sonno di Salute più il riposo detto a voce (il sonno del diario lo conta già); senza sonno di quel giorno il solo
            // pisolino non diventa «il sonno del giorno»
            let detto: Double = riposiDetti[k] ?? 0
            return Giorno(data: k, punteggio: umori[k], sonno: v?.sonnoOre.map { (($0 + detto) * 10).rounded() / 10 } ?? sonniDiario[k],
                          battito: v?.battito ?? battitiDiario[k], passi: v?.passi)
        }
        pagine = (o["pagine"] as? [[String: Any]] ?? []).compactMap { p in
            guard let id = (p["id"] as? NSNumber)?.intValue, let r = p["risposta"] as? String else { return nil }
            return Pagina(id: id, giorno: p["giorno"] as? String ?? "", domanda: p["domanda"] as? String, risposta: r, umore: p["umore"] as? String)
        }
        let medie = o["medie"] as? [String: Any] ?? [:]
        func media(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        mediaUmore = numero(medie["umore"])
        mediaSonno = media(giorni.compactMap(\.sonno)) ?? numero(medie["sonno_ore"])
        mediaBattito = media(giorni.compactMap(\.battito)) ?? numero(medie["battito_riposo"])

        var righe: [String] = []
        let n = (o["giorni_con_diario"] as? NSNumber)?.intValue ?? 0
        righe.append(n == 0 ? "Nessun giorno di diario nel periodo." : "\(n) giorn\(n == 1 ? "o" : "i") di diario nel periodo.")
        if let a = numero(o["andamento_umore"]) {
            righe.append(a > 0.5 ? "Umore in salita rispetto all'inizio del periodo." : a < -0.5 ? "Umore in discesa rispetto all'inizio del periodo." : "Umore stabile nel periodo.")
        }
        if let c = numero(o["correlazione_sonno_umore"]) {
            righe.append(c > 0.3 ? "Quando dorme di più, l'umore tende a essere migliore." : c < -0.3 ? "Curioso: nei giorni con meno sonno l'umore è più alto." : "Sonno e umore non sembrano andare insieme, per ora.")
        }
        if let m = o["temi_giorni_migliori"] as? [String], !m.isEmpty { righe.append("Nei giorni migliori: \(m.joined(separator: ", ")).") }
        if let p = o["temi_giorni_peggiori"] as? [String], !p.isEmpty { righe.append("Nei giorni più pesanti: \(p.joined(separator: ", ")).") }
        if let nota = o["nota"] as? String { righe.append(nota.prefix(1).uppercased() + nota.dropFirst() + ".") }
        frasi = righe
    }
}
