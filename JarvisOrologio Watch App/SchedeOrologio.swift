import SwiftUI
import Charts
import WatchKit
import WeatherKit
import CoreLocation

// MARK: - Cornice e caricamento, versione da polso

/// Il ciano di JARVIS, lo stesso dell'iPhone.
enum TintaOrologio { static let ciano = Color(red: 0.31, green: 0.89, blue: 1.0) }

/// 5 nov (il signore: «apertura delle sezioni da circa 1 s a 0,4-0,5 s, uguale ovunque»): i tempi di apertura di tutte le
/// schede e schermate del polso, come sull'iPhone.
/// 5 nov pomeriggio (punti 1 e 2 approvati, come l'iPhone): caricamento 0,28 s, stampa 0,32 s, copertura che sfuma in 0,25 s.
/// 8 nov pomeriggio: la stampa non si usa più (la scheda compare tutta insieme, come sull'iPhone).
enum AperturaPolso {
    /// Il caricamento HUD (prima 0,45 s; ancora prima 0,9 s nelle schede, 1,1 s nelle pagine).
    static let caricamento = 0.28
    /// La scheda che si «stampa» dall'alto (prima 0,5 s; ancora prima 0,8 s).
    static let stampa = 0.32
    /// La copertura del caricamento che sfuma (prima 0,4 s).
    static let dissolvenza = 0.25
}

