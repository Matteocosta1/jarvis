// 12 nov (P7, revisione del dialogo): le prove delle regole di fine frase e dell'intonazione, a ogni controllo di compilazione.
// Si compila insieme a «Untitled Project/DialogoVivo.swift» (solo testo e numeri: niente iPhone, niente microfono) e fallisce
// se una regola cambia senza volerlo. Avrebbe preso l'errore del «sì sì» (12 nov: 2,4 secondi invece di 0,6).
import Foundation

@main
struct ProvaDialogo {
    nonisolated(unsafe) static var errori = 0

    static func controlla(_ ok: Bool, _ nome: String) {
        print(ok ? "✓ \(nome)" : "✗ \(nome)")
        if !ok { errori += 1 }
    }

    static func main() {
        provaPause()
        provaEsitazioni()
        provaSegnali()
        provaConVoce()
        provaIntonazione()
        provaRichiami()
        provaRiprese()
        provaResto()
        provaComposti()
        print(errori == 0 ? "\nTutte le prove del dialogo superate." : "\n\(errori) prove del dialogo NON superate.")
        exit(errori == 0 ? 0 : 1)
    }

    static func provaPause() {
        let nomi = FineFrase.nomiJarvis
        let casi: [(String, Double)] = [
            ("sì sì", 0.6), ("no no", 0.6), ("ok ok", 0.6), ("grazie grazie", 0.6), ("sì", 0.6), ("va bene", 0.6), ("sì, mandala pure", 0.6),
            ("Che ore sono?", 0.7), ("Perché?", 0.7), ("che ore sono", 1.2), ("Gli ho detto che", 2.4), ("ci sono ancora delle delle", 2.4),
            ("apri il meteo", 0.9), ("Jarvis, apri il meteo", 0.9), ("oggi sono stato a Bari", 1.8), ("fammi pensare", 2.4),
            ("ciao ciao", 1.2), ("piano piano", 1.2), ("No, aspetta", 2.4), ("che tempo fa domani", 0.8), ("allora,", 2.4),
        ]
        for (frase, attesa) in casi {
            let p = FineFrase.pausa(frase, nomi: nomi)
            controlla(abs(p - attesa) < 0.001, "pausa «\(frase)» = \(p) s (attesa \(attesa))")
        }
    }

    static func provaEsitazioni() {
        let casi: [(String, Int)] = [("ehm cioè volevo dire che che", 3), ("sì sì certo", 0), ("il il problema è questo", 1), ("no no", 0),
                                     ("piano piano arriviamo", 0), ("tipo boh", 2)]
        for (frase, attese) in casi {
            let n = FineFrase.esitazioni(frase)
            controlla(n == attese, "esitazioni «\(frase)» = \(n) (attese \(attese))")
        }
    }

    static func provaSegnali() {
        let casi: [(String, FineFrase.SegnaleAscolto)] = [
            ("sì", .ascolto), ("sì sì", .ascolto), ("mh", .ascolto), ("ah ok", .ascolto), ("va bene", .ascolto), ("certo certo", .ascolto),
            ("esatto", .ascolto), ("sì sì sì", .chiusura), ("ho capito", .chiusura), ("ok grazie", .chiusura), ("va bene va bene", .chiusura),
            ("sì ma domani", .nessuno), ("no", .nessuno), ("aspetta", .nessuno), ("Jarvis", .nessuno),
        ]
        for (frase, atteso) in casi {
            let s = FineFrase.segnaleDAscolto(frase)
            controlla(s == atteso, "segnale d'ascolto «\(frase)» = \(s) (atteso \(atteso))")
        }
    }

    static func provaConVoce() {
        let casi: [(Double, Double, Int, Intonazione.Fine, Double)] = [
            (1.2, 1, 0, .scende, 0.84), (1.2, 1, 0, .sospesa, 1.5), (1.2, 1, 0, .incerta, 1.2), (0.6, 1, 0, .sospesa, 0.6),
            (0.7, 1, 0, .scende, 0.7), (2.4, 1, 0, .scende, 2.4), (1.8, 1, 2, .incerta, 2.34), (1.8, 1, 2, .sospesa, 2.6),
            (0.9, 1, 0, .scende, 0.63), (0.8, 1, 0, .scende, 0.6),
        ]
        for (lessicale, ritmo, esitazioni, fine, attesa) in casi {
            let p = FineFrase.conVoce(lessicale: lessicale, ritmo: ritmo, esitazioni: esitazioni, fine: fine)
            controlla(abs(p - attesa) < 0.001, "pausa con voce \(lessicale) s, \(fine), esitazioni \(esitazioni) = \(p) (attesa \(attesa))")
        }
    }

