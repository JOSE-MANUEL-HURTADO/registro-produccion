-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Cancelar despachos (toda una remisión o ítems sueltos)
--  · Quedan registrados con motivo, quién y cuándo
--  · No se puede cancelar: un ítem instalado, uno con el despacho ya
--    cobrado, ni uno de una remisión que ya tiene recibido firmado
--    (primero el gerente anula ese recibido)
--  Correr después del 20. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.despachos_cancelados (
  id         bigserial primary key,
  item_id    bigint,
  obra       text,
  op         text,
  op_instalacion text,
  remision   text,
  fecha_despacho date,
  motivo     text not null,
  cuando     timestamptz not null default now(),
  usuario    uuid default auth.uid(),
  quien      text
);
alter table public.despachos_cancelados enable row level security;
drop policy if exists desp_canc_select on public.despachos_cancelados;
create policy desp_canc_select on public.despachos_cancelados for select to authenticated using (public.es_interno());

create or replace function public.cancelar_despacho(p_ids bigint[], p_motivo text)
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer; bloq text;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Escribe el motivo de la cancelación'; end if;
  select string_agg(coalesce(op_instalacion, op), ', ') into bloq from public.items where id = any(p_ids) and instalado;
  if bloq is not null then raise exception 'No se puede cancelar: ya están instalados %', bloq; end if;
  select string_agg(coalesce(i.op_instalacion, i.op), ', ') into bloq
    from public.items i join public.items_comercial c on c.item_id = i.id
   where i.id = any(p_ids) and c.cobrado_despacho;
  if bloq is not null then raise exception 'No se puede cancelar: el despacho ya fue cobrado en %', bloq; end if;
  select string_agg(distinct i.remision, ', ') into bloq
    from public.items i join public.recepciones_remision r on r.remision = i.remision
   where i.id = any(p_ids);
  if bloq is not null then raise exception 'La remisión % ya fue recibida con firma en obra: el gerente debe anular ese recibido primero', bloq; end if;
  insert into public.despachos_cancelados (item_id, obra, op, op_instalacion, remision, fecha_despacho, motivo, quien)
    select id, obra, op, op_instalacion, remision, fecha_despacho, trim(p_motivo), (select nombre from public.perfiles where perfiles.id = auth.uid())
      from public.items where id = any(p_ids) and despachado;
  update public.items set despachado = false, fecha_despacho = null, remision = null,
         status = case when dia_final is not null then 'ENSAMBLADO' when ensamblador is not null or dia_inicio is not null then 'PRODUCCIÓN' else 'EN COLA' end
   where id = any(p_ids) and despachado;
  get diagnostics cnt = row_count;
  return cnt;
end; $$;
revoke all on function public.cancelar_despacho(bigint[], text) from public, anon;
grant execute on function public.cancelar_despacho(bigint[], text) to authenticated;

-- Candado también para cambios directos: quitar un despacho cobrado o de una remisión recibida
create or replace function public.chk_quitar_despacho()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(old.despachado, false) and not coalesce(new.despachado, false) then
    if exists (select 1 from public.items_comercial c where c.item_id = old.id and c.cobrado_despacho) then
      raise exception 'El despacho del ítem % (OP %) ya fue cobrado: no se puede quitar', old.item, coalesce(old.op_instalacion, old.op);
    end if;
    if old.remision is not null and exists (select 1 from public.recepciones_remision r where r.remision = old.remision) then
      raise exception 'La remisión % ya fue recibida con firma: el gerente debe anular el recibido primero', old.remision;
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_quitar_despacho on public.items;
create trigger trg_quitar_despacho before update on public.items
  for each row execute function public.chk_quitar_despacho();
