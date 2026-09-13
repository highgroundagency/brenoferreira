-- 013 — mv_impact sai do schema exposto pela API. A 012 tinha resolvido a exposição tornando as visões
-- "security definer", o que o linter (com razão) marca como ERROR. O jeito certo: a matriz fica em `private`
-- (schema fora do PostgREST) e as visões voltam a rodar com os direitos de quem consulta, filtrando por unidade.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

alter materialized view public.mv_impact set schema private;
revoke all on private.mv_impact from public, anon;
grant select on private.mv_impact to authenticated, service_role;

alter view public.v_impact_by_unit set (security_invoker = true);
alter view public.v_units_comparison set (security_invoker = true);

create or replace function public.refresh_impact() returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.auth_role() is not null and public.auth_role() not in ('central', 'unit_admin', 'global_admin') then
    raise insufficient_privilege using message = 'papel não autorizado para esta operação';
  end if;
  refresh materialized view concurrently private.mv_impact;
end $$;
revoke execute on function public.refresh_impact() from public, anon;
grant execute on function public.refresh_impact() to authenticated, service_role;
