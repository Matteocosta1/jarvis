import Foundation
import SwiftUI
import Combine
import WatchKit

/// MARK XI · la barra delle icone al polso (mockup approvato dal signore il 3 nov: «le icone col dito, le sezioni con la corona»).
/// Il dito trascina la barra; lasciata, va con lo slancio all'icona più vicina al centro, con una molla smorzata al punto critico.
/// Mentre si muove, l'icona al centro si vede in ologramma nel reattore (uno scatto per icona: suono «ruota» e vibrazione); ferma,
/// l'ologramma si crea sul tono «olo». Toccato, apre la sezione; 5 s senza toccare niente e si spegne. Un tocco su un'icona la apre
/// come sempre.
/// 5 nov (il signore: «la corona non deve comandare le icone, avevo sbagliato io»): la corona non muove più la barra (tolta
/// `CoronaBarra` del 4 nov): le icone solo col dito, la corona resta della pagina.
/// 5 nov (il signore: «se ruoto a destra o sinistra scorrono velocissime e non si fermano più finché non si chiude l'app»): la
/// molla adesso è risolta esatta, stabile con qualunque fotogramma (prima, coi fotogrammi lenti del polso, divergeva).
/// La barra a riposo è quella di sempre (dalla prima icona); all'avvio la portano `inFondo()` e `scorriA(_:durata:)`.
final class RuotaPolso: ObservableObject {
    /// Lo spostamento della barra (punti, negativo verso sinistra).
    @Published private(set) var spostamento: CGFloat = 0
    /// L'animazione dell'ultimo spostamento (avvio: easeOut; col dito: nessuna).
    @Published private(set) var animazione: Animation?
    @Published private(set) var vivo = false
    @Published private(set) var scelta = -1
    @Published private(set) var creataDa: Date?
    /// La lente: 0 → 1, solo mentre si muove.
    @Published private(set) var lente: Double = 0

    /// Il centro di ogni icona dal bordo sinistro della barra (con lo spazio iniziale di 2 punti), e la larghezza visibile.
    var centri: [CGFloat] = []
    var larghezza: CGFloat = 184
    var larghezzaTotale: CGFloat = 0

    static let resta: TimeInterval = 5
    private var p: Double = 0                      // la posizione in icone (0 = la prima al centro)
    private var velocita: Double = 0
    private var meta: Double?
    private var dito: (x: CGFloat, campioni: [(t: TimeInterval, p: Double)])?
    private var spegniAlle = Date.distantPast
    private var ultimoScatto = Date.distantPast
    private var giro: Task<Void, Never>?

    // MARK: l'avvio (come prima: la barra parte dall'ultima icona e torna alla prima)

    func inFondo() {
        animazione = nil
        spostamento = min(0, larghezza - larghezzaTotale)
    }

    /// Porta l'icona `k` sul bordo sinistro (come lo scrollTo con anchor .leading di prima).
    func scorriA(_ k: Int, durata: Double) {
        guard centri.indices.contains(k) else { return }
        animazione = .easeOut(duration: durata)
        spostamento = sinistra(k)
    }

    /// Lo spostamento che mette l'icona `k` sul bordo sinistro (senza andare oltre la fine della barra).
    private func sinistra(_ k: Int) -> CGFloat {
        max(min(0, larghezza - larghezzaTotale), min(0, -(centri[k] - 17 - 2)))
    }

    // MARK: il dito

    /// Il centro della posizione `q` (fra due icone, in proporzione; oltre la prima e l'ultima, 40 punti per icona).
    private func xDi(_ q: Double) -> CGFloat {
        guard let primo = centri.first, let ultimo = centri.last else { return 0 }
        let n = Double(centri.count - 1)
        if q <= 0 { return primo + CGFloat(q) * 40 }
        if q >= n { return ultimo + CGFloat(q - n) * 40 }
        let i = Int(q.rounded(.down)), f = CGFloat(q - Double(i))
        return centri[i] + (centri[i + 1] - centri[i]) * f
    }

    /// La posizione in icone che corrisponde allo spostamento di adesso (l'icona sotto il centro).
    private func pDi(_ s: CGFloat) -> Double {
        let x = larghezza / 2 - s
        guard let primo = centri.first, let ultimo = centri.last, centri.count > 1 else { return 0 }
        if x <= primo { return Double((x - primo) / max(1, centri[1] - primo)) }
        if x >= ultimo { return Double(centri.count - 1) + Double((x - ultimo) / max(1, ultimo - centri[centri.count - 2])) }
        for i in 0..<(centri.count - 1) where x <= centri[i + 1] {
            return Double(i) + Double((x - centri[i]) / max(1, centri[i + 1] - centri[i]))
        }
        return Double(centri.count - 1)
    }

    /// La barra dove dice la posizione (si pubblica solo ciò che cambia: ogni pubblicazione ridisegna barra, icone e ologramma).
    private func posa() {
        if animazione != nil { animazione = nil }
        let s = larghezza / 2 - xDi(p)
        if s != spostamento { spostamento = s }
    }

    func trascina(_ x: CGFloat) {
        let ora = Date().timeIntervalSinceReferenceDate
        if dito == nil {
            p = pDi(spostamento)
            meta = nil
            velocita = 0
            dito = (x: x, campioni: [(t: ora, p: p)])
            accendi()
            return
        }
        guard var d = dito else { return }
        let passo: CGFloat = 40                                       // un'icona e il suo spazio
        p = max(-0.35, min(Double(centri.count) - 0.65, p - Double((x - d.x) / passo)))
        d.x = x
        d.campioni.append((t: ora, p: p))
        while d.campioni.count > 2, ora - d.campioni[0].t > 0.09 { d.campioni.removeFirst() }
        dito = d
        posa()
        aggiorna(suona: true)
        spegniAlle = Date().addingTimeInterval(RuotaPolso.resta)
    }

