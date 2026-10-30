-- ════════════════════════════════════════════════════════════════
--  COSTO DE MANO DE OBRA POR OBRA (solo el director)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · mo_nomina: personas de la nómina con su salario básico mensual (se carga desde el directorio de nómina).
--  · mo_alias: cómo aparece cada persona en la app (ensamblador / instalador / operario) → persona de la nómina,
--    o marcada como contratista (sin costo de nómina) o ignorada (ej. "ARTICA", "OBRA").
--  · mo_param: parámetros del cálculo (carga prestacional, ARL, tiempos estimados de los procesos antes del escáner).
--  NADA de esto lo ve la asistente ni otro rol: solo es_gerente().
-- ════════════════════════════════════════════════════════════════
create table if not exists public.mo_nomina (
  id          bigserial primary key,
  nombre      text not null unique,
  salario     numeric not null check (salario >= 0),
  aux_transporte boolean,          -- null = según ley (salario <= 2 SMMLV)
  arl         numeric,             -- % ARL propio (null = el general)
  activo      boolean not null default true,
  actualizado timestamptz not null default now()
);
create table if not exists public.mo_alias (
  nombre_app  text primary key,    -- como aparece en la app (MAYÚSCULAS)
  tipo        text not null default 'nomina' check (tipo in ('nomina', 'contratista', 'ignorar')),
  nomina_id   bigint references public.mo_nomina(id) on delete set null,
  actualizado timestamptz not null default now()
);
create table if not exists public.mo_param (
  id   int primary key default 1 check (id = 1),
  p    jsonb not null default '{}'::jsonb,
  actualizado timestamptz not null default now()
);
insert into public.mo_param (id, p) values (1, '{}'::jsonb) on conflict (id) do nothing;

do $$ declare t text; begin
  foreach t in array array['mo_nomina', 'mo_alias', 'mo_param'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_ger', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.es_gerente())) with check ((select public.es_gerente()))', t || '_ger', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
grant usage, select on sequence public.mo_nomina_id_seq to authenticated;

select 'Listo SQL 94 — costo de mano de obra' as r;
