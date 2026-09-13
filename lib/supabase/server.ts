import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/lib/database.types";
import { requireSupabaseEnv } from "@/lib/supabase/env";

/** Cliente de servidor (Server Components, Route Handlers, Server Actions). */
export async function createClient() {
  const cookieStore = await cookies();
  const { url, key } = requireSupabaseEnv();
  return createServerClient<Database>(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // chamado de um Server Component: o middleware renova a sessão
        }
      },
    },
  });
}

export type Role = Database["public"]["Tables"]["profiles"]["Row"]["role"];

/** Perfil do usuário logado (ou null). */
export async function getProfile() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  const { data } = await supabase
    .from("profiles")
    .select("id, unit_id, full_name, role, active")
    .eq("id", user.id)
    .maybeSingle();
  return data;
}
