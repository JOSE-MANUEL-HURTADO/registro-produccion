-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Novedades de ensamble (ítem EN ESPERA) y una OP a la vez por ensamblador
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Si en ensamble pasa algo que para el ítem (rotura de vidrio, falta material…),
--    se reporta la NOVEDAD: el ítem sigue abierto (en ensamble) pero queda EN ESPERA.
--  · Se reanuda escaneando otra vez Inicio de ensamble, con "Reanudar" en el ítem,
--    o solo al terminar el ensamble / anularlo.
--  · Un ensamblador NO puede iniciar una OP nueva mientras tenga otra OP iniciada y sin
--    terminar, a menos que esa OP esté EN ESPERA por novedad. (El director puede forzarlo.)
--  · Aviso al director y a la asistente (campana y celular).
-- ════════════════════════════════════════════════════════════════
create table if not exists public.novedades_ensamble (
  id            bigserial primary key,
  obra          text,
  op            text,
  ops           text,
  items         bigint[] not null,
  ensamblador   text,
  motivo        text not null,
  detalle       text,
  creada        timestamptz not null default now(),
  usuario       uuid default auth.uid(),
  quien         text,
  resuelta_en   timestamptz,
  resuelta_por  text,
  resuelta_nota text
);
create index if not exists nov_ens_abiertas on public.novedades_ensamble (creada desc) where resuelta_en is null;
alter table public.novedades_ensamble enable row level security;
drop policy if exists nov_ens_ver on public.novedades_ensamble;
create policy nov_ens_ver on public.novedades_ensamble for select to authenticated using ((select public.es_interno()));
grant select on public.novedades_ensamble to authenticated;
grant all on public.novedades_ensamble to service_role;
grant usage, select on sequence public.novedades_ensamble_id_seq to service_role;

alter table public.items add column if not exists ens_novedad_id bigint;
create index if not exists items_ens_novedad_idx on public.items (ens_novedad_id) where ens_novedad_id is not null;
create index if not exists items_ens_abierto_idx on public.items (upper(btrim(ensamblador)))
  where dia_inicio is not null and dia_final is null;

-- OP abiertas (iniciadas, sin terminar, no en espera) de un ensamblador, distintas de p_op
create or replace function public.ens_ops_abiertas(p_ens text, p_op text, p_excluir bigint[] default '{}')
returns text language sql stable security definer set search_path = public as $$
  select string_agg(distinct coalesce(i.op, '?'), ', ')
    from public.items i
   where upper(btrim(i.ensamblador)) = upper(btrim(p_ens))
     and i.dia_inicio is not null and i.dia_final is null and not coalesce(i.despachado, false)
     and i.ens_novedad_id is null and i.op is distinct from p_op
     and not (i.id = any(coalesce(p_excluir, '{}')));
$$;
grant execute on function public.ens_ops_abiertas(text, text, bigint[]) to authenticated;

-- Candado: una OP a la vez por ensamblador
create or replace function public.chk_una_op_ensamblador()
returns trigger language plpgsql security definer set search_path = public as $$
declare v text;
begin
  if new.ensamblador is null or new.dia_inicio is null or new.dia_final is not null or coalesce(new.despachado, false) then return new; end if;
  if old.dia_inicio is not null and upper(btrim(coalesce(old.ensamblador, ''))) = upper(btrim(new.ensamblador)) then return new; end if;  -- no es un inicio nuevo
  if coalesce(public.es_gerente(), false) then return new; end if;
  v := public.ens_ops_abiertas(new.ensamblador, new.op, array[new.id]);
  if v is not null then
    raise exception '% tiene sin terminar la OP %. Debe terminarla, o reportarla con novedad (en espera), antes de iniciar la OP %', new.ensamblador, v, new.op;
  end if;
  return new;
end; $$;
drop trigger if exists trg_una_op_ensamblador on public.items;
create trigger trg_una_op_ensamblador before update of ensamblador, dia_inicio on public.items
  for each row execute function public.chk_una_op_ensamblador();

-- Al terminar, anular o despachar, el ítem sale de espera solo
create or replace function public.ens_novedad_auto()
returns trigger language plpgsql as $$
begin
  if new.ens_novedad_id is not null and (new.dia_final is not null or coalesce(new.despachado, false)
       or (new.ensamblador is null and new.dia_inicio is null)) then
    new.ens_novedad_id := null;
  end if;
  return new;
end; $$;
drop trigger if exists trg_ens_novedad_auto on public.items;
create trigger trg_ens_novedad_auto before update on public.items for each row execute function public.ens_novedad_auto();

-- Novedad sin ítems en espera = resuelta
create or replace function public.ens_novedad_cerrar()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from viejos where ens_novedad_id is not null) then return null; end if;
  update public.novedades_ensamble n
     set resuelta_en = now(),
         resuelta_por = coalesce(nullif(current_setting('elp.nov_quien', true), ''), 'Automático · ensamble terminado o anulado'),
         resuelta_nota = nullif(current_setting('elp.nov_nota', true), '')
   where n.resuelta_en is null
     and n.id in (select distinct ens_novedad_id from viejos where ens_novedad_id is not null)
     and not exists (select 1 from public.items i where i.ens_novedad_id = n.id);
  return null;
