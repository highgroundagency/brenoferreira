"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { REFERRAL_TYPE_LABEL, type ReferralStatus, STATUS_LABEL, TRANSITIONS } from "@/lib/domain/referral-state";
import { createClient } from "@/lib/supabase/client";

export type QueueItem = {
  id: string;
  person_id: string;
  referral_type: string;
  status: ReferralStatus;
  priority: number;
  flags: string[];
  reason: string | null;
  created_at: string;
  first_response_at: string | null;
  full_name: string;
  neighborhood: string;
  phone_e164: string | null;
  address: {
    kind: string;
    street: string | null;
    number: string | null;
    complement: string | null;
    postal_code: string | null;
    reference: string | null;
  } | null;
  children_count: number;
  children_bands: string[];
  household_children: number | null;
  needs: { type: string; item: string | null; status: string }[];
};

function hoursSince(iso: string) {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 36e5);
}

export function QueueList({ items, canOpenRecord }: { items: QueueItem[]; canOpenRecord: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);

  async function transition(id: string, to: ReferralStatus) {
    setBusy(id);
    const supabase = createClient();
    const note = to === "cancelled" ? (window.prompt("Motivo do cancelamento:") ?? undefined) : undefined;
    const { error } = await supabase.rpc("referral_transition", {
      p_referral_id: id,
      p_to: to,
      p_note: note ?? undefined,
    });
    setBusy(null);
    if (error) toast.error(`Não foi possível mudar o status: ${error.message}`);
    else router.refresh();
  }

  if (items.length === 0) return <p className="text-sm text-muted-foreground">Fila vazia.</p>;
  return (
    <div className="flex flex-col gap-2">
      {items.map((it) => (
        <Card key={it.id}>
          <CardContent className="flex flex-col gap-2 p-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="font-medium">
                {canOpenRecord ? (
                  <Link className="underline" href={`/central/pessoas/${it.person_id}`}>
                    {it.full_name}
                  </Link>
                ) : (
                  it.full_name
                )}{" "}
                <span className="text-muted-foreground">· {it.neighborhood}</span>
              </div>
              <div className="flex flex-wrap gap-1">
                <Badge variant="secondary">{REFERRAL_TYPE_LABEL[it.referral_type] ?? it.referral_type}</Badge>
                <Badge variant={it.status === "new" ? "warning" : "outline"}>{STATUS_LABEL[it.status]}</Badge>
                {it.priority === 1 ? <Badge variant="destructive">prioridade</Badge> : null}
                {it.flags.includes("duplicate_household") ? (
                  <Badge variant="destructive">mesma casa já atendida</Badge>
                ) : null}
              </div>
            </div>
            <div className="text-sm">
              {it.reason ? <div>{it.reason}</div> : null}
              {it.phone_e164 ? <div>WhatsApp: {it.phone_e164}</div> : null}
              {it.address ? (
                <div>
                  {[it.address.street, it.address.number, it.address.complement].filter(Boolean).join(", ")}
                  {it.address.reference ? ` — ref.: ${it.address.reference}` : ""}
                  {it.address.postal_code ? ` · CEP ${it.address.postal_code}` : ""}
                </div>
              ) : null}
              {it.children_count > 0 ? (
                <div>Filhos: {it.children_bands.map((b) => b.replace("_", "-")).join(", ")}</div>
              ) : null}
              {it.needs.length ? (
                <div>Necessidades: {it.needs.map((n) => `${n.type}${n.item ? ` (${n.item})` : ""}`).join(", ")}</div>
              ) : null}
              {!it.first_response_at ? (
                <div className="text-xs text-amber-700">sem responsável há {hoursSince(it.created_at)} h</div>
              ) : null}
            </div>
            <div className="flex flex-wrap gap-1">
              {TRANSITIONS[it.status].map((to) => (
                <Button
                  key={to}
                  size="sm"
                  variant={to === "cancelled" ? "ghost" : "outline"}
                  disabled={busy === it.id}
                  onClick={() => transition(it.id, to)}
                >
                  {STATUS_LABEL[to]}
                </Button>
              ))}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
