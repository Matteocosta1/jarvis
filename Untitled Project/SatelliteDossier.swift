#if os(iOS)
import SwiftUI
import MapKit
import Combine

// MARK: - Le foto dei luoghi

/// Una foto del dossier di un luogo: da dove è stata scattata (NAVIGA, GUIDA, DOSSIER), con quale fotocamera, quando,
/// se è in archivio.
struct FotoSat: Codable, Identifiable, Hashable {
    let id: UUID
    var luogo: String                 // la chiave del luogo (LuogoSat.chiave)
    let da: String                    // naviga, guida, dossier
    let cam: String                   // dietro, davanti
    let quando: Date
    var archiviata: Bool
    var file: String { id.uuidString + ".jpg" }
}

/// Le foto dei luoghi, sul telefono (Documenti › Satellite, come l'archivio di LiDAR): i file JPEG e un indice.
@MainActor
final class ArchivioFotoSat: ObservableObject {
    static let condiviso = ArchivioFotoSat()
    @Published private(set) var foto: [FotoSat] = []

    nonisolated static var cartella: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Satellite", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var indice: URL { Self.cartella.appendingPathComponent("foto.json") }

    init() {
        if let d = try? Data(contentsOf: indice), let f = try? JSONDecoder().decode([FotoSat].self, from: d) { foto = f }
    }

    /// Le foto di un luogo, dalla più recente.
    func di(_ luogo: String) -> [FotoSat] { foto.filter { $0.luogo == luogo } }

    /// Una foto nuova nel dossier del luogo. Falso se non si è potuta salvare.
    @discardableResult
    func aggiungi(_ dati: Data, luogo: String, da: String, cam: String) -> Bool {
        let f = FotoSat(id: UUID(), luogo: luogo, da: da, cam: cam, quando: Date(), archiviata: false)
        do { try dati.write(to: url(f), options: .atomic) } catch { return false }
        foto.insert(f, at: 0)
        scrivi()
        return true
    }

    func archivia(_ f: FotoSat, _ si: Bool) {
        guard let i = foto.firstIndex(where: { $0.id == f.id }) else { return }
        foto[i].archiviata = si
        scrivi()
    }

    func elimina(_ f: FotoSat) {
        foto.removeAll { $0.id == f.id }
        try? FileManager.default.removeItem(at: url(f))
        scrivi()
    }

    /// Un luogo della ricognizione salvato tra i Ricordi: le sue foto passano al luogo salvato.
    func sposta(da vecchia: String, a nuova: String) {
        var cambiate = false
        for i in foto.indices where foto[i].luogo == vecchia { foto[i].luogo = nuova; cambiate = true }
        if cambiate { scrivi() }
    }

    func url(_ f: FotoSat) -> URL { Self.cartella.appendingPathComponent(f.file) }

    /// L'immagine rimpicciolita (le miniature) o intera. La foto vera è di 12 milioni di pixel: si decodifica fuori dal
    /// thread principale (byPreparingThumbnail), se no ogni miniatura del DOSSIER bloccava lo schermo per decine di millisecondi.
    func immagine(_ f: FotoSat, lato: CGFloat? = nil) async -> UIImage? {
        guard let i = UIImage(contentsOfFile: url(f).path) else { return nil }        // qui non si decodifica ancora niente
        let s = lato.map { min(1, $0 / max(i.size.width, i.size.height, 1)) } ?? 1
        return await i.byPreparingThumbnail(ofSize: CGSize(width: i.size.width * s, height: i.size.height * s)) ?? i
    }

    private func scrivi() { if let d = try? JSONEncoder().encode(foto) { try? d.write(to: indice, options: .atomic) } }

