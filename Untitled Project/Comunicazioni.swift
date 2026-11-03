#if os(iOS)
import SwiftUI
import Contacts
import UIKit

// MARK: - La rubrica, condivisa da Messaggi e Telefono

nonisolated struct Contatto: Identifiable, Hashable, Sendable {
    let id: String
    let nome: String
    let numeri: [(etichetta: String, numero: String)]
    var iniziale: String { String(nome.prefix(1)).uppercased() }
    var primoNumero: String? { numeri.first?.numero }

    static func == (a: Contatto, b: Contatto) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
enum Rubrica {
    private static let negozio = CNContactStore()
    private static var cache: [Contatto] = []

    static func autorizza() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            negozio.requestAccess(for: .contacts) { @Sendable ok, _ in c.resume(returning: ok) }
        }
    }

    /// Tutti i contatti con almeno un numero, in ordine alfabetico (letti una volta, poi dalla cache).
    static func tutti() async -> [Contatto] {
        if !cache.isEmpty { return cache }
        guard await autorizza() else { return [] }
        let chiavi = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let richiesta = CNContactFetchRequest(keysToFetch: chiavi)
        richiesta.sortOrder = .givenName
        var out: [Contatto] = []
        try? negozio.enumerateContacts(with: richiesta) { c, _ in
            guard !c.phoneNumbers.isEmpty else { return }
            var nome = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            if nome.isEmpty { nome = c.nickname.isEmpty ? c.organizationName : c.nickname }
            guard !nome.isEmpty else { return }
            let numeri = c.phoneNumbers.map { n -> (String, String) in
                (n.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "", n.value.stringValue)
            }
            out.append(Contatto(id: c.identifier, nome: nome, numeri: numeri))
        }
        cache = out
        return out
    }

    /// Numero pulito per tel:, sms: e WhatsApp.
    static func pulisci(_ numero: String) -> String {
        var n = numero.filter { "+0123456789".contains($0) }
        if n.hasPrefix("00") { n = "+" + n.dropFirst(2) }
        return n
    }

    /// Il numero in formato internazionale per WhatsApp (senza +; i numeri italiani senza prefisso prendono 39).
    static func internazionale(_ numero: String) -> String {
        let n = pulisci(numero)
        if n.hasPrefix("+") { return String(n.dropFirst()) }
        return (n.hasPrefix("3") && n.count == 10) || n.hasPrefix("0") ? "39" + n : n
    }
}

/// Le chiamate e i messaggi fatti da JARVIS, ricordati sul telefono (iOS non lascia leggere il registro del sistema).
nonisolated struct VoceRegistro: Codable, Identifiable, Sendable {
    var id = UUID()
    let nome: String
    let numero: String
    let quando: Date
    let tipo: String        // "chiamata", "imessage", "whatsapp"
    var testo: String? = nil
}

enum Registro {
    static func leggi(_ chiave: String) -> [VoceRegistro] {
        guard let d = UserDefaults.standard.data(forKey: chiave) else { return [] }
        return (try? JSONDecoder().decode([VoceRegistro].self, from: d)) ?? []
    }
    static func aggiungi(_ v: VoceRegistro, a chiave: String) {
        var voci = leggi(chiave)
        voci.insert(v, at: 0)
        if let d = try? JSONEncoder().encode(Array(voci.prefix(100))) { UserDefaults.standard.set(d, forKey: chiave) }
    }
    static func svuota(_ chiave: String) { UserDefaults.standard.removeObject(forKey: chiave) }
}

