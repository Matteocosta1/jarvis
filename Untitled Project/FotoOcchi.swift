#if os(iOS)
import SwiftUI
import Combine
import UIKit
import ImageIO
import QuartzCore

// MARK: - 13.9 (22) · FOTO di Occhi (il signore, 28 nov 06:04–06:27, mockup Telefono approvato)
// Negli Occhi manuali (dall'icona o a voce) ogni scatto va a JARVIS e la fotocamera resta aperta. Lo scatto diventa una FOTO da
// scegliere: la miniatura sopra CERCA (l'ultima; con più foto la pila e il numero), la foto vera in chat sotto la domanda. Un tocco
// apre FOTO, il cover flow (come Digging di Vinyl Hustler e la tab PAGINE): di lato una foto alla volta; sulla foto al centro su →
// ARCHIVIO (l'Archivio di JARVIS, cartella «occhi»), giù → SCARTA; un tocco sulla foto la apre a tutto schermo. A voce «salvala» e
// «scartala». Le foto stanno sul telefono (Application Support/FotoOcchi) finché sono da scegliere o si vedono in chat.

/// Da scegliere (nella miniatura e in FOTO) o già nell'Archivio (resta in chat col bordo acceso).
nonisolated enum StatoFotoOcchi: String, Codable, Sendable { case attesa, archivio }

nonisolated struct ScattoOcchi: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let quando: Date
    var stato: StatoFotoOcchi
    /// 1 la foto; 4 i fotogrammi del giro (REC).
    let fotogrammi: Int
}

@MainActor
final class FotoOcchi: ObservableObject {
    static let condivise = FotoOcchi()
    typealias Scatto = ScattoOcchi

    @Published private(set) var scatti: [Scatto] = []
    /// FOTO aperto dalla chat (sopra la chat, con «Chiudi»), da questo scatto.
    @Published var dallaChat: UUID?
    /// FOTO aperto: «salvala» / «scartala» a voce sulla foto al centro, con lo stesso volo dello swipe (-1 su, +1 giù).
    var flusso: ((Int) -> Bool)?
    /// La descrizione per l'Archivio (la prima frase della risposta di JARVIS): la dà Jarvis.
    var descrizione: ((UUID) -> String?)?

    var inAttesa: [Scatto] { scatti.filter { $0.stato == .attesa } }

