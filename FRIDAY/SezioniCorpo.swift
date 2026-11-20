#if os(iOS)
import SwiftUI
import Combine
import UIKit
import HealthKit
import WeatherKit
import CoreLocation
import AVFoundation
import Vision
import UserNotifications

// MARK: - FRIDAY · CICLO (CORPO): dati da Salute, sintomi segnati da Bea, fasi e previsioni. Solo suoi.

struct VistaCiclo: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @StateObject private var sintomi = Salvato<[String: [String]]>("ciclo_sintomi", iniziale: [:])
    @StateObject private var inizi = Salvato<[Date]>("ciclo_inizi_manuali", iniziale: [])
    @StateObject private var opzioni = Salvato<[String: Bool]>("ciclo_opzioni", iniziale: ["promemoria": true, "spesa": true])
    @State private var giorniFlusso: [Date] = []
    @State private var pronto = false
    private static let elencoSintomi = ["Crampi", "Mal di testa", "Gonfiore", "Stanchezza", "Umore giù", "Pelle", "Piena di energia"]

    var body: some View {
        let c = CicloCalcolo(flusso: giorniFlusso, manuali: inizi.valore)
        CorniceScheda(titolo: "Ciclo", sottotitolo: c.giorno.map { "Giorno \($0) di \(c.durata)" } ?? "Da Salute", icona: "f:ciclo", tinta: tinta, pronto: pronto) {
            HStack { SoloTuo(); Spacer(); Text("DATI DA SALUTE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.tenue) }
            if c.giorno == nil {
                Pannello(titolo: "INIZIO", tinta: tinta) {
                    NotaF(testo: "In Salute non trovo ancora il ciclo. Segna qui il primo giorno dell'ultimo ciclo e FRIDAY comincia a contare.")
                    TastoF(testo: "Segna oggi come primo giorno") { inizi.valore.append(Calendar.current.startOfDay(for: Date())) }
                }
            }
            Pannello(titolo: "SETTIMANA", tinta: tinta) {
                HStack(spacing: 6) {
                    ForEach(-3...3, id: \.self) { d in
                        let g = c.giorno.map { $0 + d }
                        VStack(spacing: 4) {
                            Text(g.map { "\((($0 - 1) % c.durata + c.durata) % c.durata + 1)" } ?? "–").font(.system(size: 15, weight: .bold, design: .monospaced))
                            Text(g.map { c.fase(giorno: $0).corta } ?? "").font(.system(size: 9, design: .monospaced))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(d == 0 ? Color.fondo : tinta)
                        .background(RoundedRectangle(cornerRadius: 9).fill(d == 0 ? tinta : tinta.opacity(0.06)))
                    }
                }
            }
            Pannello(titolo: "OGGI", tinta: tinta) {
                FlowF(spazio: 8) {
                    ForEach(Self.elencoSintomi, id: \.self) { s in
                        ChipF(testo: s, acceso: sintomi.valore[Self.chiaveOggi, default: []].contains(s)) {
                            var v = sintomi.valore[Self.chiaveOggi, default: []]
                            if let i = v.firstIndex(of: s) { v.remove(at: i) } else { v.append(s) }
                            sintomi.valore[Self.chiaveOggi] = v
                        }
                    }
                }
                NotaF(testo: "Un tocco e resta segnato. Con i mesi FRIDAY impara cosa ti succede in ogni fase.")
            }
            if let g = c.giorno {
                let f = c.fase(giorno: g)
                Pannello(titolo: "FASE · \(f.nome.uppercased())", tinta: tinta) {
                    RigaF(etichetta: "Energia", valore: f.energia, stato: f == .follicolare || f == .ovulazione ? .ok : .normale)
                    RigaF(etichetta: "Allenamento", valore: f.allenamento)
                    RigaF(etichetta: "Pelle", valore: f.pelle)
                    if let piu = sintomoFrequente(in: f, c) { RigaF(etichetta: "Di solito", valore: piu) }
                }
                Pannello(titolo: "PROSSIMO", tinta: tinta) {
                    RigaF(etichetta: "Previsto", valore: c.prossimo.map { "tra \(c.giorniAlProssimo ?? 0) giorni · \($0.formatted(.dateTime.day().month(.wide)))" } ?? "—")
                    Toggle(isOn: Binding(get: { opzioni.valore["promemoria"] ?? true }, set: { opzioni.valore["promemoria"] = $0; programma(c) })) {
                        Text("Promemoria 2 giorni prima").font(.system(size: 14)).foregroundStyle(Color.testo)
                    }.tint(tinta)
                    Toggle(isOn: Binding(get: { opzioni.valore["spesa"] ?? true }, set: { opzioni.valore["spesa"] = $0 })) {
                        Text("Assorbenti in Spesa il giorno prima").font(.system(size: 14)).foregroundStyle(Color.testo)
                    }.tint(tinta)
                }
            }
            if c.durate.count > 0 {
                Pannello(titolo: "ANDAMENTO", tinta: tinta) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(c.durate.suffix(6).enumerated()), id: \.offset) { _, d in
                            VStack(spacing: 3) {
                                Text("\(d)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.testo)
                                RoundedRectangle(cornerRadius: 3).fill(tinta.opacity(0.7)).frame(height: CGFloat(d - 18) * 4)
                            }.frame(maxWidth: .infinity)
                        }
                    }.frame(height: 90)
                    RigaF(etichetta: "Durata media", valore: "\(c.durata) giorni")
                    RigaF(etichetta: "Ciclo", valore: "\(c.giorniFlusso) giorni")
                    RigaF(etichetta: "Regolarità", valore: "± \(c.scarto) giorni", stato: c.scarto <= 3 ? .ok : .no)
                }
            }
            NotaF(testo: "Dati letti da Salute dell'iPhone. Le previsioni sono stime e non valgono come contraccezione. Restano solo sul tuo profilo: nessun altro li vede.")
            TastoJarvis(testo: "Chiedi a FRIDAY", tinta: tinta) { chiedi("Come sono messa col ciclo? Fase, energia e cosa mi consigli oggi.") }
        }
        .task { await carica() }
    }

    private static var chiaveOggi: String { Date().formatted(.iso8601.year().month().day()) }

    private func sintomoFrequente(in f: CicloCalcolo.Fase, _ c: CicloCalcolo) -> String? {
        var conti: [String: Int] = [:]
        for (k, v) in sintomi.valore {
            guard let d = try? Date(k, strategy: .iso8601.year().month().day()), let g = c.giornoDi(d), c.fase(giorno: g) == f else { continue }
            for s in v { conti[s, default: 0] += 1 }
        }
        return conti.max { $0.value < $1.value }.map { $0.key.lowercased() }
    }

    private func carica() async {
        giorniFlusso = await SaluteF.giorniFlusso()
        let c = CicloCalcolo(flusso: giorniFlusso, manuali: inizi.valore)
        programma(c)
        if opzioni.valore["spesa"] ?? true, let n = c.giorniAlProssimo, n <= 1, let p = c.prossimo {
            let chiave = "ciclo_spesa_" + p.formatted(.iso8601.year().month().day())
            if !UserDefaults.standard.bool(forKey: chiave) {
                UserDefaults.standard.set(true, forKey: chiave)
                _ = await VistaVitals.chiama(["ricordo_aggiungi": "assorbenti", "tipo": "spesa"])
            }
        }
        pronto = true
    }

    private func programma(_ c: CicloCalcolo) {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: ["ciclo"])
        guard opzioni.valore["promemoria"] ?? true, let p = c.prossimo,
              let quando = Calendar.current.date(byAdding: .day, value: -2, to: p), quando > Date() else { return }
        let x = UNMutableNotificationContent()
        x.title = "Ciclo"; x.body = "Tra due giorni dovrebbe arrivare. Se vuoi, FRIDAY ti prepara un allenamento più dolce."; x.sound = .default
        var dc = Calendar.current.dateComponents([.year, .month, .day], from: quando); dc.hour = 20
        centro.add(UNNotificationRequest(identifier: "ciclo", content: x, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)))
    }
}

