#if os(iOS)
import SwiftUI
import Combine
import AVFoundation
import Speech

/// L'interprete di JARVIS: il signore parla italiano e JARVIS lo dice nell'altra lingua con la sua voce;
/// l'altro risponde nella sua lingua e JARVIS la traduce in italiano. Due direzioni, a turni, in una schermata HUD.
struct Lingua: Identifiable, Hashable {
    let codice: String      // per il cervello: en, es, fr…
    let locale: String      // per il riconoscimento vocale: en-US, es-ES…
    let nome: String
    let bandiera: String
    var id: String { codice }

    static let tutte: [Lingua] = [
        Lingua(codice: "en", locale: "en-US", nome: "Inglese", bandiera: "🇬🇧"),
        Lingua(codice: "es", locale: "es-ES", nome: "Spagnolo", bandiera: "🇪🇸"),
        Lingua(codice: "fr", locale: "fr-FR", nome: "Francese", bandiera: "🇫🇷"),
        Lingua(codice: "de", locale: "de-DE", nome: "Tedesco", bandiera: "🇩🇪"),
        Lingua(codice: "pt", locale: "pt-BR", nome: "Portoghese", bandiera: "🇧🇷"),
        Lingua(codice: "zh", locale: "zh-CN", nome: "Cinese", bandiera: "🇨🇳"),
        Lingua(codice: "ja", locale: "ja-JP", nome: "Giapponese", bandiera: "🇯🇵"),
        Lingua(codice: "ar", locale: "ar-SA", nome: "Arabo", bandiera: "🇸🇦"),
        Lingua(codice: "ru", locale: "ru-RU", nome: "Russo", bandiera: "🇷🇺"),
        Lingua(codice: "tr", locale: "tr-TR", nome: "Turco", bandiera: "🇹🇷"),
        Lingua(codice: "ro", locale: "ro-RO", nome: "Rumeno", bandiera: "🇷🇴"),
        Lingua(codice: "nl", locale: "nl-NL", nome: "Olandese", bandiera: "🇳🇱"),
        Lingua(codice: "pl", locale: "pl-PL", nome: "Polacco", bandiera: "🇵🇱"),
        Lingua(codice: "el", locale: "el-GR", nome: "Greco", bandiera: "🇬🇷"),
        Lingua(codice: "hi", locale: "hi-IN", nome: "Hindi", bandiera: "🇮🇳"),
        Lingua(codice: "uk", locale: "uk-UA", nome: "Ucraino", bandiera: "🇺🇦"),
    ]
    static let italiano = Lingua(codice: "it", locale: "it-IT", nome: "Italiano", bandiera: "🇮🇹")

    static func trova(_ codice: String) -> Lingua? {
        let c = codice.lowercased().trimmingCharacters(in: .whitespaces)
        return tutte.first { $0.codice == c } ?? tutte.first { $0.nome.lowercased().hasPrefix(c) }
    }
}

struct Interprete: View {
    /// La lingua con cui si apre: nil dall'icona (la sceglie qui dentro, nel pannello LINGUA), già scelta con «traduci in tedesco».
    let lingua: Lingua?
    /// 9 nov: la lingua scelta o cambiata qui dentro, per il contenitore (JARVIS e la pila la ricordano).
    var scelta: (Lingua) -> Void = { _ in }
    let chiudi: () -> Void
    @StateObject private var motore = MotoreInterprete()
    @AppStorage("interpreteAuto") private var automatico = true
    @State private var cambiata: Lingua?                // la lingua scelta qui dentro (nel pannello o a voce: «passa al francese»)
    @State private var scegliendo = false               // «Jarvis, cambia lingua»: il pannello LINGUA torna al posto della conversazione
    @State private var orecchio = OrecchioComandi()     // i comandi a voce tra un turno e l'altro, sempre con «Jarvis» davanti
    @State private var chiuso = false                   // a schermata chiusa l'orecchio non si riaccende più
    private var lin: Lingua? { cambiata ?? lingua }

