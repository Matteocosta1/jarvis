#if os(iOS)
import SwiftUI

// MARK: - La chat che si carica e si svuota, come le schede
// All'avvio, se la chat ha già dei messaggi: caricamento HUD (barra a linea unica, percentuale, voci), poi la chat
// si «stampa» dall'alto con la riga ciano e i caratteri si decodificano al passaggio. Chat vuota: niente.
// Pulendo la chat: settore per settore, dal basso, ogni messaggio si ritira verso sinistra dietro una riga verticale,
// i caratteri si sciolgono in simboli e in fondo una barra si svuota fino a 0%.

enum FaseChat: Equatable {
    case normale
    case nascosta                 // avvio in corso: la chat aspetta la fine delle icone
    case carica                   // caricamento HUD
    case stampa(Date)             // la chat si stampa dall'alto
    case svuota(Date)             // la chat si ritira verso sinistra
}

struct RegiaChat: Equatable {
    var fase: FaseChat = .normale
    var altezza: CGFloat = 1
    /// 13.9 (15) · chat TAB: quando è nata la cornice (l'inizio della stampa). nil = già nata (nessuna stampa: chat vuota all'avvio).
    var nata: Date? = nil
}

private struct ChiaveRegiaChat: EnvironmentKey { static let defaultValue = RegiaChat() }
extension EnvironmentValues {
    var regiaChat: RegiaChat {
        get { self[ChiaveRegiaChat.self] }
        set { self[ChiaveRegiaChat.self] = newValue }
    }
}

/// I numeri dell'avvio, in un posto solo (20 ott: +60%, SINCRO 110 ms, scelti dal signore sul mock).
enum Avvio {
    /// Quanto è più svelto l'avvio rispetto all'originale: la traccia «avvio» è rimontata a questa velocità.
    static let velocita = 1.6
    /// Quando la musica d'avvio chiude (secondi, tempo di base): lì arriva «SISTEMI IN LINEA».
    static let chiusuraMusica = 4.35
    /// Da Interprete in poi (la raffica finale) ogni icona parte prima del suo colpo, così la molla arriva sul beep.
    static let anticipoCoda = 0.110
    /// La molla delle icone della coda: la stessa, più svelta.
    static let mollaCoda = 0.12
    /// L'indice della prima icona della coda: da Ricordi (tutte le icone dello scarico).
    static func inizioCoda(_ nomi: [String]) -> Int { nomi.firstIndex(of: "Ricordi") ?? nomi.count }
    /// La partitura dell'iPhone (secondi a velocità normale, 27 icone dalla build 23, con SATELLITE): è quella con cui è montata
    /// «avvio». Le prime 16 al passo di sempre (SENSI chiude sul colpo forte di 2,5 s); STRUMENTI e INTELLIGENCE (11 icone,
    /// prima 10) distribuite su tutto lo SCARICO della musica, 2,885 → 3,724 s; Bea sull'ultimo colpo (scelto sul mock, «Dopo»).
    static let colpi: [Double] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 1.01, 1.16, 1.31, 1.46, 1.61, 1.87, 2.02, 2.17, 2.32, 2.47,
                                  2.885, 2.969, 3.053, 3.137, 3.220, 3.304, 3.388, 3.472, 3.556, 3.640, 3.724]
    /// 12.0 (14) · l'avvio è JARVIS II (versione SFUMATA, scelta dal signore il 13 nov): le icone in alto non arrivano più con la corona
    /// ma coi suoni di caricamento del finale, una alla volta da Social a Impostazioni, ognuna su un suono. Secondi dall'inizio del file
    /// (il file non è accelerato: niente ÷ velocità), misurati sull'attacco: click d'inizio · tick · bip · bip · bip · bip (passo ~0,5 s,
    /// mezzo ciclo dei bip). Il bagliore del titolo arriva con l'ultima. Stessi tempi del mockup (`TESTA_VOCE`).
    static let testaVoce: [Double] = [11.738, 12.287, 12.821, 13.334, 13.821, 14.306]
}

enum TempiChat {
    // il caricamento all'avvio va alla velocità dell'avvio (+60%): tutto in proporzione, suono «chatcarica» compreso
    static let carica = 1.0 / Avvio.velocita           // il caricamento HUD (un secondo a velocità normale)
    static let stampa = 1.1 / Avvio.velocita           // la riga che scende
    static let decodifica = 0.42 / Avvio.velocita      // ogni riga torna leggibile
    static let svuotaRiga = 0.38      // quanto ci mette un messaggio a ritirarsi
    static let svuotaScala = 0.75     // ritardo fra il messaggio più in basso e quello più in alto
    static var totaleSvuota: Double { svuotaScala + svuotaRiga + 0.25 }

