-- 014 — Desempenho (advisors): auth.uid() dentro de política de RLS é reavaliado linha a linha.
-- Envolvendo em (select auth.uid()) o planejador calcula uma vez (InitPlan). Também cobre com índice
-- as chaves estrangeiras quentes — as que apontam para `people`, usadas na mesclagem e na anonimização.

drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (public.is_unit_staff() and public.can_read_unit(unit_id)) or public.auth_role() = 'global_admin');

drop policy profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()) and role = public.auth_role() and not (unit_id is distinct from public.auth_unit_id()));

drop policy team_members_select on public.team_members;
create policy team_members_select on public.team_members for select to authenticated
  using (profile_id = (select auth.uid()) or public.can_read_unit(unit_id));

drop policy notifications_select on public.notifications;
create policy notifications_select on public.notifications for select to authenticated
  using (recipient_profile_id = (select auth.uid()) or team_id = any (public.auth_team_ids()) or public.can_write_unit(unit_id));

drop policy notifications_update on public.notifications;
create policy notifications_update on public.notifications for update to authenticated
  using (recipient_profile_id = (select auth.uid()) or team_id = any (public.auth_team_ids()) or public.can_write_unit(unit_id));

drop policy follow_ups_select on public.follow_ups;
create policy follow_ups_select on public.follow_ups for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or member_id = (select auth.uid()));

drop policy follow_ups_update on public.follow_ups;
create policy follow_ups_update on public.follow_ups for update to authenticated
  using (public.can_write_unit(unit_id) or member_id = (select auth.uid()));

drop policy delivery_orders_select on public.delivery_orders;
create policy delivery_orders_select on public.delivery_orders for select to authenticated
  using ((public.is_unit_staff() and public.can_read_unit(unit_id)) or driver_id = (select auth.uid()) or exists (
    select 1 from public.team_members tm join public.teams t on t.id = tm.team_id
    where tm.profile_id = (select auth.uid()) and tm.active and t.unit_id = delivery_orders.unit_id
      and t.kind in ('logistics', 'basic_food', 'home_items')));

drop policy volunteer_availability_rw on public.volunteer_availability;
create policy volunteer_availability_rw on public.volunteer_availability for all to authenticated
  using (profile_id = (select auth.uid()) or public.can_write_unit(unit_id))
  with check (profile_id = (select auth.uid()) or public.can_write_unit(unit_id));

-- Índices que faltavam nas FKs para public.people (mesclagem, anonimização e ficha da pessoa)
create index if not exists assistance_programs_person_idx on public.assistance_programs (person_id);
create index if not exists assistance_programs_referral_idx on public.assistance_programs (referral_id);
create index if not exists delivery_orders_person_idx on public.delivery_orders (person_id);
create index if not exists delivery_orders_program_idx on public.delivery_orders (program_id);
create index if not exists delivery_orders_referral_idx on public.delivery_orders (referral_id);
create index if not exists reward_grants_person_idx on public.reward_grants (person_id);
create index if not exists journey_progress_step_idx on public.journey_progress (step_id);
create index if not exists enrollments_person_idx on public.enrollments (person_id);
create index if not exists enrollments_course_idx on public.enrollments (course_id);
create index if not exists job_placements_person_idx on public.job_placements (person_id);
create index if not exists job_placements_opening_idx on public.job_placements (job_opening_id);
create index if not exists church_connections_person_idx on public.church_connections (person_id);
create index if not exists event_invitations_person_idx on public.event_invitations (person_id);
create index if not exists supporters_unit_status_idx on public.supporters (unit_id, status);
create index if not exists benefit_redemptions_benefit_idx on public.benefit_redemptions (benefit_id);
create index if not exists benefits_company_idx on public.benefits (company_id);
create index if not exists job_openings_company_idx on public.job_openings (company_id);
create index if not exists company_contacts_company_idx on public.company_contacts (company_id);
