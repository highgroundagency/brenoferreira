"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

const NEED_TYPES = ["food", "furniture", "appliance", "clothing", "health", "job", "training", "other"] as const;

export function PersonActions({
  personId,
  stage,
  reviewStatus,
  duplicateOf,
}: {
  personId: string;
  stage: string;
  reviewStatus: string;
  duplicateOf: string | null;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [needType, setNeedType] = useState<(typeof NEED_TYPES)[number]>("food");
  const [needText, setNeedText] = useState("");
  const [dupOf, setDupOf] = useState(duplicateOf ?? "");
  const [note, setNote] = useState("");

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
  const supabase = () => createClient();

  return (
    <Card>
      <CardHeader>
        <CardTitle>Ações da central</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        <div className="flex flex-wrap items-end gap-2">
          <div className="flex flex-col gap-1">
            <span className="text-xs">Nova necessidade (reexecuta o roteamento)</span>
            <Select value={needType} onChange={(e) => setNeedType(e.target.value as (typeof NEED_TYPES)[number])}>
              {NEED_TYPES.map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </Select>
          </div>
          <Input
            placeholder="detalhe (opcional)"
            value={needText}
            onChange={(e) => setNeedText(e.target.value)}
            className="w-56"
          />
          <Button
            variant="outline"
            disabled={busy}
            onClick={() =>
              run("Necessidade registrada", async () => {
                const { data: p } = await supabase()
                  .from("people")
                  .select("unit_id, household_id")
                  .eq("id", personId)
                  .single();
                return supabase()
                  .from("needs")
                  .insert({
                    unit_id: p?.unit_id as string,
                    person_id: personId,
                    household_id: p?.household_id ?? null,
                    need_type: needType,
                    raw_text: needText || null,
                    detected_by: "team",
                  });
              })
            }
          >
            Adicionar
          </Button>
        </div>

        <div className="flex flex-wrap items-end gap-2">
          <Input
            placeholder="anotação da central"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            className="w-72"
          />
          <Button
            variant="outline"
            disabled={busy || !note}
            onClick={() =>
              run("Anotação salva", async () => {
                const { data: p } = await supabase().from("people").select("unit_id").eq("id", personId).single();
                const { data: u } = await supabase().auth.getUser();
                const res = await supabase()
                  .from("person_events")
                  .insert({
                    unit_id: p?.unit_id as string,
                    person_id: personId,
                    event_type: "note",
                    actor_profile_id: u.user?.id ?? null,
                    payload: { note },
                  });
                if (!res.error) setNote("");
                return res;
              })
            }
          >
            Anotar
          </Button>
          <Button
            variant="outline"
            disabled={busy}
            onClick={() =>
              run("Pedido de dados registrado (prazo 15 dias)", async () => {
                const { data: p } = await supabase().from("people").select("unit_id").eq("id", personId).single();
                return supabase()
                  .from("person_events")
                  .insert({
                    unit_id: p?.unit_id as string,
                    person_id: personId,
                    event_type: "data_request",
                    payload: { channel: "central" },
                  });
              })
            }
          >
            Registrar pedido LGPD
          </Button>
        </div>

        {reviewStatus === "possible_duplicate" ? (
          <div className="flex flex-wrap items-end gap-2 rounded-md border border-amber-300 bg-amber-50 p-2">
            <span className="w-full text-xs">
              Telefone já cadastrado. É a mesma pessoa ou outra pessoa da mesma casa?
            </span>
            <Input
              placeholder="id da pessoa original"
              value={dupOf}
              onChange={(e) => setDupOf(e.target.value)}
              className="w-80"
            />
            <Button
              variant="destructive"
              size="sm"
              disabled={busy || !dupOf}
              onClick={() =>
                run("Marcada como duplicata", () =>
                  supabase().rpc("mark_duplicate", { p_person_id: personId, p_duplicate_of: dupOf }),
                )
              }
            >
              Marcar duplicata
            </Button>
            <Button
              size="sm"
              disabled={busy}
              onClick={() =>
                run("Pessoa distinta confirmada; opt-in enviado a quem atende", () =>
                  supabase().rpc("confirm_distinct_person", { p_person_id: personId }),
                )
              }
            >
              Mesma casa, pessoa diferente
            </Button>
          </div>
        ) : null}

        {stage !== "anonymized" ? (
          <div>
            <Button
              variant="ghost"
              size="sm"
              className="text-destructive"
              disabled={busy}
              onClick={() => {
                if (
                  window.confirm("Apagar nome, telefone, endereço e filhos desta pessoa? Isso não pode ser desfeito.")
                ) {
                  run("Pessoa anonimizada", () =>
                    supabase().rpc("anonymize_person", { p_person_id: personId, p_reason: "request" }),
                  );
                }
              }}
            >
              Anonimizar (pedido do titular)
            </Button>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
