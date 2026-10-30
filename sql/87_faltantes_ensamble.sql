-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Falta material (accesorios) en ENSAMBLE
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · En la novedad de ensamble "Falta material" se elige el accesorio (HSA…) de la OP y cuántos faltaron.
--    Queda en la misma tabla de faltantes con proceso = 'ensamble' y ligado a la novedad.
--  · Las unidades afectadas quedan EN ESPERA (novedad de ensamble).
--  · Al reanudar o terminar el ensamble (la novedad queda resuelta), el faltante queda resuelto solo.
-- ════════════════════════════════════════════════════════════════
alter table public.faltantes add column if not exists novedad_id bigint;
create index if not exists faltantes_novedad_idx on public.faltantes (novedad_id) where novedad_id is not null;

-- Aviso: dice si fue en corte o en ensamble
create or replace function public.faltante_nuevo()
returns trigger language plpgsql security definer set search_path = public as $$
declare a record; v_txt text; v_proc text;
begin
  new.quien := coalesce(new.quien, public.notif_quien());
  v_proc := case when new.proceso = 'ensamble' then 'falta en ensamble' else 'corte parcial' end;
  v_txt := 'Falta ' || new.ref || coalesce(' ' || new.descripcion, '') || coalesce(' · ' || trim(to_char(new.cant, 'FM999990.##')) || ' und', '')
        || coalesce(' × ' || trim(to_char(new.medida, 'FM999990')) || ' mm', '') || ' · OP ' || new.op
        || case when array_length(new.op_inst, 1) between 1 and 6 then ' (' || array_to_string(new.op_inst, ', ') || ')' else '' end;
  begin
    perform public.notif_crear('Elíptica · ' || coalesce(new.obra, ''), new.quien || ': ' || v_proc || ' · ' || v_txt || coalesce(' · ' || new.nota, ''));
  exception when others then null; end;
  begin
    for a in select pf.id from public.perfiles pf where pf.rol = 'asistente' and pf.id is distinct from auth.uid() loop
      insert into public.avisos (para, tipo, obra, ops, items, n, quien, ref)
      values (a.id, 'Falta material' || case when new.proceso = 'ensamble' then ' (ensamble)' else '' end || ' · ' || new.ref, new.obra, new.op,
              left(coalesce(new.descripcion, '') || coalesce(' · ' || new.nota, ''), 400),
              coalesce(array_length(new.item_ids, 1), 0), new.quien, 'falt:' || new.id);
      begin perform public.notif_para(a.id, 'Falta material · ' || new.ref, v_txt || ' · ' || coalesce(new.obra, '')); exception when others then null; end;
    end loop;
  exception when others then null; end;
  return new;
end; $$;

-- Novedad resuelta (reanudado, terminado o anulado) → sus faltantes de ensamble quedan resueltos
create or replace function public.faltante_ens_ok()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.resuelta_en is not null and old.resuelta_en is null then
    update public.faltantes set resuelta = now(), resuelta_por = coalesce(new.resuelta_por, 'Ensamble reanudado')
     where novedad_id = new.id and resuelta is null;
  end if;
  return null;
end; $$;
drop trigger if exists trg_faltante_ens_ok on public.novedades_ensamble;
create trigger trg_faltante_ens_ok after update of resuelta_en on public.novedades_ensamble
  for each row execute function public.faltante_ens_ok();

select 'Listo SQL 87 — faltantes en ensamble' as r,
       (select count(*) from information_schema.columns where table_name = 'faltantes' and column_name = 'novedad_id') col;
