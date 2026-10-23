import SwiftUI
import WatchKit

/// Le schermate nuove della build 22 sul polso, come nel mockup: PROTOCOLLI, TRACCIA, RADAR, PRIORITÀ.
/// (ORGANISMO è di Vitals; lo Specchio vive sull'iPhone: serve la fotocamera.)
nonisolated enum SchermataPolso: Hashable, Sendable {
    case protocolli(Protocollo?)        // con un protocollo: detto a voce, parte da solo
    case traccia, radar, priorita
}

/// I colori del mockup sul polso.
private enum ColoriPolso {
    static let ciano = TintaOrologio.ciano
    static let testo = Color(red: 0.812, green: 0.886, blue: 0.910)     // #cfe2e8
    static let chiaro = Color(red: 0.902, green: 0.957, blue: 0.973)    // #e6f4f8
    static let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)        // #4d666f
    static let verde = Color(red: 0.373, green: 0.890, blue: 0.631)     // #5fe3a1
    static let riquadro = Color(red: 0.106, green: 0.133, blue: 0.149)  // #1b2226
    static let scuro = Color(red: 0.0, green: 0.094, blue: 0.125)       // #001820
}

/// La cornice delle schermate nuove: caricamento e suoni come le altre schede del polso, poi il titolo in ciano e il contenuto.
struct SchermoPolso<Contenuto: View>: View {
    let titolo: String
    var pronto = true
    @ViewBuilder let contenuto: () -> Contenuto
    @State private var mostrato = false
    @State private var apertaDa = Date()

    var body: some View {
        ZStack {
            if mostrato {
                ScrollView {
                    VStack(spacing: 5) {
                        Text(titolo)
                            .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5)
                            .foregroundStyle(ColoriPolso.ciano)
                        contenuto()
                    }
                    .padding(.horizontal, 4)
                }
                .transition(.opacity)
            } else {
                CaricamentoOrologio(titolo: titolo)
            }
        }
        .onAppear { apertaDa = Date(); WKInterfaceDevice.current().play(.start); SuoniOrologio.schedaApre() }
        .task(id: pronto) {
            guard pronto, !mostrato else { return }
            let resta = 0.9 - Date().timeIntervalSince(apertaDa)
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            WKInterfaceDevice.current().play(.success)
            SuoniOrologio.schedaPronta()
            withAnimation(.easeOut(duration: 0.3)) { mostrato = true }
        }
    }
}

