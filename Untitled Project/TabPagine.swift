#if os(iOS)
import SwiftUI
import UIKit
import Combine
import Network
import CoreTelephony
import WatchConnectivity
import QuartzCore

// MARK: - 13.7 · PAGINE, LA TAB BASSA
// Il signore (21 nov): «una tab piccolina come quella in alto a destra, in basso a sinistra accanto a IN ATTESA, che non copra niente,
// con dentro le pagine olografiche», «che le puoi scorrere come le canzoni… tipo dischi», «all'avvio si forma in contemporanea con il
// caricamento delle icone di SISTEMI, dentro un caricamento velocissimo di tutte le icone come uno sfoglio, poi sparisce; si richiama
// con lo swipe verso destra», «in alto, con ora e batteria, l'Apple Watch connesso, la sua batteria, la rete». Scelte del signore:
// LUNGA (00:20), i tasti ALTA da 11 punti (00:49), piccola anche lei con «k/N» (00:27), trasparenza 55 % piccola e 60 % aperta, chiusa
// con lo swipe anche da piccola (01:04). Tutto come il mockup «JARVIS Approvato» (RIEPILOGO). 22 nov 02:0x, il signore: tutto in
// questa build; la miniatura di ogni pagina è la sua foto (fatta mentre è davanti, a dito fermo): dove iOS non la fotografa (la
// fotocamera) resta il fondo scuro con l'icona.

/// La batteria dell'Apple Watch, mandata dall'app del polso (PonteOrologio.mandaBatteria) quando si sveglia o cambia.
@MainActor
final class StatoPolso: ObservableObject {
    static let condiviso = StatoPolso()
    @Published private(set) var batteria: Int?
    @Published private(set) var carica = false
    private(set) var quando = Date.distantPast

    /// Dal ponte con l'orologio (fuori dal main actor): si prendono solo i numeri, poi si passa al main actor.
    nonisolated static func ricevi(_ m: [String: Any]) {
        guard let b = m["polso_batteria"] as? Int else { return }
        let c = m["polso_carica"] as? Bool ?? false
        let t = (m["quando"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        Task { @MainActor in StatoPolso.condiviso.aggiorna(b, c, t) }
    }

    private func aggiorna(_ b: Int, _ c: Bool, _ t: Date) {
        guard t >= quando else { return }                     // una notizia vecchia arrivata in coda dopo una nuova: no
        batteria = b
        carica = c
        quando = t
    }

    /// L'orologio c'è: abbinato, con l'app di JARVIS, e raggiungibile adesso o sentito da meno di mezz'ora.
    var collegato: Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return false }
        return s.isReachable || Date().timeIntervalSince(quando) < 1800
    }
}

/// La rete come la sa l'iPhone (NWPathMonitor e il tipo di rete dati): Wi-Fi, 5G / 4G / 3G, oppure nessuna. Le tacche del segnale
/// no: iOS non le dà alle app.
@MainActor
final class ReteTab: ObservableObject {
    static let condivisa = ReteTab()
    enum Tipo: Equatable { case wifi, dati(String), nessuna }
    @Published private(set) var tipo: Tipo = .wifi
    private let monitor = NWPathMonitor()
    private let telefonia = CTTelephonyNetworkInfo()
    private var avviata = false

    func avvia() {
        guard !avviata else { return }
        avviata = true
        monitor.pathUpdateHandler = ReteTab.gestore(self)
        monitor.start(queue: DispatchQueue(label: "jarvis.rete.tab"))
    }

    /// Il gestore gira sulla coda della rete: legge solo il percorso e passa al main actor.
    nonisolated private static func gestore(_ rete: ReteTab) -> @Sendable (NWPath) -> Void {
        { percorso in
            let su = percorso.status == .satisfied
            let wifi = percorso.usesInterfaceType(.wifi) || percorso.usesInterfaceType(.wiredEthernet)
            Task { @MainActor in rete.aggiorna(su: su, wifi: wifi) }
        }
    }

    private func aggiorna(su: Bool, wifi: Bool) {
        if !su { tipo = .nessuna; return }
        if wifi { tipo = .wifi; return }
        let r = telefonia.serviceCurrentRadioAccessTechnology?.values.first ?? ""
        if r == CTRadioAccessTechnologyNR || r == CTRadioAccessTechnologyNRNSA { tipo = .dati("5G") }
        else if r == CTRadioAccessTechnologyLTE { tipo = .dati("4G") }
        else if r.isEmpty { tipo = .dati("DATI") }
        else if r == CTRadioAccessTechnologyEdge || r == CTRadioAccessTechnologyGPRS { tipo = .dati("2G") }
        else { tipo = .dati("3G") }
    }
}

/// Lo stato della tab: se c'è, piccola o aperta, fissata, l'avvio, le carte, le miniature. Le misure della schermata le scrive
/// ContentView (coordinate della finestra): da lì si calcola il posto, come `zona()` del mockup.
@MainActor
final class Pagine: ObservableObject {
    static let condivisa = Pagine()

    // la tab
    @Published private(set) var su = false
    @Published private(set) var piccola = false
    @Published private(set) var fissa = false
    @Published private(set) var nataDa = Date()
    /// Si sta chiudendo: verso il bordo sinistro (lui) o richiudendosi in una riga (da sola).
    enum Chiusura: Equatable { case via, muto }
    @Published private(set) var chiusura: Chiusura?
    /// L'avvio: le icone di tutte le sezioni che scorrono come dischi, da «interface» a «operational».
    struct Avvio: Equatable {
        let nomi: [String]
        let icone: [String]
        let da: Date
        let durata: Double
        var pronte = false
    }
    @Published private(set) var avvio: Avvio?

    // le carte (Cover Flow): `off` è la carta al centro (anche a metà fra due)
    @Published var off: Double = 0
    struct Corsa: Equatable { let da: Double, a: Double, inizio: Date, durata: Double }
    @Published private(set) var corsa: Corsa?
    @Published private(set) var miniature: [UUID: UIImage] = [:]

