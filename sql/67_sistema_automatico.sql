-- ════════════════════════════════════════════════════════════════
--  SISTEMA AUTOMÁTICO AL CARGAR OP
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  La OP en PDF trae el diseño (ej. "ELI.053/028/207 -XO//O") pero no el sistema
--  (ELIPSE). Al guardar un ítem sin sistema, la base lo deduce de lo ya registrado:
--    1. el mismo diseño exacto,
--    2. el mismo diseño sin la configuración (-XO, -O…),
--    3. la misma familia (las letras iniciales: ELI., GAL., LATI., FER., ACUA…).
--  Toma el sistema más usado. Se corrigen también los ítems que hoy no tienen sistema.
-- ════════════════════════════════════════════════════════════════
create index if not exists items_diseno_idx on public.items (upper(diseno));

create or replace function public.sistema_inferido(p_diseno text)
returns text language sql stable security definer set search_path = public as $$
  with d as (
    select upper(btrim(p_diseno)) full_d,
           upper(btrim(regexp_replace(p_diseno, '\s*-\s*[XOPER/\s]+$', '', 'i'))) base_d,
           upper(substring(btrim(p_diseno) from '^[A-Za-zÁÉÍÓÚÑáéíóúñ]+')) fam
  ), c as (
    select 1 nivel, i.sistema from public.items i, d where i.sistema is not null and i.sistema <> '' and upper(btrim(i.diseno)) = d.full_d
    union all
    select 2, i.sistema from public.items i, d where i.sistema is not null and i.sistema <> '' and d.base_d <> '' and upper(btrim(i.diseno)) like d.base_d || '%'
    union all
    select 3, i.sistema from public.items i, d where i.sistema is not null and i.sistema <> '' and length(d.fam) >= 2
       and upper(i.diseno) ~ ('^' || d.fam || '([^A-ZÁÉÍÓÚÑ]|$)')
  )
  select sistema from c where p_diseno is not null and btrim(p_diseno) <> ''
   group by nivel, sistema order by nivel, count(*) desc, sistema limit 1;
$$;

create or replace function public.items_sistema_auto()
returns trigger language plpgsql as $$
begin
  if (new.sistema is null or btrim(new.sistema) = '') and new.diseno is not null then
    new.sistema := public.sistema_inferido(new.diseno);
  end if;
  return new;
end; $$;
drop trigger if exists trg_items_sistema on public.items;
create trigger trg_items_sistema before insert or update of diseno, sistema on public.items
  for each row execute function public.items_sistema_auto();

-- Los que hoy no tienen sistema
do $x$ begin
  perform set_config('elp.swap', '1', true);
  update public.items i set sistema = s.sis
    from (select id, public.sistema_inferido(diseno) sis from public.items where (sistema is null or sistema = '') and diseno is not null) s
   where s.id = i.id and s.sis is not null;
  perform set_config('elp.swap', '', true);
end $x$;

select 'Listo SQL 67' as resultado,
       (select count(*) from public.items where sistema is null or sistema = '') as siguen_sin_sistema,
       (select string_agg(distinct op || ' ' || coalesce(sistema, '?'), ', ') from public.items where op like '6300-%') as op_6300;
