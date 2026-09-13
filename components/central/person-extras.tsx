"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

type Journey = {
  status: string;
  current_sequence: number;
  completed_steps: number;
  started_at: string;
  next_send_at: string | null;
} | null;
type Progress = {
  sequence: number;
  title: string;
  status: string;
  sent_at: string | null;
  watched_at: string | null;
  feedback_score: number | null;
  answer: string | null;
};
type Reward = { item: string; name: string; earned_at: string; delivered_at: string | null };
type FollowUp = {
  id: string;
  channel: string;
  note: string;
  member_name: string | null;
  next_action_at: string | null;
  done_at: string | null;
  created_at: string;
};
type Program = {
  id: string;
  program_type: string;
  status: string;
  start_date: string;
  end_date: string;
  planned_deliveries: number;
  completed_deliveries: number;
};
type Delivery = {
  id: string;
  kind: string;
  item_code: string | null;
  status: string;
  scheduled_for: string;
  delivered_at: string | null;
  failure_reason: string | null;
};
type Referral = { id: string; referral_type: string; status: string };

const fmt = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" }) : "—";
const DELIVERY_NEXT: Record<string, string[]> = {
  scheduled: ["picking", "packed", "out_for_delivery", "cancelled"],
  picking: ["packed", "cancelled"],
  packed: ["out_for_delivery", "cancelled"],
  out_for_delivery: ["delivered", "failed"],
  failed: ["scheduled", "out_for_delivery", "cancelled"],
  delivered: [],
  cancelled: [],
};
export const DELIVERY_LABEL: Record<string, string> = {
  scheduled: "Agendada",
  picking: "Separando",
  packed: "Embalada",
  out_for_delivery: "Saiu para entrega",
  delivered: "Entregue",
  failed: "Falhou",
  cancelled: "Cancelada",
};

