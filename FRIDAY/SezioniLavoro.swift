#if os(iOS)
import SwiftUI
import Combine
import UIKit
import Photos
import HealthKit
@preconcurrency import AVFoundation
import CryptoKit
import UserNotifications

// MARK: - GESTIONALE (STRUMENTI): il gestionale di Bea Pilates, nel database del cervello. Bea lo legge e lo cambia da qui:
// lezioni, clienti con le lezioni rimaste, incassi, corsi, piano dei contenuti. Ogni modifica va subito nel database.

struct ClienteG: Identifiable, Equatable { var id = ""; var nome = ""; var tel = ""; var lezioni = 0.0; var note = "" }
struct LezioneG: Identifiable, Equatable { var id = ""; var cliente = ""; var data = ""; var ora = ""; var tipo = ""; var fatta = false }
struct PagamentoG: Identifiable, Equatable { var id = ""; var cliente = ""; var importo = 0.0; var lezioni = 0.0; var data = "" }
struct CorsoG: Identifiable, Equatable { var id = ""; var titolo = ""; var prezzo = 0.0; var abbonati: [String] = [] }
struct ContenutoG: Identifiable, Equatable { var id = ""; var titolo = ""; var tipo = "Reel"; var data = ""; var stato = "idea" }

/// I dati del gestionale e le chiamate al cervello (leggi tutto, salva una riga, togli una riga).
@MainActor final class Gestionale: ObservableObject {
    static let condiviso = Gestionale()
    @Published var clienti: [ClienteG] = []
    @Published var agenda: [LezioneG] = []
    @Published var pagamenti: [PagamentoG] = []
    @Published var corsi: [CorsoG] = []
    @Published var contenuti: [ContenutoG] = []
    @Published var caricato = false
    @Published var errore: String?

    static let giorno: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
    static func oggi(_ d: Date = Date()) -> String { giorno.string(from: d) }

    func nome(_ id: String) -> String { clienti.first { $0.id == id }?.nome ?? (id.isEmpty ? "—" : id) }

    func carica() async {
        guard let o = await VistaVitals.chiama(["gestionale": ["azione": "tutto"]], attesa: 25) else { errore = "Non raggiungo il gestionale."; return }
        if let e = o["errore"] as? String { errore = e; return }
        let righe: (String) -> [[String: Any]] = { o[$0] as? [[String: Any]] ?? [] }
        let s: ([String: Any], String) -> String = { ($0[$1] as? String) ?? (($0[$1] as? NSNumber)?.stringValue ?? "") }
        let n: ([String: Any], String) -> Double = { ($0[$1] as? NSNumber)?.doubleValue ?? Double(($0[$1] as? String) ?? "") ?? 0 }
        clienti = righe("clienti").map { ClienteG(id: s($0, "id"), nome: s($0, "nome"), tel: s($0, "tel"), lezioni: n($0, "lezioni"), note: s($0, "note")) }
            .sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
        agenda = righe("agenda").map { LezioneG(id: s($0, "id"), cliente: s($0, "cliente"), data: s($0, "data"), ora: s($0, "ora"), tipo: s($0, "tipo"), fatta: ($0["fatta"] as? Bool) ?? false) }
            .sorted { ($0.data, $0.ora) < ($1.data, $1.ora) }
        pagamenti = righe("pagamenti").map { PagamentoG(id: s($0, "id"), cliente: s($0, "cliente"), importo: n($0, "importo"), lezioni: n($0, "lezioni"), data: s($0, "data")) }
            .sorted { $0.data > $1.data }
        corsi = righe("corsi").map { CorsoG(id: s($0, "id"), titolo: s($0, "titolo"), prezzo: n($0, "prezzo"), abbonati: ($0["abbonati"] as? [Any])?.compactMap { $0 as? String } ?? []) }
        contenuti = righe("contenuti").map { ContenutoG(id: s($0, "id"), titolo: s($0, "titolo"), tipo: s($0, "tipo"), data: s($0, "data"), stato: s($0, "stato")) }
            .sorted { $0.data < $1.data }
        errore = nil
        caricato = true
    }

    @discardableResult
    func salva(_ tabella: String, _ riga: [String: Any]) async -> Bool {
        guard let o = await VistaVitals.chiama(["gestionale": ["azione": "salva", "tabella": tabella, "riga": riga]], attesa: 20) else {
            errore = "Non salvato: il gestionale non risponde."; return false
        }
        if let e = o["errore"] as? String { errore = "Non salvato: \(e)"; return false }
        await carica()
        return true
    }

    func elimina(_ tabella: String, _ id: String) async {
        _ = await VistaVitals.chiama(["gestionale": ["azione": "elimina", "tabella": tabella, "id": id]], attesa: 20)
        await carica()
    }

    func salva(_ c: ClienteG) async { await salva("clienti", ["id": c.id, "nome": c.nome, "tel": c.tel, "lezioni": c.lezioni, "note": c.note]) }
    func salva(_ l: LezioneG) async { await salva("agenda", ["id": l.id, "cliente": l.cliente, "data": l.data, "ora": l.ora, "tipo": l.tipo, "fatta": l.fatta]) }
    func salva(_ p: PagamentoG) async { await salva("pagamenti", ["id": p.id, "cliente": p.cliente, "importo": p.importo, "lezioni": p.lezioni, "data": p.data]) }
    func salva(_ c: CorsoG) async { await salva("corsi", ["id": c.id, "titolo": c.titolo, "prezzo": c.prezzo, "abbonati": c.abbonati]) }
    func salva(_ c: ContenutoG) async { await salva("contenuti", ["id": c.id, "titolo": c.titolo, "tipo": c.tipo, "data": c.data, "stato": c.stato]) }

    /// Lezione fatta (o tolta la spunta): la cliente perde (o riprende) una lezione del pacchetto.
    func spunta(_ l: LezioneG) async {
        var l = l; l.fatta.toggle()
        if var c = clienti.first(where: { $0.id == l.cliente }) {
            c.lezioni = max(0, c.lezioni + (l.fatta ? -1 : 1))
            await salva("clienti", ["id": c.id, "nome": c.nome, "tel": c.tel, "lezioni": c.lezioni, "note": c.note])
        }
        await salva(l)
    }

    /// Un incasso: si aggiungono alla cliente le lezioni pagate.
    func incassa(_ p: PagamentoG) async {
        if p.lezioni > 0, var c = clienti.first(where: { $0.id == p.cliente }) {
            c.lezioni += p.lezioni
            await salva("clienti", ["id": c.id, "nome": c.nome, "tel": c.tel, "lezioni": c.lezioni, "note": c.note])
        }
        await salva(p)
    }
}

