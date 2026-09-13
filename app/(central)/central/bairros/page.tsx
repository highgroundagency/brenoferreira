import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function BairrosPage() {
  await requireRole(STAFF_ROLES);
  const supabase = await createClient();
  const [{ data: conv }, { data: tot }] = await Promise.all([
    supabase.from("v_conversions_by_neighborhood").select("*"),
    supabase.from("v_decisions_total_by_neighborhood").select("*"),
  ]);
  const totals = new Map((tot ?? []).map((r) => [r.neighborhood_id, r]));
  const rows = (conv ?? [])
    .map((r) => ({ ...r, total: totals.get(r.neighborhood_id) }))
    .sort((a, b) => Number(b.total?.decisions_total ?? 0) - Number(a.total?.decisions_total ?? 0));
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-3 text-xl font-bold">Decisões por bairro</h1>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="py-2 pr-2">Bairro</th>
              <th className="py-2 pr-2 text-right">Decisões</th>
              <th className="py-2 pr-2 text-right">Cadastros</th>
              <th className="py-2 pr-2 text-right">Últimos 30 d</th>
              <th className="py-2 pr-2 text-right">Jornada ativa</th>
              <th className="py-2 text-right">Sem cadastro</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.neighborhood_id} className="border-b">
                <td className="py-2 pr-2 font-medium">{r.neighborhood}</td>
                <td className="py-2 pr-2 text-right tabular-nums">
                  {String(r.total?.decisions_total ?? r.people_total ?? 0)}
                </td>
                <td className="py-2 pr-2 text-right tabular-nums">{r.people_total ?? 0}</td>
                <td className="py-2 pr-2 text-right tabular-nums">{r.people_30d ?? 0}</td>
                <td className="py-2 pr-2 text-right tabular-nums">{r.journey_active ?? 0}</td>
                <td className="py-2 text-right tabular-nums">{String(r.total?.tally ?? 0)}</td>
              </tr>
            ))}
            {rows.length === 0 ? (
              <tr>
                <td colSpan={6} className="py-4 text-center text-muted-foreground">
                  Nenhuma decisão registrada ainda.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </div>
  );
}
