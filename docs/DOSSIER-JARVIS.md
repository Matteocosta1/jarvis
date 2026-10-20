# J.A.R.V.I.S. — Dossier di progetto

> Documento di passaggio per una nuova chat. Dal primo Mark a oggi (20 ott 2026, notte).
> Chi legge: sei l'assistente di **Alessandro** (socio di Matteo in Discosizer). Si parla **italiano**, tono **maggiordomo alla Tony Stark** ("Signore"), confronto maturo: dì apertamente quando non sei d'accordo.

---

## 1. Cos'è JARVIS

Assistente vocale personale di Alessandro, stile Iron Man. **App vera**, non una skill dentro Claude. Un **unico "cervello"** (Supabase Edge Function) servito a tre dispositivi:

- **iPhone** 15 Pro — app nativa Swift (installata da TestFlight)
- **Apple Watch** SE 2 — app watchOS
- **Mac** (di Matteo) — la stessa app iPhone, via "Designed for iPad" / TestFlight

Regola d'oro: ogni novità va **in parallelo su iPhone e Watch** (tranne ciò che l'orologio non può fare, es. fotocamera). Il Mac è una terza variante, da toccare **senza mai cambiare iPhone/Watch**.

## 2. Architettura

- **Cervello**: Edge Function `jarvis` su Supabase, progetto **"Discosizer Serate"** (Deno/TypeScript, file unico `supabase/functions/jarvis/index.ts`, ~235 KB). È il cervello condiviso delle app di Ale e Matteo; le app per clienti avranno progetti Supabase separati.
- **Modello**: Claude (Anthropic), chiave API dedicata "JARVIS" (account King Rusto). Ricarica **solo a mano**, mai automatica; JARVIS avvisa quando il credito cala.
- **Voce**: voce **ElevenLabs** creata da lui (via endpoint `voceTts` del cervello), spendendo il meno possibile. Trascrizione Mac via **ElevenLabs Scribe** (endpoint `trascrivi`, ~0,5 s); su iPhone c'è `SFSpeechRecognizer` on-device.
- **Audio app**: `AVAudioEngine` + `SFSpeechRecognizer` (iPhone), trascrizione cloud (Mac). Un solo motore audio condiviso.
- **Database serate**: Supabase "Discosizer Serate" (lettura). Org Supabase passata a **Pro** il 15 ott.
- **Notifiche push**: APNs (briefing, SOS Bea).

## 3. Flusso di deploy (IMPORTANTE)

Alessandro **non incolla più file**. Flusso fisso su tutte le sue app:

1. Codice del cervello → repository GitHub **Matteocosta1/jarvis** (account di Matteo).
2. Deploy del cervello tramite la Edge Function `jarvis-deploy`: si inserisce un codice usa-e-getta in tabella `jarvis_deploy_codici`, poi `net.http_get` sull'URL di deploy con **sha256 del commit + codice**.
3. Il deploy fa una **"prova generale"** (dress-rehearsal): se il codice non compila, **blocca** e non va in produzione. Va superata prima del "vai".
4. App Swift: lui fa **Pull in Xcode** dal repo, poi build e upload su TestFlight.

Versione corrente cervello: **v102** attiva. Etichetta app: **MARK VII — 5.0**.

## 4. Cronologia (Mark I → VII)

