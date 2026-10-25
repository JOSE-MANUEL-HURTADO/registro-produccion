-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Vidrio de OP trabajadas antes de la app = terminado
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Una OP-ítem cuyo vidrio entra a Ártica queda "terminada antes de la app" si en
--  Elíptica ya NO tiene ítems EN COLA, o si su obra está marcada como entregada.
--  Esas piezas cuentan como listas, no aparecen como pendientes ni se escanean, y no
--  suman en el rendimiento de las estaciones. Se aplica ahora y cada vez que se
--  cargan vidrios (al leer las órdenes PDF guardadas o al subir OP nuevas).
-- ════════════════════════════════════════════════════════════════
alter table public.art_piezas add column if not exists historica boolean not null default false;

create or replace function public.art_marcar_historicas()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.art_piezas p set historica = true
   where not p.historica and not p.tercero
     and exists (select 1 from public.items i where i.op = p.op)
     and (not exists (select 1 from public.items i where i.op = p.op and i.status = 'EN COLA')
          or exists (select 1 from public.items i join public.obras_cerradas c on c.obra = i.obra where i.op = p.op));
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_marcar_historicas() from public, anon, authenticated;

-- Al cargar vidrios se aplica la regla
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
  perform public.art_marcar_historicas();
  return n;
end; $$;
revoke all on function public.art_cargar(jsonb) from public, anon;
grant execute on function public.art_cargar(jsonb) to authenticated;

-- El escáner no registra piezas terminadas antes de la app
create or replace function public.art_escanear(p_codigo text, p_estacion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id bigint; pz public.art_piezas; hechos int; previos int; ant text; pos int; est text := lower(trim(p_estacion));
  cod text := upper(trim(coalesce(p_codigo, ''))); pre text; hoy int; quien text;
begin
  if not (public.es_gerente() or (public.rol_actual() = 'artica' and est = any(coalesce((select estaciones from public.perfiles where id = auth.uid()), '{}'))))
    then raise exception 'Sin permiso para la estación %', est; end if;
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
  if pz.historica then
    return jsonb_build_object('estado','ya','msg','Pieza terminada antes de la app', 'pieza', to_jsonb(pz), 'hechos', pz.cant, 'estacion', est, 'hoy', hoy);
  end if;
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

-- Vidrios listos para Elíptica: las históricas cuentan completas
create or replace function public.art_listos(p_ops text[])
returns table(op text, total bigint, listos bigint) language sql stable security definer set search_path = public as $$
  select p.op, sum(p.cant), sum(case when p.historica then p.cant else least(p.cant, (select count(*) from public.art_registros g where g.pieza_id = p.id and g.estacion = p.ruta[array_length(p.ruta,1)])) end)
    from public.art_piezas p where p.op = any(p_ops) and coalesce(public.rol_actual() in ('gerente','asistente','consulta','planta','cobros'), false)
   group by p.op;
$$;
grant execute on function public.art_listos(text[]) to authenticated;

-- La vista de avance incluye la marca (se recrea para tomar la columna nueva)
drop view if exists public.art_avance;
create view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

select 'Listo ✓ — OP sin ítems en cola marcadas como terminadas en Ártica' as resultado,
       public.art_marcar_historicas() as piezas_marcadas_ahora,
       (select count(*) from public.art_piezas where historica) as total_terminadas_antes,
       (select count(*) from public.art_piezas where not historica) as en_seguimiento;
