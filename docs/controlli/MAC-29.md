# Mac, build 27 → 29: perché ascoltava male e cosa è cambiato (25 ott 2026)

Dati della prova del signore (25 ott, 02:48–02:50 ora italiana), letti da `jarvis_arbitro`, `jarvis_consumi`, `jarvis_filo` e dai log delle funzioni.

## Cause
1. **Turni fantasma (richiesta unica sul Mac).** Quando l'app scarta la frase trascritta dal cervello (eco, «Jarvis» da solo, interruttore), chiude la richiesta, ma il cervello non se ne accorge (segna `staccato` solo quando prova a scrivere) e chiama Claude lo stesso. Con la strada di prima, la stessa frase partiva una seconda volta → due risposte («…muto…», 01:49:38–39 UTC). L'arbitro confronta solo dispositivi diversi, quindi lo stesso Mac vinceva due volte.
2. **Il controllo d'ingresso del giro unico era sbagliato** (`AscoltoCloud.swift`, `!eco.candidato`): «non candidato» non vuol dire «senza JARVIS dentro».
3. **Il tetto delle 40 trascrizioni ogni 10 minuti** si consumava con l'eco di JARVIS (il rimborso valeva solo per i pezzi «candidati», quasi mai): finito il tetto il Mac buttava in silenzio anche le frasi del signore.
4. **La soglia dell'eco non si imparava quasi mai** (`segnaEco` azzerava `segDurante` anche nel silenzio dopo l'ultima parola di JARVIS): il «basta/muto» sopra la sua voce restava incollato alla sua frase.
5. **JARVIS che dice «basta», «aspetta» in una risposta**: risentita dal Mac, `haParolaDOrdine` impediva di trattarla come eco.
6. **Rumori e voci lontane** («giardibisi», «ci devi smiriciare via»): il microfono del Mac è senza elaborazione vocale (scelta, per non abbassare le altre app); il pezzo partiva già a 0,006 RMS; con «Risponde a qualsiasi frase» acceso ogni pezzo diventava una domanda.

## Correzioni nella 29 (scelte del signore, 25 ott ~03:00)
- `Jarvis 2.swift`: `giroUnicoMac = false` → sul Mac la frase fa due passi (testo + controlli dell'app, poi risposta). Orologio e iPhone invariati.
- `AscoltoCloud.swift`: ogni pezzo risultato eco esce dal tetto; `segnaEco` azzera `segDurante` solo con voce mentre JARVIS tace; soglia d'inizio del pezzo `max(fondo*4, 0,009)` con almeno 0,3 s di voce chiara (la fine frase segue ancora la soglia di prima).
- `Build22.swift`: `Dialogo.eFraseDiJarvis` (3+ parole di fila sue = eco anche con una parola d'ordine dentro), `Dialogo.togliEcoDentro` (toglie pezzi di 4+ parole sue anche in mezzo; mai le parole d'ordine).
- `Jarvis 2.swift` `fraseSentitaMac`: «… Jarvis muto» vale anche con altro davanti; mentre JARVIS parla, una parola sola che non sia un ordine né «Jarvis» non lo ferma.

## Non fatto (deciso dal signore)
- **Cervello non toccato**: «quello di adesso funziona benissimo, non voglio che cambiandolo per il Mac crei problemi all'iPhone». Proposte rimaste nel cassetto: (a) `req.signal` abort → `staccato` subito (servirebbe all'orologio, che usa ancora la richiesta unica e può generare turni fantasma sui suoi comandi); (b) arbitro: stesso dispositivo, stessa frase → una sola risposta.

## Da chiedere / da guardare
- La soglia d'inizio (0,009) è prudente ma non misurata sul suo Mac: se non lo sente parlando normale, abbassarla (riga di controllo sotto il reattore: «livello N / silenzio M»).
- Indicatore «ti sto ascoltando» sul Mac (lui: «non riesco mai a capire sul Mac se mi stai ascoltando»): oggi sotto il reattore c'è «IN ATTESA» e una riga grigia piccola («● in ascolto» / «◉ sento» · livello · frasi · ultima frase). Proposta di design da portargli e far approvare prima di toccare.
- Orologio con la 26: 3 trascrizioni su 5 in 9–20 s con lo stesso testo di 53 caratteri (probabile allucinazione del trascrittore su audio senza voce), microfono che «si accende e spegne a caso». Con la 28/29 il polso usa la trascrizione del cervello: verificare dal vivo.
