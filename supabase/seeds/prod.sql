-- Seed de PRODUÇÃO (rodar uma vez após `supabase db push`). Sem segredos: o edge_shared_secret é criado pelo CI a partir de variável.
-- Substituir <ref> e a URL do vídeo antes de executar.
set search_path = public, extensions;

insert into public.app_settings (unit_id, key, value, is_public)
select u.id, 'edge_base_url', to_jsonb('https://<ref>.supabase.co/functions/v1'::text), false
from public.units u where u.slug = 'curitiba'
on conflict (unit_id, key) do update set value = excluded.value;

-- Vídeo 1 (Fase 0 d): bucket público "content"
insert into public.content_assets (unit_id, key, title, media_type, public_url, duration_seconds, source, rights_ok, active)
values (null, 'video_1', 'Primeiros passos da vida com Deus — vídeo 1', 'video', 'https://<ref>.supabase.co/storage/v1/object/public/content/video_1.mp4', null, 'legacy_platform', true, true)
on conflict (unit_id, key) do update set public_url = excluded.public_url, rights_ok = excluded.rights_ok;

-- Status/categoria dos templates espelhados da Graph API (GET /{waba_id}/message_templates) — ajustar após a aprovação
-- update public.message_templates set status = 'approved', category = 'MARKETING', meta_template_id = '<id>' where name = 'transtornar_video1_v1' and unit_id is null;
