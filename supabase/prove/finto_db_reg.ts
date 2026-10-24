// come finto_db.ts, ma registra gli insert in globalThis.__ins
(globalThis as any).__ins = [];
const fai = (tab: string | null): any => new Proxy(function () {}, {
  get(_t, p) {
    if (p === "then") return (ok: any) => ok({ data: null, error: null, count: 0 });
    if (p === "from") return (t: string) => fai(t);
    if (p === "insert") return (o: unknown) => { (globalThis as any).__ins.push({ tab, o }); return fai(tab); };
    return fai(tab);
  },
  apply() { return fai(tab); },
});
export const createClient = (..._a: any[]) => fai(null);
