#if os(iOS)
import Foundation
import SwiftUI
import QuickLook
import UIKit
import SceneKit
import simd

// MARK: - LiDAR 23 · i modi (MODI_LIDAR, NOME_LIDAR, RISULTATI_LIDAR del mockup approvato)
// Interno (Stanza), Esterno, Setup (Evento), Oggetto, Corpo (Postura = scheletro; Texture = modello 3D fotografico, chiave «Statua»),
// Misura. Si apre sempre su Interno in OLOGRAMMA. I testi sono quelli del mockup, parola per parola.

nonisolated enum ModoLidar: String, CaseIterable, Codable, Sendable {
    case stanza = "Stanza", esterno = "Esterno", evento = "Evento", oggetto = "Oggetto", corpo = "Corpo", misura = "Misura", statua = "Statua"

    /// L'ordine dei tasti (ORDINE_LIDAR): due righe da tre.
    static let ordine: [ModoLidar] = [.stanza, .esterno, .evento, .oggetto, .corpo, .misura]

    /// NOME_LIDAR: il nome sui tasti e nei titoli.
    var nome: String {
        switch self {
        case .stanza: return "Interno"
        case .esterno: return "Esterno"
        case .evento: return "Setup"
        case .oggetto: return "Oggetto"
        case .corpo: return "Corpo"
        case .statua: return "Texture"
        case .misura: return "Misura"
        }
    }
    var sotto: String {
        switch self {
        case .stanza: return "planimetria e capienza"
        case .oggetto: return "modello 3D e volume"
        case .esterno: return "superficie e dislivello"
        case .evento: return "allestimento e vie di fuga"
        case .corpo: return "postura e proporzioni"
        case .misura: return "metro a vista"
        case .statua: return "modello 3D della persona"
        }
    }
    var testo: String {
        switch self {
        case .stanza: return "Gli spazi interni: pianta, metri quadri, altezza, porte e capienza indicativa."
        case .oggetto: return "Giri intorno all'oggetto: diventa un modello 3D a grandezza vera, con misure, volume e superficie."
        case .esterno: return "Giardino, facciata, terreno: metri quadri e dislivelli, a grandi linee (il sensore legge fino a circa 5 metri)."
        case .evento: return "Sulla pianta della stanza posa palco, console, bar e stand, e controlla passaggi e uscite."
        case .corpo: return "Una persona in piedi davanti all'iPhone: postura e proporzioni. Sono stime, non misure da sarto."
        case .misura: return "Punti l'iPhone su una parete o tra due punti: JARVIS misura in diretta e scrive la misura sopra l'immagine."
        case .statua: return "La persona resta ferma e lei le gira intorno con l'iPhone per circa un minuto: esce un modello 3D a grandezza vera, con la texture fotografica o come ologramma."
        }
    }
    var voce: [String] {
        switch self {
        case .stanza: return ["Jarvis, mappa la stanza", "Jarvis, scansione ambientale", "Jarvis, dammi la pianta", "Jarvis, quanta gente ci sta?"]
        case .oggetto: return ["Jarvis, digitalizza questo oggetto", "Jarvis, acquisisci l'oggetto", "Jarvis, dimensioni dell'oggetto", "Jarvis, calcola il volume"]
        case .esterno: return ["Jarvis, rilievo del terreno", "Jarvis, mappa il perimetro", "Jarvis, misura il giardino", "Jarvis, rilievo della facciata"]
        case .evento: return ["Jarvis, setup della sala", "Jarvis, allestisci la sala", "Jarvis, metti il palco qui", "Jarvis, controlla le vie di fuga"]
        case .corpo: return ["Jarvis, analisi biometrica", "Jarvis, scansione postura", "Jarvis, analisi posturale", "Jarvis, misurami le spalle"]
        case .misura: return ["Jarvis, metro laser", "Jarvis, quanto è largo quel muro?", "Jarvis, misura questa distanza", "Jarvis, quanto è alto il soffitto?"]
        case .statua: return ["Jarvis, crea il gemello digitale", "Jarvis, gemello digitale di Marco", "Jarvis, digitalizza questa persona"]
        }
    }
    var hud: [String] {
        switch self {
        case .stanza: return ["PARETI", "M²", "ALTEZZA"]
        case .oggetto: return ["LARGO", "PROFONDO", "ALTO"]
        case .esterno: return ["M²", "PERIMETRO", "DISLIVELLO"]
        case .evento: return ["STAND", "PASSAGGI", "USCITE"]
        case .corpo: return ["ALTEZZA", "SPALLE", "POSTURA"]
        case .misura: return ["LARGO", "ALTO", "SCARTO"]
        case .statua: return ["FOTO", "ALTEZZA", "GIRO"]
        }
    }
    /// La riga sotto la fotocamera dopo «ACCENSIONE SENSORE…».
    var istruzione: String {
        switch self {
        case .stanza: return "MUOVA L'IPHONE LUNGO LE PARETI"
        case .statua: return "LA PERSONA STIA FERMA · LE GIRI INTORNO"
        case .oggetto: return "GIRI INTORNO ALL'OGGETTO"
        case .esterno: return "CAMMINI LUNGO IL BORDO"
        case .evento: return "POSO GLI ELEMENTI SULLA PIANTA"
        case .misura: return "PUNTI LA PARETE DA UN CAPO ALL'ALTRO"
        case .corpo: return "STIA IN PIEDI, BRACCIA LARGHE"
        }
    }
    /// Il titolo del pannello del risultato.
    var titoloRisultato: String {
        switch self {
        case .statua: return "CORPO · 3D"
        case .corpo: return "CORPO · POSTURA"
        default: return nome.uppercased()
        }
    }
    var nota: String {
        switch self {
        case .misura: return "Precisione di circa un centimetro fino a 5 metri; più lontano bisogna avvicinarsi."
        case .statua: return "Corpo, vestiti e proporzioni vengono bene; capelli, mani e ciò che si è mosso durante il giro meno. Per il solo viso c'è la fotocamera frontale, più precisa."
        case .oggetto: return "Precisione nell'ordine del centimetro: va bene per spedizioni, preventivi e trasporti, non per lavori di precisione."
        case .esterno: return "A grandi linee: su aree grandi l'errore cresce camminando. Per un progetto vero serve il rilievo di un tecnico."
        case .evento: return "Le misure vengono dalla scansione della stanza. Uscite, vie di fuga e capienza vere le approva il tecnico e la commissione di vigilanza."
        case .corpo: return "Sono stime dallo scheletro che vede l'iPhone, non misure da sarto: utili per seguire postura e progressi nel tempo."
        case .stanza: return ""
        }
    }
    /// La parola del sottotitolo del risultato (nel mockup «giardino · esempio», «flight case · esempio»…).
    var parolaRisultato: String {
        switch self {
        case .esterno: return "esterno"
        case .evento: return "allestimento"
        case .oggetto: return "oggetto"
        case .corpo: return "postura"
        case .statua: return "texture"
        case .misura: return "parete"
        case .stanza: return "stanza"
        }
    }
    /// La frase di JARVIS quando il modo parte a voce.
    var annuncioVoce: String {
        switch self {
        case .stanza: return "LiDAR pronto. Muova l'iPhone lungo le pareti, Sir."
        case .esterno: return "Esterno. Cammini lungo il bordo, Sir."
        case .evento: return "Setup. Muova l'iPhone lungo le pareti: poso gli elementi sulla pianta, Sir."
        case .oggetto: return "Oggetto. Ci giri intorno, Sir."
        case .corpo: return "Postura. In piedi davanti all'iPhone, braccia larghe."
        case .misura: return "Metro pronto. Punti la parete da un capo all'altro, Sir."
        case .statua: return "Gemello digitale. La persona stia ferma: le giri intorno, Sir."
        }
    }

    /// I modelli d'esempio dell'anteprima (SALA, GIARDINO, CASSA, ALLESTIMENTO, la persona, la parete del mockup).
    @MainActor var esempio: ModelloScena {
        switch self {
        case .stanza: return .stanza(EsempiLidar.sala)
        case .evento: return .evento(EsempiLidar.sala, EsempiLidar.allestimento)
        case .esterno: return .esterno(EsempiLidar.giardino)
        case .oggetto: return .cassaEsempio
        case .statua: return .statua(nil, altezza: 1.78)
        case .corpo: return .postura(PosturaScena(giunture: OlogrammaOrganismo.giunture, altezza: 1.78, spalle: 0.46, bacinoGradi: 3))
        case .misura: return .misura(larghezza: 3.42, altezza: 2.7)
        }
    }
}

