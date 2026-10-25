# Controllo del dialogo: ascolto, interruzioni, voce (25 ottobre 2026)

**Cosa ho guardato.**
- L'app è `S/lidar24` a `3dbab71`: la build 26 più la correzione «app in sottofondo».
  - iPhone e Mac: `Jarvis 2.swift`, `Richiamo.swift`, `Orecchio.swift`, `AscoltoCloud.swift`, `Build22.swift` (la parte `Dialogo`), `Posizione.swift`.
  - Orologio: `JarvisOrologio 2.swift`.
- Il cervello è `S/dcerv`, ramo `claude/decisioni-cervello`.
- Ho letto in sola lettura anche i tempi veri del 24 ottobre nel database, cioè le righe «turno» e «voce» di `jarvis_consumi`.

**Cosa non ho fatto.** Non ho toccato niente: né codice, né commit, né deploy.

**Cosa non ripeto.** Tutto quello che è già nei rapporti di ieri (RAPPORTO-CERVELLO-DIALOGO, DEC-CERVELLO, AUDIT-DIALOGO, RAPPORTO-2) e i valori che lei ha deciso:
- 2 s per l'aggiunta;
- 4 s per il seguito;
- 2 minuti di validità dell'interruzione;
- 2 s di microfono sull'orologio;
- la tabella delle pause;
- «aspetta» → «Mi dica, Sir»;
- la continuità decisa dal cervello, senza parole chiave e senza limiti di tempo.

Nessuna proposta qui cambia queste regole.

---

## In breve

Il dialogo è davvero quasi maturo. Ho trovato **7 difetti veri** e **4 idee**:
- **Linea che cade a metà risposta:** JARVIS ricomincia la risposta da capo e lei la sente due volte (iPhone, Mac e orologio).
- **Sul Mac**, «basta», «muto» o «aspetta» detti sopra la voce di JARVIS possono finire nel cestino come se fossero la sua eco. È una delle sue regole fisse.
- **Sull'orologio** un colpo di tosse, una porta o una voce vicina fermano la risposta e la perdono: «Non ho capito, Sir».
- **In mezzo alla gente**, nei 2 secondi dopo la domanda, la voce di un altro può fermare la risposta sull'iPhone.
- **Fino a 1 secondo perso** a ogni prima domanda dopo una pausa, per aspettare il GPS (iPhone e Mac).

**Prima ancora dei difetti, due cose da sapere:**
1. **Le decisioni del 24 ottobre sul dialogo non sono ancora nella build 26.** I rami `claude/decisioni-watch` (36, 37, 38: errore a metà risposta, telefonate e Siri al polso, Shazam che si ferma subito), `claude/decisioni-watch-23`, `claude/decisioni-22` e `claude/decisioni-23` non sono uniti alla build. Neanche il cervello con le decisioni è pubblicato. Quindi sul polso, oggi, una telefonata a metà risposta non è gestita, anche se è già stata corretta e approvata.
2. **I numeri veri del 24 ottobre** (26 turni):
   - **8 risposte su 26 sono state interrotte** (31%).
   - Prima parola del cervello:
     - Sonnet circa **1,0–1,9 s**;
     - Opus **1,6–13,4 s**: in 4 casi su 6 più di 3,5 s.
   - Primo suono della voce v4 Turbo: **0,24 s** (mediana) e 0,34 s (9 casi su 10).

   **La voce è veloce. Il tempo si perde nel cervello, soprattutto con Opus.**

---

## Classifica

