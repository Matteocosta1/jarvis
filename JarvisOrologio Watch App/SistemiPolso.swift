import Foundation
import SwiftUI
import WatchKit

// MARK: - Build 30 (25 ott, deciso dal signore): SISTEMI, IMPOSTAZIONI e COSTI anche al polso, MUSICA nella barra

/// Le chiavi delle impostazioni del polso (le legge anche `JarvisOrologio`).
enum ImpostazioniPolso {
    static let volume = "volumeVoceOrologio"        // volume della voce di JARVIS, 0,2–1 (di base 1)
    static let riascolto = "riascoltoOrologio"      // dopo la risposta il microfono si riapre da solo (di base sì)
}

/// L'icona di MUSICA: lo stesso vinile olografico dell'iPhone (`IconaVinile`, ICONE.Musica del mockup). Prende il colore
/// dal foregroundStyle.
struct IconaVinileOrologio: View {
    var body: some View {
        Canvas { gc, size in
            let k = min(size.width, size.height) / 24
            let dx = (size.width - 24 * k) / 2, dy = (size.height - 24 * k) / 2
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * k, y: dy + y * k) }
            func cerchio(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: dx + (12 - r) * k, y: dy + (12 - r) * k, width: 2 * r * k, height: 2 * r * k)) }
            func arco(_ da: CGPoint, _ a: CGPoint, centro: CGPoint) -> Path {
                var q = Path()
                q.addArc(center: p(centro.x, centro.y), radius: 7 * k,
                         startAngle: .radians(atan2(Double(da.y - centro.y), Double(da.x - centro.x))),
                         endAngle: .radians(atan2(Double(a.y - centro.y), Double(a.x - centro.x))), clockwise: false)
                return q
            }
            let stile = StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round)
            var tenue = gc
            tenue.opacity = 0.55
            gc.stroke(cerchio(9), with: .foreground, style: stile)
            tenue.stroke(cerchio(5.6), with: .foreground, style: stile)
            gc.stroke(cerchio(1.7), with: .foreground, style: stile)
            gc.stroke(arco(CGPoint(x: 5.7, y: 9.4), CGPoint(x: 9.4, y: 5.7), centro: CGPoint(x: 12.141, y: 12.141)), with: .foreground, style: stile)
            tenue.stroke(arco(CGPoint(x: 18.3, y: 14.6), CGPoint(x: 14.6, y: 18.3), centro: CGPoint(x: 11.859, y: 11.859)), with: .foreground, style: stile)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - SISTEMI: come il menu dell'iPhone (GitHub, Supabase, Archivio, Costi, EDITH)

