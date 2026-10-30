-- ════════════════════════════════════════════════════════════════
--  LA CITE · Repartir el vidrio procesado reportado el 30/10/2026 en los últimos 5 días hábiles
--  (se procesó antes del escáner y se reportó todo hoy). Pedido por el director de operaciones.
--  Pegar completo en Supabase → SQL Editor → New query → Run. Solo actúa una vez (respaldo en vidrio_reparto_2026_10_30).
-- ════════════════════════════════════════════════════════════════
--  · 119 unidades con vidrio_proc_en el 30/10 → 26, 27, 28, 29 y 30 de octubre (24/24/24/24/23), en orden de OP,
--    con horas repartidas dentro de la jornada (9:00 a 16:00).
create table if not exists public.vidrio_reparto_2026_10_30 (id bigint primary key, antes timestamptz, despues timestamptz);
alter table public.vidrio_reparto_2026_10_30 enable row level security;
do $$
declare dias date[] := array['2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30']::date[]; n int;
begin
  if exists (select 1 from public.vidrio_reparto_2026_10_30) then raise notice 'Ya se había repartido'; return; end if;
  with l as (
    select id, vidrio_proc_en, row_number() over (order by op, op_instalacion, id) - 1 as k, count(*) over () as tot
      from public.items where obra = 'LA CITE' and (vidrio_proc_en at time zone 'America/Bogota')::date = date '2026-10-30'),
  x as (
    select id, vidrio_proc_en antes, (k * 5 / tot)::int as dia, k - (select min(k2) from (select k as k2 from l l2 where (l2.k * 5 / l2.tot)::int = (l.k * 5 / l.tot)::int) z) as pos,
           (select count(*) from l l3 where (l3.k * 5 / l3.tot)::int = (l.k * 5 / l.tot)::int) as en_dia
      from l),
  y as (
    select id, antes, ((dias[dia + 1] + time '09:00' + make_interval(secs => (pos * 7 * 3600.0 / greatest(en_dia, 1))::int)) at time zone 'America/Bogota') as despues from x)
  insert into public.vidrio_reparto_2026_10_30 select id, antes, despues from y;
  update public.items i set vidrio_proc_en = r.despues from public.vidrio_reparto_2026_10_30 r where r.id = i.id;
  get diagnostics n = row_count; raise notice 'Repartidas % unidades', n;
end $$;

select string_agg(d || ': ' || n, ' · ' order by d) as r from (
  select (vidrio_proc_en at time zone 'America/Bogota')::date d, count(*) n from public.items where obra = 'LA CITE' and vidrio_proc_en is not null group by 1) z;
