import { assertEquals } from "jsr:@std/assert@1";
import { e164ToWa, phoneVariants, waIdToE164 } from "./phone.ts";

Deno.test("wa_id de 12 dígitos casa com E.164 de 13 (9º dígito)", () => {
  assertEquals(waIdToE164("554187650001"), "+554187650001");
  assertEquals(phoneVariants("+554187650001"), ["+5541987650001", "+554187650001"]);
  assertEquals(phoneVariants("+5541987650001").includes("+554187650001"), true);
  assertEquals(e164ToWa("+5541987650001"), "5541987650001");
});
