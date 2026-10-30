-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Registrar piezas SIN QR (vidrio cortado sin etiqueta): el director o el gerente de Ártica
--  escriben cuántas piezas de una medida van hechas en cada estación y la app crea los registros que faltan.
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
--  · art_registrar_manual(pieza, estación, hechas, fecha): si "hechas" es mayor a lo registrado, agrega registros
--    (quien = "… (sin QR)", a mediodía de la fecha indicada). Si es menor, quita registros sin QR (los últimos primero);
--    lo escaneado con QR no se borra: para eso está "Reprocesar".
--  · Corrige la productividad de Ártica: cada registro es una pieza (la columna n es el número de la etiqueta).
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_registrar_manual(p_id bigint, p_estacion text, p_hechas int, p_fecha date default null)
returns int language plpgsql security definer set search_path = public as $$
declare pz public.art_piezas; h int; d int; quien text; cuando timestamptz; borra bigint[];
begin
  if not (coalesce(public.es_gerente(), false) or coalesce(public.art_admin(), false)) then raise exception 'Sin permiso'; end if;
  select * into pz from public.art_piezas where id = p_id for update;
  if pz.id is null then raise exception 'Pieza no encontrada'; end if;
  if array_position(pz.ruta, p_estacion) is null then raise exception 'La pieza no pasa por %', p_estacion; end if;
  if p_hechas < 0 or p_hechas > pz.cant then raise exception 'Debe ser entre 0 y %', pz.cant; end if;
  h := public.art_hechos(pz, p_estacion); d := p_hechas - h;
  if d = 0 then return 0; end if;
  select nombre into quien from public.perfiles where id = auth.uid();
  if d > 0 then
    cuando := case when p_fecha is null or p_fecha >= (now() at time zone 'America/Bogota')::date then now()
                   else ((p_fecha + time '12:00') at time zone 'America/Bogota') end;
    insert into public.art_registros (pieza_id, estacion, creado, usuario, quien, n)
      select pz.id, p_estacion, cuando, auth.uid(), coalesce(quien, 'Director') || ' (sin QR)', null from generate_series(1, d);
  else
    select array_agg(id) into borra from (select id from public.art_registros where pieza_id = pz.id and estacion = p_estacion and quien like '%(sin QR)' order by creado desc, id desc limit -d) z;
    if coalesce(array_length(borra, 1), 0) < -d then raise exception 'Solo se pueden quitar registros hechos sin QR (hay %). Para piezas escaneadas usa Reprocesar', coalesce(array_length(borra, 1), 0); end if;
    delete from public.art_registros where id = any(borra);
  end if;
  return d;
end; $$;
revoke all on function public.art_registrar_manual(bigint, text, int, date) from public, anon;
grant execute on function public.art_registrar_manual(bigint, text, int, date) to authenticated;

select 'Listo SQL 101' as r;
