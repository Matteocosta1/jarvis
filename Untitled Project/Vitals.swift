#if os(iOS)
import SwiftUI
import Charts

/// Vitals: tutti i parametri vitali del signore in un posto solo, come JARVIS li legge a Stark nell'armatura.
/// Oggi: sonno con le fasi, battito a riposo, passi, calorie, allenamenti (dall'app Salute).
/// Nel tempo: umore (ricavato da JARVIS dal diario della sera) incrociato con sonno, battito e passi.
/// Sotto, il diario da rileggere e cancellare. In cima (build 22) l'ORGANISMO: la persona olografica con la prontezza.
struct VistaVitals: View {
    /// Per chiedere qualcosa a JARVIS a voce (chiude la pagina e invia la frase).
    let chiedi: (String) -> Void
    @Environment(\.chiudiOVia) private var chiudi
    @State private var giorni = 30
    @State private var dati: DatiVitals?
    @State private var oggi: SaluteOggi?
    @State private var carico = false
    @State private var errore: String?
    @State private var confermaTutto = false
    @State private var storia: [Date: SaluteStorica.Valori] = [:]      // 9 nov: per l'ologramma (sonno medio, battito, passi di ieri)

    var body: some View {
        ZStack {
            SfondoSezione()   // 7 nov: lo sfondo di tutte le sezioni
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 9 nov (build 19, il signore: «falli tutti J»): in testa l'ologramma con le prove SCANSIONE, ANELLI, RADAR, come il mockup
                    OlogrammaVitalsProve(dati: DatiVitalsOlo.da(DatiOrganismo.calcola(oggi: oggi, storia: storia, diario: dati), giorni: dati?.giorni ?? []))
                        .corniceOlo(Color.ciano)
                    // BUILD 22 · B — ORGANISMO e A VOCE, come nel mockup (Organismo.swift)
                    PannelloOrganismo(oggi: oggi, diario: dati)
                    PannelloAVoce(frasi: ["«Jarvis, scansione organismo»", "«Jarvis, stato dell'organismo»", "«Jarvis, come sto oggi?»"])
                    sezioneOggi

                    Picker("Periodo", selection: $giorni) {
                        Text("7 giorni").tag(7)
                        Text("30 giorni").tag(30)
                        Text("90 giorni").tag(90)
                    }
                    .pickerStyle(.segmented)

                    if let d = dati {
                        riquadri(d)
                        grafico(d)
                        if !d.battiti.isEmpty { graficoBattito(d) }
                        if !d.passiGiorni.isEmpty { graficoPassi(d) }
                        lettura(d)
                        Button { chiedi("Jarvis, come sto ultimamente? Guarda i miei Vitals degli ultimi \(giorni) giorni.") } label: {
                            Label("Chieda a JARVIS come sta", systemImage: "waveform")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .foregroundStyle(Color.fondo).background(Color.ciano2)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(StileStark())
                        diario(d)
                    } else if let errore {
                        Text(errore).foregroundStyle(.orange).font(.footnote)
                    } else {
                        AttesaAnello().frame(maxWidth: .infinity).padding(.top, 60)   // 8 nov: l'anello del mockup (.attesa-l)
                    }
                }
                .padding(16)
            }
            .modifier(ConBarraChiudi(tinta: Color.ciano, testata: DatiTestata(titolo: "Vitals", sottotitolo: "parametri vitali", icona: "waveform.path.ecg")) { chiudi() })   // 7 nov sera: la testata nella riga di «Chiudi»
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: giorni) { await carica() }
        .task { storia = await SaluteStorica.giorni(30) }
        .confirmationDialog("Cancellare tutto il diario? Non si può tornare indietro.", isPresented: $confermaTutto, titleVisibility: .visible) {
            Button("Cancella tutto", role: .destructive) { Task { await cancella("tutto") } }
            Button("Annulla", role: .cancel) {}
        }
        .preferredColorScheme(.dark)
        .aperturaHUD("Vitals", icona: "waveform.path.ecg")
    }

    // MARK: Pezzi della pagina

    /// Oggi, dall'app Salute: si carica subito, anche senza rete.
    private var sezioneOggi: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OGGI").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            if let o = oggi {
                HStack(spacing: 10) {
                    riquadro("SONNO", o.sonno ?? "—", sotto: o.orari ?? "stanotte")
                    riquadro("BATTITO", o.battito.map { "\($0)" } ?? "—", sotto: o.battitoMedia.map { "media 7 gg \($0)" } ?? "a riposo")
                }
                HStack(spacing: 10) {
                    riquadro("PASSI", o.passi.map { $0.formatted() } ?? "—", sotto: "oggi")
                    riquadro("ENERGIA", o.calorie.map { "\($0)" } ?? "—", sotto: "kcal attive")
                }
                if let f = o.fasi { Text("Fasi del sonno: \(f)").font(.footnote).foregroundStyle(Color.tenue) }
                if let p = o.pisolini { Text("Pisolino: \(p)\(o.riposoTotale.map { " · riposo totale \($0)" } ?? "")").font(.footnote).foregroundStyle(Color.ciano) }
                if let n = o.notaSonno { Text(n.prefix(1).uppercased() + n.dropFirst()).font(.footnote).foregroundStyle(Color.tenue) }
                ForEach(o.allenamenti, id: \.self) { a in
                    Label(a, systemImage: "figure.run").font(.footnote).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
                }
                HStack(spacing: 10) {
                    domanda("bed.double", "Come ho dormito?") { chiedi("Come ho dormito stanotte?") }
                    domanda("heart", "Come sta il cuore?") { chiedi("Come sta il mio cuore oggi?") }
                }
            } else {
                Text("Leggo l'app Salute…").font(.footnote).foregroundStyle(Color.tenue)
            }
        }
        .task { oggi = await SaluteOggi.leggi() }
        .tastiAVoce { a in
            if a == .vitalsCome { chiedi("Jarvis, come sto ultimamente? Guarda i miei Vitals degli ultimi \(giorni) giorni.") }
        }
    }

    private func domanda(_ icona: String, _ titolo: String, azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            Label(titolo, systemImage: icona)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.ciano)
                .frame(maxWidth: .infinity).frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.5), lineWidth: 0.8))
        }
        .buttonStyle(StileStark())
    }

    private func graficoPassi(_ d: DatiVitals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PASSI").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            Chart(d.passiGiorni) { g in
                BarMark(x: .value("Giorno", g.data, unit: .day), y: .value("Passi", g.passi ?? 0))
                    .foregroundStyle(Color.ciano.opacity(0.6))
            }
            .frame(height: 100)
        }
        .padding(12)
        .background(Color.ciano.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func riquadri(_ d: DatiVitals) -> some View {
        HStack(spacing: 10) {
            riquadro("UMORE", d.mediaUmore.map { String(format: "%.1f", $0) } ?? "—", sotto: "media su 10")
            riquadro("SONNO", d.mediaSonno.map { String(format: "%.1f", $0) } ?? "—", sotto: "ore di media")
            riquadro("BATTITO", d.mediaBattito.map { "\(Int($0))" } ?? "—", sotto: "media a riposo")
        }
    }

    private func riquadro(_ titolo: String, _ valore: String, sotto: String) -> some View {
        VStack(spacing: 2) {
            Text(titolo).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
            Text(valore).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(sotto).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color.ciano.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func grafico(_ d: DatiVitals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UMORE E SONNO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            if d.giorni.isEmpty {
                Text("Ancora nessun dato nel periodo. Stasera alle 23:30 JARVIS le fa la prima domanda del diario.")
                    .font(.footnote).foregroundStyle(Color.tenue)
            } else {
                Chart {
                    ForEach(d.giorni) { g in
                        if let s = g.sonno {
                            BarMark(x: .value("Giorno", g.data, unit: .day), y: .value("Valore", s))
                                .foregroundStyle(by: .value("Serie", "Sonno (ore)"))
                                .opacity(0.45)
                        }
                    }
                    ForEach(d.giorni.filter { $0.punteggio != nil }) { g in
                        LineMark(x: .value("Giorno", g.data, unit: .day), y: .value("Valore", g.punteggio!))
                            .foregroundStyle(by: .value("Serie", "Umore (1-10)"))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Giorno", g.data, unit: .day), y: .value("Valore", g.punteggio!))
                            .foregroundStyle(by: .value("Serie", "Umore (1-10)"))
                            .symbolSize(28)
                    }
                }
                .chartForegroundStyleScale(["Umore (1-10)": Color.ciano, "Sonno (ore)": Color.orange])
                .chartYScale(domain: 0...10)
                .chartLegend(position: .bottom)
                .frame(height: 200)
            }
        }
        .padding(12)
        .background(Color.ciano.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func graficoBattito(_ d: DatiVitals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BATTITO A RIPOSO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            Chart(d.battiti) { g in
                LineMark(x: .value("Giorno", g.data, unit: .day), y: .value("bpm", g.battito ?? 0))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 110)
        }
        .padding(12)
        .background(Color.ciano.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func lettura(_ d: DatiVitals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LETTURA").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            ForEach(d.frasi, id: \.self) { f in
                Text("▸ \(f)").font(.system(size: 13)).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
            }
        }
    }

    private func diario(_ d: DatiVitals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DIARIO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
                Spacer()
                if !d.pagine.isEmpty {
                    Button("Cancella tutto", role: .destructive) { confermaTutto = true }.font(.footnote)
                }
            }
            ForEach(d.pagine) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(p.giorno)\(p.umore.map { " · \($0)" } ?? "")")
                            .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Color.ciano)
                        Spacer()
                        Button { Task { await cancella(String(p.id)) } } label: { Image(systemName: "trash").font(.footnote) }
                            .tint(Color.tenue)
                            .accessibilityLabel("Cancella questa pagina")
                    }
                    if let q = p.domanda { Text(q).font(.footnote).foregroundStyle(Color.tenue).italic() }
                    Text(p.risposta).font(.system(size: 15)).foregroundStyle(.white).textSelection(.enabled)
                }
                .padding(10)
                .background(Color.ciano.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.25), lineWidth: 0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: Rete

    private func carica() async {
        errore = nil
        async let salute = SaluteStorica.giorni(giorni)
        let o = await VistaVitals.chiama(["vitals": true, "giorni": giorni])
        let s = await salute
        if let e = o?["errore"] as? String { errore = e }
        else if o == nil && s.isEmpty { errore = "Non riesco a leggere i Vitals, Sir. Riprovi tra poco."; return }
        withAnimation(.easeOut(duration: 0.4)) { dati = DatiVitals(o ?? [:], salute: s, giorni: giorni) }
    }

    private func cancella(_ quale: String) async {
        let valore: Any = quale == "tutto" ? "tutto" : (Int(quale) ?? 0)
        _ = await VistaVitals.chiama(["diario_cancella": valore])
        Suoni.tocco()
        await carica()
    }

    static func chiama(_ corpo: [String: Any], attesa: TimeInterval = 20) async -> [String: Any]? {
        guard let url = URL(string: Impostazioni.indirizzo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = attesa
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}

#endif
