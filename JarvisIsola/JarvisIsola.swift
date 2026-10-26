import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - MARK X · DYNAMIC ISLAND di JARVIS (mockup approvato, build 32), disegnata da iOS fuori dall'app.
// Compatta: a sinistra la linea (TRAVEL) o la freccia con la via (GUIDA), a destra «esci 4′» o i metri, in ciano.
// Grande (tocco lungo): il numero grande, la riga ciano in maiuscolo, la riga bianca e i due tasti (il secondo rosso).
// Nella schermata bloccata la stessa cosa della grande. I tasti aprono JARVIS con il comando (it.discosizer.jarvis://isola/…).

@main
struct IsolaJarvisBundle: WidgetBundle {
    var body: some Widget { IsolaJarvisWidget() }
}

private let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
private let rossoTasto = Color(red: 1, green: 138 / 255, blue: 138 / 255)

private func colore(_ hex: String?) -> Color {
    guard let hex, hex.count == 6, let v = UInt32(hex, radix: 16) else { return Color(red: 200 / 255, green: 0, blue: 26 / 255) }
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

private func comando(_ c: String) -> URL { URL(string: "it.discosizer.jarvis://isola/\(c)") ?? URL(fileURLWithPath: "/") }

struct IsolaJarvisWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AttivitaJarvis.self) { ctx in
            Grande(stato: ctx.state, meta: ctx.attributes.meta)
                .padding(.horizontal, 22).padding(.vertical, 18)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(ciano)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Grande(stato: ctx.state, meta: ctx.attributes.meta)
                }
            } compactLeading: {
                SinistraCompatta(stato: ctx.state)
            } compactTrailing: {
                DestraCompatta(stato: ctx.state)
            } minimal: {
                DestraCompatta(stato: ctx.state)
            }
            .widgetURL(comando("apri"))
            .keylineTint(ciano)
        }
    }
}

/// A sinistra nell'isola stretta: il bollino della linea con l'ora del mezzo (TRAVEL), la freccia e la via (GUIDA).
private struct SinistraCompatta: View {
    let stato: AttivitaJarvis.ContentState
    var body: some View {
        if stato.tipo == "travel" {
            HStack(spacing: 6) {
                Text(stato.sigla ?? "").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(colore(stato.coloreSigla)))
                Text(stato.oraMezzo ?? "").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            }
        } else {
            HStack(spacing: 6) {
                Text(stato.freccia ?? "↑").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                Text((stato.via ?? "").replacingOccurrences(of: "Via ", with: "")).font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).lineLimit(1)
            }
        }
    }
}

/// A destra: «esci 4′» (il conto alla rovescia lo tiene iOS) o i metri alla svolta.
private struct DestraCompatta: View {
    let stato: AttivitaJarvis.ContentState
    var body: some View {
        if stato.tipo == "travel", let e = stato.esci {
            if e > Date() {
                Text(timerInterval: Date()...e, countsDown: true, showsHours: false)
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
                    .frame(maxWidth: 46)
            } else {
                Text("ESCI").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
            }
        } else {
            Text("\(stato.metri ?? 0) m").font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
        }
    }
}

/// L'isola grande e la schermata bloccata.
private struct Grande: View {
    let stato: AttivitaJarvis.ContentState
    let meta: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                if stato.tipo == "travel" {
                    Text(stato.esci.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
                } else {
                    Text(stato.freccia ?? "↑").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if stato.tipo == "travel", let e = stato.esci {
                        HStack(spacing: 0) {
                            Text(e > Date() ? "TRAVEL · ESCI FRA " : "TRAVEL · ESCA ADESSO")
                            if e > Date() { Text(timerInterval: Date()...e, countsDown: true, showsHours: false).monospacedDigit() }
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(ciano).lineLimit(1)
                    } else {
                        Text("GUIDA · \((stato.via ?? meta).uppercased()) · \(stato.metri ?? 0) M")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(ciano).lineLimit(1)
                    }
                    Text(stato.riga).font(.system(size: 14)).foregroundStyle(.white).lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                if stato.tipo == "travel" {
                    tasto("Percorso", comando("percorso"), rosso: false)
                    tasto("Basta avvisi", comando("basta"), rosso: true)
                } else {
                    tasto("Apri", comando("guida"), rosso: false)
                    tasto("Ferma guida", comando("ferma"), rosso: true)
                }
            }
            .padding(.top, 4)
        }
    }

    private func tasto(_ t: String, _ u: URL, rosso: Bool) -> some View {
        Link(destination: u) {
            Text(t).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(rosso ? rossoTasto : ciano)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(Capsule().fill(rosso ? Color(red: 1, green: 90 / 255, blue: 90 / 255).opacity(0.18) : ciano.opacity(0.16)))
        }
    }
}
