#if os(iOS)
import Foundation
import SwiftUI
import Combine
import AVFoundation
import CoreMedia
import MusicKit
import WebKit

// MARK: - SHAZAM › da dove si ascolta la canzone trovata (8 nov notte, il signore: «Shazam quando riconosce la canzone deve aprire
// un player per ascoltarla o su Apple Music o YouTube, come abbiamo fatto con Vinyl Hustler»). Come Ascolto.swift di Vinyl Hustler:
//   1. APPLE MUSIC, brano intero: col permesso e l'abbonamento (il lettore di sistema, lo stesso di MUSICA e dei comandi a voce);
//   2. APPLE, anteprima di 30 secondi: per tutti, gratis (ricerca iTunes, la stessa anteprima di iTunes);
//   3. YOUTUBE: il video, cercato dal cervello (funzione «browser-video», come il visore del Browser), nel lettore ufficiale.
// Il tasto YOUTUBE del player passa al video (e APPLE torna all'audio): il signore sceglie, JARVIS parte dalla fonte migliore.

@MainActor
final class AscoltoShazam: ObservableObject {
    static let condiviso = AscoltoShazam()

    enum Fonte: Equatable { case intero, anteprima, video, nessuna }

    @Published private(set) var fonte: Fonte = .nessuna
    @Published private(set) var cercando = false
    @Published private(set) var videoID: String?
    @Published private(set) var brano: Song?
    @Published private(set) var suonaAnteprima = false
    @Published private(set) var tempoAnteprima: Double = 0
    @Published private(set) var durataAnteprima: Double = 30
    @Published var errore: String?
    /// 8 nov · il video di YouTube suona adesso (lo dice WebKit): serve al PLAY/PAUSA del mini-player e alla luce della copertina.
    @Published private(set) var suonaVideo = false

    private var anteprima: URL?
    private weak var webVideo: WKWebView?      // il lettore di YouTube nel player (LettoreYouTube), finché si vede
    private var orologioVideo: Task<Void, Never>?
    private var lettore30: AVPlayer?
    private var orologio: Task<Void, Never>?
    private var giro = 0                       // la canzone in corso: una risposta vecchia non tocca quella nuova
    /// 9 nov · i video trovati per la canzone, in ordine: se uno non si può guardare qui, parte il successivo (riserva).
    private var videoRiserva: [String] = []

    private init() {}

    static func scritta(_ f: Fonte) -> String {
        switch f {
        case .intero: "APPLE MUSIC"
        case .anteprima: "APPLE · ANTEPRIMA 30 S"
        case .video: "YOUTUBE"
        case .nessuna: "CERCO…"
        }
    }

    // MARK: si parte dalla fonte migliore

    /// `dalPolso` (8 nov, il signore: «Shazam al polso senza Apple Music»): la canzone riconosciuta sull'orologio suona qui allo
    /// stesso modo, ma senza chiedere il permesso (l'iPhone può essere in tasca: il foglio di iOS non si vedrebbe) e senza YouTube
    /// (il video si guarda sul telefono).
    func suona(titolo: String, artista: String, appleID: String?, dalPolso: Bool = false) async {
        ferma()
        // 9 nov: dal video o dall'anteprima ad Apple Music intero, l'audio di JARVIS non le sta davanti. Non dal polso: lì
        // l'iPhone può essere sulla schermata principale con JARVIS che parla (la sua voce non si tocca)
        if !dalPolso { audioARiposo() }
        giro += 1
        let mio = giro
        cercando = true
        errore = nil
        brano = nil
        videoID = nil
        anteprima = nil
        defer { if mio == giro { cercando = false } }
        // 1 · Apple Music intero
        var permesso = MusicAuthorization.currentStatus == .authorized
        if !permesso && !dalPolso { permesso = await CatalogoMusica.autorizzato() }
        if permesso, (try? await MusicSubscription.current)?.canPlayCatalogContent == true,
           let s = await Self.trova(titolo: titolo, artista: artista, appleID: appleID) {
            guard mio == giro else { return }
            brano = s
            fonte = .intero
            await LettoreMusica.condiviso.metti(s)
            return
        }
        guard mio == giro else { return }
        // 2 · l'anteprima di 30 secondi
        if let u = await Self.anteprimaITunes(titolo: titolo, artista: artista) {
            guard mio == giro else { return }
            anteprima = u
            avviaAnteprima(u)
            return
        }
        guard mio == giro else { return }
        // 3 · YouTube (non dal polso)
        guard !dalPolso else { errore = "Non la trovo né su Apple Music né fra le anteprime, Sir."; return }
        await video(titolo: titolo, artista: artista)
    }

