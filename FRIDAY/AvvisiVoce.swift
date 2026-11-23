#if os(iOS)
import Foundation
import AVFoundation
import UserNotifications
import CryptoKit

// MARK: - 18 nov · 13.1 (2) · LE NOTIFICHE CON LA VOCE DI JARVIS (mockup FUORI approvato dal signore)
// Il signore (18 nov): «notifiche vocali con la voce di JARVIS per le iniziative ad app chiusa: l'audio preparato mentre è aperta,
// usato come suono della notifica (fino a 30 secondi)». Condizioni decise insieme: solo cose importanti (l'appuntamento vicino,
// la pioggia prima di uscire, un sì che aspetta da ore), al massimo 3 al giorno, mai di notte (23–7), rispettano le modalità di
// concentrazione (ci pensa iOS), si spengono con «niente notifiche oggi».
// - L'audio: la frase detta dalla voce cloud di JARVIS (quella già in cache, o scaricata adesso), se no dalla voce dell'iPhone;
//   in Library/Sounds come .caf (iOS non suona mp3 come suono di notifica), tagliata a 29 secondi.
// - Ad app aperta, ogni 5 minuti, si preparano gli audio delle notifiche che potrebbero servire: andando dietro sono già pronti.
// - Limite di Apple (detto al signore): col telefono bloccato e l'orologio al polso iOS manda la notifica all'orologio e il telefono
//   resta muto; la voce si sente se lo specchio delle notifiche di JARVIS è spento nell'app Watch (scelta del signore).

@MainActor
enum AvvisiVoce {
    static let massimoAlGiorno = 3

    // MARK: Le regole

    /// «Niente notifiche oggi»: fino a domattina alle 7.
    static var spenteFino: Date? {
        guard let d = UserDefaults.standard.object(forKey: "avvisi.spenteFino") as? Date, d > Date() else { return nil }
        return d
    }

    static func spegniOggi() {
        let cal = Calendar.current
        let domani = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(86_400)
        let fino = cal.date(bySettingHour: 7, minute: 0, second: 0, of: domani) ?? domani
        UserDefaults.standard.set(fino, forKey: "avvisi.spenteFino")
    }

    static func riaccendi() { UserDefaults.standard.removeObject(forKey: "avvisi.spenteFino") }

    /// Mai di notte (23–7) e mai con «niente notifiche oggi».
    static func permesso(_ quando: Date) -> Bool {
        if let fino = spenteFino, quando < fino { return false }
        let h = Calendar.current.component(.hour, from: quando)
        return h >= 7 && h < 23
    }

    /// Le notifiche programmate o arrivate (identificativo → ora), per il conto dei 3 al giorno.
    private static var registro: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: "avvisi.registro") as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue.filter { Date().timeIntervalSince($0.value) < 2 * 86_400 }, forKey: "avvisi.registro") }
    }

    /// C'è posto quel giorno (al massimo 3, contando quelle già arrivate e quelle già programmate, questa esclusa)?
    static func posto(_ quando: Date, id: String) -> Bool {
        let cal = Calendar.current
        return registro.filter { $0.key != id && cal.isDate($0.value, inSameDayAs: quando) }.count < massimoAlGiorno
    }

    static func segna(_ id: String, _ quando: Date) { var r = registro; r[id] = quando; registro = r }

    /// JARVIS di nuovo davanti: quelle non ancora arrivate sono state tolte e non contano più.
    static func togli(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var r = registro
        for id in ids { r[id] = nil }
        registro = r
    }

    // MARK: Il suono: la voce di JARVIS

    private static var cartella: URL? {
        guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let c = lib.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }

    private static func nome(_ testo: String) -> String {
        let h = SHA256.hash(data: Data(testo.utf8)).map { String(format: "%02x", $0) }.joined()
        return "jarvis-avviso-" + String(h.prefix(20)) + ".caf"
    }

    /// Il suono della notifica per questa frase: la voce di JARVIS se si riesce a prepararla, se no quello di iOS.
    /// `rete`: si può scaricare adesso dalla voce cloud (andando dietro sì, al massimo 8 secondi; in anticipo sempre).
    static func suono(per testo: String, rete: Bool) async -> UNNotificationSound {
        guard let c = cartella else { return .default }
        let file = nome(testo)
        let url = c.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: url.path) { return UNNotificationSound(named: UNNotificationSoundName(file)) }
        pulisci(c)
        let id = Impostazioni.idVoceCloud
        var audio = CacheVoce.leggi(testo, id: id)
        if audio == nil, rete, Impostazioni.voceCloud, let indirizzo = URL(string: Impostazioni.indirizzo) {
            let token = Portachiavi.leggi()
            if !token.isEmpty {
                let (d, _) = await VoceCloud.scarica(testo, id: id, url: indirizzo, token: token)
                if let d { CacheVoce.salva(d, testo: testo, id: id); audio = d }
            }
        }
        if let audio, await FileVoceAvviso.daAudio(audio, a: url) { return UNNotificationSound(named: UNNotificationSoundName(file)) }
        let voce = Jarvis.voceScelta()?.identifier
        if await FileVoceAvviso.daVoceIphone(testo, voce: voce, a: url) { return UNNotificationSound(named: UNNotificationSoundName(file)) }
        return .default
    }

    /// Ad app aperta: gli audio delle notifiche che potrebbero servire, pronti prima di andare dietro.
    static func prepara(_ testi: [String]) async {
        for t in testi { _ = await suono(per: t, rete: true) }
    }

    /// Via gli audio vecchi di più di due giorni (le frasi cambiano ogni giorno).
    private static func pulisci(_ c: URL) {
        guard let elenco = try? FileManager.default.contentsOfDirectory(at: c, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in elenco where f.lastPathComponent.hasPrefix("jarvis-avviso-") {
            let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if Date().timeIntervalSince(d) > 2 * 86_400 { try? FileManager.default.removeItem(at: f) }
        }
    }
}

