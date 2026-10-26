#if os(iOS)
import SwiftUI
import Combine
import SceneKit
import UIKit
import simd
#if canImport(RoomPlan)
import RoomPlan
import ARKit
import CoreImage
import ImageIO
#endif

/// «Guarda» mentre LiDAR scansiona: la foto si prende dalla fotocamera che LiDAR sta già usando,
/// senza aprire Occhi (che le porterebbe via la fotocamera e lascerebbe la scansione al nero).
/// nil quando non c'è una scansione in corso: allora «guarda» apre Occhi come sempre.
enum OcchiLidar {
    static var scatta: (() -> Data?)?
}

/// LiDAR aperto: «rifai la scansione» la fa ripartire, e «scansione» non apre lo Scanner dei codici a barre.
enum LidarAperta {
    static var aperta = false
    /// Aperta a voce su un modo («Jarvis, metro laser»): LiDAR parte già lì.
    static var richiesta: (modo: ModoLidar, nome: String?)?

    /// «Jarvis, rifai la scansione», «riprova la scansione», «nuova scansione», «ricomincia».
    static func eRifai(_ frase: String) -> Bool {
        let t = frase.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression)
            .split(separator: " ").map(String.init).filter { !["jarvis", "giarvis", "jervis"].contains($0) }
        guard !t.isEmpty, t.count <= 6 else { return false }
        let verbi = ["rifai", "rifacciamo", "riprova", "riproviamo", "ricomincia", "ricominciamo", "riparti", "ripartiamo", "ripeti", "nuova", "rifare"]
        if t.count == 1 { return ["ricomincia", "riprova", "riparti", "rifai", "ricominciamo", "riproviamo"].contains(t[0]) }
        return t.contains(where: { verbi.contains($0) }) && t.contains(where: { $0.hasPrefix("scansion") || $0 == "scansiona" || $0 == "da" || $0 == "capo" })
    }
}

extension Notification.Name {
    static let jarvisRifaiLidar = Notification.Name("jarvisRifaiLidar")
}

// MARK: - LiDAR (STRUMENTI)
// La scansione di una stanza con il LiDAR dell'iPhone (RoomPlan di Apple): pareti, porte, finestre, aperture e mobili.
// Durante la scansione il disegno dal vivo è quello di Apple; il risultato è di JARVIS: pianta ciano con le misure,
// ologramma 3D che ruota, misure, capienza indicativa, archivio, condivisione e «Chiedi» a JARVIS.
// Tutto resta sul telefono (Documenti › LiDAR): niente cloud, niente costi.

/// Un tratto sulla pianta, visto dall'alto (metri: x e z del mondo).
nonisolated struct TrattoPianta: Codable, Hashable, Sendable {
    var ax: Double, az: Double, bx: Double, bz: Double
    var basso: Double? = nil      // porte e finestre: da che altezza (m dal pavimento)…
    var alto: Double? = nil       // …a che altezza
    var lunghezza: Double { hypot(bx - ax, bz - az) }
}

/// Una scansione salvata.
nonisolated struct ScansioneLidar: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var data = Date()
    var nome: String
    var area: Double              // m², dal pavimento (0 se il pavimento non è stato riconosciuto)
    var perimetro: Double         // m, somma delle pareti
    var altezza: Double           // m
    var pareti: [TrattoPianta]
    var porte: [TrattoPianta]
    var finestre: [TrattoPianta]
    var aperture: [TrattoPianta]
    var oggetti: [String]         // «tavolo», «divano»…
    var pavimento: [[Double]]? = nil   // il poligono del pavimento (x, z), per il 3D di OLOGRAMMA e TEXTURE
    var volume: Double { area * altezza }
    /// Capienza indicativa: 1,2 persone/m², la densità delle sale da ballo (DM 19/08/1996). Non è la capienza autorizzata.
    var capienza: Int { Int(area * 1.2) }
    var file3D: URL { ArchivioLidar.cartella.appendingPathComponent("\(id.uuidString).usdz") }

    /// Il riassunto da mandare a JARVIS con «Chiedi».
    var riassunto: String {
        var s = "Ho scansionato con il LiDAR «\(nome)»: superficie \(LidarFormato.m2(area)), perimetro \(LidarFormato.m(perimetro)), "
        s += "altezza \(LidarFormato.m(altezza, 2)), volume \(LidarFormato.n(volume, 0)) m³, \(pareti.count) pareti, "
        s += "\(porte.count) porte, \(finestre.count) finestre, \(aperture.count) aperture"
        if !oggetti.isEmpty { s += ", arredi: \(oggetti.joined(separator: ", "))" }
        s += ". Pareti: " + pareti.map { LidarFormato.m($0.lunghezza, 2) }.joined(separator: ", ") + "."
        return s + " Cosa mi dici di questo spazio?"
    }
}

nonisolated enum LidarFormato {
    static func n(_ v: Double, _ d: Int = 1) -> String { v.formatted(.number.precision(.fractionLength(d)).locale(Locale(identifier: "it_IT"))) }
    static func m(_ v: Double, _ d: Int = 1) -> String { n(v, d) + " m" }
    static func m2(_ v: Double) -> String { v > 0 ? n(v) + " m²" : "—" }
    /// «80 cm», «46 cm»: centimetri interi.
    static func cm(_ metri: Double) -> String { "\(Int((metri * 100).rounded())) cm" }
    /// «3° DX», «2° SX», «0°»: la rotazione del bacino (+ verso destra).
    static func bacino(_ gradi: Double) -> String {
        let g = Int(abs(gradi).rounded())
        return g == 0 ? "0°" : "\(g)° \(gradi > 0 ? "DX" : "SX")"
    }
}

