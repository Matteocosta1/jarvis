#if os(iOS)
import AVFoundation
import Speech

/// L'orecchio di JARVIS mentre parla: ascolta sottovoce e, se il signore dice «Jarvis», «basta», «aspetta»,
/// «stop», «zitto», «fermati» o «un attimo», lo interrompe subito e gli passa la parola.
/// Se invece il signore inizia semplicemente a parlare (almeno due parole), JARVIS tace, lo lascia finire la frase
/// e gliela consegna intera: come in una conversazione tra persone, senza toccare il reattore.
/// L'iPhone cancella l'eco della propria voce (voice processing); in più, se quello che sente coincide con le parole
/// che JARVIS sta dicendo, lo ignora: così non si interrompe da solo.
@MainActor
final class Orecchio {
    /// Chiamato quando il signore interrompe: riceve ciò che ha detto (dopo la parola d'ordine, o la frase intera).
    var interrotto: ((String) -> Void)?
    /// Chiamato appena il signore inizia a parlare: JARVIS deve tacere e mettersi in ascolto, l'orecchio continua da solo.
    var zittisci: (() -> Void)?
    /// 12 nov (P1): il signore ha detto «ho capito», «sì sì sì», «ok grazie» mentre JARVIS parlava: finisce la frase e si ferma.
    var capito: (() -> Void)?
    private var chiusuraChiesta = false
    /// 12 nov (P1): JARVIS sta facendo una domanda («…la chiamo?»): un «sì», un «va bene» detto adesso è la risposta, non un segnale
    /// d'ascolto. `rispostaAllaDomanda` riceve le sue parole: JARVIS finisce la domanda e poi le prende come frase sua.
    var domandaInCorso: (() -> Bool)?
    var rispostaAllaDomanda: ((String) -> Void)?
    /// Le parole che JARVIS sta dicendo in questo momento: servono a riconoscere la propria eco.
    var testoDetto = ""
    /// 13 nov (punto 2): la frase che JARVIS sta pronunciando adesso, per il registro dei tentativi.
    var fraseOra = ""
    private var tentativoAperto: TentativoSopra?
    private var tentativiFatti: [TentativoSopra] = []
    private var inPresa = false         // il signore sta parlando: aspetto che finisca la frase
    private var ultimoTesto = ""
    private var precedente = ""         // l'ultima trascrizione ricevuta
    private var primaPresa = ""
    private var voceConfermata = false
    private var controlloInCorso = false         // ciò che il signore ha già detto, se il riconoscimento è ripartito da capo
    private var inizioSegmento = 0      // la trascrizione si accumula: conta solo ciò che è arrivato dopo l'ultima pausa
    private var ultimaLunghezza = 0
    private var ultimoParziale = Date.distantPast
    private var timerSilenzio: Timer?
    private var timerTetto: Timer?      // come l'ascolto normale: al massimo un minuto di frase
    /// «Che ore sono, Jarvis?»: quello che il signore ha detto prima del nome, nello stesso fiato (senza l'eco di JARVIS).
    private var primaDelNome = ""

    private let motore = AVAudioEngine()
    private let riconoscitore = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timerRiavvio: Timer?
    private var turno = 0
    private var voluto = false          // il signore vuole l'orecchio acceso (JARVIS sta parlando)
    private var acceso = false

    private static let paroleStop = ["jarvis", "giarvis", "jervis", "basta", "aspetta", "ascoltami", "fermati", "zitto", "silenzio", "muto", "muta", "taci",
                                     "un attimo", "stop", "ehi", "hey", "bro", "fratello"]

    /// 12 nov (il signore: «in riservato gli stavo parlando e mi ha subito risposto»): in RISERVATO, mentre JARVIS parla, la
    /// risposta la fermano solo le parole d'ordine («Jarvis», «basta», «aspetta»…), non una frase qualsiasi detta a qualcun altro.
    var soloParoleDOrdine = false

    var attivo: Bool { acceso }
    /// Il signore gli sta parlando sopra e l'orecchio sta raccogliendo la sua frase (difetto 6 del 25 ott: in sottofondo si butta).
    var raccoglie: Bool { inPresa }

