#if os(iOS)
import AVFoundation
import MusicKit

/// «Wake up, daddy's home.» Due battiti di mani (o la frase di Tony) e JARVIS si sveglia come nel film:
/// qualche secondo di «Should I Stay or Should I Go» dei Clash, che sfuma, e poi il saluto.
/// Il pezzo è l'anteprima ufficiale di Apple Music (va anche senza abbonamento, basta il permesso a Musica).
/// Se Apple Music non risponde, parte il suono d'avvio di JARVIS: il saluto c'è comunque.
@MainActor
enum Benvenuto {
    private static var lettore: AVPlayer?
    private static var anteprima: URL?

    /// La frase di Tony, anche come la storpia il riconoscimento italiano.
    nonisolated static func eFraseDiTony(_ frase: String) -> Bool {
        let f = frase.lowercased()
        if f.contains("papà è a casa") || f.contains("papà è tornato") { return true }
        // «daddy» da solo non basta (una canzone, un nome): serve anche «home» o «wake up»
        let papa = ["daddy", "daddi", "deddy", "dedi's", "dady"].contains { f.contains($0) }
        return papa && ["home", "hom", "wake", "weak", "uek", "week"].contains { f.contains($0) }
    }

    /// Qualche secondo di Clash, poi sfuma. Restituisce falso se non è riuscito a farlo partire.
    static func suona(secondi: Double = 7) async -> Bool {
        guard let url = await trovaAnteprima() else { Suoni.avvio(); return false }
        let sessione = AVAudioSession.sharedInstance()
        try? sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try? sessione.setActive(true)
        let p = AVPlayer(url: url)
        p.volume = 0.85
        lettore = p
        p.play()
        try? await Task.sleep(for: .seconds(secondi))
        for passo in stride(from: 0.85, through: 0.0, by: -0.085) {          // sfuma in poco meno di un secondo
            p.volume = Float(max(0, passo))
            try? await Task.sleep(for: .milliseconds(90))
        }
        p.pause()
        lettore = nil
        return true
    }

    /// Il saluto, secondo l'ora.
    static func saluto() -> String {
        let ora = Calendar.current.component(.hour, from: Date())
        let quando = ora < 6 ? "Notte fonda, Sir" : ora < 13 ? "Buongiorno, Sir" : ora < 19 ? "Bentornato a casa, Sir" : "Buonasera, Sir"
        return "\(quando). Tutti i sistemi sono operativi. Cosa facciamo?"
    }

    /// L'anteprima del pezzo dal catalogo di Apple Music (cercata una volta sola, poi tenuta a mente).
    private static func trovaAnteprima() async -> URL? {
        if let anteprima { return anteprima }
        guard await MusicAuthorization.request() == .authorized else { return nil }
        var r = MusicCatalogSearchRequest(term: "Should I Stay or Should I Go The Clash", types: [Song.self])
        r.limit = 8
        guard let brani = try? await r.response().songs else { return nil }
        let scelto = brani.first { $0.artistName.lowercased().contains("clash") && $0.title.lowercased().hasPrefix("should i stay") } ?? brani.first
        anteprima = scelto?.previewAssets?.first?.url
        return anteprima
    }
}
#endif
