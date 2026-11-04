#if os(iOS)
import SwiftUI
import MapKit
import CoreLocation
import WeatherKit
import Combine
import UIKit

/// Build 23 · INTELLIGENCE › SATELLITE, come il mockup approvato: la città 3D di Apple (satellite con il rilievo) con i suoi
/// luoghi sulle aste olografiche, la camera che gira piano intorno al luogo scelto e ci vola sopra quando se ne sceglie
/// un altro; sotto TUTTI · LUOGHI · LOCALI · PERSONE, l'elenco con le distanze, Luogo · Distanza · A piedi · Meteo e
/// GUIDA · NAVIGA · DOSSIER; poi RICOGNIZIONE (un indirizzo: ci vola sopra) e A VOCE. Si chiude con «Chiudi».

/// Le richieste a voce per SATELLITE («guidami allo studio»…): Jarvis le lascia qui e apre la sezione, che le esegue
/// appena ha i luoghi.
@MainActor
final class RichiestaSatellite: ObservableObject {
    static let condivisa = RichiestaSatellite()
    @Published var azione: AzioneSatellite? { didSet { quando = Date() } }
    /// Quando è stata detta: una richiesta vecchia (la sezione non si è aperta) non parte più alla prossima apertura.
    private(set) var quando = Date.distantPast
}

/// Le schede dei luoghi, come i tasti del mockup.
enum CategoriaSat: String, CaseIterable, Identifiable {
    case tutti = "TUTTI", luoghi = "LUOGHI", locali = "LOCALI", persone = "PERSONE"
    var id: String { rawValue }
}

/// Il meteo del luogo scelto (Apple Meteo, WeatherKit): i gradi, il cielo e la pioggia delle prossime 2 ore.
struct MeteoSat: Equatable {
    let gradi: Int
    let cielo: String
    let pioggia: String           // «niente pioggia per 2 ore», «pioggia verso le 18:00»
    /// Il cielo in italiano, come nel mockup («NUVOLOSO»): `description` di WeatherKit è in inglese («Cloudy»).
    static func italiano(_ c: WeatherCondition) -> String {
        switch c {
        case .clear: return "sereno"
        case .mostlyClear: return "poco nuvoloso"
        case .partlyCloudy: return "parzialmente nuvoloso"
        case .mostlyCloudy, .cloudy: return "nuvoloso"
        case .foggy: return "nebbia"
        case .haze: return "foschia"
        case .drizzle: return "pioviggine"
        case .rain: return "pioggia"
        case .heavyRain: return "pioggia forte"
        case .thunderstorms: return "temporale"
        case .snow: return "neve"
        case .heavySnow: return "neve forte"
        case .sleet: return "nevischio"
        case .hail: return "grandine"
        case .windy, .breezy: return "vento"
        default: return "variabile"
        }
    }
    /// In basso a destra sulla mappa: «14° · NUVOLOSO».
    var hud: String { "\(gradi)° · \(cielo.uppercased())" }
    /// La riga Meteo: «14° · niente pioggia per 2 ore».
    var riga: String { "\(gradi)° · \(pioggia)" }
    /// Nell'avviso della ricognizione: «Niente pioggia per 2 ore.»
    var frase: String { pioggia.prefix(1).uppercased() + pioggia.dropFirst() + "." }

    static func di(_ c: CLLocationCoordinate2D) async -> MeteoSat? {
        let dove = CLLocation(latitude: c.latitude, longitude: c.longitude)
        guard let w = try? await WeatherService.shared.weather(for: dove, including: .current, .hourly) else { return nil }
        let (adesso, ore) = w
        let ora = Date()
        let prossime = ore.forecast.filter { $0.date > ora.addingTimeInterval(-1800) && $0.date <= ora.addingTimeInterval(7200) }
        var pioggia = "niente pioggia per 2 ore"
        if let h = prossime.first(where: { $0.precipitationChance >= 0.3 }) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "it_IT")
            f.dateFormat = "HH:mm"
            pioggia = h.date <= ora ? "pioggia adesso" : "pioggia verso le \(f.string(from: h.date))"
        }
        return MeteoSat(gradi: Int(adesso.temperature.converted(to: .celsius).value.rounded()), cielo: MeteoSat.italiano(adesso.condition), pioggia: pioggia)
    }
}

/// Decisione 19 (obbligo di WeatherKit): dove si mostrano i dati di Apple Meteo, il marchio « Meteo» e il link alle fonti dei
/// dati, presi da `WeatherService.shared.attribution` (il marchio per il fondo scuro: le schede di JARVIS sono sempre scure).
/// Piccolo, a destra, come l'attribuzione già nella scheda Meteo.
struct AttribuzioneMeteo: View {
    @State private var marchio: URL?
    @State private var legale: URL?

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            AsyncImage(url: marchio) { img in img.resizable().scaledToFit() } placeholder: {
                Text("\u{F8FF} Meteo").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.tenue)
            }
            .frame(height: 12)
            .accessibilityLabel("Apple Meteo")
            if let legale { Link("Fonti dei dati", destination: legale).font(.system(size: 10)).tint(Color.tenue) }
        }
        .task {
            guard marchio == nil, let a = try? await WeatherService.shared.attribution else { return }
            marchio = a.combinedMarkDarkURL
            legale = a.legalPageURL
        }
    }
}