struct VistaGestionale: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @StateObject private var g = Gestionale.condiviso
    @State private var parte = 0
    @State private var modulo: ModuloG?

    enum ModuloG: Identifiable {
        case cliente(ClienteG), lezione(LezioneG), pagamento(PagamentoG), corso(CorsoG), contenuto(ContenutoG)
        var id: String {
            switch self {
            case .cliente(let x): return "c" + x.id
            case .lezione(let x): return "l" + x.id
            case .pagamento(let x): return "p" + x.id
            case .corso(let x): return "k" + x.id
            case .contenuto(let x): return "s" + x.id
            }
        }
    }

    var body: some View {
        CorniceScheda(titolo: "Gestionale", sottotitolo: g.caricato ? "Bea Pilates · \(g.clienti.count) clienti" : "Collegamento gestionale", icona: "f:gestionale", tinta: tinta, pronto: g.caricato || g.errore != nil) {
            LinguetteF(voci: ["Agenda", "Clienti", "Incassi", "Corsi", "Social"], scelta: $parte)
            if let e = g.errore { RigaF(etichetta: "Gestionale", valore: e, stato: .no) }
            switch parte {
            case 0: agenda
            case 1: clienti
            case 2: incassi
            case 3: corsi
            default: social
            }
            NotaF(testo: "Il gestionale di Bea Pilates: quello che cambi qui va subito nel database. «FRIDAY, chi ho alle 10:30?»")
        }
        .task { await g.carica() }
        .sheet(item: $modulo) { m in FoglioGestionale(modulo: m).presentationDetents([.medium, .large]).presentationBackground(Color.fondo2) }
    }

    // ── Agenda: oggi, domani e i prossimi giorni con lezioni; la spunta segna la lezione fatta
    @ViewBuilder private var agenda: some View {
        let oggi = Gestionale.oggi()
        let giorni = (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) }.map { Gestionale.oggi($0) }
        let conLezioni = giorni.filter { d in d == oggi || g.agenda.contains { $0.data == d } }
        ForEach(conLezioni.prefix(6), id: \.self) { d in
            Pannello(titolo: titoloGiorno(d), tinta: tinta) {
                let lez = g.agenda.filter { $0.data == d }
                if lez.isEmpty { RigaF(etichetta: "Nessuna lezione", valore: "") }
                ForEach(lez) { l in
                    HStack(spacing: 10) {
                        Button { modulo = .lezione(l) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(l.ora).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.tipo.isEmpty ? "Lezione" : l.tipo).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.testo)
                                    Text(g.nome(l.cliente)).font(.system(size: 12)).foregroundStyle(Color.tenue)
                                }
                                Spacer(minLength: 0)
                            }
                        }.buttonStyle(.plain)
                        Button { Task { await g.spunta(l) } } label: {
                            Image(systemName: l.fatta ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                        }
                        .foregroundStyle(l.fatta ? Color.verdeF : tinta).buttonStyle(.plain)
                        .accessibilityLabel(l.fatta ? "Fatta" : "Da fare")
                    }
                    .opacity(l.fatta ? 0.6 : 1)
                }
            }
        }
        TastoF(testo: "Nuova lezione", icona: "plus") { modulo = .lezione(LezioneG(id: UUID().uuidString, cliente: g.clienti.first?.id ?? "", data: oggi, ora: "09:00", tipo: "Reformer")) }
    }

    private func titoloGiorno(_ d: String) -> String {
        guard let data = Gestionale.giorno.date(from: d) else { return d }
        if Calendar.current.isDateInToday(data) { return "OGGI" }
        if Calendar.current.isDateInTomorrow(data) { return "DOMANI" }
        return data.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT"))).uppercased()
    }

    // ── Clienti: le lezioni rimaste del pacchetto, in colore (rossa: una o nessuna)
    @ViewBuilder private var clienti: some View {
        Pannello(titolo: "CLIENTI", tinta: tinta) {
            if g.clienti.isEmpty { NotaF(testo: "Ancora nessuna cliente: aggiungi la prima qui sotto.") }
            ForEach(g.clienti) { c in
                Button { modulo = .cliente(c) } label: {
                    HStack(spacing: 10) {
                        Text(c.nome).font(.system(size: 14)).foregroundStyle(Color.testo).frame(width: 110, alignment: .leading).lineLimit(1)
                        GeometryReader { geo in
                            Capsule().fill(tinta.opacity(0.1))
                                .overlay(alignment: .leading) { Capsule().fill(coloreLezioni(c.lezioni)).frame(width: geo.size.width * min(1, c.lezioni / 10)) }
                        }.frame(height: 6)
                        Text("\(Int(c.lezioni)) \(Int(c.lezioni) == 1 ? "lezione" : "lezioni")").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
                    }
                }.buttonStyle(.plain)
            }
            if let ultima = g.clienti.first(where: { $0.lezioni <= 1 }) {
                TastoJarvis(testo: "A \(ultima.nome) resta \(Int(ultima.lezioni)) lezione: le scrivo?", icona: "message", tinta: tinta) {
                    chiedi("Scrivi a \(ultima.nome)\(ultima.tel.isEmpty ? "" : " (\(ultima.tel))") per il rinnovo del pacchetto di Pilates: le resta \(Int(ultima.lezioni)) lezione. Fammi vedere il messaggio prima di mandarlo.")
                }
            }
        }
        TastoF(testo: "Nuova cliente", icona: "plus") { modulo = .cliente(ClienteG(id: UUID().uuidString)) }
    }

    private func coloreLezioni(_ n: Double) -> Color { n <= 1 ? Color.rossoF : n <= 3 ? Color(red: 1, green: 0.54, blue: 0.24) : Color.verdeF }

    // ── Incassi: il mese, gli ultimi pagamenti
    @ViewBuilder private var incassi: some View {
        let mese = String(Gestionale.oggi().prefix(7))
        let delMese = g.pagamenti.filter { $0.data.hasPrefix(mese) }
        Pannello(titolo: Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "it_IT"))).uppercased(), tinta: tinta) {
            HStack {
                Valore(titolo: "INCASSATO", valore: euro(delMese.map(\.importo).reduce(0, +)), tinta: tinta)
                Valore(titolo: "LEZIONI", valore: "\(g.agenda.filter { $0.data.hasPrefix(mese) && $0.fatta }.count)", tinta: tinta)
            }
        }
        Pannello(titolo: "ULTIMI", tinta: tinta) {
            if g.pagamenti.isEmpty { NotaF(testo: "Nessun incasso registrato.") }
            ForEach(g.pagamenti.prefix(12)) { p in
                Button { modulo = .pagamento(p) } label: {
                    RigaF(etichetta: g.nome(p.cliente), valore: "\(giornoBreve(p.data)) · \(euro(p.importo))\(p.lezioni > 0 ? " · \(Int(p.lezioni)) lezioni" : "")")
                }.buttonStyle(.plain)
            }
        }
        TastoF(testo: "Nuovo incasso", icona: "plus") { modulo = .pagamento(PagamentoG(id: UUID().uuidString, cliente: g.clienti.first?.id ?? "", importo: 0, lezioni: 10, data: Gestionale.oggi())) }
    }

    // ── Corsi
    @ViewBuilder private var corsi: some View {
        Pannello(titolo: "CORSI", tinta: tinta) {
            if g.corsi.isEmpty { NotaF(testo: "Nessun corso: crea il primo (nome, prezzo, iscritte).") }
            ForEach(g.corsi) { c in
                Button { modulo = .corso(c) } label: {
                    RigaF(etichetta: c.titolo, valore: "\(euro(c.prezzo)) · \(c.abbonati.count) iscritte")
                }.buttonStyle(.plain)
            }
        }
        TastoF(testo: "Nuovo corso", icona: "plus") { modulo = .corso(CorsoG(id: UUID().uuidString)) }
    }

    // ── Social: il piano dei contenuti
    @ViewBuilder private var social: some View {
        Pannello(titolo: "PIANO", tinta: tinta) {
            if g.contenuti.isEmpty { NotaF(testo: "Il piano di Reel e post: aggiungi le idee e segna quando sono pronte.") }
            ForEach(g.contenuti) { c in
                Button { modulo = .contenuto(c) } label: {
                    RigaF(etichetta: "\(c.tipo) · \(c.titolo)", valore: [giornoBreve(c.data), c.stato].filter { !$0.isEmpty }.joined(separator: " · "),
                          stato: c.stato == "pronto" || c.stato == "pubblicato" ? .ok : c.stato == "da fare" ? .no : .normale)
                }.buttonStyle(.plain)
            }
        }
        TastoF(testo: "Nuovo contenuto", icona: "plus") { modulo = .contenuto(ContenutoG(id: UUID().uuidString, data: Gestionale.oggi())) }
    }

    private func euro(_ v: Double) -> String { v.formatted(.currency(code: "EUR").locale(Locale(identifier: "it_IT"))) }
    private func giornoBreve(_ d: String) -> String {
        guard let x = Gestionale.giorno.date(from: d) else { return d }
        return x.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "it_IT")))
    }
}

