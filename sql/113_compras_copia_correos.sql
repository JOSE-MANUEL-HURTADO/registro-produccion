-- ════════════════════════════════════════════════════════════════
--  COMPRAS · Copia oculta de los correos de órdenes de compra a otras personas (además de compras).
--  copia = correos separados por coma; null = sin copia. Lo lee la función oc_enviar en cada envío.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.compras_ajustes (
  id    int primary key default 1 check (id = 1),
  copia text,
  actualizado timestamptz not null default now()
);
insert into public.compras_ajustes (id) values (1) on conflict (id) do nothing;
alter table public.compras_ajustes enable row level security;
drop policy if exists compras_ajustes_ger on public.compras_ajustes;
create policy compras_ajustes_ger on public.compras_ajustes for all to authenticated using ((select public.es_gerente())) with check ((select public.es_gerente()));
revoke all on public.compras_ajustes from anon;
grant select, insert, update on public.compras_ajustes to authenticated;
grant all on public.compras_ajustes to service_role;
-- José pidió copia de los correos de OC mientras se prueba (31 oct 2026). Para quitarla: update ... set copia = null
update public.compras_ajustes set copia = 'subgerencia@eliptica.com.co', actualizado = now() where id = 1;
select 'Listo SQL 113 — copia de correos de compras' as r;
