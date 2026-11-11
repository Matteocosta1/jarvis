#if os(iOS)
import SwiftUI
import MusicKit
import AVFoundation
import Combine

// MARK: - MUSICA (build 23, MARK IX): il suo Apple Music dentro JARVIS, come nel mockup approvato (#23)

/// Il lettore della sezione MUSICA. 9 nov sera (il signore: «fai un lettore nostro interno», «come Apple Music»): è il lettore
/// DENTRO JARVIS (`ApplicationMusicPlayer`), non più l'app Musica. Chiudendo JARVIS la musica finisce; «Chiudi» sulla sezione la
/// ferma; in background (Home, altra app, schermo bloccato) continua, con JARVIS nella Dynamic Island; l'app Musica non viene mai
/// toccata. Lo stesso lettore per i comandi a voce («metti i Clash», MusicaApple.swift), Shazam e il polso. Il volume coi tasti
/// dell'iPhone; JARVIS non può abbassarlo (Apple non lo permette): con «Jarvis» va in pausa e riparte dopo la risposta.
final class LettoreMusica: ObservableObject {
    static let condiviso = LettoreMusica()

    private let lettore = ApplicationMusicPlayer.shared
    @Published private(set) var voce: MusicKit.MusicPlayer.Queue.Entry?     // il brano in coda adesso
    @Published private(set) var suona = false
    @Published private(set) var casuale = false
    @Published private(set) var ripeti = false
    @Published var errore: String?
    /// Decisione 33: la qualità vera del brano per «APPLE MUSIC · …» («DOLBY ATMOS», «HI-RES LOSSLESS», «LOSSLESS»);
    /// nil quando non si sa (radio, video, nessuna risposta): allora solo «APPLE MUSIC».
    @Published private(set) var qualita: String?
    private var qualitaDi: MusicItemID?    // il brano di cui si è chiesta la qualità
    private var angoloFermo = 0.0          // il disco: dove si è fermato (radianti)
    private var angoloDa: Date?            // da quando gira

    private init() { aggiorna() }

    /// 9 nov sera: messa in pausa da JARVIS perché il signore gli parla («Jarvis» o tocco): riparte da sola dopo la risposta.
    private(set) var fermataDaJarvis = false

    /// L'audio di JARVIS pronto per la musica: se era sul «solo effetti» (che col silenzioso tace e in background si ferma) passa
    /// alla riproduzione vera, come un'app musicale. Se il «Jarvis» in attesa ha già il microfono (registra e riproduce), resta così.
    static func preparaAudio() {
        let s = AVAudioSession.sharedInstance()
        if s.category == .ambient || s.category == .soloAmbient { try? s.setCategory(.playback, mode: .default, options: []) }
        try? s.setActive(true)
    }

    /// «Jarvis» con la musica: pausa (il lettore dell'app non si può abbassare), poi `riprendiDopoJarvis`.
    func fermaPerJarvis() {
        guard suona else { return }
        lettore.pause()
        fermataDaJarvis = true
        aggiorna()
    }
    func riprendiDopoJarvis() async {
        guard fermataDaJarvis else { return }
        fermataDaJarvis = false
        await play()
    }
    /// «Chiudi» sulla sezione: la musica finisce (come chiudere Apple Music).
    func ferma() {
        fermataDaJarvis = false
        lettore.stop()
        aggiorna()
    }

