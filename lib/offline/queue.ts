"use client";
import type { SupabaseClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import type { Json } from "@/lib/database.types";
import { getDb, type PendingItem, type PendingKind } from "./db";

export async function enqueue(id: string, kind: PendingKind, payload: Record<string, unknown>) {
  await getDb().pending_registrations.put({ id, kind, payload, created_at: Date.now(), attempts: 0 });
}

export async function pendingCount() {
  try {
    return await getDb().pending_registrations.count();
  } catch {
    return 0;
  }
}

/** Erros de rede/timeout: o item volta para a fila. Erros de regra (4xx da RPC) descartam com registro do motivo. */
export function isNetworkError(err: unknown): boolean {
  const msg = String((err as { message?: string })?.message ?? err ?? "").toLowerCase();
  return msg.includes("fetch") || msg.includes("network") || msg.includes("timeout") || msg.includes("failed to");
}

let flushing = false;
/** Reenvia tudo que está na fila (chamado ao abrir o app e no evento `online`). */
export async function flushQueue(supabase: SupabaseClient): Promise<{ sent: number; failed: number }> {
  if (flushing) return { sent: 0, failed: 0 };
  flushing = true;
  let sent = 0;
  let failed = 0;
  try {
    const items: PendingItem[] = await getDb().pending_registrations.orderBy("created_at").toArray();
    for (const item of items) {
      const { error } =
        item.kind === "register"
          ? await supabase.rpc("register_person", { payload: item.payload as unknown as Json })
          : await supabase.rpc("record_decision_tally", {
              p_neighborhood_id: item.payload.neighborhood_id as string,
              p_minor: Boolean(item.payload.minor),
            });
      if (!error) {
        await getDb().pending_registrations.delete(item.id);
        sent++;
      } else if (isNetworkError(error)) {
        await getDb().pending_registrations.update(item.id, { attempts: item.attempts + 1, last_error: error.message });
        failed++;
        break; // sem rede: para aqui
      } else {
        // erro de regra: mantém para a pessoa ver o motivo, não tenta em loop
        await getDb().pending_registrations.update(item.id, { attempts: item.attempts + 1, last_error: error.message });
        failed++;
      }
    }
  } finally {
    flushing = false;
  }
  return { sent, failed };
}

export function usePendingCount(): number {
  const [count, setCount] = useState(0);
  useEffect(() => {
    let alive = true;
    const refresh = () => pendingCount().then((c) => alive && setCount(c));
    refresh();
    const t = setInterval(refresh, 5000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);
  return count;
}