/// Il foglio per aggiungere, cambiare o togliere una riga del gestionale.
struct FoglioGestionale: View {
    @State var modulo: VistaGestionale.ModuloG
    @StateObject private var g = Gestionale.condiviso
    @Environment(\.dismiss) private var via
    @State private var salvo = false
    @State private var togli = false
    private let tinta = Color.ciano

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(titolo).font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
                campi
                TastoF(testo: salvo ? "Salvo…" : "Salva") { Task { salvo = true; await salva(); salvo = false; via() } }.disabled(salvo || !valido)
                if esiste {
                    TastoF(testo: "Togli", tinta: Color.rossoF, pieno: false) { togli = true }
                        .confirmationDialog("Togliere dal gestionale?", isPresented: $togli, titleVisibility: .visible) {
                            Button("Togli", role: .destructive) { Task { await elimina(); via() } }
                            Button("Annulla", role: .cancel) {}
                        }
                }
            }
            .padding(20)
        }
        .foregroundStyle(Color.testo)
        .tint(tinta)
    }

    private var titolo: String {
        switch modulo {
        case .cliente: return "CLIENTE"
        case .lezione: return "LEZIONE"
        case .pagamento: return "INCASSO"
        case .corso: return "CORSO"
        case .contenuto: return "CONTENUTO"
        }
    }

    private var esiste: Bool {
        switch modulo {
        case .cliente(let x): return g.clienti.contains { $0.id == x.id }
        case .lezione(let x): return g.agenda.contains { $0.id == x.id }
        case .pagamento(let x): return g.pagamenti.contains { $0.id == x.id }
        case .corso(let x): return g.corsi.contains { $0.id == x.id }
        case .contenuto(let x): return g.contenuti.contains { $0.id == x.id }
        }
    }

    private var valido: Bool {
        switch modulo {
        case .cliente(let x): return !x.nome.trimmingCharacters(in: .whitespaces).isEmpty
        case .lezione(let x): return !x.data.isEmpty && !x.ora.isEmpty
        case .pagamento(let x): return !x.cliente.isEmpty && x.importo > 0
        case .corso(let x): return !x.titolo.trimmingCharacters(in: .whitespaces).isEmpty
        case .contenuto(let x): return !x.titolo.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    @ViewBuilder private var campi: some View {
        switch modulo {
        case .cliente(let c):
            testo("Nome", c.nome) { var x = c; x.nome = $0; modulo = .cliente(x) }
            testo("Telefono", c.tel, tastiera: .phonePad) { var x = c; x.tel = $0; modulo = .cliente(x) }
            Stepper("Lezioni rimaste: \(Int(c.lezioni))", value: Binding(get: { c.lezioni }, set: { var x = c; x.lezioni = max(0, $0); modulo = .cliente(x) }), in: 0...200)
            testo("Note (solo tue)", c.note) { var x = c; x.note = $0; modulo = .cliente(x) }
        case .lezione(let l):
            sceltaCliente(l.cliente) { var x = l; x.cliente = $0; modulo = .lezione(x) }
            DatePicker("Giorno", selection: Binding(get: { Gestionale.giorno.date(from: l.data) ?? Date() }, set: { var x = l; x.data = Gestionale.oggi($0); modulo = .lezione(x) }), displayedComponents: .date)
            DatePicker("Ora", selection: Binding(get: { ora(l.ora) }, set: { var x = l; x.ora = $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)); modulo = .lezione(x) }), displayedComponents: .hourAndMinute)
            scelte(["Reformer", "Matwork", "Privata", "Bosu", "Individuale"], l.tipo) { var x = l; x.tipo = $0; modulo = .lezione(x) }
        case .pagamento(let p):
            sceltaCliente(p.cliente) { var x = p; x.cliente = $0; modulo = .pagamento(x) }
            numero("Importo (€)", p.importo) { var x = p; x.importo = $0; modulo = .pagamento(x) }
            Stepper("Lezioni pagate: \(Int(p.lezioni))", value: Binding(get: { p.lezioni }, set: { var x = p; x.lezioni = max(0, $0); modulo = .pagamento(x) }), in: 0...100)
            DatePicker("Giorno", selection: Binding(get: { Gestionale.giorno.date(from: p.data) ?? Date() }, set: { var x = p; x.data = Gestionale.oggi($0); modulo = .pagamento(x) }), displayedComponents: .date)
            if !esiste { NotaF(testo: "Le lezioni pagate si aggiungono a quelle rimaste della cliente.") }
        case .corso(let c):
            testo("Nome del corso", c.titolo) { var x = c; x.titolo = $0; modulo = .corso(x) }
            numero("Prezzo (€)", c.prezzo) { var x = c; x.prezzo = $0; modulo = .corso(x) }
            Text("ISCRITTE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            FlowF(spazio: 6) {
                ForEach(g.clienti) { cl in
                    ChipF(testo: cl.nome, acceso: c.abbonati.contains(cl.id)) { var x = c; x.abbonati.toggle(cl.id); modulo = .corso(x) }
                }
            }
        case .contenuto(let c):
            testo("Titolo", c.titolo) { var x = c; x.titolo = $0; modulo = .contenuto(x) }
            scelte(["Reel", "Post", "Storia"], c.tipo) { var x = c; x.tipo = $0; modulo = .contenuto(x) }
            DatePicker("Giorno", selection: Binding(get: { Gestionale.giorno.date(from: c.data) ?? Date() }, set: { var x = c; x.data = Gestionale.oggi($0); modulo = .contenuto(x) }), displayedComponents: .date)
            scelte(["idea", "da fare", "pronto", "pubblicato"], c.stato) { var x = c; x.stato = $0; modulo = .contenuto(x) }
        }
    }

    private func ora(_ s: String) -> Date {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: p.first ?? 9, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
    }

    private func testo(_ titolo: String, _ v: String, tastiera: UIKeyboardType = .default, _ cambia: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            TextField("", text: Binding(get: { v }, set: cambia)).keyboardType(tastiera)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(tinta.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.3), lineWidth: 1))
        }
    }

    private func numero(_ titolo: String, _ v: Double, _ cambia: @escaping (Double) -> Void) -> some View {
        testo(titolo, v == 0 ? "" : String(format: "%g", v), tastiera: .decimalPad) { cambia(Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0) }
    }

    private func scelte(_ voci: [String], _ attuale: String, _ cambia: @escaping (String) -> Void) -> some View {
        FlowF(spazio: 6) { ForEach(voci, id: \.self) { v in ChipF(testo: v, acceso: attuale == v) { cambia(v) } } }
    }

    private func sceltaCliente(_ id: String, _ cambia: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLIENTE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
            if g.clienti.isEmpty { NotaF(testo: "Prima aggiungi una cliente in Clienti.") }
            FlowF(spazio: 6) { ForEach(g.clienti) { c in ChipF(testo: c.nome, acceso: c.id == id) { cambia(c.id) } } }
        }
    }

    private func salva() async {
        switch modulo {
        case .cliente(let x): await g.salva(x)
        case .lezione(let x): await g.salva(x)
        case .pagamento(let x): if esiste { await g.salva(x) } else { await g.incassa(x) }
        case .corso(let x): await g.salva(x)
        case .contenuto(let x): await g.salva(x)
        }
    }

    private func elimina() async {
        switch modulo {
        case .cliente(let x): await g.elimina("clienti", x.id)
        case .lezione(let x): await g.elimina("agenda", x.id)
        case .pagamento(let x): await g.elimina("pagamenti", x.id)
        case .corso(let x): await g.elimina("corsi", x.id)
        case .contenuto(let x): await g.elimina("contenuti", x.id)
        }
    }
}

// MARK: - PILATES (CORPO): Allena (lo Specchio, i programmi, la settimana da Salute), Reel (foto o video 9:16 col conto alla
// rovescia, salvati in Foto, verso Instagram con la didascalia), Lezioni (oggi dal gestionale, la sequenza, le note sulle allieve).

/// Un esercizio di un programma: lo scrive e lo cambia Bea (nome, ripetizioni o tempo, molle, timer, note).
struct EsercizioP: Codable, Equatable, Identifiable {
    var id = UUID()
    var nome: String
    var dettaglio: String                 // ripetizioni o tempo, come lo scrive lei («3 × 10», «100 battute»)
    var molle: String? = nil              // «2 rosse», «1 blu»
    var secondi: Int? = nil               // il timer della sessione guidata: finito, passa da solo al prossimo
    var note: String? = nil               // cosa dire o ricordare («spalle giù»)

    /// La riga breve sotto il nome (e quella che FRIDAY dice).
    var riassunto: String {
        var v: [String] = []
        if !dettaglio.trimmingCharacters(in: .whitespaces).isEmpty { v.append(dettaglio) }
        if let m = molle, !m.trimmingCharacters(in: .whitespaces).isEmpty { v.append("molle \(m)") }
        if let s = secondi, s > 0 { v.append(s >= 60 ? "\(s / 60) min\(s % 60 > 0 ? " \(s % 60) s" : "")" : "\(s) s") }
        return v.joined(separator: " · ")
    }
}

/// Un programma di Bea: un attrezzo, una durata e gli esercizi in ordine. Si crea, si cambia e si toglie dall'app.
struct ProgrammaP: Codable, Equatable, Identifiable {
    var id = UUID()
    var nome: String
    var attrezzo: String
    var minuti: Int
    var esercizi: [EsercizioP]
}
struct AllievaP: Codable, Equatable, Identifiable { var id = UUID(); var nome: String; var nota: String; var ok: Bool }
struct ReelP: Codable, Equatable, Identifiable { var id = UUID(); var titolo: String; var video: Bool; var quando = Date(); var foto: String }

