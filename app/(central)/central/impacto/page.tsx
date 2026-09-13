import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const LABELS: [string, string][] = [
  ["people_registered", "Pessoas cadastradas"],
  ["decisions_without_record", "Decisões sem cadastro (contagem)"],
  ["journey_active", "Em jornada"],
  ["reached_day7", "Chegaram a 7 dias"],
  ["reached_day16", "Chegaram a 16 dias"],
  ["church_connected", "Conectadas a uma igreja"],
  ["families_in_food_program", "Famílias no programa de cesta"],
  ["food_baskets_delivered", "Cestas entregues"],
  ["home_items_delivered", "Itens de casa entregues"],
  ["courses_completed", "Cursos concluídos"],
  ["people_hired", "Pessoas contratadas"],
  ["neighborhoods_reached", "Bairros alcançados"],
];

/** Relatório institucional (impressão = PDF pelo navegador). Números agregados por unidade; sem dados individuais. */
export default async function ImpactoPage() {
  await requireRole(STAFF_ROLES);
  const supabase = await createClient();
  const { data } = await supabase.from("v_impact_by_unit").select("*");
  return (
    <div className="mx-auto max-w-3xl print:max-w-none">
      <div className="mb-3 flex items-center justify-between print:hidden">
        <h1 className="text-xl font-bold">Relatório de impacto</h1>
        <form action="/central/impacto/refresh" method="post">
          <button type="submit" className="text-sm underline">
            atualizar números
          </button>
        </form>
      </div>
      {(data ?? []).map((u) => (
        <section key={String(u.unit_id)} className="mb-6 rounded-md border p-4">
          <h2 className="mb-2 text-lg font-semibold">Transtornar — {u.unit_name}</h2>
          <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">
            {LABELS.map(([k, label]) => (
              <div key={k} className="rounded-md bg-muted p-3">
                <dt className="text-xs text-muted-foreground">{label}</dt>
                <dd className="text-2xl font-bold tabular-nums">{String((u as Record<string, unknown>)[k] ?? 0)}</dd>
              </div>
            ))}
          </dl>
          <p className="mt-2 text-xs text-muted-foreground">
            Atualizado em {u.refreshed_at ? new Date(String(u.refreshed_at)).toLocaleString("pt-BR") : "—"}. Dados
            agregados; nenhuma informação individual.
          </p>
        </section>
      ))}
    </div>
  );
}