    /// Quando la riga di stampa passa sopra un messaggio (secondi dall'inizio della stampa).
    static func passaggioStampa(alto: CGFloat, altezza: CGFloat) -> Double {
        let r = Double(min(1, max(0, alto / max(altezza, 1))))
        return stampa * (1 - pow(1 - r, 1 / 2.2))
    }
    /// Quando un messaggio comincia a ritirarsi: prima quelli in basso, poi a salire.
    static func avvioSvuota(fondo: CGFloat, altezza: CGFloat) -> Double {
        svuotaScala * (1 - Double(min(1, max(0, fondo / max(altezza, 1)))))
    }
    /// Curva della stampa (veloce all'inizio, rallenta in fondo).
    static func curvaStampa(_ p: Double) -> Double { 1 - pow(1 - min(1, max(0, p)), 2.2) }
    static func morbido(_ p: Double) -> Double { let x = min(1, max(0, p)); return x * x * (3 - 2 * x) }
}

/// I caratteri «da computer» che prendono il posto del testo mentre carica o si cancella.
enum Glifi {
    static let insieme = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789#%&*+=<>/\\|▪▫░▒")
    /// `quanto`: 0 = testo vero, 1 = tutti simboli.
    static func rimescola(_ s: String, _ quanto: Double) -> String {
        guard quanto > 0 else { return s }
        return String(s.map { c in
            (c == " " || c == "\n" || Double.random(in: 0..<1) > quanto) ? c : (insieme.randomElement() ?? c)
        })
    }
}

/// Avvolge una riga della chat: decide quanto è «rimescolata» e, nello svuotamento, quanto si è ritirata verso sinistra.
struct RigaAnimata<Contenuto: View>: View {
    @Environment(\.regiaChat) private var regia
    @State private var cornice: CGRect = .zero
    let contenuto: (Double) -> Contenuto          // riceve quanto rimescolare il testo (0…1)

    var body: some View {
        Group {
            switch regia.fase {
            case .normale:
                contenuto(0)
            case .nascosta, .carica:
                contenuto(1)
            case .stampa(let t0):
                TimelineView(.animation) { ctx in
                    let passa = TempiChat.passaggioStampa(alto: cornice.minY, altezza: regia.altezza)
                    let t = ctx.date.timeIntervalSince(t0) - passa
                    contenuto(t < 0 ? 1 : max(0, 1 - t / TempiChat.decodifica))
                }
            case .svuota(let t0):
                TimelineView(.animation) { ctx in
                    let parte = TempiChat.avvioSvuota(fondo: cornice.maxY, altezza: regia.altezza)
                    let p = min(1, max(0, (ctx.date.timeIntervalSince(t0) - parte) / TempiChat.svuotaRiga))
                    let e = TempiChat.morbido(p)
                    contenuto(min(1, p * 2.2))
                        .mask(alignment: .leading) {
                            GeometryReader { g in Rectangle().frame(width: g.size.width * (1 - e)) }
                        }
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Rectangle().fill(Color.ciano).frame(width: 2).frame(maxHeight: .infinity)
                                    .shadow(color: .ciano, radius: 6)
                                    .offset(x: g.size.width * (1 - e) - 1)
                                    .opacity(p > 0 && p < 1 ? 1 : 0)
                            }
                        }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("chat")) } action: { cornice = $0 }
    }
}

/// Gli effetti sulla chat intera: nascosta all'avvio, caricamento HUD, stampa con la riga ciano, barra dello svuotamento.
struct EffettiChat: ViewModifier {
    let regia: RegiaChat

    @ViewBuilder func body(content: Content) -> some View {
        switch regia.fase {
        case .normale:
            content
        case .nascosta:
            content.opacity(0)
        case .carica:
            content.opacity(0)
                .overlay { CaricamentoChat().transition(.opacity).allowsHitTesting(false) }
        case .stampa(let t0):
            TimelineView(.animation) { ctx in
                let e = TempiChat.curvaStampa(ctx.date.timeIntervalSince(t0) / TempiChat.stampa)
                content
                    .mask(alignment: .top) {
                        GeometryReader { g in
                            VStack(spacing: 0) { Rectangle().frame(height: g.size.height * e); Spacer(minLength: 0) }
                        }
                    }
                    .overlay(alignment: .top) {
                        GeometryReader { g in
                            Rectangle().fill(Color.ciano).frame(height: 2)
                                .shadow(color: .ciano, radius: 6)
                                .offset(y: g.size.height * e)
                                .opacity(e < 1 ? 1 : 0)
                        }
                        .allowsHitTesting(false)
                    }
            }
        case .svuota(let t0):
            content
                .allowsHitTesting(false)
                .overlay(alignment: .bottom) { BarraSvuota(inizio: t0) }
        }
    }
}

