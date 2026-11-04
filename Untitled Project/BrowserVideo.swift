#if os(iOS)
import SwiftUI
import WebKit

// MARK: - BROWSER · VIDEO (MARK X): il tasto VIDEO accanto alla barra apre il visore olografico con i video di YouTube.
// La ricerca la fa il cervello (funzione «browser-video», la chiave di YouTube resta su Supabase); il video si guarda nel
// lettore ufficiale di YouTube (embed). Le foto il signore le cerca a mano nel browser (deciso il 26 ott: niente Brave).

nonisolated struct VideoWeb: Identifiable, Hashable, Sendable {
    let id: String
    let titolo: String
    let canale: String
    let miniatura: URL?
}

enum CercaVideo {
    /// «Jarvis, fammi vedere dei video di …»: la frase lascia qui cosa cercare; il Browser lo prende appena si apre (entro 8 s).
    @MainActor static var richiesta: (testo: String, quando: Date)?
    @MainActor static func prendiRichiesta() -> String? {
        defer { richiesta = nil }
        guard let r = richiesta, Date().timeIntervalSince(r.quando) < 8 else { return nil }
        return r.testo
    }

    static func cerca(_ q: String) async -> ([VideoWeb], String?) {
        let base = Impostazioni.indirizzo.replacingOccurrences(of: "/functions/v1/jarvis", with: "/functions/v1/browser-video")
        guard let url = URL(string: base) else { return ([], "Indirizzo del cervello non valido.") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Portachiavi.leggi(), forHTTPHeaderField: "x-jarvis-token")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["q": q])
        do {
            let (d, _) = try await URLSession.shared.data(for: req)
            let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
            if let e = o["errore"] as? String { return ([], e) }
            let lista = (o["video"] as? [[String: Any]] ?? []).compactMap { v -> VideoWeb? in
                guard let id = v["id"] as? String, !id.isEmpty else { return nil }
                return VideoWeb(id: id, titolo: v["titolo"] as? String ?? "", canale: v["canale"] as? String ?? "",
                                miniatura: (v["miniatura"] as? String).flatMap(URL.init(string:)))
            }
            return (lista, lista.isEmpty ? "Nessun video per «\(q)», Sir." : nil)
        } catch {
            return ([], "YouTube non risponde, Sir: controlli la connessione.")
        }
    }
}

