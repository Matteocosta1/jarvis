#!/usr/bin/env python3
"""Mockup, 26 ott sera: correzioni dello Studio trovate provando tutti gli strumenti.
- SERIE × n faceva n-1 passi nella storia: ANNULLA toglieva una copia alla volta. Ora la serie è un passo solo.
Uso: mockup_correzioni_studio.py sorgente.html destinazione.html"""
import sys

src, dst = sys.argv[1], sys.argv[2]
h = open(src, encoding="utf-8").read()


def sost(vecchio, nuovo, n=1):
    global h
    c = h.count(vecchio)
    if c != n:
        sys.exit(f"ATTESO {n}, TROVATO {c}: {vecchio[:90]!r}")
    h = h.replace(vecchio, nuovo)


sost("""  function nuovo(tipo, p, nome, opz = {}) {
    memorizza();""", """  function nuovo(tipo, p, nome, opz = {}) {
    if (!opz.senzaStoria) memorizza();""")
sost("""    if (!o) return; const passo = B.ingombro(o).l + 10;
    for (let k = 1; k < n; k++) setTimeout(() => { if (vivo()) nuovo(o.tipo, JSON.parse(JSON.stringify(o.p)), nomeLibero(o.nome.replace(/ #\\d+$/, "")), { pos: { x: o.pos.x + passo * k, z: o.pos.z, y: o.pos.y || 0 }, anim: "vola", come: o }); }, k * 260);""",
     """    if (!o) return; const passo = B.ingombro(o).l + 10; memorizza();          // tutta la serie è un passo solo: ANNULLA la toglie intera
    for (let k = 1; k < n; k++) setTimeout(() => { if (vivo()) nuovo(o.tipo, JSON.parse(JSON.stringify(o.p)), nomeLibero(o.nome.replace(/ #\\d+$/, "")), { pos: { x: o.pos.x + passo * k, z: o.pos.z, y: o.pos.y || 0 }, anim: "vola", come: o, senzaStoria: true }); }, k * 260);""")
open(dst, "w", encoding="utf-8").write(h)
print("scritto", dst)

