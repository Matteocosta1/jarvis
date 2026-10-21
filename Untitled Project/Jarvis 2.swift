import Foundation
import Combine
import AVFoundation
import Speech
import Security
import CryptoKit
import UIKit

// MARK: - Modello

struct Messaggio: Identifiable, Codable, Equatable {
    var id = UUID()
    let ruolo: String          // "user" oppure "assistant"
    var testo: String
    var azioni: [String] = []
    var data = Date()
    var conFoto = false
    var immagini: [Immagine]? = nil   // galleria sotto la risposta (web, Discogs, Shazam, foto del signore)
    var aggiunta: Bool? = nil         // il signore completa la richiesta precedente («Jarvis, aspetta, ascoltami…»)
    var seguito: Bool? = nil          // riprende il discorso poco dopo: forse completa il pensiero di prima, decide il cervello

    /// Come il messaggio viene ricordato al cervello nei turni successivi (solo testo).
    var testoPerCervello: String {
        let base = conFoto ? "(il signore ha mandato una foto) \(testo)" : testo
        if aggiunta == true { return "(aggiunta alla mia richiesta precedente, considerala insieme a quella) \(base)" }
        if seguito == true {
            return "(riprendo il discorso: se questo completa o aggiunge qualcosa a quello che ti ho detto prima, rispondi tenendo conto di entrambe le cose; se è un argomento nuovo, rispondi solo a questo) \(base)"
        }
        return base
    }
}

enum Fase: String {
    case attesa = "IN ATTESA"
    case ascolto = "LA ASCOLTO"
    case elaboro = "ELABORO"
    case parlo = "PARLO"
}

enum Impostazioni {
    static let indirizzoPredefinito = "https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis"
    static var indirizzo: String { UserDefaults.standard.string(forKey: "indirizzo") ?? indirizzoPredefinito }
    static var voce: String { UserDefaults.standard.string(forKey: "voce") ?? "" }
    static var muto: Bool { UserDefaults.standard.bool(forKey: "muto") }
    /// Voce di JARVIS in cloud (ElevenLabs, tramite il cervello). Se non risponde, ripiega sulla voce dell'iPhone.
    static var voceCloud: Bool { UserDefaults.standard.bool(forKey: "voceCloud") }
    static var idVoceCloud: String { UserDefaults.standard.string(forKey: "idVoceCloud") ?? "" }
    /// Mentre JARVIS parla, l'iPhone ascolta: «Jarvis», «basta», «aspetta» lo interrompono.
    static var interruzioneVocale: Bool { UserDefaults.standard.object(forKey: "interruzioneVocale") as? Bool ?? true }
    /// In attesa, con l'app aperta, basta dire «Jarvis» per parlargli: niente tocco.
    static var richiamo: Bool { UserDefaults.standard.object(forKey: "richiamo") as? Bool ?? true }
    /// In attesa risponde a qualsiasi frase del signore, senza bisogno di «Jarvis» (spento: solo «Jarvis», «ehi», «bro»…).
    static var ascoltoSempre: Bool { UserDefaults.standard.object(forKey: "ascoltoSempre") as? Bool ?? !ProcessInfo.processInfo.isiOSAppOnMac }
    /// La stessa app gira anche sul Mac (chip Apple): il cervello lo sa e risponde da Mac.
    nonisolated static var dispositivo: String { ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : "iphone" }
}

// MARK: - Portachiavi (la parola d'ordine non sta in chiaro)

enum Portachiavi {
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

enum ErroreJarvis: LocalizedError {
    case indirizzo
    nonisolated var errorDescription: String? { "L'indirizzo nelle impostazioni non è valido." }
}

// MARK: - JARVIS

@MainActor
final class Jarvis: NSObject, ObservableObject {
    @Published var messaggi: [Messaggio] = []
    @Published var chiudiChiesto = false          // «Jarvis, chiudi» / «torna»: la schermata principale chiude quello che è aperto
    @Published var micOccupato = false            // una schermata usa il microfono per conto suo (La mia voce): il richiamo tace
    /// La frase detta dentro Occhi o Cucina: parte con la foto scattata a voce.
    private var domandaOcchi: String?
    @Published var svuotaChiesto = false          // «Nuova conversazione» dalle Impostazioni: la schermata principale svuota la chat con l'animazione
    @Published var fase: Fase = .attesa { didSet { if fase != oldValue { aggiornaRichiamo() } } }
    @Published var parziale = ""
    @Published var stato: String?          // es. «cerco sul web»
    @Published var avviso: String?
    @Published var foto: Data?             // foto in attesa di essere mandata col prossimo messaggio
    private var fotoGiro: [Data] = []      // fotogrammi di un giro con gli occhi, in attesa del prossimo messaggio
    private var allegato: String?          // un testo lungo (la trascrizione del Wiretap) che parte col prossimo messaggio
    @Published var repartoRichiesto: Reparto?   // comando vocale: la schermata apre questo reparto
    @Published var azioneLidar: ComandoVocale.AzioneLidar?   // comando vocale dentro LiDAR: lo esegue la sua schermata
    var lidarAperto = false                      // LiDAR aperto: valgono anche i suoi comandi («salva», «fine scansione»…)
    var sezioneAperta: Reparto?                  // la scheda aperta sopra la schermata principale: valgono anche i suoi tasti a voce
    @Published var diagnosiMac = ""             // Mac: la riga di controllo del microfono in attesa
    private var fraseAVoce = ""            // l'ultima frase detta a voce, in viaggio verso il cervello
    /// Sul Mac l'ascolto non usa il riconoscimento di Apple: registra e trascrive in cloud (AscoltoCloud.swift).
    nonisolated static var usaAscoltoCloud: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
    private let registratore = RegistratoreVoce()
    /// Sul Mac, in attesa: battiti di mani e frasi trascritte in cloud, al posto del richiamo di Apple.
    private lazy var attesaMac: AttesaMac = {
        let a = AttesaMac(motore: motore)          // un solo motore audio sul Mac, quello che funziona già per il tocco
        a.applauso = { [weak self, weak a] in a?.segnaBattiti(); self?.applaudito() }
        a.diagnosi = { [weak self] riga in self?.diagnosiMac = riga }
        a.frase = { [weak self] testo, inizio in self?.fraseSentitaMac(testo, inizio: inizio) }
        return a
    }()
    /// Sul Mac, subito dopo una risposta: per qualche secondo si può continuare a parlare senza dire «Jarvis».
    private var liberoMacFinoA = Date.distantPast
    /// Mac: ciò che JARVIS ha appena detto, per riconoscere la propria voce che rientra dal microfono (l'eco).
    private var dettoMac = ""
    private var dettoMacFino = Date.distantPast
    private var ascoltoCloud = false       // sta registrando una frase da trascrivere in cloud
    private var ultimaFraseAVoce = ""      // la frase della domanda in corso (vuota se scritta)
    @Published var pagina: PaginaWeb?      // pagina aperta nel browser interno
    @Published var occhi: Occhiata? { didSet { if (occhi == nil) != (oldValue == nil) { aggiornaRichiamo() } } }   // fotocamera aperta (occhi di JARVIS)
    @Published var interprete: Lingua?     // modalità interprete aperta
    @Published var allenatore = false      // modalità allenatore aperta
    private var attesaOcchi: CheckedContinuation<[Data], Never>?

    let strumenti = Strumenti()

    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let motore = AVAudioEngine()
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timerSilenzio: Timer?
    private var timerTetto: Timer?
    private var baseAscolto = ""           // quanto detto prima che il riconoscimento ripartisse da capo
    private var precedenteAscolto = ""
    private var ultimoParzialeAscolto = Date.distantPast         // la frase dura al massimo un minuto (limite del riconoscimento vocale di Apple)
    private var turnoAscolto = 0           // ogni ascolto ha il suo numero: i callback di un ascolto vecchio vengono ignorati

    private let sintesi = AVSpeechSynthesizer()
    private var bufferVoce = ""
    private var inCoda: Set<ObjectIdentifier> = []   // frasi consegnate alla sintesi e non ancora finite
    private var frasiVive: [ObjectIdentifier: AVSpeechUtterance] = [:]   // tenute in vita finché il delegato risponde (id mai riciclati)
    private var flussoFinito = true
    private var rispostaIniziata = false     // la voce ha già cominciato a dire la risposta in corso
    private var compitoRete: Task<Void, Never>?
    private let cloud = VoceCloud()
    private var vocePerCloud = false    // decisa a inizio discorso: tutte le frasi passano dalla stessa voce, in ordine
    private let richiamo = Richiamo()   // in attesa: «Jarvis, …» e lui ascolta, senza toccare
    private var avvioRichiamo: Task<Void, Never>?
    /// La schermata principale è in primo piano, senza fotocamera, interprete o altre schede aperte (lo decide ContentView).
    /// Qualcosa è aperto sopra la schermata principale (lo dice ContentView): prima di aprire Occhi si chiude.
    var schermataAperta = false
    /// Il Tocco d'aiuto di Bea (emergenza) è aperto: niente lo copre, nemmeno Occhi.
    var soccorsoAperto = false
    var richiamoConsentito = false { didSet { if richiamoConsentito != oldValue { aggiornaRichiamo() } } }
    /// Durante la sequenza d'avvio il microfono resta spento: aprirlo cambia l'audio dell'iPhone e la musica uscirebbe bassa.
    var avvioInCorso = true { didSet { if avvioInCorso != oldValue { aggiornaRichiamo() } } }
    private let orecchio = Orecchio()   // ascolta mentre JARVIS parla: «Jarvis», «basta»… lo interrompono
    private var compitoPonte: Task<Void, Never>?   // la frase «ponte» se il cervello tarda a rispondere
    private var ultimoPonte = Date.distantPast     // quando ha detto l'ultima frase ponte
    private var rispostaInterrotta: UUID?          // la risposta che il signore ha appena interrotto (per unire l'aggiunta)
    private var quandoInterrotto: Date?
    private var ultimoInvio = Date.distantPast
    /// La memoria visiva di JARVIS: l'ultima foto (o il giro) che ha visto e il messaggio a cui appartiene.
    /// La storia mandata al cervello è solo testo; senza questo, se il signore interrompe la descrizione, la foto
    /// sparisce. Così riparte al suo posto nella conversazione, e grazie alla cache del cervello costa circa
    /// un decimo di una foto nuova finché se ne parla. Resta finché arriva una foto nuova, per 10 minuti di silenzio.
    private var fotoRecenti: [Data] = []
    private var idFotoRecente: UUID?
    private var quandoFotoRecenti = Date.distantPast       // quando è partita l'ultima richiesta al cervello
    private var aggiuntaInArrivo = false           // ha detto solo «aspetta, ascoltami»: la prossima frase completa la richiesta

    /// Frasi brevi dette subito se il cervello non ha ancora iniziato a parlare dopo un secondo: la risposta sembra istantanea.
    static let ponti = [
        "Vediamo, Sir.", "Un attimo, Sir.", "Ci penso.", "Subito, Sir.", "Mi dia un istante.",
        "Un momento, Sir.", "Me ne occupo.", "Controllo subito.", "Lasci fare a me.", "Ci siamo quasi.",
        "Ricevuto, Sir.", "Ci guardo.", "Verifico, Sir.", "Con piacere.", "Mi metto all'opera.",
        "Sto raccogliendo i dati.", "Un istante soltanto.", "Lo trovo subito.", "Certamente, Sir.", "Ah, interessante.",
        "Ottima domanda, Sir.", "Lasci che ci pensi.", "Consulto i miei archivi.", "Ho capito, un momento.", "Ci sto lavorando.",
        "Interessante, vediamo.", "Faccio due conti.", "Arrivo, Sir.", "Elaboro, Sir.", "Un secondo e ci sono.",
        "Sto incrociando i dati.", "Mmh, vediamo un po'.", "Giusto, verifico.", "Mi lasci controllare.", "Recupero le informazioni.",
        "Ricevuto, ci penso io.", "Ah, bella questa.", "Subito, controllo.", "Un attimo che guardo.", "Bene, vediamo cosa trovo.",
        "Ci rifletto un istante.", "Lo metto subito a fuoco.", "Dunque, vediamo.", "Sto mettendo insieme i pezzi.",
        "Ho quasi tutto, Sir.", "Un istante, sto verificando.", "Bella domanda, ci arrivo.", "Analizzo, Sir.",
    ]
    /// Quanto ci mette di solito il cervello a dire la prima parola (media mobile, in secondi): decide quale riempitivo usare.
    private var latenzaMedia: Double = UserDefaults.standard.object(forKey: "latenzaMedia") as? Double ?? 1.5
    private var inizioTurno: Date?
    private static var ultimoPonte = ""
    /// Una frase a caso, mai la stessa due volte di fila.
    static func ponteCasuale() -> String {
        let scelta = ponti.filter { $0 != ultimoPonte }.randomElement() ?? "Un attimo, Sir."
        ultimoPonte = scelta
        return scelta
    }

