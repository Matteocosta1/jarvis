-- La notte di JARVIS (25 ott, approvata dal signore): di notte si rileggono le frasi del giorno e si trovano gli impegni detti
-- di passaggio («domani chiamo Matteo»); al mattino il briefing chiede se segnarli, e col sì diventano promesse.

-- Le frasi del giorno: solo quelle del signore (più l'inizio della risposta di JARVIS), mai le modalità riservate
-- (Confidente, Profiler, Wiretap) né la prova generale. Restano al massimo 3 giorni: le cancella la lettura notturna.
create table if not exists public.jarvis_giornata (
  id bigint generated always as identity primary key,
  creato timestamptz not null default now(),
  dispositivo text,
  signore text not null,
  jarvis text,
  letto boolean not null default false
);
create index if not exists jarvis_giornata_letto on public.jarvis_giornata (letto, creato);
alter table public.jarvis_giornata enable row level security;   -- nessuna policy: solo le funzioni (chiave di servizio)

-- Gli impegni trovati di notte, in attesa del sì o del no del signore.
-- stato: proposto (da chiedere) · segnato (diventato promessa) · scartato (ha detto no) · scaduto (nessuna risposta in 2 giorni)
create table if not exists public.jarvis_impegni (
  id bigint generated always as identity primary key,
  creato timestamptz not null default now(),
  giorno date not null,                 -- il giorno (Roma) in cui il briefing lo chiede
  testo text not null,
  persona text,
  quando timestamptz,
  frase text,                           -- la frase detta, per ricordargliela
  stato text not null default 'proposto' check (stato in ('proposto', 'segnato', 'scartato', 'scaduto')),
  ricordo bigint                        -- il ricordo (promessa) creato col sì
);
create index if not exists jarvis_impegni_stato on public.jarvis_impegni (stato, giorno);
alter table public.jarvis_impegni enable row level security;

-- La sveglia notturna: pg_cron alle 2 e alle 3 UTC; la funzione lavora solo quando a Roma sono le 4 (ora legale o solare).
create or replace function public.sveglia_jarvis_notte()
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
begin
  return net.http_post(
    url := 'https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis-briefing',
    headers := public.intestazioni_interne(),
    body := '{"notte": true}'::jsonb,
    timeout_milliseconds := 120000);
end; $function$;
revoke all on function public.sveglia_jarvis_notte() from public, anon, authenticated;

select cron.unschedule('jarvis-notte') where exists (select 1 from cron.job where jobname = 'jarvis-notte');
select cron.schedule('jarvis-notte', '0 2,3 * * *', 'select public.sveglia_jarvis_notte()');
