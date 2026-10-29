-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Lista de obras en una sola consulta
--  (al cargar una OP la app bajaba los 29.000 ítems de 1.000 en 1.000 solo para saber los
--   nombres de las obras; las últimas páginas se pasaban del tiempo máximo → "timeout")
-- ════════════════════════════════════════════════════════════════
create or replace function public.obras_lista()
returns setof text language sql stable security definer set search_path = public as $$
  select distinct obra from public.items where obra is not null and (select public.es_interno()) order by 1;
$$;
revoke all on function public.obras_lista() from public, anon;
grant execute on function public.obras_lista() to authenticated;

select 'Listo SQL 86' as r, (select count(*) from public.obras_lista()) obras;
