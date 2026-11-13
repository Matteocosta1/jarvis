import Foundation
import HealthKit
#if os(iOS)
import UIKit
#endif

/// «Come ho dormito?», «Quanto mi sono allenato?» e il pezzo di salute del briefing del mattino.
/// Legge dall'app Salute: sonno della notte, battito a riposo (oggi e media della settimana), passi, calorie attive, allenamenti.
/// Vale per iPhone e Apple Watch (stesso file, due target). Sull'iPhone servono la capability HealthKit
/// e la frase NSHealthShareUsageDescription. Solo lettura: JARVIS non scrive mai nulla in Salute.
nonisolated enum Benessere {

    nonisolated private static let negozio = HKHealthStore()
    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    private static var tipi: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate), HKQuantityType(.stepCount),
         HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling),
         HKObjectType.workoutType()]
    }

    static func riepilogo(giorni: Int) async -> (String, Bool) {
        guard HKHealthStore.isHealthDataAvailable() else { return (json(["errore": "l'app Salute non è disponibile su questo dispositivo"]), true) }
        // 13 nov (12.0 (17)): a iPhone bloccato Salute è chiusa a chiave e le letture tornavano vuote (zero passi, niente sonno): il
        // cervello le prendeva per vere. Ora lo dice; e la Salute letta mentre il signore parla, così, non parte con la domanda
        #if os(iOS)
        guard await MainActor.run(body: { UIApplication.shared.isProtectedDataAvailable }) else {
            return (json(["errore": "l'iPhone è bloccato: i dati di Salute si leggono solo a telefono sbloccato"]), true)
        }
        #endif
        do {
            try await negozio.requestAuthorization(toShare: [], read: tipi)
        } catch {
            return (json(["errore": "accesso a Salute non riuscito: \(error.localizedDescription)"]), true)
        }
        let cal = Calendar.current
        let adesso = Date()
        let oggi = cal.startOfDay(for: adesso)
        let ieri = cal.date(byAdding: .day, value: -1, to: oggi)!
        let ora = DateFormatter()
        ora.locale = Locale(identifier: "it_IT")
        ora.dateFormat = "HH:mm"

        var out: [String: Any] = [:]

        // ── Sonno: la notte (dalle 18 di ieri a mezzogiorno) e, a parte, i pisolini di oggi ──
        // Un riposo che inizia dopo le 10 del mattino è un pisolino: non si mescola alla notte, ma conta nel riposo totale.
        let inizioNotte = cal.date(byAdding: .hour, value: 18, to: ieri)!
        let confine = cal.date(byAdding: .hour, value: 10, to: oggi)!
        let campioni = await categoria(HKCategoryType(.sleepAnalysis), da: inizioNotte, a: adesso)
        // Se c'è l'orologio, si usano solo i suoi dati (più precisi e niente doppioni con l'iPhone).
        let daOrologio = campioni.filter { ($0.sourceRevision.productType ?? "").hasPrefix("Watch") }
        let tutti = daOrologio.isEmpty ? campioni : daOrologio
        let notte = tutti.filter { $0.startDate < confine }
        let pomeriggio = tutti.filter { $0.startDate >= confine }
        let fasi: [(String, Set<Int>)] = [
            ("profondo", [HKCategoryValueSleepAnalysis.asleepDeep.rawValue]),
            ("rem", [HKCategoryValueSleepAnalysis.asleepREM.rawValue]),
            ("leggero", [HKCategoryValueSleepAnalysis.asleepCore.rawValue]),
        ]
        let addormentato: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let dormito = notte.filter { addormentato.contains($0.value) }
        var riposoTotale: TimeInterval = 0
        if dormito.isEmpty {
            out["sonno"] = ["nota": "nessun dato di sonno per la notte scorsa (orologio non indossato a letto o monitoraggio del sonno spento)"]
        } else {
            let secondiNotte = unione(dormito)
            riposoTotale += secondiNotte
            var sonno: [String: Any] = ["totale": durata(secondiNotte)]
            for (nome, valori) in fasi {
                let s = unione(notte.filter { valori.contains($0.value) })
                if s > 0 { sonno[nome] = durata(s) }
            }
            let sveglio = notte.filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
            if !sveglio.isEmpty { sonno["risvegli"] = sveglio.count }
            if let a = dormito.map(\.startDate).min() { sonno["addormentato_alle"] = ora.string(from: a) }
            if let s = dormito.map(\.endDate).max() { sonno["sveglio_alle"] = ora.string(from: s) }
            out["sonno"] = sonno
        }
        // Pisolini di oggi: ogni blocco di sonno separato da almeno 30 minuti di veglia è un pisolino a sé.
        let sonnellini = pomeriggio.filter { addormentato.contains($0.value) }.sorted { $0.startDate < $1.startDate }
        var blocchi: [[HKCategorySample]] = []
        for c in sonnellini {
            if let ultimo = blocchi.last?.last, c.startDate.timeIntervalSince(ultimo.endDate) < 1800 { blocchi[blocchi.count - 1].append(c) }
            else { blocchi.append([c]) }
        }
        let pisolini = blocchi.compactMap { b -> [String: Any]? in
            let secondi = unione(b)
            guard secondi >= 600, let da = b.map(\.startDate).min(), let a = b.map(\.endDate).max() else { return nil }   // sotto i 10 minuti non è un pisolino
            riposoTotale += secondi
            return ["da": ora.string(from: da), "a": ora.string(from: a), "durata": durata(secondi)]
        }
        if !pisolini.isEmpty {
            out["pisolini_oggi"] = pisolini
            out["riposo_totale_oggi"] = durata(riposoTotale)
            out["nota_riposo"] = "il riposo totale somma la notte e i pisolini: quando valuti quanto ha dormito, conta anche questi"
        }

        // ── Battito a riposo: oggi (o ieri) e media degli ultimi 7 giorni ──
        let settimana = cal.date(byAdding: .day, value: -7, to: oggi)!
        let riposi = await quantita(HKQuantityType(.restingHeartRate), da: settimana, a: adesso)
        if let ultimo = riposi.max(by: { $0.endDate < $1.endDate }) {
            let valori = riposi.map { $0.quantity.doubleValue(for: bpm) }
            out["battito_a_riposo"] = [
                "ultimo": Int(ultimo.quantity.doubleValue(for: bpm).rounded()),
                "del": cal.isDateInToday(ultimo.endDate) ? "oggi" : (cal.isDateInYesterday(ultimo.endDate) ? "ieri" : "giorni fa"),
                "media_7_giorni": Int((valori.reduce(0, +) / Double(valori.count)).rounded()),
            ] as [String: Any]
        }

        // ── Movimento: ieri e oggi ──
        out["passi"] = ["ieri": Int(await somma(HKQuantityType(.stepCount), .count(), da: ieri, a: oggi)),
                        "oggi_finora": Int(await somma(HKQuantityType(.stepCount), .count(), da: oggi, a: adesso))]
        out["calorie_attive_kcal"] = ["ieri": Int(await somma(HKQuantityType(.activeEnergyBurned), .kilocalorie(), da: ieri, a: oggi)),
                                      "oggi_finora": Int(await somma(HKQuantityType(.activeEnergyBurned), .kilocalorie(), da: oggi, a: adesso))]

        // ── Allenamenti degli ultimi giorni ──
        let dal = cal.date(byAdding: .day, value: -max(1, min(giorni, 7)), to: adesso)!
        let giorno = DateFormatter()
        giorno.locale = Locale(identifier: "it_IT")
        giorno.dateFormat = "EEEE d, HH:mm"
        let allenamenti = await workout(da: dal, a: adesso)
        out["allenamenti"] = allenamenti.prefix(10).map { w -> [String: Any] in
            var r: [String: Any] = ["tipo": nomeAttivita(w.workoutActivityType), "quando": giorno.string(from: w.startDate),
                                    "durata": durata(w.duration)]
            if let k = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                r["kcal"] = Int(k.doubleValue(for: .kilocalorie()).rounded())
            }
            let km = (w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
                      ?? w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity())?.doubleValue(for: .meterUnit(with: .kilo))
            if let km, km > 0.05 { r["km"] = (km * 10).rounded() / 10 }
            return r
        }
        if allenamenti.isEmpty { out["allenamenti_nota"] = "nessun allenamento registrato negli ultimi \(max(1, min(giorni, 7))) giorni" }
        return (json(out), false)
    }

    /// 13 nov (12.0 (17)): il permesso di leggere Salute è già stato chiesto? Se no, la lettura fatta mentre il signore parla non
    /// parte: la finestra del permesso non deve comparire a metà frase (la chiede lo strumento del cervello, come sempre).
    static func permessoGiaChiesto() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            negozio.getRequestStatusForAuthorization(toShare: [], read: tipi) { stato, errore in
                c.resume(returning: errore == nil && stato == .unnecessary)
            }
        }
    }

    // MARK: Letture

    private static func categoria(_ tipo: HKCategoryType, da: Date, a: Date) async -> [HKCategorySample] {
        await withCheckedContinuation { (c: CheckedContinuation<[HKCategorySample], Never>) in
            let q = HKSampleQuery(sampleType: tipo, predicate: HKQuery.predicateForSamples(withStart: da, end: a),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                c.resume(returning: s as? [HKCategorySample] ?? [])
            }
            negozio.execute(q)
        }
    }

    private static func quantita(_ tipo: HKQuantityType, da: Date, a: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { (c: CheckedContinuation<[HKQuantitySample], Never>) in
            let q = HKSampleQuery(sampleType: tipo, predicate: HKQuery.predicateForSamples(withStart: da, end: a),
                                  limit: 50, sortDescriptors: nil) { _, s, _ in
                c.resume(returning: s as? [HKQuantitySample] ?? [])
            }
            negozio.execute(q)
        }
    }

    /// Somma senza doppioni tra iPhone e orologio (ci pensa HealthKit con le statistiche).
    private static func somma(_ tipo: HKQuantityType, _ unita: HKUnit, da: Date, a: Date) async -> Double {
        await withCheckedContinuation { (c: CheckedContinuation<Double, Never>) in
            let q = HKStatisticsQuery(quantityType: tipo, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: da, end: a),
                                      options: .cumulativeSum) { _, s, _ in
                c.resume(returning: s?.sumQuantity()?.doubleValue(for: unita) ?? 0)
            }
            negozio.execute(q)
        }
    }

    private static func workout(da: Date, a: Date) async -> [HKWorkout] {
        await withCheckedContinuation { (c: CheckedContinuation<[HKWorkout], Never>) in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: HKQuery.predicateForSamples(withStart: da, end: a),
                                  limit: 20, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, s, _ in
                c.resume(returning: s as? [HKWorkout] ?? [])
            }
            negozio.execute(q)
        }
    }

    // MARK: Utilità

    /// Secondi coperti da un insieme di intervalli, contando una volta sola le parti sovrapposte.
    private static func unione(_ campioni: [HKCategorySample]) -> TimeInterval {
        let ordinati = campioni.map { ($0.startDate, $0.endDate) }.sorted { $0.0 < $1.0 }
        var totale: TimeInterval = 0
        var corrente: (Date, Date)?
        for (i, f) in ordinati {
            if let c = corrente, i <= c.1 {
                corrente = (c.0, max(c.1, f))
            } else {
                if let c = corrente { totale += c.1.timeIntervalSince(c.0) }
                corrente = (i, f)
            }
        }
        if let c = corrente { totale += c.1.timeIntervalSince(c.0) }
        return totale
    }

    private static func durata(_ secondi: TimeInterval) -> String {
        let m = Int((secondi / 60).rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    private static func nomeAttivita(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "corsa"
        case .walking: return "camminata"
        case .hiking: return "escursione"
        case .cycling: return "bici"
        case .swimming: return "nuoto"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "pesi"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "cross training"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .boxing, .kickboxing: return "boxe"
        case .martialArts: return "arti marziali"
        case .socialDance, .cardioDance: return "ballo"
        case .elliptical: return "ellittica"
        case .rowing: return "vogatore"
        case .stairClimbing, .stairs: return "scale"
        case .soccer: return "calcio"
        case .tennis: return "tennis"
        case .coreTraining: return "addominali"
        case .flexibility, .cooldown: return "stretching"
        case .mindAndBody: return "mente e corpo"
        default: return "allenamento"
        }
    }

    private static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}