/// Il caricamento della chat: due anelli piccoli, la barra che si riempie in una linea sola, la percentuale e le voci.
struct CaricamentoChat: View {
    private let voci = ["COLLEGAMENTO AL CERVELLO", "RECUPERO CONVERSAZIONE", "DECODIFICA"]
    @State private var inizio = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let passato = ctx.date.timeIntervalSince(inizio)
            let av = min(0.92, 1 - exp(-passato / (0.6 / Avvio.velocita)))   // in proporzione all'avvio
            let voce = min(voci.count - 1, Int(av * Double(voci.count) / 0.92))
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.ciano.opacity(0.18), lineWidth: 1).frame(width: 64, height: 64)
                    Circle().trim(from: 0, to: 0.28).stroke(Color.ciano, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 64, height: 64).rotationEffect(.radians(t * 2.2))
                    Circle().trim(from: 0, to: 0.18).stroke(Color.ciano.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 48, height: 48).rotationEffect(.radians(-t * 3.1))
                    Text("CHAT").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
                }
                .shadow(color: .ciano.opacity(0.5), radius: 12)
                VStack(spacing: 6) {
                    LineaProgresso(valore: av).frame(width: 190)
                    Text("\(Int(av * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(Color.ciano)
                }
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(voci.enumerated()), id: \.offset) { k, s in
                        HStack(spacing: 7) {
                            Rectangle().frame(width: 5, height: 5)
                            Text(s).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        }
                        .foregroundStyle(Color.ciano.opacity(k <= voce ? 0.95 : 0.3))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { inizio = Date() }
    }
}

/// La barra in fondo mentre la chat si svuota: da 100% a 0%, con le voci della pulizia.
struct BarraSvuota: View {
    let inizio: Date
    private let voci = ["ARCHIVIO CONVERSAZIONE", "PULIZIA SCHERMO", "MEMORIA LIBERA"]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil)) { ctx in
            let q = min(1, ctx.date.timeIntervalSince(inizio) / (TempiChat.svuotaScala + TempiChat.svuotaRiga))
            VStack(spacing: 6) {
                HStack {
                    Text(voci[min(2, Int(q * 3))])
                    Spacer()
                    Text("\(Int(((1 - q) * 100).rounded()))%").monospacedDigit()
                }
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Color.ciano)
                LineaProgresso(valore: 1 - q)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(LinearGradient(colors: [.clear, Color.fondo], startPoint: .top, endPoint: .center))
        }
        .allowsHitTesting(false)
    }
}

/// Barra di avanzamento in una linea sola, senza tacche.
struct LineaProgresso: View {
    let valore: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ciano.opacity(0.15))
                Capsule().fill(Color.ciano).frame(width: g.size.width * min(1, max(0, valore)))
                    .shadow(color: .ciano, radius: 4)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - 13.9 (15) · la chat TAB (scelta dal signore il 27 nov, mockup «JARVIS Telefono» v7 / Mark XIII v121)
// La chat come le due tab piccole (PAGINE e FILO): il loro vetro (13.9 (18): identico, bordo di luce compreso), senza sfocatura di Apple; il punto di luce che
// pulsa in alto a sinistra, il filo che corre sopra la scheda, i quattro angoli di luce. Nasce sul suono della chat, quando parte
// la stampa (stessi tempi di prima: nessun tempo in più); durante il cerchio di caricamento non c'è. Le scritte scorrono dentro.

enum CorniceChat {
    /// Dove sta la scheda dentro lo spazio della chat (inset 26 · 12 · 6 · 12 del mockup).
    static let scheda = EdgeInsets(top: 26, leading: 12, bottom: 6, trailing: 12)
    /// Il margine delle scritte dentro la scheda (16 · 18 · 16 · 18 del mockup).
    static let margine = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// Quanto la tela esce dallo spazio della chat, così il punto di luce e il suo anello non si tagliano (come FILO).
    static let sporge: CGFloat = 12
    static let luce = Color(red: 79 / 255, green: 227 / 255, blue: 1)          // #4fe3ff
    static let chiaro = Color(red: 191 / 255, green: 246 / 255, blue: 1)       // #bff6ff

