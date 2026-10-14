#if os(iOS)
import SwiftUI
import Charts

// MARK: - SHAZAM: che canzone è, e tutte quelle trovate

struct VistaShazam: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.shazam

    nonisolated struct Trovata: Codable, Identifiable, Sendable {
        var id = UUID()
        let titolo: String
        let artista: String
        let album: String?
        let copertina: URL?
        let link: URL?
        let generi: [String]
        let quando: Date
    }

    enum Stato: Equatable { case fermo, ascolto, trovata, niente(String) }

    @State private var stato: Stato = .fermo
    @State private var ultima: Trovata?
    @State private var storico: [Trovata] = []
    @State private var onda = false
    @State private var chiediCancella = false

    var body: some View {
        CorniceScheda(titolo: "Shazam", sottotitolo: sottotitolo, icona: "shazam.logo", tinta: tinta) {
            ascoltatore
            if let t = ultima, stato == .trovata { scheda(t) }
            if case .niente(let motivo) = stato {
                Text(motivo).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity)
            }
            if !storico.isEmpty {
                Pannello(titolo: "TROVATE · \(storico.count)", tinta: tinta) {
                    ForEach(storico) { t in rigaStorico(t) }
                    Button(role: .destructive) { chiediCancella = true } label: { Label("Cancella la cronologia", systemImage: "trash").font(.footnote) }
                        .tint(.red).padding(.top, 4)
                }
            }
        }
        .onAppear { storico = VistaShazam.leggi() }
        .task { await ascolta() }
        .confirmationDialog("Cancellare tutte le canzoni trovate?", isPresented: $chiediCancella, titleVisibility: .visible) {
            Button("Cancella", role: .destructive) { storico = []; VistaShazam.salva([]) }
        }
    }

    private var sottotitolo: String {
        switch stato {
        case .fermo: return "tocchi per ascoltare"
        case .ascolto: return "ascolto la musica…"
        case .trovata: return "trovata"
        case .niente: return "non riconosciuta"
        }
    }

    /// Il cerchio che ascolta: onde che si allargano finché sente.
    private var ascoltatore: some View {
        Button { Task { await ascolta() } } label: {
            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    Circle().stroke(tinta.opacity(0.35), lineWidth: 2)
                        .scaleEffect(stato == .ascolto && onda ? 1.6 + Double(k) * 0.25 : 1)
                        .opacity(stato == .ascolto && onda ? 0 : 0.7)
                        .animation(stato == .ascolto ? .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(k) * 0.45) : .default, value: onda)
                }
                Circle().fill(RadialGradient(colors: [tinta, tinta.opacity(0.55)], center: .center, startRadius: 0, endRadius: 80))
                    .shadow(color: tinta.opacity(0.7), radius: stato == .ascolto ? 24 : 10)
                Image(systemName: "shazam.logo.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
            }
            .frame(width: 150, height: 150)
        }
        .buttonStyle(StileStark())
        .disabled(stato == .ascolto)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func scheda(_ t: Trovata) -> some View {
        Pannello(tinta: tinta) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: t.copertina) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: tinta.opacity(0.4), radius: 10)
                VStack(alignment: .leading, spacing: 5) {
                    Text(t.titolo).font(.system(size: 19, weight: .bold)).foregroundStyle(.white)
                    Text(t.artista).font(.system(size: 15)).foregroundStyle(tinta)
                    if let a = t.album { Text(a).font(.system(size: 12)).foregroundStyle(Color.tenue) }
                    if !t.generi.isEmpty { Text(t.generi.joined(separator: " · ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue) }
                }
            }
            HStack(spacing: 10) {
                if let l = t.link {
                    Link(destination: l) {
                        Label("Apple Music", systemImage: "music.note")
                            .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                            .foregroundStyle(Color.fondo).background(tinta).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                Button { chiedi("Raccontami qualcosa di «\(t.titolo)» di \(t.artista): l'anno, la storia, e se c'è un vinile da cercare su Discogs.") } label: {
                    Label("Chieda a JARVIS", systemImage: "waveform")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                        .foregroundStyle(tinta).overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.6), lineWidth: 1))
                }
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private func rigaStorico(_ t: Trovata) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: t.copertina) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.titolo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(t.artista).font(.system(size: 12)).foregroundStyle(tinta).lineLimit(1)
            }
            Spacer()
            Text(t.quando.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
            if let l = t.link { Link(destination: l) { Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(tinta) } }
        }
        .contextMenu {
            Button(role: .destructive) { storico.removeAll { $0.id == t.id }; VistaShazam.salva(storico) } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    private func ascolta() async {
        guard stato != .ascolto else { return }
        withAnimation { stato = .ascolto; ultima = nil }
        onda = false
        try? await Task.sleep(for: .milliseconds(50))
        onda = true
        switch await Musica.riconosci(secondi: 12) {
        case .trovato(let b):
            let t = Trovata(titolo: b.titolo, artista: b.artista, album: b.album, copertina: b.copertina, link: b.appleMusic ?? b.web, generi: b.generi, quando: Date())
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Suoni.pronto()
            withAnimation(.spring(duration: 0.45)) { ultima = t; stato = .trovata }
            storico.insert(t, at: 0)
            VistaShazam.salva(storico)
        case .nessuno:
            withAnimation { stato = .niente("Non la riconosco, Sir: forse la musica è troppo bassa o c'è troppo rumore. Ritocchi il cerchio.") }
        case .errore(let e):
            withAnimation { stato = .niente("Shazam non risponde: \(e).") }
        }
        onda = false
    }

    private static let chiave = "shazamTrovate"
    static func leggi() -> [Trovata] {
        guard let d = UserDefaults.standard.data(forKey: chiave) else { return [] }
        return (try? JSONDecoder().decode([Trovata].self, from: d)) ?? []
    }
    static func salva(_ t: [Trovata]) {
        if let d = try? JSONEncoder().encode(Array(t.prefix(200))) { UserDefaults.standard.set(d, forKey: chiave) }
    }
}