/// Dove sta il corpo: lo scheletro (Postura) o il modello fotografico (Texture, la chiave «Statua»).
nonisolated enum CorpoLidar: Sendable { case postura, statua }

// MARK: - Gli esempi del mockup (solo per l'anteprima)

@MainActor
enum EsempiLidar {
    /// La sala a L d'esempio: 18,4 × 12,6 m, 3,6 m d'altezza, due porte, tre finestre.
    static let sala = StanzaScena(poligono: [[0, 0], [18.4, 0], [18.4, 12.6], [6.2, 12.6], [6.2, 9.4], [0, 9.4]], altezza: 3.6,
                                  porte: [(0, 3.0, 1.6), (1, 8.0, 1.8)], finestre: [(2, 2.5, 2.0), (2, 7.0, 2.0), (5, 3.0, 1.8)])
    /// L'allestimento d'esempio del mockup (ALLESTIMENTO), sulla sala d'esempio: palco, console, bar, cinque stand, tre passaggi.
    static let allestimento: Allestimento = {
        var a = Allestimento()
        a.palco = RettangoloPiano(centro: [1.9, 4.7], asse: [0, 1], lungo: 5, largo: 3, versoMuro: 1)
        a.console = RettangoloPiano(centro: [4.6, 4.7], asse: [1, 0], lungo: 1.6, largo: 1.6)
        a.bar = RettangoloPiano(centro: [15.7, 1.0], asse: [1, 0], lungo: 4.6, largo: 1.4, versoMuro: -1)
        a.stand = [[7.0, 3.0], [11.2, 3.0], [15.4, 3.0], [7.0, 7.2], [11.2, 7.2]].map { (q: SIMD2<Double>) in
            RettangoloPiano(centro: q + SIMD2(1.5, 1.5), asse: [1, 0], lungo: 3, largo: 3, versoMuro: q.y < 6 ? -1 : 1)
        }
        a.passaggi = [(SIMD2(6.6, 6.6), SIMD2(18.4, 6.6)), (SIMD2(10.6, 2.4), SIMD2(10.6, 10.8)), (SIMD2(14.8, 2.4), SIMD2(14.8, 10.8))]
        a.uscite = [1.6, 1.8]
        a.areaPavimento = sala.area
        return a
    }()
    /// Il giardino d'esempio: quotaG(x, y) = 0,09 sin(0,55x) + 0,06 cos(0,7y) + 0,012x.
    static let giardino: TerrenoScena = {
        let bordo: [SIMD2<Double>] = [[0, 0], [9.2, 0], [10.4, 3.1], [9.6, 7.4], [3.8, 8.2], [0, 6.1]]
        let passo = 0.2, x0 = -0.2, z0 = -0.2
        let nx = Int((10.8 - x0) / passo) + 1, nz = Int((8.6 - z0) / passo) + 1
        var q: [Float] = []
        for j in 0..<nz { for i in 0..<nx {
            let x = x0 + (Double(i) + 0.5) * passo, y = z0 + (Double(j) + 0.5) * passo
            q.append(Float(0.09 * sin(x * 0.55) + 0.06 * cos(y * 0.7) + 0.012 * x))
        } }
        return TerrenoScena(bordo: bordo, origine: SIMD2(x0, z0), passo: passo, nx: nx, nz: nz, quote: q, colori: nil, area: 74.8, dislivello: 0.18)
    }()
}

