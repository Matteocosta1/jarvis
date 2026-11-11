#if os(iOS)
import Foundation

// MARK: - 11 nov · Le copie nell'Archivio centrale (approvato dal signore il 10 nov: «perfetto»)
// Ogni salvataggio delle sezioni va anche nell'Archivio (Dock › Sistemi › Archivio), in una cartella per sezione:
// lidar, wiretap, satellite, studio, scanner, traccia. La copia parte in sottofondo e non ferma mai la sezione: se la rete manca
// riprova tre volte; il salvataggio sul telefono c'è comunque. Il cervello accetta file fino a 50 MB: dal telefono si mandano
// al massimo 20 MB (un modello 3D più grande resta solo sul telefono, con la sua scheda di testo nell'Archivio).

enum ArchivioCentrale {
    nonisolated static let limite = 20 * 1_048_576

    /// Una copia di un file (foto, modello 3D…).
    static func copia(nome: String, cartella: String, tipo: String, dati: Data, descrizione: String? = nil) {
        guard !dati.isEmpty, dati.count <= limite else { return }
        let indirizzo = Impostazioni.indirizzo, token = Portachiavi.leggi()
        Task.detached(priority: .utility) {
            var file: [String: Any] = ["nome": nome, "cartella": cartella, "tipo": tipo, "base64": dati.base64EncodedString()]
            if let descrizione { file["descrizione"] = descrizione }
            await ArchivioCentrale.invia(["archivio_carica": file], indirizzo: indirizzo, token: token)
        }
    }

    /// Una scheda di testo (le misure di una scansione, un luogo, un prodotto…).
    static func copiaTesto(nome: String, cartella: String, testo: String, descrizione: String? = nil) {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let indirizzo = Impostazioni.indirizzo, token = Portachiavi.leggi()
        Task.detached(priority: .utility) {
            var file: [String: Any] = ["nome": nome, "cartella": cartella, "tipo": "text/plain", "testo": t + "\n"]
            if let descrizione { file["descrizione"] = descrizione }
            await ArchivioCentrale.invia(["archivio_carica": file], indirizzo: indirizzo, token: token)
        }
    }

    /// Un file del telefono (un modello 3D salvato): letto in sottofondo, mandato se non supera il limite.
    static func copiaFile(_ url: URL, nome: String, cartella: String, tipo: String, descrizione: String? = nil) {
        let indirizzo = Impostazioni.indirizzo, token = Portachiavi.leggi()
        Task.detached(priority: .utility) {
            guard let dati = try? Data(contentsOf: url), !dati.isEmpty, dati.count <= ArchivioCentrale.limite else { return }
            var file: [String: Any] = ["nome": nome, "cartella": cartella, "tipo": tipo, "base64": dati.base64EncodedString()]
            if let descrizione { file["descrizione"] = descrizione }
            await ArchivioCentrale.invia(["archivio_carica": file], indirizzo: indirizzo, token: token)
        }
    }

    /// «Scansione 11 nov 2026 21.40»: data e ora per i nomi dei file (senza i due punti, che nei nomi dei file non vanno).
    nonisolated static func quando(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMM yyyy HH.mm"
        return f.string(from: d)
    }

    nonisolated private static func invia(_ corpo: [String: Any], indirizzo: String, token: String) async {
        guard let url = URL(string: indirizzo), let body = try? JSONSerialization.data(withJSONObject: corpo) else { return }
        for tentativo in 0..<3 {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 90
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
            req.httpBody = body
            if let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], o["errore"] == nil {
                return
            }
            try? await Task.sleep(for: .seconds(Double(5 * (tentativo + 1))))
        }
    }
}
#endif
