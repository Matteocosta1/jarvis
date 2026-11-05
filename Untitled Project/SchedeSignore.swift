#if os(iOS)
import SwiftUI
import Charts
import HealthKit

// MARK: - I pezzi comuni a tutte le schede

/// Una scheda di JARVIS: fondo scuro, testata HUD con l'icona viva, «Chiudi» in alto.
/// All'apertura: il suono dell'ascolto e il caricamento da HUD (anelli che girano, riga di scansione, lettura dei sistemi);
/// quando i dati sono pronti (`pronto`): il suono di «pronto» e il contenuto che appare dall'alto, come su un visore.
struct CorniceScheda<Contenuto: View>: View {
    let titolo: String
    let sottotitolo: String
    let icona: String
    let tinta: Color
    var pronto = true
    var fotocamera = false          // Scanner: quando è pronta, il suono delle sezioni con fotocamera al posto di «pronta»
    /// 26 ott notte (il signore, «JARVIS Music»): la testata come Studio e Social, «J.A.R.V.I.S.» e sotto il nome della sezione.
    var marchio = false
    @ViewBuilder let contenuto: () -> Contenuto
    @Environment(\.chiudiOVia) private var chiudi
    @State private var mostrato = false
    @State private var stampa: CGFloat = 0           // quanto della scheda è già «stampato» (0 → 1)
    @State private var apertaDa = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fondo.ignoresSafeArea()
                GrigliaSfumata()
                RadialGradient(colors: [tinta.opacity(0.16), .clear], center: .top, startRadius: 0, endRadius: 420)
                    .ignoresSafeArea()
                // 4 nov (regola fissa): la scheda con la fotocamera (Scanner) si chiude con la X nel cerchio (vedi tastoX).
                // 5 nov (il signore: «se scorro in basso, in ogni sezione si vede quella barra grigia col Chiudi»): «Chiudi» non è
                // più nella barra di iOS, che scorrendo si vestiva di grigio, ma in una riga sua sopra la pagina, come nel mockup:
                // la pagina scorre sotto la riga e la riga resta trasparente.
                VStack(spacing: 0) {
                    if fotocamera { tastoX } else if !marchio { BarraChiudi(tinta: tinta) { chiudi() } }
                    pagina
                }
                if !mostrato {
                    CaricamentoHUD(titolo: titolo, tinta: tinta)
                        .padding(.top, 120)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            // marchio: «Chiudi» è nella testata, come Studio e Social; fotocamera: la X nel cerchio; le altre: BarraChiudi
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { apertaDa = Date(); Suoni.schedaApre() }
        .task(id: pronto) {
            guard pronto, !mostrato else { return }
            // il caricamento si vede almeno per un attimo, anche se i dati arrivano subito (5 nov: 0,45 s, uguale ovunque)
            let resta = Apertura.caricamento - Date().timeIntervalSince(apertaDa)
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            if fotocamera { Suoni.schedaPronta(soloSfuma: true); Suoni.aperturaCamera() } else { Suoni.schedaPronta() }
            mostrato = true
            withAnimation(.easeOut(duration: Apertura.stampa)) { stampa = 1 }
        }
    }

