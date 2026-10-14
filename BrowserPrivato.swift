#if os(iOS)
import SwiftUI
import Combine
import WebKit
import LocalAuthentication

/// Browser di JARVIS: lo guida il signore con le dita, JARVIS non vede cosa c'è sullo schermo.
/// Due modalità: Incognito (niente cronologia, cookie o accessi salvati: sparisce tutto alla chiusura)
/// e Normale (ricorda gli accessi ai siti). I pop-up si aprono in una finestra sopra la pagina e si chiudono con la X.
/// Sblocco con Face ID facoltativo; schermo coperto quando l'app va in secondo piano.
/// Serve la frase NSFaceIDUsageDescription nelle Info dell'app.
final class Navigatore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    let incognito: Bool
    @Published var indirizzo = ""
    @Published var carica = false
    @Published var indietro = false
    @Published var avanti = false
    @Published var popup: WKWebView?          // finestra pop-up aperta dalla pagina
    @Published var titoloPopup = ""

    init(incognito: Bool) {
        self.incognito = incognito
        let c = WKWebViewConfiguration()
        c.websiteDataStore = incognito ? .nonPersistent() : .default()
        c.allowsInlineMediaPlayback = true
        c.preferences.javaScriptCanOpenWindowsAutomatically = true     // i pop-up dei siti sono permessi
        web = WKWebView(frame: .zero, configuration: c)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
    }

    /// Un indirizzo (es. «sito.com») si apre; qualsiasi altra cosa si cerca su Google.
    func vai(_ testo: String) {
        let t = testo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var url: URL?
        if t.contains(" ") || !t.contains(".") {
            var c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "q", value: t)]
            url = c?.url
        } else {
            url = URL(string: t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") ? t : "https://" + t)
        }
        if let url { web.load(URLRequest(url: url)) }
    }

    func chiudiPopup() {
        popup?.stopLoading()
        popup = nil
        titoloPopup = ""
    }

    private func aggiorna() {
        if let u = web.url?.absoluteString { indirizzo = u }
        indietro = web.canGoBack
        avanti = web.canGoForward
        carica = web.isLoading
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { if webView === web { aggiorna() } }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { if webView === web { aggiorna() } }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === web {
            aggiorna()
            // cronologia: solo in modalità Normale (l'incognito non lascia tracce)
            if !incognito, let u = webView.url { Cronologia.aggiungi(titolo: webView.title ?? "", url: u) }
        } else if webView === popup { titoloPopup = webView.title ?? webView.url?.host() ?? "" }
    }

    /// Apre un indirizzo preciso (dalla cronologia).
    func apri(_ url: URL) { web.load(URLRequest(url: url)) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { if webView === web { aggiorna() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { if webView === web { aggiorna() } }

    // Il sito vuole aprire una nuova finestra (pop-up, accesso con Google, banner…): la mostro sopra la pagina.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if webView === popup {                      // un pop-up che apre un altro pop-up: resta nella stessa finestra
            webView.load(navigationAction.request)
            return nil
        }
        let nuova = WKWebView(frame: .zero, configuration: configuration)
        nuova.navigationDelegate = self
        nuova.uiDelegate = self
        nuova.allowsBackForwardNavigationGestures = true
        popup = nuova
        titoloPopup = navigationAction.request.url?.host() ?? "Finestra"
        return nuova
    }

    // Il sito chiude da solo il suo pop-up (es. dopo l'accesso): lo tolgo e la pagina sotto si aggiorna.
    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { chiudiPopup() }
    }

    // Avvisi e conferme JavaScript: senza risposta alcuni siti si bloccherebbero.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        _ = await Navigatore.mostraAvviso(message, conAnnulla: false)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Navigatore.mostraAvviso(message, conAnnulla: true)
    }

    private static func mostraAvviso(_ testo: String, conAnnulla: Bool) async -> Bool {
        guard let scena = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var sopra = scena.keyWindow?.rootViewController else { return !conAnnulla }
        while let p = sopra.presentedViewController { sopra = p }
        let finestra = sopra
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let a = UIAlertController(title: nil, message: testo, preferredStyle: .alert)
            if conAnnulla { a.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in c.resume(returning: false) }) }
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in c.resume(returning: true) })
            finestra.present(a, animated: true)
        }
    }
}

