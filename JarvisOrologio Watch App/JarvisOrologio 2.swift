import Foundation
import SwiftUI
import Combine
import AVFoundation
import Security
import WatchKit

// MARK: - Impostazioni e portachiavi dell'orologio

enum ImpostazioniOrologio {
    static let indirizzoPredefinito = "https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis"
    static var indirizzo: String { UserDefaults.standard.string(forKey: "indirizzo") ?? indirizzoPredefinito }
    /// Mentre JARVIS parla, il microfono resta in ascolto: se il signore inizia a parlare, JARVIS tace e lo ascolta.
    static var interruzioneVocale: Bool { UserDefaults.standard.object(forKey: "interruzioneVocaleOrologio") as? Bool ?? true }
}

/// La parola d'ordine arriva dall'iPhone e resta nel portachiavi dell'orologio.
enum PortachiaviOrologio {
    private static let servizio = "it.discosizer.jarvis.token"

    static func leggi() -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: servizio,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func salva(_ valore: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servizio]
        SecItemDelete(base as CFDictionary)
        guard !valore.isEmpty else { return }
        var nuovo = base
        nuovo[kSecValueData as String] = Data(valore.utf8)
        nuovo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly   // resta su questo dispositivo: non viaggia nei backup
        SecItemAdd(nuovo as CFDictionary, nil)
    }
}

// MARK: - JARVIS sull'orologio

@MainActor
final class JarvisOrologio: NSObject, ObservableObject {
    enum Fase { case attesa, ascolto, elaboro, parlo }

    @Published var fase: Fase = .attesa
    @Published var domanda = ""
    @Published var risposta = ""
    /// Cronologia › Cancella conversazione: la schermata principale chiede conferma e svuota con l'animazione e il suono.
    @Published var svuotaRichiesto = false
    @Published var stato: String?
    @Published var immagini: [FotoOrologio] = []  // immagini della risposta (web, Discogs, Shazam, foto del signore)
    @Published var repartoRichiesto: Reparto?    // comando vocale: la schermata apre questa sezione

