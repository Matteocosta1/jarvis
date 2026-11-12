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
    private var sommaForza: Float = 0       // 12 nov (A3): quanto la voce sta sopra il fondo, sommato sui pezzi di voce
    private var pezziVoce = 0

    private static var ora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Un ascolto nuovo: il fondo si rimisura da capo (la stanza può essere cambiata).
    func azzera() {
        lock.lock()
        fondo = -60; ultimaVoce = 0; pronta = false; pezzi = 0; sommaForza = 0; pezziVoce = 0
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
        if pronta, db > fondo + 9, db > -50 { ultimaVoce = t; sommaForza += db - fondo; pezziVoce += 1 }
        lock.unlock()
    }

    /// 12 nov (A3): di quanti decibel, in media, la voce di questo ascolto stava sopra il rumore della stanza (nil: troppo poca voce).
    var forzaMedia: Double? {
        lock.lock(); defer { lock.unlock() }
        return pezziVoce >= 15 ? Double(sommaForza / Float(pezziVoce)) : nil
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

/// 12 nov (A3, piano del dialogo approvato dal signore): come parla il signore in questa frase, rispetto al suo solito.
/// Velocità (parole al secondo), forza della voce sopra il fondo della stanza ed esitazioni (parole ripetute, «ehm», «cioè»).
/// Il suo solito si impara qui, sul telefono, frase dopo frase; finché non conosce il suo solito (8 frasi) dice solo le esitazioni.
/// La riga va al cervello («[Come parla: …]») per scegliere il registro: più calmo se è agitato, più leggero se è allegro.
@MainActor
final class ComeParla {
    static let condiviso = ComeParla()
    private let chiave = "comeParla12nov"
    private var velocita: Double
    private var forza: Double
    private var campioni: Int

    private init() {
        let d = UserDefaults.standard.dictionary(forKey: chiave) ?? [:]
        velocita = d["velocita"] as? Double ?? 0
        forza = d["forza"] as? Double ?? 0
        campioni = d["campioni"] as? Int ?? 0
    }

    /// Parole ripetute di seguito («delle delle») e intercalari di chi sta pensando.
    nonisolated static func esitazioni(_ testo: String) -> Int {
        let p = testo.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        guard p.count >= 2 else { return 0 }
        let intercalari: Set<String> = ["ehm", "eh", "mmm", "mh", "uhm", "cioè", "tipo", "praticamente", "insomma", "boh"]
        var n = p.filter { intercalari.contains($0) }.count
        for k in 1..<p.count where p[k] == p[k - 1] && p[k].count > 1 { n += 1 }
        return n
    }

    /// La riga per il cervello (nil: niente di notevole).
    func riga(testo: String, secondi: Double, forzaDb: Double?) -> String? {
        let parole = testo.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
        var note: [String] = []
        if campioni >= 8 {
            if parole >= 5, secondi > 1 {
                let v = Double(parole) / secondi
                if v > velocita * 1.25 { note.append("più veloce del solito") } else if v < velocita * 0.75 { note.append("più lento del solito") }
            }
            if let f = forzaDb {
                if f > forza + 5 { note.append("voce più forte del solito") } else if f < forza - 5 { note.append("voce più bassa del solito") }
            }
        }
        if ComeParla.esitazioni(testo) >= 2 { note.append("esita (ripete parole, «ehm», «cioè»)") }
        return note.isEmpty ? nil : note.joined(separator: ", ")
    }

    /// Una frase finita: il suo solito si aggiorna piano (media mobile).
    func impara(testo: String, secondi: Double, forzaDb: Double?) {
        let parole = testo.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
        guard parole >= 5, secondi > 1 else { return }
        let v = Double(parole) / secondi
        guard v > 0.5, v < 7 else { return }
        let peso = campioni < 8 ? 1 / Double(campioni + 1) : 0.1
        velocita += (v - velocita) * peso
        if let f = forzaDb { forza = forza == 0 ? f : forza + (f - forza) * peso }
        campioni += 1
        UserDefaults.standard.set(["velocita": velocita, "forza": forza, "campioni": campioni] as [String: Any], forKey: chiave)
    }
}
