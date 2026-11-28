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

/// 13.7 (il signore, 21 nov 20:05: «tutto deve essere in gradazione di ciano»): niente più bianco nelle tab; il più chiaro è il
/// ciano chiaro #bff6ff, poi #8ff0ff (Olo.ciano) e #4fe3ff (Olo.azzurro). La stessa luce nella tab bassa (PAGINE).
enum TintaTab {
    static let chiaro = Color(red: 191 / 255, green: 246 / 255, blue: 1)
    /// La trasparenza dinamica delle due tab (22 nov 01:04): aperta 60 %, piccola 55 %.
    // 13.8 (4) (il signore, 22 nov 12:22, video: «la trasparenza olografica deve essere ben visibile come nello swipe», cioè come le
    // pagine che vanno dietro): il fondo delle tab è quello delle pagine olografiche (VetroOlo a riposo: 50 %), da piccola 45 %
    // 23 nov: i valori li dà il vetro unico degli ologrammi (StileOlo)
    static var vetroAperta: Double { StileOlo.scelto.fondo }
    static var vetroPiccola: Double { StileOlo.scelto.fondoPiccola }
    /// 13.8 (5) (il signore, 22:49: «88 % forse meglio più basso, altrimenti sembra uguale a prima: si deve capire che è olografico»;
    /// «anche Mail deve essere uguale agli altri»): un ologramma davanti (FILO a fuoco sopra una sezione, la tendina sopra una
    /// sezione, la mail, la pagina davanti della PILA) ha il fondo al 70 %, uguale per tutti.
    static var vetroDavanti: Double { StileOlo.scelto.fondoDavanti }
}

/// 23 nov (il signore, dopo la 13.8 (7): «ologrammi molto belli ma vanno ottimizzati: due versioni senza righine orizzontali e senza
/// l'animazione della riga che scende; tutti con lo stesso stile identico, invece di colori ed effetti diversi»): UN SOLO VETRO per
/// FILO, la tab bassa (PAGINE), la tendina PROTOCOLLI, la Mail e la navigazione (la PILA e lo sfoglio dal bordo). Niente righe,
/// niente riga che scende, niente sfocatura. Il vetro: il fondo scuro (la trasparenza dinamica: aperta, piccola, davanti sopra una
/// sezione), la luce ciano dall'alto, il bordo di luce, il bagliore dai bordi dentro e (solo CHIARO) l'alone fuori. Due prove nel
/// mockup (JARVIS Telefono, OLOGRAMMI): SCURO e CHIARO, valori uguali al mockup. Scelto SCURO (04:42).
struct StileOlo {
    /// Il fondo scuro: aperta, piccola, davanti (sopra una sezione, la Mail, la pagina davanti della PILA).
    let fondo: Double
    let fondoPiccola: Double
    let fondoDavanti: Double
    /// La PILA: il vetro delle pagine è 50 % dietro e 70 % davanti, più questo.
    let pila: Double
    /// La luce ciano dall'alto: in cima, al 40 %, in fondo.
    let luceAlto: Double
    let luceMezzo: Double
    let luceBasso: Double
    /// Il bordo di luce (1 punto).
    let bordo: Color
    /// Il bagliore dai bordi, dentro: quanto e quanto entra.
    let alone: Double
    let aloneRaggio: CGFloat
    /// L'alone fuori (0: niente).
    let fuori: Double
    let fuoriRaggio: CGFloat

    /// SCURO: vetro denso con la luce ciano (il signore, 04:38: «il ciano ci deve essere»).
    static let scuro = StileOlo(fondo: 0.72, fondoPiccola: 0.62, fondoDavanti: 0.84, pila: 0.14,
                                luceAlto: 0.12, luceMezzo: 0.03, luceBasso: 0.07,
                                bordo: Color(red: 79 / 255, green: 227 / 255, blue: 1).opacity(0.45),
                                alone: 0.16, aloneRaggio: 18, fuori: 0, fuoriRaggio: 0)
    /// CHIARO: ologramma ciano molto trasparente e luminoso, bordo acceso e alone attorno.
    static let chiaro = StileOlo(fondo: 0.28, fondoPiccola: 0.24, fondoDavanti: 0.42, pila: -0.2,
                                 luceAlto: 0.2, luceMezzo: 0.07, luceBasso: 0.13,
                                 bordo: Color(red: 160 / 255, green: 244 / 255, blue: 1).opacity(0.85),
                                 alone: 0.28, aloneRaggio: 30, fuori: 0.45, fuoriRaggio: 16)
    /// Quello scelto dal signore (23 nov, 04:42: «vetro SCURO su tutto, bellissimo»).
    static let scelto: StileOlo = .scuro