    // 9 nov notte (il signore: «la sezione interprete va rifatta… si apre due volte ed è orribile così»): identica al mockup
    // (sezione Interprete del mockup Mark XI). Una sola apertura, col caricamento e la testata di tutte le sezioni (CorniceScheda):
    // in testa l'ologramma PONTE; sotto, senza lingua, il pannello LINGUA; scelta la lingua, al suo posto i due lati (LEI ⇄ L'ALTRO),
    // lo stato, la conversazione in un riquadro olografico, i turni automatici e i due tasti ASCOLTA. Prima la lingua si sceglieva in
    // una scheda a parte (SceltaLingua) che si chiudeva, e poi saliva l'Interprete col suo caricamento: due aperture.
    var body: some View {
        let frasi = motore.scambi.map { PonteInterprete.Frase(altro: $0.chi == .altro, testo: $0.originale, trad: $0.tradotto) }
        CorniceScheda(titolo: "Interprete", sottotitolo: lin.map { $0.nome.lowercased() } ?? "scelga la lingua",
                      icona: "globe.europe.africa", tinta: Color.ciano, fondo: motore.scambi.count) {
            // v270: il PONTE fra le due lingue, in testa come nel mockup (prima della scelta: IT e il punto di domanda)
            OloSingolaVista(altezza: 250, aiuto: "↔ GIRA · TOCCA UNA FRASE", etichetta: "Ologramma del ponte fra le due lingue") { gc, W, H, t, M in
                PonteInterprete.disegna(&gc, W, H, t, M, la: "IT", lb: lin.map { $0.codice.uppercased() } ?? "?", frasi: frasi)
            }
            .corniceOlo(Color.ciano)
            if let l = lin, !scegliendo {
                conversazione(l)
            } else {
                pannelloLingue
            }
        }
        .onAppear {
            motore.automatico = automatico
            orecchio.dentro = .interprete
            orecchio.comando = { c in comando(c) }
            motore.suComando = { c in comando(c) }          // «Jarvis, …» detto durante il suo turno: è un comando, non si traduce
            if let l = lin { motore.prepara(lingua: l) }
        }
        .task {
            try? await Task.sleep(for: .seconds(Apertura.orecchio))      // dopo il suono d'apertura, come nella Sentinella
            // senza lingua il microfono resta a JARVIS («Jarvis, inglese»): quello dell'Interprete parte con la lingua
            if !Task.isCancelled, !chiuso, lin != nil, motore.fase == .attesa { orecchio.avvia() }
        }
        // il microfono dei comandi resta acceso solo tra un turno e l'altro: nei turni il microfono è dell'Interprete
        .onChange(of: motore.fase) { _, f in
            if f != .attesa { orecchio.ferma(); return }
            riaccendiOrecchio()
        }
        // la lingua arrivata da fuori mentre il pannello è aperto («Jarvis, inglese» detto a JARVIS): si parte con quella
        .onChange(of: lingua) { _, l in
            guard let l, l != cambiata else { return }
            cambiata = l
            scegliendo = false
            motore.prepara(lingua: l)
            riaccendiOrecchio()
        }
        .onChange(of: automatico) { _, v in motore.automatico = v }
        .onDisappear { chiuso = true; orecchio.ferma(); motore.ferma() }
        .pausaDietro(ferma: { orecchio.ferma(); motore.ferma() },          // MARK XI: dietro in pausa
                     riprendi: { if !chiuso, lin != nil, motore.fase == .attesa { orecchio.avvia() } })
    }