    /// La pagina che scorre: la testata e il contenuto, che si «stampa» dall'alto.
    private var pagina: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if marchio {
                    // come la testata di Studio e Social: icona, J.A.R.V.I.S., la sezione sotto e «Chiudi» sulla stessa riga
                    HStack(alignment: .center) {
                        TestataScheda(titolo: titolo, sottotitolo: mostrato ? sottotitolo : TestiCaricamento.di(titolo), icona: icona, tinta: tinta, marchio: true)
                        Button("Chiudi") { chiudi() }.font(.system(size: 16, weight: .semibold)).tint(tinta)
                    }
                } else {
                    TestataScheda(titolo: titolo, sottotitolo: mostrato ? sottotitolo : TestiCaricamento.di(titolo), icona: icona, tinta: tinta)
                }
                if mostrato {
                    contenuto()
                        .mask(alignment: .top) {
                            // la scheda si «stampa» dall'alto, riga per riga
                            GeometryReader { g in
                                VStack(spacing: 0) {
                                    Rectangle().frame(height: g.size.height * stampa)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .overlay(alignment: .top) {
                            GeometryReader { g in
                                Rectangle().fill(tinta).frame(height: 2)
                                    .shadow(color: tinta, radius: 6)
                                    .offset(y: g.size.height * stampa)
                                    .opacity(stampa < 1 ? 1 : 0)
                            }
                        }
                }
            }
            .padding(16)
            .padding(.bottom, 30)
            // 26 ott sera (video 21:29, SATELLITE): trascinando la mappa la pagina scorreva anche di lato. La pagina è
            // larga esattamente quanto lo schermo e scorre solo in verticale, come nel mockup.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .scrollDismissesKeyboard(.interactively)
    }

    /// 4 nov (regola fissa): la scheda con la fotocamera (Scanner) si chiude con la X nel cerchio, nello stesso posto del
    /// «Chiudi» delle altre (come nel mockup: lo stesso tasto, a cerchio). Fuori dalla barra di iOS, che la vestirebbe di vetro.
    private var tastoX: some View {
        HStack {
            Spacer()
            Button { Suoni.tocco(); chiudi() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tinta).frame(width: 44, height: 44)
                    .overlay(Circle().stroke(tinta.opacity(0.5), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(StileStark())
            .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// La testata: icona dentro un anello che gira, nome della scheda in grande, una riga di stato.
struct TestataScheda: View {
    let titolo: String
    let sottotitolo: String
    let icona: String
    let tinta: Color
    /// Come Studio e Social: «J.A.R.V.I.S.» in ciano, sotto il nome della sezione (vedi CorniceScheda.marchio).
    var marchio = false
    /// Sentinella: anche il titolo del colore della sezione (verde in visione notturna), non bianco.
    var titoloColorato = false
    /// 4 nov: la sezione è dietro (MARK XI, invisibile o pagina olografica non davanti): l'arco si ferma, davanti riparte.
    @Environment(\.sezioneDietro) private var dietro

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tinta.opacity(0.25), lineWidth: 1)
                // 26 ott sera (SATELLITE, foto del signore 22:07: un mezzo cerchio che gira per la pagina): l'arco girava con
                // un'animazione infinita accesa all'apertura; se nello stesso istante la pagina si spostava (la salita, la barra
                // in alto) iOS ripeteva all'infinito anche lo spostamento e l'arco vagava fuori dall'anello. Ora l'angolo lo dà
                // l'orologio: stesso arco, un giro ogni 3 secondi, sempre centrato sull'icona, in tutte le schede.
                TimelineView(.animation(minimumInterval: nil, paused: dietro)) { t in
                    Circle().trim(from: 0, to: 0.3).stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360))
                }
                if icona == "satellite" {                   // build 23: disegnata come nel mockup
                    IconaSatellite(lato: 17).font(.system(size: 16, weight: .medium)).foregroundStyle(tinta)
                } else if icona == "vinile" {               // build 23, MUSICA: il vinile olografico del mockup (non è un simbolo di sistema)
                    IconaVinile().frame(width: 17, height: 17).foregroundStyle(tinta)
                } else {
                    Image(systemName: icona)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tinta)
                }
            }
            .frame(width: 40, height: 40)          // 26 ott notte (il signore): le icone animate delle sezioni più piccole (prima 52)
            .shadow(color: tinta.opacity(0.5), radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                if marchio {
                    Text("J.A.R.V.I.S.")
                        .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                        .foregroundStyle(tinta)
                } else {
                    Text(titolo.uppercased())
                        .font(.system(size: 18, weight: .bold, design: .monospaced)).tracking(3)   // 27 ott: nome della sezione più piccolo (prima 24)
                        .foregroundStyle(titoloColorato ? tinta : .white)
                }
                // 27 ott (il signore): la scritta sotto il nome arriva dal lato in trasparenza (TestoCodice)
                TestoCodice(testo: sottotitolo.uppercased())
                    .font(.system(size: marchio ? 10.5 : 9, weight: marchio ? .bold : .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(tinta)   // 27 ott: in Sound (come Studio e Social) la dicitura più marcata, senza bagliore
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }
}

/// 5 nov · «Chiudi» delle sezioni senza fotocamera, in una riga sua sopra la pagina (al posto della barra di iOS, che scorrendo
/// diventava grigia): stesso posto, stessa misura e stessa scritta di prima; la pagina scorre sotto e la riga resta trasparente.
struct BarraChiudi: View {
    let tinta: Color
    /// «Chiudi»; nelle Impostazioni «Fatto», come prima.
    var testo = "Chiudi"
    let chiudi: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(testo) { chiudi() }
                .font(.system(size: 17, weight: .semibold))
                .tint(tinta)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// Le sezioni con una pagina che scorre propria (Vitals, Confidente, Ricordi, Bea, Diario…): la riga di «Chiudi» sopra la
/// pagina e la barra di iOS nascosta (vedi BarraChiudi).
struct ConBarraChiudi: ViewModifier {
    let tinta: Color
    var testo = "Chiudi"
    let chiudi: () -> Void

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            BarraChiudi(tinta: tinta, testo: testo, chiudi: chiudi)
            content
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Il caricamento da HUD: gli angoli del mirino, dentro gli anelli che girano in senso opposto con la riga di scansione,
/// sotto la barra a segmenti con la percentuale e le voci dei «sistemi» che si accendono una alla volta.
struct CaricamentoHUD: View {
    let titolo: String
    let tinta: Color
    // 27 ott (il signore): la prima voce è quella della sezione (TestiCaricamento), poi i sistemi di sempre
    private var sistemi: [String] { [TestiCaricamento.di(titolo).uppercased(), "LETTURA SENSORI", "ANALISI", "COMPILAZIONE SCHEDA"] }
    @State private var inizio = Date()
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: dietro si ferma (MARK XI)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: dietro)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let passato = ctx.date.timeIntervalSince(inizio)
            let avanzamento = min(0.92, 1 - exp(-passato / 1.6))          // sale svelto, poi aspetta i dati
            let voce = min(sistemi.count - 1, Int(avanzamento * Double(sistemi.count) / 0.92))
            VStack(spacing: 18) {
                ZStack {
                    // gli angoli del mirino
                    Path { p in
                        let l: CGFloat = 26, w: CGFloat = 200, h: CGFloat = 160
                        for (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                            p.move(to: CGPoint(x: x, y: y + dy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
                        }
                    }
                    .stroke(tinta, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 200, height: 160)
                    // gli anelli
                    Circle().stroke(tinta.opacity(0.15), lineWidth: 1).frame(width: 110, height: 110)
                    Circle().trim(from: 0, to: 0.28).stroke(tinta, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 110, height: 110).rotationEffect(.radians(t * 2.2))
                    Circle().trim(from: 0, to: 0.18).stroke(tinta.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 84, height: 84).rotationEffect(.radians(-t * 3.1))
                    Circle().trim(from: 0, to: 0.5).stroke(tinta.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        .frame(width: 60, height: 60).rotationEffect(.radians(t * 1.4))
                    Text(titolo.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2)
                        .foregroundStyle(tinta)
                    // riga di scansione
                    Rectangle().fill(tinta.opacity(0.5)).frame(width: 110, height: 1.5)
                        .offset(y: CGFloat(sin(t * 2.4)) * 53)
                        .mask(Circle().frame(width: 110, height: 110))
                }
                .shadow(color: tinta.opacity(0.5), radius: 14)
                // la barra a segmenti con la percentuale
                VStack(spacing: 6) {
                    HStack(spacing: 3) {
                        ForEach(0..<24, id: \.self) { k in
                            Rectangle().fill(tinta.opacity(Double(k) < avanzamento * 24 ? 1 : 0.18)).frame(width: 7, height: 8)
                        }
                    }
                    Text("\(Int(avanzamento * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(tinta)
                        .contentTransition(.numericText())
                }
                // i sistemi
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(sistemi.enumerated()), id: \.offset) { k, s in
                        let acceso = k <= voce
                        HStack(spacing: 8) {
                            Rectangle().fill(tinta.opacity(acceso ? 1 : 0.2)).frame(width: 6, height: 6)
                            Text(s).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                                .foregroundStyle(tinta.opacity(acceso ? 0.95 : 0.3))
                            if k == voce {
                                Text(String(repeating: "▪", count: Int(t * 6) % 4)).font(.system(size: 8)).foregroundStyle(tinta)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { inizio = Date() }
    }
}

/// 5 nov (il signore: «apertura delle sezioni da circa 1 s a 0,4-0,5 s, uguale ovunque», come il mockup v260): i tempi di
/// apertura di tutte le sezioni in un posto solo. 5 nov pomeriggio (punti 1 e 2 approvati: «le app si aprano nel modo più veloce
/// possibile»): caricamento 0,28 s, stampa 0,32 s, la copertura del caricamento sfuma in 0,25 s. Il caricamento è un minimo: se i
/// dati del cervello arrivano dopo, la scheda li aspetta (non si mostrano mai dati vecchi).
enum Apertura {
    /// Il caricamento HUD (prima 0,45 s; ancora prima 1,1 s nelle sezioni dal vivo, 0,9 s nelle schede).
    static let caricamento = 0.28
    /// La pagina che si «stampa» dall'alto (prima 0,5 s; ancora prima 0,9 s).
    static let stampa = 0.32
    /// La copertura del caricamento che sfuma sulla sezione (prima 0,4 s).
    static let dissolvenza = 0.25
    /// L'ascolto dei comandi a voce dentro le sezioni: cambia la sessione audio, quindi parte a suoni d'apertura finiti
    /// (il caricamento più il clic di fine caricamento, 0,7 s; prima 1,8 s).
    static let orecchio = caricamento + 0.7
}

/// L'apertura da HUD per le sezioni che non caricano dati dal cervello (Sentinella, Wiretap, Interprete, Allenatore, Browser…)
/// e per quelle che hanno già la loro pagina (Vitals, Ricordi, Confidente): un attimo di caricamento con i suoni, poi la sezione.
struct AperturaHUD: ViewModifier {
    let titolo: String
    var durata = Apertura.caricamento
    var fotocamera = false          // sezioni con fotocamera: a fine caricamento il clic «aperturacamera» al posto di «pronta»
    var soloSfuma = false           // 26 ott notte (Occhi, Cucina): a fine caricamento sfuma e basta, il suono lo fa la sezione
    @State private var coperto = true

    func body(content: Content) -> some View {
        content
            .overlay {
                if coperto {
                    ZStack {
                        Color.fondo.ignoresSafeArea()
                        CaricamentoHUD(titolo: titolo, tinta: .ciano)
                    }
                    .transition(.opacity)
                }
            }
            .onAppear { Suoni.schedaApre() }
            .task {
                try? await Task.sleep(for: .seconds(durata))
                if soloSfuma { Suoni.schedaPronta(soloSfuma: true) }
                else if fotocamera { Suoni.schedaPronta(soloSfuma: true); Suoni.aperturaCamera() } else { Suoni.schedaPronta() }
                withAnimation(.easeOut(duration: Apertura.dissolvenza)) { coperto = false }
            }
    }
}

extension View {
    /// Apre la sezione con il caricamento HUD di JARVIS.
    func aperturaHUD(_ titolo: String, fotocamera: Bool = false, soloSfuma: Bool = false) -> some View {
        modifier(AperturaHUD(titolo: titolo, fotocamera: fotocamera, soloSfuma: soloSfuma))
    }
}

/// Un riquadro con bordo sottile del colore della scheda.
struct Pannello<Contenuto: View>: View {
    var titolo: String? = nil
    let tinta: Color
    var olografico = false           // 27 ott: gli angoli del visore olografico (Diario, come Browser e Confidente)
    @ViewBuilder let contenuto: () -> Contenuto

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let titolo {
                Text(titolo).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            }
            contenuto()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinta.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tinta.opacity(0.22), lineWidth: 1))
        .overlay { if olografico { AngoliOlo(tinta: tinta).padding(-1).allowsHitTesting(false) } }
    }
}

/// Un numero grande con la sua etichetta.
struct Valore: View {
    let titolo: String
    let valore: String
    var sotto: String? = nil
    let tinta: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(tinta.opacity(0.85))
            Text(valore).font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            if let sotto { Text(sotto).font(.system(size: 10)).foregroundStyle(Color.tenue).lineLimit(2) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinta.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.2), lineWidth: 1))
    }
}

/// Il tasto per passare la parola a JARVIS.
struct TastoJarvis: View {
    let testo: String
    var icona = "waveform"
    let tinta: Color
    let azione: () -> Void

    var body: some View {
        Button { Suoni.tocco(); azione() } label: {
            Label(testo, systemImage: icona)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(Color.fondo)
                .background(tinta)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: tinta.opacity(0.4), radius: 8)
        }
        .buttonStyle(StileStark())
    }
}

/// 4 nov (il signore): la domanda prima di chiudere con un lavoro non salvato, uguale a quella dello Studio («SALVARE IN
/// ARCHIVIO?», .sd-foglio.sd-chiedi di markx.html): sale dal basso con la tacca; l'icona dell'archivio, il titolo e il perché;
/// il NOME; SALVA · NON SALVARE; ANNULLA; la nota. `extra`, sopra il nome: quello che serve in più (il Trainer).
struct FoglioSalva<Extra: View>: View {
    let titolo: String
    let sotto: String
    @Binding var nome: String
    let nota: String
    let salva: () -> Void
    let nonSalvare: () -> Void
    let annulla: () -> Void
    @ViewBuilder var extra: () -> Extra

    private static var grigio: Color { Color(red: 159 / 255, green: 179 / 255, blue: 185 / 255) }   // #9fb3b9
    private static var testo: Color { Color(red: 230 / 255, green: 244 / 255, blue: 248 / 255) }    // #e6f4f8

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5)
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ciano)
                    .frame(width: 54, height: 54)
                    .background(RadialGradient(colors: [Color.ciano.opacity(0.18), Color(red: 2 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.9)],
                                               center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 42))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titolo).font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
                    Text(sotto).font(.system(size: 12)).foregroundStyle(Self.grigio)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            extra()
            VStack(alignment: .leading, spacing: 6) {
                Text("NOME").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(Color.ciano.opacity(0.7))
                TextField("", text: $nome)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.testo)
                    .submitLabel(.done)
                    .onSubmit(salva)
                    .onChange(of: nome) { _, n in if n.count > 32 { nome = String(n.prefix(32)) } }
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 2 / 255, green: 8 / 255, blue: 12 / 255).opacity(0.8)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    .accessibilityLabel("Nome")
            }
            HStack(spacing: 8) {
                Button { Suoni.tocco(); salva() } label: {
                    Text("SALVA").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color(red: 0, green: 24 / 255, blue: 32 / 255))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ciano))
                }
                .buttonStyle(StileStark())
                Button { Suoni.tocco(); nonSalvare() } label: {
                    Text("NON SALVARE").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                        .foregroundStyle(Color.ciano)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(StileStark())
            }
            Button { Suoni.tocco(); annulla() } label: {
                Text("ANNULLA").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(Color.ciano)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(0.3), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(StileStark())
            Text(nota).font(.system(size: 14)).foregroundStyle(Self.testo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
        .padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 28)
        .background(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
            .fill(Color(red: 8 / 255, green: 14 / 255, blue: 17 / 255).opacity(0.98))
            .shadow(color: .black.opacity(0.6), radius: 20, y: -10))
        .overlay(BordoAlto(raggio: 22).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
    }
}

