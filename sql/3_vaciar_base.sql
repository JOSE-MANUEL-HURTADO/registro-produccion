-- Vaciado rápido de la base para "Reemplazar base completa". Solo el gerente puede ejecutarla.
create or replace function public.vaciar_base()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_gerente() then
    raise exception 'Solo el gerente puede vaciar la base';
  end if;
  truncate table public.items restart identity cascade;
  truncate table public.historial;
end;
$$;
revoke all on function public.vaciar_base() from public, anon;
grant execute on function public.vaciar_base() to authenticated;