/// LUOGHI · LOCALI · PERSONE. Le PERSONE sono i posti dove ha incontrato qualcuno; i LOCALI quelli dove Apple Mappe
/// conosce, a meno di 30 m, un bar, un ristorante, un locale notturno, una birreria, un'enoteca o una pasticceria;
/// gli altri sono LUOGHI. La risposta di Apple si ricorda sul telefono: si chiede una volta sola per luogo.
@MainActor
enum CategorieSat {
    private static let chiave = "satelliteCategorie"

    static func lette() -> [String: String] { UserDefaults.standard.dictionary(forKey: chiave) as? [String: String] ?? [:] }

    static func categoria(_ l: LuogoSat, _ note: [String: String]) -> CategoriaSat {
        if l.tipo == "persona" || l.persona != nil { return .persone }
        return note[l.chiave] == "locale" ? .locali : .luoghi
    }

    /// Chiede ad Apple Mappe i luoghi non ancora visti (al massimo 12 alla volta, uno dopo l'altro: MapKit limita le ricerche).
    static func completa(_ luoghi: [LuogoSat]) async -> [String: String] {
        var note = lette()
        let mancanti = luoghi.filter { $0.ricordo != nil && $0.tipo != "persona" && $0.persona == nil && note[$0.chiave] == nil }.prefix(12)
        for l in mancanti {
            guard !Task.isCancelled, let esito = await chiedi(l) else { continue }
            note[l.chiave] = esito
        }
        UserDefaults.standard.set(note, forKey: chiave)
        return note
    }

    private static func chiedi(_ l: LuogoSat) async -> String? {
        let r = MKLocalPointsOfInterestRequest(center: l.coordinata, radius: 30)
        r.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .nightlife, .brewery, .winery, .bakery])
        return await cerca(MKLocalSearch(request: r))
    }

    private static func cerca(_ s: MKLocalSearch) async -> String? {
        let q = ScatolaSat(s)
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            q.valore.start { @Sendable risposta, errore in
                _ = q
                if let risposta { c.resume(returning: risposta.mapItems.isEmpty ? "luogo" : "locale"); return }
                // nessun risultato è una risposta («luogo»); un errore di rete no: si richiede la prossima volta
                if let e = errore as? MKError, e.code == .placemarkNotFound { c.resume(returning: "luogo") } else { c.resume(returning: nil) }
            }
        }
    }
}

// MARK: - La sezione

struct VistaSatellite: View {
    /// La voce di JARVIS («Guida verso Studio, Sir: segua le frecce.»).
    let parla: (String) -> Void
    @StateObject private var bussola = Bussola()
    private let richiesta = RichiestaSatellite.condivisa      // letta all'apertura (a voce la sezione si riapre sempre)
    @State private var luoghi: [LuogoSat] = []
    @State private var posti: [DatiRicordi.Riga] = []        // tutti i ricordi con una posizione: visite e note del dossier
    @State private var ricognizione: LuogoSat?
    @State private var note: [String: String] = CategorieSat.lette()
    @State private var filtro: CategoriaSat = .tutti
    @State private var sceltoChiave: String?
    @State private var caricato = false
    @State private var errore = false
    @State private var meteo: MeteoSat?
    @State private var meteoDi: String?
    @State private var indirizzo = ""
    @State private var cerca = false
    @State private var avviso: String?
    @State private var pagina: PaginaSat?
    @State private var scorri = 0                           // RICOGNIZIONE: la pagina torna sulla mappa
    private let tinta = Color.ciano

    /// Tutti i luoghi: quelli salvati e, se c'è, la ricognizione (in fondo, come nel mockup).
    private var tutti: [LuogoSat] { luoghi + (ricognizione.map { [$0] } ?? []) }
    private var scelto: LuogoSat? { tutti.first { $0.chiave == sceltoChiave } ?? tutti.first }
    private func categoria(_ l: LuogoSat) -> CategoriaSat { l.tipo == "ricognizione" ? .luoghi : CategorieSat.categoria(l, note) }
    private var visibili: [LuogoSat] { tutti.filter { filtro == .tutti || categoria($0) == filtro } }

