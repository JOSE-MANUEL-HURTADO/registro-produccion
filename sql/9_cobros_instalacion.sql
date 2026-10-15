-- El usuario de cobros puede registrar instalación (y nada más de producción)
create or replace function public.registrar_instalacion(p_ids bigint[], p_instalado boolean, p_fecha date, p_instalador text)
returns setof public.items language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros'), false) is not true then
    raise exception 'Sin permiso para registrar instalación';
  end if;
  if p_instalado and p_fecha is null then raise exception 'Falta la fecha de instalación'; end if;
  return query
    update public.items
       set instalado = p_instalado,
           fecha_instalacion = case when p_instalado then p_fecha end,
           instalador = case when p_instalado then nullif(trim(upper(p_instalador)),'') end
     where id = any(p_ids)
    returning *;
end; $$;
revoke all on function public.registrar_instalacion(bigint[], boolean, date, text) from public, anon;
grant execute on function public.registrar_instalacion(bigint[], boolean, date, text) to authenticated;
select 'Listo ✓' as resultado;
