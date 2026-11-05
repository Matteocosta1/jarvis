#if os(iOS)
import Foundation
import SwiftUI
import Combine

/// La seconda memoria di JARVIS, sull'iPhone: tutti i ricordi e i posti (qualsiasi luogo salvato),
/// con ricerca, spunta e cancellazione con uno scorrimento. La lista della spesa ha la sua scheda (icona Spesa).
struct VistaRicordi: View {
    enum Scheda: String, CaseIterable, Identifiable { case traccia = "Traccia", ricordi = "Ricordi", posti = "Posti"; var id: String { rawValue } }
    var iniziale: Scheda = .ricordi
    /// TRACCIA con la Guida già accesa (fotocamera e frecce): «Jarvis, portami al luogo».
    var guida = false
    /// TRACCIA salva subito il posto dove si trova: «Jarvis, ricorda questo luogo».
    var salva = false
    /// Per chiedere qualcosa a JARVIS a voce (chiude la pagina e invia la frase).
    let chiedi: (String) -> Void

    @Environment(\.chiudiOVia) private var chiudi
    @State private var scheda: Scheda = .ricordi
    @State private var dati: DatiRicordi?
    @State private var cerca = ""
    @State private var errore = false
    @State private var fotoAperta: Data?
    @State private var guidaAccesa = false
    @State private var salvaDaFare = false        // «ricorda questo luogo»: una volta sola, anche cambiando scheda

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fondo.ignoresSafeArea()
                GrigliaSfumata()
                VStack(spacing: 0) {
                    // 26 ott notte: la testata delle altre schede (icona con l'anello che gira) e le schede con i tasti ciano del Satellite
                    TestataScheda(titolo: scheda.rawValue, sottotitolo: "seconda memoria", icona: "brain.head.profile", tinta: Color.ciano)
                        .padding(.horizontal, 16).padding(.top, 4)
                    HStack(spacing: 6) {
                        ForEach(Scheda.allCases) { k in
                            ChipSat(testo: k.rawValue.uppercased(), acceso: scheda == k) { Suoni.tocco(); scheda = k }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8)

                    if let d = dati, scheda == .traccia {
                        // build 22: TRACCIA, la strada verso un luogo salvato (come nel mockup): i posti e i vecchi parcheggi
                        ScrollView {
                            // solo i luoghi con le coordinate: la freccia punta il più recente che si può raggiungere
                            PannelliTraccia(luoghi: d.posti.filter { ($0.tipo == "posto" || $0.tipo == "parcheggio") && $0.lat != nil && $0.lon != nil },
                                            ultimi: Array(d.ricordi.prefix(3)),
                                            guida: $guidaAccesa, salvaSubito: $salvaDaFare, ricarica: { await carica() })
                                .padding(16)
                                .padding(.bottom, 30)
                        }
                    } else if let d = dati {
                        List {
                            switch scheda {
                            case .posti: posti(d)
                            case .ricordi, .traccia: ricordi(d)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                    } else if errore {
                        Text("Non raggiungo la memoria, Sir.").foregroundStyle(.orange).padding(.top, 40)
                        Spacer()
                    } else {
                        ProgressView().tint(Color.ciano).padding(.top, 60)
                        Spacer()
                    }
                }
                .modifier(ConBarraChiudi(tinta: Color.ciano) { chiudi() })   // 5 nov: niente più barra grigia scorrendo
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { scheda = iniziale; guidaAccesa = guida; salvaDaFare = salva }
            // 4 nov (il signore, strada B): Ricordi già aperto (davanti o dietro) e TRACCIA chiesta a voce («traccia il luogo»,
            // «portami al luogo», «ricorda questo luogo»): la fa qui, sul posto (prima tornava com'era e la guida non partiva)
            .onReceive(NotificationCenter.default.publisher(for: .jarvisRichiestaSezione)) { n in
                guard (n.userInfo?["reparto"] as? String) == Reparto.ricordi.rawValue else { return }
                fotoAperta = nil                                 // una foto aperta sopra non copre TRACCIA
                scheda = .traccia
                if (n.userInfo?["guida"] as? Bool) == true { guidaAccesa = true }
                if (n.userInfo?["salva"] as? Bool) == true { salvaDaFare = true }
            }
            // TRACCIA mostra tutti i luoghi: una ricerca lasciata nella scheda Ricordi non li deve filtrare
            .onChange(of: scheda) { _, nuova in if nuova == .traccia && !cerca.isEmpty { cerca = "" } }
            .task { await carica() }
            .task(id: cerca) {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { await carica() }
            }
            .sheet(isPresented: Binding(get: { fotoAperta != nil }, set: { if !$0 { fotoAperta = nil } })) {
                if let d = fotoAperta, let img = UIImage(data: d) {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        Image(uiImage: img).resizable().scaledToFit()
                    }
                }
            }
            .chiudiFoglioDietro { fotoAperta = nil }            // 4 nov: la foto (iOS) non resta sopra la sezione che sale
        }
        .preferredColorScheme(.dark)
        .aperturaHUD("Ricordi")
    }

