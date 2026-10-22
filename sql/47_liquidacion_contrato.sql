-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Liquidación automática: cotización (contratado) por obra
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Guarda, por obra, la cotización que el gerente sube a la app
--  (ítem, cantidad y valor unitario contratado), los porcentajes de
--  A, I, U, IVA sobre utilidad y retegarantía, y los pagos recibidos.
--  Lo ejecutado sale solo de las OP instaladas en la app.
--  Solo el gerente la ve y la modifica (tiene precios).
-- ════════════════════════════════════════════════════════════════
create table if not exists public.liq_contrato (
  obra        text primary key,
  archivo     text,
  hoja        text,
  items       jsonb not null default '[]'::jsonb,
  params      jsonb not null default '{"admin":10,"imprevistos":4,"utilidad":6,"iva":19,"retegarantia":10}'::jsonb,
  pagos       jsonb not null default '[]'::jsonb,
  actualizado timestamptz not null default now(),
  usuario     uuid default auth.uid()
);
alter table public.liq_contrato enable row level security;
drop policy if exists liqc_gerente on public.liq_contrato;
create policy liqc_gerente on public.liq_contrato for all to authenticated using (public.es_gerente()) with check (public.es_gerente());
grant select, insert, update, delete on public.liq_contrato to authenticated;
