-- ════════════════════════════════════════════════════════════════
--  ASISTENCIA · Instaladores (en qué obra está cada uno cada día)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
--  Fila tipo 'instalacion': clave = instalador, estado = obra (motivo = obra) / planta / ausente.
--  El costo de mano de obra carga ese día a la obra aunque no se registren unidades instaladas.
-- ════════════════════════════════════════════════════════════════
alter table public.asistencia drop constraint if exists asistencia_tipo_chk;
alter table public.asistencia add constraint asistencia_tipo_chk check (tipo in ('ensamble', 'proceso', 'cargue', 'instalacion'));
select 'Listo SQL 103 — asistencia de instaladores' as r;
