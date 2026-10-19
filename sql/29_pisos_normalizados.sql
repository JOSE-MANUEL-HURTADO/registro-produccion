-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Piso siempre como "PISO N"
--  En algunas obras (p. ej. La Cité) el piso quedó como P1, P2, p 3, P.4,
--  PISO1, PISO 01 o solo el número. Todo queda como "PISO 1", "PISO 2"…
--  1) Corrige lo que ya está en la base (queda guardado en pisos_corregidos).
--  2) De aquí en adelante la base lo corrige sola al cargar o editar.
--  Se puede correr más de una vez.
-- ════════════════════════════════════════════════════════════════
create or replace function public.piso_normal(p text) returns text language sql immutable as $$
  select case
    when p ~* '^\s*(p|piso|pis)\s*[\.\-#°º]?\s*\d+\s*$' then 'PISO ' || (regexp_replace(p, '\D', '', 'g'))::int
    when p ~ '^\s*\d{1,3}\s*$' then 'PISO ' || trim(p)::int
    else p end
$$;

create table if not exists public.pisos_corregidos (
  item_id bigint primary key, obra text, piso_antes text, piso_nuevo text,
  cuando timestamptz not null default now()
);
alter table public.pisos_corregidos enable row level security;

do $$
begin
  perform set_config('elp.swap', '1', true);   -- permite cambiar el piso (ver SQL 24)
  insert into public.pisos_corregidos (item_id, obra, piso_antes, piso_nuevo)
    select id, obra, piso, public.piso_normal(piso) from public.items
    where piso is not null and public.piso_normal(piso) is distinct from piso
  on conflict (item_id) do nothing;
  update public.items set piso = public.piso_normal(piso)
    where piso is not null and public.piso_normal(piso) is distinct from piso;
  perform set_config('elp.swap', '', true);
end $$;

-- De aquí en adelante (corre después del candado de proteger_items, por el nombre)
create or replace function public.normalizar_piso() returns trigger language plpgsql as $$
begin
  if new.piso is not null then new.piso := public.piso_normal(new.piso); end if;
  return new;
end; $$;
drop trigger if exists trg_zz_normalizar_piso on public.items;
create trigger trg_zz_normalizar_piso before insert or update of piso on public.items
  for each row execute function public.normalizar_piso();

-- Resumen por obra
select obra, piso_antes, piso_nuevo, count(*) as items
from public.pisos_corregidos group by 1, 2, 3 order by 1, 3;
