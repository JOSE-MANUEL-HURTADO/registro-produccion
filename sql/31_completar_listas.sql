-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Completar listas de apartamentos y repartir (respuestas de José)
--  La OP impresa no alcanza a mostrar todos los apartamentos; el Excel de la OP sí.
--  · Vilanova T5 6185-8, 6185-9, 6185-14: faltaban 1203 y 1204.
--  · Izzi 96 6251-8: lista correcta 506-505-503-502-522-520-519-619-620-622-602-603-605-606.
--  Primero se corrige la lista (en todas las unidades de la OP, también las instaladas:
--  solo cambia el texto de la lista, no su piso), luego se reparte igual que el SQL 30.
--  Requiere haber corrido el SQL 30 (función ubic_partes y tablas).
-- ════════════════════════════════════════════════════════════════


create or replace function public.repartir_ubicaciones() returns void language plpgsql as $$
declare g record; it record; libres int[]; labs text[]; k int; pis int; nfijas int; ok boolean; partes int;
begin
  delete from public.ubicaciones_resumen;
  perform set_config('elp.swap', '1', true);
  for g in
    select op, obra, ubicacion as ub, count(*) as tot,
           count(*) filter (where not coalesce(instalado, false) and acta_id is null) as pend
    from public.items
    where op is not null and ubicacion ~ '\d{3,4}\s*[-/,]+\s*\d{1,4}'
    group by op, obra, ubicacion
  loop
    if g.pend = 0 then continue; end if;          -- todo instalado: no se toca
    select array_agg(x.cod order by x.n), array_agg(x.lugar order by x.n) into libres, labs from public.ubic_partes(g.ub) x;
    partes := coalesce(array_length(libres, 1), 0);
    if partes = 0 then
      insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, null, 0, 'revisar: formato no reconocido'); continue;
    end if;
    if partes <> g.tot then
      insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, partes, 0,
        'revisar: ' || g.tot || ' unidades y ' || partes || ' apartamentos'); continue;
    end if;
    -- descontar las ya instaladas por su piso
    nfijas := 0; ok := true;
    for it in select * from public.items where op = g.op and obra is not distinct from g.obra and ubicacion = g.ub
                and (coalesce(instalado, false) or acta_id is not null) loop
      nfijas := nfijas + 1;
      pis := nullif(regexp_replace(coalesce(it.piso, ''), '\D', '', 'g'), '')::int;
      k := null;
      if pis is not null then
        select i into k from generate_subscripts(libres, 1) i where libres[i] / 100 = pis order by i limit 1;
      end if;
      if k is null then ok := false; exit; end if;
      libres := libres[1:k-1] || libres[k+1:]; labs := labs[1:k-1] || labs[k+1:];
    end loop;
    if not ok then
      insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, partes, 0,
        'revisar: hay unidades instaladas cuyo piso no está en la lista'); continue;
    end if;
    k := 0;
    for it in select * from public.items where op = g.op and obra is not distinct from g.obra and ubicacion = g.ub
                and not coalesce(instalado, false) and acta_id is null
              order by length(op_instalacion), op_instalacion, id loop
      k := k + 1;
      insert into public.ubicaciones_repartidas (item_id, op, obra, ubic_antes, piso_antes, ubic_nueva, piso_nuevo)
        values (it.id, it.op, it.obra, it.ubicacion, it.piso, labs[k] || ' ' || libres[k], 'PISO ' || (libres[k] / 100))
        on conflict (item_id) do update set ubic_nueva = excluded.ubic_nueva, piso_nuevo = excluded.piso_nuevo, cuando = now();
      update public.items set ubicacion = labs[k] || ' ' || libres[k], piso = 'PISO ' || (libres[k] / 100) where id = it.id;
    end loop;
    insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, partes, k,
      case when nfijas > 0 then 'repartida (' || nfijas || ' ya instaladas sin cambio)' else 'repartida' end);
  end loop;
  perform set_config('elp.swap', '', true);
end $$;

do $$
begin
  perform set_config('elp.swap', '1', true);
  update public.items set ubicacion = ubicacion || '/1203/1204'
    where obra = 'VILANOVA T5' and op in ('6185-8', '6185-9', '6185-14')
      and ubicacion ~ '/1202$';
  update public.items set ubicacion = 'APTO. 506-505-503-502-522-520-519-619-620-622-602-603-605-606'
    where obra = 'IZZI 96' and op = '6251-8' and ubicacion ~ '^APTO\. 502-503';
  perform set_config('elp.swap', '', true);
end $$;

select public.repartir_ubicaciones();

-- Resumen del reparto
select obra, op, unidades, apartamentos, repartidas, estado
from public.ubicaciones_resumen order by estado desc, obra, op;
