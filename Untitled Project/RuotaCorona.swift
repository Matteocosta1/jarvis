import Foundation
import SwiftUI
import Combine
import QuartzCore
import UIKit

/// MARK XI · la CLICK WHEEL della corona (mockup approvato dal signore il 3 nov).
/// Il dito sull'anello delle icone gira la corona; lasciata, gira ancora per inerzia e si ferma a scatto con un'icona esattamente
/// in alto. Ogni icona che passa in alto: lo scatto (suono «ruota» + vibrazione, uno ogni 35 ms al massimo). Mentre gira il reattore
/// si vela e al suo posto c'è l'ologramma dell'icona in alto, col nome; ferma, l'ologramma si crea sul tono «olo». Toccato, apre la
/// sezione. 5 s senza toccare niente e si spegne (deciso il 3 nov). L'icona che passa in alto, solo mentre gira, cresce come nel
/// Dock (la lente); ferma, torna normale. Niente freccina sopra l'icona scelta (tolta dal signore il 3 nov).
///
/// Il movimento lo fa un CADisplayLink a 120 Hz (ProMotion) e lo pubblica qui: lo leggono solo le icone, gli archi e l'ologramma
/// (viste piccole), non tutta la schermata di JARVIS.
final class RuotaCorona: NSObject, ObservableObject {
    /// Di quanto è girata la corona (radianti, sommati all'angolo di ogni icona).
    @Published private(set) var giro: Double = 0
    /// L'ologramma è acceso (il reattore velato).
    @Published private(set) var vivo = false
    /// L'icona in alto (indice nell'elenco della corona), −1 se nessuna.
    @Published private(set) var scelta = -1
    /// Quando l'ologramma si è creato (ferma su un'icona); nil mentre gira.
    @Published private(set) var creataDa: Date?
    /// La lente (0 → 1): solo mentre gira.
    @Published private(set) var lente: Double = 0

    static let alto = -Double.pi / 2
    static let resta: TimeInterval = 5
    private static let due = 2 * Double.pi

    private var base: [Double] = []
    private var dito: (angolo: Double, campioni: [(t: CFTimeInterval, g: Double)])?
    private var molla: (meta: Double, x0: Double, v0: Double, t0: CFTimeInterval)?
    private var spegniAlle: CFTimeInterval = 0
    private var ultimoScatto: CFTimeInterval = 0
    private var ultimoPasso: CFTimeInterval = 0
    private var collegamento: CADisplayLink?
    /// 5 nov (il signore: «più feedback aptico, più forte»): lo scatto di ogni icona è un tocco secco (rigido, 0,55), non più la
    /// «selezione» di iOS, quasi impercettibile.
    private let selezione = UIImpactFeedbackGenerator(style: .rigid)

    /// Il dito si è appena mosso sull'anello: comincia a girare (gli angoli di partenza delle icone, l'angolo del dito).
    func inizia(base: [Double], angolo: Double) {
        self.base = base
        molla = nil
        dito = (angolo: angolo, campioni: [(t: CACurrentMediaTime(), g: giro)])
        creataDa = nil
        if !vivo { vivo = true; scelta = -1 }
        Aptica.permettiColMicrofono()                       // col microfono aperto iOS spegnerebbe gli scatti
        selezione.prepare()
        aggiornaScelta(suona: false)
        spegniAlle = CACurrentMediaTime() + RuotaCorona.resta
        avvia()
    }

    /// Il dito si muove: la corona lo segue.
    func trascina(angolo: Double) {
        guard var d = dito else { return }
        var da = angolo - d.angolo
        if da > .pi { da -= RuotaCorona.due }
        if da < -.pi { da += RuotaCorona.due }
        d.angolo = angolo
        giro += da
        let ora = CACurrentMediaTime()
        d.campioni.append((t: ora, g: giro))
        while d.campioni.count > 2, ora - d.campioni[0].t > 0.09 { d.campioni.removeFirst() }
        dito = d
        spegniAlle = ora + RuotaCorona.resta
        aggiornaScelta(suona: true)
    }

    /// Il dito si alza: la corona continua con lo slancio (0,325 s, come lo scorrimento di iOS) e si ferma su un'icona in alto,
    /// con una molla smorzata al punto critico (ω = 11).
    func lascia() {
        guard let d = dito else { return }
        dito = nil
        let ora = CACurrentMediaTime()
        let a: (t: CFTimeInterval, g: Double) = d.campioni.first ?? (t: ora, g: giro)
        let b: (t: CFTimeInterval, g: Double) = d.campioni.last ?? (t: ora, g: giro)
        var v = ora - b.t > 0.06 ? 0 : (b.g - a.g) / max(0.016, b.t - a.t)
        v = max(-14, min(14, v))
        let proiezione = giro + v * 0.325
        var meta = proiezione, minimo = Double.infinity
        for x in base {
            let primo = RuotaCorona.alto - x
            let g = primo + (((proiezione - primo) / RuotaCorona.due).rounded()) * RuotaCorona.due
            if abs(g - proiezione) < minimo { minimo = abs(g - proiezione); meta = g }
        }
        molla = (meta: meta, x0: giro - meta, v0: v, t0: ora)
        avvia()
    }

