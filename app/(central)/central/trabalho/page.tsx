import { EditableTable } from "@/components/admin/editable-table";
import { CsvImport } from "@/components/central/csv-import";
import { PlacementList } from "@/components/central/placement-list";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function TrabalhoPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: companies }, { data: openings }, { data: placements }] = await Promise.all([
    supabase.from("companies").select("*").order("name"),
    supabase.from("job_openings").select("*, companies(name)").order("created_at", { ascending: false }),
    supabase
      .from("job_placements")
      .select(
        "id, status, note, created_at, person_id, people!inner(people_contacts(full_name)), job_openings(role, companies(name))",
      )
      .order("created_at", { ascending: false })
      .limit(100),
  ]);
  const canWrite = ["central", "unit_admin"].includes(profile?.role ?? "");
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <h1 className="text-xl font-bold">Trabalho — empresas, vagas e colocações</h1>
      {canWrite ? (
        <CsvImport
          rpc="import_companies"
          expected={[
            "name",
            "cnpj",
            "sector",
            "contact_name",
            "contact_phone",
            "contact_email",
            "neighborhood",
            "job_role",
            "area",
            "open_positions",
            "role",
          ]}
          hint="Dedup por CNPJ, depois telefone do contato. role = employer | benefit_partner | both."
        />
      ) : null}
      <section>
        <h2 className="mb-2 font-semibold">Empresas</h2>
        <EditableTable
          table="companies"
          rows={(companies ?? []) as Record<string, unknown>[]}
          unitId={profile?.unit_id ?? null}
          canEditGlobal={false}
          columns={[
            { key: "name", label: "nome", width: "min-w-48" },
            { key: "legal_id", label: "CNPJ", width: "w-40" },
            { key: "sector", label: "setor", width: "w-32" },
            { key: "roles", label: "papéis (JSON)", type: "json", width: "w-40" },
            { key: "active", label: "ativa", type: "boolean" },
          ]}
          newRowDefaults={{ name: "Nova empresa", roles: ["employer"], source: "manual" }}
        />
      </section>
      <section>
        <h2 className="mb-2 font-semibold">Vagas</h2>
        <EditableTable
          table="job_openings"
          rows={(
            (openings ?? []) as unknown as (Record<string, unknown> & { companies: { name: string } | null })[]
          ).map((o) => ({ ...o, company: o.companies?.name ?? "", companies: undefined }))}
          unitId={profile?.unit_id ?? null}
          canEditGlobal={false}
          columns={[
            { key: "company", label: "empresa", readonly: true, width: "w-40" },
            { key: "role", label: "função", width: "min-w-40" },
            { key: "area", label: "área", width: "w-32" },
            { key: "open_positions", label: "vagas", type: "number", width: "w-16" },
            { key: "requirements", label: "requisitos", width: "min-w-40" },
            { key: "status", label: "status", width: "w-24" },
          ]}
        />
        <p className="mt-1 text-xs text-muted-foreground">
          Nova vaga: importe pelo CSV (job_role) ou cadastre a empresa e adicione a vaga pela ficha da pessoa ao
          encaminhar.
        </p>
      </section>
      <section>
        <h2 className="mb-2 font-semibold">Colocações</h2>
        <PlacementList rows={(placements ?? []) as never} />
      </section>
    </div>
  );
}