    override init() {
        super.init()
        sintesi.delegate = self
        Task { await Jarvis.riscalda() }                                 // il cervello si sveglia mentre il signore guarda lo schermo
        if Impostazioni.voceCloud { cloud.prepara(Jarvis.ponti) }       // le frasi ponte sono già pronte in cache, a costo zero
        cloud.finita = { [weak self] chiave in self?.fraseFinita(chiave) }
        orecchio.interrotto = { [weak self] resto in self?.interrottoAVoce(resto) }
        orecchio.zittisci = { [weak self] in self?.zittisciPerAscolto() }
        richiamo.sveglia = { [weak self] in self?.richiamato() }
        richiamo.testo = { [weak self] t in if self?.fase == .ascolto { self?.parziale = t } }
        richiamo.consegna = { [weak self] frase in self?.fraseRichiamo(frase) }
        richiamo.applauso = { [weak self] in self?.applaudito() }
        strumenti.apriOcchi = { [weak self] automatico, video, zoom in
            guard let self else { return [] }
            return await self.apriOcchi(automatico: automatico, video: video, zoom: CGFloat(zoom))
        }
        strumenti.apriPagina = { [weak self] url in self?.pagina = PaginaWeb(url: url) }
        strumenti.domandaOcchi = { [weak self] in self?.prendiDomandaOcchi() }
        // mentre la tastiera è aperta il battito di mani non conta (i click dei tasti lo ingannerebbero)
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            BattitoMani.tastieraAperta(true)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            BattitoMani.tastieraAperta(false)
        }
        carica()
    }

    // MARK: Interazione

    func toccaReattore() {
        fermaBenvenuto()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Suoni.tocco()
        switch fase {
        case .attesa: Task { await avviaAscolto(bip: true) }
        case .ascolto:
            if ascoltoCloud { chiudiAscoltoCloud(turno: turnoAscolto) } else { fermaAscolto(invia: true) }   // Mac: toccato = ho finito
        case .parlo, .elaboro:
            segnaInterruzione()
            interrompi()                    // lo zittisce e ascolta subito
            Task { await avviaAscolto(bip: true) }
        }
    }

    func ascoltaSubito() {
        guard fase == .attesa else { return }
        Task { await avviaAscolto() }
    }