extension Animation {
    /// La salita del foglio «Salvare?», come lo Studio: 0,32 s, cubic-bezier(.2, .8, .2, 1).
    static var salitaFoglio: Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32) }
}

extension FoglioSalva where Extra == EmptyView {
    init(titolo: String, sotto: String, nome: Binding<String>, nota: String,
         salva: @escaping () -> Void, nonSalvare: @escaping () -> Void, annulla: @escaping () -> Void) {
        self.init(titolo: titolo, sotto: sotto, nome: nome, nota: nota, salva: salva, nonSalvare: nonSalvare, annulla: annulla) { EmptyView() }
    }
}

/// Il bordo di sopra di un foglio con gli angoli arrotondati (come border-top con border-radius): solo la riga in alto.
struct BordoAlto: Shape {
    let raggio: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + raggio))
        p.addArc(center: CGPoint(x: r.minX + raggio, y: r.minY + raggio), radius: raggio, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX - raggio, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - raggio, y: r.minY + raggio), radius: raggio, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        return p
    }
}

/// Il colore delle schede: lo stesso azzurro di JARVIS per tutte.
enum Tinte {
    static let diario = Color.ciano
    static let sonno = Color.ciano
    static let cuore = Color.ciano
    static let meteo = Color.ciano
    static let briefing = Color.ciano
    static let email = Color.ciano
    static let spesa = Color.ciano
    static let shazam = Color.ciano
    static let foto = Color.ciano
    static let serata = Color.ciano
}

