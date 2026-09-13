import { redirect } from "next/navigation";
import { getProfile } from "@/lib/supabase/server";
import { homeFor, type Role } from "./roles";

/** Server-side: exige perfil ativo com um dos papéis; senão redireciona para a home do papel (ou login). */
export async function requireRole(allowed: Role[]) {
  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (!profile.active) redirect("/login?inactive=1");
  if (!allowed.includes(profile.role as Role)) redirect(homeFor(profile.role as Role));
  return profile;
}
