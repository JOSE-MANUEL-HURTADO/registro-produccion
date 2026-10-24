-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Novedades de instalación (evidencia con fecha y hora)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cuando un ítem no se puede instalar (vano sin terminar, fuera de medida,
--  sin acceso…) se registra la novedad con motivo, detalle y fotos.
--  · La fecha y hora la pone el SERVIDOR (no el celular): no se puede alterar.
--  · Nadie puede editar ni borrar una novedad (ni el gerente): es evidencia.
--    Solo se puede marcar "resuelta", y eso también queda con fecha, hora y quién.
--  · Las fotos quedan en una carpeta privada que tampoco se puede borrar desde la app.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.novedades (
  id bigserial primary key,
  obra text not null,
  items bigint[] not null,
  ops text,
  piso text,
  motivo text not null,
  detalle text,
  fotos text[] not null default '{}',
  creada timestamptz not null default now(),
  usuario uuid default auth.uid(),
  quien text,
  instalador text,
  resuelta_en timestamptz,
  resuelta_por text,
  resuelta_nota text
);
create index if not exists novedades_obra on public.novedades (obra, creada desc);
alter table public.novedades enable row level security;
drop policy if exists novedades_leer on public.novedades;
create policy novedades_leer on public.novedades for select to authenticated
  using (coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','instalador','entrega'), false));
grant select on public.novedades to authenticated;
grant all on public.novedades to service_role;
grant usage, select on sequence public.novedades_id_seq to service_role;

-- Registrar (la fecha y hora son las del servidor)
create or replace function public.novedad_crear(p_items bigint[], p_motivo text, p_detalle text, p_fotos text[], p_piso text, p_instalador text)
returns public.novedades language plpgsql security definer set search_path = public as $$
declare r public.novedades; n_obras int; v_obra text; v_ops text; v_n int;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente','cobros','instalador','entrega'), false) is not true then raise exception 'Sin permiso'; end if;
  if coalesce(btrim(p_motivo), '') = '' then raise exception 'Falta el motivo'; end if;
  select count(distinct obra), min(obra), string_agg(distinct op_instalacion, ', ' order by op_instalacion), count(*)
    into n_obras, v_obra, v_ops, v_n from public.items where id = any(p_items);
  if coalesce(v_n, 0) = 0 then raise exception 'Elige al menos un ítem'; end if;
  if n_obras > 1 then raise exception 'Los ítems de una novedad deben ser de la misma obra'; end if;
  insert into public.novedades (obra, items, ops, piso, motivo, detalle, fotos, creada, usuario, quien, instalador)
  values (v_obra, p_items, v_ops, nullif(btrim(p_piso), ''), btrim(p_motivo), nullif(btrim(p_detalle), ''), coalesce(p_fotos, '{}'),
          now(), auth.uid(), (select nombre from public.perfiles where id = auth.uid()), nullif(btrim(upper(p_instalador)), ''))
  returning * into r;
  return r;
end; $$;
revoke all on function public.novedad_crear(bigint[], text, text, text[], text, text) from public, anon;
grant execute on function public.novedad_crear(bigint[], text, text, text[], text, text) to authenticated;

-- Marcar resuelta (no se puede deshacer; queda quién y cuándo)
create or replace function public.novedad_resolver(p_id bigint, p_nota text)
returns public.novedades language plpgsql security definer set search_path = public as $$
declare r public.novedades;
begin
  if coalesce(public.rol_actual() in ('gerente','asistente'), false) is not true then raise exception 'Sin permiso'; end if;
  update public.novedades set resuelta_en = now(), resuelta_por = (select nombre from public.perfiles where id = auth.uid()),
         resuelta_nota = nullif(btrim(p_nota), '')
   where id = p_id and resuelta_en is null returning * into r;
  if r.id is null then raise exception 'La novedad no existe o ya estaba resuelta'; end if;
  return r;
end; $$;
revoke all on function public.novedad_resolver(bigint, text) from public, anon;
grant execute on function public.novedad_resolver(bigint, text) to authenticated;

-- Fotos: carpeta privada "novedades" (se suben, se ven; no se cambian ni se borran)
insert into storage.buckets (id, name, public) values ('novedades', 'novedades', false) on conflict (id) do nothing;
drop policy if exists novedades_fotos_subir on storage.objects;
create policy novedades_fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'novedades' and coalesce(public.rol_actual() in ('gerente','asistente','cobros','instalador','entrega'), false));
drop policy if exists novedades_fotos_ver on storage.objects;
create policy novedades_fotos_ver on storage.objects for select to authenticated
  using (bucket_id = 'novedades' and coalesce(public.rol_actual() in ('gerente','asistente','consulta','cobros','instalador','entrega'), false));

-- Aviso al celular del gerente
create or replace function public.notif_novedad()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.notif_crear('Elíptica · ' || new.obra, coalesce(new.quien, new.instalador, 'Alguien') || ': ⚠ novedad — ' || new.motivo
    || ' · ' || coalesce(array_length(new.items, 1), 0) || ' ítem(s) · ' || coalesce(left(new.ops, 80), '') || coalesce(' · ' || new.piso, ''));
  return null;
exception when others then return null;
end; $$;
drop trigger if exists trg_notif_novedad on public.novedades;
create trigger trg_notif_novedad after insert on public.novedades for each row execute function public.notif_novedad();

select 'Listo ✓ — novedades de instalación activadas' as resultado;
