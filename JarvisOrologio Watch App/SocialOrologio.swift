import SwiftUI
import WatchKit

// MARK: - MARK X · SOCIAL al polso: @kingrusto in un colpo d'occhio
// Follower, la settimana, i messaggi e i commenti da rispondere, il prossimo post in programma. I dati veri arrivano dal cervello
// (funzione «social», senza le bozze delle risposte: al polso non si scrivono). Rispondere e pubblicare: dall'iPhone.

struct VistaSocialOrologio: View {
    /// Detta a voce: "POSTA", "REPORT", "CALENDARIO" (quella parte va in cima).
    var scheda: String? = nil
    @State private var dati: [String: Any]?
    @State private var errore: String?
    @State private var caricato = false
    private let ciano = TintaOrologio.ciano
    private let tenue = Color(red: 0.30, green: 0.40, blue: 0.44)
    private let testo = Color(red: 0.812, green: 0.886, blue: 0.910)

    var body: some View {
        SchermoPolso(titolo: "SOCIAL · @KINGRUSTO", pronto: caricato) {
            if let errore {
                Text(errore).font(.system(size: 10)).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if dati != nil {
                ForEach(ordine, id: \.self) { parte in
                    switch parte {
                    case "REPORT": report
                    case "POSTA": posta
                    default: calendario
                    }
                }
                Text("Rispondere e pubblicare: dall'iPhone, Sir.").font(.system(size: 9)).foregroundStyle(tenue).multilineTextAlignment(.center)
            }
        }
        .task { await carica() }
    }

    private var ordine: [String] {
        let tutte = ["REPORT", "POSTA", "CALENDARIO"]
        guard let s = scheda, tutte.contains(s) else { return tutte }
        return [s] + tutte.filter { $0 != s }
    }

    // MARK: le tre parti

    private var report: some View {
        let profilo = dati?["profilo"] as? [String: Any]
        let numeri = (dati?["report"] as? [String: Any])?["numeri"] as? [[String]] ?? []
        return VStack(spacing: 4) {
            Text(profilo?["followerTesto"] as? String ?? "—").font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            Text("FOLLOWER" + (numeri.first.map { $0.count > 2 ? " · " + $0[2].uppercased() : "" } ?? ""))
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(ciano).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(Array(numeri.dropFirst().prefix(2).enumerated()), id: \.offset) { _, n in
                    VStack(spacing: 1) {
                        Text(n.count > 1 ? n[1] : "—").font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(testo)
                        Text(n.first ?? "").font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundStyle(tenue)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var posta: some View {
        let lista = (dati?["posta"] as? [[String: Any]] ?? []).filter { ($0["fatto"] as? Bool) != true && ($0["scaduto"] as? Bool) != true }
        return VStack(alignment: .leading, spacing: 3) {
            Text(lista.isEmpty ? "POSTA · TUTTO RISPOSTO" : "POSTA · \(lista.count) DA RISPONDERE")
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(ciano)
            ForEach(Array(lista.prefix(3).enumerated()), id: \.offset) { _, m in
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(m["chi"] as? String ?? "") · \((m["tipo"] as? String) == "dm" ? "DM" : "COMMENTO")")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(m["testo"] as? String ?? "").font(.system(size: 10)).foregroundStyle(testo).lineLimit(2)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ciano.opacity(0.07))
                .overlay(alignment: .leading) { Rectangle().fill(ciano).frame(width: 2) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendario: some View {
        let coda = dati?["coda"] as? [[String: Any]] ?? []
        return VStack(alignment: .leading, spacing: 3) {
            Text("CALENDARIO").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(ciano)
            if let p = coda.first {
                Text("\(p["quando"] as? String ?? "") · \(p["tipo"] as? String ?? "")").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                Text(p["titolo"] as? String ?? "").font(.system(size: 10)).foregroundStyle(testo).lineLimit(2)
            } else {
                Text("Niente in programma.").font(.system(size: 10)).foregroundStyle(testo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: il cervello

    private func carica() async {
        defer { caricato = true }
        let base = ImpostazioniOrologio.indirizzo
        let indirizzo = base.hasSuffix("/jarvis") ? String(base.dropLast(7)) + "/social" : base.replacingOccurrences(of: "/jarvis", with: "/social")
        let token = PortachiaviOrologio.leggi()
        guard !token.isEmpty, let url = URL(string: indirizzo) else { errore = "Manca la parola d'ordine, Sir: apra JARVIS sull'iPhone."; return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 40
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["azione": "stato", "leggero": true] as [String: Any])
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { errore = "Instagram non risponde, Sir."; return }
        if let e = o["errore"] as? String { errore = "Instagram: \(e)."; return }
        dati = o
    }
}
