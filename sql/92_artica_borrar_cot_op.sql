-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Borrar cotizaciones y OP de clientes equivocadas (solo el director)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · art_borrar_op(op): borra una OP de clientes de Ártica. No deja si ya tiene piezas escaneadas
--    en alguna estación (para no perder la trazabilidad). La cotización que la creó vuelve a borrador.
--  · art_borrar_cot(id, con_op): borra una cotización y, si se pide, también su OP.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_borrar_op(p_op text)
returns int language plpgsql security definer set search_path = public as $$
declare n int; v_reg int;
begin
  if not coalesce(public.es_gerente(), false) then raise exception 'Sin permiso: solo el director borra OP'; end if;
  if coalesce(btrim(p_op), '') = '' then raise exception 'Falta la OP'; end if;
  select count(*) into v_reg from public.art_registros g join public.art_piezas p on p.id = g.pieza_id where p.op = p_op and p.tercero;
  if v_reg > 0 then raise exception 'La OP % ya tiene % escaneo(s) en planta: no se puede borrar', p_op, v_reg; end if;
  delete from public.art_reprocesos r using public.art_piezas p where r.pieza_id = p.id and p.op = p_op and p.tercero;
  delete from public.art_piezas where op = p_op and tercero;
  get diagnostics n = row_count;
  update public.art_cotizaciones set op = null, estado = 'borrador' where op = p_op;
  return n;
end; $$;
revoke all on function public.art_borrar_op(text) from public, anon;
grant execute on function public.art_borrar_op(text) to authenticated;

create or replace function public.art_borrar_cot(p_id bigint, p_con_op boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.art_cotizaciones; n int := 0;
begin
  if not coalesce(public.es_gerente(), false) then raise exception 'Sin permiso: solo el director borra cotizaciones'; end if;
  select * into c from public.art_cotizaciones where id = p_id;
  if c.id is null then raise exception 'La cotización no existe'; end if;
  if p_con_op and c.op is not null then n := public.art_borrar_op(c.op); end if;
  delete from public.art_cotizaciones where id = p_id;
  perform setval('public.art_cot_seq', coalesce((select max(num) from public.art_cotizaciones), 0) + 1, false);
  return jsonb_build_object('num', c.num, 'op', case when p_con_op then c.op end, 'piezas_borradas', n);
end; $$;
revoke all on function public.art_borrar_cot(bigint, boolean) from public, anon;
grant execute on function public.art_borrar_cot(bigint, boolean) to authenticated;

select 'Listo SQL 92 — borrar cotizaciones y OP de clientes' as r;
