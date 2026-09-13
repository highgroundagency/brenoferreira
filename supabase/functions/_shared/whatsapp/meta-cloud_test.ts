import { assertEquals } from "jsr:@std/assert@1";
import { buildInteractivePayload, buildTemplatePayload, MetaCloudProvider } from "./meta-cloud.ts";
import { WhatsAppSendError } from "./provider.ts";

Deno.test("template com header de vídeo, variável do corpo e payloads dos quick replies", () => {
  const p = buildTemplatePayload("5541987650001", "transtornar_video1_v1", "pt_BR", {
    bodyParams: ["João"],
    headerVideoLink: "https://cdn/x.mp4",
    buttons: [
      { id: "video_watched", title: "Quero continuar" },
      { id: "stop", title: "Parar" },
    ],
  });
  const c = p.template.components as Record<string, unknown>[];
  assertEquals(c[0].type, "header");
  assertEquals((c[1].parameters as { text: string }[])[0].text, "João");
  assertEquals(c[2].sub_type, "quick_reply");
  assertEquals((c[3].parameters as { payload: string }[])[0].payload, "stop");
});

Deno.test("interativa com vídeo e até 3 botões de 20 caracteres", () => {
  const p = buildInteractivePayload(
    "5541",
    "corpo",
    [{ id: "a", title: "Um título muito longo demais" }],
    "https://cdn/v.mp4",
  );
  assertEquals(p.interactive.header?.type, "video");
  assertEquals(p.interactive.action.buttons[0].reply.title.length, 20);
});

Deno.test("erro da Graph API vira WhatsAppSendError com código e retryable", async () => {
  const fetchImpl = (async () =>
    new Response(JSON.stringify({ error: { code: 131026, message: "not a whatsapp user" } }), {
      status: 400,
    })) as unknown as typeof fetch;
  const wa = new MetaCloudProvider({ token: "t", phoneNumberId: "1", fetchImpl });
  try {
    await wa.sendText("5541", "oi");
    throw new Error("deveria falhar");
  } catch (e) {
    const err = e as WhatsAppSendError;
    assertEquals(err instanceof WhatsAppSendError, true);
    assertEquals(err.code, 131026);
    assertEquals(err.retryable, false);
  }
});

Deno.test("sucesso devolve wamid e wa_id canônico", async () => {
  const fetchImpl = (async () =>
    new Response(JSON.stringify({ messages: [{ id: "wamid.X" }], contacts: [{ wa_id: "554187650001" }] }), {
      status: 200,
    })) as unknown as typeof fetch;
  const wa = new MetaCloudProvider({ token: "t", phoneNumberId: "1", fetchImpl });
  const r = await wa.sendText("5541987650001", "oi");
  assertEquals(r.providerMessageId, "wamid.X");
  assertEquals(r.waId, "554187650001");
});
