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

-- 7. Comprobación: debe mostrar los 4 roles posibles y tus usuarios actuales
select u.email, p.rol from public.perfiles p join auth.users u on u.id = p.id order by p.rol;
