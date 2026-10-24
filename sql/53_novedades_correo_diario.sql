-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Correo diario de novedades a cobros (6:00 p. m.)
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Todos los días a las 6:00 p. m. (hora Colombia) la base llama a la función
--  "resumen_novedades", que envía al correo del usuario de cobros UN correo por
--  obra con el PDF de las novedades del día (fecha, hora, motivo, ítems y fotos).
--  Si un día no hay novedades, no se envía nada. Lo que no se pudo enviar
--  (sin internet, error) sale al día siguiente: nada se pierde.
-- ════════════════════════════════════════════════════════════════
create extension if not exists pg_cron;
alter table public.novedades add column if not exists correo_en timestamptz;

-- Clave interna para que solo la base (o el gerente) pueda disparar el envío
alter table public.push_config add column if not exists cron_token text;
update public.push_config set cron_token = md5(random()::text || clock_timestamp()::text) || md5(random()::text) where id = 1 and cron_token is null;

-- Correo(s) del usuario de cobros (solo los lee la función)
create or replace function public.correos_cobros()
returns setof text language sql stable security definer set search_path = public, auth as $$
  select u.email::text from auth.users u join public.perfiles p on p.id = u.id where p.rol = 'cobros' and u.email is not null;
$$;
revoke all on function public.correos_cobros() from public, anon, authenticated;
grant execute on function public.correos_cobros() to service_role;

-- Disparar el envío (lo usa el reloj de las 6 p. m. y el botón "Enviar a cobros ahora" del gerente)
create or replace function public.novedades_enviar_correo()
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare cfg public.push_config;
begin
  if auth.uid() is not null and not public.es_gerente() then raise exception 'Sin permiso'; end if;
  select * into cfg from public.push_config where id = 1;
  return net.http_post(url := replace(cfg.funcion_url, '/notificar', '/resumen_novedades'), body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'x-elp-token', cfg.cron_token),
    timeout_milliseconds := 120000);
end; $$;
revoke all on function public.novedades_enviar_correo() from public, anon;
grant execute on function public.novedades_enviar_correo() to authenticated;

-- Reloj: todos los días a las 6:00 p. m. de Colombia (23:00 UTC)
do $$ begin perform cron.unschedule('elp-novedades-diario'); exception when others then null; end $$;
select cron.schedule('elp-novedades-diario', '0 23 * * *', 'select public.novedades_enviar_correo()');

select 'Listo ✓ — el correo de novedades sale todos los días a las 6:00 p. m.' as resultado,
       (select string_agg(e, ', ') from public.correos_cobros() e) as se_envia_a;
