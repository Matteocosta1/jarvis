#if os(iOS)
import AVFoundation
import UIKit

/// I suoni dell'interfaccia, alla Stark. Se nel progetto c'è un file audio con il nome giusto, si usa quello;
/// altrimenti l'app genera un piccolo segnale sintetico. File riconosciuti (m4a, mp3, wav o caf):
///   «tick» (o «tocco») → tocco su un'icona      «avvio» → suono di fondo mentre le icone si accendono
///   «plim» → accensione di ogni singola icona (se manca, silenzio)      «inlinea» → fine sequenza
///   «scheda» → una sezione si apre (caricamento)      «schedapronta» → la sezione è pronta
/// Si spengono con «Suoni dell'interfaccia» nelle impostazioni.
@MainActor
enum Suoni {
    static var attivi: Bool { UserDefaults.standard.object(forKey: "suoni") as? Bool ?? true }

    /// Tocco su un'icona o sul reattore.
    static func tocco() { suona(.tocco) }
    /// JARVIS inizia ad ascoltare.
    static func ascolto() { suona(.ascolto) }
    /// JARVIS ha finito e torna in attesa.
    /// File: «pronto» (conferma); se manca, il bip generato.
    static func pronto() {
        if attivi, let url = file("pronto") { riproduci(url, volume: 0.6); return }
        suona(.pronto)
    }
    /// Qualcosa non è andato.
    static func errore() { suona(.errore) }
    /// Sistemi in linea, all'apertura.
    static func avvio() { suona(.avvio) }

    /// Una sezione si apre (parte il caricamento HUD). File: «scheda». Se manca, il suono dell'ascolto.
    static func schedaApre() {
        guard attivi else { return }
        guard let url = file("scheda"), let p = try? AVAudioPlayer(contentsOf: url) else { suona(.ascolto); return }
        p.volume = 0.7                                               // schede: 70%
        lettoreScheda?.stop()
        lettoreScheda = p
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))          // un «tick» dell'app non è un battito di mani
    }
    /// La sezione ha i dati e si stampa sullo schermo. File: «schedapronta». Se manca, il suono di «pronto».
    /// Il suono del caricamento sfuma in quel momento, così i due non si accavallano.
    static func schedaPronta() {
        guard attivi else { return }
        if let p = lettoreScheda, p.isPlaying { p.setVolume(0, fadeDuration: 0.18) }
        if let url = file("schedapronta") { riproduci(url, volume: 0.7); return }
        suona(.pronto)
    }
    private static var lettoreScheda: AVAudioPlayer?
    /// L'apertura delle sezioni dal vivo e personali: Bea, Spesa, Occhi, Allenatore, Profiler. File: «apertura»;
    /// se manca, il suono delle schede. Usa lo stesso lettore delle schede, così «schedaPronta» lo sfuma.
    static func apertura() {
        guard attivi else { return }
        guard let url = file("apertura"), let p = try? AVAudioPlayer(contentsOf: url) else { schedaApre(); return }
        p.volume = 0.7                                               // come le schede: 70%
        lettoreScheda?.stop()
        lettoreScheda = p
        p.play()
        BattitoMani.ignora(per: max(0.5, p.duration + 0.2))
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
        riproduci(url, volume: 0.7)
    }
    /// Click delle tre icone in alto (SISTEMI, cestino, impostazioni). File: «clicktesta»; se manca, il tick normale.
    static func clickTesta() {
        guard attivi else { return }
        if let url = file("clicktesta") { riproduci(url, volume: 0.5); return }
        tocco()
    }
    /// Il tick di un'icona che si accende all'avvio: un segnale digitale da HUD, non una nota.
    /// Un impulso di rumore elettronico brevissimo più un «ping» che scende di tono in 40 ms, con una minima
    /// variazione da un'icona all'altra. Stile: «hud» (predefinito), «note» (la scala di prima) o «off».
    static func plim(_ indice: Int) {
        guard attivi else { return }
        if indice == 0, let url = file("avvio") { riproduci(url, volume: 0.8) }   // musica d'avvio: 80%
        if let url = file("plim") { riproduci(url, volume: 0.6); return }   // pim delle icone: 60%
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
        if let url = file("inlinea") { riproduci(url, volume: 0.6); return }   // chiude l'avvio insieme ai pim: 60%
        guard (UserDefaults.standard.string(forKey: "suonoAvvio") ?? "off") != "off" else { return }
        let dati = cachePlim["inlinea"] ?? generaInLinea()
        cachePlim["inlinea"] = dati
        guard let p = try? AVAudioPlayer(data: dati) else { return }
        p.volume = 0.6
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
        if t == .tocco, let url = file("tick") ?? file("tocco") { riproduci(url, volume: 0.5); return }   // click su icone e SISTEMI: 50%
        let dati = cache[t] ?? genera(t)
        cache[t] = dati
        guard let p = try? AVAudioPlayer(data: dati) else { return }
        p.volume = t == .avvio ? 0.35 : 0.28
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