    // MARK: Ricordi

    @ViewBuilder private func ricordi(_ d: DatiRicordi) -> some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.tenue)
                TextField("Cerchi: chiavi, Luca, vino…", text: $cerca).foregroundStyle(.white)
                if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
            }
            .listRowBackground(Color.ciano.opacity(0.06))
        }
        Section {
            if d.ricordi.isEmpty {
                Text(cerca.isEmpty ? "Ancora nessun ricordo. Dica a JARVIS «ricordati che le chiavi sono sul mobile»." : "Niente con «\(cerca)».")
                    .font(.footnote).foregroundStyle(Color.tenue).listRowBackground(Color.clear)
            }
            ForEach(d.ricordi) { r in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: VistaRicordi.icona(r.tipo)).foregroundStyle(Color.ciano).frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.testo).font(.system(size: 15)).foregroundStyle(.white)
                        Text([r.persona, r.luogo, r.quando].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                    }
                    Spacer()
                    if r.conFoto {
                        Button { Task { await apriFoto(r.id) } } label: { Image(systemName: "photo").foregroundStyle(Color.ciano) }
                            .buttonStyle(.plain).accessibilityLabel("Vedi la foto")
                    }
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await elimina(r.id) } } label: { Label("Elimina", systemImage: "trash") }
                    Button { Task { await fatto(r.id) } } label: { Label("Ritrovato", systemImage: "checkmark") }.tint(.green)
                }
            }
        } header: { intestazione("brain.head.profile", cerca.isEmpty ? "ULTIMI RICORDI" : "RISULTATI") }
        Section {
            Button { chiedi("Com'è andata oggi?") } label: {
                Label("Com'è andata oggi?", systemImage: "clock.arrow.circlepath").foregroundStyle(Color.ciano)
            }
            Button { chiedi("Ricordati questo posto: dove sono adesso.") } label: {
                Label("Ricorda dove sono", systemImage: "mappin.and.ellipse").foregroundStyle(Color.ciano)
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: Posti (qualsiasi ricordo con una posizione: un luogo salvato, un locale, dove ha visto qualcuno)

    @ViewBuilder private func posti(_ d: DatiRicordi) -> some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.tenue)
                TextField("Cerchi un posto: bar, Luca, studio…", text: $cerca).foregroundStyle(.white)
                if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
            }
            .listRowBackground(Color.ciano.opacity(0.06))
        }
        Section {
            if d.posti.isEmpty {
                Text(cerca.isEmpty ? "Nessun posto salvato. Dica a JARVIS «ricorda questo luogo» o «ricordati questo posto»." : "Niente con «\(cerca)».")
                    .font(.footnote).foregroundStyle(Color.tenue).listRowBackground(Color.clear)
            }
            ForEach(d.posti) { r in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: VistaRicordi.icona(r.tipo)).foregroundStyle(Color.ciano).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.testo).font(.system(size: 15)).foregroundStyle(.white)
                            Text([r.luogo, r.persona, r.quando].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                        }
                    }
                    if let lat = r.lat, let lon = r.lon, let url = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=w") {
                        Link(destination: url) {
                            Label("Portami lì", systemImage: "figure.walk")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.ciano)
                        }
                        .padding(.leading, 32)
                    }
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { Task { await elimina(r.id) } } label: { Label("Elimina", systemImage: "trash") }
                    Button { Task { await fatto(r.id) } } label: { Label("Fatto", systemImage: "checkmark") }.tint(.green)
                }
            }
        } header: { intestazione("mappin.and.ellipse", cerca.isEmpty ? "POSTI" : "RISULTATI") }
        Section {
            Button { chiedi("Ricordati questo posto: dove sono adesso.") } label: {
                Label("Ricorda dove sono", systemImage: "mappin.and.ellipse").foregroundStyle(Color.ciano)
            }
        }
        .listRowBackground(Color.clear)
    }

    private func intestazione(_ icona: String, _ titolo: String) -> some View {
        Label(titolo, systemImage: icona).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.ciano)
    }

    static func icona(_ tipo: String) -> String {
        switch tipo {
        case "oggetto": return "key.fill"
        case "posto", "parcheggio": return "mappin.and.ellipse"     // i vecchi parcheggi sono luoghi come gli altri
        case "persona": return "person.fill"
        case "visto": return "eye.fill"
        case "idea": return "lightbulb.fill"
        default: return "note.text"
        }
    }

    // MARK: Rete

    private func carica() async {
        var corpo: [String: Any] = ["ricordi": true]
        if !cerca.isEmpty { corpo["cerca"] = cerca }
        guard let o = await VistaVitals.chiama(corpo) else { errore = true; return }
        errore = false
        withAnimation(.easeOut(duration: 0.25)) { dati = DatiRicordi(o) }
    }

    private func fatto(_ id: Int) async {
        Suoni.fatto()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        _ = await VistaVitals.chiama(["ricordo_fatto": id])
        await carica()
    }

    private func elimina(_ id: Int) async {
        _ = await VistaVitals.chiama(["ricordo_elimina": id])
        await carica()
    }

    private func apriFoto(_ id: Int) async {
        guard let o = await VistaVitals.chiama(["ricordi": true, "con_foto": true]) else { return }
        let tutti = (o["ricordi"] as? [[String: Any]] ?? [])
        guard let r = tutti.first(where: { ($0["id"] as? NSNumber)?.intValue == id }), let b64 = r["foto"] as? String,
              let d = Data(base64Encoded: b64) else { return }
        fotoAperta = d
    }
}