    // le misure della schermata (coordinate della finestra), scritte da ContentView
    var anello: (rett: CGRect, angoli: [Double], raggio: CGFloat, lato: CGFloat)?
    var fase: CGRect = .zero
    var tele: CGRect = .zero
    var sugg: CGRect = .zero
    var chatAlto: CGFloat?
    /// Dove sta la tab adesso e dove i suoi tre tasti (un tocco fuori la rimpicciolisce; sui tasti fanno solo il loro).
    var rett: CGRect = .zero
    var rettTasti: CGRect = .zero
    private var zonaPiccola: CGRect?
    private var suTasti = false
    private(set) var fissataAlle = Date.distantPast
    private var giro = 0

    static let altaPiccola: CGFloat = 72
    /// Metà della riga di telemetria più lunga (21 lettere × 6,8 punti).
    static let mezzaTelemetria: CGFloat = 21 * 6.8 / 2

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: il posto

    /// La tasca in basso a sinistra fra la colonna di icone di sinistra (sopra), la riga «Mi parli…» (sotto) e IN ATTESA (a destra):
    /// LUNGA con i tasti ALTA (parte 30 punti più su), larga fino alle scritte, alta al massimo 164.
    func zona() -> CGRect {
        let S: CGFloat = 10
        // 13.8 (il signore, 22 nov: «la tab bassa si muove a caso»): la riga sotto lo stato (TelemetriaHUD) cambia ogni 2,5 s e
        // ha lunghezze diverse; la tab la seguiva e si allargava e stringeva. Ora si ferma prima della più lunga (MEMORIA SINCRONIZZATA
        // / ELABORAZIONE IN CORSO, 21 lettere da 6,8 punti: monospaziato 8 punti con tracking 2), centrata dove sta la riga: non si muove più
        var sinistre: [CGFloat] = []
        if fase.width > 0 && fase.height > 0 { sinistre.append(fase.midX - 10 * 11.2 / 2) }   // anche lo stato: il più lungo (LA ASCOLTO)
        if tele.width > 0 && tele.height > 0 { sinistre.append(tele.midX - Pagine.mezzaTelemetria) }
        let destra = min(S + 212, (sinistre.min().map { $0 - 6 } ?? S + 140) + 8)
        var giu: CGFloat = chatAlto.map { $0 - 6 } ?? 600
        if sugg.width > 0 { giu = min(giu, sugg.minY - 5) }   // 13.8: sempre (una frase corta non la fa più allungare)
        var colonna: [CGFloat] = []
        if let a = anello, a.lato > 0 {
            let s = a.rett.height / a.lato, mezzo = 19 * s
            for ang in a.angoli {
                let x = a.rett.midX + s * a.raggio * CGFloat(cos(ang)), y = a.rett.midY + s * a.raggio * CGFloat(sin(ang))
                if x - mezzo < S + 60 && y + mezzo < giu { colonna.append(y + mezzo) }
            }
        }
        let alto = (colonna.max().map { $0 + 4 } ?? giu - 112) - 10 - 30
        let h = min(134 + 30, giu - alto)
        return CGRect(x: S, y: alto.rounded(), width: max(90, (destra - S).rounded()), height: max(Pagine.altaPiccola, h.rounded()))
    }

    /// Dove sta adesso: piccola, lo stesso inizio e alta 72 (misurata a tab aperta e tenuta, così non salta dietro alle icone).
    func posto() -> CGRect {
        let z = zona()
        if piccola { return zonaPiccola ?? CGRect(x: z.minX, y: z.minY, width: z.width, height: Pagine.altaPiccola) }
        return z
    }

    // MARK: aprire e chiudere

    /// Richiamata dal bordo sinistro (lo swipe verso destra): nasce come FILO, dall'angolo in alto a sinistra, col suono della tab.
    func apri(davanti: Int) {
        guard !su, avvio == nil else { return }
        giro += 1
        piccola = false
        fissa = false
        chiusura = nil
        corsa = nil
        off = Double(max(0, davanti))
        nataDa = Date()
        su = true
        Suoni.filo()
    }