    /// Mentre la sezione (o il polso) guarda: legge il lettore quattro volte al secondo (brano, play, casuale, ripeti).
    func segui() async {
        while !Task.isCancelled {
            aggiorna()
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func aggiorna() {
        let e = lettore.queue.currentEntry
        if e?.id != voce?.id || e?.title != voce?.title { voce = e; leggiQualita() }
        let s = lettore.state.playbackStatus == .playing
        if s != suona {
            let ora = Date()
            if s { angoloDa = ora } else { angoloFermo = angolo(ora); angoloDa = nil }
            suona = s
        }
        let c = lettore.state.shuffleMode == MusicKit.MusicPlayer.ShuffleMode.songs
        if c != casuale { casuale = c }
        let r = lettore.state.repeatMode == MusicKit.MusicPlayer.RepeatMode.one
        if r != ripeti { ripeti = r }
        // 10 nov: i prossimi in coda, per l'ologramma CODA (non pubblicati: l'ologramma li legge a ogni fotogramma)
        var nuovi: [MusicKit.MusicPlayer.Queue.Entry] = []
        if let e {
            let tutte = Array(lettore.queue.entries)
            if let i = tutte.firstIndex(where: { $0.id == e.id }) { nuovi = Array(tutte.dropFirst(i + 1).prefix(6)) }
        }
        if nuovi.map(\.id) != prossimi.map(\.id) { prossimi = nuovi }
    }

    /// I prossimi brani in coda dopo quello di adesso (al massimo 6).
    private(set) var prossimi: [MusicKit.MusicPlayer.Queue.Entry] = []

    /// CODA: toccato due volte un brano in orbita, parte (salta avanti fino a lui).
    func suonaProssimo(_ k: Int) async {
        guard k >= 0, k < prossimi.count else { return }
        fermataDaJarvis = false
        do {
            for _ in 0...k { try await lettore.skipToNextEntry() }
        } catch {
            errore = "Apple Music: \(error.localizedDescription)"
        }
        await play()
    }

    /// I dati per gli ologrammi di MUSICA (VINILE, ONDA, CODA), letti a ogni fotogramma.
    var datiOlo: DatiMusicaOlo {
        DatiMusicaOlo(ora: BranoMusicaOlo(titolo: titolo, artista: artista, album: album, durata: durata ?? 0),
                      t: voce == nil ? 0 : tempo, suona: suona, jPausa: fermataDaJarvis,
                      prossimi: prossimi.map { LettoreMusica.branoOlo($0) },
                      playPausa: { Suoni.tocco(); Task { await LettoreMusica.condiviso.playPausa() } },
                      vaiA: { f in Suoni.tocco(); LettoreMusica.condiviso.vaiA(f) },
                      suonaProssimo: { k in Suoni.tocco(); Task { await LettoreMusica.condiviso.suonaProssimo(k) } })
    }

    private static func branoOlo(_ e: MusicKit.MusicPlayer.Queue.Entry) -> BranoMusicaOlo {
        if case .song(let s)? = e.item {
            return BranoMusicaOlo(titolo: s.title, artista: s.artistName, album: s.albumTitle ?? "—", durata: s.duration ?? 0)
        }
        return BranoMusicaOlo(titolo: e.title, artista: e.subtitle ?? "—", album: e.title, durata: 0)
    }

    // MARK: la qualità (decisione 33)

    /// Il brano è cambiato: si chiede ad Apple Music in che qualità c'è (una volta per brano). Finché non risponde, e se non
    /// risponde, la scritta è solo «APPLE MUSIC».
    private func leggiQualita() {
        guard let s = brano else { qualitaDi = nil; qualita = nil; return }
        guard s.id != qualitaDi else { return }
        qualitaDi = s.id
        qualita = nil
        Task {
            let q = await LettoreMusica.qualita(di: s)
            guard self.qualitaDi == s.id else { return }               // nel frattempo è partito un altro brano
            self.qualita = q
        }
    }

    /// Come i bollini dell'app Musica: Dolby Atmos prima di tutto, poi Hi-Res Lossless, poi Lossless (nil: nessuno dei tre o
    /// non si sa). Le varianti sono un attributo «esteso» di Apple Music: se il brano non le ha già, si chiedono al catalogo
    /// (anche per i brani della libreria, che hanno il loro gemello nel catalogo).
    nonisolated static func qualita(di s: Song) async -> String? {
        var varianti = s.audioVariants
        if varianti == nil, let pieno = try? await s.with([.audioVariants], preferredSource: .catalog) { varianti = pieno.audioVariants }
        guard let v = varianti else { return nil }
        if v.contains(.dolbyAtmos) { return "DOLBY ATMOS" }
        if v.contains(.highResolutionLossless) { return "HI-RES LOSSLESS" }
        if v.contains(.lossless) { return "LOSSLESS" }
        return nil
    }

    // MARK: cosa suona

    private var brano: Song? {
        if case .song(let s)? = voce?.item { return s }
        return nil
    }
    var titolo: String { voce?.title ?? "—" }
    var artista: String { brano?.artistName ?? voce?.subtitle ?? "—" }
    var album: String { brano?.albumTitle ?? "—" }
    var copertina: Artwork? { voce?.artwork }
    var durata: TimeInterval? {
        if let d = brano?.duration, d > 0 { return d }
        return nil
    }
    var tempo: TimeInterval { lettore.playbackTime }

    /// Quanto è girato il disco (gira solo mentre suona, 0,9 radianti al secondo come nel mockup).
    func angolo(_ ora: Date) -> Double { angoloFermo + (angoloDa.map { ora.timeIntervalSince($0) * 0.9 } ?? 0) }

    /// La riga della lista è il brano che suona adesso (per evidenziarla, come «.ora» nel mockup).
    func eQuello(_ t: String, _ a: String?) -> Bool {
        voce != nil && t.caseInsensitiveCompare(titolo) == .orderedSame && (a ?? "").caseInsensitiveCompare(artista) == .orderedSame
    }

    // MARK: i tasti

    func playPausa() async {
        fermataDaJarvis = false                                    // il signore ha preso il comando: niente ripresa automatica
        if suona { pausa() } else { await play() }
    }

    func play() async {
        LettoreMusica.preparaAudio()
        do { try await lettore.play(); errore = nil } catch { errore = "Apple Music: \(error.localizedDescription)" }
        aggiorna()
    }

    func pausa() { fermataDaJarvis = false; lettore.pause(); aggiorna() }

    func avanti() async {
        do { try await lettore.skipToNextEntry() } catch { errore = "Apple Music: \(error.localizedDescription)" }
        aggiorna()
    }

    /// Come nel mockup: dopo 3 secondi torna all'inizio del brano, prima va al brano precedente.
    func indietro() async {
        if lettore.playbackTime > 3 { lettore.restartCurrentEntry() } else {
            do { try await lettore.skipToPreviousEntry() } catch { errore = "Apple Music: \(error.localizedDescription)" }
        }
        aggiorna()
    }

    func cambiaCasuale() {
        lettore.state.shuffleMode = casuale ? MusicKit.MusicPlayer.ShuffleMode.off : MusicKit.MusicPlayer.ShuffleMode.songs
        aggiorna()
    }

    /// Ripeti = lo stesso brano da capo (come nel mockup).
    func cambiaRipeti() {
        lettore.state.repeatMode = ripeti ? MusicKit.MusicPlayer.RepeatMode.none : MusicKit.MusicPlayer.RepeatMode.one
        aggiorna()
    }

    /// MARK X · player di Shazam: −15 / +15 secondi.
    func salta(_ secondi: Double) {
        let fine = durata ?? .greatestFiniteMagnitude
        lettore.playbackTime = max(0, min(fine, lettore.playbackTime + secondi))
    }

    /// Tocco sulla barra del tempo: `frazione` da 0 a 1.
    func vaiA(_ frazione: Double) {
        guard let d = durata else { return }
        lettore.playbackTime = max(0, min(1, frazione)) * d
    }

    /// Una lista (brani di una playlist, di un album, della libreria…) a partire da `da`.
    func metti<T: PlayableMusicItem>(_ lista: [T], da: T?) async {
        guard !lista.isEmpty else { return }
        guard await CatalogoMusica.autorizzato() else { errore = CatalogoMusica.senzaPermesso; return }
        lettore.queue = ApplicationMusicPlayer.Queue(for: lista, startingAt: da)
        await play()
    }

    /// Una cosa sola: un brano, una radio, una playlist intera.
    func metti<T: PlayableMusicItem>(_ cosa: T) async {
        guard await CatalogoMusica.autorizzato() else { errore = CatalogoMusica.senzaPermesso; return }
        lettore.queue = [cosa]
        await play()
    }
}

// MARK: - Le richieste ad Apple Music

/// Le richieste di MusicKit per le quattro schede: OGGI (ascoltati di recente, «Per lei», brani del momento), RADIO, LIBRERIA, CERCA.
nonisolated enum CatalogoMusica {
    static let senzaPermesso = "Per la musica serve il permesso ad Apple Music: Impostazioni › Jarvis › Contenuti multimediali e Apple Music."
    /// Decisione 34: Apple Music non ha dato niente (senza rete, o MusicKit non attivo per l'app): OGGI non resta vuoto in silenzio.
    static let nonRisponde = "Apple Music non risponde, Sir: riprovi tra poco."

    static func autorizzato() async -> Bool {
        if MusicAuthorization.currentStatus == .authorized { return true }
        return await MusicAuthorization.request() == .authorized
    }

    /// I brani ascoltati di recente, un album sola volta (le tessere del mockup: album e artista).
    static func recenti() async -> [Song] {
        var r = MusicRecentlyPlayedRequest<Song>()
        r.limit = 25
        guard let c = try? await r.response().items else { return [] }
        var visti = Set<String>()
        var out: [Song] = []
        for s in c where visti.insert((s.albumTitle ?? s.title).lowercased()).inserted {
            out.append(s)
            if out.count == 10 { break }
        }
        return out
    }

    /// «Per lei»: i suggerimenti di Apple Music (playlist e album), più le radio suggerite (vanno nella scheda RADIO).
    static func perLei() async -> (playlist: [Playlist], album: [Album], radio: [StazioneMusica]) {
        guard let risposta = try? await MusicPersonalRecommendationsRequest().response() else { return ([], [], []) }
        var p: [Playlist] = [], a: [Album] = [], s: [StazioneMusica] = []
        for rec in risposta.recommendations {
            p += Array(rec.playlists)
            a += Array(rec.albums)
            s += rec.stations.map { StazioneMusica(stazione: $0, sotto: rec.title ?? "Per lei") }
        }
        return (Array(p.prefix(12)), Array(a.prefix(12)), s)
    }

    /// I brani del momento: la classifica dei più ascoltati su Apple Music nel suo Paese.
    static func momento() async -> [Song] {
        let r = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self])
        guard let risposta = try? await r.response(), let classifica = risposta.songCharts.first else { return [] }
        return Array(classifica.items.prefix(10))
    }

