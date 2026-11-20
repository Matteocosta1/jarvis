#if os(iOS)
import SwiftUI
import Combine
import UIKit
import AVFoundation
import AVFAudio
import Contacts
import CoreLocation
import UserNotifications
import AuthenticationServices
import CryptoKit

// MARK: - FRIDAY · ACCOUNT (menu in alto): chi è collegato, i permessi, il numero, la voce. Ogni accesso lo fa Bea.

struct VistaAccount: View {
    private let tinta = Color.ciano
    @Environment(\.webAuthenticationSession) private var sessioneWeb
    @Environment(\.openURL) private var apri
    @StateObject private var spotify = SpotifyF.condiviso
    @State private var stato: [String: Any] = [:]
    @State private var pronto = false
    @State private var foglioMail = false
    @State private var numero = Profilo.numero
    @State private var contatti: Int?
    @State private var permessi: [(String, Bool?)] = []
    @State private var voce = Impostazioni.voce
    @State private var parola = ""
    @State private var esitoParola: String?
    private let sintesi = AVSpeechSynthesizer()

    private var posta: String { stato["posta"] as? String ?? "" }

    var body: some View {
        CorniceScheda(titolo: "Account", sottotitolo: "Face ID · \(permessi.filter { $0.1 == true }.count) permessi", icona: "f:account",
                      tinta: tinta, pronto: pronto) {
            HStack(spacing: 14) {
                Text("B").font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(tinta)
                    .frame(width: 58, height: 58).background(Circle().fill(tinta.opacity(0.1))).overlay(Circle().stroke(tinta.opacity(0.5), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Beatrice").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.testo)
                    Text("FRIDAY Mark I · iPhone").font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
                }
            }
            Pannello(titolo: "COLLEGATI", tinta: tinta) {
                collegato("Mail", posta.isEmpty ? "da collegare" : "iCloud · \(posta)", posta.isEmpty ? "Collega" : "Scollega") {
                    if posta.isEmpty { foglioMail = true } else { Task { await scollegaMail() } }
                }
                collegato("Spotify", spotify.collegato ? "Premium · collegato" : (spotify.idApp.isEmpty ? "lo attiva Ale" : "da collegare"),
                          spotify.collegato ? "Scollega" : "Collega", attivo: spotify.collegato || !spotify.idApp.isEmpty) {
                    if spotify.collegato { spotify.scollega() } else { Task { await spotify.collega(sessioneWeb) } }
                }
                collegato("Gestionale", "Bea Pilates", nil) {}
                collegato("Vinted", posta.isEmpty ? "dalle mail · collega la posta" : "dalle mail", nil) {}
                collegato("Instagram", "per i Reel · si apre da Pilates", nil) {}
                if let e = spotify.errore { Text(e).font(.footnote).foregroundStyle(Color.rossoF) }
            }
            Pannello(titolo: "PERMESSI", tinta: tinta) {
                ForEach(permessi, id: \.0) { p in
                    RigaF(etichetta: p.0, valore: p.1 == nil ? "da chiedere" : (p.1! ? "sì" : "no"), stato: p.1 == true ? .ok : .no)
                }
                TastoF(testo: "Apri Impostazioni", icona: "gearshape", pieno: false) {
                    if let u = URL(string: UIApplication.openSettingsURLString) { apri(u) }
                }
            }
            Pannello(titolo: "AVVIO", tinta: tinta) {
                RigaF(etichetta: "Rubrica", valore: contatti.map { "\($0) contatti letti" } ?? "non autorizzata", stato: contatti == nil ? .no : .ok)
                HStack {
                    Text("Il tuo numero").font(.system(size: 14)).foregroundStyle(Color.testo)
                    TextField("", text: $numero, prompt: Text("+39 …").foregroundStyle(Color.tenue))
                        .keyboardType(.phonePad).multilineTextAlignment(.trailing).foregroundStyle(Color.testo)
                        .onChange(of: numero) { _, n in UserDefaults.standard.set(n.filter { $0.isNumber || $0 == "+" }, forKey: Profilo.chiaveNumero) }
                }
                NotaF(testo: "Il numero l'iPhone non lo dà alle app: FRIDAY lo chiede una volta.")
            }
            Pannello(titolo: "VOCE", tinta: tinta) {
                let voci = Jarvis.vociFemminili()
                if voci.isEmpty {
                    NotaF(testo: "Nessuna voce femminile italiana sul telefono: scaricala in Impostazioni › Accessibilità › Contenuto letto ad alta voce › Voci › Italiano.")
                }
                ForEach(voci, id: \.identifier) { v in
                    Button { Suoni.tocco(); voce = v.identifier; UserDefaults.standard.set(v.identifier, forKey: "voce"); prova(v) } label: {
                        RigaF(etichetta: v.name, valore: (v.identifier == (voce.isEmpty ? Jarvis.voceScelta()?.identifier ?? "" : voce) ? "in uso · " : "") + qualita(v),
                              stato: v.identifier == (voce.isEmpty ? Jarvis.voceScelta()?.identifier ?? "" : voce) ? .ok : .normale)
                    }
                    .buttonStyle(.plain)
                }
                NotaF(testo: "La qualità «Premium» o «Avanzata» si scarica gratis in Impostazioni › Accessibilità › Contenuto letto ad alta voce › Voci › Italiano.")
            }
            Pannello(titolo: "PAROLA D'ORDINE", tinta: tinta) {
                SecureField("", text: $parola, prompt: Text("Nuova parola d'ordine").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                TastoF(testo: "Cambia", pieno: false) { Task { await cambiaParola() } }
                if let esitoParola { NotaF(testo: esitoParola) }
            }
            Pannello(titolo: "SICUREZZA", tinta: tinta) {
                NotaF(testo: "Ogni accesso lo fai tu, sulla pagina ufficiale del servizio. Le password restano nel Portachiavi dell'iPhone o nella cassaforte del tuo cervello, e puoi scollegare tutto da qui. Ale non le vede.")
            }
        }
        .sheet(isPresented: $foglioMail) { CollegaMail { email in stato["posta"] = email } }
        .task { await carica() }
    }

    private func collegato(_ nome: String, _ stato: String, _ tasto: String?, attivo: Bool = true, azione: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nome).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.testo)
                Text(stato).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
            }
            Spacer()
            if let tasto {
                Button { Suoni.tocco(); azione() } label: {
                    Text(tasto).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(tinta).overlay(Capsule().stroke(tinta.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(!attivo).opacity(attivo ? 1 : 0.4)
            }
        }
        .padding(.vertical, 2)
    }

    private func qualita(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality { case .premium: "Premium"; case .enhanced: "Avanzata"; default: "Base" }
    }

    private func prova(_ v: AVSpeechSynthesisVoice) {
        let u = AVSpeechUtterance(string: "Ciao Bea, sono FRIDAY.")
        u.voice = v
        sintesi.stopSpeaking(at: .immediate)
        sintesi.speak(u)
    }

    private func carica() async {
        if let o = await VistaVitals.chiama(["account_stato": true]) {
            stato = o
            SpotifyF.condiviso.idApp = o["spotify_client_id"] as? String ?? ""
        }
        contatti = CNContactStore.authorizationStatus(for: .contacts) == .authorized ? await Task.detached { Self.contaContatti() }.value : nil
        let notifiche = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        let pos = CLLocationManager().authorizationStatus
        func s(_ v: Bool, _ deciso: Bool) -> Bool? { deciso ? v : nil }
        permessi = [
            ("Rubrica", s(CNContactStore.authorizationStatus(for: .contacts) == .authorized, CNContactStore.authorizationStatus(for: .contacts) != .notDetermined)),
            ("Posizione", s(pos == .authorizedAlways || pos == .authorizedWhenInUse, pos != .notDetermined)),
            ("Fotocamera", s(AVCaptureDevice.authorizationStatus(for: .video) == .authorized, AVCaptureDevice.authorizationStatus(for: .video) != .notDetermined)),
            ("Microfono", s(AVAudioApplication.shared.recordPermission == .granted, AVAudioApplication.shared.recordPermission != .undetermined)),
            ("Notifiche", s(notifiche == .authorized || notifiche == .provisional, notifiche != .notDetermined)),
        ]
        pronto = true
    }

    nonisolated private static func contaContatti() -> Int {
        var n = 0
        let r = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        try? CNContactStore().enumerateContacts(with: r) { _, _ in n += 1 }
        return n
    }

    private func scollegaMail() async {
        _ = await VistaVitals.chiama(["account_mail": ["scollega": true]])
        stato["posta"] = ""
    }

    private func cambiaParola() async {
        let p = parola.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, let url = URL(string: Impostazioni.indirizzo) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(p, forHTTPHeaderField: "x-friday-token")
        req.httpBody = Data(#"{"consumi":true}"#.utf8)
        let codice = ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse)?.statusCode ?? 0
        if codice == 200 { Portachiavi.salva(p); parola = ""; esitoParola = "Parola d'ordine aggiornata." }
        else { esitoParola = codice == 401 ? "Non è quella giusta." : "Il cervello non risponde: riprova." }
    }
}

/// Bea collega la sua posta iCloud: la mail e una «password per app» (appleid.apple.com), provata subito dal cervello.
struct CollegaMail: View {
    let fatto: (String) -> Void
    @Environment(\.dismiss) private var chiudi
    @Environment(\.openURL) private var apri
    @State private var email = ""
    @State private var password = ""
    @State private var provo = false
    @State private var errore: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5).frame(maxWidth: .infinity)
            Text("POSTA ICLOUD").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            NotaF(testo: "Serve una «password per app» (non quella del tuo Apple ID): la crei in un minuto su account.apple.com › Accesso e sicurezza › Password per app. FRIDAY la prova subito e la tiene nella cassaforte del tuo cervello.")
            Button("Apri account.apple.com") { if let u = URL(string: "https://account.apple.com/account/manage") { apri(u) } }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ciano)
            TextField("", text: $email, prompt: Text("nome@icloud.com").foregroundStyle(Color.tenue))
                .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.ciano.opacity(0.06))).foregroundStyle(Color.testo)
            SecureField("", text: $password, prompt: Text("xxxx-xxxx-xxxx-xxxx").foregroundStyle(Color.tenue))
                .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.ciano.opacity(0.06))).foregroundStyle(Color.testo)
            if let errore { Text(errore).font(.footnote).foregroundStyle(Color.rossoF) }
            TastoF(testo: provo ? "Provo…" : "Collega") { Task { await collega() } }.disabled(provo)
            Spacer()
        }
        .padding(20)
        .background(Color.fondo.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func collega() async {
        provo = true; errore = nil
        defer { provo = false }
        guard let o = await VistaVitals.chiama(["account_mail": ["email": email, "password": password]], attesa: 30) else {
            errore = "Il cervello non risponde: riprova."; return
        }
        if o["ok"] as? Bool == true { fatto(email); chiudi() } else { errore = o["errore"] as? String ?? "Non riesco a collegarla." }
    }
}

