-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Cotizaciones de vidrio para clientes
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · La app arma la cotización (por m², agrupada por tipo de vidrio), la guarda, la imprime en PDF,
--    la exporta a Excel y, al aprobarse, la convierte en la OP de clientes de Ártica.
--  · La ven y la editan el director y el usuario de OP de clientes de Ártica (artica_ops).
--  · art_precios recuerda el último valor por m² de cada vidrio (tipo + calibre + color).
-- ════════════════════════════════════════════════════════════════
create sequence if not exists public.art_cot_seq;

create table if not exists public.art_cotizaciones (
  id          bigserial primary key,
  num         int not null default nextval('public.art_cot_seq'),
  fecha       date not null default (now() at time zone 'America/Bogota')::date,
  validez     int not null default 15,
  cliente     jsonb not null default '{}',
  proyecto    jsonb not null default '{}',
  lineas      jsonb not null default '[]',
  adicionales jsonb not null default '[]',
  condiciones jsonb not null default '{}',
  total       numeric,
  estado      text not null default 'borrador',
  op          text,
  quien       text,
  usuario     uuid default auth.uid(),
  creada      timestamptz not null default now(),
  actualizada timestamptz not null default now()
);
alter table public.art_cotizaciones drop constraint if exists art_cot_estado_chk;
alter table public.art_cotizaciones add constraint art_cot_estado_chk check (estado in ('borrador','enviada','aprobada','rechazada'));
create unique index if not exists art_cot_num on public.art_cotizaciones (num);

create table if not exists public.art_precios (
  clave       text primary key,
  valor       numeric not null,
  actualizado timestamptz not null default now(),
  quien       text
);

create or replace function public.art_cotiza()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.es_gerente(), false) or coalesce(public.art_solo_clientes(), false);
$$;
grant execute on function public.art_cotiza() to authenticated;

alter table public.art_cotizaciones enable row level security;
alter table public.art_precios enable row level security;
drop policy if exists art_cot_todo on public.art_cotizaciones;
create policy art_cot_todo on public.art_cotizaciones for all to authenticated
  using ((select public.art_cotiza())) with check ((select public.art_cotiza()));
drop policy if exists art_precios_todo on public.art_precios;
create policy art_precios_todo on public.art_precios for all to authenticated
  using ((select public.art_cotiza())) with check ((select public.art_cotiza()));
grant select, insert, update, delete on public.art_cotizaciones, public.art_precios to authenticated;
grant usage, select on sequence public.art_cot_seq, public.art_cotizaciones_id_seq to authenticated;
grant all on public.art_cotizaciones, public.art_precios to service_role;

create or replace function public.art_cot_touch()
returns trigger language plpgsql as $$
begin new.actualizada := now(); return new; end; $$;
drop trigger if exists trg_art_cot_touch on public.art_cotizaciones;
create trigger trg_art_cot_touch before update on public.art_cotizaciones for each row execute function public.art_cot_touch();

select 'Listo SQL 88 — cotizaciones de Ártica' as r, (select count(*) from public.art_cotizaciones) cotizaciones;
