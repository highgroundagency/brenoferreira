import { EditableTable } from "@/components/admin/editable-table";
import { EnrollmentList } from "@/components/central/enrollment-list";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function EducacaoPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: courses }, { data: enrollments }] = await Promise.all([
    supabase.from("courses").select("*").order("starts_at", { ascending: false }),
    supabase
      .from("enrollments")
      .select("id, status, created_at, person_id, child_id, courses(name), people!inner(people_contacts(full_name))")
      .order("created_at", { ascending: false })
      .limit(200),
  ]);
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6">
      <h1 className="text-xl font-bold">Educação — cursos e matrículas</h1>
      <section>
        <h2 className="mb-2 font-semibold">Cursos (Transtornar de educação e parceiros)</h2>
        <EditableTable
          table="courses"
          rows={(courses ?? []) as Record<string, unknown>[]}
          unitId={profile?.unit_id ?? null}
          canEditGlobal={false}
          columns={[
            { key: "name", label: "nome", width: "min-w-48" },
            { key: "audience", label: "público (teen/adult)", width: "w-28" },
            { key: "area", label: "área", width: "w-28" },
            { key: "partner", label: "parceiro", width: "w-32" },
            { key: "seats", label: "vagas", type: "number", width: "w-16" },
            { key: "starts_at", label: "início", width: "w-32" },
            { key: "location", label: "local", width: "w-36" },
            { key: "active", label: "ativo", type: "boolean" },
          ]}
          newRowDefaults={{ name: "Novo curso", audience: "adult", active: true }}
        />
      </section>
      <section>
        <h2 className="mb-2 font-semibold">Matrículas</h2>
        <EnrollmentList rows={(enrollments ?? []) as never} />
      </section>
    </div>
  );
}
