-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Observaciones en las actas de entrega
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Mientras el acta está en curso, quien entrega (Elíptica) escribe las
--  observaciones; quien recibe las ve antes de firmar y salen en el PDF.
--  Después de firmada ya no se pueden cambiar.
-- ════════════════════════════════════════════════════════════════
alter table public.actas add column if not exists observaciones text;

create or replace function public.acta_observaciones(p_acta bigint, p_texto text)
returns void language plpgsql security definer set search_path = public as $$
declare est text;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  select estado into est from public.actas where id = p_acta for update;
  if not found then raise exception 'Acta no encontrada'; end if;
  if coalesce(est, '') <> 'abierta' then raise exception 'El acta ya está cerrada: las observaciones no se pueden cambiar'; end if;
  update public.actas set observaciones = nullif(btrim(p_texto), '') where id = p_acta;
end; $$;
revoke all on function public.acta_observaciones(bigint, text) from public, anon;
grant execute on function public.acta_observaciones(bigint, text) to authenticated;

-- Quien recibe (usuarios de campo) también ve las observaciones al escanear el acta
create or replace function public.campo_acta(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a jsonb; its jsonb; recs jsonb;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','entrega','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  select jsonb_build_object('id', id, 'num', num, 'obra', obra, 'fecha', fecha, 'recibe', recibe, 'anulada', anulada, 'estado', estado, 'observaciones', observaciones) into a from public.actas where id = p_id;
  if a is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'op', op, 'op_instalacion', op_instalacion, 'item', item, 'piso', piso,
           'ubicacion', ubicacion, 'entregado_en', entregado_en, 'recepcion_id', recepcion_id) order by op_instalacion), '[]')
    into its from public.items where acta_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'cargo', cargo, 'creada', creada, 'n_items', n_items) order by id), '[]')
    into recs from public.recepciones where acta_id = p_id;
  return jsonb_build_object('acta', a, 'items', its, 'recs', recs);
end; $$;

select 'Listo ✓ — las actas ya tienen observaciones' as resultado;
