#if os(iOS)
import Foundation
import SwiftUI
import Combine
import Charts
import MusicKit
import UIKit
import WebKit          // 8 nov: il lettore di YouTube del player passa il suo WKWebView ad AscoltoShazam

// MARK: - FOTO: la galleria, con la ricerca per contenuto e periodo

struct VistaFotoScheda: View {
    let chiedi: (String) -> Void
    private let tinta = Tinte.foto

    enum Periodo: String, CaseIterable, Identifiable {
        case oggi = "Oggi", ieri = "Ieri", settimana = "7 giorni", mese = "30 giorni", tutte = "Tutte"
        var id: String { rawValue }
        var intervallo: (Date?, Date?) {
            let cal = Calendar.current
            let oggi = cal.startOfDay(for: Date())
            switch self {
            case .oggi: return (oggi, nil)
            case .ieri: return (oggi.addingTimeInterval(-86_400), oggi)
            case .settimana: return (oggi.addingTimeInterval(-7 * 86_400), nil)
            case .mese: return (oggi.addingTimeInterval(-30 * 86_400), nil)
            case .tutte: return (nil, nil)
            }
        }
    }

    // 4 nov: le parole le capisce DizionarioFoto (tutte le 1.303 categorie di Apple in italiano, con i plurali, parole intere;
    // selfie, screenshot, preferite e ritratti sono gli album di Apple). Prima erano una trentina e alcune non esistevano.

    @State private var periodo: Periodo = .oggi
    @State private var cerca = ""
    @FocusState private var cercaAttiva: Bool            // 12 nov (CampoInAlto): la ricerca ha la tastiera
    @State private var foto: [Immagine]?
    @State private var nota: String?
    @State private var aperta: Int?
    @State private var limitato = false
    @ObservedObject private var analisi = AvanzamentoFoto.condiviso       // il conto dell'analisi della galleria
    // 11.0 (3), come il mockup approvato: il pannello dell'analisi in ologramma, le parole capite, i quadratini che si materializzano
    @State private var pannello = false
    @State private var completa = false
    @State private var capite: [String] = []
    @State private var ritardi: [String: Double] = [:]
    @State private var quandoRisultati = Date.distantPast
    @State private var apertaIl = Date()
    @Environment(\.accessibilityReduceMotion) private var riduci
    @Environment(\.sezioneDietro) private var dietro    // dietro (MARK XI) la rilettura delle foto si ferma

