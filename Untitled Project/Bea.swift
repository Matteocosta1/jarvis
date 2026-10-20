#if os(iOS)
import SwiftUI
import UserNotifications
import MapKit

/// BEA: il reparto dedicato a Beatrice. Le cose che ama e quelle che non sopporta, le date che contano,
/// le promesse che il signore le ha fatto, le idee per sorprenderla, il suo lavoro di oggi al pilates,
/// e un tocco per chiamarla o scriverle. Si riempie anche a voce: «Jarvis, a Bea piacciono le peonie bianche».
/// Proteggerla qui vuol dire esserci: niente posizione o telefono di lei senza che sia lei a sceglierlo.
struct VistaBea: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    private let calda = Color(red: 1.0, green: 0.62, blue: 0.72)      // un filo di rosa, solo per il cuore
    @Environment(\.dismiss) private var chiudi
    @Environment(\.openURL) private var apriURL

    @AppStorage("numeroBea") private var numero = ""
    @AppStorage("nomeContattoBea") private var nomeContatto = ""
    @State private var dati: DatiBea?
    @State private var errore = false
    @State private var nuovo = ""
    @State private var tipoNuovo: TipoBea = .gusto
    @State private var giornoNuovo = Date()
    @State private var annualeNuovo = true
    @State private var conGiorno = false
    @State private var sceltaContatto = false
    @State private var pensiero: String?          // «Ti penso»: il messaggio pronto, da ritoccare e mandare
    @State private var scrivePensiero = false
    @State private var chiama112 = false
    @FocusState private var scrivendo: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fondo.ignoresSafeArea()
                RadialGradient(colors: [calda.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 420).ignoresSafeArea()
                List {
                    Section {
                        TestataScheda(titolo: "Bea", sottotitolo: sottotitolo, icona: "link", tinta: tinta)
                            .listRowBackground(Color.clear)
                        contatto.listRowBackground(Color.clear)
                    }
                    pensieri
                    if let d = dati {
                        date(d)
                        promesse(d)
                        gusti(d)
                        idee(d)
                        if !d.note.isEmpty { elenco(d.note, titolo: "DA NON DIMENTICARE", icona: "note.text") }
                        lavoro(d)
                    }
                    aggiungi
                    sicurezza
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .opacity(dati != nil || errore ? 1 : 0.25)
                .animation(.easeOut(duration: 0.4), value: dati != nil)
                if dati == nil && !errore {
                    CaricamentoHUD(titolo: "Bea", tinta: tinta).padding(.top, 120).allowsHitTesting(false)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { chiudi() }.tint(tinta) } }
            .onAppear { Suoni.schedaApre() }
            .task { await carica(); if dati != nil { Suoni.schedaPronta() } }
            .sheet(isPresented: $sceltaContatto) {
                SceltaContattoBea { c, n in
                    nomeContatto = c.nome
                    numero = n
                    sceltaContatto = false
                    PonteTelefono.condiviso.invia()          // anche l'orologio conosce il numero, per il «Ti penso»
                }
            }
            .sheet(isPresented: Binding(get: { pensiero != nil }, set: { if !$0 { pensiero = nil } })) {
                TiPenso(testo: pensiero ?? "", numero: numero) { pensiero = nil } altro: { Task { await nuovoPensiero() } }
                    .id(pensiero)                                   // «Scrivine un altro»: il testo nuovo rimpiazza il vecchio
                    .presentationDetents([.medium])
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sottotitolo: String {
        guard let d = dati else { return errore ? "non raggiungo la scheda" : "apro la sua scheda" }
        if let p = d.date.first {
            switch p.traGiorni {
            case 0: return "oggi: \(p.testo)"
            case 1: return "domani: \(p.testo)"
            default: return "\(p.testo) tra \(p.traGiorni) giorni"
            }
        }
        if !d.promesse.isEmpty { return d.promesse.count == 1 ? "una promessa da mantenere" : "\(d.promesse.count) promesse da mantenere" }
        return "prendersi cura di lei"
    }

    // MARK: Contatto

    @ViewBuilder private var contatto: some View {
        if numero.isEmpty {
            Button { sceltaContatto = true } label: {
                Label("Collega il contatto di Bea", systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .foregroundStyle(Color.fondo).background(Color.ciano2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(StileStark())
        } else {
            HStack(spacing: 10) {
                tasto("Chiama", "phone.fill") { apri("tel:\(Rubrica.pulisci(numero))") }
                tasto("Messaggio", "message.fill") { apri("sms:\(Rubrica.pulisci(numero))") }
                tasto("WhatsApp", "bubble.left.and.text.bubble.right.fill") { apri("https://wa.me/\(Rubrica.internazionale(numero))") }
            }
            Button { Task { await nuovoPensiero() } } label: {
                HStack(spacing: 8) {
                    if scrivePensiero { ProgressView().tint(Color.fondo) } else { Image(systemName: "sparkles") }
                    Text(scrivePensiero ? "JARVIS scrive…" : "Ti penso")
                }
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity).frame(height: 46)
                .foregroundStyle(Color.fondo).background(Color.ciano2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(StileStark())
            .disabled(scrivePensiero)
            Button { sceltaContatto = true } label: {
                Text("\(nomeContatto) · \(numero) · cambia").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
            }
            .buttonStyle(.plain)
        }
    }

    private func tasto(_ titolo: String, _ icona: String, _ azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            VStack(spacing: 5) {
                Image(systemName: icona).font(.system(size: 18))
                Text(titolo.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
            .foregroundStyle(tinta)
            .background(tinta.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.5), lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(StileStark())
    }

    private func apri(_ indirizzo: String) {
        guard let url = URL(string: indirizzo) else { return }
        apriURL(url)
    }

    // MARK: Pensieri: JARVIS aiuta, guardando la sua scheda

    private var pensieri: some View {
        Section {
            domanda("Cosa le scrivo adesso?", "text.bubble",
                    "Reparto Bea: aiutami a scrivere adesso un messaggio per Bea, breve e vero, con le mie parole. Guarda la sua scheda e com'è la sua giornata.")
            domanda("Un'idea per stasera", "moon.stars",
                    "Reparto Bea: proponimi due idee per stasera con Bea, fattibili, partendo da quello che le piace e da com'è andata la sua giornata.")
            domanda("Un regalo o una sorpresa", "gift",
                    "Reparto Bea: proponimi due idee regalo o sorpresa per Bea, guardando i suoi gusti, le date vicine e le idee che ho già segnato.")
            domanda("Come le sto vicino oggi?", "hands.and.sparkles",
                    "Reparto Bea: guarda la sua scheda e il suo lavoro di oggi e dimmi un gesto concreto per esserle vicino oggi.")
            domanda("Abbiamo discusso", "person.2.wave.2",
                    "Modalità confidente. Riguarda Bea: abbiamo discusso e ho bisogno di capire. Ti racconto.")
        } header: { intestazione("sparkles", "CHIEDA A JARVIS") }
    }

    private func domanda(_ titolo: String, _ icona: String, _ frase: String) -> some View {
        Button { Suoni.tocco(); chiedi(frase) } label: {
            Label(titolo, systemImage: icona).foregroundStyle(tinta)
        }
        .listRowBackground(tinta.opacity(0.05))
    }

    // MARK: Le sezioni della scheda

    @ViewBuilder private func date(_ d: DatiBea) -> some View {
        Section {
            if d.date.isEmpty {
                Text("Nessuna data. Il compleanno, il vostro anniversario: li aggiunga qui sotto o li dica a JARVIS.")
                    .font(.footnote).foregroundStyle(Color.tenue)
            }
            ForEach(d.date) { r in
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text(r.traGiorni == 0 ? "OGGI" : "\(r.traGiorni)").font(.system(size: r.traGiorni == 0 ? 13 : 20, weight: .bold, design: .monospaced))
                        if r.traGiorni > 0 { Text(r.traGiorni == 1 ? "GIORNO" : "GIORNI").font(.system(size: 7, weight: .semibold, design: .monospaced)) }
                    }
                    .foregroundStyle(r.traGiorni <= 7 ? calda : tinta)
                    .frame(width: 54)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.testo).font(.system(size: 15)).foregroundStyle(.white)
                        Text([r.quando, r.anni.map { "\($0) anni" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                    }
                }
                .listRowBackground(Color.clear)
                .swipeActions { Button(role: .destructive) { Task { await azione(["bea_elimina": r.id]) } } label: { Label("Elimina", systemImage: "trash") } }
            }
        } header: { intestazione("calendar", "LE SUE DATE") }
    }

    @ViewBuilder private func promesse(_ d: DatiBea) -> some View {
        if !d.promesse.isEmpty || !d.fatte.isEmpty {
            Section {
                ForEach(d.promesse) { r in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.raised").foregroundStyle(calda).frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.testo).font(.system(size: 15)).foregroundStyle(.white)
                            if let q = r.quando { Text("entro \(q)").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { Task { await azione(["bea_elimina": r.id]) } } label: { Label("Elimina", systemImage: "trash") }
                        Button { Task { await azione(["bea_fatto": r.id]); Suoni.pronto() } } label: { Label("Mantenuta", systemImage: "checkmark") }.tint(.green)
                    }
                }
                if !d.fatte.isEmpty {
                    Text("Mantenute di recente: \(d.fatte.prefix(4).map(\.testo).joined(separator: " · "))")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                        .listRowBackground(Color.clear)
                }
            } header: { intestazione("hand.raised", "PROMESSE · SCORRA PER SEGNARLE MANTENUTE") }
        }
    }

    @ViewBuilder private func gusti(_ d: DatiBea) -> some View {
        if !d.gusti.isEmpty || !d.nonPiace.isEmpty {
            Section {
                if !d.gusti.isEmpty { etichette(d.gusti, colore: tinta, icona: "heart.fill") }
                if !d.nonPiace.isEmpty { etichette(d.nonPiace, colore: .orange, icona: "xmark") }
            } header: { intestazione("heart", "COSA AMA · COSA NO") }
        }
    }

    private func etichette(_ voci: [DatiBea.Voce], colore: Color, icona: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(voci) { v in
                    Label(v.testo, systemImage: icona)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .foregroundStyle(colore)
                        .overlay(Capsule().stroke(colore.opacity(0.5), lineWidth: 1))
                        .contextMenu {
                            Button(role: .destructive) { Task { await azione(["bea_elimina": v.id]) } } label: { Label("Elimina", systemImage: "trash") }
                        }
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder private func idee(_ d: DatiBea) -> some View {
        if !d.idee.isEmpty || !d.regali.isEmpty {
            Section {
                ForEach(d.regali) { r in rigaIdea(r, icona: "gift") }
                ForEach(d.idee) { r in rigaIdea(r, icona: "lightbulb") }
            } header: { intestazione("gift", "IDEE E REGALI") }
        }
    }

    private func rigaIdea(_ r: DatiBea.Voce, icona: String) -> some View {
        Label(r.testo, systemImage: icona)
            .font(.system(size: 15)).foregroundStyle(.white)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { Task { await azione(["bea_elimina": r.id]) } } label: { Label("Elimina", systemImage: "trash") }
                Button { Task { await azione(["bea_fatto": r.id]); Suoni.pronto() } } label: { Label("Fatto", systemImage: "checkmark") }.tint(.green)
            }
    }

    private func elenco(_ voci: [DatiBea.Voce], titolo: String, icona: String) -> some View {
        Section {
            ForEach(voci) { v in
                Text(v.testo).font(.system(size: 15)).foregroundStyle(.white)
                    .listRowBackground(Color.clear)
                    .swipeActions { Button(role: .destructive) { Task { await azione(["bea_elimina": v.id]) } } label: { Label("Elimina", systemImage: "trash") } }
            }
        } header: { intestazione(icona, titolo) }
    }

    @ViewBuilder private func lavoro(_ d: DatiBea) -> some View {
        Section {
            if !d.lavoro.collegato {
                Text("Il gestionale del pilates non è ancora collegato a JARVIS. Quando lo collega, qui vede le lezioni di Bea di oggi.")
                    .font(.footnote).foregroundStyle(Color.tenue)
            } else if let e = d.lavoro.errore {
                Text("Non riesco a leggere il gestionale: \(e)").font(.footnote).foregroundStyle(.orange)
            } else {
                if d.lavoro.lezioni.isEmpty {
                    Text("Oggi nessuna lezione in agenda.").font(.footnote).foregroundStyle(Color.tenue)
                }
                ForEach(Array(d.lavoro.lezioni.enumerated()), id: \.offset) { _, l in
                    HStack(spacing: 12) {
                        Text(l.ora).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(tinta).frame(width: 52, alignment: .leading)
                        Text([l.cliente, l.tipo].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 14)).foregroundStyle(.white)
                        Spacer()
                        if l.fatta { Image(systemName: "checkmark").foregroundStyle(.green) }
                    }
                }
                Text("\(d.lavoro.clienti) clienti · incassato questo mese \(d.lavoro.incassato.formatted(.currency(code: "EUR")))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
            }
        } header: { intestazione("figure.pilates", "IL SUO LAVORO OGGI") }
        .listRowBackground(Color.clear)
    }

    // MARK: Aggiungere

    private var aggiungi: some View {
        Section {
            Picker("Cosa", selection: $tipoNuovo) {
                ForEach(TipoBea.allCases) { Text($0.nome).tag($0) }
            }
            .tint(tinta)
            .onChange(of: tipoNuovo) { _, t in conGiorno = t == .data }
            TextField(tipoNuovo.esempio, text: $nuovo, axis: .vertical)
                .lineLimit(1...3)
                .focused($scrivendo)
                .foregroundStyle(.white)
            if tipoNuovo == .promessa { Toggle("Con una scadenza", isOn: $conGiorno).tint(tinta) }
            if conGiorno {
                DatePicker("Giorno", selection: $giornoNuovo, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "it_IT"))
                if tipoNuovo == .data { Toggle("Ogni anno", isOn: $annualeNuovo).tint(tinta) }
            }
            Button { Task { await salvaNuovo() } } label: {
                Label("Aggiungi", systemImage: "plus.circle.fill").foregroundStyle(tinta)
            }
            .disabled(nuovo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: { intestazione("plus", "AGGIUNGI · O LO DICA A JARVIS") }
        .listRowBackground(tinta.opacity(0.05))
    }

    // MARK: Sicurezza, con lei e non su di lei

    private var sicurezza: some View {
        Section {
            Text("Proteggerla vuol dire esserci, non controllarla. Sul telefono di Bea ci sono tre strumenti che sceglie lei:")
                .font(.footnote).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
            Label("Check In: in Messaggi, nella vostra chat › + › Check In. Quando torna a casa la sera, le arriva un avviso; se non arriva, lo sa lei.", systemImage: "checkmark.message")
                .font(.footnote).foregroundStyle(.white)
            Label("Dov'è: condivide la posizione con lei solo se lo decide lei, e può toglierla quando vuole.", systemImage: "location.circle")
                .font(.footnote).foregroundStyle(.white)
            Label("SOS emergenze: in Salute › Contatti di emergenza può aggiungere lei; tenendo premuti i tasti laterali chiama il 112 e avvisa.", systemImage: "sos")
                .font(.footnote).foregroundStyle(.white)
            if !numero.isEmpty {
                Button { apri("sms:\(Rubrica.pulisci(numero))") } label: {
                    Label("Ne parlo con lei", systemImage: "message").foregroundStyle(tinta)
                }
            }
            // 112: per Bea gli strumenti ufficiali (SOS dell'iPhone e l'app del 112), per il signore la chiamata con conferma
            VStack(alignment: .leading, spacing: 8) {
                Label("EMERGENZA · 112", systemImage: "sos")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.32))
                Text("Bea: tasto laterale + volume tenuti premuti chiama il 112 e manda la sua posizione ai contatti di emergenza. Con l'app «112 Where ARE U» la centrale riceve la posizione esatta e si può scrivere in silenzio, se non si può parlare.")
                    .font(.footnote).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
                if let app = URL(string: "https://apps.apple.com/app/id888964800") {
                    ShareLink(item: app, message: Text("Amore, installa questa: è l'app ufficiale del 112, manda la tua posizione e puoi scrivere in silenzio se non puoi parlare ❤️")) {
                        Label("Manda a Bea l'app del 112", systemImage: "square.and.arrow.up").font(.footnote).foregroundStyle(tinta)
                    }
                }
                Button { chiama112 = true } label: {
                    Label("Chiama il 112", systemImage: "phone.fill").font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.32))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(red: 1.0, green: 0.27, blue: 0.32).opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 1.0, green: 0.27, blue: 0.32).opacity(0.45), lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .confirmationDialog("Chiamare il 112?", isPresented: $chiama112, titleVisibility: .visible) {
                Button("Chiama il 112", role: .destructive) { apri("tel:112") }
                Button("Annulla", role: .cancel) {}
            } message: { Text("Il numero unico di emergenza.") }
            // il Tocco d'aiuto: il comando «Aiuto Ale» sul tasto Azione del suo iPhone
            VStack(alignment: .leading, spacing: 6) {
                Label("TOCCO D'AIUTO", systemImage: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.32))
                Text("Sul suo iPhone: tasto Azione › «Aiuto Ale», oppure «Ehi Siri, Aiuto Ale». Le arriva l'allarme con la sua posizione e un messaggio. Parte solo se lo fa lei.")
                    .font(.footnote).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95))
                if let u = dati?.ultimoAiuto {
                    Text("Ultima richiesta d'aiuto: \(u)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                }
            }
            .padding(12)
            .background(Color(red: 1.0, green: 0.27, blue: 0.32).opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 1.0, green: 0.27, blue: 0.32).opacity(0.45), lineWidth: 0.8))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } header: { intestazione("shield", "LA SUA SICUREZZA") }
        .listRowBackground(Color.clear)
    }

    private func intestazione(_ icona: String, _ titolo: String) -> some View {
        Label(titolo, systemImage: icona).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
    }

    // MARK: Rete

    private func carica() async {
        guard let o = await VistaVitals.chiama(["bea": true]), o["errore"] == nil else { errore = dati == nil; return }
        errore = false
        let d = DatiBea(o)
        withAnimation(.easeOut(duration: 0.25)) { dati = d }
        await VistaBea.programmaAvvisi(d)
    }

    /// «Ti penso»: JARVIS scrive due righe nel suo stile (diverse dalle ultime mandate); le manda sempre lui.
    private func nuovoPensiero() async {
        scrivePensiero = true
        defer { scrivePensiero = false }
        Suoni.tocco()
        let ultimi = UserDefaults.standard.stringArray(forKey: "pensieriBea") ?? []
        guard let o = await VistaVitals.chiama(["bea_pensiero": true, "evita": ultimi]), let t = o["testo"] as? String, !t.isEmpty else { return }
        pensiero = t
    }

    private func azione(_ corpo: [String: Any]) async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        _ = await VistaVitals.chiama(corpo)
        await carica()
    }

    private func salvaNuovo() async {
        let t = nuovo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var voce: [String: Any] = ["tipo": tipoNuovo.rawValue, "testo": t]
        if conGiorno {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            voce["giorno"] = f.string(from: giornoNuovo)
            if tipoNuovo == .data { voce["annuale"] = annualeNuovo }
        }
        Suoni.tocco()
        _ = await VistaVitals.chiama(["bea_aggiungi": voce])
        nuovo = ""
        scrivendo = false
        await carica()
    }

    /// Gli avvisi sul telefono per le date di Bea: una settimana prima e il giorno stesso. Si rifanno a ogni apertura.
    static func programmaAvvisi(_ d: DatiBea) async {
        let centro = UNUserNotificationCenter.current()
        let vecchi = await centro.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("bea-") }
        centro.removePendingNotificationRequests(withIdentifiers: vecchi)
        let calendario = Calendar(identifier: .gregorian)
        for r in d.date {
            guard let giorno = r.data else { continue }
            let avvisi: [(String, Int, Int, String)] = [
                ("7", -7, 10, "Tra una settimana: \(r.testo). C'è tempo per pensarci bene, Sir."),
                ("0", 0, 9, "Oggi: \(r.testo)."),
            ]
            for (chiave, scarto, ora, testo) in avvisi {
                guard let quando = calendario.date(byAdding: .day, value: scarto, to: giorno),
                      let alle = calendario.date(bySettingHour: ora, minute: 0, second: 0, of: quando), alle > Date() else { continue }
                let c = UNMutableNotificationContent()
                c.title = "Bea"
                c.body = testo
                c.sound = .default
                c.userInfo = ["jarvis_testo": testo]
                let quandoC = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: alle)
                let richiesta = UNNotificationRequest(identifier: "bea-\(r.id)-\(chiave)", content: c,
                                                      trigger: UNCalendarNotificationTrigger(dateMatching: quandoC, repeats: false))
                try? await centro.add(richiesta)
            }
        }
    }
}

