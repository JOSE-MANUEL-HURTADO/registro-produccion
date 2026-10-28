-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Correo de faltantes con copia al director de operaciones
--  y envío de los faltantes abiertos que ya estaban registrados
-- ════════════════════════════════════════════════════════════════
alter table public.push_config add column if not exists correos_faltantes_cc text;
update public.push_config set correos_faltantes_cc = 'subgerencia@eliptica.com.co' where id = 1;

-- Los faltantes abiertos (sin resolver) se vuelven a poner en cola y se envían ya
update public.faltantes set correo_en = null where resuelta is null;
select net.http_post(url := replace(funcion_url, '/notificar', '/resumen_novedades'), body := '{"tipo":"faltante"}'::jsonb,
  headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || anon_key, 'x-elp-token', cron_token),
  timeout_milliseconds := 60000) as solicitud
  from public.push_config where id = 1;