struct VistaPilates: View {
    let chiedi: (String) -> Void
    let specchio: () -> Void
    private let tinta = Color.ciano
    @StateObject private var g = Gestionale.condiviso
    @StateObject private var programmi = Salvato<[ProgrammaP]>("pilates_programmi", iniziale: VistaPilates.programmiIniziali)
    @StateObject private var lezione = Salvato<String>("pilates_lezione", iniziale: "")       // il programma scelto per le lezioni
    @StateObject private var allieve = Salvato<[AllievaP]>("pilates_allieve", iniziale: [])
    @StateObject private var reel = Salvato<[ReelP]>("pilates_reel", iniziale: [])
    @State private var parte = 0
    @State private var settimana: (sessioni: Int, minuti: Int)?
    @State private var registra = false
    @State private var video = true
    @State private var esercizio = ""
    @State private var didascalia = ""
    @State private var ultimoAsset: String?
    @State private var modifica: ModificaP?
    @State private var sessione: SessioneAperta?
    @State private var nuovaAllieva = ""
    @State private var nuovaNota = ""
    @State private var allievaInModifica: UUID?

    struct ModificaP: Identifiable { let id = UUID(); let programma: ProgrammaP; let nuovo: Bool }
    struct SessioneAperta: Identifiable { let id = UUID(); let programma: ProgrammaP; let sottovoce: Bool }

    /// I due programmi di partenza (Reformer e Bosu): da qui in poi li cambia Bea.
    static let programmiIniziali: [ProgrammaP] = [
        ProgrammaP(nome: "Reformer", attrezzo: "Reformer", minuti: 50, esercizi: [
            .init(nome: "Footwork", dettaglio: "4 posizioni · 10 rip"), .init(nome: "Hundred", dettaglio: "100 battute"),
            .init(nome: "Short Spine", dettaglio: "6 rip"), .init(nome: "Elephant", dettaglio: "8 rip"),
            .init(nome: "Knee Stretches", dettaglio: "3 × 10"), .init(nome: "Long Stretch", dettaglio: "6 rip"), .init(nome: "Mermaid", dettaglio: "3 per lato"),
        ]),
        ProgrammaP(nome: "Bosu", attrezzo: "Bosu", minuti: 20, esercizi: [
            .init(nome: "Squat sulla cupola", dettaglio: "3 × 12"), .init(nome: "Affondi", dettaglio: "3 × 10 per gamba"),
            .init(nome: "Plank sul lato piatto", dettaglio: "3 volte", secondi: 40), .init(nome: "Ponte con piedi sulla cupola", dettaglio: "3 × 12"),
        ]),
    ]

    /// Il programma delle lezioni: quello scelto, se c'è ancora, altrimenti il primo.
    private var programmaLezione: ProgrammaP? { programmi.valore.first { $0.id.uuidString == lezione.valore } ?? programmi.valore.first }

    var body: some View {
        CorniceScheda(titolo: "Pilates", sottotitolo: settimana.map { "\($0.sessioni) sessioni questa settimana" } ?? "Reformer · Bosu · Reel", icona: "f:allenatore", tinta: tinta) {
            LinguetteF(voci: ["Allena", "Reel", "Lezioni"], scelta: $parte)
            switch parte {
            case 0: allena
            case 1: reelVista
            default: lezioni
            }
        }
        .task { settimana = await Self.settimanaSalute(); if !g.caricato { await g.carica() } }
        .fullScreenCover(isPresented: $registra) {
            RegistraReelVista(video: video, titolo: esercizio) { esito in
                registra = false
                if let esito { Task { await salvato(esito) } }
            }
        }
        .sheet(item: $modifica) { m in
            EditorProgrammaP(programma: m.programma, nuovo: m.nuovo, tinta: tinta) { nuovo in
                if let i = programmi.valore.firstIndex(where: { $0.id == nuovo.id }) { programmi.valore[i] = nuovo } else { programmi.valore.append(nuovo) }
            } togli: {
                programmi.valore.removeAll { $0.id == m.programma.id }
            }
            .presentationDetents([.large]).presentationBackground(Color.fondo2)
        }
        .sheet(item: $sessione) { s in
            SessionePilates(programma: s.programma, sottovoce: s.sottovoce, tinta: tinta)
                .presentationDetents([.large]).presentationBackground(Color.fondo2).interactiveDismissDisabled()
        }
    }

    // ── Allena
    @ViewBuilder private var allena: some View {
        Pannello(titolo: "SPECCHIO", tinta: tinta) {
            NotaF(testo: "Metti l'iPhone davanti a te con la fotocamera frontale: ti vedi come in uno specchio, con lo scheletro sopra. In verde la posizione giusta, in rosso cosa correggere, e FRIDAY te lo dice a voce mentre ti alleni.")
            RigaF(etichetta: "Visione del corpo", valore: "sull'iPhone · nessun video esce", stato: .ok)
            TastoF(testo: "Apri lo Specchio", icona: "f:allenatore") { specchio() }
        }
        ForEach(programmi.valore) { p in
            Pannello(titolo: p.nome.uppercased(), tinta: tinta) {
                RigaF(etichetta: p.attrezzo, valore: "\(p.minuti) min · \(p.esercizi.count) esercizi")
                ForEach(Array(p.esercizi.enumerated()), id: \.element.id) { k, e in RigaF(etichetta: "\(k + 1). \(e.nome)", valore: e.riassunto) }
                if p.esercizi.isEmpty { NotaF(testo: "Ancora nessun esercizio: tocca «Modifica» e aggiungili.") }
                HStack(spacing: 10) {
                    TastoF(testo: "Inizia", icona: "play.fill") { if !p.esercizi.isEmpty { sessione = SessioneAperta(programma: p, sottovoce: false) } }
                    TastoF(testo: "Modifica", icona: "pencil", pieno: false) { modifica = ModificaP(programma: p, nuovo: false) }
                }
            }
        }
        TastoF(testo: "Nuovo programma", icona: "plus", pieno: false) {
            modifica = ModificaP(programma: ProgrammaP(nome: "", attrezzo: "Reformer", minuti: 50, esercizi: []), nuovo: true)
        }
        NotaF(testo: "I programmi sono tuoi: li scrivi, li cambi e li riordini tu. «Inizia» ti guida esercizio per esercizio, a voce e col timer.")
        Pannello(titolo: "SETTIMANA", tinta: tinta) {
            if let s = settimana {
                HStack {
                    Valore(titolo: "SESSIONI", valore: "\(s.sessioni)", tinta: tinta)
                    Valore(titolo: "ALLENATA", valore: s.minuti >= 60 ? "\(s.minuti / 60) h \(s.minuti % 60)" : "\(s.minuti) min", tinta: tinta)
                }
                NotaF(testo: "Gli allenamenti di Pilates registrati in Salute (Apple Watch o app) negli ultimi 7 giorni.")
            } else {
                NotaF(testo: "Leggo gli allenamenti di Pilates da Salute…")
            }
        }
    }

    // ── Reel
    @ViewBuilder private var reelVista: some View {
        Pannello(titolo: "REGISTRA", tinta: tinta) {
            NotaF(testo: "Appoggi l'iPhone, scegli foto o video in verticale 9:16 e FRIDAY parte con il conto alla rovescia.")
            HStack(spacing: 8) {
                ChipF(testo: "Foto", acceso: !video) { video = false }
                ChipF(testo: "Video", acceso: video) { video = true }
            }
            TextField("", text: $esercizio, prompt: Text("Esercizio (es. Long Stretch)").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
            TastoF(testo: "● Registra", tinta: Color.rossoF) { registra = true }
        }
        Pannello(titolo: "DOPO", tinta: tinta) {
            RigaF(etichetta: "Salva in Foto", valore: "sempre, in automatico", stato: .ok)
            RigaF(etichetta: "Instagram", valore: "apre Instagram con il video pronto")
            RigaF(etichetta: "Didascalia", valore: "proposta da FRIDAY, la cambi tu")
            if !didascalia.isEmpty {
                TextEditor(text: $didascalia).frame(minHeight: 90).scrollContentBackground(.hidden).foregroundStyle(Color.testo)
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(tinta.opacity(0.06)))
            }
            if let id = ultimoAsset {
                TastoF(testo: "Apri in Instagram", icona: "square.and.arrow.up") { apriInstagram(id) }
            }
            NotaF(testo: "Il tocco finale «Condividi» lo fai tu dentro Instagram: Apple e Instagram non permettono a un'app di pubblicare da sola sul profilo. La didascalia è già copiata: la incolli lì.")
        }
        Pannello(titolo: "ULTIMI", tinta: tinta) {
            if reel.valore.isEmpty { NotaF(testo: "Ancora niente: il primo Reel lo trovi qui.") }
            ForEach(reel.valore.suffix(6).reversed()) { r in
                RigaF(etichetta: r.titolo, valore: "\(r.video ? "video" : "foto") · \(r.quando.formatted(.dateTime.day().month(.abbreviated))) · salvato", stato: .ok)
            }
        }
    }

