-- Gestión de usuarios desde la app (solo gerente)
create or replace function public.usuarios_lista()
returns table(id uuid, email text, nombre text, rol text, creado timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  return query select u.id, u.email::text, p.nombre, p.rol, u.created_at
    from auth.users u left join public.perfiles p on p.id = u.id order by u.created_at;
end; $$;
revoke all on function public.usuarios_lista() from public, anon;
grant execute on function public.usuarios_lista() to authenticated;

create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;
revoke all on function public.asignar_rol(uuid, text, text) from public, anon;
grant execute on function public.asignar_rol(uuid, text, text) to authenticated;
