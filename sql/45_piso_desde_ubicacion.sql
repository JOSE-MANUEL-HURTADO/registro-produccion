-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Llenar el piso que está escrito en la ubicación
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Ítems SIN piso cuya ubicación dice el piso, p. ej. OP 6284:
--   · "… SERIE 4 PISO 3"              → piso PISO 3
--   · "… SERIE 1 PISO 4-PISO 6-PISO 11" con 3 unidades → una unidad por piso
--     (4, 6 y 11, en orden de la OP) y la ubicación de cada una queda con su piso
--   · "… CUBIERTA"                    → piso CUBIERTA
--  Si la lista de pisos no cuadra con las unidades, esas se dejan como están.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.pisos_desde_ubicacion (
  item_id bigint, op_instalacion text, ubic_antes text, ubic_despues text, piso text, cuando timestamptz default now()
);

do $$
declare
  g record; u record; pisos text[]; k int; base text; n int := 0;
begin
  perform set_config('elp.swap', '1', true);   -- permite cambiar ubicación y piso (solo durante este arreglo)
  for g in select obra, op, ubicacion, array_agg(id order by coalesce(nullif(regexp_replace(op_instalacion, '^.*\.', ''), '')::int, 0), id) ids
             from public.items
            where piso is null and ubicacion is not null
            group by obra, op, ubicacion loop
    select array_agg('PISO ' || (m[1])::int order by ord) into pisos
      from regexp_matches(g.ubicacion, 'PISO\s*[#.\-]?\s*(\d+)', 'gi') with ordinality as t(m, ord);
    if pisos is null and g.ubicacion ~* '\mCUBIERTA\M' then pisos := array['CUBIERTA']; end if;
    if pisos is null then continue; end if;
    if (select count(distinct x) from unnest(pisos) x) = 1 then
      -- un solo piso: todas las unidades
      insert into public.pisos_desde_ubicacion (item_id, op_instalacion, ubic_antes, ubic_despues, piso)
        select id, op_instalacion, ubicacion, ubicacion, pisos[1] from public.items where id = any(g.ids);
      update public.items set piso = pisos[1] where id = any(g.ids);
      n := n + array_length(g.ids, 1);
    elsif array_length(pisos, 1) = array_length(g.ids, 1)
          and (select count(*) from public.items where op = g.op and obra is not distinct from g.obra and ubicacion = g.ubicacion) = array_length(g.ids, 1) then
      -- una unidad por piso, en el orden de la OP
      base := btrim(regexp_replace(regexp_replace(g.ubicacion, 'PISO\s*[#.\-]?\s*\d+(\s*[-–,/y]\s*PISO\s*[#.\-]?\s*\d+)+', '', 'i'), '\s+', ' ', 'g'));
      for k in 1 .. array_length(g.ids, 1) loop
        insert into public.pisos_desde_ubicacion (item_id, op_instalacion, ubic_antes, ubic_despues, piso)
          select id, op_instalacion, ubicacion, btrim(base || ' ' || pisos[k]), pisos[k] from public.items where id = g.ids[k];
        update public.items set piso = pisos[k], ubicacion = btrim(base || ' ' || pisos[k]) where id = g.ids[k];
        n := n + 1;
      end loop;
    else
      raise notice 'Sin cambiar (no cuadra): OP % · "%" · % unidades, % pisos', g.op, g.ubicacion, array_length(g.ids, 1), array_length(pisos, 1);
    end if;
  end loop;
  raise notice 'Ítems con piso asignado: %', n;
end $$;

select op_instalacion, ubicacion, piso from public.items where op like '6284%' order by op, op_instalacion;