    nonisolated private struct Stazioni: Decodable { let data: [Station] }     // la risposta dell'Apple Music API: { data: [stazioni] }

    /// Una lista di stazioni dall'Apple Music API (la via che MusicKit offre per gli indirizzi senza una richiesta dedicata).
    private static func stazioni(_ filtro: String) async -> [Station] {
        guard let paese = try? await MusicDataRequest.currentCountryCode,
              let url = URL(string: "https://api.music.apple.com/v1/catalog/\(paese)/stations?\(filtro)"),
              let risposta = try? await MusicDataRequest(urlRequest: URLRequest(url: url)).response(),
              let lette = try? JSONDecoder().decode(Stazioni.self, from: risposta.data) else { return [] }
        return lette.data
    }

    /// RADIO: le dirette di Apple Music, la sua stazione personale, le radio ascoltate di recente e quelle suggerite.
    static func radio(suggerite: [StazioneMusica]) async -> [StazioneMusica] {
        var dirette = await stazioni("filter%5Bfeatured%5D=apple-music-live-radio")
        if dirette.isEmpty {        // di riserva: Apple Music 1 e Apple Music Country, per identificativo
            let r = MusicCatalogResourceRequest<Station>(matching: \.id, memberOf: ["ra.978194965", "ra.1498157166"])
            if let c = try? await r.response().items { dirette = Array(c) }
        }
        let sua = await stazioni("filter%5Bidentity%5D=personal")
        var ascoltate: [Station] = []
        if let c = try? await MusicRecentlyPlayedRequest<Station>().response().items { ascoltate = Array(c) }
        var out = dirette.map { StazioneMusica(stazione: $0, sotto: "In diretta") }
        out += sua.map { StazioneMusica(stazione: $0, sotto: "La sua stazione") }
        out += ascoltate.map { StazioneMusica(stazione: $0, sotto: "Ascoltata di recente") }
        out += suggerite
        var visti = Set<String>()
        return out.filter { visti.insert($0.id).inserted }
    }

    /// LIBRERIA: le sue playlist.
    static func playlistLibreria() async -> [Playlist] {
        var r = MusicLibraryRequest<Playlist>()
        r.limit = 100
        guard let c = try? await r.response().items else { return [] }
        return Array(c)
    }

    /// LIBRERIA: i suoi brani, a pagine da 200 (al massimo 3000).
    static func braniLibreria() async -> [Song] {
        var out: [Song] = []
        var visti = Set<MusicItemID>()
        while out.count < 3000 {
            var r = MusicLibraryRequest<Song>()
            r.limit = 200
            r.offset = out.count
            guard let c = try? await r.response().items, !c.isEmpty else { break }
            let nuovi = c.filter { visti.insert($0.id).inserted }
            if nuovi.isEmpty { break }                               // la pagina non ha portato niente di nuovo: finita
            out += nuovi
        }
        return out
    }

    /// CERCA: i brani del catalogo Apple Music.
    static func cerca(_ testo: String) async -> [Song] {
        var r = MusicCatalogSearchRequest(term: testo, types: [Song.self])
        r.limit = 25
        guard let c = try? await r.response().songs else { return [] }
        return Array(c)
    }

    /// I brani di una playlist o di un album (per il dettaglio con «Riproduci» e per il «N brani» delle tessere).
    static func brani(_ raccolta: RaccoltaMusica) async -> [Track] {
        switch raccolta {
        case .playlist(let p):
            guard let d = try? await p.with(.tracks), let t = d.tracks else { return [] }
            return Array(t)
        case .album(let a):
            guard let d = try? await a.with(.tracks), let t = d.tracks else { return [] }
            return Array(t)
        }
    }
}

/// Una radio con la riga sotto il nome («In diretta», «Ascoltata di recente»…).
nonisolated struct StazioneMusica: Identifiable, Sendable {
    let stazione: Station
    let sotto: String
    var id: String { stazione.id.rawValue }
}

/// Una playlist o un album aperti nel dettaglio.
nonisolated enum RaccoltaMusica: Hashable, Sendable {
    case playlist(Playlist), album(Album)
    var id: String {
        switch self {
        case .playlist(let p): return p.id.rawValue
        case .album(let a): return a.id.rawValue
        }
    }
    var nome: String {
        switch self {
        case .playlist(let p): return p.name
        case .album(let a): return a.title
        }
    }
    var artwork: Artwork? {
        switch self {
        case .playlist(let p): return p.artwork
        case .album(let a): return a.artwork
        }
    }
    var genere: String {
        switch self {
        case .playlist: return "playlist"
        case .album: return "album"
        }
    }
}

// MARK: - La sezione

/// MUSICA: in alto il disco che suona (copertina che gira, anello a tacche, spettro intorno), titolo, artista, album, la barra del tempo,
/// casuale · precedente · play · successivo · ripeti e «APPLE MUSIC · LOSSLESS» (la qualità vera del brano, decisione 33);
/// sotto le schede OGGI · RADIO · LIBRERIA · CERCA.
/// Non è una sezione con la fotocamera: si chiude con «Chiudi» in alto a destra (CorniceScheda).
struct VistaMusica: View {
    private enum Scheda: String, CaseIterable, Identifiable {
        case oggi = "Oggi", radio = "Radio", libreria = "Libreria", cerca = "Cerca"
        var id: String { rawValue }
    }

