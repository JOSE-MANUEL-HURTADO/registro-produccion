-- ════════════════════════════════════════════════════════════════
--  ASISTENCIA DIARIA DE PLANTA (ensambladores y procesos) + avisos
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Al comenzar la jornada la asistente (o el director) marca cada ensamblador: en planta, en obra
--    o ausente; y cada proceso (corte, troquelado, mecanizado, vidrio, prealistado): con operario o
--    SIN OPERARIO con su motivo (queda como novedad que justifica que ese día no se produjo).
--  · Cada 30 minutos (lunes a viernes, 8:00 a 16:30, fuera del almuerzo) se revisa:
--      - si no han registrado la asistencia del día → aviso;
--      - ensambladores EN PLANTA sin una OP en mesa (iniciada y sin terminar, que no esté en espera) → aviso.
--    Llega al director (celular) y a la asistente (campana y celular). Máximo un aviso cada 90 min por persona.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.asistencia (
  id          bigserial primary key,
  fecha       date not null default (now() at time zone 'America/Bogota')::date,
  tipo        text not null,
  clave       text not null,
  estado      text not null,
  motivo      text,
  operario    text,
  quien       text,
  usuario     uuid default auth.uid(),
  creada      timestamptz not null default now(),
  actualizada timestamptz not null default now(),
  unique (fecha, tipo, clave)
);
alter table public.asistencia drop constraint if exists asistencia_tipo_chk;
alter table public.asistencia add constraint asistencia_tipo_chk check (tipo in ('ensamble', 'proceso'));
alter table public.asistencia drop constraint if exists asistencia_estado_chk;
alter table public.asistencia add constraint asistencia_estado_chk check (estado in ('planta', 'obra', 'ausente', 'activo', 'sin_operario'));
create index if not exists asistencia_fecha_idx on public.asistencia (fecha);
alter table public.asistencia enable row level security;
drop policy if exists asis_ver on public.asistencia;
create policy asis_ver on public.asistencia for select to authenticated using ((select public.es_interno()));
drop policy if exists asis_escribir on public.asistencia;
create policy asis_escribir on public.asistencia for all to authenticated
  using ((select public.puede_registrar())) with check ((select public.puede_registrar()));
grant select, insert, update, delete on public.asistencia to authenticated;
grant usage, select on sequence public.asistencia_id_seq to authenticated;
grant all on public.asistencia to service_role;

create or replace function public.asistencia_touch()
returns trigger language plpgsql as $$
begin new.actualizada := now(); new.quien := coalesce(public.notif_quien(), new.quien); return new; end; $$;
drop trigger if exists trg_asistencia_touch on public.asistencia;
create trigger trg_asistencia_touch before insert or update on public.asistencia for each row execute function public.asistencia_touch();

-- Control de avisos (para no repetir)
create table if not exists public.asistencia_alertas (fecha date not null, clave text not null, ultima timestamptz not null, primary key (fecha, clave));
alter table public.asistencia_alertas enable row level security;
grant all on public.asistencia_alertas to service_role;

create or replace function public.asistencia_avisar(p_tipo text, p_txt text)
returns void language plpgsql security definer set search_path = public as $$
declare a record;
begin
  begin perform public.notif_crear('Elíptica · ' || p_tipo, p_txt); exception when others then null; end;
  begin
    for a in select pf.id from public.perfiles pf where pf.rol = 'asistente' loop
      insert into public.avisos (para, tipo, obra, ops, items, n, quien, ref) values (a.id, p_tipo, null, null, left(p_txt, 400), 0, 'Sistema', 'asis:' || now()::date);
      begin perform public.notif_para(a.id, p_tipo, p_txt); exception when others then null; end;
    end loop;
  exception when others then null; end;
end; $$;
revoke all on function public.asistencia_avisar(text, text) from public, anon, authenticated;

create or replace function public.asistencia_revisar()
returns text language plpgsql security definer set search_path = public as $$
declare
  ahora timestamp := now() at time zone 'America/Bogota'; hoy date := ahora::date; h time := ahora::time;
  sin text[];
begin
  if extract(isodow from hoy) > 5 then return 'fin de semana'; end if;
  if h < time '08:20' or h > time '16:45' or (h >= time '12:00' and h < time '13:15') then return 'fuera de jornada'; end if;
  -- 1. No han registrado quién está en planta
  if not exists (select 1 from public.asistencia where fecha = hoy and tipo = 'ensamble') then
    if not exists (select 1 from public.asistencia_alertas where fecha = hoy and clave = '_registro' and ultima > now() - interval '90 minutes') then
      perform public.asistencia_avisar('Asistencia de planta', 'Falta registrar quién está hoy en planta (ensambladores y procesos).');
      insert into public.asistencia_alertas values (hoy, '_registro', now()) on conflict (fecha, clave) do update set ultima = now();
    end if;
    return 'sin registro';
  end if;
  -- 2. Ensambladores en planta sin OP en mesa
  select array_agg(a.clave order by a.clave) into sin
    from public.asistencia a
   where a.fecha = hoy and a.tipo = 'ensamble' and a.estado = 'planta' and upper(a.clave) not in ('ARTICA', 'ÁRTICA')
     and not exists (select 1 from public.items i where upper(btrim(i.ensamblador)) = upper(btrim(a.clave))
                       and i.dia_inicio is not null and i.dia_final is null and not coalesce(i.despachado, false) and i.ens_novedad_id is null)
     and not exists (select 1 from public.asistencia_alertas x where x.fecha = hoy and x.clave = a.clave and x.ultima > now() - interval '90 minutes');
  if sin is not null then
    perform public.asistencia_avisar('Ensamblador sin OP en mesa', array_to_string(sin, ', ') || (case when array_length(sin, 1) = 1 then ' está' else ' están' end)
      || ' en planta sin una OP en ensamble. Asígnale trabajo o registra su inicio de ensamble.');
    insert into public.asistencia_alertas select hoy, x, now() from unnest(sin) x on conflict (fecha, clave) do update set ultima = now();
    return 'avisados: ' || array_to_string(sin, ', ');
  end if;
  return 'todo en orden';
end; $$;
revoke all on function public.asistencia_revisar() from public, anon, authenticated;

do $$ begin perform cron.unschedule('elp-asistencia-30m'); exception when others then null; end $$;
select cron.schedule('elp-asistencia-30m', '*/30 13-21 * * 1-5', 'select public.asistencia_revisar()');

select 'Listo SQL 93 — asistencia de planta' as r, (select schedule from cron.job where jobname = 'elp-asistencia-30m') horario;
