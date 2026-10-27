-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Exportar a OPTIMA por lotes (obra + tipo + calibre + color)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada medida guarda cuándo y cuántas piezas se mandaron a OPTIMA. Lo enviado sale de la
--  lista de exportar; si después se rompe una pieza ya cortada (corte desmarcado), esa pieza
--  vuelve a aparecer para mandarla de nuevo. "Devolver" la regresa a la lista.
-- ════════════════════════════════════════════════════════════════
alter table public.art_piezas add column if not exists optima_en   timestamptz;
alter table public.art_piezas add column if not exists optima_pend int;
alter table public.art_piezas add column if not exists optima_lote text;

-- Marca como enviadas a OPTIMA: p = [{"id":1,"pend":8}, …] (pend = piezas que quedan en el plan de OPTIMA)
create or replace function public.art_optima_marcar(p jsonb, p_lote text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  update public.art_piezas a set optima_en = now(), optima_pend = (x->>'pend')::int, optima_lote = p_lote
    from jsonb_array_elements(p) x where a.id = (x->>'id')::bigint;
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_optima_marcar(jsonb, text) from public, anon;
grant execute on function public.art_optima_marcar(jsonb, text) to authenticated;

-- Devolver a la lista de exportar (por lote o por piezas)
create or replace function public.art_optima_devolver(p_ids bigint[])
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  update public.art_piezas set optima_en = null, optima_pend = null, optima_lote = null where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_optima_devolver(bigint[]) from public, anon;
grant execute on function public.art_optima_devolver(bigint[]) to authenticated;

-- Vista de avance: piezas cortadas después de mandarlas a OPTIMA
drop view if exists public.art_avance;
create view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo,
         case when p.optima_en is null then 0 else (select count(*)::int from public.art_registros g where g.pieza_id = p.id and g.estacion = 'corte' and g.creado > p.optima_en) end as corte_post_optima
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

select 'Listo SQL 69 — OPTIMA por lotes' as resultado;