    private var anteprime: [UUID: UIImage] = [:]
    private let cartella: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cartella = base.appendingPathComponent("FotoOcchi", isDirectory: true)
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: indice), let s = try? JSONDecoder().decode([Scatto].self, from: d) {
            scatti = s.filter { FileManager.default.fileExists(atPath: file($0.id, 0).path) }
        }
    }

    private var indice: URL { cartella.appendingPathComponent("indice.json") }
    private func file(_ id: UUID, _ k: Int) -> URL { cartella.appendingPathComponent("\(id.uuidString)-\(k).jpg") }

    private func salvaIndice() {
        if let d = try? JSONEncoder().encode(scatti) { try? d.write(to: indice, options: .atomic) }
    }

    /// Uno scatto nuovo (la foto, o i fotogrammi del giro): fra le FOTO da scegliere. Il suo id va al messaggio in chat.
    func aggiungi(_ dati: [Data]) -> UUID? {
        guard !dati.isEmpty else { return nil }
        let id = UUID()
        for (k, d) in dati.enumerated() {
            guard (try? d.write(to: file(id, k), options: .atomic)) != nil else { return nil }
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2)) {
            scatti.append(Scatto(id: id, quando: Date(), stato: .attesa, fotogrammi: dati.count))
        }
        salvaIndice()
        return id
    }

    func scatto(_ id: UUID) -> Scatto? { scatti.first { $0.id == id } }

    /// La foto piccola (lato 720) per la miniatura, il cover flow e la chat: letta una volta e tenuta.
    func anteprima(_ id: UUID) -> UIImage? {
        if let a = anteprime[id] { return a }
        guard let s = CGImageSourceCreateWithURL(file(id, 0) as CFURL, nil) else { return nil }
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                  kCGImageSourceThumbnailMaxPixelSize: 720]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, o as CFDictionary) else { return nil }
        let a = UIImage(cgImage: cg)
        anteprime[id] = a
        return a
    }

    /// La foto intera (a tutto schermo), letta solo quando serve.
    func immagine(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: file(id, 0).path) }

    /// Su: nell'Archivio di JARVIS (cartella «occhi»), con la coda sicura dell'Archivio (riparte da sola se manca la rete).
    /// Esce dalle FOTO da scegliere; in chat resta, col bordo acceso.
    @discardableResult
    func archivia(_ id: UUID) -> Bool {
        guard let i = scatti.firstIndex(where: { $0.id == id }), scatti[i].stato == .attesa else { return false }
        let s = scatti[i]
        let nome = "Occhi " + ArchivioCentrale.quando(s.quando)
        let detto = descrizione?(id)
        let gruppo = s.fotogrammi > 1 ? "occhi-\(id.uuidString)" : nil
        for k in 0..<s.fotogrammi {
            guard let d = try? Data(contentsOf: file(id, k)) else { continue }
            ArchivioCentrale.copia(nome: s.fotogrammi > 1 ? "\(nome) · giro \(k + 1)" : nome, cartella: "occhi", tipo: "image/jpeg", dati: d,
                                   descrizione: detto.map { "Occhi · \($0)" } ?? "Occhi", gruppo: gruppo)
        }
        scatti[i].stato = .archivio
        salvaIndice()
        Suoni.pronto()
        return true
    }

    /// Giù: via dal telefono (le FOTO da scegliere e la chat). Al cervello era già arrivata con la domanda.
    @discardableResult
    func scarta(_ id: UUID) -> Bool {
        guard let i = scatti.firstIndex(where: { $0.id == id }), scatti[i].stato == .attesa else { return false }
        let s = scatti.remove(at: i)
        togliFile(s)
        salvaIndice()
        Suoni.filoVia()
        return true
    }

    /// Restano le foto da scegliere e quelle ancora in chat (`legate`); le altre (archiviate, uscite dalla chat) si tolgono dal telefono.
    func tieni(_ legate: Set<UUID>) {
        let via = scatti.filter { $0.stato != .attesa && !legate.contains($0.id) }
        guard !via.isEmpty else { return }
        via.forEach(togliFile)
        scatti.removeAll { s in via.contains { $0.id == s.id } }
        salvaIndice()
    }

    private func togliFile(_ s: Scatto) {
        for k in 0..<s.fotogrammi { try? FileManager.default.removeItem(at: file(s.id, k)) }
        anteprime[s.id] = nil
    }
}

// MARK: - La miniatura sopra CERCA

/// L'ultimo scatto da scegliere, 38 punti; con 2 foto un bordo dietro, con 3 o più due bordi e il numero (che continua a salire).
struct MiniaturaFoto: View {
    let apri: () -> Void
    @ObservedObject private var foto = FotoOcchi.condivise

    var body: some View {
        let lista = foto.inAttesa
        if let ultima = lista.last {
            Button(action: apri) {
                ZStack {
                    if lista.count >= 3 { bordoDietro.offset(x: 8, y: -8).opacity(0.55) }
                    if lista.count >= 2 { bordoDietro.offset(x: 4, y: -4) }
                    Group {
                        if let a = foto.anteprima(ultima.id) { Image(uiImage: a).resizable().scaledToFill() } else { Color.black }
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.ciano.opacity(0.6), lineWidth: 1))
                    .shadow(color: Color.ciano.opacity(0.35), radius: 4)
                    .id(ultima.id)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                .frame(width: 38, height: 38)
                .overlay(alignment: .topTrailing) {
                    if lista.count > 1 {
                        Text("\(lista.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.ciano)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Color(red: 0.01, green: 0.06, blue: 0.09)))
                            .overlay(Capsule().stroke(Color.ciano, lineWidth: 1))
                            .offset(x: 17, y: -15)
                            .contentTransition(.numericText())
                    }
                }
                .frame(width: 60, height: 54)
                .contentShape(Rectangle())
            }
            .buttonStyle(StileStark())
            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.2), value: lista.map(\.id))
            .accessibilityLabel(lista.count > 1 ? "\(lista.count) foto da scegliere" : "Una foto da scegliere")
            .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }

    private var bordoDietro: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(red: 0.016, green: 0.07, blue: 0.1))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.ciano.opacity(0.45), lineWidth: 1))
            .frame(width: 38, height: 38)
    }
}

// MARK: - La foto in chat, sotto la domanda

