# JARVIS — the owner's 54 decisions (approved 24 Oct 2026, 19:03) and who implements them

S = /tmp/claude-0/-home-claude/639e17db-50d1-51b7-9272-dcff04cbeaa8/scratchpad

Read first: `S/controllo/BRIEF-COMUNE.md`. Its context, rules and tools stay valid. Two things changed since it was written:
- the builds are now `claude/build-22` (8.0 (22)) and `claude/build-23` (9.0 (23));
- the brain v108 is live (`main`), with the voice `ELEVENLABS_MODELLO=eleven_v4_turbo` already on.

These decisions are APPROVED. Implement exactly what they say, nothing more. If something is technically impossible or ambiguous, stop on that item, explain it in the report under DA CHIEDERE, and continue with the others. Do not raise version or build numbers. Do not deploy.

**Do not touch the items marked «resta così» / «già fatto» / «dopo».** They are listed only so you know about them.

## Already done or nothing to do
1 numbers (done) · 3 test functions off (done) · 2 tones: `VOCE_TONI=on` later, by the coordinator
7–11 dialogue values stay as they are · 20, 22, 25, 30, 31, 32, 35, 40, 46 stay as they are
23 big LiDAR additions: later, in a separate build · 49 mockup placeholder sections: later

## BRAIN (worktree S/dcerv, branch claude/decisioni-cervello, from `main` = live v108)
- **4.** After an interruption the brain stops at once: when the app closes the line (the stream's `cancel()` / `staccato` flag), no new Claude round starts. That means no further `chiamaClaude` in the loop and no client hand-off. The current call is already aborted.
- **5.** Spoken explanations: at most 5–6 sentences. The long version only if he says «nei dettagli», «spiegami bene» or «nel dettaglio». Put this in the LUNGHEZZA paragraph; this paragraph only, together with the existing «in breve» = 3 sentences rule.
  - Texts the owner asks for (a post, an email, a proposal) stay complete; keep that rule.
  - The confidente and the diario keep their own rules.
- **13.** Briefing notification title: «Buongiorno, Sir» instead of «Buongiorno, signore» (in `jarvis-briefing`, and anywhere else this title is built).
- **27.** In Occhi, never people's names, not even famous people. Fix the prompt line that tells it to recognise «persone note». Keep the Profiler rules unchanged.
- **50.** Mail with an uncertain send: JARVIS says clearly «Non so se è partita, Sir: in Inviata non la vedrà.» Use this phrase or the closest natural wording, wherever an uncertain send is reported.
- **51.** Resending an uncertain mail: after 10 minutes it can be resent with an explicit yes («sì, rimandala»). Today the key stays «incerto» forever.
- **52.** Memory over 80 facts: load the 80 most RECENT first, not the oldest. Meaning-based search still adds the relevant older ones.
- **53.** «Continua» after an interruption resumes with the SAME model as the interrupted answer, not the backup.
- **54.** Confidente, Profiler and Wiretap turns are also skipped by the conversation-thread summary (`filo`), as they already are by memory (`NON_MEMORIZZARE`, `senzaNoteApp`).
- **Bonus (approved as a safety fix):** `completaVettori` must never exceed the 2 s CPU limit. Add a time budget, about 700 ms of work, then stop and continue at the next turn. Today 12 embeddings after a turn can exceed it, and the worker dies with «CPU Time exceeded».

Run `S/cervtest/tutte.sh` and `S/tscheck/check.sh`, and add `prove_*.ts` for 4, 51, 52, 53, 54 and the time budget. Report: `S/controllo/DEC-CERVELLO.md`.

## iPHONE build 22 level, also in 23 (worktree S/d22, branch claude/decisioni-22, from claude/build-22)
- **12.** «Prova la voce» in Settings says «Buonasera, Sir.» instead of «Buonasera signore.».
- **15.** The PROTOCOLLI pull-down sheet closes by itself when JARVIS opens a screen by itself (Occhi, browser, Interprete, Bea's SOS, any fullScreenCover or sheet), and after «Jarvis, chiudi». This already happens for sections opened by voice.
- **16 (part 1).** Small iPhones only (375-point width: SE, mini). The top bar with the keyboard open must fit: J.A.R.V.I.S. never wraps or touches the icons. No change on 393 points and wider (his 15 Pro). Use size-based adaptation, not device names.
- **45.** Ricordi › ULTIMI: the date on the right stays on ONE line (`RigaHUD`). Shorten or scale the date if needed; the left text truncates instead.
- **43 (app side).** If the app shows JARVIS's spoken line (🔊 / caption) over section titles, the way the mockup did, it must sit BELOW the titles and never cover text. Check every section; if the app never overlaps, write that.

Report: `S/controllo/DEC-22.md`.

## WATCH (worktrees S/dw = claude/decisioni-watch from build-22 for 36–38; S/dw23 = claude/decisioni-watch-23 from build-23 for 39)
- **36.** iPhone-only sections: «… vive sull'iPhone, Sir.» is also SAID aloud, not only shown.
- **37.** The watch's sounds must no longer change the audio session or category while JARVIS speaks or listens, so with the Watch on silent his voice is never muted. Change only the audio channel handling, not any sound.
- **38.** Bring three iPhone dialogue fixes to the wrist:
  - (a) when an error arrives mid-answer, keep the part already said;
  - (b) handle incoming calls and Siri: audio interruptions, end and resume correctly;
  - (c) Shazam stops at once on a tap.

  Look at how the iPhone does each one (`Jarvis 2.swift`) and mirror it.
- **39 (23).** A guide started from the wrist when the iPhone finds no route: show and say an explanatory sentence (no route / no position), not «Nessuna guida».

Report: `S/controllo/DEC-WATCH.md`.

## iPHONE build 23 only (worktree S/d23, branch claude/decisioni-23, from claude/build-23)
- **16 (part 2).** NAVIGA in landscape on 375-point phones: nothing cut (about 14 points too many today). No change on 393 points and wider.
- **17.** Satellite guide with the phone locked: add Background Modes › Location updates to the app's Info.plist (`UIBackgroundModes` with `location`) and enable the code path that the Satellite agent said is ready («si accende da solo se la modalità c'è»). Check `allowsBackgroundLocationUpdates` and `showsBackgroundLocationIndicator`, the blue arrow. Check that the radar «Sempre» location still works.
- **18.** The location permission text (`NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription`) also mentions the walking guide, not only the weather. Italian, short, «Sir» style like the other permission strings.
- **19.** Apple Weather attribution (WeatherKit requirement): a small Apple Weather mark and legal link wherever WeatherKit data is shown (Satellite, and check Meteo/Radar if they use WeatherKit). Follow Apple's attribution rules (`WeatherService.shared.attribution`), small, JARVIS style.
- **21.** The guide arrow in Occhi reads «↱ VIA TORTONA · 80 m», as in the mockup: add the street name to `GuidaCondivisa` (Satellite side) and use it in Occhi. Fall back to today's text when there is no street name.
- **24.** LiDAR Texture: show the progress percentage during «ELABORAZIONE…» (Object Capture gives progress).
- **26.** Occhi MANUALE: remove the viewfinder (corners, grid, scan line), as in the mockup #23.
- **28.** «Modalità ologramma» said inside the Trainer answers «Ologramma, Sir.».
- **29.** CERCA sources are tappable and open in JARVIS's browser.
- **33.** «APPLE MUSIC · LOSSLESS» follows the real quality of the song (Lossless / Hi-Res Lossless / Dolby Atmos). Plain «APPLE MUSIC» when unknown.
- **34.** Apple Music not answering: the OGGI page shows a clear sentence instead of staying empty. Use the same style as the existing orange permission/subscription box.
- **41.** The Satellite DOSSIER closes with the word «Chiudi», because it is not a camera view (the owner's close rule). Same position top right.
- **42.** 3D labels (NAVIGA, GUIDA, 3D map) never get cut by the screen edge: clamp them inside.
- **44.** The app's main ring in 23: if the 5 INTELLIGENCE icons touch or nearly touch (Satellite added), space them evenly, the same as the other groups. Measure it on 375/393/430-point widths.

Report: `S/controllo/DEC-23.md`.

## MOCKUP (file S/jarvis-mark7.html; copy before edits: S/jarvis-mark7.html.pre-decisioni)
- **14.** The build 22 view (no hash) shows the build 22 app: Trainer with Specchio (Busto · Mani · Ginocchia · Specchio), Occhi WITHOUT the ETICHETTE · OLOGRAMMA · CERCA icons (as in 22), no Ologramma. The #23 view stays as it is. Use git history and the mockup backups (`S/jarvis-mark7.html.bak-*`, `pre-*`) to restore the 22 parts. Do not change #23.
- **41.** The Satellite Dossier closes with «Chiudi» (same position).
- **42.** 3D labels clamped inside the screen.
- **43.** JARVIS's spoken line (🔊 «…») sits below the titles, never over text.
- **44.** The #23 ring: the 5 INTELLIGENCE icons spaced like the others.
- **45.** Ricordi › ULTIMI date on one line.
- **47.** Remove the dead test chips «COMANDI · PRONTI / MANCANTI».
- **48.** Fix all of these:
  - «BUILD 22 · POLSO», «BUILD 22 · A VOCE» and «Le 19 icone» in the #23 view (they become 23 and 20);
  - «PRIORITÀ · 3» on the watch shows 3;
  - CERCA pauses the sample footage while the sheet is open;
  - the Scanner subtitle after a product is found;
  - the contrast of the Naviga button.
- **Mirror the approved app changes that show on screen:**
  - 12: «Buonasera, Sir.»
  - 15: the sheet closes
  - 21: the arrow text
  - 24: Texture percentage
  - 26: no viewfinder in Occhi manuale #23
  - 28: «Ologramma, Sir.»
  - 29: sources tappable
  - 33: quality label
  - 34: Apple Music error sentence
  - 36: watch says «vive sull'iPhone»
  - 39: watch guide error sentence
  - 13: «Buongiorno, Sir» where the mockup shows the briefing notification
- Run all the Playwright tests (S/t*.js, server http://127.0.0.1:8765) and add tests for the new behaviour.

Report: `S/controllo/DEC-MOCKUP.md`.
