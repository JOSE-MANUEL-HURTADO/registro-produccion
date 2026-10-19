-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Piso al instalar (unidades sin apartamento definido)
--  Algunas unidades siguen con la lista completa de apartamentos en la
--  ubicación porque no se sabe en cuál van (p. ej. Vilanova 6185-17,
--  Torreón 6269-17). Al instalarlas, el instalador escoge el piso y esta
--  función se lo asigna; si la lista tiene un apartamento libre en ese
--  piso, también le pone ese apartamento como ubicación.
--  Requiere el SQL 30 (función ubic_partes). Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create or replace function public.asignar_piso_instalacion(p_id bigint, p_piso text)
returns setof public.items language plpgsql security definer set search_path = public as $$
declare it public.items; pis int; c int; lug text; usados text[];
begin
  if not (public.puede_registrar() or public.rol_actual() = 'cobros') then raise exception 'Sin permiso'; end if;
  select * into it from public.items where id = p_id for update;
  if it.id is null then raise exception 'Ítem no encontrado'; end if;
  if coalesce(it.instalado, false) or it.acta_id is not null then raise exception 'El ítem ya está instalado'; end if;
  if (select count(*) from public.ubic_partes(it.ubicacion)) < 2 then
    raise exception 'Este ítem ya tiene su apartamento definido (%)', it.ubicacion;
  end if;
  pis := nullif(regexp_replace(coalesce(p_piso, ''), '\D', '', 'g'), '')::int;
  if pis is null then raise exception 'Piso no válido'; end if;
  select array_agg(ubicacion) into usados from public.items
    where op = it.op and obra is not distinct from it.obra and id <> it.id;
  select x.cod, x.lugar into c, lug from public.ubic_partes(it.ubicacion) x
    where x.cod / 100 = pis and not ((x.lugar || ' ' || x.cod) = any(coalesce(usados, '{}')))
    order by x.n limit 1;
  perform set_config('elp.swap', '1', true);
  update public.items set piso = 'PISO ' || pis,
         ubicacion = case when c is not null then lug || ' ' || c else ubicacion end
   where id = it.id;
  perform set_config('elp.swap', '', true);
  return query select * from public.items where id = it.id;
end; $$;
revoke all on function public.asignar_piso_instalacion(bigint, text) from public, anon;
grant execute on function public.asignar_piso_instalacion(bigint, text) to authenticated;
