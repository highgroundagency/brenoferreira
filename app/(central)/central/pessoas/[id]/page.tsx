import { PersonActions } from "@/components/central/person-actions";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { requireRole } from "@/lib/auth/require-role";
import { STAFF_ROLES } from "@/lib/auth/roles";
import { REFERRAL_TYPE_LABEL, STAGE_LABEL, STATUS_LABEL } from "@/lib/domain/referral-state";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type Record_ = {
  person: Record<string, unknown> & {
    id: string;
    stage: string;
    review_status: string;
    duplicate_of_person_id: string | null;
    observation: string | null;
    created_at: string;
    decided_at: string;
    age_range: string | null;
    needs_job: boolean | null;
    wants_training: boolean | null;
    occupation_area: string | null;
    attends_church: boolean | null;
  };
  contact: {
    full_name: string;
    phone_e164: string;
    phone_owner: string;
    contact_name: string | null;
    email: string | null;
    address_kind: string;
    street: string | null;
    number: string | null;
    complement: string | null;
    postal_code: string | null;
    address_raw: string | null;
    whatsapp_valid: boolean | null;
  } | null;
  neighborhood: string | null;
  children: { age_band: string }[];
  needs: { id: string; need_type: string; item_code: string | null; raw_text: string | null; status: string }[];
  consents: {
    purpose: string;
    granted: boolean;
    confirmed_at: string | null;
    revoked_at: string | null;
    consent_text_version: string;
  }[];
  referrals: {
    id: string;
    referral_type: string;
    status: string;
    team_name: string;
    reason: string | null;
    created_at: string;
    flags: string[];
  }[];
  events: { id: string; event_type: string; payload: Record<string, unknown>; occurred_at: string }[];
  messages: {
    id: string;
    kind: string;
    template_name: string | null;
    status: string;
    skip_reason: string | null;
    error_code: string | null;
    scheduled_for: string;
    sent_at: string | null;
  }[];
};

const fmt = (iso: string) => new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" });

export default async function PessoaPage({ params }: { params: Promise<{ id: string }> }) {
  await requireRole(STAFF_ROLES);
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("open_person_record", { p_person_id: id });
  if (error || !data)
    return <p className="text-sm text-destructive">Ficha indisponível: {error?.message ?? "não encontrada"}.</p>;
  const r = data as unknown as Record_;
  const p = r.person;
  const c = r.contact;
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-4">
      <div>
        <h1 className="text-xl font-bold">{c?.full_name ?? "Pessoa anonimizada"}</h1>
        <div className="mt-1 flex flex-wrap gap-1">
          <Badge variant="secondary">{STAGE_LABEL[p.stage] ?? p.stage}</Badge>
          {p.review_status === "possible_duplicate" ? <Badge variant="destructive">telefone repetido</Badge> : null}
          {p.review_status === "merged" ? <Badge variant="outline">duplicata</Badge> : null}
          {c?.whatsapp_valid === false ? <Badge variant="destructive">sem WhatsApp</Badge> : null}
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Dados</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-1 text-sm sm:grid-cols-2">
          <div>Bairro: {r.neighborhood ?? "?"}</div>
          <div>Decisão: {fmt(p.decided_at)}</div>
          {c ? (
            <>
              <div>
                WhatsApp: {c.phone_e164} ({c.phone_owner}
                {c.contact_name ? `: ${c.contact_name}` : ""})
              </div>
              <div>E-mail: {c.email ?? "—"}</div>
              <div className="sm:col-span-2">
                Endereço ({c.address_kind}): {[c.street, c.number, c.complement].filter(Boolean).join(", ") || "—"}
                {c.address_raw ? ` — ref.: ${c.address_raw}` : ""}
                {c.postal_code ? ` · CEP ${c.postal_code}` : ""}
              </div>
            </>
          ) : null}
          <div>Faixa etária: {p.age_range?.replace("_", "-") ?? "—"}</div>
          <div>
            Filhos: {r.children.length ? r.children.map((ch) => ch.age_band.replace("_", "-")).join(", ") : "0"}
          </div>
          <div>
            Trabalho: {p.needs_job ? "precisa" : p.needs_job === false ? "não precisa" : "—"}
            {p.wants_training ? " · quer curso" : ""}
            {p.occupation_area ? ` · ${p.occupation_area}` : ""}
          </div>
          <div>Igreja: {p.attends_church ? "frequenta" : p.attends_church === false ? "não frequenta" : "—"}</div>
          {p.observation ? <div className="sm:col-span-2">Observação: {p.observation}</div> : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Necessidades e encaminhamentos</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {r.needs.map((n) => (
            <div key={n.id}>
              {n.need_type}
              {n.item_code ? ` (${n.item_code})` : ""} — {n.status}
              {n.raw_text ? ` — "${n.raw_text}"` : ""}
            </div>
          ))}
          {r.referrals.map((ref) => (
            <div key={ref.id} className="flex flex-wrap items-center gap-1">
              <Badge variant="secondary">{REFERRAL_TYPE_LABEL[ref.referral_type] ?? ref.referral_type}</Badge>
              <span>{ref.team_name}</span>
              <Badge variant="outline">{STATUS_LABEL[ref.status as keyof typeof STATUS_LABEL] ?? ref.status}</Badge>
              <span className="text-muted-foreground">{ref.reason}</span>
              {ref.flags?.includes("duplicate_household") ? <Badge variant="destructive">mesma casa</Badge> : null}
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>WhatsApp</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm">
          {r.consents.map((co) => (
            <div key={`${co.purpose}-${co.consent_text_version}`}>
              consentimento {co.purpose} ({co.consent_text_version}):{" "}
              {co.revoked_at ? "revogado" : co.granted ? "concedido" : "negado"}
              {co.confirmed_at ? ` · confirmado ${fmt(co.confirmed_at)}` : ""}
            </div>
          ))}
          {r.messages.map((m) => (
            <div key={m.id}>
              {m.template_name ?? m.kind} — {m.status}
              {m.skip_reason ? ` (${m.skip_reason})` : ""}
              {m.error_code ? ` erro ${m.error_code}` : ""} · {fmt(m.sent_at ?? m.scheduled_for)}
            </div>
          ))}
          {r.messages.length === 0 ? <div className="text-muted-foreground">Nenhuma mensagem.</div> : null}
        </CardContent>
      </Card>

      <PersonActions
        personId={p.id}
        stage={p.stage}
        reviewStatus={p.review_status}
        duplicateOf={p.duplicate_of_person_id}
      />

      <Card>
        <CardHeader>
          <CardTitle>Linha do tempo</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm">
          {r.events.map((ev) => (
            <div key={ev.id} className="flex gap-2">
              <span className="w-28 shrink-0 text-muted-foreground">{fmt(ev.occurred_at)}</span>
              <span>
                {ev.event_type}
                {Object.keys(ev.payload ?? {}).length ? ` — ${JSON.stringify(ev.payload)}` : ""}
              </span>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  );
}
