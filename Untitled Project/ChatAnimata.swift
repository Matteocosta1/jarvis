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
}

private struct ChiaveRegiaChat: EnvironmentKey { static let defaultValue = RegiaChat() }
extension EnvironmentValues {
    var regiaChat: RegiaChat {
        get { self[ChiaveRegiaChat.self] }
        set { self[ChiaveRegiaChat.self] = newValue }
    }
}

/// I numeri dell'avvio, in un posto solo (20 ott: +40%, SINCRO 110 ms, scelti dal signore sul mock).
enum Avvio {
    /// Quanto è più svelto l'avvio rispetto all'originale: la traccia «avvio» è rimontata a questa velocità.
    static let velocita = 1.4
    /// Da Interprete in poi (la raffica finale) ogni icona parte prima del suo colpo, così la molla arriva sul beep.
    static let anticipoCoda = 0.110
    /// La molla delle icone della coda: la stessa, più svelta.
    static let mollaCoda = 0.12
    /// L'indice della prima icona della coda («Interprete»).
    static func inizioCoda(_ nomi: [String]) -> Int { nomi.firstIndex(of: "Interprete") ?? nomi.count }
}

enum TempiChat {
    // il caricamento all'avvio va alla velocità dell'avvio (+40%): tutto in proporzione, suono «chatcarica» compreso
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
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
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
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
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
#endif
