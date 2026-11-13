#if os(iOS)
import SwiftUI
import UIKit

// MARK: - 13.0 · FILO, UNA SCHEDA SOLA
// Il signore (13 nov, 22:33): «come FILO ma tutto raggruppato in un'unica tab, anziché aprirne varie per ogni argomento»; sotto le
// icone di sistema in alto a destra, olografico, interattivo e navigabile. «Mostrami…» sparisce in 2,8 s come una notifica,
// «fissalo» lo tiene, toccato resta finché lui non ha finito di scorrere. Ogni argomento ha la sua testata col nome e, in fondo a
// destra sulla stessa linea, la X che chiude solo quello. Le cose sparite tornano con lo swipe dal bordo destro dello schermo
// verso sinistra; lo swipe verso destra su FILO le rimanda via. Scelta SCORRI (23:02): gli argomenti uno sotto l'altro, giù e su.
// Misure, colori e tempi come il mockup (v1216/q16-9.js, q16-9.css).

/// Lo strato di FILO sopra la schermata e le sezioni (ContentView), con la striscia del bordo destro che lo richiama.
struct StratoFilo: View {
    @ObservedObject private var filo = Filo.condiviso
    /// 13.1: il menu SISTEMI o la tendina PROTOCOLLI sono aperti (stanno nello stesso angolo): FILO si fa da parte finché si chiudono.
    var daParte = false

    var body: some View {
        let visti = filo.visti
        let alto = filo.sottoIcone > 0 ? filo.sottoIcone + 6 : (FasciaAlta.finestra?.safeAreaInsets.top ?? 59) + 58
        ZStack(alignment: .topTrailing) {
            Color.clear
            if !visti.isEmpty {
                SchedaFilo(argomenti: visti)
                    .padding(.top, alto)
                    .padding(.trailing, 10)
                    .transition(.asymmetric(insertion: .identity, removal: .offset(x: 240).combined(with: .opacity)))   // la nascita la fa la scheda
            }
            // il bordo destro: con FILO via e qualcosa da richiamare, uno swipe verso sinistra lo riporta
            if visti.isEmpty && !filo.argomenti.isEmpty {
                Color.clear
                    .frame(width: 16, height: 280)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 10).onEnded { v in
                        guard v.translation.width < -36, abs(v.translation.height) < 60 else { return }
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { _ = filo.richiama() }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    })
                    .padding(.top, alto)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .opacity(daParte ? 0 : 1)
        .allowsHitTesting(!daParte)
        .animation(.easeOut(duration: 0.2), value: daParte)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3), value: visti.isEmpty)
    }
}

/// La nascita di FILO: si apre in largo su una riga sottile, poi in alto (scale .2,.04 → 1,.04 → 1,1), l'angolo in alto a destra fermo.
private struct NascitaFilo: ViewModifier, Animatable {
    var fase: Double
    nonisolated var animatableData: Double {
        get { fase }
        set { fase = newValue }
    }
    func body(content: Content) -> some View {
        let p = fase
        let sx = p < 0.45 ? 0.2 + 0.8 * p / 0.45 : 1
        let sy = p < 0.45 ? 0.04 : 0.04 + 0.96 * (p - 0.45) / 0.55
        return content
            .scaleEffect(x: sx, y: sy, anchor: .topTrailing)
            .opacity(p < 0.45 ? p / 0.45 : 1)
    }
}

/// La scheda: la cornice olografica, la testata FILO, gli argomenti uno sotto l'altro che scorrono.
private struct SchedaFilo: View {
    let argomenti: [ArgomentoFilo]
    @State private var nata = Date()
    @State private var contenuto: CGFloat = 0
    @State private var sopra = false        // c'è altro sopra (scorso giù)
    @State private var sotto = false        // c'è altro sotto
    @State private var dx: CGFloat = 0
    @State private var fase: Double = 0     // la nascita (0 → 1)
    @GestureState private var trascina = false   // il dito trascina sulla scheda (torna falso da solo anche se il gesto si interrompe)

