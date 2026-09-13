"use client";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { STAGE_LABEL } from "@/lib/domain/referral-state";
import { createClient } from "@/lib/supabase/client";

type Row = {
  id: string;
  created_at: string;
  stage: string;
  review_status: string;
  has_basic_need: boolean;
  children_count: number;
  people_contacts: { full_name: string } | null;
  neighborhoods: { name: string } | null;
  needs: { need_type: string; status: string }[];
};

const NEED: Record<string, string> = {
  food: "alimento",
  furniture: "móvel",
  appliance: "eletrodoméstico",
  clothing: "roupas",
  health: "saúde",
  job: "trabalho",
  training: "curso",
  other: "outro",
};

/** Chegadas em tempo quase real: polling a cada 30 s (sem Realtime na Fase 1). */
export function Feed() {
  const [rows, setRows] = useState<Row[]>([]);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const load = useCallback(async () => {
    const supabase = createClient();
    const { data } = await supabase
      .from("people")
      .select(
        "id, created_at, stage, review_status, has_basic_need, children_count, people_contacts(full_name), neighborhoods(name), needs(need_type, status)",
      )
      .neq("stage", "anonymized")
      .order("created_at", { ascending: false })
      .limit(50);
    setRows((data ?? []) as unknown as Row[]);
    setUpdatedAt(new Date());
  }, []);
  useEffect(() => {
    load();
    const t = setInterval(load, 30_000);
    return () => clearInterval(t);
  }, [load]);

  return (
    <div className="flex flex-col gap-2">
      <p className="text-xs text-muted-foreground">
        Atualizado {updatedAt ? updatedAt.toLocaleTimeString("pt-BR") : "…"} · a cada 30 s
      </p>
      {rows.length === 0 ? <p className="text-sm text-muted-foreground">Nenhum cadastro ainda.</p> : null}
      {rows.map((r) => {
        const first = r.people_contacts?.full_name?.split(" ")[0] ?? "Pessoa";
        const needs = r.needs.filter((n) => n.status !== "cancelled").map((n) => NEED[n.need_type] ?? n.need_type);
        return (
          <Link key={r.id} href={`/central/pessoas/${r.id}`}>
            <Card className="hover:bg-accent">
              <CardContent className="flex flex-col gap-1 p-3">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium">
                    Mais uma pessoa aceitou Jesus no {r.neighborhoods?.name ?? "?"} — {first}
                  </span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {new Date(r.created_at).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" })}
                  </span>
                </div>
                <div className="flex flex-wrap gap-1">
                  {needs.length ? (
                    <Badge variant="info">precisa: {needs.join(", ")}</Badge>
                  ) : (
                    <Badge variant="outline">sem necessidade declarada</Badge>
                  )}
                  {r.children_count > 0 ? <Badge variant="secondary">{r.children_count} filho(s)</Badge> : null}
                  <Badge variant="secondary">{STAGE_LABEL[r.stage] ?? r.stage}</Badge>
                  {r.review_status === "possible_duplicate" ? (
                    <Badge variant="destructive">telefone repetido</Badge>
                  ) : null}
                </div>
              </CardContent>
            </Card>
          </Link>
        );
      })}
    </div>
  );
}
