import { AppShell } from "@/components/app-shell";
import { requireRole } from "@/lib/auth/require-role";
import { CENTRAL_ROLES } from "@/lib/auth/roles";
import { CentralNav } from "./central-nav";

export default async function CentralLayout({ children }: { children: React.ReactNode }) {
  const profile = await requireRole(CENTRAL_ROLES);
  return (
    <AppShell profile={profile}>
      <CentralNav />
      {children}
    </AppShell>
  );
}
