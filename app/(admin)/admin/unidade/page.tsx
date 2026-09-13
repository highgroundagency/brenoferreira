import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { UnitSettingsForm } from "@/components/admin/unit-settings-form";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function UnidadePage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const unitId = profile?.unit_id ?? "";
  const [{ data: unit }, { data: consent }] = await Promise.all([
    supabase
      .from("units")
      .select("name, whatsapp_phone_number_id, whatsapp_waba_id, whatsapp_display_name, timezone, settings")
      .eq("id", unitId)
      .maybeSingle(),
    supabase.from("app_settings").select("value").eq("unit_id", unitId).eq("key", "consent_text_v1").maybeSingle(),
  ]);
  if (!unit)
    return <p className="text-sm text-muted-foreground">Admin global: escolha uma unidade em /admin/unidades.</p>;
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="text-xl font-bold">Unidade — {unit.name}</h1>
      <AdminNav current="/admin/unidade" />
      <UnitSettingsForm
        unitId={unitId}
        unit={{ ...unit, settings: (unit.settings ?? {}) as never }}
        consent={(consent?.value as never) ?? null}
      />
    </div>
  );
}