    /// Chiusa da lui (swipe, tasto): scivola verso il bordo sinistro; da sola (una sezione davanti, l'avvio finito): si richiude in
    /// una riga di luce. 0,24 s, poi non c'è più.
    func chiudi(muto: Bool) {
        guard su, chiusura == nil else { return }
        giro += 1
        let mio = giro
        if !muto { Suoni.filoVia() }
        withAnimation(.timingCurve(0.4, 0, 0.8, 0.4, duration: 0.24)) { chiusura = muto ? .muto : .via }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard mio == self.giro else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                self.su = false
                self.chiusura = nil
                self.avvio = nil
                self.piccola = false
                self.fissa = false
                self.corsa = nil
                self.zonaPiccola = nil
            }
        }
    }

    /// Piccola (una riga con le icone delle pagine aperte) o aperta (le pagine a dischi), morbida.
    func stringi(_ si: Bool) {
        guard su, avvio == nil, chiusura == nil, piccola != si else { return }
        if si { let z = zona(); zonaPiccola = CGRect(x: z.minX, y: z.minY, width: z.width, height: Pagine.altaPiccola) }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25)) { piccola = si }
    }

    /// Tenuta premuta: si fissa ◆ (allora non si stringe più) o si sgancia, come la tab alta.
    func fissaOSgancia() {
        guard su, avvio == nil, !suTasti else { return }
        fissa.toggle()
        fissataAlle = Date()
        Aptica.tabFissa(fissa)
        if fissa { stringi(false) }
    }

    /// Un dito sullo schermo (TocchiSchermo, coordinate della finestra): fuori dalla tab (la ruota, il reattore, le scritte) la
    /// rimpicciolisce, se non è fissata.
    func toccoSchermo(_ p: CGPoint) {
        suTasti = rettTasti.width > 0 && rettTasti.insetBy(dx: -2, dy: -7.5).contains(p)
        guard su, avvio == nil, chiusura == nil else { return }
        if rett.contains(p) { return }
        if fascia(zona()).contains(p) { return }
        if !fissa { stringi(true) }
    }

    /// La fascia invisibile sul bordo sinistro, alta quanto la tab: lo swipe verso destra la richiama.
    func fascia(_ z: CGRect) -> CGRect { CGRect(x: 0, y: z.minY, width: 24, height: z.height) }

    // MARK: le carte

    /// La carta `meta` al centro, con la curva del mockup (ease-out cubica, 0,22–0,52 s secondo la distanza).
    func vaiA(_ meta: Int, totale: Int) {
        guard totale > 0 else { return }
        let a = Double(max(0, min(totale - 1, meta)))
        let ora = offAdesso(Date())
        let durata = min(0.52, 0.22 + 0.09 * abs(a - ora))
        corsa = Corsa(da: ora, a: a, inizio: Date(), durata: durata)
        off = ora
        let c = corsa
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(durata))
            if self.corsa == c { self.off = a; self.corsa = nil }
        }
    }

    /// Dove sono le carte adesso: durante la corsa a metà strada, durante l'avvio sullo sfoglio veloce.
    func offAdesso(_ ora: Date) -> Double {
        if let a = avvio {
            let u = min(1, max(0, ora.timeIntervalSince(a.da) / a.durata))
            let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
            return Double(max(0, a.nomi.count - 1)) * e
        }
        guard let c = corsa else { return off }
        let u = min(1, max(0, ora.timeIntervalSince(c.inizio) / c.durata))
        return c.da + (c.a - c.da) * (1 - pow(1 - u, 3))
    }

    /// Il dito muove le carte: la corsa si ferma dove sono.
    func ferma(_ ora: Date) {
        if corsa != nil { off = offAdesso(ora); corsa = nil }
    }

    // MARK: l'avvio

    /// ALL'AVVIO, insieme alle icone di SISTEMI, sui tempi veri della voce (VOCE_AVVIO): su «interface» la tab si forma; mentre le
    /// 6 icone si posano in alto (11,74 → 14,31) dentro scorrono velocissime come dischi tutte le icone delle sezioni; su
    /// «operational» si ferma su PRONTE, alla fine della frase si richiude nella riga di luce. Nessun suono in più (c'è la traccia).
    /// `vivo`: l'avvio olografico c'è ancora (se la voce è stata interrotta, la tab non si forma o si richiude).
    func avvio(zero: Date, nomi: [String], icone: [String], vivo: @escaping () -> Bool) {
        guard !nomi.isEmpty else { return }
        if su { chiudi(muto: true) }                          // (aumenta già il giro: qui non si tocca, se no la chiusura resterebbe a metà)
        let mio = giro
        let interface = 11.66, posate = 14.31, operational = AvvioOlo.operational, fine = 15.08
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0, zero.timeIntervalSinceNow + interface)))
            guard mio == self.giro, vivo(), !self.su else { return }
            self.avvio = Avvio(nomi: nomi, icone: icone, da: Date(), durata: max(0.8, posate - interface - 0.06))
            self.piccola = false
            self.fissa = false
            self.chiusura = nil
            self.nataDa = Date()
            self.su = true
            self.giro += 1
            let suo = self.giro
            try? await Task.sleep(for: .seconds(max(0, zero.timeIntervalSinceNow + operational)))
            guard suo == self.giro else { return }
            withAnimation(.linear(duration: 0.26)) { self.avvio?.pronte = true }
            try? await Task.sleep(for: .seconds(max(0, zero.timeIntervalSinceNow + fine)))
            guard suo == self.giro else { return }
            self.chiudi(muto: true)
        }
    }

    /// L'avvio olografico si è spento prima (la voce sfumata): la tab dell'avvio si richiude subito.
    func interrompiAvvio() {
        giro += 1
        if avvio != nil, su { chiudi(muto: true) }
    }

    // MARK: le miniature

    /// La foto della pagina davanti, adesso, piccola (circa 160 pixel di larghezza): dove iOS non la fotografa resta scura.
    func fotografa(_ id: UUID) {
        guard let w = FasciaAlta.finestra else { return }
        let b = w.bounds
        guard b.width > 0 else { return }
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 0.4
        formato.opaque = true
        let img = UIGraphicsImageRenderer(bounds: b, format: formato).image { _ in
            _ = w.drawHierarchy(in: b, afterScreenUpdates: false)
        }
        miniature[id] = img
    }

    /// Le pagine chiuse non hanno più la loro foto; e se ne sono rimaste meno, le carte non restano oltre l'ultima.
    func tieni(_ ids: Set<UUID>) {
        if avvio == nil {
            let ultima = Double(max(0, ids.count - 1))
            if offAdesso(Date()) > ultima { corsa = nil; off = ultima }
        }
        let via = miniature.keys.filter { !ids.contains($0) }
        guard !via.isEmpty else { return }
        for k in via { miniature[k] = nil }
    }
}

/// Lo strato della tab sopra la schermata di JARVIS (sotto il menu SISTEMI, la tendina e le sezioni), con la fascia invisibile del
/// bordo sinistro che la richiama.
struct StratoPagine: View {
    @ObservedObject private var p = Pagine.condivisa
    let voci: [PilaSezioni.Voce]
    let icone: [String: String]
    /// L'ultima sezione stata davanti (quella al centro quando la tab si apre).
    let ultima: UUID?
    /// Una sezione è davanti: la tab non c'è (si richiude da sola) e la fascia è spenta.
    let sezioneDavanti: Bool
    /// La tastiera o la tendina aperte: la fascia è spenta (e con la tastiera la tab si richiude).
    let tastiera: Bool
    let tendina: Bool
    let apri: (UUID) -> Void
    let chiudi: (UUID) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in                // il posto si ricontrolla ogni secondo (come il mockup)
            GeometryReader { geo in
                let o = geo.frame(in: .global).origin
                let q = p.posto()
                ZStack(alignment: .topLeading) {
                    Color.clear
                    if p.su {
                        TabPagineVista(p: p, voci: voci, icone: icone, apri: apri, chiudi: chiudi)
                            .frame(width: q.width, height: q.height)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { p.rett = $0 }
                            .offset(x: q.minX - o.x, y: q.minY - o.y)
                            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25), value: q)
                            .zIndex(1)
                    } else if !sezioneDavanti && !tastiera && !tendina && p.avvio == nil {
                        let f = p.fascia(p.zona())
                        FasciaPagine(totale: voci.count, ultima: voci.firstIndex { $0.id == ultima } ?? max(0, voci.count - 1))
                            .frame(width: f.width, height: f.height)
                            .offset(x: f.minX - o.x, y: f.minY - o.y)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: sezioneDavanti) { _, si in if si { p.chiudi(muto: true) } }
        .onChange(of: tastiera) { _, si in if si { p.chiudi(muto: true) } }
        .onChange(of: Set(voci.map(\.id))) { _, ids in p.tieni(ids) }
    }
}

