-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Cargar OP sin "timeout"
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  El sistema se deducía fila por fila al insertar (≈0,1 s por ítem revisando toda la base):
--  una OP grande se pasaba del tiempo máximo. Ahora se deduce UNA vez por cada diseño distinto
--  de la carga, después de insertar. Al editar el diseño de un ítem sigue funcionando igual.
-- ════════════════════════════════════════════════════════════════
drop trigger if exists trg_items_sistema on public.items;
create trigger trg_items_sistema before update of diseno, sistema on public.items
  for each row execute function public.items_sistema_auto();

create or replace function public.items_sistema_carga()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('elp.swap', '1', true);
  update public.items i set sistema = s.sis
    from (select d, public.sistema_inferido(d) sis
            from (select distinct diseno d from nuevos where (sistema is null or btrim(sistema) = '') and diseno is not null) x) s
   where i.id in (select id from nuevos where sistema is null or btrim(sistema) = '')
     and i.diseno = s.d and s.sis is not null;
  perform set_config('elp.swap', '', true);
  return null;
exception when others then
  perform set_config('elp.swap', '', true);
  raise warning 'sistema no deducido: %', sqlerrm;   -- nunca bloquea la carga
  return null;
end; $$;
drop trigger if exists trg_items_sistema_carga on public.items;
create trigger trg_items_sistema_carga after insert on public.items referencing new table as nuevos
  for each statement execute function public.items_sistema_carga();

select 'Listo SQL 85 — carga de OP rápida' as r;