/// Il conto del ciclo: dai giorni di flusso di Salute (o dai primi giorni segnati a mano) gli inizi, le durate, la fase.
struct CicloCalcolo {
    let inizi: [Date]
    let durate: [Int]
    let durata: Int
    let giorniFlusso: Int
    let scarto: Int

    enum Fase: Equatable {
        case mestruale, follicolare, ovulazione, luteale
        var nome: String { switch self { case .mestruale: "Mestruale"; case .follicolare: "Follicolare"; case .ovulazione: "Ovulazione"; case .luteale: "Luteale" } }
        var corta: String { switch self { case .mestruale: "Ciclo"; case .follicolare: "Follic."; case .ovulazione: "Ovul."; case .luteale: "Luteale" } }
        var energia: String { switch self { case .mestruale: "bassa · riposa"; case .follicolare: "in salita · alta"; case .ovulazione: "al massimo"; case .luteale: "in calo" } }
        var allenamento: String { switch self { case .mestruale: "Matwork dolce, stretching"; case .follicolare: "Reformer intenso"; case .ovulazione: "Reformer + Bosu"; case .luteale: "ritmo medio, più core" } }
        var pelle: String { switch self { case .mestruale: "sensibile · idratare"; case .follicolare: "luminosa · base leggera"; case .ovulazione: "al meglio"; case .luteale: "più grassa · correttore" } }
    }

    init(flusso: [Date], manuali: [Date]) {
        let cal = Calendar.current
        let giorni = Set((flusso + manuali).map { cal.startOfDay(for: $0) }).sorted()
        var inizi: [Date] = [], lunghezze: [Int] = []
        var ultimo: Date?, lungo = 0
        for g in giorni {
            if let u = ultimo, cal.dateComponents([.day], from: u, to: g).day ?? 0 <= 2 { lungo += 1 }
            else { if lungo > 0 { lunghezze.append(lungo) }; inizi.append(g); lungo = 1 }
            ultimo = g
        }
        if lungo > 0 { lunghezze.append(lungo) }
        self.inizi = inizi
        let d = zip(inizi, inizi.dropFirst()).compactMap { cal.dateComponents([.day], from: $0, to: $1).day }.filter { (18...45).contains($0) }
        durate = d
        durata = d.isEmpty ? 28 : Int((Double(d.suffix(6).reduce(0, +)) / Double(d.suffix(6).count)).rounded())
        giorniFlusso = lunghezze.isEmpty ? 5 : max(1, lunghezze.suffix(6).reduce(0, +) / lunghezze.suffix(6).count)
        scarto = d.count < 2 ? 0 : (d.suffix(6).map { abs($0 - durata) }.max() ?? 0)
    }