# ── «crea un gatto» bloccava tutto (26 ott sera, provato dal signore): l'unione dei pezzi (BSP) girava sul filo principale e con
# sfere e tori ad alta risoluzione ci metteva decine di secondi (qui 70 s, 191.000 triangoli). Ora: l'unione gira in un
# Worker (la pagina resta viva), i pezzi si uniscono a coppie (albero bilanciato, molto più veloce dell'accumulo uno alla
# volta), le forme tonde hanno meno facce (per la stampa non cambia), dopo 60 s si rinuncia con un messaggio.
import json
i = h.index("const BSP = (() => {")
fine = "  return { daTriangoli, unione, differenza, aTriangoli };\n})();"
j = h.index(fine, i) + len(fine)
bsp = h[i:j]
lavoro = bsp + """
const coppie = (L) => { while (L.length > 1) { const n = []; for (let i = 0; i < L.length; i += 2) n.push(i + 1 < L.length ? BSP.unione(L[i], L[i + 1]) : L[i]); L = n; } return L[0] || null; };
const scatola = (L) => { const a = [1e9, 1e9, 1e9], b = [-1e9, -1e9, -1e9]; for (const P of L) for (const v of P.vs) for (let i = 0; i < 3; i++) { if (v[i] < a[i]) a[i] = v[i]; if (v[i] > b[i]) b[i] = v[i]; } return [a, b]; };
const tocca = (x, y) => x[0][0] <= y[1][0] + .01 && y[0][0] <= x[1][0] + .01 && x[0][1] <= y[1][1] + .01 && y[0][1] <= x[1][1] + .01 && x[0][2] <= y[1][2] + .01 && y[0][2] <= x[1][2] + .01;
const gruppi = (L) => { const B = L.map(scatola), pad = L.map((_, i) => i), f = (i) => (pad[i] === i ? i : (pad[i] = f(pad[i])));
  for (let i = 0; i < L.length; i++) for (let j = i + 1; j < L.length; j++) if (tocca(B[i], B[j])) pad[f(i)] = f(j);
  const m = new Map(); L.forEach((x, i) => { const r = f(i); if (!m.has(r)) m.set(r, []); m.get(r).push(x); }); return [...m.values()]; };
onmessage = (e) => { try { const pieni = e.data.pieni.map((a) => BSP.daTriangoli(a)), buchi = e.data.buchi.map((a) => BSP.daTriangoli(a));
  if (!pieni.length) { postMessage({ ok: false }); return; }
  // si uniscono solo i pezzi che si toccano (i gruppi staccati restano accostati); i fori scavano solo i gruppi che toccano
  const G = gruppi(pieni).map(coppie), H = buchi.length ? gruppi(buchi).map(coppie) : [], HB = H.map(scatola);
  let acc = []; for (let g of G) { const gb = scatola(g); for (let i = 0; i < H.length; i++) if (tocca(gb, HB[i])) g = BSP.differenza(g, H[i]); acc = acc.concat(g); }
  const t = BSP.aTriangoli(acc);
  // «stampabile»: ogni spigolo in due triangoli esatti (i vertici sono già saldati); prima lo contava la pagina e la bloccava 10 s
  const id = new Map(), sp = new Map(); let nv = 0; const v = (i) => { const k = t[i] + "," + t[i + 1] + "," + t[i + 2]; let x = id.get(k); if (x === undefined) { x = nv++; id.set(k, x); } return x; };
  for (let i = 0; i < t.length; i += 9) { const a = v(i), b = v(i + 3), c = v(i + 6); for (const [p, q] of [[a, b], [b, c], [c, a]]) { const k = p < q ? p * 4194304 + q : q * 4194304 + p; sp.set(k, (sp.get(k) || 0) + 1); } }
  let chiuso = true; for (const n of sp.values()) if (n !== 2) { chiuso = false; break; }
  postMessage({ ok: true, t, chiuso }, [t.buffer]); } catch (err) { postMessage({ ok: false, err: String(err) }); } };
"""
sost(fine, fine + """
// l'unione dei pezzi del progetto libero in un Worker: la pagina (e l'app) non si fermano mentre il cervello «costruisce»
const BSP_SORGENTE = """ + json.dumps(lavoro) + """;
let BSP_URL = null;
function bspInDisparte(pieni, buchi, ms = 60000) {          // Float32Array dei triangoli; null = troppo complesso; undefined = niente Worker
  return new Promise((ok) => {
    let w; try { BSP_URL = BSP_URL || URL.createObjectURL(new Blob([BSP_SORGENTE], { type: "text/javascript" })); w = new Worker(BSP_URL); } catch (e) { ok(undefined); return; }
    const via = setTimeout(() => { w.terminate(); ok(null); }, ms);
    w.onmessage = (e) => { clearTimeout(via); w.terminate(); if (e.data && e.data.ok) { e.data.t.chiuso = e.data.chiuso; ok(e.data.t); } else ok(null); };
    w.onerror = (e) => { clearTimeout(via); w.terminate(); e.preventDefault?.(); ok(undefined); };
    const tutti = [...pieni, ...buchi].map((a) => a.buffer);
    w.postMessage({ pieni, buchi }, tutti);
  });
}""")
# meno facce sulle forme tonde (sincrono e Worker usano le stesse)
sost('else if (q.forma === "cilindro") g = new T.CylinderGeometry(D / 2, D / 2, H, 40);', 'else if (q.forma === "cilindro") g = new T.CylinderGeometry(D / 2, D / 2, H, 32);')
sost('g = +m.d2 > .6 ? new T.CylinderGeometry(cl(m.d2, 0) / 2, D / 2, H, 40) : new T.ConeGeometry(D / 2, H, 40);', 'g = +m.d2 > .6 ? new T.CylinderGeometry(cl(m.d2, 0) / 2, D / 2, H, 32) : new T.ConeGeometry(D / 2, H, 32);')
sost('g = new T.SphereGeometry(D / 2, 32, 20);', 'g = new T.SphereGeometry(D / 2, 24, 16);')
sost('g = new T.TorusGeometry(Math.max(sz, D / 2 - sz / 2), sz / 2, 16, 48);', 'g = new T.TorusGeometry(Math.max(sz, D / 2 - sz / 2), sz / 2, 12, 36);')
# ricetta in due metà: i pezzi (qui) e la finitura (dopo il Worker)
sost("""        if (q.foro) buchi.push(tri(g)); else acc = acc ? BSP.unione(acc, tri(g)) : tri(g); }
      if (!acc) return null; for (const b of buchi) acc = BSP.differenza(acc, b);
      const g = new T.BufferGeometry(); g.setAttribute("position", new T.BufferAttribute(BSP.aTriangoli(acc), 3)); g.computeBoundingBox();""",
"""        if (soloPezzi) { const a = (g.index ? g.toNonIndexed() : g).attributes.position.array; (q.foro ? soloPezzi.buchi : soloPezzi.pieni).push(new Float32Array(a)); continue; }
        if (q.foro) buchi.push(tri(g)); else acc = acc ? BSP.unione(acc, tri(g)) : tri(g); }
      if (soloPezzi) return soloPezzi.pieni.length ? soloPezzi : null;
      if (!acc) return null; for (const b of buchi) acc = BSP.differenza(acc, b);
      return this.finisci(BSP.aTriangoli(acc)); },
    pezzi(pezzi) { return this.ricetta(pezzi, { pieni: [], buchi: [] }); },
    finisci(tri3) {
      const g = new T.BufferGeometry(); g.setAttribute("position", new T.BufferAttribute(tri3, 3)); g.computeBoundingBox();""")
