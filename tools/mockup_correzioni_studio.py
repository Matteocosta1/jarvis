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
