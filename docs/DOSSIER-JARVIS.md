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
- **Dal 20 ott sera: iPhone/Mac +60%, Watch +15%** (`Avvio.velocita = 1.6`, `AvvioOrologio.velocita = 1.15` in `ChatAnimata.swift`, `AvvioOrologio` sul Watch): ogni tempo ÷1,6, caricamento chat compreso. `avvio.m4a`/`avvioorologio.m4a` **rimissati**: musica accelerata intera (rubberband, tono invariato) + le pulsazioni originali posate su ogni icona (scarto ≤2 ms). Icone, musica e aptica su **un solo orologio** (`CACurrentMediaTime` + latenza audio), niente pause in fila.
- **Scarico (iPhone, 20 ott sera)**: STRUMENTI e INTELLIGENCE (10 icone) distribuite su tutto lo scarico della musica (2,885→3,724 s), Bea sull'ultimo colpo (`Avvio.colpi`).
- **SINCRO**: da **Ricordi** (prima: Interprete) in poi (Watch: dalla 2ª icona di STRUMENTI) l'icona parte **110 ms prima** del colpo con la stessa molla più svelta (0,12 s), così arriva sul beep. Valore scelto da Alessandro sul mock.
- Watch: traccia propria `avvioorologio.m4a` con 19 pulsazioni. **Dal 20 ott sera le icone si accendono al contrario** (da Archivio a Briefing) e la barra scorre all'indietro con loro (la prossima icona sul bordo sinistro), finendo sulle prime, dove resta a riposo; raffica finale = GIORNATA a 120 ms. Parte dopo l'animazione d'apertura del Watch (0,6 s). Sfondo con la griglia dell'iPhone (passo 14). Aptica a fine gruppo. **Partitura sulla musica** (`AvvioOrologio.colpi`, misurata): prime 11 da 0 al colpo forte 2,499 s; pausa 2,6–2,8; ultime 8 su tutto lo **scarico** della musica (2,885→3,724 s, ogni 120 ms), Briefing sull'ultimo colpo. Molle 0,32 / 0,14 ÷ velocità; ogni icona parte prima del colpo del 44,5% della sua molla (lì è al 90%), così l'arrivo cade sul beep;  la musica parte al campione con play(atTime:).
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

## 11c. Build 21 e comandi vocali (21 ott)

- **Dialogo**: microfono spento solo durante l'avvio (`avvioInCorso`); a «SISTEMI IN LINEA» si apre l'ascolto, e dopo ogni risposta torna ad ascoltare da solo come nell'ultima versione buona. Fix: a fine risposta niente `setActive(false)` mentre riparte il microfono dell'attesa; riserva in `Richiamo.accendi` (`setActive(true)`). In LiDAR il microfono resta acceso (voluto da lui).
- **Comandi nuovi** (`ComandiVocali.swift`, parametro `dentro:`): LiDAR «fine scansione», «quanto è grande?», «quante persone ci stanno?», «salva», «mostrami il 3D» (eseguiti da `VistaLidar` via `jarvis.azioneLidar`); Sentinella «Jarvis, chi è passato?», «Jarvis, schermo nero», «Jarvis, spegni la Sentinella»; Wiretap «Jarvis, fai il verbale» / «fine riunione»; ovunque «traduci in inglese» (Interprete già sulla lingua, anche sul Watch).
- **Comandi per ogni sezione** (21 ott, pomeriggio): Allenatore e Interprete hanno ora un loro `OrecchioComandi` («Jarvis, …»): Allenatore fine serie, quante ripetizioni, postura, pausa/riprendi, azzera, conta mani/ginocchia/busto, cambia fotocamera; Interprete ascolta me/lui, passa al francese, cambia lingua, ripeti, turni automatici/manuali (l'orecchio è acceso solo tra un turno e l'altro; nel turno del signore una frase «Jarvis, …» è un comando, non si traduce). Allenatore: con l'orecchio acceso la voce usa playAndRecord, non playback. Comandi rapidi dalla schermata (`.rapido`): «scrivi il diario», «ho bisogno di parlarti», «cosa cucino?», «registra la riunione» (Wiretap che parte già). «Che canzone è?» resta al cervello (riconosci_musica).
- **GitHub**: `github_scrivi` resta com'è (scrive anche su main, chiede conferma): deciso da lui il 21 ott, lo usa con cautela.
- **Lista da stampare**: `docs/comandi/COMANDI-JARVIS.pdf` (sorgente `.html` accanto): da aggiornare a ogni comando nuovo.
- Il battito di mani e il controllo dell'impronta vocale solo col rumore: lasciati così, per sua scelta.

