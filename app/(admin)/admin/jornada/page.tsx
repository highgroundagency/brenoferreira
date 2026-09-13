import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { EditableTable } from "@/components/admin/editable-table";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function JornadaPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const { data } = await supabase.from("journey_steps").select("*").order("sequence");
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-xl font-bold">Jornada — primeiros passos da vida com Deus</h1>
      <AdminNav current="/admin/jornada" />
      <p className="mb-2 text-sm text-muted-foreground">
        day_offset = dias após o início da jornada (confirmação do WhatsApp). content_key aponta para um conteúdo
        publicado (aba Conteúdo); passos sem vídeo publicado são pulados. question_kind: income | events_optin | church.
      </p>
      <EditableTable
        table="journey_steps"
        rows={(data ?? []) as Record<string, unknown>[]}
        unitId={profile?.unit_id ?? null}
        canEditGlobal={profile?.role === "global_admin"}
        columns={[
          { key: "sequence", label: "seq", type: "number", width: "w-16" },
          { key: "day_offset", label: "dia", type: "number", width: "w-16" },
          { key: "title", label: "título", width: "min-w-48" },
          { key: "template_name", label: "template", width: "w-48" },
          { key: "content_key", label: "conteúdo", width: "w-28" },
          { key: "question_kind", label: "pergunta", width: "w-28" },
          { key: "audience_segment", label: "segmento", width: "w-28" },
          { key: "active", label: "ativo", type: "boolean" },
        ]}
        newRowDefaults={{
          journey_key: "primeiros_passos",
          sequence: 99,
          day_offset: 30,
          title: "Novo passo",
          template_name: "transtornar_jornada_v1",
          active: false,
        }}
      />
    </div>
  );
}