| # | Cosa sentirebbe lei | Dove | Tipo | Lavoro | Rischio |
|---|---|---|---|---|---|
| 1 | La linea cade e JARVIS ripete la risposta da capo | iPhone, Mac, orologio + cervello | **bug** | medio | basso |
| 2 | Mac: «basta», «aspetta» detti sopra JARVIS buttati come eco; frasi mescolate con le sue parole | Mac | **bug** | piccolo | basso |
| 3 | Orologio: un rumore ferma la risposta e la perde | orologio | **bug** | piccolo | basso |
| 4 | Al bar, una voce vicina nei 2 s dopo la domanda ferma la risposta | iPhone | **bug** | piccolissimo | basso |
| 5 | Fino a 1 s in più prima della risposta, per il GPS | iPhone, Mac (orologio 0,3 s) | **bug di tempi** | piccolo | nullo |
| 6 | Va in sottofondo mentre gli parla sopra: al ritorno risponde a una frase vecchia | iPhone | **bug** (caso stretto) | piccolissimo | nullo |
| 7 | Mac: l'interruttore «Risponde a qualsiasi frase» non fa niente | Mac | **incoerenza** | piccolo | da decidere |
| A | Opus a voce: 4–13 s di silenzio prima della prima parola | cervello | idea (dati nuovi) | piccolo | medio |
| B | Due JARVIS rispondono insieme (iPhone + Mac, Mac + orologio) | cervello | idea | medio | basso |
| C | Interruzioni solo dalla sua voce, quando l'impronta c'è | iPhone | idea | medio | medio |
| D | Orologio e Mac: trascrizione e risposta in una richiesta sola | cervello + app | idea | grande | medio |

---

## BUG VERIFICATI

### 1. La linea cade a metà risposta e JARVIS ricomincia da capo

**Cosa sente lei.** Sta camminando e il telefono passa dal Wi-Fi alla rete mobile, o entra in ascensore, mentre JARVIS risponde. JARVIS finisce le frasi che aveva già pronte, poi dice di nuovo tutta la risposta dall'inizio, a volte con parole diverse. Sull'orologio la voce si interrompe e la risposta riparte da capo.

**Perché succede.**
- **iPhone e Mac.** Quando la linea cade, `flussoConRitentativi` (`Jarvis 2.swift:1280-1299`) chiama `azzeraTesto` (`:1301-1305`). Questo svuota la chat e il buffer, ma **non ferma né ricorda la voce già in coda** (`cloud`, `inCoda`, `frasiVoce`, `dettoRisposta`). Poi riprova con lo stesso numero di richiesta.
- **Il cervello** (`index.ts:3985-4002`) a quel punto fa una di due cose:
  - se la risposta era già finita, la rimanda **intera** (`:3994`);
  - se il primo tentativo è finito in «errore», la **rifà da capo** (`:3997`). Succede sempre quando il cervello si accorge che la linea è chiusa: `cancel()` alla riga 4021, poi `segnaEsito({t:"errore"})` alla 4211.
- In tutti e due i casi il testo nuovo passa da `aggiungi` → `accodaVoce` (`:1383-1398`) e viene detto **dopo** le frasi vecchie ancora in coda.
- **Orologio.** `flussoConRitentativi` (`JarvisOrologio 2.swift:863-885`) chiama `zittisci()` e `iniziaFlussoVoce()`: taglia la voce e riparte da zero.
- Il commento dell'app (`Jarvis 2.swift:1183`) promette che «il cervello riconosce la stessa richiesta e non ripete le azioni». È vero solo se la prima risposta era arrivata in fondo. Nel caso «rifatta da capo», gli strumenti del cervello ripartono. Il registro delle azioni nel contesto di solito trattiene il modello dal rifarle, ma non lo garantisce.