/// La fascia invisibile sul bordo sinistro (24 punti, alta quanto la tab): lo swipe verso destra la richiama (un tocco solo no).
private struct FasciaPagine: View {
    let totale: Int
    let ultima: Int
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { v in
                        let dx = v.translation.width, dy = abs(v.translation.height)
                        let deciso = abs(dx) > dy * 1.8 && (abs(dx) > 50 || (abs(dx) > 24 && abs(v.velocity.width) > 400))
                        if dx > 0, deciso { Pagine.condivisa.apri(davanti: min(ultima, max(0, totale - 1))) }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("PAGINE")
            .accessibilityHint("Mostra le pagine aperte")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Pagine.condivisa.apri(davanti: min(ultima, max(0, totale - 1))) }
    }
}

/// La tab: la cornice di FILO specchiata, la riga di stato, le pagine a dischi (piccola: le loro icone), il piede col nome.
private struct TabPagineVista: View {
    @ObservedObject var p: Pagine
    @ObservedObject private var polso = StatoPolso.condiviso
    @ObservedObject private var rete = ReteTab.condivisa
    let voci: [PilaSezioni.Voce]
    let icone: [String: String]
    let apri: (UUID) -> Void
    let chiudi: (UUID) -> Void
    @State private var vetroPronto = false
    @State private var nascita: Double = 0
    @State private var tremolio: Double = 0

    var body: some View {
        let piccola = p.piccola
        ZStack(alignment: .topLeading) {
            // il vetro: sfocatura, fondo scuro (aperta 50 %, piccola 45 %), luce olografica, poi la cornice
            // 13.8 (4) (il signore, 12:22: «come nello swipe»): la sfocatura senza la tinta di iOS, il fondo delle pagine olografiche
            // (aperta 50 %, piccola 45 %), sopra la luce ciano, il bagliore e le righe; poi la cornice
            SfocaturaOlo()
                .padding(EdgeInsets(top: 24, leading: 4, bottom: 3, trailing: 4))
                .opacity(vetroPronto ? 1 : 0)
            Rectangle()
                .fill(Color(red: 3 / 255, green: 12 / 255, blue: 16 / 255).opacity(piccola ? TintaTab.vetroPiccola : TintaTab.vetroAperta))
                .padding(EdgeInsets(top: 24, leading: 4, bottom: 3, trailing: 4))
                .animation(.easeOut(duration: 0.3), value: piccola)
            LuceOlografica()
                .padding(EdgeInsets(top: 24, leading: 4, bottom: 3, trailing: 4))
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSince(p.nataDa)
                Canvas(rendersAsynchronously: false) { gc, size in
                    CorniceFilo.disegna(&gc, size, t: t, fondo: 0, specchio: true)
                }
            }
            .allowsHitTesting(false)
            VStack(spacing: 0) {
                rigaStato
                if !piccola {
                    LibroPagine(p: p, voci: voci, icone: icone, apri: apri, chiudi: chiudi)
                        .padding(.top, 2)
                        .padding(.horizontal, -4)
                        .modifier(TremolioLibro(p: tremolio))
                }
                piede
            }
            .padding(EdgeInsets(top: 24, leading: 10, bottom: 6, trailing: 8))
        }
        .contentShape(Rectangle())
        // piccola: il dito non apre subito; se corre verso sinistra la chiude, se si alza fermo la apre (i tasti restano tasti)
        .gesture(DragGesture(minimumDistance: 0).onEnded { v in finePiccola(v) }, including: piccola ? .all : .subviews)
        // tenuta premuta (0,45 s, il dito fermo): si fissa ◆ / si sgancia
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45, maximumDistance: 10).onEnded { _ in
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)) { p.fissaOSgancia() }
        })
        .allowsHitTesting(p.avvio == nil && p.chiusura == nil)
        .modifier(NascitaPagine(fase: nascita))
        .modifier(ChiusuraPagine(p: p.chiusura == nil ? 0 : 1, muto: p.chiusura == .muto))
        .onAppear {
            ReteTab.condivisa.avvia()
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3)) { nascita = 1 }
            withAnimation(.linear(duration: 0.36).delay(0.17)) { tremolio = 1 }   // le carte si accendono tremolando
        }
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            vetroPronto = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PAGINE")
    }

    // MARK: la riga di stato: l'ora, la batteria dell'iPhone, l'orologio con la sua batteria, la rete, i tre tasti

    private var rigaStato: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            HStack(spacing: 0) {
                Text(TabPagineVista.formatoOra.string(from: tl.date))
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced)).tracking(0.2)
                    .monospacedDigit()
                    .foregroundStyle(Olo.ciano)
                    .shadow(color: Olo.azzurro.opacity(0.95), radius: 3)
                if p.fissa {
                    Text("◆")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(TintaTab.chiaro)
                        .shadow(color: Olo.azzurro.opacity(0.9), radius: 2.5)
                        .padding(.leading, 0.5)
                        .accessibilityLabel("fissata")
                }
                Spacer(minLength: 1.5)
                HStack(spacing: 0.5) {
                    GlifoTab(disegno: .telefono).frame(width: 5.5 * 8 / 14, height: 5.5)
                    batteria(TabPagineVista.batteriaTelefono, carica: TabPagineVista.telefonoInCarica)
                }
                Spacer(minLength: 1.5)
                HStack(spacing: 0.5) {
                    GlifoTab(disegno: .orologio).frame(width: 5.5 * 10 / 14, height: 5.5)
                    if polso.collegato, let b = polso.batteria { batteria(b, carica: polso.carica) } else { testoStato("—") }
                }
                .opacity(polso.collegato ? 1 : 0.4)
                Spacer(minLength: 1.5)
                Group {
                    switch rete.tipo {
                    case .wifi: GlifoTab(disegno: .onde).frame(width: 5.5 * 14 / 10, height: 5.5)
                    case .dati(let t): Text(t).font(.system(size: 6.5, weight: .bold, design: .monospaced)).tracking(0.4)
                    case .nessuna: Text("OFFLINE").font(.system(size: 6.5, weight: .bold, design: .monospaced)).tracking(0.4)
                    }
                }
                .foregroundStyle(Olo.ciano)
                .opacity(rete.tipo == .nessuna ? 0.4 : 1)
                Spacer(minLength: 1.5)
                TastiTab(lato: 11, spazio: 4, oltre: (v: 7.5, h: 2), chiudi: {
                    p.chiudi(muto: false)
                }, riduci: {
                    p.stringi(true)
                }, apri: {
                    p.stringi(false)
                })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { p.rettTasti = $0 }
            }
            .lineLimit(1)
        }
        .frame(height: 20)
        .padding(.top, 1)
        .padding(.horizontal, -3)
        .contentShape(Rectangle())
        // lo swipe verso sinistra dalla testata la manda via (sulle pagine il dito scorre e chiude le pagine, mai la tab)
        .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { v in fineTesta(v) })
    }

    private func batteria(_ b: Int, carica: Bool) -> some View {
        HStack(spacing: 0.5) {
            // 13.8 (il signore: «le icone di carica devono essere ciano»): il simbolo, non l'emoji (iOS la fa sempre gialla)
            if carica { Image(systemName: "bolt.fill").font(.system(size: 5, weight: .semibold)).foregroundStyle(TintaTab.chiaro) }
            testoStato("\(b)%")
        }
    }

    private func testoStato(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 6, weight: .semibold, design: .monospaced)).tracking(0.3)
            .monospacedDigit()
            .foregroundStyle(Olo.ciano)
    }

    private static var batteriaTelefono: Int {
        let l = UIDevice.current.batteryLevel
        return l < 0 ? 100 : Int((l * 100).rounded())
    }

    private static var telefonoInCarica: Bool {
        let s = UIDevice.current.batteryState
        return s == .charging || s == .full
    }

    private static let formatoOra: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: il piede: «k/N» e il nome della pagina al centro (piccola: le icone delle pagine aperte e «k/N»)

    private var piede: some View {
        TimelineView(.animation(minimumInterval: nil, paused: p.avvio == nil && p.corsa == nil)) { tl in
            let n = p.avvio?.nomi.count ?? voci.count
            let k = max(0, min(n - 1, Int(p.offAdesso(tl.date).rounded())))
            HStack(spacing: 6) {
                if p.piccola {
                    HStack(spacing: 6) {
                        ForEach(Array(voci.enumerated()), id: \.element.id) { i, v in
                            GlifoSezione(icona: icone[v.sezione.nome] ?? v.sezione.iconaDiRiserva, lato: 12)
                                .foregroundStyle(i == k ? TintaTab.chiaro : Olo.ciano)
                                .shadow(color: Olo.azzurro.opacity(0.95), radius: 2)
                                .frame(width: 14, height: 14)
                        }
                        Text(n > 0 ? "\(k + 1)/\(n)" : "0/0")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced)).tracking(1)
                            .foregroundStyle(Olo.ciano.opacity(0.62))
                            .padding(.leading, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                } else {
                    let pronte = p.avvio?.pronte == true
                    let nome: String = pronte ? "" : (p.avvio.map { a in a.nomi.indices.contains(k) ? a.nomi[k] : "" }
                                                        ?? (voci.indices.contains(k) ? voci[k].sezione.nome : "NESSUNA"))
                    HStack(spacing: 6) {
                        Text(pronte ? "PRONTE" : (n > 0 ? "\(k + 1)/\(n)" : "0"))
                            .foregroundStyle(Olo.ciano.opacity(0.62))
                        Text(nome.uppercased())
                            .foregroundStyle(TintaTab.chiaro)
                            .shadow(color: Olo.azzurro.opacity(0.9), radius: 3)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced)).tracking(1)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: 18)
        .padding(.top, 1)
        .padding(.trailing, -3)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { v in fineTesta(v) })
    }

    // MARK: i gesti della tab

    /// Deciso: orizzontale (1,8 volte il verticale), lungo (50) o corto e svelto (24, 400 punti al secondo).
    private static func deciso(_ v: DragGesture.Value) -> Bool {
        let dx = abs(v.translation.width), dy = abs(v.translation.height)
        return dx > dy * 1.8 && (dx > 50 || (dx > 24 && abs(v.velocity.width) > 400))
    }

    private func fineTesta(_ v: DragGesture.Value) {
        guard !p.piccola, v.translation.width < 0, TabPagineVista.deciso(v) else { return }
        p.chiudi(muto: false)
    }

    private func finePiccola(_ v: DragGesture.Value) {
        guard Date().timeIntervalSince(p.fissataAlle) > 0.8 else { return }   // la pressione lunga ha appena fissato
        if v.translation.width < 0, TabPagineVista.deciso(v) { p.chiudi(muto: false); return }
        if abs(v.translation.width) < 10, abs(v.translation.height) < 10 { p.stringi(false) }
    }
}