    /// Dal polso (8 nov): l'anteprima riparte o si ferma come chiede l'orologio (non è un interruttore: il polso dice cosa vuole).
    func anteprimaDalPolso(suona si: Bool) async {
        guard fonte == .anteprima, si != suonaAnteprima else { return }
        await playPausa()
    }

    /// Il tasto YOUTUBE: il video della canzone (l'audio di Apple si ferma, YouTube vuole che il video si veda).
    func video(titolo: String, artista: String) async {
        let mio = giro
        cercando = true
        defer { if mio == giro { cercando = false } }
        let (lista, e) = await CercaVideo.cerca("\(titolo) \(artista)")
        guard mio == giro else { return }
        guard let v = lista.first else { errore = e ?? "Nessun video per questa canzone, Sir."; return }
        fermaAudio()
        audioDaMusica()
        videoRiserva = lista.dropFirst().map(\.id)
        videoID = v.id
        fonte = .video
        errore = nil
    }

    /// 9 nov (il signore: il video di riserva): il lettore di YouTube dice che questo video qui non si può guardare (chi l'ha
    /// caricato non lo permette, rimosso, privato…): parte da solo il prossimo trovato per la stessa canzone. Finiti, lo dice.
    func videoNonDisponibile(_ id: String, codice: Int) {
        guard fonte == .video, videoID == id else { return }          // una risposta di un video vecchio non tocca quello nuovo
        fermaVideo()
        if !videoRiserva.isEmpty {
            videoID = videoRiserva.removeFirst()
        } else {
            videoID = nil
            errore = "Nessun video di questa canzone si può guardare qui, Sir (YouTube \(codice)). Provi APPLE."
        }
    }

    /// 9 nov notte (il signore: «dal player integrato in Shazam si sente bassissima»): per riconoscere la canzone l'audio di JARVIS
    /// va in «registrazione» (microfono aperto) e ci restava: con il microfono aperto iOS suona tutto a volume da telefonata
    /// (il pallino arancione restava acceso), e appena si usciva dall'app la canzone tornava al volume pieno. Finito l'ascolto il
    /// microfono si chiude e l'audio torna come a riposo («ambient», la musica del lettore di sistema suona piena); l'anteprima e il
    /// video, che suonano dentro JARVIS, lo prendono come musica («playback», come Vinyl Hustler).
    static func chiudiMicrofono() {
        let s = AVAudioSession.sharedInstance()
        guard s.category == .playAndRecord || s.category == .record else { return }
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        try? s.setCategory(.ambient, mode: .default, options: [])
    }

    /// L'audio di JARVIS come musica (anteprima e video). Se l'ascolto di JARVIS ha l'audio (registrazione), non si tocca.
    private func audioDaMusica() {
        let sessione = AVAudioSession.sharedInstance()
        if sessione.category == .ambient || sessione.category == .soloAmbient {
            try? sessione.setCategory(.playback, mode: .default, options: [])
        }
        try? sessione.setActive(true)
    }

    /// Chiuso il player, l'audio torna a riposo (la musica delle altre app risale); se lo usa l'ascolto di JARVIS, non si tocca.
    private func audioARiposo() {
        let sessione = AVAudioSession.sharedInstance()
        guard sessione.category == .playback else { return }
        try? sessione.setActive(false, options: .notifyOthersOnDeactivation)
        try? sessione.setCategory(.ambient, mode: .default, options: [])
    }

