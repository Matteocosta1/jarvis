import SwiftUI
import UIKit

// MARK: - PILATES: i programmi di Bea. L'editor (nome, attrezzo, durata, esercizi in ordine con ripetizioni, molle, timer e note)
// e la sessione guidata (FRIDAY dice ogni esercizio, il timer passa da solo al prossimo; sottovoce durante le lezioni).

/// Crea o cambia un programma. Salva solo con «Salva»; «Annulla» lascia tutto com'era.
struct EditorProgrammaP: View {
    @State var programma: ProgrammaP
    let nuovo: Bool
    let tinta: Color
    let salva: (ProgrammaP) -> Void
    let togli: () -> Void
    @Environment(\.dismiss) private var via
    @State private var aperto: UUID?
    @State private var chiediTogli = false

    private static let attrezzi = ["Reformer", "Bosu", "Matwork", "Chair", "Cadillac", "Altro"]

    private var valido: Bool { !programma.nome.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(nuovo ? "NUOVO PROGRAMMA" : "PROGRAMMA").font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
                    Spacer()
                    Button("Annulla") { via() }.font(.system(size: 14)).foregroundStyle(Color.tenue)
                }
                campo("Nome", $programma.nome, segnaposto: "Reformer intermedio")
                etichetta("Attrezzo")
                FlowF(spazio: 6) {
                    ForEach(Self.attrezzi, id: \.self) { a in ChipF(testo: a, acceso: programma.attrezzo == a, tinta: tinta) { programma.attrezzo = a } }
                }
                Stepper("Durata: \(programma.minuti) min", value: $programma.minuti, in: 5...120, step: 5)

                etichetta("Esercizi · \(programma.esercizi.count)")
                if programma.esercizi.isEmpty { NotaF(testo: "Aggiungi il primo esercizio: nome, ripetizioni o tempo, molle e, se vuoi, un timer.") }
                ForEach($programma.esercizi) { $e in riga($e) }
                TastoF(testo: "Aggiungi esercizio", icona: "plus", tinta: tinta, pieno: false) {
                    let e = EsercizioP(nome: "", dettaglio: "")
                    programma.esercizi.append(e)
                    aperto = e.id
                }

                TastoF(testo: "Salva", tinta: tinta) {
                    var p = programma
                    p.nome = p.nome.trimmingCharacters(in: .whitespaces)
                    p.esercizi.removeAll { $0.nome.trimmingCharacters(in: .whitespaces).isEmpty }
                    salva(p); Suoni.fatto(); via()
                }
                .disabled(!valido).opacity(valido ? 1 : 0.4)
                if !nuovo {
                    TastoF(testo: "Togli il programma", tinta: Color.rossoF, pieno: false) { chiediTogli = true }
                        .confirmationDialog("Togliere «\(programma.nome)»?", isPresented: $chiediTogli, titleVisibility: .visible) {
                            Button("Togli", role: .destructive) { togli(); via() }
                            Button("Annulla", role: .cancel) {}
                        }
                }
            }
            .padding(20)
        }
        .foregroundStyle(Color.testo)
        .tint(tinta)
    }

    /// Un esercizio: chiuso mostra nome e riassunto con le frecce per spostarlo; toccato si apre coi campi.
    @ViewBuilder private func riga(_ e: Binding<EsercizioP>) -> some View {
        let id = e.wrappedValue.id
        let k = programma.esercizi.firstIndex { $0.id == id } ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.2)) { aperto = aperto == id ? nil : id } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(k + 1). \(e.wrappedValue.nome.isEmpty ? "Nuovo esercizio" : e.wrappedValue.nome)").font(.system(size: 15, weight: .medium))
                        if !e.wrappedValue.riassunto.isEmpty { Text(e.wrappedValue.riassunto).font(.system(size: 12)).foregroundStyle(Color.tenue) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { sposta(k, -1) } label: { Image(systemName: "chevron.up") }.disabled(k == 0).opacity(k == 0 ? 0.3 : 1)
                Button { sposta(k, 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(k == programma.esercizi.count - 1).opacity(k == programma.esercizi.count - 1 ? 0.3 : 1)
            }
            .buttonStyle(.plain).foregroundStyle(tinta)
            if aperto == id {
                campo("Nome", e.nome, segnaposto: "Long Stretch")
                campo("Ripetizioni o tempo", e.dettaglio, segnaposto: "3 × 10")
                campo("Molle", Binding(get: { e.wrappedValue.molle ?? "" }, set: { e.wrappedValue.molle = $0.isEmpty ? nil : $0 }), segnaposto: "2 rosse")
                campo("Timer in secondi (facoltativo)", Binding(get: { e.wrappedValue.secondi.map(String.init) ?? "" },
                                                                 set: { e.wrappedValue.secondi = Int($0.filter(\.isNumber)).flatMap { $0 > 0 ? $0 : nil } }),
                      segnaposto: "45", tastiera: .numberPad)
                campo("Nota da dire", Binding(get: { e.wrappedValue.note ?? "" }, set: { e.wrappedValue.note = $0.isEmpty ? nil : $0 }), segnaposto: "spalle giù, respira")
                Button(role: .destructive) { programma.esercizi.removeAll { $0.id == id }; aperto = nil } label: {
                    Label("Togli esercizio", systemImage: "minus.circle").font(.system(size: 13))
                }
                .foregroundStyle(Color.rossoF)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(tinta.opacity(aperto == id ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(aperto == id ? 0.45 : 0.18), lineWidth: 1))
    }

    private func sposta(_ k: Int, _ d: Int) {
        let j = k + d
        guard programma.esercizi.indices.contains(k), programma.esercizi.indices.contains(j) else { return }
        Suoni.tocco()
        withAnimation(.easeOut(duration: 0.2)) { programma.esercizi.swapAt(k, j) }
    }

    private func etichetta(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
    }

    private func campo(_ titolo: String, _ testo: Binding<String>, segnaposto: String, tastiera: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            etichetta(titolo)
            TextField("", text: testo, prompt: Text(segnaposto).foregroundStyle(Color.tenue)).keyboardType(tastiera)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(tinta.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.3), lineWidth: 1))
        }
    }
}

