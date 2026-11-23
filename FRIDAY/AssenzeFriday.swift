// FRIDAY — quello che le novità di JARVIS chiedono a parti che FRIDAY non ha (Apple Watch, Travel, Sessione dello Studio):
// qui solo i pezzi che servono davvero sull'iPhone di Bea. Niente orologio: il «polso» non c'è mai.
#if os(iOS)
import Foundation
import EventKit
import MapKit
import CoreLocation

/// Il ponte con l'orologio di JARVIS. Bea non ha l'Apple Watch: il polso non è mai raggiungibile e non si manda niente.
nonisolated final class PonteTelefono: @unchecked Sendable {
    static let condiviso = PonteTelefono()
    var polsoRaggiungibile: Bool { false }
    func inviaAlPolso(_ messaggio: [String: Any]) {}
    func invia() {}

    /// Gli impegni di oggi con un orario (al massimo 8): «m» i minuti dalla mezzanotte, «nome» il titolo. Vuoto senza il permesso.
    static func impegniDiOggi() -> [[String: Any]] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let negozio = EKEventStore(), cal = Calendar.current, oggi = cal.startOfDay(for: Date())
        let domani = cal.date(byAdding: .day, value: 1, to: oggi) ?? oggi.addingTimeInterval(86_400)
        let eventi = negozio.events(matching: negozio.predicateForEvents(withStart: oggi, end: domani, calendars: nil))
            .filter { !$0.isAllDay && $0.startDate >= oggi && $0.startDate < domani }
            .sorted { $0.startDate < $1.startDate }
        return eventi.prefix(8).map { e -> [String: Any] in
            let c = cal.dateComponents([.hour, .minute], from: e.startDate)
            return ["m": Double((c.hour ?? 0) * 60 + (c.minute ?? 0)), "nome": e.title ?? ""]
        }
    }
}

/// Il tempo a piedi (Apple Mappe), per l'iniziativa «esci adesso».
enum DatiTravel {
    static func aPiedi(da: CLLocationCoordinate2D, a: CLLocationCoordinate2D) async -> (secondi: Double, metri: Double)? {
        let r = MKDirections.Request()
        r.source = MKMapItem(placemark: MKPlacemark(coordinate: da))
        r.destination = MKMapItem(placemark: MKPlacemark(coordinate: a))
        r.transportType = .walking
        guard let route = try? await MKDirections(request: r).calculate().routes.first else { return nil }
        return (route.expectedTravelTime, route.distance)
    }
}

/// «VEN 21:00» detto: «stasera alle nove», «oggi a mezzogiorno», «domani alle nove», «venerdì alle nove».
enum Sessione {
    static func detto(_ quando: String) -> String {
        guard let o = quando.split(separator: " ").last, o.contains(":") else { return "adesso" }
        let p = o.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return "adesso" }
        let min = p[0] * 60 + p[1]
        let giorni = ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"], nomi = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]
        let oggi = Calendar.current.component(.weekday, from: Date()) - 1
        let g = giorni.firstIndex(of: String(quando.prefix(3))) ?? oggi
        let quale = g == oggi ? (min >= 18 * 60 ? "stasera" : "oggi") : g == (oggi + 1) % 7 ? "domani" : nomi[g]
        return quale + " " + Battute.allOra(min)
    }
}
#endif
