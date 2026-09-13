"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

export type EventRow = {
  id: string;
  name: string;
  kind: string;
  status: string;
  starts_at: string | null;
  location: string | null;
  capacity: number | null;
  threshold_reached: boolean;
  neighborhood_id: string | null;
  target_segment: Record<string, unknown>;
  notes: string | null;
};
export const EVENT_KIND: Record<string, string> = {
  neighborhood: "Bairro",
  business: "Empresários",
  supporter_pitch: "Apresentação do modelo",
  training: "Capacitação",
  other: "Outro",
};
export const EVENT_STATUS: Record<string, string> = {
  draft: "Rascunho",
  planned: "Planejado",
  inviting: "Convidando",
  done: "Realizado",
  cancelled: "Cancelado",
};

/** Cria eventos e edita data/local/status; o gatilho por bairro já cria rascunhos automaticamente. */
export function EventManager({
  events,
  neighborhoods,
}: {
  events: EventRow[];
  neighborhoods: { id: string; name: string }[];
}) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [kind, setKind] = useState("neighborhood");
  const [nbh, setNbh] = useState("");
  const [busy, setBusy] = useState(false);
  const supabase = () => createClient();
  const nbhName = new Map(neighborhoods.map((n) => [n.id, n.name]));

  async function create() {
    if (!name) return toast.error("Dê um nome ao evento.");
    setBusy(true);
    const segment =
      kind === "neighborhood" && nbh
        ? { neighborhood_ids: [nbh] }
        : kind === "business"
          ? { profile_segments: ["business"] }
          : {};
    const { error } = await supabase().rpc("create_event", {
      p_name: name,
      p_kind: kind,
      p_neighborhood_id: kind === "neighborhood" && nbh ? nbh : undefined,
      p_target_segment: segment as never,
    });
    setBusy(false);
    if (error) toast.error(error.message);
    else {
      setName("");
      toast.success("Evento criado.");
      router.refresh();
    }
  }
  async function patch(id: string, patchData: Record<string, unknown>) {
    const { error } = await supabase()
      .from("events")
      .update(patchData as never)
      .eq("id", id);
    if (error) toast.error(error.message);
    else router.refresh();
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardContent className="flex flex-wrap items-end gap-2 p-3">
          <div className="flex flex-col gap-1">
            <Label>Novo evento</Label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Nome do evento"
              className="w-64"
            />
          </div>
          <Select value={kind} onChange={(e) => setKind(e.target.value)} className="w-52">
            {Object.entries(EVENT_KIND).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </Select>
          {kind === "neighborhood" ? (
            <Select value={nbh} onChange={(e) => setNbh(e.target.value)} className="w-48">
              <option value="">bairro…</option>
              {neighborhoods.map((n) => (
                <option key={n.id} value={n.id}>
                  {n.name}
                </option>
              ))}
            </Select>
          ) : null}
          <Button onClick={create} disabled={busy}>
            Criar
          </Button>
        </CardContent>
      </Card>

      {events.map((e) => (
        <Card key={e.id}>
          <CardContent className="flex flex-col gap-2 p-3 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <a className="font-medium underline" href={`/central/eventos/${e.id}`}>
                {e.name}
              </a>
              <Badge variant="secondary">{EVENT_KIND[e.kind] ?? e.kind}</Badge>
              <Badge variant={e.status === "inviting" ? "warning" : e.status === "done" ? "success" : "outline"}>
                {EVENT_STATUS[e.status] ?? e.status}
              </Badge>
              {e.threshold_reached ? <Badge variant="success">meta do bairro atingida</Badge> : null}
              {e.neighborhood_id ? (
                <span className="text-muted-foreground">{nbhName.get(e.neighborhood_id)}</span>
              ) : null}
            </div>
            <div className="flex flex-wrap items-end gap-2">
              <Input
                type="datetime-local"
                defaultValue={e.starts_at ? new Date(e.starts_at).toISOString().slice(0, 16) : ""}
                onBlur={(ev) => ev.target.value && patch(e.id, { starts_at: new Date(ev.target.value).toISOString() })}
                className="w-56"
              />
              <Input
                defaultValue={e.location ?? ""}
                placeholder="local"
                onBlur={(ev) => patch(e.id, { location: ev.target.value })}
                className="w-56"
              />
              <Input
                type="number"
                defaultValue={e.capacity ?? ""}
                placeholder="capacidade"
                onBlur={(ev) => patch(e.id, { capacity: ev.target.value ? Number(ev.target.value) : null })}
                className="w-32"
              />
              <Select
                defaultValue={e.status}
                onChange={(ev) => patch(e.id, { status: ev.target.value })}
                className="w-40"
              >
                {Object.entries(EVENT_STATUS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v}
                  </option>
                ))}
              </Select>
            </div>
            {e.notes ? <p className="text-xs text-muted-foreground">{e.notes}</p> : null}
          </CardContent>
        </Card>
      ))}
      {events.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          Nenhum evento ainda. O sistema cria um rascunho sozinho quando um bairro atinge a meta.
        </p>
      ) : null}
    </div>
  );
}
