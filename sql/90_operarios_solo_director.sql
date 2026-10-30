-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Asignar estaciones a los operarios y configurar pistolas: SOLO el director
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
do $$
declare f record; def text;
begin
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('art_operarios','art_estaciones_usuario')
  loop
    def := pg_get_functiondef(f.oid);
    if def like '%art_admin()%' then execute replace(def, 'public.art_admin()', 'public.es_gerente()'); end if;
  end loop;
end $$;
drop policy if exists art_prefijos_gerente on public.art_prefijos;
create policy art_prefijos_gerente on public.art_prefijos for all to authenticated
  using ((select public.es_gerente())) with check ((select public.es_gerente()));

select 'Listo SQL 90 — operarios y pistolas solo el director' as r,
  (select count(*) from pg_proc where proname in ('art_operarios','art_estaciones_usuario') and prosrc like '%es_gerente()%') funciones;
