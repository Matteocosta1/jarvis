-- 27 nov · USCITE MUSICALI (issue #19, pezzo 2): gli artisti di cui JARVIS controlla le uscite su Apple Music ogni mattina.
-- La legge e la scrive solo il server (funzione jarvis-briefing, dentro il giro delle novità delle 5).
create table if not exists public.jarvis_artisti (
  id bigint generated always as identity primary key,
  nome text not null unique,
  am_id text,                 -- l'identificativo dell'artista nel catalogo Apple Music (si trova da solo la prima volta)
  ultima_uscita text,         -- l'ultima uscita già detta (così non la ripete)
  attivo boolean not null default true,
  creato timestamptz not null default now()
);
alter table public.jarvis_artisti enable row level security;
revoke all on public.jarvis_artisti from anon, authenticated;
grant select, insert, update, delete on public.jarvis_artisti to service_role;

insert into public.jarvis_artisti (nome) values
  ('Sfera Ebbasta'), ('Tony Boy'), ('The Clash'), ('Sex Pistols'), ('Iggy Pop')
on conflict (nome) do nothing;
