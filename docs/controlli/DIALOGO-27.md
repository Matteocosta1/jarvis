# Dialogo 27: decisioni unite, difetti del dialogo, idee A-B-C-D (25 ottobre 2026)

**Rami (tutti pubblicati su GitHub, niente deploy, numeri di versione e build non toccati):**
- **App:** `claude/build-24` (worktree `S/lidar24`), da `3dbab71` a **`7fa4029`**. Non ho toccato `claude/build-23`.
- **Cervello:** `claude/decisioni-cervello` (worktree `S/dcerv`), da `1e3cdee` a **`86ed032`**. Contiene anche `claude/cervello-112` (decisione 27 annullata, già pubblicata dal coordinatore).

---

## In breve

- **Passo 1.** Le quattro decisioni del 24 ottobre sono dentro la build 24. Ho controllato tutte, numero per numero. Dove il lavoro di stanotte sostituiva il vecchio (Texture di LiDAR, HUD di Satellite), ha vinto stanotte. La **42 nel LiDAR 3D** c'era già nella pagina three.js, identica al mockup.
- **Passo 2.** Fatti i difetti **2, 3, 4, 5, 6 e 7**. Il **difetto 1** non l'ho fatto, come ha chiesto il signore.
- **Passo 3.** Fatte le idee **A, B, C e D**:
  - **A, Opus a voce più svelto.** Solo cervello.
  - **B, un solo JARVIS risponde.** Cervello e tre app.
  - **C, solo la sua voce lo ferma.** Solo iPhone. Sul Mac e al polso non si può fare in modo affidabile: lo spiego sotto.
  - **D, un giro solo.** Cervello, orologio e Mac. La strada di prima resta come riserva.
- **Ordine sicuro.** Tutto si accende da solo e in ordine:
  - le app nuove con il cervello vecchio fanno esattamente come prima;
  - il cervello nuovo con le app vecchie, idem.
- **Decisione 27 annullata** (richiesta arrivata durante il lavoro). Nel cervello la riga «Occhi:» è tornata com'era, uguale a `claude/cervello-112`, e la prova è aggiornata.
- **Cosa non ho potuto fare qui.** Non c'è Xcode, quindi niente compilazione: ho riletto tutto come farebbe il compilatore. Prima di caricare serve il Build di iPhone e orologio.

---

## 1. Passo 1: unione delle decisioni del 24 ottobre

Quattro unioni, una per commit:
- `f025389`: decisioni-22;
- `0d6e477`: decisioni-watch;
- `eec1b04`: decisioni-watch-23;
- `5427419`: decisioni-23.

### Conflitti risolti

**`ContentView 2.swift` (decisioni-22), `intestazione`**, come dice DEC-22 §4:
- tenute le misure strette della 23 (`tracking(mini ? 4 : 5)`, icone `padding 4`);
- aggiunti `larghezzaStretta` (riga 554), il parametro `stretta` e la rete di sicurezza sul titolo (`lineLimit`/`minimumScaleFactor`, righe 570-571);
- la chiamata alla riga 163 passa `stretta:`.

**`Lidar.swift` e `LidarCattura.swift` (decisioni-23):**
- Resta il flusso nuovo di Texture di stanotte. Fa già la decisione 24: «ELABORAZIONE… N%» da `stato.testo` (`LidarCattura.swift:1105-1107`, `Lidar.swift:319`).
- Ho tolto il doppione `elaborato`/`avanzamento` della 23. I due file sono identici a quelli di stanotte.

**`Satellite.swift`:**
- tenuti tutti e due gli import (`Combine` e `UIKit`);
- l'HUD di stanotte (coordinate a destra, più piccole; cielo in italiano) non è toccato;
- entrano `AttribuzioneMeteo` (19) e i cartellini dentro la mappa (42).

**Senza conflitti (ricontrollati a mano):**
- orologio: 36, 37, 38a-b-c, 39. Convivono con il microfono spento a mano (`micSpento`) e con `vaInSottofondo`. Tutti i nomi usati esistono, e nel polso non c'è nessun altro `setCategory(.ambient)`;
- `pbxproj`/Info.plist: 17 e 18. Numeri di build intatti.

