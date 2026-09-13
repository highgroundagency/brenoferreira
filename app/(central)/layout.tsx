import { AppShell } from "@/components/app-shell";
import { requireRole } from "@/lib/auth/require-role";
import { CENTRAL_ROLES } from "@/lib/auth/roles";

export default async function CentralLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireRole(CENTRAL_ROLES);
  return <AppShell profile={profile}>{children}</AppShell>;
}