// MARK: - Il risultato di un modo

struct RisultatoModo: Identifiable {
    let id = UUID()
    let modo: ModoLidar
    var data = Date()
    var righe: [(String, String)]
    var modello: ModelloScena
    var domanda: String               // «Chiedi»: la domanda a JARVIS con i numeri veri
    var annuncio: String              // a voce: «quanto è grande?», «dimensioni dell'oggetto»…
    var capienza: String? = nil       // a voce: «quanta gente ci sta?» (Setup)
    var file: URL? = nil              // il modello 3D già su disco (Texture)
    var nome: String? = nil

    var sotto: String { (nome?.lowercased() ?? modo.parolaRisultato) + " · " + data.formatted(date: .numeric, time: .shortened) }

    static func esterno(_ t: TerrenoScena) -> RisultatoModo {
        let erba = Int((t.area * 1.05).rounded())
        return RisultatoModo(modo: .esterno,
                             righe: [("Superficie", LidarFormato.m2(t.area)), ("Perimetro", LidarFormato.m(GeometriaPiana.perimetro(t.bordo))),
                                     ("Dislivello massimo", LidarFormato.cm(t.dislivello)), ("Erba sintetica, con sfrido 5%", "\(erba) m²")],
                             modello: .esterno(t),
                             domanda: "Ho misurato un'area esterna con il LiDAR: \(LidarFormato.n(t.area)) metri quadri, perimetro \(LidarFormato.m(GeometriaPiana.perimetro(t.bordo))), dislivello massimo \(LidarFormato.cm(t.dislivello)). Quanta erba sintetica serve?",
                             annuncio: "Circa \(LidarFormato.n(t.area)) metri quadri, perimetro \(LidarFormato.n(GeometriaPiana.perimetro(t.bordo))) metri, dislivello \(Int((t.dislivello * 100).rounded())) centimetri, Sir.")
    }

    static func oggetto(_ o: OggettoScena) -> RisultatoModo {
        // volume sotto la superficie vista dall'alto (ogni triangolo: area in pianta × altezza media; quelli rivolti in giù tolgono),
        // superficie esterna: la maglia più la base d'appoggio
        var vol: Float = 0, su: Float = 0, giu: Float = 0, sup: Float = 0
        for k in stride(from: 0, to: o.indici.count - 2, by: 3) {
            let a = o.vertici[Int(o.indici[k])], b = o.vertici[Int(o.indici[k + 1])], c = o.vertici[Int(o.indici[k + 2])]
            let x = simd_cross(b - a, c - a), pianta = abs(x.y) / 2, h = (a.y + b.y + c.y) / 3
            sup += simd_length(x) / 2
            if x.y > 0 { vol += pianta * h; su += pianta } else { vol -= pianta * h; giu += pianta }
        }
        let volume = Double(abs(vol)), superficie = Double(sup + max(su, giu))
        let l = Int((o.largo * 100).rounded()), p = Int((o.profondo * 100).rounded()), h = Int((o.alto * 100).rounded())
        return RisultatoModo(modo: .oggetto,
                             righe: [("Misure", "\(l) × \(p) × \(h) cm"), ("Volume", LidarFormato.n(volume, 3) + " m³"),
                                     ("Superficie esterna", LidarFormato.n(superficie, 2) + " m²"), ("Modello 3D", "a grandezza vera · USDZ")],
                             modello: .oggetto(o),
                             domanda: "Ho scansionato un oggetto con il LiDAR: \(l) × \(p) × \(h) cm, volume \(LidarFormato.n(volume, 3)) m³. Quanto costa spedirlo con Messina?",
                             annuncio: "\(l) per \(p) per \(h) centimetri: \(LidarFormato.n(volume, 3)) metri cubi, Sir.")
    }

