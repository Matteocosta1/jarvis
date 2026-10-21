#if os(iOS)
import SwiftUI
import Combine
import SceneKit
import UIKit
import simd
#if canImport(RoomPlan)
import RoomPlan
#endif

// MARK: - LiDAR (STRUMENTI)
// La scansione di una stanza con il LiDAR dell'iPhone (RoomPlan di Apple): pareti, porte, finestre, aperture e mobili.
// Durante la scansione il disegno dal vivo è quello di Apple; il risultato è di JARVIS: pianta ciano con le misure,
// ologramma 3D che ruota, misure, capienza indicativa, archivio, condivisione e «Chiedi» a JARVIS.
// Tutto resta sul telefono (Documenti › LiDAR): niente cloud, niente costi.

/// Un tratto sulla pianta, visto dall'alto (metri: x e z del mondo).
nonisolated struct TrattoPianta: Codable, Hashable, Sendable {
    var ax: Double, az: Double, bx: Double, bz: Double
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

// MARK: - La sezione

struct VistaLidar: View {
    let chiudi: () -> Void
    let chiedi: (String) -> Void
    @StateObject private var archivio = ArchivioLidar.condiviso
    @State private var fase: Fase = LidarSupporto.disponibile ? .scansione : .nonDisponibile
    @State private var risultato: ScansioneLidar?
    @State private var vista: Vista = .pianta
    @State private var dalVivo = MisureDalVivo()
    @State private var fermaScansione = false
    @State private var avviso: String?
    @State private var condivisi: [URL] = []
    @State private var tentativo = 0                         // «Riprova»: una sessione nuova                // pianta PNG + modello 3D, preparati quando si apre una scansione

    enum Fase { case scansione, elaboro, risultato, nonDisponibile }
    enum Vista: String, CaseIterable { case pianta = "PIANTA", tre = "3D", archivio = "ARCHIVIO" }

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            switch fase {
            case .scansione, .elaboro: schermoScansione
            case .risultato, .nonDisponibile: schermoRisultato
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(fase == .scansione || fase == .elaboro)
        .aperturaHUD("LiDAR", fotocamera: LidarSupporto.disponibile)
    }

    // MARK: Scansione

    private var schermoScansione: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("Chiudi") { Suoni.tocco(); esci() }.font(.body.weight(.semibold)).tint(Color.ciano).foregroundStyle(Color.ciano)
            }
            .padding(.horizontal, 20).padding(.top, 8)
            ZStack(alignment: .bottom) {
                #if canImport(RoomPlan)
                CatturaStanza(ferma: $fermaScansione,
                              aggiorna: { dalVivo = $0 },
                              finita: { s in mostra(s) },
                              errore: { e in avviso = e; fase = .scansione })
                .id(tentativo)
                #endif
                VStack(spacing: 10) {
                    Text(fase == .elaboro ? "ELABORAZIONE PIANTA…" : (avviso ?? "MUOVA L'IPHONE LUNGO LE PARETI"))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                        .foregroundStyle(avviso == nil ? Color.ciano : .orange)
                        .multilineTextAlignment(.center)
                    if fase == .scansione && avviso == nil {
                        Button { Suoni.tocco(); fase = .elaboro; fermaScansione = true } label: {
                            Text("Fine").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.fondo)
                                .padding(.horizontal, 28).padding(.vertical, 10).background(Color.ciano).clipShape(Capsule())
                        }
                        .buttonStyle(StileStark())
                    }
                    if avviso != nil {
                        Button { Suoni.tocco(); avviso = nil; fermaScansione = false; dalVivo = MisureDalVivo(); fase = .scansione; tentativo += 1 } label: {
                            Text("Riprova").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.fondo)
                                .padding(.horizontal, 28).padding(.vertical, 10).background(Color.ciano).clipShape(Capsule())
                        }
                        .buttonStyle(StileStark())
                    }
                }
                .padding(.bottom, 16)
            }
            .overlay(alignment: .top) { hudDalVivo.padding(12) }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ciano.opacity(0.15), lineWidth: 1))
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private var hudDalVivo: some View {
        HStack(spacing: 8) {
            datoVivo("\(dalVivo.pareti)", "PARETI")
            datoVivo(dalVivo.area > 0 ? LidarFormato.n(dalVivo.area) : "0,0", "M²")
            datoVivo(dalVivo.altezza > 0 ? LidarFormato.m(dalVivo.altezza, 2) : "—", "ALTEZZA")
        }
    }
    private func datoVivo(_ v: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.white).monospacedDigit()
                .contentTransition(.numericText())
            Text(t).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(Color.fondo.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func mostra(_ s: ScansioneLidar) {
        apri(s)
        withAnimation(.easeOut(duration: 0.3)) { fase = .risultato }
        Suoni.schedaPronta()
    }
    /// Uscendo, il modello 3D di una scansione non salvata si cancella: non resta a occupare spazio.
    private func esci() {
        if let r = risultato, !archivio.contiene(r) { try? FileManager.default.removeItem(at: r.file3D) }
        chiudi()
    }
    private func apri(_ s: ScansioneLidar) {
        risultato = s
        vista = .pianta
        condivisi = LidarCondivisione.file(s)
    }

    // MARK: Risultato

    private var schermoRisultato: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Chiudi") { Suoni.tocco(); esci() }.font(.body.weight(.semibold)).tint(Color.ciano).foregroundStyle(Color.ciano)
            }
            .padding(.horizontal, 20).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    testata
                    HStack(spacing: 6) {
                        ForEach(Vista.allCases, id: \.self) { v in
                            Button { Suoni.tocco(); vista = v } label: {
                                Text(v.rawValue).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(vista == v ? Color.fondo : Color.ciano)
                                    .background(vista == v ? Color.ciano : .clear)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(vista == v ? 1 : 0.3), lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(StileStark())
                        }
                    }
                    tavola
                    if let s = risultato, vista != .archivio { pannelli(s) }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
    }

    private var testata: some View {
        HStack(spacing: 14) {
            Image(systemName: "cube.transparent").font(.system(size: 22)).foregroundStyle(Color.ciano)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.ciano.opacity(0.25), lineWidth: 1))
                .shadow(color: .ciano.opacity(0.3), radius: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("LIDAR").font(.system(size: 22, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(.white)
                Text(risultato?.nome.lowercased() ?? (fase == .nonDisponibile ? "serve un iphone con lidar" : "archivio"))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var tavola: some View {
        Group {
            switch vista {
            case .pianta:
                if let s = risultato { PiantaLidar(scansione: s).frame(height: 280) } else { vuoto("Nessuna scansione aperta.\nNe apra una dall'archivio.") }
            case .tre:
                if let s = risultato, FileManager.default.fileExists(atPath: s.file3D.path) {
                    Ologramma3D(file: s.file3D).frame(height: 280)
                } else { vuoto("Il modello 3D non c'è per questa scansione.") }
            case .archivio:
                archivioVista
            }
        }
        .background(Color.ciano.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func vuoto(_ t: String) -> some View {
        Text(fase == .nonDisponibile && archivio.scansioni.isEmpty
             ? "La scansione funziona sull'iPhone con il LiDAR (Pro), Sir: qui si vedono le scansioni salvate su questo dispositivo." : t)
            .font(.system(size: 13)).foregroundStyle(Color.tenue).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 160).padding()
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
                                Text(s.nome).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                Text("\(LidarFormato.m2(s.area)) · \(s.data.formatted(date: .numeric, time: .shortened))")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue)
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
        }
    }

    private func pannelli(_ s: ScansioneLidar) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Pannello(titolo: "MISURE", tinta: .ciano) {
                riga("Superficie", LidarFormato.m2(s.area))
                riga("Perimetro", LidarFormato.m(s.perimetro))
                riga("Altezza", LidarFormato.m(s.altezza, 2))
                riga("Volume", s.area > 0 ? LidarFormato.n(s.volume, 0) + " m³" : "—")
                riga("Pareti · porte · finestre", "\(s.pareti.count) · \(s.porte.count) · \(s.finestre.count)")
                if !s.oggetti.isEmpty { riga("Arredi", "\(s.oggetti.count)") }
            }
            Pannello(titolo: "CAPIENZA", tinta: .ciano) {
                riga("Indicativa, 1,2 persone/m²", s.area > 0 ? "\(s.capienza) persone" : "—")
                Text("Densità delle sale da ballo (DM 19/08/1996). La capienza vera la fissano uscite e commissione di vigilanza.")
                    .font(.system(size: 11)).foregroundStyle(Color.tenue)
            }
            HStack(spacing: 8) {
                tasto(archivio.contiene(s) ? "Salvata" : "Salva", attivo: !archivio.contiene(s)) { archivio.salva(s) }
                ShareLink(items: condivisi) {
                    Text("Condividi").font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(Color.ciano)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
                }
                .simultaneousGesture(TapGesture().onEnded { Suoni.tocco() })
                tasto("Chiedi", attivo: true) { chiedi(s.riassunto) }
            }
        }
    }

    private func riga(_ t: String, _ v: String) -> some View {
        HStack {
            Text(t).font(.system(size: 14)).foregroundStyle(Color(white: 0.85))
            Spacer()
            Text(v).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.tenue).monospacedDigit()
        }
    }

    private func tasto(_ t: String, attivo: Bool, _ azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            Text(t).font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                .frame(maxWidth: .infinity).padding(.vertical, 11).foregroundStyle(Color.ciano.opacity(attivo ? 1 : 0.5))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(StileStark())
        .disabled(!attivo)
    }
}

