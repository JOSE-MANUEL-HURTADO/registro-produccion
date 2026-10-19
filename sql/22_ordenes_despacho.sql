-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Órdenes de despacho (plan de cargue)
--  La orden NO despacha nada: es la lista de lo que se va a cargar,
--  con su peso. El despacho y la remisión se crean al escanear cada
--  ítem en el cargue (estación Despacho del escáner).
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.ordenes_despacho (
  id         bigserial primary key,
  obra       text,
  items      bigint[] not null,
  peso       numeric,
  capacidad  numeric,
  estado     text not null default 'abierta',   -- abierta · cargada · anulada
  remision   text,
  creada     timestamptz not null default now(),
  cerrada    timestamptz,
  usuario    uuid default auth.uid(),
  quien      text
);
alter table public.ordenes_despacho enable row level security;
drop policy if exists od_select on public.ordenes_despacho;
create policy od_select on public.ordenes_despacho for select to authenticated using (public.es_interno());
drop policy if exists od_insert on public.ordenes_despacho;
create policy od_insert on public.ordenes_despacho for insert to authenticated with check (public.puede_registrar());
drop policy if exists od_update on public.ordenes_despacho;
create policy od_update on public.ordenes_despacho for update to authenticated using (public.puede_registrar()) with check (public.puede_registrar());