// MARK: - DIARIO: le pagine della sera

struct VistaDiario: View {
    let chiedi: (String) -> Void
    let scrivi: () -> Void
    private let tinta = Tinte.diario

    struct Pagina: Identifiable {
        let id: Int
        let giorno: Date?
        let giornoTesto: String
        let domanda: String?
        let risposta: String
        let umore: String?
        let punteggio: Int?
        let energia: Int?
        let temi: [String]
    }

    @State private var pagine: [Pagina]?
    @State private var errore: String?
    @State private var aperta: Int?
    @State private var daCancellare: Pagina?
    @State private var cancellaTutto = false

    var body: some View {
        CorniceScheda(titolo: "Diario", sottotitolo: sottotitolo, icona: "book.closed", tinta: tinta, pronto: pagine != nil || errore != nil) {
            // 11.0 (6), come il mockup v264: l'ologramma del diario con le sue tre prove (ELICA, RILIEVO, ORBITA), scelte con le chip
            if let p = pagine {
                OlogrammaDiarioProve(dati: diarioOlo(p)).corniceOlo(tinta)
            }
            oggi
            if let p = pagine {
                if p.count > 1 { andamento(p) }
                if p.isEmpty {
                    Text("Ancora nessuna pagina. Ogni sera alle 23:30 JARVIS le fa una domanda; oppure tocchi il tasto qui sopra.")
                        .font(.footnote).foregroundStyle(Color.tenue)
                }
                ForEach(p) { pagina in riga(pagina) }
                if !p.isEmpty {
                    Button(role: .destructive) { cancellaTutto = true } label: {
                        Label("Cancella tutto il diario", systemImage: "trash").font(.footnote)
                    }
                    .tint(.red).padding(.top, 8)
                }
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            } else {
                ProgressView().tint(tinta).frame(maxWidth: .infinity).padding(.top, 40)
            }
        }
        .task { await carica() }
        .tastiAVoce { a in
            switch a {
            case .diarioAVoce: scrivi()
            case .diarioNeParliamo:                 // la pagina aperta, altrimenti l'ultima
                if let p = pagine?.first(where: { $0.id == aperta }) ?? pagine?.first {
                    chiedi("Rileggimi la pagina di diario del \(p.giornoTesto) e dimmi cosa ne pensi.")
                }
            default: break
            }
        }
        .confirmationDialog("Cancellare questa pagina?", isPresented: Binding(get: { daCancellare != nil }, set: { if !$0 { daCancellare = nil } }), titleVisibility: .visible) {
            Button("Cancella", role: .destructive) { if let p = daCancellare { Task { await cancella("\(p.id)") } } }
        }
        .confirmationDialog("Cancellare tutto il diario? Non si torna indietro.", isPresented: $cancellaTutto, titleVisibility: .visible) {
            Button("Cancella tutto", role: .destructive) { Task { await cancella("tutto") } }
        }
    }

    private var sottotitolo: String {
        guard let p = pagine else { return "sfoglio le pagine" }
        return p.isEmpty ? "nessuna pagina" : "\(p.count) pagin\(p.count == 1 ? "a" : "e") scritte"
    }

    /// Per le prove dell'ologramma (11.0 (6)): le ultime 20 sere e oggi, con umore, energia, l'umore in parole, la pagina e i temi.
    private func diarioOlo(_ p: [Pagina]) -> DiarioOlo {
        var sere: [(giorno: Date, v: Int?, e: Int?, u: String?, p: String?, temi: [String])] = []
        for x in p {
            if let g = x.giorno { sere.append((giorno: g, v: x.punteggio, e: x.energia, u: x.umore, p: x.risposta, temi: x.temi)) }
        }
        return DiarioOlo(pagine: sere)
    }

    private var paginaDiOggi: Pagina? {
        pagine?.first { p in p.giorno.map { Calendar.current.isDateInToday($0) } ?? false }
    }

    @ViewBuilder private var oggi: some View {
        Pannello(titolo: "STASERA", tinta: tinta, olografico: true) {
            if let p = paginaDiOggi {
                Text("La pagina di oggi è scritta\(p.umore.map { ": \($0)" } ?? "").").font(.system(size: 15)).foregroundStyle(.white)
            } else {
                Text("Mi racconti com'è andata: lei parla, io scrivo. Umore ed energia li ricavo io.")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
            }
            TastoJarvis(testo: paginaDiOggi == nil ? "Scrivi la pagina di oggi" : "Aggiungi a oggi", icona: "mic.fill", tinta: tinta) { scrivi() }
        }
    }

