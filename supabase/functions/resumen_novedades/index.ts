// ELÍPTICA · Edge Function "resumen_novedades"
// También envía al instante el correo de faltantes de material en corte (body {tipo:"faltante"}) a compras e inventario.
// Al final de la jornada (6:00 p. m., la llama la base con pg_cron) envía a cobros UN correo por obra
// con el PDF de las novedades de instalación del día (fecha y hora del servidor, motivo, ítems y fotos).
// Secretos necesarios (Edge Functions → Secrets): GMAIL_USER y GMAIL_APP_PASSWORD.
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";
import nodemailer from "npm:nodemailer@6.9.16";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const LOGO = "https://jose-manuel-hurtado.github.io/registro-produccion/icons/logo-etiqueta.png";
const TZ = "America/Bogota";

// pdf-lib (Helvetica) solo escribe caracteres WinAnsi: se cambian los demás
const w = (t: unknown) => String(t ?? "").replace(/[–—]/g, "-").replace(/[“”]/g, '"').replace(/[‘’]/g, "'").replace(/…/g, "...")
  .replace(/[^\x20-\x7E\xA0-\xFF\n]/g, "");
const fh = (t: string | Date) => new Date(t).toLocaleString("es-CO", { timeZone: TZ, day: "2-digit", month: "2-digit", year: "numeric", hour: "numeric", minute: "2-digit" });
const fd = (t: string | Date) => new Date(t).toLocaleDateString("es-CO", { timeZone: TZ, day: "2-digit", month: "2-digit", year: "numeric" });
const lugar = (u: string | null) => String(u || "").split(/\s*[-–]\s*/)[0];

type Nov = { id: number; obra: string; items: number[]; ops: string; piso: string | null; motivo: string; detalle: string | null; fotos: string[]; creada: string; quien: string | null; instalador: string | null };
type It = { id: number; op_instalacion: string | null; op: string | null; item: string | null; ubicacion: string | null; piso: string | null };

