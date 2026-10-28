-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · La asistente también escanea en todas las estaciones
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Gerente y asistente: todas las estaciones (corte, pulido, mecanizado, templado,
--  lavado, forrado), sin tener que asignárselas. Los operarios de Ártica siguen con
--  solo las estaciones que tienen asignadas.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_escanea_todo()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.rol_actual() in ('gerente','asistente'), false);
$$;
grant execute on function public.art_escanea_todo() to authenticated;

-- Se cambia el permiso "solo gerente" por "gerente o asistente" en el escaneo y en las estaciones
do $x$
declare f record; def text;
begin
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('art_escanear', 'art_mis_estaciones') loop
    def := pg_get_functiondef(f.oid);
    if def like '%public.es_gerente()%' then
      execute replace(def, 'public.es_gerente()', 'public.art_escanea_todo()');
    end if;
  end loop;
end $x$;

select 'Listo SQL 73 — la asistente escanea Ártica' as r,
       (select count(*) from pg_proc where proname in ('art_escanear','art_mis_estaciones') and pg_get_functiondef(oid) like '%art_escanea_todo%') funciones,
       (select string_agg(coalesce(nombre, id::text), ', ') from public.perfiles where rol = 'asistente') asistentes;