    /// Il tasto APPLE: dal video torna all'audio di Apple (intero o anteprima).
    func tornaApple(titolo: String, artista: String, appleID: String?) async {
        await suona(titolo: titolo, artista: artista, appleID: appleID)
    }

    // MARK: i comandi del player (valgono per la fonte in corso)

    var suonaOra: Bool {
        switch fonte {
        case .intero: LettoreMusica.condiviso.suona
        case .anteprima: suonaAnteprima
        case .video: suonaVideo
        case .nessuna: false
        }
    }
    var tempo: Double { fonte == .anteprima ? tempoAnteprima : LettoreMusica.condiviso.tempo }
    var durata: Double? { fonte == .anteprima ? durataAnteprima : LettoreMusica.condiviso.durata }

    func playPausa() async {
        switch fonte {
        case .intero: await LettoreMusica.condiviso.playPausa()
        case .anteprima:
            guard let p = lettore30 else { if let u = anteprima { avviaAnteprima(u) }; return }
            if suonaAnteprima { p.pause() } else {
                if tempoAnteprima >= durataAnteprima - 0.5 { _ = await p.seek(to: .zero) }
                p.play()
            }
            leggi()
        case .video:
            // 8 nov · dal mini-player: col video che suona lo mette in pausa; fermo, lo fa ripartire dov'era
            guard let w = webVideo else { return }
            if await w.requestMediaPlaybackState() == .playing {
                await w.pauseAllMediaPlayback()
            } else {
                await w.setAllMediaPlaybackSuspended(false)                 // sospeso da iOS (una telefonata): riprende
                _ = try? await w.evaluateJavaScript(Self.ripartiVideo)
            }
            suonaVideo = await w.requestMediaPlaybackState() == .playing
        case .nessuna: break
        }
    }

