import { EditableTable } from "@/components/admin/editable-table";
import { BenefitRedeem } from "@/components/central/benefit-redeem";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function BeneficiosPage() {
  await requireRole(STAFF_ROLES);
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: benefits }, { data: partners }, { data: redemptions }] = await Promise.all([
    supabase.from("benefits").select("*, companies(name)").order("title"),
    supabase.from("companies").select("id, name, roles").contains("roles", ["benefit_partner"]).order("name"),
    supabase
      .from("benefit_redemptions")
      .select(
        "id, redeemed_at, note, benefits(title), supporters(card_code, external_name, people(people_contacts(full_name)))",
      )
      .order("redeemed_at", { ascending: false })
      .limit(50),
  ]);
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <div>
        <h1 className="text-xl font-bold">Clube de benefícios</h1>
        <p className="text-sm text-muted-foreground">
          Empresas com o papel <code>benefit_partner</code> (cadastro em Trabalho) oferecem benefícios a quem mantém o
          projeto. O mantenedor apresenta o código da carteirinha.
        </p>
      </div>
      <BenefitRedeem benefits={(benefits ?? []).map((b) => ({ id: b.id, title: b.title }))} />
      <section>
        <h2 className="mb-2 font-semibold">Benefícios ({partners?.length ?? 0} parceiro(s))</h2>
        <EditableTable
          table="benefits"
          rows={(
            (benefits ?? []) as unknown as (Record<string, unknown> & { companies: { name: string } | null })[]
          ).map((b) => ({ ...b, parceiro: b.companies?.name ?? "", companies: undefined }))}
          unitId={profile?.unit_id ?? null}
          canEditGlobal={false}
          columns={[
            { key: "parceiro", label: "parceiro", readonly: true, width: "w-40" },
            { key: "company_id", label: "company_id", width: "w-40" },
            { key: "title", label: "benefício", width: "min-w-48" },
            { key: "rules", label: "regras", width: "min-w-48" },
            { key: "valid_until", label: "validade", width: "w-32" },
            { key: "active", label: "ativo", type: "boolean" },
          ]}
          newRowDefaults={{ title: "Novo benefício", active: false }}
        />
        <p className="mt-1 text-xs text-muted-foreground">
          company_id: copie o id da empresa parceira na aba Trabalho.
        </p>
      </section>
      <section>
        <h2 className="mb-2 font-semibold">Resgates recentes</h2>
        <div className="flex flex-col gap-1 text-sm">
          {(
            (redemptions ?? []) as unknown as {
              id: string;
              redeemed_at: string;
              note: string | null;
              benefits: { title: string } | null;
              supporters: {
                card_code: string | null;
                external_name: string | null;
                people: { people_contacts: { full_name: string } | null } | null;
              } | null;
            }[]
          ).map((r) => (
            <div key={r.id} className="border-b py-1">
              {new Date(r.redeemed_at).toLocaleString("pt-BR")} · {r.benefits?.title} ·{" "}
              {r.supporters?.people?.people_contacts?.full_name ??
                r.supporters?.external_name ??
                r.supporters?.card_code}{" "}
              {r.note ? `· ${r.note}` : ""}
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
