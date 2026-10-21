-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Rol nuevo: PLANTA (operario que solo escanea)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  planta: entra directo al escáner y solo puede registrar
--    · procesos de planta (corte, troquelado, mecanizado, vidrio, prealistado)
--    · inicio y fin de ensamble
--    · despacho (cargar ítems al camión, con o sin orden de despacho)
--  No ve precios ni la lista de obras, no programa, no instala, no entrega
--  en obra, no cancela despachos ni cambia datos de la OP.
-- ════════════════════════════════════════════════════════════════

-- 1. Rol permitido
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta'));

-- 2. Puede registrar en el escáner y leer lo que el escáner necesita (OP, órdenes de despacho, programaciones)
create or replace function public.puede_registrar()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente','planta'), false);
$$;
create or replace function public.es_interno()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','planta'), false);
$$;

-- 3. El gerente lo puede asignar desde la app (Usuarios)
create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;

-- 4. Candado: lo que PLANTA no puede tocar en los ítems, aunque lo intente por fuera de la app
create or replace function public.limitar_planta()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual(), '') <> 'planta' then return new; end if;
  if row(new.instalado, new.fecha_instalacion, new.instalador, new.acta_id, new.entregado_en, new.entregado_por,
         new.recepcion_id, new.programado, new.programacion_id, new.ens_asignado)
     is distinct from
     row(old.instalado, old.fecha_instalacion, old.instalador, old.acta_id, old.entregado_en, old.entregado_por,
         old.recepcion_id, old.programado, old.programacion_id, old.ens_asignado) then
    raise exception 'Este usuario solo registra procesos, ensamble y despacho';
  end if;
  if old.despachado and not new.despachado then
    raise exception 'Este usuario no puede cancelar despachos';
  end if;
  return new;
end; $$;
drop trigger if exists trg_00_limitar_planta on public.items;
create trigger trg_00_limitar_planta before update on public.items
  for each row execute function public.limitar_planta();

-- Programar y anular programaciones sigue siendo solo de gerente y asistente
drop policy if exists prog_no_planta_ins on public.programaciones;
create policy prog_no_planta_ins on public.programaciones as restrictive for insert to authenticated
  with check (coalesce(public.rol_actual(), '') <> 'planta');
drop policy if exists prog_no_planta_upd on public.programaciones;
create policy prog_no_planta_upd on public.programaciones as restrictive for update to authenticated
  using (coalesce(public.rol_actual(), '') <> 'planta');

revoke all on function public.limitar_planta() from public, anon;

select 'Listo ✓ — ya puedes asignar el rol "Planta (solo escanea)" en Usuarios' as resultado;
