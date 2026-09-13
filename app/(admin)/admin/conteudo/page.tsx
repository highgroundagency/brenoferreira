import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { EditableTable } from "@/components/admin/editable-table";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function ConteudoPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const { data } = await supabase.from("content_assets").select("*").order("key");
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-xl font-bold">Conteúdo (vídeos)</h1>
      <AdminNav current="/admin/conteudo" />
      <p className="mb-2 text-sm text-muted-foreground">
        Publique o vídeo no bucket público <code>content</code> do Storage (≤ 16 MB, H.264/AAC) e cole a URL. Um passo
        só é enviado quando o conteúdo está ativo e com direitos confirmados (rights_ok).
      </p>
      <EditableTable
        table="content_assets"
        rows={(data ?? []) as Record<string, unknown>[]}
        unitId={profile?.unit_id ?? null}
        canEditGlobal={profile?.role === "global_admin"}
        columns={[
          { key: "key", label: "chave", width: "w-24" },
          { key: "title", label: "título", width: "min-w-48" },
          { key: "public_url", label: "URL pública", width: "min-w-72" },
          { key: "duration_seconds", label: "seg", type: "number", width: "w-16" },
          { key: "source", label: "origem", width: "w-32" },
          { key: "rights_ok", label: "direitos", type: "boolean" },
          { key: "active", label: "ativo", type: "boolean" },
        ]}
        newRowDefaults={{
          key: "video_x",
          title: "Novo vídeo",
          media_type: "video",
          public_url: "https://",
          source: "new",
          rights_ok: false,
          active: false,
        }}
      />
    </div>
  );
}
