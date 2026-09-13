"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

type Pending = { id: string; email: string; role: string; code: string; expires_at: string };

function inviteUrl(code: string) {
  const base = process.env.NEXT_PUBLIC_APP_URL ?? (typeof window !== "undefined" ? window.location.origin : "");
  return `${base}/convite/${code}`;
}

export function InviteForm({ teams, pending }: { teams: { id: string; name: string }[]; pending: Pending[] }) {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [role, setRole] = useState("evangelist");
  const [teamId, setTeamId] = useState("");
  const [busy, setBusy] = useState(false);

  async function create(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("create_invite", {
      p_email: email,
      p_role: role,
      p_team_id: teamId || undefined,
    });
    setBusy(false);
    if (error) {
      toast.error(error.message);
      return;
    }
    const code = (data as { code: string }).code;
    await copy(inviteUrl(code));
    setEmail("");
    router.refresh();
  }

  async function copy(url: string) {
    try {
      await navigator.clipboard.writeText(url);
      toast.success("Link copiado. Envie pelo WhatsApp para a pessoa convidada.");
    } catch {
      window.prompt("Copie o link do convite:", url);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Convidar</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <form onSubmit={create} className="flex flex-wrap items-end gap-2">
          <div className="flex flex-col gap-1">
            <Label htmlFor="inv_email">E-mail</Label>
            <Input
              id="inv_email"
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-64"
            />
          </div>
          <div className="flex flex-col gap-1">
            <Label htmlFor="inv_role">Papel</Label>
            <Select id="inv_role" value={role} onChange={(e) => setRole(e.target.value)}>
              <option value="evangelist">Evangelista</option>
              <option value="central">Central</option>
              <option value="team_member">Membro de time</option>
              <option value="unit_admin">Admin da unidade</option>
            </Select>
          </div>
          {role === "team_member" ? (
            <div className="flex flex-col gap-1">
              <Label htmlFor="inv_team">Time</Label>
              <Select id="inv_team" value={teamId} onChange={(e) => setTeamId(e.target.value)} required>
                <option value="">Escolha</option>
                {teams.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </Select>
            </div>
          ) : null}
          <Button type="submit" disabled={busy}>
            Gerar link
          </Button>
        </form>
        {pending.length ? (
          <div className="flex flex-col gap-1 text-sm">
            <span className="text-xs text-muted-foreground">Convites pendentes (7 dias)</span>
            {pending.map((p) => (
              <div key={p.id} className="flex flex-wrap items-center gap-2">
                <span>
                  {p.email} · {p.role}
                </span>
                <Button size="sm" variant="outline" onClick={() => copy(inviteUrl(p.code))}>
                  copiar link
                </Button>
              </div>
            ))}
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
