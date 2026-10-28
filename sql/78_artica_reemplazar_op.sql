-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Reemplazar una OP de clientes que venía con errores
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Al volver a cargar una OP de clientes que ya existe, la OP corregida REEMPLAZA a la anterior:
--   · Medida que sigue igual (ítem + tipo + ancho + alto): se actualiza (cantidad, canto, mecanizado,
--     forrado, observaciones, fechas) y conserva sus escaneos.
--   · Medida nueva: se agrega.
--   · Medida que ya no está: se borra si nadie la ha escaneado; si ya tiene escaneos se conserva
--     (con la nota "NO ESTÁ EN LA OP CORREGIDA") para no perder lo hecho en planta.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_ruta_fila(r jsonb)
returns text[] language plpgsql immutable as $$
declare v text[];
begin
  v := public.art_ruta(r->>'tipo', coalesce((r->>'forrado')::boolean, false));
  if coalesce(r->>'canto', '') = 'cc' then v := array_remove(v, 'pulido'); end if;
  if coalesce((r->>'tercero')::boolean, false) and not coalesce((r->>'mecanizado')::boolean, false) then v := array_remove(v, 'mecanizado'); end if;
  return v;
end; $$;

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
             canto = case when coalesce(r->>'canto', '') = 'cc' then 'cc' end, obs = nullif(btrim(r->>'obs'), ''),
             fecha_op = coalesce(nullif(r->>'fecha', '')::date, fecha_op), fecha_entrega = coalesce(nullif(r->>'entrega', '')::date, fecha_entrega),
             ruta = case when con_reg then ruta else public.art_ruta_fila(r) end
       where id = pz.id;
      usados := usados || pz.id; n_act := n_act + 1;
    else
      v_lin := v_lin + 1;
      insert into public.art_piezas (op, linea, obra, cliente, item, tipo, cant, ancho, alto, ruta, forrado, tercero, canto, obs, fecha_op, fecha_entrega)
      values (v_op, v_lin, null, r->>'cliente', r->>'item', r->>'tipo', (r->>'cant')::int, (r->>'ancho')::int, (r->>'alto')::int,
              public.art_ruta_fila(r), coalesce((r->>'forrado')::boolean, false), true,
              case when coalesce(r->>'canto', '') = 'cc' then 'cc' end, nullif(btrim(r->>'obs'), ''),
              nullif(r->>'fecha', '')::date, nullif(r->>'entrega', '')::date)
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

select 'Listo SQL 78 — reemplazar OP de clientes' as r;
