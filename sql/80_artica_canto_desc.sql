-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Descripción del canto (pulido brillado, fileteado, canto a canto…)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  OPTIMA agrega la amoladura según el calibre: el Excel y la etiqueta van con la medida
--  exacta de la OP y con la descripción del canto. Cada medida de clientes guarda esa descripción.
-- ════════════════════════════════════════════════════════════════
alter table public.art_piezas add column if not exists canto_desc text;

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
    if v_ter and not coalesce((r->>'mecanizado')::boolean, false) then v_ruta := array_remove(v_ruta, 'mecanizado'); end if;
    insert into public.art_piezas (op, linea, obra, cliente, item, tipo, cant, ancho, alto, ruta, forrado, tercero, canto, obs, fecha_op, fecha_entrega, canto_desc)
    values (r->>'op', (r->>'linea')::int, r->>'obra', r->>'cliente', r->>'item', r->>'tipo', (r->>'cant')::int,
            (r->>'ancho')::int, (r->>'alto')::int, v_ruta,
            coalesce((r->>'forrado')::boolean, false), v_ter,
            case when r->>'canto' in ('cc','fil') then r->>'canto' end, nullif(btrim(r->>'obs'), ''),
            nullif(r->>'fecha', '')::date, nullif(r->>'entrega', '')::date, nullif(upper(btrim(r->>'canto_desc')), ''))
    on conflict (op, linea, tercero) do update set obra = excluded.obra, cliente = excluded.cliente, item = excluded.item,
      tipo = excluded.tipo, cant = excluded.cant, ancho = excluded.ancho, alto = excluded.alto,
      forrado = excluded.forrado, canto = excluded.canto, obs = excluded.obs, canto_desc = coalesce(excluded.canto_desc, art_piezas.canto_desc),
      fecha_op = coalesce(excluded.fecha_op, art_piezas.fecha_op), fecha_entrega = coalesce(excluded.fecha_entrega, art_piezas.fecha_entrega),
      ruta = case when exists (select 1 from public.art_registros g where g.pieza_id = art_piezas.id) then art_piezas.ruta else excluded.ruta end;
    n := n + 1;
  end loop;
  perform public.art_marcar_historicas();
  return n;
end; $$;
revoke all on function public.art_cargar(jsonb) from public, anon;
grant execute on function public.art_cargar(jsonb) to authenticated;


create or replace function public.art_cargar_op(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r jsonb; v_op text := p->0->>'op'; pz public.art_piezas; usados bigint[] := '{}'; v_lin int;
  n_act int := 0; n_new int := 0; n_del int := 0; consv text[] := '{}'; con_reg boolean;
begin
  if not (public.es_gerente() or public.art_solo_clientes()) then raise exception 'Sin permiso'; end if;
  if v_op is null then raise exception 'OP vacía'; end if;
  if exists (select 1 from jsonb_array_elements(p) x where x->>'op' is distinct from v_op or not coalesce((x->>'tercero')::boolean, false)) then
    raise exception 'Solo se reemplazan OP de clientes de Ártica, una a la vez';
  end if;
  select coalesce(max(linea), 0) into v_lin from public.art_piezas where op = v_op and tercero;
  for r in select * from jsonb_array_elements(p) loop
    select * into pz from public.art_piezas
     where op = v_op and tercero and not (id = any(usados))
       and upper(tipo) = upper(r->>'tipo') and ancho = (r->>'ancho')::int and alto = (r->>'alto')::int
       and coalesce(item, '') = coalesce(r->>'item', '')
     order by linea limit 1;
    if pz.id is not null then
      con_reg := exists (select 1 from public.art_registros g where g.pieza_id = pz.id);
      update public.art_piezas set cant = (r->>'cant')::int, cliente = r->>'cliente', forrado = coalesce((r->>'forrado')::boolean, false),
             canto = case when r->>'canto' in ('cc','fil') then r->>'canto' end, obs = nullif(btrim(r->>'obs'), ''), canto_desc = coalesce(nullif(upper(btrim(r->>'canto_desc')), ''), canto_desc),
             fecha_op = coalesce(nullif(r->>'fecha', '')::date, fecha_op), fecha_entrega = coalesce(nullif(r->>'entrega', '')::date, fecha_entrega),
             ruta = case when con_reg then ruta else public.art_ruta_fila(r) end
       where id = pz.id;
      usados := usados || pz.id; n_act := n_act + 1;
    else
      v_lin := v_lin + 1;
      insert into public.art_piezas (op, linea, obra, cliente, item, tipo, cant, ancho, alto, ruta, forrado, tercero, canto, obs, fecha_op, fecha_entrega, canto_desc)
      values (v_op, v_lin, null, r->>'cliente', r->>'item', r->>'tipo', (r->>'cant')::int, (r->>'ancho')::int, (r->>'alto')::int,
              public.art_ruta_fila(r), coalesce((r->>'forrado')::boolean, false), true,
              case when r->>'canto' in ('cc','fil') then r->>'canto' end, nullif(btrim(r->>'obs'), ''),
              nullif(r->>'fecha', '')::date, nullif(r->>'entrega', '')::date, nullif(upper(btrim(r->>'canto_desc')), ''))
      returning id into pz.id;
      usados := usados || pz.id; n_new := n_new + 1;
    end if;
    pz := null;
  end loop;
  -- Lo que ya no está en la OP corregida
  for pz in select * from public.art_piezas where op = v_op and tercero and not (id = any(usados)) loop
    if exists (select 1 from public.art_registros g where g.pieza_id = pz.id) then
      update public.art_piezas set obs = concat_ws(' · ', nullif(obs, ''), 'NO ESTÁ EN LA OP CORREGIDA') where id = pz.id and coalesce(obs, '') not like '%NO ESTÁ EN LA OP CORREGIDA%';
      consv := consv || (coalesce(pz.item || ' ', '') || pz.ancho || '×' || pz.alto);
    else
      delete from public.art_piezas where id = pz.id; n_del := n_del + 1;
    end if;
  end loop;
  return jsonb_build_object('op', v_op, 'actualizadas', n_act, 'nuevas', n_new, 'borradas', n_del, 'conservadas', to_jsonb(consv));
end; $$;
revoke all on function public.art_cargar_op(jsonb) from public, anon;
grant execute on function public.art_cargar_op(jsonb) to authenticated;



-- Lo ya cargado: la descripción sale de las observaciones ("CANTO PULIDO MATE · …")
update public.art_piezas
   set canto_desc = upper(btrim(substring(obs from '(?i)CANTO\s+(PULIDO\s+\w+|FILETEADO|A\s+CANTO|\w+)'))),
       obs = nullif(btrim(regexp_replace(obs, '(?i)^\s*CANTO\s+(PULIDO\s+\w+|FILETEADO|\w+)\s*(·\s*)?', '')), '')
 where tercero and canto_desc is null and obs ~* 'CANTO\s+';
update public.art_piezas set canto_desc = 'CANTO A CANTO' where canto_desc = 'A CANTO';

drop view if exists public.art_avance;
create view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo,
         case when p.optima_en is null then 0 else (select count(*)::int from public.art_registros g where g.pieza_id = p.id and g.estacion = 'corte' and g.creado > p.optima_en) end as corte_post_optima
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

select 'Listo SQL 80 — descripción del canto' as r,
       (select string_agg(op || ' ' || coalesce(canto_desc, '-') || ' / ' || coalesce(obs, '-'), ' || ') from public.art_piezas where tercero) clientes;