    /// «ven 23 ott, 21:40», come nel mockup.
    static func quando(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Il DOSSIER

/// La scheda del luogo a tutto schermo, come nel mockup: DOSSIER, il nome e la categoria, la X nel cerchio; la vista da
/// strada (Look Around), FOTO · ARCHIVIO con le foto (toccata: a grande), Luogo, Distanza, Visite, Note; Foto · Ricorda,
/// Naviga · Guida.
struct SchermoDossier: View {
    let luogo: LuogoSat
    let categoria: CategoriaSat
    /// I ricordi salvati lì (entro 60 m), dal più recente: le visite e le note.
    let vicini: [DatiRicordi.Riga]
    /// «198 m · circa 2 minuti».
    let distanza: String
    let apri: (PaginaSat?) -> Void
    /// Dopo «Ricorda» su una ricognizione: SATELLITE ricarica i luoghi e riapre il dossier sul luogo salvato (la sua chiave).
    var salvato: (String) async -> Void = { _ in }
    @ObservedObject private var archivio = ArchivioFotoSat.condiviso
    @State private var vista: UIImage?
    @State private var cercata = false
    @State private var archivioAperto = false
    @State private var aperta: FotoSat?
    @State private var lavoro = false
    @State private var avviso: String?

    private var tutte: [FotoSat] { archivio.di(luogo.chiave) }
    private var mostrate: [FotoSat] { tutte.filter { $0.archiviata == archivioAperto } }

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            VStack(spacing: 0) {
                testa(titolo: "DOSSIER", sotto: "\(luogo.nome.uppercased()) · \(categoria.rawValue)") { Suoni.tocco(); apri(nil) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        vistaDaStrada
                        HStack(spacing: 6) {
                            scheda("FOTO", tutte.filter { !$0.archiviata }.count, acceso: !archivioAperto) { archivioAperto = false }
                            scheda("ARCHIVIO", tutte.filter(\.archiviata).count, acceso: archivioAperto) { archivioAperto = true }
                        }
                        griglia
                        if let avviso { AvvisoJarvis(testo: avviso) }
                        RigaHUD("Luogo", luogo.nome == luogo.via ? luogo.nome : "\(luogo.nome) · \(luogo.via)")
                        RigaHUD("Distanza", distanza)
                        RigaHUD("Visite", visite)
                        RigaHUD("Note", nota)
                        HStack(spacing: 8) {
                            TastoSat(testo: "Foto", attivo: !lavoro) { Task { await fotoDaStrada() } }
                            TastoSat(testo: "Ricorda", attivo: !lavoro) { Task { await ricorda() } }
                        }
                        HStack(spacing: 8) {
                            TastoSat(testo: "Naviga", alto: 48) { Suoni.tocco(); apri(.naviga(luogo)) }
                            TastoSat(testo: "Guida", pieno: true, alto: 48) { Suoni.tocco(); apri(.guida(luogo)) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            if let f = aperta {
                VistaFotoSat(foto: f, luogo: luogo, chiudi: { aperta = nil })
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task { await caricaVista() }
    }

    // MARK: Pezzi

    private var vistaDaStrada: some View {
        Color(red: 0.03, green: 0.07, blue: 0.08)
            .aspectRatio(720.0 / 400.0, contentMode: .fit)
            .overlay {
                if let vista {
                    Image(uiImage: vista).resizable().scaledToFill()
                } else if cercata {
                    Text("NON DISPONIBILE QUI").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(Color.tenue)
                }
            }
            .overlay(alignment: .bottom) {
                Text("VISTA DA STRADA · \(luogo.via.uppercased())")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(ColoriHUD.chiaro).lineLimit(1)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.02, green: 0.03, blue: 0.035).opacity(0.6))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ciano.opacity(0.4), lineWidth: 1))
    }

    private func scheda(_ nome: String, _ n: Int, acceso: Bool, _ azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            (Text(nome).foregroundColor(acceso ? Color.ciano : Color.ciano.opacity(0.7)) + Text(" \(n)").foregroundColor(.white))
                .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Capsule().fill(Color.ciano.opacity(acceso ? 0.16 : 0)))
                .overlay(Capsule().stroke(Color.ciano.opacity(acceso ? 1 : 0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(StileStark())
    }

    @ViewBuilder private var griglia: some View {
        if mostrate.isEmpty {
            Text(archivioAperto ? "ARCHIVIO VUOTO" : "NESSUNA FOTO · LE SCATTA DA NAVIGA O GUIDA")
                .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Color.tenue).multilineTextAlignment(.center)
                .padding(14).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(mostrate) { f in
                Button { Suoni.tocco(); withAnimation(.easeOut(duration: 0.2)) { aperta = f } } label: { MiniaturaSat(foto: f) }
                    .buttonStyle(StileStark())
                    .accessibilityLabel("Foto \(MiniaturaSat.da(f.da)), \(ArchivioFotoSat.quando(f.quando))")
            }
        }
    }

    /// «12 volte · ultima ven 23 ott, 21:40, con Matteo»: quante volte ha salvato qualcosa lì, l'ultima e con chi.
    private var visite: String {
        guard luogo.ricordo != nil, let ultima = vicini.first else { return "mai" }
        let n = vicini.count
        var t = "\(n) \(n == 1 ? "volta" : "volte") · ultima \(ultima.quando)"
        if let p = vicini.compactMap(\.persona).first { t += ", con \(p)" }
        return t
    }

    /// L'ultima cosa segnata lì che non è il luogo stesso (una nota, un oggetto, una cosa vista…).
    private var nota: String {
        if luogo.tipo == "ricognizione" { return "Ricognizione dal satellite." }
        return vicini.first { $0.id != luogo.ricordo && !["posto", "parcheggio"].contains($0.tipo) }?.testo ?? "—"
    }

    private func caricaVista() async {
        if let s = await VistaStrada.scena(guardando: luogo.coordinata) { vista = await VistaStrada.foto(s, larga: 720, alta: 400) }
        cercata = true
    }

    // MARK: Foto e Ricorda

    /// FOTO: la vista da strada del luogo entra nel dossier (fotocamera dietro), come nel mockup.
    private func fotoDaStrada() async {
        guard !lavoro else { return }
        lavoro = true
        defer { lavoro = false }
        guard let s = await VistaStrada.scena(guardando: luogo.coordinata),
              let img = await VistaStrada.foto(s, larga: 1200, alta: 900), let d = img.jpegData(compressionQuality: 0.85) else {
            Suoni.errore(); avviso = "Qui Apple non ha la vista da strada, Sir."; return
        }
        guard archivio.aggiungi(d, luogo: luogo.chiave, da: "dossier", cam: "dietro") else { Suoni.errore(); return }
        Suoni.pronto()
        avviso = nil
        archivioAperto = false
        AvvisoSat.mostra("Foto salvata nel dossier di \(luogo.nome), Sir.")
    }

    /// RICORDA: il luogo entra nei Ricordi con la sua posizione (luogo_salva del cervello, come «Salva» di TRACCIA);
    /// le foto del dossier passano al luogo salvato. Un luogo già salvato è già nei Ricordi.
    private func ricorda() async {
        guard !lavoro else { return }
        guard luogo.ricordo == nil else {
            Suoni.pronto(); AvvisoSat.mostra("\(luogo.nome) è già nei Ricordi, Sir."); return
        }
        lavoro = true
        defer { lavoro = false }
        let nome = luogo.nome == "Ricognizione" ? luogo.via : luogo.nome
        guard let o = await VistaVitals.chiama(["luogo_salva": ["lat": luogo.lat, "lon": luogo.lon, "nome": nome] as [String: Any]], attesa: 15),
              let riga = o["luogo"] as? [String: Any], let id = (riga["id"] as? NSNumber)?.intValue else {
            Suoni.errore(); avviso = "Il luogo non si è salvato, Sir: riprovi tra poco."; return
        }
        archivio.sposta(da: luogo.chiave, a: "r\(id)")
        Suoni.pronto()
        avviso = nil
        AvvisoSat.mostra("Segnato nei Ricordi: \(nome), con foto e posizione.")
        await salvato("r\(id)")
    }

    private func testa(titolo: String, sotto: String, chiudi: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(titolo).font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                Text(sotto).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.75).lineLimit(1)
            }
            .foregroundStyle(Color.ciano)
            Spacer(minLength: 4)
            Button(action: chiudi) {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ciano).frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(StileStark())
            .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
    }
}

/// Una miniatura del dossier: la foto 4:3 e da dove viene («DOSSIER», «◐ GUIDA» se con la fotocamera davanti).
struct MiniaturaSat: View {
    let foto: FotoSat
    @State private var img: UIImage?

    static func da(_ d: String) -> String { ["naviga": "NAVIGA", "guida": "GUIDA", "dossier": "DOSSIER"][d] ?? d.uppercased() }

    var body: some View {
        Color(red: 0.03, green: 0.07, blue: 0.08)
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .bottomLeading) {
                Text((foto.cam == "davanti" ? "◐ " : "") + MiniaturaSat.da(foto.da))
                    .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
                    .foregroundStyle(.white)
                    .padding(.vertical, 2).padding(.horizontal, 5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.6)))
                    .padding(5)
            }
            .task(id: foto.id) { img = await ArchivioFotoSat.condiviso.immagine(foto, lato: 360) }
    }
}

