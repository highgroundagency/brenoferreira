"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

export function BenefitRedeem({ benefits }: { benefits: { id: string; title: string }[] }) {
  const router = useRouter();
  const [code, setCode] = useState("");
  const [benefit, setBenefit] = useState(benefits[0]?.id ?? "");
  const [note, setNote] = useState("");
  async function redeem() {
    const { error } = await createClient().rpc("redeem_benefit", {
      p_card_code: code.trim(),
      p_benefit_id: benefit,
      p_note: note || undefined,
    });
    if (error) {
      toast.error(
        error.message.includes("not_active")
          ? "Carteirinha não está ativa."
          : error.message.includes("not_available")
            ? "Benefício indisponível."
            : error.message,
      );
      return;
    }
    toast.success("Benefício registrado.");
    setCode("");
    setNote("");
    router.refresh();
  }
  return (
    <Card>
      <CardContent className="flex flex-wrap items-end gap-2 p-3 text-sm">
        <Input
          placeholder="código da carteirinha"
          value={code}
          onChange={(e) => setCode(e.target.value.toUpperCase())}
          className="w-48 font-mono"
        />
        <Select value={benefit} onChange={(e) => setBenefit(e.target.value)} className="w-64">
          {benefits.map((b) => (
            <option key={b.id} value={b.id}>
              {b.title}
            </option>
          ))}
        </Select>
        <Input placeholder="observação" value={note} onChange={(e) => setNote(e.target.value)} className="w-48" />
        <Button onClick={redeem} disabled={!code || !benefit}>
          Registrar resgate
        </Button>
      </CardContent>
    </Card>
  );
}