    @ObservedObject private var lettore = LettoreMusica.condiviso
    @State private var scheda: Scheda = .oggi
    @State private var aperta: RaccoltaMusica?
    @State private var braniAperta: [Track]?
    @State private var pronto = false
    /// 8 nov (il signore: Musica «carica dopo», «uguale alle altre sezioni»): la sezione si apre col caricamento di sempre; le liste
    /// di Apple Music arrivano dopo, con l'anello del mockup al loro posto (come la Posta e il Diario). Prima il caricamento
    /// aspettava tutte e tre le risposte di Apple Music.
    @State private var attesaOggi = true
    @State private var avviso: String?
    @State private var recenti: [Song] = []
    @State private var perLeiPlaylist: [Playlist] = []
    @State private var perLeiAlbum: [Album] = []
    @State private var radioSuggerite: [StazioneMusica] = []
    @State private var momento: [Song] = []
    @State private var radio: [StazioneMusica]?
    @State private var playlist: [Playlist]?
    @State private var brani: [Song]?
    @State private var testo = ""
    @State private var risultati: [Song] = []
    @State private var cercato = ""
    @State private var conti: [String: Int] = [:]        // quanti brani ha ogni playlist / album (id → numero)

    var body: some View {
        CorniceScheda(titolo: "Musica", sottotitolo: "sound · apple music", icona: "vinile", tinta: .ciano, pronto: pronto) {   // 7 nov sera: come tutte le sezioni (prima col marchio J.A.R.V.I.S.)   // 26 ott notte: JARVIS Sound (Studio · Sound · Social), testata di Studio e Social
            // 10 nov (il signore: «fai come le altre, 3 diversi ologrammi»): in testa l'ologramma con VINILE, ONDA, CODA, come il mockup
            OlogrammaMusicaProve(lettore: lettore)
                .corniceOlo(Color.ciano)
            PannelloOraMusica(lettore: lettore)
            if let avviso {
                Pannello(tinta: .ciano) { Text(avviso).font(.footnote).foregroundStyle(.orange) }
            } else if let e = lettore.errore {
                Pannello(tinta: .ciano) { Text(e).font(.footnote).foregroundStyle(.orange) }
            }
            schede
            VStack(alignment: .leading, spacing: 14) { pagina }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await lettore.segui() }
        // 9 nov sera (il signore: «se chiudo la scheda la musica finisce, come Apple Music»): «Chiudi» ferma la musica; mandata
        // dietro la sezione resta viva (niente onDisappear) e la musica continua, col disco del Dock che gira
        .onDisappear { lettore.ferma() }
        .task { await caricaOggi() }
        .sulloSchermo(testoSchermo)
    }

    /// 8 nov notte: cosa vede JARVIS di MUSICA (il brano di adesso, la scheda, la raccolta aperta, la ricerca e i risultati).
    private var testoSchermo: String {
        var ora = "niente in riproduzione"
        if let v = lettore.voce {
            ora = "in riproduzione: \(v.title)"
            if let a = v.subtitle { ora += " – \(a)" }
            if !lettore.suona { ora += " (in pausa)" }
        }
        var pezzi: [String?] = [ora, "scheda \(scheda.rawValue)"]
        if let r = aperta {
            let brani: [String] = (braniAperta ?? []).prefix(15).enumerated().map { i, t in "\(i + 1). \(t.title) – \(t.artistName)" }
            pezzi.append("aperta: \(r.nome)" + (brani.isEmpty ? "" : ", brani: " + brani.joined(separator: "; ")))
        } else if scheda == .cerca {
            pezzi.append(Schermo.campo("cerca", testo))
            let trovati: [String] = risultati.prefix(10).enumerated().map { i, b in "\(i + 1). \(b.title) – \(b.artistName)" }
            if !trovati.isEmpty { pezzi.append("risultati per «\(cercato)»: " + trovati.joined(separator: "; ")) }
        }
        return Schermo.unisci("Musica", pezzi)
    }

    // MARK: le schede

