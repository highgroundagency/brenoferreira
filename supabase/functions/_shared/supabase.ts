import { createClient } from "npm:@supabase/supabase-js@2";

/** Cliente com service_role (bypassa RLS). Só nas Edge Functions; nunca no navegador. */
export function serviceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
