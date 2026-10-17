-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Actas de entrega de ítems instalados
--  · Cada obra lleva su propio consecutivo (Acta 1, 2, 3…)
--  · Un ítem solo entra a un acta si está instalado, y solo a una
--  · No se puede quitar la instalación a un ítem que ya está en un acta
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.actas (
  id      bigserial primary key,
  obra    text not null,
  num     integer not null,
  fecha   date not null default current_date,
  recibe  text,
  n_items integer not null default 0,
  anulada boolean not null default false,
  creada  timestamptz not null default now(),
  usuario uuid default auth.uid(),
  unique (obra, num)
);
alter table public.actas enable row level security;
drop policy if exists actas_select on public.actas;
create policy actas_select on public.actas for select to authenticated using (public.rol_actual() is not null);

alter table public.items add column if not exists acta_id bigint references public.actas(id);
create index if not exists items_acta_idx on public.items (acta_id);

-- Candado: acta_id solo lo cambian las funciones de abajo; no se desinstala un ítem entregado
create or replace function public.chk_items_acta()
returns trigger language plpgsql as $$
begin
  if new.acta_id is distinct from old.acta_id and coalesce(current_setting('elp.acta', true), '') <> '1' then
    raise exception 'El acta de entrega solo se cambia desde Actas de entrega';
  end if;
  if old.acta_id is not null and new.acta_id is not null and coalesce(old.instalado, false) and not coalesce(new.instalado, false) then
    raise exception 'El ítem % (OP %) ya está en un acta de entrega: primero anula el acta', new.item, new.op_instalacion;
  end if;
  return new;
end; $$;
drop trigger if exists trg_items_acta on public.items;
create trigger trg_items_acta before update on public.items
  for each row execute function public.chk_items_acta();

-- Crear acta con los ítems elegidos (solo los instalados y sin acta)
create or replace function public.crear_acta(p_obra text, p_ids bigint[], p_fecha date, p_recibe text)
returns table(id bigint, num integer, n integer)
language plpgsql security definer set search_path = public as $$
declare a_id bigint; a_num integer; cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros'), false) is not true then raise exception 'Sin permiso'; end if;
  perform pg_advisory_xact_lock(hashtext('acta:' || p_obra));
  select coalesce(max(a.num), 0) + 1 into a_num from public.actas a where a.obra = p_obra;
  insert into public.actas (obra, num, fecha, recibe) values (p_obra, a_num, coalesce(p_fecha, current_date), nullif(trim(p_recibe), ''))
    returning actas.id into a_id;
  perform set_config('elp.acta', '1', true);
  update public.items i set acta_id = a_id
    where i.id = any(p_ids) and i.obra = p_obra and i.instalado and i.acta_id is null;
  get diagnostics cnt = row_count;
  if cnt = 0 then raise exception 'No hay ítems instalados pendientes de acta en la selección'; end if;
  update public.actas set n_items = cnt where actas.id = a_id;
  return query select a_id, a_num, cnt;
end; $$;
revoke all on function public.crear_acta(text, bigint[], date, text) from public, anon;
grant execute on function public.crear_acta(text, bigint[], date, text) to authenticated;

-- Anular un acta (solo gerente): sus ítems vuelven a quedar pendientes de acta
create or replace function public.anular_acta(p_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if not public.es_gerente() then raise exception 'Solo el gerente puede anular actas'; end if;
  perform set_config('elp.acta', '1', true);
  update public.items set acta_id = null where acta_id = p_id;
  get diagnostics cnt = row_count;
  update public.actas set anulada = true where id = p_id;
  return cnt;
end; $$;
revoke all on function public.anular_acta(bigint) from public, anon;
grant execute on function public.anular_acta(bigint) to authenticated;