    private var schede: some View {
        HStack(spacing: 6) {
            ForEach(Scheda.allCases) { s in
                let attiva = s == scheda
                Button {
                    Suoni.tocco()
                    scheda = s
                    aperta = nil
                    Task { await carica(s) }
                } label: {
                    Text(s.rawValue.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(attiva ? ColoriMusica.scuro : Color.ciano)
                        .padding(.vertical, 8).padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .background(attiva ? Color.ciano : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(attiva ? Color.ciano : Color.ciano.opacity(0.3), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(StileStark())
                .accessibilityAddTraits(attiva ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var pagina: some View {
        if let r = aperta {
            dettaglio(r)
        } else {
            switch scheda {
            case .oggi: oggi
            case .radio: paginaRadio
            case .libreria: libreria
            case .cerca: cerca
            }
        }
    }

    // MARK: OGGI

    @ViewBuilder private var oggi: some View {
        if attesaOggi && recenti.isEmpty && perLeiPlaylist.isEmpty && perLeiAlbum.isEmpty && momento.isEmpty {
            AttesaAnello(tinta: .ciano).frame(maxWidth: .infinity).padding(.top, 24)
        }
        if !recenti.isEmpty {
            sezione("ASCOLTATI DI RECENTE") {
                fila(recenti.map { s in
                    TesseraMusica(id: "r" + s.id.rawValue, nome: s.albumTitle ?? s.title, sotto: s.artistName, artwork: s.artwork) {
                        Task { await lettore.metti(s) }
                    }
                })
            }
        }
        let suggerite = tessere(perLeiPlaylist.map { RaccoltaMusica.playlist($0) } + perLeiAlbum.map { RaccoltaMusica.album($0) })
        if !suggerite.isEmpty {
            sezione("PER LEI") { fila(suggerite) }
        }
        if !momento.isEmpty {
            sezione("BRANI DEL MOMENTO") { listaBrani(momento) }
        }
    }

    // MARK: RADIO

    @ViewBuilder private var paginaRadio: some View {
        if let radio {
            sezione("RADIO") {
                if radio.isEmpty { vuoto("NESSUNA RADIO") }
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(radio) { r in
                        riga(titolo: r.stazione.name, sotto: r.sotto, destra: r.stazione.isLive ? "LIVE" : "", artwork: r.stazione.artwork,
                             ora: lettore.titolo == r.stazione.name) {
                            Task {
                                await lettore.metti(r.stazione)
                                await PannelliTraccia.notifica("\(r.stazione.name), Sir.")   // come nel mockup: l'avviso in alto
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: LIBRERIA

    @ViewBuilder private var libreria: some View {
        if let playlist, !playlist.isEmpty {
            sezione("PLAYLIST") { fila(tessere(playlist.map { RaccoltaMusica.playlist($0) })) }
        }
        if let brani {
            sezione("BRANI · \(brani.count)\(brani.count >= 3000 ? "+" : "")") {
                if brani.isEmpty { vuoto("NESSUN BRANO") }
                listaBrani(brani)
            }
        }
    }

    // MARK: CERCA

    @ViewBuilder private var cerca: some View {
        HStack(spacing: 8) {
            Text("⌕").foregroundStyle(Color.ciano)
            TextField("", text: $testo, prompt: Text("Artisti, brani, album").foregroundStyle(Color.tenue))
                .font(.system(size: 15)).foregroundStyle(.white)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Cerca in Apple Music")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color.fondo.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
        .task(id: testo) {
            let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { risultati = []; cercato = ""; return }
            try? await Task.sleep(for: .milliseconds(350))            // mentre scrive: cerca quando si ferma
            guard !Task.isCancelled else { return }
            let r = await CatalogoMusica.cerca(t)
            guard !Task.isCancelled else { return }
            risultati = r
            cercato = t
        }
        if !cercato.isEmpty {
            if risultati.isEmpty { vuoto("NESSUN RISULTATO") } else { listaBrani(risultati) }
        }
    }

    // MARK: il dettaglio di una playlist (o di un album) con «Riproduci»

    @ViewBuilder private func dettaglio(_ r: RaccoltaMusica) -> some View {
        Button { Suoni.tocco(); aperta = nil } label: {
            Text("‹ \(scheda.rawValue)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ciano)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        Pannello(titolo: r.nome.uppercased(), tinta: .ciano) {
            Text(braniAperta.map { "\($0.count) brani · \(r.genere)" } ?? "… · \(r.genere)")
                .font(.system(size: 12)).foregroundStyle(Color.tenue)
            Button {
                Suoni.tocco()
                if let t = braniAperta, let primo = t.first { Task { await lettore.metti(t, da: primo) } }
            } label: {
                Text("▶ Riproduci")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.fondo)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Color.ciano2, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(StileStark())
            .disabled(braniAperta?.isEmpty ?? true)
        }
        if let t = braniAperta {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(t) { b in
                    riga(titolo: b.title, sotto: [b.artistName, b.albumTitle].compactMap { $0 }.joined(separator: " · "),
                         destra: b.duration.map(Self.mmss) ?? "", artwork: b.artwork, ora: lettore.eQuello(b.title, b.artistName)) {
                        Task { await lettore.metti(t, da: b) }
                    }
                }
            }
        }
    }

    // MARK: i pezzi

    private func sezione<C: View>(_ titolo: String, @ViewBuilder _ contenuto: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titolo)
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                .foregroundStyle(Color.ciano)
                .padding(.top, 4)
            contenuto()
        }
    }

    /// La fila di tessere che scorre di lato (112 punti l'una, come nel mockup).
    private func fila(_ tessere: [TesseraMusica]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(tessere) { t in
                    Button { Suoni.tocco(); t.tocco() } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            CopertinaMusica(artwork: t.artwork, lato: 112, raggio: 10, nome: t.nome)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.25), lineWidth: 1))
                            Text(t.nome).font(.system(size: 12, weight: .semibold)).foregroundStyle(ColoriHUD.chiaro).lineLimit(1)
                            Text(t.sotto).font(.system(size: 11)).foregroundStyle(Color.tenue).lineLimit(1)
                        }
                        .frame(width: 112, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .task { if let r = t.raccolta { await conta(r) } }
                }
            }
            .padding(.bottom, 4)
        }
    }

    /// Le tessere di playlist e album: un tocco apre il dettaglio con «Riproduci».
    private func tessere(_ raccolte: [RaccoltaMusica]) -> [TesseraMusica] {
        raccolte.map { r in
            TesseraMusica(id: r.id, nome: r.nome, sotto: conti[r.id].map { "\($0) brani" } ?? r.genere, artwork: r.artwork, raccolta: r) {
                apri(r)
            }
        }
    }

    private func listaBrani(_ lista: [Song]) -> some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(lista) { s in
                riga(titolo: s.title, sotto: [s.artistName, s.albumTitle].compactMap { $0 }.joined(separator: " · "),
                     destra: s.duration.map(Self.mmss) ?? "", artwork: s.artwork, ora: lettore.eQuello(s.title, s.artistName)) {
                    Task { await lettore.metti(lista, da: s) }
                }
            }
        }
    }

    /// Una riga: copertina 44, titolo, «artista · album», la durata a destra; quella che suona è evidenziata.
    private func riga(titolo: String, sotto: String, destra: String, artwork: Artwork?, ora: Bool, tocco: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); tocco() } label: {
            HStack(spacing: 10) {
                CopertinaMusica(artwork: artwork, lato: 44, raggio: 6, nome: titolo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titolo).font(.system(size: 14, weight: .semibold)).foregroundStyle(ora ? Color.ciano : ColoriHUD.chiaro).lineLimit(1)
                    Text(sotto).font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(destra).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.tenue)
            }
            .padding(6)
            .background(ora ? Color.ciano.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func vuoto(_ testo: String) -> some View {
        Text(testo)
            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
            .foregroundStyle(Color.tenue)
            .frame(maxWidth: .infinity)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    nonisolated static func mmss(_ s: TimeInterval) -> String {      // nonisolated: solo conti, si passa anche a .map
        let t = max(0, Int(s))
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    // MARK: il caricamento

    private func caricaOggi() async {
        guard await CatalogoMusica.autorizzato() else { avviso = CatalogoMusica.senzaPermesso; attesaOggi = false; pronto = true; return }
        // 8 nov pomeriggio (il signore: «clicchi, caricamento e carica TUTTA LA PAGINA»): il caricamento resta finché arrivano le
        // liste di OGGI, poi la pagina compare tutta insieme. Se Apple Music tarda più di 4 s la pagina compare comunque, con
        // l'anello al posto delle liste.
        let riserva = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { pronto = true }
        }
        defer { riserva.cancel(); pronto = true }
        if let abbonamento = try? await MusicSubscription.current, !abbonamento.canPlayCatalogContent {
            avviso = "Per far suonare Apple Music serve l'abbonamento attivo su questo iPhone, Sir."
        }
        async let r = CatalogoMusica.recenti()
        async let p = CatalogoMusica.perLei()
        async let m = CatalogoMusica.momento()
        let (rr, pp, mm) = await (r, p, m)
        withAnimation(.easeOut(duration: 0.25)) {
            recenti = rr
            perLeiPlaylist = pp.playlist
            perLeiAlbum = pp.album
            radioSuggerite = pp.radio
            momento = mm
            attesaOggi = false
        }
        // decisione 34: niente di niente, nemmeno la classifica del suo Paese (che c'è sempre quando Apple Music risponde):
        // Apple Music non ha risposto. Lo dice il riquadro arancione, come il permesso e l'abbonamento mancanti
        if avviso == nil, rr.isEmpty, pp.playlist.isEmpty, pp.album.isEmpty, pp.radio.isEmpty, mm.isEmpty {
            avviso = CatalogoMusica.nonRisponde
        }
    }

    private func carica(_ s: Scheda) async {
        switch s {
        case .radio where radio == nil:
            radio = await CatalogoMusica.radio(suggerite: radioSuggerite)
        case .libreria where playlist == nil:
            async let p = CatalogoMusica.playlistLibreria()
            async let b = CatalogoMusica.braniLibreria()
            let (pp, bb) = await (p, b)
            playlist = pp
            brani = bb
        default: break
        }
    }

    private func apri(_ r: RaccoltaMusica) {
        aperta = r
        braniAperta = nil
        Task {
            let t = await CatalogoMusica.brani(r)
            guard aperta == r else { return }
            braniAperta = t
            conti[r.id] = t.count
        }
    }

    /// Il «N brani» sotto una tessera: letto una volta sola.
    private func conta(_ r: RaccoltaMusica) async {
        guard conti[r.id] == nil else { return }
        let n = await CatalogoMusica.brani(r).count
        if n > 0 { conti[r.id] = n }
    }
}

/// Una tessera della fila (album di recente, playlist «Per lei», playlist della libreria).
private struct TesseraMusica: Identifiable {
    let id: String
    let nome: String
    let sotto: String
    let artwork: Artwork?
    var raccolta: RaccoltaMusica? = nil
    let tocco: () -> Void
}

/// I colori del mockup che la sezione usa in più.
enum ColoriMusica {
    static let scuro = Color(red: 0.0, green: 0.094, blue: 0.125)       // #001820: la scritta della scheda accesa
    static let copertinaA = Color(red: 0.012, green: 0.086, blue: 0.106) // #03161b
    static let copertinaB = Color(red: 0.02, green: 0.16, blue: 0.19)
}

/// La copertina vera di Apple Music (ArtworkImage); se manca, il fondo scuro con le iniziali come le copertine del mockup.
struct CopertinaMusica: View {
    let artwork: Artwork?
    let lato: CGFloat
    let raggio: CGFloat
    let nome: String

    var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: lato, height: lato)
            } else {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [ColoriMusica.copertinaA, ColoriMusica.copertinaB], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(String(nome.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased())
                        .font(.system(size: lato / 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.leading, lato * 0.08).padding(.bottom, lato * 0.06)
                }
            }
        }
        .frame(width: lato, height: lato)
        .clipShape(RoundedRectangle(cornerRadius: raggio))
    }
}

// MARK: - Il riquadro di quello che suona

/// Il riquadro in alto: disco, titolo, artista, album, il tempo, i cinque tasti e «APPLE MUSIC · LOSSLESS» (la qualità vera).
/// 10 nov · gli ologrammi di MUSICA (ProveMusica.swift): la tela con le copertine vere di Apple Music come simboli
/// (la prima quella di adesso, poi i prossimi in coda); senza copertina, quella disegnata dal nome dell'album.
struct OlogrammaMusicaProve: View {
    @ObservedObject var lettore: LettoreMusica
    @State private var prove = ProveMusica()

    var body: some View {
        let copertine: [Artwork?] = [lettore.copertina] + (0..<6).map { $0 < lettore.prossimi.count ? lettore.prossimi[$0].artwork : nil }
        ProveOloVista(sezione: .musica, altezza: 260, crea: { prove.crea($0) },
                      disegna: { k, gc, W, H, t, M in prove.disegna(k, &gc, W, H, t, M, LettoreMusica.condiviso.datiOlo, piccolo: false) },
                      simboli: {
                          ForEach(copertine.indices, id: \.self) { i in
                              if let a = copertine[i] {
                                  ArtworkImage(a, width: 240, height: 240).tag(CopertinaOlo.simbolo(i))
                              }
                          }
                      })
    }
}

struct PannelloOraMusica: View {
    @ObservedObject var lettore: LettoreMusica

    var body: some View {
        // 10 nov: il disco è passato nell'ologramma (VINILE), come il mockup (tolto `.mu-disco`)
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(lettore.titolo).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Text(lettore.artista).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo).lineLimit(1)
                Text(lettore.album.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color.ciano).lineLimit(1)
            }
            .multilineTextAlignment(.center)
            BarraTempoMusica(lettore: lettore)
            HStack(spacing: 18) {
                tasto(.casuale, "Casuale", premuto: lettore.casuale) { lettore.cambiaCasuale() }
                tasto(.precedente, "Brano precedente") { Task { await lettore.indietro() } }
                Button { Suoni.tocco(); Task { await lettore.playPausa() } } label: {
                    IconaTastoMusica(tipo: lettore.suona ? .pausa : .play)
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Color.fondo)
                        .frame(width: 62, height: 62)
                        .background(Color.ciano, in: Circle())
                        .shadow(color: Color.ciano.opacity(0.6), radius: 9)
                }
                .buttonStyle(StileStark())
                .accessibilityLabel(lettore.suona ? "Pausa" : "Riproduci")
                tasto(.successivo, "Brano successivo") { Task { await lettore.avanti() } }
                tasto(.ripeti, "Ripeti", premuto: lettore.ripeti) { lettore.cambiaRipeti() }
            }
            // decisione 33: la qualità vera del brano che suona (Lossless, Hi-Res Lossless, Dolby Atmos); se non si sa, solo APPLE MUSIC
            Text(lettore.qualita.map { "APPLE MUSIC · \($0)" } ?? "APPLE MUSIC")
                .font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(2)
                .foregroundStyle(Color.tenue)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: [Color.ciano.opacity(0.10), Color.fondo.opacity(0.6)], center: UnitPoint(x: 0.5, y: 0.3),
                                   startRadius: 0, endRadius: 280),
                    in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.ciano.opacity(0.28), lineWidth: 1))
    }

    private func tasto(_ tipo: IconaTastoMusica.Tipo, _ nome: String, premuto: Bool? = nil, azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            IconaTastoMusica(tipo: tipo)
                .frame(width: 20, height: 20)
                .foregroundStyle(premuto == true ? Color.ciano : Color.ciano.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(premuto == true ? Color.ciano.opacity(0.14) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(StileStark())
        .accessibilityLabel(nome)
        .accessibilityAddTraits(premuto == true ? .isSelected : [])
    }
}

/// Il tempo: 0:00 · la barra (un tocco ci salta) · la durata.
private struct BarraTempoMusica: View {
    @ObservedObject var lettore: LettoreMusica

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let t = lettore.tempo
            let d = lettore.durata ?? 0
            let f = d > 0 ? min(1, max(0, t / d)) : 0
            HStack(spacing: 8) {
                Text(VistaMusica.mmss(t)).frame(width: 38, alignment: .leading)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.ciano.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2).fill(Color.ciano)
                            .frame(width: g.size.width * f)
                            .shadow(color: Color.ciano.opacity(0.7), radius: 4)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in
                        if g.size.width > 0 { lettore.vaiA(v.location.x / g.size.width) }
                    })
                }
                .frame(height: 14)
                Text(VistaMusica.mmss(d)).frame(width: 38, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.tenue)
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo del brano")
    }
}

