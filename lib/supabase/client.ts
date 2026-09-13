"use client";
import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/database.types";
import { requireSupabaseEnv } from "@/lib/supabase/env";

let client: ReturnType<typeof createBrowserClient<Database>> | undefined;

/** Cliente do navegador (singleton). Usa a chave pública; toda escrita passa por RPCs com RLS. */
export function createClient() {
  if (!client) {
    const { url, key } = requireSupabaseEnv();
    client = createBrowserClient<Database>(url, key);
  }
  return client;
}
