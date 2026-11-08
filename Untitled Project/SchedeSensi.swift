#if os(iOS)
import Foundation
import SwiftUI
import Combine
import Charts
import MusicKit
import UIKit
import WebKit          // 8 nov: il lettore di YouTube del player passa il suo WKWebView ad AscoltoShazam

// MARK: - SHAZAM (MARK X): logo olografico in ascolto, poi sale il player che la suona subito su Apple Music

struct VistaShazam: View {
    let chiedi: (String) -> Void
    var apriMusica: () -> Void = {}
    private let tinta = Tinte.shazam

    nonisolated struct Trovata: Codable, Identifiable, Sendable {
        var id = UUID()
        let titolo: String
        let artista: String
        let album: String?
        let copertina: URL?
        let link: URL?
        let generi: [String]
        let quando: Date
        var appleMusicID: String? = nil
    }

    enum Stato: Equatable { case fermo, ascolto, trovata, niente(String) }
    /// 5 nov (il signore: «Shazam deve attivarsi quando tocco il logo, invece parte da solo»): aperto dall'icona aspetta il tocco
    /// sul logo; chiesto a voce («Jarvis, che canzone è?», «Jarvis, shazam») ascolta subito, come nel mockup (ASCOLTA). Lo mette
    /// ContentView prima di aprirlo (o di riportarlo davanti).
    static var ascoltaSubito = false

    @State private var stato: Stato = .fermo
    @State private var storico: [Trovata] = []
    @State private var chiediCancella = false
    @State private var daEliminare: UUID?               // 8 nov (scelta del signore): la canzone che aspetta CONFERMA, 3 s
    @State private var giroElimina = 0
    @State private var lampo = false                    // il lampo del logo quando la trova
    @State private var aperta: Trovata?                 // il player
    @ObservedObject private var ascolto = AscoltoShazam.condiviso   // 8 nov: da dove si ascolta (Apple Music, anteprima, YouTube)
    @State private var inLibreria = Set<String>()
    @State private var giu: CGFloat = 0                 // lo swipe giù del player
    @State private var mini = false                     // 8 nov: il player tirato giù diventa il mini-player in fondo
    @ObservedObject private var lettore = LettoreMusica.condiviso
    @Environment(\.sezioneDietro) private var dietro    // 4 nov: dietro (MARK XI) il logo olografico si ferma

    var body: some View {
        CorniceScheda(titolo: "Shazam", sottotitolo: sottotitolo, icona: "shazam.logo", tinta: tinta) {
            logoOlografico
            if case .niente(let motivo) = stato {
                Text(motivo).font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            if !storico.isEmpty {
                Pannello(titolo: "RICONOSCIUTE · \(storico.count)", tinta: tinta) {
                    ForEach(storico) { t in rigaStorico(t) }
                    Button(role: .destructive) { Suoni.schedaApre(); withAnimation(.salitaFoglio) { chiediCancella = true } } label: {
                        Label("Cancella la cronologia", systemImage: "trash").font(.footnote)
                    }
                    .tint(.red).padding(.top, 4)
                }
            }
            // 8 nov (controllo): col mini-player in fondo le ultime canzoni restavano sotto e non si toccavano: lo spazio del mini
            if aperta != nil && mini { Color.clear.frame(height: 84).accessibilityHidden(true) }
        }
        .overlay(alignment: .bottom) { if let t = aperta { player(t) } }
        .onAppear { storico = VistaShazam.leggi() }
        .task {
            guard VistaShazam.ascoltaSubito else { return }                // dall'icona: aspetta il tocco sul logo
            VistaShazam.ascoltaSubito = false
            try? await Task.sleep(for: .seconds(Apertura.caricamento + 0.8))   // dopo i suoni d'apertura (il microfono cambia l'audio)
            guard !Task.isCancelled else { return }
            await ascolta()
        }
        // già aperto (davanti o dietro) e chiesto di nuovo a voce: ascolta lì, sul posto (strada B)
        .onReceive(NotificationCenter.default.publisher(for: .jarvisRichiestaSezione)) { n in
            guard (n.userInfo?["reparto"] as? String) == Reparto.shazam.rawValue, VistaShazam.ascoltaSubito else { return }
            VistaShazam.ascoltaSubito = false
            guard stato != .ascolto else { return }
            Task { await ascolta() }
        }
        .task { await lettore.segui() }
        // 8 nov (scelta del signore): «CANCELLARE TUTTO?» olografico come lo Scanner del mockup (prima la domanda di iOS)
        .domandaCancella($chiediCancella, sotto: "\(storico.count) canzoni riconosciute",
                         nota: "Si cancella solo la cronologia di Shazam sull'iPhone. Per una sola: ELIMINA sulla sua riga.") {
            Suoni.pronto()
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) { storico = [] }
            VistaShazam.salva([])
        }
    }

    private var sottotitolo: String {
        switch stato {
        case .fermo: return "tocchi il logo per ascoltare"
        case .ascolto: return "ascolto la musica…"
        case .trovata: return aperta == nil ? "trovata" : "trovata · \(AscoltoShazam.scritta(ascolto.fonte).lowercased())"
        case .niente: return "non riconosciuta"
        }
    }

