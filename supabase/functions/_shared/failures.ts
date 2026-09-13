import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { NO_WHATSAPP_CODE } from "./whatsapp/provider.ts";

/** Número sem WhatsApp (131026): marca o contato, abre contato humano (follow_up) e registra a tentativa. */
export async function handleNoWhatsApp(supabase: SupabaseClient, unitId: string, personId: string | null) {
  if (!personId) return;
  await supabase.from("people_contacts").update({ whatsapp_valid: false }).eq("person_id", personId);
  const { data: existing } = await supabase
    .from("referrals")
    .select("id")
    .eq("person_id", personId)
    .eq("referral_type", "follow_up")
    .not("status", "in", "(done,cancelled)")
    .limit(1);
  if (!existing?.length) {
    const { data: team } = await supabase
      .from("teams")
      .select("id, kind")
      .eq("unit_id", unitId)
      .in("kind", ["follow_up", "central"])
      .eq("active", true);
    const followUp = team?.find((t) => t.kind === "follow_up") ?? team?.find((t) => t.kind === "central");
    if (followUp) {
      await supabase.from("referrals").insert({
        unit_id: unitId,
        person_id: personId,
        team_id: followUp.id,
        referral_type: "follow_up",
        reason: "número sem WhatsApp: ligar ou visitar",
        priority: 2,
      });
    }
  }
  await supabase.from("person_events").insert({
    unit_id: unitId,
    person_id: personId,
    event_type: "contact_attempt",
    payload: { channel: "whatsapp", result: "no_whatsapp", code: NO_WHATSAPP_CODE },
  });
}

export function isNoWhatsAppCode(code: number | string | null | undefined): boolean {
  return Number(code) === NO_WHATSAPP_CODE;
}
