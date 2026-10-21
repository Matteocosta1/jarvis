# JARVIS — registro delle build

Version e Build li tiene Claude su GitHub: Alessandro fa solo Pull e Archive.
Per ogni build: cosa contiene, se è stata provata, com'è andata.

| Build | Commit | Contenuto | Provata | Esito |
|---|---|---|---|---|
| 8.0 (1) | def427f | MARK VIII + comandi vocali di oggi + microfono «mai sordo» | sì | ✗ dopo la risposta non sente più (serve il reattore) |
| 8.0 (2) | 0a77723 | + guardia sul microfono | no (mai caricata) | — |
| 8.0 (3) | 0485044 | microfono dell'attesa come il 20 ott mattina | sì | ✗ stesso problema |
| 8.0 (4) | aa10955 | + audio normale a fine avvio | no | — |
| 8.0 (5) | e5a8f48 | **tutta l'app come il 20 ott alle 20:57** (b0ebe03), subito prima della modifica del volume all'avvio; solo nome MARK VIII e numeri | | |
| 8.0 (6) | 1b75d6d | 8.0 (5) + musica d'avvio +2 dB (solo il file, nessuna modifica all'audio dell'iPhone) + comandi vocali di stamattina: LiDAR (microfono acceso, fine/misure/capienza/salva/3D), Sentinella, Wiretap, «traduci in inglese» (anche Watch), Allenatore, Interprete, comandi rapidi. Microfono e conversazione: come 8.0 (5) | da provare | |
| 8.0 (7) | 2ed4221 | **identica a ieri sera, Build 20 con LiDAR (b0ebe03, 20 ott 20:57)**, scritta MARK VII-5.0 compresa: cambia solo il numero di build. Annulla tutto quello fatto oggi (comandi, volume, microfono) | da provare | |
| 8.0 (8) | 0cc3062 | 8.0 (7) + **solo** menu SISTEMI: le 4 richieste partono insieme; se il menu si chiude prima della fine non scrive più «non raggiungibile». Nient'altro | da provare | |
| 8.0 (9) | 184b524 | 8.0 (8) + tre ritocchi: «piano/sottovoce» entro le prime 5 parole (prima 3); volume basso anche sulle frasi già pronte (piano dalla prima sillaba); battito di mani valido sempre (tolta la regola dei 12 s di «confusione», che scartava i primi battiti dopo voce o musica) | da provare | |
| 8.0 (10) | 776d618 | 8.0 (9) + **solo** LiDAR: «guarda» durante la scansione prende la foto dalla fotocamera di LiDAR (niente Occhi, la scansione non si ferma e non va al nero); fuori da LiDAR «guarda» resta come prima | da provare | |
| 8.0 (11) | 2aece20 | 8.0 (10) + **voce ovunque**: «Jarvis» ascolta in schede, Occhi, Cucina, LiDAR, Impostazioni, SISTEMI, Browser, Vitals, Confidente, Ricordi (no: Interprete, Allenatore, Sentinella, Wiretap, Shazam, Scanner, Profiler, La mia voce). Comandi: «apri sistemi/impostazioni/costi/EDITH», «pulisci» (frasi esatte), «chiudi»/«torna»/«indietro» (da soli). Occhi e Cucina: la frase fa scattare e parte con la foto. Browser: «scrivi …», «invia». Watch: «pulisci». I 50 ms NON inclusi (la musica resterebbe abbassata). Menu SISTEMI: ultime righe ricordate e mostrate subito, aggiornate in sottofondo e già 8 s dopo l'avvio; cervello: registri e piano voce letti in parallelo | da provare | |
| 8.0 (12) | (questo commit) | 8.0 (11) + **comandi vocali dentro le sezioni**, con tante frasi naturali: quelli di stamattina mai provati davvero (LiDAR, Sentinella, Wiretap, «traduci in…», Allenatore, Interprete, comandi rapidi) e in più Diario, Confidente (incolla e commenta il messaggio copiato), Vitals, Cuore, Sonno, Meteo, Briefing, Posta, Spesa, Ricordi, Bea, Occhi/Cucina («in video»), Profiler e Scanner (ascolto proprio, «Jarvis, …»), Browser e Google (cerca, scrivi, cancella, indietro/avanti, scorri). Aprire/chiudere in più modi. Niente «cancella/elimina» dei dati a voce. EDITH con tutte le storpiature. «Riprova la scansione» in LiDAR. Battito di mani ignorato con la tastiera aperta. SISTEMI: niente scritte d'errore, solo dati buoni. Google: scrittura nella casella. Cervello invariato | da provare | |

Nota 21 ott pomeriggio: fotocamere bloccate in tutte le build (anche la 6.0 (20) di ieri) → era l'iPhone; risolto col riavvio.

Punto fermo: la conversazione era perfetta prima della modifica del volume (403ce34, 20 ott 21:40).
Dopo la 8.0 (5), se il dialogo va, si rimettono uno alla volta: volume all'avvio, comandi LiDAR/Sentinella/Wiretap,
comandi Allenatore/Interprete/rapidi — una build per pezzo, provata ogni volta.
