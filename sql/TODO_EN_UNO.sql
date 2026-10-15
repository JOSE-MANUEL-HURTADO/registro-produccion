-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · TODO EN UNO: roles Consulta y Cobros, copias de seguridad
--  y gestión de usuarios desde la app. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Roles nuevos: CONSULTA y COBROS
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  consulta : ve la producción y el dashboard. No modifica nada.
--  cobros   : ve la producción y marca cobrado despacho / instalación
--             (fecha y # de corte). No ve precios ni el dashboard.
-- ════════════════════════════════════════════════════════════════

-- 1. Roles permitidos
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros'));

-- 2. Funciones de permiso
create or replace function public.rol_actual()
returns text language sql stable security definer set search_path = public as $$
  select rol from public.perfiles where id = auth.uid();
$$;
create or replace function public.puede_registrar()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente'), false);
$$;
create or replace function public.ve_dashboard()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','consulta'), false);
$$;
create or replace function public.ve_cobros()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','cobros'), false);
$$;

-- 3. Solo gerente y asistente pueden modificar ítems
drop policy if exists items_update on public.items;
create policy items_update on public.items
  for update to authenticated using (public.puede_registrar()) with check (public.puede_registrar());

-- 4. Cobros SIN precio (para el rol cobros). La tabla items_comercial sigue siendo solo del gerente.
create or replace view public.items_cobros as
select c.item_id,
       c.cobrado_despacho, c.fecha_corte_despacho, c.num_corte_despacho,
       c.cobrado_instalacion, c.fecha_corte_instalacion, c.num_corte_instalacion
from public.items_comercial c
where public.ve_cobros();
revoke all on public.items_cobros from anon;
grant select on public.items_cobros to authenticated;

-- 5. Marcar / quitar cobro (solo gerente y cobros). Solo toca los campos de cobro, nunca el precio.
create or replace function public.marcar_cobros(p_ids bigint[], p_tipo text, p_cobrado boolean, p_fecha date, p_num text)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.ve_cobros() then raise exception 'Sin permiso para registrar cobros'; end if;
  if p_tipo not in ('despacho','instalacion') then raise exception 'Tipo de cobro no válido'; end if;
  if p_cobrado and p_fecha is null then raise exception 'Falta la fecha de corte'; end if;
  if p_tipo = 'despacho' then
    insert into public.items_comercial (item_id, cobrado_despacho, fecha_corte_despacho, num_corte_despacho)
    select i.id, p_cobrado, case when p_cobrado then p_fecha end, case when p_cobrado then p_num end
    from public.items i where i.id = any(p_ids) and i.despachado
    on conflict (item_id) do update set cobrado_despacho = excluded.cobrado_despacho,
      fecha_corte_despacho = excluded.fecha_corte_despacho, num_corte_despacho = excluded.num_corte_despacho;
  else
    insert into public.items_comercial (item_id, cobrado_instalacion, fecha_corte_instalacion, num_corte_instalacion)
    select i.id, p_cobrado, case when p_cobrado then p_fecha end, case when p_cobrado then p_num end
    from public.items i where i.id = any(p_ids) and i.instalado
    on conflict (item_id) do update set cobrado_instalacion = excluded.cobrado_instalacion,
      fecha_corte_instalacion = excluded.fecha_corte_instalacion, num_corte_instalacion = excluded.num_corte_instalacion;
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.marcar_cobros(bigint[], text, boolean, date, text) from public, anon;
grant execute on function public.marcar_cobros(bigint[], text, boolean, date, text) to authenticated;

-- 6. Datos del dashboard (gerente y consulta). Sin columnas de cobro.
create or replace view public.base_dashboard as
select
  i.obra as "OBRA", i.item as "ITEM", i.ubicacion as "UBICACIÓN", i.piso as "PISO", i.diseno as "DISEÑO",
  i.vidrio as "VIDRIO", i.ancho as "ANCHO", i.alto as "ALTO", i.m2 as "M2", i.op_instalacion as "OP INSTALACION",
  i.cortado as "CORTADO", i.troquelado as "TROQUELADO", i.mecanizado as "MECANIZADO", i.programado as "PROGRAMADO",
  i.vidrio_proc as "VIDRIO PROCESO", i.prealistado as "PREALISTADO",
  to_char(i.hora_inicio,'HH24:MI') as "HORA DE INICIO", i.dia_inicio as "DIA INICIO",
  i.ensamblador as "ENSAMBLADOR", i.status as "STATUS PLANTA",
  case when i.instalado then 'SI' else 'NO' end as "INSTALACION",
  public.mes_es(i.dia_inicio) as "MES PRODUCCION",
  extract(year from i.dia_inicio)::int as "AÑO PRODUCCION",
  c.precio as "PRECIO"
from public.items i
left join public.items_comercial c on c.item_id = i.id
where public.ve_dashboard()
order by i.id;
revoke all on public.base_dashboard from anon;
grant select on public.base_dashboard to authenticated;

-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Usuario CONSULTA: ve todo (precios, cobros, exportar), no modifica nada
--  Correr DESPUÉS de 4_roles_consulta_cobros.sql. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════

-- Leer precios y cobros (solo lectura)
drop policy if exists comercial_consulta on public.items_comercial;
create policy comercial_consulta on public.items_comercial
  for select to authenticated using (public.rol_actual() = 'consulta');

-- Exportar la base completa (misma vista de siempre, ahora también para consulta)
create or replace view public.base_exportable
with (security_invoker = true) as
select
  i.obra                         as "OBRA",
  i.item                         as "ITEM",
  i.ubicacion                    as "UBICACIÓN",
  i.sistema                      as "SISTEMA",
  i.serie                        as "SERIE",
  i.piso                         as "PISO",
  i.diseno                       as "DISEÑO",
  i.vidrio                       as "VIDRIO",
  i.ancho                        as "ANCHO",
  i.alto                         as "ALTO",
  i.m2                           as "M2",
  i.cant                         as "CANT",
  i.op                           as "OP",
  i.op_instalacion               as "OP INSTALACION",
  i.fecha_op                     as "FECHA OP",
  i.tiempo_op                    as "TIEMPO OP",
  i.puntos                       as "PUNTOS",
  i.cortado                      as "CORTADO",
  i.troquelado                   as "TROQUELADO",
  i.mecanizado                   as "MECANIZADO",
  i.programado                   as "PROGRAMADO",
  i.vidrio_proc                  as "VIDRIO PROCESO",
  i.prealistado                  as "PREALISTADO",
  to_char(i.hora_inicio,'HH24:MI') as "HORA DE INICIO",
  i.dia_inicio                   as "DIA INICIO",
  to_char(i.hora_final,'HH24:MI')  as "HORA FINAL",
  i.dia_final                    as "DIA FINAL",
  i.ensamblador                  as "ENSAMBLADOR",
  i.status                       as "STATUS PLANTA",
  public.semana_excel(i.dia_inicio)        as "SEMANA PRODUCCION",
  case when i.despachado then 'SI' else 'NO' end as "DESPACHO",
  i.fecha_despacho               as "FECHA DESPACHO",
  public.semana_excel(i.fecha_despacho)    as "SEMANA DESPACHO",
  extract(year from i.fecha_despacho)::int as "AÑO DESPACHO",
  i.remision                     as "REMISION",
  case c.cobrado_despacho when true then 'SI' when false then 'NO' end as "COBRADO PUESTO EN OBRA",
  c.fecha_corte_despacho         as "FECHA CORTE PUESTO EN OBRA",
  c.num_corte_despacho           as "# CORTE PUESTO EN OBRA",
  case when i.instalado then 'SI' else 'NO' end as "INSTALACION",
  i.instalador                   as "INSTALADOR",
  i.fecha_instalacion            as "FECHA INSTALACION",
  public.semana_excel(i.fecha_instalacion) as "SEMANA INSTALACION",
  public.mes_es(i.fecha_instalacion)       as "MES INSTALACION",
  extract(year from i.fecha_instalacion)::int as "AÑO INSTALACION",
  case c.cobrado_instalacion when true then 'SI' when false then 'NO' end as "COBRADO INSTALADO",
  c.fecha_corte_instalacion      as "FECHA CORTE INSTALADO",
  c.num_corte_instalacion        as "# CORTE INSTALADO",
  public.mes_es(i.dia_inicio)              as "MES PRODUCCION",
  extract(year from i.dia_inicio)::int     as "AÑO PRODUCCION",
  c.precio                       as "PRECIO"
from public.items i
left join public.items_comercial c on c.item_id = i.id
where public.rol_actual() in ('gerente','consulta')
order by i.id;

-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Registro de copias de seguridad
--  Correr después de 4_roles_consulta_cobros.sql y 5_consulta_ve_todo.sql
-- ════════════════════════════════════════════════════════════════
create table if not exists public.respaldos (
  id      bigserial primary key,
  cuando  timestamptz not null default now(),
  origen  text not null,          -- 'mac' (automática) o 'app' (manual)
  filas   integer,
  usuario uuid default auth.uid()
);
alter table public.respaldos enable row level security;

-- Solo el gerente ve el registro de copias
drop policy if exists respaldos_select on public.respaldos;
create policy respaldos_select on public.respaldos
  for select to authenticated using (public.es_gerente());

-- Anotar una copia: gerente (desde la app) o el usuario de respaldo del Mac (rol consulta)
create or replace function public.registrar_respaldo(p_origen text, p_filas integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual() in ('gerente','consulta'), false) is not true then
    raise exception 'Sin permiso';
  end if;
  insert into public.respaldos (origen, filas, usuario) values (left(p_origen, 20), p_filas, auth.uid());
end;
$$;
revoke all on function public.registrar_respaldo(text, integer) from public, anon;
grant execute on function public.registrar_respaldo(text, integer) to authenticated;

-- Gestión de usuarios desde la app (solo gerente)
create or replace function public.usuarios_lista()
returns table(id uuid, email text, nombre text, rol text, creado timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  return query select u.id, u.email::text, p.nombre, p.rol, u.created_at
    from auth.users u left join public.perfiles p on p.id = u.id order by u.created_at;
end; $$;
revoke all on function public.usuarios_lista() from public, anon;
grant execute on function public.usuarios_lista() to authenticated;

create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;
revoke all on function public.asignar_rol(uuid, text, text) from public, anon;
grant execute on function public.asignar_rol(uuid, text, text) to authenticated;

select 'Listo ✓' as resultado;
