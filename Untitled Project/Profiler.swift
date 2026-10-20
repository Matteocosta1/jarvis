#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

/// INTELLIGENCE · Profiler: la sua schermata, diversa dagli Occhi.
/// Toni ambra da archivio dei servizi, mirino a ovale per il soggetto, letture che scorrono ai lati.
/// Si scatta con la fotocamera dietro oppure con quella davanti (selfie), poi si compila la scheda
/// (nome e ruolo, facoltativi) senza uscire: il Profiler manda tutto a JARVIS, che risponde con il dossier.
struct VistaProfiler: View {
    /// Foto (vuoto = chiuso senza profilare) e il nome con il ruolo, così come lo legge JARVIS.
    let fine: ([Data], String) -> Void

    static let ambra = Color.ciano
    private var ambra: Color { VistaProfiler.ambra }

    @State private var motore = MotoreOcchi()
    @State private var davanti = false
    @State private var agganciato = false
    @State private var cambiando = false
    @State private var scattando = false
    @State private var foto: Data?
    @State private var nome = ""
    @State private var chi = ""
    @State private var lampo = false
    @State private var chiuso = false
    @State private var stato = "AVVIO OTTICHE"
    @FocusState private var campo: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let foto, let img = UIImage(data: foto) {
                Image(uiImage: img).resizable().scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.45).ignoresSafeArea())
                    .transition(.opacity)
            } else {
                AnteprimaOcchi(sessione: motore.sessione)
                    .ignoresSafeArea()
                    .opacity(agganciato && !cambiando ? 1 : 0)
                    .animation(.easeOut(duration: 0.35), value: agganciato && !cambiando)
            }
            MirinoProfiler(agganciato: agganciato, acquisito: foto != nil)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Color.white.opacity(lampo ? 0.85 : 0).ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 14) {
                intestazione
                Spacer()
                if foto == nil { comandi } else { scheda }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .statusBarHidden()
        .task { await avvia() }
        .onDisappear { motore.ferma() }
    }

    // MARK: Pezzi

    private var intestazione: some View {
        HStack(spacing: 12) {
            IconaProfiler()
                .foregroundStyle(ambra)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(ambra.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text("J.A.R.V.I.S.")
                    .font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                Text("PROFILER · \(foto != nil ? "SCHEDA SOGGETTO" : davanti ? "SELFIE" : "SOGGETTO")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.75)
            }
            .foregroundStyle(ambra)
            .shadow(color: ambra.opacity(0.5), radius: 6)
            Spacer()
            Button { Suoni.tocco(); chiudi([]) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ambra)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ambra.opacity(0.5), lineWidth: 1))
            }
            .accessibilityLabel("Chiudi")
        }
    }

    private var comandi: some View {
        VStack(spacing: 16) {
            Text(stato)
                .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3)
                .foregroundStyle(ambra)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .contentTransition(.opacity)
            HStack(spacing: 34) {
                // fotocamera davanti / dietro
                Button { Task { await giraFotocamera() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ambra)
                        .frame(width: 54, height: 54)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ambra.opacity(0.6), lineWidth: 1.5))
                        .symbolEffect(.bounce, value: davanti)
                }
                .buttonStyle(StileStark())
                .disabled(!agganciato || cambiando || scattando)
                .accessibilityLabel(davanti ? "Fotocamera posteriore" : "Selfie")

                Button { scatta() } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).stroke(ambra, lineWidth: 3).frame(width: 74, height: 74)
                        RoundedRectangle(cornerRadius: 13).fill(ambra.opacity(scattando ? 0.9 : 0.22)).frame(width: 60, height: 60)
                        IconaProfiler().foregroundStyle(.white).scaleEffect(1.3)
                    }
                    .shadow(color: ambra.opacity(0.6), radius: 10)
                }
                .buttonStyle(StileStark())
                .disabled(!agganciato || cambiando || scattando)
                .accessibilityLabel("Scatta")

                Color.clear.frame(width: 54, height: 54)
            }
        }
    }

    /// Dopo lo scatto: la scheda da compilare, sopra la foto ferma.
    private var scheda: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SCHEDA SOGGETTO").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2.5)
                Spacer()
                Text(Date.now.formatted(date: .numeric, time: .shortened))
                    .font(.system(size: 9, design: .monospaced)).opacity(0.7)
            }
            .foregroundStyle(ambra)
            campoScheda("NOME E COGNOME", "Facoltativo", testo: $nome)
            campoScheda("CHI È", "Es. fornitore audio, gestore del locale", testo: $chi)
            Text("Con il nome confronto le schede passate e, se è un contatto di lavoro, cerco in rete. Senza nome: solo lettura e stile.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 10) {
                Button {
                    Suoni.tocco()
                    withAnimation(.easeOut(duration: 0.25)) { foto = nil }
                    stato = "INQUADRI IL SOGGETTO"
                } label: {
                    Label("Rifai", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(ambra)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ambra.opacity(0.6), lineWidth: 1))
                }
                Button { profila() } label: {
                    Label("Profila", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(.black)
                        .background(ambra)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(StileStark())
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.6))
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ambra.opacity(0.45), lineWidth: 1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func campoScheda(_ titolo: String, _ suggerimento: String, testo: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(ambra.opacity(0.8))
            TextField(suggerimento, text: testo)
                .focused($campo)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .submitLabel(.done)
        }
    }

    // MARK: Lavoro

    private func avvia() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            stato = "ACCESSO NEGATO · IMPOSTAZIONI › JARVIS › FOTOCAMERA"
            Suoni.errore()
            try? await Task.sleep(for: .seconds(2.5))
            chiudi([])
            return
        }
        guard await monta(davanti ? .front : .back) else {
            stato = "FOTOCAMERA NON DISPONIBILE"
            Suoni.errore()
            try? await Task.sleep(for: .seconds(2))
            chiudi([])
            return
        }
        agganciato = true
        Suoni.apertura()
        stato = "INQUADRI IL SOGGETTO"
    }

    private func monta(_ p: AVCaptureDevice.Position) async -> Bool {
        let m = motore
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            m.avvia(posizione: p) { ok in c.resume(returning: ok) }
        }
    }

    private func giraFotocamera() async {
        guard !cambiando else { return }
        Suoni.tocco()
        cambiando = true
        let nuova = !davanti
        if await monta(nuova ? .front : .back) {
            davanti = nuova
            stato = nuova ? "SELFIE · SI METTA IN POSA" : "INQUADRI IL SOGGETTO"
        }
        try? await Task.sleep(for: .milliseconds(250))     // il tempo che l'immagine si assesti
        cambiando = false
    }

    private func scatta() {
        guard agganciato, !scattando, !chiuso else { return }
        scattando = true
        stato = "ACQUISIZIONE"
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Suoni.tocco()
        withAnimation(.easeOut(duration: 0.06)) { lampo = true }
        withAnimation(.easeIn(duration: 0.45).delay(0.06)) { lampo = false }
        motore.scatta(veloce: false) { dati in
            let jpeg = dati.flatMap { Occhi.riduci($0) }
            Task { @MainActor in
                scattando = false
                guard let jpeg else { stato = "SCATTO NON RIUSCITO · RIPROVI"; return }
                Suoni.pronto()
                withAnimation(.spring(duration: 0.45)) { foto = jpeg }
            }
        }
    }

    private func profila() {
        guard let foto else { return }
        campo = false
        let n = nome.trimmingCharacters(in: .whitespaces)
        let c = chi.trimmingCharacters(in: .whitespaces)
        let completo = n.isEmpty ? "" : (c.isEmpty ? n : "\(n) (\(c))")
        Suoni.tocco()
        chiudi([foto], completo)
    }

    private func chiudi(_ dati: [Data], _ nome: String = "") {
        guard !chiuso else { return }
        chiuso = true
        motore.ferma()
        fine(dati, nome)
    }
}

