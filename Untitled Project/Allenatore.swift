#if os(iOS)
import SwiftUI
import Combine
import AVFoundation
import Vision
import UIKit
import CoreVideo
import CoreMedia
import simd

/// L'allenatore di JARVIS: inquadra chi si allena, l'iPhone riconosce lo scheletro del corpo (Vision, tutto in locale)
/// e lo disegna in stile HUD sopra la ripresa. JARVIS commenta la postura a voce (schiena, spalle, braccia),
/// conta le ripetizioni e a fine serie fa il riassunto. Pensato per il Pilates, va bene per squat, piegamenti, addominali.
/// Build 23: quattro scelte, Busto · Mani · Ginocchia · Ologramma. Le prime tre sono quelle di sempre; l'Ologramma (al posto
/// dello Specchio, come il mockup approvato) mette su ogni persona inquadrata la sagoma laser, i lineamenti, lo scheletro,
/// il viso a maglia, le mani e i dati (distanza, spalle, gomiti, gesti); con più persone le segue tutte (distanza e passo).
/// I tre riquadri diventano PERSONE · PUNTI · DISTANZA e scendono in basso, così il viso resta libero; Azzera e Fine serie spariscono.
/// Va con la fotocamera dietro (con il LiDAR per la distanza, dove c'è) e con quella davanti (specchiata).
/// Si apre sul Busto come sempre: l'Ologramma parte scegliendolo, oppure con «Jarvis, modalità ologramma» / «ologramma delle persone».
extension Notification.Name {
    /// «Jarvis, modalità ologramma» / «ologramma delle persone» con il Trainer già aperto: passa all'Ologramma.
    static let jarvisOlogramma = Notification.Name("jarvisOlogramma")
}

