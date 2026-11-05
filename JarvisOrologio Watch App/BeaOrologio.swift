import SwiftUI
import WatchKit
import UIKit
import Combine

/// Bea sul polso: le prossime date, le promesse da mantenere (scorrere per segnarle), cosa ama,
/// le lezioni di oggi, e due domande a JARVIS. Per aggiungere: basta dirlo a JARVIS.
struct VistaBeaOrologio: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.dismiss) private var chiudi
    @State private var dati: [String: Any]?
    @State private var errore = false
    @State private var pensiero: String?
    @State private var scrive = false
    @State private var fotoOlo: UIImage?          // 11.0 (6): Bea in ologramma, fatta sull'iPhone dalla foto scelta là
    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
    private let calda = Color(red: 1.0, green: 0.62, blue: 0.72)

    var body: some View {
        List {
            Section {
                rigaOlo.listRowBackground(Color.clear)
                if let p = pensiero {
                    Text(p).font(.footnote)
                    Button { manda(p) } label: { Label("Manda", systemImage: "paperplane.fill") }.tint(ciano)
                    Button { Task { await scrivi() } } label: { Label("Un altro", systemImage: "arrow.clockwise") }
                } else {
                    Button { Task { await scrivi() } } label: {
                        if scrive { ProgressView() } else { Label("Ti penso", systemImage: "sparkles") }
                    }
                    .disabled(scrive)
                }
            }

            Section {
                Button { jarvis.chiedi("Reparto Bea: aiutami a scrivere adesso un messaggio per Bea, breve e vero, con le mie parole. Guarda la sua scheda."); chiudi() } label: {
                    Label("Cosa le scrivo?", systemImage: "text.bubble")
                }
                Button { jarvis.chiedi("Reparto Bea: guarda la sua scheda e il suo lavoro di oggi e dimmi un gesto concreto per esserle vicino oggi."); chiudi() } label: {
                    Label("Un gesto per oggi", systemImage: "hands.and.sparkles")
                }
            }

            if let d = dati {
                let date = d["date"] as? [[String: Any]] ?? []
                Section {
                    if date.isEmpty { Text("Nessuna data segnata").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(date.prefix(5).enumerated()), id: \.offset) { _, r in
                        let tra = (r["tra_giorni"] as? NSNumber)?.intValue ?? 0
                        HStack {
                            Text(tra == 0 ? "OGGI" : "\(tra)g").font(.system(.footnote, design: .monospaced).bold())
                                .foregroundStyle(tra <= 7 ? calda : ciano).frame(width: 40, alignment: .leading)
                            Text(r["testo"] as? String ?? "").font(.footnote).lineLimit(2)
                        }
                    }
                } header: { Label("Date", systemImage: "calendar") }

                let promesse = d["promesse"] as? [[String: Any]] ?? []
                if !promesse.isEmpty {
                    Section {
                        ForEach(Array(promesse.enumerated()), id: \.element.chiaveRiga) { _, r in
                            Text(r["testo"] as? String ?? "").font(.footnote)
                                .swipeActions {
                                    Button { Task { await fatto(r) } } label: { Label("Mantenuta", systemImage: "checkmark") }.tint(.green)
                                }
                        }
                    } header: { Label("Promesse", systemImage: "hand.raised") }
                }

                let gusti = (d["gusti"] as? [[String: Any]] ?? []).compactMap { $0["testo"] as? String }
                if !gusti.isEmpty {
                    Section {
                        Text(gusti.prefix(8).joined(separator: " · ")).font(.footnote)
                    } header: { Label("Cosa ama", systemImage: "heart.fill") }
                }

                if let l = d["lavoro"] as? [String: Any], (l["collegato"] as? Bool) == true {
                    let lezioni = l["lezioni"] as? [[String: Any]] ?? []
                    Section {
                        if lezioni.isEmpty { Text("Nessuna lezione oggi").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(Array(lezioni.enumerated()), id: \.offset) { _, x in
                            Text([x["ora"] as? String, x["cliente"] as? String].compactMap { $0 }.joined(separator: " · ")).font(.footnote)
                        }
                    } header: { Label("Il suo lavoro oggi", systemImage: "figure.pilates") }
                }
            } else if errore {
                Text("Non raggiungo la scheda, Sir.").font(.footnote)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Bea")
        .onAppear { WKInterfaceDevice.current().play(.start); SuoniOrologio.schedaApre() }   // come tutte le altre schede
        .task { await carica(); if dati != nil { WKInterfaceDevice.current().play(.success); SuoniOrologio.schedaPronta() } }
        .task {                                    // 11.0 (6): l'ologramma che c'è già, poi all'iPhone se ne ha uno nuovo
            fotoOlo = FotoBeaPolso.immagine()
            await PonteOrologio.condiviso.chiediBea()
        }
        .onReceive(NotificationCenter.default.publisher(for: FotoBeaPolso.cambiata)) { _ in fotoOlo = FotoBeaPolso.immagine() }
    }

    /// 11.0 (6) (il signore: «Bea sul polso: fallo»): Bea in ologramma in piccolo, come gli altri ologrammi del polso, e accanto
    /// la prossima data (come il sottotitolo di Bea sull'iPhone). Senza foto scelta sull'iPhone: il busto di luce.
    private var rigaOlo: some View {
        let prossima = (dati?["date"] as? [[String: Any]])?.first
        let tra = (prossima?["tra_giorni"] as? NSNumber)?.intValue ?? 0
        return HStack(spacing: 8) {
            OlogrammaBeaProve(dati: BeaOlo(foto: fotoOlo), piccolo: true).frame(width: 46, height: 46)   // 11.0 (6): la prova scelta sull'iPhone
            VStack(alignment: .leading, spacing: 1) {
                Text("PROSSIMA").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                Text(prossima?["testo"] as? String ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                if prossima != nil {
                    Text(tra == 0 ? "oggi" : tra == 1 ? "domani" : "tra \(tra) giorni")
                        .font(.system(size: 10)).foregroundStyle(tra <= 7 ? calda : .secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func carica() async {
        let o = await VistaVitalsOrologio.chiama(["bea": true])
        errore = o == nil
        withAnimation { dati = o }
    }

    /// «Ti penso» dal polso: JARVIS scrive, il signore lo vede e lo manda da Messaggi dell'orologio.
    private func scrivi() async {
        scrive = true
        defer { scrive = false }
        let ultimi = UserDefaults.standard.stringArray(forKey: "pensieriBea") ?? []
        if let o = await VistaVitalsOrologio.chiama(["bea_pensiero": true, "evita": ultimi]), let t = o["testo"] as? String, !t.isEmpty {
            WKInterfaceDevice.current().play(.click)
            pensiero = t
        }
    }

    private func manda(_ testo: String) {
        let numero = (UserDefaults.standard.string(forKey: "numeroBea") ?? "").filter { "+0123456789".contains($0) }
        guard !numero.isEmpty else { jarvis.stato = "Colleghi il contatto di Bea sull'iPhone, Sir."; return }
        var mandati = UserDefaults.standard.stringArray(forKey: "pensieriBea") ?? []
        mandati.insert(testo, at: 0)
        UserDefaults.standard.set(Array(mandati.prefix(12)), forKey: "pensieriBea")
        var ammessi = CharacterSet.urlQueryAllowed
        ammessi.remove(charactersIn: "&=?+#")
        let corpo = testo.addingPercentEncoding(withAllowedCharacters: ammessi) ?? ""
        if let url = URL(string: "sms:\(numero)&body=\(corpo)") { WKApplication.shared().openSystemURL(url) }
        pensiero = nil
    }

    private func fatto(_ r: [String: Any]) async {
        guard let id = (r["id"] as? NSNumber)?.intValue else { return }
        WKInterfaceDevice.current().play(.success)
        SuoniOrologio.fatto()
        _ = await VistaVitalsOrologio.chiama(["bea_fatto": id])
        await carica()
    }
}

/// 11.0 (6) · Bea sul polso: l'ologramma di Bea fatto sull'iPhone dalla foto scelta là (la foto resta sull'iPhone e non viaggia).
/// Qui se ne tiene la copia piccola, fuori dal backup; si chiede all'iPhone quando si apre Bea (viaggia solo se è cambiata) e
/// arriva da sola quando sull'iPhone ne viene scelta un'altra.
nonisolated enum FotoBeaPolso {
    static let cambiata = Notification.Name("JarvisBeaPolso")
    private static let chiave = "beaPolsoVersione"
    private static var cartella: URL { URL.applicationSupportDirectory.appending(path: "JARVIS", directoryHint: .isDirectory) }
    private static var indirizzo: URL { cartella.appending(path: "bea-polso.jpg") }

    /// La versione che c'è sull'orologio («» = nessuna).
    static var versione: String { UserDefaults.standard.string(forKey: chiave) ?? "" }

    static func immagine() -> UIImage? { (try? Data(contentsOf: indirizzo)).flatMap { UIImage(data: $0) } }

    /// Un messaggio dell'iPhone su Bea (risposta, messaggio o consegna in coda): vero se era suo.
    @discardableResult
    static func ricevi(_ m: [String: Any]) -> Bool {
        guard m["bea"] as? String == "ologramma" else { return false }
        if let d = m["jpeg"] as? Data, let v = m["versione"] as? String {
            do {
                try FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
                try d.write(to: indirizzo, options: .atomic)
                var dove = indirizzo
                var valori = URLResourceValues()
                valori.isExcludedFromBackup = true
                try dove.setResourceValues(valori)
                UserDefaults.standard.set(v, forKey: chiave)
            } catch {
                return true
            }
        } else if m["nessuna"] as? Bool == true {
            try? FileManager.default.removeItem(at: indirizzo)
            UserDefaults.standard.removeObject(forKey: chiave)
        } else {
            return true                                       // l'orologio ha già questa
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: cambiata, object: nil) }
        return true
    }
}