// MARK: - Mirino del Profiler: ovale per il volto, cornice da fascicolo, letture ai lati

struct MirinoProfiler: View {
    let agganciato: Bool
    let acquisito: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let ambra = VistaProfiler.ambra
                let w = Double(size.width), h = Double(size.height)
                let larg = min(w * 0.62, 300.0), alt = larg * 1.3
                let c = CGPoint(x: w / 2, y: h * 0.42)
                let ovale = CGRect(x: c.x - larg / 2, y: c.y - alt / 2, width: larg, height: alt)

                // l'ovale del soggetto, tratteggiato, che gira lento
                gc.stroke(Path(ellipseIn: ovale), with: .color(ambra.opacity(acquisito ? 0.9 : 0.55)),
                          style: StrokeStyle(lineWidth: 1.5, dash: [6, 7], dashPhase: acquisito ? 0 : t * 14))

                // cornice da fascicolo attorno all'ovale
                let m = 22.0
                let cornice = ovale.insetBy(dx: -m, dy: -m)
                let braccio = 26.0
                var angoli = Path()
                for (ax, ay, dx, dy) in [(cornice.minX, cornice.minY, 1.0, 1.0), (cornice.maxX, cornice.minY, -1.0, 1.0),
                                         (cornice.minX, cornice.maxY, 1.0, -1.0), (cornice.maxX, cornice.maxY, -1.0, -1.0)] {
                    angoli.move(to: CGPoint(x: ax, y: ay + dy * braccio))
                    angoli.addLine(to: CGPoint(x: ax, y: ay))
                    angoli.addLine(to: CGPoint(x: ax + dx * braccio, y: ay))
                }
                gc.stroke(angoli, with: .color(ambra.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // la riga di scansione che percorre l'ovale (si ferma quando la foto è presa)
                if agganciato && !acquisito {
                    let p = 0.5 + 0.5 * sin(t * 1.6)
                    let y = ovale.minY + alt * p
                    let dy = (y - c.y) / (alt / 2)
                    let mezza = larg / 2 * (1 - dy * dy).squareRoot()
                    gc.fill(Path(CGRect(x: c.x - mezza, y: y - 1, width: mezza * 2, height: 2)), with: .color(ambra.opacity(0.7)))
                }

                // letture ai lati: si accendono una alla volta, come un analista che compila
                let voci = ["ESPRESSIONE", "SGUARDO", "POSTURA", "STILE", "CONTESTO"]
                for (k, v) in voci.enumerated() {
                    let fase = (t * 0.7 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
                    let acceso = acquisito || fase < 0.55
                    let y = cornice.minY + 14 + Double(k) * 22
                    let sinistra = k % 2 == 0
                    let x: CGFloat = sinistra ? max(8, cornice.minX - 8) : min(CGFloat(w) - 8, cornice.maxX + 8)
                    let testo = Text(v + (acquisito ? " ✓" : ""))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ambra.opacity(acceso ? 0.85 : 0.25))
                    gc.draw(testo, at: CGPoint(x: x, y: y), anchor: sinistra ? .trailing : .leading)
                }

                // timbro quando la foto è acquisita
                if acquisito {
                    let timbro = Text("ACQUISITO")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(ambra)
                    var g = gc
                    g.translateBy(x: c.x, y: ovale.minY - 6)
                    g.rotate(by: .degrees(-4))
                    g.draw(timbro, at: .zero, anchor: .bottom)
                }
            }
        }
    }
}
#endif
