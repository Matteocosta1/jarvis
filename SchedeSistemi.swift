#if os(iOS)
import SwiftUI
import Charts
import PhotosUI
import UniformTypeIdentifiers

// MARK: - SISTEMI: GitHub, Supabase, Archivio
// Le tre schede del reparto tecnico: il cantiere (GitHub), la sala macchine (Supabase) e il disco rigido nel cloud (Archivio).
// Tutte parlano con il cervello (che tiene le chiavi) e passano la parola a JARVIS con un tasto.

/// Un link si può presentare in un foglio (per condividere un file dell'Archivio).
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Un dizionario letto con tolleranza: il cervello risponde in JSON e qui si prende ciò che serve.
nonisolated struct Voce {
    let d: [String: Any]
    init(_ d: [String: Any]) { self.d = d }
    func s(_ k: String) -> String {
        if let v = d[k] as? String { return v }
        if let v = d[k] as? NSNumber { return v.stringValue }
        return ""
    }
    func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? Int(s(k)) ?? 0 }
    func b(_ k: String) -> Bool { (d[k] as? Bool) ?? false }
    func lista(_ k: String) -> [Voce] { (d[k] as? [[String: Any]] ?? []).map(Voce.init) }
    func voce(_ k: String) -> Voce? { (d[k] as? [String: Any]).map(Voce.init) }
    func stringhe(_ k: String) -> [String] { d[k] as? [String] ?? [] }
}

// MARK: - GITHUB

struct VistaGitHub: View {
    let chiedi: (String) -> Void
    let apri: (URL) -> Void
    private let tinta = Color.ciano

    @State private var pagina: Voce?
    @State private var errore: String?
    @State private var repoScelto: String?
    @State private var dettaglio: Voce?
    @State private var caricoDettaglio = false
    @State private var titoloIssue = ""
    @StateObject private var dettatura = Wiretap()
    @State private var baseIssue = ""
    @State private var dettagliOlo: [String: Voce] = [:]          // 9 nov: i primi repository per l'ologramma (commit e 14 giorni)

    var body: some View {
        CorniceScheda(titolo: "GitHub", sottotitolo: sottotitolo, icona: "chevron.left.forwardslash.chevron.right", tinta: tinta, pronto: pagina != nil || errore != nil) {
            if let errore {
                Pannello(tinta: tinta) { Text(errore).font(.footnote).foregroundStyle(.orange) }
            } else if let pagina {
                // 9 nov (build 19, il signore: «falli tutti J»): in testa l'ologramma con le prove EXPO, ATOMO, PULSAR, come il mockup
                OlogrammaGithubProve(dati: datiOlo(pagina)).corniceOlo(tinta)
                if let repoScelto {
                    tastoIndietro(repoScelto)
                    if let dettaglio { vistaDettaglio(dettaglio) }
                    else if caricoDettaglio { CaricamentoHUD(titolo: repoScelto, tinta: tinta).padding(.vertical, 20) }
                } else {
                    HStack(spacing: 10) {
                        TastoJarvis(testo: "A che punto siamo?", icona: "waveform", tinta: tinta) { chiedi("A che punto sono i miei progetti su GitHub? Dimmi in poche frasi dove si è lavorato di recente e se c'è qualcosa di aperto.") }
                        TastoJarvis(testo: "Qualcosa di rotto?", icona: "exclamationmark.triangle", tinta: tinta) { chiedi("C'è qualcosa di rotto o di aperto nei miei repository GitHub? Issue e pull request che aspettano.") }
                    }
                    let repository = pagina.lista("repository")
                    if repository.isEmpty {
                        Pannello(tinta: tinta) { Text("Nessun repository visibile con questo token, Sir.").font(.footnote).foregroundStyle(Color.tenue) }
                    }
                    ForEach(Array(repository.enumerated()), id: \.offset) { _, r in
                        Button {
                            Suoni.tocco()
                            repoScelto = r.s("nome")
                            Task { await caricaDettaglio(r.s("nome")) }
                        } label: { rigaRepo(r) }
                        .buttonStyle(StileStark())
                    }
                }
            }
        }
        .task { await carica() }
        .onDisappear { dettatura.ferma() }
        .onChange(of: dettatura.testo) { _, nuovo in if dettatura.attivo { titoloIssue = (baseIssue + " " + nuovo).trimmingCharacters(in: .whitespaces) } }
        .sulloSchermo(testoSchermo)
    }

    /// 8 nov notte: cosa vede JARVIS di GitHub (il repository aperto e il suo dettaglio, la issue che sta scrivendo).
    private var testoSchermo: String {
        Schermo.unisci("GitHub", [repoScelto.map { "repository aperto: \($0)" } ?? "nessun repository aperto",
                                 dettaglio.map { "dettaglio a schermo: " + Schermo.esito($0.d, massimo: 1200) },
                                 Schermo.campo("titolo della issue che sta scrivendo (non ancora aperta)", titoloIssue),
                                 errore.map { "errore: \($0)" }])
    }

    private var sottotitolo: String {
        if let repoScelto { return repoScelto }
        if let pagina { let n = pagina.lista("repository").count; return n == 1 ? "1 repository" : "\(n) repository" }
        return "apro il cantiere"
    }

