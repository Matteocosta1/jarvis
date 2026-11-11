import Foundation
import AVFoundation

// MARK: - 11 nov · Il dialogo vivo (analisi del dialogo, approvata dal signore: «fai le cose perfette»)
// Due pezzi piccoli che servono all'ascolto per capire quando il signore ha davvero finito di parlare:
// - VoceAttiva: il suono della sua voce nel microfono, non solo le parole trascritte (che in una sessione lunga arrivano a scatti);
// - RitmoSignore: il suo ritmo. Se riprende spesso a parlare subito dopo che JARVIS ha chiuso la frase, JARVIS impara ad aspettare
//   un po' di più; se no, torna piano piano ai tempi normali.

/// La voce nel microfono, ascoltata dal suono: ogni pezzo di audio (circa 20-40 ms) si misura e si confronta con il rumore di
/// fondo, che si adatta da solo alla stanza (scende subito nel silenzio, sale piano col rumore costante: frigo, strada, TV bassa).
/// Scritto dal thread del microfono, letto dal thread principale.
nonisolated final class VoceAttiva: @unchecked Sendable {
    static let condivisa = VoceAttiva()

    private let lock = NSLock()
    private var fondo: Float = -60          // il rumore di fondo della stanza, in decibel
    private var ultimaVoce: TimeInterval = 0
    private var pronta = false              // il fondo si è assestato (qualche pezzo di audio dopo l'azzeramento)
    private var pezzi = 0

    private static var ora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Un ascolto nuovo: il fondo si rimisura da capo (la stanza può essere cambiata).
    func azzera() {
        lock.lock()
        fondo = -60; ultimaVoce = 0; pronta = false; pezzi = 0
        lock.unlock()
    }

    /// Un pezzo di audio del microfono.
    func misura(_ b: AVAudioPCMBuffer) {
        guard let canale = b.floatChannelData?[0], b.frameLength > 0 else { return }
        let n = Int(b.frameLength)
        var somma: Float = 0
        for i in stride(from: 0, to: n, by: 2) { somma += canale[i] * canale[i] }
        let db = 20 * log10(max((somma / Float((n + 1) / 2)).squareRoot(), 0.000_01))
        let t = VoceAttiva.ora
        lock.lock()
        pezzi += 1
        if !pronta { fondo = pezzi == 1 ? db : min(fondo, db); if pezzi >= 6 { pronta = true } }
        else if db < fondo { fondo = fondo * 0.7 + db * 0.3 }            // nel silenzio il fondo scende subito
        else { fondo += (db - fondo) * 0.004 }                            // col rumore costante sale piano
        // voce: ben sopra il fondo (9 dB) e non un sussurro dell'ambiente (-50 dB)
        if pronta, db > fondo + 9, db > -50 { ultimaVoce = t }
        lock.unlock()
    }

    /// Da quanti secondi il microfono non sente la voce (grande se non l'ha mai sentita).
    var secondiDiSilenzio: Double {
        lock.lock(); defer { lock.unlock() }
        return ultimaVoce == 0 ? 999 : VoceAttiva.ora - ultimaVoce
    }
}

/// Il ritmo del signore: un moltiplicatore delle pause di fine frase, da 1 (i tempi normali) a 1,5.
/// Sale quando il signore riprende a parlare subito dopo che JARVIS ha chiuso la frase (l'«aggiunta»: era stato tagliato),
/// scende piano a ogni frase chiusa bene. Resta sul telefono.
@MainActor
final class RitmoSignore {
    static let condiviso = RitmoSignore()
    private let chiave = "ritmoSignore11nov"
    private(set) var fattore: Double

    private init() {
        let v = UserDefaults.standard.double(forKey: chiave)
        fattore = v >= 1 && v <= 1.5 ? v : 1
    }

    /// Era stato tagliato: la prossima volta un po' più di pazienza.
    func ripresa() { cambia(fattore + 0.08) }

    /// Una frase chiusa bene: si torna piano verso i tempi normali.
    func fraseChiusaBene() { cambia(fattore - 0.01) }

    private func cambia(_ v: Double) {
        fattore = min(1.5, max(1, v))
        UserDefaults.standard.set(fattore, forKey: chiave)
    }
}
