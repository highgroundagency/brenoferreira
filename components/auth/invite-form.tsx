"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

export function InviteForm({ code, email }: { code: string; email: string }) {
  const router = useRouter();
  const [fullName, setFullName] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (password.length < 8) {
      toast.error("A senha precisa ter pelo menos 8 caracteres.");
      return;
    }
    setLoading(true);
    const supabase = createClient();
    let { error } = await supabase.auth.signUp({ email, password, options: { data: { full_name: fullName.trim() } } });
    if (error?.message?.toLowerCase().includes("already registered")) {
      ({ error } = await supabase.auth.signInWithPassword({ email, password }));
    }
    if (error) {
      setLoading(false);
      toast.error(error.message);
      return;
    }
    const { error: rpcError } = await supabase.rpc("accept_invite", { p_code: code });
    setLoading(false);
    if (rpcError) {
      toast.error(
        rpcError.message.includes("mismatch")
          ? "Este convite é para outro e-mail."
          : "Não foi possível aceitar o convite.",
      );
      return;
    }
    toast.success("Acesso criado! Adicione o app à tela inicial.");
    router.replace("/");
    router.refresh();
  }

  return (
    <form onSubmit={onSubmit} className="flex flex-col gap-4">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="full_name">Seu nome</Label>
        <Input
          id="full_name"
          autoComplete="name"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          required
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="password">Crie uma senha</Label>
        <Input
          id="password"
          type="password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={8}
        />
      </div>
      <p className="text-xs text-muted-foreground">
        Ao continuar você aceita o termo do voluntário: os dados das pessoas cadastradas são sensíveis e só podem ser
        usados para o acompanhamento pelo Transtornar.
      </p>
      <Button type="submit" size="lg" disabled={loading}>
        {loading ? "Criando…" : "Criar acesso"}
      </Button>
    </form>
  );
}
