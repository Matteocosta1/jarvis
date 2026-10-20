#if os(iOS)
import SwiftUI
import CryptoKit

/// EDITH — «Even Dead, I'm The Hero»: il sistema di difesa che Tony lascia a Peter.
/// Qui è l'hacking positivo di JARVIS: solo difesa, solo cose del signore (le sue mail, la sua rete, i suoi domini).
/// Porte, Fughe, Link e Domini li controlla il cervello (servizi gratuiti); la Password si controlla qui sul telefono
/// e non esce mai: al servizio arrivano solo i primi 5 caratteri della sua impronta (SHA-1), come vuole il metodo k-anonimato.
struct VistaEdith: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano

    @State private var ip = ""
    @State private var email = ""
    @State private var link = ""
    @State private var dominio = ""
    @State private var password = ""

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
            Text("Solo difesa e solo sue cose: le sue mail, le sue reti, i suoi domini.").font(.system(size: 9)).foregroundStyle(Color.tenue)
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
        let buono = ["pulito", "pulita", "sembra a posto"].contains(esito)
        let colore: Color = buono ? .green : (["pericoloso", "compromessa"].contains(esito) ? .red : .orange)
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
