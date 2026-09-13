"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

/** Lê um CSV (; ou ,) no navegador e chama a RPC de importação com as linhas como JSON. */
export function parseCsv(text: string): Record<string, string>[] {
  const lines = text
    .replace(/^﻿/, "")
    .split(/\r?\n/)
    .filter((l) => l.trim());
  if (lines.length < 2) return [];
  const sep = (lines[0].match(/;/g) ?? []).length >= (lines[0].match(/,/g) ?? []).length ? ";" : ",";
  const split = (l: string) => {
    const out: string[] = [];
    let cur = "";
    let q = false;
    for (let i = 0; i < l.length; i++) {
      const ch = l[i];
      if (ch === '"') {
        if (q && l[i + 1] === '"') {
          cur += '"';
          i++;
        } else q = !q;
      } else if (ch === sep && !q) {
        out.push(cur);
        cur = "";
      } else cur += ch;
    }
    out.push(cur);
    return out.map((s) => s.trim());
  };
  const headers = split(lines[0]).map((h) => h.toLowerCase().replace(/\s+/g, "_"));
  return lines.slice(1).map((l) => Object.fromEntries(split(l).map((v, i) => [headers[i] ?? `col${i}`, v])));
}

export function CsvImport({
  rpc,
  expected,
  hint,
}: {
  rpc: "import_companies" | "import_legacy_people";
  expected: string[];
  hint: string;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{
    imported: number;
    rejected: number;
    log: { row: number; error: string }[];
  } | null>(null);
  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const rows = parseCsv(await file.text());
    if (!rows.length) return toast.error("CSV vazio ou sem cabeçalho.");
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.rpc(rpc, { p_rows: rows as never, p_file_name: file.name });
    setBusy(false);
    if (error) return toast.error(error.message);
    setResult(data as never);
    toast.success("Importação concluída.");
    router.refresh();
  }
  return (
    <div className="flex flex-col gap-2 rounded-md border p-3 text-sm">
      <div className="text-xs text-muted-foreground">
        Colunas: <code>{expected.join(", ")}</code>. {hint}
      </div>
      <input type="file" accept=".csv,text/csv" onChange={onFile} disabled={busy} />
      {result ? (
        <div>
          importadas {result.imported} · rejeitadas {result.rejected}
          {result.log?.length ? (
            <ul className="mt-1 list-disc pl-5 text-xs text-destructive">
              {result.log.slice(0, 20).map((l) => (
                <li key={l.row}>
                  linha {l.row}: {l.error}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
      <Button variant="ghost" size="sm" onClick={() => setResult(null)} className="self-start">
        limpar
      </Button>
    </div>
  );
}
