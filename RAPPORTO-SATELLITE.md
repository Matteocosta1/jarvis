# SATELLITE · build 23 «MARK IX» — rapporto

Ramo `claude/23-satellite` (già unito con la build 22). Niente merge, numeri di versione e nome «MARK» non toccati.
Non toccati: Occhi.swift, Lidar.swift, Allenatore.swift, Protocolli.swift, la barra in alto e la tastiera.

## In parole semplici

- Nella corona, in INTELLIGENCE, c'è la nuova icona **SATELLITE** prima di Bea (disegnata come nel mockup: il satellite di
  sbieco con i pannelli e le onde). All'avvio le icone sono **27 sull'iPhone e 20 al polso**, sulla musica con un colpo in più.
- **SATELLITE** si apre come le altre schede («Chiudi» in alto): la città 3D di Apple (satellite con il rilievo) con i suoi
  luoghi sulle aste olografiche, la camera che gira piano e vola sul luogo scelto; sotto TUTTI · LUOGHI · LOCALI · PERSONE,
  l'elenco con le distanze, Luogo · Distanza · A piedi · Meteo e i tasti Guida · Naviga · Dossier; poi RICOGNIZIONE e A VOCE.
- **NAVIGA**: il percorso a piedi di Apple a tappe, ogni tappa con la vista da strada di Apple (Look Around) e le frecce.
- **GUIDA**: la fotocamera con le frecce verso la strada da fare, i metri che scendono, JARVIS che dice ogni svolta e
  l'arrivo. Resta attiva anche chiudendo Satellite (negli Occhi la freccia, al polso la guida) finché arriva o lei dice
  «ferma la guida».
- In NAVIGA e GUIDA c'è il **piccolo tasto di scatto** (dietro o davanti): le foto vanno nel **DOSSIER** del luogo.
- **DOSSIER**: la scheda del luogo a tutto schermo con la vista da strada, FOTO · ARCHIVIO (tocco su una foto: grande, con
  Archivia/Ripristina ed Elimina che chiede «Conferma»), Luogo, Distanza, Visite, Note, Foto e Ricorda, Naviga e Guida.
- **Orologio**: SATELLITE con i luoghi e la distanza; un tocco fa partire la guida sull'iPhone e al polso compare la guida
  in corso (freccia, metri, tappa, FINE).
- Le frasi a voce: «Jarvis, satellite», «guidami allo studio», «mostrami la strada per il locale», «ferma la guida»,
  «ricognizione su Via Savona», «mostrami lo studio in 3D».
- Non ho potuto compilare (qui non c'è Xcode): controllato tutto a mano, riga per riga, e con il controllo di sintassi.
  **Va provata in Xcode.** Ci sono alcune scelte da confermare (in fondo, DA CHIEDERE).

## File

Nuovi (iPhone):
- `Untitled Project/Satellite23.swift` — **in comune con l'orologio** (aggiunto alle membershipExceptions del progetto):
  l'icona (`FormaSatellite`/`IconaSatellite`), `AzioneSatellite` (le frasi), `LuogoSat` (i luoghi dal cervello, ricerca
  per nome detto), `GuidaPolsoDati` (la guida che va al polso).
- `Untitled Project/MotoreGuida.swift` — il percorso (`PercorsoSat`, MKDirections), la vista da strada (`VistaStrada`:
  scena e foto di Look Around), il motore della GUIDA (`MotoreGuida`: GPS e bussola, tappa, metri, voce, arrivo, percorso
  rifatto se esce di strada, scrive `GuidaCondivisa`, manda la guida al polso).
- `Untitled Project/Satellite.swift` — la sezione (`VistaSatellite`), la mappa 3D (`MappaSatellite` con l'HUD, le aste e
  LEI), il meteo (`MeteoSat`, WeatherKit), le categorie (`CategorieSat`), le richieste a voce (`RichiestaSatellite`).
- `Untitled Project/SatelliteSchermi.swift` — NAVIGA e GUIDA a tutto schermo, il tasto di scatto, il lampo, Look Around,
  le frecce olografiche.
- `Untitled Project/SatelliteDossier.swift` — le foto dei luoghi (`ArchivioFotoSat`, Documenti › Satellite) e il DOSSIER
  con la foto a grande.