**Correzione proposta.**
1. **App (iPhone, Mac e orologio).** L'app ricorda quello che ha già mandato alla voce per quella risposta. Al nuovo tentativo:
   - se il testo che torna comincia allo stesso modo, salta la parte già detta (c'è già `Dialogo.taglio`, `Build22.swift:113`);
   - se è diverso, non lo ricomincia.
2. **Cervello**, per la risposta rifatta: l'app manda insieme al nuovo tentativo quello che lei ha già sentito. Il cervello riparte da lì, esattamente come fa oggi con «continua» (stessa nota, stessa regola del prompt).

**Lavoro:** medio (tre app e una riga nel cervello). **Rischio:** basso. Si tocca solo il caso della linea caduta.

---

### 2. Mac: le parole dette sopra la voce di JARVIS finiscono mescolate o buttate

**Cosa sente lei.**
- Mentre JARVIS parla sul Mac, lei dice «basta» (o «aspetta», «muto») senza «Jarvis». A volte JARVIS **non si ferma**.
- Se invece gli fa una domanda sopra («e a Roma?»), al cervello arriva una frase con dentro **pezzi di quello che stava dicendo JARVIS** («…piove dalle tre e a Roma che tempo fa»).

**Perché succede.**
- Sul Mac il microfono resta acceso mentre JARVIS parla: `aggiornaRichiamo`, `Jarvis 2.swift:538`, «fase != .ascolto».
- La cancellazione dell'eco è spenta apposta (`AscoltoCloud.swift:400`), per non abbassare le altre app.
- Il microfono taglia l'audio a pezzi e un pezzo si chiude solo dopo 0,7 s di silenzio (`AscoltoCloud.swift:212-224`). Le frasi di JARVIS arrivano una dietro l'altra, quindi la sua parola cade **nello stesso pezzo** delle parole di JARVIS.
- In `fraseSentitaMac` il controllo dell'eco viene **prima** di quello del silenzio:
  - `:1679`: `eEco`. Se almeno il 60% delle parole sono di JARVIS, il pezzo si butta (`:1662-1672`).
  - `:1685`: `eSoloSilenzio`.
- Quindi «basta» dentro un pezzo pieno di parole di JARVIS viene buttato. Fa eccezione solo una frase che contiene «Jarvis» (`:1669`).
- Se l'eco è sotto il 60%, la frase passa **intera** a `interrottoAVoce(testo)` (`:1689-1691`), con le parole di JARVIS dentro. L'orologio, per lo stesso problema, toglie l'eco con `Dialogo.togliEco` (`Build22.swift:137`). Il Mac no.
- **In più:** ogni pezzo della voce di JARVIS va alla trascrizione in cloud (`AttesaMac.trascrivi`, `AscoltoCloud.swift:372-389`) e poi viene scartato come eco.
  - È credito ElevenLabs speso per niente.
  - Consuma il tetto di **40 trascrizioni ogni 10 minuti** (`:377`, il commento dice 20). In una conversazione fitta, superato il tetto, le sue frasi **si perdono in silenzio**.

**Correzione proposta.** In `fraseSentitaMac`, prima del controllo dell'eco, si tolgono le parole di JARVIS con `Dialogo.togliEco(testo, detto: dettoMac)`. Poi:
- se resta un ordine di silenzio, JARVIS si ferma;
- se resta altro, è quella la frase dell'interruzione;
- se non resta niente, era eco.

Facoltativo: i pezzi interamente sentiti mentre JARVIS parla, se tornano «tutto eco», non contano nel tetto dei 40.

**Lavoro:** piccolo. **Rischio:** basso (è la stessa funzione già usata dall'orologio).

---

### 3. Orologio: un rumore ferma la risposta e la perde

**Cosa sente lei.** Al polso, mentre JARVIS risponde, lei tossisce, una porta sbatte, un cane abbaia o un amico ride vicino. JARVIS tace, poi scrive «Non ho capito, Sir. Riprovi.» e la risposta non torna più.

**Perché succede.**
- L'orecchio dell'orologio guarda solo il **volume**: più di 8 dB sopra la voce di JARVIS per 0,6 s (`controllaInterruzione`, `JarvisOrologio 2.swift:1239-1248`).
- `interrottoAVoce` (`:1250-1268`) ferma subito la voce **e la richiesta al cervello** (`compito?.cancel()`).
- Dopo la trascrizione si tolgono le parole di JARVIS (`dopoTrascrizione`, `:578`). Se non resta niente, si va nel ramo `else` (`:642-646`): «Non ho capito», e il resto della risposta è perso.
- L'iPhone non ha questo problema: per fermarsi vuole almeno due parole che JARVIS non sta dicendo (`Orecchio.swift:183`).

**Correzione proposta.** Se dopo aver tolto l'eco non resta nessuna parola, non era lei che parlava. JARVIS riprende da dove si era fermato:
- se la risposta era già arrivata tutta, dice da solo le frasi rimaste (`Dialogo.taglio`, come per il punto 1);
- se no, chiede il seguito al cervello come un «continua» (decisione 53).

Niente cambia quando lei dice davvero qualcosa.

**Lavoro:** piccolo. **Rischio:** basso.

**Da decidere:** se preferisce che in quel caso JARVIS resti zitto ma **senza** «Non ho capito», e riprenda solo se lei dice «continua».

---

### 4. In mezzo alla gente: nei 2 secondi dopo la domanda la voce di un altro ferma la risposta (iPhone)

**Cosa sente lei.** Al bar o con la TV accesa: «Jarvis, che ore sono?». Un attimo dopo il vicino dice «sì sì». JARVIS butta la risposta che stava preparando e manda al cervello «che ore sono + sì sì». La risposta arriva più tardi, e a volte storta.

**Perché succede.**
- `Richiamo.swift:310`: la finestra dell'aggiunta (`liberoFinoA`, 2 s, impostata in `Jarvis 2.swift:1098`) lascia passare **qualsiasi** frase, anche di una parola, **senza guardare se intorno c'è confusione**.
- Il seguito dopo la risposta, nella stessa riga, ha invece `!affollato`.
- Lei aveva stabilito: «con gente o TV intorno serve "Jarvis" come sempre». La finestra dell'aggiunta è l'unico punto che non lo rispetta.

**Correzione proposta.** La stessa condizione del seguito: `adesso < liberoFinoA && (!affollato || voceConfermata)`. In mezzo alla gente l'aggiunta vale con «Jarvis» o con la sua voce riconosciuta. In casa, in silenzio, resta tutto com'è.

**Lavoro:** una riga. **Rischio:** basso.

---

### 5. Fino a 1 secondo perso per aspettare il GPS

**Cosa sente lei.** La prima domanda dopo una pausa di oltre 3 minuti, con l'app aperta, parte più lenta: fino a un secondo in più di silenzio.

**Perché succede.**
- `turno` aspetta la posizione **prima** di mandare la domanda al cervello (`Jarvis 2.swift:1176`).
- `Posizione.attuale()` (`Posizione.swift:39-50`) aspetta fino a **1 s** se la posizione ha più di 3 minuti.
- Il GPS si spegne da solo dopo 3 minuti (`:26-28`) e si riaccende solo all'apertura dell'app (`JarvisApp.swift:25`) o proprio in quel momento.
- Sull'orologio l'attesa massima è 0,3 s (`PosizioneOrologio.swift:44`).
- Nel cervello c'è un pezzetto in più: il numero della richiesta si registra (`index.ts:3988`) **prima** delle altre letture, che invece vanno insieme (`:4100`). Sono alcune decine di millisecondi.

**Correzione proposta.**
- Il GPS si sveglia **quando JARVIS comincia ad ascoltare**: in `avviaAscolto`, in `richiamato`, quando lei gli parla sopra. Lei impiega 1-3 secondi a dire la frase, e intanto la posizione è pronta. La domanda non aspetta più.
- Nel cervello, la registrazione del numero si fa insieme alle altre letture.

**Lavoro:** piccolo. **Rischio:** nullo (la posizione arriva come prima, solo prima).

---

### 6. App in sottofondo mentre lei gli parla sopra (iPhone)

**Cosa sente lei.** Caso stretto. Lei interrompe JARVIS parlandogli sopra, poi blocca il telefono o cambia app a metà frase. Tornando, JARVIS può rispondere a quella frase vecchia. È proprio quello che la correzione del 25 ottobre voleva evitare.

**Perché succede.**
- Quando lei parla sopra JARVIS, la frase la raccoglie l'**orecchio** (`Orecchio.swift`), non l'ascolto normale. Lo stato è `.ascolto` (`zittisciPerAscolto`, `Jarvis 2.swift:329-347`).
- `vaInSottofondo` (`:1909-1925`) chiama `fermaAscolto(invia: false)`, che spegne l'ascolto normale. **L'orecchio resta acceso** con la frase a metà e il suo timer (`Orecchio.swift:229`).
- Al ritorno, oppure quando il riconoscimento si chiude (`:232`, `:240-246`), l'orecchio chiama `consegna()` → `interrottoAVoce` → `instrada`, e la frase vecchia va al cervello.

**Correzione proposta.** In `vaInSottofondo`, se l'orecchio sta raccogliendo una frase, si ferma anche lui (`orecchio.ferma()`).

**Lavoro:** una riga. **Rischio:** nullo.

---

### 7. Mac: l'interruttore «Risponde a qualsiasi frase» non ha effetto

**Cosa vede lei.** In Impostazioni sul Mac c'è l'interruttore «Risponde a qualsiasi frase (non solo «Jarvis»)» (`ContentView 2.swift:1542`). Sul Mac parte **spento** (`Jarvis 2.swift:61`), ma il Mac risponde lo stesso a qualsiasi frase detta nella stanza, se non c'è confusione.

**Perché succede.**
- `fraseSentitaMac` (`Jarvis 2.swift:1676-1707`) non legge mai `Impostazioni.ascoltoSempre`. Lo legge solo l'iPhone, in `Richiamo.swift:311`.
- Anche `liberoMacFinoA`, gli «8 secondi di seguito senza Jarvis» (`:1544`), viene impostato ma **non è più letto da nessuna parte**.
- Dalla storia del codice, il Mac «a qualsiasi frase» è stato voluto il 19 ottobre (commit `1410448` e `d417887`). L'interruttore però è rimasto, e oggi mente.

**Proposta.** Due strade, sceglie lei:
- a) il Mac rispetta l'interruttore come l'iPhone: spento = solo «Jarvis», più gli 8 secondi di seguito;
- b) sul Mac l'interruttore si toglie, perché lì vale sempre «qualsiasi frase».

