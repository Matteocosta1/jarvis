import Foundation
import SwiftUI
import Combine
import AVFoundation
import Security
import WatchKit

// MARK: - Impostazioni e portachiavi dell'orologio

enum ImpostazioniOrologio {
    /// Idea B (25 ott): un numero per questa installazione, così il cervello capisce quando orologio e Mac (o iPhone) gli mandano
    /// la stessa frase e fa rispondere uno solo.
    static var idDispositivo: String {
        if let id = UserDefaults.standard.string(forKey: "idDispositivoJarvis"), !id.isEmpty { return id }
        let nuovo = UUID().uuidString
        UserDefaults.standard.set(nuovo, forKey: "idDispositivoJarvis")
        return nuovo
    }
    static let indirizzoPredefinito = "https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis"
    static var indirizzo: String { UserDefaults.standard.string(forKey: "indirizzo") ?? indirizzoPredefinito }
    /// Idea D (25 ott): il cervello sa ricevere la frase come audio insieme alla richiesta della risposta (lo dice la sveglia).
    /// Finché non l'ha detto, l'orologio usa la strada di prima: trascrizione e poi risposta.
    static var giroUnico: Bool { UserDefaults.standard.bool(forKey: "giroUnicoCervello") }
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

    @Published var fase: Fase = .attesa {
        didSet { if fase != oldValue { segnalaUso() } }
    }
    @Published var domanda = ""
    @Published var risposta = ""
    /// Cronologia › Cancella conversazione: la schermata principale chiede conferma e svuota con l'animazione e il suono.
    @Published var svuotaRichiesto = false
    @Published var stato: String?
    @Published var immagini: [FotoOrologio] = []  // immagini della risposta (web, Discogs, Shazam, foto del signore)
    @Published var repartoRichiesto: Reparto?    // comando vocale: la schermata apre questa sezione
    @Published var polsoRichiesto: SchermataPolso?   // build 22: comando a frase esatta, la schermata nuova da aprire
    /// La risposta come arriva dal cervello, toni compresi («[whispers]»): serve alla voce; a schermo e in cronologia va senza.
    private var rispostaGrezza = ""

    @Published private(set) var storia: [[String: String]] = [] { didSet { salvaStoria() } }   // ultimi scambi, solo testo
    private var compito: Task<Void, Never>?
    private let sintesi = AVSpeechSynthesizer()
    /// L'avviso detto mentre lavora («la linea fa i capricci»): sintesi a parte, senza delegato. Prima usava `sintesi`, e la sua
    /// fine (`didFinish` → `voceFinita`) faceva passare la coda alla frase dopo mentre la frase della risposta stava suonando.
    private let sintesiInciso = AVSpeechSynthesizer()
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
    private var quandoDaUnire = Date.distantPast      // l'interruzione vale due minuti (deciso dal signore, 24 ott), come sull'iPhone
    private var inCorso: String?                      // la domanda a cui sta rispondendo adesso (nil: risposta finita, annuncio, errore)
    /// Revisione del dialogo (24 ott), come sull'iPhone: le frasi della risposta dette per intero (H2) e se la risposta è già
    /// nella cronologia (arrivata tutta): se il signore interrompe, nella cronologia resta il punto esatto in cui l'ha fermato.
    private var dettoFinora = ""
    private var rispostaInStoria = false
    /// «Aspetta» e poi silenzio: dopo 5 secondi «Mi dica, Sir» e lo ascolta ancora; se tace, torna in attesa (deciso dal signore).
    private enum DopoAspetta { case no, aspetta, miDica }
    private var dopoAspetta = DopoAspetta.no
    private var fineVoce = Date.distantPast            // quando il signore ha smesso di parlare (l'ultima frase)
    private var limiteInizio: TimeInterval = 7         // quanto aspettare che cominci a parlare
    private var voceSentita: TimeInterval = 0          // M7: quanti secondi di voce nella frase (decide la pausa di fine frase)
    /// M7: la frase con cui il signore interrompe è registrata insieme alla voce di JARVIS: queste parole poi si tolgono.
    private var ecoDaTogliere: String?
    private var ecoMonitor = ""                        // quello che JARVIS ha detto da quando l'orecchio registra
    /// M7: per 2 secondi dopo la domanda il microfono resta aperto per un'aggiunta («…e anche domani»), come sull'iPhone.
    private var ultimaTrascrizione: Task<TrascrittoOrologio, Never>?
    private var primaParte: Task<TrascrittoOrologio, Never>?   // la frase di prima, se quella che sta dicendo è la sua aggiunta
    private var aggiunta: AVAudioRecorder?
    private var timerAggiunta: Timer?
    private var inizioAggiunta = Date()
    private var colpiAggiunta = 0
    private var livelloAggiunta: Float?
    private var fondoAggiunta: Float = -60
    private var timerUso: Timer?
    // Orecchio mentre JARVIS parla: un secondo registratore che misura solo il volume, per capire se il signore sta parlando
    private var monitor: AVAudioRecorder?
    private var timerMonitor: Timer?
    private var inizioParlato = Date()
    private var ecoMassima: Float = -160               // quanto forte si sente JARVIS stesso dall'altoparlante (misurato nel primo secondo)
    private var colpiVoce = 0
    // Voce a frasi: la prima frase si dice mentre il resto della risposta sta ancora arrivando
    private var bufferFrase = ""
    private var frasiVoce: [String] = []   // le frasi della risposta già mandate alla voce (punto 4: il «prima» della frase dopo)
    private var codaVoce: [(testo: String, audio: Task<Data?, Never>)] = []
    private var lettoreCoda: Task<Void, Never>?
    private var flussoAperto = false                   // il cervello sta ancora scrivendo
    private var giaParlato = false                     // almeno una frase di questa risposta è già partita
    private var fineFrase: CheckedContinuation<Void, Never>?
    private var fraseInVoce = false                    // una frase della coda si sta scaricando o dicendo
    private var orecchioSospeso = false                // Shazam ascolta la musica: niente orecchio per le interruzioni
    /// Idea A e B (25 ott): la domanda in corso è stata detta a voce (non un tasto): il cervello lo sa, e se anche un altro
    /// dispositivo l'ha sentita risponde uno solo.
    private var domandaAVoce = false
    /// Idea D: la frase partita col giro unico, la cui trascrizione arriva dentro la risposta (nil: strada di prima).
    private var canaleUnico: CanaleUnico?
    /// Difetto 3 (controllo del 25 ott): la risposta com'era quando il volume l'ha fermata. Se poi nella registrazione non c'è
    /// nessuna sua parola (una tosse, una porta, una risata vicino), JARVIS riprende da lì invece di dire «Non ho capito».
    private struct RispostaSospesa {
        let domanda: String                            // la domanda a cui stava rispondendo
        let completa: String?                          // la risposta intera, se era già arrivata tutta (senza i toni)
        let detto: String                              // le frasi già dette per intero
        let storia: [[String: String]]                 // la cronologia prima del segno d'interruzione
    }
    private var sospesa: RispostaSospesa?