struct WebVista: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Contenitore: sblocco con Face ID e scelta Incognito/Normale (cambiando modalità si riapre una pagina nuova).
struct BrowserPrivato: View {
    @Environment(\.dismiss) private var chiudi
    @Environment(\.scenePhase) private var fase
    @AppStorage("browserFaceID") private var conFaceID = true
    @AppStorage("browserIncognito") private var incognito = true
    @State private var sbloccato = false
    @State private var sblocco = false
    @State private var errore: String?

    var body: some View {
        PaginaBrowser(incognito: $incognito, conFaceID: $conFaceID, attivo: sbloccato || !conFaceID) { chiudi() }
            .id(incognito)
            .overlay { if (conFaceID && !sbloccato) || fase != .active { copertura } }
            .onChange(of: fase) {
                if fase == .background, conFaceID { sbloccato = false }
                if fase == .active, conFaceID, !sbloccato { Task { await sblocca() } }
            }
            .task { if conFaceID { await sblocca() } else { sbloccato = true } }
            .aperturaHUD("Browser")
    }

    private var copertura: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill").font(.system(size: 54))
                Text("BROWSER PRIVATO")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(4)
                if let errore {
                    Text(errore).font(.footnote).foregroundStyle(Color.tenue)
                }
                if fase == .active {
                    Button { Task { await sblocca() } } label: {
                        Label("Sblocca", systemImage: "faceid")
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .overlay(Capsule().stroke(Color.ciano))
                    }
                    Button("Chiudi") { chiudi() }.foregroundStyle(Color.tenue)
                }
            }
            .foregroundStyle(Color.ciano)
        }
    }

    private func sblocca() async {
        guard !sblocco, !sbloccato else { return }
        sblocco = true
        defer { sblocco = false }
        let ctx = LAContext()
        var problema: NSError?
        // senza codice o Face ID impostati sull'iPhone non c'è niente da chiedere
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problema) else { sbloccato = true; return }
        do {
            sbloccato = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Sbloccare il browser privato di JARVIS")
            errore = nil
        } catch {
            errore = "Non sbloccato. Tocchi «Sblocca» per riprovare."
        }
    }
}

struct PaginaBrowser: View {
    @Binding var incognito: Bool
    @Binding var conFaceID: Bool
    let attivo: Bool
    let chiudi: () -> Void
    @StateObject private var nav: Navigatore
    @State private var barra = ""
    @State private var mostraCronologia = false
    @FocusState private var scrivendo: Bool

    init(incognito: Binding<Bool>, conFaceID: Binding<Bool>, attivo: Bool, chiudi: @escaping () -> Void) {
        _incognito = incognito
        _conFaceID = conFaceID
        self.attivo = attivo
        self.chiudi = chiudi
        _nav = StateObject(wrappedValue: Navigatore(incognito: incognito.wrappedValue))
    }