    /// Il lettore di YouTube appena creato (LettoreYouTube nel player): da qui il PLAY/PAUSA del mini-player e lo stato vero del
    /// video (anche quando il signore lo ferma o lo fa ripartire coi tasti di YouTube). Finisce da solo quando il lettore sparisce.
    func agganciaVideo(_ w: WKWebView) {
        webVideo = w
        orologioVideo?.cancel()
        orologioVideo = Task { [weak self] in
            while !Task.isCancelled {
                guard let w = self?.webVideo else { break }
                let stato = await w.requestMediaPlaybackState()
                if !Task.isCancelled { self?.suonaVideo = stato == .playing }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// Il video riparte col comando ufficiale del lettore di YouTube (LettoreYouTube, IFrame API: `cmd`).
    private static let ripartiVideo = "cmd('play')"

    func salta(_ secondi: Double) {
        switch fonte {
        case .intero: LettoreMusica.condiviso.salta(secondi)
        case .anteprima:
            guard let p = lettore30 else { return }
            let t = max(0, min(durataAnteprima, tempoAnteprima + secondi))
            p.seek(to: CMTime(seconds: t, preferredTimescale: 600))
            tempoAnteprima = t
        case .video, .nessuna: break
        }
    }

    func vaiA(_ frazione: Double) {
        switch fonte {
        case .intero: LettoreMusica.condiviso.vaiA(frazione)
        case .anteprima:
            guard let p = lettore30 else { return }
            let t = max(0, min(1, frazione)) * durataAnteprima
            p.seek(to: CMTime(seconds: t, preferredTimescale: 600))
            tempoAnteprima = t
        case .video, .nessuna: break
        }
    }

    /// Il player si chiude: si ferma tutto (9 nov notte, scelta del signore: il player di Shazam è un assaggio), anche Apple Music
    /// intero; con MUSICA (`tieniMusica`) la canzone intera continua e passa nella sezione Musica.
    func chiudi(tieniMusica: Bool = false) {
        giro += 1
        cercando = false
        let dentro = fonte == .anteprima || fonte == .video
        if fonte != .intero || !tieniMusica { ferma() }
        videoID = nil
        videoRiserva = []
        fermaVideo()
        if dentro { audioARiposo() }
    }

    // MARK: dentro

    private func avviaAnteprima(_ u: URL) {
        fermaAudio()
        // 8 nov (controllo): finito l'avvio l'audio dell'app resta «ambient» (Suoni.fineAvvioAudio): l'anteprima taceva col tasto
        // silenzioso e, partita dal polso con l'iPhone in tasca, si fermava. Se nessuno usa l'audio, l'anteprima lo prende come musica;
        // se l'ascolto di JARVIS ha già l'audio (registrazione e riproduzione), non si tocca.
        audioDaMusica()
        let p = AVPlayer(url: u)
        lettore30 = p
        p.play()
        fonte = .anteprima
        durataAnteprima = 30
        tempoAnteprima = 0
        suonaAnteprima = true
        orologio = Task { [weak self] in
            while !Task.isCancelled {
                self?.leggi()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func leggi() {
        guard let p = lettore30 else { return }
        let t = p.currentTime().seconds
        if t.isFinite { tempoAnteprima = t }
        if let d = p.currentItem?.duration.seconds, d.isFinite, d > 0 { durataAnteprima = d }
        suonaAnteprima = p.timeControlStatus != .paused
    }

    private func fermaAudio() {
        orologio?.cancel()
        orologio = nil
        lettore30?.pause()
        lettore30 = nil
        suonaAnteprima = false
        tempoAnteprima = 0
        if fonte == .intero { LettoreMusica.condiviso.pausa() }
    }

    private func ferma() {
        fermaAudio()
        fermaVideo()
        fonte = .nessuna
    }

    private func fermaVideo() {
        orologioVideo?.cancel()
        orologioVideo = nil
        webVideo = nil
        suonaVideo = false
    }

    // MARK: le ricerche

    /// Il brano nel catalogo di Apple Music: dall'id di Shazam, se no per titolo e artista.
    private static func trova(titolo: String, artista: String, appleID: String?) async -> Song? {
        if let id = appleID {
            let r = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
            if let s = try? await r.response().items.first { return s }
        }
        var r = MusicCatalogSearchRequest(term: "\(titolo) \(artista)", types: [Song.self])
        r.limit = 1
        return try? await r.response().songs.first
    }

    private nonisolated struct VoceITunes: Decodable, Sendable {
        var trackName: String?
        var artistName: String?
        var previewUrl: String?
    }
    private nonisolated struct RispostaITunes: Decodable, Sendable { var results: [VoceITunes] }

    /// L'anteprima di 30 secondi di Apple (ricerca iTunes: gratis, senza account), la voce col titolo più vicino.
    private nonisolated static func anteprimaITunes(titolo: String, artista: String) async -> URL? {
        var c = URLComponents(string: "https://itunes.apple.com/search")
        let paese = (Locale.current.region?.identifier ?? "IT").lowercased()
        c?.queryItems = [URLQueryItem(name: "term", value: "\(titolo) \(artista)"), URLQueryItem(name: "entity", value: "song"),
                         URLQueryItem(name: "country", value: paese), URLQueryItem(name: "limit", value: "8")]
        guard let url = c?.url else { return nil }
        let risposta = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard let d = risposta?.0, let r = try? JSONDecoder().decode(RispostaITunes.self, from: d) else { return nil }
        let t = norma(titolo), a = norma(artista)
        let scelta = r.results.first { v in
            let vt = norma(v.trackName ?? ""), va = norma(v.artistName ?? "")
            return v.previewUrl != nil && (vt.contains(t) || t.contains(vt)) && (a.isEmpty || va.contains(a) || a.contains(va))
        } ?? r.results.first { $0.previewUrl != nil && norma($0.trackName ?? "").contains(t) }
        return scelta?.previewUrl.flatMap(URL.init(string:))
    }

    /// «So What (Live)» → «so what»
    private nonisolated static func norma(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        t = t.replacingOccurrences(of: #"\([^)]*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }
}
#endif
