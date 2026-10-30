-- ════════════════════════════════════════════════════════════════
--  LA CITE · V-27 (6300-1.1): se cargó en la orden de despacho N.º 16 (remisión 00-333) el 30/10/2026 a las 2:57 pm,
--  pero 10 minutos después se deshizo el escaneo desde la lista del escáner. El director confirma que sí salió en el camión:
--  se restaura el despacho con la misma remisión y fecha. La remisión 00-333 no ha sido firmada en obra.
-- ════════════════════════════════════════════════════════════════
-- La regla de despacho exige una orden abierta: se reabre la N.º 16 un momento y se vuelve a cerrar como cargada.
update public.ordenes_despacho set estado = 'abierta' where id = 16 and estado = 'cargada';
update public.items set despachado = true, fecha_despacho = date '2026-10-30', remision = '00-333'
 where id = 87777 and op_instalacion = '6300-1.1' and obra = 'LA CITE' and not coalesce(despachado, false);
update public.items set status = 'DESPACHADO' where id = 87777 and despachado and status <> 'DESPACHADO';
update public.ordenes_despacho set estado = 'cargada' where id = 16 and estado = 'abierta';
select string_agg(op_instalacion || ' ' || item || ' · ' || status, ', ' order by op_instalacion) as r from public.items where remision = '00-333';