### Decisione per decisione nel codice unito

Tutte presenti. Ho cercato ogni segno nel codice (comando nel controllo finale). Le principali:

| # | Dove |
|---|---|
| 12 | `ContentView 2.swift:1550` |
| 15 | `ContentView 2.swift:376`, `:386` |
| 16 p.1 | `ContentView 2.swift:163`, `:554` |
| 45 | `Traccia.swift:80` |
| 36 | `JarvisOrologio 2.swift` `diciSeSoloIPhone`; `VistaOrologio 2.swift:181` |
| 37 | `VistaOrologio 2.swift:27` `sessioneSuoni` |
| 38a | `fallisci` |
| 38b | `audioInterrotto` |
| 38c | `Musica 2.swift` `AttesaShazam` |
| 39 | `SatelliteOrologio.swift` `nonPartita`; `Orologio 2.swift` `seguiGuidaDalPolso` |
| 16 p.2 | `SatelliteSchermi.swift:392` |
| 17 | Info.plist `UIBackgroundModes`; `MotoreGuida.swift:326` |
| 18 | pbxproj 508/567 |
| 19 | `Satellite.swift:244` |
| 21 | `GuidaCondivisa.swift:23`; `OcchiStark.swift:699` |
| 24 | flusso di stanotte |
| 26 | `Occhi.swift:121` |
| 28 | `Jarvis 2.swift` `.ologramma`; `Allenatore.swift:707` |
| 29 | `OcchiStark.swift:872` |
| 33, 34 | `MusicaJarvis.swift:21`, `:173` |
| 41 | `SatelliteDossier.swift` |
| 42 | mappa 3D `Satellite.swift:504`; NAVIGA/GUIDA `SatelliteSchermi.swift:271` |
| 42 LiDAR 3D | `Lidar3D/lidar3d.html:3747` (`dentroBox`) e `:4375`. È la stessa funzione e la stessa chiamata del mockup (`jarvis-mark7.html:2189` e `:2736`): le etichette restano intere nel riquadro |
| 44 | nessun cambiamento, come DEC-23 |

**Controlli:** `ts/sintassi.sh`: solo il noto `SchedeDaily.swift:165`. I file del Watch presi da `Untitled Project` sono quelli dell'elenco nel pbxproj (Build22, ComandiVocali, Satellite23…); nessun file nuovo.

---

## 2. Passo 2: i difetti del controllo del 25 ottobre

### Difetto 1: NON fatto
Il signore non lo vuole. Non c'è nessuna riga del difetto 1.

### Difetto 2 (Mac): le parole dette sopra JARVIS · `50e7086`

**Cosa cambia per lei:**
- «basta», «muto», «aspetta» detti sopra la voce di JARVIS non finiscono più buttati come eco;
- una domanda detta sopra arriva al cervello senza pezzi della risposta di JARVIS;
- i pezzi di sola voce di JARVIS non vanno più in cloud.

**Dove:**
- **`Build22.swift:201` `Dialogo.togliEcoAiBordi`** (con `ecoInTesta`): toglie le parole di JARVIS **in testa e in coda** al pezzo trascritto.
  - In testa servono almeno 2 parole di fila. In coda almeno 3, oppure 1-2 subito dopo una sua parola d'ordine.
  - Le sue parole d'ordine non si tolgono mai: «basta», «muto», «zitto», «stop», «aspetta», «ascoltami», «Jarvis»…
- **`Jarvis 2.swift:1923` `fraseSentitaMac`:**
  - lavora sul testo ripulito;
  - se non c'era eco ai bordi resta la regola di prima (60% di parole sue), ma mai con una parola d'ordine (`haParolaDOrdine`);
  - un residuo di 1-2 parole sue («Sir») è eco (`eResiduoDiEco`).