export async function pdfObra(obra: string, novs: Nov[], items: Map<number, It>, foto: (r: string) => Promise<Uint8Array | null>, logo: Uint8Array | null, responder = "") {
  const pdf = await PDFDocument.create();
  const f = await pdf.embedFont(StandardFonts.Helvetica), fb = await pdf.embedFont(StandardFonts.HelveticaBold);
  const PW = 612, PH = 792, M = 40, TW = PW - 2 * M;
  const lg = logo ? await pdf.embedPng(logo).catch(() => null) : null;
  let page = pdf.addPage([PW, PH]), y = 0, hoja = 0;
  const lineas = (t: string, font = f, size = 9, ancho = TW - 12) => {
    const out: string[] = [];
    for (const par of w(t).split("\n")) {
      let l = "";
      for (const pal of par.split(" ")) { const p = l ? l + " " + pal : pal; if (font.widthOfTextAtSize(p, size) > ancho && l) { out.push(l); l = pal; } else l = p; }
      out.push(l);
    }
    return out;
  };
  const enc = () => {
    hoja++;
    if (lg) { const h = 30; page.drawImage(lg, { x: M, y: PH - 34 - h, width: h * lg.width / lg.height, height: h }); }
    page.drawText(w("NOVEDADES DE INSTALACIÓN"), { x: PW - M - fb.widthOfTextAtSize("NOVEDADES DE INSTALACION", 14), y: PH - 46, size: 14, font: fb });
    const sub = w(`Obra: ${obra}  ·  ${fd(novs[0].creada)}${hoja > 1 ? "  ·  Hoja " + hoja : ""}`);
    page.drawText(sub, { x: PW - M - f.widthOfTextAtSize(sub, 9), y: PH - 60, size: 9, font: f, color: rgb(.35, .35, .35) });
    page.drawLine({ start: { x: M, y: PH - 76 }, end: { x: PW - M, y: PH - 76 }, thickness: .6, color: rgb(.7, .7, .7) });
    y = PH - 94;
  };
  const salto = (h: number) => { if (y - h < 50) { page = pdf.addPage([PW, PH]); enc(); } };
  enc();
  for (const l of lineas(`Elíptica informa las novedades encontradas en la obra que impidieron la instalación de los ítems relacionados. La fecha y hora de cada novedad fueron asignadas por el servidor en el momento del reporte y no se pueden modificar. Las fotos llevan impresa la fecha, hora, obra y OP del reporte.${responder ? ` Por favor envíe su respuesta a: ${responder}.` : ""}`, f, 9, TW)) {
    page.drawText(l, { x: M, y, size: 9, font: f, color: rgb(.25, .25, .25) }); y -= 12;
  }
  y -= 8;
  for (const n of novs) {
    const its = (n.items || []).map((i) => items.get(i)).filter(Boolean) as It[];
    const filas: [string[], typeof f, number][] = [
      [lineas(`N.º ${n.id}  ·  ${fh(n.creada)}`, fb, 11), fb, 11],
      [lineas(`Motivo: ${n.motivo}`, fb, 9.5), fb, 9.5],
      [lineas(`Ítems (${(n.items || []).length}): ${its.length ? its.map((i) => `${i.op_instalacion || i.op} ${i.item || ""}${i.ubicacion ? " (" + lugar(i.ubicacion) + ")" : ""}`).join(", ") : n.ops}${n.piso ? "  ·  " + n.piso : ""}`), f, 9],
      ...(n.detalle ? [[lineas(`Detalle: ${n.detalle}`), f, 9] as [string[], typeof f, number]] : []),
      [lineas(`Reportó: ${n.quien || "-"}${n.instalador ? "  ·  instalador " + n.instalador : ""}`), f, 8.5],
    ];
    const hTxt = filas.reduce((s, [ls, , sz]) => s + ls.length * (sz + 3), 0) + 12;
    salto(hTxt + 10);
    page.drawRectangle({ x: M, y: y - hTxt + 12, width: TW, height: hTxt, borderColor: rgb(.75, .25, .25), borderWidth: .8 });
    let yy = y;
    for (const [ls, font, sz] of filas) for (const l of ls) { page.drawText(l, { x: M + 8, y: yy, size: sz, font }); yy -= sz + 3; }
    y -= hTxt + 6;
    const fw = (TW - 16) / 3; let col = 0, hFila = 0;
    for (const r of n.fotos || []) {
      const b = await foto(r); if (!b) continue;
      const im = await pdf.embedJpg(b).catch(() => null); if (!im) continue;
      let iw = fw, ih = fw * im.height / im.width; if (ih > 220) { ih = 220; iw = ih * im.width / im.height; }
      if (col === 0) salto(ih + 6);
      page.drawImage(im, { x: M + col * (fw + 8), y: y - ih, width: iw, height: ih });
      hFila = Math.max(hFila, ih); col++;
      if (col === 3) { y -= hFila + 8; col = 0; hFila = 0; }
    }
    if (col) y -= hFila + 8;
    y -= 14;
  }
  for (const p of pdf.getPages()) p.drawText(w(`Novedades de instalación · ${obra} · Elíptica Cerramientos Translúcidos`), { x: M, y: 24, size: 7, font: f, color: rgb(.55, .55, .55) });
  return await pdf.save();
}