    func lascia() {
        guard let d = dito else { return }
        dito = nil
        let ora = Date().timeIntervalSinceReferenceDate
        let a: (t: TimeInterval, p: Double) = d.campioni.first ?? (t: ora, p: p)
        let b: (t: TimeInterval, p: Double) = d.campioni.last ?? (t: ora, p: p)
        velocita = ora - b.t > 0.06 ? 0 : (b.p - a.p) / max(0.016, b.t - a.t)
        meta = max(0, min(Double(centri.count - 1), (p + velocita * 0.25).rounded()))
        avvia()
    }

    private func accendi() {
        if !vivo { vivo = true; scelta = -1 }
        creataDa = nil
        spegniAlle = Date().addingTimeInterval(RuotaPolso.resta)
        aggiorna(suona: false)
        avvia()
    }

    func spegni() {
        vivo = false
        scelta = -1
        creataDa = nil
        dito = nil
        meta = nil
    }

    private func aggiorna(suona: Bool) {
        guard vivo, !centri.isEmpty else { return }
        let k = max(0, min(centri.count - 1, Int(p.rounded())))
        guard k != scelta else { return }
        scelta = k
        creataDa = nil
        guard suona, Date().timeIntervalSince(ultimoScatto) > 0.035 else { return }
        ultimoScatto = Date()
        SuoniOrologio.scatto()
        WKInterfaceDevice.current().play(.click)
    }

    /// Un giro a 60 Hz (lo schermo del polso) finché c'è qualcosa che si muove o l'ologramma è acceso.
    private func avvia() {
        guard giro == nil else { return }
        giro = Task { @MainActor [weak self] in
            var prima = Date()
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let ora = Date(), dt = min(0.05, ora.timeIntervalSince(prima))
                prima = ora
                if !self.passo(dt) { break }
            }
            self?.giro = nil
        }
    }

    /// Un fotogramma: la molla verso l'icona, la creazione, lo spegnimento, la lente. Falso: niente più da fare.
    private func passo(_ dt: Double) -> Bool {
        if let m = meta, dito == nil {
            // la molla smorzata al punto critico, risolta esatta: x(t) = (x0 + (v0 + w·x0)·t)·e^(−w·t). Stabile con qualunque dt
            // (prima, Eulero con w·dt fino a 1,1: coi fotogrammi lenti del polso divergeva e le icone non si fermavano più)
            let w = 22.0, x = p - m, c = velocita + w * x, e = exp(-w * dt)
            p = m + (x + c * dt) * e
            velocita = (velocita - w * c * dt) * e
            if abs(m - p) < 0.004 && abs(velocita) < 0.05 { p = m; velocita = 0; meta = nil }
            posa()
            aggiorna(suona: true)
            spegniAlle = Date().addingTimeInterval(RuotaPolso.resta)
        }
        if vivo, dito == nil, meta == nil, creataDa == nil, scelta >= 0 {
            creataDa = Date()
            SuoniOrologio.tonoOlo()
        }
        if vivo, dito == nil, meta == nil, Date() > spegniAlle { spegni() }
        let obiettivo: Double = vivo && creataDa == nil ? 1 : 0
        if lente != obiettivo {
            let l = lente + (obiettivo - lente) * (1 - exp(-dt / 0.045))
            lente = abs(l - obiettivo) < 0.002 ? obiettivo : l
        }
        return vivo || dito != nil || meta != nil || lente > 0
    }

    func selezionata(_ k: Int) -> Bool { vivo && scelta == k }

    /// La lente sull'icona `k`: cresce fino a 1,32 al centro, solo mentre si muove.
    func scala(_ k: Int) -> CGFloat {
        guard lente > 0.001 else { return 1 }
        let d = Double(k) - p
        return CGFloat(1 + 0.32 * lente * exp(-pow(d / 0.6, 2)))
    }
}

/// La barra che segue la ruota (solo questa si ridisegna mentre si muove).
struct BarraSegueRuota: ViewModifier {
    @ObservedObject var ruota: RuotaPolso
    func body(content: Content) -> some View {
        content
            .offset(x: ruota.spostamento)
            .animation(ruota.animazione, value: ruota.spostamento)
    }
}

/// Un'icona della barra: la lente al centro mentre si muove e l'anello di selezione con l'ologramma acceso.
struct IconaSegueRuota: ViewModifier {
    @ObservedObject var ruota: RuotaPolso
    let indice: Int
    func body(content: Content) -> some View {
        let s = ruota.scala(indice), scelta = ruota.selezionata(indice)
        content
            .overlay(Circle().stroke(TintaOrologio.ciano.opacity(scelta ? 1 : 0), lineWidth: 1.4))
            .background(Circle().fill(TintaOrologio.ciano.opacity(scelta ? 0.3 : 0)))
            .shadow(color: TintaOrologio.ciano.opacity(scelta ? 0.7 : 0), radius: 5)
            .scaleEffect(s)
            .zIndex(s > 1.02 ? 2 : 0)
    }
}

/// Il reattore si vela mentre l'ologramma è acceso (e lascia i tocchi all'ologramma).
struct VeloPolso: ViewModifier {
    @ObservedObject var ruota: RuotaPolso
    func body(content: Content) -> some View {
        content
            .opacity(ruota.vivo ? 0.12 : 1)
            .animation(.easeOut(duration: 0.2), value: ruota.vivo)
            .allowsHitTesting(!ruota.vivo)
    }
}
