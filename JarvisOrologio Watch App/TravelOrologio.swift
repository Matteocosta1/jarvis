import SwiftUI
import WatchKit
import Combine

/// TRAVEL al polso (mockup approvato dal signore il 26 ott sera): sei pagine come l'iPhone (MEZZI · TRENI · VOLI · PIEDI · BICI · TAXI),
/// una per volta, in verticale: si passa dall'una all'altra con la Digital Crown o col dito, i puntini a destra dicono dove si è.
/// A voce si apre già sulla pagina chiesta («come arrivo da Bea?» → MEZZI, «a che ora parte il treno?» → TRENI…).
/// I dati li calcola l'iPhone (PonteTravel, Travel.swift) con la posizione dell'orologio: gli stessi della schermata TRAVEL.

private enum ColoriTravel {
    static let ciano = TintaOrologio.ciano
    static let testo = Color(red: 0.812, green: 0.886, blue: 0.910)     // #cfe2e8
    static let chiaro = Color(red: 0.902, green: 0.957, blue: 0.973)    // #e6f4f8
    static let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)        // #4d666f
    static let verde = Color(red: 0.373, green: 0.890, blue: 0.631)     // #5fe3a1
    static let giallo = Color(red: 1, green: 0.824, blue: 0.478)        // #ffd27a
    static let ambra = Color(red: 1, green: 0.624, blue: 0.263)         // #ff9f43
    static let scuro = Color(red: 0.0, green: 0.094, blue: 0.125)       // #001820

    static func linea(_ hex: String) -> Color {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return Color(red: 200 / 255, green: 0, blue: 26 / 255) }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Il tasto largo del polso del mockup (.wb): il testo a sinistra, il segno a destra; acceso, pieno di ciano.
