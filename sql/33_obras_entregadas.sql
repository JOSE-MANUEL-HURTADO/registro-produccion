-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Obras entregadas (contrato cerrado)
--  El gerente marca una obra como entregada: deja de aparecer en Obras
--  activas, Planta y Por entregar. Los ítems NO se modifican (su historia
--  queda igual); se puede reabrir. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.obras_cerradas (
  obra       text primary key,
  cerrada_en timestamptz not null default now(),
  usuario    uuid default auth.uid(),
  quien      text,
  nota       text
);
alter table public.obras_cerradas enable row level security;
drop policy if exists oc_select on public.obras_cerradas;
create policy oc_select on public.obras_cerradas for select to authenticated using (public.es_interno());
drop policy if exists oc_insert on public.obras_cerradas;
create policy oc_insert on public.obras_cerradas for insert to authenticated with check (public.es_gerente());
drop policy if exists oc_update on public.obras_cerradas;
create policy oc_update on public.obras_cerradas for update to authenticated using (public.es_gerente()) with check (public.es_gerente());
drop policy if exists oc_delete on public.obras_cerradas;
create policy oc_delete on public.obras_cerradas for delete to authenticated using (public.es_gerente());
