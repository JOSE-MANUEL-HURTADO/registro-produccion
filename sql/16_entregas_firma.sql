-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Entrega real de ítems y firma de recibido de las actas
--  (correr después de 15_actas_entrega.sql)
--  · Cada ítem del acta se marca "entregado" al escanear su QR
--  · El representante de la obra firma en la app lo entregado → constancia
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.recepciones (
  id        bigserial primary key,
  acta_id   bigint not null references public.actas(id),
  nombre    text not null,
  cargo     text,
  documento text,
  firma     text not null,              -- imagen PNG de la firma (data URL)
  n_items   integer not null default 0,
  creada    timestamptz not null default now(),
  usuario   uuid default auth.uid()
);
alter table public.recepciones enable row level security;
drop policy if exists recepciones_select on public.recepciones;
create policy recepciones_select on public.recepciones for select to authenticated using (public.rol_actual() is not null);

alter table public.items add column if not exists entregado_en  timestamptz;
alter table public.items add column if not exists entregado_por text;
alter table public.items add column if not exists recepcion_id  bigint references public.recepciones(id);

-- Candado: estos campos solo cambian por las funciones; no se desinstala un ítem que está en un acta
create or replace function public.chk_items_acta()
returns trigger language plpgsql as $$
begin
  if (new.acta_id is distinct from old.acta_id or new.entregado_en is distinct from old.entregado_en
      or new.entregado_por is distinct from old.entregado_por or new.recepcion_id is distinct from old.recepcion_id)
     and coalesce(current_setting('elp.acta', true), '') <> '1' then
    raise exception 'Las actas y entregas solo se cambian desde Actas de entrega o el escáner';
  end if;
  if old.acta_id is not null and new.acta_id is not null and coalesce(old.instalado, false) and not coalesce(new.instalado, false) then
    raise exception 'El ítem % (OP %) ya está en un acta de entrega: primero anula el acta', new.item, new.op_instalacion;
  end if;
  return new;
end; $$;

-- Marcar ítems como entregados en obra (escaneo del QR del ítem)
create or replace function public.entregar_items(p_ids bigint[])
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  perform set_config('elp.acta', '1', true);
  update public.items set entregado_en = now(),
         entregado_por = (select nombre from public.perfiles where id = auth.uid())
   where id = any(p_ids) and acta_id is not null and instalado and entregado_en is null;
  get diagnostics cnt = row_count;
  return cnt;
end; $$;
revoke all on function public.entregar_items(bigint[]) from public, anon;
grant execute on function public.entregar_items(bigint[]) to authenticated;

-- Deshacer una entrega (solo si todavía no está firmada)
create or replace function public.deshacer_entrega(p_ids bigint[])
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  perform set_config('elp.acta', '1', true);
  update public.items set entregado_en = null, entregado_por = null
   where id = any(p_ids) and recepcion_id is null;
  get diagnostics cnt = row_count;
  return cnt;
end; $$;
revoke all on function public.deshacer_entrega(bigint[]) from public, anon;
grant execute on function public.deshacer_entrega(bigint[]) to authenticated;

-- Firma de recibido: cubre los ítems del acta ya entregados y aún sin firma
create or replace function public.firmar_recepcion(p_acta bigint, p_nombre text, p_cargo text, p_doc text, p_firma text)
returns table(id bigint, n integer)
language plpgsql security definer set search_path = public as $$
declare r_id bigint; cnt integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros'), false) is not true then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de quien recibe'; end if;
  if coalesce(length(p_firma), 0) < 200 then raise exception 'Falta la firma'; end if;
  if length(p_firma) > 400000 then raise exception 'La firma es demasiado grande'; end if;
  perform pg_advisory_xact_lock(hashtext('recepcion:' || p_acta));
  insert into public.recepciones (acta_id, nombre, cargo, documento, firma)
    values (p_acta, trim(p_nombre), nullif(trim(p_cargo), ''), nullif(trim(p_doc), ''), p_firma)
    returning recepciones.id into r_id;
  perform set_config('elp.acta', '1', true);
  update public.items set recepcion_id = r_id
   where acta_id = p_acta and entregado_en is not null and recepcion_id is null;
  get diagnostics cnt = row_count;
  if cnt = 0 then raise exception 'No hay ítems entregados pendientes de firma en esta acta'; end if;
  update public.recepciones set n_items = cnt where recepciones.id = r_id;
  return query select r_id, cnt;
end; $$;
revoke all on function public.firmar_recepcion(bigint, text, text, text, text) from public, anon;
grant execute on function public.firmar_recepcion(bigint, text, text, text, text) to authenticated;

-- Anular acta: no se permite si ya tiene firmas; lo entregado sin firmar se limpia
create or replace function public.anular_acta(p_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare cnt integer;
begin
  if not public.es_gerente() then raise exception 'Solo el gerente puede anular actas'; end if;
  if exists (select 1 from public.items where acta_id = p_id and recepcion_id is not null) then
    raise exception 'Esta acta ya tiene ítems recibidos con firma: no se puede anular';
  end if;
  perform set_config('elp.acta', '1', true);
  update public.items set acta_id = null, entregado_en = null, entregado_por = null where acta_id = p_id;
  get diagnostics cnt = row_count;
  update public.actas set anulada = true where id = p_id;
  return cnt;
end; $$;