    func giornoDi(_ data: Date) -> Int? {
        guard let i = inizi.last(where: { $0 <= data }) else { return nil }
        return (Calendar.current.dateComponents([.day], from: i, to: Calendar.current.startOfDay(for: data)).day ?? 0) + 1
    }
    var giorno: Int? { giornoDi(Date()) }
    var prossimo: Date? { inizi.last.flatMap { Calendar.current.date(byAdding: .day, value: durata * max(1, ((giorno ?? 1) - 1) / durata + 1), to: $0) } }
    var giorniAlProssimo: Int? { prossimo.flatMap { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: $0).day } }

    func fase(giorno g0: Int) -> Fase {
        let g = ((g0 - 1) % durata + durata) % durata + 1
        let ovul = durata - 14
        if g <= giorniFlusso { return .mestruale }
        if abs(g - ovul) <= 1 { return .ovulazione }
        return g < ovul ? .follicolare : .luteale
    }
}

/// Le letture da Salute delle sezioni nuove (sola lettura).
enum SaluteF {
    static let negozio = HKHealthStore()

    static func giorniFlusso() async -> [Date] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let tipo = HKCategoryType(.menstrualFlow)
        try? await negozio.requestAuthorization(toShare: [], read: [tipo, HKCategoryType(.sleepAnalysis)])
        let da = Calendar.current.date(byAdding: .month, value: -14, to: Date())!
        let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: tipo, predicate: HKQuery.predicateForSamples(withStart: da, end: Date()))],
                                        sortDescriptors: [SortDescriptor(\.startDate)])
        let campioni = (try? await d.result(for: negozio)) ?? []
        return campioni.filter { $0.value != 5 }.map(\.startDate)          // 5 = «nessun flusso» (stesso valore in iOS 17 e 18)
    }

    /// Le ore dormite, notte per notte (la mattina in cui finisce il sonno → ore).
    static func notti(_ quante: Int = 90) async -> [Date: Double] {
        guard HKHealthStore.isHealthDataAvailable() else { return [:] }
        let tipo = HKCategoryType(.sleepAnalysis)
        try? await negozio.requestAuthorization(toShare: [], read: [tipo])
        let da = Calendar.current.date(byAdding: .day, value: -quante, to: Date())!
        let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: tipo, predicate: HKQuery.predicateForSamples(withStart: da, end: Date()))],
                                        sortDescriptors: [SortDescriptor(\.startDate)])
        let dormito: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        var ore: [Date: Double] = [:]
        for c in (try? await d.result(for: negozio)) ?? [] where dormito.contains(c.value) {
            ore[Calendar.current.startOfDay(for: c.endDate), default: 0] += c.endDate.timeIntervalSince(c.startDate) / 3600
        }
        return ore
    }
}

/// Le etichette che vanno a capo da sole (sintomi, zone).
struct FlowF: Layout {
    var spazio: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, riga: CGFloat = 0
        for s in subviews {
            let m = s.sizeThatFits(.unspecified)
            if x > 0 && x + m.width > w { x = 0; y += riga + spazio; riga = 0 }
            x += m.width + spazio; riga = max(riga, m.height)
        }
        return CGSize(width: w, height: y + riga)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, riga: CGFloat = 0
        for s in subviews {
            let m = s.sizeThatFits(.unspecified)
            if x > b.minX && x + m.width > b.maxX { x = b.minX; y += riga + spazio; riga = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(m))
            x += m.width + spazio; riga = max(riga, m.height)
        }
    }
}

// MARK: - TESTA (CORPO): emicrania ed epistassi. Diario, rischio di domani (pressione, sonno, ciclo), Buio, timer del naso.

struct Attacco: Codable, Equatable, Identifiable {
    var id = UUID()
    var inizio = Date()
    var fine: Date?
    var zone: [String] = []
    var intensita = 6
    var aura = false
    var fastidi: [String] = []
    var farmaco: Date?
}

struct Episodio: Codable, Equatable, Identifiable {
    var id = UUID()
    var inizio = Date()
    var minuti = 10
    var narice = "sinistra"
}

