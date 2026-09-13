import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { UnitManager, type UnitRow } from "@/components/admin/unit-manager";
import { requireRole } from "@/lib/auth/require-role";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function UnidadesPage() {
  await requireRole(["global_admin"]);
  const supabase = await createClient();
  const [{ data: units }, { data: cities }] = await Promise.all([
    supabase.from("v_units_comparison").select("*").order("created_at"),
    supabase.from("cities").select("id, name, state, ibge_code").order("name"),
  ]);
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-xl font-bold">Unidades (franquia)</h1>
      <AdminNav current="/admin/unidades" />
      <UnitManager units={(units ?? []) as unknown as UnitRow[]} cities={(cities ?? []) as never} />
    </div>
  );
}