    private func rigaRepo(_ r: Voce) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: r.b("privato") ? "lock" : "shippingbox")
                .font(.system(size: 16)).foregroundStyle(tinta).frame(width: 36, height: 36)
                .background(tinta.opacity(0.1)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(r.s("nome")).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text(r.s("da")).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                }
                if let u = r.voce("ultimo_commit"), !u.s("messaggio").isEmpty {
                    Text(u.s("messaggio")).font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(2)
                } else if !r.s("descrizione").isEmpty {
                    Text(r.s("descrizione")).font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(2)
                }
                HStack(spacing: 10) {
                    if !r.s("linguaggio").isEmpty { Text(r.s("linguaggio")).font(.system(size: 10, design: .monospaced)).foregroundStyle(tinta) }
                    if r.n("issue_aperte") > 0 { Text("\(r.n("issue_aperte")) issue").font(.system(size: 10, design: .monospaced)).foregroundStyle(.orange) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinta.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.2), lineWidth: 1))
    }

    private func tastoIndietro(_ nome: String) -> some View {
        Button {
            Suoni.tocco()
            repoScelto = nil; dettaglio = nil
        } label: {
            Label("Tutti i repository", systemImage: "chevron.left")
                .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
        }
        .buttonStyle(StileStark())
    }

    @ViewBuilder private func vistaDettaglio(_ d: Voce) -> some View {
        let r = d.voce("repository") ?? Voce([:])
        let nome = r.s("nome")
        HStack(spacing: 10) {
            Valore(titolo: "COMMIT", valore: "\(d.lista("commit").count)", sotto: "ultimo \(r.s("da"))", tinta: tinta)
            Valore(titolo: "ISSUE", valore: "\(d.lista("issue").count)", sotto: "aperte", tinta: tinta)
            Valore(titolo: "PR", valore: "\(d.lista("pull_request").count)", sotto: "in attesa", tinta: tinta)
        }
        let attivita = d.lista("attivita")
        if !attivita.isEmpty {
            Pannello(titolo: "ATTIVITÀ · 30 GIORNI", tinta: tinta) {
                let totale = attivita.reduce(0) { $0 + $1.n("commit") }
                Chart(Array(attivita.enumerated()), id: \.offset) { _, g in
                    BarMark(x: .value("Giorno", g.s("giorno")), y: .value("Commit", g.n("commit")))
                        .foregroundStyle(g.n("commit") > 0 ? tinta : tinta.opacity(0.12))
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 54)
                HStack {
                    Text("\(totale) commit").font(.system(size: 10, design: .monospaced)).foregroundStyle(tinta)
                    Spacer()
                    Text("30 giorni fa → oggi").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                }
            }
        }
        HStack(spacing: 10) {
            TastoJarvis(testo: "Raccontami", icona: "waveform", tinta: tinta) { chiedi("Raccontami gli ultimi commit del repository \(nome): cosa è cambiato, in poche frasi.") }
            TastoJarvis(testo: "Il README", icona: "doc.text", tinta: tinta) { chiedi("Leggi il README del repository \(nome) e spiegami in tre frasi cosa fa il progetto.") }
        }
        if let u = URL(string: r.s("url")), !r.s("url").isEmpty {
            Button { Suoni.tocco(); apri(u) } label: {
                Label("Apri su GitHub", systemImage: "safari")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .foregroundStyle(tinta)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(StileStark())
        }
        Pannello(titolo: dettatura.attivo ? "LA ASCOLTO…" : "NUOVA ISSUE", tinta: tinta) {
            HStack(spacing: 10) {
                TextField("Titolo del problema o dell'idea, o lo detti", text: $titoloIssue)
                    .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.white)
                    .padding(10).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    Suoni.tocco()
                    if dettatura.attivo { dettatura.ferma(); Suoni.pronto() }
                    else { baseIssue = titoloIssue; Suoni.ascolto(); Task { await dettatura.avvia() } }
                } label: {
                    ZStack {
                        Circle().fill(dettatura.attivo ? Color.red : tinta).frame(width: 42, height: 42)
                            .shadow(color: (dettatura.attivo ? Color.red : tinta).opacity(0.6), radius: dettatura.attivo ? 12 : 5)
                        Image(systemName: dettatura.attivo ? "stop.fill" : "mic.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.fondo)
                    }
                }
                .buttonStyle(StileStark())
            }
            TastoJarvis(testo: "Apri la issue", icona: "plus.circle", tinta: tinta) {
                let t = titoloIssue.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                dettatura.ferma()
                titoloIssue = ""
                chiedi("Apri una issue sul repository \(nome) con questo titolo: \(t). Nel corpo scrivi due righe di contesto sensate.")
            }
            .opacity(titoloIssue.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        let commit = d.lista("commit")
        if !commit.isEmpty {
            Pannello(titolo: "ULTIMI COMMIT", tinta: tinta) {
                Text("Tocchi un commit: JARVIS le racconta cosa è cambiato.").font(.system(size: 10)).foregroundStyle(Color.tenue)
                ForEach(Array(commit.enumerated()), id: \.offset) { _, c in
                    Button {
                        Suoni.tocco()
                        chiedi("Raccontami il commit \(c.s("sha")) del repository \(nome): cosa è cambiato, file per file, in due o tre frasi.")
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(c.s("sha")).font(.system(size: 10, design: .monospaced)).foregroundStyle(tinta).frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.s("messaggio")).font(.system(size: 13)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                                Text("\(c.s("autore")) · \(c.s("da"))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "waveform").font(.system(size: 11)).foregroundStyle(Color.tenue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(StileStark())
                }
            }
        }
        let issue = d.lista("issue"), pr = d.lista("pull_request")
        if !issue.isEmpty || !pr.isEmpty {
            Pannello(titolo: "ISSUE E PULL REQUEST", tinta: tinta) {
                ForEach(Array((issue + pr).enumerated()), id: \.offset) { _, i in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: i.s("stato") == "open" ? "circle" : "checkmark.circle").font(.system(size: 12)).foregroundStyle(i.s("stato") == "open" ? .orange : .green).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(i.n("numero")) \(i.s("titolo"))").font(.system(size: 13)).foregroundStyle(.white).lineLimit(2)
                            HStack(spacing: 6) {
                                ForEach(i.stringhe("etichette"), id: \.self) { e in
                                    Text(e).font(.system(size: 9, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(tinta.opacity(0.15)).clipShape(Capsule()).foregroundStyle(tinta)
                                }
                                Text(i.s("aggiornata")).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                            }
                        }
                    }
                }
            }
        }
        if !d.s("readme").isEmpty {
            Pannello(titolo: "README", tinta: tinta) {
                Text(d.s("readme")).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue).lineLimit(18)
            }
        }
    }

    private func carica() async {
        guard let o = await VistaVitals.chiama(["github": true]) else { errore = "Non raggiungo il cervello, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        pagina = Voce(o)
        // poi, senza fretta, i dettagli dei primi tre repository per l'ologramma (gli ultimi commit e l'attività)
        for r in Voce(o).lista("repository").prefix(3) {
            let nome = r.s("nome")
            if let d = await VistaVitals.chiama(["github": true, "repo": nome]), d["errore"] == nil { dettagliOlo[nome] = Voce(d) }
        }
    }

    /// I repository per l'ologramma: nome, da quando, linguaggio, gli ultimi commit e i commit degli ultimi 14 giorni.
    private func datiOlo(_ p: Voce) -> DatiGithubOlo {
        DatiGithubOlo(repo: p.lista("repository").map { r in
            let d = dettagliOlo[r.s("nome")]
            var commit: [String] = d?.lista("commit").map { $0.s("messaggio") } ?? []
            if commit.isEmpty, let u = r.voce("ultimo_commit"), !u.s("messaggio").isEmpty { commit = [u.s("messaggio")] }
            let att = d?.lista("attivita").map { $0.n("commit") } ?? []
            let giorni: [Int] = att.count >= 14 ? Array(att.suffix(14)) : Array(repeating: 0, count: 14 - att.count) + att
            return RepoOlo(nome: r.s("nome"), da: r.s("da"), lingua: r.s("linguaggio"), commit: commit.map { String($0.split(separator: "\n").first ?? "") }, giorni: giorni)
        })
    }

    private func caricaDettaglio(_ nome: String) async {
        caricoDettaglio = true; dettaglio = nil
        defer { caricoDettaglio = false }
        guard let o = await VistaVitals.chiama(["github": true, "repo": nome]), o["errore"] == nil else { repoScelto = nil; return }
        dettaglio = Voce(o)
    }
}

// MARK: - SUPABASE

struct VistaSupabase: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano

    @State private var stato: Voce?
    @State private var errore: String?
    @State private var ore = 24
    @State private var consumi: Voce?
    @State private var memoria: [Voce] = []
    @State private var mostraMemoria = false
    @State private var battito: Voce?

    var body: some View {
        CorniceScheda(titolo: "Supabase", sottotitolo: stato.map { "\($0.voce("progetto")?.s("nome") ?? "") · \($0.voce("progetto")?.s("stato") ?? "")".lowercased() } ?? "entro in sala macchine",
                      icona: "cylinder.split.1x2", tinta: tinta, pronto: stato != nil || errore != nil) {
            if let errore {
                Pannello(tinta: tinta) { Text(errore).font(.footnote).foregroundStyle(.orange) }
            } else if let stato {
                // 9 nov (build 19): in testa l'ologramma con le prove REATTORE, RETE, BATTITO, come il mockup
                OlogrammaSupabaseProve(dati: datiOlo(stato)).corniceOlo(tinta)
                let log = stato.voce("log")
                let richieste = log?.lista("richieste") ?? [], console = log?.lista("console") ?? []
                let problemi = richieste.count + console.count
                HStack(spacing: 10) {
                    Valore(titolo: "DATABASE", valore: "\(stato.s("database_mb")) MB", sotto: "\(stato.n("righe_totali")) righe", tinta: tinta)
                    let storageMB = stato.lista("storage").reduce(0.0) { $0 + (Double($1.s("mb")) ?? 0) }
                    Valore(titolo: "STORAGE", valore: String(format: "%.0f MB", storageMB),
                           sotto: "\(stato.lista("storage").reduce(0) { $0 + $1.n("file") }) file", tinta: tinta)
                    Valore(titolo: "ERRORI", valore: "\(problemi)", sotto: "ultime \(ore) ore", tinta: problemi > 0 ? .red : .green)
                }
                if let battito { pannelloBattito(battito) }
                HStack(spacing: 10) {
                    TastoJarvis(testo: "Come sta?", icona: "waveform", tinta: tinta) { chiedi("Come sta il cervello su Supabase? Stato, spazio, errori recenti: in poche frasi, prima ciò che non va.") }
                    TastoJarvis(testo: "Cosa è andato storto?", icona: "exclamationmark.triangle", tinta: tinta) { chiedi("Cosa è andato storto nelle ultime \(ore) ore nelle funzioni del cervello? Leggi i log e dimmelo in parole semplici.") }
                }
                Picker("Periodo", selection: $ore) {
                    Text("6 ore").tag(6); Text("24 ore").tag(24); Text("3 giorni").tag(72)
                }
                .pickerStyle(.segmented)
                .onChange(of: ore) { Task { await carica() } }
                if problemi > 0 {
                    Pannello(titolo: "ERRORI RECENTI", tinta: .red) {
                        ForEach(Array((richieste + console).prefix(25).enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(r.s("livello").uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.red)
                                    Text(r.s("url").isEmpty ? r.s("funzione") : r.s("url")).font(.system(size: 10, design: .monospaced)).foregroundStyle(tinta).lineLimit(1)
                                    Spacer()
                                    Text(r.s("quando")).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                                }
                                if !r.s("messaggio").isEmpty { Text(r.s("messaggio")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(3) }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    Pannello(tinta: .green) {
                        Label("Nessun errore nelle ultime \(ore) ore. Macchine in ordine, Sir.", systemImage: "checkmark.seal")
                            .font(.system(size: 13)).foregroundStyle(.green)
                    }
                }
                if let consumi { pannelloConsumi(consumi) }
                pannelloMemoria
                let funzioni = stato.lista("funzioni")
                if !funzioni.isEmpty {
                    Pannello(titolo: "FUNZIONI EDGE", tinta: tinta) {
                        ForEach(Array(funzioni.enumerated()), id: \.offset) { _, f in
                            HStack {
                                Circle().fill(f.s("stato").uppercased() == "ACTIVE" ? Color.green : Color.orange).frame(width: 6, height: 6)
                                Text(f.s("nome")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white)
                                Spacer()
                                Text("v\(f.n("versione"))").font(.system(size: 11, design: .monospaced)).foregroundStyle(tinta)
                            }
                        }
                    }
                }
                let tabelle = stato.lista("tabelle")
                if !tabelle.isEmpty {
                    Pannello(titolo: "TABELLE", tinta: tinta) {
                        ForEach(Array(tabelle.prefix(30).enumerated()), id: \.offset) { _, t in
                            HStack {
                                Text(t.s("tabella")).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                Text("\(t.n("righe"))").font(.system(size: 12, design: .monospaced)).foregroundStyle(tinta)
                            }
                        }
                    }
                }
            }
        }
        .task { await carica() }
        .task { await caricaExtra() }
        .task {                                                   // il battito si aggiorna da solo finché la scheda è aperta
            while !Task.isCancelled {
                if let p = await VistaVitals.chiama(["pulsazione": true]), p["errore"] == nil { withAnimation(.easeInOut(duration: 0.6)) { battito = Voce(p) } }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// I dati per l'ologramma: tabelle, funzioni, database, storage, errori e il battito dell'ultima ora.
    private func datiOlo(_ s: Voce) -> DatiSupabaseOlo {
        var d = DatiSupabaseOlo()
        d.tabelle = s.lista("tabelle").map { (nome: $0.s("tabella"), righe: $0.n("righe")) }
        d.funzioni = s.lista("funzioni").map { (nome: $0.s("nome"), versione: $0.n("versione"), attiva: $0.s("stato").uppercased() == "ACTIVE") }
        d.db = "\(s.s("database_mb")) MB"
        d.righe = s.n("righe_totali")
        let mb = s.lista("storage").reduce(0.0) { $0 + (Double($1.s("mb")) ?? 0) }, nf = s.lista("storage").reduce(0) { $0 + $1.n("file") }
        d.storage = String(format: "%.0f MB · %d FILE", mb, nf)
        let log = s.voce("log")
        d.errori = (log?.lista("richieste").count ?? 0) + (log?.lista("console").count ?? 0)
        d.minuti = battito?.lista("minuti").map { (r: $0.n("richieste"), e: $0.n("errori")) } ?? []
        return d
    }

    /// Il battito del cervello: le richieste minuto per minuto dell'ultima ora, gli errori in rosso.
    @ViewBuilder private func pannelloBattito(_ p: Voce) -> some View {
        let minuti = p.lista("minuti")
        let punti = minuti.enumerated().map { PuntoBattito(i: $0.offset - (minuti.count - 1), r: $0.element.n("richieste"), e: $0.element.n("errori")) }
        Pannello(titolo: "BATTITO · ULTIMA ORA", tinta: tinta) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(p.n("errori") > 0 ? Color.red : Color.green).frame(width: 7, height: 7)
                    .shadow(color: (p.n("errori") > 0 ? Color.red : Color.green).opacity(0.8), radius: 4)
                Text("\(p.n("richieste")) richieste").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                if p.n("errori") > 0 { Text("· \(p.n("errori")) errori").font(.system(size: 12, design: .monospaced)).foregroundStyle(.red) }
                Spacer()
                if !p.s("ultima").isEmpty { Text("ultima \(p.s("ultima"))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue) }
            }
            Chart {
                ForEach(punti) { m in
                    AreaMark(x: .value("Minuto", m.i), y: .value("Richieste", m.r))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [tinta.opacity(0.45), tinta.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Minuto", m.i), y: .value("Richieste", m.r))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(tinta)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(punti.filter { $0.e > 0 }) { m in
                    BarMark(x: .value("Minuto", m.i), y: .value("Errori", m.e), width: 3)
                        .foregroundStyle(.red)
                }
            }
            .chartXScale(domain: -59...0)
            .chartXAxis {
                AxisMarks(values: [-45, -30, -15, 0]) { v in
                    AxisGridLine().foregroundStyle(tinta.opacity(0.12))
                    AxisValueLabel {
                        if let k = v.as(Int.self) { Text(k == 0 ? "ora" : "\(k)m").font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.tenue) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(tinta.opacity(0.08))
                    AxisValueLabel().font(.system(size: 8, design: .monospaced)).foregroundStyle(Color.tenue)
                }
            }
            .frame(height: 110)
        }
    }

    /// Quanto sta spendendo JARVIS questo mese: cervello (stima dai token) e voce (dal piano ElevenLabs).
    @ViewBuilder private func pannelloConsumi(_ c: Voce) -> some View {
        Pannello(titolo: "SPESA DEL MESE · \(c.s("mese"))", tinta: tinta) {
            HStack(spacing: 10) {
                Valore(titolo: "CERVELLO", valore: String(format: "%.2f $", Double(c.s("dollari_mese")) ?? 0), sotto: "oggi \(String(format: "%.2f", Double(c.s("dollari_oggi")) ?? 0)) $ · \(c.n("chiamate_mese")) chiamate", tinta: tinta)
                if let v = c.voce("voce") {
                    Valore(titolo: "VOCE", valore: "\(v.n("percento"))%", sotto: "del piano \(v.s("piano")) · rinnovo \(v.s("rinnovo"))", tinta: v.n("percento") >= 90 ? .red : tinta)
                } else {
                    Valore(titolo: "VOCE", valore: "\(c.n("caratteri_voce_mese") / 1000)k", sotto: "caratteri detti", tinta: tinta)
                }
            }
            if let cr = c.voce("credito"), cr.b("impostato") {
                let residuo = Double(cr.s("residuo")) ?? 0, iniziale = Double(cr.s("saldo_iniziale")) ?? 0
                let basso = cr.n("percento") < 20 || residuo < 2
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CREDITO ANTHROPIC").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(basso ? Color.red : tinta)
                        Spacer()
                        Text(String(format: "%.2f $ su %.2f $", residuo, iniziale)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(basso ? Color.red : .white)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(tinta.opacity(0.12))
                            Capsule().fill(basso ? Color.red : tinta).frame(width: g.size.width * min(1, max(0, CGFloat(cr.n("percento")) / 100)))
                        }
                    }
                    .frame(height: 5)
                    Text("Stima dalla ricarica del \(cr.s("dal")). Dica a JARVIS «ho ricaricato…» dopo ogni ricarica.").font(.system(size: 9)).foregroundStyle(Color.tenue)
                }
            }
            ForEach(Array(c.lista("modelli").enumerated()), id: \.offset) { _, m in
                HStack {
                    Text(m.s("modello").replacingOccurrences(of: "claude-", with: "")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text("\(m.n("chiamate")) · \((m.n("token_in") + m.n("token_cache") + m.n("token_out")) / 1000)k token").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                    Text(String(format: "%.2f $", Double(m.s("dollari")) ?? 0)).font(.system(size: 11, design: .monospaced)).foregroundStyle(tinta).frame(width: 60, alignment: .trailing)
                }
            }
            Text("Stima dai token, con i listini pubblici; il conto vero è quello di Anthropic.").font(.system(size: 9)).foregroundStyle(Color.tenue)
        }
    }

    /// Cosa JARVIS sa del signore: i fatti in memoria, con il cestino per dimenticarne uno.
    private var pannelloMemoria: some View {
        Pannello(titolo: "COSA SA DI LEI · \(memoria.count) FATTI", tinta: tinta) {
            Button { Suoni.tocco(); withAnimation { mostraMemoria.toggle() } } label: {
                HStack {
                    Text(mostraMemoria ? "Nascondi" : "Mostra la memoria").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(tinta)
                    Spacer()
                    Image(systemName: mostraMemoria ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(tinta)
                }
            }
            .buttonStyle(StileStark())
            if mostraMemoria {
                if memoria.isEmpty { Text("Ancora niente, Sir. L'archivista annota da solo mentre parlate.").font(.system(size: 11)).foregroundStyle(Color.tenue) }
                ForEach(Array(memoria.enumerated()), id: \.offset) { _, m in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.s("fatto")).font(.system(size: 12)).foregroundStyle(.white)
                            Text("\(m.s("categoria")) · \(m.s("quando"))").font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.tenue)
                        }
                        Spacer(minLength: 0)
                        Button { Task { await dimentica(m) } } label: {
                            Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(.red.opacity(0.8)).padding(6)
                        }
                        .buttonStyle(StileStark())
                        .accessibilityLabel("Dimentica")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func carica() async {
        guard let o = await VistaVitals.chiama(["supabase": true, "ore": ore]) else { errore = "Non raggiungo il cervello, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        stato = Voce(o)
    }

    private func caricaExtra() async {
        if let c = await VistaVitals.chiama(["consumi": true]), c["errore"] == nil { consumi = Voce(c) }
        if let m = await VistaVitals.chiama(["memoria": true]) { memoria = Voce(m).lista("memoria") }
    }

    private func dimentica(_ m: Voce) async {
        Suoni.tocco()
        _ = await VistaVitals.chiama(["memoria_dimentica_id": m.n("id")])
        memoria.removeAll { $0.n("id") == m.n("id") }
    }
}

/// Un minuto del battito: quante richieste e quanti errori (i = minuti fa, 0 = adesso).
struct PuntoBattito: Identifiable {
    let i: Int, r: Int, e: Int
    var id: Int { i }
}

// MARK: - ARCHIVIO

struct VistaArchivio: View {
    let chiedi: (String) -> Void
    let apri: (URL) -> Void
    private let tinta = Color.ciano
    private let limiteMB = 25

    @State private var file: [Voce]?
    @State private var cartelle: [Voce] = []
    @State private var errore: String?
    @State private var cerca = ""
    @State private var cartella: String?
    @State private var cartellaNuova = ""
    @State private var fotoScelta: PhotosPickerItem?
    @State private var scegliFile = false
    @State private var caricamento: String?
    @State private var daEliminare: Voce?
    @State private var scatta = false
    @State private var daCondividere: URL?

    var body: some View {
        CorniceScheda(titolo: "Archivio", sottotitolo: file.map { "\($0.count) file · \(cartelle.count) cartelle" } ?? "apro il disco nel cloud",
                      icona: "externaldrive.badge.icloud", tinta: tinta, pronto: file != nil || errore != nil) {
            if let errore {
                Pannello(tinta: tinta) { Text(errore).font(.footnote).foregroundStyle(.orange) }
            } else if let file {
                // 9 nov (build 19): in testa l'ologramma con le prove OFFICINA, NUVOLA, SPIRALE, come il mockup
                OlogrammaArchivioProve(dati: DatiArchivioOlo(file: file.map { FileOlo(nome: $0.s("nome"), cartella: $0.s("cartella"), kb: $0.n("kb"), quando: $0.s("quando"), tipo: $0.s("tipo")) },
                                                             cartelle: cartelle.map { (nome: $0.s("nome"), n: $0.n("file")) }))
                    .corniceOlo(tinta)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.tenue)
                    TextField("Cerca nell'archivio", text: $cerca)
                        .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.white)
                        .submitLabel(.search).onSubmit { Task { await carica() } }
                    if !cerca.isEmpty { Button { cerca = ""; Task { await carica() } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tenue) } }
                }
                .padding(10).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 10))
                if !cartelle.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("tutto", attiva: cartella == nil) { cartella = nil }
                            ForEach(Array(cartelle.enumerated()), id: \.offset) { _, c in
                                chip("\(c.s("nome")) · \(c.n("file"))", attiva: cartella == c.s("nome")) { cartella = c.s("nome") }
                            }
                        }
                    }
                }
                Pannello(titolo: "CARICA", tinta: tinta) {
                    TextField("Cartella (es. denim, serate, contratti)", text: $cartellaNuova)
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(.white)
                        .padding(8).background(Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 10) {
                        Button { Suoni.tocco(); scatta = true } label: {
                            Label("Scatta", systemImage: "camera")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 42).foregroundStyle(Color.fondo)
                                .background(tinta).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(StileStark())
                        PhotosPicker(selection: $fotoScelta, matching: .any(of: [.images, .videos])) {
                            Label("Foto", systemImage: "photo")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 42).foregroundStyle(tinta)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.6), lineWidth: 1))
                        }
                        Button { Suoni.tocco(); scegliFile = true } label: {
                            Label("File", systemImage: "doc")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 42).foregroundStyle(tinta)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.6), lineWidth: 1))
                        }
                        .buttonStyle(StileStark())
                    }
                    if let caricamento { Text(caricamento).font(.system(size: 11, design: .monospaced)).foregroundStyle(tinta) }
                }
                TastoJarvis(testo: "Cosa c'è in archivio?", icona: "waveform", tinta: tinta) { chiedi("Cosa c'è nel mio archivio? Dimmi le cartelle e le cose più recenti, in poche frasi.") }
                if file.isEmpty {
                    Pannello(tinta: tinta) { Text(cerca.isEmpty ? "Archivio vuoto, Sir. Carichi qualcosa, o dica a JARVIS di salvare una foto o un verbale." : "Nessun file per «\(cerca)».").font(.footnote).foregroundStyle(Color.tenue) }
                }
                ForEach(Array(file.enumerated()), id: \.offset) { _, f in
                    Button { Suoni.tocco(); Task { await apriFile(f) } } label: { rigaFile(f) }
                        .buttonStyle(StileStark())
                        .contextMenu {
                            Button { Task { await condividi(f) } } label: { Label("Condividi", systemImage: "square.and.arrow.up") }
                            Button { Task { await apriFile(f) } } label: { Label("Apri", systemImage: "arrow.up.right.square") }
                            Button(role: .destructive) { daEliminare = f } label: { Label("Elimina", systemImage: "trash") }
                        }
                }
            }
        }
        .task { await carica() }
        .onChange(of: cartella) { Task { await carica() } }
        .onChange(of: fotoScelta) { Task { await caricaFoto() } }
        .fileImporter(isPresented: $scegliFile, allowedContentTypes: [.item]) { esito in
            if case .success(let url) = esito { Task { await caricaFile(url) } }
        }
        .fullScreenCover(isPresented: $scatta) {
            Fotocamera(sorgente: .camera) { img in
                if let dati = img.jpegData(compressionQuality: 0.85) { Task { await invia(dati, nome: "scatto-\(Int(Date().timeIntervalSince1970)).jpg", tipo: "image/jpeg") } }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $daCondividere) { url in
            VStack(spacing: 18) {
                Text("LINK VALIDO UN'ORA").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
                ShareLink(item: url) {
                    Label("Condividi il file", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 50).foregroundStyle(Color.fondo)
                        .background(tinta).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 28)
            .presentationDetents([.height(170)])
            .presentationBackground(Color.fondo)
        }
        .alert("Eliminare il file?", isPresented: Binding(get: { daEliminare != nil }, set: { if !$0 { daEliminare = nil } })) {
            Button("Elimina", role: .destructive) { if let f = daEliminare { Task { await elimina(f) } } }
            Button("Annulla", role: .cancel) { daEliminare = nil }
        } message: { Text(daEliminare?.s("nome") ?? "") }
        // 4 nov: la fotocamera, il foglio del link, la scelta dei file e la domanda (iOS) non restano sopra la sezione che sale
        .chiudiFoglioDietro { scatta = false; daCondividere = nil; scegliFile = false; daEliminare = nil }
        .sulloSchermo(testoSchermo)
    }

    /// 8 nov notte: cosa vede JARVIS dell'Archivio (la cartella, la ricerca, i file a schermo nell'ordine).
    private var testoSchermo: String {
        let nomi: [String] = (file ?? []).prefix(20).enumerated().map { i, f in "\(i + 1). \(f.s("nome"))" }
        let elenco: String
        if file == nil { elenco = errore.map { "errore: \($0)" } ?? "file in caricamento" }
        else { elenco = nomi.isEmpty ? "nessun file a schermo" : "file a schermo: " + nomi.joined(separator: "; ") }
        let dove: String = cartella.map { "cartella \($0)" } ?? "tutte le cartelle"
        return Schermo.unisci("Archivio", [dove, Schermo.campo("cerca", cerca), elenco, caricamento.map { "caricamento in corso: \($0)" }])
    }

    private func chip(_ testo: String, attiva: Bool, azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            Text(testo).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(attiva ? tinta : tinta.opacity(0.1))
                .foregroundStyle(attiva ? Color.fondo : tinta)
                .clipShape(Capsule())
        }
        .buttonStyle(StileStark())
    }

    private func icona(_ tipo: String) -> String {
        if tipo.hasPrefix("image/") { return "photo" }
        if tipo.hasPrefix("video/") { return "video" }
        if tipo.hasPrefix("audio/") { return "waveform" }
        if tipo.contains("pdf") { return "doc.richtext" }
        if tipo.hasPrefix("text/") || tipo.contains("json") { return "doc.text" }
        return "doc"
    }

    private func rigaFile(_ f: Voce) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let u = URL(string: f.s("miniatura")), !f.s("miniatura").isEmpty {
                AsyncImage(url: u) { im in im.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.05) }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.3), lineWidth: 1))
            } else {
                Image(systemName: icona(f.s("tipo")))
                    .font(.system(size: 16)).foregroundStyle(tinta).frame(width: 48, height: 48)
                    .background(tinta.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(f.s("nome")).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if !f.s("descrizione").isEmpty { Text(f.s("descrizione")).font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(2) }
                Text("\(f.s("cartella")) · \(f.n("kb")) KB · \(f.s("quando"))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right.square").font(.system(size: 13)).foregroundStyle(Color.tenue)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tinta.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.2), lineWidth: 1))
    }

    private func carica() async {
        var corpo: [String: Any] = ["archivio": true]
        if let cartella { corpo["cartella"] = cartella }
        if !cerca.trimmingCharacters(in: .whitespaces).isEmpty { corpo["cerca"] = cerca }
        guard let o = await VistaVitals.chiama(corpo) else { errore = "Non raggiungo il cervello, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        let v = Voce(o)
        file = v.lista("file")
        cartelle = v.lista("cartelle")
    }

    private func apriFile(_ f: Voce) async {
        guard let o = await VistaVitals.chiama(["archivio_link": f.s("percorso")]), let u = o["url"] as? String, let url = URL(string: u) else { return }
        apri(url)
    }

    private func condividi(_ f: Voce) async {
        guard let o = await VistaVitals.chiama(["archivio_link": f.s("percorso")]), let u = o["url"] as? String, let url = URL(string: u) else { return }
        daCondividere = url
    }

    private func elimina(_ f: Voce) async {
        daEliminare = nil
        _ = await VistaVitals.chiama(["archivio_elimina": f.s("percorso")])
        Suoni.tocco()
        await carica()
    }

    private func caricaFoto() async {
        guard let fotoScelta else { return }
        defer { self.fotoScelta = nil }
        guard let dati = try? await fotoScelta.loadTransferable(type: Data.self) else { return }
        let tipo = fotoScelta.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
        let ext = fotoScelta.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        await invia(dati, nome: "foto-\(Int(Date().timeIntervalSince1970)).\(ext)", tipo: tipo)
    }

    private func caricaFile(_ url: URL) async {
        let accesso = url.startAccessingSecurityScopedResource()
        defer { if accesso { url.stopAccessingSecurityScopedResource() } }
        guard let dati = try? Data(contentsOf: url) else { caricamento = "Non riesco a leggere il file, Sir."; return }
        let tipo = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        await invia(dati, nome: url.lastPathComponent, tipo: tipo)
    }

    private func invia(_ dati: Data, nome: String, tipo: String) async {
        guard dati.count <= limiteMB * 1_048_576 else { caricamento = "Oltre \(limiteMB) MB: dal telefono non lo carico, Sir."; return }
        caricamento = "Carico \(nome)…"
        let cartellaScelta = cartellaNuova.trimmingCharacters(in: .whitespaces).isEmpty ? (cartella ?? "varie") : cartellaNuova
        let corpo: [String: Any] = ["archivio_carica": ["nome": nome, "cartella": cartellaScelta, "tipo": tipo, "base64": dati.base64EncodedString()]]
        guard let o = await VistaVitals.chiama(corpo) else { caricamento = "Il cervello non risponde, Sir."; return }
        if let e = o["errore"] as? String { caricamento = e; return }
        caricamento = "Salvato in \(cartellaScelta)."
        Suoni.schedaPronta()
        await carica()
    }
}