// MARK: - 13 nov · La Salute letta mentre il signore parla (12.0 (17))

/// Proposta approvata dal signore il 13 nov («crea una nuova build… che include questo suggerimento su Salute»): quando parla di
/// sonno, battito o passi, il dispositivo legge Salute mentre lui parla e manda i dati insieme alla domanda.
/// Prima il cervello, davanti a «come ho dormito?», chiedeva al dispositivo di leggere Salute e aspettava (13 nov: 8,2 e 6,1 secondi
/// dalla fine della frase al primo suono). Ora la lettura parte mentre il signore parla e va con la domanda: il cervello risponde in un
/// passaggio solo. iPhone: quando le parole parlano di salute (`ArgomentoSalute`), o JARVIS ne stava parlando, o ha appena chiesto il
/// diario della sera. Orologio: watchOS non ha le parole dal vivo, quindi si legge a ogni frase mentre la dice; il cervello usa i dati
/// solo se la domanda è sulla salute. Una lettura vale 2 minuti; non si salva niente.
@MainActor
enum SalutePronta {
    private static let validita: TimeInterval = 120
    private static var dati: [String: String]?
    private static var lettaIl = Date.distantPast
    private static var inCorso = false
    private static var chiestaIl = Date.distantPast

    /// Comincia a leggere, se non c'è già una lettura fresca o in corso. Si può chiamare a ogni parola: costa niente.
    static func prepara() {
        chiestaIl = Date()
        guard !inCorso, Date().timeIntervalSince(lettaIl) > validita else { return }
        inCorso = true
        Task { @MainActor in
            dati = await leggi()
            lettaIl = Date()
            inCorso = false
        }
    }