/// Un tocco apre FOTO da lì; archiviata ha il bordo acceso (e un tocco dice dov'è).
struct FotoInChat: View {
    let id: UUID
    @ObservedObject private var foto = FotoOcchi.condivise

    var body: some View {
        if let s = foto.scatto(id), let a = foto.anteprima(id) {
            let archivio = s.stato == .archivio
            Image(uiImage: a)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 120, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.ciano.opacity(archivio ? 1 : 0.4), lineWidth: 1))
                .shadow(color: Color.ciano.opacity(archivio ? 0.35 : 0), radius: 4)
                .padding(.top, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    Suoni.tocco()
                    if archivio { OcchiAperti.parla?("È nell'archivio, Sir: Sistemi, Archivio, cartella occhi.") }
                    else { withAnimation(.easeOut(duration: 0.22)) { foto.dallaChat = id } }
                }
                .accessibilityLabel(archivio ? "Foto di Occhi, nell'archivio" : "Foto di Occhi, da scegliere")
                .accessibilityAddTraits(.isButton)
        }
    }
}

/// FOTO aperto dalla chat: sopra la schermata, si chiude con «Chiudi» (qui non c'è la fotocamera).
struct FotoDallaChat: View {
    @ObservedObject private var foto = FotoOcchi.condivise
    var body: some View {
        if let k = foto.dallaChat {
            FlussoFoto(conCamera: false, inizio: k) { withAnimation(.easeIn(duration: 0.16)) { foto.dallaChat = nil } }
                .transition(.opacity)
        }
    }
}

// MARK: - FOTO, il cover flow

struct FlussoFoto: View {
    /// Aperto dagli Occhi (sopra la fotocamera) o dalla chat: stesso FOTO, si torna con un tocco fuori dalla foto.
    let conCamera: Bool
    let inizio: UUID?
    let chiudi: () -> Void

    @ObservedObject private var foto = FotoOcchi.condivise
    /// Le foto nel flusso: quelle da scegliere quando si apre (una che vola via resta qui finché il volo finisce).
    @State private var lista: [UUID] = []
    @State private var off: Double = 0
    @State private var off0: Double = 0
    @State private var asse: Asse = .nessuno
    @State private var dy: CGFloat = 0
    @State private var cartaSu: UUID?
    @State private var vola: (id: UUID, verso: CGFloat)?
    @State private var piena = false
    @State private var grande: UIImage?
    @State private var avviso: String?
    @State private var giroAvviso = 0
    @State private var aperto = false

    private enum Asse { case nessuno, lato, su, nulla }

