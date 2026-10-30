-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Vidrio marcado en Elíptica unidad por unidad (sin esperar a que toda la OP esté en X)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Antes: marcar "vidrio procesado" en Elíptica solo descontaba en Ártica cuando TODA la OP quedaba en X
--  (ej. La Cité 6300-1 con 1 de 17 marcadas → en Ártica seguían las 34 piezas pendientes).
--  Ahora, si la OP no tiene escaneos en Ártica, las piezas hechas = cant × unidades marcadas ÷ unidades de la OP.
--  También se corrige lo que ya estaba marcado.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_vidrio_cambio()
returns trigger language plpgsql security definer set search_path = public as $$
declare n_uni int; n_x int; p public.art_piezas; k int; con_reg boolean;
begin
  if coalesce(current_setting('elp.swap', true), '') = '1' or new.op is null then return null; end if;
  if old.vidrio_proc is not distinct from new.vidrio_proc then return null; end if;
  select count(*), count(*) filter (where vidrio_proc = 'X') into n_uni, n_x from public.items where op = new.op;
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
    if not exists (select 1 from public.art_registros g join public.art_piezas q on q.id = g.pieza_id where q.op = new.op and not q.tercero) then
      if n_x >= n_uni then
        -- toda la OP en X: vidrio terminado
        update public.art_piezas set historica = true, base = cant, rotas = 0 where op = new.op and not tercero;
      else
        -- parcial: piezas hechas en proporción a las unidades marcadas
        update public.art_piezas set base = greatest(base, least(cant, ceil(cant::numeric * n_x / greatest(n_uni, 1))::int)), historica = true
         where op = new.op and not tercero and base < least(cant, ceil(cant::numeric * n_x / greatest(n_uni, 1))::int);
      end if;
    end if;
  end if;
  return null;
end; $$;

-- Corregir lo ya marcado: OP de Elíptica con vidrio en X en parte de sus unidades y sin escaneos en Ártica
with u as (select op, count(*) n, count(*) filter (where vidrio_proc = 'X') x from public.items where op is not null group by op),
     s as (select distinct q.op from public.art_registros g join public.art_piezas q on q.id = g.pieza_id where not q.tercero)
update public.art_piezas p set base = least(p.cant, ceil(p.cant::numeric * u.x / greatest(u.n, 1))::int), historica = true
  from u where u.op = p.op and not p.tercero and u.x > 0 and p.op not in (select op from s)
   and p.base < least(p.cant, ceil(p.cant::numeric * u.x / greatest(u.n, 1))::int);

select 'Listo SQL 100' as r, (select string_agg(op || ': ' || base || '/' || cant, ', ' order by op) from public.art_piezas where obra = 'LA CITE' and op in ('6295-18', '6300-1')) la_cite;
