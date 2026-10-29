-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Cargar OP sin "timeout"
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  El sistema se deducía fila por fila al insertar (≈0,1-0,2 s por ítem revisando toda la base):
--  una OP grande se pasaba del tiempo máximo. Ahora se deduce UNA vez por cada diseño distinto
--  de la carga (se recuerda durante la carga). Al editar el diseño de un ítem sigue igual.
-- ════════════════════════════════════════════════════════════════
drop trigger if exists trg_items_sistema_carga on public.items;
drop function if exists public.items_sistema_carga();

create or replace function public.items_sistema_ins()
returns trigger language plpgsql as $$
declare k text; v text;
begin
  if (new.sistema is null or btrim(new.sistema) = '') and new.diseno is not null and btrim(new.diseno) <> '' then
    k := 'elp.sis_' || md5(upper(btrim(new.diseno)));
    v := current_setting(k, true);
    if v is null then v := coalesce(public.sistema_inferido(new.diseno), ''); perform set_config(k, v, true); end if;
    if v <> '' then new.sistema := v; end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_items_sistema_ins on public.items;
create trigger trg_items_sistema_ins before insert on public.items for each row execute function public.items_sistema_ins();

-- Al editar: como antes
drop trigger if exists trg_items_sistema on public.items;
create trigger trg_items_sistema before update of diseno, sistema on public.items
  for each row execute function public.items_sistema_auto();

select 'Listo SQL 85 — carga de OP rápida' as r;
