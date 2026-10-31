-- ════════════════════════════════════════════════════════════════
--  COMPRAS · Envío de la OC al proveedor (correo de compras + WhatsApp), confirmación de la fecha de despacho
--  por el proveedor (enlace) y recordatorios automáticos.
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
--  Requiere la función "oc_enviar" (supabase/functions/oc_enviar) y sus secretos (ver ese archivo).
-- ════════════════════════════════════════════════════════════════
alter table public.compras_proveedores add column if not exists whatsapp text;
alter table public.compras_oc add column if not exists token uuid not null default gen_random_uuid();
alter table public.compras_oc add column if not exists enviada_en timestamptz;
alter table public.compras_oc add column if not exists fecha_despacho date;          -- la que confirma el proveedor
alter table public.compras_oc add column if not exists despacho_conf_en timestamptz;
alter table public.compras_oc add column if not exists despacho_nota text;
alter table public.compras_oc add column if not exists recibida_en timestamptz;
alter table public.compras_oc add column if not exists avisos jsonb not null default '[]'::jsonb;   -- historial de correos/WhatsApp
alter table public.compras_oc add column if not exists ultimo_aviso timestamptz;
create unique index if not exists compras_oc_token_idx on public.compras_oc (token);

-- La app pide el envío: la base llama a la función (con la clave interna; el navegador nunca la ve)
create or replace function public.oc_enviar(p_id bigint)
returns bigint language plpgsql security definer set search_path = public as $$
declare cfg record;
begin
  if not coalesce(public.es_gerente(), false) then raise exception 'Sin permiso'; end if;
  select * into cfg from public.push_config where id = 1;
  if cfg.funcion_url is null then raise exception 'Falta la configuración de funciones (push_config)'; end if;
  return net.http_post(url := replace(cfg.funcion_url, '/notificar', '/oc_enviar'), body := jsonb_build_object('modo', 'enviar', 'id', p_id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'x-elp-token', cfg.cron_token));
end; $$;
revoke all on function public.oc_enviar(bigint) from public, anon;
grant execute on function public.oc_enviar(bigint) to authenticated;

-- Página del proveedor (sin usuario): ve su OC con el enlace secreto y confirma la fecha de despacho
create or replace function public.oc_publica(p_token uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('num', num, 'categoria', categoria, 'fecha', fecha, 'proveedor', proveedor, 'obra', obra, 'lineas', lineas,
    'subtotal', subtotal, 'iva', iva, 'total', total, 'estado', estado, 'notas', notas, 'fecha_despacho', fecha_despacho, 'despacho_nota', despacho_nota, 'recibida_en', recibida_en)
    from public.compras_oc where token = p_token and estado in ('enviada', 'parcial', 'recibida');
$$;
revoke all on function public.oc_publica(uuid) from public;
grant execute on function public.oc_publica(uuid) to anon, authenticated;

create or replace function public.oc_confirmar(p_token uuid, p_fecha date, p_nota text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.compras_oc;
begin
  select * into o from public.compras_oc where token = p_token and estado in ('enviada', 'parcial') for update;
  if o.id is null then raise exception 'Orden de compra no encontrada o ya cerrada'; end if;
  if p_fecha is null or p_fecha < (now() at time zone 'America/Bogota')::date - 1 or p_fecha > (now() at time zone 'America/Bogota')::date + 120 then raise exception 'Fecha no válida'; end if;
  update public.compras_oc set fecha_despacho = p_fecha, despacho_conf_en = now(), despacho_nota = left(nullif(btrim(p_nota), ''), 500),
    avisos = avisos || jsonb_build_array(jsonb_build_object('t', now(), 'tipo', 'confirmacion', 'fecha', p_fecha, 'nota', left(nullif(btrim(p_nota), ''), 500)))
   where id = o.id;
  begin perform public.notif_crear('Compras · ' || o.num, coalesce(o.proveedor, 'El proveedor') || ' confirmó despacho para el ' || to_char(p_fecha, 'DD/MM/YYYY')); exception when others then null; end;
  return jsonb_build_object('ok', true, 'num', o.num, 'fecha', p_fecha);
end; $$;
revoke all on function public.oc_confirmar(uuid, date, text) from public;
grant execute on function public.oc_confirmar(uuid, date, text) to anon, authenticated;

-- Recordatorios: lunes a sábado 8:15 a. m. (pide la fecha si no la han dado; avisa si ya pasó y no ha llegado)
create or replace function public.oc_recordar()
returns bigint language plpgsql security definer set search_path = public as $$
declare cfg record;
begin
  select * into cfg from public.push_config where id = 1;
  if cfg.funcion_url is null then return null; end if;
  return net.http_post(url := replace(cfg.funcion_url, '/notificar', '/oc_enviar'), body := '{"modo":"recordar"}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'x-elp-token', cfg.cron_token));
end; $$;
revoke all on function public.oc_recordar() from public, anon, authenticated;
do $$ begin perform cron.unschedule('elp-oc-recordar'); exception when others then null; end $$;
select cron.schedule('elp-oc-recordar', '15 13 * * 1-6', 'select public.oc_recordar()');

select 'Listo SQL 111 — envío de OC al proveedor' as r;