    private func andamento(_ p: [Pagina]) -> some View {
        let punti = p.compactMap { x -> (Date, Int)? in
            guard let g = x.giorno, let s = x.punteggio else { return nil }
            return (g, s)
        }.prefix(30)
        return Pannello(titolo: "UMORE · ULTIME PAGINE", tinta: tinta, olografico: true) {
            if punti.count < 2 {
                Text("Il grafico compare dalla seconda pagina.").font(.footnote).foregroundStyle(Color.tenue)
            } else {
                Chart(Array(punti), id: \.0) { g, s in
                    AreaMark(x: .value("Giorno", g, unit: .day), y: .value("Umore", s))
                        .foregroundStyle(LinearGradient(colors: [tinta.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Giorno", g, unit: .day), y: .value("Umore", s))
                        .foregroundStyle(tinta).interpolationMethod(.catmullRom)
                    PointMark(x: .value("Giorno", g, unit: .day), y: .value("Umore", s)).foregroundStyle(tinta).symbolSize(20)
                }
                .chartYScale(domain: 1...10)
                .chartYAxis { AxisMarks(values: [1, 5, 10]) }
                .frame(height: 130)
            }
        }
    }

    private func riga(_ p: Pagina) -> some View {
        let espansa = aperta == p.id
        return Button { withAnimation(.easeOut(duration: 0.2)) { aperta = espansa ? nil : p.id } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.giorno.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? p.giornoTesto)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tinta)
                    Spacer()
                    if let s = p.punteggio {
                        Text("\(s)/10")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(Color.fondo)
                            .background(colorePunteggio(s))
                            .clipShape(Capsule())
                    }
                }
                if let u = p.umore {
                    Text(u.prefix(1).uppercased() + u.dropFirst()).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                }
                Text(p.risposta)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(espansa ? nil : 3)
                    .multilineTextAlignment(.leading)
                if !p.temi.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(p.temi, id: \.self) { t in
                                Text(t).font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(tinta)
                                    .overlay(Capsule().stroke(tinta.opacity(0.5), lineWidth: 1))
                            }
                        }
                    }
                }
                if espansa {
                    HStack(spacing: 16) {
                        if let e = p.energia { Label("energia \(e)/10", systemImage: "bolt.fill").font(.system(size: 11)).foregroundStyle(Color.tenue) }
                        Spacer()
                        Button { chiedi("Rileggimi la pagina di diario del \(p.giornoTesto) e dimmi cosa ne pensi.") } label: {
                            Label("Ne parliamo", systemImage: "waveform").font(.system(size: 12, weight: .semibold))
                        }
                        .tint(tinta)
                        Button(role: .destructive) { daCancellare = p } label: { Image(systemName: "trash") }
                            .tint(.red)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(p.punteggio.map(colorePunteggio) ?? tinta.opacity(0.4)).frame(width: 3).padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
    }

    private func colorePunteggio(_ s: Int) -> Color {
        s >= 8 ? Color(red: 0.45, green: 0.92, blue: 0.6) : s >= 5 ? tinta : Color(red: 1.0, green: 0.55, blue: 0.4)
    }

    private func carica() async {
        guard let o = await VistaVitals.chiama(["vitals": true, "giorni": 90]) else { errore = "Non raggiungo il diario, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let lista = (o["pagine"] as? [[String: Any]] ?? []).compactMap { p -> Pagina? in
            guard let id = (p["id"] as? NSNumber)?.intValue, let r = p["risposta"] as? String else { return nil }
            let g = p["giorno"] as? String ?? ""
            return Pagina(id: id, giorno: f.date(from: g), giornoTesto: g, domanda: p["domanda"] as? String, risposta: r,
                          umore: p["umore"] as? String, punteggio: (p["punteggio"] as? NSNumber)?.intValue,
                          energia: (p["energia"] as? NSNumber)?.intValue, temi: p["temi"] as? [String] ?? [])
        }
        withAnimation(.easeOut(duration: 0.3)) { pagine = lista }
    }

    private func cancella(_ quale: String) async {
        let valore: Any = quale == "tutto" ? "tutto" : (Int(quale) ?? 0)
        _ = await VistaVitals.chiama(["diario_cancella": valore])
        Suoni.tocco()
        await carica()
    }
}

// MARK: - SONNO: la notte, fase per fase

