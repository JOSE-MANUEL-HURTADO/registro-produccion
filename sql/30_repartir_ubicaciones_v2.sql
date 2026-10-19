-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Repartir ubicaciones (versión 2: entiende más formatos)
--  Reparte un apartamento por unidad en las OP cuya ubicación trae la lista
--  completa. Entiende, por ejemplo:
--    "ALC AUX101/102/201"                     → ALC AUX 101, ALC AUX 102, ALC AUX 201
--    "SALA 603-703 ALCOBA PPAL.802-902"       → SALA 603, SALA 703, ALCOBA PPAL 802…
--    "APTO.1303-1403 PPAL 1205-1505 AUX"      → PPAL 1303, PPAL 1403, AUX 1205…
--    "WC.PPAL.101-201/3/4-301/2"              → 201/3/4 = 201, 203, 204
--    "APTO. 502-503-505"                      → APTO 502, APTO 503…
--  · Solo cambia unidades SIN INSTALAR y que no estén en un acta.
--  · Si hay unidades ya instaladas, su piso debe coincidir con apartamentos de
--    la lista (se descuentan); si no, la OP queda en "revisar".
--  · Si el número de apartamentos no cuadra con las unidades → "revisar".
--  Lo anterior queda en ubicaciones_repartidas. Se puede correr más de una vez.
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

-- Convierte la ubicación en una lista ordenada de (lugar, apartamento)
create or replace function public.ubic_partes(ub text) returns table(n int, lugar text, cod int)
language plpgsql immutable as $$
declare s text; t text[]; tok text; sep text := ''; base int; txt text := ''; g int := 0;
        gl text[] := '{}'; gc int[][] ; codes int[] := '{}'; gid int[] := '{}'; antes text[] := '{}'; despues text[] := '{}';
        modo_antes boolean; i int; lab text;
begin
  s := upper(coalesce(ub, ''));
  s := regexp_replace(s, '\mAPTOS?\.?\s*', ' ', 'g');
  for t in select regexp_matches(s, '(\d+)|([^\d]+)', 'g') loop
    tok := coalesce(t[1], t[2]);
    if t[1] is not null then
      if length(tok) between 3 and 4 then
        if g = 0 or txt ~ '[A-Z]' then            -- empieza un grupo nuevo
          g := g + 1; antes := antes || trim(txt); despues := despues || ''::text;
          if g > 1 then despues[g-1] := trim(txt); end if;
        end if;
        txt := ''; base := tok::int; codes := codes || base; gid := gid || g; sep := '';
      elsif length(tok) <= 2 and base is not null and txt ~ '^\s*/+\s*$' then   -- 201/3 → 203
        codes := codes || ((base / 100) * 100 + tok::int); gid := gid || g; txt := '';
      else
        txt := txt || tok;
      end if;
    else
      txt := txt || tok;
    end if;
  end loop;
  if g = 0 then return; end if;
  despues[g] := trim(txt);
  -- quitar puntuación de los rótulos
  for i in 1..g loop
    antes[i] := trim(both ' .-,/' from regexp_replace(antes[i], '[\s\-,/]+$', ''));
    despues[i] := trim(both ' .-,/' from despues[i]);
  end loop;
  modo_antes := antes[1] <> '';
  for i in 1..array_length(codes, 1) loop
    lab := case when modo_antes then antes[gid[i]] else despues[gid[i]] end;
    if lab is null or lab = '' then lab := 'APTO'; end if;
    n := i; lugar := regexp_replace(lab, '\s+', ' ', 'g'); cod := codes[i];
    return next;
  end loop;
end $$;

do $$
declare g record; it record; libres int[]; labs text[]; k int; pis int; nfijas int; ok boolean; partes int;
begin
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
              order by op_instalacion, id loop
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

select obra, op, unidades, apartamentos, repartidas, estado
from public.ubicaciones_resumen order by estado desc, obra, op;
