"use client";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ROLE_LABEL, type Role } from "@/lib/auth/roles";
import { createClient } from "@/lib/supabase/client";

type User = {
  id: string;
  full_name: string;
  role: Role;
  active: boolean;
  team_members: { team_id: string; teams: { name: string } | null }[];
};

export function UserList({ users, selfId }: { users: User[]; selfId: string }) {
  const router = useRouter();
  async function toggle(u: User) {
    const supabase = createClient();
    const { error } = await supabase.from("profiles").update({ active: !u.active }).eq("id", u.id);
    if (error) toast.error(error.message);
    else {
      toast.success(u.active ? "Acesso desativado (efeito imediato)." : "Acesso reativado.");
      router.refresh();
    }
  }
  return (
    <Card>
      <CardHeader>
        <CardTitle>Usuários</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2 text-sm">
        {users.map((u) => (
          <div key={u.id} className="flex flex-wrap items-center justify-between gap-2 border-b py-1 last:border-0">
            <div className="flex flex-wrap items-center gap-2">
              <span className={u.active ? "font-medium" : "text-muted-foreground line-through"}>{u.full_name}</span>
              <Badge variant="secondary">{ROLE_LABEL[u.role]}</Badge>
              {u.team_members.map((tm) => (
                <Badge key={tm.team_id} variant="outline">
                  {tm.teams?.name}
                </Badge>
              ))}
            </div>
            {u.id !== selfId ? (
              <Button size="sm" variant="ghost" onClick={() => toggle(u)}>
                {u.active ? "Desativar" : "Reativar"}
              </Button>
            ) : null}
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
