# J.A.R.V.I.S. — Dossier di progetto

> Documento di passaggio per una nuova chat. Aggiornato al **20 ott 2026, ore 9:10**.
> Chi legge: sei l'assistente di **Alessandro** (socio di Matteo in Discosizer). Si parla **italiano**, tono **maggiordomo alla Tony Stark** («Signore»), confronto maturo: dì apertamente quando non sei d'accordo.
> **Regola ferrea**: nelle sue app **non prendere iniziative** che non ha chiesto, soprattutto su **suoni e grafica**. Le proposte si fanno; si applicano solo al suo sì. Ogni novità va **anche sul Watch**, nel possibile.

---

## 1. Cos'è JARVIS

Assistente vocale personale di Alessandro, stile Iron Man. **App vera**, non una skill. Un **unico cervello** (Supabase Edge Function) servito a tre dispositivi:

- **iPhone** 15 Pro — app nativa Swift (TestFlight)
- **Apple Watch** SE 2 — app watchOS
- **Mac** (di Matteo) — la stessa app iPhone, «Designed for iPad»

## 2. Architettura

- **Cervello**: Edge Function `jarvis` su Supabase, progetto **«Discosizer Serate»** (`axalouhijcsizqgnneco`). File unico `supabase/functions/jarvis/index.ts` (~240 KB).
- **Modello**: Claude (Anthropic), chiave API «JARVIS» (account King Rusto). Ricarica solo a mano. Tre modelli a seconda della domanda: **Haiku** per comandi secchi, **Sonnet** per le domande normali e per tutto il Watch, **Opus** per foto, richieste lunghe e ragionamenti. Non si tocca: vuole che resti intelligente com'è.
- **Cache** delle istruzioni: **1 ora** (`ttl: "1h"`, dal 20 ott, cervello v104). Prima era 5 minuti e le ricariche costavano il grosso della spesa (~4,5 $/giorno di test). Controllare i costi dopo un giorno d'uso.
- **Voce**: ElevenLabs (endpoint `voceTts`), trascrizione Mac via Scribe (`trascrivi`); su iPhone `SFSpeechRecognizer`.
- **Database serate**: Supabase «Discosizer Serate» (lettura). Org su piano Pro dal 15 ott.
- **Push**: APNs (briefing, SOS Bea).

## 3. Flusso di deploy (IMPORTANTE)

Alessandro **non incolla file**. Flusso fisso:

1. Codice → GitHub **Matteocosta1/jarvis**, ramo `main`.
2. Cervello: Edge Function `jarvis-deploy`: si inserisce un codice usa-e-getta in `jarvis_deploy_codici` (sha256 hex, scadenza), poi `net.http_get` su `…/functions/v1/jarvis-deploy?funzione=jarvis&da=github&ref=<commit>&sha=<sha256 di index.ts>&codice=<codice>`; l'esito si legge in `net._http_response`. Fa una **prova generale** (copia `jarvis-prova`, 3 domande vere): se non passa, non va in produzione.
3. App: lui fa **Pull in Xcode**, alza il numero di **Build** (uguale su tutti e tre i target: app, Watch, Complicazione), Archive, TestFlight.

Versione cervello: **v104**. Etichetta app: **MARK VII — 5.0**. Ultima build in lavorazione: **16** (20 ott, mattina).

**Punto di ritorno**: ramo `claude/mark-vii-suoni-ok` = versione approvata del 20 ott prima dell'aptica (suoni, avvio nuovo, chat animata, EDITH). Ramo `claude/mark-v` = Mark V 3.0.

## 4. Cronologia breve

Mark I (Mac/Chrome) → II/III (cervello su Supabase, app Swift) → IV (HUD, interruzione a voce, briefing push) → Occhi → Vitals/Diario → Seconda memoria → SENSI → Reparto Bea + Tocco d'aiuto → Mark VI/VII (Mac, SISTEMI, Costi, EDITH, sottovoce, Systems Check) → **20 ott: EDITH difesa, chat animata, suoni nuovi, avvio con pulsazioni, aptica, cache 1h**.

## 5. Interfaccia