// MARK: - SOS: 5 secondi per annullare, poi l'avviso ad Ale con la posizione (il Tocco d'aiuto di JARVIS). Il 112 lo chiama Bea.

struct VistaSOS: View {
    @Environment(\.chiudiOVia) private var chiudi
    @Environment(\.openURL) private var apri
    @State private var conto = 5
    @State private var fase: Fase = .conto
    @State private var messaggio = ""
    enum Fase { case conto, invio, mandato, annullato, errore }

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [Color.rossoF.opacity(fase == .conto ? 0.35 : 0.12), .clear], center: .center, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Label("SOS", systemImage: "exclamationmark.triangle.fill").font(.system(size: 17, weight: .bold, design: .monospaced)).tracking(3)
                        .foregroundStyle(Color.rossoF)
                    Spacer()
                    Button("Chiudi") { Suoni.tocco(); chiudi() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ciano)
                }
                .padding(.horizontal, 20).padding(.top, 8)
                Spacer()
                Text(fase == .conto ? "\(conto)" : fase == .mandato ? "✓" : fase == .invio ? "…" : "!")
                    .font(.system(size: 120, weight: .bold, design: .monospaced)).foregroundStyle(Color.rossoF)
                    .contentTransition(.numericText(countsDown: true))
                Text(testo).font(.system(size: 16)).foregroundStyle(Color.testo).multilineTextAlignment(.center).padding(.horizontal, 30)
                Spacer()
                HStack(spacing: 14) {
                    if fase == .conto {
                        TastoF(testo: "Annulla", tinta: Color.ciano, pieno: false) { fase = .annullato }
                    }
                    TastoF(testo: "Chiama 112", icona: "phone.fill", tinta: Color.rossoF) { if let u = URL(string: "tel://112") { apri(u) } }
                }
                .padding(.horizontal, 20)
                Pannello(titolo: "ATTIVAZIONE", tinta: Color.ciano) {
                    RigaF(etichetta: "Tasto Azione", valore: "comando «Aiuto Ale»")
                    RigaF(etichetta: "Voce", valore: "«FRIDAY, aiuto»")
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .task { await conta() }
    }

    private var testo: String {
        switch fase {
        case .conto: "Tra \(conto) secondi FRIDAY avvisa Ale con la tua posizione. Tocca Annulla se è partito per sbaglio."
        case .invio: "Avviso Ale…"
        case .mandato: "Ale è avvisato, con la tua posizione. Se sei in pericolo chiama il 112."
        case .annullato: "Annullato: non è partito niente."
        case .errore: messaggio
        }
    }

    private func conta() async {
        while conto > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            try? await Task.sleep(for: .seconds(1))
            guard fase == .conto, !Task.isCancelled else { return }
            withAnimation { conto -= 1 }
        }
        fase = .invio
        let esito = await SOSF.manda()
        fase = esito == nil ? .mandato : .errore
        messaggio = esito ?? ""
        UINotificationFeedbackGenerator().notificationOccurred(esito == nil ? .success : .error)
    }
}