    /// La scelta della lingua, come il mockup: il pannello LINGUA con i tasti delle lingue su due colonne.
    private var pannelloLingue: some View {
        Pannello(titolo: "LINGUA", tinta: Color.ciano, olografico: true) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Lingua.tutte) { l in
                    TastoComando(testo: "\(l.bandiera) \(l.nome)") { scegli(l) }
                }
            }
        }
    }

    /// Scelta la lingua: i due lati, lo stato, la conversazione, i turni automatici e i due tasti, come il mockup.
    @ViewBuilder private func conversazione(_ l: Lingua) -> some View {
        HStack(spacing: 10) {
            lato(Lingua.italiano, attivo: motore.lato == .io, titolo: "LEI")
            Text("⇄").foregroundStyle(Color.tenue)
            lato(l, attivo: motore.lato == .altro, titolo: "L'ALTRO")
        }
        Text(motore.stato)
            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(3)
            .foregroundStyle(motore.fase == .ascolto ? Color.ciano : Color.orange)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 18)
        if !motore.scambi.isEmpty || !motore.parziale.isEmpty {
            Pannello(tinta: Color.ciano, olografico: true) {
                ForEach(motore.scambi) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.originale).font(.system(size: 14)).foregroundStyle(.white)
                        Text(s.tradotto.isEmpty ? "…" : s.tradotto).font(.system(size: 12)).foregroundStyle(Color.tenue)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(s.chi == .io ? Color.ciano.opacity(0.35) : Color.orange.opacity(0.4), lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(s.chi == .io ? "Lei" : l.nome): \(s.originale). Tradotto: \(s.tradotto)")
                }
                if !motore.parziale.isEmpty {
                    Text(motore.parziale).font(.system(size: 14)).foregroundStyle(Color.tenue).padding(.horizontal, 10)
                }
            }
        }
        Toggle(isOn: $automatico) {                                   // come «Solo non lette» della Posta (.interr del mockup)
            Text("A turni automatici").font(.system(size: 14)).foregroundStyle(.white)
        }
        .tint(Color.ciano)
        HStack(spacing: 8) {
            TastoComando(testo: "Ascolta me", attivo: libero) { Suoni.tocco(); orecchio.ferma(); motore.ascolta(.io, lingua: l) }
            TastoComando(testo: "Ascolta \(l.bandiera)", attivo: libero) { Suoni.tocco(); orecchio.ferma(); motore.ascolta(.altro, lingua: l) }
        }
    }

    /// I tasti ASCOLTA valgono quando l'Interprete non sta traducendo o parlando.
    private var libero: Bool { motore.fase != .traduco && motore.fase != .parlo }

    /// Una lingua toccata nel pannello: la prima volta si parte, dopo è un cambio (con l'annuncio, come a voce).
    private func scegli(_ l: Lingua) {
        Suoni.tocco()
        guard lin != nil else {
            cambiata = l
            scegliendo = false
            scelta(l)
            motore.prepara(lingua: l)
            riaccendiOrecchio()
            return
        }
        cambia(l)
    }

    /// L'orecchio dei comandi si riaccende un attimo dopo (finito il turno o scelta la lingua).
    private func riaccendiOrecchio() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !chiuso, lin != nil, motore.fase == .attesa { orecchio.avvia() }
        }
    }

    /// I comandi a voce dentro l'Interprete.
    private func comando(_ c: ComandoVocale) {
        // MARK XI: «sezioni aperte», «quella di prima», «chiudi il meteo»… li esegue la schermata principale
        if c.navigaSezioni { ComandiSezioni.invia(c); return }
        switch c {
        case .torna:
            chiuso = true; orecchio.ferma(); motore.ferma(); chiudi()
        case .dentroInterprete(let a):
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            switch a {
            case .lingua(let codice): if let l = Lingua.trova(codice) { scegli(l) }
            case .sceltaLingua: withAnimation(.easeOut(duration: 0.25)) { scegliendo = true }   // 9 nov: il pannello LINGUA, qui dentro
            case .turniAutomatici(let si):
                automatico = si
                orecchio.ferma(); motore.annuncia(si ? "Turni automatici, Sir." : "Turni manuali, Sir.")
            case .ascoltaMe, .ascoltaAltro, .ripeti:
                guard let l = lin, !scegliendo else { return }       // senza lingua non c'è niente da ascoltare né da ripetere
                switch a {
                case .ascoltaMe: orecchio.ferma(); motore.ascolta(.io, lingua: l)
                case .ascoltaAltro: orecchio.ferma(); motore.ascolta(.altro, lingua: l)
                default:                                    // niente da ripetere: l'ascolto dei comandi resta acceso
                    orecchio.ferma(); motore.ripeti(l)
                    if motore.fase == .attesa { orecchio.avvia() }
                }
            }
        case .interprete(let codice):                         // «Jarvis, traduci in tedesco» anche da qui
            if let l = Lingua.trova(codice) { scegli(l) }
        default: break
        }
    }

    private func cambia(_ l: Lingua) {
        cambiata = l
        withAnimation(.easeOut(duration: 0.25)) { scegliendo = false }   // anche a voce («passa al francese») col pannello aperto
        scelta(l)
        motore.prepara(lingua: l)
        orecchio.ferma()
        motore.annuncia("\(l.nome), Sir.")
    }

    private func lato(_ l: Lingua, attivo: Bool, titolo: String) -> some View {
        VStack(spacing: 2) {
            Text(l.bandiera).font(.system(size: 28))
            Text(titolo).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.tenue)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)                 // come .in-lato del mockup
        .overlay { if attivo { AngoliOlo(tinta: Color.ciano).padding(-1).allowsHitTesting(false) } }   // 27 ott: chi parla, nel visore
        .background(Color.ciano.opacity(attivo ? 0.18 : 0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(attivo ? 0.9 : 0.25), lineWidth: attivo ? 1.4 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .ciano.opacity(attivo ? 0.5 : 0), radius: 8)
        .animation(.easeInOut(duration: 0.3), value: attivo)
    }
}

