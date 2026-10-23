-- Cervello v108: il RADAR della pioggia (build 22). Da applicare DOPO jarvis-briefing con { radar: true }.
-- 6 ─ RADAR: ogni 10 minuti il cervello guarda la pioggia dove si trova il signore e, solo se sta per piovere,
--     manda un avviso (una volta per pioggia, mai tra le 23:30 e le 8). L'avviso parte da jarvis-briefing, che ha le chiavi Apple.
create or replace function public.sveglia_jarvis_radar() returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  return net.http_post(
    url := 'https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis-briefing',
    headers := public.intestazioni_interne(),
    body := '{"radar": true}'::jsonb,
    timeout_milliseconds := 30000);
end; $$;
revoke all on function public.sveglia_jarvis_radar() from public, anon, authenticated;

select cron.unschedule('jarvis-radar') where exists (select 1 from cron.job where jobname = 'jarvis-radar');
select cron.schedule('jarvis-radar', '*/10 * * * *', 'select public.sveglia_jarvis_radar()');
