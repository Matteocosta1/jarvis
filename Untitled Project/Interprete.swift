#if os(iOS)
import SwiftUI
import Combine
import AVFoundation
import Speech

/// L'interprete di JARVIS: il signore parla italiano e JARVIS lo dice nell'altra lingua con la sua voce;
/// l'altro risponde nella sua lingua e JARVIS la traduce in italiano. Due direzioni, a turni, in una schermata HUD.
struct Lingua: Identifiable, Hashable {
    let codice: String      // per il cervello: en, es, fr…
    let locale: String      // per il riconoscimento vocale: en-US, es-ES…
    let nome: String
    let bandiera: String
    var id: String { codice }

    static let tutte: [Lingua] = [
        Lingua(codice: "en", locale: "en-US", nome: "Inglese", bandiera: "🇬🇧"),
        Lingua(codice: "es", locale: "es-ES", nome: "Spagnolo", bandiera: "🇪🇸"),
        Lingua(codice: "fr", locale: "fr-FR", nome: "Francese", bandiera: "🇫🇷"),
        Lingua(codice: "de", locale: "de-DE", nome: "Tedesco", bandiera: "🇩🇪"),
        Lingua(codice: "pt", locale: "pt-BR", nome: "Portoghese", bandiera: "🇧🇷"),
        Lingua(codice: "zh", locale: "zh-CN", nome: "Cinese", bandiera: "🇨🇳"),
        Lingua(codice: "ja", locale: "ja-JP", nome: "Giapponese", bandiera: "🇯🇵"),
        Lingua(codice: "ar", locale: "ar-SA", nome: "Arabo", bandiera: "🇸🇦"),
        Lingua(codice: "ru", locale: "ru-RU", nome: "Russo", bandiera: "🇷🇺"),
        Lingua(codice: "tr", locale: "tr-TR", nome: "Turco", bandiera: "🇹🇷"),
        Lingua(codice: "ro", locale: "ro-RO", nome: "Rumeno", bandiera: "🇷🇴"),
        Lingua(codice: "nl", locale: "nl-NL", nome: "Olandese", bandiera: "🇳🇱"),
        Lingua(codice: "pl", locale: "pl-PL", nome: "Polacco", bandiera: "🇵🇱"),
        Lingua(codice: "el", locale: "el-GR", nome: "Greco", bandiera: "🇬🇷"),
        Lingua(codice: "hi", locale: "hi-IN", nome: "Hindi", bandiera: "🇮🇳"),
        Lingua(codice: "uk", locale: "uk-UA", nome: "Ucraino", bandiera: "🇺🇦"),
    ]
    static let italiano = Lingua(codice: "it", locale: "it-IT", nome: "Italiano", bandiera: "🇮🇹")

    static func trova(_ codice: String) -> Lingua? {
        let c = codice.lowercased().trimmingCharacters(in: .whitespaces)
        return tutte.first { $0.codice == c } ?? tutte.first { $0.nome.lowercased().hasPrefix(c) }
    }
}

struct Interprete: View {
    let lingua: Lingua
    let chiudi: () -> Void
    @StateObject private var motore = MotoreInterprete()
    @AppStorage("interpreteAuto") private var automatico = true
    @State private var scelta: Lingua?                  // «Jarvis, passa al francese»: la lingua cambiata a voce
    @State private var scegliLingua = false             // «Jarvis, cambia lingua»
    @State private var orecchio = OrecchioComandi()     // i comandi a voce tra un turno e l'altro, sempre con «Jarvis» davanti
    @State private var chiuso = false                   // a schermata chiusa l'orecchio non si riaccende più
    private var lin: Lingua { scelta ?? lingua }