    /// I dati da mandare con la domanda, solo se una frase dell'ultimo minuto li ha chiesti. Se la lettura non è ancora finita si
    /// aspetta al massimo `attesa` secondi; poi la domanda parte senza (e il cervello li chiede come prima).
    static func perDomanda(attesa: Double) async -> [String: String]? {
        guard Date().timeIntervalSince(chiestaIl) < 60 else { return nil }
        let inizio = Date()
        while inCorso, Date().timeIntervalSince(inizio) < attesa { try? await Task.sleep(for: .milliseconds(25)) }
        guard !inCorso, var d = dati, Date().timeIntervalSince(lettaIl) < validita else { return nil }
        d["eta_ms"] = String(Int(Date().timeIntervalSince(lettaIl) * 1000))
        return d
    }

    private static func leggi() async -> [String: String]? {
        guard await Benessere.permessoGiaChiesto() else { return nil }
        var d: [String: String] = [:]
        let (riepilogo, errore) = await Benessere.riepilogo(giorni: 7)   // 7 giorni di allenamenti: vale per ogni richiesta del cervello
        if !errore { d["riepilogo"] = riepilogo }
        #if os(watchOS)
        d["battito"] = await Cuore.condiviso.riepilogo(ore: 3)           // al polso anche i battiti delle ultime ore (salute_battito)
        #endif
        return d.isEmpty ? nil : d
    }
}
