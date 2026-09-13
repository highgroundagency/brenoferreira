"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

type Row = {
  id: string;
  status: string;
  note: string | null;
  created_at: string;
  person_id: string;
  people: { people_contacts: { full_name: string } | null } | null;
  job_openings: { role: string; companies: { name: string } | null } | null;
};
const NEXT: Record<string, string[]> = {
  referred: ["interviewed", "hired", "not_hired", "dropped"],
  interviewed: ["hired", "not_hired", "dropped"],
};
const LABEL: Record<string, string> = {
  referred: "Encaminhado",
  interviewed: "Entrevistado",
  hired: "Contratado",
  not_hired: "Não contratado",
  dropped: "Desistiu",
};

export function PlacementList({ rows }: { rows: Row[] }) {
  const router = useRouter();
  async function go(id: string, to: string) {
    const { error } = await createClient().rpc("placement_transition", { p_placement_id: id, p_to: to });
    if (error) toast.error(error.message);
    else router.refresh();
  }
  if (!rows.length) return <p className="text-sm text-muted-foreground">Nenhuma colocação.</p>;
  return (
    <div className="flex flex-col gap-1 text-sm">
      {rows.map((r) => (
        <div key={r.id} className="flex flex-wrap items-center gap-2 border-b py-1">
          <Link className="underline" href={`/central/pessoas/${r.person_id}`}>
            {r.people?.people_contacts?.full_name ?? "—"}
          </Link>
          <span className="text-muted-foreground">
            {r.job_openings?.role} · {r.job_openings?.companies?.name}
          </span>
          <Badge variant={r.status === "hired" ? "success" : "outline"}>{LABEL[r.status] ?? r.status}</Badge>
          {(NEXT[r.status] ?? []).map((to) => (
            <Button key={to} size="sm" variant="ghost" onClick={() => go(r.id, to)}>
              {LABEL[to]}
            </Button>
          ))}
        </div>
      ))}
    </div>
  );
}