    func avvia() {
        voluto = true
        chiusuraChiesta = false
        // 13 nov (punto 1): la voce forte del signore sopra quella di JARVIS si misura da capo per ogni risposta; quando scatta
        // (mezzo secondo), le parole già sentite si rivalutano subito, senza aspettare il prossimo pezzo di trascrizione
        SopraLaVoce.condivisa.azzera()
        SopraLaVoce.condivisa.quandoForte = { [weak self] in
            Task { @MainActor [weak self] in self?.rivalutaForte() }
        }
        accendi()
    }

    func ferma() {
        chiudiTentativo()                   // 13 nov (punto 2): JARVIS ha finito di parlare, il tentativo in corso si registra
        voluto = false
        chiusuraChiesta = false
        inPresa = false
        voceConfermata = false
        primaPresa = ""
        primaDelNome = ""
        timerSilenzio?.invalidate()
        timerSilenzio = nil
        timerTetto?.invalidate()
        timerTetto = nil
        spegni()
    }

    private func accendi() {
        guard voluto, !acceso, let riconoscitore, riconoscitore.isAvailable else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        do {
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            r.addsPunctuation = true
            r.contextualStrings = ["Jarvis", "EDITH", "mi ricevi"]
            if riconoscitore.supportsOnDeviceRecognition, !ProcessInfo.processInfo.isiOSAppOnMac { r.requiresOnDeviceRecognition = true }   // sul Mac il motore locale non risponde (errore 1101): lì si usa quello di Apple   // niente quota Apple, niente rete
            richiesta = r
            try Orecchio.collega(motore, a: r)
            motore.prepare()
            try motore.start()
            acceso = true
            inizioSegmento = 0
            ultimaLunghezza = 0
            ultimoParziale = .distantPast
            precedente = ""
            turno += 1
            let mio = turno
            compito = Orecchio.riconosci(riconoscitore, r) { [weak self] testo, fine in
                Task { @MainActor [weak self] in self?.valuta(testo, fine: fine, turno: mio) }
            }
            // Apple chiude ogni ascolto dopo circa un minuto: si riparte prima, senza che si noti.
            timerRiavvio?.invalidate()
            timerRiavvio = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.inPresa else { return }   // il signore sta parlando: non gli taglio la frase
                    self.riavvia()
                }
            }
        } catch {
            spegni()
        }
    }

    private func spegni() {
        timerRiavvio?.invalidate()
        timerRiavvio = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil
        compito = nil
        acceso = false
    }

    private func riavvia() {
        guard voluto else { return }
        spegni()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.accendi()
        }
    }

    /// 12.0 (11): perché l'ultima voce sentita mentre JARVIS parlava non l'ha fermato («eco», «segnale», «folla», «orologio»,
    /// «riservato»): va nei tempi del turno, per regolare le soglie sui dati veri invece di indovinare.
    private(set) var ultimoScarto: (motivo: String, quando: Date)?
    private func scarto(_ motivo: String, parole: [String] = [], proprie: [String] = []) {
        ultimoScarto = (motivo, Date())
        annota(motivo, parole: parole, proprie: proprie)
    }

    // MARK: 13 nov (punto 2) · il registro dei tentativi

    /// Un tentativo del signore di parlare sopra JARVIS, com'è andato: fermato (e con quale regola) o no (e perché), con le parole
    /// sentite. Il signore: «ogni interruzione mancata salvata nei tempi del turno con le parole sentite, così vedo cosa è successo».
    nonisolated struct TentativoSopra: Sendable {
        var quando: Date
        var esito: String          // «fermato·nome», «fermato·parole», «fermato·voce», «risposta», «capito»; o eco, segnale, folla, orologio, riservato
        var sentite: String        // quello che il microfono ha trascritto in quel pezzo (eco compresa)
        var sue: String            // le parole riconosciute come sue
        var forteMs: Int           // per quanto la sua voce è stata forte sopra quella di JARVIS (millisecondi, sugli ultimi 0,8 s)
        var sopraDb: Int           // di quanto il microfono è salito sopra l'eco tipica di JARVIS
        var jarvis: String         // le ultime parole della frase che JARVIS stava dicendo
    }

    private func annota(_ esito: String, parole: [String], proprie: [String]) {
        let picchi = SopraLaVoce.condivisa.picchi()
        let fermato = esito.hasPrefix("fermato") || esito == "risposta" || esito == "capito"
        // solo se c'è traccia di lui (parole sue o la voce forte): la sola eco di JARVIS non è un tentativo
        guard fermato || !proprie.isEmpty || picchi.forteMs >= 150 else { return }
        tentativoAperto = TentativoSopra(
            quando: tentativoAperto?.quando ?? Date(), esito: esito,
            sentite: String(parole.suffix(14).joined(separator: " ").prefix(120)),
            sue: String(proprie.suffix(10).joined(separator: " ").prefix(80)),
            forteMs: max(picchi.forteMs, tentativoAperto?.forteMs ?? 0), sopraDb: max(picchi.sopraDb, tentativoAperto?.sopraDb ?? 0),
            jarvis: String(Orecchio.parole(fraseOra).suffix(10).joined(separator: " ").prefix(90)))
        if fermato { chiudiTentativo() }
    }

    private func chiudiTentativo() {
        SopraLaVoce.condivisa.azzeraPicchi()
        guard let t = tentativoAperto else { return }
        tentativoAperto = nil
        tentativiFatti.append(t)
        let limite = Date().addingTimeInterval(-300)
        tentativiFatti.removeAll { $0.quando < limite }
        if tentativiFatti.count > 12 { tentativiFatti.removeFirst(tentativiFatti.count - 12) }
    }

    /// I tentativi degli ultimi 3 minuti, per i tempi del turno (poi si dimenticano: ognuno va al cervello una volta sola).
    func tentativiPerMisura() -> [[String: Any]] {
        chiudiTentativo()
        let adesso = Date(), da = adesso.addingTimeInterval(-180)
        let out: [[String: Any]] = tentativiFatti.filter { $0.quando >= da }.map { t in
            ["esito": t.esito, "sentite": t.sentite, "sue": t.sue, "forte_ms": t.forteMs, "sopra_db": t.sopraDb, "jarvis": t.jarvis,
             "s_fa": Int(adesso.timeIntervalSince(t.quando).rounded())]
        }
        tentativiFatti.removeAll()
        return out
    }

    /// 13 nov (punto 1): la sua voce è appena diventata forte sopra quella di JARVIS (mezzo secondo): le parole già sentite in
    /// questo pezzo si rivalutano adesso, senza aspettare il prossimo pezzo di trascrizione.
    private func rivalutaForte() {
        guard voluto, acceso, !inPresa else { return }
        // voce forte ma ancora nessuna parola trascritta: si annota (se non arriva nessuna parola, il registro dice proprio questo)
        guard !precedente.isEmpty else { annota("senza parole", parole: [], proprie: []); return }
        valuta(precedente, fine: false, turno: turno, rivaluta: true)
    }

    /// Le parole di una frase, minuscole, senza punteggiatura.
    nonisolated private static func parole(_ t: String) -> [String] {
        t.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    /// La prima parola d'ordine detta come parola intera («basta», non «abbastanza») e che JARVIS non sta dicendo lui
    /// («un attimo, Sir» è una sua frase: la sua eco non deve fermarlo). Restituisce la parola e ciò che segue.
    private func paroladOrdine(in segmento: String) -> String? {
        let sentite = " " + Orecchio.parole(segmento).joined(separator: " ") + " "
        let dette = " " + Orecchio.parole(testoDetto).joined(separator: " ") + " "
        for p in Orecchio.paroleStop {
            let cercata = " " + p + " "
            guard sentite.contains(cercata) else { continue }
            if dette.contains(cercata) && !p.hasPrefix("jarvi") { continue }   // la sta dicendo JARVIS: è eco
            if p.hasPrefix("jarvi") && dette.contains(cercata) && sentite.components(separatedBy: cercata).count <= dette.components(separatedBy: cercata).count { continue }
            return p
        }
        return nil
    }

    /// `rivaluta`: le stesse parole già sentite, di nuovo (la voce forte è appena scattata): niente pezzo nuovo né pause.
    private func valuta(_ testo: String?, fine: Bool, turno mio: Int, rivaluta: Bool = false) {
        guard acceso, mio == turno else { return }
        if let testo, !testo.isEmpty {
            if !rivaluta {
                // dopo una pausa comincia un pezzo nuovo: valuto solo quello, non tutta la trascrizione dall'inizio
                // (prima l'eco accumulata «diluiva» le parole del signore e l'interruzione non scattava più)
                let adesso = Date()
                let pausa = adesso.timeIntervalSince(ultimoParziale)
                // il riconoscimento sull'iPhone a volte ricomincia la trascrizione da capo dopo una pausa
                let ripartito = Richiamo.pezzoNuovo(precedente: precedente, nuovo: testo, pausa: pausa)
                precedente = testo
                if ripartito {
                    if inPresa { primaPresa = ultimoTesto }   // tengo quanto ha già detto e continuo ad aggiungere
                    else { chiudiTentativo() }                 // 13 nov: un pezzo nuovo è un tentativo nuovo
                    inizioSegmento = 0
                } else if !inPresa, pausa > 0.7 { chiudiTentativo(); inizioSegmento = min(ultimaLunghezza, testo.count) }
                ultimoParziale = adesso
                ultimaLunghezza = testo.count
            }
            var segmento = String(testo.dropFirst(min(inizioSegmento, testo.count)))

            if !inPresa, let parola = paroladOrdine(in: segmento) {
                // «Jarvis», «aspetta», «basta»…: JARVIS tace subito, ma io continuo ad ascoltare sullo stesso microfono
                // dalla parola d'ordine in poi, così non si perde nulla e non serve riaprire l'ascolto (niente bip)
                if let r = segmento.range(of: parola, options: [.caseInsensitive, .backwards]) {
                    // M2: se la parola è il nome, quello che il signore ha detto subito prima («Che ore sono, Jarvis?») si tiene da
                    // parte, senza l'eco di JARVIS in testa: se dopo il nome non aggiunge altro, la domanda è quella (prima si perdeva)
                    if ["jarvis", "giarvis", "jervis"].contains(parola), !AmbienteSonoro.condiviso.affollato {   // con TV o folla no: «Thank you, Jarvis»
                        primaDelNome = Orecchio.senzaEco(String(segmento[..<r.lowerBound]), detto: testoDetto)
                    }
                    inizioSegmento = min(inizioSegmento + segmento.distance(from: segmento.startIndex, to: r.lowerBound), testo.count)
                    segmento = String(testo.dropFirst(inizioSegmento))
                }
                inPresa = true
                avviaTetto()
                annota("fermato·nome", parole: Orecchio.parole(segmento), proprie: [parola])   // 13 nov: col nome o una parola d'ordine
                zittisci?()
            }
            let parole = Orecchio.parole(segmento)
            if !inPresa, soloParoleDOrdine {                // 12 nov: RISERVATO, senza parola d'ordine non è per JARVIS
                scarto("riservato", parole: parole, proprie: FineFrase.paroleProprie(parole, detto: Orecchio.parole(testoDetto)))
                if fine { riavvia() }
                return
            }
            if !inPresa {
                // 12 nov (P1, revisione del dialogo): fra persone «sì», «mh», «certo», «esatto», «ah ok» detti mentre l'altro parla sono
                // segnali d'ascolto: chi parla continua (prima due parole bastavano a zittirlo). «Ho capito», «sì sì sì», «ok grazie»: ha
                // capito, JARVIS finisce la frase che sta dicendo e si ferma (più sotto, dopo gli stessi controlli di una frase vera:
                // eco, orologio, impronta della voce). Le parole che sta dicendo JARVIS (la sua eco) non contano
                // 12.0 (11): le parole sue, separate dall'eco di JARVIS (FineFrase.paroleProprie: eco solo se fa coppia come nella
                // frase di JARVIS; prima «ma», «non», «cosa» del signore sparivano come eco perché JARVIS le aveva usate)
                let dette = Orecchio.parole(testoDetto)
                let proprie = FineFrase.paroleProprie(parole, detto: dette)
                let segnale = proprie.isEmpty ? FineFrase.SegnaleAscolto.nessuno : FineFrase.segnaleDAscolto(proprie.joined(separator: " "))
                // mentre JARVIS fa una domanda, «sì» è la risposta (passa gli stessi controlli di una frase vera, qui sotto)
                let allaDomanda = segnale == .ascolto && domandaInCorso?() == true
                if segnale == .ascolto && !allaDomanda { scarto("segnale", parole: parole, proprie: proprie); if fine { riavvia() }; return }
                // 12.0 (11): gli parla sopra? Contano le ultime parole sentite: almeno due sue (prima l'eco accumulata nella
                // trascrizione «diluiva» le sue parole e solo «Jarvis, ascoltami» lo fermava).
                // 13 nov (punto 1, il signore: «se il microfono sente la sua voce forte sopra quella di JARVIS per mezzo secondo, più
                // almeno una parola sua, JARVIS si ferma»): non serve più aspettare la seconda parola riconosciuta
                let perParole = FineFrase.parlaSopra(parole, detto: dette)
                let perVoce = !proprie.isEmpty && SopraLaVoce.condivisa.forteSecondi >= 0.5
                guard perParole || perVoce || allaDomanda else { scarto("eco", parole: parole, proprie: proprie); if fine { riavvia() }; return }
                // decisione del signore (24 ott, M8): mentre usa l'orologio, una frase senza «Jarvis» non è per l'iPhone
                // (potrebbe essere la voce dell'orologio): valgono solo le parole d'ordine
                if OrologioInUso.attivo { scarto("orologio", parole: parole, proprie: proprie); if fine { riavvia() }; return }
                // 12.0 (11), scelta A (il signore: «risolvi con massima competenza»): l'impronta della sua voce serve solo con folla o TV
                // intorno, dove le voci degli altri non devono fermarlo. In casa basta la sua voce: sopra la voce di JARVIS il
                // confronto dell'impronta sbagliava spesso e lo lasciava parlare (idea C del 25 ott: prima valeva sempre)
                if AmbienteSonoro.condiviso.affollato && !voceConfermata {
                    scarto("folla", parole: parole, proprie: proprie)
                    // in mezzo alla folla le voci degli altri non devono zittirlo: valgono le parole d'ordine
                    // e, se il signore ha registrato la sua voce, le frasi riconosciute come sue
                    if VoceDelSignore.attiva && !controlloInCorso {
                        controlloInCorso = true
                        let mio = turno
                        Task { @MainActor [weak self] in
                            // aspetto che abbia detto qualche parola in più, così il pezzo controllato è quasi tutto
                            // voce sua e non la coda della mia; sopra la musica e la mia voce l'audio è più sporco,
                            // quindi se stiamo già parlando (fiducia di conversazione) la soglia è un po' più larga
                            try? await Task.sleep(for: .milliseconds(700))
                            let lui = await VoceDelSignore.eLui(ultimi: 1.8, sconto: VoceDelSignore.inFiducia ? 0.15 : 0.10)   // tarato dal vivo: signore 71, Matteo 59 → soglia 65
                            guard let self else { return }
                            self.controlloInCorso = false
                            guard lui == true, self.acceso, !self.inPresa, self.turno == mio else { return }
                            self.voceConfermata = true
                            self.ultimoParziale = Date()          // nessuna «pausa» finta: la frase continua da dove era
                            self.valuta(self.precedente, fine: false, turno: mio)
                        }
                    }
                    if fine { riavvia() }
                    return
                }
                if allaDomanda {
                    // P1: la risposta alla domanda che JARVIS sta facendo: la finisce e poi la prende come frase del signore
                    annota("risposta", parole: parole, proprie: proprie)
                    rispostaAllaDomanda?(proprie.joined(separator: " "))
                    if fine { riavvia() }
                    return
                }
                if segnale == .chiusura {
                    // P1: ha capito. JARVIS finisce la frase che sta dicendo e si ferma (una volta sola per risposta)
                    if !chiusuraChiesta { chiusuraChiesta = true; annota("capito", parole: parole, proprie: proprie); capito?() }
                    if fine { riavvia() }
                    return
                }
                inPresa = true
                avviaTetto()
                annota(perParole ? "fermato·parole" : "fermato·voce", parole: parole, proprie: proprie)
                zittisci?()                               // JARVIS tace; io continuo ad ascoltare la frase
            }
            // solo la frase del signore, senza l'eco di prima (più quanto detto prima di un'eventuale ripartenza)
            ultimoTesto = [primaPresa, segmento].filter { !$0.isEmpty }.joined(separator: " ")
            // la frase è finita quando il signore tace (più a lungo se si è fermato a metà: «…e», «…perché»)
            timerSilenzio?.invalidate()
            // solo la parola d'ordine («Jarvis…»): gli lascio qualche secondo per dire cosa vuole
            // («basta», «zitto», «stop» da soli: tace e basta, quindi aspetto poco;
            // «aspetta» da solo: 5 secondi, poi «Mi dica, Sir», deciso dal signore il 24 ott;
            // «Che ore sono, Jarvis?»: la domanda c'è già, la pausa è quella della frase)
            let (pulito, chiede) = Jarvis.togliRichiamo(ultimoTesto)
            let basso = ultimoTesto.lowercased()
            let chiama = chiede || ["jarvi", "giarvi", "jervis", "ehi", "hey", "bro", "fratello"].contains(where: { basso.contains($0) })
            let attesa: Double
            if pulito.isEmpty, !chiede, !primaDelNome.isEmpty { attesa = Jarvis.pausaFineFrase(primaDelNome + " " + ultimoTesto) }
            else if pulito.isEmpty { attesa = chiede ? Dialogo.silenzioDopoAspetta : (chiama ? 4.0 : 1.2) }
            else { attesa = Jarvis.pausaFineFrase(ultimoTesto) }
            timerSilenzio = Timer.scheduledTimer(withTimeInterval: attesa, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.consegna() }
            }
            if fine { riprendiPresa() }
            return
        }
        if fine { if inPresa { riprendiPresa() } else { riavvia() } }
    }

    /// Il riconoscimento ha chiuso il suo pezzo mentre il signore parlava: riapro subito l'ascolto tenendo quanto detto.
    /// Decide il silenzio (timerSilenzio) quando la frase è davvero finita, non il riconoscimento.
    private func riprendiPresa() {
        guard inPresa else { return }
        primaPresa = ultimoTesto
        spegni()
        accendi()
        if !acceso { consegna() }          // il microfono non riparte: consegno quello che ho
    }

    /// La frase del signore è completa: la passo a JARVIS.
    private func consegna() {
        guard inPresa else { return }
        var testo = ultimoTesto.trimmingCharacters(in: .whitespacesAndNewlines)
        // «Che ore sono, Jarvis?»: dopo il nome niente, quindi la domanda è quella detta prima del nome (M2).
        // «…Jarvis, basta» o «…Jarvis, apri il meteo» restano come sono: vale quello che viene dopo il nome.
        let (pulito, chiede) = Jarvis.togliRichiamo(testo)
        if pulito.isEmpty, !chiede, !primaDelNome.isEmpty, !Jarvis.eSoloSilenzio(testo) { testo = primaDelNome + " " + testo }
        primaPresa = ""
        ferma()
        interrotto?(testo)
    }

    /// Un minuto al massimo per la frase con cui il signore l'ha interrotto, come l'ascolto normale (prima nessun limite).
    private func avviaTetto() {
        timerTetto?.invalidate()
        timerTetto = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.consegna() }
        }
    }

    /// Le parole dette prima del nome, senza l'eco in testa: se cominciano con un pezzo (almeno due parole di fila) di quello
    /// che JARVIS stava dicendo, quel pezzo è l'altoparlante e si toglie. Una parola sola che coincide resta: è più probabile
    /// che sia del signore («che» in «Che ore sono, Jarvis?»).
    nonisolated static func senzaEco(_ prima: String, detto: String) -> String {
        let p = parole(prima), d = parole(detto)
        var eco = 0
        if p.count >= 2, d.count >= 2 {
            for n in stride(from: p.count, through: 2, by: -1) where n <= d.count {
                let pezzo = Array(p[0..<n])
                if (0...(d.count - n)).contains(where: { Array(d[$0..<($0 + n)]) == pezzo }) { eco = n; break }
            }
        }
        return Richiamo.dallaParola(eco, prima).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.!?"))
    }

    // MARK: Ponti fuori dal thread principale

    nonisolated private static func collega(_ motore: AVAudioEngine, a r: SFSpeechAudioBufferRecognitionRequest) throws {
        let input = motore.inputNode
        // cancellazione dell'eco: il microfono non sente la voce che esce dall'altoparlante
        if !input.isVoiceProcessingEnabled { try input.setVoiceProcessingEnabled(true) }
        let formato = input.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else {
            throw NSError(domain: "Orecchio", code: 1, userInfo: [NSLocalizedDescriptionKey: "nessun ingresso audio"])
        }
        input.removeTap(onBus: 0)
        nonisolated(unsafe) let richiesta = r
        let ambiente = AmbienteSonoro.condiviso.nuovaAnalisi(formato: formato)   // folla, musica, TV intorno?
        input.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, quando in
            richiesta.append(buffer)
            ambiente?.analizza(buffer, posizione: quando.sampleTime)
            RegistroMicrofono.condiviso.scrivi(buffer)          // gli ultimi secondi, per riconoscere la voce del signore
            SopraLaVoce.condivisa.misura(buffer)                // 13 nov (punto 1): la sua voce forte sopra quella di JARVIS
        }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in
            esito(ris?.bestTranscription.formattedString, (ris?.isFinal ?? false) || err != nil)
        }
    }
}