/// L'archivio delle scansioni sul telefono.
@MainActor
final class ArchivioLidar: ObservableObject {
    static let condiviso = ArchivioLidar()
    @Published private(set) var scansioni: [ScansioneLidar] = []

    nonisolated static var cartella: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("LiDAR", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var indice: URL { Self.cartella.appendingPathComponent("archivio.json") }

    init() {
        if let d = try? Data(contentsOf: indice), let s = try? JSONDecoder().decode([ScansioneLidar].self, from: d) { scansioni = s }
    }
    func salva(_ s: ScansioneLidar) {
        scansioni.removeAll { $0.id == s.id }
        scansioni.insert(s, at: 0)
        scrivi()
    }
    func cancella(_ s: ScansioneLidar) {
        scansioni.removeAll { $0.id == s.id }
        try? FileManager.default.removeItem(at: s.file3D)
        scrivi()
    }
    func contiene(_ s: ScansioneLidar) -> Bool { scansioni.contains { $0.id == s.id } }
    private func scrivi() { if let d = try? JSONEncoder().encode(scansioni) { try? d.write(to: indice, options: .atomic) } }
}


// MARK: - La sezione (build 23: il menu dei modi, la scansione, il risultato)

struct VistaLidar: View {
    let chiudi: () -> Void
    let chiedi: (String) -> Void
    @EnvironmentObject var jarvis: Jarvis
    @StateObject private var archivio = ArchivioLidar.condiviso
    @State private var fase: Fase = .menu
    @State private var modo: ModoLidar = .stanza              // ogni volta da Interno…
    @State private var corpo: CorpoLidar = .postura
    @State private var stile: StileLidar = .pieno             // …in OLOGRAMMA; la TEXTURE è la seconda scelta
    @State private var risultato: ScansioneLidar?             // Interno
    @State private var risultatoModo: RisultatoModo?          // gli altri modi
    @State private var salvati: Set<UUID> = []
    @State private var vista: Vista = .pianta
    @State private var dalVivo = MisureDalVivo()
    @State private var allestimentoVivo: Allestimento?
    @State private var ultimoAllestimento = Date.distantPast
    @State private var stato = StatoScansione()
    @State private var fermaScansione = false
    @State private var acceso = false                         // dopo «ACCENSIONE SENSORE…» (0,7 s)
    @State private var ancora = false                         // «Fine» toccato troppo presto
    @State private var avviso: String?
    @State private var condivisi: [URL] = []
    @State private var tentativo = 0
    @State private var inizioFine = Date()
    @State private var nomePersona: String?                   // «gemello digitale di Marco»
    @State private var mandando = false                       // MARK X: la scansione sta andando allo Studio

    enum Fase { case menu, scansione, elaboro, risultato, risultatoModo }
    enum Vista: String, CaseIterable { case pianta = "PIANTA", pieno = "OLOGRAMMA", foto = "TEXTURE", archivio = "ARCHIVIO" }