/// Le pagine a dischi (Cover Flow): la carta al centro guarda lui, le altre ai lati girate di 62° e impilate. Il dito sceglie la
/// direzione dopo 6 punti e non la cambia più: di lato scorrono i dischi (lasciati vanno per inerzia e si fermano su uno); verso
/// l'alto la pagina sotto il dito sale con lui, sfuma e si rimpicciolisce: lasciata oltre metà altezza (o con un colpo svelto) vola
/// via e si chiude, come le app nel multitasking di iOS, altrimenti torna giù. Un tocco: su una pagina di lato la porta al centro,
/// su quella al centro la apre. Qui la tab non si chiude mai.
private struct LibroPagine: View {
    @ObservedObject var p: Pagine
    let voci: [PilaSezioni.Voce]
    let icone: [String: String]
    let apri: (UUID) -> Void
    let chiudi: (UUID) -> Void

    private enum Asse { case nessuno, lato, su, giu }
    @State private var asse: Asse = .nessuno
    @State private var off0: Double = 0
    @State private var cartaSu: Int?
    @State private var alzata: CGFloat = 0
    @State private var vola: Int?
    @State private var ultimoScatto = -1

    var body: some View {
        GeometryReader { g in
            let W = Double(g.size.width), H = Double(g.size.height)
            let CH = max(26, min(88, H - 8)), CW = (CH * 0.74).rounded()
            TimelineView(.animation(minimumInterval: nil, paused: p.avvio == nil && p.corsa == nil && vola == nil)) { tl in
                let off = p.offAdesso(tl.date)
                let avvio = p.avvio
                let n = avvio?.nomi.count ?? voci.count
                ZStack(alignment: .topLeading) {
                    // il piano di luce su cui scorrono
                    LinearGradient(stops: [.init(color: TintaTab.chiaro.opacity(0), location: 0), .init(color: TintaTab.chiaro.opacity(0.8), location: 0.3),
                                           .init(color: TintaTab.chiaro.opacity(0.8), location: 0.7), .init(color: TintaTab.chiaro.opacity(0), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(0, W - 16), height: 1)
                        .shadow(color: Olo.azzurro, radius: 3)
                        .offset(x: 8, y: H - 3)
                        .zIndex(400)
                    if n == 0 {
                        Text("NESSUNA\nPAGINA")
                            .font(.system(size: 6.5, weight: .bold, design: .monospaced)).tracking(1.2)
                            .lineSpacing(3.5)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Olo.ciano.opacity(0.45))
                            .frame(width: W, height: H)
                    }
                    ForEach(0..<n, id: \.self) { i in
                        let d = Double(i) - off, ad = abs(d)
                        let foto: UIImage? = avvio == nil && voci.indices.contains(i) ? p.miniature[voci[i].id] : nil
                        let icona: String = avvio.map { $0.icone[i] } ?? (icone[voci[i].sezione.nome] ?? voci[i].sezione.iconaDiRiserva)
                        CartaPagina(foto: foto, icona: icona, cur: ad < 0.5, lum: 1.15 - 0.45 * min(1, ad))
                            .frame(width: CW, height: CH)
                            .modifier(CoverFlow(d: d, cw: CW, ch: CH))
                            .modifier(Alza(dy: cartaSu == i ? alzata : 0, ch: CH, via: vola == i))
                            .opacity(ad > 3.2 ? 0 : min(1, 3.6 - ad))
                            .opacity(avvio?.pronte == true ? 0 : 1)
                            .brightness(avvio?.pronte == true ? 0.5 : 0)
                            .offset(x: W / 2 - CW / 2, y: 3)
                            .zIndex(200 - (ad * 10).rounded())
                    }
                }
                .frame(width: W, height: H, alignment: .topLeading)
                .onChange(of: Int(off.rounded())) { _, k in scatto(k, n) }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in segue(v, W: W, CW: CW, CH: CH) }
                    .onEnded { v in fine(v, W: W, CW: CW, CH: CH) }
            )
        }
        .frame(minHeight: 30)
        .mask(Rectangle().padding(.top, -90))                         // in alto la pagina tirata su esce e sfuma; ai lati e sotto resta dentro
    }

