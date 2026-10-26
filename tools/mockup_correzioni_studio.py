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
const unisciTutti = (L) => { while (L.length > 1) { const n = []; for (let i = 0; i < L.length; i += 2) n.push(i + 1 < L.length ? BSP.unione(L[i], L[i + 1]) : L[i]); L = n; } return L[0] || null; };
onmessage = (e) => { try { const pieni = e.data.pieni.map((a) => BSP.daTriangoli(a)), buchi = e.data.buchi.map((a) => BSP.daTriangoli(a));
  let acc = unisciTutti(pieni); if (!acc) { postMessage({ ok: false }); return; } if (buchi.length) acc = BSP.differenza(acc, unisciTutti(buchi));
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