    private func salvato(_ e: RegistraReelVista.Esito) async {
        let titolo = esercizio.isEmpty ? (e.video ? "Video" : "Foto") : esercizio
        reel.valore.append(ReelP(titolo: titolo, video: e.video, foto: e.asset))
        ultimoAsset = e.asset
        Suoni.fatto()
        if let o = await VistaVitals.chiama(["scrivi": ["compito": "didascalia", "dati": ["esercizio": titolo, "tipo": e.video ? "video" : "foto"]]], attesa: 40),
           let t = o["testo"] as? String {
            didascalia = t
            UIPasteboard.general.string = t
        }
    }

    private func apriInstagram(_ id: String) {
        UIPasteboard.general.string = didascalia.isEmpty ? nil : didascalia
        let ig = URL(string: "instagram://library?LocalIdentifier=\(id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)")!
        UIApplication.shared.open(ig) { ok in
            if !ok { UIApplication.shared.open(URL(string: "https://www.instagram.com/")!) }
        }
    }

    // ── Lezioni
    @ViewBuilder private var lezioni: some View {
        let oggi = g.agenda.filter { $0.data == Gestionale.oggi() }
        Pannello(titolo: "OGGI", tinta: tinta) {
            if oggi.isEmpty { RigaF(etichetta: "Nessuna lezione oggi", valore: "") }
            ForEach(oggi) { l in RigaF(etichetta: "\(l.ora) · \(l.tipo)", valore: g.nome(l.cliente), stato: l.fatta ? .ok : .normale) }
            NotaF(testo: "Dal tuo gestionale.")
        }
        Pannello(titolo: "SEQUENZA", tinta: tinta) {
            NotaF(testo: "Scegli il programma della lezione. Durante la lezione FRIDAY ti dice ogni esercizio sottovoce negli AirPods: «Prossimo» quando vuoi, o da solo a fine timer.")
            FlowF(spazio: 6) {
                ForEach(programmi.valore) { p in ChipF(testo: p.nome, acceso: p.id == programmaLezione?.id) { lezione.valore = p.id.uuidString } }
            }
            if let p = programmaLezione {
                ForEach(Array(p.esercizi.enumerated()), id: \.element.id) { k, e in RigaF(etichetta: "\(k + 1). \(e.nome)", valore: e.riassunto) }
                HStack(spacing: 10) {
                    TastoF(testo: "Inizia la lezione", icona: "forward.fill") { if !p.esercizi.isEmpty { sessione = SessioneAperta(programma: p, sottovoce: true) } }
                    TastoF(testo: "Modifica", icona: "pencil", pieno: false) { modifica = ModificaP(programma: p, nuovo: false) }
                }
            } else {
                NotaF(testo: "Nessun programma: crealo in Allena con «Nuovo programma».")
            }
        }
        Pannello(titolo: "ALLIEVE", tinta: tinta) {
            ForEach(allieve.valore) { a in
                HStack {
                    Button {                                                                     // toccata: la cambi nei campi qui sotto
                        allievaInModifica = a.id; nuovaAllieva = a.nome; nuovaNota = a.nota
                    } label: { RigaF(etichetta: a.nome, valore: a.nota, stato: a.ok ? .ok : .no) }.buttonStyle(.plain)
                    Button { allieve.valore.removeAll { $0.id == a.id } } label: { Image(systemName: "minus.circle") }.foregroundStyle(Color.tenue).buttonStyle(.plain)
                }
            }
            HStack {
                TextField("", text: $nuovaAllieva, prompt: Text("Nome").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo).frame(width: 90)
                TextField("", text: $nuovaNota, prompt: Text("spalla dx: niente Long Stretch").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                Button {
                    guard !nuovaAllieva.isEmpty else { return }
                    let pronta = nuovaNota.lowercased().contains("pronta")
                    if let id = allievaInModifica, let i = allieve.valore.firstIndex(where: { $0.id == id }) {
                        allieve.valore[i].nome = nuovaAllieva; allieve.valore[i].nota = nuovaNota; allieve.valore[i].ok = pronta
                    } else {
                        allieve.valore.append(AllievaP(nome: nuovaAllieva, nota: nuovaNota, ok: pronta))
                    }
                    nuovaAllieva = ""; nuovaNota = ""; allievaInModifica = nil
                } label: { Image(systemName: allievaInModifica == nil ? "plus.circle.fill" : "checkmark.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
            }
            NotaF(testo: "Note tue, visibili solo a te. Tocca un'allieva per cambiarla; «pronta» nella nota la segna in verde.")
        }
    }

    /// Gli allenamenti di Pilates in Salute negli ultimi 7 giorni.
    nonisolated static func settimanaSalute() async -> (sessioni: Int, minuti: Int)? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let negozio = HKHealthStore()
        try? await negozio.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        let da = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let pred = HKQuery.predicateForSamples(withStart: da, end: Date())
        let lista: [HKWorkout] = await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 50, sortDescriptors: nil) { _, s, _ in
                c.resume(returning: (s as? [HKWorkout] ?? []).filter { $0.workoutActivityType == .pilates })
            }
            negozio.execute(q)
        }
        return (lista.count, Int(lista.map(\.duration).reduce(0, +) / 60))
    }
}

/// La fotocamera dei Reel: anteprima a tutto schermo in verticale, conto alla rovescia a voce, foto o video (con l'audio),
/// salvataggio in Foto. Torna l'identificativo della foto o del video in Foto.
struct RegistraReelVista: View {
    struct Esito { let asset: String; let video: Bool }
    let video: Bool
    let titolo: String
    let fine: (Esito?) -> Void
    @StateObject private var r = RegistraReel()
    @EnvironmentObject private var jarvis: Jarvis           // la fotocamera dei Reel registra anche l'audio: il richiamo tace
    @State private var conto: Int?
    @State private var frontale = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaReel(sessione: r.sessione).ignoresSafeArea()
            if let conto { Text("\(conto)").font(.system(size: 120, weight: .bold, design: .rounded)).foregroundStyle(.white).shadow(radius: 12) }
            VStack {
                HStack {
                    Button { r.ferma(); fine(nil) } label: { TondoX() }
                    Spacer()
                    if !titolo.isEmpty { Text(titolo.uppercased()).font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.white) }
                    Spacer()
                    Button { frontale.toggle(); r.prepara(frontale: frontale, video: video) } label: { TondoX(simbolo: "arrow.triangle.2.circlepath") }
                }
                .padding(.horizontal, 12)
                Spacer()
                if let e = r.errore { Text(e).font(.footnote).foregroundStyle(.white).padding(8).background(.black.opacity(0.6), in: Capsule()) }
                Button { tasto() } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        if r.registra { RoundedRectangle(cornerRadius: 6).fill(Color.rossoF).frame(width: 30, height: 30) }
                        else { Circle().fill(video ? Color.rossoF : .white).frame(width: 62, height: 62) }
                    }
                }
                .disabled(conto != nil || r.salvo)
                .padding(.bottom, 30)
            }
        }
        .onAppear { jarvis.micOccupato = true; r.prepara(frontale: frontale, video: video) }
        .onDisappear { r.ferma(); jarvis.micOccupato = false }
        .onChange(of: r.esito) { _, e in if let e { fine(Esito(asset: e, video: video)) } }
    }

    private func tasto() {
        if r.registra { r.stop(); return }
        Task {
            for k in stride(from: 3, through: 1, by: -1) {
                conto = k; Parlato.dici("\(k)")
                try? await Task.sleep(for: .seconds(1))
            }
            conto = nil
            Suoni.tocco()
            if video { r.avvia() } else { r.scatta() }
        }
    }
}

struct AnteprimaReel: UIViewRepresentable {
    let sessione: AVCaptureSession
    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var anteprima: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Vista {
        let v = Vista(); v.anteprima.session = sessione; v.anteprima.videoGravity = .resizeAspectFill; return v
    }
    func updateUIView(_ v: Vista, context: Context) {}
}

/// Il motore della fotocamera dei Reel (sessione su una coda sua; i risultati tornano sul thread principale).
@MainActor final class RegistraReel: NSObject, ObservableObject {
    @Published var registra = false
    @Published var salvo = false
    @Published var errore: String?
    @Published var esito: String?
    let sessione = AVCaptureSession()
    private let lavoro = Lavoro()

    /// Quello che gira fuori dal thread principale: la sessione e le uscite.
    nonisolated final class Lavoro: NSObject, AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        let coda = DispatchQueue(label: "friday.reel")
        let film = AVCaptureMovieFileOutput()
        let foto = AVCapturePhotoOutput()
        var finito: ((URL?, Data?, Error?) -> Void)?