- **`AscoltoCloud.swift:162` `EcoMac`.** Tiene il volume della voce di JARVIS mentre esce:
  - streaming: `Jarvis 2.swift`, `seguiVolume`;
  - frasi in cache: `EcoMac.segui`.

  Il `Segmentatore` (`segnaEco`, `:375`) confronta il microfono con l'eco:
  - **Non va in cloud** (`:537`) un pezzo sentito tutto mentre JARVIS parlava, con la sua voce sempre nota, e mai più forte della soglia.
  - **La soglia la impara da sola** (`:557` `impara`) dalle frasi trascritte che sono risultate tutta eco. Ne servono 3. Finché non le ha, si trascrive tutto come prima.
  - **Nel dubbio si trascrive:**
    - voce mentre JARVIS tace fra due frasi;
    - voce dell'iPhone di riserva, che non dice quanto è forte;
    - volume del Mac alzato.

    Quindi il controllo non può far perdere un «basta».
- **Mentre JARVIS parla senza pause:**
  - il pezzo con il signore si chiude 0,5 s dopo che il microfono torna al livello dell'eco. Prima aspettava una pausa di JARVIS, fino a 10 s;
  - il taglio dei «10 s di rumore continuo» non vale più sopra la sua voce. Prima buttava anche il «basta» che c'era dentro.
- **Il tetto.** I pezzi risultati tutta eco non contano nel tetto delle 40 trascrizioni ogni 10 minuti.

**Prova:** `S/d27/eco.py`, lo specchio Python di `togliEcoAiBordi` e della decisione di `fraseSentitaMac`. **21/21 giusti.** Esempi:
- «…pomeriggio basta a Roma invece il sole» → «basta»;
- «piove dalle tre e a Torino che tempo fa?» → «e a Torino che tempo fa»;
- «basta tornerà già» → «basta»;
- «Sir.» → eco.

**Limite noto (scritto anche in DA CHIEDERE 1):** se lui ripete solo parole appena dette da JARVIS («e a Roma?» dopo «…a Roma sole»), la frase resta eco come oggi.

### Difetto 3 (Watch): un rumore non perde più la risposta · `fb0c8dc`

`JarvisOrologio 2.swift`:
- **`:141` `RispostaSospesa`:** `interrottoAVoce` ricorda la risposta prima di segnare il taglio.
- **`:679`:** se, tolta la voce di JARVIS, nella registrazione non resta nessuna parola (o solo versi: «ahah», «ehm», «coff»), parte **`:751` `riprendiRisposta`**:
  - **risposta già arrivata tutta:** dice da solo le frasi mancanti dal punto esatto (`Dialogo.taglio`) e la cronologia torna intera;
  - **ancora in arrivo:** chiede il seguito al cervello come un «continua» (decisione 53). A schermo resta la sua domanda.
- Quando lui dice davvero qualcosa non cambia niente. `ferma()` cancella la risposta sospesa.

### Difetto 4 (iPhone): folla o TV nei 2 s dopo la domanda · `82d978f`
`Richiamo.swift:316`:
- la finestra dell'aggiunta segue la regola della folla: `inAggiunta && (!affollato || voceConfermata)`;
- in mezzo alla gente, nella finestra, si controlla l'impronta anche con «Risponde a qualsiasi frase» spento;
- la «fiducia di conversazione» appena data da «Jarvis» non basta più: era proprio il caso del «sì sì» del vicino;
- in casa, in silenzio, tutto come prima.

### Difetto 5: GPS sveglio quando comincia ad ascoltare · `c359623` (app) e `7a708ae` (cervello)

**App.** `Posizione.swift:42` e `PosizioneOrologio.swift:40` hanno `scalda()`, al massimo una volta ogni 30 s. Si chiama:
- iPhone/Mac: in `avviaAscolto` (`Jarvis 2.swift:1846`), `richiamato` (`:612`) e `zittisciPerAscolto` (`:374`);
- Mac: quando il microfono dell'attesa sente cominciare una frase (`AscoltoCloud.swift:476`, `quandoComincia`);
- polso: in `ascolta` e `continuaAscolto` (`JarvisOrologio 2.swift:403`, `:614`).

**Cervello.** `index.ts:4083` `registrazione` e `:4089` `giaFatta`:
- il numero della richiesta (`x-richiesta`) si registra **insieme** alle letture del turno, non prima;
- la richiesta ripetuta con la risposta già pronta si rimanda dentro il flusso (stesse due righe di prima).

