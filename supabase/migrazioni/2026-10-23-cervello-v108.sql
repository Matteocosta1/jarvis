-- Cervello v108 (build 22), 23 ottobre 2026.
-- 1. Ricerca per significato: vettori gte-small (384 numeri, calcolati dentro Supabase) su memoria, ricordi, note e diario.
-- 2. Filo della conversazione: il riassunto dei messaggi usciti dalla finestra delle ultime 20 battute, uno per dispositivo.
-- 3. Posizione per il RADAR: l'ultima posizione mandata dall'iPhone (anche ad app chiusa, con il permesso «Sempre»).
-- 4. Memorie brevi del cervello (jarvis_cache): la posta PRIORITÀ già letta, lo stato del radar (avvisato una volta per pioggia).
-- 5. Archivio: il bucket con il limite giusto (50 MB, quello del progetto), invece di 200 MB che Supabase rifiuta.
-- Tutte le tabelle hanno RLS acceso e nessuna regola: le legge e le scrive solo il cervello, con la chiave di servizio.

create extension if not exists vector with schema extensions;

-- 1 ─ vettori
alter table public.jarvis_memoria add column if not exists vettore extensions.vector(384);
alter table public.jarvis_ricordi add column if not exists vettore extensions.vector(384);
alter table public.jarvis_note    add column if not exists vettore extensions.vector(384);
alter table public.jarvis_diario  add column if not exists vettore extensions.vector(384);

create index if not exists jarvis_memoria_vettore on public.jarvis_memoria using hnsw (vettore extensions.vector_cosine_ops);
create index if not exists jarvis_ricordi_vettore on public.jarvis_ricordi using hnsw (vettore extensions.vector_cosine_ops);
create index if not exists jarvis_note_vettore    on public.jarvis_note    using hnsw (vettore extensions.vector_cosine_ops);
create index if not exists jarvis_diario_vettore  on public.jarvis_diario  using hnsw (vettore extensions.vector_cosine_ops);

-- le righe ancora senza vettore (il cervello le completa a fine turno, poche alla volta)
create index if not exists jarvis_memoria_senza_vettore on public.jarvis_memoria (id) where vettore is null;
create index if not exists jarvis_ricordi_senza_vettore on public.jarvis_ricordi (id) where vettore is null;
create index if not exists jarvis_note_senza_vettore    on public.jarvis_note    (id) where vettore is null;
create index if not exists jarvis_diario_senza_vettore  on public.jarvis_diario  (id) where vettore is null;

-- Le righe più vicine per significato a una frase (già trasformata in vettore dal cervello).
-- Solo le quattro tabelle di JARVIS: il nome della tabella non arriva mai dentro la query così com'è.
create or replace function public.jarvis_significato(tabella text, vettore extensions.vector(384), quanti integer default 10, soglia double precision default 0.8)
returns table (id bigint, somiglianza double precision)
language plpgsql stable
set search_path = public, extensions
as $$
begin
  if tabella not in ('jarvis_memoria', 'jarvis_ricordi', 'jarvis_note', 'jarvis_diario') then
    raise exception 'tabella non ammessa: %', tabella;
  end if;
  return query execute format(
    'select v.id, v.somiglianza from (
       select t.id, 1 - (t.vettore <=> $1) as somiglianza from public.%I t
       where t.vettore is not null order by t.vettore <=> $1 limit $2
     ) v where v.somiglianza >= $3 order by v.somiglianza desc', tabella)
  using vettore, least(greatest(coalesce(quanti, 10), 1), 50), coalesce(soglia, 0.8);
end $$;
revoke all on function public.jarvis_significato(text, extensions.vector, integer, double precision) from public, anon, authenticated;

-- 2 ─ filo della conversazione
create table if not exists public.jarvis_filo (
  dispositivo text primary key,
  riassunto   text not null default '',
  finestra    jsonb not null default '[]'::jsonb,   -- le battute viste al turno prima: [{r, t}], per capire quali sono uscite
  aggiornato  timestamptz not null default now()
);
alter table public.jarvis_filo enable row level security;

-- 3 ─ posizione per il radar
create table if not exists public.jarvis_posizione (
  dispositivo text primary key,
  lat         double precision not null,
  lon         double precision not null,
  precisione  double precision,
  quando      timestamptz not null,
  aggiornato  timestamptz not null default now()
);
alter table public.jarvis_posizione enable row level security;

-- 4 ─ memorie brevi del cervello
create table if not exists public.jarvis_cache (
  chiave     text primary key,
  valore     jsonb not null,
  aggiornato timestamptz not null default now()
);
alter table public.jarvis_cache enable row level security;

-- 5 ─ archivio
insert into storage.buckets (id, name, public, file_size_limit)
values ('archivio', 'archivio', false, 52428800)
on conflict (id) do update set file_size_limit = excluded.file_size_limit;

-- 6 ─ il RADAR ogni 10 minuti è in 2026-10-23-cervello-v108-radar.sql: si applica DOPO aver pubblicato jarvis-briefing con {radar: true},
--     altrimenti la vecchia jarvis-briefing scambierebbe la sveglia per quella del briefing del mattino.
