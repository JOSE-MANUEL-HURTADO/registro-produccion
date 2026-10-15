-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Registro de copias de seguridad
--  Correr después de 4_roles_consulta_cobros.sql y 5_consulta_ve_todo.sql
-- ════════════════════════════════════════════════════════════════
create table if not exists public.respaldos (
  id      bigserial primary key,
  cuando  timestamptz not null default now(),
  origen  text not null,          -- 'mac' (automática) o 'app' (manual)
  filas   integer,
  usuario uuid default auth.uid()
);
alter table public.respaldos enable row level security;

-- Solo el gerente ve el registro de copias
drop policy if exists respaldos_select on public.respaldos;
create policy respaldos_select on public.respaldos
  for select to authenticated using (public.es_gerente());

-- Anotar una copia: gerente (desde la app) o el usuario de respaldo del Mac (rol consulta)
create or replace function public.registrar_respaldo(p_origen text, p_filas integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual() in ('gerente','consulta'), false) is not true then
    raise exception 'Sin permiso';
  end if;
  insert into public.respaldos (origen, filas, usuario) values (left(p_origen, 20), p_filas, auth.uid());
end;
$$;
revoke all on function public.registrar_respaldo(text, integer) from public, anon;
grant execute on function public.registrar_respaldo(text, integer) to authenticated;
