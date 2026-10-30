-- ════════════════════════════════════════════════════════════════
--  LA CITE · Vidrio por cortar de las OP 6291-5, 6291-9, 6291-11 y 6291-13 (pedido del director, 30/10/2026)
--  Estaban como "reproceso" porque se desmarcó el corte en Elíptica para indicar las láminas que faltan.
--  Quedan como piezas pendientes normales, sin ningún proceso, y se marcan desde Ártica ("Sin QR" o escáner) al estar listas.
--  Lo que ya estaba hecho (6291-5: 6 de 9 piezas) se conserva.
-- ════════════════════════════════════════════════════════════════
update public.art_piezas
   set base = greatest(0, base - rotas), rotas = 0, historica = (base - rotas) > 0
 where obra = 'LA CITE' and not tercero and op in ('6291-5', '6291-9', '6291-11', '6291-13') and rotas > 0
   and not exists (select 1 from public.art_registros g where g.pieza_id = art_piezas.id);
select string_agg(op || ' ' || ancho || 'x' || alto || ': ' || public.art_hechos(p, 'corte') || '/' || cant || ' cortadas', ' · ' order by op, id) as r
  from public.art_piezas p where obra = 'LA CITE' and op in ('6291-5', '6291-9', '6291-11', '6291-13');