    var body: some View {
        CorniceScheda(titolo: "Satellite", sottotitolo: "pronta", icona: "satellite", tinta: tinta, pronto: caricato,
                      barraDalloScorrimento: true) {
            ScrollViewReader { lettore in
                VStack(alignment: .leading, spacing: 16) {
                    pannelloSatellite.id("mappa")
                    pannelloRicognizione
                    PannelloAVoce(frasi: ["«Jarvis, satellite»", "«Jarvis, ricognizione su Via Tortona»",
                                          "«Jarvis, mostrami lo studio in 3D»", "«Jarvis, salva questo posto con la foto»"])
                }
                .onChange(of: scorri) { withAnimation(.easeInOut(duration: 0.4)) { lettore.scrollTo("mappa", anchor: .top) } }
            }
        }
        .fullScreenCover(item: $pagina) { p in
            switch p {
            case .naviga(let l): SchermoNaviga(luogo: l, apri: apri)
            case .guida(let l): SchermoGuida(luogo: l, apri: apri)
            case .travel(let l, let k):
                // MARK X · TRAVEL: «come arrivare», sopra SATELLITE come il Dossier
                SchermoTravel(luogo: l, iniziale: k,
                              lei: bussola.lat.flatMap { la in bussola.lon.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } },
                              chiudi: { apri(nil) }, guida: { apri(.guida(l)) })
            case .dossier(let l):
                SchermoDossier(luogo: l, categoria: categoria(l), vicini: vicini(l), distanza: distanza(l), apri: apri) { nuova in
                    await ricarica(scegli: nuova)                       // la ricognizione salvata: ora è uno dei suoi luoghi
                }
            }
        }
        .chiudiFoglioDietro { if pagina != nil { apri(nil) } }  // 4 nov: Naviga, Guida, Travel o il Dossier non restano sopra a tutto
        .task { await carica() }
        .task(id: scelto?.chiave) { await caricaMeteo() }
        .onAppear { bussola.accendi() }
        .onDisappear { bussola.spegni() }
    }

    // MARK: SATELLITE

    private var pannelloSatellite: some View {
        Pannello(titolo: "SATELLITE", tinta: tinta) {
            MappaSatellite(luoghi: tutti, visibili: Set(visibili.map(\.chiave)), scelto: scelto,
                           lei: bussola.lat.flatMap { la in bussola.lon.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } },
                           etichetta: { l in etichetta(l) }, meteo: meteo?.hud, ferma: pagina != nil)
                .aspectRatio(720.0 / 620.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(tinta.opacity(0.22), lineWidth: 1))
            HStack(spacing: 6) {
                ForEach(CategoriaSat.allCases) { c in
                    ChipSat(testo: c.rawValue, acceso: filtro == c) { Suoni.tocco(); filtro = c }
                }
            }
            if let avviso { AvvisoJarvis(testo: avviso) }
            VStack(spacing: 8) {
                if errore {
                    Text("Non raggiungo la memoria, Sir.").font(.system(size: 14)).foregroundStyle(.orange)
                } else if tutti.isEmpty {
                    Text("Nessun luogo salvato, Sir: dica «Jarvis, ricorda questo luogo» dove si trova.")
                        .font(.system(size: 13)).foregroundStyle(Color.tenue).frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if visibili.isEmpty {
                    Text("Niente in questa categoria.").font(.system(size: 13)).foregroundStyle(Color.tenue)
                        .frame(maxWidth: .infinity).padding(.vertical, 34)
                }
                ForEach(visibili) { l in
                    Button { Suoni.tocco(); sceltoChiave = l.chiave } label: { rigaLuogo(l, attivo: l.chiave == scelto?.chiave) }
                        .buttonStyle(StileStark())
                }
            }
            RigaHUD("Luogo", scelto.map { $0.nome == $0.via ? $0.nome : "\($0.nome) · \($0.via)" } ?? "—")
            RigaHUD("Distanza", scelto.flatMap { metri($0) }.map { Rotta.distanza($0) } ?? "—")
            RigaHUD("A piedi", scelto.flatMap { metri($0) }.map { Rotta.aPiedi($0) } ?? "—")
            RigaHUD("Meteo", meteo?.riga ?? "—")
            // decisione 19: il meteo (qui e sulla mappa) è di Apple Meteo, che chiede il suo marchio e il link alle fonti
            if meteo != nil { AttribuzioneMeteo() }
            HStack(spacing: 8) {
                TastoComando(testo: "Guida", attivo: scelto != nil) { Suoni.tocco(); if let l = scelto { apri(.guida(l)) } }
                TastoComando(testo: "Naviga", attivo: scelto != nil) { Suoni.tocco(); if let l = scelto { apri(.naviga(l)) } }
                TastoComando(testo: "Travel", attivo: scelto != nil) { Suoni.tocco(); if let l = scelto { apri(.travel(l, .mezzi)) } }   // MARK X
                TastoComando(testo: "Dossier", attivo: scelto != nil) { Suoni.tocco(); if let l = scelto { apri(.dossier(l)) } }
            }
        }
    }

    /// Una riga dei luoghi, come nel mockup: nome, via · categoria, la distanza a destra; quello scelto è acceso.
    private func rigaLuogo(_ l: LuogoSat, attivo: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.nome).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("\(l.via) · \(categoria(l).rawValue.lowercased())").font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.56, green: 0.70, blue: 0.74)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(metri(l).map { Rotta.distanza($0) } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .monospaced)).monospacedDigit().foregroundStyle(tinta)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tinta.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(attivo ? tinta : Color(red: 0.07, green: 0.20, blue: 0.23), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(attivo ? 0.35 : 0), lineWidth: 1).padding(1))
        .contentShape(Rectangle())
    }

    // MARK: RICOGNIZIONE

    private var pannelloRicognizione: some View {
        Pannello(titolo: "RICOGNIZIONE", tinta: tinta) {
            HStack(spacing: 8) {
                TextField("Indirizzo", text: $indirizzo)
                    .font(.system(size: 14)).foregroundStyle(ColoriHUD.chiaro)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { Task { await vai() } }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(tinta.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(tinta.opacity(0.3), lineWidth: 1))
                TastoComando(testo: cerca ? "…" : "Vai", corto: true, attivo: !cerca) { Suoni.tocco(); Task { await vai() } }
            }
            Text("JARVIS ci vola sopra in 3D, poi la vista da strada, la distanza e se lì sta per piovere.")
                .font(.system(size: 11)).foregroundStyle(Color.tenue)
        }
    }

    /// «Vai»: l'indirizzo diventa il luogo RICOGNIZIONE, la mappa ci vola sopra e arriva l'avviso con distanza e meteo.
    private func vai() async {
        let via = indirizzo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !via.isEmpty, !cerca else { return }
        cerca = true
        defer { cerca = false }
        guard let c = await geocodifica(via) else {
            Suoni.errore(); avviso = "Non trovo «\(via)», Sir."; return
        }
        avviso = nil
        let l = LuogoSat(chiave: String(format: "c%.5f,%.5f", c.latitude, c.longitude), ricordo: nil, tipo: "ricognizione", nome: "Ricognizione",
                         via: via, persona: nil, lat: c.latitude, lon: c.longitude, quando: "adesso")
        ricognizione = l
        filtro = .tutti
        sceltoChiave = l.chiave
        scorri += 1
        // come il mockup: l'avviso arriva dopo il volo, con la distanza, il tempo a piedi e se lì sta per piovere
        let m = await MeteoSat.di(c)
        try? await Task.sleep(for: .seconds(1.8))
        var testo = "Ricognizione su \(via)"
        if let d = metri(l) { testo += ": \(Rotta.distanza(d)), \(Rotta.aPiedi(d).replacingOccurrences(of: "circa ", with: "")) a piedi." } else { testo += "." }
        if let m { testo += " \(m.frase)" }
        await PannelliTraccia.notifica(testo)
    }

    /// L'indirizzo detto o scritto, cercato vicino a dove si trova (entro 50 km), in italiano.
    private func geocodifica(_ testo: String) async -> CLLocationCoordinate2D? {
        var zona: CLCircularRegion?
        if let la = bussola.lat, let lo = bussola.lon {
            zona = CLCircularRegion(center: CLLocationCoordinate2D(latitude: la, longitude: lo), radius: 50_000, identifier: "vicino")
        }
        let trovati = try? await CLGeocoder().geocodeAddressString(testo, in: zona, preferredLocale: Locale(identifier: "it_IT"))
        return trovati?.first?.location?.coordinate
    }

    // MARK: Dati

    private func carica() async {
        guard let o = await VistaVitals.chiama(["ricordi": true]) else { errore = true; caricato = true; return }
        luoghi = LuogoSat.daRicordi(o)
        posti = DatiRicordi(o).posti
        caricato = true
        if richiesta.azione != nil { await eseguiVoce() }
        note = await CategorieSat.completa(luoghi)               // LOCALI: chiesto ad Apple Mappe, poi ricordato
    }

    /// Dopo «Ricorda» nel dossier: i luoghi di nuovo dal cervello, la ricognizione diventa il luogo salvato.
    private func ricarica(scegli chiave: String) async {
        guard let o = await VistaVitals.chiama(["ricordi": true]) else { return }
        luoghi = LuogoSat.daRicordi(o)
        posti = DatiRicordi(o).posti
        guard let l = luoghi.first(where: { $0.chiave == chiave }) else { return }
        ricognizione = nil
        sceltoChiave = l.chiave
        apri(.dossier(l))
    }

    private func caricaMeteo() async {
        guard let l = scelto else { meteo = nil; return }
        if meteoDi != l.chiave { meteo = nil }
        let m = await MeteoSat.di(l.coordinata)
        guard !Task.isCancelled else { return }
        meteo = m
        meteoDi = l.chiave
    }

    /// Metri in linea d'aria da dove si trova.
    private func metri(_ l: LuogoSat) -> Double? { bussola.verso(lat: l.lat, lon: l.lon)?.metri }

    private func distanza(_ l: LuogoSat) -> String {
        guard let m = metri(l) else { return "—" }
        return "\(Rotta.distanza(m)) · \(Rotta.aPiedi(m))"
    }

    /// Il cartellino sull'asta: «STUDIO · 198 m».
    private func etichetta(_ l: LuogoSat) -> String {
        let n = l.nome.uppercased()
        return metri(l).map { "\(n) · \(Rotta.distanza($0))" } ?? n
    }

    /// I ricordi salvati lì (entro 60 m), dal più recente: le visite e le note del dossier.
    private func vicini(_ l: LuogoSat) -> [DatiRicordi.Riga] {
        posti.filter { r in
            guard let la = r.lat, let lo = r.lon else { return false }
            return Rotta.metri(lat: la, lon: lo, versoLat: l.lat, versoLon: l.lon) <= 60
        }
    }

    /// Apre NAVIGA, GUIDA o il DOSSIER (anche dall'uno all'altro). NAVIGA e GUIDA compaiono in dissolvenza (senza
    /// la salita del foglio), il DOSSIER sale dal basso. GUIDA fa partire la guida.
    private func apri(_ p: PaginaSat?) {
        if case .guida(let l)? = p { MotoreGuida.condiviso.avvia(l) }
        var t = Transaction()
        t.disablesAnimations = {
            if case .dossier? = p { return false }; if case .dossier? = pagina { return false }
            if case .travel? = p { return false }; if case .travel? = pagina { return false }     // TRAVEL sale dal basso, come il Dossier
            return true
        }()
        withTransaction(t) { pagina = p }
    }

    // MARK: A voce

    /// «guidami allo studio», «mostrami la strada per il locale», «ricognizione su …», «mostrami lo studio in 3D».
    /// Come il mockup: prima la sezione, poi il volo sul luogo, poi JARVIS lo dice e si apre la schermata.
    private func eseguiVoce() async {
        guard let a = richiesta.azione else { return }
        let fresca = Date().timeIntervalSince(richiesta.quando) < 15
        richiesta.azione = nil
        guard fresca else { return }
        try? await Task.sleep(for: .seconds(1.3))
        if case .travel(var nome, let k) = a {               // MARK X · TRAVEL a voce: il luogo detto, se no quello scelto
            if k == "voli" {                                 // per VOLI il «luogo» è il numero del volo detto: si ricorda
                if !nome.isEmpty { VoloSalvato.numero = nome }
                nome = ""
            }
            guard let l = nome.isEmpty ? scelto : (LuogoSat.trova(nome, in: tutti) ?? scelto) else {
                Suoni.errore(); parla("Prima mi serve un luogo salvato, Sir: dica «Jarvis, ricorda questo luogo» dove si trova."); return
            }
            if !nome.isEmpty, LuogoSat.trova(nome, in: tutti) == nil, let c = await geocodifica(nome) {
                let r = LuogoSat(chiave: String(format: "c%.5f,%.5f", c.latitude, c.longitude), ricordo: nil, tipo: "ricognizione", nome: nome,
                                 via: nome, persona: nil, lat: c.latitude, lon: c.longitude, quando: "adesso")
                ricognizione = r
                sceltoChiave = r.chiave
                apri(.travel(r, SchedaTravel(rawValue: k) ?? .mezzi))
                return
            }
            sceltoChiave = l.chiave
            parla(k == "voli" ? "Il suo volo, Sir." : k == "treni" ? "Le partenze, Sir." : k == "bici" ? "Le bici qui vicino, Sir."
                  : k == "taxi" ? "Il radiotaxi, Sir." : k == "piedi" ? "A piedi verso \(l.nome), Sir." : "Ecco come arrivare, Sir.")
            apri(.travel(l, SchedaTravel(rawValue: k) ?? .mezzi))
            return
        }
        if case .ricognizione(let via) = a {
            indirizzo = via
            await vai()
            return
        }
        var trovato = LuogoSat.trova(a.nome, in: tutti)
        if trovato == nil, let c = await geocodifica(a.nome) {              // non è tra i suoi luoghi: l'indirizzo detto
            let r = LuogoSat(chiave: String(format: "c%.5f,%.5f", c.latitude, c.longitude), ricordo: nil, tipo: "ricognizione", nome: a.nome,
                             via: a.nome, persona: nil, lat: c.latitude, lon: c.longitude, quando: "adesso")
            ricognizione = r
            trovato = r
        }
        guard let l = trovato else { Suoni.errore(); parla("Non trovo «\(a.nome)», Sir."); return }
        filtro = .tutti
        sceltoChiave = l.chiave
        scorri += 1
        switch a {
        case .guida:
            try? await Task.sleep(for: .seconds(0.5))
            parla("Guida verso \(l.nome), Sir: segua le frecce.")
            apri(.guida(l))
        case .naviga:
            try? await Task.sleep(for: .seconds(0.5))
            parla("La strada per \(l.nome), Sir.")
            apri(.naviga(l))
        case .mostra, .ricognizione, .travel:
            break
        }
    }
}

