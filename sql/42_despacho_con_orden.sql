-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Nada se despacha sin estar en una orden de despacho
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Al marcar un ítem como despachado, debe estar en una orden de despacho
--  ABIERTA. Si se escanea otra unidad de la misma OP, la app la cambia por
--  la planeada dentro de la orden antes de despacharla, así que sigue
--  funcionando. Solo el gerente puede despachar por fuera (correcciones).
-- ════════════════════════════════════════════════════════════════
create or replace function public.exigir_orden_despacho()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.despachado and not coalesce(old.despachado, false)
     and not coalesce(public.es_gerente(), false)
     and coalesce(current_setting('elp.swap', true), '') <> '1'
     and not exists (select 1 from public.ordenes_despacho o where o.estado = 'abierta' and new.id = any(o.items)) then
    raise exception '% no está en una orden de despacho abierta: no se puede despachar', coalesce(new.op_instalacion, new.op);
  end if;
  return new;
end; $$;
drop trigger if exists trg_01_exigir_orden on public.items;
create trigger trg_01_exigir_orden before update of despachado on public.items
  for each row execute function public.exigir_orden_despacho();
revoke all on function public.exigir_orden_despacho() from public, anon;

select 'Listo ✓ — desde ahora solo se despacha lo que está en una orden de despacho abierta' as resultado;
