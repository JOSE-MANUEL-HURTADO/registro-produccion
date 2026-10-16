-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Candado en la base: no iniciar ensamble sin procesos
--  Para iniciar ensamble (poner ensamblador o día de inicio a un ítem
--  que no los tenía) deben estar en X: cortado, troquelado, mecanizado
--  y programado. Solo el gerente puede saltarse la regla.
--  La app ya lo controla; esto evita que se salte por fuera de la app.
-- ════════════════════════════════════════════════════════════════
create or replace function public.chk_ensamble_procesos()
returns trigger language plpgsql security definer set search_path = public as $$
declare falta text;
begin
  if (new.ensamblador is not null or new.dia_inicio is not null)
     and old.ensamblador is null and old.dia_inicio is null
     and not coalesce(public.es_gerente(), false) then
    falta := concat_ws(', ',
      case when coalesce(new.cortado,'')    <> 'X' then 'COR' end,
      case when coalesce(new.troquelado,'') <> 'X' then 'TRO' end,
      case when coalesce(new.mecanizado,'') <> 'X' then 'MEC' end,
      case when coalesce(new.programado,'') <> 'X' then 'PRG' end);
    if falta <> '' then
      raise exception 'No se puede iniciar el ensamble de %: falta completar %', coalesce(new.op_instalacion, new.op), falta;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ensamble_procesos on public.items;
create trigger trg_ensamble_procesos
  before update of ensamblador, dia_inicio on public.items
  for each row execute function public.chk_ensamble_procesos();
