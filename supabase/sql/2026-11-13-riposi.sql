-- 13 nov 2026 · cervello v135 · il riposo detto a voce (il signore: «mettilo nel diario della sera»)
-- Il 13 nov l'orologio non aveva registrato né la notte né il pisolino del pomeriggio, e JARVIS diceva «lo conto io come riposo»
-- senza segnarlo da nessuna parte. Ora lo strumento riposo_segna lo mette qui; la pagina di diario di quel giorno ne porta la somma
-- (riposo_detto_min) e Vitals lo aggiunge al sonno di quel giorno. Solo il cervello (service role) legge e scrive: RLS senza regole.

create table if not exists public.jarvis_riposi (
  id bigint generated always as identity primary key,
  giorno date not null,
  minuti integer not null check (minuti between 10 and 720),
  da text check (da ~ '^[0-2][0-9]:[0-5][0-9]$'),
  a text check (a ~ '^[0-2][0-9]:[0-5][0-9]$'),
  creato timestamptz not null default now()
);
alter table public.jarvis_riposi enable row level security;
create index if not exists jarvis_riposi_giorno on public.jarvis_riposi (giorno);
comment on table public.jarvis_riposi is 'Riposi (pisolini o sonno) detti a voce dal signore e non registrati in Salute: il diario della sera li conta nel sonno.';

alter table public.jarvis_diario add column if not exists riposo_detto_min integer check (riposo_detto_min between 0 and 1440);
comment on column public.jarvis_diario.riposo_detto_min is 'Minuti di riposo detti a voce quel giorno (jarvis_riposi), sommati al sonno di Salute in Vitals.';
