-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Repartir ubicaciones que quedaron con la lista completa
--  Algunas OP se cargaron con todas las ubicaciones en cada unidad, p. ej.
--  "ALC AUX101/102/103/…/1202". Aquí se reparte un apartamento por unidad:
--      ALC AUX 101 → PISO 1,  ALC AUX 102 → PISO 1,  ALC AUX 201 → PISO 2 …
--  · Solo se cambian unidades SIN INSTALAR y que no estén en un acta.
--  · Las ya instaladas no se tocan; sus apartamentos se descuentan de la
--    lista según el piso que tienen, para no repetirlos.
--  · Si el número de apartamentos no cuadra con las unidades, esa OP no se
--    toca y aparece en el resumen como "revisar".
--  Lo anterior queda guardado en ubicaciones_repartidas. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.ubicaciones_repartidas (
  item_id bigint primary key, op text, obra text,
  ubic_antes text, piso_antes text, ubic_nueva text, piso_nuevo text,
  cuando timestamptz not null default now()
);
alter table public.ubicaciones_repartidas enable row level security;
create table if not exists public.ubicaciones_resumen (
  op text, obra text, lista text, unidades int, apartamentos int, repartidas int, estado text,
  cuando timestamptz not null default now()
);
alter table public.ubicaciones_resumen enable row level security;
delete from public.ubicaciones_resumen;

do $$
declare g record; it record; m text[]; pref text; cods text[]; libres text[]; k int; c text; pis int; n int; nfijas int;
begin
  perform set_config('elp.swap', '1', true);   -- permite cambiar ubicación y piso (ver SQL 24)
  for g in
    select op, obra, ubicacion as ub, count(*) as tot
    from public.items
    where op is not null and ubicacion ~ '\d{3,4}\s*[-/,]\s*\d{3,4}'
    group by op, obra, ubicacion
  loop
    m := regexp_match(g.ub, '^(.*?)\s*(\d{3,4}(?:\s*[-/,]\s*\d{3,4})+)\s*$');
    if m is null then
      insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, null, 0, 'revisar: formato no reconocido');
      continue;
    end if;
    pref := trim(m[1]);
    cods := regexp_split_to_array(regexp_replace(m[2], '\s', '', 'g'), '[-/,]');
    -- descontar los apartamentos de las unidades ya instaladas / en acta (por su piso)
    libres := cods; nfijas := 0;
    for it in select * from public.items where op = g.op and obra is not distinct from g.obra and ubicacion = g.ub
                and (coalesce(instalado, false) or acta_id is not null) loop
      nfijas := nfijas + 1;
      pis := nullif(regexp_replace(coalesce(it.piso, ''), '\D', '', 'g'), '')::int;
      k := null;
      if pis is not null then
        select i into k from generate_subscripts(libres, 1) i where (libres[i])::int / 100 = pis order by i limit 1;
      end if;
      if k is null then k := 1; end if;
      libres := libres[1:k-1] || libres[k+1:];
    end loop;
    select count(*) into n from public.items where op = g.op and obra is not distinct from g.obra and ubicacion = g.ub
      and not coalesce(instalado, false) and acta_id is null;
    if n = 0 then continue; end if;   -- solo quedan unidades instaladas: no hay nada que repartir
    if array_length(cods, 1) <> g.tot then
      insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, array_length(cods, 1), 0,
        'revisar: ' || g.tot || ' unidades y ' || array_length(cods, 1) || ' apartamentos');
      continue;
    end if;
    k := 0;
    for it in select * from public.items where op = g.op and obra is not distinct from g.obra and ubicacion = g.ub
                and not coalesce(instalado, false) and acta_id is null
              order by op_instalacion, id loop
      k := k + 1; c := libres[k];
      insert into public.ubicaciones_repartidas (item_id, op, obra, ubic_antes, piso_antes, ubic_nueva, piso_nuevo)
        values (it.id, it.op, it.obra, it.ubicacion, it.piso, pref || ' ' || c, 'PISO ' || (c::int / 100))
        on conflict (item_id) do update set ubic_nueva = excluded.ubic_nueva, piso_nuevo = excluded.piso_nuevo, cuando = now();
      update public.items set ubicacion = pref || ' ' || c, piso = 'PISO ' || (c::int / 100) where id = it.id;
    end loop;
    insert into public.ubicaciones_resumen values (g.op, g.obra, g.ub, g.tot, array_length(cods, 1), k,
      case when nfijas > 0 then 'repartida (' || nfijas || ' ya instaladas sin cambio)' else 'repartida' end);
  end loop;
  perform set_config('elp.swap', '', true);
end $$;

-- Resumen: una fila por OP
select obra, op, unidades, apartamentos, repartidas, estado
from public.ubicaciones_resumen order by estado desc, obra, op;