    /// Il modo vero: in Corpo, Postura (lo scheletro) o Texture (la «Statua»).
    private var vero: ModoLidar { modo == .corpo && corpo == .statua ? .statua : modo }

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            GrigliaSfumata()
            VStack(spacing: 0) {
                ChiudiLidar { esci() }
                switch fase {
                case .menu:
                    ScrollView {
                        MenuLidar(modo: $modo, corpo: $corpo, stile: $stile) { avviaScansione() }
                            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
                    }
                case .scansione, .elaboro:
                    schermoScansione.padding(.top, 8)
                case .risultato:
                    schermoRisultato
                case .risultatoModo:
                    if let r = risultatoModo {
                        ScrollView {
                            RisultatoModoVista(r: r, stile: $stile, salvato: salvati.contains(r.id),
                                               salva: { salvaModo(r) },
                                               altra: { pulisciModo(); risultatoModo = nil; fase = .menu },
                                               chiedi: { chiedi(r.domanda) },
                                               studio: { alloStudio(r.modello, modo: r.modo) })
                                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(fase == .scansione || fase == .elaboro)
        .onAppear {
            LidarAperta.aperta = true
            if let r = LidarAperta.richiesta { LidarAperta.richiesta = nil; parti(r.modo, nome: r.nome) }   // aperta a voce già su un modo
        }
        .onDisappear { LidarAperta.aperta = false }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisRifaiLidar)) { _ in   // a voce: la scansione da capo, nello stesso modo
            guard fase != .menu else { return }
            Suoni.tocco()
            avviaScansione()
        }
        .onChange(of: jarvis.azioneLidar) { _, a in
            guard let a else { return }
            jarvis.azioneLidar = nil
            aVoce(a)
        }
    }

    // MARK: Comandi a voce

    /// «Fine scansione», «quanto è grande?», «quanta gente ci sta?», «salva», «mostrami il 3D», e le frasi dei modi («metro laser»…).
    private func aVoce(_ a: ComandoVocale.AzioneLidar) {
        let inScansione = fase == .scansione || fase == .elaboro
        switch a {
        case .fine:
            if fase == .scansione { premiFine() } else if fase == .risultato { vista = .pianta }
        case .misure:
            if fase == .risultatoModo, let r = risultatoModo { jarvis.annuncia(r.annuncio); return }
            if inScansione && vero != .stanza { jarvis.annuncia("Prima finisca la scansione, Sir."); return }
            let area = fase == .risultato ? (risultato?.area ?? 0) : (inScansione ? dalVivo.area : 0)
            guard area > 0 else { jarvis.annuncia(inScansione ? "Il pavimento non l'ho ancora preso, Sir: continui lungo le pareti." : "Non ho una scansione aperta, Sir."); return }
            var frase = "Circa \(LidarFormato.n(area)) metri quadri"
            if fase == .risultato, let s = risultato, s.altezza > 0 { frase += ", alta \(LidarFormato.n(s.altezza, 2)) metri" }
            jarvis.annuncia(frase + ", Sir.")
        case .capienza:
            if fase == .risultatoModo, let c = risultatoModo?.capienza { jarvis.annuncia(c); return }
            let area = fase == .risultato ? (risultato?.area ?? 0) : (inScansione && vero == .stanza ? dalVivo.area : 0)
            guard area > 0 else { jarvis.annuncia(inScansione ? "Mi serve ancora il pavimento, Sir." : "Non ho una scansione aperta, Sir."); return }
            jarvis.annuncia("Circa \(Int(area * 1.2)) persone, Sir, a 1,2 per metro quadro. Quella vera la fissano uscite e commissione.")
        case .salva:
            if fase == .risultatoModo, let r = risultatoModo {
                if salvati.contains(r.id) { jarvis.annuncia("È già nell'archivio, Sir."); return }
                salvaModo(r); jarvis.annuncia("Salvata nell'archivio, Sir."); return
            }
            guard fase == .risultato, let s = risultato else { jarvis.annuncia(inScansione ? "Prima finisca la scansione, Sir." : "Non ho una scansione aperta, Sir."); return }
            if archivio.contiene(s) { jarvis.annuncia("È già nell'archivio, Sir."); return }
            archivio.salva(s)
            jarvis.annuncia("Salvata nell'archivio, Sir.")
        case .tre:
            if fase == .risultato, risultato != nil { vista = .pieno; return }
            if fase == .risultatoModo { return }                                   // il modello 3D è già lì
            jarvis.annuncia(inScansione ? "Prima finisca la scansione, Sir." : "Non ho una scansione aperta, Sir.")
        case .modo(let chiave, let nome):
            guard let m = ModoLidar(rawValue: chiave) else { return }
            if fase == .risultatoModo, let r = risultatoModo, r.modo == m { jarvis.annuncia(r.annuncio); return }   // «dimensioni dell'oggetto» sul risultato
            if fase == .risultato, m == .stanza, risultato != nil { vista = .pianta; return }                    // «dammi la pianta»
            if inScansione, vero == m { return }                                                                 // già al lavoro
            parti(m, nome: nome)
            jarvis.annuncia(SupportoModi.disponibile(m) ? m.annuncioVoce : (Reparto.lidar.annuncio ?? ""))   // senza il sensore: niente «… pronto», c'è la riga arancione
        }
    }

    /// Un modo chiesto a voce: si sceglie e parte subito la scansione.
    private func parti(_ m: ModoLidar, nome: String?) {
        switch m {
        case .statua: modo = .corpo; corpo = .statua
        case .corpo: modo = .corpo; corpo = .postura
        default: modo = m
        }
        nomePersona = nome
        avviaScansione()
    }

    // MARK: Scansione

    /// «Scansiona»: la fotocamera si accende («ACCENSIONE SENSORE…»), dopo 0,7 s il suono della fotocamera e il tasto «Fine».
    private func avviaScansione() {
        pulisciModo()
        risultatoModo = nil
        avviso = SupportoModi.disponibile(vero) ? nil : SupportoModi.avviso(vero)
        fermaScansione = false; ancora = false; acceso = false
        dalVivo = MisureDalVivo(); stato = StatoScansione(); allestimentoVivo = nil
        fase = .scansione
        tentativo += 1
        let mio = tentativo
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard mio == tentativo, fase == .scansione else { return }
            acceso = true
            if avviso == nil { Suoni.aperturaCamera() }                            // sensore pronto: il suono delle sezioni con fotocamera
        }
    }

    private var pronto: Bool {
        switch vero {
        case .stanza, .evento: return dalVivo.chiusa
        default: return stato.pronto
        }
    }
    /// C'è abbastanza per costruire qualcosa? (il secondo «Fine» prima del «FATTO» vale solo così)
    private var haDati: Bool {
        switch vero {
        case .stanza, .evento: return dalVivo.pareti >= 3
        case .statua: return (Int(stato.hud.first ?? "") ?? 0) >= 20
        default: return stato.hud.contains { $0 != "—" }
        }
    }

    /// «Fine»: se non ha ancora finito, «ANCORA UN ATTIMO…» e si continua; toccato di nuovo, chiude con quello che c'è.
    private func premiFine() {
        guard fase == .scansione, acceso, avviso == nil else { return }
        if pronto || (ancora && haDati) {
            inizioFine = Date()
            fase = .elaboro
            fermaScansione = true
        } else {
            ancora = true
        }
    }

