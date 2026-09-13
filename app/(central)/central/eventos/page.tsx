import { EventManager, type EventRow } from "@/components/central/event-manager";
import { LiveRefresh } from "@/components/central/live-refresh";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function EventosPage() {
  await requireRole(STAFF_ROLES);
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: events }, { data: nbhs }, { data: thresholds }, { data: totals }] = await Promise.all([
    supabase.from("events").select("*").order("created_at", { ascending: false }),
    supabase
      .from("unit_neighborhoods")
      .select("neighborhoods(id, name)")
      .eq("unit_id", profile?.unit_id ?? ""),
    supabase
      .from("event_thresholds")
      .select("neighborhood_id, target, alert_50_at, alert_80_at, reached_at")
      .not("neighborhood_id", "is", null),
    supabase.from("v_decisions_total_by_neighborhood").select("neighborhood_id, neighborhood, decisions_total"),
  ]);
  const neighborhoods = ((nbhs ?? []) as unknown as { neighborhoods: { id: string; name: string } | null }[])
    .map((r) => r.neighborhoods)
    .filter((n): n is { id: string; name: string } => !!n)
    .sort((a, b) => a.name.localeCompare(b.name, "pt-BR"));
  const totalByNbh = new Map(
    (totals ?? []).map((t) => [t.neighborhood_id, { name: t.neighborhood, total: Number(t.decisions_total ?? 0) }]),
  );

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div>
        <h1 className="text-xl font-bold">Eventos</h1>
        <LiveRefresh tables={["events", "event_invitations"]} />
        <p className="text-sm text-muted-foreground">
          Quando um bairro atinge a meta de decisões, o sistema avisa a liderança e cria o evento em rascunho.
        </p>
      </div>
      {(thresholds ?? []).length ? (
        <section>
          <h2 className="mb-2 font-semibold">Metas por bairro</h2>
          <div className="flex flex-col gap-1 text-sm">
            {(thresholds ?? []).map((t) => {
              const info = totalByNbh.get(t.neighborhood_id as string);
              const pct = Math.min(100, Math.round((100 * (info?.total ?? 0)) / (t.target || 1)));
              return (
                <div key={t.neighborhood_id} className="flex items-center gap-2">
                  <span className="w-40">{info?.name ?? "—"}</span>
                  <div className="h-2 w-40 overflow-hidden rounded-full bg-muted">
                    <div className="h-full bg-primary" style={{ width: `${pct}%` }} />
                  </div>
                  <span className="tabular-nums">
                    {info?.total ?? 0}/{t.target}
                  </span>
                  {t.reached_at ? <span className="text-xs text-emerald-700">meta atingida</span> : null}
                </div>
              );
            })}
          </div>
        </section>
      ) : null}
      <EventManager events={(events ?? []) as unknown as EventRow[]} neighborhoods={neighborhoods} />
    </div>
  );
}