// MARK: - COSTI

/// Quanto costa JARVIS: il mese, oggi, ieri, 7 giorni; il cervello per modello, la voce e i costi fissi.
/// I numeri sono una stima dai token registrati dal cervello (con i listini pubblici).
struct VistaCosti: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano

    @State private var dati: Voce?
    @State private var errore: String?

    var body: some View {
        CorniceScheda(titolo: "Costi", sottotitolo: dati.map { "mese \($0.s("mese")) · stima dai token" } ?? "conto la spesa",
                      icona: "gauge.with.dots.needle.33percent", tinta: tinta, pronto: dati != nil || errore != nil) {
            if let errore {
                Pannello(tinta: tinta) { Text(errore).font(.footnote).foregroundStyle(.orange) }
            } else if let c = dati {
                // 9 nov (build 19): in testa l'ologramma con le prove PALLADIO, TORRI, CLESSIDRA, come il mockup
                OlogrammaCostiProve(dati: DatiCostiOlo.da(c.d)).corniceOlo(tinta)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Self.soldi(c.s("dollari_mese"))).font(.system(size: 46, weight: .thin, design: .rounded)).foregroundStyle(.white)
                        Text("$ questo mese").font(.footnote).foregroundStyle(Color.tenue)
                    }
                    Text("\(c.n("chiamate_mese")) risposte · stima dai token").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                }
                HStack(spacing: 10) {
                    Valore(titolo: "OGGI", valore: Self.soldi(c.s("dollari_oggi")), sotto: "\(c.n("chiamate_oggi")) risposte", tinta: tinta)
                    Valore(titolo: "IERI", valore: Self.soldi(c.s("dollari_ieri")), tinta: tinta)
                    Valore(titolo: "7 GIORNI", valore: Self.soldi(c.s("dollari_7_giorni")), tinta: tinta)
                }
                pannelloCervello(c)
                pannelloVoce(c)
                Pannello(titolo: "FISSI", tinta: tinta) {
                    ForEach(Array(c.lista("fissi").enumerated()), id: \.offset) { _, f in
                        HStack {
                            Text(f.s("nome")).font(.system(size: 14)).foregroundStyle(.white)
                            Spacer()
                            Text(f.s("costo")).font(.system(size: 12, design: .monospaced)).foregroundStyle(tinta)
                        }
                    }
                }
                HStack(spacing: 10) {
                    TastoJarvis(testo: "Stamattina?", icona: "sunrise", tinta: tinta) { chiedi("Quanto abbiamo speso stamattina con JARVIS? Cervello e voce, in due frasi.") }
                    TastoJarvis(testo: "Dove spendo?", icona: "chart.bar", tinta: tinta) { chiedi("Guarda i costi di JARVIS di questa settimana: dove spendo di più e come potrei spendere meno senza peggiorare? In poche frasi.") }
                }
                Text("Stima dai token con i listini pubblici; il conto vero è quello di Anthropic ed ElevenLabs.").font(.system(size: 9)).foregroundStyle(Color.tenue)
            }
        }
        .task { await carica() }
    }

    @ViewBuilder private func pannelloCervello(_ c: Voce) -> some View {
        let modelli = c.lista("modelli")
        let massimo = max(0.01, modelli.map { Double($0.s("dollari")) ?? 0 }.max() ?? 0.01)
        Pannello(titolo: "CERVELLO · CLAUDE", tinta: tinta) {
            if modelli.isEmpty { Text("Nessuna risposta questo mese.").font(.footnote).foregroundStyle(Color.tenue) }
            ForEach(Array(modelli.enumerated()), id: \.offset) { _, m in
                let dollari = Double(m.s("dollari")) ?? 0
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(Self.nomeModello(m.s("modello"))).font(.system(size: 14)).foregroundStyle(.white)
                        Text("\(m.n("chiamate")) risposte").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                        Spacer()
                        Text("\(Self.soldi(m.s("dollari"))) $").font(.system(size: 12, design: .monospaced)).foregroundStyle(tinta)
                    }
                    Self.barra(dollari / massimo, tinta: tinta)
                }
            }
        }
    }

    @ViewBuilder private func pannelloVoce(_ c: Voce) -> some View {
        Pannello(titolo: "VOCE · ELEVENLABS", tinta: tinta) {
            if let v = c.voce("voce") {
                HStack {
                    Text("Piano \(v.s("piano"))").font(.system(size: 14)).foregroundStyle(.white)
                    Spacer()
                    Text("\(v.n("percento"))% usato").font(.system(size: 12, design: .monospaced)).foregroundStyle(v.n("percento") >= 90 ? .red : tinta)
                }
                Self.barra(Double(v.n("percento")) / 100, tinta: v.n("percento") >= 90 ? .red : tinta)
                Text("\(v.n("usati")) di \(v.n("limite")) caratteri · rinnovo \(v.s("rinnovo"))").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
            } else {
                HStack {
                    Text("Caratteri letti").font(.system(size: 14)).foregroundStyle(.white)
                    Spacer()
                    Text("\(c.n("caratteri_voce_mese"))").font(.system(size: 12, design: .monospaced)).foregroundStyle(tinta)
                }
            }
        }
    }

    private func carica() async {
        guard let o = await VistaVitals.chiama(["consumi": true]) else { errore = "Non raggiungo il cervello, Sir."; return }
        if let e = o["errore"] as? String { errore = e; return }
        dati = Voce(o)
    }

    nonisolated static func soldi(_ s: String) -> String {
        String(format: "%.2f", Double(s) ?? 0).replacingOccurrences(of: ".", with: ",")
    }

    nonisolated static func nomeModello(_ m: String) -> String {
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return m.replacingOccurrences(of: "claude-", with: "")
    }

    static func barra(_ frazione: Double, tinta: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(tinta.opacity(0.12))
                Capsule().fill(tinta).frame(width: g.size.width * min(1, max(0, frazione)))
            }
        }
        .frame(height: 4)
    }
}
#endif
