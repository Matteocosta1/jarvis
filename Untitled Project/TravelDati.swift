import Foundation
import CoreLocation
import SwiftUI

// MARK: - MARK X · TRAVEL, i dati veri (iPhone e orologio): i tipi, il percorso dei mezzi (Transitous), le partenze dei treni
// (ViaggiaTreno) e le bici (BikeMi). La schermata dell'iPhone è in Travel.swift, quella del polso in TravelOrologio.swift.

nonisolated enum SchedaTravel: String, CaseIterable, Identifiable, Sendable {
    case mezzi, treni, voli, piedi, bici, taxi
    var id: String { rawValue }
    var titolo: String { rawValue.uppercased() }
}

/// Un pezzo del percorso, come una riga del mockup: a piedi, un mezzo (con la sua sigla e il suo colore), un cambio, l'arrivo.
nonisolated struct TrattaTravel: Identifiable, Sendable {
    nonisolated enum Tipo: Sendable { case piedi, mezzo, cambio, arrivo }
    let id = UUID()
    let tipo: Tipo
    var sigla: String? = nil
    var colore: Color? = nil
    var coloreTesto: Color = .white
    let titolo: String
    let dettaglio: String
    let ora: Date
}

nonisolated struct PercorsoTravel: Sendable {
    let esci: Date
    let arrivo: Date
    let cambi: Int
    let tratte: [TrattaTravel]
    let primaLinea: String?          // «M1» (per l'avviso e l'isola)
    let primaFermata: String?        // «Duomo M1»
    let lineaIsola: String?          // «Duomo M1 → Loreto · M2 → Bea» (riga dell'isola)
    let tempoVero: Bool              // almeno un orario aggiornato dal vivo
}

nonisolated struct PartenzaTreno: Identifiable, Sendable {
    let id: String
    let ora: Date
    let destinazione: String
    let treno: String
    let ritardo: Int
    let binario: String
}

nonisolated struct StazioneBici: Identifiable, Sendable {
    let id: String
    let nome: String
    let metri: Double
    let bici: Int
    let elettriche: Int
    let posti: Int
    let vicinoMeta: Bool
}

nonisolated struct VoloTravel: Sendable {
    let volo: String, compagnia: String, stato: String
    let daSigla: String, aSigla: String, daNome: String
    let parte: String?               // «07:00», ora locale dell'aeroporto
    let parteData: Date?
    let terminal: String?, gate: String?
    let ritardo: Int?
}

// MARK: - I dati veri