    /// La luce ciano dall'alto (forza 0…1: le pagine della PILA la fanno crescere col dito).
    func luce(_ forza: Double = 1) -> LinearGradient {
        let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
        return LinearGradient(stops: [.init(color: ciano.opacity(luceAlto * forza), location: 0),
                                      .init(color: ciano.opacity(luceMezzo * forza), location: 0.4),
                                      .init(color: ciano.opacity(luceBasso * forza), location: 1)],
                              startPoint: .top, endPoint: .bottom)
    }
}

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
            if !visti.isEmpty || filo.vuota {
                SchedaFilo(argomenti: visti, vetro: suSezione, fermo: daParte)
                    .padding(.top, alto)
                    .padding(.trailing, 10)
                    .transition(.asymmetric(insertion: .identity, removal: .offset(x: 240).combined(with: .opacity)))   // la nascita la fa la scheda
            }
            // 13.1 (il signore, 14 nov: «per richiamarlo il modo migliore per non dare noia alle icone dell'anello»; 02:40: niente
            // punto di luce, «swipe invisibile in alto»): con FILO via e qualcosa da richiamare, lo swipe verso sinistra dal bordo
            // destro nella fascia di FILO (sotto le icone di sistema, sopra la corona) lo riporta. Prima la striscia era lunga
            // 280 punti e copriva l'anello delle icone a destra e la sua rotazione.
            // 13.8: la fascia c'è sempre, anche senza niente da riportare (la tab si apre vuota, con «NESSUNA NOTIFICA»)
            if visti.isEmpty && !filo.vuota {
                FasciaFilo()
                    .padding(.top, alto - FasciaFilo.sopra)
            }
        }
        .ignoresSafeArea()
        .opacity(daParte ? 0 : 1)
        .allowsHitTesting(!daParte)
        .animation(.easeOut(duration: 0.2), value: daParte)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3), value: visti.isEmpty)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3), value: filo.vuota)
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { Filo.condiviso.rettFascia = $0 }
            .onDisappear { Filo.condiviso.rettFascia = .zero }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { v in
                        guard v.translation.width < -30, abs(v.translation.height) < 40 else { return }
                        // la vibrazione la dà il suono della tab (Suoni.filo → Aptica.tabArriva), nello stesso istante
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
    /// Debug 13.8 (8), punto 7: FILO nascosto (menu SISTEMI o tendina aperti): la cornice non si ridisegna (120 volte al secondo).
    var fermo = false
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

    /// Quanto è pieno il fondo scuro. 13.7 (il signore, 22 nov 01:04: «la trasparenza dinamica: piccola 55 %, aperta 60 %»): uguale
    /// sulla schermata di JARVIS e sopra una sezione, con il vetro sfocato dietro (prima 0,93 su JARVIS; 0,88 / 0,5 sopra una sezione).
    /// 13.8 (4) (il signore, 12:45: «quell'effetto sfocato di Apple deve sparire da ogni ologramma»): niente sfocatura; la trasparenza
    /// dinamica la fa il fondo, come le pagine della PILA: sopra una sezione, a fuoco, quasi pieno (70 %, TintaTab.vetroDavanti, come la pagina davanti), così
    /// si legge; in secondo piano e sulla schermata di JARVIS trasparente (50 %, piccola 45 %).
    private var fondoVoluto: Double { vetro && filo.fuoco ? TintaTab.vetroDavanti : (filo.fuoco ? TintaTab.vetroAperta : TintaTab.vetroPiccola) }

    var body: some View {
        let altezza = min(Self.altezzaMassima, max(30, contenuto))
        VStack(alignment: .leading, spacing: 0) {
            // 14 nov (il signore: «in alto FILO, ma che c'entra? mostri solo l'headline con scritto meteo»): niente testata FILO,
            // si vedono solo gli argomenti (METEO, AGENDA…) col loro nome
            Color.clear.frame(height: 22)                                        // lo spazio della testata resta (come prima)
            // 13.7 (il signore, 21 nov 20:22–20:38): i tre tasti come quelli di Apple, in alto a destra dentro la tab, con la linea
            // sotto; si toccano anche da piccola (e il dito lì non la sveglia)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                TastiTab(chiudi: {
                    Suoni.filoVia()                                                // suono e tocco insieme (Aptica.tabVia)
                    withAnimation(.timingCurve(0.4, 0, 0.8, 0.4, duration: 0.24)) { Filo.condiviso.rimandaVia() }
                }, riduci: {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { Filo.condiviso.riduci() }
                }, apri: {
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { Filo.condiviso.apri() }
                })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { filo.rettTasti = $0 }
            }
            .frame(height: 14, alignment: .top)
            .padding(.bottom, 5)
            .overlay(alignment: .bottom) {
                // la linea sotto i tasti, poi gli argomenti
                LinearGradient(colors: [Olo.azzurro.opacity(0.08), Olo.azzurro.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.leading, -2)
            }
            .padding(.top, 4)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if argomenti.isEmpty {
                        // 13.8 · richiamata vuota (come la tab bassa con «NESSUNA PAGINA»)
                        Text("NESSUNA NOTIFICA")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2.4)
                            .foregroundStyle(Color.tenue)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                            .padding(.bottom, 10)
                    }
                    ForEach(Array(argomenti.enumerated()), id: \.element.id) { i, a in
                        // 14 nov (scelta del signore): in secondo piano compatta, una riga per argomento
                        ArgomentoVista(a: a, primo: i == 0, compatta: !filo.fuoco)
                            // 13.7: chiuso con lo swipe esce a sinistra (−110 %), come il mockup; mandato via in altro modo, a destra
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                    removal: .opacity.combined(with: .offset(x: filo.esceASinistra == a.nome ? -SchedaFilo.larghezza * 1.1 : 24))))
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
                // 13.8 (4) (il signore, 12:45): niente sfocatura di Apple; il fondo scuro (dentro la cornice) fa la trasparenza dinamica:
                // sopra una sezione, a fuoco, 88 %; altrimenti 50 % (piccola 45 %)
                TimelineView(.animation(minimumInterval: nil, paused: fermo)) { tl in
                    let t = tl.date.timeIntervalSince(nata)
                    let p = min(1, max(0, tl.date.timeIntervalSince(scuro.t0) / 0.35))
                    let fondo = scuro.da + (scuro.a - scuro.da) * Olo.liscia(p)
                    // 13.9 (18) · issue 22: sulla schermata di JARVIS il vetro si scalda con lo sfondo; sopra una sezione dietro c'è la
                    // sezione, non lo sfondo: resta com'è
                    let caldo = vetro ? 0 : CaloreVetro.condiviso.valore(tl.date)
                    // 23 nov (il signore: «il cerchio che le lancia è tagliato da 2 spigoli, come fosse un quadrato»): il bagliore del
                    // punto di luce (6 punti dall'angolo, largo 10) usciva dalla tela; la tela sporge 12 punti per lato
                    Canvas(rendersAsynchronously: false) { gc, size in
                        gc.translateBy(x: CorniceFilo.sporge, y: CorniceFilo.sporge)
                        CorniceFilo.disegna(&gc, CorniceFilo.dentro(size), t: t, fondo: fondo, caldo: caldo)
                    }
                    .padding(-CorniceFilo.sporge)
                }
                // 13.8 (4): sopra il fondo, la luce delle pagine olografiche (come nello swipe delle sezioni)
                LuceOlografica()
                    .padding(EdgeInsets(top: 24, leading: 4, bottom: 3, trailing: 4))
                    .opacity(vetroPronto ? 1 : 0)
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
                        Suoni.filoVia()                                            // suono e tocco insieme (Aptica.tabVia)
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
                // 20 nov (il signore: «sistemare quel punto debole»): tenuto premuto sul nome si fissa (◆) come con «fissalo»; ancora,
                // si sgancia. Prima era `onLongPressGesture` su tutta la testata: dentro la lista che scorre, un gesto esclusivo può
                // trattenere il dito e lo scorrimento non parte se il dito comincia proprio sul nome. Ora la pressione lavora insieme
                // allo scorrimento (si annulla da sola se il dito si sposta di più di 10 punti, cioè se si scorre) e solo su nome e
                // linea: la X resta un tasto e basta, come nel mockup (lì la pressione non parte dalla X).
                HStack(spacing: 6) {
                    Text((a.etichetta ?? a.nome).uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.8)
                        .foregroundStyle(TintaTab.chiaro)
                        .shadow(color: Olo.azzurro.opacity(0.95), radius: 3.5)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: a.etichetta == nil, vertical: false)   // 14 nov: il titolo lungo del piano si accorcia, la X resta
                        .layoutPriority(1)
                    if a.fisso {
                        Text("◆")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(TintaTab.chiaro.opacity(0.95))
                            .shadow(color: Olo.azzurro.opacity(0.9), radius: 3)
                            .accessibilityLabel("fissato")
                    }
                    if compatta {
                        // compatta: al posto della linea e della X, il dato che conta
                        Text(tutte.first.map { r in (r.segno.map { $0 + " " } ?? "") + r.testo } ?? "")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TintaTab.chiaro)
                            .shadow(color: Olo.azzurro.opacity(0.85), radius: 4)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    } else {
                        LinearGradient(colors: [Olo.ciano.opacity(0.7), Olo.ciano.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1)
                            .transition(.opacity)
                    }
                }
                .frame(minHeight: 24)
                .contentShape(Rectangle())
                // 13.7 (il signore, 22 nov 01:04: «per evitare la ripetizione grafica, nella tab grande le sezioni si chiudono con
                // uno swipe verso sinistra e non con la X»): la X non c'è più (lo swipe qui sotto)
            }
            .frame(minHeight: 24)
            .accessibilityAction(named: a.fisso ? "Sgancia" : "Fissa") { Filo.condiviso.fissaArgomento(a.nome) }
            .accessibilityAction(named: "Chiudi") { chiudiASinistra() }
            if !compatta {
                // la riga che JARVIS sta dicendo si accende: una sola in tutta la tab, quella detta per ultima. La tab si ridisegna proprio
                // negli istanti in cui la voce arriva a una riga (niente controlli a intervalli), l'accensione corre a 120 Hz
                let tab: [RigaVista] = filo.visti.flatMap { ArgomentoVista.righeDi($0) }
                let coppie: [(id: String, testo: String)] = tab.map { r -> (id: String, testo: String) in (id: r.id, testo: r.testo) }
                TimelineView(.explicit(Filo.cambiDetta(coppie, voce: filo.voceOra))) { tl in
                    let detta = Filo.rigaDetta(coppie, voce: filo.voceOra, ora: tl.date)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(tutte) { r in riga(r, detta: r.id == detta) }
                    }
                }
                .transition(.opacity)
            }
        }
        // 21 nov (scelta del signore: «l'argomento sotto il dito»): tenuto premuto ovunque sull'argomento (il nome, la linea o il
        // testo) si fissa ◆; di nuovo, si sgancia. Prima solo su nome e linea. Lavora insieme allo scorrimento (si annulla da sola se
        // il dito si sposta di più di 10 punti, cioè se si scorre); il dito che si alza dopo non apre la riga e non chiude (consumaFissa).
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    Aptica.tabFissa(!a.fisso)                                   // 14 nov: fissata un colpo pieno, sganciata la selezione
                    withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) { Filo.condiviso.fissaArgomento(a.nome) }
                }
        )
        // 13.7: il dito che corre verso sinistra sull'argomento lo chiude (esce a sinistra). Verso destra resta il gesto che manda
        // via tutta la tab. Come il mockup: almeno 40 punti, orizzontale (il doppio del verticale), lungo (70) o svelto
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    let dx = v.translation.width, dy = abs(v.translation.height)
                    let svelto = -v.predictedEndTranslation.width > 170                 // circa 0,35 punti al millisecondo
                    guard dx < -40, -dx > dy * 2, -dx > 70 || svelto else { return }
                    chiudiASinistra()
                }
        )
        // appena arrivato (o aggiornato) si accende un attimo; richiamato col dito dal bordo no (come il mockup)
        .brightness(accesa ? 0.35 : 0)
        .onAppear { if Date().timeIntervalSince(a.aggiornato) < 0.6 { accendi() } }
        .onChange(of: a.giro) { accendi() }
    }

    /// Una riga: toccata apre la sua sezione; mentre JARVIS la dice è accesa (come `.f2-r.detta` del mockup).
    private func riga(_ r: RigaVista, detta: Bool) -> some View {
        Button {
            guard !Filo.condiviso.consumaSveglia() else { return }       // era compatta: il tocco l'ha solo riaperta
            guard !Filo.condiviso.consumaFissa() else { return }         // 21 nov: la pressione lunga ha appena fissato
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
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // 14 nov (il signore: «il testo si muove quando fa la spunta»): il segno del piano (○ ▸ ✓ ◇ ✕) sta in uno spazio
                    // fisso, così quando cambia il testo resta fermo
                    if let segno = r.segno {
                        Text(segno)
                            .frame(width: 10, alignment: .leading)
                    }
                    // 21 nov (il signore: «la frase finisce coi puntini anziché poter rileggere lì tutta la risposta»): il testo va
                    // a capo e si legge tutto; se è più alto della tab (200 punti) la lista scorre su e giù
                    Text(r.testo)
                        .lineSpacing(1.5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(TintaTab.chiaro)
                .shadow(color: Olo.azzurro.opacity(0.85), radius: 4)
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

    /// 13.7 · chiuso con lo swipe a sinistra: esce verso sinistra (0,26 s, la curva del mockup), poi il posto si chiude.
    private func chiudiASinistra() {
        let nome = a.nome
        Suoni.filoVia()                                                // suono e tocco insieme (Aptica.tabVia)
        Filo.condiviso.esceASinistra = nome
        Task { @MainActor in
            await Task.yield()                                         // la sua uscita (a sinistra) è già quella nuova
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.26)) { _ = Filo.condiviso.togliArgomento(nome) }
            try? await Task.sleep(for: .milliseconds(320))
            if Filo.condiviso.esceASinistra == nome { Filo.condiviso.esceASinistra = nil }
        }
    }

    private var righe: [RigaVista] { ArgomentoVista.righeDi(a) }

    /// L'agenda un impegno per riga («11:30 dentista», «18:00 palestra»), senza l'ora di quando è stata mostrata; le altre una riga
    /// per dato, con l'ora. 20 nov: un elenco (le voci a capo, Filo.voci) va in colonna in ogni argomento, l'ora sulla prima voce.
    private static func righeDi(_ a: ArgomentoFilo) -> [RigaVista] {
        var v: [RigaVista] = []
        for r in a.righe {
            if a.nome == "Piano" {                                         // 14 nov: i passi del piano, senza l'ora; il segno a parte
                let pezzi = r.riga.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                let segno: String? = pezzi.count == 2 && pezzi[0].count == 1 ? String(pezzi[0]) : nil
                v.append(RigaVista(id: r.id, testo: segno == nil ? r.riga : String(pezzi[1]), sezione: nil, ora: nil, segno: segno))
            } else if a.nome == "Agenda" {
                let pezzi = r.riga.components(separatedBy: " · ")
                let titolo = Filo.testo(di: RigaFilo(id: r.id, titolo: r.titolo, riga: "", sezione: nil, alle: r.alle), in: a.nome)
                for (k, pezzo) in pezzi.enumerated() {
                    v.append(RigaVista(id: r.id + "#\(k)", testo: (k == 0 && !titolo.isEmpty ? titolo : "") + pezzo, sezione: r.sezione, ora: nil))
                }
            } else {
                let ora: String = ArgomentoVista.formato.string(from: r.alle)
                let voci: [String] = Filo.voci(r.riga)
                if voci.count > 1 {
                    let titolo = Filo.testo(di: RigaFilo(id: r.id, titolo: r.titolo, riga: "", sezione: nil, alle: r.alle), in: a.nome)
                    for (k, voce) in voci.enumerated() {
                        v.append(RigaVista(id: r.id + "#\(k)", testo: (k == 0 && !titolo.isEmpty ? titolo : "") + voce, sezione: r.sezione,
                                           ora: k == 0 ? ora : nil, icona: k == 0 ? r.icona : nil))
                    }
                } else {
                    v.append(RigaVista(id: r.id, testo: Filo.testo(di: r, in: a.nome), sezione: r.sezione, ora: ora, icona: r.icona))
                }
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

/// 13.7 · i tre tasti delle tab (il signore, 21 nov 20:22: «in entrambe un tastino come quelli di Apple: uno per farla grande, uno
/// per chiuderla e uno per ridurla»): chiudi, riduci, apri, in gradazioni di ciano. Nella tab alta 16 punti, 8 fra l'uno e l'altro
/// (22 nov 00:32), con attorno un'area di tocco invisibile alta 30 e larga 24; nella tab bassa 11 punti, 4 fra l'uno e l'altro.
struct TastiTab: View {
    var lato: CGFloat = 16
    var spazio: CGFloat = 8
    /// L'area di tocco oltre il disegno: sopra e sotto, ai lati.
    var oltre: (v: CGFloat, h: CGFloat) = (v: 7, h: 4)
    let chiudi: () -> Void
    let riduci: () -> Void
    let apri: () -> Void

    var body: some View {
        HStack(spacing: spazio) {
            tasto("Chiudi la tab", azione: chiudi) { p in
                p.move(to: CGPoint(x: 3.6, y: 3.6)); p.addLine(to: CGPoint(x: 8.4, y: 8.4))
                p.move(to: CGPoint(x: 8.4, y: 3.6)); p.addLine(to: CGPoint(x: 3.6, y: 8.4))
            }
            tasto("Riduci la tab", azione: riduci) { p in
                p.move(to: CGPoint(x: 3.2, y: 6)); p.addLine(to: CGPoint(x: 8.8, y: 6))
            }
            tasto("Apri la tab intera", azione: apri) { p in
                p.move(to: CGPoint(x: 3.4, y: 8.6)); p.addLine(to: CGPoint(x: 8.6, y: 3.4))
                p.move(to: CGPoint(x: 5.2, y: 3.4)); p.addLine(to: CGPoint(x: 8.6, y: 3.4)); p.addLine(to: CGPoint(x: 8.6, y: 6.8))
            }
        }
    }

    private func tasto(_ nome: String, azione: @escaping () -> Void, segno: @escaping (inout Path) -> Void) -> some View {
        Button(action: azione) {
            let k = lato * 10 / 16 / 12                                   // il disegno (12 unità) è 10 punti nel tasto da 16
            Canvas { gc, size in
                var p = Path()
                segno(&p)
                let t = CGAffineTransform(translationX: (size.width - 12 * k) / 2, y: (size.height - 12 * k) / 2).scaledBy(x: k, y: k)
                gc.stroke(p.applying(t), with: .color(TintaTab.chiaro), style: StrokeStyle(lineWidth: 1.5 * k, lineCap: .round, lineJoin: .round))
            }
            .frame(width: lato, height: lato)
            .padding(EdgeInsets(top: oltre.v, leading: oltre.h, bottom: oltre.v, trailing: oltre.h))
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -oltre.v, leading: -oltre.h, bottom: -oltre.v, trailing: -oltre.h))
        }
        .buttonStyle(StileTastoTab(lato: lato))
        .accessibilityLabel(nome)
    }
}

/// Il tasto tondo delle tab: bordo ciano, fondo velato, un poco più acceso sotto il dito.
private struct StileTastoTab: ButtonStyle {
    let lato: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Olo.azzurro.opacity(configuration.isPressed ? 0.35 : 0.1))
                    .overlay(Circle().stroke(Olo.ciano.opacity(0.6), lineWidth: 1))
                    .shadow(color: Olo.azzurro.opacity(0.35), radius: 3)
                    .frame(width: lato, height: lato)
            }
    }
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
    /// 14 nov: il segno del passo del piano (○ ▸ ✓ ◇ ✕), disegnato in uno spazio fisso davanti al testo.
    var segno: String? = nil
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
/// 13.7: `specchio` è la tab bassa (PAGINE): il punto di luce in alto a SINISTRA e il filo che corre verso destra, il resto uguale.
enum CorniceFilo {
    /// 23 nov: quanto la tela della cornice esce dalla tab, così il bagliore del punto di luce non si taglia.
    static let sporge: CGFloat = 12
    /// La misura della tab dentro la tela più grande.
    static func dentro(_ tela: CGSize) -> CGSize {
        CGSize(width: max(0, tela.width - 2 * sporge), height: max(0, tela.height - 2 * sporge))
    }

    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double, fondo: Double = 0.93, specchio: Bool = false, caldo: Double = 0) {
        let W = Double(size.width), H = Double(size.height)
        let u0 = min(1, t / 0.5)
        gc.opacity = u0 < 1 ? (sin(u0 * 40) > -0.2 ? u0 : u0 * 0.3) : 1          // si accende sfarfallando
        let ax = specchio ? 6 : W - 6, ay = 6.0, u = Olo.liscia(t / 0.45), ly = 24.0, bx = 4.0, by = ly, bw = W - 8, bh = H - by - 3
        // il fondo (meno trasparente: la corona dietro si intuisce appena); 13.1: sopra una sezione segue il fuoco (vetro della PILA)
        // 13.9 (18) · issue 22: il fondo è vetro, si scalda con lo sfondo quando JARVIS pensa e parla (CaloreVetro)
        gc.fill(Path(CGRect(x: bx, y: by, width: bw * u, height: bh)), with: .color(CaloreVetro.fondo(caldo).opacity(fondo)))
        gc.blendMode = .plusLighter
        let pul = (t * 0.9).truncatingRemainder(dividingBy: 1)
        gc.stroke(Olo.ellisse(ax, ay, 2 + pul * 8, 2 + pul * 8), with: .color(Olo.ciano.opacity(0.7 * (1 - pul))), lineWidth: 1)
        Olo.alone(&gc, CGPoint(x: ax, y: ay), 10, 0.5)
        gc.fill(Olo.ellisse(ax, ay, 2.4, 2.4), with: .color(TintaTab.chiaro))
        var f = Path()
        f.move(to: CGPoint(x: ax, y: ay))
        if specchio {
            f.addLine(to: CGPoint(x: 24, y: ly - 4)); f.addLine(to: CGPoint(x: 24 + (W - 28) * u, y: ly - 4))
        } else {
            f.addLine(to: CGPoint(x: W - 24, y: ly - 4)); f.addLine(to: CGPoint(x: W - 24 - (W - 28) * u, y: ly - 4))
        }
        gc.stroke(f, with: .color(Olo.ciano.opacity(0.85)), style: Olo.tratto(1.1))
        // 23 nov (il signore: «lo stesso stile identico»): la luce e il bordo li mette il vetro unico (LuceOlografica); la cornice
        // tiene il punto di luce, il filo e gli angoli
        var ang = Path()
        let k = 9.0
        let angoli: [(x: Double, y: Double, sx: Double, sy: Double)] = [(x: bx, y: by, sx: 1, sy: 1), (x: bx + bw * u, y: by, sx: -1, sy: 1),
                                                                         (x: bx, y: by + bh, sx: 1, sy: -1), (x: bx + bw * u, y: by + bh, sx: -1, sy: -1)]
        for (px, py, sx, sy) in angoli {
            ang.move(to: CGPoint(x: px + sx * k, y: py)); ang.addLine(to: CGPoint(x: px, y: py)); ang.addLine(to: CGPoint(x: px, y: py + sy * k))
        }
        gc.stroke(ang, with: .color(TintaTab.chiaro.opacity(0.9)), style: Olo.tratto(1.5))
        // 23 nov (il signore: «senza l'animazione della riga che scende»): niente più riga di scansione
    }
}
#endif

