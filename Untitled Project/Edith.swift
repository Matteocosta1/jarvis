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

    var body: some View {
        CorniceScheda(titolo: "EDITH", sottotitolo: "difesa · solo cose sue", icona: "eyeglasses", tinta: tinta) {
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
                Button { Suoni.tocco(); Task { await controllaPassword() } } label: { etichetta("Controlla", attivo: inCorso.contains("password")) }
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
    }

    // MARK: Pezzi

    private func campo(_ segnaposto: String, testo: Binding<String>, tastiera: UIKeyboardType) -> some View {
        TextField(segnaposto, text: testo)
            .keyboardType(tastiera).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(10).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
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
            Task {
                inCorso.insert(chiave)
                let r = await VistaVitals.chiama(corpo())
                esiti[chiave] = Voce(r ?? ["errore": "non raggiungo il cervello"])
                inCorso.remove(chiave)
            }
        } label: { etichetta(testo, attivo: inCorso.contains(chiave)) }
        .buttonStyle(StileStark())
        .disabled(inCorso.contains(chiave))
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
