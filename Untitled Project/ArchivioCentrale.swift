#if os(iOS)
import Foundation
import Combine
import UIKit

// MARK: - 11 nov · Le copie nell'Archivio centrale (approvato dal signore il 10 nov: «perfetto»)
// Ogni salvataggio delle sezioni va anche nell'Archivio (Dock › Sistemi › Archivio), in una cartella per sezione:
// lidar, wiretap, satellite, studio, scanner, traccia.
// 13 nov (il signore: «fai quello che proponi»): SALVATAGGIO SICURO. Ogni copia entra in una coda sul telefono e ci resta finché
// l'Archivio non conferma che è arrivata: rete assente, app chiusa a metà, telefono spento… riparte da sola all'avvio e a ogni
// rientro nell'app. I file grandi (modelli 3D fino a 50 MB, il limite dell'Archivio) vanno direttamente nello spazio dell'Archivio
// con un indirizzo firmato, senza passare dal cervello (prima oltre 20 MB non partivano e nessuno lo diceva).

enum ArchivioCentrale {
    /// Il limite dell'Archivio (50 MB a file).
    nonisolated static let limite = 50 * 1_048_576
    /// Fino a qui il file passa dal cervello in un colpo solo; sopra, caricamento diretto.
    nonisolated static let limitePassaggio = 3 * 1_048_576

    /// Una copia di un file (foto, modello 3D…). `gruppo`: le copie di uno stesso salvataggio (la scheda e il 3D di una scansione),
    /// per dire a schermo quando sono arrivate tutte.
    static func copia(nome: String, cartella: String, tipo: String, dati: Data, descrizione: String? = nil, gruppo: String? = nil) {
        CodaArchivio.condivisa.aggiungi(nome: nome, cartella: cartella, tipo: tipo, descrizione: descrizione, gruppo: gruppo) { url in
            try dati.write(to: url, options: .atomic)
        }
    }

    /// Una scheda di testo (le misure di una scansione, un luogo, un prodotto…).
    static func copiaTesto(nome: String, cartella: String, testo: String, descrizione: String? = nil, gruppo: String? = nil) {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        copia(nome: nome, cartella: cartella, tipo: "text/plain", dati: Data((t + "\n").utf8), descrizione: descrizione, gruppo: gruppo)
    }

    /// Un file del telefono (un modello 3D salvato): copiato nella coda subito (su APFS è una copia istantanea), poi inviato.
    static func copiaFile(_ url: URL, nome: String, cartella: String, tipo: String, descrizione: String? = nil, gruppo: String? = nil) {
        CodaArchivio.condivisa.aggiungi(nome: nome, cartella: cartella, tipo: tipo, descrizione: descrizione, gruppo: gruppo) { destinazione in
            try FileManager.default.copyItem(at: url, to: destinazione)
        }
    }

    /// «Scansione 11 nov 2026 21.40»: data e ora per i nomi dei file (senza i due punti, che nei nomi dei file non vanno).
    nonisolated static func quando(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMM yyyy HH.mm"
        return f.string(from: d)
    }
}

/// A che punto è la copia di un salvataggio nell'Archivio.
nonisolated enum StatoCopiaArchivio: Equatable, Sendable {
    case inViaggio                  // in coda o in invio
    case arrivata                   // l'Archivio ha confermato tutto
    case inAttesa                   // non arrivata (rete): riprova da sola
    case rifiutata(String)          // l'Archivio non la prende (file troppo grande, tipo non accettato): non si riprova
}

/// La coda delle copie: su disco (Application Support/CodaArchivio), una alla volta, nell'ordine in cui sono state salvate.
@MainActor
final class CodaArchivio: ObservableObject {
    static let condivisa = CodaArchivio()

    /// Una copia in attesa di arrivare. Il contenuto è il file `id` nella cartella della coda.
    nonisolated struct Voce: Codable, Sendable {
        var id: UUID
        var nome: String
        var cartella: String
        var tipo: String
        var descrizione: String?
        var gruppo: String?
        var dimensione: Int
        var tentativi: Int
        var creata: Date
    }

    @Published private(set) var stati: [String: StatoCopiaArchivio] = [:]
    private var voci: [Voce] = []
    private var lavoro: Task<Void, Never>?
    private var riprova: Task<Void, Never>?
    private var falliti = 0