    static let larghezza: CGFloat = 212
    static let altezzaMassima: CGFloat = 200

    var body: some View {
        let altezza = min(Self.altezzaMassima, max(30, contenuto))
        VStack(alignment: .leading, spacing: 0) {
            // la testata: FILO e quanti argomenti
            HStack(spacing: 7) {
                Text("FILO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.6)
                    .foregroundStyle(Olo.ciano.opacity(0.95))
                    .shadow(color: Olo.azzurro.opacity(0.9), radius: 3)
                if argomenti.count > 1 {
                    Text("\(argomenti.count) ARGOMENTI")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(Olo.ciano.opacity(0.62))
                        .contentTransition(.numericText())
                }
            }
            .frame(height: 20)
            .padding(.leading, 10)
            .padding(.top, 2)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(argomenti.enumerated()), id: \.element.id) { i, a in
                        ArgomentoVista(a: a, primo: i == 0)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                    removal: .opacity.combined(with: .offset(x: 24))))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    contenuto = h
                    if #unavailable(iOS 18.0) { sotto = h > Self.altezzaMassima + 4 }   // iOS 17: c'è altro sotto
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: altezza)
            .mask { Sfuma(sopra: sopra, sotto: sotto) }
            .modifier(ScorreFilo(sopra: $sopra, sotto: $sotto))           // iOS 18: la sfumatura e «scorre: le notifiche aspettano»
            .padding(.top, 6)
            .padding(.leading, 12)
            .padding(.trailing, 10)                                        // come il mockup (12 a sinistra, 10 a destra)
            .padding(.bottom, 8)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25), value: argomenti.map(\.id))
        }
        .frame(width: Self.larghezza, alignment: .leading)
        .background {
            // meno trasparente: il fondo scuro dentro la cornice, poi la cornice olografica (luce, filo, angoli, scansione)
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(nata)
                Canvas(rendersAsynchronously: false) { gc, size in
                    CorniceFilo.disegna(&gc, size, t: t)
                }
            }
            .allowsHitTesting(false)
        }
        .offset(x: dx)
        .opacity(1 - min(0.8, Double(dx) / 200))
        // via con lo swipe a destra: solo un gesto chiaramente orizzontale (su e giù è per scorrere)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .updating($trascina) { _, stato, _ in stato = true }
                .onChanged { v in
                    if v.translation.width > 0, v.translation.width > abs(v.translation.height) * 2.5 { dx = v.translation.width }
                }
                .onEnded { v in
                    if v.translation.width > 80, v.translation.width > abs(v.translation.height) * 2.5 {
                        Suoni.filoVia()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.timingCurve(0.4, 0, 0.8, 0.4, duration: 0.24)) { Filo.condiviso.rimandaVia() }
                        dx = 0
                        return
                    }
                    withAnimation(.easeOut(duration: 0.2)) { dx = 0 }
                }
        )
        .onChange(of: trascina) { _, v in
            Filo.condiviso.toccato(v)                                      // finito (o interrotto): altri 2,8 secondi
            if !v, dx != 0 { withAnimation(.easeOut(duration: 0.2)) { dx = 0 } }
        }
        .modifier(NascitaFilo(fase: fase))
        .onAppear { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) { fase = 1 } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("FILO")
        .accessibilityAction(named: "Nascondi") { Filo.condiviso.rimandaVia() }
    }
}

