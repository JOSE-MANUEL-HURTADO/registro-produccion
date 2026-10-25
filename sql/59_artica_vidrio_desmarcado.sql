-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Desmarcar o marcar el proceso VIDRIO en Elíptica se refleja en Ártica
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Si se DESMARCA Vidrio en una sub-OP, el vidrio de esa unidad vuelve a quedar pendiente
--    en Ártica (desde corte). Si la pieza estaba "terminada antes de la app" se le resta esa
--    unidad; si ya tenía escaneos, queda como REPROCESO.
--  · Si se vuelve a MARCAR Vidrio a mano y todas las sub-OP de la OP quedan en X sin escaneos
--    en Ártica, el vidrio de la OP vuelve a quedar terminado.
--  · Al correrlo se corrigen las OP que hoy tienen Vidrio desmarcado y seguían terminadas.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_vidrio_cambio()
returns trigger language plpgsql security definer set search_path = public as $$
declare n_uni int; p public.art_piezas; k int; con_reg boolean;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' or new.op is null then return null; end if;
  if old.vidrio_proc is not distinct from new.vidrio_proc then return null; end if;
  select count(*) into n_uni from public.items where op = new.op;
  if old.vidrio_proc = 'X' then
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
drop trigger if exists trg_art_vidrio_cambio on public.items;
create trigger trg_art_vidrio_cambio after update of vidrio_proc on public.items for each row execute function public.art_vidrio_cambio();

-- Corrección de hoy: OP con ítems EN COLA y Vidrio desmarcado que seguían terminadas en Ártica
with x as (
  select p.id, p.cant,
         (select count(*) from public.items i where i.op = p.op) n_uni,
         (select count(*) from public.items i where i.op = p.op and i.vidrio_proc is distinct from 'X') sin_vid
    from public.art_piezas p
   where p.historica and not p.tercero
     and not exists (select 1 from public.art_registros g where g.pieza_id = p.id)
     and exists (select 1 from public.items i where i.op = p.op and i.status = 'EN COLA')
     and not exists (select 1 from public.items i join public.obras_cerradas c on c.obra = i.obra where i.op = p.op)
     and exists (select 1 from public.items i where i.op = p.op and i.vidrio_proc is distinct from 'X'))
update public.art_piezas p
   set base = greatest(0, p.base - least(p.cant, x.sin_vid * ceil(x.cant::numeric / greatest(x.n_uni, 1))::int)),
       historica = greatest(0, p.base - least(p.cant, x.sin_vid * ceil(x.cant::numeric / greatest(x.n_uni, 1))::int)) > 0
  from x where x.id = p.id;

select 'Listo SQL 59' as resultado,
       (select string_agg(op || ' base ' || base || '/' || cant, ', ') from public.art_piezas where op in ('6287-4','6287-5','6287-6')) as op_6287,
       (select count(*) from public.art_piezas where not historica) as en_seguimiento;