/// 13.8 (4) (il signore, 22 nov 12:03, foto delle tab: «non sono trasparenti quasi per nulla: rendile come nel mockup, e usa la
/// trasparenza dinamica dove richiesta»). Nel mockup il vetro delle tab è solo sfocatura (10 punti, 20 sopra una sezione a fuoco)
/// più il fondo scuro al 60 % (55 % da piccola). Il «materiale» di iOS aggiunge una sua tinta scura sopra la sfocatura: con il
/// fondo al 60 % le tab diventavano quasi piene. Questo vetro tiene la sola sfocatura (la tinta di iOS si toglie) e il fondo scuro
/// resta quello del mockup. `forte`: sopra una sezione, a fuoco, sfoca di più (come il mockup).
/// 12:26 (il signore: «va tolta la tinta Apple da tutti i vetri»): è il vetro di tutta l'app (tab, tendina, PILA, Mail, Profiler).
struct VetroTab: UIViewRepresentable {
    var forte = false

    func makeUIView(context: Context) -> VetroSenzaTinta {
        let v = VetroSenzaTinta(effect: UIBlurEffect(style: forte ? .systemThinMaterialDark : .systemUltraThinMaterialDark))
        v.forte = forte
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: VetroSenzaTinta, context: Context) {
        guard v.forte != forte else { return }
        v.forte = forte
        v.effect = UIBlurEffect(style: forte ? .systemThinMaterialDark : .systemUltraThinMaterialDark)
        v.togliTinta()
    }
}

