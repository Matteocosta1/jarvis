#if os(iOS)
import SwiftUI
import MapKit
import UIKit
import CoreLocation
import UserNotifications
import Combine

// MARK: - MARK X · TRAVEL (mockup approvato, build 32): «come arrivare» sopra SATELLITE, come il Dossier.
// Sei schede: MEZZI (Transitous, gratis: il percorso vero con le linee, i cambi e gli orari), TRENI (ViaggiaTreno: le partenze
// vere della stazione più vicina, con ritardo e binario), VOLI (AviationStack dal cervello, «travel-voli»: il volo del signore),
// PIEDI (Apple Mappe: tempo e strada, poi la GUIDA di Satellite), BICI (BikeMi, dati aperti: bici, elettriche e posti liberi),
// TAXI (il radiotaxi 02 4040). «Avvisami» mette l'avviso 5 minuti prima di uscire e il conto alla rovescia nella Dynamic Island.

/// Solo iPhone: usa l'indirizzo del cervello e il portachiavi (isolati sul MainActor), come RegiaStudio.
@MainActor
extension DatiTravel {
    /// TRENI: la stazione ferroviaria più vicina (Apple Mappe) e il suo codice ViaggiaTreno. Se non la trova, Milano Centrale.
    static func stazioneVicina(_ c: CLLocationCoordinate2D?) async -> (nome: String, codice: String) {
        let riserva = (nome: "Milano Centrale", codice: "S01700")
        guard let c else { return riserva }
        let r = MKLocalSearch.Request()
        r.naturalLanguageQuery = "stazione ferroviaria"
        r.region = MKCoordinateRegion(center: c, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
        r.resultTypes = .pointOfInterest
        guard let risposta = try? await MKLocalSearch(request: r).start() else { return riserva }
        let lei = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let vicine = risposta.mapItems.sorted {
            lei.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude))
                < lei.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
        }
        for m in vicine.prefix(3) {
            var n = (m.name ?? "").uppercased()
            for via in ["STAZIONE DI ", "STAZIONE ", "FERROVIE DELLO STATO", "(FS)", " FS"] { n = n.replacingOccurrences(of: via, with: "") }
            n = n.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty, let q = n.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let u = URL(string: "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/autocompletaStazione/\(q)"),
                  let (d, _) = try? await URLSession.shared.data(from: u), let t = String(data: d, encoding: .utf8),
                  let riga = t.split(separator: "\n").first, riga.contains("|") else { continue }
            let parti = riga.split(separator: "|")
            return (nome(String(parti[0])), String(parti[1]))
        }
        return riserva
    }

    /// VOLI: lo stato del volo (cervello, funzione «travel-voli», chiave AviationStack nel cervello).
    static func volo(_ numero: String) async -> (VoloTravel?, String?) {
        let base = Impostazioni.indirizzo.replacingOccurrences(of: "/functions/v1/jarvis", with: "/functions/v1/travel-voli")
        guard let url = URL(string: base) else { return (nil, "indirizzo del cervello non valido") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["volo": numero])
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, "il cervello non risponde") }
        if let e = o["errore"] as? String { return (nil, e) }
        let p = o["partenza"] as? [String: Any] ?? [:], a = o["arrivo"] as? [String: Any] ?? [:]
        // AviationStack scrive l'ora locale dell'aeroporto con «+00:00»: si legge così com'è
        let prevista = (p["stimata"] as? String) ?? (p["prevista"] as? String)
        let hhmm = prevista.flatMap { $0.count >= 16 ? String($0.dropFirst(11).prefix(5)) : nil }
        var data: Date?
        if let s = prevista, s.count >= 16 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = roma
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            data = f.date(from: String(s.prefix(16)))
        }
        let v = o["volo"] as? String ?? numero
        return (VoloTravel(volo: v.count > 2 ? "\(v.prefix(2)) \(v.dropFirst(2))" : v, compagnia: o["compagnia"] as? String ?? "",
                           stato: o["stato"] as? String ?? "", daSigla: p["iata"] as? String ?? "", aSigla: a["iata"] as? String ?? "",
                           daNome: p["aeroporto"] as? String ?? "", parte: hhmm, parteData: data,
                           terminal: p["terminal"] as? String, gate: p["gate"] as? String, ritardo: p["ritardo"] as? Int), nil)
    }

    /// Gli aeroporti di Milano (per «Per Linate: … · esci alle …»).
    static let aeroporti: [String: (nome: String, c: CLLocationCoordinate2D, anticipo: TimeInterval)] = [
        "LIN": ("Linate", CLLocationCoordinate2D(latitude: 45.4600, longitude: 9.2783), 3600),
        "MXP": ("Malpensa", CLLocationCoordinate2D(latitude: 45.6273, longitude: 8.7112), 5400),
        "BGY": ("Orio al Serio", CLLocationCoordinate2D(latitude: 45.6687, longitude: 9.7004), 5400),
    ]

    /// PIEDI: tempo e metri veri a piedi (Apple Mappe).
    static func aPiedi(da: CLLocationCoordinate2D, a: CLLocationCoordinate2D) async -> (secondi: Double, metri: Double)? {
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: da))
        r.destination = MKMapItem(placemark: MKPlacemark(coordinate: a))
        r.transportType = .walking
        guard let route = try? await MKDirections(request: r).calculate().routes.first else { return nil }
        return (route.expectedTravelTime, route.distance)
    }

    /// TAXI: quanto ci mette un'auto (Apple Mappe), per la stima.
    static func inAuto(da: CLLocationCoordinate2D, a: CLLocationCoordinate2D) async -> Double? {
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: da))
        r.destination = MKMapItem(placemark: MKPlacemark(coordinate: a))
        r.transportType = .automobile
        return try? await MKDirections(request: r).calculateETA().expectedTravelTime
    }
}