### Difetto 6 (iPhone): sottofondo mentre parla sopra JARVIS · `7733c38`
- `Orecchio.swift:47`: nuovo `raccoglie`;
- `Jarvis 2.swift:2203`: `vaInSottofondo` ferma anche l'orecchio che stava raccogliendo la frase;
- al polso era già coperto (`vaInSottofondo` chiude l'ascolto, anche quello partito dall'orecchio).

### Difetto 7 (Mac): l'interruttore «Risponde a qualsiasi frase» · `50e7086`
- **`Jarvis 2.swift:1954`:** `fraseSentitaMac` legge l'interruttore. Spento: in attesa e mentre pensa serve «Jarvis» (o «ehi», «bro»…) o la frase di Tony. Valgono comunque:
  - il seguito di 8 s dopo una risposta (`liberoMacFinoA`, che prima non leggeva nessuno);
  - l'aggiunta di 2 s.

  Parlargli sopra mentre parla non dipende dall'interruttore, come sull'iPhone.
- **Valore di partenza acceso anche sul Mac**, in tre posti:
  - `Jarvis 2.swift:63`;
  - `JarvisApp.swift` (`register`);
  - `ContentView 2.swift:1501` (`@AppStorage`).
- **`JarvisApp.swift:13`:** sul Mac, **una volta sola**, il valore torna a quello di partenza. Così uno «spento» rimasto da quando l'interruttore non faceva niente non cambia all'improvviso come risponde il Mac. Oggi il Mac risponde come prima.

---

## 3. Passo 3: le idee approvate

### A: Opus a voce più svelto · cervello `1883a47`

`index.ts:3029` `sforzo`, `:3034` `RAGIONAMENTO`, `:4285`:
- Quando l'app manda `a_voce` (le frasi dette a voce: le tre app ora lo mandano), anche **Opus ragiona «low»**. La prima parola arriva prima.
- **Restano «medium»:**
  - le richieste da ragionamento vero: analizza, confronta, ragiona, valuta, decidi, calcola, conti, serata, incassi, bilancio, progetta, strategia, pianifica, codice, script, profilo, scrivi, prepara, proposta, riassumi, pro e contro, conviene, «nel dettaglio», «nei dettagli», «spiegami bene»;
  - il Wiretap.
- **Lo sforzo resta lo stesso per tutto il turno.** Dopo gli strumenti del dispositivo il modello viaggia come `modello|voce` e torna con «continua»: le app lo rimandano così com'è.
- **Interruttori:**
  - `SFORZO=off` spegne tutto lo sforzo, come prima;
  - nuovo `OPUS_VOCE_SFORZO=off` spegne solo questa idea.
- Sonnet e Haiku non cambiano. La cache copre solo istruzioni e strumenti: lo sforzo non la tocca.

### B: un solo JARVIS risponde · cervello `7a708ae`, app `e0e7aa5`

**Come funziona.** Ogni frase detta a voce parte con `arbitro: {id, fine}`:
- `id` è il numero di questa installazione: `Impostazioni.idDispositivo` (`Jarvis 2.swift:68`) e `ImpostazioniOrologio.idDispositivo`;
- `fine` è quando lui ha smesso di parlare: l'ultima parola del riconoscimento, la fine del pezzo sul Mac, la fine della voce al polso.

**Nel cervello**, `index.ts:3803` `arbitra`, nuova tabella `jarvis_arbitro`:
- **Un dispositivo solo:** la frase vince subito, senza attese. Costa una scrittura e una lettura, in parallelo con le altre letture.
- **Due dispositivi, la stessa frase quasi uguale nello stesso momento** (in comune, in ordine, almeno 3/4 delle parole, a meno di 4 s): risponde uno solo.
  - Vince chi l'ha sentita **finire per primo** (precisione 0,4 s); a pari merito, chi ne ha sentito di più.
  - Chi ha già vinto resta vincitore.
  - Se un altro dispositivo è stato attivo negli ultimi 2 minuti, il cervello aspetta 0,3 s che arrivi anche la sua copia.
- **Chi perde** riceve `{"t":"doppione"}`, tace e torna in attesa:
  - iPhone/Mac: `concludiDoppione`, `Jarvis 2.swift:1450`;
  - Watch: `doppione()`, `JarvisOrologio 2.swift:1263`.

  La domanda sparisce dalla sua chat: la vede chi risponde. Nei tempi risulta turno «doppione».
