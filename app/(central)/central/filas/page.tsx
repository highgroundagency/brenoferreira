import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const KIND_LABEL: Record<string, string> = {
  central: "Central",
  basic_food: "Cesta básica",
  home_items: "Itens de casa",
  education: "Educação",
  employment: "Trabalho",
  follow_up: "Acompanhamento",
  logistics: "Logística",
  strategy: "Estratégia",
};

/** Modo central única: a central vê todas as filas; um membro de time vê só as suas (RLS). */
export default async function FilasPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("referrals")
    .select("team_id, status, teams(kind, name)")
    .not("status", "in", "(done,cancelled)");
  const counts = new Map<string, { kind: string; name: string; open: number; fresh: number }>();
  for (const r of (data ?? []) as unknown as {
    team_id: string;
    status: string;
    teams: { kind: string; name: string } | null;
  }[]) {
    const kind = r.teams?.kind ?? "central";
    const c = counts.get(kind) ?? { kind, name: r.teams?.name ?? KIND_LABEL[kind] ?? kind, open: 0, fresh: 0 };
    c.open++;
    if (r.status === "new") c.fresh++;
    counts.set(kind, c);
  }
  const list = [...counts.values()].sort((a, b) => b.fresh - a.fresh || b.open - a.open);
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="mb-3 text-xl font-bold">Filas</h1>
      {list.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum encaminhamento aberto.</p> : null}
      <div className="grid gap-2 sm:grid-cols-2">
        {list.map((c) => (
          <Link key={c.kind} href={`/central/filas/${c.kind}`}>
            <Card className="hover:bg-accent">
              <CardContent className="flex items-center justify-between p-4">
                <span className="font-medium">{c.name}</span>
                <span className="text-sm text-muted-foreground">
                  {c.fresh} novo(s) · {c.open} aberto(s)
                </span>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </div>
  );
}
