import SwiftUI
import WatchKit

/// Build 23, MUSICA sul polso: quello che suona sull'iPhone (titolo, artista, la barra del tempo) e i tre tasti
/// precedente · play/pausa · successivo, che comandano il lettore dell'iPhone (PonteOrologio › PonteTelefono › LettoreMusica).
/// Il mockup non ha il disegno del polso per MUSICA: è la versione minima nello stile delle schede dell'orologio (da approvare).
/// Si apre a voce: «Jarvis, apri la musica».
struct VistaMusicaOrologio: View {
    @State private var stato: PonteOrologio.StatoMusica?
    @State private var lettoAlle = Date()              // quando è arrivato lo stato: il tempo scorre da lì fino alla lettura dopo
    @State private var caricato = false
    @State private var muto = false                    // l'iPhone non ha risposto
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Musica", pronto: caricato) {
            VStack(spacing: 6) {
                if let s = stato {
                    if let e = s.errore {
                        Text(e).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                    Text(s.titolo).font(.system(size: 14, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
                    Text(s.artista).font(.footnote).foregroundStyle(ciano).lineLimit(1)
                    tempo(s)
                    HStack(spacing: 10) {
                        tasto("indietro", .precedente, "Brano precedente")
                        Button { comanda(s.suona ? "pausa" : "play") } label: {
                            IconaTastoPolso(tipo: s.suona ? .pausa : .play)
                                .frame(width: 18, height: 18)
                                .foregroundStyle(.black)
                                .frame(width: 44, height: 44)
                                .background(ciano, in: Circle())
                                .shadow(color: ciano.opacity(0.6), radius: 6)
                        }
                        .buttonStyle(StileStarkOrologio())
                        .accessibilityLabel(s.suona ? "Pausa" : "Riproduci")
                        tasto("avanti", .successivo, "Brano successivo")
                    }
                    .padding(.top, 2)
                } else if muto {
                    Text("L'iPhone non risponde, Sir: lo tenga vicino.").font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            // come sull'iPhone: lo stato si rilegge ogni due secondi finché la schermata è aperta
            while !Task.isCancelled {
                await leggi("stato")
                caricato = true
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// La barra del tempo con i minuti ai lati; tra una lettura e l'altra il tempo avanza da solo se suona.
    private func tempo(_ s: PonteOrologio.StatoMusica) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let d = s.durata ?? 0
            let t = s.suona ? min(d > 0 ? d : .infinity, s.tempo + ctx.date.timeIntervalSince(lettoAlle)) : s.tempo
            let f = d > 0 ? min(1, max(0, t / d)) : 0
            VStack(spacing: 3) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ciano.opacity(0.15))
                        Capsule().fill(ciano).frame(width: g.size.width * f)
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(Self.mmss(t))
                    Spacer()
                    Text(Self.mmss(d))
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private func tasto(_ comando: String, _ tipo: IconaTastoPolso.Tipo, _ nome: String) -> some View {
        Button { comanda(comando) } label: {
            IconaTastoPolso(tipo: tipo)
                .frame(width: 16, height: 16)
                .foregroundStyle(ciano)
                .frame(width: 34, height: 34)
                .background(ciano.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(ciano.opacity(0.5), lineWidth: 0.8))
        }
        .buttonStyle(StileStarkOrologio())
        .accessibilityLabel(nome)
    }

    private func comanda(_ comando: String) {
        WKInterfaceDevice.current().play(.click)
        SuoniOrologio.tick()
        Task { await leggi(comando) }
    }

    private func leggi(_ comando: String) async {
        if let s = await PonteOrologio.condiviso.musica(comando) {
            stato = s
            lettoAlle = Date()
            muto = false
        } else {
            muto = stato == nil
        }
    }

    static func mmss(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let t = max(0, Int(s))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }
}

/// I tasti del polso con gli stessi disegni dell'iPhone (gli SVG del mockup, viewBox 24, tratto 1,6).
struct IconaTastoPolso: View {
    enum Tipo { case precedente, play, pausa, successivo }
    let tipo: Tipo

    var body: some View {
        Canvas { gc, size in
            let k = min(size.width, size.height) / 24
            let dx = (size.width - 24 * k) / 2, dy = (size.height - 24 * k) / 2
            func linea(_ punti: [(CGFloat, CGFloat)], chiusa: Bool = false) -> Path {
                var q = Path()
                q.move(to: CGPoint(x: dx + punti[0].0 * k, y: dy + punti[0].1 * k))
                for t in punti.dropFirst() { q.addLine(to: CGPoint(x: dx + t.0 * k, y: dy + t.1 * k)) }
                if chiusa { q.closeSubpath() }
                return q
            }
            let stile = StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round)
            switch tipo {
            case .precedente:
                gc.stroke(linea([(6, 5), (6, 19)]), with: .foreground, style: stile)
                gc.stroke(linea([(19, 5), (9, 12), (19, 19)], chiusa: true), with: .foreground, style: stile)
            case .successivo:
                gc.stroke(linea([(18, 5), (18, 19)]), with: .foreground, style: stile)
                gc.stroke(linea([(5, 5), (15, 12), (5, 19)], chiusa: true), with: .foreground, style: stile)
            case .play:
                let t = linea([(8, 5), (8, 19), (19, 12)], chiusa: true)
                gc.fill(t, with: .foreground)
                gc.stroke(t, with: .foreground, style: stile)
            case .pausa:
                for x: CGFloat in [8, 13] {
                    let r = linea([(x, 5), (x + 3, 5), (x + 3, 19), (x, 19)], chiusa: true)
                    gc.fill(r, with: .foreground)
                    gc.stroke(r, with: .foreground, style: stile)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
