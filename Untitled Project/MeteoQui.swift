import Foundation
import CoreLocation
import WeatherKit

/// Meteo di Apple (WeatherKit) esattamente dove si trova il signore: adesso e nelle prossime ore.
/// Vale per iPhone e Apple Watch (stesso file, due target). Servono: capability WeatherKit,
/// servizio WeatherKit attivo sull'identificativo dell'app e la frase NSLocationWhenInUseUsageDescription.
@MainActor
enum MeteoQui {
    private static let posizione = CLLocationManager()

    static func adesso(ore: Int) async -> (String, Bool) {
        if posizione.authorizationStatus == .notDetermined { posizione.requestWhenInUseAuthorization() }
        let dove = await luogoAttuale() ?? CLLocation(latitude: 45.4642, longitude: 9.19)   // senza posizione: Milano
        let stimata = posizione.authorizationStatus == .denied || posizione.authorizationStatus == .restricted
        do {
            let (attuale, orario) = try await WeatherService.shared.weather(for: dove, including: .current, .hourly)
            let f = DateFormatter()
            f.locale = Locale(identifier: "it_IT")
            f.dateFormat = "HH:mm"
            let prossime = orario.forecast.filter { $0.date > Date().addingTimeInterval(-1800) }.prefix(max(1, min(ore, 12)))
            var out: [String: Any] = [
                "fonte": "Apple Meteo",
                "posizione": stimata ? "Milano (posizione non disponibile)" : "posizione attuale del signore",
                "adesso": [
                    "temperatura": Int(attuale.temperature.converted(to: .celsius).value.rounded()),
                    "percepita": Int(attuale.apparentTemperature.converted(to: .celsius).value.rounded()),
                    "cielo": attuale.condition.description,
                    "umidita_pct": Int((attuale.humidity * 100).rounded()),
                    "vento_kmh": Int(attuale.wind.speed.converted(to: .kilometersPerHour).value.rounded()),
                ] as [String: Any],
                "prossime_ore": prossime.map { h -> [String: Any] in
                    ["ora": f.string(from: h.date), "temperatura": Int(h.temperature.converted(to: .celsius).value.rounded()),
                     "cielo": h.condition.description, "probabilita_pioggia_pct": Int((h.precipitationChance * 100).rounded())]
                },
            ]
            if let geo = try? await CLGeocoder().reverseGeocodeLocation(dove).first {
                out["luogo"] = [geo.locality, geo.subLocality].compactMap { $0 }.joined(separator: ", ")
            }
            return (json(out), false)
        } catch {
            return (json(["errore": "Apple Meteo non risponde (\(error.localizedDescription)): usa lo strumento meteo"]), true)
        }
    }

    /// 13.1 · FILO («mostrami il meteo», come il mockup): il meteo in una riga da mostrare («Oggi nuvoloso · 14°, max 17°»), di oggi,
    /// di stasera o di domani, e la frase pronta da mandare a qualcuno («mandalo a Bea»). Nil: Apple Meteo non risponde (ci pensa il
    /// cervello).
    static func rigaFilo(_ giorno: String) async -> (riga: String, daMandare: String)? {
        if posizione.authorizationStatus == .notDetermined { posizione.requestWhenInUseAuthorization() }
        let dove = await luogoAttuale(recente: 1800, entro: 3) ?? CLLocation(latitude: 45.4642, longitude: 9.19)   // senza posizione: Milano
        guard let meteo = try? await WeatherService.shared.weather(for: dove, including: .current, .hourly, .daily) else { return nil }
        let (attuale, orario, giorni) = meteo
        func gradi(_ m: Measurement<UnitTemperature>) -> Int { Int(m.converted(to: .celsius).value.rounded()) }
        func cielo(_ c: WeatherCondition) -> String { c.description.lowercased() }
        let cal = Calendar.current
        switch giorno {
        case "domani":
            guard let d = giorni.forecast.first(where: { cal.isDateInTomorrow($0.date) }) else { return nil }
            let (mi, ma) = (gradi(d.lowTemperature), gradi(d.highTemperature))
            return ("Domani \(cielo(d.condition)) · \(mi)°–\(ma)°", "Domani \(cielo(d.condition)), tra \(mi) e \(ma) gradi.")
        case "stasera":
            let sera = cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()
            guard let h = orario.forecast.min(by: { abs($0.date.timeIntervalSince(sera)) < abs($1.date.timeIntervalSince(sera)) }) else { return nil }
            let t = gradi(h.temperature)
            return ("Stasera \(cielo(h.condition)) · \(t)°", "Stasera \(cielo(h.condition)), \(t) gradi.")
        default:
            let t = gradi(attuale.temperature)
            let massima = giorni.forecast.first(where: { cal.isDateInToday($0.date) }).map { gradi($0.highTemperature) }
            let riga = "Oggi \(cielo(attuale.condition)) · \(t)°" + (massima.map { ", max \($0)°" } ?? "")
            return (riga, "Oggi \(cielo(attuale.condition)), \(t) gradi" + (massima.map { " (massima \($0))" } ?? "") + ".")
        }
    }

    /// Una posizione recente, entro 8 secondi al massimo. `recente`: quanto può essere vecchia quella già nota; `entro`: quanto
    /// aspettarne una nuova (13.1: FILO non aspetta più di 3 secondi).
    private static func luogoAttuale(recente: TimeInterval = 600, entro: Double = 8) async -> CLLocation? {
        if let l = posizione.location, Date().timeIntervalSince(l.timestamp) < recente { return l }
        return await withTaskGroup(of: CLLocation?.self) { g in
            g.addTask {
                do {
                    for try await aggiornamento in CLLocationUpdate.liveUpdates() {
                        if let l = aggiornamento.location { return l }
                    }
                } catch {}
                return nil
            }
            g.addTask {
                try? await Task.sleep(for: .seconds(entro))
                return nil
            }
            let primo = await g.next() ?? nil
            g.cancelAll()
            return primo
        }
    }

    private static func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }
}
