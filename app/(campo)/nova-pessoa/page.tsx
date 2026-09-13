import { NewPersonForm } from "@/components/form/new-person-form";
import { PendingSync } from "@/components/form/pending-sync";
import { t } from "@/lib/i18n";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function NovaPessoaPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: nbhs }, { data: consent }] = await Promise.all([
    supabase
      .from("unit_neighborhoods")
      .select("neighborhood_id, neighborhoods(id, name, normalized_name)")
      .eq("unit_id", profile?.unit_id ?? "")
      .order("neighborhood_id"),
    supabase
      .from("app_settings")
      .select("value")
      .eq("key", "consent_text_v1")
      .eq("unit_id", profile?.unit_id ?? "")
      .maybeSingle(),
  ]);
  const neighborhoods = (nbhs ?? [])
    .map((r) => r.neighborhoods)
    .filter((n): n is { id: string; name: string; normalized_name: string } => !!n)
    .sort((a, b) => a.name.localeCompare(b.name, "pt-BR"));
  const consentText =
    (consent?.value as { version?: string; base?: string; social_assistance?: string; terms_url?: string } | null) ??
    null;

  return (
    <div className="mx-auto max-w-lg">
      <h1 className="mb-3 text-xl font-bold">{t("form.title")}</h1>
      <PendingSync />
      <NewPersonForm neighborhoods={neighborhoods} consent={consentText} />
    </div>
  );
}