/// La riga di un contatto, con l'iniziale nel cerchio.
struct RigaContatto: View {
    let c: Contatto
    var sotto: String? = nil
    let tinta: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tinta.opacity(0.18))
                Text(c.iniziale).font(.system(size: 15, weight: .bold)).foregroundStyle(tinta)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.nome).font(.system(size: 15, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text(sotto ?? c.primoNumero ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue).lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - MESSAGGI: si detta a voce, si manda su iMessage o WhatsApp

struct VistaMessaggi: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    enum Canale: String, CaseIterable, Identifiable { case imessage = "iMessage", whatsapp = "WhatsApp"; var id: String { rawValue } }

    @StateObject private var dettatura = Wiretap()
    @State private var contatti: [Contatto] = []
    @State private var cerca = ""
    @State private var scelto: Contatto?
    @State private var numeroScelto: String?
    @AppStorage("messaggiCanale") private var canale: Canale = .imessage
    @State private var testo = ""
    @State private var registro: [VoceRegistro] = Registro.leggi("registroMessaggi")
    @State private var esito: String?
    @State private var caricato = false
    @FocusState private var scrivendo: Bool

    var body: some View {
        CorniceScheda(titolo: "Messaggi", sottotitolo: scelto.map { "a \($0.nome) · \(canale.rawValue)" } ?? "scelga a chi scrivere", icona: "message", tinta: tinta, pronto: caricato) {
            if let s = scelto {
                destinatario(s)
                dettatore
                canali
                TastoJarvis(testo: "Invia su \(canale.rawValue)", icona: "paperplane.fill", tinta: tinta) { invia() }
                    .disabled(testo.trimmingCharacters(in: .whitespaces).isEmpty || numeroScelto == nil)
                    .opacity(testo.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                if let esito { Text(esito).font(.footnote).foregroundStyle(tinta) }
            } else {
                rubrica
            }
            if !registro.isEmpty && scelto == nil {
                Pannello(titolo: "ULTIMI MESSAGGI DI JARVIS", tinta: tinta) {
                    ForEach(registro.prefix(8)) { v in
                        Button { riprendi(v) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: v.tipo == "whatsapp" ? "phone.bubble" : "message").foregroundStyle(tinta).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.nome).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                    Text(v.testo ?? "").font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(1)
                                }
                                Spacer()
                                Text(v.quando.formatted(date: .numeric, time: .shortened)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button(role: .destructive) { Registro.svuota("registroMessaggi"); registro = [] } label: { Label("Svuota", systemImage: "trash").font(.footnote) }.tint(.red)
                }
            }
        }
        .task {
            contatti = await Rubrica.tutti()
            caricato = true
        }
        .onDisappear { dettatura.ferma() }
    }

    private var filtrati: [Contatto] {
        let c = cerca.trimmingCharacters(in: .whitespaces).lowercased()
        return c.isEmpty ? contatti : contatti.filter { $0.nome.lowercased().contains(c) || $0.numeri.contains { $0.numero.contains(c) } }
    }

    @ViewBuilder private var rubrica: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(tinta)
            TextField("Cerchi un contatto", text: $cerca).foregroundStyle(.white).focused($scrivendo)
            if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
        }
        .padding(12).background(tinta.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
        TastoJarvis(testo: "Detti a JARVIS: «scrivi a Marco…»", icona: "waveform", tinta: tinta) { chiedi("Jarvis, voglio mandare un messaggio: dimmi tu a chi e cosa, poi lo mandi.") }
        if contatti.isEmpty && caricato {
            Text("Rubrica vuota o non autorizzata: Impostazioni › JARVIS › Contatti.").font(.footnote).foregroundStyle(Color.tenue)
        }
        ForEach(filtrati.prefix(cerca.isEmpty ? 40 : 60)) { c in
            Button { scegli(c) } label: { RigaContatto(c: c, tinta: tinta) }.buttonStyle(.plain)
            Divider().overlay(tinta.opacity(0.12))
        }
    }

    private func destinatario(_ s: Contatto) -> some View {
        Pannello(tinta: tinta) {
            HStack {
                RigaContatto(c: s, sotto: numeroScelto, tinta: tinta)
                Button { Suoni.tocco(); dettatura.ferma(); scelto = nil; testo = ""; esito = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.tenue)
                }
            }
            if s.numeri.count > 1 {
                Picker("Numero", selection: Binding(get: { numeroScelto ?? "" }, set: { numeroScelto = $0 })) {
                    ForEach(s.numeri, id: \.numero) { n in Text("\(n.etichetta) \(n.numero)").tag(n.numero) }
                }
                .pickerStyle(.menu).tint(tinta)
            }
        }
    }

    /// Dettatura: tocchi il microfono, parli, il testo compare; si può correggere a mano.
    private var dettatore: some View {
        Pannello(titolo: dettatura.attivo ? "LA ASCOLTO…" : "IL MESSAGGIO", tinta: tinta) {
            TextEditor(text: $testo)
                .scrollContentBackground(.hidden)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .frame(minHeight: 90)
                .focused($scrivendo)
                .overlay(alignment: .topLeading) {
                    if testo.isEmpty && !dettatura.attivo {
                        Text("Tocchi il microfono e detti, oppure scriva qui.").font(.system(size: 15)).foregroundStyle(Color.tenue).padding(.top, 8).padding(.leading, 4).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 12) {
                Button {
                    if dettatura.attivo { fermaDettatura() } else { Task { await avviaDettatura() } }
                } label: {
                    ZStack {
                        Circle().fill(dettatura.attivo ? Color.red : tinta).frame(width: 58, height: 58)
                            .shadow(color: (dettatura.attivo ? Color.red : tinta).opacity(0.6), radius: dettatura.attivo ? 14 : 6)
                        Image(systemName: dettatura.attivo ? "stop.fill" : "mic.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.fondo)
                    }
                }
                .buttonStyle(StileStark())
                if dettatura.attivo {
                    OndaWiretap(livello: dettatura.livello, attivo: true).frame(height: 40)
                } else {
                    Text(testo.isEmpty ? "Dettatura sul telefono, in italiano" : "\(testo.count) caratteri").font(.system(size: 11)).foregroundStyle(Color.tenue)
                    Spacer()
                    if !testo.isEmpty { Button { testo = ""; Suoni.tocco() } label: { Text("Cancella").font(.system(size: 12)) }.tint(tinta) }
                }
            }
        }
        .onChange(of: dettatura.testo) { _, nuovo in if dettatura.attivo { testo = (base + " " + nuovo).trimmingCharacters(in: .whitespaces) } }
    }

    @State private var base = ""

    private var canali: some View {
        HStack(spacing: 8) {
            ForEach(Canale.allCases) { c in
                Button { Suoni.tocco(); canale = c } label: {
                    Label(c.rawValue, systemImage: c == .imessage ? "message.fill" : "phone.bubble.fill")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(canale == c ? Color.fondo : tinta)
                        .background(canale == c ? tinta : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scegli(_ c: Contatto) {
        Suoni.tocco()
        scrivendo = false
        scelto = c
        numeroScelto = c.primoNumero
        esito = nil
    }

    private func avviaDettatura() async {
        scrivendo = false
        base = testo
        Suoni.ascolto()
        await dettatura.avvia()
    }

    private func fermaDettatura() {
        dettatura.ferma()
        testo = (base + " " + dettatura.testo).trimmingCharacters(in: .whitespaces)
        Suoni.pronto()
    }

    private func riprendi(_ v: VoceRegistro) {
        if let c = contatti.first(where: { $0.nome == v.nome }) { scegli(c) } else {
            scegli(Contatto(id: v.numero, nome: v.nome, numeri: [("", v.numero)]))
        }
        canale = v.tipo == "whatsapp" ? .whatsapp : .imessage
    }

    /// iMessage/SMS: il Comando rapido «JARVIS invia» lo manda senza conferma. WhatsApp: si apre con il testo pronto, l'invio è suo.
    private func invia() {
        guard let s = scelto, let numero = numeroScelto else { return }
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        dettatura.ferma()
        let url: URL?
        switch canale {
        case .imessage:
            let dati = try? JSONSerialization.data(withJSONObject: ["numero": Rubrica.pulisci(numero), "testo": t])
            let ingresso = Strumenti.codifica(String(decoding: dati ?? Data(), as: UTF8.self))
            url = URL(string: "shortcuts://run-shortcut?name=\(Strumenti.codifica(Strumenti.comandoInvio))&input=text&text=\(ingresso)")
        case .whatsapp:
            url = URL(string: "https://wa.me/\(Rubrica.internazionale(numero))?text=\(Strumenti.codifica(t))")
        }
        guard let url else { esito = "Non riesco a preparare il messaggio."; return }
        Suoni.pronto()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Registro.aggiungi(VoceRegistro(nome: s.nome, numero: numero, quando: Date(), tipo: canale == .whatsapp ? "whatsapp" : "imessage", testo: t), a: "registroMessaggi")
        registro = Registro.leggi("registroMessaggi")
        esito = canale == .imessage ? "Inviato con il Comando rapido «\(Strumenti.comandoInvio)»." : "WhatsApp si apre con il messaggio pronto: tocchi Invia."
        UIApplication.shared.open(url)
        testo = ""
    }
}

// MARK: - TELEFONO: tastiera, rubrica, chiamate di JARVIS

struct VistaTelefono: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    enum Pagina: String, CaseIterable, Identifiable { case tastiera = "Tastiera", rubrica = "Rubrica", recenti = "Recenti"; var id: String { rawValue } }

    @State private var pagina: Pagina = .tastiera              // build 22: i PROTOCOLLI non stanno più qui, ma nella tendina dall'alto
    @State private var numero = ""
    @State private var contatti: [Contatto] = []
    @State private var cerca = ""
    @State private var registro: [VoceRegistro] = Registro.leggi("registroChiamate")
    @State private var caricato = false
    @State private var daChiamare: (String, String)?

    var body: some View {
        CorniceScheda(titolo: "Telefono", sottotitolo: pagina.rawValue.lowercased(), icona: "phone", tinta: tinta, pronto: caricato) {
            Picker("Pagina", selection: $pagina) { ForEach(Pagina.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            switch pagina {
            case .tastiera: tastiera
            case .rubrica: rubrica
            case .recenti: recenti
            }
            Text("La chiamata parte dall'app Telefono: iOS chiede un tocco di conferma, e riattacca lei da lì. Dica anche «Jarvis, chiama Marco».")
                .font(.system(size: 11)).foregroundStyle(Color.tenue)
        }
        .task { contatti = await Rubrica.tutti(); caricato = true }
        .confirmationDialog(daChiamare.map { "Chiamo \($0.0)?" } ?? "", isPresented: Binding(get: { daChiamare != nil }, set: { if !$0 { daChiamare = nil } }), titleVisibility: .visible) {
            Button("Chiama") { if let d = daChiamare { chiama(nome: d.0, numero: d.1) } }
            Button("Annulla", role: .cancel) {}
        }
    }

    private var contattoDelNumero: Contatto? {
        let n = Rubrica.pulisci(numero)
        guard n.count >= 6 else { return nil }
        return contatti.first { $0.numeri.contains { Rubrica.pulisci($0.numero).hasSuffix(n.suffix(9)) } }
    }

    @ViewBuilder private var tastiera: some View {
        VStack(spacing: 6) {
            Text(numero.isEmpty ? " " : numero)
                .font(.system(size: 34, weight: .light, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.5).lineLimit(1).frame(maxWidth: .infinity).frame(height: 46)
            Text(contattoDelNumero?.nome ?? " ").font(.system(size: 13)).foregroundStyle(tinta)
        }
        let tasti = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
        let lettere = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ", "0": "+"]
        VStack(spacing: 10) {
            ForEach(tasti, id: \.self) { riga in
                HStack(spacing: 18) {
                    ForEach(riga, id: \.self) { t in
                        Button { premi(t) } label: {
                            VStack(spacing: 0) {
                                Text(t).font(.system(size: 28, weight: .light, design: .rounded))
                                Text(lettere[t] ?? " ").font(.system(size: 8, weight: .bold)).tracking(1.5)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(tinta.opacity(0.1))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(tinta.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(StileStark())
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in if t == "0" { numero += "+"; Suoni.tocco() } })
                    }
                }
            }
            HStack(spacing: 18) {
                Color.clear.frame(width: 74, height: 74)
                Button { if !numero.isEmpty { daChiamare = (contattoDelNumero?.nome ?? numero, numero) } } label: {
                    Image(systemName: "phone.fill").font(.system(size: 28)).foregroundStyle(.white)
                        .frame(width: 74, height: 74).background(Color(red: 0.2, green: 0.75, blue: 0.4)).clipShape(Circle())
                        .shadow(color: Color.green.opacity(0.4), radius: 8)
                }
                .buttonStyle(StileStark()).disabled(numero.isEmpty).opacity(numero.isEmpty ? 0.4 : 1)
                .accessibilityLabel("Chiama")
                Button { if !numero.isEmpty { numero.removeLast(); Suoni.tocco() } } label: {
                    Image(systemName: "delete.left").font(.system(size: 22)).foregroundStyle(tinta).frame(width: 74, height: 74)
                }
                .buttonStyle(StileStark())
                .accessibilityLabel("Cancella")
                .accessibilityHint("Tenga premuto per cancellare tutto il numero")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in numero = ""; Suoni.tocco() })
                .opacity(numero.isEmpty ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func premi(_ t: String) {
        Suoni.tocco()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        numero += t
    }

    private var filtrati: [Contatto] {
        let c = cerca.trimmingCharacters(in: .whitespaces).lowercased()
        return c.isEmpty ? contatti : contatti.filter { $0.nome.lowercased().contains(c) || $0.numeri.contains { $0.numero.contains(c) } }
    }

    @ViewBuilder private var rubrica: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(tinta)
            TextField("Cerchi un contatto", text: $cerca).foregroundStyle(.white)
            if !cerca.isEmpty { Button { cerca = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
        }
        .padding(12).background(tinta.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
        if contatti.isEmpty && caricato {
            Text("Rubrica vuota o non autorizzata: Impostazioni › JARVIS › Contatti.").font(.footnote).foregroundStyle(Color.tenue)
        }
        ForEach(filtrati.prefix(cerca.isEmpty ? 60 : 80)) { c in
            HStack {
                RigaContatto(c: c, tinta: tinta)
                Button { daChiamare = (c.nome, c.primoNumero ?? "") } label: {
                    Image(systemName: "phone.fill").foregroundStyle(Color(red: 0.2, green: 0.75, blue: 0.4)).frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chiama \(c.nome)")
            }
            .contextMenu {
                ForEach(c.numeri, id: \.numero) { n in Button("Chiama \(n.etichetta) \(n.numero)") { daChiamare = (c.nome, n.numero) } }
            }
            Divider().overlay(tinta.opacity(0.12))
        }
    }

    @ViewBuilder private var recenti: some View {
        if registro.isEmpty {
            Text("Nessuna chiamata fatta da JARVIS. Il registro dell'app Telefono resta nell'app Telefono: iOS non lo condivide.")
                .font(.footnote).foregroundStyle(Color.tenue)
        }
        ForEach(registro) { v in
            Button { daChiamare = (v.nome, v.numero) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.arrow.up.right").foregroundStyle(tinta).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.nome).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                        Text(v.numero).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue)
                    }
                    Spacer()
                    Text(v.quando.formatted(date: .numeric, time: .shortened)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                }
            }
            .buttonStyle(.plain)
            Divider().overlay(tinta.opacity(0.12))
        }
        if !registro.isEmpty {
            Button(role: .destructive) { Registro.svuota("registroChiamate"); registro = [] } label: { Label("Svuota", systemImage: "trash").font(.footnote) }.tint(.red)
        }
    }

    private func chiama(nome: String, numero n: String) {
        let pulito = Rubrica.pulisci(n)
        guard !pulito.isEmpty, let url = URL(string: "tel://\(pulito)") else { return }
        Suoni.pronto()
        Registro.aggiungi(VoceRegistro(nome: nome, numero: n, quando: Date(), tipo: "chiamata"), a: "registroChiamate")
        registro = Registro.leggi("registroChiamate")
        UIApplication.shared.open(url)
    }
}
#endif