/// «Ti penso»: il messaggio scritto da JARVIS, da ritoccare se vuole; parte da WhatsApp o Messaggi, dove lo invia lui.
struct TiPenso: View {
    @State var testo: String
    let numero: String
    let chiudi: () -> Void
    let altro: () -> Void
    @Environment(\.openURL) private var apriURL

    init(testo: String, numero: String, chiudi: @escaping () -> Void, altro: @escaping () -> Void) {
        _testo = State(initialValue: testo)
        self.numero = numero
        self.chiudi = chiudi
        self.altro = altro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TI PENSO").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            TextField("", text: $testo, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 17))
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.ciano.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.4), lineWidth: 0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                invio("WhatsApp", "https://wa.me/\(Rubrica.internazionale(numero))?text=\(codifica(testo))")
                invio("Messaggio", "sms:\(Rubrica.pulisci(numero))&body=\(codifica(testo))")
            }
            Button { altro() } label: {
                Label("Scrivine un altro", systemImage: "arrow.clockwise").font(.system(size: 13, design: .monospaced)).foregroundStyle(Color.ciano)
            }
            .buttonStyle(.plain)
            Text("Parte quando tocca Invia nell'app: è sempre lei a mandarlo.").font(.footnote).foregroundStyle(Color.tenue)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.fondo.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func invio(_ titolo: String, _ indirizzo: String) -> some View {
        Button {
            var mandati = UserDefaults.standard.stringArray(forKey: "pensieriBea") ?? []
            mandati.insert(testo, at: 0)
            UserDefaults.standard.set(Array(mandati.prefix(12)), forKey: "pensieriBea")
            if let url = URL(string: indirizzo) { apriURL(url) }
            chiudi()
        } label: {
            Text(titolo.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity).frame(height: 46)
                .foregroundStyle(Color.fondo).background(Color.ciano2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(StileStark())
        .disabled(testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func codifica(_ t: String) -> String {
        var ammessi = CharacterSet.urlQueryAllowed
        ammessi.remove(charactersIn: "&=?+#")
        return t.addingPercentEncoding(withAllowedCharacters: ammessi) ?? ""
    }
}

/// Il Tocco d'aiuto di Bea: la richiesta arrivata dal suo iPhone.
struct AiutoBea: Identifiable {
    let id = UUID()
    let lat: Double?
    let lon: Double?
    let prova: Bool
}

/// «Bea ha bisogno di lei»: a tutto schermo, due tasti grandi. Chiamarla, e andare da lei.
struct VistaAiutoBea: View {
    let aiuto: AiutoBea
    let chiudi: () -> Void
    @AppStorage("numeroBea") private var numero = ""
    @Environment(\.openURL) private var apriURL
    @State private var pulsa = false
    @State private var indirizzo: String?          // la via dove si trova, da dire al 112 se serve
    @State private var chiama112 = false
    private let rosso = Color(red: 1.0, green: 0.27, blue: 0.32)

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [rosso.opacity(pulsa ? 0.35 : 0.15), .clear], center: .center, startRadius: 0, endRadius: 480)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsa)
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "link").font(.system(size: 54, weight: .medium)).foregroundStyle(rosso)
                    .scaleEffect(pulsa ? 1.08 : 0.94)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsa)
                Text(aiuto.prova ? "PROVA" : "BEA HA BISOGNO DI LEI")
                    .font(.system(size: 22, weight: .bold, design: .monospaced)).tracking(2)
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                Text(aiuto.lat == nil ? "La posizione non è arrivata: la chiami subito." : "Ha chiesto aiuto adesso, da qui sotto vede dov'è.")
                    .font(.system(size: 14)).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95)).multilineTextAlignment(.center)
                if let lat = aiuto.lat, let lon = aiuto.lon {
                    // dov'è adesso: la mappa con il suo punto, senza dover aprire nient'altro
                    let punto = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    Map(initialPosition: .region(MKCoordinateRegion(center: punto, latitudinalMeters: 700, longitudinalMeters: 700))) {
                        Marker("Bea", systemImage: "link", coordinate: punto).tint(rosso)
                    }
                    .frame(maxHeight: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(rosso.opacity(0.5), lineWidth: 1))
                    if let indirizzo {
                        Label(indirizzo, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Spacer()
                }
                grande("CHIAMA BEA", "phone.fill", pieno: true) {
                    if let u = URL(string: "tel:\(Rubrica.pulisci(numero))"), !numero.isEmpty { apriURL(u) }
                }
                .disabled(numero.isEmpty)
                if let lat = aiuto.lat, let lon = aiuto.lon {
                    grande("PORTAMI DA LEI", "location.fill", pieno: false) {
                        if let u = URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d") { apriURL(u) }
                    }
                }
                if numero.isEmpty {
                    Text("Colleghi il contatto di Bea nel reparto Bea per chiamarla da qui.").font(.footnote).foregroundStyle(Color.tenue)
                }
                Button { chiama112 = true } label: {
                    Label("Non risponde? Chiama il 112", systemImage: "sos").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(rosso)
                }
                .confirmationDialog("Chiamare il 112?", isPresented: $chiama112, titleVisibility: .visible) {
                    Button("Chiama il 112", role: .destructive) { if let u = URL(string: "tel:112") { apriURL(u) } }
                    Button("Annulla", role: .cancel) {}
                } message: { Text(indirizzo.map { "Bea è qui: \($0)" } ?? "Il numero unico di emergenza.") }
                Button("Chiudi") { chiudi() }.font(.system(size: 14, design: .monospaced)).foregroundStyle(Color.tenue).padding(.top, 6)
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            pulsa = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        .task {
            // la via, per dirla al 112 o per orientarsi subito
            guard let lat = aiuto.lat, let lon = aiuto.lon,
                  let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first else { return }
            indirizzo = [[p.thoroughfare, p.subThoroughfare].compactMap { $0 }.joined(separator: " "), p.locality]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    private func grande(_ titolo: String, _ icona: String, pieno: Bool, _ azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Label(titolo, systemImage: icona)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity).frame(height: 60)
                .foregroundStyle(pieno ? Color.fondo : rosso)
                .background(pieno ? rosso : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(rosso, lineWidth: 1.2))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(StileStark())
    }
}

/// Cosa si può segnare su Bea.
enum TipoBea: String, CaseIterable, Identifiable {
    case gusto, non_piace, data, promessa, idea, regalo, nota
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .gusto: return "Le piace"
        case .non_piace: return "Non le piace"
        case .data: return "Una data"
        case .promessa: return "Una promessa"
        case .idea: return "Un'idea per lei"
        case .regalo: return "Un regalo"
        case .nota: return "Da non dimenticare"
        }
    }
    var esempio: String {
        switch self {
        case .gusto: return "Le peonie bianche, il sushi di via…"
        case .non_piace: return "I posti troppo rumorosi…"
        case .data: return "Il suo compleanno, il nostro anniversario…"
        case .promessa: return "Portarla al mare a novembre…"
        case .idea: return "Colazione a sorpresa dopo la lezione…"
        case .regalo: return "Il tappetino nuovo che guardava…"
        case .nota: return "Giovedì ha la visita…"
        }
    }
}

