-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Programación de obra y líneas de ensamble
--  · Programación: qué OP / cantidades / pisos entran primero a producción
--    y para qué fecha. Se imprime y se entrega a cada proceso.
--  · Línea de ensamble: a cada ensamblador se le asignan ítems de la
--    programación (antes de iniciar el ensamble).
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.programaciones (
  id        bigserial primary key,
  obra      text,
  fecha_req date,
  notas     text,
  estado    text not null default 'activa',   -- activa · cerrada · anulada
  n_items   integer,
  creada    timestamptz not null default now(),
  usuario   uuid default auth.uid(),
  quien     text
);
alter table public.programaciones enable row level security;
drop policy if exists prog_select on public.programaciones;
create policy prog_select on public.programaciones for select to authenticated using (public.es_interno());
drop policy if exists prog_insert on public.programaciones;
create policy prog_insert on public.programaciones for insert to authenticated with check (public.puede_registrar());
drop policy if exists prog_update on public.programaciones;
create policy prog_update on public.programaciones for update to authenticated using (public.puede_registrar()) with check (public.puede_registrar());

alter table public.items add column if not exists programacion_id bigint references public.programaciones(id);
alter table public.items add column if not exists ens_asignado    text;
create index if not exists items_prog_idx on public.items (programacion_id);
