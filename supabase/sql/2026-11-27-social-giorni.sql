-- 27 nov · INSTAGRAM NEL BRIEFING: i follower di ogni giorno, per dire quanti ne ha guadagnati da ieri (solo server, jarvis-briefing).
create table if not exists public.jarvis_social_giorni (
  giorno date primary key,
  follower integer not null,
  creato timestamptz not null default now()
);
alter table public.jarvis_social_giorni enable row level security;
revoke all on public.jarvis_social_giorni from anon, authenticated;
grant select, insert, update, delete on public.jarvis_social_giorni to service_role;