    /// Lo scatto della click wheel quando una carta passa al centro (mai durante l'avvio: c'è la traccia).
    private func scatto(_ k: Int, _ n: Int) {
        guard p.avvio == nil, k != ultimoScatto, k >= 0, k < n else { ultimoScatto = k; return }
        ultimoScatto = k
        Suoni.scattoRuota()
    }

    /// La carta sotto il dito (la più in alto fra quelle che lo contengono), con la stessa prospettiva delle carte.
    private func cartaSotto(_ x: Double, W: Double, CW: Double) -> Int? {
        let off = p.offAdesso(Date())
        var meglio: (i: Int, z: Double)?
        for i in voci.indices {
            let d = Double(i) - off, ad = abs(d), a = min(1, ad), sg: Double = d < 0 ? -1 : (d > 0 ? 1 : 0)
            let px = sg * (a * CW * 0.64 + max(0, ad - 1) * CW * 0.26), z = -a * 22 - max(0, ad - 1) * 4
            let k = 150 / (150 - z), centro = W / 2 + px * k, mezzo = CW / 2 * cos(a * 62 * .pi / 180) * k
            if abs(x - centro) <= max(6, mezzo), meglio.map({ 200 - ad * 10 > $0.z }) ?? true { meglio = (i, 200 - ad * 10) }
        }
        return meglio?.i
    }

    private func segue(_ v: DragGesture.Value, W: Double, CW: Double, CH: Double) {
        guard p.avvio == nil, vola == nil, !voci.isEmpty else { return }
        let dx = Double(v.translation.width), dy = Double(v.translation.height)
        if asse == .nessuno {
            guard hypot(dx, dy) >= 6 else { return }
            p.ferma(Date())
            off0 = p.off
            let carta = cartaSotto(Double(v.startLocation.x), W: W, CW: CW)
            asse = abs(dx) >= abs(dy) ? .lato : (dy < 0 && carta != nil ? .su : .giu)
            cartaSu = asse == .su ? carta : nil
        }
        switch asse {
        case .lato:
            let n = Double(voci.count - 1), o = off0 - dx / 18
            p.off = o < 0 ? o * 0.35 : (o > n ? n + (o - n) * 0.35 : o)
        case .su:
            alzata = CGFloat(min(0, dy))
        default:
            break
        }
    }

    private func fine(_ v: DragGesture.Value, W: Double, CW: Double, CH: Double) {
        defer { asse = .nessuno }
        guard p.avvio == nil, vola == nil, !voci.isEmpty else { return }
        let n = voci.count
        switch asse {
        case .lato:
            let lancio = -Double(v.velocity.width) / 1000 * 9                   // inerzia: più veloce, più carte
            p.vaiA(Int((p.off + lancio).rounded()), totale: n)
        case .su:
            guard let i = cartaSu, voci.indices.contains(i) else { alzata = 0; cartaSu = nil; return }
            let dy = Double(v.translation.height)
            if -dy > CH * 0.5 || v.velocity.height < -500 {
                // via: vola in alto e si chiude
                let id = voci[i].id
                Suoni.filoVia()
                withAnimation(.timingCurve(0.3, 0, 0.8, 0.6, duration: 0.2)) { vola = i }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(210))
                    chiudi(id)
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { vola = nil; alzata = 0; cartaSu = nil }
                    p.vaiA(min(i, max(0, n - 2)), totale: max(1, n - 1))
                }
            } else {
                withAnimation(.spring(duration: 0.26, bounce: 0.35)) { alzata = 0 }
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(270)); if alzata == 0 { cartaSu = nil } }
            }
        case .giu:
            break
        case .nessuno:
            // un tocco: di lato la porta al centro, al centro la apre
            guard Date().timeIntervalSince(p.fissataAlle) > 0.8 else { return }   // la pressione lunga ha appena fissato
            guard let i = cartaSotto(Double(v.startLocation.x), W: W, CW: CW), voci.indices.contains(i) else { return }
            if i != Int(p.offAdesso(Date()).rounded()) { p.vaiA(i, totale: n); return }
            let id = voci[i].id
            p.chiudi(muto: true)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                apri(id)
            }
        }
    }
}

