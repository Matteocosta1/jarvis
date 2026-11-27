-- 27 nov · INSTAGRAM, L'AVVISO SUBITO: cosa è già stato visto, i follower di chi commenta, i commenti per post (solo server).
create table if not exists public.jarvis_ig_visti (chiave text primary key, creato timestamptz not null default now());
create table if not exists public.jarvis_ig_profili (username text primary key, follower integer not null default 0, aggiornato timestamptz not null default now());
create table if not exists public.jarvis_ig_post (id text primary key, commenti integer not null default 0, aggiornato timestamptz not null default now());
alter table public.jarvis_ig_visti enable row level security;
alter table public.jarvis_ig_profili enable row level security;
alter table public.jarvis_ig_post enable row level security;
revoke all on public.jarvis_ig_visti, public.jarvis_ig_profili, public.jarvis_ig_post from anon, authenticated;
grant select, insert, update, delete on public.jarvis_ig_visti, public.jarvis_ig_profili, public.jarvis_ig_post to service_role;

create or replace function public.sveglia_jarvis_instagram()
returns bigint language plpgsql security definer set search_path to 'public', 'extensions' as $$
begin
  return net.http_post(
    url := 'https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis-briefing',
    headers := public.intestazioni_interne(),
    body := '{"instagram_avvisi": true}'::jsonb,
    timeout_milliseconds := 120000);
end; $$;
revoke all on function public.sveglia_jarvis_instagram() from public, anon, authenticated;
grant execute on function public.sveglia_jarvis_instagram() to service_role;
-- acceso il 27 nov alle 04:22 (job jarvis-instagram): select cron.schedule('jarvis-instagram', '*/15 * * * *', 'select public.sveglia_jarvis_instagram()');
