#if os(iOS)
import SwiftUI
import Combine
import UIKit
import MapKit
import CoreLocation
import WeatherKit
import Photos
import Vision
import UserNotifications

// MARK: - FRIGO (SENSI): cosa c'è dentro e per quanto, dagli Occhi o a mano; il finito va in Spesa.

struct CosaFrigo: Codable, Equatable, Identifiable {
    var id = UUID()
    var nome: String
    var quanti = 1
    var scade: Date
}

struct VistaFrigo: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @StateObject private var frigo = Salvato<[CosaFrigo]>("frigo", iniziale: [])
    @StateObject private var finiti = Salvato<[String]>("frigo_finiti", iniziale: [])
    @StateObject private var ultima = Salvato<Date?>("frigo_scansione", iniziale: nil)
    @State private var foto = false
    @State private var guardo = false
    @State private var nuovo = ""
    @State private var giorni = 5

    var body: some View {
        CorniceScheda(titolo: "Frigo", sottotitolo: ultima.valore.map { "Ultima scansione \($0.formatted(.dateTime.weekday().hour().minute()))" } ?? "Da scansionare",
                      icona: "f:frigo", tinta: tinta, fotocamera: true) {
            TastoF(testo: guardo ? "Guardo…" : "Inquadra il frigo", icona: "camera.viewfinder") { foto = true }.disabled(guardo)
            Pannello(titolo: "DENTRO", tinta: tinta) {
                if frigo.valore.isEmpty { NotaF(testo: "Inquadra il frigo aperto: FRIDAY riconosce cosa c'è e per quanto si conserva.") }
                ForEach(frigo.valore.sorted { $0.scade < $1.scade }) { c in
                    let d = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: c.scade).day ?? 0
                    HStack {
                        RigaF(etichetta: c.quanti > 1 ? "\(c.nome) × \(c.quanti)" : c.nome, valore: d <= 0 ? "da finire oggi" : "\(d) giorni", stato: d <= 2 ? .no : d >= 7 ? .ok : .normale)
                        Button { finito(c) } label: { Image(systemName: "checkmark.circle") }.foregroundStyle(tinta).buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("", text: $nuovo, prompt: Text("Aggiungi: mozzarella…").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                    Stepper("\(giorni) g", value: $giorni, in: 1...60).fixedSize().foregroundStyle(Color.tenue)
                    Button { aggiungi(nuovo, giorni: giorni) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
                }
            }
            if !finiti.valore.isEmpty {
                Pannello(titolo: "FINITO", tinta: tinta) {
                    ForEach(finiti.valore.suffix(5).reversed(), id: \.self) { RigaF(etichetta: $0, valore: "aggiunto a Spesa", stato: .ok) }
                }
            }
            TastoJarvis(testo: "Cosa cucino con questi?", icona: "fork.knife", tinta: tinta) {
                chiedi("Cosa cucino con quello che ho in frigo? Ho: " + frigo.valore.map(\.nome).joined(separator: ", ") + ". Prima quello che scade prima.")
            }
        }
        .fullScreenCover(isPresented: $foto) { Fotocamera(sorgente: .camera) { img in Task { await guarda(img) } }.ignoresSafeArea() }
    }

    private func aggiungi(_ n: String, giorni: Int, quanti: Int = 1) {
        let n = n.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let scade = Calendar.current.date(byAdding: .day, value: giorni, to: Calendar.current.startOfDay(for: Date()))!
        if let i = frigo.valore.firstIndex(where: { $0.nome.caseInsensitiveCompare(n) == .orderedSame }) {
            frigo.valore[i].quanti = quanti; frigo.valore[i].scade = scade
        } else { frigo.valore.append(CosaFrigo(nome: n, quanti: quanti, scade: scade)) }
        nuovo = ""
    }

    private func finito(_ c: CosaFrigo) {
        Suoni.fatto()
        frigo.valore.removeAll { $0.id == c.id }
        finiti.valore.append(c.nome)
        Task { _ = await VistaVitals.chiama(["ricordo_aggiungi": c.nome, "tipo": "spesa"]) }
    }

    private func guarda(_ img: UIImage) async {
        guard let b64 = img.jpegFriday(lato: 1280) else { return }
        guardo = true; defer { guardo = false }
        guard let o = await VistaVitals.chiama(["vista": ["compito": "frigo", "immagine": b64]], attesa: 60) else { return }
        for c in o["cose"] as? [[String: Any]] ?? [] {
            aggiungi(c["nome"] as? String ?? "", giorni: (c["giorni"] as? NSNumber)?.intValue ?? 5, quanti: (c["quanti"] as? NSNumber)?.intValue ?? 1)
        }
        ultima.valore = Date()
        Suoni.schedaPronta()
    }
}

// MARK: - NANDO (STRUMENTI): pipì, giochi, giri registrati, salute e veterinario, galleria, volantino se si perde.

struct GiroNando: Codable, Equatable, Identifiable {
    var id = UUID()
    var nome = "Giro"
    var inizio = Date()
    var minuti = 0
    var metri = 0.0
    var punti: [[Double]] = []
    var pipi: [[Double]] = []
}

struct DatiNando: Codable, Equatable {
    var pipi: [Date] = []
    var giocoMinuti: [String: Int] = [:]
    var orari: [String] = ["07:30", "13:00", "19:00", "23:00"]
    var giri: [GiroNando] = []
    var razza = "barboncino", eta = "", peso = ""
    var studio = "", medico = "", telefono = "", microchip = "", allergie = "", farmaci = ""
    var visite: [String] = []
    var scadenze: [String: Date] = [:]
    var amici: [String] = []
    var pelo: String = ""
}

struct VistaNando: View {
    let chiedi: (String) -> Void
    private let tinta = Color.ciano
    @StateObject private var n = Salvato<DatiNando>("nando", iniziale: DatiNando())
    @StateObject private var giro = GiroInCorso.condiviso
    @State private var parte = 0
    @State private var foto: String?
    @State private var esitoCibo: String?
    @State private var radar: [(String, String, RigaF.Stato)] = []
    @State private var galleria: [PHAsset] = []
    @State private var cercoFoto = false
    @State private var volantino: Image?
    @State private var nuovaScadenza = ""
    @State private var dataScadenza = Date()
    @State private var nuovaVisita = ""

    var body: some View {
        CorniceScheda(titolo: "Nando", sottotitolo: prossimoGiro.map { "Prossimo giro \($0)" } ?? "In casa", icona: "f:nando", tinta: tinta) {
            Text(giro.attivo ? "NANDO · IN GIRO" : "NANDO · IN CASA").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(tinta)
            LinguetteF(voci: ["Oggi", "Percorsi", "Salute", "Archivio"], scelta: $parte)
            switch parte {
            case 0: oggi
            case 1: percorsi
            case 2: salute
            default: archivio
            }
        }
        .fullScreenCover(item: Binding(get: { foto.map { FotoChiesta(compito: $0) } }, set: { foto = $0?.compito })) { f in
            Fotocamera(sorgente: .camera) { img in Task { await guarda(img, compito: f.compito) } }.ignoresSafeArea()
        }
        .task { programmaGiri(); await caricaRadar() }
    }

    struct FotoChiesta: Identifiable { let compito: String; var id: String { compito } }

    private var oggiPipi: [Date] { n.valore.pipi.filter { Calendar.current.isDateInToday($0) } }
    private var ritmoOre: Double {
        let u = n.valore.pipi.suffix(10)
        let gap = zip(u, u.dropFirst()).map { $1.timeIntervalSince($0) / 3600 }.filter { $0 > 1 && $0 < 12 }
        return gap.isEmpty ? 4 : gap.reduce(0, +) / Double(gap.count)
    }
    /// Un giro di oggi iniziato entro 45 minuti dall'orario previsto.
    private func giroFatto(alle o: String) -> Bool {
        let p = o.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, let previsto = Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date()) else { return false }
        return n.valore.giri.contains { Calendar.current.isDateInToday($0.inizio) && abs($0.inizio.timeIntervalSince(previsto)) <= 45 * 60 }
    }
    private var prossimoGiro: String? {
        let ora = Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return n.valore.orari.sorted().first { $0 > ora }
    }

    @ViewBuilder private var oggi: some View {
        Pannello(titolo: "PIPÌ", tinta: tinta) {
            RigaF(etichetta: "Ultima", valore: n.valore.pipi.last.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—", stato: .ok)
            if let u = n.valore.pipi.last {
                let pross = u.addingTimeInterval(ritmoOre * 3600)
                RigaF(etichetta: "Prossima", valore: "entro le \(pross.formatted(date: .omitted, time: .shortened))", stato: pross < Date() ? .no : .normale)
            }
            RigaF(etichetta: "Ritmo", valore: "ogni \(String(format: "%.0f", ritmoOre)) ore circa")
            TastoF(testo: "Segna pipì adesso", icona: "drop") { n.valore.pipi.append(Date()); giro.segnaPipi() }
        }
        Pannello(titolo: "GIOCO", tinta: tinta) {
            RigaF(etichetta: "Oggi", valore: "\(n.valore.giocoMinuti[Self.oggiChiave] ?? 0) min di gioco")
            NotaF(testo: "Tocca il tasto e FRIDAY lo chiama a voce con il suo comando.")
            TastoF(testo: "«Nando, qui gioco!»", icona: "pawprint", pieno: false) {
                Parlato.dici("Nando! Qui! Gioco!")
                n.valore.giocoMinuti[Self.oggiChiave, default: 0] += 5
            }
        }
        Pannello(titolo: "GIRI", tinta: tinta) {
            ForEach(n.valore.orari.sorted(), id: \.self) { o in
                let fatto = giroFatto(alle: o)
                RigaF(etichetta: o, valore: fatto ? "fatto" : (o == prossimoGiro ? "prossimo" : ""), stato: fatto ? .ok : .normale)
            }
            NotaF(testo: "FRIDAY ti avvisa 15 minuti prima, e se sta per piovere te lo dice.")
        }
        let giriOggi = n.valore.giri.filter { Calendar.current.isDateInToday($0.inizio) }
        Pannello(titolo: "TOTALE", tinta: tinta) {
            HStack {
                Valore(titolo: "CAMMINATI", valore: "\(giriOggi.map(\.minuti).reduce(0, +)) min", tinta: tinta)
                Valore(titolo: "DISTANZA", valore: String(format: "%.1f km", giriOggi.map(\.metri).reduce(0, +) / 1000), tinta: tinta)
                Valore(titolo: "PIPÌ", valore: "\(oggiPipi.count)", tinta: tinta)
            }
        }
    }

    @ViewBuilder private var percorsi: some View {
        Map {
            if !giro.punti.isEmpty { MapPolyline(coordinates: giro.punti).stroke(tinta, lineWidth: 4) }
            ForEach(Array(giro.pipi.enumerated()), id: \.offset) { _, p in Annotation("", coordinate: p) { Circle().fill(Color.petrolio).frame(width: 10, height: 10) } }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
        if giro.attivo {
            HStack {
                Valore(titolo: "TEMPO", valore: "\(giro.minuti) min", tinta: tinta)
                Valore(titolo: "DISTANZA", valore: String(format: "%.2f km", giro.metri / 1000), tinta: tinta)
            }
            TastoF(testo: "Fine giro", icona: "stop.fill", tinta: Color.rossoF) { if let g = giro.ferma() { n.valore.giri.append(g) } }
        } else {
            TastoF(testo: "Registra il giro", icona: "figure.walk") { giro.avvia() }
        }
        let gruppi = Dictionary(grouping: n.valore.giri, by: \.nome)
        if !gruppi.isEmpty {
            Pannello(titolo: "SALVATI", tinta: tinta) {
                ForEach(gruppi.keys.sorted(), id: \.self) { k in
                    let g = gruppi[k] ?? []
                    RigaF(etichetta: k, valore: String(format: "%.1f km · %d min · %d volte", (g.map(\.metri).reduce(0, +) / Double(g.count)) / 1000, g.map(\.minuti).reduce(0, +) / g.count, g.count))
                }
                NotaF(testo: "Ogni giro registrato resta qui con il tempo, i chilometri e i punti delle pipì.")
            }
        }
        if !radar.isEmpty {
            Pannello(titolo: "RADAR", tinta: tinta) { ForEach(radar, id: \.0) { RigaF(etichetta: $0.0, valore: $0.1, stato: $0.2) } }
        }
    }

    @ViewBuilder private var salute: some View {
        Pannello(titolo: "SCHEDA", tinta: tinta) {
            campo("Razza", \.razza); campo("Età", \.eta); campo("Peso", \.peso)
        }
        Pannello(titolo: "VETERINARIO", tinta: tinta) {
            campo("Studio", \.studio); campo("Medico", \.medico); campo("Telefono", \.telefono); campo("Microchip", \.microchip)
            campo("Allergie", \.allergie); campo("Farmaci", \.farmaci)
        }
        Pannello(titolo: "VISITE", tinta: tinta) {
            ForEach(n.valore.visite.reversed(), id: \.self) { NotaF(testo: $0) }
            HStack {
                TextField("", text: $nuovaVisita, prompt: Text("12 settembre · controllo, tutto ok").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                Button { guard !nuovaVisita.isEmpty else { return }; n.valore.visite.append(nuovaVisita); nuovaVisita = "" } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
            }
            NotaF(testo: "Prima di una visita chiedi a FRIDAY il riassunto: peso, vaccini, farmaci, ultime visite.")
        }
        Pannello(titolo: "PELO", tinta: tinta) {
            if !n.valore.pelo.isEmpty { NotaF(testo: n.valore.pelo) }
            TastoF(testo: "Inquadra Nando", icona: "camera", pieno: false) { foto = "pelo" }
        }
        Pannello(titolo: "SCADENZE", tinta: tinta) {
            ForEach(n.valore.scadenze.sorted { $0.value < $1.value }, id: \.key) { s in
                let d = Calendar.current.dateComponents([.day], from: Date(), to: s.value).day ?? 0
                RigaF(etichetta: s.key, valore: d < 0 ? "scaduto" : "tra \(d) giorni", stato: d <= 3 ? .no : .normale)
            }
            HStack {
                TextField("", text: $nuovaScadenza, prompt: Text("Antiparassitario").foregroundStyle(Color.tenue)).foregroundStyle(Color.testo)
                DatePicker("", selection: $dataScadenza, displayedComponents: .date).labelsHidden()
                Button { aggiungiScadenza() } label: { Image(systemName: "plus.circle.fill").font(.system(size: 22)) }.foregroundStyle(tinta)
            }
        }
        Pannello(titolo: "CIBI", tinta: tinta) {
            NotaF(testo: "Inquadra un cibo e FRIDAY ti dice se è pericoloso per lui.")
            if let esitoCibo { NotaF(testo: esitoCibo) }
            TastoF(testo: "Inquadra il cibo", icona: "camera", pieno: false) { foto = "cibo_cane" }
            RigaF(etichetta: "Uva, cioccolato, cipolla, xilitolo", valore: "tossici per i cani", stato: .no)
        }
    }

    @ViewBuilder private var archivio: some View {
        Pannello(titolo: "GALLERIA", tinta: tinta) {
            if galleria.isEmpty {
                NotaF(testo: "FRIDAY cerca Nando nelle tue foto recenti e le raccoglie qui. Il riconoscimento avviene sull'iPhone.")
                TastoF(testo: cercoFoto ? "Cerco…" : "Trova le foto di Nando", icona: "photo.stack", pieno: false) { Task { await cercaFoto() } }.disabled(cercoFoto)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(galleria.prefix(24), id: \.localIdentifier) { a in MiniaturaFoto(asset: a) }
                }
                RigaF(etichetta: "Foto", valore: "\(galleria.count)")
            }
        }
        Pannello(titolo: "AMICI", tinta: tinta) {
            if n.valore.amici.isEmpty { NotaF(testo: "I cani che incontra più spesso: dì a FRIDAY «Nando ha giocato con Olivia» e li tengo qui.") }
            ForEach(n.valore.amici, id: \.self) { NotaF(testo: $0) }
        }
        Pannello(titolo: "SMARRITO", tinta: tinta) {
            NotaF(testo: "Un tocco e FRIDAY prepara il volantino «cane smarrito» con la foto più recente, la descrizione, il tuo numero e l'ultima posizione del giro, pronto da condividere.")
            if let volantino { ShareLink(item: volantino, preview: SharePreview("Nando smarrito", image: volantino)) { Label("Condividi il volantino", systemImage: "square.and.arrow.up").foregroundStyle(tinta) } }
            TastoF(testo: "Prepara il volantino", icona: "exclamationmark.bubble", tinta: Color.rossoF) { Task { await preparaVolantino() } }
        }
    }

    private func campo(_ nome: String, _ k: WritableKeyPath<DatiNando, String>) -> some View {
        HStack {
            Text(nome).font(.system(size: 14)).foregroundStyle(Color.testo)
            TextField("", text: Binding(get: { n.valore[keyPath: k] }, set: { n.valore[keyPath: k] = $0 }), prompt: Text("—").foregroundStyle(Color.tenue))
                .multilineTextAlignment(.trailing).foregroundStyle(Color.tenue)
        }
    }

    private static var oggiChiave: String { Date().formatted(.iso8601.year().month().day()) }

    private func aggiungiScadenza() {
        let s = nuovaScadenza.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        n.valore.scadenze[s] = dataScadenza; nuovaScadenza = ""
        let c = UNMutableNotificationContent(); c.title = "Nando"; c.body = "\(s): è il momento."; c.sound = .default
        var dc = Calendar.current.dateComponents([.year, .month, .day], from: dataScadenza); dc.hour = 9
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "nando.\(s)", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)))
    }

    /// Gli avvisi dei giri, ogni giorno 15 minuti prima.
    private func programmaGiri() {
        let centro = UNUserNotificationCenter.current()
        centro.removePendingNotificationRequests(withIdentifiers: (0..<8).map { "nando.giro.\($0)" })
        for (k, o) in n.valore.orari.enumerated() {
            let p = o.split(separator: ":").compactMap { Int($0) }
            guard p.count == 2 else { continue }
            let tot = p[0] * 60 + p[1] - 15
            var dc = DateComponents(); dc.hour = (tot / 60 + 24) % 24; dc.minute = (tot % 60 + 60) % 60
            let c = UNMutableNotificationContent(); c.title = "Nando"; c.body = "Tra 15 minuti il giro delle \(o)."; c.sound = .default
            centro.add(UNNotificationRequest(identifier: "nando.giro.\(k)", content: c, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)))
        }
    }

    private func guarda(_ img: UIImage, compito: String) async {
        guard let b64 = img.jpegFriday(lato: 1024), let o = await VistaVitals.chiama(["vista": ["compito": compito, "immagine": b64]], attesa: 60) else { return }
        if compito == "pelo" {
            let cm = (o["cm"] as? NSNumber)?.doubleValue ?? 0, g = (o["giorni"] as? NSNumber)?.intValue ?? 0
            n.valore.pelo = String(format: "Lunghezza stimata %.1f cm · toelettatura consigliata tra %d giorni (stima dagli Occhi).", cm, g)
        } else {
            let cibo = o["cibo"] as? String ?? "questo cibo", male = o["pericoloso"] as? Bool ?? true
            esitoCibo = "\(cibo.prefix(1).uppercased() + cibo.dropFirst()): \(male ? "NO" : "va bene") — \(o["perche"] as? String ?? "")"
            Parlato.dici(male ? "Attenzione: \(cibo) non va bene per Nando." : "\(cibo): va bene per Nando.")
        }
    }

    private func caricaRadar() async {
        guard let pos = await Posizione.attuale(), let la = pos["lat"] as? Double, let lo = pos["lon"] as? Double else { return }
        let qui = CLLocation(latitude: la, longitude: lo)
        var r: [(String, String, RigaF.Stato)] = []
        if let meteo = try? await WeatherService.shared.weather(for: qui, including: .current, .hourly) {
            let (adesso, ore) = meteo
            let t = adesso.temperature.converted(to: .celsius).value
            let asfalto = t + (adesso.isDaylight && adesso.cloudCover < 0.4 ? t * 0.9 : 0)
            r.append(("Asfalto", String(format: "%.0f° · %@", asfalto, asfalto >= 50 ? "troppo caldo per le zampe" : "ok per le zampe"), asfalto >= 50 ? .no : .ok))
            if let p = ore.forecast.prefix(4).first(where: { $0.precipitationChance >= 0.5 }) {
                r.append(("Pioggia", "dalle \(p.date.formatted(date: .omitted, time: .shortened))", .no))
            } else { r.append(("Pioggia", "nessuna nelle prossime ore", .ok)) }
        }
        let q = MKLocalSearch.Request(); q.naturalLanguageQuery = "area cani"; q.region = MKCoordinateRegion(center: qui.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000)
        if let v = try? await MKLocalSearch(request: q).start(), let primo = v.mapItems.min(by: { ($0.placemark.location?.distance(from: qui) ?? 1e9) < ($1.placemark.location?.distance(from: qui) ?? 1e9) }) {
            r.append(("Area cani più vicina", "\(primo.name ?? "area cani") · \(Int(primo.placemark.location?.distance(from: qui) ?? 0)) m", .normale))
        }
        radar = r
    }

    private func cercaFoto() async {
        cercoFoto = true; defer { cercoFoto = false }
        guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized || PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited else { return }
        let o = PHFetchOptions(); o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]; o.fetchLimit = 400
        let r = PHAsset.fetchAssets(with: .image, options: o)
        var tutte: [PHAsset] = []; r.enumerateObjects { a, _, _ in tutte.append(a) }
        galleria = await Task.detached { Self.conCani(tutte) }.value
    }

    nonisolated private static func conCani(_ foto: [PHAsset]) -> [PHAsset] {
        let m = PHImageManager.default(), op = PHImageRequestOptions()
        op.isSynchronous = true; op.deliveryMode = .fastFormat; op.resizeMode = .fast
        return foto.filter { a in
            var img: CGImage?
            m.requestImage(for: a, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFit, options: op) { i, _ in img = i?.cgImage }
            guard let img else { return false }
            let r = VNRecognizeAnimalsRequest()
            try? VNImageRequestHandler(cgImage: img).perform([r])
            return (r.results ?? []).contains { $0.labels.contains { $0.identifier == VNAnimalIdentifier.dog.rawValue && $0.confidence > 0.6 } }
        }
    }

    nonisolated private final class Bandierina: @unchecked Sendable { var su = false }

    private func preparaVolantino() async {
        var foto: UIImage?
        if let a = galleria.first {
            let op = PHImageRequestOptions(); op.deliveryMode = .highQualityFormat; op.isNetworkAccessAllowed = true
            foto = await withCheckedContinuation { c in
                let giaFatto = Bandierina()
                PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 1000, height: 1000), contentMode: .aspectFill, options: op) { i, info in
                    guard !giaFatto.su, (info?[PHImageResultIsDegradedKey] as? Bool) != true else { return }
                    giaFatto.su = true; c.resume(returning: i)
                }
            }
        }
        let dove = n.valore.giri.last?.punti.last.map { String(format: "Ultima posizione: %.5f, %.5f", $0[0], $0[1]) } ?? ""
        let testo = "CANE SMARRITO\n\nNando · \(n.valore.razza)\(n.valore.eta.isEmpty ? "" : " · \(n.valore.eta)")\(n.valore.microchip.isEmpty ? "" : "\nMicrochip \(n.valore.microchip)")\n\(dove)\n\nSe lo vedi chiama: \(Profilo.numero)"
        let vista = VStack(spacing: 16) {
            if let foto { Image(uiImage: foto).resizable().scaledToFill().frame(width: 900, height: 900).clipped() }
            Text(testo).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center).foregroundStyle(.black).padding(30)
        }.frame(width: 1000).background(.white)
        let r = ImageRenderer(content: vista)
        if let ui = r.uiImage { volantino = Image(uiImage: ui) }
    }
}

