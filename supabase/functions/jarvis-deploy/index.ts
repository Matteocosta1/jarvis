// jarvis-deploy: ricompone il codice di una funzione dalle parti salvate in jarvis_deploy_parti e lo pubblica
// con l'API di gestione di Supabase. Serve a caricare il cervello a pezzi piccoli invece che in un colpo solo.
// Segreti: JARVIS_SUPABASE_TOKEN (token personale), JARVIS_TOKEN (la parola d'ordine, nell'header x-jarvis-token), GITHUB_TOKEN (con ?da=github).
// Uso: ?funzione=jarvis&da=github[&verifica=1][&sha=<impronta attesa>] e la chiave (header x-jarvis-token o un ?codice= usa-e-getta).
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const REF = (Deno.env.get("SUPABASE_URL") || "").match(/https:\/\/([a-z0-9]+)\.supabase\.co/)?.[1] || "";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

Deno.serve(async (req) => {
  const segreto = Deno.env.get("JARVIS_TOKEN") ?? "";
  const url = new URL(req.url);
  const dato = req.headers.get("x-jarvis-token") ?? "";   // solo nell'header: mai nell'indirizzo, dove finirebbe nei log
  // in alternativa: un codice usa-e-getta (tabella jarvis_deploy_codici, scade da solo). Si consuma subito, in un colpo solo:
  // due richieste con lo stesso codice non passano mai entrambe.
  const codice = url.searchParams.get("codice") ?? "";
  let conCodice = false;
  if (/^[a-f0-9]{32,64}$/.test(codice)) {
    const { data: c } = await db.from("jarvis_deploy_codici").delete().eq("codice", codice).gt("scade", new Date().toISOString()).select("codice");
    conCodice = (c?.length ?? 0) > 0;
  }
  if (!conCodice && (!segreto || !uguali(dato, segreto))) return json({ errore: "parola d'ordine errata" }, 401);
  const token = Deno.env.get("JARVIS_SUPABASE_TOKEN") ?? "";
  if (!token) return json({ errore: "manca JARVIS_SUPABASE_TOKEN" }, 500);

  const funzione = (url.searchParams.get("funzione") || "jarvis").replace(/[^a-z0-9\-]/g, "");
  const verifica = url.searchParams.get("verifica") === "1";
  const files: Record<string, string> = {};
  let data: any[] = [];
  if (url.searchParams.get("da") === "github") {
    // il sorgente si prende direttamente dal repository privato di JARVIS (con il token GitHub già nei segreti)
    const repo = "Matteocosta1/jarvis";   // sempre e solo il repository di JARVIS
    const ref = (url.searchParams.get("ref") || "main").replace(/[^A-Za-z0-9._\/-]/g, "");
    const r = await fetch(`https://api.github.com/repos/${repo}/contents/supabase/functions/${funzione}/index.ts?ref=${ref}`, {
      headers: { authorization: `Bearer ${Deno.env.get("GITHUB_TOKEN") ?? ""}`, accept: "application/vnd.github.raw", "user-agent": "jarvis-deploy" },
    });
    if (!r.ok) return json({ errore: `GitHub ${r.status}: ${(await r.text()).slice(0, 200)}` }, 502);
    files["index.ts"] = await r.text();
    data = [{ file: "index.ts" }];
  } else {
    const q = await db.from("jarvis_deploy_parti").select("file, parte, contenuto").eq("funzione", funzione).order("file").order("parte");
    if (q.error) return json({ errore: q.error.message }, 500);
    data = q.data ?? [];
    if (!data.length) return json({ errore: "nessuna parte salvata per " + funzione }, 400);
    for (const p of data) files[p.file] = (files[p.file] ?? "") + p.contenuto;
  }
  const riassunto: Record<string, { byte: number; sha256: string }> = {};
  for (const [nome, testo] of Object.entries(files)) {
    const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(testo));
    riassunto[nome] = { byte: new TextEncoder().encode(testo).length, sha256: [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("") };
  }
  if (verifica) return json({ funzione, file: riassunto, parti: data.length });
  // sicurezza in più: se si indica l'impronta attesa, si pubblica solo se il file è esattamente quello
  const attesa = url.searchParams.get("sha") ?? "";
  if (attesa && riassunto["index.ts"]?.sha256 !== attesa) return json({ errore: "impronta diversa da quella attesa: non pubblico", file: riassunto }, 409);

  // pubblica con l'API di gestione (multipart: metadata + un campo file per ogni sorgente)
  const form = new FormData();
  form.append("metadata", JSON.stringify({ name: funzione, entrypoint_path: "index.ts", verify_jwt: false }));
  for (const [nome, testo] of Object.entries(files)) form.append("file", new Blob([testo], { type: "text/typescript" }), nome);
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/deploy?slug=${funzione}`, {
    method: "POST", headers: { authorization: `Bearer ${token}` }, body: form,
  });
  const testo = await r.text();
  if (!r.ok) return json({ errore: `deploy ${r.status}: ${testo.slice(0, 500)}` }, 502);
  let esito: any = {}; try { esito = JSON.parse(testo); } catch { /* testo semplice */ }
  // le parti restano nel database: sono il sorgente di riferimento, le prossime modifiche toccano solo i pezzi cambiati
  return json({ ok: true, funzione, versione: esito.version ?? null, stato: esito.status ?? null, file: riassunto });
});
