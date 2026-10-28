-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · OP de clientes Ártica, canto a canto y posición de OPTIMA
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  1. Una OP de un cliente de Ártica puede tener el mismo número que una OP de Elíptica
--     sin tener nada que ver: ahora se guardan por separado (OP + línea + cliente/Elíptica)
--     y lo de clientes nunca toca los ítems de Elíptica.
--  2. Canto a canto (cc): se respeta la medida de la OP (no se pule ni se suman 4 mm).
--     Observaciones de la OP guardadas con cada medida.
--  3. Lotes de OPTIMA numerados (L1, L2…) y cada medida con su posición (1, 2, 3…),
--     la misma que OPTIMA le da al digitar el lote en orden. Va impresa en la etiqueta.
-- ════════════════════════════════════════════════════════════════

-- 1. Separar terceros de Elíptica
alter table public.art_piezas drop constraint if exists art_piezas_op_linea_key;
do $x$ begin
  alter table public.art_piezas add constraint art_piezas_op_linea_tercero_key unique (op, linea, tercero);
exception when duplicate_object or duplicate_table then null; end $x$;

-- 2. Canto, observaciones, posición y lote de OPTIMA
alter table public.art_piezas add column if not exists canto text;          -- 'cc' = canto a canto
alter table public.art_piezas add column if not exists obs text;            -- observaciones de la OP
alter table public.art_piezas add column if not exists optima_pos int;      -- posición en el lote de OPTIMA
alter table public.art_piezas add column if not exists optima_lote_n int;   -- número de lote (L1, L2…)
create sequence if not exists public.art_lote_seq;
grant usage, select on sequence public.art_lote_seq to service_role;

create or replace function public.art_cargar(p jsonb)
returns int language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; v_ruta text[]; v_cc boolean;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  for r in select * from jsonb_array_elements(p) loop
    v_cc := coalesce(r->>'canto', '') = 'cc';
    v_ruta := public.art_ruta(r->>'tipo', coalesce((r->>'forrado')::boolean, false));
    if v_cc then v_ruta := array_remove(v_ruta, 'pulido'); end if;
    insert into public.art_piezas (op, linea, obra, cliente, item, tipo, cant, ancho, alto, ruta, forrado, tercero, canto, obs)
    values (r->>'op', (r->>'linea')::int, r->>'obra', r->>'cliente', r->>'item', r->>'tipo', (r->>'cant')::int,
            (r->>'ancho')::int, (r->>'alto')::int, v_ruta,
            coalesce((r->>'forrado')::boolean, false), coalesce((r->>'tercero')::boolean, false),
            case when v_cc then 'cc' end, nullif(btrim(r->>'obs'), ''))
    on conflict (op, linea, tercero) do update set obra = excluded.obra, cliente = excluded.cliente, item = excluded.item,
      tipo = excluded.tipo, cant = excluded.cant, ancho = excluded.ancho, alto = excluded.alto,
      forrado = excluded.forrado, canto = excluded.canto, obs = excluded.obs,
      ruta = case when exists (select 1 from public.art_registros g where g.pieza_id = art_piezas.id) then art_piezas.ruta else excluded.ruta end;
    n := n + 1;
  end loop;
  perform public.art_marcar_historicas();
  return n;
end; $$;
revoke all on function public.art_cargar(jsonb) from public, anon;
grant execute on function public.art_cargar(jsonb) to authenticated;

-- Lo de clientes no cuenta para marcar ni desmarcar vidrio de Elíptica
create or replace function public.art_marcar_historicas()
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.art_piezas p set historica = true, base = p.cant
   where not p.historica and not p.tercero
     and exists (select 1 from public.items i where i.op = p.op)
     and (not exists (select 1 from public.items i where i.op = p.op and i.status = 'EN COLA')
          or exists (select 1 from public.items i join public.obras_cerradas c on c.obra = i.obra where i.op = p.op)
          or (not exists (select 1 from public.items i where i.op = p.op and i.vidrio_proc is distinct from 'X')
              and not exists (select 1 from public.art_registros g join public.art_piezas q on q.id = g.pieza_id where q.op = p.op and not q.tercero)));
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_marcar_historicas() from public, anon, authenticated;

