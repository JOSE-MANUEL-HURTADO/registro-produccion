-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Faltantes de material: UN correo cada 2 horas
--  Pegar completo en Supabase → SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════
--  Ya no sale un correo por cada faltante. Cada 2 horas, si hay faltantes nuevos, sale UN solo
--  correo a compras e inventario (copia al director) con todos los nuevos, por obra y OP, y al final
--  los que siguen abiertos de reportes anteriores.
-- ════════════════════════════════════════════════════════════════
drop trigger if exists trg_faltante_correo on public.faltantes;

create or replace function public.faltantes_enviar_correo()
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare cfg public.push_config;
begin
  select * into cfg from public.push_config where id = 1;
  if cfg.funcion_url is null then return null; end if;
  if not exists (select 1 from public.faltantes where correo_en is null and creada > now() - interval '7 days') then return null; end if;
  return net.http_post(url := replace(cfg.funcion_url, '/notificar', '/resumen_novedades'), body := '{"tipo":"faltante"}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'x-elp-token', cfg.cron_token),
    timeout_milliseconds := 60000);
end; $$;
revoke all on function public.faltantes_enviar_correo() from public, anon, authenticated;

do $$ begin perform cron.unschedule('elp-faltantes-2h'); exception when others then null; end $$;
select cron.schedule('elp-faltantes-2h', '0 */2 * * *', 'select public.faltantes_enviar_correo()');

select 'Listo SQL 83 — faltantes cada 2 horas' as r, (select schedule from cron.job where jobname = 'elp-faltantes-2h') horario;
