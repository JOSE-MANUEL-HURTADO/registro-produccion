-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · El acta de entrega se construye al escanear
--  · Al escanear un ítem instalado en "Entrega a obra", entra al acta
--    ABIERTA de su obra (si no hay una, se crea con el siguiente número).
--  · Al final, quien recibe revisa la lista (puede dejar por fuera lo que
--    no acepte), firma en la app y el acta queda FIRMADA (cerrada).
--  · Lo que se escanee después abre el acta siguiente.
--  Correr después de 15, 16, 17 y 18. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
alter table public.actas add column if not exists estado text;

-- Migración de lo que se haya hecho con el esquema anterior
do $$
declare o record; keep bigint;
begin
  perform set_config('elp.acta', '1', true);
  -- ítems asignados a un acta pero nunca entregados vuelven a quedar libres
  update public.items set acta_id = null where acta_id is not null and entregado_en is null;
  update public.actas a set estado = case
      when a.anulada then 'anulada'
      when exists (select 1 from public.recepciones r where r.acta_id = a.id) then 'firmada'
      when exists (select 1 from public.items i where i.acta_id = a.id) then 'abierta'
      else 'anulada' end
   where a.estado is null;
  -- máximo un acta abierta por obra: se juntan en la más reciente
  for o in select obra from public.actas where estado = 'abierta' group by obra having count(*) > 1 loop
    select max(id) into keep from public.actas where obra = o.obra and estado = 'abierta';
    update public.items set acta_id = keep where acta_id in (select id from public.actas where obra = o.obra and estado = 'abierta' and id <> keep);
    update public.actas set estado = 'anulada', anulada = true where obra = o.obra and estado = 'abierta' and id <> keep;
  end loop;
  update public.actas a set n_items = (select count(*) from public.items i where i.acta_id = a.id) where a.estado in ('abierta','firmada');
end $$;
alter table public.actas alter column estado set default 'abierta';
alter table public.actas alter column estado set not null;
create unique index if not exists actas_una_abierta on public.actas (obra) where estado = 'abierta';

-- Ya no se crean actas a mano
drop function if exists public.crear_acta(text, bigint[], date, text);

