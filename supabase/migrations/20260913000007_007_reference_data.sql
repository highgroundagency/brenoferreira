-- 007 — dados de referência (idempotente). Aplicada na Fase 1 com o que existe até a 002;
-- o seed de routing_rules fica no fim da 004 e o de templates/conteúdo em supabase/seeds/prod.sql.

-- Unidade piloto
insert into public.units (slug, name)
values ('curitiba', 'Transtornar Curitiba')
on conflict (slug) do nothing;

-- Curitiba/PR (IBGE 4106902)
insert into public.cities (name, state, country_code, ibge_code)
values ('Curitiba', 'PR', 'BR', '4106902')
on conflict (ibge_code) do nothing;

-- 75 bairros oficiais (IPPUC). region (regional administrativa) pode ser preenchida depois via admin/global.
with c as (select id from public.cities where ibge_code = '4106902'),
     b (name, aliases) as (
  values
    ('Abranches', '{}'::text[]),
    ('Água Verde', array['agua verde']::text[]),
    ('Ahú', '{}'::text[]),
    ('Alto Boqueirão', '{}'::text[]),
    ('Alto da Glória', '{}'::text[]),
    ('Alto da Rua XV', array['alto da xv','alto da rua 15']::text[]),
    ('Atuba', '{}'::text[]),
    ('Augusta', '{}'::text[]),
    ('Bacacheri', '{}'::text[]),
    ('Bairro Alto', '{}'::text[]),
    ('Barreirinha', '{}'::text[]),
    ('Batel', '{}'::text[]),
    ('Bigorrilho', array['champagnat']::text[]),
    ('Boa Vista', '{}'::text[]),
    ('Bom Retiro', '{}'::text[]),
    ('Boqueirão', '{}'::text[]),
    ('Butiatuvinha', '{}'::text[]),
    ('Cabral', '{}'::text[]),
    ('Cachoeira', '{}'::text[]),
    ('Cajuru', '{}'::text[]),
    ('Campina do Siqueira', '{}'::text[]),
    ('Campo Comprido', '{}'::text[]),
    ('Campo de Santana', '{}'::text[]),
    ('Capão da Imbuia', '{}'::text[]),
    ('Capão Raso', '{}'::text[]),
    ('Cascatinha', '{}'::text[]),
    ('Caximba', '{}'::text[]),
    ('Centro', '{}'::text[]),
    ('Centro Cívico', array['centro civico']::text[]),
    ('Cidade Industrial de Curitiba', array['cic','cidade industrial']::text[]),
    ('Cristo Rei', '{}'::text[]),
    ('Fanny', '{}'::text[]),
    ('Fazendinha', '{}'::text[]),
    ('Ganchinho', '{}'::text[]),
    ('Guabirotuba', '{}'::text[]),
    ('Guaíra', '{}'::text[]),
    ('Hauer', '{}'::text[]),
    ('Hugo Lange', '{}'::text[]),
    ('Jardim Botânico', '{}'::text[]),
    ('Jardim das Américas', array['jardim das americas']::text[]),
    ('Jardim Social', '{}'::text[]),
    ('Juvevê', '{}'::text[]),
    ('Lamenha Pequena', '{}'::text[]),
    ('Lindóia', '{}'::text[]),
    ('Mercês', '{}'::text[]),
    ('Mossunguê', '{}'::text[]),
    ('Novo Mundo', '{}'::text[]),
    ('Orleans', '{}'::text[]),
    ('Parolin', '{}'::text[]),
    ('Pilarzinho', '{}'::text[]),
    ('Pinheirinho', '{}'::text[]),
    ('Portão', '{}'::text[]),
    ('Prado Velho', '{}'::text[]),
    ('Rebouças', '{}'::text[]),
    ('Riviera', '{}'::text[]),
    ('Santa Cândida', '{}'::text[]),
    ('Santa Felicidade', '{}'::text[]),
    ('Santa Quitéria', '{}'::text[]),
    ('Santo Inácio', '{}'::text[]),
    ('São Braz', array['sao bras','são brás']::text[]),
    ('São Francisco', '{}'::text[]),
    ('São João', '{}'::text[]),
    ('São Lourenço', '{}'::text[]),
    ('São Miguel', '{}'::text[]),
    ('Seminário', '{}'::text[]),
    ('Sítio Cercado', array['sitio cercado']::text[]),
    ('Taboão', '{}'::text[]),
    ('Tarumã', '{}'::text[]),
    ('Tatuquara', '{}'::text[]),
    ('Tingui', '{}'::text[]),
    ('Uberaba', '{}'::text[]),
    ('Umbará', '{}'::text[]),
    ('Vila Izabel', '{}'::text[]),
    ('Vista Alegre', '{}'::text[]),
    ('Xaxim', array['chaxim','chachim']::text[])
)
insert into public.neighborhoods (city_id, name, normalized_name, aliases)
select c.id, b.name, public.normalize_text(b.name), b.aliases from b, c
on conflict (city_id, normalized_name) do nothing;

-- Cobertura da unidade curitiba = todos os bairros de Curitiba
insert into public.unit_neighborhoods (unit_id, neighborhood_id)
select u.id, n.id
from public.units u, public.neighborhoods n
join public.cities c on c.id = n.city_id
where u.slug = 'curitiba' and c.ibge_code = '4106902'
on conflict do nothing;

-- Times da unidade (modo central única no MVP: central, basic_food, follow_up e strategy ativos)
insert into public.teams (unit_id, kind, name, active, fallback_to_central)
select u.id, t.kind, t.name, t.active, true
from public.units u,
     (values
        ('central', 'Central', true),
        ('basic_food', 'Cesta básica', true),
        ('follow_up', 'Acompanhamento', true),
        ('strategy', 'Estratégia', true),
        ('home_items', 'Itens de casa', false),
        ('education', 'Educação', false),
        ('employment', 'Trabalho', false),
        ('logistics', 'Logística', false)
     ) as t(kind, name, active)
where u.slug = 'curitiba'
on conflict (unit_id, kind) do nothing;

-- Texto de consentimento vigente (público: lido pelo app do evangelista)
insert into public.app_settings (unit_id, key, value, is_public)
select u.id, 'consent_text_v1', jsonb_build_object(
  'version', 'v1',
  'base', 'O Transtornar vai guardar seu nome, telefone, endereço e sua decisão por Jesus para te acompanhar. Vamos falar com você pelo WhatsApp. Você pode pedir para parar ou apagar seus dados a qualquer momento respondendo SAIR ou MEUS DADOS.',
  'social_assistance', 'Seus dados também vão para a equipe que cuida de cesta básica e itens de casa.',
  'terms_url', '/termos'
), true
from public.units u where u.slug = 'curitiba'
on conflict (unit_id, key) do nothing;
