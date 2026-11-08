#!/usr/bin/env python3
"""Banco di prova: mette la radice di prova nell'app e i ganci del copione (solo nel simulatore di GitHub, ramo claude/banco-prova)."""
import pathlib, re, shutil, sys

R = pathlib.Path(__file__).resolve().parent.parent
A = R / "Untitled Project"
shutil.copy(R / "banco" / "BancoProva.swift", A / "BancoProva.swift")


def cambia(nome, vecchio, nuovo, conta=1, facoltativa=False):
    p = A / nome
    s = p.read_text(encoding="utf-8")
    n = s.count(vecchio)
    if n != conta:
        if facoltativa:
            print("salto (sonda non più al suo posto)", nome, vecchio[:50].replace("\n", " ")); return
        sys.exit(f"ERRORE banco: in {nome} '{vecchio[:60]}' compare {n} volte (attese {conta})")
    p.write_text(s.replace(vecchio, nuovo), encoding="utf-8")
    print("ok", nome)


# 1. la radice: col parametro -banco, il banco al posto di ContentView
cambia("JarvisApp.swift",
       "            ContentView()\n                .environmentObject(jarvis)\n                .preferredColorScheme(.dark)",
       "            if BancoProva.attivo { RadiceBanco() } else {\n            ContentView()\n                .environmentObject(jarvis)\n                .preferredColorScheme(.dark)\n            }")
# 2. niente domande di iOS (notifiche, posizione) sopra il video
cambia("Notifiche.swift", "        UNUserNotificationCenter.current().delegate = self\n",
       "        if BancoProva.attivo { return true }\n        UNUserNotificationCenter.current().delegate = self\n")
# 3. il cervello finto
cambia("Vitals.swift", "    static func chiama(_ corpo: [String: Any], attesa: TimeInterval = 20) async -> [String: Any]? {\n",
       "    static func chiama(_ corpo: [String: Any], attesa: TimeInterval = 20) async -> [String: Any]? {\n        if let finto = await BancoProva.risposta(corpo) { return finto }\n")
# 4. Posta: il copione apre la mail numero N (come un tocco sulla riga)
cambia("SchedeDaily.swift", "        .chiudiFoglioDietro { aperta = nil }",
       "        .onReceive(NotificationCenter.default.publisher(for: .bancoApriMail)) { n in\n"
       "            if let i = n.object as? Int, let p = posta, i < p.count { Suoni.tocco(); aperta = p[i] }\n"
       "        }\n"
       "        .chiudiFoglioDietro { aperta = nil }")
# 5. la PROIEZIONE: il copione la chiude (come «Chiudi»)
p = A / "ProiezioneMail.swift"
s = p.read_text(encoding="utf-8")
m = re.search(r"\n(\s*)\.onAppear\(perform: apri\)", s)
if not m:
    sys.exit("ERRORE banco: in ProiezioneMail.swift manca .onAppear(perform: apri)")
gancio = f"\n{m.group(1)}.onReceive(NotificationCenter.default.publisher(for: .bancoChiudiMail)) {{ _ in chiudi() }}"
s = s[:m.start()] + gancio + s[m.start():]
p.write_text(s, encoding="utf-8")
print("ok ProiezioneMail.swift")

# 6. le sonde dei margini (si vedono solo nelle scene «…sonde»)
cambia("StudioWeb.swift", "            .statusBarHidden(false)\n            .interactiveDismissDisabled(presa)",
       "            .overlay { SondaSA(nome: \"VS\", riga: 0) }\n            .statusBarHidden(false)\n            .interactiveDismissDisabled(presa)", facoltativa=True)
cambia("StudioWeb.swift", "            .background(Color.fondo)\n            .ignoresSafeArea()\n            .overlay {\n                if coperto {",
       "            .background(Color.fondo)\n            .ignoresSafeArea()\n            .overlay { SondaSA(nome: \"WEB\", riga: 1) }\n            .overlay {\n                if coperto {", facoltativa=True)
cambia("SchedeSignore.swift", "            CaricamentoHUD(titolo: titolo, tinta: tinta)\n                .padding(.top, 120)\n        }\n        .allowsHitTesting(false)",
       "            CaricamentoHUD(titolo: titolo, tinta: tinta)\n                .padding(.top, 120)\n        }\n        .overlay { SondaSA(nome: \"LOAD\", riga: 2) }\n        .allowsHitTesting(false)")
cambia("SchedeSignore.swift", "            .toolbar(.hidden, for: .navigationBar)\n        }\n        .preferredColorScheme(.dark)",
       "            .overlay { SondaSA(nome: \"CORN\", riga: 0) }\n            .toolbar(.hidden, for: .navigationBar)\n        }\n        .preferredColorScheme(.dark)")
cambia("ProiezioneMail.swift", "                .frame(width: larga, height: alta)\n",
       "                .frame(width: larga, height: alta)\n                .overlay { SondaSA(nome: \"CARD\", riga: 3) }\n")
cambia("SchedeDaily.swift", "        .background(SfondoSezione(tinta: tinta))\n        .task { await carica() }",
       "        .background(SfondoSezione(tinta: tinta))\n        .overlay { SondaSA(nome: \"LET\", riga: 4) }\n        .task { await carica() }")
# 7. la PROIEZIONE senza luce e colore (scene «…B»)
cambia("ProiezioneMail.swift", "                if luce > 1.001 {", "                if luce > 1.001 && !BancoProva.senzaColori {")
cambia("ProiezioneMail.swift", "                if colore < 0.999 {", "                if colore < 0.999 && !BancoProva.senzaColori {")