    // MARK: il logo olografico (come nel mockup: 9 strati, oscilla di ±38°, gira tutto mentre ascolta, lampo quando la trova)

    private var logoOlografico: some View {
        Button { Task { await ascolta() } } label: {
            TimelineView(.animation(paused: UIAccessibility.isReduceMotionEnabled || dietro)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let ascolto = stato == .ascolto
                let angolo = ascolto ? (t * 160).truncatingRemainder(dividingBy: 360) : sin(t * 0.9) * 38
                let rad = angolo * .pi / 180
                ZStack {
                    spettro(t: t, vivo: ascolto).frame(width: 230, height: 230)
                    ForEach(0..<9, id: \.self) { k in
                        Image(systemName: "shazam.logo")
                            .font(.system(size: 88, weight: .thin))
                            .foregroundStyle(tinta.opacity(k == 4 ? 0.95 : 0.16))
                            .offset(x: CGFloat(k - 4) * 2.2 * CGFloat(sin(rad)))            // gli strati: la profondità dell'ologramma
                            .rotation3DEffect(.degrees(angolo), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    }
                    .shadow(color: tinta.opacity(ascolto ? 0.9 : 0.55), radius: ascolto ? 18 : 10)
                    if ascolto {                                                         // la scansione che attraversa il logo
                        let y = CGFloat((t * 0.8).truncatingRemainder(dividingBy: 1)) * 150 - 75
                        Rectangle().fill(tinta.opacity(0.35)).frame(width: 130, height: 2).blur(radius: 1).offset(y: y)
                    }
                    Circle().fill(.white).frame(width: 150, height: 150).opacity(lampo ? 0.55 : 0).blur(radius: 18)
                }
            }
            .frame(width: 240, height: 240)
            .contentShape(Circle())
        }
        .buttonStyle(StileStark())
        .disabled(stato == .ascolto)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel(stato == .ascolto ? "Ascolto" : "Ascolta")
    }

    /// Lo spettro attorno al logo: fermo e tenue a riposo, vivo mentre ascolta.
    private func spettro(t: Double, vivo: Bool) -> some View {
        Canvas { c, size in
            let centro = CGPoint(x: size.width / 2, y: size.height / 2), r0 = size.width * 0.36
            for i in 0..<64 {
                let a = Double(i) / 64 * 2 * .pi
                let h = vivo ? 6 + 16 * abs(sin(t * 3.1 + Double(i) * 0.61) * cos(t * 1.7 + Double(i) * 0.23)) : 3
                var p = Path()
                p.move(to: CGPoint(x: centro.x + cos(a) * r0, y: centro.y + sin(a) * r0))
                p.addLine(to: CGPoint(x: centro.x + cos(a) * (r0 + h), y: centro.y + sin(a) * (r0 + h)))
                c.stroke(p, with: .color(tinta.opacity(vivo ? 0.75 : 0.25)), lineWidth: 2)
            }
        }
    }

    // MARK: il player (sale da sotto; si chiude con «Chiudi» o uno swipe giù), come il mockup (.sz-player)
    // 8 nov (il signore: «un player per ascoltarla o su Apple Music o YouTube, come Vinyl Hustler»): in alto la fonte (APPLE MUSIC,
    // APPLE · ANTEPRIMA 30 S, YOUTUBE) e l'ora in cui è stata riconosciuta; la copertina grande con l'anello che gira mentre suona
    // (col video di YouTube al suo posto); −15 · PLAY · +15; LIBRERIA · YOUTUBE (o APPLE) · MUSICA.

    private func player(_ t: Trovata) -> some View {
        // 8 nov (controllo): tirato giù, il video di YouTube si chiudeva (la musica si fermava) e riaprendolo ripartiva da capo.
        // Ora il player pieno resta vivo sotto il mini, nascosto e senza tocchi: il video continua e si riapre dov'era.
        ZStack(alignment: .bottom) {
            playerPieno(t)
                .opacity(mini ? 0 : 1)
                .allowsHitTesting(!mini)
                .accessibilityHidden(mini)
            if mini { miniPlayer(t) }
        }
        .frame(maxWidth: 560)
        .offset(y: max(0, giu))
        .gesture(DragGesture()
            .onChanged { giu = $0.translation.height }
            .onEnded { v in
                if v.translation.height > 90 || v.predictedEndTranslation.height > 260 {
                    Suoni.tocco()
                    if mini { chiudiPlayer() }                                            // giù dal mini: si chiude
                    else { withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)) { mini = true; giu = 0 } }   // giù dal pieno: il mini
                } else { withAnimation(.spring(duration: 0.3)) { giu = 0 } }
            })
        .transition(.move(edge: .bottom))
    }

    // 8 nov (il signore, 04:07: «il player non deve andare così sopra l'ologramma col logo di Shazam… e posso tirarlo giù»): come il
    // mockup v284 — compatto, sotto l'anello del logo (copertina 96 accanto al titolo, con l'anello di luce che gira mentre suona);
    // YOUTUBE: il video a tutta larghezza sopra il titolo; tirato giù diventa il mini-player, toccato si riapre.
    private func playerPieno(_ t: Trovata) -> some View {
        let video = ascolto.fonte == .video
        return VStack(spacing: 12) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5)
            HStack {
                Text("\(AscoltoShazam.scritta(ascolto.fonte)) · RICONOSCIUTA ALLE \(t.quando.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(tinta.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Button("Chiudi") { Suoni.tocco(); chiudiPlayer() }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(tinta)
            }
            if video, let id = ascolto.videoID {
                LettoreYouTube(id: id, pronto: { ascolto.agganciaVideo($0) })
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: tinta.opacity(0.25), radius: 15)
                    .id(id)
            }
            HStack(spacing: 14) {
                if !video { copertina(t, lato: 96, raggio: 12, ferma: mini) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.titolo).font(.system(size: 19, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    Text(sottoTitolo(t)).font(.system(size: 13)).foregroundStyle(Color(red: 0.62, green: 0.70, blue: 0.73)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if ascolto.cercando { ProgressView().tint(tinta) }
            }
            if !video {
                barraTempo
                HStack(spacing: 26) {
                    Button { Suoni.tocco(); ascolto.salta(-15) } label: { Text("−15").font(.system(size: 13, weight: .bold, design: .monospaced)) }
                        .accessibilityLabel("Indietro 15 secondi")
                    Button { Suoni.tocco(); Task { await ascolto.playPausa() } } label: {
                        Image(systemName: ascolto.suonaOra ? "pause.fill" : "play.fill")
                            .font(.system(size: 26)).foregroundStyle(Color(red: 0, green: 0.094, blue: 0.125))
                            .frame(width: 64, height: 64).background(Circle().fill(tinta))
                            .shadow(color: tinta.opacity(0.5), radius: 11)
                    }
                    .accessibilityLabel(ascolto.suonaOra ? "Pausa" : "Riproduci")
                    Button { Suoni.tocco(); ascolto.salta(15) } label: { Text("+15").font(.system(size: 13, weight: .bold, design: .monospaced)) }
                        .accessibilityLabel("Avanti 15 secondi")
                }
                .foregroundStyle(tinta)
            }
            HStack(spacing: 8) {
                let gia = ascolto.brano.map { inLibreria.contains($0.id.rawValue) } ?? false
                ChipOlo(testo: gia ? "IN LIBRERIA ✓" : "LIBRERIA", acceso: false) { Suoni.tocco(); Task { await aggiungiLibreria() } }
                    .disabled(ascolto.brano == nil || gia).opacity(ascolto.brano == nil ? 0.45 : 1)
                ChipOlo(testo: video ? "APPLE" : "YOUTUBE", acceso: false) {
                    Suoni.tocco()
                    Task {
                        if video { await ascolto.tornaApple(titolo: t.titolo, artista: t.artista, appleID: t.appleMusicID) }
                        else { await ascolto.video(titolo: t.titolo, artista: t.artista) }
                    }
                }
                ChipOlo(testo: "MUSICA", acceso: false) { Suoni.tocco(); chiudiPlayer(); apriMusica() }
            }
            if let e = ascolto.errore ?? (ascolto.fonte == .intero ? lettore.errore : nil) {
                Text(e).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
        .buttonStyle(StileStark())
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 26)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(LinearGradient(colors: [Color(red: 6 / 255, green: 20 / 255, blue: 26 / 255).opacity(0.98),
                                              Color(red: 2 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.99)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(tinta.opacity(0.45)).frame(height: 1) }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                .shadow(color: tinta.opacity(0.12), radius: 20, y: -10)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Il mini-player (come .sz-player.mini del mockup): copertina, titolo, PLAY/PAUSA. Toccato si riapre; tirato giù si chiude.
    private func miniPlayer(_ t: Trovata) -> some View {
        HStack(spacing: 12) {
            copertina(t, lato: 44, raggio: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.titolo).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(sottoTitolo(t)).font(.system(size: 11)).foregroundStyle(Color(red: 0.62, green: 0.70, blue: 0.73)).lineLimit(1)
            }
            Spacer(minLength: 0)
            // 8 nov (controllo): anche col video di YouTube, come il mockup (prima il mini del video non aveva il tasto)
            Button { Suoni.tocco(); Task { await ascolto.playPausa() } } label: {
                Image(systemName: ascolto.suonaOra ? "pause.fill" : "play.fill")
                    .font(.system(size: 17)).foregroundStyle(Color(red: 0, green: 0.094, blue: 0.125))
                    .frame(width: 40, height: 40).background(Circle().fill(tinta))
                    .shadow(color: tinta.opacity(0.45), radius: 7)
            }
            .buttonStyle(StileStark())
            .accessibilityLabel(ascolto.suonaOra ? "Pausa" : "Riproduci")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(red: 6 / 255, green: 20 / 255, blue: 26 / 255).opacity(0.98),
                                              Color(red: 2 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.99)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(tinta.opacity(0.45), lineWidth: 1))
                .shadow(color: tinta.opacity(0.12), radius: 14)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { Suoni.tocco(); withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) { mini = false } }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Riapre il player")
    }

    private func sottoTitolo(_ t: Trovata) -> String {
        [t.artista, t.album, ascolto.brano?.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }].compactMap { $0 }.joined(separator: " · ")
    }

    /// La copertina grande (come .sz-p-cop): leggermente più piccola da ferma, l'anello di luce che gira mentre suona.
    private func copertina(_ t: Trovata, lato: CGFloat, raggio: CGFloat, ferma: Bool = false) -> some View {
        let suona = ascolto.suonaOra
        return TimelineView(.animation(paused: !suona || ferma || UIAccessibility.isReduceMotionEnabled || dietro)) { tl in
            let giro = tl.date.timeIntervalSinceReferenceDate * 9          // 1 giro in 40 s, come il mockup (ts / 40)
            ZStack {
                // 8 nov: gira la LUCE lungo il bordo, non il bordo (girando il quadrato gli angoli uscivano storti)
                RoundedRectangle(cornerRadius: raggio + 4)
                    .strokeBorder(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.7),
                                                          .init(color: tinta.opacity(0.7), location: 0.85), .init(color: .clear, location: 1)],
                                                  center: .center, angle: .degrees(giro.truncatingRemainder(dividingBy: 360))), lineWidth: 1.5)
                    .frame(width: lato + (lato > 60 ? 12 : 8), height: lato + (lato > 60 ? 12 : 8))
                    .opacity(suona ? 1 : 0)
                AsyncImage(url: t.copertina) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: lato, height: lato).clipShape(RoundedRectangle(cornerRadius: raggio))
                    .shadow(color: tinta.opacity(0.22), radius: lato > 60 ? 11 : 4)
                    .scaleEffect(suona ? 1 : 0.94)
                    .animation(.easeOut(duration: 0.5), value: suona)
            }
        }
        .frame(width: lato, height: lato)
    }

    private var barraTempo: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let d = ascolto.durata ?? 0, now = ascolto.tempo, f = d > 0 ? min(1, now / d) : 0
            VStack(spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(tinta).frame(width: g.size.width * f)
                    }
                    .frame(height: 4).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in ascolto.vaiA(v.location.x / max(1, g.size.width)) })
                }
                .frame(height: 22)
                HStack {
                    Text(VistaShazam.mmss(now)); Spacer(); Text(d > 0 ? "-" + VistaShazam.mmss(max(0, d - now)) : "--:--")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.tenue)
            }
        }
    }

    nonisolated static func mmss(_ s: Double) -> String { let x = Int(max(0, s)); return String(format: "%d:%02d", x / 60, x % 60) }

    private func chiudiPlayer() {
        ascolto.chiudi()                                                          // anteprima e video si fermano; Apple Music continua
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) { aperta = nil; giu = 0; mini = false }
    }

    private func rigaStorico(_ t: Trovata) -> some View {
        HStack(spacing: 10) {
            Button { Task { await suona(t) } } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: t.copertina) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.titolo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(t.artista).font(.system(size: 12)).foregroundStyle(tinta).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(t.quando.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                    Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(tinta)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 8 nov (scelta del signore, «Shazam: ELIMINA › CONFERMA»): come lo Scanner e l'archivio di LiDAR, CONFERMA per 3 s
            let sicuro = daEliminare == t.id
            let rosso = Color(red: 1, green: 107 / 255, blue: 107 / 255)                                    // #ff6b6b
            Button { elimina(t) } label: {
                Text(sicuro ? "CONFERMA" : "ELIMINA")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(sicuro ? rosso : Color.ciano)
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(sicuro ? rosso.opacity(0.6) : Color.ciano.opacity(0.3), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(StileStark())
            .accessibilityLabel(sicuro ? "Conferma: elimina \(t.titolo)" : "Elimina \(t.titolo)")
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
        .contextMenu {
            Button { chiedi("Raccontami qualcosa di «\(t.titolo)» di \(t.artista): l'anno, la storia, e se c'è un vinile da cercare su Discogs.") } label: { Label("Chieda a JARVIS", systemImage: "waveform") }
            Button(role: .destructive) { storico.removeAll { $0.id == t.id }; VistaShazam.salva(storico) } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    /// Il primo tocco su ELIMINA chiede CONFERMA per 3 secondi (come lo Scanner), il secondo elimina la canzone, solo quella.
    private func elimina(_ t: Trovata) {
        guard daEliminare == t.id else {
            Suoni.tocco()
            daEliminare = t.id
            giroElimina += 1
            let mio = giroElimina
            Task { try? await Task.sleep(for: .seconds(3)); if giroElimina == mio { daEliminare = nil } }
            return
        }
        Suoni.pronto()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
        daEliminare = nil
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) { storico.removeAll { $0.id == t.id } }
        VistaShazam.salva(storico)
    }

    // MARK: ascolto, riproduzione, libreria

    private func ascolta() async {
        guard stato != .ascolto else { return }
        // 8 nov (controllo): col player aperto spariva solo il player e l'anteprima continuava senza comandi (e Shazam la sentiva).
        // Ora si chiude come con «Chiudi» (anteprima e video si fermano), come ASCOLTA nel mockup.
        if aperta != nil { chiudiPlayer() }
        withAnimation { stato = .ascolto }
        switch await Musica.riconosci(secondi: 12) {
        case .trovato(let b):
            let t = Trovata(titolo: b.titolo, artista: b.artista, album: b.album, copertina: b.copertina, link: b.appleMusic ?? b.web,
                            generi: b.generi, quando: Date(), appleMusicID: b.appleMusicID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Suoni.pronto()
            // 8 nov (controllo): acceso e spento nello stesso istante SwiftUI non lo disegnava mai: si spegne quando è acceso
            withAnimation(.easeOut(duration: 0.15)) { stato = .trovata; lampo = true } completion: {
                withAnimation(.easeOut(duration: 0.6)) { lampo = false }
            }
            storico.insert(t, at: 0)
            VistaShazam.salva(storico)
            await suona(t)
        case .nessuno:
            withAnimation { stato = .niente("Non la riconosco, Sir: forse la musica è troppo bassa o c'è troppo rumore. Ritocchi il logo.") }
        case .errore(let e):
            withAnimation { stato = .niente("Shazam non risponde: \(e).") }
        }
    }

    /// Sale il player e la canzone parte dalla fonte migliore: Apple Music intero (permesso e abbonamento), se no l'anteprima di
    /// 30 secondi, se no il video di YouTube (AscoltoShazam).
    private func suona(_ t: Trovata) async {
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)) { aperta = t; giu = 0; mini = false }
        await ascolto.suona(titolo: t.titolo, artista: t.artista, appleID: t.appleMusicID)
    }

    private func aggiungiLibreria() async {
        guard let s = ascolto.brano else { return }
        do {
            try await MusicLibrary.shared.add(s)
            inLibreria.insert(s.id.rawValue)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            ascolto.errore = "Non riesco ad aggiungerla alla libreria: \(error.localizedDescription)"
        }
    }

    private static let chiave = "shazamTrovate"
    static func leggi() -> [Trovata] {
        guard let d = UserDefaults.standard.data(forKey: chiave) else { return [] }
        return (try? JSONDecoder().decode([Trovata].self, from: d)) ?? []
    }
    static func salva(_ t: [Trovata]) {
        if let d = try? JSONEncoder().encode(Array(t.prefix(200))) { UserDefaults.standard.set(d, forKey: chiave) }
    }
}

// MARK: - FOTO: la galleria, con la ricerca per contenuto e periodo

struct VistaFotoScheda: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.foto

    enum Periodo: String, CaseIterable, Identifiable {
        case oggi = "Oggi", ieri = "Ieri", settimana = "7 giorni", mese = "30 giorni", tutte = "Tutte"
        var id: String { rawValue }
        var intervallo: (Date?, Date?) {
            let cal = Calendar.current
            let oggi = cal.startOfDay(for: Date())
            switch self {
            case .oggi: return (oggi, nil)
            case .ieri: return (oggi.addingTimeInterval(-86_400), oggi)
            case .settimana: return (oggi.addingTimeInterval(-7 * 86_400), nil)
            case .mese: return (oggi.addingTimeInterval(-30 * 86_400), nil)
            case .tutte: return (nil, nil)
            }
        }
    }

    // 4 nov: le parole le capisce DizionarioFoto (tutte le 1.303 categorie di Apple in italiano, con i plurali, parole intere;
    // selfie, screenshot, preferite e ritratti sono gli album di Apple). Prima erano una trentina e alcune non esistevano.

    @State private var periodo: Periodo = .oggi
    @State private var cerca = ""
    @State private var foto: [Immagine]?
    @State private var nota: String?
    @State private var aperta: Int?
    @State private var limitato = false
    @ObservedObject private var analisi = AvanzamentoFoto.condiviso       // il conto dell'analisi della galleria
    // 11.0 (3), come il mockup approvato: il pannello dell'analisi in ologramma, le parole capite, i quadratini che si materializzano
    @State private var pannello = false
    @State private var completa = false
    @State private var capite: [String] = []
    @State private var ritardi: [String: Double] = [:]
    @State private var quandoRisultati = Date.distantPast
    @State private var apertaIl = Date()
    @Environment(\.accessibilityReduceMotion) private var riduci
    @Environment(\.sezioneDietro) private var dietro    // dietro (MARK XI) la rilettura delle foto si ferma

    var body: some View {
        CorniceScheda(titolo: "Foto", sottotitolo: foto.map { "\($0.count) foto · \(periodo.rawValue.lowercased())" } ?? "sfoglio la galleria", icona: "photo.on.rectangle", tinta: tinta, pronto: foto != nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Periodo.allCases) { p in
                        Button { Suoni.tocco(); periodo = p } label: {
                            Text(p.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(periodo == p ? Color.fondo : tinta)
                                .background(periodo == p ? tinta : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(tinta.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(tinta)
                TextField("Cosa cerca? cane, mare, concerto, vinile…", text: $cerca).foregroundStyle(.white).submitLabel(.search)
                if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
            }
            .padding(12)
            .background(tinta.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 11.0 (3): le cose capite, in fila col «+» (devono esserci tutte nella foto)
            if !capite.isEmpty {
                ParoleCapite(parole: capite, tinta: tinta).padding(.top, -6)
            }
            // l'analisi di tutta la galleria (una volta sola, poi solo le foto nuove), in ologramma. 7 nov sera (il signore, scelta A):
            // SEMPRE visibile: mentre va avanti il conto; finita «ANALISI COMPLETA · N FOTO» e l'ologramma che rilegge le ultime foto
            if pannello {
                PannelloAnalisi(analisi: analisi, tinta: tinta, completa: completa)
                    .transition(.opacity)
            }
            // 4 nov: con l'accesso limitato JARVIS vede solo le foto scelte: si dice, e un tocco apre le Impostazioni
            if limitato {
                Button {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                } label: {
                    Text("Accesso limitato: vedo solo le foto che ha scelto lei. Per cercare in tutta la galleria: Impostazioni › App › Jarvis › Foto › Accesso completo.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if let foto {
                if foto.isEmpty || nota != nil {
                    Text(nota ?? "Nessuna foto in questo periodo.").font(.footnote).foregroundStyle(Color.tenue)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                    ForEach(Array(foto.enumerated()), id: \.element.id) { k, f in
                        Button { aperta = k } label: {
                            Miniatura(immagine: f, lato: 300)
                                .frame(minHeight: 104, maxHeight: 104)
                                .clipped()
                                .modifier(Materializza(ritardo: ritardi[f.id], quando: quandoRisultati))   // le foto nuove: col laser
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                // la foto riempita sborda dal quadratino: senza questa riga il tocco prendeva anche la parte tagliata
                                // (che copriva il campo «Cerca» sopra la prima riga)
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !foto.isEmpty {
                    TastoJarvis(testo: "Racconta la giornata in foto", icona: "waveform", tinta: tinta) {
                        chiedi("Guarda le mie foto di \(periodo == .tutte ? "recente" : periodo.rawValue.lowercased())\(cerca.isEmpty ? "" : " con \(cerca)") e raccontamele in breve.")
                    }
                }
            } else {
                AttesaAnello(tinta: tinta).frame(maxWidth: .infinity).padding(.top, 40)   // 8 nov: l'anello del mockup (.attesa-l)
            }
        }
        // la ricerca si ripete mentre l'analisi della galleria va avanti (ogni 400 foto): escono anche le foto appena analizzate
        .task(id: "\(periodo.rawValue)|\(cerca)|\(cerca.isEmpty ? 0 : analisi.passo)") {
            try? await Task.sleep(for: .milliseconds(cerca.isEmpty ? 0 : 450))
            if !Task.isCancelled { await carica() }
        }
        .onAppear { apertaIl = Date(); aggiornaPannello() }
        .onChange(of: analisi.fatte) { _, _ in aggiornaPannello() }
        .onChange(of: analisi.attivo) { _, _ in aggiornaPannello() }
        .onChange(of: analisi.totale) { _, _ in aggiornaPannello() }
        // a galleria finita l'ologramma rilegge le ultime 30 foto, una ogni 1,5 s, solo con la sezione aperta e davanti
        .task(id: pannello && completa && !dietro) {
            guard pannello, completa, !dietro else { return }
            analisi.rileggendo(true)
            defer { analisi.rileggendo(false) }
            var k = 0
            while !Task.isCancelled {
                if let c = await IndiceFoto.condiviso.rileggi(k), !Task.isCancelled { analisi.mostra(c) }
                k = (k + 1) % 30
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        // 4 nov: quando si comincia a scrivere si cerca in tutta la galleria (poi un periodo toccato restringe la ricerca)
        .onChange(of: cerca) { prima, adesso in
            let vuota = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
            if vuota(prima) && !vuota(adesso) && periodo != .tutte { periodo = .tutte }
        }
        .fullScreenCover(isPresented: Binding(get: { aperta != nil }, set: { if !$0 { aperta = nil } })) {
            if let foto, let k = aperta { VistaImmagini(immagini: foto, iniziale: k) }
        }
        .chiudiFoglioDietro { aperta = nil }                    // 4 nov: il visore (iOS) non resta sopra la sezione che sale
    }

    private func carica() async {
        guard await FotoLocali.autorizza() else { nota = "Serve l'accesso alle foto: Impostazioni › App › Jarvis › Foto."; foto = []; return }
        limitato = FotoLocali.accessoLimitato
        let (da, a) = periodo.intervallo
        let c = cerca.trimmingCharacters(in: .whitespaces)
        let esito = await FotoLocali.cercaTesto(c, da: da, a: a, quante: c.isEmpty ? 120 : 300)
        guard !Task.isCancelled else { return }                        // un'altra ricerca è già partita
        nota = esito.nota
        let nuove = esito.trovate.map { Immagine(fonte: "Le sue foto", locale: $0) }
        // le foto che arrivano adesso (non quelle già a schermo) si materializzano una dopo l'altra; non sotto il caricamento
        // della sezione e non con «Riduci movimento»
        var r: [String: Double] = [:]
        if Date().timeIntervalSince(apertaIl) > 1.15 && !riduci {
            let gia = Set((foto ?? []).map { $0.id })                     // quelle già nella griglia restano come sono
            var k = 0
            for f in nuove where !gia.contains(f.id) { r[f.id] = Double(min(k, 16)) * 0.026; k += 1 }
        }
        ritardi = r
        quandoRisultati = Date()
        withAnimation(.easeOut(duration: 0.25)) { foto = nuove }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34)) { capite = esito.capite }
    }

    /// Il pannello dell'analisi, sempre visibile (7 nov sera, il signore: scelta A): appena c'è la galleria si apre; mentre l'analisi va
    /// avanti il conto, quando finisce davanti a lui dice «ANALISI COMPLETA» col suono «pronto» e resta, con la rilettura delle ultime
    /// foto. Se arrivano foto nuove da leggere torna al conto.
    private func aggiornaPannello() {
        if !pannello {
            guard analisi.totale > 0 else { return }
            completa = !analisi.attivo
            withAnimation(.easeOut(duration: 0.3)) { pannello = true }
        } else if !analisi.attivo && !completa {
            completa = true
            Suoni.fatto()
        } else if analisi.attivo && completa {
            completa = false
        }
    }

}

// MARK: - SERATA: i conti di una serata Discosizer

struct VistaSerata: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.serata

    struct Serata: Identifiable, Hashable {
        let id: String
        let nome: String
        let data: String
        let chiusa: Bool
        var giorno: Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: String(data.prefix(10)))
        }
        var prova: Bool { nome.lowercased().contains("demo") || nome.lowercased().contains("prova") }
    }

    @State private var serate: [Serata] = []
    @State private var scelta: Serata?
    @State private var conti: [String: Any]?
    @State private var errore: String?

    var body: some View {
        CorniceScheda(titolo: "Serata", sottotitolo: scelta.map { "\($0.nome) · \($0.giorno?.formatted(date: .abbreviated, time: .omitted) ?? $0.data)" } ?? "apro i conti",
                      icona: "music.note.list", tinta: tinta, pronto: conti != nil || errore != nil) {
            if !serate.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(serate) { s in
                            Button { Suoni.tocco(); scelta = s } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.nome).font(.system(size: 12, weight: .bold)).lineLimit(1)
                                    Text(s.giorno?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) ?? s.data)
                                        .font(.system(size: 10, design: .monospaced))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(scelta == s ? Color.fondo : tinta)
                                .background(scelta == s ? tinta : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.5), lineWidth: 1))
                                .opacity(s.prova ? 0.55 : 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let c = conti { riepilogo(c) }
            else if let errore { Text(errore).font(.footnote).foregroundStyle(.orange) }
            else { AttesaAnello(tinta: tinta).frame(maxWidth: .infinity).padding(.top, 40) }   // 8 nov: l'anello del mockup (.attesa-l)
        }
        .task { await caricaElenco() }
        .task(id: scelta?.id) { if let s = scelta { await carica(s) } }
        .sulloSchermo(testoSchermo)
    }

    /// 8 nov notte: cosa vede JARVIS della Serata (la serata scelta e i suoi conti come sono a schermo).
    private var testoSchermo: String {
        guard let s = scelta else { return Schermo.unisci("Serata", [errore.map { "errore: \($0)" } ?? "i conti si stanno aprendo"]) }
        let quale = "serata scelta: \(s.nome) del \(s.data)" + (s.chiusa ? " (chiusa)" : " (aperta)")
        let numeri: String
        if let conti { numeri = "conti a schermo: " + Schermo.esito(conti, massimo: 1500) }
        else { numeri = errore.map { "errore: \($0)" } ?? "conti in caricamento" }
        return Schermo.unisci("Serata", [quale, numeri])
    }

    private func n(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }
    private func euro(_ v: Double) -> String { v.formatted(.currency(code: "EUR").precision(.fractionLength(0))) }

    @ViewBuilder private func riepilogo(_ c: [String: Any]) -> some View {
        let tot = c["totali"] as? [String: Any] ?? [:]
        let ing = c["ingressi"] as? [String: Any] ?? [:]
        let bar = c["bar"] as? [String: Any] ?? [:]
        let spese = c["spese"] as? [String: Any] ?? [:]
        let margine = n(tot["margine_netto_iva"])

        Pannello(tinta: tinta) {
            Text("INCASSO LORDO").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            Text(euro(n(tot["incasso_lordo"]))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(.white)
            HStack {
                Text("Netto IVA \(euro(n(tot["incasso_netto_iva"])))").font(.system(size: 12)).foregroundStyle(Color.tenue)
                Spacer()
                Text("Margine \(euro(margine))")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(margine >= 0 ? Color(red: 0.45, green: 0.92, blue: 0.6) : Color(red: 1.0, green: 0.45, blue: 0.4))
            }
        }

        HStack(spacing: 10) {
            Valore(titolo: "INGRESSI", valore: euro(n(tot["ingressi_lordo"])), sotto: "\(Int(n(ing["biglietti_totali"]))) biglietti", tinta: tinta)
            Valore(titolo: "BAR", valore: euro(n(tot["bar_lordo"])), sotto: "contanti \(euro(n(bar["contanti"]))) · POS \(euro(n(bar["pos"])))", tinta: tinta)
        }

        Pannello(titolo: "DA DOVE ARRIVANO I SOLDI", tinta: tinta, olografico: true) {
            let fette: [(String, Double)] = [("Ingressi contanti", n(ing["contanti"])), ("Ingressi POS", n(ing["pos"])),
                                              ("Resident Advisor", n(ing["resident_advisor"])), ("Bar contanti", n(bar["contanti"])), ("Bar POS", n(bar["pos"]))].filter { $0.1 > 0 }
            if fette.isEmpty { Text("Nessun incasso registrato.").font(.footnote).foregroundStyle(Color.tenue) }
            else {
                // 11.0 (6), come il mockup v264: l'ologramma dei soldi con le sue tre prove (FLUSSO, TORRI, REATTORE), scelte con le
                // chip; sotto, voce per voce, quanto e che parte del totale
                OlogrammaSerataProve(dati: DatiSoldi(fonti: fette.map { DatiSoldi.Fonte(nome: $0.0, valore: $0.1) }))
                    .id(scelta?.id)                              // un'altra serata: la prova riparte da capo
                legendaSoldi(fette)
            }
        }

        if let venduti = bar["venduti"] as? [String: Any] {
            let righe = ["drink", "birra", "acqua", "chupito", "analcolico"].map { ($0.capitalized, n(venduti[$0])) }.filter { $0.1 > 0 }
            if !righe.isEmpty {
                Pannello(titolo: "BAR · PEZZI VENDUTI", tinta: tinta) {
                    Chart(righe, id: \.0) { nome, v in
                        BarMark(x: .value("Pezzi", v), y: .value("Cosa", nome)).foregroundStyle(tinta.gradient).cornerRadius(4)
                            .annotation(position: .trailing) { Text("\(Int(v))").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white) }
                    }
                    .frame(height: CGFloat(righe.count) * 30 + 10)
                }
            }
        }

        if let cat = spese["per_categoria"] as? [String: Any], !cat.isEmpty {
            let righe = cat.map { ($0.key.capitalized, n($0.value)) }.sorted { $0.1 > $1.1 }
            Pannello(titolo: "SPESE · \(euro(n(spese["totale"])))", tinta: tinta) {
                ForEach(righe, id: \.0) { nome, v in
                    HStack {
                        Text(nome).font(.system(size: 14)).foregroundStyle(.white)
                        Spacer()
                        Text(euro(v)).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                    }
                }
            }
        }

        if let b = ing["biglietti_per_prezzo"] as? [[String: Any]], !b.isEmpty {
            Pannello(titolo: "BIGLIETTI PER PREZZO", tinta: tinta) {
                ForEach(Array(b.enumerated()), id: \.offset) { _, x in
                    HStack {
                        Text(euro(n(x["prezzo"]))).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                        Spacer()
                        Text("× \(Int(n(x["quantita"])))").font(.system(size: 14, design: .monospaced)).foregroundStyle(.white)
                    }
                }
            }
        }

        if let note = c["note"] as? String { Text(note).font(.system(size: 11)).foregroundStyle(Color.tenue) }
        TastoJarvis(testo: "Analisi di JARVIS", icona: "waveform", tinta: tinta) {
            chiedi("Analizzami la serata \(scelta?.nome ?? "") del \(scelta?.data ?? ""): cosa ha funzionato, dove abbiamo perso soldi e cosa cambierei la prossima volta.")
        }
    }

    /// La legenda dell'anello: il quadretto (più acceso dove si incassa di più), la voce, gli euro e la percentuale.
    private func legendaSoldi(_ fette: [(String, Double)]) -> some View {
        let tot = max(1, fette.reduce(0) { $0 + $1.1 }), massimo = max(1, fette.map(\.1).max() ?? 1)
        return VStack(spacing: 7) {
            ForEach(fette, id: \.0) { nome, v in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(tinta).frame(width: 8, height: 8)
                        .shadow(color: tinta.opacity(0.7), radius: 3)
                        .opacity(0.45 + 0.55 * v / massimo)
                    Text(nome).font(.system(size: 13)).foregroundStyle(.white)
                    Spacer(minLength: 6)
                    Text(euro(v)).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(tinta).monospacedDigit()
                    Text("\(Int((v / tot * 100).rounded()))%").font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.tenue).frame(width: 40, alignment: .trailing)
                }
            }
        }
    }

    private func caricaElenco() async {
        guard let o = await VistaVitals.chiama(["serate": true]) else { errore = "Non raggiungo le serate, Sir."; return }
        let lista = (o["serate"] as? [[String: Any]] ?? []).compactMap { s -> Serata? in
            guard let id = s["id"] as? String else { return nil }
            return Serata(id: id, nome: s["nome"] as? String ?? "Serata", data: s["data"] as? String ?? "", chiusa: s["chiusa_il"] != nil && !(s["chiusa_il"] is NSNull))
        }
        serate = lista
        if scelta == nil { scelta = lista.first { !$0.prova } ?? lista.first }
        if lista.isEmpty { errore = "Nessuna serata registrata." }
    }

    private func carica(_ s: Serata) async {
        conti = nil
        errore = nil
        guard let o = await VistaVitals.chiama(["serata": ["data": String(s.data.prefix(10)), "nome": s.nome]]) else { errore = "Non raggiungo i conti, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        withAnimation(.easeOut(duration: 0.3)) { conti = o }
    }
}
#endif
