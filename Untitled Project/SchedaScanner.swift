#if os(iOS)
import SwiftUI
import Vision
import VisionKit

// MARK: - SCANNER: il codice a barre di un prodotto, e JARVIS dice se è buono (stile Yuka, dati Open Food Facts)
// La fotocamera legge il codice, il cervello prende i dati aperti di Open Food Facts e calcola il voto.

struct VistaScanner: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano

    /// Un prodotto già scansionato, per la cronologia (salvata sul telefono).
    nonisolated struct Passato: Codable, Identifiable, Sendable {
        var id: String { codice }
        let codice: String
        let nome: String
        let marca: String
        let voto: Int
        let immagine: String
    }

    @State private var leggo = true              // la fotocamera cerca un codice
    @State private var carico = false
    @State private var prodotto: Voce?
    @State private var errore: String?
    @State private var codiceAMano = ""
    @State private var storico: [Passato] = []
    @State private var mostraIngredienti = false

    var body: some View {
        CorniceScheda(titolo: "Scanner", sottotitolo: sottotitolo, icona: "barcode.viewfinder", tinta: tinta, fotocamera: true) {
            if leggo { lettore } else { Button { ricomincia() } label: { scansionaAncora }.buttonStyle(StileStark()) }
            if carico {
                HStack(spacing: 10) {
                    ProgressView().tint(tinta)
                    Text("Leggo l'etichetta…").font(.system(size: 13, design: .monospaced)).foregroundStyle(tinta)
                }
                .frame(maxWidth: .infinity)
            }
            if let errore {
                Pannello(tinta: .orange) { Text(errore).font(.footnote).foregroundStyle(.orange) }
            }
            if let p = prodotto { scheda(p) }
            if !storico.isEmpty {
                Pannello(titolo: "SCANSIONATI · \(storico.count)", tinta: tinta) {
                    ForEach(storico) { s in rigaStorico(s) }
                }
            }
        }
        .onAppear { storico = VistaScanner.leggi() }
    }

    private var sottotitolo: String {
        if carico { return "leggo l'etichetta" }
        if let p = prodotto { return p.s("giudizio") }
        return leggo ? "inquadri il codice a barre" : "pronto"
    }

    // MARK: lettore

    @ViewBuilder private var lettore: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ZStack {
                LettoreCodici(attivo: leggo && !carico) { codice in trovato(codice) }
                RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .frame(width: 230, height: 120)
                    .shadow(color: tinta.opacity(0.6), radius: 8)
                VStack {
                    Spacer()
                    Text("INQUADRI IL CODICE A BARRE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.55)).clipShape(Capsule()).padding(.bottom, 10)
                }
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tinta.opacity(0.3), lineWidth: 1))
        } else {
            Pannello(tinta: .orange) {
                Text("La fotocamera non può leggere i codici in questo momento (permesso negato o dispositivo non compatibile). Può scrivere il numero qui sotto.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
        HStack(spacing: 8) {
            TextField("oppure scriva il numero del codice", text: $codiceAMano)
                .keyboardType(.numberPad)
                .font(.system(size: 14, design: .monospaced))
                .padding(.horizontal, 12).frame(height: 42)
                .background(tinta.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.25), lineWidth: 1))
            Button { trovato(codiceAMano) } label: {
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.fondo)
                    .frame(width: 42, height: 42).background(tinta).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(StileStark())
            .disabled(codiceAMano.filter(\.isNumber).count < 6)
        }
    }

    private var scansionaAncora: some View {
        Label("Scansiona un altro prodotto", systemImage: "barcode.viewfinder")
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity).frame(height: 46)
            .foregroundStyle(tinta)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.6), lineWidth: 1))
    }

    // MARK: scheda del prodotto

    private func coloreVoto(_ v: Int) -> Color {
        v >= 75 ? Color(red: 0.2, green: 0.85, blue: 0.45) : v >= 50 ? Color(red: 0.6, green: 0.85, blue: 0.3) : v >= 25 ? .orange : .red
    }

    private func coloreLivello(_ l: String) -> Color {
        switch l { case "basso": return Color(red: 0.2, green: 0.85, blue: 0.45); case "moderato": return .orange; case "alto": return .red; default: return Color.tenue }
    }

    @ViewBuilder private func scheda(_ p: Voce) -> some View {
        let voto = p.n("voto"), colore = coloreVoto(voto)
        Pannello(tinta: colore) {
            HStack(alignment: .center, spacing: 14) {
                AsyncImage(url: URL(string: p.s("immagine"))) { img in img.resizable().scaledToFit() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.s("nome")).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    Text([p.s("marca"), p.s("quantita")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(1)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(colore.opacity(0.2), lineWidth: 6)
                    Circle().trim(from: 0, to: CGFloat(voto) / 100).stroke(colore, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(voto)").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(colore)
                        Text("/100").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                    }
                }
                .frame(width: 70, height: 70)
                .shadow(color: colore.opacity(0.5), radius: 8)
            }
            HStack(spacing: 8) {
                Text(p.s("giudizio").uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.fondo).padding(.horizontal, 10).padding(.vertical, 5).background(colore).clipShape(Capsule())
                if !p.s("nutriscore").isEmpty { etichetta("NUTRI-SCORE \(p.s("nutriscore"))") }
                if p.n("nova") > 0 { etichetta("NOVA \(p.n("nova"))") }
                if p.b("biologico") { etichetta("BIO") }
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))

        let nutrienti = p.lista("nutrienti")
        if !nutrienti.isEmpty {
            Pannello(titolo: "VALORI · PER 100 G", tinta: tinta) {
                ForEach(Array(nutrienti.enumerated()), id: \.offset) { _, x in
                    HStack {
                        Circle().fill(coloreLivello(x.s("livello"))).frame(width: 7, height: 7)
                        Text(x.s("nome")).font(.system(size: 13)).foregroundStyle(.white)
                        Spacer()
                        if !x.s("livello").isEmpty { Text(x.s("livello")).font(.system(size: 10, design: .monospaced)).foregroundStyle(coloreLivello(x.s("livello"))) }
                        Text("\(x.s("valore")) \(x.s("unita"))").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }
        }

        let additivi = p.lista("additivi")
        Pannello(titolo: "ADDITIVI · \(additivi.count)", tinta: additivi.contains { $0.s("rischio") == "alto" } ? .red : tinta) {
            if additivi.isEmpty {
                Label("Nessun additivo, Sir.", systemImage: "checkmark.seal").font(.system(size: 13)).foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.45))
            }
            ForEach(Array(additivi.enumerated()), id: \.offset) { _, a in
                HStack {
                    Circle().fill(coloreLivello(a.s("rischio"))).frame(width: 7, height: 7)
                    Text(a.s("codice")).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                    if !a.s("nome").isEmpty { Text(a.s("nome")).font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(1) }
                    Spacer()
                    Text("rischio \(a.s("rischio"))").font(.system(size: 10, design: .monospaced)).foregroundStyle(coloreLivello(a.s("rischio")))
                }
            }
        }

        if !p.s("ingredienti").isEmpty || !p.stringhe("allergeni").isEmpty {
            Pannello(titolo: "INGREDIENTI", tinta: tinta) {
                if !p.stringhe("allergeni").isEmpty {
                    Text("Allergeni: " + p.stringhe("allergeni").joined(separator: ", ")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                }
                if !p.s("ingredienti").isEmpty {
                    Text(p.s("ingredienti")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(mostraIngredienti ? nil : 4)
                    Button { withAnimation { mostraIngredienti.toggle() } } label: {
                        Text(mostraIngredienti ? "Meno" : "Tutti gli ingredienti").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                    }
                }
            }
        }

        TastoJarvis(testo: "Chieda a JARVIS", tinta: tinta) {
            chiedi("Ho scansionato «\(p.s("nome"))» (codice \(p.s("codice"))): è una buona scelta? Dimmi cosa pesa nel voto e che alternativa cercare.")
        }
        Text("Voto calcolato da JARVIS su Nutri-Score, additivi e biologico · dati Open Food Facts · non è un consiglio medico.")
            .font(.system(size: 9)).foregroundStyle(Color.tenue)
    }

    private func etichetta(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(tinta).padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().stroke(tinta.opacity(0.5), lineWidth: 1))
    }

    private func rigaStorico(_ s: Passato) -> some View {
        Button { trovato(s.codice) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: s.immagine)) { img in img.resizable().scaledToFit() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.nome).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(s.marca).font(.system(size: 11)).foregroundStyle(Color.tenue).lineLimit(1)
                }
                Spacer()
                Text("\(s.voto)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(coloreVoto(s.voto))
            }
        }
        .buttonStyle(StileStark())
    }

    // MARK: azioni

    private func ricomincia() {
        Suoni.tocco()
        withAnimation { prodotto = nil; errore = nil; leggo = true }
    }

    private func trovato(_ grezzo: String) {
        let codice = grezzo.filter(\.isNumber)
        guard codice.count >= 6, !carico else { return }
        Suoni.tocco()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation { leggo = false; carico = true; errore = nil; prodotto = nil }
        codiceAMano = ""
        Task {
            let o = await VistaVitals.chiama(["prodotto": codice])
            carico = false
            guard let o else { errore = "Non raggiungo il cervello, Sir."; return }
            let v = Voce(o)
            if !v.b("trovato") {
                withAnimation { errore = v.s("errore").isEmpty ? "Prodotto non trovato, Sir." : "\(v.s("errore").prefix(1).uppercased())\(v.s("errore").dropFirst()), Sir (codice \(codice))." }
                return
            }
            Suoni.pronto()                                   // prodotto trovato: la conferma, come le altre
            withAnimation(.spring(duration: 0.4)) { prodotto = v }
            let nuovo = Passato(codice: v.s("codice"), nome: v.s("nome"), marca: v.s("marca"), voto: v.n("voto"), immagine: v.s("immagine"))
            storico = [nuovo] + storico.filter { $0.codice != nuovo.codice }.prefix(29)
            VistaScanner.salva(storico)
        }
    }

    private static let chiave = "scannerStorico"
    static func leggi() -> [Passato] {
        guard let d = UserDefaults.standard.data(forKey: chiave) else { return [] }
        return (try? JSONDecoder().decode([Passato].self, from: d)) ?? []
    }
    static func salva(_ s: [Passato]) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: chiave) }
    }
}

/// La fotocamera che legge i codici a barre (VisionKit): al primo codice riconosciuto chiama `trovato`.
struct LettoreCodici: UIViewControllerRepresentable {
    let attivo: Bool
    let trovato: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.trovato = trovato
        if attivo {
            // la fotocamera parte solo quando la vista è davvero sullo schermo
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !vc.isScanning { try? vc.startScanning() }
            }
        } else if vc.isScanning {
            vc.stopScanning()
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(trovato: trovato) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var trovato: (String) -> Void
        init(trovato: @escaping (String) -> Void) { self.trovato = trovato }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let valore = b.payloadStringValue {
                    dataScanner.stopScanning()
                    trovato(valore)
                    return
                }
            }
        }
    }
}
#endif
