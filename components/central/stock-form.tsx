"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { createClient } from "@/lib/supabase/client";

export function StockForm({ items }: { items: { code: string; name: string }[] }) {
  const router = useRouter();
  const [code, setCode] = useState(items[0]?.code ?? "");
  const [delta, setDelta] = useState(1);
  const [reason, setReason] = useState("donation");
  const [note, setNote] = useState("");
  async function save() {
    const { error } = await createClient().rpc("add_stock", {
      p_item_code: code,
      p_delta: delta,
      p_reason: reason,
      p_note: note || undefined,
    });
    if (error) toast.error(error.message);
    else {
      toast.success("Movimento registrado.");
      router.refresh();
    }
  }
  return (
    <div className="flex flex-wrap items-end gap-2 rounded-md border p-3 text-sm">
      <Select value={code} onChange={(e) => setCode(e.target.value)} className="w-44">
        {items.map((i) => (
          <option key={i.code} value={i.code}>
            {i.name}
          </option>
        ))}
      </Select>
      <Input type="number" value={delta} onChange={(e) => setDelta(Number(e.target.value))} className="w-24" />
      <Select value={reason} onChange={(e) => setReason(e.target.value)} className="w-36">
        <option value="donation">doação</option>
        <option value="adjustment">ajuste</option>
        <option value="return">devolução</option>
      </Select>
      <Input placeholder="observação" value={note} onChange={(e) => setNote(e.target.value)} className="w-56" />
      <Button variant="outline" onClick={save}>
        Registrar
      </Button>
    </div>
  );
}
