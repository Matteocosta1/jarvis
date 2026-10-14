import SwiftUI
import Photos
import SafariServices

/// Un'immagine da mostrare: dal web (Brave, Discogs, Shazam) oppure dalla galleria del signore (`locale`).
nonisolated struct Immagine: Codable, Hashable, Sendable, Identifiable {
    var titolo: String?
    var miniatura: String?
    var grande: String?
    var pagina: String?
    var fonte: String?
    var locale: String?          // localIdentifier della foto nella libreria

    var id: String { locale ?? grande ?? miniatura ?? pagina ?? titolo ?? "?" }

    init(titolo: String? = nil, miniatura: String? = nil, grande: String? = nil, pagina: String? = nil, fonte: String? = nil, locale: String? = nil) {
        self.titolo = titolo; self.miniatura = miniatura; self.grande = grande; self.pagina = pagina; self.fonte = fonte; self.locale = locale
    }

    /// Dalle righe JSON del cervello (evento «immagini»).
    static func daJSON(_ x: Any?) -> [Immagine] {
        (x as? [[String: Any]] ?? []).compactMap { d in
            let i = Immagine(titolo: d["titolo"] as? String, miniatura: d["miniatura"] as? String, grande: d["grande"] as? String,
                             pagina: d["pagina"] as? String, fonte: d["fonte"] as? String)
            return (i.miniatura ?? i.grande) == nil ? nil : i
        }
    }
}

/// Indirizzo da aprire nel browser dentro l'app (serve Identifiable per il foglio).
nonisolated struct PaginaWeb: Identifiable { let url: URL; var id: String { url.absoluteString } }

// MARK: - Galleria sotto la risposta di JARVIS

struct GalleriaMessaggio: View {
    let immagini: [Immagine]
    @State private var aperta: Int?

    init(immagini: [Immagine]) { self.immagini = immagini }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(Array(immagini.enumerated()), id: \.offset) { k, img in
                    Button { aperta = k } label: {
                        Miniatura(immagine: img, lato: 300)
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 112)
        .fullScreenCover(item: Binding(get: { aperta.map { Indice(valore: $0) } }, set: { aperta = $0?.valore })) { i in
            VistaImmagini(immagini: immagini, iniziale: i.valore)
        }
    }

    nonisolated private struct Indice: Identifiable { let valore: Int; var id: Int { valore } }
}

/// Miniatura: dal web con AsyncImage, dalla libreria con Photos.
struct Miniatura: View {
    let immagine: Immagine
    var lato: CGFloat = 300
    var adatta = false
    @State private var locale: UIImage?

    var body: some View {
        Group {
            if immagine.locale != nil {
                if let locale {
                    disegna(Image(uiImage: locale))
                } else {
                    segnaposto
                }
            } else if let s = (lato > 400 ? (immagine.grande ?? immagine.miniatura) : (immagine.miniatura ?? immagine.grande)), let url = URL(string: s) {
                AsyncImage(url: url) { fase in
                    switch fase {
                    case .success(let img): disegna(img)
                    case .failure:
                        // la grande a volte non si lascia scaricare: ripiego sulla miniatura
                        if lato > 400, let m = immagine.miniatura, let u = URL(string: m), m != s {
                            AsyncImage(url: u) { disegna($0) } placeholder: { segnaposto }
                        } else {
                            Image(systemName: "photo").foregroundStyle(Color.tenue).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    default: segnaposto
                    }
                }
            } else {
                segnaposto
            }
        }
        .task(id: immagine.locale) {
            guard let id = immagine.locale else { return }
            locale = await FotoLocali.immagine(id: id, lato: lato)
        }
    }

    private func disegna(_ i: Image) -> some View {
        Group {
            if adatta { i.resizable().scaledToFit() } else { i.resizable().scaledToFill() }
        }
    }

    private var segnaposto: some View {
        ZStack {
            Color(red: 0.04, green: 0.12, blue: 0.15)
            ProgressView().tint(Color.ciano)
        }
    }
}

// MARK: - Visione a schermo intero, con pagina web nel browser interno

struct VistaImmagini: View {
    let immagini: [Immagine]
    @State var iniziale: Int
    @Environment(\.dismiss) private var chiudi
    @State private var pagina: PaginaWeb?

    var body: some View {
        NavigationStack {
            TabView(selection: $iniziale) {
                ForEach(Array(immagini.enumerated()), id: \.offset) { k, img in
                    VStack(spacing: 12) {
                        Miniatura(immagine: img, lato: 1600, adatta: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let t = img.titolo, !t.isEmpty {
                            Text(t).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal)
                        }
                        if let f = img.fonte, !f.isEmpty {
                            Text(f).font(.caption2.monospaced()).foregroundStyle(Color.tenue)
                        }
                    }
                    .padding(.bottom, 40)
                    .tag(k)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { chiudi() } }
                ToolbarItem(placement: .primaryAction) {
                    if let s = attuale?.pagina, let url = URL(string: s) {
                        Button { pagina = PaginaWeb(url: url) } label: { Label("Apri la pagina", systemImage: "safari") }
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .sheet(item: $pagina) { p in BrowserInterno(url: p.url).ignoresSafeArea() }
        }
        .preferredColorScheme(.dark)
    }

    private var attuale: Immagine? { immagini.indices.contains(iniziale) ? immagini[iniziale] : nil }
}

/// Browser dentro l'app (Safari, con lettore, condivisione e «apri in Safari»).
struct BrowserInterno: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(Color.ciano)
        c.dismissButtonStyle = .close
        return c
    }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}
