-- ════════════════════════════════════════════════════════════════
--  LA CITÉ · V-27: la unidad despachada el 30/10 (remisión 00-333) era la del PISO 2, no la del PISO 1.
--  Se intercambian sub-OP, piso y ubicación entre los dos registros (87777 ↔ 87778); el avance (procesos,
--  ensamble, despacho, remisión) queda en la unidad física despachada (id 87777, cuyo QR ya está pegado).
-- ════════════════════════════════════════════════════════════════
begin;
select set_config('elp.swap', '1', true);   -- permiso de intercambio (lo usa el control de cambios de la OP)
update public.items set op_instalacion = '6300-1.2~tmp' where id = 87777 and op_instalacion = '6300-1.1' and piso = 'PISO 1';
update public.items set op_instalacion = '6300-1.1', piso = 'PISO 1', ubicacion = 'BAÑO LOCAL 1' where id = 87778 and op_instalacion = '6300-1.2' and despachado = false;
update public.items set op_instalacion = '6300-1.2', piso = 'PISO 2', ubicacion = 'BAÑO PPAL 201' where id = 87777 and op_instalacion = '6300-1.2~tmp';
commit;
select id, op_instalacion, piso, ubicacion, status, remision from public.items where id in (87777, 87778) order by id;
