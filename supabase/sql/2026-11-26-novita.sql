-- 26 nov: il giro delle novità di JARVIS (lo scrive e lo legge solo il server, funzione jarvis-briefing)
create table if not exists public.jarvis_novita (
  id bigint generated always as identity primary key,
  giorno date not null,
  titolo text not null,
  perche text,
  fonte text,
  detta boolean not null default false,
  creato timestamptz not null default now()
);
create index if not exists jarvis_novita_giorno on public.jarvis_novita (giorno);
alter table public.jarvis_novita enable row level security;
revoke all on public.jarvis_novita from anon, authenticated;
grant select, insert, update, delete on public.jarvis_novita to service_role;

create or replace function public.sveglia_jarvis_novita()
returns bigint language plpgsql security definer set search_path to 'public', 'extensions' as $$
begin
  return net.http_post(
    url := 'https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis-briefing',
    headers := public.intestazioni_interne(),
    body := '{"novita": true}'::jsonb,
    timeout_milliseconds := 240000);
end; $$;
revoke all on function public.sveglia_jarvis_novita() from public, anon, authenticated;
grant execute on function public.sveglia_jarvis_novita() to service_role;

-- alle 5 di Roma (3 o 4 UTC a seconda dell'ora legale: la funzione controlla l'ora)
select cron.schedule('jarvis-novita', '0 3,4 * * *', 'select public.sveglia_jarvis_novita()');