    /// 13.9 (18) (il signore, 28 nov 01:15, foto con FILO accanto: «identica alla tab come trasparenza e design»): il fondo del
    /// vetro è quello delle tab a riposo (StileOlo SCURO, 62 %); sopra la stessa luce olografica (LuceOlografica).
    static let fondo = Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255)

    /// La curva con cui la scheda si apre da sinistra (1 − (1 − u)³).
    static func apre(_ t: Double) -> Double { let u = min(1, max(0, t / 0.45)); return 1 - pow(1 - u, 3) }

    /// Punto di luce, filo e angoli (la tela del mockup). `size` è lo spazio della chat, senza la parte che sporge.
    static func disegna(_ gc: inout GraphicsContext, _ size: CGSize, t: Double) {
        let W = Double(size.width), H = Double(size.height)
        let u0 = min(1, t / 0.5)
        gc.opacity = u0 < 1 ? (sin(u0 * 40) > -0.2 ? u0 : u0 * 0.3) : 1           // si accende sfarfallando
        let u = apre(t)
        let ax = 10.0, ay = 8.0, ly = 26.0, bx = 12.0, by = ly, bw = W - 24, bh = H - by - 6
        let pul = (t * 0.9).truncatingRemainder(dividingBy: 1)
        gc.stroke(Olo.ellisse(ax, ay, 2 + pul * 8, 2 + pul * 8), with: .color(luce.opacity(0.7 * (1 - pul))), lineWidth: 1)
        Olo.alone(&gc, CGPoint(x: ax, y: ay), 10, 0.5, luce)
        gc.fill(Olo.ellisse(ax, ay, 2.4, 2.4), with: .color(chiaro))
        var filo = Path()
        filo.move(to: CGPoint(x: ax, y: ay))
        filo.addLine(to: CGPoint(x: 28, y: ly - 4))
        filo.addLine(to: CGPoint(x: 28 + max(0, W - 40) * u, y: ly - 4))
        gc.stroke(filo, with: .color(luce.opacity(0.85)), lineWidth: 1.1)
        var ang = Path()
        let k = 9.0
        let angoli: [(x: Double, y: Double, sx: Double, sy: Double)] = [(x: bx, y: by, sx: 1, sy: 1), (x: bx + bw * u, y: by, sx: -1, sy: 1),
                                                                         (x: bx, y: by + bh, sx: 1, sy: -1), (x: bx + bw * u, y: by + bh, sx: -1, sy: -1)]
        for (px, py, sx, sy) in angoli {
            ang.move(to: CGPoint(x: px + sx * k, y: py)); ang.addLine(to: CGPoint(x: px, y: py)); ang.addLine(to: CGPoint(x: px, y: py + sy * k))
        }
        gc.stroke(ang, with: .color(chiaro.opacity(0.9)), lineWidth: 1.5)
    }
}

/// Il vetro e la cornice dietro le scritte. Non c'è mentre la chat aspetta l'avvio e durante il cerchio di caricamento.
/// `fermo`: una sezione copre tutto, il punto di luce smette di pulsare (niente lavoro inutile).
struct SfondoChatTab: View {
    let regia: RegiaChat
    var fermo = false