**Consiglio a)**, con il valore iniziale **acceso** sul Mac, così oggi non cambia niente e l'interruttore torna a funzionare.

**Lavoro:** piccolo. **Rischio:** da decidere (cambia cosa sente il Mac solo se lei lo spegne).

---

## IDEE DI MIGLIORAMENTO (servono il suo sì)

### A. Opus a voce: il silenzio più lungo di tutti
**Dati veri del 24 ottobre.**
- Opus, prima parola a 5,9 s, 1,6 s, 3,7 s, 6,0 s, 6,7 s e 13,4 s.
- Sonnet tra 0,9 e 2,7 s.

Il riempitivo («Un attimo, Sir») copre i primi 2 secondi. Dopo, lei sente 2-10 secondi di nulla: è la cosa meno «umana» rimasta.

L'AUDIT di ieri (punto 11) proponeva «Opus a voce con sforzo basso, medio solo per i ragionamenti», in attesa dei tempi veri. **Adesso i tempi ci sono e confermano il problema.** È una scelta su come ragiona e risponde Opus, quindi decide lei.

### B. Un solo JARVIS risponde
**Il caso.** Se ha JARVIS aperto sull'iPhone e sul Mac insieme, una frase la sentono tutti e due e rispondono tutti e due, con due voci.

**Lo stesso con orologio e Mac.** La regola «mentre usa l'orologio l'iPhone sente solo "Jarvis"» (decisione M8) arriva solo all'iPhone, perché l'orologio parla solo con l'iPhone (`Orologio 2.swift:10-16`, WatchConnectivity). Il Mac non lo sa e `fraseSentitaMac` non la controlla.

