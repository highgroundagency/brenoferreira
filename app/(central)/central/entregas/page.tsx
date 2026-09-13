import { DeliveryList, type DeliveryRow } from "@/components/central/delivery-list";
import { LiveRefresh } from "@/components/central/live-refresh";
import { type Role, STAFF_ROLES } from "@/lib/auth/roles";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

/** Logística: entregas abertas (cesta, itens, prêmios), ordenadas por data; motoristas/times veem as suas pela RLS. */
export default async function EntregasPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: rows }, { data: kpi }] = await Promise.all([
    supabase
      .from("delivery_orders")
      .select(
        "id, person_id, kind, item_code, status, scheduled_for, address_snapshot, people_contacts:people!inner(people_contacts(full_name), neighborhoods(name))",
      )
      .not("status", "in", "(delivered,cancelled)")
      .order("scheduled_for")
      .limit(200),
    supabase.from("v_delivery_kpi").select("*").maybeSingle(),
  ]);
  const list = (
    (rows ?? []) as unknown as (Omit<DeliveryRow, "people_contacts" | "neighborhoods"> & {
      people_contacts: { people_contacts: { full_name: string } | null; neighborhoods: { name: string } | null } | null;
    })[]
  ).map((r) => ({
    ...r,
    people_contacts: r.people_contacts?.people_contacts ?? null,
    neighborhoods: r.people_contacts?.neighborhoods ?? null,
  }));
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-1 text-xl font-bold">Entregas</h1>
      <LiveRefresh tables={["delivery_orders"]} />
      {kpi ? (
        <p className="mb-3 text-xs text-muted-foreground">
          entregues {kpi.delivered} · abertas {kpi.open} · falhas {kpi.failed} · mesmo dia {kpi.same_day_pct ?? 0}% ·
          lead time médio {kpi.avg_lead_hours ?? 0} h
        </p>
      ) : null}
      <DeliveryList rows={list as DeliveryRow[]} canOpenRecord={STAFF_ROLES.includes((profile?.role ?? "") as Role)} />
    </div>
  );
}