    var body: some View {
        ZStack {
            SfondoHUD(fase: motore.faseHUD)
            VStack(spacing: 12) {
                HStack {
                    AnelloOcchi(icona: "globe.europe.africa", tinta: Color.ciano)   // 26 ott notte: l'icona animata come le altre sezioni
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INTERPRETE")
                            .font(.system(size: 18, weight: .bold, design: .monospaced)).tracking(3)
                        Text(lin.nome.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                    }
                    .foregroundStyle(Color.ciano)
                    Spacer()
                    Button("Chiudi") { Suoni.tocco(); motore.ferma(); chiudi() }
                        .font(.body).tint(Color.ciano).foregroundStyle(Color.ciano)
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, 20).padding(.top, 8)

                // le due lingue, con il lato attivo che si illumina
                HStack(spacing: 10) {
                    lato(Lingua.italiano, attivo: motore.lato == .io, titolo: "LEI")
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(Color.tenue)
                    lato(lin, attivo: motore.lato == .altro, titolo: "L'ALTRO")
                }
                .padding(.horizontal, 20)

                Text(motore.stato)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(3)
                    .foregroundStyle(motore.fase == .ascolto ? Color.ciano : Color.orange)
                    .frame(minHeight: 18)

                // la conversazione
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(motore.scambi) { s in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(s.chi == .io ? "LEI" : lin.nome.uppercased()) · \(s.ora)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                                        .foregroundStyle(s.chi == .io ? Color.ciano : Color.orange)
                                    Text(s.originale).font(.system(size: 15)).foregroundStyle(.white)
                                    Text(s.tradotto.isEmpty ? "…" : s.tradotto).font(.system(size: 15)).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.95)).italic()
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.ciano.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke((s.chi == .io ? Color.ciano : Color.orange).opacity(0.35), lineWidth: 0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .id(s.id)
                            }
                            if !motore.parziale.isEmpty {
                                Text(motore.parziale).font(.system(size: 15)).foregroundStyle(Color.tenue).padding(.horizontal, 10)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    .onChange(of: motore.scambi.count) { if let u = motore.scambi.last { withAnimation { proxy.scrollTo(u.id, anchor: .bottom) } } }
                }
                // 27 ott: la conversazione nel visore olografico, come Browser e Confidente
                .background(Color.ciano.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ciano.opacity(0.25), lineWidth: 1))
                .overlay(AngoliOlo(tinta: Color.ciano).padding(-1).allowsHitTesting(false))
                .padding(.horizontal, 12)

                Toggle(isOn: $automatico) {
                    Text("A turni automatici").font(.footnote).foregroundStyle(Color.tenue)
                }
                .tint(Color.ciano2)
                .padding(.horizontal, 20)

                // i due tasti: ascolta me / ascolta l'altro
                HStack(spacing: 14) {
                    tasto("Ascolta me", icona: "person.wave.2", colore: Color.ciano) { orecchio.ferma(); motore.ascolta(.io, lingua: lin) }
                    tasto("Ascolta \(lin.bandiera)", icona: "ear", colore: Color.orange) { orecchio.ferma(); motore.ascolta(.altro, lingua: lin) }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }
        }
        .onAppear {
            motore.automatico = automatico
            motore.prepara(lingua: lin)
            orecchio.dentro = .interprete
            orecchio.comando = { c in comando(c) }
            motore.suComando = { c in comando(c) }          // «Jarvis, …» detto durante il suo turno: è un comando, non si traduce
        }
        .task {
            try? await Task.sleep(for: .seconds(1.8))      // dopo il suono d'apertura, come nella Sentinella
            if !Task.isCancelled, !chiuso, motore.fase == .attesa { orecchio.avvia() }
        }
        // il microfono dei comandi resta acceso solo tra un turno e l'altro: nei turni il microfono è dell'Interprete
        .onChange(of: motore.fase) { _, f in
            if f != .attesa { orecchio.ferma(); return }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !chiuso, motore.fase == .attesa { orecchio.avvia() }
            }
        }
        .onChange(of: automatico) { _, v in motore.automatico = v }
        .onDisappear { chiuso = true; orecchio.ferma(); motore.ferma() }
        .pausaDietro(ferma: { orecchio.ferma(); motore.ferma(); scegliLingua = false },   // MARK XI: dietro in pausa
                     riprendi: { if !chiuso, motore.fase == .attesa { orecchio.avvia() } })
        // 4 nov (il signore): «Jarvis, cambia lingua» apre la scheda di JARVIS con le lingue, come all'apertura (SceltaLingua),
        // non più il menu di iOS con le bandierine. La conversazione resta.
        .fullScreenCover(isPresented: $scegliLingua) {
            SceltaLingua { l in cambia(l) }
                .paginaPiena()
        }
        .aperturaHUD("Interprete")
    }

    /// I comandi a voce dentro l'Interprete.
    private func comando(_ c: ComandoVocale) {
        switch c {
        case .torna:
            chiuso = true; orecchio.ferma(); motore.ferma(); chiudi()
        case .dentroInterprete(let a):
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            switch a {
            case .ascoltaMe: orecchio.ferma(); motore.ascolta(.io, lingua: lin)
            case .ascoltaAltro: orecchio.ferma(); motore.ascolta(.altro, lingua: lin)
            case .ripeti:                                   // niente da ripetere: l'ascolto dei comandi resta acceso
                orecchio.ferma(); motore.ripeti(lin)
                if motore.fase == .attesa { orecchio.avvia() }
            case .turniAutomatici(let si):
                automatico = si
                orecchio.ferma(); motore.annuncia(si ? "Turni automatici, Sir." : "Turni manuali, Sir.")
            case .lingua(let codice): if let l = Lingua.trova(codice) { cambia(l) }
            case .sceltaLingua: scegliLingua = true
            }
        case .interprete(let codice):                         // «Jarvis, traduci in tedesco» anche da qui
            if let l = Lingua.trova(codice) { cambia(l) }
        default: break
        }
    }

    private func cambia(_ l: Lingua) {
        scegliLingua = false                                // anche a voce («passa al francese») con la scheda delle lingue aperta
        scelta = l
        motore.prepara(lingua: l)
        orecchio.ferma()
        motore.annuncia("\(l.nome), Sir.")
    }

    private func lato(_ l: Lingua, attivo: Bool, titolo: String) -> some View {
        VStack(spacing: 2) {
            Text(l.bandiera).font(.system(size: 28))
            Text(titolo).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.tenue)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .overlay { if attivo { AngoliOlo(tinta: Color.ciano).padding(-1).allowsHitTesting(false) } }   // 27 ott: chi parla, nel visore
        .background(Color.ciano.opacity(attivo ? 0.18 : 0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(attivo ? 0.9 : 0.3), lineWidth: attivo ? 1.4 : 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .ciano.opacity(attivo ? 0.5 : 0), radius: 8)
        .animation(.easeInOut(duration: 0.3), value: attivo)
    }

    private func tasto(_ titolo: String, icona: String, colore: Color, azione: @escaping () -> Void) -> some View {
        Button { Suoni.tocco(); azione() } label: {
            VStack(spacing: 4) {
                Image(systemName: icona).font(.system(size: 22, weight: .semibold))
                Text(titolo).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1)
            }
            .foregroundStyle(colore)
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(colore.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colore.opacity(0.6), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(StileStark())
        .disabled(motore.fase == .traduco || motore.fase == .parlo)
    }
}

/// La scelta della lingua dell'Interprete: la scheda di JARVIS (caricamento, icona animata, tasti ciano con le bandierine), non
/// il menu di iOS. 26 ott notte (il signore) per l'apertura; 4 nov anche per «Jarvis, cambia lingua» dentro l'Interprete.
struct SceltaLingua: View {
    let scegli: (Lingua) -> Void

    var body: some View {
        CorniceScheda(titolo: "Interprete", sottotitolo: "scelga la lingua", icona: "globe.europe.africa", tinta: Color.ciano) {
            Pannello(titolo: "LINGUA", tinta: Color.ciano) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Lingua.tutte) { l in
                        TastoComando(testo: "\(l.bandiera) \(l.nome)") {   // le bandierine sì, ma nella scheda di JARVIS
                            Suoni.tocco()
                            scegli(l)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Il motore: ascolta, traduce, parla

@MainActor
final class MotoreInterprete: NSObject, ObservableObject {
    enum Lato { case io, altro }
    enum FaseI { case attesa, ascolto, traduco, parlo }
    struct Scambio: Identifiable { let id = UUID(); let chi: Lato; let originale: String; var tradotto: String; let ora: String }

    @Published var fase: FaseI = .attesa
    @Published var lato: Lato = .io
    @Published var scambi: [Scambio] = []
    @Published var parziale = ""
    @Published var stato = "PRONTO"
    var automatico = true
    var suComando: ((ComandoVocale) -> Void)?    // «Jarvis, …» detto nel turno del signore

    private let motore = AVAudioEngine()
    private var riconoscitore: SFSpeechRecognizer?
    private var richiesta: SFSpeechAudioBufferRecognitionRequest?
    private var compito: SFSpeechRecognitionTask?
    private var timer: Timer?
    private var turno = 0
    private var lingua = Lingua.tutte[0]
    private var lettore: AVAudioPlayer?
    private let sintesi = AVSpeechSynthesizer()
    private var attesaVoce: CheckedContinuation<Void, Never>?

    var faseHUD: Fase { fase == .ascolto ? .ascolto : (fase == .attesa ? .attesa : .parlo) }

    override init() { super.init(); sintesi.delegate = self }

    func prepara(lingua: Lingua) {
        self.lingua = lingua
        Task {
            _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { @Sendable s in c.resume(returning: s == .authorized) }
            }
            _ = await AVAudioApplication.requestRecordPermission()
            stato = "PRONTO · TOCCHI «ASCOLTA ME»"
        }
    }

    func ferma() {
        turno += 1
        fermaAscolto()
        lettore?.stop(); lettore = nil
        sintesi.stopSpeaking(at: .immediate)
        rilasciaVoce()
        fase = .attesa
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Ascolta uno dei due lati, poi traduce e parla nell'altra lingua.
    func ascolta(_ chi: Lato, lingua: Lingua) {
        guard fase == .attesa || fase == .ascolto else { return }
        if fase == .ascolto { fermaAscolto(); fase = .attesa }
        self.lingua = lingua
        lato = chi
        let loc = chi == .io ? Lingua.italiano.locale : lingua.locale
        guard let ric = SFSpeechRecognizer(locale: Locale(identifier: loc)), ric.isAvailable else {
            stato = "RICONOSCIMENTO NON DISPONIBILE PER \(lingua.nome.uppercased())"
            Suoni.errore()
            return
        }
        riconoscitore = ric
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try s.setActive(true, options: .notifyOthersOnDeactivation)
            let r = SFSpeechAudioBufferRecognitionRequest()
            r.shouldReportPartialResults = true
            richiesta = r
            let input = motore.inputNode
            let formato = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            MotoreInterprete.collega(input, formato: formato, a: r)
            motore.prepare()
            try motore.start()
            parziale = ""
            fase = .ascolto
            stato = chi == .io ? "LA ASCOLTO, SIR" : "ASCOLTO IN \(lingua.nome.uppercased())"
            Suoni.ascolto()
            turno += 1
            let mio = turno
            compito = MotoreInterprete.riconosci(ric, r) { [weak self] testo, finale, errore in
                Task { @MainActor [weak self] in self?.aggiorna(testo, finale: finale, errore: errore, turno: mio) }
            }
            arma(7)
        } catch {
            stato = "MICROFONO NON DISPONIBILE"
            fermaAscolto()
        }
    }

    private func aggiorna(_ testo: String?, finale: Bool, errore: Bool, turno mio: Int) {
        guard fase == .ascolto, mio == turno else { return }
        if let testo, !testo.isEmpty { parziale = testo; arma(1.4) }
        if finale || errore { concludiAscolto() }
    }

    private func arma(_ secondi: Double) {
        timer?.invalidate()
        let mio = turno
        timer = Timer.scheduledTimer(withTimeInterval: secondi, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.turno == mio else { return }
                self.concludiAscolto()
            }
        }
    }

    private func fermaAscolto() {
        timer?.invalidate(); timer = nil
        if motore.isRunning { motore.stop() }
        motore.inputNode.removeTap(onBus: 0)
        richiesta?.endAudio()
        compito?.cancel()
        richiesta = nil; compito = nil
    }

    private func concludiAscolto() {
        guard fase == .ascolto else { return }
        fermaAscolto()
        let testo = parziale.trimmingCharacters(in: .whitespacesAndNewlines)
        parziale = ""
        guard !testo.isEmpty else { fase = .attesa; stato = "NON HO SENTITO NULLA"; return }
        // nel suo turno, «Jarvis, ascolta lui», «Jarvis, passa al francese»…: è un comando, non una frase da tradurre
        if lato == .io, let c = ComandoVocale.riconosci(testo, serveJarvis: true, dentro: .interprete) {
            fase = .attesa
            stato = "PRONTO"
            suComando?(c)
            return
        }
        Task { await traduciEParla(testo) }
    }

    private func traduciEParla(_ testo: String) async {
        fase = .traduco
        stato = "TRADUCO"
        let chi = lato
        let da = chi == .io ? "it" : lingua.codice
        let a = chi == .io ? lingua.codice : "it"
        let ora = Date().formatted(date: .omitted, time: .shortened)
        scambi.append(Scambio(chi: chi, originale: testo, tradotto: "", ora: ora))
        let idx = scambi.count - 1
        guard let tradotto = await MotoreInterprete.traduci(testo, da: da, a: a), !tradotto.isEmpty else {
            scambi[idx].tradotto = "(traduzione non riuscita)"
            fase = .attesa; stato = "CERVELLO NON RAGGIUNGIBILE"; Suoni.errore()
            return
        }
        scambi[idx].tradotto = tradotto
        fase = .parlo
        stato = chi == .io ? "PARLO IN \(lingua.nome.uppercased())" : "TRADUCO IN ITALIANO"
        await parla(tradotto, lingua: chi == .io ? lingua : Lingua.italiano)
        fase = .attesa
        stato = "PRONTO"
        // a turni: dopo aver parlato per il signore, ascolta subito la risposta dell'altro
        if automatico && chi == .io { ascolta(.altro, lingua: lingua) }
    }

    /// «Jarvis, ripeti»: ridice l'ultima traduzione, nella lingua in cui era stata detta.
    func ripeti(_ straniera: Lingua) {
        guard fase == .attesa, let u = scambi.last, !u.tradotto.isEmpty, u.tradotto != "(traduzione non riuscita)" else { return }
        Task {
            fase = .parlo
            stato = "RIPETO"
            await parla(u.tradotto, lingua: u.chi == .io ? straniera : Lingua.italiano)
            fase = .attesa
            stato = "PRONTO"
        }
    }

    /// Una frase breve di JARVIS in italiano (la lingua scelta, i turni).
    func annuncia(_ testo: String) {
        guard fase == .attesa else { return }
        Task {
            fase = .parlo
            await parla(testo, lingua: Lingua.italiano)
            fase = .attesa
            stato = "PRONTO"
        }
    }

    private func parla(_ testo: String, lingua: Lingua) async {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? s.setActive(true)
        if Impostazioni.voceCloud, let url = URL(string: Impostazioni.indirizzo) {
            let (dati, _) = await VoceCloud.scarica(testo, id: Impostazioni.idVoceCloud, url: url, token: Portachiavi.leggi())
            if let dati, let p = try? AVAudioPlayer(data: dati) {
                p.delegate = self
                lettore = p
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    attesaVoce = c
                    if !p.play() { rilasciaVoce() }
                }
                return
            }
        }
        let u = AVSpeechUtterance(string: testo)
        u.voice = AVSpeechSynthesisVoice(language: lingua.locale) ?? AVSpeechSynthesisVoice(language: String(lingua.locale.prefix(2)))
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            attesaVoce = c
            sintesi.speak(u)
        }
    }

    fileprivate func rilasciaVoce() {
        let c = attesaVoce
        attesaVoce = nil
        lettore = nil
        c?.resume()
    }

    // MARK: Ponti

    nonisolated private static func collega(_ input: AVAudioInputNode, formato: AVAudioFormat, a r: SFSpeechAudioBufferRecognitionRequest) {
        nonisolated(unsafe) let richiesta = r
        input.installTap(onBus: 0, bufferSize: 1024, format: formato) { buffer, _ in richiesta.append(buffer) }
    }

    nonisolated private static func riconosci(_ ric: SFSpeechRecognizer, _ r: SFSpeechAudioBufferRecognitionRequest,
                                              esito: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        ric.recognitionTask(with: r) { ris, err in esito(ris?.bestTranscription.formattedString, ris?.isFinal ?? false, err != nil) }
    }

    static func traduci(_ testo: String, da: String, a: String) async -> String? {
        guard let url = URL(string: Impostazioni.indirizzo) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["traduci": testo, "da": da, "a": a])
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o["traduzione"] as? String
    }
}

extension MotoreInterprete: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) { Task { @MainActor in self.rilasciaVoce() } }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: (any Error)?) { Task { @MainActor in self.rilasciaVoce() } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in self.rilasciaVoce() } }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in self.rilasciaVoce() } }
}
#endif
