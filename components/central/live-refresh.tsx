"use client";
import { useRealtimeRefresh } from "@/lib/hooks/use-realtime-refresh";

export function LiveRefresh({ tables }: { tables: string[] }) {
  useRealtimeRefresh(tables);
  return null;
}