    /// Il signore ha iniziato a parlare mentre JARVIS parlava: JARVIS tace all'istante e resta in ascolto
    /// (l'orecchio continua a raccogliere la frase e la consegna a `interrottoAVoce` quando è finita).
    private func zittisciPerAscolto() {
        segnaInterruzione()                 // prima di cambiare fase: serve per legare quello che sta per dire alla domanda di prima
        compitoPonte?.cancel()
        compitoRete?.cancel()
        compitoRete = nil
        occhiChiusi([])
        sintesi.stopSpeaking(at: .immediate)
        cloud.ferma()
        bufferVoce = ""
        inCoda.removeAll()
        flussoFinito = true
        stato = "La ascolto, Sir…"
        strumenti.annullaInSospeso()
        orecchio.testoDetto = ""
        fase = .ascolto
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Il signore ha detto «Jarvis», «basta», «aspetta»… mentre JARVIS parlava, oppure ha finito la frase con cui l'ha interrotto.
    private func interrottoAVoce(_ resto: String) {
        segnaInterruzione()
        interrompi()
        fase = .attesa
        stato = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if Jarvis.eSoloSilenzio(resto) { aggiuntaInArrivo = false; return }   // «muto», «basta», «Jarvis, zitto»: resta in attesa
        let (pulito, chiedeAggiunta) = Jarvis.togliRichiamo(resto)
        if chiedeAggiunta { aggiuntaInArrivo = true }
        if eseguiComando(pulito) { aggiuntaInArrivo = false; return }
        if !pulito.isEmpty {
            Task { await instrada(resto) }    // ha detto cosa vuole: «Jarvis, che ore sono», «aspetta, e anche…»
        } else if chiedeAggiunta {
            Task { await avviaAscolto() }     // «aspetta, ascoltami» e poi silenzio: lo ascolto ancora, senza bip
        } else {
            aggiuntaInArrivo = false          // «basta», «zitto», «stop»: tace e torna in attesa, come una persona
        }
    }

    /// Ricorda quale risposta il signore sta interrompendo: se poi aggiunge qualcosa, va unito alla domanda di prima.
    private func segnaInterruzione() {
        guard fase == .parlo || fase == .elaboro, let ultimo = messaggi.last, ultimo.ruolo == "assistant" else { return }
        rispostaInterrotta = ultimo.id
        quandoInterrotto = Date()
    }

    /// «Muto», «stop», «basta», «zitto», «Jarvis, basta», «stai zitto», «fermati»: la frase è solo un ordine di silenzio.
    /// Serve quando il signore parla con qualcun altro: JARVIS tace, non risponde e torna in attesa.
    nonisolated static func eSoloSilenzio(_ frase: String) -> Bool {
        let parole = frase.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        guard !parole.isEmpty, parole.count <= 6 else { return false }
        let silenzio: Set<String> = ["muto", "muta", "zitto", "zitta", "basta", "stop", "fermati", "fermo", "silenzio", "taci", "shh", "sst"]
        let contorno: Set<String> = ["ok", "okay", "ehi", "hey", "dai", "adesso", "ora", "per", "favore", "stai", "sta", "fai", "e", "ho", "detto",
                                     "grazie", "va", "bene", "così", "cosi", "un", "attimo", "aspetta", "mettiti", "in", "attesa", "the", "please"]
        guard parole.contains(where: { silenzio.contains($0) }) else { return false }
        return parole.allSatisfy { p in silenzio.contains(p) || contorno.contains(p) || Richiamo.nomi.contains(where: { p.hasPrefix($0) }) }
    }

    /// Tace, non risponde e torna in attesa (ordine di silenzio).
    private func mettiInAttesa() {
        segnaInterruzione()
        interrompi()
        fase = .attesa
        stato = nil
        parziale = ""
        aggiuntaInArrivo = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Parole di richiamo all'inizio della frase: «Jarvis», «aspetta», «ascoltami»…
    /// Restituisce la frase senza richiamo e se il signore sta chiaramente completando la richiesta di prima.
    nonisolated static func togliRichiamo(_ frase: String) -> (String, Bool) {
        let richiami = ["jarvis", "giarvis", "ehi", "hey", "bro", "fratello", "frate", "socio", "amico", "capo", "aspetta", "aspetti", "ascoltami", "mi ascolti", "ascolta", "un attimo",
                        "un momento", "fermati", "senti", "scusa", "no", "ah", "ok", "allora"]
        let segnaliAggiunta = ["aspetta", "aspetti", "ascoltami", "mi ascolti", "ascolta", "un attimo", "un momento"]
        let attacchi = ["aggiungo", "volevo aggiungere", "dimenticavo", "e poi", "inoltre", "anche", "un'altra cosa", "e anche"]
        var t = frase.trimmingCharacters(in: .whitespacesAndNewlines)
        var aggiunta = false
        var cambiato = true
        while cambiato {
            cambiato = false
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:…-"))
            let basso = t.lowercased()
            for r in richiami where basso.hasPrefix(r) {
                let dopo = basso.dropFirst(r.count)
                guard dopo.isEmpty || !(dopo.first!.isLetter) else { continue }   // «ascoltami» non è «ascolta» + «mi»
                if segnaliAggiunta.contains(r) { aggiunta = true }
                t = String(t.dropFirst(r.count))
                cambiato = true
                break
            }
        }
        let basso = t.lowercased()
        if attacchi.contains(where: { basso.hasPrefix($0 + " ") || basso == $0 }) { aggiunta = true }
        return (t, aggiunta)
    }

    /// Decide se la frase è una domanda nuova o il completamento della precedente, e la manda al cervello.
    private func instrada(_ fraseIntera: String) async {
        let frase = sottovoce(fraseIntera)
        if frase.isEmpty { return }
        if Jarvis.eSoloSilenzio(frase) { mettiInAttesa(); return }   // stava parlando con qualcun altro: «Jarvis, muto»
        // nel Confidente con la conversazione incollata: la frase è la domanda su quella conversazione («ho esagerato io?»)
        if let domanda = ConfidenteAperto.domanda, domanda(Jarvis.togliRichiamo(frase).0) { return }
        // dentro Occhi o Cucina: la frase fa scattare la foto e parte insieme a lei («Jarvis, guarda là in fondo»)
        if occhi != nil, let scatta = OcchiAperti.scatta {
            let detta = Jarvis.togliRichiamo(frase).0
            domandaOcchi = detta.isEmpty ? nil : detta
            if !scatta() { domandaOcchi = nil }          // lo scatto non è partito: la frase non resta in giro
            return
        }
        fraseAVoce = ""
        let (pulito, chiede) = Jarvis.togliRichiamo(frase)
        if chiede && pulito.isEmpty {                 // solo «aspetta, ascoltami»: lo riascolto, la frase vera arriva adesso
            aggiuntaInArrivo = true
            await avviaAscolto()
            return
        }
        let recente = (quandoInterrotto.map { Date().timeIntervalSince($0) < 120 } ?? false)
        // l'ha fermato pochi secondi dopo aver finito di parlare: non aveva finito il pensiero, è il seguito
        let continua = rispostaInterrotta != nil && (quandoInterrotto ?? .distantPast).timeIntervalSince(ultimoInvio) < 2.5   // 2 s + il tempo che il riconoscimento impiega a sentirlo
        let aggiunta = (chiede || aggiuntaInArrivo || continua) && !pulito.isEmpty
        aggiuntaInArrivo = false
        defer { rispostaInterrotta = nil; quandoInterrotto = nil }
        guard aggiunta else {
            // non ha detto «aspetta» ma riprende il discorso: dopo avermi interrotto, o entro un minuto dalla sua ultima frase.
            // Non lo tronco e non lo forzo: lo segno come possibile seguito e il cervello capisce se completa il pensiero di prima.
            let ultimaDomanda = messaggi.last(where: { $0.ruolo == "user" })
            let vicino = ultimaDomanda.map { Date().timeIntervalSince($0.data) < 60 } ?? false
            fraseAVoce = pulito.isEmpty ? frase : pulito   // solo una frase nuova e intera: se era un comando storpiato, si impara
            await invia(frase, comeSeguito: rispostaInterrotta != nil || vicino)
            return
        }
        // interrotta a metà: la domanda di prima e l'aggiunta diventano una sola richiesta, la risposta tagliata sparisce
        if recente, let idR = rispostaInterrotta, let iR = messaggi.lastIndex(where: { $0.id == idR }),
           iR > 0, messaggi[iR - 1].ruolo == "user", !messaggi[iR - 1].conFoto {
            let domanda = messaggi[iR - 1].id
            await invia(pulito, unisciA: domanda)
            return
        }
        // la risposta era già finita (o c'era una foto): la mando come aggiunta, il cervello la lega a quella di prima
        let ultimaDomanda = messaggi.last(where: { $0.ruolo == "user" })
        if let u = ultimaDomanda, Date().timeIntervalSince(u.data) < 300 {
            await invia(pulito, comeAggiunta: true)
        } else {
            await invia(pulito)
        }
    }

    // MARK: Richiamo («Jarvis» in attesa)

    /// Acceso solo in attesa, con l'app in primo piano e nulla aperto sopra; spento in ogni altro momento.
    /// In attesa e mentre pensa (prima che inizi a parlare): «Jarvis» lo chiama o lo ferma. Mentre parla c'è l'orecchio.
    private var richiamoServe: Bool {
        !inBenvenuto && !avvioInCorso && Impostazioni.richiamo && richiamoConsentito && (fase == .attesa || (fase == .elaboro && !orecchio.attivo))
            && !(occhi != nil && fase == .elaboro)      // Occhi aperti dal cervello, che aspetta la foto: lì non si interrompe
    }

    private func aggiornaRichiamo() {
        if Jarvis.usaAscoltoCloud {                      // Mac: l'attesa la fa AttesaMac (battiti e frasi in cloud)
            avvioRichiamo?.cancel()
            // sul Mac sente anche mentre JARVIS parla o pensa (come l'orecchio dell'iPhone): così gli si parla sopra
            let serve = !inBenvenuto && !avvioInCorso && Impostazioni.richiamo && richiamoConsentito && fase != .ascolto
                && !(occhi != nil && fase == .elaboro)          // Occhi aperti dal cervello, che aspetta la foto: lì non si interrompe
            guard serve else { attesaMac.ferma(); return }
            guard !attesaMac.attivo else { return }
            avvioRichiamo = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))       // dopo che la voce di JARVIS ha liberato l'audio
                guard let self, !Task.isCancelled, !self.inBenvenuto, self.fase != .ascolto else { return }
                self.attesaMac.avvia()
            }
            return
        }
        if richiamo.sveglio { return }                   // sta raccogliendo la frase dopo «Jarvis»: non lo tocco
        avvioRichiamo?.cancel()
        guard richiamoServe else { richiamo.ferma(); return }
        guard !richiamo.attivo else { return }
        // in attesa un attimo di respiro (il segnale «pronto» finisce); mentre pensa, subito
        let ritardo = fase == .attesa ? 450 : 100
        avvioRichiamo = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(ritardo))
            guard let self, !Task.isCancelled, self.richiamoServe else { return }
            self.richiamo.avvia()
        }
    }

    /// Ha sentito «Jarvis»: reattore in ascolto, il richiamo continua a raccogliere la frase.
    private func richiamato() {
        if fase == .elaboro {                            // stava pensando: lo fermo, come un'interruzione
            segnaInterruzione()
            interrompi()
        }
        if Jarvis.usaAscoltoCloud {
            // sul Mac la frase dopo «Jarvis» la registra JARVIS e la trascrive in cloud: si parte dagli ultimi 2 secondi
            // già sentiti (dentro c'è «Jarvis» e l'inizio della domanda; il nome poi si toglie da solo)
            avviso = nil
            parziale = ""
            Task { await avviaAscolto(dalNome: true) }
            return
        }
        avviso = nil
        parziale = ""
        stato = nil
        fase = .ascolto
        // chiamato a voce: niente bip, come una persona che si gira ad ascoltare (vibrazione leggera e reattore acceso)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Il rito di Tony: due battiti di mani + «Wake up, daddy's home», in qualsiasi ordine, a meno di 8 secondi l'uno dall'altra.
    /// Arrivati tutti e due: i Clash per qualche secondo, poi il saluto. Da soli: i battiti danno il segnale «pronto» e aspettano
    /// la frase (che passa anche senza «Jarvis»); la frase aspetta i battiti e, se non arrivano, il rito parte lo stesso.
    private var inBenvenuto = false
    private var ultimiBattiti = Date.distantPast
    private var ultimaFraseTony = Date.distantPast
    private static let finestraRito: TimeInterval = 8

    private var compitoBenvenuto: Task<Void, Never>?
    private var attesaBattiti: Task<Void, Never>?

    /// Due battiti di mani.
    private func applaudito() {
        guard fase == .attesa, !inBenvenuto else { return }
        if Date().timeIntervalSince(ultimaFraseTony) < Jarvis.finestraRito { benvenuto(); return }
        ultimiBattiti = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Suoni.pronto()                               // «pronto»: ora la frase
        mostraRito("👏👏  Sì, Sir?")
        attesaBattiti?.cancel()
        attesaBattiti = Task { [weak self] in       // se la frase non arriva (o il riconoscimento non la capisce) parte lo stesso
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.ultimiBattiti != .distantPast else { return }
            self.benvenuto()
        }
    }

    /// Una riga sullo schermo per qualche secondo: così si vede che JARVIS ha sentito (battiti o frase).
    private func mostraRito(_ testo: String) {
        stato = testo
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if self?.stato == testo { self?.stato = nil }
        }
    }

    /// «Wake up, daddy's home».
    private func fraseDiTony() {
        guard !inBenvenuto else { return }
        // i battiti si sentono solo con il richiamo acceso: senza, basta la frase
        let maniAccese = Impostazioni.richiamo && (UserDefaults.standard.object(forKey: "battitoMani") as? Bool ?? true)
        if !maniAccese || Date().timeIntervalSince(ultimiBattiti) < Jarvis.finestraRito { benvenuto(); return }
        ultimaFraseTony = Date()                     // aspetto i battiti…
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Suoni.pronto()
        mostraRito("Daddy's home… 👏👏?")
        attesaBattiti?.cancel()
        attesaBattiti = Task { [weak self] in       // …ma se non arrivano, il rito parte lo stesso: la frase non va mai persa
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.ultimaFraseTony != .distantPast else { return }
            self.benvenuto()
        }
    }

    /// Il rito è completo: i Clash, poi il saluto.
    private func benvenuto() {
        guard fase == .attesa, !inBenvenuto else { return }
        attesaBattiti?.cancel()
        ultimiBattiti = .distantPast
        ultimaFraseTony = .distantPast
        inBenvenuto = true
        aggiornaRichiamo()                           // mentre suona la musica non ascolta: le parole del pezzo non sono domande
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        compitoBenvenuto = Task {
            _ = await Benvenuto.suona()
            guard !Task.isCancelled, inBenvenuto else { return }   // interrotto: ci ha già pensato fermaBenvenuto()
            inBenvenuto = false
            compitoBenvenuto = nil
            if fase == .attesa { leggi(Benvenuto.saluto()) }        // finito il saluto torna in attesa e il richiamo riparte da solo
            try? await Task.sleep(for: .seconds(1))
            if fase == .attesa { aggiornaRichiamo() } // modalità silenziosa: nessuna voce, il richiamo va riacceso a mano
        }
    }

    /// Il rito si ferma subito (tocco sul reattore, una domanda, un avviso): musica spenta, niente saluto.
    private func fermaBenvenuto() {
        attesaBattiti?.cancel()
        guard inBenvenuto else { return }
        compitoBenvenuto?.cancel()
        compitoBenvenuto = nil
        Benvenuto.ferma()
        inBenvenuto = false
        aggiornaRichiamo()
    }

    /// La frase dopo «Jarvis» è finita: comando, domanda, oppure (solo «Jarvis») l'ascolto normale.
    private func fraseRichiamo(_ frase: String) {
        guard fase == .ascolto, !ascoltoCloud else { return }   // sul Mac la frase la sta già registrando l'ascolto in cloud
        parziale = ""
        fase = .attesa
        let testo = frase.trimmingCharacters(in: .whitespacesAndNewlines)
        if testo.isEmpty { return }                     // ha detto solo «Jarvis» e poi nulla: torno in attesa
        if foto == nil, eseguiComando(testo) { return }
        Task { await instrada(testo) }
    }

    // MARK: Comandi vocali

    // MARK: Sottovoce («Jarvis, piano, …»)

    /// «Piano» (entro le prime cinque parole): JARVIS risponde sottovoce (in chiesa, in riunione, con qualcuno che dorme…) per 10 minuti,
    /// e ogni «piano» li rinnova. «Voce normale» (o «parla normale», «alza la voce») torna come prima.
    private static var sottovoceFino = Date.distantPast
    static var volumeVoce: Float { Date() < sottovoceFino ? 0.05 : 1 }   // sottovoce: appena udibile, da vicino

    /// Toglie «piano» dalla frase (e accende il sottovoce) o riconosce «voce normale»; restituisce il resto della frase.
    private func sottovoce(_ frase: String) -> String {
        let basso = frase.lowercased()
        if ["voce normale", "parla normale", "alza la voce", "torna normale"].contains(where: { basso.contains($0) }), basso.count < 40 {
            Jarvis.sottovoceFino = .distantPast
            stato = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return ""
        }
        var parole = frase.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let pulita: (String) -> String = { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard let k = parole.prefix(5).firstIndex(where: { ["piano", "sottovoce"].contains(pulita($0)) }) else { return frase }
        parole.remove(at: k)
        Jarvis.sottovoceFino = Date().addingTimeInterval(600)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let resto = parole.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!"))
        if resto.isEmpty { stato = "🤫 Sottovoce"; return "" }
        return resto
    }

    /// Se la frase è un comando («attiva la Sentinella», «apri il Wiretap», «fai un giro»), apre il reparto e risponde vero.
    @discardableResult
    func eseguiComando(_ fraseIntera: String) -> Bool {
        let frase = sottovoce(fraseIntera)
        if frase.isEmpty { return true }                    // solo «sbatti» o «voce normale»: fatto
        if Benvenuto.eFraseDiTony(frase) { fraseDiTony(); return true }
        // le storpiature già imparate (Storpiature.swift): «backup daddy» è il rito, «apri il diavolo» è il diario…
        if let imparato = Storpiature.cerca(frase) {
            if imparato == "rito" { fraseDiTony(); return true }
            if let r = Reparto(rawValue: imparato) { apriReparto(r); return true }
        }
        if BrowserVoce.aperto, BrowserVoce.comando(Jarvis.togliRichiamo(frase).0) { return true }   // nel Browser: «scrivi …», «invia»
        if LidarAperta.aperta, LidarAperta.eRifai(frase) {                // in LiDAR: «rifai la scansione»
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            NotificationCenter.default.post(name: .jarvisRifaiLidar, object: nil)
            return true
        }
        let dentro: Reparto? = occhi != nil ? .occhi : (lidarAperto ? .lidar : sezioneAperta)
        switch ComandoVocale.riconosci(frase, dentro: dentro) {
        case .apri(let reparto)?:
            apriReparto(reparto)
            return true
        case .torna?:
            if Jarvis.eSoloSilenzio(frase) { return false }          // «basta», «stop»: restano un ordine di silenzio
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            chiudiChiesto = true
            return true
        case .lidar(let azione)?:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            azioneLidar = azione
            return true
        case .interprete(let codice)? where !lidarAperto:
            apriInterprete(codice)
            return true
        case .rapido(let azione)?:
            rapido(azione)
            return true
        case .domanda(let testo)?:                 // dentro una scheda, come il suo tasto «Chieda a JARVIS»: chiude e chiede
            chiudiChiesto = true
            Task { try? await Task.sleep(for: .milliseconds(350)); await invia(testo) }
            return true
        case .scheda(let azione)?:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            switch azione {
            case .occhiGiro:
                if let giro = OcchiAperti.giro, giro() { return true }
                return false                              // il giro non può partire: la frase resta allo scatto di sempre
            case .apriMail:
                if let u = URL(string: "message://") { UIApplication.shared.open(u) }
            default:
                NotificationCenter.default.post(name: .jarvisAzioneScheda, object: nil, userInfo: ["azione": azione])
            }
            return true
        default:
            return false
        }
    }

    /// «Traduci in inglese»: l'Interprete si apre già sulla lingua, senza passare dalla scelta.
    func apriInterprete(_ codice: String) {
        guard !lidarAperto, let l = Lingua.trova(codice) else { return }   // sopra LiDAR non si apre un'altra schermata
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        interrompi()
        interprete = l
    }

    @Published var riunioneSubito = false     // «registra la riunione»: il Wiretap parte già registrando

    /// I comandi rapidi: come toccare la sezione e poi il suo tasto principale.
    private func rapido(_ a: ComandoVocale.AzioneRapida) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch a {
        case .diario: chiediDiario("Diario, Sir. Mi racconti com'è andata oggi: la ascolto.")            // come «A voce» nel Diario
        case .confidente: chiediDiario("Modalità confidente. Mi racconti pure, Sir: la ascolto.")        // come «A voce» nel Confidente
        case .cucina: guardaCucina()
        case .riunione: riunioneSubito = true; repartoRichiesto = .wiretap
        }
    }

    /// Una frase breve di JARVIS per un comando (le misure di LiDAR): detta quella, torna in attesa.
    func annuncia(_ frase: String) {
        flussoFinito = true
        accodaVoce(frase, forza: true)
    }

    /// Apre un reparto o una scheda; `annuncia`: dice la sua frase (non serve quando l'ha già detto il cervello).
    private func apriReparto(_ reparto: Reparto, annuncia: Bool = true) {
        if reparto == .scanner && LidarAperta.aperta { return }      // dentro LiDAR «scansione» è la stanza, mai lo Scanner
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if annuncia, let a = reparto.annuncio {
            flussoFinito = true                     // una frase sola: finita quella, JARVIS torna in attesa
            accodaVoce(a, forza: true)
        }
        repartoRichiesto = reparto
    }

    /// Il giro con gli occhi chiesto a voce: 5 secondi, 4 fotogrammi, poi JARVIS dice cosa ha visto.
    func giroAVoce() {
        Task {
            let dati = await apriOcchi(automatico: true, video: true)
            guard !dati.isEmpty else { return }
            preparaFoto(dati)
            await invia("Cosa vedi in questo giro?")
        }
    }

    // MARK: Occhi

    /// Apre la fotocamera e aspetta le foto: una, o i 4 fotogrammi del giro (vuoto se il signore chiude).
    func apriOcchi(automatico: Bool, video: Bool = false, cucina: Bool = false, zoom: CGFloat = 1) async -> [Data] {
        // LiDAR sta scansionando: la foto viene dalla sua fotocamera, senza aprire Occhi né fermare la scansione
        if let scatta = OcchiLidar.scatta { return scatta().map { [$0] } ?? [] }   // niente fotogramma: nessuna foto, ma la scansione resta
        // una scheda o un'altra schermata aperta sopra: prima si chiude, se no Occhi non riesce ad aprirsi e JARVIS resterebbe in attesa
        if soccorsoAperto { return [] }               // il Tocco d'aiuto di Bea è aperto: non si copre mai
        if schermataAperta && occhi == nil {
            chiudiChiesto = true
            try? await Task.sleep(for: .milliseconds(700))
        }
        occhiChiusi([])                        // se ne era rimasta aperta una, si chiude
        return await withCheckedContinuation { (c: CheckedContinuation<[Data], Never>) in
            attesaOcchi = c
            occhi = Occhiata(automatico: automatico, video: video, cucina: cucina, zoom: zoom)
        }
    }

    /// Le foto scelte dal signore partono col prossimo messaggio: una come foto, più d'una come giro.
    private func preparaFoto(_ dati: [Data]) {
        if dati.count > 1 { fotoGiro = dati } else { foto = dati.first }
    }

    /// La fotocamera si è chiusa: consegna le foto a chi le aspettava.
    /// La frase detta dentro Occhi, se c'è (e la consuma).
    func prendiDomandaOcchi() -> String? {
        defer { domandaOcchi = nil }
        guard let d = domandaOcchi, !d.isEmpty else { return nil }
        return d
    }

    func occhiChiusi(_ dati: [Data]) {
        if occhi != nil { occhi = nil }
        guard let c = attesaOcchi else { return }
        attesaOcchi = nil
        c.resume(returning: dati)
    }

    /// Icona 👁️: mirino con il tasto, poi JARVIS guarda la foto (comodo per le copertine).
    func guardaManuale() {
        Task {
            let dati = await apriOcchi(automatico: false)
            let detta = prendiDomandaOcchi()
            guard !dati.isEmpty else { return }
            preparaFoto(dati)
            await invia(detta ?? (dati.count > 1 ? "Cosa vedi in questo giro?" : "Cosa vedi?"))
        }
    }

    /// «Ehi Siri, Jarvis guarda»: scatta da sola e chiede cosa c'è davanti.
    func guardaAutomatico() {
        Task {
            let dati = await apriOcchi(automatico: true)
            guard !dati.isEmpty else { return }
            preparaFoto(dati)
            await invia("Cosa sto guardando?")
        }
    }

    /// Icona Cucina: inquadra frigo o dispensa (scatto manuale), JARVIS propone cosa cucinare e cosa manca.
    func guardaCucina() {
        Task {
            let dati = await apriOcchi(automatico: false, cucina: true)
            let detta = prendiDomandaOcchi()
            guard !dati.isEmpty else { return }
            preparaFoto(dati)
            if let detta { await invia("Cucina: \(detta)"); return }      // la domanda detta a voce mentre inquadrava
            switch UserDefaults.standard.integer(forKey: "cucinaModo") {
            case 1: await invia("Cucina: che piatto è questo? Dimmi come si chiama, da dove viene e la ricetta in breve, con le dosi per due.")
            case 2: await invia("Cucina: stima i valori di questo piatto o prodotto: calorie, proteine, carboidrati e grassi per porzione, dicendo che è una stima a occhio.")
            default: await invia("Cosa cucino stasera con quello che vedi? Proponimi due o tre piatti e dimmi se manca qualcosa da mettere nella lista della spesa.")
            }
        }
    }

    /// INTELLIGENCE · Wiretap: la trascrizione va al cervello (anche lunga) e JARVIS ne fa il verbale.
    func verbaleWiretap(_ trascrizione: String, minuti: Int) {
        let t = trascrizione.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        allegato = t
        Task { await invia("Wiretap: il verbale della registrazione (\(minuti) min).") }
    }

    /// INTELLIGENCE · Profiler: la foto di una persona (o i fotogrammi di un giro) e, se il signore lo dice, chi è.
    func profila(_ dati: [Data], nome: String) {
        guard !dati.isEmpty else { return }
        preparaFoto(dati)
        let n = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await invia(n.isEmpty ? "Modalità Profiler: fammi la scheda di questa persona." : "Modalità Profiler: questo è \(n). Fammi la scheda.") }
    }

    /// La domanda del diario della sera: JARVIS la dice e subito dopo ascolta la risposta.
    private var ascoltaDopo = false
    func chiediDiario(_ domanda: String) {
        ascoltaDopo = true
        leggi(domanda)
    }

    /// Una notifica di JARVIS (briefing, avviso) da mettere in chat e dire ad alta voce, senza passare dal cervello.
    func leggi(_ testo: String) {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        interrompi()
        messaggi.append(Messaggio(ruolo: "assistant", testo: t))
        salva()
        flussoFinito = true
        accodaVoce(t, forza: true)
    }

    func interrompi() {
        fermaBenvenuto()
        liberoMacFinoA = .distantPast
        compitoRete?.cancel()
        compitoRete = nil
        compitoPonte?.cancel()
        compitoPonte = nil
        occhiChiusi([])                    // interrotto mentre guardava: la fotocamera si chiude
        orecchio.ferma()
        orecchio.testoDetto = ""
        sintesi.stopSpeaking(at: .immediate)
        cloud.ferma()
        bufferVoce = ""
        inCoda.removeAll()                  // i didCancel in arrivo per queste frasi verranno ignorati
        flussoFinito = true
        stato = nil
        strumenti.annullaInSospeso()        // interrotto: niente chiamate/app aperte più tardi a sorpresa
        if fase != .ascolto { fase = .attesa }
    }

    func invia(_ testoGrezzo: String, unisciA: UUID? = nil, comeAggiunta: Bool = false, comeSeguito: Bool = false) async {
        ultimaFraseAVoce = fraseAVoce                 // vuota se la domanda è scritta: si imparano solo le frasi dette a voce
        fraseAVoce = ""
        var testo = testoGrezzo.trimmingCharacters(in: .whitespacesAndNewlines)
        let fotoDaMandare = foto
        let giroDaMandare = fotoGiro
        if testo.isEmpty && fotoDaMandare == nil && giroDaMandare.isEmpty { fase = .attesa; return }
        if testo.isEmpty { testo = "Che cos'è?" }
        foto = nil
        fotoGiro = []
        let allegatoDaMandare = allegato
        allegato = nil
        interrompi()
        avviso = nil

        if let unisciA, let i = messaggi.lastIndex(where: { $0.id == unisciA }) {
            // «…e anche X»: la domanda di prima si allunga, la risposta interrotta viene tolta
            messaggi[i].testo += " … " + testo
            messaggi.removeSubrange((i + 1)...)
        } else {
            var m = Messaggio(ruolo: "user", testo: testo, conFoto: fotoDaMandare != nil || !giroDaMandare.isEmpty)
            // foto nuova: diventa quella di cui si parla, legata a questo messaggio
            if let f = fotoDaMandare { fotoRecenti = [f]; idFotoRecente = m.id; quandoFotoRecenti = Date() }
            else if !giroDaMandare.isEmpty { fotoRecenti = giroDaMandare; idFotoRecente = m.id; quandoFotoRecenti = Date() }
            if comeAggiunta { m.aggiunta = true } else if comeSeguito { m.seguito = true }
            messaggi.append(m)
        }
        let recenti = messaggi.suffix(20).filter { !$0.testo.isEmpty }
        let storia: [[String: Any]] = recenti.map { ["role": $0.ruolo, "content": $0.testoPerCervello] }
        // la foto vista prima torna al suo posto nella storia (non per la domanda che la porta già con sé)
        var fotoStoria: (Int, [Data])?
        if fotoDaMandare == nil, giroDaMandare.isEmpty, let idF = idFotoRecente, !fotoRecenti.isEmpty,
           Date().timeIntervalSince(quandoFotoRecenti) < 600,
           let k = recenti.firstIndex(where: { $0.id == idF }), k < recenti.count - 1 {
            fotoStoria = (k, fotoRecenti)
            quandoFotoRecenti = Date()          // finché se ne parla, la tiene davanti
        }
        let risposta = Messaggio(ruolo: "assistant", testo: "")
        messaggi.append(risposta)
        salva()

        ultimoInvio = Date()
        rispostaIniziata = false
        richiamo.liberoFinoA = Date().addingTimeInterval(2)   // nei primi 2 secondi può continuare a parlare senza dire «Jarvis»
        fase = .elaboro
        flussoFinito = false
        let fotoDaRimettere = fotoStoria
        compitoRete = Task { await self.turno(storia: storia, foto: fotoDaMandare, giro: giroDaMandare, allegato: allegatoDaMandare,
                                              fotoStoria: fotoDaRimettere, id: risposta.id) }
        // interrotto e subito un'aggiunta: una persona risponde e basta, non riempie di nuovo il vuoto
        let appenaRiempito = Date().timeIntervalSince(ultimoPonte) < 20
        if unisciA == nil && !comeAggiunta && !appenaRiempito { armaPonte(id: risposta.id, testo: testo) }
        else { compitoPonte?.cancel(); inizioTurno = Date() }
    }

    /// Se dopo un secondo il cervello non ha ancora detto nulla, JARVIS riempie l'attesa con una frase breve.
    private func armaPonte(id: UUID, testo: String) {
        compitoPonte?.cancel()
        inizioTurno = Date()
        guard !Impostazioni.muto, testo.count > 6 else { return }      // «pausa», «avanti»: rispondono già in un lampo
        compitoPonte = Task { @MainActor [weak self] in
            // niente «mh» o mezze parole (suonano come un balbettio): solo frasi intere, e solo se serve davvero.
            // Cervello di solito veloce: aspetto 1 s, spesso la risposta arriva prima. Cervello lento: parto dopo 0,4 s.
            let ritardo = (self?.latenzaMedia ?? 1.5) < 1.6 ? 1000 : 400
            try? await Task.sleep(for: .milliseconds(ritardo))
            guard let self, !Task.isCancelled, self.attesaVuota(id) else { return }
            self.ultimoPonte = Date()
            self.dici(Jarvis.ponteCasuale())
        }
    }

    /// Il cervello non ha ancora detto nulla e JARVIS sta zitto: c'è un vuoto da riempire.
    private func attesaVuota(_ id: UUID) -> Bool {
        fase == .elaboro && inCoda.isEmpty && bufferVoce.isEmpty && (messaggi.first(where: { $0.id == id })?.testo.isEmpty ?? false)
    }

    /// Una chiamata leggera al cervello all'avvio: Supabase si sveglia ora e la prima domanda non paga l'avvio a freddo.
    static func riscalda() async {
        guard let url = URL(string: Impostazioni.indirizzo) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["sveglia": true])
        // il cervello dice anche qual è la voce predefinita: se cambia, le frasi in cache si rifanno con la voce nuova
        if let (d, _) = try? await URLSession.shared.data(for: req),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let voce = o["voce"] as? String, !voce.isEmpty {
            UserDefaults.standard.set(voce, forKey: "vocePredefinitaCloud")
        }
    }

    func nuovaConversazione() {
        interrompi()
        messaggi.removeAll()
        fotoRecenti = []
        idFotoRecente = nil
        salva()
    }

    // MARK: Un turno di dialogo con il cervello (streaming + strumenti del telefono)

    private enum Esito { case fine(String, [String]), client([String: Any]), errore(String) }

    private func turno(storia: [[String: Any]], foto: Data?, giro: [Data] = [], allegato: String? = nil,
                       fotoStoria: (Int, [Data])? = nil, id: UUID) async {
        var corpo: [String: Any] = ["messaggi": storia, "dispositivo": Impostazioni.dispositivo, "strumenti_client": Strumenti.nomi]
        if let fs = fotoStoria {      // la foto di poco fa, rimessa al suo posto nella conversazione
            corpo["foto_storia"] = ["indice": fs.0, "immagini": fs.1.map { $0.base64EncodedString() }] as [String: Any]
        }
        if let foto { corpo["immagine"] = foto.base64EncodedString() }
        if !giro.isEmpty { corpo["immagini"] = giro.map { $0.base64EncodedString() } }   // i fotogrammi del giro, in ordine
        if let allegato { corpo["allegato"] = allegato }                                  // la trascrizione del Wiretap
        let posizione = await Posizione.attuale()          // dove si trova il signore: serve alla seconda memoria
        if let posizione { corpo["posizione"] = posizione }
        // iOS ci lascia finire la risposta anche se lo schermo si spegne o il signore cambia app per un momento
        let sfondo = UIApplication.shared.beginBackgroundTask(withName: "jarvis-risposta") { }
        defer { if sfondo != .invalid { UIApplication.shared.endBackgroundTask(sfondo) } }
        do {
            for _ in 0..<6 {
                // ogni passo ha un suo numero: se la linea cade e si riprova, il cervello riconosce la stessa richiesta e non ripete le azioni
                let esito = try await flussoConRitentativi(corpo, id: id, richiesta: UUID().uuidString)
                try Task.checkCancellation()
                switch esito {
                case .fine(let testo, let azioni):
                    concludi(id: id, testo: testo, azioni: azioni)
                    return
                case .errore(let msg):
                    concludi(id: id, testo: msg, azioni: [])
                    return
                case .client(let e):
                    let richieste = e["richieste"] as? [[String: Any]] ?? []
                    var risultati = e["risultati_server"] as? [[String: Any]] ?? []
                    for q in richieste {
                        try Task.checkCancellation()
                        let nome = q["name"] as? String ?? ""
                        if nome == "riconosci_musica" { await aspettaFineVoce() }   // Shazam non deve sentire JARVIS
                        try Task.checkCancellation()
                        stato = Strumenti.descrizione(nome)
                        let (contenuto, errore) = await strumenti.esegui(nome, q["input"] as? [String: Any] ?? [:])
                        aggiungiImmagini(strumenti.prendiImmagini(), id: id)
                        var esito: [String: Any] = ["tool_use_id": q["id"] as? String ?? "", "content": contenuto, "is_error": errore]
                        let viste = strumenti.prendiFotoOcchi()
                        if !viste.isEmpty {
                            fotoRecenti = viste                 // la foto scattata con «guarda»: è quella di cui si parlerà,
                            quandoFotoRecenti = Date()          // legata alla domanda che l'ha fatta scattare
                            if let i = messaggi.firstIndex(where: { $0.id == id }), i > 0, messaggi[i - 1].ruolo == "user" {
                                idFotoRecente = messaggi[i - 1].id
                            }
                            // il cervello riceve la foto (o i fotogrammi del giro) insieme al risultato di «guarda»
                            esito["immagini"] = viste.map { $0.base64EncodedString() }
                            segnaFoto(id: id)
                        }
                        risultati.append(esito)
                    }
                    try Task.checkCancellation()
                    let lavoro: Any = e["lavoro"] ?? [Any]()
                    let modello: Any = e["modello"] ?? ""
                    let azioniFatte: Any = e["azioni"] ?? [Any]()
                    let detto: Any = e["detto"] ?? ""
                    let continua: [String: Any] = ["lavoro": lavoro, "risultati": risultati,
                                                   "modello": modello, "azioni": azioniFatte, "detto": detto]
                    corpo = ["messaggi": [Any](), "dispositivo": Impostazioni.dispositivo, "strumenti_client": Strumenti.nomi,
                             "continua": continua]
                    if let posizione { corpo["posizione"] = posizione }
                }
            }
            concludi(id: id, testo: "Signore, mi sono perso in troppi passaggi. Riformuli pure.", azioni: [])
        } catch is CancellationError {
            rimuoviSeVuoto(id)              // interrotto dal signore: niente da dire
        } catch let e as URLError where e.code == .cancelled {
            rimuoviSeVuoto(id)
        } catch {
            Suoni.errore()
            concludi(id: id, testo: Jarvis.spiegaErroreRete(error), azioni: [])
        }
    }

    /// Gli errori di rete che meritano un secondo tentativo: linea caduta, tempo scaduto, niente campo.
    nonisolated private static func lineaCaduta(_ e: URLError) -> Bool {
        [.networkConnectionLost, .timedOut, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
         .dnsLookupFailed, .secureConnectionFailed, .resourceUnavailable].contains(e.code)
    }

    /// Al posto del messaggio inglese di iOS, una frase in italiano.
    nonisolated private static func spiegaErroreRete(_ e: Error) -> String {
        guard let u = e as? URLError else { return "Non riesco a raggiungere il mio cervello, Sir. \(e.localizedDescription)" }
        switch u.code {
        case .networkConnectionLost: return "Il server è irraggiungibile, Sir: ho insistito quattro volte, la linea non ha collaborato. Mi conceda un momento e me lo richieda."
        case .timedOut: return "Il mio cervello non ha risposto in tempo, Sir, nemmeno al quarto tentativo. La linea è lenta: riprovi tra poco."
        case .notConnectedToInternet: return "Siamo senza rete, Sir. Appena torna il campo sono di nuovo operativo."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: return "Non raggiungo il mio cervello, Sir: la rete c'è ma non mi fa passare. Riprovi tra un momento."
        default: return "Un intoppo di rete, Sir (\(u.code.rawValue)). Riprovi tra un momento."
        }
    }

    /// Se la linea cade (o scade il tempo), riprova da sola fino a quattro volte (pause di 1, 2 e 4 secondi), con lo stesso
    /// numero di richiesta. Al secondo inciampo JARVIS lo dice a voce, così il signore non parla con un muro.
    private func flussoConRitentativi(_ corpo: [String: Any], id: UUID, richiesta: String) async throws -> Esito {
        var tentativo = 0
        while true {
            do {
                return try await flusso(corpo, id: id, richiesta: richiesta)
            } catch let e as URLError where Jarvis.lineaCaduta(e) && tentativo < 3 {
                tentativo += 1
                azzeraTesto(id)                       // quello arrivato a metà si butta: la risposta ricomincia intera
                switch tentativo {
                case 1: stato = "Connessione persa, riprovo…"
                case 2:
                    stato = "La linea fa i capricci, insisto…"
                    accodaVoce("Un attimo, Sir: la linea fa i capricci. Insisto.")
                    accodaVoce("", forza: true)
                default: stato = "Ultimo tentativo…"
                }
                try await Task.sleep(for: .seconds(Double(1 << (tentativo - 1))))   // 1, 2, 4 secondi
            }
        }
    }

    private func azzeraTesto(_ id: UUID) {
        if let i = messaggi.firstIndex(where: { $0.id == id }) { messaggi[i].testo = "" }
        bufferVoce = ""
    }

    private func flusso(_ corpo: [String: Any], id: UUID, richiesta: String) async throws -> Esito {
        guard let url = URL(string: Impostazioni.indirizzo) else { throw ErroreJarvis.indirizzo }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.setValue(richiesta, forHTTPHeaderField: "x-richiesta")
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (righe, resp) = try await URLSession.shared.bytes(for: req)
        let codice = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if codice == 401 { return .errore("La parola d'ordine non coincide, signore. La controlli nelle impostazioni.") }
        guard codice == 200 else { return .errore("Il mio cervello ha risposto con un errore (codice \(codice)).") }

        for try await riga in righe.lines {
            try Task.checkCancellation()        // interrotto: le righe già arrivate non vanno più lette né dette
            guard let dati = riga.data(using: .utf8),
                  let e = (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any],
                  let tipo = e["t"] as? String else { continue }
            switch tipo {
            case "testo":
                if let pezzo = e["d"] as? String { aggiungi(pezzo, id: id) }
            case "stato":
                stato = e["d"] as? String
            case "immagini":
                aggiungiImmagini(Immagine.daJSON(e["d"]), id: id)
            case "fine":
                return .fine(e["testo"] as? String ?? "", e["azioni"] as? [String] ?? [])
            case "client":
                return .client(e)
            case "errore":
                return .errore(e["d"] as? String ?? "Un intoppo tecnico, signore.")
            default:
                break
            }
        }
        return .errore("La risposta si è interrotta a metà, signore. Riprovi.")
    }

    /// Nella chat, la domanda che ha fatto aprire gli occhi prende l'icona 📷.
    private func segnaFoto(id: UUID) {
        guard let i = messaggi.firstIndex(where: { $0.id == id }), i > 0, messaggi[i - 1].ruolo == "user" else { return }
        messaggi[i - 1].conFoto = true
        salva()
    }

    private func rimuoviSeVuoto(_ id: UUID) {
        if let i = messaggi.firstIndex(where: { $0.id == id }), messaggi[i].testo.isEmpty { messaggi.remove(at: i) }
        salva()
    }

    private func aggiungiImmagini(_ nuove: [Immagine], id: UUID) {
        guard !nuove.isEmpty, let i = messaggi.firstIndex(where: { $0.id == id }) else { return }
        var tutte = messaggi[i].immagini ?? []
        for n in nuove where !tutte.contains(where: { $0.id == n.id }) { tutte.append(n) }
        messaggi[i].immagini = Array(tutte.prefix(40))
        salva()
    }

    /// Prima di ascoltare la musica: finisce di dire la frase in corso («Ascolto.») e poi tace.
    private func aspettaFineVoce() async {
        orecchio.ferma()
        accodaVoce("", forza: true)
        for _ in 0..<80 where !inCoda.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !inCoda.isEmpty {
            sintesi.stopSpeaking(at: .immediate)
            cloud.ferma()
            inCoda.removeAll()
        }
        if fase == .parlo { fase = .elaboro }
    }

    private func aggiungi(_ pezzo: String, id: UUID) {
        compitoPonte?.cancel()
        if let t0 = inizioTurno {                       // prima parola arrivata: aggiorno la media dei tempi del cervello
            let dt = Date().timeIntervalSince(t0)
            latenzaMedia = latenzaMedia * 0.7 + min(dt, 8) * 0.3
            UserDefaults.standard.set(latenzaMedia, forKey: "latenzaMedia")
            inizioTurno = nil
        }
        if let i = messaggi.firstIndex(where: { $0.id == id }) { messaggi[i].testo += pezzo }
        stato = nil
        accodaVoce(pezzo)
    }

    private func concludi(id: UUID, testo: String, azioni: [String]) {
        let giaDetto = messaggi.first(where: { $0.id == id })?.testo ?? ""
        if let i = messaggi.firstIndex(where: { $0.id == id }) {
            messaggi[i].testo = testo
            messaggi[i].azioni = azioni
        }
        salva()
        stato = nil
        // se il testo finale non è stato letto in streaming (es. un errore), lo leggo ora
        if giaDetto.isEmpty { accodaVoce(testo) }
        accodaVoce("", forza: true)
        flussoFinito = true
        compitoRete = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if inCoda.isEmpty { fineParlato() }
    }

    // MARK: Voce in streaming: legge frase per frase mentre il resto arriva

    private func accodaVoce(_ pezzo: String, forza: Bool = false) {
        bufferVoce += pezzo
        guard !Impostazioni.muto else { bufferVoce = ""; return }
        if forza {
            let resto = bufferVoce.trimmingCharacters(in: .whitespacesAndNewlines)
            bufferVoce = ""
            if !resto.isEmpty { dici(resto) }
            return
        }
        // taglio all'ultima fine di frase seguita da uno spazio (così «10.500» non si spezza)
        let caratteri = Array(bufferVoce)
        var taglio: Int?
        for k in caratteri.indices.dropLast() where ".!?…;:\n".contains(caratteri[k]) && caratteri[k + 1].isWhitespace {
            taglio = k + 1
        }
        // inizio della risposta: se la prima frase è lunga, parto già alla prima virgola, così la voce attacca prima
        if taglio == nil, !rispostaIniziata, caratteri.count >= 28,
           let v = caratteri.indices.dropLast().last(where: { caratteri[$0] == "," && caratteri[$0 + 1].isWhitespace }), v >= 12 {
            taglio = v + 1
        }
        guard let t = taglio else { return }
        rispostaIniziata = true
        let frase = String(caratteri[..<t]).trimmingCharacters(in: .whitespacesAndNewlines)
        bufferVoce = String(caratteri[t...])
        if !frase.isEmpty { dici(frase) }
    }

    private func dici(_ frase: String) {
        guard fase != .ascolto else { return }   // mai prendersi l'audio mentre il signore parla
        // sul Mac niente orecchio mentre parla: è un secondo microfono (con il riconoscimento di Apple) che lascia muto quello
        // dell'attesa; lì per fermarlo basta toccare il reattore
        let conOrecchio = Impostazioni.interruzioneVocale && !Impostazioni.muto && !Jarvis.usaAscoltoCloud
        if inCoda.isEmpty {
            let sessione = AVAudioSession.sharedInstance()
            if Jarvis.usaAscoltoCloud {
                // Mac: stessa impostazione dell'attesa, così il microfono resta acceso e gli si può parlare sopra
                // (si tocca solo se è diversa: ogni cambio fermerebbe il microfono per un attimo)
                if sessione.category != .playAndRecord || !sessione.categoryOptions.contains(.mixWithOthers) {
                    try? sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
                }
            } else if conOrecchio {
                // altoparlante e microfono insieme: JARVIS parla e intanto sente se il signore lo chiama
                try? sessione.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            } else {
                try? sessione.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            }
            try? sessione.setActive(true)
            // la scelta si fa solo qui, quando nessuna delle due voci sta parlando: così non si accavallano
            vocePerCloud = Impostazioni.voceCloud && cloud.disponibile
            // l'orecchio sta per accendere il microfono con la cancellazione d'eco: l'audio dell'iPhone si riassesta
            // per un istante e le prime sillabe andrebbero perse (succede con le frasi già pronte in cache, che partono subito)
            if conOrecchio && !orecchio.attivo { cloud.partiDopo(0.3) }
        }
        let u = AVSpeechUtterance(string: frase)
        u.voice = Jarvis.voceScelta()
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = Jarvis.volumeVoce                   // «sbatti»: sottovoce
        let chiave = ObjectIdentifier(u)
        inCoda.insert(chiave)
        frasiVive[chiave] = u
        fase = .parlo
        orecchio.testoDetto += " " + frase          // così l'orecchio riconosce la propria eco
        if Jarvis.usaAscoltoCloud { dettoMac += " " + frase; dettoMacFino = Date().addingTimeInterval(30) }
        if conOrecchio, !orecchio.attivo { orecchio.avvia() }
        if vocePerCloud {
            cloud.accoda(u)                 // voce di JARVIS dal cloud; se fallisce, legge questa stessa frase con la voce dell'iPhone
        } else {
            sintesi.speak(u)
        }
    }

    /// Per «Prova la voce» nelle impostazioni.
    func parla(_ testo: String) async {
        interrompi()
        accodaVoce(testo, forza: true)
    }

    fileprivate func fraseFinita(_ chiave: ObjectIdentifier) {
        frasiVive[chiave] = nil
        guard inCoda.remove(chiave) != nil else { return }   // frase di un discorso già interrotto
        guard inCoda.isEmpty else { return }
        if flussoFinito { fineParlato() } else if fase == .parlo { fase = .elaboro }   // detto tutto, il resto è in arrivo
    }

    private func fineParlato() {
        orecchio.ferma()
        orecchio.testoDetto = ""
        guard fase != .ascolto else { return }   // il signore l'ha interrotto e sta già parlando
        fase = .attesa
        if !Impostazioni.richiamo { Suoni.pronto() }   // col richiamo a voce si chiude come una persona: in silenzio
        Task { @MainActor [weak self] in            // il segnale di fine deve finire prima di restituire l'audio alle altre app
            try? await Task.sleep(for: .milliseconds(400))
            // i Clash non si spengono; sul Mac il microfono dell'attesa sta già ripartendo: l'audio resta acceso
            guard let self, self.fase == .attesa, self.inCoda.isEmpty, !self.inBenvenuto, !Jarvis.usaAscoltoCloud else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if Jarvis.usaAscoltoCloud { liberoMacFinoA = Date().addingTimeInterval(8) }   // Mac: per 8 secondi il seguito va senza «Jarvis»
        strumenti.apriInSospeso()    // WhatsApp, Mappe, telefono: si aprono quando JARVIS ha finito di parlare
        if let l = strumenti.interpreteDaAprire {   // «traduci in spagnolo»: l'interprete parte appena ha finito la frase
            strumenti.interpreteDaAprire = nil
            interprete = l
        }
        if ascoltaDopo {             // diario della sera: finita la domanda, il microfono si apre da solo
            ascoltaDopo = false
            Task { await avviaAscolto() }
        }
        if strumenti.pulireChat {    // «cancella la conversazione»: dopo aver risposto, schermo pulito
            strumenti.pulireChat = false
            nuovaConversazione()
        }
        if let c = strumenti.comandoDaEseguire {   // il cervello ha capito un comando storpiato: lo eseguo e lo imparo
            strumenti.comandoDaEseguire = nil
            if !ultimaFraseAVoce.isEmpty { Storpiature.impara(ultimaFraseAVoce, comando: c) }
            if c == "rito" { benvenuto() } else if let r = Reparto(rawValue: c) { apriReparto(r, annuncia: false) }
        }
    }

    static func vociItaliane() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("it") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    static func voceScelta() -> AVSpeechSynthesisVoice? {
        if let v = AVSpeechSynthesisVoice(identifier: Impostazioni.voce) { return v }
        return Jarvis.vociItaliane().first ?? AVSpeechSynthesisVoice(language: "it-IT")
    }

    // MARK: Foto

    func impostaFoto(_ immagine: UIImage) {
        let lato: CGFloat = 1280
        let scala = min(1, lato / max(immagine.size.width, immagine.size.height))
        let misura = CGSize(width: immagine.size.width * scala, height: immagine.size.height * scala)
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1                   // pixel veri, non punti ×3: la foto resta sotto i limiti del cervello
        let ridotta = UIGraphicsImageRenderer(size: misura, format: formato).image { _ in immagine.draw(in: CGRect(origin: .zero, size: misura)) }
        foto = ridotta.jpegData(compressionQuality: 0.7)
    }

    // MARK: Ascolto

    /// `bip`: il suono di ascolto solo quando il signore tocca il reattore; a voce si ascolta in silenzio, come una persona.
    private func avviaAscolto(bip: Bool = false, tentativo: Int = 0, dalNome: Bool = false) async {
        avviso = nil
        guard fase == .attesa else { return }
        guard await Jarvis.chiediPermessi() else {
            avviso = "Servono microfono e riconoscimento vocale: li attivi in Impostazioni › Jarvis."
            return
        }
        guard fase == .attesa else { return }   // nel frattempo è partito un altro ascolto (doppio tocco)
        avvioRichiamo?.cancel()
        richiamo.ferma()                        // il microfono passa all'ascolto normale
        if Jarvis.usaAscoltoCloud {
            attesaMac.ferma()
            liberoMacFinoA = .distantPast
            // chiamato per nome: gli ultimi 3 secondi già sentiti (dentro c'è «Jarvis» e l'inizio della domanda), presi solo adesso
            // che il richiamo è spento, così non si perde niente di ciò che ha detto nel frattempo
            avviaAscoltoCloud(bip: bip, precarica: dalNome ? RegistroMicrofono.condiviso.ultimi(3) : [])
            return
        }
        guard let riconoscitore, riconoscitore.isAvailable else {
            // pochi tentativi: senza rete sul Mac il riconoscimento non torna da solo, inutile far aspettare
            if tentativo < 3, await riprovaAscolto(bip: bip, tentativo: tentativo) { return }
            aggiornaRichiamo()                  // il «Jarvis» in attesa torna acceso
            avviso = "Il riconoscimento vocale non è disponibile in questo momento."
            return
        }
        do {
            let sessione = AVAudioSession.sharedInstance()
            do {
                try sessione.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            } catch {
                try sessione.setCategory(.playAndRecord)           // sul Mac alcune opzioni dell'iPhone non valgono: si va sul semplice
            }
            try sessione.setActive(true, options: .notifyOthersOnDeactivation)

            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            r.addsPunctuation = true                 // il «?» aiuta a capire quando la domanda è finita
            r.contextualStrings = ["Discosizer", "Jarvis", "Discogs", "Resident Advisor", "SumUp"]
            richiesta = r
            try Jarvis.collegaMicrofono(motore.inputNode, a: r)
            motore.prepare()
            try motore.start()

            parziale = ""
            baseAscolto = ""
            precedenteAscolto = ""
            ultimoParzialeAscolto = .distantPast
            fase = .ascolto
            if bip { Suoni.ascolto() } else { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            turnoAscolto += 1
            let mio = turnoAscolto
            compito = Jarvis.avviaRiconoscimento(riconoscitore, r) { [weak self] testo, finale, errore in
                Task { @MainActor [weak self] in self?.aggiorna(testo: testo, finale: finale, errore: errore, ascolto: mio) }
            }
            armaSilenzio(secondi: 5)   // tempo per iniziare a parlare
        } catch {
            fermaAscolto(invia: false)
            if await riprovaAscolto(bip: bip, tentativo: tentativo) { return }
            aggiornaRichiamo()                  // il «Jarvis» in attesa torna acceso
            avviso = "Microfono non disponibile: \(error.localizedDescription)"
        }
    }

    // MARK: Ascolto in cloud (Mac)

    /// La frase sentita è quasi tutta fatta di parole che JARVIS ha appena detto? Allora è la sua voce (eco), non il signore.
    nonisolated static func eEco(_ sentito: String, detto: String) -> Bool {
        func parole(_ t: String) -> [String] {
            t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        let s = parole(sentito), d = Set(parole(detto))
        guard !s.isEmpty, !d.isEmpty else { return false }
        if s.contains(where: { parola in Richiamo.nomi.contains(where: { parola.hasPrefix($0) }) }) { return false }   // «Jarvis…» è sempre il signore
        let comuni = s.filter { d.contains($0) }.count
        return Double(comuni) / Double(s.count) >= 0.6
    }

    /// Mac: una frase sentita in attesa (già trascritta). La prende se c'è «Jarvis», se è la frase di Tony,
    /// o se arriva subito dopo una risposta (il seguito del discorso); il resto della stanza non è per lui.
    private func fraseSentitaMac(_ testo: String, inizio: Date) {
        guard fase == .attesa || fase == .elaboro || fase == .parlo else { return }
        if Date() > dettoMacFino { dettoMac = "" }
        if Jarvis.eEco(testo, detto: dettoMac) { return }                 // è la sua stessa voce: non è il signore
        if Jarvis.eSoloSilenzio(testo) {                                   // «Jarvis, muto», «basta», «stop»: tace e resta in attesa
            if fase != .attesa { mettiInAttesa() }
            return
        }
        if fase == .parlo {                                                // gli parla sopra: tace subito e ascolta, come sull'iPhone
            interrottoAVoce(testo)
            return
        }
        // «Jarvis…», ma anche «ehi», «senti», «ascolta», «bro»: si toglie il richiamo e resta il resto
        let conNome = Richiamo.dopoRichiamo(testo) != nil
        let dopo = Richiamo.dopoRichiamo(testo) ?? testo
        liberoMacFinoA = .distantPast
        if fase == .elaboro { segnaInterruzione(); interrompi() }   // stava pensando: lo fermo, come sull'iPhone
        avviso = nil
        parziale = ""
        if conNome && dopo.isEmpty { Task { await avviaAscolto(bip: true) }; return }   // solo «Jarvis»: apro il microfono
        // «piano»/«voce normale» per primo: cambia solo il volume, non è né il rito né una domanda
        let senzaSottovoce = sottovoce(dopo)
        if senzaSottovoce.isEmpty { return }                              // solo «piano» o «voce normale»: fatto, niente rito
        if Benvenuto.eFraseDiTony(senzaSottovoce) { fraseDiTony(); return }
        if foto == nil, eseguiComando(senzaSottovoce) { return }
        Task { await instrada(senzaSottovoce) }
    }

    /// Registra la frase; quando il signore ha finito (o tocca il reattore) la trascrive in cloud e la manda come sull'iPhone.
    private func avviaAscoltoCloud(bip: Bool, precarica: [Float]) {
        do {
            let sessione = AVAudioSession.sharedInstance()
            do {
                // mixWithOthers: la musica e le altre app restano al loro volume mentre JARVIS ascolta
                try sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            } catch {
                try sessione.setCategory(.playAndRecord, options: [.mixWithOthers])
            }
            try sessione.setActive(true, options: .notifyOthersOnDeactivation)
            registratore.azzera()
            registratore.precarica(precarica)
            turnoAscolto += 1
            let mio = turnoAscolto
            registratore.quandoFinito = { [weak self] in
                Task { @MainActor [weak self] in self?.chiudiAscoltoCloud(turno: mio) }
            }
            try Jarvis.collegaRegistratore(motore.inputNode, registratore)
            motore.prepare()
            try motore.start()
            parziale = ""
            ascoltoCloud = true
            fase = .ascolto
            stato = "La ascolto, Sir"
            Task { [weak self] in                     // paracadute: se il Mac smette di mandare audio (cuffie collegate…) non resta appeso
                try? await Task.sleep(for: .seconds(32))
                self?.chiudiAscoltoCloud(turno: mio)
            }
            if bip { Suoni.ascolto() } else { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        } catch {
            fermaAscolto(invia: false)
            aggiornaRichiamo()
            avviso = "Microfono non disponibile: \(error.localizedDescription)"
        }
    }

    /// La frase è finita: microfono spento, trascrizione in cloud, poi comando o domanda come sempre.
    private func chiudiAscoltoCloud(turno: Int) {
        guard ascoltoCloud, fase == .ascolto, turno == turnoAscolto else { return }
        ascoltoCloud = false
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        guard registratore.haParlato else {            // non ha detto niente: torna in attesa, in silenzio
            stato = nil
            fase = .attesa
            return
        }
        let registratore = self.registratore
        stato = "Un attimo, Sir"
        fase = .elaboro
        Task { [weak self] in
            let audio = await Task.detached { registratore.wav() }.value      // il file si prepara fuori dal thread principale
            let (testo, errore) = await RegistratoreVoce.trascrivi(audio, token: Portachiavi.leggi(), indirizzo: Impostazioni.indirizzo)
            guard let self, self.fase == .elaboro, !self.ascoltoCloud, self.turnoAscolto == turno else { return }   // interrotto nel frattempo
            if self.stato == "Un attimo, Sir" { self.stato = nil }
            self.fase = .attesa
            guard let testo, !testo.isEmpty else {
                self.avviso = errore ?? "Non ho capito, Sir. Riprovi."
                return
            }
            if self.foto == nil, self.eseguiComando(testo) { return }
            if self.foto == nil { await self.instrada(testo) } else { await self.invia(testo) }
        }
    }

    nonisolated private static func collegaRegistratore(_ input: AVAudioInputNode, _ registratore: RegistratoreVoce) throws {
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio valido."])
        }
        input.removeTap(onBus: 0)
        try? input.setVoiceProcessingEnabled(false)          // niente «modalità chiamata»: non abbassa le altre app
        input.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
            registratore.analizza(buffer)
            Volume.voce.misura(buffer)          // il reattore si gonfia con la voce
        }
    }

    /// Aperto da Siri («Ehi Siri, parla con Jarvis»): per un paio di secondi il microfono è ancora di Siri.
    /// Invece di arrendersi subito, JARVIS aspetta un attimo e riprova (fino a circa 6 secondi), poi ascolta.
    private func riprovaAscolto(bip: Bool, tentativo: Int) async -> Bool {
        guard tentativo < 10, fase == .attesa else { return false }
        stato = "Un attimo, Sir"
        try? await Task.sleep(for: .milliseconds(600))
        guard fase == .attesa, !Task.isCancelled else { return true }   // nel frattempo è successo altro: niente avviso
        if stato == "Un attimo, Sir" { stato = nil }
        await avviaAscolto(bip: bip, tentativo: tentativo + 1)
        return true
    }

    private func aggiorna(testo: String?, finale: Bool, errore: Bool, ascolto: Int) {
        guard fase == .ascolto, ascolto == turnoAscolto else { return }
        if let testo, !testo.isEmpty {
            let adesso = Date()
            if Richiamo.pezzoNuovo(precedente: precedenteAscolto, nuovo: testo, pausa: adesso.timeIntervalSince(ultimoParzialeAscolto)) {
                baseAscolto = parziale                 // il riconoscimento è ripartito da capo: non perdo l'inizio della frase
            }
            precedenteAscolto = testo
            ultimoParzialeAscolto = adesso
            parziale = [baseAscolto, testo].filter { !$0.isEmpty }.joined(separator: " ")
            armaSilenzio(secondi: Jarvis.pausaFineFrase(parziale))
            if timerTetto == nil {                     // il signore ha iniziato a parlare: può andare avanti fino a un minuto
                let mio = turnoAscolto
                timerTetto = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.turnoAscolto == mio else { return }
                        self.fermaAscolto(invia: true)
                    }
                }
            }
        }
        if finale || errore { fermaAscolto(invia: true) }
    }

    /// Quanto silenzio aspettare prima di considerare finita la frase, come farebbe una persona che ascolta:
    /// non conta solo il silenzio ma cosa è stato detto.
    /// - «che tempo fa oggi?», «sì», «apri la Sentinella»: la frase è chiusa, si risponde quasi subito;
    /// - «oggi ero a Bari…», «allora, ti racconto…»: è un racconto, chi parla di solito continua; si aspetta di più;
    /// - «…e», «…perché», «…ehm»: si è fermato a metà, sta pensando; si aspetta ancora di più.
    nonisolated static func pausaFineFrase(_ testo: String) -> Double {
        let pulito = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        let basso = pulito.lowercased()
        let parole = basso.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        guard let ultima = parole.last else { return 1.2 }
        let frase = parole.joined(separator: " ")

        // si è fermato a metà o sta pensando ad alta voce
        let sospese: Set<String> = ["e", "ed", "o", "ma", "che", "perché", "poi", "di", "del", "della", "dei", "delle", "a", "al",
                                    "alla", "ai", "da", "dal", "dalla", "in", "nel", "nella", "con", "per", "su", "sul", "tra", "fra",
                                    "il", "lo", "la", "i", "gli", "le", "un", "una", "uno", "mi", "ti", "ci", "si", "se", "quando",
                                    "dove", "come", "anche", "quindi", "cioè", "tipo", "ehm", "eh", "mmm", "allora", "praticamente",
                                    "comunque", "però", "mentre", "oppure", "magari", "sono", "è", "ho", "hai", "abbiamo", "volevo",
                                    "vorrei", "devo", "dobbiamo", "questo", "questa", "quel", "quella", "mio", "mia", "tuo", "tua"]
        if sospese.contains(ultima) { return 2.4 }
        if basso.hasSuffix(",") || basso.hasSuffix("…") || basso.hasSuffix("...") { return 2.0 }

        // risposte brevi: «sì», «no», «ok», «va bene», «grazie»
        let brevi: Set<String> = ["sì", "si", "no", "ok", "okay", "certo", "esatto", "grazie", "perfetto", "va bene", "giusto",
                                  "bravo", "basta", "stop", "ferma", "avanti", "pausa", "dai", "fatto", "procedi", "vai", "confermo"]
        if parole.count <= 3 && brevi.contains(where: { frase == $0 || frase.hasPrefix($0 + " ") }) { return 0.6 }

        // domanda chiusa: il punto di domanda del riconoscimento, o una domanda breve che non resta in sospeso
        if basso.hasSuffix("?") { return 0.7 }
        let interrogative: Set<String> = ["che", "cosa", "cos'è", "quanto", "quanti", "quanta", "quante", "come", "dove", "quando",
                                          "chi", "perché", "qual", "quale", "quali", "c'è", "ci", "hai", "sai", "puoi", "mi"]
        if let prima = parole.first, interrogative.contains(prima), parole.count >= 2, parole.count <= 10 { return 0.8 }

        // comandi: «apri…», «metti…», «chiama…»
        let comandi: Set<String> = ["apri", "chiudi", "metti", "chiama", "manda", "scrivi", "accendi", "spegni", "ferma", "avvia",
                                    "leggi", "cerca", "dimmi", "fammi", "ricordami", "imposta", "alza", "abbassa", "guarda",
                                    "scansiona", "traduci", "attiva", "disattiva", "riproduci", "salta", "segna", "aggiungi",
                                    "togli", "cancella", "mostrami", "trova", "calcola", "prenota", "fai"]
        if let prima = parole.first, comandi.contains(prima), parole.count <= 10 { return 0.9 }

        // racconto: chi parla sta esponendo un pensiero, di solito continua
        let racconto = ["oggi", "ieri", "stamattina", "stasera", "allora", "ascolta", "senti", "praticamente", "sai", "comunque",
                        "quindi", "ti volevo", "volevo", "ti racconto", "ti devo", "devo dirti", "pensavo", "secondo me", "io", "noi",
                        "l'altro giorno", "prima"]
        if racconto.contains(where: { frase == $0 || frase.hasPrefix($0 + " ") }) { return 1.8 }
        if parole.count >= 15 { return 1.6 }                    // discorso lungo: pause di pensiero più probabili
        return 1.2
    }

    private func armaSilenzio(secondi: Double) {
        timerSilenzio?.invalidate()
        let mio = turnoAscolto
        timerSilenzio = Timer.scheduledTimer(withTimeInterval: secondi, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.turnoAscolto == mio else { return }
                self.fermaAscolto(invia: true)
            }
        }
    }

    private func fermaAscolto(invia: Bool) {
        guard fase == .ascolto || !invia else { return }
        ascoltoCloud = false
        if richiamo.sveglio { richiamo.ferma() }       // toccato mentre il richiamo raccoglieva la frase: la mando così
        timerSilenzio?.invalidate()
        timerSilenzio = nil
        timerTetto?.invalidate()
        timerTetto = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil
        compito = nil
        let testo = parziale
        parziale = ""
        fase = .attesa
        if invia, foto == nil, eseguiComando(testo) { return }       // «attiva la Sentinella»: lo apro io, niente cervello
        if invia, !testo.isEmpty || foto != nil {
            if foto == nil { Task { await self.instrada(testo) } } else { Task { await self.invia(testo) } }
        } else { aggiuntaInArrivo = false }
    }

    // MARK: Memoria locale della conversazione

    private func salva() {
        if let d = try? JSONEncoder().encode(Array(messaggi.suffix(60))) {
            UserDefaults.standard.set(d, forKey: "messaggi")
        }
    }

    private func carica() {
        if let d = UserDefaults.standard.data(forKey: "messaggi"),
           let m = try? JSONDecoder().decode([Messaggio].self, from: d) { messaggi = m.filter { !$0.testo.isEmpty } }
    }

    // MARK: Ponti fuori dal thread principale
    // I callback audio arrivano su altri thread: queste funzioni non sono legate al MainActor.

    nonisolated private static func chiediPermessi() async -> Bool {
        let parlato = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { @Sendable stato in c.resume(returning: stato == .authorized) }
        }
        let microfono = await AVAudioApplication.requestRecordPermission()
        return (parlato || usaAscoltoCloud) && microfono   // sul Mac si trascrive in cloud: basta il microfono
    }

    nonisolated private static func collegaMicrofono(_ input: AVAudioInputNode, a r: SFSpeechAudioBufferRecognitionRequest) throws {
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Jarvis", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio valido."])
        }
        input.removeTap(onBus: 0)
        nonisolated(unsafe) let richiesta = r
        input.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in
            richiesta.append(buffer)
            Volume.voce.misura(buffer)          // il reattore si gonfia con la voce
        }
    }

    nonisolated private static func avviaRiconoscimento(
        _ ric: SFSpeechRecognizer,
        _ r: SFSpeechAudioBufferRecognitionRequest,
        risultato: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in
            risultato(ris?.bestTranscription.formattedString, ris?.isFinal ?? false, err != nil)
        }
    }
}