/// La sessione guidata: un esercizio alla volta, grande. FRIDAY lo dice (sottovoce nelle lezioni); se ha il timer, il conto
/// alla rovescia passa da solo al prossimo. Indietro, Pausa, Prossimo, Fine. Lo schermo resta acceso.
struct SessionePilates: View {
    let programma: ProgrammaP
    let sottovoce: Bool
    let tinta: Color
    @Environment(\.dismiss) private var via
    @State private var passo = 0
    @State private var resto: Int?
    @State private var pausa = false
    @State private var finita = false

    private var esercizio: EsercizioP? { programma.esercizi.indices.contains(passo) ? programma.esercizi[passo] : nil }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(programma.nome.uppercased()).font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
                Spacer()
                Text(finita ? "FINE" : "\(passo + 1) / \(programma.esercizi.count)").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.tenue)
            }
            ProgressView(value: Double(finita ? programma.esercizi.count : passo), total: Double(max(1, programma.esercizi.count))).tint(tinta)
            Spacer(minLength: 10)
            if finita {
                Text("Fine. Brava.").font(.system(size: 34, weight: .semibold))
            } else if let e = esercizio {
                Text(e.nome).font(.system(size: 34, weight: .semibold)).multilineTextAlignment(.center)
                if !e.riassunto.isEmpty { Text(e.riassunto).font(.system(size: 18)).foregroundStyle(Color.tenue).multilineTextAlignment(.center) }
                if let n = e.note, !n.isEmpty { Text(n).font(.system(size: 16)).italic().foregroundStyle(tinta).multilineTextAlignment(.center) }
                if let r = resto {
                    Text(String(format: "%d:%02d", r / 60, r % 60)).font(.system(size: 64, weight: .light, design: .monospaced)).foregroundStyle(pausa ? Color.tenue : tinta)
                        .contentTransition(.numericText())
                }
                if passo + 1 < programma.esercizi.count {
                    Text("Poi: \(programma.esercizi[passo + 1].nome)").font(.system(size: 13)).foregroundStyle(Color.tenue)
                }
            }
            Spacer(minLength: 10)
            if finita {
                TastoF(testo: "Chiudi", tinta: tinta) { chiudi() }
            } else {
                HStack(spacing: 10) {
                    TastoF(testo: "Indietro", icona: "backward.fill", tinta: tinta, pieno: false) { vai(passo - 1) }.disabled(passo == 0).opacity(passo == 0 ? 0.4 : 1)
                    if resto != nil { TastoF(testo: pausa ? "Riprendi" : "Pausa", icona: pausa ? "play.fill" : "pause.fill", tinta: tinta, pieno: false) { pausa.toggle() } }
                    TastoF(testo: "Prossimo", icona: "forward.fill", tinta: tinta) { vai(passo + 1) }
                }
                TastoF(testo: "Fine", tinta: Color.rossoF, pieno: false) { chiudi() }
            }
        }
        .padding(20)
        .foregroundStyle(Color.testo)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Parlato.sottovoce = sottovoce
            vai(0)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Parlato.sottovoce = false
        }
        .task(id: passo) {                                                   // il conto alla rovescia dell'esercizio in corso
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, !pausa, !finita, let r = resto else { continue }
                if r <= 1 { vai(passo + 1); return }
                withAnimation { resto = r - 1 }
                if r - 1 == 3 { Suoni.tocco() }
            }
        }
    }

    private func vai(_ k: Int) {
        guard k >= 0 else { return }
        pausa = false
        if k >= programma.esercizi.count {
            finita = true; resto = nil
            Parlato.dici("Fine. Brava.")
            return
        }
        passo = k
        let e = programma.esercizi[k]
        resto = e.secondi
        var frase = e.nome
        if !e.riassunto.isEmpty { frase += ". " + e.riassunto }
        if let n = e.note, !n.isEmpty { frase += ". " + n }
        Parlato.dici(frase)
    }

    private func chiudi() {
        Parlato.sottovoce = false
        via()
    }
}