private struct TastoTravel: View {
    let testo: String
    var segno = "›"
    var acceso = false
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack {
                Text(testo).lineLimit(1)
                Spacer(minLength: 4)
                Text(segno)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
            .foregroundStyle(acceso ? ColoriTravel.scuro : ColoriTravel.chiaro)
            .padding(.vertical, 7).padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(acceso ? ColoriTravel.ciano : ColoriTravel.ciano.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColoriTravel.ciano.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct VistaTravelOrologio: View {
    /// Il luogo detto a voce (vuoto: il primo dei suoi luoghi salvati) e la pagina da aprire.
    let detto: String
    let iniziale: String
    @StateObject private var bussola = Bussola()
    @State private var pagina: SchedaTravel = .mezzi
    @State private var meta: LuogoSat?
    @State private var dati: [SchedaTravel: [String: Any]] = [:]
    @State private var errore: String?
    @State private var mostrato = false
    @State private var apertaDa = Date()
    @State private var guida = false
    @State private var avvisoInCorso = false

    var body: some View {
        ZStack {
            if mostrato {
                TabView(selection: $pagina) {
                    ForEach(SchedaTravel.allCases) { s in
                        contenuto(s).tag(s)
                    }
                }
                .tabViewStyle(.verticalPage)
                .transition(.opacity)
            } else {
                CaricamentoOrologio(titolo: "TRAVEL")
            }
        }
        .navigationDestination(isPresented: $guida) { VistaGuidaOrologio() }
        .onAppear {
            guard !mostrato else { return }
            apertaDa = Date()
            pagina = SchedaTravel(rawValue: iniziale) ?? .mezzi
            WKInterfaceDevice.current().play(.start)
            SuoniOrologio.schedaApre()
            bussola.accendi()
        }
        .onDisappear { bussola.spegni() }
        .task { await prepara() }
        .onChange(of: pagina) { _, s in
            WKInterfaceDevice.current().play(.click)
            Task { await carica(s) }
        }
    }

    // MARK: Le pagine (come il mockup)

    @ViewBuilder private func contenuto(_ s: SchedaTravel) -> some View {
        VStack(spacing: 4) {
            Text("TRAVEL · \(s == .mezzi ? (meta?.nome.uppercased() ?? "MEZZI") : s.titolo)")
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(ColoriTravel.ciano).lineLimit(1)
            if let errore {
                nota(errore, colore: .orange)
            } else if let d = dati[s] {
                if let e = d["errore"] as? String {
                    nota(e, colore: .orange)
                } else {
                    vistaPagina(s, d)
                }
            } else {
                nota("CARICO…", colore: ColoriTravel.tenue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.trailing, 6)                              // i puntini delle pagine stanno a destra
    }

    @ViewBuilder private func vistaPagina(_ s: SchedaTravel, _ d: [String: Any]) -> some View {
        switch s {
        case .mezzi:
            let esci = Date(timeIntervalSince1970: (d["esci"] as? Double) ?? 0)
            let avviso = (d["avviso"] as? Double) ?? 0
            nota("ESCI ALLE", colore: ColoriTravel.tenue)
            grande(DatiTravel.ora(esci))
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                let sec = Int(esci.timeIntervalSince(tl.date))
                Text(sec > 0 ? "fra \(sec / 60) min \(String(format: "%02d", sec % 60)) s" : "esca adesso")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ColoriTravel.chiaro)
            }
            VStack(spacing: 3) {
                ForEach(Array(((d["righe"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, r in
                    riga(sigla: r["s"] as? String ?? "", colore: r["c"] as? String ?? "", r["t"] as? String ?? "", r["o"] as? String ?? "")
                }
            }
            TastoTravel(testo: avviso > 0 ? "AVVISO \(DatiTravel.ora(Date(timeIntervalSince1970: avviso)))" : "AVVISAMI",
                        segno: avviso > 0 ? "✓" : "›", acceso: avviso > 0) {
                WKInterfaceDevice.current().play(.click); SuoniOrologio.tick()
                Task { await avvisa() }
            }
            .disabled(avvisoInCorso)
        case .treni:
            nota("\(d["stazione"] as? String ?? "Stazione") · \(d["letti"] as? String ?? "")", colore: ColoriTravel.tenue)
            VStack(spacing: 3) {
                ForEach(Array(((d["partenze"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, t in
                    let rit = (t["r"] as? Int) ?? 0
                    HStack(spacing: 4) {
                        (Text(t["o"] as? String ?? "").bold() + Text(" \(t["d"] as? String ?? "")"))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 2)
                        (Text(rit > 0 ? "+\(rit)" : "orario").foregroundStyle(rit > 5 ? ColoriTravel.ambra : rit > 0 ? ColoriTravel.giallo : ColoriTravel.verde)
                         + Text(" · \(t["b"] as? String ?? "—")").foregroundStyle(ColoriTravel.tenue))
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .font(.system(size: 10)).foregroundStyle(ColoriTravel.testo)
                }
            }
            nota("ritardo · binario", colore: ColoriTravel.tenue)
        case .voli:
            Text(d["volo"] as? String ?? "—").font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            nota(d["tratta"] as? String ?? "", colore: ColoriTravel.tenue)
            VStack(spacing: 3) {
                riga("Parte", d["parte"] as? String ?? "—")
                riga("Gate", d["gate"] as? String ?? "—")
                HStack {
                    Text("Stato")
                    Spacer()
                    Text(d["stato"] as? String ?? "—").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(coloreStato(d["colore"] as? String ?? ""))
                }
                .font(.system(size: 10)).foregroundStyle(ColoriTravel.testo)
            }
            if let v = d["verso"] as? String { nota(v, colore: ColoriTravel.tenue) }
        case .piedi:
            nota("A PIEDI", colore: ColoriTravel.tenue)
            grande("\(d["minuti"] as? Int ?? 0) min")
            nota("\(d["km"] as? String ?? "—") km · arrivo \(d["arrivo"] as? String ?? "—") se esce adesso", colore: ColoriTravel.tenue)
            TastoTravel(testo: "GUIDA") {
                WKInterfaceDevice.current().play(.click); SuoniOrologio.tick()
                Task { await avviaGuida() }
            }
        case .bici:
            VStack(spacing: 3) {
                ForEach(Array(((d["stazioni"] as? [[String: Any]]) ?? []).enumerated()), id: \.offset) { _, b in
                    HStack(spacing: 4) {
                        Text("\(b["n"] as? String ?? "BikeMi")\(Text(" \(b["m"] as? String ?? "")").foregroundStyle(ColoriTravel.tenue))")
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 2)
                        Text("\(b["b"] as? Int ?? 0) · \(b["e"] as? Int ?? 0)⚡").font(.system(size: 10, design: .monospaced)).foregroundStyle(ColoriTravel.tenue)
                    }
                    .font(.system(size: 10)).foregroundStyle(ColoriTravel.testo)
                }
                if ((d["stazioni"] as? [Any]) ?? []).isEmpty { nota("Nessuna stazione BikeMi qui vicino, Sir.", colore: ColoriTravel.tenue) }
            }
            nota("bici · elettriche ⚡ · BikeMi", colore: ColoriTravel.tenue)
        case .taxi:
            nota("RADIOTAXI", colore: ColoriTravel.tenue)
            grande("02 8585", misura: 28)
            nota((d["minuti"] as? Int).map { minuti in "\(minuti) min in auto fino \(meta.map { l in "a \(l.nome)" } ?? "lì")" } ?? "stima del tragitto…", colore: ColoriTravel.tenue)
            TastoTravel(testo: "CHIAMA") {
                WKInterfaceDevice.current().play(.click); SuoniOrologio.tick()
                if let u = URL(string: "tel:028585") { WKApplication.shared().openSystemURL(u) }
            }
        }
    }

    private func nota(_ t: String, colore: Color) -> some View {
        Text(t).font(.system(size: 9)).foregroundStyle(colore).multilineTextAlignment(.center)
    }

    private func grande(_ t: String, misura: CGFloat = 34) -> some View {
        Text(t).font(.system(size: misura, weight: .bold, design: .monospaced)).foregroundStyle(ColoriTravel.ciano)
            .shadow(color: ColoriTravel.ciano.opacity(0.45), radius: 6)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func riga(sigla: String = "", colore: String = "", _ t: String, _ o: String) -> some View {
        HStack(spacing: 4) {
            if !sigla.isEmpty {
                Text(sigla).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .frame(width: 17, height: 17).background(Circle().fill(ColoriTravel.linea(colore)))
            }
            Text(t).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            Text(o).font(.system(size: 10, design: .monospaced)).foregroundStyle(ColoriTravel.tenue)
        }
        .font(.system(size: 10)).foregroundStyle(ColoriTravel.testo)
    }

    private func coloreStato(_ k: String) -> Color {
        switch k {
        case "ver": return ColoriTravel.verde
        case "amb": return ColoriTravel.ambra
        case "ros": return .red
        default: return ColoriTravel.ciano
        }
    }

    // MARK: I dati (dall'iPhone)

    private func prepara() async {
        if let o = await VistaVitalsOrologio.chiama(["ricordi": true]) {
            let luoghi = LuogoSat.daRicordi(o)
            meta = detto.isEmpty ? luoghi.first : (LuogoSat.trova(detto, in: luoghi) ?? luoghi.first)
        }
        if meta == nil { errore = detto.isEmpty ? "Nessun luogo salvato, Sir." : "Non trovo «\(detto)» tra i suoi luoghi, Sir." }
        // come le altre schede del polso: 0,45 s di caricamento con i suoni, poi la pagina
        let resta = AperturaPolso.caricamento - Date().timeIntervalSince(apertaDa)
        if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
        guard !Task.isCancelled else { return }
        WKInterfaceDevice.current().play(.success)
        SuoniOrologio.schedaPronta()
        withAnimation(.easeOut(duration: 0.3)) { mostrato = true }
        await carica(pagina)
    }

    private func messaggio(_ s: SchedaTravel, cosa: String) async -> [String: Any] {
        // la posizione dell'orologio, se c'è (al massimo 2 s per averla); se no l'iPhone usa la sua
        for _ in 0..<20 where bussola.lat == nil { try? await Task.sleep(for: .milliseconds(100)) }
        var m: [String: Any] = ["travel": cosa, "scheda": s.rawValue]
        if let l = meta { m["meta"] = l.nome; m["metaLat"] = l.lat; m["metaLon"] = l.lon }
        if let la = bussola.lat, let lo = bussola.lon { m["lat"] = la; m["lon"] = lo }
        if s == .voli, let v = DatiTravel.numeroVolo(detto) { m["volo"] = v }
        return m
    }

    private func carica(_ s: SchedaTravel) async {
        guard meta != nil || s == .treni || s == .voli, dati[s] == nil || s == .mezzi else { return }
        let r = await PonteOrologio.condiviso.travel(await messaggio(s, cosa: "dati"))
        dati[s] = r ?? ["errore": "iPhone non raggiungibile, Sir: TRAVEL prende i dati da lì."]
    }

    private func avvisa() async {
        guard !avvisoInCorso else { return }
        avvisoInCorso = true
        defer { avvisoInCorso = false }
        guard let r = await PonteOrologio.condiviso.travel(await messaggio(.mezzi, cosa: "avvisa")) else {
            WKInterfaceDevice.current().play(.failure); return
        }
        if let e = r["errore"] as? String { dati[.mezzi]?["errore"] = e; WKInterfaceDevice.current().play(.failure); return }
        dati[.mezzi]?["avviso"] = r["avviso"]
        WKInterfaceDevice.current().play((r["avviso"] as? Double ?? 0) > 0 ? .success : .click)
    }

    private func avviaGuida() async {
        guard let l = meta else { return }
        if let e = await GuidaPolso.condivisa.avvia(l) {
            dati[.piedi]?["errore"] = e
            WKInterfaceDevice.current().play(.failure)
            return
        }
        guida = true
    }
}