    /// Spegne l'ologramma (toccato, o una sezione si apre).
    func spegni() {
        vivo = false
        creataDa = nil
        scelta = -1
        dito = nil
        molla = nil
    }

    /// La corona torna com'era (all'avvio o dopo una nuova conversazione): nessun giro.
    func azzera() {
        spegni()
        giro = 0
        lente = 0
        ferma()
    }

    private func aggiornaScelta(suona: Bool) {
        guard vivo, !base.isEmpty else { return }
        var k0 = 0, m = Double.infinity
        for (k, x) in base.enumerated() {
            var d = abs(RuotaCorona.normale(x + giro - RuotaCorona.alto))
            d = min(d, RuotaCorona.due - d)
            if d < m { m = d; k0 = k }
        }
        guard k0 != scelta else { return }
        scelta = k0
        creataDa = nil
        if suona { scatto() }
    }

    private func scatto() {
        let ora = CACurrentMediaTime()
        guard ora - ultimoScatto >= 0.035 else { return }
        ultimoScatto = ora
        Suoni.scattoRuota()
        selezione.impactOccurred(intensity: 0.55)
        selezione.prepare()
    }

    private static func normale(_ a: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: due)
        return r < 0 ? r + due : r
    }

    private func avvia() {
        guard collegamento == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(passo(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        collegamento = l
        ultimoPasso = 0
    }

    private func ferma() {
        collegamento?.invalidate()
        collegamento = nil
    }

    @objc private func passo(_ l: CADisplayLink) {
        let ora = CACurrentMediaTime()
        let dt = ultimoPasso == 0 ? 1.0 / 120 : min(0.05, ora - ultimoPasso)
        ultimoPasso = ora
        if let m = molla {
            let w = 11.0, s = ora - m.t0, e = exp(-w * s)
            let x = (m.x0 + (m.v0 + w * m.x0) * s) * e
            if abs(x) < 0.0008 && s > 0.15 {
                giro = m.meta
                molla = nil
            } else {
                giro = m.meta + x
            }
            spegniAlle = ora + RuotaCorona.resta
            aggiornaScelta(suona: true)
            if vivo, abs(x) < 0.04, s > 0.05 { crea() }        // v266: appena arriva sull'icona (era 0,012: aspettava la molla quasi ferma)
        }
        if vivo, dito == nil, molla == nil { crea() }
        if vivo, dito == nil, molla == nil, ora > spegniAlle { spegni() }
        // la lente si accende e si spegne morbida (45 ms), uguale a 60 e a 120 Hz
        let girando = vivo && (dito != nil || (molla != nil && creataDa == nil))
        let obiettivo: Double = girando ? 1 : 0
        if abs(lente - obiettivo) > 0.002 {
            lente += (obiettivo - lente) * (1 - exp(-dt / 0.045))
        } else if lente != obiettivo {
            lente = obiettivo
        }
        if !vivo && dito == nil && molla == nil && lente == 0 { ferma() }
    }

    /// Ferma su un'icona: l'ologramma si crea (una volta sola per icona), sul tono «olo».
    private func crea() {
        guard creataDa == nil, scelta >= 0 else { return }
        creataDa = Date()
        Suoni.tonoOlo()
    }

    /// L'icona `k` è in alto con l'ologramma acceso (per l'anello di selezione).
    /// v266 (il signore: «quando ruoti devono essere tutte alla stessa bassa luminosità, diventano luminose quando le scegli»):
    /// l'anello si accende solo quando l'ologramma è nato, non mentre gira.
    func selezionata(_ k: Int) -> Bool { vivo && scelta == k && creataDa != nil }

    /// La lente sull'icona di angolo `x`: cresce fino a 1,5 in alto (a metà fra due, 1,25 tutte e due).
    func scala(base x: Double, passo: Double) -> CGFloat {
        guard lente > 0.001 else { return 1 }
        var d = abs(RuotaCorona.normale(x + giro - RuotaCorona.alto))
        d = min(d, RuotaCorona.due - d)
        return CGFloat(1 + 0.5 * lente * exp(-pow(d / (passo * 0.6), 2)))
    }
}
