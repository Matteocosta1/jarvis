#if os(iOS)
import Foundation
import SwiftUI

// MARK: - «CANCELLARE TUTTO?» (8 nov mattina, controllo della build; scelta del signore 05:2x: «Shazam: ELIMINA › CONFERMA»)
// Come il mockup v277 dello Scanner (chiediSalvaMock con il cestino): la domanda prima di cancellare una cronologia intera sale dal
// basso nella sezione con la tacca, sulla stessa pelle di FoglioSalva; il cestino, «CANCELLARE TUTTO?» e quante cose; CANCELLA
// rosso a tutta larghezza; ANNULLA; la nota. Sotto non si tocca niente. Prima Scanner e Shazam usavano la domanda di iOS.

/// La domanda «CANCELLARE TUTTO?».
struct FoglioCancella: View {
    let sotto: String
    let nota: String
    let cancella: () -> Void
    let annulla: () -> Void

    private static var grigio: Color { Color(red: 159 / 255, green: 179 / 255, blue: 185 / 255) }   // #9fb3b9
    private static var testo: Color { Color(red: 230 / 255, green: 244 / 255, blue: 248 / 255) }    // #e6f4f8
    private static var rosso: Color { Color(red: 1, green: 69 / 255, blue: 58 / 255) }                // #ff453a

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 40, height: 5)
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.ciano)
                    .frame(width: 54, height: 54)
                    .background(RadialGradient(colors: [Color.ciano.opacity(0.18), Color(red: 2 / 255, green: 6 / 255, blue: 10 / 255).opacity(0.9)],
                                               center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 42))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CANCELLARE TUTTO?").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Color.ciano)
                    Text(sotto).font(.system(size: 12)).foregroundStyle(Self.grigio)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { Suoni.tocco(); cancella() } label: {
                Text("CANCELLA").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                    .foregroundStyle(Color(red: 0, green: 24 / 255, blue: 32 / 255))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Self.rosso))
            }
            .buttonStyle(StileStark())
            Button { Suoni.tocco(); annulla() } label: {
                Text("ANNULLA").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(Color.ciano)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ciano.opacity(0.3), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(StileStark())
            Text(nota).font(.system(size: 14)).foregroundStyle(Self.testo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
        }
        .padding(.top, 10).padding(.horizontal, 16).padding(.bottom, 28)
        .background(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
            .fill(Color(red: 8 / 255, green: 14 / 255, blue: 17 / 255).opacity(0.98))
            .shadow(color: .black.opacity(0.6), radius: 20, y: -10))
        .overlay(BordoAlto(raggio: 22).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    /// «CANCELLARE TUTTO?» sopra la sezione: sale dal basso (0,32 s, come «Salvare?»), sotto non si tocca niente. Si apre col suono
    /// della scheda, mettendo `mostra` a vero dentro `withAnimation(.salitaFoglio)`.
    func domandaCancella(_ mostra: Binding<Bool>, sotto: String, nota: String, cancella: @escaping () -> Void) -> some View {
        overlay {
            ZStack(alignment: .bottom) {
                if mostra.wrappedValue {
                    Color.black.opacity(0.001)                                   // sotto il foglio non si tocca niente
                        .ignoresSafeArea()
                        .onTapGesture {}
                        .accessibilityHidden(true)
                    FoglioCancella(sotto: sotto, nota: nota,
                                   cancella: { withAnimation(.salitaFoglio) { mostra.wrappedValue = false }; cancella() },
                                   annulla: { withAnimation(.salitaFoglio) { mostra.wrappedValue = false } })
                        .transition(.move(edge: .bottom))
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
#endif
