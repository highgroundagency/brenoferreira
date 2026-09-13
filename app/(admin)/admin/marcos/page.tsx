import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { EditableTable } from "@/components/admin/editable-table";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function MarcosPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: rewards }, { data: points }] = await Promise.all([
    supabase.from("reward_rules").select("*").order("threshold"),
    supabase.from("point_rules").select("*").order("event_type"),
  ]);
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-xl font-bold">Marcos e pontos (gamificação)</h1>
      <AdminNav current="/admin/marcos" />
      <p className="mb-2 text-sm text-muted-foreground">
        condition_type: step_completed (passos assistidos), milestone_days (dias corridos desde o início) ou
        points_threshold (pontos acumulados). O prêmio abre uma entrega e avisa a pessoa com message_text ({"{{1}}"} =
        primeiro nome).
      </p>
      <EditableTable
        table="reward_rules"
        rows={(rewards ?? []) as Record<string, unknown>[]}
        unitId={profile?.unit_id ?? null}
        canEditGlobal={profile?.role === "global_admin"}
        columns={[
          { key: "key", label: "chave", width: "w-24" },
          { key: "name", label: "nome" },
          { key: "condition_type", label: "condição", width: "w-36" },
          { key: "threshold", label: "limiar", type: "number", width: "w-20" },
          { key: "item", label: "prêmio", width: "w-28" },
          { key: "stage_on_earn", label: "estágio", width: "w-28" },
          { key: "message_text", label: "mensagem", width: "min-w-64" },
          { key: "active", label: "ativo", type: "boolean" },
        ]}
        newRowDefaults={{
          key: "novo",
          name: "Novo marco",
          condition_type: "step_completed",
          threshold: 10,
          item: "Prêmio",
          active: false,
        }}
      />
      <h2 className="mt-6 mb-2 font-semibold">Pontos por ação</h2>
      <EditableTable
        table="point_rules"
        rows={(points ?? []) as Record<string, unknown>[]}
        unitId={profile?.unit_id ?? null}
        canEditGlobal={profile?.role === "global_admin"}
        columns={[
          { key: "event_type", label: "ação", width: "w-40" },
          { key: "points", label: "pontos", type: "number", width: "w-20" },
          { key: "active", label: "ativo", type: "boolean" },
        ]}
      />
    </div>
  );
}
