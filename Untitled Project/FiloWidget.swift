#if os(iOS)
import SwiftUI
import UIKit

// MARK: - 13.0 · FILO, UNA SCHEDA SOLA
// Il signore (13 nov, 22:33): «come FILO ma tutto raggruppato in un'unica tab, anziché aprirne varie per ogni argomento»; sotto le
// icone di sistema in alto a destra, olografico, interattivo e navigabile. «Mostrami…» sparisce in 2,8 s come una notifica,
// «fissalo» lo tiene, toccato resta finché lui non ha finito di scorrere. Ogni argomento ha la sua testata col nome e, in fondo a
// destra sulla stessa linea, la X che chiude solo quello. Le cose sparite tornano con lo swipe verso sinistra dal bordo destro, nella
// fascia di FILO (13.1: prima la striscia era lunga 280 punti e copriva l'anello delle icone); lo swipe verso destra su FILO le
// rimanda via. Scelta SCORRI (23:02): gli argomenti uno sotto l'altro, giù e su. Sopra una sezione FILO è vetro con la
// trasparenza dinamica della PILA (13.1). Misure, colori e tempi come il mockup (v1216/q16-9.js, q16-9.css).

/// Lo strato di FILO sopra la schermata e le sezioni (ContentView), con la fascia invisibile del bordo destro che lo richiama quando è via.
struct StratoFilo: View {
    @ObservedObject private var filo = Filo.condiviso
    /// 13.1: il menu SISTEMI o la tendina PROTOCOLLI sono aperti (stanno nello stesso angolo): FILO si fa da parte finché si chiudono.
    var daParte = false
    /// 13.1: una sezione è davanti: sopra di lei FILO è vetro olografico con la trasparenza dinamica della PILA.
    var suSezione = false

    var body: some View {
        let visti = filo.visti
        let alto = filo.sottoIcone > 0 ? filo.sottoIcone + 6 : (FasciaAlta.finestra?.safeAreaInsets.top ?? 59) + 58
        ZStack(alignment: .topTrailing) {
            Color.clear
            if !visti.isEmpty {
                SchedaFilo(argomenti: visti, vetro: suSezione)
                    .padding(.top, alto)
                    .padding(.trailing, 10)
                    .transition(.asymmetric(insertion: .identity, removal: .offset(x: 240).combined(with: .opacity)))   // la nascita la fa la scheda
            }
            // 13.1 (il signore, 14 nov: «per richiamarlo il modo migliore per non dare noia alle icone dell'anello»; 02:40: niente
            // punto di luce, «swipe invisibile in alto»): con FILO via e qualcosa da richiamare, lo swipe verso sinistra dal bordo
            // destro nella fascia di FILO (sotto le icone di sistema, sopra la corona) lo riporta. Prima la striscia era lunga
            // 280 punti e copriva l'anello delle icone a destra e la sua rotazione.
            if visti.isEmpty && !filo.argomenti.isEmpty {
                FasciaFilo()
                    .padding(.top, alto - FasciaFilo.sopra)
            }
        }
        .ignoresSafeArea()
        .opacity(daParte ? 0 : 1)
        .allowsHitTesting(!daParte)
        .animation(.easeOut(duration: 0.2), value: daParte)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3), value: visti.isEmpty)
        .onChange(of: daParte, initial: true) { _, v in filo.daParte = v }
    }
}

/// 13.1 · Il richiamo di FILO quando la scheda è via (il signore, 14 nov 02:40: il punto di luce no; «swipe invisibile in alto»):
/// una fascia invisibile lungo il bordo destro, solo dove sta FILO (sotto le icone di sistema, sopra la corona): lo swipe verso
/// sinistra che parte da lì lo riporta. 24×64 punti: non arriva mai all'anello delle icone (che col suo margine finisce più in
/// basso anche sugli iPhone da 375 punti), come prima faceva la striscia di 280 punti.
private struct FasciaFilo: View {
    static let largo: CGFloat = 24
    static let alto: CGFloat = 64
    /// Quanto la fascia sale sopra la cima di FILO.
    static let sopra: CGFloat = 4

    var body: some View {
        Color.clear
            .frame(width: FasciaFilo.largo, height: FasciaFilo.alto)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { v in
                        guard v.translation.width < -30, abs(v.translation.height) < 40 else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { _ = Filo.condiviso.richiama() }
                    }
            )
            // 14 nov (come il mockup): sul Mac e con il trackpad dell'iPad, due dita verso sinistra sulla fascia la richiamano
            .modifier(DueDitaFilo { dx in
                guard dx < -40 else { return }
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { _ = Filo.condiviso.richiama() }
            })
            .accessibilityElement()
            .accessibilityLabel("FILO")
            .accessibilityHint("Riporta quello che è sparito")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { _ = Filo.condiviso.richiama() }
    }
}

