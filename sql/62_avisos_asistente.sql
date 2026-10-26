-- ════════════════════════════════════════════════════════════════
--  AVISOS EN LA APP PARA LA ASISTENTE
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada vez que el director de operaciones (rol gerente):
--    · crea una ORDEN DE DESPACHO,
--    · crea una PROGRAMACIÓN (ítems programados), o
--    · arma una LÍNEA DE ENSAMBLE (asigna ítems a un ensamblador),
--  cada usuario con rol asistente recibe un aviso en la app (campana 🔔 con número),
--  con el tipo de evento, las OP / ítems, la obra y la hora.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.avisos (
  id      bigserial primary key,
  para    uuid not null,
  tipo    text not null,
  obra    text,
  ops     text,
  items   text,
  n       integer,
  quien   text,
  ref     text,
  creada  timestamptz not null default now(),
  leida   timestamptz
);
create index if not exists avisos_para_idx on public.avisos (para, creada desc);
alter table public.avisos enable row level security;
drop policy if exists avisos_ver on public.avisos;
create policy avisos_ver on public.avisos for select to authenticated using (para = auth.uid() or public.es_gerente());
drop policy if exists avisos_leer on public.avisos;
create policy avisos_leer on public.avisos for update to authenticated using (para = auth.uid()) with check (para = auth.uid());
grant select on public.avisos to authenticated;
grant update (leida) on public.avisos to authenticated;
grant all on public.avisos to service_role;
grant usage, select on sequence public.avisos_id_seq to service_role;

-- Tiempo real (la campana se actualiza sola)
do $x$ begin alter publication supabase_realtime add table public.avisos; exception when duplicate_object then null; when undefined_object then null; end $x$;

-- Crea un aviso para cada asistente (solo si quien hace la acción es el director)
create or replace function public.aviso_asistentes(p_tipo text, p_obra text, p_ops text, p_items text, p_n int, p_ref text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not coalesce(public.es_gerente(), false) then return; end if;
  insert into public.avisos (para, tipo, obra, ops, items, n, quien, ref)
  select pf.id, p_tipo, left(p_obra, 200), left(p_ops, 400), left(p_items, 400), p_n, public.notif_quien(), p_ref
    from public.perfiles pf where pf.rol = 'asistente' and pf.id is distinct from auth.uid();
exception when others then
  raise warning 'aviso no creado: %', sqlerrm;   -- nunca bloquea la acción
end; $$;
revoke all on function public.aviso_asistentes(text, text, text, text, int, text) from public, anon, authenticated;

-- 1. Orden de despacho creada
create or replace function public.aviso_od()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_ops text; v_its text; v_obra text;
begin
  select string_agg(distinct i.op, ', '), string_agg(distinct i.item, ', '), string_agg(distinct i.obra, ', ')
    into v_ops, v_its, v_obra
    from public.items i where i.id = any(new.items);
  perform public.aviso_asistentes('Orden de despacho N.º ' || new.id, coalesce(new.obra, v_obra), v_ops, v_its,
    coalesce(array_length(new.items, 1), 0), 'od:' || new.id);
  return null;
exception when others then
  raise warning 'aviso no creado: %', sqlerrm;
  return null;
end; $$;
drop trigger if exists trg_aviso_od on public.ordenes_despacho;
create trigger trg_aviso_od after insert on public.ordenes_despacho for each row execute function public.aviso_od();

-- 2 y 3. Programación y línea de ensamble: cuando se marcan los ítems (un aviso por programación / por ensamblador)
create or replace function public.aviso_items()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' then return null; end if;
  if not coalesce(public.es_gerente(), false) then return null; end if;
  for r in
    select nw.programacion_id pid, string_agg(distinct nw.op, ', ' order by nw.op) ops, string_agg(distinct nw.item, ', ') its,
           string_agg(distinct nw.obra, ', ') obras, count(*) n
      from nuevos nw join viejos od on od.id = nw.id
     where nw.programacion_id is not null and od.programacion_id is distinct from nw.programacion_id
     group by nw.programacion_id
  loop
    perform public.aviso_asistentes('Programación N.º ' || r.pid, r.obras, r.ops, r.its, r.n::int, 'prog:' || r.pid);
  end loop;
  for r in
    select nw.ens_asignado ens, string_agg(distinct nw.op, ', ' order by nw.op) ops, string_agg(distinct nw.item, ', ') its,
           string_agg(distinct nw.obra, ', ') obras, count(*) n
      from nuevos nw join viejos od on od.id = nw.id
     where nw.ens_asignado is not null and nw.ens_asignado is distinct from od.ens_asignado
     group by nw.ens_asignado
  loop
    perform public.aviso_asistentes('Línea de ensamble · ' || r.ens, r.obras, r.ops, r.its, r.n::int, 'linea:' || r.ens);
  end loop;
  return null;
exception when others then
  raise warning 'aviso no creado: %', sqlerrm;   -- nunca bloquea la acción
  return null;
end; $$;
drop trigger if exists trg_aviso_items on public.items;
create trigger trg_aviso_items after update on public.items referencing old table as viejos new table as nuevos
  for each statement execute function public.aviso_items();

select 'Listo SQL 62 — avisos para la asistente' as resultado,
       (select string_agg(coalesce(nombre, id::text), ', ') from public.perfiles where rol = 'asistente') as asistentes;
