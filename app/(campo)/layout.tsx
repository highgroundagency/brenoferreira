import { AppShell } from "@/components/app-shell";
import { requireRole } from "@/lib/auth/require-role";
import { CAMPO_ROLES } from "@/lib/auth/roles";

export default async function CampoLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireRole(CAMPO_ROLES);
  return <AppShell profile={profile}>{children}</AppShell>;
}
