import { describe, expect, it } from "vitest";
import { canTransition } from "@/lib/domain/referral-state";

describe("referral-state", () => {
  it("espelha as transições do banco", () => {
    expect(canTransition("new", "triaged")).toBe(true);
    expect(canTransition("new", "done")).toBe(false);
    expect(canTransition("triaged", "done")).toBe(true);
    expect(canTransition("in_progress", "waiting")).toBe(true);
    expect(canTransition("waiting", "in_progress")).toBe(true);
    expect(canTransition("done", "in_progress")).toBe(false);
    expect(canTransition("cancelled", "new")).toBe(false);
  });
});
