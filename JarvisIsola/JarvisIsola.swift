import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents

// MARK: - MARK X · DYNAMIC ISLAND di JARVIS (mockup approvato, build 32), disegnata da iOS fuori dall'app.
// Compatta: a sinistra la linea (TRAVEL), la freccia con la via (GUIDA), il punto rosso (REC), la nuvola (PIOGGIA) o il reattore (VOCE);
// a destra in ciano «esci 4′», i metri, il tempo registrato o i minuti alla pioggia.
// Grande (tocco lungo): il numero grande, la riga ciano in maiuscolo, la riga bianca e i due tasti (il secondo rosso).
// Nella schermata bloccata la stessa cosa della grande. I tasti che aprono JARVIS sono collegamenti (it.discosizer.jarvis://isola/…),
// gli altri (Pausa, Stop, Ok, Basta avvisi, Ferma guida) li esegue l'app senza aprirsi (ComandoIsola).

@main
struct IsolaJarvisBundle: WidgetBundle {
    var body: some Widget {
        IsolaJarvisWidget()
        if #available(iOS 18.0, *) { ControlloJarvis() }        // 12.0 (12) · B4: il controllo JARVIS
    }
}

private let ciano = Color(red: 79 / 255, green: 227 / 255, blue: 1)
private let rossoTasto = Color(red: 1, green: 138 / 255, blue: 138 / 255)
private let rossoRec = Color(red: 1, green: 59 / 255, blue: 48 / 255)

private func colore(_ hex: String?) -> Color {
    guard let hex, hex.count == 6, let v = UInt32(hex, radix: 16) else { return Color(red: 200 / 255, green: 0, blue: 26 / 255) }
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

private func comando(_ c: String) -> URL { URL(string: "it.discosizer.jarvis://isola/\(c)") ?? URL(fileURLWithPath: "/") }

/// «00:12:43»
private func hms(_ s: Int) -> String { String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }

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

private struct PuntoRec: View {
    var pausa = false
    var body: some View {
        Circle().fill(pausa ? rossoRec.opacity(0.4) : rossoRec).frame(width: 8, height: 8)
            .shadow(color: rossoRec, radius: pausa ? 0 : 3)
    }
}

private struct Nuvola: View {
    var body: some View {
        Image(systemName: "cloud.rain").font(.system(size: 13, weight: .semibold)).foregroundStyle(ciano)
    }
}

/// VOCE (12 nov): il reattore di JARVIS in piccolo (nel mockup la copia del reattore; qui fermo: l'isola non anima i disegni).
private struct ReattoreIsola: View {
    let lato: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(ciano.opacity(0.45), lineWidth: max(1, lato * 0.05))
            Circle().stroke(ciano, lineWidth: max(1.2, lato * 0.08)).padding(lato * 0.17)
            Circle().fill(ciano).frame(width: lato * 0.3, height: lato * 0.3).shadow(color: ciano, radius: lato * 0.12)
        }
        .frame(width: lato, height: lato)
    }
}

/// VOCE: le quattro barre della voce (mentre ascolta o parla), come nel mockup.
private struct BarreVoce: View {
    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach([5.0, 9.0, 6.0, 8.0], id: \.self) { h in Capsule().fill(ciano).frame(width: 2, height: h) }
        }
    }
}

/// VOCE: la parola dell'isola stretta («LA ASCOLTO» → ASCOLTO, «ELABORO» → PENSO), come nel mockup.
private func parolaVoce(_ fase: String?) -> String {
    switch fase {
    case "LA ASCOLTO": return "ASCOLTO"
    case "ELABORO": return "PENSO"
    case "PARLO": return "PARLO"
    default: return "ATTESA"
    }
}

/// A sinistra nell'isola stretta.
private struct SinistraCompatta: View {
    let stato: AttivitaJarvis.ContentState
    var body: some View {
        switch stato.tipo {
        case "travel":
            HStack(spacing: 6) {
                Text(stato.sigla ?? "").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(Circle().fill(colore(stato.coloreSigla)))
                Text(stato.oraMezzo ?? "").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            }
        case "rec":
            HStack(spacing: 5) {
                PuntoRec(pausa: stato.pausaSecondi != nil)
                Text(stato.pausaSecondi != nil ? "PAUSA" : "REC").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
            }
        case "pioggia":
            HStack(spacing: 5) {
                Nuvola()
                Text("Pioggia").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
        case "voce":
            ReattoreIsola(lato: 22)
        default:
            HStack(spacing: 6) {
                Text(stato.freccia ?? "↑").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                Text((stato.via ?? "").replacingOccurrences(of: "Via ", with: "")).font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white).lineLimit(1)
            }
        }
    }
}