struct Allenatore: View {
    let chiudi: () -> Void
    @StateObject private var motore = MotoreAllenatore()
    @State private var orecchio = OrecchioComandi()   // «Jarvis, fine serie», «Jarvis, quante ripetizioni?», «Jarvis, pausa»…

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AnteprimaAllenatore(sessione: motore.sessione).ignoresSafeArea()
            if motore.giunto == .ologramma {
                // BUILD 23 — l'Ologramma lo disegna la ripresa vera: niente scheletro semplice sotto
                OlogrammaHUD(scena: motore.scenaOlo, cambio: motore.cambioOlo).ignoresSafeArea().allowsHitTesting(false)
            } else {
                ScheletroHUD(posa: motore.posa, allarme: motore.posturaFuori, specchio: motore.frontale).ignoresSafeArea().allowsHitTesting(false)
            }

            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("J.A.R.V.I.S.").font(.system(size: 16, weight: .bold, design: .monospaced)).tracking(4)
                        Text("PERSONAL TRAINER").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).opacity(0.7)
                    }
                    .foregroundStyle(Color.ciano)
                    Spacer()
                    Button { Suoni.tocco(); motore.cambiaCamera() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.ciano).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("Cambia fotocamera")
                    Button { Suoni.tocco(); motore.ferma(); chiudi() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.ciano).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.ciano.opacity(0.5), lineWidth: 1))
                    }
                    .accessibilityLabel("Chiudi")
                }
                .padding(.horizontal, 20).padding(.top, 8)

                // telemetria in alto (nell'Ologramma i riquadri scendono in basso: il viso resta libero)
                if motore.giunto != .ologramma {
                    HStack(spacing: 10) {
                        dato("RIPETIZIONI", "\(motore.ripetizioni)", caldo: false)
                        dato("SCHIENA", motore.posa == nil ? "—" : "\(Int(motore.inclinazioneSchiena))°", caldo: motore.inclinazioneSchiena > motore.sogliaSchiena)
                        dato("SIMMETRIA", motore.posa == nil ? "—" : "\(Int(motore.simmetria))%", caldo: motore.simmetria < 85)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                if motore.giunto == .ologramma {
                    HStack(spacing: 10) {
                        dato("PERSONE", motore.datiOlo.persone, caldo: false)
                        dato("PUNTI", motore.datiOlo.punti, caldo: false)
                        dato("DISTANZA", motore.datiOlo.distanza, caldo: false)
                    }
                    .padding(.horizontal, 20)
                }

                Text(motore.commento)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .opacity(motore.commento.isEmpty ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: motore.commento)

                Picker("Conteggio", selection: $motore.giunto) {
                    Text("Busto").tag(MotoreAllenatore.Giunto.busto)
                    Text("Mani").tag(MotoreAllenatore.Giunto.mani)
                    Text("Ginocchia").tag(MotoreAllenatore.Giunto.ginocchia)
                    Text("Ologramma").tag(MotoreAllenatore.Giunto.ologramma)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)                 // quattro scelte: un po' più di spazio che con tre
                .padding(.bottom, motore.giunto == .ologramma ? 16 : 0)

                if motore.giunto != .ologramma {          // nell'Ologramma non si contano ripetizioni: Azzera e Fine serie spariscono
                    HStack(spacing: 14) {
                        Button { Suoni.tocco(); motore.azzera() } label: {
                            Label("Azzera", systemImage: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.ciano).frame(maxWidth: .infinity).frame(height: 48)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.6), lineWidth: 1))
                        }
                        Button { Suoni.tocco(); motore.fineSerie() } label: {
                            Label("Fine serie", systemImage: "flag.checkered")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.fondo).frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.ciano2).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .buttonStyle(StileStark())
                    .padding(.horizontal, 20).padding(.bottom, 16)
                }
            }
        }
        .statusBarHidden()
        .onReceive(NotificationCenter.default.publisher(for: .jarvisOlogramma)) { _ in   // detto con il Trainer già aperto
            MotoreAllenatore.ologrammaRichiesto = false; motore.giunto = .ologramma
        }
        .task {
            if MotoreAllenatore.ologrammaRichiesto { MotoreAllenatore.ologrammaRichiesto = false; motore.giunto = .ologramma }
            await motore.avvia()
            // i comandi a voce: dopo il suono d'apertura (come nella Sentinella), sempre con «Jarvis» davanti
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            orecchio.dentro = .allenatore
            orecchio.comando = { c in
                switch c {
                case .torna: motore.ferma(); orecchio.ferma(); chiudi()
                case .allenatore(let a): motore.aVoce(a)
                default: break
                }
            }
            motore.ascoltoComandi = true
            orecchio.avvia()
        }
        .onDisappear { orecchio.ferma(); motore.ferma() }
        .aperturaHUD("Trainer", fotocamera: true)
    }

    private func dato(_ titolo: String, _ valore: String, caldo: Bool) -> some View {
        VStack(spacing: 2) {
            Text(valore).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(caldo ? Color.orange : .white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(titolo).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Color.ciano)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.black.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke((caldo ? Color.orange : Color.ciano).opacity(0.5), lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Lo scheletro disegnato sopra la ripresa

struct ScheletroHUD: View {
    let posa: [VNHumanBodyPoseObservation.JointName: CGPoint]?
    let allarme: Bool
    let specchio: Bool

    private static let ossa: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.neck, .nose), (.neck, .leftShoulder), (.neck, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.neck, .root), (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                guard let posa else { return }
                let colore = allarme ? Color.orange : Color.ciano
                func p(_ g: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                    guard let n = posa[g] else { return nil }
                    let x = specchio ? 1 - n.x : n.x
                    return CGPoint(x: x * size.width, y: (1 - n.y) * size.height)
                }
                var linee = Path()
                for (a, b) in ScheletroHUD.ossa { if let pa = p(a), let pb = p(b) { linee.move(to: pa); linee.addLine(to: pb) } }
                var bagliore = gc
                bagliore.blendMode = .plusLighter
                bagliore.stroke(linee, with: .color(colore.opacity(0.35)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                gc.stroke(linee, with: .color(colore.opacity(0.95)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                for (g, _) in posa {
                    guard let c = p(g) else { continue }
                    let r: CGFloat = g == .nose ? 7 : 5
                    gc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.9)))
                    var anello = Path()
                    let inizio = Angle(radians: t * 1.5)
                    anello.addArc(center: c, radius: r + 5, startAngle: inizio, endAngle: inizio + .radians(.pi * 1.2), clockwise: false)
                    gc.stroke(anello, with: .color(colore.opacity(0.7)), lineWidth: 1)
                }
                // linea verticale di riferimento per la schiena
                if let collo = p(.neck), let bacino = p(.root) {
                    var rif = Path()
                    rif.move(to: CGPoint(x: bacino.x, y: bacino.y)); rif.addLine(to: CGPoint(x: bacino.x, y: collo.y - 20))
                    gc.stroke(rif, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
        }
    }
}

// MARK: - BUILD 23 — L'Ologramma: cosa vede l'analisi

/// Una persona nell'Ologramma (coordinate normalizzate dall'alto, nel fotogramma verticale non specchiato).
nonisolated struct PersonaOlo: @unchecked Sendable {
    var sagoma: [CGPoint]                                              // il contorno (vuoto se la maschera non l'ha presa)
    var box: CGRect                                                    // dalla sagoma, o dai punti del corpo
    var giunti: [VNHumanBodyPoseObservation.JointName: CGPoint]
    var fiducia: [VNHumanBodyPoseObservation.JointName: Float]
    var viso: VisoOlo?
    var mani: [[CGPoint?]]                                             // 21 punti, nell'ordine del mockup (polso, pollice…, mignolo)
    var distanza: Double?                                              // metri
    var velocita: Double?                                              // km/h (con più persone)
}

/// Il viso: i punti di Vision, la maglia (triangoli di Delaunay, 3 indici per triangolo), i contorni, le pupille e le tempie.
nonisolated struct VisoOlo: @unchecked Sendable {
    var punti: [CGPoint]
    var triangoli: [Int]
    var linee: [[CGPoint]]
    var pupille: (CGPoint, CGPoint)                                    // da sinistra a destra nel fotogramma
    var tempie: (CGPoint, CGPoint)
}

/// Un fotogramma analizzato.
nonisolated struct ScenaOlo: @unchecked Sendable {
    var persone: [PersonaOlo]
    var frontale: Bool
    var dimensione: CGSize                                             // pixel del fotogramma verticale
    var fuoco: Double                                                  // focale in pixel
    var lineamenti: CGImage?
    var regione: CGRect                                                // dove stanno i lineamenti (normalizzata)
    var punti: Int                                                     // i punti disegnati (PUNTI)
}

// MARK: - L'Ologramma disegnato (come olografaPersona e olografaFolla del mockup)

struct OlogrammaHUD: View {
    let scena: ScenaOlo?
    let cambio: Date

    typealias G = VNHumanBodyPoseObservation.JointName
    /// Le ossa del mockup (OSSA17): spalle, braccia, fianchi, gambe; più collo → naso.
    private static let ossa: [(G, G)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist), (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist), (.leftShoulder, .leftHip), (.rightShoulder, .rightHip), (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle), (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.neck, .nose),
    ]
    private static let visoCorpo: Set<G> = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
    /// Le dita: catene di punti della mano (polso 0, pollice 1-4, indice 5-8, medio 9-12, anulare 13-16, mignolo 17-20).
    private static let dita: [[Int]] = [[0, 1, 2, 3, 4], [0, 5, 6, 7, 8], [5, 9, 10, 11, 12], [9, 13, 14, 15, 16], [13, 17], [0, 17, 18, 19, 20]]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
            Canvas { gc, size in
                DisegnoOlo.vignetta(gc, W: size.width, H: size.height, interno: 0.35, alfa: 0.55)
                guard let scena, !scena.persone.isEmpty else { return }
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                let prog = min(1, max(0, ctx.date.timeIntervalSince(cambio) / 1.1))
                let q = Inquadra(schermo: size, immagine: scena.dimensione, specchio: scena.frontale)
                var posti = PostiEtichette(H: size.height, k: q.k, alto: 118, basso: 236)
                if scena.persone.count >= 2 { folla(gc, q, scena, t: t, prog: prog, posti: &posti) }
                else { persona(gc, q, scena, scena.persone[0], t: t, prog: prog, posti: &posti) }
            }
        }
    }

    private func a(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Una persona da vicino: sagoma, lineamenti, scheletro, viso a maglia, mani e i cartellini.
    private func persona(_ gc: GraphicsContext, _ q: Inquadra, _ s: ScenaOlo, _ p: PersonaOlo, t: Double, prog: Double, posti: inout PostiEtichette) {
        let k = q.k, iw = s.dimensione.width, ih = s.dimensione.height
        let sagoma = q.percorso(p.sagoma)
        DisegnoOlo.sagomaLaser(gc, sagoma, t: t, k: k, a: min(1, prog * 1.6) * 0.95)
        if let li = s.lineamenti { DisegnoOlo.lineamenti(gc, immagine: li, in: q.rett(s.regione), clip: sagoma, specchio: q.specchio, a: min(1, prog * 1.4)) }
        func ok(_ j: G) -> CGPoint? {
            guard let v = p.giunti[j], (p.fiducia[j] ?? 0) > 0.3, v.x > 0, v.y > 0, v.x < 1, v.y < 0.94 else { return nil }
            return v
        }
        // lo scheletro
        do {
            var c = gc
            c.opacity = a((prog - 0.15) * 2)
            var linee = Path()
            for (u, v) in Self.ossa { if let pu = ok(u), let pv = ok(v) { linee.move(to: q.p(pu)); linee.addLine(to: q.p(pv)) } }
            c.stroke(linee, with: .color(TintaOlo.ciano.opacity(0.22)), style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
            c.stroke(linee, with: .color(TintaOlo.ciano.opacity(0.95)), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round))
            for (j, _) in p.giunti {
                if p.viso != nil && Self.visoCorpo.contains(j) { continue }
                guard let v = ok(j) else { continue }
                let P = q.p(v)
                c.stroke(Path(ellipseIn: CGRect(x: P.x - 5 * k, y: P.y - 5 * k, width: 10 * k, height: 10 * k)), with: .color(.white.opacity(0.9)), lineWidth: 1.3 * k)
                c.fill(Path(ellipseIn: CGRect(x: P.x - 2 * k, y: P.y - 2 * k, width: 4 * k, height: 4 * k)), with: .color(TintaOlo.ciano))
            }
        }
        // il viso: la maglia e i contorni di occhi, naso, bocca
        if let viso = p.viso {
            var c = gc
            c.opacity = a((prog - 0.3) * 2)
            var maglia = Path()
            var i = 0
            while i + 2 < viso.triangoli.count {
                let A = q.p(viso.punti[viso.triangoli[i]]), B = q.p(viso.punti[viso.triangoli[i + 1]]), C = q.p(viso.punti[viso.triangoli[i + 2]])
                maglia.move(to: A); maglia.addLine(to: B); maglia.addLine(to: C); maglia.closeSubpath()
                i += 3
            }
            c.stroke(maglia, with: .color(TintaOlo.ciano.opacity(0.42)), lineWidth: 0.7 * k)
            var linee = Path()
            for l in viso.linee {
                guard let primo = l.first else { continue }
                linee.move(to: q.p(primo))
                for v in l.dropFirst() { linee.addLine(to: q.p(v)) }
            }
            c.stroke(linee, with: .color(TintaOlo.filo.opacity(0.9)), lineWidth: 1.4 * k)
            var punti = Path()
            for v in viso.punti { let P = q.p(v); punti.addRect(CGRect(x: P.x - 1.1 * k, y: P.y - 1.1 * k, width: 2.2 * k, height: 2.2 * k)) }
            c.fill(punti, with: .color(.white))
        }
        // le mani: 21 punti, le ossa delle dita
        if !p.mani.isEmpty {
            var c = gc
            c.opacity = a((prog - 0.4) * 2)
            for m in p.mani {
                var ossa = Path()
                for catena in Self.dita {
                    var aperta = false
                    for j in catena {
                        guard let v = m[j] else { aperta = false; continue }
                        if aperta { ossa.addLine(to: q.p(v)) } else { ossa.move(to: q.p(v)); aperta = true }
                    }
                }
                c.stroke(ossa, with: .color(TintaOlo.ambra.opacity(0.22)), lineWidth: 5 * k)
                c.stroke(ossa, with: .color(TintaOlo.ambra.opacity(0.95)), lineWidth: 1.6 * k)
                for (j, v) in m.enumerated() {
                    guard let v else { continue }
                    let P = q.p(v), punta = [4, 8, 12, 16, 20].contains(j), r = (punta ? 2.8 : 1.9) * k
                    c.fill(Path(ellipseIn: CGRect(x: P.x - r, y: P.y - r, width: 2 * r, height: 2 * r)), with: .color(punta ? .white : TintaOlo.ambra))
                }
            }
        }
        // i dati, calcolati dai punti
        let la = a((prog - 0.55) * 2.2)
        guard la > 0 else { return }
        let metro: Double? = p.distanza.map { $0 / max(1, s.fuoco) }       // metri per pixel alla distanza della persona
        if let viso = p.viso {
            let (e1, e2) = viso.pupille
            let inc = abs(atan2(Double((e2.y - e1.y) * ih), Double((e2.x - e1.x) * iw)) * 180 / .pi)
            // il cartellino accanto alla testa, dal lato con più spazio; il filo parte dalla tempia
            let ta = q.p(viso.tempie.0), tb = q.p(viso.tempie.1)
            let dx = ta.x > tb.x ? ta : tb, sx = ta.x > tb.x ? tb : ta
            let destra = q.W - dx.x > sx.x, testa = destra ? dx : sx
            DisegnoOlo.etichetta(gc, &posti, k: k, W: q.W, ax: testa.x, ay: testa.y, lx: destra ? testa.x + 22 * k : testa.x - 22 * k, ly: testa.y - 70 * k,
                                 righe: ["SOGGETTO 1", "DISTANZA " + (p.distanza.map { DisegnoOlo.nf($0, 2) + " m" } ?? "—"), "TESTA \(Int(inc.rounded()))°"],
                                 a: la, col: TintaOlo.ciano, grande: true)
        }
        if let s1 = ok(.leftShoulder), let s2 = ok(.rightShoulder) {
            let ddx = Double((s1.x - s2.x) * iw), ddy = Double((s1.y - s2.y) * ih)
            let larg = hypot(ddx, ddy)
            let tilt = abs(atan2(ddy, ddx) * 180 / .pi).truncatingRemainder(dividingBy: 180)
            let tl = Int(min(tilt, 180 - tilt).rounded())
            let P1 = q.p(s1), P2 = q.p(s2), sx = P1.x < P2.x ? P1 : P2
            DisegnoOlo.etichetta(gc, &posti, k: k, W: q.W, ax: sx.x, ay: sx.y, lx: max(8 * k, sx.x - 30 * k), ly: sx.y + 34 * k,
                                 righe: ["SPALLE " + (metro.map { "\(Int((larg * $0 * 100).rounded())) cm" } ?? "—"), "INCLINAZIONE \(tl)°"], a: la)
        }
        for (sp, go, po) in [(G.leftShoulder, G.leftElbow, G.leftWrist), (G.rightShoulder, G.rightElbow, G.rightWrist)] {
            guard let a1 = ok(sp), let b1 = ok(go), let c1 = ok(po), c1.y < 1 - 4 / ih else { continue }
            let P = q.p(b1)
            if P.y > q.H - 150 * k || P.y < 0 { continue }
            let gradi = DisegnoOlo.angolo(CGPoint(x: a1.x * iw, y: a1.y * ih), CGPoint(x: b1.x * iw, y: b1.y * ih), CGPoint(x: c1.x * iw, y: c1.y * ih))
            DisegnoOlo.etichetta(gc, &posti, k: k, W: q.W, ax: P.x, ay: P.y, lx: P.x + (P.x > q.W / 2 ? 26 : -26) * k, ly: P.y - 26 * k,
                                 righe: ["GOMITO \(gradi)°"], a: la, col: TintaOlo.ambra)
        }
        for m in p.mani {
            guard let g = DisegnoOlo.gesto(m.map { punto in punto.map { CGPoint(x: $0.x * iw, y: $0.y * ih) } }), let pollice = m[4] else { continue }
            let P = q.p(pollice)
            DisegnoOlo.etichetta(gc, &posti, k: k, W: q.W, ax: P.x, ay: P.y, lx: P.x + (P.x > q.W / 2 ? -40 : 40) * k, ly: P.y - 30 * k,
                                 righe: ["GESTO", g], a: la, col: TintaOlo.ambra)
        }
    }

    /// Più persone (strada): sagoma, scheletro, distanza e passo su ognuna.
    private func folla(_ gc: GraphicsContext, _ q: Inquadra, _ s: ScenaOlo, t: Double, prog: Double, posti: inout PostiEtichette) {
        let k = q.k
        if let li = s.lineamenti {
            var tutte = Path()
            for p in s.persone where p.sagoma.count >= 3 { tutte.addPath(q.percorso(p.sagoma)) }
            DisegnoOlo.lineamenti(gc, immagine: li, in: q.rett(s.regione), clip: tutte, specchio: q.specchio, a: min(1, prog * 1.4))
        }
        for (n, p) in s.persone.enumerated() {
            if p.sagoma.count >= 3 { DisegnoOlo.sagomaLaser(gc, q.percorso(p.sagoma), t: t, k: k * 0.7, a: min(1, prog * 1.6) * 0.9) }
            var c = gc
            c.opacity = a((prog - 0.15) * 2)
            var linee = Path(), punti = Path()
            for (u, v) in Self.ossa where (p.fiducia[u] ?? 0) > 0.2 && (p.fiducia[v] ?? 0) > 0.2 {
                if let pu = p.giunti[u], let pv = p.giunti[v] { linee.move(to: q.p(pu)); linee.addLine(to: q.p(pv)) }
            }
            for (j, v) in p.giunti where (p.fiducia[j] ?? 0) > 0.2 {
                let P = q.p(v)
                punti.addRect(CGRect(x: P.x - 1.3 * k, y: P.y - 1.3 * k, width: 2.6 * k, height: 2.6 * k))
            }
            c.stroke(linee, with: .color(TintaOlo.ciano.opacity(0.95)), lineWidth: 1.6 * k)
            c.fill(punti, with: .color(.white))
            let A = q.p(p.box.midX, p.box.minY)
            if A.x < -20 || A.x > q.W + 20 { continue }
            let passo = p.velocita.map { $0 > 1.5 ? DisegnoOlo.nf($0) + " km/h" : "FERMA" } ?? "FERMA"
            let metri = p.distanza.map { "\(Int($0.rounded())) m" } ?? "—"
            DisegnoOlo.etichetta(gc, &posti, k: k * 0.82, W: q.W, ax: A.x, ay: A.y - 2 * k, lx: A.x + (A.x > q.W * 0.6 ? -14 : 14) * k, ly: A.y - 26 * k,
                                 righe: ["PERSONA \(n + 1)", "\(metri) · \(passo)"], a: a((prog - 0.5) * 2))
        }
    }
}

// MARK: - L'analisi dell'Ologramma (Vision, sulla coda della fotocamera)

/// Corpo (VNDetectHumanBodyPoseRequest, più persone), sagome (VNGeneratePersonInstanceMaskRequest, iOS 17, un fotogramma sì e uno no),
/// con una sola persona anche viso (VNDetectFaceLandmarksRequest) e mani (VNDetectHumanHandPoseRequest); la distanza dal LiDAR
/// (dove c'è), se no dalla distanza tra le pupille (6,3 cm) o dall'altezza (1,70 m); il passo dalle distanze nel tempo.
nonisolated final class AnalisiOlogramma: @unchecked Sendable {
    typealias G = VNHumanBodyPoseObservation.JointName
    private let corpo = VNDetectHumanBodyPoseRequest()
    private let mani: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let viso = VNDetectFaceLandmarksRequest()
    private let sagome = VNGeneratePersonInstanceMaskRequest()
    private var turno = 0
    private var ultimeSagome: [Sagoma] = []
    private var maglia: (n: Int, triangoli: [Int], quando: Date)?
    private nonisolated struct Traccia { var centro: CGPoint; var storia: [(t: Date, x: Double, d: Double)]; var visto: Date }
    private var tracce: [Int: Traccia] = [:]
    private var prossimoId = 1

    private static let ordineMano: [VNHumanHandPoseObservation.JointName] = [
        .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip, .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip, .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    func azzera() { turno = 0; ultimeSagome = []; maglia = nil; tracce = [:] }

    func analizza(_ px: CVPixelBuffer, frontale: Bool, fuoco: Double, profondita: MappaProfondita?) -> ScenaOlo {
        turno += 1
        let iw = CGFloat(CVPixelBufferGetWidth(px)), ih = CGFloat(CVPixelBufferGetHeight(px))
        let gestore = VNImageRequestHandler(cvPixelBuffer: px, orientation: .up, options: [:])
        let conSagome = turno % 2 == 1 || ultimeSagome.isEmpty
        let richieste: [VNRequest] = conSagome ? [corpo, sagome] : [corpo]
        try? gestore.perform(richieste)
        if conSagome, let risultati = sagome.results {
            if let o = risultati.first, let g = Maschere.griglia(o) { ultimeSagome = Maschere.sagome(g, istanze: o.allInstances, minimo: 0.0015) }
            else { ultimeSagome = [] }
        }
        // i corpi (punti con un minimo di fiducia), dall'alto
        var corpi: [([G: CGPoint], [G: Float])] = []
        for o in corpo.results ?? [] {
            guard let tutti = try? o.recognizedPoints(.all) else { continue }
            var g: [G: CGPoint] = [:], f: [G: Float] = [:]
            for (n, r) in tutti where r.confidence > 0.2 { g[n] = CGPoint(x: r.location.x, y: 1 - r.location.y); f[n] = r.confidence }
            if g.count >= 4 { corpi.append((g, f)) }
        }
        // ogni corpo con la sua sagoma (quella che contiene il bacino, il collo o il naso)
        var libere = Array(ultimeSagome.indices)
        var persone: [PersonaOlo] = []
        for (g, f) in corpi {
            let ancore = [G.root, .neck, .nose, .leftShoulder, .rightShoulder].compactMap { g[$0] }
            var scelta: Int?
            for i in libere where ancore.contains(where: { ultimeSagome[i].griglia.a($0.x, $0.y) != 0 }) { scelta = i; break }
            var sagoma: [CGPoint] = [], box = Self.riquadro(Array(g.values))
            if let i = scelta {
                sagoma = ultimeSagome[i].contorno; box = ultimeSagome[i].box
                libere.removeAll { $0 == i }
            }
            persone.append(PersonaOlo(sagoma: sagoma, box: box, giunti: g, fiducia: f, viso: nil, mani: [], distanza: nil, velocita: nil))
        }
        // le sagome senza scheletro (persone lontane o girate) contano lo stesso
        for i in libere where ultimeSagome[i].area >= 0.003 {
            persone.append(PersonaOlo(sagoma: ultimeSagome[i].contorno, box: ultimeSagome[i].box, giunti: [:], fiducia: [:], viso: nil, mani: [], distanza: nil, velocita: nil))
        }
        var punti = 0
        if persone.count == 1 {
            // una persona da vicino: anche viso e mani (stesso fotogramma)
            try? gestore.perform([viso, mani])
            if let f = (viso.results ?? []).max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
                persone[0].viso = visoOlo(f, iw: iw, ih: ih)
            }
            for o in mani.results ?? [] {
                guard let tutti = try? o.recognizedPoints(.all) else { continue }
                let m: [CGPoint?] = Self.ordineMano.map { n in
                    guard let r = tutti[n], r.confidence > 0.3 else { return nil }
                    return CGPoint(x: r.location.x, y: 1 - r.location.y)
                }
                if m.compactMap({ $0 }).count >= 6 { persone[0].mani.append(m) }
            }
            let p = persone[0]
            punti = p.giunti.filter { (p.fiducia[$0.key] ?? 0) > 0.3 && !(p.viso != nil && [G.nose, .leftEye, .rightEye, .leftEar, .rightEar].contains($0.key)) }.count
                + (p.viso?.punti.count ?? 0) + p.mani.reduce(0) { somma, m in somma + m.compactMap { $0 }.count }
        } else {
            for p in persone { punti += p.fiducia.values.filter { $0 > 0.2 }.count }
        }
        // le distanze
        for i in persone.indices { persone[i].distanza = distanza(persone[i], sola: persone.count == 1, iw: iw, ih: ih, fuoco: fuoco, profondita: profondita) }
        // il passo (con più persone): chi è chi da un fotogramma all'altro, per vicinanza
        if persone.count >= 2 { passo(&persone, iw: iw, fuoco: fuoco) } else { tracce = [:] }
        // i lineamenti: i bordi del fotogramma attorno a tutte le sagome
        let conSagoma = persone.filter { $0.sagoma.count >= 3 }
        var regione = CGRect.null
        for p in conSagoma { regione = regione.union(p.box) }
        var lineamenti: CGImage?
        if !regione.isNull {
            regione = regione.insetBy(dx: -0.01, dy: -0.01).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            lineamenti = ImmagineOlo.lineamenti(px, regione: regione)
        }
        return ScenaOlo(persone: persone, frontale: frontale, dimensione: CGSize(width: iw, height: ih), fuoco: fuoco,
                        lineamenti: lineamenti, regione: regione.isNull ? .zero : regione, punti: punti)
    }

    private static func riquadro(_ p: [CGPoint]) -> CGRect {
        guard let a = p.first else { return .zero }
        var r = CGRect(origin: a, size: .zero)
        for q in p.dropFirst() { r = r.union(CGRect(origin: q, size: .zero)) }
        return r
    }

    /// Il viso: i punti (allPoints), la maglia di Delaunay (rifatta ogni 1,5 s o se cambia il numero di punti), i contorni.
    private func visoOlo(_ f: VNFaceObservation, iw: CGFloat, ih: CGFloat) -> VisoOlo? {
        guard let lm = f.landmarks, let tutti = lm.allPoints else { return nil }
        let uno = CGSize(width: 1, height: 1)
        func punti(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] { (r?.pointsInImage(imageSize: uno) ?? []).map { CGPoint(x: $0.x, y: 1 - $0.y) } }
        let p = punti(tutti)
        guard p.count >= 8 else { return nil }
        if maglia == nil || maglia?.n != p.count || Date().timeIntervalSince(maglia?.quando ?? .distantPast) > 1.5 {
            let t = Delaunay.triangoli(p.map { CGPoint(x: $0.x * iw, y: $0.y * ih) })
            maglia = (p.count, t.flatMap { [$0.0, $0.1, $0.2] }, Date())
        }
        func chiuso(_ l: [CGPoint]) -> [CGPoint] { l.count > 2 ? l + [l[0]] : l }
        let linee = [punti(lm.faceContour), punti(lm.leftEyebrow), punti(lm.rightEyebrow), punti(lm.noseCrest), punti(lm.nose),
                     chiuso(punti(lm.leftEye)), chiuso(punti(lm.rightEye)), chiuso(punti(lm.outerLips)), chiuso(punti(lm.innerLips))].filter { $0.count >= 2 }
        func centro(_ l: [CGPoint]) -> CGPoint? {
            guard !l.isEmpty else { return nil }
            return CGPoint(x: l.map(\.x).reduce(0, +) / CGFloat(l.count), y: l.map(\.y).reduce(0, +) / CGFloat(l.count))
        }
        guard let o1 = punti(lm.leftPupil).first ?? centro(punti(lm.leftEye)),
              let o2 = punti(lm.rightPupil).first ?? centro(punti(lm.rightEye)) else { return nil }
        let contorno = punti(lm.faceContour)
        let tempie = (contorno.first ?? o1, contorno.last ?? o2)
        return VisoOlo(punti: p, triangoli: maglia?.triangoli ?? [], linee: linee, pupille: o1.x <= o2.x ? (o1, o2) : (o2, o1), tempie: tempie)
    }

    /// LiDAR (dove c'è) sul viso o sul busto; se no le pupille (6,3 cm) o l'altezza (1,70 m in piedi, 1,50 m dal naso alle caviglie).
    private func distanza(_ p: PersonaOlo, sola: Bool, iw: CGFloat, ih: CGFloat, fuoco: Double, profondita: MappaProfondita?) -> Double? {
        var punto: CGPoint?
        if let v = p.viso { punto = CGPoint(x: (v.pupille.0.x + v.pupille.1.x) / 2, y: (v.pupille.0.y + v.pupille.1.y) / 2) }
        else if let s1 = p.giunti[.leftShoulder], let s2 = p.giunti[.rightShoulder] { punto = CGPoint(x: (s1.x + s2.x) / 2, y: (s1.y + s2.y) / 2 + 0.03) }
        else if p.box.width > 0 { punto = CGPoint(x: p.box.midX, y: p.box.minY + p.box.height * 0.35) }
        if let punto, let m = profondita?.metri(punto.x, punto.y) { return m }
        if let v = p.viso {
            let ipd = hypot(Double((v.pupille.1.x - v.pupille.0.x) * iw), Double((v.pupille.1.y - v.pupille.0.y) * ih))
            if ipd > 4 { return fuoco * 0.063 / ipd }
        }
        if !sola, p.box.height > 0.02, p.sagoma.count >= 3 { return fuoco * 1.7 / Double(p.box.height * ih) }
        if let naso = p.giunti[.nose], let c = p.giunti[.leftAnkle] ?? p.giunti[.rightAnkle], c.y - naso.y > 0.05 {
            return fuoco * 1.5 / Double((c.y - naso.y) * ih)
        }
        return nil
    }

    /// Il passo di ognuno: spostamento di lato (dai pixel e dalla distanza) e in profondità, sull'ultimo mezzo secondo circa.
    private func passo(_ persone: inout [PersonaOlo], iw: CGFloat, fuoco: Double) {
        let adesso = Date()
        var usate = Set<Int>()
        for i in persone.indices {
            guard let d = persone[i].distanza else { continue }
            let c = CGPoint(x: persone[i].box.midX, y: persone[i].box.midY)
            let x = Double(c.x * iw) * d / max(1, fuoco)                   // metri di lato
            let vicina = tracce.filter { !usate.contains($0.key) && hypot($0.value.centro.x - c.x, $0.value.centro.y - c.y) < 0.12 }
                .min { hypot($0.value.centro.x - c.x, $0.value.centro.y - c.y) < hypot($1.value.centro.x - c.x, $1.value.centro.y - c.y) }
            let id: Int
            if let v = vicina { id = v.key } else { id = prossimoId; prossimoId += 1; tracce[id] = Traccia(centro: c, storia: [], visto: adesso) }
            usate.insert(id)
            guard var tr = tracce[id] else { continue }
            let liscia = tr.storia.last.map { $0.d * 0.7 + d * 0.3 } ?? d
            tr.storia.append((adesso, x, liscia))
            tr.storia.removeAll { adesso.timeIntervalSince($0.t) > 1.2 }
            tr.centro = c; tr.visto = adesso
            tracce[id] = tr
            if let vecchio = tr.storia.first(where: { adesso.timeIntervalSince($0.t) >= 0.4 }) ?? tr.storia.first {
                let dt = adesso.timeIntervalSince(vecchio.t)
                if dt >= 0.2 { persone[i].velocita = hypot(x - vecchio.x, liscia - vecchio.d) / dt * 3.6 }
            }
        }
        tracce = tracce.filter { adesso.timeIntervalSince($0.value.visto) < 1 }
    }
}

struct AnteprimaAllenatore: UIViewRepresentable {
    let sessione: AVCaptureSession
    final class Vista: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var anteprima: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> Vista {
        let v = Vista(); v.backgroundColor = .black
        v.anteprima.session = sessione; v.anteprima.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ v: Vista, context: Context) {}
}

// MARK: - Il motore: fotocamera, Vision, conteggio e commenti

@MainActor
final class MotoreAllenatore: NSObject, ObservableObject {
    enum Giunto { case busto, mani, ginocchia, ologramma }   // build 23: l'Ologramma al posto dello Specchio

    @Published var posa: [VNHumanBodyPoseObservation.JointName: CGPoint]?
    @Published var ripetizioni = 0
    @Published var inclinazioneSchiena: Double = 0
    @Published var simmetria: Double = 100
    @Published var posturaFuori = false
    @Published var commento = ""
    @Published var frontale = false
    @Published var giunto: Giunto = .busto { didSet { cambiaGiunto(da: oldValue) } }   // si apre sul Busto, come sempre
    /// «Jarvis, modalità ologramma» con il Trainer ancora chiuso: l'Ologramma parte appena si apre.
    static var ologrammaRichiesto = false

    // BUILD 23 — Ologramma
    @Published var scenaOlo: ScenaOlo?
    @Published var cambioOlo = Date()                          // da qui l'ologramma si «accende» (sagoma, poi scheletro, viso, mani, dati)
    @Published var datiOlo: (persone: String, punti: String, distanza: String) = ("—", "—", "—")
    private var modoOlo: String?                               // "selfie", "persona", "strada": la frase sotto
    private var candidatoOlo: (modo: String, da: Date)?
    private var ultimaPersonaOlo = Date.distantPast
    private static let frasiOlo = ["selfie": "Frontale: l'ologramma è su di lei, Sir.", "persona": "Ologramma agganciato sulla persona, Sir.",
                                   "strada": "Persone in vista: le seguo tutte, Sir."]

    /// Oltre questa inclinazione la schiena è «fuori asse».
    let sogliaSchiena: Double = 12

    private let camera = CameraPosa()
    var sessione: AVCaptureSession { camera.sessione }

    // conteggio: posizione «su» e «giù» del giunto scelto, con isteresi
    private var altezza: Double = 0            // 0 in alto, 1 in basso (coordinate schermo)
    private var minimo: Double = 1, massimo: Double = 0
    private var giu = false
    private var ultimoCampione = Date.distantPast
    private var serieSchiena: [Double] = [], serieSimmetria: [Double] = []
    private var ultimoCommento = Date.distantPast
    private var ultimoAvviso = ""
    private var voceInCorso = false
    private var lettore: AVAudioPlayer?
    private let sintesi = AVSpeechSynthesizer()
    private var inizioSerie = Date()
    private var avviato = false
    var ascoltoComandi = false                  // il microfono dei comandi è acceso: la voce non deve spegnerlo
    @Published var inPausa = false

    /// I comandi a voce («Jarvis, …»): gli stessi tasti, più le domande sulla serie e la pausa.
    func aVoce(_ a: ComandoVocale.AzioneAllenatore) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch a {
        case .fineSerie: inPausa = false; fineSerie()
        case .azzera: inPausa = false; azzera(); Task { await parla("Azzerato, Sir.") }
        case .ripetizioni:
            let n = ripetizioni
            Task { await parla(n == 0 ? "Nessuna ripetizione contata, Sir." : "\(n) ripetizion\(n == 1 ? "e" : "i"), Sir.") }
        case .postura:
            guard posa != nil else { Task { await parla("Non la vedo, Sir: si metta tutta nell'inquadratura.") }; return }
            let sch = Int(inclinazioneSchiena), sim = Int(simmetria), soglia = Int(sogliaSchiena)
            let giudizio = sch <= soglia && sim >= 85 ? "Va bene così." : (sch > soglia ? "Raddrizzi la schiena." : "Cerchi la simmetria.")
            Task { await parla("Schiena a \(sch) gradi, simmetria al \(sim) per cento. \(giudizio)") }
        case .camera: cambiaCamera()
        case .pausa:
            inPausa = true
            commento = "In pausa. «Jarvis, riprendi» per continuare."
            Task { await parla("In pausa, Sir.") }
        case .riprendi:
            inPausa = false
            commento = "Si riparte, Sir."
            Task { await parla("Si riparte, Sir.") }
        case .pronto:                             // «Jarvis, allenati allo specchio» con il Trainer già aperto (come il mockup)
            Task { await parla("Personal trainer pronto, Sir.") }
        case .conta(let parte):
            switch parte {
            case .busto: giunto = .busto
            case .mani: giunto = .mani
            case .ginocchia: giunto = .ginocchia
            case .ologramma: giunto = .ologramma
            }
            let frase: String
            switch parte {
            case .busto: frase = "Conto il busto, Sir."
            case .mani: frase = "Conto le mani, Sir."
            case .ginocchia: frase = "Conto le ginocchia, Sir."
            case .ologramma: frase = "Ologramma, Sir."                    // decisione 28: «… ologramma» detto dentro il Trainer
            }
            Task { await parla(frase) }
        }
    }

    func avvia() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { commento = "Serve il permesso fotocamera, Sir."; return }
        camera.esito = { [weak self] punti in Task { @MainActor [weak self] in self?.ricevi(punti) } }
        camera.esitoOlo = { [weak self] scena in Task { @MainActor [weak self] in self?.riceviOlo(scena) } }
        avviato = true
        configura(frontale: false)
        inizioSerie = Date()
        commento = giunto == .ologramma ? "Aggancio l'ologramma, Sir…" : "Inquadri tutta la persona, Sir."
    }

    func ferma() {
        camera.ferma()
        lettore?.stop(); lettore = nil
        sintesi.stopSpeaking(at: .immediate)
    }

    func cambiaCamera() { configura(frontale: !frontale) }

    func azzera() {
        azzeraConteggio()
        serieSchiena.removeAll(); serieSimmetria.removeAll()
        inizioSerie = Date()
        commento = "Azzerato. Quando vuole, Sir."
    }

    private func azzeraConteggio() { ripetizioni = 0; minimo = 1; massimo = 0; giu = false }

    /// Busto · Mani · Ginocchia · Ologramma: il conteggio riparte; entrando o uscendo dall'Ologramma la fotocamera dietro
    /// passa al LiDAR (o torna quella di sempre).
    private func cambiaGiunto(da prima: Giunto) {
        azzeraConteggio()
        guard (prima == .ologramma) != (giunto == .ologramma) else { return }
        let olo = giunto == .ologramma
        camera.usaOlo(olo)
        scenaOlo = nil; modoOlo = nil; candidatoOlo = nil
        datiOlo = ("—", "—", "—")
        if olo { cambioOlo = Date(); commento = "Aggancio l'ologramma, Sir…" }
        else { posa = nil; commento = "Inquadri tutta la persona, Sir." }
        if avviato && !frontale { configura(frontale: false) }   // dietro: LiDAR sì o no
    }

    func fineSerie() {
        let n = ripetizioni
        let schiena = serieSchiena.isEmpty ? 0 : serieSchiena.reduce(0, +) / Double(serieSchiena.count)
        let simm = serieSimmetria.isEmpty ? 100 : serieSimmetria.reduce(0, +) / Double(serieSimmetria.count)
        let durata = Int(Date().timeIntervalSince(inizioSerie))
        var frase = n == 0 ? "Serie chiusa senza ripetizioni contate, Sir." : "Serie chiusa: \(n) ripetizion\(n == 1 ? "e" : "i") in \(durata / 60) minuti e \(durata % 60) secondi."
        if !serieSchiena.isEmpty {
            frase += schiena < 8 ? " Schiena allineata per tutta la serie, davvero bene." : schiena < 15 ? " Schiena un po' inclinata, in media \(Int(schiena)) gradi: si può fare meglio." : " Attenzione alla schiena: in media \(Int(schiena)) gradi fuori asse."
            frase += simm >= 92 ? " Simmetria ottima." : " Simmetria al \(Int(simm)) per cento: un lato lavora più dell'altro."
        }
        commento = frase
        Task { await parla(frase) }
        azzera()
        commento = frase
    }

    private func configura(frontale nuova: Bool) {
        let olo = giunto == .ologramma
        camera.configura(frontale: nuova, olo: olo) { [weak self] ok in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if ok {
                    if self.frontale != nuova, self.giunto == .ologramma { self.cambioOlo = Date(); self.modoOlo = nil; self.candidatoOlo = nil }
                    self.frontale = nuova
                } else { self.commento = "Fotocamera non disponibile, Sir." }
            }
        }
    }

    // MARK: Ologramma (build 23)

    /// Un fotogramma analizzato: i tre riquadri (persone, punti, distanza) e la frase sotto, come il mockup.
    private func riceviOlo(_ s: ScenaOlo) {
        guard giunto == .ologramma else { return }
        scenaOlo = s
        let n = s.persone.count
        let vicina = s.persone.compactMap(\.distanza).min()
        datiOlo = ("\(n)", "\(s.punti)", vicina.map { $0 < 10 ? DisegnoOlo.nf($0, 1) + " m" : "\(Int($0.rounded())) m" } ?? "—")
        let adesso = Date()
        guard n > 0 else {
            // nessuno per più di un secondo e mezzo: si riaggancia da capo
            if modoOlo != nil, adesso.timeIntervalSince(ultimaPersonaOlo) > 1.5 { modoOlo = nil; candidatoOlo = nil; commento = "Aggancio l'ologramma, Sir…" }
            return
        }
        ultimaPersonaOlo = adesso
        let modo = s.frontale ? "selfie" : (n == 1 ? "persona" : "strada")
        guard modo != modoOlo else { candidatoOlo = nil; return }
        if modoOlo == nil {                                   // il primo aggancio: subito, e l'ologramma si accende
            modoOlo = modo; commento = Self.frasiOlo[modo] ?? ""; cambioOlo = adesso; candidatoOlo = nil
        } else if let c = candidatoOlo, c.modo == modo {
            if adesso.timeIntervalSince(c.da) > 0.8 { modoOlo = modo; commento = Self.frasiOlo[modo] ?? ""; candidatoOlo = nil }   // stabile: cambia la frase
        } else {
            candidatoOlo = (modo, adesso)
        }
    }

    // MARK: Analisi di ogni posa (Busto · Mani · Ginocchia)

    private func ricevi(_ punti: [VNHumanBodyPoseObservation.JointName: CGPoint]?) {
        guard giunto != .ologramma else { return }
        posa = punti
        guard !inPausa else { posturaFuori = false; return }      // in pausa: lo scheletro si vede, niente conteggio né commenti
        guard let p = punti, let collo = p[.neck], let bacino = p[.root] else { posturaFuori = false; return }
        // schiena: angolo tra bacino→collo e la verticale (coordinate Vision: y verso l'alto)
        let dx = (collo.x - bacino.x) * 0.5625, dy = collo.y - bacino.y   // il fotogramma è verticale 9:16: l'asse x va riscalato
        let angolo = abs(atan2(dx, dy)) * 180 / .pi
        inclinazioneSchiena = inclinazioneSchiena * 0.7 + angolo * 0.3
        // simmetria: spalle e polsi alla stessa altezza, in rapporto alla larghezza delle spalle
        if let sx = p[.leftShoulder], let dxs = p[.rightShoulder] {
            let larg = max(0.05, abs(sx.x - dxs.x))
            var scarto = abs(sx.y - dxs.y) / larg
            if let px = p[.leftWrist], let pd = p[.rightWrist] { scarto = max(scarto, abs(px.y - pd.y) / larg * 0.5) }
            let s = max(0, 100 - scarto * 100)
            simmetria = simmetria * 0.7 + s * 0.3
        }
        posturaFuori = inclinazioneSchiena > sogliaSchiena || simmetria < 85
        let adesso = Date()
        if adesso.timeIntervalSince(ultimoCampione) > 0.5 {
            ultimoCampione = adesso
            serieSchiena.append(inclinazioneSchiena); serieSimmetria.append(simmetria)
        }
        conta(p)
        commenta(adesso)
    }

    /// Conta le ripetizioni: il giunto scelto scende sotto una soglia e torna su.
    private func conta(_ p: [VNHumanBodyPoseObservation.JointName: CGPoint]) {
        let y: Double?
        switch giunto {
        case .busto: y = p[.neck].map { 1 - $0.y }
        case .mani: if let a = p[.leftWrist], let b = p[.rightWrist] { y = 1 - (a.y + b.y) / 2 } else { y = nil }
        case .ginocchia: if let a = p[.leftKnee], let b = p[.rightKnee] { y = 1 - (a.y + b.y) / 2 } else { y = nil }
        case .ologramma: y = nil
        }
        guard let y else { return }
        altezza = altezza == 0 ? y : altezza * 0.6 + y * 0.4
        minimo = min(minimo * 0.998 + altezza * 0.002, altezza)      // i limiti si adattano piano piano
        massimo = max(massimo * 0.998 + altezza * 0.002, altezza)
        let corsa = massimo - minimo
        guard corsa > 0.08 else { return }                            // movimento troppo piccolo: niente da contare
        let pos = (altezza - minimo) / corsa                          // 0 = punto più alto, 1 = più basso
        if !giu && pos > 0.7 { giu = true }
        if giu && pos < 0.3 {
            giu = false
            unaRipetizione()
        }
    }

    private func unaRipetizione() {
        ripetizioni += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Suoni.tocco()
    }

    /// JARVIS parla ogni tanto: solo se c'è qualcosa da dire, mai sopra se stesso.
    private func commenta(_ adesso: Date) {
        guard !voceInCorso, adesso.timeIntervalSince(ultimoCommento) > 9 else { return }
        var frase = ""
        if inclinazioneSchiena > sogliaSchiena + 6 { frase = "Schiena fuori asse di \(Int(inclinazioneSchiena)) gradi: la raddrizzi." }
        else if inclinazioneSchiena > sogliaSchiena { frase = "Un filo di inclinazione nella schiena, \(Int(inclinazioneSchiena)) gradi." }
        else if simmetria < 80 { frase = "Un lato più basso dell'altro: cerchi la simmetria." }
        else if adesso.timeIntervalSince(ultimoCommento) > 25 { frase = ["Postura ottima, continui così.", "Schiena allineata, molto bene.", "Esecuzione pulita."].randomElement()! }
        guard !frase.isEmpty, frase != ultimoAvviso || adesso.timeIntervalSince(ultimoCommento) > 30 else { return }
        ultimoCommento = adesso
        ultimoAvviso = frase
        commento = frase
        Task { await parla(frase) }
    }

    private func parla(_ testo: String) async {
        voceInCorso = true
        defer { voceInCorso = false }
        let s = AVAudioSession.sharedInstance()
        if ascoltoComandi {
            // il microfono dei comandi è acceso: stessa impostazione sua, così parlando non lo spegne
            if s.category != .playAndRecord { try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers]) }
        } else {
            try? s.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        }
        try? s.setActive(true)
        if Impostazioni.voceCloud, let url = URL(string: Impostazioni.indirizzo) {
            let (dati, _) = await VoceCloud.scarica(testo, id: Impostazioni.idVoceCloud, url: url, token: Portachiavi.leggi())
            if let dati, let p = try? AVAudioPlayer(data: dati) {
                lettore = p
                p.play()
                while p.isPlaying { try? await Task.sleep(for: .milliseconds(100)) }
                lettore = nil
                return
            }
        }
        let u = AVSpeechUtterance(string: testo)
        u.voice = Jarvis.voceScelta()
        sintesi.speak(u)
        while sintesi.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
    }
}