    private var testoStato: String {
        if let avviso { return avviso }
        if fase == .elaboro {
            if vero == .statua, let t = stato.testo, t.hasPrefix("ELABORAZIONE") { return t }            // Texture: «ELABORAZIONE… 40%» mentre l'iPhone costruisce il modello
            return vero == .stanza ? "ELABORAZIONE PIANTA…" : "ELABORAZIONE…"
        }
        if !acceso { return "ACCENSIONE SENSORE…" }
        if pronto { return vero == .stanza ? "SALA CHIUSA · TOCCHI FINE" : "FATTO · TOCCHI FINE" }
        if let t = stato.testo { return t }                                    // cosa sta succedendo: «CERCO LA PERSONA…», «INQUADRI ANCHE I PIEDI»…
        if ancora { return vero == .stanza ? "ANCORA UN ATTIMO: MANCANO DELLE PARETI" : "ANCORA UN ATTIMO…" }
        return vero.istruzione
    }

    private var valoriHUD: [String] {
        switch vero {
        case .stanza:
            return ["\(dalVivo.pareti)", dalVivo.area > 0 ? LidarFormato.n(dalVivo.area) : "0,0", dalVivo.altezza > 0 ? LidarFormato.m(dalVivo.altezza, 2) : "—"]
        case .evento:
            guard let a = allestimentoVivo else { return ["—", "—", "—"] }
            return ["\(a.stand.count)", LidarFormato.m(Allestimento.passaggio), "\(a.uscite.count)"]
        default:
            return stato.hud
        }
    }

    private var schermoScansione: some View {
        CorniceScansione(etichette: vero.hud, valori: valoriHUD, stato: testoStato, avviso: avviso != nil,
                         mostraFine: acceso && fase == .scansione && avviso == nil,
                         mostraRiprova: avviso != nil && SupportoModi.disponibile(vero),
                         fine: premiFine, riprova: avviaScansione) {
            camera.id(tentativo)
        }
    }

    @ViewBuilder private var camera: some View {
        if !SupportoModi.disponibile(vero) {
            Color.clear
        } else {
            switch vero {
            case .stanza, .evento:
                #if canImport(RoomPlan)
                CatturaStanza(ferma: $fermaScansione,
                              aggiorna: { dalVivo = $0 },
                              vivo: vero == .evento ? { s in setupVivo(s) } : nil,
                              finita: { s in finitaStanza(s) },
                              errore: { e in errore(e) })
                #else
                Color.clear
                #endif
            case .statua:
                CatturaStatua(ferma: $fermaScansione, aggiorna: { stato = $0 }, elaboro: { fase = .elaboro },
                              finita: { mostraModo($0) }, errore: { errore($0) }, nome: nomePersona)
            default:
                CatturaAR(modo: vero, ferma: $fermaScansione, aggiorna: { stato = $0 }, finita: { mostraModo($0) }, errore: { errore($0) })
            }
        }
    }

    /// Setup: mentre la stanza si forma, l'allestimento si ricalcola (una volta al secondo).
    private func setupVivo(_ s: ScansioneLidar) {
        guard Date().timeIntervalSince(ultimoAllestimento) > 1 else { return }
        ultimoAllestimento = Date()
        allestimentoVivo = Allestimento.calcola(StanzaScena(s))
    }

    private func errore(_ e: String) {
        avviso = e
        fase = .scansione
    }

    /// La stanza è pronta: «ELABORAZIONE PIANTA…» resta almeno 0,9 s (Setup: «ELABORAZIONE…» 0,8 s), come nel mockup.
    private func finitaStanza(_ s: ScansioneLidar) {
        let resta = (vero == .evento ? 0.8 : 0.9) - Date().timeIntervalSince(inizioFine)
        Task {
            if resta > 0 { try? await Task.sleep(for: .seconds(resta)) }
            guard fase == .elaboro else { return }
            if vero == .evento {
                try? FileManager.default.removeItem(at: s.file3D)                    // a Setup il modello di Apple non serve
                mostraModo(RisultatoModo.evento(s))
            } else {
                mostra(s)
            }
        }
    }

    private func mostra(_ s: ScansioneLidar) {
        apri(s)
        withAnimation(.easeOut(duration: 0.3)) { fase = .risultato }
        Suoni.schedaPronta()
    }
    private func mostraModo(_ r: RisultatoModo) {
        guard fase == .elaboro || fase == .scansione else { return }
        risultatoModo = r
        withAnimation(.easeOut(duration: 0.3)) { fase = .risultatoModo }
        Suoni.schedaPronta()
    }

    private func salvaModo(_ r: RisultatoModo) {
        ArchivioModi.condiviso.salva(r)
        salvati.insert(r.id)
    }
    /// Un modello 3D di Texture non salvato non resta a occupare spazio.
    private func pulisciModo() {
        if let r = risultatoModo, !salvati.contains(r.id), let f = r.file { try? FileManager.default.removeItem(at: f) }
    }

    /// MARK X · STUDIO: la scansione vera va sul banco dello Studio (LidarStudio.swift): plastico della sala, terreno, oggetto,
    /// statuina, sagoma. Si legge tutto prima di uscire (uscendo, il modello di Texture non salvato si cancella), poi LiDAR si chiude.
    private func alloStudio(_ m: ModelloScena, modo: ModoLidar) {
        guard modo != .misura else { jarvis.annuncia(LidarAlloStudio.frase(.misura)); return }
        guard !mandando else { return }
        mandando = true
        Task {
            let esito = await Task.detached(priority: .userInitiated) { LidarAlloStudio.dati(m) }.value
            mandando = false
            guard case .success(let json) = esito else {
                jarvis.annuncia("Questa scansione non basta per lo Studio, Sir: la rifaccia più completa.")
                return
            }
            jarvis.annuncia(LidarAlloStudio.frase(modo))
            esci()
            try? await Task.sleep(for: .milliseconds(650))          // il tempo che LiDAR si chiuda
            PaginaMarkX.apri(AperturaPagina(sezione: "Studio", lidar: json))
        }
    }