    var body: some View {
        CorniceScheda(titolo: "Foto", sottotitolo: foto.map { "\($0.count) foto · \(periodo.rawValue.lowercased())" } ?? "sfoglio la galleria", icona: "photo.on.rectangle", tinta: tinta, pronto: foto != nil) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Periodo.allCases) { p in
                        Button { Suoni.tocco(); periodo = p } label: {
                            Text(p.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(periodo == p ? Color.fondo : tinta)
                                .background(periodo == p ? tinta : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(tinta.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(tinta)
                TextField("Cosa cerca? cane, mare, concerto, vinile…", text: $cerca).foregroundStyle(.white).submitLabel(.search)
                    .campoRegia("ricerca", testo: $cerca, cerca: true)   // 12.0 (12) · B2
                    .focused($cercaAttiva)
                if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
            }
            .padding(12)
            .background(tinta.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .id("fotoCerca")                                     // 12 nov (CampoInAlto): con la tastiera su, in cima con i risultati sotto
            .onChange(of: cercaAttiva) { _, su in if su { CampoInAlto.porta("fotoCerca") } }

            // 11.0 (3): le cose capite, in fila col «+» (devono esserci tutte nella foto)
            if !capite.isEmpty {
                ParoleCapite(parole: capite, tinta: tinta).padding(.top, -6)
            }
            // l'analisi di tutta la galleria (una volta sola, poi solo le foto nuove), in ologramma. 7 nov sera (il signore, scelta A):
            // SEMPRE visibile: mentre va avanti il conto; finita «ANALISI COMPLETA · N FOTO» e l'ologramma che rilegge le ultime foto
            if pannello {
                PannelloAnalisi(analisi: analisi, tinta: tinta, completa: completa)
                    .transition(.opacity)
            }
            // 4 nov: con l'accesso limitato JARVIS vede solo le foto scelte: si dice, e un tocco apre le Impostazioni
            if limitato {
                Button {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                } label: {
                    Text("Accesso limitato: vedo solo le foto che ha scelto lei. Per cercare in tutta la galleria: Impostazioni › App › Jarvis › Foto › Accesso completo.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }

            if let foto {
                if foto.isEmpty || nota != nil {
                    Text(nota ?? "Nessuna foto in questo periodo.").font(.footnote).foregroundStyle(Color.tenue)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 4)], spacing: 4) {
                    ForEach(Array(foto.enumerated()), id: \.element.id) { k, f in
                        Button { aperta = k } label: {
                            Miniatura(immagine: f, lato: 300)
                                .frame(minHeight: 104, maxHeight: 104)
                                .clipped()
                                .modifier(Materializza(ritardo: ritardi[f.id], quando: quandoRisultati))   // le foto nuove: col laser
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                // la foto riempita sborda dal quadratino: senza questa riga il tocco prendeva anche la parte tagliata
                                // (che copriva il campo «Cerca» sopra la prima riga)
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !foto.isEmpty {
                    TastoJarvis(testo: "Racconta la giornata in foto", icona: "waveform", tinta: tinta) {
                        chiedi("Guarda le mie foto di \(periodo == .tutte ? "recente" : periodo.rawValue.lowercased())\(cerca.isEmpty ? "" : " con \(cerca)") e raccontamele in breve.")
                    }
                }
            } else {
                AttesaAnello(tinta: tinta).frame(maxWidth: .infinity).padding(.top, 40)   // 8 nov: l'anello del mockup (.attesa-l)
            }
        }
        // la ricerca si ripete mentre l'analisi della galleria va avanti (ogni 400 foto): escono anche le foto appena analizzate
        .task(id: "\(periodo.rawValue)|\(cerca)|\(cerca.isEmpty ? 0 : analisi.passo)") {
            try? await Task.sleep(for: .milliseconds(cerca.isEmpty ? 0 : 450))
            if !Task.isCancelled { await carica() }
        }
        .onAppear { apertaIl = Date(); aggiornaPannello() }
        .onChange(of: analisi.fatte) { _, _ in aggiornaPannello() }
        .onChange(of: analisi.attivo) { _, _ in aggiornaPannello() }
        .onChange(of: analisi.totale) { _, _ in aggiornaPannello() }
        // a galleria finita l'ologramma rilegge le ultime 30 foto, una ogni 1,5 s, solo con la sezione aperta e davanti
        .task(id: pannello && completa && !dietro) {
            guard pannello, completa, !dietro else { return }
            analisi.rileggendo(true)
            defer { analisi.rileggendo(false) }
            var k = 0
            while !Task.isCancelled {
                if let c = await IndiceFoto.condiviso.rileggi(k), !Task.isCancelled { analisi.mostra(c) }
                k = (k + 1) % 30
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
        // 4 nov: quando si comincia a scrivere si cerca in tutta la galleria (poi un periodo toccato restringe la ricerca)
        .onChange(of: cerca) { prima, adesso in
            let vuota = { (s: String) in s.trimmingCharacters(in: .whitespaces).isEmpty }
            if vuota(prima) && !vuota(adesso) && periodo != .tutte { periodo = .tutte }
        }
        .fullScreenCover(isPresented: Binding(get: { aperta != nil }, set: { if !$0 { aperta = nil } })) {
            if let foto, let k = aperta { VistaImmagini(immagini: foto, iniziale: k) }
        }
        .chiudiFoglioDietro { aperta = nil }                    // 4 nov: il visore (iOS) non resta sopra la sezione che sale
        .regia("Foto", stato: testoSchermo, azioni: azioniRegia)         // 12.0 (10): la regia
    }

    // MARK: 12.0 (10) · La regia

    /// Le foto per JARVIS: periodo, ricerca, quante foto, le parole capite dalla ricerca.
    private var testoSchermo: String {
        Schermo.unisci("Foto", ["periodo \(periodo.rawValue)", Schermo.campo("cerca", cerca),
                                foto.map { "\($0.count) foto a schermo" } ?? "la galleria si sta aprendo",
                                capite.isEmpty ? nil : "la ricerca ha capito: " + capite.joined(separator: ", "), nota])
    }

    /// Cosa sa fare Foto per JARVIS: cercare (cane, mare, concerto…), cambiare periodo, aprire una foto, togliere la ricerca.
    private var azioniRegia: [AzioneRegia] {
        [
            AzioneRegia("cerca", "cerca nelle foto per contenuto (cane, mare, concerto, vinile…)", valore: "cosa",
                        frasi: ["cerca *", "cercami *", "trova *", "trovami *", "mostrami le foto con *", "le foto con *", "foto con *"]) { v in
                let c = (v["cosa"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !c.isEmpty else { return .no("niente da cercare") }
                Suoni.tocco()
                cerca = c
                return .fatto("cerco «\(c)» in tutte le foto", battuta: { Battute.una("foto.cerca", ["Cerco \(c), Sir.", "Ecco le foto con \(c).", "Setaccio la galleria: \(c)."]) })
            },
            AzioneRegia("periodo", "oggi, ieri, 7 giorni, 30 giorni, tutte", valore: "quando", frasi: ["di *", "quelle di *", "periodo *"]) { v in
                let k = Regia.chiave(v["quando"] ?? "")
                let scelto: Periodo? = k.contains("oggi") ? .oggi : k.contains("ieri") ? .ieri : (k.contains("settiman") || k.contains("7")) ? .settimana
                    : (k.contains("mese") || k.contains("30")) ? .mese : (k.contains("tutt") || k.contains("sempre")) ? .tutte : nil
                guard let p = scelto else { return .no("periodo sconosciuto") }
                Suoni.tocco()
                periodo = p
                return .fatto("periodo \(p.rawValue)", battuta: { Battute.lampo() })
            },
            AzioneRegia("apri", "apre una foto a schermo intero (per posizione: la prima, la terza, l'ultima)", valore: "quale",
                        frasi: ["apri la *", "apri l *", "mostrami la *", "ingrandisci la *"]) { v in
                guard let f = foto, !f.isEmpty, let n = Regia.ordinale(v["quale"] ?? "") else { return .no("quale foto?") }
                let k = n > 0 ? n - 1 : f.count + n
                guard k >= 0, k < f.count else { return .no("non ci sono tante foto") }
                aperta = k
                return .fatto("foto \(k + 1) di \(f.count) aperta", battuta: { Battute.lampo() })
            },
            AzioneRegia("pulisci", "toglie la ricerca", frasi: ["togli la ricerca", "pulisci la ricerca", "tutte le foto"]) { _ in
                cerca = ""
                return .fatto("ricerca tolta", battuta: { Battute.lampo() })
            },
        ]
    }

    private func carica() async {
        guard await FotoLocali.autorizza() else { nota = "Serve l'accesso alle foto: Impostazioni › App › Jarvis › Foto."; foto = []; return }
        limitato = FotoLocali.accessoLimitato
        let (da, a) = periodo.intervallo
        let c = cerca.trimmingCharacters(in: .whitespaces)
        let esito = await FotoLocali.cercaTesto(c, da: da, a: a, quante: c.isEmpty ? 120 : 300)
        guard !Task.isCancelled else { return }                        // un'altra ricerca è già partita
        nota = esito.nota
        let nuove = esito.trovate.map { Immagine(fonte: "Le sue foto", locale: $0) }
        // le foto che arrivano adesso (non quelle già a schermo) si materializzano una dopo l'altra; non sotto il caricamento
        // della sezione e non con «Riduci movimento»
        var r: [String: Double] = [:]
        if Date().timeIntervalSince(apertaIl) > 1.15 && !riduci {
            let gia = Set((foto ?? []).map { $0.id })                     // quelle già nella griglia restano come sono
            var k = 0
            for f in nuove where !gia.contains(f.id) { r[f.id] = Double(min(k, 16)) * 0.026; k += 1 }
        }
        ritardi = r
        quandoRisultati = Date()
        withAnimation(.easeOut(duration: 0.25)) { foto = nuove }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.34)) { capite = esito.capite }
    }

    /// Il pannello dell'analisi, sempre visibile (7 nov sera, il signore: scelta A): appena c'è la galleria si apre; mentre l'analisi va
    /// avanti il conto, quando finisce davanti a lui dice «ANALISI COMPLETA» col suono «pronto» e resta, con la rilettura delle ultime
    /// foto. Se arrivano foto nuove da leggere torna al conto.
    private func aggiornaPannello() {
        if !pannello {
            guard analisi.totale > 0 else { return }
            completa = !analisi.attivo
            withAnimation(.easeOut(duration: 0.3)) { pannello = true }
        } else if !analisi.attivo && !completa {
            completa = true
            Suoni.fatto()
        } else if analisi.attivo && completa {
            completa = false
        }
    }

}

#endif