/// L'icona VIDEO del mockup (schermo con il triangolo del play), in ciano come le altre.
struct IconaVideoWeb: View {
    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width, g.size.height) / 24
            ZStack {
                RoundedRectangle(cornerRadius: 4.5 * k).stroke(lineWidth: 1.6 * k)
                    .frame(width: 19 * k, height: 14 * k)
                Path { p in
                    p.move(to: CGPoint(x: 10 * k, y: 9.2 * k)); p.addLine(to: CGPoint(x: 10 * k, y: 14.8 * k))
                    p.addLine(to: CGPoint(x: 14.8 * k, y: 12 * k)); p.closeSubpath()
                }
                .fill()
                .frame(width: 24 * k, height: 24 * k)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

/// Il visore olografico: le cornici si chiudono, la scansione passa SOLO mentre carica, poi la griglia dei video.
/// Un video si apre nel lettore ufficiale di YouTube; si scorre con le frecce o con uno swipe.
struct VisoreVideo: View {
    let cerca: String
    let accento: Color
    let chiudi: () -> Void
    @State private var video: [VideoWeb] = []
    @State private var carica = true
    @State private var errore: String?
    @State private var aperto: Int?
    @State private var cornici = false
    @Environment(\.sezioneDietro) private var dietro    // 4 nov: il Browser dietro (MARK XI): la scansione si ferma

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    IconaVideoWeb().frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("VIDEO").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                        Text("«\(cerca)»").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    }
                    Spacer()
                    Button("Chiudi") { if aperto != nil { withAnimation { aperto = nil } } else { chiudi() } }
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 16).padding(.top, 8)
                ZStack {
                    if let i = aperto, video.indices.contains(i) { lettore(i) } else { griglia }
                    if carica { scansione }
                }
                .padding(10)
                .overlay { Cornici(chiusura: cornici ? 1 : 0).stroke(accento.opacity(0.8), lineWidth: 2) }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .foregroundStyle(accento)
        }
        .task {
            withAnimation(.easeOut(duration: 0.45)) { cornici = true }
            let (l, e) = await CercaVideo.cerca(cerca)
            withAnimation(.easeOut(duration: 0.3)) { video = l; errore = e; carica = false }
        }
    }

    private var griglia: some View {
        ScrollView {
            if let e = errore { Text(e).font(.footnote).foregroundStyle(.orange).padding(.top, 30).multilineTextAlignment(.center) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 12) {
                ForEach(Array(video.enumerated()), id: \.element.id) { i, v in
                    Button { withAnimation(.spring(duration: 0.35)) { aperto = i } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            AsyncImage(url: v.miniatura) { img in img.resizable().scaledToFill() } placeholder: { accento.opacity(0.08) }
                                .frame(height: 96).frame(maxWidth: .infinity).clipped()
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accento.opacity(0.45), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay { Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 4) }
                            Text(v.titolo).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                            Text(v.canale).font(.system(size: 10, design: .monospaced)).foregroundStyle(accento.opacity(0.8)).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func lettore(_ i: Int) -> some View {
        let v = video[i]
        return VStack(spacing: 12) {
            LettoreYouTube(id: v.id)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accento.opacity(0.5), lineWidth: 1))
                .id(v.id)
            Text(v.titolo).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(v.canale).font(.system(size: 11, design: .monospaced)).foregroundStyle(accento)
            HStack(spacing: 28) {
                Button { withAnimation { aperto = max(0, i - 1) } } label: { Image(systemName: "chevron.left").font(.system(size: 22)) }
                    .disabled(i == 0).accessibilityLabel("Video precedente")
                Button { if let u = URL(string: "https://www.youtube.com/watch?v=\(v.id)") { UIApplication.shared.open(u) } } label: {
                    Text("YOUTUBE").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.5)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .overlay(Capsule().stroke(accento.opacity(0.6), lineWidth: 1))
                }
                Button { withAnimation { aperto = min(video.count - 1, i + 1) } } label: { Image(systemName: "chevron.right").font(.system(size: 22)) }
                    .disabled(i == video.count - 1).accessibilityLabel("Video successivo")
            }
            Spacer(minLength: 0)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            if g.translation.width < -60, i < video.count - 1 { withAnimation { aperto = i + 1 } }
            if g.translation.width > 60, i > 0 { withAnimation { aperto = i - 1 } }
        })
    }

    /// La scansione: una riga di luce che scende, solo mentre carica (deciso dal signore: non continua sul video aperto).
    private var scansione: some View {
        TimelineView(.animation(minimumInterval: nil, paused: dietro)) { tl in
            GeometryReader { g in
                let y = CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4) * g.size.height
                Rectangle().fill(LinearGradient(colors: [.clear, accento.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 26).offset(y: y - 13)
            }
        }
        .allowsHitTesting(false)
        .overlay { Text("CERCO…").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2) }
    }
}

/// Le quattro cornici del visore: arrivano dai bordi e si fermano agli angoli.
private struct Cornici: Shape {
    var chiusura: CGFloat                      // 0 = larghe e staccate dagli angoli, 1 = ferme agli angoli
    var animatableData: CGFloat { get { chiusura } set { chiusura = newValue } }
    func path(in r: CGRect) -> Path {
        let l = 60 - 38 * chiusura, d = 14 * (1 - chiusura)
        var p = Path()
        for (x, y, sx, sy) in [(r.minX + d, r.minY + d, CGFloat(1), CGFloat(1)), (r.maxX - d, r.minY + d, -1, 1), (r.minX + d, r.maxY - d, 1, -1), (r.maxX - d, r.maxY - d, -1, -1)] {
            p.move(to: CGPoint(x: x, y: y + sy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + sx * l, y: y))
        }
        return p
    }
}

/// Il lettore ufficiale di YouTube (embed), nella pagina: niente download, solo riproduzione.
struct LettoreYouTube: UIViewRepresentable {
    let id: String
    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: c)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.isScrollEnabled = false
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;background:#000;height:100%}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(id)?playsinline=1&autoplay=1&rel=0" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe></body></html>
        """
        w.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