/// La scheda di Bea, letta dal cervello.
struct DatiBea {
    struct Voce: Identifiable {
        let id: Int
        let testo: String
        let quando: String?
    }
    struct Ricorrenza: Identifiable {
        let id: Int
        let testo: String
        let traGiorni: Int
        let data: Date?
        let quando: String?
        let anni: Int?
    }
    struct Lezione {
        let ora: String
        let cliente: String?
        let tipo: String?
        let fatta: Bool
    }
    struct Lavoro {
        var collegato = false
        var errore: String?
        var lezioni: [Lezione] = []
        var clienti = 0
        var incassato = 0.0
    }

    let date: [Ricorrenza]
    let promesse: [Voce]
    let gusti: [Voce]
    let nonPiace: [Voce]
    let idee: [Voce]
    let regali: [Voce]
    let note: [Voce]
    let fatte: [Voce]
    let lavoro: Lavoro
    let ultimoAiuto: String?        // quando Bea ha chiesto aiuto l'ultima volta (le prove non contano)

    private static let leggiGiorno: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let scriviGiorno: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    init(_ o: [String: Any]) {
        func voci(_ k: String) -> [Voce] {
            (o[k] as? [[String: Any]] ?? []).compactMap { r in
                guard let id = (r["id"] as? NSNumber)?.intValue, let t = r["testo"] as? String else { return nil }
                let q = (r["giorno"] as? String).flatMap { DatiBea.leggiGiorno.date(from: $0) }.map { DatiBea.scriviGiorno.string(from: $0) }
                return Voce(id: id, testo: t, quando: q)
            }
        }
        date = (o["date"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = (r["id"] as? NSNumber)?.intValue, let t = r["testo"] as? String else { return nil }
            let giorno = (r["prossima"] as? String).flatMap { DatiBea.leggiGiorno.date(from: $0) }
            return Ricorrenza(id: id, testo: t, traGiorni: (r["tra_giorni"] as? NSNumber)?.intValue ?? 0, data: giorno,
                         quando: giorno.map { DatiBea.scriviGiorno.string(from: $0) }, anni: (r["anni"] as? NSNumber)?.intValue)
        }
        promesse = voci("promesse")
        gusti = voci("gusti")
        nonPiace = voci("non_piace")
        idee = voci("idee")
        regali = voci("regali")
        note = voci("note")
        fatte = voci("fatte")
        var l = Lavoro()
        if let w = o["lavoro"] as? [String: Any] {
            l.collegato = (w["collegato"] as? Bool) ?? false
            l.errore = w["errore"] as? String
            l.clienti = (w["clienti"] as? NSNumber)?.intValue ?? 0
            l.incassato = (w["incassato_mese"] as? NSNumber)?.doubleValue ?? 0
            l.lezioni = (w["lezioni"] as? [[String: Any]] ?? []).map {
                Lezione(ora: $0["ora"] as? String ?? "", cliente: $0["cliente"] as? String, tipo: $0["tipo"] as? String, fatta: ($0["fatta"] as? Bool) ?? false)
            }
        }
        lavoro = l
        ultimoAiuto = o["ultimo_aiuto"] as? String
    }
}

/// La scelta del contatto di Bea dalla rubrica (si apre già cercando «Bea»).
struct SceltaContattoBea: View {
    let scelto: (Contatto, String) -> Void
    @State private var tutti: [Contatto] = []
    @State private var cerca = "Bea"
    @Environment(\.dismiss) private var chiudi

    private var trovati: [Contatto] {
        let c = cerca.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? tutti : tutti.filter { $0.nome.localizedCaseInsensitiveContains(c) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(trovati) { c in
                    ForEach(Array(c.numeri.enumerated()), id: \.offset) { _, n in
                        Button { scelto(c, n.numero) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.nome).foregroundStyle(.white)
                                Text([n.etichetta, n.numero].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(Color.tenue)
                            }
                        }
                    }
                }
                if tutti.isEmpty {
                    Text("Serve il permesso di leggere i contatti.").font(.footnote).foregroundStyle(Color.tenue)
                }
            }
            .searchable(text: $cerca, prompt: "Cerchi Bea nella rubrica")
            .navigationTitle("Il contatto di Bea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { chiudi() }.tint(Color.ciano) } }
            .task { tutti = await Rubrica.tutti() }
        }
        .preferredColorScheme(.dark)
    }
}
#endif
