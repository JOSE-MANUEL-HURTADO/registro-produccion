-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Correo inmediato de faltantes de material en corte
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Cada vez que se registra un faltante en corte, la base llama a la función "resumen_novedades"
--  (la misma que envía las novedades a cobros, con la cuenta de Gmail configurada) y sale un
--  correo a compras e inventario con obra, OP, unidades afectadas, perfil, cantidad y medida.
--  Lo que no se pudo enviar (sin internet, error) se reintenta en el siguiente envío.
--  Destinatarios: push_config.correos_faltantes (separados por coma).
-- ════════════════════════════════════════════════════════════════
alter table public.faltantes add column if not exists correo_en timestamptz;
alter table public.push_config add column if not exists correos_faltantes text;
update public.push_config set correos_faltantes = 'compras@eliptica.com.co, inventario.eliptica@gmail.com' where id = 1;
-- Los faltantes que ya estaban registrados no se envían (solo los nuevos desde hoy)
update public.faltantes set correo_en = now() where correo_en is null;

create or replace function public.faltante_correo()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare cfg public.push_config; v_ids bigint[];
begin
  select array_agg(id) into v_ids from nuevos;
  select * into cfg from public.push_config where id = 1;
  if cfg.funcion_url is null or coalesce(cfg.correos_faltantes, '') = '' then return null; end if;
  perform net.http_post(url := replace(cfg.funcion_url, '/notificar', '/resumen_novedades'),
    body := jsonb_build_object('tipo', 'faltante', 'ids', to_jsonb(v_ids)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || cfg.anon_key, 'x-elp-token', cfg.cron_token),
    timeout_milliseconds := 60000);
  return null;
exception when others then
  raise warning 'correo de faltante no enviado: %', sqlerrm;   -- nunca bloquea el registro
  return null;
end; $$;
drop trigger if exists trg_faltante_correo on public.faltantes;
create trigger trg_faltante_correo after insert on public.faltantes referencing new table as nuevos
  for each statement execute function public.faltante_correo();

select 'Listo SQL 81 — correo de faltantes' as r, (select correos_faltantes from public.push_config where id = 1) destinatarios,
       (select funcion_url is not null and cron_token is not null from public.push_config where id = 1) config_ok;