/// Le schermate a tutto schermo di SATELLITE.
enum PaginaSat: Identifiable {
    case naviga(LuogoSat), guida(LuogoSat), dossier(LuogoSat)
    case travel(LuogoSat, SchedaTravel)                   // MARK X
    var id: String {
        switch self {
        case .travel(let l, _): return "travel-\(l.chiave)"
        case .naviga(let l): return "naviga-\(l.chiave)"
        case .guida(let l): return "guida-\(l.chiave)"
        case .dossier(let l): return "dossier-\(l.chiave)"
        }
    }
}

/// I tasti delle schede (TUTTI · LUOGHI · LOCALI · PERSONE), come i «chip» del mockup.
struct ChipSat: View {
    let testo: String
    let acceso: Bool
    let azione: () -> Void
    var body: some View {
        Button(action: azione) {
            Text(testo)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(acceso ? Color(red: 0, green: 0.094, blue: 0.125) : Color.ciano)
                .padding(.vertical, 8).padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(acceso ? Color.ciano : .clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(acceso ? 1 : 0.3), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(StileStark())
        .accessibilityAddTraits(acceso ? .isSelected : [])
    }
}

// MARK: - La mappa 3D

/// La città 3D di Apple (satellite con il rilievo): i luoghi sulle aste olografiche (quello scelto in arancio), lei in
/// verde; la camera gira piano intorno al luogo scelto (ferma per 2,6 s dopo un tocco), ci vola sopra quando se ne sceglie
/// un altro (1,7 s, alzandosi a metà), il dito in orizzontale la fa girare (in verticale la pagina scorre).
/// Sopra, l'HUD: SATELLITE · 3D, la bussola, le coordinate con la quota, il meteo e il mirino.
struct MappaSatellite: View {
    let luoghi: [LuogoSat]
    let visibili: Set<String>
    let scelto: LuogoSat?
    let lei: CLLocationCoordinate2D?
    let etichetta: (LuogoSat) -> String
    let meteo: String?
    /// Coperta da NAVIGA, GUIDA o DOSSIER: la camera sta ferma (niente lavoro inutile).
    var ferma = false
    /// 4 nov: anche con SATELLITE dietro (MARK XI, un'altra sezione davanti) la camera sta ferma; davanti riparte.
    @Environment(\.sezioneDietro) private var dietro

    @State private var posizione: MapCameraPosition = .automatic
    @State private var camera: MapCamera?
    @State private var centro: CLLocationCoordinate2D?
    @State private var giro = 34.0                    // la direzione della camera, gradi dal nord
    @State private var volo: (da: CLLocationCoordinate2D, a: CLLocationCoordinate2D, inizio: Date)?
    @State private var ultimoTocco = Date.distantPast
    @State private var dito: CGFloat?
    @State private var prima = Date()
    @State private var lato: CGSize = .zero                 // la misura della mappa (i cartellini restano dentro, decisione 42)

    /// Come il mockup: a 560 m dal luogo, inclinata di 37° (la camera sta a 53° sopra l'orizzonte).
    private let distanza = 560.0
    private let inclinazione = 37.3
    fileprivate static let spazio = "mappaSatellite"

    /// Decisione 42: di quanto spostare il cartellino in cima a un'asta perché resti tutto dentro la mappa (a 4 punti dal bordo).
    /// Il cartellino resta nell'asta (MapKit lo tiene attaccato al luogo, anche sul rilievo): qui si calcola solo lo
    /// spostamento, dal punto del luogo sullo schermo (la camera vera della mappa) e dalla misura del cartellino. Lontano dai
    /// bordi lo spostamento è zero: il cartellino sta esattamente dov'era.
    private func sposta(_ mappa: MapProxy, _ c: CLLocationCoordinate2D, alta: CGFloat, testo: String) -> CGSize {
        guard lato.width > 0, lato.height > 0, let p = mappa.convert(c, to: .named(MappaSatellite.spazio)) else { return .zero }
        let m: CGFloat = 4
        let d = MisuraCartellino.di(testo)
        let basso = p.y - alta                                       // dove poggia il cartellino: la cima dell'asta
        let x = min(max(p.x, m + d.width / 2), max(m + d.width / 2, lato.width - m - d.width / 2))
        let y = min(max(basso, m + d.height), max(m + d.height, lato.height - m))
        return CGSize(width: x - p.x, height: y - basso)
    }

    var body: some View {
        MapReader { mappa in
            ZStack {
                Map(position: $posizione, interactionModes: []) {
                    ForEach(luoghi) { l in
                        if visibili.contains(l.chiave) {
                            Annotation("", coordinate: l.coordinata, anchor: .bottom) {
                                AstaSat(testo: etichetta(l), scelta: l.chiave == scelto?.chiave,
                                        sposta: sposta(mappa, l.coordinata, alta: AstaSat.alta, testo: etichetta(l)))
                            }
                        }
                    }
                    if let lei {
                        Annotation("", coordinate: lei, anchor: .bottom) { PuntoLei(sposta: sposta(mappa, lei, alta: PuntoLei.alto + 4, testo: "LEI")) }
                    }
                }
                .mapStyle(.imagery(elevation: .realistic))
                .mapControls { MapCompass().mapControlVisibility(.hidden) }
                .onMapCameraChange(frequency: .continuous) { ctx in camera = ctx.camera }
                // il dito in orizzontale fa girare la camera (come il mockup: −0,008 rad per punto); in verticale la pagina scorre
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { g in
                                let x = g.location.x
                                if let d = dito { giro += Double(d - x) * 0.008 * 180 / .pi }
                                dito = x
                                ultimoTocco = Date()
                            }
                            .onEnded { _ in dito = nil; ultimoTocco = Date() }
                    )
                HudSatellite(camera: camera, meteo: meteo).allowsHitTesting(false)
            }
            .coordinateSpace(.named(MappaSatellite.spazio))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { lato = $0 }
        }
        .onChange(of: scelto?.chiave, initial: true) { _, _ in
            guard let a = scelto?.coordinata else { return }
            if let da = centro { volo = (da, a, Date()) } else { centro = a }
        }
        .onChange(of: lei == nil) { _, _ in if centro == nil, let lei { centro = lei } }
        .task(id: ferma || dietro) {
            // la camera a ogni fotogramma dello schermo, fino a 120 Hz (4 nov; prima 30 volte al secondo): il giro lento, il volo,
            // il dito (coperta da un'altra schermata, o la sezione dietro: ferma)
            guard !ferma, !dietro else { return }
            prima = Date()
            let ritmo = RitmoSatellite { passo() }
            ritmo.avvia()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }      // la cancellazione la sveglia subito
            ritmo.ferma()
        }
    }

