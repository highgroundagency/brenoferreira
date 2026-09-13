import { NextResponse } from "next/server";
import { createClient, getProfile } from "@/lib/supabase/server";

/** CSV para prestação de contas (agregado por bairro ou fila de encaminhamentos). Registrado em audit_log. */
export async function GET(request: Request) {
  const supabase = await createClient();
  const profile = await getProfile();
  if (!profile || !["central", "unit_admin", "global_admin"].includes(profile.role))
    return new NextResponse("forbidden", { status: 403 });
  const url = new URL(request.url);
  const kind = url.searchParams.get("kind") ?? "bairros";
  let rows: Record<string, unknown>[] = [];
  if (kind === "bairros") {
    const { data } = await supabase
      .from("v_decisions_total_by_neighborhood")
      .select("neighborhood, registered, tally, minors, decisions_total");
    rows = (data ?? []) as Record<string, unknown>[];
  } else if (kind === "encaminhamentos") {
    const { data } = await supabase
      .from("referrals")
      .select("id, referral_type, status, priority, created_at, first_response_at, done_at, outcome, teams(name)")
      .order("created_at", { ascending: false })
      .limit(5000);
    rows = ((data ?? []) as unknown as Record<string, unknown>[]).map((r) => ({
      ...r,
      team: (r.teams as { name: string } | null)?.name,
      teams: undefined,
    }));
  } else if (kind === "entregas") {
    const { data } = await supabase
      .from("delivery_orders")
      .select("id, kind, item_code, status, scheduled_for, dispatched_at, delivered_at, failure_reason")
      .order("scheduled_for", { ascending: false })
      .limit(5000);
    rows = (data ?? []) as Record<string, unknown>[];
  } else {
    return new NextResponse("kind inválido", { status: 400 });
  }
  await supabase.from("audit_log").insert({
    unit_id: profile.unit_id,
    actor_id: profile.id,
    actor_role: profile.role,
    action: `export_csv:${kind}`,
    table_name: kind,
  });
  const cols = rows.length ? Object.keys(rows[0]).filter((k) => k !== "teams") : [];
  const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
  const csv = [cols.join(";"), ...rows.map((r) => cols.map((c) => esc(r[c])).join(";"))].join("\n");
  return new NextResponse(`﻿${csv}`, {
    headers: {
      "Content-Type": "text/csv; charset=utf-8",
      "Content-Disposition": `attachment; filename="transtornar-${kind}.csv"`,
    },
  });
}
