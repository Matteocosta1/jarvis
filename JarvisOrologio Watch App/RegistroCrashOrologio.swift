import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// Il registro dei crash (Sentry): se l'app si chiude da sola o si blocca, il punto esatto del codice finisce su Sentry
/// e si corregge senza dover ricostruire cosa è successo. Nessun contenuto delle conversazioni: solo l'errore e dove.
/// Si accende solo quando il pacchetto Sentry è aggiunto al progetto e la voce SENTRY_DSN è nelle Info del target.
enum RegistroCrashOrologio {
    static func avvia() {
        #if canImport(Sentry)
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String, !dsn.isEmpty else { return }
        SentrySDK.start { o in
            o.dsn = dsn
            o.sendDefaultPii = false                 // niente dati personali
            o.tracesSampleRate = 0.1                 // un campione dei tempi, per vedere dove l'app è lenta
        }
        #endif
    }
}
