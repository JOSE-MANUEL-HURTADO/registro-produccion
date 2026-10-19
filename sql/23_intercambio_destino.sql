-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Intercambio de destino entre unidades de la misma OP
--  Las unidades de una OP son iguales (mismo tipo de ventana). En el
--  cargue se puede subir cualquiera: si la escaneada no es la que pedía
--  la orden de despacho, la app le pasa el destino (ubicación y piso)
--  de la que estaba planeada, y viceversa. Queda registrado.
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.intercambios_destino (
  id        bigserial primary key,
  op        text,
  item_a    bigint, op_inst_a text,
  item_b    bigint, op_inst_b text,
  ubic_a    text, piso_a text,      -- destino que tenía A (y pasa a B)
  ubic_b    text, piso_b text,      -- destino que tenía B (y pasa a A)
  cuando    timestamptz not null default now(),
  usuario   uuid default auth.uid()
);
alter table public.intercambios_destino enable row level security;
drop policy if exists inter_select on public.intercambios_destino;
create policy inter_select on public.intercambios_destino for select to authenticated using (public.es_interno());

create or replace function public.intercambiar_destino(p_a bigint, p_b bigint)
returns void language plpgsql security definer set search_path = public as $$
declare a public.items; b public.items;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  select * into a from public.items where id = p_a for update;
  select * into b from public.items where id = p_b for update;
  if a.id is null or b.id is null then raise exception 'Ítem no encontrado'; end if;
  if a.op is distinct from b.op then raise exception 'Solo se intercambian unidades de la misma OP'; end if;
  if a.despachado or b.despachado or a.instalado or b.instalado then raise exception 'No se intercambian unidades ya despachadas o instaladas'; end if;
  insert into public.intercambios_destino (op, item_a, op_inst_a, item_b, op_inst_b, ubic_a, piso_a, ubic_b, piso_b)
    values (a.op, a.id, a.op_instalacion, b.id, b.op_instalacion, a.ubicacion, a.piso, b.ubicacion, b.piso);
  perform set_config('elp.swap', '1', true);   -- ver SQL 24 (proteger_items)
  update public.items set ubicacion = b.ubicacion, piso = b.piso where id = a.id;
  update public.items set ubicacion = a.ubicacion, piso = a.piso where id = b.id;
  perform set_config('elp.swap', '', true);
end; $$;
revoke all on function public.intercambiar_destino(bigint, bigint) from public, anon;
grant execute on function public.intercambiar_destino(bigint, bigint) to authenticated;