/// Una scheda sull'orologio: il nome in alto, il caricamento HUD (anelli, barra, sistemi) e poi il contenuto
/// che compare tutto insieme (8 nov; prima si stampava dall'alto). Stesso ciano di JARVIS, stesso ritmo dell'iPhone, in piccolo.
/// 27 ott: la GrigliaSfumata delle sezioni dell'iPhone, in scala col polso (schermo largo la metà): passo 28 → 14, sfumatura 520 → 260,
/// stesso centro, stesso colore; linea un filo più carica perché lo schermo del polso ha meno pixel per punto (2x invece di 3x).
struct GrigliaPolso: View {
    var body: some View {
        Canvas { gc, size in
            let passo: CGFloat = 14
            var g = Path()
            var x: CGFloat = 0
            while x < size.width { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height)); x += passo }
            var y: CGFloat = 0
            while y < size.height { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: size.width, y: y)); y += passo }
            gc.stroke(g, with: .color(Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.09)), lineWidth: 1)
        }
        .mask(RadialGradient(stops: [.init(color: .black, location: 0.25), .init(color: .clear, location: 0.8)],
                             center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 200))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CorniceOrologio<Contenuto: View>: View {
    let titolo: String
    var pronto = true
    var apertura = false            // Bea e Spesa: il suono «apertura» invece di quello delle schede
    @ViewBuilder let contenuto: () -> Contenuto
    @State private var mostrato = false
    @State private var caricamentoVia = false
    @State private var apertaDa = Date()

    var body: some View {
        ZStack {
            GrigliaPolso()                  // 27 ott (il signore): le sezioni come sull'iPhone (GrigliaSfumata)
            // 8 nov pomeriggio: la scheda è già pronta sotto il caricamento; a fine caricamento cambia solo la trasparenza
            // (tutta insieme, nessun fotogramma vuoto), e il caricamento si toglie a dissolvenza finita
            ScrollView {
                VStack(alignment: .leading, spacing: 8) { contenuto() }
                    .padding(.horizontal, 4)
            }
            .avvisaRighe()                       // MARK XI: toccando fuori da una riga di lato, la corona torna alla pagina
            .opacity(mostrato ? 1 : 0)
            .allowsHitTesting(mostrato)
            .accessibilityHidden(!mostrato)
            if !caricamentoVia {
                CaricamentoOrologio(titolo: titolo)
                    .opacity(mostrato ? 0 : 1)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(titolo)
        // già caricata (si torna indietro da Radar o Priorità, aperti da qui): niente caricamento né suoni da capo
        .onAppear {
            guard !mostrato else { return }
            apertaDa = Date(); WKInterfaceDevice.current().play(.start); if apertura { SuoniOrologio.apertura() } else { SuoniOrologio.schedaApre() }
        }
        .task(id: pronto) {
            guard pronto, !mostrato else { return }
            let resta = AperturaPolso.caricamento - Date().timeIntervalSince(apertaDa)
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            guard !Task.isCancelled else { return }       // uscito prima della fine: niente «pronta» a scheda chiusa
            WKInterfaceDevice.current().play(.success)
            SuoniOrologio.schedaPronta()
            // 8 nov pomeriggio (il signore: «clicchi, caricamento e carica TUTTA LA PAGINA… una pagina unica»), come l'iPhone:
            // niente più stampa dall'alto, il caricamento sfuma e la scheda compare tutta insieme
            withAnimation(.easeOut(duration: AperturaPolso.dissolvenza)) { mostrato = true }
            try? await Task.sleep(for: .seconds(AperturaPolso.dissolvenza + 0.05))
            caricamentoVia = true
        }
    }
}

struct CaricamentoOrologio: View {
    let titolo: String
    private let sistemi = ["CERVELLO", "SENSORI", "ANALISI", "SCHEDA"]
    @State private var inizio = Date()
    private let ciano = TintaOrologio.ciano

    var body: some View {
        TimelineView(.animation(minimumInterval: nil)) { ctx in                   // 4 nov: al massimo dell'orologio, 60 Hz (prima 30)
            let t = ctx.date.timeIntervalSinceReferenceDate
            let passato = ctx.date.timeIntervalSince(inizio)
            let avanzamento = min(0.92, 1 - exp(-passato / 1.6))
            let voce = min(sistemi.count - 1, Int(avanzamento * Double(sistemi.count) / 0.92))
            VStack(spacing: 10) {
                ZStack {
                    Path { p in
                        let l: CGFloat = 14, w: CGFloat = 110, h: CGFloat = 86
                        for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                            p.move(to: CGPoint(x: x, y: y + dy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
                        }
                    }
                    .stroke(ciano, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 110, height: 86)
                    Circle().stroke(ciano.opacity(0.15), lineWidth: 1).frame(width: 62, height: 62)
                    Circle().trim(from: 0, to: 0.28).stroke(ciano, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 62, height: 62).rotationEffect(.radians(t * 2.2))
                    Circle().trim(from: 0, to: 0.18).stroke(ciano.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        .frame(width: 46, height: 46).rotationEffect(.radians(-t * 3.1))
                    Text(titolo.uppercased()).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                    Rectangle().fill(ciano.opacity(0.5)).frame(width: 62, height: 1)
                        .offset(y: CGFloat(sin(t * 2.4)) * 30)
                        .mask(Circle().frame(width: 62, height: 62))
                }
                HStack(spacing: 2) {
                    ForEach(0..<16, id: \.self) { k in
                        Rectangle().fill(ciano.opacity(Double(k) < avanzamento * 16 ? 1 : 0.18)).frame(width: 6, height: 5)
                    }
                }
                Text("\(Int(avanzamento * 100))% · \(sistemi[voce])")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
            }
        }
        .onAppear { inizio = Date() }
    }
}

/// L'apertura da HUD per le pagine che esistevano già (Vitals, Ricordi, Cuore, Sentinella).
struct AperturaOrologio: ViewModifier {
    let titolo: String
    @State private var coperto = true
    func body(content: Content) -> some View {
        content
            .overlay { if coperto { ZStack { Color.black.ignoresSafeArea(); CaricamentoOrologio(titolo: titolo) }.transition(.opacity) } }
            // già scoperta (si torna indietro da Organismo, Traccia o Cuore, aperti da qui): niente caricamento né suoni da capo
            .onAppear { if coperto { WKInterfaceDevice.current().play(.start); SuoniOrologio.schedaApre() } }
            .task {
                guard coperto else { return }
                try? await Task.sleep(for: .seconds(AperturaPolso.caricamento))
                guard !Task.isCancelled else { return }   // uscito prima della fine: niente «pronta» a pagina chiusa
                WKInterfaceDevice.current().play(.success)
                SuoniOrologio.schedaPronta()
                withAnimation(.easeOut(duration: AperturaPolso.dissolvenza)) { coperto = false }
            }
    }
}

extension View {
    func aperturaOrologio(_ titolo: String) -> some View { modifier(AperturaOrologio(titolo: titolo)) }
}

/// Un numero grande con l'etichetta, da polso.
struct ValoreOrologio: View {
    let titolo: String
    let valore: String
    var sotto: String? = nil
    var colore: Color? = nil          // verde o rosso per gli stati positivi o negativi; altrimenti bianco
    private let ciano = TintaOrologio.ciano

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titolo).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
            Text(valore).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(colore ?? .white).minimumScaleFactor(0.6).lineLimit(1)
            if let sotto { Text(sotto).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ciano.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// 3 nov: le righe degli elenchi che si aggiornano (Spesa, Ricordi, Bea) si riconoscono dal loro numero nella memoria,
/// non dalla posizione: eliminata o spuntata una voce, l'animazione resta sulla riga giusta.
extension Dictionary where Key == String, Value == Any {
    nonisolated var chiaveRiga: String {
        if let n = self["id"] as? NSNumber { return "id\(n.intValue)" }
        return "t\(self["testo"] as? String ?? "")·\(self["quando_leggibile"] as? String ?? "")"
    }
}

struct IntestazioneOrologio: View {
    let testo: String
    var body: some View {
        Text(testo).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(TintaOrologio.ciano).padding(.top, 4)
    }
}

/// Il tasto che passa la parola a JARVIS: chiude la scheda e invia la frase.
struct TastoJarvisOrologio: View {
    let testo: String
    let frase: String
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.dismiss) private var chiudi
    var body: some View {
        Button { jarvis.chiedi(frase); chiudi() } label: { Label(testo, systemImage: "waveform").font(.footnote) }
            .tint(TintaOrologio.ciano)
    }
}

// MARK: - DIARIO

struct VistaDiarioOrologio: View {
    @State private var pagine: [DatiVitals.Pagina]?
    @State private var olo: DatiDiario?           // 11.0 (4): l'umore degli ultimi 7 giorni (la media accanto all'ologramma)
    @State private var sere = DiarioOlo()         // 11.0 (6): le prove dell'ologramma, la stessa scelta dell'iPhone
    @State private var errore = false
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Diario", pronto: pagine != nil || errore) {
            if let d = olo {
                HStack(spacing: 8) {
                    OlogrammaDiarioProve(dati: sere, piccolo: true).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("UMORE · 7 GIORNI").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                        Text(media(d)).font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                }
            }
            TastoJarvisOrologio(testo: "Scrivi la pagina di oggi", frase: "Jarvis, voglio scrivere il diario di oggi.")
            if let p = pagine {
                if p.isEmpty { Text("Ancora nessuna pagina, Sir.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(p.prefix(14)) { pg in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(pg.giorno).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                            Spacer()
                            if let u = pg.umore { Text(u).font(.system(size: 9)).foregroundStyle(.secondary) }
                        }
                        Text(pg.risposta).font(.footnote).lineLimit(4)
                    }
                    .padding(8).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if errore {
                Text("Non raggiungo il diario, Sir.").font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let o = await VistaVitalsOrologio.chiama(["vitals": true, "giorni": 60]) else { errore = true; return }
            let dv = DatiVitals(o, giorni: 60)
            var voti: [Date: Int] = [:]
            for g in dv.giorni { if let p = g.punteggio { voti[Calendar.current.startOfDay(for: g.data)] = Int(p.rounded()) } }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            let oggi = f.string(from: Date())
            olo = DatiDiario(voti: voti, oggi: dv.pagine.contains { $0.giorno == oggi })
            // le prove: l'umore di ogni sera (sul polso senza scritte: niente energia, parole e temi) e la pagina di oggi
            var righe: [(giorno: Date, v: Int?, e: Int?, u: String?, p: String?, temi: [String])] = []
            for g in dv.giorni {
                if let v = g.punteggio { righe.append((giorno: g.data, v: Int(v.rounded()), e: nil, u: nil, p: nil, temi: [])) }
            }
            if dv.pagine.contains(where: { $0.giorno == oggi }) && !righe.contains(where: { Calendar.current.isDateInToday($0.giorno) }) {
                righe.append((giorno: Date(), v: nil, e: nil, u: nil, p: nil, temi: []))
            }
            sere = DiarioOlo(pagine: righe)
            pagine = dv.pagine
        }
    }

    /// La media dell'umore degli ultimi 7 giorni con la pagina, all'italiana («6,6»).
    private func media(_ d: DatiDiario) -> String {
        let v = d.giorni.compactMap(\.voto)
        return v.isEmpty ? "—" : Olo.numero(Double(v.reduce(0, +)) / Double(v.count), decimali: 1)
    }
}

// MARK: - SONNO

struct VistaSonnoOrologio: View {
    @State private var oggi: SaluteOggi?
    @State private var notti: [(Date, Double)] = []
    @State private var notte: SonnoOlo?           // 11.0 (6): le prove dell'ologramma della notte, la stessa scelta dell'iPhone
    @State private var caricato = false
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Sonno", pronto: caricato) {
            HStack(spacing: 6) {
                // 5 nov sera (come l'iPhone): l'ologramma c'è sempre, anche senza i dati della notte
                OlogrammaSonnoProve(dati: notte ?? SonnoOlo(), piccolo: true).frame(width: 46, height: 46)
                ValoreOrologio(titolo: "DORMITO", valore: oggi?.sonno ?? "—", sotto: oggi?.orari)
            }
            if let f = oggi?.fasi { Text(f).font(.system(size: 10)).foregroundStyle(.secondary) }
            if let p = oggi?.pisolini { Text("Pisolino \(p)").font(.system(size: 10)).foregroundStyle(ciano) }
            if notti.count > 1 {
                IntestazioneOrologio(testo: "ULTIME 14 NOTTI")
                Chart {
                    ForEach(notti, id: \.0) { d, ore in
                        BarMark(x: .value("Notte", d, unit: .day), y: .value("Ore", ore))
                            .foregroundStyle(ore >= 7 ? ciano : ciano.opacity(0.45)).cornerRadius(2)
                    }
                    RuleMark(y: .value("Obiettivo", 7)).foregroundStyle(Color.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXAxis(.hidden).chartYAxis { AxisMarks(values: [0, 4, 8]) }
                .frame(height: 70)
                Text(String(format: "Media %.1f h", notti.map(\.1).reduce(0, +) / Double(notti.count))).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if caricato && oggi?.sonno == nil { Text("Nessun dato: porti l'orologio a letto.").font(.system(size: 10)).foregroundStyle(.secondary) }
            TastoJarvisOrologio(testo: "Com'ho dormito?", frase: "Come ho dormito stanotte?")
        }
        .task {
            async let o = SaluteOggi.leggi()
            async let g = SaluteStorica.giorni(14)
            async let f = SaluteStorica.notte()
            let (a, b, c) = await (o, g, f)
            oggi = a
            notti = b.compactMap { d, v in v.sonnoOre.map { (d, $0) } }.sorted { $0.0 < $1.0 }
            notte = c.isEmpty && notti.count < 2 ? nil : SonnoOlo(fasi: c, notti: notti)
            caricato = true
        }
    }
}

// MARK: - BRIEFING

struct VistaBriefingOrologio: View {
    @State private var salute: SaluteOggi?
    @State private var meteo: String?
    @State private var spesa = 0
    @State private var promesse: [String] = []
    @State private var posta: String?
    @State private var caricato = false
    @State private var giornata = BriefingOlo()    // 11.0 (6): le prove dell'ologramma della giornata, la stessa scelta dell'iPhone
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Briefing", pronto: caricato) {
            HStack(spacing: 8) {
                OlogrammaBriefingProve(dati: giornata, piccolo: true).frame(width: 46, height: 46)
                Text(saluto).font(.system(size: 14, weight: .medium))
            }
            TastoJarvisOrologio(testo: "Briefing a voce", frase: "Buongiorno Jarvis, il briefing per favore.")
            HStack(spacing: 6) {
                ValoreOrologio(titolo: "METEO", valore: meteo ?? "—")
                ValoreOrologio(titolo: "SONNO", valore: salute?.sonno ?? "—")
            }
            HStack(spacing: 6) {
                ValoreOrologio(titolo: "POSTA", valore: posta ?? "—", sotto: "non lette")
                ValoreOrologio(titolo: "SPESA", valore: "\(spesa)", sotto: "da comprare")
            }
            if let s = salute {
                HStack(spacing: 6) {
                    ValoreOrologio(titolo: "CUORE", valore: s.battito.map { "\($0)" } ?? "—", sotto: "a riposo")
                    ValoreOrologio(titolo: "PASSI", valore: s.passi.map { $0.formatted() } ?? "—")
                }
            }
            if !promesse.isEmpty {
                IntestazioneOrologio(testo: "PROMESSE")
                ForEach(promesse, id: \.self) { Text($0).font(.footnote) }
            }
        }
        .task {
            async let s = SaluteOggi.leggi()
            async let m = MeteoQui.adesso(ore: 3)
            let (ss, mm) = await (s, m)
            salute = ss
            if !mm.1, let d = mm.0.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let a = o["adesso"] as? [String: Any], let t = (a["temperatura"] as? NSNumber)?.intValue {
                meteo = "\(t)° \(a["cielo"] as? String ?? "")"
            }
            caricato = true
            await sole()
            // 11.0 (6): gli impegni di oggi dall'iPhone, per i bersagli del RADAR e i fari della PISTA
            let impegni = await PonteOrologio.condiviso.impegniDiOggi()
            giornata.impegni = impegni.map { BriefingOlo.Impegno(m: $0.m, nome: $0.nome, corto: BriefingOlo.corto($0.nome)) }
            if let o = await VistaVitalsOrologio.chiama(["ricordi": true]) {
                spesa = (o["spesa"] as? [Any])?.count ?? 0
                promesse = (o["promesse"] as? [[String: Any]] ?? []).prefix(3).compactMap { $0["testo"] as? String }
            }
            if let o = await VistaVitalsOrologio.chiama(["posta": true, "ore": 24]), o["errore"] == nil {
                posta = "\((o["non_lette"] as? NSNumber)?.intValue ?? 0)"
            }
        }
    }

    private var saluto: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Buongiorno, Sir." : h < 18 ? "Buon pomeriggio, Sir." : "Buonasera, Sir."
    }

    /// Alba e tramonto di oggi dove si trova (Apple Meteo), per l'ologramma della giornata.
    private func sole() async {
        var dove = CLLocation(latitude: 45.4642, longitude: 9.19)
        if let p = await PosizioneOrologio.attuale(), let lat = p["lat"] as? Double, let lon = p["lon"] as? Double { dove = CLLocation(latitude: lat, longitude: lon) }
        giornata.lat = dove.coordinate.latitude
        giornata.lon = dove.coordinate.longitude
        guard let g = try? await WeatherService.shared.weather(for: dove, including: .daily).forecast.first else { return }
        if let a = g.sun.sunrise { giornata.alba = DatiGiornata.minuti(a) }
        if let t = g.sun.sunset { giornata.tramonto = DatiGiornata.minuti(t) }
    }
}

// MARK: - METEO

struct VistaMeteoOrologio: View {
    @State private var meteo: Weather?
    @State private var luogo = "qui"
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Meteo", pronto: meteo != nil || errore != nil) {
            NavigationLink { VistaRadarOrologio() } label: { Label("Radar", systemImage: "cloud.rain") }   // build 22: RADAR
            if let m = meteo {
                let c = m.currentWeather
                HStack(spacing: 10) {
                    // 11.0 (3), come il mockup approvato: il cielo di adesso in ologramma, piccolo
                    OlogrammaCielo(stato: StatoCielo(c, probabilita: m.hourlyForecast.forecast.first?.precipitationChance), piccolo: true)
                        .frame(width: 46, height: 46)
                        .padding(-4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(gradi(c.temperature)).font(.system(size: 30, weight: .thin, design: .rounded))
                        Text(c.condition.description).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Text(luogo).font(.system(size: 9, design: .monospaced)).foregroundStyle(ciano)
                IntestazioneOrologio(testo: "PROSSIME ORE")
                // MARK XI: col dito come sempre; toccata, anche con la corona (un'ora per scatto)
                let ore = Array(m.hourlyForecast.forecast.filter { $0.date > Date().addingTimeInterval(-1800) }.prefix(12))
                RigaCorona(quanti: ore.count) {
                    HStack(spacing: 10) {
                        ForEach(Array(ore.enumerated()), id: \.element.date) { k, h in
                            VStack(spacing: 2) {
                                Text(h.date.formatted(.dateTime.hour())).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                                Image(systemName: h.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 13))
                                Text(gradi(h.temperature)).font(.system(size: 11, weight: .semibold))
                                Text(h.precipitationChance >= 0.1 ? "\(Int((h.precipitationChance * 100).rounded()))%" : " ").font(.system(size: 8)).foregroundStyle(ciano)
                            }
                            .id(k)
                        }
                    }
                }
                IntestazioneOrologio(testo: "PROSSIMI GIORNI")
                ForEach(Array(m.dailyForecast.forecast.prefix(5)), id: \.date) { g in
                    HStack(spacing: 6) {
                        Text(Calendar.current.isDateInToday(g.date) ? "Oggi" : g.date.formatted(.dateTime.weekday(.abbreviated)).capitalized)
                            .font(.system(size: 11)).frame(width: 34, alignment: .leading)
                        Image(systemName: g.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 12)).frame(width: 18)
                        Text(g.precipitationChance >= 0.1 ? "\(Int((g.precipitationChance * 100).rounded()))%" : "").font(.system(size: 8)).foregroundStyle(ciano).frame(width: 24)
                        Spacer()
                        Text("\(gradi(g.lowTemperature)) \(gradi(g.highTemperature))").font(.system(size: 11, design: .monospaced))
                    }
                }
                TastoJarvisOrologio(testo: "Mi serve l'ombrello?", frase: "Che tempo fa qui nelle prossime ore? Mi serve l'ombrello?")
                if let a = attribuzione { Text(a).font(.system(size: 7)).foregroundStyle(.secondary) }
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task { await carica() }
    }

    @State private var attribuzione: String?
    private func gradi(_ t: Measurement<UnitTemperature>) -> String { "\(Int(t.converted(to: .celsius).value.rounded()))°" }

    private func carica() async {
        var dove = CLLocation(latitude: 45.4642, longitude: 9.19)
        if let p = await PosizioneOrologio.attuale(), let lat = p["lat"] as? Double, let lon = p["lon"] as? Double { dove = CLLocation(latitude: lat, longitude: lon) }
        do {
            meteo = try await WeatherService.shared.weather(for: dove)
            if let geo = try? await CLGeocoder().reverseGeocodeLocation(dove).first, let n = geo.locality { luogo = n }
            attribuzione = " Meteo"
        } catch { errore = "Apple Meteo non risponde, Sir." }
    }
}

// MARK: - EMAIL

struct VistaPostaOrologio: View {
    @State private var posta: [[String: Any]]?
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Email", pronto: posta != nil || errore != nil) {
            NavigationLink { VistaPrioritaOrologio() } label: { Label("Priorità", systemImage: "exclamationmark.circle") }   // build 22: PRIORITÀ
            if let posta {
                let nonLette = posta.filter { !(($0["letta"] as? Bool) ?? true) }.count
                // v267: SMISTA in piccolo, come le altre sezioni (la riga con l'ologramma e il numero)
                HStack(spacing: 8) {
                    OlogrammaPosta(dati: postaOlo(posta), piccolo: true).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NON LETTE").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                        Text("\(nonLette) su \(posta.count)").font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("ultimi 3 giorni").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                TastoJarvisOrologio(testo: "Riassumi", frase: "Riassumimi la posta degli ultimi tre giorni: cosa conta davvero?")
                if posta.isEmpty { Text("Nessuna email, Sir.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(posta.prefix(20).enumerated()), id: \.offset) { _, m in
                    let letta = (m["letta"] as? Bool) ?? true
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if !letta { Circle().fill(ciano).frame(width: 5, height: 5) }
                            Text((m["da"] as? String ?? "").components(separatedBy: " <").first ?? "").font(.system(size: 11, weight: letta ? .regular : .bold)).lineLimit(1)
                        }
                        Text(m["oggetto"] as? String ?? "").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        Text(m["data"] as? String ?? "").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .padding(6).background(Color.white.opacity(letta ? 0.03 : 0.07)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let o = await VistaVitalsOrologio.chiama(["posta": true, "ore": 72]) else { errore = "Non raggiungo la posta, Sir."; return }
            if let e = o["errore"] as? String { errore = e; return }
            posta = o["email"] as? [[String: Any]] ?? []
        }
    }

    /// v267: le mail per l'ologramma SMISTA (il nome senza l'indirizzo, come nella lista).
    private func postaOlo(_ posta: [[String: Any]]) -> PostaOlo {
        PostaOlo(posta: posta.prefix(8).map { m in
            PostaOlo.Mail(nome: (m["da"] as? String ?? "").components(separatedBy: " <").first ?? "", oggetto: m["oggetto"] as? String ?? "",
                          data: m["data"] as? String ?? "", letta: (m["letta"] as? Bool) ?? true)
        })
    }
}

// MARK: - SPESA

struct VistaSpesaOrologio: View {
    @State private var voci: [[String: Any]]?
    @State private var presi = 0                  // 11.0 (4): spuntate in questa visita (il carrello in ologramma)
    @State private var prese: [SpesaOlo.Voce] = []  // 11.0 (6): quali (per le prove dell'ologramma: passano dalla cassa)
    @State private var errore = false
    private let ciano = TintaOrologio.ciano

    /// 3 nov (il signore): un elenco vero, come Ricordi e Bea, perché lo swipe «Elimina» funziona solo dentro una List.
    var body: some View {
        List {
            if let voci {
                Section {
                    if !voci.isEmpty || presi > 0 {
                        HStack(spacing: 8) {
                            OlogrammaSpesaProve(dati: spesaOlo(voci), piccolo: true).frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("PRESE").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                                Text("\(presi) su \(voci.count + presi)").font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(Array(voci.enumerated()), id: \.element.chiaveRiga) { _, r in
                        let testo = r["testo"] as? String ?? ""
                        Button { Task { await spunta(r) } } label: {
                            Label(testo.prefix(1).uppercased() + testo.dropFirst(), systemImage: "circle").font(.footnote)
                        }
                        .swipeActions {
                            Button(role: .destructive) { Task { await elimina(r) } } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text(voci.isEmpty ? "Lista vuota, Sir." : "\(voci.count) da comprare · tocchi per spuntare")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(ciano).textCase(nil)
                }
                Section {
                    TastoJarvisOrologio(testo: "Me la legga JARVIS", frase: "Leggimi la lista della spesa.")
                    TastoJarvisOrologio(testo: "Aggiungi a voce", frase: "Jarvis, aggiungi alla lista della spesa:")
                }
            } else if errore {
                Text("Non raggiungo la lista, Sir.").font(.footnote).foregroundStyle(.orange)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Spesa")
        .task { await carica() }
    }

    /// `presa`: appena spuntata una voce; la lista nuova e il carrello cambiano insieme (il cubo cade dentro una volta sola).
    private func carica(presa: Bool = false) async {
        guard let o = await VistaVitalsOrologio.chiama(["ricordi": true]) else { errore = true; return }
        voci = o["spesa"] as? [[String: Any]] ?? []
        if presa { presi += 1 }
    }
    private func spunta(_ r: [String: Any]) async {
        guard let id = (r["id"] as? NSNumber)?.intValue else { return }
        WKInterfaceDevice.current().play(.success)
        SuoniOrologio.fatto()
        _ = await VistaVitalsOrologio.chiama(["ricordo_fatto": id])
        prese.append(SpesaOlo.Voce(id: id, nome: r["testo"] as? String ?? "", qta: "", presa: true))
        await carica(presa: true)
    }

    /// Per le prove dell'ologramma (11.0 (6)): le cose da comprare e quelle spuntate qui, nell'ordine in cui sono state scritte
    /// (così non saltano di posto), al massimo 12.
    private func spesaOlo(_ voci: [[String: Any]]) -> SpesaOlo {
        let gia = Set(prese.map(\.id))
        var tutte: [SpesaOlo.Voce] = voci.compactMap { r in
            guard let id = (r["id"] as? NSNumber)?.intValue, !gia.contains(id) else { return nil }
            return SpesaOlo.Voce(id: id, nome: r["testo"] as? String ?? "", qta: "", presa: false)
        }
        tutte += prese
        tutte.sort { $0.id < $1.id }
        return SpesaOlo(voci: Array(tutte.prefix(12)))
    }
    private func elimina(_ r: [String: Any]) async {
        guard let id = (r["id"] as? NSNumber)?.intValue else { return }
        _ = await VistaVitalsOrologio.chiama(["ricordo_elimina": id]); await carica()
    }
}

// MARK: - SHAZAM

struct VistaShazamOrologio: View {
    enum Stato: Equatable { case fermo, ascolto, trovata, niente(String) }
    /// 5 nov (il signore: «Shazam deve attivarsi quando tocco il logo, invece parte da solo»): aperto aspetta il tocco sul logo.
    @State private var stato: Stato = .fermo
    @State private var brano: Musica.Brano?
    @State private var suona = false                 // MARK X: la canzone suona sull'iPhone; dal polso pausa e play
    @State private var avviso: String?
    @State private var fonte = "APPLE MUSIC"          // 8 nov: o «APPLE · ANTEPRIMA 30 S» (senza Apple Music, come lo Shazam dell'iPhone)
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Shazam") {
            VStack(spacing: 10) {
                logo
                    .frame(width: 92, height: 92)
                    .onTapGesture { Task { await ascolta() } }
                switch stato {
                case .fermo: Text("Tocchi il logo per ascoltare.").font(.footnote).foregroundStyle(.secondary)
                case .ascolto: Text("Ascolto la musica…").font(.footnote).foregroundStyle(.secondary)
                case .trovata:
                    if let b = brano {
                        Text(b.titolo).font(.system(size: 14, weight: .bold)).multilineTextAlignment(.center)
                        Text(b.artista).font(.footnote).foregroundStyle(ciano)
                        if let a = b.album { Text(a).font(.system(size: 9)).foregroundStyle(.secondary) }
                        Button { Task { await playPausa() } } label: {
                            Label(suona ? "PAUSA" : "PLAY", systemImage: suona ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .tint(ciano)
                        Text(avviso ?? "SUONA SULL'IPHONE · \(fonte)").font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(avviso == nil ? .secondary : Color.orange).multilineTextAlignment(.center)
                        TastoJarvisOrologio(testo: "Chieda a JARVIS", frase: "Raccontami qualcosa di «\(b.titolo)» di \(b.artista).")
                    }
                case .niente(let m):
                    Text(m).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    Button("Riprova") { Task { await ascolta() } }.tint(ciano)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Il logo olografico come sull'iPhone (più leggero: 5 strati), gira mentre ascolta e oscilla a riposo.
    private var logo: some View {
        TimelineView(.animation(minimumInterval: nil)) { tl in                    // 4 nov: al massimo dell'orologio, 60 Hz (prima 30)
            let t = tl.date.timeIntervalSinceReferenceDate
            let angolo = stato == .ascolto ? (t * 160).truncatingRemainder(dividingBy: 360) : sin(t * 0.9) * 38
            let rad = angolo * .pi / 180
            ZStack {
                Circle().stroke(ciano.opacity(stato == .ascolto ? 0.6 : 0.25), lineWidth: 1.5)
                ForEach(0..<5, id: \.self) { k in
                    Image(systemName: "shazam.logo")
                        .font(.system(size: 44, weight: .thin))
                        .foregroundStyle(ciano.opacity(k == 2 ? 0.95 : 0.2))
                        .offset(x: CGFloat(k - 2) * 1.6 * CGFloat(sin(rad)))
                        .rotation3DEffect(.degrees(angolo), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                }
                .shadow(color: ciano.opacity(0.7), radius: 8)
            }
        }
    }

    private func ascolta() async {
        guard stato != .ascolto else { return }
        stato = .ascolto; brano = nil; suona = false; avviso = nil
        switch await Musica.riconosci(secondi: 12) {
        case .trovato(let b):
            brano = b; stato = .trovata; WKInterfaceDevice.current().play(.success); SuoniOrologio.pronto()
            // la canzone parte subito sull'iPhone, come il player del telefono: Apple Music intero se può, se no l'anteprima di 30 s
            // (8 nov, il signore: «Shazam al polso senza Apple Music»)
            let d: [String: String] = ["id": b.appleMusicID ?? "", "cerca": "\(b.titolo) \(b.artista)", "titolo": b.titolo, "artista": b.artista]
            let j = String(decoding: (try? JSONSerialization.data(withJSONObject: d)) ?? Data("{}".utf8), as: UTF8.self)
            if let r = await PonteOrologio.condiviso.musica("brano:" + j) { suona = r.suona; avviso = r.errore; fonte = r.fonte ?? "APPLE MUSIC" }
            else { avviso = "L'IPHONE NON RISPONDE" }
        case .nessuno: stato = .niente("Non la riconosco, Sir. Avvicini il polso alla musica.")
        case .errore(let e): stato = .niente("Shazam non risponde: \(e)")
        }
    }

    private func playPausa() async {
        WKInterfaceDevice.current().play(.click)
        // 8 nov: «shazam:…», così comanda la fonte di Shazam (anche l'anteprima), non la coda di MUSICA
        if let r = await PonteOrologio.condiviso.musica(suona ? "shazam:pausa" : "shazam:play") { suona = r.suona; avviso = r.errore }
        else { avviso = "L'IPHONE NON RISPONDE" }
    }
}

// MARK: - SERATA

struct VistaSerataOrologio: View {
    @State private var conti: [String: Any]?
    @State private var nome = ""
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Serata", pronto: conti != nil || errore != nil) {
            if let c = conti {
                let tot = c["totali"] as? [String: Any] ?? [:]
                let ing = c["ingressi"] as? [String: Any] ?? [:]
                let margine = n(tot["margine_netto_iva"])
                let bar = c["bar"] as? [String: Any] ?? [:]
                Text(nome).font(.system(size: 10, design: .monospaced)).foregroundStyle(ciano)
                // 11.0 (6): l'ologramma dei soldi con la prova scelta sull'iPhone (FLUSSO, TORRI o REATTORE), le voci che incassano
                HStack(spacing: 6) {
                    OlogrammaSerataProve(dati: DatiSoldi(fonti: [DatiSoldi.Fonte(nome: "Ingressi contanti", valore: n(ing["contanti"])),
                                                                 DatiSoldi.Fonte(nome: "Ingressi POS", valore: n(ing["pos"])),
                                                                 DatiSoldi.Fonte(nome: "Resident Advisor", valore: n(ing["resident_advisor"])),
                                                                 DatiSoldi.Fonte(nome: "Bar contanti", valore: n(bar["contanti"])),
                                                                 DatiSoldi.Fonte(nome: "Bar POS", valore: n(bar["pos"]))].filter { $0.valore > 0 }), piccolo: true)
                        .frame(width: 46, height: 46)
                    ValoreOrologio(titolo: "INCASSO LORDO", valore: euro(n(tot["incasso_lordo"])), sotto: "netto IVA \(euro(n(tot["incasso_netto_iva"])))")
                }
                HStack(spacing: 6) {
                    ValoreOrologio(titolo: "INGRESSI", valore: euro(n(tot["ingressi_lordo"])), sotto: "\(Int(n(ing["biglietti_totali"]))) biglietti")
                    ValoreOrologio(titolo: "BAR", valore: euro(n(tot["bar_lordo"])))
                }
                HStack {
                    Text("MARGINE").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                    Spacer()
                    Text(euro(margine)).font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(margine >= 0 ? Color.green : Color.red)
                }
                .padding(8).background(Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 8))
                if let spese = c["spese"] as? [String: Any] {
                    Text("Spese \(euro(n(spese["totale"])))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                TastoJarvisOrologio(testo: "Analisi di JARVIS", frase: "Analizzami l'ultima serata: cosa ha funzionato e dove abbiamo perso soldi.")
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let e = await VistaVitalsOrologio.chiama(["serate": true]), let lista = e["serate"] as? [[String: Any]] else { errore = "Non raggiungo le serate, Sir."; return }
            let vera = lista.first { !(($0["nome"] as? String ?? "").lowercased().contains("demo")) } ?? lista.first
            guard let s = vera else { errore = "Nessuna serata registrata."; return }
            nome = "\(s["nome"] as? String ?? "") · \((s["data"] as? String ?? "").prefix(10))"
            guard let o = await VistaVitalsOrologio.chiama(["serata": ["data": String((s["data"] as? String ?? "").prefix(10)), "nome": s["nome"] as? String ?? ""]]) else { errore = "Non raggiungo i conti, Sir."; return }
            if let er = o["errore"] as? String { errore = er } else { conti = o }
        }
    }

    private func n(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }
    private func euro(_ v: Double) -> String { v.formatted(.currency(code: "EUR").precision(.fractionLength(0))) }
}

// MARK: - SISTEMI: GitHub, Supabase, Archivio (versione da polso)

struct VistaGitHubOrologio: View {
    @State private var repository: [[String: Any]]?
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "GitHub", pronto: repository != nil || errore != nil) {
            if let repository {
                Text("\(repository.count) repository").font(.system(size: 10, design: .monospaced)).foregroundStyle(ciano)
                TastoJarvisOrologio(testo: "A che punto siamo?", frase: "A che punto sono i miei progetti su GitHub? In due frasi.")
                ForEach(Array(repository.prefix(12).enumerated()), id: \.offset) { _, r in
                    let ultimo = r["ultimo_commit"] as? [String: Any]
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(r["nome"] as? String ?? "").font(.system(size: 11, weight: .bold)).lineLimit(1)
                            Spacer()
                            Text(r["da"] as? String ?? "").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        if let m = ultimo?["messaggio"] as? String, !m.isEmpty { Text(m).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                        if let n = (r["issue_aperte"] as? NSNumber)?.intValue, n > 0 { Text("\(n) issue aperte").font(.system(size: 9, design: .monospaced)).foregroundStyle(.orange) }
                    }
                    .padding(6).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let o = await VistaVitalsOrologio.chiama(["github": true]) else { errore = "Non raggiungo GitHub, Sir."; return }
            if let e = o["errore"] as? String { errore = e; return }
            repository = o["repository"] as? [[String: Any]] ?? []
        }
    }
}

struct VistaSupabaseOrologio: View {
    @State private var stato: [String: Any]?
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Supabase", pronto: stato != nil || errore != nil) {
            if let stato {
                let log = stato["log"] as? [String: Any]
                let errori = ((log?["richieste"] as? [[String: Any]]) ?? []) + ((log?["console"] as? [[String: Any]]) ?? [])
                HStack(spacing: 6) {
                    ValoreOrologio(titolo: "DB", valore: "\(stato["database_mb"] ?? 0) MB")
                    ValoreOrologio(titolo: "ERRORI 24H", valore: "\(errori.count)", colore: errori.isEmpty ? .green : .red)
                }
                TastoJarvisOrologio(testo: "Come sta?", frase: "Come sta il cervello su Supabase? Prima ciò che non va, in due frasi.")
                if errori.isEmpty {
                    Text("Nessun errore nelle ultime 24 ore, Sir.").font(.system(size: 10)).foregroundStyle(.green)
                } else {
                    ForEach(Array(errori.prefix(8).enumerated()), id: \.offset) { _, r in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(r["livello"] as? String ?? "").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.red)
                                Spacer()
                                Text(r["quando"] as? String ?? "").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            Text(r["messaggio"] as? String ?? "").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .padding(6).background(Color.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                let funzioni = stato["funzioni"] as? [[String: Any]] ?? []
                ForEach(Array(funzioni.enumerated()), id: \.offset) { _, f in
                    HStack {
                        Circle().fill((f["stato"] as? String ?? "").uppercased() == "ACTIVE" ? Color.green : Color.orange).frame(width: 5, height: 5)
                        Text(f["nome"] as? String ?? "").font(.system(size: 10, design: .monospaced)).lineLimit(1)
                        Spacer()
                        Text("v" + String(describing: f["versione"] ?? 0)).font(.system(size: 9, design: .monospaced)).foregroundStyle(ciano)
                    }
                }
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let o = await VistaVitalsOrologio.chiama(["supabase": true, "ore": 24]) else { errore = "Non raggiungo la sala macchine, Sir."; return }
            if let e = o["errore"] as? String { errore = e; return }
            stato = o
        }
    }
}

struct VistaArchivioOrologio: View {
    @State private var file: [[String: Any]]?
    @State private var cartelle: [[String: Any]] = []
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Archivio", pronto: file != nil || errore != nil) {
            if let file {
                Text("\(file.count) file · \(cartelle.count) cartelle").font(.system(size: 10, design: .monospaced)).foregroundStyle(ciano)
                TastoJarvisOrologio(testo: "Cosa c'è?", frase: "Cosa c'è nel mio archivio? Le cartelle e le cose più recenti, in due frasi.")
                if file.isEmpty { Text("Archivio vuoto, Sir.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(file.prefix(20).enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f["nome"] as? String ?? "").font(.system(size: 11, weight: .bold)).lineLimit(1)
                        Text("\(f["cartella"] as? String ?? "") · \(String(describing: f["kb"] ?? 0)) KB · \(f["quando"] as? String ?? "")").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .padding(6).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let o = await VistaVitalsOrologio.chiama(["archivio": true]) else { errore = "Non raggiungo l'archivio, Sir."; return }
            if let e = o["errore"] as? String { errore = e; return }
            file = o["file"] as? [[String: Any]] ?? []
            cartelle = o["cartelle"] as? [[String: Any]] ?? []
        }
    }
}
