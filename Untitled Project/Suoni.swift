#if os(iOS)
import AVFoundation
import QuartzCore
import UIKit

/// I suoni dell'interfaccia, alla Stark. Se nel progetto c'è un file audio con il nome giusto, si usa quello;
/// altrimenti l'app genera un piccolo segnale sintetico. File riconosciuti (m4a, mp3, wav o caf):
///   «tick» (o «tocco») → tocco su un'icona      «avvio» → suono di fondo mentre le icone si accendono
///   «avvio» ha già dentro una pulsazione per ogni icona, al passo dell'avvio (150 ms, 110 tra i gruppi, INTELLIGENCE 120)
///   «plim» → accensione di ogni singola icona (se manca, silenzio)      «inlinea» → fine sequenza
///   «scheda» → una sezione si apre (caricamento)      «schedapronta» → la sezione è pronta
/// Si spengono con «Suoni dell'interfaccia» nelle impostazioni.
@MainActor
enum Suoni {
    static var attivi: Bool { UserDefaults.standard.object(forKey: "suoni") as? Bool ?? true }

    /// All'apertura l'audio dell'iPhone va preso SUBITO, prima della musica d'avvio: l'avvio ha la precedenza.
    /// «playback»: suona anche col silenzioso, la musica di altre app si abbassa, i tasti del volume regolano JARVIS.
    static func preparaAudio() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? s.setActive(true)
    }

    /// Finito l'avvio: l'audio torna come prima (la musica delle altre app risale); poi l'ascolto e la voce lo prendono come sempre.
    static func fineAvvioAudio() async {
        // prima finiscono i suoni ancora in corso («in linea», la coda della musica): spegnere l'audio li taglierebbe
        for _ in 0..<30 where lettori.contains(where: { $0.isPlaying }) { try? await Task.sleep(for: .milliseconds(100)) }
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        try? s.setCategory(.ambient, mode: .default, options: [])
    }

    /// Tocco su un'icona o sul reattore.
    static func tocco() { Aptica.click(); suona(.tocco) }
    /// JARVIS inizia ad ascoltare.
    static func ascolto() { suona(.ascolto) }
    /// JARVIS ha finito e torna in attesa.
    /// Conferma: solo la vibrazione. Il suono «pronto» è tolto (20 ott, su richiesta): niente suono finché non se ne sceglie un altro.
    static func pronto() {
        Aptica.pronto()
    }
    /// Spunte verdi «Fatto» (promesse, spesa, ricordi) e SOS: qui il suono «pronto» resta (20 ott). Pieno+, 100%.
    static func fatto() {
        Aptica.pronto()
        if attivi, let url = file("pronto") { riproduci(url, volume: 1.0) }
    }
    /// Qualcosa non è andato.
    static func errore() { suona(.errore) }
    /// Sistemi in linea, all'apertura.
    static func avvio() { suona(.avvio) }

    /// Una sezione si apre (parte il caricamento HUD). File: «scheda». Se manca, il suono dell'ascolto.
    static func schedaApre() {
        guard attivi else { return }
        guard let url = file("scheda"), let p = try? AVAudioPlayer(contentsOf: url) else { suona(.ascolto); return }
        p.volume = 1.0                                               // schede: 100%
        lettoreScheda?.stop()
        lettoreScheda = p
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))          // un «tick» dell'app non è un battito di mani
    }
    /// La sezione ha i dati e si stampa sullo schermo. File: «schedapronta». Se manca, il suono di «pronto».
    /// Il suono del caricamento sfuma in quel momento, così i due non si accavallano.
    static func schedaPronta(soloSfuma: Bool = false) {
        guard attivi else { return }
        if let p = lettoreScheda, p.isPlaying { p.setVolume(0, fadeDuration: 0.18) }
        if soloSfuma { return }                                      // Bea e Spesa: il suono d'apertura sfuma, nessun altro suono
        if let url = file("schedapronta") { riproduci(url, volume: 1.0); return }
        return                                                       // niente bip «pronto» di riserva
    }
    private static var lettoreScheda: AVAudioPlayer?
    /// L'apertura delle sezioni dal vivo e personali: Bea, Spesa, Occhi, Allenatore, Profiler. File: «apertura»;
    /// se manca, il suono delle schede. Usa lo stesso lettore delle schede, così «schedaPronta» lo sfuma.
    static func apertura() {
        guard attivi else { return }
        guard let url = file("apertura"), let p = try? AVAudioPlayer(contentsOf: url) else { schedaApre(); return }
        p.volume = 1.0                                               // come le schede: 100%
        lettoreScheda?.stop()
        lettoreScheda = p
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))
    }
    /// L'apertura delle sezioni con fotocamera (Occhi, Cucina, Allenatore, Profiler, Scanner), quando la fotocamera è pronta.
    /// File: «aperturacamera»; finché non c'è, lo stesso suono di «apertura».
    static func aperturaCamera() {
        Aptica.fotocamera()
        guard attivi else { return }
        if let url = file("aperturacamera") { riproduci(url, volume: 1.0); return }
        apertura()
    }
    private static var lettoreChat: AVAudioPlayer?
    /// La chat si stampa all'avvio: i caratteri che si caricano. File: «chatcarica». Sfuma con `chatPronta()`.
    static func chatCarica() {
        guard attivi, let url = file("chatcarica"), let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = 0.7                                               // come le schede: 70%
        lettoreChat?.stop()
        lettoreChat = p
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))
    }
    /// La chat è stampata: il suono del caricamento sfuma.
    static func chatPronta() {
        if let p = lettoreChat, p.isPlaying { p.setVolume(0, fadeDuration: 0.25) }
    }
    /// La chat si svuota (cestino › Pulisci). File: «chatsvuota».
    static func chatSvuota() {
        guard attivi, let url = file("chatsvuota") else { return }
        riproduci(url, volume: 1.0)
    }
    /// Click delle tre icone in alto (SISTEMI, cestino, impostazioni). File: «clicktesta»; se manca, il tick normale.
    static func clickTesta() {
        Aptica.click()
        guard attivi else { return }
        if let url = file("clicktesta") { riproduci(url, volume: 1.0); return }
        tocco()
    }
    // MARK: MARK XI (mockup del 3 nov, suoni scelti dal signore)

    /// Il click delle icone del Dock in alto (Social, Musica, Studio, Sistemi, cestino, Impostazioni): mixkit «modern technology
    /// select» (3124). File: «dock». Sul Mac suona anche passandoci sopra col puntatore (`clickDockSopra`).
    static func clickDock() {
        Aptica.click()
        guard attivi else { return }
        if let url = file("dock") { riproduci(url, volume: 1.0); return }
        clickTesta()
    }
    /// Sul Mac, il puntatore che entra su un'icona del Dock: lo stesso click, al massimo uno ogni 60 ms.
    static func clickDockSopra() {
        guard attivi, let url = file("dock") else { return }
        let ora = CACurrentMediaTime()
        guard ora - ultimoDockSopra >= 0.06 else { return }
        ultimoDockSopra = ora
        riproduci(url, volume: 0.7)
    }
    private static var ultimoDockSopra: CFTimeInterval = 0

    /// Lo scatto della click wheel: un'icona passa in alto. File: «ruota» (mixkit «mouse hard clicking», un colpo solo).
    /// Arriva a raffica (fino a uno ogni 35 ms): quattro lettori già pronti, a turno, così parte senza ritardo.
    static func scattoRuota() {
        guard attivi, let url = file("ruota") else { return }
        if lettoriRuota.isEmpty {
            lettoriRuota = (0..<4).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            lettoriRuota.forEach { $0.volume = 0.86; $0.prepareToPlay() }
        }
        guard !lettoriRuota.isEmpty else { return }
        let p = lettoriRuota[turnoRuota % lettoriRuota.count]
        turnoRuota += 1
        p.currentTime = 0
        p.play()
        BattitoMani.ignora(per: 0.5)
    }
    private static var lettoriRuota: [AVAudioPlayer] = []
    private static var turnoRuota = 0

    /// La corona si è fermata: l'ologramma dell'icona si crea. File: «olo» (mixkit «click melodic tone»).
    static func tonoOlo() {
        guard attivi, let url = file("olo") else { return }
        riproduci(url, volume: 0.86)
    }

    // MARK: MARK XI · i suoni delle pagine, a tempo con l'animazione (3 nov sera, «sincronizza alla perfezione»)
    // «sparisce», «caricaolo» e «scelta» hanno due lettori già pronti ciascuno (niente file da aprire nel momento del gesto) e
    // partono a un istante preciso dell'orologio audio (`play(atTime:)`), tenendo conto del ritardo dell'uscita (altoparlante
    // ~10–20 ms, cuffie Bluetooth di più). Ogni funzione restituisce fra quanto il suono si sente davvero: l'animazione si regola
    // su quello, così i colpi del suono e i momenti dell'animazione coincidono.

    /// Prepara i lettori (all'apertura del contenitore delle sezioni), così il primo gesto non aspetta.
    static func preparaPagine() {
        for n in ["sparisce", "caricaolo", "scelta"] { _ = pronti(n) }
    }

    /// Le pagine olografiche delle sezioni aperte compaiono. File: «caricaolo» (vadim «holographic interface menu opening»).
    /// Sfuma al primo gesto (`zittisciOlo`). Restituisce fra quanti secondi si sente.
    @discardableResult static func caricaOlo() -> TimeInterval {
        let (fra, p) = suonaPronto("caricaolo", volume: 1.0)
        if let p { lettoreOlo = p }
        return fra
    }
    /// Si sfoglia, si sceglie o si chiude una pagina: il suono delle pagine sfuma (0,25 s).
    static func zittisciOlo() {
        if let p = lettoreOlo, p.isPlaying { p.setVolume(0, fadeDuration: 0.25) }
    }
    private static var lettoreOlo: AVAudioPlayer?

    /// AGGANCIO: la sezione vola nel reattore. File: «sparisce» (vadim «hologram menu appear»; colpi a 0,466 e 1,002 s).
    /// Restituisce fra quanti secondi si sente (l'aggancio cade 0,44 s dopo).
    @discardableResult static func sparisce() -> TimeInterval {
        suonaPronto("sparisce", volume: 1.0).0
    }

    /// Scelta una pagina dalle pagine olografiche (solo le sezioni senza fotocamera: quelle con la fotocamera hanno il loro suono).
    /// File: «scelta» (soundshelfstudio «sci-fi ui click»). `fra`: fra quanti secondi deve sentirsi (quando la pagina arriva).
    static func sceltaPagina(fra: TimeInterval = 0) {
        _ = suonaPronto("scelta", volume: 1.0, fra: fra)
    }

    private static var lettoriPronti: [String: [AVAudioPlayer]] = [:]
    private static var turnoPronti: [String: Int] = [:]

    /// Un lettore già pronto per il file `nome` (due a turno: un suono può ripartire mentre l'altro finisce).
    private static func pronti(_ nome: String) -> AVAudioPlayer? {
        if lettoriPronti[nome] == nil, let url = file(nome) {
            let l: [AVAudioPlayer] = (0..<2).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
            l.forEach { $0.prepareToPlay() }
            lettoriPronti[nome] = l
        }
        guard let l = lettoriPronti[nome], !l.isEmpty else { return nil }
        let k = (turnoPronti[nome] ?? 0) % l.count
        turnoPronti[nome] = k + 1
        return l[k]
    }

    /// Suona `nome` in modo che si senta fra `fra` secondi (o appena possibile): restituisce fra quanto si sente davvero.
    private static func suonaPronto(_ nome: String, volume: Float, fra: TimeInterval = 0) -> (TimeInterval, AVAudioPlayer?) {
        guard attivi, let p = pronti(nome) else { return (0, nil) }
        let uscita = min(0.25, max(0, AVAudioSession.sharedInstance().outputLatency))
        let anticipo = max(0.012, fra - uscita)                     // 12 ms: il tempo all'audio di mettersi in fila, preciso
        p.stop()
        p.currentTime = 0
        p.volume = volume
        p.prepareToPlay()
        p.play(atTime: p.deviceCurrentTime + anticipo)
        BattitoMani.ignora(per: anticipo + p.duration + 0.2)         // un suono dell'app non è un battito di mani
        return (anticipo + uscita, p)
    }

    /// Il tick di un'icona che si accende all'avvio: un segnale digitale da HUD, non una nota.
    /// Un impulso di rumore elettronico brevissimo più un «ping» che scende di tono in 40 ms, con una minima
    /// variazione da un'icona all'altra. Stile: «hud» (predefinito), «note» (la scala di prima) o «off».
    static func plim(_ indice: Int) {
        guard attivi else { return }
        if indice == 0, let url = file("avvio") { riproduci(url, volume: 1.0) }   // musica d'avvio: 100%
        if let url = file("plim") { riproduci(url, volume: 1.0); return }   // pim delle icone: 100% (l'avvio si deve sentire)
        let stile = UserDefaults.standard.string(forKey: "suonoAvvio") ?? "off"   // sintesi solo se scelta apposta
        guard stile != "off" else { return }
        let k = min(max(indice, 0), 23)
        let chiave = "\(stile)-\(k)"
        let dati = cachePlim[chiave] ?? (stile == "note" ? generaNota(k) : generaTick(k))
        cachePlim[chiave] = dati
        guard let p = try? AVAudioPlayer(data: dati) else { return }
        p.volume = 0.6
        lettori.removeAll { !$0.isPlaying }
        lettori.append(p)
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))          // un «tick» dell'app non è un battito di mani
    }

    /// Chiusura della sequenza: «sistemi in linea», un doppio ping discendente, morbido.
    static func inLinea() {
        guard attivi else { return }
        if let url = file("inlinea") { riproduci(url, volume: 0.5); return }
        guard (UserDefaults.standard.string(forKey: "suonoAvvio") ?? "off") != "off" else { return }
        let dati = cachePlim["inlinea"] ?? generaInLinea()
        cachePlim["inlinea"] = dati
        guard let p = try? AVAudioPlayer(data: dati) else { return }
        p.volume = 0.3
        lettori.removeAll { !$0.isPlaying }
        lettori.append(p)
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))          // un «tick» dell'app non è un battito di mani
    }

    private static var cachePlim: [String: Data] = [:]

    /// Il file audio del signore, se è stato trascinato nel progetto.
    private static var cacheFile: [String: URL?] = [:]
    private static func file(_ nome: String) -> URL? {
        if let u = cacheFile[nome] { return u }
        let u = ["m4a", "mp3", "wav", "caf"].lazy.compactMap { Bundle.main.url(forResource: nome, withExtension: $0) }.first
        cacheFile[nome] = u
        return u
    }
    private static func riproduci(_ url: URL, volume: Float) {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.volume = volume
        lettori.removeAll { !$0.isPlaying }
        lettori.append(p)
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))          // un «tick» dell'app non è un battito di mani
    }

    /// Tick da HUD: 8 ms di rumore filtrato (il «click» elettronico) + ping 2400→1500 Hz che muore in 45 ms.
    private static func generaTick(_ k: Int) -> Data {
        let freq = 44100.0, durata = 0.075
        let campioni = Int(freq * durata)
        var pcm = [Float](repeating: 0, count: campioni + 200)
        // ogni icona è leggermente diversa: ±4% di intonazione, deterministico per indice
        let varia = 1.0 + (Double((k * 7919) % 17) / 17.0 - 0.5) * 0.08
        var fase = 0.0
        var rumoreFiltrato = 0.0
        var seme: UInt32 = UInt32(12345 + k * 777)
        for i in 0..<campioni {
            let t = Double(i) / freq
            // ping: parte acuto e scende, decadimento esponenziale rapido
            let f = (2400.0 * varia) * pow(1500.0 / 2400.0, min(1, t / 0.04))
            fase += 2 * .pi * f / freq
            let inviluppoPing = min(1, t / 0.0015) * exp(-t / 0.016)
            let ping = sin(fase) * inviluppoPing
            // click: rumore bianco passato in un filtro passa-basso, solo nei primi 8 ms
            seme = seme &* 1664525 &+ 1013904223
            let bianco = Double(seme >> 8) / Double(1 << 24) * 2 - 1
            rumoreFiltrato = rumoreFiltrato * 0.55 + bianco * 0.45
            let inviluppoClick = t < 0.008 ? exp(-t / 0.0025) : 0
            let click = rumoreFiltrato * inviluppoClick
            pcm[i] = Float((ping * 0.55 + click * 0.5) * 0.6)
        }
        return wav(pcm, frequenza: Int(freq))
    }

    /// «Sistemi in linea»: due ping, il secondo più basso, con una coda corta.
    private static func generaInLinea() -> Data {
        let freq = 44100.0
        let note: [(Double, Double, Double)] = [(1320, 0.0, 0.12), (990, 0.11, 0.22)]   // (hz, inizio, durata)
        let campioni = Int(freq * 0.36)
        var pcm = [Float](repeating: 0, count: campioni)
        for (f, inizio, durata) in note {
            var fase = 0.0
            let da = Int(inizio * freq), n = Int(durata * freq)
            for i in 0..<n where da + i < campioni {
                let t = Double(i) / freq
                fase += 2 * .pi * f / freq
                let inv = min(1, t / 0.004) * exp(-t / (durata * 0.35))
                pcm[da + i] += Float((sin(fase) + 0.2 * sin(2 * fase)) * inv * 0.4)
            }
        }
        return wav(pcm, frequenza: Int(freq))
    }

    /// La scala di prima (pentatonica), per chi la preferisce.
    private static func generaNota(_ k: Int) -> Data {
        let gradi = [0, 2, 4, 7, 9]
        let semitoni = gradi[k % 5] + 12 * ((k / 5) % 2)
        let f = 1046.5 * pow(2, Double(semitoni) / 12)
        let freq = 44100.0, durata = 0.16
        let campioni = Int(freq * (durata + 0.02))
        var pcm = [Float](repeating: 0, count: campioni)
        var fase = 0.0
        for i in 0..<Int(freq * durata) {
            let p = Double(i) / (freq * durata)
            fase += 2 * .pi * f / freq
            let inviluppo = min(1, p * 60) * pow(1 - p, 3)
            pcm[i] = Float((sin(fase) + 0.3 * sin(2 * fase) + 0.12 * sin(3 * fase)) * inviluppo * 0.45)
        }
        return wav(pcm, frequenza: Int(freq))
    }
    private enum Tipo: CaseIterable { case tocco, ascolto, pronto, errore, avvio }
    private static var cache: [Tipo: Data] = [:]
    private static var lettori: [AVAudioPlayer] = []

    private static func suona(_ t: Tipo) {
        guard attivi else { return }
        if t == .tocco, let url = file("tick") ?? file("tocco") { riproduci(url, volume: 1.0); return }   // click su icone e SISTEMI: 100%
        let dati = cache[t] ?? genera(t)
        cache[t] = dati
        guard let p = try? AVAudioPlayer(data: dati) else { return }
        p.volume = 1.0                                               // bip generati («parli adesso», errore): Pieno+, 100%
        lettori.removeAll { !$0.isPlaying }
        lettori.append(p)
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))          // un «tick» dell'app non è un battito di mani
    }

    // MARK: Sintesi: ogni suono è una o più note con inviluppo morbido, scritte come WAV in memoria

    private struct Nota { let da: Double; let a: Double; let durata: Double; let inizio: Double; let volume: Double }

    private static func genera(_ t: Tipo) -> Data {
        let note: [Nota]
        switch t {
        case .tocco:   note = [Nota(da: 1500, a: 2100, durata: 0.05, inizio: 0, volume: 0.9)]
        case .ascolto: note = [Nota(da: 660, a: 660, durata: 0.07, inizio: 0, volume: 0.8), Nota(da: 990, a: 1100, durata: 0.10, inizio: 0.08, volume: 0.9)]
        case .pronto:  note = [Nota(da: 1100, a: 1000, durata: 0.07, inizio: 0, volume: 0.8), Nota(da: 740, a: 700, durata: 0.14, inizio: 0.08, volume: 0.7)]
        case .errore:  note = [Nota(da: 240, a: 200, durata: 0.12, inizio: 0, volume: 0.9), Nota(da: 240, a: 200, durata: 0.12, inizio: 0.16, volume: 0.9)]
        case .avvio:   note = [Nota(da: 320, a: 1500, durata: 0.55, inizio: 0, volume: 0.6), Nota(da: 1500, a: 1500, durata: 0.12, inizio: 0.58, volume: 0.5),
                               Nota(da: 2000, a: 2000, durata: 0.10, inizio: 0.74, volume: 0.45)]
        }
        let freq = 44100.0
        let fine = note.map { $0.inizio + $0.durata }.max() ?? 0.1
        let campioni = Int(freq * (fine + 0.03))
        var pcm = [Float](repeating: 0, count: campioni)
        for n in note {
            let inizio = Int(n.inizio * freq), lunghezza = Int(n.durata * freq)
            var fase = 0.0
            for k in 0..<lunghezza where inizio + k < campioni {
                let p = Double(k) / Double(lunghezza)
                let f = n.da + (n.a - n.da) * p
                fase += 2 * .pi * f / freq
                // attacco rapido, coda morbida; un filo di seconda armonica per il timbro «vetro»
                let inviluppo = min(1, p * 25) * pow(1 - p, 1.6)
                pcm[inizio + k] += Float((sin(fase) + 0.25 * sin(2 * fase)) * inviluppo * n.volume * 0.5)
            }
        }
        return wav(pcm, frequenza: Int(freq))
    }

    private static func wav(_ pcm: [Float], frequenza: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let byteDati = UInt32(pcm.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + byteDati); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(frequenza)); u32(UInt32(frequenza * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(byteDati)
        for v in pcm { u16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32767))) }
        return d
    }
}
#endif