    private func passo() {
        let ora = Date()
        let dt = min(0.05, ora.timeIntervalSince(prima))
        prima = ora
        guard var c = centro else { return }
        var quota = 0.0
        if let v = volo {
            // come il mockup: 1,7 s, accelera e frena; a metà strada la camera sale di 420 m
            let p = min(1, ora.timeIntervalSince(v.inizio) / 1.7)
            let e = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            c = CLLocationCoordinate2D(latitude: v.da.latitude + (v.a.latitude - v.da.latitude) * e,
                                       longitude: v.da.longitude + (v.a.longitude - v.da.longitude) * e)
            quota = sin(p * .pi) * 420
            if p >= 1 { volo = nil; c = v.a }
            centro = c
        }
        // senza il dito da 2,6 s, la camera gira piano (0,09 rad/s, come il mockup)
        if dito == nil, ora.timeIntervalSince(ultimoTocco) > 2.6 { giro += dt * 0.09 * 180 / .pi }
        giro = giro.truncatingRemainder(dividingBy: 360)
        if giro < 0 { giro += 360 }
        posizione = .camera(MapCamera(centerCoordinate: c, distance: distanza + quota, heading: giro, pitch: inclinazione))
    }
}

/// Il passo della camera a ogni fotogramma dello schermo (CADisplayLink a 120 Hz, come la ruota delle icone e l'AGGANCIO).
private final class RitmoSatellite: NSObject {
    private let passo: () -> Void
    private var link: CADisplayLink?

