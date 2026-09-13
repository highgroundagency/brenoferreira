import { assertEquals } from "jsr:@std/assert@1";
import { hasValidBearer, hmacSha256Hex, verifyMetaSignature } from "./auth.ts";

Deno.test("bearer compartilhado", () => {
  const ok = new Request("http://x", { headers: { authorization: "Bearer s3cret" } });
  assertEquals(hasValidBearer(ok, "s3cret"), true);
  assertEquals(hasValidBearer(ok, "other"), false);
  assertEquals(hasValidBearer(new Request("http://x"), "s3cret"), false);
  assertEquals(hasValidBearer(ok, undefined), false);
});

Deno.test("assinatura da Meta (X-Hub-Signature-256)", async () => {
  const body = '{"entry":[]}';
  const sig = await hmacSha256Hex("app-secret", body);
  assertEquals(await verifyMetaSignature(body, `sha256=${sig}`, "app-secret"), true);
  assertEquals(await verifyMetaSignature(body, `sha256=${sig}`, "wrong"), false);
  assertEquals(await verifyMetaSignature(`${body} `, `sha256=${sig}`, "app-secret"), false);
  assertEquals(await verifyMetaSignature(body, null, "app-secret"), false);
});
