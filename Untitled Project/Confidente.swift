#if os(iOS)
import SwiftUI

/// Il confidente: il signore incolla una conversazione (WhatsApp, messaggi) o racconta cosa è successo,
/// e JARVIS gli dice cosa ne pensa, schietto in entrambe le direzioni. Oppure glielo racconta a voce.
/// Quello che si dice qui non finisce nella memoria di JARVIS.
struct VistaConfidente: View {
    /// Manda il testo a JARVIS (chiude la pagina).
    let invia: (String) -> Void
    /// Apre l'ascolto a voce (chiude la pagina).
    let aVoce: () -> Void
    @State private var testo = ""
    @State private var stato: SaluteOggi?          // corpo e mente insieme: lo stato fisico di oggi accompagna ogni domanda
    @State private var domanda = ""
    @FocusState private var scrivendo: Bool

    @Environment(\.dismiss) private var chiudi

    /// La riga che JARVIS riceve insieme alla conversazione, così il confidente sa come sta il corpo.
    private var rigaStato: String {
        guard let s = stato else { return "" }
        var parti: [String] = []
        if let x = s.sonno { parti.append("sonno stanotte \(x)") }
        if let p = s.pisolini { parti.append("pisolino oggi \(p)\(s.riposoTotale.map { ", riposo totale \($0)" } ?? "")") }
        if let b = s.battito { parti.append("battito a riposo \(b)\(s.battitoMedia.map { " (media 7 giorni \($0))" } ?? "")") }
        if let p = s.passi { parti.append("passi oggi \(p)") }
        if !s.allenamenti.isEmpty { parti.append("allenamenti: \(s.allenamenti.joined(separator: "; "))") }
        return parti.isEmpty ? "" : "\n[Stato fisico di oggi: \(parti.joined(separator: ", "))]"
    }

    /// Una striscia discreta in alto: il corpo, oggi. JARVIS lo terrà presente nella risposta.
    @ViewBuilder private var statoFisico: some View {
        if let s = stato, s.sonno != nil || s.battito != nil {
            HStack(spacing: 14) {
                if let x = s.sonno { Label(x, systemImage: "bed.double.fill") }
                if let r = s.riposoTotale, s.pisolini != nil { Label("\(r) tot.", systemImage: "moon.zzz.fill") }
                if let b = s.battito {
                    let alto = (s.battitoMedia.map { b > $0 + 4 }) ?? false
                    Label("\(b) bpm", systemImage: "heart.fill").foregroundStyle(alto ? Color.orange : Color(red: 0.81, green: 0.91, blue: 0.95))
                }
                if let p = s.passi { Label(p.formatted(), systemImage: "figure.walk") }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciano.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.3), lineWidth: 0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("JARVIS terrà conto anche di come sta il suo corpo oggi.")
                .font(.footnote).foregroundStyle(Color.tenue)
        }
    }

    var body: some View {
        NavigationStack {
        ZStack {
                Color.fondo.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Mi racconti, Sir. Le dico quello che penso davvero, anche quando non le darò ragione. Vedo solo la sua metà della storia: il mio è un parere, non una sentenza.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))

                        statoFisico

                        Button { Suoni.tocco(); aVoce() } label: {
                            Label("Preferisco raccontarlo a voce", systemImage: "waveform")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .foregroundStyle(Color.fondo).background(Color.ciano2)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(StileStark())

                        Text("OPPURE INCOLLI LA CONVERSAZIONE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                            .foregroundStyle(Color.ciano)

                        ZStack(alignment: .topLeading) {
                            if testo.isEmpty {
                                Text("Su WhatsApp: tenga premuto un messaggio › Inoltra o Copia, poi incolli qui. Oppure scriva cosa è successo.")
                                    .font(.system(size: 14)).foregroundStyle(Color.tenue)
                                    .padding(.horizontal, 5).padding(.vertical, 8)
                            }
                            TextEditor(text: $testo)
                                .focused($scrivendo)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .frame(minHeight: 200)
                        }
                        .padding(8)
                        .background(Color.ciano.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        TextField("Cosa vuole sapere? (es. ho esagerato io?)", text: $domanda, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(Color.ciano.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            Suoni.tocco()
                            let d = domanda.trimmingCharacters(in: .whitespacesAndNewlines)
                            invia("Modalità confidente. \(d.isEmpty ? "Cosa ne pensi? Dimmi la verità." : d)\(rigaStato)\n\n\(testo.trimmingCharacters(in: .whitespacesAndNewlines))")
                        } label: {
                            Label("Chieda a JARVIS", systemImage: "person.2.wave.2")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .foregroundStyle(Color.ciano)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.7), lineWidth: 1))
                        }
                        .buttonStyle(StileStark())
                        .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)

                        Text("Resta tra voi: JARVIS non lo salva nella memoria, a meno che non glielo chieda lei.")
                            .font(.footnote).foregroundStyle(Color.tenue)
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .task { stato = await SaluteOggi.leggi() }
            .navigationTitle("Confidente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() }.tint(Color.ciano) }
            }
        }
        .preferredColorScheme(.dark)
        .aperturaHUD("Confidente")
    }
}
#endif