create or replace function public.art_sync_vidrio()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_op text; v_ult text; v_ter boolean;
begin
  select op, ruta[array_length(ruta, 1)], tercero into v_op, v_ult, v_ter from public.art_piezas where id = new.pieza_id;
  if new.estacion = v_ult and not coalesce(v_ter, false) then perform public.art_sync_vidrio_op(v_op); end if;
  return null;
end; $$;

create or replace function public.art_listos(p_ops text[])
returns table(op text, total bigint, listos bigint) language sql stable security definer set search_path = public as $$
  select p.op, sum(p.cant), sum(public.art_hechos(p, p.ruta[array_length(p.ruta,1)]))
    from public.art_piezas p where p.op = any(p_ops) and not p.tercero
     and coalesce(public.rol_actual() in ('gerente','asistente','consulta','planta','cobros'), false)
   group by p.op;
$$;
grant execute on function public.art_listos(text[]) to authenticated;

create or replace function public.art_vidrio_cambio()
returns trigger language plpgsql security definer set search_path = public as $$
declare n_uni int; p public.art_piezas; k int; con_reg boolean;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' or new.op is null then return null; end if;
  if old.vidrio_proc is not distinct from new.vidrio_proc then return null; end if;
  select count(*) into n_uni from public.items where op = new.op;
  if old.vidrio_proc = 'X' then
    perform set_config('art.origen', 'Vidrio desmarcado en Elíptica · ' || coalesce(new.op_instalacion, new.op), true);
    -- Desmarcado: esa unidad vuelve a pendiente
    for p in select * from public.art_piezas where op = new.op and not tercero for update loop
      k := ceil(p.cant::numeric / greatest(n_uni, 1));
      con_reg := exists (select 1 from public.art_registros g where g.pieza_id = p.id);
      if p.base > 0 and not con_reg then
        update public.art_piezas set base = greatest(0, base - k), historica = (base - k) > 0 where id = p.id;
      else
        update public.art_piezas set rotas = rotas + least(k, public.art_hechos(p, p.ruta[array_length(p.ruta, 1)])) where id = p.id;
      end if;
    end loop;
  elsif new.vidrio_proc = 'X' then
    -- Marcado a mano: si toda la OP queda en X y no hay escaneos, vidrio terminado
    if not exists (select 1 from public.items i where i.op = new.op and i.vidrio_proc is distinct from 'X')
       and not exists (select 1 from public.art_registros g join public.art_piezas q on q.id = g.pieza_id where q.op = new.op and not q.tercero) then
      update public.art_piezas set historica = true, base = cant, rotas = 0 where op = new.op and not tercero;
    end if;
  end if;
  return null;
end; $$;

-- 3. Lote de OPTIMA numerado y posición de cada medida: p = [{"id":1,"pend":8,"pos":1}, …]
create or replace function public.art_optima_lote(p jsonb, p_lote text)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
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
declare n int;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  update public.art_piezas set optima_en = null, optima_pend = null, optima_lote = null, optima_lote_n = null, optima_pos = null where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_optima_devolver(bigint[]) from public, anon;
grant execute on function public.art_optima_devolver(bigint[]) to authenticated;

-- La vista de avance trae las columnas nuevas
drop view if exists public.art_avance;
create view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo,
         case when p.optima_en is null then 0 else (select count(*)::int from public.art_registros g where g.pieza_id = p.id and g.estacion = 'corte' and g.creado > p.optima_en) end as corte_post_optima
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

select 'Listo SQL 74 — clientes Ártica y posición OPTIMA' as r,
       (select count(*) from public.art_piezas where tercero) piezas_clientes,
       (select pg_get_constraintdef(oid) from pg_constraint where conname = 'art_piezas_op_linea_tercero_key') llave;