    var body: some View {
        VStack(spacing: 0) {
            testata
            Text("↑ ARCHIVIO")
                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3)
                .foregroundStyle(Color.ciano)
                .opacity(guida(su: true))
                .padding(.top, 10)
            GeometryReader { g in palco(g.size) }
            Text("↓ SCARTA")
                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(3)
                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.38))
                .opacity(guida(su: false))
                .padding(.bottom, 6)
            Text(avviso ?? conto)
                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Color.tenue)
                .lineLimit(1)
                .frame(minHeight: 14)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .contentTransition(.opacity)
        }
        .background(Color(red: 0.008, green: 0.03, blue: 0.047).opacity(0.95).ignoresSafeArea())
        .contentShape(Rectangle())
        // 06:48 (il signore: «quella X sembra che chiuda l'app»): niente X né «Chiudi»; il tocco fuori dalla foto (testata, scritte,
        // il vuoto intorno) torna dov'era, negli Occhi o in chat. Sulle foto decidono le foto (lì sopra c'è il loro gesto)
        .onTapGesture { Suoni.tocco(); chiudi() }
        .accessibilityAction(named: "Torna indietro") { chiudi() }
        .onAppear {
            lista = foto.inAttesa.map(\.id)
            guard !lista.isEmpty else { chiudi(); return }
            off = Double(inizio.flatMap { lista.firstIndex(of: $0) } ?? 0)
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24)) { aperto = true }
            foto.flusso = { verso in
                guard lista.indices.contains(Int(off.rounded())), vola == nil else { return false }
                via(lista[Int(off.rounded())], verso: verso)
                return true
            }
        }
        .onDisappear { foto.flusso = nil }
        // archiviata o scartata a voce da fuori (FOTO chiuso non succede; qui per sicurezza): esce anche dal flusso
        .onChange(of: foto.inAttesa.map(\.id)) { _, ids in
            let restano = lista.filter { ids.contains($0) || $0 == vola?.id }
            if restano.count != lista.count { lista = restano; off = min(off, Double(max(0, restano.count - 1))) }
            if lista.isEmpty { chiudi() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Foto")
    }

    private var testata: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FOTO").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                Text("OCCHI · \(lista.count) FOTO DA SCEGLIERE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                    .opacity(0.7)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Color.ciano)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var conto: String {
        lista.isEmpty ? "" : "\(min(lista.count - 1, max(0, Int(off.rounded()))) + 1) / \(lista.count)"
    }

    /// «↑ ARCHIVIO» / «↓ SCARTA»: tenui, si accendono mentre il dito porta la foto da quella parte.
    private func guida(su: Bool) -> Double {
        guard cartaSu != nil, su ? dy < 0 : dy > 0 else { return 0.35 }
        return 0.35 + 0.65 * min(1, Double(abs(dy)) / 140)
    }

    // MARK: le foto

    private func misure(_ s: CGSize) -> (w: Double, h: Double) {
        let W = Double(s.width), H = Double(s.height)
        let h = max(140, min(H * 0.7, W * 0.62 * 4 / 3, 420))
        return (h * 0.75, h)
    }

    private func palco(_ size: CGSize) -> some View {
        let (w, h) = misure(size)
        let W = Double(size.width), H = Double(size.height)
        let centro = Int(off.rounded())
        return ZStack(alignment: .topLeading) {
            // la riga di luce sotto le foto, come il Cover Flow di Digging
            LinearGradient(stops: [.init(color: Color.ciano.opacity(0), location: 0), .init(color: Color.ciano.opacity(0.75), location: 0.3),
                                   .init(color: Color.ciano.opacity(0.75), location: 0.7), .init(color: Color.ciano.opacity(0), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: max(0, W - 36), height: 1)
                .shadow(color: Color.ciano, radius: 3)
                .offset(x: 18, y: H / 2 + h / 2 + 6)
                .opacity(piena ? 0 : 1)
                .allowsHitTesting(false)
            ForEach(Array(lista.enumerated()), id: \.element) { i, id in
                let d = Double(i) - off, ad = abs(d)
                if ad <= 3.6 {
                    let alCentro = i == centro
                    let tutta = piena && alCentro
                    let ww = tutta ? W - 24 : w, hh = tutta ? H - 12 : h
                    let su = cartaSu == id ? dy : 0
                    let u = min(1, Double(abs(su)) / (h * 1.1))
                    let voloVia = vola?.id == id
                    carta(id, w: ww, h: hh, scuro: 0.45 * min(1, ad), tutta: tutta)
                        .modifier(EffettoFlussoFoto(d: d, cw: w))
                        .scaleEffect(CGFloat(voloVia ? 0.82 : 1 - 0.18 * u))
                        .rotationEffect(.degrees(voloVia && (vola?.verso ?? 0) > 0 ? 6 : 0))
                        .offset(y: voloVia ? (vola?.verso ?? 0) * CGFloat(h * 1.4) : su)
                        .opacity(voloVia ? 0 : (ad > 3.2 ? 0 : min(1, 3.6 - ad)) * (1 - 0.75 * u) * (piena && !alCentro ? 0 : 1))
                        .offset(x: W / 2 - ww / 2, y: H / 2 - hh / 2)
                        .zIndex(200 - (ad * 10).rounded())
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .scaleEffect(aperto ? 1 : 0.96)
        .opacity(aperto ? 1 : 0)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { segue($0, W: W, H: H, w: w, h: h) }
                .onEnded { fine($0, W: W, H: H, w: w, h: h) }
        )
        .clipped()
    }

    private func carta(_ id: UUID, w: Double, h: Double, scuro: Double, tutta: Bool) -> some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let img = (tutta ? grande : nil) ?? foto.anteprima(id)
        let vista = Group {
            if let img {
                if tutta { Image(uiImage: img).resizable().scaledToFit() } else { Image(uiImage: img).resizable().scaledToFill() }
            } else { Color.black }
        }
        return vista
            .frame(width: w, height: h)
            .background(Color.black)
            .overlay(Color.black.opacity(scuro))
            .clipShape(forma)
            .shadow(color: .black.opacity(0.65), radius: 18, y: 9)
            .overlay(alignment: .top) {
                if !tutta {                                           // il riflesso sotto, che sfuma
                    vista
                        .frame(width: w, height: h)
                        .overlay(Color.black.opacity(scuro))
                        .clipShape(forma)
                        .scaleEffect(x: 1, y: -1)
                        .mask(LinearGradient(stops: [.init(color: .black.opacity(0.22), location: 0), .init(color: .clear, location: 0.28)],
                                             startPoint: .top, endPoint: .bottom))
                        .offset(y: h + 3)
                        .allowsHitTesting(false)
                }
            }
    }

    /// La foto sotto il dito (la più davanti fra quelle che lo contengono, anche in altezza): fuori dalle foto, niente.
    private func cartaSotto(_ p: CGPoint, W: Double, H: Double, w: Double, h: Double) -> UUID? {
        let centro = Int(off.rounded())
        var meglio: (i: Int, z: Double)?
        let P = w * 2.3
        for i in lista.indices {
            let d = Double(i) - off, ad = abs(d)
            guard ad <= 3.2 else { continue }
            if piena && i != centro { continue }
            let a = min(1, ad), sg: Double = d < 0 ? -1 : (d > 0 ? 1 : 0)
            let px = sg * (a * w * 0.64 + max(0, ad - 1) * w * 0.26), z = -(a * 0.34 + max(0, ad - 1) * 0.06) * w
            let k = P / (P - z)
            let mezzoW = piena && i == centro ? (W - 24) / 2 : w / 2 * cos(a * 62 * .pi / 180) * k
            let mezzoH = piena && i == centro ? (H - 12) / 2 : h / 2 * k
            let cx = W / 2 + px * k
            if abs(Double(p.x) - cx) <= max(6, mezzoW), abs(Double(p.y) - H / 2) <= mezzoH,
               meglio.map({ 200 - ad * 10 > $0.z }) ?? true { meglio = (i, 200 - ad * 10) }
        }
        return meglio.map { lista[$0.i] }
    }

    private func segue(_ v: DragGesture.Value, W: Double, H: Double, w: Double, h: Double) {
        guard vola == nil, !lista.isEmpty else { return }
        let dx = Double(v.translation.width), dyy = v.translation.height
        if asse == .nessuno {
            guard hypot(dx, Double(dyy)) >= 6 else { return }
            off0 = off.rounded()
            let sopra = cartaSotto(v.startLocation, W: W, H: H, w: w, h: h)
            let alCentro = sopra != nil && sopra == lista[min(lista.count - 1, Int(off.rounded()))]
            asse = abs(dx) >= abs(Double(dyy)) ? (piena ? .nulla : .lato) : (alCentro ? .su : .nulla)
            cartaSu = asse == .su ? sopra : nil
        }
        switch asse {
        case .lato:
            // una foto alla volta («tac»): il dito sposta al massimo di una foto, qualunque sia la spinta
            let n = Double(lista.count - 1)
            let o = min(off0 + 1, max(off0 - 1, off0 - dx / (w * 0.32)))
            off = o < 0 ? o * 0.35 : (o > n ? n + (o - n) * 0.35 : o)
        case .su:
            dy = dyy
        default:
            break
        }
    }

    private func fine(_ v: DragGesture.Value, W: Double, H: Double, w: Double, h: Double) {
        defer { asse = .nessuno }
        guard vola == nil, !lista.isEmpty else { return }
        switch asse {
        case .nessuno:
            // un tocco: su una foto di lato la porta al centro; sulla foto al centro la apre a tutto schermo (un altro tocco torna);
            // fuori dalle foto torna dov'era (negli Occhi o in chat)
            guard let s = cartaSotto(v.startLocation, W: W, H: H, w: w, h: h), let i = lista.firstIndex(of: s) else { Suoni.tocco(); chiudi(); return }
            Suoni.tocco()
            if i != Int(off.rounded()) { piena = false; vaiA(i) }
            else {
                if !piena { grande = foto.immagine(s) }
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.26)) { piena.toggle() }
            }
        case .lato:
            let dx = Double(v.translation.width), vx = Double(v.velocity.width)
            let colpo = abs(dx) > 10 && abs(vx) > 300                       // un colpetto breve vale come uno lungo
            let k0 = Int(off0)
            if dx < -w * 0.12 || (colpo && vx < 0) { vaiA(k0 + 1) }
            else if dx > w * 0.12 || (colpo && vx > 0) { vaiA(k0 - 1) }
            else { vaiA(k0) }
        case .su:
            guard let s = cartaSu else { dy = 0; return }
            let d = Double(v.translation.height), vy = Double(v.velocity.height)
            if d < -h * 0.35 || vy < -500 { via(s, verso: -1) }
            else if d > h * 0.35 || vy > 500 { via(s, verso: 1) }
            else {
                withAnimation(.spring(duration: 0.26, bounce: 0.35)) { dy = 0 }
                Task { @MainActor in try? await Task.sleep(for: .milliseconds(270)); if dy == 0 { cartaSu = nil } }
            }
        case .nulla:
            break
        }
    }

    /// Porta la foto `k` al centro con la curva della tab PAGINE; quando si ferma, «tac».
    private func vaiA(_ k: Int) {
        guard !lista.isEmpty else { return }
        let a = Double(min(max(0, k), lista.count - 1))
        let cambia = abs(a - off.rounded()) > 0.01
        let durata = min(0.52, 0.22 + abs(a - off) * 0.15)
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: durata)) { off = a }
        if cambia {
            Task { @MainActor in try? await Task.sleep(for: .seconds(durata)); Suoni.tocco() }
        }
    }

    /// La foto va via: su nell'Archivio (vola in alto), giù scartata (cade). Poi le altre si stringono; finite, FOTO si chiude.
    private func via(_ id: UUID, verso: Int) {
        let ok = verso < 0 ? foto.archivia(id) : foto.scarta(id)
        guard ok else {
            withAnimation(.spring(duration: 0.26, bounce: 0.35)) { dy = 0 }
            cartaSu = nil
            return
        }
        UIImpactFeedbackGenerator(style: verso < 0 ? .medium : .light).impactOccurred()
        let nome = foto.scatto(id).map { "Occhi " + ArchivioCentrale.quando($0.quando) }
        mostra(verso < 0 ? "ARCHIVIO › OCCHI · \((nome ?? "").uppercased())" : "SCARTATA")
        withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 0.26)) { vola = (id, CGFloat(verso)) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(270))
            let i = lista.firstIndex(of: id) ?? 0
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                lista.removeAll { $0 == id }
                vola = nil; dy = 0; cartaSu = nil; piena = false; grande = nil
                off = min(off, Double(max(0, lista.count - 1)))
            }
            if lista.isEmpty {
                try? await Task.sleep(for: .milliseconds(200))
                chiudi()
                return
            }
            vaiA(min(i, lista.count - 1))
        }
    }

    private func mostra(_ t: String) {
        giroAvviso += 1
        let mio = giroAvviso
        withAnimation(.easeOut(duration: 0.2)) { avviso = t }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard mio == giroAvviso else { return }
            withAnimation(.easeOut(duration: 0.2)) { avviso = nil }
        }
    }
}

