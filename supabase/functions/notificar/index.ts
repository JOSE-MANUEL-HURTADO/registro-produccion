// ELÍPTICA · Edge Function "notificar"
// La llama la base de datos (pg_net) cada vez que se crea una notificación.
// Envía el aviso a los celulares suscritos (menos al de quien hizo la acción):
// al director todas las acciones; a la asistente solo los avisos que son para ella.
// Supabase → Edge Functions → Deploy a new function → Via Editor → nombre: notificar → pegar todo → Deploy.
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  try {
    const { id } = await req.json();
    if (!id) return new Response("sin id", { status: 400 });
    // Toma la notificación una sola vez (si llega dos veces no la repite)
    const { data: n } = await db.from("notificaciones").update({ enviada: new Date().toISOString() })
      .eq("id", id).is("enviada", null).select().maybeSingle();
    if (!n) return new Response("ya enviada");
    const { data: cfg } = await db.from("push_config").select("*").eq("id", 1).single();
    webpush.setVapidDetails(cfg.subject, cfg.public_key, cfg.private_key);
    // Con destinatario (avisos para la asistente): solo a sus celulares.
    // Sin destinatario (cada acción en la app): a los celulares del director (rol gerente).
    let q = db.from("push_subs").select("*");
    if (n.para) q = q.eq("user_id", n.para);
    else {
      const { data: ger } = await db.from("perfiles").select("id").eq("rol", "gerente");
      q = q.in("user_id", (ger || []).map((g) => g.id));
    }
    if (n.actor) q = q.neq("user_id", n.actor);
    const { data: subs } = await q;
    const payload = JSON.stringify({ title: n.titulo, body: n.cuerpo, url: n.url || "./", tag: "elp-" + n.id });
    let ok = 0;
    await Promise.all((subs || []).map(async (s) => {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400, urgency: "high" });
        ok++;
      } catch (e) {
        const c = (e as { statusCode?: number }).statusCode;
        if (c === 404 || c === 410) await db.from("push_subs").delete().eq("endpoint", s.endpoint); // celular dado de baja
        else console.error("push", c, String(e));
      }
    }));
    return new Response(JSON.stringify({ enviados: ok }), { headers: { "Content-Type": "application/json" } });
  } catch (e) {
    console.error(e);
    return new Response(String(e), { status: 500 });
  }
});