- Corona di icone principale: 22 icone in 4 gruppi (SIGNORE, DAILY, SENSI, STRUMENTI) + **INTELLIGENCE** sotto. **Dal 20 ott sera**: in STRUMENTI **LiDAR** al posto di Bea; INTELLIGENCE = Sentinella, Profiler, Wiretap, **Bea** (26 icone, traccia d'avvio con 26 pulsazioni; «SISTEMI IN LINEA» sulla chiusura della musica, 4,35 s base). Watch: Bea in INTELLIGENCE dopo Sentinella. **Niente nuove sezioni lì**: le novità vanno nel menu **SISTEMI** (GitHub, Supabase, Archivio, Costi, EDITH).
- Header: le tre icone (SISTEMI, cestino, rotella) ravvicinate (padding orizzontale 5), sulla riga «MARK VII-5.0».
- Titoli di una sola parola. Mock sempre ottimizzati per tutti i dispositivi.
- Il Watch ha 19 icone in 6 gruppi (GIORNATA, SIGNORE, SENSI, STRUMENTI, INTELLIGENCE, SISTEMI).

## 6. Avvio (20 ott)

- Musica d'avvio `avvio.m4a`: la musica di sempre **con una pulsazione mixata per ogni icona** (dal file «sci-fi device pulsations» di Mixkit: 4 colpi puliti, passa-alto 350 Hz, picco al 70% della musica, prima icona di ogni gruppo +1,5 dB, nessun accento finale). Volume app 80%.
- Passo base: 150 ms per icona, 110 ms tra i gruppi, **INTELLIGENCE 120 ms**; dopo l'ultima icona **370 ms** (coda della musica) → «SISTEMI IN LINEA» → se la chat ha messaggi, **900 ms** di respiro → caricamento chat.
- **Dal 20 ott sera: iPhone/Mac +60%, Watch velocità normale** (`Avvio.velocita = 1.6`, `AvvioOrologio.velocita = 1.0` in `ChatAnimata.swift`, `AvvioOrologio` sul Watch): ogni tempo ÷1,6, caricamento chat compreso. `avvio.m4a`/`avvioorologio.m4a` **rimissati**: musica accelerata intera (rubberband, tono invariato) + le pulsazioni originali posate su ogni icona (scarto ≤2 ms). Icone, musica e aptica su **un solo orologio** (`CACurrentMediaTime` + latenza audio), niente pause in fila.
- **SINCRO**: da **Interprete** in poi (Watch: dalla 2ª icona di STRUMENTI) l'icona parte **110 ms prima** del colpo con la stessa molla più svelta (0,12 s), così arriva sul beep. Valore scelto da Alessandro sul mock.
- Watch: traccia propria `avvioorologio.m4a` con 19 pulsazioni. **Dal 20 ott sera le icone si accendono al contrario** (da Archivio a Briefing) e la barra scorre all'indietro con loro (la prossima icona sul bordo sinistro), finendo sulle prime, dove resta a riposo; raffica finale = GIORNATA a 120 ms. Parte dopo l'animazione d'apertura del Watch (0,6 s). Sfondo con la griglia dell'iPhone (passo 14). Aptica a fine gruppo, molla 0,32 grande→piccola, coda (ultime 8) 0,12 con 110 ms d'anticipo.
- I «plim» sintetici e il suono «inlinea» restano **spenti** di default (`suonoAvvio` = off).
- **Aptica** all'avvio (Core Haptics, `Aptica.swift`): **5 tocchi**, uno sull'ultima icona di ogni gruppo, in crescendo, l'ultimo (Wiretap) più pieno. Idea di Alessandro. Niente tocco per icona (sarebbe ronzio).

## 7. Chat animata (`ChatAnimata.swift`, 20 ott)

- All'avvio, se la chat ha messaggi: resta nascosta, poi **caricamento HUD con barra a linea unica** (voci: collegamento al cervello, recupero conversazione, decodifica), poi si **stampa dall'alto** con la riga ciano e i caratteri che si decodificano da simboli. Suono `chatcarica` (caratteri digitali) parte con la stampa. Chat vuota: niente.
- **Cestino › Pulisci** e **Impostazioni › Nuova conversazione**: i messaggi si ritirano **verso sinistra uno alla volta dal basso**, barra in fondo da 100% a 0% (archivio conversazione, pulizia schermo, memoria libera). Suono `chatsvuota` = carta appallottolata (Mixkit «pile of paper trash»). Aptica: tocco morbido che cala.
- Il caricamento **a tacche col mirino** resta per tutte le sezioni; la **barra a linea unica è solo della chat**.
- Watch: domanda e risposta si decodificano all'avvio e si ritirano verso sinistra al Pulisci (`TestoChatOrologio`).

## 8. Suoni (stato definitivo 20 ott)

Volumi (dal 20 ott sera, «Pieno+»): **tutto 100%** con file alzati di +4 dB col limitatore, tranne **chatcarica 70%** (invariato). File in `Untitled Project/` (il Watch li prende via membership exceptions nel pbxproj).

| Momento | File | Note |
|---|---|---|
| Click icone/reattore | `tick` | 50% |
| Click SISTEMI, cestino, rotella (Watch: Ricordi, Cronologia) | `clicktesta` | 50%, Mixkit «click menu select small» |
| Apertura di **tutte le schede** (Bea e Spesa comprese) | `scheda` | 70%; sfuma quando pronta |
| Scheda stampata | `schedapronta` | 70% |
| **Fotocamera pronta** (Occhi, Cucina, Allenatore, Profiler, **Scanner**) | `aperturacamera` | 70%, Mixkit «sci-fi interface robot click». Lo Scanner prima fa anche il caricamento da scheda |
| **Conferme** (Fatto, spunte, foto scattata, Shazam, ricordi, SOS, messaggi, prodotto trovato, applauso) | `pronto` solo su spunte verdi «Fatto» (promesse, spesa, ricordi) e **SOS** (`Suoni.fatto()`, 100%) | Tolto il 20 ott da applauso, Shazam, foto, messaggi, chiamate, dettature, prodotto trovato, fine risposta: lì solo vibrazione |
| Caricamento chat | `chatcarica` | 70% |
| Svuotamento chat | `chatsvuota` | 70% |
| `apertura` (Mixkit «interface hint») | nel progetto, **non usato** | |

Bip generati (`ascolto`) restano solo per «parli adesso»: reattore, Interprete, dettature.
Tentativi **scartati** da Alessandro: normalizzazione loudness a -18 LUFS (sentita peggio), pausa 300 ms nello Scanner, aptica UIKit per famiglia (sostituita da Core Haptics).

## 9. Aptica (`Aptica.swift`, iPhone)

Click → selezione fine · Fotocamera pronta → clack medio secco · Pronto → notifica successo · Svuotamento → continuo morbido in calo + punto fermo · Avvio → i 5 tocchi **forti** (0,9; l'ultimo 1,0 + coda di 120 ms). Vibrazioni permesse anche col microfono aperto (`setAllowHapticsAndSystemSoundsDuringRecording`). Watch: click per icona, `.directionUp` a fine gruppo, `.success` finale. Un transitorio ogni 100 ms al massimo; motore scaldato all'`onAppear`; sul Mac tace; Watch con i suoi `WKHaptic` di sempre.

## 10. Voce: silenzio

«**muto**, **stop**, **basta**, **zitto**, **Jarvis basta**» (+ taci, silenzio, fermati, stai zitto, basta così): JARVIS tace e torna in attesa **senza rispondere**, anche se lei sta parlando con un'altra persona. `Jarvis.eSoloSilenzio` (iPhone/Mac, in `interrottoAVoce`, `instrada`, `fraseSentitaMac`) e `JarvisOrologio.eSoloSilenzio` (Watch). Frasi brevi (≤6 parole) fatte solo di quelle parole; «basta con la musica» resta un comando.

## 11. EDITH — solo difesa

Voce in SISTEMI, icona occhiali. Servizi gratuiti/senza chiave. **9 strumenti**, tutti nel cervello e con scheda in `Edith.swift`:
Porte · Fughe · Link · Domini · Password (SHA-1 on-device) · **Azienda** (VIES) · **IBAN** (MOD-97 + ABI) · **Numero** (prefissi) · **Reputazione** (Serper). A voce funzionano anche sul Watch.

**Instant Kill** (idea di Alessandro, in standby): modalità difensiva «si tolgono le chiavi, non si attacca». Proposta a 3 livelli: Allerta (controllo completo), Blindatura (cervello risponde solo al suo iPhone, rotazione chiavi, avviso a Matteo), Protocollo (link diretti a Trova iPhone, ID Apple, Google, GitHub, Instagram, banca; salvataggio log). Attivazione voce + Face ID. Niente contrattacco (615-ter c.p.).

## 11b. LiDAR (`Lidar.swift`, 20 ott)

RoomPlan (Apple) per la cattura, con numeri dal vivo (pareti, m², altezza); poi RoomBuilder e risultato di JARVIS: **Pianta** (Canvas ciano, misure per parete, porte arancio, finestre), **3D** (USDZ parametrico in SceneKit a fil di ferro che ruota), **Archivio** (Documenti › LiDAR, `archivio.json`). Misure, capienza indicativa 1,2 persone/m² (DM 19/08/1996, sale da ballo), Salva/Condividi (PNG + USDZ)/Chiedi. Voce: «scansiona la stanza», «LiDAR», «planimetria». Solo iPhone Pro; sul Mac mostra l'archivio.

## 12. Lavori in sospeso

1. **Build 16**: in upload il 20 ott mattina. Avviso Xcode «CFBundleVersion 15 vs 16»: i tre target risultano a 16, probabilmente avviso vecchio; se l'upload fallisce, Clean Build Folder e ricontrollare Build Settings › Current Project Version.
2. **Test della build**: «Jarvis, muto» mentre parla con qualcuno; avvio con pulsazioni e i 5 tocchi; chat che si carica/svuota; Scanner; Watch.
3. **Costi**: verificare dopo un giorno quanto ha risparmiato la cache da 1 ora. Idee non applicate: strumenti a gruppi (rischio piccolo), meno Opus (**no**, vuole l'intelligenza intatta).
4. **Instant Kill**: quando lo chiede lui.
5. **Tocco d'aiuto di Bea**: completare con lei (tasto Azione, mappa nella schermata allarme; mockup in `docs/bea`).
6. Mock completo pubblicato (artifact «JARVIS Mark VII») con avvio, chat, sezioni e tutti i suoni: ricostruirlo solo se serve, è fedele all'app.

## 13. Note operative

- Siti suoni: **Pixabay** (gratis), **Mixkit** (gratis), Zapsplat (registrazione), Freesound (licenze varie), ElevenLabs Sound Effects (crediti). Tutti i suoni scelti sono di Mixkit/Pixabay.
- Suoni: li manda lui; io taglio silenzi, pareggio e converto in m4a. Non cambiare file o volumi senza che lo chieda.
- Modello: su Max 20x può capitare l'auto-switch; non è un bug del progetto.
- Chat lunghe rallentano: una chat per sessione/argomento, dossier aggiornato a fine sessione.
- **File chiave**: `supabase/functions/jarvis/index.ts` (cervello) · `supabase/functions/jarvis-systems/index.ts` · `Untitled Project/`: `Jarvis 2.swift`, `ContentView 2.swift`, `Suoni.swift`, `Aptica.swift`, `ChatAnimata.swift`, `Edith.swift`, `Orecchio.swift`, `SchedeSignore.swift` (CorniceScheda), `SchedaScanner.swift`, `Bea.swift`, `SchedeDaily.swift`, `Occhi.swift` · `JarvisOrologio Watch App/`: `VistaOrologio 2.swift` (SuoniOrologio, avvio, TestoChatOrologio), `JarvisOrologio 2.swift`, `SchedeOrologio.swift`, `BeaOrologio.swift` · `docs/edith`, `docs/costi`, `docs/bea`, `docs/mac`.

---

*Per ripartire: allega questo file e di' «continuiamo JARVIS». Gusti, persone e decisioni sono nella memoria dell'account.*
