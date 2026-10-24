-- 24 ott 2026 (punto 2 dell'audit del dialogo): i tempi di ogni chiamata, turno e frase in jarvis_consumi.
-- Applicata al progetto il 24 ott (solo colonne in più: la versione v107 non le usa).
alter table public.jarvis_consumi
  add column if not exists ms_prima_parola integer,
  add column if not exists ms_primo_suono integer,
  add column if not exists ms_totale integer,
  add column if not exists esito text;
-- Righe nuove: servizio «turno» (domanda nuova) e «turno_seguito» (ritorno dal dispositivo dopo i suoi strumenti).
-- Le funzioni dei costi (jarvis_costi, jarvis_token_per_modello, jarvis_voce_caratteri) filtrano per servizio: non cambiano.
--
-- Per leggerli (ultimi 7 giorni, mediana e 90° percentile):
-- select servizio, modello, count(*),
--   percentile_cont(0.5) within group (order by ms_prima_parola) as prima_parola_p50,
--   percentile_cont(0.9) within group (order by ms_prima_parola) as prima_parola_p90,
--   percentile_cont(0.5) within group (order by ms_primo_suono)  as primo_suono_p50
-- from jarvis_consumi where creato > now() - interval '7 days' group by 1, 2 order by 1, 2;