    /// Una voce finta: armoniche (1/k) con l'altezza che segue `f0(t)`, un filo di rumore; a pezzi da 1024 campioni a 48 kHz.
    static func voce(_ into: Intonazione, durata: Double, inizio: Double, f0: (Double) -> Double) -> Double {
        let hz = 48_000.0
        let n = Int(durata * hz)
        var fase = 0.0
        var pezzo = [Float](repeating: 0, count: 1024)
        var k = 0, t = inizio
        var rumore: UInt64 = 0x9E37_79B9_7F4A_7C15
        while k < n {
            let quanti = min(1024, n - k)
            for i in 0..<quanti {
                let tempo = Double(k + i) / hz
                fase += 2 * Double.pi * f0(tempo) / hz
                var s = 0.0
                for armonica in 1...8 { s += sin(fase * Double(armonica)) / Double(armonica) }
                rumore = rumore &* 6364136223846793005 &+ 1442695040888963407
                let r = Double(rumore >> 40) / Double(1 << 24) - 0.5
                pezzo[i] = Float(0.15 * s + 0.004 * r)
            }
            t = inizio + Double(k + quanti) / hz
            pezzo.withUnsafeBufferPointer { into.ascolta($0.baseAddress!, n: quanti, hz: hz, voce: true, tempo: t) }
            k += quanti
        }
        return t
    }

    static func provaIntonazione() {
        let into = Intonazione()
        // altezza giusta: 200 Hz = 12 semitoni sopra i 100 Hz; 110 Hz ≈ 1,65
        for (f, atteso) in [(200.0, 12.0), (110.0, 1.65), (300.0, 19.02)] {
            into.azzera()
            let fine = voce(into, durata: 1.0, inizio: 1_000, f0: { _ in f })
            let st = into.misure(ultimi: 5, ora: fine).map(\.st)
            let m = Double(Intonazione.mediana(st))
            controlla(st.count >= 30 && abs(m - atteso) < 0.3, "altezza \(Int(f)) Hz = \(String(format: "%.2f", m)) semitoni (\(st.count) misure, attesi \(atteso))")
        }
        // la voce scende in fondo (frase finita): 130 Hz, poi giù fino a 95 Hz nell'ultimo mezzo secondo
        into.azzera()
        var fine = voce(into, durata: 2.0, inizio: 2_000, f0: { t in t < 1.5 ? 130 + sin(t * 9) : 130 - (t - 1.5) / 0.5 * 35 })
        var g = into.giudizio(ora: fine + 0.3)
        controlla(g.fine == .scende, "voce che scende → \(g.fine) (livello \(g.livello), pendenza \(g.pendenza), \(g.punti) misure)")
        // la voce resta sospesa (vuole continuare): 120 Hz, poi sale a 135 Hz
        into.azzera()
        fine = voce(into, durata: 2.0, inizio: 3_000, f0: { t in t < 1.5 ? 120 + sin(t * 9) : 120 + (t - 1.5) / 0.5 * 15 })
        g = into.giudizio(ora: fine + 0.3)
        controlla(g.fine == .sospesa, "voce che sale → \(g.fine) (livello \(g.livello), pendenza \(g.pendenza), \(g.punti) misure)")
        // voce piatta: sospesa
        into.azzera()
        fine = voce(into, durata: 2.0, inizio: 4_000, f0: { _ in 125 })
        g = into.giudizio(ora: fine + 0.3)
        controlla(g.fine == .sospesa, "voce piatta → \(g.fine) (livello \(g.livello), pendenza \(g.pendenza))")
        // voce sentita troppo tempo fa: incerta (non si decide su una frase vecchia)
        g = into.giudizio(ora: fine + 3)
        controlla(g.fine == .incerta, "voce di 3 secondi fa → \(g.fine)")
        // solo rumore: nessuna misura, incerta
        into.azzera()
        var rumore = [Float](repeating: 0, count: 1024)
        var x: UInt64 = 42
        var t = 5_000.0
        for _ in 0..<100 {
            for i in 0..<1024 { x = x &* 6364136223846793005 &+ 1442695040888963407; rumore[i] = Float(Double(x >> 40) / Double(1 << 24) - 0.5) * 0.2 }
            t += 1024 / 48_000
            rumore.withUnsafeBufferPointer { into.ascolta($0.baseAddress!, n: 1024, hz: 48_000, voce: true, tempo: t) }
        }
        g = into.giudizio(ora: t + 0.2)
        controlla(g.fine == .incerta, "solo rumore → \(g.fine) (\(into.misure(ultimi: 5, ora: t).count) misure)")
    }