- **Si apre sempre:**
  - database assente, guasto o lento (oltre 1,2 s): la frase vince;
  - id non valido: la frase vince;
  - domande scritte e tasti: nessun arbitro.

  Meglio due voci che nessuna.

### C: solo la sua voce lo ferma, se l'impronta c'è · `3e81a4e` (solo iPhone)

- **Mentre pensa** (`Richiamo.swift:321`, con `richiamo.inRisposta`, `Jarvis 2.swift:305`): con l'impronta registrata e «riconosciVoce» acceso, una frase senza «Jarvis» ferma la risposta solo se l'impronta la riconosce (`controllaVoce`). Vale anche nei 2 s dell'aggiunta. Restano valide:
  - la frase di Tony;
  - in una stanza tranquilla, «muto», «basta», «stop».
- **Mentre parla** (`Orecchio.swift:192`): il controllo dell'impronta, che prima valeva solo con la folla, vale anche nella calma.
- **Parole d'ordine.** «Jarvis», «basta», «muto», «aspetta» fermano sempre, come prima.
- **Tutto come prima** senza impronta, con «Riconosci la voce» spento, e per cominciare una conversazione nuova.
- **Costo:** circa 0,7 s prima di fermarsi.

**Prova:** `S/d27/richiamo.py`, la tabella delle decisioni di Richiamo con 4 e C. **13/13 giusti.**

**Detto chiaro: dove C non si può fare in modo affidabile.**
- **Mac.** Il microfono non cancella l'eco: è spenta apposta, per non abbassare le altre app. Il pezzo che si dovrebbe riconoscere contiene anche la voce di JARVIS dagli altoparlanti, quindi l'impronta lì darebbe esiti a caso. Non l'ho messo.
- **Orologio.** Non ha l'impronta: il modello `VoceModello.bin` e `VoceDelSignore` sono solo dell'iPhone. Non l'ho messo.

### D: un giro solo · cervello `7a708ae`, orologio `abe136d`, Mac `7fa4029`

