# Cervello di JARVIS (Supabase Edge Functions)

Progetto Supabase `axalouhijcsizqgnneco`. Le chiavi NON stanno qui: sono nei segreti di Supabase
(ANTHROPIC_API_KEY, JARVIS_TOKEN, ELEVENLABS_API_KEY, GITHUB_TOKEN, JARVIS_SUPABASE_TOKEN, …).

- `jarvis` — il cervello: conversazione, strumenti, voce, schede GitHub/Supabase/Archivio
- `jarvis-ascolto` — trascrizione audio (orologio)
- `jarvis-allarme` — allarmi e avvisi
- `jarvis-briefing` — briefing del mattino, diario della sera, promesse (notifiche push)
- `jarvis-deploy` — pubblica una funzione a pezzi dalla tabella `jarvis_deploy_parti`