struct VistaTesta: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @StateObject private var attacchi = Salvato<[Attacco]>("testa_attacchi", iniziale: [])
    @StateObject private var episodi = Salvato<[Episodio]>("testa_episodi", iniziale: [])
    @State private var parte = 0
    @State private var aperto: Attacco?
    @State private var buio = false
    @State private var luce: CGFloat = 0.5
    @State private var naso: Date?
    @State private var rischio: (testo: String, alto: Bool)?
    @State private var aria: (umidita: Int, secca: Bool)?
    @State private var notti: [Date: Double] = [:]
    @State private var cicli = CicloCalcolo(flusso: [], manuali: [])
    @State private var riassunto: String?
    @State private var pronto = false
    private static let zone = ["Fronte", "Tempia sx", "Tempia dx", "Dietro l'occhio", "Nuca"]
    private static let fastidiTutti = ["luce", "rumori", "odori", "nausea"]

    var body: some View {
        CorniceScheda(titolo: "Testa", sottotitolo: rischio?.alto == true ? "Rischio emicrania domani: alto" : "Diario della testa", icona: "f:testa", tinta: tinta, pronto: pronto) {
            HStack { SoloTuo(); Spacer() }
            LinguetteF(voci: ["Emicrania", "Epistassi"], scelta: $parte)
            if parte == 0 { emicrania } else { epistassi }
            NotaF(testo: "FRIDAY tiene il diario e ti aiuta a vedere cosa succede. Non sostituisce il medico e non dà dosi di farmaci.")
        }
        .overlay { if buio { modoBuio } }
        .task { await carica() }
    }

    @ViewBuilder private var emicrania: some View {
        if let r = rischio {
            Pannello(titolo: r.alto ? "RISCHIO ALTO DOMANI" : "DOMANI", tinta: r.alto ? Color.rossoF : tinta) { NotaF(testo: r.testo) }
        }
        if let a = aperto {
            Pannello(titolo: "ATTACCO IN CORSO", tinta: Color.rossoF) {
                FlowF {
                    ForEach(Self.zone, id: \.self) { z in
                        ChipF(testo: z, acceso: a.zone.contains(z), tinta: Color.rossoF) { modifica { $0.zone.toggle(z) } }
                    }
                }
                Stepper(value: Binding(get: { a.intensita }, set: { v in modifica { $0.intensita = v } }), in: 1...10) {
                    RigaF(etichetta: "Intensità", valore: "\(a.intensita) / 10", stato: a.intensita >= 7 ? .no : .normale)
                }.tint(Color.rossoF)
                Toggle(isOn: Binding(get: { a.aura }, set: { v in modifica { $0.aura = v } })) { Text("Aura").foregroundStyle(Color.testo) }.tint(Color.rossoF)
                FlowF {
                    ForEach(Self.fastidiTutti, id: \.self) { f in
                        ChipF(testo: f, acceso: a.fastidi.contains(f), tinta: Color.rossoF) { modifica { $0.fastidi.toggle(f) } }
                    }
                }
                RigaF(etichetta: "Farmaco", valore: a.farmaco.map { "quello del medico · alle \($0.formatted(date: .omitted, time: .shortened))" } ?? "non ancora")
                HStack {
                    TastoF(testo: "Preso il farmaco", tinta: Color.rossoF, pieno: false) { modifica { $0.farmaco = Date() } }
                    TastoF(testo: "È passato", tinta: Color.rossoF) { chiudiAttacco(a) }
                }
                TastoF(testo: buio ? "Esci dal Buio" : "Buio", icona: "moon.fill", tinta: Color.rossoF, pieno: false) { accendiBuio(!buio) }
            }
        } else {
            TastoF(testo: "Ho un attacco", icona: "bolt.fill", tinta: Color.rossoF) {
                aperto = Attacco(); accendiBuio(true)
            }
        }
        Pannello(titolo: Date().formatted(.dateTime.month(.wide)).uppercased(), tinta: tinta) {
            calendario
            let mese = attacchi.valore.filter { Calendar.current.isDate($0.inizio, equalTo: Date(), toGranularity: .month) }
            RigaF(etichetta: "Attacchi", valore: "\(Set(mese.map { Calendar.current.startOfDay(for: $0.inizio) }).count) giorni")
            let farmaci = Set(mese.compactMap { $0.farmaco.map { Calendar.current.startOfDay(for: $0) } }).count
            RigaF(etichetta: "Giorni con farmaco", valore: "\(farmaci)", stato: farmaci >= 10 ? .no : .ok)
            NotaF(testo: "Più colore = più forte. La riga verde = farmaco preso. Se i giorni con antidolorifico salgono molto, FRIDAY te lo segnala: è una cosa da dire al medico.")
        }
        let f = fattori
        if !attacchi.valore.isEmpty {
            Pannello(titolo: "FATTORI", tinta: tinta) {
                ForEach(f, id: \.0) { RigaF(etichetta: $0.0, valore: "\($0.1) su \(attacchi.valore.count)", stato: $0.1 * 2 >= attacchi.valore.count ? .no : .normale) }
                NotaF(testo: "Collegamenti trovati nei tuoi dati, non diagnosi: più mesi registri, più diventano affidabili.")
            }
        }
        Pannello(titolo: "BUIO", tinta: tinta) {
            RigaF(etichetta: "Schermo", valore: "luminosità minima, solo rosso", stato: .ok)
            RigaF(etichetta: "Voce di FRIDAY", valore: "sottovoce", stato: .ok)
            RigaF(etichetta: "Non disturbare", valore: "dal Centro di Controllo")
            NotaF(testo: "Parte da solo quando tocchi «Ho un attacco». Non disturbare lo accendi tu: iOS non lascia farlo alle app.")
        }
        Pannello(titolo: "MEDICO", tinta: tinta) {
            if let riassunto { Text(riassunto).font(.system(size: 13)).foregroundStyle(Color.testo).textSelection(.enabled); ShareLink(item: riassunto) { Label("Condividi", systemImage: "square.and.arrow.up").foregroundStyle(tinta) } }
            TastoF(testo: "Prepara il riassunto degli ultimi 3 mesi", pieno: false) { Task { await preparaRiassunto() } }
        }
        Pannello(titolo: "CHIAMA IL 112 SE", tinta: Color.rossoF) {
            NotaF(testo: "Il dolore è improvviso e il più forte mai avuto · c'è febbre con collo rigido · senti debolezza, formicolii o parli in modo confuso · è iniziato dopo un colpo alla testa.")
        }
    }

    @ViewBuilder private var epistassi: some View {
        if let naso {
            Pannello(titolo: "TIENI STRETTO", tinta: Color.rossoF) {
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    let resta = max(0, 600 - Int(t.date.timeIntervalSince(naso)))
                    Text(String(format: "%02d:%02d", resta / 60, resta % 60)).font(.system(size: 54, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.rossoF).frame(maxWidth: .infinity)
                        .onChange(of: resta) { _, r in if r == 0 { finitoNaso() } }
                }
                TastoF(testo: "Si è fermato", tinta: Color.rossoF) { finitoNaso() }
            }
        } else {
            TastoF(testo: "Sangue dal naso", icona: "drop.fill", tinta: Color.rossoF) {
                naso = Date(); Parlato.dici("Siediti e piega la testa in avanti. Stringi la parte morbida del naso per dieci minuti: conto io.")
            }
        }
        Pannello(titolo: "PROTOCOLLO", tinta: tinta) {
            NotaF(testo: "Siediti e piega la testa in avanti. Non indietro: il sangue andrebbe in gola. Stringi la parte morbida del naso, sotto l'osso, con pollice e indice. Tieni stretto per 10 minuti senza mollare: FRIDAY conta per te. Respira con la bocca. Qualcosa di freddo sulla radice del naso aiuta. Dopo, niente soffiare il naso né sforzi per qualche ora.")
        }
        let mese = episodi.valore.filter { Calendar.current.isDate($0.inizio, equalTo: Date(), toGranularity: .month) }
        Pannello(titolo: "MESE", tinta: tinta) {
            RigaF(etichetta: "Episodi", valore: "\(mese.count)")
            RigaF(etichetta: "Durata media", valore: mese.isEmpty ? "—" : "\(mese.map(\.minuti).reduce(0, +) / mese.count) min")
            if let u = episodi.valore.last { RigaF(etichetta: "Ultimo", valore: u.inizio.formatted(.dateTime.weekday(.wide).day().hour().minute())) }
        }
        if let aria {
            Pannello(titolo: "ARIA", tinta: tinta) {
                RigaF(etichetta: "Umidità fuori", valore: "\(aria.umidita)%\(aria.secca ? " · aria secca" : "")", stato: aria.secca ? .no : .ok)
                NotaF(testo: "Con l'aria secca gli episodi aumentano. Chiedi al medico se usare un umidificatore o una soluzione per il naso.")
            }
        }
        Pannello(titolo: "CHIAMA IL 112 O VAI AL PRONTO SOCCORSO SE", tinta: Color.rossoF) {
            NotaF(testo: "Dopo 20 minuti non si ferma · il sangue è tanto · è successo dopo un colpo · ti gira la testa o stai per svenire.")
        }
    }

    private var calendario: some View {
        let cal = Calendar.current
        let inizio = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let giorni = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<giorni, id: \.self) { k in
                let g = cal.date(byAdding: .day, value: k, to: inizio)!
                let delGiorno = attacchi.valore.filter { cal.isDate($0.inizio, inSameDayAs: g) }
                let forza = delGiorno.map(\.intensita).max() ?? 0
                VStack(spacing: 2) {
                    Text("\(k + 1)").font(.system(size: 11, design: .monospaced)).foregroundStyle(forza > 0 ? Color.fondo : Color.tenue)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(forza > 0 ? Color.rossoF.opacity(0.25 + Double(forza) / 14) : tinta.opacity(0.05)))
                    Rectangle().fill(delGiorno.contains { $0.farmaco != nil } ? Color.verdeF : .clear).frame(height: 2)
                }
            }
        }
    }

    private var fattori: [(String, Int)] {
        let cal = Calendar.current
        var ciclo = 0, sonno = 0
        for a in attacchi.valore {
            if let g = cicli.giornoDi(a.inizio), g <= 2 { ciclo += 1 }
            if let ore = notti[cal.startOfDay(for: a.inizio)], ore < 6 { sonno += 1 }
        }
        return [("Ciclo (giorni 1-2)", ciclo), ("Sonno sotto 6 h", sonno)]
    }

    private var modoBuio: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("BUIO").font(.system(size: 14, weight: .bold, design: .monospaced)).tracking(4)
                Text("Resto qui, sottovoce.").font(.system(size: 15))
                Button("Esci") { accendiBuio(false) }.font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(red: 0.55, green: 0.05, blue: 0.05))
        }
        .transition(.opacity)
    }

    private func accendiBuio(_ si: Bool) {
        withAnimation(.easeInOut(duration: 0.4)) { buio = si }
        let schermo = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
        if si { luce = schermo?.brightness ?? 0.5; schermo?.brightness = 0.05 } else { schermo?.brightness = luce }
        Parlato.sottovoce = si
    }

    private func modifica(_ f: (inout Attacco) -> Void) {
        guard var a = aperto else { return }
        f(&a); aperto = a
    }

    private func chiudiAttacco(_ a: Attacco) {
        var a = a; a.fine = Date()
        attacchi.valore.append(a); aperto = nil; accendiBuio(false)
    }

    private func finitoNaso() {
        guard let n = naso else { return }
        episodi.valore.append(Episodio(inizio: n, minuti: max(1, Int(Date().timeIntervalSince(n) / 60))))
        naso = nil
        Parlato.dici("Fatto. Adesso niente soffiare il naso per qualche ora.")
    }

    private func carica() async {
        notti = await SaluteF.notti(100)
        cicli = CicloCalcolo(flusso: await SaluteF.giorniFlusso(), manuali: ArchivioF.leggi("ciclo_inizi_manuali", [Date].self) ?? [])
        if let pos = await Posizione.attuale(), let la = pos["lat"] as? Double, let lo = pos["lon"] as? Double,
           let w = try? await WeatherService.shared.weather(for: CLLocation(latitude: la, longitude: lo), including: .current, .hourly) {
            let (adesso, ore) = w
            let um = Int(adesso.humidity * 100)
            aria = (um, um < 40)
            let cal = Calendar.current
            let domani = ore.forecast.filter { cal.isDateInTomorrow($0.date) }.map { $0.pressure.converted(to: .hectopascals).value }
            let oggi = adesso.pressure.converted(to: .hectopascals).value
            if let media = domani.isEmpty ? nil : domani.reduce(0, +) / Double(domani.count) {
                let calo = oggi - media
                var motivi: [String] = []
                if calo >= 5 { motivi.append("la pressione scende di \(Int(calo.rounded())) hPa") }
                if let g = cicli.giornoDi(Date().addingTimeInterval(86_400)), g <= 2 { motivi.append("domani sei ai primi giorni del ciclo") }
                if let o = notti[cal.startOfDay(for: Date())], o < 6 { motivi.append("stanotte hai dormito \(String(format: "%.1f", o)) ore") }
                rischio = motivi.isEmpty ? ("Niente di particolare in vista per domani.", false)
                    : ("Domani: " + motivi.joined(separator: ", ") + ". Stasera dormi presto, bevi e tieni a portata il farmaco che ti ha dato il medico.", true)
            }
        }
        pronto = true
    }

    private func preparaRiassunto() async {
        let da = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let dati: [[String: Any]] = attacchi.valore.filter { $0.inizio > da }.map { a in
            ["data": a.inizio.formatted(.iso8601), "minuti": a.fine.map { Int($0.timeIntervalSince(a.inizio) / 60) } ?? 0, "intensita": a.intensita,
             "zone": a.zone, "aura": a.aura, "fastidi": a.fastidi, "farmaco": a.farmaco != nil]
        }
        let ep = episodi.valore.filter { $0.inizio > da }.map { ["data": $0.inizio.formatted(.iso8601), "minuti": $0.minuti] }
        if let o = await VistaVitals.chiama(["scrivi": ["compito": "medico", "dati": ["emicrania": dati, "epistassi": ep]]], attesa: 60) {
            riassunto = o["testo"] as? String ?? "Non riesco a prepararlo adesso."
        }
    }
}