    static func misura(larghezza: Float, altezza: Float) -> RisultatoModo {
        let L = Double(larghezza), H = Double(altezza), S = L * H
        return RisultatoModo(modo: .misura,
                             righe: [("Larghezza", LidarFormato.m(L, 2)), ("Altezza", LidarFormato.m(H, 2)), ("Superficie", LidarFormato.n(S, 2) + " m²"),
                                     ("Pittura, due mani (10 m² al litro)", LidarFormato.n(S * 2 / 10) + " l")],
                             modello: .misura(larghezza: larghezza, altezza: altezza),
                             domanda: "Ho misurato una parete con il LiDAR: larga \(LidarFormato.m(L, 2)), alta \(LidarFormato.m(H, 2)), \(LidarFormato.n(S, 2)) m². Quanta pittura serve per due mani?",
                             annuncio: "\(LidarFormato.n(L, 2)) metri di larghezza, \(LidarFormato.n(H, 2)) di altezza: \(LidarFormato.n(S, 1)) metri quadri, Sir.")
    }

    static func postura(_ p: Postura) -> RisultatoModo {
        let scena = PosturaScena(giunture: p.giunture, altezza: p.altezza, spalle: p.spalle, bacinoGradi: p.bacinoGradi)
        return RisultatoModo(modo: .corpo,
                             righe: [("Altezza stimata", LidarFormato.m(Double(p.altezza), 2)), ("Larghezza spalle", LidarFormato.cm(Double(p.spalle))),
                                     ("Spalle", p.testoSpalle), ("Bacino", p.testoBacino)],
                             modello: .postura(scena),
                             domanda: "Scansione della postura con il LiDAR: altezza stimata \(LidarFormato.m(Double(p.altezza), 2)), spalle \(LidarFormato.cm(Double(p.spalle))), spalle \(p.testoSpalle), bacino \(p.testoBacino). Come sto di postura?",
                             annuncio: "Alto circa \(LidarFormato.n(Double(p.altezza), 2)) metri, spalle \(Int((p.spalle * 100).rounded())) centimetri; spalle \(p.testoSpalle), bacino \(p.testoBacino), Sir.")
    }

    @MainActor static func statua(file: URL, foto: Int, minuti: Double, nome: String?) -> RisultatoModo {
        var h: Float = 0
        if let s = try? SCNScene(url: file, options: nil) { let (lo, hi) = s.rootNode.boundingBox; h = Float(hi.y - lo.y) }
        let tempo = minuti < 1 ? "meno di un minuto" : "circa \(Int(minuti.rounded())) minut\(Int(minuti.rounded()) == 1 ? "o" : "i")"
        let chi = nome ?? "una persona"
        return RisultatoModo(modo: .statua,
                             righe: [("Modello 3D", "texture o ologramma · USDZ"), ("Altezza", h > 0 ? LidarFormato.m(Double(h), 2) : "—"),
                                     ("Foto usate", "\(foto)"), ("Elaborazione sull'iPhone", tempo)],
                             modello: .statua(file, altezza: h),
                             domanda: "Ho creato con il LiDAR il modello 3D di \(chi): alto \(LidarFormato.m(Double(h), 2)), \(foto) foto, elaborato sull'iPhone in \(tempo). Cosa posso farci?",
                             annuncio: "Il modello 3D di \(chi) è pronto, Sir: alto \(LidarFormato.n(Double(h), 2)) metri.", file: file, nome: nome)
    }

