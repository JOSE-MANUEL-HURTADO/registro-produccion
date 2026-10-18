-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Secuencia obligatoria completa (candado en la base)
--   procesos (COR, TRO, MEC, PRG en X) → inicio de ensamble → ensamble terminado
--   → despacho (con remisión) → instalación → acta de entrega
--  Solo el gerente puede iniciar un ensamble sin los procesos completos
--  o quitar un proceso a un ítem que ya está en ensamble.
--  Revisa solo cuando el dato CAMBIA: los registros viejos se pueden seguir editando.
--  Reemplaza los candados de 11_secuencia_y_cortes y 13_ensamble_procesos.
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create or replace function public.validar_secuencia()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  ger boolean := coalesce(public.es_gerente(), false);
  en_ens boolean := new.ensamblador is not null or new.dia_inicio is not null;
  ens boolean := new.dia_final is not null or coalesce(old.status,'') in ('ENSAMBLADO','DESPACHADO');
  falta text;
  quita text;
begin
  -- 1. Iniciar ensamble: deben estar en X cortado, troquelado, mecanizado y programado
  if en_ens and old.ensamblador is null and old.dia_inicio is null and not ger then
    falta := concat_ws(', ',
      case when coalesce(new.cortado,'')    <> 'X' then 'COR' end,
      case when coalesce(new.troquelado,'') <> 'X' then 'TRO' end,
      case when coalesce(new.mecanizado,'') <> 'X' then 'MEC' end,
      case when coalesce(new.programado,'') <> 'X' then 'PRG' end);
    if falta <> '' then
      raise exception 'No se puede iniciar el ensamble de % (OP %): falta completar %', new.item, coalesce(new.op_instalacion, new.op), falta;
    end if;
  end if;
  -- 2. No quitar un proceso a un ítem que ya está en ensamble
  if en_ens and not ger then
    quita := concat_ws(', ',
      case when old.cortado    = 'X' and coalesce(new.cortado,'')    <> 'X' then 'COR' end,
      case when old.troquelado = 'X' and coalesce(new.troquelado,'') <> 'X' then 'TRO' end,
      case when old.mecanizado = 'X' and coalesce(new.mecanizado,'') <> 'X' then 'MEC' end,
      case when old.programado = 'X' and coalesce(new.programado,'') <> 'X' then 'PRG' end);
    if quita <> '' then
      raise exception 'El ítem % (OP %) ya está en ensamble: no se puede quitar %', new.item, coalesce(new.op_instalacion, new.op), quita;
    end if;
  end if;
  -- 3. Terminar ensamble: debe tener ensamblador y día de inicio
  if new.dia_final is not null and old.dia_final is null and (new.ensamblador is null or new.dia_inicio is null) then
    raise exception 'No se puede terminar el ensamble de % (OP %): falta el ensamblador o el día de inicio', new.item, coalesce(new.op_instalacion, new.op);
  end if;
  -- 4. Despachar: debe estar ensamblado y llevar remisión
  if new.despachado and not coalesce(old.despachado, false) then
    if not ens then raise exception 'No se puede despachar: el ítem % (OP %) no está ensamblado', new.item, coalesce(new.op_instalacion, new.op); end if;
    if coalesce(trim(new.remision), '') = '' then raise exception 'No se puede despachar el ítem % (OP %) sin número de remisión', new.item, coalesce(new.op_instalacion, new.op); end if;
  end if;
  -- 5. Instalar: debe estar despachado
  if new.instalado and not coalesce(old.instalado, false) and not coalesce(new.despachado, false) then
    raise exception 'No se puede instalar: el ítem % (OP %) no está despachado', new.item, coalesce(new.op_instalacion, new.op);
  end if;
  -- 6. Hacia atrás: no se deshace un paso si el siguiente ya está hecho
  if coalesce(old.despachado, false) and not coalesce(new.despachado, false) and coalesce(new.instalado, false) then
    raise exception 'El ítem % (OP %) está instalado: primero quita la instalación', new.item, coalesce(new.op_instalacion, new.op);
  end if;
  if coalesce(new.despachado, false) and ((old.dia_final is not null and new.dia_final is null) or (old.ensamblador is not null and new.ensamblador is null)) then
    raise exception 'El ítem % (OP %) está despachado: primero quita el despacho', new.item, coalesce(new.op_instalacion, new.op);
  end if;
  return new;
end; $$;
drop trigger if exists trg_validar_secuencia on public.items;
create trigger trg_validar_secuencia before update on public.items
  for each row execute function public.validar_secuencia();
-- El candado anterior de procesos queda incluido aquí
drop trigger if exists trg_ensamble_procesos on public.items;
