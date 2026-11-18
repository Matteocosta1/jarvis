import Foundation
import Combine
import SwiftUI
import WatchKit

// MARK: - 18 nov · 13.1 (2) · IL SÌ DAL POLSO (mockup FUORI approvato dal signore)
// Quando sull'iPhone un messaggio, una chiamata, un post o un passo del piano aspetta il sì, qui arriva la scheda: la domanda in
// ciano («LO MANDO?»), cosa («A Bea · «Arrivo alle nove.»»), Sì e No coi tasti dell'isola già approvati. Col telefono in mano
// arriva in silenzio; col telefono in tasca bussa due volte (scelta del signore). Un tocco su Sì vale come dirlo a voce: lo fa
// l'iPhone, e la risposta di JARVIS torna qui scritta (il telefono in tasca non parla). Col telefono bloccato iOS non lascia partire
// iMessage dall'iPhone: si apre Messaggi qui sull'orologio col testo già scritto, basta toccare Invia (scelta del signore).

@MainActor
final class SchedaSi: ObservableObject {
    static let condivisa = SchedaSi()

    nonisolated enum Tipo: Equatable, Sendable { case si, attesa, fatto, errore }
    nonisolated struct Scheda: Equatable, Sendable {
        var chiave: String
        var tipo: Tipo
        var titolo: String
        var riga: String
    }

    @Published private(set) var scheda: Scheda?
    private var chiusura: Task<Void, Never>?
    private var manoUltima = true

    /// Un messaggio dall'iPhone per la scheda. Vero se era suo.
    nonisolated static func ricevi(_ m: [String: Any]) -> Bool {
        if let d = m["si_scheda"] as? [String: Any] {
            let k = d["k"] as? String ?? "", domanda = d["d"] as? String ?? "", riga = d["r"] as? String ?? ""
            let quando = (d["t"] as? NSNumber)?.doubleValue ?? 0, mano = d["mano"] as? Bool ?? true
            Task { @MainActor in SchedaSi.condivisa.arriva(k, domanda: domanda, riga: riga, quando: quando, inMano: mano) }
            return true
        }
        if let k = m["si_via"] as? String {
            Task { @MainActor in SchedaSi.condivisa.via(k) }
            return true
        }
        if let t = m["si_fatto"] as? String {
            Task { @MainActor in SchedaSi.condivisa.fatto(t) }
            return true
        }
        if let d = m["si_messaggio"] as? [String: Any] {
            let numero = d["numero"] as? String ?? "", testo = d["testo"] as? String ?? ""
            Task { @MainActor in SchedaSi.condivisa.apriMessaggi(numero: numero, testo: testo) }
            return true
        }
        if let d = m["si_chiama"] as? [String: Any] {
            let numero = d["numero"] as? String ?? ""
            Task { @MainActor in SchedaSi.condivisa.chiama(numero) }
            return true
        }
        return false
    }

    private func arriva(_ k: String, domanda: String, riga: String, quando: Double, inMano: Bool) {
        guard !k.isEmpty, Date().timeIntervalSince1970 - quando < 180 else { return }   // arrivata in coda e ormai scaduta
        let nuova = scheda?.chiave != k || scheda?.tipo != .si
        chiusura?.cancel()
        scheda = Scheda(chiave: k, tipo: .si, titolo: domanda, riga: riga)
        // bussa solo col telefono in tasca: quando arriva, o quando il telefono ci va mentre la scheda è qui
        if !inMano && (nuova || manoUltima) { bussa() }
        manoUltima = inMano
    }

    private func via(_ k: String) {
        guard scheda?.chiave == k, scheda?.tipo == .si else { return }
        scheda = nil
    }

    /// La risposta di JARVIS a un sì dato da qui (o arrivata dopo, dal cervello).
    private func fatto(_ testo: String) {
        mostra(Scheda(chiave: "fatto", tipo: .fatto, titolo: "FATTO", riga: testo), per: 5)
        ApticaPolso.suona(.success)
    }

