-- ════════════════════════════════════════════════════════════════
--  Personal retirado: Eduardo Betancourth y Duver Moreno ya no trabajan en Elíptica (30/10/2026)
--  Dejan de salir en la asistencia y en las listas para asignar ensamble; su historial se conserva.
-- ════════════════════════════════════════════════════════════════
update public.ensambladores set activo = false
 where upper(nombre) in ('EDUARDO BETANCOURTH', 'EDUARDO BETANCOUR', 'EDUARDO BETANCORTH', 'DUVER MORENO');
select string_agg(nombre || ': ' || case when activo then 'activo' else 'retirado' end, ', ') as r
  from public.ensambladores where upper(nombre) in ('EDUARDO BETANCOURTH', 'EDUARDO BETANCOUR', 'EDUARDO BETANCORTH', 'DUVER MORENO');
