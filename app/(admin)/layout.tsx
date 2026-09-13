import { AppShell } from "@/components/app-shell";
import { requireRole } from "@/lib/auth/require-role";
import { ADMIN_ROLES } from "@/lib/auth/roles";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireRole(ADMIN_ROLES);
  return <AppShell profile={profile}>{children}</AppShell>;
}
