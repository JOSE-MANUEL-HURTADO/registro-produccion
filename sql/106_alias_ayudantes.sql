-- ════════════════════════════════════════════════════════════════
--  MANO DE OBRA · Ayudantes de instalación ↔ nómina (como los nombra el director)
--  Bogotá: Johan González, Elvis Guerra, Johnny Sanabria · Ibagué: Edinson Bravo, Brayan López (ya emparejados)
-- ════════════════════════════════════════════════════════════════
insert into public.mo_alias (nombre_app, tipo, nomina_id)
select a, 'nomina', (select id from public.mo_nomina where nombre = b)
  from (values ('JOHAN GONZALEZ', 'GONZALEZ SANCHEZ JOAN STIVEN'), ('JOHNNY SANABRIA', 'SANABRIA ORTEGA JHONY ALEJANDRO')) v(a, b)
on conflict (nombre_app) do update set tipo = 'nomina', nomina_id = excluded.nomina_id, actualizado = now();
select string_agg(m.nombre_app || ' → ' || n.nombre, ' · ') as r from public.mo_alias m join public.mo_nomina n on n.id = m.nomina_id where m.nombre_app in ('JOHAN GONZALEZ', 'JOHNNY SANABRIA');
