-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Unificar nombres de instaladores / ensambladores
--  · Todas las variantes de JOSE DARWIN quedan con la forma más usada.
--  · Todas las variantes de AMIR quedan con la forma más usada.
--  · DIEGO DEVIA (y variantes) queda como DIEGO VIEDA.
--  Aplica a instalador, ensamblador y ensamblador asignado. Lo anterior
--  queda en nombres_unificados. Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create table if not exists public.nombres_unificados (
  antes text primary key, despues text, cuando timestamptz not null default now()
);
alter table public.nombres_unificados enable row level security;

do $$
declare grupo record; canon text; v text;
begin
  for grupo in select * from (values ('JOSE DARWIN', '^JOS[EÉ]\s+DARWIN'), ('AMIR', '^AMIR\M'), ('DIEGO VIEDA', '^DIEGO\s+(VIEDA|DEVIA)')) g(nombre, patron) loop
    -- la forma más usada del grupo (para DIEGO siempre DIEGO VIEDA)
    if grupo.nombre = 'DIEGO VIEDA' then canon := 'DIEGO VIEDA';
    else
      select n into canon from (
        select upper(trim(instalador)) n from public.items where upper(trim(instalador)) ~ grupo.patron
        union all select upper(trim(ensamblador)) from public.items where upper(trim(ensamblador)) ~ grupo.patron
      ) x group by n order by count(*) desc, length(n) desc limit 1;
    end if;
    if canon is null then continue; end if;
    for v in select distinct n from (
        select upper(trim(instalador)) n from public.items where upper(trim(instalador)) ~ grupo.patron
        union select upper(trim(ensamblador)) from public.items where upper(trim(ensamblador)) ~ grupo.patron
        union select upper(trim(ens_asignado)) from public.items where upper(trim(ens_asignado)) ~ grupo.patron
      ) y where n <> canon loop
      insert into public.nombres_unificados (antes, despues) values (v, canon) on conflict (antes) do update set despues = excluded.despues, cuando = now();
    end loop;
    update public.items set instalador = canon where upper(trim(instalador)) ~ grupo.patron and instalador is distinct from canon;
    update public.items set ensamblador = canon where upper(trim(ensamblador)) ~ grupo.patron and ensamblador is distinct from canon;
    update public.items set ens_asignado = canon where upper(trim(ens_asignado)) ~ grupo.patron and ens_asignado is distinct from canon;
  end loop;
end $$;

select antes as nombre_anterior, despues as queda_como from public.nombres_unificados order by despues, antes;
