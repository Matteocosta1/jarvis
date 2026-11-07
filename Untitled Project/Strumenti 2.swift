import Foundation
import EventKit
import Contacts
import UIKit
import CoreLocation
import AVFoundation

/// Gli strumenti che il cervello chiede di eseguire sull'iPhone.
/// Ogni strumento restituisce un testo (di solito JSON) per il cervello e un flag di errore.
@MainActor
final class Strumenti {
    /// Gli strumenti di questo dispositivo; sul Mac in più «mac_comando» (il Comando rapido «JARVIS Mac»).
    static var nomi: [String] { ProcessInfo.processInfo.isiOSAppOnMac ? nomiBase + ["mac_comando"] : nomiBase }
    private static let nomiBase = ["calendario_crea", "calendario_leggi", "promemoria_crea", "contatti_cerca", "chiama", "messaggio", "naviga",
                       "invia_messaggio", "riconosci_musica", "apri_apple_music", "foto_cerca", "apri_pagina",
                       "musica_riproduci", "musica_controllo", "meteo_qui", "salute_riepilogo", "conversazione_pulisci", "guarda", "interprete_avvia",
                       "telefono_torcia", "telefono_luminosita", "telefono_batteria", "telefono_comando", "comando_app"]

    /// Nome del Comando rapido che invia SMS e iMessage senza conferma.
    static let comandoInvio = "JARVIS invia"

    static func descrizione(_ nome: String) -> String {
        switch nome {
        case "calendario_crea": return "segno in calendario"
        case "calendario_leggi": return "guardo il calendario"
        case "promemoria_crea": return "creo il promemoria"
        case "contatti_cerca": return "cerco in rubrica"
        case "chiama": return "preparo la chiamata"
        case "messaggio": return "preparo il messaggio"
        case "naviga": return "preparo il percorso"
        case "invia_messaggio": return "invio il messaggio"
        case "riconosci_musica": return "ascolto la musica"
        case "apri_apple_music": return "preparo Apple Music"
        case "foto_cerca": return "cerco tra le sue foto"
        case "apri_pagina": return "apro la pagina"
        case "musica_riproduci": return "metto la musica"
        case "musica_controllo": return "un attimo"
        case "meteo_qui": return "guardo il cielo"
        case "salute_riepilogo": return "guardo l'app Salute"
        case "conversazione_pulisci": return "faccio pulizia"
        case "guarda": return "guardo"
        case "interprete_avvia": return "preparo l'interprete"
        case "telefono_torcia": return "torcia"
        case "telefono_luminosita": return "regolo lo schermo"
        case "telefono_batteria": return "controllo la batteria"
        case "telefono_comando": return "comando il telefono"
        case "comando_app": return "subito"
        case "mac_comando": return "comando il Mac"
        default: return "un attimo"
        }
    }

    private let eventi = EKEventStore()
    private let rubrica = CNContactStore()
    /// App da aprire (telefono, Messaggi, WhatsApp, Mappe): si aprono quando JARVIS ha finito di parlare,
    /// così la risposta non viene tagliata dal passaggio all'altra app.
    private var daAprire: [URL] = []
    /// Immagini trovate dagli strumenti (copertina di Shazam, foto della galleria): Jarvis le mette sotto la risposta.
    private var immaginiNuove: [Immagine] = []
    /// Pagina web da aprire nel browser interno (la imposta Jarvis).
    var apriPagina: ((URL) -> Void)?
    /// «Jarvis, cancella la conversazione»: la chat si pulisce appena JARVIS ha finito di rispondere.
    var pulireChat = false
    /// Gli occhi di JARVIS: apre la fotocamera (automatica o manuale; foto o giro) e restituisce le foto, vuoto se chiusa.
    var apriOcchi: ((Bool, Bool, Double) async -> [Data])?
    /// La frase che il signore ha detto mentre la fotocamera era aperta (lo scatto è partito a voce).
    var domandaOcchi: (() -> String?)?
    /// Le foto scattate da «guarda» (una, o i fotogrammi del giro): Jarvis le allega al risultato, così il cervello le vede.
    private var fotoOcchi: [Data] = []
    /// «Jarvis, traduci in spagnolo»: la lingua dell'interprete da aprire appena JARVIS ha finito di parlare.
    var interpreteDaAprire: Lingua?
    /// Un comando dell'app capito dal cervello in una frase storpiata («rito» o un reparto): parte appena JARVIS ha finito di parlare.
    var comandoDaEseguire: String?