/// L'avviso ad Ale (SOS, Rientro non fermato): il cervello lo passa al Tocco d'aiuto di JARVIS. Se il cervello non lo manda,
/// si apre Messaggi con il testo e la posizione pronti per Ale (il tocco su Invia lo fa Bea).
enum SOSF {
    static let chiaveAle = "numeroAleFriday"
    static var numeroAle: String { UserDefaults.standard.string(forKey: chiaveAle) ?? "" }

    @MainActor static func manda(prova: Bool = false) async -> String? {
        let pos = await Posizione.attuale()
        let lat = pos?["lat"] as? Double, lon = pos?["lon"] as? Double
        var corpo: [String: Any] = ["prova": prova]
        if let lat, let lon { corpo["lat"] = lat; corpo["lon"] = lon }
        if let o = await VistaVitals.chiama(["sos": corpo]), o["ok"] as? Bool == true { return nil }
        // riserva: Messaggi con tutto pronto
        let dove = lat.flatMap { la in lon.map { "https://maps.apple.com/?ll=\(la),\($0)" } } ?? "posizione non disponibile"
        let testo = "Ale, ho bisogno di aiuto. \(dove)"
        if let t = testo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let u = URL(string: "sms:\(numeroAle.isEmpty ? "" : numeroAle)&body=\(t)") {
            _ = await UIApplication.shared.open(u)
            return "Il cervello non ha potuto avvisare Ale: ti ho aperto Messaggi con il testo pronto, tocca Invia."
        }
        return "Non sono riuscita ad avvisare Ale: chiamalo o chiama il 112."
    }
}