## 11d. MARK XI (11.0, 3 nov) — come ci si muove
- **iPhone/Mac**: click wheel sulla corona (dito sull'anello; ologramma dell'icona in alto nel reattore, tocco = apre); lente e click del Dock in alto (sul Mac anche col puntatore); le sezioni restano aperte (fino a 10) in un contenitore sopra JARVIS: swipe su dalla fascia poco sopra la barretta di iOS, come iPhone (pagina attaccata al dito; sollevata piano e ferma = vibrazione e pagine olografiche a metà pagina da sfogliare; lanciata = AGGANCIO, vola dentro il reattore a tempo col suono), bordi destro/sinistro = la sezione accanto (anche due dita sul trackpad del Mac). Tutte restano vive dietro (anche Studio e Social); fotocamera e microfono dietro in pausa, davanti riprendono da dove erano; il Wiretap dietro continua a registrare. La tendina PROTOCOLLI scende dall'alto come prima (titolo e centro del reattore).
- **Polso**: la barra delle icone solo col dito (ologramma nel reattore; dal 5 nov la corona non comanda più le icone, il signore: «avevo sbagliato io»); con la ruota viva il microfono d'attesa è spento, si riapre spenta la ruota. Nelle sezioni la corona per le pagine e, toccate, per le righe di lato (ore del Meteo, foto della chat). Sul polso niente sezioni dietro (watchOS).
- **AGGANCIO** (dal 4 nov, 11.0 (2)): lo stile ORIGINE · AGGANCIO II del mockup (diaframma e anelli giroscopici, poi il laser di AGGANCIO II con scintille a vortice, staffe che diventano un rombo, mirino, lampo e battiti), prospettiva della pagina come il mockup, tutto spento a 1,1 s.
- **Foto** (dal 4 nov, 11.0 (2)): la ricerca usa l'analisi di tutta la galleria (IndiceFoto, una volta sola, poi le nuove; conto a schermo), il dizionario italiano delle 1.303 categorie di Apple (DizionarioFoto) e gli album di Apple per selfie, screenshot, preferite e ritratti.
- **Ologrammi delle sezioni** (dal 4 nov, 11.0 (3), mockup v247): Cuore (il cuore che batte al ritmo di adesso, l'anello 40-180 con oggi, adesso e a riposo), Meteo (il cielo di adesso con la rosa dei venti), Foto (il pannello dell'analisi con la foto letta dal laser e le cose trovate; le parole capite sotto il campo; i risultati nuovi col laser); al polso Cuore e Meteo in piccolo. `OlogrammiSezioni.swift` è di iPhone e orologio insieme (nell'elenco dei file condivisi del progetto).
- **Frequenza**: tutte le animazioni al massimo dello schermo: 120 Hz su iPhone e Mac (anche Trainer, Traccia, Occhi, Vitals, Satellite), 60 Hz sull'orologio. Solo la ripresa LiDAR resta a 60 (ARKit). Dal 4 nov le sezioni dietro fermano le loro animazioni (e la fotocamera della Guida di Ricordi) e davanti ripartono; Studio e Social no (pagina web).
- **Aperture a voce** (dal 4 nov, 11.0 (3)): quando JARVIS apre Studio, Social, Occhi o l'Interprete, la sezione davanti va dietro viva (non si chiude); si chiude solo quello che sta sopra a tutto (tendina, tastiera, SISTEMI, pagina web, fotocamera di sistema). Una sezione che va dietro chiude il suo foglio di iOS (Dossier di SATELLITE, visore delle foto, Registro…). Una richiesta nuova a Studio o Social già davanti: la pagina scende e risale con la richiesta (scelta A). «Jarvis, chiudi» chiude anche Studio e Social. «Jarvis, apri il meteo» col Meteo già davanti: resta fermo.
- **Le sezioni a voce** (dal 4 nov, 11.0 (3), mockup v249 › A VOCE): «Jarvis, sezioni aperte» (le pagine olografiche, come sollevata piano col dito), «Jarvis, quella di prima» (torna davanti quella di prima), «Jarvis, chiudi il meteo» (qualsiasi sezione per nome, anche dietro), «Jarvis, mettila da parte» (AGGANCIO nel reattore, resta dietro), «Jarvis, chiudi tutto» (tutte, anche quelle dietro). Valgono anche dai microfoni di Wiretap, Sentinella, Interprete, Trainer, Profiler e Scanner (lì JARVIS non parla, vibra). JARVIS dice qualcosa solo se non si vede («Sezione Meteo chiusa, Sir.», «La sezione Meteo non è aperta, Sir.», «Nessuna sezione aperta, Sir.»). Riconoscimento: `ComandoVocale.navigazione` e `nomeSezione` (ComandiVocali.swift, in comune con l'orologio, dove vanno al cervello come prima); esecuzione: `ContentView.comandoSezioni` e `StratoSezioniVista` (le stesse animazioni del dito).
- **Niente si perde** (dal 4 nov, 11.0 (3)): il Wiretap chiuso da fuori (pagine olografiche, «chiudi tutto», per nome) fa come il suo «Chiudi» (con testo parte il verbale) e all'undicesima sezione non si chiude mai da solo. LiDAR: alla ✕ (e a «Modalità») con una scansione non salvata «SALVARE LA SCANSIONE?» uguale allo Studio (`FoglioSalva` in SchedeSignore.swift); chiusa in un altro modo si salva da sola; ARCHIVIO con ELIMINA › CONFERMA (3 s). Messaggi e Confidente tengono la bozza (file protetto sul telefono, `Bozze` in Comunicazioni.swift); «Cancella» nel Confidente.
- **Richieste nuove sul posto** (strada B, dal 4 nov sera, 11.0 (3), mockup v253): Ricordi, Browser, SATELLITE e LiDAR già aperti, davanti o dietro, e una richiesta nuova a voce («portami al luogo», «video di…», «come arrivo da Bea?», «metro laser»): la sezione torna davanti (0,38 s) e la fa lì, senza riaprirsi (`ContentView.richiestaSulPosto` › `.jarvisRichiestaSezione`). LiDAR con una scansione non salvata chiede prima «SALVARE LA SCANSIONE?»; la frase del modo la dice LiDAR quando parte. Il Browser dietro non prende più le frasi a voce (vanno a JARVIS). «Cerca…» da solo è di JARVIS; «cerca su Google…» o «googla…» aprono il Browser da ovunque e cercano lì (mockup v254).
- **Ologrammi nuovi** (dal 5 nov, dopo la 11.0 (3), mockup v261): Diario (il libro di oggi, la penna di luce, l'umore di 7 giorni), Sonno (la luna e l'anello delle fasi), Briefing (il quadrante delle 24 ore con alba, tramonto, adesso e impegni), Spesa (il carrello, i cubi che cadono dentro), Serata (l'anello dei soldi in «Da dove arrivano i soldi»), Bea (la sua foto in ologramma: Vision ritaglia la persona, salvata solo sul telefono). Al polso in piccolo tutti tranne Bea. `OlogrammiNuovi.swift` (iPhone e orologio), `OlogrammaBea.swift` (iPhone).
- **Le tre prove di ogni ologramma** (dalla 11.0 (6), mockup v262–v265): Diario (ELICA, RILIEVO, ORBITA), Sonno (LETTO, dal v266 al posto di ONDA; CICLI, NOTTI), Briefing (RADAR, GLOBO, PISTA), Spesa (CASSA, SCAFFALE, ANELLO), Serata (FLUSSO, TORRI, REATTORE), Bea (PUNTI, LINEE, VETRO e, dal v266, SCUDO: quattro chip): si scelgono con le chip sotto l'ologramma, la scelta resta (`@AppStorage` «oloProva.<sezione>») e va al polso nel contesto dell'orologio («oloProve»), dove la riga della sezione mostra la stessa prova in piccolo (46 punti, senza scritte né dita). Il dito di lato gira (con lo slancio), il tocco su un elemento apre il riquadro (in Spesa il tocco spunta la voce, come nella lista). File: `ProveOlo.swift` (il motore, `ProveOloVista`, `ProvaOloPiccola`) e `ProveDiario/Sonno/Briefing/Spesa/Serata/Bea.swift`, tutti anche dell'orologio. Gli ologrammi della v261 (`OlogrammaDiario`, `OlogrammaNotte`, `OlogrammaGiornata`, `OlogrammaSpesa`, `OlogrammaSoldi`, `OlogrammaBea`) restano nel codice ma non si usano più.
- **Click wheel** (dalla 11.0 (6)): l'ologramma dell'icona nasce con la GRIGLIA (`NascitaGriglia` in OlogrammiNuovi.swift, iPhone e polso) e l'icona è tagliata dalle righe di scansione (`RigheIcona`). Dal v266: nascita a 1,5× (GRIGLIA 0,31 s), appena la ruota arriva sull'icona; mentre gira tutto tenue (icona 20%), l'anello e la luce piena solo quando nasce.
- **Messaggi, Email, Confidente** (dal v267, 11.0 (6)): BOLLE (i messaggi di JARVIS come fumetti su un'elica), SMISTA (la casella come pila di lastre con le PRIORITÀ in alto; anche al polso), BILANCIA (la chat incollata sui piatti, il cuore di oggi nel perno). File: `ProveMessaggi.swift`, `ProvePosta.swift`, `ProveConfidente.swift`; la vista per un ologramma solo è `OloSingolaVista` (polso: `OloPiccolaVista`).
- **Avvio, la chat** (dal v266, 11.0 (6)): il caricamento HUD parte sul colpo dell'ultima icona (Bea), poi la stampa; le icone e la musica come prima.
- **Aperture** (dal 5 nov): tutte le sezioni in 0,45 s, iPhone e polso (`Apertura` in SchedeSignore.swift, `AperturaPolso` in SchedeOrologio.swift); dalla 11.0 (6) caricamento 0,28 s, stampa 0,32 s, dissolvenza 0,25 s.
- **Swipe su** (dalla 11.0 (6)): parte senza scatto; le pagine accanto si intravedono dal 18% dell'altezza, alla pausa oltre il 28% si completano con vibrazione e suono.
- **Icone in alto come il Dock** (dal 5 nov): il primo tocco le ingrandisce, il tocco sull'icona grande la apre; alzando il dito non si apre niente.
- File: `RuotaCorona.swift`, `OlogrammaRuota.swift`, `LenteDock.swift`, `StratoSezioni.swift`, `NavigaSezioni.swift`, `FotoLocali 2.swift`, `DizionarioFoto.swift`, `OlogrammiSezioni.swift`, `OlogrammaFoto.swift`; al polso `RuotaPolso.swift`, `OlogrammaPolso.swift`, `RigaCorona.swift`. Dettagli nel registro delle build (11.0 (1), (2) e (3)).

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

- **5 nov sera · swipe su lento = la PILA, come l'App Switcher di iOS** (11.0 (6), mockup v268 approvato «identico»): sezioni aperte in ordine d'uso (la più recente davanti a destra), pagina al 68,3% al centro, la precedente sporge di 0,198 pagine, icona e nome sopra ogni pagina, vetro olografico con trasparenza dinamica (al centro si legge, le altre trasparenti), dietro JARVIS sfocato; dito di lato scorre, in su chiude, tocco apre, tocco fuori torna a JARVIS; da JARVIS le pagine entrano da sinistra.