    override init() {
        super.init()
        sintesi.delegate = self
        if let d = UserDefaults.standard.data(forKey: "storiaOrologio"),
           let s = try? JSONDecoder().decode([[String: String]].self, from: d) { storia = s }
        if let ultima = storia.last, ultima["role"] == "assistant" { risposta = ultima["content"] ?? "" }
        if storia.count >= 2, let d = storia[storia.count - 2]["content"], storia[storia.count - 2]["role"] == "user" { domanda = d }
        SuoniOrologio.jarvis = self                  // decisione 37: i suoni del polso sanno quando l'audio è di JARVIS
        // Decisione 38b (24 ott), come sull'iPhone (Jarvis 2.swift, `audioInterrotto`): una telefonata, Siri, un allarme si
        // prendono l'audio. Prima al polso nessuno lo sentiva: il lettore si fermava senza dire «finito» e JARVIS restava
        // «parlo» per sempre (fino a un tocco), oppure l'ascolto restava aperto su un microfono muto.
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let tipo = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard let tipo else { return }
            Task { @MainActor [weak self] in self?.audioInterrotto(iniziato: tipo == .began) }
        }
    }

    /// Decisione 38b: l'audio dell'orologio è stato preso da altro (telefonata, Siri, un allarme) o restituito. Come sull'iPhone:
    /// mentre pensa o parla si ferma come se l'avesse interrotto il signore (poi «continua» o «dicevi?» riprende da lì);
    /// mentre ascolta, l'ascolto si chiude senza mandare niente. A chiamata finita non c'è niente da riaccendere: al polso non
    /// c'è il «Jarvis» in attesa dell'iPhone, e il prossimo tocco (o la complicazione) riapre l'audio da capo.
    private func audioInterrotto(iniziato: Bool) {
        guard iniziato else { return }
        switch fase {
        case .parlo, .elaboro:
            segnaInterruzione()
            ferma()                                      // anche Shazam, se stava ascoltando la musica (decisione 38c)
        case .ascolto:
            dopoAspetta = .no                            // come `fermaAscolto(invia: false)` dell'iPhone: niente «Mi dica, Sir» dopo
            primaParte = nil                             // la frase di prima non parte con un'aggiunta che non c'è più
            ferma()
        case .attesa:
            break
        }
        chiudiAggiunta(spegniAudio: false)               // anche il microfono dell'aggiunta: l'audio adesso è della telefonata
    }

    private func salvaStoria() {
        if let d = try? JSONEncoder().encode(storia) { UserDefaults.standard.set(d, forKey: "storiaOrologio") }
    }

    /// Decisione del signore (24 ott, M8): mentre il signore usa l'orologio, l'iPhone per 10 secondi non prende le frasi senza
    /// «Jarvis» (sentirebbe la domanda fatta al polso o la voce dell'orologio e risponderebbe anche lui). L'orologio glielo dice
    /// a ogni cambio di fase, ogni 4 secondi mentre ascolta, pensa o parla, e quando ha finito (i 10 secondi contano da lì).
    private func segnalaUso() {
        PonteOrologio.condiviso.segnalaUso(forza: fase == .attesa)
        if fase == .attesa {
            timerUso?.invalidate()
            timerUso = nil
        } else if timerUso == nil {
            timerUso = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
                Task { @MainActor in PonteOrologio.condiviso.segnalaUso() }
            }
        }
    }

    /// Cancella la conversazione sull'orologio. Memoria e note di JARVIS restano nel cervello.
    func cancellaConversazione() {
        ferma()
        daUnire = nil
        inCorso = nil
        rispostaInStoria = false
        dopoAspetta = .no
        storia = []
        domanda = ""
        risposta = ""
        immagini = []
    }

    // MARK: Interazione

    func controllaCollegamento() {
        let indirizzo = ImpostazioniOrologio.indirizzo
        let gia = PortachiaviOrologio.leggi()
        // idea D: il cervello si sveglia (come sull'iPhone) e dice se sa ricevere la frase come audio insieme alla risposta
        if !gia.isEmpty { Task { await JarvisOrologio.riscalda(token: gia, indirizzo: indirizzo) } }
        guard gia.isEmpty else { return }
        stato = "Mi collego all'iPhone…"
        Task {
            let ok = await PonteOrologio.condiviso.chiediToken()
            if ok { await JarvisOrologio.riscalda(token: PortachiaviOrologio.leggi(), indirizzo: indirizzo) }
            if fase == .attesa { stato = ok ? nil : "Apra JARVIS sull'iPhone vicino a me, Sir: così ricevo la parola d'ordine." }
        }
    }

    // MARK: Sottovoce («sbatti, …»): come sull'iPhone, risponde a voce bassissima per 10 minuti; «voce normale» torna come prima
    private var sottovoceFino = Date.distantPast
    private var volumeVoce: Float { Date() < sottovoceFino ? 0.05 : 1 }   // sottovoce: appena udibile

    /// Revisione del dialogo (24 ott, M1): la stessa regola dell'iPhone (`Dialogo.volume`): «qual è il piano per stasera?» e
    /// «ma è una voce normale?» sono domande, non ordini.
    private func togliSbatti(_ frase: String) -> String {
        let (resto, cambio) = Dialogo.volume(frase)
        switch cambio {
        case .normale?: sottovoceFino = .distantPast; return ""
        case .sottovoce?: sottovoceFino = Date().addingTimeInterval(600); return resto
        case nil: return frase
        }
    }

    /// `aVoce`: la frase detta a voce (e non scritta o da un tasto): se prima l'aveva interrotto, completa la domanda di prima.
    func chiedi(_ grezzo: String, aVoce: Bool = false) {
        let testo = togliSbatti(grezzo.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !testo.isEmpty else {
            stato = Date() < sottovoceFino ? "🤫 Sottovoce" : nil
            if fase == .elaboro { compito = nil; fase = .attesa }   // solo «piano» o «voce normale»: prima restava a «pensare»
            return
        }
        if Self.eSoloSilenzio(testo) {                          // «muto», «stop», «basta», «zitto», «Jarvis, basta»: tace e resta in attesa
            if fase == .elaboro || fase == .parlo { segnaInterruzione() }
            ferma()
            return
        }
        // l'interruzione vale due minuti (deciso dal signore, 24 ott): dopo, la frase è una domanda nuova
        let prima = aVoce && Date().timeIntervalSince(quandoDaUnire) < Dialogo.validitaInterruzione ? daUnire : nil
        daUnire = nil
        // solo «aspetta», «ascoltami»: lo riascolto, la frase vera arriva adesso. Come sull'iPhone (`instrada`) vale sempre,
        // non solo dopo un'interruzione: prima, detto al microfono che si riapre dopo la risposta, andava al cervello come domanda.
        if aVoce, Seguito.soloAspetta(testo) {
            daUnire = prima                                     // se l'aveva interrotto, la domanda interrotta resta da completare
            ferma()
            // se tace: «Mi dica, Sir» 5 secondi dopo che ha smesso di parlare (fine frase e trascrizione sono già passate)
            let limite = max(1.5, Dialogo.silenzioDopoAspetta - Date().timeIntervalSince(fineVoce))
            Task { await self.ascolta(limiteInizio: limite, aspetta: .aspetta) }
            return
        }
        dopoAspetta = .no
        ferma()
        // l'aveva interrotto: come sull'iPhone decide il cervello, che vede la domanda interrotta e la frase nuova.
        // M7: la nota sta in testa al messaggio, come sull'iPhone (il cervello la riconosce lì); la domanda interrotta resta
        // al suo posto nella cronologia, con la risposta per quanto l'aveva sentita.
        var perCervello: String?
        if let prima { perCervello = JarvisOrologio.notaInterruzione(prima) + testo }
        domanda = testo
        risposta = ""
        rispostaGrezza = ""
        immagini = []
        stato = nil
        fase = .elaboro
        rispostaInStoria = false
        // una domanda di prima rimasta senza risposta (un errore, «Stop») non resta; quella interrotta sì
        if storia.last?["role"] == "user", prima == nil { storia.removeLast() }
        storia.append(["role": "user", "content": perCervello ?? testo])
        inCorso = testo
        storia = Array(storia.suffix(12))
        while storia.first?["role"] == "assistant" { storia.removeFirst() }   // la cronologia deve iniziare con l'utente
        domandaAVoce = aVoce
        compito = Task { await self.turno(nuovoTentativo: true) }
    }

    /// La nota che va davanti alla frase quando il signore aveva interrotto la risposta a `prima` (il cervello la riconosce lì).
    nonisolated static func notaInterruzione(_ prima: String) -> String {
        "(ti ho interrotto mentre rispondevi a «\(prima)». Se questa frase completa, corregge o aggiunge qualcosa a quella richiesta, rispondi tenendo conto di tutte e due insieme; se è una domanda nuova, rispondi solo a questa, senza riprendere la risposta interrotta) "
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
        sospesa = nil                                  // difetto 3: fermato davvero, niente da riprendere
        inCorso = nil                                  // fermato: quello che dice dopo non è più «la risposta in corso»
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
        guard let d = inCorso else { return }           // solo una risposta in corso: non un annuncio, un errore o una risposta già finita
        daUnire = d
        quandoDaUnire = Date()
        // H2/M7: nella cronologia la risposta resta per quello che il signore ha sentito davvero, col punto del taglio
        // (prima restava tutta, come se l'avesse sentita, oppure non restava niente se era ancora in arrivo)
        if rispostaInStoria, storia.last?["role"] == "assistant" {
            storia[storia.count - 1]["content"] = Dialogo.rispostaInterrotta(storia[storia.count - 1]["content"] ?? "", detto: dettoFinora)
        } else if !risposta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, storia.last?["role"] == "user" {
            storia.append(["role": "assistant", "content": Dialogo.rispostaInterrotta(risposta, detto: dettoFinora)])
        }
        rispostaInStoria = false
    }

    /// 24 ott, come sull'iPhone: in attesa il tocco sul reattore spegne il microfono (niente ascolto da solo dopo le risposte);
    /// il tocco dopo lo riaccende e ascolta subito. Riaprendo l'app riparte acceso.
    @Published var micSpento = false

    func toccaReattore() {
        switch fase {
        case .attesa:
            if micSpento { micSpento = false; Task { await self.ascolta() } } else { micSpento = true }
        case .ascolto: fermaEInvia()
        case .elaboro, .parlo:
            micSpento = false
            segnaInterruzione()
            ferma()
            Task { await self.ascolta() }
        }
    }

    /// Tocco sulla complicazione del quadrante: JARVIS si apre e ascolta subito.
    func ascoltaDaComplicazione() {
        guard fase == .attesa else { return }
        micSpento = false                                    // tocco voluto sulla complicazione: il microfono si riaccende
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

    /// `limiteInizio`: quanto aspettare che cominci a parlare; `aspetta`: ascolto dopo «aspetta» (se tace: «Mi dica, Sir»)
    /// o dopo «Mi dica, Sir» (se tace: torna in attesa in silenzio).
    private func ascolta(automatico auto: Bool = false, limiteInizio limite: TimeInterval = 7, aspetta: DopoAspetta = .no) async {
        guard await AVAudioApplication.requestRecordPermission() else {
            stato = "Mi serve il microfono, Sir: lo attivi in Impostazioni › Privacy e sicurezza › Microfono."
            return
        }
        guard fase == .attesa, !micSpento else { return }   // microfono spento a mano: niente ascolto finché non ritocca
        PosizioneOrologio.scalda()                          // difetto 5: il GPS si sveglia mentre il signore parla
        zittisci()
        chiudiAggiunta(spegniAudio: false)
        limiteInizio = limite
        dopoAspetta = aspetta
        voceSentita = 0
        ecoDaTogliere = nil
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
            voceSentita += 0.2
        } else if parlatoRilevato {
            if let da = silenzioDa {
                // M7: la pausa di fine frase come sull'iPhone, per quanto si può senza le parole (l'orologio non le ha finché
                // non trascrive): una risposta corta («sì», «che ore sono?») 0,8 s come prima; una frase normale 1,2 s;
                // un discorso lungo 1,6 s (lì le pause per pensare sono più probabili). Prima 0,8 s per tutto: tagliava i pensieri.
                let pausa = voceSentita < 1.5 ? 0.8 : (voceSentita > 6 ? 1.6 : 1.2)
                if ora.timeIntervalSince(da) > pausa { fermaEInvia(); return }
            } else {
                silenzioDa = ora
            }
        }
        let durata = ora.timeIntervalSince(inizioAscolto)
        if !parlatoRilevato && automatico && durata > 2 {       // partito da solo e nessuno parla: si chiude in silenzio dopo 2 secondi
            chiudiMicrofono()
            fase = .attesa
            stato = nil
        } else if !parlatoRilevato && durata > limiteInizio {
            chiudiMicrofono()
            fase = .attesa
            switch dopoAspetta {
            case .aspetta: stato = nil; miDica()          // «aspetta» e poi silenzio: «Mi dica, Sir» (deciso dal signore, 24 ott)
            case .miDica: stato = nil; dopoAspetta = .no   // nemmeno dopo «Mi dica»: torna in attesa, in silenzio
            case .no: stato = "Non ho sentito nulla, Sir. Tocchi il reattore e parli."
            }
        } else if durata > 25 {
            fermaEInvia()
        }
    }

    private func fermaEInvia() {
        guard fase == .ascolto, let r = registratore else { return }
        let fondoStanza = fondo
        fineVoce = silenzioDa ?? Date()
        dopoAspetta = .no                                // ha parlato: l'attesa dopo «aspetta» è chiusa (la rimette chiedi, se serve)
        timerAscolto?.invalidate()
        timerAscolto = nil
        r.stop()
        registratore = nil
        let audio = try? Data(contentsOf: r.url)        // letto subito: il microfono dell'aggiunta registra già su un altro file
        WKInterfaceDevice.current().play(.stop)
        fase = .elaboro
        stato = "Trascrivo…"
        let eco = ecoDaTogliere
        ecoDaTogliere = nil
        let prima = primaParte                          // c'era una frase prima, e questa è la sua aggiunta
        primaParte = nil
        let token = PortachiaviOrologio.leggi()
        canaleUnico = nil
        // Idea D (25 ott): una frase normale (non un'interruzione sopra JARVIS, non l'aggiunta a una frase di prima) va al cervello
        // in una richiesta sola, l'audio insieme alla domanda: il cervello la trascrive, la rimanda subito e intanto prepara la
        // risposta. Un giro di rete in meno al polso. Se il cervello non lo sa fare, o la trascrizione non riesce, la strada di prima.
        if ImpostazioniOrologio.giroUnico, eco == nil, prima == nil, !token.isEmpty, let audio, audio.count > 1_000 {
            let canale = CanaleUnico()
            canale.prima = Date().timeIntervalSince(quandoDaUnire) < Dialogo.validitaInterruzione ? daUnire : nil
            canaleUnico = canale
            ultimaTrascrizione = Task { await canale.attendi() }
            compito = Task { await self.turno(nuovoTentativo: true, unico: (audio: audio, canale: canale)) }
            ascoltaAggiunta(fondo: fondoStanza)          // M7: per 2 secondi il microfono resta aperto per un'aggiunta
            return
        }
        let indirizzo = JarvisOrologio.indirizzoAscolto
        let trascrizione = Task { () -> TrascrittoOrologio in
            guard let audio, audio.count > 1_000 else { return TrascrittoOrologio(testo: nil, errore: nil, vuoto: true) }
            let (testo, errore) = await JarvisOrologio.trascrivi(audio, token: token, indirizzo: indirizzo)
            return TrascrittoOrologio(testo: testo, errore: errore, vuoto: false)
        }
        ultimaTrascrizione = trascrizione
        compito = Task { await self.dopoTrascrizione(trascrizione, eco: eco, prima: prima) }
        ascoltaAggiunta(fondo: fondoStanza)              // M7: per 2 secondi il microfono resta aperto per un'aggiunta
    }

    // MARK: L'aggiunta subito dopo la domanda (M7, come sull'iPhone e come deciso dal signore: 2 secondi)

    /// Per 2 secondi dopo la domanda un registratore resta acceso: se il signore riprende a parlare («…e anche domani»),
    /// quella frase si registra dall'inizio e parte insieme alla prima (decide il cervello, come sull'iPhone).
    /// Prima il microfono si chiudeva subito e la seconda frase andava persa.
    private func ascoltaAggiunta(fondo stanza: Float?) {
        chiudiAggiunta(spegniAudio: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aggiunta-\(UUID().uuidString).m4a")
        let impostazioni: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: impostazioni) else { spegniAudioSeLibero(); return }
        r.isMeteringEnabled = true
        guard r.record() else { spegniAudioSeLibero(); return }
        aggiunta = r
        inizioAggiunta = Date()
        colpiAggiunta = 0
        livelloAggiunta = nil
        fondoAggiunta = stanza ?? -60
        timerAggiunta = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.controllaAggiunta() }
        }
    }

    private func controllaAggiunta() {
        guard let r = aggiunta else { return }
        let trascorso = Date().timeIntervalSince(inizioAggiunta)
        // finita la finestra (o JARVIS sta già rispondendo, o un comando ha già fatto il suo): si chiude
        guard fase == .elaboro, trascorso < Dialogo.finestraAggiunta || (colpiAggiunta > 0 && trascorso < Dialogo.finestraAggiunta + 0.6) else {
            chiudiAggiunta(spegniAudio: true)            // il microfono si spegne, se JARVIS non sta parlando
            return
        }
        r.updateMeters()
        let grezzo = r.averagePower(forChannel: 0)
        livelloAggiunta = livelloAggiunta.map { $0 * 0.6 + grezzo * 0.4 } ?? grezzo
        guard trascorso > 0.4 else { return }            // il primo istante contiene il «tic» dell'aptica di fine ascolto
        if livelloAggiunta! > max(fondoAggiunta + 9, -50) { colpiAggiunta += 1 } else { colpiAggiunta = 0 }
        if colpiAggiunta >= 2 { aggiuntaSentita(r) }     // voce per quasi mezzo secondo: sta parlando di nuovo
    }

    private func chiudiAggiunta(spegniAudio: Bool) {
        timerAggiunta?.invalidate()
        timerAggiunta = nil
        if let r = aggiunta { r.stop(); r.deleteRecording() }
        aggiunta = nil
        if spegniAudio { spegniAudioSeLibero() }
    }

    /// Il microfono si spegne, ma non se JARVIS sta parlando o ascoltando.
    private func spegniAudioSeLibero() {
        guard fase != .parlo, fase != .ascolto else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ha ripreso a parlare subito dopo la domanda: la domanda di prima si ferma (se era già partita) o aspetta (se era
    /// ancora in trascrizione), e questa frase si ascolta fino in fondo, dal registratore che l'ha già presa dall'inizio.
    private func aggiuntaSentita(_ r: AVAudioRecorder) {
        timerAggiunta?.invalidate()
        timerAggiunta = nil
        aggiunta = nil
        if inCorso != nil {
            segnaInterruzione()                          // già dal cervello: come un'interruzione, la nuova frase la completa
            inCorso = nil
        } else {
            primaParte = ultimaTrascrizione              // ancora in trascrizione: partirà insieme a questa
        }
        if let c = canaleUnico, c.esito == nil {
            // idea D: la prima frase è ancora in trascrizione dentro il giro unico. La richiesta non si chiude: serve il suo testo,
            // che partirà insieme a questa aggiunta; appena arriva, il giro unico si ferma da solo (prima che parta Claude)
            c.soloTesto = true
            compito = nil
        } else {
            compito?.cancel()
            compito = nil
        }
        zittisci()
        continuaAscolto(r)
    }

    /// Il signore sta già parlando e il registratore lo sta già registrando dall'inizio della frase: si continua da lì
    /// come un ascolto normale (stesse pause), senza perdere le prime parole. `eco`: le parole di JARVIS finite nel file.
    private func continuaAscolto(_ r: AVAudioRecorder, eco: String? = nil) {
        PosizioneOrologio.scalda()                       // difetto 5: il GPS si sveglia mentre il signore parla
        timerAscolto?.invalidate()
        registratore = r
        automatico = false
        parlatoRilevato = true
        voceSentita = 0.4
        silenzioDa = nil
        livello = nil
        if fondo == nil { fondo = -60 }                  // il rumore della stanza: quello misurato all'ultimo ascolto
        inizioAscolto = Date().addingTimeInterval(-1)    // niente «tic» da saltare: il signore parla già
        limiteInizio = 7
        dopoAspetta = .no
        ecoDaTogliere = eco
        domanda = ""
        stato = "La ascolto, Sir…"
        fase = .ascolto
        timerAscolto = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.controllaSilenzio() }
        }
    }

    /// 25 ott, come sull'iPhone: l'app va in sottofondo (polso giù, altra app). La frase che stava registrando si butta,
    /// non si trascrive al ritorno; anche l'aggiunta dei 2 secondi si chiude.
    func vaInSottofondo() {
        chiudiAggiunta(spegniAudio: false)
        guard fase == .ascolto else { return }
        chiudiMicrofono()
        primaParte = nil
        dopoAspetta = .no
        fase = .attesa
        stato = nil
    }

    private func chiudiMicrofono() {
        timerAscolto?.invalidate()
        timerAscolto = nil
        guard let r = registratore else { return }
        r.stop()
        registratore = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)   // spegne il microfono
    }

    /// La frase è trascritta: comando, domanda o aggiunta a quella di prima.
    /// `eco`: la frase interrompeva JARVIS (le sue parole sono nella registrazione e si tolgono); `prima`: la frase di prima,
    /// se questa è la sua aggiunta (va nella conversazione come domanda interrotta, e questa la completa).
    private func dopoTrascrizione(_ trascrizione: Task<TrascrittoOrologio, Never>, eco: String?, prima: Task<TrascrittoOrologio, Never>?) async {
        let esito = await trascrizione.value
        guard !Task.isCancelled, fase == .elaboro else { return }
        var testo = esito.testo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let eco, let t = testo { testo = Dialogo.togliEco(t, detto: eco) }
        if let prima {
            let q = (await prima.value).testo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !Task.isCancelled, fase == .elaboro else { return }
            if !q.isEmpty {
                guard let aggiunta = testo, !aggiunta.isEmpty else { chiedi(q, aVoce: true); return }   // l'aggiunta non si è capita: vale la prima
                if storia.last?["role"] == "user" { storia.removeLast() }                  // una domanda vecchia senza risposta
                storia.append(["role": "user", "content": q])                              // la prima, come domanda interrotta
                daUnire = q
                quandoDaUnire = Date()
                chiedi(aggiunta, aVoce: true)
                return
            }
        }
        // difetto 3: la frase con cui «l'aveva interrotto» era solo un rumore (dopo aver tolto la voce di JARVIS non resta nessuna
        // parola): non era il signore. JARVIS riprende la risposta da dove si era fermato
        if eco != nil, let s = sospesa {
            sospesa = nil
            if esito.vuoto || (esito.errore == nil && JarvisOrologio.soloRumore(testo ?? "")) { riprendiRisposta(s); return }
        }
        if esito.vuoto {
            compito = nil
            fase = .attesa
            stato = "Non ho sentito nulla, Sir."
            return
        }
        let errore = esito.errore
        if let testo, !testo.isEmpty {
            // build 22: i comandi a frase esatta («protocollo notte», «radar pioggia»…), prima di tutto il resto
            // «ricorda questo luogo» sul polso va al cervello: lo salva lui con la posizione dell'orologio
            if let d = ComandoDedicato.riconosci(testo), d != .salvaLuogo { dedicato(d); return }
            // build 23: le frasi esatte degli Occhi alla Stark e dei modi di LiDAR vivono sull'iPhone (fotocamera, LiDAR):
            // al polso la schermata scrive «… vive sull'iPhone, Sir.», come per «apri gli occhi»; prima andavano al cervello
            if let r = JarvisOrologio.fraseDellIPhone(testo) {
                compito = nil
                WKInterfaceDevice.current().play(.click)
                repartoRichiesto = r
                daUnire = nil
                inCorso = nil
                fase = .attesa
                return
            }
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
                daUnire = nil                          // un comando è un'azione nuova: la domanda interrotta non si porta dietro
                inCorso = nil
                // una sezione che vive sull'iPhone (Occhi, LiDAR, Trainer…): la schermata scrive «… vive sull'iPhone, Sir.»
                // e JARVIS non annuncia un'apertura che al polso non c'è (prima diceva «Occhi aperti, Sir.», «LiDAR pronto…»)
                if !JarvisOrologio.soloIPhone(reparto), let a = reparto.annuncio { parla(a) } else { fase = .attesa }
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

    /// Difetto 3: nella registrazione non c'è nessuna parola vera, solo rumore (una tosse, una risata trascritta «ahah»).
    nonisolated static func soloRumore(_ t: String) -> Bool {
        let parole = t.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let versi: Set<String> = ["ah", "ahah", "ahahah", "ahahahah", "haha", "hahaha", "hahahaha", "mh", "mmh", "mm", "hm", "hmm",
                                  "ehm", "uhm", "coff", "etciù", "etciu"]
        return parole.allSatisfy { versi.contains($0) }
    }

    /// Difetto 3: riprende la risposta fermata da un rumore. Se era già arrivata tutta, dice da solo le frasi che mancavano
    /// (dal punto esatto, `Dialogo.taglio`); se no, chiede al cervello il seguito come un «continua» (decisione 53: stesso
    /// modello, riparte dal segno d'interruzione). Prima JARVIS scriveva «Non ho capito, Sir.» e la risposta era persa.
    private func riprendiRisposta(_ s: RispostaSospesa) {
        compito = nil
        stato = nil
        if let completa = s.completa {
            let detto = TagVoce.togli(s.detto).trimmingCharacters(in: .whitespacesAndNewlines)
            let resto: String? = detto.isEmpty ? completa : Dialogo.taglio(completa, dopo: detto).map { String(completa[$0...]) }
            if let resto {
                storia = s.storia                      // il signore non l'ha interrotto: la risposta resta intera in cronologia
                daUnire = nil
                domanda = s.domanda
                risposta = completa
                rispostaGrezza = ""
                rispostaInStoria = true
                inCorso = s.domanda
                riascolta = true                       // come a fine risposta: detta tutta, riascolta da solo
                let r = resto.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !r.isEmpty else { fase = .attesa; dopoRisposta(); return }   // l'aveva già detta tutta
                iniziaFlussoVoce()
                dettoFinora = s.detto                  // se poi lo interrompe davvero, il punto del taglio resta giusto
                accodaPezzo(r)
                chiudiFlussoVoce()
                return
            }
        }
        // la risposta era ancora in arrivo (o il punto non si ritrova): il seguito dal cervello, dal segno d'interruzione
        daUnire = s.domanda
        quandoDaUnire = Date()
        chiedi("continua", aVoce: true)
        domanda = s.domanda                            // a schermo resta la sua domanda (il «continua» non l'ha detto lui)
        inCorso = s.domanda
    }

    /// Le sezioni che al polso non ci sono (servono la fotocamera, il LiDAR o lo schermo dell'iPhone): `VistaOrologio.apri`
    /// scrive «… vive sull'iPhone, Sir.» (il Trainer: «Trainer: questa sezione vive sull'iPhone, Sir.»), senza l'annuncio
    /// d'apertura; la stessa frase JARVIS la dice anche a voce (decisione 36, `diciSeSoloIPhone`).
    private static func soloIPhone(_ r: Reparto) -> Bool {
        switch r {
        case .occhi, .giro, .profiler, .wiretap, .cucina, .scanner, .foto, .browser, .messaggi, .telefono, .lidar,
             .costi, .edith, .sistemi, .impostazioni, .allenatore:
            return true
        default:
            return false
        }
    }

    /// Decisione 36 (24 ott): una sezione che vive sull'iPhone, chiesta al polso, si dice anche a voce, non solo scritta.
    /// La frase è la stessa che `VistaOrologio.apri` scrive sotto il reattore. La chiama la schermata quando arriva la
    /// richiesta (`repartoRichiesto`): vale per tutte le strade che la mandano («apri gli occhi», «modalità specchio»…).
    /// Solo se JARVIS è libero: non parla sopra un ascolto o un'altra risposta.
    func diciSeSoloIPhone(_ r: Reparto) {
        guard JarvisOrologio.soloIPhone(r), fase == .attesa else { return }
        parla(r == .allenatore ? "Trainer: questa sezione vive sull'iPhone, Sir."
                               : "\(r.rawValue.capitalized): questa sezione vive sull'iPhone, Sir.")
    }

    /// Decisione 37 (24 ott): JARVIS sta usando l'audio per parlare o ascoltare, quindi la sessione è sua (.playAndRecord o
    /// .playback): i suoni del polso (`SuoniOrologio`) in questi momenti non le cambiano categoria. Ascolto, voce (anche la
    /// frase che si sta scaricando), l'aggiunta dei 2 secondi dopo la domanda, Shazam dentro una risposta, l'avviso
    /// «la linea fa i capricci».
    var usaAudio: Bool {
        fase == .ascolto || fase == .parlo || aggiunta != nil || orecchioSospeso || fraseInVoce || sintesiInciso.isSpeaking
    }

    // MARK: Build 22: comandi a frase esatta

    /// Un comando a frase esatta: si apre la sua schermata, senza passare dal cervello (come i comandi di sempre).
    private func dedicato(_ d: ComandoDedicato) {
        compito = nil
        daUnire = nil                          // un comando è un'azione nuova: la domanda interrotta non si porta dietro
        inCorso = nil
        stato = nil
        WKInterfaceDevice.current().play(.click)
        let reparto: Reparto?
        switch d {
        case .protocollo(let p):
            polsoRichiesto = .protocolli(p)    // la schermata dei protocolli si apre e parte da sola (JARVIS non parla)
            fase = .attesa
            return
        case .traccia, .guida: polsoRichiesto = .traccia; reparto = .ricordi   // sul polso niente fotocamera: la bussola
        case .salvaLuogo: return                                              // non arriva qui (va al cervello, vedi sopra)
        case .radar: polsoRichiesto = .radar; reparto = .meteo
        case .priorita: polsoRichiesto = .priorita; reparto = .email
        case .organismo: polsoRichiesto = .organismo; reparto = .vitals   // direttamente l'Organismo, non l'elenco di Vitals
        case .ologramma, .allenamento: repartoRichiesto = .allenatore; reparto = nil   // il Trainer vive sull'iPhone: lo scrive la schermata
        case .satellite(let a): polsoRichiesto = .satellite(a); reparto = .satellite  // build 23: SATELLITE; «guidami a…» fa partire la guida
        case .fermaGuida:                                                             // build 23: la guida vive sull'iPhone: si ferma lì
            Task { @MainActor in
                // lo stato vero, dall'iPhone; se l'iPhone non risponde la guida non si può fermare da qui: lo dice
                // (prima diceva «Guida fermata, Sir.» anche se il messaggio non era arrivato e la guida continuava)
                guard await GuidaPolso.condivisa.aggiorna() else { parla("L'iPhone non risponde, Sir: lo tenga vicino."); return }
                let c_era = GuidaPolso.condivisa.dati != nil
                GuidaPolso.condivisa.ferma()
                parla(c_era ? "Guida fermata, Sir." : "Non c'è nessuna guida in corso, Sir.")
            }
            return
        }
        if let a = reparto?.annuncio { parla(a) } else { fase = .attesa }
    }

    /// Build 23: «mostra le etichette», «scansione olografica», «aggancia il bersaglio», «cerca questo sul web»… (le stesse frasi
    /// di `ComandoOcchi`, OcchiStark.swift, che è solo dell'iPhone) e i modi di LiDAR («metro laser», «mappa la stanza»…).
    private static func fraseDellIPhone(_ frase: String) -> Reparto? {
        var t = frase.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init)
        while let p = t.first, ["ehi", "ok", "hey", "jarvis", "giarvis", "jervis"].contains(p) { t.removeFirst() }
        let occhi: Set<String> = ["mostra le etichette", "togli le etichette", "scansione olografica", "disattiva l ologramma",
                                  "aggancia il bersaglio", "cerca questo sul web"]
        if occhi.contains(t.joined(separator: " ")) { return .occhi }
        if ComandoVocale.modoLidar(t) != nil { return .lidar }
        return nil
    }

    /// Decisione 39 (24 ott): la guida chiesta dal polso non è partita sull'iPhone: JARVIS dice il motivo («Non ho la sua
    /// posizione, Sir.», «Non trovo una strada a piedi fino a lì, Sir.»), che GUIDA intanto scrive. Se sta finendo una frase
    /// (l'annuncio di SATELLITE) la lascia finire; se il signore sta parlando o ha chiesto altro, il motivo resta solo scritto.
    func annunciaGuida(_ motivo: String) {
        Task { @MainActor in
            for _ in 0..<40 where fase == .parlo { try? await Task.sleep(for: .milliseconds(100)) }   // al massimo 4 secondi
            guard fase == .attesa else { return }
            parla(motivo)
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

    /// `lascia`, `soloTesto`, `ripiega`: idea D, il giro unico si ferma dopo la trascrizione (comando dell'app, testo per
    /// l'aggiunta, trascrizione fallita nel cervello).
    private enum Esito { case fine(String), nonAutorizzato, errore(String), client([String: Any]), doppione, lascia(String), soloTesto, ripiega }

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
            await aspettaFineVoce()                               // come sull'iPhone: prima finisce «Ascolto.», poi Shazam
            guard !Task.isCancelled else { return ("{\"errore\": \"interrotto dal signore\"}", true) }   // niente Shazam a domanda fermata
            stato = "ascolto la musica"
            WKInterfaceDevice.current().play(.start)
            let secondi = (input["secondi"] as? NSNumber)?.doubleValue ?? 15
            let esito = await Musica.riconosci(secondi: secondi)
            orecchioSospeso = false
            if Task.isCancelled {
                // fermato o interrotto mentre ascoltava la musica: l'audio adesso è dell'ascolto che è partito dopo, non si spegne
            } else if giaParlato {
                fase = .parlo                                     // la risposta continua a frasi: voce e orecchio come prima
                attivaAudio()
            } else {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
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

    /// `unico`: idea D, la frase parte come audio in questa stessa richiesta (la trascrizione arriva con «trascritto»).
    private func turno(nuovoTentativo: Bool, unico: (audio: Data, canale: CanaleUnico)? = nil) async {
        // idea D: chi aspetta il testo della frase (l'aggiunta) non resta mai appeso, qualunque cosa succeda qui
        defer { unico?.canale.consegna(TrascrittoOrologio(testo: nil, errore: nil, vuoto: false)) }
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
        // 25 ott, crash della 27: l'orologio (arm64_32) ha Int a 32 bit; i millisecondi dal 1970 (~1,76 bilioni) non ci stanno
        // e Int(...) chiudeva l'app appena preparata la domanda. Per «fine» si usa Int64.
        do {
            var corpo: [String: Any] = ["messaggi": storia, "dispositivo": "orologio", "strumenti_client": JarvisOrologio.strumenti]
            if let u = unico {
                // idea D: la cronologia come la preparerebbe `chiedi`, senza la domanda nuova (la aggiunge il cervello con la nota)
                corpo["messaggi"] = storiaSenzaDomanda(prima: u.canale.prima)
                corpo["audio_domanda"] = u.audio.base64EncodedString()
                corpo["formato_audio"] = "m4a"
                corpo["prefisso_domanda"] = u.canale.prima.map { JarvisOrologio.notaInterruzione($0) } ?? ""
                corpo["a_voce"] = true
                corpo["arbitro"] = ["id": ImpostazioniOrologio.idDispositivo, "fine": Int64(fineVoce.timeIntervalSince1970 * 1000)] as [String: Any]
            } else if domandaAVoce {
                // idea B: se anche il Mac (o l'iPhone) ha sentito la stessa frase, il cervello fa rispondere uno solo
                corpo["a_voce"] = true
                corpo["arbitro"] = ["id": ImpostazioniOrologio.idDispositivo, "fine": Int64(fineVoce.timeIntervalSince1970 * 1000)] as [String: Any]
            }
            let posizione = await PosizioneOrologio.attuale()      // dove si trova il signore: serve alla seconda memoria
            if let posizione { corpo["posizione"] = posizione }
            if unico == nil { iniziaFlussoVoce() }               // col giro unico la voce si prepara quando la frase è accettata
            for _ in 0..<5 {
                switch try await flussoConRitentativi(token: token, corpo: corpo, richiesta: UUID().uuidString, canale: unico?.canale) {
                case .fine(let testo):
                    guard !Task.isCancelled else { return }
                    risposta = TagVoce.togli(testo)                               // i toni della voce non si vedono
                    rispostaGrezza = ""
                    stato = nil
                    storia.append(["role": "assistant", "content": TagVoce.togli(testo)])
                    rispostaInStoria = true                                      // se ora la interrompe, qui si segna il punto
                    compito = nil
                    riascolta = true                                             // detta la risposta, riascolta da solo
                    if giaParlato { chiudiFlussoVoce() } else { parla(testo) }   // già partito a frasi: dice solo il resto
                    return
                case .nonAutorizzato:
                    if nuovoTentativo, await PonteOrologio.condiviso.chiediToken(soloDiretta: true) {
                        await turno(nuovoTentativo: false, unico: unico)   // l'iPhone aveva una parola d'ordine più recente
                    } else {
                        fallisci("La parola d'ordine non coincide, Sir. La controlli nell'app JARVIS sull'iPhone.")
                    }
                    return
                case .errore(let messaggio):
                    fallisci(messaggio)
                    return
                case .doppione:
                    doppione()                                   // idea B: risponde un altro dispositivo
                    return
                case .lascia(let testo):
                    // idea D: la frase è un comando dell'orologio (o va detta diversamente): la richiesta è già chiusa, si fa
                    // come con la strada di prima, con il testo già trascritto
                    await dopoTrascrizione(Task { TrascrittoOrologio(testo: testo, errore: nil, vuoto: false) }, eco: nil, prima: nil)
                    return
                case .soloTesto:
                    return                                       // idea D: il testo serviva all'aggiunta, che riparte da sé
                case .ripiega:
                    // idea D: il cervello non è riuscito a trascrivere: la strada di prima (le orecchie in cloud, più servizi in gara)
                    guard let u = unico else { fallisci("Non sono riuscito a trascrivere, Sir. Riprovi."); return }
                    let (testo, errore) = await JarvisOrologio.trascrivi(u.audio, token: token, indirizzo: JarvisOrologio.indirizzoAscolto)
                    let esito = TrascrittoOrologio(testo: testo, errore: errore, vuoto: false)
                    u.canale.consegna(esito)
                    if u.canale.soloTesto { return }
                    await dopoTrascrizione(Task { esito }, eco: nil, prima: nil)
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
    private func flussoConRitentativi(token: String, corpo: [String: Any], richiesta: String, canale: CanaleUnico? = nil) async throws -> Esito {
        var tentativo = 0
        while true {
            do {
                return try await flusso(token: token, corpo: corpo, richiesta: richiesta, canale: canale)
            } catch let e as URLError where JarvisOrologio.lineaCaduta(e) && tentativo < 3 {
                tentativo += 1
                risposta = ""                                 // quello arrivato a metà si butta: la risposta ricomincia intera
                rispostaGrezza = ""
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
        sintesiInciso.speak(u)
    }

    private func flusso(token: String, corpo: [String: Any], richiesta: String, canale: CanaleUnico? = nil) async throws -> Esito {
        guard let url = URL(string: ImpostazioniOrologio.indirizzo) else { return .errore("Indirizzo del cervello non valido.") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.setValue(richiesta, forHTTPHeaderField: "x-richiesta")
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (righe, resp) = try await URLSession.shared.bytes(for: req, delegate: canale?.presa)
        let codice = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if codice == 401 { return .nonAutorizzato }
        guard codice == 200 else {
            if let canale, canale.esito == nil { canale.presa.chiudi(); return .ripiega }   // idea D: la strada di prima
            return .errore("Il cervello ha risposto con un errore (codice \(codice)).")
        }

        for try await riga in righe.lines {
            try Task.checkCancellation()
            guard let dati = riga.data(using: .utf8),
                  let e = (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any],
                  let tipo = e["t"] as? String else { continue }
            switch tipo {
            case "testo":
                if let pezzo = e["d"] as? String {
                    rispostaGrezza += pezzo
                    risposta = TagVoce.togli(rispostaGrezza, inCorso: true)      // a schermo senza i toni; la voce li riceve tutti
                    stato = nil
                    accodaPezzo(pezzo)
                }
            case "stato":
                stato = e["d"] as? String
                diciPrimaDelloStrumento()                                    // punto 1: il cervello sta usando uno strumento
            case "immagini":
                let nuove = (e["d"] as? [[String: Any]] ?? []).compactMap { d -> FotoOrologio? in
                    guard let m = (d["miniatura"] ?? d["grande"]) as? String else { return nil }
                    return FotoOrologio(url: m, grande: d["grande"] as? String, pagina: d["pagina"] as? String, titolo: d["titolo"] as? String)
                }
                immagini = Array((immagini + nuove).prefix(10))
            case "fine":
                return .fine(e["testo"] as? String ?? rispostaGrezza)
            case "errore":
                return .errore(e["d"] as? String ?? "Un intoppo tecnico, Sir.")
            case "client":
                diciPrimaDelloStrumento()                                    // punto 1: tocca all'orologio eseguire uno strumento
                return .client(e)
            case "doppione":
                return .doppione
            case "trascritto":
                // idea D: la frase detta, trascritta dal cervello dentro questa stessa richiesta
                guard let canale, canale.esito == nil else { break }   // un nuovo tentativo dopo la linea caduta: già fatto
                let t = (e["d"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty, e["errore"] != nil { canale.presa.chiudi(); return .ripiega }
                canale.consegna(TrascrittoOrologio(testo: t, errore: nil, vuoto: false))
                if canale.soloTesto { canale.presa.chiudi(); return .soloTesto }
                guard accettaUnico(t, canale: canale) else { canale.presa.chiudi(); return .lascia(t) }
            default:
                break
            }
        }
        return .errore("La risposta si è interrotta a metà, Sir. Riprovi.")
    }

    // MARK: Idea D (25 ott): la frase in audio insieme alla richiesta della risposta

    /// Le orecchie in cloud della strada di prima (la funzione jarvis-ascolto).
    static var indirizzoAscolto: String {
        let base = ImpostazioniOrologio.indirizzo
        return base.hasSuffix("/jarvis") ? base + "-ascolto" : base.replacingOccurrences(of: "/jarvis", with: "/jarvis-ascolto")
    }

    /// Il cervello si sveglia (la prima domanda non paga l'avvio) e dice se sa fare il giro unico.
    nonisolated static func riscalda(token: String, indirizzo: String) async {
        guard !token.isEmpty, let url = URL(string: indirizzo) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["sveglia": true])
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        UserDefaults.standard.set(o["giro_unico"] as? Bool ?? false, forKey: "giroUnicoCervello")
    }

    /// La cronologia che `chiedi` manderebbe, senza la domanda nuova: il cervello la aggiunge con la nota, uguale.
    private func storiaSenzaDomanda(prima: String?) -> [[String: String]] {
        var base = storia
        if base.last?["role"] == "user", prima == nil { base.removeLast() }
        base.append(["role": "user", "content": ""])
        base = Array(base.suffix(12))
        while base.first?["role"] == "assistant" { base.removeFirst() }
        base.removeLast()
        return base
    }

    /// La frase trascritta va al cervello così com'è (come `dopoTrascrizione` → `chiedi(testo, aVoce: true)`)? Non se è un
    /// comando dell'orologio, una frase dell'iPhone, l'interprete, «piano»/«voce normale», un ordine di silenzio o solo «aspetta».
    private func eDomandaSemplice(_ testo: String) -> Bool {
        guard !testo.isEmpty else { return false }
        if let d = ComandoDedicato.riconosci(testo), d != .salvaLuogo { return false }
        if JarvisOrologio.fraseDellIPhone(testo) != nil { return false }
        var comando = ComandoVocale.riconosci(testo)
        if case .rapido(let a)? = comando {
            switch a {
            case .diario, .confidente: return false
            case .cucina, .riunione: comando = nil
            }
        }
        if case .apri(_)? = comando { return false }
        if case .interprete(let codice)? = comando,
           ComandoVocale.lingueAVoce.first(where: { $0.codice == codice })?.parole.first != nil { return false }
        if Dialogo.volume(testo).cambio != nil { return false }
        if Self.eSoloSilenzio(testo) || Seguito.soloAspetta(testo) { return false }
        return true
    }

    /// Idea D: la frase arrivata con «trascritto» è una domanda normale: la si accetta come farebbe `chiedi(testo, aVoce: true)`,
    /// ma senza un'altra richiesta, perché la risposta sta già arrivando in questa. Falso: si chiude e si fa come prima.
    private func accettaUnico(_ testo: String, canale: CanaleUnico) -> Bool {
        guard fase == .elaboro, eDomandaSemplice(testo) else { return false }
        let prima = Date().timeIntervalSince(quandoDaUnire) < Dialogo.validitaInterruzione ? daUnire : nil
        guard prima == canale.prima else { return false }   // nel frattempo è cambiata la domanda interrotta: la strada di prima
        sospesa = nil
        riascolta = false
        dopoAspetta = .no
        daUnire = nil
        zittisci()
        domanda = testo
        risposta = ""
        rispostaGrezza = ""
        immagini = []
        stato = nil
        fase = .elaboro
        rispostaInStoria = false
        if storia.last?["role"] == "user", prima == nil { storia.removeLast() }
        storia.append(["role": "user", "content": prima.map { JarvisOrologio.notaInterruzione($0) + testo } ?? testo])
        inCorso = testo
        storia = Array(storia.suffix(12))
        while storia.first?["role"] == "assistant" { storia.removeFirst() }
        domandaAVoce = true
        iniziaFlussoVoce()
        return true
    }

    /// Idea B (25 ott): la stessa frase l'ha sentita anche un altro dispositivo e risponde lui: l'orologio tace e torna in attesa.
    private func doppione() {
        guard !Task.isCancelled else { return }
        inCorso = nil
        compito = nil
        stato = nil
        if storia.last?["role"] == "user" { storia.removeLast() }   // la domanda la tiene chi risponde
        domanda = ""
        risposta = ""
        rispostaGrezza = ""
        riascolta = false
        zittisci()
        fase = .attesa
    }

    private func fallisci(_ messaggio: String) {
        guard !Task.isCancelled else { return }   // fermato o sostituito da una nuova domanda: non tocca nulla
        inCorso = nil
        compito = nil
        stato = nil
        // Decisione 38a (24 ott), come sull'iPhone (`concludiConErrore`): l'errore arriva a risposta già cominciata. Il pezzo
        // già arrivato resta a schermo e in cronologia con l'errore sotto; le frasi intere già in coda si dicono fino in fondo,
        // la frase rimasta a metà no, e poi JARVIS dice l'errore. Prima `parla` zittiva tutto: il pezzo spariva sotto l'errore
        // e JARVIS si interrompeva a metà frase.
        let parziale = risposta.trimmingCharacters(in: .whitespacesAndNewlines)   // già senza i toni della voce
        guard !parziale.isEmpty else {
            if storia.last?["role"] == "user" { storia.removeLast() }   // la domanda senza risposta non resta in cronologia
            risposta = messaggio
            flussoAperto = false
            parla(messaggio)
            return
        }
        risposta = parziale + "\n\n" + messaggio
        rispostaGrezza = ""
        if storia.last?["role"] == "user" { storia.append(["role": "assistant", "content": risposta]) }
        rispostaInStoria = false                       // un errore non è una risposta da completare (sull'iPhone idTurno = nil)
        if giaParlato {
            bufferFrase = ""                           // la frase rimasta a metà non si dice: si passa all'errore
            accodaFrase(messaggio)                     // dopo le frasi già in coda, nella stessa voce a frasi (la coda la legge
            flussoAperto = false                       // `leggiCoda`, che finita la coda torna in attesa come a fine risposta)
        } else {
            flussoAperto = false
            parla(messaggio)                           // nessuna frase ancora partita: si dice solo l'errore
        }
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
                if p.play() { avviaMonitor(); ecoMonitor += " " + testo; return }
                lettore = nil
            }
            let pulita = TagVoce.togli(testo)                             // la voce dell'orologio non sa dire i toni
            if pulita.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { voceFinita(); return }
            let u = AVSpeechUtterance(string: pulita)
            u.voice = AVSpeechSynthesisVoice(language: "it-IT")
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = volumeVoce
            sintesi.speak(u)
            avviaMonitor()
            ecoMonitor += " " + testo
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
        fraseInVoce = false
        orecchioSospeso = false
        fineFrase?.resume()
        fineFrase = nil
        fermaMonitor()
        lettore?.stop()
        lettore = nil
        sintesi.stopSpeaking(at: .immediate)
        sintesiInciso.stopSpeaking(at: .immediate)
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
        if dopoAspetta == .miDica {                    // detto «Mi dica, Sir»: lo ascolto, con 5 secondi per cominciare
            Task {
                try? await Task.sleep(for: .milliseconds(250))     // la coda della voce non entra nel microfono
                if fase == .attesa { await ascolta(limiteInizio: Dialogo.silenzioDopoAspetta, aspetta: .miDica) }
            }
            return
        }
        dopoRisposta()
    }

    /// «Aspetta» e poi silenzio (deciso dal signore, 24 ott): «Mi dica, Sir», poi lo ascolta. Come sull'iPhone.
    private func miDica() {
        dopoAspetta = .miDica
        riascolta = false
        parla(Dialogo.miDica)
    }

    // MARK: Voce a frasi

    private func iniziaFlussoVoce() {
        bufferFrase = ""
        giaParlato = false
        flussoAperto = true
        dettoFinora = ""
        frasiVoce = []
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
        // punto 4 (24 ott): le ultime due frasi già dette della risposta, così l'intonazione continua come sull'iPhone
        let p = frasiVoce.suffix(2).joined(separator: " ")
        let prima: String? = p.isEmpty ? nil : String(p.suffix(300))
        frasiVoce.append(frase)
        let audio = Task { await JarvisOrologio.scaricaVoce(frase, token: token, indirizzo: indirizzo, prima: prima) }   // si scarica subito, in parallelo
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

    /// Punto 1 (24 ott, approvato): il cervello si ferma per usare uno strumento (evento `stato` o `client`): la frase già
    /// scritta («Guardo.», «Ascolto.», «Un attimo, controllo.») si dice subito, come sull'iPhone, anche se è più corta dei
    /// 20 caratteri della voce a frasi. Prima restava ferma e usciva attaccata alla risposta dopo lo strumento.
    /// Solo una frase finita (punto, ! ? … :); `tutto`: anche un pezzo senza punto (prima di Shazam, come l'iPhone).
    private func diciPrimaDelloStrumento(tutto: Bool = false) {
        guard flussoAperto else { return }
        let resto = bufferFrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ultimo = resto.last, tutto || ".!?…:".contains(ultimo) else { return }
        bufferFrase = ""
        accodaFrase(resto)
    }

    /// Prima di Shazam, come sull'iPhone (`aspettaFineVoce`): finisce di dire la frase già partita («Ascolto.») e poi tace,
    /// con l'orecchio spento. Shazam non deve sentire JARVIS, e la musica della stanza non deve sembrare il signore che
    /// parla sopra: prima, con l'orecchio acceso durante il riconoscimento, la musica fermava la risposta e Shazam si perdeva.
    private func aspettaFineVoce() async {
        diciPrimaDelloStrumento(tutto: true)
        orecchioSospeso = true
        fermaMonitor()
        for _ in 0..<80 where fraseInVoce || !codaVoce.isEmpty {        // al massimo 8 secondi
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else { return }          // fermato nel frattempo: la fase è già di chi è venuto dopo
        if fase == .parlo { fase = .elaboro }            // mentre ascolta la musica il reattore pensa (come sull'iPhone)
    }

    private func leggiCoda(turno mio: Int) async {
        while mio == turnoVoce {
            if codaVoce.isEmpty {
                if !flussoAperto { break }                       // finito di scrivere e di dire
                try? await Task.sleep(for: .milliseconds(80))   // aspetta la prossima frase
                continue
            }
            let (frase, scarico) = codaVoce.removeFirst()
            fraseInVoce = true                         // si scarica o si sta dicendo (Shazam aspetta che finisca)
            defer { if mio == turnoVoce { fraseInVoce = false } }
            let audio = await scarico.value
            guard mio == turnoVoce else { return }
            if sintesiInciso.isSpeaking { sintesiInciso.stopSpeaking(at: .immediate) }   // arriva la risposta: l'avviso tace
            var partito = false
            if let audio, let p = try? AVAudioPlayer(data: audio) {
                p.delegate = self
                lettore = p
                p.volume = volumeVoce
                Volume.segui(p)
                partito = p.play()
            }
            if !partito {
                let pulita = TagVoce.togli(frase)                             // la voce dell'orologio non sa dire i toni
                if pulita.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }   // solo un tono: niente da dire
                let u = AVSpeechUtterance(string: pulita)
                u.voice = AVSpeechSynthesisVoice(language: "it-IT")
                u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = volumeVoce
                sintesi.speak(u)
            }
            avviaMonitor()
            ecoMonitor += " " + frase                  // se il signore interrompe, queste parole sono nella registrazione
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in fineFrase = c }
            if mio == turnoVoce { dettoFinora += " " + frase }   // detta fino in fondo (interrotta: turnoVoce è già cambiato)
        }
        guard mio == turnoVoce else { return }
        inCorso = nil                                  // risposta letta tutta (a frasi): da qui una frase nuova è una domanda nuova
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
        chiudiAggiunta(spegniAudio: false)                         // JARVIS risponde: l'attesa dell'aggiunta finisce qui
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
        guard conOrecchio, fase == .parlo, monitor == nil, !orecchioSospeso else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orecchio.m4a")
        try? FileManager.default.removeItem(at: url)
        // M7: la stessa qualità dell'ascolto normale: se il signore interrompe, la sua frase si trascrive da questo file
        let impostazioni: [String: Any] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        guard let r = try? AVAudioRecorder(url: url, settings: impostazioni) else { return }
        r.isMeteringEnabled = true
        guard r.record() else { return }
        monitor = r
        ecoMonitor = ""
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
        // difetto 3: prima di segnare il taglio si ricorda la risposta com'era, per riprenderla se non era lui a parlare
        let completa: String? = rispostaInStoria && storia.last?["role"] == "assistant" ? storia.last?["content"] : nil
        sospesa = inCorso.map { RispostaSospesa(domanda: $0, completa: completa, detto: dettoFinora, storia: storia) }
        segnaInterruzione()
        inCorso = nil
        // M7: la frase del signore è già nella registrazione dell'orecchio (insieme alla voce di JARVIS, che poi si toglie):
        // si continua da lì, così le parole con cui l'ha interrotto non vanno perse. Prima il microfono ripartiva da capo
        // e il signore doveva ripetere la frase.
        let preso = monitor
        let eco = ecoMonitor
        timerMonitor?.invalidate()
        timerMonitor = nil
        monitor = nil                        // così zittisci() non lo ferma
        zittisci()
        compito?.cancel()
        compito = nil
        fase = .attesa
        WKInterfaceDevice.current().play(.click)
        stato = "La ascolto, Sir…"
        if let preso, preso.isRecording { continuaAscolto(preso, eco: eco) } else { Task { await self.ascolta() } }
    }

    nonisolated static func scaricaVoce(_ testo: String, token: String, indirizzo: String, prima: String? = nil) async -> Data? {
        guard !token.isEmpty, let url = URL(string: indirizzo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        var corpo: [String: Any] = ["voce": testo]
        if let prima, !prima.isEmpty { corpo["prima"] = prima }       // punto 4: l'intonazione continua dalla frase prima
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
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

/// Una frase registrata sull'orologio, trascritta in cloud (M7: la trascrizione si può aspettare da due punti).
nonisolated struct TrascrittoOrologio: Sendable { let testo: String?; let errore: String?; let vuoto: Bool }

/// Idea D (25 ott): la frase partita col giro unico. La sua trascrizione arriva dentro la risposta del cervello: qui la
/// aspetta chi ne ha bisogno (l'aggiunta dei 2 secondi), e qui c'è la presa per chiudere la richiesta.
@MainActor
final class CanaleUnico {
    private(set) var esito: TrascrittoOrologio?
    private var attese: [CheckedContinuation<TrascrittoOrologio, Never>] = []
    /// La domanda interrotta quando la frase è partita (la sua nota va davanti alla frase).
    var prima: String?
    /// Il signore ha aggiunto subito un'altra frase: questa serve solo come testo, la risposta non si aspetta.
    var soloTesto = false
    let presa = PresaRete()

    func attendi() async -> TrascrittoOrologio {
        if let esito { return esito }
        return await withCheckedContinuation { (c: CheckedContinuation<TrascrittoOrologio, Never>) in attese.append(c) }
    }

    /// La trascrizione (la prima che arriva vale; le altre si ignorano).
    func consegna(_ e: TrascrittoOrologio) {
        guard esito == nil else { return }
        esito = e
        let chi = attese
        attese = []
        for c in chi { c.resume(returning: e) }
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
