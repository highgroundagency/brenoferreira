import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { STAGE_LABEL } from "@/lib/domain/referral-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const fmt = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("pt-BR") : "—");

/** CRM: quem precisa de contato humano (estágio, último contato, responsável, próxima ação). */
export default async function AcompanhamentoPage({
  searchParams,
}: {
  searchParams: Promise<{ stage?: string; mine?: string }>;
}) {
  const profile = await requireRole(STAFF_ROLES);
  const { stage, mine } = await searchParams;
  const supabase = await createClient();
  let q = supabase
    .from("people")
    .select(
      "id, stage, last_contact_at, assigned_to, created_at, points, people_contacts(full_name), neighborhoods(name), profiles!people_assigned_to_fkey(full_name), follow_ups(next_action_at, done_at)",
    )
    .not("stage", "in", "(anonymized,opted_out)")
    .neq("review_status", "merged")
    .order("last_contact_at", { ascending: true, nullsFirst: true })
    .limit(200);
  if (stage) q = q.eq("stage", stage);
  if (mine) q = q.eq("assigned_to", profile.id);
  const { data } = await q;
  type Row = {
    id: string;
    stage: string;
    last_contact_at: string | null;
    created_at: string;
    points: number;
    people_contacts: { full_name: string } | null;
    neighborhoods: { name: string } | null;
    profiles: { full_name: string } | null;
    follow_ups: { next_action_at: string | null; done_at: string | null }[];
  };
  const rows = (data ?? []) as unknown as Row[];
  const stages = Object.keys(STAGE_LABEL).filter((s) => !["anonymized", "opted_out"].includes(s));
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="mb-3 text-xl font-bold">Acompanhamento</h1>
      <div className="mb-3 flex flex-wrap gap-1 text-sm">
        <Link
          href="/central/acompanhamento"
          className={`rounded-full border px-3 py-1 ${!stage && !mine ? "bg-primary text-primary-foreground" : ""}`}
        >
          todos
        </Link>
        <Link
          href="/central/acompanhamento?mine=1"
          className={`rounded-full border px-3 py-1 ${mine ? "bg-primary text-primary-foreground" : ""}`}
        >
          meus
        </Link>
        {stages.map((s) => (
          <Link
            key={s}
            href={`/central/acompanhamento?stage=${s}`}
            className={`rounded-full border px-3 py-1 ${stage === s ? "bg-primary text-primary-foreground" : ""}`}
          >
            {STAGE_LABEL[s]}
          </Link>
        ))}
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="py-2 pr-2">Pessoa</th>
              <th className="py-2 pr-2">Bairro</th>
              <th className="py-2 pr-2">Estágio</th>
              <th className="py-2 pr-2">Último contato</th>
              <th className="py-2 pr-2">Próxima ação</th>
              <th className="py-2 pr-2">Responsável</th>
              <th className="py-2 text-right">Pontos</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const next = r.follow_ups
                .filter((f) => !f.done_at && f.next_action_at)
                .sort((a, b) => String(a.next_action_at).localeCompare(String(b.next_action_at)))[0];
              return (
                <tr key={r.id} className="border-b">
                  <td className="py-2 pr-2">
                    <Link className="underline" href={`/central/pessoas/${r.id}`}>
                      {r.people_contacts?.full_name ?? "—"}
                    </Link>
                  </td>
                  <td className="py-2 pr-2">{r.neighborhoods?.name}</td>
                  <td className="py-2 pr-2">
                    <Badge variant="secondary">{STAGE_LABEL[r.stage] ?? r.stage}</Badge>
                  </td>
                  <td className="py-2 pr-2">{fmt(r.last_contact_at)}</td>
                  <td className="py-2 pr-2">{next ? fmt(next.next_action_at) : "—"}</td>
                  <td className="py-2 pr-2">{r.profiles?.full_name ?? "—"}</td>
                  <td className="py-2 text-right tabular-nums">{r.points}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
