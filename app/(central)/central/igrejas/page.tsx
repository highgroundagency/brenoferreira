import { EditableTable } from "@/components/admin/editable-table";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function IgrejasPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: churches }, { data: nbhs }, { data: conns }] = await Promise.all([
    supabase.from("churches").select("*").order("name"),
    supabase.from("neighborhoods").select("id, name"),
    supabase.from("church_connections").select("status, churches(name)").limit(2000),
  ]);
  const nbhName = new Map((nbhs ?? []).map((n) => [n.id, n.name]));
  const counts = new Map<string, Record<string, number>>();
  for (const c of (conns ?? []) as unknown as { status: string; churches: { name: string } | null }[]) {
    const k = c.churches?.name ?? "?";
    const m = counts.get(k) ?? {};
    m[c.status] = (m[c.status] ?? 0) + 1;
    counts.set(k, m);
  }
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4">
      <h1 className="text-xl font-bold">Igrejas parceiras</h1>
      <p className="text-sm text-muted-foreground">
        A sugestão para a pessoa prioriza a igreja do mesmo bairro. Convite e conexão exigem o consentimento
        "compartilhar com igreja" (botão na jornada ou colhido pela central).
      </p>
      <EditableTable
        table="churches"
        rows={((churches ?? []) as Record<string, unknown>[]).map((c) => ({
          ...c,
          bairro: nbhName.get(String(c.neighborhood_id)) ?? "",
          conexoes: JSON.stringify(counts.get(String(c.name)) ?? {}),
        }))}
        unitId={profile?.unit_id ?? null}
        canEditGlobal={false}
        columns={[
          { key: "name", label: "nome", width: "min-w-48" },
          { key: "bairro", label: "bairro", readonly: true, width: "w-32" },
          { key: "neighborhood_id", label: "neighborhood_id", width: "w-40" },
          { key: "address", label: "endereço", width: "min-w-40" },
          { key: "leader_name", label: "líder", width: "w-32" },
          { key: "contact_phone_e164", label: "telefone", width: "w-36" },
          { key: "service_times", label: "cultos", width: "w-32" },
          { key: "conexoes", label: "conexões", readonly: true, width: "w-40" },
          { key: "active", label: "ativa", type: "boolean" },
        ]}
        newRowDefaults={{ name: "Nova igreja", active: true }}
      />
    </div>
  );
}