    /// Uscendo, il modello 3D di una scansione non salvata si cancella: non resta a occupare spazio.
    private func esci() {
        if let r = risultato, !archivio.contiene(r) { try? FileManager.default.removeItem(at: r.file3D) }
        pulisciModo()
        chiudi()
    }
    private func apri(_ s: ScansioneLidar) {
        risultato = s
        vista = .pianta
        condivisi = LidarCondivisione.file(s)
    }

    // MARK: Risultato di Interno (PIANTA · OLOGRAMMA · TEXTURE · ARCHIVIO)

    private var schermoRisultato: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TestataScheda(titolo: "LiDAR", sottotitolo: risultato?.nome.lowercased() ?? "archivio", icona: "cube.transparent", tinta: .ciano)
                HStack(spacing: 6) {
                    ForEach(Vista.allCases, id: \.self) { v in ChipLidar(testo: v.rawValue, premuto: vista == v) { vista = v } }
                }
                TavolaLidar(proporzione: vista == .archivio ? nil : 720 / 560) { tavola }
                if let s = risultato { pannelli(s) }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
    }

    @ViewBuilder private var tavola: some View {
        switch vista {
        case .pianta:
            if let s = risultato { PiantaLidar(scansione: s) } else { vuoto("Nessuna scansione aperta.\nNe apra una dall'archivio.") }
        case .pieno, .foto:
            if let s = risultato {
                Vista3DLidar(modello: .stanza(StanzaScena(s)), fase: .risultato, stile: vista == .foto ? .foto : .pieno).id(s.id)
            } else { vuoto("Nessuna scansione aperta.\nNe apra una dall'archivio.") }
        case .archivio:
            archivioVista
        }
    }

    private func vuoto(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13)).foregroundStyle(Color.tenue).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 140).padding()
    }

    @ViewBuilder private var archivioVista: some View {
        if archivio.scansioni.isEmpty {
            vuoto("Ancora nessuna scansione salvata.\nTocchi «Salva» per tenerla qui.")
        } else {
            VStack(spacing: 0) {
                ForEach(archivio.scansioni) { s in
                    HStack {
                        Button { Suoni.tocco(); apri(s) } label: {
                            HStack {
                                Text(s.nome).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo).lineLimit(1)
                                Spacer()
                                Text("\(LidarFormato.m2(s.area)) · \(s.data.formatted(date: .numeric, time: .shortened))")
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue)
                            }
                        }
                        Button { Suoni.tocco(); if risultato?.id == s.id { risultato = nil }; archivio.cancella(s) } label: {
                            Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Color.tenue).padding(.leading, 8)
                        }
                        .accessibilityLabel("Cancella \(s.nome)")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    if s.id != archivio.scansioni.last?.id { Divider().overlay(Color.ciano.opacity(0.12)) }
                }
            }
            .frame(minHeight: 140, alignment: .top)
        }
    }

    private func pannelli(_ s: ScansioneLidar) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Pannello(titolo: "MISURE", tinta: .ciano) {
                RigaHUD("Superficie", LidarFormato.m2(s.area))
                RigaHUD("Perimetro", LidarFormato.m(s.perimetro))
                RigaHUD("Altezza", LidarFormato.m(s.altezza, 2))
                RigaHUD("Volume", s.area > 0 ? LidarFormato.n(s.volume, 0) + " m³" : "—")
                RigaHUD("Pareti · porte · finestre", "\(s.pareti.count) · \(s.porte.count) · \(s.finestre.count)")
            }
            Pannello(titolo: "CAPIENZA", tinta: .ciano) {
                RigaHUD("Indicativa, 1,2 persone/m²", s.area > 0 ? "\(s.capienza) persone" : "—")
                Text("Densità delle sale da ballo (DM 19/08/1996). La capienza vera la fissano uscite e commissione di vigilanza.")
                    .font(.system(size: 11)).foregroundStyle(Color.tenue).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TastoLidar(testo: archivio.contiene(s) ? "Salvata" : "Salva", attivo: !archivio.contiene(s)) { archivio.salva(s) }
                ShareLink(items: condivisi) {
                    Text("CONDIVIDI").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 11).padding(.horizontal, 8).foregroundStyle(Color.ciano)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
                }
                .simultaneousGesture(TapGesture().onEnded { Suoni.tocco() })
                TastoLidarStudio { alloStudio(.stanza(StanzaScena(s)), modo: .stanza) }     // MARK X: la sala vera diventa un plastico
                TastoLidar(testo: "Chiedi") { chiedi(s.riassunto) }
            }
        }
    }
}


/// I numeri che salgono mentre scansiona.
nonisolated struct MisureDalVivo: Equatable, Sendable { var pareti = 0; var area = 0.0; var altezza = 0.0; var chiusa = false }

enum LidarSupporto {
    static var disponibile: Bool {
        #if canImport(RoomPlan)
        if ProcessInfo.processInfo.isiOSAppOnMac { return false }
        return RoomCaptureSession.isSupported
        #else
        return false
        #endif
    }
}