    init(_ passo: @escaping () -> Void) { self.passo = passo }

    func avvia() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(scatto(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func ferma() {
        link?.invalidate()
        link = nil
    }

    @objc private func scatto(_ l: CADisplayLink) { passo() }
}

/// L'HUD sulla mappa, come il mockup: in alto SATELLITE · 3D e la bussola, in basso le coordinate con la quota e il meteo,
/// al centro il mirino.
private struct HudSatellite: View {
    let camera: MapCamera?
    let meteo: String?

    var body: some View {
        ZStack {
            // il mirino: un cerchio di 46 punti con la croce che esce di 8
            ZStack {
                Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1).frame(width: 46, height: 46)
                Rectangle().fill(Color.ciano.opacity(0.6)).frame(width: 1, height: 62)
                Rectangle().fill(Color.ciano.opacity(0.6)).frame(width: 62, height: 1)
            }
            VStack {
                HStack(alignment: .top) {
                    testo("SATELLITE · 3D")
                    Spacer()
                    testo(camera.map { Rotta.bussola($0.heading) } ?? "—")
                }
                Spacer()
                // 24 ott, chiesto dal signore: coordinate e quota a destra, più piccole, sopra il meteo;
                // a sinistra resta libero il marchio di Mappe di Apple
                HStack(alignment: .bottom) {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        testo(coordinate, lato: 9).multilineTextAlignment(.trailing)
                        if let meteo { testo(meteo).foregroundStyle(ColoriHUD.chiaro) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var coordinate: String {
        guard let c = camera else { return "—" }
        let la = c.centerCoordinate.latitude, lo = c.centerCoordinate.longitude
        let quota = Int((c.distance * cos(c.pitch * .pi / 180)).rounded())
        return String(format: "%.4f %@ · %.4f %@", abs(la), la >= 0 ? "N" : "S", abs(lo), lo >= 0 ? "E" : "O") + "\nQUOTA \(quota) m"
    }

    private func testo(_ t: String, lato: CGFloat = 11) -> some View {
        Text(t)
            .font(.system(size: lato, weight: .semibold, design: .monospaced)).tracking(1.2)
            .foregroundStyle(Color.ciano.opacity(0.9))
            .shadow(color: Color.ciano.opacity(0.5), radius: 3)
            .lineSpacing(3)
    }
}

/// Il cartellino del mockup (.sat-et): scuro, bordo ciano (arancio sul luogo scelto, verde per lei), lettere da terminale.
struct CartellinoSat: View {
    let testo: String
    var tinta: Color = .ciano
    var scritta: Color = ColoriHUD.chiaro
    var alone = false

    var body: some View {
        Text(testo)
            .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
            .foregroundStyle(scritta)
            .lineLimit(1).fixedSize()
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.02, green: 0.03, blue: 0.035).opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tinta.opacity(alone ? 1 : 0.6), lineWidth: 1))
            .shadow(color: tinta.opacity(alone ? 0.35 : 0), radius: 5)
    }
}

/// L'asta olografica di un luogo: il cartellino in cima, l'asta luminosa, l'anello a terra che pulsa.
/// Decisione 42: `sposta` spinge il cartellino dentro la mappa quando vicino al bordo uscirebbe (lontano dal bordo è zero).
private struct AstaSat: View {
    let testo: String
    let scelta: Bool
    var sposta: CGSize = .zero
    static let arancio = Color(red: 1.0, green: 0.706, blue: 0.353)        // #ffb45a
    /// Dalla base (il luogo) alla cima dell'asta, dove poggia il cartellino: l'anello (12) e l'asta (64).
    static let alta: CGFloat = 12 + 64
    @Environment(\.sezioneDietro) private var dietro                       // 4 nov: dietro (MARK XI) l'anello si ferma

    var body: some View {
        let tinta = scelta ? AstaSat.arancio : Color.ciano
        VStack(spacing: 0) {
            CartellinoSat(testo: testo, tinta: tinta, scritta: scelta ? Color(red: 1, green: 0.85, blue: 0.66) : ColoriHUD.chiaro, alone: scelta)
                .offset(sposta)
            Rectangle().fill(tinta.opacity(0.85)).frame(width: 2.2, height: 64).shadow(color: tinta, radius: 4)
            TimelineView(.animation(minimumInterval: nil, paused: dietro)) { ctx in   // 4 nov: a 120 Hz come tutta l'app (prima 30)
                let p = (ctx.date.timeIntervalSinceReferenceDate * 0.8).truncatingRemainder(dividingBy: 1)
                Ellipse().stroke(tinta, lineWidth: 2)
                    .frame(width: 22, height: 9)
                    .scaleEffect(1 + p * 1.6)
                    .opacity((1 - p) * 0.9)
                    .frame(width: 60, height: 24)
            }
            .frame(height: 12, alignment: .top)
        }
        .allowsHitTesting(false)
    }
}

/// Dove si trova lui: il punto verde con l'anello che pulsa e LEI (spinto dentro la mappa vicino al bordo, decisione 42).
private struct PuntoLei: View {
    var sposta: CGSize = .zero
    private static let verde = Color(red: 0.47, green: 0.90, blue: 0.59)          // #78e696
    /// Il punto con l'anello sotto il cartellino LEI (che poggia 4 punti più su).
    static let alto: CGFloat = 30
    @Environment(\.sezioneDietro) private var dietro                       // 4 nov: dietro (MARK XI) l'anello si ferma
    var body: some View {
        VStack(spacing: 4) {
            CartellinoSat(testo: "LEI", tinta: PuntoLei.verde, scritta: Color(red: 0.79, green: 0.96, blue: 0.84))
                .offset(sposta)
            ZStack {
                TimelineView(.animation(minimumInterval: nil, paused: dietro)) { ctx in // 4 nov: a 120 Hz come tutta l'app (prima 30)
                    let p = (ctx.date.timeIntervalSinceReferenceDate * 0.9).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(PuntoLei.verde, lineWidth: 2).frame(width: 20, height: 20)
                        .scaleEffect(1 + p * 1.5).opacity((1 - p) * 0.9)
                }
                Circle().fill(PuntoLei.verde).frame(width: 11, height: 11)
            }
            .frame(width: 50, height: PuntoLei.alto)
        }
        .allowsHitTesting(false)
    }
}

/// Decisione 42: la misura di un cartellino della mappa senza disegnarlo (stesso carattere di `CartellinoSat`: SF Mono 10
/// grassetto, spaziatura 1, margini 7 ai lati e 3 sopra e sotto), per sapere se vicino al bordo uscirebbe. Ricordata per testo.
@MainActor
enum MisuraCartellino {
    private static var fatte: [String: CGSize] = [:]

    static func di(_ testo: String) -> CGSize {
        if let s = fatte[testo] { return s }
        let carattere = UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
        let t = (testo as NSString).size(withAttributes: [.font: carattere, .kern: 1])
        let s = CGSize(width: ceil(t.width) + 14, height: ceil(t.height) + 6)
        if fatte.count > 300 { fatte.removeAll() }                 // i metri cambiano: niente elenco che cresce per sempre
        fatte[testo] = s
        return s
    }
}
#endif
