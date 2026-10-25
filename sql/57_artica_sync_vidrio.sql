-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Sintonizar con el proceso "Vidrio" de Elíptica
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Antes de la app de Ártica el vidrio se registraba a mano en Elíptica (proceso Vidrio).
--  Si TODOS los ítems de una OP tienen Vidrio en X en Elíptica y la OP no tiene ningún
--  escaneo en Ártica, su vidrio queda terminado en Ártica. Se aplica ahora y cada vez
--  que se cargan vidrios. (Las OP que Ártica marcó solas al 70 % ya tienen escaneos: no se tocan.)
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_marcar_historicas()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.art_piezas p set historica = true
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

select 'Listo ✓ — Ártica sintonizada con el Vidrio de Elíptica' as resultado, public.art_marcar_historicas() as lineas_marcadas_ahora;
