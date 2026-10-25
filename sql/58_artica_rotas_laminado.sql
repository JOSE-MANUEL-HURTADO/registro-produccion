-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Laminado con ruta normal + vidrio para reprocesar al desmarcar el corte en Elíptica
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  1. El laminado ya no tiene ruta propia: se compra laminado al proveedor y sigue la ruta
--     normal (corte → pulido → mecanizado → lavado → [templado] → [forrado]).
--  2. Cada pieza lleva dos contadores:
--     · base  = piezas que ya estaban hechas antes de la app (terminadas)
--     · rotas = piezas que hay que volver a hacer
--     Lo hecho en cada estación = base + escaneos − rotas (entre 0 y la cantidad).
--  3. Si en Elíptica se desmarca el CORTE de una sub-OP (por ejemplo, se rompió un vidrio),
--     a cada medida de esa OP se le suma la parte de una unidad como "rotas": vuelve a
--     aparecer pendiente desde corte y se puede escanear de nuevo en todas las estaciones.
-- ════════════════════════════════════════════════════════════════
alter table public.art_piezas add column if not exists base int not null default 0;
alter table public.art_piezas add column if not exists rotas int not null default 0;
update public.art_piezas set base = cant where historica and base = 0;

-- Lo hecho en una estación (efectivo)
create or replace function public.art_hechos(p public.art_piezas, p_est text)
returns int language sql stable security definer set search_path = public as $$
  select greatest(0, least(p.cant, p.base + (select count(*)::int from public.art_registros g where g.pieza_id = p.id and g.estacion = p_est) - p.rotas));
$$;

-- 1. Laminado = ruta normal
create or replace function public.art_ruta(p_tipo text, p_forrado boolean)
returns text[] language sql immutable as $$
  select case when upper(p_tipo) ~ 'TEMP' then array['corte','pulido','mecanizado','lavado','templado']
              else array['corte','pulido','mecanizado','lavado'] end
    || case when p_forrado then array['forrado'] else array[]::text[] end;
$$;
update public.art_piezas p set ruta = public.art_ruta(p.tipo, p.forrado)
 where upper(p.tipo) ~ '(^|[^A-Z])LAM' and not exists (select 1 from public.art_registros g where g.pieza_id = p.id);

-- Terminadas antes de la app: base = cantidad
create or replace function public.art_marcar_historicas()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.art_piezas p set historica = true, base = p.cant
   where not p.historica and not p.tercero
     and exists (select 1 from public.items i where i.op = p.op)
     and (not exists (select 1 from public.items i where i.op = p.op and i.status = 'EN COLA')
          or exists (select 1 from public.items i join public.obras_cerradas c on c.obra = i.obra where i.op = p.op)
          or (not exists (select 1 from public.items i where i.op = p.op and i.vidrio_proc is distinct from 'X')
              and not exists (select 1 from public.art_registros g join public.art_piezas q on q.id = g.pieza_id where q.op = p.op)));
  get diagnostics n = row_count;
  return n;
end; $$;
revoke all on function public.art_marcar_historicas() from public, anon, authenticated;

