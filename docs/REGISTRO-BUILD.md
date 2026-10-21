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

Punto fermo: la conversazione era perfetta prima della modifica del volume (403ce34, 20 ott 21:40).
Dopo la 8.0 (5), se il dialogo va, si rimettono uno alla volta: volume all'avvio, comandi LiDAR/Sentinella/Wiretap,
comandi Allenatore/Interprete/rapidi — una build per pezzo, provata ogni volta.
