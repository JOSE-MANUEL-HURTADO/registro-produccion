-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Instalar en otro piso lo que se despachó para un piso
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Ej.: se despacharon los ítems del piso 5, pero en obra los instalaron en el piso 1.
--  La unidad despachada toma el destino (piso y apartamento) de una unidad del piso 1 que
--  todavía no se ha despachado, y esa unidad queda para el piso 5. Las unidades de una OP son
--  iguales, así que solo cambia a dónde va cada una. Queda registrado en intercambios_destino.
-- ════════════════════════════════════════════════════════════════
create or replace function public.reubicar_instalacion(p_desp bigint, p_dest bigint)
returns void language plpgsql security definer set search_path = public as $$
declare a public.items; b public.items;
begin
  if not coalesce(public.rol_actual() in ('gerente','asistente','cobros','instalador','entrega'), false) then raise exception 'Sin permiso'; end if;
  select * into a from public.items where id = p_desp for update;
  select * into b from public.items where id = p_dest for update;
  if a.id is null or b.id is null then raise exception 'Ítem no encontrado'; end if;
  if a.op is distinct from b.op or a.obra is distinct from b.obra then raise exception 'Solo entre unidades de la misma OP y obra'; end if;
  if not coalesce(a.despachado, false) then raise exception 'La unidad % no está despachada', a.op_instalacion; end if;
  if coalesce(a.instalado, false) or coalesce(b.instalado, false) or a.acta_id is not null or b.acta_id is not null then
    raise exception 'No se cambia el destino de unidades ya instaladas o en un acta';
  end if;
  insert into public.intercambios_destino (op, item_a, op_inst_a, item_b, op_inst_b, ubic_a, piso_a, ubic_b, piso_b)
    values (a.op, a.id, a.op_instalacion, b.id, b.op_instalacion, a.ubicacion, a.piso, b.ubicacion, b.piso);
  perform set_config('elp.swap', '1', true);
  update public.items set ubicacion = b.ubicacion, piso = b.piso where id = a.id;
  update public.items set ubicacion = a.ubicacion, piso = a.piso where id = b.id;
  perform set_config('elp.swap', '', true);
end; $$;
revoke all on function public.reubicar_instalacion(bigint, bigint) from public, anon;
grant execute on function public.reubicar_instalacion(bigint, bigint) to authenticated;

select 'Listo SQL 84 — instalar en otro piso' as r;
