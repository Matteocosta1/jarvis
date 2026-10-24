#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreVideo
import CoreMedia

/// Gli occhi di JARVIS: la fotocamera posteriore con un mirino da HUD.
/// Automatico: si apre, aggancia e scatta da solo dopo poco più di un secondo («Jarvis, cosa sto guardando?»).
/// Manuale: mirino con il tasto di scatto (icona 👁️, comodo per le copertine dei dischi).
/// Giro (video): 5 secondi mentre il signore muove il telefono, 4 fotogrammi ben distanziati
/// («fai un giro», scaffali, file di dischi, stanze). Si avvia a voce o con il tasto REC del mirino manuale.
/// Le foto escono già ridotte (lato massimo 1280 px, 1024 nel giro, JPEG) e vanno al cervello, che le guarda e risponde a voce.
/// Occhi aperti in modalità manuale: «Jarvis, …» detto mentre inquadra fa scattare la foto (come il tasto).
enum OcchiAperti {
    static var scatta: (() -> Bool)?
    static var giro: (() -> Bool)?        // «Jarvis, fai un giro»: come il tasto REC
    static var comando: ((ComandoVocale.AzioneScheda) -> Bool)?   // «girati», «zoom», «allarga», «zoom normale»
    /// Build 23: «mostra le etichette», «scansione olografica», «aggancia il bersaglio», «cerca questo sul web»… (Occhi manuali aperti).
    static var stark: ((ComandoOcchi) -> Bool)?
    /// Build 23: la voce di JARVIS dagli Occhi («Ecco cosa ho trovato, Sir.»): la imposta Jarvis.
    static var parla: ((String) -> Void)?
}

struct Occhiata: Identifiable {
    let id = UUID()
    let automatico: Bool
    var video = false
    var cucina = false
    /// Lo zoom con cui si aprono gli Occhi: «guarda da lontano» → 3×, «guarda tutta la stanza» → 0,5×.
    var zoom: CGFloat = 1
    /// Build 23, aperti a voce: già con l'OLOGRAMMA, le ETICHETTE o il bersaglio agganciato (a mano si aprono sempre spenti).
    var olo = false
    var eti = false
    var aggancia = false
}

struct Occhi: View {
    let automatico: Bool
    var video = false
    /// Cucina (icona forchetta): stessa fotocamera, ma con la sua veste calda e tre richieste da scegliere.
    var cucina = false
    /// Lo zoom di partenza (lo sceglie JARVIS dalla richiesta a voce).
    var zoomIniziale: CGFloat = 1
    /// Build 23: aperti a voce con «scansione olografica», «mostra le etichette», «aggancia il bersaglio».
    var oloIniziale = false
    var etiIniziale = false
    var agganciaIniziale = false
    /// Le foto scattate: una, oppure i fotogrammi del giro. Vuoto = chiuso senza scattare.
    let fine: ([Data]) -> Void

    /// Il giro: quanto dura e quanti fotogrammi manda a JARVIS.
    static let durataGiro = 5.0
    static let fotogrammiGiro = 4

