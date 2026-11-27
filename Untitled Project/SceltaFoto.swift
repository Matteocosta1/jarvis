#if os(iOS)
import SwiftUI
import PhotosUI
import UIKit

/// 27 nov · FOTO INSIEME (mockup approvato dal signore, JARVIS Mark XIII v111): «Scegli dalla libreria» apre il selettore di iOS
/// con la scelta multipla, fino a `limite` foto, nell'ordine in cui il signore le tocca. Le foto tornano già nell'ordine scelto.
/// «Scatta una foto» resta la fotocamera di sempre (`Fotocamera`, una foto).
struct SceltaFoto: UIViewControllerRepresentable {
    let limite: Int
    let suFoto: ([UIImage]) -> Void
    @Environment(\.chiudiOVia) var chiudi

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var c = PHPickerConfiguration()
        c.filter = .images
        c.selectionLimit = limite
        c.selection = .ordered
        let p = PHPickerViewController(configuration: c)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinatore { Coordinatore(self) }

    final class Coordinatore: NSObject, PHPickerViewControllerDelegate {
        let padre: SceltaFoto
        init(_ padre: SceltaFoto) { self.padre = padre }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let fornitori: [NSItemProvider] = results.map(\.itemProvider)
            let suFoto = padre.suFoto
            padre.chiudi()
            guard !fornitori.isEmpty else { return }          // «Annulla»: niente
            Task { @MainActor in
                var immagini: [UIImage] = []
                for f in fornitori {                          // una dopo l'altra: l'ordine resta quello scelto dal signore
                    if let i = await SceltaFoto.carica(f) { immagini.append(i) }
                }
                if !immagini.isEmpty { suFoto(immagini) }
            }
        }
    }

    /// L'immagine di una foto scelta (anche da iCloud: iOS la scarica). Nil se non si può leggere.
    static func carica(_ f: NSItemProvider) async -> UIImage? {
        guard f.canLoadObject(ofClass: UIImage.self) else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<UIImage?, Never>) in
            _ = f.loadObject(ofClass: UIImage.self) { oggetto, _ in
                c.resume(returning: oggetto as? UIImage)
            }
        }
    }
}
#endif