struct MiniaturaFoto: View {
    let asset: PHAsset
    @State private var img: UIImage?
    var body: some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay { if let img { Image(uiImage: img).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task {
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: nil) { i, _ in
                    let foto = i
                    Task { @MainActor in img = foto }
                }
            }
    }
}

/// Il giro registrato: posizione, tempo, distanza, pipì. Continua anche con lo schermo spento (posizione in sottofondo).
@MainActor final class GiroInCorso: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let condiviso = GiroInCorso()
    @Published var attivo = false
    @Published var punti: [CLLocationCoordinate2D] = []
    @Published var pipi: [CLLocationCoordinate2D] = []
    @Published var metri = 0.0
    @Published var minuti = 0
    private let gestore = CLLocationManager()
    private var inizio = Date()
    private var ultimo: CLLocation?

    func avvia() {
        gestore.delegate = self
        gestore.desiredAccuracy = kCLLocationAccuracyBest
        gestore.distanceFilter = 5
        gestore.activityType = .fitness
        if gestore.authorizationStatus == .notDetermined { gestore.requestWhenInUseAuthorization() }
        gestore.allowsBackgroundLocationUpdates = true
        gestore.showsBackgroundLocationIndicator = true
        punti = []; pipi = []; metri = 0; minuti = 0; ultimo = nil; inizio = Date(); attivo = true
        gestore.startUpdatingLocation()
    }

    func segnaPipi() { if attivo, let u = ultimo { pipi.append(u.coordinate) } }

    func ferma() -> GiroNando? {
        guard attivo else { return nil }
        gestore.stopUpdatingLocation(); gestore.allowsBackgroundLocationUpdates = false; attivo = false
        let ora = Calendar.current.component(.hour, from: inizio)
        let nome = ora < 11 ? "Giro del mattino" : ora < 16 ? "Giro di mezzogiorno" : ora < 21 ? "Giro della sera" : "Giro della notte"
        return GiroNando(nome: nome, inizio: inizio, minuti: Int(Date().timeIntervalSince(inizio) / 60), metri: metri,
                         punti: punti.map { [$0.latitude, $0.longitude] }, pipi: pipi.map { [$0.latitude, $0.longitude] })
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let buone = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 30 }
        Task { @MainActor in
            for l in buone {
                if let u = self.ultimo { self.metri += l.distance(from: u) }
                self.ultimo = l; self.punti.append(l.coordinate)
            }
            self.minuti = Int(Date().timeIntervalSince(self.inizio) / 60)
        }
    }
}
#endif