    static func evento(_ s: ScansioneLidar) -> RisultatoModo {
        let st = StanzaScena(s), a = Allestimento.calcola(st)
        let posti = Int(a.areaLibera * 1.2)
        return RisultatoModo(modo: .evento,
                             righe: [("Stand 3 × 3 m", "\(a.stand.count)"), ("Passaggi minimi", LidarFormato.m(Allestimento.passaggio)),
                                     ("Uscite", a.testoUscite), ("Palco, console, bar", a.testoPosati)],
                             modello: .evento(st, a),
                             domanda: "Ho allestito la sala con il LiDAR: \(LidarFormato.m2(st.area)) di pavimento; palco, console e bar: \(a.testoPosati); \(a.stand.count) stand da 3 × 3 m, passaggi da 1,2 m, uscite \(a.testoUscite). Restano circa \(Int(a.areaLibera.rounded())) m² liberi. Quante persone ci stanno con questo allestimento?",
                             annuncio: "\(a.stand.count) stand da tre per tre, passaggi da un metro e venti, \(a.uscite.count) uscite. Palco, console e bar: \(a.testoPosati), Sir.",
                             capienza: "Con l'allestimento restano circa \(Int(a.areaLibera.rounded())) metri quadri liberi: circa \(posti) persone, Sir, a 1,2 per metro quadro. Quella vera la fissano uscite e commissione.")
    }
}

// MARK: - L'archivio dei modi (Documenti › LiDAR › modi.json)

nonisolated struct ModoSalvato: Codable, Identifiable, Sendable {
    var id: UUID
    var modo: ModoLidar
    var data: Date
    var sotto: String
    var righe: [[String]]
    var file: String?                 // il modello 3D accanto (USDZ), se c'è
}

@MainActor
final class ArchivioModi {
    static let condiviso = ArchivioModi()
    private(set) var voci: [ModoSalvato] = []
    private var indice: URL { ArchivioLidar.cartella.appendingPathComponent("modi.json") }

    init() {
        if let d = try? Data(contentsOf: indice), let v = try? JSONDecoder().decode([ModoSalvato].self, from: d) { voci = v }
    }
    func contiene(_ id: UUID) -> Bool { voci.contains { $0.id == id } }

    /// Salva i numeri e, per Oggetto e Texture, il modello 3D (USDZ) accanto.
    func salva(_ r: RisultatoModo) {
        guard !contiene(r.id) else { return }
        var nomeFile: String?
        if let f = r.file { nomeFile = f.lastPathComponent }
        else if case .oggetto(let o) = r.modello {
            let url = ArchivioLidar.cartella.appendingPathComponent("oggetto-\(r.id.uuidString).usdz")
            if Self.esporta(o, url) { nomeFile = url.lastPathComponent }
        }
        let voce = ModoSalvato(id: r.id, modo: r.modo, data: r.data, sotto: r.sotto, righe: r.righe.map { [$0.0, $0.1] }, file: nomeFile)
        voci.insert(voce, at: 0)
        if let d = try? JSONEncoder().encode(voci) { try? d.write(to: indice, options: .atomic) }
        // 11 nov (approvato il 10 nov): la copia nell'Archivio centrale, cartella lidar: le misure e, se c'è, il modello 3D
        let nome = "\(voce.modo.nome) · \(ArchivioCentrale.quando(voce.data))"
        ArchivioCentrale.copiaTesto(nome: nome, cartella: "lidar", testo: ArchivioModi.scheda(voce), descrizione: "LiDAR · \(voce.modo.nome) · \(voce.sotto)")
        if let f = nomeFile {
            ArchivioCentrale.copiaFile(ArchivioLidar.cartella.appendingPathComponent(f), nome: nome + " 3D", cartella: "lidar",
                                       tipo: "model/vnd.usdz+zip", descrizione: "LiDAR · \(voce.modo.nome) · modello 3D")
        }
    }

    /// La maglia dell'oggetto, coi colori veri, in USDZ.
    private static func esporta(_ o: OggettoScena, _ url: URL) -> Bool {
        let v = SCNGeometrySource(vertices: o.vertici.map { SCNVector3($0.x, $0.y, $0.z) })
        let n = SCNGeometrySource(normals: ScenaLidar.normali(o.vertici, o.indici).map { SCNVector3($0.x, $0.y, $0.z) })
        var fonti = [v, n]
        if let c = o.colori { fonti.append(ScenaLidar.fonteColori(c)) }
        let g = SCNGeometry(sources: fonti, elements: [SCNGeometryElement(indices: o.indici, primitiveType: .triangles)])
        let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = UIColor.white; m.isDoubleSided = true
        g.materials = [m]
        let s = SCNScene(); s.rootNode.addChildNode(SCNNode(geometry: g))
        return s.write(to: url, options: nil, delegate: nil, progressHandler: nil)
    }
}

// MARK: - I pezzi delle schermate (stili del mockup: .chip, .tavola, .comando, .lidar-hud, .lidar-stato, .lidar-fine)

/// Il tasto a scelta (.chip): pieno ciano quando è premuto.
struct ChipLidar: View {
    let testo: String
    let premuto: Bool
    var piccolo = false                 // .modi-l.sei: 10 pt
    let azione: () -> Void