/// Il volo del signore, ricordato sull'iPhone («Jarvis, il volo AZ 2041 è in orario?»).
@MainActor
enum VoloSalvato {
    static var numero: String? {
        get { UserDefaults.standard.string(forKey: "travelVolo") }
        set { UserDefaults.standard.set(newValue, forKey: "travelVolo") }
    }
}

// MARK: - La schermata

struct SchermoTravel: View {
    let luogo: LuogoSat
    let iniziale: SchedaTravel
    /// Lat/lon di dove si trova (da SATELLITE).
    let lei: CLLocationCoordinate2D?
    let chiudi: () -> Void
    let guida: () -> Void
    @State private var scheda: SchedaTravel = .mezzi
    @State private var percorso: PercorsoTravel?
    @State private var caricoPercorso = true
    @State private var stazione: (nome: String, codice: String)?
    @State private var treni: [PartenzaTreno]?
    @State private var lettiTreni: Date?
    @State private var bici: [StazioneBici]?
    @State private var lettiBici: Date?
    @State private var piedi: (secondi: Double, metri: Double)?
    @State private var auto: Double?
    @State private var volo: VoloTravel?
    @State private var erroreVolo: String?
    @State private var verso: (linea: String, fermata: String, esci: Date)?
    @State private var avviso = AvvisoTravel.attivo
    @State private var caricato: Set<SchedaTravel> = []