/// La vista di sfocatura senza la tinta di iOS: dopo ogni disegno toglie il colore ai livelli della tinta (tutto tranne quello
/// della sfocatura). Se iOS un giorno li chiamasse in un altro modo, il vetro resta semplicemente quello di iOS.
final class VetroSenzaTinta: UIVisualEffectView {
    var forte = false

    override func layoutSubviews() {
        super.layoutSubviews()
        togliTinta()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        togliTinta()
    }

    func togliTinta() {
        for s in subviews where !String(describing: type(of: s)).contains("Backdrop") {
            s.backgroundColor = .clear
        }
    }
}

/// La luce del vetro unico degli ologrammi (StileOlo), sopra il fondo scuro che mette chi la usa: la luce ciano dall'alto, il
/// bagliore dai bordi dentro, il bordo di luce e (solo CHIARO) l'alone fuori. 23 nov: niente più righe di scansione. Una vista
/// senza dati: si ridisegna solo se cambia la misura.
struct LuceOlografica<Forma: InsettableShape>: View {
    let forma: Forma
    var forza: Double = 1
    /// 13.9 (18): il bordo di luce (il campo di testo della chat tiene il suo contorno di sempre e non lo vuole).
    var conBordo = true

    var body: some View {
        let s = StileOlo.scelto
        let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
        ZStack {
            forma.fill(s.luce(forza))
            Canvas { gc, size in
                let w = size.width, h = size.height, b = min(s.aloneRaggio, w / 2, h / 2)
                let bordi: [(CGRect, CGPoint, CGPoint)] = [
                    (CGRect(x: 0, y: 0, width: w, height: b), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: b)),
                    (CGRect(x: 0, y: h - b, width: w, height: b), CGPoint(x: 0, y: h), CGPoint(x: 0, y: h - b)),
                    (CGRect(x: 0, y: 0, width: b, height: h), CGPoint(x: 0, y: 0), CGPoint(x: b, y: 0)),
                    (CGRect(x: w - b, y: 0, width: b, height: h), CGPoint(x: w, y: 0), CGPoint(x: w - b, y: 0)),
                ]
                for (r, da, a) in bordi {
                    gc.fill(Path(r), with: .linearGradient(Gradient(colors: [ciano.opacity(s.alone * forza), ciano.opacity(0)]), startPoint: da, endPoint: a))
                }
            }
            .clipShape(forma)
            if conBordo { forma.strokeBorder(s.bordo.opacity(forza), lineWidth: 1) }
        }
        .background {
            if s.fuori > 0 {
                forma.stroke(ciano.opacity(s.fuori * forza), lineWidth: 2)
                    .blur(radius: s.fuoriRaggio / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

extension LuceOlografica where Forma == Rectangle {
    /// Le tab: un rettangolo.
    init(forza: Double = 1) { self.init(forma: Rectangle(), forza: forza) }
}