    var body: some View {
        Button { Suoni.tocco(); azione() } label: {
            Text(testo).font(.system(size: piccolo ? 10 : 11, weight: .semibold, design: .monospaced)).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, piccolo ? 4 : 8)
                .foregroundStyle(premuto ? Color.fondo : Color.ciano)
                .background(premuto ? Color.ciano : .clear)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(premuto ? Color.ciano : Color.ciano.opacity(0.3), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(StileStark())
        .accessibilityAddTraits(premuto ? .isSelected : [])
    }
}

/// Il tasto da comando (.comando): contorno ciano, maiuscolo da terminale, 11 pt di imbottitura come nel mockup.
struct TastoLidar: View {
    let testo: String
    var attivo = true
    let azione: () -> Void

    var body: some View {
        Button { Suoni.tocco(); azione() } label: {
            Text(testo.uppercased()).font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).padding(.vertical, 11).padding(.horizontal, 8)
                .foregroundStyle(Color.ciano.opacity(attivo ? 1 : 0.5))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
        .disabled(!attivo)
    }
}

/// La tavola (.tavola): bordo sottile, angoli da 12, il 3D dentro con le proporzioni del mockup.
struct TavolaLidar<Contenuto: View>: View {
    let proporzione: CGFloat?             // 720/420 nel menu, 720/560 nel risultato; nil: alta quanto il contenuto (l'archivio)
    @ViewBuilder let contenuto: () -> Contenuto

    var body: some View {
        Group {
            if let proporzione { contenuto().aspectRatio(proporzione, contentMode: .fit) } else { contenuto() }
        }
            .frame(maxWidth: .infinity)
            .background(Color.ciano.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.22), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// La riga in alto di LiDAR: la testata a sinistra e la X nel cerchio a destra (LiDAR è una sezione con la fotocamera), come tutte
/// le sezioni (7 nov sera: BarraSezione, la testata nella riga della X). Durante la scansione solo la X, come prima.
struct ChiudiLidar: View {
    var testata: DatiTestata? = nil
    let azione: () -> Void
    var body: some View {
        BarraSezione(testata: testata, tinta: .ciano, conX: true, chiudi: azione)
    }
}

/// La schermata di scansione (.lidar): fotocamera con gli angoli da 18, i tre numeri in alto, la riga di stato e «Fine» in basso.
struct CorniceScansione<Camera: View>: View {
    let etichette: [String]
    let valori: [String]
    let stato: String
    var avviso = false                    // stato in arancio (errore)
    let mostraFine: Bool
    var mostraRiprova = false
    let fine: () -> Void
    var riprova: () -> Void = {}
    @ViewBuilder let camera: () -> Camera

    var body: some View {
        ZStack(alignment: .bottom) {
            camera()
            VStack(spacing: 10) {
                Text(stato)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                    .foregroundStyle(avviso ? Color.orange : Color.ciano)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
                if mostraFine {
                    Button { Suoni.tocco(); fine() } label: {
                        Text("Fine").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.fondo)
                            .padding(.horizontal, 28).padding(.vertical, 10).background(Color.ciano).clipShape(Capsule())
                    }
                    .buttonStyle(StileStark())
                }
                if mostraRiprova {
                    Button { Suoni.tocco(); riprova() } label: {
                        Text("Riprova").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.fondo)
                            .padding(.horizontal, 28).padding(.vertical, 10).background(Color.ciano).clipShape(Capsule())
                    }
                    .buttonStyle(StileStark())
                }
            }
            .padding(.bottom, 16)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(spacing: 2) {
                        Text(i < valori.count ? valori[i] : "—").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        Text(i < etichette.count ? etichette[i] : "").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(Color.fondo.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.22), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
        }
        .background(RadialGradient(colors: [Color(red: 0.08, green: 0.14, blue: 0.16), Color.fondo], center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0, endRadius: 420))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(red: 0.07, green: 0.14, blue: 0.16), lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 24)
    }
}

// MARK: - Il menu dei modi (modiLidar)

struct MenuLidar: View {
    @Binding var modo: ModoLidar
    @Binding var corpo: CorpoLidar
    @Binding var stile: StileLidar
    let scansiona: () -> Void
    /// 11 nov: l'ARCHIVIO in fondo al menu (tocco su una stanza: si riapre col suo risultato)
    var apriStanza: ((ScansioneLidar) -> Void)? = nil

