// Decisioni 24 ott: un client Supabase finto CON STATO, in memoria (globalThis.__tab: tabella → righe).
// Basta per le prove del cervello: select (colonne ignorate), eq/neq/is/in/gt/gte/lt/lte, order, limit, maybeSingle/single,
// count con head; insert (chiave unica → errore come Postgres), upsert, update(...).eq(...).select(), delete; rpc → globalThis.__rpc.
// I filtri che il finto non sa fare (not, or, ilike…) non filtrano: le prove non li usano per decidere.
const g = globalThis as any;
g.__tab ??= {} as Record<string, any[]>;
let prossimoId = 1000;
const CHIAVE: Record<string, string> = { jarvis_cache: "chiave", jarvis_richieste: "id", jarvis_filo: "dispositivo", jarvis_posizione: "dispositivo" };
const copia = (x: unknown) => x === undefined ? undefined : JSON.parse(JSON.stringify(x));
const uguale = (a: unknown, b: unknown) => a === b || (a != null && b != null && String(a) === String(b));

class Q {
  op = "select"; filtri: ((r: any) => boolean)[] = []; ordini: [string, boolean][] = []; lim: number | null = null;
  uno: "" | "maybe" | "single" = ""; val: any = null; ritorna = false; opz: any = {};
  constructor(public tab: string) {}
  righe(): any[] { return (g.__tab[this.tab] ??= []); }
  select(_c?: string, opz?: any) { if (this.op === "select") this.opz = opz ?? {}; else this.ritorna = true; return this; }
  insert(v: any) { this.op = "insert"; this.val = v; return this; }
  upsert(v: any) { this.op = "upsert"; this.val = v; return this; }
  update(v: any) { this.op = "update"; this.val = v; return this; }
  delete() { this.op = "delete"; return this; }
  eq(c: string, v: unknown) { this.filtri.push((r) => uguale(r[c], v)); return this; }
  neq(c: string, v: unknown) { this.filtri.push((r) => !uguale(r[c], v)); return this; }
  is(c: string, v: unknown) { this.filtri.push((r) => v === null ? r[c] == null : r[c] === v); return this; }
  in(c: string, v: unknown[]) { this.filtri.push((r) => v.some((x) => uguale(r[c], x))); return this; }
  gt(c: string, v: any) { this.filtri.push((r) => r[c] > v); return this; }
  gte(c: string, v: any) { this.filtri.push((r) => r[c] >= v); return this; }
  lt(c: string, v: any) { this.filtri.push((r) => r[c] < v); return this; }
  lte(c: string, v: any) { this.filtri.push((r) => r[c] <= v); return this; }
  not() { return this; } or() { return this; } ilike() { return this; } like() { return this; } contains() { return this; } range() { return this; }
  order(c: string, o: { ascending?: boolean } = {}) { this.ordini.push([c, o.ascending !== false]); return this; }
  limit(n: number) { this.lim = n; return this; }
  maybeSingle() { this.uno = "maybe"; return this; }
  single() { this.uno = "single"; return this; }
  esegui(): any {
    const tutte = this.righe();
    const scelte = tutte.filter((r) => this.filtri.every((f) => f(r)));
    const k = CHIAVE[this.tab] ?? "id";
    if (this.op === "insert" || this.op === "upsert") {
      const nuove = (Array.isArray(this.val) ? this.val : [this.val]).map((v: any) => ({ ...(k === "id" && v.id === undefined ? { id: prossimoId++ } : {}), ...copia(v) }));
      for (const n of nuove) {
        const i = tutte.findIndex((r) => r[k] !== undefined && uguale(r[k], n[k]));
        if (i >= 0 && this.op === "insert") return { data: null, error: { message: "duplicate key value violates unique constraint", code: "23505" } };
        if (i >= 0) tutte[i] = { ...tutte[i], ...n }; else tutte.push(n);
      }
      (g.__ops ??= []).push({ op: this.op, tab: this.tab, righe: copia(nuove) });
      return { data: this.ritorna ? copia(nuove) : null, error: null };
    }
    if (this.op === "update") {
      for (const r of scelte) Object.assign(r, copia(this.val));
      (g.__ops ??= []).push({ op: "update", tab: this.tab, righe: copia(scelte) });
      return { data: this.ritorna ? copia(scelte) : null, error: null };
    }
    if (this.op === "delete") {
      g.__tab[this.tab] = tutte.filter((r) => !scelte.includes(r));
      return { data: this.ritorna ? copia(scelte) : null, error: null };
    }
    let out = [...scelte];
    for (const [c, su] of [...this.ordini].reverse()) {
      out.sort((a, b) => { const x = a[c], y = b[c]; if (x == y) return 0; if (x == null) return 1; if (y == null) return -1; return (x < y ? -1 : 1) * (su ? 1 : -1); });
    }
    if (this.lim !== null) out = out.slice(0, this.lim);
    if (this.opz?.head) return { data: null, error: null, count: scelte.length };
    if (this.uno) {
      if (this.uno === "single" && out.length !== 1) return { data: null, error: { message: "not single" } };
      return { data: copia(out[0] ?? null), error: null };
    }
    return { data: copia(out), error: null, count: this.opz?.count ? scelte.length : null };
  }
  then(ok: (x: any) => unknown, no?: (e: unknown) => unknown) {
    try { return Promise.resolve(this.esegui()).then(ok, no); } catch (e) { return no ? Promise.resolve(no(e)) : Promise.reject(e); }
  }
}
export const createClient = (..._a: any[]) => ({
  from: (t: string) => new Q(t),
  rpc: async (nome: string, arg: unknown) => (g.__rpc ? g.__rpc(nome, arg) : { data: [], error: null }),
  storage: { from: () => ({}) },
});
