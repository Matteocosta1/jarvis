# FRIDAY — regole per Claude

App iPhone di Bea, costruita da Alessandro partendo da JARVIS 13.1 (1). Il cervello è su Supabase (progetto «Gestionale Bea Pilates», funzione `friday`). Le scelte su FRIDAY le approva **solo Alessandro**.

- **Ramo di Xcode:** `friday-app`. Se non è chiaro, chiederlo prima di fare push.
- **Version** 1.0; **Build** +1 a ogni consegna (sempre dopo averglielo chiesto). Bea la prova da tester esterna su TestFlight, con un iPhone 16 Pro.
- FRIDAY dà del **tu** a Bea, ha una voce femminile (quelle gratis di Apple: Federica o Alice) e l'aspetto del mockup approvato (artefatto «FRIDAY» di Alessandro su claude.ai): l'app vera deve essere identica al mockup.
- Regola fissa: nelle sezioni che aprono la fotocamera si chiude con l'icona **X nel cerchio**; nelle sezioni senza fotocamera c'è la scritta **«Chiudi»**.
- Privacy: niente foto né dati personali di Bea nei repository pubblici (il carattere di FRIDAY sta nel database, tabella `friday_config`). Quello che Bea dice a FRIDAY non arriva mai a JARVIS né ad Alessandro.
- Il cervello si pubblica solo col suo via. Il codice delle funzioni `friday` e `friday-prova` sta nel repository jarvis, ramo `friday-cervello`; su Supabase ogni funzione importa quel codice a un commit fisso.
- Registro di piano, decisioni e build: `docs/REGISTRO-FRIDAY.md` (aggiornarlo a ogni passo e a ogni build).

## Come si lavora con Alessandro (valido per ogni sessione)

**Prima di fare**
- Prima di modificare il codice: spiegare in parole semplici cosa si vuole fare e aspettare il suo sì. Per una correzione semplice si fa solo quella, senza aggiungere altro.
- Ogni scelta tecnica o di struttura (come dividere sezioni, schermate, file) va chiesta e approvata prima. L'app vera deve essere identica al mockup approvato.
- Mai togliere voci, sezioni, passi o funzioni senza chiederlo. Se un'istruzione si può capire in più modi, chiedere invece di interpretare.
- Design, layout, grafica e suoni li cambia solo lui, su sua richiesta. Le proposte si possono fare, ma non si applicano da sole.
- Proporre sempre la soluzione migliore e più funzionale, non la scorciatoia più veloce. Se una cosa non si può fare (es. limite di Apple), dirlo subito e chiaramente.
- I costi (API, servizi) si dicono subito, con i numeri.

**Git e build**
- Lavorare sempre sul ramo su cui è già Xcode (indicato sopra): niente ramo nuovo per ogni build. A lui basta Integrate › Pull.
- Version e Build li gestisce Claude nel progetto (lui non li tocca in Xcode), ma il numero di build non si alza da soli: prima chiedergli se carica la build e che numero vuole.
- Ogni build va su TestFlight col suo metodo di sempre (Pull + Archive + TestFlight), mai solo col cavo da Xcode. Non proporre metodi diversi senza chiedere.
- Tenere traccia delle build (cosa contengono, quale funzionava) è compito di Claude, non suo.

**Prima di dire "pronta"** — qui (claude.ai/code, Linux) Xcode non c'è, quindi:
1. Ricontrollare a mano ogni file toccato:
   - import espliciti in ogni file: il progetto ha MEMBER_IMPORT_VISIBILITY attivo, senza import il file non compila. In particolare `import Combine` dove si usano `@Published` / `ObservableObject`;
   - nomi ambigui tra framework (es. `MusicPlayer`);
   - codice del thread principale chiamato da closure/blocchi che non girano sul main actor (default MainActor + Approachable Concurrency);
   - tipi scritti in modo esplicito nelle liste di tuple.
2. Zero errori **e zero warning**: anche gli avvisi di Xcode vanno tolti.
3. Lanciare il controllo di compilazione su GitHub: fare il push con **`[compila]`** nel messaggio del commit, poi leggere il risultato del workflow **Compila** (scheda Actions del repo). Consegnare solo se è verde. Ogni controllo consuma minuti Mac di GitHub: usarlo solo quando serve davvero.
4. Mai dire "risolto" se il risultato non è esattamente quello che vuole lui: dire chiaro cosa è fatto, cosa no e cosa va verificato sul telefono.

**Nell'app**
- Animazioni a 120 Hz (ProMotion), fatte bene ma funzionali: zero animazioni inutili.
- Continuità: tutte le sezioni si aprono, si presentano e si chiudono allo stesso modo.
- Titoli di sezioni, schede ed etichette di una sola parola chiara. Diciture leggibili, senza ripetere le stesse parole ovunque. I numeri e i conti stanno scritti a schermo.
- Mockup sempre realistici (funzionamento e animazioni provabili nel mockup) e ottimizzati per ogni dispositivo.

**Skill in `.claude/skills`**
- Si usano per controllare e per segnalare problemi. I loro risultati sono proposte da mostrare ad Alessandro: non si applicano modifiche al codice, e mai al design, senza il suo sì.