    /// Il modo vero: in Corpo, Postura o Texture (la «Statua»).
    private var vero: ModoLidar { modo == .corpo && corpo == .statua ? .statua : modo }
    private var conStile: Bool { vero != .corpo && vero != .misura }
    private var titolo: String {
        if modo == .corpo { return "CORPO · " + (corpo == .statua ? (stile == .pieno ? "OLOGRAMMA" : "TEXTURE") : "POSTURA") }
        return modo.nome.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(ModoLidar.ordine, id: \.self) { m in
                        ChipLidar(testo: m.nome.uppercased(), premuto: m == modo, piccolo: true) { modo = m }
                    }
                }
                if modo == .corpo {
                    HStack(spacing: 6) {
                        ChipLidar(testo: "POSTURA", premuto: corpo == .postura) { corpo = .postura }
                        ChipLidar(testo: "OLOGRAMMA", premuto: corpo == .statua && stile == .pieno) { corpo = .statua; stile = .pieno }
                        ChipLidar(testo: "TEXTURE", premuto: corpo == .statua && stile == .foto) { corpo = .statua; stile = .foto }
                    }
                }
                if modo != .corpo && modo != .misura {
                    HStack(spacing: 6) {
                        ChipLidar(testo: "OLOGRAMMA", premuto: stile == .pieno) { stile = .pieno }
                        ChipLidar(testo: "TEXTURE", premuto: stile == .foto) { stile = .foto }
                    }
                }
            }
            TavolaLidar(proporzione: 720 / 420) {
                Vista3DLidar(modello: vero.esempio, fase: .anteprima, stile: conStile ? stile : nil)
                    .id(vero)
            }
            Pannello(titolo: titolo, tinta: .ciano) {
                Text(vero.testo).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo).fixedSize(horizontal: false, vertical: true)
            }
            PannelloAVoce(frasi: vero.voce.map { "«\($0)»" })
            TastoLidar(testo: "Scansiona", azione: scansiona)
            if let apriStanza { ArchivioLidarMenu(stanze: ArchivioLidar.condiviso, apriStanza: apriStanza) }
        }
    }
}

// MARK: - Il risultato di un modo (scansionaModo, dopo «Fine»)

struct RisultatoModoVista: View {
    let r: RisultatoModo
    @Binding var stile: StileLidar
    let salvato: Bool
    let salva: () -> Void
    let altra: () -> Void
    let chiedi: () -> Void
    var studio: (() -> Void)? = nil                    // MARK X: STUDIO, la scansione vera sul banco dello Studio

    private var conStile: Bool { r.modo != .corpo && r.modo != .misura }
    private var stile3D: StileLidar? { r.modo == .corpo ? nil : (r.modo == .misura ? .foto : stile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if conStile {
                HStack(spacing: 6) {
                    ChipLidar(testo: "OLOGRAMMA", premuto: stile == .pieno) { stile = .pieno }
                    ChipLidar(testo: "TEXTURE", premuto: stile == .foto) { stile = .foto }
                }
            }
            TavolaLidar(proporzione: 720 / 560) {
                Vista3DLidar(modello: r.modello, fase: .risultato, stile: stile3D)
                    .id(r.id)
            }
            Pannello(titolo: r.modo.titoloRisultato, tinta: .ciano) {
                ForEach(Array(r.righe.enumerated()), id: \.offset) { _, riga in RigaHUD(riga.0, riga.1) }
                Text(r.modo.nota).font(.system(size: 11)).foregroundStyle(Color.tenue).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TastoLidar(testo: salvato ? "Salvata" : "Salva", attivo: !salvato, azione: salva)
                if let studio { TastoLidarStudio(azione: studio) }      // come il mockup: Salva · Studio · Modalità · Chiedi
                TastoLidar(testo: "Modalità", azione: altra)
                TastoLidar(testo: "Chiedi", azione: chiedi)
            }
        }
    }
}

// MARK: - 11 nov · ARCHIVIO di LiDAR: i modi salvati (Oggetto, Corpo, Esterno, Setup, Misura, Texture)

extension ArchivioModi {
    /// La scheda di un modo salvato per l'Archivio centrale: le righe delle misure, leggibili da chiunque.
    nonisolated static func scheda(_ v: ModoSalvato) -> String {
        (["LIDAR · \(v.modo.nome.uppercased()) · \(v.sotto)", ArchivioCentrale.quando(v.data), ""]
            + v.righe.map { $0.joined(separator: ": ") }).joined(separator: "\n")
    }

    /// Elimina un modo salvato e il suo modello 3D dal telefono (la copia nell'Archivio centrale resta: si toglie da lì).
    func cancella(_ v: ModoSalvato) {
        if let u = file3D(v) { try? FileManager.default.removeItem(at: u) }
        voci.removeAll { $0.id == v.id }
        if let d = try? JSONEncoder().encode(voci) { try? d.write(to: indice, options: .atomic) }
    }