    private let ciano = Color.ciano
    private let grigio = Color(red: 159 / 255, green: 179 / 255, blue: 185 / 255)
    private let chiaro = Color(red: 230 / 255, green: 244 / 255, blue: 248 / 255)
    private let verde = Color(red: 95 / 255, green: 227 / 255, blue: 161 / 255)
    private let ambra = Color(red: 1, green: 159 / 255, blue: 67 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            Color.fondo.ignoresSafeArea()
            RadialGradient(colors: [ciano.opacity(0.14), .clear], center: .top, startRadius: 0, endRadius: 300)
                .frame(height: 300).frame(maxWidth: .infinity).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRAVEL").font(.system(size: 22, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(.white)
                        Text("COME ARRIVARE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(ciano)
                    }
                    Spacer()
                    Button { Suoni.tocco(); chiudi() } label: {
                        Text("Chiudi").font(.system(size: 17, weight: .semibold)).foregroundStyle(ciano)
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(StileStark())
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        meta
                        schede
                        contenuto
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { scheda = iniziale }
        .task(id: scheda) { await carica(scheda) }
    }

    // MARK: Pezzi

    private var meta: some View {
        let arrivo = percorso.map { "ARRIVO \(DatiTravel.ora($0.arrivo))" }
        return (Text("VERSO ").foregroundStyle(grigio) + Text(luogo.nome.uppercased()).foregroundStyle(chiaro)
                + Text(arrivo.map { " · \($0)" } ?? "").foregroundStyle(grigio)
                + Text(luogo.tipo == "ricognizione" ? " · indirizzo" : " · luogo salvato").foregroundStyle(Color.tenue))
            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
    }

    private var schede: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SchedaTravel.allCases) { s in
                    Button { Suoni.tocco(); scheda = s } label: {
                        Text(s.titolo).font(.system(size: 11, weight: scheda == s ? .bold : .semibold, design: .monospaced)).tracking(2)
                            .foregroundStyle(scheda == s ? Color(red: 0, green: 24 / 255, blue: 32 / 255) : grigio)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(Capsule().fill(scheda == s ? ciano : .clear))
                            .overlay(Capsule().stroke(scheda == s ? ciano : ciano.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(StileStark())
                    .accessibilityAddTraits(scheda == s ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private var contenuto: some View {
        switch scheda {
        case .mezzi: mezzi
        case .treni: treniVista
        case .voli: voli
        case .piedi: piediVista
        case .bici: biciVista
        case .taxi: taxi
        }
    }

    private func attesa(_ t: String) -> some View {
        Text(t).font(.system(size: 12, design: .monospaced)).foregroundStyle(grigio).padding(.vertical, 18)
    }

    private func fonte(_ t: String) -> some View {
        Text(t).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.tenue)
    }

    // MEZZI

    @ViewBuilder private var mezzi: some View {
        if let p = percorso {
            VStack(alignment: .leading, spacing: 6) {
                Text("ESCI ALLE").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(grigio)
                Text(DatiTravel.ora(p.esci)).font(.system(size: 52, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let s = Int(p.esci.timeIntervalSince(tl.date))
                    Text(s > 0 ? "fra \(s / 60) min \(String(format: "%02d", s % 60)) s" : "esca adesso")
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(chiaro)
                        .opacity(0.65 + 0.35 * abs(cos(tl.date.timeIntervalSinceReferenceDate * .pi / 1.6)))
                }
                HStack(spacing: 18) {
                    dato("ARRIVO", DatiTravel.ora(p.arrivo))
                    dato("DURATA", "\(Int(p.arrivo.timeIntervalSince(p.esci) / 60)) min")
                    dato("CAMBI", "\(p.cambi)")
                }
                .padding(.top, 6)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(ciano.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ciano.opacity(0.35), lineWidth: 1))
            VStack(spacing: 0) {
                ForEach(Array(p.tratte.enumerated()), id: \.element.id) { k, t in
                    rigaTratta(t, filo: k < p.tratte.count - 1)
                }
            }
            HStack(spacing: 10) {
                Button { Suoni.tocco(); attivaAvviso(p) } label: {
                    Text(avviso != nil ? "Avviso alle \(DatiTravel.ora(p.esci.addingTimeInterval(-300))) ✓" : "Avvisami")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(avviso != nil ? verde : Color(red: 0, green: 24 / 255, blue: 31 / 255))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(avviso != nil ? Color.clear : ciano))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(avviso != nil ? verde : .clear, lineWidth: 1))
                }
                .buttonStyle(StileStark())
                Button { Suoni.tocco(); apriInMappe() } label: {
                    Text("Apri in Mappe").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(ciano)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ciano.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(StileStark())
            }
            fonte("Percorso: Transitous (gratis) · orari \(p.tempoVero ? "aggiornati dal vivo" : "di linea"), letti alle \(DatiTravel.ora(Date()))")
        } else if caricoPercorso {
            attesa("CALCOLO IL PERCORSO…")
        } else {
            attesa(lei == nil ? "Mi serve la sua posizione, Sir: la attivi per JARVIS." : "Nessun percorso con i mezzi trovato adesso.")
        }
    }

    private func dato(_ k: String, _ v: String) -> some View {
        (Text("\(k) ").foregroundStyle(grigio) + Text(v).foregroundStyle(chiaro).bold()).font(.system(size: 12, design: .monospaced))
    }

    private func rigaTratta(_ t: TrattaTravel, filo: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                ZStack {
                    if let c = t.colore, t.tipo == .mezzo {
                        Circle().fill(c)
                        Text(t.sigla ?? "").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(t.coloreTesto)
                            .minimumScaleFactor(0.6).lineLimit(1).padding(3)
                    } else if t.tipo == .mezzo {
                        Circle().stroke(ciano.opacity(0.5), lineWidth: 1)
                        Text(t.sigla ?? "").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            .minimumScaleFactor(0.6).lineLimit(1).padding(3)
                    } else {
                        Circle().stroke(ciano.opacity(0.5), lineWidth: 1)
                        Image(systemName: t.tipo == .piedi ? "figure.walk" : t.tipo == .cambio ? "arrow.left.arrow.right" : "mappin.and.ellipse")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(ciano)
                    }
                }
                .frame(width: 34, height: 34)
                if filo { FiloTratta().frame(width: 2).frame(maxHeight: .infinity).opacity(0.6) }
            }
            .frame(width: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.titolo).font(.system(size: 13, design: .monospaced)).foregroundStyle(chiaro)
                if !t.dettaglio.isEmpty { Text(t.dettaglio).font(.system(size: 11, design: .monospaced)).foregroundStyle(grigio) }
            }
            .padding(.bottom, 12)
            Spacer(minLength: 4)
            Text(DatiTravel.ora(t.ora)).font(.system(size: 12, design: .monospaced)).foregroundStyle(grigio)
        }
        .frame(minHeight: 58, alignment: .top)
    }

    // TRENI

    @ViewBuilder private var treniVista: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(stazione?.nome ?? "Stazione…").font(.system(size: 15, design: .monospaced)).foregroundStyle(chiaro)
            Spacer()
            Text("PARTENZE · \(DatiTravel.ora(lettiTreni ?? Date()))").font(.system(size: 11, design: .monospaced)).foregroundStyle(grigio)
        }
        rigaTreno(ora: "ORA", d: "DESTINAZIONE", sotto: nil, r: "RITARDO", b: "BIN.", testa: true)
        if let t = treni {
            if t.isEmpty { attesa("Nessuna partenza nella prossima ora.") }
            ForEach(t) { p in
                rigaTreno(ora: DatiTravel.ora(p.ora), d: p.destinazione, sotto: p.treno,
                          r: p.ritardo > 0 ? "+\(p.ritardo)" : "orario", b: p.binario, ritardo: p.ritardo)
            }
            fonte("Dati ViaggiaTreno (Trenitalia · RFI · Trenord), letti davvero alle \(DatiTravel.ora(lettiTreni ?? Date()))")
        } else if caricato.contains(.treni) {
            attesa("ViaggiaTreno non risponde adesso, Sir.")
        } else {
            attesa("LEGGO LE PARTENZE…")
        }
    }

    private func rigaTreno(ora: String, d: String, sotto: String?, r: String, b: String, testa: Bool = false, ritardo: Int = 0) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(ora).frame(width: 52, alignment: .leading).font(.system(size: testa ? 10 : 14, design: .monospaced))
                .foregroundStyle(testa ? Color.tenue : chiaro)
            VStack(alignment: .leading, spacing: 1) {
                Text(d).font(.system(size: testa ? 10 : 13, design: .monospaced)).foregroundStyle(testa ? Color.tenue : chiaro).lineLimit(1)
                if let sotto { Text(sotto).font(.system(size: 10, design: .monospaced)).foregroundStyle(grigio) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(r).frame(width: 52, alignment: .leading)
                .font(.system(size: testa ? 10 : 13, weight: !testa && ritardo > 5 ? .bold : .regular, design: .monospaced))
                .foregroundStyle(testa ? Color.tenue : ritardo > 5 ? ambra : ritardo > 0 ? Color(red: 1, green: 210 / 255, blue: 122 / 255) : verde)
            Text(b).frame(width: 34, alignment: .leading)
                .font(.system(size: testa ? 10 : 15, weight: testa ? .regular : .bold, design: .monospaced))
                .foregroundStyle(testa ? Color.tenue : ciano)
        }
        .padding(.vertical, testa ? 0 : 10)
        .overlay(alignment: .top) { if !testa { Rectangle().fill(ciano.opacity(0.12)).frame(height: 1) } }
    }

    // VOLI

    @ViewBuilder private var voli: some View {
        if let v = volo {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("IL TUO VOLO").tracking(2).foregroundStyle(grigio)
                    Spacer()
                    Text(statoVolo(v).0).foregroundStyle(statoVolo(v).1)
                }
                .font(.system(size: 11, design: .monospaced))
                Text("\(v.volo) · \(v.daSigla) → \(v.aSigla)").font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(chiaro)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 16) {
                    dato("PARTE", v.parte ?? "—")
                    dato("TERMINAL", v.terminal ?? "—")
                    dato("GATE", v.gate ?? "—")
                }
                if let verso, let a = DatiTravel.aeroporti[v.daSigla] {
                    (Text("Per \(a.nome): ").foregroundStyle(chiaro) + Text(verso.linea).foregroundStyle(ciano).bold()
                     + Text(" da \(verso.fermata) · esci alle \(DatiTravel.ora(verso.esci))").foregroundStyle(chiaro))
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.top, 8)
                        .overlay(alignment: .top) { Rectangle().fill(ciano.opacity(0.15)).frame(height: 1) }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ciano.opacity(0.35), lineWidth: 1))
        } else if let e = erroreVolo {
            attesa(e)
        } else if VoloSalvato.numero == nil {
            attesa("Nessun volo salvato, Sir.")
        } else {
            attesa("LEGGO IL VOLO…")
        }
        Text("Dica «Jarvis, il mio volo è in orario?» o il numero del volo.").font(.system(size: 11, design: .monospaced)).foregroundStyle(grigio)
        fonte("Orari voli: AviationStack (piano gratuito, 100 ricerche al mese)")
    }

    private func statoVolo(_ v: VoloTravel) -> (String, Color) {
        switch v.stato {
        case "landed": return ("ATTERRATO", verde)
        case "active": return ("IN VOLO", ciano)
        case "cancelled": return ("CANCELLATO", .red)
        case "diverted": return ("DIROTTATO", ambra)
        case "incident": return ("PROBLEMA", .red)
        default:
            if let r = v.ritardo, r > 5 { return ("RITARDO +\(r)′", ambra) }
            return ("IN ORARIO", verde)
        }
    }

    // PIEDI

    @ViewBuilder private var piediVista: some View {
        if let p = piedi {
            VStack(alignment: .leading, spacing: 6) {
                Text("A PIEDI").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(grigio)
                Text("\(Int(p.secondi / 60)) min").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                Text("\(String(format: "%.1f", p.metri / 1000).replacingOccurrences(of: ".", with: ",")) km · arrivo \(DatiTravel.ora(Date().addingTimeInterval(p.secondi))) se esci adesso")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(grigio)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(ciano.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ciano.opacity(0.35), lineWidth: 1))
            TastoComando(testo: "Guida con Satellite") { Suoni.tocco(); guida() }
            fonte("La guida è quella di SATELLITE, che resta dov'è")
        } else if caricato.contains(.piedi) {
            attesa(lei == nil ? "Mi serve la sua posizione, Sir." : "Apple Mappe non trova la strada a piedi.")
        } else {
            attesa("CALCOLO LA STRADA…")
        }
    }

    // BICI

    @ViewBuilder private var biciVista: some View {
        if let b = bici {
            if b.isEmpty { attesa("Nessuna stazione BikeMi qui vicino, Sir.") }
            ForEach(b) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DatiTravel.nome(s.nome)).font(.system(size: 13, design: .monospaced)).foregroundStyle(chiaro).lineLimit(1)
                        Text(s.vicinoMeta ? "vicino a \(luogo.nome)" : "\(Int(s.metri.rounded())) m da te")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(grigio)
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        numero(s.bici, "BICI", ciano)
                        numero(s.elettriche, "ELETTR.", ciano)
                        numero(s.posti, "POSTI", chiaro)
                    }
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ciano.opacity(0.25), lineWidth: 1))
            }
            fonte("Dati aperti BikeMi, letti alle \(DatiTravel.ora(lettiBici ?? Date()))")
        } else if caricato.contains(.bici) {
            attesa("BikeMi non risponde adesso, Sir.")
        } else {
            attesa("CERCO LE BICI…")
        }
    }

    private func numero(_ n: Int, _ k: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(n)").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(c)
            Text(k).font(.system(size: 9, design: .monospaced)).foregroundStyle(grigio)
        }
    }

    // TAXI

    @ViewBuilder private var taxi: some View {
        Button { Suoni.tocco(); if let u = URL(string: "tel:024040") { UIApplication.shared.open(u) } } label: {
            Text("Chiama il radiotaxi").font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0, green: 24 / 255, blue: 31 / 255))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(ciano))
        }
        .buttonStyle(StileStark())
        TastoComando(testo: "Apri l'app taxi su «\(luogo.nome)»") { Suoni.tocco(); apriAppTaxi() }
        Text("Radiotaxi 02 4040 · \(auto.map { "stima del tragitto: \(Int($0 / 60)) min" } ?? "stima del tragitto…")")
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(grigio)
    }

    // MARK: Azioni

    private func carica(_ s: SchedaTravel) async {
        let meta = luogo.coordinata
        switch s {
        case .mezzi:
            if percorso == nil, let lei {
                caricoPercorso = true
                percorso = await DatiTravel.percorso(da: lei, a: meta, meta: luogo.nome)
            }
            caricoPercorso = false
        case .treni:
            if stazione == nil { stazione = await DatiTravel.stazioneVicina(lei) }
            if let c = stazione?.codice { treni = await DatiTravel.partenze(c); lettiTreni = Date() }
        case .voli:
            guard let n = VoloSalvato.numero, volo == nil else { break }
            let (v, e) = await DatiTravel.volo(n)
            volo = v
            erroreVolo = e.map { $0 == "volo non trovato" ? "Il volo \(n) oggi non lo trovo, Sir." : "Non leggo il volo adesso: \($0)." }
            if let v, let a = DatiTravel.aeroporti[v.daSigla], let parte = v.parteData, parte > Date(), let lei,
               let p = await DatiTravel.percorso(da: lei, a: a.c, meta: a.nome, arrivoEntro: parte.addingTimeInterval(-a.anticipo)),
               let l = p.primaLinea, let f = p.primaFermata {
                verso = (l, f, p.esci)
            }
        case .piedi:
            if let lei { piedi = await DatiTravel.aPiedi(da: lei, a: meta) }
        case .bici:
            bici = await DatiTravel.bici(lei: lei, meta: meta)
            lettiBici = Date()
        case .taxi:
            if let lei { auto = await DatiTravel.inAuto(da: lei, a: meta) }
        }
        caricato.insert(s)
    }

    private func attivaAvviso(_ p: PercorsoTravel) {
        if avviso != nil {
            AvvisoTravel.spegni()
            avviso = nil
            return
        }
        AvvisoTravel.accendi(p, meta: luogo.nome)
        avviso = AvvisoTravel.attivo
        OcchiAperti.parla?("Le dico io quando uscire, Sir: alle \(DatiTravel.ora(p.esci.addingTimeInterval(-300))). Il conto alla rovescia è nella Dynamic Island.")
    }

    private func apriInMappe() {
        let m = MKMapItem(placemark: MKPlacemark(coordinate: luogo.coordinata))
        m.name = luogo.nome
        m.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }

    private func apriAppTaxi() {
        let m = MKMapItem(placemark: MKPlacemark(coordinate: luogo.coordinata))
        m.name = luogo.nome
        m.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// Il filo tratteggiato che scorre tra una tratta e l'altra (tvScorre del mockup).
private struct FiloTratta: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let f = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9 * 8
            GeometryReader { g in
                Path { p in p.move(to: CGPoint(x: 1, y: 0)); p.addLine(to: CGPoint(x: 1, y: g.size.height)) }
                    .stroke(Color.ciano, style: StrokeStyle(lineWidth: 2, dash: [4, 4], dashPhase: -f))
            }
        }
    }
}

