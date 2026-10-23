#if os(iOS)
import SwiftUI
import UIKit

/// Email › PRIORITÀ (build 22), in testa alla posta come nel mockup: le mail che contano con il riassunto e la risposta
/// proposta da JARVIS (Invia la spedisce, solo dopo il tocco; Cambia la rende modificabile), poi ALTRE e A VOCE.
/// Dal cervello: { "posta_priorita": true } e { "posta_rispondi": { id, testo } }.
struct PannelloPriorita: View {
    let posta: PostaPriorita?
    let errore: String?
    private let tinta = Color.ciano

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Pannello(titolo: "PRIORITÀ", tinta: tinta) {
                if let posta {
                    if posta.importanti.isEmpty {
                        Text("Niente di importante, Sir.").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                    }
                    ForEach(Array(posta.importanti.enumerated()), id: \.element.id) { k, m in
                        MailPriorita(mail: m, prima: k == 0)
                    }
                } else if let errore {
                    Text(errore).font(.system(size: 13)).foregroundStyle(.orange)
                } else {
                    Text("JARVIS legge la posta…").font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                }
            }
            if let posta {
                Pannello(titolo: "ALTRE", tinta: tinta) {
                    RigaHUD("Newsletter e notifiche", posta.altreNota.isEmpty ? "\(posta.altreConteggio)" : "\(posta.altreConteggio) · \(posta.altreNota)")
                }
            }
            PannelloAVoce(frasi: ["«Jarvis, rapporto posta»", "«Jarvis, cosa c'è di importante?»", "«Jarvis, rispondi tu al commercialista»"])
        }
    }

    /// La posta che conta, dal cervello.
    static func chiedi() async -> (PostaPriorita?, String?) {
        // la prima lettura dopo posta nuova può essere lunga (intestazioni, testi, riassunti): il cervello la finisce e la tiene pronta
        guard let o = await VistaVitals.chiama(["posta_priorita": true], attesa: 60) else { return (nil, "Sto ancora leggendo la posta, Sir: riapra tra un minuto.") }
        if let e = o["errore"] as? String { return (nil, e) }
        guard let p = PostaPriorita(o) else { return (nil, "La posta non è arrivata come mi aspettavo, Sir.") }
        return (p, nil)
    }
}

/// Una mail importante: mittente e ora, il riassunto, la risposta proposta con Invia e Cambia.
private struct MailPriorita: View {
    let mail: MailImportante
    let prima: Bool
    private enum Invio: Equatable { case pronta, invio, inviata, errore(String) }
    @State private var bozza: String
    @State private var cambia = false
    @State private var stato: Invio = .pronta
    @FocusState private var fuoco: Bool
    private let tinta = Color.ciano

    init(mail: MailImportante, prima: Bool) {
        self.mail = mail
        self.prima = prima
        _bozza = State(initialValue: PostaPriorita.senzaVirgolette(mail.risposta ?? ""))   // la risposta proposta, senza «»
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !prima { Rectangle().fill(ColoriHUD.filo).frame(height: 1).padding(.bottom, 4) }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(mail.mittente).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                Text(mail.quando).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(Color.tenue)
            }
            Text(mail.riassunto).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo).fixedSize(horizontal: false, vertical: true)
            if let r = mail.risposta {
                Group {
                    if cambia && mail.serveRisposta {
                        TextField("La risposta", text: $bozza, axis: .vertical)
                            .focused($fuoco)
                            .foregroundStyle(ColoriHUD.testo)
                    } else {
                        Text(mail.serveRisposta ? "«\(bozza)»" : r).foregroundStyle(ColoriHUD.testo)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 13))
                .padding(.vertical, 4)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tinta.opacity(0.05))
                .overlay(alignment: .leading) { Rectangle().fill(tinta).frame(width: 2) }
                if mail.serveRisposta {
                    HStack(spacing: 8) {
                        TastoComando(testo: etichettaInvia, attivo: stato == .pronta || isErrore) { Task { await invia() } }
                        TastoComando(testo: "Cambia", attivo: stato != .inviata && stato != .invio) {
                            Suoni.tocco()
                            cambia = true
                            fuoco = true
                        }
                    }
                    if case .errore(let e) = stato {
                        Text(e).font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var isErrore: Bool { if case .errore = stato { return true } else { return false } }

    private var etichettaInvia: String {
        switch stato {
        case .invio: return "…"
        case .inviata: return "Inviata"
        default: return "Invia"
        }
    }

    /// Spedisce solo adesso, dopo il tocco del signore.
    private func invia() async {
        let testo = bozza.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testo.isEmpty, stato != .invio, stato != .inviata else { return }
        stato = .invio
        fuoco = false
        // il cervello apre la casella, spedisce, segna la mail come risposta e mette la copia in Inviata: può volerci un po'
        let o = await VistaVitals.chiama(mail.corpoRisposta(testo), attesa: 45)
        if (o?["ok"] as? Bool) == true {
            stato = .inviata
            cambia = false
            Suoni.fatto()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            // nessuna risposta in tempo: la mail potrebbe essere partita lo stesso. Riprovare è sicuro: il cervello non la rimanda
            stato = .errore(o == nil ? "Non so se è partita, Sir: controlli in Inviata. Se riprova, JARVIS non la manda due volte."
                                     : (o?["errore"] as? String) ?? "Non sono riuscito a inviarla, Sir. Riprovi.")
        }
    }
}
#endif
