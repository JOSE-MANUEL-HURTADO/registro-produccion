// ELÍPTICA · Edge Function "oc_enviar"
//  · {modo:"enviar", id}: envía la orden de compra al proveedor por correo (desde el correo de compras) y por WhatsApp,
//    con un enlace para que confirme la fecha de despacho (queda registrada en la OC).
//  · {modo:"recordar"} (pg_cron, lunes a sábado 8:15 a. m.): si el proveedor no ha confirmado la fecha (24 h después de enviada),
//    se la vuelve a pedir; si la fecha de despacho ya pasó y la OC no se ha recibido, le pide información. Un aviso por OC al día.
//  Lo llama la base (oc_enviar / oc_recordar) con la clave interna x-elp-token; el navegador nunca la ve.
// Secretos (Edge Functions → Secrets):
//   COMPRAS_GMAIL_USER, COMPRAS_GMAIL_APP_PASSWORD  → cuenta de correo de compras (contraseña de aplicación de Google)
//   WA_TOKEN, WA_PHONE_ID                            → WhatsApp Business Cloud API (Meta), opcional
//   WA_TEMPLATE (opcional, por defecto "orden_compra") → plantilla aprobada con 3 variables: proveedor, número de OC, enlace
import { createClient } from "npm:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const APP = "https://jose-manuel-hurtado.github.io/registro-produccion";
const TZ = "America/Bogota";
const cop = (v: unknown) => "$ " + Math.round(Number(v) || 0).toLocaleString("es-CO");
const fd = (t: string) => new Date(t + (t.length === 10 ? "T12:00:00" : "")).toLocaleDateString("es-CO", { timeZone: TZ, day: "2-digit", month: "2-digit", year: "numeric" });
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
const correos = (s: string | null) => String(s || "").split(/[;,\s]+/).filter((x) => /^\S+@\S+\.\S+$/.test(x));
const celular = (s: string | null) => { const m = String(s || "").replace(/[^\d]/g, " ").match(/\b(57)?(3\d{9})\b/); return m ? "57" + m[2] : null; };

type OC = { id: number; num: string; categoria: string; fecha: string; proveedor: string; obra: string | null; lineas: any[]; subtotal: number; iva: number; total: number;
  estado: string; notas: string | null; token: string; enviada_en: string | null; fecha_despacho: string | null; recibida_en: string | null; avisos: any[]; ultimo_aviso: string | null };

