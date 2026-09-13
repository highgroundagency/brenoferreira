"use client";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";

/** MFA por app autenticador (TOTP) para quem lê dados sensíveis. Opcional na Fase 1; recomendado para central/admin. */
export function MfaSetup() {
  const supabase = createClient();
  const [factors, setFactors] = useState<{ id: string; friendly_name?: string; status: string }[]>([]);
  const [enroll, setEnroll] = useState<{ id: string; qr: string; secret: string } | null>(null);
  const [code, setCode] = useState("");

  async function load() {
    const { data } = await supabase.auth.mfa.listFactors();
    setFactors((data?.totp ?? []).map((f) => ({ id: f.id, friendly_name: f.friendly_name, status: f.status })));
  }
  // biome-ignore lint/correctness/useExhaustiveDependencies: carga inicial
  useEffect(() => {
    load();
  }, []);

  async function start() {
    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: "Transtornar" });
    if (error || !data) return toast.error(error?.message ?? "erro");
    setEnroll({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
  }
  async function verify() {
    if (!enroll) return;
    const ch = await supabase.auth.mfa.challenge({ factorId: enroll.id });
    if (ch.error) return toast.error(ch.error.message);
    const v = await supabase.auth.mfa.verify({ factorId: enroll.id, challengeId: ch.data.id, code });
    if (v.error) return toast.error("Código inválido.");
    toast.success("MFA ativado.");
    setEnroll(null);
    setCode("");
    load();
  }
  async function remove(id: string) {
    const { error } = await supabase.auth.mfa.unenroll({ factorId: id });
    if (error) toast.error(error.message);
    else load();
  }
  return (
    <div className="flex flex-col gap-3 text-sm">
      {factors.map((f) => (
        <div key={f.id} className="flex items-center justify-between rounded-md border p-2">
          <span>
            {f.friendly_name ?? "autenticador"} — {f.status}
          </span>
          <Button size="sm" variant="ghost" onClick={() => remove(f.id)}>
            remover
          </Button>
        </div>
      ))}
      {enroll ? (
        <div className="flex flex-col gap-2 rounded-md border p-3">
          {/* biome-ignore lint/performance/noImgElement: QR inline em SVG data URI */}
          <img src={enroll.qr} alt="QR code do autenticador" className="h-40 w-40" />
          <span className="text-xs text-muted-foreground">Chave manual: {enroll.secret}</span>
          <Input
            placeholder="código de 6 dígitos"
            inputMode="numeric"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            className="w-48"
          />
          <Button onClick={verify} disabled={code.length < 6}>
            Confirmar
          </Button>
        </div>
      ) : (
        <Button variant="outline" onClick={start}>
          Ativar autenticador (TOTP)
        </Button>
      )}
    </div>
  );
}
