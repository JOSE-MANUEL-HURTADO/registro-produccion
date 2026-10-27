-- ════════════════════════════════════════════════════════════════
--  FALTANTES DE MATERIAL EN CORTE (perfiles HSP)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cuando el corte de una OP / sub-OP queda parcial (+) porque no alcanzó un perfil,
--  se registra cuál HSP faltó (la app lee los HSP de la orden PDF de esa OP).
--  · Le llega un aviso al director (celular) y a la asistente (campana de la app).
--  · Se da por resuelto solo cuando el corte de esos ítems queda completo (X),
--    o a mano con el botón "Resuelto".
-- ════════════════════════════════════════════════════════════════
create table if not exists public.faltantes (
  id          bigserial primary key,
  obra        text,
  op          text not null,
  item_ids    bigint[] not null default '{}',
  op_inst     text[] not null default '{}',
  proceso     text not null default 'corte',
  ref         text not null,
  descripcion text,
  cant        numeric,
  medida      numeric,
  nota        text,
  quien       text,
  usuario     uuid default auth.uid(),
  creada      timestamptz not null default now(),
  resuelta    timestamptz,
  resuelta_por text
);
create index if not exists faltantes_obra_idx on public.faltantes (obra);
create index if not exists faltantes_op_idx on public.faltantes (op);
alter table public.faltantes enable row level security;
drop policy if exists falt_ver on public.faltantes;
create policy falt_ver on public.faltantes for select to authenticated using ((select public.es_interno()));
drop policy if exists falt_crear on public.faltantes;
create policy falt_crear on public.faltantes for insert to authenticated with check ((select public.puede_registrar()));
drop policy if exists falt_resolver on public.faltantes;
create policy falt_resolver on public.faltantes for update to authenticated using ((select public.puede_registrar())) with check ((select public.puede_registrar()));
grant select, insert, update on public.faltantes to authenticated;
grant usage, select on sequence public.faltantes_id_seq to authenticated;
grant all on public.faltantes to service_role;

-- Quién lo registró y aviso al director y a la asistente
create or replace function public.faltante_nuevo()
returns trigger language plpgsql security definer set search_path = public as $$
declare a record; v_txt text;
begin
  new.quien := coalesce(new.quien, public.notif_quien());
  v_txt := 'Falta ' || new.ref || coalesce(' ' || new.descripcion, '') || coalesce(' · ' || trim(to_char(new.cant, 'FM999990')) || ' und', '')
        || coalesce(' × ' || trim(to_char(new.medida, 'FM999990')) || ' mm', '') || ' · OP ' || new.op
        || case when array_length(new.op_inst, 1) between 1 and 6 then ' (' || array_to_string(new.op_inst, ', ') || ')' else '' end;
  begin
    perform public.notif_crear('Elíptica · ' || coalesce(new.obra, ''), new.quien || ': corte parcial · ' || v_txt || coalesce(' · ' || new.nota, ''));
  exception when others then null; end;
  begin
    for a in select pf.id from public.perfiles pf where pf.rol = 'asistente' and pf.id is distinct from auth.uid() loop
      insert into public.avisos (para, tipo, obra, ops, items, n, quien, ref)
      values (a.id, 'Falta material · ' || new.ref, new.obra, new.op, left(coalesce(new.descripcion, '') || coalesce(' · ' || new.nota, ''), 400),
              coalesce(array_length(new.item_ids, 1), 0), new.quien, 'falt:' || new.id);
      begin perform public.notif_para(a.id, 'Falta material · ' || new.ref, v_txt || ' · ' || coalesce(new.obra, '')); exception when others then null; end;
    end loop;
  exception when others then null; end;   -- sin tablas de avisos (SQL 62/63): no bloquea
  return new;
end; $$;
drop trigger if exists trg_faltante_nuevo on public.faltantes;
create trigger trg_faltante_nuevo before insert on public.faltantes for each row execute function public.faltante_nuevo();

-- Corte completo (X) de todos sus ítems → el faltante queda resuelto solo
create or replace function public.faltante_corte_ok()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.faltantes f set resuelta = now(), resuelta_por = 'Corte completo'
   where f.resuelta is null and f.proceso = 'corte' and f.op in (select distinct op from nuevos where cortado = 'X')
     and not exists (select 1 from public.items i where i.id = any(f.item_ids) and i.cortado is distinct from 'X');
  return null;
end; $$;
drop trigger if exists trg_faltante_corte_ok on public.items;
create trigger trg_faltante_corte_ok after update on public.items referencing new table as nuevos
  for each statement execute function public.faltante_corte_ok();

select 'Listo SQL 68 — faltantes de material' as resultado;
