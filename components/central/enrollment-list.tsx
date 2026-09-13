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
  created_at: string;
  person_id: string;
  child_id: string | null;
  courses: { name: string } | null;
  people: { people_contacts: { full_name: string } | null } | null;
};
const NEXT: Record<string, string[]> = {
  interested: ["enrolled", "dropped"],
  enrolled: ["attending", "completed", "dropped"],
  attending: ["completed", "dropped"],
};
const LABEL: Record<string, string> = {
  interested: "Interessado",
  enrolled: "Matriculado",
  attending: "Frequentando",
  completed: "Concluiu",
  dropped: "Desistiu",
};

export function EnrollmentList({ rows }: { rows: Row[] }) {
  const router = useRouter();
  async function go(id: string, to: string) {
    const note = to === "completed" ? (window.prompt("Certificado / observação:") ?? undefined) : undefined;
    const { error } = await createClient().rpc("enrollment_transition", {
      p_enrollment_id: id,
      p_to: to,
      p_note: note,
    });
    if (error) toast.error(error.message);
    else router.refresh();
  }
  if (!rows.length)
    return <p className="text-sm text-muted-foreground">Nenhuma matrícula. Matricule pela ficha da pessoa.</p>;
  return (
    <div className="flex flex-col gap-1 text-sm">
      {rows.map((r) => (
        <div key={r.id} className="flex flex-wrap items-center gap-2 border-b py-1">
          <Link className="underline" href={`/central/pessoas/${r.person_id}`}>
            {r.people?.people_contacts?.full_name ?? "—"}
          </Link>
          {r.child_id ? <Badge variant="secondary">filho(a)</Badge> : null}
          <span className="text-muted-foreground">{r.courses?.name}</span>
          <Badge variant={r.status === "completed" ? "success" : "outline"}>{LABEL[r.status] ?? r.status}</Badge>
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
