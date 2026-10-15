-- ════════════════════════════════════════════════════════════════
--  ELÍPTICA · Órdenes de producción en PDF
--  Pegar completo en Supabase → SQL Editor → New query → Run
--  Se puede correr más de una vez sin problema.
-- ════════════════════════════════════════════════════════════════
--  Carpeta privada "ordenes": un PDF por número de OP (ops/6235.pdf)
--  · Todos los usuarios con rol pueden abrirlos
--  · Solo el gerente puede subirlos, reemplazarlos o borrarlos
-- ════════════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ordenes', 'ordenes', false, 52428800, array['application/pdf'])
on conflict (id) do update set public = false, file_size_limit = 52428800, allowed_mime_types = array['application/pdf'];

drop policy if exists ordenes_ver on storage.objects;
create policy ordenes_ver on storage.objects for select to authenticated
  using (bucket_id = 'ordenes' and public.rol_actual() is not null);

drop policy if exists ordenes_subir on storage.objects;
create policy ordenes_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'ordenes' and public.es_gerente());

drop policy if exists ordenes_reemplazar on storage.objects;
create policy ordenes_reemplazar on storage.objects for update to authenticated
  using (bucket_id = 'ordenes' and public.es_gerente()) with check (bucket_id = 'ordenes' and public.es_gerente());

drop policy if exists ordenes_borrar on storage.objects;
create policy ordenes_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'ordenes' and public.es_gerente());

select 'Listo ✓' as resultado;
