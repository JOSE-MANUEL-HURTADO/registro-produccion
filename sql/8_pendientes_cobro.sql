-- Resumen de lo pendiente por cobrar (despacho e instalación), agrupado por obra y OP
create or replace function public.pendientes_cobro()
returns table(tipo text, obra text, op text, n integer, m2 numeric, valor numeric, fecha date, remisiones text)
language plpgsql stable security definer set search_path = public as $$
declare r text := public.rol_actual();
begin
  if r is null or r not in ('gerente','cobros','consulta') then raise exception 'Sin permiso'; end if;
  return query
    select 'D'::text, i.obra, coalesce(i.op,''), count(*)::int, sum(i.m2),
           case when r in ('gerente','consulta') then sum(c.precio) end,
           max(i.fecha_despacho), string_agg(distinct i.remision, ', ')
    from public.items i left join public.items_comercial c on c.item_id = i.id
    where i.despachado and coalesce(c.cobrado_despacho, false) = false
    group by i.obra, coalesce(i.op,'')
    union all
    select 'I'::text, i.obra, coalesce(i.op,''), count(*)::int, sum(i.m2),
           case when r in ('gerente','consulta') then sum(c.precio) end,
           max(i.fecha_instalacion), string_agg(distinct i.instalador, ', ')
    from public.items i left join public.items_comercial c on c.item_id = i.id
    where i.instalado and coalesce(c.cobrado_instalacion, false) = false
    group by i.obra, coalesce(i.op,'');
end; $$;
revoke all on function public.pendientes_cobro() from public, anon;
grant execute on function public.pendientes_cobro() to authenticated;
select 'Listo ✓' as resultado;
