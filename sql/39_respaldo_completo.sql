-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Copia de seguridad COMPLETA (todas las tablas + PDF de OP)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  La copia diaria del Mac solo bajaba la base de ítems. Con esto baja
--  además todas las tablas (órdenes de despacho, programaciones, actas
--  con firmas, remisiones, historial, personas, usuarios…) y los PDF.
--  · Solo el gerente y el usuario de respaldo (rol consulta) pueden usarlo.
--  · Las tablas nuevas que se creen después entran solas en la copia.
--  · No cambia ni borra nada: solo lee.
-- ════════════════════════════════════════════════════════════════

-- 1. Lista de tablas de la base (todas las de "public")
create or replace function public.respaldo_tablas()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if coalesce(public.rol_actual() in ('gerente','consulta'), false) is not true then
    raise exception 'Sin permiso';
  end if;
  return (select coalesce(jsonb_agg(c.relname::text order by c.relname), '[]'::jsonb)
            from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r','p'));
end;
$$;

-- 2. Filas de una tabla, de a bloques (ordenadas por su llave para no repetir ni saltar filas)
create or replace function public.respaldo_tabla(p_tabla text, p_desde integer default 0, p_limite integer default 1000)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_rel   regclass;
  v_orden text;
  v_res   jsonb;
begin
  if coalesce(public.rol_actual() in ('gerente','consulta'), false) is not true then
    raise exception 'Sin permiso';
  end if;
  select c.oid::regclass into v_rel
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p') and c.relname = p_tabla;
  if v_rel is null then raise exception 'Tabla no válida: %', p_tabla; end if;

  select string_agg(format('t.%I', a.attname), ', ' order by array_position(i.indkey::int2[], a.attnum))
    into v_orden
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey::int2[])
   where i.indrelid = v_rel and i.indisprimary;
  if v_orden is null then v_orden := 't::text'; end if;   -- tabla sin llave: orden por toda la fila

  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from %s t order by %s offset $1 limit $2) t',
                 v_rel, v_orden)
     into v_res
    using greatest(coalesce(p_desde, 0), 0), least(greatest(coalesce(p_limite, 1000), 1), 2000);
  return v_res;
end;
$$;

-- 3. Lista de los PDF de OP guardados en la app (para bajar solo los nuevos o cambiados)
create or replace function public.respaldo_pdfs()
returns jsonb language plpgsql stable security definer set search_path = public, storage as $$
begin
  if coalesce(public.rol_actual() in ('gerente','consulta'), false) is not true then
    raise exception 'Sin permiso';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
                    'name', o.name,
                    'size', coalesce((o.metadata->>'size')::bigint, 0),
                    'updated_at', coalesce(o.updated_at, o.created_at)) order by o.name), '[]'::jsonb)
            from storage.objects o
           where o.bucket_id = 'ordenes' and o.name not like '%/.emptyFolderPlaceholder');
end;
$$;

revoke all on function public.respaldo_tablas() from public, anon;
revoke all on function public.respaldo_tabla(text, integer, integer) from public, anon;
revoke all on function public.respaldo_pdfs() from public, anon;
grant execute on function public.respaldo_tablas() to authenticated;
grant execute on function public.respaldo_tabla(text, integer, integer) to authenticated;
grant execute on function public.respaldo_pdfs() to authenticated;

-- Resumen: qué tablas entran en la copia y cuántas filas tiene cada una
select c.relname as tabla, greatest(c.reltuples, 0)::bigint as filas_aprox
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r','p')
 order by 1;