/// Una carta: la foto della pagina (velata di ciano, con le righe di scansione e un riflesso) e sopra la sua icona.
private struct CartaPagina: View {
    let foto: UIImage?
    let icona: String
    let cur: Bool
    let lum: Double

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 4)
        // 13.8 (4) (il signore, 22 nov 12:12, con la foto di una pagina olografica sopra JARVIS: «le carte vanno rese trasparenti
        // olografiche, più luminose quando selezionate; trasparenze vere»): la carta non ha più il fondo pieno né il nero dei lati:
        // è la pagina vera in versione olografica (la foto, la tinta ciano leggera, le righe), e attraverso si vede quello che c'è
        // dietro. Al centro, selezionata: la pagina quasi piena, più luminosa, il bordo acceso. Ai lati: più tenue e trasparente.
        // L'icona della sezione resta solo sulle carte senza foto (quelle che iOS non riesce a fotografare).
        ZStack {
            // 12:06 («alcune pagine non sono uguali di altezza»): la carta è sempre CW × CH, la foto non le dà mai la sua misura
            Color(red: 3 / 255, green: 13 / 255, blue: 16 / 255).opacity(cur ? 0.22 : 0.32)
                .overlay(alignment: .top) {
                    if let foto {
                        Image(uiImage: foto)
                            .resizable()
                            .scaledToFill()
                            .opacity(cur ? 0.92 : 0.5)
                    }
                }
                .clipped()
            Olo.azzurro.blendMode(.color).opacity(cur ? 0.3 : 0.5)
            VeloCarta()
            if foto == nil {
                GlifoSezione(icona: icona, lato: 13)
                    .foregroundStyle(Olo.ciano)
                    .shadow(color: Olo.azzurro, radius: 2)
            }
        }
        .compositingGroup()                                        // la tinta colora la pagina, non quello che c'è dietro
        .brightness(cur ? 0.12 : 0)
        .opacity(cur ? 1 : max(0.35, lum))                         // ai lati più tenue (prima un velo nero: la carta diventava piena)
        .clipShape(forma)
        .overlay(forma.strokeBorder(Olo.ciano.opacity(cur ? 0.8 : 0.3), lineWidth: 1))
        .overlay { if cur { forma.stroke(Olo.azzurro.opacity(0.22), lineWidth: 6).blur(radius: 5).clipShape(forma) } }
        .shadow(color: Olo.azzurro.opacity(cur ? 0.45 : 0), radius: 6)
    }
}

/// Il velo della miniatura: un riflesso in diagonale e le righe di scansione (1 punto scuro ogni 3).
private struct VeloCarta: View {
    var body: some View {
        Canvas { gc, size in
            let W = Double(size.width), H = Double(size.height)
            let a = 120.0 * .pi / 180, dx = sin(a), dy = -cos(a), l = abs(W * dx) + abs(H * dy)
            let c = CGPoint(x: W / 2, y: H / 2)
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(stops: [.init(color: Olo.azzurro.opacity(0.2), location: 0), .init(color: Olo.azzurro.opacity(0), location: 0.38),
                                 .init(color: Olo.azzurro.opacity(0), location: 0.7), .init(color: Olo.azzurro.opacity(0.12), location: 1)]),
                startPoint: CGPoint(x: c.x - dx * l / 2, y: c.y - dy * l / 2), endPoint: CGPoint(x: c.x + dx * l / 2, y: c.y + dy * l / 2)))
            var righe = Path()
            var y = 0.0
            while y < H { righe.addRect(CGRect(x: 0, y: H - y - 1, width: W, height: 1)); y += 3 }
            gc.fill(righe, with: .color(.black.opacity(0.3)))
        }
        .allowsHitTesting(false)
    }
}

/// Il Cover Flow del mockup: la carta `d` posti dal centro si sposta di lato, va indietro e gira di 62° attorno al suo asse, con la
/// prospettiva di 150 punti centrata sul libro (come `perspective: 150px` e `rotateY` del mockup).
nonisolated private struct CoverFlow: GeometryEffect {
    let d: Double
    let cw: Double
    let ch: Double

    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let ad = abs(d), a = min(1, ad), sg: Double = d < 0 ? -1 : (d > 0 ? 1 : 0)
        let x = sg * (a * cw * 0.64 + max(0, ad - 1) * cw * 0.26)
        let rot = -sg * a * 62 * .pi / 180
        let z = -a * 22 - max(0, ad - 1) * 4
        let mx = Double(size.width) / 2, my = Double(size.height) / 2
        // dal centro della carta: gira, va di lato e indietro; poi la prospettiva (l'occhio a 150 punti), e di nuovo al suo posto
        var m = CATransform3DMakeTranslation(-mx, -my, 0)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(rot, 0, 1, 0))
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(x, 0, z))
        var prospettiva = CATransform3DIdentity
        prospettiva.m34 = -1 / 150
        m = CATransform3DConcat(m, prospettiva)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(mx, my, 0))
        return ProjectionTransform(m)
    }
}

/// La pagina tirata su col dito (sale, si rimpicciolisce, sfuma) o che vola via verso l'alto, chiusa.
private struct Alza: ViewModifier {
    let dy: CGFloat
    let ch: Double
    let via: Bool
    func body(content: Content) -> some View {
        let u = min(1, max(0, Double(-dy) / (ch * 1.1)))
        content
            .scaleEffect(via ? 0.82 : 1 - 0.18 * u)
            .offset(y: via ? -ch * 1.6 : dy)
            .opacity(via ? 0 : 1 - 0.75 * u)
            .brightness(via ? 0.5 : 0)
    }
}

/// La nascita, come FILO ma dall'angolo in alto a sinistra: una riga che si allunga e poi si apre (scale .2,.04 → 1,.04 → 1,1).
private struct NascitaPagine: ViewModifier, Animatable {
    var fase: Double
    nonisolated var animatableData: Double {
        get { fase }
        set { fase = newValue }
    }
    func body(content: Content) -> some View {
        let p = fase
        let sx = p < 0.45 ? 0.2 + 0.8 * p / 0.45 : 1
        let sy = p < 0.45 ? 0.04 : 0.04 + 0.96 * (p - 0.45) / 0.55
        return content
            .scaleEffect(x: sx, y: sy, anchor: .topLeading)
            .opacity(p < 0.45 ? p / 0.45 : 1)
    }
}