        func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
            finito?(url, nil, error)
        }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            finito?(nil, photo.fileDataRepresentation(), error)
        }
    }

    func prepara(frontale: Bool, video: Bool) {
        let s = sessione, l = lavoro
        l.finito = { [weak self] url, dati, err in
            let messaggio = err?.localizedDescription
            Task { @MainActor in self?.arrivato(url: url, dati: dati, errore: messaggio) }
        }
        l.coda.async {
            s.beginConfiguration()
            s.inputs.forEach { s.removeInput($0) }
            s.outputs.forEach { s.removeOutput($0) }
            s.sessionPreset = video ? .high : .photo
            if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: frontale ? .front : .back),
               let ing = try? AVCaptureDeviceInput(device: cam), s.canAddInput(ing) { s.addInput(ing) }
            if video, let mic = AVCaptureDevice.default(for: .audio), let ing = try? AVCaptureDeviceInput(device: mic), s.canAddInput(ing) { s.addInput(ing) }
            let uscita: AVCaptureOutput = video ? l.film : l.foto
            if s.canAddOutput(uscita) { s.addOutput(uscita) }
            if let c = uscita.connection(with: .video) {
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }          // in verticale: 9:16
                if frontale, c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true }
            }
            s.commitConfiguration()
            if !s.isRunning { s.startRunning() }
        }
    }

    func avvia() {
        let l = lavoro
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reel-\(UUID().uuidString).mov")
        registra = true
        l.coda.async { l.film.startRecording(to: url, recordingDelegate: l) }
    }

    func stop() { let l = lavoro; l.coda.async { l.film.stopRecording() } }

    func scatta() {
        let l = lavoro
        l.coda.async { l.foto.capturePhoto(with: AVCapturePhotoSettings(), delegate: l) }
    }

    func ferma() { let s = sessione; lavoro.coda.async { if s.isRunning { s.stopRunning() } } }

    private func arrivato(url: URL?, dati: Data?, errore err: String?) {
        registra = false
        let filmato = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if !filmato && dati == nil { errore = err ?? "Non ho registrato niente: riprova."; return }
        salvo = true
        Task {
            let id = await RegistraReel.inFoto(url: url, dati: dati)
            salvo = false
            if let id { esito = id; ferma() } else { errore = "Non riesco a salvare in Foto: controlla il permesso in Impostazioni." }
        }
    }

    /// Salva in Foto e restituisce l'identificativo (per aprirlo in Instagram).
    nonisolated static func inFoto(url: URL?, dati: Data?) async -> String? {
        let st = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard st == .authorized || st == .limited else { return nil }
        let scatola = Scatola()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let r: PHAssetCreationRequest = PHAssetCreationRequest.forAsset()
                if let url { r.addResource(with: .video, fileURL: url, options: nil) }
                else if let dati { r.addResource(with: .photo, data: dati, options: nil) }
                scatola.id = r.placeholderForCreatedAsset?.localIdentifier
            }
        } catch { return nil }
        if let url { try? FileManager.default.removeItem(at: url) }
        return scatola.id
    }
    nonisolated private final class Scatola: @unchecked Sendable { var id: String? }
}

// MARK: - ARMADIO (STRUMENTI): i capi (dagli Occhi o staccati da una foto), la prova vera su una foto di Bea, i doppioni,
// l'annuncio Vinted, i conti e i desideri con le 48 ore.

struct CapoA: Identifiable, Equatable { let id: String; let cat: String; let nome: String; let brand: String; let colore: String; let hash: String; let mini: UIImage? }
struct ProvaA: Identifiable, Equatable { let id: String; let quando: String; let mini: UIImage? }
struct DesiderioA: Codable, Equatable, Identifiable { var id = UUID(); var nome: String; var da = Date() }
struct MovimentoA: Codable, Equatable, Identifiable { var id = UUID(); var cosa: String; var euro: Double; var venduto: Bool; var quando = Date() }

/// Le chiamate dell'Armadio al cervello (le funzioni SQL friday_*) e il caricamento delle foto a pezzi.
enum ArmadioF {
    static func rpc(_ nome: String, _ args: [String: Any] = [:], attesa: TimeInterval = 25) async -> Any? {
        guard let o = await VistaVitals.chiama(["rpc": ["nome": nome, "args": args]], attesa: attesa), o["errore"] == nil else { return nil }
        return o["dati"]
    }

    static func immagine(_ b64: String?) -> UIImage? { b64.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) } }

    /// Carica una foto (JPEG) nei pezzi del database e restituisce la sua impronta (SHA-256).
    static func carica(_ img: UIImage, lato: CGFloat = 1600) async -> String? {
        let piccola = img.ridotta(lato: lato)
        guard let dati = piccola.jpegData(compressionQuality: 0.85) else { return nil }
        let hash = SHA256.hash(data: dati).map { String(format: "%02x", $0) }.joined()
        if let mancano = await rpc("friday_foto_mancanti", ["p_hash": [hash]]) as? [String], mancano.isEmpty { return hash }   // già su
        let b64 = dati.base64EncodedString()
        let misura = 400_000
        let tot = (b64.count + misura - 1) / misura
        for k in 0..<tot {
            let da = b64.index(b64.startIndex, offsetBy: k * misura), a = b64.index(da, offsetBy: min(misura, b64.count - k * misura))
            guard await rpc("friday_foto_parte", ["p_hash": hash, "p_parte": k, "p_tot": tot, "p_mime": "image/jpeg", "p_dati": String(b64[da..<a])], attesa: 60) != nil else { return nil }
        }
        return hash
    }

    static func ruolo(_ cat: String) -> String {
        switch cat {
        case "maglie", "camicie": return "sopra"
        case "jeans", "pantaloni", "gonne": return "sotto"
        case "vestiti": return "vestito"
        case "giacche", "cappotti": return "giacca"
        case "scarpe": return "scarpe"
        case "borse": return "borsa"
        default: return "sopra"
        }
    }
}

extension UIImage {
    /// La foto ridotta al lato più lungo dato (le foto della fotocamera sono 4000 punti: troppe per il cervello).
    func ridotta(lato: CGFloat) -> UIImage {
        let m = max(size.width, size.height)
        guard m > lato else { return self }
        let k = lato / m, nuova = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: nuova, format: f).image { _ in draw(in: CGRect(origin: .zero, size: nuova)) }
    }
}

