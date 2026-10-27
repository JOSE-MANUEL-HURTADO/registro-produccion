-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Trazabilidad por pieza y registro de reprocesos
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Las etiquetas nuevas llevan el número de la pieza en el QR (ART:123-5 = pieza 5 de esa medida).
--    Cada escaneo guarda ese número: se ve qué piezas pasaron por cada estación, cuándo y quién.
--    La misma pieza no se puede registrar dos veces en una estación (salvo que se mande a reprocesar).
--    Las etiquetas viejas (ART:123) siguen funcionando, sin número de pieza.
--  · Cada reproceso queda anotado: corte o vidrio desmarcado en Elíptica (con la sub-OP)
--    o pieza rota en Ártica (botón "Reprocesar"), con fecha, hora, quién y cuántas piezas.
-- ════════════════════════════════════════════════════════════════
alter table public.art_registros add column if not exists n int;

create table if not exists public.art_reprocesos (
  id       bigserial primary key,
  pieza_id bigint not null references public.art_piezas(id) on delete cascade,
  cant     int not null,
  origen   text,
  nota     text,
  quien    text,
  creado   timestamptz not null default now()
);
create index if not exists art_reprocesos_pieza on public.art_reprocesos (pieza_id, creado);
alter table public.art_reprocesos enable row level security;
drop policy if exists art_reprocesos_leer on public.art_reprocesos;
create policy art_reprocesos_leer on public.art_reprocesos for select to authenticated using ((select public.art_lee()));
grant select on public.art_reprocesos to authenticated;
grant all on public.art_reprocesos to service_role;

-- Anota cada vez que una medida vuelve a quedar pendiente (rotas sube o base baja)
create or replace function public.art_log_reproceso()
returns trigger language plpgsql security definer set search_path = public as $$
declare d int := greatest(0, new.rotas - old.rotas) + greatest(0, old.base - new.base);
begin
  if d > 0 then
    insert into public.art_reprocesos (pieza_id, cant, origen, nota, quien)
    values (new.id, d, coalesce(nullif(current_setting('art.origen', true), ''), 'Reproceso'), nullif(current_setting('art.nota', true), ''), public.notif_quien());
  end if;
  return null;
end; $$;
drop trigger if exists trg_art_log_reproceso on public.art_piezas;
create trigger trg_art_log_reproceso after update of rotas, base on public.art_piezas for each row execute function public.art_log_reproceso();

-- Pieza rota en Ártica: vuelve a pendiente desde corte
create or replace function public.art_reprocesar(p_id bigint, p_cant int, p_nota text)
returns int language plpgsql security definer set search_path = public as $$
declare pz public.art_piezas; k int;
begin
  if not (public.es_gerente() or public.rol_actual() = 'artica') then raise exception 'Sin permiso'; end if;
  select * into pz from public.art_piezas where id = p_id for update;
  if pz.id is null then raise exception 'Pieza no encontrada'; end if;
  k := least(greatest(coalesce(p_cant, 1), 1), public.art_hechos(pz, 'corte'));
  if k <= 0 then raise exception 'Esa medida no tiene piezas cortadas para reprocesar'; end if;
  perform set_config('art.origen', 'Rota en Ártica', true);
  perform set_config('art.nota', coalesce(p_nota, ''), true);
  update public.art_piezas set rotas = rotas + k where id = p_id;
  return k;
end; $$;
revoke all on function public.art_reprocesar(bigint, int, text) from public, anon;
grant execute on function public.art_reprocesar(bigint, int, text) to authenticated;

create or replace function public.art_corte_desmarcado()
returns trigger language plpgsql security definer set search_path = public as $$
declare n_uni int; p public.art_piezas; k int;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' then return null; end if;
  if not (old.cortado = 'X' and new.cortado is distinct from 'X') or new.op is null then return null; end if;
  select count(*) into n_uni from public.items where op = new.op;
  perform set_config('art.origen', 'Corte desmarcado en Elíptica · ' || coalesce(new.op_instalacion, new.op), true);
  for p in select * from public.art_piezas where op = new.op and not tercero for update loop
    k := ceil(p.cant::numeric / greatest(n_uni, 1));
    -- no más de lo que ya estaba cortado
    update public.art_piezas set rotas = rotas + least(k, public.art_hechos(p, 'corte')) where id = p.id;
  end loop;
  return null;
