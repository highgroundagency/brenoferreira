import { assertEquals } from "jsr:@std/assert@1";
import { classifyMessage, dedupKey } from "../_shared/inbound.ts";

Deno.test("classifica botão de template, botão interativo, texto e mídia", () => {
  assertEquals(classifyMessage({ id: "w1", type: "button", button: { payload: "optin_yes", text: "Quero receber" } }), {
    kind: "button",
    payload: { button_id: "optin_yes", wamid: "w1" },
  });
  assertEquals(
    classifyMessage({
      id: "w2",
      type: "interactive",
      interactive: { type: "button_reply", button_reply: { id: "video_watched", title: "Assisti" } },
    }).payload.button_id,
    "video_watched",
  );
  assertEquals(classifyMessage({ id: "w3", type: "text", text: { body: "sair" } }), {
    kind: "text",
    payload: { text: "sair", wamid: "w3" },
  });
  assertEquals(classifyMessage({ id: "w4", type: "audio" }).kind, "text");
});

Deno.test("dedup_key estável por wamid/tipo/status/timestamp", async () => {
  const a = await dedupKey(["wamid.1", "status", "delivered", "1700000000"]);
  const b = await dedupKey(["wamid.1", "status", "delivered", "1700000000"]);
  const c = await dedupKey(["wamid.1", "status", "read", "1700000001"]);
  assertEquals(a, b);
  assertEquals(a === c, false);
});