sost("    ricetta(pezzi) {\n", "    ricetta(pezzi, soloPezzi = null) {\n")
sost("""    let R; try { R = B.ricetta(ric.pezzi); } catch (e) { console.warn(e); R = null; }""",
"""    // 26 ott sera: l'unione in disparte (Worker), la pagina resta viva; senza Worker, come prima
    inventando = true; info(["CREA · PROGETTO LIBERO", `«${D.toUpperCase()}»`, `UNISCO ${ric.pezzi.length} PEZZI…`]);
    let R = null; try { const pp = B.pezzi(ric.pezzi); if (pp) { const t = await bspInDisparte(pp.pieni, pp.buchi); R = t === undefined ? B.ricetta(ric.pezzi) : t ? B.finisci(t) : null; if (R && t) R.chiuso = t.chiuso; } } catch (e) { console.warn(e); R = null; }
    inventando = false; if (!vivo()) return;""")
# il «chiuso» calcolato nel Worker passa al pezzo (GEO_DATI) e la pagina non lo ricalcola
sost('const k = "r" + Date.now().toString(36); GEO_DATI.set(k, { pos: R.pos, norm: R.norm });', 'const k = "r" + Date.now().toString(36); GEO_DATI.set(k, { pos: R.pos, norm: R.norm, chiuso: R.chiuso });')
sost("""    oggetti.set(o.id, rec); posa(o);""", """    if (o.tipo === "unito") { const D = GEO_DATI.get(o.p.k); if (D && D.chiuso != null) rec.chiuso = D.chiuso; }
    oggetti.set(o.id, rec); posa(o);""")
open(dst, "w", encoding="utf-8").write(h)
print("scritto (con il Worker)", dst)

