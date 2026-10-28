-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Usuario que carga las OP de clientes y las manda a OPTIMA, fecha de OP
--  y Ártica más rápida
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Rol nuevo "artica_ops" (Ártica · OP de clientes y OPTIMA): carga OP de clientes de
--    Ártica (PDF o Excel), las exporta a OPTIMA e imprime sus etiquetas. Solo ve el vidrio
--    de clientes de Ártica; nada de Elíptica. No puede cargar OP de Elíptica.
--  · Cada medida guarda la fecha de la OP (y la de entrega, si la OP la trae) para
--    priorizar el corte. Las de Elíptica la toman de sus ítems.
--  · Las reglas de lectura se evalúan una sola vez por consulta (antes, una vez por fila):
--    Ártica carga mucho más rápido.
-- ════════════════════════════════════════════════════════════════

-- 1. Rol nuevo
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador','artica','artica_ops'));

create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador','artica','artica_ops') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;

create or replace function public.art_solo_clientes()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() = 'artica_ops', false);
$$;
grant execute on function public.art_solo_clientes() to authenticated;

create or replace function public.art_lee()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente','consulta','planta','artica_ops'), false);
$$;

-- 2. Lectura: una evaluación por consulta; artica_ops solo ve vidrio de clientes
drop policy if exists art_piezas_leer on public.art_piezas;
create policy art_piezas_leer on public.art_piezas for select to authenticated
  using ((select public.art_lee()) and (tercero or not (select public.art_solo_clientes())));
drop policy if exists art_registros_leer on public.art_registros;
create policy art_registros_leer on public.art_registros for select to authenticated using ((select public.art_lee()));

-- 3. Fecha de la OP y de entrega
alter table public.art_piezas add column if not exists fecha_op date;
alter table public.art_piezas add column if not exists fecha_entrega date;
create index if not exists art_piezas_pend on public.art_piezas (historica) where not historica;

create or replace function public.art_obra_eliptica()
returns trigger language plpgsql security definer set search_path = public as $$
declare o text;
begin
  if coalesce(new.tercero, false) then return new; end if;
  select i.obra into o from public.items i where i.op = new.op and i.obra is not null group by i.obra order by count(*) desc limit 1;
  if o is null and new.obra is not null then select a.obra into o from public.obras_alias a where a.alias = new.obra; end if;
  if o is not null then new.obra := o; end if;
  if new.fecha_op is null then select min(i.fecha_op) into new.fecha_op from public.items i where i.op = new.op; end if;
  return new;
end; $$;

update public.art_piezas p set fecha_op = x.f
  from (select op, min(fecha_op) f from public.items where op is not null group by op) x
 where p.op = x.op and not p.tercero and p.fecha_op is null;

-- 4. Cargar: el director carga todo; artica_ops solo OP de clientes
create or replace function public.art_cargar(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; v_ruta text[]; v_cc boolean; v_ter boolean; ops boolean := public.art_solo_clientes();
begin
  if not (public.es_gerente() or ops) then raise exception 'Sin permiso'; end if;
  for r in select * from jsonb_array_elements(p) loop
    v_ter := coalesce((r->>'tercero')::boolean, false);
    if ops and not v_ter then raise exception 'La OP % es de Elíptica: este usuario solo carga OP de clientes de Ártica', r->>'op'; end if;
    v_cc := coalesce(r->>'canto', '') = 'cc';
    v_ruta := public.art_ruta(r->>'tipo', coalesce((r->>'forrado')::boolean, false));
    if v_cc then v_ruta := array_remove(v_ruta, 'pulido'); end if;
    insert into public.art_piezas (op, linea, obra, cliente, item, tipo, cant, ancho, alto, ruta, forrado, tercero, canto, obs, fecha_op, fecha_entrega)
    values (r->>'op', (r->>'linea')::int, r->>'obra', r->>'cliente', r->>'item', r->>'tipo', (r->>'cant')::int,
            (r->>'ancho')::int, (r->>'alto')::int, v_ruta,
            coalesce((r->>'forrado')::boolean, false), v_ter,
            case when v_cc then 'cc' end, nullif(btrim(r->>'obs'), ''),
            nullif(r->>'fecha', '')::date, nullif(r->>'entrega', '')::date)
    on conflict (op, linea, tercero) do update set obra = excluded.obra, cliente = excluded.cliente, item = excluded.item,
      tipo = excluded.tipo, cant = excluded.cant, ancho = excluded.ancho, alto = excluded.alto,
      forrado = excluded.forrado, canto = excluded.canto, obs = excluded.obs,
      fecha_op = coalesce(excluded.fecha_op, art_piezas.fecha_op), fecha_entrega = coalesce(excluded.fecha_entrega, art_piezas.fecha_entrega),
      ruta = case when exists (select 1 from public.art_registros g where g.pieza_id = art_piezas.id) then art_piezas.ruta else excluded.ruta end;
    n := n + 1;
  end loop;
  perform public.art_marcar_historicas();
  return n;
end; $$;
revoke all on function public.art_cargar(jsonb) from public, anon;
grant execute on function public.art_cargar(jsonb) to authenticated;

-- 5. OPTIMA: artica_ops solo sobre vidrio de clientes
create or replace function public.art_optima_lote(p jsonb, p_lote text)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int; ops boolean := public.art_solo_clientes();
begin
  if not (public.es_gerente() or ops) then raise exception 'Sin permiso'; end if;
  if ops and exists (select 1 from jsonb_array_elements(p) x join public.art_piezas a on a.id = (x->>'id')::bigint where not a.tercero) then
    raise exception 'Este usuario solo exporta vidrio de clientes de Ártica';
  end if;
  v_n := nextval('public.art_lote_seq');
  update public.art_piezas a set optima_en = now(), optima_pend = (x->>'pend')::int, optima_lote = 'L' || v_n || ' · ' || p_lote,
         optima_lote_n = v_n, optima_pos = (x->>'pos')::int
    from jsonb_array_elements(p) x where a.id = (x->>'id')::bigint;
  return v_n;
end; $$;
revoke all on function public.art_optima_lote(jsonb, text) from public, anon;
grant execute on function public.art_optima_lote(jsonb, text) to authenticated;

create or replace function public.art_optima_devolver(p_ids bigint[])
returns int language plpgsql security definer set search_path = public as $$
declare n int; ops boolean := public.art_solo_clientes();
begin
  if not (public.es_gerente() or ops) then raise exception 'Sin permiso'; end if;
  update public.art_piezas set optima_en = null, optima_pend = null, optima_lote = null, optima_lote_n = null, optima_pos = null
   where id = any(p_ids) and (not ops or tercero);
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_optima_devolver(bigint[]) from public, anon;
grant execute on function public.art_optima_devolver(bigint[]) to authenticated;

-- 6. Vista de avance con las columnas nuevas
drop view if exists public.art_avance;
create view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo,
         case when p.optima_en is null then 0 else (select count(*)::int from public.art_registros g where g.pieza_id = p.id and g.estacion = 'corte' and g.creado > p.optima_en) end as corte_post_optima
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

select 'Listo SQL 75 — OP de clientes en Ártica' as r,
       (select count(*) from public.art_piezas where fecha_op is not null) con_fecha,
       (select count(*) from public.art_piezas where not historica) pendientes;