struct VistaSonno: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.sonno

    @State private var oggi: SaluteOggi?
    @State private var fasi: [Salute.Tratto] = []
    @State private var notti: [(Date, Double)] = []
    @State private var caricato = false

    var body: some View {
        CorniceScheda(titolo: "Sonno", sottotitolo: oggi?.orari.map { "stanotte \($0)" } ?? "la notte scorsa", icona: "bed.double", tinta: tinta, pronto: caricato) {
            // 11.0 (6), come il mockup v264: l'ologramma della notte con le sue tre prove (ONDA, CICLI, NOTTI), scelte con le chip
            if !fasi.isEmpty || notti.count > 1 {
                OlogrammaSonnoProve(dati: SonnoOlo(fasi: fasi.map { t -> (Date, Date, Int) in (t.da, t.a, t.fase.rawValue) }, notti: notti))
                    .corniceOlo(tinta)
            }
            HStack(spacing: 10) {
                Valore(titolo: "DORMITO", valore: oggi?.sonno ?? "—", sotto: oggi?.orari, tinta: tinta)
                Valore(titolo: "MEDIA 14 NOTTI", valore: media.map { String(format: "%.1f h", $0) } ?? "—", sotto: confronto, tinta: tinta)
            }
            if !fasi.isEmpty { ipnogramma }
            if let f = oggi?.fasi {
                Pannello(titolo: "FASI", tinta: tinta) { Text(f.prefix(1).uppercased() + f.dropFirst()).font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)) }
            }
            if let p = oggi?.pisolini {
                Pannello(titolo: "PISOLINI DI OGGI", tinta: tinta) {
                    Text(p).font(.system(size: 14)).foregroundStyle(.white)
                    if let t = oggi?.riposoTotale { Text("Riposo totale: \(t)").font(.footnote).foregroundStyle(tinta) }
                }
            }
            if let n = oggi?.notaSonno {
                Text(n.prefix(1).uppercased() + n.dropFirst()).font(.footnote).foregroundStyle(Color.tenue)
            }
            if notti.count > 1 { storico }
            TastoJarvis(testo: "Com'ho dormito? Chieda a JARVIS", tinta: tinta) { chiedi("Come ho dormito stanotte? Dimmi anche come sta andando la settimana.") }
            if caricato && oggi?.sonno == nil && fasi.isEmpty {
                Text("Nessun dato di sonno: porti l'orologio a letto con il monitoraggio del sonno attivo (app Salute › Sonno).")
                    .font(.footnote).foregroundStyle(Color.tenue)
            }
        }
        .task {
            async let o = SaluteOggi.leggi()
            async let f = Salute.notte()
            async let g = SaluteStorica.giorni(14)
            let (a, b, c) = await (o, f, g)
            withAnimation(.easeOut(duration: 0.3)) {
                oggi = a
                fasi = b
                notti = c.compactMap { d, v in v.sonnoOre.map { (d, $0) } }.sorted { $0.0 < $1.0 }
                caricato = true
            }
        }
    }

    private var media: Double? { notti.isEmpty ? nil : notti.map(\.1).reduce(0, +) / Double(notti.count) }
    private var confronto: String? {
        guard let m = media, let ultima = notti.last?.1 else { return nil }
        let d = ultima - m
        return abs(d) < 0.25 ? "stanotte nella media" : (d > 0 ? String(format: "stanotte +%.1f h", d) : String(format: "stanotte %.1f h", d))
    }

    /// Il grafico della notte: quando era sveglio, in REM, nel sonno leggero e in quello profondo.
    private var ipnogramma: some View {
        Pannello(titolo: "LA NOTTE, FASE PER FASE", tinta: tinta) {
            Chart(fasi) { t in
                RectangleMark(xStart: .value("Da", t.da), xEnd: .value("A", t.a), y: .value("Fase", t.fase.nome))
                    .foregroundStyle(t.fase.colore)
                    .cornerRadius(2)
            }
            .chartYScale(domain: Salute.Fase.allCases.map(\.nome))
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.hour())
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
            } }
            .frame(height: 150)
        }
    }

    private var storico: some View {
        Pannello(titolo: "ULTIME 14 NOTTI", tinta: tinta) {
            Chart {
                ForEach(notti, id: \.0) { d, ore in
                    BarMark(x: .value("Notte", d, unit: .day), y: .value("Ore", ore))
                        .foregroundStyle(ore >= 7 ? tinta : tinta.opacity(0.45))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Obiettivo", 7)).foregroundStyle(Color.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("7 h").font(.system(size: 9)).foregroundStyle(Color.tenue) }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 140)
        }
    }
}

// MARK: - CUORE: battito di oggi, a riposo e variabilità

struct VistaCuoreTelefono: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.cuore

    @State private var battiti: [(Date, Double)] = []
    @State private var riposo: [(Date, Double)] = []
    @State private var hrv: [(Date, Double)] = []
    @State private var oggi: SaluteOggi?
    @State private var caricato = false
    @State private var confermaSOS = false
    @State private var esitoSOS: String?
    @State private var inviando = false

    var body: some View {
        CorniceScheda(titolo: "Cuore", sottotitolo: ultimo.map { "ultimo battito \(Int($0.1)) bpm · \($0.0.formatted(date: .omitted, time: .shortened))" } ?? "ascolto il polso",
                      icona: "heart", tinta: tinta, pronto: caricato) {
            // 11.0 (3), come il mockup approvato: il cuore in ologramma batte al ritmo di adesso; l'anello va da 40 a 180 battiti,
            // con l'arco di oggi (dal minimo al massimo), adesso e a riposo
            OlogrammaCuore(dati: DatiCuore(adesso: ultimo?.1 ?? 0, riposo: Double(oggi?.battito ?? 0),
                                           minimo: battiti.map(\.1).min() ?? 0, massimo: battiti.map(\.1).max() ?? 0))
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .background(tinta.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(tinta.opacity(0.22), lineWidth: 1))
                .overlay { AngoliOlo(tinta: tinta).padding(-1).allowsHitTesting(false) }
            HStack(spacing: 10) {
                Valore(titolo: "ADESSO", valore: ultimo.map { "\(Int($0.1))" } ?? "—", sotto: "bpm", tinta: tinta)
                Valore(titolo: "A RIPOSO", valore: oggi?.battito.map { "\($0)" } ?? "—", sotto: oggi?.battitoMedia.map { "media 7 gg \($0)" }, tinta: tinta)
                Valore(titolo: "HRV", valore: hrv.last.map { "\(Int($0.1))" } ?? "—", sotto: "ms", tinta: tinta)
            }
            if !battiti.isEmpty { oggiGrafico }
            if riposo.count > 1 {
                Pannello(titolo: "A RIPOSO · 30 GIORNI", tinta: tinta) {
                    Chart(riposo, id: \.0) { d, v in
                        LineMark(x: .value("Giorno", d, unit: .day), y: .value("bpm", v)).foregroundStyle(tinta).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Giorno", d, unit: .day), y: .value("bpm", v)).foregroundStyle(tinta).symbolSize(12)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 130)
                    Text("Più basso è, più il cuore è a riposo. Una salita di qualche giorno spesso vuol dire stanchezza o poco sonno.")
                        .font(.system(size: 11)).foregroundStyle(Color.tenue)
                }
            }
            if hrv.count > 1 {
                Pannello(titolo: "VARIABILITÀ (HRV) · 30 GIORNI", tinta: tinta) {
                    Chart(hrv, id: \.0) { d, v in
                        BarMark(x: .value("Giorno", d, unit: .day), y: .value("ms", v)).foregroundStyle(tinta.opacity(0.7)).cornerRadius(2)
                    }
                    .frame(height: 110)
                    Text("Più alta è, più il corpo ha recuperato.").font(.system(size: 11)).foregroundStyle(Color.tenue)
                }
            }
            TastoJarvis(testo: "Come sta il cuore? Chieda a JARVIS", tinta: tinta) { chiedi("Come sta il mio cuore oggi? Guarda battito a riposo e variabilità.") }
            // SOS: avvisa il contatto di emergenza con la posizione, subito
            Button { confermaSOS = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sos.circle.fill").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SOS · CHIEDI AIUTO").font(.system(size: 14, weight: .heavy, design: .monospaced)).tracking(1.5)
                        Text("SMS, WhatsApp e chiamata al contatto di emergenza, con la sua posizione").font(.system(size: 10)).opacity(0.85)
                    }
                    Spacer()
                    if inviando { ProgressView().tint(.white) }
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Color(red: 0.85, green: 0.15, blue: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.red.opacity(0.45), radius: 10)
            }
            .buttonStyle(StileStark())
            .disabled(inviando)
            if let esitoSOS { Text(esitoSOS).font(.footnote).foregroundStyle(esitoSOS.contains("NON") || esitoSOS.contains("non riuscito") ? .orange : Color(red: 0.45, green: 0.92, blue: 0.6)) }
            Text("L'Apple Watch sorveglia da solo: sopra 130 o sotto 40 battiti a riposo avvisa il contatto, con 5 secondi per annullare.")
                .font(.system(size: 11)).foregroundStyle(Color.tenue)
            if caricato && battiti.isEmpty && riposo.isEmpty {
                Text("Nessun dato del battito: serve l'Apple Watch al polso e il permesso di lettura in Salute.")
                    .font(.footnote).foregroundStyle(Color.tenue)
            }
        }
        .tastiAVoce { a in if a == .cuoreSOS { confermaSOS = true } }   // a voce si apre solo la domanda: il «sì» resta col dito
        .confirmationDialog("Chiedo aiuto al contatto di emergenza, con la sua posizione?", isPresented: $confermaSOS, titleVisibility: .visible) {
            Button("SÌ, CHIEDI AIUTO", role: .destructive) { Task { await sos() } }
            Button("Annulla", role: .cancel) {}
        }
        .task {
            async let b = Salute.battitiOggi()
            async let h = Salute.variabilita(giorni: 30)
            async let g = SaluteStorica.giorni(30)
            async let o = SaluteOggi.leggi()
            let (bb, hh, gg, oo) = await (b, h, g, o)
            withAnimation(.easeOut(duration: 0.3)) {
                battiti = bb
                hrv = hh
                riposo = gg.compactMap { d, v in v.battito.map { (d, $0) } }.sorted { $0.0 < $1.0 }
                oggi = oo
                caricato = true
            }
        }
    }

    private var ultimo: (Date, Double)? { battiti.last }

    /// Il tasto SOS: posizione dell'iPhone e chiamata alla funzione jarvis-allarme, la stessa dell'orologio.
    private func sos() async {
        inviando = true
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        var posizione: String?
        if let p = await Posizione.attuale(), let lat = p["lat"] as? Double, let lon = p["lon"] as? Double {
            posizione = String(format: "%.5f,%.5f", lat, lon)
        }
        let base = Impostazioni.indirizzo
        let indirizzo = base.hasSuffix("/jarvis") ? base + "-allarme" : base.replacingOccurrences(of: "/jarvis", with: "/jarvis-allarme")
        var corpo: [String: Any] = ["bpm": ultimo?.1 ?? 0, "prova": false, "motivo": "manuale"]
        if let posizione { corpo["posizione"] = posizione }
        var esito = "Nessuna connessione: allarme NON inviato."
        if let url = URL(string: indirizzo) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
            req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
            if let (d, r) = try? await URLSession.shared.data(for: req) {
                let codice = (r as? HTTPURLResponse)?.statusCode ?? 0
                let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
                if codice == 200 {
                    if json?["ripetuto"] as? Bool == true { esito = "Il contatto era già stato avvisato pochi minuti fa." }
                    else {
                        let canali = (json?["canali"] as? [String] ?? []).map { $0 == "whatsapp" ? "WhatsApp" : $0 == "sms" ? "SMS" : $0 == "chiamata" ? "telefonata" : $0 }
                        esito = "Contatto di emergenza avvisato: \(Array(Set(canali)).sorted().joined(separator: ", ")). Resti dov'è, Sir."
                    }
                } else { esito = "Allarme non riuscito: \(json?["errore"] as? String ?? "codice \(codice)")." }
            }
        }
        inviando = false
        esitoSOS = esito
        Suoni.fatto()                                 // SOS: il suono resta
    }

    private var oggiGrafico: some View {
        let valori = battiti.map(\.1)
        return Pannello(titolo: "OGGI · MIN \(Int(valori.min() ?? 0)) · MAX \(Int(valori.max() ?? 0))", tinta: tinta) {
            Chart(battiti, id: \.0) { d, v in
                LineMark(x: .value("Ora", d), y: .value("bpm", v)).foregroundStyle(tinta).interpolationMethod(.catmullRom)
                AreaMark(x: .value("Ora", d), yStart: .value("base", (valori.min() ?? 40) - 5), yEnd: .value("bpm", v))
                    .foregroundStyle(LinearGradient(colors: [tinta.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
            .frame(height: 150)
        }
    }
}

// MARK: - Letture da Salute per le schede (solo lettura)

nonisolated enum Salute {
    nonisolated private static let negozio = HKHealthStore()

    enum Fase: Int, CaseIterable, Sendable {
        case sveglio, rem, leggero, profondo
        var nome: String { ["Sveglio", "REM", "Leggero", "Profondo"][rawValue] }
        var colore: Color {
            [Color(red: 1.0, green: 0.6, blue: 0.45), Color(red: 0.55, green: 0.85, blue: 1.0),
             Color(red: 0.45, green: 0.55, blue: 1.0), Color(red: 0.35, green: 0.3, blue: 0.85)][rawValue]
        }
    }

    struct Tratto: Identifiable, Sendable {
        let da: Date
        let a: Date
        let fase: Fase
        var id: Date { da }
    }

    private static func permesso(_ tipi: Set<HKObjectType>) async {
        try? await negozio.requestAuthorization(toShare: [], read: tipi)
    }

    /// La notte scorsa, a tratti: dalle 18 di ieri alle 10 di oggi. Se c'è l'orologio, solo i suoi dati.
    static func notte() async -> [Tratto] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        await permesso([HKCategoryType(.sleepAnalysis)])
        let cal = Calendar.current
        let oggi = cal.startOfDay(for: Date())
        let da = oggi.addingTimeInterval(-6 * 3600), a = oggi.addingTimeInterval(10 * 3600)
        let campioni: [HKCategorySample] = await withCheckedContinuation { (c: CheckedContinuation<[HKCategorySample], Never>) in
            let q = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: da, end: a),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, _ in
                c.resume(returning: s as? [HKCategorySample] ?? [])
            }
            negozio.execute(q)
        }
        let daOrologio = campioni.filter { ($0.sourceRevision.productType ?? "").hasPrefix("Watch") }
        let scelti = daOrologio.isEmpty ? campioni : daOrologio
        return scelti.compactMap { s -> Tratto? in
            let fase: Fase
            switch s.value {
            case HKCategoryValueSleepAnalysis.awake.rawValue: fase = .sveglio
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: fase = .rem
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: fase = .profondo
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: fase = .leggero
            default: return nil                                    // «a letto» non è sonno
            }
            return Tratto(da: s.startDate, a: s.endDate, fase: fase)
        }
    }

    /// Il battito di oggi, una media ogni dieci minuti.
    static func battitiOggi() async -> [(Date, Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let tipo = HKQuantityType(.heartRate)
        await permesso([tipo])
        let inizio = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { (c: CheckedContinuation<[(Date, Double)], Never>) in
            let q = HKStatisticsCollectionQuery(quantityType: tipo, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: inizio, end: Date()),
                                                options: .discreteAverage, anchorDate: inizio, intervalComponents: DateComponents(minute: 10))
            q.initialResultsHandler = { _, risultati, _ in
                var out: [(Date, Double)] = []
                let bpm = HKUnit.count().unitDivided(by: .minute())
                risultati?.enumerateStatistics(from: inizio, to: Date()) { s, _ in
                    if let v = s.averageQuantity()?.doubleValue(for: bpm) { out.append((s.startDate, v)) }
                }
                c.resume(returning: out)
            }
            negozio.execute(q)
        }
    }

    /// La variabilità del battito (HRV, SDNN), media al giorno.
    static func variabilita(giorni: Int) async -> [(Date, Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let tipo = HKQuantityType(.heartRateVariabilitySDNN)
        await permesso([tipo])
        let cal = Calendar.current
        let ancora = cal.startOfDay(for: Date())
        guard let inizio = cal.date(byAdding: .day, value: -giorni, to: ancora) else { return [] }
        return await withCheckedContinuation { (c: CheckedContinuation<[(Date, Double)], Never>) in
            let q = HKStatisticsCollectionQuery(quantityType: tipo, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: inizio, end: Date()),
                                                options: .discreteAverage, anchorDate: ancora, intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, risultati, _ in
                var out: [(Date, Double)] = []
                risultati?.enumerateStatistics(from: inizio, to: Date()) { s, _ in
                    if let v = s.averageQuantity()?.doubleValue(for: .secondUnit(with: .milli)) { out.append((s.startDate, v)) }
                }
                c.resume(returning: out)
            }
            negozio.execute(q)
        }
    }
}
/// 27 ott (il signore): la scritta sotto il nome della sezione scorre veloce da sinistra, da trasparente al colore pieno (0,35 s);
/// quella di prima resta leggibile almeno 0,7 s, poi continua a scorrere a destra tornando trasparente, e arriva la nuova allo
/// stesso modo. Poi si ferma.
struct TestoCodice: View {
    let testo: String
    @State private var mostrato = ""                 // la scritta che si vede (la nuova arriva solo dopo che la vecchia si è letta)
    @State private var dentro = false                // posata (nitida, al suo posto) o fuori (trasparente, spostata, sfocata)
    @State private var daSinistra = false            // in uscita va a sinistra, in entrata arriva da destra
    @State private var lettaDa = Date.distantPast    // da quando la scritta mostrata è tutta leggibile
    @State private var voluta = ""                   // l'ultima scritta chiesta (se cambia ancora durante l'attesa, vale quella)