/// La fotocamera dell'allenatore: lavora su una coda sua, riceve i fotogrammi e chiede a Vision lo scheletro (uno su tre basta).
/// Nell'Ologramma analizza ogni fotogramma che fa in tempo (quelli in ritardo si scartano) e, dietro, usa il LiDAR per la distanza.
nonisolated final class CameraPosa: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    let sessione = AVCaptureSession()
    let coda = DispatchQueue(label: "it.discosizer.jarvis.allenatore")
    var esito: (@Sendable ([VNHumanBodyPoseObservation.JointName: CGPoint]?) -> Void)?   // lo scheletro (Busto · Mani · Ginocchia)
    var esitoOlo: (@Sendable (ScenaOlo) -> Void)?                                         // l'Ologramma
    private let uscita = AVCaptureVideoDataOutput()
    private let profonda = AVCaptureDepthDataOutput()
    private var ingresso: AVCaptureDeviceInput?
    private var contatore = 0
    private let richiesta = VNDetectHumanBodyPoseRequest()
    // build 23: l'Ologramma
    private var olo = false
    private var frontale = false
    private var campo: Float = 70
    private let analisi = AnalisiOlogramma()
    private let mappa = MappaProfondita()
    private var conLidar = false

    func usaOlo(_ si: Bool) { coda.async { self.olo = si; self.analisi.azzera() } }

    func configura(frontale: Bool, olo: Bool, pronto: @escaping @Sendable (Bool) -> Void) {
        coda.async {
            let s = self.sessione
            s.beginConfiguration()
            if let vecchio = self.ingresso { s.removeInput(vecchio); self.ingresso = nil }
            // dietro, nell'Ologramma: la fotocamera con il LiDAR (iPhone Pro), per la distanza vera
            let lidar = !frontale && olo ? AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) : nil
            let formati = lidar.flatMap { Self.formatiLidar($0) }
            if formati == nil { s.sessionPreset = .high }
            let cam = (formati != nil ? lidar : nil) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: frontale ? .front : .back)
            if let cam, let i = try? AVCaptureDeviceInput(device: cam), s.canAddInput(i) {
                s.addInput(i); self.ingresso = i
            }
            if !s.outputs.contains(self.uscita) {
                self.uscita.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.uscita.alwaysDiscardsLateVideoFrames = true
                self.uscita.setSampleBufferDelegate(self, queue: self.coda)
                if s.canAddOutput(self.uscita) { s.addOutput(self.uscita) }
            }
            self.conLidar = false
            if let cam, let scelti = formati, self.ingresso?.device == cam {
                let (video, profondita) = scelti
                if !s.outputs.contains(self.profonda), s.canAddOutput(self.profonda) {
                    s.addOutput(self.profonda)
                    self.profonda.isFilteringEnabled = true                     // la mappa senza buchi
                    self.profonda.alwaysDiscardsLateDepthData = true
                    self.profonda.setDelegate(self, callbackQueue: self.coda)
                }
                if s.outputs.contains(self.profonda), (try? cam.lockForConfiguration()) != nil {
                    cam.activeFormat = video
                    cam.activeDepthDataFormat = profondita
                    cam.unlockForConfiguration()
                    self.conLidar = true
                }
            } else if s.outputs.contains(self.profonda) {
                s.removeOutput(self.profonda)
            }
            if let c = self.uscita.connection(with: .video) {
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }   // ripresa verticale
                if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = false }
            }
            if self.conLidar, let c = self.profonda.connection(with: .depthData) {
                // la mappa nel verso del fotogramma (se la connessione lo sa fare); se no la ruota MappaProfondita
                if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90; self.mappa.ruotata = true } else { self.mappa.ruotata = false }
            }
            if !self.conLidar { self.mappa.svuota() }
            s.commitConfiguration()
            self.frontale = frontale
            if let cam = self.ingresso?.device { self.campo = Ottica.campo(cam) }
            if !s.isRunning { s.startRunning() }
            pronto(self.ingresso != nil && s.isRunning)
        }
    }

    /// Il formato video più grande (fino a 1920) che dà anche la profondità in metri (DepthFloat32, se no DepthFloat16:
    /// MappaProfondita la converte), a 30 fotogrammi al secondo.
    private static func formatiLidar(_ d: AVCaptureDevice) -> (AVCaptureDevice.Format, AVCaptureDevice.Format)? {
        func punti(_ p: AVCaptureDevice.Format) -> Int32 {
            let tipo = CMFormatDescriptionGetMediaSubType(p.formatDescription)
            let largo = CMVideoFormatDescriptionGetDimensions(p.formatDescription).width
            return largo * 2 + (tipo == kCVPixelFormatType_DepthFloat32 ? 1 : 0)        // a parità di misura, meglio a 32 bit
        }
        var scelta: (AVCaptureDevice.Format, AVCaptureDevice.Format, Int32)?
        for f in d.formats {
            let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard dim.width <= 1920, f.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 }) else { continue }
            let metri = f.supportedDepthDataFormats.filter {
                let tipo = CMFormatDescriptionGetMediaSubType($0.formatDescription)
                return tipo == kCVPixelFormatType_DepthFloat32 || tipo == kCVPixelFormatType_DepthFloat16
            }
            guard let p = metri.max(by: { punti($0) < punti($1) }) else { continue }
            if scelta == nil || dim.width > (scelta?.2 ?? 0) { scelta = (f, p, dim.width) }
        }
        return scelta.map { ($0.0, $0.1) }
    }

    func ferma() {
        coda.async { if self.sessione.isRunning { self.sessione.stopRunning() } }
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        mappa.aggiorna(depthData)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output == uscita, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if olo {
            // l'Ologramma: ogni fotogramma che fa in tempo (gli altri li scarta la fotocamera)
            let lato = max(CVPixelBufferGetWidth(pixel), CVPixelBufferGetHeight(pixel))
            let scena = analisi.analizza(pixel, frontale: frontale, fuoco: Ottica.fuoco(campo: campo, latoLungo: lato), profondita: conLidar ? mappa : nil)
            esitoOlo?(scena)
            return
        }
        contatore += 1
        guard contatore % 3 == 0 else { return }
        let gestore = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up)
        try? gestore.perform([richiesta])
        guard let oss = richiesta.results?.first, let punti = try? oss.recognizedPoints(.all) else { esito?(nil); return }
        var out: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (nome, p) in punti where p.confidence > 0.3 { out[nome] = CGPoint(x: p.location.x, y: p.location.y) }
        esito?(out.count >= 5 ? out : nil)
    }
}
#endif
