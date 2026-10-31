-- ════════════════════════════════════════════════════════════════
--  COTIZADOR · base migrada de OCOBO (diseños, fórmulas, referencias con precio, histórico de cotizaciones y OP)
--  Pegar completo en Supabase → SQL Editor → New query → Run. Se puede correr más de una vez.
--  Los datos se cargan desde la app (Cotizador → Importar OCOBO) con los archivos JSON exportados del volcado.
--  Solo el director (y luego el rol "cotizaciones") ven estas tablas: aquí hay precios y fórmulas de la empresa.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.cot_concepto (   -- nombres de los parámetros/variables (C405 = Ancho 1, 16301 = Costos…)
  id int primary key, nombre text not null
);
create table if not exists public.cot_referencia ( -- perfiles, accesorios y vidrios con su precio
  id bigint primary key,
  descripcion text not null,
  unidad int not null default 22902,             -- 22921 lineal (mm) · 22902 unidad · 22922/22923 área (mm²) · 22999 sin uso
  desperdicio numeric not null default 0,        -- mm que se suman a cada corte (perfiles) o a cada tramo
  equivalencia numeric not null default 1,       -- cuántas unidades de medida trae el precio (1000 = precio por metro; 1e6 = por m²)
  valor numeric not null default 0,              -- precio por "equivalencia" (sin IVA)
  unitario numeric not null default 0,           -- precio por unidad de medida (valor / equivalencia)
  categoria int, categoria_nombre text,          -- 16050 perfil · 16051 accesorio ensamble · 16054 vidrio · 16055 longitud…
  proveedor_id bigint, estado int,
  activo boolean not null default true,
  actualizado timestamptz not null default now()
);
create table if not exists public.cot_diseno (     -- "clase" de OCOBO: un diseño parametrizado
  id int primary key,
  nombre text not null,
  sistema text, tipologia text, observacion text,
  params jsonb not null default '[]'::jsonb,     -- [{c:405, def:0}, …] parámetros que pide el diseño, en orden
  usado int not null default 0, ultimo_uso date,
  activo boolean not null default true,
  origen text not null default 'ocobo',
  creado timestamptz not null default now(), actualizado timestamptz not null default now()
);
create table if not exists public.cot_formula (    -- renglones de la fórmula de cada diseño
  diseno int not null references public.cot_diseno(id) on delete cascade,
  orden int not null,
  concepto int not null,                         -- perfil (código corto × 100 + acabado), accesorio (referencia) o 6 = vidrio
  expr text not null default '',                 -- largo / medida: C405-25 · SI[C505]=[4][…][-1] · ?[C509]C405+3 · ¿[C502][2][ancho][alto]
  cantidad text not null default '1',            -- número o expresión (1*C404)
  corte text not null default '',                -- tipo de corte
  primary key (diseno, orden)
);
create table if not exists public.cot_opcion (     -- etiquetas de los valores de los parámetros de selección (acabado 3 = Pin. Negra H3…)
  concepto int not null, valor numeric not null, etiqueta text not null, usos int not null default 0,
  primary key (concepto, valor)
);
create table if not exists public.cot_documento (  -- histórico de OCOBO (solo lectura) y futuras cotizaciones de la app
  interno bigint primary key,
  tipo text not null check (tipo in ('cotizacion', 'op')),
  numero int not null, fecha date, obra text, cliente_id bigint, cliente text, usuario text, estado int,
  procedencia bigint, observacion text,
  origen text not null default 'ocobo',
  creado timestamptz not null default now()
);
create table if not exists public.cot_item (
  interno bigint not null references public.cot_documento(interno) on delete cascade,
  item int not null,
  descripcion text, diseno int, nomenclatura text, cantidad int not null default 1, estado int,
  params jsonb not null default '{}'::jsonb,     -- {"405": 1507, "408": 1247, "501": 3, …}
  comercial jsonb not null default '{}'::jsonb,  -- {"301": 10, "302": 61500, "303": 65, "304": 19, "312": 10, "313": 4, "314": 6, "316": 19, …}
  primary key (interno, item)
);
create table if not exists public.cot_despiece (   -- despiece calculado (OCOBO) por ítem: [orden, concepto, referencia, corte, dimX, dimY, cant, unitario, valor, medX, medY]
  interno bigint not null, item int not null, filas jsonb not null default '[]'::jsonb,
  primary key (interno, item)
);
create index if not exists cot_item_diseno_idx on public.cot_item (diseno);
create index if not exists cot_documento_tipo_fecha_idx on public.cot_documento (tipo, fecha desc);
create index if not exists cot_diseno_nombre_idx on public.cot_diseno using gin (to_tsvector('simple', nombre));

-- Permisos: director y rol "cotizaciones" (se crea aquí para los cotizadores y dibujo) ven y editan; nadie más.
create or replace function public.es_cotizador() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.perfiles where id = auth.uid() and rol in ('gerente', 'cotizaciones'));
$$;
grant execute on function public.es_cotizador() to authenticated;
do $$ declare t text; begin
  foreach t in array array['cot_concepto', 'cot_referencia', 'cot_diseno', 'cot_formula', 'cot_opcion', 'cot_documento', 'cot_item', 'cot_despiece'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_cot', t);
    execute format('create policy %I on public.%I for all to authenticated using ((select public.es_cotizador())) with check ((select public.es_cotizador()))', t || '_cot', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
  end loop;
end $$;
-- El rol "cotizaciones" en perfiles (si la restricción de roles existe, se amplía)
do $$ declare c text; begin
  select pg_get_constraintdef(oid) into c from pg_constraint where conrelid = 'public.perfiles'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%rol%';
  if c is not null and c not like '%cotizaciones%' then
    execute 'alter table public.perfiles drop constraint ' || (select conname from pg_constraint where conrelid = 'public.perfiles'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%rol%' limit 1);
    execute 'alter table public.perfiles add constraint perfiles_rol_check check (rol in (''gerente'',''asistente'',''consulta'',''cobros'',''conductor'',''entrega'',''recibe'',''planta'',''instalador'',''artica'',''artica_ops'',''artica_gerente'',''cotizaciones''))';
  end if;
exception when others then raise notice 'perfiles.rol: %', sqlerrm; end $$;
select 'Listo SQL 115 — cotizador (base OCOBO)' as r;
