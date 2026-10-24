#if os(iOS)
import SwiftUI

/// I pezzi dei pannelli della build 22 (Telefono, Ricordi, Meteo, Email), con le misure e i colori del mockup.
enum ColoriHUD {
    static let testo = Color(red: 0.812, green: 0.886, blue: 0.910)     // #cfe2e8: righe e frasi
    static let chiaro = Color(red: 0.902, green: 0.957, blue: 0.973)    // #e6f4f8: passi spuntati, avvisi
    static let spento = Color(red: 0.624, green: 0.718, blue: 0.745)    // #9fb7be: passi da fare
    static let verde = Color(red: 0.373, green: 0.890, blue: 0.631)     // #5fe3a1: spunta
    static let filo = Color(red: 0.114, green: 0.165, blue: 0.180)      // #1d2a2e: linea tra le mail
}

/// Una riga del pannello: il nome a sinistra, il valore a destra in carattere da terminale.
struct RigaHUD: View {
    let etichetta: String
    let valore: String
    /// Decisione 45 (Ricordi › ULTIMI): il valore a destra (la data o il posto) resta su UNA riga, rimpicciolito se serve;
    /// il testo a sinistra si tronca al suo posto. Spento (tutte le altre righe): come sempre.
    var valoreSuUnaRiga = false
    init(_ etichetta: String, _ valore: String, valoreSuUnaRiga: Bool = false) {
        self.etichetta = etichetta; self.valore = valore; self.valoreSuUnaRiga = valoreSuUnaRiga
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if valoreSuUnaRiga {
                // a sinistra almeno 100 punti: un posto lunghissimo non si mangia tutto il testo del ricordo
                Text(etichetta).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
                    .lineLimit(1)
                    .frame(minWidth: 100, alignment: .leading)
            } else {
                Text(etichetta).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo)
            }
            Spacer(minLength: 8)
            Text(valore)
                .font(.system(size: 12, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(Color.tenue)
                .multilineTextAlignment(.trailing)
                .lineLimit(valoreSuUnaRiga ? 1 : nil)
                .minimumScaleFactor(valoreSuUnaRiga ? 0.75 : 1)
                .layoutPriority(valoreSuUnaRiga ? 1 : 0)        // il valore prende il suo posto per primo
        }
    }
}

/// Il pannello A VOCE: le frasi da dire a JARVIS per questa sezione.
struct PannelloAVoce: View {
    let frasi: [String]
    var nota: String? = nil

    var body: some View {
        Pannello(titolo: "A VOCE", tinta: .ciano) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(frasi, id: \.self) { Text($0).font(.system(size: 14)).foregroundStyle(ColoriHUD.testo) }
            }
            if let nota { Text(nota).font(.system(size: 11)).foregroundStyle(Color.tenue) }
        }
    }
}

/// Il tasto da HUD del mockup: contorno ciano, scritta in maiuscolo da terminale. `corto`: largo quanto la scritta.
struct TastoComando: View {
    let testo: String
    var corto = false
    var attivo = true
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            Text(testo)
                .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(1.5)
                .textCase(.uppercase)
                .lineLimit(1)
                .foregroundStyle(Color.ciano)
                .padding(.vertical, corto ? 7 : 8)
                .padding(.horizontal, corto ? 14 : 8)
                .frame(maxWidth: corto ? nil : .infinity)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(StileStark())
        .disabled(!attivo)
        .opacity(attivo ? 1 : 0.5)
    }
}

/// L'avviso di JARVIS in testa a un pannello («JARVIS · AVVISO»).
struct AvvisoJarvis: View {
    var etichetta = "JARVIS · AVVISO"
    let testo: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(etichetta).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
            Text(testo).font(.system(size: 14)).foregroundStyle(ColoriHUD.chiaro).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ciano.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.45), lineWidth: 1)
                .shadow(color: Color.ciano.opacity(0.2), radius: 8)                     // il bagliore solo sul bordo
        )
    }
}
#endif
