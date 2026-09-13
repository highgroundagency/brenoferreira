import { MfaSetup } from "@/components/auth/mfa-setup";
import { requireRole } from "@/lib/auth/require-role";

export default async function SegurancaPage() {
  await requireRole(["evangelist", "central", "team_member", "unit_admin", "global_admin"]);
  return (
    <main className="mx-auto max-w-md px-4 py-8">
      <h1 className="mb-3 text-xl font-bold">Segurança da conta</h1>
      <MfaSetup />
    </main>
  );
}