/// Le carte si accendono tremolando dopo la nascita (0,36 s, dopo 0,17 s), con un lampo che si spegne (le tappe del mockup).
private struct TremolioLibro: ViewModifier, Animatable {
    var p: Double
    nonisolated var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let u = min(1, max(0, p))
        let tappe: [(Double, Double)] = [(0, 0), (0.25, 0.8), (0.4, 0.2), (0.55, 0.95), (0.7, 0.5), (1, 1)]
        var o = 1.0
        if u < 1 {
            o = 0
            for k in 1..<tappe.count where u <= tappe[k].0 {
                o = tappe[k - 1].1 + (tappe[k].1 - tappe[k - 1].1) * (u - tappe[k - 1].0) / (tappe[k].0 - tappe[k - 1].0)
                break
            }
        }
        return content
            .opacity(o)
            .brightness(u < 1 ? 0.6 * (1 - u) : 0)
    }
}

/// Chiusa da lui: scivola verso il bordo sinistro (−115 %) e sfuma; da sola: si stringe in una riga di luce (al 60 %) e poi
/// sparisce stringendosi anche in largo, come il mockup. `p` va da 0 a 1 nei 0,24 s della chiusura.
private struct ChiusuraPagine: ViewModifier, Animatable {
    var p: Double
    let muto: Bool
    nonisolated var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let q = min(1, max(0, p))
        let sy = muto ? (q < 0.6 ? 1 - 0.97 * q / 0.6 : 0.03) : 1
        let sx = muto ? (q < 0.6 ? 1 : 1 - 0.7 * (q - 0.6) / 0.4) : 1
        let o = muto ? (q < 0.6 ? 1 - 0.1 * q / 0.6 : 0.9 * (1 - (q - 0.6) / 0.4)) : 1 - q
        let via = muto ? 0 : q
        return content
            .scaleEffect(x: sx, y: sy, anchor: .center)
            .visualEffect { c, g in c.offset(x: -g.size.width * 1.15 * via) }
            .opacity(o)
    }
}

/// Il simbolo di una sezione, come sulla corona (IconaPila, senza la cornice), grande `lato`.
private struct GlifoSezione: View {
    let icona: String
    let lato: CGFloat
    var body: some View {
        Group {
            switch icona {
            case "profiler": IconaProfiler().scaleEffect(lato / 15)
            case "satellite": IconaSatellite(lato: lato)
            case "social": IconaSocial().scaleEffect(lato / 15)
            case "studio": IconaStudio(pieno: true).frame(width: lato, height: lato)
            case "vinile": IconaVinile().frame(width: lato, height: lato)
            case "archivio": IconaArchivio().frame(width: 22, height: 22).scaleEffect(lato / 22)
            case "costi":
                if UIImage(named: "langfuse-logo") != nil {
                    Image("langfuse-logo").resizable().renderingMode(.template).scaledToFit().frame(width: lato, height: lato)
                } else {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: lato * 0.95))
                }
            default:
                if icona.hasPrefix("logo:") {
                    Image(String(icona.dropFirst(5))).resizable().renderingMode(.template).scaledToFit().frame(width: lato, height: lato)
                } else {
                    Image(systemName: icona).font(.system(size: lato * 0.95))
                }
            }
        }
        .symbolRenderingMode(.monochrome)
        .frame(width: lato, height: lato)
        .accessibilityHidden(true)
    }
}

/// I simboli piccoli della riga di stato (come il mockup): il telefono, l'orologio, le onde del Wi-Fi.
private struct GlifoTab: View {
    enum Disegno { case telefono, orologio, onde }
    let disegno: Disegno
    var body: some View {
        Canvas { gc, size in
            let (vw, vh): (Double, Double) = disegno == .telefono ? (8, 14) : (disegno == .orologio ? (10, 14) : (14, 10))
            let k = min(Double(size.width) / vw, Double(size.height) / vh)
            var g = gc
            g.scaleBy(x: k, y: k)
            let colore = GraphicsContext.Shading.color(Olo.ciano)
            switch disegno {
            case .telefono:
                g.stroke(Path(roundedRect: CGRect(x: 1, y: 0.8, width: 6, height: 12.4), cornerRadius: 1.6), with: colore, lineWidth: 1.1)
                var p = Path(); p.move(to: CGPoint(x: 3, y: 2.4)); p.addLine(to: CGPoint(x: 5, y: 2.4))
                g.stroke(p, with: colore, style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            case .orologio:
                g.stroke(Path(roundedRect: CGRect(x: 1.5, y: 3, width: 7, height: 8), cornerRadius: 2), with: colore, lineWidth: 1.1)
                var p = Path()
                p.move(to: CGPoint(x: 3.2, y: 3)); p.addLine(to: CGPoint(x: 3.6, y: 0.8)); p.addLine(to: CGPoint(x: 6.4, y: 0.8)); p.addLine(to: CGPoint(x: 6.8, y: 3))
                p.move(to: CGPoint(x: 3.2, y: 11)); p.addLine(to: CGPoint(x: 3.6, y: 13.2)); p.addLine(to: CGPoint(x: 6.4, y: 13.2)); p.addLine(to: CGPoint(x: 6.8, y: 11))
                g.stroke(p, with: colore, lineWidth: 0.9)
            case .onde:
                var p = Path()
                for (r, y, meta) in [(8.6, 3.6, 6.0), (5.6, 5.8, 4.0), (2.6, 8.0, 2.0)] as [(Double, Double, Double)] {
                    // un arco da (7 − meta, y) a (7 + meta, y) che sale, come «a r r 0 0 1» del mockup
                    let cy = y + sqrt(max(0, r * r - meta * meta))
                    let a0 = atan2(y - cy, (7 - meta) - 7), a1 = atan2(y - cy, (7 + meta) - 7)
                    p.move(to: CGPoint(x: 7 - meta, y: y))
                    p.addArc(center: CGPoint(x: 7, y: cy), radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
                }
                g.stroke(p, with: colore, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
        .shadow(color: Olo.azzurro.opacity(0.8), radius: 1.5)
        .accessibilityHidden(true)
    }
}
#endif