/// «Avvisami»: la notifica 5 minuti prima di uscire e il conto alla rovescia nell'isola (IsolaJarvis, se c'è).
@MainActor
enum AvvisoTravel {
    static var attivo: Date? {
        guard let d = UserDefaults.standard.object(forKey: "travelAvviso") as? Date, d > Date() else { return nil }
        return d
    }

    static func accendi(_ p: PercorsoTravel, meta: String) {
        let quando = p.esci.addingTimeInterval(-300)
        UserDefaults.standard.set(p.esci, forKey: "travelAvviso")
        let c = UNMutableNotificationContent()
        c.title = "TRAVEL"
        c.body = "Esca alle \(DatiTravel.ora(p.esci)), Sir\(p.primaLinea.map { ": \($0) da \(p.primaFermata ?? "")" } ?? "") verso \(meta)."
        c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(quando.timeIntervalSinceNow, 1), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "travel-avviso", content: c, trigger: t))
        IsolaJarvis.travel(esci: p.esci, linea: p.primaLinea ?? "", ora: DatiTravel.ora(p.tratte.first(where: { $0.tipo == .mezzo })?.ora ?? p.esci),
                           percorso: (p.lineaIsola ?? meta) + " · arrivo \(DatiTravel.ora(p.arrivo))", meta: meta)
    }

    static func spegni() {
        UserDefaults.standard.removeObject(forKey: "travelAvviso")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["travel-avviso"])
        IsolaJarvis.fineTravel()
    }
}
#endif
