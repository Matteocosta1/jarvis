import Foundation
import SwiftUI
import Combine
import WatchKit

/// MARK XI · la barra delle icone al polso (mockup approvato dal signore il 3 nov: «le icone col dito, le sezioni con la corona»).
/// Il dito trascina la barra; lasciata, va con lo slancio all'icona più vicina al centro, con una molla smorzata al punto critico.
/// Mentre si muove, l'icona al centro si vede in ologramma nel reattore (uno scatto per icona: suono «ruota» e vibrazione); ferma,
/// l'ologramma si crea sul tono «olo». Toccato, apre la sezione; 5 s senza toccare niente e si spegne. Un tocco su un'icona la apre
/// come sempre.
/// 4 nov (il signore: «con la corona le muovi normalmente, con il dito l'animazione olografica»): nella schermata principale la
/// corona fa scorrere la barra normalmente, un'icona per scatto (l'icona sul bordo sinistro, come lo scorrimento di prima), senza
/// ologramma né lente; la pagina si scorre col dito. Nelle sezioni la corona resta delle pagine (`CoronaBarra`).
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
    /// La corona: l'icona che sta sul bordo sinistro (si aggiorna anche dopo il dito, così la corona riparte da dov'è la barra).
    @Published private(set) var kCorona = 0

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
        kCorona = ultimaCorona
    }

    /// Porta l'icona `k` sul bordo sinistro (come lo scrollTo con anchor .leading di prima).
    func scorriA(_ k: Int, durata: Double) {
        guard centri.indices.contains(k) else { return }
        animazione = .easeOut(duration: durata)
        spostamento = sinistra(k)
        kCorona = min(k, ultimaCorona)
    }

    // MARK: la corona (4 nov)

    /// Lo spostamento che mette l'icona `k` sul bordo sinistro (senza andare oltre la fine della barra).
    private func sinistra(_ k: Int) -> CGFloat {
        max(min(0, larghezza - larghezzaTotale), min(0, -(centri[k] - 17 - 2)))
    }

    /// L'ultima posizione della corona: quella che porta in vista la fine della barra (oltre, la barra non si muove più).
    var ultimaCorona: Int {
        guard !centri.isEmpty else { return 0 }
        let fine = min(0, larghezza - larghezzaTotale)
        return centri.indices.first { sinistra($0) <= fine + 0.5 } ?? centri.count - 1
    }

    /// Uno scatto della corona: la barra scorre normalmente fino all'icona `k` (sul bordo sinistro), senza ologramma né lente.
    func corona(_ k: Int) {
        guard centri.indices.contains(k) else { return }
        if vivo { spegni() }                                          // l'ologramma è del dito: la corona lo spegne
        dito = nil
        meta = nil
        velocita = 0
        kCorona = k
        animazione = .easeOut(duration: 0.16)
        spostamento = sinistra(k)
    }

    /// Dopo il dito: la posizione della corona è l'icona che sta più vicina al bordo sinistro.
    private func sincronizzaCorona() {
        guard !centri.isEmpty else { return }
        var migliore = 0, distanza = CGFloat.greatestFiniteMagnitude
        for k in 0...ultimaCorona {
            let d = abs(sinistra(k) - spostamento)
            if d < distanza { distanza = d; migliore = k }
        }
        if kCorona != migliore { kCorona = migliore }
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

    private func posa() {
        animazione = nil
        spostamento = larghezza / 2 - xDi(p)
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
            let w = 22.0
            velocita += (w * w * (m - p) - 2 * w * velocita) * dt
            p += velocita * dt
            if abs(m - p) < 0.004 && abs(velocita) < 0.05 { p = m; velocita = 0; meta = nil }
            posa()
            if meta == nil { sincronizzaCorona() }                    // ferma: la corona riparte da qui
            aggiorna(suona: true)
            spegniAlle = Date().addingTimeInterval(RuotaPolso.resta)
        }
        if vivo, dito == nil, meta == nil, creataDa == nil, scelta >= 0 {
            creataDa = Date()
            SuoniOrologio.tonoOlo()
        }
        if vivo, dito == nil, meta == nil, Date() > spegniAlle { spegni() }
        let obiettivo: Double = vivo && creataDa == nil ? 1 : 0
        lente += (obiettivo - lente) * (1 - exp(-dt / 0.045))
        if abs(lente - obiettivo) < 0.002 { lente = obiettivo }
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

/// 4 nov · la corona nella schermata principale (il signore: «con la corona scorri normalmente le icone, con il dito che trascina
/// tipo click wheel si crea l'animazione olografica; dentro le sezioni la corona fa scorrere le pagine»). La barra prende la corona
/// finito l'avvio e ogni volta che la schermata torna davanti; un'icona per scatto, con lo scatto della corona di watchOS. La riga
/// delle foto nella chat, toccata, se la prende come prima; quando la lascia (toccato altrove), la corona torna alle icone. Nelle
/// sezioni non c'è: lì la corona resta delle pagine.
struct CoronaBarra: ViewModifier {
    @ObservedObject var ruota: RuotaPolso
    /// Finito l'avvio (prima la barra si accende da sola).
    let attiva: Bool
    @FocusState private var fuoco: Bool
    @State private var valore = 0.0
    @State private var davanti = false

    func body(content: Content) -> some View {
        content
            .focusable(attiva && davanti)
            .focused($fuoco)
            .focusEffectDisabled()
            .digitalCrownRotation($valore, from: 0, through: Double(max(1, ruota.ultimaCorona)), by: 1,
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .onChange(of: valore) { _, v in
                let k = Int(v.rounded())
                if k != ruota.kCorona { ruota.corona(min(k, ruota.ultimaCorona)) }
            }
            .onChange(of: ruota.kCorona) { _, k in if Int(valore.rounded()) != k { valore = Double(k) } }
            .onChange(of: attiva) { _, si in if si && davanti { prendi() } }
            .onAppear {
                davanti = true
                if attiva { prendi() }
            }
            .onDisappear { davanti = false }
            .onReceive(NotificationCenter.default.publisher(for: RigaCorona<EmptyView>.lascia)) { _ in
                // la riga delle foto ha lasciato la corona (toccato altrove): torna alle icone
                if attiva && davanti { prendi() }
            }
    }

    /// La barra prende la corona (al giro dopo: prima deve essere diventata «focusable»).
    private func prendi() {
        valore = Double(ruota.kCorona)
        Task { @MainActor in fuoco = true }
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