function html(o: OC, tipo: string) {
  const link = `${APP}/proveedor.html?t=${o.token}`;
  const intro = tipo === "enviar" ? `Adjuntamos nuestra <b>orden de compra ${esc(o.num)}</b>. Por favor confírmenos la <b>fecha de despacho</b> en el botón de abajo.`
    : tipo === "fecha" ? `Aún no hemos recibido la <b>fecha de despacho</b> de nuestra orden de compra <b>${esc(o.num)}</b>. Por favor confírmela en el botón de abajo.`
    : `Según lo confirmado, la orden de compra <b>${esc(o.num)}</b> se despachaba el <b>${fd(o.fecha_despacho!)}</b> y aún no la hemos recibido. Por favor infórmenos el estado del despacho y la nueva fecha.`;
  const vid = o.categoria === "vidrio";
  const filas = (o.lineas || []).map((l, k) => `<tr><td style="padding:6px;border-bottom:1px solid #ddd">${k + 1}</td><td style="padding:6px;border-bottom:1px solid #ddd"><b>${esc(l.ref || "")}</b> ${esc(l.desc || "")}${l.acab ? " · " + esc(l.acab) : ""}${vid && l.ancho ? ` · lámina ${l.ancho} × ${l.alto}` : ""}</td>
    <td style="padding:6px;border-bottom:1px solid #ddd;text-align:right">${l.cant ?? ""}${vid && l.m2 ? ` (${Number(l.m2).toFixed(2)} m²)` : ""}</td><td style="padding:6px;border-bottom:1px solid #ddd;text-align:right">${cop(l.unit)}</td><td style="padding:6px;border-bottom:1px solid #ddd;text-align:right">${cop(l.total)}</td></tr>`).join("");
  return `<div style="font-family:Arial,sans-serif;color:#272727;max-width:680px">
    <div style="background:#272727;color:#fff;padding:18px 22px"><div style="font-size:12px;letter-spacing:3px">ELÍPTICA · HURTADO SARMIENTO SAS</div><div style="font-size:22px;font-weight:bold;letter-spacing:2px;margin-top:6px">ORDEN DE COMPRA ${esc(o.num)}</div></div>
    <div style="padding:18px 22px;font-size:14px;line-height:1.5"><p>Señores <b>${esc(o.proveedor)}</b>:</p><p>${intro}</p>
    <p style="text-align:center;margin:22px 0"><a href="${link}" style="background:#272727;color:#fff;padding:12px 22px;text-decoration:none;font-weight:bold;letter-spacing:1px">CONFIRMAR FECHA DE DESPACHO</a></p>
    <p style="font-size:13px">Fecha de la orden: ${fd(o.fecha)}${o.obra ? ` · Obra / OP: <b>${esc(o.obra)}</b>` : ""}</p>
    <table style="width:100%;border-collapse:collapse;font-size:13px"><tr style="background:#272727;color:#fff"><th style="padding:6px">#</th><th style="padding:6px;text-align:left">Artículo</th><th style="padding:6px">Cant.</th><th style="padding:6px">${vid ? "Valor m²" : "V/unitario"}</th><th style="padding:6px">V/total</th></tr>${filas}
      <tr><td colspan="4" style="padding:6px;text-align:right">Subtotal</td><td style="padding:6px;text-align:right">${cop(o.subtotal)}</td></tr><tr><td colspan="4" style="padding:6px;text-align:right">IVA 19 %</td><td style="padding:6px;text-align:right">${cop(o.iva)}</td></tr>
      <tr><td colspan="4" style="padding:6px;text-align:right"><b>TOTAL</b></td><td style="padding:6px;text-align:right"><b>${cop(o.total)}</b></td></tr></table>
    ${o.notas ? `<p><b>Observaciones:</b> ${esc(o.notas)}</p>` : ""}
    <p style="font-size:12px;color:#555">Entregar en la Cra 16 Sur No. 67-406 Bodega 6, Zona Industrial El Papayo, Ibagué. El material favor enviarlo remisionado. Las facturas favor enviarlas antes del 25 de cada mes; de lo contrario serán devueltas.</p>
    <p style="font-size:12px;color:#555">Compras · Elíptica · Cel. 313 387 1747</p></div></div>`;
}

async function whatsapp(tel: string, o: OC, tipo: string) {
  const token = Deno.env.get("WA_TOKEN"), phone = Deno.env.get("WA_PHONE_ID");
  if (!token || !phone) return { ok: false, motivo: "WhatsApp API sin configurar" };
  const link = `${APP}/proveedor.html?t=${o.token}`;
  const tpl = Deno.env.get(tipo === "enviar" ? "WA_TEMPLATE" : "WA_TEMPLATE_RECORDAR") || (tipo === "enviar" ? "orden_compra" : "orden_compra_recordatorio");
  const r = await fetch(`https://graph.facebook.com/v20.0/${phone}/messages`, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ messaging_product: "whatsapp", to: tel, type: "template", template: { name: tpl, language: { code: "es" },
      components: [{ type: "body", parameters: [{ type: "text", text: o.proveedor }, { type: "text", text: o.num }, { type: "text", text: link }] }] } }) });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, motivo: r.ok ? null : (j?.error?.message || String(r.status)) };
}