/// Il tasto largo del polso («PARTY ›»); acceso: pieno di ciano.
private struct TastoPolso: View {
    let testo: String
    var segno = "›"
    var acceso = false
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack {
                Text(testo)
                Spacer(minLength: 4)
                Text(segno)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
            .foregroundStyle(acceso ? ColoriPolso.scuro : ColoriPolso.chiaro)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(acceso ? ColoriPolso.ciano : ColoriPolso.ciano.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ColoriPolso.ciano.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Una riga piccola: il nome a sinistra, il valore a destra.
private struct RigaPolso: View {
    let etichetta: String
    let valore: String
    var colore: Color = ColoriPolso.tenue

    var body: some View {
        HStack(spacing: 6) {
            Text(etichetta).foregroundStyle(ColoriPolso.testo)
            Spacer(minLength: 4)
            Text(valore).font(.system(size: 10, design: .monospaced)).foregroundStyle(colore)
        }
        .font(.system(size: 10))
    }
}

/// Il riquadro grigio scuro con l'etichetta in ciano («JARVIS · ORA», «RISPOSTA»).
private struct RiquadroPolso<Contenuto: View>: View {
    @ViewBuilder let contenuto: () -> Contenuto
    var body: some View {
        VStack(alignment: .leading, spacing: 4) { contenuto() }
            .font(.system(size: 11))
            .foregroundStyle(ColoriPolso.chiaro)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ColoriPolso.riquadro)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private func etichettaPolso(_ t: String) -> Text {
    Text(t).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(ColoriPolso.ciano)
}

// MARK: - PROTOCOLLI

/// I tre protocolli e i loro passi. Dal polso i Comandi rapidi dell'iPhone non partono: i passi dell'iPhone restano
/// segnati «iPhone», quelli di JARVIS si spuntano e JARVIS lo dice a voce (JarvisOrologio.protocolloDalPolso).
struct VistaProtocolliOrologio: View {
    var avvia: Protocollo? = nil
    @EnvironmentObject var jarvis: JarvisOrologio
    @State private var scelto: Protocollo?
    @State private var mostrati = 0
    @State private var giro = 0

    var body: some View {
        SchermoPolso(titolo: "PROTOCOLLI") {
            ForEach(Protocollo.allCases) { p in
                TastoPolso(testo: p.titolo, acceso: scelto == p) {
                    WKInterfaceDevice.current().play(.click)
                    parti(p)
                }
            }
            if let p = scelto {
                VStack(spacing: 3) {
                    ForEach(Array(p.passi.prefix(mostrati).enumerated()), id: \.offset) { _, passo in
                        RigaPolso(etichetta: passo.breve, valore: passo.jarvis ? "✓" : "iPhone",
                                  colore: passo.jarvis ? ColoriPolso.verde : ColoriPolso.tenue)
                    }
                }
                .padding(.top, 2)
            }
        }
        .task {
            guard let avvia else { return }               // detto a voce: la schermata si vede, poi parte
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            parti(avvia)
        }
    }

    private func parti(_ p: Protocollo) {
        giro += 1
        let mio = giro
        scelto = p
        mostrati = 0
        Task { @MainActor in
            for k in p.passi.indices {
                try? await Task.sleep(for: .milliseconds(300))
                guard giro == mio else { return }
                mostrati = k + 1
                SuoniOrologio.tick()
            }
            if p.passi.contains(where: { $0.jarvis }) { SuoniOrologio.fatto() }
            try? await Task.sleep(for: .milliseconds(400))      // i suoni finiscono prima della voce
            guard giro == mio else { return }
            jarvis.protocolloDalPolso(p)
        }
    }
}

// MARK: - TRACCIA

/// La bussola con la freccia verso la macchina (l'ultimo «parcheggio»), i metri e l'indirizzo, come nel mockup.
struct VistaTracciaOrologio: View {
    private struct Macchina { let lat: Double; let lon: Double; let luogo: String }
    @StateObject private var bussola = Bussola()
    @State private var macchina: Macchina?
    @State private var caricato = false

    var body: some View {
        SchermoPolso(titolo: "TRACCIA", pronto: caricato) {
            if let m = macchina {
                let rotta = bussola.verso(lat: m.lat, lon: m.lon)
                Canvas { gc, size in disegna(gc, size, rilevamento: rotta?.rilevamento) }
                    .frame(maxWidth: .infinity).aspectRatio(4 / 3, contentMode: .fit)   // sta anche sul 40 mm
                Text(rotta.map { Rotta.distanza($0.metri) } ?? "…")
                    .font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                Text(m.luogo.isEmpty ? "Macchina" : "Macchina · \(m.luogo)")
                    .font(.system(size: 9)).foregroundStyle(ColoriPolso.tenue).multilineTextAlignment(.center)
            } else {
                Text("Nessun parcheggio salvato, Sir.").font(.system(size: 11)).foregroundStyle(ColoriPolso.testo)
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            if let o = await VistaVitalsOrologio.chiama(["ricordi": true]), let pk = o["parcheggio"] as? [String: Any],
               let lat = (pk["lat"] as? NSNumber)?.doubleValue, let lon = (pk["lon"] as? NSNumber)?.doubleValue {
                macchina = Macchina(lat: lat, lon: lon, luogo: (pk["luogo"] as? String) ?? (pk["testo"] as? String) ?? "")
                bussola.accendi()
            }
            caricato = true
        }
        .onDisappear { bussola.spegni() }
    }

    /// Come `bussola` del mockup: il quadrante gira con il polso, la freccia punta la macchina.
    private func disegna(_ gc: GraphicsContext, _ size: CGSize, rilevamento: Double?) {
        let W = Double(size.width), H = Double(size.height)
        let cx = W / 2, cy = H / 2, r = H * 0.42
        let polso = (bussola.direzione ?? 0) * Double.pi / 180
        let dir = ((rilevamento ?? 0) - (bussola.direzione ?? 0)) * Double.pi / 180
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x), y: CGFloat(y)) }
        let ciano = ColoriPolso.ciano
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
        guard rilevamento != nil else { return }                       // senza posizione, niente freccia
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

// MARK: - RADAR

/// La pioggia in arrivo dove si trova il signore (dal cervello, azione «radar»). La notifica arriva da sola dall'iPhone.
struct VistaRadarOrologio: View {
    @State private var radar: DatiRadar?
    @State private var caricato = false

    var body: some View {
        SchermoPolso(titolo: "RADAR", pronto: caricato) {
            if let r = radar {
                if r.piove {
                    RiquadroPolso {
                        etichettaPolso("JARVIS · ORA")
                        Text(r.avvisoBreve)
                    }
                    VStack(spacing: 3) {
                        RigaPolso(etichetta: "Quanta", valore: "\(r.millimetri) mm")
                        RigaPolso(etichetta: "Smette", valore: r.smette.isEmpty ? "—" : r.smette)
                    }
                } else {
                    Text("Nessuna pioggia in arrivo").font(.system(size: 11)).foregroundStyle(ColoriPolso.testo)
                }
            } else {
                Text("Il radar non risponde, Sir.").font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .task {
            var corpo: [String: Any] = ["radar": true]
            if let p = await PosizioneOrologio.attuale(), let lat = p["lat"] as? Double, let lon = p["lon"] as? Double {
                corpo["lat"] = lat
                corpo["lon"] = lon
            }
            radar = (await VistaVitalsOrologio.chiama(corpo)).flatMap { DatiRadar($0) }
            caricato = true
            if radar?.piove == true { SuoniOrologio.fatto() }         // come nel mockup: l'avviso arriva col suo suono
        }
    }
}

// MARK: - PRIORITÀ

/// La prima mail che conta, la risposta proposta da JARVIS e INVIA (spedisce solo dopo il tocco).
struct VistaPrioritaOrologio: View {
    private enum Invio: Equatable { case pronta, invio, inviata, errore }
    @State private var posta: PostaPriorita?
    @State private var errore: String?
    @State private var caricato = false
    @State private var stato: Invio = .pronta

    var body: some View {
        SchermoPolso(titolo: posta.map { "PRIORITÀ · \($0.importanti.count)" } ?? "PRIORITÀ", pronto: caricato) {
            if let m = posta?.importanti.first {
                RigaPolso(etichetta: m.mittente, valore: m.quando)
                RiquadroPolso {
                    Text(m.riassunto)
                    if let r = m.risposta {
                        etichettaPolso(m.serveRisposta ? "RISPOSTA" : "NOTA")
                        Text(m.serveRisposta ? "«\(PostaPriorita.senzaVirgolette(r))»" : r)
                    }
                }
                if m.serveRisposta, let r = m.risposta {
                    TastoPolso(testo: stato == .inviata ? "INVIATA" : (stato == .invio ? "…" : "INVIA"),
                               segno: stato == .inviata ? "✓" : "›", acceso: stato == .inviata) {
                        Task { await invia(m, PostaPriorita.senzaVirgolette(r)) }
                    }
                    .disabled(stato == .invio || stato == .inviata)
                    if stato == .errore {
                        Text("Non sono riuscito a inviarla, Sir.").font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            } else if posta != nil {
                Text("Niente di importante, Sir.").font(.system(size: 11)).foregroundStyle(ColoriPolso.testo)
            } else {
                Text(errore ?? "Non raggiungo la posta, Sir.").font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .task {
            if let o = await VistaVitalsOrologio.chiama(["posta_priorita": true], attesa: 45) {
                if let e = o["errore"] as? String { errore = e } else { posta = PostaPriorita(o) }
            }
            caricato = true
        }
    }

    private func invia(_ m: MailImportante, _ testo: String) async {
        guard stato == .pronta || stato == .errore, !testo.isEmpty else { return }
        stato = .invio
        WKInterfaceDevice.current().play(.click)
        let o = await VistaVitalsOrologio.chiama(m.corpoRisposta(testo), attesa: 45)
        if (o?["ok"] as? Bool) == true {
            stato = .inviata
            SuoniOrologio.fatto()
            WKInterfaceDevice.current().play(.success)
        } else {
            stato = .errore
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