/// I numeri che salgono mentre scansiona.
nonisolated struct MisureDalVivo: Equatable, Sendable { var pareti = 0; var area = 0.0; var altezza = 0.0 }

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

// MARK: - L'ologramma 3D (SceneKit): il modello della stanza a fil di ferro ciano, che ruota

struct Ologramma3D: UIViewRepresentable {
    let file: URL

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = UIColor(Color.fondo)
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling4X
        v.scene = Self.scena(file)
        return v
    }
    func updateUIView(_ v: SCNView, context: Context) {}

    static func scena(_ file: URL) -> SCNScene {
        let scena = SCNScene()
        guard let modello = try? SCNScene(url: file, options: [.checkConsistency: true]) else { return scena }
        let perno = SCNNode()
        for n in modello.rootNode.childNodes { perno.addChildNode(n) }
        let ciano = UIColor(red: 0.31, green: 0.89, blue: 1, alpha: 1)
        var conGeometria: [SCNNode] = []
        perno.enumerateHierarchy { nodo, _ in if nodo.geometry != nil { conGeometria.append(nodo) } }
        for nodo in conGeometria {
            guard let g = nodo.geometry else { continue }
            let filo = SCNMaterial()
            filo.fillMode = .lines
            filo.lightingModel = .constant
            filo.diffuse.contents = ciano
            filo.emission.contents = ciano
            filo.isDoubleSided = true
            g.materials = [filo]
            // un velo trasparente sotto il filo, come le pareti dell'ologramma
            let velo = SCNNode(geometry: g.copy() as? SCNGeometry)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = ciano.withAlphaComponent(0.08)
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            velo.geometry?.materials = [m]
            nodo.addChildNode(velo)
        }
        // al centro, poi gira piano
        let (lo, hi) = perno.boundingBox
        let centro = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
        perno.pivot = SCNMatrix4MakeTranslation(centro.x, centro.y, centro.z)
        perno.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)))
        scena.rootNode.addChildNode(perno)
        let raggio = max(hi.x - lo.x, hi.z - lo.z, 1)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.zFar = 500
        camera.position = SCNVector3(0, raggio * 0.75, raggio * 1.25)
        camera.look(at: SCNVector3(0, 0, 0))
        scena.rootNode.addChildNode(camera)
        return scena
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
    let finita: (ScansioneLidar) -> Void
    let errore: (String) -> Void

    func makeCoordinator() -> Regista { Regista(aggiorna: aggiorna, finita: finita, errore: errore) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let v = RoomCaptureView(frame: .zero)
        v.delegate = context.coordinator
        v.captureSession.delegate = context.coordinator
        context.coordinator.vista = v
        v.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return v
    }
    func updateUIView(_ v: RoomCaptureView, context: Context) {
        if ferma && !context.coordinator.fermata {
            context.coordinator.fermata = true
            v.captureSession.stop()
        }
    }
    static func dismantleUIView(_ v: RoomCaptureView, coordinator: Regista) {
        coordinator.annullata = true
        if !coordinator.fermata { v.captureSession.stop() }
    }

    /// Riceve gli aggiornamenti della sessione e il risultato della vista. NSCoding lo chiede il protocollo di Apple.
    @objc(JarvisRegistaLidar)                   // nome stabile: RoomCaptureViewDelegate passa da NSCoding
    nonisolated final class Regista: NSObject, RoomCaptureViewDelegate, RoomCaptureSessionDelegate, @unchecked Sendable {
        let aggiorna: (MisureDalVivo) -> Void
        let finita: (ScansioneLidar) -> Void
        let errore: (String) -> Void
        weak var vista: RoomCaptureView?
        var fermata = false
        var annullata = false                       // chiusa a metà: niente pianta, niente suono, niente file

        init(aggiorna: @escaping (MisureDalVivo) -> Void, finita: @escaping (ScansioneLidar) -> Void, errore: @escaping (String) -> Void) {
            self.aggiorna = aggiorna; self.finita = finita; self.errore = errore
        }
        required init?(coder: NSCoder) { nil }
        func encode(with coder: NSCoder) {}

        // i numeri dal vivo
        nonisolated func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            let m = MisureDalVivo(pareti: room.walls.count, area: Misuratore.area(room), altezza: Misuratore.altezza(room))
            Task { @MainActor in self.aggiorna(m) }
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
    static func tratto(_ s: CapturedRoom.Surface) -> TrattoPianta {
        let t = s.transform, c = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let dir = simd_normalize(SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)), l = s.dimensions.x / 2
        let a = c - dir * l, b = c + dir * l
        return TrattoPianta(ax: Double(a.x), az: Double(a.z), bx: Double(b.x), bz: Double(b.z))
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
        let pareti = r.walls.map(tratto)
        return ScansioneLidar(nome: "Stanza del " + Date().formatted(date: .numeric, time: .shortened),
                              area: area(r), perimetro: pareti.reduce(0) { $0 + $1.lunghezza }, altezza: altezza(r),
                              pareti: pareti, porte: r.doors.map(tratto), finestre: r.windows.map(tratto),
                              aperture: r.openings.map(tratto), oggetti: r.objects.map { nome($0.category) })
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
