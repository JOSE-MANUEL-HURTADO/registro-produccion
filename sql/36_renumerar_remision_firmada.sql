-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Número consecutivo real para la remisión firmada en ceros
--  Las remisiones recuperadas con el SQL 34 (p. ej. Serrano López, "0000")
--  reciben el siguiente número consecutivo 00-NNN. Se cambia a la vez en
--  los ítems, en el recibido firmado (la firma no se pierde), en la orden
--  de despacho y en los despachos cancelados. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.remisiones_renumeradas (
  remision_antes text primary key, remision_nueva text, obra text, items int,
  cuando timestamptz not null default now()
);
alter table public.remisiones_renumeradas enable row level security;

do $$
declare r record; usado int; n int; nueva text; k int;
begin
  for r in
    select x.remision_antes as rem, min(x.obra) as obra
    from public.remisiones_recuperadas x
    where x.remision_antes ~ '^[0\s\-\./]+$'
      and not exists (select 1 from public.remisiones_renumeradas z where z.remision_antes = x.remision_antes)
    group by x.remision_antes
  loop
    perform pg_advisory_xact_lock(4207001);
    select coalesce(max(substring(remision from '^00-(\d{1,6})$')::integer), 0) into usado
      from public.items where remision ~ '^00-\d{1,6}$';
    select greatest(usado, coalesce(max(num), 0)) + 1 into n from public.remisiones;
    insert into public.remisiones (num) values (n);
    nueva := '00-' || lpad(n::text, 3, '0');
    update public.items i set remision = nueva
      from public.remisiones_recuperadas x
      where x.id = i.id and x.remision_antes = r.rem and i.remision = r.rem;
    get diagnostics k = row_count;
    update public.recepciones_remision set remision = nueva where remision = r.rem;
    update public.ordenes_despacho set remision = nueva where remision = r.rem and obra = r.obra;
    update public.despachos_cancelados set remision = nueva where remision = r.rem and obra = r.obra;
    insert into public.remisiones_renumeradas values (r.rem, nueva, r.obra, k);
  end loop;
end $$;

select obra, remision_antes, remision_nueva, items from public.remisiones_renumeradas order by cuando desc;