extension Array where Element == String {
    mutating func toggle(_ s: String) { if let i = firstIndex(of: s) { remove(at: i) } else { append(s) } }
}

/// Le frasi brevi che FRIDAY dice dalle sezioni nuove (timer, guide), con la sua voce; sottovoce nel Buio.
enum Parlato {
    static var sottovoce = false
    private static let sintesi = AVSpeechSynthesizer()
    static func dici(_ testo: String) {
        let u = AVSpeechUtterance(string: testo)
        u.voice = Jarvis.voceScelta()
        u.volume = sottovoce ? 0.35 : 1
        u.rate = sottovoce ? 0.45 : AVSpeechUtteranceDefaultSpeechRate
        sintesi.stopSpeaking(at: .immediate)
        sintesi.speak(u)
    }
}

// MARK: - MAKEUP (CORPO): lo specchio con la fotocamera frontale, la guida sul viso (riconosciuto sul telefono), la trousse.

struct ProdottoTrucco: Codable, Equatable, Identifiable {
    var id = UUID()
    var tipo: String
    var dettaglio: String
}

struct VistaMakeup: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @StateObject private var specchio = SpecchioTrucco()
    @StateObject private var trousse = Salvato<[ProdottoTrucco]>("makeup_trousse", iniziale: [])
    @State private var gruppo = 0
    @State private var nuovoTipo = ""
    @State private var nuovoDettaglio = ""
    @State private var occasione = ""
    @State private var consiglio: String?
    @State private var foto = false

    var body: some View {
        CorniceScheda(titolo: "Makeup", sottotitolo: "Specchio · fotocamera frontale", icona: "f:makeup", tinta: tinta, fotocamera: true) {
            ZStack {
                AnteprimaSpecchio(sessione: specchio.sessione)
                GuidaViso(viso: specchio.viso, gruppo: gruppo, tinta: tinta)
                VStack { HStack { Text("LIVE").font(.system(size: 10, weight: .bold, design: .monospaced)).padding(5).background(Color.rossoF).foregroundStyle(.white); Spacer() }; Spacer() }.padding(10)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(tinta.opacity(0.4), lineWidth: 1))
            LinguetteF(voci: ["Base", "Occhi", "Labbra"], scelta: $gruppo)
            Pannello(titolo: "LETTURA", tinta: tinta) {
                NotaF(testo: specchio.viso == nil ? "Leggo luce e pelle dal video… guarda la fotocamera." : specchio.lettura)
                NotaF(testo: passo)
            }
            Pannello(titolo: "TROUSSE", tinta: tinta) {
                if trousse.valore.isEmpty { NotaF(testo: "Aggiungi i tuoi prodotti: scrivili qui o fotografali, FRIDAY legge brand e tonalità.") }
                ForEach(trousse.valore) { p in
                    RigaF(etichetta: p.tipo, valore: p.dettaglio)
                        .contextMenu { Button("Togli", role: .destructive) { trousse.valore.removeAll { $0.id == p.id } } }
                }
                HStack {
                    TextField("", text: $nuovoTipo, prompt: Text("Fondotinta").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                    TextField("", text: $nuovoDettaglio, prompt: Text("2W").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                    Button { aggiungi(nuovoTipo, nuovoDettaglio) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
                }
                TastoF(testo: "Fotografa un prodotto", icona: "camera", pieno: false) { foto = true }
            }
            Pannello(titolo: "CONSIGLIO", tinta: tinta) {
                TextField("", text: $occasione, prompt: Text("Per cosa? (stasera, lezione, cena…)").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                if let consiglio { Text(consiglio).font(.system(size: 14)).foregroundStyle(Color.testo) }
                TastoF(testo: "Consigliami", pieno: false) { Task { await chiediConsiglio() } }
            }
            NotaF(testo: "Il video resta sull'iPhone: il viso viene riconosciuto sul telefono, nessuna immagine esce.")
        }
        .fullScreenCover(isPresented: $foto) {
            Fotocamera(sorgente: .camera) { img in Task { await leggiProdotto(img) } }.ignoresSafeArea()
        }
        .task { await specchio.avvia() }
        .onDisappear { specchio.ferma() }
        .pausaDietro(ferma: { specchio.ferma() }, riprendi: { Task { await specchio.avvia() } })
    }

    private var passo: String {
        switch gruppo {
        case 0: "Base: picchietta il fondotinta dal centro verso l'esterno, il blush sulle guance verso le tempie (le zone segnate)."
        case 1: "Occhi: la linea parte dall'angolo esterno e sale verso la coda del sopracciglio, come la guida."
        default: "Labbra: contorna con la matita seguendo il bordo segnato, poi riempi dal centro."
        }
    }

    private func aggiungi(_ t: String, _ d: String) {
        let t = t.trimmingCharacters(in: .whitespaces), d = d.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        trousse.valore.append(ProdottoTrucco(tipo: t, dettaglio: d)); nuovoTipo = ""; nuovoDettaglio = ""
    }

    private func leggiProdotto(_ img: UIImage) async {
        guard let b64 = img.jpegFriday(lato: 1024) else { return }
        if let o = await VistaVitals.chiama(["vista": ["compito": "trucco", "immagine": b64]], attesa: 60) {
            let tipo = o["tipo"] as? String ?? "", brand = o["brand"] as? String ?? "", nome = o["nome"] as? String ?? "", ton = o["tonalita"] as? String ?? ""
            aggiungi(tipo.isEmpty ? "Prodotto" : tipo, [brand, nome, ton].filter { !$0.isEmpty }.joined(separator: " · "))
        }
    }

    private func chiediConsiglio() async {
        let dati: [String: Any] = ["trousse": trousse.valore.map { "\($0.tipo) \($0.dettaglio)" }, "occasione": occasione, "luce": specchio.lettura]
        if let o = await VistaVitals.chiama(["scrivi": ["compito": "trucco", "dati": dati]], attesa: 60) { consiglio = o["testo"] as? String }
    }
}

extension UIImage {
    /// JPEG in base64, ridotta al lato massimo dato (per le foto che FRIDAY guarda).
    func jpegFriday(lato: CGFloat) -> String? {
        let s = min(1, lato / max(size.width, size.height))
        let m = CGSize(width: size.width * s, height: size.height * s)
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        let r = UIGraphicsImageRenderer(size: m, format: f).image { _ in draw(in: CGRect(origin: .zero, size: m)) }
        return r.jpegData(compressionQuality: 0.75)?.base64EncodedString()
    }
}

/// I punti del viso (normalizzati 0…1, origine in alto a sinistra, già specchiati come lo vede Bea).
struct VisoF {
    var contorno: [CGPoint] = []
    var occhioSx: [CGPoint] = [], occhioDx: [CGPoint] = []
    var sopraccSx: [CGPoint] = [], sopraccDx: [CGPoint] = []
    var labbra: [CGPoint] = []
    var guanciaSx: CGPoint = .zero, guanciaDx: CGPoint = .zero
}

@MainActor final class SpecchioTrucco: NSObject, ObservableObject {
    let sessione = AVCaptureSession()
    @Published var viso: VisoF?
    @Published var lettura = ""
    private let coda = DispatchQueue(label: "it.discosizer.friday.makeup")
    private var pronta = false
    private var lettore: LettoreViso?          // la camera non tiene il delegato: lo tiene lo specchio

    func avvia() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { lettura = "Serve il permesso della fotocamera."; return }
        if !pronta {
            sessione.beginConfiguration()
            sessione.sessionPreset = .high
            guard let d = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front), let i = try? AVCaptureDeviceInput(device: d),
                  sessione.canAddInput(i) else { sessione.commitConfiguration(); return }
            sessione.addInput(i)
            let o = AVCaptureVideoDataOutput()
            o.alwaysDiscardsLateVideoFrames = true
            o.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let l = LettoreViso(self); lettore = l
            o.setSampleBufferDelegate(l, queue: coda)
            if sessione.canAddOutput(o) { sessione.addOutput(o) }
            o.connection(with: .video)?.videoRotationAngle = 90
            o.connection(with: .video)?.isVideoMirrored = true
            sessione.commitConfiguration()
            pronta = true
        }
        let s = sessione
        coda.async { s.startRunning() }
    }

    func ferma() { let s = sessione; coda.async { s.stopRunning() } }

    nonisolated func ricevuto(_ v: VisoF?, lettura l: String) {
        Task { @MainActor in self.viso = v; if !l.isEmpty { self.lettura = l } }
    }
}

/// Legge i fotogrammi fuori dal main actor: Vision trova il viso e i suoi punti; dalla guancia la luce e il tono.
nonisolated final class LettoreViso: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private weak var padre: SpecchioTrucco?
    private var ultimo = Date.distantPast
    init(_ p: SpecchioTrucco) { padre = p }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(ultimo) > 0.12, let px = CMSampleBufferGetImageBuffer(sb) else { return }
        ultimo = Date()
        let r = VNDetectFaceLandmarksRequest()
        try? VNImageRequestHandler(cvPixelBuffer: px, orientation: .up).perform([r])
        guard let f = r.results?.first, let lm = f.landmarks else { padre?.ricevuto(nil, lettura: ""); return }
        let b = f.boundingBox
        func pt(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (r?.normalizedPoints ?? []).map { CGPoint(x: b.minX + $0.x * b.width, y: 1 - (b.minY + $0.y * b.height)) }
        }
        var v = VisoF()
        v.contorno = pt(lm.faceContour)
        v.occhioSx = pt(lm.leftEye); v.occhioDx = pt(lm.rightEye)
        v.sopraccSx = pt(lm.leftEyebrow); v.sopraccDx = pt(lm.rightEyebrow)
        v.labbra = pt(lm.outerLips)
        v.guanciaSx = CGPoint(x: b.minX + b.width * 0.22, y: 1 - (b.minY + b.height * 0.42))
        v.guanciaDx = CGPoint(x: b.minX + b.width * 0.78, y: 1 - (b.minY + b.height * 0.42))
        padre?.ricevuto(v, lettura: Self.leggiPelle(px, v.guanciaSx))
    }

    private static func leggiPelle(_ px: CVPixelBuffer, _ p: CGPoint) -> String {
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(px) == kCVPixelFormatType_32BGRA, let base = CVPixelBufferGetBaseAddress(px) else { return "" }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px), riga = CVPixelBufferGetBytesPerRow(px)
        let cx = Int(p.x * CGFloat(w)), cy = Int(p.y * CGFloat(h))
        var r = 0.0, g = 0.0, bl = 0.0, n = 0.0
        for y in max(0, cy - 8)..<min(h, cy + 8) { for x in max(0, cx - 8)..<min(w, cx + 8) {
            let q = base.advanced(by: y * riga + x * 4).assumingMemoryBound(to: UInt8.self)
            bl += Double(q[0]); g += Double(q[1]); r += Double(q[2]); n += 1
        } }
        guard n > 0 else { return "" }
        let luce = (r + g + bl) / (3 * n) / 255
        let caldo = r / max(bl, 1)
        let luceT = luce < 0.35 ? "poca luce: avvicinati a una finestra" : luce > 0.75 ? "luce forte" : "luce buona"
        let tono = caldo > 1.35 ? "sottotono caldo (oro, pesca)" : caldo < 1.15 ? "sottotono freddo (rosa, argento)" : "sottotono neutro"
        return "\(luceT.prefix(1).uppercased() + luceT.dropFirst()) · \(tono)."
    }
}