Nuovi (orologio):
- `JarvisOrologio Watch App/SatelliteOrologio.swift` — SATELLITE e GUIDA al polso, `GuidaPolso` (la guida dall'iPhone).

Cambiati:
- `Build22.swift` — `ComandoDedicato.satellite(…)` e `.fermaGuida` (frasi esatte, prima di tutto il resto).
- `ComandiVocali.swift` — `Reparto.satellite` («Satellite, Sir.»), «apri il satellite», «chiudi il satellite».
- `ContentView 2.swift` — icona in INTELLIGENCE prima di Bea, la scheda, l'apertura a voce, la voce della guida.
- `Jarvis 2.swift` — le frasi di Satellite e «ferma la guida».
- `ChatAnimata.swift` — `Avvio.colpi` a 27 (la partitura del mockup 23).
- `SchedeSignore.swift` — la testata della scheda disegna l'icona di Satellite (le altre come prima).
- `Orologio 2.swift` — il ponte: la guida all'orologio e «avvia / ferma / stato» dall'orologio.
- `avvio.m4a`, `avvioorologio.m4a` — le tracce 23 (vedi Controlli).
- Orologio: `VistaOrologio 2.swift` (icona, 20 colpi, molla delle ultime 9, apertura), `SchermatePolso.swift`
  (`.satellite`), `JarvisOrologio 2.swift` (le frasi), `PonteOrologio 2.swift` (la guida dall'iPhone).
- `Untitled Project.xcodeproj/project.pbxproj` — Satellite23.swift anche nel target dell'orologio.
- Prove a voce (fuori dal ramo): `verifica22/riconosci.py` (le stesse regole di Build22.swift), `casi.py`,
  `casi_sezioni.py`, `prova.py` (la scheda «satellite»).

## Il mockup, pezzo per pezzo

| Mockup | App |
|---|---|
| Icona Satellite (SVG) in INTELLIGENCE prima di Bea | `IconaSatellite` (stessi tracciati, archi convertiti), 18 pt nella corona, 22 nella testata, 15 al polso |
| Avvio 27 icone / 20 al polso, COLPI_DOPO, SCAR 9 | `Avvio.colpi` (27), `AvvioOrologio.colpi` (20), molla delle ultime 9 al polso |
| Testata SATELLITE · «pronta», «Chiudi» | `CorniceScheda` come le altre schede |
| Città 3D (three.js), camera a 560 m, 0,92 rad, giro 0,09 rad/s dopo 2,6 s, volo 1,7 s +420 m, dito = giro | `Map` con `.imagery(elevation: .realistic)`, `MapCamera` a 560 m, inclinata 37,3°, stessi tempi; il dito in orizzontale gira, in verticale scorre la pagina |
| Aste olografiche, anello che pulsa, cartellino «STUDIO · 198 m», scelto in arancio, LEI in verde | `Annotation` con `AstaSat` e `PuntoLei` |
| HUD: SATELLITE · 3D, bussola, coordinate e QUOTA, meteo, mirino | `HudSatellite` dalla camera vera (`onMapCameraChange`) e dal meteo vero |
| TUTTI · LUOGHI · LOCALI · PERSONE | `ChipSat`; «Niente in questa categoria.» |
| Elenco luoghi (via · categoria, distanza) | i luoghi salvati (gli stessi di TRACCIA, più le persone) con la distanza vera |
| Luogo · Distanza · A piedi · Meteo | `RigaHUD`; meteo di Apple sul luogo: «14° · niente pioggia per 2 ore» |
| Guida · Naviga · Dossier | `TastoComando` |
| RICOGNIZIONE: indirizzo + Vai, volo, avviso con distanza e meteo | geocodifica di Apple (vicino a lei), luogo «Ricognizione», avviso dopo 1,8 s |
| A VOCE (4 frasi) | `PannelloAVoce` con le 4 frasi (senza la nota «qui sono simulate») |
| NAVIGA: J.A.R.V.I.S. · NAVIGA · STUDIO, bussola, ✕ | `TestaSat`; X nel cerchio |
| Viste 360° per tappa, frecce sul selciato, meta e cartellino | `MKLookAroundViewController` per ogni tappa + `FrecceNaviga` |
| Istruzione, «per 110 m · tappa 1 di 3», miniature delle tappe, A piedi, Mappe · Guida | istruzioni di Apple (italiano), miniature da `MKLookAroundSnapshotter`, Mappe apre Apple Mappe a piedi |
| GUIDA: PER 50 M / poi: …, MANCANO · A PIEDI · TAPPA, la nota, Naviga · Fine guida | stessi testi, dai metri veri lungo il percorso |
| Frecce olografiche, voce a ogni svolta, «Arrivato, Sir», chiusura dopo 4 s | `FrecceGuida` sulla fotocamera (come TRACCIA), `MotoreGuida` |
| Guida attiva a Satellite chiuso (Occhi e orologio) | `MotoreGuida` vive fuori dalla sezione, scrive `GuidaCondivisa` (interfaccia invariata) |
| Scatto: DIETRO/DAVANTI, giro, numero di foto, lampo, «Foto nel dossier di …» | `ScattoSat` + `LampoSat`, foto vere |
| DOSSIER: vista da strada, FOTO · ARCHIVIO, vuoti, Luogo/Distanza/Visite/Orari/Note, Foto · Ricorda, Naviga · Guida | `SchermoDossier` (Orari: vedi DA CHIEDERE) |
| Foto a grande: FOTO · luogo, «GUIDA · DIETRO · ven 23 ott, 21:40», Archivia/Ripristina, Elimina → Conferma (3 s) | `VistaFotoSat` |
| Polso: SATELLITE (4 luoghi con distanza, «Tocchi un luogo: parte la GUIDA») | `VistaSatelliteOrologio` |
| Polso: GUIDA (bussola con freccia, metri, «↱ Via Tortona», FINE ›) | `VistaGuidaOrologio` |
| Frasi VOCI22 (satellite, guidami, mostrami la strada, ferma la guida, ricognizione) | `ComandoDedicato` + `Reparto.satellite`, anche al polso |

## API usate (documentazione Apple)

Lette sulla documentazione durante il lavoro: `MKLookAroundViewController` (init(scene:)/nib, isNavigationEnabled,
showsRoadLabels, badgePosition, scene), `MKLookAroundSceneRequest` (init(coordinate:), init(mapItem:),
getSceneWithCompletionHandler), `MKLookAroundSnapshotter` (+ Options: size; getSnapshotWithCompletionHandler),
`MapStyle.imagery(elevation:)`. Le altre dalla documentazione nota (iOS 17 / watchOS 10, nessuna più nuova):
- https://developer.apple.com/documentation/mapkit/mklookaroundviewcontroller
- https://developer.apple.com/documentation/mapkit/mklookaroundscenerequest
- https://developer.apple.com/documentation/mapkit/mklookaroundsnapshotter
- https://developer.apple.com/documentation/mapkit/mapstyle (imagery(elevation:), Elevation.realistic)
- https://developer.apple.com/documentation/mapkit/map (init(position:interactionModes:content:), Annotation, mapControls, onMapCameraChange, MapCamera)
- https://developer.apple.com/documentation/mapkit/mkdirections (calculate(completionHandler:), Request, .walking, MKRoute.Step)
- https://developer.apple.com/documentation/mapkit/mklocalpointsofinterestrequest + MKLocalSearch(request:)
- https://developer.apple.com/documentation/mapkit/mkmapitem/openinmaps(launchoptions:)
- https://developer.apple.com/documentation/corelocation/clgeocoder (geocodeAddressString(_:in:preferredLocale:))
- https://developer.apple.com/documentation/weatherkit/weatherservice (weather(for:including:), .current, .hourly)
- https://developer.apple.com/documentation/watchconnectivity/wcsession (sendMessage(_:replyHandler:errorHandler:))
- https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- https://developer.apple.com/documentation/uikit/uiimage/preparingthumbnail(of:)

Concorrenza: le risposte di MapKit (completion handler) sono chiuse in blocchi `@Sendable` con i valori in una scatola
`ScatolaSat` (così non c'è il controllo del main actor che farebbe chiudere l'app se Apple risponde da un altro thread);
gli oggetti di MapKit restano vivi finché arriva la risposta. Fotocamera: `MotoreOcchi` di sempre (solo usato, non cambiato).

## Controlli fatti

- Sintassi (tree-sitter) di tutte e due le cartelle: nessun errore nuovo (resta solo il noto SchedeDaily.swift:165).
- Ogni funzione riletta; nomi nuovi controllati: nessun doppione nel modulo.
- Prove a voce (`verifica22`, con JARVIS_APP=questo ramo): **casi.py 1004 frasi, 0 errori** (248 nuove di Satellite,
  incluse le domande vicine che devono restare al cervello: «quanti satelliti…», «guidami», «la guida di Milano…»),
  **casi_sezioni.py 853, 0**, **casi_pronunce.py 853, 0**. «Jarvis, portami al luogo» (TRACCIA) resta com'era.
  Nota: nella stessa cartella lavora anche l'agente della MUSICA (casi.py, prova.py): le mie aggiunte sono in blocchi
  separati; ricontrollate alla fine, ci sono tutte e due.
- Musica d'avvio: i file dell'app sono **identici** (campione per campione, correlazione 1,0) alle tracce 22 dell'app
  preparate il 23 ott (`avvio23/iph26.m4a`, `w19.m4a`); le tracce 23 corrispondenti (`iph27.m4a`, `w20.m4a`: la stessa
  musica allo stesso volume dell'app, con la coda rimontata e un colpo in più) hanno i colpi dello scarico agli stessi
  istanti del mockup 23 (entro 2 ms). Quindi ho sostituito `avvio.m4a` ← iph27 e `avvioorologio.m4a` ← w20.
  Le tracce del mockup (`VAR`/`VARW`) sono le stesse ma al volume del mockup, per questo non le ho usate così come sono.
- Mockup aperto (#23) con Playwright: Satellite, Naviga, Guida, Dossier, foto, conferma: misure, testi e colori presi da lì.

## DA CHIEDERE

1. **Guida a telefono bloccato.** Oggi la guida segue il GPS con JARVIS aperto (anche con Satellite chiuso). Per farla
   continuare a telefono bloccato in tasca (e farla partire dall'orologio con JARVIS chiuso sull'iPhone) serve la modalità
   «Posizione in sottofondo» (Background Modes › Location updates nell'Info.plist): iOS mostra la freccia blu della
   posizione. Il codice è già pronto: si accende da solo se la modalità c'è. La aggiungo?
   (Senza: dall'orologio, con JARVIS chiuso, al polso compare «Apra JARVIS sull'iPhone, Sir: la guida parte da lì.»)
2. **Visite** (il cervello non registra le visite): oggi «N volte · ultima <quando>, con <persona>» = quante cose ha
   salvato lì (entro 60 m), l'ultima e con chi; per la ricognizione «mai». Va bene così o preferisce un'altra fonte?
3. **Note**: l'ultima cosa segnata lì che non è il luogo stesso (una nota, un oggetto, una cosa vista); «—» se niente.
4. **LOCALI e Orari**: LOCALI = Apple Mappe conosce lì (entro 30 m) un bar, un ristorante, un locale notturno, una
   birreria, un'enoteca o una pasticceria (chiesto una volta per luogo e ricordato). Gli **orari** Apple non li dà alle app
   (MapKit non ha gli orari): la riga Orari non compare mai (nel mockup c'è solo per il locale). PERSONE = i ricordi di tipo
   persona o con una persona.
5. **Dove stanno le foto**: sul telefono, in Documenti › Satellite (come l'archivio di LiDAR), non nella Libreria Foto né
   nel cervello. Al posto suo valuterei se vuole anche una copia nella Libreria Foto.
6. **Foto dal DOSSIER** = la vista da strada del luogo (come dice il mockup); **scatto in NAVIGA** = una foto vera dalla
   fotocamera scelta, senza anteprima (sullo schermo c'è la vista da strada); in GUIDA dalla fotocamera accesa
   (davanti: passa un attimo alla frontale).
7. **Ricorda nel DOSSIER**: per la ricognizione (o un indirizzo detto) salva il luogo nei Ricordi con la posizione
   (`luogo_salva`, serve il cervello v108) e le foto passano al luogo salvato; per un luogo già salvato dice «… è già nei
   Ricordi, Sir.». Il cervello non ha un modo per salvare una foto su un luogo: se lo vuole, serve una riga nel cervello.
8. **«Jarvis, salva questo posto con la foto»** (in A VOCE): oggi va al cervello come sempre (salva il posto; la foto
   arriva solo se c'è una foto in quella conversazione). Vuole che scatti lui una foto e la allego?
9. **Campo RICOGNIZIONE**: vuoto, con «Indirizzo» in grigio (nel mockup «Via Savona 20» è un esempio).
10. **Look Around**: Apple non dice alle app dove sta guardando la vista da strada mentre lei la gira col dito: in NAVIGA le
    frecce stanno sullo schermo (dritte, poi la svolta) e la bussola mostra la direzione della tappa. Il marchio «Look
    Around» di Apple resta visibile in alto a destra, sotto l'intestazione (obbligo di Apple).
11. **Mappa 3D**: come il mockup, il dito in orizzontale la gira e in verticale fa scorrere la pagina (niente pizzico o
    spostamento della mappa).
12. **Meteo**: WeatherKit chiede di mostrare il marchio Apple Meteo dove si usano i suoi dati; nel mockup non c'è.
13. **«guidami a …» con un posto che non è tra i suoi luoghi**: JARVIS cerca l'indirizzo (vicino a lei) e guida lì
    (come una ricognizione); se non lo trova: «Non trovo «…», Sir.».
14. **Al polso, a voce**: «guidami a …» fa partire la guida; «mostrami la strada…», «ricognizione…», «… in 3D» aprono
    SATELLITE con l'elenco (sul polso niente 3D né vista da strada).