**Proposta.** Il cervello vede arrivare la stessa frase da due dispositivi a pochi secondi di distanza. Risponde solo il primo, e il secondo tace in silenzio.

**Lavoro:** medio. **Rischio:** basso.

### C. Interruzioni solo dalla sua voce, quando l'impronta c'è
**Il caso.** Oggi, in una stanza tranquilla, con «Ascolto sempre»:
- mentre JARVIS pensa, basta una frase di due parole di chiunque (Bea, un amico) per fermare la risposta (`Richiamo.swift:310-311`);
- mentre JARVIS parla, bastano due parole che non sta dicendo lui (`Orecchio.swift:183`).

L'impronta della sua voce (`VoceDelSignore`) esiste già, ma si usa solo quando c'è confusione.

**Proposta.** Se l'impronta è registrata, per **fermare** una risposta in corso senza dire «Jarvis» serve la sua voce. Per cominciare una conversazione nuova resta tutto come oggi.

**Costo:** circa 0,7 s di controllo prima di fermarsi.

### D. Orologio e Mac: una richiesta invece di due
**Il caso.** Al polso e sul Mac la frase fa due giri:
1. l'audio va alla trascrizione;
2. il testo torna e riparte verso il cervello.

L'orologio, in più, usa una funzione a parte (`jarvis-ascolto`). Il Mac è già passato al cervello, «mezzo secondo invece di 7-8» (`AscoltoCloud.swift:139`).

