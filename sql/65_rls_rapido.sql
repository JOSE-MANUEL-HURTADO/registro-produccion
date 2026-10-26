-- ════════════════════════════════════════════════════════════════
--  RENDIMIENTO · Permisos de ítems evaluados una sola vez por consulta
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema. No cambia quién ve o edita qué.
-- ════════════════════════════════════════════════════════════════
--  Las reglas de acceso de items e items_comercial llamaban a la función de rol una vez
--  POR FILA (29.000 veces por consulta). Envueltas en (select …) Postgres las calcula una
--  sola vez. Esto acelera el Excel "Hacer copia ahora", el dashboard y la carga de obras,
--  y evita el error "canceling statement due to statement timeout".
-- ════════════════════════════════════════════════════════════════
alter policy items_delete on public.items using ((select public.es_gerente()));
alter policy items_insert on public.items with check ((select public.es_gerente()));
alter policy items_select on public.items using ((select public.tiene_rol()));
alter policy items_update on public.items using ((select public.puede_registrar())) with check ((select public.puede_registrar()));
alter policy comercial_consulta on public.items_comercial using (((select public.rol_actual()) = 'consulta'::text));
alter policy comercial_gerente on public.items_comercial using ((select public.es_gerente())) with check ((select public.es_gerente()));

select 'Listo SQL 65 — permisos de ítems más rápidos' as resultado;