export function PersonExtras({
  personId,
  points,
  journey,
  progress,
  rewards,
  followUps,
  programs,
  deliveries,
  referrals,
  canWrite,
}: {
  personId: string;
  points: number;
  journey: Journey;
  progress: Progress[];
  rewards: Reward[];
  followUps: FollowUp[];
  programs: Program[];
  deliveries: Delivery[];
  referrals: Referral[];
  canWrite: boolean;
}) {
  const router = useRouter();
  const [note, setNote] = useState("");
  const [channel, setChannel] = useState("whatsapp");
  const [next, setNext] = useState("");
  const [busy, setBusy] = useState(false);
  const supabase = () => createClient();
  async function run(label: string, fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true);
    const { error } = await fn();
    setBusy(false);
    if (error) toast.error(`${label}: ${error.message}`);
    else {
      toast.success(label);
      router.refresh();
    }
  }
  const foodReferral = referrals.find(
    (r) => r.referral_type === "basic_food" && !["done", "cancelled"].includes(r.status),
  );
  const activeProgram = programs.find((p) => p.status === "active");

  return (
    <>
      <Card>
        <CardHeader>
          <CardTitle>Jornada e gamificação</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {journey ? (
            <div className="flex flex-wrap gap-1">
              <Badge variant="secondary">jornada {journey.status}</Badge>
              <Badge variant="outline">{journey.completed_steps} passo(s) concluído(s)</Badge>
              <Badge variant="outline">{points} pontos</Badge>
              {journey.next_send_at ? (
                <span className="text-muted-foreground">próximo envio {fmt(journey.next_send_at)}</span>
              ) : null}
            </div>
          ) : (
            <span className="text-muted-foreground">Jornada ainda não iniciada (inicia ao confirmar o WhatsApp).</span>
          )}
          {progress.map((s) => (
            <div key={s.sequence} className="flex flex-wrap items-center gap-2">
              <span className="w-6 text-muted-foreground">{s.sequence}</span>
              <span className="min-w-40">{s.title}</span>
              <Badge
                variant={
                  s.status === "watched" || s.status === "answered"
                    ? "success"
                    : s.status === "skipped"
                      ? "warning"
                      : "outline"
                }
              >
                {s.status}
              </Badge>
              {s.feedback_score ? <span className="text-xs">feedback {s.feedback_score}/3</span> : null}
              {s.answer ? <span className="text-xs">resposta: {s.answer}</span> : null}
              <span className="text-xs text-muted-foreground">{fmt(s.watched_at ?? s.sent_at)}</span>
            </div>
          ))}
          {rewards.map((r) => (
            <div key={r.name}>
              🎁 {r.item} ({r.name}) —{" "}
              {r.delivered_at ? `entregue ${fmt(r.delivered_at)}` : `conquistado ${fmt(r.earned_at)}`}
            </div>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Acompanhamento</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {followUps.map((f) => (
            <div key={f.id} className="border-b pb-1 last:border-0">
              <span className="text-xs text-muted-foreground">
                {fmt(f.created_at)} · {f.member_name ?? "?"} · {f.channel}
              </span>
              <div>{f.note}</div>
              {f.next_action_at && !f.done_at ? (
                <div className="text-xs text-amber-700">próxima ação {fmt(f.next_action_at)}</div>
              ) : null}
            </div>
          ))}
          <div className="flex flex-wrap items-end gap-2">
            <Input
              placeholder="o que aconteceu no contato"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className="w-72"
            />
            <Select value={channel} onChange={(e) => setChannel(e.target.value)} className="w-36">
              <option value="whatsapp">WhatsApp</option>
              <option value="phone">Ligação</option>
              <option value="visit">Visita</option>
              <option value="church">Igreja</option>
              <option value="other">Outro</option>
            </Select>
            <Input type="datetime-local" value={next} onChange={(e) => setNext(e.target.value)} className="w-56" />
            <Button
              variant="outline"
              disabled={busy || !note}
              onClick={() =>
                run("Acompanhamento registrado", async () => {
                  const res = await supabase().rpc("add_follow_up", {
                    p_person_id: personId,
                    p_note: note,
                    p_channel: channel,
                    p_next_action_at: next ? new Date(next).toISOString() : undefined,
                  });
                  if (!res.error) {
                    setNote("");
                    setNext("");
                  }
                  return res;
                })
              }
            >
              Registrar contato
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Cesta básica e entregas</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {programs.map((p) => (
            <div key={p.id}>
              Programa {p.program_type} — {p.status} · {p.start_date} → {p.end_date} · {p.completed_deliveries}/
              {p.planned_deliveries} entregas
            </div>
          ))}
          {foodReferral && !activeProgram && canWrite ? (
            <Button
              variant="outline"
              disabled={busy}
              onClick={() =>
                run("Programa de 3 meses iniciado", () =>
                  supabase().rpc("start_assistance_program", { p_referral_id: foodReferral.id }),
                )
              }
            >
              Iniciar programa de cesta básica (3 meses)
            </Button>
          ) : null}
          {deliveries.map((d) => (
            <div key={d.id} className="flex flex-wrap items-center gap-2">
              <span>
                {d.kind === "basic_food"
                  ? "Cesta"
                  : d.kind === "reward"
                    ? `Prêmio: ${d.item_code}`
                    : `Item: ${d.item_code ?? ""}`}{" "}
                · {d.scheduled_for}
              </span>
              <Badge variant={d.status === "delivered" ? "success" : d.status === "failed" ? "destructive" : "outline"}>
                {DELIVERY_LABEL[d.status] ?? d.status}
              </Badge>
              {d.failure_reason ? <span className="text-xs text-destructive">{d.failure_reason}</span> : null}
              {(DELIVERY_NEXT[d.status] ?? []).map((to) => (
                <Button
                  key={to}
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() => {
                    const note =
                      to === "delivered" || to === "failed"
                        ? (window.prompt(to === "delivered" ? "Quem recebeu?" : "Motivo da falha:") ?? undefined)
                        : undefined;
                    run(`Entrega: ${DELIVERY_LABEL[to]}`, () =>
                      supabase().rpc("delivery_transition", { p_delivery_id: d.id, p_to: to, p_note: note }),
                    );
                  }}
                >
                  {DELIVERY_LABEL[to]}
                </Button>
              ))}
            </div>
          ))}
        </CardContent>
      </Card>
    </>
  );
}
