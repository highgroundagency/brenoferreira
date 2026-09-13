import { SupporterBoard } from "@/components/central/supporter-board";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function MantenedoresPage() {
  await requireRole(STAFF_ROLES);
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: supporters }, { data: candidates }, { data: funnel }, { data: contributions }] = await Promise.all([
    supabase
      .from("supporters")
      .select("*, people(people_contacts(full_name))")
      .order("created_at", { ascending: false }),
    supabase.rpc("supporter_candidates", { p_unit_id: profile?.unit_id ?? "" }),
    supabase.from("v_supporter_funnel").select("*"),
    supabase
      .from("contributions")
      .select("id, amount, paid_on, method, supporter_id")
      .order("paid_on", { ascending: false })
      .limit(50),
  ]);
  const rows = (
    (supporters ?? []) as unknown as (Record<string, unknown> & {
      people: { people_contacts: { full_name: string } | null } | null;
    })[]
  ).map((s) => ({
    ...s,
    name: s.people?.people_contacts?.full_name ?? (s.external_name as string) ?? "—",
  }));
  return (
    <SupporterBoard
      supporters={rows as never}
      candidates={(candidates ?? []) as never}
      funnel={(funnel ?? []) as never}
      contributions={(contributions ?? []) as never}
    />
  );
}