end; $$;

create or replace function public.art_vidrio_cambio()
returns trigger language plpgsql security definer set search_path = public as $$
declare n_uni int; p public.art_piezas; k int; con_reg boolean;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' or new.op is null then return null; end if;
  if old.vidrio_proc is not distinct from new.vidrio_proc then return null; end if;
  select count(*) into n_uni from public.items where op = new.op;
  if old.vidrio_proc = 'X' then
    perform set_config('art.origen', 'Vidrio desmarcado en Elíptica · ' || coalesce(new.op_instalacion, new.op), true);
    -- Desmarcado: esa unidad vuelve a pendiente
    for p in select * from public.art_piezas where op = new.op and not tercero for update loop
      k := ceil(p.cant::numeric / greatest(n_uni, 1));
      con_reg := exists (select 1 from public.art_registros g where g.pieza_id = p.id);
      if p.base > 0 and not con_reg then
        update public.art_piezas set base = greatest(0, base - k), historica = (base - k) > 0 where id = p.id;
      else
        update public.art_piezas set rotas = rotas + least(k, public.art_hechos(p, p.ruta[array_length(p.ruta, 1)])) where id = p.id;
      end if;
    end loop;
  elsif new.vidrio_proc = 'X' then
    -- Marcado a mano: si toda la OP queda en X y no hay escaneos, vidrio terminado
    if not exists (select 1 from public.items i where i.op = new.op and i.vidrio_proc is distinct from 'X')
       and not exists (select 1 from public.art_registros g join public.art_piezas q on q.id = g.pieza_id where q.op = new.op) then
      update public.art_piezas set historica = true, base = cant, rotas = 0 where op = new.op and not tercero;
    end if;
  end if;
  return null;
end; $$;

create or replace function public.art_escanear(p_codigo text, p_estacion text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id bigint; v_n int; ult timestamptz; pz public.art_piezas; hechos int; previos int; ant text; pos int; est text := lower(trim(p_estacion));
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
  v_n  := nullif(substring(cod from 'ART[:\-]?\d+[.\-/](\d+)'), '')::int;   -- número de la pieza en la etiqueta (ART:123-5 = pieza 5)
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
  -- La misma pieza (número de etiqueta) no se registra dos veces en la estación, salvo que se haya mandado a reprocesar después
  if v_n is not null then
    select max(creado) into ult from public.art_reprocesos where pieza_id = pz.id;
    if exists (select 1 from public.art_registros g where g.pieza_id = pz.id and g.estacion = est and g.n = v_n and (ult is null or g.creado > ult)) then
      return jsonb_build_object('estado','ya','msg','La pieza ' || v_n || '/' || pz.cant || ' ya pasó por ' || est, 'pieza', to_jsonb(pz), 'hechos', hechos, 'estacion', est, 'hoy', hoy, 'n', v_n);
    end if;
  end if;
  if pos > 1 then
    ant := pz.ruta[pos - 1];
    previos := public.art_hechos(pz, ant);
    if previos <= hechos then
      return jsonb_build_object('estado','fuera','msg','Falta ' || ant || ' (' || previos || ' de ' || pz.cant || ')', 'pieza', to_jsonb(pz), 'hechos', hechos, 'estacion', est, 'hoy', hoy);
    end if;
  end if;
  select nombre into quien from public.perfiles where id = auth.uid();
  insert into public.art_registros (pieza_id, estacion, quien, n) values (pz.id, est, quien, v_n);
  return jsonb_build_object('estado','ok','n', v_n, 'pieza', to_jsonb(pz), 'hechos', hechos + 1, 'estacion', est, 'hoy', hoy + 1,
    'listo', pos = array_length(pz.ruta, 1));
end; $$;
revoke all on function public.art_escanear(text, text) from public, anon;
grant execute on function public.art_escanear(text, text) to authenticated;

select 'Listo SQL 70 — trazabilidad por pieza y reprocesos' as resultado;