struct VistaArmadio: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @State private var parte = 0
    @State private var capi: [CapoA] = []
    @State private var totale: Int?
    @State private var prove: [ProvaA] = []
    @State private var caricando = false
    @State private var foto: Compito?
    @State private var letto: [String: Any] = [:]
    @State private var ultimaFoto: UIImage?
    @State private var stato: String?
    @State private var scelti: [String] = []
    @State private var alta = false
    @State private var risultato: UIImage?
    @State private var doppione: String?
    @State private var annuncio: [String: String] = [:]
    @State private var pagato = ""
    @State private var condizioni = "ottime"
    @State private var capoVinted: CapoA?
    @StateObject private var bea = Salvato<String>("armadio_bea", iniziale: "")
    @StateObject private var desideri = Salvato<[DesiderioA]>("armadio_desideri", iniziale: [])
    @StateObject private var conti = Salvato<[MovimentoA]>("armadio_conti", iniziale: [])
    @StateObject private var pubblicati = Salvato<Int>("armadio_pubblicati", iniziale: 0)
    @State private var nuovoDesiderio = ""
    @State private var nuovoMov = ""
    @State private var nuovoEuro = ""
    @State private var nuovoVenduto = false

    enum Compito: String, Identifiable { case capo, bea, doppione, vinted; var id: String { rawValue } }

    var body: some View {
        CorniceScheda(titolo: "Armadio", sottotitolo: totale.map { "\($0) capi\(prove.isEmpty ? "" : " · \(prove.count) prove")" } ?? "Apertura armadio", icona: "f:armadio", tinta: tinta, pronto: totale != nil) {
            LinguetteF(voci: ["Capi", "Vinted", "Conti"], scelta: $parte)
            if let stato { RigaF(etichetta: "FRIDAY", valore: stato) }
            switch parte {
            case 0: capiVista
            case 1: vinted
            default: contiVista
            }
        }
        .task { await ricarica() }
        .fullScreenCover(item: $foto) { c in
            Fotocamera(sorgente: c == .bea ? .photoLibrary : .camera) { img in Task { await arrivata(img, c) } }.ignoresSafeArea()
        }
    }

    private func ricarica() async {
        totale = (await ArmadioF.rpc("friday_capi_conta") as? NSNumber)?.intValue ?? totale ?? 0
        var tutti: [CapoA] = []
        var da = 0
        while da < 200, let pagina = await ArmadioF.rpc("friday_capi_elenco", ["p_da": da, "p_quanti": 20], attesa: 40) as? [[String: Any]], !pagina.isEmpty {
            tutti += pagina.map { r in
                CapoA(id: r["id"] as? String ?? UUID().uuidString, cat: r["cat"] as? String ?? "", nome: r["nome"] as? String ?? "", brand: r["brand"] as? String ?? "",
                      colore: r["colore"] as? String ?? "", hash: r["foto_hash"] as? String ?? "", mini: ArmadioF.immagine(r["miniatura"] as? String))
            }
            if pagina.count < 20 { break }
            da += 20
        }
        capi = tutti.reversed()
        if let p = await ArmadioF.rpc("friday_prova_elenco", ["p_quanti": 12], attesa: 40) as? [[String: Any]] {
            prove = p.map { ProvaA(id: $0["id"] as? String ?? "", quando: $0["creato"] as? String ?? "", mini: ArmadioF.immagine($0["miniatura"] as? String)) }
        }
    }

    // ── Capi
    @ViewBuilder private var capiVista: some View {
        Pannello(titolo: "ARMADIO", tinta: tinta) {
            HStack {
                Valore(titolo: "CAPI", valore: "\(totale ?? 0)", tinta: tinta)
                Valore(titolo: "CATEGORIE", valore: "\(Set(capi.map(\.cat)).count)", tinta: tinta)
                Valore(titolo: "PROVE", valore: "\(prove.count)", tinta: tinta)
            }
            if !capi.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(capi.prefix(40)) { c in
                        Button { scelti.toggle(c.id); if scelti.count > 6 { scelti.removeFirst() } } label: { miniatura(c) }.buttonStyle(.plain)
                    }
                }
                NotaF(testo: "Tocca fino a 6 capi per la prova vera.")
            }
        }
        Pannello(titolo: "OCCHI", tinta: tinta) {
            NotaF(testo: "Inquadra un vestito o l'etichetta: FRIDAY riconosce capo, brand, colore, materiale e taglia, e lo mette nell'armadio.")
            if !letto.isEmpty {
                RigaF(etichetta: "Capo", valore: letto["capo"] as? String ?? "—")
                let brand = letto["brand"] as? String ?? ""
                RigaF(etichetta: "Brand", valore: brand.isEmpty ? "—" : (letto["brand_sicuro"] as? Bool == true ? "\(brand) · dall'etichetta" : "\(brand) · probabile"), stato: letto["brand_sicuro"] as? Bool == true ? .ok : .normale)
                RigaF(etichetta: "Colore", valore: letto["colore"] as? String ?? "—")
                RigaF(etichetta: "Materiale", valore: (letto["materiale"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                RigaF(etichetta: "Taglia", valore: (letto["taglia"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                TastoF(testo: caricando ? "Lo metto nell'armadio…" : "Metti nell'armadio", icona: "f:armadio") { Task { await mettiNellArmadio() } }.disabled(caricando || ultimaFoto == nil)
            }
            TastoF(testo: "Inquadra un capo", icona: "camera", pieno: letto.isEmpty) { foto = .capo }
            NotaF(testo: "Con logo o etichetta visibili il brand è sicuro; senza, FRIDAY scrive «probabile».")
        }
        Pannello(titolo: "PROVA VERA", tinta: tinta) {
            if let r = risultato { Image(uiImage: r).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) }
            RigaF(etichetta: "La tua foto", valore: bea.valore.isEmpty ? "da caricare" : "pronta", stato: bea.valore.isEmpty ? .no : .ok)
            RigaF(etichetta: "Capi scelti", valore: "\(scelti.count) di 6")
            HStack(spacing: 8) {
                ChipF(testo: "Normale · ~7 cent", acceso: !alta) { alta = false }
                ChipF(testo: "Alta · ~14 cent", acceso: alta) { alta = true }
            }
            TastoF(testo: "＋ Carica la tua foto (figura intera)", pieno: false) { foto = .bea }
            TastoF(testo: caricando ? "Preparo la prova…" : "Prova addosso", icona: "sparkles") { Task { await prova() } }.disabled(caricando || bea.valore.isEmpty || scelti.isEmpty)
            if !prove.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(prove) { p in
                            Button { Task { await apriProva(p.id) } } label: {
                                Group { if let m = p.mini { Image(uiImage: m).resizable().scaledToFill() } else { tinta.opacity(0.1) } }
                                    .frame(width: 64, height: 86).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            NotaF(testo: "Una foto a figura intera, con qualsiasi sfondo: FRIDAY ti veste con i capi scelti. La foto resta nel tuo database privato.")
        }
        Pannello(titolo: "DOPPIONI", tinta: tinta) {
            NotaF(testo: "Inquadra un capo in negozio o su Vinted e FRIDAY ti dice se hai già qualcosa di simile.")
            if let doppione { RigaF(etichetta: "Ultimo controllo", valore: doppione) }
            TastoF(testo: "Ce l'ho già?", icona: "camera", pieno: false) { foto = .doppione }
        }
    }

    private func miniatura(_ c: CapoA) -> some View {
        let acceso = scelti.contains(c.id)
        return VStack(spacing: 3) {
            Group { if let m = c.mini { Image(uiImage: m).resizable().scaledToFit() } else { SimboloFriday(nome: "f:armadio", lato: 18).foregroundStyle(tinta) } }
                .frame(height: 64).frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(acceso ? tinta : .clear, lineWidth: 2))
            Text(c.nome).font(.system(size: 9)).foregroundStyle(acceso ? tinta : Color.tenue).lineLimit(1)
        }
    }

    private func arrivata(_ img: UIImage, _ c: Compito) async {
        switch c {
        case .bea:
            stato = "Carico la tua foto…"
            if let h = await ArmadioF.carica(img, lato: 1600) { bea.valore = h; stato = "La tua foto è pronta per la prova." } else { stato = "La foto non è arrivata: riprova." }
        case .capo, .vinted:
            ultimaFoto = img
            stato = "Guardo il capo…"
            guard let b64 = img.jpegFriday(lato: 1280), let o = await VistaVitals.chiama(["vista": ["compito": "capo", "immagine": b64]], attesa: 60) else { stato = "Non sono riuscita a guardarlo."; return }
            letto = o; stato = nil
            if c == .vinted { await scriviAnnuncio(descrizione(o)) }
        case .doppione:
            stato = "Confronto con il tuo armadio…"
            let elenco = capi.map { "\($0.nome) \($0.colore) \($0.brand)".trimmingCharacters(in: .whitespaces) }.joined(separator: "; ")
            guard let b64 = img.jpegFriday(lato: 1024), let o = await VistaVitals.chiama(["vista": ["compito": "doppione", "immagine": b64, "contesto": elenco]], attesa: 60) else { stato = "Non sono riuscita a guardarlo."; return }
            let simili = o["simili"] as? [String] ?? []
            doppione = "\(o["capo"] as? String ?? "questo capo") · " + (simili.isEmpty ? "niente di simile" : "ne hai \(simili.count) simil\(simili.count == 1 ? "e" : "i"): \(simili.joined(separator: ", "))")
            stato = nil
            Parlato.dici(simili.isEmpty ? "Non hai niente di simile." : "Ne hai già \(simili.count) simil\(simili.count == 1 ? "e" : "i").")
        }
    }

    private func descrizione(_ o: [String: Any]) -> String {
        ["capo", "brand", "colore", "materiale", "taglia"].compactMap { (o[$0] as? String).flatMap { $0.isEmpty ? nil : $0 } }.joined(separator: ", ")
    }

    private func mettiNellArmadio() async {
        guard let img = ultimaFoto else { return }
        caricando = true; defer { caricando = false }
        stato = "Carico la foto…"
        guard let h = await ArmadioF.carica(img, lato: 1600) else { stato = "La foto non è arrivata: riprova."; return }
        guard let id = await ArmadioF.rpc("friday_estrai_avvia", ["p": ["fonte": h, "nome": letto["capo"] as? String ?? ""]]) as? String else { stato = "Non riesco a metterlo nell'armadio adesso."; return }
        stato = "Lo stacco dalla foto (meno di un minuto)…"
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(3))
            guard let s = await ArmadioF.rpc("friday_estrai_stato", ["p_id": id]) as? [String: Any] else { continue }
            let st = s["stato"] as? String ?? ""
            if st == "pronta" || st == "fatta" || st == "pronto" { break }
            if st == "errore" { stato = "Non ci sono riuscita: \(s["errore"] as? String ?? "riprova")."; return }
        }
        letto = [:]; ultimaFoto = nil; stato = "Nell'armadio."
        Suoni.fatto()
        await ricarica()
    }

    private func prova() async {
        let pezzi = capi.filter { scelti.contains($0.id) && !$0.hash.isEmpty }
        guard !pezzi.isEmpty, !bea.valore.isEmpty else { return }
        caricando = true; defer { caricando = false }
        stato = "Preparo la prova…"
        let richiesta: [String: Any] = ["bea": bea.valore, "qualita": alta ? "alta" : "normale", "formato": "3:4",
                                        "capi": pezzi.map { ["hash": $0.hash, "ruolo": ArmadioF.ruolo($0.cat), "nome": $0.nome, "brand": $0.brand, "colore": $0.colore] }]
        guard let id = await ArmadioF.rpc("friday_prova_avvia", ["p": richiesta]) as? String else { stato = "La prova non parte: la tua foto va ricaricata?"; return }
        stato = "Ti vesto (circa 30 secondi)…"
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(3))
            guard let s = await ArmadioF.rpc("friday_prova_stato", ["p_id": id]) as? [String: Any] else { continue }
            let st = s["stato"] as? String ?? ""
            if st == "pronta" { stato = nil; await apriProva(id); Suoni.fatto(); await ricarica(); return }
            if st == "errore" { stato = "Non ci sono riuscita: \(s["errore"] as? String ?? "riprova")."; return }
        }
        stato = "Ci sta mettendo troppo: la trovi qui sotto appena è pronta."
    }

    private func apriProva(_ id: String) async {
        guard let s = await ArmadioF.rpc("friday_prova_stato", ["p_id": id]) as? [String: Any], let n = (s["n"] as? NSNumber)?.intValue, n > 0 else { return }
        var b64 = ""
        var da = 1
        while da <= n {
            guard let pezzo = await ArmadioF.rpc("friday_prova_pezzo", ["p_id": id, "p_da": da, "p_quanti": 900_000], attesa: 60) as? String, !pezzo.isEmpty else { break }
            b64 += pezzo; da += pezzo.count
        }
        if let img = ArmadioF.immagine(b64) { risultato = img }
    }

    // ── Vinted
    @ViewBuilder private var vinted: some View {
        Pannello(titolo: "VENDI", tinta: tinta) {
            NotaF(testo: "Fai la foto e FRIDAY prepara l'annuncio: titolo, descrizione, taglia, condizioni, categoria. Tu lo incolli su Vinted.")
            HStack {
                TextField("", text: $pagato, prompt: Text("Pagato (€)").foregroundStyle(Color.tenue)).keyboardType(.decimalPad).foregroundStyle(Color.testo)
                TextField("", text: $condizioni, prompt: Text("Condizioni").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
            }
            TastoF(testo: "Fotografa il capo da vendere", icona: "camera") { foto = .vinted }
            if !capi.isEmpty {
                Menu {
                    ForEach(capi.prefix(60)) { c in Button(c.nome + (c.brand.isEmpty ? "" : " · \(c.brand)")) { Task { await scriviAnnuncio("\(c.nome), \(c.brand), \(c.colore)") } } }
                } label: { Label("Oppure scegli dall'armadio", systemImage: "list.bullet").font(.system(size: 14)).foregroundStyle(tinta) }
            }
        }
        if !annuncio.isEmpty {
            Pannello(titolo: "ANNUNCIO", tinta: tinta) {
                RigaF(etichetta: "Titolo", valore: annuncio["titolo"] ?? "")
                RigaF(etichetta: "Condizioni", valore: annuncio["condizioni"] ?? "")
                RigaF(etichetta: "Categoria", valore: annuncio["categoria"] ?? "")
                if !pagato.isEmpty { RigaF(etichetta: "Pagato", valore: "\(pagato) €") }
                RigaF(etichetta: "Prezzo", valore: "lo decidi tu")
                NotaF(testo: annuncio["descrizione"] ?? "")
                TastoF(testo: "Copia e apri Vinted", icona: "doc.on.doc") {
                    UIPasteboard.general.string = [annuncio["titolo"], annuncio["descrizione"]].compactMap { $0 }.joined(separator: "\n\n")
                    pubblicati.valore += 1
                    UIApplication.shared.open(URL(string: "https://www.vinted.it/items/new")!)
                }
            }
        }
        Pannello(titolo: "VENDITA", tinta: tinta) {
            RigaF(etichetta: "Capi nell'armadio", valore: "\(totale ?? 0)")
            RigaF(etichetta: "Annunci preparati", valore: "\(pubblicati.valore)")
        }
    }

    private func scriviAnnuncio(_ capo: String) async {
        stato = "Scrivo l'annuncio…"
        guard let o = await VistaVitals.chiama(["scrivi": ["compito": "annuncio", "dati": ["capo": capo, "condizioni": condizioni, "pagato": pagato]]], attesa: 40) else { stato = "L'annuncio non è arrivato: riprova."; return }
        annuncio = o.compactMapValues { $0 as? String }
        stato = nil
    }

    // ── Conti e desideri
    @ViewBuilder private var contiVista: some View {
        let mese = conti.valore.filter { Calendar.current.isDate($0.quando, equalTo: Date(), toGranularity: .month) }
        let comprato = mese.filter { !$0.venduto }.map(\.euro).reduce(0, +), venduto = mese.filter(\.venduto).map(\.euro).reduce(0, +)
        Pannello(titolo: Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "it_IT"))).uppercased(), tinta: tinta) {
            RigaF(etichetta: "Comprato", valore: euro(comprato))
            RigaF(etichetta: "Venduto", valore: euro(venduto))
            RigaF(etichetta: "Saldo", valore: euro(venduto - comprato), stato: venduto - comprato < 0 ? .no : .ok)
            ForEach(mese.reversed()) { m in RigaF(etichetta: m.cosa, valore: (m.venduto ? "+ " : "− ") + euro(m.euro)) }
            HStack {
                TextField("", text: $nuovoMov, prompt: Text("Cosa").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                TextField("", text: $nuovoEuro, prompt: Text("€").foregroundStyle(Color.tenue)).keyboardType(.decimalPad).frame(width: 60).foregroundStyle(Color.testo)
                Button { nuovoVenduto.toggle() } label: { Text(nuovoVenduto ? "venduto" : "comprato").font(.system(size: 12, design: .monospaced)) }.foregroundStyle(tinta)
                Button {
                    guard !nuovoMov.isEmpty, let e = Double(nuovoEuro.replacingOccurrences(of: ",", with: ".")) else { return }
                    conti.valore.append(MovimentoA(cosa: nuovoMov, euro: e, venduto: nuovoVenduto)); nuovoMov = ""; nuovoEuro = ""
                } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
            }
            TastoJarvis(testo: "Leggi le mail di Vinted", icona: "envelope", tinta: tinta) {
                chiedi("Leggi le mail di Vinted di questo mese e dimmi cosa ho comprato e venduto, con gli importi, e se c'è un pacco da spedire.")
            }
        }
        Pannello(titolo: "DESIDERI", tinta: tinta) {
            ForEach(desideri.valore) { d in
                let ore = 48 - Int(Date().timeIntervalSince(d.da) / 3600)
                HStack {
                    RigaF(etichetta: d.nome, valore: ore > 0 ? "ci pensi ancora \(ore >= 24 ? "\(ore / 24 + (ore % 24 > 0 ? 1 : 0)) giorni" : "\(ore) ore")" : "lo vuoi ancora?", stato: ore > 0 ? .normale : .ok)
                    Button { togliDesiderio(d) } label: { Image(systemName: "minus.circle") }.foregroundStyle(Color.tenue).buttonStyle(.plain)
                }
            }
            HStack {
                TextField("", text: $nuovoDesiderio, prompt: Text("Stivali in pelle").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                Button { aggiungiDesiderio() } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
            }
            NotaF(testo: "Quello che vuoi comprare lo metti qui: dopo 48 ore FRIDAY ti chiede se lo vuoi ancora.")
        }
        NotaF(testo: "I conti li vede solo Bea: restano su questo iPhone.")
    }

    private func aggiungiDesiderio() {
        let n = nuovoDesiderio.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let d = DesiderioA(nome: n)
        desideri.valore.append(d); nuovoDesiderio = ""
        let c = UNMutableNotificationContent(); c.title = "Armadio"; c.body = "Sono passate 48 ore: \(n), lo vuoi ancora?"; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "desiderio.\(d.id)", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 48 * 3600, repeats: false)))
    }

    private func togliDesiderio(_ d: DesiderioA) {
        desideri.valore.removeAll { $0.id == d.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["desiderio.\(d.id)"])
    }

    private func euro(_ v: Double) -> String { v.formatted(.currency(code: "EUR").locale(Locale(identifier: "it_IT"))) }
}
#endif
