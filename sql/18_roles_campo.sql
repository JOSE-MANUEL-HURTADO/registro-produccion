-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Usuarios de campo: CONDUCTOR, ENTREGA y RECIBE
--  Solo escanean y firman; no pueden consultar nada más de la base.
--   · conductor : escanea el QR de la remisión y hace firmar el recibido
--   · entrega   : escanea los ítems que entrega en obra y el QR del acta
--                 para hacer firmar el recibido
--   · recibe    : escanea el QR del acta o de la remisión, ve qué se le
--                 entregó y firma el recibido
--  Correr después de 15, 16 y 17. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════

-- 1. Roles permitidos
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe'));

-- 2. "Interno" = personal de la empresa. Los usuarios de campo NO leen tablas directamente.
create or replace function public.es_interno()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros'), false);
$$;
-- tiene_rol() protege la lectura de items y ensambladores: ahora solo internos
create or replace function public.tiene_rol()
returns boolean language sql stable security definer set search_path = public as $$
  select public.es_interno();
$$;
drop policy if exists actas_select on public.actas;
create policy actas_select on public.actas for select to authenticated using (public.es_interno());
drop policy if exists recepciones_select on public.recepciones;
create policy recepciones_select on public.recepciones for select to authenticated using (public.es_interno());
drop policy if exists rec_rem_select on public.recepciones_remision;
create policy rec_rem_select on public.recepciones_remision for select to authenticated using (public.es_interno());
drop policy if exists ordenes_ver on storage.objects;
create policy ordenes_ver on storage.objects for select to authenticated
  using (bucket_id = 'ordenes' and public.es_interno());

-- 3. El gerente puede asignar los roles nuevos
create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;

-- 4. Consultas mínimas por código escaneado (solo lo necesario para entregar / firmar)
create or replace function public.campo_remision(p_rem text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare filas jsonb; rec jsonb;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','conductor','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  select coalesce(jsonb_agg(f order by f.obra, f.op), '[]') into filas from (
    select i.obra, i.op, string_agg(distinct i.item, ', ') as item, string_agg(distinct i.diseno, ' / ') as dis,
           sum(coalesce(i.cant, 1))::int as n, min(i.fecha_despacho) as fecha
      from public.items i where i.remision = p_rem and i.despachado and i.op is not null
     group by i.obra, i.op) f;
  select to_jsonb(r) - 'firma' - 'usuario' into rec from public.recepciones_remision r where r.remision = p_rem;
  return jsonb_build_object('remision', p_rem, 'filas', filas, 'rec', rec);
end; $$;
revoke all on function public.campo_remision(text) from public, anon;
grant execute on function public.campo_remision(text) to authenticated;

create or replace function public.campo_acta(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a jsonb; its jsonb; recs jsonb;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','entrega','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  select jsonb_build_object('id', id, 'num', num, 'obra', obra, 'fecha', fecha, 'recibe', recibe, 'anulada', anulada) into a from public.actas where id = p_id;
  if a is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'op', op, 'op_instalacion', op_instalacion, 'item', item, 'piso', piso,
           'ubicacion', ubicacion, 'entregado_en', entregado_en, 'recepcion_id', recepcion_id) order by op_instalacion), '[]')
    into its from public.items where acta_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'cargo', cargo, 'creada', creada, 'n_items', n_items) order by id), '[]')
    into recs from public.recepciones where acta_id = p_id;
  return jsonb_build_object('acta', a, 'items', its, 'recs', recs);
end; $$;
revoke all on function public.campo_acta(bigint) from public, anon;
grant execute on function public.campo_acta(bigint) to authenticated;

create or replace function public.campo_items_op(p_op text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'obra', obra, 'op', op, 'op_instalacion', op_instalacion, 'item', item,
            'piso', piso, 'ubicacion', ubicacion, 'instalado', instalado, 'acta_id', acta_id, 'entregado_en', entregado_en,
            'recepcion_id', recepcion_id) order by id), '[]')
          from public.items where op = p_op);
end; $$;
revoke all on function public.campo_items_op(text) from public, anon;
grant execute on function public.campo_items_op(text) to authenticated;

-- 5. Permisos de las acciones de campo
create or replace function public.entregar_items(p_ids bigint[])
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  perform set_config('elp.acta', '1', true);
  update public.items set entregado_en = now(),
         entregado_por = (select nombre from public.perfiles where id = auth.uid())
   where id = any(p_ids) and acta_id is not null and instalado and entregado_en is null;
  get diagnostics cnt = row_count;
  return cnt;
end; $$;

create or replace function public.deshacer_entrega(p_ids bigint[])
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  perform set_config('elp.acta', '1', true);
  update public.items set entregado_en = null, entregado_por = null
   where id = any(p_ids) and recepcion_id is null;
  get diagnostics cnt = row_count;
  return cnt;
end; $$;

create or replace function public.firmar_recepcion(p_acta bigint, p_nombre text, p_cargo text, p_doc text, p_firma text)
returns table(id bigint, n integer)
language plpgsql security definer set search_path = public as $$
declare r_id bigint; cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','entrega','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de quien recibe'; end if;
  if coalesce(length(p_firma), 0) < 200 then raise exception 'Falta la firma'; end if;
  if length(p_firma) > 400000 then raise exception 'La firma es demasiado grande'; end if;
  perform pg_advisory_xact_lock(hashtext('recepcion:' || p_acta));
  insert into public.recepciones (acta_id, nombre, cargo, documento, firma)
    values (p_acta, trim(p_nombre), nullif(trim(p_cargo), ''), nullif(trim(p_doc), ''), p_firma)
    returning recepciones.id into r_id;
  perform set_config('elp.acta', '1', true);
  update public.items set recepcion_id = r_id
   where acta_id = p_acta and entregado_en is not null and recepcion_id is null;
  get diagnostics cnt = row_count;
  if cnt = 0 then raise exception 'No hay ítems entregados pendientes de firma en esta acta'; end if;
  update public.recepciones set n_items = cnt where recepciones.id = r_id;
  return query select r_id, cnt;
end; $$;

create or replace function public.firmar_remision(p_rem text, p_nombre text, p_cargo text, p_doc text, p_obs text, p_detalle jsonb, p_firma text)
returns bigint language plpgsql security definer set search_path = public as $$
declare r_id bigint; env integer; rec integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','conductor','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de quien recibe'; end if;
  if coalesce(length(p_firma), 0) < 200 then raise exception 'Falta la firma'; end if;
  if length(p_firma) > 400000 then raise exception 'La firma es demasiado grande'; end if;
  if not exists (select 1 from public.items where remision = p_rem and despachado) then
    raise exception 'No hay ítems despachados con la remisión %', p_rem;
  end if;
  if exists (select 1 from public.recepciones_remision where remision = p_rem) then
    raise exception 'La remisión % ya tiene recibido firmado', p_rem;
  end if;
  select coalesce(sum((e->>'enviado')::int), 0), coalesce(sum((e->>'recibido')::int), 0) into env, rec
    from jsonb_array_elements(coalesce(p_detalle, '[]'::jsonb)) e;
  insert into public.recepciones_remision (remision, nombre, cargo, documento, observaciones, detalle, n_enviado, n_recibido, firma)
    values (p_rem, trim(p_nombre), nullif(trim(p_cargo), ''), nullif(trim(p_doc), ''), nullif(trim(p_obs), ''), coalesce(p_detalle, '[]'::jsonb), env, rec, p_firma)
    returning id into r_id;
  return r_id;
end; $$;
