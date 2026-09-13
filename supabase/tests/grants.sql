-- Execução das funções: o papel `anon` (PostgREST sem sessão) só pode chamar convite e carteirinha.
-- Regressão da 012: funções criadas depois de um `revoke ... from anon` voltavam a ficar públicas.
begin;
select plan(11);

-- anon: nada de PII nem de escrita
select ok(not has_function_privilege('anon', 'public.supporter_candidates(uuid)', 'execute'), 'anon não lista candidatos a mantenedor');
select ok(not has_function_privilege('anon', 'public.event_audience(uuid)', 'execute'), 'anon não lista o público do evento');
select ok(not has_function_privilege('anon', 'public.import_legacy_people(jsonb, text)', 'execute'), 'anon não importa pessoas');
select ok(not has_function_privilege('anon', 'public.create_unit(text, text, text, text, text, text, text, char)', 'execute'), 'anon não cria unidade');
select ok(not has_function_privilege('anon', 'public.event_rsvp(uuid, uuid, text)', 'execute'), 'anon não responde RSVP por outra pessoa');
select ok(not has_function_privilege('anon', 'public.refresh_impact()', 'execute'), 'anon não força refresh do impacto');
select ok(not has_function_privilege('anon', 'public.register_person(jsonb)', 'execute'), 'anon não cadastra pessoa');

-- anon: o que a página pública precisa
select ok(has_function_privilege('anon', 'public.get_invite(text)', 'execute'), 'anon lê o convite pelo código');
select ok(has_function_privilege('anon', 'public.supporter_card(text)', 'execute'), 'anon abre a carteirinha pública');

-- authenticated: o app continua funcionando
select ok(has_function_privilege('authenticated', 'public.register_person(jsonb)', 'execute'), 'app cadastra pessoa');
select ok(not has_function_privilege('authenticated', 'public.advance_journeys()', 'execute'), 'jornada só avança pelo cron/service_role');

select * from finish();
rollback;
