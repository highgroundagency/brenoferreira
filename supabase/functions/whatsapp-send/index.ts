// Worker de envio: chamado a cada minuto pelo pg_cron (Authorization: Bearer EDGE_SHARED_SECRET).
// Lê message_log.status='queued' com scheduled_for <= now(), revalida consentimento/estágio e envia pela Cloud API.
import { hasValidBearer } from "../_shared/auth.ts";
import { handleNoWhatsApp, isNoWhatsAppCode } from "../_shared/failures.ts";
import { e164ToWa } from "../_shared/phone.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { MetaCloudProvider } from "../_shared/whatsapp/meta-cloud.ts";
import { type TemplateButton, WhatsAppSendError } from "../_shared/whatsapp/provider.ts";

type Msg = {
  id: string;
  unit_id: string;
  person_id: string | null;
  to_phone_e164: string | null;
  kind: "template" | "interactive" | "text" | "media";
  template_name: string | null;
  content_asset_id: string | null;
  payload: Record<string, unknown>;
  attempts: number;
};

const FIRST_CONTACT_TEMPLATES = new Set(["transtornar_video1_v1", "transtornar_optin_v1"]);

export async function processUnit(
  supabase: ReturnType<typeof serviceClient>,
  unit: { id: string; whatsapp_phone_number_id: string; whatsapp_token_secret_name: string },
  provider?: MetaCloudProvider,
) {
  const token = Deno.env.get(unit.whatsapp_token_secret_name || "WHATSAPP_ACCESS_TOKEN");
  if (!token && !provider) return { unit: unit.id, skipped: "no_token" };
  const wa =
    provider ??
    new MetaCloudProvider({
      token: token as string,
      phoneNumberId: unit.whatsapp_phone_number_id,
      apiVersion: Deno.env.get("WHATSAPP_API_VERSION") ?? undefined,
    });

  const { data: queue } = await supabase
    .from("message_log")
    .select("id, unit_id, person_id, to_phone_e164, kind, template_name, content_asset_id, payload, attempts")
    .eq("unit_id", unit.id)
    .eq("status", "queued")
    .lte("scheduled_for", new Date().toISOString())
    .order("scheduled_for")
    .limit(50);
  const stats = { sent: 0, failed: 0, skipped: 0 };

  for (const m of (queue ?? []) as Msg[]) {
    // trava otimista
    const { data: locked } = await supabase
      .from("message_log")
      .update({ status: "sending" })
      .eq("id", m.id)
      .eq("status", "queued")
      .select("id");
    if (!locked?.length) continue;

    const skip = async (reason: string) => {
      await supabase.from("message_log").update({ status: "skipped", skip_reason: reason }).eq("id", m.id);
      stats.skipped++;
    };

    if (!m.to_phone_e164) {
      await skip("no_phone");
      continue;
    }
    if (m.person_id) {
      const { data: person } = await supabase
        .from("people")
        .select("stage, review_status")
        .eq("id", m.person_id)
        .single();
      if (
        !person ||
        ["opted_out", "anonymized", "paused"].includes(person.stage) ||
        person.review_status === "merged"
      ) {
        await skip(`stage_${person?.stage ?? "missing"}`);
        continue;
      }
      const { data: consent } = await supabase
        .from("consents")
        .select("id")
        .eq("person_id", m.person_id)
        .eq("purpose", "whatsapp_contact")
        .eq("granted", true)
        .is("revoked_at", null)
        .limit(1);
      if (!consent?.length) {
        await skip("no_consent");
        continue;
      }
    }

    try {
      const to = e164ToWa(m.to_phone_e164);
      let result: { providerMessageId: string; waId?: string };
      if (m.kind === "template" && m.template_name) {
        const { data: tpl } = await supabase
          .from("message_templates")
          .select("language, buttons, status")
          .eq("name", m.template_name)
          .or(`unit_id.eq.${m.unit_id},unit_id.is.null`)
          .order("unit_id", { nullsFirst: false })
          .limit(1)
          .maybeSingle();
        const buttons = ((tpl?.buttons as TemplateButton[] | null) ?? []) as TemplateButton[];
        let headerVideoLink: string | undefined;
        if (m.template_name === "transtornar_video1_v1") {
          const { data: asset } = await supabase
            .from("content_assets")
            .select("public_url")
            .eq("key", "video_1")
            .eq("active", true)
            .or(`unit_id.eq.${m.unit_id},unit_id.is.null`)
            .limit(1)
            .maybeSingle();
          headerVideoLink = asset?.public_url ?? undefined;
          if (!headerVideoLink) {
            await skip("no_video_asset");
            continue;
          }
        }
        result = await wa.sendTemplate(to, m.template_name, tpl?.language ?? "pt_BR", {
          bodyParams: [String(m.payload.first_name ?? "")],
          headerVideoLink,
          buttons,
        });
      } else if (m.kind === "media") {
        const { data: asset } = await supabase
          .from("content_assets")
          .select("public_url, title")
          .eq("id", m.content_asset_id as string)
          .single();
        if (!asset) {
          await skip("no_video_asset");
          continue;
        }
        const buttons = ((m.payload.buttons as TemplateButton[] | undefined) ?? [
          { id: "video_watched", title: "Assisti até o final" },
        ]) as TemplateButton[];
        result = await wa.sendVideoWithButtons(
          to,
          asset.public_url,
          String(m.payload.text ?? "Aqui está o vídeo que preparamos para você. Para parar, responda SAIR."),
          buttons,
        );
      } else if (m.kind === "interactive") {
        result = await wa.sendButtons(to, String(m.payload.text ?? ""), (m.payload.buttons as TemplateButton[]) ?? []);
      } else {
        result = await wa.sendText(to, String(m.payload.text ?? ""));
      }
      await supabase
        .from("message_log")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          provider_message_id: result.providerMessageId || null,
          attempts: m.attempts + 1,
        })
        .eq("id", m.id);
      if (m.person_id) {
        if (result.waId)
          await supabase
            .from("people_contacts")
            .update({ wa_id: result.waId })
            .eq("person_id", m.person_id)
            .is("wa_id", null);
        if (m.kind === "template" && m.template_name && FIRST_CONTACT_TEMPLATES.has(m.template_name)) {
          await supabase
            .from("people")
            .update({ first_contact_sent_at: new Date().toISOString() })
            .eq("id", m.person_id)
            .is("first_contact_sent_at", null);
        }
        await supabase.from("person_events").insert({
          unit_id: m.unit_id,
          person_id: m.person_id,
          event_type: "message_sent",
          payload: { message_id: m.id, template: m.template_name, kind: m.kind },
        });
      }
      stats.sent++;
    } catch (err) {
      const e = err as WhatsAppSendError;
      const retry = err instanceof WhatsAppSendError ? e.retryable : true;
      if (retry && m.attempts + 1 < 5) {
        await supabase
          .from("message_log")
          .update({
            status: "queued",
            attempts: m.attempts + 1,
            error_code: String(e.code ?? ""),
            error_message: String(e.message ?? err).slice(0, 500),
            scheduled_for: new Date(Date.now() + 5 * 60_000).toISOString(),
          })
          .eq("id", m.id);
      } else {
        await supabase
          .from("message_log")
          .update({
            status: "failed",
            attempts: m.attempts + 1,
            error_code: String(e.code ?? ""),
            error_message: String(e.message ?? err).slice(0, 500),
          })
          .eq("id", m.id);
        if (isNoWhatsAppCode(e.code)) await handleNoWhatsApp(supabase, m.unit_id, m.person_id);
      }
      stats.failed++;
    }
  }
  return { unit: unit.id, ...stats };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  if (!hasValidBearer(req, Deno.env.get("EDGE_SHARED_SECRET"))) return new Response("unauthorized", { status: 401 });
  const supabase = serviceClient();
  const { data: units } = await supabase
    .from("units")
    .select("id, whatsapp_phone_number_id, whatsapp_token_secret_name")
    .eq("active", true)
    .not("whatsapp_phone_number_id", "is", null);
  const results = [];
  for (const u of units ?? [])
    results.push(
      await processUnit(
        supabase,
        u as { id: string; whatsapp_phone_number_id: string; whatsapp_token_secret_name: string },
      ),
    );
  return Response.json({ ok: true, results });
});
