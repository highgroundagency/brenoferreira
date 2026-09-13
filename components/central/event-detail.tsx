"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";
import { EVENT_KIND, EVENT_STATUS } from "./event-manager";

type Ev = {
  id: string;
  name: string;
  kind: string;
  status: string;
  starts_at: string | null;
  location: string | null;
  capacity: number | null;
  target_segment: Record<string, unknown>;
  notes: string | null;
};
type Inv = {
  id: string;
  person_id: string;
  rsvp: string | null;
  checkin_code: string | null;
  checked_in_at: string | null;
  full_name: string;
  neighborhood: string;
};

export function EventDetail({
  event,
  audienceSize,
  invitations,
}: {
  event: Ev;
  audienceSize: number;
  invitations: Inv[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [code, setCode] = useState("");
  const supabase = () => createClient();
  const yes = invitations.filter((i) => i.rsvp === "yes").length;
  const checked = invitations.filter((i) => i.checked_in_at).length;

  async function invite() {
    setBusy(true);
    const { data, error } = await supabase().rpc("invite_to_event", { p_event_id: event.id, p_limit: 1000 });
    setBusy(false);
    if (error) return toast.error(error.message);
    const r = data as { invited: number; skipped: number };
    toast.success(
      `${r.invited} convite(s) enfileirado(s); ${r.skipped} pulado(s) por falta de consentimento ou já convidados.`,
    );
    router.refresh();
  }
  async function checkin() {
    if (!code) return;
    const { data, error } = await supabase().rpc("event_checkin", { p_code: code.trim() });
    if (error) return toast.error(error.message);
    const r = data as { already: boolean; name: string | null; event: string };
    toast.success(r.already ? `${r.name ?? "Pessoa"} já tinha entrado.` : `Check-in de ${r.name ?? "pessoa"} feito.`);
    setCode("");
    router.refresh();
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-4">
      <div>
        <Link href="/central/eventos" className="text-sm underline">
          ← eventos
        </Link>
        <h1 className="text-xl font-bold">{event.name}</h1>
        <div className="flex flex-wrap gap-1">
          <Badge variant="secondary">{EVENT_KIND[event.kind] ?? event.kind}</Badge>
          <Badge variant="outline">{EVENT_STATUS[event.status] ?? event.status}</Badge>
          {event.starts_at ? (
            <span className="text-sm text-muted-foreground">{new Date(event.starts_at).toLocaleString("pt-BR")}</span>
          ) : null}
          {event.location ? <span className="text-sm text-muted-foreground">· {event.location}</span> : null}
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Convites</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          <div className="flex flex-wrap items-center gap-3">
            <span>
              público-alvo: <strong>{audienceSize}</strong>
            </span>
            <span>
              convidados: <strong>{invitations.length}</strong>
            </span>
            <span>
              confirmados: <strong>{yes}</strong>
            </span>
            <span>
              presentes: <strong>{checked}</strong>
            </span>
            <Button size="sm" onClick={invite} disabled={busy}>
              Disparar convites
            </Button>
          </div>
          <p className="text-xs text-muted-foreground">
            Segmento: <code>{JSON.stringify(event.target_segment)}</code>. Só recebe quem consentiu convites (botão na
            jornada) e segue com WhatsApp ativo.
          </p>
          <div className="flex items-end gap-2">
            <Input
              placeholder="código de entrada"
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              className="w-48"
            />
            <Button size="sm" variant="outline" onClick={checkin}>
              Check-in
            </Button>
          </div>
        </CardContent>
      </Card>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b text-left text-muted-foreground">
              <th className="py-1 pr-2">Pessoa</th>
              <th className="py-1 pr-2">Bairro</th>
              <th className="py-1 pr-2">RSVP</th>
              <th className="py-1 pr-2">Código</th>
              <th className="py-1">Entrada</th>
            </tr>
          </thead>
          <tbody>
            {invitations.map((i) => (
              <tr key={i.id} className="border-b">
                <td className="py-1 pr-2">
                  <Link className="underline" href={`/central/pessoas/${i.person_id}`}>
                    {i.full_name}
                  </Link>
                </td>
                <td className="py-1 pr-2">{i.neighborhood}</td>
                <td className="py-1 pr-2">
                  {i.rsvp === "yes" ? "vem" : i.rsvp === "no" ? "não vem" : i.rsvp === "maybe" ? "talvez" : "—"}
                </td>
                <td className="py-1 pr-2 font-mono text-xs">{i.checkin_code}</td>
                <td className="py-1">
                  {i.checked_in_at ? new Date(i.checked_in_at).toLocaleTimeString("pt-BR") : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
