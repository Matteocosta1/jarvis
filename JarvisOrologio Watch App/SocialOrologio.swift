import SwiftUI
import WatchKit

// MARK: - MARK X · SOCIAL al polso (come il mockup: «Instagram al polso: il messaggio nuovo e la risposta di JARVIS, parte con un tocco»)
// Il primo commento o messaggio da rispondere, con la risposta preparata da JARVIS; INVIA la manda (la stessa funzione «social»
// dell'iPhone, col sì del signore: il tocco). Niente da rispondere: «0 · Nessun messaggio da rispondere».

struct VistaSocialOrologio: View {
    /// Detta a voce ("POSTA", "REPORT"…): al polso c'è solo la posta, come nel mockup.
    var scheda: String? = nil
    @State private var messaggio: [String: Any]?
    @State private var errore: String?
    @State private var caricato = false
    @State private var inviata = false
    @State private var invio = false
    private let ciano = TintaOrologio.ciano
    private let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)
    private let testo = Color(red: 0.812, green: 0.886, blue: 0.910)

    var body: some View {
        SchermoPolso(titolo: "SOCIAL · @KINGRUSTO", pronto: caricato) {
            if let errore {
                Text(errore).font(.system(size: 10)).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if let m = messaggio {
                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(m["chi"] as? String ?? "")").font(.system(size: 10, weight: .bold)).foregroundStyle(ciano)
                    Text(m["testo"] as? String ?? "").font(.system(size: 11)).foregroundStyle(.white)
                    Text("JARVIS").font(.system(size: 10, weight: .bold)).foregroundStyle(ciano).padding(.top, 2)
                    Text("«\(m["bozza"] as? String ?? "")»").font(.system(size: 11)).foregroundStyle(testo)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ciano.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Button { Task { await invia(m) } } label: {
                    HStack {
                        Text(inviata ? "INVIATA" : invio ? "INVIO…" : "INVIA").font(.system(size: 12, weight: .bold, design: .monospaced))
                        Spacer()
                        Text(inviata ? "✓" : "›").font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .foregroundStyle(inviata ? Color.black : ciano)
                    .background(RoundedRectangle(cornerRadius: 10).fill(inviata ? ciano : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ciano.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(inviata || invio || (m["bozza"] as? String ?? "").isEmpty)
                Text("\((m["tipo"] as? String) == "dm" ? "Messaggio" : "Commento") · Instagram")
                    .font(.system(size: 9)).foregroundStyle(tenue)
            } else {
                Text("0").font(.system(size: 30, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                Text("Nessun messaggio da rispondere").font(.system(size: 9)).foregroundStyle(tenue).multilineTextAlignment(.center)
            }
        }
        .task { await carica() }
    }

    // MARK: il cervello (funzione «social», come l'iPhone)

    private static var indirizzo: URL? {
        let base = ImpostazioniOrologio.indirizzo
        return URL(string: base.hasSuffix("/jarvis") ? String(base.dropLast(7)) + "/social" : base.replacingOccurrences(of: "/jarvis", with: "/social"))
    }

    private static func chiama(_ corpo: [String: Any], attesa: TimeInterval) async -> [String: Any]? {
        let token = PortachiaviOrologio.leggi()
        guard !token.isEmpty, let url = indirizzo else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = attesa
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        guard let (d, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private func carica() async {
        defer { caricato = true }
        guard !PortachiaviOrologio.leggi().isEmpty else { errore = "Manca la parola d'ordine, Sir: apra JARVIS sull'iPhone."; return }
        guard let o = await Self.chiama(["azione": "stato"], attesa: 45) else { errore = "Instagram non risponde, Sir."; return }
        if let e = o["errore"] as? String { errore = "Instagram: \(e)."; return }
        let posta = o["posta"] as? [[String: Any]] ?? []
        messaggio = posta.first { ($0["fatto"] as? Bool) != true && ($0["scaduto"] as? Bool) != true }
    }

    private func invia(_ m: [String: Any]) async {
        guard !inviata, !invio else { return }
        invio = true
        WKInterfaceDevice.current().play(.click)
        let corpo: [String: Any] = ["azione": "rispondi", "tipo": m["tipo"] as? String ?? "", "id": m["id"] as? String ?? "",
                                    "a": m["a"] as? String ?? "", "testo": m["bozza"] as? String ?? ""]
        let r = await Self.chiama(corpo, attesa: 30)
        invio = false
        if r?["ok"] as? Bool == true {
            inviata = true
            WKInterfaceDevice.current().play(.success)
        } else {
            errore = "Non è partita, Sir: " + (r?["errore"] as? String ?? "Instagram non risponde") + "."
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