/// Il Cover Flow di FOTO (come Digging di Vinyl Hustler): la foto `d` posti dal centro va di lato, indietro e gira di 62° attorno
/// al suo asse, con la prospettiva centrata sulla foto. `d` si anima: lo scorrimento è fluido.
nonisolated private struct EffettoFlussoFoto: GeometryEffect {
    var d: Double
    let cw: Double

    var animatableData: Double {
        get { d }
        set { d = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let ad = abs(d), a = min(1, ad), sg: Double = d < 0 ? -1 : (d > 0 ? 1 : 0)
        let x = sg * (a * cw * 0.64 + max(0, ad - 1) * cw * 0.26)
        let rot = -sg * a * 62 * .pi / 180
        let z = -(a * 0.34 + max(0, ad - 1) * 0.06) * cw
        let mx = Double(size.width) / 2, my = Double(size.height) / 2
        var m = CATransform3DMakeTranslation(-mx, -my, 0)
        m = CATransform3DConcat(m, CATransform3DMakeRotation(rot, 0, 1, 0))
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(x, 0, z))
        var prospettiva = CATransform3DIdentity
        prospettiva.m34 = -1 / (cw * 2.3)
        m = CATransform3DConcat(m, prospettiva)
        m = CATransform3DConcat(m, CATransform3DMakeTranslation(mx, my, 0))
        return ProjectionTransform(m)
    }
}
#endif
