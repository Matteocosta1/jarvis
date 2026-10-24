// Server IMAP e SMTP finti (testo in chiaro su 127.0.0.1): rispondono come iCloud e registrano quello che ricevono.
export const registro: { imap: string[]; smtp: string[]; dati: string; append: string } = { imap: [], smtp: [], dati: "", append: "" };
const enc = new TextEncoder();
const latino = (b: Uint8Array) => String.fromCharCode(...b);
export const opzioni = { smtpMutoDopoDati: false, intestazioni: "", search: "", fetchPriorita: "", corpo: "", fetchProtocolli: "", senzaMove: false };

async function righe(conn: Deno.Conn, gestisci: (riga: string, leggiByte: (n: number) => Promise<string>) => Promise<boolean | void>) {
  let resto = "";
  const buf = new Uint8Array(65536);
  const leggiByte = async (n: number) => {
    while (resto.length < n) { const k = await conn.read(buf); if (k === null) break; resto += latino(buf.subarray(0, k)); }
    const out = resto.slice(0, n); resto = resto.slice(n); return out;
  };
  while (true) {
    let i;
    while ((i = resto.indexOf("\r\n")) < 0) { const k = await conn.read(buf).catch(() => null); if (k === null) return; resto += latino(buf.subarray(0, k)); }
    const riga = resto.slice(0, i); resto = resto.slice(i + 2);
    if (await gestisci(riga, leggiByte)) return;
  }
}

export function imap(porta: number) {
  const l = Deno.listen({ hostname: "127.0.0.1", port: porta });
  (async () => {
    for await (const c of l) {
      (async () => {
        const w = (s: string) => c.write(Uint8Array.from(s, (ch) => ch.charCodeAt(0) & 255));   // i byte così come sono (stringhe in latin1)
        await w("* OK iCloud finto\r\n");
        await righe(c, async (riga, leggiByte) => {
          registro.imap.push(riga);
          const [tag, ...p] = riga.split(" "); const cmd = (p[0] ?? "").toUpperCase(); const resto = p.slice(1).join(" ");
          if (cmd === "LOGIN") await w(`${tag} OK LOGIN completed\r\n`);
          else if (cmd === "LIST") await w(`* LIST (\\HasNoChildren) "/" "INBOX"\r\n* LIST (\\HasNoChildren \\Sent) "/" "Sent Messages"\r\n* LIST (\\HasNoChildren \\Junk) "/" "Junk"\r\n* LIST (\\HasNoChildren \\Trash) "/" "Deleted Messages"\r\n${tag} OK LIST completed\r\n`);
          else if (cmd === "SELECT" || cmd === "EXAMINE") await w(`* 10 EXISTS\r\n* OK [UIDVALIDITY 777] UIDs valid\r\n${tag} OK [READ-WRITE] done\r\n`);
          else if (cmd === "UID" && /^SEARCH/i.test(resto)) await w(`* SEARCH ${opzioni.search}\r\n${tag} OK SEARCH completed\r\n`);
          else if (cmd === "UID" && /^FETCH \d+ \(UID BODY\.PEEK\[HEADER/i.test(resto)) {
            const h = opzioni.intestazioni; await w(`* 5 FETCH (UID 12 BODY[HEADER.FIELDS (FROM REPLY-TO SUBJECT MESSAGE-ID REFERENCES)] {${h.length}}\r\n${h})\r\n${tag} OK FETCH completed\r\n`);
          } else if (cmd === "UID" && /^FETCH [\d,]+ \(UID FLAGS BODYSTRUCTURE/i.test(resto)) await w(`${opzioni.fetchPriorita}${tag} OK FETCH completed\r\n`);
          else if (cmd === "UID" && /^FETCH \d+ \(BODY\.PEEK\[/i.test(resto)) {
            const uid = resto.split(" ")[1], sez = resto.match(/BODY\.PEEK\[([^\]]+)\]/)![1], b = opzioni.corpo;
            await w(`* 7 FETCH (UID ${uid} BODY[${sez}]<0> {${b.length}}\r\n${b})\r\n${tag} OK FETCH completed\r\n`);
          } else if (cmd === "UID" && /^FETCH [\d,]+ \(UID FLAGS BODY\.PEEK\[HEADER\.FIELDS \(FROM TO SUBJECT DATE\)\]\)/i.test(resto)) await w(`${opzioni.fetchPriorita}${tag} OK FETCH completed\r\n`);
          else if (cmd === "UID" && /^FETCH [\d,]+ \(UID BODY\.PEEK\[HEADER\.FIELDS \(SUBJECT X-JARVIS\)\]\)/i.test(resto)) await w(`${opzioni.fetchProtocolli}${tag} OK FETCH completed\r\n`);
          else if (cmd === "UID" && /^MOVE/i.test(resto)) await w(opzioni.senzaMove ? `${tag} BAD MOVE non supportato\r\n` : `* OK [COPYUID 777 1 1]\r\n${tag} OK MOVE completed\r\n`);
          else if (cmd === "UID" && /^(COPY|EXPUNGE)/i.test(resto)) await w(`${tag} OK done\r\n`);
          else if (cmd === "UID" && /^STORE/i.test(resto)) await w(`* 5 FETCH (UID 12 FLAGS (\\Seen \\Answered))\r\n${tag} OK STORE completed\r\n`);
          else if (cmd === "APPEND") {
            const n = Number(riga.match(/\{(\d+)\}$/)![1]); await w("+ Ready for literal data\r\n");
            registro.append = await leggiByte(n); await leggiByte(2); await w(`${tag} OK [APPENDUID 777 99] APPEND completed\r\n`);
          } else if (cmd === "LOGOUT") { await w(`* BYE\r\n${tag} OK LOGOUT completed\r\n`); c.close(); return true; }
          else await w(`${tag} BAD comando sconosciuto\r\n`);
        });
      })().catch(() => {});
    }
  })();
  return l;
}

export function smtp(porta: number) {
  const l = Deno.listen({ hostname: "127.0.0.1", port: porta });
  (async () => {
    for await (const c of l) {
      (async () => {
        const w = (s: string) => c.write(Uint8Array.from(s, (ch) => ch.charCodeAt(0) & 255));   // i byte così come sono (stringhe in latin1)
        await w("220 smtp finto\r\n");
        let inDati = false, dati = "";
        await righe(c, async (riga) => {
          if (inDati) {
            if (riga === ".") { inDati = false; registro.dati = dati; if (opzioni.smtpMutoDopoDati) return false; await w("250 2.0.0 queued\r\n"); return; }
            dati += riga + "\r\n"; return;
          }
          registro.smtp.push(riga);
          const cmd = riga.split(" ")[0].toUpperCase();
          if (cmd === "EHLO") await w("250-smtp finto\r\n250-AUTH PLAIN LOGIN\r\n250 8BITMIME\r\n");
          else if (cmd === "AUTH") await w("235 2.7.0 ok\r\n");
          else if (cmd === "MAIL" || cmd === "RCPT") await w("250 2.1.0 ok\r\n");
          else if (cmd === "DATA") { inDati = true; dati = ""; await w("354 avanti\r\n"); }
          else if (cmd === "QUIT") { await w("221 ciao\r\n"); c.close(); return true; }
          else await w("500 boh\r\n");
        });
      })().catch(() => {});
    }
  })();
  return l;
}
