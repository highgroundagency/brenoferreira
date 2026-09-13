import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { EditableTable } from "@/components/admin/editable-table";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function RegrasPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const { data } = await supabase.from("routing_rules").select("*").order("priority");
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-xl font-bold">Regras de roteamento</h1>
      <AdminNav current="/admin/regras" />
      <p className="mb-2 text-sm text-muted-foreground">
        Se a unidade tiver ao menos uma regra própria, as globais deixam de valer para ela. Condições: {"{"}
        "always":true{"}"}, {"{"}"need_type":"food"{"}"}, {"{"}"need_type_in":[...]{"}"}, {"{"}
        "children_age_band_in":[...]{"}"}, {"{"}"person_flags_any":["needs_job","wants_training"]{"}"}.
      </p>
      <EditableTable
        table="routing_rules"
        rows={(data ?? []) as Record<string, unknown>[]}
        unitId={profile?.unit_id ?? null}
        canEditGlobal={profile?.role === "global_admin"}
        columns={[
          { key: "priority", label: "prioridade", type: "number", width: "w-20" },
          { key: "name", label: "nome" },
          { key: "condition", label: "condição (JSON)", type: "json", width: "min-w-56" },
          { key: "target_team_kind", label: "time", width: "w-32" },
          { key: "referral_type", label: "tipo", width: "w-36" },
          { key: "auto_triage", label: "auto", type: "boolean" },
          { key: "active", label: "ativa", type: "boolean" },
        ]}
        newRowDefaults={{
          name: "Nova regra",
          priority: 60,
          condition: { always: false },
          target_team_kind: "central",
          referral_type: "other",
          active: false,
        }}
      />
    </div>
  );
}
