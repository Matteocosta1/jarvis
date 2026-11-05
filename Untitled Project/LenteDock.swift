import Foundation
import SwiftUI
import Combine
import UIKit

/// MARK XI · il DOCK in alto (mockup approvato dal signore il 3 nov): il dito che scorre sulle icone piccole in alto (o il puntatore
/// sul Mac, senza premere) le ingrandisce come il Dock del Mac, verso il basso (sopra c'è lo schermo): cresce quella sotto il dito
/// (1,5), fra due icone il testimone passa continuo (1,25 tutte e due a metà strada), le altre restano dove sono. Scorrendo, un click
/// per icona («dock», mixkit 3124). Come la ruota: lo leggono solo le icone, non tutta la schermata.
/// 5 nov (il signore: «si aprono involontariamente e si cliccano male… dargli la possibilità di essere cliccate dopo
/// l'ingrandimento, proprio come il Dock di Apple»): sull'iPhone niente si apre più alzando il dito né al primo tocco. Il dito che
/// scorre (o il primo tocco su un'icona) ingrandisce come il puntatore sul Dock del Mac; alzato il dito, le icone restano grandi
/// per 2,5 s e il tocco sull'icona ingrandita la apre. Sul Mac il puntatore ingrandisce e il click apre, come prima.
final class LenteDock: ObservableObject {
    /// Dov'è il dito (o il puntatore), in coordinate globali; nil: nessuno.
    @Published private(set) var x: CGFloat?
    /// Le icone sono ingrandite e aspettano il tocco (dito alzato, o primo tocco su un'icona): il tocco apre.
    @Published private(set) var trattenuta = false
    /// Quanto restano grandi dopo il dito, se non si tocca niente.
    static let attesa: Double = 2.5
    private var giro = 0
    /// Il centro di ogni icona a riposo (coordinate globali), misurato quando la lente è spenta.
    private var centri: [Int: CGFloat] = [:]
    private var riquadri: [Int: CGRect] = [:]
    private var ultima: Int?
    private var ultimoClick: CFTimeInterval = 0
    private let tocco = UIImpactFeedbackGenerator(style: .light)

    func misura(_ indice: Int, riquadro: CGRect) {
        guard x == nil else { return }
        centri[indice] = riquadro.midX
        riquadri[indice] = riquadro
    }

    /// Il punto è sulle icone (il riquadro che le contiene tutte, con 8 punti di margine).
    func vicino(_ p: CGPoint) -> Bool {
        guard let primo = riquadri.values.first else { return false }
        let tutto = riquadri.values.reduce(primo) { $0.union($1) }.insetBy(dx: -8, dy: -8)
        return tutto.contains(p)
    }

    /// Il passo fra due icone vicine (per la larghezza della lente).
    private var passo: CGFloat {
        let c = centri.values.sorted()
        guard let a = c.first, let b = c.last, c.count > 1 else { return 26 }
        return (b - a) / CGFloat(c.count - 1)
    }

    /// L'icona sotto il dito (entro tre quarti di passo dal suo centro), o nessuna.
    var sopra: Int? {
        guard let x, let k = centri.min(by: { abs($0.value - x) < abs($1.value - x) }) else { return nil }
        return abs(k.value - x) < passo * 0.75 ? k.key : nil
    }

    func scala(_ indice: Int) -> CGFloat {
        guard let x, let c = centri[indice] else { return 1 }
        let d = Double((x - c) / (passo * 0.6))
        return CGFloat(1 + 0.5 * exp(-d * d))
    }

    /// Il dito (o il puntatore) è qui: un click per icona su cui passa (al massimo uno ogni 35 ms).
    func segui(_ nuovo: CGFloat, mac: Bool = false) {
        if trattenuta { trattenuta = false; giro += 1 }               // il dito di nuovo sulle icone: la lente torna sua
        x = nuovo
        let s = sopra
        guard s != ultima else { return }
        ultima = s
        guard s != nil else { return }
        let ora = CACurrentMediaTime()
        guard ora - ultimoClick > 0.035 else { return }
        ultimoClick = ora
        if mac { Suoni.clickDockSopra() } else { Suoni.clickDock(); tocco.impactOccurred(intensity: 0.5) }
    }

    /// Il dito si alza (o il puntatore esce): le icone tornano normali. Restituisce l'icona su cui era.
    @discardableResult func lascia() -> Int? {
        let s = sopra
        x = nil
        ultima = nil
        trattenuta = false
        giro += 1
        return s
    }

    /// iPhone, dito alzato dopo aver scorso: le icone restano grandi dove erano e aspettano il tocco (2,5 s).
    func trattieni() {
        guard x != nil else { return }
        trattenuta = true
        aspetta()
    }

    /// iPhone, primo tocco su un'icona con le icone piccole: si ingrandiscono attorno a lei (col suo click), senza aprirla.
    func mostra(_ indice: Int) {
        guard let c = centri[indice] else { return }
        x = c
        ultima = indice
        ultimoClick = CACurrentMediaTime()
        Suoni.clickDock()
        tocco.impactOccurred(intensity: 0.5)
        trattenuta = true
        aspetta()
    }

    /// Passati 2,5 s senza toccare niente, le icone tornano piccole.
    private func aspetta() {
        giro += 1
        let mio = giro
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(LenteDock.attesa))
            guard let self, self.giro == mio, self.trattenuta else { return }
            self.lascia()
        }
    }
}

/// Un'icona del Dock: misura il suo centro e cresce sotto il dito (verso il basso), seguendo il dito con una molla morbida.
struct PostoDock: ViewModifier {
    @ObservedObject var dock: LenteDock
    let indice: Int

    func body(content: Content) -> some View {
        let s = dock.scala(indice)
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { dock.misura(indice, riquadro: $0) }
            .scaleEffect(s, anchor: .top)
            .animation(.spring(response: dock.x == nil ? 0.22 : 0.1, dampingFraction: 0.9), value: s)
            .zIndex(s > 1.02 ? 1 : 0)
    }
}