    func prendiFotoOcchi() -> [Data] {
        defer { fotoOcchi = [] }
        return fotoOcchi
    }

    func prendiImmagini() -> [Immagine] {
        defer { immaginiNuove.removeAll() }
        return immaginiNuove
    }

    func apriInSospeso() {
        guard let url = daAprire.first else { return }
        daAprire.removeAll()
        UIApplication.shared.open(url)
    }

    func annullaInSospeso() { daAprire.removeAll(); comandoDaEseguire = nil }

    // MARK: Permessi
    // Versioni a callback con chiusura @Sendable: i callback arrivano su un thread qualsiasi e non devono
    // ereditare il MainActor (crash in Swift 6); niente invio di EKEventStore/CNContactStore fuori dal MainActor.

    private func accessoEventi(promemoria: Bool) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let fine: @Sendable (Bool, (any Error)?) -> Void = { ok, _ in c.resume(returning: ok) }
            if promemoria { eventi.requestFullAccessToReminders(completion: fine) }
            else { eventi.requestFullAccessToEvents(completion: fine) }
        }
    }

    private func accessoRubrica() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            rubrica.requestAccess(for: .contacts) { @Sendable ok, _ in c.resume(returning: ok) }
        }
    }

    func esegui(_ nome: String, _ i: [String: Any]) async -> (String, Bool) {
        do {
            switch nome {
            case "calendario_crea": return (try await calendarioCrea(i), false)
            case "calendario_leggi": return (try await calendarioLeggi(i), false)
            case "promemoria_crea": return (try await promemoriaCrea(i), false)
            case "contatti_cerca": return (try await contattiCerca(i), false)
            case "chiama": return (try chiama(i), false)
            case "messaggio": return (try messaggio(i), false)
            case "naviga": return (try naviga(i), false)
            case "invia_messaggio": return (try inviaMessaggio(i), false)
            case "riconosci_musica": return (await riconosciMusica(i), false)
            case "apri_apple_music": return (try apriAppleMusic(i), false)
            case "foto_cerca": return (try await fotoCerca(i), false)
            case "apri_pagina": return (try apriPaginaWeb(i), false)
            case "musica_riproduci": return await MusicaApple.riproduci(cerca: i["cerca"] as? String ?? "", tipo: i["tipo"] as? String ?? "brano")
            case "musica_controllo": return await MusicaApple.controllo(azione: i["azione"] as? String ?? "")
            case "conversazione_pulisci":
                pulireChat = true
                return (json(["ok": true, "nota": "la chat sullo schermo si pulisce appena hai finito di rispondere; memoria e note restano"]), false)
            case "guarda": return await guarda(video: (i["video"] as? Bool) ?? false, zoom: (i["zoom"] as? NSNumber)?.doubleValue ?? 1)
            case "interprete_avvia":
                guard let l = Lingua.trova(i["lingua"] as? String ?? "") else {
                    return (json(["errore": "lingua non disponibile; scegli tra: \(Lingua.tutte.map(\.codice).joined(separator: ", "))"]), true)
                }
                interpreteDaAprire = l
                return (json(["ok": true, "nota": "l'interprete per \(l.nome) si apre appena hai finito di parlare: di' solo una frase breve"]), false)
            case "salute_riepilogo": return await Benessere.riepilogo(giorni: (i["giorni"] as? NSNumber)?.intValue ?? 2)
            case "meteo_qui": return await MeteoQui.adesso(ore: (i["ore"] as? Int) ?? (i["ore"] as? Double).map { Int($0) } ?? 6)
            case "telefono_torcia": return (try torcia(i), false)
            case "telefono_luminosita": return (try luminosita(i), false)
            case "telefono_batteria": return (batteria(), false)
            case "telefono_comando": return (try comandoTelefono(i), false)
            case "mac_comando": return (try comandoMac(i), false)
            case "comando_app":
                let c = i["comando"] as? String ?? ""
                guard c == "rito" || Reparto(rawValue: c) != nil else { return (json(["errore": "comando sconosciuto"]), true) }
                comandoDaEseguire = c
                return (json(["ok": true, "nota": c == "rito"
                    ? "il rito parte appena hai finito di parlare (i Clash e poi il saluto): rispondi soltanto «Subito, Sir.»"
                    : "la sezione si apre appena hai finito di parlare: rispondi con una frase brevissima"]), false)
            default: return (json(["errore": "strumento \(nome) non disponibile sull'iPhone"]), true)
            }
        } catch {
            return (json(["errore": error.localizedDescription]), true)
        }
    }

    // MARK: Calendario e promemoria

    private func calendarioCrea(_ i: [String: Any]) async throws -> String {
        guard await accessoEventi(promemoria: false) else { throw Problema("Il signore non ha dato accesso al calendario.") }
        guard let titolo = i["titolo"] as? String, let inizio = Strumenti.data(i["inizio"]) else { throw Problema("Mancano titolo o data di inizio.") }
        let e = EKEvent(eventStore: eventi)
        e.title = titolo
        e.isAllDay = i["tutto_il_giorno"] as? Bool ?? false
        e.startDate = inizio
        e.endDate = Strumenti.data(i["fine"]) ?? inizio.addingTimeInterval(e.isAllDay ? 86_400 : 3_600)
        e.location = i["luogo"] as? String
        e.notes = i["note"] as? String
        e.calendar = eventi.defaultCalendarForNewEvents
        try eventi.save(e, span: .thisEvent, commit: true)
        return json(["ok": true, "creato": titolo, "quando": Strumenti.leggibile(inizio)])
    }

    private func calendarioLeggi(_ i: [String: Any]) async throws -> String {
        guard await accessoEventi(promemoria: false) else { throw Problema("Il signore non ha dato accesso al calendario.") }
        let da = Strumenti.data(i["da"]) ?? Calendar.current.startOfDay(for: Date())
        let a = Strumenti.data(i["a"]) ?? da.addingTimeInterval(86_400)
        let trovati = eventi.events(matching: eventi.predicateForEvents(withStart: da, end: a, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .prefix(30)
            .map { e -> [String: Any] in
                ["titolo": e.title ?? "", "inizio": e.isAllDay ? "tutto il giorno" : Strumenti.leggibile(e.startDate),
                 "fine": Strumenti.leggibile(e.endDate), "luogo": e.location ?? ""]
            }
        return json(["eventi": Array(trovati)])
    }

    private func promemoriaCrea(_ i: [String: Any]) async throws -> String {
        guard await accessoEventi(promemoria: true) else { throw Problema("Il signore non ha dato accesso ai Promemoria.") }
        guard let titolo = i["titolo"] as? String else { throw Problema("Manca il titolo.") }
        let r = EKReminder(eventStore: eventi)
        r.title = titolo
        r.notes = i["note"] as? String
        guard let lista = eventi.defaultCalendarForNewReminders() else { throw Problema("Nessuna lista Promemoria predefinita.") }
        r.calendar = lista
        var quando = "senza orario"
        if let d = Strumenti.data(i["quando"]) {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            r.addAlarm(EKAlarm(absoluteDate: d))
            quando = Strumenti.leggibile(d)
        }
        try eventi.save(r, commit: true)
        return json(["ok": true, "creato": titolo, "avviso": quando])
    }

    // MARK: Rubrica, chiamate, messaggi, mappe

    private func contattiCerca(_ i: [String: Any]) async throws -> String {
        guard await accessoRubrica() else { throw Problema("Il signore non ha dato accesso alla rubrica.") }
        guard let nome = i["nome"] as? String, !nome.isEmpty else { throw Problema("Manca il nome da cercare.") }
        let chiavi = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let trovati = try rubrica.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: nome), keysToFetch: chiavi)
            .prefix(5)
            .map { c -> [String: Any] in
                var nomeCompleto = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                if !c.nickname.isEmpty { nomeCompleto += " («\(c.nickname)»)" }
                let numeri: [[String: String]] = c.phoneNumbers.map { n in
                    let etichetta = n.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
                    return ["etichetta": etichetta, "numero": n.value.stringValue]
                }
                return ["nome": nomeCompleto, "numeri": numeri]
            }
        return json(["contatti": Array(trovati)])
    }

    private func chiama(_ i: [String: Any]) throws -> String {
        let numero = Strumenti.pulisci(i["numero"] as? String ?? "")
        guard !numero.isEmpty, let url = URL(string: "tel://\(numero)") else { throw Problema("Numero non valido.") }
        daAprire.append(url)
        return json(["ok": true, "nota": "la chiamata parte quando hai finito di parlare; l'iPhone chiede conferma"])
    }

    private func messaggio(_ i: [String: Any]) throws -> String {
        let numero = Strumenti.pulisci(i["numero"] as? String ?? "")
        let testo = Strumenti.codifica(i["testo"] as? String ?? "")
        guard !numero.isEmpty else { throw Problema("Numero non valido.") }
        let whatsapp = (i["app"] as? String) == "whatsapp"
        let indirizzo = whatsapp
            ? "https://wa.me/\(numero.replacingOccurrences(of: "+", with: ""))?text=\(testo)"
            : "sms:\(numero)&body=\(testo)"
        guard let url = URL(string: indirizzo) else { throw Problema("Non riesco a preparare il messaggio.") }
        daAprire.append(url)
        let testoVero = i["testo"] as? String ?? ""                        // 7 nov: anche questo nell'ologramma di Messaggi
        Task { await RegistroMessaggi.mandato(a: numero, testo: testoVero, whatsapp: whatsapp) }
        return json(["ok": true, "nota": "il messaggio si apre pronto in \(whatsapp ? "WhatsApp" : "Messaggi") quando hai finito di parlare: lo invia il signore"])
    }

    private func naviga(_ i: [String: Any]) throws -> String {
        guard let dest = i["destinazione"] as? String, !dest.isEmpty else { throw Problema("Manca la destinazione.") }
        let flag = ["auto": "d", "piedi": "w", "mezzi": "r"][i["mezzo"] as? String ?? "auto"] ?? "d"
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(Strumenti.codifica(dest))&dirflg=\(flag)") else { throw Problema("Destinazione non valida.") }
        daAprire.append(url)
        return json(["ok": true, "nota": "Mappe si apre con il percorso quando hai finito di parlare"])
    }

    // MARK: Messaggi automatici (Comando rapido «JARVIS Invia»)

    private func inviaMessaggio(_ i: [String: Any]) throws -> String {
        let numero = Strumenti.pulisci(i["numero"] as? String ?? "")
        let testo = (i["testo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numero.isEmpty else { throw Problema("Numero non valido.") }
        guard !testo.isEmpty else { throw Problema("Manca il testo del messaggio.") }
        let dati = try JSONSerialization.data(withJSONObject: ["numero": numero, "testo": testo])
        let ingresso = Strumenti.codifica(String(decoding: dati, as: UTF8.self))
        guard let url = URL(string: "shortcuts://run-shortcut?name=\(Strumenti.codifica(Strumenti.comandoInvio))&input=text&text=\(ingresso)") else {
            throw Problema("Non riesco a preparare il messaggio.")
        }
        daAprire.append(url)
        Task { await RegistroMessaggi.mandato(a: numero, testo: testo, whatsapp: false) }   // 7 nov: anche questo nell'ologramma di Messaggi
        return json(["ok": true, "nota": "il Comando rapido «\(Strumenti.comandoInvio)» lo invia appena hai finito di parlare, senza conferma"])
    }

    // MARK: Telefono: torcia, schermo, batteria e i comandi che passano dai Comandi rapidi

    private func torcia(_ i: [String: Any]) throws -> String {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { throw Problema("Questo iPhone non ha la torcia.") }
        let azione = (i["azione"] as? String ?? "accendi").lowercased()
        let accendi = azione == "accendi" || azione == "on" || azione == "accesa"
        let livello = min(1, max(0.05, (i["livello"] as? Double) ?? (i["livello"] as? Int).map(Double.init) ?? 1))
        try d.lockForConfiguration()
        defer { d.unlockForConfiguration() }
        if accendi { try d.setTorchModeOn(level: Float(livello)) } else { d.torchMode = .off }
        return json(["ok": true, "torcia": accendi ? "accesa" : "spenta", "livello": accendi ? Int(livello * 100) : 0])
    }

    private func luminosita(_ i: [String: Any]) throws -> String {
        guard let v = (i["livello"] as? Double) ?? (i["livello"] as? Int).map(Double.init) else { throw Problema("Manca il livello (0-100).") }
        let livello = min(100, max(0, v))
        UIScreen.main.brightness = livello / 100
        return json(["ok": true, "luminosita": Int(livello)])
    }

    private func batteria() -> String {
        let d = UIDevice.current
        d.isBatteryMonitoringEnabled = true
        let livello = d.batteryLevel < 0 ? nil : Int((d.batteryLevel * 100).rounded())
        let stato: String
        switch d.batteryState {
        case .charging: stato = "in carica"
        case .full: stato = "carica completa"
        case .unplugged: stato = "a batteria"
        default: stato = "sconosciuto"
        }
        var out: [String: Any] = ["stato": stato, "risparmio_energetico": ProcessInfo.processInfo.isLowPowerModeEnabled]
        if let livello { out["percento"] = livello }
        return json(out)
    }

    /// Timer e sveglia: Comando rapido «JARVIS timer» / «JARVIS sveglia» con il valore come input.
    /// Non disturbare, Wi-Fi, Bluetooth: due comandi ciascuno, «JARVIS wifi on» e «JARVIS wifi off», senza input né condizioni.
    private func comandoTelefono(_ i: [String: Any]) throws -> String {
        let comando = (i["comando"] as? String ?? "").lowercased()
        let valore = String(describing: i["valore"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nome: String
        var url: URL?
        switch comando {
        case "timer", "sveglia":
            nome = "JARVIS \(comando)"
            guard !valore.isEmpty else { throw Problema("Manca il valore (\(comando == "timer" ? "minuti" : "ora HH:mm")).") }
            url = URL(string: "shortcuts://run-shortcut?name=\(Strumenti.codifica(nome))&input=text&text=\(Strumenti.codifica(valore))")
        case "non_disturbare", "wifi", "bluetooth":
            let acceso = ["on", "si", "sì", "attiva", "acceso", "true", "1"].contains(valore)
            nome = "JARVIS \(comando == "non_disturbare" ? "non disturbare" : comando) \(acceso ? "on" : "off")"
            url = URL(string: "shortcuts://run-shortcut?name=\(Strumenti.codifica(nome))")
        default:
            throw Problema("Comando sconosciuto: \(comando). Scegli tra timer, sveglia, non_disturbare, wifi, bluetooth.")
        }
        guard let url else { throw Problema("Non riesco a preparare il comando.") }
        daAprire.append(url)
        return json(["ok": true, "nota": "il Comando rapido «\(nome)» parte appena hai finito di parlare; se il signore non l'ha ancora creato, iOS glielo dirà"])
    }

    /// Sul Mac: il Comando rapido «JARVIS Mac» (uno solo, con uno script che conosce solo questi comandi).
    /// Al comando passa un testo tipo «volume 60» o «apri Spotify»; il valore viene ripulito qui e controllato di nuovo nello script.
    private func comandoMac(_ i: [String: Any]) throws -> String {
        guard ProcessInfo.processInfo.isiOSAppOnMac else { throw Problema("Questo comando funziona solo sul Mac.") }
        let comando = (i["comando"] as? String ?? "").lowercased()
        let ammessi: Set<String> = ["volume", "muto", "musica", "apri", "cartella", "scura", "blocca", "screenshot",
                                    "riordina_scrivania", "ordina_download", "svuota_cestino"]
        guard ammessi.contains(comando) else { throw Problema("Comando sconosciuto: \(comando).") }
        let grezzo = String(describing: i["valore"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let valore = String(grezzo.filter { $0.isLetter || $0.isNumber || " .-_".contains($0) }.prefix(40))
        let testo = valore.isEmpty ? comando : "\(comando) \(valore)"
        guard let url = URL(string: "shortcuts://run-shortcut?name=\(Strumenti.codifica("JARVIS Mac"))&input=text&text=\(Strumenti.codifica(testo))") else {
            throw Problema("Non riesco a preparare il comando.")
        }
        daAprire.append(url)
        return json(["ok": true, "nota": "il Comando rapido «JARVIS Mac» (\(testo)) parte appena hai finito di parlare: rispondi con una frase brevissima"])
    }

    // MARK: Musica (ShazamKit)

    private func riconosciMusica(_ i: [String: Any]) async -> String {
        let secondi = (i["secondi"] as? Double) ?? (i["secondi"] as? Int).map(Double.init) ?? 15
        switch await Musica.riconosci(secondi: secondi) {
        case .trovato(let b):
            immaginiNuove.append(Immagine(titolo: "\(b.artista) – \(b.titolo)", miniatura: b.copertina?.absoluteString,
                                          grande: b.copertina?.absoluteString, pagina: (b.appleMusic ?? b.web)?.absoluteString, fonte: "Shazam"))
            var out: [String: Any] = ["trovato": true, "titolo": b.titolo, "artista": b.artista]
            if let a = b.album { out["album_o_sottotitolo"] = a }
            if let u = b.appleMusic { out["apple_music"] = u.absoluteString }
            if !b.generi.isEmpty { out["generi"] = b.generi }
            return json(out)
        case .nessuno:
            return json(["trovato": false, "nota": "nessun brano riconosciuto: forse la musica è troppo bassa o c'è troppo rumore"])
        case .errore(let e):
            return json(["trovato": false, "errore": e])
        }
    }

    private func apriAppleMusic(_ i: [String: Any]) throws -> String {
        var url: URL?
        if let s = i["url"] as? String, let u = URL(string: s), u.scheme == "https", u.host?.hasSuffix("music.apple.com") == true { url = u }
        if url == nil, let r = i["ricerca"] as? String, !r.isEmpty { url = URL(string: "https://music.apple.com/it/search?term=\(Strumenti.codifica(r))") }
        guard let url else { throw Problema("Mi serve il link di Apple Music o cosa cercare.") }
        daAprire.append(url)
        return json(["ok": true, "nota": "Apple Music si apre quando hai finito di parlare"])
    }

    // MARK: Foto della galleria

    private func fotoCerca(_ i: [String: Any]) async throws -> String {
        guard await FotoLocali.autorizza() else { throw Problema("Il signore non ha dato accesso alle foto: Impostazioni › Jarvis › Foto.") }
        var luogo: CLLocation?
        if let nome = i["luogo"] as? String, !nome.isEmpty {
            let trovati = try? await CLGeocoder().geocodeAddressString(nome)
            guard let pos = trovati?.first?.location else { throw Problema("Non trovo il luogo «\(nome)».") }
            luogo = pos
        }
        let cosa: [String] = (i["cosa"] as? [String]) ?? ((i["cosa"] as? String).map { $0.components(separatedBy: ",") } ?? [])
        let quante = (i["quante"] as? Int) ?? (i["quante"] as? Double).map { Int($0) } ?? 12
        let esito = await FotoLocali.cerca(cosa: cosa, da: Strumenti.data(i["da"]), a: Strumenti.data(i["a"]), luogo: luogo,
                                           raggioKm: 5, album: i["album"] as? String, quante: quante)
        immaginiNuove.append(contentsOf: esito.trovate.map { Immagine(fonte: "Le sue foto", locale: $0) })
        var out: [String: Any] = ["trovate": esito.trovate.count, "foto": esito.righe, "esaminate": esito.esaminate,
                                  "nota_per_te": "le foto trovate sono già sullo schermo del signore"]
        if let n = esito.nota { out["nota"] = n }
        return json(out)
    }

    // MARK: Occhi (fotocamera)

    private func guarda(video: Bool, zoom: Double = 1) async -> (String, Bool) {
        guard let apri = apriOcchi else { return (json(["errore": "fotocamera non disponibile"]), true) }
        let foto = await apri(true, video, min(max(zoom, 0.5), 15))
        guard !foto.isEmpty else {
            return (json(["visto": false, "nota": "il signore ha chiuso la fotocamera o non ha dato il permesso: nessuna foto"]), false)
        }
        fotoOcchi = foto
        if let detta = domandaOcchi?() {
            return (json(["visto": true, "il_signore_ha_detto": detta,
                          "nota": "la foto appena scattata è allegata qui: il signore l'ha scattata a voce dicendo la frase in il_signore_ha_detto; rispondi a quella"]), false)
        }
        if foto.count > 1 {
            return (json(["visto": true, "fotogrammi": foto.count,
                          "nota": "qui sono allegati \(foto.count) fotogrammi in ordine di tempo, presi durante un giro di 5 secondi mentre il signore muoveva il telefono: è una sola scena, mettili insieme e rispondi"]), false)
        }
        return (json(["visto": true, "nota": "la foto appena scattata dalla fotocamera posteriore è allegata qui: guardala e rispondi al signore"]), false)
    }

    // MARK: Browser interno

    private func apriPaginaWeb(_ i: [String: Any]) throws -> String {
        guard var s = (i["url"] as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { throw Problema("Manca l'indirizzo.") }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), url.scheme == "https" || url.scheme == "http" else { throw Problema("Indirizzo non valido.") }
        apriPagina?(url)
        return json(["ok": true, "nota": "la pagina è aperta nel browser dell'app"])
    }

    // MARK: Utilità

    struct Problema: LocalizedError {
        let messaggio: String
        init(_ m: String) { messaggio = m }
        nonisolated var errorDescription: String? { messaggio }
    }

    private func json(_ o: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    static func data(_ valore: Any?) -> Date? {
        guard let s = valore as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let solo = DateFormatter()
        solo.locale = Locale(identifier: "en_US_POSIX")
        solo.timeZone = .current
        for formato in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            solo.dateFormat = formato
            if let d = solo.date(from: s) { return d }
        }
        return nil
    }

    static func leggibile(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "EEEE d MMMM, HH:mm"
        return f.string(from: d)
    }

    static func pulisci(_ numero: String) -> String {
        numero.filter { $0.isNumber || $0 == "+" }
    }

    static func codifica(_ testo: String) -> String {
        // solo ASCII non riservato: lettere accentate, spazi, & e + vengono codificati
        let ammessi = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return testo.addingPercentEncoding(withAllowedCharacters: ammessi) ?? ""
    }
}
