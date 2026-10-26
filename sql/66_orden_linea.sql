-- ════════════════════════════════════════════════════════════════
--  LÍNEA DE ENSAMBLE EN EL ORDEN EN QUE SE ASIGNA
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada vez que se asigna un ítem a un ensamblador queda con un consecutivo (ens_orden).
--  La línea de ensamble se muestra en ese orden: lo primero que asignas va primero,
--  sin importar la obra ni la fecha de la programación.
--  Lo ya asignado conserva el orden en que se veía hasta hoy.
-- ════════════════════════════════════════════════════════════════
alter table public.items add column if not exists ens_orden bigint;
create sequence if not exists public.ens_orden_seq;
grant usage, select on sequence public.ens_orden_seq to authenticated;

create or replace function public.ens_orden_asignar()
returns trigger language plpgsql as $$
begin
  if new.ens_asignado is null then new.ens_orden := null;
  elsif new.ens_asignado is distinct from old.ens_asignado or new.ens_orden is null then new.ens_orden := nextval('public.ens_orden_seq');
  end if;
  return new;
end; $$;
drop trigger if exists trg_ens_orden on public.items;
create trigger trg_ens_orden before update of ens_asignado on public.items for each row execute function public.ens_orden_asignar();

-- Lo ya asignado: el orden que se veía (fecha requerida de la programación, OP, unidad)
do $x$ begin
  if exists (select 1 from public.items where ens_asignado is not null and ens_orden is null) then
    perform set_config('elp.swap', '1', true);
    with o as (
      select i.id, row_number() over (order by coalesce(p.fecha_req, '9999-12-31'), i.op, i.op_instalacion, i.id) rn
        from public.items i left join public.programaciones p on p.id = i.programacion_id
       where i.ens_asignado is not null and i.ens_orden is null)
    update public.items i set ens_orden = o.rn from o where o.id = i.id;
    perform setval('public.ens_orden_seq', greatest((select coalesce(max(ens_orden), 0) from public.items), 1));
    perform set_config('elp.swap', '', true);
  end if;
end $x$;

select 'Listo SQL 66' as resultado, (select count(*) from public.items where ens_asignado is not null) as asignados, (select max(ens_orden) from public.items) as ultimo;
