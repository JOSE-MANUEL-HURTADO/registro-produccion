-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Orden obligatorio ensamble → despacho → instalación
--             y consulta de cortes cobrados
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════

-- 1. La base rechaza:
--    · despachar un ítem que no está ensamblado
--    · instalar un ítem que no está despachado
--    · quitar el despacho a un ítem instalado, o quitar el ensamble a uno despachado
--    Solo revisa cuando ese dato CAMBIA, así los registros viejos se pueden seguir editando.
create or replace function public.validar_secuencia()
returns trigger language plpgsql as $$
declare ens boolean := new.dia_final is not null or coalesce(old.status,'') in ('ENSAMBLADO','DESPACHADO');
begin
  if new.despachado and not coalesce(old.despachado, false) and not ens then
    raise exception 'No se puede despachar: el ítem % (OP %) no está ensamblado', new.item, new.op;
  end if;
  if new.instalado and not coalesce(old.instalado, false) and not coalesce(new.despachado, false) then
    raise exception 'No se puede instalar: el ítem % (OP %) no está despachado', new.item, new.op;
  end if;
  if coalesce(old.despachado, false) and not coalesce(new.despachado, false) and coalesce(new.instalado, false) then
    raise exception 'El ítem % (OP %) está instalado: primero quita la instalación', new.item, new.op;
  end if;
  if old.dia_final is not null and new.dia_final is null and coalesce(new.despachado, false) then
    raise exception 'El ítem % (OP %) está despachado: primero quita el despacho', new.item, new.op;
  end if;
  return new;
end; $$;
drop trigger if exists trg_validar_secuencia on public.items;
create trigger trg_validar_secuencia before update on public.items
  for each row execute function public.validar_secuencia();

-- 2. Quitar un cobro funciona aunque el ítem haya cambiado de estado
create or replace function public.marcar_cobros(p_ids bigint[], p_tipo text, p_cobrado boolean, p_fecha date, p_num text)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not public.ve_cobros() then raise exception 'Sin permiso para registrar cobros'; end if;
  if p_tipo not in ('despacho','instalacion') then raise exception 'Tipo de cobro no válido'; end if;
  if p_cobrado and p_fecha is null then raise exception 'Falta la fecha de corte'; end if;
  if p_tipo = 'despacho' then
    insert into public.items_comercial (item_id, cobrado_despacho, fecha_corte_despacho, num_corte_despacho)
    select i.id, p_cobrado, case when p_cobrado then p_fecha end, case when p_cobrado then p_num end
    from public.items i where i.id = any(p_ids) and (i.despachado or not p_cobrado)
    on conflict (item_id) do update set cobrado_despacho = excluded.cobrado_despacho,
      fecha_corte_despacho = excluded.fecha_corte_despacho, num_corte_despacho = excluded.num_corte_despacho;
  else
    insert into public.items_comercial (item_id, cobrado_instalacion, fecha_corte_instalacion, num_corte_instalacion)
    select i.id, p_cobrado, case when p_cobrado then p_fecha end, case when p_cobrado then p_num end
    from public.items i where i.id = any(p_ids) and (i.instalado or not p_cobrado)
    on conflict (item_id) do update set cobrado_instalacion = excluded.cobrado_instalacion,
      fecha_corte_instalacion = excluded.fecha_corte_instalacion, num_corte_instalacion = excluded.num_corte_instalacion;
  end if;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.marcar_cobros(bigint[], text, boolean, date, text) from public, anon;
grant execute on function public.marcar_cobros(bigint[], text, boolean, date, text) to authenticated;

-- 3. Cortes cobrados por obra (gerente y cobros)
create or replace function public.cortes_cobro()
returns table(tipo text, obra text, num text, fecha date, n integer, m2 numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.ve_cobros() then raise exception 'Sin permiso'; end if;
  return query
    select 'D'::text, i.obra, coalesce(c.num_corte_despacho,''), max(c.fecha_corte_despacho), count(*)::int, sum(i.m2)
    from public.items i join public.items_comercial c on c.item_id = i.id
    where c.cobrado_despacho
    group by i.obra, coalesce(c.num_corte_despacho,'')
    union all
    select 'I'::text, i.obra, coalesce(c.num_corte_instalacion,''), max(c.fecha_corte_instalacion), count(*)::int, sum(i.m2)
    from public.items i join public.items_comercial c on c.item_id = i.id
    where c.cobrado_instalacion
    group by i.obra, coalesce(c.num_corte_instalacion,'');
end; $$;
revoke all on function public.cortes_cobro() from public, anon;
grant execute on function public.cortes_cobro() to authenticated;

select 'Listo ✓' as resultado;
