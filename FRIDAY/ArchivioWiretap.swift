#if os(iOS)
import Foundation
import SwiftUI

/// 11 nov (approvato il 10 nov: «perfetto»): l'ARCHIVIO dentro il Wiretap. Le registrazioni salvate (nell'Archivio centrale,
/// cartella wiretap), dalla più recente. Tocco: si apre la trascrizione; CONDIVIDI e ELIMINA › CONFERMA come nelle altre sezioni.
/// Si vede quando il Wiretap è fermo e vuoto (durante una registrazione conta solo quella).
struct ArchivioWiretap: View {
    @State private var file: [Voce]?
    @State private var errore: String?
    @State private var aperto: String?                   // il percorso della registrazione aperta
    @State private var testi: [String: String] = [:]
    @State private var daEliminare: String?
    @State private var giro = 0

    var body: some View {
        Pannello(titolo: "ARCHIVIO", tinta: .ciano) {
            if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            } else if let file {
                if file.isEmpty {
                    Text("Nessuna registrazione salvata. Chiudendo il Wiretap con del testo, JARVIS chiede se salvarla qui.")
                        .font(.system(size: 13)).foregroundStyle(Color.tenue).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(file.enumerated()), id: \.offset) { i, f in
                                riga(f)
                                if i < file.count - 1 { Divider().overlay(Color.ciano.opacity(0.12)) }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            } else {
                Text("Apro l'archivio…").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
            }
        }
        .task { await carica() }
    }

    @ViewBuilder private func riga(_ f: Voce) -> some View {
        let percorso = f.s("percorso")
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Suoni.tocco()
                    withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) { aperto = aperto == percorso ? nil : percorso }
                    if testi[percorso] == nil { Task { await leggi(percorso) } }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.s("nome").replacingOccurrences(of: ".txt", with: "")).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo).lineLimit(1)
                        // un testo breve pesa meno di 1 KB: si scrive 1, come il mockup
                        Text("\(f.s("quando")) · \(max(1, f.n("kb"))) KB").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StileStark())
                let sicuro = daEliminare == percorso
                let rosso = Color(red: 1, green: 107 / 255, blue: 107 / 255)                                    // #ff6b6b
                Button { Task { await elimina(percorso) } } label: {
                    Text(sicuro ? "CONFERMA" : "ELIMINA")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                        .foregroundStyle(sicuro ? rosso : Color.ciano)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(sicuro ? rosso.opacity(0.6) : Color.ciano.opacity(0.3), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(StileStark())
                .accessibilityLabel(sicuro ? "Conferma: elimina la registrazione" : "Elimina la registrazione")
            }
            if aperto == percorso {
                if let t = testi[percorso] {
                    Text(t).font(.system(size: 13)).foregroundStyle(Color(red: 0.85, green: 0.93, blue: 0.97))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    ShareLink(item: t) {
                        Text("CONDIVIDI").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                            .frame(maxWidth: .infinity).padding(.vertical, 8).foregroundStyle(Color.ciano)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(0.3), lineWidth: 1))
                    }
                } else {
                    Text("Apro la trascrizione…").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
                }
            }
        }
        .padding(.vertical, 11)
    }

    private func carica() async {
        guard let o = await VistaVitals.chiama(["archivio": true, "cartella": "wiretap"]) else { errore = "Non raggiungo l'archivio, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        file = Voce(o).lista("file")
    }

    private func leggi(_ percorso: String) async {
        guard let o = await VistaVitals.chiama(["archivio_link": percorso]), let u = o["url"] as? String, let url = URL(string: u),
              let (d, _) = try? await URLSession.shared.data(from: url) else { testi[percorso] = "Non riesco ad aprirla, Sir."; return }
        testi[percorso] = String(data: d, encoding: .utf8) ?? "Non riesco a leggerla, Sir."
    }

    /// Il primo tocco chiede CONFERMA per 3 secondi, il secondo elimina dall'Archivio.
    private func elimina(_ percorso: String) async {
        guard daEliminare == percorso else {
            Suoni.tocco()
            daEliminare = percorso
            giro += 1
            let mio = giro
            Task { try? await Task.sleep(for: .seconds(3)); if giro == mio { daEliminare = nil } }
            return
        }
        Suoni.pronto()
        daEliminare = nil
        _ = await VistaVitals.chiama(["archivio_elimina": percorso])
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) {
            file?.removeAll { $0.s("percorso") == percorso }
            if aperto == percorso { aperto = nil }
        }
    }
}
#endif
