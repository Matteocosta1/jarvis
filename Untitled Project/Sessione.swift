#if os(iOS)
import Foundation
import Combine
import Photos
import UIKit

// MARK: - 12.0 (16) · LAVORARE INSIEME
// Il signore (13 nov sera): «in una sessione come "progettiamo…" JARVIS propone, mostra, ascolta le correzioni e rifà, senza perdere
// il filo, finché lei non chiude». Qui il lavoro insieme sul post di Instagram, dentro Social › PUBBLICA (la pagina del mockup
// nell'app): «Progettiamo il post di stasera» porta davanti PUBBLICA con l'ultima foto della galleria, il formato POST e stasera
// alle nove; la prima idea la scrive il cervello (vede la SESSIONE nella riga [Schermo]) con la regia di Social, e ogni didascalia
// nuova è una versione. «Più corto», «togli l'hashtag», «rifallo più ironico»: riscrive il cervello; «torna alla versione di prima»,
// «ok salvalo», «lascia stare»: l'app. Pubblicare (o programmare) solo col sì. Niente riga INSIEME (il signore, 13 nov: «non la
// voglio»): la didascalia cambiata si accende un attimo, come nel mockup 12.0 (16).

@MainActor
final class Sessione: ObservableObject {
    static let condivisa = Sessione()

    struct Versione: Equatable {
        var didascalia: String
        var formato: String
        var quando: String
        var nota: String
    }

    /// Lo stato del compositore di Social, come lo manda la pagina (messaggio «socStato»).
    struct StatoSocial: Equatable {
        var aperta = false
        var scheda = ""
        var formato = ""
        var quando = ""
        var didascalia = ""
        var foto = false
    }

    /// «post» mentre si lavora insieme; nil: nessun lavoro aperto.
    @Published private(set) var tema: String?
    @Published private(set) var versioni: [Versione] = []
    @Published private(set) var indice = -1
    /// L'ultimo post salvato (pronto da pubblicare col sì).
    @Published private(set) var bozza: Versione?
    @Published var social = StatoSocial()

    var aperta: Bool { tema != nil }
    var versione: Versione? { versioni.indices.contains(indice) ? versioni[indice] : nil }

    // MARK: Il lavoro

    /// «Progettiamo il post di stasera»: PUBBLICA davanti, l'ultima foto della galleria, POST, stasera alle nove. Fa mentre il
    /// cervello pensa la prima idea.
    func inizia(tema: String) async {
        self.tema = "post"
        versioni = []
        indice = -1
        if !social.aperta {
            PaginaMarkX.apri(AperturaPagina(sezione: "Social", scheda: "PUBBLICA"))
        } else {
            js("window.__jarvisSoc && window.__jarvisSoc.tocca('[data-sc=\"pubblica\"]')")
        }
        // la pagina pronta (al massimo 6 s), poi la foto, il formato e l'ora
        for _ in 0..<60 where !(social.aperta && social.scheda == "pubblica") { try? await Task.sleep(for: .milliseconds(100)) }
        guard aperta else { return }
        if !social.foto, await FotoLocali.autorizza(), let id = Sessione.idUltimaFoto(),
           let img = await FotoLocali.immagine(id: id, lato: 1600), let jpg = img.jpegData(compressionQuality: 0.88) {
            js("(function(){var im=new Image();im.onload=function(){window.__socFonte&&window.__socFonte(im,'galleria',false);};im.src='data:image/jpeg;base64,\(jpg.base64EncodedString())';})()")
            try? await Task.sleep(for: .milliseconds(250))
        }
        js("window.__jarvisSoc && (window.__jarvisSoc.tocca('[data-formato=\"POST\"]'), window.__jarvisSoc.quando(\(RegiaStudio.js(Sessione.stasera(21 * 60)))))")
        Filo.condiviso.metti(CosaFilo(chiave: "post", tipo: "post", nomi: ["post", "bozza", "didascalia"], titolo: "Post", riga: "in preparazione",
                                      detto: "il post di stasera", sezione: "Social"))
    }