    var body: some View {
        Text(mostrato)
            .opacity(dentro ? 1 : 0)
            .offset(x: dentro ? 0 : (daSinistra ? 60 : -40))      // entra da sinistra, poi scorre via a destra
            .onAppear { mostra(testo, attesa: 0) }
            .onChange(of: testo) { _, nuovo in mostra(nuovo, attesa: max(0, 0.7 - Date().timeIntervalSince(lettaDa))) }
    }

    private func mostra(_ nuovo: String, attesa: Double) {
        voluta = nuovo
        Task { @MainActor in
            if attesa > 0 { try? await Task.sleep(for: .seconds(attesa)) }
            guard nuovo == voluta else { return }                      // nel frattempo è cambiata ancora: vale l'ultima
            if !mostrato.isEmpty {                                     // la vecchia continua a scorrere a destra, sfumando
                daSinistra = true
                withAnimation(.easeIn(duration: 0.3)) { dentro = false }
                try? await Task.sleep(for: .milliseconds(300))
                guard nuovo == voluta else { return }
            }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { mostrato = nuovo; daSinistra = false; dentro = false }   // pronta fuori, a sinistra
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) { dentro = true }
            try? await Task.sleep(for: .milliseconds(360))
            if nuovo == voluta { lettaDa = Date() }
        }
    }
}
/// 27 ott (il signore: «testi cool per il caricamento di ogni sezione»): cosa sta facendo JARVIS mentre apre ogni sezione.
/// Sotto il nome della sezione (al posto di «acquisizione dati») e prima voce dei sistemi nel caricamento.
enum TestiCaricamento {
    private static let testi: [String: String] = [
        "meteo": "aggancio satelliti meteo", "email": "decrittazione posta", "messaggi": "messaggi in arrivo",
        "diario": "apertura archivio personale", "sonno": "lettura cicli notturni", "cuore": "sincronizzazione battito",
        "briefing": "compilazione rapporto", "spesa": "inventario dispensa", "shazam": "scansione spettro sonoro",
        "foto": "scansione galleria", "serata": "collegamento sala", "telefono": "apertura linea sicura",
        "bea": "protective instinct", "github": "sincronizzazione repository", "supabase": "interrogazione database",
        "archivio": "recupero file classificati", "costi": "calcolo consumi", "edith": "attivazione protocolli difesa",
        "scanner": "ottiche in posizione", "satellite": "aggancio orbita", "sound": "riscaldamento amplificatori",
        "vitals": "lettura parametri vitali", "ricordi": "richiamo memoria", "confidente": "canale riservato",
        "wiretap": "microfoni in ascolto", "interprete": "caricamento dizionari", "trainer": "calibrazione scheletro",
        "occhi": "sistemi ottici in linea", "cucina": "analisi ingredienti", "lidar": "proiezione griglia laser",
        "sentinella": "armamento perimetro", "profiler": "riconoscimento soggetto", "browser": "connessione cifrata",
        "studio": "laboratorio 3d in linea", "social": "social network",
    ]
    static func di(_ sezione: String) -> String { testi[sezione.lowercased()] ?? "acquisizione dati" }
}
#endif