-- Escanear con los contadores efectivos
create or replace function public.art_escanear(p_codigo text, p_estacion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id bigint; pz public.art_piezas; hechos int; previos int; ant text; pos int; est text := lower(trim(p_estacion));
  cod text := upper(trim(coalesce(p_codigo, ''))); pre text; hoy int; quien text;
begin
  if not (public.es_gerente() or (public.rol_actual() = 'artica' and est = any(coalesce((select estaciones from public.perfiles where id = auth.uid()), '{}'))))
    then raise exception 'Sin permiso para la estación %', est; end if;
  pre := substring(cod from '^(P\d+)-');
  if pre is not null then
    select estacion into est from public.art_prefijos where prefijo = pre;
    if est is null then return jsonb_build_object('estado','nohay','msg','Prefijo ' || pre || ' sin estación asignada'); end if;
    if not (public.es_gerente() or est = any(coalesce((select estaciones from public.perfiles where id = auth.uid()), '{}'))) then
      return jsonb_build_object('estado','nohay','msg','Este usuario no registra ' || est); end if;
    cod := substring(cod from '^P\d+-(.*)$');
  end if;
  v_id := nullif(substring(cod from 'ART[:\-]?(\d+)'), '')::bigint;
  if v_id is null then return jsonb_build_object('estado','nohay','msg','Ese código no es una pieza de Ártica','estacion',est); end if;
  select * into pz from public.art_piezas where id = v_id for update;
  if pz.id is null then return jsonb_build_object('estado','nohay','msg','Pieza no encontrada','estacion',est); end if;
  select count(*) into hoy from public.art_registros where estacion = est and creado >= date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota';
  pos := array_position(pz.ruta, est);
  if pos is null then
    return jsonb_build_object('estado','noruta','msg','Esta pieza no pasa por ' || est, 'pieza', to_jsonb(pz), 'estacion', est, 'hoy', hoy);
  end if;
  hechos := public.art_hechos(pz, est);
  if hechos >= pz.cant then
    return jsonb_build_object('estado','ya','msg', case when pz.historica and pz.rotas = 0 then 'Pieza terminada antes de la app' else 'Ya se registraron las ' || pz.cant || ' piezas en ' || est end,
      'pieza', to_jsonb(pz), 'hechos', hechos, 'estacion', est, 'hoy', hoy);
  end if;
  if pos > 1 then
    ant := pz.ruta[pos - 1];
    previos := public.art_hechos(pz, ant);
    if previos <= hechos then
      return jsonb_build_object('estado','fuera','msg','Falta ' || ant || ' (' || previos || ' de ' || pz.cant || ')', 'pieza', to_jsonb(pz), 'hechos', hechos, 'estacion', est, 'hoy', hoy);
    end if;
  end if;
  select nombre into quien from public.perfiles where id = auth.uid();
  insert into public.art_registros (pieza_id, estacion, quien) values (pz.id, est, quien);
  return jsonb_build_object('estado','ok','pieza', to_jsonb(pz), 'hechos', hechos + 1, 'estacion', est, 'hoy', hoy + 1,
    'listo', pos = array_length(pz.ruta, 1));
end; $$;
revoke all on function public.art_escanear(text, text) from public, anon;
grant execute on function public.art_escanear(text, text) to authenticated;

create or replace function public.art_deshacer(p_estacion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.art_registros; pz public.art_piezas; sig text;
begin
  select * into r from public.art_registros where usuario = auth.uid() and estacion = lower(p_estacion)
     and creado >= date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota'
   order by id desc limit 1;
  if r.id is null then raise exception 'No hay nada tuyo para deshacer hoy en esta estación'; end if;
  select * into pz from public.art_piezas where id = r.pieza_id;
  sig := pz.ruta[array_position(pz.ruta, r.estacion) + 1];
  if sig is not null and public.art_hechos(pz, sig) >= public.art_hechos(pz, r.estacion) and public.art_hechos(pz, sig) > 0 then
    raise exception 'No se puede deshacer: esa pieza ya pasó por %', sig;
  end if;
  delete from public.art_registros where id = r.id;
  return jsonb_build_object('pieza', to_jsonb(pz), 'estacion', r.estacion);
end; $$;
revoke all on function public.art_deshacer(text) from public, anon;
grant execute on function public.art_deshacer(text) to authenticated;

-- Listos para Elíptica y Vidrio automático: contadores efectivos
create or replace function public.art_listos(p_ops text[])
returns table(op text, total bigint, listos bigint) language sql stable security definer set search_path = public as $$
  select p.op, sum(p.cant), sum(public.art_hechos(p, p.ruta[array_length(p.ruta,1)]))
    from public.art_piezas p where p.op = any(p_ops) and coalesce(public.rol_actual() in ('gerente','asistente','consulta','planta','cobros'), false)
   group by p.op;
$$;
grant execute on function public.art_listos(text[]) to authenticated;

create or replace function public.art_sync_vidrio_op(p_op text)
returns int language plpgsql security definer set search_path = public as $$
declare n_med int; n_ok int; tot numeric; ok numeric; n int := 0;
begin
  select count(*), count(*) filter (where l >= 0.7 * cant), sum(cant), sum(l)
    into n_med, n_ok, tot, ok
    from (select p.cant, public.art_hechos(p, p.ruta[array_length(p.ruta, 1)]) l
            from public.art_piezas p where p.op = p_op and not p.tercero) x;
  if coalesce(n_med, 0) = 0 or n_ok < n_med then return 0; end if;
  update public.items set vidrio_proc = 'X' where op = p_op and vidrio_proc is distinct from 'X';
  get diagnostics n = row_count;
  insert into public.art_vidrio_auto (op, pct, items) values (p_op, round(ok / tot * 100), n)
    on conflict (op) do update set marcado = now(), pct = excluded.pct, items = excluded.items;
  return n;
end; $$;
revoke all on function public.art_sync_vidrio_op(text) from public, anon, authenticated;

-- 3. Desmarcar el corte de una sub-OP en Elíptica → esa unidad de vidrio vuelve a quedar pendiente en Ártica
create or replace function public.art_corte_desmarcado()
returns trigger language plpgsql security definer set search_path = public as $$
declare n_uni int; p public.art_piezas; k int;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' then return null; end if;
  if not (old.cortado = 'X' and new.cortado is distinct from 'X') or new.op is null then return null; end if;
  select count(*) into n_uni from public.items where op = new.op;
  for p in select * from public.art_piezas where op = new.op and not tercero for update loop
    k := ceil(p.cant::numeric / greatest(n_uni, 1));
    -- no más de lo que ya estaba cortado
    update public.art_piezas set rotas = rotas + least(k, public.art_hechos(p, 'corte')) where id = p.id;
  end loop;
  return null;
end; $$;
drop trigger if exists trg_art_corte_desmarcado on public.items;
create trigger trg_art_corte_desmarcado after update of cortado on public.items for each row execute function public.art_corte_desmarcado();

-- Vista de avance con base y rotas
drop view if exists public.art_avance;
create view public.art_avance with (security_invoker = true) as
  select p.*, coalesce((select jsonb_object_agg(estacion, n) from (select estacion, count(*) n from public.art_registros g where g.pieza_id = p.id group by estacion) x), '{}') as hechos,
         (select max(creado) from public.art_registros g where g.pieza_id = p.id) as ultimo
    from public.art_piezas p;
grant select on public.art_avance to authenticated;

select 'Listo ✓ — laminado con ruta normal y vidrio para reprocesar al desmarcar el corte' as resultado,
       (select count(*) from public.art_piezas where upper(tipo) ~ '(^|[^A-Z])LAM' and not historica) as laminados_en_seguimiento;
