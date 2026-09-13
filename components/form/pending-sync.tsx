"use client";
import { useEffect } from "react";
import { toast } from "sonner";
import { flushQueue, usePendingCount } from "@/lib/offline/queue";
import { createClient } from "@/lib/supabase/client";

/** Banner + sincronização automática da fila offline (abertura do app e evento online). */
export function PendingSync() {
  const count = usePendingCount();
  useEffect(() => {
    const supabase = createClient();
    const run = async () => {
      const { sent } = await flushQueue(supabase);
      if (sent > 0) toast.success(`${sent} cadastro(s) enviado(s).`);
    };
    run();
    window.addEventListener("online", run);
    return () => window.removeEventListener("online", run);
  }, []);
  if (count === 0) return null;
  return (
    <div className="mb-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-sm text-amber-900">
      {count} cadastro(s) salvo(s) no aparelho — envia quando houver sinal.
    </div>
  );
}
