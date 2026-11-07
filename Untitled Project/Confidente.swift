#if os(iOS)
import SwiftUI
import UIKit

/// Il confidente: il signore incolla una conversazione (WhatsApp, messaggi) o racconta cosa è successo,
/// e JARVIS gli dice cosa ne pensa, schietto in entrambe le direzioni. Oppure glielo racconta a voce.
/// Quello che si dice qui non finisce nella memoria di JARVIS.
struct VistaConfidente: View {
    /// Manda il testo a JARVIS (chiude la pagina); il secondo testo va al cervello ma non si vede in chat (lo stato fisico).
    let invia: (_ testo: String, _ nascosto: String) -> Void
    /// Apre l'ascolto a voce (chiude la pagina).
    let aVoce: () -> Void
    @State private var testo = ""
    @State private var stato: SaluteOggi?          // corpo e mente insieme: lo stato fisico di oggi accompagna ogni domanda
    @State private var domanda = ""
    @State private var giroBozza = 0
    @FocusState private var scrivendo: Bool

    @Environment(\.chiudiOVia) private var chiudi

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
                SfondoSezione()   // 7 nov: lo sfondo di tutte le sezioni
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 26 ott notte: la testata delle altre sezioni (icona con l'anello che gira), niente titolo di iOS
                        TestataScheda(titolo: "Confidente", sottotitolo: "mi racconti", icona: "person.2.wave.2", tinta: Color.ciano)
                        Text("Mi racconti, Sir. Le dico quello che penso davvero, anche quando non le darò ragione. Vedo solo la sua metà della storia: il mio è un parere, non una sentenza.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))

                        // v267: la BILANCIA, sotto le parole di JARVIS: la conversazione sui piatti, il cuore di oggi nel perno
                        OlogrammaConfidente(dati: ConfidenteOlo(testo: testo, battito: stato?.battito)).corniceOlo(Color.ciano)

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
                        .overlay(AngoliOlo(tinta: Color.ciano).padding(-1).allowsHitTesting(false))   // 27 ott: la cornice olografica

                        // 4 nov (il signore): la bozza resta riaprendo; «Cancella», come in Messaggi, la svuota
                        if !testo.isEmpty || !domanda.isEmpty {
                            HStack {
                                Spacer()
                                Button { Suoni.tocco(); svuota() } label: { Text("Cancella").font(.system(size: 12)) }.tint(Color.ciano)
                            }
                            .padding(.top, -8)
                        }

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
                            let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
                            svuota()                                  // mandata: la bozza non serve più
                            invia("Modalità confidente. \(d.isEmpty ? "Cosa ne pensi? Dimmi la verità." : d)\n\n\(t)", rigaStato)
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
                .modifier(ConBarraChiudi(tinta: Color.ciano) { chiudi() })   // 5 nov: niente più barra grigia scorrendo
            }
            .task { stato = await SaluteOggi.leggi() }
            .tastiAVoce { a in
                switch a {
                case .confidenteIncolla:
                    if let c = UIPasteboard.general.string, !c.isEmpty { testo = testo.isEmpty ? c : testo + "\n" + c; Suoni.tocco() }
                case .confidenteAVoce: Suoni.tocco(); aVoce()
                default: break
                }
            }
            .onAppear {
                // con la conversazione incollata, quello che dice a voce è la sua domanda («Jarvis, ho esagerato io?»)
                ConfidenteAperto.domanda = { frase in
                    var t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
                    // niente incollato, ma parla di «questo messaggio», «questa chat»…: prende quello che ha copiato
                    let basso = frase.lowercased()
                    if t.isEmpty, ["messaggio", "questo", "questa", "conversazione", "chat", "whatsapp", "ha scritto", "mi ha detto", "copiato"].contains(where: { basso.contains($0) }),
                       let copiato = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !copiato.isEmpty {
                        testo = copiato
                        t = copiato
                    }
                    guard !t.isEmpty else { return false }
                    let d = frase.trimmingCharacters(in: .whitespacesAndNewlines)
                    svuota()                                      // mandata: la bozza non serve più
                    invia("Modalità confidente. \(d.isEmpty ? "Cosa ne pensi? Dimmi la verità." : d)\n\n\(t)", rigaStato)
                    return true
                }
                // riaprendo: la conversazione incollata e la domanda di prima
                if testo.isEmpty, domanda.isEmpty, let b = Bozze.leggi("confidente", come: Bozze.Confidente.self) {
                    testo = b.testo
                    domanda = b.domanda
                }
            }
            .onDisappear { ConfidenteAperto.domanda = nil }
            .onChange(of: testo) { salvaBozza() }
            .onChange(of: domanda) { salvaBozza() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .aperturaHUD("Confidente")
    }

    /// La bozza si scrive un attimo dopo l'ultimo tasto (sul telefono, protetta); vuota, sparisce.
    private func salvaBozza() {
        giroBozza += 1
        let mio = giroBozza
        guard !testo.isEmpty || !domanda.isEmpty else { Bozze.cancella("confidente"); return }
        let b = Bozze.Confidente(testo: testo, domanda: domanda)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if mio == giroBozza { Bozze.scrivi("confidente", b) }
        }
    }

    /// «Cancella», o mandata a JARVIS: via la conversazione, la domanda e la bozza.
    private func svuota() {
        giroBozza += 1
        testo = ""
        domanda = ""
        Bozze.cancella("confidente")
    }
}
#endif
