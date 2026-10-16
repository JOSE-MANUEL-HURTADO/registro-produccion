-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Número de remisión consecutivo automático (00-NNN)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
-- Números entregados por la app (para que dos personas nunca reciban el mismo)
create table if not exists public.remisiones (
  num     integer primary key,
  creada  timestamptz not null default now(),
  usuario uuid default auth.uid()
);
alter table public.remisiones enable row level security;   -- sin políticas: solo se usa por la función

-- Siguiente remisión: la mayor usada (formato 00-NNN) + 1.
-- Si esta misma persona ya pidió un número y todavía no lo usó, le devuelve ese mismo (no deja huecos).
create or replace function public.siguiente_remision()
returns text language plpgsql security definer set search_path = public as $$
declare usado integer; propia integer; n integer;
begin
  if not public.puede_registrar() then raise exception 'Sin permiso'; end if;
  perform pg_advisory_xact_lock(4207001);
  select coalesce(max(substring(remision from '^00-(\d{1,6})$')::integer), 0) into usado
    from public.items where remision ~ '^00-\d{1,6}$';
  select max(num) into propia from public.remisiones where usuario = auth.uid() and num > usado;
  if propia is not null then return '00-' || lpad(propia::text, 3, '0'); end if;
  select greatest(usado, coalesce(max(num), 0)) + 1 into n from public.remisiones;
  insert into public.remisiones (num) values (n);
  return '00-' || lpad(n::text, 3, '0');
end; $$;
revoke all on function public.siguiente_remision() from public, anon;
grant execute on function public.siguiente_remision() to authenticated;
