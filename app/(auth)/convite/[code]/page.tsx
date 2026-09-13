import { InviteForm } from "@/components/auth/invite-form";
import { ROLE_LABEL, type Role } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/server";

export default async function InvitePage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = await createClient();
  const { data } = await supabase.rpc("get_invite", { p_code: code });
  const invite = data as { email: string; role: Role; unit_name: string; expires_at: string; accepted: boolean } | null;

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center gap-6 px-4 py-8">
      <div>
        <h1 className="text-2xl font-bold">Convite — Transtornar</h1>
        {invite ? (
          <p className="text-sm text-muted-foreground">
            {invite.unit_name} · {ROLE_LABEL[invite.role]} · {invite.email}
          </p>
        ) : null}
      </div>
      {!invite ? (
        <p className="text-sm text-destructive">Convite inválido ou expirado. Peça um novo link à central.</p>
      ) : invite.accepted ? (
        <p className="text-sm">Este convite já foi usado. Vá para a página de login.</p>
      ) : (
        <InviteForm code={code} email={invite.email} />
      )}
    </main>
  );
}
