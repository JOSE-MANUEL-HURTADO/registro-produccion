-- ════════════════════════════════════════════════════════════════
--  ASISTENCIA · Novedad "Cargue de camión" (ensambladores u operarios de proceso que cargan el camión)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  · Fila tipo 'cargue': clave = 'PERSONA|OBRA', horas = horas de cargue, motivo = obra.
--  · Mientras dure el cargue no se avisa "ensamblador sin OP en mesa".
--  · El costo de mano de obra carga esas horas a la obra del camión.
-- ════════════════════════════════════════════════════════════════
alter table public.asistencia add column if not exists horas numeric;
alter table public.asistencia drop constraint if exists asistencia_tipo_chk;
alter table public.asistencia add constraint asistencia_tipo_chk check (tipo in ('ensamble', 'proceso', 'cargue'));
alter table public.asistencia drop constraint if exists asistencia_estado_chk;
alter table public.asistencia add constraint asistencia_estado_chk check (estado in ('planta', 'obra', 'ausente', 'activo', 'sin_operario', 'cargue'));

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
     and not exists (select 1 from public.asistencia_alertas x where x.fecha = hoy and x.clave = a.clave and x.ultima > now() - interval '90 minutes')
     -- cargando el camión: no se avisa mientras dure el cargue registrado
     and not exists (select 1 from public.asistencia c where c.fecha = hoy and c.tipo = 'cargue' and upper(btrim(split_part(c.clave, '|', 1))) = upper(btrim(a.clave))
                       and c.actualizada + make_interval(mins => (coalesce(c.horas, 1) * 60)::int) > now());
  if sin is not null then
    perform public.asistencia_avisar('Ensamblador sin OP en mesa', array_to_string(sin, ', ') || (case when array_length(sin, 1) = 1 then ' está' else ' están' end)
      || ' en planta sin una OP en ensamble. Asígnale trabajo o registra su inicio de ensamble.');
    insert into public.asistencia_alertas select hoy, x, now() from unnest(sin) x on conflict (fecha, clave) do update set ultima = now();
    return 'avisados: ' || array_to_string(sin, ', ');
  end if;
  return 'todo en orden';
end; $$;
revoke all on function public.asistencia_revisar() from public, anon, authenticated;

select 'Listo SQL 95 — cargue de camión' as r;
