-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Fecha de cada proceso (para medir el desempeño)
--  · Cada vez que un proceso pasa a X queda la fecha y hora (cortado_en, …)
--  · Se rellena lo anterior desde el historial de cambios
--  · Corrige el intercambio de destino en el cargue para la asistente
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
alter table public.items add column if not exists cortado_en     timestamptz;
alter table public.items add column if not exists troquelado_en  timestamptz;
alter table public.items add column if not exists mecanizado_en  timestamptz;
alter table public.items add column if not exists programado_en  timestamptz;
alter table public.items add column if not exists vidrio_proc_en timestamptz;
alter table public.items add column if not exists prealistado_en timestamptz;

create or replace function public.fechar_procesos()
returns trigger language plpgsql as $$
begin
  if new.cortado     = 'X' and old.cortado     is distinct from 'X' then new.cortado_en     := now(); elsif new.cortado     is distinct from 'X' then new.cortado_en     := null; end if;
  if new.troquelado  = 'X' and old.troquelado  is distinct from 'X' then new.troquelado_en  := now(); elsif new.troquelado  is distinct from 'X' then new.troquelado_en  := null; end if;
  if new.mecanizado  = 'X' and old.mecanizado  is distinct from 'X' then new.mecanizado_en  := now(); elsif new.mecanizado  is distinct from 'X' then new.mecanizado_en  := null; end if;
  if new.programado  = 'X' and old.programado  is distinct from 'X' then new.programado_en  := now(); elsif new.programado  is distinct from 'X' then new.programado_en  := null; end if;
  if new.vidrio_proc = 'X' and old.vidrio_proc is distinct from 'X' then new.vidrio_proc_en := now(); elsif new.vidrio_proc is distinct from 'X' then new.vidrio_proc_en := null; end if;
  if new.prealistado = 'X' and old.prealistado is distinct from 'X' then new.prealistado_en := now(); elsif new.prealistado is distinct from 'X' then new.prealistado_en := null; end if;
  return new;
end; $$;
drop trigger if exists trg_fechar_procesos on public.items;
create trigger trg_fechar_procesos before update on public.items
  for each row execute function public.fechar_procesos();

-- Rellenar con el historial (la última vez que cada proceso pasó a X)
do $$
declare k text;
begin
  foreach k in array array['cortado','troquelado','mecanizado','programado','vidrio_proc','prealistado'] loop
    execute format($f$
      update public.items i set %1$I_en = h.cuando
        from (select item_id, max(cuando) cuando from public.historial
               where despues->>%2$L = 'X' and coalesce(antes->>%2$L, '') <> 'X' group by item_id) h
       where h.item_id = i.id and i.%2$I = 'X' and i.%1$I_en is null$f$, k, k);
  end loop;
end $$;

-- Resumen de procesos hechos en un periodo (por día, obra y OP)
create or replace function public.procesos_hechos(p_desde date, p_hasta date)
returns table(proceso text, dia date, obra text, op text, n integer, m2 numeric)
language sql stable security definer set search_path = public as $$
  select p.proceso, (p.cuando at time zone 'America/Bogota')::date, i.obra, i.op, count(*)::int, sum(coalesce(i.m2, 0) * coalesce(i.cant, 1))
    from public.items i
    cross join lateral (values ('cortado', i.cortado_en), ('troquelado', i.troquelado_en), ('mecanizado', i.mecanizado_en),
                               ('programado', i.programado_en), ('vidrio_proc', i.vidrio_proc_en), ('prealistado', i.prealistado_en)) p(proceso, cuando)
   where public.es_interno() and p.cuando is not null
     and (p.cuando at time zone 'America/Bogota')::date between p_desde and p_hasta
   group by 1, 2, 3, 4;
$$;
revoke all on function public.procesos_hechos(date, date) from public, anon;
grant execute on function public.procesos_hechos(date, date) to authenticated;

-- Corrección: el intercambio de destino en el cargue (SQL 23) lo puede hacer la asistente
create or replace function public.proteger_items()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() and coalesce(current_setting('elp.swap', true), '') <> '1' then
    if row(new.obra, new.item, new.ubicacion, new.piso, new.diseno, new.vidrio,
           new.ancho, new.alto, new.m2, new.cant, new.op, new.op_instalacion)
       is distinct from
       row(old.obra, old.item, old.ubicacion, old.piso, old.diseno, old.vidrio,
           old.ancho, old.alto, old.m2, old.cant, old.op, old.op_instalacion) then
      raise exception 'Sin permiso para modificar los datos de la OP';
    end if;
  end if;
  new.actualizado_en  := now();
  new.actualizado_por := auth.uid();
  return new;
end;
$$;
create or replace function public.intercambiar_destino(p_a bigint, p_b bigint)
returns void language plpgsql security definer set search_path = public as $$
declare a public.items; b public.items;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  select * into a from public.items where id = p_a for update;
  select * into b from public.items where id = p_b for update;
  if a.id is null or b.id is null then raise exception 'Ítem no encontrado'; end if;
  if a.op is distinct from b.op then raise exception 'Solo se intercambian unidades de la misma OP'; end if;
  if a.despachado or b.despachado or a.instalado or b.instalado then raise exception 'No se intercambian unidades ya despachadas o instaladas'; end if;
  insert into public.intercambios_destino (op, item_a, op_inst_a, item_b, op_inst_b, ubic_a, piso_a, ubic_b, piso_b)
    values (a.op, a.id, a.op_instalacion, b.id, b.op_instalacion, a.ubicacion, a.piso, b.ubicacion, b.piso);
  perform set_config('elp.swap', '1', true);
  update public.items set ubicacion = b.ubicacion, piso = b.piso where id = a.id;
  update public.items set ubicacion = a.ubicacion, piso = a.piso where id = b.id;
  perform set_config('elp.swap', '', true);
end; $$;
