-- ════════════════════════════════════════════════════════════════
--  COMPRAS · Catálogo (proveedor y precio asignados a cada referencia, también las que aún no se han pedido)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.compras_catalogo (
  id bigserial primary key,
  categoria text not null check (categoria in ('aluminio', 'vidrio', 'accesorios')),
  clave text not null,                 -- referencia normalizada (HSA005) o descripción del vidrio
  ref text, descripcion text,
  presentacion text,                   -- und, metros, bolsa x 8, rollo x 1000…
  proveedor text,
  proveedor_id bigint references public.compras_proveedores(id) on delete set null,
  precio numeric,                      -- sin IVA, por unidad de compra (vidrio: por m²)
  lamina text,                         -- vidrio: medida de la lámina (3.66 × 2.4)
  notas text,
  actualizado timestamptz not null default now(),
  usuario uuid default auth.uid(),
  unique (categoria, clave)
);
alter table public.compras_catalogo enable row level security;
drop policy if exists compras_catalogo_ger on public.compras_catalogo;
create policy compras_catalogo_ger on public.compras_catalogo for all to authenticated using ((select public.es_gerente())) with check ((select public.es_gerente()));
revoke all on public.compras_catalogo from anon;
grant select, insert, update, delete on public.compras_catalogo to authenticated;
grant usage, select on sequence public.compras_catalogo_id_seq to authenticated;
grant all on public.compras_catalogo to service_role;
select 'Listo SQL 109 — catálogo de compras' as r;
