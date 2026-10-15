-- Historial también para los cambios de cobros (items_comercial)
create or replace function public.registrar_historial_com()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'UPDATE' and row(new.*) is not distinct from row(old.*) then return new; end if;
  -- En INSERT solo se anota lo que hace el usuario de cobros (las cargas masivas del gerente no llenan el historial)
  if TG_OP = 'INSERT' and coalesce(public.rol_actual(), '') <> 'cobros' then return new; end if;
  insert into public.historial (item_id, usuario, antes, despues)
  values (new.item_id, auth.uid(), case when TG_OP = 'UPDATE' then to_jsonb(old) end, to_jsonb(new) || '{"_tabla":"cobros"}'::jsonb);
  return new;
end; $$;
drop trigger if exists trg_historial_com on public.items_comercial;
create trigger trg_historial_com after insert or update on public.items_comercial
  for each row execute function public.registrar_historial_com();
select 'Listo ✓' as resultado;
