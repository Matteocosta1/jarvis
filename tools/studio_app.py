#!/usr/bin/env python3
"""MARK X · STUDIO e SOCIAL nell'app: prende il mockup approvato (artifact «JARVIS Mark X», index.html) e scrive la pagina dell'app
«Untitled Project/Studio3D/markx.html», identica al mockup con poche toppe per l'app:
  - three.js dal pacchetto dell'app (jarvis3d://) invece che dalla rete;
  - FOTO apre la fotocamera vera dell'iPhone (non la prova del mockup), il microfono usa la dettatura vera;
  - STAMPA/CONDIVIDI: l'STL va al foglio di condivisione così com'è (niente zip);
  - una porta per la foto che arriva dall'app (STUDIO_ATTIVO.foto);
  - SOCIAL con i dati veri di Instagram dal cervello (toppe in tools/toppe_social.py);
  - LiDAR → STUDIO con la scansione vera dell'iPhone (toppe in tools/toppe_lidar.py).
Uso: python3 tools/studio_app.py /percorso/index.html
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from toppe_social import toppe_social
from toppe_lidar import toppe_lidar
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
out = pathlib.Path(__file__).resolve().parent.parent / "Untitled Project" / "Studio3D" / "markx.html"

def toppa(s, vecchio, nuovo):
    assert s.count(vecchio) == 1, f"toppa non trovata o doppia: {vecchio[:70]}"
    return s.replace(vecchio, nuovo)

s = src
s = toppa(s, 'import("https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.min.js")', 'import("jarvis3d://app/three.module.min.js")')
s = toppa(s, 'if (k === "foto") fotocamera();',
          'if (k === "foto") { if (window.JARVIS_APP) window.webkit.messageHandlers.jarvis.postMessage({ tipo: "foto" }); else fotocamera(); }')
s = toppa(s, 'mic.addEventListener("click", () => { suona("aTick"); ascolta(SD_ESEMPI[esempio++ % SD_ESEMPI.length]); });',
          'mic.addEventListener("click", () => { suona("aTick"); if (window.JARVIS_APP) { const su = !mic.classList.contains("ascolta"); mic.classList.toggle("ascolta", su); '
          'const d = $sd("detto"); d.classList.toggle("vivo", su); d.querySelector("small").textContent = su ? "LA ASCOLTO · TOCCHI DI NUOVO PER FINIRE" : "A VOCE O SCRITTO"; '
          'window.webkit.messageHandlers.jarvis.postMessage({ tipo: su ? "ascolta" : "ferma" }); return; } ascolta(SD_ESEMPI[esempio++ % SD_ESEMPI.length]); });')
s = toppa(s, 'if (/\\.stl$/i.test(nome)) { dati = zipUno(', 'if (!window.JARVIS_APP && /\\.stl$/i.test(nome)) { dati = zipUno(')
s = toppa(s, 'window.STUDIO_ATTIVO = { vivo, voce: (t) => ascolta(t.replace(/^./, (c) => c.toLowerCase())),',
          'window.STUDIO_ATTIVO = { vivo, voce: (t) => ascolta(t.replace(/^./, (c) => c.toLowerCase())), foto: (im, nome) => { A.querySelector(".sd-cam")?.remove(); leggiFoto(im, nome || "foto", "oggetto"); },')
s = toppe_social(s, toppa)
s = toppe_lidar(s, toppa)
# il mockup pubblicato ha già il suo scheletro (doctype, viewport): si blocca solo lo zoom col pizzico
pagina = s.replace('content="width=device-width,initial-scale=1,viewport-fit=cover"', 'content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover"', 1)
if not pagina.lstrip().lower().startswith("<!doctype"):
    pagina = '<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover"></head><body>\n' + pagina + '\n</body></html>\n'
out.write_text(pagina, encoding="utf-8")
print("scritto", out, len(pagina) // 1024, "KB")