// MARK: - IN1 · PONTE (v270) — le due lingue sono due piattaforme di luce ai lati del proiettore (la sua, IT, e quella dell'altro),
// ognuna con il codice grande sopra e l'equalizzatore della voce attorno, che si accende quando quella parte parla. Fra le due un
// ponte di luce ad arco, con i suoi binari e le traversine: le frasi lo attraversano come capsule, partono nella lingua di chi parla
// e a metà ponte si traducono (il testo si scompone e si ricompone nell'altra lingua), lasciando una scia di scintille. Il dito gira
// la scena; toccata una capsula: la frase e la sua traduzione. Uguale al mockup v270 (olo_extra/nuovi.js, ponteInterprete).
enum PonteInterprete {
    struct Frase { let altro: Bool; let testo: String; let trad: String }
    private static let fraseId = 0
    private static let latoId = 10

    static func disegna(_ gc: inout GraphicsContext, _ W: Double, _ H: Double, _ t: Double, _ M: ManoOlo, la: String, lb: String, frasi: [Frase]) {
        let cx = W / 2, base = H - 14, rx = min(W * 0.22, 84)
        Olo.pavimento(&gc, cx, base, rx, t, n: 48)
        let al = 0.3, sz = min(W * 0.36, H * 0.55), cy = base - 14
        let ang = 0.15 * sin(t * 0.22) + M.giro * 0.6, nasce = OP.lis(t / 0.9)
        let P = { (x: Double, y: Double, z: Double) -> P3 in Olo.proietta(x, y, z, ang, al, cx, cy, sz) }
        var F = FasciOlo(6)
        let periodo = 4.2, n = max(1, frasi.count), corrente = Int(t / periodo) % n, u = t.truncatingRemainder(dividingBy: periodo) / periodo
        let parla = frasi.isEmpty ? Int(t / 5) % 2 : (frasi[corrente].altro ? 1 : 0)
        // le due piattaforme con l'equalizzatore
        let lati = [-0.95, 0.95]
        for (i, X) in lati.enumerated() {
            let vivo = i == parla, rg = 0.32
            var q: P3?
            for s in 0...36 {
                let a = Double(s) / 36 * OP.due, p = P(X + cos(a) * rg, sin(a) * rg, 0.02)
                if let q { F.metti(vivo ? 3 : 1, q, p) }
                q = p
            }
            q = nil
            for s in 0...36 {
                let a = Double(s) / 36 * OP.due, p = P(X + cos(a) * rg * 0.6, sin(a) * rg * 0.6, 0.02)
                if let q { F.metti(0, q, p) }
                q = p
            }
            for b in 0..<18 {
                let a = Double(b) / 18 * OP.due + t * 0.3
                let onda = vivo ? 0.5 + 0.5 * abs(sin(t * 7 + Double(b) * 1.7) * sin(t * 3.1 + Double(b))) : 0.12
                let r0 = rg * 0.75, z1 = 0.05 + 0.3 * onda * nasce
                F.metti(vivo ? 4 : 1, P(X + cos(a) * r0, sin(a) * r0, 0.03), P(X + cos(a) * r0, sin(a) * r0, z1))
            }
        }
        // il ponte: due binari ad arco e le traversine
        let A = P3(-0.95, 0, 0.42), C = P3(0, 0, 1.05), B2 = P3(0.95, 0, 0.42)
        let arco = { (s: Double, dy: Double) -> P3 in
            let v = 1 - s, p = A * (v * v) + C * (2 * v * s) + B2 * (s * s)
            return P(p.x, p.y + dy, p.z)
        }
        let pezzi = 40
        for k in 0..<pezzi {
            let s0 = Double(k) / Double(pezzi), s1 = Double(k + 1) / Double(pezzi)
            if s1 > nasce { break }
            F.metti(3, arco(s0, -0.07), arco(s1, -0.07))
            F.metti(3, arco(s0, 0.07), arco(s1, 0.07))
            if k % 3 == 0 { F.metti(1, arco(s0, -0.07), arco(s0, 0.07)) }
        }
        for X in lati { F.metti(1, P(X, 0, 0.05), P(X, 0, 0.42)) }        // i piloni
        F.linee(&gc, colore: { $0 >= 4 ? OP.b(0.85) : OP.c(0.1 + 0.17 * Double($0)) },
                spessore: { 0.7 + Double($0) * 0.14 }, alone: { $0 >= 3 ? OP.s(0.08) : nil })
        // la capsula che attraversa (dalla lingua di chi parla all'altra), con la scia di scintille
        let s = parla == 1 ? 1 - OP.lis(u) : OP.lis(u), cap = arco(s, 0)
        for k in 1...8 {
            let sk = parla == 1 ? min(1, s + Double(k) * 0.018) : max(0, s - Double(k) * 0.018), q = arco(sk, 0.03 * sin(t * 9 + Double(k)))
            OP.alone(&gc, q.x, q.y, 3.5, 0.5 * (1 - Double(k) / 9))
        }
        OP.alone(&gc, cap.x, cap.y, 14, 0.6, bianco: true)
        // i codici delle lingue sopra le piattaforme
        for (i, X) in lati.enumerated() {
            let p = P(X, 0, 0.55), vivo = i == parla
            OP.scritta(&gc, i == 1 ? lb : la, p.x, p.y - 4, vivo ? 15 : 12, 800, vivo ? OP.b(0.98) : OP.c(0.6))
            OP.scritta(&gc, i == 1 ? "L'ALTRO" : "LEI", p.x, p.y + 8, 6.5, 600, OP.c(0.75))
            M.zona(p.x, p.y, 20, latoId + i)
        }
        // la capsula: il testo nella lingua di chi parla, a metà ponte si traduce
        if !frasi.isEmpty {
            let f = frasi[corrente], meta = abs(s - 0.5) < 0.06, tradotta = parla == 1 ? s < 0.5 : s > 0.5
            let testo = OP.taglia(tradotta ? (f.trad.isEmpty ? "…" : f.trad) : f.testo, 22)
            let w = min(150, 14 + Double(testo.count) * 5.2), hC = 20.0, bx = cap.x - w / 2, by = cap.y - hC - 8
            gc.fill(Path(CGRect(x: bx, y: by, width: w, height: hC)), with: .color(Color(red: 2 / 255, green: 12 / 255, blue: 16 / 255).opacity(0.82)))
            var tacche = Path()
            let spigoli: [(x: Double, y: Double, dx: Double, dy: Double)] = [(bx, by, 1, 1), (bx + w, by, -1, 1), (bx, by + hC, 1, -1), (bx + w, by + hC, -1, -1)]
            for g in spigoli {
                tacche.move(to: CGPoint(x: g.x, y: g.y + g.dy * 5))
                tacche.addLine(to: CGPoint(x: g.x, y: g.y))
                tacche.addLine(to: CGPoint(x: g.x + g.dx * 5, y: g.y))
            }
            gc.stroke(tacche, with: .color(M.scelta == fraseId ? OP.b(1) : OP.c(0.85)), lineWidth: 1)
            var mescola = testo
            if meta {                                                     // a metà ponte il testo si scompone
                let segni = Array("01#<>/*"), passo = Int(t * 30)
                mescola = String(testo.enumerated().map { e -> Character in
                    if e.element.isWhitespace || (e.offset + passo) % 3 == 0 { return e.element }
                    return segni[min(6, Int((t * 50 + Double(e.offset)).truncatingRemainder(dividingBy: 7)))]
                })
            }
            OP.scritta(&gc, mescola, cap.x, by + 13, 6.8, 700, OP.b(0.95))
            var gamba = Path()
            Olo.linea(&gamba, cap.x, by + hC, cap.x, cap.y - 3)
            gc.stroke(gamba, with: .color(OP.s(0.5)), lineWidth: 1)
            M.zona(cap.x, by + hC / 2, max(18, w / 2), fraseId)
            if M.scelta == fraseId {
                OP.riquadro(&gc, W, H, cap.x, cap.y, [OP.taglia(f.testo, 30), OP.taglia(f.trad, 30), f.altro ? "L'ALTRO → LEI · \(lb) → \(la)" : "LEI → L'ALTRO · \(la) → \(lb)"],
                            t - M.sceltaT, codice: "FRASE \(corrente + 1)/\(n)")
            }
        }
        OP.scritta(&gc, "INTERPRETE", 10, 14, 8, 600, OP.c(0.85), .leading)
        OP.scritta(&gc, "\(la) ⇄ \(lb)", W - 10, 14, 8, 700, OP.b(0.95), .trailing)
        if frasi.isEmpty && lb == "?" { OP.scritta(&gc, "SCELGA LA LINGUA", W / 2, 34, 7, 700, OP.c(0.85)) }   // 8 nov: come il mockup
        if let k = M.scelta, k >= latoId, k - latoId < lati.count {
            let i = k - latoId, p = P(lati[i], 0, 0.55)
            OP.riquadro(&gc, W, H, p.x, p.y, [i == 1 ? lb : la, i == 1 ? "LA LINGUA DELL'ALTRO" : "LA SUA LINGUA", parla == i ? "STA PARLANDO" : "ASCOLTA"],
                        t - M.sceltaT, codice: i == 1 ? "L'ALTRO" : "LEI")
        }
    }
}

