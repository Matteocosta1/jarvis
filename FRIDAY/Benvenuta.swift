import SwiftUI
import UIKit

/// FRIDAY · il primo avvio: la parola d'ordine del cervello (la dà Alessandro) e il numero di Bea (l'iPhone non lo dà alle app).
/// La parola d'ordine si prova subito sul cervello e finisce nel Portachiavi; il numero resta sul telefono.
struct Benvenuta: View {
    let fatto: () -> Void

    private enum Passo { case parola, numero }
    @State private var passo: Passo = .parola
    @State private var parola = ""
    @State private var numero = UserDefaults.standard.string(forKey: Profilo.chiaveNumero) ?? ""
    @State private var provo = false
    @State private var errore: String?
    @FocusState private var campo: Bool

    var body: some View {
        ZStack {
            Color.fondo.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer(minLength: 40)
                Text("F.R.I.D.A.Y.")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(Color.ciano)
                    .shadow(color: Color.ciano.opacity(0.6), radius: 12)
                Text(passo == .parola ? "Ciao Bea. Per svegliarmi mi serve la parola d'ordine che ti ha dato Ale."
                                      : "Ultima cosa: il tuo numero. L'iPhone non lo dà alle app, quindi te lo chiedo una volta sola.")
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.testo)
                    .padding(.horizontal, 28)
                Group {
                    if passo == .parola {
                        SecureField("", text: $parola, prompt: Text("Parola d'ordine").foregroundStyle(Color.tenue))
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { Task { await prova() } }
                    } else {
                        TextField("", text: $numero, prompt: Text("+39 …").foregroundStyle(Color.tenue))
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }
                }
                .focused($campo)
                .font(.system(size: 17, design: .monospaced))
                .foregroundStyle(Color.testo)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.ciano.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ciano.opacity(0.35), lineWidth: 1))
                .padding(.horizontal, 28)
                if let errore {
                    Text(errore).font(.system(size: 13)).foregroundStyle(Color.rossoF).multilineTextAlignment(.center).padding(.horizontal, 28)
                }
                Button {
                    Suoni.tocco()
                    if passo == .parola { Task { await prova() } } else { salvaNumero() }
                } label: {
                    HStack(spacing: 8) {
                        if provo { ProgressView().tint(Color.fondo) }
                        Text(passo == .parola ? "Entra" : "Fatto").font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.ciano))
                    .foregroundStyle(Color.fondo)
                }
                .disabled(provo || (passo == .parola && parola.trimmingCharacters(in: .whitespaces).isEmpty))
                .padding(.horizontal, 28)
                if passo == .numero {
                    Button("Dopo") { Suoni.tocco(); fatto() }
                        .font(.system(size: 14)).foregroundStyle(Color.tenue)
                }
                Spacer()
                Text("Resta tutto su questo iPhone e nel tuo cervello di FRIDAY: Ale non vede quello che le dici.")
                    .font(.system(size: 12)).foregroundStyle(Color.tenue).multilineTextAlignment(.center).padding(.horizontal, 32).padding(.bottom, 18)
            }
        }
        .onAppear { campo = true }
        .animation(.easeOut(duration: 0.25), value: passo)
    }

    /// La parola d'ordine giusta il cervello la accetta (200); quella sbagliata la rifiuta (401). Chiede i consumi: niente costi.
    private func prova() async {
        let p = parola.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !provo, let url = URL(string: Impostazioni.indirizzo) else { return }
        provo = true; errore = nil
        defer { provo = false }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(p, forHTTPHeaderField: "x-friday-token")
        req.httpBody = Data(#"{"consumi":true}"#.utf8)
        do {
            let (_, risposta) = try await URLSession.shared.data(for: req)
            switch (risposta as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200:
                Portachiavi.salva(p)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                passo = .numero
                campo = true
            case 401: errore = "Non è quella giusta. Ricontrolla le maiuscole."; UINotificationFeedbackGenerator().notificationOccurred(.error)
            default: errore = "Il cervello non risponde adesso. Riprova tra poco."; UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        } catch {
            errore = "Niente connessione. Controlla Wi-Fi o dati e riprova."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func salvaNumero() {
        let n = numero.filter { $0.isNumber || $0 == "+" }
        if !n.isEmpty { UserDefaults.standard.set(n, forKey: Profilo.chiaveNumero) }
        fatto()
    }
}

/// Il profilo di Bea sul telefono: il suo numero (lo chiede Benvenuta, si cambia in Account).
enum Profilo {
    static let chiaveNumero = "mioNumeroFriday"
    static var numero: String { UserDefaults.standard.string(forKey: chiaveNumero) ?? "" }
}
