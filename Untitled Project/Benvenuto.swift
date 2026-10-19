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
        let f = frase.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard f.count <= 32 else { return false }        // solo la frase di Tony, non un discorso che la contiene
        if f.contains("papà è a casa") || f.contains("papà è tornato") { return true }
        // «daddy» da solo non basta (una canzone, un nome): serve anche «home» o «wake up»
        let papa = ["daddy", "daddi", "deddy", "deddi", "dady", "dad's", "dads"].contains { f.contains($0) }   // niente «dedi», «dadi»: dedica, dadi…
        // il Mac capisce anche «backup daddy», «wake up daddy», «daddy's back»…
        let resto = ["home", "hom", " om", "wake", "weak", "uek", "week", "uei", "ueik", "ap ", "up", "back", "bek"].contains { f.contains($0) }
        return papa && resto
    }

    /// Qualche secondo di Clash, poi sfuma. Restituisce falso se non è riuscito a farlo partire.
    static func suona(secondi: Double = 7) async -> Bool {
        if Impostazioni.muto { return false }                 // modalità silenziosa: niente musica
        let trovato = await anteprimaEntro(secondi: 3)
        if Task.isCancelled { return false }                  // interrotto mentre cercava: niente musica né suono d'avvio
        guard let url = trovato else {
            Suoni.avvio()
            try? await Task.sleep(for: .seconds(1.5))      // il suono d'avvio finisce prima del saluto
            return false
        }
        let sessione = AVAudioSession.sharedInstance()
        try? sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try? sessione.setActive(true)
        let p = AVPlayer(url: url)
        p.volume = 0.85
        lettore = p
        p.play()
        try? await Task.sleep(for: .seconds(secondi))
        for passo in stride(from: 0.85, through: 0.0, by: -0.085) {          // sfuma in poco meno di un secondo
            if Task.isCancelled || lettore !== p { break }
            p.volume = Float(max(0, passo))
            try? await Task.sleep(for: .milliseconds(90))
        }
        p.pause()
        if lettore === p { lettore = nil }
        return !Task.isCancelled
    }

    /// Ferma subito la musica (il signore ha toccato il reattore, è arrivato un avviso…).
    static func ferma() {
        lettore?.pause()
        lettore = nil
    }

    /// L'anteprima, ma senza far aspettare: se Apple Music non risponde entro pochi secondi si va avanti senza
    /// (la ricerca continua per conto suo e il risultato resta in memoria per la volta dopo).
    private static func anteprimaEntro(secondi: Double) async -> URL? {
        if let anteprima { return anteprima }
        let fatto = Fatto()
        return await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            Task { @MainActor in let u = await trovaAnteprima(); if !fatto.si { fatto.si = true; c.resume(returning: u) } }
            Task { @MainActor in try? await Task.sleep(for: .seconds(secondi)); if !fatto.si { fatto.si = true; c.resume(returning: nil) } }
        }
    }
    private final class Fatto { var si = false }

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
