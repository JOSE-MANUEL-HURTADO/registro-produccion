-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Usuario CONSULTA: ve todo (precios, cobros, exportar), no modifica nada
--  Correr DESPUÉS de 4_roles_consulta_cobros.sql. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════

-- Leer precios y cobros (solo lectura)
drop policy if exists comercial_consulta on public.items_comercial;
create policy comercial_consulta on public.items_comercial
  for select to authenticated using (public.rol_actual() = 'consulta');

-- Exportar la base completa (misma vista de siempre, ahora también para consulta)
create or replace view public.base_exportable
with (security_invoker = true) as
select
  i.obra                         as "OBRA",
  i.item                         as "ITEM",
  i.ubicacion                    as "UBICACIÓN",
  i.sistema                      as "SISTEMA",
  i.serie                        as "SERIE",
  i.piso                         as "PISO",
  i.diseno                       as "DISEÑO",
  i.vidrio                       as "VIDRIO",
  i.ancho                        as "ANCHO",
  i.alto                         as "ALTO",
  i.m2                           as "M2",
  i.cant                         as "CANT",
  i.op                           as "OP",
  i.op_instalacion               as "OP INSTALACION",
  i.fecha_op                     as "FECHA OP",
  i.tiempo_op                    as "TIEMPO OP",
  i.puntos                       as "PUNTOS",
  i.cortado                      as "CORTADO",
  i.troquelado                   as "TROQUELADO",
  i.mecanizado                   as "MECANIZADO",
  i.programado                   as "PROGRAMADO",
  i.vidrio_proc                  as "VIDRIO PROCESO",
  i.prealistado                  as "PREALISTADO",
  to_char(i.hora_inicio,'HH24:MI') as "HORA DE INICIO",
  i.dia_inicio                   as "DIA INICIO",
  to_char(i.hora_final,'HH24:MI')  as "HORA FINAL",
  i.dia_final                    as "DIA FINAL",
  i.ensamblador                  as "ENSAMBLADOR",
  i.status                       as "STATUS PLANTA",
  public.semana_excel(i.dia_inicio)        as "SEMANA PRODUCCION",
  case when i.despachado then 'SI' else 'NO' end as "DESPACHO",
  i.fecha_despacho               as "FECHA DESPACHO",
  public.semana_excel(i.fecha_despacho)    as "SEMANA DESPACHO",
  extract(year from i.fecha_despacho)::int as "AÑO DESPACHO",
  i.remision                     as "REMISION",
  case c.cobrado_despacho when true then 'SI' when false then 'NO' end as "COBRADO PUESTO EN OBRA",
  c.fecha_corte_despacho         as "FECHA CORTE PUESTO EN OBRA",
  c.num_corte_despacho           as "# CORTE PUESTO EN OBRA",
  case when i.instalado then 'SI' else 'NO' end as "INSTALACION",
  i.instalador                   as "INSTALADOR",
  i.fecha_instalacion            as "FECHA INSTALACION",
  public.semana_excel(i.fecha_instalacion) as "SEMANA INSTALACION",
  public.mes_es(i.fecha_instalacion)       as "MES INSTALACION",
  extract(year from i.fecha_instalacion)::int as "AÑO INSTALACION",
  case c.cobrado_instalacion when true then 'SI' when false then 'NO' end as "COBRADO INSTALADO",
  c.fecha_corte_instalacion      as "FECHA CORTE INSTALADO",
  c.num_corte_instalacion        as "# CORTE INSTALADO",
  public.mes_es(i.dia_inicio)              as "MES PRODUCCION",
  extract(year from i.dia_inicio)::int     as "AÑO PRODUCCION",
  c.precio                       as "PRECIO"
from public.items i
left join public.items_comercial c on c.item_id = i.id
where public.rol_actual() in ('gerente','consulta')
order by i.id;