extension Jarvis: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let chiave = ObjectIdentifier(u)
        Task { @MainActor in self.fraseFinita(chiave) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let chiave = ObjectIdentifier(u)
        Task { @MainActor in self.fraseFinita(chiave) }
    }
}

// MARK: - Voce di JARVIS dal cloud (ElevenLabs tramite il cervello)
// Ogni frase si scarica appena arriva (in parallelo) e si ascolta in ordine. Se una frase non arriva,
// la legge la voce dell'iPhone: JARVIS non resta mai muto.

nonisolated struct VoceRemota: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let nome: String
    let descrizione: String?
}

@MainActor
final class VoceCloud: NSObject {
    var finita: ((ObjectIdentifier) -> Void)?

    /// L'audio di una frase: intero (dalla cache, o mp3 della voce di riserva) oppure in arrivo a pezzi (streaming).
    private enum Sorgente { case intero(Data), flusso(AudioInArrivo) }
    private struct Pezzo { let frase: AVSpeechUtterance; let audio: Task<Sorgente?, Never> }
    private var flussi: [AudioInArrivo] = []      // gli streaming ancora in corso (da fermare se il signore interrompe)
    private var motore: AVAudioEngine?             // la voce in streaming suona da qui
    private var nodo: AVAudioPlayerNode?
    private var formatoNodo: AVAudioFormat?
    private var spegniMotore: Task<Void, Never>?
    private var coda: [Pezzo] = []
    private var generazione = 0              // cambia a ogni interruzione: i lavori vecchi si fermano da soli
    private var inCorso = false
    private var sospesaFino = Date.distantPast
    private var lettore: AVAudioPlayer?
    private let riserva = AVSpeechSynthesizer()
    private var attesa: CheckedContinuation<Bool, Never>?
    private var attuale: ObjectIdentifier?   // il suono (mp3 o frase di riserva) che sta andando adesso
    private var inDownload = 0               // frasi in scaricamento in questo momento