- **Mark I** — JARVIS sul Mac in Chrome, voce del Mac, note/progetti, Spotify, DB serate (sola lettura).
- **Mark II/III** — cervello spostato su Supabase; app nativa Swift iPhone + Mac sullo stesso cervello. (Spotify non Premium → niente ricerca brani via API.)
- **Mark IV (build 9)** — HUD, interruzione a voce, suoni, briefing push. Su TestFlight.
- **"Occhi" (build 10)** — fotocamera iPhone che descrive ciò che inquadra (dischi → prezzo Discogs). Regola: **mai perdere una foto vista** se lui interrompe la descrizione.
- **Vitals / Diario** — diario serale (notifica 23:30, una domanda diversa a sera), sezione "Vitals" (umore incrociato con sonno/battito del Watch), "confidente" su richiesta (legge una conversazione che incolla; dice ciò che pensa in entrambe le direzioni).
- **Seconda memoria** — oggetti/posti (dov'è la Q3), persone, promesse, cose viste, idee al volo, filo della giornata. + traduttore/interprete a voce.
- **SENSI** — Cucina (frigo → cosa cucinare + lista spesa), scanner alimentare stile Yuka (Open Food Facts), Allenatore (posa/Pilates con Vision in locale).
- **build 16** — comandi telefono via Comandi Rapidi, rete a 4 tentativi con frasi d'attesa, interruzione a voce; JARVIS meno logorroico.
- **Mark V (3.0, build 9)** → salvata nel branch `claude/mark-v` per eventuale downgrade.
- **Reparto Bea** (gruppo STRUMENTI, icona due anelli) — scheda di Bea, "Ti penso", sicurezza **col suo consenso**; **Tocco d'aiuto** (Comando rapido "Aiuto Ale" sul tasto Azione dell'iPhone di Bea, segreto `BEA_SOS_CHIAVE`): creato e provato sul suo iPhone, link iCloud mandato a Bea; a lei resta da collegarlo al tasto Azione. Niente Twilio per ora (a pagamento; c'è già il 112).
- **Mark VI → VII (5.0)** — vedi sotto (Mac, SISTEMI, EDITH, sottovoce).

## 5. Interfaccia

- Corona di icone principale: **definitiva**, "la più bella mai fatta". **Niente nuove sezioni lì.**
- Le novità vanno nel menu **SISTEMI** in alto: GitHub, Supabase, Archivio, **Costi**, **EDITH**.
- Header: icone (SISTEMI/cestino/rotella) allineate e più piccole sulla riga "MARK VII-5.0"; il punto finale attaccato alla **S** di J.A.R.V.I.S.
- Titoli di sezione/scheda: **una sola parola** che faccia capire subito (odia i titoli lunghi).
- Mockup/app: ottimizzati per **tutti i dispositivi** (regola fissa).

## 6. Novità recenti (Mark VII)

- **Costi** (SISTEMI, logo Langfuse): mostra la spesa; anche a voce ("quanto ho speso"). Prezzi 5.5, token di cache, mezzanotte Roma (DST).
- **Systems Check** (ex "Ronda", che odiava): controllo orario dei sistemi, nome "alla Tony Stark". Edge functions vecchie/scartate ripulite.
- **Mac**:
  - Attivazione "alla Tony Stark": **due battiti di mani** o frase **"Wake up, daddy's home"** → parte qualche secondo di *Should I Stay or Should I Go* dei Clash, poi saluto.
  - Dialogo **identico all'iPhone**: gli parli sopra e si ferma; in attesa **qualsiasi parola** lo risblocca; microfono sempre aperto; veloce.
  - Reattore **enorme** al centro, scalato per 15", chat sotto proporzionata (non due colonne).
  - **Comandi vocali Mac** via un unico Comando Rapido "JARVIS Mac" (volume, musica, aprire app, ordinare desktop/cartelle, screenshot, dark mode, blocco).
- **Sottovoce**: parola chiave **"piano"** (prima "sbatti") → risponde **molto piano** (volume 0,05) o per iscritto; esce con "voce normale"/"parla normale"/"alza la voce". (Bug risolto: entrando in sottovoce partiva la canzone dei Clash.)
- Priorità vocale: **lui interrompe sempre** JARVIS, JARVIS non interrompe mai lui; se una spiegazione è interrotta, la **riprende** da dove si era fermata.

## 7. EDITH — "hacking positivo" (solo difesa)

Voce in SISTEMI, icona **occhiali** (come EDITH di Tony Stark). Solo **difensivo**, solo asset propri, **niente contro il consenso**. Servizi **gratuiti e senza chiave** (o chiavi già presenti).

**Strumenti base (5):**
- **Porte** — porte/servizi esposti di un IP (Shodan InternetDB)
- **Fughe** — email in data breach (XposedOrNot)
- **Link** — link sospetti in un testo
- **Domini** — info dominio (RDAP, Google DNS, crt.sh)
- **Password** — se una password è trapelata (HaveIBeenPwned, k-anonymity, SHA-1 on-device)

**Strumenti difensivi (4) — codati stanotte, DA DEPLOYARE:**
- **Azienda** (`edith_azienda`) — verifica una partita IVA europea nel registro **VIES** (valida/attiva, nome, indirizzo). Prima di fidarsi di un fornitore/cliente.
- **Pagamenti/IBAN** (`edith_iban`) — forma + cifra di controllo MOD-97 (offline) + banca italiana da ABI. Prima di pagare una fattura.
- **Numero** (`edith_numero`) — che numero è (Paese, fisso/mobile) e forma giusta. Offline, solo prefissi.
- **Reputazione** (`edith_reputazione`) — risultati pubblici del web (Google via SERPER). Per farsi un'idea su azienda/persona pubblica/dominio.

> **Stato preciso stanotte**: i 4 strumenti sono **scritti nel cervello** (`index.ts`: funzioni `edithAzienda/edithIban/edithNumero/edithReputazione`, definizioni tool, `esegui()`, `paginaEdith()`, `NON_FIDATI`). **Mancano**: le schede Swift in `Untitled Project/Edith.swift`, il commit su GitHub e il deploy del cervello (con prova generale). Vanno anche richiamabili a voce → funzionano anche su Watch "nel possibile".

## 8. Lavori in sospeso

1. **Finire EDITH difesa**: schede Swift dei 4 strumenti + commit + deploy cervello.
2. **Idea dialogo** (non ancora fatta): mentre JARVIS è in ascolto e Ale parla con un'altra persona, dire **"Jarvis aspetta / zitto / fermati"** per fermarlo e mandarlo in attesa.
3. Tocco d'aiuto di Bea: completare con lei quando avrà il suo telefono (mappa posizione nella schermata allarme + riquadro in sicurezza; mockup in `docs/bea`).

## 9. Note operative

- **Modello**: su piano Max 20x può capitare l'auto-switch 5.5 → 4.8 vicino ai limiti; non è un bug del progetto.
- **Diagnostica**: falsi allarmi sistemati (endpoint log Supabase migrato a `logs`; ElevenLabs "chiave rifiutata"; ClickSend che insisteva — serve solo per l'SMS se Ale si sentisse male, ~1,68 €).
- **File chiave**:
  - `supabase/functions/jarvis/index.ts` — cervello
  - `supabase/functions/jarvis-systems/index.ts` — Systems Check
  - `Untitled Project/Jarvis 2.swift`, `AscoltoCloud.swift`, `Strumenti 2.swift`, `ContentView 2.swift`, `Edith.swift`
  - `JarvisOrologio Watch App/JarvisOrologio 2.swift`
  - `docs/edith/mock.html`, `docs/costi/mock.html`, `docs/mac/JARVIS-Mac.sh`

---

*Per ripartire in una nuova chat: allega questo file e di' "continuiamo JARVIS". Il resto (gusti, persone, decisioni) è già nella memoria dell'account.*
