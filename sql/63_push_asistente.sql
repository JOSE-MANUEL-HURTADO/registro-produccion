-- ════════════════════════════════════════════════════════════════
--  AVISOS AL CELULAR (con la app cerrada) TAMBIÉN PARA LA ASISTENTE
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema. Requiere el SQL 50 y el 62.
-- ════════════════════════════════════════════════════════════════
--  · La asistente puede activar los avisos al celular (🔔 → "Activar en este celular").
--  · A ella solo le llegan los avisos del SQL 62 (órdenes de despacho, programaciones y
--    líneas de ensamble que crea el director). Al director le siguen llegando todas las acciones.
--  · Requiere la Edge Function "notificar" actualizada (filtra por destinatario).
-- ════════════════════════════════════════════════════════════════
alter table public.notificaciones add column if not exists para uuid;

drop policy if exists push_subs_propias on public.push_subs;
create policy push_subs_propias on public.push_subs for all to authenticated
  using (user_id = auth.uid() and (public.es_gerente() or public.rol_actual() = 'asistente'))
  with check (user_id = auth.uid() and (public.es_gerente() or public.rol_actual() = 'asistente'));

-- Notificación para una persona en particular
create or replace function public.notif_para(p_para uuid, p_titulo text, p_cuerpo text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare nid bigint; cfg public.push_config;
begin
  if not exists (select 1 from public.push_subs where user_id = p_para) then return; end if;
  insert into public.notificaciones (actor, para, titulo, cuerpo) values (auth.uid(), p_para, left(p_titulo, 120), left(p_cuerpo, 400)) returning id into nid;
  select * into cfg from public.push_config where id = 1;
  if cfg.funcion_url is null then return; end if;
  perform net.http_post(url := cfg.funcion_url, body := jsonb_build_object('id', nid),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'apikey', cfg.anon_key));
exception when others then
  raise warning 'notificación no enviada: %', sqlerrm;
end; $$;
revoke all on function public.notif_para(uuid, text, text) from public, anon, authenticated;

-- Los avisos del SQL 62 ahora también van al celular de cada asistente
create or replace function public.aviso_asistentes(p_tipo text, p_obra text, p_ops text, p_items text, p_n int, p_ref text)
returns void language plpgsql security definer set search_path = public as $$
declare a record; v_hora text := to_char(now() at time zone 'America/Bogota', 'HH12:MI') || case when extract(hour from now() at time zone 'America/Bogota') < 12 then ' a. m.' else ' p. m.' end;
begin
  if not coalesce(public.es_gerente(), false) then return; end if;
  for a in select pf.id from public.perfiles pf where pf.rol = 'asistente' and pf.id is distinct from auth.uid() loop
    insert into public.avisos (para, tipo, obra, ops, items, n, quien, ref)
    values (a.id, p_tipo, left(p_obra, 200), left(p_ops, 400), left(p_items, 400), p_n, public.notif_quien(), p_ref);
    perform public.notif_para(a.id, p_tipo || ' · ' || v_hora,
      concat_ws(' · ', 'OP ' || left(p_ops, 120), case when p_items is not null then 'Ítems ' || left(p_items, 80) end, p_obra, public.notif_quien()));
  end loop;
exception when others then
  raise warning 'aviso no creado: %', sqlerrm;
end; $$;
revoke all on function public.aviso_asistentes(text, text, text, text, int, text) from public, anon, authenticated;

select 'Listo SQL 63 — avisos al celular para la asistente' as resultado;
