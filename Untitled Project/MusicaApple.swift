import Foundation
import MusicKit

/// «Jarvis, metti …»: fa suonare brani, album, artisti e playlist di Apple Music (serve l'abbonamento).
/// 9 nov sera: usa il lettore DENTRO JARVIS (come la sezione Musica): chiudendo JARVIS la musica finisce, l'app Musica non si tocca.
/// Serve il servizio MusicKit attivo sull'identificativo dell'app e la frase NSAppleMusicUsageDescription.
enum MusicaApple {

    static func riproduci(cerca: String, tipo: String) async -> (String, Bool) {
        let testo = cerca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testo.isEmpty else { return (json(["errore": "manca cosa cercare"]), true) }
        guard await MusicAuthorization.request() == .authorized else {
            return (json(["errore": "il signore non ha dato accesso ad Apple Music: Impostazioni › Jarvis › Contenuti multimediali e Apple Music"]), true)
        }
        do {
            let abbonamento = try await MusicSubscription.current
            guard abbonamento.canPlayCatalogContent else {
                return (json(["errore": "per far partire i brani serve un abbonamento Apple Music attivo"]), true)
            }
            let lettore = ApplicationMusicPlayer.shared
            var suona = ""
            switch tipo {
            case "album":
                var r = MusicCatalogSearchRequest(term: testo, types: [Album.self]); r.limit = 1
                guard let a = try await r.response().albums.first else { return nessuno(testo) }
                lettore.queue = [a]
                suona = "l'album \(a.title) di \(a.artistName)"
            case "playlist":
                var r = MusicCatalogSearchRequest(term: testo, types: [Playlist.self]); r.limit = 1
                guard let p = try await r.response().playlists.first else { return nessuno(testo) }
                lettore.queue = [p]
                suona = "la playlist \(p.name)"
            case "artista":
                var r = MusicCatalogSearchRequest(term: testo, types: [Artist.self]); r.limit = 1
                guard let artista = try await r.response().artists.first else { return nessuno(testo) }
                let dettagli = try await artista.with([.topSongs])
                guard let tutti = dettagli.topSongs, !tutti.isEmpty else { return nessuno(testo) }
                // 26 nov (dialogo delle 4:29: chiesto Tony Boy, partiva un brano di Sfera Ebbasta): fra i più ascoltati dell'artista
                // Apple Music mette anche i brani di altri dove lui è solo ospite. In coda vanno solo quelli dove è l'artista
                // principale (il suo nome in testa); se non ce n'è nessuno, la classifica com'è. Al cervello torna il brano che parte.
                let suoi = tutti.filter { MusicaApple.principale(artista.name, di: $0.artistName) }
                let brani: [Song] = suoi.isEmpty ? Array(tutti) : suoi
                lettore.queue = ApplicationMusicPlayer.Queue(for: brani)
                let primo = brani[0]
                suona = "i brani più ascoltati di \(artista.name): parte «\(primo.title)» di \(primo.artistName)"
            default:
                var r = MusicCatalogSearchRequest(term: testo, types: [Song.self]); r.limit = 1
                guard let b = try await r.response().songs.first else { return nessuno(testo) }
                lettore.queue = [b]
                suona = "\(b.title) di \(b.artistName)"
            }
            await LettoreMusica.condiviso.play()
            if let e = LettoreMusica.condiviso.errore { return (json(["errore": e]), true) }
            return (json(["ok": true, "in_riproduzione": suona]), false)
        } catch {
            return (json(["errore": "Apple Music: \(error.localizedDescription)"]), true)
        }
    }

    static func controllo(azione: String) async -> (String, Bool) {
        let l = LettoreMusica.condiviso
        l.errore = nil
        switch azione {
        case "pausa": l.pausa()
        case "play": await l.play()
        case "avanti": await l.avanti()
        case "indietro": await l.indietro()
        default: return (json(["errore": "azione sconosciuta: \(azione)"]), true)
        }
        if let e = l.errore { return (json(["errore": e]), true) }
        return (json(["ok": true]), false)
    }

    /// L'artista cercato è il principale del brano? «Tony Boy» sì per «Tony Boy» e «Tony Boy & Guè», no per «Sfera Ebbasta & Tony Boy».
    nonisolated static func principale(_ artista: String, di nomeBrano: String) -> Bool {
        let a = artista.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
        let b = nomeBrano.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
        return !a.isEmpty && b.hasPrefix(a)
    }

    private static func nessuno(_ testo: String) -> (String, Bool) {
        (json(["trovato": false, "nota": "niente su Apple Music per «\(testo)»"]), false)
    }

    private static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}
