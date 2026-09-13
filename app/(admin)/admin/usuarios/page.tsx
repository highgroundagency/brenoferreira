import { InviteForm } from "@/components/admin/invite-form";
import { UserList } from "@/components/admin/user-list";
import { createClient, getProfile } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export default async function UsuariosPage() {
  const supabase = await createClient();
  const profile = await getProfile();
  const [{ data: profiles }, { data: teams }, { data: invites }] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, full_name, role, active, created_at, team_members(team_id, teams(name))")
      .order("created_at"),
    supabase
      .from("teams")
      .select("id, kind, name, active")
      .eq("unit_id", profile?.unit_id ?? "")
      .order("name"),
    supabase
      .from("invites")
      .select("id, email, role, code, expires_at, accepted_at")
      .is("accepted_at", null)
      .order("created_at", { ascending: false }),
  ]);
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-xl font-bold">Usuários e convites</h1>
      <InviteForm
        teams={(teams ?? []).map((t) => ({ id: t.id, name: t.name }))}
        pending={(invites ?? []).map((i) => ({ ...i, expires_at: i.expires_at }))}
      />
      <UserList users={(profiles ?? []) as never} selfId={profile?.id ?? ""} />
    </div>
  );
}
