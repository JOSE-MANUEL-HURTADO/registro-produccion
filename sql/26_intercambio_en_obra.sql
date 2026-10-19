-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Intercambio de destino también al instalar en obra
--  En obra el instalador toma cualquier unidad de la OP. Al escanear
--  para instalación dice dónde la puso; si no era su ubicación, la app
--  le pasa esa ubicación y piso (y la otra unidad toma los de esta).
--  Se permite entre dos unidades de la misma OP y la misma obra que:
--    · ninguna está despachada (cargue), o
--    · las dos están despachadas, sin instalar y sin acta (instalación).
--  También lo puede hacer el usuario de cobros (registra instalación).
--  Queda registrado en intercambios_destino. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create or replace function public.intercambiar_destino(p_a bigint, p_b bigint)
returns void language plpgsql security definer set search_path = public as $$
declare a public.items; b public.items;
begin
  if not (public.puede_registrar() or public.rol_actual() = 'cobros') then raise exception 'Sin permiso'; end if;
  select * into a from public.items where id = p_a for update;
  select * into b from public.items where id = p_b for update;
  if a.id is null or b.id is null then raise exception 'Ítem no encontrado'; end if;
  if a.op is distinct from b.op or a.obra is distinct from b.obra then raise exception 'Solo se intercambian unidades de la misma OP y obra'; end if;
  if coalesce(a.instalado, false) or coalesce(b.instalado, false) or a.acta_id is not null or b.acta_id is not null then
    raise exception 'No se intercambian unidades ya instaladas o en un acta';
  end if;
  if coalesce(a.despachado, false) <> coalesce(b.despachado, false) then
    raise exception 'Solo se intercambian dos unidades sin despachar o dos ya despachadas';
  end if;
  if not coalesce(a.despachado, false) and public.rol_actual() = 'cobros' then raise exception 'Sin permiso'; end if;
  insert into public.intercambios_destino (op, item_a, op_inst_a, item_b, op_inst_b, ubic_a, piso_a, ubic_b, piso_b)
    values (a.op, a.id, a.op_instalacion, b.id, b.op_instalacion, a.ubicacion, a.piso, b.ubicacion, b.piso);
  perform set_config('elp.swap', '1', true);   -- ver SQL 24 (proteger_items)
  update public.items set ubicacion = b.ubicacion, piso = b.piso where id = a.id;
  update public.items set ubicacion = a.ubicacion, piso = a.piso where id = b.id;
  perform set_config('elp.swap', '', true);
end; $$;
revoke all on function public.intercambiar_destino(bigint, bigint) from public, anon;
grant execute on function public.intercambiar_destino(bigint, bigint) to authenticated;
