import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function BairrosPage({
  searchParams,
}: {
  searchParams: Promise<{ dias?: string; stage?: string }>;
}) {
  await requireRole(STAFF_ROLES);
  const { dias, stage } = await searchParams;
  const supabase = await createClient();
  const [{ data: conv }, { data: tot }, { data: filtered }] = await Promise.all([
    supabase.from("v_conversions_by_neighborhood").select("*"),
    supabase.from("v_decisions_total_by_neighborhood").select("*"),
    dias || stage
      ? (() => {
          let q = supabase.from("people").select("neighborhood_id").neq("review_status", "merged");
          if (dias) q = q.gte("decided_at", new Date(Date.now() - Number(dias) * 86400000).toISOString());
          if (stage) q = q.eq("stage", stage);
          return q;
        })()
      : Promise.resolve({ data: null }),
  ]);
  const filteredCount = new Map<string, number>();
  for (const r of (filtered ?? []) as { neighborhood_id: string }[])
    filteredCount.set(r.neighborhood_id, (filteredCount.get(r.neighborhood_id) ?? 0) + 1);
  const totals = new Map((tot ?? []).map((r) => [r.neighborhood_id, r]));
  const rows = (conv ?? [])
    .map((r) => ({ ...r, total: totals.get(r.neighborhood_id) }))
    .sort((a, b) => Number(b.total?.decisions_total ?? 0) - Number(a.total?.decisions_total ?? 0));
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-1 text-xl font-bold">Decisões por bairro</h1>
      <div className="mb-3 flex flex-wrap items-center gap-1 text-xs">
        <a className="rounded-full border px-2 py-1" href="/central/bairros">
          tudo
        </a>
        <a className="rounded-full border px-2 py-1" href="/central/bairros?dias=30">
          30 dias
        </a>
        <a className="rounded-full border px-2 py-1" href="/central/bairros?dias=90">
          90 dias
        </a>
        <a className="rounded-full border px-2 py-1" href="/central/bairros?stage=journey_active">
          jornada ativa
        </a>
        <a className="rounded-full border px-2 py-1" href="/central/bairros?stage=day7_done">
          7 dias
        </a>
        <a className="rounded-full border px-2 py-1" href="/central/bairros?stage=day16_done">
          16 dias
        </a>
        <a className="ml-auto underline" href="/central/exportar?kind=bairros">
          exportar CSV
        </a>
        <a className="underline" href="/central/exportar?kind=encaminhamentos">
          encaminhamentos CSV
        </a>
        <a className="underline" href="/central/exportar?kind=entregas">
          entregas CSV
        </a>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="py-2 pr-2">Bairro</th>
              <th className="py-2 pr-2 text-right">Decisões</th>
              <th className="py-2 pr-2 text-right">Cadastros</th>
              <th className="py-2 pr-2 text-right">Últimos 30 d</th>
              <th className="py-2 pr-2 text-right">Jornada ativa</th>
              {dias || stage ? <th className="py-2 pr-2 text-right">Filtro</th> : null}
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
                {dias || stage ? (
                  <td className="py-2 pr-2 text-right tabular-nums">
                    {filteredCount.get(r.neighborhood_id ?? "") ?? 0}
                  </td>
                ) : null}
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
