-- 25 ottobre 2026, idea B approvata dal signore: un solo JARVIS risponde.
-- Quando iPhone e Mac (o orologio e Mac) sentono la stessa frase e la mandano tutti e due al cervello, risponde uno solo.
-- Ogni frase detta a voce lascia qui una riga (chi l'ha sentita, il testo normalizzato, quando è finita) e la decisione.
-- Il cervello la legge e la scrive con la chiave di servizio: RLS acceso e nessuna regola, come le altre tabelle di JARVIS.
-- Le righe più vecchie di un'ora le cancella il cervello da solo. Senza questa tabella il cervello risponde come prima
-- (l'arbitro fallisce in silenzio e la frase vince).

create table if not exists public.jarvis_arbitro (
  id          bigint generated always as identity primary key,
  creata      timestamptz not null default now(),   -- il cervello la scrive lui (ora di arrivo della richiesta)
  dispositivo text not null,                        -- l'id dell'installazione dell'app (uuid), non il tipo
  tipo        text,                                 -- iphone, mac, orologio
  testo       text not null,                        -- la frase senza accenti, punteggiatura e «Jarvis» davanti
  fine        bigint,                               -- quando il signore ha smesso di parlare (ms, orologio del dispositivo)
  parole      integer,                              -- quante parole ha sentito
  vince       boolean                               -- vero: risponde; falso: tace; nullo: ancora da decidere
);
create index if not exists jarvis_arbitro_creata on public.jarvis_arbitro (creata desc);
alter table public.jarvis_arbitro enable row level security;

-- Per controllare dal vivo (ultimi 10 minuti):
-- select creata, tipo, testo, fine, parole, vince from jarvis_arbitro where creata > now() - interval '10 minutes' order by id desc;
-- I turni che hanno taciuto risultano anche in jarvis_consumi: servizio «turno», esito «doppione».
