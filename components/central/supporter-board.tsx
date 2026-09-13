"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

type Supporter = {
  id: string;
  person_id: string | null;
  name: string;
  origin: string;
  status: string;
  contribution_plan: string | null;
  monthly_amount: number | null;
  card_code: string | null;
  since: string | null;
};
type Candidate = { person_id: string; full_name: string; rule_id: string; rule_name: string };
type Funnel = { status: string; total: number; monthly_amount: number };
type Contribution = { id: string; amount: number; paid_on: string; method: string; supporter_id: string };

const STATUS: Record<string, string> = {
  prospect: "Possível",
  invited: "Convidado",
  attended: "Participou",
  active: "Mantenedor",
  paused: "Pausado",
  declined: "Recusou",
};
const NEXT: Record<string, string[]> = {
  prospect: ["invited", "declined"],
  invited: ["attended", "active", "declined"],
  attended: ["active", "declined"],
  active: ["paused"],
  paused: ["active"],
};

export function SupporterBoard({
  supporters,
  candidates,
  funnel,
  contributions,
}: {
  supporters: Supporter[];
  candidates: Candidate[];
  funnel: Funnel[];
  contributions: Contribution[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [amount, setAmount] = useState<Record<string, string>>({});
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
  const totalByStatus = new Map(funnel.map((f) => [f.status, f]));
  const contribBySupporter = new Map<string, number>();
  for (const c of contributions)
    contribBySupporter.set(c.supporter_id, (contribBySupporter.get(c.supporter_id) ?? 0) + Number(c.amount));

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <h1 className="text-xl font-bold">Mantenedores</h1>
      <div className="flex flex-wrap gap-2 text-sm">
        {Object.entries(STATUS).map(([k, label]) => (
          <div key={k} className="rounded-md bg-muted px-3 py-2">
            <div className="text-xs text-muted-foreground">{label}</div>
            <div className="text-xl font-bold tabular-nums">{totalByStatus.get(k)?.total ?? 0}</div>
            {k === "active" ? (
              <div className="text-xs">
                R$ {Number(totalByStatus.get(k)?.monthly_amount ?? 0).toLocaleString("pt-BR")}/mês
              </div>
            ) : null}
          </div>
        ))}
      </div>

      {candidates.length ? (
        <Card>
          <CardHeader>
            <CardTitle>Pessoas elegíveis ({candidates.length})</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-1 text-sm">
            {candidates.slice(0, 30).map((c) => (
              <div key={c.person_id} className="flex flex-wrap items-center gap-2 border-b py-1 last:border-0">
                <Link className="underline" href={`/central/pessoas/${c.person_id}`}>
                  {c.full_name}
                </Link>
                <Badge variant="outline">{c.rule_name}</Badge>
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() =>
                    run("Adicionado ao funil", () =>
                      supabase().rpc("create_supporter", { p_person_id: c.person_id, p_status: "prospect" }),
                    )
                  }
                >
                  adicionar ao funil
                </Button>
              </div>
            ))}
          </CardContent>
        </Card>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle>Funil</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {supporters.map((s) => (
            <div key={s.id} className="flex flex-wrap items-center gap-2 border-b py-1 last:border-0">
              {s.person_id ? (
                <Link className="underline" href={`/central/pessoas/${s.person_id}`}>
                  {s.name}
                </Link>
              ) : (
                <span>{s.name}</span>
              )}
              <Badge variant={s.status === "active" ? "success" : "outline"}>{STATUS[s.status] ?? s.status}</Badge>
              {s.origin === "external" ? <Badge variant="secondary">externo</Badge> : null}
              {s.monthly_amount ? (
                <span className="text-xs">R$ {Number(s.monthly_amount).toLocaleString("pt-BR")}/mês</span>
              ) : null}
              {contribBySupporter.get(s.id) ? (
                <span className="text-xs text-muted-foreground">
                  recebido: R$ {contribBySupporter.get(s.id)?.toLocaleString("pt-BR")}
                </span>
              ) : null}
              {s.card_code ? (
                <a
                  className="font-mono text-xs underline"
                  href={`/carteirinha/${s.card_code}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {s.card_code}
                </a>
              ) : null}
              {(NEXT[s.status] ?? []).map((to) => (
                <Button
                  key={to}
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() =>
                    run(`Status: ${STATUS[to]}`, () =>
                      supabase().rpc("supporter_transition", {
                        p_supporter_id: s.id,
                        p_to: to,
                        p_plan: to === "active" ? "mensal" : undefined,
                        p_amount: to === "active" && amount[s.id] ? Number(amount[s.id]) : undefined,
                      }),
                    )
                  }
                >
                  {STATUS[to]}
                </Button>
              ))}
              {s.status !== "active" ? (
                <Input
                  placeholder="R$/mês"
                  className="h-8 w-24"
                  value={amount[s.id] ?? ""}
                  onChange={(e) => setAmount({ ...amount, [s.id]: e.target.value })}
                />
              ) : null}
              {s.status === "active" ? (
                <Button
                  size="sm"
                  variant="outline"
                  disabled={busy}
                  onClick={() => {
                    const v = window.prompt("Valor recebido (R$):");
                    if (v)
                      run("Contribuição registrada", () =>
                        supabase().rpc("record_contribution", {
                          p_supporter_id: s.id,
                          p_amount: Number(v.replace(",", ".")),
                          p_method: "pix",
                        }),
                      );
                  }}
                >
                  registrar contribuição
                </Button>
              ) : null}
            </div>
          ))}
          {supporters.length === 0 ? <p className="text-muted-foreground">Ninguém no funil ainda.</p> : null}
        </CardContent>
      </Card>
      <NewExternalSupporter />
    </div>
  );
}

function NewExternalSupporter() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [plan, setPlan] = useState("mensal");
  return (
    <Card>
      <CardHeader>
        <CardTitle>Mantenedor externo (não veio pelo Transtornar)</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-wrap items-end gap-2">
        <Input placeholder="nome" value={name} onChange={(e) => setName(e.target.value)} className="w-56" />
        <Input placeholder="telefone" value={phone} onChange={(e) => setPhone(e.target.value)} className="w-44" />
        <Select value={plan} onChange={(e) => setPlan(e.target.value)} className="w-36">
          <option value="mensal">mensal</option>
          <option value="pontual">pontual</option>
        </Select>
        <Button
          variant="outline"
          onClick={async () => {
            const { error } = await createClient().rpc("create_supporter", {
              p_person_id: undefined,
              p_status: "prospect",
              p_external: { name, phone } as never,
            });
            if (error) toast.error(error.message);
            else {
              setName("");
              setPhone("");
              toast.success("Mantenedor externo criado.");
              router.refresh();
            }
          }}
          disabled={!name}
        >
          Adicionar
        </Button>
      </CardContent>
    </Card>
  );
}
