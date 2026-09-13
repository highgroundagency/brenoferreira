import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { STAGE_LABEL } from "@/lib/domain/referral-state";
import { t } from "@/lib/i18n";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Row = {
  id: string;
  full_name: string;
  phone_e164: string | null;
  neighborhood: string;
  stage: string;
  review_status: string;
  whatsapp_valid: boolean | null;
  last_message_status: string | null;
  created_at: string;
};

const MSG_LABEL: Record<string, string> = {
  queued: "Mensagem agendada",
  sending: "Enviando",
  sent: "Mensagem enviada",
  delivered: "Mensagem entregue",
  read: "Mensagem lida",
  failed: "Falha no envio",
  skipped: "Envio não realizado",
};

export default async function MeusCadastrosPage() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("get_my_registrations");
  const rows = (data ?? []) as unknown as Row[];
  return (
    <div className="mx-auto max-w-lg">
      <h1 className="mb-3 text-xl font-bold">{t("nav.myRegistrations")}</h1>
      {rows.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum cadastro ainda.</p> : null}
      <div className="flex flex-col gap-2">
        {rows.map((r) => (
          <Card key={r.id}>
            <CardContent className="flex flex-col gap-1 p-3">
              <div className="flex items-center justify-between gap-2">
                <span className="font-medium">{r.full_name}</span>
                <span className="text-xs text-muted-foreground">
                  {new Date(r.created_at).toLocaleDateString("pt-BR")}
                </span>
              </div>
              <div className="text-sm text-muted-foreground">
                {r.neighborhood}
                {r.phone_e164 ? ` · ${r.phone_e164}` : ""}
              </div>
              <div className="flex flex-wrap gap-1">
                <Badge variant="secondary">{STAGE_LABEL[r.stage] ?? r.stage}</Badge>
                {r.last_message_status ? (
                  <Badge variant="outline">{MSG_LABEL[r.last_message_status] ?? r.last_message_status}</Badge>
                ) : null}
                {r.review_status === "possible_duplicate" ? (
                  <Badge variant="warning">Em revisão: telefone já cadastrado</Badge>
                ) : null}
                {r.whatsapp_valid === false ? <Badge variant="destructive">Número sem WhatsApp</Badge> : null}
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
