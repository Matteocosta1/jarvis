#if os(iOS)
import AVFoundation
import Accelerate

// La voce-impronta del signore: una piccola rete neurale (GE2E, Resemblyzer, licenza Apache 2.0) che riassume
// un pezzo di parlato in 256 numeri. La stessa persona dà impronte vicine, persone diverse impronte lontane.
// Tutto gira sull'iPhone: i pesi stanno in VoceModello.bin, l'impronta del signore resta nelle impostazioni del telefono.
// Si usa solo quando intorno c'è confusione (AmbienteSonoro): nella calma JARVIS risponde e basta.

/// Il modello: spettrogramma mel (40 bande, 25 ms ogni 10 ms, 16 kHz) → LSTM a 3 strati → 256 numeri normalizzati.
nonisolated final class ModelloVoce: @unchecked Sendable {
    static let condiviso = ModelloVoce()

    private static let nFFT = 400, hop = 160, nMel = 40, bins = 201, nascosto = 256, porte = 1024, finestra = 160
    private var mel: [Float] = []                          // 40 × 201
    private var wi: [[Float]] = [], wh: [[Float]] = [], b: [[Float]] = []
    private var linW: [Float] = [], linB: [Float] = []
    private var cosT: [Float] = [], sinT: [Float] = []     // 400 × 201: la trasformata di Fourier fatta a matrice
    private var hann: [Float] = []
    private(set) var pronto = false

    private init() { carica() }

    private func carica() {
        guard let url = Bundle.main.url(forResource: "VoceModello", withExtension: "bin"),
              let dati = try? Data(contentsOf: url), dati.count > 4, dati.prefix(4) == Data("JVX1".utf8) else { return }
        let quanti = (dati.count - 4) / 4
        var tutti = [Float](repeating: 0, count: quanti)
        _ = tutti.withUnsafeMutableBytes { dati.copyBytes(to: $0, from: 4..<(4 + quanti * 4)) }
        var i = 0
        func prendi(_ n: Int) -> [Float] { defer { i += n }; return Array(tutti[i..<(i + n)]) }
        mel = prendi(Self.nMel * Self.bins)
        for l in 0..<3 {
            let ingresso = l == 0 ? Self.nMel : Self.nascosto
            wi.append(prendi(Self.porte * ingresso))
            wh.append(prendi(Self.porte * Self.nascosto))
            b.append(prendi(Self.porte))
        }
        linW = prendi(Self.nascosto * Self.nascosto)
        linB = prendi(Self.nascosto)
        guard i == tutti.count else { return }
        // finestra di Hann periodica e tabelle seno/coseno
        hann = (0..<Self.nFFT).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(Self.nFFT)) }
        cosT = [Float](repeating: 0, count: Self.nFFT * Self.bins)
        sinT = cosT
        for n in 0..<Self.nFFT {
            for k in 0..<Self.bins {
                let a = 2 * Double.pi * Double(k * n) / Double(Self.nFFT)
                cosT[n * Self.bins + k] = Float(cos(a))
                sinT[n * Self.bins + k] = Float(-sin(a))
            }
        }
        pronto = true
    }

    /// Spettrogramma mel (frame × 40) di un segnale a 16 kHz, come librosa (center=True, reflect, potenza 2).
    private func spettrogramma(_ x: [Float]) -> [Float] {
        let p = Self.nFFT / 2
        guard x.count > p + 1 else { return [] }
        var y = [Float](repeating: 0, count: x.count + 2 * p)
        for k in 0..<p { y[p - 1 - k] = x[k + 1]; y[p + x.count + k] = x[x.count - 2 - k] }
        for k in 0..<x.count { y[p + k] = x[k] }
        let n = 1 + (y.count - Self.nFFT) / Self.hop
        var frame = [Float](repeating: 0, count: n * Self.nFFT)
        for t in 0..<n {
            for k in 0..<Self.nFFT { frame[t * Self.nFFT + k] = y[t * Self.hop + k] * hann[k] }
        }
        var re = [Float](repeating: 0, count: n * Self.bins), im = re
        vDSP_mmul(frame, 1, cosT, 1, &re, 1, vDSP_Length(n), vDSP_Length(Self.bins), vDSP_Length(Self.nFFT))
        vDSP_mmul(frame, 1, sinT, 1, &im, 1, vDSP_Length(n), vDSP_Length(Self.bins), vDSP_Length(Self.nFFT))
        var potenza = [Float](repeating: 0, count: n * Self.bins)
        vDSP_vmma(re, 1, re, 1, im, 1, im, 1, &potenza, 1, vDSP_Length(n * Self.bins))
        // (n × 201) · (201 × 40): la matrice mel è salvata 40 × 201, la trasposta si fa qui una volta
        var melT = [Float](repeating: 0, count: Self.bins * Self.nMel)
        vDSP_mtrans(mel, 1, &melT, 1, vDSP_Length(Self.bins), vDSP_Length(Self.nMel))
        var out = [Float](repeating: 0, count: n * Self.nMel)
        vDSP_mmul(potenza, 1, melT, 1, &out, 1, vDSP_Length(n), vDSP_Length(Self.nMel), vDSP_Length(Self.bins))
        return out
    }

    private static func sigmoide(_ v: Float) -> Float { 1 / (1 + exp(-v)) }

    /// L'impronta di una finestra di 160 frame (1,6 s).
    private func parziale(_ m: ArraySlice<Float>) -> [Float] {
        var ingresso = Array(m)
        var larghezza = Self.nMel
        var h = [Float](repeating: 0, count: Self.nascosto)
        for l in 0..<3 {
            h = [Float](repeating: 0, count: Self.nascosto)
            var c = h
            var uscite = [Float](repeating: 0, count: Self.finestra * Self.nascosto)
            var g = [Float](repeating: 0, count: Self.porte), gh = g
            for t in 0..<Self.finestra {
                let xt = Array(ingresso[(t * larghezza)..<((t + 1) * larghezza)])
                vDSP_mmul(wi[l], 1, xt, 1, &g, 1, vDSP_Length(Self.porte), 1, vDSP_Length(larghezza))
                vDSP_mmul(wh[l], 1, h, 1, &gh, 1, vDSP_Length(Self.porte), 1, vDSP_Length(Self.nascosto))
                for k in 0..<Self.nascosto {
                    let ig = Self.sigmoide(g[k] + gh[k] + b[l][k])
                    let fg = Self.sigmoide(g[256 + k] + gh[256 + k] + b[l][256 + k])
                    let cg = tanh(g[512 + k] + gh[512 + k] + b[l][512 + k])
                    let og = Self.sigmoide(g[768 + k] + gh[768 + k] + b[l][768 + k])
                    c[k] = fg * c[k] + ig * cg
                    h[k] = og * tanh(c[k])
                    uscite[t * Self.nascosto + k] = h[k]
                }
            }
            ingresso = uscite
            larghezza = Self.nascosto
        }
        var e = [Float](repeating: 0, count: Self.nascosto)
        vDSP_mmul(linW, 1, h, 1, &e, 1, vDSP_Length(Self.nascosto), 1, vDSP_Length(Self.nascosto))
        for k in 0..<Self.nascosto { e[k] = max(0, e[k] + linB[k]) }
        return ModelloVoce.normalizza(e)
    }

    static func normalizza(_ v: [Float]) -> [Float] {
        var n: Float = 0
        vDSP_svesq(v, 1, &n, vDSP_Length(v.count))
        let r = sqrt(n)
        return r > 0 ? v.map { $0 / r } : v
    }

    static func somiglianza(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var d: Float = 0
        vDSP_dotpr(a, 1, b, 1, &d, vDSP_Length(a.count))
        return d
    }

    /// L'impronta di un pezzo di parlato a 16 kHz (almeno ~0,7 s). Nil se il modello non c'è o il pezzo è troppo corto.
    func impronta(_ campioni16k: [Float]) -> [Float]? {
        guard pronto, campioni16k.count >= 11_200 else { return nil }
        // volume portato a -30 dBFS (solo in su), come nell'addestramento
        var rms: Float = 0
        vDSP_rmsqv(campioni16k, 1, &rms, vDSP_Length(campioni16k.count))
        var x = campioni16k
        let obiettivo = pow(10, Float(-30) / 20)
        if rms > 0, rms < obiettivo { let k = obiettivo / rms; x = x.map { max(-1, min(1, $0 * k)) } }
        var m = spettrogramma(x)
        var frames = m.count / Self.nMel
        if frames < Self.finestra {
            m += [Float](repeating: 0, count: (Self.finestra - frames) * Self.nMel)
            frames = Self.finestra
        }
        var somma = [Float](repeating: 0, count: Self.nascosto)
        var quante = 0
        var inizio = 0
        while inizio + Self.finestra <= frames {
            let e = parziale(m[(inizio * Self.nMel)..<((inizio + Self.finestra) * Self.nMel)])
            vDSP_vadd(somma, 1, e, 1, &somma, 1, vDSP_Length(Self.nascosto))
            quante += 1
            inizio += 80
        }
        guard quante > 0 else { return nil }
        return ModelloVoce.normalizza(somma)
    }
}