    @Published private(set) var storia: [[String: String]] = [] { didSet { salvaStoria() } }   // ultimi scambi, solo testo
    private var compito: Task<Void, Never>?
    private let sintesi = AVSpeechSynthesizer()
    private var lettore: AVAudioPlayer?
    private var turnoVoce = 0                         // ogni risposta detta ha il suo numero
    private var registratore: AVAudioRecorder?
    private var timerAscolto: Timer?
    private var parlatoRilevato = false
    private var silenzioDa: Date?
    private var livello: Float?                       // livello del microfono, smussato
    private var fondo: Float?                         // rumore di fondo della stanza
    private var inizioAscolto = Date()
    private var automatico = false                    // ascolto partito da solo (fine avvio, dopo una risposta): se tace, si chiude in silenzio
    private var riascolta = false                     // detta la risposta, riascolta da solo
    /// La domanda che il signore ha interrotto (toccando o parlando mentre JARVIS pensava o parlava, anche solo per «muto»):
    /// la prossima frase detta a voce la completa, come sull'iPhone (22 ott, chiesto dal signore).
    private var daUnire: String?
    private var inCorso: String?                      // la domanda a cui sta rispondendo adesso (nil: risposta finita, annuncio, errore)
    // Orecchio mentre JARVIS parla: un secondo registratore che misura solo il volume, per capire se il signore sta parlando
    private var monitor: AVAudioRecorder?
    private var timerMonitor: Timer?
    private var inizioParlato = Date()
    private var ecoMassima: Float = -160               // quanto forte si sente JARVIS stesso dall'altoparlante (misurato nel primo secondo)
    private var colpiVoce = 0
    // Voce a frasi: la prima frase si dice mentre il resto della risposta sta ancora arrivando
    private var bufferFrase = ""
    private var codaVoce: [(testo: String, audio: Task<Data?, Never>)] = []
    private var lettoreCoda: Task<Void, Never>?
    private var flussoAperto = false                   // il cervello sta ancora scrivendo
    private var giaParlato = false                     // almeno una frase di questa risposta è già partita
    private var fineFrase: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        sintesi.delegate = self
        if let d = UserDefaults.standard.data(forKey: "storiaOrologio"),
           let s = try? JSONDecoder().decode([[String: String]].self, from: d) { storia = s }
        if let ultima = storia.last, ultima["role"] == "assistant" { risposta = ultima["content"] ?? "" }
        if storia.count >= 2, let d = storia[storia.count - 2]["content"], storia[storia.count - 2]["role"] == "user" { domanda = d }
    }

    private func salvaStoria() {
        if let d = try? JSONEncoder().encode(storia) { UserDefaults.standard.set(d, forKey: "storiaOrologio") }
    }

    /// Cancella la conversazione sull'orologio. Memoria e note di JARVIS restano nel cervello.
    func cancellaConversazione() {
        ferma()
        daUnire = nil
        inCorso = nil
        storia = []
        domanda = ""
        risposta = ""
        immagini = []
    }

    // MARK: Interazione

    func controllaCollegamento() {
        guard PortachiaviOrologio.leggi().isEmpty else { return }
        stato = "Mi collego all'iPhone…"
        Task {
            let ok = await PonteOrologio.condiviso.chiediToken()
            if fase == .attesa { stato = ok ? nil : "Apra JARVIS sull'iPhone vicino a me, Sir: così ricevo la parola d'ordine." }
        }
    }

    // MARK: Sottovoce («sbatti, …»): come sull'iPhone, risponde a voce bassissima per 10 minuti; «voce normale» torna come prima
    private var sottovoceFino = Date.distantPast
    private var volumeVoce: Float { Date() < sottovoceFino ? 0.05 : 1 }   // sottovoce: appena udibile

    private func togliSbatti(_ frase: String) -> String {
        let basso = frase.lowercased()
        if ["voce normale", "parla normale", "alza la voce", "torna normale"].contains(where: { basso.contains($0) }), basso.count < 40 {
            sottovoceFino = .distantPast
            return ""
        }
        var parole = frase.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let k = parole.prefix(3).firstIndex(where: { ["piano", "sottovoce"].contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }) else { return frase }
        parole.remove(at: k)
        sottovoceFino = Date().addingTimeInterval(600)
        return parole.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!"))
    }

    /// `aVoce`: la frase detta a voce (e non scritta o da un tasto): se prima l'aveva interrotto, completa la domanda di prima.
    func chiedi(_ grezzo: String, aVoce: Bool = false) {
        var testo = togliSbatti(grezzo.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !testo.isEmpty else { stato = Date() < sottovoceFino ? "🤫 Sottovoce" : nil; return }
        if Self.eSoloSilenzio(testo) {                          // «muto», «stop», «basta», «zitto», «Jarvis, basta»: tace e resta in attesa
            if fase == .elaboro || fase == .parlo { segnaInterruzione() }
            ferma()
            return
        }
        let prima = aVoce ? daUnire : nil
        daUnire = nil
        ferma()
        if let prima {
            // interrotto: la domanda di prima e quello che aggiunge diventano una sola richiesta, la risposta tagliata sparisce
            if storia.last?["role"] == "assistant", storia.count >= 2,
               storia[storia.count - 2]["role"] == "user", storia[storia.count - 2]["content"] == prima { storia.removeLast() }
            testo = prima + " … " + testo
        }
        domanda = testo
        risposta = ""
        immagini = []
        stato = nil
        fase = .elaboro
        if storia.last?["role"] == "user" { storia.removeLast() }   // domanda precedente rimasta senza risposta (o quella che si allunga)
        storia.append(["role": "user", "content": testo])
        inCorso = testo
        storia = Array(storia.suffix(12))
        while storia.first?["role"] == "assistant" { storia.removeFirst() }   // la cronologia deve iniziare con l'utente
        compito = Task { await self.turno(nuovoTentativo: true) }
    }

    /// Come sull'iPhone: la frase è solo un ordine di silenzio.
    nonisolated static func eSoloSilenzio(_ frase: String) -> Bool {
        let parole = frase.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        guard !parole.isEmpty, parole.count <= 6 else { return false }
        let silenzio: Set<String> = ["muto", "muta", "zitto", "zitta", "basta", "stop", "fermati", "fermo", "silenzio", "taci", "shh", "sst"]
        let contorno: Set<String> = ["ok", "okay", "ehi", "hey", "dai", "adesso", "ora", "per", "favore", "stai", "sta", "fai", "e", "ho", "detto",
                                     "grazie", "va", "bene", "così", "cosi", "un", "attimo", "aspetta", "mettiti", "in", "attesa", "please"]
        let nomi = ["jarvi", "giarvi", "giàrvi", "jervis", "charvis", "jarves", "jarbis"]
        guard parole.contains(where: { silenzio.contains($0) }) else { return false }
        return parole.allSatisfy { p in silenzio.contains(p) || contorno.contains(p) || nomi.contains(where: { p.hasPrefix($0) }) }
    }

    func ferma() {
        riascolta = false
        compito?.cancel()
        compito = nil
        chiudiMicrofono()
        zittisci()
        stato = nil
        fase = .attesa
    }

    func ripeti() {
        guard !risposta.isEmpty else { return }
        parla(risposta)
    }

    // MARK: Ascolto col reattore: tocco, parlo, si ferma da solo quando taccio (o al secondo tocco)

    /// Ricorda la domanda che il signore sta interrompendo: quello che dirà adesso la completa.
    private func segnaInterruzione() {
        if let d = inCorso { daUnire = d }              // solo una risposta in corso: non un annuncio, un errore o una risposta già finita
    }

    func toccaReattore() {
        switch fase {
        case .attesa: Task { await self.ascolta() }
        case .ascolto: fermaEInvia()
        case .elaboro, .parlo:
            segnaInterruzione()
            ferma()
            Task { await self.ascolta() }
        }
    }

    /// Tocco sulla complicazione del quadrante: JARVIS si apre e ascolta subito.
    func ascoltaDaComplicazione() {
        guard fase == .attesa else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(400))   // il tempo che l'app sia davvero in primo piano
            if fase == .attesa { await ascolta() }
        }
    }

    /// Fine dell'avvio: JARVIS si mette in ascolto da solo, come col tocco sul reattore.
    func ascoltaDopoAvvio() {
        guard fase == .attesa else { return }
        Task { await ascolta(automatico: true) }
    }

    /// Detta la risposta: riascolta da solo (se il signore tace, il microfono si chiude dopo 2 secondi).
    private func dopoRisposta() {
        guard riascolta else { return }
        riascolta = false
        Task {
            try? await Task.sleep(for: .milliseconds(250))     // la coda della voce non entra nel microfono
            guard fase == .attesa else { return }
            await ascolta(automatico: true)
        }
    }

    private func ascolta(automatico auto: Bool = false) async {
        guard await AVAudioApplication.requestRecordPermission() else {
            stato = "Mi serve il microfono, Sir: lo attivi in Impostazioni › Privacy e sicurezza › Microfono."
            return
        }
        guard fase == .attesa else { return }
        zittisci()
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default)
            try s.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voce.m4a")
            try? FileManager.default.removeItem(at: url)
            let impostazioni: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                                               AVSampleRateKey: 16_000,
                                               AVNumberOfChannelsKey: 1,
                                               AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            let r = try AVAudioRecorder(url: url, settings: impostazioni)
            r.isMeteringEnabled = true
            guard r.record() else {
                try? s.setActive(false, options: .notifyOthersOnDeactivation)
                stato = "Il microfono non parte, Sir. Riprovi."
                return
            }
            registratore = r
            automatico = auto
            parlatoRilevato = false
            silenzioDa = nil
            livello = nil
            fondo = nil
            inizioAscolto = Date()
            domanda = ""
            stato = "La ascolto, Sir…"
            fase = .ascolto
            WKInterfaceDevice.current().play(.start)
            timerAscolto = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.controllaSilenzio() }
            }
        } catch {
            stato = "Microfono non disponibile: \(error.localizedDescription)"
        }
    }

    private func controllaSilenzio() {
        guard fase == .ascolto, let r = registratore else { return }
        r.updateMeters()
        let grezzo = r.averagePower(forChannel: 0)          // decibel: -160 silenzio, 0 massimo
        Volume.voce.mettiDecibel(grezzo)                    // il reattore si gonfia con la voce
        let ora = Date()
        let avviato = ora.timeIntervalSince(inizioAscolto) > 0.5   // il primo mezzo secondo contiene il "tic" dell'aptica
        // soglie che si adattano al rumore della stanza: il fondo è il livello più basso sentito (che risale piano)
        livello = livello == nil ? grezzo : (livello! * 0.6 + grezzo * 0.4)
        let l = livello!
        fondo = min(l, (fondo ?? l) + 0.08)
        let voce = l > max(fondo! + 9, -50)
        if voce && avviato {
            parlatoRilevato = true
            silenzioDa = nil
        } else if parlatoRilevato {
            if let da = silenzioDa {
                if ora.timeIntervalSince(da) > 0.8 { fermaEInvia(); return }   // 0,8 s di silenzio: ha finito
            } else {
                silenzioDa = ora
            }
        }
        let durata = ora.timeIntervalSince(inizioAscolto)
        if !parlatoRilevato && automatico && durata > 2 {       // partito da solo e nessuno parla: si chiude in silenzio dopo 2 secondi
            chiudiMicrofono()
            fase = .attesa
            stato = nil
        } else if !parlatoRilevato && durata > 7 {
            chiudiMicrofono()
            fase = .attesa
            stato = "Non ho sentito nulla, Sir. Tocchi il reattore e parli."
        } else if durata > 25 {
            fermaEInvia()
        }
    }

    private func fermaEInvia() {
        guard fase == .ascolto, let url = registratore?.url else { return }
        chiudiMicrofono()
        WKInterfaceDevice.current().play(.stop)
        fase = .elaboro
        stato = "Trascrivo…"
        compito = Task { await self.trascriviEChiedi(url) }
    }

    private func chiudiMicrofono() {
        timerAscolto?.invalidate()
        timerAscolto = nil
        guard let r = registratore else { return }
        r.stop()
        registratore = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)   // spegne il microfono
    }

    private func trascriviEChiedi(_ url: URL) async {
        guard let audio = try? Data(contentsOf: url), audio.count > 1_000 else {
            fase = .attesa
            stato = "Non ho sentito nulla, Sir."
            return
        }
        let base = ImpostazioniOrologio.indirizzo
        let indirizzo = base.hasSuffix("/jarvis") ? base + "-ascolto" : base.replacingOccurrences(of: "/jarvis", with: "/jarvis-ascolto")
        let (testo, errore) = await JarvisOrologio.trascrivi(audio, token: PortachiaviOrologio.leggi(), indirizzo: indirizzo)
        guard !Task.isCancelled, fase == .elaboro else { return }
        if let testo, !testo.isEmpty {
            // un comando («apri il diario», «fammi vedere il meteo»): la sezione si apre qui, senza passare dal cervello
            var comando = ComandoVocale.riconosci(testo)
            // i comandi rapidi che sull'orologio hanno la loro sezione: «scrivi il diario» → Diario, «ho bisogno di parlarti» → Confidente
            if case .rapido(let a)? = comando {
                switch a {
                case .diario: comando = .apri(.diario)
                case .confidente: comando = .apri(.confidente)
                case .cucina, .riunione: comando = nil            // vivono sull'iPhone: la frase va al cervello
                }
            }
            if case .apri(let reparto)? = comando {
                compito = nil
                WKInterfaceDevice.current().play(.click)
                repartoRichiesto = reparto
                if let a = reparto.annuncio { parla(a) } else { fase = .attesa }
                return
            }
            // «traduci in inglese»: come la sezione Interprete dell'orologio, già sulla lingua
            if case .interprete(let codice)? = comando, let lingua = ComandoVocale.lingueAVoce.first(where: { $0.codice == codice })?.parole.first {
                WKInterfaceDevice.current().play(.click)
                chiedi("Fammi da interprete in \(lingua): ti dirò una frase, tu traducila in \(lingua) e dimmela ad alta voce.")
                return
            }
            chiedi(testo, aVoce: true)
        } else {
            compito = nil
            fase = .attesa
            stato = errore ?? "Non ho capito, Sir. Riprovi."
        }
    }

    nonisolated static func trascrivi(_ audio: Data, token: String, indirizzo: String) async -> (String?, String?) {
        guard !token.isEmpty, let url = URL(string: indirizzo) else { return (nil, "Manca la parola d'ordine, Sir: apra JARVIS sull'iPhone.") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["audio": audio.base64EncodedString(), "formato": "m4a"])
        guard let (d, r) = try? await URLSession.shared.data(for: req) else { return (nil, "Non raggiungo le mie orecchie in cloud, Sir.") }
        let codice = (r as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        if codice == 200 { return (json?["testo"] as? String, nil) }
        if codice == 401 { return (nil, "La parola d'ordine non coincide, Sir.") }
        let dettaglio = json?["errore"] as? String ?? "codice \(codice)"
        if dettaglio.contains(" 401") || dettaglio.contains(" 403") {
            return (nil, "La chiave ElevenLabs non ha il permesso Speech to Text, Sir.")
        }
        return (nil, "Non sono riuscito a trascrivere, Sir (\(dettaglio)).")
    }

    // MARK: Dialogo con il cervello

    private enum Esito { case fine(String), nonAutorizzato, errore(String), client([String: Any]) }

    /// Strumenti che l'orologio sa eseguire per il cervello.
    static let strumenti = ["salute_battito", "salute_riepilogo", "riconosci_musica", "meteo_qui", "foto_cerca"]

    private func eseguiStrumento(_ nome: String, _ input: [String: Any]) async -> (String, Bool) {
        switch nome {
        case "salute_battito":
            stato = "guardo il cuore"
            let ore = (input["ore"] as? NSNumber)?.doubleValue ?? 3
            return (await Cuore.condiviso.riepilogo(ore: ore), false)
        case "salute_riepilogo":
            stato = "guardo l'app Salute"
            return await Benessere.riepilogo(giorni: (input["giorni"] as? NSNumber)?.intValue ?? 2)
        case "foto_cerca":
            stato = "cerco tra le sue foto sull'iPhone"
            let (testo, miniature) = await PonteOrologio.condiviso.cercaFoto(input)
            immagini.append(contentsOf: miniature.prefix(8).map { FotoOrologio(dati: $0, titolo: "Le sue foto") })
            return (testo, false)
        case "meteo_qui":
            stato = "guardo il cielo"
            return await MeteoQui.adesso(ore: (input["ore"] as? NSNumber)?.intValue ?? 6)
        case "riconosci_musica":
            stato = "ascolto la musica"
            WKInterfaceDevice.current().play(.start)
            let secondi = (input["secondi"] as? NSNumber)?.doubleValue ?? 15
            let esito = await Musica.riconosci(secondi: secondi)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            switch esito {
            case .trovato(let b):
                if let c = b.copertina {
                    immagini.append(FotoOrologio(url: c.absoluteString, grande: c.absoluteString,
                                                 pagina: (b.appleMusic ?? b.web)?.absoluteString, titolo: "\(b.artista) – \(b.titolo)"))
                }
                var out: [String: Any] = ["trovato": true, "titolo": b.titolo, "artista": b.artista]
                if let a = b.album { out["album_o_sottotitolo"] = a }
                if !b.generi.isEmpty { out["generi"] = b.generi }
                let d = (try? JSONSerialization.data(withJSONObject: out)) ?? Data("{}".utf8)
                return (String(decoding: d, as: UTF8.self), false)
            case .nessuno:
                return ("{\"trovato\": false, \"nota\": \"nessun brano riconosciuto\"}", false)
            case .errore(let e):
                let d = (try? JSONSerialization.data(withJSONObject: ["trovato": false, "errore": e] as [String: Any])) ?? Data("{}".utf8)
                return (String(decoding: d, as: UTF8.self), true)
            }
        default:
            return ("{\"errore\": \"strumento \(nome) non disponibile sull'orologio: va fatto dall'iPhone\"}", true)
        }
    }

    private func turno(nuovoTentativo: Bool) async {
        var token = PortachiaviOrologio.leggi()
        if token.isEmpty {
            stato = "Chiedo la parola d'ordine all'iPhone…"
            _ = await PonteOrologio.condiviso.chiediToken()
            token = PortachiaviOrologio.leggi()
            if token.isEmpty {
                fallisci("Non ho ancora la parola d'ordine, Sir. Apra JARVIS sull'iPhone e riprovi.")
                return
            }
        }
        do {
            var corpo: [String: Any] = ["messaggi": storia, "dispositivo": "orologio", "strumenti_client": JarvisOrologio.strumenti]
            let posizione = await PosizioneOrologio.attuale()      // dove si trova il signore: serve alla seconda memoria
            if let posizione { corpo["posizione"] = posizione }
            iniziaFlussoVoce()
            for _ in 0..<5 {
                switch try await flussoConRitentativi(token: token, corpo: corpo, richiesta: UUID().uuidString) {
                case .fine(let testo):
                    guard !Task.isCancelled else { return }
                    risposta = testo
                    stato = nil
                    storia.append(["role": "assistant", "content": testo])
                    compito = nil
                    riascolta = true                                             // detta la risposta, riascolta da solo
                    if giaParlato { chiudiFlussoVoce() } else { parla(testo) }   // già partito a frasi: dice solo il resto
                    return
                case .nonAutorizzato:
                    if nuovoTentativo, await PonteOrologio.condiviso.chiediToken(soloDiretta: true) {
                        await turno(nuovoTentativo: false)       // l'iPhone aveva una parola d'ordine più recente
                    } else {
                        fallisci("La parola d'ordine non coincide, Sir. La controlli nell'app JARVIS sull'iPhone.")
                    }
                    return
                case .errore(let messaggio):
                    fallisci(messaggio)
                    return
                case .client(let e):
                    // il cervello chiede all'orologio di eseguire uno strumento (es. leggere i battiti)
                    let richieste = e["richieste"] as? [[String: Any]] ?? []
                    var risultati = e["risultati_server"] as? [[String: Any]] ?? []
                    for q in richieste {
                        try Task.checkCancellation()
                        let (contenuto, errore) = await eseguiStrumento(q["name"] as? String ?? "", q["input"] as? [String: Any] ?? [:])
                        risultati.append(["tool_use_id": q["id"] as? String ?? "", "content": contenuto, "is_error": errore])
                    }
                    try Task.checkCancellation()
                    let lavoro: Any = e["lavoro"] ?? [Any]()
                    let modello: Any = e["modello"] ?? ""
                    let azioniFatte: Any = e["azioni"] ?? [Any]()
                    let detto: Any = e["detto"] ?? ""
                    let continua: [String: Any] = ["lavoro": lavoro, "risultati": risultati,
                                                   "modello": modello, "azioni": azioniFatte, "detto": detto]
                    corpo = ["messaggi": [Any](), "dispositivo": "orologio", "strumenti_client": JarvisOrologio.strumenti, "continua": continua]
                    if let posizione { corpo["posizione"] = posizione }
                }
            }
            fallisci("Mi sono perso in troppi passaggi, Sir. Riformuli pure.")
        } catch {
            if Task.isCancelled { return }
            if let e = error as? URLError, e.code == .cancelled { return }
            fallisci(JarvisOrologio.spiegaErroreRete(error))
        }
    }

    /// Se la linea cade (o scade il tempo), riprova da sola fino a quattro volte (pause 1, 2, 4 s) con lo stesso numero di richiesta,
    /// così il cervello riconosce il doppione. Al secondo inciampo JARVIS lo dice a voce.
    private func flussoConRitentativi(token: String, corpo: [String: Any], richiesta: String) async throws -> Esito {
        var tentativo = 0
        while true {
            do {
                return try await flusso(token: token, corpo: corpo, richiesta: richiesta)
            } catch let e as URLError where JarvisOrologio.lineaCaduta(e) && tentativo < 3 {
                tentativo += 1
                risposta = ""                                 // quello arrivato a metà si butta: la risposta ricomincia intera
                zittisci()
                fase = .elaboro                               // sta ancora lavorando: niente «attesa» a metà
                iniziaFlussoVoce()
                switch tentativo {
                case 1: stato = "Connessione persa, riprovo…"
                case 2:
                    stato = "La linea fa i capricci, insisto…"
                    parlaInciso("Un attimo, Sir: la linea fa i capricci. Insisto.")
                default: stato = "Ultimo tentativo…"
                }
                try await Task.sleep(for: .seconds(Double(1 << (tentativo - 1))))
            }
        }
    }

    nonisolated private static func lineaCaduta(_ e: URLError) -> Bool {
        [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
         .dnsLookupFailed, .secureConnectionFailed, .resourceUnavailable].contains(e.code)
    }

    nonisolated private static func spiegaErroreRete(_ e: Error) -> String {
        guard let u = e as? URLError else { return "Non raggiungo il mio cervello, Sir. \(e.localizedDescription)" }
        switch u.code {
        case .networkConnectionLost: return "Il server è irraggiungibile, Sir: ho insistito quattro volte, la linea non ha collaborato. Mi conceda un momento e me lo richieda."
        case .timedOut: return "Il mio cervello non ha risposto in tempo, Sir, nemmeno al quarto tentativo. Riprovi tra poco."
        case .notConnectedToInternet: return "Siamo senza rete, Sir. Appena torna il campo sono di nuovo operativo."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: return "Non raggiungo il mio cervello, Sir: la rete c'è ma non mi fa passare. Riprovi tra un momento."
        default: return "Un intoppo di rete, Sir (\(u.code.rawValue)). Riprovi tra un momento."
        }
    }

    /// Una frase detta a voce senza cambiare fase (per gli avvisi mentre sta ancora lavorando): voce dell'orologio, subito.
    private func parlaInciso(_ testo: String) {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio)
        try? s.setActive(true)
        let u = AVSpeechUtterance(string: testo)
        u.voice = AVSpeechSynthesisVoice(language: "it-IT")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = volumeVoce
        sintesi.speak(u)
    }

    private func flusso(token: String, corpo: [String: Any], richiesta: String) async throws -> Esito {
        guard let url = URL(string: ImpostazioniOrologio.indirizzo) else { return .errore("Indirizzo del cervello non valido.") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.setValue(richiesta, forHTTPHeaderField: "x-richiesta")
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (righe, resp) = try await URLSession.shared.bytes(for: req)
        let codice = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if codice == 401 { return .nonAutorizzato }
        guard codice == 200 else { return .errore("Il cervello ha risposto con un errore (codice \(codice)).") }

        for try await riga in righe.lines {
            try Task.checkCancellation()
            guard let dati = riga.data(using: .utf8),
                  let e = (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any],
                  let tipo = e["t"] as? String else { continue }
            switch tipo {
            case "testo":
                if let pezzo = e["d"] as? String { risposta += pezzo; stato = nil; accodaPezzo(pezzo) }
            case "stato":
                stato = e["d"] as? String
            case "immagini":
                let nuove = (e["d"] as? [[String: Any]] ?? []).compactMap { d -> FotoOrologio? in
                    guard let m = (d["miniatura"] ?? d["grande"]) as? String else { return nil }
                    return FotoOrologio(url: m, grande: d["grande"] as? String, pagina: d["pagina"] as? String, titolo: d["titolo"] as? String)
                }
                immagini = Array((immagini + nuove).prefix(10))
            case "fine":
                return .fine(e["testo"] as? String ?? risposta)
            case "errore":
                return .errore(e["d"] as? String ?? "Un intoppo tecnico, Sir.")
            case "client":
                return .client(e)
            default:
                break
            }
        }
        return .errore("La risposta si è interrotta a metà, Sir. Riprovi.")
    }

    private func fallisci(_ messaggio: String) {
        inCorso = nil
        guard !Task.isCancelled else { return }   // fermato o sostituito da una nuova domanda: non tocca nulla
        if storia.last?["role"] == "user" { storia.removeLast() }   // la domanda senza risposta non resta in cronologia
        compito = nil
        stato = nil
        risposta = messaggio
        flussoAperto = false
        parla(messaggio)
    }

    // MARK: Voce: prima quella di JARVIS dal cloud, se non arriva la voce dell'orologio

    private func parla(_ testo: String) {
        zittisci()
        turnoVoce += 1
        let mio = turnoVoce
        fase = .parlo
        Task {
            let token = PortachiaviOrologio.leggi()
            let audio = await JarvisOrologio.scaricaVoce(testo, token: token, indirizzo: ImpostazioniOrologio.indirizzo)
            guard mio == turnoVoce, fase == .parlo else { return }   // nel frattempo interrotto o nuova domanda
            attivaAudio()
            if let audio, let p = try? AVAudioPlayer(data: audio) {
                p.delegate = self
                lettore = p
                p.volume = volumeVoce
                Volume.segui(p)
                if p.play() { avviaMonitor(); return }
                lettore = nil
            }
            let u = AVSpeechUtterance(string: testo)
            u.voice = AVSpeechSynthesisVoice(language: "it-IT")
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = volumeVoce
            sintesi.speak(u)
            avviaMonitor()
        }
    }

    private func zittisci() {
        turnoVoce += 1
        lettoreCoda?.cancel()
        lettoreCoda = nil
        for v in codaVoce { v.audio.cancel() }
        codaVoce.removeAll()
        bufferFrase = ""
        giaParlato = false
        flussoAperto = false
        fineFrase?.resume()
        fineFrase = nil
        fermaMonitor()
        lettore?.stop()
        lettore = nil
        sintesi.stopSpeaking(at: .immediate)
        if fase == .parlo { fase = .attesa }
    }

    fileprivate func voceFinita() {
        if let c = fineFrase { fineFrase = nil; c.resume(); return }   // modalità a frasi: passa alla prossima
        guard fase == .parlo else { return }
        inCorso = nil                                  // detta tutta: da qui una frase nuova è una domanda nuova
        fermaMonitor()
        lettore = nil
        fase = .attesa
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        dopoRisposta()
    }

    // MARK: Voce a frasi

    private func iniziaFlussoVoce() {
        bufferFrase = ""
        giaParlato = false
        flussoAperto = true
    }

    /// Ogni pezzo di testo in arrivo: appena c'è una frase completa (almeno 20 caratteri), parte la sua voce.
    private func accodaPezzo(_ pezzo: String) {
        guard flussoAperto else { return }
        bufferFrase += pezzo
        while let fine = JarvisOrologio.fineDiFrase(in: bufferFrase) {
            let frase = String(bufferFrase[..<fine]).trimmingCharacters(in: .whitespacesAndNewlines)
            bufferFrase = String(bufferFrase[fine...])
            if !frase.isEmpty { accodaFrase(frase) }
        }
    }

    nonisolated private static func fineDiFrase(in testo: String) -> String.Index? {
        var i = testo.startIndex
        while i < testo.endIndex {
            let c = testo[i]
            let dopo = testo.index(after: i)
            if ".!?\n".contains(c), testo.distance(from: testo.startIndex, to: i) >= 20,
               dopo < testo.endIndex, testo[dopo] == " " || testo[dopo] == "\n" || c == "\n" {
                return dopo
            }
            i = dopo
        }
        return nil
    }

    private func accodaFrase(_ frase: String) {
        let token = PortachiaviOrologio.leggi()
        let indirizzo = ImpostazioniOrologio.indirizzo
        let audio = Task { await JarvisOrologio.scaricaVoce(frase, token: token, indirizzo: indirizzo) }   // si scarica subito, in parallelo
        codaVoce.append((frase, audio))
        if !giaParlato {
            giaParlato = true
            turnoVoce += 1
            fase = .parlo
            attivaAudio()
        }
        if lettoreCoda == nil {
            let mio = turnoVoce
            lettoreCoda = Task { await self.leggiCoda(turno: mio) }
        }
    }

    /// La risposta è finita: quello che resta nel buffer diventa l'ultima frase.
    private func chiudiFlussoVoce() {
        let resto = bufferFrase.trimmingCharacters(in: .whitespacesAndNewlines)
        bufferFrase = ""
        if !resto.isEmpty { accodaFrase(resto) }
        flussoAperto = false
        if lettoreCoda == nil && codaVoce.isEmpty { voceFinita() }
    }

    private func leggiCoda(turno mio: Int) async {
        while mio == turnoVoce {
            if codaVoce.isEmpty {
                if !flussoAperto { break }                       // finito di scrivere e di dire
                try? await Task.sleep(for: .milliseconds(80))   // aspetta la prossima frase
                continue
            }
            let (frase, scarico) = codaVoce.removeFirst()
            let audio = await scarico.value
            guard mio == turnoVoce else { return }
            var partito = false
            if let audio, let p = try? AVAudioPlayer(data: audio) {
                p.delegate = self
                lettore = p
                p.volume = volumeVoce
                Volume.segui(p)
                partito = p.play()
            }
            if !partito {
                let u = AVSpeechUtterance(string: frase)
                u.voice = AVSpeechSynthesisVoice(language: "it-IT")
                u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = volumeVoce
                sintesi.speak(u)
            }
            avviaMonitor()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in fineFrase = c }
        }
        guard mio == turnoVoce else { return }
        lettoreCoda = nil
        lettore = nil
        if fase == .parlo {
            fermaMonitor()
            fase = .attesa
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            dopoRisposta()
        }
    }

    private var conOrecchio: Bool {
        ImpostazioniOrologio.interruzioneVocale && AVAudioApplication.shared.recordPermission == .granted
    }

    private func attivaAudio() {
        let s = AVAudioSession.sharedInstance()
        if conOrecchio {
            try? s.setCategory(.playAndRecord, mode: .default)      // altoparlante e microfono insieme: parla e intanto ascolta
        } else {
            try? s.setCategory(.playback, mode: .spokenAudio)
        }
        try? s.setActive(true)
    }

    // MARK: Orecchio mentre parla: se il signore inizia a parlare, JARVIS tace e si mette in ascolto

    /// Il primo secondo serve a misurare quanto forte l'orologio sente sé stesso; da lì in poi, un volume nettamente
    /// più alto per oltre mezzo secondo è la voce del signore (l'orologio al polso è più vicino alla bocca che all'altoparlante).
    private func avviaMonitor() {
        guard conOrecchio, fase == .parlo, monitor == nil else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orecchio.m4a")
        try? FileManager.default.removeItem(at: url)
        let impostazioni: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: impostazioni) else { return }
        r.isMeteringEnabled = true
        guard r.record() else { return }
        monitor = r
        inizioParlato = Date()
        ecoMassima = -160
        colpiVoce = 0
        timerMonitor = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.controllaInterruzione() }
        }
    }

    private func fermaMonitor() {
        timerMonitor?.invalidate()
        timerMonitor = nil
        monitor?.stop()
        monitor = nil
    }

    private func controllaInterruzione() {
        guard fase == .parlo, let r = monitor else { fermaMonitor(); return }
        r.updateMeters()
        let livello = r.averagePower(forChannel: 0)
        let trascorso = Date().timeIntervalSince(inizioParlato)
        if trascorso < 1.2 { ecoMassima = max(ecoMassima, livello); return }   // taratura: così sento JARVIS, non il signore
        let soglia = max(ecoMassima + 8, -38)
        if livello > soglia { colpiVoce += 1 } else { colpiVoce = 0 }
        if colpiVoce >= 3 { interrottoAVoce() }                                  // oltre mezzo secondo: è lui
    }

    private func interrottoAVoce() {
        segnaInterruzione()
        fermaMonitor()
        zittisci()
        compito?.cancel()
        compito = nil
        fase = .attesa
        WKInterfaceDevice.current().play(.click)
        stato = "La ascolto, Sir…"
        Task { await self.ascolta() }        // il microfono riparte pulito: il signore ripete la frase dopo il tocco sul polso
    }

    nonisolated static func scaricaVoce(_ testo: String, token: String, indirizzo: String) async -> Data? {
        guard !token.isEmpty, let url = URL(string: indirizzo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["voce": testo])
        guard let (d, r) = try? await URLSession.shared.data(for: req),
              let http = r as? HTTPURLResponse, http.statusCode == 200,
              (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("audio"), !d.isEmpty else { return nil }
        return d
    }
}

extension JarvisOrologio: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) {
        Task { @MainActor in self.voceFinita() }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor in self.voceFinita() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.voceFinita() }
    }
}

/// Un'immagine sull'orologio: dal web (url) oppure una miniatura arrivata dall'iPhone (dati).
nonisolated struct FotoOrologio: Identifiable, Hashable, Sendable {
    let id = UUID()
    var url: String? = nil
    var grande: String? = nil
    var dati: Data? = nil
    var pagina: String? = nil
    var titolo: String? = nil
}