// MARK: - Il motore: ascolta, traduce, parla

@MainActor
final class MotoreInterprete: NSObject, ObservableObject {
    enum Lato { case io, altro }
    enum FaseI { case attesa, ascolto, traduco, parlo }
    struct Scambio: Identifiable { let id = UUID(); let chi: Lato; let originale: String; var tradotto: String; let ora: String }

    @Published var fase: FaseI = .attesa
    @Published var lato: Lato = .io
    @Published var scambi: [Scambio] = []
    @Published var parziale = ""
    @Published var stato = "PRONTO"
    var automatico = true
    var suComando: ((ComandoVocale) -> Void)?    // «Jarvis, …» detto nel turno del signore

    private let motore = AVAudioEngine()
    private var riconoscitore: SFSpeechRecognizer?
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var turno = 0
    private var lingua = Lingua.tutte[0]
    private var lettore: AVAudioPlayer?
    private let sintesi = AVSpeechSynthesizer()
    private var attesaVoce: CheckedContinuation<Void, Never>?

    var faseHUD: Fase { fase == .ascolto ? .ascolto : (fase == .attesa ? .attesa : .parlo) }

    override init() { super.init(); sintesi.delegate = self }

    func prepara(lingua: Lingua) {
        self.lingua = lingua
        Task {
            _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { @Sendable s in c.resume(returning: s == .authorized) }
            }
            _ = await AVAudioApplication.requestRecordPermission()
            stato = "PRONTO · TOCCHI «ASCOLTA ME»"
        }
    }

    func ferma() {
        turno += 1
        fermaAscolto()
        lettore?.stop(); lettore = nil
        sintesi.stopSpeaking(at: .immediate)
        rilasciaVoce()
        fase = .attesa
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ascolta uno dei due lati, poi traduce e parla nell'altra lingua.
    func ascolta(_ chi: Lato, lingua: Lingua) {
        guard fase == .attesa || fase == .ascolto else { return }
        if fase == .ascolto { fermaAscolto(); fase = .attesa }
        self.lingua = lingua
        lato = chi
        let loc = chi == .io ? Lingua.italiano.locale : lingua.locale
        guard let ric = SFSpeechRecognizer(locale: Locale(identifier: loc)), ric.isAvailable else {
            stato = "RICONOSCIMENTO NON DISPONIBILE PER \(lingua.nome.uppercased())"
            Suoni.errore()
            return
        }
        riconoscitore = ric
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try s.setActive(true, options: .notifyOthersOnDeactivation)
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            richiesta = r
            let input = motore.inputNode
            let formato = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            MotoreInterprete.collega(input, formato: formato, a: r)
            motore.prepare()
            try motore.start()
            parziale = ""
            fase = .ascolto
            stato = chi == .io ? "LA ASCOLTO, SIR" : "ASCOLTO IN \(lingua.nome.uppercased())"
            Suoni.ascolto()
            turno += 1
            let mio = turno
            compito = MotoreInterprete.riconosci(ric, r) { [weak self] testo, finale, errore in
                Task { @MainActor [weak self] in self?.aggiorna(testo, finale: finale, errore: errore, turno: mio) }
            }
            arma(7)
        } catch {
            stato = "MICROFONO NON DISPONIBILE"
            fermaAscolto()
        }
    }

    private func aggiorna(_ testo: String?, finale: Bool, errore: Bool, turno mio: Int) {
        guard fase == .ascolto, mio == turno else { return }
        if let testo, !testo.isEmpty { parziale = testo; arma(1.4) }
        if finale || errore { concludiAscolto() }
    }

    private func arma(_ secondi: Double) {
        timer?.invalidate()
        let mio = turno
        timer = Timer.scheduledTimer(withTimeInterval: secondi, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.turno == mio else { return }
                self.concludiAscolto()
            }
        }
    }

    private func fermaAscolto() {
        timer?.invalidate(); timer = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil; compito = nil
    }

    private func concludiAscolto() {
        guard fase == .ascolto else { return }
        fermaAscolto()
        let testo = parziale.trimmingCharacters(in: .whitespacesAndNewlines)
        parziale = ""
        guard !testo.isEmpty else { fase = .attesa; stato = "NON HO SENTITO NULLA"; return }
        // nel suo turno, «Jarvis, ascolta lui», «Jarvis, passa al francese»…: è un comando, non una frase da tradurre
        if lato == .io, let c = ComandoVocale.riconosci(testo, serveJarvis: true, dentro: .interprete) {
            fase = .attesa
            stato = "PRONTO"
            suComando?(c)
            return
        }
        Task { await traduciEParla(testo) }
    }

    private func traduciEParla(_ testo: String) async {
        fase = .traduco
        stato = "TRADUCO"
        let chi = lato
        let da = chi == .io ? "it" : lingua.codice
        let a = chi == .io ? lingua.codice : "it"
        let ora = Date().formatted(date: .omitted, time: .shortened)
        scambi.append(Scambio(chi: chi, originale: testo, tradotto: "", ora: ora))
        let idx = scambi.count - 1
        guard let tradotto = await MotoreInterprete.traduci(testo, da: da, a: a), !tradotto.isEmpty else {
            scambi[idx].tradotto = "(traduzione non riuscita)"
            fase = .attesa; stato = "CERVELLO NON RAGGIUNGIBILE"; Suoni.errore()
            return
        }
        scambi[idx].tradotto = tradotto
        fase = .parlo
        stato = chi == .io ? "PARLO IN \(lingua.nome.uppercased())" : "TRADUCO IN ITALIANO"
        await parla(tradotto, lingua: chi == .io ? lingua : Lingua.italiano)
        fase = .attesa
        stato = "PRONTO"
        // a turni: dopo aver parlato per il signore, ascolta subito la risposta dell'altro
        if automatico && chi == .io { ascolta(.altro, lingua: lingua) }
    }

    /// «Jarvis, ripeti»: ridice l'ultima traduzione, nella lingua in cui era stata detta.
    func ripeti(_ straniera: Lingua) {
        guard fase == .attesa, let u = scambi.last, !u.tradotto.isEmpty, u.tradotto != "(traduzione non riuscita)" else { return }
        Task {
            fase = .parlo
            stato = "RIPETO"
            await parla(u.tradotto, lingua: u.chi == .io ? straniera : Lingua.italiano)
            fase = .attesa
            stato = "PRONTO"
        }
    }

    /// Una frase breve di JARVIS in italiano (la lingua scelta, i turni).
    func annuncia(_ testo: String) {
        guard fase == .attesa else { return }
        Task {
            fase = .parlo
            await parla(testo, lingua: Lingua.italiano)
            fase = .attesa
            stato = "PRONTO"
        }
    }

    private func parla(_ testo: String, lingua: Lingua) async {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? s.setActive(true)
        if Impostazioni.voceCloud, let url = URL(string: Impostazioni.indirizzo) {
            let (dati, _) = await VoceCloud.scarica(testo, id: Impostazioni.idVoceCloud, url: url, token: Portachiavi.leggi())
            if let dati, let p = try? AVAudioPlayer(data: dati) {
                p.delegate = self
                lettore = p
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    attesaVoce = c
                    if !p.play() { rilasciaVoce() }
                }
                return
            }
        }
        let u = AVSpeechUtterance(string: testo)
        u.voice = AVSpeechSynthesisVoice(language: lingua.locale) ?? AVSpeechSynthesisVoice(language: String(lingua.locale.prefix(2)))
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            attesaVoce = c
            sintesi.speak(u)
        }
    }

    fileprivate func rilasciaVoce() {
        let c = attesaVoce
        attesaVoce = nil
        lettore = nil
        c?.resume()
    }

    // MARK: Ponti

    nonisolated private static func collega(_ input: AVAudioInputNode, formato: AVAudioFormat, a r: SFSpeechAudioBufferRecognitionRequest) {
        nonisolated(unsafe) let richiesta = r
        input.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in richiesta.append(buffer) }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in esito(ris?.bestTranscription.formattedString, ris?.isFinal ?? false, err != nil) }
    }

    static func traduci(_ testo: String, da: String, a: String) async -> String? {
        guard let url = URL(string: Impostazioni.indirizzo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["traduci": testo, "da": da, "a": a])
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o["traduzione"] as? String
    }
}

extension MotoreInterprete: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) { Task { @MainActor in self.rilasciaVoce() } }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: (any Error)?) { Task { @MainActor in self.rilasciaVoce() } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.rilasciaVoce() } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.rilasciaVoce() } }
}
#endif
