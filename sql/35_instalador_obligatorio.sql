-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · No se registra una instalación sin instalador
--  Aplica a todo: escáner, ficha del ítem, selección múltiple y usuario de cobros.
--  (Lo ya instalado sin instalador no se toca; se puede completar después.)
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create or replace function public.requiere_instalador() returns trigger language plpgsql as $$
begin
  if coalesce(new.instalado, false) and not coalesce(old.instalado, false)
     and coalesce(trim(new.instalador), '') = '' then
    raise exception 'Falta el instalador: no se puede registrar la instalación de % (OP %) sin instalador', new.item, coalesce(new.op_instalacion, new.op);
  end if;
  return new;
end; $$;
drop trigger if exists trg_requiere_instalador on public.items;
create trigger trg_requiere_instalador before update on public.items
  for each row execute function public.requiere_instalador();

-- Para revisar: lo instalado sin instalador (más reciente primero)
select obra, op_instalacion, item, fecha_instalacion
from public.items
where instalado and coalesce(trim(instalador), '') = ''
order by fecha_instalacion desc nulls last
limit 50;
