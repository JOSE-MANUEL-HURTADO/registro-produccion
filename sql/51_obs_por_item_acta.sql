-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Observaciones POR ÍTEM en las actas de entrega
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Mientras se entrega (al escanear cada ítem) se puede anotar una observación
--  de ese ítem: "falta silicona", "vidrio rayado", "pendiente manija"…
--  Salen debajo de cada ítem en el acta; las observaciones generales salen
--  al final. Después de firmada el acta ya no se cambian.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.actas_obs_items (
  acta_id bigint not null references public.actas(id) on delete cascade,
  item_id bigint not null references public.items(id) on delete cascade,
  texto text not null,
  quien text,
  creada timestamptz not null default now(),
  primary key (acta_id, item_id)
);
alter table public.actas_obs_items enable row level security;
drop policy if exists actas_obs_items_leer on public.actas_obs_items;
create policy actas_obs_items_leer on public.actas_obs_items for select to authenticated
  using (coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','entrega','recibe'), false));
grant select on public.actas_obs_items to authenticated;
grant all on public.actas_obs_items to service_role;

create or replace function public.acta_item_obs(p_acta bigint, p_item bigint, p_texto text)
returns void language plpgsql security definer set search_path = public as $$
declare est text;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  select estado into est from public.actas where id = p_acta;
  if not found then raise exception 'Acta no encontrada'; end if;
  if coalesce(est, '') <> 'abierta' then raise exception 'El acta ya está cerrada: las observaciones no se pueden cambiar'; end if;
  if not exists (select 1 from public.items where id = p_item and acta_id = p_acta) then raise exception 'Ese ítem no está en el acta'; end if;
  if nullif(btrim(p_texto), '') is null then
    delete from public.actas_obs_items where acta_id = p_acta and item_id = p_item;
  else
    insert into public.actas_obs_items (acta_id, item_id, texto, quien)
    values (p_acta, p_item, btrim(p_texto), (select nombre from public.perfiles where id = auth.uid()))
    on conflict (acta_id, item_id) do update set texto = excluded.texto, quien = excluded.quien, creada = now();
  end if;
end; $$;
revoke all on function public.acta_item_obs(bigint, bigint, text) from public, anon;
grant execute on function public.acta_item_obs(bigint, bigint, text) to authenticated;

-- Quien recibe ve también la observación de cada ítem al escanear el acta
create or replace function public.campo_acta(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a jsonb; its jsonb; recs jsonb;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','entrega','recibe'), false) is not true then raise exception 'Sin permiso'; end if;
  select jsonb_build_object('id', id, 'num', num, 'obra', obra, 'fecha', fecha, 'recibe', recibe, 'anulada', anulada, 'estado', estado, 'observaciones', observaciones) into a from public.actas where id = p_id;
  if a is null then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'op', i.op, 'op_instalacion', i.op_instalacion, 'item', i.item, 'piso', i.piso,
           'ubicacion', i.ubicacion, 'entregado_en', i.entregado_en, 'recepcion_id', i.recepcion_id, 'obs', o.texto) order by i.op_instalacion), '[]')
    into its from public.items i left join public.actas_obs_items o on o.acta_id = p_id and o.item_id = i.id
   where i.acta_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'cargo', cargo, 'creada', creada, 'n_items', n_items) order by id), '[]')
    into recs from public.recepciones where acta_id = p_id;
  return jsonb_build_object('acta', a, 'items', its, 'recs', recs);
end; $$;

select 'Listo ✓ — ya se pueden anotar observaciones por ítem en las actas' as resultado;
