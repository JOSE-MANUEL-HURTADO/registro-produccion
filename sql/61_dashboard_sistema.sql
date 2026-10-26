-- ════════════════════════════════════════════════════════════════
--  DASHBOARD · Agrega la columna SISTEMA a la vista del dashboard (Top sistemas)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
create or replace view public.base_dashboard as
 SELECT i.obra AS "OBRA",
    i.item AS "ITEM",
    i.ubicacion AS "UBICACIÓN",
    i.piso AS "PISO",
    i.diseno AS "DISEÑO",
    i.vidrio AS "VIDRIO",
    i.ancho AS "ANCHO",
    i.alto AS "ALTO",
    i.m2 AS "M2",
    i.op_instalacion AS "OP INSTALACION",
    i.cortado AS "CORTADO",
    i.troquelado AS "TROQUELADO",
    i.mecanizado AS "MECANIZADO",
    i.programado AS "PROGRAMADO",
    i.vidrio_proc AS "VIDRIO PROCESO",
    i.prealistado AS "PREALISTADO",
    to_char((i.hora_inicio)::interval, 'HH24:MI'::text) AS "HORA DE INICIO",
    i.dia_inicio AS "DIA INICIO",
    i.ensamblador AS "ENSAMBLADOR",
    i.status AS "STATUS PLANTA",
        CASE
            WHEN i.instalado THEN 'SI'::text
            ELSE 'NO'::text
        END AS "INSTALACION",
    mes_es(i.dia_inicio) AS "MES PRODUCCION",
    (EXTRACT(year FROM i.dia_inicio))::integer AS "AÑO PRODUCCION",
    c.precio AS "PRECIO",
    i.sistema AS "SISTEMA"
   FROM (items i
     LEFT JOIN items_comercial c ON ((c.item_id = i.id)))
  WHERE ve_dashboard()
  ORDER BY i.id;

select 'Listo SQL 61' as resultado, (select count(*) from public.base_dashboard where "SISTEMA" is not null) as con_sistema;
