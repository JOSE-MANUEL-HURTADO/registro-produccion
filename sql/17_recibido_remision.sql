-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Recibido de remisiones en obra (con firma en la app)
--  Al llegar el despacho se escanea el QR de la remisión, quien recibe
--  confirma las cantidades por OP (y anota novedades) y firma.
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.recepciones_remision (
  id            bigserial primary key,
  remision      text not null unique,
  nombre        text not null,
  cargo         text,
  documento     text,
  observaciones text,
  detalle       jsonb not null default '[]',   -- [{op, enviado, recibido}]
  n_enviado     integer not null default 0,
  n_recibido    integer not null default 0,
  firma         text not null,                 -- imagen PNG de la firma (data URL)
  creada        timestamptz not null default now(),
  usuario       uuid default auth.uid()
);
alter table public.recepciones_remision enable row level security;
drop policy if exists rec_rem_select on public.recepciones_remision;
create policy rec_rem_select on public.recepciones_remision for select to authenticated using (public.rol_actual() is not null);

create or replace function public.firmar_remision(p_rem text, p_nombre text, p_cargo text, p_doc text, p_obs text, p_detalle jsonb, p_firma text)
returns bigint language plpgsql security definer set search_path = public as $$
declare r_id bigint; env integer; rec integer;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros'), false) is not true then raise exception 'Sin permiso'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de quien recibe'; end if;
  if coalesce(length(p_firma), 0) < 200 then raise exception 'Falta la firma'; end if;
  if length(p_firma) > 400000 then raise exception 'La firma es demasiado grande'; end if;
  if not exists (select 1 from public.items where remision = p_rem and despachado) then
    raise exception 'No hay ítems despachados con la remisión %', p_rem;
  end if;
  if exists (select 1 from public.recepciones_remision where remision = p_rem) then
    raise exception 'La remisión % ya tiene recibido firmado', p_rem;
  end if;
  select coalesce(sum((e->>'enviado')::int), 0), coalesce(sum((e->>'recibido')::int), 0) into env, rec
    from jsonb_array_elements(coalesce(p_detalle, '[]'::jsonb)) e;
  insert into public.recepciones_remision (remision, nombre, cargo, documento, observaciones, detalle, n_enviado, n_recibido, firma)
    values (p_rem, trim(p_nombre), nullif(trim(p_cargo), ''), nullif(trim(p_doc), ''), nullif(trim(p_obs), ''), coalesce(p_detalle, '[]'::jsonb), env, rec, p_firma)
    returning id into r_id;
  return r_id;
end; $$;
revoke all on function public.firmar_remision(text, text, text, text, text, jsonb, text) from public, anon;
grant execute on function public.firmar_remision(text, text, text, text, text, jsonb, text) to authenticated;

-- Quitar un recibido mal hecho (solo gerente)
create or replace function public.anular_recibido_remision(p_rem text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Solo el gerente puede anular un recibido'; end if;
  delete from public.recepciones_remision where remision = p_rem;
end; $$;
revoke all on function public.anular_recibido_remision(text) from public, anon;
grant execute on function public.anular_recibido_remision(text) to authenticated;