/// Il disco: la copertina al centro che gira mentre suona, l'anello a tacche e lo spettro tutto intorno (come `musica` nel mockup:
/// le misure sono quelle del suo disegno da 480, in scala).
struct DiscoMusica: View {
    @ObservedObject var lettore: LettoreMusica
    @Environment(\.sezioneDietro) private var dietro          // 4 nov: dietro (MARK XI) la musica suona, il disco non si disegna

    var body: some View {
        GeometryReader { g in
            let W = min(g.size.width, g.size.height)
            TimelineView(.animation(minimumInterval: nil, paused: dietro)) { ctx in
                let a = lettore.angolo(ctx.date)
                let ms = ctx.date.timeIntervalSinceReferenceDate * 1000
                let suona = lettore.suona
                ZStack {
                    Canvas { gc, _ in DiscoMusica.anelli(gc, W: W, a: a, ms: ms, suona: suona) }
                    CopertinaMusica(artwork: lettore.copertina, lato: W * 0.6, raggio: W * 0.3, nome: lettore.album)
                        .rotationEffect(.radians(a))
                    Canvas { gc, _ in DiscoMusica.centro(gc, W: W) }
                }
                .frame(width: W, height: W)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func punto(_ c: CGFloat, _ g: Double, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c + CGFloat(cos(g)) * r, y: c + CGFloat(sin(g)) * r)
    }

    /// L'anello a tacche (120, una ogni dieci più lunga, che scorre piano al contrario) e lo spettro (72 raggi).
    static func anelli(_ gc: GraphicsContext, W: CGFloat, a: Double, ms: Double, suona: Bool) {
        let u = W / 480, c = W / 2, R = W * 0.45
        gc.stroke(Path(ellipseIn: CGRect(x: c - R, y: c - R, width: R * 2, height: R * 2)), with: .color(Color.ciano.opacity(0.35)), lineWidth: 2 * u)
        var tacche = Path()
        for k in 0..<120 {
            let g = Double(k) / 120 * 2 * Double.pi - a * 0.2
            let l: CGFloat = (k % 10 == 0 ? 14 : 6) * u
            tacche.move(to: punto(c, g, R))
            tacche.addLine(to: punto(c, g, R - l))
        }
        gc.stroke(tacche, with: .color(Color.ciano.opacity(0.35 * 0.55)), lineWidth: 2 * u)
        var spettro = Path()
        for k in 0..<72 {
            let g = Double(k) / 72 * 2 * Double.pi
            let v = suona ? 0.35 + 0.65 * abs(sin(ms / 260 + Double(k) * 0.7) * sin(ms / 410 + Double(k) * 1.3)) : 0.08
            let r0 = W * 0.33, r1 = r0 + CGFloat(v) * W * 0.07
            spettro.move(to: punto(c, g, r0))
            spettro.addLine(to: punto(c, g, r1))
        }
        var s = gc
        s.addFilter(.shadow(color: Color.ciano, radius: 4 * u))
        s.stroke(spettro, with: .color(Color.ciano), lineWidth: 3 * u)
    }

    /// I solchi sulla copertina e il foro al centro.
    static func centro(_ gc: GraphicsContext, W: CGFloat) {
        let u = W / 480, c = W / 2
        for k in 1..<5 {
            let r = W * 0.3 * CGFloat(k) / 5
            gc.stroke(Path(ellipseIn: CGRect(x: c - r, y: c - r, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.25)), lineWidth: u)
        }
        let f = W * 0.035
        let foro = Path(ellipseIn: CGRect(x: c - f, y: c - f, width: f * 2, height: f * 2))
        gc.fill(foro, with: .color(Color.fondo))
        gc.stroke(foro, with: .color(Color.ciano), lineWidth: 2 * u)
    }
}

// MARK: - Le icone (gli stessi disegni del mockup, viewBox 24, tratto 1,6)

/// L'icona di MUSICA: il vinile olografico (ICONE.Musica del mockup). Prende il colore dal foregroundStyle.
struct IconaVinile: View {
    var body: some View {
        Canvas { gc, size in
            let k = min(size.width, size.height) / 24
            let dx = (size.width - 24 * k) / 2, dy = (size.height - 24 * k) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * k, y: dy + y * k) }
            func cerchio(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: dx + (12 - r) * k, y: dy + (12 - r) * k, width: 2 * r * k, height: 2 * r * k)) }
            // gli archi del mockup (SVG «a7 7 0 0 1»): il centro è quello che l'SVG calcola dai due estremi
            func arco(_ da: CGPoint, _ a: CGPoint, centro: CGPoint) -> Path {
                var q = Path()
                q.addArc(center: p(centro.x, centro.y), radius: 7 * k,
                         startAngle: .radians(atan2(Double(da.y - centro.y), Double(da.x - centro.x))),
                         endAngle: .radians(atan2(Double(a.y - centro.y), Double(a.x - centro.x))), clockwise: false)
                return q
            }
            let stile = StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round)
            var tenue = gc
            tenue.opacity = 0.55
            gc.stroke(cerchio(9), with: .foreground, style: stile)
            tenue.stroke(cerchio(5.6), with: .foreground, style: stile)
            gc.stroke(cerchio(1.7), with: .foreground, style: stile)
            gc.stroke(arco(CGPoint(x: 5.7, y: 9.4), CGPoint(x: 9.4, y: 5.7), centro: CGPoint(x: 12.141, y: 12.141)), with: .foreground, style: stile)
            tenue.stroke(arco(CGPoint(x: 18.3, y: 14.6), CGPoint(x: 14.6, y: 18.3), centro: CGPoint(x: 11.859, y: 11.859)), with: .foreground, style: stile)
        }
        .accessibilityHidden(true)
    }
}