// MARK: - La pianta (Canvas): pareti ciano con le misure, porte in arancio con l'arco, finestre a doppia linea

struct PiantaLidar: View {
    let scansione: ScansioneLidar
    var animata = true
    @State private var stampa: CGFloat = 0

    var body: some View {
        Canvas { gc, size in
            let tutti = scansione.pareti + scansione.porte + scansione.finestre + scansione.aperture
            guard !tutti.isEmpty else { return }
            let xs = tutti.flatMap { [$0.ax, $0.bx] }, zs = tutti.flatMap { [$0.az, $0.bz] }
            let mx = xs.min()!, Mx = xs.max()!, mz = zs.min()!, Mz = zs.max()!
            let k = min((size.width - 110) / max(Mx - mx, 0.5), (size.height - 60) / max(Mz - mz, 0.5))
            let ox = (size.width - (Mx - mx) * k) / 2, oz = (size.height - (Mz - mz) * k) / 2
            func p(_ x: Double, _ z: Double) -> CGPoint { CGPoint(x: ox + (x - mx) * k, y: oz + (z - mz) * k) }
            // griglia da un metro
            var griglia = Path()
            var gx = ceil(mx); while gx <= Mx { griglia.move(to: p(gx, mz)); griglia.addLine(to: p(gx, Mz)); gx += 1 }
            var gz = ceil(mz); while gz <= Mz { griglia.move(to: p(mx, gz)); griglia.addLine(to: p(Mx, gz)); gz += 1 }
            gc.stroke(griglia, with: .color(Color.ciano.opacity(0.07)), lineWidth: 0.5)
            // pareti
            var muri = Path()
            for w in scansione.pareti { muri.move(to: p(w.ax, w.az)); muri.addLine(to: p(w.bx, w.bz)) }
            var bagliore = gc; bagliore.addFilter(.blur(radius: 4))
            bagliore.stroke(muri, with: .color(Color.ciano.opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            gc.stroke(muri, with: .color(Color.ciano), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            // finestre e aperture
            for f in scansione.finestre { doppia(gc, p(f.ax, f.az), p(f.bx, f.bz), .white.opacity(0.85)) }
            for a in scansione.aperture {
                var s = Path(); s.move(to: p(a.ax, a.az)); s.addLine(to: p(a.bx, a.bz))
                gc.stroke(s, with: .color(Color.fondo), lineWidth: 4)
                gc.stroke(s, with: .color(Color.ciano.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            // porte: varco e arco d'apertura
            for d in scansione.porte {
                let a = p(d.ax, d.az), b = p(d.bx, d.bz)
                var v = Path(); v.move(to: a); v.addLine(to: b); gc.stroke(v, with: .color(Color.fondo), lineWidth: 4)
                let r = hypot(b.x - a.x, b.y - a.y), ang = atan2(b.y - a.y, b.x - a.x)
                var arco = Path(); arco.move(to: a); arco.addLine(to: b)
                arco.addArc(center: a, radius: r, startAngle: .radians(ang), endAngle: .radians(ang + .pi / 2), clockwise: false)
                arco.closeSubpath()
                gc.stroke(arco, with: .color(Color(red: 1, green: 0.7, blue: 0.35).opacity(0.9)), lineWidth: 1)
            }
            // misure delle pareti, fuori dal muro
            let cx = (mx + Mx) / 2, cz = (mz + Mz) / 2
            for w in scansione.pareti where w.lunghezza >= 0.4 {
                let a = p(w.ax, w.az), b = p(w.bx, w.bz)
                let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), c = p(cx, cz)
                let l = max(hypot(b.x - a.x, b.y - a.y), 1)
                var nx = -(b.y - a.y) / l, ny = (b.x - a.x) / l
                if (m.x - c.x) * nx + (m.y - c.y) * ny < 0 { nx = -nx; ny = -ny }        // la normale verso l'esterno
                let fuori: CGFloat = abs(nx) > 0.7 ? 26 : 10
                gc.draw(Text(LidarFormato.m(w.lunghezza, 2)).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color.ciano),
                        at: CGPoint(x: m.x + nx * fuori, y: m.y + ny * fuori))
            }
        }
        .mask(alignment: .top) { GeometryReader { g in Rectangle().frame(height: g.size.height * (animata ? stampa : 1)) } }   // si stampa dall'alto, come le schede
        .onAppear { guard animata else { return }; stampa = 0; withAnimation(.easeOut(duration: 0.9)) { stampa = 1 } }
        .id(scansione.id)
    }

    private func doppia(_ gc: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ colore: Color) {
        let l = max(hypot(b.x - a.x, b.y - a.y), 1), nx = -(b.y - a.y) / l * 2.5, ny = (b.x - a.x) / l * 2.5
        var s = Path(); s.move(to: a); s.addLine(to: b); gc.stroke(s, with: .color(Color.fondo), lineWidth: 5)
        for o in [-1.0, 1.0] {
            var q = Path(); q.move(to: CGPoint(x: a.x + nx * o, y: a.y + ny * o)); q.addLine(to: CGPoint(x: b.x + nx * o, y: b.y + ny * o))
            gc.stroke(q, with: .color(colore), lineWidth: 1)
        }
    }
}

// MARK: - Condivisione: la pianta in PNG e il modello 3D (USDZ)

enum LidarCondivisione {
    @MainActor static func file(_ s: ScansioneLidar) -> [URL] {
        var out: [URL] = []
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("\(s.nome.replacingOccurrences(of: "/", with: "-")) - pianta.png")
        let r = ImageRenderer(content: PiantaLidarStampa(scansione: s))
        r.scale = 3
        if let img = r.uiImage, let d = img.pngData(), (try? d.write(to: png)) != nil { out.append(png) }
        if FileManager.default.fileExists(atPath: s.file3D.path) { out.append(s.file3D) }
        return out
    }
}

/// La pianta per la condivisione: su fondo scuro, con titolo e misure.
private struct PiantaLidarStampa: View {
    let scansione: ScansioneLidar
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("J.A.R.V.I.S. · LIDAR").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(Color.ciano)
            Text(scansione.nome).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            PiantaStatica(scansione: scansione).frame(width: 600, height: 440)
            Text("\(LidarFormato.m2(scansione.area)) · perimetro \(LidarFormato.m(scansione.perimetro)) · altezza \(LidarFormato.m(scansione.altezza, 2))")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue)
        }
        .padding(20).background(Color.fondo)
    }
}
/// La stessa pianta, senza l'animazione di stampa (per l'immagine).
private struct PiantaStatica: View {
    let scansione: ScansioneLidar
    var body: some View { PiantaLidar(scansione: scansione, animata: false) }
}

// MARK: - La cattura (RoomPlan)

#if canImport(RoomPlan)
/// La vista di Apple per la scansione, con i numeri dal vivo e il risultato elaborato da RoomBuilder.
struct CatturaStanza: UIViewRepresentable {
    @Binding var ferma: Bool
    let aggiorna: (MisureDalVivo) -> Void
    let vivo: ((ScansioneLidar) -> Void)?          // Setup: la stanza com'è adesso, per posare l'allestimento mentre si forma
    let finita: (ScansioneLidar) -> Void
    let errore: (String) -> Void