    /// Una didascalia nuova scritta da JARVIS (la regia di Social): con il lavoro aperto è una versione nuova.
    func nuova(didascalia: String, nota: String?) {
        let t = didascalia.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        js("window.__jarvisSoc && window.__jarvisSoc.dida(\(RegiaStudio.js(t)), true)")
        guard aperta else { return }
        let base = versione ?? Versione(didascalia: "", formato: social.formato.isEmpty ? "POST" : social.formato,
                                        quando: social.quando.isEmpty ? Sessione.stasera(21 * 60) : social.quando, nota: "")
        if indice < versioni.count - 1 { versioni.removeSubrange((indice + 1)...) }   // dopo «torna indietro» si riparte da lì
        versioni.append(Versione(didascalia: t, formato: social.formato.isEmpty ? base.formato : social.formato,
                                 quando: social.quando.isEmpty ? base.quando : social.quando,
                                 nota: nota ?? (versioni.isEmpty ? "prima idea" : "versione \(versioni.count + 1)")))
        indice = versioni.count - 1
        segnaNelFilo()
    }

    /// «Torna alla versione di prima» (o «la prima era meglio»).
    func indietro(allaPrima: Bool) async -> String {
        guard aperta, indice > 0 else { return versioni.isEmpty ? "Non c'è ancora una versione, Sir." : "Questa è già la prima, Sir." }
        indice = allaPrima ? 0 : indice - 1
        guard let v = versione else { return Battute.lampo() }
        js("window.__jarvisSoc && (window.__jarvisSoc.dida(\(RegiaStudio.js(v.didascalia)), true), window.__jarvisSoc.tocca('[data-formato=\"\(v.formato)\"]'), window.__jarvisSoc.quando(\(RegiaStudio.js(v.quando))))")
        segnaNelFilo()
        return allaPrima ? "Torniamo alla prima, Sir." : "Torniamo alla versione \(Battute.numero(indice + 1)), Sir."
    }

    /// «Ok salvalo», «va bene così»: il lavoro si chiude, la bozza resta pronta (esce solo col sì).
    func salva() -> String {
        guard let v = versione ?? (social.didascalia.isEmpty ? nil : Versione(didascalia: social.didascalia, formato: social.formato, quando: social.quando, nota: "")) else {
            chiudi(salva: false)
            return "Non c'è ancora niente da salvare, Sir."
        }
        bozza = v
        chiudi(salva: true)
        Congedo.condiviso.cosaVera()                                    // un lavoro chiuso è una cosa vera
        if Battute.diFretta { return "Salvato." }
        let ora = Sessione.minuti(v.quando)
        return ora.map { "Salvato, Sir: pronto per stasera \(Battute.allOra($0)). Esce solo col suo sì." } ?? "Salvato tra le bozze, Sir: esce solo col suo sì."
    }

    func chiudi(salva: Bool) {
        if !salva, let v = versione { bozza = bozza ?? v }                // «lascia stare»: la bozza resta lì se cambia idea
        tema = nil
        versioni = []
        indice = -1
    }

    /// Il sì è arrivato: pubblica adesso o programma (nella pagina, come il tasto PUBBLICA › SÌ).
    func pubblica(alle: String?, ora: Bool) async -> String? {
        if aperta { _ = salva() }
        guard social.aperta else {
            PaginaMarkX.apri(AperturaPagina(sezione: "Social", scheda: "PUBBLICA"))
            for _ in 0..<60 where !social.aperta { try? await Task.sleep(for: .milliseconds(100)) }
            guard social.aperta else { return "Instagram non si apre, Sir." }
            return await pubblica(alle: alle, ora: ora)
        }
        if let b = bozza, social.didascalia != b.didascalia { js("window.__jarvisSoc && window.__jarvisSoc.dida(\(RegiaStudio.js(b.didascalia)), false)") }
        js("window.__jarvisSoc && window.__jarvisSoc.quando(\(RegiaStudio.js(ora ? "ORA" : (alle ?? bozza?.quando ?? Sessione.stasera(21 * 60)))))")
        try? await Task.sleep(for: .milliseconds(120))
        js("window.__jarvisSoc && window.__jarvisSoc.pubblica()")
        bozza = nil
        return ""                                                        // la pagina dice «Pubblicato» o «Programmato…» con la sua voce
    }

    // MARK: Per il cervello

