-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Notificaciones al celular (web push) de cada acción en la app
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada acción de un usuario (un escaneo, una programación, un despacho, un acta
--  firmada, un cambio de precio…) genera UNA notificación agrupada, por ejemplo:
--  "Juan: Corte · 8 ítems · OP 6142-1 · CALLE 125". La función "notificar"
--  (Edge Function) la envía a los celulares del gerente que activaron avisos.
--  Las acciones del propio gerente no le llegan a él.
-- ════════════════════════════════════════════════════════════════
create extension if not exists pg_net with schema extensions;

-- 1. Configuración (llaves VAPID: solo las lee la Edge Function con la llave de servicio)
create table if not exists public.push_config (id int primary key default 1, public_key text not null, private_key text not null, subject text not null, funcion_url text not null, anon_key text not null);
alter table public.push_config enable row level security;   -- sin políticas: nadie la lee desde la app
insert into public.push_config (id, public_key, private_key, subject, funcion_url, anon_key)
values (1, 'BIs30XQvC_QlybChrV8iLMrTKXXveez0hBV8lBhw-lyIVGw6hj2RNbd6NVyTfQp3mDKULsFxYdJyB_pGlqj1XgA', 'PEGAR_AQUI_LA_LLAVE_PRIVADA', 'mailto:subgerencia@eliptica.com.co', 'https://fnwndrdebndlirmejlgb.supabase.co/functions/v1/notificar', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZud25kcmRlYm5kbGlybWVqbGdiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE5NDcxNzUsImV4cCI6MjEwNzUyMzE3NX0.zoTCGcjrsH3is2sQZEsGKkWpB_d_70dMEIJ1SySBges')
on conflict (id) do update set public_key = excluded.public_key, private_key = excluded.private_key, subject = excluded.subject, funcion_url = excluded.funcion_url, anon_key = excluded.anon_key;

-- 2. Celulares suscritos (solo el gerente)
create table if not exists public.push_subs (
  endpoint text primary key, user_id uuid not null default auth.uid(), p256dh text not null, auth text not null,
  dispositivo text, creada timestamptz not null default now()
);
alter table public.push_subs enable row level security;
drop policy if exists push_subs_propias on public.push_subs;
create policy push_subs_propias on public.push_subs for all to authenticated
  using (user_id = auth.uid() and public.es_gerente()) with check (user_id = auth.uid() and public.es_gerente());
grant select, insert, update, delete on public.push_subs to authenticated;

-- 3. Notificaciones (registro de lo enviado)
create table if not exists public.notificaciones (
  id bigserial primary key, actor uuid, titulo text not null, cuerpo text not null, url text,
  creada timestamptz not null default now(), enviada timestamptz
);
alter table public.notificaciones enable row level security;
drop policy if exists notif_gerente on public.notificaciones;
create policy notif_gerente on public.notificaciones for select to authenticated using (public.es_gerente());
grant select on public.notificaciones to authenticated;
grant all on public.notificaciones, public.push_subs, public.push_config to service_role;
grant usage, select on sequence public.notificaciones_id_seq to service_role;

-- Quién hizo la acción (nombre del perfil o correo)
create or replace function public.notif_quien()
returns text language sql stable security definer set search_path = public, auth as $$
  select coalesce((select nullif(btrim(nombre), '') from public.perfiles where id = auth.uid()),
                  (select split_part(email, '@', 1) from auth.users where id = auth.uid()), 'Sistema');
$$;

-- Registra la notificación y le avisa a la Edge Function (sin esperar respuesta)
create or replace function public.notif_crear(p_titulo text, p_cuerpo text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare nid bigint; cfg public.push_config;
begin
  if not exists (select 1 from public.push_subs) then return; end if;   -- nadie suscrito: no hace nada
  insert into public.notificaciones (actor, titulo, cuerpo) values (auth.uid(), left(p_titulo, 120), left(p_cuerpo, 400)) returning id into nid;
  select * into cfg from public.push_config where id = 1;
  if cfg.funcion_url is null then return; end if;
  perform net.http_post(url := cfg.funcion_url, body := jsonb_build_object('id', nid),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'apikey', cfg.anon_key));
exception when others then
  raise warning 'notificación no enviada: %', sqlerrm;   -- nunca bloquea la acción del usuario
end; $$;
revoke all on function public.notif_crear(text, text) from public, anon, authenticated;

-- 4. Ítems: una notificación por cada acción (un update de varios ítems = una sola)
create or replace function public.notif_items()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  acc text[] := '{}'; n int; ops text; obras text; extra text; r record;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' then return null; end if;   -- intercambios internos
  if TG_OP = 'INSERT' then
    select count(*), string_agg(distinct op, ', '), string_agg(distinct obra, ', ') into n, ops, obras from nuevos;
    if n = 0 then return null; end if;
    perform public.notif_crear('Elíptica · ' || coalesce(obras, ''), public.notif_quien() || ': cargó ' || n || ' ítem(s) nuevos · OP ' || coalesce(ops, ''));
    return null;
  elsif TG_OP = 'DELETE' then
    select count(*), string_agg(distinct obra, ', ') into n, obras from viejos;
    if n = 0 then return null; end if;
    perform public.notif_crear('Elíptica · ' || coalesce(obras, ''), public.notif_quien() || ': eliminó ' || n || ' ítem(s)');
    return null;
  end if;
  select
    count(*) filter (where nw.cortado = 'X' and od.cortado is distinct from 'X') c_x,
    count(*) filter (where nw.cortado = '+' and od.cortado is distinct from '+') c_p,
    count(*) filter (where od.cortado in ('X','+') and nw.cortado is null) c_q,
    count(*) filter (where nw.troquelado = 'X' and od.troquelado is distinct from 'X') t_x,
    count(*) filter (where nw.troquelado = '+' and od.troquelado is distinct from '+') t_p,
    count(*) filter (where od.troquelado in ('X','+') and nw.troquelado is null) t_q,
    count(*) filter (where nw.mecanizado = 'X' and od.mecanizado is distinct from 'X') m_x,
    count(*) filter (where nw.mecanizado = '+' and od.mecanizado is distinct from '+') m_p,
    count(*) filter (where od.mecanizado in ('X','+') and nw.mecanizado is null) m_q,
    count(*) filter (where nw.vidrio_proc = 'X' and od.vidrio_proc is distinct from 'X') v_x,
    count(*) filter (where nw.vidrio_proc = '+' and od.vidrio_proc is distinct from '+') v_p,
    count(*) filter (where nw.prealistado = 'X' and od.prealistado is distinct from 'X') p_x,
    count(*) filter (where nw.prealistado = '+' and od.prealistado is distinct from '+') p_p,
    count(*) filter (where nw.programacion_id is not null and od.programacion_id is null) prog,
    count(*) filter (where nw.programacion_id is null and od.programacion_id is not null) desprog,
    count(*) filter (where nw.ens_asignado is not null and nw.ens_asignado is distinct from od.ens_asignado) asig,
    count(*) filter (where nw.ens_asignado is null and od.ens_asignado is not null) desasig,
    count(*) filter (where nw.dia_inicio is not null and od.dia_inicio is null) ini,
    count(*) filter (where nw.dia_inicio is null and od.dia_inicio is not null) anul_ini,
    count(*) filter (where nw.dia_final is not null and od.dia_final is null) fin,
    count(*) filter (where coalesce(nw.despachado, false) and not coalesce(od.despachado, false)) desp,
    count(*) filter (where not coalesce(nw.despachado, false) and coalesce(od.despachado, false)) canc,
    count(*) filter (where coalesce(nw.instalado, false) and not coalesce(od.instalado, false)) inst,
    count(*) filter (where not coalesce(nw.instalado, false) and coalesce(od.instalado, false)) desinst,
    count(*) filter (where nw.acta_id is not null and od.acta_id is null) entr,
    count(*) filter (where row(nw.obra, nw.item, nw.diseno, nw.vidrio, nw.ancho, nw.alto, nw.m2, nw.cant, nw.op, nw.op_instalacion)
                     is distinct from row(od.obra, od.item, od.diseno, od.vidrio, od.ancho, od.alto, od.m2, od.cant, od.op, od.op_instalacion)) datos,
    count(distinct nw.id) total,
    string_agg(distinct nw.op, ', ') ops, string_agg(distinct nw.obra, ', ') obras,
    string_agg(distinct nw.ensamblador, ', ') filter (where nw.dia_inicio is not null and od.dia_inicio is null) ens,
    string_agg(distinct nw.ens_asignado, ', ') filter (where nw.ens_asignado is not null and nw.ens_asignado is distinct from od.ens_asignado) lin,
    string_agg(distinct nw.remision, ', ') filter (where coalesce(nw.despachado, false) and not coalesce(od.despachado, false)) rem,
    string_agg(distinct nw.instalador || coalesce(' · ' || nw.piso, ''), ', ') filter (where coalesce(nw.instalado, false) and not coalesce(od.instalado, false)) ins
  into r
  from nuevos nw join viejos od on od.id = nw.id;
  if r.c_x > 0 then acc := acc || ('Corte ' || r.c_x); end if;
  if r.c_p > 0 then acc := acc || ('Corte parcial (+) ' || r.c_p); end if;
  if r.c_q > 0 then acc := acc || ('quitó Corte ' || r.c_q); end if;
  if r.t_x > 0 then acc := acc || ('Troquelado ' || r.t_x); end if;
  if r.t_p > 0 then acc := acc || ('Troquelado parcial (+) ' || r.t_p); end if;
  if r.t_q > 0 then acc := acc || ('quitó Troquelado ' || r.t_q); end if;
  if r.m_x > 0 then acc := acc || ('Mecanizado ' || r.m_x); end if;
  if r.m_p > 0 then acc := acc || ('Mecanizado parcial (+) ' || r.m_p); end if;
  if r.m_q > 0 then acc := acc || ('quitó Mecanizado ' || r.m_q); end if;
  if r.v_x > 0 then acc := acc || ('Vidrio ' || r.v_x); end if;
  if r.v_p > 0 then acc := acc || ('Vidrio parcial (+) ' || r.v_p); end if;
  if r.p_x > 0 then acc := acc || ('Prealistado ' || r.p_x); end if;
  if r.p_p > 0 then acc := acc || ('Prealistado parcial (+) ' || r.p_p); end if;
  if r.prog > 0 then acc := acc || ('programó ' || r.prog); end if;
  if r.desprog > 0 then acc := acc || ('quitó de programación ' || r.desprog); end if;
  if r.asig > 0 then acc := acc || ('asignó a la línea de ' || coalesce(r.lin, '') || ' ' || r.asig); end if;
  if r.desasig > 0 then acc := acc || ('quitó de la línea ' || r.desasig); end if;
  if r.ini > 0 then acc := acc || ('inició ensamble (' || coalesce(r.ens, '') || ') ' || r.ini); end if;
  if r.anul_ini > 0 then acc := acc || ('anuló ensamble ' || r.anul_ini); end if;
  if r.fin > 0 then acc := acc || ('terminó ensamble ' || r.fin); end if;
  if r.desp > 0 then acc := acc || ('despachó ' || r.desp || coalesce(' · rem. ' || r.rem, '')); end if;
  if r.canc > 0 then acc := acc || ('canceló despacho ' || r.canc); end if;
  if r.inst > 0 then acc := acc || ('instaló ' || r.inst || coalesce(' (' || r.ins || ')', '')); end if;
  if r.desinst > 0 then acc := acc || ('quitó instalación ' || r.desinst); end if;
  if r.entr > 0 then acc := acc || ('entregó en acta ' || r.entr); end if;
  if r.datos > 0 then acc := acc || ('editó datos de la OP ' || r.datos); end if;
  if array_length(acc, 1) is null then return null; end if;   -- cambios internos (estado, fechas): no avisa
  perform public.notif_crear('Elíptica · ' || coalesce(r.obras, ''),
    public.notif_quien() || ': ' || array_to_string(acc, ' · ') || ' · OP ' || coalesce(left(r.ops, 80), ''));
  return null;
end; $$;
drop trigger if exists trg_notif_items_upd on public.items;
create trigger trg_notif_items_upd after update on public.items referencing old table as viejos new table as nuevos
  for each statement execute function public.notif_items();
drop trigger if exists trg_notif_items_ins on public.items;
create trigger trg_notif_items_ins after insert on public.items referencing new table as nuevos
  for each statement execute function public.notif_items();
drop trigger if exists trg_notif_items_del on public.items;
create trigger trg_notif_items_del after delete on public.items referencing old table as viejos
  for each statement execute function public.notif_items();

-- 5. Precios y cortes de cobro (una notificación por cambio)
create or replace function public.notif_precios()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; acc text[] := '{}';
begin
  if TG_OP = 'UPDATE' then
    select count(*) filter (where nw.precio is distinct from od.precio) pre,
           count(*) filter (where coalesce(nw.cobrado_despacho, false) and not coalesce(od.cobrado_despacho, false)) cd,
           count(*) filter (where coalesce(nw.cobrado_instalacion, false) and not coalesce(od.cobrado_instalacion, false)) ci,
           count(*) filter (where not coalesce(nw.cobrado_despacho, false) and coalesce(od.cobrado_despacho, false)
                               or not coalesce(nw.cobrado_instalacion, false) and coalesce(od.cobrado_instalacion, false)) qc,
           string_agg(distinct i.obra, ', ') obras
      into r from nuevos nw join viejos od on od.item_id = nw.item_id join public.items i on i.id = nw.item_id;
  else
    select count(*) filter (where nw.precio is not null) pre, 0 cd, 0 ci, 0 qc, string_agg(distinct i.obra, ', ') obras
      into r from nuevos nw join public.items i on i.id = nw.item_id;
  end if;
  if coalesce(r.pre, 0) > 0 then acc := acc || ('cambió el precio de ' || r.pre || ' ítem(s)'); end if;
  if coalesce(r.cd, 0) > 0 then acc := acc || ('corte de cobro de despacho: ' || r.cd || ' ítem(s)'); end if;
  if coalesce(r.ci, 0) > 0 then acc := acc || ('corte de cobro de instalación: ' || r.ci || ' ítem(s)'); end if;
  if coalesce(r.qc, 0) > 0 then acc := acc || ('quitó cobro de ' || r.qc || ' ítem(s)'); end if;
  if array_length(acc, 1) is null then return null; end if;
  perform public.notif_crear('Elíptica · ' || coalesce(r.obras, ''), public.notif_quien() || ': ' || array_to_string(acc, ' · '));
  return null;
end; $$;
drop trigger if exists trg_notif_precios_upd on public.items_comercial;
create trigger trg_notif_precios_upd after update on public.items_comercial referencing old table as viejos new table as nuevos
  for each statement execute function public.notif_precios();
drop trigger if exists trg_notif_precios_ins on public.items_comercial;
create trigger trg_notif_precios_ins after insert on public.items_comercial referencing new table as nuevos
  for each statement execute function public.notif_precios();

-- 6. Programaciones, órdenes de despacho, actas y recibidos firmados
create or replace function public.notif_docs()
returns trigger language plpgsql security definer set search_path = public as $$
declare q text := public.notif_quien();
begin
  if TG_TABLE_NAME = 'programaciones' then
    if TG_OP = 'INSERT' then perform public.notif_crear('Elíptica · ' || coalesce(new.obra, ''), q || ': creó la programación N.º ' || new.id || coalesce(' · para el ' || to_char(new.fecha_req, 'DD/MM'), ''));
    elsif new.estado is distinct from old.estado then perform public.notif_crear('Elíptica · ' || coalesce(new.obra, ''), q || ': programación N.º ' || new.id || ' ' || coalesce(new.estado, '')); end if;
  elsif TG_TABLE_NAME = 'ordenes_despacho' then
    if TG_OP = 'INSERT' then perform public.notif_crear('Elíptica · ' || coalesce(new.obra, ''), q || ': creó la orden de despacho N.º ' || new.id || ' · ' || coalesce(array_length(new.items, 1), 0) || ' ítems');
    elsif new.estado is distinct from old.estado then perform public.notif_crear('Elíptica · ' || coalesce(new.obra, ''), q || ': orden de despacho N.º ' || new.id || ' ' || coalesce(new.estado, '') || coalesce(' · rem. ' || new.remision, '')); end if;
  elsif TG_TABLE_NAME = 'actas' then
    if TG_OP = 'INSERT' then perform public.notif_crear('Elíptica · ' || new.obra, q || ': abrió el acta de entrega N.º ' || new.num);
    elsif coalesce(new.anulada, false) and not coalesce(old.anulada, false) then perform public.notif_crear('Elíptica · ' || new.obra, q || ': anuló el acta N.º ' || new.num);
    elsif new.estado is distinct from old.estado then perform public.notif_crear('Elíptica · ' || new.obra, q || ': acta N.º ' || new.num || ' ' || coalesce(new.estado, '')); end if;
  elsif TG_TABLE_NAME = 'recepciones' then
    perform public.notif_crear('Elíptica · acta firmada', new.nombre || coalesce(' (' || new.cargo || ')', '') || ' firmó el recibido de ' || new.n_items || ' ítem(s) · acta ' || new.acta_id);
  elsif TG_TABLE_NAME = 'recepciones_remision' then
    perform public.notif_crear('Elíptica · remisión recibida', new.nombre || coalesce(' (' || new.cargo || ')', '') || ' firmó la remisión ' || new.remision || ' · ' || new.n_recibido || ' de ' || new.n_enviado);
  end if;
  return null;
end; $$;
drop trigger if exists trg_notif_prog on public.programaciones;
create trigger trg_notif_prog after insert or update on public.programaciones for each row execute function public.notif_docs();
drop trigger if exists trg_notif_od on public.ordenes_despacho;
create trigger trg_notif_od after insert or update on public.ordenes_despacho for each row execute function public.notif_docs();
drop trigger if exists trg_notif_actas on public.actas;
create trigger trg_notif_actas after insert or update on public.actas for each row execute function public.notif_docs();
drop trigger if exists trg_notif_rec on public.recepciones;
create trigger trg_notif_rec after insert on public.recepciones for each row execute function public.notif_docs();
drop trigger if exists trg_notif_recrem on public.recepciones_remision;
create trigger trg_notif_recrem after insert on public.recepciones_remision for each row execute function public.notif_docs();

select 'Listo ✓ — falta crear la función "notificar" y activar los avisos en el celular' as resultado;
