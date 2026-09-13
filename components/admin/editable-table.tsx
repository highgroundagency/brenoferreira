"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";

export type Column = {
  key: string;
  label: string;
  type?: "text" | "number" | "boolean" | "json";
  readonly?: boolean;
  width?: string;
};

/**
 * Tabela editável genérica para catálogos (routing_rules, journey_steps, reward_rules, content_assets...).
 * Linhas globais (unit_id null) são só leitura para unit_admin: "Copiar para a unidade" cria a versão local.
 */
export function EditableTable({
  table,
  rows,
  columns,
  unitId,
  canEditGlobal,
  newRowDefaults,
}: {
  table: string;
  rows: Record<string, unknown>[];
  columns: Column[];
  unitId: string | null;
  canEditGlobal: boolean;
  newRowDefaults?: Record<string, unknown>;
}) {
  const router = useRouter();
  const [drafts, setDrafts] = useState<Record<string, Record<string, unknown>>>({});
  const [busy, setBusy] = useState(false);
  const supabase = () => createClient();

  function edit(id: string, key: string, value: unknown) {
    setDrafts((d) => ({ ...d, [id]: { ...(d[id] ?? {}), [key]: value } }));
  }
  function parse(col: Column, raw: string): unknown {
    if (col.type === "number") return Number(raw);
    if (col.type === "json") {
      try {
        return JSON.parse(raw);
      } catch {
        return undefined;
      }
    }
    return raw;
  }
  async function save(id: string) {
    const patch = drafts[id];
    if (!patch) return;
    if (Object.values(patch).some((v) => v === undefined)) {
      toast.error("JSON inválido.");
      return;
    }
    setBusy(true);
    // biome-ignore lint/suspicious/noExplicitAny: tabela dinâmica
    const { error } = await (supabase().from(table as any) as any).update(patch).eq("id", id);
    setBusy(false);
    if (error) toast.error(error.message);
    else {
      setDrafts((d) => {
        const { [id]: _, ...rest } = d;
        return rest;
      });
      toast.success("Salvo.");
      router.refresh();
    }
  }
  async function copyToUnit(row: Record<string, unknown>) {
    const { id: _id, created_at: _c, updated_at: _u, ...rest } = row;
    setBusy(true);
    // biome-ignore lint/suspicious/noExplicitAny: tabela dinâmica
    const { error } = await (supabase().from(table as any) as any).insert({ ...rest, unit_id: unitId });
    setBusy(false);
    if (error) toast.error(error.message);
    else {
      toast.success("Copiado para a unidade; a versão local passa a valer.");
      router.refresh();
    }
  }
  async function addRow() {
    setBusy(true);
    // biome-ignore lint/suspicious/noExplicitAny: tabela dinâmica
    const { error } = await (supabase().from(table as any) as any).insert({
      ...(newRowDefaults ?? {}),
      unit_id: canEditGlobal && !unitId ? null : unitId,
    });
    setBusy(false);
    if (error) toast.error(error.message);
    else router.refresh();
  }
  async function remove(id: string) {
    if (!window.confirm("Excluir esta linha?")) return;
    // biome-ignore lint/suspicious/noExplicitAny: tabela dinâmica
    const { error } = await (supabase().from(table as any) as any).delete().eq("id", id);
    if (error) toast.error(error.message);
    else router.refresh();
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b text-left text-muted-foreground">
            <th className="py-1 pr-2">escopo</th>
            {columns.map((c) => (
              <th key={c.key} className="py-1 pr-2">
                {c.label}
              </th>
            ))}
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const id = String(row.id);
            const isGlobal = row.unit_id == null;
            const editable = isGlobal ? canEditGlobal : true;
            return (
              <tr key={id} className="border-b align-top">
                <td className="py-1 pr-2 text-xs text-muted-foreground">{isGlobal ? "global" : "unidade"}</td>
                {columns.map((c) => {
                  const value = drafts[id]?.[c.key] ?? row[c.key];
                  if (c.type === "boolean") {
                    return (
                      <td key={c.key} className="py-1 pr-2">
                        <input
                          type="checkbox"
                          checked={Boolean(value)}
                          disabled={!editable || c.readonly}
                          onChange={(e) => edit(id, c.key, e.target.checked)}
                        />
                      </td>
                    );
                  }
                  const display = c.type === "json" ? JSON.stringify(value ?? null) : String(value ?? "");
                  return (
                    <td key={c.key} className="py-1 pr-2">
                      {editable && !c.readonly ? (
                        <Input
                          className={`h-8 ${c.width ?? "min-w-32"}`}
                          defaultValue={display}
                          onChange={(e) => edit(id, c.key, parse(c, e.target.value))}
                        />
                      ) : (
                        <span className="text-muted-foreground">{display}</span>
                      )}
                    </td>
                  );
                })}
                <td className="whitespace-nowrap py-1">
                  {editable ? (
                    <>
                      <Button size="sm" variant="outline" disabled={busy || !drafts[id]} onClick={() => save(id)}>
                        salvar
                      </Button>{" "}
                      <Button size="sm" variant="ghost" disabled={busy} onClick={() => remove(id)}>
                        excluir
                      </Button>
                    </>
                  ) : unitId ? (
                    <Button size="sm" variant="outline" disabled={busy} onClick={() => copyToUnit(row)}>
                      copiar para a unidade
                    </Button>
                  ) : null}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {newRowDefaults ? (
        <Button className="mt-2" size="sm" variant="outline" disabled={busy} onClick={addRow}>
          + nova linha
        </Button>
      ) : null}
    </div>
  );
}