// MARK: - DIFESA › STRADA: rientro con timer, chiamata finta, sirena, registrazione

struct StradaDifesa: View {
    let tinta: Color
    @StateObject private var s = StradaMotore.condiviso
    @State private var minuti = 25
    @State private var numeroAle = SOSF.numeroAle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                scudo("Rientro", "timer «sono arrivata»", "figure.walk.arrival", attivo: s.rientroFine != nil) { s.rientroFine == nil ? s.iniziaRientro(minuti) : s.fermaRientro() }
                scudo("Chiamata", "FRIDAY ti chiama", "phone.arrow.down.left", attivo: s.chiamata) { s.chiamataFinta() }
            }
            HStack(spacing: 10) {
                scudo("Sirena", "allarme fortissimo", "speaker.wave.3.fill", attivo: s.sirena) { s.sirena ? s.fermaSirena() : s.suonaSirena() }
                scudo("Registra", "audio + posizione", "record.circle", attivo: s.registra) { s.registra ? s.fermaRegistra() : s.iniziaRegistra() }
            }
            if let fine = s.rientroFine {
                Pannello(titolo: "VERSO CASA", tinta: tinta) {
                    TimelineView(.periodic(from: .now, by: 1)) { t in
                        let resta = max(0, Int(fine.timeIntervalSince(t.date)))
                        Text(String(format: "%02d:%02d", resta / 60, resta % 60)).font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(tinta)
                    }
                    NotaF(testo: "Se non lo fermi in tempo, FRIDAY avvisa Ale con la tua posizione.")
                    TastoF(testo: "Sono arrivata") { s.fermaRientro() }
                }
            } else {
                Pannello(titolo: "RIENTRO", tinta: tinta) {
                    Stepper(value: $minuti, in: 5...120, step: 5) { RigaF(etichetta: "Tempo", valore: "\(minuti) min") }.tint(tinta)
                    RigaF(etichetta: "Se non lo fermi", valore: "avviso ad Ale con posizione")
                }
            }
            if let e = s.esito { NotaF(testo: e) }
            Pannello(titolo: "ALE", tinta: tinta) {
                HStack {
                    Text("Numero di Ale").font(.system(size: 14)).foregroundStyle(Color.testo)
                    TextField("", text: $numeroAle, prompt: Text("+39 …").foregroundStyle(Color.tenue)).keyboardType(.phonePad)
                        .multilineTextAlignment(.trailing).foregroundStyle(Color.testo)
                        .onChange(of: numeroAle) { _, n in UserDefaults.standard.set(n.filter { $0.isNumber || $0 == "+" }, forKey: SOSF.chiaveAle) }
                }
                NotaF(testo: "Serve solo se il cervello non riesce ad avvisarlo: allora FRIDAY ti prepara un SMS per lui.")
            }
            if !s.registrazioni.isEmpty {
                Pannello(titolo: "REGISTRAZIONI", tinta: tinta) {
                    ForEach(s.registrazioni, id: \.self) { u in
                        ShareLink(item: u) { RigaF(etichetta: u.deletingPathExtension().lastPathComponent, valore: "condividi") }
                    }
                }
            }
            Pannello(titolo: "TECNICHE", tinta: tinta) {
                RigaF(etichetta: "Liberarsi da una presa al polso", valore: "ruota verso il pollice")
                RigaF(etichetta: "Distanza e voce alta", valore: "«Stai lontano!»")
                NotaF(testo: "Solo difesa. Quello che l'iPhone non permette di controllare non viene promesso.")
            }
        }
        .fullScreenCover(isPresented: $s.chiamata) { ChiamataFinta { s.chiamata = false } }
    }

    private func scudo(_ nome: String, _ sotto: String, _ icona: String, attivo: Bool, azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icona).font(.system(size: 18))
                Text(nome).font(.system(size: 14, weight: .semibold))
                Text(sotto).font(.system(size: 11)).foregroundStyle(attivo ? Color.fondo.opacity(0.7) : Color.tenue)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .foregroundStyle(attivo ? Color.fondo : tinta)
            .background(RoundedRectangle(cornerRadius: 14).fill(attivo ? tinta : tinta.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tinta.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(StileStark())
    }
}