    private var accento: Color { incognito ? Color(red: 0.75, green: 0.55, blue: 1.0) : Color.ciano }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { chiudi() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Chiudi il browser")
                HStack(spacing: 6) {
                    Image(systemName: incognito ? "eyeglasses" : "lock.shield").font(.footnote)
                    TextField(incognito ? "Incognito: cerchi o scriva un indirizzo" : "Cerchi o scriva un indirizzo", text: $barra)
                        .keyboardType(.webSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($scrivendo)
                        .foregroundStyle(.white)
                        .onSubmit { nav.vai(barra); scrivendo = false }
                    if nav.carica { ProgressView().controlSize(.small).tint(accento) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(accento.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accento.opacity(0.35), lineWidth: 0.8))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            WebVista(web: nav.web)
                .overlay { if nav.popup != nil { finestraPopup } }

            HStack {
                Button { nav.web.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!nav.indietro).accessibilityLabel("Indietro")
                Spacer()
                Button { nav.web.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!nav.avanti).accessibilityLabel("Avanti")
                Spacer()
                Button { nav.web.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Ricarica")
                Spacer()
                Button { scrivendo = false; mostraCronologia = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Cronologia")
                Spacer()
                Button { incognito.toggle() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: incognito ? "eyeglasses" : "eye")
                        Text(incognito ? "INCOGNITO" : "NORMALE").font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                }
                .accessibilityLabel(incognito ? "Navigazione in incognito: tocchi per la normale" : "Navigazione normale: tocchi per l'incognito")
                Spacer()
                Button { conFaceID.toggle() } label: { Image(systemName: conFaceID ? "faceid" : "lock.open") }
                    .accessibilityLabel(conFaceID ? "Blocco Face ID attivo" : "Blocco Face ID spento")
            }
            .font(.system(size: 19))
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .foregroundStyle(accento)
        .background(Color.fondo.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: nav.popup != nil)
        .onChange(of: nav.indirizzo) { if !scrivendo { barra = nav.indirizzo } }
        .onChange(of: attivo) { if attivo, barra.isEmpty { scrivendo = true } }
        .onAppear { if attivo, barra.isEmpty { scrivendo = true } }
        .sheet(isPresented: $mostraCronologia) {
            VistaCronologiaBrowser(incognito: incognito, accento: accento) { url in
                mostraCronologia = false
                nav.apri(url)
            }
        }
    }

    /// Il pop-up del sito, in una finestra sopra la pagina: la X lo chiude.
    private var finestraPopup: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { nav.chiudiPopup() }
            VStack(spacing: 0) {
                HStack {
                    Text(nav.titoloPopup.isEmpty ? "Finestra del sito" : nav.titoloPopup)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Spacer()
                    Button { nav.chiudiPopup() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 26))
                    }
                    .accessibilityLabel("Chiudi il pop-up")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.fondo)
                if let p = nav.popup {
                    WebVista(web: p)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accento.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.vertical, 30)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}
// MARK: - Cronologia del browser (solo modalità Normale, solo su questo iPhone)

nonisolated struct VoceCronologia: Codable, Identifiable, Sendable {
    var id = UUID()
    let titolo: String
    let url: URL
    let quando: Date
}

enum Cronologia {
    private static let chiave = "browserCronologia"
    static let massimo = 500

    static func leggi() -> [VoceCronologia] {
        guard let d = UserDefaults.standard.data(forKey: chiave) else { return [] }
        return (try? JSONDecoder().decode([VoceCronologia].self, from: d)) ?? []
    }

    static func salva(_ voci: [VoceCronologia]) {
        if let d = try? JSONEncoder().encode(Array(voci.prefix(massimo))) { UserDefaults.standard.set(d, forKey: chiave) }
    }

    static func aggiungi(titolo: String, url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        var voci = leggi()
        if let prima = voci.first, prima.url == url, Date().timeIntervalSince(prima.quando) < 600 { return }   // stessa pagina ricaricata
        voci.insert(VoceCronologia(titolo: titolo.isEmpty ? (url.host() ?? url.absoluteString) : titolo, url: url, quando: Date()), at: 0)
        salva(voci)
    }

    /// Cancella le voci più recenti di `da` (nil = tutto). Con `anchedati` toglie anche cookie e accessi ai siti.
    @MainActor static func cancella(da: Date?, ancheDati: Bool) async {
        if let da { salva(leggi().filter { $0.quando < da }) } else { UserDefaults.standard.removeObject(forKey: chiave) }
        if ancheDati {
            let negozio = WKWebsiteDataStore.default()
            await negozio.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: da ?? .distantPast)
        }
    }
}

struct VistaCronologiaBrowser: View {
    let incognito: Bool
    let accento: Color
    let apri: (URL) -> Void
    @Environment(\.dismiss) private var chiudi
    @State private var voci: [VoceCronologia] = []
    @State private var cerca = ""
    @State private var chiediCancella = false
    @State private var ancheDati = false