    /// Il modello 3D accanto (USDZ), se c'è ancora sul telefono.
    func file3D(_ v: ModoSalvato) -> URL? {
        guard let f = v.file else { return nil }
        let u = ArchivioLidar.cartella.appendingPathComponent(f)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

/// 11 nov (approvato il 10 nov: «perfetto»): l'ARCHIVIO nel menu di LiDAR, con tutto quello che è stato salvato: le stanze
/// (Interno) e i modi (Esterno, Setup, Oggetto, Corpo, Misura, Texture), dal più recente. Tocco su una stanza: si riapre col suo
/// risultato (pianta, ologramma, texture). Tocco su un modo: si aprono le sue misure, con 3D (AR Quick Look, se c'è il modello) e
/// CONDIVIDI. ELIMINA › CONFERMA come nel resto di LiDAR. Ogni salvataggio va anche nell'Archivio centrale, cartella lidar.
struct ArchivioLidarMenu: View {
    @ObservedObject var stanze: ArchivioLidar
    let apriStanza: (ScansioneLidar) -> Void
    @State private var modi: [ModoSalvato] = ArchivioModi.condiviso.voci
    @State private var aperto: UUID?
    @State private var daEliminare: UUID?
    @State private var giro = 0
    @State private var anteprima3D: URL?

    private enum Voce: Identifiable {
        case stanza(ScansioneLidar), modo(ModoSalvato)
        var id: UUID { switch self { case .stanza(let s): return s.id; case .modo(let m): return m.id } }
        var data: Date { switch self { case .stanza(let s): return s.data; case .modo(let m): return m.data } }
    }

    private var voci: [Voce] {
        (stanze.scansioni.map { Voce.stanza($0) } + modi.map { Voce.modo($0) }).sorted { $0.data > $1.data }
    }

    var body: some View {
        Pannello(titolo: "ARCHIVIO", tinta: .ciano) {
            if voci.isEmpty {
                Text("Ancora niente di salvato. Ogni scansione salvata resta qui (e nell'Archivio, cartella lidar).")
                    .font(.system(size: 13)).foregroundStyle(Color.tenue).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(voci) { v in
                        riga(v)
                        if v.id != voci.last?.id { Divider().overlay(Color.ciano.opacity(0.12)) }
                    }
                }
            }
        }
        .onAppear { modi = ArchivioModi.condiviso.voci }
        .quickLookPreview($anteprima3D)
    }

    @ViewBuilder private func riga(_ v: Voce) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Suoni.tocco()
                    switch v {
                    case .stanza(let s): apriStanza(s)
                    case .modo(let m): withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) { aperto = aperto == m.id ? nil : m.id }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titolo(v)).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo).lineLimit(1)
                        Text(dettaglio(v)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(StileStark())
                let sicuro = daEliminare == v.id
                let rosso = Color(red: 1, green: 107 / 255, blue: 107 / 255)                                    // #ff6b6b
                Button { elimina(v) } label: {
                    Text(sicuro ? "CONFERMA" : "ELIMINA")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
                        .foregroundStyle(sicuro ? rosso : Color.ciano)
                        .padding(.vertical, 6).padding(.horizontal, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(sicuro ? rosso.opacity(0.6) : Color.ciano.opacity(0.3), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(StileStark())
                .accessibilityLabel(sicuro ? "Conferma: elimina \(titolo(v))" : "Elimina \(titolo(v))")
            }
            if case .modo(let m) = v, aperto == m.id {
                ForEach(Array(m.righe.enumerated()), id: \.offset) { _, r in RigaHUD(r.first ?? "", r.count > 1 ? r[1] : "") }
                HStack(spacing: 6) {
                    if let u = ArchivioModi.condiviso.file3D(m) {
                        ChipLidar(testo: "3D", premuto: false) { anteprima3D = u }
                    }
                    ShareLink(items: condivisi(m)) {
                        Text("CONDIVIDI").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 8).foregroundStyle(Color.ciano)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(0.3), lineWidth: 1))
                    }
                }
            }
        }
        .padding(.vertical, 11)
    }

    private func titolo(_ v: Voce) -> String {
        switch v {
        case .stanza(let s): return s.nome
        case .modo(let m): return m.modo.nome
        }
    }

    private func dettaglio(_ v: Voce) -> String {
        switch v {
        case .stanza(let s): return "INTERNO · \(LidarFormato.m2(s.area)) · \(s.data.formatted(date: .numeric, time: .shortened))"
        case .modo(let m): return "\(m.sotto.uppercased()) · \(m.data.formatted(date: .numeric, time: .shortened))"
        }
    }

    /// Le misure in un file di testo e, se c'è, il modello 3D.
    private func condivisi(_ m: ModoSalvato) -> [URL] {
        var out: [URL] = []
        let testo = FileManager.default.temporaryDirectory.appendingPathComponent("LiDAR \(m.modo.nome) \(ArchivioCentrale.quando(m.data)).txt")
        if (try? ArchivioModi.scheda(m).write(to: testo, atomically: true, encoding: .utf8)) != nil { out.append(testo) }
        if let u = ArchivioModi.condiviso.file3D(m) { out.append(u) }
        return out
    }

    /// Il primo tocco chiede CONFERMA per 3 secondi, il secondo elimina (dal telefono; la copia nell'Archivio centrale resta).
    private func elimina(_ v: Voce) {
        guard daEliminare == v.id else {
            Suoni.tocco()
            daEliminare = v.id
            giro += 1
            let mio = giro
            Task { try? await Task.sleep(for: .seconds(3)); if giro == mio { daEliminare = nil } }
            return
        }
        Suoni.pronto()
        daEliminare = nil
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)) {
            switch v {
            case .stanza(let s): stanze.cancella(s)
            case .modo(let m): ArchivioModi.condiviso.cancella(m); modi = ArchivioModi.condiviso.voci
            }
        }
    }
}
#endif