-- Escanear = entregar: el ítem (instalado y sin acta) entra al acta abierta de su obra
drop function if exists public.entregar_items(bigint[]);
create or replace function public.entregar_items(p_ids bigint[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare o record; a_id bigint; a_num integer; cnt integer; res jsonb := '[]'; quien text;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  perform set_config('elp.acta', '1', true);
  select nombre into quien from public.perfiles where id = auth.uid();
  for o in select distinct obra from public.items where id = any(p_ids) and instalado and acta_id is null loop
    perform pg_advisory_xact_lock(hashtext('acta:' || o.obra));
    select id, num into a_id, a_num from public.actas where obra = o.obra and estado = 'abierta';
    if a_id is null then
      select coalesce(max(num), 0) + 1 into a_num from public.actas where obra = o.obra;
      insert into public.actas (obra, num, fecha, estado) values (o.obra, a_num, current_date, 'abierta') returning id into a_id;
    end if;
    update public.items set acta_id = a_id, entregado_en = now(), entregado_por = quien
     where id = any(p_ids) and obra = o.obra and instalado and acta_id is null;
    get diagnostics cnt = row_count;
    update public.actas set n_items = (select count(*) from public.items where acta_id = a_id) where id = a_id;
    res := res || jsonb_build_object('obra', o.obra, 'acta_id', a_id, 'num', a_num, 'n', cnt);
  end loop;
  return res;
end; $$;
revoke all on function public.entregar_items(bigint[]) from public, anon;
grant execute on function public.entregar_items(bigint[]) to authenticated;

-- Sacar ítems del acta abierta (escaneo equivocado o la obra no lo recibe)
create or replace function public.deshacer_entrega(p_ids bigint[])
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  perform set_config('elp.acta', '1', true);
  update public.items i set acta_id = null, entregado_en = null, entregado_por = null
   where i.id = any(p_ids) and i.recepcion_id is null
     and exists (select 1 from public.actas a where a.id = i.acta_id and a.estado = 'abierta');
  get diagnostics cnt = row_count;
  update public.actas a set n_items = (select count(*) from public.items i where i.acta_id = a.id) where a.estado = 'abierta';
  delete from public.actas a where a.estado = 'abierta' and a.n_items = 0
    and not exists (select 1 from public.recepciones r where r.acta_id = a.id);
  return cnt;
end; $$;

-- Firmar = cerrar el acta. p_excluir: ítems que la obra no recibe (salen del acta)
drop function if exists public.firmar_recepcion(bigint, text, text, text, text);
create or replace function public.firmar_recepcion(p_acta bigint, p_nombre text, p_cargo text, p_doc text, p_firma text, p_excluir bigint[] default '{}')
returns table(id bigint, n integer)
language plpgsql security definer set search_path = public as $$
declare r_id bigint; cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','entrega','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de quien recibe'; end if;
  if coalesce(length(p_firma), 0) < 200 then raise exception 'Falta la firma'; end if;
  if length(p_firma) > 400000 then raise exception 'La firma es demasiado grande'; end if;
  perform pg_advisory_xact_lock(hashtext('recepcion:' || p_acta));
  if not exists (select 1 from public.actas where actas.id = p_acta and estado = 'abierta') then
    raise exception 'Esta acta ya está cerrada';
  end if;
  perform set_config('elp.acta', '1', true);
  update public.items set acta_id = null, entregado_en = null, entregado_por = null
   where acta_id = p_acta and items.id = any(coalesce(p_excluir, '{}'));
  if not exists (select 1 from public.items where acta_id = p_acta) then
    raise exception 'No quedan ítems para recibir en esta acta';
  end if;
  insert into public.recepciones (acta_id, nombre, cargo, documento, firma)
    values (p_acta, trim(p_nombre), nullif(trim(p_cargo), ''), nullif(trim(p_doc), ''), p_firma)
    returning recepciones.id into r_id;
  update public.items set recepcion_id = r_id where acta_id = p_acta;
  get diagnostics cnt = row_count;
  update public.recepciones set n_items = cnt where recepciones.id = r_id;
  update public.actas set estado = 'firmada', fecha = current_date, n_items = cnt, recibe = trim(p_nombre) where actas.id = p_acta;
  return query select r_id, cnt;
end; $$;
revoke all on function public.firmar_recepcion(bigint, text, text, text, text, bigint[]) from public, anon;
grant execute on function public.firmar_recepcion(bigint, text, text, text, text, bigint[]) to authenticated;

-- Anular: solo un acta abierta (sin firma); sus ítems vuelven a quedar sin entregar
create or replace function public.anular_acta(p_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if not public.es_gerente() then raise exception 'Solo el gerente puede anular actas'; end if;
  if exists (select 1 from public.actas where id = p_id and estado = 'firmada') then
    raise exception 'Esta acta ya está firmada: no se puede anular';
  end if;
  perform set_config('elp.acta', '1', true);
  update public.items set acta_id = null, entregado_en = null, entregado_por = null where acta_id = p_id;
  get diagnostics cnt = row_count;
  update public.actas set anulada = true, estado = 'anulada' where id = p_id;
  return cnt;
end; $$;

-- Consulta de campo: ahora incluye el estado del acta
create or replace function public.campo_acta(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a jsonb; its jsonb; recs jsonb;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','entrega','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  select jsonb_build_object('id', id, 'num', num, 'obra', obra, 'fecha', fecha, 'recibe', recibe, 'anulada', anulada, 'estado', estado) into a from public.actas where id = p_id;
  if a is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'op', op, 'op_instalacion', op_instalacion, 'item', item, 'piso', piso,
           'ubicacion', ubicacion, 'entregado_en', entregado_en, 'recepcion_id', recepcion_id) order by op_instalacion), '[]')
    into its from public.items where acta_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'cargo', cargo, 'creada', creada, 'n_items', n_items) order by id), '[]')
    into recs from public.recepciones where acta_id = p_id;
  return jsonb_build_object('acta', a, 'items', its, 'recs', recs);
end; $$;
