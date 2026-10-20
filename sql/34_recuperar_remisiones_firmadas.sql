-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Recuperar remisiones firmadas que el SQL 27 renombró
--  El SQL 27 le puso número SR-… a todo lo despachado con remisión en
--  ceros. Si una de esas remisiones ya tenía el recibido firmado, los
--  ítems quedaron separados de su firma. Aquí se les devuelve el número
--  con el que se firmó (solo las OP que aparecen en ese recibido y
--  despachadas cerca de la fecha de la firma).
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.remisiones_recuperadas (
  id bigint primary key, obra text, op text, remision_actual text, remision_antes text, firmo text, creada timestamptz,
  cuando timestamptz not null default now()
);
alter table public.remisiones_recuperadas enable row level security;
insert into public.remisiones_recuperadas (id, obra, op, remision_actual, remision_antes, firmo, creada)
select i.id, i.obra, i.op, i.remision as remision_actual, rc.remision_antes, r.nombre as firmo, r.creada
from public.remisiones_corregidas rc
join public.items i on i.id = rc.item_id and i.remision = rc.remision_nueva
join public.recepciones_remision r on r.remision = rc.remision_antes
where exists (select 1 from jsonb_array_elements(r.detalle) d where d->>'op' = i.op)
  and (i.fecha_despacho is null or i.fecha_despacho::date >= r.creada::date - 7)
on conflict (id) do nothing;

do $$
begin
  perform set_config('elp.swap', '1', true);
  update public.items i set remision = x.remision_antes from public.remisiones_recuperadas x where i.id = x.id and i.remision = x.remision_actual;
  delete from public.remisiones_corregidas rc using public.remisiones_recuperadas x where rc.item_id = x.id;
  perform set_config('elp.swap', '', true);
end $$;

-- Lo que se recuperó: una fila por remisión
select obra, remision_antes as remision, firmo as recibido_por, creada::date as firmado, count(*) as items
from public.remisiones_recuperadas group by 1, 2, 3, 4 order by 4 desc, 1;