/// 9 nov notte (il signore, provato nel mockup: «bellissimo, lo voglio anche nell'app»): il vinile di MUSICA nel Dock gira come
/// un disco a 33 giri (1,8 s a giro) mentre la musica suona; fermata, resta dov'era (riparte da lì). A 120 Hz con l'orologio dello
/// schermo, e solo mentre suona. Con «Riduci movimento» resta fermo.
struct VinileDock: View {
    @ObservedObject private var lettore = LettoreMusica.condiviso
    // 11 nov (il signore: «musica accesa, disco gira»): gira anche con la canzone di Shazam che suona dentro JARVIS (anteprima o video)
    @ObservedObject private var shazam = AscoltoShazam.condiviso
    @Environment(\.accessibilityReduceMotion) private var ridotto
    @State private var base: Double = 0                // dove si è fermato (gradi)
    @State private var da: Date?                       // da quando gira

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: da == nil)) { t in
            IconaVinile().rotationEffect(.degrees(angolo(t.date)))
        }
        .onChange(of: (lettore.suona || shazam.suonaDentro) && !ridotto, initial: true) { _, gira in
            if gira {
                if da == nil { da = Date() }
            } else if da != nil {
                base = angolo(Date()).truncatingRemainder(dividingBy: 360)
                da = nil
            }
        }
    }

    private func angolo(_ ora: Date) -> Double { base + (da.map { ora.timeIntervalSince($0) } ?? 0) * 360 / 1.8 }
}

