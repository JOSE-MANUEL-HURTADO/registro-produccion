-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Rol nuevo: INSTALADOR (solo escanea lo que instala)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  instalador: entra directo al escáner de Instalación, elige el piso y escanea.
--  Solo puede marcar instalado (fecha, instalador, piso del apartamento) lo
--  que ya está despachado, y deshacer lo que registró hoy. No ve precios ni
--  obras, no despacha, no entrega en obra, no cambia nada más.
-- ════════════════════════════════════════════════════════════════

-- 1. Rol permitido
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador'));

create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;

-- 2. Puede leer los ítems (para escanear la OP y ver lo pendiente por piso). Precios: no (están en otra tabla).
create or replace function public.tiene_rol()
returns boolean language sql stable security definer set search_path = public as $$
  select public.es_interno() or coalesce(public.rol_actual() = 'instalador', false);
$$;

-- 3. Registrar instalación, asignar piso y cambiar destino entre unidades despachadas de la misma OP
CREATE OR REPLACE FUNCTION public.registrar_instalacion(p_ids bigint[], p_instalado boolean, p_fecha date, p_instalador text)
 RETURNS SETOF items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','instalador'), false) is not true then
    raise exception 'Sin permiso para registrar instalación';
  end if;
  -- Instalador: solo instala lo despachado, y solo puede deshacer lo instalado hoy
  if public.rol_actual() = 'instalador' then
    if p_instalado and exists (select 1 from public.items where id = any(p_ids) and not coalesce(despachado, false)) then
      raise exception 'Hay ítems sin despachar: no se pueden instalar';
    end if;
    if not p_instalado and exists (select 1 from public.items where id = any(p_ids) and fecha_instalacion is distinct from (now() at time zone 'America/Bogota')::date) then
      raise exception 'Solo se puede deshacer una instalación registrada hoy';
    end if;
  end if;
  if p_instalado and p_fecha is null then raise exception 'Falta la fecha de instalación'; end if;
  return query
    update public.items
       set instalado = p_instalado,
           fecha_instalacion = case when p_instalado then p_fecha end,
           instalador = case when p_instalado then nullif(trim(upper(p_instalador)),'') end
     where id = any(p_ids)
    returning *;
end; $function$;

CREATE OR REPLACE FUNCTION public.asignar_piso_instalacion(p_id bigint, p_piso text)
 RETURNS SETOF items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; pis int; c int; lug text; usados text[];
begin
  if not (public.puede_registrar() or public.rol_actual() in ('cobros','instalador')) then raise exception 'Sin permiso'; end if;
  select * into it from public.items where id = p_id for update;
  if it.id is null then raise exception 'Ítem no encontrado'; end if;
  if coalesce(it.instalado, false) or it.acta_id is not null then raise exception 'El ítem ya está instalado'; end if;
  if (select count(*) from public.ubic_partes(it.ubicacion)) < 2 then
    raise exception 'Este ítem ya tiene su apartamento definido (%)', it.ubicacion;
  end if;
  pis := nullif(regexp_replace(coalesce(p_piso, ''), '\D', '', 'g'), '')::int;
  if pis is null then raise exception 'Piso no válido'; end if;
  select array_agg(ubicacion) into usados from public.items
    where op = it.op and obra is not distinct from it.obra and id <> it.id;
  select x.cod, x.lugar into c, lug from public.ubic_partes(it.ubicacion) x
    where x.cod / 100 = pis and not ((x.lugar || ' ' || x.cod) = any(coalesce(usados, '{}')))
    order by x.n limit 1;
  perform set_config('elp.swap', '1', true);
  update public.items set piso = 'PISO ' || pis,
         ubicacion = case when c is not null then lug || ' ' || c else ubicacion end
   where id = it.id;
  perform set_config('elp.swap', '', true);
  return query select * from public.items where id = it.id;
end; $function$;

CREATE OR REPLACE FUNCTION public.intercambiar_destino(p_a bigint, p_b bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.items; b public.items;
begin
  if not (public.puede_registrar() or public.rol_actual() in ('cobros','instalador')) then raise exception 'Sin permiso'; end if;
  select * into a from public.items where id = p_a for update;
  select * into b from public.items where id = p_b for update;
  if a.id is null or b.id is null then raise exception 'Ítem no encontrado'; end if;
  if a.op is distinct from b.op or a.obra is distinct from b.obra then raise exception 'Solo se intercambian unidades de la misma OP y obra'; end if;
  if coalesce(a.instalado, false) or coalesce(b.instalado, false) or a.acta_id is not null or b.acta_id is not null then
    raise exception 'No se intercambian unidades ya instaladas o en un acta';
  end if;
  if coalesce(a.despachado, false) <> coalesce(b.despachado, false) then
    raise exception 'Solo se intercambian dos unidades sin despachar o dos ya despachadas';
  end if;
  if not coalesce(a.despachado, false) and public.rol_actual() in ('cobros','instalador') then raise exception 'Sin permiso'; end if;
  insert into public.intercambios_destino (op, item_a, op_inst_a, item_b, op_inst_b, ubic_a, piso_a, ubic_b, piso_b)
    values (a.op, a.id, a.op_instalacion, b.id, b.op_instalacion, a.ubicacion, a.piso, b.ubicacion, b.piso);
  perform set_config('elp.swap', '1', true);
  update public.items set ubicacion = b.ubicacion, piso = b.piso where id = a.id;
  update public.items set ubicacion = a.ubicacion, piso = a.piso where id = b.id;
  perform set_config('elp.swap', '', true);
end; $function$;

select 'Listo ✓ — ya puedes asignar el rol "Instalador (solo escanea instalación)" en Usuarios' as resultado;