    nonisolated static let cartella: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let c = base.appendingPathComponent("CodaArchivio", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }()
    private var indice: URL { Self.cartella.appendingPathComponent("coda.json") }

    private init() {
        if let d = try? Data(contentsOf: indice), let v = try? JSONDecoder().decode([Voce].self, from: d) {
            // solo le voci col loro file ancora sul disco
            voci = v.filter { FileManager.default.fileExists(atPath: Self.cartella.appendingPathComponent($0.id.uuidString).path) }
        }
        _ = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in CodaArchivio.condivisa.avvia() }
        }
    }

    var inCoda: Int { voci.count }

    /// Mette una copia in coda: `scrivi` prepara il contenuto nel file della coda (sul momento, così una scheda e il suo 3D
    /// entrano insieme e «arrivata» si dice solo quando sono arrivati tutti e due).
    func aggiungi(nome: String, cartella: String, tipo: String, descrizione: String?, gruppo: String?, scrivi: (URL) throws -> Void) {
        let id = UUID()
        let url = Self.cartella.appendingPathComponent(id.uuidString)
        do { try scrivi(url) } catch { if let gruppo { stati[gruppo] = .rifiutata("Il file da copiare non si legge.") }; return }
        let dim = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard dim > 0 else { try? FileManager.default.removeItem(at: url); return }
        guard dim <= ArchivioCentrale.limite else {
            try? FileManager.default.removeItem(at: url)
            if let gruppo { stati[gruppo] = .rifiutata("Il modello 3D pesa \(dim / 1_048_576) MB: l'Archivio accetta file fino a 50 MB. Resta sul telefono.") }
            return
        }
        voci.append(Voce(id: id, nome: nome, cartella: cartella, tipo: tipo, descrizione: descrizione, gruppo: gruppo,
                         dimensione: dim, tentativi: 0, creata: Date()))
        if let gruppo, stati[gruppo] == nil || stati[gruppo] == .arrivata { stati[gruppo] = .inViaggio }
        scriviIndice()
        falliti = 0
        avvia()
    }

    /// Fa partire la coda (all'avvio dell'app, a ogni rientro, dopo un salvataggio). Una sola corsa alla volta.
    func avvia() {
        guard lavoro == nil, !voci.isEmpty else { return }
        riprova?.cancel(); riprova = nil
        lavoro = Task { @MainActor in
            await self.giro()
            self.lavoro = nil
        }
    }

    private func giro() async {
        // uscendo dall'app iOS concede ancora qualche secondo: la copia in corso li usa per finire (CompitoSfondo: Radar.swift)
        let compito = CompitoSfondo()
        compito.id = UIApplication.shared.beginBackgroundTask(withName: "Archivio") { compito.chiudi() }
        defer { compito.chiudi() }
        let indirizzo = Impostazioni.indirizzo, token = Portachiavi.leggi()
        while let voce = voci.first {
            if let g = voce.gruppo, stati[g] == nil || stati[g] == .inAttesa { stati[g] = .inViaggio }
            let file = Self.cartella.appendingPathComponent(voce.id.uuidString)
            let esito = await InvioArchivio.invia(voce, file: file, indirizzo: indirizzo, token: token)
            switch esito {
            case .ok:
                togli(voce, file: file)
                falliti = 0
                if let g = voce.gruppo, !voci.contains(where: { $0.gruppo == g }), stati[g] == .inViaggio { stati[g] = .arrivata }
            case .rifiutata(let motivo):
                // l'Archivio ha risposto ma non la prende: dopo tre risposte uguali non si insiste (resta sul telefono)
                if voce.tentativi >= 2 {
                    togli(voce, file: file)
                    if let g = voce.gruppo { stati[g] = .rifiutata("L'Archivio non l'ha presa: \(motivo).") }
                } else {
                    segnaTentativo(voce)
                    pausa()
                    return
                }
            case .rete:
                segnaTentativo(voce)
                for g in Set(voci.compactMap(\.gruppo)) where stati[g] == .inViaggio { stati[g] = .inAttesa }
                pausa()
                return
            }
        }
    }

    private func togli(_ voce: Voce, file: URL) {
        voci.removeAll { $0.id == voce.id }
        try? FileManager.default.removeItem(at: file)
        scriviIndice()
    }

    private func segnaTentativo(_ voce: Voce) {
        if let i = voci.firstIndex(where: { $0.id == voce.id }) { voci[i].tentativi += 1 }
        scriviIndice()
    }

    /// Niente rete o Archivio occupato: si riprova da soli, sempre più piano (30 s, 1, 2, 4… fino a 10 minuti), finché l'app è aperta;
    /// altrimenti alla prossima apertura.
    private func pausa() {
        falliti += 1
        let attesa = min(600, 30 * pow(2, Double(min(falliti - 1, 5))))
        riprova?.cancel()
        riprova = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(attesa))
            guard !Task.isCancelled, let self else { return }
            self.riprova = nil
            if UIApplication.shared.applicationState == .active { self.avvia() }
        }
    }

    private func scriviIndice() {
        if let d = try? JSONEncoder().encode(voci) { try? d.write(to: indice, options: .atomic) }
    }
}

