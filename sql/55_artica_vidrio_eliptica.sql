-- ════════════════════════════════════════════════════════════════
--  ÁRTICA → ELÍPTICA · Proceso "Vidrio" automático al 70 %
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada vez que en Ártica una pieza termina su ruta (último escaneo = lista),
--  se revisa cada medida de esa OP-ítem. Cuando TODAS las medidas tienen al menos
--  el 70 % de sus piezas listas, los ítems de esa OP en Elíptica quedan con Vidrio en X.
--  Si después se deshace un escaneo, la marca en Elíptica NO se quita sola
--  (se quita a mano si hace falta). Las OP de terceros no aplican.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.art_vidrio_auto (op text primary key, marcado timestamptz not null default now(), pct int, items int);
alter table public.art_vidrio_auto enable row level security;
drop policy if exists art_vidrio_auto_leer on public.art_vidrio_auto;
create policy art_vidrio_auto_leer on public.art_vidrio_auto for select to authenticated using (public.art_lee());
grant select on public.art_vidrio_auto to authenticated;
grant all on public.art_vidrio_auto to service_role;

create or replace function public.art_sync_vidrio_op(p_op text)
returns int language plpgsql security definer set search_path = public as $$
declare n_med int; n_ok int; tot numeric; ok numeric; n int := 0;
begin
  -- Cada medida (línea de vidrio) de la OP-ítem debe tener al menos el 70 % de sus piezas listas
  select count(*), count(*) filter (where l >= 0.7 * cant), sum(cant), sum(l)
    into n_med, n_ok, tot, ok
    from (select p.cant, least(p.cant, (select count(*) from public.art_registros g where g.pieza_id = p.id and g.estacion = p.ruta[array_length(p.ruta, 1)])) l
            from public.art_piezas p where p.op = p_op and not p.tercero) x;
  if coalesce(n_med, 0) = 0 or n_ok < n_med then return 0; end if;
  update public.items set vidrio_proc = 'X' where op = p_op and vidrio_proc is distinct from 'X';
  get diagnostics n = row_count;
  insert into public.art_vidrio_auto (op, pct, items) values (p_op, round(ok / tot * 100), n) on conflict (op) do nothing;
  return n;
end; $$;
revoke all on function public.art_sync_vidrio_op(text) from public, anon, authenticated;

create or replace function public.art_sync_vidrio()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_op text; v_ult text;
begin
  select op, ruta[array_length(ruta, 1)] into v_op, v_ult from public.art_piezas where id = new.pieza_id;
  if new.estacion = v_ult then perform public.art_sync_vidrio_op(v_op); end if;
  return null;
end; $$;
drop trigger if exists trg_art_sync_vidrio on public.art_registros;
create trigger trg_art_sync_vidrio after insert on public.art_registros for each row execute function public.art_sync_vidrio();

-- Ponerse al día con lo que ya esté listo
select 'Listo ✓ — Vidrio automático al 70 %' as resultado,
       coalesce(sum(public.art_sync_vidrio_op(op)), 0) as items_marcados_ahora
  from (select distinct op from public.art_piezas where not tercero) x;