**Proposta.**
- **Subito, piccolo:** l'orologio trascrive anche lui dal cervello, che è già sveglio.
- **Poi, grande:** l'audio va direttamente nella richiesta della risposta. Il cervello rimanda prima il testo trascritto e intanto pensa. Se l'app vede che è un comando suo («apri il meteo»), chiude la linea, e con la decisione 4 il cervello si ferma senza spendere.

**Guadagno stimato:** da mezzo secondo a un secondo per frase al polso. Da misurare.

---

## Controlli fatti

- **Lettura riga per riga** delle funzioni del dialogo:
  - iPhone e Mac: `Jarvis 2.swift` (tutto), `Richiamo.swift`, `Orecchio.swift`, `AscoltoCloud.swift`, `Dialogo` in `Build22.swift`, `Posizione.swift`, `Orologio 2.swift` (OrologioInUso);
  - orologio: `JarvisOrologio 2.swift`, la parte del dialogo (righe 40-1310), e `PosizioneOrologio.swift`;
  - cervello: il gestore del turno (`index.ts:3769-4232`), `chiamaClaude*` (2961-3161), il filo (2469-2575), l'archivista (2584-2632), il prompt VOCE E STILE / LUNGHEZZA / TONO (46-52) e `jarvis-ascolto`.
- **Storia del codice** (git) per capire se il comportamento del Mac era voluto (punto 7).
- **Rami delle decisioni:** `git merge-base --is-ancestor` dice che `decisioni-watch`, `decisioni-watch-23`, `decisioni-22` e `decisioni-23` **non** sono dentro `3dbab71`.
- **Database, sola lettura:**
  - `jarvis_consumi`, servizi `turno` (26 righe del 24 ottobre, 8 «interrotto») e `voce` (112 frasi v4 Turbo, primo suono mediana 245 ms);
  - nei log di ieri sera, nessun uso dell'orologio da misurare.
- **Cosa non si può provare qui.** I punti 1-6 sono dimostrati seguendo il codice. Nessuno è stato provato a voce su un dispositivo, perché qui non ci sono iPhone né Xcode. Il punto 2 dipende da come il Mac taglia i pezzi di audio. Il punto 6 dipende da cosa fa iOS al microfono in sottofondo. Tutti e due vanno confermati dal vivo, con le prove qui sotto.

## Cosa provare (dopo le correzioni)

1. **Linea caduta.** Una domanda con risposta lunga, poi a metà risposta si stacca il Wi-Fi. JARVIS finisce la frase e continua da lì, senza ripetere l'inizio. Stessa prova al polso, in modalità aereo.
2. **Mac.** Mentre JARVIS parla, dica solo «basta»: si ferma. Dica «e a Roma?»: in chat compare solo «e a Roma?», senza pezzi della risposta.
3. **Orologio.** Mentre JARVIS risponde, tossisca o batta una mano sul tavolo: JARVIS continua, oppure riprende da dove era.
4. **Bar o TV ad alto volume.** «Jarvis, che ore sono?», poi qualcun altro parla subito: JARVIS risponde all'ora.
5. **Dopo 5 minuti di pausa con l'app aperta:** «Jarvis, che tempo fa?». La risposta parte come le altre, senza il secondo in più.