    private var prontoDa = Date.distantPast   // prima di allora non parte nessun suono (l'audio si sta riassestando)

    /// La prossima frase parte non prima di fra `secondi`.
    func partiDopo(_ secondi: TimeInterval) { prontoDa = Date().addingTimeInterval(secondi) }

    /// Falso per qualche minuto se il cervello dice che la voce cloud non è configurata.
    var disponibile: Bool { Date() >= sospesaFino }

    override init() {
        super.init()
        riserva.delegate = self
    }

    func accoda(_ u: AVSpeechUtterance) {
        let testo = u.speechString
        let token = Portachiavi.leggi()
        let id = Impostazioni.idVoceCloud
        let url = URL(string: Impostazioni.indirizzo)
        let audio = Task { [weak self] () async -> Sorgente? in
            guard let url, let self else { return nil }
            // le frasi già dette una volta sono in cache: partono subito, senza rete e senza consumare credito
            if let pronta = CacheVoce.leggi(testo, id: id) { return .intero(pronta) }
            // al massimo 2 frasi scaricate insieme: ElevenLabs ne accetta poche in parallelo,
            // e se si esagera alcune frasi tornano con la voce dell'iPhone (voce che cambia a metà)
            while self.inDownload >= 2 && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(60)) }
            if Task.isCancelled { return nil }
            self.inDownload += 1
            // in streaming: la voce comincia mentre ElevenLabs sta ancora generando il resto della frase
            let a = VoceCloud.avviaFlusso(testo, id: id, url: url, token: token)
            self.flussi.append(a)
            Task { @MainActor [weak self] in
                await a.attendiFine()
                guard let self else { return }
                self.inDownload -= 1
                self.flussi.removeAll { $0 === a }
                if let codice = a.codiceErrore, codice == 503 || codice == 401 { self.sospesaFino = Date().addingTimeInterval(300) }
                if let d = a.perCache() { CacheVoce.salva(d, testo: testo, id: id) }   // la prossima volta parte dalla cache
            }
            switch await a.attendiInizio() {
            case .pcm: return .flusso(a)
            case .intero:
                await a.attendiFine()
                if Task.isCancelled { return nil }
                return a.riuscito ? .intero(a.tutto) : nil
            default: return nil
            }
        }
        coda.append(Pezzo(frase: u, audio: audio))
        if !inCorso {
            inCorso = true
            let g = generazione
            Task { await self.ciclo(g) }
        }
    }

    /// Scarica in sottofondo le frasi fisse non ancora in cache (frasi ponte, annunci): la prima volta che servono sono già pronte.
    func prepara(_ frasi: [String]) {
        let token = Portachiavi.leggi()
        let id = Impostazioni.idVoceCloud
        guard let url = URL(string: Impostazioni.indirizzo), !token.isEmpty else { return }
        let mancanti = frasi.filter { CacheVoce.leggi($0, id: id) == nil }
        guard !mancanti.isEmpty else { return }
        Task.detached(priority: .utility) {
            for f in mancanti {
                let (dati, _) = await VoceCloud.scarica(f, id: id, url: url, token: token)
                if let dati { CacheVoce.salva(dati, testo: f, id: id) }
                try? await Task.sleep(for: .milliseconds(400))   // una alla volta, senza intralciare la voce vera
            }
        }
    }

    func ferma() {
        generazione += 1
        coda.forEach { $0.audio.cancel() }
        coda.removeAll()
        flussi.forEach { $0.annulla() }
        nodo?.stop()
        lettore?.stop()
        lettore = nil
        riserva.stopSpeaking(at: .immediate)
        rilascia(false)
        inCorso = false
    }

    private func ciclo(_ g: Int) async {
        while g == generazione, !coda.isEmpty {
            let p = coda.removeFirst()
            let sorgente = await p.audio.value
            guard g == generazione else { return }
            let manca = prontoDa.timeIntervalSinceNow
            if manca > 0 { try? await Task.sleep(for: .milliseconds(Int(manca * 1000))) }
            guard g == generazione else { return }
            var detta = false
            switch sorgente {
            case .intero(let dati)?: detta = await suona(dati)
            case .flusso(let a)?: detta = await suonaFlusso(a, g)
            case nil: break
            }
            guard g == generazione else { return }
            if !detta {
                _ = await leggiConRiserva(p.frase)
                guard g == generazione else { return }
            }
            finita?(ObjectIdentifier(p.frase))
        }
        if g == generazione {
            inCorso = false
            // finito di parlare: fra poco si spegne anche il motore dello streaming (l'audio torna libero)
            spegniMotore?.cancel()
            spegniMotore = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, !self.inCorso else { return }
                self.nodo?.stop()
                self.motore?.stop()
            }
        }
    }

    /// Prepara (o riprende) il motore che suona l'audio in streaming.
    private func preparaMotore(_ frequenza: Double) -> (AVAudioEngine, AVAudioPlayerNode, AVAudioFormat)? {
        spegniMotore?.cancel()
        guard let formato = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: frequenza, channels: 1, interleaved: false) else { return nil }
        if motore == nil || formatoNodo?.sampleRate != frequenza {
            motore?.stop()
            let m = AVAudioEngine()
            let n = AVAudioPlayerNode()
            m.attach(n)
            m.connect(n, to: m.mainMixerNode, format: formato)
            VoceCloud.seguiVolume(m)
            motore = m; nodo = n; formatoNodo = formato
        }
        guard let m = motore, let n = nodo else { return nil }
        if !m.isRunning {
            m.prepare()
            guard (try? m.start()) != nil else { return nil }
        }
        n.volume = Jarvis.volumeVoce                   // «sbatti»: sottovoce
        if !n.isPlaying { n.play() }
        return (m, n, formato)
    }

    /// Suona una frase mentre arriva: parte appena c'è un filo di anticipo (0,2 s) e continua finché ElevenLabs la finisce.
    private func suonaFlusso(_ a: AudioInArrivo, _ g: Int) async -> Bool {
        guard case .pcm(let frequenza) = a.stato else { return false }
        let anticipo = Int(frequenza * 2 * 0.2)               // byte: 16 bit per campione
        let limite = Date().addingTimeInterval(10)
        while g == generazione, !a.finito, a.quanti < anticipo, Date() < limite {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard g == generazione else { return true }
        guard a.quanti >= 2, let pronto = preparaMotore(frequenza) else { return false }
        let (m, n, formato) = pronto
        let suonati = Contatore()
        var letti = 0, programmati = 0
        var campioni = 0
        let inizio = Date()
        while g == generazione {
            let (nuovi, finito) = a.leggi(da: letti)
            let utili = nuovi.count & ~1
            if utili > 0, let b = VoceCloud.buffer(nuovi.prefix(utili), formato) {
                VoceCloud.programma(n, b, suonati)
                programmati += 1
                campioni += Int(b.frameLength)
                letti += utili
            }
            if !m.isRunning {                                   // l'audio dell'iPhone si è riassestato: riparto
                m.prepare()
                if (try? m.start()) != nil { n.play() }
            }
            if finito && a.quanti - letti < 2 {
                // tutto programmato: aspetto che finisca di suonare (con un tetto, se l'audio si fosse inceppato)
                let durata = Double(campioni) / frequenza
                if suonati.valore >= programmati || Date().timeIntervalSince(inizio) > durata + 1.5 { break }
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return true
    }

    nonisolated private static func seguiVolume(_ m: AVAudioEngine) {
        m.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { b, _ in Volume.voce.misura(b) }   // il reattore segue la voce
    }

    nonisolated private static func programma(_ n: AVAudioPlayerNode, _ b: AVAudioPCMBuffer, _ c: Contatore) {
        n.scheduleBuffer(b, completionCallbackType: .dataPlayedBack) { _ in c.aggiungi() }
    }

    /// PCM 16 bit little-endian → campioni float per il motore audio.
    nonisolated private static func buffer(_ d: Data, _ formato: AVAudioFormat) -> AVAudioPCMBuffer? {
        let quanti = d.count / 2
        guard quanti > 0, let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: AVAudioFrameCount(quanti)),
              let dst = b.floatChannelData?[0] else { return nil }
        b.frameLength = AVAudioFrameCount(quanti)
        d.withUnsafeBytes { raw in
            for i in 0..<quanti { dst[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768 }
        }
        return b
    }

    /// Avvia lo streaming di una frase: la richiesta parte subito, l'audio si accumula in `AudioInArrivo` mentre arriva.
    nonisolated static func avviaFlusso(_ testo: String, id: String, url: URL, token: String) -> AudioInArrivo {
        let a = AudioInArrivo()
        let lavoro = Task.detached(priority: .userInitiated) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
            var corpo: [String: Any] = ["voce": testo, "flusso": true]
            if !id.isEmpty { corpo["id_voce"] = id }
            req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
            do {
                let (byte, r) = try await URLSession.shared.bytes(for: req)
                let http = r as? HTTPURLResponse
                let codice = http?.statusCode ?? 0
                let tipo = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
                guard codice == 200, tipo.contains("audio") else { a.inizia(.errore(codice)); a.chiudi(ok: false); return }
                if tipo.contains("pcm") {
                    let frequenza = tipo.range(of: #"rate=(\d+)"#, options: .regularExpression)
                        .flatMap { Double(tipo[$0].dropFirst(5)) } ?? 24_000
                    a.inizia(.pcm(frequenza))
                } else {
                    a.inizia(.intero)                        // voce di riserva (mp3): arriva intera
                }
                var pezzo = Data()
                pezzo.reserveCapacity(4800)
                for try await x in byte {
                    pezzo.append(x)
                    if pezzo.count >= 4800 { a.aggiungi(pezzo); pezzo.removeAll(keepingCapacity: true) }   // 0,1 s di voce
                }
                if !pezzo.isEmpty { a.aggiungi(pezzo) }
                a.chiudi(ok: true)
            } catch {
                a.inizia(.errore(0))
                a.chiudi(ok: false)
            }
        }
        a.lavoro = lavoro
        return a
    }

    private func suona(_ dati: Data) async -> Bool {
        guard let p = try? AVAudioPlayer(data: dati) else { return false }
        p.delegate = self
        p.volume = Jarvis.volumeVoce                   // sottovoce anche per le frasi già pronte
        lettore = p
        Volume.segui(p)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            attesa = c
            attuale = ObjectIdentifier(p)
            if !p.play() { rilascia(false) }
        }
    }

    private func leggiConRiserva(_ u: AVSpeechUtterance) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            attesa = c
            attuale = ObjectIdentifier(u)
            riserva.speak(u)
        }
    }

    fileprivate func chiudi(_ id: ObjectIdentifier, _ ok: Bool) {
        guard id == attuale else { return }  // segnale di un suono già interrotto
        rilascia(ok)
    }

    private func rilascia(_ ok: Bool) {
        let c = attesa
        attesa = nil
        attuale = nil
        lettore = nil
        c?.resume(returning: ok)
    }

    nonisolated static func scarica(_ testo: String, id: String, url: URL, token: String) async -> (Data?, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15                 // il cervello può riprovare con ElevenLabs: diamogli tempo
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
        var corpo: [String: Any] = ["voce": testo]
        if !id.isEmpty { corpo["id_voce"] = id }
        req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            let http = r as? HTTPURLResponse
            let codice = http?.statusCode ?? 0
            let tipo = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
            return (codice == 200 && tipo.contains("audio") && !d.isEmpty) ? (d, 200) : (nil, codice)
        } catch {
            return (nil, 0)
        }
    }

    /// Le voci dell'account ElevenLabs, per sceglierle nelle impostazioni. nil = voce cloud non configurata o non raggiungibile.
    static func elencoVoci() async -> [VoceRemota]? {
        guard let url = URL(string: Impostazioni.indirizzo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = Data(#"{"voci":true}"#.utf8)
        struct Risposta: Decodable { let attiva: Bool; let voci: [VoceRemota] }
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let r = try? JSONDecoder().decode(Risposta.self, from: d), r.attiva else { return nil }
        return r.voci
    }
}

/// L'audio di una frase in streaming: cresce mentre arriva; chi suona lo legge a pezzi.
nonisolated final class AudioInArrivo: @unchecked Sendable {
    enum Stato { case attesa, pcm(Double), intero, errore(Int) }
    private let lock = NSLock()
    private var _stato = Stato.attesa
    private var dati = Data()
    private var _finito = false
    private var _riuscito = false
    private var _lavoro: Task<Void, Never>?

    var lavoro: Task<Void, Never>? {
        get { lock.lock(); defer { lock.unlock() }; return _lavoro }
        set { lock.lock(); _lavoro = newValue; lock.unlock() }
    }
    var stato: Stato { lock.lock(); defer { lock.unlock() }; return _stato }
    var finito: Bool { lock.lock(); defer { lock.unlock() }; return _finito }
    var riuscito: Bool { lock.lock(); defer { lock.unlock() }; return _riuscito }
    var quanti: Int { lock.lock(); defer { lock.unlock() }; return dati.count }
    var tutto: Data { lock.lock(); defer { lock.unlock() }; return dati }
    var codiceErrore: Int? { if case .errore(let c) = stato { return c }; return nil }

    func inizia(_ s: Stato) {
        lock.lock()
        if case .attesa = _stato { _stato = s }
        lock.unlock()
    }
    func aggiungi(_ d: Data) { lock.lock(); dati.append(d); lock.unlock() }
    func chiudi(ok: Bool) {
        lock.lock()
        if case .attesa = _stato { _stato = .errore(0) }
        _riuscito = ok && !dati.isEmpty
        _finito = true
        lock.unlock()
    }
    func annulla() { lavoro?.cancel() }

    /// I byte arrivati dopo `da`, e se la frase è finita.
    func leggi(da: Int) -> (Data, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (da < dati.count ? dati.subdata(in: da..<dati.count) : Data(), _finito)
    }

    func attendiInizio() async -> Stato {
        while true {
            let s = stato
            if case .attesa = s, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(15)); continue }
            return s
        }
    }

    func attendiFine() async {
        while !finito && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Da salvare in cache, se è arrivata tutta: il PCM diventa un WAV (lo legge AVAudioPlayer come gli mp3).
    func perCache() -> Data? {
        guard riuscito else { return nil }
        switch stato {
        case .intero: return tutto
        case .pcm(let f): return AudioInArrivo.wav(tutto, frequenza: Int(f))
        default: return nil
        }
    }

    static func wav(_ pcm: Data, frequenza: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(frequenza)); u32(UInt32(frequenza * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }
}

/// Un contatore da usare dal thread audio.
nonisolated final class Contatore: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func aggiungi() { lock.lock(); n += 1; lock.unlock() }
    var valore: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// La cache delle frasi già pronunciate: un file audio per frase (e per voce), nella cartella Caches dell'app.
/// Le frasi che JARVIS ripete (ponti, conferme, annunci) partono all'istante; iOS può svuotare la cartella se serve spazio.
nonisolated enum CacheVoce {
    private static let cartella: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let c = base.appendingPathComponent("voce-jarvis", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }()
    private static let massimoFile = 400

    private static func file(_ testo: String, id: String) -> URL? {
        let voce = id.isEmpty ? (UserDefaults.standard.string(forKey: "vocePredefinitaCloud") ?? "") : id
        let chiave = "\(voce)|\(testo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        let hash = SHA256.hash(data: Data(chiave.utf8)).map { String(format: "%02x", $0) }.joined()
        return cartella?.appendingPathComponent(hash + ".mp3")
    }

    static func leggi(_ testo: String, id: String) -> Data? {
        guard let f = file(testo, id: id), let d = try? Data(contentsOf: f), d.count > 200 else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: f.path)   // usata ora: resta tra le recenti
        return d
    }

    static func salva(_ dati: Data, testo: String, id: String) {
        guard let f = file(testo, id: id), testo.count <= 300 else { return }   // le frasi lunghe non si ripetono mai uguali
        try? dati.write(to: f, options: .atomic)
        potatura()
    }

    /// Se i file sono troppi, via i meno usati di recente.
    private static func potatura() {
        guard let c = cartella,
              let elenco = try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: [.contentModificationDateKey]),
              elenco.count > massimoFile else { return }
        let ordinati = elenco.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }
        for f in ordinati.prefix(elenco.count - massimoFile) { try? FileManager.default.removeItem(at: f) }
    }
}

extension VoceCloud: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) {
        let id = ObjectIdentifier(p)
        Task { @MainActor in self.chiudi(id, ok) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(p)
        Task { @MainActor in self.chiudi(id, false) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.chiudi(id, true) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in self.chiudi(id, true) }
    }
}
