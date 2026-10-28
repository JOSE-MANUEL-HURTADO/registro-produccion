-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Clientes: mecanizado y forrado solo si la OP lo dice
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  La OP de clientes (plantilla) dice por medida si va MECANIZADO y si va FORRADO.
--  Ruta de clientes: corte → [pulido] → [mecanizado] → lavado → [templado] → [forrado]
--    · pulido: no si es canto a canto · mecanizado: solo si dice SÍ · forrado: solo si dice SÍ
--    · laminado: nunca pulido, mecanizado ni templado (como siempre)
--  Lo de clientes ya cargado y sin escaneos queda sin mecanizado.
-- ════════════════════════════════════════════════════════════════
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

update public.art_piezas p set ruta = array_remove(p.ruta, 'mecanizado')
 where p.tercero and 'mecanizado' = any(p.ruta)
   and not exists (select 1 from public.art_registros g where g.pieza_id = p.id);

select 'Listo SQL 77 — clientes: mecanizado y forrado según la OP' as r,
       (select string_agg(op || ' ' || array_to_string(ruta, '>'), ', ') from (select distinct op, ruta from public.art_piezas where tercero) x) rutas_clientes;
