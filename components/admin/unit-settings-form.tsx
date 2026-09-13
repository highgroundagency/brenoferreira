"use client";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { createClient } from "@/lib/supabase/client";

type Settings = {
  first_contact_mode?: string;
  first_contact_delay_minutes?: number;
  quiet_hours?: { start: string; end: string };
  basic_food_months?: number;
  basic_food_frequency_days?: number;
  monthly_message_cap?: number;
  same_day_cutoff?: string;
  central_hours?: { weekdays: string };
};
type Consent = { version: string; base: string; social_assistance: string; terms_url: string };

export function UnitSettingsForm({
  unitId,
  unit,
  consent,
}: {
  unitId: string;
  unit: {
    name: string;
    whatsapp_phone_number_id: string | null;
    whatsapp_waba_id: string | null;
    whatsapp_display_name: string | null;
    timezone: string;
    settings: Settings;
  };
  consent: Consent | null;
}) {
  const router = useRouter();
  const [s, setS] = useState<Settings>(unit.settings);
  const [wa, setWa] = useState({
    phone_number_id: unit.whatsapp_phone_number_id ?? "",
    waba_id: unit.whatsapp_waba_id ?? "",
    display_name: unit.whatsapp_display_name ?? "",
    timezone: unit.timezone,
  });
  const [c, setC] = useState<Consent>(
    consent ?? { version: "v1", base: "", social_assistance: "", terms_url: "/termos" },
  );
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    const supabase = createClient();
    const u = await supabase
      .from("units")
      .update({
        settings: s as never,
        whatsapp_phone_number_id: wa.phone_number_id || null,
        whatsapp_waba_id: wa.waba_id || null,
        whatsapp_display_name: wa.display_name || null,
        timezone: wa.timezone,
      })
      .eq("id", unitId);
    const nextVersion =
      consent && (consent.base !== c.base || consent.social_assistance !== c.social_assistance)
        ? bumpVersion(consent.version)
        : c.version;
    const a = await supabase
      .from("app_settings")
      .upsert(
        { unit_id: unitId, key: "consent_text_v1", value: { ...c, version: nextVersion } as never, is_public: true },
        { onConflict: "unit_id,key" },
      );
    setBusy(false);
    if (u.error || a.error) toast.error(u.error?.message ?? a.error?.message ?? "erro");
    else {
      toast.success(nextVersion !== c.version ? `Salvo. Texto de consentimento agora é ${nextVersion}.` : "Salvo.");
      router.refresh();
    }
  }
  return (
    <div className="flex flex-col gap-4 text-sm">
      <section className="grid gap-2 sm:grid-cols-2">
        <div className="flex flex-col gap-1">
          <Label>Primeiro contato (número da própria pessoa)</Label>
          <Select
            value={s.first_contact_mode ?? "video_first"}
            onChange={(e) => setS({ ...s, first_contact_mode: e.target.value })}
          >
            <option value="video_first">vídeo 1 direto (video_first)</option>
            <option value="optin_first">mensagem neutra antes (optin_first)</option>
          </Select>
        </div>
        <div className="flex flex-col gap-1">
          <Label>Atraso do 1º contato (min)</Label>
          <Input
            type="number"
            value={s.first_contact_delay_minutes ?? 10}
            onChange={(e) => setS({ ...s, first_contact_delay_minutes: Number(e.target.value) })}
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Silêncio: início</Label>
          <Input
            value={s.quiet_hours?.start ?? "21:00"}
            onChange={(e) => setS({ ...s, quiet_hours: { start: e.target.value, end: s.quiet_hours?.end ?? "08:00" } })}
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Silêncio: fim</Label>
          <Input
            value={s.quiet_hours?.end ?? "08:00"}
            onChange={(e) =>
              setS({ ...s, quiet_hours: { start: s.quiet_hours?.start ?? "21:00", end: e.target.value } })
            }
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Cesta básica: meses</Label>
          <Input
            type="number"
            value={s.basic_food_months ?? 3}
            onChange={(e) => setS({ ...s, basic_food_months: Number(e.target.value) })}
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Cesta básica: a cada N dias</Label>
          <Input
            type="number"
            value={s.basic_food_frequency_days ?? 30}
            onChange={(e) => setS({ ...s, basic_food_frequency_days: Number(e.target.value) })}
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Teto mensal de mensagens</Label>
          <Input
            type="number"
            value={s.monthly_message_cap ?? 5000}
            onChange={(e) => setS({ ...s, monthly_message_cap: Number(e.target.value) })}
          />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Corte para entrega no mesmo dia</Label>
          <Input
            value={s.same_day_cutoff ?? "14:00"}
            onChange={(e) => setS({ ...s, same_day_cutoff: e.target.value })}
          />
        </div>
      </section>
      <section className="grid gap-2 sm:grid-cols-2">
        <div className="flex flex-col gap-1">
          <Label>WhatsApp phone_number_id</Label>
          <Input value={wa.phone_number_id} onChange={(e) => setWa({ ...wa, phone_number_id: e.target.value })} />
        </div>
        <div className="flex flex-col gap-1">
          <Label>WABA id</Label>
          <Input value={wa.waba_id} onChange={(e) => setWa({ ...wa, waba_id: e.target.value })} />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Nome exibido</Label>
          <Input value={wa.display_name} onChange={(e) => setWa({ ...wa, display_name: e.target.value })} />
        </div>
        <div className="flex flex-col gap-1">
          <Label>Fuso horário</Label>
          <Input value={wa.timezone} onChange={(e) => setWa({ ...wa, timezone: e.target.value })} />
        </div>
      </section>
      <section className="flex flex-col gap-2">
        <Label>Roteiro de consentimento (versão {c.version}; alterar o texto gera nova versão)</Label>
        <Textarea rows={3} value={c.base} onChange={(e) => setC({ ...c, base: e.target.value })} />
        <Textarea
          rows={2}
          value={c.social_assistance}
          onChange={(e) => setC({ ...c, social_assistance: e.target.value })}
        />
        <Input value={c.terms_url} onChange={(e) => setC({ ...c, terms_url: e.target.value })} />
      </section>
      <Button onClick={save} disabled={busy}>
        Salvar configurações
      </Button>
    </div>
  );
}

function bumpVersion(v: string) {
  const n = Number.parseInt(v.replace(/\D/g, ""), 10);
  return `v${Number.isFinite(n) ? n + 1 : 2}`;
}
