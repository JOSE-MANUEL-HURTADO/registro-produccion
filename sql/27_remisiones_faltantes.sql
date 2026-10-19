-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Remisión para lo despachado que quedó sin número
--  Ítems despachados con remisión vacía o solo ceros/guiones (0, 000-0, 00-000…)
--  reciben un número propio por OBRA y FECHA DE DESPACHO:
--      SR-AAMMDD-N   (SR = "sin remisión"; N separa las obras del mismo día)
--      SR-SINFECHA-N si el despacho no tiene fecha
--  No se cruza con la numeración real (00-NNN). Lo anterior queda guardado en
--  remisiones_corregidas para poder revisarlo o devolverlo.
--  Se puede correr más de una vez (solo toca lo que siga sin número).
-- ════════════════════════════════════════════════════════════════
create table if not exists public.remisiones_corregidas (
  item_id   bigint primary key,
  obra      text,
  fecha_despacho date,
  remision_antes text,
  remision_nueva text,
  cuando    timestamptz not null default now()
);
alter table public.remisiones_corregidas enable row level security;

with malos as (
  select id, obra, fecha_despacho, remision
  from public.items
  where despachado
    and (remision is null or trim(remision) = '' or trim(remision) ~ '^[0\s\-\./]+$')
), grupos as (
  select obra, fecha_despacho,
         row_number() over (partition by fecha_despacho order by obra) as n
  from (select distinct obra, fecha_despacho from malos) g
), nuevos as (
  select m.id, m.obra, m.fecha_despacho, m.remision,
         'SR-' || coalesce(to_char(m.fecha_despacho, 'YYMMDD'), 'SINFECHA') || '-' || g.n as nueva
  from malos m join grupos g on g.obra is not distinct from m.obra and g.fecha_despacho is not distinct from m.fecha_despacho
), guardar as (
  insert into public.remisiones_corregidas (item_id, obra, fecha_despacho, remision_antes, remision_nueva)
  select id, obra, fecha_despacho, remision, nueva from nuevos
  on conflict (item_id) do update set remision_antes = excluded.remision_antes, remision_nueva = excluded.remision_nueva, cuando = now()
  returning item_id
)
update public.items i set remision = n.nueva
from nuevos n where i.id = n.id;

-- Resumen de lo que se asignó (una fila por remisión nueva)
select remision_nueva as remision, obra, fecha_despacho, count(*) as items
from public.remisiones_corregidas
group by 1, 2, 3
order by fecha_despacho nulls last, obra;
