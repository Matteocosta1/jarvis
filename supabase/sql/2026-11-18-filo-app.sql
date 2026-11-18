-- 18 nov 2026 · 13.1 (2) · il filo che passa dal Mac al telefono (il signore: «Supabase», scelta del 18 nov)
-- Ogni dispositivo (iphone, mac) lascia qui, a fine turno e quando JARVIS va dietro, le ultime battute della chat (senza quelle
-- delle modalità riservate: Confidente, Profiler, Wiretap) e quello che aspetta il suo sì (un messaggio, una chiamata, il piano
-- in corso). L'altro dispositivo, quando JARVIS si riapre, lo legge e riprende il discorso. Vale 12 ore.
-- Solo la funzione jarvis-filo (service role) legge e scrive: RLS senza regole, come le altre tabelle di JARVIS.

create table if not exists public.jarvis_filo_app (
  dispositivo text primary key check (dispositivo in ('iphone', 'mac')),
  stato jsonb not null default '{}'::jsonb,
  aggiornato timestamptz not null default now()
);
alter table public.jarvis_filo_app enable row level security;
comment on table public.jarvis_filo_app is 'Il filo della conversazione tra iPhone e Mac (ultime battute e sì in attesa), scritto e letto solo dalla funzione jarvis-filo.';
