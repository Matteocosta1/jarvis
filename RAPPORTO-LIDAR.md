# LiDAR · build 23 «MARK IX» — rapporto

Ramo `claude/23-lidar` (già unito con build-22). Niente merge, numeri di versione e nome «MARK» non toccati.
Riferimento: `mockup-23-riferimento.html` (#23 = build 23, senza # = l'app di oggi), letto e provato con Playwright
(`modiLidar`, `scansionaModo`, `apriLidar`, `mostraRisultato`, `MODI_LIDAR`, `NOME_LIDAR`, `RISULTATI_LIDAR`, `scena3d`, `monta3d`, `disegnaModo`).

## In parole semplici

LiDAR ora si apre su un menu con sei modi: **Interno, Esterno, Setup, Oggetto, Corpo, Misura** (Corpo ha Postura, Ologramma, Texture).
Ogni modo ha l'anteprima 3D che gira, il suo testo, le frasi «A VOCE» e il tasto **Scansiona**. La scansione usa davvero il sensore:
la stanza con RoomPlan (come la 22), il giardino e gli oggetti con la «maglia» del LiDAR e i colori veri presi dalla fotocamera,
le pareti con i piani di ARKit, la postura con lo scheletro che vede l'iPhone, il «gemello digitale» con Object Capture di Apple
(il modello fotografico si costruisce sull'iPhone, circa 2 minuti). Alla fine il risultato in 3D (OLOGRAMMA o TEXTURE), le righe con
i numeri veri, **Salva · Modalità · Chiedi**. Chiusura con la X nel cerchio (sezione con fotocamera). L'orologio non cambia.
Non ho potuto compilare (qui non c'è Swift): il codice è controllato riga per riga, con le API verificate sulla documentazione Apple;
va provato sull'iPhone 15 Pro (elenco sotto).

## File

| File | Cosa |
|---|---|
| `Untitled Project/Lidar.swift` (modificato) | La sezione: menu → scansione → risultato. Interno con PIANTA · OLOGRAMMA · TEXTURE · ARCHIVIO. RoomPlan esteso: pavimento (poligono), altezze di porte e finestre, «sala chiusa», stanza dal vivo per Setup. Tolta la vecchia vista «3D» a fil di ferro (sostituita da OLOGRAMMA/TEXTURE). |
| `Untitled Project/LidarModi.swift` (nuovo) | I modi con i testi del mockup parola per parola, i risultati con i numeri veri, l'archivio dei modi, menu, schermata di scansione, risultato, tasti (.chip, .comando, .tavola, X). |
| `Untitled Project/LidarScena.swift` (nuovo) | Il 3D olografico in SceneKit: la `scena3d` del mockup (ologramma fresnel con righe, materializzazione dal basso 1,1 s, mirino ad anelli, polvere, nuvola di punti in anteprima, quote ed etichette nel risultato, casa delle bambole, giro col dito / due dita / doppio tocco, ripresa del giro dopo 2,6 s). Trame «fotografiche» del mockup (parquet, intonaco, erba, terra, laminato, noce, moquette). |
| `Untitled Project/LidarCattura.swift` (nuovo) | Le catture: ARKit (Esterno, Oggetto, Misura, Postura) e Object Capture (Texture), con i conti su una coda separata. |
| `Untitled Project/LidarAllestimento.swift` (nuovo) | Setup: palco, console, bar, stand, passaggi e uscite posati sulla pianta vera. |
| `Untitled Project/ComandiVocali.swift` | Le frasi dei modi (solo iPhone, `#if os(iOS)`: il file è anche nell'orologio, che resta identico). |
| `Untitled Project/Jarvis 2.swift` | 6 righe: una frase di modo detta da fuori apre LiDAR già su quel modo e lo fa partire. |
| `verifica22/casi.py`, `verifica22/riconosci.py` | Casi nuovi (le frasi dei modi, da casa, da dentro LiDAR, da una scheda; domande vicine che restano al cervello) e lo specchio Python delle regole. |

Non toccati: Occhi, Allenatore, Satellite, ContentView (icone e barra), Protocolli, Organismo (riuso solo `corpo.bin`, le giunture e `EtichettaOlo`), Info.plist (basta il permesso fotocamera che c'è già).

## Mockup → app

| Mockup 23 | App |
|---|---|
| `apriSezione("LiDAR")` #23: niente caricamento HUD, `modiLidar` su Interno e OLOGRAMMA | `VistaLidar` parte da `.menu`, `modo = .stanza`, `stile = .pieno`; tolta `aperturaHUD` (era della 22) |
| X nel cerchio (`#sezione.camera #chiudiSez`) | `ChiudiLidar` (44 pt, cerchio ciano come Occhi/Profiler) su menu, scansione e risultati |
| `.modi-l.sei`: INTERNO ESTERNO SETUP / OGGETTO CORPO MISURA | `MenuLidar`: griglia 3 × 2, 10 pt |
| riga Corpo: POSTURA · OLOGRAMMA · TEXTURE; riga stile OLOGRAMMA · TEXTURE (nascosta in Corpo e Misura) | uguali, stessa logica di `scegli()` (`corpoLidar`, `stileLidar` condivisi) |
| tavola 720 × 420 con `monta3d(..., "anteprima")` | `TavolaLidar` 720/420 + `Vista3DLidar(.anteprima)`: esempi del mockup (SALA, GIARDINO, CASSA, ALLESTIMENTO, persona MakeHuman, parete 3,42 × 2,70) |
| pannello titolo + testo, «A VOCE», «Scansiona» | `Pannello`, `PannelloAVoce`, `TastoLidar` |
| scansione: HUD 3 valori, «ACCENSIONE SENSORE…» 0,7 s → `aCamera` → istruzione + Fine | `CorniceScansione`: stessi valori, stessi testi, `Suoni.aperturaCamera()` a 0,7 s |
| Fine troppo presto: «ANCORA UN ATTIMO…» / Interno «ANCORA UN ATTIMO: MANCANO DELLE PARETI»; pronto: «FATTO · TOCCHI FINE» / «SALA CHIUSA · TOCCHI FINE» | uguali (vedi DA CHIEDERE 3) |
| «ELABORAZIONE…» 0,8 s / «ELABORAZIONE PIANTA…» 0,9 s, poi `aPronta` | uguali (minimi rispettati) + `Suoni.schedaPronta()` |
| risultato modi: OLOGRAMMA · TEXTURE (non in Corpo e Misura), tavola 720 × 560, pannello con righe e nota, Salva · Modalità · Chiedi | `RisultatoModoVista`; Misura sempre in TEXTURE, Corpo senza stile, come `monta3d` del mockup |
| Interno: PIANTA · OLOGRAMMA · TEXTURE · ARCHIVIO, MISURE, CAPIENZA, Salva · Condividi · Chiedi | uguali (OLOGRAMMA/TEXTURE dalla stanza vera: pareti, porte, finestre, pavimento) |
| etichette `.et` (normale, grande, ambra, verde), «360°», «RILIEVO ×3» | `EtichettaOlo` sul modello (10 pt fissi sullo schermo), «360°» e «RILIEVO ×3» sopra la tavola |

Testi: controllo automatico (`scratchpad/lidar_testi_check.py`) di 135 stringhe del mockup (nomi, sottotitoli, testi, frasi, HUD,
istruzioni, note, etichette delle righe, stati): 130 presenti identiche; le 5 restanti sono le domande d'esempio di «Chiedi» (vedi DA CHIEDERE 7)
e «A VOCE», che è già nel componente comune.

## Come lavora ogni modo (API vere, iPhone 15 Pro · iOS 17.6)

- **Interno** — RoomPlan come nella 22 (`RoomCaptureView`, `RoomBuilder`). Nuovo: «sala chiusa» quando ogni capo di parete tocca (≤ 35 cm) quello di un'altra; pavimento come poligono (`floors.polygonCorners`), altezze vere di porte e finestre per il 3D.
- **Setup** — la stessa scansione RoomPlan; mentre la stanza si forma (1 volta al secondo) l'allestimento si posa sulla pianta: palco 5 × 3 m a 40 cm dal muro più lungo senza porte, console 1,6 × 1,6 a 40 cm dal palco, bar 4,6 × 1,4 a 30 cm dal muro più lontano, stand 3 × 3 con passaggi da 1,2 m (la griglia che ne fa entrare di più), 1,5 m liberi davanti a ogni porta. HUD: STAND, PASSAGGI, USCITE. Provato in Python sulla sala del mockup: nessuna sovrapposizione, tutto dentro.
- **Esterno** — `ARWorldTrackingConfiguration` + `sceneReconstruction = .mesh` (+ `sceneDepth`). Il bordo è il giro camminato (chiuso quando si torna entro 1,5 m dalla partenza dopo 6 m; se no l'inviluppo del terreno visto); quote del terreno su celle da 10 cm dalla maglia (superfici orizzontali); dislivello = 98° − 2° percentile; colori veri dall'immagine (YCbCr → RGB come il campione Apple). Modello: plastico con rilievo ×3, prato coi colori veri in TEXTURE.
- **Oggetto** — maglia del LiDAR: si mira l'oggetto al centro (raycast), l'appoggio è il piano orizzontale sotto; l'oggetto è la regione di maglia attaccata al punto mirato (griglia 2 cm). Misure dal rettangolo più piccolo visto dall'alto (1°, poi 0,05°) e dall'altezza sull'appoggio; volume e superficie dalla maglia. FATTO quando le misure sono ferme (± 1,5 cm) e si è girato per almeno metà del giro. Colori veri sui vertici (solo dove la profondità dice che sono visibili). Provato in Python su un flight case ruotato: 80 × 60 × 55 cm, 0,264 m³, 2,50 m².
- **Misura** — piani verticali di ARKit (`planeExtent`, iOS 16+): larghezza e altezza della parete mirata, scritta in arancio sopra l'immagine; SCARTO «±1 cm» fino a 5 m (oltre: «—»). FATTO quando la larghezza è ferma da 1,5 s.
- **Corpo › Postura** — `ARBodyTrackingConfiguration` con stima automatica della scala; 60 campioni in 2,5 s; altezza dagli occhi (93 % della statura), spalle tra le articolazioni + 4 cm, spalle allineate entro 2 cm, bacino = rotazione della linea delle anche. Scheletro ciano sopra la persona; nel risultato fantasma della persona (MakeHuman, alto come lei), scheletro vero, «SPALLE …», «BACINO …° DX/SX», quota.
- **Corpo › Texture** — `ObjectCaptureSession` + `ObjectCaptureView` (rilevamento automatico, scatti automatici dopo 2 s), poi `PhotogrammetrySession` sull'iPhone (`.modelFile`, USDZ con texture). HUD: FOTO dal vivo, GIRO 360° a giro completato.
- Ovunque: niente sensore → riga arancione «SERVE UN IPHONE CON IL LIDAR» (o «… CHE SEGUA IL CORPO»), senza Fine; errori → riga arancione e «Riprova». «Guarda» durante la scansione usa la fotocamera già accesa (in Texture non apre gli Occhi).

## A voce

Le frasi del pannello A VOCE di ogni modo funzionano da casa (aprono LiDAR già sul modo e partono, JARVIS dice la sua frase), da una scheda,
e da dentro LiDAR (cambiano modo; sul risultato dello stesso modo JARVIS dice i numeri: «dimensioni dell'oggetto», «quanto è largo quel muro?»).
«Gemello digitale di Marco» mette il nome sul modello. «Scansiona/misura la stanza», «planimetria» partono in Interno; «apri LiDAR» apre il menu
(«LiDAR, Sir.»). Restano «quanta gente ci sta?», «salva», «fine», «rifai la scansione». Domande vicine («quanto è largo il Po?», «cos'è un gemello digitale?»,
«che cos'è una planimetria?») restano al cervello.

## Controlli fatti

- Sintassi Swift (tree-sitter, `ts/sintassi.sh`): pulita (solo il falso positivo noto di SchedeDaily.swift:165).
- Voce: `casi.py` 1243 frasi, 0 sbagliate; `casi_sezioni.py` 853, 0; `casi_pronunce.py` 853, 0 (con `JARVIS_APP` sul ramo). Nota: un altro agente sta scrivendo negli stessi file di `verifica22` (casi OLOGRAMMA/OCCHI 23): convivono.
- Nomi: nessun tipo doppio nel progetto (iPhone + orologio). `ComandiVocali.swift` è anche nell'orologio: nessun riferimento a tipi solo-iPhone.
- Algoritmi portati 1:1 in Python e provati (`scratchpad/lidarprove/`): allestimento sulla sala del mockup, triangolazione dei pavimenti (L, U, punti allineati, 20 poligoni a caso: aree esatte), scatola/volume/superficie dell'oggetto.
- Isolamento: delegati ARKit `nonisolated` con `MainActor.assumeIsolated` (ARKit consegna sul main), conti pesanti su una coda propria, nessun delegato di SceneKit sul thread di disegno (il giro del 3D è un CADisplayLink sul main).
- Rilette tutte le funzioni nuove; firme verificate sulla documentazione Apple (sotto).

## Da provare sull'iPhone (qui non si può)

Compilazione in Xcode; shader degli ologrammi (stessi costrutti dell'Organismo 22: `scn_frame`, `_surface.view`, più `discard_fragment()` per la materializzazione);
luci e trame in OLOGRAMMA/TEXTURE; sensazione dei tempi «FATTO»; precisione di Postura (altezza e spalle sono stime dello scheletro di ARKit);
Object Capture su una persona (Apple lo pensa per oggetti); esportazione USDZ di Oggetto al Salva (`SCNScene.write`, che Apple documenta per .scn: se non scrive, il Salva tiene i numeri senza il file).

## DA CHIEDERE

1. **TEXTURE di Interno, Setup e Misura**: è la resa del mockup (parquet, intonaco, legno disegnati), perché RoomPlan non dà le foto delle pareti. In Esterno, Oggetto e Texture la texture è vera (fotocamera / Object Capture). Proposta: fotografare ogni parete durante la scansione e usarla come texture vera.
2. **Setup**: fa la sua scansione RoomPlan e posa gli elementi da solo. Il mockup non dice da dove arriva la pianta: in alternativa può usare l'ultima stanza dell'archivio. «Metti il palco qui» oggi avvia Setup: posare il palco nel punto indicato vuol dire una schermata nuova (non nel mockup).
3. **Fine prima del FATTO**: nel mockup «ANCORA UN ATTIMO…» si ripete sempre. Nell'app il secondo tocco chiude con quello che c'è (solo se basta per costruire qualcosa), altrimenti una stanza aperta o un giardino non chiuso non finirebbero mai.
4. **Misura «tra due punti»**: il testo del mockup lo dice, ma il mockup mostra solo la parete. Per i due punti serve toccare lo schermo due volte (schermata da approvare).
5. **Texture, HUD**: Apple non dà né l'altezza né i gradi del giro durante Object Capture. FOTO è dal vivo, GIRO diventa 360° a giro completato, ALTEZZA resta «—» e compare nel risultato. Gli scatti partono da soli 2 s dopo che la persona è inquadrata. Durante l'elaborazione (1-3 minuti) c'è solo «ELABORAZIONE…» come nel mockup: si può aggiungere la percentuale?
6. **Dove si vedono i risultati salvati dei modi nuovi**: si salvano in Documenti › LiDAR (numeri, più il modello USDZ di Oggetto e Texture), ma il mockup non ha una schermata per rivederli (l'ARCHIVIO è solo di Interno).
7. **Chiedi**: manda a JARVIS la domanda del mockup con i numeri veri (es. «… 80 × 60 × 55 cm, volume 0,264 m³. Quanto costa spedirlo con Messina?»). Le domande d'esempio del mockup («portarla a Roma», «250 persone», «Mandami il modello di Marco») erano esempi: vanno bene così?
8. **Sottotitolo dei risultati**: nel mockup «giardino · esempio»; nell'app «esterno · data e ora» (o il nome: «marco · …»).
9. **Esterno sulle facciate**: «rilievo della facciata» parte, ma il calcolo è quello del terreno (superfici orizzontali). Una facciata vera (parete esterna verticale) va trattata come Misura in grande: da decidere.
10. **Spalle**: «Larghezza spalle» è la distanza tra le articolazioni più 4 cm (circa da osso a osso), non la misura da sarto (≈ 46 cm sul dorso): va bene?
11. **Orologio** (proposta, niente fatto): sul polso l'ultima misura di LiDAR (es. «Parete 3,42 × 2,70 m», «Oggetto 80 × 60 × 55 cm») e il tasto «Misura» che avvia il metro sull'iPhone.
12. **Annuncio a voce di «apri LiDAR»**: era «LiDAR pronto. Muova l'iPhone lungo le pareti», ora che si apre sul menu è «LiDAR, Sir.»; ogni modo detto a voce ha la sua frase (es. «Metro pronto. Punti la parete da un capo all'altro, Sir.»).

## Documentazione Apple usata

- ObjectCaptureSession: https://developer.apple.com/documentation/realitykit/objectcapturesession
- PhotogrammetrySession: https://developer.apple.com/documentation/realitykit/photogrammetrysession — Request: https://developer.apple.com/documentation/realitykit/photogrammetrysession/request
- WWDC23 «Meet Object Capture for iOS» (flusso, `.modelFile(url:)`, dettaglio ridotto su iOS, LiDAR + A14): https://developer.apple.com/videos/play/wwdc2023/10191/ (note: https://wwdcnotes.com/notes/wwdc23/10191)
- ARBodyTrackingConfiguration: https://developer.apple.com/documentation/arkit/arbodytrackingconfiguration — ARBodyAnchor: https://developer.apple.com/documentation/arkit/arbodyanchor
- Nomi delle giunture: https://developer.apple.com/documentation/arkit/validating-a-model-for-motion-capture — ARSkeleton.JointName: https://developer.apple.com/documentation/arkit/arskeleton/jointname
- ARPlaneExtent (width, height, rotationOnYAxis, iOS 16): https://developer.apple.com/documentation/arkit/arplaneextent
- SCNGeometryElement (anche da MTLBuffer, punti): https://developer.apple.com/documentation/scenekit/scngeometryelement
- Volumi dei nodi (comprendono i figli): https://developer.apple.com/documentation/scenekit/scnboundingvolume
- SCNScene.write: https://developer.apple.com/documentation/scenekit/scnscene/write(to:options:delegate:progresshandler:)
