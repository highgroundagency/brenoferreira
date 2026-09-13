// Webhook da Meta: GET de verificação; POST com assinatura X-Hub-Signature-256.
// Cada evento vira uma linha em wa_inbound_events (dedup_key) e só é processado se foi inserido agora.
import { verifyMetaSignature } from "../_shared/auth.ts";
import { handleNoWhatsApp, isNoWhatsAppCode } from "../_shared/failures.ts";
import { classifyMessage, dedupKey } from "../_shared/inbound.ts";
import { waIdToE164 } from "../_shared/phone.ts";
import { serviceClient } from "../_shared/supabase.ts";

type Change = { field: string; value: Record<string, unknown> };

async function processChange(supabase: ReturnType<typeof serviceClient>, change: Change) {
  const v = change.value;
  if (change.field === "messages") {
    const phoneNumberId = (v.metadata as { phone_number_id?: string })?.phone_number_id ?? "";
    const { data: unit } = await supabase
      .from("units")
      .select("id")
      .eq("whatsapp_phone_number_id", phoneNumberId)
      .maybeSingle();
    for (const msg of (v.messages as Record<string, unknown>[] | undefined) ?? []) {
      const key = await dedupKey([msg.id as string, "message", "", msg.timestamp as string]);
      const { data: ins } = await supabase
        .from("wa_inbound_events")
        .upsert(
          {
            unit_id: unit?.id ?? null,
            dedup_key: key,
            wamid: msg.id as string,
            phone_number_id: phoneNumberId,
            wa_id: msg.from as string,
            event_type: "message",
            raw: msg,
          },
          { onConflict: "dedup_key", ignoreDuplicates: true },
        )
        .select("id");
      if (!ins?.length) continue;
      if (!unit) {
        await supabase
          .from("wa_inbound_events")
          .update({ processed_at: new Date().toISOString(), error: "unknown_phone_number_id" })
          .eq("dedup_key", key);
        continue;
      }
      const { kind, payload } = classifyMessage(msg);
      const { data, error } = await supabase.rpc("handle_inbound", {
        p_unit_id: unit.id,
        p_wa_id: msg.from as string,
        p_phone_e164: waIdToE164(msg.from as string),
        p_kind: kind,
        p_payload: payload,
      });
      await supabase
        .from("wa_inbound_events")
        .update({
          processed_at: new Date().toISOString(),
          error: error?.message ?? null,
          raw: { ...msg, result: data ?? null },
        })
        .eq("dedup_key", key);
    }
    for (const st of (v.statuses as Record<string, unknown>[] | undefined) ?? []) {
      const key = await dedupKey([st.id as string, "status", st.status as string, st.timestamp as string]);
      const { data: ins } = await supabase
        .from("wa_inbound_events")
        .upsert(
          {
            unit_id: unit?.id ?? null,
            dedup_key: key,
            wamid: st.id as string,
            phone_number_id: phoneNumberId,
            wa_id: st.recipient_id as string,
            event_type: "status",
            raw: st,
          },
          { onConflict: "dedup_key", ignoreDuplicates: true },
        )
        .select("id");
      if (!ins?.length) continue;
      const status = st.status as string; // sent | delivered | read | failed
      const ts = new Date(Number(st.timestamp) * 1000).toISOString();
      const patch: Record<string, unknown> = {};
      if (status === "sent") patch.sent_at = ts;
      if (status === "delivered") patch.delivered_at = ts;
      if (status === "read") patch.read_at = ts;
      if (["sent", "delivered", "read", "failed"].includes(status)) {
        const { data: current } = await supabase
          .from("message_log")
          .select("id, unit_id, person_id, status")
          .eq("provider_message_id", st.id as string)
          .maybeSingle();
        if (current) {
          const rank: Record<string, number> = { queued: 0, sending: 1, sent: 2, delivered: 3, read: 4, failed: 5 };
          if ((rank[status] ?? 0) >= (rank[current.status] ?? 0) || status === "failed") patch.status = status;
          if (status === "failed") {
            const err = ((st.errors as { code?: number; title?: string; message?: string }[] | undefined) ?? [])[0];
            patch.error_code = String(err?.code ?? "");
            patch.error_message = String(err?.message ?? err?.title ?? "").slice(0, 500);
            if (isNoWhatsAppCode(err?.code)) await handleNoWhatsApp(supabase, current.unit_id, current.person_id);
          }
          await supabase.from("message_log").update(patch).eq("id", current.id);
        }
      }
      await supabase.from("wa_inbound_events").update({ processed_at: new Date().toISOString() }).eq("dedup_key", key);
    }
  } else if (change.field === "message_template_status_update" || change.field === "template_category_update") {
    const name = v.message_template_name as string;
    const language = (v.message_template_language as string) ?? "pt_BR";
    const key = await dedupKey([
      change.field,
      name,
      language,
      v.event as string,
      v.new_category as string,
      Date.now().toString().slice(0, 7),
    ]);
    await supabase
      .from("wa_inbound_events")
      .upsert(
        { dedup_key: key, event_type: "template_update", raw: v, processed_at: new Date().toISOString() },
        { onConflict: "dedup_key", ignoreDuplicates: true },
      );
    const patch: Record<string, unknown> = { meta_template_id: String(v.message_template_id ?? "") || undefined };
    if (change.field === "message_template_status_update") {
      const map: Record<string, string> = {
        APPROVED: "approved",
        REJECTED: "rejected",
        PAUSED: "paused",
        DISABLED: "disabled",
        PENDING: "pending",
      };
      patch.status = map[String(v.event)] ?? "pending";
    } else {
      patch.category = String(v.new_category ?? "MARKETING");
    }
    await supabase.from("message_templates").update(patch).eq("name", name).eq("language", language);
  } else {
    const key = await dedupKey([change.field, JSON.stringify(v).slice(0, 200), Date.now().toString().slice(0, 8)]);
    await supabase.from("wa_inbound_events").upsert(
      {
        dedup_key: key,
        event_type: change.field === "phone_number_quality_update" ? "quality_update" : "unknown",
        raw: v,
        processed_at: new Date().toISOString(),
      },
      { onConflict: "dedup_key", ignoreDuplicates: true },
    );
  }
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge") ?? "";
    if (mode === "subscribe" && token && token === Deno.env.get("WHATSAPP_VERIFY_TOKEN"))
      return new Response(challenge, { status: 200 });
    return new Response("forbidden", { status: 403 });
  }
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const raw = await req.text();
  if (!(await verifyMetaSignature(raw, req.headers.get("x-hub-signature-256"), Deno.env.get("WHATSAPP_APP_SECRET"))))
    return new Response("invalid signature", { status: 401 });
  let body: { entry?: { changes?: Change[] }[] };
  try {
    body = JSON.parse(raw);
  } catch {
    return new Response("bad json", { status: 400 });
  }
  const supabase = serviceClient();
  for (const entry of body.entry ?? []) {
    for (const change of entry.changes ?? []) {
      try {
        await processChange(supabase, change);
      } catch (err) {
        console.error("webhook change failed", change.field, err);
      }
    }
  }
  return Response.json({ ok: true });
});
