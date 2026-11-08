-- JARVIS · SOCIAL › RIVALI (8 nov 2026): il login di Facebook (serve a Business Discovery) e gli account seguiti.
-- Si applica solo col via del signore, insieme alle funzioni «social-facebook» e «social».

-- La chiave di Facebook (60 giorni) e l'account Instagram legato alla pagina. Una riga sola (id = 1).
-- «attesa» e «attesa_fino» sono il codice monouso del login in corso (protezione dal CSRF): valgono 10 minuti.
create table if not exists public.social_facebook (
  id int primary key default 1 check (id = 1),
  token text,
  scade timestamptz,
  ig_id text,
  pagina text,
  attesa text,
  attesa_fino timestamptz,
  aggiornato timestamptz not null default now()
);

-- Gli account seguiti in RIVALI (fino a 10) e gli ultimi numeri letti (si rileggono dopo 6 ore).
create table if not exists public.social_rivali (
  username text primary key check (username ~ '^[a-z0-9._]{1,30}$'),
  aggiunto timestamptz not null default now(),
  dati jsonb,
  letto timestamptz
);

-- Solo le funzioni del cervello (service role) ci arrivano: nessuna policy per anon/authenticated.
alter table public.social_facebook enable row level security;
alter table public.social_rivali enable row level security;
