-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Seguimiento del vidrio por pieza (OP-ítem + medida)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Las piezas salen de las líneas de vidrio del PDF de la OP (tipo, cantidad, ancho, alto).
--  · Ruta normal: corte → pulido → mecanizado → [templado] → lavado → [forrado]
--    (el templado se lava ANTES de templar y no se vuelve a lavar).
--    Laminado: corte → lavado → [forrado]. El último paso = listo / entregado.
--  · Cada escaneo suma 1 pieza en esa estación. Rojo si la pieza no ha pasado el paso anterior.
--  · Rol nuevo "artica" (operario): solo escanea en sus estaciones.
-- ════════════════════════════════════════════════════════════════

-- 1. Rol de operario de Ártica y sus estaciones
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador','artica'));
alter table public.perfiles add column if not exists estaciones text[];

create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador','artica') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;

create or replace function public.art_estaciones_usuario(p_id uuid, p_estaciones text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  update public.perfiles set estaciones = (select array_agg(e) from unnest(p_estaciones) e
     where e in ('corte','pulido','mecanizado','templado','lavado','forrado')) where id = p_id;
end; $$;
revoke all on function public.art_estaciones_usuario(uuid, text[]) from public, anon;
grant execute on function public.art_estaciones_usuario(uuid, text[]) to authenticated;

-- Quién ve Ártica: gerente, asistente y consulta (solo lectura), operarios de Ártica (solo por las funciones)
create or replace function public.art_lee()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente','consulta','planta'), false);
$$;

-- 2. Piezas (una fila por línea de vidrio de la OP: OP-ítem + medida)
create table if not exists public.art_piezas (
  id bigserial primary key,
  op text not null,                 -- OP-ítem, ej. 6291-7
  linea int not null,               -- orden de la línea de vidrio dentro de la OP
  obra text, cliente text, item text,
  tipo text not null,               -- ej. LAM CRUDO INCOL 3+3 (6 MM)
  cant int not null check (cant > 0),
  ancho int not null, alto int not null,
  ruta text[] not null,
  forrado boolean not null default false,
  tercero boolean not null default false,
  orden_corte int, lote_corte text,
  creada timestamptz not null default now(),
  unique (op, linea)
);
create index if not exists art_piezas_op on public.art_piezas (op);
alter table public.art_piezas enable row level security;
drop policy if exists art_piezas_leer on public.art_piezas;
create policy art_piezas_leer on public.art_piezas for select to authenticated using (public.art_lee());
grant select on public.art_piezas to authenticated;
grant all on public.art_piezas to service_role;
grant usage, select on sequence public.art_piezas_id_seq to service_role;

-- 3. Registros de cada escaneo (1 fila = 1 pieza pasó por una estación)
create table if not exists public.art_registros (
  id bigserial primary key,
  pieza_id bigint not null references public.art_piezas(id) on delete cascade,
  estacion text not null check (estacion in ('corte','pulido','mecanizado','templado','lavado','forrado')),
  creado timestamptz not null default now(),
  usuario uuid default auth.uid(),
  quien text
);
create index if not exists art_registros_pieza on public.art_registros (pieza_id, estacion);
create index if not exists art_registros_dia on public.art_registros (estacion, creado desc);
alter table public.art_registros enable row level security;
drop policy if exists art_registros_leer on public.art_registros;
create policy art_registros_leer on public.art_registros for select to authenticated using (public.art_lee());
grant select on public.art_registros to authenticated;
grant all on public.art_registros to service_role;
grant usage, select on sequence public.art_registros_id_seq to service_role;

-- 4. Prefijos de pistola (P1-, P2-…) → estación, para equipos compartidos
create table if not exists public.art_prefijos (prefijo text primary key, estacion text not null);
alter table public.art_prefijos enable row level security;
drop policy if exists art_prefijos_leer on public.art_prefijos;
create policy art_prefijos_leer on public.art_prefijos for select to authenticated using (true);
drop policy if exists art_prefijos_gerente on public.art_prefijos;
create policy art_prefijos_gerente on public.art_prefijos for all to authenticated using (public.es_gerente()) with check (public.es_gerente());
grant select, insert, update, delete on public.art_prefijos to authenticated;
grant all on public.art_prefijos to service_role;

-- Ruta según el tipo de vidrio
create or replace function public.art_ruta(p_tipo text, p_forrado boolean)
returns text[] language sql immutable as $$
  select case
    when upper(p_tipo) ~ '(^|[^A-Z])LAM' then array['corte','lavado']
    when upper(p_tipo) ~ 'TEMP' then array['corte','pulido','mecanizado','lavado','templado']
    else array['corte','pulido','mecanizado','lavado'] end
    || case when p_forrado then array['forrado'] else array[]::text[] end;
$$;

-- 5. Cargar / actualizar las piezas de las OP (desde la carga del PDF). No toca lo ya escaneado.
create or replace function public.art_cargar(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  for r in select * from jsonb_array_elements(p) loop
    insert into public.art_piezas (op, linea, obra, cliente, item, tipo, cant, ancho, alto, ruta, forrado, tercero)
    values (r->>'op', (r->>'linea')::int, r->>'obra', r->>'cliente', r->>'item', r->>'tipo', (r->>'cant')::int,
            (r->>'ancho')::int, (r->>'alto')::int,
            public.art_ruta(r->>'tipo', coalesce((r->>'forrado')::boolean, false)),
            coalesce((r->>'forrado')::boolean, false), coalesce((r->>'tercero')::boolean, false))
    on conflict (op, linea) do update set obra = excluded.obra, cliente = excluded.cliente, item = excluded.item,
      tipo = excluded.tipo, cant = excluded.cant, ancho = excluded.ancho, alto = excluded.alto,
      forrado = excluded.forrado, tercero = excluded.tercero,
      ruta = case when exists (select 1 from public.art_registros g where g.pieza_id = art_piezas.id) then art_piezas.ruta else excluded.ruta end;
    n := n + 1;
  end loop;
  return n;
end; $$;
revoke all on function public.art_cargar(jsonb) from public, anon;
grant execute on function public.art_cargar(jsonb) to authenticated;

-- Cambiar la ruta de una pieza (gerente), ej. un vidrio que no lleva mecanizado
create or replace function public.art_ruta_set(p_id bigint, p_ruta text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  update public.art_piezas set ruta = (select array_agg(e order by array_position(array['corte','pulido','mecanizado','lavado','templado','forrado'], e))
     from unnest(p_ruta) e where e in ('corte','pulido','mecanizado','lavado','templado','forrado')) where id = p_id;
end; $$;
revoke all on function public.art_ruta_set(bigint, text[]) from public, anon;
grant execute on function public.art_ruta_set(bigint, text[]) to authenticated;

-- Orden de corte (del plan optimizado de OPTIMA)
create or replace function public.art_orden_corte(p jsonb, p_lote text)
returns int language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  for r in select * from jsonb_array_elements(p) loop
    update public.art_piezas set orden_corte = (r->>'orden')::int, lote_corte = p_lote where id = (r->>'id')::bigint;
    n := n + 1;
  end loop;
  return n;
end; $$;
revoke all on function public.art_orden_corte(jsonb, text) from public, anon;
grant execute on function public.art_orden_corte(jsonb, text) to authenticated;

-- 6. Escanear: ok (verde) · fuera (rojo, no pasó el paso anterior) · noruta (rojo) · ya (negro) · nohay (rojo)
create or replace function public.art_escanear(p_codigo text, p_estacion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id bigint; pz public.art_piezas; hechos int; previos int; ant text; pos int; est text := lower(trim(p_estacion));
  cod text := upper(trim(coalesce(p_codigo, ''))); pre text; hoy int; quien text;
begin
  if not (public.es_gerente() or (public.rol_actual() = 'artica' and est = any(coalesce((select estaciones from public.perfiles where id = auth.uid()), '{}'))))
    then raise exception 'Sin permiso para la estación %', est; end if;
  -- Prefijo de pistola: "P2-ART:123" → la estación del prefijo P2
  pre := substring(cod from '^(P\d+)-');
  if pre is not null then
    select estacion into est from public.art_prefijos where prefijo = pre;
    if est is null then return jsonb_build_object('estado','nohay','msg','Prefijo ' || pre || ' sin estación asignada'); end if;
    if not (public.es_gerente() or est = any(coalesce((select estaciones from public.perfiles where id = auth.uid()), '{}'))) then
      return jsonb_build_object('estado','nohay','msg','Este usuario no registra ' || est); end if;
    cod := substring(cod from '^P\d+-(.*)$');
  end if;
  v_id := nullif(substring(cod from 'ART[:\-]?(\d+)'), '')::bigint;
  if v_id is null then return jsonb_build_object('estado','nohay','msg','Ese código no es una pieza de Ártica','estacion',est); end if;
  select * into pz from public.art_piezas where id = v_id for update;
  if pz.id is null then return jsonb_build_object('estado','nohay','msg','Pieza no encontrada','estacion',est); end if;
  select count(*) into hoy from public.art_registros where estacion = est and creado >= date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota';
  pos := array_position(pz.ruta, est);
  if pos is null then
    return jsonb_build_object('estado','noruta','msg','Esta pieza no pasa por ' || est, 'pieza', to_jsonb(pz), 'estacion', est, 'hoy', hoy);
  end if;
  select count(*) into hechos from public.art_registros where pieza_id = pz.id and estacion = est;
  if hechos >= pz.cant then
    return jsonb_build_object('estado','ya','msg','Ya se registraron las ' || pz.cant || ' piezas en ' || est, 'pieza', to_jsonb(pz), 'hechos', hechos, 'estacion', est, 'hoy', hoy);
  end if;
  if pos > 1 then
    ant := pz.ruta[pos - 1];
    select count(*) into previos from public.art_registros where pieza_id = pz.id and estacion = ant;
    if previos <= hechos then
      return jsonb_build_object('estado','fuera','msg','Falta ' || ant || ' (' || previos || ' de ' || pz.cant || ')', 'pieza', to_jsonb(pz), 'hechos', hechos, 'estacion', est, 'hoy', hoy);
    end if;
  end if;
  select nombre into quien from public.perfiles where id = auth.uid();
  insert into public.art_registros (pieza_id, estacion, quien) values (pz.id, est, quien);
  return jsonb_build_object('estado','ok','pieza', to_jsonb(pz), 'hechos', hechos + 1, 'estacion', est, 'hoy', hoy + 1,
    'listo', pos = array_length(pz.ruta, 1));
end; $$;
revoke all on function public.art_escanear(text, text) from public, anon;
grant execute on function public.art_escanear(text, text) to authenticated;

-- Deshacer el último escaneo propio de hoy en esa estación
create or replace function public.art_deshacer(p_estacion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.art_registros; pz public.art_piezas; sig text;
begin
  select * into r from public.art_registros where usuario = auth.uid() and estacion = lower(p_estacion)
     and creado >= date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota'
   order by id desc limit 1;
  if r.id is null then raise exception 'No hay nada tuyo para deshacer hoy en esta estación'; end if;
  select * into pz from public.art_piezas where id = r.pieza_id;
  sig := pz.ruta[array_position(pz.ruta, r.estacion) + 1];
  if sig is not null and (select count(*) from public.art_registros where pieza_id = pz.id and estacion = sig)
       >= (select count(*) from public.art_registros where pieza_id = pz.id and estacion = r.estacion) then
    raise exception 'No se puede deshacer: esa pieza ya pasó por %', sig;
  end if;
  delete from public.art_registros where id = r.id;
  return jsonb_build_object('pieza', to_jsonb(pz), 'estacion', r.estacion);
end; $$;
revoke all on function public.art_deshacer(text) from public, anon;
grant execute on function public.art_deshacer(text) to authenticated;

-- Contador del día y búsqueda para el operario (sin acceso directo a las tablas)
create or replace function public.art_mi_dia(p_estacion text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('hoy', count(*), 'mios', count(*) filter (where usuario = auth.uid()))
    from public.art_registros where estacion = lower(p_estacion)
     and creado >= date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota';
$$;
grant execute on function public.art_mi_dia(text) to authenticated;
create or replace function public.art_buscar(p_texto text)
returns setof public.art_piezas language sql stable security definer set search_path = public as $$
  select * from public.art_piezas where coalesce(public.rol_actual() in ('gerente','asistente','consulta','artica','planta'), false)
     and (op ilike '%' || trim(p_texto) || '%' or (ancho || 'X' || alto) ilike '%' || replace(upper(trim(p_texto)), ' ', '') || '%')
   order by op, linea limit 40;
$$;
grant execute on function public.art_buscar(text) to authenticated;

-- 7. Avance: hechos por estación de cada pieza
create or replace view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

-- Para ensamble en Elíptica: vidrios listos por OP-ítem (informativo)
create or replace function public.art_listos(p_ops text[])
returns table(op text, total bigint, listos bigint) language sql stable security definer set search_path = public as $$
  select p.op, sum(p.cant), sum(least(p.cant, (select count(*) from public.art_registros g where g.pieza_id = p.id and g.estacion = p.ruta[array_length(p.ruta,1)])))
    from public.art_piezas p where p.op = any(p_ops) and coalesce(public.rol_actual() in ('gerente','asistente','consulta','planta','cobros'), false)
   group by p.op;
$$;
grant execute on function public.art_listos(text[]) to authenticated;

-- Usuarios para la lista (estaciones)
create or replace function public.art_operarios()
returns table(id uuid, nombre text, estaciones text[]) language sql stable security definer set search_path = public as $$
  select id, nombre, estaciones from public.perfiles where rol = 'artica' and public.es_gerente();
$$;
grant execute on function public.art_operarios() to authenticated;
create or replace function public.art_mis_estaciones()
returns text[] language sql stable security definer set search_path = public as $$
  select case when public.es_gerente() then array['corte','pulido','mecanizado','templado','lavado','forrado'] else coalesce(estaciones, '{}') end
    from public.perfiles where id = auth.uid();
$$;
grant execute on function public.art_mis_estaciones() to authenticated;

select 'Listo ✓ — Ártica activada' as resultado;