# ── CREA veloce (26 ott sera, il signore: «veloce e intelligente al massimo») ──
# 1 · il pezzo compare SUBITO (i pezzi accostati, così come arrivano dal cervello) e diventa un solido unico appena il Worker ha finito;
# 2 · nel Worker si uniscono solo i pezzi che si toccano (gruppi separati restano separati: nessun calcolo inutile) e i fori scavano
#     solo i gruppi che toccano; 3 · le forme tonde hanno facce in proporzione alla misura (un occhio da 4 mm non ne ha come la testa).
# facce in proporzione alla misura
sost('else if (q.forma === "cilindro") g = new T.CylinderGeometry(D / 2, D / 2, H, 32);', 'else if (q.forma === "cilindro") g = new T.CylinderGeometry(D / 2, D / 2, H, giri(D, 12, 32));')
sost('g = +m.d2 > .6 ? new T.CylinderGeometry(cl(m.d2, 0) / 2, D / 2, H, 32) : new T.ConeGeometry(D / 2, H, 32);', 'g = +m.d2 > .6 ? new T.CylinderGeometry(cl(m.d2, 0) / 2, D / 2, H, giri(D, 12, 32)) : new T.ConeGeometry(D / 2, H, giri(D, 12, 32));')
sost('g = new T.SphereGeometry(D / 2, 24, 16);', 'g = new T.SphereGeometry(D / 2, giri(D, 10, 24), Math.round(giri(D, 10, 24) * .66));')
sost('g = new T.TorusGeometry(Math.max(sz, D / 2 - sz / 2), sz / 2, 12, 36);', 'g = new T.TorusGeometry(Math.max(sz, D / 2 - sz / 2), sz / 2, giri(sz * 2, 8, 12), giri(D, 16, 36));')
sost("      let acc = null; const buchi = [];\n", "      let acc = null; const buchi = []; const giri = (d, a, b) => Math.max(a, Math.min(b, Math.round(d * .9)));\n")
# il pezzo subito, poi il solido unico
sost("""    inventando = true; info(["CREA · PROGETTO LIBERO", `«${D.toUpperCase()}»`, `UNISCO ${ric.pezzi.length} PEZZI…`]);
    let R = null; try { const pp = B.pezzi(ric.pezzi); if (pp) { const t = await bspInDisparte(pp.pieni, pp.buchi); R = t === undefined ? B.ricetta(ric.pezzi) : t ? B.finisci(t) : null; if (R && t) R.chiuso = t.chiuso; } } catch (e) { console.warn(e); R = null; }
    inventando = false; if (!vivo()) return;
    if (!R) { parlaMock("Il progetto non torna, Sir: riprovi con una descrizione più semplice.", 3000); return; }
    const k = "r" + Date.now().toString(36); GEO_DATI.set(k, { pos: R.pos, norm: R.norm, chiuso: R.chiuso });
    const o = nuovo("unito", { k, ricetta: D }, nomeLibero(String(ric.nome || D).slice(0, 28).replace(/^./, (c) => c.toUpperCase())), { anim: "vacuform" }); const g = B.ingombro(o);""",
"""    let pp = null; try { pp = B.pezzi(ric.pezzi); } catch (e) { console.warn(e); }
    if (!pp) { parlaMock("Il progetto non torna, Sir: riprovi con una descrizione più semplice.", 3000); return; }
    // subito sul banco: i pezzi accostati come arrivano (si vede in un attimo); intanto il Worker li fonde in un solido unico
    const tutti = new Float32Array(pp.pieni.reduce((n, a) => n + a.length, 0)); { let i = 0; for (const a of pp.pieni) { tutti.set(a, i); i += a.length; } }
    const R0 = B.finisci(tutti), k = "r" + Date.now().toString(36); GEO_DATI.set(k, { pos: R0.pos, norm: R0.norm, chiuso: false });
    const o = nuovo("unito", { k, ricetta: D }, nomeLibero(String(ric.nome || D).slice(0, 28).replace(/^./, (c) => c.toUpperCase())), { anim: "vacuform" });
    inventando = true; info(["CREA · PROGETTO LIBERO", `«${o.nome.toUpperCase()}» · ${ric.pezzi.length} PEZZI`, "UNISCO IN UN SOLIDO UNICO…"]);
    let R = null; try { const t = await bspInDisparte(pp.pieni, pp.buchi); R = t === undefined ? B.ricetta(ric.pezzi) : t ? B.finisci(t) : null; if (R && t) R.chiuso = t.chiuso; } catch (e) { console.warn(e); R = null; }
    inventando = false; if (!vivo()) return;
    if (R) GEO_DATI.set(k, { pos: R.pos, norm: R.norm, chiuso: R.chiuso });   // vale anche per le copie (ANNULLA/RIPETI usano la stessa chiave)
    const oo = oggetti.find((x) => x.p?.k === k); if (!oo) return;   // tolto mentre si univa: niente da mostrare
    if (!R) { parlaMock("Il pezzo è troppo complesso da unire, Sir: lo vede, ma per la stampa lo descriva più semplice.", 3600); mostraDati(); return; }
    rifai(oo, "nessuna"); const g = B.ingombro(oo);""")
open(dst, "w", encoding="utf-8").write(h)
print("scritto (CREA veloce)", dst)
