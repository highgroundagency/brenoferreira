import { describe, expect, it } from "vitest";
import { formatBrPhone, phoneVariants, toE164, waIdToE164 } from "@/lib/domain/phone";

describe("phone", () => {
  it("normaliza formatos brasileiros para E.164", () => {
    expect(toE164("(41) 98765-0001")).toBe("+5541987650001");
    expect(toE164("41 9 8765 0001")).toBe("+5541987650001");
    expect(toE164("+55 41 98765-0001")).toBe("+5541987650001");
    expect(toE164("4132650001")).toBe("+554132650001");
  });
  it("rejeita números curtos", () => {
    expect(toE164("1234")).toBeNull();
    expect(toE164("")).toBeNull();
  });
  it("gera variantes com e sem o 9º dígito", () => {
    expect(phoneVariants("+5541987650001")).toEqual(["+5541987650001", "+554187650001"]);
    expect(phoneVariants("+554187650001")).toEqual(["+5541987650001", "+554187650001"]);
    expect(phoneVariants("+12025550123")).toEqual(["+12025550123"]);
  });
  it("máscara de digitação", () => {
    expect(formatBrPhone("41987650001")).toBe("(41) 9 8765-0001");
    expect(formatBrPhone("4132650001")).toBe("(41) 3265-0001");
    expect(formatBrPhone("4")).toBe("(4");
  });
  it("wa_id -> E.164", () => {
    expect(waIdToE164("554187650001")).toBe("+554187650001");
  });
});