    @State private var motore = MotoreOcchi()
    @State private var stato = "AGGANCIO OTTICO"
    @State private var lampo = false
    @State private var scattando = false
    @State private var chiuso = false
    @State private var agganciato = false
    @State private var registrando = false
    @State private var mancano = 5
    @State private var davanti = false          // selfie: fotocamera frontale
    @State private var cambiando = false
    /// Zoom come sulla Fotocamera dell'iPhone: 0,5× grandangolo, 1×, 2×, 3× teleobiettivo (dove c'è), più il pizzico.
    @State private var zoom: CGFloat = 1
    @State private var zoomInizioPizzico: CGFloat?
    @State private var preselezioni: [CGFloat] = [1]
    @State private var zoomMassimo: CGFloat = 1
    /// L'ultimo tocco sullo zoom: in automatico lo scatto aspetta che il signore abbia finito di aggiustare.
    @State private var ultimoTocco = Date()
    /// Cucina: 0 cosa cucino con quello che vedo, 1 che piatto è (e la ricetta), 2 valori nutrizionali.
    @AppStorage("cucinaModo") private var modoCucina = 0
    static let richiesteCucina = ["COSA CUCINO", "CHE PIATTO È", "VALORI"]
    private var tinta: Color { Color.ciano }
    // BUILD 23 — gli Occhi alla Stark (solo gli Occhi manuali): riconoscimento, ologramma, CERCA
    @StateObject private var stark = StatoOcchi()
    @ObservedObject private var guida = GuidaCondivisa.condivisa
    /// Un avviso di CERCA resta 2 secondi al posto dei conti.
    @State private var avviso: String?
    @State private var web: (id: UUID, nome: String, cosa: String, esito: CervelloOcchi.Esito?)?
    /// I pezzi dell'interfaccia sopra la ripresa (i nomi piccoli non ci vanno sopra).
    @State private var riservati: [String: CGRect] = [:]
    /// Gli Occhi manuali (non la Cucina, non l'automatico, non il giro): qui c'è il riconoscimento del mockup 23.
    private var manualeStark: Bool { !automatico && !video && !cucina }
    private var occupato: Bool { scattando || registrando }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaOcchi(sessione: motore.sessione)
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { g in
                            guard !davanti, agganciato else { return }
                            let inizio = zoomInizioPizzico ?? zoom
                            if zoomInizioPizzico == nil { zoomInizioPizzico = zoom }
                            imposta(inizio * g.magnification, animato: false)
                        }
                        .onEnded { _ in zoomInizioPizzico = nil }
                )
                .onTapGesture(coordinateSpace: .global) { p in      // build 23: un tocco su un oggetto, JARVIS aggancia quello
                    guard manualeStark, agganciato, !occupato else { return }
                    stark.tocco(p)
                }
                .onGeometryChange(for: CGSize.self) { $0.size } action: { stark.schermo = $0 }
                .opacity(agganciato && !cambiando ? 1 : 0)
                .animation(.easeOut(duration: 0.4), value: agganciato && !cambiando)
            if !cucina {
                // build 23: il riconoscimento (Occhi manuali) e la freccia della GUIDA di SATELLITE, se è in corso
                RiconoscimentoHUD(stato: stark, manuale: manualeStark && agganciato && !cambiando, riservati: Array(riservati.values), guida: guida.stato)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            MirinoHUD(agganciato: agganciato, scattando: scattando || registrando, tinta: tinta)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if registrando {
                VStack {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                            .shadow(color: .red, radius: 6)
                        Text("REC · \(mancano)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(.top, 70)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            Color.white.opacity(lampo ? 0.85 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                HStack(alignment: manualeStark ? .top : .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("J.A.R.V.I.S.")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .tracking(4)
                        Text(cucina ? "CUCINA · \(video ? "GIRO DEL FRIGO" : Occhi.richiesteCucina[min(modoCucina, 2)])"
                                    : "OCCHI · \(video ? "GIRO" : automatico ? "AUTOMATICO" : "MANUALE")")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(2)
                            .opacity(0.7)
                        if manualeStark {
                            // sotto OCCHI · MANUALE, piccolo, quello che vede (come i sistemi all'avvio)
                            RigheOcchi(righe: righeInfo)
                                .animation(.easeOut(duration: 0.35), value: righeInfo.map(\.chiave))
                        }
                    }
                    .foregroundStyle(tinta)
                    .shadow(color: tinta.opacity(0.6), radius: 6)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riservati["testa"] = $0 }
                    Spacer()
                    Button { Suoni.tocco(); chiudi([]) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(tinta)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(tinta.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("Chiudi")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riservati["chiudi"] = $0 }
                }
                Spacer()
                if !manualeStark {
                    Text(stato)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(tinta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())
                        .contentTransition(.opacity)
                }
                if cucina && !video && !registrando {
                    // cosa vuole sapere: si sceglie prima di scattare, e resta ricordato
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { k in
                            Button { Suoni.tocco(); withAnimation(.easeOut(duration: 0.2)) { modoCucina = k } } label: {
                                Text(Occhi.richiesteCucina[k])
                                    .font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                                    .foregroundStyle(modoCucina == k ? Color.black : tinta)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(modoCucina == k ? tinta : Color.black.opacity(0.5))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(tinta.opacity(0.6), lineWidth: 1))
                            }
                            .buttonStyle(StileStark())
                        }
                    }
                }
                if manualeStark {
                    // le tre icone sopra lo zoom: ETICHETTE, OLOGRAMMA (si accendono e si spengono), CERCA (il solo bersaglio)
                    HStack(alignment: .top, spacing: 18) {
                        TastoOcchi(tipo: .etichette, titolo: "ETICHETTE", acceso: stark.eti) {
                            guard !occupato else { return }
                            Suoni.tocco(); mettiEtichette(!stark.eti)
                        }
                        TastoOcchi(tipo: .ologramma, titolo: "OLOGRAMMA", acceso: stark.olo) {
                            guard !occupato else { return }
                            Suoni.tocco(); mettiOlogramma(!stark.olo)
                        }
                        TastoOcchi(tipo: .cerca, titolo: "CERCA", acceso: false) {
                            guard !occupato else { return }
                            Suoni.tocco(); cerca()
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riservati["icone"] = $0 }
                }
                if !video && !davanti && agganciato && (preselezioni.count > 1 || zoomMassimo > 1.05) {
                    selettoreZoom
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riservati["zoom"] = $0 }
                }
                if !automatico && !video {
                    HStack(spacing: 34) {
                        // selfie: si vede lei e chi c'è dietro
                        Button { Task { await giraFotocamera() } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(tinta)
                                .frame(width: 54, height: 54)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(tinta.opacity(0.6), lineWidth: 1.5))
                        }
                        .buttonStyle(StileStark())
                        .disabled(!agganciato || scattando || registrando || cambiando)
                        .accessibilityLabel(davanti ? "Fotocamera posteriore" : "Selfie")
                        Button { scatta() } label: {
                            ZStack {
                                Circle().stroke(tinta, lineWidth: 3).frame(width: 74, height: 74)
                                Circle().fill(tinta.opacity(scattando ? 0.9 : 0.25)).frame(width: 60, height: 60)
                                Image(systemName: cucina ? "fork.knife" : "eye").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                            }
                            .shadow(color: tinta.opacity(0.7), radius: 10)
                        }
                        .buttonStyle(StileStark())
                        .disabled(!agganciato || scattando || registrando)
                        .accessibilityLabel("Scatta")
                        // giro di 5 secondi: muova il telefono lungo lo scaffale o la stanza
                        Button { Task { await giro() } } label: {
                            ZStack {
                                Circle().stroke(Color.red.opacity(0.85), lineWidth: 2).frame(width: 54, height: 54)
                                Text("REC").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            }
                            .shadow(color: .red.opacity(0.5), radius: 8)
                        }
                        .buttonStyle(StileStark())
                        .disabled(!agganciato || scattando || registrando)
                        .accessibilityLabel("Giro di cinque secondi")
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riservati["tasti"] = $0 }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // CERCA: il foglio sale dal basso, la fotocamera resta viva sopra
            if let w = web {
                VStack {
                    Spacer()
                    FoglioWebOcchi(nome: w.nome, cosa: w.cosa, esito: w.esito) { withAnimation(.easeOut(duration: 0.25)) { web = nil }; riservati["web"] = nil }
                        .frame(maxHeight: stark.schermo.height * 0.56)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { riservati["web"] = $0 }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(w.id)
            }
        }
        .statusBarHidden()
        .task { await prepara() }
        .onDisappear {
            OcchiAperti.scatta = nil; OcchiAperti.giro = nil; OcchiAperti.comando = nil; OcchiAperti.stark = nil
            stark.visore.imposta(attivo: false, olo: false, bersaglio: nil)
            motore.ferma()
        }
    }

    // MARK: Build 23 — riconoscimento, ologramma, CERCA

    /// Le righe sotto OCCHI · MANUALE: l'aggancio, lo scatto, un avviso di CERCA, i conti; se no «INQUADRI E SCATTI».
    private var righeInfo: [(chiave: String, testo: String)] {
        if !agganciato || occupato { return [("s", stato)] }
        if let avviso { return [("s", avviso)] }
        if stark.eti || stark.olo, !stark.conti.isEmpty { return stark.conti }
        return [("s", "INQUADRI E SCATTI")]
    }

    private func mettiOlogramma(_ v: Bool) {
        stark.olo = v
        if !stark.olo && !stark.eti { stark.spento() } else { stark.aggiorna() }
    }

    private func mettiEtichette(_ v: Bool) {
        stark.eti = v
        if !stark.olo && !stark.eti { stark.spento() } else { stark.aggiorna() }
    }

    /// Un avviso di CERCA al posto dei conti per 2 secondi.
    private func avvisa(_ t: String) {
        avviso = t
        Task {
            try? await Task.sleep(for: .seconds(2))
            if avviso == t { avviso = nil }
        }
    }

    /// CERCA: il solo bersaglio (quello col mirino pieno o toccato) va al cervello, che lo cerca sul web e risponde nel foglio,
    /// con il riassunto e tre fonti. Le persone no (niente ricerca di volti).
    private func cerca() {
        guard let o = stark.obiettivo, stark.olo || stark.eti else {
            avvisa(stark.olo || stark.eti ? "TOCCHI UN OGGETTO DA CERCARE" : "ACCENDA ETICHETTE O OLOGRAMMA")
            return
        }
        if o.tipo == .persona {
            avvisa("LE PERSONE NON LE CERCO")
            OcchiAperti.parla?("Le persone non le cerco sul web, Sir.")
            return
        }
        stark.blocca()                                          // il mirino resta su quello cercato
        let titolo = stark.titolo(o) ?? ""
        let cosa = titolo.isEmpty ? o.nome : titolo
        let id = UUID()
        withAnimation(.easeOut(duration: 0.3)) { web = (id: id, nome: o.nome, cosa: cosa, esito: nil) }
        Suoni.schedaApre()
        let visore = stark.visore, box = o.box, nome = o.nome
        Task {
            let foto = await Task.detached(priority: .userInitiated) { visore.ritaglio(box, lato: 768) }.value
            let esito = await CervelloOcchi.cerca(nome: nome, cosa: cosa, immagine: foto)
            guard web?.id == id, !chiuso else { return }
            web?.esito = esito
            switch esito {
            case .trovato: Suoni.schedaPronta(); OcchiAperti.parla?("Ecco cosa ho trovato, Sir.")
            case .persona: OcchiAperti.parla?("Le persone non le cerco sul web, Sir.")
            case .errore: Suoni.errore()
            }
        }
    }

    // MARK: Lavoro

    private func prepara() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            stato = "ACCESSO NEGATO · IMPOSTAZIONI › JARVIS › FOTOCAMERA"
            Suoni.errore()
            try? await Task.sleep(for: .seconds(2.5))
            chiudi([])
            return
        }
        if manualeStark {
            // build 23: i fotogrammi piccoli (come l'anteprima) vanno al riconoscimento, sulla coda della fotocamera
            let visore = stark.visore
            motore.fotogramma = { px, frontale, fuoco in visore.analizza(px, frontale: frontale, fuoco: fuoco) }
        }
        let pronto = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            motore.avvia { ok in c.resume(returning: ok) }
        }
        guard pronto else {
            stato = "FOTOCAMERA NON DISPONIBILE"
            Suoni.errore()
            try? await Task.sleep(for: .seconds(2))
            chiudi([])
            return
        }
        leggiZoom()
        if !davanti && abs(zoomIniziale - 1) > 0.05 { imposta(zoomIniziale, animato: true) }
        agganciato = true
        Suoni.aperturaCamera()
        if video {
            stato = "SISTEMI OTTICI ATTIVI"
            try? await Task.sleep(for: .milliseconds(700))     // il tempo di mettere a fuoco
            await giro()
        } else if automatico {
            stato = zoom > 1.05 || zoom < 0.95 ? "ANALISI OTTICA · \(Occhi.etichetta(zoom))" : "ANALISI OTTICA"
            ultimoTocco = Date()
            // scatta da solo appena nessuno tocca lo zoom per un attimo (col teleobiettivo un po' di più: deve mettere a fuoco)
            while !chiuso && !scattando {
                try? await Task.sleep(for: .milliseconds(100))
                let attesa = zoom > 1.5 ? 1.8 : 1.3
                if Date().timeIntervalSince(ultimoTocco) >= attesa { break }
            }
            scatta()
        } else {
            stato = cucina ? "INQUADRI FRIGO, DISPENSA O PIATTO" : "INQUADRI E SCATTI"
            OcchiAperti.scatta = {                     // a voce: «Jarvis, guarda là in fondo»
                guard agganciato, !scattando, !chiuso, !cambiando else { return false }
                scatta()
                return true
            }
            OcchiAperti.comando = { a in               // a voce: i tasti della fotocamera
                guard agganciato, !scattando, !registrando, !chiuso, !cambiando else { return false }
                switch a {
                case .occhiGira: Task { await giraFotocamera() }
                case .occhiZoomAvanti:
                    let dopo = preselezioni.first(where: { $0 > zoom + 0.05 }) ?? min(zoom * 2, zoomMassimo)
                    imposta(dopo, animato: true)
                case .occhiZoomIndietro:
                    let prima = preselezioni.last(where: { $0 < zoom - 0.05 }) ?? (preselezioni.first ?? 1)
                    imposta(prima, animato: true)
                case .occhiZoomNormale: imposta(1, animato: true)
                default: return false
                }
                Suoni.tocco()
                return true
            }
            OcchiAperti.giro = {                       // a voce: «Jarvis, fai un giro»
                guard agganciato, !scattando, !registrando, !chiuso, !cambiando else { return false }
                Task { await giro() }
                return true
            }
            if manualeStark {
                // deciso dal signore (24 ott): all'apertura niente acceso; aperti a voce, acceso solo quello che chiede
                stark.olo = oloIniziale
                stark.eti = etiIniziale
                stark.aggiorna()
                OcchiAperti.stark = { c in                 // a voce: «mostra le etichette», «scansione olografica»…
                    guard agganciato, !chiuso else { return false }
                    switch c {
                    case .etichette(let v): mettiEtichette(v)
                    case .ologramma(let v): mettiOlogramma(v); if v { stark.aggancia() }
                    case .aggancia: mettiOlogramma(true); stark.aggancia()
                    case .cerca: cerca()
                    }
                    return true
                }
                if agganciaIniziale {
                    try? await Task.sleep(for: .milliseconds(900))
                    if !chiuso { stark.aggancia() }
                }
            }
        }
    }

    /// Fotocamera davanti (selfie) o dietro.
    private func giraFotocamera() async {
        guard !cambiando else { return }
        Suoni.tocco()
        cambiando = true
        let nuova = !davanti
        let m = motore
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            m.avvia(posizione: nuova ? .front : .back) { ok in c.resume(returning: ok) }
        }
        if ok {
            davanti = nuova
            leggiZoom()
            stato = nuova ? "SELFIE · LEI E CHI LE STA DIETRO" : (cucina ? "INQUADRI FRIGO, DISPENSA O PIATTO" : "INQUADRI E SCATTI")
        }
        try? await Task.sleep(for: .milliseconds(250))
        cambiando = false
    }

    /// I tasti dello zoom, come nella Fotocamera: quello attivo è pieno e mostra lo zoom esatto mentre si pizzica.
    private var selettoreZoom: some View {
        HStack(spacing: 8) {
            ForEach(preselezioni, id: \.self) { p in
                let attivo = attivaPreselezione == p
                Button { Suoni.tocco(); UISelectionFeedbackGenerator().selectionChanged(); imposta(p, animato: true) } label: {
                    Text(attivo ? Occhi.etichetta(zoom) : Occhi.etichetta(p, corta: true))
                        .font(.system(size: attivo ? 12 : 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(attivo ? Color.black : tinta)
                        .frame(width: attivo ? 44 : 36, height: attivo ? 44 : 36)
                        .background(attivo ? tinta : Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(tinta.opacity(0.6), lineWidth: 1))
                        .shadow(color: tinta.opacity(attivo ? 0.6 : 0), radius: 6)
                }
                .buttonStyle(StileStark())
                .animation(.spring(duration: 0.25), value: attivo)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }

    /// La preselezione «di competenza» dello zoom attuale (2,4× accende il 2×).
    private var attivaPreselezione: CGFloat {
        preselezioni.last(where: { zoom >= $0 - 0.05 }) ?? preselezioni.first ?? 1
    }

    static func etichetta(_ z: CGFloat, corta: Bool = false) -> String {
        if z < 0.95 { return corta ? "0,5" : "0,5×" }
        let tondo = (z * 10).rounded() / 10
        let testo = tondo == tondo.rounded() ? String(Int(tondo)) : String(format: "%.1f", Double(tondo)).replacingOccurrences(of: ".", with: ",")
        return corta ? testo : "\(testo)×"
    }

    private func leggiZoom() {
        let info = motore.zoomDisponibile()
        preselezioni = info.preselezioni
        zoomMassimo = info.massimo
        zoom = 1
    }

    private func imposta(_ valore: CGFloat, animato: Bool) {
        let minimo = preselezioni.first ?? 1
        let v = min(max(valore, minimo), zoomMassimo)
        zoom = v
        ultimoTocco = Date()
        if automatico && !scattando { stato = "ANALISI OTTICA · \(Occhi.etichetta(v))" }
        motore.zoom(v, animato: animato)
    }

    private func scatta() {
        guard agganciato, !scattando, !chiuso, !cambiando else { return }
        scattando = true
        stato = "ACQUISIZIONE"
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Suoni.tocco()
        withAnimation(.easeOut(duration: 0.06)) { lampo = true }
        withAnimation(.easeIn(duration: 0.45).delay(0.06)) { lampo = false }
        motore.scatta(veloce: false) { dati in
            let jpeg = dati.flatMap { Occhi.riduci($0) }
            Task { @MainActor in chiudi(jpeg.map { [$0] } ?? []) }
        }
    }

    /// Il giro: 5 secondi, 4 fotogrammi distribuiti nel tempo (circa uno ogni secondo e un quarto), poi si chiude da solo.
    private func giro() async {
        guard agganciato, !scattando, !registrando, !chiuso else { return }
        registrando = true
        stato = "ACQUISIZIONE IN MOVIMENTO"
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        let inizio = Date()
        let passo = Occhi.durataGiro / Double(Occhi.fotogrammiGiro)
        var fotogrammi: [Data] = []
        let conto = Task { @MainActor in                       // il conto alla rovescia sullo schermo
            for s in stride(from: Int(Occhi.durataGiro), through: 1, by: -1) {
                withAnimation { mancano = s }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        for k in 0..<Occhi.fotogrammiGiro {
            let quando = passo * (Double(k) + 0.4)               // 0,5 · 1,75 · 3 · 4,25 secondi
            let attesa = quando - Date().timeIntervalSince(inizio)
            if attesa > 0 { try? await Task.sleep(for: .seconds(attesa)) }
            guard !chiuso else { conto.cancel(); return }
            let dati = await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
                motore.scatta(veloce: true) { d in c.resume(returning: d) }
            }
            if let dati, let jpeg = Occhi.riduci(dati, lato: 1024) { fotogrammi.append(jpeg) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        let resto = Occhi.durataGiro - Date().timeIntervalSince(inizio)
        if resto > 0 { try? await Task.sleep(for: .seconds(resto)) }
        conto.cancel()
        guard !chiuso else { return }
        registrando = false
        stato = "ANALISI"
        Suoni.tocco()
        chiudi(fotogrammi)
    }

    private func chiudi(_ dati: [Data]) {
        guard !chiuso else { return }
        chiuso = true
        OcchiAperti.scatta = nil
        OcchiAperti.giro = nil
        OcchiAperti.comando = nil
        OcchiAperti.stark = nil
        stark.visore.imposta(attivo: false, olo: false, bersaglio: nil)
        motore.ferma()
        fine(dati)
    }

    /// Lato massimo 1280 px (1024 nel giro) e JPEG al 70%: la foto resta leggera per il cervello, ma la copertina si legge bene.
    /// Fatto con ImageIO: gira fuori dal thread principale e raddrizza la foto secondo l'orientamento del telefono.
    nonisolated static func riduci(_ dati: Data, lato: Int = 1280) -> Data? {
        guard let sorgente = CGImageSourceCreateWithData(dati as CFData, nil) else { return nil }
        let opzioni: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: lato,
        ]
        guard let piccola = CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary) else { return nil }
        let uscita = NSMutableData()
        guard let destinazione = CGImageDestinationCreateWithData(uscita as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destinazione, piccola, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destinazione) else { return nil }
        return uscita as Data
    }
}

// MARK: - Mirino da HUD: angoli, reticolo che gira, riga di scansione

struct MirinoHUD: View {
    let agganciato: Bool
    let scattando: Bool
    var tinta: Color = .ciano

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let w = Double(size.width), h = Double(size.height)
                let c = CGPoint(x: w / 2, y: h / 2)
                let lato = min(w, h) * 0.72
                let colore = scattando ? Color.orange : tinta
                let x0 = (w - lato) / 2, y0 = (h - lato) / 2
                let braccio = lato * 0.12

                // angoli del riquadro
                var angoli = Path()
                for (ax, ay, dx, dy) in [(x0, y0, 1.0, 1.0), (x0 + lato, y0, -1.0, 1.0), (x0, y0 + lato, 1.0, -1.0), (x0 + lato, y0 + lato, -1.0, -1.0)] {
                    angoli.move(to: CGPoint(x: ax, y: ay + dy * braccio))
                    angoli.addLine(to: CGPoint(x: ax, y: ay))
                    angoli.addLine(to: CGPoint(x: ax + dx * braccio, y: ay))
                }
                gc.stroke(angoli, with: .color(colore.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // reticolo al centro: due archi che girano in senso opposto
                let giro = t * (agganciato ? 0.8 : 2.4)
                for (r, verso, lung) in [(lato * 0.16, 1.0, 0.6), (lato * 0.21, -1.0, 0.35)] {
                    var arco = Path()
                    let inizio = Angle(radians: giro * verso)
                    arco.addArc(center: c, radius: r, startAngle: inizio, endAngle: inizio + .radians(2 * .pi * lung), clockwise: false)
                    gc.stroke(arco, with: .color(colore.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                var croce = Path()
                croce.move(to: CGPoint(x: c.x - 8, y: c.y)); croce.addLine(to: CGPoint(x: c.x + 8, y: c.y))
                croce.move(to: CGPoint(x: c.x, y: c.y - 8)); croce.addLine(to: CGPoint(x: c.x, y: c.y + 8))
                gc.stroke(croce, with: .color(colore.opacity(0.8)), lineWidth: 1)

                // riga di scansione che scende nel riquadro
                let p = (t * 0.55).truncatingRemainder(dividingBy: 1)
                let y = y0 + lato * p
                let riga = Path(CGRect(x: x0, y: y - 1, width: lato, height: 2))
                gc.fill(riga, with: .color(colore.opacity(0.55)))
                let scia = Path(CGRect(x: x0, y: max(y0, y - 40), width: lato, height: min(40, y - y0)))
                gc.fill(scia, with: .linearGradient(Gradient(colors: [colore.opacity(0), colore.opacity(0.14)]),
                                                    startPoint: CGPoint(x: 0, y: y - 40), endPoint: CGPoint(x: 0, y: y)))

                // tacche laterali con lettura «telemetrica»
                for k in 0..<12 {
                    let ty = y0 + lato * Double(k) / 11
                    var tacca = Path()
                    tacca.move(to: CGPoint(x: x0 - 14, y: ty)); tacca.addLine(to: CGPoint(x: x0 - (k % 3 == 0 ? 4 : 8), y: ty))
                    tacca.move(to: CGPoint(x: x0 + lato + 14, y: ty)); tacca.addLine(to: CGPoint(x: x0 + lato + (k % 3 == 0 ? 4 : 8), y: ty))
                    gc.stroke(tacca, with: .color(colore.opacity(0.45)), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Anteprima della fotocamera

struct AnteprimaOcchi: UIViewRepresentable {
    let sessione: AVCaptureSession

    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var anteprima: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Vista {
        let v = Vista()
        v.backgroundColor = .black
        v.anteprima.session = sessione
        v.anteprima.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ v: Vista, context: Context) {}
}

// MARK: - Motore della fotocamera (lavora su una coda sua, fuori dal thread principale)

nonisolated final class MotoreOcchi: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sessione = AVCaptureSession()
    private let uscita = AVCapturePhotoOutput()
    private let coda = DispatchQueue(label: "it.discosizer.jarvis.occhi")
    /// Build 23: i fotogrammi per il riconoscimento degli Occhi manuali (piccoli come l'anteprima, BGRA, verticali, non specchiati),
    /// su una coda loro. Nil (Profiler, Traccia): niente uscita video, la fotocamera è quella di sempre. Va impostato prima di `avvia`.
    var fotogramma: (@Sendable (CVPixelBuffer, _ frontale: Bool, _ fuoco: Double) -> Void)?
    private let video = AVCaptureVideoDataOutput()
    private let codaVideo = DispatchQueue(label: "it.discosizer.jarvis.occhi.video")
    private var configurata = false
    private var consegna: (@Sendable (Data?) -> Void)?
    /// Quale fotocamera è montata: quella dietro (di solito) o quella davanti (selfie nel Profiler).
    private var montata: AVCaptureDevice.Position = .back
    private var camera: AVCaptureDevice?
    /// Fattore del dispositivo che corrisponde a «1×» (con il grandangolo è 2: lo 0,5× è il fattore 1).
    private var base: CGFloat = 1
    private var passaggi: [CGFloat] = []

    /// Le preselezioni da mostrare (0,5× se c'è il grandangolo, 1×, 2×, e il teleobiettivo vero) e lo zoom massimo sensato.
    func zoomDisponibile() -> (preselezioni: [CGFloat], massimo: CGFloat) {
        coda.sync {
            guard let cam = camera, montata == .back else { return ([1], 1) }
            var p: [CGFloat] = []
            if base > 1 { p.append(0.5) }
            p.append(1)
            p.append(2)
            for x in passaggi.dropFirst(base > 1 ? 1 : 0) {
                let m = (x / base * 10).rounded() / 10
                if m > 1.05 && !p.contains(m) { p.append(m) }
            }
            let massimo = min(cam.maxAvailableVideoZoomFactor / base, 15)
            p = p.filter { $0 <= massimo + 0.01 }.sorted()
            return (p, max(massimo, 1))
        }
    }

    /// Zoom «mostrato» (0,5×, 1×, 3×…): lo traduce nel fattore del dispositivo. animato = scivola come nella Fotocamera.
    func zoom(_ mostrato: CGFloat, animato: Bool) {
        coda.async {
            guard let cam = self.camera, (try? cam.lockForConfiguration()) != nil else { return }
            let f = min(max(mostrato * self.base, cam.minAvailableVideoZoomFactor), cam.maxAvailableVideoZoomFactor)
            if animato { cam.ramp(toVideoZoomFactor: f, withRate: 12) } else { cam.cancelVideoZoomRamp(); cam.videoZoomFactor = f }
            cam.unlockForConfiguration()
        }
    }

    func avvia(posizione: AVCaptureDevice.Position = .back, pronto: @escaping @Sendable (Bool) -> Void) {
        coda.async {
            if !self.configurata || posizione != self.montata {
                self.sessione.beginConfiguration()
                self.sessione.sessionPreset = .photo
                for vecchio in self.sessione.inputs { self.sessione.removeInput(vecchio) }
                // dietro: la fotocamera «virtuale» che unisce grandangolo, principale e teleobiettivo (passa da sola tra le lenti)
                let virtuale = posizione == .back
                    ? (AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                       ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                       ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back))
                    : nil
                guard let cam = virtuale ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: posizione)
                        ?? AVCaptureDevice.default(for: .video),          // sul Mac: la webcam, qualunque sia
                      let ingresso = try? AVCaptureDeviceInput(device: cam),
                      self.sessione.canAddInput(ingresso) else {
                    self.sessione.commitConfiguration()
                    pronto(false)
                    return
                }
                self.sessione.addInput(ingresso)
                if !self.sessione.outputs.contains(self.uscita) {
                    guard self.sessione.canAddOutput(self.uscita) else { self.sessione.commitConfiguration(); pronto(false); return }
                    self.sessione.addOutput(self.uscita)
                }
                if self.fotogramma != nil {
                    // build 23: l'uscita video per il riconoscimento (se non si può aggiungere, gli Occhi restano quelli di sempre)
                    if !self.sessione.outputs.contains(self.video), self.sessione.canAddOutput(self.video) {
                        self.video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        self.video.alwaysDiscardsLateVideoFrames = true
                        self.video.automaticallyConfiguresOutputBufferDimensions = false
                        self.video.deliversPreviewSizedOutputBuffers = true      // piccoli come l'anteprima: veloci per Vision
                        self.video.setSampleBufferDelegate(self, queue: self.codaVideo)
                        self.sessione.addOutput(self.video)
                    }
                    if let c = self.video.connection(with: .video) {
                        if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }          // verticale, come lo schermo
                        if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = false }
                    }
                }
                self.sessione.commitConfiguration()
                self.montata = posizione
                self.camera = cam
                // con la fotocamera virtuale lo zoom 1.0 è il grandangolo: la base «1×» è il primo punto di passaggio
                let passaggi = cam.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
                self.base = (cam.deviceType == .builtInTripleCamera || cam.deviceType == .builtInDualWideCamera) ? (passaggi.first ?? 1) : 1
                self.passaggi = passaggi
                if (try? cam.lockForConfiguration()) != nil {
                    if cam.isFocusModeSupported(.continuousAutoFocus) { cam.focusMode = .continuousAutoFocus }
                    cam.videoZoomFactor = min(max(self.base, cam.minAvailableVideoZoomFactor), cam.maxAvailableVideoZoomFactor)
                    cam.unlockForConfiguration()
                }
                self.configurata = true
            }
            if !self.sessione.isRunning { self.sessione.startRunning() }
            pronto(self.sessione.isRunning)
        }
    }

    func ferma() {
        coda.async { if self.sessione.isRunning { self.sessione.stopRunning() } }
    }

    /// veloce: per i fotogrammi del giro, scatto immediato senza elaborazioni pesanti.
    func scatta(veloce: Bool, _ fine: @escaping @Sendable (Data?) -> Void) {
        coda.async {
            guard self.sessione.isRunning, self.consegna == nil else { fine(nil); return }
            self.consegna = fine
            let impostazioni = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            if veloce { impostazioni.photoQualityPrioritization = .speed }
            self.uscita.capturePhoto(with: impostazioni, delegate: self)
        }
    }

    /// Build 23: un fotogramma per il riconoscimento, con la sua focale in pixel (campo visivo e zoom di adesso).
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let f = fotogramma, let px = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let porta = connection.inputPorts.first
        let frontale = porta?.sourceDevicePosition == .front
        let lato = max(CVPixelBufferGetWidth(px), CVPixelBufferGetHeight(px))
        var fuoco = Ottica.fuoco(campo: 70, latoLungo: lato)
        if let cam = (porta?.input as? AVCaptureDeviceInput)?.device {
            fuoco = Ottica.fuoco(campo: Ottica.campo(cam), latoLungo: lato, zoom: cam.videoZoomFactor)
        }
        f(px, frontale, fuoco)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
        let dati = error == nil ? photo.fileDataRepresentation() : nil
        coda.async {
            let f = self.consegna
            self.consegna = nil
            f?(dati)
        }
    }
}
#endif
