-- ════════════════════════════════════════════════════════════════
--  COMPRAS · Proveedores y órdenes de compra (historial 2026 importado de los Excel de compras)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
--  · compras_proveedores: base de proveedores (NIT, contacto, dirección, teléfono, ciudad, correo, categorías).
--  · compras_oc: cada orden de compra (aluminio AL-, vidrio V-, accesorios AC-) con sus líneas en JSON
--    (referencia, descripción, acabado/presentación, cantidad, valor unitario, total, obra/OP).
--  · Con precios: solo el director (más adelante también el rol de compras). La asistente no ve nada de esto.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.compras_proveedores (
  id bigserial primary key,
  nombre text not null unique,
  nit text, contacto text, direccion text, telefono text, ciudad text, email text,
  categorias text[] not null default '{}',
  activo boolean not null default true,
  actualizado timestamptz not null default now()
);
create table if not exists public.compras_oc (
  id bigserial primary key,
  num text not null unique,                 -- AL-26-058, V-26-033, AC-26-221
  categoria text not null check (categoria in ('aluminio', 'vidrio', 'accesorios')),
  fecha date,
  proveedor text,
  proveedor_id bigint references public.compras_proveedores(id) on delete set null,
  obra text,
  lineas jsonb not null default '[]'::jsonb,
  subtotal numeric, iva numeric, total numeric,
  estado text not null default 'historica',  -- historica · borrador · enviada · parcial · recibida · anulada
  notas text,
  origen text not null default 'excel',
  creada timestamptz not null default now(),
  usuario uuid default auth.uid()
);
create index if not exists compras_oc_fecha_idx on public.compras_oc (fecha);
do $$ declare t text; begin
  foreach t in array array['compras_proveedores', 'compras_oc'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_ger', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.es_gerente())) with check ((select public.es_gerente()))', t || '_ger', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
grant usage, select on sequence public.compras_proveedores_id_seq, public.compras_oc_id_seq to authenticated;
select 'Listo SQL 108 — compras' as r;