/// I dati della pagina, letti dal JSON del cervello.
struct DatiRicordi {
    struct Riga: Identifiable {
        let id: Int
        let tipo: String
        let testo: String
        let persona: String?
        let luogo: String?
        let lat: Double?
        let lon: Double?
        let quando: String
        let avviso: String?
        let conFoto: Bool
    }
    let spesa: [Riga]
    let posti: [Riga]
    let ricordi: [Riga]

    init(_ o: [String: Any]) {
        func riga(_ r: [String: Any]) -> Riga? {
            guard let id = (r["id"] as? NSNumber)?.intValue, let t = r["testo"] as? String else { return nil }
            let quando = r["quando_leggibile"] as? String ?? ""
            return Riga(id: id, tipo: r["tipo"] as? String ?? "", testo: t, persona: r["persona"] as? String, luogo: r["luogo"] as? String,
                        lat: (r["lat"] as? NSNumber)?.doubleValue, lon: (r["lon"] as? NSNumber)?.doubleValue,
                        quando: quando, avviso: r["quando"] != nil ? quando : nil, conFoto: (r["con_foto"] as? Bool) ?? false)
        }
        posti = (o["posti"] as? [[String: Any]] ?? []).compactMap(riga)
        spesa = (o["spesa"] as? [[String: Any]] ?? []).compactMap(riga)
        ricordi = (o["ricordi"] as? [[String: Any]] ?? []).compactMap(riga)
    }
}
#endif