    /// Il telefono è in tasca: iMessage parte da qui, con Messaggi dell'orologio e il testo già scritto (l'ultimo tocco è suo).
    private func apriMessaggi(numero: String, testo: String) {
        let n = numero.filter { "+0123456789".contains($0) }
        guard !n.isEmpty else { return }
        var ammessi = CharacterSet.urlQueryAllowed
        ammessi.remove(charactersIn: "&=?+#")
        let corpo = testo.addingPercentEncoding(withAllowedCharacters: ammessi) ?? ""
        chiusura?.cancel()
        scheda = nil
        ApticaPolso.suona(.click)
        if let url = URL(string: "sms:\(n)&body=\(corpo)") { WKApplication.shared().openSystemURL(url) }
    }

    /// Il telefono è in tasca: la chiamata parte dall'orologio (iOS chiede conferma).
    private func chiama(_ numero: String) {
        let n = numero.filter { "+0123456789".contains($0) }
        guard !n.isEmpty else { return }
        chiusura?.cancel()
        scheda = nil
        ApticaPolso.suona(.click)
        if let url = URL(string: "tel:\(n)") { WKApplication.shared().openSystemURL(url) }
    }

    /// Sì o No sulla scheda: all'iPhone, che lo fa come detto a voce.
    func tocca(si: Bool) {
        guard let s = scheda, s.tipo == .si else { return }
        ApticaPolso.suona(.click)
        chiusura?.cancel()
        scheda = Scheda(chiave: s.chiave, tipo: .attesa, titolo: si ? "SÌ" : "NO", riga: s.riga)
        Task { @MainActor in
            let r = await PonteOrologio.condiviso.rispondiSi(si, chiave: s.chiave)
            if let e = r.errore {
                mostra(Scheda(chiave: "errore", tipo: .errore, titolo: "JARVIS", riga: e), per: 4)
                ApticaPolso.suona(.failure)
            } else if !r.testo.isEmpty {
                fatto(r.testo)
            } else if scheda?.tipo == .attesa {
                // risponde il cervello: la risposta arriva da sola («si_fatto»); se non arriva, la scheda si chiude fra un minuto
                mostra(Scheda(chiave: s.chiave, tipo: .attesa, titolo: si ? "SÌ" : "NO", riga: "Ci penso io, Sir."), per: 60)
            }
        }
    }

    /// Tocco fuori dai tasti su una scheda finita: si chiude subito.
    func chiudi() {
        guard let s = scheda, s.tipo != .si else { return }
        chiusura?.cancel()
        scheda = nil
    }

    private func mostra(_ s: Scheda, per secondi: Double) {
        chiusura?.cancel()
        scheda = s
        chiusura = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(secondi))
            guard !Task.isCancelled, self?.scheda?.chiave == s.chiave, self?.scheda?.tipo == s.tipo else { return }
            self?.scheda = nil
        }
    }

    /// Due colpi al polso: qualcosa aspetta il sì.
    private func bussa() {
        ApticaPolso.suona(.notification)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            ApticaPolso.suona(.notification)
        }
    }
}

/// La scheda sul polso (mockup FUORI: fondo nero, la domanda in ciano, la riga bianca, Sì e No coi colori dell'isola VOCE).
struct VistaSchedaSi: View {
    let scheda: SchedaSi.Scheda
    private let ciano = Color(red: 0.31, green: 0.89, blue: 1.0)
    private let rosso = Color(red: 1, green: 138 / 255, blue: 138 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(scheda.titolo)
                .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.6)
                .foregroundStyle(ciano)
            Text(scheda.riga)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
            if scheda.tipo == .si {
                HStack(spacing: 6) {
                    tasto("Sì", colore: ciano, sfondo: ciano.opacity(0.16)) { SchedaSi.condivisa.tocca(si: true) }
                    tasto("No", colore: rosso, sfondo: Color(red: 1, green: 90 / 255, blue: 90 / 255).opacity(0.18)) { SchedaSi.condivisa.tocca(si: false) }
                }
                .padding(.top, 4)
            } else if scheda.tipo == .attesa {
                ProgressView().tint(ciano).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 18)
        .background(Color.black.opacity(0.94))
        .contentShape(Rectangle())
        .onTapGesture { SchedaSi.condivisa.chiudi() }
        .ignoresSafeArea()
    }

    private func tasto(_ titolo: String, colore: Color, sfondo: Color, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Text(titolo)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(colore)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(sfondo))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titolo)
    }
}