// Copia oculta adicional de todos los correos de OC (tabla compras_ajustes, la cambia el director sin volver a publicar la función)
let copia: string[] = [];
async function avisar(o: OC, tipo: string, smtp: any, de: string) {
  const { data: p } = await db.from("compras_proveedores").select("email,whatsapp,telefono").eq("nombre", o.proveedor).maybeSingle();
  const para = correos(p?.email), tel = celular(p?.whatsapp || p?.telefono);
  const reg: any = { t: new Date().toISOString(), tipo, correo: null, whatsapp: null };
  const asunto = tipo === "enviar" ? `Orden de compra ${o.num} · Elíptica` : tipo === "fecha" ? `Confirme fecha de despacho · OC ${o.num} · Elíptica` : `OC ${o.num} sin recibir · Elíptica`;
  if (para.length) { try { await smtp.sendMail({ from: `"Compras Elíptica" <${de}>`, to: para.join(", "), bcc: [de, ...copia].join(", "), subject: asunto, html: html(o, tipo) }); reg.correo = para.join(", "); } catch (e) { reg.correo_error = String(e?.message || e); } }
  else reg.correo_error = "El proveedor no tiene correo";
  if (tel) { const w = await whatsapp(tel, o, tipo); reg.whatsapp = w.ok ? tel : null; if (!w.ok) reg.whatsapp_error = w.motivo; } else reg.whatsapp_error = "El proveedor no tiene celular";
  const patch: any = { avisos: [...(o.avisos || []), reg], ultimo_aviso: reg.t };
  if (tipo === "enviar") { patch.enviada_en = reg.t; if (o.estado === "borrador") patch.estado = "enviada"; }
  await db.from("compras_oc").update(patch).eq("id", o.id);
  return reg;
}

Deno.serve(async (req) => {
  try {
    const { data: cfg } = await db.from("push_config").select("cron_token").eq("id", 1).single();
    if (!cfg?.cron_token || req.headers.get("x-elp-token") !== cfg.cron_token) return new Response("no autorizado", { status: 401 });
    const de = Deno.env.get("COMPRAS_GMAIL_USER"), clave = Deno.env.get("COMPRAS_GMAIL_APP_PASSWORD");
    if (!de || !clave) return new Response("Faltan los secretos COMPRAS_GMAIL_USER y COMPRAS_GMAIL_APP_PASSWORD", { status: 500 });
    const smtp = nodemailer.createTransport({ host: "smtp.gmail.com", port: 465, secure: true, auth: { user: de, pass: clave } });
    const { data: aj } = await db.from("compras_ajustes").select("copia").eq("id", 1).maybeSingle();
    copia = correos(aj?.copia ?? null);
    const body = await req.json().catch(() => ({}));
    if (body?.modo === "enviar") {
      const { data: o } = await db.from("compras_oc").select("*").eq("id", body.id).single();
      if (!o) return new Response("OC no encontrada", { status: 404 });
      return Response.json(await avisar(o as OC, "enviar", smtp, de));
    }
    // recordar
    const hoy = new Date().toLocaleDateString("en-CA", { timeZone: TZ }), dia = Date.now() - 20 * 3600e3;
    const { data: l } = await db.from("compras_oc").select("*").in("estado", ["enviada", "parcial"]).not("enviada_en", "is", null);
    const out: any[] = [];
    for (const o of (l || []) as OC[]) {
      if (o.ultimo_aviso && new Date(o.ultimo_aviso).getTime() > dia) continue;
      if (!o.fecha_despacho && new Date(o.enviada_en!).getTime() < dia && (o.avisos || []).filter((a: any) => a.tipo === "fecha").length < 5) out.push([o.num, await avisar(o, "fecha", smtp, de)]);
      else if (o.fecha_despacho && o.fecha_despacho < hoy && !o.recibida_en) out.push([o.num, await avisar(o, "llegada", smtp, de)]);
    }
    return Response.json({ avisos: out.length, out });
  } catch (e) { return new Response(String(e?.message || e), { status: 500 }); }
});
