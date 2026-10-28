-- ════════════════════════════════════════════════════════════════
--  ÁRTICA · El nombre de la obra es el mismo de Elíptica
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  El vidrio de una OP toma el nombre de obra que tiene esa OP en Elíptica (aunque la
--  orden PDF diga otro nombre). Si la OP aún no está en Elíptica, se usa el alias guardado
--  (obras_alias). Si en Elíptica se cambia el nombre de la obra, Ártica cambia también.
--  Las OP de clientes (solo vidrio) conservan el nombre de la orden.
-- ════════════════════════════════════════════════════════════════
create or replace function public.art_obra_eliptica()
returns trigger language plpgsql security definer set search_path = public as $$
declare o text;
begin
  if coalesce(new.tercero, false) then return new; end if;
  select i.obra into o from public.items i where i.op = new.op and i.obra is not null group by i.obra order by count(*) desc limit 1;
  if o is null and new.obra is not null then select a.obra into o from public.obras_alias a where a.alias = new.obra; end if;
  if o is not null then new.obra := o; end if;
  return new;
end; $$;
drop trigger if exists trg_art_obra_eliptica on public.art_piezas;
create trigger trg_art_obra_eliptica before insert or update of obra, op on public.art_piezas for each row execute function public.art_obra_eliptica();

-- Cuando en Elíptica se cargan ítems o se cambia el nombre de la obra
create or replace function public.art_obra_desde_items()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.art_piezas p set obra = n.obra
    from (select distinct on (op) op, obra from nuevos where op is not null and obra is not null order by op) n
   where p.op = n.op and not p.tercero and p.obra is distinct from n.obra;
  return null;
end; $$;
drop trigger if exists trg_art_obra_ins on public.items;
create trigger trg_art_obra_ins after insert on public.items referencing new table as nuevos for each statement execute function public.art_obra_desde_items();
drop trigger if exists trg_art_obra_upd on public.items;
create trigger trg_art_obra_upd after update on public.items referencing new table as nuevos for each statement execute function public.art_obra_desde_items();

-- Corregir lo que ya está cargado
update public.art_piezas p set obra = x.obra
  from (select op, (array_agg(obra order by n desc))[1] obra from (select op, obra, count(*) n from public.items where op is not null and obra is not null group by op, obra) z group by op) x
 where p.op = x.op and not p.tercero and p.obra is distinct from x.obra;

select 'Listo SQL 71' as resultado,
       (select count(distinct obra) from public.art_piezas where not tercero) as obras_artica,
       (select count(*) from public.art_piezas p where not p.tercero and not exists (select 1 from public.items i where i.op = p.op and i.obra = p.obra)) as sin_par_en_eliptica;