// MARK: - 13 nov (punto 1) · la voce del signore forte sopra quella di JARVIS

/// Il signore: «se il microfono sente la sua voce forte sopra quella di JARVIS per mezzo secondo, più almeno una parola sua,
/// JARVIS si ferma». Il microfono dell'orecchio ha la cancellazione dell'eco: della voce di JARVIS resta un'eco debole che segue il
/// volume con cui JARVIS parla. Si misura di quanto il microfono sta sopra la voce che esce (rapporto in dB) e se ne tiene il valore
/// tipico di questa risposta (75° percentile degli ultimi 6 secondi, senza i pezzi già presi per voce sua): quando il signore gli
/// parla sopra il microfono sale di colpo, oltre 10 dB sopra il tipico. Nelle pause fra le frasi (nessuna voce in uscita) il
/// confronto è col fondo della stanza (12 dB sopra). «Forte» = almeno mezzo secondo così negli ultimi 0,8 s (le sillabe hanno
/// piccoli vuoti). Gira sul thread del microfono: tutto sotto lucchetto.
nonisolated final class SopraLaVoce: @unchecked Sendable {
    static let condivisa = SopraLaVoce()

    private let lock = NSLock()
    private var rapporti: [(t: TimeInterval, d: Float)] = []    // microfono − voce in uscita (dB), mentre JARVIS suona
    private var tipico: Float?                                   // il 75° percentile dei rapporti (l'eco tipica)
    private var fondo: Float = -60                               // il microfono nelle pause di JARVIS (dB)
    private var pezziFondo = 0
    private var forti: [(t: TimeInterval, durata: Double)] = []  // i pezzi di voce forte dell'ultimo 0,8 s
    private var ultimoCalcolo: TimeInterval = 0
    private var eraForte = false
    private var piccoForte: Double = 0                           // per il registro dei tentativi
    private var piccoSopra: Float = 0
    private var avviso: (@Sendable () -> Void)?

    private static var ora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Chiamato (dal thread del microfono) quando la sua voce diventa forte: mezzo secondo raggiunto.
    var quandoForte: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return avviso }
        set { lock.lock(); avviso = newValue; lock.unlock() }
    }

    /// Una risposta nuova: l'eco tipica si rimisura da capo.
    func azzera() {
        lock.lock()
        rapporti.removeAll(); tipico = nil; fondo = -60; pezziFondo = 0; forti.removeAll(); eraForte = false
        piccoForte = 0; piccoSopra = 0; ultimoCalcolo = 0
        lock.unlock()
    }

    /// Un pezzo di audio del microfono dell'orecchio (dopo la cancellazione dell'eco).
    func misura(_ b: AVAudioPCMBuffer) {
        guard let c = b.floatChannelData?[0], b.frameLength > 0, b.format.sampleRate > 0 else { return }
        let n = Int(b.frameLength)
        var somma: Float = 0
        for i in stride(from: 0, to: n, by: 2) { somma += c[i] * c[i] }
        let m = 20 * log10(max((somma / Float((n + 1) / 2)).squareRoot(), 0.000_01))
        let durata = Double(n) / b.format.sampleRate
        let uscita = EcoMac.condivisa.riferimento().rif          // la voce di JARVIS che esce adesso (nil nelle pause)
        let t = SopraLaVoce.ora
        var chiama: (@Sendable () -> Void)?
        lock.lock()
        var forte = false
        var sopra: Float = 0
        if let uscita {
            let d = m - 20 * log10(max(uscita, 0.000_01))
            if let tip = tipico { sopra = d - tip; forte = sopra > 10 && m > -55 }
            if !forte { rapporti.append((t, d)) }
        } else {
            // pausa fra due frasi di JARVIS: il fondo della stanza (scende subito, sale piano)
            if pezziFondo < 4 { fondo = pezziFondo == 0 ? m : min(fondo, m) }
            else if m < fondo { fondo = fondo * 0.6 + m * 0.4 }
            else if m < fondo + 12 { fondo += (m - fondo) * 0.01 }
            pezziFondo += 1
            if pezziFondo >= 4 { sopra = m - fondo; forte = sopra > 12 && m > -55 }
        }
        while let p = rapporti.first, t - p.t > 6 { rapporti.removeFirst() }
        if t - ultimoCalcolo > 0.25, rapporti.count >= 15 {
            let s = rapporti.map(\.d).sorted()
            tipico = s[min(s.count - 1, Int(Float(s.count) * 0.75))]
            ultimoCalcolo = t
        }
        if forte { forti.append((t, durata)); piccoSopra = max(piccoSopra, sopra) }
        while let p = forti.first, t - p.t > 0.8 { forti.removeFirst() }
        let secondi = forti.reduce(0) { $0 + $1.durata }
        piccoForte = max(piccoForte, secondi)
        let adesso = secondi >= 0.5
        if adesso && !eraForte { chiama = avviso }
        eraForte = adesso
        lock.unlock()
        chiama?()
    }

    /// Per quanti secondi, nell'ultimo 0,8 s, la sua voce è stata forte sopra quella di JARVIS.
    var forteSecondi: Double {
        lock.lock(); defer { lock.unlock() }
        let t = SopraLaVoce.ora
        return forti.filter { t - $0.t <= 0.8 }.reduce(0) { $0 + $1.durata }
    }

    /// Il massimo dall'ultimo azzeramento (per il registro): millisecondi di voce forte e dB sopra l'eco tipica.
    func picchi() -> (forteMs: Int, sopraDb: Int) {
        lock.lock(); defer { lock.unlock() }
        return (Int((piccoForte * 1000).rounded()), Int(piccoSopra.rounded()))
    }

    func azzeraPicchi() {
        lock.lock(); piccoForte = 0; piccoSopra = 0; lock.unlock()
    }
}
#endif
