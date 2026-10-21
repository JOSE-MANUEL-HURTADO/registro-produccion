-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Nombres de obra equivalentes + pasar PROYECTO 125 a CALLE 125
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  1. Tabla obras_alias: "la OP dice X, pero la obra es Y". Al cargar OP,
--     la app la usa sola; el gerente agrega nombres desde la revisión de carga.
--  2. Pasa todo lo que quedó como PROYECTO 125 a CALLE 125 (en todas las tablas).
-- ════════════════════════════════════════════════════════════════
create table if not exists public.obras_alias (
  alias  text primary key,
  obra   text not null,
  creado timestamptz not null default now()
);
alter table public.obras_alias enable row level security;
drop policy if exists alias_select on public.obras_alias;
create policy alias_select on public.obras_alias for select to authenticated using (public.es_interno());
drop policy if exists alias_gerente on public.obras_alias;
create policy alias_gerente on public.obras_alias for all to authenticated using (public.es_gerente()) with check (public.es_gerente());
grant select, insert, update, delete on public.obras_alias to authenticated;

insert into public.obras_alias (alias, obra) values ('PROYECTO 125', 'CALLE 125')
on conflict (alias) do update set obra = excluded.obra;

-- 2. Unificar el nombre en todas las tablas que tienen columna "obra"
do $$
declare
  r record; n bigint; total bigint := 0;
begin
  if not exists (select 1 from public.items where obra = 'CALLE 125') then
    raise exception 'No encontré la obra CALLE 125 escrita exactamente así. Obras parecidas: %',
      (select string_agg(distinct obra, ' | ') from public.items where obra ilike '%125%');
  end if;
  perform set_config('elp.swap', '1', true);   -- permite cambiar el nombre de obra en los ítems (solo durante este cambio)
  for r in select c.table_name from information_schema.columns c join information_schema.tables t
             on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
            where c.table_schema = 'public' and c.column_name = 'obra' and c.table_name <> 'obras_alias' loop
    execute format('update public.%I set obra = %L where obra = %L', r.table_name, 'CALLE 125', 'PROYECTO 125');
    get diagnostics n = row_count;
    if n > 0 then raise notice '%: % filas', r.table_name, n; end if;
    total := total + n;
  end loop;
  raise notice 'Total cambiadas: %', total;
end $$;

select obra, count(*) as items from public.items where obra in ('CALLE 125', 'PROYECTO 125') group by obra;
