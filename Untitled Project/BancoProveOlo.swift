#if DEBUG && os(iOS)
import Foundation
import SwiftUI

// MARK: - IL BANCO DI PROVA DEGLI OLOGRAMMI (solo versione di prova: mai su TestFlight, che è Release)
// 9 nov (il signore: «ricontrolla su una macchina virtuale le funzionalità nuove e la nuova grafica»): il controllo su GitHub avvia
// l'app nel simulatore con -provaBanco <sezione> e -oloProva.<sezione> <prova>; qui la tela della sezione, con i dati d'esempio del
// mockup (gli stessi numeri), a tutta larghezza come nella sezione: così le foto si confrontano col mockup una per una.

struct BancoProveOlo: View {
    let sezione: String
    private let tinta = Color.ciano

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("BANCO · \(sezione.uppercased())").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(tinta)
                tela.corniceOlo(tinta)
                Spacer(minLength: 0)
            }
            .padding(16)
            .padding(.top, 50)
        }
    }

    @ViewBuilder private var tela: some View {
        switch sezione {
        case "cuore": OlogrammaCuoreProve(dati: BancoProveOlo.cuore)
        case "telefono": OlogrammaTelefono(dati: DatiTelefonoOlo(numero: "35", chi: nil, contatti: BancoProveOlo.contatti, recenti: [(nome: "Matteo", numero: "+39 335 610 2284", quando: "23/10/26, 18:42")]))
        case "meteo": OlogrammaMeteoProve(dati: DatiMeteoOlo(stato: StatoCielo(cielo: .nuvole, pioggia: 20, vento: 11, ventoDa: 225), gradi: 14, nome: "Nuvoloso"))
        case "edith": OlogrammaEdithProve(dati: DatiEdithOlo(controlli: BancoProveOlo.controlli))
        case "posta": OlogrammaPosta(dati: PostaOlo(posta: BancoProveOlo.posta))
        case "messaggi": OlogrammaMessaggi(dati: BancoProveOlo.messaggi)
        case "confidente": OlogrammaConfidente(dati: ConfidenteOlo(testo: BancoProveOlo.conversazione, battito: 62))
        case "vitals": OlogrammaVitalsProve(dati: BancoProveOlo.vitals)
        case "github": OlogrammaGithubProve(dati: BancoProveOlo.github)
        case "supabase": OlogrammaSupabaseProve(dati: BancoProveOlo.supabase)
        case "archivio": OlogrammaArchivioProve(dati: BancoProveOlo.archivio)
        case "costi": OlogrammaCostiProve(dati: BancoProveOlo.costi)
        case "traccia": BancoTraccia()
        case "interprete": BancoInterprete()
        default: Text("Sezione sconosciuta: \(sezione)").foregroundStyle(.orange)
        }
    }

    // MARK: i dati d'esempio del mockup

    static let contatti: [(nome: String, numero: String)] = [("Bea", "+39 333 120 4471"), ("Camilla", "+39 347 552 0193"), ("Commercialista", "+39 02 4851 2290"),
                                                             ("Cristina", "+39 349 771 0458"), ("Matteo", "+39 335 610 2284"), ("Noleggio audio", "+39 02 3956 1170"), ("Pier", "+39 338 904 3312")]

    static var cuore: DatiCuoreOlo {
        var d = DatiCuoreOlo()
        let ora = Calendar.current.dateComponents([.hour, .minute], from: Date()), fine = (ora.hour ?? 12) * 60 + (ora.minute ?? 0)
        var oggi: [(m: Double, v: Double)] = []
        var m = 0
        while m <= fine {
            let h = Double(m) / 60
            var b = h < 6.5 ? 55 + 2.5 * sin(h * 1.4) : h < 8 ? 60 + (h - 6.5) * 9 : 72 + 5 * sin(h * 0.8)
            if h > 17.5 && h < 18.5 { b = 92 + 26 * sin((h - 17.5) * .pi) }
            oggi.append((m: Double(m), v: b.rounded()))
            m += 10
        }
        d.oggi = oggi
        d.adesso = oggi.last?.v ?? 72
        d.riposo = 58
        d.minimo = Int(oggi.map { $0.v }.min() ?? 51)
        d.massimo = Int(oggi.map { $0.v }.max() ?? 75)
        d.hrv = 42
        d.riposo30 = (0..<30).map { 57 + 3 * sin(Double($0) * 0.7) + Double($0 % 3) }
        d.hrv30 = (0..<30).map { 40 + 8 * sin(Double($0) * 0.5) + Double($0 % 4) }
        return d
    }

    static let controlli: [ControlloEdith] = [
        ControlloEdith(id: "porte", nome: "PORTE", esito: "93.41.x.x · DA SISTEMARE", fatto: true, ok: false, pronto: true),
        ControlloEdith(id: "fughe", nome: "FUGHE", esito: "PULITA: questa mail non è in nessun furto di dati noto.", fatto: true, ok: true, pronto: true),
        ControlloEdith(id: "link", nome: "LINK", esito: "Truffa probabile: poste-verifica.top", fatto: true, ok: false, pronto: true),
        ControlloEdith(id: "dominio", nome: "DOMINI", esito: "Certificato valido fino al 12 gen 2027", fatto: true, ok: true, pronto: true),
        ControlloEdith(id: "azienda", nome: "AZIENDA", esito: "Rossi Audio Srl", fatto: true, ok: true, pronto: true),
        ControlloEdith(id: "iban", nome: "IBAN", esito: "corretto · Banca Sella", fatto: true, ok: true, pronto: true),
        ControlloEdith(id: "numero", nome: "NUMERO", esito: "Italia · cellulare", fatto: true, ok: true, pronto: true),
        ControlloEdith(id: "reputazione", nome: "REPUTAZIONE", esito: "recensioni 4,2 su 5", fatto: false, ok: false, pronto: false),
        ControlloEdith(id: "password", nome: "PASSWORD", esito: "Trovata in 3 furti di dati", fatto: true, ok: false, pronto: false),
    ]

    static let posta: [PostaOlo.Mail] = [
        PostaOlo.Mail(nome: "Commercialista", oggetto: "F24 di novembre", data: "ven 23 ott, 09:12", letta: false),
        PostaOlo.Mail(nome: "Noleggio audio", oggetto: "Preventivo impianto", data: "gio 22 ott, 18:40", letta: false),
        PostaOlo.Mail(nome: "Banca", oggetto: "Nuovo accesso", data: "gio 22 ott, 11:05", letta: true),
        PostaOlo.Mail(nome: "Amazon", oggetto: "Ordine spedito", data: "mer 21 ott, 20:14", letta: true),
        PostaOlo.Mail(nome: "Affitto", oggetto: "Ricevuta ottobre", data: "lun 19 ott, 09:00", letta: true),
    ]

    static var messaggi: MessaggiOlo {
        let ora = Date()
        let v: [MessaggiOlo.Voce] = [
            MessaggiOlo.Voce(id: UUID(), nome: "Matteo", testo: "Allora sabato il live lo spostiamo all'una?", quando: ora.addingTimeInterval(-12 * 60), tipo: "imessage", ricevuto: true),
            MessaggiOlo.Voce(id: UUID(), nome: "Bea", testo: "Arrivo tra venti minuti, tieni il posto", quando: ora.addingTimeInterval(-25 * 60), tipo: "whatsapp"),
            MessaggiOlo.Voce(id: UUID(), nome: "Bea", testo: "Sono uscita adesso, ci vediamo da te.", quando: ora.addingTimeInterval(-70 * 60), tipo: "imessage", ricevuto: true),
            MessaggiOlo.Voce(id: UUID(), nome: "Matteo", testo: "La cassa di sabato torna: 6.840", quando: ora.addingTimeInterval(-3 * 3600), tipo: "imessage"),
            MessaggiOlo.Voce(id: UUID(), nome: "Pier", testo: "Le casse sono già in macchina.", quando: ora.addingTimeInterval(-5 * 3600), tipo: "imessage", ricevuto: true),
            MessaggiOlo.Voce(id: UUID(), nome: "Cristina", testo: "Il bar è pronto, scorte a posto.", quando: ora.addingTimeInterval(-6 * 3600), tipo: "whatsapp", ricevuto: true),
            MessaggiOlo.Voce(id: UUID(), nome: "Service audio", testo: "Confermato il ritiro alle 17", quando: ora.addingTimeInterval(-26 * 3600), tipo: "whatsapp"),
        ]
        return MessaggiOlo(voci: v, totale: 9, scelto: nil, canale: "iMessage")
    }

    static let conversazione = "Bea: ciao amore, stasera ci vediamo?\nio: sì dai, grazie, sono contento\nBea: sei sempre stanco però, basta\nio: scusa, il lavoro della serata mi ha ucciso\nBea: va bene, ti amo ❤\nio: ti amo anche io, sabato cena dai miei?\nBea: perfetto 😊"

    static var vitals: DatiVitalsOlo {
        var d = DatiVitalsOlo()
        d.prontezza = 87
        d.sonno = (92, "6 H 40", "35 MIN SOTTO LA MEDIA")
        d.battito = (100, "58 BPM", "A RIPOSO")
        d.umore = (70, "7 SU 10", "DAL DIARIO")
        d.passi = (84, "8.420", "IERI · OBIETTIVO 10.000")
        let g = 30.0, oggi = Date()
        func rnd(_ k: Double, _ a: Double, _ b: Double) -> Double { a + (b - a) * (0.5 + 0.5 * sin(k * 1.7 + g)) }
        d.giorni = (0..<30).map { k in
            let kk = Double(k)
            return GiornoVitalsOlo(d: oggi.addingTimeInterval(-Double(29 - k) * 86_400), um: rnd(kk, 5, 8.5), so: rnd(kk + 2, 5.5, 8), ba: rnd(kk + 5, 56, 62), pa: rnd(kk + 1, 2500, 11000))
        }
        return d
    }

    static let github = DatiGithubOlo(repo: [
        RepoOlo(nome: "jarvis", da: "1 h fa", lingua: "Swift", commit: ["Build 11.0 (19)", "Interprete rifatto: una sola apertura", "Wiretap: chiede di salvare", "VinileDock nel Dock"],
                giorni: [9, 7, 12, 4, 6, 11, 8, 3, 5, 10, 14, 6, 9, 12]),
        RepoOlo(nome: "vinyl-hustler", da: "2 g fa", lingua: "Swift", commit: ["Catalogo: filtri per genere", "Scheda disco più grande"], giorni: [0, 2, 1, 0, 3, 0, 0, 1, 2, 0, 0, 1, 0, 0]),
        RepoOlo(nome: "discosizer", da: "5 g fa", lingua: "Swift", commit: ["Serate: incassi per sala"], giorni: [1, 0, 0, 2, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]),
    ])

    static var supabase: DatiSupabaseOlo {
        var d = DatiSupabaseOlo()
        d.tabelle = [(nome: "jarvis_messaggi", righe: 31402), (nome: "jarvis_memoria", righe: 412), (nome: "jarvis_ricordi", righe: 96), (nome: "jarvis_diario", righe: 58)]
        d.funzioni = [(nome: "jarvis", versione: 123, attiva: true), (nome: "jarvis-briefing", versione: 24, attiva: true), (nome: "jarvis-ascolto", versione: 9, attiva: true), (nome: "jarvis-deploy", versione: 6, attiva: true)]
        d.db = "214 MB"
        d.righe = 48210
        d.storage = "36 MB · 12 FILE"
        d.minuti = (0..<60).map { i in (r: max(0, Int((3 + 2 * sin(Double(i) * 0.7) + (i % 17 == 5 ? 4 : 0)).rounded())), e: 0) }
        return d
    }

    static var archivio: DatiArchivioOlo {
        let f: [(String, String, Int, String, String)] = [("custom-giacca-verde.jpg", "denim", 2458, "ieri", "image/jpeg"), ("prospetto-sabato.pdf", "serate", 180, "mer", "application/pdf"),
            ("contratto-locale.pdf", "contratti", 1126, "lun", "application/pdf"), ("riunione-fornitori.m4a", "verbali", 8397, "12 ott", "audio/mp4"),
            ("toppa-ricamo.jpg", "denim", 1946, "11 ott", "image/jpeg"), ("scaletta-halloween.pdf", "serate", 120, "9 ott", "application/pdf"),
            ("jeans-cimosa.jpg", "denim", 2867, "7 ott", "image/jpeg"), ("preventivo-luci.pdf", "contratti", 400, "5 ott", "application/pdf"),
            ("flyer-ottobre.png", "serate", 3174, "3 ott", "image/png"), ("borchie-schizzo.jpg", "denim", 1229, "1 ott", "image/jpeg"),
            ("incassi-settembre.pdf", "serate", 200, "29 set", "application/pdf"), ("giubbotto-retro.jpg", "denim", 2662, "26 set", "image/jpeg")]
        return DatiArchivioOlo(file: f.map { FileOlo(nome: $0.0, cartella: $0.1, kb: $0.2, quando: $0.3, tipo: $0.4) },
                               cartelle: [(nome: "denim", n: 5), (nome: "serate", n: 4), (nome: "contratti", n: 2), (nome: "verbali", n: 1)])
    }

    static var costi: DatiCostiOlo {
        var d = DatiCostiOlo()
        d.mese = 18.4; d.oggi = 0.84; d.ieri = 1.12; d.sette = 5.9; d.risposte = 412
        d.modelli = [(nome: "SONNET", dollari: 12.1, risposte: 301), (nome: "OPUS", dollari: 5.0, risposte: 13), (nome: "HAIKU", dollari: 1.3, risposte: 98)]
        d.voce = (percento: 38, testo: "38.120 DI 100.000 CARATTERI")
        d.fissi = "SUPABASE PRO 25 $/MESE · APPLE DEVELOPER 99 €/ANNO"
        let cal = Calendar.current, oggi = cal.startOfDay(for: Date()), n = cal.component(.day, from: oggi)
        let base: [Double] = [0.42, 0.55, 0.61, 0.38, 0.9, 1.3, 0.7, 0.66, 0.52, 0.81, 0.95, 0.5, 0.44, 0.73, 1.05, 0.88, 0.62, 0.57, 1.4, 0.98, 0.79, 1.12, 0.84, 0.6, 0.7, 0.9, 0.5, 0.65, 0.8, 0.7, 0.9]
        d.giorni = (0..<n).map { i in (giorno: oggi.addingTimeInterval(-Double(n - 1 - i) * 86_400), dollari: base[i % base.count]) }
        return d
    }
}