/// 14 nov · lo swipe a due dita del trackpad (Mac, iPad con la tastiera), come le rotelle del mockup: non è un trascinamento, iOS
/// lo dà solo a un riconoscitore che accetta lo scorrimento. Le dita sullo schermo non le prende (restano agli altri gesti) e lavora
/// insieme a tutti gli altri (la lista della tab scorre su e giù come sempre). `fine`: lo spostamento orizzontale a gesto finito.
/// Prima di iOS 18 (iPhone senza trackpad) non serve: non c'è.
private struct DueDitaFilo: ViewModifier {
    let fine: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(GestoDueDita(fine: fine))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct GestoDueDita: UIGestureRecognizerRepresentable {
    let fine: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.allowedScrollTypesMask = .continuous
        g.allowedTouchTypes = []
        g.delegate = InsiemeAgliAltri.condiviso
        return g
    }

    func handleUIGestureRecognizerAction(_ g: UIPanGestureRecognizer, context: Context) {
        guard g.state == .ended else { return }
        let t = g.translation(in: g.view)
        guard abs(t.x) > abs(t.y) * 1.5 else { return }
        fine(t.x)
    }
}

/// Il trackpad della tab lavora insieme agli altri gesti (lo scorrimento della lista, i tocchi).
private final class InsiemeAgliAltri: NSObject, UIGestureRecognizerDelegate {
    static let condiviso = InsiemeAgliAltri()
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith altro: UIGestureRecognizer) -> Bool { true }
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
    /// 13.1: sopra una sezione (vetro olografico che segue il fuoco); sulla schermata di JARVIS resta il fondo scuro di sempre.
    let vetro: Bool
    @ObservedObject private var filo = Filo.condiviso
    /// Il fondo scuro: da quanto a quanto sta andando, e da quando (lo legge la cornice a ogni fotogramma, 120 Hz).
    @State private var scuro: (da: Double, a: Double, t0: Date) = (da: 0.93, a: 0.93, t0: .distantPast)
    /// Il vetro (sfocatura) entra a nascita finita, come il fondo che si apre.
    @State private var vetroPronto = false
    @State private var nata = Date()
    @State private var contenuto: CGFloat = 0
    @State private var sopra = false        // c'è altro sopra (scorso giù)
    @State private var sotto = false        // c'è altro sotto
    @State private var dx: CGFloat = 0
    @State private var fase: Double = 0     // la nascita (0 → 1)
    @GestureState private var trascina = false   // il dito trascina sulla scheda (torna falso da solo anche se il gesto si interrompe)

    static let larghezza: CGFloat = 212
    static let altezzaMassima: CGFloat = 200

    /// Quanto è pieno il fondo scuro: sulla schermata di JARVIS 0,93 come sempre; sopra una sezione come il vetro della PILA
    /// (0,5 + 0,38 × fuoco): 0,88 a fuoco, 0,5 in secondo piano.
    private var fondoVoluto: Double { vetro ? (filo.fuoco ? 0.88 : 0.5) : 0.93 }

    var body: some View {
        let altezza = min(Self.altezzaMassima, max(30, contenuto))
        VStack(alignment: .leading, spacing: 0) {
            // 14 nov (il signore: «in alto FILO, ma che c'entra? mostri solo l'headline con scritto meteo»): niente testata FILO,
            // si vedono solo gli argomenti (METEO, AGENDA…) col loro nome
            Color.clear.frame(height: 22)                                        // lo spazio della testata resta (come prima)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(argomenti.enumerated()), id: \.element.id) { i, a in
                        // 14 nov (scelta del signore): in secondo piano compatta, una riga per argomento
                        ArgomentoVista(a: a, primo: i == 0, compatta: !filo.fuoco)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                    removal: .opacity.combined(with: .offset(x: 24))))
                    }
                }
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26), value: filo.fuoco)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                    contenuto = h
                    if #unavailable(iOS 18.0) { sotto = h > Self.altezzaMassima + 4 }   // iOS 17: c'è altro sotto
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: altezza)
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26), value: altezza)   // si stringe e si riapre col contenuto
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
            // meno trasparente: il fondo scuro dentro la cornice, poi la cornice olografica (luce, filo, angoli, scansione).
            // 13.1: sopra una sezione, sotto il fondo c'è il vetro della PILA (VetroOlo): a fuoco pieno e sfocato, in secondo
            // piano trasparente (la sezione si vede attraverso), con gli stessi valori delle pagine olografiche.
            ZStack {
                if vetro {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .padding(EdgeInsets(top: 24, leading: 4, bottom: 3, trailing: 4))
                        .opacity(vetroPronto ? 0.3 + 0.7 * (filo.fuoco ? 1 : 0) : 0)
                        .animation(.easeInOut(duration: 0.35), value: filo.fuoco)
                        .animation(.easeOut(duration: 0.2), value: vetroPronto)
                        .transition(.opacity)
                }
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSince(nata)
                    let p = min(1, max(0, tl.date.timeIntervalSince(scuro.t0) / 0.35))
                    let fondo = scuro.da + (scuro.a - scuro.da) * Olo.liscia(p)
                    Canvas(rendersAsynchronously: false) { gc, size in
                        CorniceFilo.disegna(&gc, size, t: t, fondo: fondo)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: vetro)
            .allowsHitTesting(false)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { filo.rettScheda = $0 }
        .onChange(of: fondoVoluto, initial: true) { _, nuovo in
            // il fondo riparte da dove si trova adesso verso il nuovo valore (anche a metà di un cambio)
            let p = min(1, max(0, Date().timeIntervalSince(scuro.t0) / 0.35))
            let ora = scuro.da + (scuro.a - scuro.da) * Olo.liscia(p)
            scuro = (da: scuro.t0 == .distantPast ? nuovo : ora, a: nuovo, t0: Date())
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            vetroPronto = true
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
                    // 14 nov: basta anche un colpo veloce verso destra (corto ma lanciato), come le notifiche di iOS
                    let lanciata = v.translation.width > 30 && v.predictedEndTranslation.width > 170
                    if v.translation.width > 80 || lanciata, v.translation.width > abs(v.translation.height) * 2.5 {
                        Suoni.filoVia()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.timingCurve(0.4, 0, 0.8, 0.4, duration: 0.24)) { Filo.condiviso.rimandaVia() }
                        dx = 0
                        return
                    }
                    withAnimation(.easeOut(duration: 0.2)) { dx = 0 }
                }
        )
        // 14 nov (come il mockup): sul Mac e con il trackpad dell'iPad, due dita verso destra sulla tab la mandano via
        .modifier(DueDitaFilo { dx in
            guard dx > 60 else { return }
            Suoni.filoVia()
            withAnimation(.timingCurve(0.4, 0, 0.8, 0.4, duration: 0.24)) { Filo.condiviso.rimandaVia() }
        })
        .onChange(of: trascina) { _, v in
            Filo.condiviso.toccato(v, da: "trascina")                     // finito (o interrotto): altri 2,8 secondi
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
/// 14 nov (scelta del signore, 09:08): `compatta` (la tab in secondo piano) è una riga sola, il nome e il dato che conta (il primo
/// impegno, il meteo…); toccata torna intera. E mentre JARVIS parla si accende la riga che sta dicendo. Come il mockup.
private struct ArgomentoVista: View {
    let a: ArgomentoFilo
    let primo: Bool
    let compatta: Bool
    @ObservedObject private var filo = Filo.condiviso
    @State private var accesa = false

    var body: some View {
        let tutte = righe
        VStack(alignment: .leading, spacing: 1) {
            if !primo {
                // tra un argomento e l'altro una linea di luce
                LinearGradient(colors: [Olo.azzurro.opacity(0), Olo.azzurro.opacity(0.45), Olo.azzurro.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.bottom, compatta ? 3 : 8)
                    .padding(.top, compatta ? 2 : 10)
            }
            HStack(spacing: 6) {
                Text((a.etichetta ?? a.nome).uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.8)
                    .foregroundStyle(Olo.bianco)
                    .shadow(color: Olo.azzurro.opacity(0.95), radius: 3.5)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: a.etichetta == nil, vertical: false)   // 14 nov: il titolo lungo del piano si accorcia, la X resta
                    .layoutPriority(1)
                if a.fisso {
                    Text("◆")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Olo.bianco.opacity(0.95))
                        .shadow(color: Olo.azzurro.opacity(0.9), radius: 3)
                        .accessibilityLabel("fissato")
                }
                if compatta {
                    // compatta: al posto della linea e della X, il dato che conta
                    Text(tutte.first?.testo ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 236 / 255, green: 252 / 255, blue: 1).opacity(0.96))
                        .shadow(color: Olo.azzurro.opacity(0.85), radius: 4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                } else {
                    LinearGradient(colors: [Olo.ciano.opacity(0.7), Olo.ciano.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 1)
                        .transition(.opacity)
                    Button {
                        guard !Filo.condiviso.consumaSveglia() else { return }   // era compatta: il tocco l'ha solo riaperta
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
                            .contentShape(Rectangle().inset(by: -8))           // 14 nov: si prende col dito (44 punti), il disegno è quello
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, -6)
                    .accessibilityLabel("Chiudi \(a.nome)")
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 24)
            // 14 nov: tenuto premuto sul nome, si fissa (◆) come con «fissalo»; ancora, si sgancia
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) { Filo.condiviso.fissaArgomento(a.nome) }
            }
            .accessibilityAction(named: a.fisso ? "Sgancia" : "Fissa") { Filo.condiviso.fissaArgomento(a.nome) }
            if !compatta {
                // la riga che JARVIS sta dicendo si accende (si guarda solo mentre parla): una sola in tutta la tab, quella detta per ultima
                TimelineView(.animation(minimumInterval: 0.1, paused: filo.voceOra == nil)) { tl in
                    let tab: [RigaVista] = filo.visti.flatMap { ArgomentoVista.righeDi($0) }
                    let detta = Filo.rigaDetta(tab.map { r -> (id: String, testo: String) in (id: r.id, testo: r.testo) }, voce: filo.voceOra, ora: tl.date)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(tutte) { r in riga(r, detta: r.id == detta) }
                    }
                }
                .transition(.opacity)
            }
        }
        // appena arrivato (o aggiornato) si accende un attimo; richiamato col dito dal bordo no (come il mockup)
        .brightness(accesa ? 0.35 : 0)
        .onAppear { if Date().timeIntervalSince(a.aggiornato) < 0.6 { accendi() } }
        .onChange(of: a.giro) { accendi() }
    }

    /// Una riga: toccata apre la sua sezione; mentre JARVIS la dice è accesa (come `.f2-r.detta` del mockup).
    private func riga(_ r: RigaVista, detta: Bool) -> some View {
        Button {
            guard !Filo.condiviso.consumaSveglia() else { return }       // era compatta: il tocco l'ha solo riaperta
            if let s = r.sezione { Suoni.tocco(); Regia.condivisa.porta(s) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let icona = r.icona {
                    Image(systemName: icona)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Olo.ciano)
                        .shadow(color: Olo.azzurro.opacity(0.85), radius: 4)
                        .accessibilityHidden(true)
                }
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
            .background {
                if detta {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Olo.azzurro.opacity(0.16))
                        .overlay(alignment: .leading) { Rectangle().fill(Olo.ciano).frame(width: 2) }
                        .shadow(color: Olo.azzurro.opacity(0.25), radius: 5)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: detta)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(r.sezione == nil ? "" : "Apre \(r.sezione ?? "")")
    }

    private func accendi() {
        accesa = true
        withAnimation(.easeOut(duration: 0.5)) { accesa = false }
    }

    private var righe: [RigaVista] { ArgomentoVista.righeDi(a) }

    /// L'agenda un impegno per riga («11:30 dentista», «18:00 palestra»), senza l'ora di quando è stata mostrata; le altre una riga
    /// per dato, con l'ora.
    private static func righeDi(_ a: ArgomentoFilo) -> [RigaVista] {
        var v: [RigaVista] = []
        for r in a.righe {
            if a.nome == "Piano" {                                         // 14 nov: i passi del piano, senza l'ora
                v.append(RigaVista(id: r.id, testo: r.riga, sezione: nil, ora: nil))
            } else if a.nome == "Agenda" {
                let pezzi = r.riga.components(separatedBy: " · ")
                let titolo = Filo.testo(di: RigaFilo(id: r.id, titolo: r.titolo, riga: "", sezione: nil, alle: r.alle), in: a.nome)
                for (k, pezzo) in pezzi.enumerated() {
                    v.append(RigaVista(id: r.id + "#\(k)", testo: (k == 0 && !titolo.isEmpty ? titolo : "") + pezzo, sezione: r.sezione, ora: nil))
                }
            } else {
                v.append(RigaVista(id: r.id, testo: Filo.testo(di: r, in: a.nome), sezione: r.sezione, ora: ArgomentoVista.formato.string(from: r.alle), icona: r.icona))
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
                .onScrollPhaseChange { _, fase in Filo.condiviso.toccato(fase != .idle, da: "scorre") }
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
    var icona: String? = nil
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
    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, fondo: Double = 0.93) {
        let W = Double(size.width), H = Double(size.height)
        let u0 = min(1, t / 0.5)
        gc.opacity = u0 < 1 ? (sin(u0 * 40) > -0.2 ? u0 : u0 * 0.3) : 1          // si accende sfarfallando
        let ax = W - 6, ay = 6.0, u = Olo.liscia(t / 0.45), ly = 24.0, bx = 4.0, by = ly, bw = W - 8, bh = H - by - 3
        // il fondo (meno trasparente: la corona dietro si intuisce appena); 13.1: sopra una sezione segue il fuoco (vetro della PILA)
        gc.fill(Path(CGRect(x: bx, y: by, width: bw * u, height: bh)), with: .color(Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255).opacity(fondo)))
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
