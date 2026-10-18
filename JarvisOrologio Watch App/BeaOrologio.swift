import SwiftUI
import WatchKit

/// Bea sul polso: le prossime date, le promesse da mantenere (scorrere per segnarle), cosa ama,
/// le lezioni di oggi, e due domande a JARVIS. Per aggiungere: basta dirlo a JARVIS.
struct VistaBeaOrologio: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @Environment(\.dismiss) private var chiudi
    @State private var dati: [String: Any]?
    @State private var errore = false
    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
    private let calda = Color(red: 1.0, green: 0.62, blue: 0.72)

    var body: some View {
        List {
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
                        ForEach(Array(promesse.enumerated()), id: \.offset) { _, r in
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
        .task { await carica() }
    }

    private func carica() async {
        let o = await VistaVitalsOrologio.chiama(["bea": true])
        errore = o == nil
        withAnimation { dati = o }
    }

    private func fatto(_ r: [String: Any]) async {
        guard let id = (r["id"] as? NSNumber)?.intValue else { return }
        WKInterfaceDevice.current().play(.success)
        _ = await VistaVitalsOrologio.chiama(["bea_fatto": id])
        await carica()
    }
}