struct AnteprimaSpecchio: UIViewRepresentable {
    let sessione: AVCaptureSession
    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var anteprima: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Vista {
        let v = Vista(); v.anteprima.session = sessione; v.anteprima.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ v: Vista, context: Context) {}
}

/// La guida sul viso: Base (contorno e zone del blush), Occhi (la linea dall'angolo esterno), Labbra (il bordo).
struct GuidaViso: View {
    let viso: VisoF?
    let gruppo: Int
    let tinta: Color
    var body: some View {
        Canvas { gc, s in
            guard let v = viso else { return }
            func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x * s.width, y: q.y * s.height) }
            func linea(_ pt: [CGPoint], chiusa: Bool = false) -> Path {
                var path = Path(); guard let a = pt.first else { return path }
                path.move(to: p(a)); pt.dropFirst().forEach { path.addLine(to: p($0)) }; if chiusa { path.closeSubpath() }; return path
            }
            let stile = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            switch gruppo {
            case 0:
                gc.stroke(linea(v.contorno), with: .color(tinta.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                for g in [v.guanciaSx, v.guanciaDx] {
                    let c = p(g)
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - 22, y: c.y - 12, width: 44, height: 24)), with: .color(Color.rossoF.opacity(0.25)))
                }
            case 1:
                for (occhio, sopr) in [(v.occhioSx, v.sopraccSx), (v.occhioDx, v.sopraccDx)] {
                    gc.stroke(linea(occhio, chiusa: true), with: .color(tinta), style: stile)
                    guard let fuori = occhio.max(by: { abs($0.x - 0.5) < abs($1.x - 0.5) }), let coda = sopr.max(by: { abs($0.x - 0.5) < abs($1.x - 0.5) }) else { continue }
                    let a = p(fuori), b = p(coda)
                    var ala = Path(); ala.move(to: a); ala.addLine(to: CGPoint(x: a.x + (b.x - a.x) * 0.45, y: a.y + (b.y - a.y) * 0.45))
                    gc.stroke(ala, with: .color(Color.rossoF), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            default:
                gc.stroke(linea(v.labbra, chiusa: true), with: .color(tinta), style: stile)
            }
        }
        .allowsHitTesting(false)
    }
}
#endif
