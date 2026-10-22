-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Cualquier etiqueta de la OP sirve en planta (reclasificar unidad)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Las unidades de una OP son iguales. Si en procesos o al iniciar ensamble
--  escanean la etiqueta de una unidad que NO está en la programación (o no es
--  la asignada al ensamblador), la app le pasa a esa unidad la programación,
--  el ensamblador asignado y los procesos de una unidad programada pendiente,
--  y viceversa. Así la etiqueta queda con la unidad física desde ese momento.
--  Solo entre unidades de la misma OP y obra que aún no inician ensamble.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.reclasificaciones (
  id bigserial primary key, op text, escaneada bigint, op_inst_escaneada text,
  toma_de bigint, op_inst_toma_de text, cuando timestamptz not null default now(), usuario uuid default auth.uid()
);
alter table public.reclasificaciones enable row level security;
drop policy if exists recl_select on public.reclasificaciones;
create policy recl_select on public.reclasificaciones for select to authenticated using (public.es_gerente());

create or replace function public.reclasificar_unidad(p_escaneada bigint, p_toma bigint)
returns setof public.items language plpgsql security definer set search_path = public as $$
declare a public.items; b public.items;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  select * into a from public.items where id = p_escaneada for update;
  select * into b from public.items where id = p_toma for update;
  if a.id is null or b.id is null then raise exception 'Ítem no encontrado'; end if;
  if a.op is distinct from b.op or a.obra is distinct from b.obra then raise exception 'Solo entre unidades de la misma OP y obra'; end if;
  if a.ensamblador is not null or a.dia_inicio is not null or b.ensamblador is not null or b.dia_inicio is not null
     or coalesce(a.despachado, false) or coalesce(b.despachado, false) or coalesce(a.instalado, false) or coalesce(b.instalado, false) then
    raise exception 'Solo se reclasifican unidades que aún no inician ensamble';
  end if;
  insert into public.reclasificaciones (op, escaneada, op_inst_escaneada, toma_de, op_inst_toma_de)
    values (a.op, a.id, a.op_instalacion, b.id, b.op_instalacion);
  perform set_config('elp.swap', '1', true);
  update public.items set
    programacion_id = b.programacion_id, programado = b.programado, programado_en = b.programado_en, ens_asignado = b.ens_asignado,
    cortado = b.cortado, cortado_en = b.cortado_en, troquelado = b.troquelado, troquelado_en = b.troquelado_en,
    mecanizado = b.mecanizado, mecanizado_en = b.mecanizado_en, vidrio_proc = b.vidrio_proc, vidrio_proc_en = b.vidrio_proc_en,
    prealistado = b.prealistado, prealistado_en = b.prealistado_en, status = b.status
  where id = a.id;
  update public.items set
    programacion_id = a.programacion_id, programado = a.programado, programado_en = a.programado_en, ens_asignado = a.ens_asignado,
    cortado = a.cortado, cortado_en = a.cortado_en, troquelado = a.troquelado, troquelado_en = a.troquelado_en,
    mecanizado = a.mecanizado, mecanizado_en = a.mecanizado_en, vidrio_proc = a.vidrio_proc, vidrio_proc_en = a.vidrio_proc_en,
    prealistado = a.prealistado, prealistado_en = a.prealistado_en, status = a.status
  where id = b.id;
  perform set_config('elp.swap', '', true);
  return query select * from public.items where id in (a.id, b.id);
end; $$;
revoke all on function public.reclasificar_unidad(bigint, bigint) from public, anon;
grant execute on function public.reclasificar_unidad(bigint, bigint) to authenticated;

-- Durante el intercambio no se reescriben las fechas de los procesos (se conservan las reales)
create or replace function public.fechar_procesos()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' then return new; end if;
  if new.cortado     = 'X' and old.cortado     is distinct from 'X' then new.cortado_en     := now(); elsif new.cortado     is distinct from 'X' then new.cortado_en     := null; end if;
  if new.troquelado  = 'X' and old.troquelado  is distinct from 'X' then new.troquelado_en  := now(); elsif new.troquelado  is distinct from 'X' then new.troquelado_en  := null; end if;
  if new.mecanizado  = 'X' and old.mecanizado  is distinct from 'X' then new.mecanizado_en  := now(); elsif new.mecanizado  is distinct from 'X' then new.mecanizado_en  := null; end if;
  if new.programado  = 'X' and old.programado  is distinct from 'X' then new.programado_en  := now(); elsif new.programado  is distinct from 'X' then new.programado_en  := null; end if;
  if new.vidrio_proc = 'X' and old.vidrio_proc is distinct from 'X' then new.vidrio_proc_en := now(); elsif new.vidrio_proc is distinct from 'X' then new.vidrio_proc_en := null; end if;
  if new.prealistado = 'X' and old.prealistado is distinct from 'X' then new.prealistado_en := now(); elsif new.prealistado is distinct from 'X' then new.prealistado_en := null; end if;
  return new;
end; $$;

-- El usuario Planta también puede reclasificar (el candado de planta deja pasar este intercambio)
create or replace function public.limitar_planta()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual(), '') <> 'planta' then return new; end if;
  if coalesce(current_setting('elp.swap', true), '') = '1' then return new; end if;
  if row(new.instalado, new.fecha_instalacion, new.instalador, new.acta_id, new.entregado_en, new.entregado_por,
         new.recepcion_id, new.programado, new.programacion_id, new.ens_asignado)
     is distinct from
     row(old.instalado, old.fecha_instalacion, old.instalador, old.acta_id, old.entregado_en, old.entregado_por,
         old.recepcion_id, old.programado, old.programacion_id, old.ens_asignado) then
    raise exception 'Este usuario solo registra procesos, ensamble y despacho';
  end if;
  if old.despachado and not new.despachado then
    raise exception 'Este usuario no puede cancelar despachos';
  end if;
  return new;
end; $$;

select 'Listo ✓ — en planta sirve cualquier etiqueta de la OP' as resultado;