/// I file audio delle notifiche (fuori dal thread principale): .caf lineare a 16 bit, al massimo 29 secondi.
nonisolated enum FileVoceAvviso {
    static let massimo: Double = 29

    /// Il file: PCM lineare a 16 bit, come vuole iOS per i suoni delle notifiche.
    static func impostazioni(_ hz: Double, _ canali: Int) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: hz, AVNumberOfChannelsKey: canali,
         AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
    }

    /// Dalla voce cloud (mp3, o wav per le frasi arrivate in streaming).
    @concurrent static func daAudio(_ dati: Data, a url: URL) async -> Bool {
        let wav = dati.prefix(4) == Data("RIFF".utf8)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + (wav ? ".wav" : ".mp3"))
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try dati.write(to: tmp)
            let ingresso = try AVAudioFile(forReading: tmp)
            let formato = ingresso.processingFormat
            let quanti = AVAudioFrameCount(min(Double(ingresso.length), formato.sampleRate * massimo))
            guard quanti > 0, let b = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: quanti) else { return false }
            try ingresso.read(into: b, frameCount: quanti)
            let uscita = try AVAudioFile(forWriting: url, settings: impostazioni(formato.sampleRate, Int(formato.channelCount)),
                                         commonFormat: formato.commonFormat, interleaved: formato.isInterleaved)
            try uscita.write(from: b)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    /// Dalla voce dell'iPhone (senza rete o senza voce cloud).
    @concurrent static func daVoceIphone(_ testo: String, voce: String?, a url: URL) async -> Bool {
        let lavoro = ScritturaVoce(url: url)
        return await lavoro.scrivi(testo, voce: voce)
    }
}

/// La voce dell'iPhone scritta su file (AVSpeechSynthesizer.write): i pezzi arrivano su un altro thread, uno alla volta.
nonisolated final class ScritturaVoce: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var scritti: AVAudioFramePosition = 0
    private var fine: CheckedContinuation<Bool, Never>?
    private var sintesi: AVSpeechSynthesizer?

    init(url: URL) { self.url = url }

    func scrivi(_ testo: String, voce: String?) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            lock.withLock { fine = c }
            let s = AVSpeechSynthesizer()
            let u = AVSpeechUtterance(string: testo)
            u.voice = voce.flatMap { AVSpeechSynthesisVoice(identifier: $0) } ?? AVSpeechSynthesisVoice(language: "it-IT")
            lock.withLock { sintesi = s }
            s.write(u) { [self] buffer in self.ricevi(buffer) }
            // rete di sicurezza: se iOS non chiude mai la scrittura, dopo 20 secondi si va avanti col suono di iOS
            Task { [self] in
                try? await Task.sleep(for: .seconds(20))
                self.chiudi(false)
            }
        }
    }

    private func ricevi(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 { chiudi(true); return }
        lock.lock()
        defer { lock.unlock() }
        guard fine != nil else { return }
        do {
            if file == nil {
                let f = pcm.format
                file = try AVAudioFile(forWriting: url, settings: FileVoceAvviso.impostazioni(f.sampleRate, Int(f.channelCount)),
                                       commonFormat: f.commonFormat, interleaved: f.isInterleaved)
            }
            guard let file, Double(scritti) < pcm.format.sampleRate * FileVoceAvviso.massimo else { return }
            try file.write(from: pcm)
            scritti += AVAudioFramePosition(pcm.frameLength)
        } catch {
            file = nil
        }
    }

    private func chiudi(_ ok: Bool) {
        lock.lock()
        let c = fine
        fine = nil
        let riuscito = ok && file != nil && scritti > 0
        file = nil
        sintesi = nil
        lock.unlock()
        if !riuscito, c != nil { try? FileManager.default.removeItem(at: url) }
        c?.resume(returning: riuscito)
    }
}
#endif
