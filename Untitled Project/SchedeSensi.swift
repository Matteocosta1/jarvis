#if os(iOS)
import Foundation
import SwiftUI
import Combine
import Charts
import MusicKit
import UIKit

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
    @State private var lampo = false                    // il lampo del logo quando la trova
    @State private var aperta: Trovata?                 // il player
    @State private var brano: Song?                     // il brano di Apple Music che suona nel player
    @State private var inLibreria = Set<String>()
    @State private var giu: CGFloat = 0                 // lo swipe giù del player
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
                    Button(role: .destructive) { chiediCancella = true } label: { Label("Cancella la cronologia", systemImage: "trash").font(.footnote) }
                        .tint(.red).padding(.top, 4)
                }
            }
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
        .confirmationDialog("Cancellare tutte le canzoni riconosciute?", isPresented: $chiediCancella, titleVisibility: .visible) {
            Button("Cancella", role: .destructive) { storico = []; VistaShazam.salva([]) }
        }
    }

    private var sottotitolo: String {
        switch stato {
        case .fermo: return "tocchi il logo per ascoltare"
        case .ascolto: return "ascolto la musica…"
        case .trovata: return "trovata · suona su Apple Music"
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

    // MARK: il player (sale da sotto; si chiude con uno swipe giù, come in Vinyl Hustler)

    private func player(_ t: Trovata) -> some View {
        VStack(spacing: 14) {
            Capsule().fill(Color.white.opacity(0.35)).frame(width: 40, height: 5)
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: t.copertina) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: tinta.opacity(0.5), radius: 12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.titolo).font(.system(size: 19, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    Text(t.artista).font(.system(size: 15)).foregroundStyle(tinta).lineLimit(1)
                    Text([t.album, brano?.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(1)
                    Text("APPLE MUSIC").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(tinta.opacity(0.8))
                }
                Spacer(minLength: 0)
            }
            barraTempo
            HStack(spacing: 34) {
                Button { lettore.salta(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 24)) }
                Button { Task { await lettore.playPausa() } } label: {
                    Image(systemName: lettore.suona ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 54))
                }
                Button { lettore.salta(15) } label: { Image(systemName: "goforward.15").font(.system(size: 24)) }
            }
            .foregroundStyle(tinta)
            HStack(spacing: 10) {
                let gia = brano.map { inLibreria.contains($0.id.rawValue) } ?? false
                Button { Task { await aggiungiLibreria() } } label: {
                    Label(gia ? "IN LIBRERIA" : "LIBRERIA", systemImage: gia ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).frame(height: 42)
                        .foregroundStyle(tinta).overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.6), lineWidth: 1))
                }
                .disabled(brano == nil || gia)
                Button { chiudiPlayer(); apriMusica() } label: {
                    Label("MUSICA", systemImage: "music.note")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).frame(maxWidth: .infinity).frame(height: 42)
                        .foregroundStyle(Color.fondo).background(tinta).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if let e = lettore.errore { Text(e).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center) }
        }
        .buttonStyle(StileStark())
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 30)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 26).fill(Color.fondo.opacity(0.97))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(tinta.opacity(0.45), lineWidth: 1))
                .shadow(color: tinta.opacity(0.3), radius: 20)
        )
        .offset(y: max(0, giu))
        .gesture(DragGesture()
            .onChanged { giu = $0.translation.height }
            .onEnded { v in
                if v.translation.height > 90 || v.predictedEndTranslation.height > 260 { chiudiPlayer() }
                else { withAnimation(.spring(duration: 0.3)) { giu = 0 } }
            })
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .ignoresSafeArea(edges: .bottom)
    }

    private var barraTempo: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let d = lettore.durata ?? 0, now = lettore.tempo, f = d > 0 ? min(1, now / d) : 0
            VStack(spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(tinta).frame(width: g.size.width * f)
                    }
                    .frame(height: 4).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { v in lettore.vaiA(v.location.x / max(1, g.size.width)) })
                }
                .frame(height: 22)
                HStack {
                    Text(VistaShazam.mmss(now)); Spacer(); Text(d > 0 ? VistaShazam.mmss(d) : "--:--")
                }
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
            }
        }
    }

    nonisolated static func mmss(_ s: Double) -> String { let x = Int(max(0, s)); return String(format: "%d:%02d", x / 60, x % 60) }

    private func chiudiPlayer() {
        withAnimation(.spring(duration: 0.35)) { aperta = nil; giu = 0 }            // la musica continua
    }

    private func rigaStorico(_ t: Trovata) -> some View {
        Button { Task { await suona(t) } } label: {
            HStack(spacing: 12) {
                AsyncImage(url: t.copertina) { img in img.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.titolo).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(t.artista).font(.system(size: 12)).foregroundStyle(tinta).lineLimit(1)
                }
                Spacer()
                Text(t.quando.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(tinta)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { chiedi("Raccontami qualcosa di «\(t.titolo)» di \(t.artista): l'anno, la storia, e se c'è un vinile da cercare su Discogs.") } label: { Label("Chieda a JARVIS", systemImage: "waveform") }
            Button(role: .destructive) { storico.removeAll { $0.id == t.id }; VistaShazam.salva(storico) } label: { Label("Elimina", systemImage: "trash") }
        }
    }

    // MARK: ascolto, riproduzione, libreria

    private func ascolta() async {
        guard stato != .ascolto else { return }
        withAnimation { stato = .ascolto; aperta = nil }
        switch await Musica.riconosci(secondi: 12) {
        case .trovato(let b):
            let t = Trovata(titolo: b.titolo, artista: b.artista, album: b.album, copertina: b.copertina, link: b.appleMusic ?? b.web,
                            generi: b.generi, quando: Date(), appleMusicID: b.appleMusicID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Suoni.pronto()
            withAnimation(.easeOut(duration: 0.15)) { stato = .trovata; lampo = true }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) { lampo = false }
            storico.insert(t, at: 0)
            VistaShazam.salva(storico)
            await suona(t)
        case .nessuno:
            withAnimation { stato = .niente("Non la riconosco, Sir: forse la musica è troppo bassa o c'è troppo rumore. Ritocchi il logo.") }
        case .errore(let e):
            withAnimation { stato = .niente("Shazam non risponde: \(e).") }
        }
    }

    /// Sale il player e la canzone parte subito su Apple Music (serve l'abbonamento; senza, il player resta con il link).
    private func suona(_ t: Trovata) async {
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { aperta = t; giu = 0 }
        brano = nil
        guard await CatalogoMusica.autorizzato() else { lettore.errore = CatalogoMusica.senzaPermesso; return }
        var trovato: Song?
        if let id = t.appleMusicID {
            let r = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
            trovato = try? await r.response().items.first
        }
        if trovato == nil {
            var r = MusicCatalogSearchRequest(term: "\(t.titolo) \(t.artista)", types: [Song.self]); r.limit = 1
            trovato = try? await r.response().songs.first
        }
        guard let s = trovato else { lettore.errore = "Non la trovo su Apple Music, Sir."; return }
        lettore.errore = nil
        brano = s
        await lettore.metti(s)
    }

    private func aggiungiLibreria() async {
        guard let s = brano else { return }
        do {
            try await MusicLibrary.shared.add(s)
            inLibreria.insert(s.id.rawValue)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            lettore.errore = "Non riesco ad aggiungerla alla libreria: \(error.localizedDescription)"
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
            // l'analisi di tutta la galleria (una volta sola, poi solo le foto nuove), in ologramma: c'è solo mentre va avanti e se
            // restano almeno 50 foto (le poche foto nuove passano senza); finita lo dice, poi il pannello si chiude
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
                ProgressView().tint(tinta).frame(maxWidth: .infinity).padding(.top, 40)
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

    /// Il pannello dell'analisi: si apre se l'analisi va avanti e restano almeno 50 foto; quando finisce dice «ANALISI COMPLETA»
    /// (col suono «pronto»), poi dopo 1,9 s si chiude.
    private func aggiornaPannello() {
        if !pannello && analisi.attivo && analisi.totale > 0 && analisi.totale - analisi.fatte >= 50 {
            completa = false
            withAnimation(.easeOut(duration: 0.3)) { pannello = true }
        } else if pannello && !analisi.attivo && !completa {
            completa = true
            Suoni.fatto()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.9))
                withAnimation(.timingCurve(0.3, 0.7, 0.3, 1, duration: 0.45)) { pannello = false }
                completa = false
            }
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
            else { ProgressView().tint(tinta).frame(maxWidth: .infinity).padding(.top, 40) }
        }
        .task { await caricaElenco() }
        .task(id: scelta?.id) { if let s = scelta { await carica(s) } }
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
                // 11.0 (4), come il mockup v261: l'anello di monete (una fetta per voce, alta quanto pesa), i soldi che arrivano
                // e l'incasso che sale al centro; sotto, voce per voce, quanto e che parte del totale
                OlogrammaSoldi(dati: DatiSoldi(fonti: fette.map { DatiSoldi.Fonte(nome: $0.0, valore: $0.1) }))
                    .frame(height: 220)
                    .id(scelta?.id)                              // un'altra serata: l'anello riparte da capo
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
