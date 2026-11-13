#if os(iOS)
import SwiftUI
import CryptoKit

/// EDITH — «Even Dead, I'm The Hero»: il sistema di difesa che Tony lascia a Peter.
/// Qui è l'hacking positivo di JARVIS: solo difesa, solo cose del signore (le sue mail, la sua rete, i suoi domini).
/// Porte, Fughe, Link, Domini, Azienda (VIES), IBAN, Numero e Reputazione li controlla il cervello (servizi gratuiti o chiavi già presenti); la Password si controlla qui sul telefono
/// e non esce mai: al servizio arrivano solo i primi 5 caratteri della sua impronta (SHA-1), come vuole il metodo k-anonimato.
struct VistaEdith: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano

    @State private var ip = ""
    @State private var email = ""
    @State private var link = ""
    @State private var dominio = ""
    @State private var password = ""
    @State private var piva = ""
    @State private var iban = ""
    @State private var numero = ""
    @State private var reputazione = ""

    @State private var esiti: [String: Voce] = [:]
    @State private var inCorso: Set<String> = []
    @State private var esitoPassword: String?
    /// 12 nov (CampoInAlto): il campo che ha la tastiera. Toccato un campo, la pagina lo porta in cima con sotto il suo tasto;
    /// toccato il tasto, la tastiera scende e si vede il risultato (NUMERO e IP hanno tastiere senza «Invio»).
    @FocusState private var campoAttivo: String?

    var body: some View {
        CorniceScheda(titolo: "EDITH", sottotitolo: "Sistema di Difesa e Riconoscimento", icona: "eyeglasses", tinta: tinta) {
            // 9 nov (build 19, il signore: «falli tutti J»): in testa l'ologramma con le prove OCCHIALI, DRONI, SCUDO (i nove controlli;
            // toccato due volte, un controllo col campo scritto parte, come il suo tasto)
            OlogrammaEdithProve(dati: DatiEdithOlo(controlli: controlliOlo, avvia: { esegui($0) })).corniceOlo(tinta)
            // PORTE
            Pannello(titolo: "PORTE", tinta: tinta) {
                Text("Cosa si vede da internet della sua rete: router, DVR, NAS, PC.").font(.footnote).foregroundStyle(Color.tenue)
                campo("IP pubblico (vuoto = la rete di adesso)", testo: $ip, tastiera: .numbersAndPunctuation)
                tasto("Controlla", chiave: "porte") { ["edith": "porte", "ip": ip] }
                if let e = esiti["porte"] { risultatoPorte(e) }
            }
            // FUGHE
            Pannello(titolo: "FUGHE", tinta: tinta) {
                Text("La sua mail è finita in un furto di dati?").font(.footnote).foregroundStyle(Color.tenue)
                campo("mail", testo: $email, tastiera: .emailAddress)
                tasto("Controlla", chiave: "fughe") { ["edith": "fughe", "email": email] }
                if let e = esiti["fughe"] { risultatoFughe(e) }
            }
            // LINK
            Pannello(titolo: "LINK", tinta: tinta) {
                Text("Incolli un SMS, una mail o un link strano: lo controllo senza aprirlo.").font(.footnote).foregroundStyle(Color.tenue)
                campo("testo o link", testo: $link, tastiera: .URL)
                tasto("Controlla", chiave: "link") { ["edith": "link", "testo": link] }
                if let e = esiti["link"] { risultatoLink(e) }
            }
            // DOMINI
            Pannello(titolo: "DOMINI", tinta: tinta) {
                Text("Certificato, DNS e siti truffa con nomi quasi uguali.").font(.footnote).foregroundStyle(Color.tenue)
                campo("es. discosizer.it", testo: $dominio, tastiera: .URL)
                tasto("Controlla", chiave: "dominio") { ["edith": "dominio", "dominio": dominio] }
                if let e = esiti["dominio"] { risultatoDominio(e) }
            }
            // Difesa prima di fidarsi: in un Group, così la scheda resta sotto i 10 blocchi di SwiftUI
            Group {
            // AZIENDA
            Pannello(titolo: "AZIENDA", tinta: tinta) {
                Text("Una partita IVA è vera e attiva? E di chi è? Prima di fidarsi di un fornitore o di un cliente.").font(.footnote).foregroundStyle(Color.tenue)
                campo("partita IVA (es. 12345678901 o DE123456789)", testo: $piva, tastiera: .asciiCapable)
                tasto("Verifica", chiave: "azienda") { ["edith": "azienda", "piva": piva] }
                if let e = esiti["azienda"] { risultatoAzienda(e) }
            }
            // IBAN
            Pannello(titolo: "IBAN", tinta: tinta) {
                Text("Prima di pagare una fattura: l'IBAN è scritto giusto? Di che banca è?").font(.footnote).foregroundStyle(Color.tenue)
                campo("IT60 X054 2811 1010 0000 0123 456", testo: $iban, tastiera: .asciiCapable)
                tasto("Verifica", chiave: "iban") { ["edith": "iban", "iban": iban] }
                if let e = esiti["iban"] { risultatoIban(e) }
            }
            // NUMERO
            Pannello(titolo: "NUMERO", tinta: tinta) {
                Text("Un numero sconosciuto: da che Paese arriva, cellulare o fisso.").font(.footnote).foregroundStyle(Color.tenue)
                campo("+39 …", testo: $numero, tastiera: .phonePad)
                tasto("Verifica", chiave: "numero") { ["edith": "numero", "numero": numero] }
                if let e = esiti["numero"] { risultatoNumero(e) }
            }
            // REPUTAZIONE
            Pannello(titolo: "REPUTAZIONE", tinta: tinta) {
                Text("Cosa si trova pubblicamente su un'azienda, un sito o un marchio.").font(.footnote).foregroundStyle(Color.tenue)
                campo("nome, azienda o sito", testo: $reputazione, tastiera: .default)
                tasto("Cerca", chiave: "reputazione") { ["edith": "reputazione", "nome": reputazione] }
                if let e = esiti["reputazione"] { risultatoReputazione(e) }
            }
            }
            // PASSWORD
            Pannello(titolo: "PASSWORD", tinta: tinta) {
                Text("È già stata rubata? Il controllo si fa qui: la password non esce dal telefono.").font(.footnote).foregroundStyle(Color.tenue)
                SecureField("password", text: $password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .focused($campoAttivo, equals: "password")
                    .id("edith-password")
                Button { Suoni.tocco(); campoAttivo = nil; Task { await controllaPassword() } } label: { etichetta("Controlla", attivo: inCorso.contains("password")) }
                    .buttonStyle(StileStark()).disabled(password.isEmpty || inCorso.contains("password"))
                if let esitoPassword { Text(esitoPassword).font(.system(size: 13)).foregroundStyle(esitoPassword.hasPrefix("⚠️") ? .orange : .green) }
            }
            // RETE
            Pannello(titolo: "RETE", tinta: tinta) {
                Text("Chi è collegato al suo Wi-Fi: serve un permesso Apple in più, arriva con un prossimo aggiornamento. Intanto PORTE controlla cosa vede internet della sua rete.")
                    .font(.footnote).foregroundStyle(Color.tenue)
            }
            HStack(spacing: 10) {
                TastoJarvis(testo: "Controllo completo", icona: "eyeglasses", tinta: tinta) {
                    chiedi("EDITH, controllo completo: guarda cosa si vede da internet della mia rete di adesso e dimmi in poche frasi se c'è qualcosa da sistemare.")
                }
            }
            Text("Solo difesa: le sue cose, e dati pubblici prima di fidarsi di qualcuno.").font(.system(size: 9)).foregroundStyle(Color.tenue)
        }
        .regia("EDITH", stato: testoSchermo, azioni: [                   // 12.0 (10): la regia (la password solo a mano)
            AzioneRegia("controlla", "scrive il dato nel suo campo e fa partire il controllo. tipo: porte (dato = IP; vuoto = la rete di adesso), fughe (mail), link (testo o link), dominio, azienda (partita IVA), iban, numero, reputazione (nome, azienda o sito). La password solo a mano: non esce dal telefono",
                        valore: "tipo, dato") { v in
                let dato = (v["dato"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let chiave: String
                switch Regia.chiave(v["tipo"] ?? "") {
                case "porte", "porta", "rete", "ip": chiave = "porte"; ip = dato
                case "fughe", "fuga", "mail", "email": chiave = "fughe"; email = dato
                case "link", "sms", "testo": chiave = "link"; link = dato
                case "dominio", "domini", "sito": chiave = "dominio"; dominio = dato
                case "azienda", "piva", "partitaiva": chiave = "azienda"; piva = dato
                case "iban": chiave = "iban"; iban = dato
                case "numero", "telefono": chiave = "numero"; numero = dato
                case "reputazione", "nome": chiave = "reputazione"; reputazione = dato
                case "password": return .no("la password si controlla solo a mano, nel suo campo: non esce dal telefono")
                default: return .no("controllo sconosciuto: porte, fughe, link, dominio, azienda, iban, numero, reputazione")
                }
                guard !inCorso.contains(chiave) else { return .no("il controllo \(chiave) è già in corso") }
                guard let c = corpo(chiave) else { return .no("manca il dato da controllare") }
                Suoni.tocco()
                campoAttivo = nil
                await controlla(chiave, c)
                return .fatto("esito \(chiave): " + (esiti[chiave].map { Schermo.esito($0.d) } ?? "nessun esito"))
            },
        ])
        .onChange(of: campoAttivo) { _, c in if let c { CampoInAlto.porta("edith-" + c) } }   // 12 nov: il campo toccato sale in cima
    }

    /// 8 nov notte: cosa vede JARVIS di EDITH (i campi scritti e i risultati già mostrati). La password non esce mai dal telefono:
    /// JARVIS sa solo se è scritta e l'esito del controllo fatto qui.
    private var testoSchermo: String {
        let campi: [(String, String)] = [("PORTE · IP", ip), ("FUGHE · mail", email), ("LINK · testo o link", link), ("DOMINI · dominio", dominio),
                                         ("AZIENDA · partita IVA", piva), ("IBAN", iban), ("NUMERO", numero), ("REPUTAZIONE · nome", reputazione)]
        var pezzi: [String?] = campi.map { Schermo.campo($0.0, $0.1) }
        if !password.isEmpty { pezzi.append("PASSWORD: scritta (il valore resta sul telefono)") }
        let chiavi: [(String, String)] = [("porte", "PORTE"), ("fughe", "FUGHE"), ("link", "LINK"), ("dominio", "DOMINI"), ("azienda", "AZIENDA"),
                                          ("iban", "IBAN"), ("numero", "NUMERO"), ("reputazione", "REPUTAZIONE")]
        for (chiave, nome) in chiavi {
            if inCorso.contains(chiave) { pezzi.append("Esito \(nome): controllo in corso") }
            else if let e = esiti[chiave] { pezzi.append("Esito \(nome) già mostrato: \(Schermo.esito(e.d))") }
        }
        if let esitoPassword { pezzi.append("Esito PASSWORD: \(esitoPassword)") }
        return Schermo.unisci("EDITH (difesa)", pezzi)
    }

    // MARK: Pezzi

    private func campo(_ segnaposto: String, testo: Binding<String>, tastiera: UIKeyboardType) -> some View {
        TextField(segnaposto, text: testo)
            .keyboardType(tastiera).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(10).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
            .focused($campoAttivo, equals: segnaposto)
            .id("edith-" + segnaposto)
    }

    private func etichetta(_ testo: String, attivo: Bool) -> some View {
        HStack(spacing: 8) {
            if attivo { ProgressView().tint(Color.fondo) }
            Text(attivo ? "Controllo…" : testo).font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity).frame(height: 42)
        .foregroundStyle(Color.fondo).background(tinta).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tasto(_ testo: String, chiave: String, corpo: @escaping () -> [String: Any]) -> some View {
        Button {
            Suoni.tocco()
            campoAttivo = nil                          // 12 nov: la tastiera scende, il risultato si vede
            Task { await controlla(chiave, corpo()) }
        } label: { etichetta(testo, attivo: inCorso.contains(chiave)) }
        .buttonStyle(StileStark())
        .disabled(inCorso.contains(chiave))
    }

    private func controlla(_ chiave: String, _ corpo: [String: Any]) async {
        inCorso.insert(chiave)
        let r = await VistaVitals.chiama(corpo)
        esiti[chiave] = Voce(r ?? ["errore": "non raggiungo il cervello"])
        inCorso.remove(chiave)
    }

    // MARK: L'ologramma (9 nov)

    /// Il corpo della domanda di un controllo, solo se il suo campo è scritto (PORTE va anche vuoto: la rete di adesso).
    private func corpo(_ chiave: String) -> [String: Any]? {
        let pieno = { (s: String) -> Bool in !s.trimmingCharacters(in: .whitespaces).isEmpty }
        switch chiave {
        case "porte": return ["edith": "porte", "ip": ip]
        case "fughe": return pieno(email) ? ["edith": "fughe", "email": email] : nil
        case "link": return pieno(link) ? ["edith": "link", "testo": link] : nil
        case "dominio": return pieno(dominio) ? ["edith": "dominio", "dominio": dominio] : nil
        case "azienda": return pieno(piva) ? ["edith": "azienda", "piva": piva] : nil
        case "iban": return pieno(iban) ? ["edith": "iban", "iban": iban] : nil
        case "numero": return pieno(numero) ? ["edith": "numero", "numero": numero] : nil
        case "reputazione": return pieno(reputazione) ? ["edith": "reputazione", "nome": reputazione] : nil
        default: return nil
        }
    }

    /// Il tocco nell'ologramma: fa partire il controllo, come il suo tasto.
    private func esegui(_ chiave: String) {
        guard !inCorso.contains(chiave) else { return }
        if chiave == "password" {
            guard !password.isEmpty else { return }
            Suoni.tocco()
            Task { await controllaPassword() }
            return
        }
        guard let c = corpo(chiave) else { return }
        Suoni.tocco()
        Task { await controlla(chiave, c) }
    }

    /// I nove controlli per l'ologramma: fatto (c'è un esito a schermo), a posto o no, e se si può far partire dal tocco.
    private var controlliOlo: [ControlloEdith] {
        let buoni: Set<String> = ["pulito", "pulita", "sembra a posto", "valida", "corretto"]
        let nomi: [(String, String)] = [("porte", "PORTE"), ("fughe", "FUGHE"), ("link", "LINK"), ("dominio", "DOMINI"), ("azienda", "AZIENDA"),
                                        ("iban", "IBAN"), ("numero", "NUMERO"), ("reputazione", "REPUTAZIONE")]
        var out: [ControlloEdith] = nomi.map { (chiave: String, nome: String) -> ControlloEdith in
            let pronto = corpo(chiave) != nil
            guard let e = esiti[chiave] else { return ControlloEdith(id: chiave, nome: nome, esito: "", fatto: false, ok: false, pronto: pronto) }
            if !e.s("errore").isEmpty { return ControlloEdith(id: chiave, nome: nome, esito: e.s("errore"), fatto: true, ok: false, pronto: pronto) }
            var esito = e.s("esito")
            var ok = buoni.contains(esito)
            switch chiave {
            case "link":
                let l = e.lista("link"), male = l.first { !buoni.contains($0.s("esito")) }
                ok = !l.isEmpty && male == nil
                esito = male.map { "\($0.s("dominio")): \($0.s("esito"))" } ?? "tutti i link sembrano a posto"
            case "dominio":
                let giorni = e.voce("certificato")?.n("giorni_rimasti") ?? 99, simili = e.stringhe("simili_registrati")
                ok = simili.isEmpty && giorni >= 15
                esito = "certificato \(giorni) giorni · \(simili.count) simili registrati"
            case "azienda":
                ok = esito == "valida"
                if !e.s("nome").isEmpty { esito = e.s("nome") }
            case "iban":
                ok = esito.hasPrefix("cifra di controllo corretta")
                if ok, !e.s("banca").isEmpty { esito = "corretto · \(e.s("banca"))" }
            case "numero":
                ok = true
                esito = [e.s("paese"), e.s("tipo")].filter { !$0.isEmpty }.joined(separator: " · ")
            case "reputazione":
                ok = true
                esito = e.voce("scheda")?.s("nome") ?? "\(e.lista("risultati").count) risultati"
            default: break
            }
            return ControlloEdith(id: chiave, nome: nome, esito: esito, fatto: true, ok: ok, pronto: pronto)
        }
        let p = esitoPassword.map { $0.replacingOccurrences(of: "⚠️ ", with: "").replacingOccurrences(of: "✓ ", with: "") } ?? ""
        out.append(ControlloEdith(id: "password", nome: "PASSWORD", esito: p, fatto: esitoPassword != nil, ok: esitoPassword?.hasPrefix("✓") ?? false, pronto: !password.isEmpty))
        return out
    }

    private func stato(_ esito: String) -> some View {
        let buono = ["pulito", "pulita", "sembra a posto", "valida", "corretto"].contains(esito)
        let colore: Color = buono ? .green : (["pericoloso", "compromessa", "non valida", "sbagliato"].contains(esito) ? .red : .orange)
        return Text(esito.uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5)
            .padding(.horizontal, 8).padding(.vertical, 3).foregroundStyle(.black).background(colore).clipShape(Capsule())
    }

    @ViewBuilder private func errore(_ e: Voce) -> some View {
        if !e.s("errore").isEmpty { Text(e.s("errore")).font(.footnote).foregroundStyle(.orange) }
    }

    @ViewBuilder private func risultatoPorte(_ e: Voce) -> some View {
        errore(e)
        if !e.s("ip").isEmpty {
            HStack { Text(e.s("ip")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white); Spacer(); stato(e.s("esito")) }
            let porte = (e.d["porte_aperte"] as? [NSNumber] ?? []).map { $0.stringValue }
            if !porte.isEmpty { Text("Porte aperte: \(porte.joined(separator: ", "))").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue) }
            ForEach(e.stringhe("porte_a_rischio"), id: \.self) { Text("⚠️ \($0)").font(.system(size: 12)).foregroundStyle(.orange) }
            ForEach(e.stringhe("vulnerabilita_note"), id: \.self) { Text("🛑 \($0)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.red) }
            if !e.s("nota").isEmpty { Text(e.s("nota")).font(.system(size: 12)).foregroundStyle(Color.tenue) }
        }
    }

    @ViewBuilder private func risultatoFughe(_ e: Voce) -> some View {
        errore(e)
        if !e.s("email").isEmpty {
            HStack { Text(e.s("email")).font(.system(size: 13)).foregroundStyle(.white); Spacer(); stato(e.s("esito")) }
            let furti = e.stringhe("furti")
            if !furti.isEmpty { Text("Trovata in: \(furti.joined(separator: ", "))").font(.system(size: 12)).foregroundStyle(.orange) }
            if !e.s("consiglio").isEmpty { Text(e.s("consiglio")).font(.system(size: 12)).foregroundStyle(Color.tenue) }
        }
    }

    @ViewBuilder private func risultatoLink(_ e: Voce) -> some View {
        errore(e)
        ForEach(Array(e.lista("link").enumerated()), id: \.offset) { _, l in
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text(l.s("dominio")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white).lineLimit(1); Spacer(); stato(l.s("esito")) }
                ForEach(l.stringhe("segnali"), id: \.self) { Text("• \($0)").font(.system(size: 12)).foregroundStyle(Color.tenue) }
            }
        }
    }

    @ViewBuilder private func risultatoDominio(_ e: Voce) -> some View {
        errore(e)
        if !e.s("dominio").isEmpty {
            Text(e.s("dominio")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white)
            if let c = e.voce("certificato") {
                let giorni = c.n("giorni_rimasti")
                Text("Certificato: scade fra \(giorni) giorni (\(c.s("emesso_da")))").font(.system(size: 12)).foregroundStyle(giorni < 15 ? .orange : Color.tenue)
            }
            let simili = e.stringhe("simili_registrati")
            if simili.isEmpty { Text("Nessun dominio simile registrato.").font(.system(size: 12)).foregroundStyle(.green) }
            else { Text("Simili già registrati: \(simili.joined(separator: ", "))").font(.system(size: 12)).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder private func risultatoAzienda(_ e: Voce) -> some View {
        errore(e)
        if !e.s("partita_iva").isEmpty {
            HStack { Text(e.s("partita_iva")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white); Spacer(); stato(e.s("esito") == "valida" ? "valida" : "non valida") }
            if !e.s("nome").isEmpty { Text(e.s("nome")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }
            if !e.s("indirizzo").isEmpty { Text(e.s("indirizzo")).font(.system(size: 12)).foregroundStyle(Color.tenue) }
            if !e.s("nota").isEmpty { Text(e.s("nota")).font(.system(size: 12)).foregroundStyle(.orange) }
        }
    }

    @ViewBuilder private func risultatoIban(_ e: Voce) -> some View {
        errore(e)
        if !e.s("iban").isEmpty {
            let giusto = e.s("esito").hasPrefix("cifra di controllo corretta")
            HStack { Text(e.s("iban")).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7); Spacer(); stato(giusto ? "corretto" : "sbagliato") }
            if !e.s("banca").isEmpty { Text("Banca: \(e.s("banca"))").font(.system(size: 12)).foregroundStyle(.white) }
            Text(giusto ? (e.s("nota").isEmpty ? e.s("esito") : e.s("nota")) : e.s("esito")).font(.system(size: 12)).foregroundStyle(giusto ? Color.tenue : .red)
        }
    }

    @ViewBuilder private func risultatoNumero(_ e: Voce) -> some View {
        errore(e)
        if !e.s("numero").isEmpty {
            HStack { Text(e.s("numero")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.white); Spacer()
                Text(e.s("tipo").uppercased()).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(tinta) }
            Text(e.s("paese")).font(.system(size: 12)).foregroundStyle(.white)
            if !e.s("nota").isEmpty { Text(e.s("nota")).font(.system(size: 12)).foregroundStyle(Color.tenue) }
        }
    }

    @ViewBuilder private func risultatoReputazione(_ e: Voce) -> some View {
        errore(e)
        if let k = e.voce("scheda"), !k.s("nome").isEmpty {
            Text([k.s("nome"), k.s("tipo")].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
        ForEach(Array(e.lista("risultati").enumerated()), id: \.offset) { _, r in
            VStack(alignment: .leading, spacing: 2) {
                if let url = URL(string: r.s("sito")) {
                    Link(r.s("titolo"), destination: url).font(.system(size: 13, weight: .semibold)).foregroundStyle(tinta).lineLimit(2)
                    Text(url.host ?? "").font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
                } else { Text(r.s("titolo")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }
                if !r.s("testo").isEmpty { Text(r.s("testo")).font(.system(size: 12)).foregroundStyle(Color.tenue).lineLimit(3) }
            }
        }
        if !e.s("nota").isEmpty { Text(e.s("nota")).font(.system(size: 12)).foregroundStyle(Color.tenue) }
    }

    // MARK: Password (tutto sul telefono)

    private func controllaPassword() async {
        inCorso.insert("password"); defer { inCorso.remove("password") }
        let impronta = Insecure.SHA1.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined()
        let prefisso = String(impronta.prefix(5)), resto = String(impronta.dropFirst(5))
        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefisso)"),
              let (d, _) = try? await URLSession.shared.data(from: url) else {
            esitoPassword = "⚠️ Non riesco a controllare adesso."
            return
        }
        let righe = String(decoding: d, as: UTF8.self).split(whereSeparator: \.isNewline)
        if let riga = righe.first(where: { $0.hasPrefix(resto) }), let volte = riga.split(separator: ":").last {
            esitoPassword = "⚠️ Rubata \(volte.trimmingCharacters(in: .whitespaces)) volte: la cambi ovunque la usa."
        } else {
            esitoPassword = "✓ Non compare tra le password rubate note."
        }
        password = ""
    }
}
#endif