    /// La riga SESSIONE dentro [Schermo]: il lavoro aperto, la versione e cosa c'è adesso.
    func perCervello() -> String? {
        guard aperta else {
            guard let b = bozza else { return nil }
            return "POST IN BOZZA (salvato, esce solo col sì): «\(b.didascalia.prefix(300))», \(b.formato), \(b.quando)"
        }
        let v = versione
        let quale = v.map { "versione \(indice + 1) di \(versioni.count): «\($0.didascalia.prefix(600))» (\($0.formato), \($0.quando))" } ?? "ancora nessuna versione: proponi tu la prima"
        return "SESSIONE APERTA, LAVORATE INSIEME AL POST DI INSTAGRAM (Social › PUBBLICA): \(quale). Proponi e correggi scrivendo la didascalia INTERA con la regia «Social · didascalia» (ogni volta una versione nuova; in «nota» due parole su cosa cambia), poi di' in una riga cosa hai fatto. Formato e ora con «formato» e «quando». «Torna indietro», «salvalo», «lascia stare» e il sì per pubblicare li fa l'app: tu non pubblichi."
    }

    /// Le azioni di Social per la regia (la pagina di Instagram dell'app).
    func azioniSocial() -> [AzioneRegia] {
        [
            AzioneRegia("didascalia", "scrive la didascalia intera (nel lavoro insieme: una versione nuova; nota: cosa cambia)", valore: "testo") { [weak self] v in
                guard let self else { return .no("non pronta") }
                let t = (v["testo"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return .no("didascalia vuota") }
                self.nuova(didascalia: t, nota: v["nota"])
                return .fatto("didascalia scritta" + (self.aperta ? " (versione \(self.indice + 1))" : ""))
            },
            AzioneRegia("formato", "POST, REEL o STORIA", valore: "nome") { [weak self] v in
                let f = (v["nome"] ?? "").uppercased()
                guard ["POST", "REEL", "STORIA"].contains(f) else { return .no("formato: POST, REEL o STORIA") }
                self?.js("window.__jarvisSoc && window.__jarvisSoc.tocca('[data-formato=\"\(f)\"]')")
                return .fatto("formato \(f)")
            },
            AzioneRegia("quando", "ORA, oppure giorno e ora come «VEN 21:00»", valore: "quando") { [weak self] v in
                let q = (v["quando"] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { return .no("quando: ORA o «VEN 21:00»") }
                self?.js("window.__jarvisSoc && window.__jarvisSoc.quando(\(RegiaStudio.js(q)))")
                return .fatto("esce \(q)")
            },
            AzioneRegia("scheda", "PUBBLICA, POSTA, GRIGLIA, PIANO, REPORT, ORARI, RIVALI, AUTOMAZIONI", valore: "nome") { [weak self] v in
                let k = Regia.chiave(v["nome"] ?? "")
                guard !k.isEmpty else { return .no("quale scheda?") }
                self?.js("window.__jarvisSoc && window.__jarvisSoc.tocca('[data-sc=\"\(k)\"]')")
                return .fatto("scheda \(k)")
            },
            AzioneRegia("foto", "fa scegliere la foto dalla galleria (la sceglie il signore)") { [weak self] _ in
                self?.js("window.__jarvisSoc && window.__jarvisSoc.tocca('[data-fonte=\"galleria\"]', true)")
                return .fatto("la galleria è aperta: la foto la sceglie il signore")
            },
            AzioneRegia("pubblica", "pubblica (o programma, se c'è l'ora) il post così com'è", conferma: true) { [weak self] _ in
                guard let self else { return .no("non pronta") }
                _ = await self.pubblica(alle: nil, ora: self.social.quando == "ORA")
                return .fatto("pubblicato o programmato come da PUBBLICA")
            },
        ]
    }

    /// Cosa mostra Social per la regia (una riga).
    var statoSocial: String {
        guard social.aperta else { return "" }
        var r = ["scheda \(social.scheda.uppercased())"]
        if social.scheda == "pubblica" {
            r.append("formato \(social.formato.isEmpty ? "—" : social.formato)")
            r.append("esce \(social.quando.isEmpty ? "—" : social.quando)")
            r.append(social.foto ? "foto scelta" : "foto da scegliere")
            r.append(social.didascalia.isEmpty ? "didascalia vuota" : "didascalia: «\(social.didascalia.prefix(500))»")
        }
        return "Social · @kingrusto · " + r.joined(separator: " · ")
    }

    // MARK: Pezzi

    private func segnaNelFilo() {
        guard let v = versione else { return }
        Filo.condiviso.metti(CosaFilo(chiave: "post", tipo: "post", nomi: ["post", "bozza", "didascalia"], titolo: "Post",
                                      riga: Filo.primaFrase(v.didascalia), detto: "il post di stasera",
                                      daMandare: v.didascalia.replacingOccurrences(of: "\n", with: " "), sezione: "Social"))
    }

    private func js(_ codice: String) { PaginaMarkX.esegui?(codice) }

    /// «VEN 21:00»: il giorno di oggi e l'ora (in minuti), come le chip QUANDO della pagina.
    static func stasera(_ minuti: Int) -> String {
        let giorni = ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"]
        let g = giorni[(Calendar.current.component(.weekday, from: Date()) - 1) % 7]
        return "\(g) " + String(format: "%02d:%02d", minuti / 60, minuti % 60)
    }
    /// L'ora detta dopo «programmalo alle…» («nove», «21», «nove e mezza», «le 18:30») → «VEN 21:00»; oggi, o domani se è già
    /// passata. Fino alle 11 senza «mattina» vale la sera («alle nove» è stasera). Nil: niente ora capita.
    static func quando(detto: String?) -> String? {
        guard let d = detto?.lowercased(), !d.isEmpty else { return nil }
        let parole = ["una": 1, "l una": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9,
                      "dieci": 10, "undici": 11, "dodici": 12, "mezzogiorno": 12, "mezzanotte": 0]
        let pulito = d.replacingOccurrences(of: "'", with: " ").replacingOccurrences(of: ".", with: ":")
        var h: Int?, m = 0
        let numeri = pulito.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if let primo = numeri.first, primo <= 24 {
            h = primo
            if numeri.count > 1, numeri[1] < 60 { m = numeri[1] }
        } else {
            for (p, v) in parole.sorted(by: { $0.key.count > $1.key.count }) where pulito.hasPrefix(p) || pulito.hasPrefix("le " + p) || pulito.hasPrefix("l " + p) {
                h = v; break
            }
        }
        guard var ora = h else { return nil }
        if pulito.contains("mezza") || pulito.contains("trenta") { m = 30 } else if pulito.contains("un quarto") || pulito.contains("quindici") { m = m == 0 ? 15 : m }
        if ora < 12, ora > 0, !pulito.contains("mattin") { ora += 12 }
        if ora == 24 { ora = 0 }
        let minuti = ora * 60 + m
        let adesso = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let passato = minuti <= (adesso.hour ?? 0) * 60 + (adesso.minute ?? 0)
        let giorni = ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"]
        let g = giorni[(Calendar.current.component(.weekday, from: Date()) - 1 + (passato ? 1 : 0)) % 7]
        return "\(g) " + String(format: "%02d:%02d", ora, m)
    }

    /// «VEN 21:00» detto: «stasera alle nove», «oggi a mezzogiorno», «domani alle nove», «venerdì alle nove».
    static func detto(_ quando: String) -> String {
        guard let min = minuti(quando) else { return "adesso" }
        let giorni = ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"], nomi = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]
        let oggi = Calendar.current.component(.weekday, from: Date()) - 1
        let g = giorni.firstIndex(of: String(quando.prefix(3))) ?? oggi
        let quale = g == oggi ? (min >= 18 * 60 ? "stasera" : "oggi") : g == (oggi + 1) % 7 ? "domani" : nomi[g]
        return quale + " " + Battute.allOra(min)
    }

    /// «VEN 21:00» → 1260; «ORA» → nil.
    static func minuti(_ quando: String) -> Int? {
        guard let o = quando.split(separator: " ").last, o.contains(":") else { return nil }
        let p = o.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : nil
    }

    nonisolated private static func idUltimaFoto() -> String? {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        o.fetchLimit = 1
        return PHAsset.fetchAssets(with: o).firstObject?.localIdentifier
    }
}
#endif