/// TRACCIA al banco: SENTIERO, B.A.R.F. e MAPPA coi luoghi e i ricordi del mockup.
private struct BancoTraccia: View {
    @State private var sentiero = SentieroTraccia()
    private let ricordi: [RicordoOlo] = [
        RicordoOlo(tipo: "oggetto", testo: "Chiavi di casa sulla mensola dell'ingresso", chi: nil, dove: "casa", quando: "ven 23 ott, 23:05"),
        RicordoOlo(tipo: "persona", testo: "Luca ha cambiato lavoro: ora è da Spotify", chi: "Luca", dove: nil, quando: "gio 22 ott, 19:30"),
        RicordoOlo(tipo: "visto", testo: "Vino: Barbera d'Alba 2021, da ricomprare", chi: nil, dove: "Bar Basso", quando: "lun 19 ott, 22:10"),
        RicordoOlo(tipo: "idea", testo: "Lettering in oro per la serata di dicembre", chi: nil, dove: nil, quando: "dom 18 ott, 02:14"),
        RicordoOlo(tipo: "promessa", testo: "Ridare il libro a Marco", chi: "Marco", dove: nil, quando: "sab 17 ott, 18:00"),
    ]
    private let luoghi: [LuogoOlo] = [LuogoOlo(nome: "Studio", via: "Via Tortona 12", quando: "ven 23 ott, 21:40", metri: 180),
                                      LuogoOlo(nome: "Bar Basso", via: "Via Plinio 39", quando: "lun 19 ott, 16:05", metri: 950),
                                      LuogoOlo(nome: "Casa di Luca", via: "Viale Coni Zugna 41", quando: "lun 12 ott, 20:10", metri: 2300)]
    var body: some View {
        ProveOloVista(sezione: .traccia, altezza: 260, crea: { _ in }) { k, gc, W, H, t, M in
            switch k {
            case 1: ProveRicordiTavola.barf(&gc, W, H, t, M, ricordi, piccolo: false)
            case 2: ProveRicordiTavola.mappa(&gc, W, H, t, M, luoghi, scelto: 0, piccolo: false)
            default: sentiero.disegna(&gc, W, H, t, M, nome: "Studio", metri: 180)
            }
        }
    }
}

/// INTERPRETE al banco: PONTE, GLOBO e VOCI con l'inglese e due frasi.
private struct BancoInterprete: View {
    private let frasi = [PonteInterprete.Frase(altro: false, testo: "Buonasera, un tavolo per due", trad: "Good evening, a table for two"),
                         PonteInterprete.Frase(altro: true, testo: "Of course, follow me please", trad: "Certo, mi segua prego.")]
    var body: some View {
        ProveOloVista(sezione: .interprete, altezza: 250, crea: { _ in }) { k, gc, W, H, t, M in
            switch k {
            case 1: ProveInterpreteTavola.globo(&gc, W, H, t, M, codice: "EN", frasi: frasi, piccolo: false)
            case 2: ProveInterpreteTavola.voci(&gc, W, H, t, M, codice: "EN", frasi: frasi, piccolo: false)
            default: PonteInterprete.disegna(&gc, W, H, t, M, la: "IT", lb: "EN", frasi: frasi)
            }
        }
    }
}
#endif