@MainActor final class StradaMotore: ObservableObject {
    static let condiviso = StradaMotore()
    @Published var rientroFine: Date?
    @Published var chiamata = false
    @Published var sirena = false
    @Published var registra = false
    @Published var esito: String?
    @Published var registrazioni: [URL] = []
    private var timer: Task<Void, Never>?
    private var motore: AVAudioEngine?
    private var registratore: AVAudioRecorder?
    private var dovePartito: [String: Any]?

    init() { registrazioni = Self.elenco() }

    func iniziaRientro(_ minuti: Int) {
        let fine = Date().addingTimeInterval(TimeInterval(minuti * 60))
        rientroFine = fine; esito = nil
        // se l'app viene chiusa, la notifica ricorda di fermarlo (l'avviso ad Ale parte solo con l'app viva: iOS non lascia altro)
        let c = UNMutableNotificationContent()
        c.title = "Rientro"; c.body = "Sei arrivata? Apri FRIDAY e fermalo, se no avviso Ale."; c.sound = .default
        c.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rientro", content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(60, minuti * 60 - 60)), repeats: false)))
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minuti * 60)))
            guard !Task.isCancelled, let self, self.rientroFine != nil else { return }
            self.rientroFine = nil
            let e = await SOSF.manda()
            self.esito = e ?? "Tempo scaduto: Ale è avvisato con la tua posizione."
        }
    }

    func fermaRientro() {
        timer?.cancel(); rientroFine = nil; esito = "Rientro fermato: bentornata."
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rientro"])
    }

    func chiamataFinta() {
        Task { try? await Task.sleep(for: .seconds(5)); chiamata = true }
        esito = "Tra 5 secondi FRIDAY ti chiama."
    }

    /// La sirena: due toni che si alternano, al massimo che l'app può (il volume del telefono lo alza Bea).
    func suonaSirena() {
        let e = AVAudioEngine()
        let nodo = Self.nodoSirena()
        e.attach(nodo)
        e.connect(nodo, to: e.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        try? e.start()
        motore = e; sirena = true
        esito = "Sirena accesa: alza il volume al massimo."
    }

    /// Il generatore della sirena: gira sul filo dell'audio, fuori dal main actor.
    nonisolated private static func nodoSirena() -> AVAudioSourceNode {
        let sr = 44_100.0
        var fase = 0.0, t = 0.0
        return AVAudioSourceNode { _, _, frames, abl -> OSStatus in
            let buf = UnsafeMutableAudioBufferListPointer(abl)
            for f in 0..<Int(frames) {
                let freq = Int(t * 2.5) % 2 == 0 ? 960.0 : 770.0
                fase += 2 * .pi * freq / sr
                t += 1 / sr
                let v: Float = sin(fase) > 0 ? 0.9 : -0.9
                for b in buf { b.mData?.assumingMemoryBound(to: Float.self)[f] = v }
            }
            return noErr
        }
    }

    func fermaSirena() { motore?.stop(); motore = nil; sirena = false; esito = nil }

    func iniziaRegistra() {
        let nome = "Difesa " + Date().formatted(.dateTime.day().month().hour().minute()).replacingOccurrences(of: "/", with: "-")
        let u = Self.cartella.appendingPathComponent(nome + ".m4a")
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        let r = try? AVAudioRecorder(url: u, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1])
        guard let r, r.record() else { esito = "Non riesco a registrare: controlla il permesso del microfono."; return }
        registratore = r; registra = true
        Task { dovePartito = await Posizione.attuale(); esito = "Registro audio e posizione." }
    }

    func fermaRegistra() {
        registratore?.stop(); registratore = nil; registra = false
        if let d = dovePartito, let la = d["lat"] as? Double, let lo = d["lon"] as? Double {
            esito = "Registrazione salvata. Posizione all'inizio: \(String(format: "%.5f, %.5f", la, lo))."
        } else { esito = "Registrazione salvata." }
        registrazioni = Self.elenco()
    }

    private static var cartella: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Difesa", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static func elenco() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: cartella, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "m4a" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

