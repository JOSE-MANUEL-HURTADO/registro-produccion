-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · El vidrio laminado nunca va pulido, mecanizado ni templado
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Ruta del laminado: corte → lavado → [forrado]
--  Ruta del resto:    corte → pulido → mecanizado → lavado → [templado] → [forrado]
--  Se corrige la ruta de todas las piezas laminadas ya cargadas.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_ruta(p_tipo text, p_forrado boolean)
returns text[] language sql immutable as $$
  select case when upper(coalesce(p_tipo, '')) ~ '(^|[^A-Z])LAM' then array['corte','lavado']
              when upper(coalesce(p_tipo, '')) ~ 'TEMP' then array['corte','pulido','mecanizado','lavado','templado']
              else array['corte','pulido','mecanizado','lavado'] end
    || case when p_forrado then array['forrado'] else array[]::text[] end;
$$;

update public.art_piezas
   set ruta = array(select e from unnest(ruta) with ordinality u(e, n) where e not in ('pulido','mecanizado','templado') order by n)
 where upper(coalesce(tipo, '')) ~ '(^|[^A-Z])LAM'
   and ruta && array['pulido','mecanizado','templado'];

select 'Listo SQL 60' as resultado,
       (select count(*) from public.art_piezas where upper(coalesce(tipo, '')) ~ '(^|[^A-Z])LAM') as laminados,
       (select count(*) from public.art_piezas where upper(coalesce(tipo, '')) ~ '(^|[^A-Z])LAM' and ruta && array['pulido','mecanizado','templado']) as laminados_con_pulido;
