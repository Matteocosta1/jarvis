import WidgetKit
import SwiftUI

// Complicazione di JARVIS per il quadrante dell'Apple Watch: il reattore.
// Un tocco apre JARVIS e lo mette subito in ascolto (jarvis://ascolta).

struct VoceReattore: TimelineEntry {
    let date: Date
}

struct FornitoreReattore: TimelineProvider {
    func placeholder(in context: Context) -> VoceReattore { VoceReattore(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (VoceReattore) -> Void) { completion(VoceReattore(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoceReattore>) -> Void) {
        completion(Timeline(entries: [VoceReattore(date: .now)], policy: .never))   // immagine fissa: niente aggiornamenti, niente batteria
    }
}

/// Il reattore disegnato: anello esterno, corona a segmenti, nucleo luminoso.
struct ReattoreMini: View {
    var body: some View {
        GeometryReader { g in
            let lato = min(g.size.width, g.size.height)
            ZStack {
                Circle()
                    .stroke(Color(red: 0.31, green: 0.89, blue: 1.0).opacity(0.45), lineWidth: lato * 0.05)
                Circle()
                    .inset(by: lato * 0.13)
                    .stroke(Color(red: 0.31, green: 0.89, blue: 1.0),
                            style: StrokeStyle(lineWidth: lato * 0.09, dash: [lato * 0.11, lato * 0.06]))
                    .widgetAccentable()
                Circle()
                    .inset(by: lato * 0.31)
                    .fill(RadialGradient(colors: [.white, Color(red: 0.31, green: 0.89, blue: 1.0)],
                                         center: .center, startRadius: 0, endRadius: lato * 0.2))
                    .widgetAccentable()
            }
            .frame(width: lato, height: lato)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct VistaComplicazione: View {
    @Environment(\.widgetFamily) private var famiglia
    let voce: VoceReattore

    var body: some View {
        switch famiglia {
        case .accessoryCorner:
            ReattoreMini()
                .padding(2)
                .widgetLabel("JARVIS")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                ReattoreMini().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("J.A.R.V.I.S.")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .widgetAccentable()
                    Text("Tocchi e parli")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        case .accessoryInline:
            Label("JARVIS", systemImage: "circle.circle")
        default:   // .accessoryCircular
            ReattoreMini().padding(3)
        }
    }
}

// Il punto di avvio (@main) è nel file JarvisComplicazioneBundle creato da Xcode.
struct JarvisComplicazione: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JarvisReattore", provider: FornitoreReattore()) { voce in
            VistaComplicazione(voce: voce)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(URL(string: "jarvis://ascolta"))
        }
        .configurationDisplayName("JARVIS")
        .description("Il reattore: un tocco e JARVIS la ascolta.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}
