"use client";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { createClient } from "@/lib/supabase/client";

/** Recarrega a página quando houver mudança nas tabelas (Realtime); o polling continua como fallback. */
export function useRealtimeRefresh(tables: string[], fallbackMs = 30_000) {
  const router = useRouter();
  const key = tables.join(",");
  // biome-ignore lint/correctness/useExhaustiveDependencies: `key` representa `tables` (array nova a cada render)
  useEffect(() => {
    const supabase = createClient();
    let channel = supabase.channel(`refresh:${key}`);
    for (const table of tables) {
      channel = channel.on("postgres_changes", { event: "*", schema: "public", table }, () => router.refresh());
    }
    channel.subscribe();
    const t = setInterval(() => router.refresh(), fallbackMs);
    return () => {
      supabase.removeChannel(channel);
      clearInterval(t);
    };
  }, [router, key, fallbackMs]);
}
