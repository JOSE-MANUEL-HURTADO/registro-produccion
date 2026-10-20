-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Una sola remisión por orden de despacho (corrección)
--  Antes de la versión 6.42, si una orden se cargaba a distintas horas,
--  salía una remisión nueva cada vez. Aquí, para las órdenes de los
--  últimos 3 días con más de una remisión, todo lo cargado de la orden
--  queda con la PRIMERA remisión (la de número menor).
--  · Si alguna de esas remisiones ya tiene recibido firmado, la orden NO
--    se toca y aparece como "revisar" (para no separar la firma).
--  Lo anterior queda en remisiones_unificadas. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.remisiones_unificadas (
  item_id bigint primary key, orden_id bigint, obra text, remision_antes text, remision_nueva text,
  cuando timestamptz not null default now()
);
alter table public.remisiones_unificadas enable row level security;
create table if not exists public.remisiones_unificadas_resumen (
  orden_id bigint, obra text, remisiones text, queda text, items int, estado text,
  cuando timestamptz not null default now()
);
alter table public.remisiones_unificadas_resumen enable row level security;
delete from public.remisiones_unificadas_resumen;

do $$
declare o record; rems text[]; queda text; firm text; k int;
begin
  for o in select * from public.ordenes_despacho where creada >= now() - interval '3 days' and estado <> 'anulada' loop
    select array_agg(distinct remision order by remision) into rems
      from public.items where id = any(o.items) and despachado and coalesce(remision, '') <> '';
    if rems is null or array_length(rems, 1) < 2 then continue; end if;
    select string_agg(remision, ', ') into firm from public.recepciones_remision where remision = any(rems);
    if firm is not null then
      insert into public.remisiones_unificadas_resumen values (o.id, o.obra, array_to_string(rems, ', '), null, 0,
        'revisar: ya tiene recibido firmado (' || firm || ')');
      continue;
    end if;
    -- la de número menor (00-NNN) es la primera que salió
    select r into queda from unnest(rems) r
      order by nullif(substring(r from '(\d+)$'), '')::int nulls last, r limit 1;
    insert into public.remisiones_unificadas (item_id, orden_id, obra, remision_antes, remision_nueva)
      select id, o.id, obra, remision, queda from public.items
      where id = any(o.items) and despachado and remision is distinct from queda and coalesce(remision, '') <> ''
      on conflict (item_id) do nothing;
    update public.items set remision = queda
      where id = any(o.items) and despachado and remision is distinct from queda and coalesce(remision, '') <> '';
    get diagnostics k = row_count;
    update public.ordenes_despacho set remision = queda where id = o.id;
    insert into public.remisiones_unificadas_resumen values (o.id, o.obra, array_to_string(rems, ', '), queda, k, 'unificada');
  end loop;
end $$;

select orden_id as orden, obra, remisiones as tenia, queda, items as items_cambiados, estado
from public.remisiones_unificadas_resumen order by orden_id;