/// Gli ultimi secondi di microfono, sempre pronti: il tap ci scrive dentro, il controllo della voce legge da qui.
nonisolated final class RegistroMicrofono: @unchecked Sendable {
    static let condiviso = RegistroMicrofono()
    private let lock = NSLock()
    private var campioni: [Float] = []
    private var frequenza: Double = 48_000
    private let secondi: Double = 8

    func scrivi(_ buffer: AVAudioPCMBuffer) {
        guard let canale = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        lock.lock()
        frequenza = buffer.format.sampleRate
        campioni.append(contentsOf: UnsafeBufferPointer(start: canale, count: n))
        let massimo = Int(frequenza * secondi)
        if campioni.count > massimo + Int(frequenza) { campioni.removeFirst(campioni.count - massimo) }   // si accorcia una volta al secondo
        lock.unlock()
    }

    func svuota() { lock.lock(); campioni.removeAll(); lock.unlock() }

    /// Gli ultimi `durata` secondi, portati a 16 kHz.
    func ultimi(_ durata: Double) -> [Float] {
        lock.lock()
        let fr = frequenza
        let n = min(campioni.count, Int(fr * durata))
        let pezzo = Array(campioni.suffix(n))
        lock.unlock()
        return RegistroMicrofono.a16k(pezzo, da: fr)
    }

    /// Ricampionamento semplice a 16 kHz: media sui campioni di ogni intervallo (filtro passa-basso grezzo) e scelta.
    static func a16k(_ x: [Float], da fr: Double) -> [Float] {
        guard fr > 16_000, !x.isEmpty else { return x }
        let passo = fr / 16_000
        let n = Int(Double(x.count) / passo)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a = Int(Double(i) * passo), z = min(x.count, Int(Double(i + 1) * passo))
            var s: Float = 0
            for k in a..<max(a + 1, z) where k < x.count { s += x[k] }
            out[i] = s / Float(max(1, z - a))
        }
        return out
    }
}