    func makeCoordinator() -> Regista { Regista(aggiorna: aggiorna, vivo: vivo, finita: finita, errore: errore) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let v = RoomCaptureView(frame: .zero)
        v.delegate = context.coordinator
        v.captureSession.delegate = context.coordinator
        context.coordinator.vista = v
        v.captureSession.run(configuration: RoomCaptureSession.Configuration())
        OcchiLidar.scatta = { [weak v] in v.flatMap { CatturaStanza.fotogramma($0) } }
        return v
    }
    func updateUIView(_ v: RoomCaptureView, context: Context) {
        if ferma && !context.coordinator.fermata {
            context.coordinator.fermata = true
            OcchiLidar.scatta = nil                    // scansione finita: «guarda» torna a Occhi
            v.captureSession.stop()
        }
    }
    static func dismantleUIView(_ v: RoomCaptureView, coordinator: Regista) {
        coordinator.annullata = true
        OcchiLidar.scatta = nil
        if !coordinator.fermata { v.captureSession.stop() }
        v.captureSession.arSession.pause()             // la fotocamera di RoomPlan si spegne del tutto prima del risultato 3D
    }

    /// L'immagine che la fotocamera di LiDAR sta vedendo adesso, dritta (verticale) e in JPEG, lato lungo massimo 1600 px.
    static func fotogramma(_ v: RoomCaptureView) -> Data? {
        guard let frame = v.captureSession.arSession.currentFrame else { return nil }
        return LidarFoto.jpeg(frame)
    }

    /// Riceve gli aggiornamenti della sessione e il risultato della vista. NSCoding lo chiede il protocollo di Apple.
    @objc(JarvisRegistaLidar)                   // nome stabile: RoomCaptureViewDelegate passa da NSCoding
    nonisolated final class Regista: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, @unchecked Sendable {
        let aggiorna: (MisureDalVivo) -> Void
        let vivo: ((ScansioneLidar) -> Void)?
        let finita: (ScansioneLidar) -> Void
        let errore: (String) -> Void
        weak var vista: RoomCaptureView?
        var fermata = false
        var annullata = false                       // chiusa a metà: niente pianta, niente suono, niente file

        init(aggiorna: @escaping (MisureDalVivo) -> Void, vivo: ((ScansioneLidar) -> Void)?, finita: @escaping (ScansioneLidar) -> Void,
             errore: @escaping (String) -> Void) {
            self.aggiorna = aggiorna; self.vivo = vivo; self.finita = finita; self.errore = errore
        }
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {}

        // i numeri dal vivo
        nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            let m = MisureDalVivo(pareti: room.walls.count, area: Misuratore.area(room), altezza: Misuratore.altezza(room),
                                  chiusa: Misuratore.chiusa(room))
            let adesso = vivo != nil ? Misuratore.scansione(room) : nil
            Task { @MainActor in
                self.aggiorna(m)
                if let adesso { self.vivo?(adesso) }
            }
        }

        // la scansione è finita: niente schermata finale di Apple, il risultato lo costruisce JARVIS
        nonisolated func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
            if annullata { return false }
            if let error {
                Task { @MainActor in self.errore("SCANSIONE INTERROTTA · \(error.localizedDescription.uppercased())") }
                return false
            }
            Task {
                do {
                    let stanza = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: roomDataForProcessing)
                    if self.annullata { return }
                    let pronta = Misuratore.scansione(stanza)
                    try? stanza.export(to: pronta.file3D, exportOptions: .parametric)   // il modello 3D per l'ologramma e la condivisione
                    await MainActor.run { if !self.annullata { self.finita(pronta) } }
                } catch {
                    await MainActor.run { if !self.annullata { self.errore("NON RIESCO A COSTRUIRE LA PIANTA · RIPROVI") } }
                }
            }
            return false
        }
        nonisolated func captureView(didPresent processedResult: CapturedRoom, error: Error?) {}
    }
}

