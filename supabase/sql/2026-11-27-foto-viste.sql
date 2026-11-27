-- 27 nov · CRONOLOGIA DELLE FOTO (issue #20, pezzo 1): le foto che il signore fa vedere a JARVIS, salvate da sole a fine turno.
-- Solo server (cervello). L'immagine sta nello Storage privato «foto-viste»; qui data, luogo, frase del signore e descrizione di JARVIS.
create table if not exists public.jarvis_foto (
  id bigint generated always as identity primary key,
  creato timestamptz not null default now(),
  dispositivo text,
  origine text not null default 'occhi',     -- chat | occhi | giro
  percorso text not null,
  impronta text not null unique,              -- sha256 dell'immagine: la stessa foto non si salva due volte
  domanda text,
  descrizione text,
  lat double precision,
  lon double precision,
  vettore extensions.vector(384),
  vettore_g extensions.vector(768)
);
create index if not exists jarvis_foto_creato on public.jarvis_foto (creato desc);
create index if not exists jarvis_foto_vettore on public.jarvis_foto using hnsw (vettore extensions.vector_cosine_ops);
create index if not exists jarvis_foto_vettore_g on public.jarvis_foto using hnsw (vettore_g extensions.vector_cosine_ops);
create index if not exists jarvis_foto_senza_vettore on public.jarvis_foto (id) where vettore is null;
create index if not exists jarvis_foto_senza_vettore_g on public.jarvis_foto (id) where vettore_g is null;
alter table public.jarvis_foto enable row level security;
revoke all on public.jarvis_foto from anon, authenticated;
grant select, insert, update, delete on public.jarvis_foto to service_role;

-- la ricerca per significato accetta anche jarvis_foto
create or replace function public.jarvis_significato(tabella text, vettore extensions.vector, quanti integer default 10, soglia double precision default 0.8)
returns table(id bigint, somiglianza double precision) language plpgsql stable set search_path to 'public', 'extensions' as $function$
begin
  if tabella not in ('jarvis_memoria', 'jarvis_ricordi', 'jarvis_note', 'jarvis_diario', 'jarvis_episodi', 'jarvis_foto') then
    raise exception 'tabella non ammessa: %', tabella;
  end if;
  return query execute format(
    'select v.id, v.somiglianza from (
       select t.id, 1 - (t.vettore <=> $1) as somiglianza from public.%I t
       where t.vettore is not null order by t.vettore <=> $1 limit $2
     ) v where v.somiglianza >= $3 order by v.somiglianza desc', tabella)
  using vettore, least(greatest(coalesce(quanti, 10), 1), 50), coalesce(soglia, 0.8);
end $function$;
create or replace function public.jarvis_significato_g(tabella text, vettore extensions.vector, quanti integer default 10, soglia double precision default 0.7)
returns table(id bigint, somiglianza double precision) language plpgsql stable set search_path to 'public', 'extensions' as $function$
begin
  if tabella not in ('jarvis_memoria', 'jarvis_ricordi', 'jarvis_note', 'jarvis_diario', 'jarvis_episodi', 'jarvis_foto') then
    raise exception 'tabella non ammessa: %', tabella;
  end if;
  return query execute format(
    'select v.id, v.somiglianza from (
       select t.id, 1 - (t.vettore_g <=> $1) as somiglianza from public.%I t
       where t.vettore_g is not null order by t.vettore_g <=> $1 limit $2
     ) v where v.somiglianza >= $3 order by v.somiglianza desc', tabella)
  using vettore, least(greatest(coalesce(quanti, 10), 1), 50), coalesce(soglia, 0.7);
end $function$;