// MARK: - FOTO: la galleria, con la ricerca per contenuto e periodo

struct VistaFotoScheda: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.foto

    enum Periodo: String, CaseIterable, Identifiable {
        case oggi = "Oggi", ieri = "Ieri", settimana = "7 giorni", mese = "30 giorni", tutte = "Tutte"
        var id: String { rawValue }
        var intervallo: (Date?, Date?) {
            let cal = Calendar.current
            let oggi = cal.startOfDay(for: Date())
            switch self {
            case .oggi: return (oggi, nil)
            case .ieri: return (oggi.addingTimeInterval(-86_400), oggi)
            case .settimana: return (oggi.addingTimeInterval(-7 * 86_400), nil)
            case .mese: return (oggi.addingTimeInterval(-30 * 86_400), nil)
            case .tutte: return (nil, nil)
            }
        }
    }

    /// Parole in italiano → etichette di Apple Vision (in inglese).
    private static let parole: [String: [String]] = [
        "cane": ["dog"], "gatto": ["cat"], "mare": ["sea", "beach"], "spiaggia": ["beach"], "montagna": ["mountain"], "neve": ["snow"],
        "cibo": ["food"], "pizza": ["pizza"], "auto": ["car"], "macchina": ["car"], "concerto": ["concert"], "festa": ["party", "concert"],
        "persone": ["people"], "folla": ["crowd"], "documento": ["document"], "documenti": ["document"], "screenshot": ["screenshot"],
        "tramonto": ["sunset"], "vinile": ["vinyl"], "dischi": ["vinyl"], "fiori": ["flower"], "città": ["city"], "graffiti": ["graffiti"],
        "muro": ["wall", "graffiti"], "selfie": ["selfie"], "bambino": ["baby", "child"], "torta": ["cake"], "vino": ["wine"], "birra": ["beer"],
        "scarpe": ["shoe"], "jeans": ["jeans", "denim"], "denim": ["denim", "jeans"], "dj": ["dj", "concert"], "laser": ["laser", "concert"],
    ]

    @State private var periodo: Periodo = .oggi
    @State private var cerca = ""
    @State private var foto: [Immagine]?
    @State private var nota: String?
    @State private var aperta: Int?

    var body: some View {
        CorniceScheda(titolo: "Foto", sottotitolo: foto.map { "\($0.count) foto · \(periodo.rawValue.lowercased())" } ?? "sfoglio la galleria", icona: "photo.on.rectangle", tinta: tinta, pronto: foto != nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Periodo.allCases) { p in
                        Button { Suoni.tocco(); periodo = p } label: {
                            Text(p.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(periodo == p ? Color.fondo : tinta)
                                .background(periodo == p ? tinta : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(tinta.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(tinta)
                TextField("Cosa cerca? cane, mare, concerto, vinile…", text: $cerca).foregroundStyle(.white).submitLabel(.search)
                if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
            }
            .padding(12)
            .background(tinta.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let foto {
                if foto.isEmpty {
                    Text(nota ?? "Nessuna foto in questo periodo.").font(.footnote).foregroundStyle(Color.tenue)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                    ForEach(Array(foto.enumerated()), id: \.offset) { k, f in
                        Button { aperta = k } label: {
                            Miniatura(immagine: f, lato: 300)
                                .frame(minHeight: 104, maxHeight: 104)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !foto.isEmpty {
                    TastoJarvis(testo: "Racconta la giornata in foto", icona: "waveform", tinta: tinta) {
                        chiedi("Guarda le mie foto di \(periodo == .tutte ? "recente" : periodo.rawValue.lowercased())\(cerca.isEmpty ? "" : " con \(cerca)") e raccontamele in breve.")
                    }
                }
            } else {
                ProgressView().tint(tinta).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .task(id: "\(periodo.rawValue)|\(cerca)") {
            try? await Task.sleep(for: .milliseconds(cerca.isEmpty ? 0 : 450))
            if !Task.isCancelled { await carica() }
        }
        .fullScreenCover(isPresented: Binding(get: { aperta != nil }, set: { if !$0 { aperta = nil } })) {
            if let foto, let k = aperta { VistaImmagini(immagini: foto, iniziale: k) }
        }
    }

    private func carica() async {
        guard await FotoLocali.autorizza() else { nota = "Serve l'accesso alle foto: Impostazioni › JARVIS › Foto."; foto = []; return }
        let (da, a) = periodo.intervallo
        let c = cerca.lowercased().trimmingCharacters(in: .whitespaces)
        let cosa = c.isEmpty ? [] : c.components(separatedBy: CharacterSet(charactersIn: " ,")).filter { !$0.isEmpty }.flatMap { VistaFotoScheda.parole[$0] ?? [$0] }
        let esito = await FotoLocali.cerca(cosa: cosa, da: da, a: a, luogo: nil, raggioKm: 5, album: nil, quante: cosa.isEmpty ? 120 : 60)
        nota = esito.nota
        withAnimation(.easeOut(duration: 0.25)) { foto = esito.trovate.map { Immagine(fonte: "Le sue foto", locale: $0) } }
    }
}

// MARK: - SERATA: i conti di una serata Discosizer

struct VistaSerata: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.serata

    struct Serata: Identifiable, Hashable {
        let id: String
        let nome: String
        let data: String
        let chiusa: Bool
        var giorno: Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: String(data.prefix(10)))
        }
        var prova: Bool { nome.lowercased().contains("demo") || nome.lowercased().contains("prova") }
    }

    @State private var serate: [Serata] = []
    @State private var scelta: Serata?
    @State private var conti: [String: Any]?
    @State private var errore: String?

    var body: some View {
        CorniceScheda(titolo: "Serata", sottotitolo: scelta.map { "\($0.nome) · \($0.giorno?.formatted(date: .abbreviated, time: .omitted) ?? $0.data)" } ?? "apro i conti",
                      icona: "music.note.list", tinta: tinta, pronto: conti != nil || errore != nil) {
            if !serate.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(serate) { s in
                            Button { Suoni.tocco(); scelta = s } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.nome).font(.system(size: 12, weight: .bold)).lineLimit(1)
                                    Text(s.giorno?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) ?? s.data)
                                        .font(.system(size: 10, design: .monospaced))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(scelta == s ? Color.fondo : tinta)
                                .background(scelta == s ? tinta : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.5), lineWidth: 1))
                                .opacity(s.prova ? 0.55 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let c = conti { riepilogo(c) }
            else if let errore { Text(errore).font(.footnote).foregroundStyle(.orange) }
            else { ProgressView().tint(tinta).frame(maxWidth: .infinity).padding(.top, 40) }
        }
        .task { await caricaElenco() }
        .task(id: scelta?.id) { if let s = scelta { await carica(s) } }
    }

    private func n(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }
    private func euro(_ v: Double) -> String { v.formatted(.currency(code: "EUR").precision(.fractionLength(0))) }

    @ViewBuilder private func riepilogo(_ c: [String: Any]) -> some View {
        let tot = c["totali"] as? [String: Any] ?? [:]
        let ing = c["ingressi"] as? [String: Any] ?? [:]
        let bar = c["bar"] as? [String: Any] ?? [:]
        let spese = c["spese"] as? [String: Any] ?? [:]
        let margine = n(tot["margine_netto_iva"])

        Pannello(tinta: tinta) {
            Text("INCASSO LORDO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            Text(euro(n(tot["incasso_lordo"]))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white)
            HStack {
                Text("Netto IVA \(euro(n(tot["incasso_netto_iva"])))").font(.system(size: 12)).foregroundStyle(Color.tenue)
                Spacer()
                Text("Margine \(euro(margine))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(margine >= 0 ? Color(red: 0.45, green: 0.92, blue: 0.6) : Color(red: 1.0, green: 0.45, blue: 0.4))
            }
        }

        HStack(spacing: 10) {
            Valore(titolo: "INGRESSI", valore: euro(n(tot["ingressi_lordo"])), sotto: "\(Int(n(ing["biglietti_totali"]))) biglietti", tinta: tinta)
            Valore(titolo: "BAR", valore: euro(n(tot["bar_lordo"])), sotto: "contanti \(euro(n(bar["contanti"]))) · POS \(euro(n(bar["pos"])))", tinta: tinta)
        }

        Pannello(titolo: "DA DOVE ARRIVANO I SOLDI", tinta: tinta) {
            let fette: [(String, Double)] = [("Ingressi contanti", n(ing["contanti"])), ("Ingressi POS", n(ing["pos"])),
                                              ("Resident Advisor", n(ing["resident_advisor"])), ("Bar contanti", n(bar["contanti"])), ("Bar POS", n(bar["pos"]))].filter { $0.1 > 0 }
            if fette.isEmpty { Text("Nessun incasso registrato.").font(.footnote).foregroundStyle(Color.tenue) }
            else {
                Chart(fette, id: \.0) { nome, v in
                    SectorMark(angle: .value("Euro", v), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(by: .value("Voce", nome))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(range: [tinta, tinta.opacity(0.6), Color(red: 1.0, green: 0.8, blue: 0.4), Color(red: 0.4, green: 0.8, blue: 1.0), Color(red: 0.4, green: 0.6, blue: 1.0)])
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 190)
            }
        }

        if let venduti = bar["venduti"] as? [String: Any] {
            let righe = ["drink", "birra", "acqua", "chupito", "analcolico"].map { ($0.capitalized, n(venduti[$0])) }.filter { $0.1 > 0 }
            if !righe.isEmpty {
                Pannello(titolo: "BAR · PEZZI VENDUTI", tinta: tinta) {
                    Chart(righe, id: \.0) { nome, v in
                        BarMark(x: .value("Pezzi", v), y: .value("Cosa", nome)).foregroundStyle(tinta.gradient).cornerRadius(4)
                            .annotation(position: .trailing) { Text("\(Int(v))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white) }
                    }
                    .frame(height: CGFloat(righe.count) * 30 + 10)
                }
            }
        }

        if let cat = spese["per_categoria"] as? [String: Any], !cat.isEmpty {
            let righe = cat.map { ($0.key.capitalized, n($0.value)) }.sorted { $0.1 > $1.1 }
            Pannello(titolo: "SPESE · \(euro(n(spese["totale"])))", tinta: tinta) {
                ForEach(righe, id: \.0) { nome, v in
                    HStack {
                        Text(nome).font(.system(size: 14)).foregroundStyle(.white)
                        Spacer()
                        Text(euro(v)).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                    }
                }
            }
        }

        if let b = ing["biglietti_per_prezzo"] as? [[String: Any]], !b.isEmpty {
            Pannello(titolo: "BIGLIETTI PER PREZZO", tinta: tinta) {
                ForEach(Array(b.enumerated()), id: \.offset) { _, x in
                    HStack {
                        Text(euro(n(x["prezzo"]))).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                        Spacer()
                        Text("× \(Int(n(x["quantita"])))").font(.system(size: 14, design: .monospaced)).foregroundStyle(.white)
                    }
                }
            }
        }

        if let note = c["note"] as? String { Text(note).font(.system(size: 11)).foregroundStyle(Color.tenue) }
        TastoJarvis(testo: "Analisi di JARVIS", icona: "waveform", tinta: tinta) {
            chiedi("Analizzami la serata \(scelta?.nome ?? "") del \(scelta?.data ?? ""): cosa ha funzionato, dove abbiamo perso soldi e cosa cambierei la prossima volta.")
        }
    }

    private func caricaElenco() async {
        guard let o = await VistaVitals.chiama(["serate": true]) else { errore = "Non raggiungo le serate, Sir."; return }
        let lista = (o["serate"] as? [[String: Any]] ?? []).compactMap { s -> Serata? in
            guard let id = s["id"] as? String else { return nil }
            return Serata(id: id, nome: s["nome"] as? String ?? "Serata", data: s["data"] as? String ?? "", chiusa: s["chiusa_il"] != nil && !(s["chiusa_il"] is NSNull))
        }
        serate = lista
        if scelta == nil { scelta = lista.first { !$0.prova } ?? lista.first }
        if lista.isEmpty { errore = "Nessuna serata registrata." }
    }

    private func carica(_ s: Serata) async {
        conti = nil
        errore = nil
        guard let o = await VistaVitals.chiama(["serata": ["data": String(s.data.prefix(10)), "nome": s.nome]]) else { errore = "Non raggiungo i conti, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        withAnimation(.easeOut(duration: 0.3)) { conti = o }
    }
}
#endif