**Cervello** (`index.ts:4196`, `:3745` `trascriviTesto`):
- Riceve `audio_domanda` (wav del Mac, m4a dell'orologio), `prefisso_domanda` (la nota d'interruzione o di seguito che l'app metterebbe) e la cronologia senza la domanda.
- Trascrive con ElevenLabs Scribe e manda subito `{"t":"trascritto"}`. Poi aspetta mentre fa le letture (150 ms; 300 ms per l'orologio, che passa spesso dall'iPhone e ha un giro di rete più lungo), e solo dopo chiama Claude.
- Con la frase in audio il filo della conversazione si aggiorna solo dopo il primo giro con Claude: un comando chiuso dall'app non ci finisce.
- Se l'app chiude la linea (era un suo comando), Claude non parte e il turno non risulta interrotto.
- Se la trascrizione fallisce, `trascritto` porta l'errore.
- La sveglia dice `giro_unico: true` (`:3936`).

**Orologio** (`JarvisOrologio 2.swift:513`; `:1236` `accettaUnico`; `:1639` `CanaleUnico`):
- Una frase normale va in una richiesta sola. Non vale per un'interruzione sopra JARVIS né per l'aggiunta a una frase di prima: quelle restano sulla strada di prima.
- Al «trascritto»:
  - **domanda normale:** la accoglie come `chiedi(testo, aVoce: true)` e la risposta continua nella stessa richiesta;
  - **comando dell'orologio, frase dell'iPhone, interprete, «piano», «muto», solo «aspetta»:** chiude la richiesta all'istante con `PresaRichiesta` (`Build22.swift:81`) e fa come prima con il testo già trascritto.
- L'aggiunta dei 2 s aspetta il testo della prima frase da `CanaleUnico`: non si perde.
- Trascrizione fallita o risposta non 200: la trascrizione di prima (`jarvis-ascolto`, con i servizi in gara).

**Mac** (`Jarvis 2.swift:1471` `partiGiroUnico`, `:1493` `accettaGiroUnico`, `:1572` `lasciaGiroUnico`; `AscoltoCloud.swift:566`):
- Vale per due frasi:
  - quella sentita in attesa, senza la voce di JARVIS in mezzo;
  - quella registrata dopo il tocco o dopo «Jarvis» da solo.
- Al «trascritto» si rifanno **senza eseguire niente** i controlli di prima: eco, folla, interruttore, nome da solo, comandi dell'app (`comandoLocale`), «aspetta», interruzione o seguito.
  - **domanda normale con la stessa nota:** si accoglie come `invia`;
  - **altrimenti:** la richiesta si chiude all'istante e si fa come prima.
- La strada di prima resta per: foto in giro, Occhi, LiDAR, Browser, Confidente, e la trascrizione fallita.
- L'attesa del Mac manda la frase successiva solo dopo (`viaggioFinito`): l'ordine delle frasi è quello di prima.

**Quando si accende.** Solo quando la sveglia del cervello ha detto `giro_unico` (chiave `giroUnicoCervello`):
- l'iPhone (e il Mac) lo legge nella `riscalda` che fa già;
- l'orologio fa ora anche lui la sveglia all'avvio, in `controllaCollegamento`, e così scalda il cervello prima della prima domanda.

**Guadagno atteso** (da misurare dal vivo):
- al polso, un giro di rete in meno e niente avvio di `jarvis-ascolto`: da mezzo secondo a un secondo;
- sul Mac, una richiesta in meno: alcune centinaia di millisecondi.

---

## 4. Controlli fatti

### Cervello (`S/dcerv`)
- **`bash S/cervtest/tutte.sh`:** **21 file, 0 sbagliate in tutti** (esito in `S/d27/finale-tutte.txt`).
- **Prove nuove** (anche in `supabase/prove/`):
  - `prove_sforzo.ts` (A): **10/10**;
  - `prove_arbitro.ts` (B): **14/14**. Casi provati:
    - un dispositivo, che non aspetta (meno di 250 ms);
    - iPhone + Mac quasi insieme;
    - frasi diverse;
    - stesso dispositivo due volte;
    - copia in ritardo;
    - vince chi ha sentito per primo anche se arriva dopo;
    - pari tempo: vince chi ha sentito più parole;
    - senza arbitro;
    - database guasto;
    - id non valido;
  - `prove_giro_unico.ts` (D e difetto 5): **24/24**. Casi provati:
    - «trascritto» prima della risposta, con prefisso e cronologia giusti;
    - la linea chiusa subito dopo: nessuna chiamata a Claude e nessun turno «interrotto»;
    - errore di trascrizione;
    - niente di detto;
    - m4a dell'orologio;
    - sveglia;
    - audio + arbitro;
    - richiesta ripetuta con la risposta pronta;
    - richiesta ripetuta ancora in lavorazione;
    - il filo non si tocca se l'app chiude la linea, e si aggiorna con una domanda vera.
- **`prove_testi_decisioni.ts`** aggiornata per la decisione 27 annullata: 0 sbagliate.
- **`bash S/tscheck/check.sh`:** 0 errori.
- La riga «Occhi:» è identica a `claude/cervello-112`. `git diff` sulla riga: nessuna differenza.

### App (`S/lidar24`)
- **`bash S/ts/sintassi.sh S/lidar24`:** solo il noto `SchedeDaily.swift:165`, dopo ogni commit.
- **Specchi Python:** `S/d27/eco.py` (difetto 2, 21/21) e `S/d27/richiamo.py` (difetti 4 e C, 13/13).
- **Rilettura come farebbe il compilatore** di tutto il diff (`S/d27/diff-jarvis.txt`, `S/d27/diff-polso.txt`):
  - switch esaustivi sui nuovi casi di `Esito`;
  - `return` con valore in `fraseSentitaMac`, che ora dà un `Bool`;
  - tuple etichettate scritte per esteso; `Int?` esplicito;
  - nessuna funzione locale dentro una chiusura; nessuna `var` catturata in un `Task`;
  - i tipi nuovi `nonisolated final class … @unchecked Sendable` hanno il loro `NSLock` (`EcoMac`, `PresaRichiesta`);
  - `@MainActor` dove servono il MainActor e `CheckedContinuation`;
  - import: `PresaRichiesta` in `Build22.swift` (Foundation; è nei due target), `EcoMac` in `AscoltoCloud.swift` (AVFoundation);
  - API: `URLSession.bytes(for:delegate:)` e `URLSessionTaskDelegate.urlSession(_:didCreateTask:)` sono di iOS 16 e watchOS 9 (le destinazioni sono iOS 17.6 e watchOS 10.6); `ProcessInfo.systemUptime`.
- **Destinazione Watch:** il codice nuovo comune (`PresaRichiesta`, `togliEcoAiBordi`) è in `Build22.swift`, che il Watch compila. `CanaleUnico` è solo nel file del polso. `EcoMac` e `GiroUnicoMac` sono solo iPhone/Mac.
- **Riconoscitore dei comandi:** non toccato, quindi `S/verifica22` non va rifatto.

### Cosa non si può verificare qui
- La compilazione.
- La soglia dell'eco sul Mac vero e l'impronta nella calma.
- I tempi veri del giro unico.

Tutto è nelle prove dal vivo qui sotto.

---

## 5. Cosa provare sul telefono, sul Mac e al polso (dopo migrazione, deploy e Build)

1. **Build in Xcode** di iPhone e orologio dal ramo `claude/build-24`.
2. **Difetto 2 (Mac):**
   - mentre JARVIS parla una risposta lunga, dica solo «basta»: deve fermarsi entro circa 1-2 s;
   - poi «e a Torino che tempo fa?» detto sopra: in chat compare solo la sua frase;
   - dopo tre o quattro risposte lasciate dire per intero senza parlare, sotto il reattore il numero «frasi N» non deve più salire mentre JARVIS parla.
3. **Difetto 3 (polso):**
   - mentre JARVIS risponde, tossisca o batta le mani: JARVIS riprende la frase dov'era;
   - con una risposta ancora in arrivo, riparte da lì dopo un attimo.
4. **Difetto 4 (iPhone):** TV alta. «Jarvis, che ore sono?» e qualcuno dice subito «sì sì»: JARVIS risponde all'ora.
5. **Difetto 5:** app aperta, 5 minuti di pausa, poi «Jarvis, che tempo fa?»: la risposta parte come le altre.
6. **Difetto 6 (iPhone):** mentre JARVIS parla gli parli sopra e, a metà frase, blocchi il telefono. Al ritorno non deve rispondere a quella frase.
7. **Difetto 7 (Mac):**
   - Impostazioni: «Risponde a qualsiasi frase» acceso, il Mac risponde come prima;
   - lo spenga: una frase senza «Jarvis» non è più per lui, salvo subito dopo una risposta (8 s).
8. **A:** «ricordami cosa avevamo detto ieri sulle chiavi» (Opus): la prima parola deve arrivare prima di ieri. «Analizza gli incassi di sabato» resta pieno. In `jarvis_consumi`, servizio «turno», `ms_prima_parola` di Opus a confronto con il 24 ottobre.
9. **B:** iPhone e Mac aperti insieme, «Jarvis, che tempo fa domani?»:
   - risponde uno solo;
   - sull'altro la domanda sparisce e torna in attesa;
   - in `jarvis_arbitro` una riga vince e una no.

   Poi lo stesso con orologio + Mac.
10. **C (iPhone, con l'impronta registrata):**
    - mentre JARVIS spiega, Bea dice due parole: JARVIS non si ferma;
    - lui dice «e domani?»: si ferma (circa 0,7 s);
    - «basta» lo ferma sempre;
    - con «Riconosci la voce» spento torna come prima.
11. **D (polso):**
    - «Jarvis, che tempo fa?» al polso: risposta più rapida di prima;
    - «apri il meteo» al polso: si apre la scheda, nessuna risposta del cervello (in `jarvis_consumi` nessun turno; con una rete molto lenta al più un turno «interrotto», senza risposta e senza filo);
    - una domanda e poi subito un'aggiunta («…e domani?»): partono insieme come prima.
12. **D (Mac):** le stesse prove con il Mac. Anche «Jarvis» da solo, attesa, poi la domanda.

---

## 6. DA CHIEDERE

1. **Mac, frasi che ripetono le parole di JARVIS (difetto 2).** «e a Roma?» detto subito dopo «…a Roma sole» resta trattato come eco, come oggi: 2 parole su 3 erano sue. Sui bordi tolgo l'eco solo con almeno 2 parole in testa o 3 in coda, proprio per non mangiare le sue parole.
   - Opzioni: (a) lasciare così; (b) abbassare la regola del 60% per le frasi corte che finiscono con «?».
   - **Consiglio (a)**: (b) rischia di far rispondere JARVIS alla propria voce.
2. **C sul Mac e al polso.** Non si può fare in modo affidabile (sezione 3, C). Va bene così? **Consiglio: sì.**
3. **C, l'aggiunta di una parola sola.** Con l'impronta registrata, un «sì» detto da solo nei 2 s dopo la domanda non basta più. L'impronta vuole almeno due parole: va detto «Jarvis, sì» oppure una frase.
   - Opzioni: (a) così; (b) nei 2 s dell'aggiunta le risposte brevi passano senza impronta, nella calma.
   - **Consiglio (a)**, perché è proprio il caso di Bea che dice «sì».
4. **B, i comandi dell'app.** «Jarvis, apri il meteo» sentito da iPhone e Mac si apre su tutti e due, perché i comandi non passano dal cervello. Va bene così, o anche quelli solo sul dispositivo più vicino? (Servirebbe un messaggio fra le app.) **Consiglio: così.**
5. **D al polso, chi trascrive.** Nel giro unico trascrive ElevenLabs Scribe (lo stesso del Mac). La strada di prima metteva in gara Groq, Gemini ed ElevenLabs. Se Scribe sbaglia una parola, non c'è un secondo parere: si ripassa dalla gara solo se Scribe dà errore.
   - Opzioni: (a) così; (b) anche il cervello mette in gara più servizi (servono i segreti GROQ/GEMINI nella funzione `jarvis`).
   - **Consiglio (a)**, poi si guarda dal vivo.
6. **A, l'elenco delle richieste «da ragionamento»** (sezione 3, A): va bene così o vuole aggiungere o togliere qualche parola?
7. **Difetto 7, il ritorno una tantum sul Mac.** All'aggiornamento, sul Mac l'interruttore torna acceso una volta. Se lo aveva spento apposta, va rispento. **Consiglio: tenere** (così il Mac non cambia comportamento da solo).

---

## 7. Migrazione e deploy (per il coordinatore)

1. **Migrazione** (non applicata da me): `S/dcerv/supabase/migrazioni/2026-10-25-un-solo-jarvis.sql`. Crea `public.jarvis_arbitro` con RLS acceso e senza regole, come le altre tabelle.
   - Senza la tabella il cervello funziona lo stesso: l'arbitro fallisce in silenzio e risponde sempre.
   - Ma va applicata **prima** delle prove di B.
2. **Deploy della funzione `jarvis`** da `claude/decisioni-cervello` (ultimo commit del ramo, vedi in cima).
   - Dentro: tutto `claude/cervello-112` (già vivo), più A, B, D e il difetto 5.
   - `jarvis-briefing` non cambia rispetto a `cervello-112`.
   - Nessun segreto nuovo obbligatorio. Facoltativo: `OPUS_VOCE_SFORZO=off`, per spegnere solo l'idea A.
3. **Dopo il deploy:**
   - `{"sveglia":true}` deve rispondere con `"giro_unico": true`;
   - una domanda di prova deve dare un turno «fine» in `jarvis_consumi`.
4. **App:** dopo la revisione, `claude/build-24` (`7fa4029`) va portato su `claude/build-23`. Non l'ho fatto io, come da istruzioni. Il numero di build lo decide il signore.
5. **Ordine sicuro.**
   - Le app nuove con il cervello vecchio: niente `giro_unico` (si usa la strada di prima) e i campi `a_voce`/`arbitro` vengono ignorati.
   - Il cervello nuovo con le app vecchie: nessun arbitro, sforzo come prima, nessun audio.

   Si può pubblicare in qualsiasi ordine.