/// La chiamata finta: lo schermo di una chiamata in arrivo da «FRIDAY»; risposto, FRIDAY parla come una persona al telefono.
struct ChiamataFinta: View {
    let fine: () -> Void
    @State private var risposto = false
    private let sintesi = AVSpeechSynthesizer()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.fondo2, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer().frame(height: 60)
                Text("FRIDAY").font(.system(size: 34, weight: .regular)).foregroundStyle(.white)
                Text(risposto ? "in chiamata" : "cellulare").font(.system(size: 17)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 80) {
                    Button { sintesi.stopSpeaking(at: .immediate); fine() } label: {
                        Image(systemName: "phone.down.fill").font(.system(size: 30)).foregroundStyle(.white).frame(width: 76, height: 76).background(Circle().fill(.red))
                    }
                    if !risposto {
                        Button { risposto = true; parla() } label: {
                            Image(systemName: "phone.fill").font(.system(size: 30)).foregroundStyle(.white).frame(width: 76, height: 76).background(Circle().fill(.green))
                        }
                    }
                }
                .padding(.bottom, 70)
            }
        }
        .onAppear { UINotificationFeedbackGenerator().notificationOccurred(.warning); Suoni.tocco() }
    }

    private func parla() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let u = AVSpeechUtterance(string: "Ciao Bea, sono io. Dove sei? Ti sto aspettando qui all'angolo, ti vedo tra due minuti. Resta al telefono con me.")
        u.voice = Jarvis.voceScelta()
        sintesi.speak(u)
    }
}

