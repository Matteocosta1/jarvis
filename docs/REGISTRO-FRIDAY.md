# FRIDAY — registro

## Nascita
- 13 nov 2026: FRIDAY nasce da JARVIS 13.1 (1) — repository jarvis, ramo `claude/build-23`, commit `414fc09` (compilazione verde: 0 errori, 0 warning, run 43520023823). Dentro c'è già il dialogo nuovo di JARVIS (si ferma solo per una voce vera, filo del discorso), Salute con l'iPhone bloccato e l'avvio dal tasto Azione.
- Prima compilazione verde il 13 nov: commit `6d4381b`, run 43523299661 (0 errori, 0 warning).
- Scelte di Alessandro (13 nov): copia dell'ultima JARVIS verde · Bea tester esterna su TestFlight · si lavora sul ramo `friday-app` del repository jarvis (pubblico: compilazioni gratis), senza foto né dati di Bea; alla fine tutto passa nel repository privato «friday» · via dall'app le sezioni di JARVIS che nel mockup non ci sono.

## Piano
1. **Nascita** — un solo target, l'app iPhone «FRIDAY» (`it.discosizer.friday`, 1.0 build 1). Via Apple Watch, complicazione e Isola; poi via le sezioni che sono solo di JARVIS: Cuore, Briefing, Meteo, Shazam, Browser, Serata, LiDAR, Sentinella, Profiler, Wiretap, Satellite, Bea, Sistemi (GitHub, Supabase, Archivio, Costi), Impostazioni, Studio e Social (il codice che serve ad altro, es. l'SOS della sezione Bea, si riusa). Prima compilazione verde.
2. **Aspetto** — come il mockup: arancio e rosso, il «tu», i suoni di FRIDAY, i cinque gruppi della corona, l'icona (da approvare).
3. **Cervello e voce** — la funzione `friday` portata alla v135 di JARVIS (pubblicata solo dopo la prova), la parola d'ordine nel Portachiavi, la voce femminile di Apple.
4. **Sezioni** — tutte quelle del mockup (tabella sotto).
5. **Consegna** — 0 errori e 0 warning, confronto con il mockup, build 1.0 (1) su TestFlight per Bea.

## Fase 1b: via le sezioni solo di JARVIS (14 nov)
- Tolti i file di LiDAR (con il suo 3D), Sentinella, Profiler, Satellite (con Travel e la guida), Bea (scheda e SOS), Browser, Meteo, Briefing, Cuore, Shazam (la scheda), Serata, Sistemi (GitHub, Supabase, Archivio, Costi), Impostazioni, Studio e Social (con le sessioni del post), Isola e Apple Watch (il lato iPhone). Del Wiretap resta solo la dettatura, che usano i Messaggi.
- Tolti anche i loro comandi a voce, le battute, le destinazioni della regia, le icone e le notifiche (SOS di Bea, radar pioggia).
- Spostati dove servono ancora: `Voce` e `URL: Identifiable` (SchedeSignore), `AngoliOlo` (Ologramma), `ChipSat` (Ricordi), le curve di salita e discesa `StratoPagina` (PaginaPiena).
- Resta `Studio3D/three.module.min.js`: lo usa l'aereo olografico degli Occhi (AEREO).
- Il primo avvio aspetta la parola d'ordine, che in JARVIS si scrive in Impostazioni: in FRIDAY arriva in fase 3, col cervello.
- L'SOS della sezione Bea di JARVIS (`Bea.swift`, commit `414fc09`) si riprende per l'SOS di FRIDAY (fase 4).
- Codice rimasto ma non più usato, da togliere in un secondo passo: i banchi di prova degli ologrammi delle sezioni tolte (BancoProveOlo, ProveTavolaA/B/C/Viste, OlogrammiSezioni, i loro casi in SezioneOlo), GuidaCondivisa, i campi video di AscoltoShazam, alcune parole in Vocabolario, OrecchioComandi e Abitudini, l'elenco dei banchi in `prova.yml`.

## Sezioni: da JARVIS a FRIDAY
Corona del mockup: SENSI (Occhi, Foto, Frigo, Cucina, Scanner) · CORPO (Pilates, Makeup, Vitals, Sonno, Ciclo, Testa) · CONTATTI (Mail, Messaggi, Telefono, Interprete) · STRUMENTI (Gestionale, Armadio, Nando, Spesa, Musica) · MENTE (Diario, Confidente, Memoria). In alto: Musica, Cestino, Difesa, Account, SOS.

| FRIDAY | Da JARVIS |
|---|---|
| Occhi, Foto, Scanner, Vitals, Sonno, Messaggi, Telefono, Interprete, Spesa, Musica, Diario, Confidente, Cestino, Protocolli, chat | le stesse, rifatte per Bea |
| Frigo e Cucina | Cucina |
| Pilates | Trainer (Allenatore) |
| Mail | Email |
| Memoria | Ricordi |
| Difesa | EDITH |
| Armadio (Capi, Prova vera · bozza · ologramma, Vinted, Conti), Ciclo, Makeup, Testa, Gestionale, Nando, Account, SOS | nuove |

## Cervello
- Supabase, progetto «Gestionale Bea Pilates» (`xqayklmnglhldeutepqw`).
- `friday`: il cervello di JARVIS (v130) adattato a Bea. Codice: jarvis@`friday-cervello`, `supabase/functions/friday/index.ts` (commit `ffc4a65`). Il carattere sta in `friday_config` (`sistema`), la parola d'ordine in `friday_config` (`token`), intestazione `x-friday-token`.
- `friday-prova`: prova vera dei capi e capi dalle foto (Gemini per le immagini, Claude Haiku per riconoscere i capi). Codice: jarvis@`friday-cervello`, `supabase/functions/friday-prova/index.ts` (commit `6bce825`).

## Build
| Build | Data | Contenuto | Esito |
|---|---|---|---|
| — | 13 nov | Fase 1: il progetto FRIDAY (solo iPhone), codice identico a JARVIS 13.1 (1) | verde (run 43523299661) |
| — | 14 nov | Fase 1b: via le sezioni solo di JARVIS | da compilare |
