-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Solo las OP con el formato de Ártica son de clientes de Ártica
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Las OP con el formato de Elíptica son siempre de Elíptica, aunque solo traigan vidrio
--  (CASA 19 SERNA MEJIA, PROYECTO DUCUARA…). Antes la app las tomaba como clientes de Ártica.
--  Las OP de clientes de Ártica no traen obra (solo cliente); las que tienen obra vuelven a Elíptica.
-- ════════════════════════════════════════════════════════════════
update public.art_piezas p set tercero = false, obra = p.obra
 where p.tercero and p.obra is not null
   and not exists (select 1 from public.art_piezas q where q.op = p.op and q.linea = p.linea and not q.tercero);

select public.art_marcar_historicas() as marcadas_terminadas;

select 'Listo SQL 76' as r,
       (select count(*) from public.art_piezas where tercero) quedan_clientes,
       (select string_agg(distinct op || ' ' || obra, ', ') from public.art_piezas where op in ('5996-1','6218-1','5698-3','5902-3','6273-5')) ahora_eliptica;