/// Una foto a grande: FOTO e il luogo, la X; da dove e quando; Archivia (o Ripristina) ed Elimina, che chiede conferma
/// con un secondo tocco entro 3 secondi.
struct VistaFotoSat: View {
    let foto: FotoSat
    let luogo: LuogoSat
    let chiudi: () -> Void
    @State private var img: UIImage?
    @State private var sicuro = false
    @State private var giro = 0

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.024, blue: 0.027).opacity(0.96).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FOTO").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                        Text(luogo.nome.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.75)
                    }
                    .foregroundStyle(Color.ciano)
                    Spacer()
                    Button { Suoni.tocco(); chiudi() } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.ciano).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(StileStark())
                    .accessibilityLabel("Chiudi")
                }
                Color(red: 0.03, green: 0.07, blue: 0.08)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.4), lineWidth: 1))
                Text("\(MiniaturaSat.da(foto.da)) · \(foto.cam.uppercased()) · \(ArchivioFotoSat.quando(foto.quando))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
                HStack(spacing: 8) {
                    TastoSat(testo: foto.archiviata ? "Ripristina" : "Archivia") {
                        Suoni.pronto()
                        ArchivioFotoSat.condiviso.archivia(foto, !foto.archiviata)
                        chiudi()
                        AvvisoSat.mostra(foto.archiviata ? "Foto ripristinata, Sir." : "Foto archiviata, Sir.")
                    }
                    TastoSat(testo: sicuro ? "Conferma" : "Elimina", rosso: true, conferma: sicuro) { elimina() }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 22)
        }
        .task { img = await ArchivioFotoSat.condiviso.immagine(foto, lato: 1600) }
    }

    /// Il primo tocco chiede conferma (3 secondi), il secondo elimina.
    private func elimina() {
        guard sicuro else {
            Suoni.tocco()
            sicuro = true
            giro += 1
            let mio = giro
            Task { try? await Task.sleep(for: .seconds(3)); if giro == mio { sicuro = false } }
            return
        }
        Suoni.pronto()
        ArchivioFotoSat.condiviso.elimina(foto)
        chiudi()
        AvvisoSat.mostra("Foto eliminata, Sir.")
    }
}
#endif
