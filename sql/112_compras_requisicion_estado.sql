-- ════════════════════════════════════════════════════════════════
--  COMPRAS · Estado de la requisición por OP (para listar las OP a las que falta armarles la requisición)
--  Una OP se da por pedida si ya tiene una OC que la nombra ("OP 6298"); aquí se guardan las marcas manuales:
--  'hecha' (ya se pidió por fuera) o 'no_requiere'. Solo el director. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.compras_req (
  op     text primary key,               -- número base de la OP (6291)
  estado text not null check (estado in ('hecha', 'no_requiere')),
  nota   text,
  por    uuid default auth.uid(),
  en     timestamptz not null default now()
);
alter table public.compras_req enable row level security;
drop policy if exists compras_req_ger on public.compras_req;
create policy compras_req_ger on public.compras_req for all to authenticated using ((select public.es_gerente())) with check ((select public.es_gerente()));
revoke all on public.compras_req from anon;
grant select, insert, update, delete on public.compras_req to authenticated;
grant all on public.compras_req to service_role;
select 'Listo SQL 112 — estado de requisiciones por OP' as r;