nonisolated enum DatiTravel {
    static let roma = TimeZone(identifier: "Europe/Rome") ?? .current

    static func ora(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.timeZone = roma
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// «DUOMO M3» → «Duomo M3»; le sigle (M3, FS, T.I.B.B.) restano maiuscole.
    static func nome(_ s: String) -> String {
        s.split(separator: " ").map { p -> String in
            let w = String(p)
            if w.count <= 2 || w.contains(where: \.isNumber) || w.contains(".") { return w.uppercased() == w ? w : w.capitalized }
            return w.prefix(1).uppercased() + w.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func iso(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }

    private static func colore(_ hex: String?) -> Color? {
        guard let hex, hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// Le metro di Milano col loro colore detto a parole.
    private static let metroMilano = ["1": "rossa", "2": "verde", "3": "gialla", "4": "blu", "5": "lilla"]

    /// Il numero del volo dentro una frase («il volo AZ 2041», «FR4521», «az duemila…» no): nil se non c'è.
    static func numeroVolo(_ f: String) -> String? {
        let t = f.uppercased()
        guard let r = t.range(of: "\\b([A-Z]{2}|[A-Z][0-9]|[0-9][A-Z])\\s?[0-9]{1,4}[A-Z]?\\b", options: .regularExpression) else { return nil }
        let v = String(t[r]).replacingOccurrences(of: " ", with: "")
        guard v.contains(where: \.isNumber), v.contains(where: \.isLetter) else { return nil }
        return v
    }

    /// MEZZI: il percorso di Transitous (gratis, senza chiave). `arrivoEntro`: per arrivare entro quell'ora (VOLI → aeroporto).
    static func percorso(da: CLLocationCoordinate2D, a: CLLocationCoordinate2D, meta: String, arrivoEntro: Date? = nil) async -> PercorsoTravel? {
        var u = URLComponents(string: "https://api.transitous.org/api/v1/plan")
        var q = [URLQueryItem(name: "fromPlace", value: String(format: "%.6f,%.6f", da.latitude, da.longitude)),
                 URLQueryItem(name: "toPlace", value: String(format: "%.6f,%.6f", a.latitude, a.longitude))]
        if let arrivoEntro {
            q.append(URLQueryItem(name: "time", value: ISO8601DateFormatter().string(from: arrivoEntro)))
            q.append(URLQueryItem(name: "arriveBy", value: "true"))
        }
        u?.queryItems = q
        guard let url = u?.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.setValue("JARVIS (iPhone)", forHTTPHeaderField: "User-Agent")
        guard let (d, risp) = try? await URLSession.shared.data(for: r), (risp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let its = o["itineraries"] as? [[String: Any]] else { return nil }
        let adesso = Date().addingTimeInterval(-60)
        let scelti = its.filter { (iso($0["startTime"] as? String) ?? .distantPast) >= adesso || arrivoEntro != nil }
        guard let it = (arrivoEntro != nil ? scelti.last : scelti.first) ?? its.first,
              let esci = iso(it["startTime"] as? String), let arrivo = iso(it["endTime"] as? String),
              let legs = it["legs"] as? [[String: Any]], !legs.isEmpty else { return nil }
        var tratte: [TrattaTravel] = []
        var primaLinea: String?, primaFermata: String?, pezziIsola: [String] = []
        var vero = false
        for (i, l) in legs.enumerated() {
            let modo = l["mode"] as? String ?? "WALK"
            let inizio = iso(l["startTime"] as? String) ?? esci
            let durata = Int(((l["duration"] as? Double) ?? Double(l["duration"] as? Int ?? 0)) / 60)
            let da = nome((l["from"] as? [String: Any])?["name"] as? String ?? "")
            var a = nome((l["to"] as? [String: Any])?["name"] as? String ?? "")
            if a.uppercased() == "END" { a = meta }
            if (l["realTime"] as? Bool) == true { vero = true }
            if modo == "WALK" {
                let m = Int((l["distance"] as? Double) ?? Double(l["distance"] as? Int ?? 0))
                if i == legs.count - 1 {
                    tratte.append(TrattaTravel(tipo: .arrivo, titolo: "A piedi fino a \(meta)", dettaglio: "\(max(durata, 1)) min", ora: inizio))
                } else if i == 0 {
                    tratte.append(TrattaTravel(tipo: .piedi, titolo: "A piedi fino a \(a)", dettaglio: "\(max(durata, 1)) min · \(m) m", ora: inizio))
                } else {
                    tratte.append(TrattaTravel(tipo: .cambio, titolo: "Cambio a \(da)", dettaglio: "\(max(durata, 1)) min a piedi", ora: inizio))
                }
                continue
            }
            let corta = l["routeShortName"] as? String ?? l["displayName"] as? String ?? ""
            let agenzia = (l["agencyName"] as? String ?? "").uppercased()
            let direzione = nome(l["headsign"] as? String ?? "")
            let fermate = ((l["intermediateStops"] as? [Any])?.count ?? 0) + 1
            let sigla: String, mezzo: String
            switch modo {
            case "SUBWAY", "METRO":
                sigla = corta.hasPrefix("M") ? corta : "M\(corta)"
                let n = corta.replacingOccurrences(of: "M", with: "")
                mezzo = agenzia.contains("ATM") ? "Metro \(metroMilano[n] ?? n)" : "Metro \(sigla)"
            case "TRAM": sigla = corta; mezzo = "Tram \(corta)"
            case "BUS", "COACH": sigla = corta; mezzo = "Bus \(corta)"
            default:
                let nomeTreno = l["displayName"] as? String ?? corta
                sigla = String(nomeTreno.split(separator: " ").first ?? "").prefix(4).uppercased()
                mezzo = nomeTreno
            }
            let col = colore(l["routeColor"] as? String)
            let testo = colore(l["routeTextColor"] as? String) ?? .white
            tratte.append(TrattaTravel(tipo: .mezzo, sigla: sigla, colore: col, coloreTesto: testo, titolo: "\(mezzo) → \(a)",
                                       dettaglio: "\(direzione.isEmpty ? "" : "direzione \(direzione) · ")\(fermate) \(fermate == 1 ? "fermata" : "fermate") · \(max(durata, 1)) min",
                                       ora: inizio))
            if primaLinea == nil { primaLinea = sigla; primaFermata = da }
            pezziIsola.append(pezziIsola.isEmpty ? "\(da) \(sigla) → \(a)" : "\(sigla) → \(a)")
        }
        if tratte.last?.tipo != .arrivo {
            tratte.append(TrattaTravel(tipo: .arrivo, titolo: "Arrivo a \(meta)", dettaglio: "", ora: arrivo))
        }
        let cambi = it["transfers"] as? Int ?? max(0, tratte.filter { $0.tipo == .mezzo }.count - 1)
        let isola = pezziIsola.isEmpty ? nil : (pezziIsola + [meta]).joined(separator: " · ").replacingOccurrences(of: " · \(meta)", with: " → \(meta)")
        return PercorsoTravel(esci: esci, arrivo: arrivo, cambi: cambi, tratte: tratte, primaLinea: primaLinea, primaFermata: primaFermata,
                              lineaIsola: isola, tempoVero: vero)
    }

    /// TRENI: le partenze vere (ViaggiaTreno, Trenitalia · RFI · Trenord).
    static func partenze(_ codice: String) async -> [PartenzaTreno]? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = roma
        f.dateFormat = "EEE MMM dd yyyy HH:mm:ss 'GMT'Z"
        guard let quando = f.string(from: Date()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let u = URL(string: "https://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno/partenze/\(codice)/\(quando)"),
              let (d, risp) = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 12)),
              (risp as? HTTPURLResponse)?.statusCode == 200,
              let lista = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return nil }
        let soglia = Date().addingTimeInterval(-90)
        return lista.compactMap { t -> PartenzaTreno? in
            guard let ms = (t["orarioPartenza"] as? Double) ?? (t["orarioPartenza"] as? Int).map(Double.init) else { return nil }
            let ora = Date(timeIntervalSince1970: ms / 1000)
            guard ora >= soglia else { return nil }
            let num = (t["numeroTreno"] as? Int).map(String.init) ?? "\(t["numeroTreno"] ?? "")"
            let cat = (t["categoriaDescrizione"] as? String ?? t["categoria"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let bin = (t["binarioEffettivoPartenzaDescrizione"] as? String) ?? (t["binarioProgrammatoPartenzaDescrizione"] as? String) ?? "—"
            return PartenzaTreno(id: "\(num)-\(ms)", ora: ora, destinazione: nome(t["destinazione"] as? String ?? ""),
                                 treno: [cat, num].filter { !$0.isEmpty }.joined(separator: " "),
                                 ritardo: t["ritardo"] as? Int ?? 0, binario: bin.trimmingCharacters(in: .whitespaces))
        }.sorted { $0.ora < $1.ora }.prefix(6).map { $0 }
    }

    /// BICI: BikeMi (dati aperti GBFS). Le due stazioni più vicine a lei e quella più vicina alla meta.
    static func bici(lei: CLLocationCoordinate2D?, meta: CLLocationCoordinate2D) async -> [StazioneBici]? {
        guard let ui = URL(string: "https://gbfs.urbansharing.com/bikemi.com/station_information.json"),
              let us = URL(string: "https://gbfs.urbansharing.com/bikemi.com/station_status.json") else { return nil }
        async let a = URLSession.shared.data(from: ui)
        async let b = URLSession.shared.data(from: us)
        guard let (di, _) = try? await a, let (ds, _) = try? await b,
              let oi = try? JSONSerialization.jsonObject(with: di) as? [String: Any],
              let os = try? JSONSerialization.jsonObject(with: ds) as? [String: Any],
              let info = (oi["data"] as? [String: Any])?["stations"] as? [[String: Any]],
              let stato = (os["data"] as? [String: Any])?["stations"] as? [[String: Any]] else { return nil }
        var conti: [String: (Int, Int, Int)] = [:]
        for s in stato {
            guard let id = s["station_id"] as? String, (s["is_renting"] as? Bool) != false else { continue }
            var bici = 0, ele = 0
            for v in s["vehicle_types_available"] as? [[String: Any]] ?? [] {
                let n = v["count"] as? Int ?? 0
                if (v["vehicle_type_id"] as? String ?? "").contains("ebike") { ele += n } else { bici += n }
            }
            conti[id] = (bici, ele, s["num_docks_available"] as? Int ?? 0)
        }
        func lista(_ c: CLLocationCoordinate2D, meta: Bool) -> [StazioneBici] {
            let p = CLLocation(latitude: c.latitude, longitude: c.longitude)
            return info.compactMap { s -> StazioneBici? in
                guard let id = s["station_id"] as? String, let la = s["lat"] as? Double, let lo = s["lon"] as? Double, let n = conti[id] else { return nil }
                let m = p.distance(from: CLLocation(latitude: la, longitude: lo))
                return StazioneBici(id: id + (meta ? "-m" : ""), nome: s["name"] as? String ?? "BikeMi", metri: m, bici: n.0, elettriche: n.1, posti: n.2, vicinoMeta: meta)
            }.sorted { $0.metri < $1.metri }
        }
        var r: [StazioneBici] = []
        if let lei { r += lista(lei, meta: false).filter { $0.metri < 2_000 }.prefix(2) }
        if let m = lista(meta, meta: true).first, m.metri < 1_000, !r.contains(where: { $0.id + "-m" == m.id }) { r.append(m) }
        return r
    }

}