/// I cinque tasti della sezione, disegnati come gli SVG del mockup.
struct IconaTastoMusica: View {
    enum Tipo { case casuale, precedente, play, pausa, successivo, ripeti }
    let tipo: Tipo

    var body: some View {
        Canvas { gc, size in
            let k = min(size.width, size.height) / 24
            let dx = (size.width - 24 * k) / 2, dy = (size.height - 24 * k) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * k, y: dy + y * k) }
            func linea(_ punti: [(CGFloat, CGFloat)], chiusa: Bool = false) -> Path {
                var q = Path()
                q.move(to: p(punti[0].0, punti[0].1))
                for t in punti.dropFirst() { q.addLine(to: p(t.0, t.1)) }
                if chiusa { q.closeSubpath() }
                return q
            }
            let stile = StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round)
            switch tipo {
            case .casuale:
                for t in [linea([(3, 7), (6, 7), (15, 17), (21, 17)]), linea([(3, 17), (6, 17), (9, 13.5)]), linea([(13, 10.5), (15, 7), (21, 7)]),
                          linea([(18, 4), (21, 7), (18, 10)]), linea([(18, 14), (21, 17), (18, 20)])] {
                    gc.stroke(t, with: .foreground, style: stile)
                }
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
            case .ripeti:
                var su = Path()                                   // M4 11V9a3 3 0 0 1 3-3h12
                su.move(to: p(4, 11)); su.addLine(to: p(4, 9))
                su.addArc(center: p(7, 9), radius: 3 * k, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                su.addLine(to: p(19, 6))
                var giu = Path()                                  // M20 13v2a3 3 0 0 1-3 3H5
                giu.move(to: p(20, 13)); giu.addLine(to: p(20, 15))
                giu.addArc(center: p(17, 15), radius: 3 * k, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                giu.addLine(to: p(5, 18))
                for t in [su, giu, linea([(16, 3), (19, 6), (16, 9)]), linea([(8, 21), (5, 18), (8, 15)])] {
                    gc.stroke(t, with: .foreground, style: stile)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Il polso: la musica dell'iPhone comandata dall'Apple Watch

/// L'orologio chiede «stato», «play», «pausa», «avanti», «indietro» (PonteTelefono): risponde con titolo, artista, durata, tempo e play.
enum PonteMusica {
    static func esegui(_ comando: String) async -> [String: Any] {
        let l = LettoreMusica.condiviso
        // MARK X: Shazam al polso → la canzone suona sull'iPhone. 8 nov (il signore: «Shazam al polso senza Apple Music»): come lo
        // Shazam del telefono (AscoltoShazam), Apple Music intero se può, se no l'anteprima di 30 s; il PLAY/PAUSA di quella scheda
        // arriva come «shazam:play» / «shazam:pausa» (la MUSICA del polso resta sul lettore di Apple Music, qui sotto).
        if comando.hasPrefix("brano:") || comando.hasPrefix("shazam:") { return await shazamDalPolso(comando) }
        guard MusicAuthorization.currentStatus == .authorized else {
            return ["errore": "Apra MUSICA sull'iPhone e dia il permesso ad Apple Music, Sir."]
        }
        switch comando {
        case "play": await l.play()
        case "pausa": l.pausa()
        case "avanti": await l.avanti()
        case "indietro": await l.indietro()
        default: break
        }
        if comando != "stato" { try? await Task.sleep(for: .milliseconds(250)) }     // il lettore ha cambiato brano: si legge quello nuovo
        l.aggiorna()
        var r: [String: Any] = ["titolo": l.titolo, "artista": l.artista, "tempo": l.tempo, "suona": l.suona]
        if let d = l.durata { r["durata"] = d }
        if let e = l.errore { r["errore"] = e }
        return r
    }

    /// Shazam al polso: «brano:{id, titolo, artista, cerca}» la fa suonare; «shazam:play» e «shazam:pausa» la comandano.
    /// Risponde se suona, da dove («APPLE MUSIC» o «APPLE · ANTEPRIMA 30 S») e l'eventuale errore.
    private static func shazamDalPolso(_ comando: String) async -> [String: Any] {
        let a = AscoltoShazam.condiviso, l = LettoreMusica.condiviso
        if comando.hasPrefix("brano:") {
            let d = (try? JSONSerialization.jsonObject(with: Data(comando.dropFirst(6).utf8))) as? [String: String] ?? [:]
            let cerca = d["cerca"] ?? "", id = d["id"] ?? ""
            await a.suona(titolo: d["titolo"] ?? cerca, artista: d["artista"] ?? "", appleID: id.isEmpty ? nil : id, dalPolso: true)
        } else {
            let si = comando == "shazam:play"
            switch a.fonte {
            case .anteprima: await a.anteprimaDalPolso(suona: si)
            case .intero: if si { await l.play() } else { l.pausa() }
            case .video, .nessuna: break
            }
        }
        try? await Task.sleep(for: .milliseconds(250))     // il lettore ha appena cambiato: si legge com'è adesso
        l.aggiorna()
        var r: [String: Any] = ["suona": a.suonaOra, "fonte": AscoltoShazam.scritta(a.fonte)]
        if let e = a.errore ?? (a.fonte == .intero ? l.errore : nil) { r["errore"] = e }
        return r
    }
}
#endif
