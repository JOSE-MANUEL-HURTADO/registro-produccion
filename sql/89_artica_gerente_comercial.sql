-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · Rol "artica_gerente" (Gerente comercial de Ártica)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Tiene acceso a TODO Ártica (avance, estaciones, OPTIMA y etiquetas, cotizaciones, operarios,
--  escanear en cualquier estación, cargar OP de clientes, rutas y reprocesos), igual que el director
--  dentro de Ártica. No ve Elíptica.
-- ════════════════════════════════════════════════════════════════

-- 1. Rol nuevo
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check
  check (rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador','artica','artica_ops','artica_gerente'));

create or replace function public.asignar_rol(p_id uuid, p_rol text, p_nombre text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_gerente() then raise exception 'Sin permiso'; end if;
  if p_id = auth.uid() then raise exception 'No puedes cambiar tu propio rol'; end if;
  if p_rol is null or p_rol = '' then
    delete from public.perfiles where id = p_id;
  elsif p_rol in ('gerente','asistente','consulta','cobros','conductor','entrega','recibe','planta','instalador','artica','artica_ops','artica_gerente') then
    insert into public.perfiles (id, nombre, rol) values (p_id, nullif(trim(p_nombre),''), p_rol)
    on conflict (id) do update set rol = excluded.rol, nombre = coalesce(excluded.nombre, public.perfiles.nombre);
  else
    raise exception 'Rol no válido';
  end if;
end; $$;

-- 2. Administrador de Ártica = director o gerente comercial de Ártica
create or replace function public.art_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.es_gerente(), false) or coalesce(public.rol_actual() = 'artica_gerente', false);
$$;
grant execute on function public.art_admin() to authenticated;

-- 3. Las funciones de Ártica que eran solo del director pasan a art_admin()
do $$
declare f record; def text;
begin
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('art_orden_corte','art_operarios','art_ruta_set','art_estaciones_usuario','art_optima_lote',
              'art_optima_marcar','art_reprocesar','art_optima_devolver','art_cargar','art_cargar_op')
  loop
    def := pg_get_functiondef(f.oid);
    if def ~ 'es_gerente\(\)' then
      execute regexp_replace(def, '(public\.)?es_gerente\(\)', 'public.art_admin()', 'g');
    end if;
  end loop;
  -- Lectura, búsqueda y escaneo en todas las estaciones
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('art_lee','art_buscar','art_escanea_todo')
  loop
    def := pg_get_functiondef(f.oid);
    if position('artica_gerente' in def) = 0 then
      execute replace(def, '''gerente''', '''gerente'',''artica_gerente''');
    end if;
  end loop;
end $$;

-- 4. Cotizaciones y prefijos
create or replace function public.art_cotiza()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.art_admin(), false) or coalesce(public.art_solo_clientes(), false);
$$;
drop policy if exists art_prefijos_gerente on public.art_prefijos;
create policy art_prefijos_gerente on public.art_prefijos for all to authenticated
  using ((select public.art_admin())) with check ((select public.art_admin()));

select 'Listo SQL 89 — gerente comercial de Ártica' as r,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prosrc like '%art_admin()%') funciones,
  (select count(*) from pg_proc where proname in ('art_lee','art_buscar','art_escanea_todo') and prosrc like '%artica_gerente%') lectura;
