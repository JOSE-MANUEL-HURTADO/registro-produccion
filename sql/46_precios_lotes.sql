-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Cambios de precio por lote (para poder reversarlos)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada vez que se cargan precios desde una liquidación queda un "lote"
--  con el precio que tenía cada ítem antes y el nuevo. Desde la app el
--  gerente puede reversar el lote completo.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.precios_lotes (
  id           bigserial primary key,
  obra         text not null,
  archivo      text,
  detalle      text,
  n_items      integer,
  creado       timestamptz not null default now(),
  usuario      uuid default auth.uid(),
  revertido_en timestamptz
);
create table if not exists public.precios_lote_items (
  lote_id  bigint not null references public.precios_lotes(id) on delete cascade,
  item_id  bigint not null,
  antes    numeric,
  despues  numeric,
  primary key (lote_id, item_id)
);
alter table public.precios_lotes enable row level security;
alter table public.precios_lote_items enable row level security;
drop policy if exists pl_gerente on public.precios_lotes;
create policy pl_gerente on public.precios_lotes for all to authenticated using (public.es_gerente()) with check (public.es_gerente());
drop policy if exists pli_gerente on public.precios_lote_items;
create policy pli_gerente on public.precios_lote_items for all to authenticated using (public.es_gerente()) with check (public.es_gerente());
grant select, insert, update, delete on public.precios_lotes, public.precios_lote_items to authenticated;
grant usage, select on sequence public.precios_lotes_id_seq to authenticated;

-- Reversar un lote: cada ítem vuelve al precio que tenía, salvo que lo hayan cambiado después
create or replace function public.precios_reversar(p_lote bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if exists (select 1 from public.precios_lotes where id = p_lote and revertido_en is not null) then
    raise exception 'Ese cambio de precios ya se había reversado';
  end if;
  insert into public.items_comercial (item_id, precio)
    select li.item_id, li.antes from public.precios_lote_items li
      join public.items_comercial c on c.item_id = li.item_id
     where li.lote_id = p_lote and c.precio is not distinct from li.despues
  on conflict (item_id) do update set precio = excluded.precio;
  get diagnostics n = row_count;
  update public.precios_lotes set revertido_en = now() where id = p_lote;
  return n;
end; $$;
revoke all on function public.precios_reversar(bigint) from public, anon;
grant execute on function public.precios_reversar(bigint) to authenticated;

select 'Listo ✓ — ya se pueden cargar precios de la liquidación y reversarlos' as resultado;
