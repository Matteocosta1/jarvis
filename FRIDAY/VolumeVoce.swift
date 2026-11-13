import Foundation
import AVFoundation

/// Il volume della voce, da 0 a 1: il microfono quando JARVIS ascolta, la voce di JARVIS quando parla.
/// Lo scrive chi sente l'audio (anche dal thread del microfono); il reattore lo legge a ogni fotogramma
/// e si gonfia di conseguenza: più forte si parla, più si espande.
nonisolated final class Volume: @unchecked Sendable {
    static let voce = Volume()

    private let lock = NSLock()
    private var grezzo = 0.0
    private var quando = Date.distantPast
    private var liscio = 0.0

    /// Un nuovo valore da 0 a 1.
    func metti(_ v: Double) {
        let v = min(max(v, 0), 1)
        lock.lock()
        grezzo = Date().timeIntervalSince(quando) < 0.35 ? grezzo * 0.5 + v * 0.5 : v   // media con il pezzo prima
        quando = Date()
        lock.unlock()
    }

    /// Un valore in decibel (come quelli di AVAudioPlayer e AVAudioRecorder).
    func mettiDecibel(_ db: Float) { metti(Volume.normalizza(Double(db))) }

    /// Misura un pezzo di audio del microfono.
    func misura(_ b: AVAudioPCMBuffer) {
        guard let canale = b.floatChannelData?[0], b.frameLength > 0 else { return }
        let n = Int(b.frameLength)
        var somma: Float = 0
        for i in stride(from: 0, to: n, by: 2) { somma += canale[i] * canale[i] }
        let rms = (somma / Float((n + 1) / 2)).squareRoot()
        metti(Volume.normalizza(Double(20 * log10(max(rms, 0.000_01)))))
    }

    /// Letto dal reattore a ogni fotogramma. Due valori:
    /// - `voce`: segue la voce sillaba per sillaba, con una molla (fluida, con un filo di rimbalzo, come un muscolo);
    /// - `energia`: la media dell'ultimo secondo, lenta: fa crescere la sfera mentre il discorso prende forza.
    /// Il passo dipende dal tempo trascorso, così è uguale a 30 e a 120 fotogrammi al secondo.
    private var ultimaLettura = Date()
    private var spinta = 0.0
    private var energia = 0.0
    func leggi() -> (voce: Double, energia: Double) {
        lock.lock(); defer { lock.unlock() }
        let ora = Date()
        let dt = min(max(ora.timeIntervalSince(ultimaLettura), 0), 0.1)
        ultimaLettura = ora
        let obiettivo = ora.timeIntervalSince(quando) < 0.35 ? grezzo : 0
        let omega = 16.0, smorzo = 0.6
        let passi = 4
        let h = dt / Double(passi)
        for _ in 0..<passi {
            let acc = omega * omega * (obiettivo - liscio) - 2 * smorzo * omega * spinta
            spinta += acc * h
            liscio += spinta * h
        }
        liscio = min(max(liscio, 0), 1.2)
        energia += (liscio - energia) * (1 - exp(-dt / 0.7))
        return (liscio, energia)
    }

    /// -50 dB è silenzio, -12 dB è una voce forte.
    static func normalizza(_ db: Double) -> Double { min(max((db + 50) / 38, 0), 1) }

    /// Segue il volume di una frase di JARVIS finché suona.
    @MainActor static func segui(_ p: AVAudioPlayer) {
        p.isMeteringEnabled = true
        Task { @MainActor [weak p] in
            var suonato = false
            for _ in 0..<4000 {
                guard let p else { break }
                if p.isPlaying {
                    suonato = true
                    p.updateMeters()
                    Volume.voce.mettiDecibel(p.averagePower(forChannel: 0))
                } else if suonato { break }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }
}

/// Il «tempo di rotazione» del reattore: avanza alla velocità della fase e, quando la fase cambia,
/// la velocità sale o scende in modo morbido invece di saltare (niente scatti tra ascolto, pensiero e voce).
nonisolated final class Giri: @unchecked Sendable {
    static let reattore = Giri()
    private let lock = NSLock()
    private var posizione = 0.0
    private var velocita = 0.35
    private var ultimo = Date()

    func avanza(_ obiettivo: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        let ora = Date()
        let dt = min(max(ora.timeIntervalSince(ultimo), 0), 0.1)
        ultimo = ora
        velocita += (obiettivo - velocita) * (1 - exp(-dt / 0.6))
        posizione += velocita * dt
        return posizione
    }
}