/// Un argomento: la testata (il nome, la linea che corre, la X in fondo a destra) e le sue righe.
private struct ArgomentoVista: View {
    let a: ArgomentoFilo
    let primo: Bool
    @State private var accesa = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !primo {
                // tra un argomento e l'altro una linea di luce
                LinearGradient(colors: [Olo.azzurro.opacity(0), Olo.azzurro.opacity(0.45), Olo.azzurro.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.bottom, 8)
                    .padding(.top, 10)
            }
            HStack(spacing: 6) {
                Text(a.nome.uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.8)
                    .foregroundStyle(Olo.bianco)
                    .shadow(color: Olo.azzurro.opacity(0.95), radius: 3.5)
                    .lineLimit(1)
                    .fixedSize()
                if a.fisso {
                    Text("◆")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Olo.bianco.opacity(0.95))
                        .shadow(color: Olo.azzurro.opacity(0.9), radius: 3)
                        .accessibilityLabel("fissato")
                }
                LinearGradient(colors: [Olo.ciano.opacity(0.7), Olo.ciano.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Button {
                    Suoni.filoVia()
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)) { _ = Filo.condiviso.togliArgomento(a.nome) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(Olo.bianco)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Olo.azzurro.opacity(0.08)))
                        .overlay(Circle().stroke(Olo.ciano.opacity(0.55), lineWidth: 1))
                        .shadow(color: Olo.azzurro.opacity(0.35), radius: 3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -6)
                .accessibilityLabel("Chiudi \(a.nome)")
            }
            .frame(minHeight: 24)
            ForEach(righe) { r in
                Button {
                    if let s = r.sezione { Suoni.tocco(); Regia.condivisa.porta(s) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(r.testo)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(red: 236 / 255, green: 252 / 255, blue: 1).opacity(0.98))
                            .shadow(color: Olo.azzurro.opacity(0.85), radius: 4)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let ora = r.ora {
                            Text(ora)
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Olo.ciano.opacity(0.6))
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(r.sezione == nil ? "" : "Apre \(r.sezione ?? "")")
            }
        }
        // appena arrivato (o aggiornato) si accende un attimo; richiamato col dito dal bordo no (come il mockup)
        .brightness(accesa ? 0.35 : 0)
        .onAppear { if Date().timeIntervalSince(a.aggiornato) < 0.6 { accendi() } }
        .onChange(of: a.giro) { accendi() }
    }

    private func accendi() {
        accesa = true
        withAnimation(.easeOut(duration: 0.5)) { accesa = false }
    }

    /// L'agenda un impegno per riga («11:30 dentista», «18:00 palestra»), senza l'ora di quando è stata mostrata; le altre una riga
    /// per dato, con l'ora.
    private var righe: [RigaVista] {
        var v: [RigaVista] = []
        for r in a.righe {
            if a.nome == "Agenda" {
                let pezzi = r.riga.components(separatedBy: " · ")
                let titolo = Filo.testo(di: RigaFilo(id: r.id, titolo: r.titolo, riga: "", sezione: nil, alle: r.alle), in: a.nome)
                for (k, pezzo) in pezzi.enumerated() {
                    v.append(RigaVista(id: r.id + "#\(k)", testo: (k == 0 && !titolo.isEmpty ? titolo : "") + pezzo, sezione: r.sezione, ora: nil))
                }
            } else {
                v.append(RigaVista(id: r.id, testo: Filo.testo(di: r, in: a.nome), sezione: r.sezione, ora: ArgomentoVista.formato.string(from: r.alle)))
            }
        }
        return v
    }

    private static let formato: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// Dove è lo scorrimento (sfumatura sopra e sotto) e se il dito sta scorrendo (le notifiche aspettano). Su iOS 17 (l'app parte da
/// iOS 17.6) queste due letture non ci sono: la sfumatura resta solo in basso quando c'è altro, e mentre si scorre conta il
/// trascinamento della scheda.
private struct ScorreFilo: ViewModifier {
    @Binding var sopra: Bool
    @Binding var sotto: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: [Bool].self) { g in
                    [g.contentOffset.y > 4, g.contentOffset.y + g.containerSize.height < g.contentSize.height - 4]
                } action: { _, v in
                    sopra = v[0]
                    sotto = v[1]
                }
                .onScrollPhaseChange { _, fase in Filo.condiviso.toccato(fase != .idle) }
        } else {
            content
        }
    }
}

/// Una riga come si vede (l'agenda divisa per impegno).
private struct RigaVista: Identifiable {
    let id: String
    let testo: String
    let sezione: String?
    let ora: String?
}

