"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { DELIVERY_LABEL } from "./person-extras";

export type DeliveryRow = {
  id: string;
  person_id: string;
  kind: string;
  item_code: string | null;
  status: string;
  scheduled_for: string;
  address_snapshot: {
    street?: string;
    number?: string;
    complement?: string;
    reference?: string;
    phone?: string;
    kind?: string;
  } | null;
  people_contacts: { full_name: string } | null;
  neighborhoods: { name: string } | null;
};
const NEXT: Record<string, string[]> = {
  scheduled: ["picking", "packed", "out_for_delivery", "cancelled"],
  picking: ["packed", "cancelled"],
  packed: ["out_for_delivery", "cancelled"],
  out_for_delivery: ["delivered", "failed"],
  failed: ["scheduled", "out_for_delivery", "cancelled"],
};

export function DeliveryList({ rows, canOpenRecord }: { rows: DeliveryRow[]; canOpenRecord: boolean }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  async function go(id: string, to: string) {
    const note =
      to === "delivered" || to === "failed"
        ? (window.prompt(to === "delivered" ? "Quem recebeu?" : "Motivo da falha:") ?? undefined)
        : undefined;
    setBusy(id);
    const { error } = await createClient().rpc("delivery_transition", { p_delivery_id: id, p_to: to, p_note: note });
    setBusy(null);
    if (error) toast.error(error.message);
    else router.refresh();
  }
  if (rows.length === 0) return <p className="text-sm text-muted-foreground">Nenhuma entrega aberta.</p>;
  return (
    <div className="flex flex-col gap-2">
      {rows.map((d) => (
        <Card key={d.id}>
          <CardContent className="flex flex-col gap-1 p-3 text-sm">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span className="font-medium">
                {canOpenRecord ? (
                  <Link className="underline" href={`/central/pessoas/${d.person_id}`}>
                    {d.people_contacts?.full_name ?? "—"}
                  </Link>
                ) : (
                  (d.people_contacts?.full_name ?? "—")
                )}{" "}
                <span className="text-muted-foreground">· {d.neighborhoods?.name}</span>
              </span>
              <div className="flex gap-1">
                <Badge variant="secondary">
                  {d.kind === "basic_food"
                    ? "Cesta básica"
                    : d.kind === "reward"
                      ? `Prêmio: ${d.item_code}`
                      : `Item: ${d.item_code}`}
                </Badge>
                <Badge variant={d.status === "out_for_delivery" ? "warning" : "outline"}>
                  {DELIVERY_LABEL[d.status]}
                </Badge>
              </div>
            </div>
            <div>
              {d.scheduled_for} ·{" "}
              {[d.address_snapshot?.street, d.address_snapshot?.number, d.address_snapshot?.complement]
                .filter(Boolean)
                .join(", ")}
              {d.address_snapshot?.reference ? ` — ref.: ${d.address_snapshot.reference}` : ""}
              {d.address_snapshot?.phone ? ` · ${d.address_snapshot.phone}` : ""}
            </div>
            <div className="flex flex-wrap gap-1">
              {(NEXT[d.status] ?? []).map((to) => (
                <Button
                  key={to}
                  size="sm"
                  variant={to === "cancelled" ? "ghost" : "outline"}
                  disabled={busy === d.id}
                  onClick={() => go(d.id, to)}
                >
                  {DELIVERY_LABEL[to]}
                </Button>
              ))}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