/// A destra: «esci 4′» (il conto alla rovescia lo tiene iOS), i metri, la fase, il tempo del REC, i minuti alla pioggia.
private struct DestraCompatta: View {
    let stato: AttivitaJarvis.ContentState
    var body: some View {
        switch stato.tipo {
        case "travel", "pioggia":
            if let e = stato.esci, e > Date() {
                Text(timerInterval: Date()...e, countsDown: true, showsHours: false)
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
                    .frame(maxWidth: 46)
            } else {
                Text(stato.tipo == "travel" ? "ESCI" : "ORA").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
            }
        case "rec":
            if let p = stato.pausaSecondi {
                Text(hms(p)).font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
            } else if let i = stato.inizio {
                Text(timerInterval: i...Date.distantFuture, countsDown: false, showsHours: true)
                    .font(.system(size: 12, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
                    .frame(maxWidth: 64)
            }
        case "voce":
            HStack(spacing: 5) {
                Text(parolaVoce(stato.fase)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
                if stato.fase == "LA ASCOLTO" || stato.fase == "PARLO" { BarreVoce() }
            }
        default:
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
                sinistra
                VStack(alignment: .leading, spacing: 4) {
                    titolo
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(ciano).lineLimit(1)
                    Text(stato.riga).font(.system(size: 14)).foregroundStyle(.white).lineLimit(2)
                }
            }
            HStack(spacing: 8) { tasti }
                .padding(.top, 4)
        }
    }

    @ViewBuilder private var sinistra: some View {
        switch stato.tipo {
        case "travel":
            Text(stato.esci.map { $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? "—")
                .font(.system(size: 30, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
        case "rec":
            Group {
                if let p = stato.pausaSecondi {
                    Text(hms(p))
                } else if let i = stato.inizio {
                    Text(timerInterval: i...Date.distantFuture, countsDown: false, showsHours: true)
                }
            }
            .font(.system(size: 30, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
            .frame(maxWidth: 150, alignment: .leading)
        case "pioggia":
            Group {
                if let e = stato.esci, e > Date() {
                    Text(timerInterval: Date()...e, countsDown: true, showsHours: false)
                } else {
                    Text("ORA")
                }
            }
            .font(.system(size: 38, weight: .bold, design: .monospaced)).monospacedDigit().foregroundStyle(ciano)
            .frame(maxWidth: 120, alignment: .leading)
        case "voce":
            ReattoreIsola(lato: 58)
        default:
            Text(stato.freccia ?? "↑").font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(ciano)
        }
    }

    @ViewBuilder private var titolo: some View {
        switch stato.tipo {
        case "travel":
            if let e = stato.esci {
                HStack(spacing: 0) {
                    Text(e > Date() ? "TRAVEL · ESCI FRA " : "TRAVEL · ESCA ADESSO")
                    if e > Date() { Text(timerInterval: Date()...e, countsDown: true, showsHours: false).monospacedDigit() }
                }
            }
        case "rec":
            HStack(spacing: 6) {
                PuntoRec(pausa: stato.pausaSecondi != nil)
                Text("WIRETAP · \(stato.pausaSecondi != nil ? "IN PAUSA" : "REGISTRO")")
            }
        case "pioggia":
            Text(stato.esci.map { $0 > Date() } == true ? "RADAR · PIOGGIA IN ARRIVO" : "RADAR · STA PIOVENDO")
        case "voce":
            Text("J.A.R.V.I.S. · \(stato.fase ?? "IN ATTESA")")
        default:
            Text("GUIDA · \((stato.via ?? meta).uppercased()) · \(stato.metri ?? 0) M")
        }
    }

    @ViewBuilder private var tasti: some View {
        switch stato.tipo {
        case "travel":
            collegamento("Percorso", "percorso")
            azione("Basta avvisi", "basta", rosso: true)
        case "rec":
            if stato.pausaSecondi != nil { azione("Riprendi", "riprendi", rosso: false) } else { azione("Pausa", "pausa", rosso: false) }
            azione("Stop", "stoprec", rosso: true)
        case "pioggia":
            collegamento("Radar", "radar")
            azione("Ok", "ok", rosso: true)
        case "voce":
            collegamento("Apri", "apri")
            azione("Fine", "finevoce", rosso: true)
        default:
            collegamento("Apri", "guida")
            azione("Ferma guida", "ferma", rosso: true)
        }
    }

    private func etichetta(_ t: String, rosso: Bool) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(rosso ? rossoTasto : ciano)
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(Capsule().fill(rosso ? Color(red: 1, green: 90 / 255, blue: 90 / 255).opacity(0.18) : ciano.opacity(0.16)))
    }

    /// Un tasto che apre JARVIS sulla cosa giusta.
    private func collegamento(_ t: String, _ c: String) -> some View {
        Link(destination: comando(c)) { etichetta(t, rosso: false) }
    }

    /// Un tasto che l'app esegue senza aprirsi.
    private func azione(_ t: String, _ c: String, rosso: Bool) -> some View {
        Button(intent: ComandoIsola(c)) { etichetta(t, rosso: rosso) }
            .buttonStyle(.plain)
    }
}