struct VistaSistemiOrologio: View {
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Sistemi") {
            NavigationLink { VistaGitHubOrologio() } label: { riga("GitHub") { Image("github-logo").resizable().renderingMode(.template).scaledToFit() } }
            NavigationLink { VistaSupabaseOrologio() } label: { riga("Supabase") { Image("supabase-logo").resizable().renderingMode(.template).scaledToFit() } }
            NavigationLink { VistaArchivioOrologio() } label: { riga("Archivio") { IconaArchivioOrologio().scaleEffect(0.75) } }
            NavigationLink { VistaCostiOrologio() } label: { riga("Costi") { Image(systemName: "gauge.with.dots.needle.33percent") } }
            // EDITH vive sull'iPhone (come Occhi e LiDAR): al polso la riga lo dice e non apre niente
            riga("EDITH", nota: "sull'iPhone") { Image(systemName: "eyeglasses") }.opacity(0.55)
        }
    }

    private func riga<Icona: View>(_ nome: String, nota: String? = nil, @ViewBuilder icona: () -> Icona) -> some View {
        HStack(spacing: 8) {
            icona()
                .frame(width: 16, height: 16)
                .foregroundStyle(ciano)
                .frame(width: 30, height: 30)
                .background(ciano.opacity(0.12))
                .clipShape(Circle())
            Text(nome).font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            if let nota { Text(nota).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - COSTI (versione da polso della scheda dell'iPhone)

struct VistaCostiOrologio: View {
    @State private var dati: [String: Any]?
    @State private var errore: String?
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Costi", pronto: dati != nil || errore != nil) {
            if let c = dati {
                // 9 nov (build 19): la prova scelta sull'iPhone (PALLADIO, TORRI, CLESSIDRA), in piccolo accanto al mese, come il mockup
                HStack(spacing: 8) {
                    OlogrammaCostiProve(dati: DatiCostiOlo.da(c), piccolo: true).frame(width: 46, height: 46)
                    ValoreOrologio(titolo: "MESE", valore: "\(Self.soldi(c["dollari_mese"])) $", sotto: "\(Self.intero(c["chiamate_mese"])) risposte")
                }
                HStack(spacing: 6) {
                    ValoreOrologio(titolo: "OGGI", valore: Self.soldi(c["dollari_oggi"]))
                    ValoreOrologio(titolo: "IERI", valore: Self.soldi(c["dollari_ieri"]))
                }
                ValoreOrologio(titolo: "7 GIORNI", valore: "\(Self.soldi(c["dollari_7_giorni"])) $")
                TastoJarvisOrologio(testo: "Dove spendo?", frase: "Guarda i costi di JARVIS di questa settimana: dove spendo di più? In due frasi.")
                let modelli = c["modelli"] as? [[String: Any]] ?? []
                if !modelli.isEmpty { IntestazioneOrologio(testo: "CERVELLO") }
                ForEach(Array(modelli.enumerated()), id: \.offset) { _, m in
                    HStack {
                        Text(Self.nomeModello(m["modello"] as? String ?? "")).font(.system(size: 12))
                        Text("\(Self.intero(m["chiamate"]))").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Self.soldi(m["dollari"])) $").font(.system(size: 11, design: .monospaced)).foregroundStyle(ciano)
                    }
                }
                Text("Stima dai token con i listini pubblici.").font(.system(size: 8)).foregroundStyle(.secondary)
            } else if let errore {
                Text(errore).font(.footnote).foregroundStyle(.orange)
            }
        }
        .task {
            guard let o = await VistaVitalsOrologio.chiama(["consumi": true]) else { errore = "Non raggiungo il cervello, Sir."; return }
            if let e = o["errore"] as? String { errore = e; return }
            dati = o
        }
    }

    /// Un numero arrivato dal cervello (numero o testo) con due decimali e la virgola, come sull'iPhone.
    private static func soldi(_ v: Any?) -> String {
        let d = (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "") ?? 0
        return String(format: "%.2f", d).replacingOccurrences(of: ".", with: ",")
    }
    private static func intero(_ v: Any?) -> String {
        let d = (v as? NSNumber)?.doubleValue ?? Double(v as? String ?? "") ?? 0
        return String(format: "%.0f", d)
    }
    private static func nomeModello(_ m: String) -> String {
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return m.replacingOccurrences(of: "claude-", with: "")
    }
}

// MARK: - IMPOSTAZIONI del polso: voce e microfono (scelto dal signore)

struct VistaImpostazioniOrologio: View {
    @EnvironmentObject var jarvis: JarvisOrologio
    @AppStorage(ImpostazioniPolso.volume) private var volume = 1.0
    @AppStorage(ImpostazioniPolso.riascolto) private var riascolto = true
    @State private var sottovoce = false
    private let ciano = TintaOrologio.ciano

    var body: some View {
        CorniceOrologio(titolo: "Impostazioni") {
            Toggle(isOn: Binding(get: { !jarvis.micSpento }, set: { jarvis.micSpento = !$0 })) {
                etichetta("Microfono", jarvis.micSpento ? "spento: tocchi il reattore" : "acceso")
            }
            .tint(ciano)
            Toggle(isOn: $riascolto) {
                etichetta("Riascolto", riascolto ? "sempre in ascolto" : "solo col tocco")
            }
            .tint(ciano)
            VStack(alignment: .leading, spacing: 2) {
                etichetta("Volume", "\(Int((volume * 100).rounded()))%")
                Slider(value: $volume, in: 0.2...1, step: 0.1).tint(ciano)
            }
            Toggle(isOn: $sottovoce) {
                etichetta("Sottovoce", "per 10 minuti")
            }
            .tint(ciano)
            .onChange(of: sottovoce) { _, si in jarvis.sottovoce = si }
        }
        .onAppear { sottovoce = jarvis.sottovoce }
    }

    private func etichetta(_ nome: String, _ stato: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(nome).font(.system(size: 14, weight: .semibold))
            Text(stato).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}