    private var filtrate: [VoceCronologia] {
        let c = cerca.trimmingCharacters(in: .whitespaces).lowercased()
        return c.isEmpty ? voci : voci.filter { $0.titolo.lowercased().contains(c) || $0.url.absoluteString.lowercased().contains(c) }
    }

    /// Le voci raggruppate per giorno, dal più recente.
    private var giorni: [(Date, [VoceCronologia])] {
        let cal = Calendar.current
        let gruppi = Dictionary(grouping: filtrate) { cal.startOfDay(for: $0.quando) }
        return gruppi.keys.sorted(by: >).map { ($0, gruppi[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if incognito {
                    Label("In incognito non registro niente: qui c'è la cronologia della modalità Normale.", systemImage: "eyeglasses")
                        .font(.footnote).foregroundStyle(Color.tenue).listRowBackground(Color.clear)
                }
                if voci.isEmpty {
                    Text("Cronologia vuota.").font(.footnote).foregroundStyle(Color.tenue).listRowBackground(Color.clear)
                }
                ForEach(giorni, id: \.0) { giorno, lista in
                    Section {
                        ForEach(lista) { v in
                            Button { apri(v.url) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(v.titolo).font(.system(size: 15)).foregroundStyle(.white).lineLimit(1)
                                    HStack {
                                        Text(v.url.host() ?? v.url.absoluteString).lineLimit(1)
                                        Spacer()
                                        Text(v.quando.formatted(date: .omitted, time: .shortened))
                                    }
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.tenue)
                                }
                            }
                            .listRowBackground(accento.opacity(0.05))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { togli(v) } label: { Label("Elimina", systemImage: "trash") }
                            }
                        }
                    } header: {
                        Text(Calendar.current.isDateInToday(giorno) ? "OGGI" : Calendar.current.isDateInYesterday(giorno) ? "IERI"
                             : giorno.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(accento)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.fondo.ignoresSafeArea())
            .searchable(text: $cerca, prompt: "Cerca nella cronologia")
            .navigationTitle("Cronologia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { chiudi() }.tint(accento) }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { chiediCancella = true } label: { Label("Cancella…", systemImage: "trash") }
                        .tint(.red)
                }
                ToolbarItem(placement: .bottomBar) {
                    Toggle(isOn: $ancheDati) { Text("anche cookie e accessi").font(.system(size: 11)) }
                        .toggleStyle(.switch).tint(.red).fixedSize()
                }
            }
            .confirmationDialog(ancheDati ? "Cancellare la cronologia, i cookie e gli accessi ai siti?" : "Cancellare la cronologia?",
                                isPresented: $chiediCancella, titleVisibility: .visible) {
                Button("Ultima ora", role: .destructive) { Task { await cancella(Date().addingTimeInterval(-3600)) } }
                Button("Oggi", role: .destructive) { Task { await cancella(Calendar.current.startOfDay(for: Date())) } }
                Button("Ultima settimana", role: .destructive) { Task { await cancella(Date().addingTimeInterval(-7 * 86_400)) } }
                Button("Tutto", role: .destructive) { Task { await cancella(nil) } }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { voci = Cronologia.leggi() }
    }

    private func togli(_ v: VoceCronologia) {
        voci.removeAll { $0.id == v.id }
        Cronologia.salva(voci)
    }

    private func cancella(_ da: Date?) async {
        await Cronologia.cancella(da: da, ancheDati: ancheDati)
        Suoni.tocco()
        withAnimation { voci = Cronologia.leggi() }
    }
}
#endif
