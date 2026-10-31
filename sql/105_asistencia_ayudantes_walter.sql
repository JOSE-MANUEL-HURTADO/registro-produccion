-- ════════════════════════════════════════════════════════════════
--  ASISTENCIA · Número de ayudantes por oficial + cuadrilla de Walter Díaz en Vilanova (26 a 30 de octubre de 2026)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
--  · ayudantes: cuántos ayudantes lleva el oficial ese día (si no se sabe quiénes, se costean al salario mínimo).
--  · Pedido del director (30/10/2026): toda la semana Walter Díaz estuvo en Vilanova (torre 5, donde registró
--    sus instalaciones del 27 al 30) con 3 ayudantes.
-- ════════════════════════════════════════════════════════════════
alter table public.asistencia add column if not exists ayudantes int;
insert into public.asistencia (fecha, tipo, clave, estado, motivo, ayudantes)
select d::date, 'instalacion', 'WALTER DIAZ', 'obra', 'VILANOVA T5', 3 from generate_series(date '2026-10-26', date '2026-10-30', interval '1 day') d
on conflict (fecha, tipo, clave) do update set estado = 'obra', motivo = excluded.motivo, ayudantes = excluded.ayudantes, actualizada = now();
select 'Listo SQL 105' as r, (select string_agg(fecha::text || ' ' || motivo || ' +' || ayudantes, ' · ' order by fecha) from public.asistencia where clave = 'WALTER DIAZ' and tipo = 'instalacion') walter;