    /// 12.0 (10): richiamare JARVIS dopo che ha taciuto («Jarvis?», «ci sei?», «dico a te»; «tu che ne pensi?» va con la frase).
    static func provaRichiami() {
        let casi: [(String, String?)] = [
            ("Jarvis?", ""), ("Jarvis!", ""), ("", nil), ("ci sei?", ""), ("Jarvis, ci sei?", ""), ("ma ci sei o no?", ""),
            ("mi senti?", ""), ("allora?", ""), ("e allora?", ""), ("dico a te", ""), ("sto parlando con te, Jarvis", ""),
            ("sì, dico a te", ""), ("senti, ci sei?", ""), ("rispondi per favore", ""), ("perché non mi rispondi?", ""),
            ("sei lì?", ""), ("pronto?", ""), ("hai sentito cosa ho detto?", ""),
            ("tu che ne pensi?", "tu che ne pensi?"), ("e tu?", "e tu?"), ("Jarvis, secondo te?", "Jarvis, secondo te?"),
            ("Bea, mi passi il sale?", nil), ("allora domani andiamo da Marco", nil), ("sì", nil), ("no", nil), ("ok", nil),
            ("che tempo fa domani", nil), ("ci sono ancora delle cose da fare", nil),
        ]
        for (frase, atteso) in casi {
            let r = FineFrase.richiamoDopoSilenzio(frase)
            controlla(r == atteso, "richiamo dopo il silenzio «\(frase)» = \(r.map { "«\($0)»" } ?? "nessuno") (atteso \(atteso.map { "«\($0)»" } ?? "nessuno"))")
        }
    }

    /// 12.0 (10): «dicevi?», «continua pure», «scusa, vai avanti» riprendono la frase di JARVIS; dopo una sua domanda «vai» è la
    /// risposta; senza «Jarvis» (ascolto libero) valgono solo quelle che parlano della sua frase.
    static func provaRiprese() {
        let casi: [(String, Bool, Bool, Bool)] = [   // frase, dopo una domanda, presa senza nome, attesa
            ("dicevi?", false, false, true), ("scusa, dicevi?", false, false, true), ("continua pure", false, false, true),
            ("continua pure", false, true, false), ("Jarvis, continua", false, false, true), ("scusa, vai avanti", false, false, true),
            ("vai", false, false, true), ("vai", true, false, false), ("vai", false, true, false), ("prego", false, false, true),
            ("prego", true, false, false), ("no niente, continua", false, false, true), ("dove eri rimasto?", false, false, true),
            ("dove eri rimasto?", false, true, true), ("dov'eri rimasto?", false, false, true), ("ti ho interrotto, scusa", false, false, true),
            ("continua a cercare su Google", false, false, false), ("vai avanti con la spesa", false, false, false),
            ("va bene, continua", false, false, true), ("finisci la frase", false, true, true), ("e poi?", false, false, true),
            ("e poi?", true, false, false), ("avanti tutta", false, false, false), ("no", false, false, false), ("sì", false, false, false),
        ]
        for (frase, domanda, libera, attesa) in casi {
            let r = FineFrase.chiedeDiContinuare(frase, dopoDomanda: domanda, libera: libera)
            controlla(r == attesa, "ripresa «\(frase)»\(domanda ? " dopo una domanda" : "")\(libera ? " senza nome" : "") = \(r) (attesa \(attesa))")
        }
    }

    /// 12.0 (10): più comandi in una frase vanno al cervello (la regia li fa in fila); le frasi normali no.
    static func provaComposti() {
        let casi: [(String, Bool)] = [
            ("apri la spesa e aggiungi il latte", true), ("Jarvis, chiudi tutto e poi dimmi il meteo", true),
            ("apri il meteo e dimmi se piove domani", true), ("metti pausa e apri la posta", true),
            ("aggiungi il latte e togli il pane", true), ("apri la spesa", false), ("aggiungi pane e latte", false),
            ("aggiungi latte, uova e pane", false), ("Bea e io andiamo al cinema", false), ("che tempo fa domani e sabato?", false),
            ("dimmi chi ha vinto e perché", false), ("apri Bea", false),
        ]
        for (frase, atteso) in casi {
            controlla(FineFrase.comandoComposto(frase) == atteso, "comando composto «\(frase)» = \(FineFrase.comandoComposto(frase))")
        }
    }

    /// 12.0 (10): il resto della risposta da dire dopo l'interruzione, dal punto esatto.
    static func provaResto() {
        let completa = "Domani sole a Milano, ventidue gradi. Giovedì invece pioggia. Porti l'ombrello, Sir."
        let casi: [(String, String?)] = [
            ("Domani sole a Milano, ventidue gradi.", "Giovedì invece pioggia. Porti l'ombrello, Sir."),
            ("[laughs] Domani sole a Milano, ventidue gradi.", "Giovedì invece pioggia. Porti l'ombrello, Sir."),
            ("Domani sole a Milano, ventidue gradi. Giovedì invece pioggia.", "Porti l'ombrello, Sir."),
            ("", completa), (completa, ""), ("Ieri pioggia.", nil),
        ]
        for (detto, atteso) in casi {
            let r = FineFrase.restoDaDire(completa, detto: detto)
            controlla(r == atteso, "resto dopo «\(detto.prefix(30))» = \(r.map { "«\($0.prefix(40))»" } ?? "nessuno")")
        }
    }
}
