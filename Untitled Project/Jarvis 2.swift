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
    var interruzione: String? = nil   // l'ha interrotto mentre rispondeva a questa domanda: decide il cervello se la completa o è nuova
    /// Risposta interrotta: le frasi che JARVIS aveva detto per intero quando il signore l'ha fermato (vuoto: non aveva ancora
    /// cominciato). Nil: risposta detta tutta. Serve al cervello per riprendere dal punto giusto con «continua» (revisione del dialogo, 24 ott).
    var detto: String? = nil
    /// 7 nov (il signore): quello che va al cervello ma non si vede in chat (il Confidente: lo stato fisico di oggi). Prima la riga
    /// «[Stato fisico di oggi: …]» compariva nel messaggio del signore.
    var nascosto: String? = nil

    /// Come il messaggio viene ricordato al cervello nei turni successivi (solo testo).
    var testoPerCervello: String {
        if ruolo == "assistant", let detto { return Dialogo.rispostaInterrotta(testo, detto: detto) }
        let completo = nascosto.map { "\(testo)\n\($0)" } ?? testo
        let base = conFoto ? "(il signore ha mandato una foto) \(completo)" : completo
        if aggiunta == true { return "(aggiunta alla mia richiesta precedente, considerala insieme a quella) \(base)" }
        if let q = interruzione {
            return "(ti ho interrotto mentre rispondevi a «\(q)». Se questa frase completa, corregge o aggiunge qualcosa a quella richiesta, rispondi tenendo conto di tutte e due insieme; se è una domanda nuova, rispondi solo a questa, senza riprendere la risposta interrotta) \(base)"
        }
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
    /// Difetto 7 (controllo del 25 ott): vale anche sul Mac e parte acceso anche lì. Prima sul Mac partiva spento ma non contava:
    /// il Mac rispondeva comunque a qualsiasi frase. Acceso di partenza, oggi non cambia niente; spento, il Mac vuole «Jarvis».
    static var ascoltoSempre: Bool { UserDefaults.standard.object(forKey: "ascoltoSempre") as? Bool ?? true }
    /// La stessa app gira anche sul Mac (chip Apple): il cervello lo sa e risponde da Mac.
    nonisolated static var dispositivo: String { ProcessInfo.processInfo.isiOSAppOnMac ? "mac" : "iphone" }
    /// Idea B (25 ott): un numero per questa installazione (iPhone e Mac hanno ognuno il suo), così il cervello capisce quando
    /// due dispositivi gli mandano la stessa frase e fa rispondere uno solo.
    static var idDispositivo: String {
        if let id = UserDefaults.standard.string(forKey: "idDispositivoJarvis"), !id.isEmpty { return id }
        let nuovo = UUID().uuidString
        UserDefaults.standard.set(nuovo, forKey: "idDispositivoJarvis")
        return nuovo
    }
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

// MARK: - Idea D (25 ott): sul Mac la frase va al cervello come audio insieme alla richiesta della risposta

/// Una frase del Mac partita col giro unico: l'audio, da dove viene, la nota che il cervello le mette davanti e la presa per
/// chiudere la richiesta all'istante se la frase trascritta è un comando dell'app.
@MainActor
final class GiroUnicoMac {
    enum Origine { case ascolto(turno: Int), stanza(inizio: Date) }
    let audio: Data
    let origine: Origine
    let prefisso: String
    let fine: Date
    let presa = PresaRete()
    var gestito = false                   // «trascritto» già arrivato (un nuovo tentativo dopo la linea caduta lo ripete)
    private var fatto: (() -> Void)?      // l'attesa del Mac può mandare la frase che aspettava

    init(audio: Data, origine: Origine, prefisso: String, fine: Date, fatto: (() -> Void)?) {
        self.audio = audio; self.origine = origine; self.prefisso = prefisso; self.fine = fine; self.fatto = fatto
    }

    /// La frase è passata (accettata o rimandata alla strada di prima): l'attesa può andare avanti. Una volta sola.
    func libera() {
        let f = fatto
        fatto = nil
        f?()
    }
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
    /// 24 ott: il signore ha spento il microfono con un tocco sul reattore (in attesa). Finché non lo ritocca JARVIS non sente
    /// nulla: niente «Jarvis», niente battiti, niente «Ascolto sempre», niente ascolto automatico. Riaprendo l'app riparte acceso.
    @Published var micSpento = false {
        didSet { if micSpento != oldValue { aggiornaRichiamo() } }
    }
    /// La scritta della fase sotto il reattore: in attesa col microfono spento, «MICROFONO SPENTO».
    /// 9 nov (logica approvata dal signore): IN ATTESA (ascolta tutto), RISERVATO (solo «Jarvis»: scelto col tocco o con la musica),
    /// SPENTO (sordo: pressione lunga sul reattore).
    var etichettaFase: String {
        guard fase == .attesa else { return fase.rawValue }
        if micSpento { return "SPENTO" }
        return riservato || musicaSuona ? "RISERVATO" : fase.rawValue
    }
    /// 9 nov: RISERVATO scelto a mano (tocco sul reattore in attesa): sente solo «Jarvis», niente frasi, conversazioni, TV, battiti.
    @Published var riservato = false {
        didSet { if riservato != oldValue { aggiornaRichiamo() } }
    }
    private var spentoLungo = Date.distantPast     // la pressione lunga: il rilascio che segue non è un tocco
    /// 9 nov: pressione lunga sul reattore (o «Jarvis, spegni il microfono»): SPENTO, sordo davvero. Un tocco lo riaccende.
    func spegniMicrofono() {
        guard !micSpento else { return }
        spentoLungo = Date()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        Suoni.microfonoSpento()
        riservato = false
        micSpento = true
    }
    /// 9 nov (il signore: «mentre suona la canzone dico Jarvis, la musica si abbassa, ci parlo, risponde, e dopo uno o due secondi
    /// la musica risfuma verso l'alto»): mentre suona la musica (Apple Music, Spotify… o il player di Shazam) l'orecchio dell'attesa
    /// sente solo «Jarvis» (niente frasi senza nome, niente battiti di mani, niente orecchio mentre parla): prima sentiva la canzone
    /// (la voce del cantante, i colpi di batteria come battiti) e rispondeva da solo. Detto «Jarvis»: la musica si abbassa (l'ascolto
    /// ha .duckOthers), JARVIS ascolta e risponde; un secondo e mezzo dopo la risposta la musica risale. Anche il tocco sul reattore.
    @Published private(set) var musicaSuona = false {
        didSet {
            guard musicaSuona != oldValue else { return }
            aggiornaRichiamo()
        }
    }
    private var guardiaMusica: Task<Void, Never>?
    private var silenzioMusica = 0              // secondi di fila senza musica: fra due canzoni l'orecchio non si riaccende per un attimo

    /// Guarda una volta al secondo se suona musica (costa niente: legge solo lo stato dell'audio).
    private func seguiMusica() {
        guardiaMusica?.cancel()
        guardiaMusica = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.leggiMusica()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func leggiMusica() {
        // 9 nov: quattro letture insieme (una sola non bastava sul telefono): l'app Musica (anche dalla sezione Musica e da Shazam),
        // il player di Shazam dentro JARVIS (anteprima e video), e l'audio delle altre app (Spotify, un video)
        let sessione = AVAudioSession.sharedInstance()
        let altre: Bool = sessione.isOtherAudioPlaying || sessione.secondaryAudioShouldBeSilencedHint
        // 9 nov sera (il signore: «il disco gira sempre anche se la musica è spenta»): lo stato del lettore si leggeva solo a sezione
        // aperta; ora anche qui, una volta al secondo, così il disco nel Dock si ferma quando la musica si ferma (anche dall'isola)
        let lettore = LettoreMusica.condiviso
        lettore.aggiorna()
        let suona: Bool = altre || lettore.suona || lettore.fermataDaJarvis || AscoltoShazam.condiviso.suonaOra
        if suona { silenzioMusica = 0; musicaSuona = true; return }
        silenzioMusica += 1
        if silenzioMusica >= 2 { musicaSuona = false }
    }

    @Published var fase: Fase = .attesa {
        didSet {
            guard fase != oldValue else { return }
            AmbienteSonoro.condiviso.jarvisSuona(avvioInCorso || (Jarvis.usaAscoltoCloud && fase == .parlo))   // la musica d'avvio (e sul Mac la sua voce) non è «confusione»
            BattitoMani.jarvisParla(Jarvis.usaAscoltoCloud && fase == .parlo)   // Mac: la sua voce rientra dal microfono dell'attesa, non sono battiti
            EcoMac.condivisa.jarvisParla(Jarvis.usaAscoltoCloud && fase == .parlo)   // difetto 2: quello che sente mentre parla può essere eco
            aggiornaRichiamo()
            if dialogoFuori || IsolaJarvis.voceAccesa { aggiornaIsolaVoce() }   // 12 nov: l'isola VOCE segue il dialogo fuori dall'app
        }
    }
    @Published var parziale = ""
    @Published var stato: String?          // es. «cerco sul web»
    @Published var avviso: String?
    @Published var foto: Data?             // foto in attesa di essere mandata col prossimo messaggio
    private var fotoGiro: [Data] = []      // fotogrammi di un giro con gli occhi, in attesa del prossimo messaggio
    private var allegato: String?          // un testo lungo (la trascrizione del Wiretap) che parte col prossimo messaggio
    @Published var repartoRichiesto: Reparto?   // comando vocale: la schermata apre questo reparto
    var guidaTraccia = false                     // build 22: Ricordi › TRACCIA si apre con la Guida (fotocamera) accesa
    var salvaTraccia = false                     // build 22: Ricordi › TRACCIA salva subito il posto dove si trova («ricorda questo luogo»)
    var richiestaTraccia = false                 // 4 nov (strada B): chiesto TRACCIA a voce («traccia», «portami al», «ricorda questo luogo»):
                                                 // con Ricordi già aperto, si fa sul posto (ContentView.richiestaSulPosto)
    @Published var azioneLidar: ComandoVocale.AzioneLidar?   // comando vocale dentro LiDAR: lo esegue la sua schermata
    var lidarAperto = false                      // LiDAR aperto: valgono anche i suoi comandi («salva», «fine scansione»…)
    var sezioneAperta: Reparto?                  // la scheda aperta sopra la schermata principale: valgono anche i suoi tasti a voce
    @Published var diagnosiMac = ""             // Mac: la riga di controllo del microfono in attesa
    private var fraseAVoce = ""            // l'ultima frase detta a voce, in viaggio verso il cervello
    /// La risposta come arriva dal cervello, toni compresi («[whispers]»): serve alla voce; in chat e in cronologia va senza (TagVoce).
    private var testiGrezzi: [UUID: String] = [:]
    /// Sul Mac l'ascolto non usa il riconoscimento di Apple: registra e trascrive in cloud (AscoltoCloud.swift).
    nonisolated static var usaAscoltoCloud: Bool { ProcessInfo.processInfo.isiOSAppOnMac }
    private let registratore = RegistratoreVoce()
    /// Sul Mac, in attesa: battiti di mani e frasi trascritte in cloud, al posto del richiamo di Apple.
    private lazy var attesaMac: AttesaMac = {
        let a = AttesaMac(motore: motore)          // un solo motore audio sul Mac, quello che funziona già per il tocco
        a.applauso = { [weak self, weak a] in a?.segnaBattiti(); self?.applaudito() }
        a.diagnosi = { [weak self] riga in self?.diagnosiMac = riga }
        a.frase = { [weak self] testo, inizio, fine in self?.fraseSentitaMac(testo, inizio: inizio, fine: fine) ?? false }
        a.giroUnico = { [weak self] audio, inizio, eco, fatto in   // idea D: la frase in un giro solo, se si può
            self?.partiGiroUnico(audio, origine: .stanza(inizio: inizio), fine: eco.fine, fatto: fatto) ?? false
        }
        return a
    }()
    /// Sul Mac, subito dopo una risposta: per qualche secondo si può continuare a parlare senza dire «Jarvis».
    private var liberoMacFinoA = Date.distantPast
    /// Mac: ciò che JARVIS ha appena detto, per riconoscere la propria voce che rientra dal microfono (l'eco).
    private var dettoMac = ""
    private var dettoMacFino = Date.distantPast
    private var ascoltoCloud = false       // sta registrando una frase da trascrivere in cloud
    private var ultimaFraseAVoce = ""      // la frase della domanda in corso (vuota se scritta)
    /// Idea B (25 ott): quando il signore ha smesso di dire la frase che sta per partire (per l'arbitro del cervello).
    private var fineFraseVoce: Date?
    @Published var pagina: PaginaWeb?      // pagina aperta nel browser interno
    @Published var occhi: Occhiata? { didSet { if (occhi == nil) != (oldValue == nil) { aggiornaRichiamo() } } }   // fotocamera aperta (occhi di JARVIS)
    @Published var interprete: Lingua?     // modalità interprete aperta
    @Published var allenatore = false      // modalità allenatore aperta
    private var attesaOcchi: CheckedContinuation<[Data], Never>?

    let strumenti = Strumenti()

    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var motore = AVAudioEngine()
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timerSilenzio: Timer?
    private var timerTetto: Timer?
    private var baseAscolto = ""           // quanto detto prima che il riconoscimento ripartisse da capo
    private var precedenteAscolto = ""
    private var ultimoParzialeAscolto = Date.distantPast         // la frase dura al massimo un minuto (limite del riconoscimento vocale di Apple)
    private var turnoAscolto = 0           // ogni ascolto ha il suo numero: i callback di un ascolto vecchio vengono ignorati
    /// 11 nov (analisi del dialogo): quante volte, in questo ascolto, il riconoscimento è ripartito senza chiudere la frase.
    /// Prima un «frase finita» o un errore del riconoscimento di Apple mandava subito quello che c'era (anche tre parole).
    private var riavviiAscolto = 0
    /// 11 nov: i callback di un riconoscimento sostituito (ripartito) non contano più
    private var generazioneRic = 0
    /// 11 nov («ascoltami», regola del signore): in questo ascolto JARVIS aspetta 3,5 s di silenzio e lo lascia parlare fino a 90 s
    private var ascoltoLungo = false
    private var ascoltoLungoProssimo = false
    /// 11 nov: quando è arrivata l'ultima parola nuova (il suono da solo, senza parole, non tiene aperto l'ascolto all'infinito)
    private var ultimaParolaAscolto = Date.distantPast
    /// 11 nov (#16): il dialogo continua fuori dall'app; quando finisce il microfono si spegne
    /// Pubblicati: la schermata (ContentView) li legge per tenere acceso il microfono fuori dall'app finché il dialogo continua.
    @Published private(set) var dialogoFuori = false
    private var chiusuraFuori: Task<Void, Never>?
    @Published private(set) var micChiusoFuori = false   // dialogo finito fuori dall'app: microfono spento finché non torna nell'app
    /// 11 nov · risposta anticipata: la risposta preparata durante la pausa del signore (nil: nessuna)
    private var anticipo: Anticipo?
    private var timerAnticipo: Timer?
    private var anticipiTurno = 0                  // al massimo 3 per frase (ogni tentativo buttato costa circa un centesimo)
    private var anticipiButtati = 0
    private var anticipoSpentoFino = Date.distantPast   // il cervello ha detto «no_anticipo» (interruttore d'emergenza): 10 minuti senza
    /// 12 nov (A1): il cervello ha detto che il signore non aveva finito («[aspetto]») su questa frase: se la manda di nuovo uguale
    /// (ha taciuto), parte con `dopo_aspetto` e il cervello risponde comunque
    private var aspettoSu: String?
    /// 12 nov (A1): pausa minima di fine frase di questo ascolto (la risposta anticipata ha detto che il signore non aveva finito)
    private var pausaMinimaAscolto = 0.0
    /// 12 nov (A3): quando il signore ha cominciato a parlare in questo ascolto, e la riga su come ha parlato (per il cervello)
    private var inizioParlato: Date?
    private var voceCome: String?
    /// 12 nov (B4): la frase d'attesa preparata dal cervello per questa risposta (al posto di quella a caso)
    private var ponteDelCervello: String?
    /// 11 nov · dove comincia la finestra della conversazione mandata al cervello (scorre a scatti di 20 battute)
    private var inizioFinestra: UUID?
    /// 11 nov · i tempi del turno, misurati qui (vanno al cervello con la richiesta dopo)
    private var motivoChiusura = ""
    private var misura: [String: Any] = [:]
    private var misuraDa: Date?
    private var misuraTurno: UUID?
    private var tempiDaMandare: [String: Any]?

    private let sintesi = AVSpeechSynthesizer()
    private var bufferVoce = ""
    private var inCoda: Set<ObjectIdentifier> = []   // frasi consegnate alla sintesi e non ancora finite
    /// Le frasi della risposta in voce: a quale risposta appartengono e il loro testo (il ponte e gli annunci non ci sono).
    private var frasiRisposta: [ObjectIdentifier: (id: UUID, frase: String)] = [:]
    /// Quello che il signore ha sentito davvero della risposta in corso: solo le frasi finite (revisione del dialogo, H2).
    private var dettoRisposta: (id: UUID, testo: String)?
    private var frasiVive: [ObjectIdentifier: AVSpeechUtterance] = [:]   // tenute in vita finché il delegato risponde (id mai riciclati)
    private var flussoFinito = true
    private var rispostaIniziata = false     // la voce ha già cominciato a dire la risposta in corso
    /// Le frasi della risposta in corso già mandate alla voce (24 ott, punto 4): le ultime vanno a ElevenLabs come «prima»,
    /// così ogni frase continua l'intonazione di quella prima e la risposta suona come un discorso unico.
    private var frasiVoce: [String] = []
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
    var avvioInCorso = true {
        didSet {
            guard avvioInCorso != oldValue else { return }
            AmbienteSonoro.condiviso.jarvisSuona(avvioInCorso || (Jarvis.usaAscoltoCloud && fase == .parlo))   // la musica d'avvio non è «confusione»
            aggiornaRichiamo()
        }
    }
    private let orecchio = Orecchio()   // ascolta mentre JARVIS parla: «Jarvis», «basta»… lo interrompono
    private var compitoPonte: Task<Void, Never>?   // la frase «ponte» se il cervello tarda a rispondere
    private var ultimoPonte = Date.distantPast     // quando ha detto l'ultima frase ponte
    private var rispostaInterrotta: UUID?          // la risposta che il signore ha appena interrotto (per unire l'aggiunta)
    private var idTurno: UUID?                     // la risposta in preparazione o detta adesso: solo questa si può interrompere per unire
    private var domandaInterrotta: String?         // il testo della domanda interrotta (la risposta vuota sparisce subito, la domanda no)
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
    /// 12 nov (piano del dialogo): tolte le frasi che non stanno bene su qualunque domanda («Ottima domanda», «Ah, bella questa»,
    /// «Ah, interessante»…: su una brutta notizia stonavano) e meno «Sir». Quando la risposta tarda davvero (Opus) la frase la
    /// prepara il cervello sulla richiesta (`ponteDelCervello`); queste restano di riserva.
    static let ponti = [
        "Vediamo, Sir.", "Un attimo, Sir.", "Ci penso.", "Subito, Sir.", "Mi dia un istante.",
        "Un momento, Sir.", "Me ne occupo.", "Controllo subito.", "Lasci fare a me.", "Ci siamo quasi.",
        "Ricevuto, Sir.", "Ci guardo.", "Verifico, Sir.", "Con piacere.", "Mi metto all'opera.",
        "Sto raccogliendo i dati.", "Un istante soltanto.", "Lo trovo subito.", "Certamente, Sir.",
        "Lasci che ci pensi.", "Consulto i miei archivi.", "Ho capito, un momento.", "Ci sto lavorando.",
        "Faccio due conti.", "Arrivo, Sir.", "Elaboro.", "Un secondo e ci sono.",
        "Sto incrociando i dati.", "Mmh, vediamo un po'.", "Giusto, verifico.", "Mi lasci controllare.", "Recupero le informazioni.",
        "Ricevuto, ci penso io.", "Subito, controllo.", "Un attimo che guardo.", "Bene, vediamo cosa trovo.",
        "Ci rifletto un istante.", "Lo metto subito a fuoco.", "Dunque, vediamo.", "Sto mettendo insieme i pezzi.",
        "Ho quasi tutto.", "Un istante, sto verificando.", "Analizzo.",
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
        AmbienteSonoro.condiviso.jarvisSuona(true)   // si apre con la musica d'avvio: non è «confusione»
        sintesi.delegate = self
        seguiMusica()                                // 9 nov: con la musica l'orecchio dell'attesa sente solo «Jarvis»
        Task { await Jarvis.riscalda() }                                 // il cervello si sveglia mentre il signore guarda lo schermo
        if Impostazioni.voceCloud { cloud.prepara(Jarvis.ponti + [Dialogo.miDica]) }   // le frasi ponte sono già pronte in cache, a costo zero
        cloud.finita = { [weak self] chiave in self?.fraseFinita(chiave, detta: true) }   // il cloud avvisa solo le frasi suonate fino in fondo
        orecchio.interrotto = { [weak self] resto in self?.interrottoAVoce(resto) }
        orecchio.zittisci = { [weak self] in self?.zittisciPerAscolto() }
        richiamo.sveglia = { [weak self] in self?.richiamato() }
        richiamo.testo = { [weak self] t in if self?.fase == .ascolto { self?.parziale = t; self?.programmaAnticipo(t) } }
        richiamo.consegna = { [weak self] frase in self?.motivoChiusura = "richiamo"; self?.fraseRichiamo(frase) }
        cloud.iniziaFrase = { [weak self] chiave in self?.suonoIniziato(chiave) }   // 11 nov: il primo suono della risposta (i tempi)
        richiamo.applauso = { [weak self] in self?.applaudito() }
        IsolaJarvis.fineDialogo = { [weak self] in self?.fineDialogoFuori() }   // 12 nov: «Fine» sull'isola VOCE
        richiamo.inRisposta = { [weak self] in self?.fase == .elaboro && self?.idTurno != nil }   // idea C: una risposta in preparazione
        strumenti.apriOcchi = { [weak self] automatico, video, zoom in
            guard let self else { return [] }
            return await self.apriOcchi(automatico: automatico, video: video, zoom: CGFloat(zoom))
        }
        strumenti.apriPagina = { [weak self] url in self?.pagina = PaginaWeb(url: url) }
        strumenti.domandaOcchi = { [weak self] in self?.prendiDomandaOcchi() }
        OcchiAperti.parla = { [weak self] frase in self?.annuncia(frase) }   // build 23: la voce dagli Occhi («Ecco cosa ho trovato, Sir.»)
        // mentre la tastiera è aperta il battito di mani non conta (i click dei tasti lo ingannerebbero)
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
            BattitoMani.tastieraAperta(true)
        }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { _ in
            BattitoMani.tastieraAperta(false)
        }
        // una telefonata, Siri, un allarme si prendono l'audio: JARVIS si ferma come se l'avesse interrotto il signore
        // (dopo, «dicevi?» riprende da lì) e a chiamata finita il «Jarvis» in attesa torna ad ascoltare
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let tipo = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard let tipo else { return }
            Task { @MainActor [weak self] in self?.audioInterrotto(iniziato: tipo == .began) }
        }
        carica()
    }

    /// L'audio dell'iPhone è stato preso da altro (telefonata, Siri, allarme) o restituito.
    private func audioInterrotto(iniziato: Bool) {
        if iniziato {
            switch fase {
            case .parlo, .elaboro: segnaInterruzione(); interrompi()
            case .ascolto: fermaAscolto(invia: false)
            case .attesa: break
            }
            // il microfono dell'attesa si è spento: va riacceso da capo a chiamata finita, non lasciato acceso ma «sordo»
            if Jarvis.usaAscoltoCloud { attesaMac.ferma() } else { richiamo.ferma() }
        } else {
            aggiornaRichiamo()
        }
    }

    // MARK: Interazione

    func toccaReattore() {
        if Date().timeIntervalSince(spentoLungo) < 0.8 { return }   // 9 nov: il dito alzato dopo la pressione lunga non è un tocco
        fermaBenvenuto()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Suoni.tocco()
        switch fase {
        case .attesa:
            // 9 nov (logica approvata dal signore): SPENTO → il tocco lo riaccende e ascolta subito; con la musica il tocco ascolta
            // subito (la musica si abbassa); altrimenti il tocco passa fra IN ATTESA e RISERVATO (solo «Jarvis»)
            if micSpento { micSpento = false; Task { await avviaAscolto(bip: true) } }
            else if musicaSuona { LettoreMusica.condiviso.fermaPerJarvis(); Task { await avviaAscolto(bip: true) } }   // 9 nov sera: pausa, non sfuma
            else { riservato.toggle() }
        case .ascolto:
            if ascoltoCloud { chiudiAscoltoCloud(turno: turnoAscolto) } else { fermaAscolto(invia: true, toccato: true) }   // Mac: toccato = ho finito
        case .parlo, .elaboro:
            // 12 nov (il signore: «se clicco sul reattore mentre parla lo devo spegnere»): il tocco lo zittisce e basta, e JARVIS
            // torna in attesa nello stato di prima (IN ATTESA o RISERVATO). Prima il tocco lo zittiva e lo metteva in ascolto: se
            // aveva sentito per sbaglio, ripartiva da capo. La domanda interrotta resta: la frase dopo può completarla (come sempre)
            segnaInterruzione()
            ascoltaDopo = false             // dopo il tocco il microfono non si riapre da solo
            interrompi()
        }
    }

    func ascoltaSubito() {
        guard fase == .attesa else { return }
        Task { await avviaAscolto() }
    }

    /// Il signore ha iniziato a parlare mentre JARVIS parlava: JARVIS tace all'istante e resta in ascolto
    /// (l'orecchio continua a raccogliere la frase e la consegna a `interrottoAVoce` quando è finita).
    private func zittisciPerAscolto() {
        Posizione.scalda()                  // difetto 5: gli parla sopra, la frase nuova partirà fra poco: il GPS si sveglia ora
        segnaInterruzione()                 // prima di cambiare fase: serve per legare quello che sta per dire alla domanda di prima
        ascoltaDopo = false                 // gli ha parlato sopra («Mi dica, Sir», la domanda del diario): sta già ascoltando
        compitoPonte?.cancel()
        compitoRete?.cancel()
        compitoRete = nil
        occhiChiusi([])
        sintesi.stopSpeaking(at: .immediate)
        cloud.ferma()
        bufferVoce = ""
        inCoda.removeAll()
        frasiRisposta.removeAll()
        flussoFinito = true
        stato = "La ascolto, Sir…"
        strumenti.annullaInSospeso()
        orecchio.testoDetto = ""
        fase = .ascolto
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Il signore ha detto «Jarvis», «basta», «aspetta»… mentre JARVIS parlava, oppure ha finito la frase con cui l'ha interrotto.
    private func interrottoAVoce(_ resto: String) {
        fineFraseVoce = Date()              // idea B: la frase con cui l'ha interrotto è appena finita
        segnaInterruzione()
        interrompi()
        fase = .attesa
        stato = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if Jarvis.eSoloSilenzio(resto) { aggiuntaInArrivo = false; dopoAspetta = .no; return }   // «muto», «basta», «Jarvis, zitto»: resta in attesa
        let (pulito, chiedeAggiunta) = Jarvis.togliRichiamo(resto)
        if chiedeAggiunta { aggiuntaInArrivo = true }
        if !pulito.isEmpty, eseguiComando(pulito) { aggiuntaInArrivo = false; return }   // solo «aspetta»: niente comando, riascolta
        if !pulito.isEmpty {
            Task { await instrada(resto) }    // ha detto cosa vuole: «Jarvis, che ore sono», «aspetta, e anche…»
        } else if chiedeAggiunta {
            if Jarvis.usaAscoltoCloud {
                // Mac: la frase «Jarvis, aspetta» arriva appena trascritta, senza i 5 secondi dell'orecchio dell'iPhone. Come in
                // attesa (instrada): lo ascolta per il resto dei 5 secondi e solo se tace «Mi dica, Sir» (decisione del signore, 24 ott)
                aggiuntaInArrivo = true
                dopoAspetta = .aspetta
                if resto.lowercased().contains("ascolt") { ascoltoLungoProssimo = true }
                Task { await avviaAscolto(silenzio: max(1.5, Dialogo.silenzioDopoAspetta - Jarvis.pausaFineFrase(resto))) }
                return
            }
            // «aspetta, ascoltami» e poi silenzio: l'orecchio ha già aspettato i 5 secondi (decisione del signore, 24 ott)
            miDica()
        } else {
            aggiuntaInArrivo = false          // «basta», «zitto», «stop»: tace e torna in attesa, come una persona
        }
    }

    /// «Aspetta» e poi silenzio (deciso dal signore, 24 ott): dopo 5 secondi JARVIS dice «Mi dica, Sir» e lo ascolta,
    /// senza bip, come dopo la domanda del diario. Se tace ancora, torna in attesa in silenzio: non lo ripete.
    private enum DopoAspetta { case no, aspetta, miDica }
    private var dopoAspetta = DopoAspetta.no

    private func miDica() {
        dopoAspetta = .miDica
        if Impostazioni.muto { Task { await avviaAscolto() }; return }   // modalità muta: niente voce, ascolta e basta
        ascoltaDopo = true                       // finita la frase, il microfono si apre da solo
        annuncia(Dialogo.miDica)
    }

    /// Un messaggio scritto (Invia): se JARVIS stava pensando o rispondendo, vale come un'interruzione a voce (23 ott, chiesto dal signore):
    /// il cervello vede la domanda interrotta e decide se è il seguito o una domanda nuova, come nel dialogo a voce.
    func inviaScritto(_ testo: String) async {
        segnaInterruzione()                          // solo se c'è una risposta vera in corso (pensa o parla); altrimenti non fa niente
        if let q = interruzioneValida(), !testo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await invia(testo, interrottoSu: q)
        } else {
            await invia(testo)
        }
    }

    /// La domanda interrotta, se l'interruzione vale ancora: due minuti (deciso dal signore, 24 ott). Scaduta, sparisce
    /// e quello che il signore dice dopo è una domanda nuova (prima restava per sempre).
    private func interruzioneValida() -> String? {
        guard rispostaInterrotta != nil, let q = domandaInterrotta else { return nil }
        guard let quando = quandoInterrotto, Date().timeIntervalSince(quando) < Dialogo.validitaInterruzione else {
            rispostaInterrotta = nil; quandoInterrotto = nil; domandaInterrotta = nil
            return nil
        }
        return q
    }

    /// Ricorda quale risposta il signore sta interrompendo: se poi aggiunge qualcosa, va unito alla domanda di prima.
    private func segnaInterruzione() {
        // solo la risposta a una domanda in corso: non un annuncio di sezione, una notifica letta o una frase del Diario
        guard fase == .parlo || fase == .elaboro, let ultimo = messaggi.last, ultimo.ruolo == "assistant", ultimo.id == idTurno else { return }
        rispostaInterrotta = ultimo.id
        quandoInterrotto = Date()
        if let i = messaggi.lastIndex(where: { $0.id == ultimo.id }) {
            if i > 0, messaggi[i - 1].ruolo == "user" { domandaInterrotta = messaggi[i - 1].testo }
            // H2: nella conversazione resta il punto esatto in cui l'ha fermato (le frasi finite di dire, non tutto il testo
            // arrivato dal cervello, che arriva in pochi secondi mentre la voce ci mette molto di più)
            if let d = dettoRisposta, d.id == ultimo.id { messaggi[i].detto = d.testo } else { messaggi[i].detto = "" }
            salva()
        }
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
        dopoAspetta = .no
        ascoltaDopo = false                  // «muto»: niente microfono che si riapre da solo
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Parole di richiamo all'inizio della frase: «Jarvis», «aspetta», «ascoltami»…
    /// Restituisce la frase senza richiamo e se il signore sta chiaramente completando la richiesta di prima.
    nonisolated static func togliRichiamo(_ frase: String) -> (String, Bool) {
        let richiami = ["jarvis", "giarvis", "ehi", "hey", "bro", "fratello", "frate", "socio", "amico", "capo", "aspetta", "aspetti", "ascoltami", "mi ascolti", "ascolta", "un attimo",
                        "un momento", "un secondo", "fermati", "senti", "scusa", "no", "ah", "ok", "allora"]
        let segnaliAggiunta = ["aspetta", "aspetti", "ascoltami", "mi ascolti", "ascolta", "un attimo", "un momento", "un secondo"]
        let attacchi = ["aggiungo", "volevo aggiungere", "dimenticavo", "e poi", "inoltre", "anche", "e anche"]   // «un'altra cosa» è una domanda nuova (Seguito)
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

    /// 12 nov (A1, piano del dialogo approvato dal signore): il cervello dice che il signore non aveva finito («Gli ho detto»,
    /// «ci sono ancora delle…»). Come una persona, JARVIS non risponde: la risposta vuota sparisce, la domanda resta, e lo
    /// riascolta in silenzio. Quello che dice adesso è il seguito di quella frase (come dopo «aspetta»); se tace, dopo 5 secondi
    /// «Mi dica, Sir.», la stessa regola di «aspetta» decisa dal signore il 24 ottobre.
    private func aspettoDalCervello(id: UUID) {
        idTurno = nil
        compitoPonte?.cancel()
        compitoPonte = nil
        compitoRete = nil
        flussoFinito = true
        testiGrezzi[id] = nil
        stato = nil
        if let i = messaggi.firstIndex(where: { $0.id == id }), messaggi[i].testo.isEmpty { messaggi.remove(at: i); salva() }
        aspettoSu = messaggi.last(where: { $0.ruolo == "user" }).map { Jarvis.normaAnticipo($0.testo) }
        aggiuntaInArrivo = true
        dopoAspetta = .aspetta
        switch fase {
        case .ascolto:
            return                                   // ha già ripreso a parlare: lo sta ascoltando
        case .parlo:
            ascoltaDopo = true                       // stava dicendo la frase d'attesa: finita quella, il microfono si riapre
        case .elaboro, .attesa:
            fase = .attesa
            if richiamo.sveglio { return }           // il «Jarvis» in attesa sta già raccogliendo le sue parole
            Task { await avviaAscolto(silenzio: Dialogo.silenzioDopoAspetta) }
        }
    }

    /// Decide se la frase è una domanda nuova o il completamento della precedente, e la manda al cervello.
    private func instrada(_ fraseIntera: String) async {
        defer { scartaAnticipo() }              // 11 nov: una risposta anticipata non adottata (comando, «aspetta», muto…) si butta
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
            dopoAspetta = .aspetta
            if frase.lowercased().contains("ascolt") { ascoltoLungoProssimo = true }   // 11 nov: «ascoltami» = lo lascio finire
            // se tace: «Mi dica, Sir» 5 secondi dopo che ha smesso di parlare (la pausa di fine frase è già passata)
            await avviaAscolto(silenzio: max(1.5, Dialogo.silenzioDopoAspetta - Jarvis.pausaFineFrase(frase)))
            return
        }
        let riprende = chiede || aggiuntaInArrivo           // «aspetta…» detto adesso o un attimo fa
        aggiuntaInArrivo = false
        dopoAspetta = .no
        let interrottoSu = interruzioneValida()             // l'interruzione vale due minuti (deciso dal signore, 24 ott)
        defer { rispostaInterrotta = nil; quandoInterrotto = nil; domandaInterrotta = nil }
        // Come in una conversazione vera, decide il cervello (22 ott, chiesto dal signore): niente frasi incollate a forza.
        // L'aveva interrotto (tocco, «Jarvis», voce sopra, anche solo «muto»): il cervello vede la domanda interrotta,
        // la risposta tagliata e la frase nuova, e capisce lui se è il seguito (risponde a tutto insieme) o una domanda nuova.
        if let q = interrottoSu {
            let detta = pulito.isEmpty ? frase : pulito         // anche solo «no», «ok»: va con la sua domanda interrotta
            fraseAVoce = detta
            await invia(detta, interrottoSu: q)
            return
        }
        // non interrotto: se riprende il discorso («aspetta…», «ascoltami…», entro un minuto dall'ultima domanda)
        // la frase va come possibile seguito, e anche qui decide il cervello se completa quella di prima o è nuova
        let ultimaDomanda = messaggi.last(where: { $0.ruolo == "user" })
        let vicino = ultimaDomanda.map { Date().timeIntervalSince($0.data) < (riprende ? 300 : 60) } ?? false
        fraseAVoce = pulito.isEmpty ? frase : pulito   // solo una frase nuova e intera: se era un comando storpiato, si impara
        await invia(pulito.isEmpty ? frase : pulito, comeSeguito: vicino)
    }

    // MARK: Richiamo («Jarvis» in attesa)

    /// Acceso solo in attesa, con l'app in primo piano e nulla aperto sopra; spento in ogni altro momento.
    /// In attesa e mentre pensa (prima che inizi a parlare): «Jarvis» lo chiama o lo ferma. Mentre parla c'è l'orecchio.
    private var richiamoServe: Bool {
        !inBenvenuto && !avvioInCorso && !micSpento && !micChiusoFuori && Impostazioni.richiamo && richiamoConsentito
            && (fase == .attesa || (fase == .elaboro && !orecchio.attivo))
            && !(occhi != nil && fase == .elaboro)      // Occhi aperti dal cervello, che aspetta la foto: lì non si interrompe
    }

    private func aggiornaRichiamo() {
        if Jarvis.usaAscoltoCloud {                      // Mac: l'attesa la fa AttesaMac (battiti e frasi in cloud)
            avvioRichiamo?.cancel()
            // sul Mac sente anche mentre JARVIS parla o pensa (come l'orecchio dell'iPhone): così gli si parla sopra
            let serve = !inBenvenuto && !avvioInCorso && !micSpento && !musicaSuona && !riservato && Impostazioni.richiamo && richiamoConsentito && fase != .ascolto
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
        richiamo.soloNome = musicaSuona || riservato     // 9 nov: RISERVATO (a mano o con la musica): solo «Jarvis»
        avvioRichiamo?.cancel()
        guard richiamoServe else { richiamo.ferma(); restituisciMusica(); return }
        guard !richiamo.attivo else { return }
        // in attesa un attimo di respiro (il microfono di quando parlava si libera); mentre pensa, subito.
        // M6: prima erano 450 ms, per lasciar finire il segnale «pronto», che col richiamo acceso non suona mai: intanto
        // un «Perché?» detto appena JARVIS aveva finito cadeva nel vuoto
        restituisciMusica()                              // 9 nov: tornato in attesa con la musica, fra 1,5 s la musica risale
        // 9 nov: con la musica, finita la risposta l'orecchio riparte dopo che la musica è risalita (1,5 s, come vuole il signore)
        let ritardo = fase == .attesa ? (musicaSuona ? 1700 : 150) : 100
        avvioRichiamo = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(ritardo))
            guard let self, !Task.isCancelled, self.richiamoServe else { return }
            // 9 nov sera: con la musica, prima di riaccendere il «Jarvis» la musica dev'essere tornata su
            if self.musicaSuona, self.fase == .attesa { await self.rilasciaMusica() }
            guard !Task.isCancelled, self.richiamoServe, !self.richiamo.attivo else { return }
            self.richiamo.avvia()
        }
    }

    /// 9 nov: con la musica, tornato in attesa (anche da un ascolto senza frase) l'audio si restituisce:
    /// la musica abbassata dall'ascolto torna al suo volume. Un attimo dopo, così una domanda appena partita non la rialza.
    private func restituisciMusica() {
        guard musicaSuona, fase == .attesa, !Jarvis.usaAscoltoCloud else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            // 9 nov sera: la musica del lettore dentro JARVIS, messa in pausa per ascoltare, riparte da dove era
            if let self, self.fase == .attesa, self.inCoda.isEmpty, LettoreMusica.condiviso.fermataDaJarvis {
                await LettoreMusica.condiviso.riprendiDopoJarvis()
                return
            }
            guard let self, self.musicaSuona, self.fase == .attesa, self.inCoda.isEmpty, !self.inBenvenuto, !self.richiamo.attivo,
                  !AscoltoShazam.condiviso.suonaDentro else { return }   // la canzone di Shazam suona dentro JARVIS: l'audio resta acceso
            await self.rilasciaMusica()
        }
    }

    /// 9 nov sera (il signore: «dopo la risposta di Jarvis la musica non torna»): la musica abbassata torna su solo quando l'audio di
    /// JARVIS si spegne davvero. A volte iOS dice «occupato» (un suono che finisce, il microfono che si libera) e prima non si
    /// riprovava: la musica restava bassa. Ora: niente più «abbassa gli altri», poi si spegne, riprovando fino a 6 volte (2 s).
    func rilasciaMusica() async {
        let sessione = AVAudioSession.sharedInstance()
        for _ in 0..<6 {
            guard fase == .attesa, inCoda.isEmpty, !richiamo.attivo, !AscoltoShazam.condiviso.suonaDentro,
                  !LettoreMusica.condiviso.suona, !LettoreMusica.condiviso.fermataDaJarvis else { return }   // la musica è nostra: l'audio resta
            try? sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            do { try sessione.setActive(false, options: .notifyOthersOnDeactivation); return } catch {
                try? await Task.sleep(for: .milliseconds(330))
            }
        }
    }

    /// Ha sentito «Jarvis»: reattore in ascolto, il richiamo continua a raccogliere la frase.
    private func richiamato() {
        anticipiTurno = 0                                // 11 nov: una frase nuova dopo «Jarvis»: fino a 3 risposte anticipate
        scartaAnticipo()
        Posizione.scalda()                               // difetto 5: il GPS si sveglia mentre il signore dice la frase
        // 9 nov: con la musica il microfono dell'attesa non abbassa la canzone: detto «Jarvis», si passa all'ascolto vero, che la
        // abbassa (.duckOthers); il bip dice di parlare. Sul Mac l'attesa con la musica è spenta come prima.
        if musicaSuona, !Jarvis.usaAscoltoCloud {
            if fase == .elaboro { segnaInterruzione(); interrompi() }
            richiamo.ferma()
            LettoreMusica.condiviso.fermaPerJarvis()     // 9 nov sera: il lettore dentro JARVIS non si abbassa: pausa, riparte dopo
            Task {
                await avviaAscolto(bip: true)
                if fase == .attesa { aggiornaRichiamo() }   // l'ascolto non è partito: il «Jarvis» in attesa torna acceso
            }
            return
        }
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
        guard fase == .attesa, !inBenvenuto, !musicaSuona, !riservato else { return }   // 9 nov: con la musica (e in RISERVATO) niente battiti
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
        fineFraseVoce = richiamo.ultimaVoce                     // idea B: l'ultima parola sentita
        parziale = ""
        fase = .attesa
        let testo = frase.trimmingCharacters(in: .whitespacesAndNewlines)
        if testo.isEmpty { scartaAnticipo(); return }   // ha detto solo «Jarvis» e poi nulla: torno in attesa
        if foto == nil, eseguiComando(testo) { scartaAnticipo(); return }
        Task { await instrada(testo) }
    }

    // MARK: Comandi vocali

    // MARK: Sottovoce («Jarvis, piano, …»)

    /// «Piano, …» / «sottovoce»: JARVIS risponde sottovoce (in chiesa, in riunione, con qualcuno che dorme…) per 10 minuti,
    /// e ogni «piano» li rinnova. «Voce normale» (o «parla normale», «alza la voce») torna come prima.
    /// Revisione del dialogo (24 ott, M1): quando una parola è l'ordine e quando no lo decide `Dialogo.volume`, uguale sull'orologio
    /// («qual è il piano per stasera?» e «ma è una voce normale?» sono domande, non ordini).
    private static var sottovoceFino = Date.distantPast
    static var volumeVoce: Float { Date() < sottovoceFino ? 0.05 : 1 }   // sottovoce: appena udibile, da vicino

    /// Toglie «piano» dalla frase (e accende il sottovoce) o riconosce «voce normale»; restituisce il resto della frase.
    private func sottovoce(_ frase: String) -> String {
        let (resto, cambio) = Dialogo.volume(frase)
        switch cambio {
        case .normale?:
            Jarvis.sottovoceFino = .distantPast
            stato = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return ""
        case .sottovoce?:
            Jarvis.sottovoceFino = Date().addingTimeInterval(600)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if resto.isEmpty { stato = "🤫 Sottovoce"; return "" }
            return resto
        case nil:
            return frase
        }
    }

    /// Se la frase è un comando («attiva la Sentinella», «apri il Wiretap», «fai un giro»), apre il reparto e risponde vero.
    @discardableResult
    func eseguiComando(_ fraseIntera: String) -> Bool {
        // niente detto (silenzio): non è un comando. Prima risultava «fatto» e, dopo un «aspetta» seguito dal silenzio,
        // l'attesa dell'aggiunta non si chiudeva mai (revisione del dialogo, M5)
        guard !fraseIntera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let fatto = eseguiComandoLocale(fraseIntera)
        // un comando eseguito (sezione, LiDAR, Interprete, tasto di una scheda, Browser, rito…) è un'azione nuova:
        // la domanda interrotta prima non si porta dietro
        if fatto, !fraseIntera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chiudiInterruzione() }
        return fatto
    }

    private func eseguiComandoLocale(_ fraseIntera: String) -> Bool {
        let frase = sottovoce(fraseIntera)
        if frase.isEmpty { return true }                    // solo «sbatti» o «voce normale»: fatto
        if Benvenuto.eFraseDiTony(frase) { fraseDiTony(); return true }
        // 9 nov (logica approvata dal signore): «spegni il microfono» = SPENTO (come la pressione lunga sul reattore)
        let ordine = frase.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?;:"))
        if ["spegni il microfono", "spegni microfono", "microfono spento", "chiudi il microfono"].contains(ordine) {
            spegniMicrofono()
            annuncia("Microfono spento, Sir. Un tocco sul reattore e torno ad ascoltarla.")
            return true
        }
        // build 22: i comandi a frase esatta («protocollo notte», «radar pioggia»…): subito, senza cervello, prima delle storpiature
        if let d = ComandoDedicato.riconosci(frase) {
            // build 23: dentro LiDAR «mostrami la stanza in 3D» è il 3D di LiDAR (come «mostrami il 3D»), non SATELLITE
            // che chiude LiDAR e va a cercare un luogo chiamato «Stanza»
            if lidarAperto, case .satellite(.mostra(_)) = d {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                azioneLidar = .tre
                return true
            }
            eseguiDedicato(d)
            return true
        }
        // build 23: gli Occhi alla Stark («mostra le etichette», «scansione olografica», «cerca questo sul web»…), a frase esatta
        if !lidarAperto, let o = ComandoOcchi.riconosci(frase) { eseguiOcchi(o); return true }   // dentro LiDAR no: lì la fotocamera è sua
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
            chiudiInterruzione()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            chiudiChiesto = true
            return true
        case .lidar(let azione)?:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if case .modo(let chiave, let nome) = azione, !lidarAperto, let m = ModoLidar(rawValue: chiave) {   // LiDAR 23: «metro laser» da fuori apre LiDAR già sul modo
                LidarAperta.richiesta = (m, nome, true)
                // 4 nov (strada B): la frase del modo la dice LiDAR quando il modo parte (VistaLidar.avviaModo): appena aperto, o
                // già aperto dietro dopo «SALVARE LA SCANSIONE?» se c'è una scansione da salvare
                apriReparto(.lidar, annuncia: false)
                return true
            }
            azioneLidar = azione
            return true
        case .pagina(let sezione, let voce, let scheda)?:     // MARK X: STUDIO e SOCIAL, la pagina del mockup
            apriPagina(sezione, voce: voce, scheda: scheda)
            return true
        case .interprete(let codice)? where !lidarAperto:
            apriInterprete(codice)
            return true
        case .rapido(let azione)?:
            rapido(azione)
            return true
        case let c? where c.navigaSezioni:         // MARK XI: «sezioni aperte», «quella di prima», «chiudi il meteo»… (ContentView)
            chiudiInterruzione()
            ComandiSezioni.invia(c)
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
            case .occhiGira, .occhiZoomAvanti, .occhiZoomIndietro, .occhiZoomNormale:
                if let c = OcchiAperti.comando, c(azione) { return true }
                return true                               // fotocamera occupata un attimo: niente scatto per sbaglio
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

    /// Build 22: un comando a frase esatta apre la sua sezione, già sul pannello giusto.
    private func eseguiDedicato(_ d: ComandoDedicato) {
        switch d {
        case .protocollo(let p):
            Protocolli.condiviso.richiedi(p)     // la tendina PROTOCOLLI scende e lo avvia, come il tasto «Avvia» (ContentView)
        case .traccia: guidaTraccia = false; salvaTraccia = false; richiestaTraccia = true; apriReparto(.ricordi)   // Ricordi su TRACCIA, con la bussola
        case .guida: guidaTraccia = true; salvaTraccia = false; richiestaTraccia = true; apriReparto(.ricordi)      // TRACCIA con la Guida già accesa
        case .salvaLuogo: guidaTraccia = false; salvaTraccia = true; richiestaTraccia = true; apriReparto(.ricordi) // TRACCIA salva il posto dove si trova
        case .radar: apriReparto(.meteo)          // RADAR è in testa al Meteo
        case .priorita: apriReparto(.email)       // PRIORITÀ è in testa all'Email
        case .organismo: apriReparto(.vitals)
        case .ologramma:                          // build 23: il Trainer già sull'Ologramma (a mano si apre sul Busto)
            let giaAperto = allenatore            // il Trainer era già aperto: passa all'Ologramma e basta
            MotoreAllenatore.ologrammaRichiesto = true
            NotificationCenter.default.post(name: .jarvisOlogramma, object: nil)
            if giaAperto {
                // decisione 28: «modalità ologramma» detto dentro il Trainer risponde «Ologramma, Sir.» (non «Personal trainer pronto»)
                apriReparto(.allenatore, annuncia: false)
                flussoFinito = true               // una frase sola: finita quella, JARVIS torna in attesa (come gli annunci)
                accodaVoce("Ologramma, Sir.", forza: true)
            } else {
                apriReparto(.allenatore)
            }
        case .allenamento:                        // «allenati allo specchio»: il Trainer, come il mockup 23
            apriReparto(.allenatore)
        case .satellite(let a):                   // build 23: SATELLITE si apre e fa la sua cosa (guida, naviga, ricognizione, 3D)
            RichiestaSatellite.condivisa.azione = a
            apriReparto(.satellite)
        case .fermaGuida:                         // build 23: la GUIDA di SATELLITE si ferma, anche a Satellite chiuso
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let c_era = MotoreGuida.condiviso.attiva
            MotoreGuida.condiviso.ferma()
            annuncia(c_era ? "Guida fermata, Sir." : "Non c'è nessuna guida in corso, Sir.")
        }
    }

    /// Build 23: un comando degli Occhi. Aperti (manuali) agisce lì e JARVIS dice la sua frase; chiusi, si aprono già così.
    private func eseguiOcchi(_ c: ComandoOcchi) {
        chiudiInterruzione()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if occhi != nil, let f = OcchiAperti.stark, f(c) {
            if let r = c.risposta { annuncia(r) }
            return
        }
        if case .aereo("AEREO_OFF", _) = c {                     // MARK X: a Occhi chiusi non c'è niente da spegnere
            annuncia("La ricerca degli aerei è già spenta, Sir.")
            return
        }
        if let r = c.risposta ?? c.annuncioApertura ?? Reparto.occhi.annuncio { annuncia(r) }
        guardaManuale(iniziale: c)
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
    /// Un comando (sezione, «chiudi», comando rapido): è un'azione nuova, la domanda interrotta prima non si porta dietro.
    private func chiudiInterruzione() {
        rispostaInterrotta = nil
        quandoInterrotto = nil
        domandaInterrotta = nil
        aggiuntaInArrivo = false
        dopoAspetta = .no
    }

    private func rapido(_ a: ComandoVocale.AzioneRapida) {
        chiudiInterruzione()
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

    /// MARK X: STUDIO e SOCIAL, la pagina del mockup («crea una piastra…», «apri Instagram»). `parla`: JARVIS dice la sua frase;
    /// no quando la frase arriva dal microfono del Wiretap (4 nov: la sua voce finirebbe nella registrazione).
    func apriPagina(_ sezione: String, voce: String?, scheda: String?, parla: Bool = true) {
        chiudiInterruzione()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        var a = AperturaPagina(sezione: sezione, voce: voce, scheda: scheda)
        if sezione == "Studio", let v = voce, v.contains("plastico") || v.contains("nello studio") {   // la sala vera, non quella d'esempio
            let p = PaginaMarkX.plasticoDaArchivio(PaginaMarkX.tipoPlastico(v))
            if parla { annuncia(p.frase) }
            guard let json = p.json else { return }
            a = AperturaPagina(sezione: "Studio", lidar: json)
        } else if parla {
            annuncia(PaginaMarkX.annuncio(a))
        }
        // 4 nov · MARK XI: niente più «chiudi» prima (chiudeva la sezione davanti, Occhi compresi): Studio o Social salgono
        // e quella davanti va dietro da sola, viva, come nel mockup (ContentView, .jarvisApriPagina)
        PaginaMarkX.apri(a)
    }

    /// Apre un reparto o una scheda; `annuncia`: dice la sua frase (non serve quando l'ha già detto il cervello).
    private func apriReparto(_ reparto: Reparto, annuncia: Bool = true) {
        chiudiInterruzione()
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
    func apriOcchi(automatico: Bool, video: Bool = false, cucina: Bool = false, zoom: CGFloat = 1, iniziale: ComandoOcchi? = nil) async -> [Data] {
        // LiDAR sta scansionando: la foto viene dalla sua fotocamera, senza aprire Occhi né fermare la scansione
        if let scatta = OcchiLidar.scatta { return scatta().map { [$0] } ?? [] }   // niente fotogramma: nessuna foto, ma la scansione resta
        if soccorsoAperto { return [] }               // il Tocco d'aiuto di Bea è aperto: non si copre mai
        // 4 nov · MARK XI: la sezione davanti non si chiude più prima («cosa vedi?» dal Meteo chiudeva il Meteo): gli Occhi salgono
        // e lei va dietro da sola, viva, come nel mockup. Quello che sta sopra a tutto (la pagina web, il menu SISTEMI) lo chiude
        // la schermata principale (ContentView, liberaSopra).
        occhiChiusi([])                        // se ne era rimasta aperta una, si chiude
        return await withCheckedContinuation { (c: CheckedContinuation<[Data], Never>) in
            attesaOcchi = c
            var o = Occhiata(automatico: automatico, video: video, cucina: cucina, zoom: zoom)
            switch iniziale {                  // build 23: aperti a voce, acceso solo quello che chiede
            case .etichette(true)?: o.eti = true
            case .ologramma(true)?: o.olo = true
            case .aggancia?: o.olo = true; o.aggancia = true
            case .studio?: o.manda = "studio"          // MARK X: a fuoco e parte da sola verso lo Studio
            case .social?: o.manda = "social"
            case .aereo(let p, let f)?: o.aereo = (p: p, frase: f)     // MARK X · AEREO: aperti, cercano e agganciano
            default: break
            }
            occhi = o
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
    /// `iniziale`: aperti a voce con un comando degli Occhi (build 23).
    func guardaManuale(iniziale: ComandoOcchi? = nil) {
        Task {
            let dati = await apriOcchi(automatico: false, iniziale: iniziale)
            let detta = prendiDomandaOcchi()
            guard !dati.isEmpty else { return }
            preparaFoto(dati)
            await invia(detta ?? (dati.count > 1 ? "Cosa vedi in questo giro?" : "Cosa vedi?"))
        }
    }

    /// MARK XI: gli Occhi tornano davanti dalle sezioni aperte (erano dietro, in pausa): la stessa inquadratura (le stesse
    /// impostazioni) e JARVIS riaspetta la foto, come quando li si apre dall'icona.
    func riprendiOcchi(_ o: Occhiata) {
        occhiChiusi([])
        Task {
            let dati = await withCheckedContinuation { (c: CheckedContinuation<[Data], Never>) in
                attesaOcchi = c
                occhi = o
            }
            let detta = prendiDomandaOcchi()
            guard !dati.isEmpty else { return }
            preparaFoto(dati)
            if o.cucina {
                await invia(detta.map { "Cucina: \($0)" } ?? "Cosa cucino stasera con quello che vedi? Proponimi due o tre piatti e dimmi se manca qualcosa da mettere nella lista della spesa.")
            } else {
                await invia(detta ?? (dati.count > 1 ? "Cosa vedi in questo giro?" : "Cosa vedi?"))
            }
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
        idTurno = nil                            // una lettura (notifiche, briefing) non è la risposta a una domanda
        interrompi()
        let mostrato = TagVoce.togli(t).trimmingCharacters(in: .whitespacesAndNewlines)   // i toni della voce non si vedono
        if !mostrato.isEmpty { messaggi.append(Messaggio(ruolo: "assistant", testo: mostrato)) }
        salva()
        flussoFinito = true
        accodaVoce(t, forza: true)
    }

    func interrompi() {
        idTurno = nil                       // la risposta è fermata: un annuncio o un errore detti dopo non sono più «la risposta»
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
        frasiRisposta.removeAll()
        flussoFinito = true
        stato = nil
        strumenti.annullaInSospeso()        // interrotto: niente chiamate/app aperte più tardi a sorpresa
        if fase != .ascolto { fase = .attesa }
    }

    func invia(_ testoGrezzo: String, unisciA: UUID? = nil, comeAggiunta: Bool = false, comeSeguito: Bool = false, interrottoSu: String? = nil,
               nascosto: String? = nil) async {
        rispostaInterrotta = nil                      // una domanda è partita (anche scritta): l'interruzione di prima è chiusa
        quandoInterrotto = nil
        domandaInterrotta = nil
        aggiuntaInArrivo = false
        dopoAspetta = .no
        ultimaFraseAVoce = fraseAVoce                 // vuota se la domanda è scritta: si imparano solo le frasi dette a voce
        fraseAVoce = ""
        // idea A e B (25 ott): la frase detta a voce lo dice al cervello (sforzo di Opus, un solo JARVIS risponde)
        let fineVoce: Date? = ultimaFraseAVoce.isEmpty ? nil : (fineFraseVoce ?? Date())
        fineFraseVoce = nil
        // 12 nov (A1): la stessa frase su cui il cervello aveva detto «aspetto», e il signore non ha aggiunto altro
        let dopoAspetto = aspettoSu != nil && aspettoSu == Jarvis.normaAnticipo(testoGrezzo)
        aspettoSu = nil
        let comeParla = fineVoce == nil ? nil : voceCome      // A3: solo per le frasi dette a voce
        voceCome = nil
        ponteDelCervello = nil
        // 11 nov: il ritmo del signore. Ha ripreso a parlare subito dopo che la frase era stata chiusa (aggiunta): era stato tagliato,
        // la prossima volta JARVIS aspetta un po' di più; una frase detta e chiusa bene riporta piano ai tempi normali
        if fineVoce != nil { if unisciA != nil || comeAggiunta { RitmoSignore.condiviso.ripresa() } else { RitmoSignore.condiviso.fraseChiusaBene() } }
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
            if comeAggiunta { m.aggiunta = true } else if let q = interrottoSu { m.interruzione = q } else if comeSeguito { m.seguito = true }
            if let n = nascosto?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { m.nascosto = n }
            // 11 nov · risposta anticipata: la frase è proprio quella su cui JARVIS stava già preparando la risposta? Allora si
            // adotta quella (è già pronta o quasi) invece di farne un'altra
            if let a = anticipo, !a.adottato, fotoDaMandare == nil, giroDaMandare.isEmpty, allegatoDaMandare == nil, a.vale(per: m, dopo: messaggi.last?.id) {
                adotta(a, fineVoce: fineVoce)
                return
            }
            messaggi.append(m)
        }
        scartaAnticipo()
        let recenti = finestraCervello()
        let storia: [[String: Any]] = recenti.map(Jarvis.perCervello)
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
        idTurno = risposta.id
        salva()
        iniziaMisura(id: risposta.id, fineVoce: fineVoce, anticipo: "nessuno")

        ultimoInvio = Date()
        rispostaIniziata = false
        frasiVoce = []
        dettoRisposta = (risposta.id, "")
        richiamo.liberoFinoA = Date().addingTimeInterval(Dialogo.finestraAggiunta)   // nei primi 2 secondi può continuare a parlare senza dire «Jarvis»
        richiamo.seguitoFinoA = .distantPast
        fase = .elaboro
        flussoFinito = false
        let fotoDaRimettere = fotoStoria
        compitoRete = Task { await self.turno(storia: storia, foto: fotoDaMandare, giro: giroDaMandare, allegato: allegatoDaMandare,
                                              fotoStoria: fotoDaRimettere, id: risposta.id, fineVoce: fineVoce,
                                              dopoAspetto: dopoAspetto, comeParla: comeParla) }
        // interrotto e subito un'aggiunta: una persona risponde e basta, non riempie di nuovo il vuoto
        let appenaRiempito = Date().timeIntervalSince(ultimoPonte) < 20
        if unisciA == nil && !comeAggiunta && !appenaRiempito { armaPonte(id: risposta.id, testo: testo) }
        else { compitoPonte?.cancel(); inizioTurno = Date() }
    }

    /// Se il cervello non ha ancora detto nulla, JARVIS riempie l'attesa con una frase breve.
    /// Decisione del signore (24 ott, H3): il riempitivo parte solo dopo i 2 secondi in cui JARVIS ascolta ancora un'aggiunta.
    /// Prima partiva dopo 0,4–1 s: la voce spegneva quell'ascolto e la seconda frase detta subito («…e anche domani») si perdeva.
    private func armaPonte(id: UUID, testo: String) {
        compitoPonte?.cancel()
        inizioTurno = Date()
        guard !Impostazioni.muto, testo.count > 6 else { return }      // «pausa», «avanti»: rispondono già in un lampo
        let finestra = max(0, richiamo.liberoFinoA.timeIntervalSinceNow)
        compitoPonte = Task { @MainActor [weak self] in
            // niente «mh» o mezze parole (suonano come un balbettio): solo frasi intere, e solo se serve davvero
            try? await Task.sleep(for: .milliseconds(Int(finestra * 1000) + 100))
            // il signore sta parlando proprio adesso (l'ascolto lo sente, anche se non è per me): non gli parlo sopra
            var giri = 0
            while giri < 10, !Task.isCancelled, Date().timeIntervalSince(self?.richiamo.ultimaVoce ?? .distantPast) < 0.6 {
                try? await Task.sleep(for: .milliseconds(300))
                giri += 1
            }
            guard let self, !Task.isCancelled, self.attesaVuota(id) else { return }
            self.ultimoPonte = Date()
            // 12 nov (B4): la frase del cervello che riprende la richiesta, se è arrivata; se no, una di riserva
            let frase = self.ponteDelCervello ?? Jarvis.ponteCasuale()
            self.ponteDelCervello = nil
            self.dici(frase)
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
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            if let voce = o["voce"] as? String, !voce.isEmpty { UserDefaults.standard.set(voce, forKey: "vocePredefinitaCloud") }
            if let parole = o["parole"] as? [String] { UserDefaults.standard.set(parole, forKey: "paroleRiconoscimento") }   // 12 nov (A4)
            // idea D (25 ott): il cervello sa ricevere la frase come audio insieme alla richiesta della risposta (Mac)
            UserDefaults.standard.set(o["giro_unico"] as? Bool ?? false, forKey: "giroUnicoCervello")
        }
    }

    func nuovaConversazione() {
        interrompi()
        scartaAnticipo()
        inizioFinestra = nil
        messaggi.removeAll()
        fotoRecenti = []
        idFotoRecente = nil
        salva()
    }

    // MARK: Un turno di dialogo con il cervello (streaming + strumenti del telefono)

    /// `lascia` e `ripiega`: idea D, il giro unico si ferma dopo la trascrizione (frase da fare come prima, trascrizione fallita).
    fileprivate enum Esito { case fine(String, [String]), client([String: Any]), errore(String), doppione, lascia(String), ripiega,
                         sospeso([String: Any]), noAnticipo, aspetto }

    private func turno(storia: [[String: Any]], foto: Data?, giro: [Data] = [], allegato: String? = nil,
                       fotoStoria: (Int, [Data])? = nil, id: UUID, fineVoce: Date? = nil, unico: GiroUnicoMac? = nil,
                       primo: Esito? = nil, dopoAspetto: Bool = false, comeParla: String? = nil) async {
        defer { unico?.libera() }          // idea D: l'attesa del Mac può mandare la frase dopo, qualunque cosa succeda qui
        var corpo: [String: Any] = ["messaggi": storia, "dispositivo": Impostazioni.dispositivo, "strumenti_client": Strumenti.nomi]
        if let unico {
            // idea D: la frase come audio; il cervello la trascrive, la mette dopo la cronologia con la nota e risponde
            corpo["audio_domanda"] = unico.audio.base64EncodedString()
            corpo["formato_audio"] = "wav"
            corpo["prefisso_domanda"] = unico.prefisso
        }
        if let fineVoce {
            // idea A: detta a voce (Opus risponde più svelto); idea B: se un altro dispositivo ha sentito la stessa frase,
            // il cervello fa rispondere uno solo e all'altro manda «doppione»
            corpo["a_voce"] = true
            corpo["arbitro"] = ["id": Impostazioni.idDispositivo, "fine": Int(fineVoce.timeIntervalSince1970 * 1000)] as [String: Any]
            // 12 nov (A1): l'app sa ascoltare ancora se il cervello dice che il signore non ha finito; A3: come ha parlato
            corpo["capisce_aspetto"] = true
            if dopoAspetto { corpo["dopo_aspetto"] = true }
            if let comeParla { corpo["voce_come"] = comeParla }
        }
        corpo["ponte_contesto"] = true      // 12 nov (B4): con Opus il cervello prepara la frase d'attesa sulla richiesta
        if let fs = fotoStoria {      // la foto di poco fa, rimessa al suo posto nella conversazione
            corpo["foto_storia"] = ["indice": fs.0, "immagini": fs.1.map { $0.base64EncodedString() }] as [String: Any]
        }
        if let foto { corpo["immagine"] = foto.base64EncodedString() }
        if !giro.isEmpty { corpo["immagini"] = giro.map { $0.base64EncodedString() } }   // i fotogrammi del giro, in ordine
        if let allegato { corpo["allegato"] = allegato }                                  // la trascrizione del Wiretap
        // 8 nov notte: la sezione aperta e cosa mostra (campi scritti, voce aperta, risultati): JARVIS vede quello che vede lui
        if let schermo = Schermo.perCervello(sezione: sezioneAperta) { corpo["schermo"] = schermo }
        let inizioGps = Date()
        let posizione = await Posizione.attuale()          // dove si trova il signore: serve alla seconda memoria
        if misuraTurno == id { misura["ms_gps"] = Int(Date().timeIntervalSince(inizioGps) * 1000) }
        if let posizione { corpo["posizione"] = posizione }
        // 11 nov: i tempi del turno di prima (solo se questa richiesta parte davvero: con l'anticipo adottato è già fatta)
        if primo == nil, let t = tempiDaMandare { corpo["tempi_app"] = t; tempiDaMandare = nil }
        // iOS ci lascia finire la risposta anche se lo schermo si spegne o il signore cambia app per un momento
        let sfondo = UIApplication.shared.beginBackgroundTask(withName: "jarvis-risposta") { }
        defer { if sfondo != .invalid { UIApplication.shared.endBackgroundTask(sfondo) } }
        do {
            var pronto = primo                 // 11 nov: l'esito della risposta anticipata adottata (la sua richiesta è già fatta)
            for _ in 0..<6 {
                // ogni passo ha un suo numero: se la linea cade e si riprova, il cervello riconosce la stessa richiesta e non ripete le azioni
                let esito: Esito
                if let p = pronto { esito = p; pronto = nil }
                else { esito = try await flussoConRitentativi(corpo, id: id, richiesta: UUID().uuidString, unico: unico) }
                try Task.checkCancellation()
                switch esito {
                case .noAnticipo:
                    // la risposta anticipata non c'era (interruttore d'emergenza): la domanda parte adesso, come prima
                    anticipoSpentoFino = Date().addingTimeInterval(600)
                    corpo["anticipo"] = nil
                    pronto = nil
                    continue
                case .sospeso(let e):
                    // 11 nov: l'anticipo si era fermato davanti a uno strumento; il signore ha finito: gli strumenti partono adesso
                    let continua: [String: Any] = ["lavoro": e["lavoro"] ?? [Any](), "modello": e["modello"] ?? "", "azioni": e["azioni"] ?? [Any](),
                                                   "detto": e["detto"] ?? "", "esegui": true]
                    corpo = ["messaggi": [Any](), "dispositivo": Impostazioni.dispositivo, "strumenti_client": Strumenti.nomi, "continua": continua]
                    if let posizione { corpo["posizione"] = posizione }
                case .fine(let testo, let azioni):
                    concludi(id: id, testo: testo, azioni: azioni)
                    return
                case .aspetto:
                    aspettoDalCervello(id: id)      // 12 nov (A1): il signore non aveva finito: JARVIS lo riascolta in silenzio
                    return
                case .errore(let msg):
                    idTurno = nil                   // un messaggio d'errore non è una risposta da completare
                    concludiConErrore(id: id, msg)
                    return
                case .doppione:
                    concludiDoppione(id: id)        // idea B: risponde un altro dispositivo
                    return
                case .lascia(let testo):
                    // idea D: la frase trascritta non è una domanda da mandare così (un comando, «muto», l'eco…): la richiesta è
                    // già chiusa, e con il testo si fa esattamente come prima
                    if let unico { await lasciaGiroUnico(unico, testo: testo, errore: nil) }
                    return
                case .ripiega:
                    // idea D: il cervello non è riuscito a trascrivere: la trascrizione di prima, poi come prima
                    if let unico {
                        let (testo, errore) = await RegistratoreVoce.trascrivi(unico.audio, token: Portachiavi.leggi(), indirizzo: Impostazioni.indirizzo)
                        await lasciaGiroUnico(unico, testo: testo ?? "", errore: errore)
                    }
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
            idTurno = nil
            concludi(id: id, testo: "Sir, mi sono perso in troppi passaggi. Riformuli pure.", azioni: [])
        } catch is CancellationError {
            rimuoviSeVuoto(id)              // interrotto dal signore: niente da dire
        } catch let e as URLError where e.code == .cancelled {
            rimuoviSeVuoto(id)
        } catch {
            Suoni.errore()
            idTurno = nil
            concludiConErrore(id: id, Jarvis.spiegaErroreRete(error))
        }
    }

    /// Un errore arrivato quando una parte della risposta c'era già (e magari l'aveva già detta): quella parte resta in chat
    /// e JARVIS dice l'errore a voce. Prima la risposta a metà spariva sotto l'errore e JARVIS taceva di colpo (revisione del dialogo).
    private func concludiConErrore(id: UUID, _ msg: String) {
        let parziale = messaggi.first(where: { $0.id == id })?.testo.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !parziale.isEmpty else { concludi(id: id, testo: msg, azioni: []); return }
        testiGrezzi[id] = nil
        bufferVoce = ""                                   // la frase rimasta a metà non si dice: si passa all'errore
        if let i = messaggi.firstIndex(where: { $0.id == id }) { messaggi[i].testo = parziale + "\n\n" + msg }
        salva()
        stato = nil
        accodaVoce(msg, forza: true)
        flussoFinito = true
        compitoRete = nil
        if inCoda.isEmpty { fineParlato() }
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
    private func flussoConRitentativi(_ corpo: [String: Any], id: UUID, richiesta: String, unico: GiroUnicoMac? = nil) async throws -> Esito {
        var tentativo = 0
        while true {
            do {
                return try await flusso(corpo, id: id, richiesta: richiesta, unico: unico)
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
        testiGrezzi[id] = nil
        bufferVoce = ""
    }

    private func flusso(_ corpo: [String: Any], id: UUID, richiesta: String, unico: GiroUnicoMac? = nil, deposito: Anticipo? = nil) async throws -> Esito {
        guard let url = URL(string: Impostazioni.indirizzo) else { throw ErroreJarvis.indirizzo }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.setValue(richiesta, forHTTPHeaderField: "x-richiesta")
        req.httpBody = try JSONSerialization.data(withJSONObject: corpo)

        let (righe, resp) = try await URLSession.shared.bytes(for: req, delegate: unico?.presa)
        let codice = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let unico, !unico.gestito, codice != 200 { unico.presa.chiudi(); return .ripiega }   // idea D: la strada di prima
        if codice == 401 { return .errore("La parola d'ordine non coincide, Sir. La controlli nelle impostazioni.") }
        guard codice == 200 else { return .errore("Il mio cervello ha risposto con un errore (codice \(codice)).") }

        for try await riga in righe.lines {
            try Task.checkCancellation()        // interrotto: le righe già arrivate non vanno più lette né dette
            guard let dati = riga.data(using: .utf8),
                  let e = (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any],
                  let tipo = e["t"] as? String else { continue }
            switch tipo {
            case "testo":
                // 11 nov: una risposta anticipata non ancora adottata resta da parte (il signore potrebbe non aver finito)
                if let pezzo = e["d"] as? String {
                    if let d = deposito, !d.adottato { d.eventi.append(.testo(pezzo)); preparaVoce(d, finita: false) } else { aggiungi(pezzo, id: id) }
                }
            case "stato":
                if let d = deposito, !d.adottato { d.eventi.append(.stato(e["d"] as? String)) } else { stato = e["d"] as? String }
            case "immagini":
                if let d = deposito, !d.adottato { d.eventi.append(.immagini(e["d"])) } else { aggiungiImmagini(Immagine.daJSON(e["d"]), id: id) }
            case "sospeso":
                return .sospeso(e)
            case "no_anticipo":
                return .noAnticipo
            case "aspetto":
                return .aspetto                 // 12 nov (A1): il cervello dice che il signore non ha finito di parlare
            case "ponte":
                // 12 nov (B4): la frase d'attesa sulla richiesta (solo per la risposta vera, non per quella anticipata)
                if deposito == nil || deposito?.adottato == true, let f = e["d"] as? String, !f.isEmpty { ponteDelCervello = f }
            case "fine":
                if let d = deposito, let l = e["lavoro"] { d.lavoroFine = l }    // 11 nov: solo nella risposta anticipata
                if let d = deposito, !d.adottato { preparaVoce(d, finita: true) }
                return .fine(e["testo"] as? String ?? "", e["azioni"] as? [String] ?? [])
            case "client":
                return .client(e)
            case "errore":
                return .errore(e["d"] as? String ?? "Un intoppo tecnico, Sir.")
            case "doppione":
                return .doppione
            case "trascritto":
                // idea D: la frase detta, trascritta dal cervello dentro questa stessa richiesta
                guard let unico, !unico.gestito else { break }       // un nuovo tentativo dopo la linea caduta: già fatto
                unico.gestito = true
                let t = (e["d"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty, e["errore"] != nil { unico.presa.chiudi(); return .ripiega }
                guard accettaGiroUnico(unico, testo: t, id: id) else { unico.presa.chiudi(); return .lascia(t) }
                unico.libera()                                        // accettata: l'attesa del Mac va avanti
            default:
                break
            }
        }
        return .errore("La risposta si è interrotta a metà, Sir. Riprovi.")
    }

    /// Idea B (25 ott): la stessa frase l'ha sentita anche un altro dispositivo (iPhone e Mac, orologio e Mac) e risponde lui.
    /// Questo JARVIS tace e torna in attesa: la domanda e la risposta vuota spariscono da qui (le vede l'altro).
    private func concludiDoppione(id: UUID) {
        idTurno = nil
        compitoPonte?.cancel()
        compitoPonte = nil
        compitoRete = nil
        flussoFinito = true
        testiGrezzi[id] = nil
        if let i = messaggi.firstIndex(where: { $0.id == id }) {
            let domanda: Int? = i > 0 && messaggi[i - 1].ruolo == "user" ? i - 1 : nil
            messaggi.remove(at: i)
            if let d = domanda { messaggi.remove(at: d) }
        }
        salva()
        stato = nil
        if inCoda.isEmpty, fase != .ascolto { fase = .attesa }   // se stava dicendo il riempitivo, lo finisce e poi torna in attesa
    }

    // MARK: Idea D (25 ott): sul Mac la frase in un giro solo

    /// Prova della 27: il giro unico sul Mac è spento (vedi `partiGiroUnico`). Orologio e iPhone non cambiano.
    private static let giroUnicoMac = false

    /// Fa partire la frase del Mac come audio dentro la richiesta della risposta. Falso: non si può (cervello di prima, una
    /// foto in giro, Occhi o LiDAR aperti…) e si fa come prima, trascrizione e poi risposta.
    /// Prova della 27 sul Mac (25 ott): spento (`giroUnicoMac`). Quando l'app chiude la richiesta (eco, comando, «Jarvis» da solo,
    /// interruttore…) il cervello non se ne accorge in tempo e risponde lo stesso: un turno fantasma e, con la strada di prima, due
    /// risposte alla stessa frase. Sul Mac la frase torna a fare due giri: prima il testo e i controlli dell'app, poi la risposta.
    private func partiGiroUnico(_ audio: Data, origine: GiroUnicoMac.Origine, fine: Date, fatto: (() -> Void)?) -> Bool {
        guard Jarvis.giroUnicoMac else { return false }
        guard Jarvis.usaAscoltoCloud, UserDefaults.standard.bool(forKey: "giroUnicoCervello"), !micSpento,
              foto == nil, fotoGiro.isEmpty, allegato == nil, occhi == nil, !lidarAperto, !LidarAperta.aperta, !BrowserVoce.aperto,
              ConfidenteAperto.domanda == nil, audio.count > 1_000 else { return false }
        if case .stanza = origine { guard fase == .attesa else { return false } } else { guard fase == .elaboro else { return false } }
        // la foto vista poco fa tornerebbe nella cronologia (foto_storia): lì la strada di prima, che la sa rimettere al suo posto
        if idFotoRecente != nil, !fotoRecenti.isEmpty, Date().timeIntervalSince(quandoFotoRecenti) < 600 { return false }
        // la nota che `invia` metterebbe davanti a una frase normale detta adesso: la mette il cervello, uguale
        var m = Messaggio(ruolo: "user", testo: "")
        if let q = interruzioneValida() { m.interruzione = q }
        else if let u = messaggi.last(where: { $0.ruolo == "user" }), Date().timeIntervalSince(u.data) < (aggiuntaInArrivo ? 300 : 60) { m.seguito = true }
        // la cronologia che `invia` manderebbe, senza la domanda nuova (le ultime 19 più quella fanno le sue 20)
        let storia: [[String: Any]] = finestraCervello().map(Jarvis.perCervello)
        let giro = GiroUnicoMac(audio: audio, origine: origine, prefisso: m.testoPerCervello, fine: fine, fatto: fatto)
        let id = UUID()
        compitoRete?.cancel()
        compitoRete = Task { await self.turno(storia: storia, foto: nil, id: id, fineVoce: fine, unico: giro) }
        return true
    }

    /// La frase che è arrivata con «trascritto» è una domanda normale, con la stessa nota che il cervello le ha messo davanti?
    /// Allora si accoglie come farebbero `instrada` e `invia`, senza un'altra richiesta: la risposta sta già arrivando in questa.
    private func accettaGiroUnico(_ giro: GiroUnicoMac, testo: String, id: UUID) -> Bool {
        guard !testo.isEmpty, !micSpento, foto == nil, fotoGiro.isEmpty, allegato == nil else { return false }
        var frase = testo
        switch giro.origine {
        case .ascolto(let t):
            guard fase == .elaboro, !ascoltoCloud, turnoAscolto == t else { return false }
        case .stanza:
            // come `fraseSentitaMac` in attesa, senza fare niente: nessuna eco, folla, ordine di silenzio, interruttore, nome da solo
            guard fase == .attesa else { return false }
            if Date() > dettoMacFino { dettoMac = "" }
            guard Dialogo.togliEcoAiBordi(testo, detto: dettoMac) == testo, !Jarvis.eEco(testo, detto: dettoMac) else { return false }
            if AmbienteSonoro.condiviso.affollato {
                let basso = testo.lowercased()
                guard Richiamo.nomi.contains(where: { basso.contains($0) }) || Benvenuto.eFraseDiTony(testo) else { return false }
            }
            guard !Jarvis.eSoloSilenzio(testo) else { return false }
            let conNome = Richiamo.dopoRichiamo(testo) != nil
            let dopo = Richiamo.dopoRichiamo(testo) ?? testo
            if !Impostazioni.ascoltoSempre, !conNome, !Benvenuto.eFraseDiTony(testo) {
                guard Date() < liberoMacFinoA || Date() < richiamo.liberoFinoA else { return false }
            }
            guard !(conNome && dopo.isEmpty) else { return false }
            frase = dopo
        }
        // come `eseguiComando` (nessun comando dell'app) e `instrada` (domanda nuova, interrotta o seguito)
        guard !comandoLocale(frase), !frase.isEmpty, !Jarvis.eSoloSilenzio(frase) else { return false }
        let (pulito, chiede) = Jarvis.togliRichiamo(frase)
        guard !(chiede && pulito.isEmpty) else { return false }
        let detta = pulito.isEmpty ? frase : pulito
        let riprende = chiede || aggiuntaInArrivo
        var m = Messaggio(ruolo: "user", testo: "")
        let interrottoSu = interruzioneValida()
        if let q = interrottoSu { m.interruzione = q }
        else if let u = messaggi.last(where: { $0.ruolo == "user" }), Date().timeIntervalSince(u.data) < (riprende ? 300 : 60) { m.seguito = true }
        guard m.testoPerCervello == giro.prefisso else { return false }   // cambiata nel frattempo: la strada di prima
        // accolta: quello che fanno `fraseSentitaMac`, `instrada` e `invia`, tranne la richiesta (è già questa)
        if case .ascolto = giro.origine, stato == "Un attimo, Sir" { stato = nil }
        liberoMacFinoA = .distantPast
        avviso = nil
        parziale = ""
        fermaBenvenuto()
        compitoPonte?.cancel()
        rispostaInterrotta = nil
        quandoInterrotto = nil
        domandaInterrotta = nil
        aggiuntaInArrivo = false
        dopoAspetta = .no
        ultimaFraseAVoce = detta
        fraseAVoce = ""
        fineFraseVoce = nil
        m.testo = detta
        messaggi.append(m)
        messaggi.append(Messaggio(id: id, ruolo: "assistant", testo: ""))
        idTurno = id
        salva()
        ultimoInvio = Date()
        rispostaIniziata = false
        frasiVoce = []
        dettoRisposta = (id, "")
        richiamo.liberoFinoA = Date().addingTimeInterval(Dialogo.finestraAggiunta)
        richiamo.seguitoFinoA = .distantPast
        bufferVoce = ""
        fase = .elaboro
        flussoFinito = false
        if Date().timeIntervalSince(ultimoPonte) < 20 { compitoPonte?.cancel(); inizioTurno = Date() } else { armaPonte(id: id, testo: detta) }
        return true
    }

    /// Idea D: la frase sarebbe un comando dell'app (`eseguiComandoLocale`)? Lo stesso riconoscimento, senza eseguire niente.
    /// Nel dubbio vero: si fa come prima.
    private func comandoLocale(_ frase: String) -> Bool {
        if Dialogo.volume(frase).cambio != nil || Benvenuto.eFraseDiTony(frase) { return true }
        if ComandoDedicato.riconosci(frase) != nil || ComandoOcchi.riconosci(frase) != nil || Storpiature.cerca(frase) != nil { return true }
        if BrowserVoce.aperto || LidarAperta.aperta || lidarAperto { return true }
        let dentro: Reparto? = occhi != nil ? .occhi : (lidarAperto ? .lidar : sezioneAperta)
        return ComandoVocale.riconosci(frase, dentro: dentro) != nil
    }

    /// Idea D: la frase del giro unico si fa come prima, con il testo già trascritto (la richiesta è già chiusa).
    private func lasciaGiroUnico(_ giro: GiroUnicoMac, testo grezzo: String, errore: String?) async {
        let testo = grezzo.trimmingCharacters(in: .whitespacesAndNewlines)
        switch giro.origine {
        case .ascolto(let t):
            // come `chiudiAscoltoCloud` dopo la trascrizione
            guard fase == .elaboro, !ascoltoCloud, turnoAscolto == t else { return }   // interrotto nel frattempo
            if stato == "Un attimo, Sir" { stato = nil }
            fase = .attesa
            fineFraseVoce = giro.fine
            guard !testo.isEmpty else { avviso = errore ?? "Non ho capito, Sir. Riprovi."; return }
            if foto == nil, eseguiComando(testo) { return }
            if foto == nil { await instrada(testo) } else { await invia(testo) }
        case .stanza(let inizio):
            // come l'attesa del Mac dopo la trascrizione
            guard attesaMac.inAscolto, !testo.isEmpty else { return }
            fraseSentitaMac(testo, inizio: inizio, fine: giro.fine)
        }
    }

    /// Nella chat, la domanda che ha fatto aprire gli occhi prende l'icona 📷.
    private func segnaFoto(id: UUID) {
        guard let i = messaggi.firstIndex(where: { $0.id == id }), i > 0, messaggi[i - 1].ruolo == "user" else { return }
        messaggi[i - 1].conFoto = true
        salva()
    }

    private func rimuoviSeVuoto(_ id: UUID) {
        if let i = messaggi.firstIndex(where: { $0.id == id }), messaggi[i].testo.isEmpty { messaggi.remove(at: i) }
        testiGrezzi[id] = nil
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
        if let i = messaggi.firstIndex(where: { $0.id == id }) {
            let grezzo = (testiGrezzi[id] ?? messaggi[i].testo) + pezzo
            testiGrezzi[id] = grezzo
            messaggi[i].testo = TagVoce.togli(grezzo, inCorso: true)     // in chat senza i toni della voce
        }
        stato = nil
        accodaVoce(pezzo, di: id)                                         // la voce li riceve tutti
    }

    private func concludi(id: UUID, testo: String, azioni: [String]) {
        let giaDetto = testiGrezzi[id] ?? messaggi.first(where: { $0.id == id })?.testo ?? ""
        testiGrezzi[id] = nil
        if let i = messaggi.firstIndex(where: { $0.id == id }) {
            messaggi[i].testo = TagVoce.togli(testo)                      // chat e cronologia senza i toni della voce
            messaggi[i].azioni = azioni
        }
        salva()
        stato = nil
        // se il testo finale non è stato letto in streaming (es. un errore), lo leggo ora
        let diRisposta: UUID? = idTurno == id ? id : nil       // un errore non è la risposta: non conta come «detto»
        if giaDetto.isEmpty { accodaVoce(testo, di: diRisposta) }
        accodaVoce("", forza: true, di: diRisposta)
        flussoFinito = true
        compitoRete = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if inCoda.isEmpty { fineParlato() }
    }

    // MARK: Voce in streaming: legge frase per frase mentre il resto arriva

    /// `di`: la risposta a cui appartiene il testo (per sapere cosa il signore ha sentito davvero se la interrompe).
    private func accodaVoce(_ pezzo: String, forza: Bool = false, di risposta: UUID? = nil) {
        bufferVoce += pezzo
        guard !Impostazioni.muto else { bufferVoce = ""; return }
        if forza {
            let resto = bufferVoce.trimmingCharacters(in: .whitespacesAndNewlines)
            bufferVoce = ""
            if !resto.isEmpty { dici(resto, di: risposta) }
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
        if !frase.isEmpty { dici(frase, di: risposta) }
    }

    private func dici(_ frase: String, di risposta: UUID? = nil) {
        guard fase != .ascolto else { return }   // mai prendersi l'audio mentre il signore parla
        // sul Mac niente orecchio mentre parla: è un secondo microfono (con il riconoscimento di Apple) che lascia muto quello
        // dell'attesa; lì per fermarlo basta toccare il reattore
        let conOrecchio = Impostazioni.interruzioneVocale && !Impostazioni.muto && !Jarvis.usaAscoltoCloud && !musicaSuona   // 9 nov: la canzone lo interromperebbe
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
        // i toni («[whispers]») li sa dire solo la voce di JARVIS dal cloud: la voce dell'iPhone li salta
        let detta = vocePerCloud ? frase : TagVoce.togli(frase)
        if detta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        let u = AVSpeechUtterance(string: detta)
        u.voice = Jarvis.voceScelta()
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        u.volume = Jarvis.volumeVoce                   // «sbatti»: sottovoce
        let chiave = ObjectIdentifier(u)
        inCoda.insert(chiave)
        frasiVive[chiave] = u
        if let risposta { frasiRisposta[chiave] = (risposta, frase) }
        fase = .parlo
        orecchio.testoDetto += " " + frase          // così l'orecchio riconosce la propria eco
        if Jarvis.usaAscoltoCloud { dettoMac += " " + frase; dettoMacFino = Date().addingTimeInterval(30) }
        orecchio.soloParoleDOrdine = riservato         // 12 nov: in RISERVATO solo «Jarvis», «basta», «aspetta»… lo fermano
        if conOrecchio, !micSpento, !orecchio.attivo { orecchio.avvia() }   // microfono spento a mano: non ascolta nemmeno mentre parla
        if vocePerCloud {
            // solo le frasi della risposta portano il loro «prima» (le ultime due, fino a 300 caratteri); frasi ponte e annunci no
            var prima: String?
            if risposta != nil {
                let p = frasiVoce.suffix(2).joined(separator: " ")
                if !p.isEmpty { prima = String(p.suffix(300)) }
                frasiVoce.append(detta)
            }
            cloud.accoda(u, prima: prima)   // voce di JARVIS dal cloud; se fallisce, legge questa stessa frase con la voce dell'iPhone
        } else {
            sintesi.speak(u)
        }
    }

    /// Per «Prova la voce» nelle impostazioni.
    func parla(_ testo: String) async {
        interrompi()
        accodaVoce(testo, forza: true)
    }

    /// `detta`: la frase è arrivata fino in fondo (falso: fermata a metà).
    fileprivate func fraseFinita(_ chiave: ObjectIdentifier, detta: Bool) {
        frasiVive[chiave] = nil
        let diRisposta = frasiRisposta.removeValue(forKey: chiave)
        guard inCoda.remove(chiave) != nil else { return }   // frase di un discorso già interrotto
        // H2: il signore l'ha sentita tutta; se poi interrompe, il cervello sa che questa c'era
        if detta, let r = diRisposta {
            if let d = dettoRisposta, d.id == r.id { dettoRisposta = (d.id, d.testo + " " + r.frase) } else { dettoRisposta = (r.id, r.frase) }
        }
        guard inCoda.isEmpty else { return }
        if flussoFinito { fineParlato() } else if fase == .parlo { fase = .elaboro }   // detto tutto, il resto è in arrivo
    }

    private func fineParlato() {
        let eraRisposta = flussoFinito && idTurno != nil   // la risposta a una domanda (non un annuncio, una notifica, un errore)
        if flussoFinito { idTurno = nil }        // risposta detta tutta: da qui in poi una frase nuova è una domanda nuova
        orecchio.ferma()
        orecchio.testoDetto = ""
        guard fase != .ascolto else { return }   // il signore l'ha interrotto e sta già parlando
        // M6: finita la risposta, per qualche secondo il seguito vale anche senza «Jarvis» («Perché?», «E domani?»)
        if eraRisposta { richiamo.seguitoFinoA = Date().addingTimeInterval(Dialogo.finestraSeguito) }
        fase = .attesa
        // 11 nov (#16): fuori dall'app il dialogo resta aperto per il seguito; se per 8 secondi non dice nulla, è finito
        if dialogoFuori { chiudiDialogoFuori(fra: 8) }
        let pronto = !Impostazioni.richiamo
        if pronto { Suoni.pronto() }                // col richiamo a voce si chiude come una persona: in silenzio
        Task { @MainActor [weak self] in
            // il segnale di fine deve finire prima di restituire l'audio alle altre app; senza segnale (M6) si restituisce
            // subito, prima che il «Jarvis» in attesa riparta (150 ms): così la musica torna al suo volume e il microfono è pronto
            if pronto { try? await Task.sleep(for: .milliseconds(400)) }
            if self?.musicaSuona == true { try? await Task.sleep(for: .milliseconds(1500)) }   // 9 nov: la musica risale dopo 1,5 s
            // i Clash non si spengono; sul Mac il microfono dell'attesa sta già ripartendo: l'audio resta acceso;
            // se il «Jarvis» in attesa è già ripartito l'audio è suo (spegnerlo qui gli fermerebbe il microfono)
            guard let self, self.fase == .attesa, self.inCoda.isEmpty, !self.inBenvenuto, !Jarvis.usaAscoltoCloud,
                  !self.richiamo.attivo, !AscoltoShazam.condiviso.suonaDentro else { return }   // 9 nov: né la canzone di Shazam
            if self.musicaSuona { await self.rilasciaMusica() } else if !LettoreMusica.condiviso.suona {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
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
            // i comandi a frase esatta della build 22 non si imparano mai come storpiature
            if !ultimaFraseAVoce.isEmpty, ComandoDedicato.riconosci(ultimaFraseAVoce) == nil, ComandoOcchi.riconosci(ultimaFraseAVoce) == nil { Storpiature.impara(ultimaFraseAVoce, comando: c) }
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
    /// `silenzio`: quanto aspettare che cominci a parlare (dopo «aspetta» meno: la pausa di fine frase è già passata).
    /// Nil: il solito (5 secondi sull'iPhone, 7 sul Mac, dove la frase si registra e si trascrive in cloud).
    private func avviaAscolto(bip: Bool = false, tentativo: Int = 0, dalNome: Bool = false, silenzio: Double? = nil) async {
        avviso = nil
        guard fase == .attesa, !micSpento else { return }      // microfono spento a mano: nessun ascolto finché non ritocca
        guard await Jarvis.chiediPermessi() else {
            avviso = "Servono microfono e riconoscimento vocale: li attivi in Impostazioni › Jarvis."
            return
        }
        guard fase == .attesa else { return }   // nel frattempo è partito un altro ascolto (doppio tocco)
        Posizione.scalda()                      // difetto 5: il GPS si sveglia mentre il signore parla, la domanda non lo aspetta
        avvioRichiamo?.cancel()
        richiamo.ferma()                        // il microfono passa all'ascolto normale
        if Jarvis.usaAscoltoCloud {
            attesaMac.ferma()
            liberoMacFinoA = .distantPast
            // chiamato per nome: gli ultimi 3 secondi già sentiti (dentro c'è «Jarvis» e l'inizio della domanda), presi solo adesso
            // che il richiamo è spento, così non si perde niente di ciò che ha detto nel frattempo
            avviaAscoltoCloud(bip: bip, precarica: dalNome ? RegistroMicrofono.condiviso.ultimi(3) : [], attesa: silenzio)
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

            let r = Jarvis.nuovaRichiestaAscolto()
            richiesta = r
            // iPhone: un motore nuovo, creato ora che l'audio permette il microfono (come nel richiamo); sul Mac resta quello dell'attesa
            if !Jarvis.usaAscoltoCloud && !motore.isRunning { motore = AVAudioEngine() }
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
            riavviiAscolto = 0
            anticipiTurno = 0
            scartaAnticipo()
            generazioneRic += 1
            let g = generazioneRic
            pausaMinimaAscolto = 0                     // 12 nov (A1)
            inizioParlato = nil                        // 12 nov (A3)
            voceCome = nil
            ascoltoLungo = ascoltoLungoProssimo        // «ascoltami» detto da solo: l'ascolto che parte adesso è quello lungo
            ascoltoLungoProssimo = false
            ultimaParolaAscolto = Date()
            VoceAttiva.condivisa.azzera()
            compito = Jarvis.avviaRiconoscimento(riconoscitore, r) { [weak self] testo, finale, errore in
                Task { @MainActor [weak self] in self?.aggiorna(testo: testo, finale: finale, errore: errore, ascolto: mio, generazione: g) }
            }
            armaSilenzio(secondi: silenzio ?? 5)   // tempo per iniziare a parlare
            // 9 nov sera: con la musica (anche abbassata) il riconoscimento sente le parole della canzone e il silenzio non arriva
            // mai: la musica restava bassa a lungo. Con la musica l'ascolto dura al massimo 10 secondi, poi manda quello che ha.
            if musicaSuona {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    guard let self, self.turnoAscolto == mio, self.fase == .ascolto else { return }
                    self.motivoChiusura = "musica"
                    self.fermaAscolto(invia: !self.parziale.isEmpty)
                }
            }
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
    /// Restituisce vero se era soltanto l'eco della voce di JARVIS (difetto 2: non conta nel tetto delle trascrizioni).
    @discardableResult
    private func fraseSentitaMac(_ sentito: String, inizio: Date, fine: Date = Date()) -> Bool {
        guard fase == .attesa || fase == .elaboro || fase == .parlo else { return false }
        fineFraseVoce = fine                                               // idea B: quando il signore ha smesso di parlare
        if Date() > dettoMacFino { dettoMac = "" }
        // difetto 2 (controllo del 25 ott), come sull'orologio: il pezzo di audio contiene anche la voce di JARVIS, prima e dopo
        // le parole del signore. Si tolgono le sue parole in testa e in coda e resta solo il signore: «basta», «muto», «aspetta»
        // detti sopra di lui non finiscono più buttati come eco, e una domanda detta sopra non arriva mescolata alle sue parole
        // prova della 27: una sua frase ripresa parola per parola è eco anche con dentro «basta» o «aspetta» (prima lo fermava e
        // diventava una domanda: JARVIS rispondeva a se stesso); anche una sua frase rimasta in mezzo (almeno quattro parole) si toglie
        if Dialogo.eFraseDiJarvis(sentito, detto: dettoMac) { return true }
        let testo = Dialogo.togliEcoDentro(Dialogo.togliEcoAiBordi(sentito, detto: dettoMac), detto: dettoMac)
        if testo.isEmpty { return true }                                   // era tutta la sua voce
        if testo == sentito {
            // nessun pezzo della sua voce ai bordi: come prima, quasi tutte parole sue = eco. Mai però con una sua parola d'ordine
            if Jarvis.eEco(testo, detto: dettoMac), !Jarvis.haParolaDOrdine(testo) { return true }
        } else if Jarvis.eResiduoDiEco(testo, detto: dettoMac) {
            return true                                                    // un pezzetto della sua voce rimasto in mezzo («Sir»)
        }
        // musica, TV o gente intorno: vale solo una frase col suo nome (o la frase di Tony); il resto della stanza non è per lui
        if AmbienteSonoro.condiviso.affollato {
            let basso = testo.lowercased()
            guard Richiamo.nomi.contains(where: { basso.contains($0) }) || Benvenuto.eFraseDiTony(testo) else { return false }
        }
        // «Jarvis…», ma anche «ehi», «senti», «ascolta», «bro»: si toglie il richiamo e resta il resto
        let conNome = Richiamo.dopoRichiamo(testo) != nil
        let dopo = Richiamo.dopoRichiamo(testo) ?? testo
        // «Jarvis, muto», «basta», «stop»: tace e resta in attesa. Prova della 27: vale anche se prima di «Jarvis» c'è altro
        // («…no no, Jarvis muto»), perché sul Mac il pezzo contiene spesso anche la voce di JARVIS
        if Jarvis.eSoloSilenzio(testo) || (conNome && Jarvis.eSoloSilenzio(dopo)) {
            if fase != .attesa { mettiInAttesa() }
            return false
        }
        if fase == .parlo {                                                // gli parla sopra: tace subito e ascolta, come sull'iPhone
            // come l'orecchio dell'iPhone: sopra la sua voce serve una parola d'ordine o almeno due parole. Una parola sola
            // (la sua voce o un rumore capiti male dalla trascrizione) non lo ferma
            let quante = testo.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
            guard quante >= 2 || conNome || Jarvis.haParolaDOrdine(testo) else { return false }
            interrottoAVoce(testo)
            return false
        }
        // difetto 7 (controllo del 25 ott): l'interruttore «Risponde a qualsiasi frase» vale anche sul Mac, come sull'iPhone.
        // Spento: in attesa e mentre pensa serve «Jarvis» (o «ehi», «bro»…) o la frase di Tony, tranne nel seguito subito dopo una
        // risposta (8 secondi) e nei 2 secondi dell'aggiunta dopo la domanda. Acceso (di partenza): come prima, qualsiasi frase
        if !Impostazioni.ascoltoSempre, !conNome, !Benvenuto.eFraseDiTony(testo) {
            let adesso = Date()
            guard adesso < liberoMacFinoA || adesso < richiamo.liberoFinoA else { return false }
        }
        liberoMacFinoA = .distantPast
        if fase == .elaboro { segnaInterruzione(); interrompi() }   // stava pensando: lo fermo, come sull'iPhone
        avviso = nil
        parziale = ""
        if conNome && dopo.isEmpty { Task { await avviaAscolto(bip: true) }; return false }   // solo «Jarvis»: apro il microfono
        // «piano»/«voce normale» per primo: cambia solo il volume, non è né il rito né una domanda
        let senzaSottovoce = sottovoce(dopo)
        if senzaSottovoce.isEmpty { return false }                        // solo «piano» o «voce normale»: fatto, niente rito
        if Benvenuto.eFraseDiTony(senzaSottovoce) { fraseDiTony(); return false }
        if foto == nil, eseguiComando(senzaSottovoce) { return false }
        Task { await instrada(senzaSottovoce) }
        return false
    }

    /// C'è una parola con cui il signore ferma o chiama JARVIS («basta», «muto», «aspetta», «Jarvis»…): mai eco (difetto 2).
    nonisolated static func haParolaDOrdine(_ frase: String) -> Bool {
        let parole = frase.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        let ordini: Set<String> = ["muto", "muta", "zitto", "zitta", "basta", "stop", "fermati", "fermo", "silenzio", "taci",
                                   "aspetta", "aspetti", "ascoltami"]
        return parole.contains { p in ordini.contains(p) || Richiamo.nomi.contains(where: { p.hasPrefix($0) }) }
    }

    /// Difetto 2: tolta l'eco ai bordi resta una o due parole che JARVIS ha appena detto (non un suo ordine): è eco anche quello.
    nonisolated static func eResiduoDiEco(_ resto: String, detto: String) -> Bool {
        func parole(_ t: String) -> [String] {
            t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        }
        let r = parole(resto), d = Set(parole(detto))
        guard !r.isEmpty, r.count <= 2, !haParolaDOrdine(resto) else { return false }
        return r.allSatisfy { d.contains($0) }
    }

    /// Registra la frase; quando il signore ha finito (o tocca il reattore) la trascrive in cloud e la manda come sull'iPhone.
    /// `attesa`: quanto aspettare che cominci a parlare (nil: i soliti 7 secondi; dopo «aspetta» meno).
    private func avviaAscoltoCloud(bip: Bool, precarica: [Float], attesa: Double? = nil) {
        do {
            let sessione = AVAudioSession.sharedInstance()
            do {
                // mixWithOthers: la musica e le altre app restano al loro volume mentre JARVIS ascolta
                try sessione.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            } catch {
                try sessione.setCategory(.playAndRecord, options: [.mixWithOthers])
            }
            try sessione.setActive(true, options: .notifyOthersOnDeactivation)
            registratore.azzera(attesa: attesa ?? 7)
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
            if dopoAspetta == .aspetta { miDica() } else { aggiuntaInArrivo = false; dopoAspetta = .no }   // come sull'iPhone
            return
        }
        let registratore = self.registratore
        let fineVoce = Date().addingTimeInterval(-0.9)   // idea B: il registratore chiude dopo 0,9 s di silenzio
        stato = "Un attimo, Sir"
        fase = .elaboro
        Task { [weak self] in
            let audio = await Task.detached { registratore.wav() }.value      // il file si prepara fuori dal thread principale
            // idea D: la frase va al cervello insieme alla richiesta della risposta (un giro solo), se il cervello lo sa fare
            if let me = self, me.fase == .elaboro, !me.ascoltoCloud, me.turnoAscolto == turno,
               me.partiGiroUnico(audio, origine: .ascolto(turno: turno), fine: fineVoce, fatto: nil) { return }
            let (testo, errore) = await RegistratoreVoce.trascrivi(audio, token: Portachiavi.leggi(), indirizzo: Impostazioni.indirizzo)
            guard let self, self.fase == .elaboro, !self.ascoltoCloud, self.turnoAscolto == turno else { return }   // interrotto nel frattempo
            if self.stato == "Un attimo, Sir" { self.stato = nil }
            self.fase = .attesa
            self.fineFraseVoce = fineVoce
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

    private func aggiorna(testo: String?, finale: Bool, errore: Bool, ascolto: Int, generazione: Int) {
        guard fase == .ascolto, ascolto == turnoAscolto, generazione == generazioneRic else { return }
        if let testo, !testo.isEmpty {
            let adesso = Date()
            if testo != precedenteAscolto { ultimaParolaAscolto = adesso }
            if Richiamo.pezzoNuovo(precedente: precedenteAscolto, nuovo: testo, pausa: adesso.timeIntervalSince(ultimoParzialeAscolto)) {
                baseAscolto = parziale                 // il riconoscimento è ripartito da capo: non perdo l'inizio della frase
            }
            precedenteAscolto = testo
            ultimoParzialeAscolto = adesso
            parziale = [baseAscolto, testo].filter { !$0.isEmpty }.joined(separator: " ")
            if inizioParlato == nil { inizioParlato = adesso }                    // 12 nov (A3)
            // 12 nov (A1): la pausa lunga chiesta dalla risposta anticipata vale finché la frase è quella; parole nuove, si riparte
            if pausaMinimaAscolto > 0, Jarvis.normaAnticipo(Jarvis.fraseAnticipabile(parziale)) != aspettoSu { pausaMinimaAscolto = 0 }
            // 11 nov: «ascoltami», «fammi finire» dentro la frase: da qui aspetta come vuole il signore (3,5 s, fino a 90 s)
            if !ascoltoLungo, Jarvis.chiedeAscoltoLungo(parziale) { ascoltoLungo = true; timerTetto?.invalidate(); timerTetto = nil }
            armaSilenzio(secondi: pausaAscolto(parziale))
            programmaAnticipo(parziale)                // 11 nov: la risposta si prepara durante la pausa
            if timerTetto == nil {                     // il signore ha iniziato a parlare: può andare avanti fino a un minuto (90 s con «ascoltami»)
                let mio = turnoAscolto
                timerTetto = Timer.scheduledTimer(withTimeInterval: ascoltoLungo ? 90 : 60, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.turnoAscolto == mio else { return }
                        self.motivoChiusura = "tetto"
                        self.fermaAscolto(invia: true)
                    }
                }
            }
        }
        if finale || errore {
            // 11 nov (il signore: «dico tre parole e già risponde»): il riconoscimento di Apple chiude un pezzo («finito» o errore)
            // anche quando il signore sta solo pensando. Con delle parole già sentite si riparte senza chiudere, come fa già il
            // richiamo dopo «Jarvis»: la frase la chiude solo il silenzio vero (parole E voce).
            if !parziale.isEmpty, riavviiAscolto < 6, riavviaRiconoscimento(ascolto: ascolto) { return }
            motivoChiusura = errore ? "errore" : "finale"
            fermaAscolto(invia: true)
        }
    }

    /// 11 nov: la richiesta del riconoscimento dell'ascolto (la stessa all'avvio e quando riparte senza chiudere).
    nonisolated private static func nuovaRichiestaAscolto() -> SFSpeechAudioBufferRecognitionRequest {
        let r = SFSpeechAudioBufferRecognitionRequest()
        r.shouldReportPartialResults = true
        r.addsPunctuation = true                 // il «?» aiuta a capire quando la domanda è finita
        // 12 nov (A4): anche i nomi delle sue persone e dei suoi progetti, imparati dal cervello (arrivano con la sveglia)
        let imparate = UserDefaults.standard.stringArray(forKey: "paroleRiconoscimento") ?? []
        r.contextualStrings = Array((["Discosizer", "Jarvis", "Discogs", "Resident Advisor", "SumUp", "EDITH", "mi ricevi"] + imparate).prefix(100))
        return r
    }

    /// 11 nov: il riconoscimento ha chiuso il suo pezzo ma il signore non ha finito: si tiene quanto detto e si riapre, con il
    /// microfono che non si ferma mai (cambia solo il trascrittore). Falso: non si può, e la frase si manda come prima.
    private func riavviaRiconoscimento(ascolto mio: Int) -> Bool {
        guard fase == .ascolto, mio == turnoAscolto, !Jarvis.usaAscoltoCloud, motore.isRunning,
              let riconoscitore, riconoscitore.isAvailable else { return false }
        riavviiAscolto += 1
        generazioneRic += 1
        let g = generazioneRic
        richiesta?.endAudio()
        compito?.cancel()
        let r = Jarvis.nuovaRichiestaAscolto()
        do { try Jarvis.collegaMicrofono(motore.inputNode, a: r) } catch { return false }
        richiesta = r
        baseAscolto = parziale
        precedenteAscolto = ""
        compito = Jarvis.avviaRiconoscimento(riconoscitore, r) { [weak self] testo, finale, errore in
            Task { @MainActor [weak self] in self?.aggiorna(testo: testo, finale: finale, errore: errore, ascolto: mio, generazione: g) }
        }
        armaSilenzio(secondi: pausaAscolto(parziale))
        return true
    }

    /// 11 nov: la pausa di fine frase di questo ascolto: quella della frase, almeno 3,5 s con «ascoltami», e un po' più lunga
    /// se il signore di recente riprendeva spesso a parlare subito dopo l'invio (il suo ritmo, imparato da `RitmoSignore`).
    private func pausaAscolto(_ testo: String) -> Double {
        var base = Jarvis.pausaFineFrase(testo) * RitmoSignore.condiviso.fattore
        // 12 nov (A2): chi ripete parole o dice «ehm», «cioè», «tipo» sta cercando le parole: un po' più di pazienza
        if base >= 1, ComeParla.esitazioni(testo) >= 2 { base = min(2.6, base * 1.3) }
        return max(ascoltoLungo ? max(base, 3.5) : base, pausaMinimaAscolto)
    }

    /// 11 nov: il signore chiede di essere lasciato finire («ascoltami», «fammi finire», «lasciami parlare»…).
    nonisolated static func chiedeAscoltoLungo(_ testo: String) -> Bool {
        let t = " " + testo.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "it_IT")).lowercased()
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        return [" ascoltami ", " fammi finire ", " lasciami finire ", " fammi parlare ", " lasciami parlare ", " non interrompermi ",
                " aspetta che finisco ", " ascoltami bene "].contains { t.contains($0) }
    }

    /// Quanto silenzio aspettare prima di considerare finita la frase, come farebbe una persona che ascolta:
    /// non conta solo il silenzio ma cosa è stato detto.
    /// - «che tempo fa oggi?», «sì», «apri la Sentinella»: la frase è chiusa, si risponde quasi subito;
    /// - «oggi ero a Bari…», «allora, ti racconto…»: è un racconto, chi parla di solito continua; si aspetta di più;
    /// - «…e», «…perché», «…ehm»: si è fermato a metà, sta pensando; si aspetta ancora di più.
    /// Revisione del dialogo (24 ott): stessa tabella di tempi, ma nell'ordine giusto. Prima il «?» veniva dopo la frase
    /// sospesa, e «Che ore sono?», «Chi è?», «Perché?» aspettavano 2,4 s («sono», «è», «perché» sembravano parole a metà);
    /// «No, aspetta», «Ok senti» erano prese per risposte brevi e tagliate a 0,6 s. Prova: rev_dialogo/pausa_v2.py.
    nonisolated static func pausaFineFrase(_ testo: String) -> Double {
        let basso = testo.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "’", with: "'").lowercased()
        var parole = basso.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        // il nome o un richiamo davanti non fa parte della frase («Jarvis, apri il meteo» è un comando come «apri il meteo»)
        while let p = parole.first, ["ehi", "hey", "ei"].contains(p) || Richiamo.nomi.contains(where: { p.hasPrefix($0) }) {
            parole.removeFirst()
        }
        guard let ultima = parole.last, let prima = parole.first else { return 1.2 }
        let frase = parole.joined(separator: " ")

        // domanda chiusa: il punto di domanda del riconoscimento («Che ore sono?», «Chi è?», «Perché?», «E sabato?»)
        if basso.hasSuffix("?") { return 0.7 }

        // 12 nov (A2): l'ultima parola ripetuta («ci sono ancora delle delle», «che che»): sta cercando la parola, aspetta
        if parole.count >= 2, parole[parole.count - 1] == parole[parole.count - 2] { return 2.4 }

        // risposte brevi, anche di due o tre parole: «sì», «no grazie», «va bene», «sì, mandala pure»
        let brevi: Set<String> = ["sì", "si", "no", "ok", "okay", "certo", "esatto", "grazie", "mille", "perfetto", "va", "bene", "giusto",
                                  "bravo", "basta", "stop", "ferma", "avanti", "pausa", "dai", "fatto", "procedi", "vai", "confermo",
                                  "pure", "sir", "mandala", "mandalo", "mandale", "mandali", "inviala", "invialo", "fallo", "falla"]
        if parole.count <= 3 && parole.allSatisfy({ brevi.contains($0) }) { return 0.6 }

        // domanda breve senza «?» che finisce col verbo («che ore sono», «chi è», «che impegni ho»): è chiusa, non sospesa
        let interrogative: Set<String> = ["che", "cosa", "cos'è", "quanto", "quanti", "quanta", "quante", "chi", "dove", "qual", "quale",
                                          "quali", "c'è", "com'è", "dov'è"]
        let verbiFinali: Set<String> = ["sono", "è", "ho", "hai", "sei", "siamo", "c'è"]
        if interrogative.contains(prima), verbiFinali.contains(ultima), parole.count >= 2, parole.count <= 6, !basso.contains("?") { return 1.2 }

        // si è fermato a metà o sta pensando ad alta voce («…e», «…perché», «no, aspetta», «fammi pensare»)
        let sospese: Set<String> = ["e", "ed", "o", "ma", "che", "perché", "poi", "di", "del", "della", "dei", "delle", "a", "al",
                                    "alla", "ai", "da", "dal", "dalla", "in", "nel", "nella", "con", "per", "su", "sul", "tra", "fra",
                                    "il", "lo", "la", "i", "gli", "le", "un", "una", "uno", "mi", "ti", "ci", "si", "se", "quando",
                                    "dove", "come", "anche", "quindi", "cioè", "tipo", "ehm", "eh", "mmm", "allora", "praticamente",
                                    "comunque", "però", "mentre", "oppure", "magari", "sono", "è", "ho", "hai", "abbiamo", "volevo",
                                    "vorrei", "devo", "dobbiamo", "questo", "questa", "quel", "quella", "mio", "mia", "tuo", "tua"]
        // «aspetta», «senti», «guarda» in fondo: sta per dire la cosa vera (non «mi senti», «lo guarda»)
        let segnali: Set<String> = ["aspetta", "senti", "ascolta", "guarda", "scusa"]
        let cliticoPrima = parole.count >= 2 && ["mi", "ci", "lo", "la", "li", "le", "ti"].contains(parole[parole.count - 2])
        if sospese.contains(ultima) || (segnali.contains(ultima) && !cliticoPrima)
            || ["fammi pensare", "fammi capire", "fammi dire"].contains(frase) { return 2.4 }
        if basso.hasSuffix(",") || basso.hasSuffix("…") || basso.hasSuffix("...") { return 2.0 }

        // domanda chiusa senza «?»: solo le interrogative vere («che tempo fa domani»). «Come», «quando», «mi», «hai»…
        // senza «?» aprono spesso un racconto («Quando ero piccolo…», «Mi sono svegliato tardi…»): lì l'attesa è normale
        if interrogative.contains(prima), parole.count >= 2, parole.count <= 10 { return 0.8 }

        // comandi: «apri…», «metti…», «chiama…», «guarda là in fondo» (ma «Guarda, oggi…» è un racconto)
        let comandi: Set<String> = ["apri", "chiudi", "metti", "chiama", "manda", "scrivi", "accendi", "spegni", "ferma", "avvia",
                                    "leggi", "cerca", "dimmi", "fammi", "ricordami", "imposta", "alza", "abbassa", "guarda",
                                    "scansiona", "traduci", "attiva", "disattiva", "riproduci", "salta", "segna", "aggiungi",
                                    "togli", "cancella", "mostrami", "trova", "calcola", "prenota", "fai"]
        let guardaRacconto = prima == "guarda" && (parole.count > 5 || basso.contains("guarda,"))
        if comandi.contains(prima), parole.count <= 10, !guardaRacconto { return 0.9 }

        // racconto: chi parla sta esponendo un pensiero, di solito continua
        let racconto = ["oggi", "ieri", "stamattina", "stasera", "allora", "ascolta", "senti", "praticamente", "sai", "comunque",
                        "quindi", "ti volevo", "volevo", "ti racconto", "ti devo", "devo dirti", "pensavo", "secondo me", "io", "noi",
                        "l'altro giorno", "prima", "aspetta", "scusa"]
        if guardaRacconto || racconto.contains(where: { frase == $0 || frase.hasPrefix($0 + " ") }) { return 1.8 }
        if parole.count >= 15 { return 1.6 }                    // discorso lungo: pause di pensiero più probabili
        return 1.2
    }

    private func armaSilenzio(secondi: Double) {
        timerSilenzio?.invalidate()
        let mio = turnoAscolto
        timerSilenzio = Timer.scheduledTimer(withTimeInterval: secondi, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.turnoAscolto == mio, self.fase == .ascolto else { return }
                // 11 nov (analisi del dialogo): il silenzio si decideva solo dalle parole trascritte. In una sessione lunga il
                // riconoscimento le consegna a scatti e una pausa finta chiudeva la frase. Ora conta anche il suono: se il microfono
                // sente ancora la voce del signore, si aspetta ancora (ma senza parole nuove da 6 s è solo rumore: si chiude)
                let quieto = VoceAttiva.condivisa.secondiDiSilenzio
                let senzaParole = Date().timeIntervalSince(self.ultimaParolaAscolto)
                if quieto + 0.05 < secondi, senzaParole < 6 {
                    self.armaSilenzio(secondi: max(0.25, secondi - quieto))
                    return
                }
                self.motivoChiusura = "silenzio"
                self.fermaAscolto(invia: true)
            }
        }
    }

    /// `toccato`: il signore ha toccato il reattore per chiudere (non è il silenzio a chiudere l'ascolto).
    /// 25 ott (deciso dal signore): l'app va in sottofondo. Quello che stava sentendo si butta, non va al cervello, e le frasi
    /// lasciate a metà non si legano più a niente: tornando nell'app JARVIS riparte pulito e non risponde a frasi vecchie
    /// (prima, per esempio, rispondeva a quello che dicevano gli amici mentre lui scansionava con LiDAR).
    func vaInSottofondo() {
        // 11 nov (#16, il signore: «se esco da JARVIS mentre parla non lo sento… vorrei che continuasse a parlare e ad ascoltare, e
        // appena capisce che il dialogo è finito richiuda il microfono»): con un dialogo in corso (JARVIS parla, pensa, lo ascolta,
        // o ha appena risposto) il dialogo continua fuori dall'app. Finito il dialogo, `chiudiDialogoFuori` spegne il microfono.
        // Senza dialogo in corso resta la regola del 25 ott: quello che stava sentendo si butta.
        if dialogoPuoContinuareFuori {
            dialogoFuori = true
            chiudiDialogoFuori(fra: 8)       // finché il dialogo è vivo si riguarda ogni 8 s; finita la risposta riparte da capo
            return
        }
        // 9 nov sera (il signore: «come Apple Music»): in background (Home, altra app, schermo bloccato) la musica continua; la
        // musica è del lettore dentro JARVIS, quindi chiudendo JARVIS finisce da sola. «Chiudi» sulla sezione la ferma.
        IsolaJarvis.fineVoce()                         // 12 nov: accesa mentre l'app usciva, ma il dialogo non continua: si spegne
        if richiamo.sveglio { richiamo.ferma() }       // la frase dopo «Jarvis» a metà: buttata (il richiamo si riaccende da solo)
        // difetto 6 (controllo del 25 ott): gli stava parlando sopra e l'orecchio raccoglieva la frase. Anche quella si butta:
        // prima l'orecchio restava acceso e al ritorno (o alla chiusura del riconoscimento) la consegnava al cervello
        if orecchio.raccoglie {
            orecchio.ferma()
            orecchio.testoDetto = ""
        }
        if fase == .ascolto {
            if ascoltoCloud {                          // Mac: la registrazione da trascrivere non parte più
                ascoltoCloud = false
                turnoAscolto += 1
                if motore.isRunning { motore.stop() }
                motore.inputNode.removeTap(onBus: 0)
                stato = nil
                fase = .attesa
            } else {
                fermaAscolto(invia: false)
            }
        }
        parziale = ""
        chiudiInterruzione()
    }

    /// 11 nov (#16): il dialogo fuori dall'app è finito (nessuna frase per `secondi` dopo la risposta): il microfono si spegne e
    /// l'audio torna libero (sparisce il pallino arancione). Si riaccende tornando nell'app.
    func chiudiDialogoFuori(fra secondi: Double) {
        chiusuraFuori?.cancel()
        chiusuraFuori = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(secondi))
            guard let self, !Task.isCancelled, self.dialogoFuori, UIApplication.shared.applicationState != .active else { return }
            // revisione 11 nov: il dialogo è ancora vivo (lo ascolta, pensa, parla): si riguarda fra poco. Prima qui si usciva e
            // basta, e se l'ascolto finiva senza frase (silenzio) nessuno richiudeva più il microfono
            guard self.fase == .attesa, !self.richiamo.sveglio, self.inCoda.isEmpty else { self.chiudiDialogoFuori(fra: secondi); return }
            self.spegniMicFuori()
        }
    }

    /// Il dialogo fuori dall'app è finito: microfono spento, audio libero (se non suona musica), isola VOCE chiusa.
    private func spegniMicFuori() {
        chiusuraFuori?.cancel()
        dialogoFuori = false
        micChiusoFuori = true
        richiamo.ferma()
        orecchio.ferma()
        if !LettoreMusica.condiviso.suona, !LettoreMusica.condiviso.fermataDaJarvis, !AscoltoShazam.condiviso.suonaDentro {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        IsolaJarvis.fineVoce()
    }

    /// 12 nov · «Fine» sull'isola VOCE: il dialogo finisce subito (JARVIS tace, l'ascolto si butta) e il microfono si spegne.
    func fineDialogoFuori() {
        guard dialogoFuori || IsolaJarvis.voceAccesa else { return }
        interrompi()
        if fase == .ascolto { fermaAscolto(invia: false) }
        if richiamo.sveglio { richiamo.ferma() }
        richiamo.seguitoFinoA = .distantPast
        if UIApplication.shared.applicationState == .active { dialogoFuori = false; IsolaJarvis.fineVoce() } else { spegniMicFuori() }
    }

    /// 12 nov · l'isola VOCE (mockup approvato, build 32): la fase come sotto il reattore e la riga di quello che sente o risponde.
    /// iOS la lascia accendere solo con l'app ancora davanti: la schermata la chiama mentre l'app esce, poi si aggiorna da sola.
    func aggiornaIsolaVoce() {
        guard !Jarvis.usaAscoltoCloud else { return }
        let riga: String
        switch fase {
        case .ascolto: riga = parziale.isEmpty ? "La ascolto, Sir." : "«\(parziale)»"
        case .elaboro: riga = messaggi.last(where: { $0.ruolo == "user" }).map { "«\($0.testo)»" } ?? "…"
        case .parlo: riga = messaggi.last(where: { $0.ruolo == "assistant" && !$0.testo.isEmpty })?.testo ?? "…"
        case .attesa: riga = "Mi dica pure, Sir: la ascolto."
        }
        IsolaJarvis.voce(fase: fase.rawValue, riga: String(riga.prefix(160)))
    }

    /// 11 nov (#16): c'è un dialogo che può continuare fuori dall'app (JARVIS ascolta, pensa o parla, o ha appena risposto e il
    /// seguito vale ancora). La schermata lo usa per non spegnere il «Jarvis» quando l'app va dietro (revisione 11 nov: prima il
    /// microfono dell'attesa si spegneva comunque appena l'app usciva dal primo piano, e il seguito fuori dall'app non si sentiva).
    var dialogoPuoContinuareFuori: Bool {
        !Jarvis.usaAscoltoCloud && !micSpento && !micChiusoFuori
            && (dialogoFuori || fase != .attesa || richiamo.sveglio || Date() < richiamo.seguitoFinoA)
    }

    /// 11 nov (#16): di nuovo nell'app: il dialogo torna quello di sempre e il microfono dell'attesa si riaccende.
    func tornaDavanti() {
        chiusuraFuori?.cancel()
        dialogoFuori = false
        IsolaJarvis.fineVoce()                          // 12 nov: dentro JARVIS l'isola VOCE non serve
        if micChiusoFuori { micChiusoFuori = false; aggiornaRichiamo() }
    }

    private func fermaAscolto(invia: Bool, toccato: Bool = false) {
        guard fase == .ascolto || !invia else { return }
        ascoltoCloud = false
        if richiamo.sveglio { richiamo.ferma() }       // toccato mentre il richiamo raccoglieva la frase: la mando così
        timerSilenzio?.invalidate()
        timerSilenzio = nil
        timerTetto?.invalidate()
        timerTetto = nil
        generazioneRic += 1                            // 11 nov: i callback in ritardo del riconoscimento non riaprono niente
        ascoltoLungo = false
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil
        compito = nil
        let testo = parziale
        // 12 nov (A3): come ha parlato in questa frase rispetto al suo solito (velocità, forza, esitazioni); poi il suo solito impara
        if invia, let t0 = inizioParlato, !testo.isEmpty, ultimoParzialeAscolto != .distantPast {
            let secondi = ultimoParzialeAscolto.timeIntervalSince(t0)
            let forza = VoceAttiva.condivisa.forzaMedia
            voceCome = ComeParla.condiviso.riga(testo: testo, secondi: secondi, forzaDb: forza)
            ComeParla.condiviso.impara(testo: testo, secondi: secondi, forzaDb: forza)
        }
        inizioParlato = nil
        parziale = ""
        fase = .attesa
        fineFraseVoce = ultimoParzialeAscolto == .distantPast ? Date() : ultimoParzialeAscolto   // idea B: l'ultima parola sentita
        if toccato { motivoChiusura = "tocco" } else if motivoChiusura.isEmpty { motivoChiusura = "altro" }
        timerAnticipo?.invalidate()
        // 11 nov: una risposta anticipata che nessuno adotta (era un comando, «aspetta», niente da mandare) si butta fra poco
        if invia { Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if let self, let a = self.anticipo, !a.adottato { self.scartaAnticipo() }
        } } else { scartaAnticipo() }
        if invia, foto == nil, eseguiComando(testo) { scartaAnticipo(); return }       // «attiva la Sentinella»: lo apro io, niente cervello
        if invia, !testo.isEmpty || foto != nil {
            if foto == nil { Task { await self.instrada(testo) } } else { Task { await self.invia(testo) } }
        } else if invia, !toccato, dopoAspetta == .aspetta {
            miDica()                                 // «aspetta» e poi silenzio per 5 secondi: «Mi dica, Sir» (deciso dal signore)
        } else {
            aggiuntaInArrivo = false                 // non ha detto niente (anche dopo «Mi dica»): torna in attesa, in silenzio
            dopoAspetta = .no
        }
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
            VoceAttiva.condivisa.misura(buffer) // 11 nov: c'è ancora la voce del signore? (la fine frase non dipende solo dalle parole)
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
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        let chiave = ObjectIdentifier(u)
        Task { @MainActor in self.suonoIniziato(chiave) }      // 11 nov: il primo suono della risposta (voce dell'iPhone)
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let chiave = ObjectIdentifier(u)
        Task { @MainActor in self.fraseFinita(chiave, detta: true) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let chiave = ObjectIdentifier(u)
        Task { @MainActor in self.fraseFinita(chiave, detta: false) }
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
    /// 11 nov: una frase comincia a suonare adesso (per i tempi del turno)
    var iniziaFrase: ((ObjectIdentifier) -> Void)?

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

    /// 12 nov (E1): le frasi della risposta anticipata in preparazione (testo → scaricamento in corso).
    private var preparazioni: [String: Task<Void, Never>] = [:]

    /// 12 nov (E1): scarica in sottofondo la voce di una frase e la mette in cache, senza suonarla.
    func preparaUna(_ testo: String) {
        let id = Impostazioni.idVoceCloud
        let token = Portachiavi.leggi()
        guard preparazioni[testo] == nil, CacheVoce.leggi(testo, id: id) == nil,
              let url = URL(string: Impostazioni.indirizzo), !token.isEmpty else { return }
        let scarico = Task { () async -> Void in
            let (dati, _) = await VoceCloud.scarica(testo, id: id, url: url, token: token)
            if let dati { CacheVoce.salva(dati, testo: testo, id: id) }
        }
        preparazioni[testo] = scarico
        Task { [weak self] in
            await scarico.value
            try? await Task.sleep(for: .seconds(20))
            self?.preparazioni[testo] = nil
        }
    }

    /// `prima`: le frasi già dette della stessa risposta (punto 4). Con `prima` la frase non passa dalla cache:
    /// l'intonazione dipende da quello che la precede, quindi la cache resta per le frasi dette da sole.
    func accoda(_ u: AVSpeechUtterance, prima: String? = nil) {
        let testo = u.speechString
        let token = Portachiavi.leggi()
        let id = Impostazioni.idVoceCloud
        let url = URL(string: Impostazioni.indirizzo)
        let audio = Task { [weak self] () async -> Sorgente? in
            guard let url, let self else { return nil }
            // 12 nov (E1): la prima frase della risposta anticipata si stava già preparando: si aspetta quella, non se ne chiede un'altra
            if prima == nil, let inArrivo = self.preparazioni[testo] { await inArrivo.value }
            // le frasi già dette una volta sono in cache: partono subito, senza rete e senza consumare credito
            if prima == nil, let pronta = CacheVoce.leggi(testo, id: id) { return .intero(pronta) }
            // al massimo 2 frasi scaricate insieme: ElevenLabs ne accetta poche in parallelo,
            // e se si esagera alcune frasi tornano con la voce dell'iPhone (voce che cambia a metà)
            while self.inDownload >= 2 && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(60)) }
            if Task.isCancelled { return nil }
            self.inDownload += 1
            // in streaming: la voce comincia mentre ElevenLabs sta ancora generando il resto della frase
            let a = VoceCloud.avviaFlusso(testo, id: id, url: url, token: token, prima: prima)
            self.flussi.append(a)
            Task { @MainActor [weak self] in
                await a.attendiFine()
                guard let self else { return }
                self.inDownload -= 1
                self.flussi.removeAll { $0 === a }
                if let codice = a.codiceErrore, codice == 503 || codice == 401 { self.sospesaFino = Date().addingTimeInterval(300) }
                if prima == nil, let d = a.perCache() { CacheVoce.salva(d, testo: testo, id: id) }   // la prossima volta parte dalla cache
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
            iniziaFrase?(ObjectIdentifier(p.frase))
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
        var ripartenze = 0
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
                // 11 nov (#16, JARVIS muto uscendo dall'app mentre parla): iOS può fermare il motore della voce quando l'audio si
                // riorganizza (uscita dall'app, cuffie, il microfono dell'orecchio). Prima si riprovava senza riattivare l'audio e,
                // se non ripartiva, la frase restava muta fino in fondo. Ora: audio riattivato, motore riacceso; se proprio non
                // riparte, la frase la dice la voce dell'iPhone (JARVIS non resta mai muto)
                try? AVAudioSession.sharedInstance().setActive(true)
                m.prepare()
                if (try? m.start()) != nil { n.play() } else {
                    ripartenze += 1
                    if ripartenze >= 3 { return false }
                }
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
        m.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { b, _ in
            Volume.voce.misura(b)                       // il reattore segue la voce
            if Jarvis.usaAscoltoCloud { EcoMac.condivisa.misura(b) }   // difetto 2: sul Mac quanto forte esce, per riconoscere la sua eco
        }
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
    nonisolated static func avviaFlusso(_ testo: String, id: String, url: URL, token: String, prima: String? = nil) -> AudioInArrivo {
        let a = AudioInArrivo()
        let lavoro = Task.detached(priority: .userInitiated) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(token, forHTTPHeaderField: "x-jarvis-token")
            var corpo: [String: Any] = ["voce": testo, "flusso": true]
            if !id.isEmpty { corpo["id_voce"] = id }
            if let prima, !prima.isEmpty { corpo["prima"] = prima }   // punto 4: l'intonazione continua dalla frase prima
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
        if Jarvis.usaAscoltoCloud { EcoMac.segui(p) }  // difetto 2: sul Mac quanto forte esce, per riconoscere la sua eco
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            attesa = c
            attuale = ObjectIdentifier(p)
            if !p.play() { rilascia(false) }
        }
    }

    private func leggiConRiserva(_ u: AVSpeechUtterance) async -> Bool {
        // la voce dell'iPhone non sa dire i toni («[whispers]»): li salta
        let pulita = TagVoce.togli(u.speechString)
        if pulita.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let frase: AVSpeechUtterance
        if pulita == u.speechString { frase = u } else {
            frase = AVSpeechUtterance(string: pulita)
            frase.voice = u.voice
            frase.rate = u.rate
            frase.volume = u.volume
        }
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            attesa = c
            attuale = ObjectIdentifier(frase)
            riserva.speak(frase)
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
        // «vocePredefinitaCloud» arriva dal cervello all'avvio: voce, e con il modello fisso «voce·modello» (24 ott). Entra nella
        // chiave anche quando il signore ha scelto una voce, così al cambio di modello (v4 Turbo) le frasi si rifanno con la voce nuova
        let predefinita = UserDefaults.standard.string(forKey: "vocePredefinitaCloud") ?? ""
        let voce = id.isEmpty ? predefinita : "\(id)|\(predefinita)"
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

// MARK: - 11 nov · Risposta anticipata, finestra della conversazione, tempi del turno (analisi del dialogo, approvata dal signore)

extension Jarvis {

    /// La risposta preparata durante la pausa del signore. I pezzi arrivano e restano da parte finché il signore non ha davvero
    /// finito (allora si adotta e si dicono subito); se riprende a parlare, si butta e il cervello si ferma (linea chiusa).
    final class Anticipo {
        enum Evento { case testo(String), stato(String?), immagini(Any?) }
        let messaggio: Messaggio                 // la frase del signore come l'ha vista il cervello
        let ultimoPrima: UUID?                    // l'ultimo messaggio della chat quando è partito
        let idRisposta = UUID()
        var eventi: [Evento] = []
        var adottato = false
        var compito: Task<Void, Never>?
        var lavoroFine: Any?                       // il lavoro del cervello a risposta finita (per i ricordi, se si adotta)
        var voceFatta = false                      // 12 nov (E1): l'audio della prima frase è già in preparazione
        fileprivate var esito: Esito?
        private var finito = false
        private var attese: [CheckedContinuation<Void, Never>] = []

        init(messaggio: Messaggio, ultimoPrima: UUID?) {
            self.messaggio = messaggio
            self.ultimoPrima = ultimoPrima
        }

        /// È la stessa frase, detta nello stesso punto della conversazione e con le stesse note?
        func vale(per m: Messaggio, dopo ultimo: UUID?) -> Bool {
            Jarvis.normaAnticipo(m.testo) == Jarvis.normaAnticipo(messaggio.testo) && m.seguito == messaggio.seguito
                && m.interruzione == nil && m.aggiunta != true && m.nascosto == nil && ultimo == ultimoPrima
        }

        fileprivate func chiudi(_ e: Esito?) {
            esito = e
            finito = true
            attese.forEach { $0.resume() }
            attese.removeAll()
        }

        /// L'esito della sua richiesta (nil: non è arrivata in fondo).
        fileprivate func esitoFinale() async -> Esito? {
            if !finito { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in attese.append(c) } }
            return esito
        }
    }

    /// La frase come si confronta: minuscole, senza punteggiatura né spazi doppi («Che ore sono?» = «che ore sono»).
    nonisolated static func normaAnticipo(_ t: String) -> String {
        t.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Acceso? (iPhone; sul Mac la frase si trascrive in cloud a frase finita: lì non serve). Spento per 10 minuti se il cervello
    /// ha risposto «no_anticipo» (il suo interruttore d'emergenza, ANTICIPO=off).
    private var anticipoAcceso: Bool {
        !Jarvis.usaAscoltoCloud && !Impostazioni.muto && Date() >= anticipoSpentoFino
            && UserDefaults.standard.object(forKey: "rispostaAnticipata") as? Bool ?? true
    }

    /// A ogni parola nuova: fra 0,45 s di silenzio (parole e voce) si prova a preparare la risposta. Se il signore ha ripreso a
    /// parlare e la frase è cambiata, la risposta preparata prima si butta.
    fileprivate func programmaAnticipo(_ testo: String) {
        timerAnticipo?.invalidate()
        guard anticipoAcceso, fase == .ascolto else { return }
        if let a = anticipo, !a.adottato, Jarvis.normaAnticipo(a.messaggio.testo) != Jarvis.normaAnticipo(testo) { scartaAnticipo() }
        let t = testo
        timerAnticipo = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.provaAnticipo(t) }
        }
    }

    private func provaAnticipo(_ t: String) {
        guard fase == .ascolto, anticipo == nil, anticipiTurno < 3, Jarvis.normaAnticipo(parziale) == Jarvis.normaAnticipo(t) else { return }
        // la voce si sente ancora (le parole trascritte arrivano in ritardo): si riprova fra un attimo
        if VoceAttiva.condivisa.secondiDiSilenzio < 0.3 {
            timerAnticipo = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.provaAnticipo(t) }
            }
            return
        }
        guard let m = messaggioAnticipabile(t) else { return }
        anticipiTurno += 1
        let a = Anticipo(messaggio: m, ultimoPrima: messaggi.last?.id)
        anticipo = a
        var storia: [[String: Any]] = finestraCervello().map(Jarvis.perCervello)
        storia.append(Jarvis.perCervello(m))
        var corpo: [String: Any] = ["messaggi": storia, "dispositivo": Impostazioni.dispositivo, "strumenti_client": Strumenti.nomi,
                                    "a_voce": true, "anticipo": true, "capisce_aspetto": true]   // 12 nov (A1)
        // 12 nov (A3): come sta parlando finora (senza aggiornare il suo solito: la frase non è ancora chiusa)
        if let t0 = inizioParlato, let riga = ComeParla.condiviso.riga(testo: parziale, secondi: ultimoParzialeAscolto.timeIntervalSince(t0),
                                                                      forzaDb: VoceAttiva.condivisa.forzaMedia) { corpo["voce_come"] = riga }
        // revisione 11 nov: come il turno normale, anche l'anticipo passa dall'arbitro (se la stessa frase l'ha sentita l'orologio,
        // risponde uno solo). La fine della frase è adesso: il signore ha appena smesso di parlare
        corpo["arbitro"] = ["id": Impostazioni.idDispositivo, "fine": Int64(Date().timeIntervalSince1970 * 1000)] as [String: Any]
        if let schermo = Schermo.perCervello(sezione: sezioneAperta) { corpo["schermo"] = schermo }
        let base = corpo
        a.compito = Task { [weak self] in
            guard let self else { return }
            var c = base
            if let posizione = await Posizione.attuale() { c["posizione"] = posizione }
            do {
                let e = try await self.flusso(c, id: a.idRisposta, richiesta: UUID().uuidString, deposito: a)
                a.chiudi(e)
                if case .aspetto = e { self.anticipoAspetta(a) }     // 12 nov (A1): non ha finito, si aspetta di più
            } catch {
                a.chiudi(nil)
            }
        }
    }

    /// La frase andrebbe al cervello come una domanda normale (non un comando dell'app, non «aspetta», non un'interruzione,
    /// niente foto)? Allora ecco il messaggio come lo manderebbe `instrada` (con la nota del seguito se serve). Nil: niente anticipo.
    private func messaggioAnticipabile(_ t: String) -> Messaggio? {
        let frase = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard frase.count >= 6, Dialogo.volume(frase).cambio == nil, !Jarvis.eSoloSilenzio(frase), !Seguito.soloAspetta(frase) else { return nil }
        guard ConfidenteAperto.domanda == nil, occhi == nil, foto == nil, fotoGiro.isEmpty, allegato == nil, !lidarAperto,
              !LidarAperta.aperta, !BrowserVoce.aperto, !micSpento else { return nil }
        let (_, chiede) = Jarvis.togliRichiamo(frase)
        guard !chiede, !aggiuntaInArrivo, dopoAspetta == .no, interruzioneValida() == nil else { return nil }
        let detta = Jarvis.fraseAnticipabile(frase)
        guard Jarvis.normaAnticipo(detta).split(separator: " ").count >= 2, !comandoLocale(frase), !comandoLocale(detta) else { return nil }
        var m = Messaggio(ruolo: "user", testo: detta)
        if let u = messaggi.last(where: { $0.ruolo == "user" }), Date().timeIntervalSince(u.data) < 60 { m.seguito = true }
        return m
    }

    /// La frase come la manderebbe `instrada` (senza «Jarvis», «aspetta», «allora» davanti): la stessa per l'anticipo e per l'attesa.
    nonisolated static func fraseAnticipabile(_ t: String) -> String {
        let frase = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let pulito = Jarvis.togliRichiamo(frase).0
        return pulito.isEmpty ? frase : pulito
    }

    /// 12 nov (A1): la risposta anticipata dice che il signore non ha finito («[aspetto]»): non si adotta, e la pausa di fine frase
    /// di questo ascolto diventa di almeno 3 secondi finché la frase resta quella. Se poi tace, la frase parte con `dopo_aspetto`.
    fileprivate func anticipoAspetta(_ a: Anticipo) {
        guard anticipo === a, !a.adottato, fase == .ascolto else { return }
        anticipo = nil
        anticipiButtati += 1
        aspettoSu = Jarvis.normaAnticipo(a.messaggio.testo)
        pausaMinimaAscolto = 3
        armaSilenzio(secondi: pausaAscolto(parziale))
    }

    /// 12 nov (E1): appena la risposta anticipata ha la sua prima frase, la voce di quella frase si prepara in sottofondo (senza
    /// suonare): se il signore ha davvero finito, JARVIS parla subito, senza aspettare la voce dal cloud. Il taglio è lo stesso di
    /// `accodaVoce`, così la frase si ritrova uguale nella cache.
    fileprivate func preparaVoce(_ a: Anticipo, finita: Bool) {
        guard !a.voceFatta, Impostazioni.voceCloud, !Impostazioni.muto, cloud.disponibile else { return }
        let pezzi: [String] = a.eventi.compactMap { ev -> String? in
            if case .testo(let t) = ev { return t }
            return nil
        }
        guard let frase = Jarvis.primaFraseVoce(pezzi, finita: finita) else { return }
        a.voceFatta = true
        cloud.preparaUna(frase)
    }

    /// La prima frase che `accodaVoce` manderebbe alla voce con questi pezzi di testo (stesse regole di taglio).
    nonisolated static func primaFraseVoce(_ pezzi: [String], finita: Bool) -> String? {
        var buffer = ""
        for p in pezzi {
            buffer += p
            let c = Array(buffer)
            var taglio: Int?
            for k in c.indices.dropLast() where ".!?…;:\n".contains(c[k]) && c[k + 1].isWhitespace { taglio = k + 1 }
            if taglio == nil, c.count >= 28,
               let v = c.indices.dropLast().last(where: { c[$0] == "," && c[$0 + 1].isWhitespace }), v >= 12 { taglio = v + 1 }
            if let t = taglio {
                let f = String(c[..<t]).trimmingCharacters(in: .whitespacesAndNewlines)
                return f.isEmpty ? nil : f
            }
        }
        guard finita else { return nil }
        let f = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? nil : f
    }

    /// La risposta preparata non serve più (il signore ha continuato, ha cambiato frase, era un comando): si chiude la linea e il
    /// cervello si ferma.
    fileprivate func scartaAnticipo() {
        timerAnticipo?.invalidate()
        guard let a = anticipo, !a.adottato else { anticipo = nil; return }
        a.compito?.cancel()
        anticipo = nil
        anticipiButtati += 1
    }

    /// Il signore ha finito ed era proprio la frase anticipata: la risposta (già pronta, o in arrivo) diventa quella vera.
    fileprivate func adotta(_ a: Anticipo, fineVoce: Date?) {
        timerAnticipo?.invalidate()
        a.adottato = true
        anticipo = nil
        messaggi.append(a.messaggio)
        let risposta = Messaggio(id: a.idRisposta, ruolo: "assistant", testo: "")
        messaggi.append(risposta)
        idTurno = risposta.id
        salva()
        iniziaMisura(id: risposta.id, fineVoce: fineVoce, anticipo: "adottato")
        ultimoInvio = Date()
        rispostaIniziata = false
        frasiVoce = []
        dettoRisposta = (risposta.id, "")
        richiamo.liberoFinoA = Date().addingTimeInterval(Dialogo.finestraAggiunta)   // nei primi 2 secondi può ancora aggiungere
        richiamo.seguitoFinoA = .distantPast
        fase = .elaboro
        flussoFinito = false
        // quello che è già arrivato, nell'ordine: la voce parte subito
        let arrivati = a.eventi
        a.eventi.removeAll()
        for ev in arrivati {
            switch ev {
            case .testo(let pezzo): aggiungi(pezzo, id: risposta.id)
            case .stato(let s): stato = s
            case .immagini(let d): aggiungiImmagini(Immagine.daJSON(d), id: risposta.id)
            }
        }
        let rete = a.compito
        compitoRete = Task { [weak self] in
            let esito = await withTaskCancellationHandler { await a.esitoFinale() } onCancel: { rete?.cancel() }
            guard let self, !Task.isCancelled else { return }
            if let esito, !Jarvis.eNoAnticipo(esito) {
                // finita durante la pausa: il cervello aveva rimandato i ricordi e la giornata; adottata, li fa adesso
                if case .fine(let testo, _) = esito, let lavoro = a.lavoroFine {
                    Task { _ = await VistaVitals.chiama(["anticipo_adottato": ["lavoro": lavoro, "testo": testo] as [String: Any],
                                                         "dispositivo": Impostazioni.dispositivo], attesa: 30) }
                }
                await self.turno(storia: [], foto: nil, id: risposta.id, fineVoce: fineVoce, primo: esito)
            } else {
                // la richiesta anticipata non è arrivata in fondo (rete, interruttore): la domanda riparte come sempre
                if case .noAnticipo? = esito { self.anticipoSpentoFino = Date().addingTimeInterval(600) }
                self.azzeraTesto(risposta.id)
                let storia = self.finestraCervello().filter { $0.id != risposta.id && !$0.testo.isEmpty }.map(Jarvis.perCervello)
                await self.turno(storia: storia, foto: nil, id: risposta.id, fineVoce: fineVoce)
            }
        }
        if arrivati.isEmpty, Date().timeIntervalSince(ultimoPonte) >= 20 { armaPonte(id: risposta.id, testo: a.messaggio.testo) }
        else { compitoPonte?.cancel(); inizioTurno = Date() }
    }

    fileprivate static func eNoAnticipo(_ e: Esito) -> Bool {
        if case .noAnticipo = e { return true }
        return false
    }

    // MARK: La finestra della conversazione

    /// Le battute che vanno al cervello: da 20 a 40, e la finestra scorre a scatti di 20 (quando supera le 40, le 20 più vecchie
    /// escono e le riassume il cervello). Così la parte vecchia resta identica da un turno all'altro e il cervello la rilegge dalla
    /// cache: più veloce e più economico man mano che la conversazione cresce.
    fileprivate func finestraCervello() -> [Messaggio] {
        let validi = messaggi.filter { !$0.testo.isEmpty }
        guard !validi.isEmpty else { inizioFinestra = nil; return [] }
        var k = inizioFinestra.flatMap { id in validi.firstIndex { $0.id == id } } ?? max(0, validi.count - 20)
        if validi.count - k > 40 { k = validi.count - 20 }
        inizioFinestra = validi[k].id
        return Array(validi[k...])
    }

    /// Una battuta come la riceve il cervello, con il momento in cui è stata detta (giorno e ora per il cervello).
    fileprivate static func perCervello(_ m: Messaggio) -> [String: Any] {
        ["role": m.ruolo, "content": m.testoPerCervello, "quando": Int((m.data.timeIntervalSince1970 * 1000).rounded())]
    }

    // MARK: I tempi del turno

    /// Comincia la misura di un turno detto a voce: da quando il signore ha smesso di parlare al primo suono della risposta.
    fileprivate func iniziaMisura(id: UUID, fineVoce: Date?, anticipo esitoAnticipo: String) {
        guard let fineVoce else { misuraDa = nil; misuraTurno = nil; return }
        misuraDa = fineVoce
        misuraTurno = id
        misura = ["esito": "voce", "chiusura": motivoChiusura.isEmpty ? "altro" : motivoChiusura, "riavvii": riavviiAscolto,
                  "ritmo": (RitmoSignore.condiviso.fattore * 100).rounded() / 100, "termico": ProcessInfo.processInfo.thermalState.rawValue,
                  "battute": finestraCervello().count, "anticipo": esitoAnticipo, "buttati": anticipiButtati]
        anticipiButtati = 0
        motivoChiusura = ""
    }

    /// Una frase di JARVIS comincia a suonare: se è la prima della risposta misurata, il tempo è fatto (va col turno dopo).
    fileprivate func suonoIniziato(_ chiave: ObjectIdentifier) {
        guard let da = misuraDa, let t = misuraTurno, frasiRisposta[chiave]?.id == t else { return }
        misura["ms_primo_suono"] = Int(Date().timeIntervalSince(da) * 1000)
        misura["ms_totale"] = Int(Date().timeIntervalSince(ultimoInvio) * 1000)
        tempiDaMandare = misura
        misuraDa = nil
        misuraTurno = nil
    }
}
