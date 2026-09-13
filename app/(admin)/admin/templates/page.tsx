import { AdminNav } from "@/app/(admin)/admin/layout-nav";
import { Badge } from "@/components/ui/badge";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function TemplatesPage() {
  const supabase = await createClient();
  const { data } = await supabase.from("message_templates").select("*").order("name");
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="text-xl font-bold">Templates do WhatsApp</h1>
      <AdminNav current="/admin/templates" />
      <p className="mb-2 text-sm text-muted-foreground">
        Status e categoria são espelhados da Meta (webhook <code>message_template_status_update</code>). Submeta cada
        template no Business Manager com o mesmo nome, idioma, corpo e botões na mesma ordem (docs/ops/whatsapp.md).
      </p>
      <div className="flex flex-col gap-2 text-sm">
        {(data ?? []).map((t) => (
          <div key={t.id} className="rounded-md border p-3">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-medium">{t.name}</span>
              <Badge
                variant={t.status === "approved" ? "success" : t.status === "rejected" ? "destructive" : "outline"}
              >
                {t.status}
              </Badge>
              <Badge variant="secondary">{t.category}</Badge>
              <span className="text-xs text-muted-foreground">
                {t.language} · header {t.header_type ?? "none"} · {t.unit_id ? "unidade" : "global"}
              </span>
            </div>
            <div className="mt-1">{t.body_text}</div>
            <div className="mt-1 text-xs text-muted-foreground">botões: {JSON.stringify(t.buttons)}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
