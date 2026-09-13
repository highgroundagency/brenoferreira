import { CsvImport } from "@/components/central/csv-import";
import { requireRole } from "@/lib/auth/require-role";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ImportarPage() {
  await requireRole(["central", "unit_admin"]);
  const supabase = await createClient();
  const { data: batches } = await supabase
    .from("import_batches")
    .select("kind, file_name, rows_total, rows_imported, rows_rejected, created_at")
    .order("created_at", { ascending: false })
    .limit(20);
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-4">
      <h1 className="text-xl font-bold">Importar pessoas da plataforma legada</h1>
      <p className="text-sm text-muted-foreground">
        Pessoas importadas entram <strong>sem consentimento de WhatsApp</strong>: nenhuma mensagem é enviada. Cada uma
        gera um encaminhamento de contato humano; ao colher o consentimento por telefone, use "Ativar (consentimento
        colhido)" na ficha.
      </p>
      <CsvImport
        rpc="import_legacy_people"
        expected={["full_name", "phone", "neighborhood", "decided_at", "address"]}
        hint="Telefones já cadastrados são rejeitados."
      />
      <div className="text-xs text-muted-foreground">
        {(batches ?? []).map((b, i) => (
          <div key={`${b.created_at}-${i.toString()}`}>
            {new Date(b.created_at).toLocaleString("pt-BR")} · {b.kind} · {b.file_name} · {b.rows_imported}/
            {b.rows_total} importadas, {b.rows_rejected} rejeitadas
          </div>
        ))}
      </div>
    </div>
  );
}
