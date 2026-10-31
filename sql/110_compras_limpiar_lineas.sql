-- ════════════════════════════════════════════════════════════════
--  COMPRAS · Quitar de las OC importadas las "líneas" que eran el pie de la hoja (firmas, recibo, observaciones)
--  En algunas hojas de accesorios no había SUBTOTAL y se leyeron como artículos. Se borran las líneas sin cantidad,
--  sin precio y sin total. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
update public.compras_oc o set lineas = coalesce((
  select jsonb_agg(l) from jsonb_array_elements(o.lineas) l
   where coalesce(l->>'cant', l->>'unit', l->>'total') is not null
     and coalesce(l->>'ref', '') !~* '^(ELABOR|ESTADO|FIRMA|NOMBRE|OBSERVACION|RECIBE|RECIBO|TRANSPORTADORA|POR FAVOR|ATN|FLETE|ENTREGA)'), '[]'::jsonb)
 where origen = 'excel';
select (select sum(jsonb_array_length(lineas)) from public.compras_oc)::text || ' líneas' as r;
