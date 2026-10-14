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

    /// Una posizione recente, entro 8 secondi al massimo.
    private static func luogoAttuale() async -> CLLocation? {
        if let l = posizione.location, Date().timeIntervalSince(l.timestamp) < 600 { return l }
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
                try? await Task.sleep(for: .seconds(8))
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
