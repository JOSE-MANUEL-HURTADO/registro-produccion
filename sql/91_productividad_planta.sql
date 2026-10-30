-- ════════════════════════════════════════════════════════════════
--  PRODUCTIVIDAD DE PLANTA (Elíptica + Ártica) por día y por periodo
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  prod_resumen(desde, hasta) devuelve, por día (hora de Colombia):
--   · procesos de Elíptica (programado, cortado, troquelado, mecanizado, vidrio, prealistado): unidades y m²
--   · ensamble terminado por ensamblador (unidades, m², puntos) e iniciados
--   · despachos e instalaciones (por instalador)
--   · Ártica: piezas y m² por estación y por operario; reprocesos
--   · novedades de ensamble y faltantes de material
--  Solo el director.
-- ════════════════════════════════════════════════════════════════
create index if not exists items_dia_final_idx on public.items (dia_final) where dia_final is not null;
create index if not exists items_fecha_inst_idx on public.items (fecha_instalacion) where fecha_instalacion is not null;
create index if not exists items_fecha_desp_idx on public.items (fecha_despacho) where fecha_despacho is not null;
create index if not exists art_registros_creado_idx on public.art_registros (creado);

create or replace function public.prod_resumen(p_desde date, p_hasta date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  t0 timestamptz := (p_desde::timestamp at time zone 'America/Bogota');
  t1 timestamptz := ((p_hasta + 1)::timestamp at time zone 'America/Bogota');
  r jsonb;
begin
  if not coalesce(public.es_gerente(), false) then raise exception 'Sin permiso'; end if;
  if p_hasta < p_desde or p_hasta - p_desde > 120 then raise exception 'Rango de fechas no válido'; end if;
  select jsonb_build_object(
    'proc', coalesce((select jsonb_agg(jsonb_build_object('d', d, 'p', p, 'u', u, 'm2', round(m2::numeric, 2)) order by d, p) from (
        select d, p, count(*) u, sum(m2) m2 from (
          select (cortado_en at time zone 'America/Bogota')::date d, 'cortado' p, coalesce(m2, 0) m2 from public.items where cortado_en >= t0 and cortado_en < t1
          union all select (troquelado_en at time zone 'America/Bogota')::date, 'troquelado', coalesce(m2, 0) from public.items where troquelado_en >= t0 and troquelado_en < t1
          union all select (mecanizado_en at time zone 'America/Bogota')::date, 'mecanizado', coalesce(m2, 0) from public.items where mecanizado_en >= t0 and mecanizado_en < t1
          union all select (vidrio_proc_en at time zone 'America/Bogota')::date, 'vidrio_proc', coalesce(m2, 0) from public.items where vidrio_proc_en >= t0 and vidrio_proc_en < t1
          union all select (prealistado_en at time zone 'America/Bogota')::date, 'prealistado', coalesce(m2, 0) from public.items where prealistado_en >= t0 and prealistado_en < t1
          union all select (programado_en at time zone 'America/Bogota')::date, 'programado', coalesce(m2, 0) from public.items where programado_en >= t0 and programado_en < t1
        ) x group by d, p) y), '[]'),
    'ens', coalesce((select jsonb_agg(jsonb_build_object('d', dia_final, 'e', e, 'u', u, 'm2', round(m2::numeric, 2), 'pts', round(pts::numeric, 1)) order by dia_final, e) from (
        select dia_final, coalesce(nullif(upper(btrim(ensamblador)), ''), 'SIN NOMBRE') e, count(*) u, sum(coalesce(m2, 0)) m2, sum(coalesce(puntos, 0)) pts
          from public.items where dia_final between p_desde and p_hasta group by 1, 2) y), '[]'),
    'ini', coalesce((select jsonb_agg(jsonb_build_object('d', dia_inicio, 'u', u) order by dia_inicio) from (
        select dia_inicio, count(*) u from public.items where dia_inicio between p_desde and p_hasta group by 1) y), '[]'),
    'desp', coalesce((select jsonb_agg(jsonb_build_object('d', fecha_despacho, 'u', u, 'm2', round(m2::numeric, 2), 'obras', obras) order by fecha_despacho) from (
        select fecha_despacho, count(*) u, sum(coalesce(m2, 0)) m2, string_agg(distinct obra, ', ') obras from public.items where despachado and fecha_despacho between p_desde and p_hasta group by 1) y), '[]'),
    'inst', coalesce((select jsonb_agg(jsonb_build_object('d', fecha_instalacion, 'e', e, 'u', u, 'm2', round(m2::numeric, 2)) order by fecha_instalacion, e) from (
        select fecha_instalacion, coalesce(nullif(upper(btrim(instalador)), ''), 'SIN NOMBRE') e, count(*) u, sum(coalesce(m2, 0)) m2
          from public.items where instalado and fecha_instalacion between p_desde and p_hasta group by 1, 2) y), '[]'),
    'art', coalesce((select jsonb_agg(jsonb_build_object('d', d, 'est', estacion, 'q', q, 'pz', pz, 'm2', round(m2::numeric, 2), 'cli', cli) order by d, estacion, q) from (
        select (g.creado at time zone 'America/Bogota')::date d, g.estacion, coalesce(nullif(btrim(g.quien), ''), 'Sin nombre') q,
               sum(coalesce(g.n, 1)) pz, sum(coalesce(g.n, 1) * p.ancho * p.alto / 1e6) m2, sum(case when p.tercero then coalesce(g.n, 1) else 0 end) cli
          from public.art_registros g join public.art_piezas p on p.id = g.pieza_id
         where g.creado >= t0 and g.creado < t1 group by 1, 2, 3) y), '[]'),
    'rep', coalesce((select jsonb_agg(jsonb_build_object('d', d, 'o', origen, 'pz', pz) order by d) from (
        select (creado at time zone 'America/Bogota')::date d, coalesce(origen, '') origen, sum(coalesce(cant, 1)) pz
          from public.art_reprocesos where creado >= t0 and creado < t1 group by 1, 2) y), '[]'),
    'nov', coalesce((select jsonb_agg(jsonb_build_object('d', d, 'm', motivo, 'n', n) order by d) from (
        select (creada at time zone 'America/Bogota')::date d, motivo, count(*) n from public.novedades_ensamble where creada >= t0 and creada < t1 group by 1, 2) y), '[]'),
    'falt', coalesce((select jsonb_agg(jsonb_build_object('d', d, 'p', proceso, 'n', n) order by d) from (
        select (creada at time zone 'America/Bogota')::date d, proceso, count(*) n from public.faltantes where creada >= t0 and creada < t1 group by 1, 2) y), '[]')
  ) into r;
  return r;
end; $$;
revoke all on function public.prod_resumen(date, date) from public, anon;
grant execute on function public.prod_resumen(date, date) to authenticated;

select 'Listo SQL 91 — productividad de planta' as r;
