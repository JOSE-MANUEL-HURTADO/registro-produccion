-- ════════════════════════════════════════════════════════════════
--  ASISTENCIA · Ayudante de cada instalador (en obra o salida a instalar)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
alter table public.asistencia add column if not exists ayudante text;
select 'Listo SQL 104 — ayudante de instalación' as r;