/// Le misure da una stanza di RoomPlan, viste dall'alto.
nonisolated enum Misuratore {
    static func tratto(_ s: CapturedRoom.Surface) -> TrattoPianta { tratto(s, pavimento: nil) }
    /// Con il pavimento: anche da che altezza a che altezza (porte e finestre).
    static func tratto(_ s: CapturedRoom.Surface, pavimento: Float?) -> TrattoPianta {
        let t = s.transform, c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let dir = simd_normalize(SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)), l = s.dimensions.x / 2
        let a = c - dir * l, b = c + dir * l
        var r = TrattoPianta(ax: Double(a.x), az: Double(a.z), bx: Double(b.x), bz: Double(b.z))
        if let pavimento, s.dimensions.y > 0 {
            r.basso = Double(max(0, c.y - s.dimensions.y / 2 - pavimento))
            r.alto = Double(c.y + s.dimensions.y / 2 - pavimento)
        }
        return r
    }
    /// L'altezza del pavimento: il suo piano, o il piede più basso delle pareti.
    static func quotaPavimento(_ r: CapturedRoom) -> Float? {
        if let f = r.floors.first { return f.transform.columns.3.y }
        return r.walls.map { $0.transform.columns.3.y - $0.dimensions.y / 2 }.min()
    }
    /// La sala è chiusa: almeno tre pareti, e ogni capo di parete tocca (entro 35 cm) il capo di un'altra.
    static func chiusa(_ r: CapturedRoom) -> Bool {
        let t = r.walls.map(tratto)
        guard t.count >= 3 else { return false }
        let capi = t.enumerated().flatMap { i, w in [(i, SIMD2(w.ax, w.az)), (i, SIMD2(w.bx, w.bz))] }
        return capi.allSatisfy { i, p in capi.contains { j, q in j != i && simd_distance(p, q) < 0.35 } }
    }
    /// Il poligono del pavimento nel mondo (x, z), dal pavimento più grande.
    static func poligonoPavimento(_ r: CapturedRoom) -> [[Double]]? {
        let poli = r.floors.map { f in f.polygonCorners.map { v -> [Double] in
            let w = f.transform * SIMD4<Float>(v.x, v.y, v.z, 1)
            return [Double(w.x), Double(w.z)]
        } }.filter { $0.count >= 3 }
        return poli.max { GeometriaPiana.area($0.map { SIMD2($0[0], $0[1]) }) < GeometriaPiana.area($1.map { SIMD2($0[0], $0[1]) }) }
    }
    /// Superficie del pavimento (m²): i vertici del pavimento portati nel mondo, area col metodo dei lacci.
    static func area(_ r: CapturedRoom) -> Double {
        var tot = 0.0
        for f in r.floors {
            let p = f.polygonCorners.map { v -> SIMD2<Double> in
                let w = f.transform * SIMD4<Float>(v.x, v.y, v.z, 1)
                return SIMD2(Double(w.x), Double(w.z))
            }
            guard p.count >= 3 else {                              // pavimento senza poligono: il rettangolo
                tot += Double(f.dimensions.x * max(f.dimensions.y, f.dimensions.z)); continue
            }
            var a = 0.0
            for i in 0..<p.count { let j = (i + 1) % p.count; a += p[i].x * p[j].y - p[j].x * p[i].y }
            tot += abs(a) / 2
        }
        return tot
    }
    static func altezza(_ r: CapturedRoom) -> Double {
        let h = r.walls.map { Double($0.dimensions.y) }.sorted()
        return h.isEmpty ? 0 : h[h.count / 2]                       // la mediana: un muretto non abbassa la stanza
    }
    static func scansione(_ r: CapturedRoom) -> ScansioneLidar {
        let pareti = r.walls.map(tratto), pav = quotaPavimento(r)
        return ScansioneLidar(nome: "Stanza del " + Date().formatted(date: .numeric, time: .shortened),
                              area: area(r), perimetro: pareti.reduce(0) { $0 + $1.lunghezza }, altezza: altezza(r),
                              pareti: pareti, porte: r.doors.map { tratto($0, pavimento: pav) }, finestre: r.windows.map { tratto($0, pavimento: pav) },
                              aperture: r.openings.map { tratto($0, pavimento: pav) }, oggetti: r.objects.map { nome($0.category) },
                              pavimento: poligonoPavimento(r))
    }
    static func nome(_ c: CapturedRoom.Object.Category) -> String {
        switch c {
        case .table: return "tavolo"
        case .chair: return "sedia"
        case .sofa: return "divano"
        case .bed: return "letto"
        case .storage: return "mobile"
        case .refrigerator: return "frigo"
        case .stove: return "fornelli"
        case .oven: return "forno"
        case .sink: return "lavello"
        case .dishwasher: return "lavastoviglie"
        case .washerDryer: return "lavatrice"
        case .toilet: return "WC"
        case .bathtub: return "vasca"
        case .television: return "TV"
        case .fireplace: return "camino"
        case .stairs: return "scale"
        @unknown default: return "arredo"
        }
    }
}
#endif
#endif