end; $$;
drop trigger if exists trg_ens_novedad_cerrar on public.items;
create trigger trg_ens_novedad_cerrar after update on public.items referencing old table as viejos
  for each statement execute function public.ens_novedad_cerrar();

-- Reportar novedad: los ítems quedan EN ESPERA
create or replace function public.ens_novedad_crear(p_items bigint[], p_motivo text, p_detalle text)
returns public.novedades_ensamble language plpgsql security definer set search_path = public as $$
declare r public.novedades_ensamble; v_ids bigint[]; v_obra text; v_op text; v_ops text; v_ens text; v_txt text; a record;
begin
  if not coalesce(public.puede_registrar(), false) then raise exception 'Sin permiso'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'Falta el motivo'; end if;
  select array_agg(id order by op_instalacion), string_agg(distinct obra, ', '), string_agg(distinct op, ', '),
         string_agg(distinct op_instalacion, ', ' order by op_instalacion), string_agg(distinct ensamblador, ', ')
    into v_ids, v_obra, v_op, v_ops, v_ens
    from public.items
   where id = any(p_items) and ensamblador is not null and dia_inicio is not null and dia_final is null
     and not coalesce(despachado, false) and ens_novedad_id is null;
  if v_ids is null then raise exception 'Ninguno de los ítems está en ensamble (iniciado y sin terminar), o ya están en espera'; end if;
  insert into public.novedades_ensamble (obra, op, ops, items, ensamblador, motivo, detalle, quien)
  values (v_obra, v_op, v_ops, v_ids, v_ens, btrim(p_motivo), nullif(btrim(p_detalle), ''), public.notif_quien())
  returning * into r;
  update public.items set ens_novedad_id = r.id where id = any(v_ids);
  v_txt := '⏸ ' || r.motivo || coalesce(' · ' || r.detalle, '') || ' · OP ' || coalesce(v_ops, v_op) || coalesce(' · ' || v_ens, '');
  begin perform public.notif_crear('Elíptica · ' || coalesce(v_obra, ''), coalesce(r.quien, 'Planta') || ': novedad de ensamble — ' || v_txt);
  exception when others then null; end;
  begin
    for a in select pf.id from public.perfiles pf where pf.rol = 'asistente' and pf.id is distinct from auth.uid() loop
      insert into public.avisos (para, tipo, obra, ops, items, n, quien, ref)
      values (a.id, 'Novedad de ensamble · ' || r.motivo, v_obra, v_ops, left(coalesce(r.detalle, '') || coalesce(' · ' || v_ens, ''), 400),
              coalesce(array_length(v_ids, 1), 0), r.quien, 'nens:' || r.id);
      begin perform public.notif_para(a.id, 'Novedad de ensamble · ' || r.motivo, v_txt || ' · ' || coalesce(v_obra, '')); exception when others then null; end;
    end loop;
  exception when others then null; end;
  return r;
end; $$;
revoke all on function public.ens_novedad_crear(bigint[], text, text) from public, anon;
grant execute on function public.ens_novedad_crear(bigint[], text, text) to authenticated;

-- Reanudar: los ítems salen de espera (vuelven a "en ensamble")
create or replace function public.ens_reanudar(p_items bigint[], p_nota text)
returns setof public.items language plpgsql security definer set search_path = public as $$
declare a record; v text;
begin
  if not coalesce(public.puede_registrar(), false) then raise exception 'Sin permiso'; end if;
  if not coalesce(public.es_gerente(), false) then
    for a in select ensamblador, min(op) op from public.items where id = any(p_items) and ens_novedad_id is not null group by ensamblador loop
      v := public.ens_ops_abiertas(a.ensamblador, a.op, p_items);
      if v is not null then
        raise exception '% está trabajando la OP %. Debe terminarla, o ponerla en espera, antes de reanudar la OP %', a.ensamblador, v, a.op;
      end if;
    end loop;
  end if;
  perform set_config('elp.nov_quien', coalesce(public.notif_quien(), 'Reanudado'), true);
  perform set_config('elp.nov_nota', coalesce(btrim(p_nota), ''), true);
  return query update public.items set ens_novedad_id = null where id = any(p_items) and ens_novedad_id is not null returning *;
  perform set_config('elp.nov_quien', '', true);
  perform set_config('elp.nov_nota', '', true);
end; $$;
revoke all on function public.ens_reanudar(bigint[], text) from public, anon;
grant execute on function public.ens_reanudar(bigint[], text) to authenticated;

select 'Listo SQL 72 — novedades de ensamble' as r,
       (select count(*) from information_schema.columns where table_name = 'items' and column_name = 'ens_novedad_id') col,
       (select count(*) from public.novedades_ensamble) novedades;