// ── Faltantes de material en corte: correo inmediato a compras e inventario (SQL 81) ──
type Falt = { id: number; obra: string | null; op: string; op_inst: string[]; ref: string; descripcion: string | null; cant: number | null; medida: number | null; nota: string | null; quien: string | null; creada: string };
const e = (t: unknown) => String(t ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;");
const n0 = (v: number | null) => v == null ? "" : Number(v).toLocaleString("es-CO", { maximumFractionDigits: 2 });
async function correoFaltantes(ids: number[] | null, usuario: string, clave: string) {
  const { data: cf } = await db.from("push_config").select("correos_faltantes").eq("id", 1).single();
  const para = String(cf?.correos_faltantes || "").split(/[,;\s]+/).map((x) => x.trim()).filter(Boolean);
  if (!para.length) return { enviados: 0, error: "sin destinatarios" };
  // Los indicados, y lo que haya quedado sin enviar de los últimos 3 días
  const { data: fs, error } = await db.from("faltantes").select("*").is("correo_en", null)
    .gte("creada", new Date(Date.now() - 3 * 864e5).toISOString()).order("creada");
  if (error) throw error;
  const l = (fs || []) as Falt[];   // incluye los recién registrados (ids) y lo que no se pudo enviar antes
  if (!l.length) return { enviados: 0 };
  const smtp = nodemailer.createTransport({ host: "smtp.gmail.com", port: 465, secure: true, auth: { user: usuario, pass: clave } });
  const grupos = new Map<string, Falt[]>();
  for (const f of l) { const k = (f.obra || "") + "|" + f.op + "|" + f.creada.slice(0, 16); if (!grupos.has(k)) grupos.set(k, []); grupos.get(k)!.push(f); }
  let n = 0;
  for (const g of grupos.values()) {
    const f0 = g[0], subs = [...new Set(g.flatMap((f) => f.op_inst || []))];
    const filas = g.map((f) => `<tr><td style="padding:6px 10px;border:1px solid #ccc"><b>${e(f.ref)}</b></td><td style="padding:6px 10px;border:1px solid #ccc">${e(f.descripcion || "")}</td><td style="padding:6px 10px;border:1px solid #ccc;text-align:right"><b>${n0(f.cant)}</b></td><td style="padding:6px 10px;border:1px solid #ccc;text-align:right">${f.medida ? n0(f.medida) + " mm" : ""}</td></tr>`).join("");
    const html = `<p>Se registró un <b>faltante de material en corte</b>:</p>
      <p><b>Obra:</b> ${e(f0.obra || "")}<br><b>OP:</b> ${e(f0.op)}${subs.length ? ` · unidades afectadas: ${e(subs.join(", "))}` : ""}<br><b>Reportó:</b> ${e(f0.quien || "")} · ${fh(f0.creada)}</p>
      <table style="border-collapse:collapse;font-family:Arial,sans-serif;font-size:13px"><tr style="background:#1e1f20;color:#fff"><th style="padding:6px 10px;text-align:left">Perfil</th><th style="padding:6px 10px;text-align:left">Descripción</th><th style="padding:6px 10px">Cantidad faltante</th><th style="padding:6px 10px">Medida de corte</th></tr>${filas}</table>
      ${g.some((f) => f.nota) ? `<p><b>Nota:</b> ${e(g.map((f) => f.nota).filter(Boolean).join(" · "))}</p>` : ""}
      <p>Elíptica Cerramientos Translúcidos · Registro de producción</p>`;
    try {
      await smtp.sendMail({ from: `"Elíptica · Faltante de material" <${usuario}>`, to: para.join(", "),
        subject: `Faltante de material · ${f0.obra || ""} · OP ${f0.op} · ${g.map((f) => f.ref).join(", ")}`, html });
      await db.from("faltantes").update({ correo_en: new Date().toISOString() }).in("id", g.map((f) => f.id));
      n++;
    } catch (err) { console.error("faltante", err); }
  }
  return { enviados: n };
}

Deno.serve(async (req) => {
  try {
    const { data: cfg } = await db.from("push_config").select("cron_token").eq("id", 1).single();
    if (!cfg?.cron_token || req.headers.get("x-elp-token") !== cfg.cron_token) return new Response("no autorizado", { status: 401 });
    const usuario = Deno.env.get("GMAIL_USER"), clave = Deno.env.get("GMAIL_APP_PASSWORD");
    if (!usuario || !clave) return new Response("Faltan los secretos GMAIL_USER y GMAIL_APP_PASSWORD", { status: 500 });
    const body = await req.json().catch(() => ({}));
    if (body?.tipo === "faltante") return new Response(JSON.stringify(await correoFaltantes(body.ids || null, usuario, clave)), { headers: { "Content-Type": "application/json" } });
    const { data: para } = await db.rpc("correos_cobros");
    const destinos = (para || []).map((x: { email?: string } | string) => typeof x === "string" ? x : x.email).filter(Boolean);
    if (!destinos.length) return new Response("No hay usuario de cobros con correo", { status: 500 });
    const { data: novs, error } = await db.from("novedades").select("*").is("correo_en", null).order("creada");
    if (error) throw error;
    if (!novs?.length) return new Response(JSON.stringify({ enviados: 0 }), { headers: { "Content-Type": "application/json" } });
    const ids = [...new Set(novs.flatMap((n: Nov) => n.items || []))];
    const items = new Map<number, It>();
    for (let k = 0; k < ids.length; k += 500) {
      const { data } = await db.from("items").select("id,op_instalacion,op,item,ubicacion,piso").in("id", ids.slice(k, k + 500));
      for (const i of data || []) items.set(i.id, i);
    }
    const foto = async (r: string) => { const { data } = await db.storage.from("novedades").download(r); return data ? new Uint8Array(await data.arrayBuffer()) : null; };
    const logo = await fetch(LOGO).then((r) => r.ok ? r.arrayBuffer() : null).then((b) => b ? new Uint8Array(b) : null).catch(() => null);
    const copia = (Deno.env.get("COPIA_A") || usuario).split(",").map((x) => x.trim()).filter(Boolean);
    const responder = [...new Set([...destinos, ...copia])];
    const smtp = nodemailer.createTransport({ host: "smtp.gmail.com", port: 465, secure: true, auth: { user: usuario, pass: clave } });
    const porObra = new Map<string, Nov[]>();
    for (const n of novs as Nov[]) { if (!porObra.has(n.obra)) porObra.set(n.obra, []); porObra.get(n.obra)!.push(n); }
    const res: { obra: string; n: number; ok: boolean; error?: string }[] = [];
    for (const [obra, l] of porObra) {
      try {
        const pdf = await pdfObra(obra, l, items, foto, logo, responder.join(" y "));
        const fecha = fd(l[l.length - 1].creada), nItems = l.reduce((s, n) => s + (n.items || []).length, 0);
        const archivo = `Novedades_${obra.replace(/[^\w\- ]+/g, "").trim().replace(/\s+/g, "_")}_${fecha.replace(/\//g, "-")}.pdf`;
        const lista = l.map((n) => `<li><b>${fh(n.creada)}</b> — ${n.motivo} · ${(n.items || []).length} ítem(s) · ${n.ops || ""}${n.piso ? " · " + n.piso : ""}${n.detalle ? `<br><i>${n.detalle.replace(/</g, "&lt;")}</i>` : ""}</li>`).join("");
        await smtp.sendMail({
          from: `"Elíptica · Novedades de instalación" <${usuario}>`, to: destinos.join(", "), cc: copia.join(", "), replyTo: responder.join(", "),
          subject: `Novedades de instalación · ${obra} · ${fecha}`,
          html: `<p>Buenas tardes,</p><p>Durante la jornada del <b>${fecha}</b> se reportaron <b>${l.length} novedad(es)</b> que impidieron instalar <b>${nItems} ítem(s)</b> en la obra <b>${obra}</b>:</p><ul>${lista}</ul><p>Se adjunta el documento con la evidencia (fecha y hora del reporte, motivo y fotos) para reenviar a la obra.</p><p><b>Al reenviarlo a la obra, deje en copia a ${copia.join(", ")}</b> para que la respuesta de la obra llegue también a la gerencia.</p><p>Elíptica Cerramientos Translúcidos</p>`,
          attachments: [{ filename: archivo, content: pdf, contentType: "application/pdf" }],
        });
        await db.from("novedades").update({ correo_en: new Date().toISOString() }).in("id", l.map((n) => n.id));
        res.push({ obra, n: l.length, ok: true });
      } catch (e) { console.error(obra, e); res.push({ obra, n: l.length, ok: false, error: String(e) }); }
    }
    return new Response(JSON.stringify({ enviados: res.filter((r) => r.ok).length, detalle: res }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error(e);
    return new Response(String(e), { status: 500 });
  }
});
