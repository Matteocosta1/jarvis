import SwiftUI
import WatchKit

/// Build 23, SATELLITE al polso (come il mockup): sul polso niente 3D (watchOS non lo permette), i luoghi con la
/// distanza; un tocco su un luogo fa partire la GUIDA sull'iPhone e al polso compare la guida in corso
/// (la freccia, i metri, la tappa e FINE). La guida vive sull'iPhone (percorso, GPS, voce): qui arriva col ponte.

/// I colori del mockup sul polso (gli stessi di SchermatePolso.swift).
private enum ColoriSat {
    static let ciano = TintaOrologio.ciano
    static let testo = Color(red: 0.812, green: 0.886, blue: 0.910)     // #cfe2e8
    static let chiaro = Color(red: 0.902, green: 0.957, blue: 0.973)    // #e6f4f8
    static let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)        // #4d666f
    static let scuro = Color(red: 0.0, green: 0.094, blue: 0.125)       // #001820
}

/// Il tasto largo del polso del mockup (.wb): il nome a sinistra, a destra la distanza (o «›»).
private struct TastoSat: View {
    let testo: String
    let destra: String
    var acceso = false
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack {
                Text(testo).lineLimit(1)
                Spacer(minLength: 4)
                Text(destra)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
            .foregroundStyle(acceso ? ColoriSat.scuro : ColoriSat.chiaro)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(acceso ? ColoriSat.ciano : ColoriSat.ciano.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColoriSat.ciano.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - La guida in corso, dall'iPhone

/// La GUIDA in corso come la manda l'iPhone (Orologio 2.swift › inviaGuida). nil: nessuna guida.
@MainActor
final class GuidaPolso: ObservableObject {
    static let condivisa = GuidaPolso()
    @Published private(set) var dati: GuidaPolsoDati?

    /// Un messaggio dall'iPhone: { guida: {…} } con la guida, { guida: { fine: true } } quando finisce.
    nonisolated static func ricevi(_ m: [String: Any]) {
        guard let d = m["guida"] as? [String: Any] else { return }
        let g = GuidaPolsoDati(d)                        // nil con { fine: true }
        Task { @MainActor in condivisa.dati = g }
    }

    /// Chiede all'iPhone lo stato attuale (all'apertura della schermata). Falso se l'iPhone non ha risposto.
    @discardableResult
    func aggiorna() async -> Bool {
        guard let r = await PonteOrologio.condiviso.guida(["guida": "stato"]) else { return false }
        dati = r.guida
        return true
    }

    /// Fa partire la guida sull'iPhone. nil se è partita, altrimenti il motivo.
    func avvia(_ l: LuogoSat) async -> String? {
        var m: [String: Any] = ["guida": "avvia", "lat": l.lat, "lon": l.lon, "nome": l.nome, "via": l.via, "chiave": l.chiave]
        if let id = l.ricordo { m["ricordo"] = id }
        guard let r = await PonteOrologio.condiviso.guida(m) else { return "iPhone non raggiungibile, Sir: la guida parte da lì." }
        return r.errore
    }

    /// FINE: la guida si ferma anche sull'iPhone.
    func ferma() {
        dati = nil
        Task { _ = await PonteOrologio.condiviso.guida(["guida": "ferma"]) }
    }
}

// MARK: - SATELLITE

/// I luoghi del signore con la distanza (i primi quattro, come nel mockup); un tocco: parte la GUIDA.
struct VistaSatelliteOrologio: View {
    /// Detto a voce («guidami allo studio»): la guida parte da sola verso quel luogo appena i luoghi sono arrivati.
    var azione: AzioneSatellite? = nil
    @StateObject private var bussola = Bussola()
    @State private var luoghi: [LuogoSat] = []
    @State private var caricato = false
    @State private var avviso: String?
    @State private var parte: String?            // la chiave del luogo per cui sta partendo la guida
    @State private var guida = false
    @State private var azioneFatta = false       // «guidami allo studio»: una volta sola (tornando da GUIDA il compito riparte)

    var body: some View {
        SchermoPolso(titolo: "SATELLITE", pronto: caricato) {
            if luoghi.isEmpty {
                Text("Nessun luogo salvato, Sir.").font(.system(size: 11)).foregroundStyle(ColoriSat.testo)
                    .multilineTextAlignment(.center)
            }
            ForEach(luoghi.prefix(4)) { l in
                TastoSat(testo: l.nome, destra: distanza(l), acceso: parte == l.chiave) {
                    WKInterfaceDevice.current().play(.click)
                    SuoniOrologio.tick()
                    Task { await avvia(l) }
                }
            }
            if let avviso {
                Text(avviso).font(.system(size: 10)).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if !luoghi.isEmpty {
                Text("Tocchi un luogo: parte la GUIDA")
                    .font(.system(size: 9)).foregroundStyle(ColoriSat.tenue).multilineTextAlignment(.center)
            }
        }
        .navigationDestination(isPresented: $guida) { VistaGuidaOrologio() }
        .task {
            if let o = await VistaVitalsOrologio.chiama(["ricordi": true]) { luoghi = LuogoSat.daRicordi(o) }
            caricato = true
            if !luoghi.isEmpty, !Task.isCancelled { bussola.accendi() }   // pagina già chiusa mentre arrivavano i luoghi: GPS spento
            // a voce: «guidami allo studio» parte da solo (gli altri comandi di SATELLITE vivono sull'iPhone: qui la lista).
            // Una volta sola: tornando da GUIDA (FINE) il compito della pagina riparte e prima rifaceva partire la guida.
            if !azioneFatta, case .guida(let nome)? = azione {
                azioneFatta = true
                try? await Task.sleep(for: .seconds(1.3))          // come il mockup: prima la schermata, poi la guida
                guard !Task.isCancelled else { return }
                if let l = LuogoSat.trova(nome, in: luoghi) { await avvia(l) }
                else { avviso = "Non trovo «\(nome)» tra i suoi luoghi, Sir." }
            }
        }
        .onDisappear { bussola.spegni() }
    }

    private func distanza(_ l: LuogoSat) -> String {
        bussola.verso(lat: l.lat, lon: l.lon).map { Rotta.distanza($0.metri) } ?? "—"
    }

    private func avvia(_ l: LuogoSat) async {
        guard parte == nil else { return }
        parte = l.chiave
        avviso = nil
        let errore = await GuidaPolso.condivisa.avvia(l)
        parte = nil
        if let errore { avviso = errore; WKInterfaceDevice.current().play(.failure); return }
        guida = true
    }
}

// MARK: - GUIDA

/// La guida in corso al polso: la freccia verso il percorso (la bussola gira col polso), i metri alla prossima
/// svolta (all'arrivo, «ARRIVATO»), la tappa e FINE, che la ferma anche sull'iPhone.
struct VistaGuidaOrologio: View {
    @ObservedObject private var guida = GuidaPolso.condivisa
    @StateObject private var bussola = Bussola()
    @Environment(\.dismiss) private var indietro

    var body: some View {
        SchermoPolso(titolo: "GUIDA") {
            Canvas { gc, size in disegna(gc, size) }
                .frame(maxWidth: .infinity).aspectRatio(4 / 3, contentMode: .fit)
            if let g = guida.dati {
                Text(g.arrivato ? "ARRIVATO" : Rotta.distanza(g.metri))
                    .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(g.arrivato ? g.nome : "\(GuidaPolsoDati.freccia(g.svolta)) \(g.via)")
                    .font(.system(size: 9)).foregroundStyle(ColoriSat.tenue).multilineTextAlignment(.center)
            } else {
                Text("—").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                Text("Nessuna guida").font(.system(size: 9)).foregroundStyle(ColoriSat.tenue)
            }
            TastoSat(testo: "FINE", destra: "›") {
                WKInterfaceDevice.current().play(.click)
                SuoniOrologio.tick()
                guida.ferma()
                indietro()
            }
        }
        .task { await guida.aggiorna() }
        .onAppear { bussola.accendi() }
        .onDisappear { bussola.spegni() }
    }

    /// Come la bussola di TRACCIA al polso: il quadrante gira con il polso, la freccia punta il percorso.
    private func disegna(_ gc: GraphicsContext, _ size: CGSize) {
        let W = Double(size.width), H = Double(size.height)
        let cx = W / 2, cy = H / 2, r = H * 0.42
        let polso = (bussola.direzione ?? 0) * Double.pi / 180
        let rilevamento = guida.dati.flatMap { $0.arrivato ? nil : $0.rilevamento }
        let dir = ((rilevamento ?? 0) - (bussola.direzione ?? 0)) * Double.pi / 180
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
        let ciano = ColoriSat.ciano
        gc.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(ciano.opacity(0.35)), lineWidth: 1)
        var tacche = Path()
        for i in 0..<36 {
            let a: Double = Double(i) / 36 * 2 * Double.pi - polso
            let l: Double = i % 9 == 0 ? 7 : 3
            tacche.move(to: pt(cx + sin(a) * r, cy - cos(a) * r))
            tacche.addLine(to: pt(cx + sin(a) * (r - l), cy - cos(a) * (r - l)))
        }
        gc.stroke(tacche, with: .color(ciano.opacity(0.35)), lineWidth: 1)
        let arancio = Color(red: 1.0, green: 0.706, blue: 0.353)          // #ffb45a
        gc.draw(Text("N").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(arancio),
                at: pt(cx + sin(-polso) * (r - 13), cy - cos(-polso) * (r - 13)), anchor: .center)
        guard rilevamento != nil else { return }                       // senza guida (o arrivato), niente freccia
        var freccia = Path()
        freccia.move(to: pt(0, -r * 0.78))
        freccia.addLine(to: pt(r * 0.28, r * 0.12))
        freccia.addLine(to: pt(0, -r * 0.05))
        freccia.addLine(to: pt(-r * 0.28, r * 0.12))
        freccia.closeSubpath()
        var g = gc
        g.translateBy(x: CGFloat(cx), y: CGFloat(cy))
        g.rotate(by: .radians(dir))
        g.addFilter(.shadow(color: ciano, radius: 6))
        g.fill(freccia, with: .color(ciano))
    }
}