// MARK: - SPOTIFY: Bea si collega da sola (PKCE, nessun segreto nell'app); FRIDAY comanda il suo Spotify

@MainActor final class SpotifyF: ObservableObject {
    static let condiviso = SpotifyF()
    static let ritorno = "it.discosizer.friday://spotify"
    @Published var collegato = Portachiavi2.leggi("spotify.refresh") != nil
    @Published var errore: String?
    @Published var brano: (titolo: String, artista: String, suona: Bool, durata: Double, posizione: Double)?
    @Published var playlist: [(nome: String, uri: String, brani: Int)] = []
    var idApp = ""
    private var accesso: (token: String, scade: Date)?

    func collega(_ sessione: WebAuthenticationSession) async {
        errore = nil
        guard !idApp.isEmpty else { errore = "Spotify non è ancora attivato: lo attiva Ale."; return }
        let verificatore = Self.casuale(64)
        let sfida = Data(SHA256.hash(data: Data(verificatore.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [.init(name: "client_id", value: idApp), .init(name: "response_type", value: "code"),
                        .init(name: "redirect_uri", value: Self.ritorno), .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "code_challenge", value: sfida),
                        .init(name: "scope", value: "user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private")]
        do {
            let r = try await sessione.authenticate(using: c.url!, callbackURLScheme: "it.discosizer.friday")
            guard let codice = URLComponents(url: r, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                errore = "Spotify non ha dato l'accesso."; return
            }
            try await token(["grant_type": "authorization_code", "code": codice, "redirect_uri": Self.ritorno, "client_id": idApp, "code_verifier": verificatore])
            collegato = true
            await aggiorna()
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { errore = "Collegamento non riuscito: riprova." }
        }
    }

    func scollega() { Portachiavi2.salva("spotify.refresh", nil); accesso = nil; collegato = false; brano = nil; playlist = [] }

    private func token(_ campi: [String: String]) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = campi.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let (d, r) = try await URLSession.shared.data(for: req)
        guard (r as? HTTPURLResponse)?.statusCode == 200, let o = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = o["access_token"] as? String else { throw URLError(.userAuthenticationRequired) }
        accesso = (t, Date().addingTimeInterval((o["expires_in"] as? Double ?? 3600) - 60))
        if let rt = o["refresh_token"] as? String { Portachiavi2.salva("spotify.refresh", rt) }
    }

    private func pronto() async -> String? {
        if let a = accesso, a.scade > Date() { return a.token }
        guard let rt = Portachiavi2.leggi("spotify.refresh"), !idApp.isEmpty else { return nil }
        do { try await token(["grant_type": "refresh_token", "refresh_token": rt, "client_id": idApp]); return accesso?.token }
        catch { collegato = false; return nil }
    }

    @discardableResult
    func api(_ metodo: String, _ percorso: String, corpo: [String: Any]? = nil) async -> [String: Any]? {
        guard let t = await pronto(), let u = URL(string: "https://api.spotify.com/v1" + percorso) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = metodo
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        if let corpo { req.httpBody = try? JSONSerialization.data(withJSONObject: corpo); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return nil }
        if (r as? HTTPURLResponse)?.statusCode == 404 { errore = "Spotify non è aperto su nessun dispositivo: aprilo un attimo e riprova." }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    func aggiorna() async {
        guard collegato else { return }
        if let o = await api("GET", "/me/player/currently-playing"), let item = o["item"] as? [String: Any] {
            let artisti = (item["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: ", ")
            brano = (item["name"] as? String ?? "", artisti, o["is_playing"] as? Bool ?? false,
                     (item["duration_ms"] as? Double ?? 0) / 1000, (o["progress_ms"] as? Double ?? 0) / 1000)
        }
        if playlist.isEmpty, let o = await api("GET", "/me/playlists?limit=30") {
            playlist = (o["items"] as? [[String: Any]] ?? []).compactMap { p in
                guard let n = p["name"] as? String, let u = p["uri"] as? String else { return nil }
                return (n, u, ((p["tracks"] as? [String: Any])?["total"] as? Int) ?? 0)
            }
        }
    }

    func playPausa() async { await api("PUT", brano?.suona == true ? "/me/player/pause" : "/me/player/play"); try? await Task.sleep(for: .milliseconds(300)); await aggiorna() }
    func avanti() async { await api("POST", "/me/player/next"); try? await Task.sleep(for: .milliseconds(400)); await aggiorna() }
    func indietro() async { await api("POST", "/me/player/previous"); try? await Task.sleep(for: .milliseconds(400)); await aggiorna() }
    func suona(_ uri: String) async { await api("PUT", "/me/player/play", corpo: ["context_uri": uri]); try? await Task.sleep(for: .milliseconds(500)); await aggiorna() }

    private static func casuale(_ n: Int) -> String {
        let s = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in s.randomElement()! })
    }
}

/// La MUSICA di Bea quando Spotify è collegato: cosa suona, i tasti, le playlist.
struct PannelliSpotify: View {
    let tinta: Color
    @StateObject private var s = SpotifyF.condiviso
    @Environment(\.openURL) private var apri

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Pannello(titolo: "ADESSO", tinta: tinta) {
                if let b = s.brano {
                    Text(b.titolo).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.testo)
                    Text(b.artista).font(.system(size: 14)).foregroundStyle(Color.tenue)
                    ProgressView(value: min(b.posizione, max(b.durata, 1)), total: max(b.durata, 1)).tint(tinta)
                } else {
                    NotaF(testo: "Niente in riproduzione. Scegli una playlist qui sotto.")
                }
                HStack(spacing: 30) {
                    Spacer()
                    Button { Task { await s.indietro() } } label: { Image(systemName: "backward.fill") }
                    Button { Task { await s.playPausa() } } label: { Image(systemName: s.brano?.suona == true ? "pause.fill" : "play.fill").font(.system(size: 30)) }
                    Button { Task { await s.avanti() } } label: { Image(systemName: "forward.fill") }
                    Spacer()
                }
                .font(.system(size: 22)).foregroundStyle(tinta).buttonStyle(.plain)
                if let e = s.errore {
                    NotaF(testo: e)
                    Button("Apri Spotify") { if let u = URL(string: "spotify:") { apri(u) } }.foregroundStyle(tinta)
                }
            }
            Pannello(titolo: "SPOTIFY", tinta: tinta) { RigaF(etichetta: "Account", valore: "Premium · accesso fatto da te", stato: .ok) }
            if !s.playlist.isEmpty {
                Pannello(titolo: "PLAYLIST", tinta: tinta) {
                    ForEach(s.playlist, id: \.uri) { p in
                        Button { Suoni.tocco(); Task { await s.suona(p.uri) } } label: { RigaF(etichetta: p.nome, valore: "\(p.brani) brani") }.buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await s.aggiorna() }
    }
}

/// Un Portachiavi a chiavi libere (Spotify): resta su questo iPhone.
enum Portachiavi2 {
    static func leggi(_ chiave: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "it.discosizer.friday." + chiave,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(decoding: d, as: UTF8.self)
    }
    static func salva(_ chiave: String, _ valore: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "it.discosizer.friday." + chiave]
        SecItemDelete(base as CFDictionary)
        guard let valore else { return }
        var nuovo = base
        nuovo[kSecValueData as String] = Data(valore.utf8)
        nuovo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(nuovo as CFDictionary, nil)
    }
}
#endif