/// La sfumatura in alto e in basso quando c'è altro da scorrere.
private struct Sfuma: View {
    let sopra: Bool
    let sotto: Bool
    var body: some View {
        LinearGradient(stops: [.init(color: sopra ? .clear : .black, location: 0),
                               .init(color: .black, location: sopra ? 0.18 : 0),
                               .init(color: .black, location: sotto ? 0.78 : 1),
                               .init(color: sotto ? .clear : .black, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// La cornice olografica di FILO (corniceFilo del mockup): il punto di luce in alto a destra che pulsa, il filo che scende e
/// corre sotto la testata, il fondo scuro, gli angoli, la riga di scansione che scende lenta.
private enum CorniceFilo {
    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double) {
        let W = Double(size.width), H = Double(size.height)
        let u0 = min(1, t / 0.5)
        gc.opacity = u0 < 1 ? (sin(u0 * 40) > -0.2 ? u0 : u0 * 0.3) : 1          // si accende sfarfallando
        let ax = W - 6, ay = 6.0, u = Olo.liscia(t / 0.45), ly = 24.0, bx = 4.0, by = ly, bw = W - 8, bh = H - by - 3
        // il fondo (meno trasparente: la corona dietro si intuisce appena)
        gc.fill(Path(CGRect(x: bx, y: by, width: bw * u, height: bh)), with: .color(Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.93)))
        gc.blendMode = .plusLighter
        let pul = (t * 0.9).truncatingRemainder(dividingBy: 1)
        gc.stroke(Olo.ellisse(ax, ay, 2 + pul * 8, 2 + pul * 8), with: .color(Olo.ciano.opacity(0.7 * (1 - pul))), lineWidth: 1)
        Olo.alone(&gc, CGPoint(x: ax, y: ay), 10, 0.5)
        gc.fill(Olo.ellisse(ax, ay, 2.4, 2.4), with: .color(Olo.bianco))
        var f = Path()
        f.move(to: CGPoint(x: ax, y: ay)); f.addLine(to: CGPoint(x: W - 24, y: ly - 4)); f.addLine(to: CGPoint(x: W - 24 - (W - 28) * u, y: ly - 4))
        gc.stroke(f, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(1.1))
        gc.fill(Path(CGRect(x: bx, y: by, width: bw * u, height: bh)),
                with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0.13), Olo.azzurro.opacity(0.02)]),
                                      startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + bh)))
        gc.stroke(Path(CGRect(x: bx + 0.5, y: by + 0.5, width: bw * u, height: bh)), with: .color(Olo.ciano.opacity(0.32)), style: Olo.tratto(1.1))
        var ang = Path()
        let k = 9.0
        let angoli: [(x: Double, y: Double, sx: Double, sy: Double)] = [(x: bx, y: by, sx: 1, sy: 1), (x: bx + bw * u, y: by, sx: -1, sy: 1),
                                                                         (x: bx, y: by + bh, sx: 1, sy: -1), (x: bx + bw * u, y: by + bh, sx: -1, sy: -1)]
        for (px, py, sx, sy) in angoli {
            ang.move(to: CGPoint(x: px + sx * k, y: py)); ang.addLine(to: CGPoint(x: px, y: py)); ang.addLine(to: CGPoint(x: px, y: py + sy * k))
        }
        gc.stroke(ang, with: .color(Olo.bianco.opacity(0.9)), style: Olo.tratto(1.5))
        // la riga di scansione che scende lenta dentro la scheda
        if bh > 12 {
            let sy = by + (t * 26).truncatingRemainder(dividingBy: bh)
            gc.fill(Path(CGRect(x: bx, y: sy - 10, width: bw * u, height: 10)),
                    with: .linearGradient(Gradient(colors: [Olo.azzurro.opacity(0), Olo.azzurro.opacity(0.10)]),
                                          startPoint: CGPoint(x: 0, y: sy - 10), endPoint: CGPoint(x: 0, y: sy)))
        }
    }
}
#endif