/// Riconosce il signore dalla voce, solo quando serve (in mezzo alla confusione), con la «fiducia di conversazione»:
/// riconosciuto una volta, le battute successive della stessa conversazione (anche un «sì») passano senza ricontrollo.
@MainActor
enum VoceDelSignore {
    private static let chiave = "improntaVoce"
    private static var fiduciaFino = Date.distantPast

    static var registrata: Bool { impronta != nil }
    static var attiva: Bool { registrata && (UserDefaults.standard.object(forKey: "riconosciVoce") as? Bool ?? true) }
    /// Quanto deve somigliare per essere lui (0,60 largo … 0,85 severo).
    static var soglia: Float { Float(UserDefaults.standard.object(forKey: "sogliaVoce") as? Double ?? 0.80) }

    static var impronta: [Float]? {
        get { (UserDefaults.standard.array(forKey: chiave) as? [NSNumber])?.map { $0.floatValue } }
        set { UserDefaults.standard.set(newValue?.map { NSNumber(value: $0) }, forKey: chiave) }
    }

    static var inFiducia: Bool { Date() < fiduciaFino }
    /// Il signore ha appena parlato con JARVIS: la conversazione è sua per i prossimi 45 secondi.
    static func rinnovaFiducia() { fiduciaFino = Date().addingTimeInterval(45) }

    /// È lui? Usa gli ultimi `secondi` di microfono. Nil se non si può dire (niente impronta, pezzo troppo corto).
    static func eLui(ultimi secondi: Double = 1.6) async -> Bool? {
        guard let mia = impronta else { return nil }
        let pezzo = RegistroMicrofono.condiviso.ultimi(secondi)
        let soglia = self.soglia
        let e = await Task.detached(priority: .userInitiated) { ModelloVoce.condiviso.impronta(pezzo) }.value
        guard let e else { return nil }
        let ok = ModelloVoce.somiglianza(e, mia) >= soglia
        if ok { rinnovaFiducia() }
        return ok
    }
}
#endif