    var body: some View {
        switch regia.fase {
        case .nascosta, .carica:
            Color.clear
        case .normale, .stampa, .svuota:
            TimelineView(.animation(minimumInterval: nil, paused: fermo)) { tl in
                // nata all'inizio della stampa; senza stampa è già nata (il tempo grande tiene il pulsare continuo)
                let t = regia.nata.map { tl.date.timeIntervalSince($0) } ?? tl.date.timeIntervalSinceReferenceDate
                let u = CorniceChat.apre(t)
                ZStack {
                    // il vetro delle tab (lo stesso di FILO e PAGINE, senza sfocatura di Apple); si apre da sinistra
                    ZStack {
                        Rectangle().fill(CorniceChat.fondo.opacity(TintaTab.vetroPiccola))
                        LuceOlografica()                                            // luce dall'alto, bordo di luce, bagliore dai bordi
                    }
                        .mask(alignment: .leading) {
                            GeometryReader { g in Rectangle().frame(width: g.size.width * u) }
                        }
                        .padding(CorniceChat.scheda)
                    Canvas(rendersAsynchronously: false) { gc, size in
                        gc.translateBy(x: CorniceChat.sporge, y: CorniceChat.sporge)
                        CorniceChat.disegna(&gc, CGSize(width: max(0, size.width - 2 * CorniceChat.sporge),
                                                        height: max(0, size.height - 2 * CorniceChat.sporge)), t: t)
                    }
                    .padding(-CorniceChat.sporge)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 13.9 (16) · lo swipe verso sinistra toglie un messaggio dallo schermo (il signore, 28 nov 00:21–00:27: «senza X», «senza
/// click», «un aiuto in più nell'eliminare i messaggi, ma solo esteticamente»: il cervello lo legge ancora). Il messaggio segue il
/// dito; lasciato oltre il 40 % della sua larghezza esce a sinistra col suono (e il tocco) della tab mandata via e lo spazio si
/// chiude; prima di lì torna a posto, in silenzio. Il gesto si decide al primo movimento, come le righe di FILO: chiaramente di
/// lato e verso sinistra (il doppio del verticale) scivola il messaggio; altrimenti la chat scorre come sempre.
struct ScivolaVia: ViewModifier {
    let attivo: Bool                      // solo a chat ferma (non mentre si carica, si stampa o si svuota)
    let via: () -> Void
    @State private var dx: CGFloat = 0
    @State private var asse: Bool?        // true: di lato verso sinistra · false: in su o in giù (deciso al primo movimento)
    @State private var seguito = false    // in questo gesto il messaggio ha seguito il dito
    @State private var esce = false
    @State private var larghezza: CGFloat = 1
    @GestureState private var tocca = false

    func body(content: Content) -> some View {
        content
            // 13.9 (17) (il signore, 01:13: «posso cancellare solo i messaggi di JARVIS e non i miei»): una riga corta (le sue
            // risposte brevi) era larga solo quanto il testo e lo spazio a destra non si poteva prendere col dito. Ora ogni
            // messaggio occupa tutta la riga, come nel mockup, e si prende ovunque
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .offset(x: dx)
            .opacity(esce ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { larghezza = max(1, $0) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)                              // come le righe di FILO: lo scorrimento resta libero
                    .updating($tocca) { _, stato, _ in stato = true }
                    .onChanged { v in
                        guard attivo, !esce else { return }
                        if asse == nil {
                            asse = v.translation.width < 0 && -v.translation.width > abs(v.translation.height) * 2
                            seguito = false
                        }
                        guard asse == true else { return }
                        seguito = true
                        dx = min(0, v.translation.width)
                    }
                    .onEnded { v in
                        // deciso da quello che il messaggio ha fatto (non da `asse`, che il fine del gesto azzera)
                        guard seguito, attivo, !esce else { return }
                        seguito = false
                        if -v.translation.width > larghezza * 0.4 { manda() }
                        else { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { dx = 0 } }
                    }
            )
            // finito o interrotto (lo scorrimento si è preso il dito): si decide di nuovo al prossimo; se non è uscito torna a posto
            .onChange(of: tocca) { _, v in
                guard !v else { return }
                asse = nil
                if !esce, dx != 0 { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { dx = 0 } }
            }
            .onChange(of: attivo) { _, a in if !a, !esce { dx = 0 } }
            .accessibilityAction(named: Text("Togli dallo schermo")) { if attivo, !esce { manda() } }
    }

    private func manda() {
        esce = true
        Suoni.filoVia()                                                    // suono e tocco insieme (Aptica.tabVia), come FILO
        withAnimation(.timingCurve(0.4, 0, 1, 1, duration: 0.22)) {
            dx = -larghezza * 1.1
        } completion: {
            via()
        }
    }
}

/// Le scritte sfumano in basso (16 punti) e, solo quando la chat è scorsa in su, anche in alto (22 punti). Durante la stampa
/// niente sfumature: la maschera è quella della riga che scende (come il mockup).
struct SfumaChat: ViewModifier {
    let attiva: Bool
    @State private var sopra = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 18.0, *) {
                content
                    .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 2 } action: { _, v in sopra = v }
            } else {
                content
            }
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [attiva && sopra ? .clear : .black, .black], startPoint: .top, endPoint: .bottom).frame(height: 22)
                Color.black
                LinearGradient(colors: [.black, attiva ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: 16)
            }
        }
    }
}
#endif
