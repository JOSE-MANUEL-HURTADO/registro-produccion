-- ════════════════════════════════════════════════════════════════
--  CONTRASEÑAS sin correo: el director pone una contraseña temporal y el usuario la cambia al entrar
--  (varios usuarios se crearon con correos que no existen, así que "olvidé mi contraseña" por correo no sirve)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
alter table public.perfiles add column if not exists cambiar_clave boolean not null default false;

-- El director asigna una contraseña temporal; el usuario queda obligado a cambiarla al entrar
create or replace function public.admin_cambiar_clave(p_id uuid, p_clave text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not coalesce(public.es_gerente(), false) then raise exception 'Sin permiso: solo el director'; end if;
  if length(coalesce(p_clave, '')) < 6 then raise exception 'La contraseña debe tener al menos 6 caracteres'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_clave, extensions.gen_salt('bf')), updated_at = now() where id = p_id;
  if not found then raise exception 'Usuario no encontrado'; end if;
  update public.perfiles set cambiar_clave = true where id = p_id;
end; $$;
revoke all on function public.admin_cambiar_clave(uuid, text) from public, anon;
grant execute on function public.admin_cambiar_clave(uuid, text) to authenticated;

-- El usuario ya puso su propia contraseña
create or replace function public.mi_clave_cambiada()
returns void language sql security definer set search_path = public as $$
  update public.perfiles set cambiar_clave = false where id = auth.uid();
$$;
revoke all on function public.mi_clave_cambiada() from public, anon;
grant execute on function public.mi_clave_cambiada() to authenticated;

select 'Listo SQL 107 — cambio de contraseña' as r;