// MARK: - L'invio di una copia (fuori dal thread principale: la lettura e la codifica di un file di qualche MB non toccano le animazioni)

nonisolated enum InvioArchivio {
    enum Esito: Sendable { case ok, rete, rifiutata(String) }

    @concurrent static func invia(_ v: CodaArchivio.Voce, file: URL, indirizzo: String, token: String) async -> Esito {
        guard let url = URL(string: indirizzo) else { return .rete }                       // indirizzo del cervello non ancora impostato: la copia aspetta
        guard let dati = try? Data(contentsOf: file, options: .mappedIfSafe) else { return .rifiutata("file non leggibile") }
        if dati.count <= ArchivioCentrale.limitePassaggio {
            var f: [String: Any] = ["nome": v.nome, "cartella": v.cartella, "tipo": v.tipo]
            if v.tipo.hasPrefix("text/"), let t = String(data: dati, encoding: .utf8) { f["testo"] = t } else { f["base64"] = dati.base64EncodedString() }
            if let d = v.descrizione { f["descrizione"] = d }
            return esito(await cervello(["archivio_carica": f], url: url, token: token, attesa: 90))
        }
        // file grande: indirizzo firmato, caricamento diretto, poi la riga nell'indice dell'Archivio
        var richiesta: [String: Any] = ["nome": v.nome, "cartella": v.cartella, "tipo": v.tipo, "dimensione": dati.count]
        if let d = v.descrizione { richiesta["descrizione"] = d }
        guard let firma = await cervello(["archivio_firma": richiesta], url: url, token: token, attesa: 30) else { return .rete }
        if let e = firma["errore"] as? String { return .rifiutata(e) }
        guard let su = (firma["url"] as? String).flatMap(URL.init(string:)), let percorso = firma["percorso"] as? String else { return .rete }
        var put = URLRequest(url: su)
        put.httpMethod = "PUT"
        put.timeoutInterval = 300
        put.setValue(firma["tipo"] as? String ?? v.tipo, forHTTPHeaderField: "Content-Type")
        put.setValue("true", forHTTPHeaderField: "x-upsert")
        guard let (_, r) = try? await URLSession.shared.upload(for: put, from: dati), let codice = (r as? HTTPURLResponse)?.statusCode else { return .rete }
        if codice == 413 { return .rifiutata("file troppo grande") }
        guard (200..<300).contains(codice) else { return codice >= 500 ? .rete : .rifiutata("caricamento rifiutato (\(codice))") }
        var registra: [String: Any] = ["percorso": percorso, "tipo": v.tipo, "dimensione": dati.count]
        if let d = v.descrizione { registra["descrizione"] = d }
        return esito(await cervello(["archivio_registra": registra], url: url, token: token, attesa: 30))
    }

    private static func esito(_ o: [String: Any]?) -> Esito {
        guard let o else { return .rete }
        if let e = o["errore"] as? String { return .rifiutata(e) }
        return o["ok"] as? Bool == true ? .ok : .rete
    }

    private static func cervello(_ corpo: [String: Any], url: URL, token: String, attesa: TimeInterval) async -> [String: Any]? {
        guard let body = try? JSONSerialization.data(withJSONObject: corpo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = attesa
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = body
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
#endif
